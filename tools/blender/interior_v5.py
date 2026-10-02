"""Frontier Habitat 5.0 - ART-HAB: interiors of the new structures (docs/V5_DESIGN.md section 7).

residence_tube
  A street runs along model X from porch (0 deg) to porch (180 deg).  On each side of it a band of rectangular
  cells; each cell is one unit (low partition walls, 1.30 m, so the roof cutaway shows the plan) or a shared
  commons.  Behind the cells, garden strips with planters; at the street ends, entry corners.
  Family unit (units M/L/XL 2/3/4): a living room with a kitchenette and the family table, a parents' room with
    two beds, a children's room with a bunk bed.   Anchors per unit: 4 Bed (2 parents, the lower bunk, the upper bunk),
    2 Seat (the parents' chairs at the table), 1 Stand (kitchenette), 1 Unit (the unit door, floor 0).
  Executive unit (units M/L/XL 1/2/3): bedroom (two beds), a private bath (en suite), an office (desk), a lounge
    (sofa, coffee table, media wall) and a kitchenette.  Anchors per unit: 2 Bed, 3 Seat (sofa 2, office chair 1),
    1 Stand, 1 Unit.
  Anchor numbers run unit by unit: unit i owns Bed 4i..4i+3 (family) / 2i..2i+1 (executive), Seat 2i.. / 3i..,
  Stand i, Unit i.
"""
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, pi

import rooms_kit as K
import interior_kit as IK
import interior_furniture as FU
import interior_rooms as IR
from rooms_kit import T, RX, RY, RZ, FLOOR_Z, WALL_TOP
from interior_kit import F, Plan, bbox, plate_x, plate_y, plate_z, SEAT_BACK, BED_BACK, BED_Z, BENCH_Z, SEAT_Z

WALL_H = 1.30          # unit partitions: under the cut (1.40), so the cutaway shows every room of a unit
HS = 0.80              # street half width
DOOR_W = 1.00          # unit door gap
IDOOR_W = 0.84         # inner door gap


# --------------------------------------------------------------------------------------
# Cells: a rectangle beside the street, local u along the street, v away from it
# --------------------------------------------------------------------------------------
class Cell:
    def __init__(self, plan, ox, oy, rot, W, Dp):
        self.plan, self.ox, self.oy, self.rot, self.W, self.Dp = plan, ox, oy, rot, W, Dp
        self.c, self.s = cos(radians(rot)), sin(radians(rot))

    def w(self, u, v):
        return (self.ox + self.c * u - self.s * v, self.oy + self.s * u + self.c * v)

    def yaw(self, yl):
        return yl + self.rot

    def at(self, u, v, yl):
        x, y = self.w(u, v)
        return self.plan.n.at(T(x, y, 0.0), RZ(self.yaw(yl)))

    def loc(self, u, v, yl, lx, ly):
        a = radians(yl)
        return self.w(u + lx * cos(a) - ly * sin(a), v + lx * sin(a) + ly * cos(a))

    def rect(self, u, v, hu, hv, yl=0.0, tag=""):
        x, y = self.w(u, v)
        self.plan.rect(x, y, hu, hv, self.yaw(yl), tag=tag)

    def box_rect(self, u0, u1, v0, v1, tag=""):
        self.rect(0.5 * (u0 + u1), 0.5 * (v0 + v1), 0.5 * (u1 - u0), 0.5 * (v1 - v0), 0.0, tag)

    def anchor(self, kind, u, v, yl, lx=0.0, ly=0.0, z=F):
        x, y = self.loc(u, v, yl, lx, ly)
        self.plan.anchor(kind, x, y, self.yaw(yl), z)

    def floor(self, u0, u1, v0, v1, mat, z=F + 0.004):
        (xa, ya), (xb, yb) = self.w(u0, v0), self.w(u1, v1)
        plate_z(self.plan.n, z, min(xa, xb), max(xa, xb), min(ya, yb), max(ya, yb), mat)

    def centre(self):
        return self.w(self.W / 2, self.Dp / 2)


def wall(c, u0, v0, u1, v1, gaps=(), h=WALL_H, stripe="Accent", posts=True):
    """A straight partition from (u0, v0) to (u1, v1) of cell c; gaps [(t, width)] along it from the start.
    A wall already drawn (same end points) is skipped."""
    plan = c.plan
    A, B = c.w(u0, v0), c.w(u1, v1)
    key = tuple(sorted([(round(A[0], 2), round(A[1], 2)), (round(B[0], 2), round(B[1], 2))]))
    if key in plan.v5_walls:
        return
    plan.v5_walls.add(key)
    L = hypot(B[0] - A[0], B[1] - A[1])
    ang = degrees(atan2(B[1] - A[1], B[0] - A[0]))
    cuts = sorted((t - w_ / 2, t + w_ / 2) for t, w_ in gaps)
    pieces, t = [], 0.0
    for c0, c1 in cuts:
        if c0 > t + 0.04:
            pieces.append((t, c0))
        t = max(t, c1)
    if L - t > 0.04:
        pieces.append((t, L))
    n = plan.n
    with n.at(T(A[0], A[1], 0.0), RZ(ang)):
        for t0, t1 in pieces:
            bbox(n, t0, t1, -0.05, 0.05, F, F + 0.10, "HullDark", mats={"-z": None})
            bbox(n, t0, t1, -0.045, 0.045, F + 0.10, F + h - 0.04, "Hull", mats={"-z": None, "+z": None})
            bbox(n, t0 - 0.005, t1 + 0.005, -0.06, 0.06, F + h - 0.04, F + h, "Frame")
            for sy in (-1, 1):
                plate_y(n, sy * 0.0456, t0 + 0.03, t1 - 0.03, F + 0.92, F + 0.97, stripe, facing=sy)
        if posts:
            for c0, c1 in cuts:
                for tt in (c0, c1):
                    if 0.05 < tt < L - 0.05:
                        bbox(n, tt - 0.035, tt + 0.035, -0.075, 0.075, F, F + h + 0.05, "Frame", mats={"-z": None})
    ca, sa = cos(radians(ang)), sin(radians(ang))
    for t0, t1 in pieces:
        tm = 0.5 * (t0 + t1)
        plan.rect(A[0] + ca * tm, A[1] + sa * tm, 0.5 * (t1 - t0), 0.07, ang, tag="wall")


def door_plate(c, u, number):
    """The unit number plate beside the unit door, on the street face (Accent square + a lamp strip)."""
    n = c.plan.n
    with c.at(u, -0.06, 0.0):
        bbox(n, -0.16, 0.16, -0.015, 0.0, F + 0.95, F + 1.23, "Frame")
        plate_y(n, -0.0155, -0.13, 0.13, F + 0.98, F + 1.20, "Accent", facing=-1)
        for k in range(number + 1):
            x = -0.09 + 0.06 * k
            plate_y(n, -0.0165, x - 0.015, x + 0.015, F + 1.03, F + 1.15, "Hull", facing=-1)


# --------------------------------------------------------------------------------------
# Furniture made for the residences
# --------------------------------------------------------------------------------------
def kitchenette(p, w=2.0, fridge=True, seed=0):
    """Counter against a wall: back at x = 0, front at x = 0.60 (faces +X), along Y (width w, centred).  Top 0.90.
    The fridge column stands at the +Y end.  The cook's stand point is (1.05, 0) facing -X."""
    d = 0.60
    zt = F + BENCH_Z
    y0, y1 = -w / 2, w / 2
    yf = y1 - 0.64 if fridge else y1
    bbox(p, 0.04, d - 0.06, y0 + 0.02, yf - 0.02, F, F + 0.09, "FloorDark", mats={"-z": None})
    bbox(p, 0.0, d - 0.03, y0, yf, F + 0.09, zt - 0.04, "Hull", bevel=0.01, mats={"-z": None})
    nd = max(2, int(round((yf - y0) / 0.55)))
    for k in range(nd):
        a0 = y0 + (yf - y0) * k / nd + 0.012
        a1 = y0 + (yf - y0) * (k + 1) / nd - 0.012
        plate_x(p, d - 0.027, a0, a1, F + 0.13, zt - 0.08, "HullDark" if k % 2 else "Hull")
        plate_x(p, d - 0.024, a0 + 0.06, a1 - 0.06, zt - 0.14, zt - 0.12, "Frame")
    bbox(p, -0.005, d + 0.01, y0 - 0.01, yf + 0.005, zt - 0.04, zt, "Wood", bevel=0.008)
    # sink (left third) and hob (right third)
    ys = y0 + (yf - y0) * 0.28
    bbox(p, 0.14, 0.46, ys - 0.24, ys + 0.24, zt - 0.005, zt + 0.004, "Metal")
    plate_z(p, zt + 0.006, 0.18, 0.42, ys - 0.20, ys + 0.20, "FloorDark")
    p.vcyl(0.08, ys, zt, zt + 0.26, 0.018, seg=6, mat="Metal", cap0=False)
    p.beam((0.08, ys, zt + 0.26), (0.24, ys, zt + 0.24), 0.03, 0.03, "Metal")
    yh = y0 + (yf - y0) * 0.72
    bbox(p, 0.10, 0.50, yh - 0.30, yh + 0.30, zt, zt + 0.012, "HullDark")
    for (dx, dy) in ((-0.1, -0.14), (0.1, -0.14), (-0.1, 0.14), (0.1, 0.14)):
        with p.at(T(0.30 + dx, yh + dy, 0.0)):
            p.cap_disc(0.075, zt + 0.014, "Ember" if (dx + dy) < 0 else "Frame", seg=10)
    # splash panel and a shelf with jars
    plate_x(p, 0.005, y0 + 0.02, yf - 0.02, zt, F + WALL_H - 0.05, "Frost")
    import interior_props as PR          # 5.0 (V5 15.3): the chatbot kettle, the subscription toaster, sourdough
    PR.counter_set(p, 0.10, y0 + 0.02, yf - 0.02, zt, seed=seed)
    if fridge:
        bbox(p, 0.0, 0.62, yf + 0.02, y1, F, F + 1.82, "Hull", bevel=0.02)
        plate_x(p, 0.623, yf + 0.05, y1 - 0.03, F + 1.12, F + 1.14, "Frame")
        bbox(p, 0.62, 0.66, y1 - 0.12, y1 - 0.08, F + 0.60, F + 1.00, "Frame")
        bbox(p, 0.62, 0.66, y1 - 0.12, y1 - 0.08, F + 1.24, F + 1.60, "Frame")
        plate_x(p, 0.624, yf + 0.10, yf + 0.26, F + 1.50, F + 1.60, "Screen")


