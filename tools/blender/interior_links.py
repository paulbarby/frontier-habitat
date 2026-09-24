"""
Frontier Habitat 3.0 - ART-HAB: doorway, wall patch, corridor and corridor rib (Blender 5.2, --background only).

Run from the project root:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/interior_links.py -- [--only doorway,wall_patch,corridor,corridor_rib]

assets/models/doorway.glb (docs/V3_DESIGN.md section 7.2)
  Origin at z = 0 (the room's ground level, like the room files; floor top 0.14) ON THE WALL LINE: the outer face
  of the room wall, radius Rw = R - 0.32.  +X points out along the corridor, +Y to the left seen from the room.
  Clear opening 1.50 m wide x 2.10 m high (floor top to 2.24).  Frame 2.20 m wide (y +-1.10), jamb x -0.38..0.06;
  room-side pocket housings x -0.50..-0.38 reach y +-1.62 (the open leaves slide into them).
  A collar x 0.02..0.46 caps the corridor tube (outer y +-1.26, top 2.46; inner = the corridor inside, y +-1.00).
  Objects (every one split at WALL_TOP 1.40 so the game can cut it with the room roof):
    Frame      jambs, sill, collar below 1.40            FrameTop   jambs, header, collar above 1.40
    DoorL      left leaf (-Y side) below 1.40            DoorLTop   the same leaf above 1.40
    DoorR      right leaf (+Y side) below 1.40           DoorRTop   the same leaf above 1.40
    Lights     green status strips (material Glow) on the inner faces of the opening only, all below 1.40
    Sign       exit signs on the header (room side) and on the collar (corridor side), above 1.40
  Leaves: closed DoorL y -0.79..0, DoorR y 0..0.79, plane x -0.47..-0.41.  Open = DoorL moved -0.75 m on Y,
  DoorR +0.75 m on Y.  They slide into the pocket housings.  Material Accent (header stripe, collar stripe)
  is tinted by the game to the room's category colour.  Anchor_Room x -1.05, Anchor_Corridor x +1.00.
  In the roof cutaway show Frame, DoorL, DoorR, Lights; hide FrameTop, DoorLTop, DoorRTop, Sign.

assets/models/wall_patch.glb
  One object Base: a straight slice of the 3.0 room wall, 1.00 m long on Y (y -0.5..0.5), outer face on x = 0,
  inner face x = -0.20, z 0.09..1.40, with the room band in material Accent (the game tints it to the room's
  category colour, so the band runs up to the door), battens and the two wall pipes.
  The game scales it on Y to close the part of a hidden wall segment that the doorway frame does not cover.

assets/models/corridor.glb     (unchanged contract: 1.0 m on X, the game scales it on X; Base + Roof)
assets/models/corridor_rib.glb (not scaled: a structural rib, 0.14 m on X; Base below 1.0 m, Roof = arch part;
  place one every 2.5 m along a corridor)
"""
import bpy
import os
import sys
import json
import math
import time
from math import sin, cos, pi, radians, degrees, hypot, sqrt, asin
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import rooms_kit as K           # noqa: E402
import interior_kit as IK       # noqa: E402
from rooms_kit import P, T, RX, RY, RZ, FLOOR_Z, WALL_TOP  # noqa: E402
from interior_kit import bbox, plate_x, plate_y, plate_z   # noqa: E402

F = FLOOR_Z
OPEN_HW = 0.75
FRAME_HW = 1.10
DOOR_TOP = F + 2.10
HEAD_TOP = 2.40
POCKET = (-0.50, -0.38)     # room-side jamb / pocket housing, 12 cm deep (the leaves slide into it)
POCKET_HW = 1.62            # the housing reaches this far from the door axis (the leaves open to 1.54)
MAIN = (-0.38, 0.06)        # the jamb in the wall plane
LEAF = (-0.47, -0.41)
LEAF_W = 0.79
COLLAR = (0.02, 0.46)
C_OUT = (1.26, 1.46)       # collar outer: wall half width, arch rise above z 1.0
C_IN = (1.00, 1.20)        # collar inner = corridor inside
C_WALL = 1.00              # the corridor wall height
REPORT = os.path.join(HERE, "interior_links_report.json")
# (critic round 4) above WALL_TOP every door part inside the wall line stays under the smallest room shell: this is
# the shell of the S domes measured at the wall line (worst: oxygen_plant_s) minus 1 cm, and no part rises above
# the door top (the lowest podium deck is 2.25).  x = offset from the wall line (negative = inside the room).
ENV = [(WALL_TOP, 0.00), (1.60, -0.04), (1.80, -0.09), (2.00, -0.18), (2.12, -0.25), (DOOR_TOP, -0.35)]


