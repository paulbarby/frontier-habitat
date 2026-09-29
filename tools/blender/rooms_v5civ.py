"""Frontier Habitat 5.0 (docs/V5_DESIGN.md section 7) - ART-HAB: exteriors of the civic modules.

retail           comfort   a shop drum: shop windows all round, striped awnings, a lit sign pylon on the deck
park             comfort   a lattice glass dome (the garden shows through), a crown hub, the badge on a plate
academy          science   a deck with a small observatory dome and the science mast; clerestory windows
security_office  civic     an armoured drum with slit windows, a watch cupola with a light bar
jail             civic     a heavy drum with bars on narrow windows, a guard cupola with a searchlight, roof fence
The family badge goes on the largest free roof patch (rooms_identity.identity_pass).  Interiors: interior_v5civ.py.
"""
from math import sin, cos, radians, degrees, sqrt, pi, atan2

import rooms_kit as K
from rooms_kit import T, RX, RY, RZ, WALL_TOP, reg_angles, columns, col_mid_fn, ang_diff, lamp, kiewitt_dome, FLOOR_Z
import rooms_identity as RI

F = FLOOR_Z


def _base(rm, bolts=None, band="Accent", wall="Hull"):
    rm.levels = False
    rm.build_base(lamps=(), bolts=rm.size >= 2 if bolts is None else bolts, band=band, wall=wall)
    rm.porch = K.P("PorchTop")        # lit parts on the roof (beacons, floodlights, signs): hidden in the cutaway
    rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [rm.porch]


def _glow_ring(rm, z, mat="LightStrip"):
    """A lit ring under the parapet (reads by night at 250 m)."""
    Rw = rm.Rw
    rm.porch.lathe_a([(Rw + 0.06, z), (Rw + 0.06, z + 0.10)], reg_angles(rm.seg * 2), lambda k, i: mat, smooth=False)


def _awnings(rm, z_top, n, depth=0.20, drop=0.34):
    """Striped awnings over the shop windows (Accent / Hull stripes), n round the drum."""
    ro = rm.roof
    Rw = rm.Rw
    for k in range(n):
        a0 = 360.0 * k / n + 3.0
        a1 = 360.0 * (k + 1) / n - 3.0
        m = 6
        for j in range(m):
            t0, t1 = radians(a0 + (a1 - a0) * j / m), radians(a0 + (a1 - a0) * (j + 1) / m)
            mat = "Accent" if j % 2 == 0 else "Hull"
            p = [(Rw + 0.01, t0, z_top), (Rw + depth, t0, z_top - drop), (Rw + depth, t1, z_top - drop),
                 (Rw + 0.01, t1, z_top)]
            ids = [ro.v((r * cos(t), r * sin(t), z)) for r, t, z in p]
            ro.f(ids, mat)
            back = [ro.v((r * cos(t), r * sin(t), z - 0.01)) for r, t, z in p]
            ro.f(list(reversed(back)), mat)
        # a lit shop sign over every awning
        am = radians(0.5 * (a0 + a1))
        with rm.porch.at(T((Rw + 0.03) * cos(am), (Rw + 0.03) * sin(am), 0.0), RZ(degrees(am))):
            rm.porch.box0(0.0, 0.0, z_top + 0.04, 0.05, 1.3, 0.30, "Frame")
            rm.porch.box((0.03, 0.0, z_top + 0.19), (0.01, 1.2, 0.22), "Screen", mats={"-x": None})


