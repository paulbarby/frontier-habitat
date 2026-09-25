"""
Frontier Habitat 2.0 - ART-A builders: airlock, junction, corridor (single size, no level parts).
airlock:  armoured drum, heavy door frame with hazard stripes on +X, suit racks and benches inside.
junction: small low hub dome with floor markings (colonists walk through the centre: keep it clear).
corridor: one 1.0 m segment along X; the game scales it on X, so every detail runs the full length except
          the end collars (x in [-0.5, -0.44] and [0.44, 0.5]).
"""
import math
from math import sin, cos, pi, radians, degrees, hypot, sqrt
from mathutils import Vector

import rooms_kit as K
from rooms_kit import (T, RX, RY, RZ, S, polar, frame_m, reg_angles, ang_diff, porthole, lamp, antenna, fan_unit,
                       capsule, tank_v, pipe, screen, bolts_ring, ladder, locker, cabinet, console, tangent_fit,
                       FLOOR_Z, WALL_TOP)

F = FLOOR_Z


def suit_rack(n, x, y, yaw):
    """Suit on a wall rack (Hull body, Accent chest band, dark visor), faces local -X."""
    with n.at(T(x, y, 0), RZ(yaw)):
        n.box0(0.12, 0, F, 0.08, 0.7, 2.0, "HullDark", mats={"-z": None})
        n.box((0.0, 0, F + 1.18), (0.30, 0.46, 0.55), "Hull")
        n.box((-0.155, 0, F + 1.25), (0.012, 0.47, 0.10), "Accent", mats={"+x": None})
        n.sphere((0.0, 0, F + 1.62), 0.17, "Hull", seg=8, rings=4)
        n.box((-0.13, 0, F + 1.63), (0.08, 0.2, 0.12), "Frame")
        for sy in (-1, 1):
            n.box((0.0, sy * 0.31, F + 1.10), (0.14, 0.12, 0.5), "Hull")
            n.box((0.0, sy * 0.11, F + 0.55), (0.16, 0.14, 0.6), "Hull")


def build_airlock(rm):
    if getattr(rm, "v3_mode", False):
        import interior_airlock as IA            # 3.1: suit room -> inner door -> chamber -> outer door -> porch
        IA.exterior(rm)
        return
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(pilasters=8, pil_mat="Frame", lamps=(120.0, 240.0), bolts=True, door_w=1.40, floor="grate",
                  kick="Hazard")
    D = 2.75
    rm.build_podium(D, ribs=8, rib_mat="Frame", band="Accent", band_z=1.8, parapet=0.14, deck="HullDark")
    ro, b = rm.roof, rm.base
    # heavy outer door frame: hazard lintel band and armour cheeks
    x1 = rm.door_x[1]
    for k in range(6):
        y0 = -0.95 + 0.317 * k
        ro.quad((x1 + 0.006, y0, 2.20), (x1 + 0.006, y0 + 0.317, 2.20), (x1 + 0.006, y0 + 0.317 + 0.1, 2.40),
                (x1 + 0.006, y0 + 0.1, 2.40), "Hazard" if k % 2 == 0 else "Rubber")
    # raised armoured cap with two pressure bottles and a warning light
    ro.lathe_a([(Rw - 0.30, D + 0.02), (Rw - 0.55, D + 0.34), (0.95, D + 0.40), (0.0, D + 0.40)], reg_angles(20),
               lambda k, i: ("Frame", "HullDark", "HullDark")[k], smooth=False)
    for sy in (-1, 1):
        capsule(ro, (-0.85, sy * 0.55, D + 0.72), (0.35, sy * 0.55, D + 0.72), 0.24, mat="Metal", seg=8, rings=2)
        for x in (-0.55, 0.05):
            ro.box0(x, sy * 0.55, D + 0.38, 0.12, 0.5, 0.14, "Frame", mats={"-z": None})
        ro.cyl((0.55, sy * 0.55, D + 0.72), (0.70, sy * 0.55, D + 0.72), 0.08, seg=6, mat="Accent")
    ro.vcyl(-1.1, 0, D + 0.40, D + 0.75, 0.07, seg=6, mat="Frame")
    ro.sphere((-1.1, 0, D + 0.84), 0.12, "Light", seg=8, rings=4)
    rm.anchor("Light", (-1.1, 0.0, D + 0.84))
    antenna(ro, 0.9, -1.2, D + 0.40, 1.2)
    rm.top_z = max(rm.top_z, D + 1.9)
    # interior: benches and suit racks on both sides, X axis clear, cycle console, floor stripe
    n = rm.interior
    for sy in (-1, 1):
        n.box0(-0.15, sy * 1.25, F + 0.34, 1.6, 0.40, 0.08, "Hull")
        for x in (-0.75, 0.45):
            n.box0(x, sy * 1.25, F, 0.10, 0.30, 0.34, "Frame", mats={"-z": None, "+z": None})
        for k in range(2):
            a = 90.0 * sy + (28.0 if k else -28.0)
            x, y, _ = polar(Ri - 0.2, a)
            suit_rack(n, x, y, a)
    with n.at(RZ(180.0), T(tangent_fit(Ri, 0.3, 0.5, 0.05), 0, 0)):
        console(n, w=0.9, glow="Window")
    n.box((0.35, 0, F + 0.006), (2.6, 0.14, 0.012), "Hazard", mats={"-z": None})
    for sx in (-1, 1):
        n.box((0.35 + sx * 1.3, 0, F + 0.007), (0.10, 1.2, 0.012), "Hazard", mats={"-z": None})


