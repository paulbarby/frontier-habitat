"""
Frontier Habitat 3.0 - ART-HAB interiors: industry (mine, refinery, polymer plant, workshop, glassworks,
electronics fab, fabricator) and life support (oxygen plant, water recycler, atmosphere processor).

Industry language: ONE machine on a hazard plinth, a control line (consoles or benches = the Work anchors) facing
it, painted walkways on a grate floor, gas bottles, carts and pallets in the free floor, tool walls and cable trays
on the wall.  Life language: equipment islands with a service walkway and one console.
"""
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, pi

import interior_kit as IK
import interior_furniture as FU
from rooms_kit import T, RX, RY, RZ, S, tank_v, capsule, fan_unit
from interior_kit import F, Plan, bbox, plate_x, plate_y, plate_z, ui_screen, furniture_of
from interior_rooms import at, wall_set, DEPTHS, finish
from interior_families import (fill_decor, console_at, bench_at, sit_desk, chord_x, rect_at, DECOR, NEED)

IND_WALL = ["toolwall", "cable", "rack", "lockers", "vent", "rack", "cable", "panel"]


# --------------------------------------------------------------------------------------
# machines (local frame: centre at the origin, the control side is +X)
# --------------------------------------------------------------------------------------
def m_mine(n, s, compact=False):
    r = 0.95 + 0.1 * s
    n.lathe([(r + 0.35, F), (r + 0.35, F + 0.40), (r + 0.25, F + 0.50), (r, F + 0.50), (r, F - 0.02)],
            lambda k, i: ("HullDark", "Hazard", "Frame", "Frame")[k], seg=16)
    n.cap_disc(r, F + 0.0, "FloorDark", seg=12)
    FU.floor_line(n, -r - 0.2, 0, r + 0.2, 0, w=0.04, mat="Frame", z=F + 0.01)
    # hoist cage and head beams on four posts
    for sx in (-1, 1):
        for sy in (-1, 1):
            bbox(n, sx * (r + 0.1) - 0.07, sx * (r + 0.1) + 0.07, sy * (r + 0.1) - 0.07, sy * (r + 0.1) + 0.07,
                 F + 0.5, F + 2.30, "Hazard")
    for sy in (-1, 1):
        n.beam((-(r + 0.1), sy * (r + 0.1), F + 2.30), ((r + 0.1), sy * (r + 0.1), F + 2.30), 0.14, 0.18, "Frame")
    n.cyl((0, -r - 0.2, F + 2.45), (0, r + 0.2, F + 2.45), 0.08, seg=8, mat="Metal")
    n.cyl((0, -0.10, F + 2.45), (0, 0.10, F + 2.45), 0.45, seg=12, mat="Accent")
    bbox(n, -0.45, 0.45, -0.45, 0.45, F + 0.55, F + 1.95, "Frame", mats={"-z": None})
    for j in range(4):
        bbox(n, -0.46, 0.46, -0.46, 0.46, F + 0.7 + 0.3 * j, F + 0.74 + 0.3 * j, "Metal", mats={"-z": None, "+z": None})
    n.vcyl(0, 0, F + 1.95, F + 2.40, 0.02, seg=4, mat="Frame", cap0=False, cap1=False)
    if compact:
        return
    # ore conveyor from the shaft to a hopper on -Y
    with n.at(T(0.0, -(r + 1.35), 0), RZ(90.0)):
        FU.conveyor(n, 1.6, w=0.55, h=0.75)
    hy = -(r + 2.45)
    n.convex([(-0.55, hy - 0.55, F + 1.35), (0.55, hy - 0.55, F + 1.35), (0.55, hy + 0.55, F + 1.35),
              (-0.55, hy + 0.55, F + 1.35), (-0.25, hy - 0.25, F + 0.55), (0.25, hy - 0.25, F + 0.55),
              (0.25, hy + 0.25, F + 0.55), (-0.25, hy + 0.25, F + 0.55)],
             [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "HullDark")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bbox(n, sx * 0.45 - 0.04, sx * 0.45 + 0.04, hy + sy * 0.45 - 0.04, hy + sy * 0.45 + 0.04, F, F + 1.0,
                 "Frame")
    n.convex([(-0.5, hy - 0.5, F + 1.36), (0.5, hy - 0.5, F + 1.36), (0.5, hy + 0.5, F + 1.36),
              (-0.5, hy + 0.5, F + 1.36), (0.05, hy, F + 1.62)], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], "Ore")


def m_refinery(n, s, compact=False):
    fr = 0.85 + 0.1 * s
    n.lathe([(fr + 0.1, F), (fr + 0.1, F + 0.25), (fr, F + 0.25), (fr, F + 1.55), (fr + 0.04, F + 1.6),
             (fr + 0.04, F + 1.85), (fr * 0.7, F + 2.15), (0.3, F + 2.2), (0.3, F + 2.3)],
            lambda k, i: ("Frame", "Frame", "HullDark", "Accent", "Accent", "HullDark", "Frame", "Metal")[k], seg=14)
    bbox(n, fr - 0.05, fr + 0.25, -0.5, 0.5, F + 0.45, F + 1.25, "Frame", bevel=0.02)
    plate_x(n, fr + 0.252, -0.38, 0.38, F + 0.55, F + 1.10, "Window")
    # crucible on a rail, casting line with glowing ingots
    cl = 1.6 if compact else 2.6
    with n.at(T(fr + (0.95 if compact else 1.3), 0.0, 0), RZ(90.0)):
        FU.conveyor(n, cl, w=0.7, h=0.72, belt="FloorDark")
        for j in range(int(cl / 0.5)):
            bbox(n, -cl / 2 + 0.3 + 0.5 * j - 0.15, -cl / 2 + 0.3 + 0.5 * j + 0.15, -0.18, 0.18, F + 0.72, F + 0.80,
                 "Window" if j < 3 else "Metal", bevel=0.01)
    with n.at(T(fr + 0.35, 0.95, F + 1.2)):
        n.lathe([(0.30, -0.3), (0.35, 0.10), (0.28, 0.12), (0.24, -0.25)], "HullDark", seg=10)
        n.cap_disc(0.27, 0.05, "Window", seg=10)
    for sy in (-1, 1):
        bbox(n, fr + 0.05, fr + 0.65, 0.95 + sy * 0.4 - 0.04, 0.95 + sy * 0.4 + 0.04, F, F + 1.2, "Frame")


def m_polymer(n, s, compact=False):
    nv = (1, 2, 2, 3)[s]
    xs = [(j - (nv - 1) / 2) * 1.45 for j in range(nv)]
    for j, y in enumerate(xs):
        tank_v(n, -0.2, y, F, 1.25, 0.58, mat="Metal", band="Accent", cap="dome", seg=12, legs=True)
        FU.pipe_run(n, [(-0.2, y, F + 1.78), (-0.2, y, F + 1.98), (0.9, y * 0.5, F + 1.98), (0.9, y * 0.5, F + 1.1)],
                    r=0.06, mat="Metal")
    with n.at(T(1.05, 0.0, 0)):
        FU.machine_block(n, 0.35, 0.55 + 0.2 * (nv - 1), 1.1, glow="Glow")


