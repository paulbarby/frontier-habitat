"""
Frontier Habitat 3.0 - ART-HAB interiors of the room families other than the habitat (Blender 5.2, --background).
Imported at the end of interior_rooms.py (it uses that module's helpers).  See interior_rooms.py for the layout
languages; every function here builds the Interior, the wall items, the anchors, the lights and the aisles of one
room type for any size.
"""
import math
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, pi
from mathutils import Vector

import rooms_kit as K
import interior_kit as IK
import interior_furniture as FU
from rooms_kit import P, T, RX, RY, RZ, polar, FLOOR_Z, WALL_TOP, SOIL_Z, tank_v, capsule, fan_unit
from interior_kit import (F, SEAT_Z, Plan, bbox, plate_x, plate_y, plate_z, ui_screen, furniture_of, seg_mid, SEAT_BACK,
                          CONSOLE_AHEAD, BENCH_AHEAD, BED_BACK)
from interior_rooms import at, world, lamp_cb, wall_set, DEPTHS, finish, stand_at_wall

BED_L = FU.BED_L


# --------------------------------------------------------------------------------------
# shared helpers
# --------------------------------------------------------------------------------------
def seat_anchor(plan, p, sx, sy):
    """Seat anchor for a seat centre (sx, sy) in the current frame of Part p, the sitter facing local +X."""
    x0, y0, _ = world(p, sx, sy, 0.0)
    x1, y1, _ = world(p, sx + SEAT_BACK, sy, 0.0)
    plan.anchor("Seat", x1, y1, degrees(atan2(y1 - y0, x1 - x0)))


def work_anchor(plan, p, lx, ly, face_local=180.0, sit=False):
    """Work anchor at (lx, ly) of Part p's current frame, facing local angle face_local (default: -X)."""
    x0, y0, _ = world(p, lx, ly, 0.0)
    x1, y1, _ = world(p, lx + cos(radians(face_local)), ly + sin(radians(face_local)), 0.0)
    plan.anchor("Work", x0, y0, degrees(atan2(y1 - y0, x1 - x0)))


def rect_at(plan, p, lx, ly, hx, hy, tag=""):
    """Footprint of a rectangle centred at local (lx, ly) of Part p's current frame."""
    x0, y0, _ = world(p, lx, ly, 0.0)
    x1, y1, _ = world(p, lx + 1.0, ly, 0.0)
    plan.rect(x0, y0, hx, hy, degrees(atan2(y1 - y0, x1 - x0)), tag=tag)


def chord_x(plan, y, margin=0.0):
    """Half length of the chord of the r_max circle at height y."""
    r = plan.r_max - margin
    return sqrt(max(0.0, r * r - y * y))


def sit_desk(plan, x, y, yaw, w=1.2, d=0.62, monitors=2, lamp=True, work=True, seed=0, chair=True, seat=False):
    """Desk with the sitter's stand point 0.12 in front of it and the chair seat 0.30 behind that.
    The frame's +X points from the desk toward the sitter.  Adds a Work (sit) or Seat anchor."""
    n = plan.n
    with at(n, x, y, yaw):
        FU.desk(n, w=w, d=d, monitors=monitors, lamp_cb=lamp_cb(plan, n) if lamp else None, seed=seed)
        if chair:
            with n.at(T(0.42, 0, 0), RZ(180.0)):
                FU.office_chair(n)
                if work is None:
                    pass
                elif work:
                    x0, y0, _ = world(n, 0.0, 0.0, 0.0)
                    x1, y1, _ = world(n, SEAT_BACK, 0.0, 0.0)
                    plan.anchor("Work", x1, y1, degrees(atan2(y1 - y0, x1 - x0)))
                elif seat:
                    seat_anchor(plan, n, 0.0, 0.0)
        rect_at(plan, n, 0.02, 0.0, 0.64, w / 2 + 0.02, tag="desk")


def console_at(plan, x, y, yaw, w=1.0, work=True, glow="Screen"):
    """Standing console (body behind the frame origin); the operator stands 0.45 in front, facing it."""
    n = plan.n
    with at(n, x, y, yaw):
        FU.console(n, w=w, glow=glow)
        if work:
            work_anchor(plan, n, CONSOLE_AHEAD, 0.0)
        rect_at(plan, n, -0.30, 0.0, 0.28, w / 2, tag="console")


def bench_at(plan, x, y, yaw, w=1.8, work=True, lab=False, seed=0):
    n = plan.n
    with at(n, x, y, yaw):
        if lab:
            FU.lab_bench(n, w=w, d=0.75, seed=seed)
        else:
            FU.workbench(n, w=w, d=0.75, seed=seed)
        if work:
            work_anchor(plan, n, BENCH_AHEAD, 0.0)
        rect_at(plan, n, -0.37, 0.0, 0.40, w / 2, tag="bench")


# --------------------------------------------------------------------------------------
# Decor filler: fills the free floor of big rooms with family clusters (no anchors), keeping walkways
# --------------------------------------------------------------------------------------
def d_plant(plan, x, y, yaw, k):
    FU.tall_plant(plan.n, x, y, seed=k)
    return 0.30


def d_light_column(plan, x, y, yaw, k):
    n = plan.n
    n.vcyl(x, y, F, F + 0.06, 0.22, seg=10, mat="Frame", cap0=False)
    n.vcyl(x, y, F + 0.06, F + 1.30, 0.025, seg=6, mat="Metal", cap0=False)
    n.lathe([(0.26, F + 1.28), (0.18, F + 1.55), (0.0, F + 1.55)], "Window", seg=10, smooth=False)
    n.vcyl(x, y, F + 1.25, F + 1.29, 0.27, seg=10, mat="Frame")
    plan.lamp(x, y, F + 1.4)
    return 0.25


def d_reading(plan, x, y, yaw, k, compact=False):
    """Two armchairs round a side table with a lamp, on a round rug."""
    n = plan.n
    FU.rug_round(n, 0.80 if compact else 1.05, x, y, mat=("Fabric", "Cushion")[k % 2], ring="Accent", seg=12)
    with at(n, x, y, yaw):
        for sy in (-1, 1):
            with n.at(T(0.0, sy * (0.52 if compact else 0.62), 0), RZ(-90.0 * sy)):
                FU.sofa(n, n=1, fabric=("Fabric", "Cushion")[(k + (sy > 0)) % 2])
        n.vcyl(0.35, 0, F, F + 0.55, 0.20, seg=8, mat="Hull", cap0=False, cap1=False)
        with n.at(T(0.35, 0, 0)):
            n.lathe([(0.21, F + 0.55), (0.21, F + 0.58), (0.0, F + 0.58)], "Wood", seg=8, smooth=False)
            n.vcyl(0, 0, F + 0.58, F + 0.80, 0.012, seg=4, mat="Metal", cap0=False, cap1=False)
            n.lathe([(0.10, F + 0.76), (0.075, F + 0.92), (0.0, F + 0.92)], "Window", seg=8, smooth=False)
    lx, ly, _ = (x + cos(radians(yaw)) * 0.35, y + sin(radians(yaw)) * 0.35, 0)
    plan.lamp(lx, ly, F + 0.86)
    return 0.85 if compact else 1.05


