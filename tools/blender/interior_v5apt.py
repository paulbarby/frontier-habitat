"""Frontier Habitat 5.0 - ART-HAB: the apartment block interiors (docs/V5_DESIGN.md section 7), three floors.

Floor k's furniture is the object F<k>_Interior (floor 0: Interior), built at z = k * 3.6.  Every anchor carries its
floor in its height: z = k * 3.6 + 0.14 (floor top).  Anchor numbers run over the whole building:

  Bed    floor 0 unit i: 4i .. 4i+3 (parents 2, lower bunk, upper bunk) | floor 1 unit i: 20+4i .. 23+4i |
         penthouse p: 40+4p .. 43+4p (master 2, bedroom 2, bedroom 3)
  Seat   floor 0 unit i: i (dining) | floor 1 unit i: 5+i | penthouse p: 10+3p (dining), 11+3p, 12+3p (sofa)
  Stand  0 mail wall (floor 0), 1 laundry (floor 0), 2 laundry (floor 1), 3 hobby bench (floor 1),
         4, 5 penthouse kitchens
  Unit_<floor>_<i>  the unit doors;  Lift_<floor>  in front of the lift;  Door_<i>  the 6 link ports (floor 0)
Plan and radii: rooms_v5apt.py.
"""
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, pi, ceil, asin

import rooms_kit as K
import interior_kit as IK
import interior_furniture as FU
import interior_rooms as IR
import interior_v5 as V5
import rooms_v5apt as A
from rooms_kit import T, RX, RY, RZ, FLOOR_Z, WALL_TOP
from interior_kit import F, Plan, bbox, plate_x, plate_y, plate_z, SEAT_BACK, BED_BACK, BED_Z
from interior_v5 import Cell, wall

H = A.H


class FloorPlan(Plan):
    """A Plan for floor k >= 1: its own footprints and part (F<k>_Interior); anchors lifted to the floor."""

    def __init__(self, rm, k, count):
        prev = getattr(rm, "plan", None)
        super().__init__(rm)
        rm.plan = prev
        self.k = k
        self.z0 = H * k
        self.n = K.P("F%d_Interior" % k)
        rm.extra_parts.append(self.n)
        self.count = count
        self.v5_walls = set()

    def anchor(self, kind, x, y, yaw, z=F):
        Plan.anchor(self, kind, x, y, yaw, z + self.z0)

    def lamp(self, x, y, z):
        Plan.lamp(self, x, y, z + self.z0)


def near(g, ref):
    """The angle g (deg) moved by whole turns to within 180 deg of ref."""
    while g < ref - 180.0:
        g += 360.0
    while g > ref + 180.0:
        g -= 360.0
    return g


def pol(r, a):
    return (r * cos(radians(a)), r * sin(radians(a)))


def ident(plan):
    return Cell(plan, 0.0, 0.0, 0.0, 0.0, 0.0)


def pc(plan, r, a):
    """A frame at the polar point (r, a): local +v radial out, +u tangential clockwise."""
    x, y = pol(r, a)
    return Cell(plan, x, y, a - 90.0, 0.0, 0.0)


def room_cell(plan, a_lo, a_hi, rb, r_out, margin=0.12):
    """The largest useful rectangle of the sector room (a_lo..a_hi, rb..r_out): +v radial out along the bisector,
    u = 0 on the counter-clockwise side (a_hi), u = W on the clockwise side (a_lo)."""
    am = 0.5 * (a_lo + a_hi)
    half = radians(0.5 * (a_hi - a_lo))
    W = 2.0 * rb * sin(half) - 2.0 * margin
    Dp = sqrt(max(0.0, (r_out - margin) ** 2 - (W / 2) ** 2)) - rb
    rot = am - 90.0
    ox = rb * cos(radians(am)) - (W / 2) * cos(radians(rot))
    oy = rb * sin(radians(am)) - (W / 2) * sin(radians(rot))
    return Cell(plan, ox, oy, rot, W, Dp)


def radial_wall(plan, a, r0, r1, gaps=()):
    """A partition along the radius at angle a from r0 to r1; gaps [(r, width)]."""
    x0, y0 = pol(r0, a)
    x1, y1 = pol(r1, a)
    wall(ident(plan), x0, y0, x1, y1, gaps=[(r - r0, w) for r, w in gaps])


def arc_wall(plan, r, a0, a1, gaps=(), piece=1.4):
    """A partition along the circle r from a0 to a1 (deg, a0 < a1) in straight pieces; gaps [(angle, width_m)]."""
    cuts = sorted((ga - degrees(w / 2.0 / r), ga + degrees(w / 2.0 / r)) for ga, w in gaps)
    spans, a = [], a0
    for g0, g1 in cuts:
        if g1 < a0 or g0 > a1:
            continue
        if g0 > a + 0.05:
            spans.append((a, g0))
        a = max(a, g1)
    if a1 > a + 0.05:
        spans.append((a, a1))
    c0 = ident(plan)
    for s0, s1 in spans:
        n = max(1, int(ceil(radians(s1 - s0) * r / piece)))
        for k in range(n):
            t0, t1 = s0 + (s1 - s0) * k / n, s0 + (s1 - s0) * (k + 1) / n
            (xa, ya), (xb, yb) = pol(r, t0), pol(r, t1)
            wall(c0, xa, ya, xb, yb, posts=False)
    for g0, g1 in cuts:
        for g in (g0, g1):
            if a0 < g < a1:
                x, y = pol(r, g)
                with plan.n.at(T(x, y, 0.0), RZ(g)):
                    bbox(plan.n, -0.075, 0.075, -0.035, 0.035, F, F + V5.WALL_H + 0.05, "Frame", mats={"-z": None})


def sector_floor(plan, r0, r1, a0, a1, mat, z=F + 0.004, step=6.0):
    n = plan.n
    k = max(1, int(ceil((a1 - a0) / step)))
    for i in range(k):
        t0, t1 = a0 + (a1 - a0) * i / k, a0 + (a1 - a0) * (i + 1) / k
        p = [pol(r0, t0), pol(r1, t0), pol(r1, t1), pol(r0, t1)]
        n.quad((p[0][0], p[0][1], z), (p[1][0], p[1][1], z), (p[2][0], p[2][1], z), (p[3][0], p[3][1], z), mat)


def ring_floor(plan, r0, r1, mat, z=F + 0.004, seg=72):
    plan.n.lathe_a([(r1, z), (r0, z)], [360.0 * (k + 0.5) / seg for k in range(seg)], lambda k, i: mat,
                   smooth=False)


