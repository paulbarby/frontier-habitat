"""
Frontier Habitat 3.0 - ART-HAB furniture and machine library for the room interiors (Blender 5.2, --background).

Every builder draws in its own local frame at the current transform of the Part (use `with p.at(T(..), RZ(..))`).
F = floor top (0.14).  Heights of the NPC furniture numbers: seat top 0.46, mattress top 0.55, console 1.00,
bench 0.90 (interior_kit constants).  Style: Hull / Frame carcasses with bevels, inset panels and trims; wood only
on small inserts and tops (round-2 critique: about half the wood of the pilot); no plain boxes.

Wall-side items (`wi_*`) are built inside `with wall_slot(rm, k) as p:` : local +X = into the room, back at x = 0,
width w along Y, depth d along X.
"""
import math
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, pi
from mathutils import Vector

import rooms_kit as K
from rooms_kit import T, RX, RY, RZ, S, polar, capsule, tank_v, fan_unit
from interior_kit import (F, bbox, plate_x, plate_y, plate_z, ui_screen, SEAT_Z, BED_Z, CONSOLE_Z, BENCH_Z)

BED_W, BED_L = 0.94, 2.04


# --------------------------------------------------------------------------------------
# Plants, rugs, small things
# --------------------------------------------------------------------------------------
def leafy_plant(p, x, y, z, s=1.0, n=5, seed=1):
    """A plant crown: n bent leaves (double-sided Plant) and a dark core."""
    rng = random.Random(seed)
    p.sphere((x, y, z + 0.10 * s), 0.13 * s, "PlantDark", seg=5, rings=2, smooth=False, scale=(1, 1, 0.8))
    for k in range(n):
        a = 360.0 * k / n + rng.uniform(-12, 12)
        L = s * rng.uniform(0.34, 0.48)
        up = rng.uniform(0.30, 0.60)
        w = 0.07 * s
        with p.at(T(x, y, z + 0.06 * s), RZ(a)):
            mid = Vector((L * 0.55, 0, L * up * 0.9))
            tip = Vector((L, 0, L * up * 0.35))
            p.quad((0, -w * 0.4, 0), (0, w * 0.4, 0), (mid.x, w, mid.z), (mid.x, -w, mid.z), "Plant")
            p.quad((mid.x, -w, mid.z), (mid.x, w, mid.z), (tip.x, w * 0.2, tip.z), (tip.x, -w * 0.2, tip.z),
                   "Plant" if k % 2 else "PlantDark")


def pot_plant(p, x, y, r=0.20, h=0.42, s=1.0, seed=1, pot="Hull", z0=None):
    z0 = F if z0 is None else z0
    p.vcyl(x, y, z0, z0 + h, r * 0.78, r, seg=10, mat=pot, cap0=False, cap1=False)
    p.lathe([(r, z0 + h), (r + 0.015, z0 + h + 0.02), (r - 0.02, z0 + h + 0.02), (r - 0.02, z0 + h - 0.03)], "Frame",
            seg=10)
    with p.at(T(x, y, 0)):
        p.cap_disc(r - 0.02, z0 + h - 0.03, "FloorDark", seg=8)
    leafy_plant(p, x, y, z0 + h - 0.04, s=s, seed=seed)


def tall_plant(p, x, y, seed=3):
    """A tall indoor tree in a square planter (1.5 m)."""
    bbox(p, x - 0.26, x + 0.26, y - 0.26, y + 0.26, F, F + 0.50, "Hull", bevel=0.02)
    plate_z(p, F + 0.505, x - 0.22, x + 0.22, y - 0.22, y + 0.22, "FloorDark")
    p.vcyl(x, y, F + 0.5, F + 1.1, 0.03, seg=5, mat="Frame", cap0=False)
    leafy_plant(p, x, y, F + 1.05, s=1.1, n=8, seed=seed)
    leafy_plant(p, x + 0.05, y - 0.04, F + 0.78, s=0.8, n=6, seed=seed + 7)


def rug_round(p, r, x=0.0, y=0.0, mat="Cushion", ring="Accent", seg=24):
    with p.at(T(x, y, 0)):
        p.lathe([(r, F + 0.004), (r - 0.03, F + 0.012), (r - 0.16, F + 0.012), (r - 0.20, F + 0.012),
                 (0.0, F + 0.012)], lambda k, i: (mat, ring, mat, mat)[k], seg=seg, smooth=False)


def rug_rect(p, hx, hy, mat="Cushion", border="Accent"):
    z = F + 0.012
    bbox(p, -hx, hx, -hy, hy, F, z, border, mats={"-z": None})
    plate_z(p, z + 0.001, -hx + 0.10, hx - 0.10, -hy + 0.10, hy - 0.10, mat)


def floor_line(p, x0, y0, x1, y1, w=0.06, mat="Hazard", z=None):
    """A painted floor line (walkway edge)."""
    z = F + 0.004 if z is None else z
    d = Vector((x1 - x0, y1 - y0, 0))
    if d.length < 1e-6:
        return
    n = Vector((-d.y, d.x, 0)).normalized() * (w / 2)
    a, b = Vector((x0, y0, z)), Vector((x1, y1, z))
    p.quad(tuple(a - n), tuple(b - n), tuple(b + n), tuple(a + n), mat)


def hazard_rect(p, hx, hy, w=0.10, n_per_m=3.0):
    """Striped hazard outline round a machine footprint (Hazard / Rubber) on the floor, local frame."""
    z = F + 0.005
    for (x0, y0, x1, y1) in ((-hx, -hy, hx, -hy), (hx, -hy, hx, hy), (hx, hy, -hx, hy), (-hx, hy, -hx, -hy)):
        L = hypot(x1 - x0, y1 - y0)
        n = max(2, int(L * n_per_m))
        for k in range(n):
            t0, t1 = k / n, (k + 1) / n
            xa, ya = x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0
            xb, yb = x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1
            floor_line(p, xa, ya, xb, yb, w=w, mat="Hazard" if k % 2 == 0 else "Frame", z=z)


def crate(p, x, y, s=0.5, z=None, mat="Hull", band="Frame", yaw=0.0):
    z = F if z is None else z
    with p.at(T(x, y, z), RZ(yaw)):
        bbox(p, -s / 2, s / 2, -s / 2, s / 2, 0.0, s, mat, bevel=0.015)
        bbox(p, -s / 2 - 0.012, s / 2 + 0.012, -s / 2 - 0.012, s / 2 + 0.012, s * 0.40, s * 0.58, band,
             mats={"-z": None, "+z": None})


def pallet(p, x, y, yaw=0.0, load=2, seed=0, mats=("Hull", "Accent", "HullDark")):
    rng = random.Random(seed)
    with p.at(T(x, y, 0), RZ(yaw)):
        bbox(p, -0.6, 0.6, -0.5, 0.5, F, F + 0.12, "Wood", mats={"-z": None})
        for k in range(3):
            plate_x(p, 0.601, -0.45 + 0.35 * k, -0.35 + 0.35 * k, F + 0.02, F + 0.10, "FloorDark")
        if load >= 1:
            crate(p, -0.28, -0.22, s=0.5, z=F + 0.12, mat=rng.choice(mats), band="Frame")
            crate(p, 0.28, 0.20, s=0.5, z=F + 0.12, mat=rng.choice(mats), band="Frame")
        if load >= 2:
            crate(p, 0.0, 0.0, s=0.44, z=F + 0.62, mat=rng.choice(mats), band="Accent")


