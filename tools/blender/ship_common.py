"""
Frontier Habitat 3.1 - ART-B ship library (V3_1_DESIGN.md section 6.2). Blender 5.2, --background only.

Uses the geometry builder, AO bake and GLB reader of tools/blender/ext_common.py READ-ONLY (that file belongs to
ART-HAB now); everything ship-specific lives here and in tools/blender/ship_<kind>.py.

Ship file contract (assets/models/ship_<kind>.glb):
  Hull            the fixed body (all static detail)
  Leg_<name>      landing legs. Rest pose = deployed. Origin on the hinge; the hinge axis is the node's local X.
  Ramp            boarding ramp. Rest pose = open (foot on the ground). Origin on the hinge, axis local X.
  Door_<name>     doors / hatches. Rest pose = open. Origin on the hinge, axis local X.
  Thruster_<name> empties at nozzle exits; local +X = the flame / dust direction.
  Anchor_<name>   empties: Anchor_Ramp (ramp foot, walk-off point), Anchor_Cargo (trader), Anchor_Door (crew door foot).
  Every animated node carries glTF extras {"stow_deg": d}: rotate the node about its local X axis by d * s degrees,
  s = 0 landed / open, s = 1 flight / folded / closed. Godot keeps the extras as node metadata "extras".
Origin: centre of the landing footprint, z = 0 at the soles of the foot pads. Front = +X.
Materials (8): Palette (white; the paint colour is in COLOR_0 together with the baked AO, as ART-HAB does; metal
parts merged in since round 11), Accent (kind colour), Window (bridge), CabinWindow (passenger windows, dimmer),
Light, Plasma (nozzle glow), LightRed, LightGreen.
"""
import bpy
import os
import sys
import json
import math
import time
from math import sin, cos, pi, radians, degrees, sqrt, atan2, copysign

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402  (read-only use)
from ext_common import Part, Anchor, T, RX, RY, RZ, S, lerp, smoothstep   # noqa: E402,F401
from mathutils import Vector, Matrix                       # noqa: E402

ROOT = C.ROOT
MODEL_DIR = C.MODEL_DIR
ART_DIR = os.path.join(ROOT, "art", "ships")
REPORT_JSON = os.path.join(ART_DIR, "ship_report.json")

MAX_TRIS = 12000
MAX_MATS = 8
MAX_R = 7.5            # plan radius: inside the painted ring of the pad (agreed with ART-HAB)
MAX_H = 18.0

KIND_ACCENT = {         # the Accent colour per ship kind (sRGB)
    "trader": "#e07a3a", "shuttle": "#f2c14e", "liner": "#f08fc0", "medical": "#e04b5a",
    "science": "#7c8cff", "courier": "#d8a93b",
}
NAMED = ("Accent", "Window", "Light", "Plasma", "Glass", "Neon")    # kept as their own material
PALETTE_SPEC = {"Palette": dict(color="#ffffff", rough=0.62), "PaletteMetal": dict(color="#ffffff", metal=0.6, rough=0.42)}


# ======================================================================================
# monotone cubic + lofted hull (generalised from the Meridian hull)
# ======================================================================================
class Pchip:
    def __init__(self, xs, ys):
        self.xs, self.ys = list(xs), list(ys)
        n = len(xs)
        h = [xs[i + 1] - xs[i] for i in range(n - 1)]
        d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
        m = [0.0] * n
        m[0], m[-1] = d[0], d[-1]
        for i in range(1, n - 1):
            if d[i - 1] * d[i] <= 0:
                m[i] = 0.0
            else:
                w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        self.m, self.h = m, h

    def __call__(self, x):
        xs = self.xs
        if x <= xs[0]:
            return self.ys[0]
        if x >= xs[-1]:
            return self.ys[-1]
        i = 0
        while xs[i + 1] < x:
            i += 1
        h = self.h[i]
        t = (x - xs[i]) / h
        h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
        h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
        return h00 * self.ys[i] + h10 * h * self.m[i] + h01 * self.ys[i + 1] + h11 * h * self.m[i + 1]