HOOD_X = (-0.52, COLLAR[0])      # the entry hood: the corridor profile carried inward to the pocket plane


def arch_z(y, hw=None, rise=None):
    """Top of the corridor outer U profile (C_OUT) at lateral offset y."""
    hw = C_OUT[0] if hw is None else hw
    rise = C_OUT[1] if rise is None else rise
    t = abs(y) / hw
    return C_WALL + rise * sqrt(max(0.0, 1.0 - t * t)) if t <= 1.0 else C_WALL


def env_x(z):
    if z <= ENV[0][0]:
        return ENV[0][1]
    for (za, xa), (zb, xb) in zip(ENV, ENV[1:]):
        if z <= zb:
            return xa + (xb - xa) * (z - za) / (zb - za)
    return ENV[-1][1]


# --------------------------------------------------------------------------------------
# Doorway
# --------------------------------------------------------------------------------------
def oquad(p, a, b, c, d, mat, want, smooth=False):
    """Quad whose normal points along `want` (the vertex order is reversed when needed)."""
    va, vb, vc = Vector(a), Vector(b), Vector(c)
    n = (vb - va).cross(vc - va)
    if n.length < 1e-12:
        n = (Vector(c) - va).cross(Vector(d) - va)
    if n.dot(Vector(want)) < 0:
        a, b, c, d = d, c, b, a
    p.quad(a, b, c, d, mat, smooth=smooth)


def radial_want(y, z, sign=1.0):
    """Outward direction of a U profile point (walls: +-Y; arch: away from the arch centre at z = C_WALL)."""
    v = Vector((0.0, y, max(0.0, z - C_WALL)))
    if v.length < 1e-9:
        v = Vector((0.0, 1.0 if y >= 0 else -1.0, 0.0))
    return v.normalized() * sign


def u_contour(hw, rise, zsplit=WALL_TOP, n_arch=10):
    """Points of a corridor-like U profile (y, z): up the -Y wall, over the arch, down the +Y wall.
    Includes a point at z = zsplit on both sides of the arch and at C_WALL."""
    pts = [(-hw, 0.0), (-hw, C_WALL)]
    ts = sorted({0.0, 180.0} | {180.0 * k / n_arch for k in range(1, n_arch)})
    t_split = degrees(asin(min(1.0, (zsplit - C_WALL) / rise)))
    ts = sorted(set([t for t in ts if abs(t - t_split) > 3 and abs(t - (180 - t_split)) > 3] + [t_split, 180 - t_split]))
    for t in ts[1:-1]:
        tr = radians(180.0 - t)
        pts.append((hw * cos(tr), C_WALL + rise * sin(tr)))
    pts += [(hw, C_WALL), (hw, 0.0)]
    return pts