def bunk_bed(p, blankets=("Accent", "Fabric"), seed=0):
    """Two-tier bunk on the bed convention (FU.bed): centre at the origin, heads toward +Y, the lower mattress top
    at 0.55 m, stand point (+0.55, 0).  Ladder at the foot on the +X side; guard rail round the upper bed."""
    W, L = 0.96, 2.06
    z1 = F + BED_Z
    z2 = z1 + 1.12
    for sx in (-1, 1):
        for sy in (-1, 1):
            bbox(p, sx * (W / 2) - 0.035, sx * (W / 2) + 0.035, sy * (L / 2) - 0.035, sy * (L / 2) + 0.035,
                 F, z2 + 0.32, "Frame", mats={"-z": None})
    for k, zt in enumerate((z1, z2)):
        bbox(p, -W / 2, W / 2, -L / 2, L / 2, zt - 0.26, zt - 0.16, "Hull")
        bbox(p, -W / 2 + 0.03, W / 2 - 0.03, -L / 2 + 0.03, L / 2 - 0.03, zt - 0.16, zt, "Hull", bevel=0.04)
        bl = blankets[k % len(blankets)]
        bbox(p, -W / 2 - 0.02, W / 2 + 0.02, -L / 2 - 0.02, L / 2 - 0.52, zt - 0.12, zt + 0.035, bl, bevel=0.015)
        bbox(p, -0.28, 0.28, L / 2 - 0.44, L / 2 - 0.12, zt - 0.01, zt + 0.11, "Hull", bevel=0.045)
        # a soft toy on each bed
        with p.at(T(-0.18, L / 2 - 0.62, zt + 0.03)):
            p.sphere((0, 0, 0.09), 0.08, "Cushion" if k else "Accent", seg=6, rings=3, smooth=True)
            p.sphere((0, 0, 0.21), 0.06, "Cushion" if k else "Accent", seg=6, rings=3, smooth=True)
    # head and foot boards (Accent inserts)
    for sy in (-1, 1):
        bbox(p, -W / 2 + 0.03, W / 2 - 0.03, sy * (L / 2) - 0.015, sy * (L / 2) + 0.015, z1 - 0.16, z1 + 0.30,
             "Accent" if sy > 0 else "Hull")
        bbox(p, -W / 2 + 0.03, W / 2 - 0.03, sy * (L / 2) - 0.015, sy * (L / 2) + 0.015, z2 - 0.16, z2 + 0.30,
             "Accent" if sy > 0 else "Hull")
    # upper guard rails: full on -X, from the ladder to the head on +X
    bbox(p, -W / 2 - 0.02, -W / 2 + 0.02, -L / 2, L / 2, z2 + 0.20, z2 + 0.26, "Frame")
    bbox(p, W / 2 - 0.02, W / 2 + 0.02, -L / 2 + 0.52, L / 2, z2 + 0.20, z2 + 0.26, "Frame")
    # ladder at the foot, +X side
    for yy in (-L / 2 + 0.08, -L / 2 + 0.46):
        bbox(p, W / 2 + 0.02, W / 2 + 0.06, yy - 0.02, yy + 0.02, F, z2 + 0.26, "Frame", mats={"-z": None})
    for k in range(5):
        z = F + 0.30 + (z2 + 0.05 - F - 0.30) * k / 4.0
        p.beam((W / 2 + 0.04, -L / 2 + 0.08, z), (W / 2 + 0.04, -L / 2 + 0.46, z), 0.03, 0.03, "Metal")


def toy_chest(p, w=0.70, d=0.42, seed=0):
    """A toy chest (back at x = 0, faces +X) with toys on the lid."""
    rng = random.Random(seed)
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + 0.44, "Fabric", bevel=0.02)
    bbox(p, -0.01, d + 0.01, -w / 2 - 0.01, w / 2 + 0.01, F + 0.44, F + 0.48, "Accent", bevel=0.01)
    for k in range(3):
        plate_x(p, d + 0.003, -w / 2 + 0.06 + (w - 0.12) * k / 3 + 0.02, -w / 2 + 0.06 + (w - 0.12) * (k + 1) / 3 - 0.02,
                F + 0.16, F + 0.30, ("Glow", "CushionLight", "Hull")[(k + seed) % 3])
    for k in range(3):
        c = rng.choice(("Cushion", "Fabric", "Hull", "Glow"))
        bbox(p, 0.06 + 0.1 * k, 0.18 + 0.1 * k, -w / 2 + 0.08 + 0.2 * k, -w / 2 + 0.20 + 0.2 * k,
             F + 0.48, F + 0.60, c, bevel=0.01)


def toys(p, x, y, seed=0, n=5):
    """Blocks and balls on the floor round (x, y)."""
    rng = random.Random(seed)
    for k in range(n):
        a = rng.uniform(0, 2 * pi)
        r = rng.uniform(0.15, 0.55)
        px, py = x + r * cos(a), y + r * sin(a)
        c = rng.choice(("Accent", "Cushion", "Fabric", "Glow", "Hull"))
        if k % 2:
            p.sphere((px, py, F + 0.08), 0.08, c, seg=8, rings=4, smooth=True)
        else:
            s = rng.uniform(0.08, 0.14)
            with p.at(T(px, py, 0.0), RZ(rng.uniform(0, 90))):
                bbox(p, -s / 2, s / 2, -s / 2, s / 2, F, F + s, c)


def kid_desk(p, seed=0):
    """A small desk (back at x = 0, faces +X) with a lamp and a stool."""
    zt = F + 0.58
    bbox(p, 0.0, 0.48, -0.42, 0.42, zt - 0.03, zt, "Wood", bevel=0.01)
    for sy in (-1, 1):
        bbox(p, 0.02, 0.44, sy * 0.38 - 0.02, sy * 0.38 + 0.02, F, zt - 0.03, "Accent", mats={"-z": None})
    bbox(p, 0.08, 0.30, -0.12, 0.12, zt, zt + 0.02, "Hull")
    bbox(p, 0.10, 0.28, -0.10, 0.10, zt + 0.02, zt + 0.025, "Screen")
    with p.at(T(0.78, 0.0, 0.0)):
        p.vcyl(0, 0, F, F + 0.30, 0.16, 0.14, seg=10, mat="Accent", cap0=False)
        p.cap_disc(0.14, F + 0.30, "Cushion", seg=10)


def play_frame(p, seed=0):
    """A small climbing frame with a slide (about 1.9 x 0.8 m), centred at the origin, slide toward +X."""
    h = 0.78
    for sx in (-0.35, 0.35):
        for sy in (-0.35, 0.35):
            bbox(p, sx - 0.4 - 0.03, sx - 0.4 + 0.03, sy - 0.03, sy + 0.03, F, F + h + 0.45, "Accent", mats={"-z": None})
    bbox(p, -0.78, -0.02, -0.38, 0.38, F + h - 0.05, F + h, "Hull")
    bbox(p, -0.78, -0.02, -0.40, -0.36, F + h + 0.30, F + h + 0.36, "Frame")
    bbox(p, -0.78, -0.02, 0.36, 0.40, F + h + 0.30, F + h + 0.36, "Frame")
    for k in range(3):                                   # ladder rungs on -X
        z = F + 0.20 + 0.22 * k
        p.beam((-0.80, -0.28, z), (-0.80, 0.28, z), 0.03, 0.03, "Frame")
    # the slide: a ramp with raised edges
    a, b = (-0.02, 0.0, F + h), (1.10, 0.0, F + 0.08)
    for sy, m in ((-0.24, "Frame"), (0.24, "Frame")):
        p.beam((a[0], sy, a[2] + 0.06), (b[0], sy, b[2] + 0.06), 0.04, 0.12, m)
    p.quad((a[0], -0.22, a[2]), (b[0], -0.22, b[2]), (b[0], 0.22, b[2]), (a[0], 0.22, a[2]), "Glow")
    p.quad((a[0], 0.22, a[2] - 0.03), (b[0], 0.22, b[2] - 0.03), (b[0], -0.22, b[2] - 0.03), (a[0], -0.22, a[2] - 0.03),
           "Hull")


def washer(p, seed=0):
    """A washing machine, back at x = 0, faces +X (0.60 x 0.60 x 0.86)."""
    bbox(p, 0.0, 0.60, -0.30, 0.30, F, F + 0.86, "Hull", bevel=0.02)
    with p.at(T(0.602, 0.0, F + 0.44), RY(90.0)):
        p.lathe([(0.20, 0.0), (0.21, 0.02), (0.16, 0.03), (0.0, 0.03)], lambda k, i: ("Frame", "Frame", "Frost")[k],
                seg=16, smooth=False)
    plate_x(p, 0.603, -0.26, 0.26, F + 0.74, F + 0.82, "HullDark")
    plate_x(p, 0.605, 0.10, 0.22, F + 0.76, F + 0.80, "Screen")


def bathtub(p):
    """Bath, long along Y (1.70), back at x = 0, front at x = 0.78.  Rim top 0.56."""
    zt = F + 0.56
    bbox(p, 0.0, 0.78, -0.85, 0.85, F, zt, "Hull", bevel=0.03)
    plate_z(p, zt + 0.002, 0.08, 0.70, -0.76, 0.76, "HullDark")
    plate_z(p, zt - 0.12, 0.10, 0.68, -0.74, 0.74, "WaterBlue")
    bbox(p, 0.08, 0.70, -0.76, 0.76, zt - 0.12, zt - 0.119, "WaterBlue")
    p.vcyl(0.10, 0.70, zt, zt + 0.22, 0.02, seg=6, mat="Metal", cap0=False)
    p.beam((0.10, 0.70, zt + 0.22), (0.26, 0.70, zt + 0.18), 0.03, 0.03, "Metal")
    bbox(p, 0.30, 0.48, -0.70, -0.52, zt, zt + 0.02, "Cushion")          # a folded towel


def shower(p, s=0.92):
    """Shower corner: tray s x s (x 0..s, y -s/2..s/2), frosted panels on +X and +Y, a head on the back wall."""
    bbox(p, 0.0, s, -s / 2, s / 2, F, F + 0.06, "HullDark")
    plate_z(p, F + 0.062, 0.05, s - 0.05, -s / 2 + 0.05, s / 2 - 0.05, "Frame")
    h = 1.95
    bbox(p, s - 0.02, s + 0.02, -s / 2, s / 2 - 0.45, F + 0.06, F + h, "Frost")
    bbox(p, 0.0, s + 0.02, s / 2 - 0.02, s / 2 + 0.02, F + 0.06, F + h, "Frost")
    bbox(p, s - 0.03, s + 0.03, -s / 2, s / 2 + 0.03, F + h, F + h + 0.04, "Frame")
    p.vcyl(0.06, 0.0, F + 0.9, F + 1.92, 0.015, seg=6, mat="Metal", cap0=False, cap1=False)
    p.cyl((0.06, 0.0, F + 1.92), (0.20, 0.0, F + 1.88), 0.06, 0.08, seg=10, mat="Metal")