class LoftHull:
    """stations: [(x, half_width, z_top, z_bottom, z_chine), ...] ; superellipse sections, t in degrees:
    0 = +Y chine, 90 = top, 180 = -Y chine, 270 = bottom."""

    def __init__(self, stations, n_top=2.4, n_bot=4.0, y0=0.0):
        xs = [s[0] for s in stations]
        self.x0, self.x1 = xs[0], xs[-1]
        self.fw = Pchip(xs, [s[1] for s in stations])
        self.ft = Pchip(xs, [s[2] for s in stations])
        self.fb = Pchip(xs, [s[3] for s in stations])
        self.fc = Pchip(xs, [s[4] for s in stations])
        self.nt, self.nb, self.y0 = n_top, n_bot, y0

    def sec(self, x):
        return self.fw(x), self.ft(x), self.fb(x), self.fc(x)

    def pt(self, x, t, off=0.0):
        w, zt, zb, zc = self.sec(x)
        a = radians(t)
        c, s = cos(a), sin(a)
        if s >= 0:
            e, h = 2.0 / self.nt, zt - zc
        else:
            e, h = 2.0 / self.nb, zc - zb
        p = Vector((x, self.y0 + w * copysign(abs(c) ** e, c), zc + copysign(abs(s) ** e, s) * h))
        if off:
            p = p + self.nrm(x, t) * off
        return p

    def nrm(self, x, t):
        dt = self.pt(x, t + 0.4) - self.pt(x, t - 0.4)
        dx = self.pt(min(x + 0.05, self.x1), t) - self.pt(max(x - 0.05, self.x0), t)
        n = dt.cross(dx)
        return n.normalized() if n.length > 1e-9 else Vector((1, 0, 0))

    def t_scale(self, x, t):
        dt = (self.pt(x, t + 0.5) - self.pt(x, t - 0.5)).length
        dx = (self.pt(x + 0.1, t) - self.pt(x - 0.1, t)).length / 0.2
        return max(dt, 1e-4), max(dx, 1e-4)

    def t_at_z(self, x, z, side):
        lo, hi = (0.0, 90.0) if side > 0 else (90.0, 180.0)
        for _ in range(40):
            mid = (lo + hi) / 2
            zm = self.pt(x, mid).z
            if (zm < z) == (side > 0):
                lo = mid
            else:
                hi = mid
        return (lo + hi) / 2

    def skin(self, p, xs, ts, matfn, cap_nose=True, cap_tail=True, nose_mat="Palette:Hull", tail_mat="Palette:Frame",
             smooth=True):
        rings = [[self.pt(x, t) for t in ts] for x in xs]
        idx = [[p.v(q) for q in ring] for ring in rings]
        n = len(ts)
        for k in range(len(xs) - 1):
            for i in range(n):
                j = (i + 1) % n
                ta, tb = ts[i], (ts[j] if j else 360.0)
                p.f([idx[k][i], idx[k][j], idx[k + 1][j], idx[k + 1][i]], matfn(xs[k], xs[k + 1], ta, tb), smooth)
        if cap_nose:
            c = sum(rings[-1], Vector((0, 0, 0))) / n + Vector((0.06, 0, 0))
            tip = p.v(c)
            for i in range(n):
                p.f([idx[-1][i], idx[-1][(i + 1) % n], tip], nose_mat, smooth)
        if cap_tail:
            c = sum(rings[0], Vector((0, 0, 0))) / n - Vector((0.04, 0, 0))
            tip = p.v(c)
            for i in range(n):
                p.f([idx[0][(i + 1) % n], idx[0][i], tip], tail_mat, False)


# ---- surface helpers on a LoftHull ---------------------------------------------------------
def emit_oriented(p, pts, n_ref, mat, smooth=False):
    n = Vector((0, 0, 0))
    for k in range(len(pts)):
        a, b = pts[k], pts[(k + 1) % len(pts)]
        n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    if n.dot(n_ref) < 0:
        pts = list(reversed(pts))
    p.f([p.v(q) for q in pts], mat, smooth)


def patch(p, H, x0, x1, t0, t1, off, mat, nx=2, nt=2, smooth=True):
    P = [[H.pt(x0 + (x1 - x0) * i / nx, t0 + (t1 - t0) * j / nt, off) for j in range(nt + 1)] for i in range(nx + 1)]
    ids = [[p.v(q) for q in row] for row in P]
    flip = (x1 - x0) * (t1 - t0) < 0
    for i in range(nx):
        for j in range(nt):
            q = [ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]]
            if flip:
                q.reverse()
            p.f(q, mat, smooth)
    return P


def panel(p, H, x0, x1, t0, t1, h, mat, side="Palette:Frame", nx=2, nt=2, base=-0.03, smooth=True):
    patch(p, H, x0, x1, t0, t1, h, mat, nx, nt, smooth)
    rim = [(x0 + (x1 - x0) * i / nx, t0) for i in range(nx)] + [(x1, t0 + (t1 - t0) * j / nt) for j in range(nt)] + \
          [(x1 - (x1 - x0) * i / nx, t1) for i in range(nx)] + [(x0, t1 - (t1 - t0) * j / nt) for j in range(nt)]
    cc = H.pt((x0 + x1) / 2, (t0 + t1) / 2, h)
    for k in range(len(rim)):
        (xa, ta), (xb, tb) = rim[k], rim[(k + 1) % len(rim)]
        a0, b0, a1, b1 = H.pt(xa, ta, base), H.pt(xb, tb, base), H.pt(xa, ta, h), H.pt(xb, tb, h)
        emit_oriented(p, [a0, b0, b1, a1], (a1 + b1) / 2 - cc, side)


def window_row(p, H, xs, t, w, h, frame="Palette:Frame"):
    """square windows along the hull at angle t: dark frame in Hull, emissive pane"""
    for x in xs:
        tw, xw = H.t_scale(x, t)
        dt, dx = h / 2 / tw, w / 2
        panel(p, H, x - dx - 0.06, x + dx + 0.06, t - dt - 0.06 / tw, t + dt + 0.06 / tw, 0.03, frame, side=frame, nx=1, nt=1)
        panel(p, H, x - dx, x + dx, t - dt, t + dt, 0.05, "Window", side=frame, nx=1, nt=1)