def collar(lo, hi):
    """Doorway collar: the U ring from x COLLAR[0] to COLLAR[1] with 4 cm chamfers at both ends, the room stripe
    (Accent, tinted per room by the game) and a Frame trim line round the outside, two latch blocks.
    Faces below WALL_TOP go to `lo`, above to `hi`."""
    x0, x1 = COLLAR
    ch = 0.04
    out = u_contour(*C_OUT)
    outc = u_contour(C_OUT[0] - ch, C_OUT[1] - ch)
    inn = u_contour(*C_IN)
    n = len(out)

    def part(za, zb):
        return hi if 0.5 * (za + zb) > WALL_TOP + 1e-4 else lo
    for i in range(n - 1):
        (ya, za), (yb, zb) = out[i], out[i + 1]
        (ea, fa), (eb, fb) = outc[i], outc[i + 1]
        (yc, zc), (yd, zd) = inn[i], inn[i + 1]
        p = part(za, zb)
        sm = i not in (0, n - 2)
        wo = radial_want(0.5 * (ya + yb), 0.5 * (za + zb))
        oquad(p, (x1 - ch, ya, za), (x0 + ch, ya, za), (x0 + ch, yb, zb), (x1 - ch, yb, zb), "Hull", wo, smooth=sm)
        for (xe, xc_, dx) in ((x1, x1 - ch, 1), (x0, x0 + ch, -1)):       # chamfers
            oquad(p, (xc_, ya, za), (xe, ea, fa), (xe, eb, fb), (xc_, yb, zb), "Frame", wo + Vector((dx, 0, 0)))
        oquad(p, (x0, yc, zc), (x1, yc, zc), (x1, yd, zd), (x0, yd, zd), "Frame",
              -radial_want(0.5 * (yc + yd), 0.5 * (zc + zd)), smooth=sm)
        oquad(p, (x1, ea, fa), (x1, eb, fb), (x1, yd, zd), (x1, yc, zc), "Frame", (1, 0, 0))
        oquad(p, (x0, eb, fb), (x0, ea, fa), (x0, yc, zc), (x0, yd, zd), "HullDark", (-1, 0, 0))
    # the room stripe (x 0.20..0.30) and a Frame trim line (x 0.36..0.38) round the outside
    for (bx0, bx1, mat, off) in ((0.20, 0.30, "Accent", 0.02), (0.36, 0.38, "Frame", 0.012)):
        band = u_contour(C_OUT[0] + off, C_OUT[1] + off)
        for i in range(n - 1):
            (ya, za), (yb, zb) = band[i], band[i + 1]
            (yc, zc), (yd, zd) = out[i], out[i + 1]
            p = part(za, zb)
            wo = radial_want(0.5 * (ya + yb), 0.5 * (za + zb))
            oquad(p, (bx1, ya, za), (bx0, ya, za), (bx0, yb, zb), (bx1, yb, zb), mat, wo, smooth=i not in (0, n - 2))
            oquad(p, (bx1, ya, za), (bx1, yb, zb), (bx1, yd, zd), (bx1, yc, zc), mat, (1, 0, 0))
            oquad(p, (bx0, yb, zb), (bx0, ya, za), (bx0, yc, zc), (bx0, yd, zd), mat, (-1, 0, 0))
    # latch blocks on both sides and the collar feet
    for sy in (-1, 1):
        ya, yb = sorted((sy * C_OUT[0], sy * (C_OUT[0] + 0.07)))
        bbox(lo, 0.08, 0.18, ya, yb, 0.55, 0.80, "Frame", bevel=0.01)
        bbox(lo, 0.10, 0.16, min(ya, yb) - (0.0 if sy > 0 else 0.004), max(ya, yb) + (0.004 if sy > 0 else 0.0),
             0.62, 0.66, "Hazard")
        bbox(lo, x0 - 0.02, x1 + 0.02, sy * C_IN[0] if sy > 0 else -C_OUT[0] - 0.04,
             sy * C_OUT[0] + 0.04 if sy > 0 else -C_IN[0], 0.0, 0.10, "Frame", mats={"-z": None})


def jamb(lo, hi, sy):
    """One side (sy = -1 or +1): the jamb in the wall plane and ONE clean room-side profile, 12 cm deep, that is
    also the pocket housing of the leaf (open leaves slide into it; nothing shows outside the wall on S rooms).
    Split at WALL_TOP."""
    y0, y1 = (OPEN_HW, FRAME_HW) if sy > 0 else (-FRAME_HW, -OPEN_HW)
    p0, p1 = (OPEN_HW, POCKET_HW) if sy > 0 else (-POCKET_HW, -OPEN_HW)
    yi = sy * OPEN_HW
    bbox(lo, MAIN[0], MAIN[1], y0, y1, 0.0, WALL_TOP, "Hull")
    # above the wall top the jamb stays under the entry hood: its top follows the corridor arch
    ya_, yb_ = sorted((abs(y0), abs(y1)))
    ys = [ya_ + (yb_ - ya_) * k / 4 for k in range(5)]
    prof = [(sy * ys[0], WALL_TOP), (sy * ys[-1], WALL_TOP)] + [(sy * y, arch_z(y) - 0.03) for y in reversed(ys)]
    hi.prism_x(prof, MAIN[0], HOOD_X[1] - 0.01, "Hull")
    # the pocket housing (below the wall top only): back plate, front plate, far end; the slot faces the opening
    xa, xb = POCKET
    bbox(lo, xa, xa + 0.03, p0, p1, 0.0, WALL_TOP, "Hull")                 # room face
    bbox(lo, xb - 0.03, xb, p0, p1, 0.0, WALL_TOP, "Hull")                 # back
    pe0, pe1 = (POCKET_HW - 0.04, POCKET_HW) if sy > 0 else (-POCKET_HW, -POCKET_HW + 0.04)
    bbox(lo, xa + 0.03, xb - 0.03, pe0, pe1, 0.0, WALL_TOP, "Hull")        # far end
    bbox(lo, xa, xb, p0, p1, WALL_TOP - 0.03, WALL_TOP, "Frame")          # cap
    # room face: a recessed panel line and a Frame edge on the slot side
    plate_x(lo, xa - 0.002, min(p0, p1) + 0.05, max(p0, p1) - 0.05, 0.18, WALL_TOP - 0.05, "HullDark", facing=-1)
    plate_x(lo, xa - 0.004, min(p0, p1) + 0.08, max(p0, p1) - 0.08, 0.21, WALL_TOP - 0.05, "Hull", facing=-1)
    plate_x(lo, xa - 0.005, min(p0, p1) + 0.08, max(p0, p1) - 0.08, WALL_TOP - 0.20, WALL_TOP - 0.15, "Accent",
            facing=-1)
    # slot edges (Frame) on the opening face
    for part, za, zb in ((lo, F, WALL_TOP),):
        for (ea, eb) in ((POCKET[0], POCKET[0] + 0.03), (POCKET[1] - 0.03, POCKET[1])) +                 (((MAIN[0], MAIN[1]),) if part is lo else ()):
            plate_y(part, yi - sy * 0.002, ea, eb, za, zb, "Frame", facing=-sy)
    bbox(lo, POCKET[0] + 0.03, POCKET[1] - 0.03, min(p0, p1), max(p0, p1), 0.0, F + 0.004, "Frame", mats={"-z": None})