def d_bench(plan, x, y, yaw, k):
    """Waiting bench (three shell seats on a beam)."""
    n = plan.n
    with at(n, x, y, yaw):
        n.beam((0, -0.95, F + 0.30), (0, 0.95, F + 0.30), 0.08, 0.06, "Frame")
        for sy in (-0.9, 0.9):
            bbox(n, -0.20, 0.20, sy - 0.03, sy + 0.03, F, F + 0.30, "Frame")
        for j in range(3):
            with n.at(T(0, -0.62 + 0.62 * j, 0)):
                bbox(n, -0.21, 0.21, -0.26, 0.26, F + 0.38, F + 0.46, "Accent" if j != 1 else "Hull", bevel=0.02)
                with n.at(T(-0.22, 0, F + 0.46), RY(-10.0)):
                    bbox(n, -0.03, 0.0, -0.26, 0.26, 0.0, 0.40, "Hull", bevel=0.015)
    return 1.0


def d_cart(plan, x, y, yaw, k):
    """Service cart with drawers (medical, lab, workshop)."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.30, 0.30, -0.22, 0.22, F + 0.12, F + 0.90, ("Hull", "Accent")[k % 2], bevel=0.02)
        for j in range(4):
            plate_x(n, 0.301, -0.18, 0.18, F + 0.18 + 0.17 * j, F + 0.30 + 0.17 * j, "FloorDark")
        for sx in (-0.24, 0.24):
            for sy in (-0.16, 0.16):
                n.vcyl(sx, sy, F, F + 0.12, 0.05, seg=6, mat="Frame")
        n.beam((-0.33, -0.2, F + 0.95), (-0.33, 0.2, F + 0.95), 0.03, 0.03, "Metal")
    return 0.42


def d_rack_island(plan, x, y, yaw, k):
    """Double-sided shelf island (1.6 m long)."""
    n = plan.n
    with at(n, x, y, yaw):
        for side in (-1, 1):
            with n.at(T(0, side * 0.01, 0), RZ(90.0 * side)):
                FU.wi_shelf(n, w=1.6, d=0.30, h=1.30, seed=k * 3 + side)
    return 0.95


def d_pallets(plan, x, y, yaw, k):
    FU.pallet(plan.n, x, y, yaw, load=1 + k % 2, seed=k)
    return 0.80


def d_bottles(plan, x, y, yaw, k):
    """Gas bottle rack (industry)."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.45, 0.45, -0.18, 0.18, F, F + 0.05, "Frame")
        for j in range(4):
            yy = -0.33 + 0.22 * j
            n.vcyl(yy, 0, F + 0.05, F + 1.25, 0.09, seg=8, mat=("Hazard", "Metal", "Accent", "Metal")[j])
            n.vcyl(yy, 0, F + 1.25, F + 1.35, 0.03, seg=6, mat="Frame")
        n.beam((-0.45, -0.18, F + 0.9), (0.45, -0.18, F + 0.9), 0.03, 0.03, "Frame")
    return 0.50


def d_planter(plan, x, y, yaw, k):
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.80, 0.80, -0.28, 0.28, F, F + 0.48, "Hull", bevel=0.02)
        plate_z(n, F + 0.485, -0.76, 0.76, -0.24, 0.24, "FloorDark")
        for j in range(4):
            FU.leafy_plant(n, -0.6 + 0.4 * j, 0.0, F + 0.46, s=0.55, n=5, seed=k + j)
    return 0.85


def d_tanks(plan, x, y, yaw, k):
    """Two process tanks on a skid with a pipe bridge."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.95, 0.95, -0.5, 0.5, F, F + 0.10, "Frame", bevel=0.01)
        for sx in (-0.48, 0.48):
            tank_v(n, sx, 0.0, F + 0.10, 1.05, 0.40, mat="Metal", band="Accent", cap="dome", seg=10)
        FU.pipe_run(n, [(-0.48, 0.0, F + 1.45), (-0.48, 0.0, F + 1.62), (0.48, 0.0, F + 1.62), (0.48, 0.0, F + 1.45)],
                    r=0.05, mat="Metal")
    return 1.0


def d_unit(plan, x, y, yaw, k):
    """A process unit on a hazard pad with a side screen."""
    n = plan.n
    with at(n, x, y, yaw):
        if plan.rm.cat not in ("science", "medical"):
            FU.hazard_rect(n, 0.85, 0.65)
        FU.machine_block(n, 0.6, 0.45, 1.1 + 0.1 * (k % 3), glow=("Window", "Screen", None)[k % 3])
    return 0.95


NEED = {"tanks": 1.0, "unit": 0.95, "plant": 0.30, "light": 0.25, "reading": 1.05, "bench": 1.0, "cart": 0.42,
        "racks": 0.95, "pallets": 0.80, "bottles": 0.5, "planter": 0.85}
DECOR = {"tanks": d_tanks, "unit": d_unit, "plant": d_plant, "light": d_light_column, "reading": d_reading, "bench": d_bench, "cart": d_cart,
         "racks": d_rack_island, "pallets": d_pallets, "bottles": d_bottles, "planter": d_planter}


def fill_decor(plan, kinds, max_n=None, walk=0.85, seed=0, step=0.7, align=None):
    """Place decor clusters (cycling `kinds`) in free floor: each cluster keeps `walk` metres to every other
    footprint.  max_n default: one cluster per 9 m2 of the r_max disc beyond what S has."""
    rng = random.Random(seed)
    area = pi * plan.r_max ** 2
    if max_n is None:
        max_n = max(0, int((area - 14.0) / 9.0))
    placed = 0
    cands = []
    m = int(plan.r_max // step)
    for i in range(-m, m + 1):
        for j in range(-m, m + 1):
            cands.append((i * step + rng.uniform(-0.1, 0.1), j * step + rng.uniform(-0.1, 0.1)))
    rng.shuffle(cands)
    k = 0
    for (x, y) in cands:
        if placed >= max_n:
            break
        kind = kinds[k % len(kinds)]
        need = NEED[kind]
        if hypot(x, y) > plan.r_max - need - 0.05:
            continue
        if plan.dist(x, y) < need + walk:
            continue
        yaw = align if align is not None else degrees(atan2(y, x)) + 90.0
        r = DECOR[kind](plan, x, y, yaw, k)
        plan.circle(x, y, r, tag="decor")
        placed += 1
        k += 1
    return placed


# --------------------------------------------------------------------------------------
# COMFORT: lounge and cantina
# --------------------------------------------------------------------------------------
def media_unit(plan, x, y, yaw, w=1.9):
    """Low credenza with a big screen on a stand; faces local +X."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.22, 0.22, -w / 2, w / 2, F, F + 0.48, "Hull", bevel=0.02)
        bbox(n, -0.225, 0.225, -w / 2 - 0.005, w / 2 + 0.005, F + 0.48, F + 0.51, "Wood", bevel=0.006)
        for j in range(3):
            plate_x(n, 0.221, -w / 2 + 0.06 + (w - 0.1) * j / 3, -w / 2 + 0.04 + (w - 0.1) * (j + 1) / 3,
                    F + 0.08, F + 0.42, "FloorDark")
        bbox(n, -0.10, 0.0, -0.06, 0.06, F + 0.51, F + 0.72, "Frame")
        with n.at(T(-0.05, 0, F + 1.12)):
            ui_screen(n, w * 0.85, 0.80, glow="Screen", seed=2)
        plate_x(n, 0.23, -w / 2 + 0.1, w / 2 - 0.1, F + 0.45, F + 0.47, "Neon")
        FU.pot_plant(n, 0.0, w / 2 + 0.30, r=0.18, h=0.45, s=0.8, seed=3)
        rect_at(plan, n, 0.0, 0.15, 0.26, w / 2 + 0.35, tag="media")


def sofa_at(plan, x, y, yaw, nseat, fabric="Cushion"):
    n = plan.n
    with at(n, x, y, yaw):
        seats = FU.sofa(n, n=nseat, fabric=fabric)
        for (sx, sy) in seats:
            seat_anchor(plan, n, sx, sy)
        rect_at(plan, n, -0.03, 0.0, 0.42, nseat * 0.31 + 0.13, tag="sofa")