# --------------------------------------------------------------------------------------
# Seating
# --------------------------------------------------------------------------------------
def chair(p, seat="Cushion", shell="Hull"):
    """Shell chair.  Seat centre at the origin, the sitter faces +X.  Seat top at F + SEAT_Z."""
    zs = F + SEAT_Z
    for sy in (-1, 1):
        p.beam((-0.22, sy * 0.19, F + 0.015), (0.20, sy * 0.19, F + 0.015), 0.035, 0.03, "Frame")
        p.beam((0.13, sy * 0.19, F + 0.03), (0.08, sy * 0.19, zs - 0.07), 0.03, 0.03, "Frame", caps=False)
        p.beam((-0.18, sy * 0.19, F + 0.03), (-0.14, sy * 0.19, zs - 0.07), 0.03, 0.03, "Frame", caps=False)
    bbox(p, -0.21, 0.21, -0.22, 0.22, zs - 0.08, zs - 0.03, shell, bevel=0.015)
    bbox(p, -0.19, 0.20, -0.20, 0.20, zs - 0.04, zs, seat, bevel=0.02)
    with p.at(T(-0.215, 0, zs - 0.03), RY(-9.0)):
        bbox(p, -0.035, 0.0, -0.22, 0.22, 0.0, 0.44, shell, bevel=0.015)
        bbox(p, 0.0, 0.025, -0.18, 0.18, 0.06, 0.38, seat, bevel=0.01)


def office_chair(p, seat="Cushion"):
    """Swivel chair on a star base, seat centre at the origin, faces +X, seat top F + SEAT_Z."""
    zs = F + SEAT_Z
    for k in range(5):
        a = 72.0 * k
        p.beam((0, 0, F + 0.06), (0.28 * cos(radians(a)), 0.28 * sin(radians(a)), F + 0.04), 0.04, 0.03, "Frame")
    p.vcyl(0, 0, F + 0.06, zs - 0.07, 0.03, seg=6, mat="Metal", cap0=False, cap1=False)
    bbox(p, -0.22, 0.22, -0.22, 0.22, zs - 0.07, zs, seat, bevel=0.025)
    bbox(p, -0.26, -0.21, -0.20, 0.20, zs + 0.06, zs + 0.52, seat, bevel=0.02)
    bbox(p, -0.24, -0.22, -0.04, 0.04, zs - 0.05, zs + 0.10, "Frame")


def stool(p, seat="Cushion"):
    p.vcyl(0, 0, F, F + 0.02, 0.17, seg=10, mat="Frame", cap0=False)
    p.vcyl(0, 0, F + 0.02, F + SEAT_Z - 0.06, 0.03, seg=6, mat="Metal", cap0=False, cap1=False)
    p.lathe([(0.19, F + SEAT_Z - 0.07), (0.20, F + SEAT_Z - 0.02), (0.18, F + SEAT_Z), (0.0, F + SEAT_Z)], seat, seg=12)


def sofa(p, n=3, seat_w=0.62, fabric="Cushion", frame="Frame", arm="Hull", pillow_mats=("Fabric", "Accent")):
    """Straight modular sofa facing +X.  Seat centres at x = 0.05, y = (i - (n-1)/2) * seat_w; seat top SEAT_Z.
    Returns the seat centre list [(x, y)]."""
    zs = F + SEAT_Z
    W = n * seat_w
    bbox(p, -0.44, 0.38, -W / 2 - 0.12, W / 2 + 0.12, F + 0.04, F + 0.22, frame, bevel=0.02)       # plinth
    for sy in (-1, 1):
        p.vcyl(0.30, sy * (W / 2 + 0.02), F, F + 0.05, 0.03, seg=6, mat="Metal", cap0=False)
        p.vcyl(-0.36, sy * (W / 2 + 0.02), F, F + 0.05, 0.03, seg=6, mat="Metal", cap0=False)
    seats = []
    for i in range(n):
        y = (i - (n - 1) / 2) * seat_w
        bbox(p, -0.24, 0.36, y - seat_w / 2 + 0.01, y + seat_w / 2 - 0.01, F + 0.22, zs, fabric, bevel=0.04)
        bbox(p, -0.44, -0.24, y - seat_w / 2 + 0.01, y + seat_w / 2 - 0.01, F + 0.22, zs + 0.42, fabric, bevel=0.05)
        seats.append((0.05, y))
    for sy in (-1, 1):
        bbox(p, -0.44, 0.38, sy * (W / 2) + (0.0 if sy > 0 else -0.12), sy * (W / 2) + (0.12 if sy > 0 else 0.0),
             F + 0.04, zs + 0.16, arm, bevel=0.035)
    for k, y in enumerate([seats[0][1], seats[-1][1]] if n > 1 else [seats[0][1]]):
        with p.at(T(-0.20, y, zs + 0.18), RY(-18.0)):
            bbox(p, -0.06, 0.06, -0.20, 0.20, -0.16, 0.16, pillow_mats[k % 2], bevel=0.05)
    return seats


def coffee_table(p, hx=0.55, hy=0.35, top="Wood"):
    bbox(p, -hx, hx, -hy, hy, F + 0.36, F + 0.40, top, bevel=0.012)
    bbox(p, -hx + 0.05, hx - 0.05, -hy + 0.05, hy - 0.05, F + 0.08, F + 0.11, "Frame")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bbox(p, sx * (hx - 0.06) - 0.02, sx * (hx - 0.06) + 0.02, sy * (hy - 0.06) - 0.02, sy * (hy - 0.06) + 0.02,
                 F, F + 0.36, "Frame", mats={"-z": None, "+z": None})


def table_round(p, r=0.62, h=0.74, top="Wood", seg=18, edge="Accent"):
    p.lathe([(r * 0.46, F), (r * 0.44, F + 0.03), (0.07, F + 0.05), (0.0, F + 0.05)], "Frame", seg=10, smooth=False)
    p.vcyl(0, 0, F + 0.04, F + h - 0.06, 0.06, seg=8, mat="Metal", cap0=False, cap1=False)
    p.lathe([(0.20, F + h - 0.06), (0.20, F + h - 0.035), (0.0, F + h - 0.035)], "Frame", seg=8, smooth=False)
    p.lathe([(r - 0.01, F + h - 0.035), (r, F + h - 0.015), (r - 0.012, F + h), (0.0, F + h)],
            lambda k, i: edge if k == 0 else top, seg=seg, smooth=False)


def table_rect(p, hx, hy, h=0.74, top="Hull", edge="Frame", legs="Frame"):
    """Rectangular table centred at the origin (half sizes hx, hy)."""
    bbox(p, -hx, hx, -hy, hy, F + h - 0.045, F + h, top, bevel=0.012)
    plate_x(p, hx + 0.001, -hy + 0.01, hy - 0.01, F + h - 0.04, F + h - 0.008, edge)
    plate_x(p, -hx - 0.001, -hy + 0.01, hy - 0.01, F + h - 0.04, F + h - 0.008, edge, facing=-1)
    for sx in (-1, 1):
        bbox(p, sx * (hx - 0.10) - 0.03, sx * (hx - 0.10) + 0.03, -hy + 0.08, hy - 0.08, F, F + 0.04, legs,
             mats={"-z": None})
        bbox(p, sx * (hx - 0.10) - 0.025, sx * (hx - 0.10) + 0.025, -0.03, 0.03, F + 0.04, F + h - 0.045, legs,
             mats={"-z": None, "+z": None})
    bbox(p, -hx + 0.10, hx - 0.10, -0.025, 0.025, F + h - 0.20, F + h - 0.15, legs)