def leaf(lo, hi, sy):
    """Sliding leaf on the sy side, closed position.  Meeting edge at y = 0."""
    ya, yb = (0.0, LEAF_W) if sy > 0 else (-LEAF_W, 0.0)
    x0, x1 = LEAF
    bbox(lo, x0, x1, ya, yb, F + 0.005, WALL_TOP, "Hull")
    bbox(lo, x0 - 0.008, x1 + 0.008, -0.012 if sy < 0 else 0.0, 0.012 if sy > 0 else 0.0, F + 0.005, WALL_TOP, "Rubber")
    # the upper leaf: square top to the door top, its outer corner cut along the corridor arch
    ys = [LEAF_W * k / 6 for k in range(7)]
    top = [min(DOOR_TOP - 0.005, arch_z(y) - 0.04) for y in ys]
    prof = [(0.0, WALL_TOP), (sy * LEAF_W, WALL_TOP)] + [(sy * y, t) for y, t in reversed(list(zip(ys, top)))]
    hi.prism_x(prof, x0, x1, "Hull")
    zr = min(DOOR_TOP - 0.005, arch_z(0.012) - 0.04)
    bbox(hi, x0 - 0.008, x1 + 0.008, -0.012 if sy < 0 else 0.0, 0.012 if sy > 0 else 0.0, WALL_TOP, zr, "Rubber")
    for fx, face in ((x0 - 0.003, -1), (x1 + 0.003, 1)):
        yA, yB = ya + 0.05, yb - 0.05
        plate_x(lo, fx, yA, yB, 0.95, 1.03, "Trim", facing=face)
        for k in range(5):
            w = (yB - yA) / 5.0
            a, b = yA + w * k, yA + w * (k + 1)
            m = "Hazard" if k % 2 == 0 else "Rubber"
            if face > 0:
                lo.quad((fx, a, 0.22), (fx, b, 0.22), (fx, b, 0.36), (fx, a, 0.36), m)
            else:
                lo.quad((fx, b, 0.22), (fx, a, 0.22), (fx, a, 0.36), (fx, b, 0.36), m)
        yv0, yv1 = (0.14, 0.34) if sy > 0 else (-0.34, -0.14)
        plate_x(hi, fx + face * 0.001, yv0 - 0.03, yv1 + 0.03, 1.52, 2.04, "Frame", facing=face)
        plate_x(hi, fx + face * 0.003, yv0, yv1, 1.55, 2.01, "Visor", facing=face)
        for z in (0.62, 1.30):
            plate_x(lo, fx, yA, yB, z, z + 0.015, "Frame", facing=face)


def sill(lo, lights):
    x0, x1 = -0.70, COLLAR[1]
    bbox(lo, x0, x1, -FRAME_HW, FRAME_HW, -0.05, F + 0.012, "FloorDark", bevel=0.01)
    plate_z(lo, F + 0.0135, LEAF[0] - 0.02, LEAF[1] + 0.02, -OPEN_HW, OPEN_HW, "Frame")
    for k in range(8):
        ya = -OPEN_HW + 1.5 * k / 8.0
        yb = ya + 1.5 / 8.0
        lo.quad((x0 + 0.03, ya, F + 0.0135), (x0 + 0.12, ya, F + 0.0135), (x0 + 0.12, yb, F + 0.0135),
                (x0 + 0.03, yb, F + 0.0135), "Hazard" if k % 2 == 0 else "Rubber")


def status_strips(lights):
    """Green status strips on the inner (opening) faces only: one on each pocket housing, one on each jamb."""
    for sy in (-1, 1):
        yi = sy * (OPEN_HW - 0.004)
        plate_y(lights, yi, POCKET[0] + 0.045, POCKET[0] + 0.075, 0.45, 1.36, "Glow", facing=-sy)
        plate_y(lights, yi, MAIN[0] + 0.18, MAIN[0] + 0.21, 0.45, 1.36, "Glow", facing=-sy)