def island(plan, cx, cy, yaw, spec, rug=(1.5, 1.2), table=(0.55, 0.35), rugmat="RugLight"):
    """A conversation island: rug, coffee table, and sofas/armchairs (kind, nseat, dx, dy, dyaw) in the island
    frame; each sofa faces its local +X (toward the table)."""
    n = plan.n
    with at(n, cx, cy, yaw):
        FU.rug_rect(n, rug[0], rug[1], mat=rugmat, border="Accent")
        FU.coffee_table(n, table[0], table[1])
        FU.pot_plant(n, 0.2, 0.08, r=0.07, h=0.08, s=0.25, seed=4, z0=F + 0.40)
        rect_at(plan, n, 0.0, 0.0, table[0], table[1], tag="ctable")
    c, s_ = cos(radians(yaw)), sin(radians(yaw))
    for (kind, ns, dx, dy, dyaw) in spec:
        x, y = cx + c * dx - s_ * dy, cy + s_ * dx + c * dy
        sofa_at(plan, x, y, yaw + dyaw, ns, fabric="CushionLight" if kind == "sofa" else "Fabric")


def lounge(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "panel", "radial", ring_step=1.4, radial=12, edge_band=0.64, inner_disc=1.0)
    rmax = plan.r_max
    w_media = 1.6 + 0.2 * s
    # the media unit's footprint (0.26 deep, w/2 + 0.35 wide) stays inside r_max: the door lane (2026-09-25)
    rl = min(rmax, plan.lane_r())
    mx = -(sqrt(max(0.3, rl ** 2 - (w_media / 2 + 0.35) ** 2)) - 0.28)
    media_unit(plan, mx, 0.0, 0.0, w=w_media)
    if s == 0:        # 3 seats
        island(plan, mx + 1.55, 0.0, 0.0, [("sofa", 3, 0.95, 0.0, 180.0)], rug=(1.2, 1.35), table=(0.45, 0.30))
        # (critic round 7) the armchair pair, facing the table from both sides (no anchors: the room has 3 seats)
        n_ = plan.n
        for sy in (-1, 1):
            ax, ay = mx + 1.55 - 0.15, sy * 1.25
            with at(n_, ax, ay, -90.0 * sy):
                FU.sofa(n_, n=1, fabric="Fabric")
            plan.rect(ax, ay, 0.44, 0.44, 0.0, tag="armchair")
    elif s == 1:      # 6 seats: an L of two 3-seat sofas
        island(plan, mx + 2.15, 0.0, 0.0, [("sofa", 3, 1.00, 0.0, 180.0), ("sofa", 3, -0.75, -1.25, 90.0)],
               rug=(1.6, 1.6))
    elif s == 2:      # 10 seats: an L of 3 + 3, a reading corner of a 2-seat sofa and 2 armchairs
        island(plan, mx + 2.1, 0.0, 0.0, [("sofa", 3, 1.00, 0.0, 180.0), ("sofa", 3, -0.75, -1.25, 90.0)],
               rug=(1.7, 1.7))
        island(plan, rmax * 0.42, rmax * 0.38, -35.0, [("sofa", 2, 0.0, 1.0, 270.0), ("chair", 1, 0.95, -0.35, 150.0),
                                       ("chair", 1, -0.95, -0.35, 30.0)], rug=(1.3, 1.3), table=(0.40, 0.40),
               rugmat="Fabric")
    else:             # 16 seats: a U of 3 + 3 + 3, and an island of 3 + 2 + 2 armchairs
        island(plan, mx + 2.3, 0.0, 0.0, [("sofa", 3, 1.25, 0.0, 180.0), ("sofa", 3, -0.75, -1.3, 90.0),
                                          ("sofa", 3, -0.75, 1.3, 270.0)], rug=(1.9, 1.9))
        island(plan, rmax * 0.45, -rmax * 0.30, 20.0, [("sofa", 3, 0.0, -1.15, 90.0), ("sofa", 2, 0.0, 1.1, 270.0),
                                       ("chair", 1, 1.25, 0.0, 180.0), ("chair", 1, -1.25, 0.0, 0.0)],
               rug=(1.5, 1.5), table=(0.45, 0.40), rugmat="Fabric")
    if s <= 1:
        place_reading(plan, seed=21 + s)
    for (px, py) in ((mx + 0.35, rmax * 0.62), (mx + 0.35, -rmax * 0.62), (rmax * 0.55, rmax * 0.55),
                     (rmax * 0.62, -rmax * 0.1)):
        if plan.dist(px, py) > 0.45 and hypot(px, py) < rmax - 0.3 and not (s == 0 and plan.count.get("_plants", 0)):
            plan.count["_plants"] = plan.count.get("_plants", 0) + 1
            FU.tall_plant(plan.n, px, py, seed=int(abs(px) * 10) % 7)
            plan.rect(px, py, 0.28, 0.28, 0.0, tag="plant")
    fill_decor(plan, ["reading", "light", "plant", "light"], seed=21 + s, max_n=None if s else 0)
    plan.wall_items(["cab_lamp", "shelf", "planter", "bottles", "cab_books", "panel", "planter", "shelf"],
                    wall_set(plan), open_every=3 if s else 2, seed=21 + s, depth_of=DEPTHS)
    plan.stands(fu["stands"])
    finish(plan)


def bar_counter(plan, x, y, yaw, L, h=0.78):
    """Straight counter (wood top, dark body, neon lines, foot rail); the staff side is local -X."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.30, 0.30, -L / 2, L / 2, F, F + h - 0.04, "HullDark", bevel=0.02)
        bbox(n, -0.34, 0.36, -L / 2 - 0.03, L / 2 + 0.03, F + h - 0.04, F + h, "Wood", bevel=0.01)
        plate_x(n, 0.302, -L / 2 + 0.04, L / 2 - 0.04, F + 0.12, F + 0.15, "Neon")
        plate_x(n, 0.302, -L / 2 + 0.04, L / 2 - 0.04, F + h - 0.14, F + h - 0.11, "Neon")
        n.cyl((0.36, -L / 2 + 0.1, F + 0.20), (0.36, L / 2 - 0.1, F + 0.20), 0.025, seg=6, mat="Metal")
        nb = int(L / 0.9) + 1
        for k in range(nb):
            yy = -L / 2 + 0.2 + (L - 0.4) * k / max(1, nb - 1)
            n.vcyl(-0.1, yy, F + h, F + h + 0.20, 0.04, seg=6, mat="Glass", cap0=False)
        rect_at(plan, n, 0.0, 0.0, 0.36, L / 2 + 0.05, tag="bar")


def table_lamp(plan, p, x, y, z):
    """Small warm table lamp (a glowing shade) with an Anchor_Lamp for the game's warm pool."""
    p.vcyl(x, y, z, z + 0.02, 0.06, seg=6, mat="Frame", cap0=False)
    p.vcyl(x, y, z + 0.02, z + 0.16, 0.012, seg=4, mat="Metal", cap0=False, cap1=False)
    p.vcyl(x, y, z + 0.14, z + 0.24, 0.085, 0.055, seg=8, mat="Window")
    plan.lamp(*world(p, x, y, z + 0.22))