# ======================================================================================
# animated parts: a Part in its own local frame plus a placement matrix
# ======================================================================================
class Anim(Part):
    """a Part whose vertices are in local coordinates; `place` = local -> world; `stow_deg` about local X"""

    def __init__(self, name, place, stow_deg):
        super().__init__(name)
        self.place = place
        self.stow_deg = stow_deg


def place_frame(origin, out_dir_deg):
    """local frame: origin on the hinge, local +Y = horizontal direction out_dir_deg, local X = hinge axis"""
    return T(*origin) @ RZ(out_dir_deg - 90.0)


def leg_geometry(p, L_h, L_down, foot_r=0.5, strut=0.24, accent=True):
    """a landing leg in its local frame: hinge at 0, leg goes out (+Y) L_h and down (-Z) L_down.
    Thick upper strut, shock absorber, hydraulic ram, side braces, a 1.0 m foot pad."""
    foot = Vector((0.0, L_h, -L_down))
    mid = foot * 0.52
    u = mid.normalized()
    p.cyl((0, 0, 0), mid, strut, strut * 0.9, seg=8, mat="PaletteMetal:Metal")
    p.cyl(mid - u * 0.1, foot + Vector((0, 0, 0.38)), strut * 0.62, seg=8, mat="PaletteMetal:Trim")
    p.cyl(mid - u * 0.42, mid + u * 0.22, strut * 1.3, seg=8, mat="Accent" if accent else "Palette:HullDark")
    p.cyl(mid + u * 0.22, mid + u * 0.3, strut * 1.1, seg=8, mat="Palette:Hazard")
    ram0 = Vector((0.0, -0.35, 0.35))                      # hydraulic ram from the leg bay to the lower strut
    ram1 = mid.lerp(foot, 0.45) + Vector((0, -0.12, 0))
    p.cyl(ram0, ram0.lerp(ram1, 0.55), 0.09, seg=6, mat="PaletteMetal:Frame")
    p.cyl(ram0.lerp(ram1, 0.5), ram1, 0.055, seg=6, mat="PaletteMetal:Trim")
    for sx in (-1, 1):
        p.cyl((sx * 0.5, -0.1, -0.12), mid * 0.9, 0.07, seg=5, mat="PaletteMetal:Frame")
    p.cyl((-0.4, 0, 0), (0.4, 0, 0), strut * 1.15, seg=8, mat="PaletteMetal:Frame")               # hinge pin
    with p.at(T(*foot)):
        p.lathe([(foot_r, 0.0), (foot_r, 0.1), (foot_r * 0.6, 0.24), (0.0, 0.27)], "PaletteMetal:Frame", seg=12)
        p.lathe([(foot_r + 0.005, 0.02), (foot_r + 0.005, 0.07), (foot_r - 0.02, 0.075)], "Palette:Hazard", seg=12)
        p.sphere((0, 0, 0.34), 0.2, "PaletteMetal:Metal", seg=8, rings=4)


def ramp_geometry(p, width, length, slope_deg, rails=True):
    """ramp in its local frame: hinge on local X at 0, plate going out (+Y) and down at slope_deg"""
    a = radians(slope_deg)
    d = Vector((0, cos(a), -sin(a)))
    n = Vector((0, sin(a), cos(a)))
    hw = width / 2
    q = [Vector((-hw, 0, 0)), Vector((hw, 0, 0)), Vector((hw, 0, 0)) + d * length, Vector((-hw, 0, 0)) + d * length]
    th = 0.14
    top = [x + n * 0.0 for x in q]
    bot = [x - n * th for x in q]
    emit_oriented(p, top, n, "Palette:HullDark")
    emit_oriented(p, bot, -n, "Palette:Frame")
    cen = sum(top, Vector((0, 0, 0))) / 4
    for i in range(4):
        a0, b0, a1, b1 = bot[i], bot[(i + 1) % 4], top[i], top[(i + 1) % 4]
        emit_oriented(p, [a0, b0, b1, a1], (a1 + b1) / 2 - cen, "Palette:Frame")
    for k in range(6):                                           # treads
        f = (k + 0.6) / 6.5
        c = d * (length * f) + n * 0.015
        p.box(tuple(c), (width * 0.86, 0.08, 0.03), "PaletteMetal:Frame")
    for sx in (-1, 1):                                           # hazard edges + rails
        e0 = Vector((sx * (hw - 0.07), 0, 0)) + n * 0.03
        e1 = e0 + d * length
        p.beam(e0, e1, 0.14, 0.06, "Palette:Hazard", up=tuple(n))
        if rails:
            posts = [e0 + d * (length * f) for f in (0.15, 0.55, 0.95)]
            for q_ in posts:
                p.beam(q_, q_ + Vector((0, 0, 0.95)), 0.05, 0.05, "PaletteMetal:Frame")
            p.beam_path([q_ + Vector((0, 0, 0.95)) for q_ in posts], 0.05, 0.05, "PaletteMetal:Trim")
    return d * length


def door_geometry(p, w, h, t=0.08, window=True):
    """a hatch leaf in its local frame: hinge along local X at its lower edge? No: the leaf lies in the local XZ
    plane, hinge on local X at z = 0, leaf rises +Z; outer face toward -Y."""
    p.box((0, 0, h / 2), (w, t, h), "Palette:Hull", mats={"-y": "Palette:Hull", "+y": "Palette:HullDark"})
    p.box((0, -t / 2 - 0.006, h * 0.5), (w * 0.9, 0.012, 0.08), "Accent")
    if window:
        p.box((0, -t / 2 - 0.008, h * 0.72), (w * 0.4, 0.012, h * 0.16), "Window")