def wc(p):
    """Toilet against a wall: back at x = 0, faces +X."""
    bbox(p, 0.0, 0.18, -0.20, 0.20, F + 0.40, F + 0.80, "Hull", bevel=0.02)
    with p.at(T(0.42, 0.0, 0.0)):
        p.lathe([(0.12, F), (0.16, F + 0.30), (0.19, F + 0.40), (0.19, F + 0.43), (0.12, F + 0.43), (0.0, F + 0.43)],
                lambda k, i: "Hull" if k < 3 else ("Frame" if k == 3 else "HullDark"), seg=12, smooth=True)
    bbox(p, 0.18, 0.28, -0.08, 0.08, F + 0.30, F + 0.40, "Hull")


def vanity(p, w=0.90):
    """Wash basin on a cabinet, a mirror above; back at x = 0, faces +X."""
    zt = F + 0.86
    bbox(p, 0.0, 0.46, -w / 2, w / 2, F + 0.10, zt - 0.03, "Wood", bevel=0.01)
    bbox(p, 0.0, 0.48, -w / 2 - 0.01, w / 2 + 0.01, zt - 0.03, zt, "Hull")
    with p.at(T(0.25, 0.0, 0.0)):
        p.lathe([(0.19, zt), (0.20, zt + 0.10), (0.17, zt + 0.10), (0.15, zt + 0.03), (0.0, zt + 0.03)],
                lambda k, i: "Hull" if k < 2 else "Frost", seg=14, smooth=True)
    p.vcyl(0.05, 0.0, zt, zt + 0.22, 0.015, seg=6, mat="Metal", cap0=False)
    bbox(p, 0.0, 0.03, -w / 2 + 0.05, w / 2 - 0.05, zt + 0.30, zt + 0.88, "Frame")
    plate_x(p, 0.031, -w / 2 + 0.08, w / 2 - 0.08, zt + 0.33, zt + 0.85, "Frost")
    plate_x(p, 0.032, -w / 2 + 0.10, w / 2 - 0.10, zt + 0.80, zt + 0.83, "LightStrip")


def media_wall(p, w=1.6, seed=0):
    """Low media cabinet with a screen on a post (back at x = 0, faces +X)."""
    bbox(p, 0.0, 0.40, -w / 2, w / 2, F, F + 0.46, "Hull", bevel=0.015)
    plate_x(p, 0.402, -w / 2 + 0.03, w / 2 - 0.03, F + 0.40, F + 0.42, "LightStrip")
    for k in range(3):
        plate_x(p, 0.401, -w / 2 + 0.04 + (w - 0.08) * k / 3 + 0.01, -w / 2 + 0.04 + (w - 0.08) * (k + 1) / 3 - 0.01,
                F + 0.06, F + 0.36, "Wood" if k == 1 else "HullDark")
    with p.at(T(0.12, 0.0, F + 0.46 + 0.42)):
        IK.ui_screen(p, min(1.2, w * 0.8), 0.62, seed=seed)
    FU.pot_plant(p, 0.22, w / 2 - 0.18, r=0.12, h=0.20, s=0.55, seed=seed + 3, z0=F + 0.46)


def floor_lamp(p, lamp_cb=None):
    """A standing lamp: a weighted foot, a pole, a warm shade (the lamp position goes to lamp_cb)."""
    p.vcyl(0, 0, F, F + 0.03, 0.16, seg=10, mat="Frame", cap0=False)
    p.vcyl(0, 0, F + 0.03, F + 1.45, 0.018, seg=6, mat="Metal", cap0=False)
    p.lathe([(0.20, F + 1.30), (0.13, F + 1.58), (0.0, F + 1.58)], "Window", seg=12, smooth=True)
    p.lathe([(0.0, F + 1.30), (0.20, F + 1.30)], "LightStrip", seg=12, smooth=False)
    if lamp_cb:
        lamp_cb(0.0, 0.0, F + 1.40)


def sideboard(p, w=1.4, seed=0):
    """A low sideboard (back at x = 0, faces +X) with a lamp and books on top."""
    zt = F + 0.72
    bbox(p, 0.0, 0.44, -w / 2, w / 2, F + 0.08, zt, "Wood", bevel=0.012)
    bbox(p, 0.03, 0.41, -w / 2 + 0.04, w / 2 - 0.04, F, F + 0.08, "Frame", mats={"-z": None})
    for k in range(3):
        a0 = -w / 2 + 0.03 + (w - 0.06) * k / 3 + 0.01
        a1 = -w / 2 + 0.03 + (w - 0.06) * (k + 1) / 3 - 0.01
        plate_x(p, 0.442, a0, a1, F + 0.12, zt - 0.05, "HullDark" if k == 1 else "Hull")
    rng = random.Random(seed)
    y = -w / 2 + 0.10
    for k in range(5):
        bw = rng.uniform(0.04, 0.07)
        bbox(p, 0.10, 0.32, y, y + bw, zt, zt + rng.uniform(0.18, 0.26), rng.choice(("Accent", "Cushion", "Hull")))
        y += bw + 0.01
    FU.pot_plant(p, 0.22, w / 2 - 0.22, r=0.11, h=0.18, s=0.5, seed=seed, z0=zt)


