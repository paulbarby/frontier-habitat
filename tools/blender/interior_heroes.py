"""Frontier Habitat 5.0 round 2 (coordinator 2026-10-02): one signature element per industry type, so the 17 industry
rooms do not look alike from the follow camera.  Each hero stands on (or rises from) its machine's own footprint, so
it needs no floor and keeps the door lanes; it rises toward the roof (rm.headroom), which gives each room its own
silhouette at eye height:

  mine                 a spoked sheave wheel on the headframe
  refinery             a flue stack with a glowing collar
  polymer_plant        an extruder tower with a filament spool
  workshop             a giant wrench on a pole ("EMPLOYEE OF THE MONTH")
  glassworks           a chimney and a blown-glass sculpture
  electronics_fab      a clean-room hood over the litho machine
  fabricator           a giant rubber duck, half printed on the bed
  steel_mill           an exhaust hood and stack over the furnace
  titanium_smelter     a cooling tower
  ceramics_kiln        a brick chimney
  carbon_works         a fibre oven column with lit slits
  battery_plant        a giant battery cell mascot
  parts_works          a tall robot arm
  magnet_works         a giant horseshoe magnet
  superconductor_lab   a maglev pod hovering over a track
  metamaterial_foundry a floating violet tesseract

Built in the machine's local frame (the caller's `at(n, mx, my, 0)`); (mx, my) map local to room coordinates for the
head-room test.  All original designs.
"""
from math import sin, cos, radians, sqrt

from rooms_kit import T, RX, RY, RZ, S
from interior_kit import F, bbox, plate_x, plate_z
import interior_props as PR


def _top(vs):
    return max(v.z for v in vs) if vs else F + 1.5


def _ext(vs):
    return min(v.x for v in vs), max(v.x for v in vs), min(v.y for v in vs), max(v.y for v in vs)


class H:
    def __init__(self, rm, n, mx, my, vs):
        self.rm, self.n, self.mx, self.my, self.vs = rm, n, mx, my, vs
        self.top = _top(vs)
        self.x0, self.x1, self.y0, self.y1 = _ext(vs)

    def room(self, lx, ly, r=0.3):
        """Head room (absolute z) over local (lx, ly), the lowest over a small cross."""
        best = 99.0
        for dx, dy in ((0, 0), (r, 0), (-r, 0), (0, r), (0, -r)):
            best = min(best, self.rm.headroom(self.mx + lx + dx, self.my + ly + dy))
        return best - 0.12


def mine(h):
    n = h.n
    zc = min(h.room(0.0, 0.0, 0.8) - 0.85, F + 3.0)
    if zc < h.top + 0.3:
        return False
    with n.at(T(0.0, 0.0, zc), RX(90.0)):
        n.torus(0.70, 0.06, "Hazard", seg=16, tseg=5)
        for k in range(4):
            with n.at(RZ(45.0 * k)):
                n.box((0.0, 0.0, 0.0), (1.36, 0.05, 0.05), "Frame")
        n.cyl((0, 0, -0.12), (0, 0, 0.12), 0.12, seg=8, mat="Metal")
    for sy in (-1, 1):
        n.beam((0.0, sy * 0.10, h.top - 0.05), (0.0, sy * 0.10, zc), 0.08, 0.08, "Frame")
    return True


def stack(h, x, y, r, mat="HullDark", collar="Ember", bands="Hazard"):
    n = h.n
    zt = h.room(x, y, r)
    z0 = max(F + 1.2, h.top - 0.4)
    if zt - z0 < 0.8:
        return False
    n.vcyl(x, y, z0, zt, r, seg=10, mat=mat, cap0=False)
    n.vcyl(x, y, zt - 0.10, zt, r + 0.04, seg=10, mat=collar)
    for t in (0.35, 0.65):
        zz = z0 + (zt - z0) * t
        n.vcyl(x, y, zz, zz + 0.08, r + 0.015, seg=10, mat=bands, cap0=False, cap1=False)
    return True


def refinery(h):
    return stack(h, 0.0, 0.0, 0.26)


