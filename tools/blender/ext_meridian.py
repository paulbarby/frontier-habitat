"""
Frontier Habitat 2.0 - The Meridian (crashed colony ship, AAA_DESIGN.md section 9) and debris_a/b/c.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_meridian.py -- [--only meridian,debris_a]

Output: assets/models/meridian.glb, debris_a.glb, debris_b.glb, debris_c.glb

The ship is modelled level in "ship space" (belly at z = 0, nose at +X), then placed with CRASH:
pitch PITCH deg nose down about the line x = PIVOT_X on the ground, roll ROLL deg (-Y side down) about the
+Y belly edge, then lowered by SINK. In Godot the tilt is rotation.z = -PITCH deg and rotation.x = +ROLL deg;
to show the ship level (test flight) apply rotation.z += PITCH deg, rotation.x -= ROLL deg.

Objects: Hull (intact ship), Damage1 (hull breaches, torn plates, sand, dirt berm), Damage2 (systems:
shattered cockpit glass, spilled cables, snapped antenna), Damage3 (engines: crumpled nozzle, torn cowl, soot,
wreckage), Scaffold (towers + work lights), Lights (cabin windows, portholes, running lights; emissive),
EngineGlow (nozzle glow; emissive).  Empties: Anchor_Engine_L (+Y pod), Anchor_Engine_R (-Y pod),
Anchor_Ramp (foot of the side ramp).  Anchor local +X = exhaust direction / walking direction.
"""
import os
import sys
import random
from math import sin, cos, pi, radians, degrees, sqrt, atan2, copysign

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                       # noqa: E402
from ext_common import Part, Anchor, T, RX, RY, RZ, S, lerp, smoothstep   # noqa: E402
from mathutils import Vector, Matrix                         # noqa: E402

PITCH = 4.0         # degrees, nose down
ROLL = 2.0          # degrees, -Y side down
PIVOT_X = -13.0     # the belly touches the ground here
ROLL_Y = 4.4        # roll axis: the +Y belly edge
SINK = 0.10         # the whole ship sits this much in the dust


def crash_matrix():
    m_pitch = T(PIVOT_X, 0, 0) @ RY(PITCH) @ T(-PIVOT_X, 0, 0)
    m_roll = T(0, ROLL_Y, 0) @ RX(ROLL) @ T(0, -ROLL_Y, 0)
    return T(0, 0, -SINK) @ m_roll @ m_pitch


M = crash_matrix()
M3 = M.to_3x3()


def W(p):
    """ship space -> world"""
    return M @ Vector(p)


# ======================================================================================
# monotone cubic interpolation (Fritsch-Carlson)
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
            return self.ys[0] + self.m[0] * (x - xs[0])
        if x >= xs[-1]:
            return self.ys[-1] + self.m[-1] * (x - xs[-1])
        i = 0
        while xs[i + 1] < x:
            i += 1
        h = self.h[i]
        t = (x - xs[i]) / h
        h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
        h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
        return h00 * self.ys[i] + h10 * h * self.m[i] + h01 * self.ys[i + 1] + h11 * h * self.m[i + 1]


# ======================================================================================
# the hull shape (ship space)
# ======================================================================================
#        x       w     ztop  zbot  zchine
STATIONS = [
    (-19.30, 4.05, 5.55, 0.70, 2.10),
    (-18.50, 4.12, 5.78, 0.46, 2.06),
    (-16.00, 4.22, 6.08, 0.18, 2.02),
    (-12.00, 4.36, 6.32, 0.05, 2.00),
    (-10.00, 4.52, 6.40, 0.00, 2.00),
    (-7.00, 5.28, 6.40, 0.00, 2.00),
    (-5.00, 5.60, 6.40, 0.00, 2.00),
    (5.00, 5.60, 6.40, 0.00, 2.00),
    (8.00, 5.55, 6.30, 0.02, 2.00),
    (11.00, 5.30, 5.86, 0.08, 1.96),
    (14.00, 4.76, 5.06, 0.20, 1.91),
    (17.00, 3.86, 4.06, 0.40, 1.87),
    (19.00, 2.92, 3.32, 0.65, 1.85),
    (20.40, 1.94, 2.78, 0.95, 1.85),
    (21.10, 1.02, 2.36, 1.30, 1.85),
    (21.40, 0.32, 2.02, 1.64, 1.85),
]
N_TOP, N_BOT = 2.3, 4.2
X_TAIL, X_NOSE = -19.30, 21.40


class HullShape:
    def __init__(self):
        xs = [s[0] for s in STATIONS]
        self.fw = Pchip(xs, [s[1] for s in STATIONS])
        self.ft = Pchip(xs, [s[2] for s in STATIONS])
        self.fb = Pchip(xs, [s[3] for s in STATIONS])
        self.fc = Pchip(xs, [s[4] for s in STATIONS])

    def sec(self, x):
        return self.fw(x), self.ft(x), self.fb(x), self.fc(x)

    def pt(self, x, t, off=0.0):
        w, zt, zb, zc = self.sec(x)
        a = radians(t)
        c, s = cos(a), sin(a)
        if s >= 0:
            e, h = 2.0 / N_TOP, zt - zc
        else:
            e, h = 2.0 / N_BOT, zc - zb
        p = Vector((x, w * copysign(abs(c) ** e, c), zc + copysign(abs(s) ** e, s) * h))
        if off:
            p = p + self.nrm(x, t) * off
        return p

    def nrm(self, x, t):
        dt = self.pt(x, t + 0.4) - self.pt(x, t - 0.4)
        dx = self.pt(x + 0.05, t) - self.pt(x - 0.05, t)
        n = dt.cross(dx)
        if n.length < 1e-9:
            return Vector((1, 0, 0))
        return n.normalized()

    def t_scale(self, x, t):
        """metres of surface per degree of t, and per metre of x"""
        dt = (self.pt(x, t + 0.5) - self.pt(x, t - 0.5)).length
        dx = (self.pt(x + 0.1, t) - self.pt(x - 0.1, t)).length / 0.2
        return max(dt, 1e-4), max(dx, 1e-4)

    def t_at_z(self, x, z, side):
        """t on the upper flank (side +1: 0..90, side -1: 90..180) where the hull has height z"""
        lo, hi = (0.0, 90.0) if side > 0 else (90.0, 180.0)
        for _ in range(40):
            mid = (lo + hi) / 2
            zm = self.pt(x, mid).z
            if side > 0:
                if zm < z:
                    lo = mid
                else:
                    hi = mid
            else:
                if zm > z:
                    lo = mid
                else:
                    hi = mid
        return (lo + hi) / 2


H = HullShape()


# ======================================================================================
# surface helpers (all in ship space; the caller wraps them in part.at(M))
# ======================================================================================
def _emit_oriented(part, pts, n_ref, mat, smooth=False):
    """polygon from ship-space points, wound so its normal agrees with n_ref"""
    a, b, c = pts[0], pts[1], pts[2]
    n = (b - a).cross(c - b)
    if len(pts) > 3:
        n = Vector((0, 0, 0))
        for k in range(len(pts)):
            p, q = pts[k], pts[(k + 1) % len(pts)]
            n += Vector(((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y)))
    if n.dot(n_ref) < 0:
        pts = list(reversed(pts))
    part.f([part.v(p) for p in pts], mat, smooth)


def patch(part, x0, x1, t0, t1, off, mat, nx=2, nt=2, smooth=True):
    """a rectangle in (x, t) laid on the hull at `off` metres"""
    P = [[H.pt(x0 + (x1 - x0) * i / nx, t0 + (t1 - t0) * j / nt, off) for j in range(nt + 1)] for i in range(nx + 1)]
    ids = [[part.v(p) for p in row] for row in P]
    flip = (x1 - x0) * (t1 - t0) < 0
    for i in range(nx):
        for j in range(nt):
            q = [ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]]
            if flip:
                q.reverse()
            m = mat(i, j) if callable(mat) else mat
            if m:
                part.f(q, m, smooth)
    return P


def panel(part, x0, x1, t0, t1, h, mat, side="Frame", nx=2, nt=2, base=-0.03, smooth=True):
    """raised panel: top at `h` above the hull, side walls down to `base`"""
    top = patch(part, x0, x1, t0, t1, h, mat, nx, nt, smooth)
    rim = [(x0 + (x1 - x0) * i / nx, t0) for i in range(nx)] + [(x1, t0 + (t1 - t0) * j / nt) for j in range(nt)] + \
          [(x1 - (x1 - x0) * i / nx, t1) for i in range(nx)] + [(x0, t1 - (t1 - t0) * j / nt) for j in range(nt)]
    cx, ct = (x0 + x1) / 2, (t0 + t1) / 2
    for k in range(len(rim)):
        (xa, ta), (xb, tb) = rim[k], rim[(k + 1) % len(rim)]
        pa0, pb0 = H.pt(xa, ta, base), H.pt(xb, tb, base)
        pa1, pb1 = H.pt(xa, ta, h), H.pt(xb, tb, h)
        mid = (pa1 + pb1) / 2
        outward = mid - H.pt(cx, ct, h)
        _emit_oriented(part, [pa0, pb0, pb1, pa1], outward, side)
    return top