def ring_line(plan, r, w=0.06, mat="LightStrip", z=F + 0.006, seg=72):
    plan.n.lathe_a([(r + w / 2, z), (r - w / 2, z)], [360.0 * (k + 0.5) / seg for k in range(seg)],
                   lambda k, i: mat, smooth=False)


# --------------------------------------------------------------------------------------
# The core: lift shaft, spiral stair, core wall with two openings
# --------------------------------------------------------------------------------------
LIFT_X = (0.0, 1.8)
STAIR_C, STAIR_R = (-1.3, 0.0), 1.1


def core(rm, plan, k, top):
    """Floor k's core.  Below the cut in plan.n (furniture), above it in `top` (absolute z; Roof for floor 0,
    F<k>_WallTop above)."""
    n = plan.n
    z0 = H * k
    # core wall: two openings (lift at 0 deg, stair at 180 deg)
    A._ring_wall(n, A.R_CORE, F, V5.WALL_H, [F, F + 0.10, V5.WALL_H - 0.04, V5.WALL_H],
                 lambda a, b: "HullDark" if b <= F + 0.11 else ("Hull" if b <= V5.WALL_H - 0.03 else "Frame"),
                 seg=40, thick=0.12, gaps=[(0.0, 1.6), (180.0, 1.3)])
    A._ring_wall(top, A.R_CORE, z0 + WALL_TOP, z0 + H - 0.02, [z0 + WALL_TOP, z0 + 2.3, z0 + 2.55, z0 + H - 0.02],
                 lambda a, b: "Hull" if b <= z0 + 2.31 else ("Accent" if b <= z0 + 2.56 else "Hull"),
                 seg=40, thick=0.12, gaps=[(0.0, 1.6), (180.0, 1.3)])
    # lift shaft: four Frame posts, frosted glass on three sides, doors facing +X
    x0, x1 = LIFT_X
    for (px, py) in ((x0, -0.9), (x0, 0.9), (x1, -0.9), (x1, 0.9)):
        bbox(n, px - 0.05, px + 0.05, py - 0.05, py + 0.05, F, V5.WALL_H, "Frame", mats={"-z": None})
        bbox(top, px - 0.05, px + 0.05, py - 0.05, py + 0.05, z0 + WALL_TOP, z0 + H, "Frame", mats={"-z": None})
    for (a0_, a1_, b0_, b1_) in ((x0, x0 + 0.02, -0.85, 0.85), (x0, x1, -0.9, -0.88), (x0, x1, 0.88, 0.9)):
        bbox(n, a0_, a1_, b0_, b1_, F, V5.WALL_H - 0.02, "Frost")
        bbox(top, a0_, a1_, b0_, b1_, z0 + WALL_TOP, z0 + H - 0.05, "Frost")
    for sy in (-1, 1):                                    # the door leaves (closed), with a green strip
        bbox(n, x1 - 0.03, x1, sy * 0.02 if sy > 0 else -0.85, 0.85 if sy > 0 else -0.02, F, V5.WALL_H - 0.02,
             "Metal")
        bbox(top, x1 - 0.03, x1, sy * 0.02 if sy > 0 else -0.85, 0.85 if sy > 0 else -0.02, z0 + WALL_TOP,
             z0 + 2.3, "Metal")
    bbox(top, x1 - 0.02, x1 + 0.02, -0.5, 0.5, z0 + 2.4, z0 + 2.55, "Screen")
    plate_z(n, F + 0.01, x0 + 0.05, x1 - 0.05, -0.85, 0.85, "FloorDark")
    plan.rect(0.5 * (x0 + x1), 0.0, 0.5 * (x1 - x0), 0.95, tag="lift")
    # spiral stair: 16 steps per floor round a post; the steps under the cut here, the rest above
    cx, cy = STAIR_C
    n.vcyl(cx, cy, F, V5.WALL_H, 0.09, seg=10, mat="Frame")
    top.vcyl(cx, cy, z0 + WALL_TOP, z0 + H, 0.09, seg=10, mat="Frame")
    for s in range(16):
        a = 180.0 - 22.5 * s
        zt = F + 0.225 * (s + 1)
        part, off = (n, 0.0) if zt <= V5.WALL_H else (top, z0)
        with part.at(T(cx, cy, off), RZ(a)):
            bbox(part, 0.10, STAIR_R, -0.20, 0.20, zt - 0.05, zt, "Hull" if s % 2 else "Frame", bevel=0.01)
            bbox(part, STAIR_R - 0.04, STAIR_R, -0.03, 0.03, zt, zt + 0.85 if zt + 0.85 <= V5.WALL_H or part is top
                 else V5.WALL_H, "Metal")
    plan.circle(cx, cy, STAIR_R + 0.05, tag="stair")
    plan.circle(0.0, 0.0, A.R_CORE + 0.07, tag="core")        # the core counts as built floor (density)
    # lift anchor (in front of the doors, facing them)
    plan.rm.anchor("Lift_%d" % k, (A.R_CORE + 0.75, 0.0, z0 + F), 180.0)
    ring_floor(plan, A.R_CORE + 0.06, A.R_LOBBY - 0.05, "Floor")
    ring_line(plan, A.R_LOBBY - 0.25)


# --------------------------------------------------------------------------------------
# Shared rooms of floors 0 and 1 (between the spokes, R_LOBBY..R_INNER)
# --------------------------------------------------------------------------------------
def treadmill(p):
    """A treadmill, the runner faces +X (1.8 x 0.8)."""
    bbox(p, -0.9, 0.7, -0.38, 0.38, F, F + 0.18, "HullDark", bevel=0.02)
    plate_z(p, F + 0.182, -0.8, 0.6, -0.26, 0.26, "Rubber")
    for sy in (-1, 1):
        p.beam((0.62, sy * 0.34, F + 0.18), (0.72, sy * 0.34, F + 1.25), 0.05, 0.05, "Frame")
    bbox(p, 0.64, 0.80, -0.38, 0.38, F + 1.18, F + 1.30, "Frame")
    plate_x(p, 0.64, -0.25, 0.25, F + 1.20, F + 1.28, "Screen", facing=-1)


def weight_bench(p):
    bbox(p, -0.6, 0.6, -0.16, 0.16, F + 0.36, F + 0.46, "Cushion", bevel=0.03)
    for sx in (-0.45, 0.45):
        bbox(p, sx - 0.04, sx + 0.04, -0.14, 0.14, F, F + 0.36, "Frame", mats={"-z": None})
    for sy in (-1, 1):
        bbox(p, 0.35, 0.40, sy * 0.40 - 0.03, sy * 0.40 + 0.03, F, F + 1.10, "Frame", mats={"-z": None})
    p.cyl((0.38, -0.75, F + 1.05), (0.38, 0.75, F + 1.05), 0.018, seg=6, mat="Metal")
    for sy in (-1, 1):
        p.cyl((0.38, sy * 0.58, F + 1.05), (0.38, sy * 0.66, F + 1.05), 0.16, seg=12, mat="HullDark")