def m_workshop(n, s, compact=False):
    with n.at(T(-0.2, 0.0, 0)):
        bbox(n, -1.3, 1.3, -0.40, 0.40, F, F + 0.72, "HullDark", bevel=0.02)
        bbox(n, -0.9, -0.2, -0.38, 0.38, F + 0.72, F + 1.35, "Accent", bevel=0.02)
        n.cyl((-0.2, 0, F + 1.02), (0.05, 0, F + 1.02), 0.24, seg=10, mat="Metal")
        n.cyl((0.05, 0, F + 1.02), (1.05, 0, F + 1.02), 0.07, seg=6, mat="Metal")
        bbox(n, 1.05, 1.30, -0.22, 0.22, F + 0.72, F + 1.15, "Frame")
        plate_x(n, -0.199, -0.25, 0.25, F + 0.95, F + 1.20, "Screen")
    if not compact:
        with n.at(T(0.2, 1.35, 0)):
            FU.robot_arm(n, reach=1.0, yaw=-60.0, seed=s)


def m_glassworks(n, s, compact=False):
    kr = 0.9 + 0.1 * s
    cols = 12
    n.lathe([(kr + 0.1, F), (kr + 0.1, F + 0.35), (kr, F + 0.40), (kr * 0.92, F + 0.9), (kr * 0.68, F + 1.30),
             (kr * 0.30, F + 1.50), (0.0, F + 1.52)], lambda k, i: ("Frame", "Frame", "HullDark", "HullDark",
                                                                    "HullDark", "Frame")[k], seg=cols)
    n.vcyl(0, 0, F + 1.45, F + 1.98, 0.18, seg=8, mat="Frame", cap0=False)
    n.lathe([(0.24, F + 1.98), (0.24, F + 2.06), (0.12, F + 2.06)], "Window", seg=8)
    bbox(n, kr - 0.05, kr + 0.20, -0.45, 0.45, F + 0.35, F + 1.0, "Frame", bevel=0.02)
    plate_x(n, kr + 0.202, -0.33, 0.33, F + 0.45, F + 0.90, "Window")
    # float bath (glowing trough) and a sheet rack
    bl = 1.6 if compact else 2.8
    with n.at(T(kr + 0.75, 0.0, 0), RZ(90.0)):
        bbox(n, -bl / 2, bl / 2, -0.45, 0.45, F, F + 0.62, "HullDark", bevel=0.02)
        plate_z(n, F + 0.625, -bl / 2 + 0.08, bl / 2 - 0.08, -0.36, 0.36, "Window")
        for sy in (-1, 1):
            bbox(n, -bl / 2, bl / 2, sy * 0.45 - 0.03, sy * 0.45 + 0.03, F + 0.62, F + 0.72, "Frame")
    if compact:
        return
    with n.at(T(0.0, -(kr + 0.9), 0)):
        bbox(n, -0.8, 0.8, -0.35, 0.35, F, F + 0.10, "Frame")
        for j in range(6):
            bbox(n, -0.65 + 0.26 * j, -0.62 + 0.26 * j, -0.30, 0.30, F + 0.10, F + 1.25, "Glass")


def m_litho(n, s, compact=False):
    FU.machine_block(n, 0.8, 1.0 + 0.15 * s, 1.75, body="Hull", panel="HullDark", stripe="Accent", glow="Plasma")
    for j in range(3):
        n.vcyl(-0.3 + 0.3 * j, 0.0, F + 1.75, F + 2.05, 0.10, seg=8, mat="Metal")
    bbox(n, -0.9, 0.9, -1.1 - 0.15 * s, 1.1 + 0.15 * s, F, F + 0.06, "Plasma")


def m_printer(n, s, compact=False):
    pl = (2.0 if compact else 2.6) + 0.4 * s
    for sx in (-1, 1):
        for sy in (-1, 1):
            bbox(n, sx * pl / 2 - 0.08, sx * pl / 2 + 0.08, sy * 1.1 - 0.08, sy * 1.1 + 0.08, F, F + 1.90, "Frame")
    for sy in (-1, 1):
        n.beam((-pl / 2, sy * 1.1, F + 1.90), (pl / 2, sy * 1.1, F + 1.90), 0.16, 0.20, "Frame")
    n.beam((0.3, -1.2, F + 1.84), (0.3, 1.2, F + 1.84), 0.20, 0.24, "Hazard")
    bbox(n, 0.15, 0.45, 0.05, 0.35, F + 1.10, F + 1.74, "Accent", bevel=0.02)
    n.vcyl(0.3, 0.2, F + 0.95, F + 1.10, 0.04, seg=6, mat="Plasma")
    bbox(n, -pl / 2 + 0.2, pl / 2 - 0.2, -0.9, 0.9, F, F + 0.5, "HullDark", bevel=0.02)
    plate_z(n, F + 0.501, -pl / 2 + 0.3, pl / 2 - 0.3, -0.8, 0.8, "Metal")
    bbox(n, -0.6, 0.6, -0.4, 0.4, F + 0.5, F + 0.90, "Hull", bevel=0.03)


MACHINES = {"mine": m_mine, "refinery": m_refinery, "polymer_plant": m_polymer, "workshop": m_workshop,
            "glassworks": m_glassworks, "electronics_fab": m_litho, "fabricator": m_printer}

# the main machine grows with the room (critic round 4): plan scale on X/Y, a little on Z (about the floor)
M_SCALE = (1.0, 1.05, 1.32, 1.62)
M_SCALE_Z = (1.0, 1.0, 1.06, 1.12)


def run_machine(n, tid, s, compact, sc):
    sz = 1.0 + (sc - 1.0) * 0.2 if sc > 1.0 else 1.0
    sz = min(sz, M_SCALE_Z[s])
    with n.at(T(0, 0, F), S(sc, sc, sz), T(0, 0, -F)):
        MACHINES[tid](n, s, compact)


def machine_extent(tid, s, compact, sc, verts=False):
    """Build the machine into a scratch part and return its footprint (x0, x1, y0, y1) (and the vertices)."""
    from rooms_kit import P
    q = P("scratch")
    run_machine(q, tid, s, compact, sc)
    xs = [v.x for v in q.verts]
    ys = [v.y for v in q.verts]
    if verts:
        return (min(xs), max(xs), min(ys), max(ys)), q.verts
    return min(xs), max(xs), min(ys), max(ys)


def under_roof(rm, verts, dx, dy, margin=0.04):
    return all(v.z <= rm.headroom(v.x + dx, v.y + dy) - margin for v in verts[::3])


def rect_clear(plan, cx, cy, hx, hy, n=7):
    """True when no footprint overlaps the axis-aligned rectangle (sampled on an n x n grid)."""
    for i in range(n):
        for j in range(n):
            x = cx - hx + 2 * hx * i / (n - 1)
            y = cy - hy + 2 * hy * j / (n - 1)
            if plan.dist(x, y) <= 0.0:
                return False
    return True


def roof_z(rm, x, y, want, margin=0.06):
    return min(want, rm.headroom(x, y) - margin)


