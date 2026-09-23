"""
Frontier Habitat 2.0 - ART-A room builders: industry family (sheds and halls on a round base).
mine (dome + lattice headframe + ore hopper), refinery (shed + furnace + chimneys), polymer_plant (vats with
domed lids + pipe rack), workshop (sawtooth shed + roof crane + parts rack), glassworks (kiln dome + glowing
stack + cooling bed of glass sheets), electronics_fab (clean-room block + ducts + blue window band),
fabricator (tall hall + gantry + rolling door + stacked hull plates).
"""
import math
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2
from mathutils import Vector

import rooms_kit as K
from rooms_kit import (T, RX, RY, RZ, S, polar, frame_m, reg_angles, columns, ang_diff, porthole, lamp, antenna,
                       vent_box, fan_unit, capsule, tank_v, pipe, screen, rail_ring, rail_line, ladder, dome_band,
                       drum_band, crown_teeth, lv_module, lv_fins, lv_annex, lv_beacon, lv_emblem, lv_collar_dome,
                       levels_dome, levels_podium, auto_sites, table_round, stool, chair, console, cabinet, crate,
                       workbench, shelf_rack, radial_fit, tangent_fit, hall, grid_wall, FLOOR_Z, WALL_TOP)
from rooms_habitat import spread, roof_vent

F = FLOOR_Z


def industrial_base(rm, **kw):
    s = rm.size
    args = dict(pilasters=(10, 14, 16, 20)[s], pil_mat="Frame", lamps=(160.0, 200.0), bolts=s >= 2, floor="grate",
                wall="HullDark", kick="Frame")
    args.update(kw)
    rm.build_base(**args)


def rect_fn(cx, cy, a, b, m=0.1):
    return lambda x, y: abs(x - cx) < a - m and abs(y - cy) < b - m


def rect_obstacles(cx, cy, a, b):
    """Circles that cover a rectangle (for auto_sites)."""
    out = []
    n = max(1, int(round(a / b)))
    for k in range(n):
        x = cx - a + a * (2 * k + 1) / n
        out.append((x, cy, hypot(a / n, b) + 0.1))
    return out


def chimney(p, rm, x, y, z0, z1, r, name):
    p.vcyl(x, y, z0, z0 + 0.45, r + 0.25, r + 0.12, seg=10, mat="Frame", cap0=False)
    p.vcyl(x, y, z0 + 0.4, z1, r, seg=10, mat="HullDark", cap0=False, cap1=False)
    for zb in (z0 + (z1 - z0) * 0.55, z1 - 0.75):
        p.vcyl(x, y, zb, zb + 0.24, r + 0.03, seg=10, mat="Accent", cap0=False, cap1=False)
    with p.at(T(x, y, z1)):
        p.lathe([(r + 0.08, -0.05), (r + 0.08, 0.12), (r - 0.05, 0.12), (r - 0.05, -0.4)],
                lambda k, i: ("Frame", "Frame", "Rubber")[k], seg=10)
        p.cap_disc(r - 0.05, -0.4, "Rubber", seg=8)
    ladder(p, x + r + 0.06, y, z0 + 0.5, z1 - 0.2, yaw=0.0, w=0.34)
    rm.anchor(name, (x, y, z1 + 0.15))
    return z1 + 0.12


# --------------------------------------------------------------------------------------
# MINE: dome + lattice headframe with a winch wheel through the roof, ore hopper on the side
# --------------------------------------------------------------------------------------
def headframe(p, x, y, z0, z1, w0, w1, levels=4, beam=0.14, rail=True):
    corners = ((1, 1), (-1, 1), (-1, -1), (1, -1))

    def hw(z):
        return w0 + (w1 - w0) * (z - z0) / (z1 - z0)
    for sx, sy in corners:
        p.beam((x + sx * hw(z0), y + sy * hw(z0), z0), (x + sx * hw(z1), y + sy * hw(z1), z1), beam, beam, "Frame",
               caps=False)
    zs = [z0 + (z1 - z0) * (k + 1) / levels for k in range(levels)]
    prev = z0 + 0.3
    for li, z in enumerate(zs):
        h = hw(z)
        for c in range(4):
            a, b = corners[c], corners[(c + 1) % 4]
            p.beam((x + a[0] * h, y + a[1] * h, z), (x + b[0] * h, y + b[1] * h, z), 0.09, 0.09, "Frame", caps=False)
            hp = hw(prev)
            if (li + c) % 2 == 0:
                p.beam((x + a[0] * hp, y + a[1] * hp, prev), (x + b[0] * h, y + b[1] * h, z), 0.06, 0.06, "Frame", caps=False)
            else:
                p.beam((x + b[0] * hp, y + b[1] * hp, prev), (x + a[0] * h, y + a[1] * h, z), 0.06, 0.06, "Frame", caps=False)
        prev = z
    h = hw(z1)
    p.box0(x, y, z1, 2 * h + 0.4, 2 * h + 0.4, 0.12, "HullDark")
    if rail:
        rail_line(p, (x - h - 0.2, y - h - 0.2), (x + h + 0.2, y - h - 0.2), z1 + 0.12, h=0.8, posts=3, mat="Hazard")
    # sheave wheel on an A-frame
    zw = z1 + 0.75
    p.cyl((x, y - 0.10, zw), (x, y + 0.10, zw), 0.58, seg=12, mat="Accent")
    p.cyl((x, y - 0.17, zw), (x, y + 0.17, zw), 0.15, seg=6, mat="Frame")
    for sy in (-1, 1):
        p.beam((x - 0.45, y + sy * 0.24, z1 + 0.12), (x, y + sy * 0.24, zw + 0.05), 0.08, 0.08, "Frame")
        p.beam((x + 0.45, y + sy * 0.24, z1 + 0.12), (x, y + sy * 0.24, zw + 0.05), 0.08, 0.08, "Frame")
    return zw + 0.6