def booth(plan, x, y, yaw, per_side=2, seed=0):
    """Booth: a table between two high-backed benches, an end screen toward the wall (local -X), open toward the
    room (+X).  Seats face the table.  A table lamp."""
    n = plan.n
    L = 0.62 * per_side + 0.12
    fab = ("Cushion", "Fabric")[seed % 2]
    with at(n, x, y, yaw):
        bbox(n, -L / 2 - 0.16, L / 2 + 0.30, -1.08, 1.08, F, F + 0.012, "Wood", mats={"-z": None})
        plate_x(n, L / 2 + 0.301, -1.04, 1.04, F + 0.002, F + 0.011, "Neon")
        FU.table_rect(n, L / 2 - 0.02, 0.32, top="Wood", edge="Neon")
        for sy in (-1, 1):
            y0, y1 = sorted((sy * 0.52, sy * 0.88))
            bbox(n, -L / 2, L / 2, y0, y1, F, F + 0.22, "Frame", bevel=0.02)
            bbox(n, -L / 2 + 0.02, L / 2 - 0.02, y0 + 0.01, y1 - 0.01, F + 0.22, F + SEAT_Z, fab, bevel=0.04)
            b0, b1 = sorted((sy * 0.86, sy * 1.00))
            bbox(n, -L / 2, L / 2, b0, b1, F + 0.22, F + 1.12, fab, bevel=0.04)
            bbox(n, -L / 2 - 0.01, L / 2 + 0.01, b0 - 0.005, b1 + 0.005, F + 1.12, F + 1.16, "Frame")
            plate_z(n, F + 1.161, -L / 2 + 0.03, L / 2 - 0.03, (b0 + b1) / 2 - 0.02, (b0 + b1) / 2 + 0.02, "Neon")
            for j in range(per_side):
                sx = -L / 2 + 0.06 + 0.31 + 0.62 * j
                with n.at(T(sx, sy * 0.70, 0), RZ(-90.0 if sy > 0 else 90.0)):
                    seat_anchor(plan, n, 0.0, 0.0)
        bbox(n, -L / 2 - 0.14, -L / 2, -1.00, 1.00, F, F + 1.16, "HullDark", bevel=0.02)
        plate_x(n, -L / 2 + 0.002, -0.9, 0.9, F + 0.95, F + 0.99, "Neon")
        table_lamp(plan, n, -L / 2 + 0.16, 0.0, F + 0.74)
        rect_at(plan, n, -0.07, 0.0, L / 2 + 0.07, 1.0, tag="booth")


def back_bar(plan, x, y, L):
    """Back bar behind the bartender (hidable Tall part): shelves of bottles lit from below by neon, a mirror
    panel, a neon ring sign.  Faces -Y (toward the bar)."""
    tp = plan.tall(x, y)
    with at(tp, x, y, -90.0):
        bbox(tp, -0.20, 0.20, -L / 2, L / 2, F, F + 0.86, "HullDark", bevel=0.02)
        plate_x(tp, 0.202, -L / 2 + 0.05, L / 2 - 0.05, F + 0.80, F + 0.83, "Neon")
        bbox(tp, -0.20, -0.14, -L / 2, L / 2, F + 0.86, F + 1.55, "Frame")
        plate_x(tp, -0.138, -L / 2 + 0.08, L / 2 - 0.08, F + 0.92, F + 1.48, "Glass")
        for z in (F + 1.06, F + 1.34):
            bbox(tp, -0.14, 0.05, -L / 2 + 0.05, L / 2 - 0.05, z - 0.03, z, "Wood")
            tp.quad((-0.12, -L / 2 + 0.08, z - 0.031), (-0.12, L / 2 - 0.08, z - 0.031), (0.03, L / 2 - 0.08, z - 0.031),
                    (0.03, -L / 2 + 0.08, z - 0.031), "Neon")
            nb = int((L - 0.2) / 0.11)
            for k in range(nb):
                yy = -L / 2 + 0.12 + 0.11 * k
                tp.vcyl(-0.05, yy, z, z + 0.16 + 0.04 * (k % 3), 0.032, seg=6,
                        mat=("Glass", "Accent", "Window", "Glass")[k % 4])
        with tp.at(T(-0.12, 0.0, F + 1.72), RY(-90.0)):
            tp.torus(0.16, 0.02, "Neon", seg=12, tseg=3)
    plan.rect(x, y, 0.22, L / 2, 90.0, tag="backbar")


def cantina(rm):
    """Cantina (critic round 4): a lit bar with a neon front and a back bar, a dark lounge floor zone with high-
    backed booths round the south arc, bistro tables between, a warm lamp on every table."""
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "panel", "grid", grid=1.0)
    n = plan.n
    rmax = plan.r_max
    bar_n, sides, bistro = {0: (2, (1,), 0), 1: (4, (2,), 0), 2: (4, (2, 2, 1), 0), 3: (6, (2, 2, 2, 1), 1)}[s]
    n_booth = len(sides)
    assert bar_n + sum(2 * q for q in sides) + bistro * 2 == fu["seats"], "cantina seats"
    # the bar on a chord in the north, stools on its south side
    by = rmax * 0.50
    L = min(2 * chord_x(plan, by + 0.5, 0.2), 0.62 * bar_n + 0.6)
    bar_counter(plan, 0.0, by, -90.0, L)
    with at(n, 0.0, by, -90.0):
        # neon fins down the bar front (seen from above and from the room)
        nf = int(L / 0.45)
        for k in range(nf + 1):
            yy = -L / 2 + 0.06 + (L - 0.12) * k / max(1, nf)
            plate_x(n, 0.304, yy - 0.012, yy + 0.012, F + 0.15, F + 0.64, "Neon")
    for k in range(bar_n):
        sx = -L / 2 + 0.35 + (L - 0.7) * k / max(1, bar_n - 1)
        with at(n, sx, by - 0.62, 90.0):
            FU.stool(n)
            seat_anchor(plan, n, 0.0, 0.0)
        plan.circle(sx, by - 0.62, 0.20, tag="stool")
    for k in range(max(1, int(L / 1.2))):
        xx = -L / 2 + 0.4 + (L - 0.8) * (k + 0.5) / max(1, int(L / 1.2))
        table_lamp(plan, n, xx, by + 0.05, F + 0.78)
    back_bar(plan, 0.0, by + 0.70, max(1.2, L - 0.3))
    # booths round the south arc, backs to the wall, on a dark lounge floor band with a neon rim
    step = (0.0, 0.0, 55.0, 47.0)[s]
    angs = [270.0 + (k - (n_booth - 1) / 2) * step for k in range(n_booth)]
    span = (n_booth - 1) * step / 2 + degrees(1.35 / max(1.0, rmax - 1.0)) + 6.0
    # (critic round 7: the floor band read as a stain) each booth stands on its own wood inlay
    zy = -rmax * 0.30
    for i, a in enumerate(angs):
        for rr in [rmax - 1.0 - 0.1 * j for j in range(12)]:
            bx, bb = rr * cos(radians(a)), rr * sin(radians(a))
            if plan.fits(bx, bb, 0.75, 1.02, a + 180.0) and rect_ok(plan, bx, bb, a + 180.0):
                booth(plan, bx, bb, a + 180.0, per_side=sides[i], seed=i)
                break
        else:
            raise AssertionError("cantina: no room for booth %d" % i)
    # bistro tables for two (XL)
    for j in range(bistro):
        tx = (j - (bistro - 1) / 2) * 2.6
        ty = zy + 0.4
        with n.at(T(tx, ty, 0)):
            FU.table_round(n, r=0.40, edge="Neon")
        table_lamp(plan, n, tx, ty, F + 0.74)
        plan.circle(tx, ty, 0.40, tag="table")
        for a in (0.0, 180.0):
            cx, cy = tx + 0.76 * cos(radians(a)), ty + 0.76 * sin(radians(a))
            with at(n, cx, cy, a + 180.0):
                FU.chair(n, seat="Fabric")
                seat_anchor(plan, n, 0.0, 0.0)
            plan.rect(cx, cy, 0.25, 0.24, a + 180.0, tag="chair")
    # standing high tables (the stand anchors: people drink standing) in the free middle
    highs = []
    for k in range((0, 1, 2, 3)[s]):
        for (hx_, hy_) in [(-1.6 + 1.6 * k + dx, by - 1.9 + dy) for dx in (0.0, 0.4, -0.4) for dy in (0.0, -0.5, -1.0)]:
            if plan.fits(hx_, hy_, 0.9, 0.9) and rect_ok(plan, hx_, hy_, 0.0, 0.85, 0.85):
                with n.at(T(hx_, hy_, 0)):
                    n.vcyl(0, 0, F, F + 0.03, 0.24, seg=8, mat="Frame", cap0=False)
                    n.vcyl(0, 0, F + 0.03, F + 1.02, 0.04, seg=6, mat="Metal", cap0=False, cap1=False)
                    n.vcyl(0, 0, F + 1.02, F + 1.06, 0.34, seg=12, mat="Wood")
                    n.vcyl(0, 0, F + 1.00, F + 1.02, 0.35, seg=12, mat="Neon", cap0=False, cap1=False)
                table_lamp(plan, n, hx_ + 0.12, hy_, F + 1.06)
                plan.circle(hx_, hy_, 0.36, tag="high")
                highs += [(hx_ + 0.62, hy_, 180.0), (hx_ - 0.62, hy_, 0.0)]
                break
    fill_decor(plan, ["gametable", "planter", "light", "plant", "gametable"], max_n=(0, 2, 3, 5)[s], seed=31 + s,
               walk=0.55)
    plan.wall_items(["bottles", "poster", "cab_lamp", "plant", "panel", "bottles", "vent", "poster"],
                    wall_set(plan), open_every=3, seed=31 + s, depth_of=DEPTHS)
    cands = highs + [(-L / 2 + 0.4 + 0.55 * j, by - 1.15, 90.0) for j in range(10)]
    plan.stands(fu["stands"], cands)
    finish(plan)