# --------------------------------------------------------------------------------------
# process details: floor trenches (pipes and cables to the wall), risers, type-specific stock
# --------------------------------------------------------------------------------------
def stock_zone(plan, x, y, yaw, kinds, seed=0):
    """A marked stock zone (2.6 x 1.5 m, dashed hazard border, a floor number plate) with three stock items."""
    n = plan.n
    with at(n, x, y, yaw):
        FU.hazard_rect(n, 1.30, 0.75, w=0.06, n_per_m=2.5)
        plate_z(n, F + 0.004, -1.25, 1.25, -0.70, 0.70, "FloorDark")
    c, s_ = cos(radians(yaw)), sin(radians(yaw))
    for j, lx in enumerate((-0.80, 0.0, 0.80)):
        kx, ky = x + c * lx, y + s_ * lx
        DECOR[kinds[(j + seed) % len(kinds)]](plan, kx, ky, yaw, seed + j)
    plan.rect(x, y, 1.30, 0.75, yaw, tag="stock")


def stock_zones(plan, count, kinds, seed=0):
    """Put up to `count` stock zones on the free floor of the outer ring (tangential, backs to the wall)."""
    placed = 0
    for rr in [plan.r_max - 0.8 - 0.3 * j for j in range(6)]:
        for k in range(36):
            if placed >= count:
                return placed
            a = 10.0 * k + 5.0 * (seed % 2)
            x, y = rr * cos(radians(a)), rr * sin(radians(a))
            yaw = a + 90.0
            if not plan.fits(x, y, 1.32, 0.78, yaw):
                continue
            c, s_ = cos(radians(yaw)), sin(radians(yaw))
            ok = True
            for i in range(-3, 4):
                for jj in range(-2, 3):
                    lx, ly = 1.6 * i / 3, 1.05 * jj / 2
                    if plan.dist(x + c * lx - s_ * ly, y + s_ * lx + c * ly) <= 0.0:
                        ok = False
            if ok:
                stock_zone(plan, x, y, yaw, kinds, seed=seed + placed)
                placed += 1
    return placed


def floor_trench(plan, x0, y0, ang, r1=None, w=0.34, mats=("Metal", "Accent")):
    """A covered floor trench from (x0, y0) straight out along `ang` (deg) to the wall face: a dark channel, two
    pipes, grating bars.  Flat (7 cm): people walk over it."""
    n = plan.n
    r1 = plan.Ri - 0.08 if r1 is None else r1
    ca, sa = cos(radians(ang)), sin(radians(ang))
    # distance along the ray to the circle r1
    b = x0 * ca + y0 * sa
    c = x0 * x0 + y0 * y0 - r1 * r1
    L = -b + sqrt(max(0.0, b * b - c))
    if L < 0.4:
        return
    with at(n, x0, y0, ang):
        plate_z(n, F + 0.004, 0.0, L, -w / 2, w / 2, "FloorDark")
        for sy in (-1, 1):
            plate_z(n, F + 0.006, 0.0, L, sy * w / 2 - 0.02, sy * w / 2, "Frame")
        for j, m in enumerate(mats):
            yy = (-0.07, 0.07)[j]
            n.cyl((0.0, yy, F + 0.045), (L, yy, F + 0.045), 0.04, seg=5, mat=m, cap0=False, cap1=False)
        nb = int(L / 0.45)
        for k in range(1, nb):
            bbox(n, 0.45 * k - 0.02, 0.45 * k + 0.02, -w / 2, w / 2, F + 0.06, F + 0.075, "Frame",
                 mats={"-z": None})


def riser(n, x, y, z0, z1, r=0.07, mat="Metal", dx=0.18):
    """Two vertical pipes from a machine up into the dome (seen as the machine's feed from the roof)."""
    for sx in (-dx / 2, dx / 2):
        n.vcyl(x + sx, y, z0, z1, r, seg=6, mat=mat, cap0=False)
        n.vcyl(x + sx, y, z0 + 0.25, z0 + 0.31, r + 0.025, seg=6, mat="Frame")


def free_angles(plan, cx, cy, count, avoid=(), start=0.0, clear=0.35):
    """Up to `count` directions from (cx, cy) whose ray to the wall does not cross a footprint (sampled)."""
    out = []
    for k in range(72):
        a = start + 5.0 * k
        if any(abs(((a - b) + 180.0) % 360.0 - 180.0) < 40.0 for b in list(avoid) + out):
            continue
        ok = True
        for t in range(6, 60):
            x, y = cx + 0.12 * t * cos(radians(a)), cy + 0.12 * t * sin(radians(a))
            if hypot(x, y) > plan.r_max:
                break
            if plan.dist(x, y, skip_tag="machine") < clear:
                ok = False
                break
        if ok:
            out.append(a)
        if len(out) >= count:
            break
    return out


def d_orebin(plan, x, y, yaw, k):
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.60, 0.60, -0.42, 0.42, F, F + 0.12, "Frame", bevel=0.01)
        for (x0, x1, y0, y1) in ((-0.6, 0.6, -0.42, -0.36), (-0.6, 0.6, 0.36, 0.42), (-0.6, -0.54, -0.42, 0.42),
                                 (0.54, 0.6, -0.42, 0.42)):
            bbox(n, x0, x1, y0, y1, F + 0.12, F + 0.72, "HullDark")
        plate_x(n, 0.602, -0.30, 0.30, F + 0.50, F + 0.58, "Hazard")
        n.convex([(-0.52, -0.34, F + 0.60), (0.52, -0.34, F + 0.60), (0.52, 0.34, F + 0.60), (-0.52, 0.34, F + 0.60),
                  (-0.1, 0.05, F + 0.86), (0.2, -0.05, F + 0.80)],
                 [(0, 1, 5), (1, 2, 5), (2, 3, 4), (3, 0, 4), (0, 5, 4), (2, 4, 5)], "Ore")
    return 0.78


def d_ingots(plan, x, y, yaw, k):
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.55, 0.55, -0.45, 0.45, F, F + 0.12, "Wood", mats={"-z": None})
        for layer in range(3 + k % 2):
            z = F + 0.12 + 0.09 * layer
            for j in range(4):
                if layer % 2 == 0:
                    bbox(n, -0.48, 0.48, -0.40 + 0.21 * j, -0.22 + 0.21 * j, z, z + 0.085, "Metal", bevel=0.01)
                else:
                    bbox(n, -0.48 + 0.25 * j, -0.28 + 0.25 * j, -0.40, 0.40, z, z + 0.085, "Metal", bevel=0.01)
        bbox(n, -0.56, -0.53, -0.46, 0.46, F + 0.12, F + 0.50, "Accent")
    return 0.70


def d_drums(plan, x, y, yaw, k):
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.66, 0.66, -0.66, 0.66, F, F + 0.10, "Hazard", mats={"-z": None})
        bbox(n, -0.60, 0.60, -0.60, 0.60, F + 0.10, F + 0.12, "Frame")
        mats = ("Accent", "Metal", "HullDark", "Accent")
        for j, (dx, dy) in enumerate(((-0.3, -0.3), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3))):
            if j == 3 and k % 2:
                continue
            n.vcyl(dx, dy, F + 0.12, F + 0.98, 0.27, seg=10, mat=mats[(j + k) % 4], cap0=False)
            for z in (0.35, 0.70):
                n.vcyl(dx, dy, F + z, F + z + 0.03, 0.285, seg=10, mat="Frame", cap0=False, cap1=False)
    return 0.80


