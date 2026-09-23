"""
Frontier Habitat 2.0 - life-support exteriors: water_extractor, reservoir (sizes S, M, L, XL).

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_life.py -- [--only reservoir_xl,water_extractor]

Output: assets/models/<id>_s|m|l|xl.glb and <id>.glb (= size M, the v1 name). Objects Base, L2, L3, L4, L5.
Accent = life-support teal. Water parts use WaterBlue.
"""
import os
import sys
from math import sin, cos, pi, radians, sqrt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402
from ext_common import Part, T, RX, RY, RZ, S, polar, dome_profile   # noqa: E402
import ext_levels as LVK                                   # noqa: E402
from mathutils import Vector                               # noqa: E402

BLD = C.load_content("buildings.json")
SIZES = ("s", "m", "l", "xl")


def radius(bid, k):
    return BLD[bid]["sizes"]["radius"][k]


# ======================================================================================
# shared parts
# ======================================================================================
def rig(p, cx, cy, n, foot_r, apex_z, top_r=0.32, levels=(0.34, 0.68), a0=90.0, leg_w=0.15, string=True):
    """lattice drill rig over a wellhead"""
    angs = [radians(a0 + 360.0 * i / n) for i in range(n)]
    feet = [Vector((cx + foot_r * cos(a), cy + foot_r * sin(a), 0.0)) for a in angs]
    tops = [Vector((cx + top_r * cos(a), cy + top_r * sin(a), apex_z)) for a in angs]
    for f, t, a in zip(feet, tops, angs):
        p.beam(f + Vector((0, 0, 0.08)), t, leg_w, leg_w, "Frame")
        with p.at(T(f.x, f.y, 0.0), RZ(degrees_(a))):
            p.box0(0, 0, 0.0, 0.5, 0.5, 0.12, "HullDark")
    fr = [0.08 / apex_z] + list(levels) + [0.97]
    pts = [[f + (t - f) * q for f, t in zip(feet, tops)] for q in fr]
    for q in pts[1:-1]:
        for i in range(n):
            p.beam(q[i], q[(i + 1) % n], leg_w * 0.62, leg_w * 0.62, "Frame")
    for lv in range(len(pts) - 1):
        lo, hi = pts[lv], pts[lv + 1]
        for i in range(n):
            j = (i + 1) % n
            p.beam(lo[i], hi[j], leg_w * 0.42, leg_w * 0.42, "Frame")
            if lv % 2 == 0:
                p.beam(lo[j], hi[i], leg_w * 0.42, leg_w * 0.42, "Frame")
    # crown block, sheave, drill string, drive head
    p.vcyl(cx, cy, apex_z - 0.12, apex_z + 0.22, top_r + 0.2, seg=n * 2, mat="Accent", smooth=False)
    p.box((cx, cy, apex_z + 0.30), (0.5, 0.5, 0.16), "Frame")
    p.cyl((cx, cy - 0.1, apex_z + 0.55), (cx, cy + 0.1, apex_z + 0.55), 0.26, seg=10, mat="Metal")
    if string:
        p.vcyl(cx, cy, 0.9, apex_z, 0.08, seg=8, mat="Metal", cap0=False, cap1=False)
        zd = apex_z * 0.5
        p.box((cx, cy, zd), (0.55, 0.55, 0.5), "HullDark", bevel=0.05)
        p.box((cx, cy, zd), (0.59, 0.59, 0.14), "Accent")
        p.cyl((cx + 0.28, cy, zd + 0.12), (cx + 0.5, cy, zd + 0.12), 0.08, seg=6, mat="Frame")
    return tops


def degrees_(a):
    return a * 180.0 / pi


def wellhead(p, cx, cy, s=1.0):
    with p.at(T(cx, cy, 0.0), S(s)):
        p.lathe([(0.62, 0.0), (0.62, 0.22), (0.44, 0.30), (0.44, 0.60), (0.32, 0.68), (0.32, 0.95), (0.0, 0.95)],
                lambda k, i: ("HullDark", "HullDark", "WaterBlue", "HullDark", "HullDark", "Frame")[k], seg=12)
        for a in (0.0, 180.0):
            x, y, _ = polar(0.44, a)
            p.cyl((x, y, 0.45), (x * 1.5, y * 1.5, 0.45), 0.09, seg=8, mat="Metal")
            p.cyl((x * 1.5, y * 1.5, 0.45), (x * 1.62, y * 1.62, 0.45), 0.13, seg=8, mat="WaterBlue")