def build_retail(rm):
    """A market: a striped canopy roof (a pinwheel of Accent and Hull from above), awnings with lit signs round
    the drum, a big two-sided billboard, the shopping-bag badge."""
    s = rm.size
    _base(rm)
    rm.badge_family = "shop"
    D = 3.1
    rm.build_podium(D, ribs=(12, 14, 18, 18)[s], band="Accent", band_z=D - 0.42, parapet=0.16,
                    windows=(1.52, 2.46), win_mat="Window", win_seams=(12, 14, 18, 18)[s], wall="Hull", deck="HullDark")
    n_aw = (6, 7, 9, 9)[s]
    _awnings(rm, 2.62, n_aw)
    ro = rm.roof
    Rw = rm.Rw
    # the canopy: a shallow cone over the deck, 16 stripes, a finial
    rc, hc = Rw - 0.3, 1.2 + 0.2 * s
    n = 16
    for k in range(n):
        t0, t1 = 2 * pi * k / n, 2 * pi * (k + 1) / n
        mat = "Accent" if k % 2 == 0 else "Hull"
        ro.f([ro.v((0.0, 0.0, D + 0.2 + hc)), ro.v((rc * cos(t0), rc * sin(t0), D + 0.2)),
              ro.v((rc * cos(t1), rc * sin(t1), D + 0.2))], mat)
    ro.lathe_a([(rc + 0.05, D + 0.02), (rc + 0.05, D + 0.22), (rc - 0.05, D + 0.22)], reg_angles(48),
               lambda k, i: "Frame", smooth=False)
    ro.vcyl(0.0, 0.0, D + 0.2 + hc - 0.1, D + 0.2 + hc + 0.5, 0.05, seg=6, mat="Frame")
    rm.porch.sphere((0.0, 0.0, D + 0.2 + hc + 0.58), 0.14, "Light", seg=8, rings=4)
    # the billboard on legs, turned to the game camera
    px, py = 0.52 * Rw * cos(radians(125.0)), 0.52 * Rw * sin(radians(125.0))
    sw = 3.4 + 0.6 * s
    zb = D + 0.2 + hc * (1.0 - 0.52) - 0.1
    with ro.at(T(px, py, zb), RZ(55.0)):
        for sx in (-1, 1):
            ro.box0(sx * sw * 0.36, 0.0, 0.0, 0.18, 0.18, 1.5, "Frame")
        ro.box0(0.0, 0.0, 1.5, sw, 0.34, 1.8, "HullDark", bevel=0.03)
        ro.box0(0.0, 0.0, 3.3, sw + 0.1, 0.38, 0.08, "Accent")
    with rm.porch.at(T(px, py, zb), RZ(55.0)):
        for sy in (-1, 1):
            rm.porch.box((0.0, sy * 0.175, 2.45), (sw - 0.2, 0.01, 1.4), "Screen")
            rm.porch.box((0.0, sy * 0.18, 1.62), (sw - 0.2, 0.01, 0.10), "LightStrip")
    rm.top_z = max(rm.top_z, zb + 3.5, D + 0.2 + hc + 0.8)
    _glow_ring(rm, D - 0.30)
    rm.no_extras = True


def build_park(rm):
    s = rm.size
    _base(rm)
    rm.seal_ring()
    H = (5.5, 6.2, 7.4, 8.6)[s]
    rings = (4, 4, 5, 6)[s]
    sectors = (6, 6, 7, 8)[s]
    kiewitt_dome(rm, H, sectors=sectors, rings=rings, beam=0.10 if s < 2 else 0.13)
    ro = rm.roof
    ro.vcyl(0, 0, H - 0.12, H + 0.22, 0.55, seg=12, mat="Frame")
    ro.vcyl(0, 0, H + 0.22, H + 0.30, 0.40, seg=12, mat="Accent")
    # a ring of lamps round the dome foot (garden lights, lit at night)
    for k in range(12):
        a = radians(30.0 * k + 15.0)
        lamp(ro, ro, ((rm.Rw + 0.02) * cos(a), (rm.Rw + 0.02) * sin(a), WALL_TOP + 0.06), (cos(a), sin(a), 0.0),
             up=(0, 0, 1), w=0.26, h=0.10, d=0.06, lens="Window")
    rm.top_z = max(rm.top_z, H + 0.30)
    rm.no_extras = True