def ore_hopper(p, x, y, zb, zt, w=0.95, yaw=0.0):
    with p.at(T(x, y, 0), RZ(yaw)):
        p.convex([(-w, -w, zt), (w, -w, zt), (w, w, zt), (-w, w, zt),
                  (-w * 0.5, -w * 0.5, zb), (w * 0.5, -w * 0.5, zb), (w * 0.5, w * 0.5, zb), (-w * 0.5, w * 0.5, zb)],
                 [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "HullDark")
        p.box((0, 0, zt + 0.02), (2 * w + 0.12, 2 * w + 0.12, 0.14), "Accent", mats={"-z": None})
        p.convex([(-w * 0.9, -w * 0.9, zt + 0.08), (w * 0.9, -w * 0.9, zt + 0.08), (w * 0.9, w * 0.9, zt + 0.08),
                  (-w * 0.9, w * 0.9, zt + 0.08), (0.1, 0.05, zt + 0.55)], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)],
                 "Ore")


def build_mine(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    industrial_base(rm)
    H = (3.5, 3.9, 4.4, 4.9)[s]
    rm.build_dome(H, crown="open", seams=6 if s == 0 else 8, crown_t=72.0)
    rm.door_hood(depth=0.9)
    ro = rm.roof
    w0 = (0.90, 1.05, 1.20, 1.35)[s]
    z0 = rm.dome_z(w0 * 1.3, 0.0) - 0.25
    z1 = H + (1.4, 1.9, 2.4, 2.9)[s]
    top = headframe(ro, 0.0, 0.0, z0, z1, w0, 0.55, levels=(2, 3, 4, 4)[s], rail=s >= 1)
    rm.top_z = max(rm.top_z, top)
    # dome crown ring round the headframe opening
    rc, zc = rm.dome_rz(72.0)
    ro.lathe([(rc + 0.06, zc - 0.08), (rc + 0.06, zc + 0.08), (rc - 0.08, zc + 0.10)], "Frame",
             seg=12 if s == 0 else 16)
    ro.cap_disc(rc - 0.08, zc + 0.02, "HullDark", seg=12 if s == 0 else 16)
    # back stays
    for sy in (-1, 1):
        ro.beam((-0.4, sy * 0.4, z1 - 0.2), (-Rw * 0.62, sy * 0.9, rm.dome_z(Rw * 0.62, 0.9) - 0.1), 0.12, 0.12, "Frame",
                caps=False)
    # conveyors to ore hoppers on the -Y flank
    hoppers = [(Rw * 0.30, -Rw * 0.58)] + ([(-Rw * 0.30, -Rw * 0.58)] if s >= 2 else [])
    for (hx, hy) in hoppers:
        hz = rm.dome_z(hx, hy)
        tz = hz + 0.9
        ore_hopper(ro, hx, hy, hz - 0.8, tz, w=0.8 + 0.1 * s)
        sx = 0.35 if hx > 0 else -0.35
        ro.beam((sx, -0.45, z0 + (z1 - z0) * 0.45), (hx, hy + 0.3, tz + 0.45), 0.55, 0.10, "Rubber")
        ro.beam((sx, -0.45, z0 + (z1 - z0) * 0.45 - 0.08), (hx, hy + 0.3, tz + 0.37), 0.66, 0.07, "Frame")
    if s == 3:
        # winch house on the dome
        pos, _ = rm.dpt(40.0, 150.0)
        ro.box0(pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.4, 1.8, 1.3, 1.3, "HullDark", mats={"-z": None})
        ro.box0(pos.x, pos.y, rm.dome_z(pos.x, pos.y) + 0.9, 1.9, 1.4, 0.1, "Frame")
    levels_dome(rm, dict(collar=(3.0, 9.0), band3=(30.0, 32.5), band4=(14.0, 16.0), ant=(46.0, 110.0, 1.2),
                         mod3=(50.0, 60.0), fins4=(46.0, 200.0 if s == 3 else 170.0), annex4=(24.0, -160.0),
                         crown5=(56.0, 59.0), beacon5=(0.55 + 0.05 * s, 0.55 + 0.05 * s, z1 + 0.12),
                         emblem5=(38.0, 20.0),
                         emblem_size=0.8 + 0.12 * s, mod_size=(1.0 + 0.1 * s, 0.7, 0.5)))
    # interior: shaft collar, cage, winch, ore carts, ore pile, console
    n = rm.interior
    n.lathe([(1.35, F), (1.35, F + 0.45), (1.25, F + 0.55), (0.95, F + 0.55), (0.95, F)],
            lambda k, i: ("HullDark", "Hazard", "Frame", "Frame")[k], seg=16)
    n.cap_disc(0.96, F + 0.02, "Rubber", seg=12)
    n.box((0, 0, F + 1.25), (1.0, 1.0, 1.3), "Frame", mats={"+x": "HullDark", "-x": "HullDark"})
    n.box((0, 0, F + 1.95), (1.1, 1.1, 0.10), "Accent")
    with n.at(T(-2.2 - 0.3 * s, 0, F)):
        n.box0(0, 0, 0, 1.5, 1.7, 0.18, "Frame")
        n.cyl((0, -0.6, 0.72), (0, 0.6, 0.72), 0.46, seg=10, mat="Metal")
        n.cyl((0, -0.68, 0.72), (0, -0.6, 0.72), 0.58, seg=10, mat="Accent")
        n.cyl((0, 0.6, 0.72), (0, 0.68, 0.72), 0.58, seg=10, mat="Accent")
        for sy in (-1, 1):
            n.box0(0, sy * 0.95, 0.18, 0.7, 0.30, 0.95, "HullDark", mats={"-z": None})
    rng = random.Random(3 + s)
    for k in range((1, 2, 3, 4)[s]):
        a = -70.0 + 50.0 * k
        x, y, _ = polar(1.9 + 0.3 * s, a)
        with n.at(T(x, y, F), RZ(a + 90.0)):
            n.box0(0, 0, 0.18, 1.2, 0.8, 0.55, "HullDark", mats={"-z": None})
            n.box((0, 0, 0.72), (1.05, 0.66, 0.14), "Ore")
            for sx in (-0.4, 0.4):
                n.cyl((sx, -0.44, 0.16), (sx, 0.44, 0.16), 0.16, seg=6, mat="Rubber")
    pts = [(rng.uniform(-0.9, 0.9), rng.uniform(-0.7, 0.7), rng.uniform(0.0, 0.7)) for _ in range(14)]
    pts = [(x, y, z * (1.0 - 0.6 * math.hypot(x / 0.9, y / 0.7) / 1.42)) for x, y, z in pts]
    pts += [(-0.9, -0.7, 0), (0.9, -0.7, 0), (0.9, 0.7, 0), (-0.9, 0.7, 0)]
    px, py, _ = polar(Ri - 1.35, 120.0)
    with n.at(T(px, py, F), RZ(-20)):
        n.hull(pts, "Ore", vein=((0, 0, 0.3), (1, 0.3, 0.6), 0.12), vein_max=3)
    with n.at(RZ(-150.0), T(tangent_fit(Ri, 0.3, 0.5, 0.06), 0, 0)):
        console(n, w=0.9, glow="Window")


# --------------------------------------------------------------------------------------
# REFINERY: shed on a round base with a furnace and tall chimneys
# --------------------------------------------------------------------------------------
def build_refinery(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    industrial_base(rm)
    D = 2.5
    rm.build_podium(D, ribs=(10, 14, 16, 20)[s], band="Accent", band_z=D - 0.5, parapet=0.14, wall="HullDark",
                    deck="Frame")
    ro = rm.roof
    cx, cy, a, b = -0.12 * Rw, 0.14 * Rw, 0.50 * Rw, 0.36 * Rw
    eave = D + (1.6, 1.9, 2.2, 2.4)[s]
    ridge = eave + (0.7, 0.85, 1.0, 1.1)[s]
    top = hall(ro, cx, cy, a, b, D + 0.02, eave, ridge, roof="gable", wall="Hull", roof_mat="Frame",
               band="Accent", windows=True, win_mat="Window")
    rm.rooms_hi.append((rect_fn(cx, cy, a, b), eave - 0.1))
    stacks = [(0.46 * Rw, -0.36 * Rw)] + ([(0.10 * Rw, -0.62 * Rw)] if s >= 2 else []) + \
             ([(-0.52 * Rw, -0.48 * Rw)] if s >= 3 else [])
    zc = (6.2, 7.2, 8.2, 9.2)[s]
    rch = (0.36, 0.42, 0.46, 0.50)[s]
    obst = rect_obstacles(cx, cy, a, b)
    for k, (x, y) in enumerate(stacks):
        top = max(top, chimney(ro, rm, x, y, D, zc - 0.6 * k, rch, "Smoke" if k == 0 else "Smoke%d" % (k + 1)))
        obst.append((x, y, rch + 0.4))
    rm.top_z = max(rm.top_z, top)
    # heat exchanger with glowing slits
    if s >= 1:
        hx, hy = 0.52 * Rw, 0.36 * Rw
        ro.box0(hx, hy, D, 1.5, 1.2, 0.9, "HullDark", mats={"-z": None})
        for k in range(4):
            ro.box((hx - 0.5 + 0.33 * k, hy, D + 0.92), (0.14, 1.0, 0.05), "Window", mats={"-z": None})
        ro.box((hx, hy, D + 0.65), (1.54, 1.24, 0.14), "Accent", mats={"-z": None, "+z": None})
        obst.append((hx, hy, 1.0))
    levels_podium(rm, auto_sites(rm, obst, D))
    # interior: furnace under the shed, casting table, ingots, crucible, ore bin
    n = rm.interior
    fx, fy = cx - a * 0.35, cy
    fr = (1.0, 1.2, 1.35, 1.5)[s]
    fh = min(eave - 0.4, 2.6 + 0.2 * s)
    with n.at(T(fx, fy, 0)):
        n.lathe([(fr + 0.1, F), (fr + 0.1, F + 0.25), (fr, F + 0.25), (fr, fh - 0.6), (fr + 0.03, fh - 0.55),
                 (fr + 0.03, fh - 0.3), (fr * 0.75, fh), (0.0, fh + 0.05)],
                lambda k, i: ("Frame", "Frame", "HullDark", "Accent", "Accent", "HullDark", "Frame")[k], seg=12)
    n.box((fx + fr + 0.05, fy, F + 0.8), (0.5, 1.2, 1.0), "Frame")
    n.box((fx + fr + 0.305, fy, F + 0.75), (0.012, 0.9, 0.7), "Window", mats={"-x": None})
    n.box0(fx + fr + 0.7, fy, F, 0.9, 1.3, 0.02, "Hazard", mats={"-z": None})
    with n.at(T(0.6 + 0.3 * s, -0.4 * Rw, F), RZ(20.0)):
        n.box0(0, 0, 0, 2.4, 0.9, 0.55, "HullDark", mats={"-z": None})
        for k in range(5):
            n.box((-0.9 + 0.45 * k, 0, 0.56), (0.30, 0.62, 0.04), "Window" if k < 3 else "Metal", mats={"-z": None})
    for k in range((1, 2, 3, 3)[s]):
        x, y, _ = polar(Ri - 0.9, 60.0 + 40.0 * k)
        with n.at(T(x, y, F), RZ(60.0 + 40.0 * k)):
            n.box0(0, 0, 0, 1.2, 0.9, 0.08, "Frame")
            for layer, cnt in enumerate((3, 2, 1)):
                for j in range(cnt):
                    yy = (j - (cnt - 1) / 2) * 0.26
                    n.prism_x([(yy - 0.11, 0.08 + 0.15 * layer), (yy + 0.11, 0.08 + 0.15 * layer),
                               (yy + 0.08, 0.22 + 0.15 * layer), (yy - 0.08, 0.22 + 0.15 * layer)], -0.5, 0.5, "Metal")
    x, y, _ = polar(Ri - 0.9, 230.0)
    with n.at(T(x, y, F), RZ(230.0)):
        n.box0(0, 0, 0, 1.0, 1.4, 0.7, "Hull", mats={"-z": None})
        n.box((0, 0, 0.72), (0.8, 1.2, 0.1), "Ore", mats={"-z": None})


# --------------------------------------------------------------------------------------
# POLYMER PLANT: round vats with domed lids and a pipe rack over the roof
# --------------------------------------------------------------------------------------
def vat_top(p, x, y, z0, h, r, seg=14):
    prof = [(r, z0), (r, z0 + h * 0.45), (r + 0.03, z0 + h * 0.48), (r + 0.03, z0 + h * 0.68), (r, z0 + h * 0.70),
            (r, z0 + h)]
    mats = ["Metal", "Accent", "Accent", "Accent", "Metal"]
    for t in (30.0, 60.0):
        prof.append((r * cos(radians(t)), z0 + h + r * 0.42 * sin(radians(t))))
        mats.append("Metal")
    prof.append((0.0, z0 + h + r * 0.42))
    mats.append("Metal")
    with p.at(T(x, y, 0)):
        p.lathe_a(prof, reg_angles(seg), lambda k, i: mats[k])
    p.vcyl(x, y, z0 + h + r * 0.38, z0 + h + r * 0.42 + 0.22, 0.22, seg=8, mat="Frame")
    return z0 + h + r * 0.42 + 0.22


def pipe_rack(p, x0, x1, y, zb, zt, frames=3, w=0.9):
    """Portal frames along X with three pipes on top."""
    for k in range(frames):
        x = x0 + (x1 - x0) * k / (frames - 1)
        for sy in (-1, 1):
            p.box0(x, y + sy * w / 2, zb, 0.14, 0.14, zt - zb, "Frame", mats={"-z": None, "+z": None})
        p.box0(x, y, zt, 0.16, w + 0.3, 0.14, "Frame")
    for j, (mat, r) in enumerate((("Metal", 0.12), ("Accent", 0.09), ("HullDark", 0.10))):
        yy = y - w / 2 + 0.2 + (w - 0.4) * j / 2
        p.cyl((x0 - 0.2, yy, zt + 0.14 + r), (x1 + 0.2, yy, zt + 0.14 + r), r, seg=6, mat=mat, cap0=True, cap1=True)


def build_polymer_plant(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    industrial_base(rm)
    D = 2.3
    rm.build_podium(D, ribs=(10, 14, 16, 20)[s], band="Accent", band_z=D - 0.5, parapet=0.14, wall="HullDark",
                    deck="Frame")
    ro = rm.roof
    vats = {0: [(-0.5, 1.35, 1.05)], 1: [(-0.9, 1.75, 1.15), (-0.9, -1.75, 1.15)],
            2: [(-2.0, 1.95, 1.25), (-2.0, -1.95, 1.25), (1.9, 1.95, 1.2)],
            3: [(-2.4, 2.3, 1.35), (-2.4, -2.3, 1.35), (2.3, 2.3, 1.3), (2.3, -2.3, 1.3)]}[s]
    hv = (1.3, 1.5, 1.7, 1.9)[s]
    obst = []
    tops = []
    for (x, y, r) in vats:
        tops.append((x, y, vat_top(ro, x, y, D, hv, r, seg=12 if s == 0 else 14)))
        obst.append((x, y, r + 0.2))
    zr = max(t[2] for t in tops) + 0.4
    ry = 0.0 if s else -1.2
    x0, x1 = (-Rw * 0.62, Rw * 0.62)
    pipe_rack(ro, x0, x1, ry, D, zr, frames=3 if s < 2 else 4, w=0.9)
    obst += [(x0 + (x1 - x0) * k / 4.0, ry, 0.7) for k in range(5)]
    for (x, y, zt) in tops:
        yy = ry + (0.25 if y > ry else -0.25)
        pipe(ro, [(x, y, zt - 0.05), (x, y, zr + 0.25), (x * 0.7 + 0.0, yy, zr + 0.25)], r=0.08, mat="Metal", seg=6,
             fillet=0.2)
    rm.top_z = max(rm.top_z, zr + 0.5)
    rm.anchor("Vent", (x1, ry, zr + 0.4))
    levels_podium(rm, auto_sites(rm, obst, D))
    # interior: vat bodies, press, pellet bins, pipes
    n = rm.interior
    for (x, y, r) in vats:
        n.vcyl(x, y, F, F + 0.2, r + 0.08, seg=12, mat="Frame", cap0=False)
        n.vcyl(x, y, F + 0.2, D - 0.05, r - 0.02, seg=12, mat="Metal", cap0=False, cap1=False)
        n.vcyl(x, y, F + 1.0, F + 1.35, r + 0.01, seg=12, mat="Accent", cap0=False, cap1=False)
    px, py = (1.4, -0.4) if s else (1.2, -1.2)
    with n.at(T(px, py, F)):
        n.box0(0, 0, 0, 1.5, 1.7, 0.35, "HullDark", mats={"-z": None})
        for sy in (-0.7, 0.7):
            n.vcyl(0, sy, 0.35, 1.75, 0.10, seg=6, mat="Metal", cap0=False, cap1=False)
        n.box0(0, 0, 1.75, 1.3, 1.8, 0.25, "HullDark")
        n.box0(0, 0, 1.1, 1.0, 1.15, 0.16, "Metal")
        n.vcyl(0, 0, 1.26, 1.75, 0.20, seg=8, mat="Accent", cap0=False, cap1=False)
    for k in range((2, 3, 4, 5)[s]):
        a = 360.0 * (k + 0.5) / (2, 3, 4, 5)[s] + 200.0
        x, y, _ = polar(tangent_fit(Ri, 0.45, 0.65, 0.06), a)
        with n.at(T(x, y, F), RZ(a)):
            n.box0(0, 0, 0, 0.9, 1.3, 0.75, "Hull", mats={"-z": None})
            n.box((0, 0, 0.77), (0.72, 1.12, 0.04), "Accent" if k % 2 == 0 else "Cargo", mats={"-z": None})


# --------------------------------------------------------------------------------------
# WORKSHOP: sawtooth shed with a roof crane arm and a parts rack
# --------------------------------------------------------------------------------------
def roof_crane(p, x, y, z, boom=3.4, yaw=-25.0, h=1.0):
    p.vcyl(x, y, z, z + 0.3, 0.55, 0.45, seg=10, mat="Frame", cap0=False)
    p.vcyl(x, y, z + 0.3, z + h, 0.26, seg=8, mat="HullDark", cap0=False)
    with p.at(T(x, y, z + h), RZ(yaw)):
        p.box0(0, 0, 0, 1.0, 0.85, 0.55, "Accent")
        p.box((0.51, 0, 0.30), (0.012, 0.6, 0.26), "Window", mats={"-x": None})
        p.beam((0.3, 0, 0.62), (boom, 0, 1.15), 0.24, 0.28, "Hazard")
        p.beam((0.3, 0, 0.30), (boom * 0.55, 0, 0.90), 0.09, 0.09, "Frame")
        p.box((-0.85, 0, 0.42), (0.8, 0.75, 0.5), "HullDark")
        p.vcyl(boom - 0.15, 0, 0.25, 1.05, 0.025, seg=4, mat="Rubber", cap0=False, cap1=False)
        p.box((boom - 0.15, 0, 0.18), (0.24, 0.20, 0.24), "Frame")
    return z + h + 1.3


def build_workshop(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    industrial_base(rm)
    D = 2.4
    rm.build_podium(D, ribs=(10, 14, 16, 20)[s], band="Accent", band_z=D - 0.5, parapet=0.14, wall="HullDark",
                    deck="Frame")
    ro = rm.roof
    cx, cy, a, b = 0.10 * Rw, 0.16 * Rw, 0.52 * Rw, 0.40 * Rw
    eave = D + (1.5, 1.8, 2.0, 2.2)[s]
    ridge = eave + (0.8, 0.9, 1.0, 1.1)[s]
    top = hall(ro, cx, cy, a, b, D + 0.02, eave, ridge, roof="saw", wall="Hull", roof_mat="HullDark", band="Accent",
               teeth=(2, 3, 3, 4)[s], saw_glass="Window", windows=True)
    rm.rooms_hi.append((rect_fn(cx, cy, a, b), eave - 0.1))
    obst = rect_obstacles(cx, cy, a, b)
    kx, ky = -0.62 * Rw, -0.34 * Rw
    top = max(top, roof_crane(ro, kx, ky, D, boom=(2.4, 3.0, 3.8, 4.4)[s], yaw=35.0, h=0.9 + 0.1 * s))
    obst.append((kx, ky, 0.9))
    # parts rack on the deck
    px, py = 0.42 * Rw, -0.55 * Rw
    with ro.at(T(px, py, D), RZ(30.0)):
        for sx in (-1, 1):
            for sy in (-1, 1):
                ro.box0(sx * 0.9, sy * 0.3, 0, 0.07, 0.07, 1.4, "Frame", mats={"-z": None})
        for zz in (0.35, 0.9):
            ro.box0(0, 0, zz, 1.9, 0.7, 0.05, "Metal")
            for k in range(3):
                ro.box0(-0.6 + 0.6 * k, 0, zz + 0.05, 0.45, 0.5, 0.35, ("Cargo", "Accent", "Hull")[k], mats={"-z": None})
    obst.append((px, py, 1.1))
    if s >= 3:
        top = max(top, roof_crane(ro, 0.48 * Rw, 0.50 * Rw, D, boom=3.0, yaw=200.0, h=1.0))
        obst.append((0.48 * Rw, 0.50 * Rw, 0.9))
    rm.top_z = max(rm.top_z, top)
    levels_podium(rm, auto_sites(rm, obst, D))
    # interior: benches, lathe, robot arm, parts rack, trolley
    n = rm.interior
    for k in range((2, 2, 3, 4)[s]):
        ang = (60.0, 120.0, 180.0, 240.0)[k]
        with n.at(RZ(ang), T(tangent_fit(Ri, 0.38, 1.1, 0.05), 0, 0)):
            workbench(n, w=2.1, d=0.75, stripe="Accent")
    with n.at(T(0.3, -0.45 * Rw, F), RZ(8.0)):
        n.box0(0, 0, 0, 2.6, 0.75, 0.70, "HullDark", mats={"-z": None})
        n.box0(-0.9, 0, 0.70, 0.75, 0.70, 0.65, "Accent")
        n.cyl((-0.52, 0, 1.05), (-0.30, 0, 1.05), 0.26, seg=10, mat="Metal")
        n.cyl((-0.30, 0, 1.05), (0.85, 0, 1.05), 0.09, seg=6, mat="Metal")
        n.box0(1.0, 0, 0.70, 0.35, 0.45, 0.50, "Frame")
    with n.at(T(-0.45 * Rw, 0.1 * Rw, F), RZ(-35.0)):
        n.vcyl(0, 0, 0, 0.35, 0.40, seg=8, mat="Frame")
        n.beam((0, 0, 0.35), (0.2, 0, 1.35), 0.22, 0.22, "Hazard")
        n.beam((0.2, 0, 1.35), (1.2, 0, 1.0), 0.16, 0.16, "Hazard")
        n.sphere((0.2, 0, 1.35), 0.18, "Frame", seg=8, rings=4)
        n.box((1.25, 0, 0.92), (0.16, 0.26, 0.2), "Metal")
    with n.at(RZ(200.0), T(tangent_fit(Ri, 0.3, 1.0, 0.05), 0, 0)):
        shelf_rack(n, w=2.0, d=0.6, h=1.85, levels=4, fill=0.8, seed=11 + s)
    with n.at(T(0.35 * Rw, 0.25 * Rw, F), RZ(30.0)):
        n.box0(0, 0, 0.12, 0.9, 0.55, 0.70, "Hazard", mats={"-z": None})
        n.box0(0, 0, 0.82, 0.95, 0.60, 0.05, "Frame")


# --------------------------------------------------------------------------------------
# GLASSWORKS: kiln dome with a short glowing stack and a cooling bed of glass sheets
# --------------------------------------------------------------------------------------
def kiln(p, rm, x, y, z0, r, name, seg=12):
    """Squat dome with glowing seams (Window) and a short stack with a glowing rim."""
    cols, kind, _ = columns(seg, [22.5 + 45.0 * k for k in range(8)], seam_w=4.0)
    prof = [(r + 0.08, z0), (r + 0.08, z0 + 0.35), (r, z0 + 0.38)]
    for t in (20.0, 45.0, 70.0):
        prof.append((r * cos(radians(t)), z0 + 0.38 + r * 0.72 * sin(radians(t))))
    zt = prof[-1][1]
    with p.at(T(x, y, 0)):
        p.lathe_a(prof, cols, lambda k, i: ("Frame" if k < 2 else ("Window" if kind[i] == "s" and k < 4 else "HullDark")))
        p.cap_disc(prof[-1][0], zt, "Frame", seg=8)
    sr = r * 0.30
    p.vcyl(x, y, zt, zt + 1.1, sr, seg=8, mat="Frame", cap0=False, cap1=False)
    with p.at(T(x, y, zt + 1.1)):
        p.lathe([(sr + 0.06, -0.06), (sr + 0.06, 0.10), (sr - 0.04, 0.10), (sr - 0.04, -0.3)],
                lambda k, i: ("Frame", "Window", "Window")[k], seg=8)
        p.cap_disc(sr - 0.04, -0.3, "Window", seg=8)
    rm.anchor(name, (x, y, zt + 1.3))
    # glowing furnace door
    with p.at(T(x, y, 0), RZ(-90.0)):
        p.box((r + 0.05, 0, z0 + 0.5), (0.14, 0.9, 0.7), "Frame")
        p.box((r + 0.125, 0, z0 + 0.5), (0.012, 0.6, 0.45), "Window", mats={"-x": None})
    return zt + 1.2


def cooling_bed(p, x, y, z0, L, n, yaw=0.0):
    with p.at(T(x, y, z0), RZ(yaw)):
        p.box0(0, 0, 0, L, 1.6, 0.25, "Frame", mats={"-z": None})
        for k in range(n):
            xx = -L / 2 + 0.25 + (L - 0.5) * k / max(1, n - 1)
            p.box0(xx, 0, 0.25, 0.035, 1.3, 0.95, "Glass", mats={"-z": None})
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.box0(sx * (L / 2 - 0.05), sy * 0.75, 0.25, 0.08, 0.08, 1.4, "Frame", mats={"-z": None})
        for sy in (-1, 1):
            p.beam((-L / 2, sy * 0.75, 1.65), (L / 2, sy * 0.75, 1.65), 0.08, 0.08, "Frame")


def build_glassworks(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    industrial_base(rm)
    D = 2.3
    rm.build_podium(D, ribs=(10, 14, 16, 20)[s], band="Accent", band_z=D - 0.5, parapet=0.14, wall="HullDark",
                    deck="Frame")
    ro = rm.roof
    kr = (1.25, 1.5, 1.7, 1.85)[s]
    kilns = [(-0.30 * Rw, 0.18 * Rw)] + ([(-0.20 * Rw, -0.42 * Rw)] if s >= 2 else [])
    obst = []
    top = 0.0
    for k, (x, y) in enumerate(kilns):
        rr = kr * (1.0 if k == 0 else 0.8)
        top = max(top, kiln(ro, rm, x, y, D, rr, "Smoke" if k == 0 else "Smoke2", seg=12 if s == 0 else 16))
        obst.append((x, y, rr + 0.3))
    bl = (2.0, 2.6, 3.2, 3.6)[s]
    beds = [(0.36 * Rw, -0.05 * Rw, 90.0)] + ([(0.30 * Rw, 0.55 * Rw, 0.0)] if s >= 3 else [])
    for (x, y, yaw) in beds:
        cooling_bed(ro, x, y, D, bl, (5, 6, 7, 8)[s], yaw=yaw)
        obst += rect_obstacles(x, y, 0.8, bl / 2) if yaw == 90.0 else rect_obstacles(x, y, bl / 2, 0.8)
    rm.top_z = max(rm.top_z, top, D + 1.8)
    levels_podium(rm, auto_sites(rm, obst, D))
    # interior: furnace, float bath, sheet stacks, bench, cullet bins
    n = rm.interior
    kx, ky = kilns[0]
    n.vcyl(kx, ky, F, F + 1.6, kr * 0.7, seg=12, mat="HullDark", cap0=False)
    n.box((kx + kr * 0.7 + 0.05, ky, F + 0.7), (0.3, 0.9, 0.8), "Frame")
    n.box((kx + kr * 0.7 + 0.205, ky, F + 0.7), (0.012, 0.7, 0.55), "Window", mats={"-x": None})
    with n.at(T(0.3 * Rw, -0.15 * Rw, F), RZ(90.0)):
        n.box0(0, 0, 0, 3.0 + 0.4 * s, 1.0, 0.7, "HullDark", mats={"-z": None})
        n.box((0, 0, 0.705), (2.8 + 0.4 * s, 0.8, 0.012), "Window", mats={"-z": None})
    for k in range((2, 3, 4, 5)[s]):
        a = 200.0 + 30.0 * k
        x, y, _ = polar(tangent_fit(Ri, 0.4, 0.6, 0.06), a)
        with n.at(T(x, y, F), RZ(a)):
            n.box0(0, 0, 0, 0.8, 1.2, 0.12, "Frame")
            for j in range(4):
                n.box0(0, -0.45 + 0.3 * j, 0.12, 0.7, 0.03, 1.0, "Glass", mats={"-z": None})


# --------------------------------------------------------------------------------------
# ELECTRONICS FAB: clean-room block with ducts, filters and a blue-lit window band
# --------------------------------------------------------------------------------------
def duct(p, pts, w=0.5, h=0.4, mat="Metal"):
    pts = [Vector(q) for q in pts]
    for i in range(len(pts) - 1):
        p.beam(pts[i], pts[i + 1], w, h, mat)


def build_electronics_fab(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    industrial_base(rm, windows=None)
    D = 2.3
    rm.build_podium(D, ribs=(8, 14, 16, 20)[s], band=None, windows=(1.62, 1.92), win_mat="Plasma",
                    win_seams=(10, 16, 20, 24)[s], parapet=0.14)
    ro = rm.roof
    blocks = {0: [(0.0, 0.2, 0.52, 0.36)], 1: [(0.0, 0.2, 0.52, 0.38)],
              2: [(-0.18, 0.28, 0.40, 0.30), (0.34, -0.36, 0.28, 0.22)],
              3: [(-0.22, 0.30, 0.40, 0.30), (0.38, -0.30, 0.26, 0.24)]}[s]
    obst = []
    top = 0.0
    eave = D + (1.4, 1.6, 1.8, 2.0)[s]
    for k, (fx, fy, fa, fb) in enumerate(blocks):
        cx, cy, a, b = fx * Rw, fy * Rw, fa * Rw, fb * Rw
        e = eave - 0.3 * k
        top = max(top, hall(ro, cx, cy, a, b, D + 0.02, e, roof="flat", wall="Hull", roof_mat="HullDark",
                            band="Accent", windows=True, win_mat="Plasma", ribs=True, rib_mat="Frame"))
        rm.rooms_hi.append((rect_fn(cx, cy, a, b), e - 0.1))
        obst += rect_obstacles(cx, cy, a, b)
        # filter units and exhaust fans on the block roof
        for j in range(2 if a > 1.6 else 1):
            ux = cx - a * 0.5 + a * j
            vent_box(ro, ux, cy + b * 0.35, e + 0.16, 0.9, 0.7, 0.35, slats=3)
            fan_unit(ro, ux, cy - b * 0.35, e + 0.16, 0.34)
        # duct from the roof down to the deck
        duct(ro, [(cx + a - 0.35, cy - b * 0.1, e + 0.35), (cx + a + 0.45, cy - b * 0.1, e + 0.35),
                  (cx + a + 0.45, cy - b * 0.1, D + 0.25)], w=0.45, h=0.40)
        obst.append((cx + a + 0.45, cy - b * 0.1, 0.5))
    if s >= 2:
        (fx0, fy0, fa0, fb0), (fx1, fy1, fa1, fb1) = blocks
        duct(ro, [(fx0 * Rw + fa0 * Rw * 0.4, fy0 * Rw - fb0 * Rw, eave - 0.2),
                  (fx0 * Rw + fa0 * Rw * 0.4, fy1 * Rw + fb1 * Rw * 0.2, eave - 0.2),
                  (fx1 * Rw - fa1 * Rw, fy1 * Rw + fb1 * Rw * 0.2, eave - 0.2)], w=0.5, h=0.45, mat="Hull")
    rm.top_z = max(rm.top_z, top + 0.6)
    levels_podium(rm, auto_sites(rm, obst, D))
    # interior: clean benches, lithography machine, wafer racks, consoles
    n = rm.interior
    for k in range((2, 3, 4, 6)[s]):
        a = 360.0 * (k + 0.5) / (2, 3, 4, 6)[s] + 40.0
        if ang_diff(a, 0.0) < 24:
            a += 30.0
        with n.at(RZ(a), T(tangent_fit(Ri, 0.38, 0.9, 0.05), 0, 0)):
            workbench(n, w=1.8, d=0.75, stripe="Plasma")
    cx, cy = blocks[0][0] * Rw, blocks[0][1] * Rw
    with n.at(T(cx, cy, F)):
        n.box0(0, 0, 0, 2.2, 1.4, 1.6, "Hull", mats={"-z": None})
        n.box((0, -0.706, 1.1), (1.8, 0.012, 0.3), "Plasma", mats={"+y": None})
        n.box0(0, 0, 1.6, 1.2, 0.9, 0.4, "HullDark", mats={"-z": None})
    for k in range((1, 2, 3, 3)[s]):
        a = 150.0 + 60.0 * k
        with n.at(RZ(a), T(tangent_fit(Ri, 0.3, 0.9, 0.05), 0, 0)):
            shelf_rack(n, w=1.8, d=0.55, h=1.8, levels=5, fill=0.9, seed=5 + k, mats=("Frame", "Plasma", "HullDark"))
    with n.at(RZ(-40.0), T(tangent_fit(Ri, 0.3, 0.5, 0.05), 0, 0)):
        console(n, w=0.9, glow="Plasma")


# --------------------------------------------------------------------------------------
# FABRICATOR: tall hall with a gantry, a rolling door and hull plates stacked outside
# --------------------------------------------------------------------------------------
def plate_stack(p, x, y, z, n, yaw=0.0, w=1.6, d=1.0):
    with p.at(T(x, y, z), RZ(yaw)):
        p.box0(0, 0, 0, w + 0.2, d + 0.1, 0.10, "Frame", mats={"-z": None})
        for k in range(n):
            p.box0(0.02 * (k % 2), 0.0, 0.10 + 0.07 * k, w, d, 0.06, "Metal" if k % 3 else "Hull", mats={"-z": None})


def build_fabricator(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    industrial_base(rm)
    D = 2.3
    rm.build_podium(D, ribs=(10, 14, 16, 20)[s], band="Accent", band_z=D - 0.5, parapet=0.14, wall="HullDark",
                    deck="Frame")
    ro = rm.roof
    cx, cy, a, b = -0.06 * Rw, 0.12 * Rw, 0.52 * Rw, 0.34 * Rw
    eave = D + (2.4, 2.9, 3.3, 3.6)[s]
    ridge = eave + (0.9, 1.1, 1.3, 1.4)[s]
    top = hall(ro, cx, cy, a, b, D + 0.02, eave, ridge, roof="barrel", wall="Hull", roof_mat="HullDark",
               band="Accent", windows=True, win_mat="Window")
    rm.rooms_hi.append((rect_fn(cx, cy, a, b), eave - 0.1))
    obst = rect_obstacles(cx, cy, a, b)
    # rolling door on the +X end: slatted panel in a hazard frame
    x1 = cx + a + 0.012
    dw, dh = b * 1.1, (eave - D) * 0.8
    for k in range(int(dh / 0.18)):
        z = D + 0.1 + 0.18 * k
        ro.box((x1, cy, z + 0.08), (0.03, dw, 0.15), "HullDark" if k % 2 else "Frame", mats={"-x": None})
    for sy in (-1, 1):
        ro.box((x1 + 0.02, cy + sy * (dw / 2 + 0.08), D + dh / 2), (0.05, 0.14, dh), "Hazard", mats={"-x": None})
    ro.box((x1 + 0.02, cy, D + dh + 0.1), (0.05, dw + 0.3, 0.14), "Hazard", mats={"-x": None})
    # gantry crane over the hall: two A-frames on the deck, bridge beam, trolley and hook
    gx = cx - a * 0.25
    zg = ridge + 0.5
    for sy in (-1, 1):
        yb = cy + sy * (b + 0.45)
        for dx in (-0.6, 0.6):
            ro.beam((gx + dx, yb, D), (gx, yb, zg), 0.16, 0.16, "Hazard", caps=False)
    ro.beam((gx, cy - b - 0.6, zg + 0.1), (gx, cy + b + 0.6, zg + 0.1), 0.26, 0.34, "Hazard")
    ro.box0(gx, cy - b * 0.3, zg - 0.3, 0.5, 0.5, 0.3, "Frame")
    ro.vcyl(gx, cy - b * 0.3, ridge + 0.05, zg - 0.3, 0.025, seg=4, mat="Rubber", cap0=False, cap1=False)
    obst += [(gx, cy - b - 0.45, 0.8), (gx, cy + b + 0.45, 0.8)]
    # hull plates stacked outside (on the deck)
    stacks = [(0.55 * Rw, -0.42 * Rw, 20.0, 6)] + ([(0.62 * Rw, 0.40 * Rw, -20.0, 5)] if s >= 1 else []) + \
             ([(-0.62 * Rw, -0.36 * Rw, 60.0, 7)] if s >= 3 else [])
    for (x, y, yaw, nn) in stacks:
        plate_stack(ro, x, y, D, nn + s, yaw=yaw)
        obst.append((x, y, 1.1))
    rm.top_z = max(rm.top_z, zg + 0.3, top)
    levels_podium(rm, auto_sites(rm, obst, D))
    # interior: printer portal over a bed, composite press, plate stacks, robot arm
    n = rm.interior
    px, py = cx - a * 0.2, cy
    pl = min(a * 1.2, 4.6)
    for sx in (-1, 1):
        for sy in (-1, 1):
            n.box0(px + sx * pl / 2, py + sy * 1.1, F, 0.16, 0.16, 2.6, "Frame", mats={"-z": None})
    for sy in (-1, 1):
        n.beam((px - pl / 2, py + sy * 1.1, F + 2.6), (px + pl / 2, py + sy * 1.1, F + 2.6), 0.16, 0.2, "Frame")
    n.beam((px + 0.3, py - 1.2, F + 2.5), (px + 0.3, py + 1.2, F + 2.5), 0.2, 0.25, "Hazard")
    n.box((px + 0.3, py + 0.2, F + 2.1), (0.3, 0.3, 0.6), "Accent")
    n.box0(px, py, F, pl - 0.4, 1.8, 0.5, "HullDark", mats={"-z": None})
    n.box0(px - 0.3, py, F + 0.5, pl * 0.5, 1.4, 0.06, "Metal", mats={"-z": None})
    with n.at(T(0.45 * Rw, -0.35 * Rw, F), RZ(30.0)):
        n.box0(0, 0, 0, 1.6, 1.2, 0.9, "HullDark", mats={"-z": None})
        n.box0(0, 0, 1.6, 1.6, 1.2, 0.3, "HullDark")
        for sx in (-0.65, 0.65):
            n.vcyl(sx, 0, 0.9, 1.6, 0.08, seg=6, mat="Metal", cap0=False, cap1=False)
    for k in range((1, 2, 2, 3)[s]):
        a2 = 200.0 + 40.0 * k
        x, y, _ = polar(Ri - 1.1, a2)
        plate_stack(n, x, y, F, 4, yaw=a2)
    with n.at(RZ(150.0), T(tangent_fit(Ri, 0.3, 0.5, 0.06), 0, 0)):
        console(n, w=0.9, glow="Window")


BUILDERS = {
    "mine": build_mine,
    "refinery": build_refinery,
    "polymer_plant": build_polymer_plant,
    "workshop": build_workshop,
    "glassworks": build_glassworks,
    "electronics_fab": build_electronics_fab,
    "fabricator": build_fabricator,
}