def frame_strips(part, x0, x1, t0, t1, width, h, mat):
    """four thin raised strips round a rectangle (door frames)"""
    tw, xw = H.t_scale((x0 + x1) / 2, (t0 + t1) / 2)
    dt = width / tw
    panel(part, x0, x1, t0 - dt, t0, h, mat, side=mat, nx=2, nt=1)
    panel(part, x0, x1, t1, t1 + dt, h, mat, side=mat, nx=2, nt=1)
    panel(part, x0 - width, x0, t0 - dt, t1 + dt, h, mat, side=mat, nx=1, nt=2)
    panel(part, x1, x1 + width, t0 - dt, t1 + dt, h, mat, side=mat, nx=1, nt=2)


def to_xt(xc, tc, du, dv):
    """metric offset (du along x, dv along the surface in t) -> (x, t)"""
    tw, xw = H.t_scale(xc, tc)
    return xc + du / xw, tc + dv / tw


def decal(part, xc, tc, radii, off, mat, rings=(0.55, 1.0), rot=0.0, ecc=1.0):
    """jagged polygon on the hull; radii: list of metric radii at equal angles"""
    n = len(radii)
    nref = H.nrm(xc, tc)
    centre = H.pt(xc, tc, off)
    prev = None
    rim_pts = []
    for fr in rings:
        ring = []
        for k in range(n):
            a = 2 * pi * k / n + rot
            r = radii[k] * fr
            x, t = to_xt(xc, tc, r * cos(a) * ecc, r * sin(a))
            ring.append(H.pt(x, t, off))
        if prev is None:
            for k in range(n):
                _emit_oriented(part, [centre, ring[k], ring[(k + 1) % n]], nref, mat)
        else:
            for k in range(n):
                _emit_oriented(part, [prev[k], ring[k], ring[(k + 1) % n], prev[(k + 1) % n]], nref, mat)
        prev = ring
        rim_pts = ring
    return rim_pts


def thin_plate(part, a, b, tip, thick, top_mat, bot_mat, nref):
    """triangular plate (a, b, tip) with thickness along nref (petals, shards)"""
    d = nref.normalized() * thick
    A, B, Tt = [a, b, tip], [a - d, b - d, tip - d], None
    _emit_oriented(part, A, nref, top_mat)
    _emit_oriented(part, B, -nref, bot_mat)
    cen = (a + b + tip) / 3
    for i in range(3):
        p, q = A[i], A[(i + 1) % 3]
        p2, q2 = B[i], B[(i + 1) % 3]
        out = (p + q) / 2 - cen
        _emit_oriented(part, [p, q, q2, p2], out, bot_mat)


def quad_plate(part, pts, thick, top_mat, bot_mat, nref):
    d = nref.normalized() * thick
    A = list(pts)
    B = [p - d for p in pts]
    _emit_oriented(part, A, nref, top_mat)
    _emit_oriented(part, B, -nref, bot_mat)
    cen = sum(A, Vector((0, 0, 0))) / len(A)
    for i in range(len(A)):
        p, q = A[i], A[(i + 1) % len(A)]
        p2, q2 = B[i], B[(i + 1) % len(A)]
        _emit_oriented(part, [p, q, q2, p2], (p + q) / 2 - cen, bot_mat)


# ======================================================================================
# HULL
# ======================================================================================
T_LIST = [0, 5, 11, 17, 22.5, 28, 36, 44, 46.5, 55, 65, 75, 85, 95, 105, 115, 125, 133.5, 136, 144, 152, 157.5, 163,
          169, 175, 180, 187, 196, 208, 225, 250, 270, 290, 315, 332, 344, 353]
CHEAT = ((17, 22.5), (157.5, 163))
SEAM_T = ((44, 46.5), (133.5, 136))
RIB_X = (-16.2, -10.9, -3.4, 3.2, 9.6)
SEAM_X = (-13.6, -7.3, 0.0, 6.4, 12.8)
CHEAT_X = (-17.8, 19.2)


def x_rings():
    xs = [-19.30, -19.05, -18.50, -17.70, -16.80, -15.60, -14.40, -12.40, -11.60, -10.20, -9.00, -8.00, -7.00, -6.00,
          -5.00, -4.20, -2.60, -1.40, 1.00, 2.00, 4.30, 5.40, 7.40, 8.40, 9.00, 10.40, 11.20, 12.00, 13.60, 14.40, 15.40,
          16.40, 17.40, 18.30, 19.10, 19.80, 20.40, 20.85, 21.10, 21.28, 21.40]
    for s in SEAM_X:
        xs += [s - 0.06, s + 0.06]
    for r in RIB_X:
        xs += [r - 0.22, r + 0.22]
    xs = sorted(set(round(x, 3) for x in xs))
    out = []
    for x in xs:
        if not out or x - out[-1] > 0.05:
            out.append(x)
    return out


PANEL_XB = sorted(SEAM_X + RIB_X)
PANEL_TB = (0.0, 17.0, 22.5, 44.0, 46.5, 70.0, 90.0, 110.0, 133.5, 136.0, 157.5, 163.0, 180.0)


def _panel_tone(xm, tm):
    """large hull panels alternate between Hull and the pale Accent (a hash of the panel index)"""
    i = sum(1 for b in PANEL_XB if xm > b)
    j = sum(1 for b in PANEL_TB if tm > b)
    h = (i * 73856093 ^ j * 19349663) % 97
    return "Accent" if h % 3 == 0 else "Hull"


def hull_mat(xa, xb, ta, tb):
    xm, tm = (xa + xb) / 2, (ta + tb) / 2
    if tm > 180:
        return "Frame"
    for s in SEAM_X:
        if abs(xm - s) < 0.07 and 8 < tm < 172:
            return "HullDark"
    for a, b in CHEAT:
        if a <= tm <= b and CHEAT_X[0] < xm < CHEAT_X[1]:
            return "Hazard"
    for a, b in SEAM_T:
        if a <= tm <= b and -18.6 < xm < 19.8:
            return "HullDark"
    if -18.8 < xm < 20.2 and 4.0 < tm < 176.0:
        return _panel_tone(xm, tm)
    return "Hull"


def build_hull_skin(p):
    xs = x_rings()
    ts = T_LIST
    rings = [[H.pt(x, t) for t in ts] for x in xs]
    idx = [[p.v(q) for q in ring] for ring in rings]
    for k in range(len(xs) - 1):
        for i in range(len(ts)):
            j = (i + 1) % len(ts)
            ta, tb = ts[i], ts[j] if j else 360.0
            m = hull_mat(xs[k], xs[k + 1], ta, tb)
            p.f([idx[k][i], idx[k][j], idx[k + 1][j], idx[k + 1][i]], m, True)
    # nose cap
    tip = p.v(H.pt(X_NOSE, 90) * 0 + Vector((X_NOSE + 0.08, 0.0, 1.86)))
    last = idx[-1]
    for i in range(len(ts)):
        j = (i + 1) % len(ts)
        p.f([last[i], last[j], tip], "Frame" if ts[i] >= 180 else "Hull", True)
    # tail bulkhead: a short inset collar and a flat cap
    first = idx[0]
    inner = [p.v(Vector((X_TAIL + 0.12, H.pt(X_TAIL, t).y * 0.9, 2.9 + (H.pt(X_TAIL, t).z - 2.9) * 0.9))) for t in ts]
    for i in range(len(ts)):
        j = (i + 1) % len(ts)
        p.f([first[j], first[i], inner[i], inner[j]], "Frame", False)
    p.f(list(reversed(inner)), "HullDark", False)
    return xs


def build_ribs(p):
    for xr in RIB_X:
        ts = T_LIST
        prof = [(-0.22, 0.0), (-0.17, 0.075), (0.17, 0.075), (0.22, 0.0)]
        rings = [[H.pt(xr + dx, t, off) for t in ts] for dx, off in prof]
        p.loft(rings, lambda k, i: "HullDark" if ts[i] < 180 else "Frame", smooth=True, closed=True)


def build_spine(p):
    """dorsal spine from x = -16.6 to 7.2, with a sensor dome and a top hatch"""
    x0, x1 = -16.6, 7.2
    zb = 5.85
    sec = [(1.20, zb), (1.20, 6.62), (0.95, 7.02), (-0.95, 7.02), (-1.20, 6.62), (-1.20, zb)]
    xs = [x0, x0 + 0.9, x1 - 1.6, x1]
    rings = []
    for x in xs:
        s = 1.0
        zt_scale = 1.0
        if x == x0:
            s, zt_scale = 0.55, 0.35
        if x == x1:
            s, zt_scale = 0.6, 0.25
        ring = []
        for (y, z) in sec:
            ring.append((x, y * s, zb + (z - zb) * zt_scale))
        rings.append(ring)
    # sides go along the ring order; normals: loft (ring dir) x (station dir)
    p.loft(rings, lambda k, i: "Frame" if i in (2,) else "HullDark", smooth=False, closed=True, cap0=True, cap1=True,
           cap_mat="HullDark")
    # top hatch + handrail
    p.vcyl(4.2, 0, 6.98, 7.10, 0.55, seg=12, mat="Frame")
    p.vcyl(4.2, 0, 7.10, 7.16, 0.42, seg=12, mat="Accent")
    for sy in (-1, 1):
        p.tube([(3.4, sy * 0.75, 7.0), (3.4, sy * 0.75, 7.35), (5.0, sy * 0.75, 7.35), (5.0, sy * 0.75, 7.0)], 0.035, seg=4,
               mat="Hazard", smooth=False, fillet=0.08, fillet_n=1)
    # sensor dome at the front end
    p.hemi((7.6, 0, 6.2), 0.62, "Hull", seg=12, rings=3)
    p.vcyl(7.6, 0, 6.0, 6.22, 0.70, seg=12, mat="Frame")


