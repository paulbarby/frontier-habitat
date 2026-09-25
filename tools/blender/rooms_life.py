"""
Frontier Habitat 2.0 - ART-A room builders: life family.
oxygen_plant (dome with glass panels + electrolysis stacks through the roof, 1/2/3/4 stacks),
water_recycler (drum with a ring of filter columns and blue piping, vent stack),
atmo_processor (hyperbolic cooling towers on a round base, intake grilles, vapour vents; 2/2/3/4 towers).
"""
import math
from math import sin, cos, radians, degrees, hypot, sqrt, atan2
from mathutils import Vector

import rooms_kit as K
from rooms_kit import (T, RX, RY, RZ, S, polar, frame_m, reg_angles, ang_diff, porthole, lamp, antenna, vent_box,
                       fan_unit, capsule, tank_v, pipe, screen, rail_ring, rail_line, ladder, dome_band, drum_band,
                       crown_teeth, lv_module, lv_fins, lv_annex, lv_beacon, lv_emblem, lv_collar_dome, levels_dome,
                       levels_podium, table_round, stool, chair, console, cabinet, crate, workbench, radial_fit,
                       tangent_fit, setback_drum, cooling_tower, grid_wall, FLOOR_Z, WALL_TOP)
from rooms_habitat import spread, roof_vent

F = FLOOR_Z


# --------------------------------------------------------------------------------------
# OXYGEN PLANT
# --------------------------------------------------------------------------------------
def o2_stack_roof(p, x, y, zd, ztop, r, band="Accent"):
    """Stack above the dome: collar at the dome, body, two bands, vent head."""
    p.vcyl(x, y, zd - 0.30, zd + 0.12, r + 0.30, r + 0.18, seg=10, mat="Frame", cap0=False)
    p.vcyl(x, y, zd, ztop - 0.35, r, seg=10, mat="HullDark", cap0=False, cap1=False)
    for zb in (zd + (ztop - zd) * 0.35, ztop - 0.9):
        p.vcyl(x, y, zb, zb + 0.22, r + 0.03, seg=10, mat=band, cap0=False, cap1=False)
    with p.at(T(x, y, ztop - 0.35)):
        p.lathe([(r + 0.06, 0.0), (r + 0.06, 0.12), (r + 0.14, 0.18), (r + 0.14, 0.26), (r * 0.4, 0.40), (0.0, 0.42)],
                lambda k, i: ("Frame", "Frame", "Metal", "Frame", "Frame")[k], seg=10)
    return ztop + 0.07


def o2_cell(n, x, y, top, r=0.5):
    """Electrolysis cell under a stack (Interior): tank with a water band, a pipe up to the dome."""
    h = 1.5
    tank_v(n, x, y, F, h, r, mat="Metal", band="WaterBlue", cap="dome", seg=10, band_z=0.40)
    n.vcyl(x, y, F + h + 0.2, top, 0.18, seg=8, mat="HullDark", cap0=False, cap1=False)
    n.vcyl(x, y, F + h + 0.35, F + h + 0.55, 0.22, seg=8, mat="Accent", cap0=False)


