"""
Frontier Habitat 2.0 - energy exteriors: solar_array, wind_turbine, battery (sizes S, M, L, XL).

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_energy.py -- [--only solar_array_m,wind_turbine]

Output: assets/models/<id>_s|m|l|xl.glb, and <id>.glb (= size M, the v1 name).
Objects: Base, L2, L3, L4, L5 (+ Rotor for the wind turbine: origin at the hub, spins about local Blender Y).
Footprint radius per size from content/buildings.json. Accent = utilities blue.
"""
import os
import sys
import random
from math import sin, cos, pi, radians, sqrt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402
from ext_common import Part, T, RX, RY, RZ, S, polar       # noqa: E402
import ext_levels as LVK                                   # noqa: E402
from mathutils import Vector                               # noqa: E402

BLD = C.load_content("buildings.json")
SIZES = ("s", "m", "l", "xl")


def radius(bid, k):
    return BLD[bid]["sizes"]["radius"][k]


# ======================================================================================
# SOLAR ARRAY
# ======================================================================================
MOD_W, MOD_GAP = 1.00, 0.05


def module_row(p, n, slant):
    """n panel modules in local X, tilted plane = local XY, normal = local +Z"""
    total = n * MOD_W + (n - 1) * MOD_GAP
    for k in range(n):
        x = -total / 2 + MOD_W / 2 + k * (MOD_W + MOD_GAP)
        p.box((x, 0, 0), (MOD_W, slant, 0.06), "Frame", mats={"+z": "Solar", "-z": None})
        p.box((x, 0, 0.034), (0.025, slant, 0.008), "Frame", mats={"-z": None})
        for yy in (-slant / 6, slant / 6):
            p.box((x, yy, 0.034), (MOD_W, 0.02, 0.008), "Frame", mats={"-z": None})
    return total


