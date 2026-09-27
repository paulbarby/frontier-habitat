"""Frontier Habitat 4.0 industry rooms: the main machine of each new type (SIM list 2026-09-27) for
interior_fam_ind.industry (the machine, the control line with the work places, stock decor, the second line in
L / XL, the door lanes).  Local frame: the machine's front (+X) faces the control line."""
from math import sin, cos, radians, pi

import interior_fam_ind as IND
import interior_furniture as FU
from interior_kit import F, bbox, plate_x, plate_z
from rooms_kit import T, RX, RY, RZ, polar, tank_v


def m_steel(n, s, compact=False):
    """Furnace with a glowing pour spout, a ladle on a short rail."""
    fr = 0.80 + 0.08 * s
    n.lathe([(fr + 0.1, F), (fr + 0.1, F + 0.3), (fr, F + 0.3), (fr, F + 1.5), (fr * 0.7, F + 1.9), (0.3, F + 2.0)],
            lambda k, i: ("Frame", "Frame", "HullDark", "Frame", "Metal")[k], seg=14)
    n.vcyl(0, 0, F + 1.95, F + 2.25, 0.28, seg=8, mat="Frame", cap0=False)
    bbox(n, fr - 0.05, fr + 0.35, -0.18, 0.18, F + 0.9, F + 1.05, "Frame")
    plate_z(n, F + 1.051, fr, fr + 0.33, -0.12, 0.12, "Ember")
    plate_x(n, fr + 0.001, -0.35, 0.35, F + 0.4, F + 0.8, "Ember")
    if not compact:
        for dy in (-0.35, 0.35):
            bbox(n, fr + 0.4, fr + 1.6, dy - 0.04, dy + 0.04, F, F + 0.08, "Metal")
        with n.at(T(fr + 1.0, 0, 0)):
            n.lathe([(0.25, F + 0.1), (0.38, F + 0.75), (0.33, F + 0.75), (0.2, F + 0.15)], "Frame", seg=10)
            n.cap_disc(0.33, F + 0.72, "Ember", seg=10)


def m_titanium(n, s, compact=False):
    """Arc furnace: a squat shell, three electrodes on a mast arm, cable bundles."""
    fr = 0.85 + 0.08 * s
    n.lathe([(fr + 0.12, F), (fr + 0.12, F + 0.35), (fr, F + 0.4), (fr, F + 1.05), (fr * 0.85, F + 1.2)],
            lambda k, i: ("Frame", "Frame", "HullDark", "Ember")[k], seg=16)
    n.cap_disc(fr * 0.85, F + 1.2, "HullDark", seg=16)
    for k in range(3):
        x_, y_, _ = polar(fr * 0.35, 120.0 * k)
        n.vcyl(x_, y_, F + 1.2, F + 2.1, 0.09, seg=6, mat="Metal")
    bbox(n, -fr - 0.3, -fr - 0.05, -0.2, 0.2, F, F + 2.3, "Frame")
    n.beam((-fr - 0.2, 0, F + 2.2), (0.2, 0, F + 2.2), 0.14, 0.18, "Hazard")
    for dy in (-0.12, 0.0, 0.12):
        n.cyl((-fr - 0.2, dy, F + 2.0), (-fr - 0.2, dy, F + 0.2), 0.05, seg=5, mat="Rubber", cap0=False, cap1=False)


def m_ceramics(n, s, compact=False):
    """Tunnel kiln segment with glowing ports and a kiln car on rails."""
    L = (2.2 if compact else 2.8) + 0.3 * s
    bbox(n, -L / 2, L / 2, -0.55, 0.55, F, F + 1.2, "HullDark", bevel=0.04)
    bbox(n, -L / 2 - 0.05, L / 2 + 0.05, -0.6, 0.6, F + 1.2, F + 1.3, "Frame")
    for k in range(4):
        x_ = -L / 2 + L * (k + 0.5) / 4
        plate_x(n, 0.551, x_ - 0.15, x_ + 0.15, F + 0.5, F + 0.8, "Ember") if False else None
        bbox(n, x_ - 0.15, x_ + 0.15, 0.55, 0.57, F + 0.5, F + 0.8, "Ember")
        n.vcyl(x_, 0, F + 1.3, F + 1.8, 0.08, seg=6, mat="Metal")
    for dy in (-0.3, 0.3):
        bbox(n, -L / 2 - 0.9, -L / 2, dy - 0.03, dy + 0.03, F, F + 0.06, "Metal")
    bbox(n, -L / 2 - 0.85, -L / 2 - 0.1, -0.42, 0.42, F + 0.06, F + 0.35, "Frame")
    bbox(n, -L / 2 - 0.8, -L / 2 - 0.15, -0.35, 0.35, F + 0.35, F + 0.7, "Cargo")


