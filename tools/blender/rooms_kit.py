"""
Frontier Habitat 2.0 - ART-A room kit (Blender 5.2, always --background).

Shared by tools/blender/rooms_*.py:
  * materials: the v1 list + the 2.0 list; `Accent` and `Neon` take the category colour of the file
  * P: the v1 Part geometry builder (build_assets.Part) + column lathes, frames and small details
  * Room: round base (foundation ring, floor, wall to 1.40 m), dome and podium roof shells,
    surface queries to place parts, the interior head-room check
  * upgrade parts L2..L5: standard pieces and a default placement per shell
  * furniture and machine props for the interiors
  * vertex-colour AO (BVH ray cast per face corner -> COLOR_0), atomic GLB export, GLB inspection

Conventions (docs/AAA_DESIGN.md section 11): metres, Blender Z up, front +X, doors +X, origin at ground
level at the footprint centre.  Blender (x, y, z) -> glTF / Godot (x, z, -y).
Triangle budgets (all objects, L2..L5 included): S 3000, M 4500, L 6500, XL 9000.  So: no bevels on small
props, 6..8 sided small cylinders, single-face level bands.
"""
import bpy
import os
import sys
import json
import math
import struct
import random
import time
import warnings
from math import sin, cos, pi, radians, degrees, sqrt, atan2, asin, acos, hypot
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

warnings.filterwarnings("ignore", category=DeprecationWarning)

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import build_assets as BA                                             # noqa: E402
from build_assets import T, RX, RY, RZ, S, polar, dome_profile          # noqa: E402,F401

ROOT = BA.ROOT
MODEL_DIR = os.path.join(ROOT, "assets", "models")
THUMB_DIR = os.path.join(ROOT, "assets", "thumbs")
PREVIEW_DIR = os.path.join(HERE, "previews", "rooms")
CONTENT_BUILDINGS = os.path.join(ROOT, "content", "buildings.json")
REPORT_JSON = os.path.join(HERE, "build_report.json")
REPORT_MD = os.path.join(HERE, "build_report.md")

FLOOR_Z = 0.14          # top of the floor (same as v1 and the corridor)
WALL_TOP = 1.40         # the round wall (Base) stops here; everything above is Roof
WALL_T = 0.20
SOIL_Z = 0.55           # greenhouse / fungus tray soil top
MARGIN = 0.10           # model stays this far inside the footprint circle
SIZE_KEYS = ("s", "m", "l", "xl")
BUDGET = (3000, 4500, 6500, 9000)
LEVELS = ("L2", "L3", "L4", "L5")
F = FLOOR_Z


def load_buildings():
    with open(CONTENT_BUILDINGS, "r", encoding="utf-8") as fh:
        return json.load(fh)


# --------------------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------------------
ACCENTS = dict(BA.ACCENTS)
MATERIALS = dict(BA.MATERIALS)          # build_assets.py holds the v1 list + the 2.0 list
PER_FILE = ("Accent", "Neon")
EMISSIVE = {n for n, s in MATERIALS.items() if "emit" in s} | {"Neon"}
NON_OCCLUDING = {"Glass"}               # transparent: does not shade other faces in the AO bake


class MatSet:
    """One set per exported file: Accent and Neon take the category colour."""

    def __init__(self, accent_hex):
        self.accent_hex = accent_hex
        self.cache = {}

    def spec(self, name):
        if name == "Accent":
            return dict(color=self.accent_hex, rough=0.55)
        if name == "Neon":
            return dict(color=self.accent_hex, rough=0.40, emit=self.accent_hex, emit_strength=3.0)
        return MATERIALS[name]

    def get(self, name):
        if name not in self.cache:
            self.cache[name] = BA.make_material(name, self.spec(name))
        return self.cache[name]


# --------------------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------------------
def frame_m(pos, z=(0.0, 0.0, 1.0), x=(1.0, 0.0, 0.0)):
    """Matrix whose local Z = z, local X = x (made perpendicular), origin = pos."""
    zv = Vector(z).normalized()
    xv = Vector(x)
    xv = xv - zv * xv.dot(zv)
    if xv.length < 1e-6:
        xv = Vector((1, 0, 0)) if abs(zv.x) < 0.9 else Vector((0, 1, 0))
        xv = xv - zv * xv.dot(zv)
    xv.normalize()
    yv = zv.cross(xv)
    return Matrix(((xv.x, yv.x, zv.x, pos[0]), (xv.y, yv.y, zv.y, pos[1]), (xv.z, yv.z, zv.z, pos[2]), (0, 0, 0, 1)))


def ang_diff(a, b):
    return abs(((a - b + 180.0) % 360.0) - 180.0)


def columns(seg, seams=(), seam_w=1.0, phase=0.0):
    """Column angles (degrees) for a full-circle lathe: `seg` regular columns plus a narrow strip of
    width `seam_w` degrees at each seam angle.  Returns (angles, kind, is_seam_col):
    kind[i] = 's' when the quad from column i to column i+1 is a seam strip, else 'p'."""
    step = 360.0 / seg
    cols = []
    seams = [s % 360.0 for s in seams]
    for k in range(seg):
        a = ((k + 0.5) * step + phase) % 360.0
        if any(ang_diff(a, s) < seam_w * 0.5 + step * 0.22 for s in seams):
            continue
        cols.append((a, "p"))
    for s in seams:
        cols.append(((s - seam_w / 2.0) % 360.0, "s0"))
        cols.append(((s + seam_w / 2.0) % 360.0, "s1"))
    cols.sort(key=lambda c: c[0])
    angles = [c[0] for c in cols]
    kind = ["s" if c[1] == "s0" else "p" for c in cols]
    is_seam_col = [c[1] in ("s0", "s1") for c in cols]
    return angles, kind, is_seam_col


def reg_angles(seg, phase=0.5):
    return [360.0 * (k + phase) / seg for k in range(seg)]


def col_mid_fn(cols):
    n = len(cols)

    def mid(i):
        a0 = cols[i]
        a1 = cols[(i + 1) % n] + (360.0 if i == n - 1 else 0.0)
        return (0.5 * (a0 + a1)) % 360.0
    return mid


def hexagon(r, rot=30.0, cx=0.0, cy=0.0):
    return [(cx + r * cos(radians(rot + 60 * k)), cy + r * sin(radians(rot + 60 * k))) for k in range(6)]


def ngon(r, n, rot=0.0, cx=0.0, cy=0.0):
    return [(cx + r * cos(radians(rot + 360.0 * k / n)), cy + r * sin(radians(rot + 360.0 * k / n))) for k in range(n)]


def radial_fit(Ri, half_len, half_w, margin=0.04):
    """Centre radius of a rectangle placed radially (long side along the radius) whose outer end is as close
    to the inner wall as possible: (r + half_len)^2 + half_w^2 <= (Ri - margin)^2."""
    return sqrt(max(0.0, (Ri - margin) ** 2 - half_w ** 2)) - half_len


def tangent_fit(Ri, half_depth, half_w, margin=0.04):
    """Centre radius of a rectangle placed tangentially (back to the wall)."""
    return sqrt(max(0.0, (Ri - margin) ** 2 - half_w ** 2)) - half_depth


class P(BA.Part):
    """v1 Part + helpers.  Every method respects the transform stack (`with p.at(...)`)."""

    def quad(self, a, b, c, d, mat, smooth=False):
        self.f([self.v(a), self.v(b), self.v(c), self.v(d)], mat, smooth)

    def tri(self, a, b, c, mat, smooth=False):
        self.f([self.v(a), self.v(b), self.v(c)], mat, smooth)

    def lathe_a(self, profile, angles, mat, smooth=True, closed=True, offs=None):
        """Surface of revolution about local Z with explicit column angles (degrees, ascending).
        Walk the (r, z) profile up the outside, inward over the top, down the inside (outward normals).
        closed: the last column joins the first (full circle).  mat: name or fn(k, i) -> name / None.
        offs: fn(ring k, column i) -> (dr, dz) added to that vertex."""
        rings = []
        for kr, (r, z) in enumerate(profile):
            if r < 1e-6:
                rings.append([(0.0, 0.0, z)])
                continue
            ring = []
            for i, a in enumerate(angles):
                dr, dz = offs(kr, i) if offs else (0.0, 0.0)
                ar = radians(a)
                ring.append(((r + dr) * cos(ar), (r + dr) * sin(ar), z + dz))
            rings.append(ring)
        return self.loft(rings, mat, smooth, closed=closed)

    def ring_solid(self, r0, r1, z0, z1, mat, seg=24, top=None, inner=True):
        """Annular solid (outer face, top, optional inner face)."""
        prof = [(r1, z0), (r1, z1), (r0, z1)]
        if inner:
            prof.append((r0, z0))
        mats = [mat, top or mat, mat]
        self.lathe_a(prof, reg_angles(seg), lambda k, i: mats[k], smooth=False)

    def cap_disc(self, r, z, mat, seg=16, up=True):
        if up:
            self.lathe([(r, z), (0.0, z)], mat, seg=seg, smooth=False)
        else:
            self.lathe([(0.0, z), (r, z)], mat, seg=seg, smooth=False)

    def plate(self, poly, z, mat, up=True):
        """Flat polygon at height z (a painted plate / decal)."""
        area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                   for i in range(len(poly)))
        pts = list(poly) if (area > 0) == up else list(reversed(poly))
        self.f([self.v((x, y, z)) for x, y in pts], mat)

    def slab(self, x, y, z0, sx, sy, sz, mat, yaw=0.0, mats=None):
        """Box standing on z0 without its bottom face (10 triangles)."""
        mm = {"-z": None}
        if mats:
            mm.update(mats)
        if yaw:
            with self.at(T(x, y, 0), RZ(yaw)):
                self.box0(0, 0, z0, sx, sy, sz, mat, mats=mm)
        else:
            self.box0(x, y, z0, sx, sy, sz, mat, mats=mm)


# --------------------------------------------------------------------------------------
# Small details
# --------------------------------------------------------------------------------------
def porthole(p, pos, nor, r, rim=0.07, depth=0.08, seg=8, glow="Window", frame="Frame"):
    pos, nor = Vector(pos), Vector(nor).normalized()
    p.cyl(pos - nor * 0.10, pos + nor * depth, r + rim, seg=seg, mat=frame, cap0=False, phase=pi / seg)
    p.cyl(pos, pos + nor * (depth + 0.012), r, seg=seg, mat=None, cap_mat=glow, cap0=False, phase=pi / seg)


def bolts_ring(p, r, z, n, size=0.07, h=0.035, mat="Metal", a0=0.0, skip=None):
    for k in range(n):
        a = a0 + 360.0 * k / n
        if skip and any(ang_diff(a, s[0]) < s[1] for s in skip):
            continue
        with p.at(RZ(a), T(r, 0, z)):
            p.box0(0, 0, 0, size, size, h, mat, mats={"-z": None})


def lamp(pb, pl, pos, out, up=(0, 0, 1), w=0.22, h=0.12, d=0.10, lens="Light"):
    """Wall lamp: housing (Frame) in part pb, lens (emissive) in part pl.  out = outward direction."""
    out = Vector(out).normalized()
    m = frame_m(pos, out, up)          # local Z = outward, local X = up
    with pb.at(m):
        pb.box((0, 0, d / 2), (h, w, d), "Frame", mats={"-z": None})
    with pl.at(m):
        pl.box((0, 0, d + 0.006), (h * 0.62, w * 0.78, 0.012), lens, mats={"-z": None})


def antenna(p, x, y, z, h, mat="Trim", yaw=0.0):
    with p.at(T(x, y, z), RZ(yaw)):
        p.box0(0, 0, -0.12, 0.30, 0.30, 0.16, "Frame", mats={"-z": None})
        p.beam((0, 0, 0.0), (0, 0, h), 0.07, 0.07, mat, caps=False)
        p.beam((-0.28, 0, h * 0.62), (0.28, 0, h * 0.62), 0.035, 0.035, mat)
        p.beam((0, -0.2, h * 0.82), (0, 0.2, h * 0.82), 0.03, 0.03, mat)
        p.beam((0, 0, h), (0, 0, h + 0.4), 0.02, 0.02, "Frame", caps=False)
        p.box((0, 0, h + 0.43), (0.08, 0.08, 0.08), "Light", mats={"-z": None})