def d_gametable(plan, x, y, yaw, k):
    """A game table (felt top, wood rails, a hanging-lamp glow) for the cantina floor."""
    n = plan.n
    with at(n, x, y, yaw):
        for sx in (-0.5, 0.5):
            for sy in (-0.28, 0.28):
                bbox(n, sx - 0.05, sx + 0.05, sy - 0.05, sy + 0.05, F, F + 0.70, "Frame", mats={"-z": None})
        bbox(n, -0.68, 0.68, -0.42, 0.42, F + 0.70, F + 0.80, "Wood", bevel=0.02)
        plate_z(n, F + 0.802, -0.60, 0.60, -0.34, 0.34, "Cushion")
        for j, (bx, by) in enumerate(((-0.2, 0.05), (0.1, -0.12), (0.3, 0.14))):
            n.vcyl(bx, by, F + 0.80, F + 0.85, 0.028, seg=6, mat=("Neon", "Hull", "Window")[j])
    plan.lamp(x, y, F + 1.2)
    return 0.80


def place_reading(plan, seed=0):
    """The armchair pair with a side table and a lamp, in the first free spot round the room (lounge S/M)."""
    for compact, need in ((False, 1.05), (True, 0.85)):
        for rr in [plan.r_max - need - 0.05 - 0.2 * j for j in range(8)]:
            for k in range(36):
                a = 10.0 * k + 7.0
                x, y = rr * cos(radians(a)), rr * sin(radians(a))
                if hypot(x, y) + need > plan.r_max + 0.25 or plan.dist(x, y) < need + 0.35:
                    continue
                r = d_reading(plan, x, y, a + 90.0, seed, compact=compact)
                plan.circle(x, y, r, tag="reading")
                return True
    return False


DECOR["gametable"] = d_gametable
NEED["gametable"] = 0.80


def zone_arc(n, r0, r1, a0, a1, mat="FloorDark", rim="Neon"):
    """A floor band (annular sector) with a neon rim on its inner edge."""
    k = max(2, int((a1 - a0) / 5.0))
    z = F + 0.008
    for i in range(k):
        t0, t1 = radians(a0 + (a1 - a0) * i / k), radians(a0 + (a1 - a0) * (i + 1) / k)
        n.quad((r0 * cos(t0), r0 * sin(t0), z), (r1 * cos(t0), r1 * sin(t0), z), (r1 * cos(t1), r1 * sin(t1), z),
               (r0 * cos(t1), r0 * sin(t1), z), mat)
        n.quad(((r0 - 0.05) * cos(t0), (r0 - 0.05) * sin(t0), z + 0.001), (r0 * cos(t0), r0 * sin(t0), z + 0.001),
               (r0 * cos(t1), r0 * sin(t1), z + 0.001), ((r0 - 0.05) * cos(t1), (r0 - 0.05) * sin(t1), z + 0.001), rim)


def rect_ok(plan, x, y, yaw, hx=0.78, hy=1.05):
    c, s_ = cos(radians(yaw)), sin(radians(yaw))
    for i in range(-2, 3):
        for j in range(-2, 3):
            lx, ly = hx * i / 2, hy * j / 2
            if plan.dist(x + c * lx - s_ * ly, y + s_ * lx + c * ly) <= 0.0:
                return False
    return True


# --------------------------------------------------------------------------------------
# MEDICAL and BIO-LAB
# --------------------------------------------------------------------------------------
def med_bed(plan, x, y, yaw, i, arch=False):
    """Treatment bed, head toward local +Y, on a pedestal; a hidable headwall (Tall) with a monitor and gas
    outlets; optional scanner arch.  Bed anchor: stand point beside the bed, the heal pose lies on it."""
    n = plan.n
    c, s_ = cos(radians(yaw + 90.0)), sin(radians(yaw + 90.0))
    hx, hy = x + c * (BED_L / 2 + 0.12), y + s_ * (BED_L / 2 + 0.12)
    tp = plan.tall(hx, hy)
    zt = F + 0.55
    with at(n, x, y, yaw):
        for sy in (-0.7, 0.7):
            bbox(n, -0.25, 0.25, sy - 0.05, sy + 0.05, F, F + 0.06, "Frame")
        bbox(n, -0.06, 0.06, -0.06, 0.06, F + 0.06, zt - 0.18, "Metal")
        bbox(n, -0.30, 0.30, -0.75, 0.75, F + 0.06, F + 0.12, "Frame")
        bbox(n, -0.44, 0.44, -1.0, 1.0, zt - 0.18, zt - 0.10, "Frame", bevel=0.01)
        bbox(n, -0.42, 0.42, -0.98, 0.98, zt - 0.10, zt, "Hull", bevel=0.04)
        with n.at(T(0, 0.50, zt - 0.02), RX(-16.0)):
            bbox(n, -0.40, 0.40, -0.02, 0.44, 0.0, 0.08, "Hull", bevel=0.03)
        bbox(n, -0.45, 0.45, -0.97, 0.05, zt - 0.02, zt + 0.03, "Accent", bevel=0.012)
        for sx in (-1, 1):
            n.beam((sx * 0.47, -0.6, zt + 0.12), (sx * 0.47, 0.2, zt + 0.12), 0.03, 0.03, "Metal")
            n.beam((sx * 0.47, -0.55, zt - 0.10), (sx * 0.47, -0.55, zt + 0.12), 0.025, 0.025, "Metal")
            n.beam((sx * 0.47, 0.15, zt - 0.10), (sx * 0.47, 0.15, zt + 0.12), 0.025, 0.025, "Metal")
        if arch:
            with n.at(T(0, -0.25, F + 0.30), RX(90.0)):
                n.lathe([(0.98, -0.28), (0.98, 0.28), (0.78, 0.28), (0.78, -0.28)],
                        lambda k, j: ("Hull", "Hull", "HullDark", "Hull")[k], seg=10, a0=0.0, a1=180.0, smooth=True,
                        caps=True, cap_mat="Hull")
                n.lathe([(0.99, -0.06), (0.99, 0.06)], "Neon", seg=10, a0=0.0, a1=180.0, caps=False)
            for sx in (-1, 1):
                bbox(n, sx * 0.98 - 0.12, sx * 0.98 + 0.12, -0.55, 0.05, F, F + 0.32, "HullDark", bevel=0.02)
        tf = n._stack[-1]
    with tp.at(tf):
        yh = BED_L / 2 + 0.08
        bbox(tp, -0.55, 0.55, yh, yh + 0.10, F, F + 1.30, "Hull", bevel=0.02)
        plate_y(tp, yh - 0.002, -0.45, 0.45, F + 1.12, F + 1.17, "LightStrip", facing=-1)
        plate_y(tp, yh - 0.002, -0.45, 0.45, F + 0.72, F + 0.75, "Accent", facing=-1)
        with tp.at(T(0.28, yh - 0.02, F + 0.96), RZ(-90.0)):
            ui_screen(tp, 0.34, 0.24, seed=i)
        for j in range(3):
            bbox(tp, -0.36 + 0.09 * j, -0.30 + 0.09 * j, yh - 0.03, yh, F + 0.86, F + 0.92,
                 ("Accent", "WaterBlue", "Frame")[j])
    plan.rect(x, y, 1.12 if arch else 0.47, BED_L / 2 + 0.2, yaw, tag="mbed%d" % i)
    off = 0.55
    c2, s2 = cos(radians(yaw)), sin(radians(yaw))
    plan.anchor("Bed", x + c2 * off, y + s2 * off, yaw)