def bike(p, col="Accent"):
    """A bicycle on its stand, along X."""
    for x in (-0.52, 0.52):
        with p.at(T(x, 0.0, F + 0.34), RX(90.0)):
            p.lathe([(0.34, -0.02), (0.34, 0.02), (0.30, 0.02), (0.30, -0.02)], "Rubber", seg=16, smooth=False)
    p.beam((-0.52, 0.0, F + 0.34), (0.0, 0.0, F + 0.62), 0.04, 0.04, col)
    p.beam((0.0, 0.0, F + 0.62), (0.52, 0.0, F + 0.34), 0.04, 0.04, col)
    p.beam((-0.15, 0.0, F + 0.34), (0.0, 0.0, F + 0.62), 0.04, 0.04, col)
    p.beam((-0.52, 0.0, F + 0.34), (-0.15, 0.0, F + 0.34), 0.04, 0.04, col)
    bbox(p, -0.22, -0.02, -0.07, 0.07, F + 0.68, F + 0.73, "HullDark")
    p.beam((0.40, -0.25, F + 0.86), (0.40, 0.25, F + 0.86), 0.03, 0.03, "Frame")


def shared_room(plan, kind, a_lo, a_hi, seed):
    """A shared room between two spokes: doors on the lobby and on the street at its bisector."""
    am = 0.5 * (a_lo + a_hi)
    radial_wall(plan, a_lo, A.R_LOBBY, A.R_INNER)
    radial_wall(plan, a_hi, A.R_LOBBY, A.R_INNER)
    arc_wall(plan, A.R_LOBBY, a_lo, a_hi, gaps=[(am, 1.1)])
    arc_wall(plan, A.R_INNER, a_lo, a_hi, gaps=[(am, 1.2)])
    mats = dict(lobby="Wood", laundry="Frost", gym="Rubber", play="CushionLight", store="FloorDark", library="Wood",
                hobby="Floor", lounge="Wood")
    sector_floor(plan, A.R_LOBBY + 0.06, A.R_INNER - 0.06, a_lo + 0.8, a_hi - 0.8, mats.get(kind, "Floor"))
    c = room_cell(plan, a_lo, a_hi, A.R_LOBBY + 0.25, A.R_INNER)
    n = plan.n
    W, Dp = c.W, c.Dp
    uL, uR = 0.75, W - 0.75            # the two sides; the middle (the door line) stays clear
    if kind == "lobby":
        for k, v in enumerate((0.9, 2.1)):
            with c.at(uL - 0.1, v, 0.0):
                V5.armchair(n, fabric=("Cushion", "Fabric")[k])
            c.rect(uL - 0.1, v, 0.42, 0.47, 0.0, tag="armchair")
        with c.at(uL + 0.75, 1.5, 0.0):
            FU.table_round(n, r=0.30, h=0.46, top="Wood")
        c.rect(uL + 0.75, 1.5, 0.30, 0.30, tag="ctable")
        with c.at(uR + 0.55, 1.5, 180.0):
            FU.wi_lockers(n, w=1.6, d=0.40, h=1.20, n=6)
        c.rect(uR + 0.35, 1.5, 0.21, 0.80, tag="lockers")
        c.anchor("Stand", uR + 0.35 - 0.21 - 0.45, 1.5, 0.0)
        FU.tall_plant(n, *c.w(uR + 0.3, Dp - 0.2), seed=seed)
        c.rect(uR + 0.3, Dp - 0.2, 0.27, 0.27, tag="plant")
    elif kind == "laundry":
        for k in range(3):
            with c.at(0.05, 0.5 + 0.66 * k, 0.0):
                V5.washer(n, seed=k)
            c.rect(0.35, 0.5 + 0.66 * k, 0.31, 0.31, tag="washer")
        with c.at(uR, 1.4, 0.0):
            FU.table_rect(n, 0.35, 0.75, h=0.90, top="Hull")
            for j in range(3):
                bbox(n, -0.25, 0.25, -0.6 + 0.42 * j, -0.3 + 0.42 * j, F + 0.90, F + 0.96 + 0.03 * j,
                     ("Fabric", "CushionLight", "Hull")[j])
        c.rect(uR, 1.4, 0.35, 0.75, tag="counter")
        c.anchor("Stand", uR - 0.35 - 0.45, 1.4, 0.0)
        FU.pot_plant(n, *c.w(uR + 0.2, Dp - 0.1), r=0.18, h=0.36, seed=seed)
        c.rect(uR + 0.2, Dp - 0.1, 0.2, 0.2, tag="plant")
    elif kind == "gym":
        for k, u in enumerate((uL - 0.2, uL + 0.8)):
            with c.at(u, 1.3, 90.0):
                treadmill(n)
            c.rect(u, 1.2, 0.40, 0.90, tag="treadmill")
        with c.at(uR, 1.5, 90.0):
            weight_bench(n)
        c.rect(uR, 1.5, 0.80, 0.62, 90.0, tag="bench")
        with c.at(uR + 0.2, 0.2, 90.0):
            V5.rug_pattern(n, 0.8, 0.5, seed=seed)
    elif kind == "play":
        with c.at(uL + 0.2, 1.4, 90.0):
            V5.play_frame(n, seed=seed)
        c.rect(uL + 0.2, 1.5, 0.45, 1.1, tag="play")
        with c.at(uR, 1.2, 0.0):
            V5.rug_pattern(n, 0.7, 0.9, seed=seed)
        V5.toys(n, *c.w(uR, 1.2), seed=seed, n=7)
        with c.at(uR + 0.35, 2.4, 180.0):
            V5.toy_chest(n, w=0.7, d=0.42, seed=seed)
        c.rect(uR + 0.14, 2.4, 0.21, 0.36, tag="chest")
    elif kind == "store":
        for k in range(3):
            with c.at(uL - 0.25, 0.6 + 0.55 * k, 90.0):
                bike(n, col=("Accent", "Fabric", "Glow")[k])
            c.rect(uL - 0.25, 0.6 + 0.55 * k, 0.12, 0.88, 90.0, tag="bike")
        for k in range(2):
            with c.at(uR + 0.55, 0.9 + 1.1 * k, 180.0):
                FU.wi_rack(n, w=0.9, d=0.42, h=1.25, seed=seed + k)
            c.rect(uR + 0.34, 0.9 + 1.1 * k, 0.21, 0.45, tag="rack")
    elif kind == "library":
        for u in (uL - 0.25, uL + 0.55):
            with c.at(u, Dp + 0.05, -90.0):
                FU.wi_shelf(n, w=0.78, d=0.36, h=1.25, seed=seed + int(u * 10))
            c.rect(u, Dp - 0.13, 0.39, 0.18, tag="shelf")
        for k, v in enumerate((0.8, 1.9)):
            with c.at(uR, v, 180.0):
                V5.armchair(n, fabric=("Fabric", "Cushion")[k])
            c.rect(uR, v, 0.42, 0.47, 180.0, tag="armchair")
        with c.at(uR - 0.2, 2.75, 0.0):
            V5.floor_lamp(n, lamp_cb=IR.lamp_cb(plan, n))
        c.rect(uR - 0.2, 2.75, 0.18, 0.18, tag="lamp")
        with c.at(uL, 1.1, 0.0):
            FU.table_rect(n, 0.45, 0.35, top="Wood")
        c.rect(uL, 1.1, 0.45, 0.35, tag="table")
    elif kind == "hobby":
        with c.at(uR, Dp - 0.8, -90.0):
            FU.workbench(n, w=1.4, d=0.7, seed=seed)
        c.rect(uR, Dp - 0.45, 0.70, 0.35, tag="bench")
        c.anchor("Stand", uR, Dp - 1.2, 90.0)
        with c.at(uL, 1.0, 0.0):
            FU.table_rect(n, 0.6, 0.4, top="Wood")
            for j in range(3):
                bbox(n, -0.4 + 0.3 * j, -0.2 + 0.3 * j, -0.2, 0.2, F + 0.74, F + 0.80, ("Fabric", "Accent", "Glow")[j])
        c.rect(uL, 1.0, 0.6, 0.4, tag="table")
        FU.pot_plant(n, *c.w(uL - 0.3, Dp - 0.1), r=0.18, h=0.36, seed=seed)
        c.rect(uL - 0.3, Dp - 0.1, 0.2, 0.2, tag="plant")
    elif kind == "lounge":
        with c.at(uL - 0.25, 1.5, 0.0):
            FU.sofa(n, n=3, seat_w=0.62, fabric="Fabric")
        c.rect(uL - 0.28, 1.5, 0.42, 1.08, tag="sofa")
        with c.at(uL + 0.8, 1.5, 0.0):
            FU.coffee_table(n, hx=0.3, hy=0.55)
            FU.rug_rect(n, 0.9, 1.2, mat="RugLight", border="Accent")
        c.rect(uL + 0.8, 1.5, 0.3, 0.55, tag="ctable")
        with c.at(uR + 0.55, 1.5, 180.0):
            V5.media_wall(n, w=1.4, seed=seed)
        c.rect(uR + 0.35, 1.5, 0.2, 0.7, tag="media")
    V5.pendant(plan, c, 0.5 * W, 0.5 * Dp, seed) if kind in ("lobby", "library", "lounge") else None
    return c.w(0.5 * W, 0.5 * Dp)