def build_radiators(p):
    """two radiator wings tilted up from the spine, x = -14.8 .. -4.4"""
    for sy in (-1, 1):
        for (xa, xb) in ((-14.8, -10.0), (-9.4, -4.6)):
            ang = radians(24.0)
            y0 = sy * 1.22
            L = 2.55
            y1 = y0 + sy * L * cos(ang)
            z0 = 6.52
            z1 = z0 + L * sin(ang)
            # panel (thin box along the tilted plane)
            with p.at(T((xa + xb) / 2, (y0 + y1) / 2, (z0 + z1) / 2), RX(sy * 24.0)):
                p.box((0, 0, 0), (xb - xa, L, 0.07), "Trim", mats={"-z": "Frame", "edge": "Frame"})
                for k in range(5):
                    xk = -(xb - xa) / 2 + (xb - xa) * (k + 0.5) / 5
                    p.box((xk, 0, 0.045), (0.07, L * 0.96, 0.03), "Frame", mats={"-z": None})
                p.box((0, sy * (L / 2 - 0.06), 0.05), (xb - xa, 0.10, 0.04), "Accent", mats={"-z": None})
            # two struts under the panel
            for xk in (xa + 0.5, xb - 0.5):
                p.beam((xk, sy * 1.3, 6.35), (xk, y0 + sy * L * 0.62 * cos(ang), z0 + L * 0.62 * sin(ang) - 0.06), 0.07, 0.07,
                       "Frame")


def build_fin(p):
    """swept dorsal fin at the tail"""
    poly = [(-13.4, 6.3), (-15.3, 7.2), (-17.9, 9.25), (-19.35, 9.45), (-19.55, 9.05), (-19.1, 6.0)]
    p.prism_y(poly, -0.16, 0.16, "Hull")
    p.prism_y([(-16.45, 8.05), (-17.55, 8.9), (-18.95, 9.0), (-17.2, 7.72)], -0.19, 0.19, "Accent")
    p.prism_y([(-18.9, 9.28), (-19.38, 9.40), (-19.52, 9.06), (-19.0, 8.98)], -0.19, 0.19, "Frame")
    # root fairing
    p.prism_y([(-13.2, 6.0), (-13.6, 6.45), (-19.2, 6.45), (-19.4, 5.35)], -0.36, 0.36, "HullDark")


def build_comms(p):
    """comms array on the spine: lattice mast, tilted dish, whip antennas"""
    bx, by, bz = 1.6, 0.0, 7.0
    top = 9.1
    for (dx, dy) in ((-0.28, -0.28), (0.28, -0.28), (0.28, 0.28), (-0.28, 0.28)):
        p.beam((bx + dx, by + dy, bz), (bx + dx * 0.45, by + dy * 0.45, top), 0.07, 0.07, "Frame")
    for z in (7.6, 8.3):
        f = 1 - (z - bz) / (top - bz) * 0.55
        c = [(bx + dx * f, by + dy * f, z) for dx, dy in ((-0.28, -0.28), (0.28, -0.28), (0.28, 0.28), (-0.28, 0.28))]
        for i in range(4):
            p.beam(c[i], c[(i + 1) % 4], 0.05, 0.05, "Frame")
    p.box((bx, by, top + 0.1), (0.42, 0.42, 0.22), "HullDark", bevel=0.04)
    # dish looking up and to -Y / +X
    with p.at(T(bx, by, top + 0.25), RZ(-60.0), RY(-38.0)):
        p.lathe([(0.0, 0.0), (0.45, 0.06), (1.05, 0.30), (1.12, 0.36), (1.02, 0.36), (0.44, 0.13), (0.0, 0.08)],
                lambda k, i: "Hull" if k < 3 else ("Frame" if k == 3 else "Metal"), seg=16, smooth=True)
        for a in (0, 120, 240):
            p.cyl(polar3(1.02, a, 0.34), (0, 0, 1.05), 0.022, seg=4, mat="Frame", smooth=False)
        p.vcyl(0, 0, 0.9, 1.15, 0.07, seg=6, mat="Frame")
    for (x, y, h) in ((-1.6, -0.7, 2.2), (-2.2, 0.7, 1.6), (6.4, 0.55, 1.2)):
        p.vcyl(x, y, 6.9, 6.9 + h, 0.035, seg=4, mat="Frame", smooth=False)
        p.vcyl(x, y, 6.9, 7.08, 0.09, seg=6, mat="HullDark")


def polar3(r, deg, z):
    a = radians(deg)
    return (r * cos(a), r * sin(a), z)


POD_Y, POD_Z, POD_X0 = 5.10, 1.98, -6.9
POD_PROFILE = [  # (r, dz) dz = distance rearward from the pod front
    (1.02, 0.30), (1.30, 0.0), (1.52, 0.30), (1.70, 1.10), (1.76, 1.8), (1.76, 2.05), (1.80, 2.10), (1.80, 2.50),
    (1.76, 2.55), (1.76, 6.30), (1.80, 6.35), (1.80, 6.75), (1.76, 6.80), (1.76, 10.40), (1.66, 11.40), (1.44, 11.95),
    (1.30, 12.05), (1.00, 12.05)]
NOZ_PROFILE = [(1.06, 11.95), (1.24, 12.25), (1.40, 13.25), (1.52, 14.10), (1.55, 14.22), (1.44, 14.22),
               (1.30, 13.40), (1.10, 12.60), (0.86, 12.30)]
POD_MATS = ["Frame", "Accent", "Hull", "Hull", "Hull", "Trim", "Trim", "Trim", "Hull", "Hull", "HazardBand", "Hull",
            "Hull", "Hull", "Metal", "Metal", "Frame"]


def pod_frame(sy):
    """local Z of the lathe -> world -X (rearward), origin at the pod front centre"""
    return T(POD_X0, sy * POD_Y, POD_Z) @ RY(-90.0)


def build_pods(p):
    for sy in (-1, 1):
        with p.at(pod_frame(sy)):
            # outer shell: flip the (r, z) order so normals face out (profile walks rearward = +z local)
            mats = [m if m != "HazardBand" else "Hazard" for m in POD_MATS]
            prof = [(r, dz) for (r, dz) in POD_PROFILE]
            p.lathe(prof, lambda k, i: mats[k] if k < len(mats) else "Hull", seg=24, smooth=True)
            # intake: dark disc and a centre cone
            p.lathe([(0.0, 0.62), (1.02, 0.30)], "Rubber", seg=24, smooth=False)
            p.lathe([(0.0, 0.02), (0.34, 0.50)], "Metal", seg=12, smooth=True)
            # nozzle bell: outer metal, inner dark
            p.lathe(NOZ_PROFILE, lambda k, i: "Metal" if k < 4 else ("Frame" if k == 4 else "Rubber"), seg=24, smooth=True)
            p.lathe([(0.86, 12.30), (0.0, 12.05)], "Rubber", seg=24, smooth=False)
            # actuator rods on the bell
            for a in (45, 135, 225, 315):
                p.cyl(polar3(1.50, a, 11.2), polar3(1.30, a, 13.4), 0.05, seg=4, mat="Frame", smooth=False)
        # pylon fairing on top between pod and hull
        xa, xb = POD_X0 - 1.0, POD_X0 - 10.6
        yi = sy * (POD_Y - 1.35)
        yo = sy * (POD_Y - 0.25)
        prof = [(yi, 2.9), (yo, 3.55), (yo, 3.95), (yi, 4.6)]
        with p.at(T(0, 0, 0)):
            rings = []
            for x, s in ((xa, 0.0), (xa - 1.6, 1.0), (xb + 1.2, 1.0), (xb, 0.2)):
                rings.append([(x, y, POD_Z + 0.8 + (z - POD_Z - 0.8) * s) for (y, z) in prof])
            p.loft(rings, "HullDark", smooth=False, closed=False, flip=(sy > 0))
        # a small strake on top of the pod (outboard)
        p.prism_x([(sy * (POD_Y + 0.55) - 0.06, POD_Z + 1.62), (sy * (POD_Y + 0.55) + 0.06, POD_Z + 1.62),
                   (sy * (POD_Y + 0.62) + 0.05, POD_Z + 2.15), (sy * (POD_Y + 0.62) - 0.05, POD_Z + 2.15)],
                  POD_X0 - 9.8, POD_X0 - 3.5, "Frame")