# ======================================================================================
# FLEET LANGUAGE (critic round 9 fixes 1-5): shared by all six ships
# ======================================================================================
DGLASS = "Palette:#18233f"          # dark cockpit glass by day (lit panes are in the Lights node)
BRONZE = "PaletteMetal:#b08d57"
NAV_SPEC = {"LightRed": dict(color="#ff3b30", rough=0.4, emit="#ff3b30", emit_strength=3.0),
            "LightGreen": dict(color="#3dff6e", rough=0.4, emit="#3dff6e", emit_strength=3.0)}
# round 11 fix 4: warm #FFD9A0 at 60 % of the old strength; passenger windows dimmer than the bridge
WINDOW_SPEC = {"Window": dict(color="#ffd9a0", rough=0.4, emit="#ffd9a0", emit_strength=0.9),
               "CabinWindow": dict(color="#ffd9a0", rough=0.4, emit="#ffd9a0", emit_strength=0.5)}
REG = {"trader": "TR-07", "shuttle": "SH-12", "liner": "LN-03", "medical": "MD-21", "science": "SC-09",
       "courier": "CR-01"}

GLYPHS = {
    "0": [[(0, 0), (1, 0), (1, 2), (0, 2), (0, 0)]], "1": [[(0.5, 0), (0.5, 2)], [(0.2, 1.7), (0.5, 2)]],
    "2": [[(0, 2), (1, 2), (1, 1), (0, 1), (0, 0), (1, 0)]], "3": [[(0, 2), (1, 2), (1, 0), (0, 0)], [(0.2, 1), (1, 1)]],
    "4": [[(0, 2), (0, 1), (1, 1)], [(1, 2), (1, 0)]], "5": [[(1, 2), (0, 2), (0, 1), (1, 1), (1, 0), (0, 0)]],
    "6": [[(1, 2), (0, 2), (0, 0), (1, 0), (1, 1), (0, 1)]], "7": [[(0, 2), (1, 2), (1, 0)]],
    "8": [[(0, 0), (1, 0), (1, 2), (0, 2), (0, 0)], [(0, 1), (1, 1)]],
    "9": [[(1, 1), (0, 1), (0, 2), (1, 2), (1, 0), (0, 0)]],
    "T": [[(0, 2), (1, 2)], [(0.5, 2), (0.5, 0)]], "R": [[(0, 0), (0, 2), (1, 2), (1, 1), (0, 1)], [(0.4, 1), (1, 0)]],
    "S": [[(1, 2), (0, 2), (0, 1), (1, 1), (1, 0), (0, 0)]], "H": [[(0, 0), (0, 2)], [(1, 0), (1, 2)], [(0, 1), (1, 1)]],
    "L": [[(0, 2), (0, 0), (1, 0)]], "N": [[(0, 0), (0, 2), (1, 0), (1, 2)]], "M": [[(0, 0), (0, 2), (0.5, 1), (1, 2), (1, 0)]],
    "D": [[(0, 0), (0, 2), (0.6, 2), (1, 1.4), (1, 0.6), (0.6, 0), (0, 0)]], "C": [[(1, 2), (0, 2), (0, 0), (1, 0)]],
    "E": [[(1, 2), (0, 2), (0, 0), (1, 0)], [(0, 1), (0.7, 1)]], "-": [[(0.15, 1), (0.85, 1)]],
}


def stencil(p, text, origin, right, up, height, mat, normal, depth=0.02):
    """stroke letters on a plane: origin = bottom-left, right/up unit vectors, height of a letter in metres"""
    s = height / 2.0
    right, up, normal = Vector(right).normalized(), Vector(up).normalized(), Vector(normal).normalized()
    x = 0.0
    w = 0.26 * s
    for ch in text:
        for stroke in GLYPHS.get(ch, []):
            pts = [Vector(origin) + right * ((x + a) * s) + up * (b * s) + normal * (depth / 2) for a, b in stroke]
            for a, b in zip(pts[:-1], pts[1:]):
                d = (b - a).normalized()
                p.beam(a - d * w / 2, b + d * w / 2, w, depth, mat, up=tuple(normal))
        x += 1.55
    return x * s


def registration(p, H, kind, x_centre, t_plus, height=0.42, mat="Palette:#2c3036", plate="Palette:#eef0f2"):
    """registration code on both flanks at hull angle t_plus (+Y side) and 180 - t_plus (-Y side)"""
    code = REG[kind]
    length = (len(code) * 1.55 - 0.55) * height / 2
    for side, t in ((1, t_plus), (-1, 180.0 - t_plus)):
        n = H.nrm(x_centre, t)
        c = H.pt(x_centre, t, 0.05)
        tang = (H.pt(x_centre + 0.1, t) - H.pt(x_centre - 0.1, t)).normalized()     # follows a tapering hull
        right = -tang if side > 0 else tang
        n = (n - tang * n.dot(tang)).normalized()
        up = n.cross(right).normalized()
        if up.z < 0:
            up = -up
        tw, xw = H.t_scale(x_centre, t)
        dt = (height * 0.8) / tw
        panel(p, H, x_centre - length / 2 - 0.2, x_centre + length / 2 + 0.2, t - dt, t + dt, 0.03, plate, side=plate,
              nx=2, nt=1)
        o = c - right * (length / 2) - up * (height / 2)
        stencil(p, code, o, right, up, height, mat, n, depth=0.03)


