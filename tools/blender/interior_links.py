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
from math import sin, cos, pi, radians, degrees, hypot, sqrt, asin, atan2
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
COLLAR = (0.04, 0.46)      # 3.1: starts on the corridor face of the frame housing (no gap)
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


# --------------------------------------------------------------------------------------
# 3.1 DOOR KIT (docs/V3_1_DESIGN.md section 3): a solid frame housing with the pockets inside it, full-height
# opaque leaves, a threshold plate, a header status light, solid caps at the cutaway height.
# --------------------------------------------------------------------------------------

def sbox(lo, hi, x0, x1, y0, y1, z0, z1, mat, cap="HullDark", bevel=0.0, mats=None):
    """A solid box split at WALL_TOP: the lower half gets a solid cap face (the cutaway cut), the upper half keeps
    its own bottom face; each half is a closed box."""
    if z1 <= WALL_TOP + 1e-6:
        bbox(lo, x0, x1, y0, y1, z0, z1, mat, bevel=bevel, mats=mats)
        return
    if z0 >= WALL_TOP - 1e-6:
        bbox(hi, x0, x1, y0, y1, z0, z1, mat, bevel=bevel, mats=mats)
        return
    m_lo = dict(mats or {})
    m_lo["+z"] = cap
    bbox(lo, x0, x1, y0, y1, z0, WALL_TOP, mat, mats=m_lo)
    bbox(hi, x0, x1, y0, y1, WALL_TOP, z1, mat, mats=mats)


def splate_x(lo, hi, x, y0, y1, z0, z1, mat, facing=1):
    if z0 < WALL_TOP:
        plate_x(lo, x, y0, y1, z0, min(z1, WALL_TOP), mat, facing=facing)
    if z1 > WALL_TOP:
        plate_x(hi, x, y0, y1, max(z0, WALL_TOP), z1, mat, facing=facing)


def threshold(lo, x1=None):
    x0, x1 = HX[0] - 0.14, (COLLAR[1] if x1 is None else x1)
    bbox(lo, x0, x1, -OPEN_HW - 0.02, OPEN_HW + 0.02, -0.05, F + 0.012, "FloorDark", bevel=0.01)
    plate_z(lo, F + 0.0135, SLOT[0], SLOT[1], -OPEN_HW, OPEN_HW, "Frame")
    for (xa, xb) in ((x0 + 0.03, x0 + 0.12), (x1 - 0.12, x1 - 0.03)):
        for k in range(8):
            ya = -OPEN_HW + 1.5 * k / 8.0
            yb = ya + 1.5 / 8.0
            lo.quad((xa, ya, F + 0.0135), (xb, ya, F + 0.0135), (xb, yb, F + 0.0135), (xa, yb, F + 0.0135),
                    "Hazard" if k % 2 == 0 else "Rubber")


def signs31(sg, rw=None):
    """Exit signs: on the room face of the +Y housing block (turned with the curved face) and on the corridor face
    of the collar top."""
    def pictogram(xf, facing, yc, zc, w, h):
        with sg.at(T(xf, yc, zc), RZ(0.0 if facing > 0 else 180.0)):
            bbox(sg, -0.03, 0.0, -w / 2 - 0.02, w / 2 + 0.02, -h / 2 - 0.02, h / 2 + 0.02, "Frame")
            plate_x(sg, 0.002, -w / 2, w / 2, -h / 2, h / 2, "Screen")
            dx = -w * 0.22
            for (y0, y1, z0, z1) in ((dx - 0.05, dx + 0.05, h * 0.30, h * 0.36), (dx - 0.05, dx - 0.035, -h * 0.34, h * 0.36),
                                     (dx + 0.035, dx + 0.05, -h * 0.34, h * 0.36)):
                plate_x(sg, 0.004, y0, y1, z0, z1, "LightStrip")
            ax = w * 0.14
            plate_x(sg, 0.004, ax - 0.10, ax + 0.04, -0.012, 0.012, "LightStrip")
            sg.tri((0.004, ax + 0.03, -0.055), (0.004, ax + 0.11, 0.0), (0.004, ax + 0.03, 0.055), "LightStrip")
    ys = 1.20
    slope = degrees(atan2(x_room(ys + 0.01, rw) - x_room(ys - 0.01, rw), 0.02))
    with sg.at(T(x_room(ys, rw) - 0.006, ys, 0.0), RZ(-slope)):
        pictogram(0.0, -1, 0.0, 1.66, 0.40, 0.15)
    pictogram(COLLAR[1] + 0.003, 1, 0.0, 2.30, 0.44, 0.13)


