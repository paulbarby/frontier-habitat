"""Frontier Habitat 5.0 distillery interior (SIM 2026-10-01): the industry layout of interior_fam_ind.industry (the
main machine on a hazard pad, the control line = the Work anchors, the second unit at L / XL, floor trenches,
stock zones at XL, decor, wall items) with a distillery machine and distillery stock.

Machine (local frame, centre at the origin, the control side +X): a copper wash still and a smaller spirit still
on dark firebox plinths (glowing firebox doors), each with a swan neck, a lyne arm and a copper condenser behind
it (-X), and a brass-framed spirit safe on a pedestal in front (+X), piped from the condensers.  Compact (S, M and
the second unit): one still, its condenser and the safe.
Stock: casks on racks, wooden washbacks (fermenters) with lids, grain sacks on a pallet, crates of green bottles."""
from math import sin, cos, radians

import interior_fam_ind as IND
import interior_furniture as FU
from interior_families import DECOR, NEED
from interior_kit import F, bbox, plate_x, plate_z
import interior_rooms as IR
from interior_rooms import at
from rooms_kit import T, RX, RY, RZ

COPPER = "Copper"


def still(n, x, y, r, h, cond=True):
    """A pot still at (x, y): plinth, onion pot, boil ball, swan neck (top at F + h), a lyne arm to a condenser at
    -X.  Returns the condenser foot (x, y)."""
    n.vcyl(x, y, F, F + 0.26, r + 0.10, seg=14, mat="HullDark")
    plate_x(n, x + r + 0.101, y - 0.14, y + 0.14, F + 0.06, F + 0.20, "Ember")
    zb = F + 0.26
    neck = max(0.07, 0.18 * r)
    prof = [(r * 0.80, zb), (r * 0.96, zb + 0.20 * r), (r, zb + 0.48 * r), (r * 0.94, zb + 0.78 * r),
            (r * 0.72, zb + 1.02 * r), (r * 0.44, zb + 1.16 * r), (r * 0.30, zb + 1.24 * r), (r * 0.40, zb + 1.38 * r),
            (r * 0.28, zb + 1.52 * r), (neck * 1.3, zb + 1.66 * r), (neck, F + h), (0.0, F + h + 0.02)]
    with n.at(T(x, y, 0.0)):
        n.lathe(prof, COPPER, seg=14)
        n.vcyl(0.0, 0.0, zb + 0.74 * r, zb + 0.80 * r, r * 0.955, seg=14, mat="Frame", cap0=False, cap1=False)
    bbox(n, x + r * 0.88, x + r * 0.95, y - 0.16 * r, y + 0.16 * r, zb + 0.35 * r, zb + 0.62 * r, "Frame")
    cx = x - r - 0.42
    zc = F + h - 0.42
    n.tube([(x, y, F + h - 0.03), (x - 0.20, y, F + h - 0.01), (cx, y, zc + 0.08)], max(0.045, neck * 0.65),
           seg=8, mat=COPPER, caps=False)
    n.vcyl(cx, y, F, zc + 0.16, 0.20, seg=10, mat=COPPER)
    for zz in (F + 0.30, zc - 0.25):
        n.vcyl(cx, y, zz, zz + 0.06, 0.215, seg=10, mat="Frame", cap0=False, cap1=False)
    return cx, y


def spirit_safe(n, x, y):
    """The spirit safe: a pedestal with a brass (copper) framed glass box, a lock hasp."""
    bbox(n, x - 0.18, x + 0.18, y - 0.22, y + 0.22, F, F + 0.86, "HullDark", bevel=0.02)
    bbox(n, x - 0.22, x + 0.22, y - 0.30, y + 0.30, F + 0.86, F + 0.90, COPPER)
    for sx in (-0.2, 0.2):
        for sy in (-0.28, 0.28):
            bbox(n, x + sx - 0.02, x + sx + 0.02, y + sy - 0.02, y + sy + 0.02, F + 0.90, F + 1.22, COPPER)
    bbox(n, x - 0.22, x + 0.22, y - 0.30, y + 0.30, F + 1.22, F + 1.27, COPPER)
    for gx in (x + 0.205, x - 0.205):
        plate_x(n, gx, y - 0.26, y + 0.26, F + 0.92, F + 1.20, "Glass")
    n.vcyl(x - 0.06, y, F + 0.92, F + 1.05, 0.05, seg=6, mat="Window")          # the spirit glowing in the jars
    n.vcyl(x + 0.08, y + 0.1, F + 0.92, F + 1.02, 0.04, seg=6, mat="Window")
    bbox(n, x + 0.22, x + 0.25, y - 0.05, y + 0.05, F + 1.02, F + 1.12, "Hazard")


def m_distillery(n, s, compact=False):
    r = 0.60 + 0.03 * s
    if compact:
        feet = [still(n, -0.15, 0.0, r, 2.15)]
        sy = [0.0]
    else:
        feet = [still(n, -0.15, -0.85, r, 2.20), still(n, -0.15, 0.85, r * 0.84, 2.05)]
        sy = [-0.85, 0.85]
    sx = r + 0.45
    spirit_safe(n, sx, 0.0)
    # low feed pipes from the condensers to the safe (along the floor edge of the pad, 0.10 m high)
    for (fx, fy) in feet:
        FU.pipe_run(n, [(fx, fy, F + 0.12), (fx, fy - 0.26 if fy <= 0 else fy + 0.26, F + 0.12),
                        (sx - 0.18, fy - 0.26 if fy <= 0 else fy + 0.26, F + 0.12), (sx - 0.18, 0.0, F + 0.12)],
                    r=0.035, mat=COPPER)


