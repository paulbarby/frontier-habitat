"""
Frontier Habitat 2.0 - ART-A room builders: science family.
research_lab: stacked hexagonal pods on a podium and an observatory dome with a slit and a telescope.
S: 1 pod, M: 2 pods, L: 3 pods (one stacked), XL: 4 pods (two stacked) + a dish antenna.
"""
import math
from math import sin, cos, radians, degrees, hypot, sqrt
from mathutils import Vector

import rooms_kit as K
from rooms_kit import (T, RX, RY, RZ, S, polar, frame_m, reg_angles, columns, col_mid_fn, ang_diff, porthole,
                       antenna, dish, fan_unit, tank_v, pipe, screen, rail_ring, ladder, drum_band, lv_module, lv_fins,
                       lv_annex, lv_beacon, lv_emblem, levels_podium, table_round, stool, chair, console, cabinet,
                       workbench, tangent_fit, hex_pod, FLOOR_Z, WALL_TOP)

F = FLOOR_Z


def observatory(p, cx, cy, z0, r, slit_a=-60.0, seg=16):
    """Short drum + dome with an open slit (dark strip) and a telescope looking out of it."""
    dh = 0.85
    with p.at(T(cx, cy, 0)):
        p.lathe_a([(r + 0.06, z0), (r + 0.06, z0 + 0.12), (r, z0 + 0.14), (r, z0 + dh), (r + 0.05, z0 + dh),
                   (r + 0.05, z0 + dh + 0.10)], reg_angles(seg), lambda k, i: ("Frame", "Frame", "Hull", "Frame", "Frame")[k])
    cols, kind, sc = columns(seg, [slit_a], seam_w=degrees(0.55 / r))
    zb = z0 + dh + 0.10
    ts = (0, 22, 45, 68, 84)
    prof = [((r - 0.02) * cos(radians(t)), zb + (r - 0.02) * 0.92 * sin(radians(t))) for t in ts]
    with p.at(T(cx, cy, 0)):
        p.lathe_a(prof, cols, lambda k, i: "Rubber" if kind[i] == "s" else "Hull")
        ztop = prof[-1][1]
        p.cap_disc(prof[-1][0], ztop, "Frame", seg=8)
        # slit rails
        for side in (-1, 1):
            a = radians(slit_a + side * degrees(0.34 / r))
            pts = [Vector(((r + 0.01) * cos(radians(t)) * cos(a), (r + 0.01) * cos(radians(t)) * sin(a),
                           zb + (r + 0.01) * 0.92 * sin(radians(t)))) for t in (0, 30, 60, 84)]
            p.beam_path(pts, 0.07, 0.07, "Frame")
        # telescope: tube on a fork, looking out of the slit
        el = 48.0
        d = Vector((cos(radians(slit_a)) * cos(radians(el)), sin(radians(slit_a)) * cos(radians(el)), sin(radians(el))))
        c0 = Vector((0, 0, zb + 0.15))
        p.cyl(c0 - d * 0.5, c0 + d * (r * 0.95), 0.26, seg=8, mat="Hull")
        p.cyl(c0 + d * (r * 0.95 - 0.12), c0 + d * (r * 0.95 + 0.05), 0.29, seg=8, mat="Accent", cap0=False)
    return ztop