def wall_art(c, u, v, yl, w=0.9, seed=0):
    """A framed picture on a partition face: (u, v) on the wall centre line, yl = the direction it faces."""
    n = c.plan.n
    rng = random.Random(seed)
    if seed % 4 == 3:
        import interior_roles as RO      # 5.0 (V5 15.3): a family wall of photographs and a child's drawing
        with c.at(u, v, yl):
            with n.at(T(0.048, 0.0, 0.0)):
                RO.photos(n, min(0.84, w), 0.0, seed)
        return
    if seed % 2 == 0:
        import interior_props as PR      # 5.0 (V5 15.3): original parody posters
        kinds = ("ai", "film", "band", "captcha", "travel", "wellness", "cat")
        with c.at(u, v, yl):
            with n.at(T(0.048, 0.0, 0.0)):
                PR.poster(n, w=min(0.68, w), kind=kinds[(seed // 2) % len(kinds)], seed=seed // 2, off=0.0)
        return
    with c.at(u, v, yl):
        bbox(n, 0.048, 0.072, -w / 2, w / 2, F + 0.70, F + 1.22, "Frame")
        plate_x(n, 0.073, -w / 2 + 0.04, w / 2 - 0.04, F + 0.74, F + 1.18, "Hull")
        cols = ("Accent", "Fabric", "CushionLight", "Wood", "Cushion", "Glow")
        x0 = -w / 2 + 0.07
        for k in range(3):
            bw = (w - 0.14) / 3.0
            z0 = F + 0.78 + rng.uniform(0.0, 0.12)
            z1 = F + 1.14 - rng.uniform(0.0, 0.12)
            plate_x(n, 0.074, x0 + k * bw + 0.01, x0 + (k + 1) * bw - 0.01, z0, z1, cols[(seed + 2 * k) % len(cols)])


def pendant(plan, c, u, v, seed=0):
    """A pendant lamp over a table: a cord from the ceiling line, a warm shade; a lamp anchor for the light pool."""
    n = plan.n
    x, y = c.w(u, v)
    n.vcyl(x, y, F + 1.78, F + 2.36, 0.008, seg=4, mat="Frame", cap0=False, cap1=False)
    with n.at(T(x, y, 0.0)):
        n.lathe([(0.26, F + 1.56), (0.20, F + 1.70), (0.05, F + 1.79), (0.0, F + 1.79)], "Wood" if seed % 2 else "Accent",
                seg=14, smooth=True)
        n.lathe([(0.0, F + 1.57), (0.22, F + 1.57)], "Window", seg=14, smooth=False)
    plan.lamp(x, y, F + 1.50)


def headboard_wall(c, uc, v_head, width=2.9):
    """The upholstered headboard wall behind a pair of beds (executive): Cushion panel with Accent piping and
    two reading-light strips."""
    n = c.plan.n
    with c.at(uc, v_head, 90.0):
        bbox(n, -0.030, 0.010, -width / 2 - 0.06, width / 2 + 0.06, F + 0.30, F + 1.29, "Wood")
        bbox(n, -0.045, -0.02, -width / 2, width / 2, F + 0.62, F + 1.24, "Fabric", bevel=0.01)
        for k_ in range(6):
            yy_ = -width / 2 + width * (k_ + 0.5) / 6
            bbox(n, -0.050, -0.035, yy_ - 0.01, yy_ + 0.01, F + 0.66, F + 1.20, "Cushion")
        for yy in (-0.72, 0.72):
            plate_x(n, -0.051, yy - 0.28, yy + 0.28, F + 1.18, F + 1.20, "LightStrip", facing=-1)


def rug_pattern(p, hx, hy, seed=0):
    """A children's rug with coloured stripes and a border, centred at the origin."""
    cols = ("Accent", "Fabric", "Glow", "CushionLight", "Hull")
    z = F + 0.012
    bbox(p, -hx, hx, -hy, hy, F, z, "Accent", mats={"-z": None})
    n = 5
    for k in range(n):
        y0 = -hy + 0.08 + (2 * hy - 0.16) * k / n
        y1 = -hy + 0.08 + (2 * hy - 0.16) * (k + 1) / n
        plate_z(p, z + 0.001, -hx + 0.08, hx - 0.08, y0, y1, cols[(k + seed) % len(cols)])


def armchair(p, fabric="Cushion"):
    return FU.sofa(p, n=1, seat_w=0.70, fabric=fabric)


def planter_box(p, L, d=0.46, seed=0):
    """Free-standing garden planter along X (length L), centred."""
    bbox(p, -L / 2, L / 2, -d / 2, d / 2, F, F + 0.48, "Hull", bevel=0.02)
    plate_z(p, F + 0.47, -L / 2 + 0.04, L / 2 - 0.04, -d / 2 + 0.04, d / 2 - 0.04, "Soil")
    for sy in (-1, 1):
        plate_y(p, sy * (d / 2 + 0.003), -L / 2 + 0.05, L / 2 - 0.05, F + 0.36, F + 0.40, "LightStrip", facing=sy)
    n = max(2, int(L / 0.42))
    for k in range(n):
        x = -L / 2 + L * (k + 0.5) / n
        FU.leafy_plant(p, x, 0.0, F + 0.44, s=0.55 + 0.12 * ((k * 7 + seed) % 3), n=5, seed=seed + k)


def bench(p, L=1.4):
    """A slatted bench along Y, the sitter faces +X."""
    zs = F + SEAT_Z
    for sy in (-1, 1):
        bbox(p, -0.20, 0.20, sy * (L / 2 - 0.10) - 0.03, sy * (L / 2 - 0.10) + 0.03, F, zs - 0.04, "Frame",
             mats={"-z": None})
    for k in range(3):
        x0 = -0.20 + 0.14 * k
        bbox(p, x0 + 0.01, x0 + 0.12, -L / 2, L / 2, zs - 0.04, zs, "Wood")
    bbox(p, -0.24, -0.20, -L / 2, L / 2, zs + 0.10, zs + 0.40, "Wood")


# --------------------------------------------------------------------------------------
# Units
# --------------------------------------------------------------------------------------
def V5_rug_big(p):
    """A large bedroom rug with a patterned border (drawn under and round the executive beds)."""
    FU.rug_rect(p, 1.75, 1.35, mat="RugLight", border="Fabric")
    for sx in (-1, 1):
        plate_z(p, F + 0.0135, sx * 1.55 - 0.05, sx * 1.55 + 0.05, -1.15, 1.15, "Accent")


def exec_bed(p, duvet="CushionLight", throw="Fabric", seed=0):
    """Executive bed (the bed convention: centre at the origin, heads toward +Y, stand point (+0.55, 0)): an
    upholstered platform wider than the mattress, a deep duvet, two pillows and a bolster; no headboard (the
    headboard wall behind the pair)."""
    W, L = IR.BED_W, IR.BED_L
    zt = F + BED_Z
    bbox(p, -W / 2 - 0.08, W / 2 + 0.08, -L / 2 - 0.08, L / 2, F + 0.06, zt - 0.17, "Wood", bevel=0.03)
    bbox(p, -W / 2 - 0.08, W / 2 + 0.08, -L / 2 - 0.14, -L / 2 - 0.04, F + 0.06, zt + 0.02, "Cushion", bevel=0.03)
    bbox(p, -W / 2 + 0.06, W / 2 - 0.06, -L / 2 + 0.06, L / 2 - 0.08, F, F + 0.07, "FloorDark", mats={"-z": None})
    bbox(p, -W / 2 + 0.02, W / 2 - 0.02, -L / 2 + 0.02, L / 2 - 0.04, zt - 0.17, zt, "Hull", bevel=0.05)
    bbox(p, -W / 2 - 0.04, W / 2 + 0.04, -L / 2 - 0.02, L / 2 - 0.55, zt - 0.12, zt + 0.05, duvet, bevel=0.03)
    bbox(p, -W / 2 - 0.05, W / 2 + 0.05, -L / 2 + 0.05, -L / 2 + 0.45, zt + 0.04, zt + 0.09, throw, bevel=0.02)
    for sx in (-1, 1):
        with p.at(T(sx * 0.21, L / 2 - 0.30, zt + 0.07), RZ(sx * 3.0)):
            bbox(p, -0.20, 0.20, -0.14, 0.14, -0.06, 0.08, "Hull", bevel=0.05)
    p.cyl((-0.30, L / 2 - 0.55, zt + 0.08), (0.30, L / 2 - 0.55, zt + 0.08), 0.08, seg=8, mat=throw)


def exec_bay(plan, c, uc, v_head, idx):
    """The executive pair: two upholstered beds (same anchors and footprints as interior_rooms.bay), a wide
    bedside unit between them with two lamps."""
    n = plan.n
    hx, hy = c.w(uc, v_head)
    dirdeg = c.yaw(90.0)
    cc, ss = cos(radians(dirdeg)), sin(radians(dirdeg))

    def to_w(bx, by):
        return hx + cc * bx - ss * by, hy + ss * bx + cc * by
    xc = -(0.07 + IR.BED_L / 2)
    for j, by in enumerate((-(IR.GAP / 2 + IR.BED_W / 2), IR.GAP / 2 + IR.BED_W / 2)):
        wx, wy = to_w(xc, by)
        yaw = dirdeg - 90.0
        with n.at(T(wx, wy, 0.0), RZ(yaw)):
            exec_bed(n, duvet=("Fabric", "Cushion")[(idx + j) % 2], throw=("CushionLight", "Accent")[j], seed=idx)
        plan.rect(wx, wy, IR.BED_L / 2 + 0.07, IR.BED_W / 2 + 0.05, dirdeg, tag="bed%d" % (idx + j))
        sx, sy = to_w(xc, by - BED_BACK)
        plan.anchor("Bed", sx, sy, yaw)
    ux, uy = to_w(-0.27, 0.0)
    with n.at(T(ux, uy, 0.0), RZ(dirdeg - 90.0)):
        FU.bedside(n, item="books", seed=idx, lamp_cb=IR.lamp_cb(plan, n))
    plan.rect(ux, uy, 0.21, 0.23, dirdeg, tag="bed%d" % idx)


def _bay(plan, c, uc, v_head, idx):
    """The parents' / the bedroom's two beds, heads on the back line (uc, v_head), heads toward +v."""
    x, y = c.w(uc, v_head)
    IR.bay(plan, x, y, c.yaw(90.0), idx, tall=False)


def _bunk(plan, c, u, v, yl, seed):
    """A bunk bed centred at (u, v); yl = local yaw of the bed frame (+Y = heads).  Adds two Beds: the lower bunk,
    then the upper bunk (the same stand point lifted by BUNK_UP, so the lying pose lands on the upper mattress;
    coordinator decision 2026-09-30: the children's bunks count as 2 beds)."""
    n = plan.n
    with c.at(u, v, yl):
        bunk_bed(n, blankets=(("Accent", "Fabric"), ("Fabric", "Cushion"), ("Cushion", "Accent"))[seed % 3], seed=seed)
    c.rect(u, v, 0.51, 1.06, yl, tag="bunk")
    c.anchor("Bed", u, v, yl, lx=BED_BACK)
    c.anchor("Bed", u, v, yl, lx=BED_BACK, z=F + BUNK_UP)


BUNK_UP = 1.12            # upper mattress top above the lower one (bunk_bed: z2 = z1 + 1.12)


def c_off(u, v, yl, lx, ly):
    a = radians(yl)
    return (u + lx * cos(a) - ly * sin(a), v + lx * sin(a) + ly * cos(a))


def _table(plan, c, u, v, yl, seed, anchors=2, n_chairs=4, hx=0.62, hy=0.40):
    """Family table (long along local x of the frame yl) with n_chairs chairs; the first `anchors` chairs
    get a Seat."""
    n = plan.n
    with c.at(u, v, yl):
        FU.table_rect(n, hx, hy, top="Wood", edge="Accent")
        FU.pot_plant(n, 0.0, 0.0, r=0.08, h=0.12, s=0.45, seed=seed, z0=F + 0.74)
        bbox(n, -0.35, -0.13, -0.12, 0.12, F + 0.74, F + 0.745, "Cushion")
    c.rect(u, v, hx, hy, yl, tag="table")
    k = 0
    for sy in (-1, 1):
        for sx in (-0.30, 0.30):
            if k >= n_chairs:
                break
            lx, ly = sx, sy * (hy + 0.42)        # the stand point 0.12 off the table edge (check_desk_seats)
            cu, cv = c_off(u, v, yl, lx, ly)
            cy_ = yl - 90.0 * sy            # faces the table
            with c.at(cu, cv, cy_):
                FU.chair(n)
            c.rect(cu, cv, 0.25, 0.24, cy_, tag="seat")
            if k < anchors:
                c.anchor("Seat", cu, cv, cy_, lx=SEAT_BACK)
            k += 1


def family_unit(plan, c, s, idx, seed):
    W, Dp = c.W, c.Dp
    n = plan.n
    if Dp >= 4.6:
        # A: bedrooms along the back, the living room at the street
        db = 3.0 if s <= 2 else 3.3
        vb = Dp - db
        up = 0.56 * W
        u_door = 0.5 * W
        wall(c, 0.0, 0.0, W, 0.0, gaps=[(u_door, DOOR_W)])
        wall(c, up, vb, up, Dp)
        wall(c, 0.0, vb, up, vb, gaps=[(0.55, IDOOR_W)])
        wall(c, up, vb, W, vb, gaps=[(W - up - 0.55, IDOOR_W)])
        c.floor(0.05, up - 0.05, vb + 0.05, Dp - 0.05, "RugLight")
        c.floor(up + 0.05, W - 0.05, vb + 0.05, Dp - 0.05, "CushionLight")
        c.floor(0.05, W - 0.05, 0.05, vb - 0.05, "Wood")
        with c.at(0.5 * (up + W) + 0.15, vb + 0.95, 0.0):
            rug_pattern(n, 0.75, 0.55, seed=seed)
        # parents: two beds, heads to the back wall; the outer stand side toward the partition
        uc = min(up - 1.70, max(1.35, 0.5 * up))
        _bay(plan, c, uc, Dp - 0.06, 3 * idx)
        if up - uc - 1.215 > 1.1:                      # room for a wardrobe beside the bed stand
            with c.at(up - 0.06, Dp - 0.50, 180.0):
                FU.wi_wardrobe(n, w=0.80, d=0.42, h=1.26)
            c.rect(up - 0.27, Dp - 0.50, 0.21, 0.40, tag="wardrobe")
        # children: bunk along the back wall, heads toward the side wall; toys, a chest, a small desk at XL
        bu = W - 0.10 - 1.06
        _bunk(plan, c, bu, Dp - 0.08 - 0.51, -90.0, seed)
        with c.at(up + 0.06, Dp - 0.45, 0.0):
            toy_chest(n, w=0.62, d=0.40, seed=seed)
        c.rect(up + 0.26, Dp - 0.45, 0.21, 0.32, tag="chest")
        if s >= 2:
            with c.at(up + 0.06, vb + 0.95, 0.0):
                kid_desk(n, seed=seed)
            c.rect(up + 0.48, vb + 0.95, 0.46, 0.42, tag="desk")
        toys(n, *c.w(0.5 * (up + W), vb + 0.75), seed=seed + 2, n=5)
        # living: kitchenette on the street wall left of the door, the family table on the right
        kw = min(2.2, u_door - DOOR_W / 2 - 0.25)
        with c.at(0.10 + kw / 2, 0.06, 90.0):
            kitchenette(n, w=kw, seed=seed)
        c.rect(0.10 + kw / 2, 0.06 + 0.31, kw / 2, 0.33, 0.0, tag="counter")
        c.anchor("Stand", 0.10 + kw / 2 - 0.35, 0.06 + 1.05, -90.0)
        tu = W - 1.5
        tv = 0.5 * vb + 0.05
        _table(plan, c, tu, tv, 0.0, seed)
        pendant(plan, c, tu, tv, seed)
        wall_art(c, 0.5 * up + 0.4, vb, -90.0, w=0.9, seed=seed)
        if s >= 3:
            # a two-seat sofa against the bedroom wall, facing the street, and a media wall on the street side
            su = 0.5 * (1.0 + up - 0.2)
            sv = vb - 0.06 - 0.44
            with c.at(su, sv, -90.0):
                FU.sofa(n, n=2, seat_w=0.62, fabric="Cushion")
            c.rect(su, sv + 0.03, 0.42, 0.76, -90.0, tag="sofa")
            with c.at(su, sv - 1.0, 0.0):
                FU.coffee_table(n, hx=0.50, hy=0.30)
            c.rect(su, sv - 1.0, 0.50, 0.30, tag="ctable")
            if s >= 4:                                  # XL: room for a sideboard by the door
                with c.at(u_door + DOOR_W / 2 + 0.85, 0.06, 90.0):
                    sideboard(n, w=1.2, seed=seed)
                c.rect(u_door + DOOR_W / 2 + 0.85, 0.28, 0.60, 0.22, tag="sideboard")
        FU.pot_plant(n, *c.w(W - 0.35, 0.40), r=0.18, h=0.36, s=0.9, seed=seed + 5)
        c.rect(W - 0.35, 0.40, 0.2, 0.2, tag="plant")
        lights = [c.w(0.5 * W, 0.5 * vb), c.w(0.5 * up, vb + 0.5 * db), c.w(0.5 * (up + W), vb + 0.5 * db)]
        door = (u_door, 0.0)
    else:
        # B (M): the living room at one end, the bedrooms side by side behind a short hall
        hall = 1.1
        ul = 0.45 * W
        up = ul + 3.1
        u_door = ul - 0.75
        wall(c, 0.0, 0.0, W, 0.0, gaps=[(u_door, DOOR_W)])
        wall(c, ul, hall, ul, Dp)
        wall(c, up, hall, up, Dp)
        wall(c, ul, hall, up, hall, gaps=[(0.55, IDOOR_W)])
        wall(c, up, hall, W, hall, gaps=[(W - up - 0.55, IDOOR_W)])
        c.floor(ul + 0.05, up - 0.05, hall + 0.05, Dp - 0.05, "RugLight")
        c.floor(up + 0.05, W - 0.05, hall + 0.05, Dp - 0.05, "CushionLight")
        c.floor(0.05, ul - 0.05, 0.05, Dp - 0.05, "Wood")
        with c.at(W - 0.80, hall + 0.95, 90.0):
            rug_pattern(n, 0.55, 0.45, seed=seed)
        uc = up - 1.72
        _bay(plan, c, uc, Dp - 0.06, 3 * idx)
        # the bunk against the partition, heads to the back wall; its stand side toward the room
        _bunk(plan, c, up + 0.08 + 0.51, Dp - 0.08 - 1.06, 0.0, seed)
        with c.at(W - 0.06, Dp - 0.50, 180.0):
            toy_chest(n, w=0.62, d=0.40, seed=seed)
        c.rect(W - 0.26, Dp - 0.50, 0.21, 0.32, tag="chest")
        toys(n, *c.w(W - 0.6, hall + 0.9), seed=seed + 2, n=4)
        # living: kitchenette on the end wall, table in the middle
        kw = min(2.2, Dp - 0.6)
        with c.at(0.06, 0.25 + kw / 2, 0.0):
            kitchenette(n, w=kw, seed=seed)
        c.rect(0.06 + 0.31, 0.25 + kw / 2, 0.33, kw / 2, 0.0, tag="counter")
        c.anchor("Stand", 0.06 + 1.05, 0.25 + kw / 2 - 0.3, 180.0)
        _table(plan, c, 0.5 * ul + 0.45, Dp - 1.35, 0.0, seed)
        pendant(plan, c, 0.5 * ul + 0.45, Dp - 1.35, seed)
        wall_art(c, ul, 2.0, 180.0, w=0.8, seed=seed)
        FU.pot_plant(n, *c.w(ul - 0.35, Dp - 0.35), r=0.18, h=0.36, s=0.9, seed=seed + 5)
        c.rect(ul - 0.35, Dp - 0.35, 0.2, 0.2, tag="plant")
        lights = [c.w(0.5 * ul, 0.5 * Dp), c.w(0.5 * (ul + up), 0.5 * (hall + Dp)), c.w(0.5 * (up + W), 0.5 * (hall + Dp))]
        door = (u_door, 0.0)
    c.anchor("Unit", door[0], door[1], 90.0)
    door_plate(c, door[0] - DOOR_W / 2 - 0.25, idx)
    return lights


def _bath(plan, c, u0, u1, v0, v1, seed, door="u0"):
    """En-suite bath in the rectangle; `door` = the wall with the door ("u0", "u1" side walls: gap 0.6..1.44 m from
    the front; "v0" front wall: gap at the u0 end).  Tub on the back wall at the far side, shower in the far front
    corner, WC on the far wall between them, basin near the door."""
    n = plan.n
    c.floor(u0 + 0.05, u1 - 0.05, v0 + 0.05, v1 - 0.05, "Frost")
    with c.at(0.5 * (u0 + u1), v0 + 0.5 * (v1 - v0), 0.0):
        FU.rug_rect(n, 0.45, 0.32, mat="CushionLight", border="Accent")         # a bath mat
    far = u0 if door == "u1" else u1          # the side away from the door
    sg = 1.0 if far == u1 else -1.0           # +1: far side is +u
    # tub along the back wall, pushed to the far side (long along u)
    tu = far - sg * (0.06 + 0.85)
    with c.at(tu, v1 - 0.06, -90.0):
        bathtub(n)
    c.rect(tu, v1 - 0.45, 0.85, 0.39, tag="tub")
    # shower in the far front corner
    su = far - sg * 0.06
    with c.at(su, v0 + 0.06 + 0.46, 180.0 if sg > 0 else 0.0):
        shower(n, s=0.92)
    c.rect(far - sg * 0.52, v0 + 0.52, 0.46, 0.46, tag="shower")
    # WC on the far wall between the shower and the tub
    wv = v0 + 0.98 + 0.5 * ((v1 - 0.84) - (v0 + 0.98))
    with c.at(far - sg * 0.06, wv, 180.0 if sg > 0 else 0.0):
        wc(n)
    c.rect(far - sg * 0.38, wv, 0.32, 0.21, tag="wc")
    # basin: on the front wall near the door (side door) or on the near wall (front door)
    if door in ("u0", "u1"):
        near = u0 if door == "u0" else u1
        bu = near + (1.2 if door == "u0" else -1.2)
        with c.at(bu, v0 + 0.06, 90.0):
            vanity(n, w=0.9)
        c.rect(bu, v0 + 0.30, 0.45, 0.24, tag="vanity")
    else:
        with c.at(u0 + 0.06, v0 + 1.75, 0.0):
            vanity(n, w=0.9)
        c.rect(u0 + 0.30, v0 + 1.75, 0.24, 0.45, tag="vanity")


def _office(plan, c, ud, vd, yl, seed):
    """Desk with its front edge at (ud, vd) facing local yl (the sitter faces the desk), an office chair."""
    n = plan.n
    with c.at(ud, vd, yl):
        FU.desk(n, w=1.4, d=0.65, monitors=2, lamp_cb=IR.lamp_cb(plan, n), seed=seed)
    c.rect(*c_off(ud, vd, yl, -0.33, 0.0), 0.33, 0.70, yl, tag="desk")
    cu, cv = c_off(ud, vd, yl, 0.42, 0.0)
    with c.at(cu, cv, yl + 180.0):
        FU.office_chair(n)
    c.rect(cu, cv, 0.28, 0.28, yl, tag="seat")
    c.anchor("Seat", cu, cv, yl + 180.0, lx=SEAT_BACK)


def _lounge(plan, c, u, v, yl, seed, seats=2, screen_d=2.3, vmax=None, fabric="Cushion"):
    """Three-seat sofa at (u, v) facing local yl, a coffee table, a media wall screen_d ahead; the first
    `seats` sofa places get a Seat."""
    n = plan.n
    with c.at(u, v, yl):
        pts = FU.sofa(n, n=3, seat_w=0.62, fabric=fabric)
    c.rect(*c_off(u, v, yl, -0.03, 0.0), 0.42, 1.08, yl, tag="sofa")
    if fabric != "Cushion":                                # the executive sectional: a chaise at one end
        with c.at(u, v, yl):
            bbox(n, -0.44, 0.95, 0.95, 1.55, F + 0.04, F + 0.22, "Frame", bevel=0.02)
            bbox(n, -0.24, 0.93, 0.97, 1.53, F + 0.22, F + 0.46, fabric, bevel=0.04)
            bbox(n, -0.44, -0.24, 0.97, 1.53, F + 0.22, F + 0.88, fabric, bevel=0.05)
        c.rect(*c_off(u, v, yl, 0.25, 1.25), 0.70, 0.30, yl, tag="sofa")
    for k, (sx, sy) in enumerate(pts[:seats]):
        su, sv = c_off(u, v, yl, sx, sy)
        c.anchor("Seat", su, sv, yl, lx=SEAT_BACK)
    tu, tv = c_off(u, v, yl, 1.05, 0.0)
    with c.at(tu, tv, yl):
        FU.coffee_table(n, hx=0.32, hy=0.55)
        FU.rug_rect(n, 1.05, 1.25, mat="RugLight", border="Accent")
    c.rect(tu, tv, 0.32, 0.55, yl, tag="ctable")
    # a floor lamp at one end of the sofa, a plant at the other (only where the room has floor for them)
    vmax = c.Dp if vmax is None else vmax

    def inside(uu, vv, r):
        return r + 0.12 < uu < c.W - r - 0.12 and r + 0.12 < vv < vmax - r - 0.12
    lu, lv = c_off(u, v, yl, -0.10, 1.35)
    if inside(lu, lv, 0.18):
        with c.at(lu, lv, 0.0):
            floor_lamp(n, lamp_cb=IR.lamp_cb(plan, n))
        c.rect(lu, lv, 0.18, 0.18, tag="lamp")
    pu, pv = c_off(u, v, yl, -0.10, -1.35)
    if inside(pu, pv, 0.22):
        FU.pot_plant(n, *c.w(pu, pv), r=0.20, h=0.40, s=1.0, seed=seed + 9)
        c.rect(pu, pv, 0.22, 0.22, tag="plant")
    if not screen_d:
        return
    mu, mv = c_off(u, v, yl, screen_d, 0.0)
    with c.at(mu, mv, yl + 180.0):
        media_wall(n, w=1.6, seed=seed)
    c.rect(*c_off(u, v, yl, screen_d - 0.20, 0.0), 0.20, 0.80, yl, tag="media")


def exec_unit(plan, c, s, idx, seed):
    W, Dp = c.W, c.Dp
    n = plan.n
    if Dp >= 4.6:
        db = 3.0 if s <= 2 else 3.2
        vb = Dp - db
        ub = 4.4                                        # bedroom | bath
        ue = min(W, ub + 3.0) if W > 10.0 else W        # bath | office (L: the office behind; XL: none behind)
        u_door = 0.5 * W if W > 10.0 else 3.1
        wall(c, 0.0, 0.0, W, 0.0, gaps=[(u_door, DOOR_W)])
        wall(c, ub, vb, ub, Dp, gaps=[(1.02, IDOOR_W)])         # en-suite door from the bedroom
        wall(c, 0.0, vb, ub, vb, gaps=[(1.5 if W > 10.0 else 3.4, IDOOR_W)])
        wall(c, ub, vb, ue, vb)
        c.floor(0.05, ub - 0.05, vb + 0.05, Dp - 0.05, "Wood")
        _bath(plan, c, ub, ue, vb, Dp, seed, door="u0")
        uc = 1.60
        exec_bay(plan, c, uc, Dp - 0.06, 2 * idx)
        headboard_wall(c, uc, Dp - 0.045)
        wall_art(c, 3.3 if W > 10.0 else 1.4, vb, 90.0, w=0.8, seed=seed + 1)
        with c.at(uc, Dp - 1.3, 0.0):
            V5_rug_big(n)
        wall_art(c, ue if W > 10.0 else W, vb + 1.5 if W > 10.0 else vb + 2.2, 180.0, w=0.6, seed=seed + 7) \
            if W <= 10.0 else None
        if W > 10.0:
            FU.pot_plant(n, *c.w(ub - 0.33, Dp - 1.25), r=0.20, h=0.40, s=1.0, seed=seed + 4)
            c.rect(ub - 0.33, Dp - 1.25, 0.22, 0.22, tag="plant")
        else:
            FU.pot_plant(n, *c.w(0.33, vb + 0.35), r=0.20, h=0.40, s=1.0, seed=seed + 4)
            c.rect(0.33, vb + 0.35, 0.22, 0.22, tag="plant")
        with c.at(uc, Dp - 0.06 - 2.3, 0.0):
            FU.rug_rect(n, 1.1, 0.34, mat="Cushion", border="Accent")
        with c.at(ub - 0.06, Dp - 0.55, 180.0):
            FU.wi_wardrobe(n, w=0.80, d=0.42, h=1.26)
        c.rect(ub - 0.27, Dp - 0.55, 0.21, 0.40, tag="wardrobe")
        if Dp - 1.3 - 0.4 > vb + 1.02 + IDOOR_W / 2 + 0.05:
            with c.at(ub - 0.06, Dp - 1.30, 180.0):
                FU.wi_wardrobe(n, w=0.80, d=0.42, h=1.26, insert="Cushion")
            c.rect(ub - 0.27, Dp - 1.30, 0.21, 0.40, tag="wardrobe")
        if W > 10.0:
            # L: the office behind, beside the bath; the lounge along the street
            wall(c, ue, vb, ue, Dp)
            wall(c, ue, vb, W, vb, gaps=[(0.5 * (W - ue), 1.6)])
            c.floor(ue + 0.05, W - 0.05, vb + 0.05, Dp - 0.05, "Wood")
            with c.at(0.5 * (ue + W), vb + 1.0, 0.0):
                FU.rug_rect(n, 1.3, 0.6, mat="RugLight", border="Accent")
            wall_art(c, ue, vb + 1.6, 0.0, w=0.8, seed=seed + 2)
            _office(plan, c, 0.5 * (ue + W), Dp - 0.06 - 0.65, -90.0, seed)
            with c.at(W - 0.06, Dp - 0.65, 180.0):
                FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed)
            c.rect(W - 0.24, Dp - 0.65, 0.18, 0.40, tag="shelf")
            with c.at(W - 0.06, vb + 0.62, 180.0):
                FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed + 1)
            c.rect(W - 0.24, vb + 0.62, 0.18, 0.40, tag="shelf")
            FU.tall_plant(n, *c.w(ue + 0.45, Dp - 0.45), seed=seed + 3)
            c.rect(ue + 0.45, Dp - 0.45, 0.27, 0.27, tag="plant")
            c.floor(0.05, W - 0.05, 0.05, vb - 0.05, "Wood")
            with c.at(4.75, 0.06, 90.0):
                sideboard(n, w=1.4, seed=seed)
            c.rect(4.75, 0.28, 0.70, 0.22, tag="sideboard")
            # lounge: sofa facing +u, media wall on the unit's end wall
            _lounge(plan, c, 3.25, 0.5 * vb + 0.05, 180.0, seed, seats=2, screen_d=3.19, vmax=vb, fabric="RugLight")
            # the lamp and the plant stand in the lounge corners by the bedroom wall
            with c.at(3.95, vb - 0.30, 0.0):
                floor_lamp(n, lamp_cb=IR.lamp_cb(plan, n))
            c.rect(3.95, vb - 0.30, 0.18, 0.18, tag="lamp")
            FU.pot_plant(n, *c.w(2.45, vb - 0.32), r=0.20, h=0.40, s=1.0, seed=seed + 9)
            c.rect(2.45, vb - 0.32, 0.22, 0.22, tag="plant")
            kw = 2.2
            with c.at(W - 0.10 - kw / 2, 0.06, 90.0):
                kitchenette(n, w=kw, seed=seed)
            c.rect(W - 0.10 - kw / 2, 0.37, kw / 2, 0.33, tag="counter")
            c.anchor("Stand", W - 0.10 - kw / 2 - 0.35, 0.06 + 1.05, -90.0)
            wall_art(c, 2.2, 0.0, 90.0, w=1.0, seed=seed + 3)
            with c.at(u_door + 2.2, 0.5 * vb + 0.1, 0.0):
                FU.rug_round(n, 1.25, mat="RugLight", ring="Fabric", seg=24)
            for k, uu in enumerate((5.0, 5.85)):
                with c.at(uu, vb - 0.06, -90.0):
                    FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed + 5 + k)
                c.rect(uu, vb - 0.24, 0.40, 0.18, tag="shelf")
            pendant(plan, c, u_door + 2.2, 0.5 * vb + 0.1, seed)
            with c.at(u_door + 2.2, 0.5 * vb + 0.1, 0.0):
                FU.table_round(n, r=0.45, top="Wood")
            c.rect(u_door + 2.2, 0.5 * vb + 0.1, 0.45, 0.45, tag="table")
            for sy in (-1, 1):
                cu, cv = u_door + 2.2, 0.5 * vb + 0.1 + sy * 0.75
                with c.at(cu, cv, -90.0 * sy):
                    FU.chair(n)
                c.rect(cu, cv, 0.25, 0.24, -90.0 * sy, tag="seat")
            lights = [c.w(0.25 * W, 0.5 * vb), c.w(0.75 * W, 0.5 * vb), c.w(0.5 * ub, vb + 0.5 * db),
                      c.w(0.5 * (ue + W), vb + 0.5 * db)]
        else:
            # XL: the lounge and an open office along the street
            uo = 4.6
            wall(c, uo, 1.4, uo, vb)
            c.floor(0.05, uo - 0.05, 0.05, vb - 0.05, "Wood")
            c.floor(uo + 0.05, W - 0.05, 0.05, vb - 0.05, "Wood")
            with c.at(0.5 * (uo + W), 0.5 * (1.4 + vb) + 0.2, 0.0):
                FU.rug_rect(n, 1.2, 0.9, mat="Cushion", border="Accent")
            wall_art(c, 1.2, 0.0, 90.0, w=1.0, seed=seed + 3)
            wall_art(c, uo, 1.95, 0.0, w=0.7, seed=seed + 2)
            with c.at(1.8, vb - 0.06, -90.0):
                FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed + 5)
            c.rect(1.8, vb - 0.24, 0.40, 0.18, tag="shelf")
            FU.pot_plant(n, *c.w(uo + 0.35, 1.75), r=0.20, h=0.40, s=1.0, seed=seed + 6)
            c.rect(uo + 0.35, 1.75, 0.22, 0.22, tag="plant")
            _office(plan, c, W - 0.06 - 0.65, 0.5 * (1.4 + vb) + 0.2, 180.0, seed)
            with c.at(uo + 0.06, vb - 0.55, 0.0):
                FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed)
            c.rect(uo + 0.24, vb - 0.55, 0.18, 0.40, tag="shelf")
            _lounge(plan, c, 0.55, 0.5 * vb + 0.35, 0.0, seed, seats=2, screen_d=uo - 0.06 - 0.55, vmax=vb,
                    fabric="RugLight")
            kw = 2.0
            with c.at(W - 0.10 - kw / 2, 0.06, 90.0):
                kitchenette(n, w=kw, seed=seed)
            c.rect(W - 0.10 - kw / 2, 0.37, kw / 2, 0.33, tag="counter")
            c.anchor("Stand", W - 0.10 - kw / 2 - 0.35, 0.06 + 1.05, -90.0)
            lights = [c.w(0.3 * W, 0.5 * vb), c.w(0.75 * W, 0.5 * vb), c.w(0.5 * ub, vb + 0.5 * db),
                      c.w(0.5 * (ub + W), vb + 0.5 * db)]
        door = (u_door, 0.0)
    else:
        # M: lounge (with the office nook) at one end; bath and bedroom behind a short hall
        hall = 1.1
        ul = 0.45 * W
        ub = ul + 2.3
        u_door = ul - 0.75
        wall(c, 0.0, 0.0, W, 0.0, gaps=[(u_door, DOOR_W)])
        wall(c, ul, hall, ul, Dp)
        wall(c, ub, hall, ub, Dp)
        wall(c, ul, hall, ub, hall, gaps=[(0.55, IDOOR_W)])
        wall(c, ub, hall, W, hall, gaps=[(0.55, IDOOR_W)])
        c.floor(0.05, ul - 0.05, 0.05, Dp - 0.05, "Wood")
        c.floor(ub + 0.05, W - 0.05, hall + 0.05, Dp - 0.05, "Wood")
        _bath(plan, c, ul, ub, hall, Dp, seed, door="v0")
        uc = W - 1.72
        exec_bay(plan, c, uc, Dp - 0.06, 2 * idx)
        headboard_wall(c, uc, Dp - 0.045)
        with c.at(uc, hall + 0.45, 0.0):
            FU.rug_rect(n, 1.1, 0.30, mat="Cushion", border="Accent")
        wall_art(c, ul, 2.85, 180.0, w=0.9, seed=seed + 1)
        with c.at(0.06, 2.55, 0.0):
            FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed + 5)
        c.rect(0.24, 2.55, 0.18, 0.40, tag="shelf")
        _office(plan, c, 0.95, Dp - 0.06 - 0.65, -90.0, seed)
        _lounge(plan, c, ul - 0.55, 2.85, 180.0, seed, seats=2, screen_d=None, fabric="RugLight")
        kw = 1.8
        with c.at(0.06, 0.2 + kw / 2, 0.0):
            kitchenette(n, w=kw, seed=seed)
        c.rect(0.37, 0.2 + kw / 2, 0.33, kw / 2, tag="counter")
        c.anchor("Stand", 0.06 + 1.05, 0.2 + kw / 2 - 0.3, 180.0)
        lights = [c.w(0.5 * ul, 0.5 * Dp), c.w(0.5 * (ub + W), 0.5 * (hall + Dp)), c.w(0.5 * (ul + ub), 0.5 * (hall + Dp))]
        door = (u_door, 0.0)
    c.anchor("Unit", door[0], door[1], 90.0)
    door_plate(c, door[0] - DOOR_W / 2 - 0.25, idx)
    return lights