def faceted_cockpit(h, lights, x0, xm, x1, w, zb, zt, c, front_top, front_w, mull="PaletteMetal:Frame", body="Palette:Hull"):
    """chamfered bridge block along +X: body from x0 to xm, glass nose from xm to x1 (top drops to front_top,
    width to front_w). Dark glass by day; lit copies of the glass faces in `lights` (Window)."""
    def ring(x, ww, zt_, cc):
        return [Vector((x, ww, zb)), Vector((x, ww, zt_ - cc)), Vector((x, ww - cc, zt_)), Vector((x, -(ww - cc), zt_)),
                Vector((x, -ww, zt_ - cc)), Vector((x, -ww, zb))]
    r0, r1, r2 = ring(x0, w, zt, c), ring(xm, w, zt, c), ring(x1, front_w, front_top, c * 0.7)
    cen = Vector(((x0 + x1) / 2, 0, (zb + zt) / 2))
    for A, B, glass in ((r0, r1, False), (r1, r2, True)):
        for i in range(5):
            q = [A[i], A[i + 1], B[i + 1], B[i]]
            mid = sum(q, Vector((0, 0, 0))) / 4
            is_glass = glass and i in (1, 2, 3)
            emit_oriented(h, q, mid - cen, DGLASS if is_glass else body)
            if is_glass:
                n = (q[1] - q[0]).cross(q[2] - q[1])
                if n.dot(mid - cen) < 0:
                    n = -n
                n.normalize()
                ins = [v + (mid - v) * 0.12 + n * 0.02 for v in q]
                emit_oriented(lights, ins, n, "Window")
    emit_oriented(h, list(r2), Vector((1, 0, 0)), body)
    # mullions along the glass edges and one across the windshield
    for i in (1, 2, 3, 4):
        h.beam(r1[i], r2[i], 0.09, 0.09, mull)
    h.beam_path([r1[i] for i in (1, 2, 3, 4)], 0.1, 0.1, mull)
    h.beam_path([r2[i] for i in (1, 2, 3, 4)], 0.1, 0.1, mull)
    mid = [r1[i].lerp(r2[i], 0.5) for i in (2, 3)]
    h.beam(mid[0], mid[1], 0.07, 0.07, mull)
    for sy in (-1, 1):                                        # side mullion on the chamfer glass
        a = r1[1 if sy > 0 else 4].lerp(r1[2 if sy > 0 else 3], 0.5)
        b = r2[1 if sy > 0 else 4].lerp(r2[2 if sy > 0 else 3], 0.5)
        h.beam(a, b, 0.07, 0.07, mull)
    # a sun visor lip
    h.beam(r1[2] + Vector((0.05, 0, 0.08)), r1[3] + Vector((0.05, 0, 0.08)), 0.22, 0.08, "Palette:HullDark")


def engine_bell(h, origin, direction_deg_y, r=0.72, L=2.3, ring_mat="Accent"):
    """nacelle + bell nozzle with an inner cone (Plasma) and a bronze rim; lathe along the exhaust direction.
    origin = front centre, the nozzle points along local +Z of RY(direction_deg_y). Returns the exit point."""
    with h.at(T(*origin), RY(direction_deg_y)):
        prof = [(r * 0.62, 0.0), (r, 0.22), (r * 1.03, 0.45), (r * 1.03, L * 0.52), (r, L * 0.6), (r * 0.9, L * 0.72),
                (r * 0.72, L * 0.8), (r * 0.8, L * 0.93), (r * 0.9, L), (r * 0.94, L + 0.02), (r * 0.8, L + 0.02),
                (r * 0.62, L * 0.84)]
        mats = ["Palette:Hull", ring_mat, "Palette:Hull", "PaletteMetal:Frame", "PaletteMetal:Metal", "PaletteMetal:Metal",
                "PaletteMetal:Metal", "PaletteMetal:Metal", BRONZE, BRONZE, "Palette:#23262c"]
        h.lathe(prof, lambda k, i: mats[k], seg=16)
        h.lathe([(0.0, L * 0.84 - 0.01), (r * 0.62, L * 0.84)], "Palette:#23262c", seg=16, smooth=False)
        h.lathe([(r * 0.42, L * 0.84), (0.0, L + 0.12)], "Plasma", seg=12, smooth=True)          # inner cone
        h.lathe([(r * 1.05, L * 0.28), (r * 1.07, L * 0.31), (r * 1.07, L * 0.4), (r * 1.05, L * 0.43)], "PaletteMetal:Trim",
                seg=16, smooth=False)
    a = radians(direction_deg_y)
    return Vector(origin) + Vector((sin(a), 0, cos(a))) * (L + 0.05)