# --------------------------------------------------------------------------------------
# 3.1 DOOR KIT, round 10 (docs/V3_1_DESIGN.md section 3; critic round 10): the room face of the housing follows
# the wall radius, rounded top corners, 8 cm chamfers at the ends, a curved hood over the top that carries the dome
# line; a clear green status strip; kick plates and a chevron strip at the meeting edge.
# --------------------------------------------------------------------------------------
HX = (-0.56, 0.04)          # housing depth at the door axis: room face .. corridor face (the collar starts at 0.04)
HY = 1.72                   # housing half width (pockets to 1.66, open leaves to 1.54)
HT = 2.56                   # housing top at the door axis
TOP_R = 0.30                # rounded top corners (elevation)
CHAMFER = 0.08
SLOT = (-0.31, -0.21)       # the pocket slot (the leaves run in it; hidden inside the housing)
LEAF31 = (-0.29, -0.23)     # leaf plane: 6 cm thick
POCKET_END = 1.66
OPEN_TRAVEL = 0.75
DOORWAY_RW = (2.50, 3.25, 4.00, 4.75, 5.50, 6.25, 7.00, 7.75, 8.50, 9.25)   # doorway_r<rw>.glb variants


def x_room(y, rw):
    """Room face of the housing at lateral offset y: 0.56 m inside the wall line, following the wall radius."""
    if not rw:
        return HX[0]
    r = rw + HX[0]
    return sqrt(max(0.0, r * r - y * y)) - rw


def top_z(y):
    """Housing top at |y|: flat, with rounded outer corners (TOP_R)."""
    a = abs(y)
    y0 = HY - TOP_R
    if a <= y0:
        return HT
    d = min(TOP_R, a - y0)
    return HT - TOP_R + sqrt(max(0.0, TOP_R * TOP_R - d * d))


def solid_loft(p, sections, mat_fn, cap_mats=("HullDark", "HullDark")):
    """Closed solid through convex sections (lists of points, same count, in order round the section).  Faces are
    turned outward (away from the local section centroid).  mat_fn(edge, k) -> material; cap_mats for the two
    end sections (None = no cap)."""
    ids = [[p.v(pt) for pt in sec] for sec in sections]
    cents = [sum((Vector(pt) for pt in sec), Vector((0, 0, 0))) / len(sec) for sec in sections]
    n = len(sections[0])
    for k in range(len(sections) - 1):
        c = 0.5 * (cents[k] + cents[k + 1])
        for i in range(n):
            j = (i + 1) % n
            a, b = Vector(sections[k][i]), Vector(sections[k][j])
            cc, d = Vector(sections[k + 1][j]), Vector(sections[k + 1][i])
            nv = (b - a).cross(d - a)
            if nv.length < 1e-12:
                nv = (cc - b).cross(a - b)
            fc = (a + b + cc + d) / 4
            quad = [ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]]
            if nv.dot(fc - c) < 0:
                quad.reverse()
            m = mat_fn(i, k)
            if m:
                p.f(quad, m)
    for (end, other, cm) in ((0, 1, cap_mats[0]), (len(sections) - 1, len(sections) - 2, cap_mats[1])):
        if not cm:
            continue
        sec = sections[end]
        a, b, c3 = Vector(sec[0]), Vector(sec[1]), Vector(sec[2])
        nv = (b - a).cross(c3 - a)
        face = list(ids[end])
        if nv.dot(cents[end] - cents[other]) < 0:
            face.reverse()
        p.f(face, cm)


