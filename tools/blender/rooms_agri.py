"""
Frontier Habitat 2.0 - ART-A room builders: agri family.
greenhouse (lattice glass dome, trays at content tray_offsets), fungus_farm (dark ribbed dome, racks at the
tray places), algae_bioreactor (ring of glowing tubes round a core), kitchen (dome + extractor chimney).
"""
import math
import random
from math import sin, cos, radians, degrees, hypot, sqrt, atan2
from mathutils import Vector

import rooms_kit as K
from rooms_kit import (T, RX, RY, RZ, S, polar, frame_m, reg_angles, ang_diff, porthole, lamp, antenna, vent_box,
                       fan_unit, capsule, tank_v, pipe, screen, rail_ring, rail_line, ladder, dome_band, drum_band,
                       crown_teeth, lv_module, lv_fins, lv_annex, lv_beacon, lv_emblem, lv_collar_dome, levels_dome,
                       levels_podium, table_round, table_rect, stool, chair, console, cabinet, crate, plant_pot,
                       rug_disc, floor_ring_mark, shelf_rack, workbench, radial_fit, tangent_fit, kiewitt_dome,
                       grid_wall, FLOOR_Z, WALL_TOP, SOIL_Z)
from rooms_habitat import spread, wall_portholes, dome_portholes, roof_vent

F = FLOOR_Z


def tray_offsets(rm):
    offs = rm.bdef.get("sizes", {}).get("tray_offsets")
    if offs:
        return [tuple(o) for o in offs[rm.size]]
    return [tuple(o) for o in rm.bdef.get("tray_offsets", [])]


def rect(cx, cy, hx, hy, z):
    return [(cx + hx, cy - hy, z), (cx + hx, cy + hy, z), (cx - hx, cy + hy, z), (cx - hx, cy - hy, z)]


def crop_tray(n, cx, cy, body="Hull", stripe="Accent"):
    """Tray 3.0 x 1.4 m, soil top exactly at SOIL_Z, centred on (cx, cy) (content tray_offsets)."""
    rim = SOIL_Z + 0.08
    n.loft([rect(cx, cy, 1.5, 0.7, F), rect(cx, cy, 1.5, 0.7, rim), rect(cx, cy, 1.42, 0.62, rim),
            rect(cx, cy, 1.42, 0.62, SOIL_Z)], lambda k, i: body if k != 1 else "Frame", smooth=False, closed=True,
           cap1=True, cap_mat="Soil")
    n.loft([rect(cx, cy, 1.51, 0.71, F + 0.16), rect(cx, cy, 1.51, 0.71, F + 0.24)], stripe, smooth=False, closed=True)