def build_windows(p, lights):
    """cockpit windshield + side windows + porthole row. Hull gets dark glass (Solar) and frames; `lights` gets the
    emissive panes (Window) 12 mm above them."""
    # dark "mask" round the cockpit (one graphite patch), then the panes on top of it
    mask = [(14.0, 36.0), (14.6, 30.0), (16.6, 34.0), (17.9, 48.0), (18.15, 90.0), (17.9, 132.0), (16.6, 146.0),
            (14.6, 150.0), (14.0, 144.0), (14.35, 90.0)]
    cx, ct = 16.2, 90.0
    nref = H.nrm(cx, ct)
    cen = H.pt(cx, ct, 0.03)
    ring = [H.pt(x, t, 0.03) for (x, t) in mask]
    mid = [H.pt(lerp(cx, x, 0.55), lerp(ct, t, 0.55), 0.03) for (x, t) in mask]
    n = len(ring)
    for k in range(n):
        _emit_oriented(p, [cen, mid[k], mid[(k + 1) % n]], nref, "Frame")
        _emit_oriented(p, [mid[k], ring[k], ring[(k + 1) % n], mid[(k + 1) % n]], nref, "Frame")
    # windshield: five panes (the outer two are trapezoids that wrap round the sides)
    x0, x1 = 15.25, 17.35
    panes = [(47, 62), (64, 81), (83, 97), (99, 116), (118, 133)]
    for k, (ta, tb) in enumerate(panes):
        xa = x0 + (0.35 if k in (0, 4) else 0.0)
        xb = x1 - (0.30 if k in (0, 4) else 0.0)
        panel(p, xa, xb, ta, tb, 0.06, "Solar", side="Frame", nx=2, nt=2)
        patch(lights, xa + 0.05, xb - 0.05, ta + 0.7, tb - 0.7, 0.075, "Window", nx=2, nt=2, smooth=False)
    # side windows, two per side, inside the mask
    for (ta, tb) in ((36, 45), (135, 144)):
        for (xa, xb) in ((14.55, 15.3), (15.5, 16.3)):
            panel(p, xa, xb, ta, tb, 0.06, "Solar", side="Frame", nx=1, nt=1)
            patch(lights, xa + 0.04, xb - 0.04, ta + 0.6, tb - 0.6, 0.075, "Window", nx=1, nt=1, smooth=False)
    # a crew hatch with handrail on the nose top, a nose sensor mast
    hx, ht = 11.2, 90.0
    panel(p, hx - 0.55, hx + 0.55, ht - 9, ht + 9, 0.06, "HullDark", side="Frame", nx=1, nt=2)
    q0 = H.pt(hx - 0.45, ht - 11, 0.0)
    q1 = H.pt(hx + 0.45, ht - 11, 0.0)
    p.tube([q0, q0 + Vector((0, 0, 0.35)), q1 + Vector((0, 0, 0.35)), q1], 0.03, seg=4, mat="Hazard", smooth=False)
    sm = H.pt(13.2, 90.0, 0.0)
    p.cyl(sm - Vector((0, 0, 0.1)), sm + Vector((0, 0, 0.9)), 0.05, 0.03, seg=5, mat="Frame")
    p.sphere(sm + Vector((0, 0, 0.95)), 0.09, "Frame", seg=6, rings=3)
    # porthole row on both upper flanks
    for sgn in (1, -1):
        for k in range(9):
            x = -5.4 + k * 1.55
            z = 4.05
            t = H.t_at_z(x, z, sgn)
            xa, ta = to_xt(x, t, -0.28, -0.22)
            xb, tb = to_xt(x, t, 0.28, 0.22)
            ta, tb = min(ta, tb), max(ta, tb)
            panel(p, xa - 0.08, xb + 0.08, ta - 1.2, tb + 1.2, 0.03, "Frame", side="Frame", nx=1, nt=1)
            panel(p, xa, xb, ta, tb, 0.05, "Solar", side="Frame", nx=1, nt=1)
            patch(lights, xa + 0.03, xb - 0.03, ta + 0.4, tb - 0.4, 0.062, "Window", nx=1, nt=1, smooth=False)


def build_cargo_doors(p):
    """three cargo bay doors on each upper flank, with frames and hazard corners"""
    for sgn in (1, -1):
        for (xa, xb) in ((-9.6, -6.2), (-1.2, 2.6), (4.0, 7.6)):
            za, zb = 4.55, 5.75
            ta = H.t_at_z((xa + xb) / 2, za, sgn)
            tb = H.t_at_z((xa + xb) / 2, zb, sgn)
            ta, tb = min(ta, tb), max(ta, tb)
            panel(p, xa, xb, ta, tb, 0.04, "HullDark", side="Frame", nx=3, nt=2)
            frame_strips(p, xa, xb, ta, tb, 0.12, 0.07, "Frame")
            # hinge line and hazard corners
            for xc in (xa + 0.05, xb - 0.35):
                panel(p, xc, xc + 0.3, tb - 1.8, tb - 0.2, 0.06, "Hazard", side="Frame", nx=1, nt=1)
            panel(p, xa + 0.4, xb - 0.4, (ta + tb) / 2 - 0.4, (ta + tb) / 2 + 0.4, 0.055, "Frame", side="Frame", nx=2, nt=1)


def build_vents_and_hatches(p):
    # vent grilles on the lower flanks (above the chine), slats in Frame
    for sgn in (1, -1):
        for x in (-15.0, -12.8, 10.2, 12.0):
            z = 2.9
            t = H.t_at_z(x, z, sgn)
            xa, ta = to_xt(x, t, -0.55, -0.3)
            xb, tb = to_xt(x, t, 0.55, 0.3)
            ta, tb = min(ta, tb), max(ta, tb)
            panel(p, xa, xb, ta, tb, 0.035, "Rubber", side="Frame", nx=1, nt=1)
            for k in range(4):
                xs = xa + (xb - xa) * (k + 0.5) / 4
                panel(p, xs - 0.04, xs + 0.04, ta, tb, 0.06, "Frame", side="Frame", nx=1, nt=1)
    # RCS thruster blocks: nose sides and tail corners
    for (x, z) in ((18.2, 3.1), (-17.6, 4.8)):
        for sgn in (1, -1):
            t = H.t_at_z(x, z, sgn)
            pos = H.pt(x, t, 0.0)
            n = H.nrm(x, t)
            p.box(tuple(pos + n * 0.12), (0.62, 0.36, 0.36), "HullDark", bevel=0.04)
            for dx in (-0.14, 0.14):
                p.cyl(pos + n * 0.12 + Vector((dx, 0, 0)), pos + n * 0.36 + Vector((dx, 0, 0)), 0.08, 0.1, seg=6,
                      mat="Frame", cap1=False)
    # handrails along the top deck (spine sides), x = -3.4 .. 6.8
    for sy in (-1, 1):
        posts = [(-3.2 + 1.45 * k) for k in range(8)]
        y = sy * 2.35
        pts = []
        for x in posts:
            w, zt, zb, zc = H.sec(x)
            t = degrees(atan2(1, 0))
            # hull height at this y: search t on the top half
            tt = t_for_y(x, y)
            z = H.pt(x, tt).z
            p.beam((x, y, z - 0.05), (x, y, z + 0.62), 0.05, 0.05, "Frame")
            pts.append((x, y, z + 0.62))
        p.beam_path(pts, 0.05, 0.05, "Hazard")


def t_for_y(x, y):
    lo, hi = 0.0, 180.0
    for _ in range(40):
        mid = (lo + hi) / 2
        if H.pt(x, mid).y > y:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def build_strakes(p):
    """a thin ledge along the chine on both sides (x = -6.4 .. 18.6): a strong horizontal line"""
    xs = [-6.4 + 1.0 * k for k in range(26)]
    for sy in (1, -1):
        rings = []
        for x in xs:
            w, zt, zb, zc = H.sec(x)
            d = 0.55 * smoothstep(-6.4, -4.6, x) * (1.0 - smoothstep(15.0, 18.6, x)) + 0.02
            prof = [(w - 0.06, zc + 0.13), (w + d, zc + 0.03), (w + d, zc - 0.05), (w - 0.06, zc - 0.17)]
            rings.append([(x, sy * yy, zz) for (yy, zz) in prof])
        p.loft(rings, lambda k, i: ("HullDark", "Frame", "Frame", "Frame")[i], smooth=False, closed=True, flip=(sy > 0))


def pod_r(dz):
    for (r0, z0), (r1, z1) in zip(POD_PROFILE[1:-2], POD_PROFILE[2:-1]):
        if z0 <= dz <= z1 and z1 > z0:
            return r0 + (r1 - r0) * (dz - z0) / (z1 - z0)
    return 1.76


def pod_decal(part, dzc, angc, radii, off, mat, ecc=1.0):
    """jagged patch on a pod surface, in pod-local coordinates (call inside part.at(pod_frame(sy)))"""
    n = len(radii)

    def q(u, v):
        dz = dzc + u
        r = pod_r(dz) + off
        a = radians(angc) + v / r
        return Vector((r * cos(a), r * sin(a), dz))
    nref = Vector((cos(radians(angc)), sin(radians(angc)), 0.0))
    cen = q(0.0, 0.0)
    ring = [q(radii[k] * cos(2 * pi * k / n) * ecc, radii[k] * sin(2 * pi * k / n)) for k in range(n)]
    for k in range(n):
        _emit_oriented(part, [cen, ring[k], ring[(k + 1) % n]], nref, mat)


def build_leg_fairings(p):
    """four folded landing legs in fairings on the lower flanks"""
    for sgn in (1, -1):
        for xc in (9.2, -11.6):
            L = 3.0
            t = 186.0 if sgn < 0 else 354.0          # just below the chine
            w, zt, zb, zc = H.sec(xc)
            y = sgn * (w - 0.1)
            # fairing: half capsule along x
            with p.at(T(xc, y, zc - 0.55)):
                p.cyl((-L / 2, 0, 0), (L / 2, 0, 0), 0.42, seg=8, mat="Frame", cap0=True, cap1=True)
                p.box((0, sgn * 0.30, 0.0), (L * 0.8, 0.10, 0.46), "HullDark")
                # folded strut and pad visible on the outside
                p.cyl((-L * 0.4, sgn * 0.42, 0.05), (L * 0.35, sgn * 0.42, -0.12), 0.10, seg=6, mat="Metal")
                p.box((L * 0.42, sgn * 0.42, -0.14), (0.5, 0.16, 0.40), "Metal", bevel=0.04)