def _side_sections(sy, rw, z0, z1f, steps=10):
    """Sections (x-z rectangles) along y for one side block, from the opening edge to the end (with a chamfer)."""
    xs_c = HX[1]
    ys = [OPEN_HW + (HY - CHAMFER - OPEN_HW) * t / steps for t in range(steps + 1)] + [HY]
    secs = []
    for y in ys:
        ch = CHAMFER if y > HY - 1e-6 else 0.0
        xr = x_room(y, rw) + ch
        xc = xs_c - ch
        zt = z1f(y) - (ch if z1f(y) > WALL_TOP + 0.05 and z0 >= WALL_TOP - 1e-6 else 0.0)
        yy = sy * y
        secs.append([(xr, yy, z0), (xc, yy, z0), (xc, yy, zt), (xr, yy, zt)])
    return secs


CAP_T = 0.025        # critic round 13: the cutaway cap plate, 2.5 cm thick, 8 mm proud of the housing faces
CAP_OUT = 0.008


def cap_plate(cap, sy, rw):
    """The clean cutaway cap of one side block (object FrameCap / <prefix>FrameCap): a Frame plate WALL_TOP - CAP_T
    .. WALL_TOP + 0.004, 8 mm proud of the housing faces, on the same outline (curved room face, chamfered end)."""
    secs = []
    for sec in _side_sections(sy, rw, WALL_TOP - CAP_T, lambda y: WALL_TOP + 0.004):
        (xr, yy, z0), (xc, _, _), _, _ = sec
        yy2 = yy + sy * (CAP_OUT if abs(yy) >= HY - 1e-6 else 0.0)
        secs.append([(xr - CAP_OUT, yy2, z0), (xc + CAP_OUT, yy2, z0), (xc + CAP_OUT, yy2, WALL_TOP + 0.004),
                     (xr - CAP_OUT, yy2, WALL_TOP + 0.004)])
    # critic round 14: a light Trim plate with the Frame-coloured top inset 2.5 cm, so the cut reads as a wall with
    # a thin light edge (not a dark lid)
    solid_loft(cap, secs, lambda i, k: ("Trim", "Trim", "Trim", "Trim")[i], cap_mats=("Trim", "Trim"))
    ins = []
    for sec in secs:
        (xa, yy, _), (xb, _, _), _, _ = sec
        yy2 = yy - sy * (CAP_EDGE if abs(yy) >= HY - 1e-6 else 0.0)
        ins.append([(xa + CAP_EDGE, yy2, WALL_TOP + 0.004), (xb - CAP_EDGE, yy2, WALL_TOP + 0.004),
                    (xb - CAP_EDGE, yy2, WALL_TOP + 0.005), (xa + CAP_EDGE, yy2, WALL_TOP + 0.005)])
    ins[0] = [(x, y - sy * 0.0, z) for (x, y, z) in ins[0]]
    solid_loft(cap, ins, lambda i, k: (None, "Frame", "Frame", "Frame")[i], cap_mats=("Frame", "Frame"))


CAP_EDGE = 0.025


def cap_top(p, x0, x1, y0, y1, z):
    """A cut-wall cap on a box footprint: a light Trim plate (8 mm proud) with a Frame-coloured top inset 2.5 cm."""
    bbox(p, x0 - CAP_OUT, x1 + CAP_OUT, y0 - CAP_OUT, y1 + CAP_OUT, z - CAP_T, z + 0.004, "Trim", mats={"-z": None})
    e = min(CAP_EDGE, 0.25 * (x1 - x0), 0.25 * (y1 - y0))
    bbox(p, x0 - CAP_OUT + e, x1 + CAP_OUT - e, y0 - CAP_OUT + e, y1 + CAP_OUT - e, z + 0.004, z + 0.005, "Frame",
         mats={"-z": None})


def collar_cap(cap):
    """Caps of the collar ring where WALL_TOP cuts it (both sides): the ring cross-section, closed."""
    x0, x1 = COLLAR
    out = u_contour(*C_OUT)
    inn = u_contour(*C_IN)
    for side in (0, 1):
        io = [i for i, (y, z) in enumerate(out) if abs(z - WALL_TOP) < 1e-6]
        ii = [i for i, (y, z) in enumerate(inn) if abs(z - WALL_TOP) < 1e-6]
        if len(io) < 2 or len(ii) < 2:
            continue
        yo, yi = out[io[side]][0], inn[ii[side]][0]
        ya, yb = sorted((yo, yi))
        cap_top(cap, x0, x1, ya, yb, WALL_TOP)