# --------------------------------------------------------------------------------------
# Beds
# --------------------------------------------------------------------------------------
def bed(p, dressing=0, pillows=1, blanket="Fabric", throw="Cushion", side=1, hb=None, style=0):
    """Single bed.  Bed centre at the origin, head toward +Y, stand point at (+0.55 * side, 0).
    dressing 0: flat blanket; 1: turned down at the head (25 cm of white sheet shows); 2: a folded throw at the foot.
    hb: optional separate Part for the headboard (a hidable Tall part; built with the same world transform)."""
    W, L = BED_W, BED_L
    zt = F + BED_Z
    if style == 1:
        # raised frame on four legs (open underneath) with a low footboard
        for sx in (-1, 1):
            for sy in (-1, 1):
                bbox(p, sx * (W / 2 - 0.05) - 0.03, sx * (W / 2 - 0.05) + 0.03, sy * (L / 2 - 0.06) - 0.03,
                     sy * (L / 2 - 0.06) + 0.03, F, zt - 0.24, "Frame", mats={"-z": None, "+z": None})
        bbox(p, -W / 2, W / 2, -L / 2, L / 2 - 0.02, zt - 0.24, zt - 0.15, "Hull")
        bbox(p, -W / 2 - 0.02, W / 2 + 0.02, -L / 2 - 0.05, -L / 2 + 0.01, F, zt + 0.12, "Frame", mats={"-z": None})
    else:
        bbox(p, -W / 2 + 0.08, W / 2 - 0.08, -L / 2 + 0.10, L / 2 - 0.16, F, F + 0.11, "FloorDark", mats={"-z": None})
        bbox(p, -W / 2, W / 2, -L / 2, L / 2 - 0.02, F + 0.10, zt - 0.15, "Hull", bevel=0.025)
        xs = side * (W / 2 + 0.003)
        if style == 2:
            # storage base: two deep drawers with handles on the stand side
            for (y0, y1) in ((-L / 2 + 0.08, -0.04), (0.04, L / 2 - 0.16)):
                plate_x(p, xs, y0, y1, F + 0.14, zt - 0.19, "HullDark", facing=side)
                plate_x(p, xs + side * 0.003, (y0 + y1) / 2 - 0.12, (y0 + y1) / 2 + 0.12, zt - 0.26, zt - 0.24,
                        "Frame", facing=side)
        else:
            for (y0, y1) in ((-L / 2 + 0.10, -0.06), (0.02, L / 2 - 0.20)):
                plate_x(p, xs, y0, y1, F + 0.16, zt - 0.21, "FloorDark", facing=side)
                plate_x(p, xs + side * 0.002, y0 + 0.30, y1 - 0.30, zt - 0.245, zt - 0.23, "Frame", facing=side)
    bbox(p, -W / 2 + 0.03, W / 2 - 0.03, -L / 2 + 0.04, L / 2 - 0.08, zt - 0.16, zt, "Hull", bevel=0.045)
    # blanket: 3.5 cm overhang on the sides and the foot, 1.5 cm bevel
    yb = {0: L / 2 - 0.50, 1: L / 2 - 0.78, 2: L / 2 - 0.50}[dressing]
    bbox(p, -W / 2 - 0.035, W / 2 + 0.035, -L / 2 - 0.035, yb, zt - 0.13, zt + 0.03, blanket, bevel=0.015)
    if dressing == 1:
        # the turned-down fold: a rolled edge and the white sheet above it
        p.cyl((-W / 2 - 0.02, yb, zt + 0.02), (W / 2 + 0.02, yb, zt + 0.02), 0.045, seg=6, mat=blanket)
        bbox(p, -W / 2 + 0.02, W / 2 - 0.02, yb + 0.02, yb + 0.27, zt - 0.02, zt + 0.012, "Hull", bevel=0.01)
    if dressing == 2:
        bbox(p, -W / 2 - 0.05, W / 2 + 0.05, -L / 2 + 0.10, -L / 2 + 0.46, zt + 0.03, zt + 0.085, throw, bevel=0.02)
    # pillows
    if pillows == 1:
        bbox(p, -0.31, 0.31, L / 2 - 0.46, L / 2 - 0.12, zt - 0.01, zt + 0.12, "Hull", bevel=0.05)
    else:
        for sx in (-1, 1):
            with p.at(T(sx * 0.20, L / 2 - 0.30, zt + 0.05), RZ(sx * 4.0)):
                bbox(p, -0.19, 0.19, -0.15, 0.15, -0.06, 0.07, "Hull", bevel=0.05)
    # headboard: 0.80 m, a Cushion pad on the top 30 cm with the reading light strip
    q = hb if hb is not None else p
    ctx = q.at(p._stack[-1]) if hb is not None else _null()
    with ctx:
        yh = L / 2 + 0.02
        if style == 1:
            # slatted headboard: two posts, a top rail and five slats
            for sx in (-1, 1):
                bbox(q, sx * (W / 2 + 0.02) - 0.03, sx * (W / 2 + 0.02) + 0.03, yh - 0.03, yh + 0.04, F, F + 0.82,
                     "Frame", mats={"-z": None})
            bbox(q, -W / 2 - 0.05, W / 2 + 0.05, yh - 0.03, yh + 0.04, F + 0.74, F + 0.82, "Hull")
            for k in range(4):
                xx = -W / 2 + 0.14 + (W - 0.28) * k / 3
                bbox(q, xx - 0.035, xx + 0.035, yh - 0.015, yh + 0.025, zt - 0.10, F + 0.74, "Hull")
            bbox(q, -W / 2 + 0.06, W / 2 - 0.06, yh - 0.04, yh - 0.03, F + 0.80, F + 0.81, "LightStrip")
        elif style == 2:
            # wingback: a tall rounded pad over a base panel
            bbox(q, -W / 2 - 0.05, W / 2 + 0.05, yh - 0.02, yh + 0.06, F, F + 0.60, "Hull", mats={"-z": None})
            q.cyl((-W / 2 - 0.06, yh + 0.01, F + 0.72), (W / 2 + 0.06, yh + 0.01, F + 0.72), 0.14, seg=6,
                  mat="Cushion")
            bbox(q, -W / 2 - 0.06, W / 2 + 0.06, yh - 0.05, yh + 0.07, F + 0.56, F + 0.72, "Cushion")
            plate_y(q, yh - 0.0505, -W / 2 + 0.04, W / 2 - 0.04, F + 0.58, F + 0.60, "LightStrip", facing=-1)
        else:
            bbox(q, -W / 2 - 0.05, W / 2 + 0.05, yh - 0.02, yh + 0.05, F, F + 0.50, "Hull", bevel=0.015)
            bbox(q, -W / 2 - 0.05, W / 2 + 0.05, yh - 0.05, yh + 0.05, F + 0.50, F + 0.80, "Cushion", bevel=0.03)
            bbox(q, -W / 2 + 0.06, W / 2 - 0.06, yh - 0.02, yh + 0.03, F + 0.80, F + 0.82, "LightStrip")
            plate_y(q, yh - 0.0205, -W / 2 + 0.02, W / 2 - 0.02, F + 0.46, F + 0.49, "Frame", facing=-1)


class _null:
    def __enter__(self):
        return None

    def __exit__(self, *exc):
        return False


PERSONAL = ("books", "cup", "plant", "tablet", "photo", None)