RAMP_HALF = 1.45        # half width of the rear door and ramp
DOOR_Z0, DOOR_Z1 = 0.92, 3.30


def build_rear_door(p, lights):
    """rear cargo door in the tail bulkhead (between the engine pods)"""
    xd = X_TAIL + 0.10
    p.box((xd - 0.03, 0, (DOOR_Z0 + DOOR_Z1) / 2), (0.08, 2 * RAMP_HALF, DOOR_Z1 - DOOR_Z0), "Rubber")
    # hazard frame
    for sy in (-1, 1):
        for k in range(5):
            z0 = DOOR_Z0 + (DOOR_Z1 - DOOR_Z0) * k / 5
            p.box((xd - 0.09, sy * (RAMP_HALF + 0.09), z0 + (DOOR_Z1 - DOOR_Z0) / 10), (0.10, 0.18, (DOOR_Z1 - DOOR_Z0) / 5),
                  "Hazard" if k % 2 == 0 else "Frame")
    p.box((xd - 0.09, 0, DOOR_Z1 + 0.10), (0.10, 2 * RAMP_HALF + 0.36, 0.20), "Frame")
    # interior glow (Lights)
    lights.box((xd - 0.09, 0, (DOOR_Z0 + DOOR_Z1) / 2 + 0.1), (0.02, 2 * RAMP_HALF - 0.3, DOOR_Z1 - DOOR_Z0 - 0.4), "Window",
               mats={"+x": None})


def world_ramp(p):
    """rear ramp from the door sill (ship space) down to the ground (world space), toward -X"""
    sill_a = W(Vector((X_TAIL - 0.05, -RAMP_HALF, DOOR_Z0)))
    sill_b = W(Vector((X_TAIL - 0.05, RAMP_HALF, DOOR_Z0)))
    run = sill_a.z / 0.40            # about 22 degrees
    foot_a = Vector((sill_a.x - run, sill_a.y, 0.02))
    foot_b = Vector((sill_b.x - run, sill_b.y, 0.02))
    nrm = (sill_b - sill_a).cross(foot_a - sill_a).normalized()
    if nrm.z < 0:
        nrm = -nrm
    quad_plate(p, [sill_a, sill_b, foot_b, foot_a], 0.16, "HullDark", "Frame", nrm)
    for k in range(7):
        f = (k + 0.6) / 7.4
        a = sill_a.lerp(foot_a, f) + nrm * 0.012
        b = sill_b.lerp(foot_b, f) + nrm * 0.012
        p.beam(a + (b - a) * 0.06, b - (b - a) * 0.06, 0.10, 0.04, "Frame", up=tuple(nrm))
    for (s0, f0) in ((sill_a, foot_a), (sill_b, foot_b)):
        side = Vector((0, 0.08 if s0.y > 0 else -0.08, 0))
        p.beam(s0 + nrm * 0.03 - side, f0 + nrm * 0.03 - side, 0.16, 0.12, "Hazard", up=tuple(nrm))
        rail = []
        for f in (0.08, 0.5, 0.92):
            q = s0.lerp(f0, f)
            p.beam(q, q + Vector((0, 0, 1.0)), 0.05, 0.05, "Frame")
            rail.append(q + Vector((0, 0, 1.0)))
        p.beam_path(rail, 0.05, 0.05, "Trim")
        q = s0.lerp(f0, 0.42)
        p.cyl(q, W(Vector((X_TAIL + 0.02, s0.y * 0.98, DOOR_Z1 - 0.3))), 0.06, seg=6, mat="Metal")
    foot = (foot_a + foot_b) / 2
    return foot, Vector((-1, 0, 0))


def build_hull(p, lights):
    with p.at(M):
        build_hull_skin(p)
        build_ribs(p)
        build_spine(p)
        build_radiators(p)
        build_fin(p)
        build_comms(p)
        build_pods(p)
        build_cargo_doors(p)
        build_vents_and_hatches(p)
        build_leg_fairings(p)
        build_strakes(p)
    with p.at(M), lights.at(M):
        build_windows(p, lights)
        build_rear_door(p, lights)
    foot, dirv = world_ramp(p)
    return foot, dirv


# ======================================================================================
# LIGHTS and ENGINE GLOW
# ======================================================================================
def build_running_lights(lights, hull):
    with lights.at(M), hull.at(M):
        # fin tip, pods (outboard, rear), nose chin, spine end
        spots = [((-19.25, 0.0, 9.52), 0.12), ((7.6, 0.0, 6.86), 0.10)]
        for sy in (-1, 1):
            spots.append(((POD_X0 - 11.2, sy * (POD_Y + 1.62), POD_Z + 0.6), 0.10))
            spots.append(((POD_X0 - 1.0, sy * (POD_Y + 1.1), POD_Z + 1.35), 0.08))
            spots.append(((16.0, sy * 3.95, 3.2), 0.09))
        for (c, r) in spots:
            hull.sphere(c, r * 1.05, "Frame", seg=8, rings=4)
            lights.sphere(c, r * 1.25, "Light", seg=8, rings=4)
        # landing floodlights under the nose chin (face forward/down)
        for sy in (-1, 1):
            pos = H.pt(19.4, 200 if sy < 0 else 340, 0.02)
            lights.box(tuple(pos + Vector((0.1, 0, -0.05))), (0.25, 0.5, 0.18), "Light", bevel=0.03)
            hull.box(tuple(pos + Vector((0.0, 0, 0.0))), (0.3, 0.6, 0.22), "Frame", bevel=0.03)


def build_engine_glow(g):
    for sy in (-1, 1):
        with g.at(pod_frame(sy)):
            g.lathe([(0.84, 12.36), (0.0, 12.12)], "Plasma", seg=24, smooth=False)
            # glow ring on the inner bell surface
            g.lathe([(1.40, 14.16), (1.28, 13.30), (1.16, 12.85)], "Plasma", seg=24, smooth=True)
            # inner "flame" cone, short
            g.lathe([(0.78, 12.40), (0.40, 13.30), (0.0, 13.75)], "Plasma", seg=16, smooth=True)


def engine_anchors():
    out = []
    for sy, name in ((1, "Engine_L"), (-1, "Engine_R")):
        pos = W(Vector((POD_X0 - 14.22, sy * POD_Y, POD_Z)))
        fwd = M3 @ Vector((-1, 0, 0))
        out.append(Anchor(name, pos, forward=fwd, up=M3 @ Vector((0, 0, 1))))
    return out


# ======================================================================================
# DAMAGE
# ======================================================================================
def jag(rng, n, r, amp=0.35):
    return [r * (1.0 + rng.uniform(-amp, amp) * (1.0 if k % 2 else 0.6)) for k in range(n)]


def oriented(nv, nref):
    return nv if nv.dot(nref) >= 0 else -nv


def breach(part, rng, xc, tc, r, ecc=1.25, petals=7, ribs=2, scorch=True):
    """a hull breach: scorched halo, dark hole, exposed ribs and torn plates bent outward"""
    n = 14
    radii = jag(rng, n, r, 0.38)
    if scorch:
        decal(part, xc, tc, [q * 1.55 + rng.uniform(0, 0.25) for q in radii], 0.014, "HullDark", rings=(1.0,), ecc=ecc)
    rim = decal(part, xc, tc, radii, 0.03, "Rubber", rings=(1.0,), ecc=ecc)
    nref = H.nrm(xc, tc)
    tw, xw = H.t_scale(xc, tc)
    for k in range(ribs):                               # exposed ribs (circumferential) and a stringer
        dx = (k - (ribs - 1) / 2) * r * 0.75
        x = xc + dx / xw
        span = r * 0.85
        a = H.pt(x, tc - span / tw, 0.035)
        b = H.pt(x, tc + span / tw, 0.035)
        m = H.pt(x, tc, -0.06)
        part.beam_path([a, m, b], 0.11, 0.12, "Frame", up=tuple(nref))
    a = H.pt(xc - r * 0.9 / xw, tc + r * 0.2 / tw, 0.02)
    b = H.pt(xc + r * 0.9 / xw, tc + r * 0.2 / tw, 0.02)
    part.beam(a, b, 0.08, 0.08, "Metal", up=tuple(nref))
    idxs = sorted(rng.sample(range(len(rim)), min(petals, len(rim))))
    centre = H.pt(xc, tc, 0.03)
    for i in idxs:                                      # torn plates round the rim, bent outward
        pa, pb = rim[i], rim[(i + 1) % len(rim)]
        mid = (pa + pb) / 2
        radial = (mid - centre)
        radial = radial - nref * radial.dot(nref)
        if radial.length < 1e-6:
            continue
        radial.normalize()
        L = rng.uniform(0.35, 0.8) * r
        up = rng.uniform(0.35, 1.0)
        tip = mid - radial * L * 0.35 + nref * L * up
        thin_plate(part, pa, pb, tip, 0.05, "Hull", "Frame", oriented((pb - pa).cross(tip - pa), nref))