def housing(lo, hi, rw=None, flat=False, cap=None):
    """The frame housing: two side blocks and the header, split at WALL_TOP (the lower half closed with a solid cap),
    the room face on the wall radius rw (None = flat, for partitions), rounded top corners, chamfered ends; the
    pocket slots are inside (a dark slot line on each reveal)."""
    # critic round 13: the lower block has no top face and the upper block no bottom face (they met at WALL_TOP
    # and fought); the cut is closed by the separate cap plate (cap_plate), which reads clean in the cutaway
    def mats(face):
        return lambda i, k: ("Frame", "Hull", None, "Hull")[i] if face == "lo" else (None, "Hull", "Hull", "Hull")[i]
    cap = cap if cap is not None else lo
    for sy in (-1, 1):
        solid_loft(lo, _side_sections(sy, rw, 0.0, lambda y: WALL_TOP), mats("lo"), cap_mats=("Hull", "Hull"))
        solid_loft(hi, _side_sections(sy, rw, WALL_TOP, top_z), mats("hi"), cap_mats=("Hull", "Hull"))
        cap_plate(cap, sy, rw)
        # the cutaway cap: a dark plate on top of the lower block
        yi = sy * OPEN_HW
        # slot line on the reveal (the leaf runs here) and the reveal trim
        for part, za, zb in ((lo, F, WALL_TOP), (hi, WALL_TOP, DOOR_TOP)):
            plate_y(part, yi - sy * 0.002, SLOT[0], SLOT[1], za, zb, "Rubber", facing=-sy)
            for (ea, eb) in ((HX[0] + 0.02, HX[0] + 0.06), (HX[1] - 0.06, HX[1] - 0.02)):
                plate_y(part, yi - sy * 0.003, ea, eb, za, zb, "Frame", facing=-sy)
        # room face details: a recessed panel with the room stripe (on the curved face, per section)
        steps = 6
        for t in range(steps):
            ya = OPEN_HW + 0.10 + (HY - 0.20 - OPEN_HW - 0.10) * t / steps
            yb = OPEN_HW + 0.10 + (HY - 0.20 - OPEN_HW - 0.10) * (t + 1) / steps
            xa, xb = x_room(ya, rw) - 0.004, x_room(yb, rw) - 0.004
            for (z0, z1, m, part) in ((0.92, 1.10, "Accent", lo), (0.28, 0.31, "Frame", lo),
                                      (HT - 0.12, HT - 0.08, "Accent", hi)):
                pa, pb = (sy * ya, sy * yb)
                q = [(xa, pa, z0), (xb, pb, z0), (xb, pb, z1), (xa, pa, z1)]
                oquad(part, *q, m, (-1, 0, 0))
        # corridor face: the room stripe and a trim line
        for (z0, z1, m, part) in ((0.92, 1.10, "Accent", lo), (HT - 0.12, HT - 0.08, "Accent", hi)):
            y0, y1 = sorted((sy * (OPEN_HW + 0.10), sy * (HY - 0.20)))
            plate_x(part, HX[1] + 0.003, y0, y1, z0, z1, m, facing=1)
    # the header over the opening (room face curved as well)
    secs = []
    for t in range(5):
        y = -OPEN_HW + 2 * OPEN_HW * t / 4
        xr = x_room(y, rw)
        secs.append([(xr, y, DOOR_TOP), (HX[1], y, DOOR_TOP), (HX[1], y, HT), (xr, y, HT)])
    solid_loft(hi, secs, lambda i, k: ("Frame", "Hull", "Hull", "Hull")[i], cap_mats=(None, None))
    if flat:
        flat_lid(hi, rw)
    else:
        hood(hi, rw)


def flat_lid(hi, rw):
    """For flat-roofed rooms (podium, drum, setback): a flat lid with a Frame edge instead of the curved hood, so the
    housing top reads flush with the roof edge."""
    secs = []
    steps = 14
    for t in range(steps + 1):
        y = -HY + 0.06 + (2 * HY - 0.12) * t / steps
        zt = top_z(y)
        xr, xc = x_room(y, rw) - 0.02, HX[1] + 0.03
        secs.append([(xc, y, zt - 0.002), (xr, y, zt - 0.002), (xr, y, zt + 0.06), (xc, y, zt + 0.06)])
    solid_loft(hi, secs, lambda i, k: ("HullDark", "Frame", "Frame", "Frame")[i], cap_mats=("Frame", "Frame"))