# --------------------------------------------------------------------------------------
# GREENHOUSE: lattice glass dome over crop trays and grow lights
# --------------------------------------------------------------------------------------
def build_greenhouse(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0), bolts=s >= 2, floor_mat="HullDark", accent_floor=False)
    rm.seal_ring()
    H = (3.9, 4.7, 5.5, 6.3)[s]
    rings = (3, 4, 5, 5)[s]
    sectors = (6, 6, 6, 7)[s]
    nodes = kiewitt_dome(rm, H, sectors=sectors, rings=rings, beam=0.10 if s < 2 else 0.12)
    ro = rm.roof
    # crown hub with a vent
    ro.vcyl(0, 0, H - 0.12, H + 0.18, 0.42, seg=10, mat="Frame")
    ro.vcyl(0, 0, H + 0.18, H + 0.26, 0.30, seg=10, mat="Accent")
    rm.top_z = max(rm.top_z, H + 0.26)
    rm.door_hood(depth=0.8)
    # ---- levels: bands on the base wall, parts lifted off the lattice ----------------------------------
    L = rm.L
    drum_band(L[2], Rw, WALL_TOP - 0.06, WALL_TOP + 0.10, 0.05, "Trim", seg=rm.seg)
    pos, _ = rm.dpt(40.0, -135.0, off=0.10)
    antenna(L[2], pos.x, pos.y, pos.z, 1.3 + 0.2 * s)
    drum_band(L[3], Rw, 0.40, 0.48, 0.02, "L3Band", seg=rm.seg, top_edge=False)
    L[3].lathe_a([(0.62, H - 0.02), (0.62, H + 0.22), (0.43, H + 0.22)], reg_angles(10), "Hull")
    L[3].lathe_a([(0.64, H + 0.06), (0.64, H + 0.14)], reg_angles(10), "L3Band")
    pos, _ = rm.dpt(52.0, -60.0, off=0.10)
    lv_module(L[3], pos.x, pos.y, pos.z, yaw=30.0, w=0.9 + 0.15 * s, d=0.7, h=0.45, sink=0.12)
    drum_band(L[4], Rw, 0.54, 0.62, 0.02, "L4Band", seg=rm.seg, top_edge=False)
    pos, _ = rm.dpt(38.0, 100.0, off=0.12)
    lv_fins(L[4], pos.x, pos.y, pos.z, yaw=100.0, n=4 + (s >= 2), h=0.7, length=0.8, sink=0.1)
    pos, _ = rm.dpt(34.0 if s == 0 else 24.0, -80.0, off=0.14)
    lv_annex(L[4], pos.x, pos.y, pos.z - 0.1, yaw=10.0, L=1.4 + 0.25 * s, r=0.40 + 0.03 * s)
    L[5].lathe_a([(0.76, H + 0.20), (0.76, H + 0.34), (0.44, H + 0.34)], reg_angles(10), "L5Gold")
    crown_teeth(L[5], 0.72, H + 0.32, n=8, h=0.22)
    lv_beacon(rm, L[5], 0.0, 0.0, H + 0.26, h=0.7 + 0.1 * s)
    pos, nor = rm.dpt(46.0, -20.0, off=0.14)
    lv_emblem(L[5], pos, nor, size=0.9 + 0.15 * s, xdir=(0, 0, 1))
    # ---- interior: trays at the content offsets, grow light gantries, water tank, bench -----------------
    n = rm.interior
    offs = tray_offsets(rm)
    for (cx, cy) in offs:
        crop_tray(n, cx, cy)
        rm.trays.append((cx, cy))
    zl = 2.35
    rows = sorted(set(round(o[1], 3) for o in offs))
    xs = sorted(set(round(o[0], 3) for o in offs))
    x0, x1 = min(xs) - 1.6, max(xs) + 1.6
    for y in rows:
        for x in (x0, x1):
            n.box0(x, y, F, 0.10, 0.10, zl - F, "Frame", mats={"-z": None, "+z": None})
        n.beam((x0, y, zl + 0.05), (x1, y, zl + 0.05), 0.10, 0.12, "Frame")
        for cx in xs:
            n.box((cx, y, zl - 0.22), (2.7, 0.45, 0.06), "Light")
            n.box((cx, y, zl - 0.17), (2.8, 0.52, 0.05), "Frame", mats={"-z": None})
    # irrigation line along the rows
    for y in rows:
        pipe(n, [(x0, y + 0.78, F + 0.25), (x1, y + 0.78, F + 0.25)], r=0.045, mat="WaterBlue", seg=4, fillet=0.0)
    xt = tangent_fit(Ri, 0.5, 0.5, 0.08)
    ta = 180.0 if s < 3 else 90.0
    tx, ty, _ = polar(xt, ta)
    tank_v(n, tx, ty, F, 1.3 + 0.2 * s, 0.48, mat="Hull", band="WaterBlue", cap="dome", seg=10)
    if s >= 1:
        with n.at(RZ(250.0 if s < 3 else 200.0), T(tangent_fit(Ri, 0.38, 0.9, 0.06), 0, 0)):
            workbench(n, w=1.8, d=0.75, stripe="Accent")
            crate(n, -0.1, 0.45, s=0.35, z=F + 0.87, mat="Soil", band="Frame")