def _rect_gap(cx, cy, hx, hy, yaw, x, y):
    """Distance from the point (x, y) to an oriented rectangle (0 inside)."""
    c, s_ = cos(radians(yaw)), sin(radians(yaw))
    lx = c * (x - cx) + s_ * (y - cy)
    ly = -s_ * (x - cx) + c * (y - cy)
    return hypot(max(abs(lx) - hx, 0.0), max(abs(ly) - hy, 0.0))


def iv_stand(n, x, y):
    n.vcyl(x, y, F, F + 0.03, 0.18, seg=6, mat="Frame", cap0=False)
    n.vcyl(x, y, F + 0.03, F + 1.75, 0.015, seg=4, mat="Metal", cap0=False)
    n.beam((x - 0.15, y, F + 1.72), (x + 0.15, y, F + 1.72), 0.02, 0.02, "Metal")
    bbox(n, x + 0.06, x + 0.14, y - 0.03, y + 0.03, F + 1.45, F + 1.65, "WaterBlue")


def medical(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "grid", grid=1.2)
    n = plan.n
    rmax = plan.r_max
    nb = fu["beds"]
    # a row of treatment bays on a chord in the north, heads to the north, curtains between them
    pitch = 1.70 if nb < 6 else 1.55                # XL: six bays on the chord inside r_max
    gap = (0.45 if nb < 6 else 0.52) if s >= 1 else 0.0     # extra room beside the arch bay
    half_row = (nb - 1) * pitch / 2 + 0.75 + gap / 2
    head_y = sqrt(max(0.3, (rmax - 0.1) ** 2 - half_row ** 2)) - 0.30
    cy = head_y - BED_L / 2 - 0.12
    # the arch bay (footprint 1.12 wide) in the middle of the row, where the chord is longest (the door lane)
    arch_i = nb // 2 if s >= 1 else -1
    for i in range(nb):
        x = (i - (nb - 1) / 2) * pitch - gap / 2 + (gap if i >= arch_i >= 0 else 0.0)
        med_bed(plan, x, cy, 0.0, i, arch=(i == arch_i))
        if i < nb - 1:
            cx_ = x + max(pitch / 2 + (0.12 if i != arch_i else 0.25), 0.95) + (gap / 2 if i == arch_i - 1 else 0.0)
            tp = plan.tall(cx_, cy + 0.45)
            with at(tp, cx_, cy + 0.45, 90.0):
                FU.privacy_screen(tp, 1.2, h=1.35, panel="Frost", edge="Frame")
            plan.rect(cx_, cy + 0.45, 0.6, 0.04, 90.0, tag="curtain")
    iv_stand(n, -half_row - 0.1 + 0.3, cy + 0.6)
    plan.circle(-half_row + 0.2, cy + 0.6, 0.2)
    if s >= 2:
        FU.floor_line(n, -chord_x(plan, cy - 1.45), cy - BED_L / 2 - 0.45, chord_x(plan, cy - 1.45),
                      cy - BED_L / 2 - 0.45, w=0.08, mat="Accent")
    # the nurse station in the south, facing the beds; the other seats are visitor chairs
    dy = -(rmax * 0.58)
    sit_desk(plan, 0.6, dy, -90.0, w=1.3, work=False, seat=True, seed=1)
    for j in range(fu["seats"] - 1):
        cx_, cy_ = -1.2 - 0.62 * j, dy - 0.05
        with at(n, cx_, cy_, 90.0):
            FU.chair(n, seat="Accent")
            seat_anchor(plan, n, 0.0, 0.0)
        plan.rect(cx_, cy_, 0.25, 0.25, 90.0, tag="chair")
    if s >= 2:
        # diagnostics in the south half: a scanner with its patient table, one or two supply islands
        items = ([(scanner, 1.30, 0.85)] if s == 3 else []) + [(supply_island, 0.50, 0.95)] * (1 if s == 2 else 2)
        for (fn, hx_, hy_) in items:
            for rr in [rmax - max(hx_, hy_) - 0.1 - 0.3 * j for j in range(8)]:
                done = False
                for a in range(186, 360, 8):
                    gx, gy = rr * cos(radians(a)), rr * sin(radians(a))
                    yaw = a + 90.0
                    if plan.fits(gx, gy, hx_, hy_, yaw) and rect_ok(plan, gx, gy, yaw, hx_ + 0.25, hy_ + 0.25) \
                            and all(hypot(gx - q[1][0], gy - q[1][1]) > max(hx_, hy_) + 0.6 and
                                    _rect_gap(gx, gy, hx_ + 0.25, hy_ + 0.25, yaw, q[1][0], q[1][1]) >= 0.40
                                    for q in rm.anchors
                                    if q[0].startswith(("Anchor_Bed", "Anchor_Seat", "Anchor_Stand", "Anchor_Work"))):
                        fn(plan, gx, gy, yaw)
                        done = True
                        break
                if done:
                    break
    fill_decor(plan, ["bench", "cart", "plant", "cart"], seed=41 + s, max_n=(0, 1, 2, 3)[s])
    plan.wall_items(["medcab", "medcab", "tap", "shelf", "lockers", "panel", "medcab", "plant"],
                    wall_set(plan), open_every=3, seed=41 + s, depth_of=DEPTHS)
    plan.stands(fu["stands"], [(-0.6, dy + 1.1, 90.0), (1.6, dy + 1.1, 90.0)])
    finish(plan)