def hood(hi, rw):
    """A curved hood over the housing top: it rises from the corridor face to the room side, so the housing reads as
    part of the dome, not a plate on it."""
    secs = []
    steps = 14
    for t in range(steps + 1):
        y = -HY + 0.10 + (2 * HY - 0.20) * t / steps
        zt = top_z(y)
        xr = x_room(y, rw) - 0.04
        xc = HX[1] + 0.02
        xm = 0.5 * (xr + xc)
        secs.append([(xc, y, zt - 0.01), (xr, y, zt + 0.26), (xr, y, zt + 0.32), (xm, y, zt + 0.26),
                     (xc, y, zt + 0.06)])
    solid_loft(hi, secs, lambda i, k: ("HullDark", "Hull", "Hull", "Hull", "Frame")[i], cap_mats=("Frame", "Frame"))


def status_light(st, rw=None):
    """The header status light (object Status): a clear strip over the opening on both faces, StatusGreen
    (#5EE07A); RENDER switches it to amber or red."""
    for (fc,) in ((-1,), (1,)):
        if fc < 0:
            xs = [x_room(-0.55, rw), x_room(0.0, rw), x_room(0.55, rw)]
            x0 = min(xs) - 0.035
            x1 = min(xs) - 0.005
        else:
            x0, x1 = HX[1] + 0.005, HX[1] + 0.035
        bbox(st, x0, x1, -0.55, 0.55, DOOR_TOP + 0.07, DOOR_TOP + 0.12, "StatusGreen")


def tunnel_lights(lights):
    """Green strips on both reveals (below 1.40 m): the status colour at eye level."""
    for sy in (-1, 1):
        yi = sy * (OPEN_HW - 0.004)
        for (xa, xb) in ((HX[0] + 0.10, HX[0] + 0.14), (HX[1] - 0.14, HX[1] - 0.10)):
            plate_y(lights, yi, xa, xb, 0.40, 1.36, "StatusGreen", facing=-sy)


def reveal_trim(lo, hi):
    """(kept for the airlock callers: the reveal trim is part of housing() now)"""
    return


def leaf31(lo, hi, sy):
    """One full-height opaque leaf (6 cm): a window strip, a seal line at the meeting edge, a chevron strip beside it,
    a dark kick plate, trim lines."""
    ya, yb = (0.0, LEAF_W) if sy > 0 else (-LEAF_W, 0.0)
    x0, x1 = LEAF31
    z0, z1 = F + 0.005, DOOR_TOP + 0.01
    sbox(lo, hi, x0, x1, ya, yb, z0, z1, "Hull", cap="HullDark")
    e0, e1 = (0.0, 0.014) if sy > 0 else (-0.014, 0.0)
    sbox(lo, hi, x0 - 0.006, x1 + 0.006, e0, e1, z0, z1, "Rubber", cap="Rubber")
    wy0, wy1 = sorted((sy * 0.16, sy * 0.25))
    cy0, cy1 = sorted((sy * 0.02, sy * 0.10))                   # the chevron strip beside the meeting edge
    for (fx, face) in ((x0 - 0.002, -1), (x1 + 0.002, 1)):
        splate_x(lo, hi, fx, wy0 - 0.02, wy1 + 0.02, 1.08, 1.98, "Frame", facing=face)
        splate_x(lo, hi, fx + face * 0.002, wy0, wy1, 1.10, 1.96, "Visor", facing=face)
        fy0, fy1 = sorted((sy * 0.12, sy * (LEAF_W - 0.04)))
        plate_x(lo, fx, fy0, fy1, F + 0.02, 0.52, "HullDark", facing=face)            # kick plate
        plate_x(lo, fx + face * 0.001, fy0 + 0.03, fy1 - 0.03, 0.50, 0.515, "Frame", facing=face)
        for z in (0.95, 1.30):
            plate_x(lo, fx, sorted((sy * 0.30, sy * (LEAF_W - 0.06)))[0], sorted((sy * 0.30, sy * (LEAF_W - 0.06)))[1],
                    z, z + 0.015, "Frame", facing=face)
        plate_x(hi, fx, fy0, fy1, 1.90, 1.915, "Frame", facing=face)
        # chevrons: slanted Hazard / Rubber bands, 0.16 m apart, from the kick plate up to the window level
        nch = 12
        for k in range(nch):
            za = 0.54 + 0.13 * k
            zb = za + 0.065
            part = lo if zb + 0.04 <= WALL_TOP else (hi if za - 0.04 >= WALL_TOP else None)
            if part is None:
                continue
            m = "Hazard" if k % 2 == 0 else "Rubber"
            q = [(fx + face * 0.002, cy0, za), (fx + face * 0.002, cy1, za + (0.04 if sy > 0 else -0.04)),
                 (fx + face * 0.002, cy1, zb + (0.04 if sy > 0 else -0.04)), (fx + face * 0.002, cy0, zb)]
            oquad(part, *q, m, (face, 0, 0))


