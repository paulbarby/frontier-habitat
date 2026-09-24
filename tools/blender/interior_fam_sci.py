"""
Frontier Habitat 3.0 - ART-HAB interiors: science (research lab, research assembler) and links (airlock,
junction).

research_lab: desk pods (two desks back to back with a low divider) round a glowing holo table; the desks are the
              Work anchors (work_pose "sit").
research_assembler: a clean-room line: water feed -> conveyor -> robot arm cell -> pack stacker -> pack racks.
airlock: a suit bay by the outer door (+X, kept), a bench, a decontamination grate, the cycle console.
junction: an open hub; floor medallion and direction arrows, nothing tall (up to 6 doorways).
"""
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, pi

import interior_kit as IK
import interior_furniture as FU
from rooms_kit import T, RX, RY, RZ, tank_v, capsule
from interior_kit import F, Plan, bbox, plate_x, plate_y, plate_z, ui_screen, furniture_of
from interior_rooms import at, wall_set, DEPTHS, finish, lamp_cb
from interior_families import (fill_decor, console_at, sit_desk, chord_x, rect_at, seat_anchor, DECOR, NEED)


def research_lab(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "radial", ring_step=1.2, radial=12, edge_band=0.64, inner_disc=1.3)
    n = plan.n
    rmax = plan.r_max
    FU.rug_round(n, 1.25 + 0.1 * s, mat="Cushion", ring="Accent", seg=24)
    FU.holo_table(n, r=0.62 + 0.08 * s)
    plan.circle(0.0, 0.0, 0.66 + 0.08 * s, tag="holo")
    nw = fu["work_slots"]
    npods = max((nw + 1) // 2, (1, 2, 3, 4)[s])      # more desks than staff in the big labs (unstaffed stations)
    rp = min(rmax - 1.25, 2.3 + 0.35 * s)
    for k in range(npods):
        a = 90.0 + 360.0 * k / max(1, npods) + (0.0 if npods > 1 else 180.0)
        px, py = rp * cos(radians(a)), rp * sin(radians(a))
        # the pod runs tangentially; desk A faces the room centre side, desk B faces the wall side
        tang = a + 90.0
        for j, side in enumerate((-1, 1)):
            if 2 * k + j >= max(nw, 2 * npods):
                break
            dx, dy = side * 0.02 * cos(radians(a)), side * 0.02 * sin(radians(a))
            yaw = a + (180.0 if side < 0 else 0.0)        # +X of the desk frame points to the sitter
            sit_desk(plan, px + dx, py + dy, yaw, w=1.25, d=0.62, monitors=2, seed=2 * k + j,
                     work=(2 * k + j < nw), chair=(2 * k + j < nw) or (j == 0))
        # low divider between the two desks with a light line
        with at(n, px, py, tang):
            bbox(n, -0.66, 0.66, -0.025, 0.025, F + 0.74, F + 1.10, "Hull", bevel=0.01)
            plate_z(n, F + 1.101, -0.62, 0.62, -0.01, 0.01, "LightStrip")
    fill_decor(plan, ["specimen", "server", "cart", "specimen", "server"], max_n=(2, 3, 5, 7)[s],
               seed=151 + s, walk=0.6)
    ws = wall_set(plan, {"screenwall": lambda p, w, d, k: wi_screenwall(p, w=w, seed=k),
                         "samples": lambda p, w, d, k: wi_samples(p, w=w, d=min(d, 0.32), seed=k)})
    plan.wall_items(["samples", "screenwall", "samples", "desk", "screenwall", "shelf", "medcab", "samples"], ws,
                    open_every=4, seed=151 + s, depth_of=dict(DEPTHS, screenwall=0.08, samples=0.32))
    plan.stands(fu["stands"], [(1.3, 0.0, 180.0), (-1.3, 0.0, 0.0), (0.0, 1.3, -90.0)])
    finish(plan)


def d_server(plan, x, y, yaw, k):
    """A pair of server / analysis racks with LED rows and a screen (research)."""
    n = plan.n
    with at(n, x, y, yaw):
        for sy in (-0.33, 0.33):
            bbox(n, -0.30, 0.30, sy - 0.30, sy + 0.30, F, F + 1.75, "HullDark", bevel=0.02)
            for j in range(7):
                z = F + 0.20 + 0.20 * j
                plate_x(n, 0.302, sy - 0.24, sy + 0.24, z, z + 0.03, "Frame")
                plate_x(n, 0.304, sy - 0.22, sy - 0.14, z + 0.005, z + 0.025, ("L3Band", "Screen", "Accent")[(j + k) % 3])
            plate_z(n, F + 1.752, -0.25, 0.25, sy - 0.25, sy + 0.25, "Frame")
    return 0.70


DECOR["server"] = d_server
NEED["server"] = 0.70


def wi_screenwall(p, w=0.80, seed=0):
    """Wall section with a large analysis screen, a graph strip and a status bar (x 0 = wall)."""
    bbox(p, 0.0, 0.05, -w / 2 + 0.02, w / 2 - 0.02, F + 0.55, F + 1.32, "HullDark")
    plate_x(p, 0.052, -w / 2 + 0.05, w / 2 - 0.05, F + 0.60, F + 1.27, "Screen")
    for j in range(4):
        y0 = -w / 2 + 0.10 + (w - 0.2) * j / 4
        plate_x(p, 0.054, y0, y0 + (w - 0.2) / 4 - 0.03, F + 0.66, F + 0.66 + 0.08 + 0.12 * ((j + seed) % 3),
                ("L3Band", "Accent", "LightStrip")[(j + seed) % 3])
    plate_x(p, 0.054, -w / 2 + 0.08, w / 2 - 0.08, F + 1.18, F + 1.21, "LightStrip")


def wi_samples(p, w=0.80, d=0.32, seed=0):
    """Sample-rack wall section: three shelves of tube racks (glowing cultures, capped tubes)."""
    rng = random.Random(seed)
    for sy in (-1, 1):
        bbox(p, 0.0, d, sy * w / 2 - 0.02, sy * w / 2 + 0.02, F, F + 1.25, "Frame")
    plate_x(p, 0.02, -w / 2, w / 2, F, F + 1.25, "HullDark")
    for lv in range(3):
        z = F + 0.30 + 0.36 * lv
        bbox(p, 0.02, d, -w / 2 + 0.02, w / 2 - 0.02, z - 0.02, z, "Hull")
        bbox(p, 0.06, d - 0.04, -w / 2 + 0.06, w / 2 - 0.06, z, z + 0.05, "Frame")
        for j in range(4):
            yy = -w / 2 + 0.14 + (w - 0.28) * j / 3
            p.vcyl(d / 2, yy, z + 0.05, z + 0.05 + rng.uniform(0.10, 0.16), 0.03, seg=4,
                   mat=("Glow", "Glass", "L3Band", "Glass")[(j + lv) % 4], cap0=False)


def d_specimen(plan, x, y, yaw, k):
    """Specimen case: a lit plinth with a glass case round a glowing sample."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.32, 0.32, -0.32, 0.32, F, F + 0.85, "Hull", bevel=0.02)
        plate_z(n, F + 0.852, -0.28, 0.28, -0.28, 0.28, "LightStrip")
        for sx in (-1, 1):
            plate_x(n, sx * 0.30, -0.30, 0.30, F + 0.86, F + 1.45, "Glass", facing=sx)
            plate_x(n, sx * 0.296, -0.30, 0.30, F + 0.86, F + 1.45, "Glass", facing=-sx)
            plate_y(n, sx * 0.30, -0.30, 0.30, F + 0.86, F + 1.45, "Glass", facing=sx)
            plate_y(n, sx * 0.296, -0.30, 0.30, F + 0.86, F + 1.45, "Glass", facing=-sx)
        bbox(n, -0.32, 0.32, -0.32, 0.32, F + 1.45, F + 1.49, "Frame")
        n.vcyl(0, 0, F + 0.86, F + 0.92, 0.10, seg=8, mat="Frame")
        capsule(n, (0, 0, F + 1.02), (0, 0, F + 1.22), 0.08, mat="Glow", seg=6, rings=1)
        plate_x(n, 0.322, -0.20, 0.20, F + 0.60, F + 0.72, "Screen")
    return 0.45


DECOR["specimen"] = d_specimen
NEED["specimen"] = 0.45


def pack_rack(n, w=1.4, h=1.4, seed=0):
    """Free-standing rack of research packs (local +X front): blue basic, cyan applied, violet exotic packs."""
    rng = random.Random(seed)
    for sy in (-1, 1):
        bbox(n, -0.25, 0.25, sy * w / 2 - 0.03, sy * w / 2 + 0.03, F, F + h, "Frame")
    for lv in range(4):
        z = F + 0.08 + (h - 0.2) * lv / 3
        bbox(n, -0.25, 0.25, -w / 2, w / 2, z - 0.03, z, "Hull")
        if lv == 3:
            break
        y = -w / 2 + 0.08
        while y < w / 2 - 0.18:
            m = rng.choice(("Accent", "Accent", "L3Band", "L4Band"))
            bbox(n, -0.18, 0.18, y, y + 0.14, z, z + 0.20, "Hull", bevel=0.01)
            plate_x(n, 0.181, y + 0.02, y + 0.12, z + 0.04, z + 0.16, m)
            y += 0.17


def research_assembler(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "grid", grid=1.0)
    n = plan.n
    rmax = plan.r_max
    lines = [0.0] if s < 3 else [0.9, -0.9]
    for li, y in enumerate(lines):
        L = min(2 * chord_x(plan, abs(y) + 0.5, 0.2) - 2.2, 3.4 + 0.5 * s)
        L = max(L, 1.6)
        x0 = -L / 2
        # the water feed station at the start of the line
        tx = x0 - 0.55
        tank_v(n, tx, y, F, 1.0, 0.32, mat="Hull", band="WaterBlue", cap="dome", seg=10, legs=True)
        plan.circle(tx, y, 0.4)
        FU.pipe_run(n, [(tx + 0.3, y, F + 0.6), (x0 + 0.2, y, F + 0.6), (x0 + 0.2, y, F + 0.85)], r=0.04,
                    mat="WaterBlue")
        with at(n, 0.0, y, 0.0):
            FU.conveyor(n, L, w=0.6, h=0.80)
            for j in range(int(L / 0.45)):
                xx = -L / 2 + 0.3 + 0.45 * j
                bbox(n, xx - 0.12, xx + 0.12, -0.12, 0.12, F + 0.80, F + 0.98, "Hull", bevel=0.01)
                plate_z(n, F + 0.981, xx - 0.08, xx + 0.08, -0.08, 0.08, ("Accent", "L3Band", "L4Band")[j % 3])
        plan.rect(0.0, y, L / 2, 0.36, 0.0, tag="line")
        # the robot arm cell over the middle, in a clean-room glass partition
        ay = y + (0.75 if li == 0 else -0.75)
        with at(n, -0.2, ay, 0.0):
            FU.robot_arm(n, reach=0.75, yaw=-90.0 if li == 0 else 90.0, mat="Hull")
        plan.circle(-0.2, ay, 0.4)
        with at(n, -0.2, y, 0.0):
            for sx in (-1, 1):
                bbox(n, sx * 0.9 - 0.02, sx * 0.9 + 0.02, -0.55, 0.55, F + 0.9, F + 1.9, "Frame")
                # clear tinted glass (both faces) with cyan edge lights, so it reads as glass from any side
                plate_x(n, sx * 0.9 + 0.004, -0.5, 0.5, F + 1.0, F + 1.85, "Glass", facing=1)
                plate_x(n, sx * 0.9 - 0.004, -0.5, 0.5, F + 1.0, F + 1.85, "Glass", facing=-1)
                plate_x(n, sx * 0.9 + 0.012, -0.5, 0.5, F + 1.0, F + 1.85, "Glass", facing=1)
                plate_x(n, sx * 0.9 - 0.012, -0.5, 0.5, F + 1.0, F + 1.85, "Glass", facing=-1)
                for fc in (1, -1):
                    for zz in (F + 0.99, F + 1.84):
                        plate_x(n, sx * 0.9 + fc * 0.022, -0.5, 0.5, zz, zz + 0.02, "Plasma", facing=fc)
                    for yy in (-0.5, 0.48):
                        plate_x(n, sx * 0.9 + fc * 0.022, yy, yy + 0.02, F + 1.0, F + 1.85, "Plasma", facing=fc)
            for sy in (-1, 1):
                bbox(n, -0.92, 0.92, sy * 0.55 - 0.03, sy * 0.55 + 0.03, F + 1.88, F + 1.96, "Frame")
            bbox(n, -0.92, 0.92, -0.04, 0.04, F + 1.90, F + 1.96, "Frame")
            plate_z(n, F + 1.898, -0.85, 0.85, -0.025, 0.025, "LightStrip")
        # the pack stacker at the end of the line
        with at(n, L / 2 + 0.45, y, 0.0):
            FU.machine_block(n, 0.35, 0.40, 1.05, body="Hull", panel="HullDark", stripe="Accent", glow="Screen")
        plan.rect(L / 2 + 0.45, y, 0.38, 0.42, 0.0, tag="stacker")
    # pack racks along the south side
    nr = (1, 2, 2, 3)[s]
    ry = -(rmax * 0.62) if s < 3 else -(rmax * 0.72)
    for k in range(nr):
        rx = (k - (nr - 1) / 2) * 1.7
        if hypot(abs(rx) + 0.8, ry - 0.3) > rmax:
            continue
        with at(n, rx, ry, 90.0):
            pack_rack(n, w=1.4, seed=k)
        plan.rect(rx, ry, 0.72, 0.28, 90.0, tag="packs")
    console_at(plan, rmax * 0.35, rmax * 0.55, -90.0, w=0.9, work=False)
    FU.floor_line(n, -chord_x(plan, 1.2), 1.2 if s < 3 else 2.1, chord_x(plan, 1.2), 1.2 if s < 3 else 2.1, w=0.06,
                  mat="Accent")
    fill_decor(plan, ["cart", "crates", "reels"], max_n=(0, 1, 2, 3)[s], seed=161 + s, align=0.0)
    plan.wall_items(["shelf", "vent", "cable", "panel", "fridge", "lockers"], wall_set(plan), open_every=3,
                    seed=161 + s, depth_of=DEPTHS)
    plan.stands(fu["stands"])
    finish(plan)


def airlock(rm):
    fu = furniture_of(rm)
    plan = Plan(rm, clear=0.45, item_depth=0.40)
    IK.build_floor_v3(rm, "grate", "grid", grid=0.6)
    n = plan.n
    # decontamination grate and hazard frame in front of the outer door (+X)
    with at(n, 0.9, 0.0, 0.0):
        FU.hazard_rect(n, 0.55, 0.75, w=0.08)
        for j in range(6):
            plate_z(n, F + 0.006, -0.5, 0.5, -0.7 + 0.25 * j, -0.62 + 0.25 * j, "Frame")
    # a bench down the middle (west half) and the cycle console by the door
    with at(n, -0.55, 0.0, 90.0):
        bbox(n, -0.60, 0.60, -0.18, 0.18, F + 0.38, F + 0.46, "Hull", bevel=0.02)
        for sx in (-0.45, 0.45):
            bbox(n, sx - 0.04, sx + 0.04, -0.14, 0.14, F, F + 0.38, "Frame")
        FU.crate(n, 0.3, 0.0, s=0.22, z=F + 0.46, mat="Accent")
    plan.rect(-0.55, 0.0, 0.62, 0.2, 90.0, tag="bench")
    console_at(plan, 0.95, -1.15, 90.0, w=0.6, work=False)
    # EVA suits on free-standing racks near the wall (hidable Tall parts: the segments are too narrow here)
    for a in (125.0, 160.0, 200.0, 235.0):
        r = plan.Ri - 0.30
        x, y = r * cos(radians(a)), r * sin(radians(a))
        tp = plan.tall(x, y)
        with at(tp, x, y, a + 180.0):
            with tp.at(T(-0.26, 0, 0)):
                FU.wi_suitrack(tp, w=0.7)
        plan.rect(x, y, 0.25, 0.36, a, tag="suit")
    plan.wall_items(["lockers", "panel", "vent"], wall_set(plan), open_every=0, seed=171, depth_of=DEPTHS,
                    skip=[k for k in range(32) if 115.0 < IK.seg_mid(k) < 245.0])
    plan.stands(fu["stands"], [(0.4, 0.55, 180.0), (0.4, -0.55, 180.0), (-1.1, 0.6, 0.0)])
    plan.lights([(0.0, 0.0), (0.9, 0.0)], z=2.2)
    plan.aisles(spacing=0.8, clearance=0.30, link=1.4)


def junction(rm):
    fu = furniture_of(rm)
    plan = Plan(rm, clear=0.45, item_depth=0.10)
    IK.build_floor_v3(rm, "panel", "radial", ring_step=0.9, radial=6, edge_band=0.40, inner_disc=0.6)
    n = plan.n
    FU.rug_round(n, 0.55, mat="Floor", ring="Accent", seg=16)
    for k in range(6):
        with at(n, 0.0, 0.0, 60.0 * k):
            n.quad((0.85, -0.10, F + 0.012), (1.15, -0.10, F + 0.012), (1.25, 0.0, F + 0.012), (0.95, 0.0, F + 0.012),
                   "Accent")
            n.quad((0.95, 0.0, F + 0.012), (1.25, 0.0, F + 0.012), (1.15, 0.10, F + 0.012), (0.85, 0.10, F + 0.012),
                   "Accent")
    # a low information post at the centre (seen from above as a lit disc)
    n.vcyl(0, 0, F, F + 0.06, 0.22, seg=10, mat="Frame", cap0=False)
    n.vcyl(0, 0, F + 0.06, F + 0.95, 0.07, seg=8, mat="Hull", cap0=False)
    n.vcyl(0, 0, F + 0.95, F + 1.05, 0.16, seg=10, mat="Frame")
    with n.at(T(0, 0, F + 1.051)):
        n.cap_disc(0.13, 0.0, "Screen", seg=10)
    plan.circle(0.0, 0.0, 0.25, tag="post")
    plan.wall_items(["vent", "panel"], wall_set(plan), open_every=2, open_kinds=("panel", None), seed=181,
                    depth_of=DEPTHS)
    plan.stands(fu["stands"], [(0.65, 0.0, 180.0)])
    plan.lights([(0.0, 0.0), (0.6, 0.6)], z=2.1)
    plan.aisles(spacing=0.7, clearance=0.30, link=1.2)


INTERIORS = {
    "research_lab": research_lab,
    "research_assembler": research_assembler,
    "airlock": airlock,
    "junction": junction,
}