def hover_thruster(h, x, y, z_top, r=0.42):
    """downward thruster in a housing, inner cone glows (Plasma). Returns the exit point."""
    h.vcyl(x, y, z_top - 0.55, z_top, r, seg=12, mat="PaletteMetal:Metal", cap0=False)
    h.vcyl(x, y, z_top - 0.64, z_top - 0.55, r * 1.1, seg=12, mat=BRONZE, cap0=False)
    h.vcyl(x, y, z_top - 0.6, z_top - 0.59, r * 0.8, seg=12, mat="Palette:#23262c", cap1=False)
    with h.at(T(x, y, z_top - 0.6), RX(180)):
        h.lathe([(r * 0.5, 0.0), (0.0, 0.16)], "Plasma", seg=10)
    return Vector((x, y, z_top - 0.66))


def hazard_frame(p, H, x0, x1, t0, t1, width=0.14, n=6, off=0.03):
    """striped Hazard / graphite border round a rectangle (x, t) on the hull (an opening)"""
    tw, xw = H.t_scale((x0 + x1) / 2, (t0 + t1) / 2)
    dt = width / tw
    for k in range(n):
        m = "Palette:Hazard" if k % 2 == 0 else "Palette:#2b2d33"
        xa, xb = x0 + (x1 - x0) * k / n, x0 + (x1 - x0) * (k + 1) / n
        patch(p, H, xa, xb, t0 - dt, t0, off, m, nx=1, nt=1)
        patch(p, H, xa, xb, t1, t1 + dt, off, m, nx=1, nt=1)
        ta, tb = t0 + (t1 - t0) * k / n, t0 + (t1 - t0) * (k + 1) / n
        patch(p, H, x0 - width, x0, ta, tb, off, m, nx=1, nt=1)
        patch(p, H, x1, x1 + width, ta, tb, off, m, nx=1, nt=1)


def inset_panel(p, H, x0, x1, t0, t1, mat="Palette:#c3c9d1", border="Palette:HullDark"):
    """flank panel inset: a darker frame line and a slightly different panel tone"""
    tw, xw = H.t_scale((x0 + x1) / 2, (t0 + t1) / 2)
    b = 0.05 / tw
    patch(p, H, x0, x1, t0, t1, 0.012, mat, nx=1, nt=1)
    for (xa, xb, ta, tb) in ((x0 - 0.05, x1 + 0.05, t0 - b, t0), (x0 - 0.05, x1 + 0.05, t1, t1 + b),
                             (x0 - 0.05, x0, t0, t1), (x1, x1 + 0.05, t0, t1)):
        patch(p, H, xa, xb, ta, tb, 0.016, border, nx=1, nt=1)


def rail(p, pts, h=0.55, post_every=1.2, mat="Palette:Hazard", post="PaletteMetal:Frame"):
    pts = [Vector(q) for q in pts]
    tops = []
    for k, q in enumerate(pts):
        p.beam(q, q + Vector((0, 0, h)), 0.04, 0.04, post)
        tops.append(q + Vector((0, 0, h)))
    p.beam_path(tops, 0.045, 0.045, mat)


def hull_ladder(p, H, x, side, t_bottom, t_top, n=7, w=0.4):
    """rungs up the flank from angle t_bottom to t_top at station x"""
    ts = [t_bottom + (t_top - t_bottom) * k / (n - 1) for k in range(n)]
    for dy in (-w / 2, w / 2):
        pts = [H.pt(x + dy, t, 0.1) for t in ts]
        p.beam_path(pts, 0.04, 0.04, "PaletteMetal:Trim")
    for t in ts[1:-1]:
        p.beam(H.pt(x - w / 2, t, 0.1), H.pt(x + w / 2, t, 0.1), 0.03, 0.03, "PaletteMetal:Frame")


def nav_light(h, lights, pos, colour, r=0.1):
    """housing in the hull, lens in Lights (colour 'LightRed', 'LightGreen' or 'Light')"""
    h.sphere(tuple(pos), r * 1.2, "PaletteMetal:Frame", seg=8, rings=4)
    lights.sphere(tuple(Vector(pos) + Vector((0, 0, 0.03))), r * 1.35, colour, seg=8, rings=4)


FLOODS = []          # (position, aim) of every flood of the ship being built -> empties Flood_<i> (round 12)


def flood(h, lights, pos, aim, r=0.11):
    """a flood light: box housing in the hull, emissive lens in Lights, facing `aim`; also registered as an empty"""
    aim = Vector(aim).normalized()
    h.box(tuple(pos), (0.3 + r, 0.3 + r, 0.16), "PaletteMetal:Frame", bevel=0.03)
    lights.cyl(Vector(pos) + aim * 0.08, Vector(pos) + aim * 0.12, r, seg=10, mat="Light")
    FLOODS.append((Vector(pos) + aim * 0.14, aim))