def m_carbon(n, s, compact=False):
    """A spinning frame: a row of fibre spools on a frame, a take-up drum."""
    nsp = (4 if compact else 6) + s
    L = 0.36 * nsp + 0.4
    bbox(n, -0.35, 0.35, -L / 2, L / 2, F, F + 0.8, "HullDark", bevel=0.02)
    for k in range(nsp):
        y_ = -L / 2 + 0.38 + 0.36 * k
        n.vcyl(0.0, y_, F + 0.8, F + 1.2, 0.13, seg=8, mat="Rubber")
        n.vcyl(0.0, y_, F + 1.2, F + 1.35, 0.04, seg=5, mat="Metal")
    bbox(n, -0.05, 0.05, -L / 2, L / 2, F + 1.7, F + 1.78, "Frame")
    for sy in (-1, 1):
        bbox(n, -0.06, 0.06, sy * L / 2 - 0.06, sy * L / 2 + 0.06, F + 0.8, F + 1.78, "Frame")
    with n.at(T(-0.7, 0, F + 0.7), RX(90.0)):
        n.cyl((0, 0, -L / 2 + 0.2), (0, 0, L / 2 - 0.2), 0.32, seg=12, mat="Rubber")
    bbox(n, -1.05, -0.35, -L / 2 + 0.1, -L / 2 + 0.25, F, F + 1.0, "Frame")
    bbox(n, -1.05, -0.35, L / 2 - 0.25, L / 2 - 0.1, F, F + 1.0, "Frame")


def m_battery(n, s, compact=False):
    """Cell formation racks with blue status lights and a cell line."""
    nr = (2 if compact else 3) + (1 if s >= 2 else 0)
    for k in range(nr):
        y_ = (k - (nr - 1) / 2) * 0.75
        bbox(n, -0.5, 0.5, y_ - 0.3, y_ + 0.3, F, F + 1.75, "Hull", bevel=0.02)
        for j in range(6):
            z = F + 0.2 + 0.25 * j
            bbox(n, 0.5, 0.52, y_ - 0.25, y_ + 0.25, z, z + 0.04, "L3Band")
    bbox(n, 0.7, 1.3, -(nr * 0.75) / 2, (nr * 0.75) / 2, F, F + 0.85, "HullDark", bevel=0.02)
    for j in range(5):
        bbox(n, 0.8, 1.2, -(nr * 0.75) / 2 + 0.15 + 0.3 * j, -(nr * 0.75) / 2 + 0.35 + 0.3 * j, F + 0.85, F + 1.0,
             "Metal")


def m_parts(n, s, compact=False):
    """An assembly jig with a rover chassis, a wheel on a stand and an overhead hoist."""
    L = 2.2 if compact else 2.8
    bbox(n, -L / 2, L / 2, -0.7, 0.7, F, F + 0.35, "Frame")
    bbox(n, -L / 2 + 0.2, L / 2 - 0.2, -0.55, 0.55, F + 0.35, F + 0.7, "Accent", bevel=0.03)
    for sx in (-1, 1):
        with n.at(T(sx * (L / 2 - 0.3), -0.85, F + 0.45), RX(90.0)):
            n.torus(0.32, 0.12, "Rubber", seg=12, tseg=6, z=0.0)
            n.cyl((0, 0, -0.1), (0, 0, 0.1), 0.2, seg=8, mat="Metal")
    for sx in (-1, 1):
        bbox(n, sx * L / 2 - 0.08, sx * L / 2 + 0.08, 0.9, 1.06, F, F + 2.1, "Hazard")
    n.beam((-L / 2, 0.98, F + 2.1), (L / 2, 0.98, F + 2.1), 0.14, 0.18, "Frame")
    bbox(n, -0.2, 0.2, 0.8, 1.15, F + 1.6, F + 2.0, "HullDark")