def panel_table(p, cx, cy, n, slant=1.7, tilt=30.0, zc=1.35, footings=True):
    """a row of n modules facing -Y, on posts. Returns the half width."""
    c, s = cos(radians(tilt)), sin(radians(tilt))
    with p.at(T(cx, cy, zc), RX(tilt)):
        total = module_row(p, n, slant)
        p.box((0, slant / 2 + 0.05, 0.0), (total + 0.08, 0.09, 0.10), "Accent")
        p.box((0, -slant / 2 - 0.04, 0.0), (total + 0.08, 0.07, 0.08), "Frame")
        for yy in (-slant * 0.3, slant * 0.3):
            p.box((0, yy, -0.07), (total, 0.08, 0.08), "Frame")
    nposts = max(2, n // 2 + 1)
    for k in range(nposts):
        x = cx - total / 2 + 0.25 + (total - 0.5) * k / (nposts - 1)
        for yy in (-slant * 0.3, slant * 0.3):
            ztop = zc + yy * s - 0.1
            p.box0(x, cy + yy * c, 0.0, 0.09, 0.09, ztop, "Frame")
            if footings:
                p.box0(x, cy + yy * c, 0.0, 0.22, 0.22, 0.08, "HullDark")
        p.beam((x, cy - slant * 0.3 * c, 0.2), (x, cy + slant * 0.3 * c, zc + slant * 0.3 * s - 0.35), 0.05, 0.05, "Frame")
    return total / 2


def tracker(p, cx, cy, nx, ny, mast_h, tilt=35.0, slant=1.7, yaw=0.0):
    """two-axis tracker: mast, gear head, a nx x ny module array tilted toward -Y"""
    with p.at(T(cx, cy, 0)):
        p.lathe([(0.55, -0.02), (0.55, 0.12), (0.42, 0.20), (0.0, 0.20)], "HullDark", seg=12, smooth=False)
        p.vcyl(0, 0, 0.2, mast_h, 0.16, 0.13, seg=10, mat="Metal")
        p.vcyl(0, 0, mast_h * 0.45, mast_h * 0.45 + 0.12, 0.19, seg=10, mat="Accent")
        p.box((0, 0, mast_h + 0.1), (0.5, 0.42, 0.34), "Hull", bevel=0.05)
        p.cyl((-0.3, 0, mast_h + 0.12), (0.3, 0, mast_h + 0.12), 0.12, seg=10, mat="Frame")
    with p.at(T(cx, cy, mast_h + 0.35), RZ(yaw), RX(tilt)):
        total = 0
        for j in range(ny):
            yy = (j - (ny - 1) / 2) * (slant + 0.05)
            with p.at(T(0, yy, 0)):
                total = module_row(p, nx, slant)
        h = ny * (slant + 0.05)
        p.box((0, 0, -0.08), (0.14, h, 0.10), "Frame")
        p.box((0, 0, -0.08), (total, 0.12, 0.10), "Frame")
        p.box((0, h / 2 + 0.04, 0.0), (total + 0.06, 0.08, 0.09), "Accent")


def build_solar(spec):
    k = spec["size"]
    R = radius("solar_array", k)
    b = Part("Base")
    if k == 0:                                         # S: one table of three modules
        hw = panel_table(b, -0.15, 0.0, 3, slant=1.6, zc=1.25)
        LVK.kiosk(b, 1.55, -0.55, rot=0.0, w=0.55, d=0.45, h=0.85)
        b.box0(1.1, -0.2, 0.0, 0.8, 0.12, 0.08, "Frame")                           # cable duct
        kx, ky, kh, kw = 1.55, -0.55, 0.85, 0.55
        LV = dict(ring=R - 0.16, antenna=(kx - 0.12, ky + 0.1, 0.1 + kh + 0.06, 0.9),
                  band3=("box", kx, ky, 0.1 + kh * 0.45, kw, 0.45, 0.07), modules=[(1.45, 0.75, 0.0, 90.0, 0.8)],
                  band4=("box", kx, ky, 0.1 + kh * 0.25, kw, 0.45, 0.07), annex=[(-1.05, 1.18, 0.0, 0.0, 0.7)],
                  crown=(kx, ky, 0.1 + kh + 0.06, 0.34), beacon=(kx + 0.1, ky - 0.08, 0.1 + kh + 0.06, 0.45),
                  emblem=((kx + kw / 2 + 0.01, ky, 0.1 + kh * 0.5), (1, 0, 0), 0.14))
    elif k == 1:                                       # M: two rows of four
        for yc in (-1.12, 1.12):
            panel_table(b, -0.25, yc, 4, slant=1.7, zc=1.45)
        LVK.kiosk(b, 2.45, 0.0, rot=0.0, w=0.62, d=0.8, h=1.0)
        b.box0(1.9, 0.0, 0.0, 0.7, 0.14, 0.09, "Frame")
        for yc in (-1.12, 1.12):
            b.box0(-0.25, yc, 0.0, 4.3, 0.12, 0.07, "HullDark")                    # cable trays under the rows
        kx, ky, kh, kw = 2.45, 0.0, 1.0, 0.62
        LV = dict(ring=R - 0.16, antenna=(kx - 0.15, ky + 0.25, 0.1 + kh + 0.06, 1.1),
                  band3=("box", kx, ky, 0.1 + kh * 0.45, kw, 0.8, 0.08), modules=[(2.05, -1.6, 0.0, 0.0, 0.85)],
                  band4=("box", kx, ky, 0.1 + kh * 0.25, kw, 0.8, 0.08), annex=[(1.95, 1.6, 0.0, 0.0, 0.85)],
                  crown=(kx, ky, 0.1 + kh + 0.06, 0.45), beacon=(kx, ky - 0.2, 0.1 + kh + 0.06, 0.55),
                  emblem=((kx + kw / 2 + 0.01, ky, 0.1 + kh * 0.5), (1, 0, 0), 0.17))
    elif k == 2:                                       # L: four rows, inverter station
        for yc, n in ((-2.85, 4), (-0.95, 5), (0.95, 5), (2.85, 4)):
            panel_table(b, -0.1, yc, n, slant=1.7, zc=1.45)
            b.box0(-0.1, yc, 0.0, n * 1.05 + 0.1, 0.12, 0.07, "HullDark")
        LVK.kiosk(b, 3.3, 0.0, rot=0.0, w=0.7, d=1.0, h=1.25)
        b.box0(2.7, 0.0, 0.0, 0.6, 0.16, 0.09, "Frame")
        b.box0(2.75, 0.0, 0.0, 0.16, 5.7, 0.09, "Frame")                           # collector duct
        kx, ky, kh, kw = 3.3, 0.0, 1.25, 0.7
        LV = dict(ring=R - 0.16, antenna=(kx - 0.18, ky + 0.3, 0.1 + kh + 0.06, 1.3),
                  band3=("box", kx, ky, 0.1 + kh * 0.45, kw, 1.0, 0.09), modules=[(3.0, -1.9, 0.0, 0.0, 0.9)],
                  band4=("box", kx, ky, 0.1 + kh * 0.25, kw, 1.0, 0.09), annex=[(2.95, 1.95, 0.0, 0.0, 0.9)],
                  crown=(kx, ky, 0.1 + kh + 0.06, 0.55), beacon=(kx, ky - 0.25, 0.1 + kh + 0.06, 0.6),
                  emblem=((kx + kw / 2 + 0.01, ky, 0.1 + kh * 0.5), (1, 0, 0), 0.2))
    else:                                              # XL: central tracker, two small trackers, two fixed rows
        tracker(b, 0.0, 0.0, 4, 2, 2.3, tilt=35.0)
        for sx in (-1, 1):
            tracker(b, sx * 4.05, 0.0, 2, 1, 1.5, tilt=35.0)
        for yc in (-3.9, 3.9):
            panel_table(b, 0.0, yc, 5, slant=1.7, zc=1.4)
            b.box0(0.0, yc, 0.0, 5.3, 0.12, 0.07, "HullDark")
        LVK.kiosk(b, 3.55, -2.35, rot=0.0, w=0.7, d=0.9, h=1.2)
        b.box0(1.8, -1.2, 0.0, 3.5, 0.16, 0.09, "Frame")
        kx, ky, kh, kw = 3.55, -2.35, 1.2, 0.7
        LV = dict(ring=R - 0.16, antenna=(kx - 0.18, ky + 0.25, 0.1 + kh + 0.06, 1.3),
                  band3=("cyl", 0.0, 0.0, 1.0, 0.15, 0.14), modules=[(-3.55, -2.35, 0.0, 0.0, 0.95)],
                  band4=("cyl", 0.0, 0.0, 1.35, 0.14, 0.14), annex=[(-3.5, 2.35, 0.0, 0.0, 0.95)],
                  fins=[(3.6, 2.35, 0.0, 0.0, 5, 0.9, 0.55)],
                  crown=(kx, ky, 0.1 + kh + 0.06, 0.55), beacon=(kx, ky - 0.2, 0.1 + kh + 0.06, 0.6),
                  emblem=((kx + kw / 2 + 0.01, ky, 0.1 + kh * 0.5), (1, 0, 0), 0.2))
    return [b] + LVK.add_levels([b], LV)


# ======================================================================================
# WIND TURBINE
# ======================================================================================
def blade(r, hub, L, k):
    """one blade in the rotor's XZ plane pointing up (+Z), turned by RY(120 * k) about the hub"""
    with r.at(T(*hub), RY(120.0 * k)):
        sections = [(0.20, -0.14, 0.14, 0.16, 0.0), (0.16 * L, -0.30, 0.18, 0.12, 10.0), (0.45 * L, -0.24, 0.12, 0.08, 6.0),
                    (0.80 * L, -0.13, 0.07, 0.045, 2.0), (L, -0.04, 0.03, 0.02, 0.0)]
        rings = []
        for (z, c0, c1, th, tw) in sections:
            ca, sa = cos(radians(tw)), sin(radians(tw))
            pts = [(c1, -th / 2), (c1, th / 2), (c0, th / 2), (c0, -th / 2)]
            rings.append([(x * ca - y * sa, x * sa + y * ca, z) for x, y in pts])
        r.loft(rings, lambda kk, i: "Accent" if kk == 3 else "Hull", smooth=False, closed=True, cap0=True, cap1=True)


def build_wind(spec):
    k = spec["size"]
    R = radius("wind_turbine", k)
    H = BLD["wind_turbine"]["sizes"]["mast_height"][k]
    s = (0.72, 1.0, 1.3, 1.6)[k]                       # detail scale
    L = (2.05, 2.45, 3.05, 3.65)[k]                    # blade length from the hub centre
    hub_y = -(0.52 + 0.08 * k)
    hub = Vector((0.0, hub_y, H + 0.32 * s))
    b = Part("Base")
    rot = Part("Rotor", origin=tuple(hub))
    # foundation
    LVK.pad(b, R * 0.82, h=0.14, seg=16)
    b.vcyl(0, 0, 0.14, 0.32, 0.46 * s, seg=12, mat="Frame")
    for i in range(8):
        x, y, _ = polar(0.38 * s, 45.0 * i)
        b.vcyl(x, y, 0.32, 0.38, 0.04 * s, seg=5, mat="Metal")
    # tower: tapered tube with flanges and an accent band
    r0, r1 = 0.36 * s, 0.20 * s
    prof = [(r0, 0.32), (r0, 0.45), (r0 * 0.96, H * 0.18), (r0 * 0.96 + 0.02, H * 0.18 + 0.03),
            (r0 * 0.96 + 0.02, H * 0.18 + 0.18), (r0 * 0.94, H * 0.18 + 0.21), (r1 + (r0 - r1) * 0.45, H * 0.55),
            (r1 + (r0 - r1) * 0.45 + 0.02, H * 0.55 + 0.02), (r1 + (r0 - r1) * 0.45 + 0.02, H * 0.55 + 0.08),
            (r1 + (r0 - r1) * 0.44, H * 0.55 + 0.10), (r1, H - 0.05)]
    mats = ["Frame", "Hull", "Accent", "Accent", "Accent", "Hull", "Frame", "Frame", "Frame", "Hull"]
    b.lathe(prof, lambda kk, i: mats[kk] if kk < len(mats) else "Hull", seg=14)
    # door on +X
    b.box((r0 - 0.01, 0, 0.32 + 0.55 * s), (0.08, 0.36 * s, 0.9 * s), "HullDark")
    b.box((r0 + 0.035, 0, 0.32 + 0.95 * s), (0.02, 0.2 * s, 0.1 * s), "Light")
    if k >= 2:                                           # service platform with railing
        zp = H * 0.62
        rp = r1 + (r0 - r1) * 0.35 + 0.55
        b.lathe([(rp, zp - 0.08), (rp, zp), (r1 + 0.05, zp), (r1 + 0.05, zp - 0.08)], "Frame", seg=14, smooth=False)
        for i in range(10):
            x, y, _ = polar(rp - 0.03, 36.0 * i)
            b.beam((x, y, zp), (x, y, zp + 0.85), 0.04, 0.04, "Frame")
        b.lathe([(rp, zp + 0.82), (rp, zp + 0.88), (rp - 0.05, zp + 0.88), (rp - 0.05, zp + 0.82)], "Hazard", seg=14,
                smooth=False)
        for i in range(4):
            x, y, _ = polar(rp - 0.1, 45.0 + 90.0 * i)
            b.beam((x, y, zp - 0.05), ((r1 + 0.2) * cos(radians(45 + 90 * i)), (r1 + 0.2) * sin(radians(45 + 90 * i)),
                                       zp - 0.9), 0.05, 0.05, "Frame")
    if k >= 1:                                           # transformer kiosk and cable duct
        kx, ky = (R * 0.60, R * 0.30)
        LVK.kiosk(b, kx, ky, rot=0.0, w=0.46 * s + 0.1, d=0.40 * s + 0.1, h=0.7 * s + 0.2)
        b.box0((kx + 0.0) / 2, ky / 2, 0.0, kx, 0.12, 0.08, "Frame")
    # nacelle (fixed), rotor faces -Y
    nz = H + 0.32 * s
    b.vcyl(0, 0, H - 0.05, H + 0.08, r1 + 0.06, seg=12, mat="Frame")
    b.box((0, 0.15 * s, nz), (0.62 * s, 1.55 * s, 0.62 * s), "Hull", bevel=0.12 * s)
    b.box((0, 0.35 * s, nz), (0.645 * s, 0.30 * s, 0.645 * s), "Accent", bevel=0.10 * s)
    b.box((0, 0.93 * s, nz + 0.02), (0.50 * s, 0.10 * s, 0.50 * s), "Frame", bevel=0.03)
    for i in range(4):                                   # cooling fins at the back
        b.box((0, 0.99 * s + 0.0, nz - 0.18 * s + 0.12 * s * i), (0.46 * s, 0.10 * s, 0.03 * s), "Metal")
    b.vcyl(0.12 * s, 0.75 * s, nz + 0.30 * s, nz + 0.65 * s, 0.02, seg=4, mat="Frame", smooth=False)    # anemometer
    b.beam((0.02 * s, 0.75 * s, nz + 0.65 * s), (0.22 * s, 0.75 * s, nz + 0.65 * s), 0.02, 0.02, "Frame")
    b.cyl((0, hub_y + 0.62, nz), (0, hub_y + 0.30, nz), 0.24 * s, seg=12, mat="Frame")
    # rotor: spinner + three blades
    rot.cyl(hub + Vector((0, 0.30, 0)), hub + Vector((0, -0.06, 0)), 0.30 * s, seg=12, mat="Hull")
    rot.cyl(hub + Vector((0, -0.06, 0)), hub + Vector((0, -0.46 * s, 0)), 0.30 * s, 0.0, seg=12, mat="Accent", cap0=False)
    for i in range(3):
        blade(rot, hub, L, i)
        with rot.at(T(*hub), RY(120.0 * i)):
            rot.cyl((0, 0, 0.12 * s), (0, 0, 0.30 * s), 0.12 * s, seg=8, mat="Frame")
    mz = H
    LV = dict(ring=R * 0.82 - 0.05,
              antenna=(-0.12 * s, 0.55 * s, nz + 0.31 * s, 0.7 + 0.2 * k),
              band3=("cyl", 0, 0, H * 0.34, r0 * 0.96 - (r0 - r1) * 0.30, 0.16 * s),
              modules=[(-R * 0.55, -R * 0.35, 0.14, 0.0, 0.6 + 0.12 * k)],
              band4=("cyl", 0, 0, H * 0.44, r0 * 0.96 - (r0 - r1) * 0.42, 0.16 * s),
              annex=[(-R * 0.5, R * 0.42, 0.14, 90.0, 0.55 + 0.12 * k)],
              crown=(0, 0, H - 0.34 * s, r1 + 0.16 * s),
              beacon=(0.0, 0.62 * s, nz + 0.31 * s, 0.35),
              emblem=((r0 + 0.02, 0, 0.32 + 1.6 * s), (1, 0, 0), 0.10 + 0.04 * k))
    return [b, rot] + LVK.add_levels([b], LV)


# ======================================================================================
# BATTERY BANK
# ======================================================================================
def cabinet(p, x, y, face, w=0.80, d=1.0, h=1.40, z0=0.20):
    """battery cabinet; face = +1 (front +X) or -1 (front -X)"""
    p.box0(x, y, z0, d, w, h, "Hull", bevel=0.05)
    fx = x + face * (d / 2 + 0.006)
    f = {"-x": None} if face > 0 else {"+x": None}
    p.box((fx, y, z0 + h * 0.5), (0.012, w * 0.78, h * 0.68), "HullDark", mats=f)
    p.box((fx + face * 0.006, y, z0 + h * 0.93), (0.014, w + 0.01, 0.10), "Accent", mats=f)
    p.box((fx + face * 0.012, y + w * 0.28, z0 + h * 0.93), (0.02, 0.10, 0.05), "Light")
    for j in range(3):
        p.box((fx + face * 0.008, y - w * 0.15, z0 + h * (0.30 + 0.12 * j)), (0.012, w * 0.34, 0.05), "Frame", mats=f)
    for j in range(4):                                           # cooling fins on the roof
        p.box0(x, y - w * 0.33 + w * 0.22 * j, z0 + h, d * 0.8, 0.04, 0.14, "Metal")
    p.box0(x, y, z0 + h, d * 0.88, w * 0.9, 0.03, "Frame")


def connector_post(p, x, y, h=1.9):
    """round grid-connector post with insulators (the L5 crown sits on it)"""
    p.vcyl(x, y, 0.0, 0.12, 0.28, seg=10, mat="Frame")
    p.vcyl(x, y, 0.12, h, 0.12, 0.10, seg=10, mat="Metal")
    for j in range(3):
        p.vcyl(x, y, h * 0.45 + 0.22 * j, h * 0.45 + 0.22 * j + 0.08, 0.16, seg=10, mat="Hull")
    p.box((x, y, h + 0.05), (0.5, 0.12, 0.10), "Frame")
    for sx in (-0.2, 0.2):
        p.vcyl(x + sx, y, h + 0.1, h + 0.28, 0.05, seg=6, mat="Hull")


def build_battery(spec):
    k = spec["size"]
    R = radius("battery", k)
    b = Part("Base")
    if k == 0:                                         # S: two cabinets on a skid
        for sx in (-0.30, 0.30):
            b.box0(sx, 0, 0.0, 0.14, 1.65, 0.20, "Frame")
        b.box0(0, 0, 0.12, 1.0, 1.6, 0.08, "HullDark")
        for y in (-0.41, 0.41):
            cabinet(b, 0.05, y, 1, w=0.76, d=0.85, h=1.25)
        b.box((0, 0, 1.28), (0.88, 1.60, 0.10), "Accent", mats={"-z": None, "+z": None})
        connector_post(b, -0.62, 0.62, 1.5)
        top, px, py, ph = 1.45, -0.62, 0.62, 1.5
        LV = dict(ring=R - 0.12, antenna=(-0.3, -0.55, top + 0.15, 0.8),
                  band3=("box", 0.05, 0, 0.55, 0.85, 1.58, 0.07), modules=[(-0.72, -0.62, 0.0, 90.0, 0.62)],
                  band4=("box", 0.05, 0, 0.40, 0.85, 1.58, 0.07), annex=[(0.9, 0.0, 0.0, 90.0, 0.55)],
                  crown=(px, py, ph - 0.25, 0.14), beacon=(px, py, ph + 0.28, 0.25),
                  emblem=((0.49, 0.41, 0.6), (1, 0, 0), 0.12))
    elif k == 1:                                       # M: three cabinets, rear radiator
        for sx in (-0.45, 0.45):
            b.box0(sx, 0, 0.0, 0.16, 2.80, 0.20, "Frame")
        b.box0(0, 0, 0.12, 1.30, 2.70, 0.10, "HullDark")
        for y in (-0.86, 0.0, 0.86):
            cabinet(b, 0.0, y, 1, w=0.80, d=1.0, h=1.38)
        b.box((0, 0, 1.50), (1.09, 2.56, 0.10), "Accent", mats={"-z": None, "+z": None})
        b.box0(-0.66, 0, 0.30, 0.14, 2.3, 1.0, "Frame")
        for j in range(9):
            b.box0(-0.77, -1.0 + 0.25 * j, 0.35, 0.10, 0.05, 0.90, "Metal")
        connector_post(b, 0.95, 1.05, 1.7)
        b.tube([(0.3, 1.32, 0.45), (0.6, 1.15, 0.45), (0.95, 1.05, 0.12)], 0.06, seg=6, mat="Rubber", fillet=0.1)
        px, py, ph = 0.95, 1.05, 1.7
        LV = dict(ring=R - 0.12, antenna=(-0.2, -0.86, 1.78, 0.9),
                  band3=("box", 0.0, 0, 0.62, 1.0, 2.52, 0.08), modules=[(0.95, -1.1, 0.0, 0.0, 0.7)],
                  band4=("box", 0.0, 0, 0.45, 1.0, 2.52, 0.08), annex=[(-1.2, 0.0, 0.0, 90.0, 0.62)],
                  crown=(px, py, ph - 0.25, 0.16), beacon=(px, py, ph + 0.28, 0.28),
                  emblem=((0.51, 0.0, 0.75), (1, 0, 0), 0.14))
    elif k == 2:                                       # L: two rows back to back, roof cooler, transformer
        b.box0(0, 0, 0.0, 2.55, 2.9, 0.18, "Frame")
        b.box0(0, 0, 0.1, 2.45, 2.8, 0.10, "HullDark")
        for face, x in ((1, 0.62), (-1, -0.62)):
            for y in (-0.87, 0.0, 0.87):
                cabinet(b, x, y, face, w=0.82, d=1.0, h=1.45)
        b.box((0, 0, 1.55), (2.3, 2.66, 0.10), "Accent", mats={"-z": None, "+z": None})
        b.box0(0, 0, 1.79, 1.4, 1.6, 0.36, "HullDark", bevel=0.06)                   # roof cooler
        b.vcyl(0.35, 0.4, 2.15, 2.22, 0.34, seg=12, mat="Frame")
        b.vcyl(-0.35, -0.4, 2.15, 2.22, 0.34, seg=12, mat="Frame")
        b.box0(0.0, 1.85, 0.0, 1.0, 0.55, 0.95, "Frame", bevel=0.05)                 # transformer
        for j in range(5):
            b.box0(-0.4 + 0.2 * j, 2.14, 0.15, 0.05, 0.08, 0.7, "Metal")
        connector_post(b, -1.3, 1.6, 1.9)
        px, py, ph = -1.3, 1.6, 1.9
        LV = dict(ring=R - 0.12, antenna=(0.6, -0.9, 1.84, 1.0),
                  band3=("box", 0.0, 0.0, 0.66, 2.1, 2.52, 0.09), modules=[(1.25, -1.55, 0.0, 0.0, 0.75)],
                  band4=("box", 0.0, 0.0, 0.48, 2.1, 2.52, 0.09), annex=[(-1.2, -1.6, 0.0, 0.0, 0.72)],
                  crown=(px, py, ph - 0.25, 0.16), beacon=(px, py, ph + 0.28, 0.3),
                  emblem=((1.13, 0.0, 0.8), (1, 0, 0), 0.16))
    else:                                              # XL: two rows of four, aisle canopy, radiator bank
        b.box0(0, 0, 0.0, 2.9, 4.0, 0.18, "Frame")
        b.box0(0, 0, 0.1, 2.8, 3.9, 0.10, "HullDark")
        for face, x in ((1, 0.78), (-1, -0.78)):
            for y in (-1.29, -0.43, 0.43, 1.29):
                cabinet(b, x, y, face, w=0.82, d=0.95, h=1.50)
        b.box((0.78, 0, 1.60), (1.0, 3.5, 0.10), "Accent", mats={"-z": None, "+z": None})
        b.box((-0.78, 0, 1.60), (1.0, 3.5, 0.10), "Accent", mats={"-z": None, "+z": None})
        b.box0(0, 0, 0.2, 0.55, 3.6, 0.10, "Frame")                                  # aisle floor
        for y in (-1.6, 1.6):                                                        # canopy over the aisle
            b.box0(0, y, 1.7, 0.08, 0.08, 0.5, "Frame")
        b.box0(0, 0, 2.2, 0.8, 3.4, 0.06, "Solar")
        b.box0(0, 0, 2.16, 0.86, 3.46, 0.04, "Frame")
        b.box0(0.0, -2.35, 0.0, 2.2, 0.60, 1.3, "Frame", bevel=0.04)               # radiator bank
        for j in range(10):
            b.box0(-0.95 + 0.21 * j, -2.35, 1.3, 0.05, 0.56, 0.35, "Metal")
        b.box0(0.0, 2.3, 0.0, 1.2, 0.60, 1.1, "Frame", bevel=0.05)                 # transformer
        for j in range(6):
            b.box0(-0.5 + 0.2 * j, 2.62, 0.15, 0.05, 0.08, 0.8, "Metal")
        connector_post(b, -1.35, 2.35, 2.1)
        px, py, ph = -1.35, 2.35, 2.1
        LV = dict(ring=R - 0.12, antenna=(0.8, -1.29, 1.9, 1.1),
                  band3=("box", 0.0, 0.0, 0.68, 2.55, 3.45, 0.10), modules=[(1.55, 2.35, 0.0, 0.0, 0.8)],
                  band4=("box", 0.0, 0.0, 0.50, 2.55, 3.45, 0.10), annex=[(1.5, -2.2, 0.0, 90.0, 0.62)],
                  crown=(px, py, ph - 0.25, 0.16), beacon=(px, py, ph + 0.28, 0.32),
                  emblem=((1.26, 0.43, 0.85), (1, 0, 0), 0.17))
    return [b] + LVK.add_levels([b], LV)


# ======================================================================================
BUDGET = (3000, 4500, 6500, 9000)
MODELS = []
for bid, fn, accent in (("solar_array", build_solar, "utilities"), ("wind_turbine", build_wind, "utilities"),
                        ("battery", build_battery, "utilities")):
    for k, sz in enumerate(SIZES):
        objs = ["Base", "L2", "L3", "L4", "L5"] + (["Rotor"] if bid == "wind_turbine" else [])
        MODELS.append(dict(id="%s_%s" % (bid, sz), kind="exterior", footprint=radius(bid, k), accent=accent,
                           budget=BUDGET[k], objects=objs, size=k, also=[bid] if k == 1 else [],
                           free={"Rotor": 1.0} if bid == "wind_turbine" else {},
                           ao=dict(dist=0.6 + 0.2 * k, samples=32), builder=fn))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    rows = []
    for spec in MODELS:
        if only and spec["id"] not in only and spec["id"].rsplit("_", 1)[0] not in only:
            continue
        print("building", spec["id"], "...")
        rows.append(C.build_model(spec, spec["builder"]))
    C.write_reports(rows)


if __name__ == "__main__":
    main()