def dish(p, pos, aim, r, mat="Hull", feed="Frame", seg=12):
    """Parabolic dish at pos looking along aim (front and back faces)."""
    m = frame_m(pos, aim)
    with p.at(m):
        front = [(r, 0.30 * r), (r * 0.66, 0.13 * r), (r * 0.33, 0.035 * r), (0.0, 0.0)]
        p.lathe(front, mat, seg=seg, smooth=True)
        back = [(0.0, -0.04), (r * 0.5, 0.075 * r - 0.04), (r, 0.30 * r - 0.03)]
        p.lathe(back, "Frame", seg=seg, smooth=True)
        p.beam((0, 0, 0), (0, 0, 0.62 * r), 0.03, 0.03, feed)
        p.box((0, 0, 0.64 * r), (0.09, 0.09, 0.09), feed)


def ladder(p, x, y, z0, z1, yaw=0.0, w=0.44, mat="Frame"):
    with p.at(T(x, y, 0), RZ(yaw)):
        for s in (-1, 1):
            p.beam((0, s * w / 2, z0), (0, s * w / 2, z1), 0.045, 0.045, mat, caps=False)
        n = max(2, int((z1 - z0) / 0.34))
        for k in range(1, n):
            zz = z0 + (z1 - z0) * k / n
            p.beam((0, -w / 2, zz), (0, w / 2, zz), 0.03, 0.03, mat, caps=False)


def rail_ring(p, r, z, h=0.9, seg=32, posts=12, a0=0.0, a1=360.0, mat="Frame"):
    """Hand rail on a circle: posts + a flat top rail (2 faces)."""
    full = abs((a1 - a0) - 360.0) < 1e-6
    if full:
        p.lathe_a([(r + 0.025, z + h - 0.04), (r + 0.025, z + h), (r - 0.025, z + h)], reg_angles(seg), mat, smooth=False)
        pa = [a0 + 360.0 * k / posts for k in range(posts)]
    else:
        p.lathe([(r + 0.025, z + h - 0.04), (r + 0.025, z + h), (r - 0.025, z + h)], mat, seg=seg,
                smooth=False, a0=a0, a1=a1, caps=False)
        pa = [a0 + (a1 - a0) * k / (posts - 1) for k in range(posts)]
    for a in pa:
        with p.at(RZ(a), T(r, 0, 0)):
            p.box0(0, 0, z, 0.04, 0.04, h - 0.03, mat, mats={"-z": None, "+z": None})


def rail_line(p, a, b, z, h=0.9, posts=None, mat="Frame"):
    a, b = Vector((a[0], a[1], z + h)), Vector((b[0], b[1], z + h))
    p.beam(a, b, 0.04, 0.04, mat)
    n = posts or max(2, int((b - a).length / 1.4) + 1)
    for k in range(n):
        q = a.lerp(b, k / (n - 1))
        p.box0(q.x, q.y, z, 0.04, 0.04, h - 0.02, mat, mats={"-z": None, "+z": None})


def hazard_band(p, x0, x1, y, z0, z1, n=6, facing=1, lean=0.25):
    """Slanted hazard stripes on a vertical plane y = const (facing +Y if facing > 0), from x0 to x1."""
    w = (x1 - x0) / n
    for k in range(n):
        xa, xb = x0 + w * k, x0 + w * (k + 1)
        mat = "Hazard" if k % 2 == 0 else "Rubber"
        sh = lean * (z1 - z0)
        pts = [(xa, y, z0), (xb, y, z0), (min(x1, xb + sh), y, z1), (min(x1, xa + sh), y, z1)]
        if k == 0:
            pts[3] = (xa, y, z1) if sh > 0 else pts[3]
        if facing < 0:
            pts = list(reversed(pts))
        p.f([p.v(q) for q in pts], mat)


def vent_box(p, x, y, z, w, d, h, yaw=0.0, mat="HullDark", slat="Frame", slats=3):
    with p.at(T(x, y, z), RZ(yaw)):
        p.box0(0, 0, 0, w, d, h, mat, mats={"-z": None})
        for k in range(slats):
            yy = -d * 0.32 + d * 0.64 * k / max(1, slats - 1)
            p.box0(0, yy, h, w * 0.82, 0.05, 0.035, slat, mats={"-z": None})


def fan_unit(p, x, y, z, r, mat="Frame", blade="Metal", seg=8):
    """Round fan in a short housing, axis up (about 50 triangles)."""
    p.vcyl(x, y, z, z + 0.20, r, seg=seg, mat=mat, cap1=False, cap0=False)
    p.lathe([(r, z + 0.20), (r - 0.05, z + 0.20), (r - 0.05, z + 0.10)], mat, seg=seg, smooth=False)
    with p.at(T(x, y, z)):
        p.cap_disc(r - 0.05, 0.10, "Rubber", seg=seg)
        p.box((0, 0, 0.14), (r * 1.6, 0.10, 0.02), blade)
        p.box((0, 0, 0.14), (0.10, r * 1.6, 0.02), blade)


def capsule(p, p0, p1, r, mat="Hull", seg=10, rings=2):
    """Cylinder with round ends between p0 and p1 (centres of the end spheres)."""
    p0, p1 = Vector(p0), Vector(p1)
    L = (p1 - p0).length
    m = frame_m(p0, p1 - p0)
    prof = [(0.0, -r)]
    for k in range(1, rings + 1):
        t = -90.0 + 90.0 * k / rings
        prof.append((r * cos(radians(t)), r * sin(radians(t))))
    for k in range(0, rings):
        t = 90.0 * k / rings
        prof.append((r * cos(radians(t)), L + r * sin(radians(t))))
    prof.append((0.0, L + r))
    with p.at(m):
        p.lathe(prof, mat, seg=seg)


def tank_v(p, x, y, z0, h, r, mat="Metal", band="Accent", cap="dome", seg=12, legs=False, band_z=0.55, band_h=0.22):
    """Vertical tank: optional legs, body, a proud band, a domed or flat top.  Returns the top z."""
    body0 = z0 + (0.16 if legs else 0.0)
    if legs:
        for k in range(4):
            lx, ly, _ = polar(r * 0.70, 45.0 + 90.0 * k)
            p.box0(x + lx, y + ly, z0, 0.10, 0.10, 0.20, "Frame", mats={"-z": None, "+z": None})
    prof = [(r, body0)]
    mats = []
    if band:
        zb = body0 + h * band_z
        prof += [(r, zb), (r + 0.03, zb + 0.02), (r + 0.03, zb + band_h - 0.02), (r, zb + band_h)]
        mats += [mat, band, band, band]
    prof.append((r, body0 + h))
    mats.append(mat)
    if cap == "dome":
        for t in (35.0, 65.0):
            prof.append((r * cos(radians(t)), body0 + h + 0.45 * r * sin(radians(t))))
            mats.append(mat)
        prof.append((0.0, body0 + h + 0.45 * r))
        mats.append(mat)
        top = body0 + h + 0.45 * r
    else:
        prof.append((0.0, body0 + h))
        mats.append(cap if isinstance(cap, str) and cap not in ("flat",) else mat)
        top = body0 + h
    with p.at(T(x, y, 0)):
        p.lathe_a(prof, reg_angles(seg), lambda k, i: mats[k])
    return top


def pipe(p, pts, r=0.07, mat="Metal", seg=6, fillet=0.25):
    p.tube(pts, r, seg=seg, mat=mat, fillet=fillet)


def screen(p, x, y, z, w, h, yaw=0.0, glow="Window"):
    """Wall/desk screen: frame + glowing face toward local +X."""
    with p.at(T(x, y, z), RZ(yaw)):
        p.box((0, 0, 0), (0.06, w, h), "Frame", mats={"-x": None})
        p.box((0.035, 0, 0), (0.012, w - 0.06, h - 0.06), glow, mats={"-x": None})


# --------------------------------------------------------------------------------------
# The room shell
# --------------------------------------------------------------------------------------
def seg_for(rw):
    n = int(round(2 * pi * rw / 1.15 / 4.0)) * 4
    return max(24, min(48, n))