# --------------------------------------------------------------------------------------
# stock
# --------------------------------------------------------------------------------------
def _cask(n, x, y, z, r=0.26, L=0.70, along_y=False):
    rot = (RZ(90.0), RY(90.0)) if along_y else (RY(90.0),)
    with n.at(T(x, y, z + r), *rot):
        n.lathe([(0.0, -L / 2), (r * 0.84, -L / 2), (r * 0.96, -L / 4), (r, 0.0), (r * 0.96, L / 4),
                 (r * 0.84, L / 2), (0.0, L / 2)], "Wood", seg=10)
        for zz in (-L * 0.34, L * 0.28):
            n.vcyl(0.0, 0.0, zz, zz + 0.045, r * 0.99, seg=10, mat="Frame", cap0=False, cap1=False)


def d_casks(plan, x, y, yaw, k):
    """A cask rack (dunnage row) along local X: four casks below, three on top, heads to the aisle."""
    n = plan.n
    with at(n, x, y, yaw):
        for sy in (-0.22, 0.22):
            bbox(n, -1.08, 1.08, sy - 0.04, sy + 0.04, F, F + 0.08, "Frame")
        for i in range(4):
            _cask(n, -0.78 + 0.52 * i, 0.0, F + 0.06, along_y=True)
        for i in range(3 if k % 2 == 0 else 2):
            _cask(n, -0.52 + 0.52 * i, 0.0, F + 0.06 + 0.44, along_y=True)
    return 1.15


def d_washbacks(plan, x, y, yaw, k):
    """Two wooden washbacks (fermenters) on a plinth along local X: staves, Frame hoops, lids with hatches, a copper
    manifold over the lids."""
    n = plan.n
    r, h = 0.52, 1.40
    with at(n, x, y, yaw):
        bbox(n, -1.25, 1.25, -0.62, 0.62, F, F + 0.08, "HullDark", mats={"-z": None})
        for cx_ in (-0.62, 0.62):
            n.vcyl(cx_, 0.0, F + 0.08, F + h, r, seg=14, mat="Wood", cap1=False)
            for zz in (0.30, 0.78, 1.22):
                n.vcyl(cx_, 0.0, F + zz, F + zz + 0.05, r + 0.012, seg=14, mat="Frame", cap0=False, cap1=False)
            n.vcyl(cx_, 0.0, F + h, F + h + 0.05, r + 0.03, seg=14, mat="HullDark")
            bbox(n, cx_ - 0.15, cx_ + 0.15, -0.18, 0.18, F + h + 0.05, F + h + 0.10, "Frame")
            n.vcyl(cx_, 0.0, F + h + 0.05, F + h + 0.30, 0.05, seg=6, mat=COPPER)
        n.cyl((-0.62, 0.0, F + h + 0.30), (0.62, 0.0, F + h + 0.30), 0.05, seg=6, mat=COPPER)
        bbox(n, -1.2, -1.14, -0.05, 0.05, F + 0.08, F + h + 0.30, "Frame")
    return 1.25


def d_grain(plan, x, y, yaw, k):
    """Grain sacks on a pallet."""
    n = plan.n
    with at(n, x, y, yaw):
        bbox(n, -0.55, 0.55, -0.45, 0.45, F, F + 0.12, "Wood", mats={"-z": None})
        for layer in range(2 + k % 2):
            for j in range(3):
                for i in range(2):
                    if layer == 2 and (i + j) % 2:
                        continue
                    cx_, cy_ = -0.36 + 0.36 * j, -0.21 + 0.42 * i
                    if layer % 2:
                        cx_ += 0.05
                    n.sphere((cx_, cy_, F + 0.20 + 0.16 * layer), 0.19, "OreVein", seg=8, rings=4,
                             scale=(1.0, 1.1, 0.45))
    return 0.70


def d_bottling(plan, x, y, yaw, k):
    """Crates of green bottles, stacked two high."""
    n = plan.n
    with at(n, x, y, yaw):
        for (cx_, cy_, z) in ((-0.22, 0.0, F), (0.22, 0.0, F), (0.0, 0.0, F + 0.30)):
            bbox(n, cx_ - 0.20, cx_ + 0.20, cy_ - 0.28, cy_ + 0.28, z, z + 0.26, "Wood", bevel=0.01)
            for i in range(2):
                for j in range(3):
                    bx, by = cx_ - 0.09 + 0.18 * i, cy_ - 0.18 + 0.18 * j
                    n.vcyl(bx, by, z + 0.26, z + 0.34, 0.035, seg=6, mat="PlantDark", cap0=False)
    return 0.55


DECOR.update({"casks": d_casks, "washbacks": d_washbacks, "grain": d_grain, "bottling": d_bottling})
NEED.update({"casks": 1.15, "washbacks": 1.25, "grain": 0.70, "bottling": 0.55})

IND.MACHINES["distillery"] = m_distillery
IND.IND_STOCK["distillery"] = ["washbacks", "casks", "grain", "bottling", "casks", "cart"]
IR.V4_KINDS["distillery"] = ["washbacks", "casks", "grain", "casks", "bottling"]   # the 4.0 filler: its own kinds
INTERIORS = {"distillery": IND.industry}