def bedside(p, lamp=True, item=None, seed=0, lamp_cb=None):
    """Bedside unit at the origin: 0.44 (X) x 0.40 (Y), front toward -Y.  Hull carcass, wood top, a warm lamp,
    a personal item.  lamp_cb(x, y, z) receives the lamp position (local)."""
    bbox(p, -0.22, 0.22, -0.20, 0.20, F, F + 0.52, "Hull", bevel=0.02)
    bbox(p, -0.225, 0.225, -0.205, 0.205, F + 0.52, F + 0.55, "Wood", bevel=0.008)
    plate_y(p, -0.203, -0.18, 0.18, F + 0.30, F + 0.48, "FloorDark", facing=-1)
    plate_y(p, -0.206, -0.06, 0.06, F + 0.44, F + 0.455, "Frame", facing=-1)
    plate_y(p, -0.203, -0.18, 0.18, F + 0.06, F + 0.26, "FloorDark", facing=-1)
    zt = F + 0.55
    if lamp:
        p.vcyl(0.08, 0.05, zt, zt + 0.03, 0.07, seg=8, mat="Frame", cap0=False)
        p.vcyl(0.08, 0.05, zt + 0.03, zt + 0.22, 0.012, seg=4, mat="Metal", cap0=False, cap1=False)
        with p.at(T(0.08, 0.05, 0)):
            p.lathe([(0.11, zt + 0.17), (0.08, zt + 0.33), (0.0, zt + 0.33)], "Window", seg=10, smooth=False)
        if lamp_cb:
            lamp_cb(0.08, 0.05, zt + 0.25)
    if item == "books":
        for j, (m, h) in enumerate((("Accent", 0.035), ("Fabric", 0.03), ("Cushion", 0.03))):
            z0 = zt + sum((0.035, 0.03, 0.03)[:j])
            with p.at(T(-0.09, -0.02, z0), RZ(8.0 * j - 6.0)):
                bbox(p, -0.08, 0.08, -0.11, 0.11, 0.0, h, m)
    elif item == "cup":
        p.vcyl(-0.10, -0.06, zt, zt + 0.09, 0.035, seg=8, mat="Accent", cap0=False)
    elif item == "plant":
        pot_plant(p, -0.10, -0.04, r=0.06, h=0.08, s=0.25, seed=seed, z0=zt)
    elif item == "tablet":
        with p.at(T(-0.08, -0.05, zt), RZ(12.0)):
            bbox(p, -0.09, 0.09, -0.12, 0.12, 0.0, 0.01, "Frame")
            plate_z(p, 0.011, -0.08, 0.08, -0.11, 0.11, "Screen")
    elif item == "photo":
        with p.at(T(-0.10, 0.08, zt), RZ(-20.0)):
            with p.at(RX(-12.0)):
                bbox(p, -0.07, 0.07, -0.01, 0.01, 0.0, 0.17, "Frame")
                plate_y(p, -0.0105, -0.055, 0.055, 0.02, 0.15, "Accent", facing=-1)


def curtain_screen(p, L, h=1.30, panel="Frost", edge="Frame"):
    """(critic round 4) Privacy curtain: two slim posts on feet, a top rail, pleated frosted panels hanging from it
    (neutral, light).  Along local X, centred at the origin."""
    # a floor rail and a Frame border (no legs), 5 cm thick
    bbox(p, -L / 2, L / 2, -0.035, 0.035, F, F + 0.06, edge)
    for sx in (-1, 1):
        x = sx * (L / 2 - 0.02)
        bbox(p, x - 0.02, x + 0.02, -0.025, 0.025, F + 0.06, F + h, edge)
    bbox(p, -L / 2, L / 2, -0.025, 0.025, F + h - 0.04, F + h, edge)
    npl = max(3, int((L - 0.1) / 0.24))
    w = (L - 0.12) / npl
    for k in range(npl):
        x0 = -L / 2 + 0.06 + w * k
        off = 0.018 if k % 2 else -0.018
        bbox(p, x0, x0 + w + 0.004, off - 0.008, off + 0.008, F + 0.16, F + h - 0.05, panel)


def privacy_screen(p, L, h=1.20, panel="Cushion", edge="Frame"):
    """Free-standing privacy screen along local X (length L), centred at the origin, 5 cm thick, on two feet."""
    bbox(p, -L / 2, L / 2, -0.03, 0.03, F + 0.10, F + h, edge, bevel=0.01)
    for sy in (-1, 1):
        plate_y(p, sy * 0.031, -L / 2 + 0.05, L / 2 - 0.05, F + 0.16, F + h - 0.06, panel, facing=sy)
    for sx in (-1, 1):
        bbox(p, sx * (L / 2 - 0.12) - 0.04, sx * (L / 2 - 0.12) + 0.04, -0.22, 0.22, F, F + 0.10, edge, bevel=0.01)


# --------------------------------------------------------------------------------------
# Work furniture
# --------------------------------------------------------------------------------------
def console(p, w=1.0, glow="Screen", body="Hull", stripe="Accent"):
    """Standing console.  The body is behind x = 0 (x in -0.55..0); the operator stands at (+CONSOLE_AHEAD, 0)
    facing -X.  Desk height CONSOLE_Z (1.00)."""
    zt = F + CONSOLE_Z
    bbox(p, -0.55, -0.05, -w / 2, w / 2, F, zt - 0.10, body, bevel=0.02)
    plate_x(p, -0.048, -w / 2 + 0.05, w / 2 - 0.05, F + 0.12, F + 0.30, "FloorDark")
    plate_x(p, -0.047, -w / 2 + 0.05, w / 2 - 0.05, zt - 0.22, zt - 0.18, stripe)
    with p.at(T(-0.05, 0, zt - 0.10), RY(-14.0)):
        bbox(p, -0.45, 0.02, -w / 2, w / 2, 0.0, 0.08, "Frame", bevel=0.01)
        plate_z(p, 0.081, -0.40, -0.05, -w / 2 + 0.06, w / 2 - 0.06, "Screen")
    with p.at(T(-0.50, 0, zt + 0.05), RY(-10.0)):
        bbox(p, -0.04, 0.02, -w / 2 + 0.04, w / 2 - 0.04, 0.0, 0.48, "Frame")
        plate_x(p, 0.021, -w / 2 + 0.08, w / 2 - 0.08, 0.05, 0.44, "Screen")
        plate_x(p, 0.023, -w / 2 + 0.10, -w / 2 + 0.10 + (w - 0.2) * 0.6, 0.36, 0.40, "LightStrip")
        plate_x(p, 0.023, -w / 2 + 0.10, -w / 2 + 0.10 + (w - 0.2) * 0.35, 0.10, 0.13, "LightStrip")


def workbench(p, w=1.8, d=0.75, top="Metal", stripe="Accent", tools=True, seed=0):
    """Bench: body behind x = 0 (x in -d..0); the worker stands at (+BENCH_AHEAD... x = +0.40, 0) facing -X.
    Top at BENCH_Z (0.90).  A back board with tools."""
    zt = F + BENCH_Z
    bbox(p, -d, 0.0, -w / 2, w / 2, zt - 0.05, zt, top, bevel=0.01)
    for sy in (-1, 1):
        bbox(p, -d + 0.05, -0.05, sy * (w / 2 - 0.06) - 0.03, sy * (w / 2 - 0.06) + 0.03, F, zt - 0.05, "Frame",
             mats={"-z": None, "+z": None})
    bbox(p, -d + 0.04, -0.06, -w / 2 + 0.04, w / 2 - 0.04, F + 0.18, F + 0.22, "Frame")
    bbox(p, -d + 0.08, -0.10, -w * 0.45, -w * 0.05, F + 0.22, zt - 0.08, "Hull", bevel=0.01)
    plate_x(p, -0.099, -w * 0.43, -w * 0.07, zt - 0.20, zt - 0.17, stripe)
    bbox(p, -d, -d + 0.04, -w / 2, w / 2, zt, zt + 0.55, "HullDark")
    if tools:
        rng = random.Random(seed)
        for k in range(5):
            y = -w / 2 + 0.15 + (w - 0.3) * k / 4
            h = rng.uniform(0.12, 0.26)
            bbox(p, -d + 0.04, -d + 0.07, y - 0.02, y + 0.02, zt + 0.25, zt + 0.25 + h, rng.choice(("Metal", "Hazard", "Frame")))
        bbox(p, -d + 0.10, -d + 0.40, w * 0.15, w * 0.35, zt, zt + 0.16, "Accent", bevel=0.01)
        bbox(p, -0.40, -0.20, -w * 0.30, -w * 0.10, zt, zt + 0.05, "Frame")