def family_commons(plan, c, seed):
    """Shared play room and laundry (the cell with no unit)."""
    W, Dp = c.W, c.Dp
    n = plan.n
    wall(c, 0.0, 0.0, W, 0.0, gaps=[(0.5 * W, 2.2)])
    c.floor(0.05, W - 0.05, 0.05, Dp - 0.05, "RugLight")
    with c.at(0.5 * W - 0.3, Dp - 1.3, 0.0):
        play_frame(n, seed=seed)
    c.rect(0.5 * W - 0.1, Dp - 1.3, 1.1, 0.45, tag="play")
    FU.rug_round(n, 1.0, *c.w(0.28 * W, 0.45 * Dp), mat="RugLight", ring="Accent", seg=20)
    toys(n, *c.w(0.28 * W, 0.45 * Dp), seed=seed, n=7)
    for k in range(2):
        with c.at(W - 0.06, 0.9 + 0.66 * k, 180.0):
            washer(n, seed=k)
        c.rect(W - 0.36, 0.9 + 0.66 * k, 0.31, 0.31, tag="washer")
    with c.at(W - 0.06, 2.55, 180.0):
        FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed)
    c.rect(W - 0.24, 2.55, 0.18, 0.40, tag="shelf")
    for k in range(2):
        with c.at(0.06, Dp - 0.6 - 0.9 * k, 0.0):
            toy_chest(n, w=0.70, d=0.42, seed=seed + k)
        c.rect(0.27, Dp - 0.6 - 0.9 * k, 0.21, 0.36, tag="chest")
    # the children's table with four low stools, and two bean bags by the rug
    tu, tv = 0.68 * W, 0.42 * Dp
    with c.at(tu, tv, 0.0):
        FU.table_round(n, r=0.45, h=0.52, top="Hull", edge="Accent")
    c.rect(tu, tv, 0.45, 0.45, tag="table")
    for k in range(4):
        a = 45.0 + 90.0 * k
        su, sv = tu + 0.78 * cos(radians(a)), tv + 0.78 * sin(radians(a))
        with c.at(su, sv, 0.0):
            n.vcyl(0, 0, F, F + 0.30, 0.15, 0.13, seg=10, mat=("Accent", "Cushion", "Fabric", "Glow")[k], cap0=False)
            n.cap_disc(0.13, F + 0.30, "Hull", seg=10)
        c.rect(su, sv, 0.16, 0.16, tag="stool")
    for k in range(2):
        bu, bv = 0.12 * W + 0.75 * k, 0.16 * Dp + 0.25
        with c.at(bu, bv, 30.0 * k):
            n.sphere((0, 0, F + 0.22), 0.36, ("Fabric", "Cushion")[k], seg=10, rings=5, smooth=True, scale=(1, 1, 0.62))
        c.rect(bu, bv, 0.36, 0.36, tag="beanbag")
    return [c.centre()]