def pump_skid(p, x, y, rot=0.0, s=1.0):
    with p.at(T(x, y, 0.0), RZ(rot), S(s)):
        p.box0(0, 0, 0.0, 1.3, 0.95, 0.14, "Frame")
        p.box0(-0.15, 0, 0.14, 0.75, 0.75, 0.70, "Hull", bevel=0.06)
        p.box((-0.15, 0, 0.72), (0.79, 0.79, 0.14), "Accent")
        p.box((0.23, 0, 0.45), (0.02, 0.5, 0.3), "HullDark")
        p.cyl((0.22, 0, 0.50), (0.62, 0, 0.50), 0.25, seg=10, mat="Metal")
        p.cyl((0.60, 0, 0.50), (0.66, 0, 0.50), 0.27, seg=10, mat="Frame")
        p.box0(0.35, 0, 0.14, 0.4, 0.5, 0.12, "Hazard")
        p.box((-0.15, 0.3, 0.97), (0.10, 0.10, 0.06), "Light")


def vtank(p, x, y, r, h, z0=0.0, ladder=True, band=True):
    """vertical tank with a domed top, a water band and a ladder"""
    with p.at(T(x, y, z0)):
        p.vcyl(0, 0, 0.0, 0.14, r + 0.08, seg=14, mat="Frame")
        p.vcyl(0, 0, 0.14, h, r, seg=14, mat="Hull", cap0=False, cap1=False)
        if band:
            p.vcyl(0, 0, h * 0.45, h * 0.62, r + 0.015, seg=14, mat="WaterBlue", cap0=False, cap1=False)
            p.vcyl(0, 0, h * 0.85, h * 0.91, r + 0.015, seg=14, mat="Accent", cap0=False, cap1=False)
        with p.at(T(0, 0, h)):
            p.lathe(dome_profile(r, 0.0, r * 0.45, 3), "Hull", seg=14)
        p.vcyl(0, 0, h + r * 0.42, h + r * 0.42 + 0.16, 0.10, seg=8, mat="Frame")
    if ladder:
        LVK.ladder(p, x + r + 0.12, y, 0.0, z0 + h + 0.1, rot=0.0, w=0.36)


def htank(p, cx, cy, zc, r, L, bands=True, stripe=True):
    """horizontal tank along X (capsule) with accent bands and a WaterBlue level stripe"""
    e = r * 0.72
    prof = [(0.0, -L / 2 - e * 0.25), (r * 0.52, -L / 2 - e * 0.18), (r * 0.84, -L / 2 + e * 0.05), (r, -L / 2 + e * 0.35),
            (r, -L * 0.30), (r, -L * 0.24), (r, L * 0.24), (r, L * 0.30), (r, L / 2 - e * 0.35), (r * 0.84, L / 2 - e * 0.05),
            (r * 0.52, L / 2 + e * 0.18), (0.0, L / 2 + e * 0.25)]
    mats = ["Hull", "Hull", "Hull", "Hull", "Accent" if bands else "Hull", "Hull", "Accent" if bands else "Hull", "Hull",
            "Hull", "Hull", "Hull"]
    with p.at(T(cx, cy, zc), RY(90.0)):
        p.lathe(prof, lambda k, i: mats[k], seg=20)
        if stripe:
            for a0 in (118.0, 214.0):
                p.lathe([(r, -L * 0.22), (r + 0.03, -L * 0.22), (r + 0.03, L * 0.22), (r, L * 0.22)], "WaterBlue", seg=3,
                        a0=a0, a1=a0 + 28.0, smooth=True)