def desk(p, w=1.2, d=0.65, monitors=2, lamp_cb=None, seed=0):
    """Desk: body behind x = 0 (x in -d..0), top 0.74.  The sitter's stand point is (+0.12, 0) facing -X; the
    chair seat centre is 0.30 behind it at (+0.42, 0).  Monitors glow (Screen)."""
    zt = F + 0.74
    bbox(p, -d, 0.0, -w / 2, w / 2, zt - 0.035, zt, "Hull", bevel=0.01)
    plate_x(p, 0.001, -w / 2 + 0.01, w / 2 - 0.01, zt - 0.03, zt - 0.006, "Accent")
    for sy in (-1, 1):
        bbox(p, -d + 0.03, -0.05, sy * (w / 2 - 0.04) - 0.02, sy * (w / 2 - 0.04) + 0.02, F, zt - 0.035, "Frame",
             mats={"-z": None, "+z": None})
    bbox(p, -d + 0.05, -0.12, w * 0.12, w / 2 - 0.06, F + 0.05, zt - 0.06, "FloorDark", bevel=0.01)
    for m in range(monitors):
        y = 0.0 if monitors == 1 else (-0.24 + 0.48 * m) * (w / 1.2)
        with p.at(T(-d * 0.72, y, zt), RZ(12.0 * (1 if y < 0 else -1) if monitors > 1 else 0.0)):
            bbox(p, -0.06, 0.06, -0.05, 0.05, 0.0, 0.02, "Frame")
            bbox(p, -0.02, 0.02, -0.02, 0.02, 0.02, 0.16, "Frame")
            bbox(p, -0.02, 0.01, -0.26, 0.26, 0.12, 0.44, "Frame", bevel=0.005)
            plate_x(p, 0.011, -0.24, 0.24, 0.14, 0.42, "Screen")
    bbox(p, -0.30, -0.12, -0.20, 0.20, zt, zt + 0.015, "Frame")
    if lamp_cb:
        y = w / 2 - 0.14
        p.vcyl(-d + 0.12, y, zt, zt + 0.02, 0.06, seg=8, mat="Frame", cap0=False)
        p.beam((-d + 0.12, y, zt + 0.02), (-d + 0.18, y, zt + 0.36), 0.02, 0.02, "Metal")
        with p.at(T(-d + 0.26, y, zt + 0.36), RY(35.0)):
            p.lathe([(0.07, -0.06), (0.03, 0.02), (0.0, 0.02)], "Window", seg=8, smooth=False)
        lamp_cb(-d + 0.26, y, zt + 0.30)


def ui_screen_small(p, w, h):
    """A small upright screen on a foot, facing +X."""
    bbox(p, -0.05, 0.05, -0.06, 0.06, 0.0, 0.02, "Frame")
    bbox(p, -0.015, 0.015, -0.02, 0.02, 0.02, 0.10, "Frame")
    bbox(p, -0.02, 0.0, -w / 2, w / 2, 0.10, 0.10 + h, "HullDark")
    plate_x(p, 0.001, -w / 2 + 0.02, w / 2 - 0.02, 0.12, 0.08 + h, "Screen")


def lab_bench(p, w=1.8, d=0.75, seed=0, glow="Glow"):
    """Lab bench (bench height) with glassware, a sample rack and a shelf; worker at (+0.40, 0) facing -X."""
    workbench(p, w=w, d=d, top="Hull", tools=False)
    zt = F + BENCH_Z
    rng = random.Random(seed)
    for k in range(4):
        y = -w / 2 + 0.25 + (w - 0.5) * k / 3
        m = "Glass" if k % 2 == 0 else glow
        p.vcyl(-d * 0.55, y, zt, zt + rng.uniform(0.14, 0.24), 0.05 + 0.02 * (k % 2), seg=8, mat=m, cap0=False)
    bbox(p, -d + 0.04, -d + 0.30, -0.1, 0.35, zt + 0.30, zt + 0.33, "Frame")
    for j in range(5):
        p.vcyl(-d + 0.17, -0.05 + 0.08 * j, zt + 0.33, zt + 0.43, 0.018, seg=6, mat=("Accent", glow, "Glass")[j % 3],
               cap0=False)
    # (critic round 4) equipment on the bench: a microscope, a centrifuge and an analysis screen
    ym = -w / 2 + 0.34
    big = p.at(T(-0.20, ym, zt), S(1.3, 1.3, 1.3), T(0.20, -ym, -zt))
    big.__enter__()
    bbox(p, -0.30, -0.10, ym - 0.10, ym + 0.10, zt, zt + 0.04, "Frame")
    bbox(p, -0.28, -0.22, ym - 0.03, ym + 0.03, zt + 0.04, zt + 0.30, "Hull")
    with p.at(T(-0.20, ym, zt + 0.28), RY(35.0)):
        p.vcyl(0, 0, -0.02, 0.12, 0.025, seg=6, mat="HullDark")
    p.vcyl(-0.16, ym, zt + 0.04, zt + 0.12, 0.045, seg=6, mat="Frame", cap0=False)
    big.__exit__(None, None, None)
    yc = w / 2 - 0.36
    big = p.at(T(-0.25, yc, zt), S(1.3, 1.3, 1.3), T(0.25, -yc, -zt))
    big.__enter__()
    p.vcyl(-0.25, yc, zt, zt + 0.16, 0.14, seg=10, mat="Hull", cap0=False)
    p.vcyl(-0.25, yc, zt + 0.16, zt + 0.19, 0.12, seg=10, mat="Accent", cap0=False)
    plate_x(p, -0.109, yc - 0.06, yc + 0.06, zt + 0.05, zt + 0.08, "Screen", facing=1)
    big.__exit__(None, None, None)
    with p.at(T(-d + 0.10, 0.10, zt + 0.02), S(1.3, 1.3, 1.3)):
        ui_screen_small(p, 0.36, 0.24)


# --------------------------------------------------------------------------------------
# Wall-side items: local +X into the room, back at x = 0, width w (Y), depth d (X)
# --------------------------------------------------------------------------------------
def wi_wardrobe(p, w=0.80, d=0.42, h=1.26, insert="Wood", stripe="Accent"):
    """Hull carcass with a Frame edge; the wood is only a narrow insert panel on each door."""
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + h, "Hull", bevel=0.02)
    for sy in (-1, 1):
        y0, y1 = (0.012, w / 2 - 0.03) if sy > 0 else (-w / 2 + 0.03, -0.012)
        plate_x(p, d + 0.004, y0, y1, F + 0.06, F + h - 0.06, "Frame")
        plate_x(p, d + 0.006, y0 + 0.03, y1 - 0.03, F + 0.09, F + h - 0.09, "Hull")
        plate_x(p, d + 0.008, y0 + 0.05, y1 - 0.05, F + h * 0.52, F + h - 0.14, insert)
    plate_x(p, d + 0.01, -0.012, 0.012, F + 0.45, F + 0.95, "LightStrip")
    plate_x(p, d + 0.009, -w / 2 + 0.06, -w / 2 + 0.20, F + h - 0.075, F + h - 0.035, stripe)
    bbox(p, 0.02, d - 0.02, -w / 2 + 0.03, w / 2 - 0.03, F, F + 0.05, "FloorDark", mats={"-z": None})