# --------------------------------------------------------------------------------------
# FUNGUS FARM: dark ribbed dome, no glass, violet grow strips, mushroom racks at the tray places
# --------------------------------------------------------------------------------------
def mushroom_rack(n, cx, cy, rng, shelves=(1.30, 2.02)):
    """Rack over a tray place: the bottom bed IS the tray (soil top at SOIL_Z), two shelves with mushrooms and
    violet grow strips (L4Band)."""
    crop_tray(n, cx, cy, body="HullDark", stripe="Accent")
    top = shelves[-1] + 0.10
    for sx in (-1, 1):
        for sy in (-1, 1):
            n.box0(cx + sx * 1.47, cy + sy * 0.67, F, 0.06, 0.06, top + 0.45 - F, "Frame", mats={"-z": None})
    # violet grow-light bar over the rack (seen from above when the roof is open)
    n.box0(cx, cy, top + 0.40, 2.9, 0.20, 0.06, "Frame")
    n.box((cx, cy, top + 0.385), (2.8, 0.16, 0.03), "L4Band", mats={"+z": None})
    nm = 4 if len(shelves) < 3 else 3
    for k, z in enumerate(shelves):
        n.box0(cx, cy, z, 3.0, 1.4, 0.07, "HullDark")
        n.box0(cx, cy, z + 0.07, 2.84, 1.24, 0.02, "Soil", mats={"-z": None})
        n.box((cx, cy, z - 0.02), (2.7, 0.14, 0.03), "L4Band", mats={"+z": None})
        for j in range(nm):
            mx = cx - 1.05 + 2.1 * j / (nm - 1) + rng.uniform(-0.12, 0.12)
            my = cy + rng.uniform(-0.35, 0.35)
            hgt = rng.uniform(0.10, 0.18)
            rr = rng.uniform(0.09, 0.14)
            n.convex([(mx - rr, my - rr, z + 0.09 + hgt * 0.6), (mx + rr, my - rr, z + 0.09 + hgt * 0.6),
                      (mx + rr, my + rr, z + 0.09 + hgt * 0.6), (mx - rr, my + rr, z + 0.09 + hgt * 0.6),
                      (mx, my, z + 0.09 + hgt)], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (0, 3, 2, 1)], "Cargo")