def build_academy(rm):
    """A schoolhouse: a gable-roofed hall on the deck (Accent roof), a clock tower at its end, a small
    observatory; the mortarboard badge."""
    s = rm.size
    _base(rm)
    rm.badge_family = "academy"
    D = 3.0
    rm.build_podium(D, ribs=(10, 12, 16, 16)[s], band="Accent", band_z=D - 0.5, parapet=0.16,
                    windows=(1.62, 2.30), win_mat="Window", win_seams=(12, 14, 16, 16)[s], wall="Hull", deck="HullDark")
    ro = rm.roof
    Rw = rm.Rw
    # the schoolhouse hall (gable roof in the family colour), across the +Y half of the deck
    a, b = 0.46 * Rw, 0.20 * Rw
    cy = 0.30 * Rw
    top = K.hall(ro, 0.0, cy, a, b, D + 0.02, D + 1.5, ridge=D + 1.5 + b * 0.7, roof="gable", wall="Hull",
                 roof_mat="Accent", band="Frame", windows=True)
    # the clock tower at the hall's +X end
    tx, ty = a + 0.2, cy
    tw = 0.7 + 0.1 * s
    ro.box0(tx, ty, D + 0.02, 2 * tw, 2 * tw, 3.4 + 0.3 * s, "Hull", bevel=0.03)
    zt = D + 3.4 + 0.3 * s
    ro.box0(tx, ty, zt, 2 * tw + 0.2, 2 * tw + 0.2, 0.12, "Frame")
    ro.f([ro.v((tx - tw - 0.1, ty - tw - 0.1, zt + 0.12)), ro.v((tx + tw + 0.1, ty - tw - 0.1, zt + 0.12)),
          ro.v((tx, ty, zt + 1.3))], "Accent")
    ro.f([ro.v((tx + tw + 0.1, ty - tw - 0.1, zt + 0.12)), ro.v((tx + tw + 0.1, ty + tw + 0.1, zt + 0.12)),
          ro.v((tx, ty, zt + 1.3))], "Accent")
    ro.f([ro.v((tx + tw + 0.1, ty + tw + 0.1, zt + 0.12)), ro.v((tx - tw - 0.1, ty + tw + 0.1, zt + 0.12)),
          ro.v((tx, ty, zt + 1.3))], "Accent")
    ro.f([ro.v((tx - tw - 0.1, ty + tw + 0.1, zt + 0.12)), ro.v((tx - tw - 0.1, ty - tw - 0.1, zt + 0.12)),
          ro.v((tx, ty, zt + 1.3))], "Accent")
    for (nx, ny) in ((1, 0), (0, -1)):                   # clock faces (lit) on two sides
        with rm.porch.at(T(tx + nx * (tw + 0.01), ty + ny * (tw + 0.01), zt - 0.75),
                         RZ(0.0 if nx else -90.0), RY(-90.0)):
            rm.porch.cap_disc(0.45 * tw + 0.15, 0.0, "Window", seg=16)
            rm.porch.box((0.0, 0.10, 0.012), (0.04, 0.24, 0.01), "HullDark")
            rm.porch.box((0.12, 0.0, 0.012), (0.30, 0.04, 0.01), "HullDark")
    # the observatory on the -Y side
    ox, oy = 0.42 * Rw * cos(radians(-60.0)), 0.42 * Rw * sin(radians(-60.0))
    r_o = 0.9 + 0.2 * s
    with ro.at(T(ox, oy, D + 0.02)):
        ro.lathe([(r_o + 0.1, 0.0), (r_o + 0.1, 0.55), (r_o, 0.62)] +
                 [(r_o * cos(radians(t)), 0.62 + r_o * sin(radians(t))) for t in range(15, 91, 15)],
                 lambda k, i: "Hull" if k != 1 else "Accent", seg=20)
        with ro.at(T(0.0, 0.0, 0.62 + 0.2), RZ(30.0), RY(-40.0)):
            ro.cyl((0.0, 0.0, 0.0), (0.0, 0.0, r_o + 0.5), 0.16, seg=10, mat="Frame")
    rm.top_z = max(rm.top_z, zt + 1.4, top)
    _glow_ring(rm, D - 0.30)
    rm.no_extras = True


def _civic_drum(rm, D, slit=True, heavy=False, band="Accent", wall=None, deck="HullDark", coping="Frame"):
    s = rm.size
    rm.build_podium(D, ribs=(12, 16, 20, 20)[s], band=band, band_z=D - 0.5, parapet=0.22 if heavy else 0.16,
                    windows=(1.75, 2.30) if slit else None, win_mat="Window", win_seams=(10, 12, 16, 16)[s],
                    wall=wall or ("HullDark" if heavy else "Hull"), deck=deck, rib_mat="Frame", coping=coping)