# --------------------------------------------------------------------------------------
# Family units of floors 0 and 1
# --------------------------------------------------------------------------------------
def unit(plan, k, fl, idx, seed):
    rr = A.unit_rooms(k)
    a0, a1 = rr["unit"]
    n = plan.n
    hall, liv, bA, bB = rr["hall"], rr["living"], rr["bedA"], rr["bedB"]
    ham = 0.5 * sum(hall)
    RS, RU = A.R_STREET, A.R_UNIT
    # walls: the street front (unit door), the spoke sides, the room partitions, the back (floor 0)
    arc_wall(plan, RS, a0, a1, gaps=[(ham, V5.DOOR_W)])
    radial_wall(plan, a0, RS, RU)
    radial_wall(plan, a1, RS, RU)
    radial_wall(plan, bA[1], RS, RU, gaps=[(10.5, V5.IDOOR_W)])
    radial_wall(plan, liv[0], RS, RU, gaps=[(10.5, V5.IDOOR_W)])
    radial_wall(plan, bB[0], RS, RU, gaps=[(10.4, V5.IDOOR_W)])
    cBa = room_cell(plan, hall[0], hall[1], 11.62, RU)
    gx, gy = cBa.w(0.55, -0.1)
    arc_wall(plan, 11.4, hall[0], hall[1], gaps=[(near(degrees(atan2(gy, gx)), ham), V5.IDOOR_W)])
    if fl == 0:
        arc_wall(plan, RU, a0, a1, gaps=[(rr["door_out"], 1.2)])
    # floors
    sector_floor(plan, RS + 0.06, RU - 0.06, bA[0] + 0.4, bA[1] - 0.3, "RugLight")
    sector_floor(plan, RS + 0.06, 11.34, hall[0] + 0.3, hall[1] - 0.3, "Floor")
    sector_floor(plan, RS + 0.06, RU - 0.06, liv[0] + 0.3, liv[1] - 0.3, "Wood")
    sector_floor(plan, RS + 0.06, RU - 0.06, bB[0] + 0.3, bB[1] - 0.4, "CushionLight")
    # the bath
    V5._bath(plan, cBa, 0.0, cBa.W, 0.0, cBa.Dp, seed, door="v0")
    # parents' bedroom: two beds to the back wall, a wardrobe by the street wall, a rug, a picture
    cA = room_cell(plan, bA[0], bA[1], 11.5, RU)
    uc = cA.W - 1.72
    V5._bay(plan, cA, uc, cA.Dp - 0.06, 20 * fl + 2 * idx)
    with cA.at(uc, cA.Dp - 2.45, 0.0):
        FU.rug_rect(n, 1.1, 0.32, mat="Cushion", border="Accent")
    w_ = pc(plan, RS + 0.06, bA[0] + 5.5)
    with w_.at(0.0, 0.0, 90.0):
        FU.wi_wardrobe(n, w=0.80, d=0.42, h=1.26)
    w_.rect(0.0, 0.21, 0.40, 0.21, tag="wardrobe")
    # children's room: a bunk to the back wall (no anchor: content beds 2 per unit), a chest, a desk
    cB = room_cell(plan, bB[0], bB[1], 11.0, RU)
    V5._bunk(plan, cB, 0.10 + 0.51, cB.Dp - 0.08 - 1.06, 0.0, seed)       # 2 Beds (lower, upper)
    with cB.at(cB.W - 0.02, cB.Dp - 0.5, 180.0):
        V5.toy_chest(n, w=0.62, d=0.40, seed=seed)
    cB.rect(cB.W - 0.22, cB.Dp - 0.5, 0.21, 0.32, tag="chest")
    with cB.at(cB.W - 0.02, 0.9, 180.0):
        V5.kid_desk(n, seed=seed)
    cB.rect(cB.W - 0.45, 0.9, 0.45, 0.42, tag="desk")
    with cB.at(0.75, 0.9, 0.0):
        V5.rug_pattern(n, 0.5, 0.45, seed=seed)
    # living: kitchenette on the street wall, the family table, a sofa group to the back
    cL = room_cell(plan, liv[0], liv[1], 10.0, RU)
    W, Dp = cL.W, cL.Dp
    ku = 0.5 * W + 0.25
    with cL.at(ku, -0.30, 90.0):
        V5.kitchenette(n, w=2.1, seed=seed)
    cL.rect(ku, 0.0, 1.05, 0.33, tag="counter")
    V5._table(plan, cL, 0.5 * W, 1.9, 0.0, seed, anchors=1)
    V5.pendant(plan, cL, 0.5 * W, 1.9, seed)
    su = W - 1.15
    with cL.at(su, Dp - 0.50, -90.0):
        FU.sofa(n, n=3, seat_w=0.62, fabric="Cushion")
    cL.rect(su, Dp - 0.47, 0.42, 1.08, -90.0, tag="sofa")
    with cL.at(su, Dp - 1.50, 0.0):
        FU.coffee_table(n, hx=0.50, hy=0.28)
        FU.rug_rect(n, 1.2, 0.8, mat="RugLight", border="Accent")
    cL.rect(su, Dp - 1.50, 0.50, 0.28, tag="ctable")
    with cL.at(0.35, Dp - 0.3, 0.0):
        V5.floor_lamp(n, lamp_cb=IR.lamp_cb(plan, n))
    cL.rect(0.35, Dp - 0.3, 0.18, 0.18, tag="lamp")
    # the hall: a coat bench and a plant
    ch = room_cell(plan, hall[0], hall[1], RS + 0.15, 11.34)
    FU.pot_plant(n, *ch.w(ch.W - 0.25, 0.9), r=0.16, h=0.32, s=0.8, seed=seed)
    ch.rect(ch.W - 0.25, 0.9, 0.18, 0.18, tag="plant")
    # the unit door anchor (on the street, facing in)
    x, y = pol(RS, ham)
    plan.rm.anchor("Unit_%d_%d" % (fl, idx), (x, y, H * fl + F), ham)
    return [cL.w(0.5 * W, 0.5 * Dp), cA.w(0.5 * cA.W, 0.5 * cA.Dp), cB.w(0.5 * cB.W, 0.5 * cB.Dp),
            cBa.w(0.5 * cBa.W, 0.5 * cBa.Dp)]