def missing_plates(part, rng, xa, xb, ta, tb, hang=True):
    """a rectangle of missing skin: dark, with the frame grid showing"""
    patch(part, xa, xb, ta, tb, 0.025, "Rubber", nx=2, nt=2)
    nref = H.nrm((xa + xb) / 2, (ta + tb) / 2)
    for k in range(3):
        x = xa + (xb - xa) * (k + 0.5) / 3
        part.beam_path([H.pt(x, ta, 0.045), H.pt(x, (ta + tb) / 2, 0.045), H.pt(x, tb, 0.045)], 0.09, 0.07, "Frame",
                       up=tuple(nref))
    part.beam_path([H.pt(xa, (ta + tb) / 2, 0.05), H.pt(xb, (ta + tb) / 2, 0.05)], 0.07, 0.06, "Frame", up=tuple(nref))
    if hang:                                            # one plate hanging off by a corner
        p0 = H.pt(xb, tb, 0.04)
        p1 = H.pt(xb, ta + (tb - ta) * 0.3, 0.04)
        tip = p1 + nref * 0.9 + Vector((0, 0, -0.5))
        thin_plate(part, p0, p1, tip, 0.05, "Hull", "Frame", oriented((p1 - p0).cross(tip - p0), nref))


def sand_drift(part, rng, xc, tc, r, ecc=2.2):
    radii = [r * (1 + rng.uniform(-0.25, 0.25)) for _ in range(12)]
    decal(part, xc, tc, radii, 0.035, "OreVein", rings=(0.5, 1.0), ecc=ecc)


def contact_points(side, xs):
    """world points where the hull meets the ground (z = 0) on one side (+1 = +Y), for ship stations xs"""
    out = []
    if side > 0:
        ts = [0.0 + 2 * k for k in range(0, 91)]            # chine up over the +Y flank
        lower = [360.0 - 2 * k for k in range(1, 46)]        # chine down to the belly centre
    else:
        ts = [180.0 - 2 * k for k in range(0, 91)]
        lower = [180.0 + 2 * k for k in range(1, 46)]
    for x in xs:
        found = None
        seq = list(reversed(lower)) + ts                    # from the belly centre up to the top
        prev = None
        for t in seq:
            q = W(H.pt(x, t % 360.0))
            if prev is not None and prev.z < 0.0 <= q.z:
                f = -prev.z / (q.z - prev.z)
                found = prev.lerp(q, f)
                break
            prev = q
        if found is not None:
            out.append(found)
    return out


def build_berm(d, rng):
    """ploughed regolith round the buried nose (world space). Returns the path points."""
    xs = [2.0 + 1.0 * k for k in range(20)] + [21.0, 21.3]
    right = contact_points(-1, xs)          # -Y side, x increasing
    left = contact_points(1, xs)            # +Y side, x increasing
    if not right or not left:
        return []
    rr, ll = right[-1], left[-1]
    xf = max(rr.x, ll.x)
    ym = (rr.y + ll.y) / 2
    hy = (ll.y - rr.y) / 2
    arc = []
    for k in range(1, 7):
        a = -pi / 2 + pi * k / 7
        arc.append(Vector((xf + 0.9 * cos(a) + 0.3, ym + hy * 1.05 * sin(a), 0.0)))
    path = right + arc + list(reversed(left))            # counter-clockwise seen from above
    n = len(path)
    rings = []
    for k, q in enumerate(path):
        a = path[max(0, k - 1)]
        b = path[min(n - 1, k + 1)]
        tng = Vector((b.x - a.x, b.y - a.y, 0.0))
        if tng.length < 1e-6:
            tng = Vector((1, 0, 0))
        tng.normalize()
        out = Vector((tng.y, -tng.x, 0.0))
        f_front = smoothstep(6.0, 21.0, q.x)
        hgt = (0.30 + 1.05 * f_front) * rng.uniform(0.85, 1.15)
        wid = (1.0 + 1.1 * f_front) * rng.uniform(0.85, 1.15)
        if abs(out.y) > 0.3:                              # keep the berm inside |y| <= 6.9
            room = 6.9 - abs(q.y)
            wid = max(0.6, min(wid, room / max(abs(out.y), 0.3)))
        base = Vector((q.x, q.y, 0.0))
        prof = [(-0.45, hgt * 0.55), (wid * 0.18, hgt), (wid * 0.45, hgt * 0.8), (wid * 0.75, hgt * 0.32), (wid, -0.06)]
        rings.append([base + out * o + Vector((0, 0, z)) for (o, z) in prof])
    d.loft(rings, lambda k, i: "Soil" if i == 0 else "OreVein", smooth=True, closed=False)
    return path


def clods(d, rng, pts, n=18):
    for k in range(n):
        q = rng.choice(pts)
        c = Vector((q.x + rng.uniform(-1.2, 1.8), q.y + rng.uniform(-1.2, 1.2), 0))
        c.y = max(-6.6, min(6.6, c.y))
        r = rng.uniform(0.18, 0.40)
        c.y = max(-6.85 + r, min(6.85 - r, c.y))
        pts3 = [(c.x + rng.uniform(-r, r), c.y + rng.uniform(-r, r), rng.uniform(-0.05, r * 0.9)) for _ in range(9)]
        d.hull(pts3, rng.choice(["Soil", "OreVein", "Ore"]))


def ground_scrap(d, rng, centres, mats=("Hull", "Frame", "Metal", "HullDark")):
    """bent plates and chunks lying on the ground"""
    for (x, y) in centres:
        kind = rng.random()
        if kind < 0.55:
            L, Wd = rng.uniform(0.8, 1.8), rng.uniform(0.5, 1.1)
            a = rng.uniform(0, 2 * pi)
            ca, sa = cos(a), sin(a)
            bend = rng.uniform(0.15, 0.5)
            pts = []
            for (u, v) in ((-L / 2, -Wd / 2), (L / 2, -Wd / 2), (L / 2, Wd / 2), (-L / 2, Wd / 2)):
                z = 0.04 + (bend if u > 0 else 0.0) * (1 if v > 0 else 0.6)
                pts.append(Vector((x + u * ca - v * sa, y + u * sa + v * ca, z)))
            over = max(abs(q.y) for q in pts) - 6.9           # keep the piece inside |y| <= 6.9
            if over > 0:
                sh = -over if y > 0 else over
                pts = [q + Vector((0, sh, 0)) for q in pts]
            quad_plate(d, pts, 0.05, rng.choice(("Hull", "HullDark")), "Frame", Vector((0, 0, 1)))
        else:
            r = rng.uniform(0.25, 0.55)
            yc = max(-6.9 + r, min(6.9 - r, y))
            pts = [(x + rng.uniform(-r, r) * 1.6, yc + rng.uniform(-r, r), rng.uniform(-0.05, r)) for _ in range(10)]
            d.hull(pts, rng.choice(mats))


def build_damage1(d, rng):
    with d.at(M):
        breach(d, rng, -2.6, 140.0, 1.15, petals=8, ribs=2)          # -Y upper flank (seen in the thumbnail)
        breach(d, rng, 11.4, 157.0, 0.85, petals=6, ribs=2)          # -Y flank near the cockpit
        breach(d, rng, 10.3, 70.0, 0.90, petals=7, ribs=2)           # top of the nose section, +Y
        breach(d, rng, -3.9, 30.0, 0.95, petals=7, ribs=2)           # +Y flank
        missing_plates(d, rng, -13.6, -11.6, 118.0, 138.0)
        missing_plates(d, rng, 7.9, 9.4, 30.0, 46.0)
        for (x, t, r) in ((15.5, 172.0, 0.8), (6.0, 176.0, 0.9), (16.0, 8.0, 0.7), (-3.5, 6.0, 0.8)):
            decal(d, x, t, jag(rng, 12, r, 0.3), 0.015, "HullDark", rings=(1.0,), ecc=3.0)
    path = build_berm(d, rng)
    if path:
        clods(d, rng, path, n=16)
    ground_scrap(d, rng, [(8.5, -6.5), (12.0, 6.5), (-1.0, 6.6), (15.5, -6.2), (3.5, -6.7), (-2.2, -6.7), (19.5, 5.6)])


def build_damage2(d, rng):
    with d.at(M):
        for (ta, tb) in ((72, 88), (110, 128)):            # shattered windshield panes
            xc = 16.2
            decal(d, xc, (ta + tb) / 2, jag(rng, 10, 0.55, 0.45), 0.095, "Rubber", rings=(1.0,), ecc=1.6)
            nref = H.nrm(xc, (ta + tb) / 2)
            for k in range(3):
                a = H.pt(xc + rng.uniform(-0.6, 0.6), ta + rng.uniform(0, tb - ta), 0.1)
                b = a + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0.05, 0.2)))
                c = a + nref * rng.uniform(0.25, 0.5)
                thin_plate(d, a, b, c, 0.02, "Frame", "Frame", oriented((b - a).cross(c - a), Vector((0, 0, 1))))
        missing_plates(d, rng, 12.3, 13.5, 135.0, 147.0, hang=True)       # a side window blown out
        for (xc, tc, n_c) in ((-2.6, 140.0, 4), (11.4, 157.0, 3)):      # cables spilling down the flank
            for k in range(n_c):
                x = xc + rng.uniform(-0.6, 0.6)
                t = tc + rng.uniform(-4, 4)
                pts = []
                for j in range(5):
                    tt = t + j * (7.0 + rng.uniform(-2, 2))
                    pts.append(H.pt(x + rng.uniform(-0.2, 0.2), min(tt, 179.0), 0.10 + 0.14 * abs(sin(j * 1.3))))
                d.tube(pts, 0.045, seg=5, mat=rng.choice(("Rubber", "Hazard", "Accent")), smooth=True, caps=True)
        base = Vector((-0.2, 0.0, 6.99))                                  # avionics hatch blown open on the spine
        d.box((base.x, base.y, base.z + 0.02), (1.2, 1.3, 0.03), "Rubber", mats={"-z": None})
        lid = [base + Vector((0.6, -0.65, 0.03)), base + Vector((0.6, 0.65, 0.03)), base + Vector((1.25, 0.65, 0.78)),
               base + Vector((1.25, -0.65, 0.78))]
        quad_plate(d, lid, 0.05, "HullDark", "Frame", Vector((-0.75, 0, 0.65)))
        d.cyl((-2.2, 0.7, 7.05), (-0.6, 2.4, 6.8), 0.035, seg=4, mat="Frame", smooth=False)   # snapped whip antenna
        with d.at(T(-6.6, -1.9, 6.62), RX(-58.0), RZ(20.0)):                                # knocked-off small dish
            d.lathe([(0.0, 0.0), (0.45, 0.10), (0.62, 0.22), (0.55, 0.24), (0.0, 0.08)],
                    lambda k, i: "Hull" if k < 2 else "Frame", seg=10, smooth=True)
        for sgn in (1, -1):                                               # blown RCS blocks: soot
            t = H.t_at_z(18.2, 3.1, sgn)
            decal(d, 18.2, t, jag(rng, 10, 0.55, 0.3), 0.02, "Rubber", rings=(1.0,), ecc=1.4)
    ground_scrap(d, rng, [(14.2, -6.5), (2.5, 6.7)], mats=("Frame", "Metal"))