def d_sheets(plan, x, y, yaw, k):
    """A-frame rack with glass sheets (glassworks)."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.75, 0.75, -0.40, 0.40, F, F + 0.08, "Frame")
        for sx in (-0.7, 0.7):
            n.beam((sx, -0.35, F + 0.08), (sx, 0.0, F + 1.30), 0.05, 0.05, "Frame")
            n.beam((sx, 0.35, F + 0.08), (sx, 0.0, F + 1.30), 0.05, 0.05, "Frame")
        n.beam((-0.72, 0.0, F + 1.30), (0.72, 0.0, F + 1.30), 0.06, 0.06, "Frame")
        for side in (-1, 1):
            for j in range(3):
                off = side * (0.06 + 0.05 * j)
                n.quad((-0.65, off * 5.0 + side * 0.02, F + 0.10), (0.65, off * 5.0 + side * 0.02, F + 0.10),
                       (0.65, off, F + 1.25), (-0.65, off, F + 1.25), "Glass")
    return 0.80


def d_reels(plan, x, y, yaw, k):
    """Cable or filament reels on a low stand."""
    n = plan.n
    with at(n, x, y, yaw):
        for j, dy in enumerate((-0.32, 0.32)):
            with n.at(T(0.0, dy, F + 0.36), RX(90.0)):
                n.lathe([(0.34, -0.14), (0.34, -0.11), (0.26, -0.11), (0.26, 0.11), (0.34, 0.11), (0.34, 0.14),
                         (0.08, 0.14)], lambda kk, i: ("HullDark", "HullDark", ("Accent", "Metal")[(j + k) % 2],
                                                        "HullDark", "HullDark", "HullDark")[kk], seg=12)
            bbox(n, -0.30, 0.30, dy - 0.16, dy + 0.16, F, F + 0.03, "Frame")
    return 0.60


def d_crates(plan, x, y, yaw, k):
    n = plan.n
    with at(n, x, y, yaw):
        for (dx, dy) in ((-0.28, -0.28), (0.28, -0.28), (-0.28, 0.28), (0.28, 0.28)):
            FU.crate(n, dx, dy, s=0.52, mat=("Hull", "Accent")[(int(dx * 10) + k) % 2 == 0])
        FU.crate(n, 0.0, 0.0, s=0.46, z=F + 0.52, mat="HullDark", yaw=12.0)
    return 0.72


def d_cooler(plan, x, y, yaw, k):
    """Fin-fan cooler on legs (life support, industry)."""
    n = plan.n
    with at(n, x, y, yaw):
        for sx in (-0.55, 0.55):
            for sy in (-0.40, 0.40):
                bbox(n, sx - 0.04, sx + 0.04, sy - 0.04, sy + 0.04, F, F + 0.70, "Frame")
        bbox(n, -0.65, 0.65, -0.48, 0.48, F + 0.70, F + 0.95, "HullDark", bevel=0.02)
        for j in range(9):
            yy = -0.40 + 0.10 * j
            plate_x(n, 0.652, yy - 0.02, yy + 0.02, F + 0.73, F + 0.92, "Metal")
        for sx in (-0.32, 0.32):
            fan_unit(n, sx, 0.0, F + 0.95, 0.28, mat="Frame")
    return 0.85


DECOR.update({"orebin": d_orebin, "ingots": d_ingots, "drums": d_drums, "sheets": d_sheets, "reels": d_reels,
              "crates": d_crates, "cooler": d_cooler})
NEED.update({"orebin": 0.78, "ingots": 0.70, "drums": 0.80, "sheets": 0.80, "reels": 0.60, "crates": 0.72,
             "cooler": 0.85})

IND_STOCK = {
    "mine": ["orebin", "crates", "bottles", "orebin", "pallets", "cart"],
    "refinery": ["ingots", "bottles", "orebin", "ingots", "tanks", "cart"],
    "polymer_plant": ["drums", "bottles", "tanks", "drums", "pallets", "cart"],
    "workshop": ["crates", "racks", "pallets", "cart", "bottles", "crates"],
    "glassworks": ["sheets", "pallets", "sheets", "cart", "bottles", "crates"],
    "electronics_fab": ["reels", "cart", "racks", "reels", "crates"],
    "fabricator": ["crates", "reels", "pallets", "cart", "racks", "drums"],
}


def industry(rm):
    s = rm.size
    tid = rm.tid
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "grate", "grid", grid=1.0)
    n = plan.n
    rmax = plan.r_max
    nw = fu["work_slots"]
    span = 1.35
    line_d = 1.9 if tid in ("workshop", "electronics_fab") else 1.7     # machine edge -> far side of the controls
    line_hw = (nw - 1) * span / 2 + 0.65
    # the biggest machine (scale, then the full / compact variant) that fits with its margin and the control line
    tries = []
    sc0 = M_SCALE[s]
    for sc in [sc0 - 0.08 * j for j in range(int((sc0 - 1.0) / 0.08) + 1)] + [1.0]:
        tries += [(sc, False), (sc, True)]
    for (sc, compact) in tries:
        (x0, x1, y0, y1), vs = machine_extent(tid, s, compact, sc, verts=True)
        x0, x1, y0, y1 = x0 - 0.25, x1 + 0.25, y0 - 0.25, y1 + 0.25
        mx = -(x0 + x1 + line_d) / 2
        my = -(y0 + y1) / 2
        pts = [(mx + x0, my + y0), (mx + x0, my + y1), (mx + x1 + line_d, -line_hw), (mx + x1 + line_d, line_hw),
               (mx + x1, my + y0), (mx + x1, my + y1)]
        if all(hypot(px, py) <= rmax for px, py in pts) and under_roof(rm, vs, mx, my):
            break
    rm.v3_info = dict(machine_scale=round(sc, 2), compact=compact)
    with at(n, mx, my, 0.0):
        run_machine(n, tid, s, compact, sc)
    cxm, cym = mx + (x0 + x1) / 2, my + (y0 + y1) / 2
    with at(n, cxm, cym, 0.0):
        FU.hazard_rect(n, (x1 - x0) / 2, (y1 - y0) / 2)
    plan.rect(cxm, cym, (x1 - x0) / 2, (y1 - y0) / 2, 0.0, tag="machine")
    cx = mx + x1 + line_d - 0.45
    ys = [(j - (nw - 1) / 2) * span for j in range(nw)]
    for j, y in enumerate(ys):
        if tid == "workshop":
            bench_at(plan, cx + 0.05, y, 0.0, w=1.2, seed=j)
        elif tid == "electronics_fab":
            sit_desk(plan, cx, y, 0.0, w=1.15, monitors=1 + (j % 2), seed=j)
        else:
            console_at(plan, cx, y, 0.0, w=1.0)
    yl = max(line_hw, (y1 - y0) / 2) + 0.35
    for sgn in (-1, 1):
        yy = cym + sgn * yl
        lim = chord_x(plan, abs(yy), 0.1)
        xa, xb = max(mx + x0 - 0.3, -lim), min(cx + 0.9, lim)
        if xb > xa:
            FU.floor_line(n, xa, yy, xb, yy, w=0.06, mat="Hazard")
    # L/XL: a second, smaller unit of the same process behind the main machine (a real plant has two lines),
    # linked by a conveyor (solids) or a pipe bridge (fluids) or a cable tray (electronics)
    if s >= 2:
        (ax0, ax1, ay0, ay1), avs = machine_extent(tid, 1, True, 1.0, verts=True)
        ahx, ahy = (ax1 - ax0) / 2 + 0.25, (ay1 - ay0) / 2 + 0.25
        best = None
        mhx, mhy = (x1 - x0) / 2, (y1 - y0) / 2
        for ri in range(12):
            rr = plan.r_max - max(ahx, ahy) - 0.05 - 0.35 * ri
            if rr < 1.0:
                break
            for k in range(48):
                a = 7.5 * k
                acx, acy = rr * cos(radians(a)), rr * sin(radians(a))
                if not plan.fits(acx, acy, ahx, ahy, 0.0):
                    continue
                if not rect_clear(plan, acx, acy, ahx + 0.55, ahy + 0.55):
                    continue
                if not under_roof(rm, avs, acx - (ax0 + ax1) / 2, acy - (ay0 + ay1) / 2):
                    continue
                if any(abs(q[1][0] - acx) < ahx + 0.6 and abs(q[1][1] - acy) < ahy + 0.6 for q in rm.anchors
                       if q[0].startswith(("Anchor_Work", "Anchor_Stand", "Anchor_Seat"))):
                    continue                     # keep the control line's stand points free
                d = hypot(acx - cxm, acy - cym)
                if best is None or d < best[0]:
                    best = (d, acx, acy)
        if best is not None:
            _, acx, acy = best
            with at(n, acx - (ax0 + ax1) / 2, acy - (ay0 + ay1) / 2, 0.0):
                run_machine(n, tid, 1, True, 1.0)
            with at(n, acx, acy, 0.0):
                FU.hazard_rect(n, ahx, ahy)
            plan.rect(acx, acy, ahx, ahy, 0.0, tag="machine2")
            # the link: from the edge of the second unit to the edge of the main machine, along the centre line
            ux_, uy_ = cxm - acx, cym - acy
            dl = hypot(ux_, uy_)
            ux_, uy_ = ux_ / dl, uy_ / dl

            def edge(hx_, hy_):
                tx = hx_ / abs(ux_) if abs(ux_) > 1e-6 else 1e9
                ty = hy_ / abs(uy_) if abs(uy_) > 1e-6 else 1e9
                return min(tx, ty)
            t0 = edge(ahx, ahy)
            t1 = dl - edge(mhx, mhy)
            lx0, ly0 = acx + ux_ * t0, acy + uy_ * t0
            lx1, ly1 = acx + ux_ * t1, acy + uy_ * t1
            L = t1 - t0
            ang = degrees(atan2(uy_, ux_))
            clear_path = all(plan.dist(lx0 + ux_ * L * q / 10, ly0 + uy_ * L * q / 10) > 0.35
                             for q in range(1, 10)) if L > 0 else False
            if tid in ("mine", "refinery", "glassworks", "fabricator", "workshop") and L > 0.6 and clear_path:
                with at(n, 0.5 * (lx0 + lx1), 0.5 * (ly0 + ly1), ang):
                    FU.conveyor(n, L, w=0.55, h=0.70)
                plan.rect(0.5 * (lx0 + lx1), 0.5 * (ly0 + ly1), L / 2, 0.35, ang, tag="link")
            elif L > 0.3:
                zb = min(roof_z(rm, lx0, ly0, F + 1.95), roof_z(rm, lx1, ly1, F + 1.95),
                         roof_z(rm, 0.5 * (lx0 + lx1), 0.5 * (ly0 + ly1), F + 1.95))
                px_, py_ = -uy_, ux_
                for off in (-0.12, 0.12):
                    FU.pipe_run(n, [(lx0 + px_ * off, ly0 + py_ * off, F + 1.0), (lx0 + px_ * off, ly0 + py_ * off, zb),
                                    (lx1 + px_ * off, ly1 + py_ * off, zb), (lx1 + px_ * off, ly1 + py_ * off, F + 1.0)],
                                r=0.07, mat=("Metal", "Accent")[off > 0])
    # service runs: covered floor trenches from the machine to the wall, feed risers into the dome
    for a in free_angles(plan, cxm, cym, (1, 2, 2, 3)[s], start=150.0):
        ex = min((x1 - x0) / 2, (y1 - y0) / 2)
        floor_trench(plan, cxm + ex * cos(radians(a)), cym + ex * sin(radians(a)), a)
    if s >= 2:
        rx_, ry_ = cxm - (x1 - x0) * 0.22, cym + (y1 - y0) * 0.22
        riser(n, rx_, ry_, F + 1.2, roof_z(rm, rx_, ry_, F + 2.9 + 0.1 * s, 0.03))
    if s == 3:
        stock_zones(plan, 3, [k for k in IND_STOCK[tid] if k not in ("cart", "racks", "tanks")], seed=5)
    fill_decor(plan, IND_STOCK[tid], seed=111 + s, align=0.0, max_n=(1, 2, 5, 8)[s], walk=(0.75, 0.75, 0.6, 0.6)[s])
    plan.wall_items(IND_WALL, wall_set(plan), open_every=3, seed=111 + s, depth_of=DEPTHS)
    plan.stands(fu["stands"], [(cx - 0.9, max(ys) + 1.0, 180.0), (cx - 0.9, min(ys) - 1.0, 180.0)])
    finish(plan)


# --------------------------------------------------------------------------------------
# LIFE SUPPORT (critic round 4: one big process group per room that grows with the size)
# --------------------------------------------------------------------------------------
def electrolysis_stack(n, x, y, h=1.8, r=0.34):
    n.vcyl(x, y, F, F + 0.12, r + 0.11, seg=10, mat="Frame")
    for j in range(7):
        z = F + 0.12 + (h - 0.3) * j / 7
        n.vcyl(x, y, z, z + (h - 0.3) / 7 - 0.03, r, seg=10, mat="Hull" if j % 2 else "Metal", cap0=False, cap1=False)
        n.vcyl(x, y, z + (h - 0.3) / 7 - 0.03, z + (h - 0.3) / 7, r + 0.02, seg=10, mat="WaterBlue" if j % 2 else "Frame",
               cap0=False, cap1=False)
    n.vcyl(x, y, F + h - 0.18, F + h, r - 0.04, seg=10, mat="Accent")
    for a in (0.0, 180.0):
        n.cyl((x + r * cos(radians(a)), y, F + 0.6), (x + r * cos(radians(a)), y, F + h - 0.2), 0.03, seg=5,
              mat="Metal")


def side_spot(plan, cands, w=0.9):
    """First console position (x, y, yaw) whose body (0.55 m behind the origin) fits inside r_max, away from the
    other footprints, with free floor for the operator in front."""
    def ok(x, y, yaw):
        c, sn = cos(radians(yaw)), sin(radians(yaw))
        bx, by = x - 0.30 * c, y - 0.30 * sn
        px, py = x + 0.55 * c, y + 0.55 * sn
        return (plan.fits(bx, by, 0.30, w / 2 + 0.03, yaw) and plan.dist(bx, by) > 0.35 and plan.dist(px, py) > 0.15
                and hypot(px, py) < plan.r_max and plan.rm.headroom(x - 0.5 * c, y - 0.5 * sn) > F + 1.62)
    for (x, y, yaw) in cands:
        if ok(x, y, yaw):
            return (x, y, yaw)
    for k in range(144):
        a = 5.0 * (k % 72)
        r = plan.r_max - (0.64 if k < 72 else 1.2)
        x, y = r * cos(radians(a)), r * sin(radians(a))
        if ok(x, y, a + 180.0):
            return (x, y, a + 180.0)
    return None                   # no room for a free-standing console (small rooms): the wall panels serve


def plinth(n, hx, hy, h=0.14, edge="Hazard"):
    bbox(n, -hx, hx, -hy, hy, F, F + h, "Frame", bevel=0.02)
    plate_z(n, F + h + 0.002, -hx + 0.06, hx - 0.06, -hy + 0.06, hy - 0.06, "HullDark")
    FU.hazard_rect(n, hx + 0.10, hy + 0.10, w=0.07) if edge == "Hazard" else None


def oxygen_plant(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "grid", grid=1.1)
    n = plan.n
    rmax = plan.r_max
    if s < 2:
        hx, hy, oy = _oxygen_compact(rm, plan, s)
    else:
        hx, hy, oy = _oxygen_large(rm, plan, s)
    cpos = side_spot(plan, [(hx + 0.75, oy, 180.0), (-hx - 0.75, oy, 0.0), (hx + 0.75, oy + 0.9, 180.0),
                            (0.0, oy + hy + 0.75, 270.0)] if s >= 2 else
                     [(hx + 0.55, oy - 0.2, 180.0), (-hx - 0.55, oy - 0.2, 0.0)])
    if cpos and (s >= 2 or hypot(cpos[0], cpos[1]) + 0.45 <= plan.lane_r() + 0.15):
        console_at(plan, cpos[0], cpos[1], cpos[2], w=0.8, work=False)
    _oxygen_finish(rm, plan, s, fu, hx, hy, oy)


def _oxygen_compact(rm, plan, s):
    """S and M (door lanes, 2026-09-25): the stacks and the tanks on ONE plinth in the -Y half, so a corridor can
    join the whole +Y half (S at least 120 deg, M at least 180 deg of free door angles)."""
    n = plan.n
    sr = 0.32 + 0.03 * s
    tr = 0.40 + 0.05 * s
    h = 1.7 + 0.12 * s
    th = 1.15 + 0.1 * s
    if s == 0:
        hx, hy, oy = 0.95, 0.65, -0.80
        stacks, tanks = [(-0.45, 0.0)], [(0.43, 0.0)]
        ym = 0.0
    else:
        hx, hy, oy = 1.35, 1.25, -0.60
        stacks, tanks = [(-0.575, 0.55), (0.575, 0.55)], [(-0.575, -0.50), (0.575, -0.50)]
        ym = 0.55
    with at(n, 0.0, oy, 0.0):
        plinth(n, hx, hy)
        for (xx, yy) in stacks:
            electrolysis_stack(n, xx, yy, h=h, r=sr)
        for j, (xx, yy) in enumerate(tanks):
            tank_v(n, xx, yy, F + 0.14, th, tr, mat="Hull", band=("WaterBlue", "Accent")[j % 2], cap="dome", seg=12)
        # the O2 manifold over the stacks, down to the tank header
        x0, x1 = min(x for x, _ in stacks) - 0.25, max(x for x, _ in stacks) + 0.25
        FU.pipe_run(n, [(x0, ym, F + h + 0.20), (x1 + 0.1, ym, F + h + 0.20), (x1 + 0.1, ym, F + 0.35)],
                    r=0.08, mat="WaterBlue")
        for (xx, yy) in stacks:
            FU.pipe_run(n, [(xx, yy, F + h - 0.1), (xx, ym, F + h + 0.20)], r=0.05, mat="Metal")
        ty_ = tanks[0][1]
        FU.pipe_run(n, [(min(x for x, _ in tanks), ty_ - tr - 0.08, F + 0.45),
                        (max(x for x, _ in tanks) + 0.1, ty_ - tr - 0.08, F + 0.45)], r=0.06, mat="Metal")
        bbox(n, x0 - 0.05, x0 + 0.05, ym - 0.05, ym + 0.05, F + 0.14, F + h + 0.15, "Frame")
    plan.rect(0.0, oy, hx + 0.15, hy + 0.15, 0.0, tag="machine")
    return hx, hy, oy


def _oxygen_large(rm, plan, s):
    n = plan.n
    rmax = plan.r_max
    rows = 1 if s < 2 else 2
    per = (2, 3, 3, 4)[s]
    pitch = 1.10 + 0.05 * s
    sr = 0.32 + 0.03 * s
    h = 1.7 + 0.12 * s
    hx = (per - 1) * pitch / 2 + sr + 0.35
    hy = (rows - 1) * 0.65 + sr + 0.35
    oy = 0.45 if s < 2 else 0.75
    with at(n, 0.0, oy, 0.0):
        plinth(n, hx, hy)
        for r_ in range(rows):
            yy = (r_ - (rows - 1) / 2) * 1.3
            for j in range(per):
                xx = (j - (per - 1) / 2) * pitch
                electrolysis_stack(n, xx, yy, h=h, r=sr)
                FU.pipe_run(n, [(xx, yy, F + h - 0.1), (xx, 0.0 if rows > 1 else yy + sr + 0.25, F + h + 0.25)],
                            r=0.05, mat="Metal")
        ym = 0.0 if rows > 1 else sr + 0.25
        # the O2 manifold over the stacks, carried on two frames
        FU.pipe_run(n, [(-hx + 0.2, ym, F + h + 0.25), (hx - 0.2, ym, F + h + 0.25), (hx - 0.2, ym, F + 0.3)],
                    r=0.09, mat="WaterBlue")
        for sx in (-hx + 0.2, hx - 0.45):
            bbox(n, sx - 0.05, sx + 0.05, ym - 0.05, ym + 0.05, F + 0.14, F + h + 0.15, "Frame")
        if s >= 2 and rm.headroom(-hx + 0.35, oy + ym) - (F + h + 0.25) > 0.3:
            riser(n, -hx + 0.35, ym, F + h + 0.25, roof_z(rm, -hx + 0.35, oy + ym, F + h + 1.1, 0.03), r=0.08,
                  mat="Metal")
    plan.rect(0.0, oy, hx + 0.15, hy + 0.15, 0.0, tag="machine")
    # storage: O2 (WaterBlue) and H2 (Accent) tanks on their own plinth, piped to the manifold
    nt = (1, 2, 3, 4)[s]
    tr = 0.40 + 0.05 * s
    ty = oy - hy - 0.95 - tr * 0.5
    thx = (nt - 1) * (2 * tr + 0.25) / 2 + tr + 0.25
    if ty - tr - 0.3 < -rmax * 0.95 or not plan.fits(0.0, ty, thx, tr + 0.25):
        ty = -rmax + tr + 0.35
    with at(n, 0.0, ty, 0.0):
        plinth(n, thx, tr + 0.25, edge=None)
        for j in range(nt):
            xx = (j - (nt - 1) / 2) * (2 * tr + 0.25)
            tank_v(n, xx, 0.0, F + 0.14, 1.15 + 0.1 * s, tr, mat="Hull", band=("WaterBlue", "Accent")[j % 2],
                   cap="dome", seg=12)
        FU.pipe_run(n, [(-thx + 0.2, 0.0, F + 0.45), (thx - 0.2, 0.0, F + 0.45)], r=0.06, mat="Metal")
    plan.rect(0.0, ty, thx + 0.1, tr + 0.35, 0.0, tag="tanks")
    FU.pipe_run(n, [(hx - 0.2, oy - hy + 0.1, F + 0.30), (hx - 0.2, ty + tr + 0.2, F + 0.30),
                    (thx - 0.2, ty + tr + 0.2, F + 0.30)], r=0.06, mat="WaterBlue")
    return hx, hy, oy


def _oxygen_finish(rm, plan, s, fu, hx, hy, oy):
    n = plan.n
    for a in free_angles(plan, 0.0, oy, (1, 2, 2, 3)[s], start=100.0):
        floor_trench(plan, (hx + 0.1) * cos(radians(a)) if abs(cos(radians(a))) > 0.7 else 0.0,
                     oy + ((hy + 0.1) * sin(radians(a)) if abs(cos(radians(a))) <= 0.7 else 0.0), a,
                     mats=("WaterBlue", "Metal"))
    fill_decor(plan, ["bottles", "cooler", "cart", "drums"], max_n=(0, 1, 2, 4)[s], seed=121 + s, align=0.0)
    plan.wall_items(["vent", "cable", "shelf", "panel", "lockers"], wall_set(plan), open_every=3, seed=121 + s,
                    depth_of=DEPTHS)
    plan.stands(fu["stands"], [(hx + 0.75, oy + 1.2, 180.0), (-hx - 0.6, oy, 0.0)])
    finish(plan)


def water_recycler(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "clean", "grid", grid=1.0)
    n = plan.n
    rmax = plan.r_max
    rd = getattr(rm, "drum_r", rmax)            # head room is 1.46 m outside the drum
    th = min(1.5, (rm.D or 2.6) - 1.0)
    cols, rows = ((2, 1), (2, 2), (3, 2), (3, 3))[s]
    tr = 0.36 + 0.04 * s
    pitch = 2 * tr + 0.35
    hx = (cols - 1) * pitch / 2 + tr + 0.30
    hy = (rows - 1) * pitch / 2 + tr + 0.30
    ox = -0.55 if s < 2 else -0.9
    # keep the tank group inside the drum
    while hypot(abs(ox) + hx, hy) > min(rd, rmax) - 0.1 and pitch > 2 * tr + 0.2:
        pitch -= 0.05
        hx = (cols - 1) * pitch / 2 + tr + 0.30
        hy = (rows - 1) * pitch / 2 + tr + 0.30
    with at(n, ox, 0.0, 0.0):
        plinth(n, hx, hy)
        tops = []
        for i in range(cols):
            for j in range(rows):
                x = (i - (cols - 1) / 2) * pitch
                y = (j - (rows - 1) / 2) * pitch
                tank_v(n, x, y, F + 0.14, th, tr, mat="Metal", band="WaterBlue", cap="dome", seg=12)
                tops.append((x, y))
        # thick manifolds: one low header per row, one high header across the tops
        for j in range(rows):
            y = (j - (rows - 1) / 2) * pitch
            ys_ = y + (tr + 0.14 if j == rows - 1 else -(tr + 0.14))
            FU.pipe_run(n, [(-hx + 0.15, ys_, F + 0.42), (hx + 0.35, ys_, F + 0.42)], r=0.09, mat="WaterBlue")
            for i in range(cols):
                x = (i - (cols - 1) / 2) * pitch
                n.cyl((x, y + (tr - 0.02) * (1 if j == rows - 1 else -1), F + 0.42), (x, ys_, F + 0.42), 0.06, seg=6,
                      mat="Metal", cap0=False, cap1=False)
        FU.pipe_run(n, [(-hx + 0.3, 0.0, F + 0.14 + th + 0.30), (hx + 0.35, 0.0, F + 0.14 + th + 0.30),
                        (hx + 0.35, 0.0, F + 0.9)], r=0.10, mat="Metal")
        for sx in (-hx + 0.3, hx + 0.35):
            bbox(n, sx - 0.05, sx + 0.05, -0.05, 0.05, F + 0.14, F + 0.14 + th + 0.25, "Frame")
    plan.rect(ox, 0.0, hx + 0.45, hy + 0.15, 0.0, tag="machine")
    # UV line on its skid next to the tanks, a pump each side
    ux = ox + hx + 1.05
    with at(n, ux, 0.0, 90.0):
        bbox(n, -0.8, 0.8, -0.35, 0.35, F, F + 0.12, "Frame", bevel=0.01)
        for sy in (-0.15, 0.15):
            n.cyl((-0.7, sy, F + 0.55), (0.7, sy, F + 0.55), 0.08, seg=8, mat="L3Band")
            n.cyl((-0.78, sy, F + 0.55), (-0.7, sy, F + 0.55), 0.10, seg=8, mat="Frame")
            n.cyl((0.7, sy, F + 0.55), (0.78, sy, F + 0.55), 0.10, seg=8, mat="Frame")
        for sx in (-0.6, 0.6):
            bbox(n, sx - 0.04, sx + 0.04, -0.3, 0.3, F + 0.12, F + 0.75, "Frame")
    plan.rect(ux, 0.0, 0.35, 0.8, 0.0, tag="uv")
    for sy in ((1,) if s < 2 else (-1, 1)):
        FU.pump(n, ux, sy * 1.25, 90.0)
        plan.rect(ux, sy * 1.25, 0.3, 0.42, 0.0)
    cpos = side_spot(plan, [(ux + 0.95, 0.0, 180.0), (ox, hy + 0.75, 270.0), (ox, -hy - 0.75, 90.0),
                            (ox - hx - 0.75, 0.0, 0.0)])
    if cpos:
        console_at(plan, cpos[0], cpos[1], cpos[2], w=0.8, work=False)
    for a in free_angles(plan, ox, 0.0, (1, 2, 2, 3)[s], start=120.0):
        floor_trench(plan, ox + (hx + 0.1) * cos(radians(a)), (hy + 0.1) * sin(radians(a)), a,
                     mats=("WaterBlue", "Metal"))
    fill_decor(plan, ["drums", "cart", "bottles", "cooler"], max_n=(0, 0, 2, 3)[s], seed=131 + s, align=0.0)
    plan.wall_items(["vent", "cable", "shelf", "panel"], wall_set(plan), open_every=3, seed=131 + s,
                    depth_of=DEPTHS)
    plan.stands(fu["stands"], [(ux + 0.95, 1.1, 180.0), (ux, -1.9, 90.0), (ox, hy + 0.7, 270.0)])
    finish(plan)


def fractionation_column(n, cr, h, s, stack=True):
    """The atmosphere processor's central column: skirt, banded shell, a platform with a rail, a ladder, a top."""
    n.lathe([(cr + 0.30, F), (cr + 0.30, F + 0.12), (cr + 0.12, F + 0.30), (cr, F + 0.34)],
            lambda k, i: ("Frame", "HullDark", "Frame")[k], seg=16)
    nb = 5 + s
    for j in range(nb):
        z0 = F + 0.34 + (h - 0.7) * j / nb
        z1 = F + 0.34 + (h - 0.7) * (j + 1) / nb
        n.vcyl(0, 0, z0, z1 - 0.05, cr, seg=16, mat=("Hull", "Metal")[j % 2], cap0=False, cap1=False)
        n.vcyl(0, 0, z1 - 0.05, z1, cr + 0.025, seg=16, mat="Accent" if j == nb - 2 else "Frame", cap0=False,
               cap1=False)
    n.lathe([(cr, F + h - 0.36), (cr * 0.85, F + h - 0.15), (cr * 0.45, F + h), (0.0, F + h + 0.02)], "Hull", seg=16)
    if stack:
        n.vcyl(0, 0, F + h - 0.05, F + h + 0.45, 0.10, seg=8, mat="Metal")
    else:                                   # the column meets the ceiling: a flange ring
        n.vcyl(0, 0, F + h - 0.10, F + h, cr * 0.55, seg=12, mat="Frame")
    # platform ring and rail at 1.25 m
    zp = min(F + 1.25, F + h - 1.10)
    n.lathe([(cr + 0.50, zp - 0.04), (cr + 0.50, zp), (cr, zp), (cr, zp - 0.04)], "Frame", seg=16, smooth=False)
    for k in range(8):
        a = 22.5 + 45.0 * k
        n.vcyl((cr + 0.46) * cos(radians(a)), (cr + 0.46) * sin(radians(a)), zp, zp + 0.9, 0.02, seg=4, mat="Hazard",
               cap0=False)
    n.lathe([(cr + 0.47, zp + 0.88), (cr + 0.47, zp + 0.93), (cr + 0.45, zp + 0.93), (cr + 0.45, zp + 0.88)],
            "Hazard", seg=16, smooth=False)
    # ladder on +X
    for sy in (-0.18, 0.18):
        n.cyl((cr + 0.10, sy, F), (cr + 0.10, sy, min(zp + 0.9, F + h - 0.12)), 0.02, seg=4, mat="Frame")
    for j in range(6):
        z = F + 0.2 + 0.2 * j
        n.cyl((cr + 0.10, -0.18, z), (cr + 0.10, 0.18, z), 0.015, seg=4, mat="Frame", cap0=False, cap1=False)