def wi_lockers(p, w=0.80, d=0.40, h=1.20, n=3, stripe="Accent"):
    """A bank of narrow lockers with vents and number tags."""
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + h, "Hull", bevel=0.015)
    lw = (w - 0.04) / n
    for i in range(n):
        y0 = -w / 2 + 0.02 + lw * i
        plate_x(p, d + 0.004, y0 + 0.01, y0 + lw - 0.01, F + 0.06, F + h - 0.05, "FloorDark" if i % 2 else "Frame")
        for z in (F + h - 0.20, F + h - 0.25):
            plate_x(p, d + 0.006, y0 + 0.05, y0 + lw - 0.05, z, z + 0.02, "Hull")
        plate_x(p, d + 0.006, y0 + 0.04, y0 + 0.09, F + h * 0.55, F + h * 0.55 + 0.05, stripe)


def wi_cabinet(p, w=0.80, d=0.42, h=0.90, top="Wood", deco=None, seed=0, lamp_cb=None):
    """Low cabinet (Hull carcass, wood top) with things on top: 'plant', 'books', 'lamp', 'lamp+plant', ..."""
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + h - 0.03, "Hull", bevel=0.015)
    bbox(p, -0.005, d + 0.02, -w / 2 - 0.01, w / 2 + 0.01, F + h - 0.03, F + h, top)
    for sy in (-1, 1):
        y0, y1 = (0.01, w / 2 - 0.03) if sy > 0 else (-w / 2 + 0.03, -0.01)
        plate_x(p, d + 0.004, y0, y1, F + 0.08, F + h - 0.10, "FloorDark")
        plate_x(p, d + 0.006, y0 + 0.04, y1 - 0.04, F + h - 0.16, F + h - 0.14, "Frame")
    zt = F + h
    deco = deco or ""
    if "plant" in deco:
        p.vcyl(d * 0.5, -w * 0.22, zt, zt + 0.16, 0.08, 0.10, seg=8, mat="Hull", cap0=False)
        leafy_plant(p, d * 0.5, -w * 0.22, zt + 0.14, s=min(0.42, max(0.2, (0.28 * w - 0.03) / 0.48)), n=6, seed=seed)
    if "books" in deco:
        for j, (mat, hh) in enumerate((("Accent", 0.20), ("Cushion", 0.23), ("Hull", 0.18), ("Fabric", 0.21))):
            bbox(p, d * 0.25, d * 0.80, -w * 0.30 + 0.045 * j, -w * 0.30 + 0.045 * j + 0.04, zt, zt + hh, mat)
    if "lamp" in deco:
        p.vcyl(d * 0.5, w * 0.24, zt, zt + 0.03, 0.06, seg=8, mat="Frame", cap0=False)
        p.vcyl(d * 0.5, w * 0.24, zt + 0.03, zt + 0.22, 0.01, seg=4, mat="Metal", cap0=False, cap1=False)
        with p.at(T(d * 0.5, w * 0.24, 0)):
            p.lathe([(0.10, zt + 0.17), (0.075, zt + 0.31), (0.0, zt + 0.31)], "Window", seg=10, smooth=False)
        if lamp_cb:
            lamp_cb(d * 0.5, w * 0.24, zt + 0.26)
    if "box" in deco:
        crate(p, d * 0.5, w * 0.1, s=0.26, z=zt, mat="Hull", band="Accent")


def wi_shelf(p, w=0.80, d=0.36, h=1.20, seed=2, mats=("Hull", "Accent", "Cushion", "HullDark")):
    rng = random.Random(seed)
    for sy in (-1, 1):
        bbox(p, 0.0, d, sy * (w / 2) - 0.025, sy * (w / 2) + 0.025, F, F + h, "Frame")
    plate_x(p, 0.02, -w / 2, w / 2, F, F + h, "HullDark")
    for j in range(4):
        z = F + 0.06 + (h - 0.08) * j / 3.0
        bbox(p, 0.02, d, -w / 2 + 0.025, w / 2 - 0.025, z - 0.025, z, "Hull" if j else "Frame")
        if j == 3:
            break
        y = -w / 2 + 0.06
        while y < w / 2 - 0.12:
            bw = rng.uniform(0.10, 0.22)
            bh = rng.uniform(0.14, 0.26)
            if rng.random() < 0.8:
                bbox(p, 0.05, d - 0.05, y, min(w / 2 - 0.05, y + bw), z, z + bh, rng.choice(mats))
            y += bw + 0.03


def wi_planter(p, w=0.80, d=0.36, h=0.46, seed=3):
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + h, "Hull", bevel=0.02)
    plate_x(p, d + 0.004, -w / 2 + 0.04, w / 2 - 0.04, F + h - 0.10, F + h - 0.07, "LightStrip")
    plate_z(p, F + h - 0.02, 0.03, d - 0.03, -w / 2 + 0.03, w / 2 - 0.03, "Soil")
    smax = max(0.2, (0.28 * w - 0.03) / 0.48)
    for j, yy in enumerate((-w * 0.22, 0.0, w * 0.22)):
        leafy_plant(p, d / 2, yy, F + h - 0.04, s=min(smax * (1.25 if j == 1 else 1.0), 0.55), seed=seed + j, n=5)


def wi_desk(p, w=0.80, d=0.44, seed=0):
    zt = F + 0.74
    bbox(p, 0.0, d, -w / 2, w / 2, zt - 0.035, zt, "Wood", bevel=0.01)
    for sy in (-1, 1):
        bbox(p, 0.0, d - 0.06, sy * (w / 2 - 0.06) - 0.02, sy * (w / 2 - 0.06) + 0.02, F, zt - 0.035, "Frame",
             mats={"-z": None})
    with p.at(T(0.03, 0, zt + 0.33)):
        ui_screen(p, w * 0.78, 0.42, seed=seed)
    bbox(p, 0.06, 0.22, -0.10, 0.10, zt, zt + 0.015, "Frame")
    with p.at(T(d - 0.12, w * 0.12, 0)):
        stool(p)


def wi_tap(p, w=0.62, d=0.40):
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + 0.95, "Hull", bevel=0.02)
    plate_x(p, d + 0.004, -w / 2 + 0.05, w / 2 - 0.05, F + 0.10, F + 0.62, "FloorDark")
    plate_x(p, d + 0.006, -w / 2 + 0.05, w / 2 - 0.05, F + 0.86, F + 0.89, "LightStrip")
    p.vcyl(d * 0.45, 0, F + 0.95, F + 1.30, 0.13, seg=10, mat="WaterBlue", cap0=False)
    p.vcyl(d * 0.45, 0, F + 1.30, F + 1.34, 0.06, seg=8, mat="WaterBlue", cap0=False)
    bbox(p, d - 0.02, d + 0.08, -0.03, 0.03, F + 0.78, F + 0.82, "Metal")
    bbox(p, d - 0.10, d + 0.06, -0.12, 0.12, F + 0.64, F + 0.66, "Frame")


def wi_panel(p, w=0.70, d=0.08, seed=0):
    """Open wall: a wall screen with a UI pattern."""
    with p.at(T(0.03, 0, F + 0.92)):
        ui_screen(p, min(0.66, w - 0.1), 0.38, seed=seed)