def build_research_lab(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(windows=(0.50, 0.84) if s else None, win_seams=(10, 14, 16, 20)[s], lamps=(160.0, 200.0),
                  bolts=s >= 2)
    D = 2.4
    rm.build_podium(D, ribs=(8, 12, 14, 16)[s], band="Accent", band_z=D - 0.5, parapet=0.14)
    ro = rm.roof
    lay = {0: dict(obs=(-1.25, -0.55, 1.30), pods=[(1.30, 1.0, 1.10, 1)]),
           1: dict(obs=(-1.6, -0.9, 1.55), pods=[(1.55, 1.35, 1.20, 1), (1.45, -1.95, 1.05, 1)]),
           2: dict(obs=(-2.2, -1.2, 1.85), pods=[(1.9, 1.9, 1.35, 2), (2.3, -2.3, 1.25, 1), (-1.7, 2.9, 1.1, 1)]),
           3: dict(obs=(-2.9, -1.5, 2.15), pods=[(2.5, 2.3, 1.5, 2), (2.9, -2.6, 1.4, 2), (-1.5, 3.9, 1.2, 1),
                                                 (0.4, -4.6, 1.0, 1)])}[s]
    ox, oy, orr = lay["obs"]
    top = observatory(ro, ox, oy, D, orr, slit_a=-60.0, seg=12 if s == 0 else 16)
    rm.top_z = max(rm.top_z, top)
    rm.anchor("Telescope", (ox, oy, top))
    for k, (px, py, pr, lev) in enumerate(lay["pods"]):
        z = D + 0.02
        for L_ in range(lev):
            z = hex_pod(ro, px, py, pr, z, 1.75, rot=30.0 + 15.0 * k, windows=(0, 2, 4) if L_ == 0 else (1, 3, 5),
                        chamfer=0.28) + (0.0 if L_ == lev - 1 else -0.03)
            if L_ < lev - 1:
                z += 0.0
        rm.top_z = max(rm.top_z, z)
        # a small roof unit on each top pod
        fan_unit(ro, px, py, z, pr * 0.32)
    # connecting tubes pod <-> observatory at deck level
    for (px, py, pr, lev) in lay["pods"][:2]:
        pipe(ro, [(px, py, D + 0.45), (ox, oy, D + 0.45)], r=0.22, mat="Hull", seg=8, fillet=0.0)
    if s == 3:
        dish(ro, Vector((-5.4, 2.6, D + 1.6)), (0.4, -0.3, 0.8), 1.1)
        ro.box0(-5.4, 2.6, D, 0.3, 0.3, 1.2, "Frame", mats={"-z": None})
        rm.top_z = max(rm.top_z, D + 2.5)
    # levels on the deck
    sites = {0: dict(ant=(1.5, -1.9, 1.0), mod3=(2.5, -0.4, 90.0), fins4=(-2.2, 1.6, 45.0), annex4=(-0.4, 2.55, 0.0),
                     beacon5=(0.3, -2.4, D + 0.02), emblem5=(-2.55, 0.9, D + 0.05, 0, 0, 1)),
             1: dict(ant=(-0.2, -3.6, 1.1), mod3=(3.5, -0.2, 90.0), fins4=(-3.0, 1.6, 60.0), annex4=(-0.3, 3.7, 0.0),
                     beacon5=(1.3, -3.6, D + 0.02), emblem5=(-3.7, -0.2, D + 0.05, 0, 0, 1)),
             2: dict(ant=(0.0, -4.9, 1.2), mod3=(4.6, 0.1, 90.0), fins4=(-4.5, 1.0, 90.0), annex4=(1.4, 4.4, 0.0),
                     beacon5=(-1.2, -4.4, D + 0.02), emblem5=(-2.2, 1.0, D + 0.05, 0, 0, 1)),
             3: dict(ant=(-2.6, -5.8, 1.3), mod3=(5.8, 0.2, 90.0), fins4=(-6.0, -1.8, 90.0), annex4=(1.9, 5.8, 0.0),
                     beacon5=(-4.9, -4.3, D + 0.02), emblem5=(-0.4, 0.8, D + 0.05, 0, 0, 1))}[s]
    sites["emblem_size"] = 0.8 + 0.15 * s
    levels_podium(rm, sites)
    # interior: benches with consoles, holo table, cabinets, instrument, telescope console
    n = rm.interior
    nb = (2, 3, 5, 6)[s]
    xb = tangent_fit(Ri, 0.38, 0.9, 0.05)
    for k in range(nb):
        a = 360.0 * (k + 0.5) / nb + 30.0
        if ang_diff(a, 0.0) < 24:
            a += 30.0
        with n.at(RZ(a), T(xb, 0, 0)):
            workbench(n, w=1.8, d=0.75, stripe="Accent")
            screen(n, 0.28, 0.35, F + 1.25, 0.6, 0.4, yaw=180.0, glow="Neon")
    rt = (0.55, 0.7, 0.85, 1.0)[s]
    table_round(n, 0.0, 0.0, rt, 0.9, top="Frame", seg=12)
    n.cap_disc(rt * 0.8, F + 0.905, "Neon", seg=12)
    for k in range((3, 4, 5, 6)[s]):
        x, y, _ = polar(rt + 0.45, 360.0 * k / (3, 4, 5, 6)[s] + 20.0)
        stool(n, x, y, top="Accent")
    with n.at(RZ(150.0), T(tangent_fit(Ri, 0.45, 0.7, 0.05), 0, 0)):
        n.box0(0, 0, F, 0.9, 1.4, 1.7, "HullDark", mats={"-z": None})
        n.box((-0.456, 0, F + 1.15), (0.012, 1.1, 0.35), "Window", mats={"+x": None})
        n.box((-0.456, 0, F + 0.55), (0.012, 1.2, 0.08), "Accent", mats={"+x": None})
    if s >= 1:
        with n.at(RZ(-120.0), T(tangent_fit(Ri, 0.3, 0.8, 0.05), 0, 0)):
            cabinet(n, w=1.6, d=0.6, h=1.8, stripe="Accent")


# --------------------------------------------------------------------------------------
# RESEARCH ASSEMBLER (3.0): clean-room hall on the round base, ducts and filter units, a water tank, a pack hatch
# --------------------------------------------------------------------------------------
def build_research_assembler(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(windows=(0.50, 0.84) if s else None, win_seams=(10, 12, 16, 20)[s], win_mat="Plasma",
                  lamps=(160.0, 200.0), bolts=s >= 2)
    D = 2.4
    rm.build_podium(D, ribs=(8, 12, 14, 16)[s], band="Accent", band_z=D - 0.5, parapet=0.14)
    ro = rm.roof
    # the clean-room hall: flat roof, blue window band, filter units and fans on top
    # (critic round 4) a white clean-room block: a tall hall with a lit band, a roof covered in fan-filter units,
    # an air-handling unit with a big duct into the roof, and an airlock vestibule with a cyan door stripe
    cx, cy, a, b = -0.08 * Rw, 0.10 * Rw, 0.48 * Rw, 0.34 * Rw
    eave = D + (1.6, 1.9, 2.2, 2.5)[s]
    top = K.hall(ro, cx, cy, a, b, D + 0.02, eave, roof="flat", wall="Hull", roof_mat="HullDark", band="Plasma",
                 windows=True, win_mat="Plasma", ribs=True, rib_mat="Frame")
    rm.rooms_hi.append((lambda x, y, cx=cx, cy=cy, a=a, b=b: abs(x - cx) < a - 0.1 and abs(y - cy) < b - 0.1,
                        eave - 0.1))
    obst = [(cx + a * (2 * k + 1) / 3 - a, cy, max(a / 3, b) + 0.1) for k in range(3)]
    # fan-filter units: a grid of square filter panels in frames on the roof
    nfx, nfy = max(2, int(2 * a / 0.85)), max(2, int(2 * b / 0.85))
    for i in range(nfx):
        for j in range(nfy):
            fx = cx - a + (2 * a) * (i + 0.5) / nfx
            fy = cy - b + (2 * b) * (j + 0.5) / nfy
            # a glazed skylight: frame, a lit light-bar under clear glass
            ro.box0(fx, fy, top, 2 * a / nfx - 0.10, 2 * b / nfy - 0.10, 0.10, "Frame", mats={"-z": None})
            ro.box0(fx, fy, top + 0.10, 2 * a / nfx - 0.30, 0.06, 0.012, "L3Band", mats={"-z": None})
            ro.box0(fx, fy, top + 0.16, 2 * a / nfx - 0.20, 2 * b / nfy - 0.20, 0.012, "Glass", mats={"-z": None})
    # air-handling unit on the podium (-X side) and its duct over the parapet into the roof
    ax, ay = cx - a - 0.55, cy - b * 0.35
    ro.box0(ax, ay, D, 0.8, 1.2, 1.05 + 0.1 * s, "HullDark", bevel=0.03, mats={"-z": None})
    K.fan_unit(ro, ax, ay - 0.25, D + 1.05 + 0.1 * s, 0.26)
    ro.box0(ax, ay + 0.35, D + 1.05 + 0.1 * s, 0.34, 0.34, 0.05, "Frame", mats={"-z": None})
    ro.beam((ax, ay + 0.35, D + 1.10 + 0.1 * s), (ax, ay + 0.35, top + 0.35), 0.34, 0.34, "Metal")
    ro.beam((ax, ay + 0.35, top + 0.35), (cx - a + 0.35, ay + 0.35, top + 0.35), 0.34, 0.34, "Metal")
    obst.append((ax, ay, 0.8))
    # airlock vestibule on the +Y face with a cyan door stripe
    vx, vy = cx + a * 0.35, cy + b + 0.35
    ro.box0(vx, vy, D, 1.0, 0.70, 2.05, "Hull", bevel=0.04, mats={"-z": None})
    ro.box0(vx, vy + 0.352, D + 0.10, 0.62, 0.004, 1.70, "Glass")
    ro.box0(vx, vy + 0.356, D + 1.84, 0.80, 0.004, 0.10, "L3Band")
    ro.box0(vx, vy, D + 2.05, 1.08, 0.78, 0.06, "Frame", mats={"-z": None})
    obst.append((vx, vy, 0.7))
    # a water tank with a blue band and a feed pipe into the hall
    tx, ty = 0.52 * Rw, -0.42 * Rw
    tt = K.tank_v(ro, tx, ty, D, 1.0 + 0.2 * s, 0.42 + 0.05 * s, mat="Hull", band="WaterBlue", cap="dome", seg=10)
    K.pipe(ro, [(tx, ty, D + 0.8), (tx - 0.6, ty + 0.2, D + 0.8), (cx + a, cy - b * 0.5, D + 0.8)], r=0.06,
           mat="WaterBlue", seg=6, fillet=0.2)
    obst.append((tx, ty, 0.6 + 0.05 * s))
    # the pack hatch: a square hatch with violet / cyan / blue pack colours in its frame
    hx, hy = 0.50 * Rw, 0.45 * Rw
    ro.box0(hx, hy, D, 0.9, 0.9, 0.16, "Frame", mats={"-z": None})
    for k, m in enumerate(("L4Band", "L3Band", "Accent")):
        ro.box0(hx - 0.28 + 0.28 * k, hy, D + 0.16, 0.22, 0.7, 0.04, m, mats={"-z": None})
    obst.append((hx, hy, 0.7))
    rm.top_z = max(rm.top_z, top + 0.5, tt)
    K.levels_podium(rm, K.auto_sites(rm, obst, D))


BUILDERS = {
    "research_lab": build_research_lab,
    "research_assembler": build_research_assembler,
}