def yard(plan, k, seed):
    """Floor 0: the unit's yard behind its back wall (lawn, planters on the spoke edges, a patio set, a tree)."""
    n = plan.n
    rr = A.unit_rooms(k)
    r0, r1 = A.R_UNIT + 0.12, plan.r_max - 0.06
    dg = A.spoke_delta(0.5 * (r0 + r1))
    a0, a1 = A.SPOKES[k] + dg, A.SPOKES[k] + 72.0 - dg
    sector_floor(plan, r0, r1, a0, a1, "Plant", z=F + 0.005, step=4.0)
    # planter rows along both spoke edges
    L = r1 - r0 - 0.4
    for a in (a0 + 1.2, a1 - 1.2):
        x, y = pol(r0 + 0.2 + L / 2, a)
        with n.at(T(x, y, 0.0), RZ(a)):
            V5.planter_box(n, L, d=0.40, seed=seed + int(a))
        plan.rect(x, y, L / 2, 0.20, a, tag="planter")
    # pot plants flanking the living-room door; a patio table + 2 chairs beside it, a bench and a tree further along
    for s_ in (-1, 1):
        x, y = pol(r0 + 0.45, rr["door_out"] + s_ * 3.4)
        FU.pot_plant(n, x, y, r=0.22, h=0.44, s=1.0, seed=seed + s_)
        plan.rect(x, y, 0.24, 0.24, tag="plant")
    ra = 0.5 * (r0 + r1)
    S = a1 - a0
    for j, (a, what) in enumerate(((rr["door_out"] - 6.5, "patio"), (a0 + 0.36 * S, "bench"),
                                  (a0 + 0.12 * S, "tree"), (a0 + 0.55 * S, "sandpit"), (a1 - 0.07 * S, "tree"),
                                  (a0 + 0.24 * S, "bed"))):
        x, y = pol(ra, a)
        if what == "patio":
            with n.at(T(x, y, 0.0)):
                FU.table_round(n, r=0.38, h=0.72, top="Wood", edge="Accent")
            plan.rect(x, y, 0.38, 0.38, tag="table")
            for s in (-1, 1):
                cx, cy = pol(ra + s * 0.72, a)
                with n.at(T(cx, cy, 0.0), RZ(a + (180.0 if s > 0 else 0.0))):
                    FU.chair(n, seat="Fabric")
                plan.rect(cx, cy, 0.25, 0.24, a, tag="seat")
        elif what == "bench":
            with n.at(T(x, y, 0.0), RZ(a + 180.0)):
                V5.bench(n, L=1.4)
            plan.rect(x, y, 0.24, 0.72, a, tag="bench")
        elif what == "bed":
            with n.at(T(x, y, 0.0), RZ(a + 90.0)):
                V5.planter_box(n, 1.6, d=0.5, seed=seed + 5)
            plan.rect(x, y, 0.8, 0.25, a + 90.0, tag="planter")
        elif what == "tree":
            FU.tall_plant(n, x, y, seed=seed + j)
            plan.rect(x, y, 0.27, 0.27, tag="plant")
        else:
            with n.at(T(x, y, 0.0), RZ(a)):
                for (x0_, x1_, y0_, y1_) in ((-0.55, 0.55, -0.6, -0.52), (-0.55, 0.55, 0.52, 0.6),
                                             (-0.55, -0.47, -0.52, 0.52), (0.47, 0.55, -0.52, 0.52)):
                    bbox(n, x0_, x1_, y0_, y1_, F, F + 0.2, "Accent", mats={"-z": None})
                plate_z(n, F + 0.12, -0.47, 0.47, -0.52, 0.52, "Soil")
                n.sphere((0.2, 0.15, F + 0.2), 0.09, "Fabric", seg=8, rings=4)
            plan.rect(x, y, 0.55, 0.6, a, tag="sandpit")