def build_fungus_farm(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(wall="HullDark", kick="Frame", lamps=(160.0, 200.0), bolts=s >= 2, floor_mat="Frame",
                  accent_floor=False)
    H = (3.8, 4.3, 4.8, 5.3)[s]

    def dm(t, a):
        return "Rubber" if t > 70.0 else "Frame"
    rm.build_dome(H, crown="hatch", seams=(8, 12, 14, 16)[s], seam_mat="HullDark",
                  hseams=(30.0,) if s == 0 else (26.0, 52.0), mat=dm, inset=-0.045, cap_mat="Rubber")
    rm.door_hood(depth=0.9)
    ro = rm.roof
    # dark vent louvres round the lower dome and a humidity stack on top
    for a in spread((4, 8, 10, 12)[s], (0.0, 16.0), gap=4.0):
        pos, nor = rm.dpt(16.0, a, off=0.02)
        with ro.at(frame_m(pos, nor, (0, 0, 1))):
            ro.box0(0, 0, -0.02, 0.5, 0.36, 0.08, "HullDark", mats={"-z": None})
            for j in range(2 if s == 0 else 3):
                ro.box((0.0, -0.10 + 0.2 * j / (1 if s == 0 else 2), 0.07), (0.44, 0.05, 0.03), "Rubber",
                       mats={"-z": None})
    for a in (120.0, 240.0):
        pos, _ = rm.dpt(55.0, a)
        roof_vent(ro, pos.x, pos.y, pos.z, r=0.18, cap="Accent")
    levels_dome(rm, dict(band3=(34.0, 36.5), band4=(9.0, 11.0), mod3=(58.0, -60.0), fins4=(45.0, 60.0),
                         annex4=(24.0, -100.0), ant=(56.0, 180.0, 1.2), crown5=(66.0, 69.0), emblem5=(42.0, -25.0),
                         emblem_size=0.85 + 0.12 * s))
    n = rm.interior
    rng = random.Random(40 + s)
    for (cx, cy) in tray_offsets(rm):
        mushroom_rack(n, cx, cy, rng)
        rm.trays.append((cx, cy))
    # humidifier tanks and a misting line
    for k, a in enumerate((90.0, 270.0) if s else (90.0,)):
        x, y, _ = polar(tangent_fit(Ri, 0.4, 0.4, 0.08), a)
        tank_v(n, x, y, F, 1.2, 0.36, mat="Hull", band="Accent", cap="dome", seg=8)
    if s >= 2:
        with n.at(RZ(180.0), T(tangent_fit(Ri, 0.3, 0.6, 0.06), 0, 0)):
            console(n, w=1.0, glow="L4Band")


# --------------------------------------------------------------------------------------
# ALGAE BIOREACTOR: ring of tall glowing tubes round a central core, pipes at the top
# --------------------------------------------------------------------------------------
def glow_tube(p, x, y, z0, z1, r, seg=8, bands=3):
    """Photobioreactor tube: green algae column (PlantDark) with glowing rings (Glow) and frame collars."""
    p.vcyl(x, y, z0, z0 + 0.20, r + 0.07, seg=seg, mat="Frame", cap0=False, cap1=False)
    p.vcyl(x, y, z0 + 0.20, z1 - 0.20, r, seg=seg, mat="PlantDark", cap0=False, cap1=False)
    for k in range(bands):
        zb = z0 + 0.2 + (z1 - z0 - 0.4) * (k + 0.5) / bands
        p.vcyl(x, y, zb - 0.10, zb + 0.10, r + 0.018, seg=seg, mat="Glow", cap0=False, cap1=False)
    p.vcyl(x, y, z1 - 0.20, z1, r + 0.07, seg=seg, mat="Frame", cap0=False)


def build_algae_bioreactor(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0), bolts=s >= 2)
    D = 2.3
    rm.build_podium(D, ribs=(0, 10, 12, 14)[s], band="Accent" if s else None, band_z=1.75, parapet=0.12,
                    deck="HullDark")
    ro = rm.roof
    nt = (6, 8, 10, 12)[s]
    rt = Rw - (0.55, 0.6, 0.7, 0.8)[s]
    th = (2.6, 3.0, 3.4, 3.8)[s]
    tr = (0.22, 0.25, 0.27, 0.30)[s]
    ztop = D + th
    angs = [360.0 * (k + 0.5) / nt for k in range(nt)]
    for a in angs:
        x, y, _ = polar(rt, a)
        glow_tube(ro, x, y, D, ztop, tr, seg=6 if s == 0 else 8, bands=2 if s == 0 else 3)
    # manifold ring over the tube tops
    ms = max(16, nt * 2)
    ro.lathe_a([(rt + 0.12, ztop + 0.02), (rt + 0.12, ztop + 0.18), (rt - 0.12, ztop + 0.18)],
               reg_angles(ms), "Metal", smooth=False)
    # core
    rc = (0.75, 0.9, 1.05, 1.2)[s]
    zc = ztop + 0.8
    if s == 0:
        ro.lathe_a([(rc + 0.12, D), (rc + 0.12, D + 0.3), (rc, zc - 0.6), (rc, zc - 0.4), (rc, zc), (0.0, zc + 0.25)],
                   reg_angles(10), lambda k, i: ("Frame", "HullDark", "Accent", "HullDark", "Frame")[k])
    else:
        ro.lathe_a([(rc + 0.15, D), (rc + 0.15, D + 0.3), (rc, D + 0.35), (rc, zc - 0.6), (rc + 0.04, zc - 0.58),
                    (rc + 0.04, zc - 0.38), (rc, zc - 0.36), (rc, zc), (rc * 0.5, zc + 0.25), (0.0, zc + 0.3)],
                   reg_angles(12), lambda k, i: ("Frame", "Frame", "HullDark", "Accent", "Accent", "Accent",
                                                 "HullDark", "Frame", "Frame")[k])
    for k in range(3 if s == 0 else 4 if s < 2 else 6):
        a = 360.0 * k / (3 if s == 0 else 4 if s < 2 else 6) + 360.0 / nt / 2
        x, y, _ = polar(rt, a)
        cx, cy, _ = polar(rc, a)
        pipe(ro, [(x, y, ztop + 0.18), (x * 0.8, y * 0.8, ztop + 0.55), (cx, cy, zc - 0.2)], r=0.08, mat="Metal",
             seg=6, fillet=0.0 if s == 0 else 0.3)
    rm.anchor("Vent", (0.0, 0.0, zc + 0.3))
    rm.top_z = max(rm.top_z, zc + 0.3)
    if s >= 3:
        for k in range(6):
            a = 30.0 + 60.0 * k
            x, y, _ = polar(rt * 0.62, a)
            glow_tube(ro, x, y, D, ztop - 0.8, tr * 0.8, seg=6)
    # levels
    q = rt - 0.95
    cfg = dict(ant=(q * cos(radians(200)), q * sin(radians(200)), 0.9), mod3=(q * cos(radians(-60)), q * sin(radians(-60)), 30.0),
               fins4=(q * cos(radians(100)), q * sin(radians(100)), 10.0), annex4=(q * cos(radians(-150)), q * sin(radians(-150)), 60.0),
               beacon5=(0.0, 0.0, zc + 0.28), emblem5=(q * cos(radians(20)), q * sin(radians(20)), D + 0.05, 0, 0, 1),
               emblem_size=0.7 + 0.12 * s)
    if s == 0:
        cfg = dict(ant=None, mod3=None, fins4=None, annex4=None, beacon5=(0.0, 0.0, zc + 0.28), emblem5=None)
        L = rm.L
        antenna(L[2], rc * 0.6, 0.0, zc + 0.12, 0.9)
        lv_module(L[3], rt, 0.0, D + 0.05, yaw=90.0, w=0.8, d=0.5, h=0.4, sink=0.03)
        drum_band(L[4], rc, zc - 0.9, zc - 0.82, 0.02, "L4Band", seg=12, top_edge=False)
        lv_fins(L[4], -rt, 0.0, D + 0.05, yaw=90.0, n=3, h=0.6, length=0.6, sink=0.03)
        lv_annex(L[4], 0.0, 1.62, D + 0.3, yaw=0.0, L=1.1, r=0.3)
        pe, ne = Vector((rc * 0.72, -rc * 0.72, zc - 0.1)), Vector((0.7, -0.7, 0.1)).normalized()
        lv_emblem(L[5], pe + ne * 0.03, ne, size=0.55, xdir=(0, 0, 1))
    levels_podium(rm, cfg)
    # interior: pumps, filter columns, culture tanks, console
    n = rm.interior
    for k in range((2, 4, 5, 6)[s]):
        a = 360.0 * (k + 0.5) / (2, 4, 5, 6)[s] + 30.0
        if ang_diff(a, 0.0) < 20:
            a += 30.0
        x, y, _ = polar(tangent_fit(Ri, 0.45, 0.45, 0.08), a)
        tank_v(n, x, y, F, 1.2 + 0.1 * s, 0.42, mat="Glass", band="Frame", cap="dome", seg=6 if s == 0 else 8)
        n.vcyl(x, y, F + 0.05, F + 1.1 + 0.1 * s, 0.34, seg=6 if s == 0 else 8, mat="Glow", cap0=False)
    tank_v(n, 0.0, 0.0, F, D - 0.6, rc, mat="Metal", band="Accent", cap="flat", seg=8 if s == 0 else 12)
    for k in range(2 if s == 0 else 4):
        a = (180.0 if s == 0 else 90.0) * k + 45.0
        x, y, _ = polar(rc + 0.9, a)
        n.box0(x, y, F, 0.6, 0.5, 0.55, "HullDark", mats={"-z": None})
        n.cyl((x, y, F + 0.45), (x * 0.55, y * 0.55, F + 0.45), 0.07, seg=6, mat="Metal")
    with n.at(RZ(180.0), T(tangent_fit(Ri, 0.3, 0.5, 0.06), 0, 0)):
        console(n, w=0.9, glow="Glow")