def atmo_processor(rm):
    s = rm.size
    fu = furniture_of(rm)
    plan = Plan(rm)
    IK.build_floor_v3(rm, "grate", "grid", grid=1.0)
    n = plan.n
    rmax = plan.r_max
    cr = 0.42 + 0.10 * s
    ch = min(2.4 + 0.18 * s, rm.headroom(0.0, 0.0) - F - 0.06)
    fractionation_column(n, cr, ch, s, stack=rm.headroom(0.0, 0.0) - F - ch > 0.55)
    plan.circle(0.0, 0.0, cr + 0.55, tag="machine")
    nc = (2, 3, 3, 4)[s]
    cs = 1.0 + 0.10 * s                       # compressor skid scale
    rc = min(cr + 1.45 + 0.25 * s, rmax - 0.60 * cs - 0.1)
    angs = [360.0 * (k + 0.5) / nc + 90.0 for k in range(nc)]
    for a in angs:
        x, y = rc * cos(radians(a)), rc * sin(radians(a))
        with at(n, x, y, a + 90.0):
            with n.at(S(cs, cs, 1.0)):
                bbox(n, -0.95, 0.95, -0.50, 0.50, F, F + 0.18, "Frame", bevel=0.01)
                capsule(n, (-0.6, 0, F + 0.62), (0.6, 0, F + 0.62), 0.40, mat="Metal", seg=10, rings=2)
                for sx in (-0.5, 0.5):
                    n.cyl((sx, -0.45, F + 0.62), (sx, 0.45, F + 0.62), 0.43, seg=10, mat="Frame", cap0=False,
                          cap1=False)
                n.cyl((0.1, 0, F + 1.02), (0.1, 0, F + 1.30), 0.12, seg=8, mat="Accent")
        # a thick pipe from each compressor to the column (over the walkway at 1.9 m)
        pz = min(F + 1.9 + 0.1 * s, rm.headroom(x, y) - 0.18, rm.headroom(0.0, 0.0) - 0.18)
        FU.pipe_run(n, [(x, y, F + 1.0), (x, y, pz), (cr * cos(radians(a)) * 1.05, cr * sin(radians(a)) * 1.05, pz)],
                    r=0.10 + 0.01 * s, mat="Metal")
        plan.rect(x, y, 1.0 * cs, 0.55 * cs, a + 90.0, tag="comp")
    # coolers between the compressors on L/XL
    if s >= 2:
        for a in angs[:2 if s == 2 else 3]:
            b = a + 180.0 / nc
            x, y = (rc + 0.2) * cos(radians(b)), (rc + 0.2) * sin(radians(b))
            if plan.fits(x, y, 0.7, 0.55, b) and plan.dist(x, y) > 1.0:
                d_cooler(plan, x, y, b + 90.0, 0)
                plan.circle(x, y, 0.85, tag="decor")
                FU.pipe_run(n, [(x, y, F + 0.8), (x * 0.45, y * 0.45, F + 0.8), (x * 0.45, y * 0.45, F + 0.2)],
                            r=0.07, mat="Metal")
    # service console facing the column, between two compressors
    b0 = angs[0] + 180.0 / nc
    ccx, ccy = (cr + 1.05) * cos(radians(b0 + 180.0)), (cr + 1.05) * sin(radians(b0 + 180.0))
    console_at(plan, ccx, ccy, b0, w=0.9, work=False)
    for a in free_angles(plan, 0.0, 0.0, (1, 2, 3, 3)[s], start=angs[0] + 180.0 / nc, clear=0.25):
        floor_trench(plan, (cr + 0.35) * cos(radians(a)), (cr + 0.35) * sin(radians(a)), a)
    if s == 3:
        stock_zones(plan, 3, ["drums", "crates", "bottles"], seed=7)
        for a in (angs[0] + 180.0 / nc + 90.0, angs[-1] + 180.0 / nc + 90.0):
            x, y = (rmax - 1.0) * cos(radians(a)), (rmax - 1.0) * sin(radians(a))
            if plan.fits(x, y, 0.7, 0.55, a) and plan.dist(x, y) > 1.2:
                d_cooler(plan, x, y, a + 90.0, 1)
                plan.circle(x, y, 0.85, tag="decor")
    fill_decor(plan, ["bottles", "drums", "cart", "tanks"], max_n=(0, 1, 2, 4)[s], seed=141 + s, align=0.0)
    plan.wall_items(["vent", "cable", "vent", "panel", "lockers"], wall_set(plan), open_every=3, seed=141 + s,
                    depth_of=DEPTHS)
    plan.stands(fu["stands"], [(ccx * 1.5, ccy * 1.5, b0), (-(cr + 0.9), 0.0, 0.0), ((cr + 0.9), 0.0, 180.0)])
    finish(plan)


INTERIORS = {tid: industry for tid in MACHINES}
INTERIORS.update({"oxygen_plant": oxygen_plant, "water_recycler": water_recycler, "atmo_processor": atmo_processor})