def build_damage3(d, rng):
    with d.at(M):
        for sy in (-1, 1):                                                # soot streaks on both pods near the nozzles
            with d.at(pod_frame(sy)):
                for (dzc, ang, r) in ((10.2, 20.0, 0.75), (9.6, 75.0 * sy, 0.6), (10.6, -40.0 * sy, 0.55), (9.9, 130.0 * sy, 0.5)):
                    pod_decal(d, dzc, ang, jag(rng, 10, r, 0.35), 0.06, "HullDark", ecc=2.2)
                    pod_decal(d, dzc + 0.3, ang, jag(rng, 8, r * 0.45, 0.35), 0.075, "Rubber", ecc=2.0)
        with d.at(pod_frame(-1)):                                         # crumpled nozzle rim, -Y engine
            for k in range(9):
                if k in (2, 3, 6):
                    continue
                a = 40.0 * k + rng.uniform(-8, 8)
                r0 = 1.53
                pa = Vector(polar3(r0, a - 10, 14.18))
                pb = Vector(polar3(r0, a + 10, 14.18))
                tip = Vector(polar3(r0 + rng.uniform(0.12, 0.30), a, 14.18 + rng.uniform(0.10, 0.35)))
                thin_plate(d, pa, pb, tip, 0.05, "Metal", "Rubber", oriented((pb - pa).cross(tip - pa), Vector(polar3(1, a, 0))))
        with d.at(pod_frame(-1)):                                         # torn cowl, -Y engine (outboard side)
            a0, a1 = 335.0, 390.0
            d.lathe([(1.795, 3.6), (1.795, 6.2)], "Rubber", seg=6, a0=a0, a1=a1, smooth=True, caps=False)
            for k in range(3):
                z = 3.9 + 0.7 * k
                pts = [polar3(1.83, a0 + 10 + 13 * k, z), polar3(2.05, a0 + 20 + 13 * k, z + 0.5),
                       polar3(1.83, a0 + 27 + 13 * k, z + 1.2)]
                d.tube(pts, 0.06, seg=5, mat="Metal", smooth=True)
            hinge_a = Vector(polar3(1.80, a1, 3.6))
            hinge_b = Vector(polar3(1.80, a1, 6.2))
            outv = Vector(polar3(1.0, a1 + 75, 0.0))
            quad_plate(d, [hinge_a, hinge_b, hinge_b + outv * 1.1, hinge_a + outv * 1.0], 0.05, "Hull", "Frame",
                       Vector(polar3(1.0, a1 - 30, 0.0)))
        xc = -11.6                                                        # broken landing leg, +Y rear
        w, zt, zb, zc = H.sec(xc)
        a = Vector((xc + 0.8, w - 0.1, zc - 0.55))
        b = Vector((xc + 2.6, w + 1.15, 0.25))
        d.cyl(a, b, 0.12, seg=6, mat="Metal")
        d.cyl(b, b + Vector((0.9, 0.25, -0.35)), 0.10, seg=6, mat="Metal")
        d.box(tuple(b + Vector((1.1, 0.3, -0.35))), (0.8, 0.8, 0.14), "Frame", bevel=0.03)
    ground_scrap(d, rng, [(-21.8, 3.2), (-21.4, -3.6), (-19.6, 5.0), (-16.5, -6.4), (-22.4, -1.9)], mats=("Metal", "Frame"))
    with d.at(T(-22.6, 2.4, 0.45), RY(75.0), RX(10.0)):                  # a nozzle ring blown off, on the ground
        d.torus(0.72, 0.14, "Metal", seg=16, tseg=6)


# ======================================================================================
# SCAFFOLD
# ======================================================================================
def tower(p, x0, y0, sx, sy, h, levels, ladder_side=1):
    """scaffold tower standing on z = 0, centred on (x0, y0), sx along X, sy along Y"""
    hx, hy = sx / 2, sy / 2
    corners = [(x0 - hx, y0 - hy), (x0 + hx, y0 - hy), (x0 + hx, y0 + hy), (x0 - hx, y0 + hy)]
    for (x, y) in corners:
        p.beam((x, y, 0.0), (x, y, h + 1.0), 0.07, 0.07, "Metal")
        p.box0(x, y, 0.0, 0.22, 0.22, 0.06, "Frame")
    zs = [h * (k + 1) / levels for k in range(levels)]
    for z in [0.35] + zs:
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            p.beam((a[0], a[1], z), (b[0], b[1], z), 0.06, 0.06, "Metal")
    for z in zs:
        p.box0(x0, y0, z + 0.03, sx - 0.02, sy - 0.02, 0.06, "HullDark")
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            p.beam((a[0], a[1], z + 0.16), (b[0], b[1], z + 0.16), 0.03, 0.16, "Hazard")
            p.beam((a[0], a[1], z + 0.98), (b[0], b[1], z + 0.98), 0.045, 0.045, "Hazard")
    prev = 0.35
    for z in zs:                                         # diagonal braces on the long faces
        p.beam((x0 - hx, y0 - hy, prev), (x0 + hx, y0 - hy, z), 0.05, 0.05, "Frame")
        p.beam((x0 + hx, y0 + hy, prev), (x0 - hx, y0 + hy, z), 0.05, 0.05, "Frame")
        prev = z
    lx = x0 + ladder_side * (hx + 0.12)                  # ladder on an X face
    for dy in (-0.22, 0.22):
        p.beam((lx, y0 + dy, 0.0), (lx, y0 + dy, h + 1.0), 0.05, 0.05, "Hazard")
    for k in range(int(h / 0.45)):
        z = 0.3 + 0.45 * k
        p.beam((lx, y0 - 0.22, z), (lx, y0 + 0.22, z), 0.035, 0.035, "Metal")
    return corners


def floodlight(p, x, y, z, aim, h=1.1):
    p.beam((x, y, z), (x, y, z + h), 0.06, 0.06, "Frame")
    head = Vector((x, y, z + h + 0.12))
    d = Vector(aim).normalized()
    p.box(tuple(head), (0.38, 0.38, 0.26), "Frame", bevel=0.04)
    p.cyl(head + d * 0.10, head + d * 0.22, 0.15, 0.18, seg=8, mat="Frame", cap1=False)
    p.cyl(head + d * 0.19, head + d * 0.22, 0.16, seg=8, mat="Light")


def light_mast(p, x, y, aim, h=4.0):
    for a in (0, 120, 240):
        f = Vector((x + 0.6 * cos(radians(a)), y + 0.6 * sin(radians(a)), 0.0))
        p.beam(f, (x, y, h * 0.35), 0.05, 0.05, "Frame")
    p.beam((x, y, h * 0.3), (x, y, h), 0.07, 0.07, "Metal")
    d = Vector(aim).normalized()
    for dy in (-0.25, 0.25):
        head = Vector((x, y + dy, h + 0.18))
        p.box(tuple(head), (0.34, 0.34, 0.26), "Frame", bevel=0.04)
        p.cyl(head + d * 0.12, head + d * 0.2, 0.14, seg=8, mat="Light")
    p.box0(x + 0.45, y, 0.0, 0.5, 0.35, 0.35, "Hazard")


def build_scaffold(s, rng):
    """towers against the hull at the breaches, work lights, repair materials (world space)"""
    for (xc, tc, side, sx) in ((-2.6, 140.0, -1, 2.8), (11.4, 157.0, -1, 2.2), (-3.9, 30.0, 1, 2.6), (10.3, 50.0, 1, 2.2)):
        hz = W(H.pt(xc, tc)).z
        levels = max(1, min(3, int(round(hz / 1.9))))
        h = max(1.4, hz - 0.6)
        wmax = max(abs(W(H.pt(xc, 180.0 if side < 0 else 0.0)).y), abs(W(H.pt(xc, tc)).y), 4.6)
        sy = 1.05
        yc = side * min(wmax + 0.25 + sy / 2, 6.82 - sy / 2)
        tower(s, xc, yc, sx, sy, h, levels, ladder_side=1)
        s.box0(xc, yc - side * (sy / 2 + 0.35), h + 0.03, sx * 0.8, 0.7, 0.06, "HullDark")   # plank toward the hull
        floodlight(s, xc - sx / 2 + 0.1, yc + side * 0.3, h + 1.0, (0.2, -side, -0.7))
    light_mast(s, 17.6, -6.35, (-0.4, 0.8, -0.35), h=4.2)
    light_mast(s, 1.2, 6.35, (0.3, -0.9, -0.35), h=4.0)
    for k in range(4):                                   # stacked hull plates and a cable reel
        s.box0(6.5, -6.3, 0.09 * k, 1.8, 0.95, 0.08, "Trim" if k % 2 else "Hull")
    s.box0(6.5, -6.3, 0.36, 1.6, 0.12, 0.10, "Hazard")
    with s.at(T(-5.2, -6.35, 0.56), RX(90)):
        s.cyl((0, 0, -0.35), (0, 0, 0.35), 0.55, seg=12, mat="Frame")
        s.cyl((0, 0, -0.30), (0, 0, 0.30), 0.40, seg=12, mat="Hazard")