# --------------------------------------------------------------------------------------
# Penthouses (floor 2)
# --------------------------------------------------------------------------------------
def penthouse(plan, p, seed):
    rr = A.ph_rooms(p)
    n = plan.n
    c0, c1 = rr["unit"]
    RL, R2 = A.R_LOBBY, A.R2 - 0.1
    bath, mast, liv, b2, b3 = rr["bath"], rr["master"], rr["living"], rr["bed2"], rr["bed3"]
    arc_wall(plan, RL, c0, c1, gaps=[(rr["entry"], 1.1)])
    radial_wall(plan, c0, RL, R2)
    radial_wall(plan, c1, RL, R2)
    radial_wall(plan, bath[1], RL, R2, gaps=[(8.0, V5.IDOOR_W)])
    radial_wall(plan, mast[1], RL, R2, gaps=[(5.0, V5.IDOOR_W)])
    radial_wall(plan, liv[1], RL, R2, gaps=[(5.0, V5.IDOOR_W)])
    arc_wall(plan, 5.6, liv[1], c1, gaps=[(0.5 * sum(b2), V5.IDOOR_W), (0.5 * sum(b3), V5.IDOOR_W)])
    radial_wall(plan, b2[1], 5.6, R2)
    sector_floor(plan, RL + 0.06, R2 - 0.06, mast[0] + 0.3, mast[1] - 0.3, "Wood")
    sector_floor(plan, RL + 0.06, R2 - 0.06, liv[0] + 0.3, liv[1] - 0.3, "Wood")
    sector_floor(plan, 5.66, R2 - 0.06, b2[0] + 0.3, b2[1] - 0.3, "RugLight")
    sector_floor(plan, 5.66, R2 - 0.06, b3[0] + 0.3, b3[1] - 0.3, "CushionLight")
    # bath (door from the master bedroom, on the bath's counter-clockwise wall = u0)
    cb = room_cell(plan, bath[0], bath[1], 7.0, R2)
    V5._bath(plan, cb, 0.0, cb.W, 0.0, cb.Dp, seed, door="u0")
    # master bedroom
    cm = room_cell(plan, mast[0], mast[1], 6.0, R2)
    uc = cm.W - 1.72
    V5.exec_bay(plan, cm, uc, cm.Dp - 0.06, 20 + 3 * p)
    V5.headboard_wall(cm, uc, cm.Dp - 0.045)
    with cm.at(uc, cm.Dp - 2.5, 0.0):
        FU.rug_rect(n, 1.2, 0.35, mat="Cushion", border="Accent")
    for j, v in enumerate((0.3, 1.2)):
        with cm.at(0.02, v, 0.0):
            FU.wi_wardrobe(n, w=0.80, d=0.42, h=1.26, insert=("Wood", "Cushion")[j])
        cm.rect(0.23, v, 0.21, 0.40, tag="wardrobe")
    FU.pot_plant(n, *cm.w(cm.W - 0.3, 0.2), r=0.2, h=0.4, seed=seed)
    cm.rect(cm.W - 0.3, 0.2, 0.22, 0.22, tag="plant")
    # living, dining, kitchen
    cl = room_cell(plan, liv[0], liv[1], 5.0, R2)
    W, Dp = cl.W, cl.Dp
    with cl.at(W - 0.95, -0.12, 90.0):
        V5.kitchenette(n, w=1.8, seed=seed)
    cl.rect(W - 0.95, 0.19, 0.90, 0.33, tag="counter")
    cl.anchor("Stand", W - 0.95 - 0.30, -0.12 + 1.05, -90.0)
    V5._table(plan, cl, W - 0.95, 2.0, 90.0, seed, anchors=1)
    tx_, ty_ = pol(A.R2 - 0.75, liv[1] - 5.0)
    FU.tall_plant(n, tx_, ty_, seed=seed + 9)
    plan.rect(tx_, ty_, 0.27, 0.27, tag="plant")
    for s_ in (-1, 1):                                    # plants flanking the terrace door
        x, y = pol(A.R2 - 0.55, rr["terrace_door"] + s_ * 4.2)
        FU.pot_plant(n, x, y, r=0.22, h=0.44, s=1.0, seed=seed + 2 + s_)
        plan.rect(x, y, 0.24, 0.24, tag="plant")
    V5.pendant(plan, cl, W - 0.95, 2.0, seed)
    V5._lounge(plan, cl, 0.55, 3.4, 0.0, seed, seats=2, screen_d=2.75, vmax=Dp, fabric="RugLight")
    # a reading corner between the entry and the lounge: an armchair, a floor lamp, a side table
    with cl.at(2.25, 1.45, 90.0):
        V5.armchair(n, fabric="Fabric")
    cl.rect(2.25, 1.45, 0.47, 0.42, tag="armchair")
    with cl.at(1.55, 1.25, 0.0):
        V5.floor_lamp(n, lamp_cb=IR.lamp_cb(plan, n))
    cl.rect(1.55, 1.25, 0.18, 0.18, tag="lamp")
    for k, v in enumerate((Dp - 0.1,)):
        with cl.at(1.7, v, -90.0):
            FU.wi_shelf(n, w=0.80, d=0.36, h=1.20, seed=seed + 3)
        cl.rect(1.7, v - 0.18, 0.40, 0.18, tag="shelf")
    # bedroom 2 (anchored) and bedroom 3 (a guest room), each with a desk and a wardrobe
    for j, rng_ in enumerate((b2, b3)):
        cr = room_cell(plan, rng_[0], rng_[1], 6.8, R2)
        bu = 0.12 + 0.47 + 0.035
        with cr.at(bu, cr.Dp - 0.06 - 1.09, 0.0):
            FU.bed(n, dressing=j, pillows=1 + j, blanket=("Fabric", "Accent")[j], throw="Cushion", side=1, style=j)
        cr.rect(bu, cr.Dp - 1.15, 0.505, 1.09, tag="bed")
        cr.anchor("Bed", bu, cr.Dp - 0.06 - 1.09, 0.0, lx=BED_BACK)          # every penthouse bedroom counts
        with cr.at(cr.W - 0.02, cr.Dp - 0.6, 180.0):
            FU.wi_desk(n, w=0.9, d=0.44, seed=seed + j)
        cr.rect(cr.W - 0.24, cr.Dp - 0.6, 0.22, 0.45, tag="desk")
        with cr.at(cr.W - 0.02, 0.6, 180.0):
            FU.wi_wardrobe(n, w=0.80, d=0.42, h=1.26)
        cr.rect(cr.W - 0.23, 0.6, 0.21, 0.40, tag="wardrobe")
    x, y = pol(RL, rr["entry"])
    plan.rm.anchor("Unit_2_%d" % p, (x, y, 2 * H + F), rr["entry"])
    return [cl.w(0.5 * W, 0.5 * Dp), cm.w(0.5 * cm.W, 0.5 * cm.Dp), cb.w(0.5 * cb.W, 0.5 * cb.Dp),
            pol(8.2, 0.5 * sum(b2)), pol(8.2, 0.5 * sum(b3)), cl.w(0.5 * W, 0.8 * Dp)]