def build_security_office(rm):
    """A command post: a black drum with a red band, a red ring on the dark deck, a watch tower with a light bar,
    a tall lattice comms mast with a red beacon and dishes; the black-and-red shield badge."""
    s = rm.size
    _base(rm, band="Fabric", wall="HullDark")
    rm.badge_family = "security"
    D = 2.9
    _civic_drum(rm, D, band="Fabric", wall="HullDark", coping="Fabric")
    ro = rm.roof
    Rw = rm.Rw
    # the red ring painted on the deck edge
    ro.lathe_a([(Rw - 0.35, D + 0.035), (Rw - 1.05, D + 0.035)], reg_angles(64), lambda k, i: "Fabric", smooth=False)
    # the watch tower: a drum on a stem, a glazed cab, a wide light bar
    cx, cy = 0.40 * Rw * cos(radians(135.0)), 0.40 * Rw * sin(radians(135.0))
    tr = 1.3 + 0.2 * s
    ro.vcyl(cx, cy, D + 0.02, D + 1.2, tr * 0.55, seg=10, mat="HullDark")
    K.hex_pod(ro, cx, cy, tr, D + 1.2, 1.3, rot=0.0, wall="HullDark", band="Fabric", win="Window",
              top="HullDark", windows=(0, 1, 2, 3, 4, 5))
    with rm.porch.at(T(cx, cy, D + 2.52), RZ(55.0)):
        rm.porch.box0(0.0, 0.0, 0.0, 2.4, 0.36, 0.16, "Frame")
        rm.porch.box((-0.62, 0.0, 0.26), (1.1, 0.32, 0.18), "Screen")
        rm.porch.box((0.62, 0.0, 0.26), (1.1, 0.32, 0.18), "Ember")
    # the comms mast: a lattice tower, dishes, a red beacon on top
    mx, my = 0.30 * Rw * cos(radians(-40.0)), 0.30 * Rw * sin(radians(-40.0))
    hm = 7.0 + 0.8 * s
    for (dx, dy) in ((-0.3, -0.3), (0.3, -0.3), (0.3, 0.3), (-0.3, 0.3)):
        ro.cyl((mx + dx, my + dy, D + 0.02), (mx + dx * 0.3, my + dy * 0.3, D + hm), 0.05, seg=4, mat="Frame",
               cap0=False)
    for k in range(int(hm / 1.2)):
        z = D + 0.6 + 1.2 * k
        f = 1.0 - (z - D) / hm * 0.7
        ro.box0(mx, my, z, 0.62 * f, 0.62 * f, 0.05, "Fabric" if k % 2 else "HullDark")
    K.dish(ro, (mx + 0.35, my, D + 0.5 * hm), (1.0, -0.8, 0.5), 0.55)
    K.dish(ro, (mx - 0.3, my + 0.2, D + 0.7 * hm), (-0.6, 1.0, 0.4), 0.40)
    rm.porch.sphere((mx, my, D + hm + 0.12), 0.20, "Ember", seg=8, rings=4)
    rm.top_z = max(rm.top_z, D + hm + 0.4)
    _glow_ring(rm, D - 0.30, mat="Ember")
    rm.no_extras = True


def build_jail(rm):
    """A walled block: a heavy drum with an orange band, a raised perimeter wall on the roof, four corner guard
    towers with floodlights, bars on the slit windows; the padlock badge."""
    s = rm.size
    _base(rm, band="Hazard", wall="HullDark")
    rm.badge_family = "jail"
    D = 3.0
    _civic_drum(rm, D, heavy=True, band="Hazard")
    ro = rm.roof
    Rw = rm.Rw
    # bars over the slit windows
    n = (40, 48, 64, 64)[s]
    for k in range(n):
        a = radians(360.0 * (k + 0.5) / n)
        ro.vcyl((Rw + 0.05) * cos(a), (Rw + 0.05) * sin(a), 1.80, 2.35, 0.022, seg=4, mat="Metal",
                cap0=False, cap1=False)
    # the raised perimeter wall on the roof edge, with an orange top band
    rp = Rw - 0.30
    ro.lathe_a([(rp + 0.18, D + 0.02), (rp + 0.18, D + 1.30), (rp + 0.18, D + 1.52), (rp - 0.18, D + 1.52),
                (rp - 0.18, D + 0.02)], reg_angles(rm.seg * 2),
               lambda k, i: ("HullDark", "Hazard", "Frame", "HullDark")[k], smooth=False)
    # four corner guard towers with floodlights
    for k in range(4):
        a = 45.0 + 90.0 * k
        tx, ty = (rp - 1.45) * cos(radians(a)), (rp - 1.45) * sin(radians(a))
        ro.box0(tx, ty, D + 0.02, 1.1, 1.1, 2.6, "HullDark", bevel=0.03)
        K.hex_pod(ro, tx, ty, 0.85 + 0.1 * s, D + 2.6, 1.0, rot=30.0, wall="HullDark", band="Hazard", win="Window",
                  top="Frame", windows=(0, 1, 2, 3, 4, 5))
        with rm.porch.at(T(tx, ty, D + 3.66), RZ(a + 180.0), RY(30.0)):
            rm.porch.box0(0.0, 0.0, 0.0, 0.30, 0.9, 0.22, "HullDark")
            rm.porch.box((0.16, 0.0, 0.11), (0.01, 0.8, 0.16), "Light")
    rm.top_z = max(rm.top_z, D + 4.0)
    _glow_ring(rm, D - 0.30, mat="BeaconAmber")
    rm.no_extras = True


BUILDERS = {
    "retail": build_retail,
    "park": build_park,
    "academy": build_academy,
    "security_office": build_security_office,
    "jail": build_jail,
}