def saddles(p, cx, cy, zc, r, L, n=2, w=None):
    w = w or r * 1.8
    xs = [cx - L * 0.3, cx + L * 0.3] if n == 2 else [cx - L * 0.36, cx, cx + L * 0.36]
    for x in xs:
        p.prism_x([(cy - w / 2, 0.0), (cy + w / 2, 0.0), (cy + w / 2, zc - r * 0.55), (cy + r * 0.62, zc - r * 0.2),
                   (cy - r * 0.62, zc - r * 0.2), (cy - w / 2, zc - r * 0.55)], x - 0.16, x + 0.16, "Frame")
        p.box0(x, cy, 0.0, 0.5, w + 0.2, 0.08, "HullDark")


# ======================================================================================
# WATER EXTRACTOR
# ======================================================================================
def build_extractor(spec):
    k = spec["size"]
    R = radius("water_extractor", k)
    b = Part("Base")
    if k == 0:                                   # S: tripod rig, small pump, gauge
        tops = rig(b, 0.0, 0.0, 3, 1.25, 3.1, top_r=0.24, levels=(0.45,), leg_w=0.12)
        wellhead(b, 0.0, 0.0, 0.8)
        pump_skid(b, 0.95, -0.85, rot=-40.0, s=0.7)
        b.tube([(0.36, 0, 0.36), (0.65, -0.45, 0.36), (0.8, -0.7, 0.36)], 0.07, seg=6, mat="Metal", fillet=0.15)
        crown_z, band_spec, band4 = 3.1 + 0.22, ("cyl", 0.0, 0.0, 1.35, 0.08, 0.14), ("cyl", 0.0, 0.0, 1.9, 0.08, 0.14)
        LV = dict(ring=R - 0.14, antenna=(0.1, 0.1, 3.1 + 0.38, 0.8), band3=band_spec,
                  modules=[(-1.05, -0.85, 0.0, 30.0, 0.6)], band4=band4, annex=[(-0.9, 1.0, 0.0, -30.0, 0.55)],
                  crown=(0.0, 0.0, 3.1 + 0.25, 0.46), beacon=(0.0, 0.0, 3.1 + 0.62, 0.3),
                  emblem=((0.95 + 0.2, -0.85 - 0.1, 0.45), (0.77, -0.64, 0.0), 0.1))
    elif k == 1:                                 # M: three-leg rig, pump skid, separator tank
        rig(b, 0.0, 0.0, 3, 1.9, 4.2, top_r=0.30, leg_w=0.15)
        wellhead(b, 0.0, 0.0)
        pump_skid(b, 1.25, 0.0, rot=0.0)
        b.tube([(0.30, 0, 0.46), (0.72, 0, 0.46)], 0.10, seg=8, mat="Metal", caps=False)
        b.tube([(1.92, 0, 0.50), (2.2, 0, 0.50), (2.2, 0, 1.2), (2.2, -0.5, 1.2)], 0.09, seg=8, mat="Metal", fillet=0.16)
        vtank(b, -0.55, -1.55, 0.40, 1.5, ladder=False)
        b.tube([(-0.55, -1.55, 1.85), (-0.55, -1.55, 2.05), (-0.1, -0.3, 2.05), (-0.1, -0.3, 1.0)], 0.06, seg=6, mat="Metal",
               fillet=0.15)
        LV = dict(ring=R - 0.14, antenna=(0.12, 0.12, 4.2 + 0.38, 1.0), band3=("cyl", -0.55, -1.55, 0.35, 0.40, 0.14),
                  modules=[(-1.35, 0.9, 0.0, 60.0, 0.7)], band4=("cyl", -0.55, -1.55, 1.05, 0.40, 0.14),
                  annex=[(0.85, 1.55, 0.0, 20.0, 0.68)],
                  crown=(0.0, 0.0, 4.2 + 0.25, 0.52), beacon=(0.0, 0.0, 4.2 + 0.62, 0.35),
                  emblem=((1.25 - 0.15 + 0.39, 0.0, 0.45), (1, 0, 0), 0.13))
    elif k == 2:                                 # L: four-leg derrick, pump house, tank, pipe rack
        rig(b, 0.0, 0.0, 4, 1.75, 5.6, top_r=0.34, levels=(0.25, 0.5, 0.75), a0=45.0, leg_w=0.17)
        wellhead(b, 0.0, 0.0, 1.1)
        LVK.kiosk(b, 2.1, -1.2, rot=0.0, w=1.1, d=1.0, h=1.5)                       # pump house
        pump_skid(b, 2.1, 1.1, rot=0.0, s=0.9)
        vtank(b, -2.05, -1.2, 0.55, 2.0)
        b.tube([(0.4, 0, 0.5), (1.45, 0, 0.5), (1.45, -1.2, 0.5), (1.55, -1.2, 0.5)], 0.10, seg=8, mat="Metal", fillet=0.2)
        b.tube([(-2.05, -1.2, 2.5), (-2.05, -1.2, 2.8), (-0.3, -0.3, 2.8), (-0.3, -0.3, 1.0)], 0.07, seg=6, mat="Metal",
               fillet=0.18)
        for y in (-0.55, 0.55):                                                   # pipe rack to the west
            b.box0(-1.6, y + 1.2, 0.0, 0.12, 0.12, 1.2, "Frame")
        b.box0(-1.6, 1.2, 1.2, 0.2, 1.3, 0.1, "Frame")
        b.cyl((-2.4, 0.95, 1.36), (-0.6, 0.95, 1.36), 0.09, seg=8, mat="WaterBlue")
        b.cyl((-2.4, 1.45, 1.36), (-0.6, 1.45, 1.36), 0.09, seg=8, mat="Metal")
        LV = dict(ring=R - 0.14, antenna=(0.12, 0.12, 5.6 + 0.38, 1.1), band3=("cyl", -2.05, -1.2, 0.45, 0.55, 0.16),
                  modules=[(0.5, 2.55, 0.0, 0.0, 0.8)], band4=("cyl", -2.05, -1.2, 1.35, 0.55, 0.16),
                  annex=[(-0.2, -2.7, 0.0, 0.0, 0.8)],
                  crown=(0.0, 0.0, 5.6 + 0.25, 0.58), beacon=(0.0, 0.0, 5.6 + 0.62, 0.4),
                  emblem=((2.1 + 0.56, -1.2, 0.9), (1, 0, 0), 0.16))
    else:                                        # XL: twin rigs, manifold, big tank, pump skid
        for cx in (-1.55, 1.55):
            rig(b, cx, -0.9, 3, 1.35, 4.6, top_r=0.28, leg_w=0.15, a0=90.0)
            wellhead(b, cx, -0.9, 0.9)
        b.tube([(-1.2, -0.9, 0.45), (-0.3, -0.9, 0.45), (-0.3, 0.6, 0.45)], 0.11, seg=8, mat="Metal", fillet=0.25)
        b.tube([(1.2, -0.9, 0.45), (0.3, -0.9, 0.45), (0.3, 0.6, 0.45)], 0.11, seg=8, mat="Metal", fillet=0.25)
        b.box0(0.0, 0.8, 0.0, 1.2, 0.7, 0.75, "HullDark", bevel=0.05)                # manifold block
        b.box((0.0, 0.8, 0.62), (1.24, 0.74, 0.12), "Accent")
        vtank(b, -1.2, 2.45, 0.85, 2.2)
        pump_skid(b, 1.5, 2.2, rot=90.0, s=0.95)
        b.tube([(-0.35, 1.0, 0.62), (-0.6, 1.8, 0.62), (-0.9, 2.1, 0.62)], 0.09, seg=8, mat="WaterBlue", fillet=0.2)
        b.tube([(0.35, 1.0, 0.5), (0.9, 1.6, 0.5), (1.5, 1.6, 0.5)], 0.09, seg=8, mat="Metal", fillet=0.2)
        LV = dict(ring=R - 0.14, antenna=(1.65, -0.8, 4.6 + 0.38, 1.1), band3=("cyl", -1.2, 2.45, 0.5, 0.85, 0.18),
                  modules=[(2.9, 0.3, 0.0, 90.0, 0.85)], band4=("cyl", -1.2, 2.45, 1.45, 0.85, 0.18),
                  annex=[(-3.0, 0.3, 0.0, 90.0, 0.85)],
                  crown=(-1.55, -0.9, 4.6 + 0.25, 0.5), beacon=(-1.55, -0.9, 4.6 + 0.62, 0.4),
                  emblem=((0.61, 0.8, 0.4), (1, 0, 0), 0.16))
    return [b] + LVK.add_levels([b], LV)