# --------------------------------------------------------------------------------------
# Terraces (outside the floor walls)
# --------------------------------------------------------------------------------------
def terrace1(rm, part):
    """Floor 1 garden terrace on the floor-0 roof (R1..Rw): a rail, planters on the spoke lines, a lounge set
    outside every living-room door.  All under the floor-1 cut (1.40 m above the slab)."""
    z = H + F
    Rw = rm.Rw
    ro = Rw - 0.35
    with part.at(T(0.0, 0.0, z)):
        # the rail
        part.lathe_a([(ro + 0.03, 0.90), (ro + 0.03, 0.96), (ro - 0.03, 0.96), (ro - 0.03, 0.90)],
                     [360.0 * (k + 0.5) / 120 for k in range(120)], lambda k, i: "Frame", smooth=False)
        for k in range(60):
            x, y = pol(ro, 6.0 * k)
            part.vcyl(x, y, 0.0, 0.92, 0.025, seg=5, mat="Frame")
        for k in range(5):
            a = A.SPOKES[k]
            L = ro - A.R1 - 0.9
            x, y = pol(A.R1 + 0.45 + L / 2, a)
            with part.at(T(x, y, -F), RZ(a)):
                V5.planter_box(part, L, d=0.45, seed=k)
            rr = A.unit_rooms(k)
            a0u, a1u = rr["unit"]
            r0b, r1b = A.R1 + 0.2, ro - 0.25
            # the balcony deck (wood) over the whole unit front, glass screens at its ends
            kk = max(2, int((a1u - a0u) / 4.0))
            for i in range(kk):
                t0 = a0u + 1.0 + (a1u - a0u - 2.0) * i / kk
                t1 = a0u + 1.0 + (a1u - a0u - 2.0) * (i + 1) / kk
                q = [pol(r0b, t0), pol(r1b, t0), pol(r1b, t1), pol(r0b, t1)]
                part.quad((q[0][0], q[0][1], 0.012), (q[1][0], q[1][1], 0.012), (q[2][0], q[2][1], 0.012),
                          (q[3][0], q[3][1], 0.012), "Wood" if i % 2 else "Floor")
            for t in (a0u + 0.6, a1u - 0.6):
                (xa, ya), (xb, yb) = pol(r0b, t), pol(r1b - 0.2, t)
                with part.at(T(0.5 * (xa + xb), 0.5 * (ya + yb), 0.0), RZ(t)):
                    bbox(part, -0.5 * (r1b - 0.2 - r0b), 0.5 * (r1b - 0.2 - r0b), -0.03, 0.03, 0.0, 1.18, "Frost")
                    bbox(part, -0.5 * (r1b - 0.2 - r0b), 0.5 * (r1b - 0.2 - r0b), -0.04, 0.04, 1.16, 1.22, "Frame")
            a = rr["door_out"]
            for s in (-1, 1):
                lx, ly = pol(A.R1 + 1.7, a - 9.0 + s * 2.6)
                with part.at(T(lx, ly, 0.0), RZ(a)):
                    bbox(part, -0.85, 0.85, -0.30, 0.30, 0.0, 0.26, "Frame", bevel=0.02)
                    bbox(part, -0.78, 0.60, -0.28, 0.28, 0.26, 0.36, ("Fabric", "Accent")[k % 2], bevel=0.03)
            tx, ty = pol(A.R1 + 1.6, a + 4.0)
            with part.at(T(tx, ty, -F)):
                FU.table_round(part, r=0.40, h=0.74, top="Wood", edge="Accent")
            for s in (-1, 1):
                cx_, cy_ = pol(A.R1 + 1.6 + s * 0.75, a + 4.0)
                with part.at(T(cx_, cy_, -F), RZ(a + (180.0 if s > 0 else 0.0))):
                    FU.chair(part, seat="Fabric")
            for t in (a0u + 5.0, a0u + 13.0, a1u - 5.0):
                x, y = pol(r1b - 0.3, t)
                with part.at(T(x, y, -F), RZ(t + 90.0)):
                    V5.planter_box(part, 1.4, d=0.40, seed=k * 3 + int(t))
            x, y = pol(r0b + 0.5, a + 9.0)
            part.sphere((x, y, 1.1), 0.14, "Window", seg=8, rings=4)
            part.vcyl(x, y, 0.0, 1.0, 0.03, seg=5, mat="Frame")


def terrace2(rm, part):
    """Floor 2: the glass-roofed penthouse terrace (R2..R1): a plunge pool, loungers, a dining set, planters, a
    planter wall between the two penthouses."""
    z = 2 * H + F
    with part.at(T(0.0, 0.0, z)):
        for p in range(2):
            rr = A.ph_rooms(p)
            a = rr["terrace_door"]
            rp = 0.5 * (A.R2 + A.R1)
            # pool: a rounded basin with a Frame coping and blue water
            px, py = pol(rp, a - 14.0)
            with part.at(T(px, py, 0.0), RZ(a - 14.0 + 90.0)):
                bbox(part, -2.2, 2.2, -1.25, 1.25, 0.0, 0.14, "Frame", bevel=0.03)
                plate_z(part, 0.141, -2.05, 2.05, -1.1, 1.1, "WaterBlue")
                plate_z(part, 0.142, -2.05, 2.05, 1.0, 1.1, "LightStrip")
                bbox(part, 1.25, 1.35, -0.3, 0.3, 0.12, 0.60, "Metal")
            for s in range(3):
                lx, ly = pol(rp + 0.2, a + 4.0 + 6.0 * s)
                with part.at(T(lx, ly, 0.0), RZ(a + 4.0 + 6.0 * s)):
                    bbox(part, -0.85, 0.85, -0.30, 0.30, 0.0, 0.26, "Frame", bevel=0.02)
                    bbox(part, -0.78, 0.60, -0.28, 0.28, 0.26, 0.36, "Cushion", bevel=0.03)
            tx, ty = pol(rp, a + 30.0)
            with part.at(T(tx, ty, -F)):
                FU.table_round(part, r=0.5, h=0.74, top="Wood", edge="Accent")
            for j, ap in enumerate((a + 30.0, a + 7.0)):          # parasols (under the cut: 1.35 m)
                px_, py_ = pol(rp + (0.0 if j == 0 else 0.9), ap)
                part.vcyl(px_, py_, 0.0, 1.1, 0.03, seg=5, mat="Frame")
                with part.at(T(px_, py_, 0.0)):
                    part.lathe([(1.15, 0.98), (0.0, 1.22)], lambda k_, i_: ("Accent", "Hull")[i_ % 2], seg=12,
                               smooth=False)
            for s in range(4):
                cx, cy = pol(rp + 0.85 * cos(radians(90.0 * s)), a + 30.0 + degrees(0.85 * sin(radians(90.0 * s)) / rp))
                with part.at(T(cx, cy, -F), RZ(a + 30.0 + 90.0 * s + 180.0)):
                    FU.chair(part, seat="Fabric")
            # planters along the glass edge
            for s in range(-5, 6):
                x, y = pol(A.R1 - 0.5, rr["entry"] + 15.0 * s)
                with part.at(T(x, y, -F), RZ(rr["entry"] + 15.0 * s + 90.0)):
                    V5.planter_box(part, 1.6, d=0.42, seed=p * 11 + s)
        # the planter walls between the penthouses (90 and 270 deg)
        for a in (90.0, 270.0):
            L = A.R1 - A.R2 - 0.6
            x, y = pol(A.R2 + 0.3 + L / 2, a)
            with part.at(T(x, y, -F), RZ(a)):
                V5.planter_box(part, L, d=0.5, seed=int(a))