def header(hi):
    """(critic round 4) The entry hood: the corridor's outer U profile carried inward from the collar to the pocket
    plane (x -0.52 .. 0.02), above the wall top only.  On a small dome it reads as the corridor tube entering the
    dome; everything above the wall top stays inside it.  A short track over the opening."""
    x0, x1 = HOOD_X
    out = u_contour(*C_OUT)
    inn = u_contour(C_OUT[0] - 0.05, C_OUT[1] - 0.05)
    n_ = len(out)
    for i in range(n_ - 1):
        (ya, za), (yb, zb) = out[i], out[i + 1]
        (yc, zc), (yd, zd) = inn[i], inn[i + 1]
        if min(za, zb) < WALL_TOP - 1e-4 or min(zc, zd) < WALL_TOP - 0.06:
            continue
        wo = radial_want(0.5 * (ya + yb), 0.5 * (za + zb))
        oquad(hi, (x1, ya, za), (x0, ya, za), (x0, yb, zb), (x1, yb, zb), "Hull", wo, smooth=True)
        oquad(hi, (x0, yc, zc), (x1, yc, zc), (x1, yd, zd), (x0, yd, zd), "HullDark", -wo, smooth=True)
        oquad(hi, (x0, yb, zb), (x0, ya, za), (x0, yc, zc), (x0, yd, zd), "Frame", (-1, 0, 0))
    bbox(hi, POCKET[0], POCKET[1], -0.62, 0.62, DOOR_TOP - 0.05, DOOR_TOP, "Frame")


def signs(sg):
    """Exit signs: a lit plate with a door-and-arrow pictogram (no text)."""
    def pictogram(xf, facing, zc, w, h):
        with sg.at(T(xf, 0, zc), RZ(0.0 if facing > 0 else 180.0)):
            bbox(sg, -0.03, 0.0, -w / 2 - 0.02, w / 2 + 0.02, -h / 2 - 0.02, h / 2 + 0.02, "Frame")
            plate_x(sg, 0.002, -w / 2, w / 2, -h / 2, h / 2, "Screen")
            # door outline (left) and an arrow (right), in LightStrip
            dx = -w * 0.22
            for (y0, y1, z0, z1) in ((dx - 0.05, dx + 0.05, h * 0.30, h * 0.36), (dx - 0.05, dx - 0.035, -h * 0.34, h * 0.36),
                                     (dx + 0.035, dx + 0.05, -h * 0.34, h * 0.36)):
                plate_x(sg, 0.004, y0, y1, z0, z1, "LightStrip")
            ax = w * 0.14
            plate_x(sg, 0.004, ax - 0.10, ax + 0.04, -0.012, 0.012, "LightStrip")
            sg.tri((0.004, ax + 0.03, -0.055), (0.004, ax + 0.11, 0.0), (0.004, ax + 0.03, 0.055), "LightStrip")
    with sg.at(T(0, 0.93, 0)):
        pictogram(MAIN[0] - 0.006, -1, 1.60, 0.22, 0.12)
    pictogram(COLLAR[1] + 0.003, 1, 2.30, 0.44, 0.13)


def build_doorway():
    parts = {n: P(n) for n in ("Frame", "FrameTop", "DoorL", "DoorLTop", "DoorR", "DoorRTop", "Lights", "Sign")}
    lo, hi = parts["Frame"], parts["FrameTop"]
    sill(lo, parts["Lights"])
    for sy in (-1, 1):
        jamb(lo, hi, sy)
    header(hi)
    collar(lo, hi)
    leaf(parts["DoorL"], parts["DoorLTop"], -1)
    leaf(parts["DoorR"], parts["DoorRTop"], 1)
    status_strips(parts["Lights"])
    signs(parts["Sign"])
    anchors = [("Anchor_Room", (-1.05, 0.0, F), 180.0), ("Anchor_Corridor", (1.00, 0.0, F), 0.0)]
    return parts, anchors


