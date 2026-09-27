"""Frontier Habitat 4.0 industry rooms (SIM list 2026-09-27, docs/requests/SIM-to-ART-HAB.md): the roofs.
Industry family identity (V4_DESIGN 3.1): a flat deck with stacks and vents, the gear badge (rooms_identity, the
generic pass), the stronger band.  Each type has its own roof machine so it reads apart from the others.
Interiors: interior_fam_v4ind.py (machines for interior_fam_ind.industry)."""
from math import sin, cos, radians, hypot, sqrt, pi, atan2, degrees

import rooms_kit as K
from rooms_kit import T, RX, RY, RZ, polar, hall, fan_unit, vent_box, tank_v, levels_podium, auto_sites, WALL_TOP
import rooms_identity as RI
from rooms_industry import industrial_base, rect_obstacles

# SIM 2026-09-27: kind room, sizes S-XL, radii 6 / 7.5 / 9.6 / 11.7, 1-3 work places (as the v3 industry rooms)
V4_ROOMS = ("steel_mill", "titanium_smelter", "ceramics_kiln", "carbon_works", "battery_plant", "parts_works",
            "magnet_works", "superconductor_lab", "metamaterial_foundry")
PROVISIONAL_DEF = {"kind": "room", "category": "industry", "family": "industry",
                   "sizes": {"radius": [6.0, 7.5, 9.6, 11.7], "work_slots": [1, 1, 2, 3]},
                   "furniture": {"beds": [0, 0, 0, 0], "seats": [0, 0, 0, 0], "work_slots": [1, 1, 2, 3],
                                 "stands": [1, 2, 2, 3], "work_pose": "stand"}}


def _deck(rm, D=2.6, wall="HullDark", deck="Frame"):
    s = rm.size
    industrial_base(rm)
    rm.build_podium(D, ribs=(10, 14, 16, 20)[s], band="Accent", band_z=D - 0.62, parapet=0.14, wall=wall, deck=deck)
    rm.no_extras = True               # the builder has its own stacks: the identity pass adds only the badge
    return rm.roof, D


def _finish(rm, obst, D, top):
    rm.top_z = max(rm.top_z, top)
    # keep the badge place free: the deck quarter on -Y toward the game camera
    obst = list(obst) + [(0.0, -0.52 * rm.Rw, 0.34 * rm.Rw + 0.3)]
    levels_podium(rm, auto_sites(rm, obst, D))
    rm.badge_done = True
    RI.badge(rm.roof, "industry", 0.0, -0.52 * rm.Rw, 0.30 * rm.Rw, lambda x, y: D + 0.02, lift=0.015)


def build_steel_mill(rm):
    """A squat furnace hall with a tall stack and ladle rails; a glowing pour window."""
    ro, D = _deck(rm)
    Rw, s = rm.Rw, rm.size
    cx, cy, a, b = -0.10 * Rw, 0.22 * Rw, 0.46 * Rw, 0.32 * Rw
    top = hall(ro, cx, cy, a, b, D + 0.02, D + 2.0 + 0.2 * s, roof="gable", wall="HullDark", roof_mat="Frame",
               band="Accent", windows=False)
    # the pour window on the -Y face (Ember glow) and a hood over it
    ro.box((cx, cy - b - 0.01, D + 1.0), (a * 0.9, 0.02, 0.7), "Ember", mats={"+y": None})
    ro.box((cx, cy - b - 0.25, D + 1.55), (a * 1.0, 0.5, 0.12), "Frame")
    obst = rect_obstacles(cx, cy, a, b)
    # the tall stack at the hall's end
    sx, sy = cx - a + 0.6, cy + b + 0.7
    top = max(top, RI.stack(ro, rm.lights, sx, sy, D, 7.0 + 0.6 * s, 0.55 + 0.05 * s, bands=3))
    obst.append((sx, sy, 1.0))
    # ladle rails from the pour window across the deck, a ladle car on them
    for dy in (-0.45, 0.45):
        ro.box0(cx, cy - b - 1.2 + dy, D + 0.02, 2 * a, 0.10, 0.10, "Metal")
    lx, ly = cx + a * 0.3, cy - b - 1.2
    ro.box0(lx, ly, D + 0.12, 1.2, 1.1, 0.25, "HullDark")
    ro.lathe([(0.0, D + 0.37), (0.45, D + 0.37), (0.55, D + 1.1), (0.50, D + 1.15)], "Frame", seg=10) if False else None
    with ro.at(T(lx, ly, 0.0)):
        ro.lathe([(0.35, D + 0.37), (0.55, D + 1.15), (0.48, D + 1.15), (0.30, D + 0.45)], "Frame", seg=10)
        ro.cap_disc(0.48, D + 1.12, "Ember", seg=10)
    obst.append((lx, ly, 1.0))
    _finish(rm, obst, D, top)