class Room:
    """One room model: the parts, the radii and the roof shell that the builders share."""

    def __init__(self, tid, size, R, cat, bdef=None, single=False):
        self.tid, self.size, self.R, self.cat = tid, size, R, cat
        self.bdef = bdef or {}
        self.single = single
        self.Rf = R - MARGIN
        self.Rw = R - 0.32
        self.Ri = self.Rw - WALL_T
        self.seg = seg_for(self.Rw)
        self.base, self.roof, self.interior, self.lights = P("Base"), P("Roof"), P("Interior"), P("Lights")
        self.L = {n: P("L%d" % n) for n in (2, 3, 4, 5)}
        self.levels = not single
        self.anchors = []                 # (name, (x, y, z))
        self.shell = None
        self.H = None                     # dome apex (ellipse top)
        self.D = None                     # podium deck height
        self.rooms_hi = []                # [(fn(x, y) -> bool, z_top)] extra head room (halls, towers)
        self.trays = []                   # tray centres the builder placed (checked against content)
        self.door_half = 0.0
        self.door_top = WALL_TOP
        self.top_z = WALL_TOP
        self.sc = min(1.0, max(0.62, R / 6.0))     # detail scale for level parts
        # 3.0 (docs/V3_DESIGN.md section 7): the round wall as 32 objects Wall_00..Wall_31 (interior_kit.py)
        self.v3 = False
        self.walls = []                   # [P("Wall_00"), ...] when v3

    # ---- output --------------------------------------------------------------------------
    def parts(self):
        out = [self.base, self.roof, self.interior]
        if self.levels:
            out += [self.L[n] for n in (2, 3, 4, 5)]
        if self.lights.faces:
            out.append(self.lights)
        out += [w for w in self.walls if w.faces]
        out += [q for q in getattr(self, "extra_parts", []) if q.faces]
        return out

    def anchor(self, name, pos, yaw=0.0):
        """Empty Anchor_<name>.  yaw (degrees, about +Z): local +X = the direction a person at the anchor faces."""
        self.anchors.append(("Anchor_" + name, tuple(pos), float(yaw)))

    # ---- the round base -----------------------------------------------------------------
    def build_base(self, wall="Hull", kick="HullDark", band="Accent", band_proud=None, windows=None, win_seams=16,
                   win_mat="Window", pilasters=0, pil_mat="Frame", door=True, door_w=1.30, lamps=(), bolts=None,
                   floor="plain", inner="Hull", floor_mat="HullDark", accent_floor=True, floor_rings=None):
        if getattr(self, "v3_mode", False):
            # 3.0: foundation + 32 wall segments; the interior builder makes the floor; no fake +X door
            import interior_kit as IK
            b = self.base
            b.lathe_a([(self.Rf, -0.20), (self.Rf, 0.05), (self.Rw + 0.02, 0.09)], reg_angles(self.seg), "Frame")
            if bolts is None:
                bolts = self.size >= 2
            keep = bool(door and getattr(self, "keep_door", False))
            dh = degrees(asin(min(0.95, (door_w / 2 + 0.3) / self.Rw))) if keep else 0.0
            if bolts:
                nb = max(8, self.seg // 3)
                bolts_ring(b, (self.Rf + self.Rw) / 2 + 0.01, 0.07, nb, size=0.08, h=0.03, mat="Metal",
                           a0=180.0 / nb, skip=[(0.0, dh)] if keep else None)
            if band_proud is None:
                band_proud = self.size >= 1
            IK.build_walls_v3(self, band=band or None, band_proud=band_proud, wall=wall, kick=kick, windows=windows,
                              win_mat=win_mat, win_seams=win_seams, pilasters=pilasters, pil_mat=pil_mat,
                              door_half=dh + 1.0 if keep else 0.0)
            self.door_half = dh
            if keep:
                self.build_door(door_w)
            return
        b = self.base
        Rf, Rw, Ri, seg = self.Rf, self.Rw, self.Ri, self.seg
        # ---- foundation ring: the largest radius of the model -------------------------------------
        angs = reg_angles(seg)
        b.lathe_a([(Rf, -0.20), (Rf, 0.05), (Rw + 0.02, 0.09)], angs, "Frame")
        dh = degrees(asin(min(0.95, (door_w / 2 + 0.3) / Rw))) if door else 0.0
        self.door_half = dh
        if bolts is None:
            bolts = self.size >= 2
        if bolts:
            nb = max(8, seg // 3)
            bolts_ring(b, (Rf + Rw) / 2 + 0.01, 0.07, nb, size=0.08, h=0.03, mat="Metal",
                       a0=180.0 / nb, skip=[(0.0, dh)] if door else None)
        # ---- wall: kick plate, panel, optional ribbon windows, accent band, top --------------------
        if band_proud is None:
            band_proud = self.size >= 1
        seams = [360.0 * (k + 0.5) / win_seams for k in range(win_seams)] if windows else []
        cols, kind, _ = columns(seg, seams, seam_w=degrees(0.08 / Rw))
        mid = col_mid_fn(cols)
        prof, mats = [], []

        def add(r, z, m=None):
            if prof:
                mats.append(m)
            prof.append((r, z))
        add(Rw, 0.09)
        add(Rw, 0.32, kick)
        if windows:
            add(Rw, windows[0], wall)
            add(Rw, windows[1], "WIN")
        if band:
            if band_proud:
                add(Rw, 0.92, wall)
                add(Rw + 0.03, 0.935, band)
                add(Rw + 0.03, 1.125, band)
                add(Rw, 1.14, band)
            else:
                add(Rw, 0.94, wall)
                add(Rw, 1.12, band)
        add(Rw, WALL_TOP, wall)
        add(Ri, WALL_TOP, "Frame")
        add(Ri, FLOOR_Z, inner)

        def wmat(k, i):
            m = mats[k]
            if m == "WIN":
                if door and ang_diff(mid(i), 0.0) < dh + 4.0:
                    return wall
                return "Frame" if kind[i] == "s" else win_mat
            return m
        b.lathe_a(prof, cols, wmat)
        # ---- pilasters ------------------------------------------------------------------------------
        for k in range(pilasters):
            a = 360.0 * (k + 0.5) / pilasters
            if door and ang_diff(a, 0.0) < dh + 3.0:
                continue
            with b.at(RZ(a), T(Rw, 0, 0)):
                b.box0(0.03, 0, 0.09, 0.12, 0.16, WALL_TOP - 0.11, pil_mat, mats={"-z": None, "-x": None})
        # ---- floor ------------------------------------------------------------------------------------
        self.build_floor(floor, floor_mat, accent_floor, floor_rings)
        # ---- door at +X --------------------------------------------------------------------------------
        if door:
            self.build_door(door_w)
        for a in lamps:
            pos = Vector(polar(Rw + 0.035 if band_proud else Rw, a, 1.27))
            lamp(b, self.lights, pos, Vector(polar(1.0, a, 0.0)), w=0.24, h=0.10, d=0.07)

    def build_floor(self, style="plain", floor_mat="HullDark", accent=True, rings=None):
        """Floor disc at FLOOR_Z.  It reaches under the wall (Ri + 0.12) so a coarser polygon has no gaps."""
        b = self.base
        Ri = self.Ri
        nf = max(16, (self.seg * 2) // 3 // 4 * 4)
        rs = rings or [Ri - 0.32]
        if rings is None:
            r = Ri - 0.32
            step = 1.5
            while r - step > 0.9:
                r -= step
                rs.append(r)
        prof = [(Ri + 0.12, FLOOR_Z)] + [(r, FLOOR_Z) for r in rs]
        ring_acc = None
        if accent:
            ra = min(1.4, rs[-1] - 0.1)
            if ra > 0.5:
                prof += [(ra, FLOOR_Z), (ra - 0.14, FLOOR_Z)]
                ring_acc = len(prof) - 2
        prof.append((0.0, FLOOR_Z))

        def fm(k, i):
            if k == 0:
                return "Frame"
            if ring_acc is not None and k == ring_acc:
                return "Accent"
            if style == "grate":
                return "Frame" if k % 2 == 0 else floor_mat
            return floor_mat
        b.lathe_a(prof, reg_angles(nf), fm, smooth=False)

    def build_door(self, w=1.30):
        """Service door on +X: frame posts, lintel, door slab, hazard stripes, threshold, two lamps.
        Parts below WALL_TOP go to Base; the upper part goes to Roof.  Everything stays inside Rf."""
        b, r = self.base, self.roof
        Rw, Rf = self.Rw, self.Rf
        hw = w / 2.0
        pw = 0.18
        ymax = hw + pw + 0.05
        x1 = min(Rw + 0.14, sqrt((Rf - 0.03) ** 2 - ymax ** 2) - 0.075)      # room for the door lamps
        x0 = Rw - 0.22
        top = 2.18
        for sy in (-1, 1):
            yc = sy * (hw + pw / 2)
            b.box((0.5 * (x0 + x1), yc, 0.5 * (0.09 + WALL_TOP)), (x1 - x0, pw, WALL_TOP - 0.09), "Frame",
                  mats={"-z": None, "-x": None, "+z": None})
            r.box((0.5 * (x0 + x1), yc, 0.5 * (WALL_TOP + top)), (x1 - x0, pw, top - WALL_TOP), "Frame",
                  mats={"-z": None, "-x": None})
            for k in range(4):                                     # slanted hazard stripes on the post face
                z0 = 0.16 + 0.29 * k
                mat = "Hazard" if k % 2 == 0 else "Rubber"
                b.quad((x1 + 0.004, yc - pw / 2, z0), (x1 + 0.004, yc + pw / 2, z0 + 0.10),
                       (x1 + 0.004, yc + pw / 2, z0 + 0.39), (x1 + 0.004, yc - pw / 2, z0 + 0.29), mat)
        r.box((0.5 * (x0 + x1), 0, top + 0.13), (x1 - x0, w + 2 * pw + 0.04, 0.26), "Frame", mats={"-x": None})
        r.box((x1 + 0.006, 0, top + 0.13), (0.012, w + 0.16, 0.10), "Accent", mats={"-x": None})
        xs = min(Rw + 0.05, x1 - 0.04)
        b.box((xs - 0.04, 0, 0.5 * (0.10 + WALL_TOP)), (0.08, w, WALL_TOP - 0.10), "HullDark",
              mats={"-x": None, "-z": None, "+z": None})
        r.box((xs - 0.04, 0, 0.5 * (WALL_TOP + top)), (0.08, w, top - WALL_TOP), "HullDark", mats={"-x": None})
        r.box((xs + 0.006, 0, 1.80), (0.012, w * 0.46, 0.30), "Window", mats={"-x": None})
        b.box((xs + 0.006, 0, 0.95), (0.012, w * 0.86, 0.08), "Accent", mats={"-x": None})
        b.box((xs + 0.006, w * 0.3, 0.62), (0.012, 0.08, 0.30), "Frame", mats={"-x": None})
        b.box0(xs - 0.05, 0, 0.0, 0.34, w + 0.1, 0.10, "HullDark", mats={"-z": None})
        for sy in (-1, 1):
            lamp(b, self.lights, Vector((x1, sy * (hw + pw / 2), 1.22)), (1, 0, 0), w=0.10, h=0.14, d=0.05)
        self.door_top = top + 0.26
        self.door_x = (x0, x1)
        self.door_w = w
        self.anchor("Door", (x1 + 0.3, 0.0, 0.0))

    def door_hood(self, depth=1.1):
        """Box that joins the door lintel to a dome (in Roof)."""
        if getattr(self, "v3_mode", False) and not hasattr(self, "door_x"):
            return
        Rw = self.Rw
        w = getattr(self, "door_w", 1.3)
        x0 = Rw - depth
        x1 = self.door_x[1] if hasattr(self, "door_x") else Rw + 0.1
        top = self.door_top
        self.roof.box0(0.5 * (x0 + x1 - 0.02), 0, WALL_TOP + 0.05, x1 - 0.02 - x0, w + 0.44,
                       top - WALL_TOP - 0.07, "Hull", mats={"-z": None})
        self.roof.box0(0.5 * (x0 + x1), 0, top - 0.04, x1 - x0, w + 0.50, 0.08, "Frame", mats={"-z": None})

    def seal_ring(self):
        Rw = self.Rw
        self.roof.lathe_a([(Rw + 0.05, WALL_TOP - 0.03), (Rw + 0.05, WALL_TOP + 0.08), (Rw - 0.04, WALL_TOP + 0.14)],
                          reg_angles(self.seg), "Frame")

    # ---- dome ---------------------------------------------------------------------------------
    def dome_rz(self, t):
        return self.Rw * cos(radians(t)), WALL_TOP + (self.H - WALL_TOP) * sin(radians(t))

    def dome_nrz(self, t):
        a, b = self.Rw, self.H - WALL_TOP
        tr = radians(t)
        nr, nz = b * cos(tr), a * sin(tr)
        ln = hypot(nr, nz)
        return nr / ln, nz / ln

    def dpt(self, t, ang, off=0.0):
        r, z = self.dome_rz(t)
        nr, nz = self.dome_nrz(t)
        a = radians(ang)
        n = Vector((nr * cos(a), nr * sin(a), nz))
        return Vector((r * cos(a), r * sin(a), z)) + n * off, n

    def dome_z(self, x, y):
        r = min(hypot(x, y), self.Rw)
        return WALL_TOP + (self.H - WALL_TOP) * sqrt(max(0.0, 1.0 - (r / self.Rw) ** 2))

    def t_at_r(self, r):
        return degrees(acos(max(-1.0, min(1.0, r / self.Rw))))

    def build_dome(self, H, ts=None, crown="hatch", seams=8, seam_phase=22.5, seam_mat="HullDark", hseams=None,
                   mat=None, inset=0.012, seal=True, seg=None, crown_mat="Frame", cap_mat="HullDark", crown_t=None):
        """Elliptic dome from the wall top (r = Rw, z = 1.40) to the apex H with meridian and ring seams.
        mat(t_mid, a_mid) -> panel material (default Hull).  crown: 'hatch', 'skylight', 'open', 'apex'."""
        self.shell = "dome"
        self.H = H
        seg = seg or self.seg
        if seal:
            self.seal_ring()
        if ts is None:
            ts = [(0, 12, 27, 44, 62, 79), (0, 10, 22, 36, 51, 66, 79), (0, 8, 18, 30, 43, 56, 68, 80),
                  (0, 7, 16, 27, 38, 50, 61, 71, 80)][self.size]
        if hseams is None:
            hseams = [(24.0,), (21.0, 48.0), (19.0, 44.0), (18.0, 40.0)][self.size]
        ts = list(ts)
        if crown_t is not None:
            ts = [t for t in ts if t < crown_t - 2.0] + [crown_t]
        if crown == "apex":
            ts = ts + [90.0]
        tl = sorted(set(ts + [h - 0.8 for h in hseams] + [h + 0.8 for h in hseams]))
        hs_band, hs_ring = set(), set()
        for k in range(len(tl) - 1):
            midt = 0.5 * (tl[k] + tl[k + 1])
            if any(abs(midt - h) < 0.81 for h in hseams):
                hs_band.add(k)
                hs_ring.update((k, k + 1))
        cols, kind, sc = columns(seg, [seam_phase + 360.0 * k / seams for k in range(seams)] if seams else [],
                                 seam_w=1.3)
        mid = col_mid_fn(cols)
        prof = [self.dome_rz(t) for t in tl]
        if crown == "apex":
            prof[-1] = (0.0, prof[-1][1])

        def m(k, i):
            if k in hs_band or kind[i] == "s":
                return seam_mat
            if mat:
                return mat(0.5 * (tl[k] + tl[k + 1]), mid(i))
            return "Hull"

        def offs(kr, i):
            if kr in hs_ring or sc[i]:
                nr, nz = self.dome_nrz(tl[kr])
                return -inset * nr, -inset * nz
            return 0.0, 0.0
        self.roof.lathe_a(prof, cols, m, smooth=True, offs=offs if inset > 0 else None)
        self.dome_ts = tl
        self.top_z = max(self.top_z, H)
        if crown in ("hatch", "skylight"):
            tc = tl[-1]
            rc, zc = self.dome_rz(tc)
            self.crown_r, self.crown_z = rc, zc
            r = self.roof
            cs = max(12, (seg // 2) // 4 * 4)
            r.lathe([(rc + 0.06, zc - 0.10), (rc + 0.06, zc + 0.10), (rc - 0.07, zc + 0.12)], crown_mat, seg=cs)
            if crown == "hatch":
                r.lathe([(rc - 0.07, zc + 0.12), (rc - 0.07, zc + 0.05), (0.0, zc + 0.07)],
                        lambda k, i: crown_mat if k == 0 else cap_mat, seg=cs, smooth=False)
                r.box((0, 0, zc + 0.095), (rc * 1.25, 0.10, 0.05), "Frame", mats={"-z": None})
                r.box((0, 0, zc + 0.095), (0.10, rc * 1.25, 0.05), "Frame", mats={"-z": None})
                self.top_z = max(self.top_z, zc + 0.13)
            else:
                rr = rc - 0.07
                with r.at(T(0, 0, zc + 0.05)):
                    r.lathe([(rr, 0.0), (rr * 0.72, rr * 0.30), (0.0, rr * 0.42)], "Glass", seg=cs)
                for k in range(2):
                    with r.at(RZ(90.0 * k)):
                        pts = [Vector((-rr, 0, zc + 0.06)), Vector((-rr * 0.55, 0, zc + 0.06 + rr * 0.33)),
                               Vector((0.0, 0, zc + 0.07 + rr * 0.42)), Vector((rr * 0.55, 0, zc + 0.06 + rr * 0.33)),
                               Vector((rr, 0, zc + 0.06))]
                        r.beam_path(pts, 0.05, 0.05, "Frame")
                self.top_z = max(self.top_z, zc + 0.12 + rr * 0.42)

    # ---- podium: a drum above the wall + a flat deck ---------------------------------------------------
    def build_podium(self, D, wall="Hull", band="Accent", ribs=12, rib_mat="Frame", deck="HullDark",
                     parapet=0.16, windows=None, win_mat="Window", win_seams=16, coping="Frame", deck_rings=None,
                     deck_edge="Frame", band_z=None, lower_mat=None, deck_seg=None):
        """Drum wall from 1.40 to D at the wall radius, a parapet and a flat deck at D (Roof)."""
        self.shell = "podium"
        self.D = D
        r = self.roof
        Rw, seg = self.Rw, self.seg
        seams = [360.0 * (k + 0.5) / win_seams for k in range(win_seams)] if windows else []
        cols, kind, _ = columns(seg, seams, seam_w=degrees(0.08 / Rw))
        mid = col_mid_fn(cols)
        prof, mats = [], []

        def add(rr, z, m=None):
            if prof:
                mats.append(m)
            prof.append((rr, z))
        add(Rw, WALL_TOP - 0.02)
        bz = band_z if band_z is not None else D - 0.55
        lo = WALL_TOP
        if windows:
            add(Rw, windows[0], lower_mat or wall)
            add(Rw, windows[1], "WIN")
            lo = windows[1]
        if band and bz > lo + 0.05:
            add(Rw, bz, wall)
            add(Rw, bz + 0.20, band)
        add(Rw, D, wall)
        add(Rw + 0.04, D, coping)
        add(Rw + 0.04, D + parapet, coping)
        add(Rw - 0.12, D + parapet, coping)
        add(Rw - 0.12, D + 0.02, coping)

        def wm(k, i):
            m = mats[k]
            if m == "WIN":
                if self.door_half and ang_diff(mid(i), 0.0) < self.door_half + 4.0:
                    return wall
                return "Frame" if kind[i] == "s" else win_mat
            return m
        r.lathe_a(prof, cols, wm)
        for k in range(ribs):
            a = 360.0 * (k + 0.5) / ribs
            if self.door_half and ang_diff(a, 0.0) < self.door_half + 3.0:
                continue
            with r.at(RZ(a), T(Rw, 0, 0)):
                r.box0(0.02, 0, WALL_TOP, 0.10, 0.16, D - WALL_TOP, rib_mat, mats={"-z": None, "-x": None, "+z": None})
        # deck
        rs = deck_rings or [Rw - 0.12, Rw - 0.40] + [Rw - 0.40 - 1.6 * k for k in range(1, 8) if Rw - 0.40 - 1.6 * k > 0.8]
        dprof = [(q, D + 0.02) for q in rs] + [(0.0, D + 0.02)]
        ds = deck_seg or max(16, (seg * 2) // 3 // 4 * 4)
        if ds != seg:
            dprof[0] = (Rw - 0.02, D + 0.02)
        r.lathe_a(dprof, reg_angles(ds), lambda k, i: (deck_edge if (k == 0 and deck_edge) else deck), smooth=False)
        self.top_z = max(self.top_z, D + parapet)

    # ---- head room (interior check) -----------------------------------------------------------------
    def headroom(self, x, y):
        if self.shell == "dome":
            best = self.dome_z(x, y) - 0.04
        elif self.shell in ("podium", "drum"):
            best = self.D - 0.02
        else:
            best = WALL_TOP
        for fn, ztop in self.rooms_hi:
            if fn(x, y):
                best = max(best, ztop)
        return best


# --------------------------------------------------------------------------------------
# Shell modules: setback drum, halls, hex pods, cooling towers, lattice dome
# --------------------------------------------------------------------------------------
def grid_wall(p, o, u, v, nu, nv, mat, smooth=False):
    """Planar grid: origin o, edge vectors u (along) and v (up); normal = u x v.  mat: name or fn(iu, iv)."""
    o, u, v = Vector(o), Vector(u), Vector(v)
    ids = [[p.v(o + u * (i / nu) + v * (j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            m = mat(i, j) if callable(mat) else mat
            if m is None:
                continue
            p.f([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], m, smooth)


def setback_drum(rm, r, D, wall="Hull", band="Accent", ribs=10, rib_mat="Frame", ledge="HullDark", top="HullDark",
                 parapet=0.12, band_z=None, windows=None, win_mat="Window", win_seams=12, coping="Frame",
                 top_rings=None, seg=None):
    """Roof: a flat ledge over the wall top (1.40 -> 1.48) out to the wall radius, and a drum of radius r from the
    ledge up to D with a parapet and a flat top.  Head room: D inside the drum, 1.46 m under the ledge."""
    ro = rm.roof
    Rw = rm.Rw
    seg = seg or max(16, int(round(2 * pi * r / 1.15 / 4.0)) * 4)
    rm.shell = "setback"
    rm.D = D
    rm.drum_r = r
    ro.lathe_a([(Rw + 0.05, WALL_TOP - 0.03), (Rw + 0.05, WALL_TOP + 0.08), (r + 0.02, WALL_TOP + 0.08)],
               reg_angles(rm.seg), lambda k, i: "Frame" if k == 0 else ledge, smooth=False)
    seams = [360.0 * (k + 0.5) / win_seams for k in range(win_seams)] if windows else []
    cols, kind, _ = columns(seg, seams, seam_w=degrees(0.08 / r))
    mid = col_mid_fn(cols)
    prof, mats = [], []

    def add(rr, z, m=None):
        if prof:
            mats.append(m)
        prof.append((rr, z))
    add(r, WALL_TOP + 0.06)
    lo = WALL_TOP
    if windows:
        add(r, windows[0], wall)
        add(r, windows[1], "WIN")
        lo = windows[1]
    bz = band_z if band_z is not None else D - 0.5
    if band and bz > lo + 0.05:
        add(r, bz, wall)
        add(r, bz + 0.2, band)
    add(r, D, wall)
    add(r + 0.04, D, coping)
    add(r + 0.04, D + parapet, coping)
    add(r - 0.10, D + parapet, coping)
    add(r - 0.10, D + 0.02, coping)

    def wm(k, i):
        m = mats[k]
        if m == "WIN":
            return "Frame" if kind[i] == "s" else win_mat
        return m
    ro.lathe_a(prof, cols, wm)
    for k in range(ribs):
        a = 360.0 * (k + 0.5) / ribs
        with ro.at(RZ(a), T(r, 0, 0)):
            ro.box0(0.02, 0, WALL_TOP + 0.08, 0.09, 0.14, D - WALL_TOP - 0.08, rib_mat,
                    mats={"-z": None, "-x": None, "+z": None})
    rs = top_rings or [r - 0.10] + [r - 0.10 - 1.5 * k for k in range(1, 6) if r - 0.10 - 1.5 * k > 0.7]
    ro.lathe_a([(q, D + 0.02) for q in rs] + [(0.0, D + 0.02)], reg_angles(max(12, seg * 2 // 3 // 4 * 4)), top,
               smooth=False)
    rm.top_z = max(rm.top_z, D + parapet)
    rm.rooms_hi.append((lambda x, y, r=r: hypot(x, y) < r - 0.05, D - 0.02))


def hall(p, cx, cy, a, b, z0, eave, ridge=None, roof="gable", wall="Hull", roof_mat="HullDark", band="Accent",
         band_z=None, ribs=True, rib_mat="Frame", windows=True, win_mat="Window", teeth=3, saw_glass="Window",
         end_mat=None, nu=None):
    """Rectangular hall centred (cx, cy), half sizes a (X) and b (Y), walls z0..eave.
    roof: 'gable' (ridge along X), 'saw' (sawtooth, glazed faces toward -X), 'barrel' (vault along X), 'flat'.
    Returns the top height."""
    ridge = ridge or (eave + b * 0.45)
    x0, x1, y0, y1 = cx - a, cx + a, cy - b, cy + b
    H = eave - z0
    nu_x = nu or max(2, int(2 * a / 1.6))
    nu_y = max(2, int(2 * b / 1.6))
    bz = band_z if band_z is not None else z0 + H * 0.62
    wz0, wz1 = z0 + H * 0.30, z0 + H * 0.52

    def wall_rows(zb):
        rows = [z0, wz0, wz1, bz, bz + 0.2, eave] if windows else [z0, bz, bz + 0.2, eave]
        return rows

    def side(o, u, n_cols, mat_win=True):
        rows = wall_rows(bz)
        for j in range(len(rows) - 1):
            za, zb = rows[j], rows[j + 1]
            if zb - za < 1e-4:
                continue
            is_band = abs(za - bz) < 1e-6
            is_win = windows and mat_win and abs(za - wz0) < 1e-6

            def mf(i, jj, is_band=is_band, is_win=is_win):
                if is_band:
                    return band
                if is_win:
                    return win_mat if i % 2 == 0 else wall
                return wall
            grid_wall(p, Vector(o) + Vector((0, 0, za - z0)), u, (0, 0, zb - za), n_cols, 1, mf)
    # four walls (normals outward): -Y wall runs +X, +Y wall runs -X, +X wall runs +Y, -X wall runs -Y
    side((x0, y0, z0), (2 * a, 0, 0), nu_x)
    side((x1, y1, z0), (-2 * a, 0, 0), nu_x)
    side((x1, y0, z0), (0, 2 * b, 0), nu_y, mat_win=False)
    side((x0, y1, z0), (0, -2 * b, 0), nu_y, mat_win=False)
    if ribs:
        for i in range(nu_x + 1):
            x = x0 + 2 * a * i / nu_x
            for yy, s in ((y0, -1), (y1, 1)):
                p.box0(x, yy + s * 0.04, z0, 0.12, 0.08, H, rib_mat, mats={"-z": None, "+z": None})
    top = eave
    if roof == "gable":
        # two slopes (normals up and out) + gable ends
        grid_wall(p, (x0 - 0.1, y0 - 0.12, eave - 0.02), (2 * a + 0.2, 0, 0), (0, b + 0.12, ridge - eave + 0.02),
                  nu_x, 2, roof_mat)
        grid_wall(p, (x1 + 0.1, y1 + 0.12, eave - 0.02), (-2 * a - 0.2, 0, 0), (0, -(b + 0.12), ridge - eave + 0.02),
                  nu_x, 2, roof_mat)
        for xx, s in ((x1, 1), (x0, -1)):
            pts = [(xx, y0, eave), (xx, y1, eave), (xx, cy, ridge)]
            if s < 0:
                pts = list(reversed(pts))
            p.f([p.v(q) for q in pts], end_mat or wall)
        p.beam((x0 - 0.12, cy, ridge + 0.03), (x1 + 0.12, cy, ridge + 0.03), 0.16, 0.10, rib_mat)
        top = ridge + 0.08
    elif roof == "saw":
        n = teeth
        w = 2 * a / n
        hz = ridge - eave
        for k in range(n):
            xa = x0 + w * k
            xb = xa + w
            # glazed vertical face at xa (facing -X), sloped roof from (xa, ridge) down to (xb, eave)
            grid_wall(p, (xa, y1, eave), (0, -2 * b, 0), (0, 0, hz), max(2, nu_y), 1,
                      lambda i, j: saw_glass if i % 2 == 0 else rib_mat)
            p.quad((xb, y0, eave), (xb, y1, eave), (xa, y1, ridge), (xa, y0, ridge), roof_mat)
            p.f([p.v((xa, y0, eave)), p.v((xb, y0, eave)), p.v((xa, y0, ridge))], wall)
            p.f([p.v((xb, y1, eave)), p.v((xa, y1, eave)), p.v((xa, y1, ridge))], wall)
            p.beam((xa, y0 - 0.06, ridge + 0.02), (xa, y1 + 0.06, ridge + 0.02), 0.10, 0.08, rib_mat)
        top = ridge + 0.06
    elif roof == "barrel":
        nseg = 8
        ang = [180.0 * k / nseg for k in range(nseg + 1)]
        rise = ridge - eave
        pts = [(cy + b * cos(radians(t)), eave + rise * sin(radians(t))) for t in ang]
        rings = [[(x0 - 0.08, yy, zz) for yy, zz in pts], [(x1 + 0.08, yy, zz) for yy, zz in pts]]
        p.loft(rings, roof_mat, True, closed=False)
        for xx, s in ((x1 + 0.08, 1), (x0 - 0.08, -1)):
            ring = [(xx, yy, zz) for yy, zz in pts]
            face = ring if s > 0 else list(reversed(ring))
            p.f([p.v(q) for q in face], end_mat or wall)
        for i in range(nu_x + 1):
            x = x0 + 2 * a * i / nu_x
            arc = [Vector((x, yy + 0.0, zz + 0.04)) for yy, zz in pts]
            p.beam_path(arc, 0.10, 0.06, rib_mat, up=lambda q, cy=cy, eave=eave: Vector((0, q.y - cy, q.z - eave + 0.01)).normalized())
        top = ridge + 0.1
    else:
        grid_wall(p, (x0, y0, eave), (2 * a, 0, 0), (0, 2 * b, 0), nu_x, nu_y, roof_mat)
        for (pa, pb) in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
            p.beam((pa[0], pa[1], eave + 0.08), (pb[0], pb[1], eave + 0.08), 0.12, 0.16, rib_mat)
        top = eave + 0.16
    return top


def hex_pod(p, cx, cy, r, z0, h, rot=0.0, wall="Hull", band="Accent", win="Window", top="HullDark", windows=(0, 2, 4),
            chamfer=0.30):
    """Hexagonal pod: six walls with a band and windows, a chamfered roof edge and a flat top."""
    pts = hexagon(r, rot=rot, cx=cx, cy=cy)
    zb = z0 + h * 0.55
    for k in range(6):
        a, b = pts[k], pts[(k + 1) % 6]
        u = (b[0] - a[0], b[1] - a[1], 0.0)
        rows = [(z0, zb, wall), (zb, zb + 0.18, band), (zb + 0.18, z0 + h, wall)]
        for (za, zb2, m) in rows:
            p.quad((a[0], a[1], za), (b[0], b[1], za), (b[0], b[1], zb2), (a[0], a[1], zb2), m)
        if k in windows:
            ca = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0))
            out = (ca - Vector((cx, cy, 0))).normalized()
            wz = z0 + h * 0.28
            uu = Vector(u).normalized()
            L = Vector(u).length
            c0 = ca + out * 0.012 - uu * L * 0.30
            c1 = ca + out * 0.012 + uu * L * 0.30
            p.quad((c0.x, c0.y, wz), (c1.x, c1.y, wz), (c1.x, c1.y, wz + h * 0.20), (c0.x, c0.y, wz + h * 0.20), win)
    inner = hexagon(r - chamfer, rot=rot, cx=cx, cy=cy)
    for k in range(6):
        a, b = pts[k], pts[(k + 1) % 6]
        c, d = inner[(k + 1) % 6], inner[k]
        p.quad((a[0], a[1], z0 + h), (b[0], b[1], z0 + h), (c[0], c[1], z0 + h + chamfer * 0.6),
               (d[0], d[1], z0 + h + chamfer * 0.6), "Frame")
    p.plate(inner, z0 + h + chamfer * 0.6, top)
    return z0 + h + chamfer * 0.6


def cooling_tower(p, cx, cy, z0, h, rb, rt, rtop, seg=16, shell="Hull", inner="HullDark", band="Accent", grille=0.6,
                  slats=None):
    """Hyperbolic cooling tower on a ring of intake grilles.  Returns the top z."""
    zs = z0 + grille
    # intake grille ring: slats (Frame) between z0 and zs
    n = slats or seg
    for k in range(n):
        a = 360.0 * (k + 0.5) / n
        with p.at(T(cx, cy, 0), RZ(a), T(rb - 0.05, 0, 0)):
            p.box0(0, 0, z0, 0.10, 2 * pi * rb / n * 0.55, grille, "Frame", mats={"-z": None, "+z": None})
    p.vcyl(cx, cy, z0, zs, rb - 0.12, seg=seg // 2, mat="Rubber", cap0=False, cap1=False)
    # hyperboloid: r(z) = rt * sqrt(1 + ((z - zt)/c)^2) with the throat at 70 % height
    zt = zs + (h - grille) * 0.70
    ztop = z0 + h

    def rad(z):
        # fit c so that r(zs) = rb
        c = (zt - zs) / sqrt(max(1e-6, (rb / rt) ** 2 - 1.0))
        return rt * sqrt(1.0 + ((z - zt) / c) ** 2)
    zsamp = [zs, zs + (zt - zs) * 0.35, zs + (zt - zs) * 0.7, zt, ztop - 0.35, ztop]
    prof = [(rad(z), z) for z in zsamp[:-1]]
    prof[-1] = (prof[-1][0], prof[-1][1])
    prof.append((rtop, ztop))
    band_k = len(prof) - 2
    prof_all = prof + [(rtop - 0.14, ztop), (rtop - 0.14, ztop - 0.6), (rt - 0.14, zt), (rb - 0.26, zs + 0.3)]
    mats = []
    for k in range(len(prof_all) - 1):
        if k < len(prof) - 1:
            mats.append(band if k == band_k else shell)
        elif k == len(prof) - 1:
            mats.append("Frame")
        else:
            mats.append(inner)
    with p.at(T(cx, cy, 0)):
        p.lathe_a(prof_all, reg_angles(seg), lambda k, i: mats[k])
        p.cap_disc(rb - 0.26, zs + 0.3, "Rubber", seg=seg // 2)
    return ztop


def kiewitt_dome(rm, H, sectors=6, rings=4, frame="Frame", glass="Glass", beam=0.09, base_mat="Accent"):
    """Triangulated lattice dome (Kiewitt pattern) over the wall top: ring i has i*sectors nodes.
    Glass faces + a frame beam on every edge.  Returns node positions for placing parts."""
    ro = rm.roof
    Rw = rm.Rw - 0.02
    Hd = H - WALL_TOP
    rm.shell = "dome"
    rm.H = H
    nodes = [[Vector((0.0, 0.0, WALL_TOP + Hd))]]
    for i in range(1, rings + 1):
        th = radians(90.0 * i / rings)
        n = i * sectors
        ring = []
        for j in range(n):
            a = radians(360.0 * j / n + 90.0 / sectors)
            ring.append(Vector((Rw * sin(th) * cos(a), Rw * sin(th) * sin(a), WALL_TOP + Hd * cos(th))))
        nodes.append(ring)
    tris = []
    for i in range(rings):
        A, B = nodes[i], nodes[i + 1]
        na, nb = len(A), len(B)
        if na == 1:
            for j in range(nb):
                tris.append((A[0], B[j], B[(j + 1) % nb]))
            continue
        # per sector: ring i has i nodes (+ next corner), ring i+1 has i+1 nodes
        ia, ib = 0, 0
        while ia < na or ib < nb:
            a0, a1 = A[ia % na], A[(ia + 1) % na]
            b0, b1 = B[ib % nb], B[(ib + 1) % nb]
            fa = (ia + 1) / na
            fb = (ib + 1) / nb
            if ib < nb and (ia >= na or fb <= fa):
                tris.append((a0, b0, b1))
                ib += 1
            else:
                tris.append((a0, b0, a1))
                ia += 1
    edges = {}
    for t in tris:
        for k in range(3):
            pa, pb = t[k], t[(k + 1) % 3]
            key = tuple(sorted((tuple(round(c, 4) for c in pa), tuple(round(c, 4) for c in pb))))
            edges[key] = (pa, pb)
    for t in tris:
        c = (t[0] + t[1] + t[2]) / 3.0
        nrm = (t[1] - t[0]).cross(t[2] - t[0])
        face = [t[0], t[1], t[2]] if nrm.dot(c - Vector((0, 0, WALL_TOP))) > 0 else [t[0], t[2], t[1]]
        ro.f([ro.v(q) for q in face], glass)
    cen = Vector((0, 0, WALL_TOP))
    for pa, pb in edges.values():
        mid = (pa + pb) / 2
        up = (mid - cen).normalized()
        beam3(ro, pa, pb, beam, up, frame)
    rm.top_z = max(rm.top_z, H + 0.08)
    return nodes


def beam3(p, a, b, w, up, mat):
    """Triangular-section beam from a to b (apex along `up`): 6 triangles, for lattice frames."""
    a, b, up = Vector(a), Vector(b), Vector(up).normalized()
    t = (b - a).normalized()
    side = t.cross(up)
    if side.length < 1e-6:
        return
    side.normalize()
    upp = side.cross(t).normalized()
    sec = [upp * (w * 0.75), -upp * (w * 0.1) + side * (w * 0.6), -upp * (w * 0.1) - side * (w * 0.6)]
    rings = [[tuple(a + s) for s in sec], [tuple(b + s) for s in sec]]
    p.loft(rings, mat, False, closed=True)


# --------------------------------------------------------------------------------------
# Upgrade parts (L2..L5)
# --------------------------------------------------------------------------------------
def dome_band(rm, p, t0, t1, off, mat, seg=None, top_edge=True):
    """A band that hugs the dome between the profile angles t0 and t1, `off` metres proud (1 or 2 faces)."""
    seg = seg or rm.seg

    def rz(t, o):
        r, z = rm.dome_rz(t)
        nr, nz = rm.dome_nrz(t)
        return (r + nr * o, z + nz * o)
    prof = [rz(t0, off), rz(t1, off)]
    if top_edge:
        prof.append(rz(t1, -0.01))
    p.lathe_a(prof, reg_angles(seg), mat)


def drum_band(p, r, z0, z1, off, mat, seg=32, top_edge=True):
    prof = [(r + off, z0), (r + off, z1)]
    if top_edge:
        prof.append((r - 0.01, z1))
    p.lathe_a(prof, reg_angles(seg), mat, smooth=True)


def crown_teeth(p, r, z, n=8, h=0.22, w=0.16, mat="L5Gold", a0=0.0):
    for k in range(n):
        a = a0 + 360.0 * (k + 0.5) / n
        with p.at(RZ(a), T(r, 0, z)):
            p.convex([(-0.03, -w / 2, 0), (0.03, -w / 2, 0), (0.03, w / 2, 0), (-0.03, w / 2, 0), (0.0, 0.0, h)],
                     [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], mat)


def lv_module(p, x, y, z, yaw=0.0, w=1.1, d=0.8, h=0.55, band="L3Band", sink=0.25):
    """L3 roof module: equipment box on a plinth, a glowing band and a fan (about 110 triangles)."""
    with p.at(T(x, y, z), RZ(yaw)):
        p.box0(0, 0, -sink, w + 0.12, d + 0.12, sink + 0.02, "Frame", mats={"-z": None})
        p.box0(0, 0, 0.0, w, d, h, "Hull", mats={"-z": None})
        p.box((0, 0, h * 0.42), (w + 0.03, d + 0.03, 0.08), band, mats={"-z": None, "+z": None})
        p.box((w / 2 + 0.008, 0, h * 0.72), (0.012, d * 0.55, h * 0.24), "Frame", mats={"-x": None})
    ca, sa = cos(radians(yaw)), sin(radians(yaw))
    fan_unit(p, x - ca * w * 0.2, y - sa * w * 0.2, z + h - 0.02, min(w, d) * 0.33, mat="Frame")


def lv_fins(p, x, y, z, yaw=0.0, n=5, h=0.9, length=0.9, gap=0.2, band="L4Band", sink=0.2):
    """L4 radiator fin bank on a rail (about 90 triangles)."""
    with p.at(T(x, y, z), RZ(yaw)):
        span = gap * (n - 1)
        p.box0(0, 0, -sink, length + 0.1, span + 0.24, sink + 0.10, "Frame", mats={"-z": None})
        p.box((0, 0, 0.03), (length + 0.13, span + 0.27, 0.06), band, mats={"-z": None, "+z": None})
        for k in range(n):
            yy = -span / 2 + gap * k
            p.box0(0, yy, 0.1, length, 0.035, h, "Trim", mats={"-z": None})
        p.cyl((-length / 2 + 0.05, -span / 2 - 0.06, 0.1 + h * 0.86), (-length / 2 + 0.05, span / 2 + 0.06, 0.1 + h * 0.86),
              0.05, seg=6, mat="Metal")


def lv_annex(p, x, y, z, yaw=0.0, L=1.8, r=0.5, band="L4Band", seg=10):
    """L4 side annex: a capsule pod on two saddles, windows and a glowing ring (about 140 triangles)."""
    with p.at(T(x, y, z), RZ(yaw)):
        for sx in (-L * 0.26, L * 0.26):
            p.box0(sx, 0, -0.3, 0.16, r * 1.4, 0.3 + r * 0.5, "Frame", mats={"-z": None})
        capsule(p, (-L / 2 + r, 0, r + 0.02), (L / 2 - r, 0, r + 0.02), r, mat="Hull", seg=seg, rings=2)
        p.cyl((L * 0.14 - 0.06, 0, r + 0.02), (L * 0.14 + 0.06, 0, r + 0.02), r + 0.022, seg=seg, mat=band,
              cap0=False, cap1=False)
        for sy in (-1, 1):
            p.box((-L * 0.16, sy * r * 0.80, r + 0.14), (L * 0.34, 0.24, 0.14), "Window", mats={"-y" if sy > 0 else "+y": None})


def lv_beacon(rm, p, x, y, z, h=0.9):
    """L5 beacon: mast, gold collars and a category-colour lamp (about 90 triangles)."""
    sg = 6 if rm.size == 0 else 8
    p.box0(x, y, z - 0.08, 0.32, 0.32, 0.12, "Frame", mats={"-z": None})
    p.beam((x, y, z), (x, y, z + h), 0.07, 0.07, "Trim", caps=False)
    p.vcyl(x, y, z + h, z + h + 0.06, 0.18, seg=sg, mat="L5Gold")
    p.sphere((x, y, z + h + 0.19), 0.14, "Neon", seg=sg, rings=3 if rm.size == 0 else 4)
    p.vcyl(x, y, z + h + 0.31, z + h + 0.36, 0.14, seg=sg, mat="L5Gold")
    rm.anchor("Beacon", (x, y, z + h + 0.19))
    return z + h + 0.36


def lv_emblem(p, pos, normal, size=1.0, xdir=(1, 0, 0)):
    """L5 emblem: gold hexagon plate with a glowing four-point star (no text, no logo; about 60 triangles)."""
    m = frame_m(pos, normal, xdir)
    with p.at(m):
        p.prism(hexagon(size * 0.5, rot=0.0), -0.05, 0.05, "L5Gold", cap0=False)
        s = size * 0.38
        star = []
        for k in range(8):
            rr = s if k % 2 == 0 else s * 0.32
            a = radians(90.0 + 45.0 * k)
            star.append((rr * cos(a), rr * sin(a)))
        p.prism(star, 0.05, 0.08, "Neon", cap0=False)


def lv_collar_dome(rm, t0=3.0, t1=10.0, bolts=None):
    p = rm.L[2]
    if bolts is None:
        bolts = rm.size >= 2
    dome_band(rm, p, t0, t1, 0.06, "Trim")
    if bolts:
        tm = 0.5 * (t0 + t1)
        n = max(8, rm.seg // 3)
        for k in range(n):
            pos, nor = rm.dpt(tm, 360.0 * (k + 0.5) / n, off=0.06)
            with p.at(frame_m(pos, nor, (0, 0, 1))):
                p.box0(0, 0, 0, 0.08, 0.08, 0.03, "Frame", mats={"-z": None})


def levels_dome(rm, cfg=None):
    """Default upgrade parts on a dome.  cfg overrides the sites (profile angle t, azimuth a in degrees)."""
    c = dict(collar=(3.0, 10.0), ant=(56.0, -128.0, 1.5), band3=(31.0, 33.5), mod3=(60.0, -58.0),
             band4=(17.5, 20.0), fins4=(44.0, 128.0), annex4=(21.0, -92.0), crown5=(73.0, 77.0), emblem5=(47.0, -12.0),
             beacon5="top", emblem_size=None, mod_size=None, annex_len=None, fin_n=None)
    c.update(cfg or {})
    R = rm.R
    sc = rm.sc
    if c["collar"]:
        lv_collar_dome(rm, *c["collar"])
    if c["ant"]:
        t, a, h = c["ant"]
        pos, _ = rm.dpt(t, a)
        antenna(rm.L[2], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, h * sc + 0.3)
    if c["band3"]:
        dome_band(rm, rm.L[3], c["band3"][0], c["band3"][1], 0.02, "L3Band", top_edge=False)
    if c["mod3"]:
        t, a = c["mod3"][:2]
        pos, _ = rm.dpt(t, a)
        w, d, h = c["mod_size"] or (1.2 * sc + 0.2, 0.85 * sc + 0.15, 0.55)
        lv_module(rm.L[3], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, yaw=a + 90.0, w=w, d=d, h=h)
    if c["band4"]:
        dome_band(rm, rm.L[4], c["band4"][0], c["band4"][1], 0.02, "L4Band", top_edge=False)
    if c["fins4"]:
        t, a = c["fins4"][:2]
        pos, _ = rm.dpt(t, a)
        lv_fins(rm.L[4], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, yaw=a, n=c["fin_n"] or (4 if R < 4.5 else 5),
                h=0.75 * sc + 0.2, length=0.9 * sc + 0.1)
    if c["annex4"]:
        t, a = c["annex4"][:2]
        pos, _ = rm.dpt(t, a)
        L = c["annex_len"] or (1.4 * sc + 0.5)
        lv_annex(rm.L[4], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.05, yaw=a + 90.0, L=L, r=0.30 * sc + 0.14,
                 seg=8 if rm.size == 0 else 10)
    if c["crown5"]:
        t0, t1 = c["crown5"]
        dome_band(rm, rm.L[5], t0, t1, 0.07, "L5Gold", top_edge=rm.size >= 1)
        rr, zz = rm.dome_rz(t1)
        nr, nz = rm.dome_nrz(t1)
        crown_teeth(rm.L[5], rr + nr * 0.03, zz + nz * 0.03 - 0.03, n=8, h=0.2 * sc + 0.1, w=0.18)
    if c["beacon5"]:
        if c["beacon5"] == "top":
            lv_beacon(rm, rm.L[5], 0.0, 0.0, rm.top_z - 0.02, h=0.6 * sc + 0.3)
        else:
            x, y, z = c["beacon5"]
            lv_beacon(rm, rm.L[5], x, y, z, h=0.6 * sc + 0.3)
    if c["emblem5"]:
        t, a = c["emblem5"]
        pos, nor = rm.dpt(t, a, off=0.02)
        lv_emblem(rm.L[5], pos, nor, size=c["emblem_size"] or (0.9 * sc + 0.2), xdir=(0, 0, 1))


def auto_sites(rm, obstacles, D, prefer=-80.0, keep=None):
    """Pick deck sites for the podium level parts, clear of `obstacles` [(x, y, radius)].
    Greedy: largest clearance, a small bonus toward azimuth `prefer` (seen by the thumbnail and game cameras).
    Returns a cfg dict for levels_podium."""
    Rw = rm.Rw
    sc = rm.sc
    need = dict(mod3=0.75 * sc + 0.25, annex4=0.85 * sc + 0.25, fins4=0.65 * sc + 0.2, emblem5=0.45 * sc + 0.15,
                ant=0.35, beacon5=0.35)
    lim = Rw - 0.25
    cands = []
    for f in (0.86, 0.66, 0.45, 0.25):
        ring = (Rw - 0.3) * f
        n = max(8, int(2 * pi * ring / 0.6))
        for k in range(n):
            a = 360.0 * k / n
            cands.append((ring * cos(radians(a)), ring * sin(radians(a)), a))
    placed = []
    out = {}
    for name in ("mod3", "annex4", "fins4", "emblem5", "ant", "beacon5"):
        best, bscore = None, -1e9
        for (x, y, a) in cands:
            r_need = need[name]
            if hypot(x, y) + r_need > lim:
                continue
            clear = min([hypot(x - ox, y - oy) - orr for (ox, oy, orr) in obstacles + placed] or [9.0]) - r_need
            if clear < 0.0:
                continue
            score = min(clear, 1.5) + 0.5 * cos(radians(a - prefer)) + (0.3 if name in ("ant", "beacon5") and
                                                                        hypot(x, y) > (Rw - 0.3) * 0.7 else 0.0)
            if score > bscore:
                best, bscore = (x, y, a), score
        if best is None:
            continue
        x, y, a = best
        placed.append((x, y, need[name]))
        yaw = a + 90.0
        if name == "ant":
            out["ant"] = (x, y, 1.0)
        elif name == "beacon5":
            out["beacon5"] = (x, y, D + 0.02)
        elif name == "emblem5":
            out["emblem5"] = (x, y, D + 0.06, 0, 0, 1)
            out["emblem_x"] = (cos(radians(a)), sin(radians(a)), 0)
        else:
            out[name] = (x, y, yaw)
    out["emblem_size"] = 0.7 + 0.12 * rm.size
    if keep:
        out.update(keep)
    return out


def levels_podium(rm, cfg):
    """Upgrade parts on a podium (drum + deck).  cfg: ant = (x, y, h), mod3/fins4/annex4 = (x, y, yaw[, z]);
    beacon5 = (x, y, z); emblem5 = (x, y, z, nx, ny, nz); bands go round the drum wall."""
    D = rm.D
    Rw = rm.Rw
    seg = rm.seg
    R = rm.R
    sc = rm.sc
    c = dict(trim=True, band3=(D - 0.42, D - 0.34), band4=(1.66, 1.74), crown5=True)
    c.update(cfg)
    if c["trim"]:
        drum_band(rm.L[2], Rw, WALL_TOP - 0.06, WALL_TOP + 0.10, 0.05, "Trim", seg=seg)
        n = max(8, seg // 3) if rm.size >= 2 else 0
        for k in range(n):
            a = 360.0 * (k + 0.5) / n
            with rm.L[2].at(RZ(a), T(Rw + 0.05, 0, WALL_TOP + 0.02)):
                rm.L[2].box((0.015, 0, 0), (0.03, 0.08, 0.08), "Frame", mats={"-x": None})
    if c.get("ant"):
        x, y, h = c["ant"]
        antenna(rm.L[2], x, y, c.get("ant_z", D + 0.02), h * sc + 0.4)
    if c["band3"]:
        drum_band(rm.L[3], Rw, c["band3"][0], c["band3"][1], 0.02, "L3Band", seg=seg, top_edge=False)
    if c.get("mod3"):
        x, y, yaw = c["mod3"][:3]
        z = c["mod3"][3] if len(c["mod3"]) > 3 else D + 0.02
        lv_module(rm.L[3], x, y, z, yaw=yaw, w=1.1 * sc + 0.25, d=0.8 * sc + 0.15, h=0.55, sink=0.02)
    if c["band4"]:
        drum_band(rm.L[4], Rw, c["band4"][0], c["band4"][1], 0.02, "L4Band", seg=seg, top_edge=False)
    if c.get("fins4"):
        x, y, yaw = c["fins4"][:3]
        z = c["fins4"][3] if len(c["fins4"]) > 3 else D + 0.02
        lv_fins(rm.L[4], x, y, z, yaw=yaw, n=4 if R < 4.5 else 5, h=0.75 * sc + 0.2, length=0.9 * sc + 0.1, sink=0.02)
    if c.get("annex4"):
        x, y, yaw = c["annex4"][:3]
        z = c["annex4"][3] if len(c["annex4"]) > 3 else D + 0.02
        lv_annex(rm.L[4], x, y, z + 0.30, yaw=yaw, L=1.4 * sc + 0.5, r=0.30 * sc + 0.14, seg=8 if rm.size == 0 else 10)
    if c["crown5"]:
        top = D + 0.16
        prof = [(Rw + 0.10, top - 0.02), (Rw + 0.10, top + 0.10), (Rw - 0.16, top + 0.10)]
        rm.L[5].lathe_a(prof, reg_angles(seg), "L5Gold")
        crown_teeth(rm.L[5], Rw + 0.02, top + 0.09, n=12 if R > 5 else 8, h=0.24 * sc + 0.08)
    if c.get("beacon5"):
        x, y, z = c["beacon5"]
        lv_beacon(rm, rm.L[5], x, y, z, h=0.6 * sc + 0.3)
    if c.get("emblem5"):
        x, y, z, nx, ny, nz = c["emblem5"]
        lv_emblem(rm.L[5], Vector((x, y, z)), Vector((nx, ny, nz)), size=c.get("emblem_size", 0.9 * sc + 0.2),
                  xdir=c.get("emblem_x", (1, 0, 0)))


# --------------------------------------------------------------------------------------
# Furniture and machines (interiors).  Local +X = toward the wall unless stated.
# --------------------------------------------------------------------------------------
def bunk(p, blanket="Accent"):
    """Single bed, 2.0 x 0.9, head at local +X (toward the wall).  50 triangles."""
    p.box0(0, 0, F, 2.0, 0.9, 0.30, "Frame", mats={"-z": None})
    p.box0(0.02, 0, F + 0.30, 1.9, 0.84, 0.12, "Hull", mats={"-z": None})
    p.box0(-0.40, 0, F + 0.30, 1.10, 0.88, 0.16, blanket, mats={"-z": None})
    p.box0(0.66, 0, F + 0.42, 0.40, 0.60, 0.08, "Hull", mats={"-z": None})
    p.box0(1.04, 0, F, 0.08, 0.92, 0.80, "HullDark", mats={"-z": None})


def bunk_double(p, blanket="Accent"):
    """Two-tier bunk, 2.0 x 0.9 x 1.7, head at local +X.  About 100 triangles."""
    for sx in (-1, 1):
        p.box0(sx * 0.98, 0, F, 0.07, 0.92, 1.70, "HullDark", mats={"-z": None})
    for zb in (0.24, 1.10):
        p.box0(0, 0, F + zb, 1.9, 0.86, 0.10, "Frame", mats={"-z": None})
        p.box0(0.02, 0, F + zb + 0.10, 1.82, 0.80, 0.10, "Hull", mats={"-z": None})
        p.box0(-0.38, 0, F + zb + 0.10, 1.05, 0.84, 0.14, blanket, mats={"-z": None})
        p.box0(0.62, 0, F + zb + 0.20, 0.36, 0.56, 0.07, "Hull", mats={"-z": None})
    p.box0(0.0, 0.46, F + 1.42, 1.9, 0.04, 0.05, "Frame")


def locker(p, w=0.6, d=0.5, h=1.8, mat="Hull", stripe="Accent"):
    """Locker at the local origin, door toward local -X.  30 triangles."""
    p.box0(0, 0, F, d, w, h, mat, mats={"-z": None})
    p.box((-d / 2 - 0.006, 0, F + h * 0.62), (0.012, w * 0.82, 0.07), stripe, mats={"+x": None})
    p.box((-d / 2 - 0.006, w * 0.3, F + h * 0.45), (0.012, 0.04, 0.22), "Frame", mats={"+x": None})


def table_round(p, x, y, r, h=0.74, top="Hull", seg=12):
    p.vcyl(x, y, F, F + 0.05, r * 0.45, seg=8, mat="Frame", cap0=False)
    p.vcyl(x, y, F + 0.05, F + h - 0.05, 0.07, seg=6, mat="Frame", cap0=False, cap1=False)
    p.vcyl(x, y, F + h - 0.05, F + h, r, seg=seg, mat=top, cap0=True)


def table_rect(p, x, y, w, d, h=0.74, yaw=0.0, top="Hull"):
    with p.at(T(x, y, 0), RZ(yaw)):
        for sx in (-1, 1):
            p.box0(sx * (w / 2 - 0.08), 0, F, 0.07, d * 0.8, h - 0.05, "Frame", mats={"-z": None, "+z": None})
        p.box0(0, 0, F + h - 0.05, w, d, 0.05, top)


def stool(p, x, y, top="Accent"):
    p.vcyl(x, y, F, F + 0.40, 0.05, seg=4, mat="Frame", cap0=False, cap1=False)
    p.vcyl(x, y, F + 0.40, F + 0.47, 0.17, seg=8, mat=top, cap0=True)


def chair(p, x, y, yaw=0.0, seat="Accent"):
    """Chair facing local +X (backrest at -X).  About 26 triangles."""
    with p.at(T(x, y, 0), RZ(yaw)):
        p.box0(0, 0, F, 0.08, 0.08, 0.42, "Frame", mats={"-z": None, "+z": None})
        p.box0(0, 0, F + 0.42, 0.46, 0.46, 0.07, seat)
        p.box0(-0.21, 0, F + 0.49, 0.05, 0.42, 0.42, seat, mats={"-z": None})


def console(p, w=1.0, glow="Window", mat="Hull"):
    """Desk console at local origin, the operator stands at local +X.  About 40 triangles."""
    p.box0(0, 0, F, 0.6, w, 0.78, mat, mats={"-z": None})
    p.box((0.06, 0, F + 0.80), (0.46, w - 0.06, 0.04), "Frame", mats={"-z": None})
    with p.at(T(-0.12, 0, F + 0.82), RY(-28.0)):
        p.box((0, 0, 0.22), (0.05, w * 0.84, 0.42), "Frame", mats={"-z": None})
        p.box((0.03, 0, 0.22), (0.012, w * 0.76, 0.34), glow, mats={"-x": None})


def cabinet(p, w=1.2, d=0.5, h=1.2, mat="Hull", stripe="Accent"):
    """Cabinet, front toward local -X.  About 30 triangles."""
    p.box0(0, 0, F, d, w, h, mat, mats={"-z": None})
    p.box((-d / 2 - 0.006, 0, F + h - 0.14), (0.012, w - 0.1, 0.06), stripe, mats={"+x": None})
    p.box((-d / 2 - 0.006, 0, F + h * 0.45), (0.012, w - 0.12, h * 0.62), "HullDark", mats={"+x": None})


def crate(p, x, y, s=0.6, z=None, mat="Cargo", band="Frame", yaw=0.0):
    z = F if z is None else z
    with p.at(T(x, y, z), RZ(yaw)):
        p.box0(0, 0, 0, s, s, s, mat, mats={"-z": None})
        p.box0(0, 0, s * 0.38, s * 1.03, s * 1.03, s * 0.2, band, mats={"-z": None, "+z": None})


def plant_pot(p, x, y, r=0.35, big=True):
    p.vcyl(x, y, F, F + 0.5, r * 0.8, r, seg=8, mat="HullDark", cap0=False, cap1=False)
    with p.at(T(x, y, F + 0.46)):
        p.cap_disc(r * 0.96, 0.0, "Soil", seg=8)
        p.sphere((0, 0, 0.40 * r / 0.35), 0.5 * r / 0.35, "Plant", seg=7, rings=3, smooth=False, scale=(1, 1, 0.85))
        if big:
            p.sphere((0.15, 0.08, 0.80 * r / 0.35), 0.3 * r / 0.35, "PlantDark", seg=5, rings=3, smooth=False)


def rug_disc(p, r, x=0.0, y=0.0, mat="Fabric", seg=16):
    with p.at(T(x, y, 0)):
        p.cap_disc(r, F + 0.008, mat, seg=seg)


def floor_ring_mark(p, r0, r1, mat="Accent", seg=24, z=None):
    p.ring_flat(r0, r1, (F + 0.01) if z is None else z, mat, seg=seg)


def workbench(p, w=1.8, d=0.75, stripe="Accent"):
    """Bench at the local origin, worker at local -X.  About 70 triangles."""
    p.box0(0, 0, F + 0.80, d, w, 0.07, "Metal")
    for sy in (-1, 1):
        p.box0(0, sy * (w / 2 - 0.08), F, d * 0.9, 0.07, 0.80, "Frame", mats={"-z": None, "+z": None})
    p.box0(0.05, 0, F + 0.22, d * 0.85, w - 0.2, 0.05, "HullDark", mats={"-z": None})
    p.box0(d / 2 - 0.04, 0, F + 0.87, 0.07, w, 0.55, "HullDark", mats={"-z": None})
    p.box0(0.0, -w * 0.28, F + 0.87, 0.34, 0.40, 0.22, stripe, mats={"-z": None})


def shelf_rack(p, w=1.8, d=0.55, h=1.9, levels=4, fill=0.75, seed=3, mats=("Cargo", "Accent", "Hull", "Cargo")):
    rng = random.Random(seed)
    for k in range(levels):
        z = F + 0.08 + (h - 0.12) * k / (levels - 1)
        p.box0(0, 0, z, d, w, 0.04, "Metal", mats={"-z": None} if k else None)
    for sy in (-1, 1):
        for sx in (-1, 1):
            p.box0(sx * (d / 2 - 0.03), sy * (w / 2 - 0.03), F, 0.05, 0.05, h, "Frame", mats={"-z": None})
    for k in range(levels - 1):
        z = F + 0.12 + (h - 0.12) * k / (levels - 1)
        nb = max(2, int(w / 0.45))
        for j in range(nb):
            if rng.random() > fill:
                continue
            yy = -w / 2 + (j + 0.5) * w / nb
            hh = rng.uniform(0.18, min(0.38, (h - 0.12) / (levels - 1) - 0.08))
            p.box0(0, yy, z, d * 0.8, w / nb * 0.8, hh, rng.choice(mats), mats={"-z": None})


# --------------------------------------------------------------------------------------
# Scene, AO bake, export, inspection
# --------------------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
                 bpy.data.images):
        for item in list(coll):
            coll.remove(item)


def anchor_object(name, pos, yaw=0.0):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = "ARROWS"
    ob.empty_display_size = 0.4
    ob.location = pos
    if yaw:
        ob.rotation_euler = (0.0, 0.0, radians(yaw))
    bpy.context.scene.collection.objects.link(ob)
    return ob


# Which objects shade which (the game hides Roof to show Interior, and shows L2..Ln cumulatively):
AO_SETS = {
    "Base": ("Base", "Interior", "Lights"),
    "Interior": ("Base", "Interior"),
    "Lights": ("Base", "Lights"),
    "Roof": ("Base", "Roof"),
    "L2": ("Base", "Roof", "L2"),
    "L3": ("Base", "Roof", "L2", "L3"),
    "L4": ("Base", "Roof", "L2", "L3", "L4"),
    "L5": ("Base", "Roof", "L2", "L3", "L4", "L5"),
}


def ao_sets_for(objs):
    """AO_SETS plus the 3.0 wall segments: every Wall_* shades and is shaded like Base (the game hides a segment
    only where a doorway replaces it)."""
    walls = tuple(sorted(n for n in objs if n.startswith("Wall_")))
    talls = tuple(sorted(n for n in objs if n.startswith("Tall_")))
    if not walls and not talls:
        return AO_SETS
    out = {}
    for k, v in AO_SETS.items():
        out[k] = tuple(v) + (walls if ("Base" in v and k != "Lights") else ()) + (talls if "Interior" in v else ())
    for w in walls:
        out[w] = ("Base", "Interior") + walls + talls
    for t in talls:
        out[t] = ("Base", "Interior") + walls + talls
    return out


def _hemisphere(n):
    """Cosine-weighted directions around +Z (Fibonacci spiral on the unit disc)."""
    ga = pi * (3.0 - sqrt(5.0))
    out = []
    for i in range(n):
        r = sqrt((i + 0.5) / n)
        a = i * ga
        x, y = r * cos(a), r * sin(a)
        out.append((x, y, sqrt(max(0.0, 1.0 - x * x - y * y))))
    return out


def _bvh(objs):
    verts, polys = [], []
    for ob in objs:
        me = ob.data
        mw = ob.matrix_world
        skip = {i for i, m in enumerate(me.materials) if m is not None and m.name.split(".")[0] in NON_OCCLUDING}
        off = len(verts)
        verts.extend(mw @ v.co for v in me.vertices)
        for p in me.polygons:
            if p.material_index in skip:
                continue
            polys.append(tuple(i + off for i in p.vertices))
    if not polys:
        return None
    return BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)


# Same method and curve as ART-B (tools/blender/ext_common.py bake_ao; docs/requests/ART-B-to-ART-A.md) so both
# sets of models look the same in the game: 48 cosine rays per corner, 18 % inset, weight 1 - (d/dist)^2,
# ground plane z = 0, value = max(min_ao, 1 - occ).  A global contrast change belongs in the game shader.
AO_DEFAULT = dict(dist=1.6, samples=48, strength=1.0, gamma=1.0, min_ao=0.18, inset=0.18, seed=11)


def bake_ao(objs, sets=AO_SETS, dist=1.6, samples=48, strength=1.0, gamma=1.0, min_ao=0.18, inset=0.18, seed=11,
            name="AO"):
    """Per face corner: `samples` cosine-weighted rays from a point `inset` of the way from the corner to the face
    centre; occlusion weight 1 - (d/dist)^2; an analytic ground plane at z = 0; corners buried inside another
    solid (most hits are back faces) take 0.55 x the mean of the visible corners of their face; corners that
    share a vertex and a normal are averaged (smooth AO).  value = max(min_ao, (1 - strength*occ)^gamma).
    Writes a FLOAT_COLOR corner attribute (white = open, linear) and makes it the active colour."""
    rng = random.Random(seed)
    dirs = _hemisphere(samples)
    cache = {}
    total = 0
    t0 = time.time()
    for oname, ob in objs.items():
        if ob.type != "MESH" or not ob.data.polygons:
            continue
        occ = tuple(sorted(n for n in sets.get(oname, (oname,)) if n in objs))
        if oname not in occ:
            occ = tuple(sorted(occ + (oname,)))
        if occ not in cache:
            cache[occ] = _bvh([objs[n] for n in occ])
        bvh = cache[occ]
        me = ob.data
        mw = ob.matrix_world
        rot = mw.to_3x3()
        wv = [mw @ v.co for v in me.vertices]
        nl = len(me.loops)
        lv = [0] * nl
        me.loops.foreach_get("vertex_index", lv)
        cn = [0.0] * (nl * 3)
        me.corner_normals.foreach_get("vector", cn)
        vals = [1.0] * nl
        embedded = [False] * nl
        for poly in me.polygons:
            ls, lt = poly.loop_start, poly.loop_total
            pv = [wv[lv[li]] for li in range(ls, ls + lt)]
            centre = sum(pv, Vector((0, 0, 0))) / lt
            fn = (rot @ poly.normal).normalized()
            u, v, w = BA._basis(fn)
            for k, li in enumerate(range(ls, ls + lt)):
                p0 = pv[k] + (centre - pv[k]) * inset
                o = p0 + fn * 0.004
                phi = rng.uniform(0.0, 2 * pi)
                cp, sp = cos(phi), sin(phi)
                uu = u * cp + v * sp
                vv = v * cp - u * sp
                acc = 0.0
                backs = 0
                for (dx, dy, dz) in dirs:
                    d = uu * dx + vv * dy + w * dz
                    hd = None
                    if bvh is not None:
                        loc, hn, hi, hdist = bvh.ray_cast(o, d, dist)
                        if loc is not None:
                            hd = hdist
                            if hn.dot(d) > 0.0:
                                backs += 1
                    if o.z > 1e-4 and d.z < -1e-6:
                        tg = -o.z / d.z
                        if tg < dist and (hd is None or tg < hd):
                            hd = tg
                    if hd is not None:
                        q = hd / dist
                        acc += 1.0 - q * q
                total += len(dirs)
                occv = acc / len(dirs)
                if backs > 0.55 * len(dirs):
                    embedded[li] = True
                vals[li] = max(min_ao, max(0.0, 1.0 - strength * occv) ** gamma)
        for poly in me.polygons:
            ls, lt = poly.loop_start, poly.loop_total
            vis = [vals[li] for li in range(ls, ls + lt) if not embedded[li]]
            ref = sum(vis) / len(vis) if vis else 1.0
            for li in range(ls, ls + lt):
                if embedded[li]:
                    vals[li] = max(min_ao, 0.55 * ref)
        groups = {}
        for li in range(nl):
            key = (lv[li], round(cn[3 * li], 2), round(cn[3 * li + 1], 2), round(cn[3 * li + 2], 2))
            groups.setdefault(key, []).append(li)
        for lis in groups.values():
            if len(lis) > 1:
                m = sum(vals[li] for li in lis) / len(lis)
                for li in lis:
                    vals[li] = m
        attr = me.color_attributes.get(name) or me.color_attributes.new(name=name, type="FLOAT_COLOR", domain="CORNER")
        flat = []
        for val in vals:
            flat.extend((val, val, val, 1.0))
        attr.data.foreach_set("color", flat)
        me.color_attributes.active_color = attr
        try:
            me.color_attributes.render_color_index = list(me.color_attributes).index(attr)
        except Exception:
            pass
        me.update()
    return total, time.time() - t0


def _replace_retry(tmp, path):
    for attempt in range(40):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.25)
    os.replace(tmp, path)


def export_glb_atomic(path):
    tmp = path[:-4] + ".tmp.glb"
    if os.path.exists(tmp):
        os.remove(tmp)
    bpy.ops.export_scene.gltf(
        filepath=tmp, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False, export_skins=False, export_morph=False,
        export_extras=False, export_materials="EXPORT", export_normals=True, export_tangents=False,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_active_vertex_color_when_no_material=True,
    )
    _replace_retry(tmp, path)


def copy_atomic(src, dst):
    ext = os.path.splitext(dst)[1]
    tmp = dst[:-len(ext)] + ".tmp" + ext
    with open(src, "rb") as fi, open(tmp, "wb") as fo:
        fo.write(fi.read())
    _replace_retry(tmp, dst)


def read_glb(path):
    with open(path, "rb") as fh:
        magic, version, length = struct.unpack("<4sII", fh.read(12))
        assert magic == b"glTF", "not a GLB file"
        clen, ctype = struct.unpack("<II", fh.read(8))
        return json.loads(fh.read(clen).decode("utf-8"))


def inspect_glb(path):
    g = read_glb(path)
    scene = g["scenes"][g.get("scene", 0)]
    nodes = g.get("nodes", [])
    top = [nodes[i].get("name") for i in scene["nodes"]]
    tris, color0, mats_by = {}, {}, {}
    used = set()
    for i in scene["nodes"]:
        n = nodes[i]
        if "mesh" not in n:
            continue
        cnt, ok, names = 0, True, set()
        for prim in g["meshes"][n["mesh"]]["primitives"]:
            acc = g["accessors"][prim["indices"]] if "indices" in prim else g["accessors"][prim["attributes"]["POSITION"]]
            cnt += acc["count"] // 3
            if "material" in prim:
                nm = g["materials"][prim["material"]]["name"]
                used.add(nm)
                names.add(nm)
            if "COLOR_0" not in prim["attributes"]:
                ok = False
        tris[n.get("name")] = cnt
        color0[n.get("name")] = ok
        mats_by[n.get("name")] = sorted(names)
    alpha = {m["name"]: m.get("alphaMode", "OPAQUE") for m in g.get("materials", [])}
    return dict(top=top, tris=tris, color0=color0, materials=sorted(used), mats_by=mats_by, alpha=alpha,
                mesh_nodes=[nodes[i].get("name") for i in scene["nodes"] if "mesh" in nodes[i]],
                empties=[nodes[i].get("name") for i in scene["nodes"] if "mesh" not in nodes[i]],
                child_nodes=any("children" in nodes[i] for i in scene["nodes"]),
                extras=[k for k in ("cameras", "animations", "skins", "images") if k in g])


def part_stats(part):
    tris = sum(len(f) - 2 for f in part.faces)
    if not part.verts:
        return dict(tris=0, lo=(0, 0, 0), hi=(0, 0, 0), radius=0.0)
    xs = [v.x for v in part.verts]
    ys = [v.y for v in part.verts]
    zs = [v.z for v in part.verts]
    rad = max(math.hypot(v.x, v.y) for v in part.verts)
    return dict(tris=tris, lo=(min(xs), min(ys), min(zs)), hi=(max(xs), max(ys), max(zs)), radius=rad)


def check_interior(rm):
    """Interior stays inside the inner wall and under the roof shell (head room of the shell)."""
    flags = []
    worst_r, worst_z = -9.0, -9.0
    wr = wz = None
    for v in rm.interior.verts:
        r = math.hypot(v.x, v.y)
        if r - rm.Ri > worst_r:
            worst_r, wr = r - rm.Ri, (round(v.x, 2), round(v.y, 2), round(v.z, 2))
        dz = v.z - rm.headroom(v.x, v.y)
        if dz > worst_z:
            worst_z, wz = dz, (round(v.x, 2), round(v.y, 2), round(v.z, 2))
    if worst_r > 0.02:
        flags.append("Interior passes the inner wall by %.2f m at %s" % (worst_r, wr))
    if worst_z > 0.02:
        flags.append("Interior passes the roof by %.2f m at %s" % (worst_z, wz))
    return flags


# --------------------------------------------------------------------------------------
# Draw-call budget: at most MAX_SURFACES materials on the Interior (and on each Tall_* part)
# --------------------------------------------------------------------------------------
MAX_SURFACES = 8
PALETTE_KEEP = ("Accent", "Neon", "Screen", "Glass", "Soil", "Palette", "PaletteMetal")   # named: the game uses them


def _spec_of(mset, name):
    try:
        return mset.spec(name)
    except KeyError:
        return {}


WALL_SHELL = ("Hull", "HullDark", "Accent", "Frame", "Trim", "Window", "Glass", "Metal", "Rubber")   # models.gd


def palette_target(mset, name, keep=()):
    """Where a material goes: 'Palette' (plain), 'PaletteMetal' (metal), or itself (named or emissive)."""
    if name in PALETTE_KEEP or name in keep:
        return name
    sp = _spec_of(mset, name)
    if sp.get("emit") or sp.get("alpha", 1.0) < 1.0:
        return "LightStrip" if name == "Light" else name
    return "PaletteMetal" if sp.get("metal", 0.0) >= 0.3 else "Palette"


def palette_merge(o, mset, max_surfaces=MAX_SURFACES, keep=()):
    """Merge the plain materials of object `o` into the palette materials (the face colour goes into the corner
    colour attribute, multiplied with the baked AO); then, while the object still has more than `max_surfaces`
    materials, fold the least used coloured emissive into the nearest emissive colour, then PaletteMetal into
    Palette.  Returns (before, after) material counts."""
    me = o.data
    names = [m.name.split(".")[0] if m else "" for m in me.materials]
    before = len(set(names))
    attr = me.color_attributes.active_color or (me.color_attributes[0] if me.color_attributes else None)
    target = {nm: palette_target(mset, nm, keep) for nm in set(names)}
    use = {}
    for p in me.polygons:
        t = target[names[p.material_index]]
        use[t] = use.get(t, 0) + 1

    def lin(nm):
        sp = _spec_of(mset, nm)
        h = sp.get("color", "#ffffff")
        return BA.hex_to_linear(h)

    def emit_col(nm):
        sp = _spec_of(mset, nm)
        return BA.hex_to_linear(sp.get("emit", sp.get("color", "#ffffff")))
    fixed = ("LightStrip", "Screen", "Neon", "Accent", "Glass", "Soil", "Palette", "PaletteMetal")
    while len(use) > max_surfaces:
        em = [k for k in use if k not in fixed]
        k = min(em, key=lambda q: use[q]) if em else None
        others = [q for q in use if q != k and q not in ("Accent", "Glass", "Soil", "Palette", "PaletteMetal", "Screen")]
        if em and others:
            ck = emit_col(k)
            dst = min(others, key=lambda q: sum((a - b) ** 2 for a, b in zip(ck, emit_col(q))))
        elif "PaletteMetal" in use:
            k, dst = "PaletteMetal", "Palette"
        elif "Soil" in use:
            k, dst = "Soil", "Palette"
        else:
            break
        for nm, t in list(target.items()):
            if t == k:
                target[nm] = dst
        use[dst] = use.get(dst, 0) + use.pop(k)
    # rewrite: the new material slots, the corner colours of the palette faces
    order = sorted(set(target.values()))
    slot = {}
    orig = [p.material_index for p in me.polygons]          # clear() resets the indices
    me.materials.clear()
    for nm in order:
        me.materials.append(mset.get(nm))
        slot[nm] = len(me.materials) - 1
    cols = [0.0] * (len(attr.data) * 4) if attr is not None else None
    if attr is not None:
        attr.data.foreach_get("color", cols)
    for p in me.polygons:
        src = names[orig[p.index]]
        t = target[src]
        if attr is not None and t in ("Palette", "PaletteMetal") and src not in ("Palette", "PaletteMetal"):
            r, g, b = lin(src)
            for li in p.loop_indices:
                cols[li * 4] *= r
                cols[li * 4 + 1] *= g
                cols[li * 4 + 2] *= b
        p.material_index = slot[t]
    if attr is not None:
        attr.data.foreach_set("color", cols)
    me.update()
    return before, len(order)


def build_file(rm, path, also=(), ao=None):
    """Turn a finished Room into objects, bake AO, export atomically.  Returns (objs, rays, seconds)."""
    t0 = time.time()
    reset_scene()
    mset = MatSet(ACCENTS[rm.cat])
    objs = {}
    for part in rm.parts():
        if not part.faces:
            continue
        objs[part.name] = BA.part_to_object(part, mset)
    for a in rm.anchors:
        anchor_object(a[0], a[1], a[2] if len(a) > 2 else 0.0)
    bpy.context.view_layer.update()
    kw = dict(AO_DEFAULT)
    kw.update(ao or {})
    kw["sets"] = ao_sets_for(objs)
    rays, secs = bake_ao(objs, **kw)
    if getattr(rm, "v3", False):
        rm.surfaces = {}
        for nm, o in objs.items():
            if nm == "Interior" or nm.startswith("Tall_"):
                rm.surfaces[nm] = palette_merge(o, mset)
            elif nm.startswith("Wall_"):
                # wall-side items: their plain materials join the palette; the wall shell keeps its names
                palette_merge(o, mset, max_surfaces=99, keep=WALL_SHELL)
    export_glb_atomic(path)
    for extra in also:
        copy_atomic(path, extra)
    return objs, rays, time.time() - t0