# --------------------------------------------------------------------------------------
# Wall patch
# --------------------------------------------------------------------------------------
def build_wall_patch():
    """A straight 1.0 m slice of the 3.0 wall: the category band (Accent: the game tints it to the room's category
    colour), the pipe run and a batten, so the wall continues to the doorway frame."""
    b = P("Base")
    Rw = 10.0
    Ri = Rw - 0.20
    prof, mats = IK.wall_profile_v3(Rw, Ri, band="Accent", band_proud=True)
    rings = []
    for y in (-0.5, 0.5):                       # this order gives outward normals (checked: outer face -> +X)
        rings.append([(r - Rw, y, z) for (r, z) in prof])
    idx = [[b.v(p) for p in ring] for ring in rings]
    A, B = idx
    for i in range(len(prof) - 1):
        m = mats[i]
        m = "Hull" if m == "IN" else m
        b.f([A[i], B[i], B[i + 1], A[i + 1]], m)
    plate_x(b, -0.2 - 0.018, -0.015, 0.015, 0.29, 1.255, "Frame", facing=-1)
    plate_x(b, 0.008, -0.015, 0.015, 0.33, 0.915, "HullDark", facing=1)
    for z in IK.PIPE_Z:
        b.cyl((-0.2 - 0.045, -0.5, z), (-0.2 - 0.045, 0.5, z), IK.PIPE_R, seg=5, mat="Metal", cap0=False, cap1=False)
    return {"Base": b}, []


# --------------------------------------------------------------------------------------
# Junction door kit (critic round 4): no leaves, no side pockets.  A junction (R 2.5) takes up to 6 links 28 deg
# apart, so its mouths merge into open spans; posts close the ends of a span and stand between two links that are
# far enough apart.  Placement rule: interior_render.junction_plan() and docs/requests/ART-HAB-to-RENDER.md.
# --------------------------------------------------------------------------------------
JPOST_HW = 0.12             # post half width (tangential)
JPOST_X = (-0.26, 0.07)     # post depth: inner face just inside the wall's inner face, outer face just outside


def build_junction_post():
    """A slim post on the wall line, 0 .. WALL_TOP: plinth, chamfered shaft, capital, the room stripe (Accent) on
    both faces, a green status strip (Lights) on both side faces."""
    b, lt = P("Base"), P("Lights")
    x0, x1 = JPOST_X
    hw = JPOST_HW
    bbox(b, x0 - 0.03, x1 + 0.03, -hw - 0.03, hw + 0.03, 0.0, 0.20, "Frame", bevel=0.02)
    bbox(b, x0, x1, -hw, hw, 0.20, WALL_TOP - 0.10, "Hull", bevel=0.03, mats={"-z": None, "+z": None})
    bbox(b, x0 - 0.03, x1 + 0.03, -hw - 0.03, hw + 0.03, WALL_TOP - 0.10, WALL_TOP, "Frame", bevel=0.02)
    for (xf, face) in ((x0 - 0.001, -1), (x1 + 0.001, 1)):
        plate_x(b, xf, -hw + 0.03, hw - 0.03, 0.935, 1.125, "Accent", facing=face)
        plate_x(b, xf, -hw + 0.03, hw - 0.03, 0.30, 0.34, "HullDark", facing=face)
    for sy in (-1, 1):
        plate_y(lt, sy * (hw + 0.001), -0.10, -0.06, 0.40, 1.20, "Glow", facing=sy)
    return {"Base": b, "Lights": lt}, []


def build_junction_sill():
    """Threshold across an open junction span: 1.0 m on Y (the game scales it on its local Godot Z), x from inside
    the wall line (-0.24) to the corridor start (+0.10); covers the cut wall foot."""
    b = P("Base")
    x0, x1 = -0.24, 0.10
    bbox(b, x0, x1, -0.5, 0.5, -0.05, F + 0.006, "FloorDark", mats={"-z": None, "+y": None, "-y": None})
    plate_z(b, F + 0.007, -0.20, -0.17, -0.5, 0.5, "Accent")
    plate_z(b, F + 0.007, 0.04, 0.06, -0.5, 0.5, "Frame")
    return {"Base": b}, []


# --------------------------------------------------------------------------------------
# Corridor (1.0 m unit, scaled on X by the game) and its rib (not scaled)
# --------------------------------------------------------------------------------------
HALF, WALL_H, WT = 1.18, 1.00, 0.18