def exec_commons(plan, c, seed):
    """Residents' lounge: a bar counter with stools, armchairs round a table, shelves and plants."""
    W, Dp = c.W, c.Dp
    n = plan.n
    wall(c, 0.0, 0.0, W, 0.0, gaps=[(0.5 * W, 2.4)])
    c.floor(0.05, W - 0.05, 0.05, Dp - 0.05, "Wood")
    for k in (-1, 1):
        FU.tall_plant(n, *c.w(0.5 * W + k * 1.55, 0.42), seed=seed + 5 + k)
        c.rect(0.5 * W + k * 1.55, 0.42, 0.27, 0.27, tag="plant")
    bl = min(2.6, W - 2.0)
    with c.at(0.5 * W, Dp - 0.06, -90.0):
        bbox(n, 0.0, 0.55, -bl / 2, bl / 2, F, F + 1.02, "HullDark", bevel=0.015)
        bbox(n, -0.02, 0.60, -bl / 2 - 0.02, bl / 2 + 0.02, F + 1.02, F + 1.06, "Wood", bevel=0.01)
        plate_x(n, 0.551, -bl / 2 + 0.05, bl / 2 - 0.05, F + 0.86, F + 0.90, "LightStrip")
        for k in range(5):
            yy = -bl / 2 + 0.25 + (bl - 0.5) * k / 4
            n.vcyl(0.20, yy, F + 1.06, F + 1.06 + 0.22, 0.04, seg=8, mat=("Glass", "Accent", "Frost")[k % 3])
    c.rect(0.5 * W, Dp - 0.06 - 0.30, bl / 2 + 0.02, 0.31, 0.0, tag="bar")
    for k in range(3):
        with c.at(0.5 * W - bl / 2 + 0.4 + (bl - 0.8) * k / 2, Dp - 1.1, 0.0):
            FU.stool(n)
        c.rect(0.5 * W - bl / 2 + 0.4 + (bl - 0.8) * k / 2, Dp - 1.1, 0.2, 0.2, tag="stool")
    tu, tv = 0.30 * W, 0.42 * Dp
    with c.at(tu, tv, 0.0):
        FU.table_round(n, r=0.42, h=0.46, top="Wood")
    c.rect(tu, tv, 0.42, 0.42, tag="ctable")
    for k, a in enumerate((0.0, 120.0, 240.0)):
        au, av = tu + 1.05 * cos(radians(a)), tv + 1.05 * sin(radians(a))
        with c.at(au, av, a + 180.0):
            armchair(n, fabric=("Cushion", "Fabric", "Cushion")[k])
        c.rect(au, av, 0.42, 0.47, a + 180.0, tag="armchair")
    FU.tall_plant(n, *c.w(W - 0.45, Dp - 0.45), seed=seed)
    c.rect(W - 0.45, Dp - 0.45, 0.27, 0.27, tag="plant")
    FU.tall_plant(n, *c.w(0.45, Dp - 0.45), seed=seed + 4)
    c.rect(0.45, Dp - 0.45, 0.27, 0.27, tag="plant")
    if W > 6.5:
        # a wide lounge: a second group (sofa against the side wall, coffee table, rug)
        us, vs = W - 0.54, 0.45 * Dp
        with c.at(us, vs, 180.0):
            FU.sofa(n, n=3, seat_w=0.62, fabric="Fabric")
        c.rect(us - 0.03, vs, 0.42, 1.08, 180.0, tag="sofa")
        with c.at(us - 1.05, vs, 180.0):
            FU.coffee_table(n, hx=0.32, hy=0.55)
            FU.rug_rect(n, 1.05, 1.25, mat="RugLight", border="Accent")
        c.rect(us - 1.05, vs, 0.32, 0.55, 180.0, tag="ctable")
    else:
        with c.at(W - 0.06, 0.5 * Dp, 180.0):
            FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed)
        c.rect(W - 0.24, 0.5 * Dp, 0.18, 0.40, tag="shelf")
    return [c.centre()]