def polymer(h):
    n = h.n
    x = h.x0 + 0.35
    zt = h.room(x, 0.0, 0.5)
    if zt - F < 2.6:
        return False
    n.vcyl(x, 0.0, F, zt - 0.6, 0.18, seg=8, mat="Metal")
    n.vcyl(x, 0.0, zt - 0.6, zt - 0.4, 0.26, seg=8, mat="Accent")
    with n.at(T(x, 0.0, zt - 0.62), RX(90.0)):
        n.torus(0.36, 0.10, "Fabric", seg=14, tseg=5)
    n.tube([(x, 0.0, F + 1.2), (x + 0.5, 0.25, F + 1.5), (x + 0.2, 0.45, F + 1.9), (x, 0.0, zt - 0.7)], 0.03, seg=5,
           mat="Fabric")
    return True


def workshop(h):
    n = h.n
    x, y = h.x0 + 0.15, h.y1 - 0.15
    zt = h.room(x, y, 0.4)
    if zt - F < 2.4:
        return False
    n.vcyl(x, y, F, zt - 0.85, 0.05, seg=6, mat="Frame")
    zc = zt - 0.55
    with n.at(T(x, y, zc), RZ(90.0), RY(-20.0)):
        n.box((0.0, 0.0, 0.0), (0.06, 0.12, 0.70), "Metal")
        n.box((0.0, 0.0, 0.40), (0.06, 0.34, 0.14), "Metal")
        n.box((0.0, 0.08, 0.50), (0.07, 0.10, 0.10), "HullDark")
        n.box((0.0, -0.08, 0.50), (0.07, 0.10, 0.10), "HullDark")
    with n.at(T(x, y, 0.0), RZ(180.0)):
        bbox(n, 0.06, 0.08, -0.32, 0.32, zc - 0.60, zc - 0.40, "Hazard")
        PR.text(n, "EMPLOYEE OF", 0.0, zc - 0.465, 0.040, "Rubber", x=0.081)
        PR.text(n, "THE MONTH", 0.0, zc - 0.535, 0.040, "Rubber", x=0.081)
    return True


def glassworks(h):
    n = h.n
    ok = stack(h, 0.0, 0.0, 0.20, mat="Frame", collar="Window", bands="Copper")
    x = h.x1 - 0.1
    y = h.y1 + 0.0
    n.vcyl(x - 0.3, y - 0.3, F, F + 1.0, 0.04, seg=6, mat="Frame")
    n.sphere((x - 0.3, y - 0.3, F + 1.25), 0.26, "Glass", seg=10, rings=6)
    n.sphere((x - 0.3, y - 0.3, F + 1.62), 0.14, "L3Band", seg=8, rings=4)
    return ok


def electronics(h):
    n = h.n
    x0, x1, y0, y1 = h.x0 - 0.05, h.x1 + 0.05, h.y0 - 0.05, h.y1 + 0.05
    zt = min([h.room(xx, yy, 0.1) for xx in (x0, x1) for yy in (y0, y1)] + [F + 2.6]) - 0.12
    if zt < h.top + 0.2:
        return False
    for sx in (x0, x1):
        for sy in (y0, y1):
            bbox(n, sx - 0.04, sx + 0.04, sy - 0.04, sy + 0.04, F, zt, "Hull")
    bbox(n, x0, x1, y0, y1, zt, zt + 0.10, "Hull")
    plate_z(n, zt - 0.002, x0 + 0.05, x1 - 0.05, y0 + 0.05, y1 - 0.05, "BeaconAmber")       # lit underside (yellow)
    for (a0, a1, b0, b1, ax) in ((y0, y1, zt - 1.0, zt, x0), (y0, y1, zt - 1.0, zt, x1)):
        plate_x(n, ax, a0, a1, b0, b1, "Glass", facing=-1 if ax == x0 else 1)
    with n.at(T(x1 + 0.002, (y0 + y1) / 2, 0.0)):
        PR.text(n, "CLEAN ROOM", 0.0, zt + 0.05, 0.05, "Rubber", x=0.0)
    return True