def build_junction(rm):
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(door=False, lamps=(45.0, 135.0, 225.0, 315.0), bolts=True, band_proud=True, accent_floor=False)
    rm.build_dome(2.85, ts=(0, 14, 32, 52, 70), crown="hatch", seams=6, seam_phase=30.0, hseams=(24.0,),
                  crown_t=70.0)
    ro = rm.roof
    # hub cap: accent ring and a light over the hatch
    rc, zc = rm.crown_r, rm.crown_z
    ro.lathe([(rc + 0.10, zc + 0.10), (rc + 0.10, zc + 0.18), (rc - 0.06, zc + 0.18)], "Accent", seg=12)
    ro.vcyl(0, 0, zc + 0.10, zc + 0.24, 0.16, seg=8, mat="Frame")
    ro.sphere((0, 0, zc + 0.30), 0.09, "Light", seg=6, rings=3)
    rm.top_z = max(rm.top_z, zc + 0.4)
    for a in (0.0, 120.0, 240.0):
        pos, nor = rm.dpt(40.0, a + 60.0)
        ro.box0(pos.x, pos.y, pos.z - 0.12, 0.34, 0.34, 0.26, "HullDark", mats={"-z": None})
    # interior: floor markings only (colonists walk through the centre), ceiling light ring
    n = rm.interior
    n.ring_flat(1.05, 1.22, F + 0.01, "Accent", seg=24)
    n.cap_disc(0.30, F + 0.01, "Accent", seg=12)
    for k in range(6):
        with n.at(RZ(60.0 * k)):
            n.quad((0.55, -0.10, F + 0.012), (0.85, -0.10, F + 0.012), (0.95, 0.0, F + 0.012), (0.65, 0.0, F + 0.012),
                   "Hazard")
            n.quad((0.65, 0.0, F + 0.012), (0.95, 0.0, F + 0.012), (0.85, 0.10, F + 0.012), (0.55, 0.10, F + 0.012),
                   "Hazard")
    for k in range(3):
        a = 60.0 + 120.0 * k
        with n.at(RZ(a), T(tangent_fit(Ri, 0.2, 0.3, 0.05), 0, 0)):
            n.box0(0, 0, F, 0.4, 0.6, 0.9, "Hull", mats={"-z": None})
            n.box((-0.206, 0, F + 0.7), (0.012, 0.5, 0.16), "Accent", mats={"+x": None})


def build_corridor(rm):
    """1.0 m segment on X (-0.5 .. 0.5).  Floor top at 0.14, walls to 1.0 m, arched glass roof to 2.36 m."""
    b, r = rm.base, rm.roof
    rm.levels = False
    HALF, WALL_H, WT = 1.18, 1.00, 0.18
    x0, x1 = -0.5, 0.5
    # floor: centre grating, violet guide lines, side plates
    b.box((0, 0, (F - 0.06) / 2), (1.0, 2 * (HALF - WT), F + 0.06), "HullDark", mats={"+y": None, "-y": None, "-z": None,
                                                                                    "+x": None, "-x": None})
    b.quad((x0, -0.42, F + 0.004), (x1, -0.42, F + 0.004), (x1, 0.42, F + 0.004), (x0, 0.42, F + 0.004), "Frame")
    for sy in (-1, 1):
        y = sy * 0.47
        b.quad((x0, y - 0.03, F + 0.006), (x1, y - 0.03, F + 0.006), (x1, y + 0.03, F + 0.006), (x0, y + 0.03, F + 0.006),
               "Accent")
    for sy in (-1, 1):
        yc = sy * (HALF - WT / 2)
        # wall body: outer face Hull with a dark kick strip, inner face Hull with a light strip, top Frame
        b.box((0, yc, (WALL_H - 0.05) / 2), (1.0, WT, WALL_H + 0.05), "Hull", mats={"-z": None, "+z": "Frame",
                                                                                   "+x": None, "-x": None})
        yo = sy * (HALF + 0.004)
        yi = sy * (HALF - WT - 0.004)

        def strip(y, z0, z1, facing, mat):
            if facing > 0:
                b.quad((x1, y, z0), (x0, y, z0), (x0, y, z1), (x1, y, z1), mat)
            else:
                b.quad((x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1), mat)
        strip(yo, 0.0, 0.24, sy, "HullDark")          # outer kick strip
        strip(yo, 0.58, 0.66, sy, "Accent")           # outer guide stripe
        strip(yi, 0.78, 0.84, -sy, "Light")           # inner light strip
        strip(yi, F, 0.30, -sy, "HullDark")           # inner kick strip
    # arched roof: glass shell, hull edge strips, a spine on top, frame collars at both ends
    N = 12

    def arc(ry, rz, x):
        return [(x, ry * cos(pi * i / N), WALL_H + rz * sin(pi * i / N)) for i in range(N + 1)]
    r.loft([arc(1.155, 1.355, x0), arc(1.155, 1.355, x1)],
           lambda k, i: "Hull" if i in (0, 1, N - 2, N - 1) else "Glass", smooth=True, closed=False)
    r.beam((x0, 0, WALL_H + 1.37), (x1, 0, WALL_H + 1.37), 0.30, 0.06, "Frame", caps=False)
    for (xa, xb) in ((x0, x0 + 0.06), (x1 - 0.06, x1)):
        r.loft([arc(1.20, 1.40, xa), arc(1.20, 1.40, xb), arc(1.08, 1.28, xb), arc(1.08, 1.28, xa)], "Frame",
               smooth=True, closed=False, wrap=True)
    rm.top_z = WALL_H + 1.40


BUILDERS = {
    "airlock": build_airlock,
    "junction": build_junction,
    "corridor": build_corridor,
}