def m_magnet(n, s, compact=False):
    """A sinter press (frame, ram, die) and a ring magnet on a test stand."""
    bbox(n, -0.6, 0.6, -0.6, 0.6, F, F + 0.5, "HullDark", bevel=0.02)
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            n.vcyl(sx, sy, F + 0.5, F + 2.0, 0.07, seg=6, mat="Metal")
    bbox(n, -0.65, 0.65, -0.65, 0.65, F + 2.0, F + 2.25, "Frame")
    n.vcyl(0, 0, F + 1.1, F + 2.0, 0.22, seg=10, mat="Metal")
    bbox(n, -0.3, 0.3, -0.3, 0.3, F + 0.5, F + 0.7, "Accent")
    if not compact:
        with n.at(T(0.0, 1.3, F + 0.95), RX(90.0)):
            n.torus(0.55, 0.14, "Metal", seg=16, tseg=6, z=0.0)
            for k in range(6):
                with n.at(RZ(60.0 * k)):
                    n.box((0.55, 0.0, 0.0), (0.12, 0.22, 0.32), "Accent")
        bbox(n, -0.25, 0.25, 1.1, 1.5, F, F + 0.35, "Frame")


def m_supercond(n, s, compact=False):
    """Cryostat drums with frost bands, transfer lines and a quench vent."""
    nd = (2 if compact else 3) + (1 if s >= 2 else 0)
    for k in range(nd):
        y_ = (k - (nd - 1) / 2) * 1.05
        tank_v(n, 0.0, y_, F, 1.3, 0.42, mat="Hull", band="Frost", cap="dome", seg=12, legs=True)
        FU.pipe_run(n, [(0.0, y_, F + 1.85), (0.0, y_, F + 2.05), (-0.8, y_ * 0.5, F + 2.05)], r=0.05, mat="Frost")
    n.vcyl(-0.8, 0.0, F, F + 2.3, 0.12, seg=8, mat="Frost")
    bbox(n, 0.55, 0.95, -0.3, 0.3, F, F + 1.1, "Hull", bevel=0.02)
    plate_x(n, 0.951, -0.22, 0.22, F + 0.7, F + 1.0, "Screen")


def m_metamat(n, s, compact=False):
    """The violet field chamber: a plinth, a cage of posts, glowing ring coils and a core."""
    fr = 0.75 + 0.08 * s
    n.vcyl(0, 0, F, F + 0.3, fr + 0.2, seg=16, mat="Frame")
    for k in range(8):
        x_, y_, _ = polar(fr, 45.0 * k)
        n.vcyl(x_, y_, F + 0.3, F + 1.9, 0.05, seg=6, mat="Metal")
    for zz in (0.8, 1.5):
        with n.at(T(0, 0, F + zz)):
            n.torus(fr, 0.06, "L4Band", seg=18, tseg=5, z=0.0)
    n.sphere((0, 0, F + 1.1), 0.32, "L4Band", seg=10, rings=5)
    with n.at(T(0, 0, F + 1.9)):
        n.torus(fr, 0.09, "Frame", seg=18, tseg=5, z=0.0)


NEW = {"steel_mill": m_steel, "titanium_smelter": m_titanium, "ceramics_kiln": m_ceramics, "carbon_works": m_carbon,
       "battery_plant": m_battery, "parts_works": m_parts, "magnet_works": m_magnet,
       "superconductor_lab": m_supercond, "metamaterial_foundry": m_metamat}
STOCK = {"steel_mill": ["ingots", "orebin", "crates", "ingots", "cart"],
         "titanium_smelter": ["orebin", "ingots", "drums", "cart"],
         "ceramics_kiln": ["sheets", "pallets", "crates", "cart"],
         "carbon_works": ["reels", "pallets", "crates", "cart"],
         "battery_plant": ["crates", "racks", "reels", "cart"],
         "parts_works": ["crates", "racks", "pallets", "cart"],
         "magnet_works": ["ingots", "crates", "drums", "cart"],
         "superconductor_lab": ["cooler", "crates", "racks", "cart"],
         "metamaterial_foundry": ["crates", "drums", "reels", "cart"]}
IND.MACHINES.update(NEW)
IND.IND_STOCK.update(STOCK)
INTERIORS = {tid: IND.industry for tid in NEW}