def scanner(plan, x, y, yaw):
    """Diagnostic scanner: a thick ring on a pedestal, a sliding patient table through it (no anchor)."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.45, 0.45, -0.55, 0.55, F, F + 0.14, "Frame", bevel=0.02)
        with n.at(T(0.0, 0.0, F + 0.95), RY(90.0)):
            n.lathe([(0.80, -0.22), (0.80, 0.22), (0.50, 0.22), (0.50, -0.22)],
                    lambda k, j: ("Hull", "Hull", "HullDark", "Hull")[k], seg=16, smooth=True)
            n.lathe([(0.81, -0.05), (0.81, 0.05)], "Accent", seg=16, caps=False)
        bbox(n, 0.3, 1.1, -0.22, 0.22, F, F + 0.60, "Hull", bevel=0.03)
        bbox(n, -1.2, 1.2, -0.28, 0.28, F + 0.60, F + 0.72, "Hull", bevel=0.03)
        bbox(n, -0.9, 1.1, -0.22, 0.22, F + 0.72, F + 0.76, "Accent", bevel=0.01)
        plate_x(n, 0.451, -0.30, 0.30, F + 1.30, F + 1.50, "Screen")
        rect_at(plan, n, 0.0, 0.0, 1.25, 0.85, tag="scanner")    # (was outside the frame)


def supply_island(plan, x, y, yaw):
    """Sterile supply island: a counter with drawers on both sides, a sink and a screen."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.40, 0.40, -0.85, 0.85, F, F + 0.88, "Hull", bevel=0.02)
        bbox(n, -0.42, 0.42, -0.87, 0.87, F + 0.88, F + 0.92, "Frame", bevel=0.01)
        for sx in (-1, 1):
            for j in range(3):
                yy = -0.6 + 0.6 * j
                plate_x(n, sx * 0.402, yy - 0.25, yy + 0.25, F + 0.12, F + 0.80, "HullDark", facing=sx)
                plate_x(n, sx * 0.405, yy - 0.10, yy + 0.10, F + 0.72, F + 0.74, "Accent", facing=sx)
        bbox(n, -0.22, 0.22, 0.30, 0.70, F + 0.86, F + 0.925, "Metal")
        n.vcyl(0.0, 0.72, F + 0.92, F + 1.20, 0.02, seg=6, mat="Metal", cap0=False)
        bbox(n, -0.02, 0.02, -0.55, -0.15, F + 0.92, F + 1.25, "Frame")
        plate_x(n, 0.021, -0.53, -0.17, F + 0.98, F + 1.22, "Screen", facing=1)
        rect_at(plan, n, 0.0, 0.0, 0.45, 0.90, tag="supply")     # (was outside the frame: registered at 0, 0)


def d_glovebox(plan, x, y, yaw, k):
    """Glove box: a sealed glass cabinet on a stand, two dark glove ports, an airlock drum at the side."""
    n = plan.n
    with at(n, x, y, yaw):
        for sx in (-0.5, 0.5):
            for sy in (-0.25, 0.25):
                bbox(n, sx - 0.03, sx + 0.03, sy - 0.03, sy + 0.03, F, F + 0.80, "Frame", mats={"-z": None})
        bbox(n, -0.62, 0.62, -0.34, 0.34, F + 0.80, F + 0.88, "Hull")
        bbox(n, -0.60, 0.60, -0.32, 0.32, F + 1.40, F + 1.46, "Hull")
        for sx in (-1, 1):
            plate_x(n, sx * 0.60, -0.32, 0.32, F + 0.88, F + 1.40, "Glass", facing=sx)
            plate_y(n, sx * 0.32, -0.60, 0.60, F + 0.88, F + 1.40, "Glass", facing=sx)
        for yy in (-0.25, 0.25):
            with n.at(T(0.61, yy, F + 1.10), RY(90.0)):
                n.vcyl(0, 0, -0.01, 0.04, 0.09, seg=10, mat="Frame")
        n.cyl((-0.62, 0.0, F + 1.10), (-0.85, 0.0, F + 1.10), 0.16, seg=10, mat="Hull")
        plate_z(n, F + 1.461, -0.40, 0.40, -0.05, 0.05, "Glow")
    return 0.70