def belly_flood(parts):
    """round 12: a large lit lens under the belly next to the ramp hinge, aimed at the ramp foot"""
    hull = next(p for p in parts if p.name == "Hull")
    lights = next(p for p in parts if p.name == "Lights")
    ramp = next(p for p in parts if p.name == "Ramp")
    hinge = ramp.place.translation
    out = (ramp.place.to_3x3() @ Vector((0, 1, 0))).normalized()
    zs = [v.z for v in hull.verts if (Vector((v.x, v.y, 0)) - Vector((hinge.x, hinge.y, 0)) - out * -0.4).length < 0.45]
    zb = min(zs) if zs else hinge.z
    pos = Vector((hinge.x, hinge.y, 0)) - out * 0.4 + Vector((0, 0, zb - 0.1))
    steep = ramp.stow_deg < 90.0                 # a rear ramp slopes down under the lens: aim steeper, not along it
    aim = (out * (0.5 if steep else 1.15) + Vector((0, 0, -1))).normalized()
    flood(hull, lights, pos, aim, r=0.18)


def ribbed_container(p, c, size, colour="Accent", yaw=0.0, ribs=5):
    """ribbed cargo container (stencilled with a hazard corner band)"""
    sx, sy, sz = size
    with p.at(T(*c), RZ(yaw)):
        p.box0(0, 0, 0.0, sx, sy, sz, colour, mats={"-z": None})
        for k in range(ribs):
            x = -sx / 2 + sx * (k + 0.5) / ribs
            p.box0(x, 0, 0.02, 0.06, sy + 0.06, sz - 0.04, "Palette:#6b7078", mats={"-z": None})
        for sx_ in (-1, 1):
            p.box0(sx_ * (sx / 2 - 0.04), 0, 0.0, 0.1, sy + 0.08, sz + 0.02, "PaletteMetal:Frame", mats={"-z": None})
        p.box0(0, 0, sz, sx - 0.2, sy - 0.2, 0.03, "Palette:#6b7078")
        p.box((sx * 0.25, -(sy / 2 + 0.035), sz * 0.72), (sx * 0.3, 0.012, 0.12), "Palette:Hazard")


# ======================================================================================
# build: parts -> objects -> AO -> palette -> export with extras -> checks
# ======================================================================================
def split_mat(name):
    """'Palette:Hull' -> ('Palette', '#d9dde2'); 'Accent' -> ('Accent', None)"""
    if ":" in name:
        base, src = name.split(":", 1)
        if base == "PaletteMetal":          # round 11: one palette material frees a slot for CabinWindow
            base = "Palette"
        return base, (src if src.startswith("#") else C.MATERIALS[src]["color"])
    return name, None


class ShipMatSet(C.MaterialSet):
    def spec(self, name):
        if name in PALETTE_SPEC:
            return PALETTE_SPEC[name]
        if name in NAV_SPEC:
            return NAV_SPEC[name]
        if name in WINDOW_SPEC:
            return WINDOW_SPEC[name]
        return super().spec(name)


def part_to_obj(part, mset):
    """like ext_common.part_to_object, with 'Palette:<src>' names: the face gets material Palette, and the source
    colour is remembered per face for the COLOR_0 multiply after the AO bake."""
    base_names = []
    colours = []
    for m in part.fmat:
        b, col = split_mat(m)
        base_names.append(b)
        colours.append(C.hex_to_linear(col) if col else (1.0, 1.0, 1.0))
    saved = part.fmat
    part.fmat = base_names
    ob = C.part_to_object(part, mset)
    part.fmat = saved
    ob["_face_col"] = [c for rgb in colours for c in rgb]
    if isinstance(part, Anim):
        ob.matrix_world = part.place
        ob["stow_deg"] = float(part.stow_deg)
    return ob


def apply_palette(ob):
    me = ob.data
    cols = list(ob["_face_col"])
    del ob["_face_col"]
    if len(cols) != 3 * len(me.polygons):
        raise RuntimeError("%s: face colours %d != faces %d (mesh.validate removed faces)" % (ob.name, len(cols) // 3,
                                                                                          len(me.polygons)))
    attr = me.color_attributes.active_color
    data = [0.0] * (len(attr.data) * 4)
    attr.data.foreach_get("color", data)
    for poly in me.polygons:
        r, g, b = cols[poly.index * 3:poly.index * 3 + 3]
        for li in poly.loop_indices:
            data[li * 4] *= r
            data[li * 4 + 1] *= g
            data[li * 4 + 2] *= b
    attr.data.foreach_set("color", data)
    me.update()


def anchor_obj(a, props=None):
    """empty named exactly a.name (Thruster_*, Anchor_*); local +X = a.forward"""
    ob = bpy.data.objects.new(a.name, None)
    ob.empty_display_type = "ARROWS"
    ob.empty_display_size = 0.5
    x = a.forward
    z = a.up - x * a.up.dot(x)
    if z.length < 1e-6:
        z = Vector((0, 0, 1)) if abs(x.z) < 0.9 else Vector((0, 1, 0))
        z = z - x * z.dot(x)
    z.normalize()
    y = z.cross(x)
    m = Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z)))
    ob.matrix_world = Matrix.Translation(a.pos) @ m.to_4x4()
    bpy.context.scene.collection.objects.link(ob)
    for k, v in (props or {}).items():
        ob[k] = v
    return ob


def export_glb(path):
    tmp = path[:-4] + ".tmp.glb"
    if os.path.exists(tmp):
        os.remove(tmp)
    bpy.ops.export_scene.gltf(
        filepath=tmp, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False, export_skins=False, export_morph=False,
        export_extras=True, export_materials="EXPORT", export_normals=True, export_tangents=False,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_active_vertex_color_when_no_material=True)
    os.replace(tmp, path)