def fabricator(h):
    """A giant rubber duck half printed on the bed (the printer works on it)."""
    n = h.n
    z = F + 0.92
    n.sphere((0.0, 0.0, z + 0.26), 0.36, "Hazard", seg=12, rings=6, scale=(1.25, 1.0, 0.8))
    n.sphere((0.22, 0.0, z + 0.62), 0.22, "Hazard", seg=10, rings=5)
    bbox(n, 0.38, 0.52, -0.08, 0.08, z + 0.56, z + 0.62, "Fabric")
    for sy in (-1, 1):
        n.sphere((0.36, sy * 0.10, z + 0.68), 0.03, "Rubber", seg=6, rings=3)
    # the unprinted top half: a wire-frame (thin rings) over the duck
    with n.at(T(0.0, 0.0, z + 0.40)):
        n.torus(0.36, 0.008, "Plasma", seg=16, tseg=3)
    return True


def steel(h):
    n = h.n
    zt = h.room(0.0, 0.0, 0.9)
    zh = max(h.top + 0.15, F + 2.2)
    if zt - zh < 0.6:
        return False
    n.convex([(-0.75, -0.75, zh), (0.75, -0.75, zh), (0.75, 0.75, zh), (-0.75, 0.75, zh),
              (-0.25, -0.25, zh + 0.45), (0.25, -0.25, zh + 0.45), (0.25, 0.25, zh + 0.45), (-0.25, 0.25, zh + 0.45)],
             [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "HullDark")
    n.vcyl(0.0, 0.0, zh + 0.45, zt, 0.22, seg=8, mat="Frame", cap0=False)
    n.vcyl(0.0, 0.0, zh - 0.02, zh, 0.80, seg=12, mat="Ember", cap1=False)
    return True


def titanium(h):
    n = h.n
    x, y = h.x0 + 0.28, h.y1 - 0.28
    zt = min(h.room(x, y, 0.4), F + 3.0)
    if zt - F < 2.2:
        return False
    hh = zt - F
    with n.at(T(x, y, 0.0)):
        n.lathe([(0.34, F), (0.24, F + hh * 0.55), (0.29, F + hh), (0.26, F + hh), (0.21, F + hh * 0.55),
                 (0.31, F + 0.02)], "Hull", seg=12, smooth=True)
        n.vcyl(0.0, 0.0, F + hh * 0.25, F + hh * 0.25 + 0.08, 0.31, seg=12, mat="Hazard", cap0=False, cap1=False)
    return True



def ceramics(h):
    n = h.n
    x = h.x1 - 0.3
    zt = h.room(x, 0.0, 0.35)
    z0 = F + 1.3
    if zt - z0 < 0.8:
        return False
    n.box((x, 0.0, (z0 + zt) / 2), (0.42, 0.42, zt - z0), "Copper", mats={"-z": None})
    for k in range(int((zt - z0) / 0.3)):
        zz = z0 + 0.3 * k + 0.15
        n.box((x, 0.0, zz), (0.44, 0.44, 0.02), "Frame", mats={"-z": None, "+z": None})
    n.box((x, 0.0, zt - 0.05), (0.50, 0.50, 0.10), "HullDark")
    return True


def carbon(h):
    n = h.n
    x = h.x0 + 0.30
    zt = h.room(x, 0.0, 0.4)
    if zt - F < 2.3:
        return False
    n.vcyl(x, 0.0, F, zt, 0.28, seg=10, mat="HullDark")
    for k in range(4):
        zz = F + 0.5 + (zt - F - 0.8) * k / 3
        with n.at(T(x, 0.0, zz)):
            n.torus(0.285, 0.02, "L3Band", seg=10, tseg=3)
    return True


def battery(h):
    """A giant battery cell (an original mascot) on the cell line: 'BIG CELL ENERGY'."""
    n = h.n
    x, y = (h.x0 + h.x1) / 2, h.y1 - 0.3
    z0 = h.top
    zt = min(h.room(x, y, 0.4), z0 + 1.5)
    if zt - z0 < 0.8:
        return False
    hh = zt - z0 - 0.1
    n.vcyl(x, y, z0, z0 + hh * 0.75, 0.30, seg=12, mat="Rubber")
    n.vcyl(x, y, z0 + hh * 0.75, z0 + hh, 0.30, seg=12, mat="Plant")
    n.vcyl(x, y, z0 + hh, z0 + hh + 0.08, 0.10, seg=8, mat="Metal")
    with n.at(T(x + 0.301, y, 0.0)):
        PR.text(n, "BIG CELL", 0.0, z0 + hh * 0.45, min(0.08, hh * 0.12), "Plant", x=0.0)
        PR.text(n, "ENERGY", 0.0, z0 + hh * 0.30, min(0.08, hh * 0.12), "Plant", x=0.0)
    return True


def parts(h):
    import interior_furniture as FU
    n = h.n
    x, y = h.x1 - 0.35, h.y0 + 0.35
    if h.room(x, y, 0.8) < F + 0.56 + 1.75:
        return False
    with n.at(T(x, y, 0.56)):
        FU.robot_arm(n, reach=1.1, yaw=135.0, seed=2)
    return True


def magnet(h):
    n = h.n
    zc = min(h.room(0.0, 0.0, 0.8) - 0.75, h.top + 0.9)
    if zc - h.top < 0.45:
        return False
    with n.at(T(0.0, 0.0, zc), RX(90.0)):
        n.lathe([(0.55, -0.08), (0.55, 0.08), (0.30, 0.08), (0.30, -0.08)], "SignalRed", seg=16, a0=0.0, a1=180.0,
                smooth=False)
        for sx in (-1, 1):
            n.box((sx * 0.425, -0.20, 0.0), (0.25, 0.40, 0.16), "SignalRed")
            n.box((sx * 0.425, -0.47, 0.0), (0.25, 0.14, 0.16), "Metal")
    n.beam((0.0, 0.0, h.top), (0.0, 0.0, zc + 0.30), 0.06, 0.06, "Frame")
    return True


def supercond(h):
    """A maglev pod hovering 8 cm over a track on the cryostats ('IT FLOATS. WE DO NOT KNOW WHY.')."""
    n = h.n
    z0 = h.top + 0.05
    if h.room(0.0, 0.0, 0.8) - z0 < 0.6:
        return False
    L = max(1.2, (h.y1 - h.y0) * 0.8)
    bbox(n, -0.15, 0.15, -L / 2, L / 2, z0, z0 + 0.08, "Frost")
    n.box((0.0, 0.0, z0 + 0.26), (0.36, 0.70, 0.18), "Hull", bevel=0.05)
    plate_x(n, 0.181, -0.25, 0.25, z0 + 0.22, z0 + 0.30, "L3Band")
    plate_x(n, -0.181, -0.25, 0.25, z0 + 0.22, z0 + 0.30, "L3Band", facing=-1)
    for sy in (-1, 1):
        n.beam((0.0, sy * L / 2, h.top - 0.1), (0.0, sy * L / 2, z0), 0.06, 0.06, "Frame")
    return True


def metamat(h):
    n = h.n
    zc = min(h.room(0.0, 0.0, 0.8) - 0.6, h.top + 0.8)
    if zc - h.top < 0.45:
        return False
    for s_, rot in ((0.45, 0.0), (0.25, 30.0)):
        with n.at(T(0.0, 0.0, zc), RZ(rot), RX(20.0)):
            for a in (-1, 1):
                for b in (-1, 1):
                    n.beam((a * s_, b * s_, -s_), (a * s_, b * s_, s_), 0.025, 0.025, "L4Band")
                    n.beam((a * s_, -s_, b * s_), (a * s_, s_, b * s_), 0.025, 0.025, "L4Band")
                    n.beam((-s_, a * s_, b * s_), (s_, a * s_, b * s_), 0.025, 0.025, "L4Band")
    return True


HEROES = {"mine": mine, "refinery": refinery, "polymer_plant": polymer, "workshop": workshop,
          "glassworks": glassworks, "electronics_fab": electronics, "fabricator": fabricator, "steel_mill": steel,
          "titanium_smelter": titanium, "ceramics_kiln": ceramics, "carbon_works": carbon, "battery_plant": battery,
          "parts_works": parts, "magnet_works": magnet, "superconductor_lab": supercond,
          "metamaterial_foundry": metamat}


def hero(rm, n, tid, mx, my, vs):
    fn = HEROES.get(tid)
    if fn is None:
        return False
    ok = fn(H(rm, n, mx, my, vs))
    if ok:
        PR.USED["hero_" + tid] = 1
    return ok