# --------------------------------------------------------------------------------------
# KITCHEN & MESS: dome with an extractor chimney and a service hatch; dining tables inside
# --------------------------------------------------------------------------------------
def chimney(p, x, y, z0, z1, r=0.34, band="Accent"):
    p.vcyl(x, y, z0, z0 + 0.35, r + 0.22, r + 0.12, seg=10, mat="Frame", cap0=False)
    p.vcyl(x, y, z0 + 0.3, z1, r, seg=10, mat="Metal", cap0=False, cap1=False)
    p.vcyl(x, y, z1 - 0.7, z1 - 0.45, r + 0.03, seg=10, mat=band, cap0=False, cap1=False)
    with p.at(T(x, y, z1)):
        p.lathe([(r + 0.02, 0.0), (r + 0.25, 0.05), (r + 0.25, 0.14), (r * 0.5, 0.32), (0.0, 0.34)],
                lambda k, i: "Frame" if k < 2 else "HullDark", seg=10)
    for k in range(4):
        a = radians(45 + 90 * k)
        p.beam((x + (r + 0.02) * cos(a), y + (r + 0.02) * sin(a), z1 - 0.02),
               (x + (r + 0.22) * cos(a), y + (r + 0.22) * sin(a), z1 + 0.10), 0.04, 0.04, "Frame")
    return z1 + 0.34