def build_ship(kind, builder, ao_dist=1.0):
    t0 = time.time()
    C.reset_scene()
    FLOODS.clear()
    out = builder()
    parts = [p for p in out if isinstance(p, Part)]
    belly_flood(parts)
    anchors = [a for a in out if isinstance(a, tuple)]            # (Anchor, props)
    for k, (pos, aim) in enumerate(FLOODS):
        anchors.append((Anchor("Flood_%d" % (k + 1), pos, forward=aim, up=(0, 0, 1) if abs(aim.z) < 0.95 else (1, 0, 0)),
                        {"role": "flood"}))
    mset = ShipMatSet(KIND_ACCENT[kind])
    objs = {}
    for part in parts:
        if part.faces:
            objs[part.name] = part_to_obj(part, mset)
    for a, props in anchors:
        anchor_obj(a, props)
    bpy.context.view_layer.update()
    main = [n for n in objs if not (n.startswith("Leg_") or n.startswith("Ramp") or n.startswith("Door_") or n == "Lights")]
    occ = {n: (main if n in main else main + [n]) for n in objs}
    C.bake_ao(objs, occ, dist=ao_dist, samples=32, min_ao=0.2)
    for ob in objs.values():
        apply_palette(ob)
    os.makedirs(MODEL_DIR, exist_ok=True)
    path = os.path.join(MODEL_DIR, "ship_%s.glb" % kind)
    export_glb(path)
    return check_ship(kind, path, time.time() - t0)


def check_ship(kind, path, secs):
    g, _ = C.read_glb(path)
    info = C.inspect_glb(path)
    flags = []
    tris = sum(info["tris"].values())
    mats = info["materials"]
    if tris > MAX_TRIS:
        flags.append("triangles %d > %d" % (tris, MAX_TRIS))
    if len(mats) > MAX_MATS:
        flags.append("materials %d > %d" % (len(mats), MAX_MATS))
    if not all(info["color0"].values()):
        flags.append("COLOR_0 missing")
    names = [n.get("name") for n in g["nodes"]]
    for need in ("Hull", "Ramp"):
        if need not in names:
            flags.append("no %s node" % need)
    if not any(n.startswith("Leg_") for n in names):
        flags.append("no Leg_ nodes")
    if not any(n.startswith("Thruster_") for n in names):
        flags.append("no Thruster_ nodes")
    for n in g["nodes"]:
        nm = n.get("name", "")
        if nm.startswith(("Leg_", "Ramp", "Door_")) and "stow_deg" not in n.get("extras", {}):
            flags.append("%s has no stow_deg" % nm)
    # plan radius and height from the Blender scene (world space, rest pose)
    rmax, zmax, zmin = 0.0, -1e9, 1e9
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            q = mw @ v.co
            rmax = max(rmax, math.hypot(q.x, q.y))
            zmax, zmin = max(zmax, q.z), min(zmin, q.z)
    if rmax > MAX_R + 1e-3:
        flags.append("plan radius %.2f > %.2f" % (rmax, MAX_R))
    if zmax > MAX_H:
        flags.append("height %.2f > %.2f" % (zmax, MAX_H))
    if zmin < -0.02:
        flags.append("below the soles: z %.2f" % zmin)
    row = dict(id="ship_" + kind, tris=tris, tris_by=info["tris"], materials=mats, n_materials=len(mats),
               radius=round(rmax, 2), height=round(zmax, 2), zmin=round(zmin, 3), nodes=names,
               kb=os.path.getsize(path) // 1024, flags=flags, seconds=round(secs, 1))
    print("  ship_%-10s %6d tris  %d mats  r %.2f  h %.2f  %s" % (kind, tris, len(mats), rmax, zmax, "; ".join(flags) or "ok"))
    os.makedirs(ART_DIR, exist_ok=True)
    rep = {}
    if os.path.exists(REPORT_JSON):
        try:
            rep = json.load(open(REPORT_JSON, encoding="utf-8"))
        except Exception:
            rep = {}
    rep[row["id"]] = row
    json.dump(rep, open(REPORT_JSON, "w", encoding="utf-8"), indent=1)
    return row


def bubble_canopy(h, lights, c, rx, ry, rz, ribs=4):
    """courier canopy: a half-ellipsoid of dark glass with frame ribs; a lit inner shell in `lights`"""
    prof = [(1.0, 0.0), (0.96, 0.3), (0.82, 0.62), (0.55, 0.88), (0.0, 1.0)]
    with h.at(T(*c), S(rx, ry, rz)):
        h.lathe(prof, DGLASS, seg=16)
    with lights.at(T(*c), S(rx * 0.985, ry * 0.985, rz * 0.985)):
        lights.lathe(prof[1:-1], "Window", seg=16)
    for k in range(ribs):
        x = -rx + 2 * rx * (k + 0.5) / ribs
        f = sqrt(max(0.0, 1 - (x / rx) ** 2))
        pts = [Vector((c[0] + x, ry * f * cos(radians(a)), c[2] + rz * f * sin(radians(a)) + 0.01)) for a in range(0, 181, 30)]
        h.beam_path(pts, 0.05, 0.05, "Palette:Frame")