def build_doorway(rw=None, flat=False):
    parts = {n: P(n) for n in ("Frame", "FrameCap", "FrameTop", "DoorL", "DoorLTop", "DoorR", "DoorRTop", "Lights",
                               "Status", "Sign")}
    lo, hi = parts["Frame"], parts["FrameTop"]
    housing(lo, hi, rw, flat=flat, cap=parts["FrameCap"])
    threshold(lo)
    collar(lo, hi)
    collar_cap(parts["FrameCap"])
    leaf31(parts["DoorL"], parts["DoorLTop"], -1)
    leaf31(parts["DoorR"], parts["DoorRTop"], 1)
    tunnel_lights(parts["Lights"])
    status_light(parts["Status"], rw)
    signs31(parts["Sign"], rw)
    anchors = [("Anchor_Room", (-1.05, 0.0, F), 180.0), ("Anchor_Corridor", (1.00, 0.0, F), 0.0)]
    return parts, anchors


# --------------------------------------------------------------------------------------
# Wall patch
# --------------------------------------------------------------------------------------
def build_wall_patch(band="Accent", batten=True):
    """A straight 1.0 m slice of the 3.0 wall: the category band (Accent: the game tints it to the room's category
    colour), the pipe run and a batten, so the wall continues to the doorway frame.  band=None: the plain slice for
    the last 5 cm before a door housing (3.1: the band ends before the door, with a cap)."""
    b = P("Base")
    Rw = 10.0
    Ri = Rw - 0.20
    prof, mats = IK.wall_profile_v3(Rw, Ri, band=band, band_proud=True)
    rings = []
    for y in (-0.5, 0.5):                       # this order gives outward normals (checked: outer face -> +X)
        rings.append([(r - Rw, y, z) for (r, z) in prof])
    idx = [[b.v(p) for p in ring] for ring in rings]
    A, B = idx
    for i in range(len(prof) - 1):
        m = mats[i]
        m = "Hull" if m == "IN" else m
        b.f([A[i], B[i], B[i + 1], A[i + 1]], m)
    if batten:
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


def build_wall_patch_upper():
    """Upper wall slice for flat-walled rooms (podium, drum, setback): 1.0 m long on Y (the game scales it on its
    local Godot Z like the wall patch) and 1.0 m high (scaled on Y to the deck height - 1.40); outer face on x = 0,
    inner face x = -0.20, a Frame lip on top.  Placed at z 1.40 beside a door housing and over it."""
    b = P("Base")
    bbox(b, -0.20, 0.0, -0.5, 0.5, 0.0, 1.0, "Hull", mats={"+y": None, "-y": None, "-z": None})
    bbox(b, -0.22, 0.02, -0.5, 0.5, 0.97, 1.0, "Frame", mats={"+y": None, "-y": None})
    return {"Base": b}, []


def build_upper_band():
    """The upper wall band of flat-walled rooms, carried over a door's patch span to its cap: 1.0 m on local Godot
    Z (scaled like the patches) and 1.0 m high (scaled to the room's band height); proud of the wall line by 3 cm;
    material Accent (tinted by the game)."""
    b = P("Base")
    bbox(b, 0.0, 0.03, -0.5, 0.5, 0.0, 1.0, "Accent", mats={"+y": None, "-y": None, "-x": None})
    return {"Base": b}, []