def build_corridor():
    b, r = P("Base"), P("Roof")
    x0, x1 = -0.5, 0.5
    yi = HALF - WT
    # floor: warm walkway, dark gutters, centre light line
    b.box((0, 0, (F - 0.06) / 2), (1.0, 2 * yi, F + 0.06), "FloorDark", mats={"+y": None, "-y": None, "-z": None,
                                                                             "+x": None, "-x": None})
    plate_z(b, F + 0.003, x0, x1, -0.78, 0.78, "Floor")
    for sy in (-1, 1):
        plate_z(b, F + 0.005, x0, x1, sy * 0.40 - 0.012, sy * 0.40 + 0.012, "FloorDark")
    plate_z(b, F + 0.006, x0, x1, -0.03, 0.03, "LightStrip")
    for sy in (-1, 1):
        yc = sy * (HALF - WT / 2)
        b.box((0, yc, (WALL_H - 0.05) / 2), (1.0, WT, WALL_H + 0.05), "Hull",
              mats={"-z": None, "+z": "Frame", "+x": None, "-x": None})
        yo = sy * (HALF + 0.004)
        yin = sy * (yi - 0.004)

        def strip(y, z0, z1, facing, mat):
            plate_y(b, y, x0, x1, z0, z1, mat, facing=facing)
        strip(yo, 0.0, 0.24, sy, "HullDark")
        strip(yo, 0.58, 0.66, sy, "Accent")
        strip(yin, F, 0.30, -sy, "FloorDark")
        strip(yin, 0.70, 0.74, -sy, "LightStrip")
        # handrail (continuous: it stretches with the corridor)
        b.cyl((x0, sy * (yi - 0.07), 0.90), (x1, sy * (yi - 0.07), 0.90), 0.025, seg=6, mat="Metal", cap0=False,
              cap1=False)
    N = 12

    def arc(ry, rz, x):
        return [(x, ry * cos(pi * i / N), WALL_H + rz * sin(pi * i / N)) for i in range(N + 1)]
    r.loft([arc(1.155, 1.355, x0), arc(1.155, 1.355, x1)],
           lambda k, i: "Hull" if i in (0, 1, N - 2, N - 1) else "Glass", smooth=True, closed=False)
    r.beam((x0, 0, WALL_H + 1.37), (x1, 0, WALL_H + 1.37), 0.30, 0.06, "Frame", caps=False)
    return {"Base": b, "Roof": r}, []


def build_corridor_rib():
    """Rib frame (0.14 m on X): wall posts, rail brackets and a floor grate (Base); arch rib, a light bar and a
    sensor (Roof)."""
    b, r = P("Base"), P("Roof")
    t = 0.07
    yi = HALF - WT
    for sy in (-1, 1):
        # outer post
        bbox(b, -t, t, sy * HALF - 0.05 if sy > 0 else -HALF - 0.05, sy * HALF + 0.05 if sy > 0 else -HALF + 0.05,
             0.0, WALL_H + 0.02, "Frame")
        # inner pilaster with a small lamp
        bbox(b, -t + 0.01, t - 0.01, sy * yi - 0.05 if sy > 0 else -yi - 0.0, sy * yi if sy > 0 else -yi + 0.05,
             F, WALL_H, "Frame")
        plate_y(b, sy * (yi - 0.052), -0.025, 0.025, 0.30, 0.60, "LightStrip", facing=-sy)
        # rail bracket
        b.beam((0, sy * (yi - 0.05), 0.90), (0, sy * (yi - 0.095), 0.90), 0.04, 0.04, "Metal")
    # floor grate across the corridor
    bbox(b, -0.10, 0.10, -yi, yi, F - 0.01, F + 0.008, "Frame")
    # arch rib (Roof), just outside the glass
    N = 12
    pts_o = [(1.23 * cos(pi * i / N), WALL_H + 1.43 * sin(pi * i / N)) for i in range(N + 1)]
    pts_i = [(1.15 * cos(pi * i / N), WALL_H + 1.35 * sin(pi * i / N)) for i in range(N + 1)]
    for i in range(N):
        (ya, za), (yb, zb) = pts_o[i], pts_o[i + 1]
        (yc, zc), (yd, zd) = pts_i[i], pts_i[i + 1]
        wo = radial_want(0.5 * (ya + yb), 0.5 * (za + zb))
        oquad(r, (t, yb, zb), (-t, yb, zb), (-t, ya, za), (t, ya, za), "Frame", wo)
        oquad(r, (-t, yc, zc), (-t, yd, zd), (t, yd, zd), (t, yc, zc), "Frame", -wo)
        oquad(r, (t, ya, za), (t, yc, zc), (t, yd, zd), (t, yb, zb), "Frame", (1, 0, 0))
        oquad(r, (-t, yb, zb), (-t, yd, zd), (-t, yc, zc), (-t, ya, za), "Frame", (-1, 0, 0))
    # light bar under the crown and a sensor
    bbox(r, -0.06, 0.06, -0.30, 0.30, WALL_H + 1.26, WALL_H + 1.34, "Frame")
    oquad(r, (-0.04, -0.27, WALL_H + 1.258), (-0.04, 0.27, WALL_H + 1.258), (0.04, 0.27, WALL_H + 1.258),
          (0.04, -0.27, WALL_H + 1.258), "LightStrip", (0, 0, -1))
    return {"Base": b, "Roof": r}, []