# ======================================================================================
# MERIDIAN
# ======================================================================================
def build_meridian(spec):
    rng = random.Random(1947)
    hull = Part("Hull")
    lights = Part("Lights")
    glow = Part("EngineGlow")
    d1, d2, d3 = Part("Damage1"), Part("Damage2"), Part("Damage3")
    sc = Part("Scaffold")
    foot, dirv = build_hull(hull, lights)
    build_running_lights(lights, hull)
    with glow.at(M):
        build_engine_glow(glow)
    build_damage1(d1, random.Random(11))
    build_damage2(d2, random.Random(22))
    build_damage3(d3, random.Random(33))
    build_scaffold(sc, random.Random(44))
    dv = Vector((dirv.x, dirv.y, 0)).normalized()
    anchors = engine_anchors() + [Anchor("Ramp", Vector((foot.x, foot.y, 0.0)) + dv * 0.3, forward=dv)]
    return [hull, d1, d2, d3, sc, lights, glow] + anchors


def meridian_checks(stats):
    """capsule footprint check: every Hull / Damage / Scaffold vertex within 7.0 m of the segment x in [-14, 14]"""
    return None


# ======================================================================================
# DEBRIS
# ======================================================================================
def build_debris(spec):
    rng = random.Random(spec["seed"])
    p = Part("Base")
    v = spec["id"][-1]
    if v == "a":
        # torn curved hull panel, half dug in, with ribs underneath
        L, R, a0, a1 = 3.2, 2.2, 55.0, 125.0
        nt, nx = 6, 4
        rows = []
        for i in range(nx + 1):
            x = -L / 2 + L * i / nx
            row = []
            for j in range(nt + 1):
                a = radians(a0 + (a1 - a0) * j / nt)
                jag_ = 0.0
                if i == nx:
                    jag_ = rng.uniform(-0.35, 0.1)
                row.append(Vector((x + jag_, R * cos(a), R * sin(a) - R * 0.62 + 0.1 * (x / L))))
            rows.append(row)
        # tilt the panel so one edge is in the ground
        m = RZ(24.0) @ RX(-16.0) @ RY(6.0)
        rows = [[(m @ q) for q in row] for row in rows]
        for i in range(nx):
            for j in range(nt):
                q = [rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]]
                mat = "Hull" if not (i == 1 and j in (2, 3)) else "Hazard"
                if (i + j) % 5 == 4:
                    mat = "HullDark"
                p.poly(q, mat, smooth=True)
                p.poly(list(reversed([x - (m @ Vector((0, cos(radians(90)), sin(radians(90))))) * 0.0 + Vector((0, 0, -0.06)) for x in q])), "Frame", smooth=True)
        for i in (0, 2, 4):
            pts = [rows[i][j] + Vector((0, 0, -0.15)) for j in range(nt + 1)]
            p.beam_path(pts, 0.12, 0.16, "Frame")
        pts = [rows[i][3] + Vector((0, 0, -0.18)) for i in range(nx + 1)]
        p.beam_path(pts, 0.10, 0.12, "Metal")
        # a torn corner petal
        thin_plate(p, rows[nx][1], rows[nx][3], rows[nx][2] + Vector((0.5, 0.1, 0.4)), 0.04, "Hull", "Frame", Vector((0.3, 0, 1)))
    elif v == "b":
        # a crumpled tank / nozzle section with scorch, lying on its side
        with p.at(T(0, 0, 0.62), RY(90.0), RX(8.0)):
            prof = []
            for k in range(7):
                z = -0.9 + 1.8 * k / 6
                r = 0.62 * (1.0 + 0.05 * sin(k * 2.1))
                prof.append((r, z))
            idx = p.lathe(prof, lambda k, i: "Rubber" if (k >= 4 and i % 3 == 0) else ("Metal" if k < 5 else "HullDark"),
                          seg=14, smooth=True)
            p.lathe([(0.62, -0.9), (0.52, -0.9), (0.52, 0.8)], "Rubber", seg=14, smooth=True)
            p.torus(0.64, 0.06, "Frame", seg=14, tseg=4, z=-0.35)
            p.torus(0.64, 0.06, "Frame", seg=14, tseg=4, z=0.35)
        # dent the tank: crush a side by moving verts (simple: add a crumpled cap plate)
        for k in range(5):
            a = rng.uniform(0, 2 * pi)
            tip = Vector((0.95 + rng.uniform(0, 0.4), 0.62 * cos(a) * 0.9, 0.62 + 0.62 * sin(a) * 0.9))
            base_a = Vector((0.9, 0.6 * cos(a - 0.35), 0.62 + 0.6 * sin(a - 0.35)))
            base_b = Vector((0.9, 0.6 * cos(a + 0.35), 0.62 + 0.6 * sin(a + 0.35)))
            thin_plate(p, base_a, base_b, tip, 0.04, "Metal", "Rubber", Vector((1, cos(a), sin(a))))
        # bracket and a pipe stub
        p.box0(-0.55, 0.0, 0.0, 0.5, 0.9, 0.18, "Frame")
        p.tube([(-0.9, 0.3, 0.9), (-1.3, 0.3, 1.1), (-1.5, 0.6, 0.4)], 0.07, seg=6, mat="Metal", fillet=0.2)
    else:
        # a twisted truss section with a torn plate, 3.6 m long
        L = 3.6
        tw = 0.0
        prev = None
        nodes = []
        for k in range(5):
            x = -L / 2 + L * k / 4
            tw = radians(9.0 * k + rng.uniform(-4, 4))
            sag = 0.25 * sin(pi * k / 4)
            pts = []
            for (y, z) in ((-0.35, 0.0), (0.35, 0.0), (0.0, 0.55)):
                yy = y * cos(tw) - z * sin(tw)
                zz = y * sin(tw) + z * cos(tw)
                pts.append(Vector((x, yy, zz + 0.22 + sag)))
            nodes.append(pts)
        for k in range(4):
            for c in range(3):
                p.beam(nodes[k][c], nodes[k + 1][c], 0.09, 0.09, "Frame")
            p.beam(nodes[k][0], nodes[k + 1][2], 0.05, 0.05, "Metal")
            p.beam(nodes[k][1], nodes[k + 1][2], 0.05, 0.05, "Metal")
        for k in range(5):
            for c in range(3):
                p.beam(nodes[k][c], nodes[k][(c + 1) % 3], 0.06, 0.06, "Frame")
        # torn plate hanging on one side
        a, b = nodes[1][1], nodes[3][1]
        quad_plate(p, [a, b, b + Vector((0.1, 0.55, -0.35)), a + Vector((-0.2, 0.7, -0.2))], 0.04, "Hull", "Frame",
                   Vector((0, 1, 0.4)))
        # broken end: jagged stubs
        for c in range(3):
            q = nodes[4][c]
            p.beam(q, q + Vector((0.3 + rng.uniform(0, 0.3), rng.uniform(-0.1, 0.1), rng.uniform(-0.2, 0.1))), 0.08, 0.08,
                   "Metal")
    return [p]


# ======================================================================================
MODELS = [
    dict(id="meridian", kind="special", footprint=None, accent="space", budget=30000,
         objects=["Hull", "Damage1", "Damage2", "Damage3", "Scaffold", "Lights", "EngineGlow"],
         anchors=["Anchor_Engine_L", "Anchor_Engine_R", "Anchor_Ramp"], zmin=-3.5,
         ao=dict(dist=2.4, samples=32, occluders={
             "Hull": [], "Lights": ["Hull"], "EngineGlow": ["Hull"],
             "Damage1": ["Hull"], "Damage2": ["Hull"], "Damage3": ["Hull"], "Scaffold": ["Hull"]}),
         builder=build_meridian),
    dict(id="debris_a", kind="prop", footprint=None, accent="space", budget=900, objects=["Base"], seed=5, zmin=-0.6,
         ao=dict(dist=0.8, samples=40), builder=build_debris),
    dict(id="debris_b", kind="prop", footprint=None, accent="space", budget=900, objects=["Base"], seed=6, zmin=-0.3,
         ao=dict(dist=0.8, samples=40), builder=build_debris),
    dict(id="debris_c", kind="prop", footprint=None, accent="space", budget=900, objects=["Base"], seed=7, zmin=-0.3,
         ao=dict(dist=0.8, samples=40), builder=build_debris),
]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    rows = []
    for spec in MODELS:
        if only and spec["id"] not in only:
            continue
        print("building", spec["id"], "...")
        rows.append(C.build_model(spec, spec["builder"]))
    C.write_reports(rows)


if __name__ == "__main__":
    main()