def build_band_cap():
    """The end cap of the wall band before a door (not scaled): a small Frame block over the proud band's end, its
    origin on the wall line at the band's end; local +Y points away from the door."""
    b = P("Base")
    bbox(b, -0.01, 0.05, -0.02, 0.02, 0.90, 1.16, "Frame", bevel=0.008)
    return {"Base": b}, []


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
    "doorway": (lambda: build_doorway(5.50), 2400),
    "wall_patch": (build_wall_patch, 120),
    "wall_patch_plain": (lambda: build_wall_patch(band=None, batten=False), 120),
    "band_cap": (build_band_cap, 60),
    "wall_patch_upper": (build_wall_patch_upper, 60),
    "upper_band": (build_upper_band, 30),
    "corridor": (build_corridor, 400),
    "corridor_rib": (build_corridor_rib, 400),
    "junction_post": (build_junction_post, 300),
    "junction_sill": (build_junction_sill, 60),
}
for _rw in DOORWAY_RW:          # 3.1: the room face follows the wall; RENDER takes the variant nearest to Rw
    BUILDS["doorway_r%03d" % round(_rw * 100)] = ((lambda rw=_rw: build_doorway(rw)), 2400)
    BUILDS["doorway_flat_r%03d" % round(_rw * 100)] = ((lambda rw=_rw: build_doorway(rw, flat=True)), 2400)
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
    if "FrameCap" in objs:
        sets["FrameCap"] = ("Frame", "FrameCap")      # the cap is seen with the upper parts gone: no AO from them
    kw = dict(K.AO_DEFAULT)
    kw["dist"] = 0.8
    rays, secs = K.bake_ao(objs, sets=sets, **kw)
    # draw calls (RENDER 2026-09-25): plain materials of the static and door parts join the palette
    for pname, o in objs.items():
        g = K.game_group(pname)
        if g in ("Status", "Lights", "Sign"):
            continue
        if name.startswith(("wall_patch", "band_cap", "upper_band")):
            K.shell_fold(o, mset)              # patches join the wall shell look: shell names only
            continue
        K.palette_merge(o, mset, max_surfaces=K.MAX_SHELL_SURFACES, keep=K.INTERIOR_ONLY + ("Visor",))
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
    if name.startswith("doorway"):
        # the cut at WALL_TOP: lower objects below, upper objects above
        for pn, part in parts.items():
            zs = [v.z for v in part.verts]
            if not zs:
                continue
            if pn in ("Frame", "DoorL", "DoorR", "Lights") and max(zs) > WALL_TOP + 0.002:
                flags.append("%s reaches z %.3f > WALL_TOP" % (pn, max(zs)))
            if pn == "FrameCap" and (max(zs) > WALL_TOP + 0.005 or min(zs) < WALL_TOP - CAP_T - 0.001):
                flags.append("%s reaches z %.3f > WALL_TOP" % (pn, max(zs)))
            if False:
                flags.append("%s reaches z %.3f > WALL_TOP" % (pn, max(zs)))
            if pn in ("FrameTop", "DoorLTop", "DoorRTop", "Sign", "Status") and min(zs) < WALL_TOP - 0.002:
                flags.append("%s starts at z %.3f < WALL_TOP" % (pn, min(zs)))
        # 3.1: an open leaf (moved 0.75 m) stays inside the frame housing and its pocket slot
        for pn, sy in (("DoorL", -1), ("DoorLTop", -1), ("DoorR", 1), ("DoorRTop", 1)):
            for v in parts[pn].verts:
                yo = v.y + sy * OPEN_TRAVEL
                if abs(yo) > POCKET_END + 1e-3 or not (SLOT[0] - 1e-3 <= v.x <= SLOT[1] + 1e-3):
                    flags.append("%s leaves the pocket when open (y %.3f, x %.3f)" % (pn, yo, v.x))
                    break
        ys = [abs(v.y) for pn in ("Frame", "FrameTop") for v in parts[pn].verts if v.x < COLLAR[0] - 1e-4]
        if max(ys) > HY + 0.01:
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