def build_titanium_smelter(rm):
    """An electric arc furnace dome with thick cables to a transformer yard."""
    ro, D = _deck(rm)
    Rw, s = rm.Rw, rm.size
    fx, fy, fr = -0.18 * Rw, 0.22 * Rw, 0.26 * Rw
    with ro.at(T(fx, fy, 0.0)):
        prof = [(fr + 0.2, D), (fr + 0.2, D + 0.4), (fr, D + 0.5)] + \
               [(fr * cos(radians(t)), D + 0.5 + fr * 0.8 * sin(radians(t))) for t in range(15, 91, 15)]
        ro.lathe(prof, lambda k, i: "HullDark" if k != 2 else "Ember", seg=20)
        for k in range(3):                             # the three electrodes through the roof
            x_, y_, _ = polar(fr * 0.35, 120.0 * k + 90.0)
            ro.vcyl(x_, y_, D + 0.5 + fr * 0.6, D + 0.5 + fr * 0.8 + 1.4, 0.16, seg=8, mat="Metal")
            ro.vcyl(x_, y_, D + 0.5 + fr * 0.8 + 1.1, D + 0.5 + fr * 0.8 + 1.25, 0.2, seg=8, mat="Hazard",
                    cap0=False, cap1=False)
    top = D + 0.5 + fr * 0.8 + 1.5
    obst = [(fx, fy, fr + 0.4)]
    # the transformer yard: three finned transformers behind a low fence
    tx, ty = 0.42 * Rw, 0.30 * Rw
    for k in range(3):
        bx, by = tx + (k - 1) * 0.0, ty + (k - 1) * 1.2
        ro.box0(bx, by, D, 1.0, 0.9, 1.4, "HullDark", bevel=0.03)
        for j in range(5):
            ro.box0(bx + 0.55, by - 0.36 + 0.18 * j, D + 0.15, 0.10, 0.04, 1.1, "Frame")
        for j in range(3):
            ro.vcyl(bx - 0.25 + 0.25 * j, by, D + 1.4, D + 1.85, 0.06, seg=6, mat="Hull")
        # thick cables to the furnace
        ro.tube([(bx - 0.5, by, D + 1.1), ((bx + fx) / 2, (by + fy) / 2, D + 0.3),
                 (fx + fr + 0.2, fy, D + 0.35)], 0.09, seg=6, mat="Rubber", caps=False)
    obst += [(tx, ty, 2.1)]
    ro.box0(tx - 0.7, ty, D, 0.06, 4.0, 0.9, "Hazard")
    _finish(rm, obst, D, top)