# --------------------------------------------------------------------------------------
# The block
# --------------------------------------------------------------------------------------
SHARED = {0: ("lobby", "laundry", "gym", "play", "store"), 1: ("library", "laundry", "hobby", "play", "lounge")}


def apartment_block(rm):
    plan0 = Plan(rm)
    plan0.v5_walls = set()
    count = plan0.count
    plans = [plan0, FloorPlan(rm, 1, count), FloorPlan(rm, 2, count)]
    rm.plan = plan0
    plans[1].r_max = A.R_UNIT - 0.15
    plans[2].r_max = A.R2 - 0.25
    IK.build_floor_v3(rm, "panel", "radial", ring_step=1.6, radial=20, edge_band=0.62, inner_disc=1.2)
    tops = {0: rm.roof, 1: rm.fpart("F1_WallTop"), 2: rm.fpart("F2_WallTop")}
    lights = {0: [], 1: [], 2: []}
    order = []
    # the anchor order: floor 0 units, then floor 0 shared rooms, floor 1 units, floor 1 shared, penthouses
    for fl in (0, 1):
        pl = plans[fl]
        with pl.n.at(T(0.0, 0.0, H * fl)):
            for k in range(5):
                lights[fl] += unit(pl, k, fl, k, seed=7 * k + 31 * fl)
            for k in range(5):
                lights[fl].append(shared_room(pl, SHARED[fl][k], A.SPOKES[k] + A.D_INNER,
                                              A.SPOKES[k] + 72.0 - A.D_INNER, seed=5 * k + 13 * fl))
            core(rm, pl, fl, tops[fl])
            ring_floor(pl, A.R_INNER + 0.06, A.R_STREET - 0.06, "FloorDark")
            ring_line(pl, A.R_INNER + 0.25)
            ring_line(pl, A.R_STREET - 0.25)
            for k in range(5):                            # spoke floors (runner + light line)
                a = A.SPOKES[k]
                r_end = (pl.r_max - 0.1) if fl == 0 else A.R_UNIT
                for (r0_, r1_) in ((A.R_LOBBY, A.R_INNER), (A.R_STREET, r_end)):
                    sector_floor(pl, r0_ + 0.05, r1_ - 0.05, a - A.spoke_delta(r1_) + 0.8, a + A.spoke_delta(r1_) - 0.8,
                                 "FloorDark", step=10.0)
            if fl == 0:
                for k in range(5):
                    yard(pl, k, seed=3 + k)
    with plans[2].n.at(T(0.0, 0.0, 2 * H)):
        for p in range(2):
            lights[2] += penthouse(plans[2], p, seed=41 + 7 * p)
        core(rm, plans[2], 2, tops[2])
    terrace1(rm, rm.fpart("F1_Terrace"))
    terrace2(rm, rm.fpart("F2_Terrace"))
    # link ports on the ground floor
    Rw = rm.R - 0.32
    for i, a in enumerate(A.PORTS):
        x, y = pol(Rw, a)
        rm.anchor("Door_%d" % i, (x, y, F), a)
    # ceiling lights: one over every room (critic round 33: a soft fill, no dark rooms)
    li = 0
    for fl in (0, 1, 2):
        for (x, y) in [(A.R_LOBBY - 0.8, 0.0)] + lights[fl]:
            rm.anchor("Light_%d" % li, (x, y, H * fl + 2.9), 0.0)
            li += 1
    # the ground floor: wall items, aisle points; the density and stand-point checks per floor
    pattern = ["planter", "shelf", "lockers", "cab_plant", "tap", "cab_books"]
    plan0.wall_items(pattern, IR.wall_set(plan0), open_every=3, seed=5, depth_of=IR.DEPTHS)
    plan0.aisles()
    rm.floor_flags = []
    info = {}
    for fl, pl in enumerate(plans):
        lo, hi = H * fl + F - 0.05, H * fl + F + 0.05
        people = [a[1][:2] for a in rm.anchors if a[0].startswith(("Anchor_Bed", "Anchor_Seat", "Anchor_Stand"))
                  and lo < a[1][2] < hi]
        patch, where = IR.empty_patch(pl, people=people)
        info["floor%d_patch" % fl] = [round(patch, 2), [round(q, 1) for q in where] if where else None]
        if fl == 0:
            pl.v4_patch = patch
        elif patch > 2.7:
            rm.floor_flags.append("floor %d: an empty patch %.1f m wide (> 2.5 m) at %s" % (fl, patch, where))
        if fl:
            class Shim:
                pass
            sh = Shim()
            sh.floor_shim = True
            sh.plan, sh.bdef, sh.size, sh.single, sh.Ri = pl, rm.bdef, rm.size, rm.single, rm.Ri
            sh.anchors = [(a[0], (a[1][0], a[1][1], a[1][2] - H * fl), a[2]) for a in rm.anchors
                          if lo < a[1][2] < hi]
            rm.floor_flags += ["floor %d: %s" % (fl, f_) for f_ in IK.check_standpoints(sh)]
    rm.info = info
    rm.plan = plan0


INTERIORS = {
    "apartment_block": apartment_block,
}