# --------------------------------------------------------------------------------------
# Export and checks
# --------------------------------------------------------------------------------------
BUILDS = {
    "doorway": (build_doorway, 1600),
    "wall_patch": (build_wall_patch, 120),
    "corridor": (build_corridor, 400),
    "corridor_rib": (build_corridor_rib, 400),
    "junction_post": (build_junction_post, 300),
    "junction_sill": (build_junction_sill, 60),
}
ALLOWED = set(K.MATERIALS) | set(K.PER_FILE)


def export_parts(name, parts, anchors, accent="logistics"):
    K.reset_scene()
    mset = K.MatSet(K.ACCENTS[accent])
    objs = {}
    for pname, part in parts.items():
        if part.faces:
            objs[pname] = BA_part(part, mset)
    for a in anchors:
        K.anchor_object(a[0], a[1], a[2])
    bpy.context.view_layer.update()
    static = tuple(n for n in objs if n in ("Frame", "FrameTop", "Sign", "Base", "Roof"))
    sets = {n: tuple(sorted(set(static) | {n})) for n in objs}
    kw = dict(K.AO_DEFAULT)
    kw["dist"] = 0.8
    rays, secs = K.bake_ao(objs, sets=sets, **kw)
    path = os.path.join(K.MODEL_DIR, name + ".glb")
    K.export_glb_atomic(path)
    return path


def BA_part(part, mset):
    import build_assets as BA
    return BA.part_to_object(part, mset)


def check_file(name, path, parts, budget):
    info = K.inspect_glb(path)
    flags = []
    tris = sum(info["tris"].values())
    if tris > budget:
        flags.append("over budget %d > %d" % (tris, budget))
    want = sorted(n for n, p in parts.items() if p.faces)
    if sorted(info["mesh_nodes"]) != want:
        flags.append("objects %s != %s" % (sorted(info["mesh_nodes"]), want))
    miss = [n for n, ok in info["color0"].items() if not ok]
    if miss:
        flags.append("no COLOR_0 on %s" % miss)
    bad = [m for m in info["materials"] if m not in ALLOWED]
    if bad:
        flags.append("unknown materials %s" % bad)
    if info["child_nodes"]:
        flags.append("nodes have children")
    if name == "doorway":
        # the cut at WALL_TOP: lower objects below, upper objects above
        for pn, part in parts.items():
            zs = [v.z for v in part.verts]
            if not zs:
                continue
            if pn in ("Frame", "DoorL", "DoorR", "Lights") and max(zs) > WALL_TOP + 0.002:
                flags.append("%s reaches z %.3f > WALL_TOP" % (pn, max(zs)))
            if pn in ("FrameTop", "DoorLTop", "DoorRTop", "Sign") and min(zs) < WALL_TOP - 0.002:
                flags.append("%s starts at z %.3f < WALL_TOP" % (pn, min(zs)))
        worst = 0.0
        for pn in ("FrameTop", "DoorLTop", "DoorRTop", "Sign"):
            for v in parts[pn].verts:
                if v.x < COLLAR[0] - 1e-4:
                    worst = max(worst, abs(v.y) - C_OUT[0], v.z - arch_z(v.y), HOOD_X[0] - v.x)
        if worst > 0.005:
            flags.append("upper door parts leave the entry hood by %.3f m" % worst)
        ys = [abs(v.y) for pn in ("Frame", "FrameTop") for v in parts[pn].verts]
        if max(ys) > POCKET_HW + 0.01:
            flags.append("frame half width %.2f" % max(ys))
    return dict(id=name, tris=tris, budget=budget, tris_by_object=info["tris"], materials=info["materials"],
                empties=info["empties"], flags=flags, file_size=os.path.getsize(path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    rows = []
    for name, (fn, budget) in BUILDS.items():
        if only and name not in only:
            continue
        t0 = time.time()
        parts, anchors = fn()
        path = export_parts(name, parts, anchors)
        row = check_file(name, path, parts, budget)
        row["seconds"] = round(time.time() - t0, 1)
        rows.append(row)
        print("  %-14s %5d/%-5d tris  %s  %s" % (name, row["tris"], budget, row["tris_by_object"], "; ".join(row["flags"]) or "ok"))
    old = {}
    if os.path.exists(REPORT):
        try:
            old = {r["id"]: r for r in json.load(open(REPORT, encoding="utf-8"))["models"]}
        except Exception:
            old = {}
    for r in rows:
        old[r["id"]] = r
    with open(REPORT, "w", encoding="utf-8") as fh:
        json.dump(dict(generator="interior_links.py", models=list(old.values())), fh, indent=1)


if __name__ == "__main__":
    main()