def build_ceramics_kiln(rm):
    """A long low tunnel kiln with vents along its roof."""
    ro, D = _deck(rm)
    Rw, s = rm.Rw, rm.size
    ky, kl, kh = 0.28 * Rw, 0.72 * Rw, 1.3
    x0, x1 = -kl, kl * 0.9
    # the tunnel: a half-cylinder vault along X on a plinth, glowing mouths at both ends
    ro.box0((x0 + x1) / 2, ky, D, x1 - x0, 2.0, 0.35, "Frame")
    n = 10
    arc = [(0.9 * cos(pi * k / n), D + 0.35 + kh * sin(pi * k / n)) for k in range(n + 1)]
    for k in range(n):
        (ya, za), (yb, zb) = arc[k], arc[k + 1]
        ro.f([ro.v((x0, ky + ya, za)), ro.v((x1, ky + ya, za)), ro.v((x1, ky + yb, zb)), ro.v((x0, ky + yb, zb))],
             "HullDark", smooth=True)
    for xe, sg in ((x0, -1), (x1, 1)):
        c0 = ro.v((xe, ky, D + 0.35))
        ids = [ro.v((xe, ky + y, z)) for (y, z) in arc]
        for k in range(n):
            ro.f([c0, ids[k], ids[k + 1]] if sg > 0 else [c0, ids[k + 1], ids[k]], "Frame")
        ro.box((xe + sg * 0.02, ky, D + 0.75), (0.02, 0.9, 0.55), "Ember",
               mats={("-x" if sg > 0 else "+x"): None})
    for k in range(int((x1 - x0) / 0.9)):             # ribs
        xr = x0 + 0.45 + 0.9 * k
        for j in range(n):
            (ya, za), (yb, zb) = arc[j], arc[j + 1]
            ro.beam((xr, ky + ya * 1.02, za), (xr, ky + yb * 1.02, zb), 0.06, 0.06, "Frame")
    top = D + 0.35 + kh
    nv = 4 + s
    for k in range(nv):                               # the roof vents: short stacks with caps
        xv = x0 + (x1 - x0) * (k + 0.5) / nv
        ro.vcyl(xv, ky, top - 0.1, top + 0.8, 0.16, seg=8, mat="Metal", cap1=False)
        ro.vcyl(xv, ky, top + 0.8, top + 0.9, 0.24, seg=8, mat="Frame")
    obst = [(x0 + (x1 - x0) * (k + 0.5) / 5, ky, 1.2) for k in range(5)]
    # a kiln-car siding with loaded cars
    for k in range(2 + s // 2):
        cx_ = x0 + 0.8 + 1.4 * k
        ro.box0(cx_, ky - 1.8, D, 1.1, 0.8, 0.35, "HullDark")
        ro.box0(cx_, ky - 1.8, D + 0.35, 0.9, 0.6, 0.45, "Cargo")
    obst.append((x0 + 1.5, ky - 1.8, 1.5))
    top = max(top + 1.0, rm.top_z)
    _finish(rm, obst, D, top)


def build_carbon_works(rm):
    """Spinning towers and fibre spools stacked outside."""
    ro, D = _deck(rm)
    Rw, s = rm.Rw, rm.size
    top = D
    obst = []
    nt = 2 + (1 if s >= 2 else 0)
    for k in range(nt):
        tx, ty = (-0.35 + 0.30 * k) * Rw, 0.35 * Rw
        h = 5.5 + 0.5 * s - 0.6 * k
        ro.box0(tx, ty, D, 1.0, 1.0, 0.4, "Frame")
        ro.vcyl(tx, ty, D + 0.4, D + h, 0.38, 0.32, seg=10, mat="Hull")
        for zz in (0.35, 0.6, 0.85):
            ro.vcyl(tx, ty, D + h * zz, D + h * zz + 0.14, 0.40, seg=10, mat="Accent", cap0=False, cap1=False)
        ro.vcyl(tx, ty, D + h, D + h + 0.3, 0.46, seg=10, mat="Frame")
        # a fibre line from the tower top down to a winder
        ro.cyl((tx + 0.3, ty, D + h - 0.2), (tx + 1.1, ty - 1.2, D + 0.9), 0.02, seg=4, mat="Rubber", cap0=False,
               cap1=False)
        ro.box0(tx + 1.1, ty - 1.2, D, 0.6, 0.5, 0.8, "HullDark")
        ro.sphere((tx, ty, D + h + 0.4), 0.09, "Light", seg=6, rings=3)
        top = max(top, D + h + 0.5)
        obst.append((tx, ty, 0.9))
        obst.append((tx + 1.1, ty - 1.2, 0.6))
    # stacked fibre spools (black carbon on metal cores) on pallets
    for j in range(2 + s):
        px, py = 0.55 * Rw, (-0.10 + 0.22 * j) * Rw
        if hypot(px, py) > Rw - 1.3:
            continue
        ro.box0(px, py, D, 1.2, 1.0, 0.14, "Wood")
        for i in range(2):
            for lv in range(2):
                with ro.at(T(px - 0.28 + 0.56 * i, py, D + 0.14 + 0.44 * lv + 0.22), RX(90.0)):
                    ro.cyl((0, 0, -0.42), (0, 0, 0.42), 0.22, seg=10, mat="Rubber")
                    ro.cyl((0, 0, -0.44), (0, 0, 0.44), 0.07, seg=6, mat="Metal")
        obst.append((px, py, 0.9))
    _finish(rm, obst, D, top)


def build_battery_plant(rm):
    """A clean hall with racks of cells and blue status lights."""
    ro, D = _deck(rm, wall="Hull", deck="HullDark")
    Rw, s = rm.Rw, rm.size
    cx, cy, a, b = -0.05 * Rw, 0.25 * Rw, 0.50 * Rw, 0.30 * Rw
    top = hall(ro, cx, cy, a, b, D + 0.02, D + 2.2 + 0.2 * s, roof="flat", wall="Hull", roof_mat="HullDark",
               band="Accent", windows=True, win_mat="L3Band")
    obst = rect_obstacles(cx, cy, a, b)
    # outdoor cell racks (container-like modules) with blue status strips
    for k in range(2 + s):
        rx, ry = (-0.45 + 0.32 * k) * Rw, -0.20 * Rw
        if hypot(rx, ry) > Rw - 1.4:
            continue
        ro.box0(rx, ry, D, 1.5, 0.9, 1.6, "Hull", bevel=0.03)
        for j in range(4):
            ro.box((rx, ry - 0.46, D + 0.35 + 0.32 * j), (1.2, 0.02, 0.06), "L3Band", mats={"+y": None})
        ro.box0(rx, ry, D + 1.6, 1.6, 1.0, 0.08, "Frame")
        obst.append((rx, ry, 1.0))
    for (vx, vy) in ((0.62 * Rw, 0.10 * Rw),):
        ro.box0(vx, vy, D, 0.9, 0.9, 0.55, "HullDark")
        fan_unit(ro, vx, vy, D + 0.55, 0.36)
        obst.append((vx, vy, 0.7))
    _finish(rm, obst, D, top)


def build_parts_works(rm):
    """An assembly bay with a gantry and a wheel rack."""
    ro, D = _deck(rm)
    Rw, s = rm.Rw, rm.size
    gx0, gx1, gy = -0.50 * Rw, 0.45 * Rw, 0.25 * Rw
    gw, gh = 1.6 + 0.2 * s, 3.2 + 0.2 * s
    for x_ in (gx0, gx1):                             # the gantry: two legs frames and a girder
        for sy in (-1, 1):
            ro.box0(x_, gy + sy * gw, D, 0.25, 0.25, gh, "Hazard")
        ro.beam((x_, gy - gw, D + gh), (x_, gy + gw, D + gh), 0.22, 0.28, "Frame")
    for sy in (-1, 1):
        ro.beam((gx0, gy + sy * gw, D + gh + 0.2), (gx1, gy + sy * gw, D + gh + 0.2), 0.20, 0.26, "Frame")
    hx = (gx0 + gx1) / 2 + 0.6
    ro.box0(hx, gy, D + gh - 0.5, 0.7, 2 * gw + 0.3, 0.45, "HullDark")
    ro.vcyl(hx, gy, D + 1.2, D + gh - 0.5, 0.03, seg=4, mat="Metal", cap0=False)
    ro.box0(hx, gy, D + 0.8, 0.5, 0.5, 0.4, "Frame")
    top = D + gh + 0.5
    obst = [(x_, gy, gw + 0.4) for x_ in (gx0, (gx0 + gx1) / 2, gx1)]
    # a rover chassis under the gantry
    ro.box0((gx0 + gx1) / 2 - 0.3, gy, D + 0.35, 2.6, 1.6, 0.35, "Accent")
    # the wheel rack: big rover wheels on a frame
    wx, wy = 0.25 * Rw, -0.20 * Rw
    ro.box0(wx, wy, D, 2.6, 0.3, 0.1, "Frame")
    for k in range(3):
        with ro.at(T(wx - 0.9 + 0.9 * k, wy, D + 0.55), RX(90.0)):
            ro.torus(0.40, 0.14, "Rubber", seg=14, tseg=6, z=0.0)
            ro.cyl((0, 0, -0.14), (0, 0, 0.14), 0.26, seg=10, mat="Metal")
    for sx in (-1.25, 1.25):
        ro.box0(wx + sx, wy, D, 0.1, 0.3, 1.1, "Frame")
    obst.append((wx, wy, 1.5))
    _finish(rm, obst, D, top)


def build_magnet_works(rm):
    """A furnace and press line with a large ring magnet on a stand."""
    ro, D = _deck(rm)
    Rw, s = rm.Rw, rm.size
    cx, cy, a, b = -0.20 * Rw, 0.28 * Rw, 0.36 * Rw, 0.26 * Rw
    top = hall(ro, cx, cy, a, b, D + 0.02, D + 1.9, roof="saw", wall="HullDark", roof_mat="Frame", band="Accent",
               teeth=2 + s // 2, saw_glass="Window", windows=False)
    obst = rect_obstacles(cx, cy, a, b)
    sx, sy = cx - a + 0.5, cy + b + 0.6
    top = max(top, RI.stack(ro, rm.lights, sx, sy, D, 5.0 + 0.4 * s, 0.40))
    obst.append((sx, sy, 0.8))
    # the ring magnet on its stand, copper coils (Hazard-orange accent) and a dark core
    mx, my, mr = 0.40 * Rw, 0.05 * Rw, 1.1 + 0.15 * s
    ro.box0(mx, my, D, 1.0, 0.8, 0.5, "Frame")
    for sx_ in (-0.35, 0.35):
        ro.box0(mx + sx_, my, D + 0.5, 0.14, 0.5, mr, "Frame")
    with ro.at(T(mx, my, D + 0.5 + mr + 0.15), RY(90.0)):
        ro.torus(mr, 0.26, "Metal", seg=24, tseg=8, z=0.0)
        for k in range(8):
            with ro.at(RZ(45.0 * k)):
                ro.box((mr, 0.0, 0.0), (0.2, 0.38, 0.58), "Accent")
    top = max(top, D + 0.5 + 2 * mr + 0.5)
    obst.append((mx, my, mr + 0.4))
    _finish(rm, obst, D, top)


def build_superconductor_lab(rm):
    """Cryostat drums, a white clean room and frost vents."""
    ro, D = _deck(rm, wall="Hull", deck="HullDark")
    Rw, s = rm.Rw, rm.size
    cx, cy, a, b = 0.10 * Rw, 0.30 * Rw, 0.36 * Rw, 0.26 * Rw
    top = hall(ro, cx, cy, a, b, D + 0.02, D + 2.0, roof="flat", wall="Hull", roof_mat="Hull", band="Accent",
               windows=True, win_mat="Screen")
    obst = rect_obstacles(cx, cy, a, b)
    for k in range(2 + s):                            # cryostat drums with frost bands and cryo pipes
        dx, dy = -0.55 * Rw, (0.30 - 0.26 * k) * Rw
        if hypot(dx, dy) > Rw - 1.2:
            continue
        tank_v(ro, dx, dy, D, 1.6, 0.55, mat="Hull", band="Frost", cap="dome", seg=12)
        ro.vcyl(dx, dy, D + 0.25, D + 0.45, 0.57, seg=12, mat="Frost", cap0=False, cap1=False)
        ro.tube([(dx + 0.5, dy, D + 1.3), (cx - a, dy * 0.5 + cy * 0.5, D + 1.3)], 0.06, seg=6, mat="Frost",
                caps=False)
        obst.append((dx, dy, 0.8))
    for (vx, vy) in ((0.60 * Rw, -0.05 * Rw), (0.45 * Rw, -0.28 * Rw)):
        ro.vcyl(vx, vy, D, D + 1.8, 0.2, seg=8, mat="Frost")
        ro.vcyl(vx, vy, D + 1.8, D + 1.95, 0.28, seg=8, mat="Frame")
        obst.append((vx, vy, 0.5))
    _finish(rm, obst, D, max(top, D + 2.1))


def build_metamaterial_foundry(rm):
    """A dark hall with a violet field chamber (links to the crystal refinery)."""
    ro, D = _deck(rm, wall="HullDark", deck="Rubber")
    Rw, s = rm.Rw, rm.size
    cx, cy, a, b = -0.25 * Rw, 0.25 * Rw, 0.32 * Rw, 0.30 * Rw
    top = hall(ro, cx, cy, a, b, D + 0.02, D + 2.1, roof="barrel", wall="HullDark", roof_mat="Rubber",
               band="Accent", windows=True, win_mat="L4Band")
    obst = rect_obstacles(cx, cy, a, b)
    # the field chamber: a cage of posts round a violet glowing core on a plinth, ring coils above
    fx, fy, fr = 0.38 * Rw, 0.10 * Rw, 1.2 + 0.1 * s
    ro.vcyl(fx, fy, D, D + 0.35, fr + 0.3, seg=16, mat="Frame")
    for k in range(8):
        x_, y_, _ = polar(fr, 45.0 * k)
        ro.vcyl(fx + x_, fy + y_, D + 0.35, D + 2.8, 0.07, seg=6, mat="Metal")
    for zz in (1.2, 2.2):
        with ro.at(T(fx, fy, D + zz)):
            ro.torus(fr, 0.08, "L4Band", seg=20, tseg=5, z=0.0)
    ro.sphere((fx, fy, D + 1.6), 0.55, "L4Band", seg=12, rings=6)
    with ro.at(T(fx, fy, D + 2.8)):
        ro.torus(fr, 0.12, "Frame", seg=20, tseg=5, z=0.0)
    top = max(top, D + 3.0)
    obst.append((fx, fy, fr + 0.5))
    _finish(rm, obst, D, top)


BUILDERS = {"steel_mill": build_steel_mill, "titanium_smelter": build_titanium_smelter,
            "ceramics_kiln": build_ceramics_kiln, "carbon_works": build_carbon_works,
            "battery_plant": build_battery_plant, "parts_works": build_parts_works,
            "magnet_works": build_magnet_works, "superconductor_lab": build_superconductor_lab,
            "metamaterial_foundry": build_metamaterial_foundry}