# --------------------------------------------------------------------------------------
# The residence tube
# --------------------------------------------------------------------------------------
TUBE_PORTS = {1: (0.0, 180.0, 90.0, 270.0), 2: (0.0, 180.0, 90.0, 235.0, 305.0),
              3: (0.0, 180.0, 60.0, 120.0, 240.0, 300.0)}      # M / L / XL: 4 / 5 / 6 (V5_DESIGN 7)


def residence_tube(rm):
    s = rm.size
    exe = getattr(rm, "variant", "family") == "executive"
    plan = Plan(rm)
    plan.v5_walls = set()
    IK.build_floor_v3(rm, "panel", "grid", grid=1.2, edge_band=0.62)
    n = plan.n
    var = rm.bdef.get("variants", {}).get("executive" if exe else "family", {})
    units = int(var.get("units", [2, 2, 3, 4] if not exe else [1, 1, 2, 3])[s])
    r_o = plan.r_max - 0.05
    yb = 0.70 * r_o
    xe = sqrt(r_o * r_o - yb * yb)
    per_side = 1 if (s == 1 or (exe and s == 2)) else 2
    W = 2.0 * xe / per_side
    Dp = yb - HS
    cells = []
    for k in range(per_side):                         # +Y side, then -Y side (turned 180 deg)
        cells.append(Cell(plan, -xe + W * k, HS, 0.0, W, Dp))
    for k in range(per_side):
        cells.append(Cell(plan, xe - W * k, -HS, 180.0, W, Dp))
    # the unit order: family L puts the commons last (-Y, the far cell); executive M / XL likewise
    lights = []
    for i, c in enumerate(cells):
        seed = 11 * i + 3 * s
        if i < units:
            if exe:
                lights += exec_unit(plan, c, s + 1, i, seed)
            else:
                lights += family_unit(plan, c, s + 1, i, seed)
        else:
            lights += (exec_commons if exe else family_commons)(plan, c, seed)
        # cell boundary walls (street wall drawn by the layout)
        wall(c, 0.0, c.Dp, c.W, c.Dp)
        wall(c, 0.0, 0.0, 0.0, c.Dp)
        wall(c, c.W, 0.0, c.W, c.Dp)
    # the street: a runner with Accent edge lines, from porch to porch
    for sy in (-1, 1):
        FU.floor_line(n, -r_o + 0.3, sy * (HS - 0.18), r_o - 0.3, sy * (HS - 0.18), w=0.06, mat="LightStrip")
    plate_z(n, F + 0.003, -r_o + 0.3, r_o - 0.3, -HS + 0.24, HS - 0.24, "FloorDark")
    _yards(plan, cells, units, exe, yb, s)
    _entries(plan, r_o, xe, yb, s)
    # the ring wall items (behind the aisle ring)
    pattern = ["planter", "shelf", "notice", "lockers", "cab_plant", "tap", "aiposter", "cab_books", "planter",
               "wardrobe", "filmposter"]
    plan.wall_items(pattern, IR.wall_set(plan), open_every=3, seed=5 + s, depth_of=IR.DEPTHS,
                    open_kinds=("poster", "aiposter", "notice", "plant", "panel", "filmposter"))
    # link ports (SIM anchors_spec): the porch doors at 0 / 180 deg and the side doors; on the wall line, facing out.
    # The model takes a doorway at any angle (no blocked angles); these are where the design puts them.
    Rw = rm.R - 0.32
    for a_ in TUBE_PORTS[s]:
        plan.rm.anchor("Door_%d" % TUBE_PORTS[s].index(a_), (Rw * cos(radians(a_)), Rw * sin(radians(a_)), F), a_)
    pts = [(0.0, 0.0)] + lights
    for i, (x, y) in enumerate(pts):
        rm.anchor("Light_%d" % i, (x, y, 2.30), 0.0)
    plan.aisles()
    patch, where = IR.empty_patch(plan)
    plan.v4_patch = patch
    rm.info = dict(units=units, cells=len(cells), cell_w=round(W, 2), cell_d=round(Dp, 2), variant=rm.variant,
                   patch_at=[round(q, 2) for q in where] if where else None)