def d_labfridge(plan, x, y, yaw, k):
    """Sample fridge: tall, frosted glass door with lit shelves, a display."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.36, 0.36, -0.36, 0.36, F, F + 1.85, "Hull", bevel=0.02)
        plate_x(n, 0.362, -0.30, 0.30, F + 0.10, F + 1.62, "HullDark")
        plate_x(n, 0.365, -0.30, 0.30, F + 0.10, F + 1.62, "Glass")
        for j in range(5):
            plate_x(n, 0.364, -0.28, 0.28, F + 0.25 + 0.28 * j, F + 0.27 + 0.28 * j, "LightStrip")
        plate_x(n, 0.364, -0.18, 0.18, F + 1.68, F + 1.78, "Screen")
    return 0.52


DECOR["glovebox"] = d_glovebox
NEED["glovebox"] = 0.70
DECOR["labfridge"] = d_labfridge
NEED["labfridge"] = 0.52


def fume_hood(n, w=1.2):
    """Fume hood; local +X is the open front."""
    zt = F + 0.90
    bbox(n, -0.70, 0.0, -w / 2, w / 2, F, zt - 0.03, "Hull", bevel=0.02)
    bbox(n, -0.72, 0.02, -w / 2 - 0.02, w / 2 + 0.02, zt - 0.03, zt, "Metal")
    bbox(n, -0.70, -0.62, -w / 2, w / 2, zt, F + 1.62, "Hull")
    for sy in (-1, 1):
        y0, y1 = (w / 2 - 0.04, w / 2) if sy > 0 else (-w / 2, -w / 2 + 0.04)
        bbox(n, -0.70, 0.0, y0, y1, zt, F + 1.62, "Hull")
    bbox(n, -0.72, 0.02, -w / 2 - 0.02, w / 2 + 0.02, F + 1.62, F + 2.02, "Hull", bevel=0.02)
    plate_x(n, 0.021, -w / 2 + 0.02, w / 2 - 0.02, F + 1.70, F + 1.74, "Accent")
    plate_x(n, -0.02, -w / 2 + 0.05, w / 2 - 0.05, zt + 0.30, F + 1.58, "Glass")
    plate_z(n, F + 1.61, -0.66, -0.05, -w / 2 + 0.05, w / 2 - 0.05, "LightStrip")
    for j in range(3):
        n.vcyl(-0.35, -w * 0.3 + w * 0.3 * j, zt, zt + 0.22, 0.05, seg=6, mat=("Glow", "Glass", "Glow")[j], cap0=False)


def bio_lab(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "grid", grid=1.0)
    n = plan.n
    rmax = plan.r_max
    nw = fu["work_slots"]
    rows = {1: [0.0], 2: [0.9, -0.9], 3: [1.7, 0.0, -1.7]}[nw]
    for i, y in enumerate(rows):
        hl = min(1.3 + 0.25 * s, chord_x(plan, abs(y) + 0.9, 0.2) - 0.2)
        bench_at(plan, 0.0, y + 0.37, -90.0, w=2 * hl, lab=True, seed=i)
        zs = min(F + 2.02, rm.headroom(0.0, y + 0.37) - 0.10)
        bbox(n, -hl, hl, y + 0.52, y + 0.64, zs, zs + 0.08, "Frame")
        plate_z(n, zs - 0.001, -hl + 0.05, hl - 0.05, y + 0.55, y + 0.61, "LightStrip")
        for sx in (-hl + 0.05, hl - 0.05):
            bbox(n, sx - 0.03, sx + 0.03, y + 0.55, y + 0.61, F + 0.90, zs, "Frame")
    fy = rows[0] + 1.55
    fx = -rmax * 0.30
    if hypot(abs(fx) + 0.6, fy + 0.4) > rmax:
        fy = sqrt(max(0.0, (rmax - 0.1) ** 2 - (abs(fx) + 0.6) ** 2)) - 0.4
    tp = plan.tall(fx, fy)
    with at(tp, fx, fy, -90.0):
        fume_hood(tp, w=1.1)
    plan.rect(fx, fy + 0.35, 0.6, 0.40, 0.0, tag="hood")
    tx, ty = rmax * 0.42, fy - 0.1
    FU.tank(n, tx, ty, 1.0 + 0.1 * s, 0.38, mat="Glass", band="Accent", seg=10)
    n.vcyl(tx, ty, F + 0.25, F + 1.15 + 0.1 * s, 0.30, seg=10, mat="Glow", cap0=False)
    plan.circle(tx, ty, 0.5)
    fill_decor(plan, ["glovebox", "labfridge", "cart", "glovebox", "labfridge"], seed=51 + s, align=0.0,
               max_n=(1, 2, 3, 5)[s], walk=0.6)
    plan.wall_items(["medcab", "fridge", "shelf", "panel", "medcab", "planter", "vent"],
                    wall_set(plan), open_every=3, seed=51 + s, depth_of=DEPTHS)
    plan.stands(fu["stands"])
    finish(plan)


# --------------------------------------------------------------------------------------
# KITCHEN
# --------------------------------------------------------------------------------------
def cook_line(plan, x, y, yaw, L, cooktops=2, works=1):
    """Straight kitchen line on a splashback: counters, cooktops (glowing rings), a sink, one hood per cooktop
    hanging from the splashback.  Local +X faces the cooks; their work anchors stand 0.45 in front."""
    n = plan.n
    with at(n, x, y, yaw):
        zt = F + 0.90
        bbox(n, -0.65, 0.0, -L / 2, L / 2, F, zt - 0.04, "Hull", bevel=0.02)
        bbox(n, -0.67, 0.02, -L / 2 - 0.01, L / 2 + 0.01, zt - 0.04, zt, "Metal", bevel=0.008)
        nd = max(2, int(L / 0.6))
        for j in range(nd):
            y0 = -L / 2 + 0.03 + (L - 0.06) * j / nd
            plate_x(n, 0.002, y0 + 0.02, y0 + (L - 0.06) / nd - 0.02, F + 0.10, zt - 0.10, "FloorDark")
        bbox(n, -0.75, -0.65, -L / 2, L / 2, F, F + 1.95, "Hull")
        plate_x(n, -0.648, -L / 2 + 0.05, L / 2 - 0.05, zt + 0.05, zt + 0.55, "Metal")
        pos = [-L / 2 + L * (j + 0.5) / (cooktops + 1) for j in range(cooktops + 1)]
        for j, cy_ in enumerate(pos[:cooktops]):
            bbox(n, -0.55, -0.10, cy_ - 0.28, cy_ + 0.28, zt, zt + 0.015, "Frame")
            for (dx, dy) in ((-0.42, -0.13), (-0.42, 0.13), (-0.22, -0.13), (-0.22, 0.13)):
                with n.at(T(dx, cy_ + dy, zt + 0.016)):
                    n.torus(0.07, 0.012, "Window", seg=8, tseg=3)
            bbox(n, -0.75, -0.25, cy_ - 0.38, cy_ + 0.38, F + 1.62, F + 1.78, "Metal", bevel=0.02)
            plate_z(n, F + 1.619, -0.70, -0.30, cy_ - 0.32, cy_ + 0.32, "LightStrip")
            if j < works:
                work_anchor(plan, n, CONSOLE_AHEAD, cy_)
        sy_ = pos[-1]
        bbox(n, -0.55, -0.15, sy_ - 0.25, sy_ + 0.25, zt - 0.14, zt + 0.005, "WaterBlue")
        n.beam((-0.6, sy_, zt), (-0.6, sy_, zt + 0.30), 0.03, 0.03, "Metal")
        n.beam((-0.6, sy_, zt + 0.30), (-0.42, sy_, zt + 0.30), 0.03, 0.03, "Metal")
        rect_at(plan, n, -0.37, 0.0, 0.40, L / 2 + 0.02, tag="cook")


def mess_table(plan, x, y, yaw, nper, seat="Cushion"):
    """Long table with nper chairs on each long side."""
    n = plan.n
    L = 0.62 * nper + 0.3
    with at(n, x, y, yaw):
        FU.table_rect(n, 0.42, L / 2, top="Hull", edge="Accent")
        for side in (-1, 1):
            for j in range(nper):
                yy = -L / 2 + 0.46 + 0.62 * j
                with n.at(T(side * 0.80, yy, 0), RZ(180.0 if side > 0 else 0.0)):
                    FU.chair(n, seat=seat)
                    seat_anchor(plan, n, 0.0, 0.0)
        rect_at(plan, n, 0.0, 0.0, 1.05, L / 2 + 0.05, tag="mess")


def kitchen(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "panel", "grid", grid=0.9)
    n = plan.n
    rmax = plan.r_max
    gx = -(rmax - 0.80)                      # the galley on the west chord (under the chimney)
    L = min(3.4, 2 * sqrt(max(0.3, (rmax - 0.1) ** 2 - (abs(gx) + 0.45) ** 2)))
    # the galley's footprint (back 0.77 m behind gx) stays inside the door lanes (2026-09-25)
    gx = -(sqrt(max(0.3, (min(rmax, plan.lane_r()) - 0.02) ** 2 - (L / 2 + 0.02) ** 2)) - 0.77)
    cook_line(plan, gx, 0.0, 0.0, L, cooktops=(1, 2, 2, 3)[s], works=fu["work_slots"])
    if s >= 2:                               # a prep island
        ix = gx + 1.75
        with at(n, ix, 0.0, 0.0):
            bbox(n, -0.40, 0.40, -1.0, 1.0, F, F + 0.86, "Hull", bevel=0.02)
            bbox(n, -0.43, 0.43, -1.03, 1.03, F + 0.86, F + 0.90, "Wood", bevel=0.008)
            for j in range(3):
                FU.crate(n, 0.0, -0.6 + 0.6 * j, s=0.22, z=F + 0.90, mat=("Plant", "Hull", "Accent")[j], band="Frame")
        plan.rect(ix, 0.0, 0.45, 1.05, 0.0, tag="island")
    spec = {0: [2], 1: [3], 2: [3, 2], 3: [3, 3, 2]}[s]
    x0 = (0.75, 1.0, 1.5, 0.75)[s]
    if s >= 2:
        # L / XL: the tables turn along X and stand side by side, inside r_max (the door lane, 2026-09-25)
        xc = (2.0, 2.3)[s - 2]
        for j, nper in enumerate(spec):
            mess_table(plan, xc, (j - (len(spec) - 1) / 2) * 2.3, 90.0, nper, seat=("Cushion", "Fabric")[j % 2])
    else:
        for j, nper in enumerate(spec):
            mess_table(plan, x0 + max(2.25, plan.r_max * 0.36) * j, 0.0, 0.0, nper, seat=("Cushion", "Fabric")[j % 2])
    fill_decor(plan, ["racks", "planter", "cart"], seed=61 + s, align=0.0)
    plan.wall_items(["fridge", "shelf", "fridge", "planter", "cab_box", "panel", "shelf", "tap"],
                    wall_set(plan), open_every=3, seed=61 + s, depth_of=DEPTHS)
    plan.stands(fu["stands"], [(gx + 1.0, L / 2 + 0.25, 180.0), (gx + 1.0, -L / 2 - 0.25, 180.0)])
    finish(plan)


INTERIORS = {
    "lounge": lounge,
    "cantina": cantina,
    "medical": medical,
    "bio_lab": bio_lab,
    "kitchen": kitchen,
}