def wi_vent(p, w=0.70, d=0.08, seed=0):
    """Open wall: a vent grille with slats and a small fan housing."""
    ww = min(0.6, w - 0.1)
    bbox(p, 0.0, 0.05, -ww / 2, ww / 2, F + 0.42, F + 0.86, "Frame", bevel=0.008)
    for j in range(6):
        z = F + 0.47 + 0.065 * j
        bbox(p, 0.05, 0.075, -ww / 2 + 0.04, ww / 2 - 0.04, z, z + 0.03, "HullDark")


POSTER = (("Cushion", "Accent"), ("HullDark", "Fabric"), ("Accent", "Cushion"), ("Cushion", "Fabric"))


def wi_poster(p, w=0.70, d=0.08, seed=0, colours=POSTER):
    """Open wall: a framed poster (abstract planet and rings, no text)."""
    bg, fg = colours[seed % len(colours)]
    ww = min(0.52, w - 0.14)
    bbox(p, 0.0, 0.03, -ww / 2, ww / 2, F + 0.62, F + 1.18, "Frame")
    plate_x(p, 0.031, -ww / 2 + 0.03, ww / 2 - 0.03, F + 0.65, F + 1.15, bg)
    with p.at(T(0.034, 0, F + 0.92), RY(90.0)):
        p.cap_disc(ww * 0.22, 0.0, fg, seg=12)
    plate_x(p, 0.035, -ww * 0.40, ww * 0.40, F + 0.90, F + 0.925, "Hull")


def wi_plant(p, w=0.70, d=0.40, seed=0):
    """Open wall: a floor plant in a pot."""
    pot_plant(p, 0.22, 0.0, r=0.17, h=0.40, s=min(0.9, (w / 2 - 0.04) / 0.48), seed=seed)


def wi_medcab(p, w=0.80, d=0.36, h=1.20):
    """Medicine cabinet: frosted doors, an accent cross, a sink shelf."""
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + h, "Hull", bevel=0.015)
    for sy in (-1, 1):
        y0, y1 = (0.01, w / 2 - 0.03) if sy > 0 else (-w / 2 + 0.03, -0.01)
        plate_x(p, d + 0.004, y0, y1, F + h * 0.45, F + h - 0.05, "Frost")
        plate_x(p, d + 0.004, y0, y1, F + 0.06, F + h * 0.42, "FloorDark")
    plate_x(p, d + 0.007, -0.10, 0.10, F + h * 0.70, F + h * 0.76, "Accent")
    plate_x(p, d + 0.007, -0.03, 0.03, F + h * 0.63, F + h * 0.83, "Accent")


def wi_toolwall(p, w=0.80, d=0.30, seed=0):
    """Pegboard with tools and a low tool chest."""
    rng = random.Random(seed)
    bbox(p, 0.0, 0.03, -w / 2, w / 2, F + 0.60, F + 1.30, "HullDark")
    for k in range(7):
        y = -w / 2 + 0.08 + (w - 0.16) * k / 6
        hh = rng.uniform(0.12, 0.30)
        bbox(p, 0.03, 0.06, y - 0.02, y + 0.02, F + 1.15 - hh, F + 1.15, rng.choice(("Metal", "Hazard", "Frame", "Accent")))
    bbox(p, 0.0, d, -w / 2 + 0.05, w / 2 - 0.05, F, F + 0.55, "Accent", bevel=0.015)
    for j in range(3):
        plate_x(p, d + 0.004, -w / 2 + 0.08, w / 2 - 0.08, F + 0.07 + 0.16 * j, F + 0.19 + 0.16 * j, "Frame")


def wi_rack(p, w=0.80, d=0.42, h=1.30, seed=0, mats=("Cargo", "Accent", "Hull")):
    """Heavy storage rack with boxes (logistics)."""
    wi_shelf(p, w=w, d=d, h=h, seed=seed, mats=mats)


def wi_fridge(p, w=0.70, d=0.42, h=1.26, mat="Hull"):
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + h, mat, bevel=0.025)
    plate_x(p, d + 0.004, -w / 2 + 0.03, w / 2 - 0.03, F + h * 0.62, F + h - 0.04, "Frame")
    plate_x(p, d + 0.005, -w / 2 + 0.05, w / 2 - 0.05, F + h * 0.64, F + h - 0.06, mat)
    plate_x(p, d + 0.004, -w / 2 + 0.03, w / 2 - 0.03, F + 0.05, F + h * 0.60, "Frame")
    plate_x(p, d + 0.005, -w / 2 + 0.05, w / 2 - 0.05, F + 0.07, F + h * 0.58, mat)
    bbox(p, d, d + 0.04, w / 2 - 0.10, w / 2 - 0.07, F + h * 0.30, F + h * 0.85, "Metal")
    plate_x(p, d + 0.007, -0.1, 0.1, F + h * 0.67, F + h * 0.70, "LightStrip")


def wi_suitrack(p, w=0.80, d=0.40):
    """EVA suit on a wall rack (airlock)."""
    bbox(p, 0.0, 0.06, -w / 2 + 0.05, w / 2 - 0.05, F, F + 1.30, "HullDark")
    bbox(p, 0.10, 0.36, -0.22, 0.22, F + 0.88, F + 1.28, "Hull", bevel=0.04)
    plate_x(p, 0.361, -0.21, 0.21, F + 1.00, F + 1.07, "Accent")
    for sy in (-1, 1):
        bbox(p, 0.12, 0.30, sy * 0.30 - 0.06, sy * 0.30 + 0.06, F + 0.80, F + 1.20, "Hull", bevel=0.03)
        bbox(p, 0.13, 0.29, sy * 0.10 - 0.07, sy * 0.10 + 0.07, F + 0.25, F + 0.86, "Hull", bevel=0.03)
        bbox(p, 0.10, 0.34, sy * 0.10 - 0.08, sy * 0.10 + 0.08, F, F + 0.14, "Rubber", bevel=0.02)
    bbox(p, 0.06, 0.12, -0.20, 0.20, F + 0.95, F + 1.28, "Pack")


def wi_freezer(p, w=0.80, d=0.42):
    """Tall freezer with frosted glass door (cold storage)."""
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + 1.28, "Hull", bevel=0.02)
    plate_x(p, d + 0.004, -w / 2 + 0.04, w / 2 - 0.04, F + 0.10, F + 1.18, "Frame")
    plate_x(p, d + 0.006, -w / 2 + 0.07, w / 2 - 0.07, F + 0.14, F + 1.14, "Frost")
    for j in range(3):
        plate_x(p, d + 0.008, -w / 2 + 0.08, w / 2 - 0.08, F + 0.40 + 0.28 * j, F + 0.42 + 0.28 * j, "Frame")
    plate_x(p, d + 0.008, -w / 2 + 0.07, w / 2 - 0.07, F + 1.20, F + 1.23, "L3Band")


def wi_bottles(p, w=0.80, d=0.30, seed=0):
    """Back-bar shelf with bottles and a neon line (cantina)."""
    rng = random.Random(seed)
    bbox(p, 0.0, d, -w / 2, w / 2, F, F + 0.85, "HullDark", bevel=0.015)
    for z in (F + 0.95, F + 1.20):
        bbox(p, 0.0, d * 0.8, -w / 2, w / 2, z - 0.03, z, "Wood")
        y = -w / 2 + 0.07
        while y < w / 2 - 0.06:
            h = rng.uniform(0.12, 0.20)
            p.vcyl(d * 0.4, y, z, z + h, 0.03, seg=6, mat=rng.choice(("Glass", "Glow", "Accent", "WaterBlue")), cap0=False)
            y += 0.09
    plate_x(p, d + 0.004, -w / 2 + 0.03, w / 2 - 0.03, F + 0.78, F + 0.81, "Neon")