def _yards(plan, cells, units, exe, yb, s):
    """Critic 27 fix 1: the floor behind each cell (between its back wall and the aisle ring) is that unit's yard:
    a lawn (family) or a wood deck (executive), planters on the borders, a patio table or loungers, a tree, and a
    sandpit for the children.  Commons cells get a shared play yard or a garden bench."""
    n = plan.n
    ry = plan.r_max - 0.06
    borders = set()
    for i, c in enumerate(cells):
        sg = 1.0 if c.rot == 0.0 else -1.0
        xa, xb = sorted((c.w(0.0, 0.0)[0], c.w(c.W, 0.0)[0]))
        y0 = yb + 0.06

        def h(x):
            return sqrt(max(0.0, ry * ry - x * x))
        xs = [xa + (xb - xa) * k / 12 for k in range(13)]
        top = [(x, max(y0 + 0.01, h(x))) for x in xs]
        poly = [(xa, sg * y0), (xb, sg * y0)] + [(x, sg * y) for x, y in reversed(top)]
        unit = i < units
        mat = ("Wood" if exe else "Plant") if unit else ("RugLight" if not exe else "Wood")
        n.plate(poly, F + 0.005, mat)
        # planter borders between neighbouring yards
        for xbd in (xa, xb):
            key = round(xbd, 2), sg
            if key in borders or abs(abs(xbd) - max(abs(xa), abs(xb))) < 1e-3 and abs(xbd) > 0.5:
                continue
            borders.add(key)
            L = h(xbd) - y0 - 0.5
            if L > 0.9:
                with n.at(T(xbd, sg * (y0 + 0.1 + L / 2), 0.0), RZ(90.0)):
                    planter_box(n, L, d=0.40, seed=i + 3)
                plan.rect(xbd, sg * (y0 + 0.1 + L / 2), 0.20, L / 2, 0.0, tag="planter")
        # the deep end of the yard (nearest the tube's middle)
        xd = min(max(0.0, xa), xb)
        dirx = 1.0 if xd <= xa + 1e-6 else -1.0          # from the deep end into the yard
        dep = lambda x: h(x) - y0
        # patio (units): a table and two chairs, or two loungers (executive); a pendant-free garden lamp
        xt = xd + dirx * 1.35
        if dep(xt) > 1.5:
            yt = y0 + 0.5 * dep(xt)
            if unit and not exe:
                with n.at(T(xt, sg * yt, 0.0)):
                    FU.table_round(n, r=0.38, h=0.72, top="Wood", edge="Accent")
                plan.rect(xt, sg * yt, 0.38, 0.38, tag="table")
                for k in (-1, 1):
                    cx_ = xt + k * 0.72
                    with n.at(T(cx_, sg * yt, 0.0), RZ(0.0 if k < 0 else 180.0)):
                        FU.chair(n, seat="Fabric")
                    plan.rect(cx_, sg * yt, 0.25, 0.24, tag="seat")
            elif unit:
                for k in (-1, 1):
                    lx = xt + k * 0.45
                    with n.at(T(lx, sg * yt, 0.0), RZ(90.0 * sg)):
                        bbox(n, -0.30, 0.30, -0.85, 0.85, F, F + 0.26, "Frame", bevel=0.02)
                        bbox(n, -0.28, 0.28, -0.78, 0.60, F + 0.26, F + 0.36, "Cushion", bevel=0.03)
                        with n.at(T(0.0, 0.62, F + 0.30), RX(35.0)):
                            bbox(n, -0.28, 0.28, 0.0, 0.08, 0.0, 0.52, "Cushion", bevel=0.03)
                    plan.rect(lx, sg * yt, 0.30, 0.85, 0.0, tag="lounger")
                with n.at(T(xt, sg * (yt - 1.1), 0.0)):
                    FU.table_round(n, r=0.25, h=0.45, top="Wood", edge="Frame")
                plan.rect(xt, sg * (yt - 1.1), 0.25, 0.25, tag="table")
            else:
                with n.at(T(xt, sg * yt, 0.0), RZ(-90.0 * sg)):
                    bench(n, L=1.4)
                plan.rect(xt, sg * yt, 0.72, 0.24, 0.0, tag="bench")
        # a sandpit (family units and the family commons) further along, if the yard is deep enough there
        xs_ = xd + dirx * 3.1
        if not exe and dep(xs_) > 1.5 and xa + 0.8 < xs_ < xb - 0.8:
            ys_ = y0 + 0.5 * dep(xs_) - 0.05
            with n.at(T(xs_, sg * ys_, 0.0)):
                for (x0_, x1_, y0_, y1_) in ((-0.65, 0.65, -0.55, -0.47), (-0.65, 0.65, 0.47, 0.55),
                                             (-0.65, -0.57, -0.47, 0.47), (0.57, 0.65, -0.47, 0.47)):
                    bbox(n, x0_, x1_, y0_, y1_, F, F + 0.20, "Accent", mats={"-z": None})
                plate_z(n, F + 0.12, -0.57, 0.57, -0.47, 0.47, "Soil")
                n.sphere((0.25, 0.1, F + 0.20), 0.09, "Accent", seg=8, rings=4)
                bbox(n, -0.35, -0.15, -0.20, 0.0, F + 0.14, F + 0.24, "Fabric")
            plan.rect(xs_, sg * ys_, 0.65, 0.55, tag="sandpit")
        elif exe and unit and dep(xd + dirx * 3.0) > 1.3:
            px_ = xd + dirx * 3.0
            FU.pot_plant(n, px_, sg * (y0 + 0.45), r=0.22, h=0.44, s=1.0, seed=i + 7)
            plan.rect(px_, sg * (y0 + 0.45), 0.24, 0.24, tag="plant")
        # a tree at the deep end, against the back wall
        tx_ = xd + dirx * 2.35
        if dep(tx_) > 1.2 and xa + 0.4 < tx_ < xb - 0.4:
            FU.tall_plant(n, tx_, sg * (y0 + 0.40), seed=i + 11)
            plan.rect(tx_, sg * (y0 + 0.40), 0.27, 0.27, tag="plant")


def _gardens_unused(plan, cells, r_o, yb, xe, s):
    """Behind the cells: planter strips on the back walls and benches facing them."""
    n = plan.n
    for sg in (1, -1):
        y_p = sg * (yb + 0.06 + 0.24)
        L = 2.0 * sqrt(max(0.0, (r_o - 0.1) ** 2 - (abs(y_p) + 0.24) ** 2)) - 0.4
        if L < 1.2:
            continue
        nseg = max(1, int(L / 2.6))
        seglen = L / nseg
        for k in range(nseg):
            x = -L / 2 + seglen * (k + 0.5)
            with n.at(T(x, y_p, 0.0)):
                planter_box(n, seglen - 0.5, d=0.46, seed=k + (7 if sg > 0 else 17))
            plan.rect(x, y_p, (seglen - 0.5) / 2, 0.23, 0.0, tag="planter")
        # benches in the widest part of the strip, facing the planters
        y_b = sg * (yb + 1.30)
        if abs(y_b) + 0.3 < r_o - 0.2:
            half = sqrt(max(0.0, (r_o - 0.3) ** 2 - (abs(y_b) + 0.25) ** 2))
            nb = 1 if half < 3.0 else 2
            for k in range(nb):
                x = (0.0 if nb == 1 else (-0.45 + 0.9 * k) * half)
                with n.at(T(x, y_b, 0.0), RZ(-90.0 * sg)):
                    bench(n, L=1.4)
                plan.rect(x, y_b, 0.72, 0.24, 0.0, tag="bench")
                FU.tall_plant(n, x + 1.1, y_b, seed=3 + k)
                plan.rect(x + 1.1, y_b, 0.27, 0.27, tag="plant")


def _entries(plan, r_o, xe, yb, s):
    """At each street end (the porch doors): a door mat, shoe benches against the end cells, mail lockers, plants;
    the corners between the street and the end cells are lawns (critic 27 fix 1)."""
    n = plan.n
    ry = plan.r_max - 0.06
    for sx in (1, -1):
        for sy in (1, -1):
            yl0 = HS + 0.45
            xo = sqrt(max(0.0, ry * ry - yl0 * yl0))
            if xo < xe + 0.5:
                continue
            pts = [(xe + 0.06, yl0), (xo, yl0)]
            a0 = atan2(yl0, xo)
            a1 = atan2(sqrt(max(0.0, ry * ry - (xe + 0.06) ** 2)), xe + 0.06)
            for k in range(1, 9):
                a_ = a0 + (a1 - a0) * k / 8
                pts.append((ry * cos(a_), ry * sin(a_)))
            n.plate([(sx * x, sy * y) for x, y in pts], F + 0.005, "Plant")
            # a tree and a planter in the corner
            tx, ty = xe + 0.55 + 0.35 * (xo - xe - 0.5), yl0 + 0.55
            if hypot(tx, ty) < ry - 0.4:
                FU.tall_plant(n, sx * tx, sy * ty, seed=int(21 + 3 * sx + sy))
                plan.rect(sx * tx, sy * ty, 0.27, 0.27, tag="plant")
    for sx in (1, -1):
        mx = sx * (r_o - 1.2)
        with n.at(T(mx, 0.0, 0.0)):
            FU.rug_rect(n, 0.85, 0.75, mat="FloorDark", border="Accent")
        for sy in (1, -1):
            ly = sy * (HS + 3.3)
            if abs(ly) + 0.7 < yb - 0.05:
                with n.at(T(sx * (xe + 0.06), ly, 0.0), RZ(0.0 if sx > 0 else 180.0)):
                    FU.wi_lockers(n, w=1.2, d=0.40, h=1.20, n=4)
                plan.rect(sx * (xe + 0.27), ly, 0.21, 0.60, 0.0, tag="lockers")
    for sx in (1, -1):
        for sy in (1, -1):
            # against the end wall of the end cell, facing out along the street
            x = sx * (xe + 0.30)
            y = sy * (HS + 1.0)
            if hypot(x + sx * 0.5, y) > r_o - 0.3:
                continue
            with n.at(T(x, y, 0.0), RZ(0.0 if sx > 0 else 180.0)):
                bench(n, L=1.2)
                bbox(n, -0.18, -0.02, -0.55, 0.55, F + 0.95, F + 1.00, "Frame")
                for k in range(4):
                    n.vcyl(-0.08, -0.45 + 0.3 * k, F + 1.00, F + 1.12, 0.012, seg=5, mat="Metal", cap0=False)
            plan.rect(x, y, 0.24, 0.62, 0.0, tag="bench")
            if r_o - xe > 2.6:
                # a long entry: tall plants flanking the street before the porch
                qx, qy = sx * (xe + 1.3), sy * (HS + 0.45)
                FU.tall_plant(n, qx, qy, seed=int(9 + sx + 3 * sy))
                plan.rect(qx, qy, 0.27, 0.27, tag="plant")
            px, py = sx * (xe + 0.45), sy * (HS + 2.4)
            if hypot(px, py) < r_o - 0.45:
                FU.pot_plant(n, px, py, r=0.22, h=0.44, s=1.0, seed=int(4 + sx + 2 * sy))
                plan.rect(px, py, 0.23, 0.23, tag="plant")


INTERIORS = {
    "residence_tube": residence_tube,
}