def build_kitchen(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(windows=(0.52, 0.82) if s >= 1 else None, win_seams=(10, 12, 14, 16)[s], lamps=(160.0, 200.0),
                  bolts=s >= 2)
    H = (3.5, 4.1, 4.7, 5.3)[s]
    rm.build_dome(H, crown="hatch" if s < 2 else "skylight", seams=8, crown_t=(79.0, 79.0, 74.0, 72.0)[s])
    rm.door_hood(depth=0.9)
    ro = rm.roof
    cook_a = 180.0
    rck = Ri - 0.7
    chims = [(cook_a, 0.0)] if s < 2 else [(cook_a - 22.0, 0.0), (cook_a + 22.0, 0.0)]
    top = rm.top_z
    for a, _ in chims:
        x, y, _ = polar(rck - 0.45, a)
        zd = rm.dome_z(x, y)
        top = max(top, chimney(ro, x, y, zd - 0.3, zd + 1.3 + 0.2 * s, r=0.30 + 0.03 * s))
        rm.anchor("Smoke" if len(chims) == 1 else "Smoke%d" % (1 + chims.index((a, 0.0))), (x, y, zd + 1.3 + 0.2 * s + 0.35))
    rm.top_z = max(rm.top_z, top)
    # service hatch dormer on the -Y side
    ha = -95.0
    hx, hy, _ = polar(Rw - 0.55, ha)
    with ro.at(T(hx, hy, 0), RZ(ha)):
        ro.box0(-0.2, 0, WALL_TOP - 0.02, 1.2, 1.5, 1.2, "Hull", mats={"-z": None})
        ro.box0(-0.2, 0, WALL_TOP + 1.16, 1.3, 1.62, 0.08, "Frame")
        ro.box((0.41, 0, WALL_TOP + 0.55), (0.012, 1.1, 0.9), "HullDark", mats={"-x": None})
        for k in range(4):
            ro.box((0.42, 0, WALL_TOP + 0.2 + 0.22 * k), (0.012, 1.1, 0.03), "Frame", mats={"-x": None})
        ro.box((0.42, 0, WALL_TOP + 1.05), (0.012, 1.2, 0.08), "Accent", mats={"-x": None})
    # roof fan units
    for a in ((40.0,) if s < 2 else (35.0, 110.0)):
        pos, _ = rm.dpt(52.0, a)
        ro.box0(pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.25, 0.9, 0.9, 0.45, "HullDark", mats={"-z": None})
        fan_unit(ro, pos.x, pos.y, rm.dome_z(pos.x, pos.y) + 0.2, 0.36)
    pb, _ = rm.dpt(56.0, 140.0)
    levels_dome(rm, dict(band3=(30.0, 32.5), band4=(15.0, 17.5), mod3=(58.0, -40.0), fins4=(50.0, 110.0 if s < 2 else 70.0),
                         annex4=(24.0, -150.0), ant=(56.0, -140.0, 1.2), crown5=(65.0, 68.0) if s < 2 else (60.0, 63.0),
                         emblem5=(44.0, -60.0),
                         beacon5=(0.0, 0.0, rm.crown_z + 0.12) if s < 2 else (pb.x, pb.y, rm.dome_z(pb.x, pb.y) - 0.02)))
    # interior: cooking line along the back wall, hood, fridge units, tables
    n = rm.interior
    span = (70.0, 80.0, 90.0, 100.0)[s]
    a0, a1 = cook_a - span / 2, cook_a + span / 2
    ro_, ri_ = Ri - 0.08, Ri - 0.80
    n.lathe([(ro_, F), (ro_, F + 0.90), (ri_, F + 0.90), (ri_, F)], "Hull", seg=6, a0=a0, a1=a1, smooth=False)
    n.lathe([(ro_ + 0.01, F + 0.90), (ro_ + 0.01, F + 0.95), (ri_ - 0.03, F + 0.95), (ri_ - 0.03, F + 0.90)], "Metal",
            seg=6, a0=a0, a1=a1, smooth=False, caps=False)
    rc = (ro_ + ri_) / 2
    nh = (2, 3, 4, 5)[s]
    for k in range(nh):
        a = a0 + span * (k + 0.5) / nh
        with n.at(RZ(a), T(rc, 0, F + 0.95)):
            n.box0(0, 0, 0, 0.6, 0.62, 0.04, "Frame")
            n.box((0.0, -0.15, 0.05), (0.26, 0.2, 0.012), "Window", mats={"-z": None})
            n.box((0.0, 0.15, 0.05), (0.26, 0.2, 0.012), "Window", mats={"-z": None})
    n.lathe([(ro_ - 0.1, F + 1.72), (ro_ - 0.1, F + 1.92), (ri_, F + 1.92), (ri_, F + 1.72)], "Accent", seg=6,
            a0=a0 + 4, a1=a1 - 4, smooth=False)
    for a in (a0 - 10.0, a1 + 10.0):
        with n.at(RZ(a), T(tangent_fit(Ri, 0.35, 0.45, 0.06), 0, 0)):
            n.box0(0, 0, F, 0.7, 0.9, 1.9, "Hull", mats={"-z": None})
            n.box((-0.356, 0, F + 1.0), (0.012, 0.8, 1.6), "HullDark", mats={"+x": None})
            n.box((-0.362, 0.3, F + 1.0), (0.012, 0.05, 0.6), "Frame", mats={"+x": None})
    # dining tables with chairs
    nt = (1, 2, 3, 5)[s]
    if nt == 1:
        places = [(0.5, 0.0, 90.0)]
    else:
        rr = (0.0, 1.35, 1.9, 2.7)[s]
        places = []
        for k in range(nt):
            a = -span / 2 + 360.0 * (k + 0.5) / nt
            x, y, _ = polar(rr, a + 20.0)
            places.append((x, y, a + 20.0 + 90.0))
        if s == 3:
            places.append((0.0, 0.0, 0.0))
    for (x, y, yaw) in places:
        table_rect(n, x, y, 1.6, 0.8, 0.74, yaw=yaw, top="Hull")
        for sx in (-0.45, 0.45):
            for sy in (-1, 1):
                cx = x + cos(radians(yaw)) * sx - sin(radians(yaw)) * sy * 0.62
                cy = y + sin(radians(yaw)) * sx + cos(radians(yaw)) * sy * 0.62
                chair(n, cx, cy, yaw=yaw - 90.0 * sy)
    if s >= 1:
        with n.at(RZ(-40.0), T(tangent_fit(Ri, 0.3, 0.8, 0.06), 0, 0)):
            cabinet(n, w=1.6, d=0.6, h=1.0, stripe="Accent")


BUILDERS = {
    "greenhouse": build_greenhouse,
    "fungus_farm": build_fungus_farm,
    "algae_bioreactor": build_algae_bioreactor,
    "kitchen": build_kitchen,
}