def wi_cable(p, w=0.80, d=0.20, seed=0):
    """Open industrial wall: a cable tray at 1.1 m, a junction box and a fire point."""
    bbox(p, 0.0, 0.18, -w / 2 + 0.01, w / 2 - 0.01, F + 1.02, F + 1.06, "Frame")
    for sy in (-1, 1):
        bbox(p, 0.16, 0.18, -w / 2 + 0.01, w / 2 - 0.01, F + 1.06, F + 1.12, "Frame")
    for j in range(3):
        p.cyl((0.05 + 0.04 * j, -w / 2 + 0.01, F + 1.08), (0.05 + 0.04 * j, w / 2 - 0.01, F + 1.08), 0.018, seg=5,
              mat=("Rubber", "Hazard", "Rubber")[j], cap0=False, cap1=False)
    bbox(p, 0.0, 0.14, -0.15, 0.15, F + 0.55, F + 0.85, "HullDark", bevel=0.01)
    plate_x(p, 0.141, -0.1, 0.1, F + 0.78, F + 0.81, "Hazard")


# --------------------------------------------------------------------------------------
# Machines and equipment (free-standing)
# --------------------------------------------------------------------------------------
def pump(p, x, y, yaw=0.0, mat="HullDark", band="Accent"):
    with p.at(T(x, y, 0), RZ(yaw)):
        bbox(p, -0.40, 0.40, -0.28, 0.28, F, F + 0.10, "Frame")
        capsule(p, (-0.22, 0, F + 0.36), (0.18, 0, F + 0.36), 0.20, mat=mat, seg=8, rings=2)
        p.cyl((0.26, 0, F + 0.36), (0.40, 0, F + 0.36), 0.08, seg=6, mat="Metal")
        p.vcyl(-0.05, 0, F + 0.52, F + 0.66, 0.06, seg=6, mat=band)


def hazard_plinth(p, hx, hy, h=0.10):
    bbox(p, -hx, hx, -hy, hy, F, F + h, "Frame", bevel=0.01)
    hazard_rect(p, hx + 0.12, hy + 0.12)


def pipe_run(p, pts, r=0.06, mat="Metal", seg=6):
    p.tube([Vector(q) for q in pts], r, seg=seg, mat=mat, fillet=0.18)


def robot_arm(p, reach=1.2, yaw=0.0, mat="Hazard", seed=0):
    """Industrial arm on a round base at the origin (about 1.5 m tall, posed over its work)."""
    with p.at(RZ(yaw)):
        p.vcyl(0, 0, F, F + 0.18, 0.32, 0.28, seg=10, mat="Frame")
        p.vcyl(0, 0, F + 0.18, F + 0.42, 0.18, seg=8, mat=mat)
        a = Vector((0, 0, F + 0.46))
        b = Vector((reach * 0.35, 0, F + 1.30))
        c = Vector((reach, 0, F + 1.10))
        d = Vector((reach, 0, F + 0.78))
        p.sphere(tuple(a), 0.15, "Frame", seg=8, rings=4)
        p.beam(a, b, 0.16, 0.18, mat)
        p.sphere(tuple(b), 0.12, "Frame", seg=8, rings=4)
        p.beam(b, c, 0.12, 0.13, mat)
        p.beam(c, d, 0.07, 0.07, "Metal")
        bbox(p, reach - 0.08, reach + 0.08, -0.07, 0.07, F + 0.66, F + 0.78, "Frame")


def conveyor(p, L, w=0.60, h=0.75, belt="FloorDark", rails="Frame"):
    """Conveyor along local X from -L/2 to L/2, belt top at F + h."""
    bbox(p, -L / 2, L / 2, -w / 2, w / 2, F + h - 0.10, F + h - 0.02, rails, bevel=0.01)
    plate_z(p, F + h, -L / 2 + 0.05, L / 2 - 0.05, -w / 2 + 0.06, w / 2 - 0.06, belt)
    for sy in (-1, 1):
        bbox(p, -L / 2, L / 2, sy * (w / 2) - 0.03 + (0.0 if sy > 0 else 0.0), sy * (w / 2) + 0.01, F + h - 0.02,
             F + h + 0.06, "Hazard" if sy > 0 else rails)
    n = max(2, int(L / 1.2) + 1)
    for k in range(n):
        x = -L / 2 + 0.1 + (L - 0.2) * k / (n - 1)
        for sy in (-1, 1):
            bbox(p, x - 0.03, x + 0.03, sy * (w / 2 - 0.05) - 0.03, sy * (w / 2 - 0.05) + 0.03, F, F + h - 0.10, rails,
                 mats={"-z": None, "+z": None})
    for sx in (-1, 1):
        p.cyl((sx * L / 2, -w / 2, F + h - 0.06), (sx * L / 2, w / 2, F + h - 0.06), 0.06, seg=8, mat="Metal")


def tank(p, x, y, h, r, mat="Metal", band="Accent", legs=True, seg=12):
    return tank_v(p, x, y, F, h, r, mat=mat, band=band, cap="dome", seg=seg, legs=legs)


def machine_block(p, hx, hy, h, body="HullDark", panel="Hull", stripe="Accent", glow=None, vents=True):
    """A generic machine housing with inset panels, an accent band, vents and an optional glowing window (+X)."""
    bbox(p, -hx, hx, -hy, hy, F, F + h, body, bevel=0.03)
    for sy in (-1, 1):
        plate_y(p, sy * (hy + 0.003), -hx + 0.08, hx - 0.08, F + 0.12, F + h * 0.55, panel, facing=sy)
    plate_x(p, hx + 0.004, -hy + 0.05, hy - 0.05, F + h * 0.62, F + h * 0.70, stripe)
    if glow:
        plate_x(p, hx + 0.005, -hy * 0.5, hy * 0.5, F + h * 0.25, F + h * 0.52, glow)
    if vents:
        for j in range(4):
            plate_z(p, F + h + 0.002, -hx * 0.6, hx * 0.6, -hy + 0.1 + (2 * hy - 0.2) * j / 3 - 0.02,
                    -hy + 0.1 + (2 * hy - 0.2) * j / 3 + 0.02, "Frame")


def holo_table(p, r=0.70):
    """Round holo table: pedestal, glowing screen top, a translucent projection and a light ring."""
    p.lathe([(r * 0.55, F), (r * 0.5, F + 0.12), (r * 0.35, F + 0.20), (r * 0.35, F + 0.80), (r, F + 0.86),
             (r, F + 0.92), (r - 0.06, F + 0.94), (0.0, F + 0.94)],
            lambda k, i: ("Frame", "Frame", "HullDark", "Frame", "Accent", "Frame", "Screen")[k], seg=16)
    p.lathe([(r - 0.10, F + 0.95), (r - 0.10, F + 0.97), (r - 0.16, F + 0.97)], "LightStrip", seg=16, smooth=False)
    with p.at(T(0, 0, F + 0.97)):
        p.lathe([(r * 0.62, 0.0), (r * 0.30, 0.55), (0.0, 0.60)], "Glass", seg=12)
        p.sphere((0, 0, 0.34), r * 0.20, "L3Band", seg=10, rings=5)
        p.torus(r * 0.34, 0.012, "L3Band", seg=16, tseg=3, z=0.34)