def build_oxygen_plant(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0) if s else (), bolts=s >= 2)
    H = (3.1, 3.6, 4.2, 4.8)[s]
    stacks = {0: [(0.0, 0.0)], 1: [(0.0, 0.95), (0.0, -0.95)],
              2: [polar(1.45, a)[:2] for a in (90.0, 210.0, 330.0)],
              3: [polar(1.95, a)[:2] for a in (45.0, 135.0, 225.0, 315.0)]}[s]
    st_ang = [math.degrees(math.atan2(y, x)) % 360.0 for x, y in stacks] if s else []

    def dm(t, a):
        if 12.0 < t < 44.0 and ang_diff(a, 0.0) > 18.0:
            k = int(((a % 360.0) + 22.5) // 45.0)
            return "Glass" if k % 2 == 0 else "Hull"
        return "Hull"
    rm.build_dome(H, crown="open" if s == 0 else "hatch", seams=8, seam_mat="Frame", mat=dm, inset=-0.02,
                  hseams=(12.0, 44.0) if s else (12.0, 44.0), crown_t=(74.0, 79.0, 79.0, 79.0)[s])
    rm.door_hood(depth=0.8)
    ro, n = rm.roof, rm.interior
    ztop = (4.9, 5.5, 6.1, 6.8)[s]
    rs = (0.42, 0.38, 0.40, 0.42)[s]
    top = 0.0
    for k, (x, y) in enumerate(stacks):
        zd = rm.dome_z(x, y) if s else rm.dome_rz(74.0)[1]
        top = max(top, o2_stack_roof(ro, x, y, zd, ztop - (0.35 * (k % 2) if s >= 2 else 0.0), rs))
        rm.anchor("Vent%d" % (k + 1), (x, y, ztop + 0.1))
        o2_cell(n, x, y, rm.dome_z(hypot(x, y) + 0.25, 0.0) - 0.07, r=0.45 + 0.03 * s)
    rm.top_z = max(rm.top_z, top)
    if s >= 2:
        x, y = stacks[0]
        ladder(ro, x + rs + 0.08, y, rm.dome_z(x + rs, y) + 0.1, ztop - 0.5, yaw=0.0, w=0.36)
    # levels: bands below the glass, parts between the stacks
    ant_a = 200.0 if s != 1 else 180.0
    lv = dict(collar=(3.0, 9.0), band3=(46.5, 48.5), band4=(9.5, 11.5), ant=(52.0, ant_a, 1.0),
              mod3=(56.0, -60.0 if s != 1 else -90.0), fins4=(50.0, 60.0 if s != 1 else 90.0),
              annex4=(50.0, 150.0 if s != 2 else 270.0) if s else None, crown5=(62.0, 65.0),
              emblem5=(52.0, -30.0 if s != 1 else 0.0 + 30.0), emblem_size=0.55 + 0.15 * s,
              mod_size=(0.8 + 0.15 * s, 0.6, 0.45), fin_n=3 + s // 2)
    if s == 0:
        lv.update(beacon5=(0.9, -0.9, rm.dome_z(0.9, -0.9) - 0.02), crown5=(50.0, 53.0), mod3=(40.0, -50.0),
                  fins4=(40.0, 120.0), emblem5=(34.0, 20.0), ant=(40.0, 220.0, 0.9), band3=(46.5, 48.5))
        lv_annex(rm.L[4], *rm.dpt(28.0, 270.0)[0].xy, rm.dome_z(*rm.dpt(28.0, 270.0)[0].xy) - 0.05, yaw=0.0, L=1.0,
                 r=0.28, seg=8)
    else:
        bx, by = polar(0.0 if s == 1 else 0.0, 0.0)[:2]
        lv.update(beacon5=(0.0, 0.0, rm.crown_z + 0.12) if s != 2 else (0.0, 0.0, rm.crown_z + 0.12))
    levels_dome(rm, lv)
    # interior: manifold, water inlet tank, console
    if s >= 1:
        for (x, y) in stacks:
            pipe(n, [(x, y, F + 1.9), (x * 0.3, y * 0.3, F + 2.1)], r=0.06, seg=6, fillet=0.0)
    xt = tangent_fit(Ri, 0.38, 0.4, 0.06)
    tank_v(n, *polar(xt, 180.0 if s else 150.0)[:2], F, 1.1, 0.36, mat="Hull", band="WaterBlue", cap="dome", seg=8)
    with n.at(RZ(-40.0 if s else -60.0), T(tangent_fit(Ri, 0.3, 0.5, 0.06), 0, 0)):
        console(n, w=0.9, glow="Window")


# --------------------------------------------------------------------------------------
# WATER RECYCLER
# --------------------------------------------------------------------------------------
def filter_column(p, x, y, z0, h, r, seg=8):
    """Filter column: body with a blue section and a frame ring, domed head (5 bands)."""
    prof = [(r, z0), (r, z0 + h * 0.25), (r, z0 + h * 0.55), (r, z0 + h), (r * 0.72, z0 + h + r * 0.30),
            (0.0, z0 + h + r * 0.42)]
    mats = ["Hull", "WaterBlue", "Hull", "Frame", "Frame"]
    with p.at(T(x, y, 0)):
        p.lathe_a(prof, reg_angles(seg), lambda k, i: mats[k])
    return z0 + h + r * 0.42


def build_water_recycler(rm):
    s = rm.size
    R, Rw, Ri = rm.R, rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0) if s else (), bolts=s >= 2, floor="grate")
    rd = min(Rw - 0.85 - 0.12 * s, max(0.6 * R + 0.15, Rw * 0.62))
    # round 12: the deck ring Rw - 0.62 .. Rw is the doorway housing's zone (door kit 3.1, HX -0.56): the filter
    # columns stand between the drum and that ring, so no hood can meet a column at any door angle
    KEEP = Rw - 0.62
    rd = min(rd, KEEP - 2 * (0.24, 0.30, 0.36, 0.42)[s] - 0.06)
    D = (2.6, 2.8, 3.0, 3.2)[s]
    setback_drum(rm, rd, D, wall="Hull", band="Accent", ribs=(6, 10, 12, 14)[s], band_z=D - 0.55,
                 windows=(1.75, 2.05), win_mat="WaterBlue", win_seams=(6, 10, 12, 14)[s])
    ro = rm.roof
    nc = (6, 8, 10, 12)[s]
    cr = min(0.42, (KEEP - rd - 0.03) / 2)
    rc = rd + 0.03 + cr
    cr = min(cr, math.pi * rc / nc * 0.62)
    hc = (1.6, 1.9, 2.2, 2.5)[s]
    tops = []
    for k in range(nc):
        a = 360.0 * (k + 0.5) / nc
        if ang_diff(a, 0.0) < 14.0:
            continue
        x, y, _ = polar(rc, a)
        tp = filter_column(ro, x, y, WALL_TOP + 0.08, hc, cr, seg=6 if s == 0 else 8)
        tops.append((x, y, tp, a))
    # blue pipes: column tops -> drum wall (straight, no caps: 12 triangles each)
    for x, y, tp, a in tops[::(2 if s < 2 else 1)]:
        ex, ey, _ = polar(rd + 0.05, a)
        ro.cyl((x, y, tp - 0.08), (ex, ey, tp - 0.08), 0.06, seg=6, mat="WaterBlue", cap0=False, cap1=False)
    # a ring main on the drum wall
    ro.lathe_a([(rd + 0.14, WALL_TOP + hc + 0.28), (rd + 0.14, WALL_TOP + hc + 0.40), (rd + 0.02, WALL_TOP + hc + 0.40)],
               reg_angles(max(16, rm.seg * 2 // 3 // 4 * 4)), "WaterBlue", smooth=False)
    # small vent stack on the drum top + a hatch
    vx, vy = -rd * 0.45, rd * 0.35
    ro.vcyl(vx, vy, D, D + 1.4 + 0.2 * s, 0.14, seg=8, mat="Metal", cap0=False)
    ro.vcyl(vx, vy, D + 1.0 + 0.2 * s, D + 1.15 + 0.2 * s, 0.18, seg=8, mat="Accent", cap0=False, cap1=False)
    rm.anchor("Vent", (vx, vy, D + 1.45 + 0.2 * s))
    ro.box0(rd * 0.3, -rd * 0.3, D, 0.9, 0.9, 0.18, "Frame", mats={"-z": None})
    ro.box0(rd * 0.3, -rd * 0.3, D + 0.18, 0.75, 0.75, 0.05, "Accent", mats={"-z": None})
    rm.top_z = max(rm.top_z, D + 1.45 + 0.2 * s)
    # levels on the drum top
    q = rd - 0.75
    cfg = dict(trim=False, band3=(D - 0.30, D - 0.22), band4=(1.57, 1.65),
               ant=(-q * 0.2, -q * 0.8, 0.9), mod3=(q * 0.75, q * 0.35, 90.0), fins4=(-q * 0.9, -q * 0.15, 90.0),
               annex4=(q * 0.1, q * 0.75, 0.0), beacon5=(q * 0.7, -q * 0.7, D + 0.02),
               emblem5=(-q * 0.2, -q * 0.15, D + 0.05, 0, 0, 1), emblem_size=0.6 + 0.12 * s)
    drum_band(rm.L[2], Rw, WALL_TOP - 0.06, WALL_TOP + 0.10, 0.05, "Trim", seg=rm.seg)
    rm.D, save_rw = D, rm.Rw
    rm.Rw = rd                       # bands and crown go round the drum, not the base wall
    levels_podium(rm, cfg)
    rm.Rw = save_rw
    # interior: filtration tanks under the drum, pumps, UV line, console
    n = rm.interior
    nt = (2, 3, 4, 5)[s]
    for k in range(nt):
        a = 360.0 * (k + 0.5) / nt + 15.0
        x, y, _ = polar(rd - 0.75, a)
        tank_v(n, x, y, F, min(1.7, D - 0.9), 0.45, mat="Metal", band="WaterBlue", cap="dome", seg=8, legs=True)
    for k in range(nt):
        a = 360.0 * (k + 0.5) / nt + 15.0 + 180.0 / nt
        x, y, _ = polar(rd * 0.35, a)
        n.box0(x, y, F, 0.55, 0.45, 0.5, "HullDark", mats={"-z": None})
        pipe(n, [(x, y, F + 0.4), polar(rd - 0.75, a - 180.0 / nt, F + 0.4)], r=0.06, mat="WaterBlue", seg=6, fillet=0.0)
    with n.at(RZ(-150.0), T(min(tangent_fit(Ri, 0.3, 0.5, 0.06), rd + 0.4), 0, 0)):
        console(n, w=0.9, glow="Window")
    # low pipe racks under the ledge (head room 1.46 m)
    for k in range(nc):
        a = 360.0 * (k + 0.5) / nc
        if ang_diff(a, 0.0) < 20.0 or k % 2 or s == 0:
            continue
        x, y, _ = polar((rd + Ri) / 2, a)
        n.box0(x, y, F, 0.3, 0.3, 0.9, "Frame", mats={"-z": None})
        n.vcyl(x, y, F + 0.9, F + 1.2, 0.12, seg=6, mat="WaterBlue")


# --------------------------------------------------------------------------------------
# ATMOSPHERE PROCESSOR
# --------------------------------------------------------------------------------------
def build_atmo_processor(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0), bolts=s >= 2, pilasters=(8, 12, 14, 16)[s], floor="grate")
    D = 2.3
    rm.build_podium(D, ribs=0, band="Accent" if s else None, band_z=D - 0.45, windows=(1.55, 1.80), win_mat="Rubber",
                    win_seams=(8, 24, 32, 40)[s], parapet=0.12)
    ro = rm.roof
    towers = {0: [(0.0, 1.45), (0.0, -1.45)], 1: [(0.0, 1.85), (0.0, -1.85)],
              2: [polar(2.35, a)[:2] for a in (90.0, 210.0, 330.0)],
              3: [polar(3.0, a)[:2] for a in (45.0, 135.0, 225.0, 315.0)]}[s]
    rb = (1.25, 1.5, 1.6, 1.7)[s]
    h = (3.9, 4.8, 5.4, 6.0)[s]
    seg = (10, 16, 16, 16)[s]
    top = 0.0
    for k, (x, y) in enumerate(towers):
        hh = h - (0.4 if (s >= 2 and k % 2) else 0.0)
        top = max(top, cooling_tower(ro, x, y, D + 0.02, hh, rb, rb * 0.66, rb * 0.76, seg=seg, grille=0.55,
                                     slats=6 if s == 0 else None))
        rm.anchor("Vapour%d" % (k + 1), (x, y, D + 0.02 + hh))
        rm.rooms_hi.append((lambda qx, qy, x=x, y=y: hypot(qx - x, qy - y) < rb - 0.4, D + 0.4))
    rm.top_z = max(rm.top_z, top)
    # intake hood units: two beside the towers (M), one in the middle (L, XL)
    if s == 1:
        for x in (Rw * 0.55, -Rw * 0.55):
            vent_box(ro, x, 0.0, D, 1.4, 0.9, 0.7, yaw=90.0, slats=4)
    elif s >= 2:
        vent_box(ro, 0.0, 0.0, D, 1.3, 1.3, 0.8, yaw=45.0, slats=4)
    # levels on the deck (sites chosen clear of the towers)
    q = Rw - 0.9
    if s == 0:
        cfg = dict(ant=(2.4, -1.6, 0.9), mod3=(1.95, 0.0, 90.0), fins4=(-2.4, 1.6, 90.0), annex4=(-1.95, 0.0, 90.0),
                   beacon5=(2.4, 1.6, D + 0.02), emblem5=(-2.4, -1.6, D + 0.05, 0, 0, 1), emblem_size=0.55)
    elif s == 1:
        cfg = dict(ant=(-0.76, -3.45, 0.9), mod3=(2.2, -2.0, 90.0), fins4=(-2.2, 2.0, 90.0), annex4=(-2.3, -1.9, 90.0),
                   beacon5=(2.46, 1.9, D + 0.02), emblem5=(Rw * 0.55, -0.72, D + 0.36, 0, -1, 0),
                   emblem_x=(0, 0, 1), emblem_size=0.5)
    else:
        cfg = dict(ant=polar(q, 150.0)[:2] + (1.1,), mod3=polar(q - 0.2, 270.0)[:2] + (0.0,),
                   fins4=polar(q - 0.1, 30.0)[:2] + (120.0,), annex4=polar(q * 0.45, 150.0)[:2] + (60.0,),
                   beacon5=polar(q, 90.0)[:2] + (D + 0.02,), emblem5=polar(q * 0.5, 270.0)[:2] + (D + 0.05, 0, 0, 1),
                   emblem_size=0.8)
        if s == 3:
            cfg.update(ant=polar(q, 180.0)[:2] + (1.2,), mod3=polar(q, 270.0)[:2] + (0.0,),
                       fins4=polar(q, 90.0)[:2] + (0.0,), annex4=polar(q * 0.3, 90.0)[:2] + (0.0,),
                       beacon5=polar(q, 0.0)[:2] + (D + 0.02,), emblem5=(-q * 0.35, 0.0, D + 0.05, 0, 0, 1))
    levels_podium(rm, cfg)
    # interior: compressors, fans, ducts to the towers, console
    n = rm.interior
    for k, (x, y) in enumerate(towers):
        n.vcyl(x, y, D - 0.55, D - 0.03, rb * 0.7, seg=10, mat="HullDark", cap0=True, cap1=False)
        n.box0(x, y, F, 0.5, 0.5, D - 0.7 - F, "Frame", mats={"-z": None, "+z": None})
        fan_unit(n, x, y, D - 0.80, rb * 0.55, mat="Frame")
    for k in range((1, 2, 3, 4)[s]):
        a = 360.0 * (k + 0.5) / (1, 2, 3, 4)[s] + 90.0
        x, y, _ = polar(tangent_fit(Ri, 0.5, 0.9, 0.08) - 0.2, a)
        with n.at(T(x, y, 0), RZ(a + 90.0)):
            n.box0(0, 0, F, 1.8, 0.9, 0.18, "Frame", mats={"-z": None})
            capsule(n, (-0.6, 0, F + 0.62), (0.6, 0, F + 0.62), 0.40, mat="Metal", seg=8, rings=2)
            n.cyl((0.1, 0, F + 1.02), (0.1, 0, F + 1.3), 0.1, seg=6, mat="Accent")
    with n.at(RZ(0.0 if s else -60.0), T(0.0 if s else 0.5, 0, 0)):
        console(n, w=0.9, glow="Window")


BUILDERS = {
    "oxygen_plant": build_oxygen_plant,
    "water_recycler": build_water_recycler,
    "atmo_processor": build_atmo_processor,
}