# ======================================================================================
# RESERVOIR
# ======================================================================================
def tank_walkway(p, cx, cy, top_z, L, w=0.7):
    p.box0(cx, cy, top_z, L, w, 0.06, "Frame")
    for sy in (-1, 1):
        LVK.railing(p, [(cx - L / 2 + 0.05, cy + sy * (w / 2 - 0.03), top_z + 0.06),
                        (cx + L / 2 - 0.05, cy + sy * (w / 2 - 0.03), top_z + 0.06)], h=0.8, post_every=1.2)


def build_reservoir(spec):
    k = spec["size"]
    R = radius("reservoir", k)
    b = Part("Base")
    if k == 0:                                   # S: small horizontal tank
        r, L, zc = 0.92, 2.2, 1.18
        htank(b, 0.0, 0.0, zc, r, L)
        saddles(b, 0.0, 0.0, zc, r, L)
        b.vcyl(-0.2, 0, zc + r - 0.08, zc + r + 0.12, 0.30, seg=10, mat="HullDark")
        b.tube([(1.55, 0, 0.62), (1.85, 0, 0.62), (1.85, 0, 0.08)], 0.08, seg=6, mat="Metal", fillet=0.15)
        b.cyl((1.6, 0, 0.62), (1.7, 0, 0.62), 0.12, seg=8, mat="WaterBlue")
        gx = -0.5
        b.vcyl(gx, -r - 0.12, zc - 0.6, zc + 0.6, 0.05, seg=6, mat="Frame")
        b.vcyl(gx, -r - 0.12, zc - 0.45, zc + 0.2, 0.065, seg=6, mat="WaterBlue", cap0=False, cap1=False)
        LV = dict(ring=R - 0.14, antenna=(0.4, 0.2, zc + r - 0.05, 0.8), band3=("xcyl", -0.6, 0.0, zc, r, 0.12),
                  modules=[(-1.25, -0.95, 0.0, 30.0, 0.55)], band4=("xcyl", 0.6, 0.0, zc, r, 0.12),
                  annex=[(-1.2, 0.95, 0.0, -30.0, 0.5)],
                  crown=(-0.2, 0.0, zc + r + 0.1, 0.36), beacon=(-0.2, 0.0, zc + r + 0.12, 0.35),
                  emblem=((L / 2 + r * 0.5, 0.0, zc), (1, 0, 0), 0.14))
    elif k == 1:                                 # M: tank with a top walkway, ladder, pipes, sight glass
        r, L, zc = 1.30, 3.0, 1.72
        htank(b, 0.0, 0.0, zc, r, L)
        saddles(b, 0.0, 0.0, zc, r, L)
        tank_walkway(b, -0.2, 0.0, zc + r - 0.02, 2.2)
        LVK.ladder(b, -0.2, -r - 0.18, 0.0, zc + r + 0.2, rot=90.0, w=0.42)
        b.vcyl(0.9, 0, zc + r - 0.1, zc + r + 0.18, 0.34, seg=12, mat="HullDark")
        b.tube([(-1.0, 0.45, zc + r - 0.05), (-1.0, 0.45, zc + r + 0.4), (-2.45, 0.45, zc + r + 0.4), (-2.45, 0.45, 0.10)],
               0.10, seg=8, mat="Metal", fillet=0.3)
        b.cyl((-2.45, 0.45, 0.9), (-2.45, 0.45, 1.2), 0.135, seg=8, mat="WaterBlue")
        b.tube([(2.2, 0, 0.9), (2.6, 0, 0.9), (2.6, 0, 0.10)], 0.11, seg=8, mat="Metal", fillet=0.2)
        b.cyl((2.3, 0, 0.9), (2.45, 0, 0.9), 0.15, seg=8, mat="WaterBlue")
        for (x, y) in ((2.6, 0.0), (-2.45, 0.45)):
            b.vcyl(x, y, 0.0, 0.10, 0.2, seg=8, mat="Frame")
        gx, gy = 2.3, -0.62
        b.vcyl(gx, gy, zc - 0.8, zc + 0.8, 0.07, seg=8, mat="Frame")
        b.vcyl(gx, gy, zc - 0.62, zc + 0.25, 0.09, seg=8, mat="WaterBlue", cap0=False, cap1=False)
        LV = dict(ring=R - 0.14, antenna=(0.9, 0.2, zc + r + 0.18, 1.0), band3=("xcyl", -1.1, 0.0, zc, r, 0.14),
                  modules=[(-1.8, -1.6, 0.0, 30.0, 0.7)], band4=("xcyl", 1.1, 0.0, zc, r, 0.14),
                  annex=[(1.1, 1.95, 0.0, 0.0, 0.7)],
                  crown=(0.9, 0.0, zc + r + 0.12, 0.42), beacon=(0.9, 0.0, zc + r + 0.18, 0.4),
                  emblem=((L / 2 + r * 0.55, 0.0, zc), (1, 0, 0), 0.18))
    elif k == 2:                                 # L: two tanks and a catwalk bridge
        r, L, zc = 1.15, 3.6, 1.55
        for cy in (-1.35, 1.35):
            htank(b, 0.0, cy, zc, r, L)
            saddles(b, 0.0, cy, zc, r, L)
        b.box0(0.0, 0.0, zc + r + 0.02, 0.9, 2.7, 0.06, "Frame")                   # bridge between the tanks
        LVK.railing(b, [(-0.4, -1.3, zc + r + 0.08), (-0.4, 1.3, zc + r + 0.08)], h=0.8, post_every=0.9)
        LVK.railing(b, [(0.4, -1.3, zc + r + 0.08), (0.4, 1.3, zc + r + 0.08)], h=0.8, post_every=0.9)
        for cy in (-1.35, 1.35):
            tank_walkway(b, 0.0, cy, zc + r - 0.02, 2.6, w=0.6)
        LVK.ladder(b, -1.3, 0.0, 0.0, zc + r + 0.1, rot=90.0, w=0.42)
        b.tube([(2.45, -1.35, 0.8), (2.95, -1.35, 0.8), (2.95, 1.35, 0.8), (2.45, 1.35, 0.8)], 0.11, seg=8, mat="Metal",
               fillet=0.2)
        b.tube([(2.95, 0.0, 0.8), (3.35, 0.0, 0.8), (3.35, 0.0, 0.1)], 0.12, seg=8, mat="Metal", fillet=0.2)
        b.cyl((2.95, -0.2, 0.8), (2.95, 0.2, 0.8), 0.16, seg=8, mat="WaterBlue")
        b.vcyl(3.35, 0.0, 0.0, 0.12, 0.24, seg=8, mat="Frame")
        LV = dict(ring=R - 0.14, antenna=(0.0, 0.0, zc + r + 0.08, 1.2), band3=("xcyl", -1.3, -1.35, zc, r, 0.14),
                  modules=[(-2.5, -2.4, 0.0, 30.0, 0.8)], band4=("xcyl", -1.3, 1.35, zc, r, 0.14),
                  annex=[(-2.55, 2.35, 0.0, -30.0, 0.8)],
                  crown=(0.0, 0.0, zc + r + 0.1, 0.62), beacon=(0.0, 0.3, zc + r + 0.1, 0.5),
                  emblem=((L / 2 + r * 0.5, -1.35, zc), (1, 0, 0), 0.18))
    else:                                        # XL: a sphere on legs, top platform, stair ladder, pump house
        rs, zc = 2.35, 3.25
        with b.at(T(0, 0, zc)):
            prof = []
            for j in range(9):
                a = radians(-90 + 180 * j / 8)
                prof.append((rs * cos(a), rs * sin(a)))
            prof[0], prof[-1] = (0.0, -rs), (0.0, rs)
            mats = ["Hull", "Hull", "Hull", "Accent", "WaterBlue", "Hull", "Hull", "Hull"]
            b.lathe(prof, lambda kk, i: mats[kk], seg=20)
            b.torus(rs + 0.02, 0.08, "Frame", seg=20, tseg=5, z=0.0)
        for i in range(6):                                                        # legs with cross braces
            a = radians(30 + 60 * i)
            top = Vector((rs * 0.98 * cos(a), rs * 0.98 * sin(a), zc))
            foot = Vector((rs * 1.04 * cos(a), rs * 1.04 * sin(a), 0.0))
            b.beam(foot, top, 0.22, 0.22, "Frame")
            b.box0(foot.x, foot.y, 0.0, 0.55, 0.55, 0.12, "HullDark")
            a2 = radians(30 + 60 * (i + 1))
            foot2 = Vector((rs * 1.04 * cos(a2), rs * 1.04 * sin(a2), 0.0))
            b.beam(foot + Vector((0, 0, 0.3)), foot2.lerp(top, 0.0) + Vector((0, 0, 1.6)), 0.07, 0.07, "Frame")
        b.vcyl(0, 0, zc + rs - 0.12, zc + rs + 0.10, 0.9, seg=16, mat="Frame")       # top platform + railing
        for i in range(8):
            x, y, _ = polar(0.85, 45 * i)
            b.beam((x, y, zc + rs + 0.1), (x, y, zc + rs + 0.95), 0.04, 0.04, "Frame")
        b.lathe([(0.87, zc + rs + 0.9), (0.87, zc + rs + 0.96), (0.82, zc + rs + 0.96), (0.82, zc + rs + 0.9)], "Hazard",
                seg=16, smooth=False)
        LVK.ladder(b, 0.0, -rs - 0.35, 0.0, zc + rs * 0.2, rot=90.0, w=0.44)
        b.tube([(0.0, -rs - 0.35, zc + rs * 0.2), (0.0, -1.3, zc + rs * 0.75), (0.0, -0.9, zc + rs + 0.1)], 0.04, seg=4,
               mat="Hazard", fillet=0.3)
        LVK.kiosk(b, 3.2, 2.05, rot=90.0, w=1.0, d=0.8, h=1.2)                    # pump house
        b.tube([(0.0, 0.0, zc - rs + 0.1), (0.0, 0.0, 0.6), (2.0, 1.4, 0.6), (2.75, 2.05, 0.6)], 0.14, seg=8, mat="Metal",
               fillet=0.4)
        b.cyl((1.2, 0.84, 0.6), (1.45, 1.02, 0.6), 0.2, seg=8, mat="WaterBlue")
        b.vcyl(-3.4, -1.4, 0.0, 2.6, 0.09, seg=8, mat="Frame")                    # level gauge post
        b.vcyl(-3.4, -1.4, 0.6, 2.2, 0.11, seg=8, mat="WaterBlue", cap0=False, cap1=False)
        LV = dict(ring=R - 0.14, antenna=(0.45, 0.45, zc + rs + 0.1, 1.3), band3=("cyl", 0, 0, zc - rs * 0.55, rs * 0.83, 0.2),
                  modules=[(-3.3, 1.6, 0.0, -30.0, 0.9)], band4=("cyl", 0, 0, zc + rs * 0.42, rs * 0.9, 0.2),
                  annex=[(2.6, -2.9, 0.0, 40.0, 0.85)],
                  crown=(0, 0, zc + rs * 0.83, rs * 0.55), beacon=(-0.4, 0.3, zc + rs + 0.1, 0.55),
                  emblem=((3.2 + 0.41, 2.05, 0.75), (1, 0, 0), 0.18))
    return [b] + LVK.add_levels([b], LV)


# ======================================================================================
BUDGET = (3000, 4500, 6500, 9000)
MODELS = []
for bid, fn in (("water_extractor", build_extractor), ("reservoir", build_reservoir)):
    for k, sz in enumerate(SIZES):
        MODELS.append(dict(id="%s_%s" % (bid, sz), kind="exterior", footprint=radius(bid, k), accent="life_support",
                           budget=BUDGET[k], objects=["Base", "L2", "L3", "L4", "L5"], size=k,
                           also=[bid] if k == 1 else [], ao=dict(dist=0.6 + 0.2 * k, samples=32), builder=fn))


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
