"""
Frontier Habitat 2.0 - industry exteriors: regolith_harvester, fuel_refinery (sizes S, M, L, XL).

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_industry.py -- [--only fuel_refinery_l,regolith_harvester]

Output: assets/models/<id>_s|m|l|xl.glb and <id>.glb (= size M, the v1 name). Objects Base, L2, L3, L4, L5.
Accent = industry orange. The regolith load uses OreVein (sand colour); the flare flame uses Neon.
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
# REGOLITH HARVESTER parts
# ======================================================================================
def track(p, x, y, L, h, w):
    """crawler track: stadium side profile in XZ, road wheels and grousers on the outer side"""
    r = h / 2
    pts = []
    for i in range(5):
        a = radians(-90 + 45 * i)
        pts.append((x + L / 2 - r + r * cos(a), r + r * sin(a)))
    for i in range(5):
        a = radians(90 + 45 * i)
        pts.append((x - L / 2 + r + r * cos(a), r + r * sin(a)))
    p.prism_y(pts, y - w / 2, y + w / 2, "Rubber")
    side = 1 if y > 0 else -1
    yo = y + side * (w / 2 + 0.005)
    p.prism_y([(x - L / 2 + r, r * 0.35), (x + L / 2 - r, r * 0.35), (x + L / 2 - r * 0.7, r), (x + L / 2 - r, r * 1.65),
               (x - L / 2 + r, r * 1.65), (x - L / 2 + r * 0.7, r)], min(yo, yo + side * 0.03), max(yo, yo + side * 0.03),
              "Frame")
    n = max(3, int(L / 0.55))
    for i in range(n):
        xw = x - L / 2 + r + (L - 2 * r) * i / (n - 1)
        p.cyl((xw, yo, r), (xw, yo + side * 0.06, r), r * 0.42, seg=8, mat="Metal")
    ng = int(L / 0.3)
    for i in range(ng):
        xg = x - L / 2 + r + (L - 2 * r) * (i + 0.5) / ng
        p.box((xg, y, h + 0.012), (0.07, w, 0.03), "Frame", mats={"-z": None})


def body(p, x, y, L, W, z0, h, cab_x, cab=True):
    """chassis + upper body + engine deck + cab + sensor turret + exhaust"""
    p.box0(x, y, z0, L, W, 0.22, "HullDark")
    p.box0(x, y, z0 + 0.22, L * 0.92, W * 0.92, h, "Hull", bevel=0.06)
    p.box((x, y, z0 + 0.22 + h * 0.55), (L * 0.92 + 0.02, W * 0.92 + 0.02, h * 0.16), "Accent", mats={"+z": None, "-z": None})
    zt = z0 + 0.22 + h
    p.box0(x - L * 0.2, y, zt, L * 0.42, W * 0.7, 0.18, "HullDark", bevel=0.03)               # engine deck
    for i in range(5):
        p.box0(x - L * 0.2 - L * 0.16 + L * 0.08 * i, y, zt + 0.18, 0.04, W * 0.6, 0.04, "Frame")
    p.vcyl(x - L * 0.36, y + W * 0.28, zt, zt + 0.75, 0.07, seg=6, mat="Metal")                # exhaust
    p.vcyl(x - L * 0.36, y + W * 0.28, zt + 0.62, zt + 0.78, 0.09, seg=6, mat="Frame")
    if cab:
        cw = W * 0.55
        p.box0(cab_x, y - W * 0.2, zt, 0.75, cw, 0.62, "Hull", bevel=0.05)
        p.box((cab_x + 0.38, y - W * 0.2, zt + 0.40), (0.02, cw * 0.8, 0.26), "Window", mats={"-x": None})
        p.box((cab_x, y - W * 0.2 - cw / 2 - 0.006, zt + 0.40), (0.55, 0.012, 0.22), "Window", mats={"+y": None})
        p.box0(cab_x, y - W * 0.2, zt + 0.62, 0.82, cw + 0.06, 0.05, "Frame")
        p.vcyl(cab_x - 0.15, y - W * 0.2, zt + 0.67, zt + 0.95, 0.14, seg=10, mat="HullDark")     # sensor turret
        p.vcyl(cab_x - 0.15, y - W * 0.2, zt + 0.95, zt + 1.0, 0.17, seg=10, mat="Accent")
        return (cab_x - 0.15, y - W * 0.2, zt + 1.0, zt)
    return (x, y, zt, zt)


def bucket(p, x, y, z, w, s=1.0, teeth=5):
    """front loader bucket opening to +X (profile in XZ, extruded along Y)"""
    prof = [(0.0, 0.0), (0.55 * s, 0.0), (0.62 * s, 0.06 * s), (0.08 * s, 0.10 * s), (-0.05 * s, 0.55 * s),
            (0.05 * s, 0.62 * s), (-0.14 * s, 0.62 * s), (-0.18 * s, 0.1 * s)]
    with p.at(T(x, 0, z)):
        p.prism_y(prof, y - w / 2, y + w / 2, "Accent", cap_mat="HullDark")
        for i in range(teeth):
            yt = y - w / 2 + w * (i + 0.5) / teeth
            p.box((0.64 * s, yt, 0.03 * s), (0.10 * s, 0.07 * s, 0.05 * s), "Metal")
        p.box((0.25 * s, y, 0.14 * s), (0.4 * s, w * 0.9, 0.06 * s), "OreVein")


def conveyor(p, a, b, w=0.5, load=True):
    """inclined belt conveyor from a (low) to b (high): truss rails, belt, legs, rollers"""
    a, b = Vector(a), Vector(b)
    d = (b - a)
    L = d.length
    u = d.normalized()
    side = Vector((-u.y, u.x, 0.0)).normalized()
    for s_ in (-1, 1):
        o = side * (w / 2) * s_
        p.beam(a + o, b + o, 0.08, 0.12, "Frame")
        p.beam(a + o - Vector((0, 0, 0.25)), b + o - Vector((0, 0, 0.25)), 0.05, 0.05, "Frame")
        n = max(2, int(L / 0.7))
        for i in range(n + 1):
            q = a.lerp(b, i / n) + o
            p.beam(q, q - Vector((0, 0, 0.25)), 0.04, 0.04, "Frame")
            if i < n:
                q2 = a.lerp(b, (i + 1) / n) + o - Vector((0, 0, 0.25))
                p.beam(q, q2, 0.035, 0.035, "Metal")
    p.beam(a + Vector((0, 0, 0.05)), b + Vector((0, 0, 0.05)), w * 0.9, 0.04, "Rubber")
    if load:
        n = int(L / 0.35)
        for i in range(1, n):
            q = a.lerp(b, i / n) + Vector((0, 0, 0.1))
            p.box(tuple(q), (0.16, w * 0.5, 0.08), "OreVein")
    mid = a.lerp(b, 0.55)
    if mid.z > 0.9:                                  # support legs under the middle
        for s_ in (-1, 1):
            q = mid + side * (w / 2 + 0.02) * s_
            p.beam(Vector((q.x, q.y, 0.0)), q - Vector((0, 0, 0.2)), 0.07, 0.07, "Frame")


def hopper(p, x, y, top_z, w, h=1.1, legs=True, pile=True):
    """square hopper bin on legs, sand heaped inside"""
    zb = top_z - h
    rings = [[(x + sx * w * 0.22, y + sy * w * 0.22, zb) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))],
             [(x + sx * w * 0.5, y + sy * w * 0.5, top_z - h * 0.35) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))],
             [(x + sx * w * 0.5, y + sy * w * 0.5, top_z) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]]
    p.loft(rings, lambda k, i: "Accent" if k == 1 else "HullDark", smooth=False, closed=True, cap0=True, cap_mat="Frame")
    p.box((x, y, top_z + 0.04), (w + 0.08, w + 0.08, 0.08), "Frame", mats={"-z": None})
    if pile:
        p.convex([(x - w * 0.46, y - w * 0.46, top_z - 0.05), (x + w * 0.46, y - w * 0.46, top_z - 0.05),
                  (x + w * 0.46, y + w * 0.46, top_z - 0.05), (x - w * 0.46, y + w * 0.46, top_z - 0.05),
                  (x + 0.05, y, top_z + w * 0.28)], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], "OreVein")
    if legs:
        for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1)):
            p.beam((x + sx * w * 0.42, y + sy * w * 0.42, 0.0), (x + sx * w * 0.42, y + sy * w * 0.42, top_z - h * 0.35), 0.1,
                   0.1, "Frame")
            p.box0(x + sx * w * 0.42, y + sy * w * 0.42, 0.0, 0.26, 0.26, 0.06, "HullDark")
        p.vcyl(x, y, zb - 0.35, zb, 0.12, seg=8, mat="Metal")
        p.box0(x, y, zb - 0.55, 0.34, 0.34, 0.2, "Frame")


def bucket_wheel(p, cx, cy, cz, R, w=0.34, n=8):
    """bucket wheel in the XZ plane (axis along Y)"""
    with p.at(T(cx, cy, cz), RX(90.0)):
        p.lathe([(R, -w / 2), (R, w / 2), (R - 0.14, w / 2), (R - 0.14, -w / 2)], "Accent", seg=20, smooth=False, wrap=True)
        p.cyl((0, 0, -w / 2 - 0.05), (0, 0, w / 2 + 0.05), 0.20, seg=10, mat="Frame")
        for i in range(6):
            a = radians(60 * i)
            p.beam((0.18 * cos(a), 0.18 * sin(a), 0), ((R - 0.12) * cos(a), (R - 0.12) * sin(a), 0), 0.07, 0.07, "Frame")
        for i in range(n):
            a = radians(360.0 * i / n)
            c = Vector(((R + 0.08) * cos(a), (R + 0.08) * sin(a), 0))
            with p.at(T(*c), RZ(degrees(a) + 90.0)):
                p.box((0, 0.02, 0), (0.30, 0.20, w + 0.06), "Metal", mats={"-y": "HullDark"})
                p.box((0.16, 0.08, 0), (0.05, 0.08, w + 0.04), "Frame")


def degrees(a):
    return a * 180.0 / pi


# ======================================================================================
def build_harvester(spec):
    k = spec["size"]
    R = radius("regolith_harvester", k)
    b = Part("Base")
    if k == 0:                                   # S: compact crawler with a front bucket and a small bin
        for y in (-0.55, 0.55):
            track(b, 0.0, y, 1.9, 0.5, 0.34)
        tur = body(b, -0.05, 0.0, 1.5, 1.1, 0.42, 0.55, 0.35)
        for y in (-0.42, 0.42):
            b.beam((0.55, y, 0.85), (1.2, y, 0.42), 0.08, 0.10, "Frame")
        b.cyl((0.6, -0.3, 0.75), (1.0, -0.3, 0.5), 0.05, seg=6, mat="Metal")
        bucket(b, 1.15, 0.0, 0.05, 1.2, s=0.85)
        b.box0(-0.45, 0.25, tur[3], 0.55, 0.5, 0.35, "Accent")
        b.box0(-0.45, 0.25, tur[3] + 0.35, 0.5, 0.45, 0.06, "OreVein")
        LV = dict(ring=R - 0.14, antenna=(tur[0] - 0.12, tur[1] + 0.1, tur[2], 0.8),
                  band3=("box", -0.45, 0.25, tur[3] + 0.08, 0.55, 0.5, 0.07), modules=[(-1.4, -0.9, 0.0, 30.0, 0.55)],
                  band4=("box", -0.45, 0.25, tur[3] + 0.20, 0.55, 0.5, 0.07), annex=[(-1.35, 0.95, 0.0, -30.0, 0.5)],
                  crown=(tur[0], tur[1], tur[2] - 0.2, 0.2), beacon=(tur[0], tur[1], tur[2], 0.3),
                  emblem=((-0.05, -0.51, 0.9), (0, -1, 0), 0.12))
    elif k == 1:                                 # M: crawler + bucket + conveyor to a hopper
        for y in (-0.62, 0.62):
            track(b, 0.55, y, 2.2, 0.55, 0.38)
        tur = body(b, 0.5, 0.0, 1.8, 1.25, 0.45, 0.6, 1.0)
        for y in (-0.48, 0.48):
            b.beam((1.3, y, 0.95), (2.0, y, 0.45), 0.09, 0.11, "Frame")
        bucket(b, 1.95, 0.0, 0.05, 1.3, s=0.95)
        conveyor(b, (1.1, 0.0, 1.35), (-1.6, 0.0, 2.55), w=0.45)
        hopper(b, -2.05, 0.0, 2.55, 1.2, h=1.0)
        LV = dict(ring=R - 0.14, antenna=(tur[0] - 0.12, tur[1] + 0.1, tur[2], 0.9),
                  band3=("box", -2.05, 0.0, 2.1, 1.12, 1.12, 0.08), modules=[(0.6, -1.9, 0.0, 0.0, 0.7)],
                  band4=("box", -2.05, 0.0, 1.95, 1.12, 1.12, 0.08), annex=[(0.6, 1.95, 0.0, 0.0, 0.66)],
                  crown=(tur[0], tur[1], tur[2] - 0.2, 0.22), beacon=(tur[0], tur[1], tur[2], 0.35),
                  emblem=((0.5, -0.585, 1.1), (0, -1, 0), 0.14))
    elif k == 2:                                 # L: bucket-wheel excavator, conveyor, hopper
        for y in (-0.8, 0.8):
            track(b, 0.0, y, 2.6, 0.62, 0.45)
        tur = body(b, 0.0, 0.0, 2.2, 1.6, 0.5, 0.75, 0.45)
        for y in (-0.3, 0.3):                                             # boom
            b.beam((0.9, y, 1.2), (2.5, y, 1.75), 0.14, 0.18, "Frame")
        b.beam((0.3, 0.0, 2.1), (2.4, 0.0, 1.95), 0.08, 0.08, "Metal")
        b.beam((0.3, 0.0, 1.35), (0.3, 0.0, 2.15), 0.14, 0.14, "Frame")
        bucket_wheel(b, 2.55, 0.0, 1.75, 0.95)
        conveyor(b, (1.8, 0.0, 1.55), (-2.1, 0.0, 2.6), w=0.5)
        hopper(b, -2.55, 0.0, 2.6, 1.4, h=1.1)
        LV = dict(ring=R - 0.14, antenna=(tur[0] - 0.12, tur[1] + 0.1, tur[2], 1.0),
                  band3=("box", -2.55, 0.0, 2.15, 1.32, 1.32, 0.09), modules=[(-0.4, -2.5, 0.0, 0.0, 0.75)],
                  band4=("box", -2.55, 0.0, 1.98, 1.32, 1.32, 0.09), annex=[(-0.4, 2.55, 0.0, 0.0, 0.72)],
                  crown=(tur[0], tur[1], tur[2] - 0.2, 0.22), beacon=(tur[0], tur[1], tur[2], 0.4),
                  emblem=((0.0, -0.745, 1.15), (0, -1, 0), 0.16))
    else:                                        # XL: big bucket wheel, silo, stacker, sand pile
        for y in (-0.95, 0.95):
            track(b, 0.3, y, 3.0, 0.7, 0.5)
        tur = body(b, 0.3, 0.0, 2.6, 1.9, 0.56, 0.85, 0.75)
        for y in (-0.35, 0.35):
            b.beam((1.3, y, 1.35), (3.0, y, 2.0), 0.16, 0.2, "Frame")
        b.beam((0.5, 0.0, 2.45), (2.9, 0.0, 2.25), 0.09, 0.09, "Metal")
        b.beam((0.5, 0.0, 1.5), (0.5, 0.0, 2.5), 0.16, 0.16, "Frame")
        bucket_wheel(b, 3.15, 0.0, 2.0, 1.2, w=0.4, n=10)
        # silo on legs with a conical bottom
        sx, sy, sr = -2.75, -1.35, 0.95
        b.vcyl(sx, sy, 2.1, 3.9, sr, seg=14, mat="Hull", cap0=False)
        b.vcyl(sx, sy, 3.1, 3.35, sr + 0.02, seg=14, mat="Accent", cap0=False, cap1=False)
        with b.at(T(sx, sy, 2.1)):
            b.lathe([(0.18, -0.9), (sr, 0.0)], "HullDark", seg=14, smooth=False)
        for i in range(4):
            a = radians(45 + 90 * i)
            b.beam((sx + sr * 0.8 * cos(a), sy + sr * 0.8 * sin(a), 0.0), (sx + sr * 0.9 * cos(a), sy + sr * 0.9 * sin(a), 2.4),
                   0.12, 0.12, "Frame")
        b.vcyl(sx, sy, 3.9, 4.0, sr + 0.06, seg=14, mat="Frame")
        conveyor(b, (-0.6, -0.3, 1.8), (-2.35, -1.2, 3.9), w=0.5)
        conveyor(b, (-2.7, -0.3, 1.2), (-2.5, 1.9, 0.6), w=0.45, load=False)          # stacker to the pile
        b.convex([(-3.6, 1.4, -0.02), (-1.5, 1.35, -0.02), (-1.6, 3.05, -0.02), (-3.3, 3.2, -0.02), (-2.55, 2.2, 1.05),
                  (-2.2, 2.6, 0.7)], [(0, 1, 4), (1, 2, 5), (1, 5, 4), (2, 3, 4), (2, 4, 5), (3, 0, 4)], "OreVein")
        LV = dict(ring=R - 0.14, antenna=(tur[0] - 0.12, tur[1] + 0.1, tur[2], 1.1),
                  band3=("cyl", sx, sy, 2.5, sr, 0.14), modules=[(0.9, -2.75, 0.0, 0.0, 0.8)],
                  band4=("cyl", sx, sy, 2.8, sr, 0.14), annex=[(0.8, 2.8, 0.0, 0.0, 0.78)],
                  crown=(sx, sy, 4.0, sr - 0.1), beacon=(sx, sy, 4.0, 0.5),
                  emblem=((0.3, -0.875, 1.25), (0, -1, 0), 0.18))
    return [b] + LVK.add_levels([b], LV)


# ======================================================================================
# FUEL REFINERY parts
# ======================================================================================
def sphere_tank(p, x, y, r, zc, legs=4):
    with p.at(T(x, y, zc)):
        prof = []
        for j in range(9):
            a = radians(-90 + 180 * j / 8)
            prof.append((r * cos(a), r * sin(a)))
        prof[0], prof[-1] = (0.0, -r), (0.0, r)
        mats = ["Hull", "Hull", "Hull", "Accent", "Hazard", "Hull", "Hull", "Hull"]
        p.lathe(prof, lambda k, i: mats[k] if not (k == 4 and i % 2) else "Frame", seg=16)
        p.torus(r + 0.015, 0.05, "Frame", seg=16, tseg=4, z=0.0)
        p.vcyl(0, 0, r - 0.05, r + 0.18, 0.12, seg=8, mat="Frame")
        p.cyl((0, 0, r + 0.12), (0.3, 0, r + 0.12), 0.05, seg=6, mat="Metal")
    for i in range(legs):
        a = radians(45 + 360.0 * i / legs)
        top = Vector((x + r * 0.95 * cos(a), y + r * 0.95 * sin(a), zc))
        foot = Vector((x + r * 1.02 * cos(a), y + r * 1.02 * sin(a), 0.0))
        p.beam(foot, top, 0.12, 0.12, "Frame")
        p.box0(foot.x, foot.y, 0.0, 0.3, 0.3, 0.08, "HullDark")


def column(p, x, y, r, h, platforms=2):
    """cracking column with hazard stripes, platforms, ladder and a gooseneck vent"""
    with p.at(T(x, y, 0)):
        p.vcyl(0, 0, 0.0, 0.25, r + 0.18, seg=12, mat="Frame")
        stripes = []
        z = 0.25
        prof = [(r, 0.25)]
        mats = []
        for (z0, z1, m) in ((0.25, 0.85, "Hull"), (0.85, 1.25, "HAZ"), (1.25, h * 0.55, "Metal"), (h * 0.55, h * 0.6, "Accent"),
                            (h * 0.6, h - 0.8, "Hull"), (h - 0.8, h - 0.35, "HAZ"), (h - 0.35, h, "Frame")):
            prof.append((r, z1))
            mats.append(m)
        p.lathe(prof, lambda k, i: ("Hazard" if i % 2 == 0 else "Frame") if mats[k] == "HAZ" else mats[k], seg=12)
        with p.at(T(0, 0, h)):
            p.lathe(dome_profile(r, 0.0, r * 0.5, 3), "Hull", seg=12)
        p.tube([(0, 0, h + r * 0.45), (0, 0, h + r * 0.45 + 0.35), (0.35, 0, h + r * 0.45 + 0.55), (0.55, 0, h + 0.2)],
               0.06, seg=6, mat="Metal", fillet=0.12)
        for pz in [h * (0.35 + 0.3 * q) for q in range(platforms)]:
            rp = r + 0.5
            p.lathe([(rp, pz - 0.06), (rp, pz), (r, pz), (r, pz - 0.06)], "Frame", seg=12, smooth=False, a0=-120, a1=120,
                    caps=True)
            for q in range(6):
                a = radians(-110 + 44 * q)
                p.beam((rp * cos(a), rp * sin(a), pz), (rp * cos(a), rp * sin(a), pz + 0.8), 0.035, 0.035, "Frame")
            p.lathe([(rp, pz + 0.76), (rp, pz + 0.81), (rp - 0.04, pz + 0.81), (rp - 0.04, pz + 0.76)], "Hazard", seg=12,
                    smooth=False, a0=-120, a1=120, caps=True)
    LVK.ladder(p, x - r - 0.14, y, 0.0, h, rot=0.0, w=0.36)


def flare(p, x, y, h):
    """flare stack: guyed pipe, wind shield and a small flame (Neon, industry colour)"""
    p.vcyl(x, y, 0.0, 0.18, 0.35, seg=8, mat="Frame")
    p.vcyl(x, y, 0.18, h, 0.13, 0.10, seg=8, mat="Metal", cap1=False)
    p.vcyl(x, y, h * 0.5, h * 0.5 + 0.1, 0.16, seg=8, mat="Accent")
    p.vcyl(x, y, h - 0.25, h, 0.16, seg=8, mat="Frame", cap1=False)
    p.cyl((x, y, h - 0.02), (x, y, h + 0.45), 0.12, 0.0, seg=6, mat="Neon", cap1=False)
    for i in range(3):
        a = radians(90 + 120 * i)
        p.beam((x, y, h * 0.7), (x + 0.9 * cos(a), y + 0.9 * sin(a), 0.0), 0.02, 0.02, "Metal")


def pipe_rack(p, a, b, h=1.6, pipes=3):
    a, b = Vector(a), Vector(b)
    d = (b - a)
    L = d.length
    u = d.normalized()
    side = Vector((-u.y, u.x, 0.0))
    n = max(2, int(L / 1.2) + 1)
    for i in range(n):
        q = a.lerp(b, i / (n - 1))
        for s_ in (-1, 1):
            p.beam(q + side * 0.35 * s_, q + side * 0.35 * s_ + Vector((0, 0, h)), 0.09, 0.09, "Frame")
        p.beam(q - side * 0.4 + Vector((0, 0, h)), q + side * 0.4 + Vector((0, 0, h)), 0.09, 0.09, "Frame")
    for j in range(pipes):
        off = side * (-0.25 + 0.25 * j) + Vector((0, 0, h + 0.1))
        p.cyl(a + off, b + off, 0.07, seg=6, mat="Accent" if j == 1 else "Metal", cap0=True, cap1=True)


def build_refinery(spec):
    k = spec["size"]
    R = radius("fuel_refinery", k)
    b = Part("Base")
    if k == 0:                                   # S: one sphere + short column + kiosk
        sphere_tank(b, -0.75, 0.55, 0.92, 1.25)
        column(b, 0.85, -0.55, 0.30, 4.0, platforms=1)
        LVK.kiosk(b, 1.05, 1.15, rot=0.0, w=0.55, d=0.5, h=0.85)
        b.tube([(0.85, -0.55, 0.7), (0.0, -0.1, 0.7), (-0.4, 0.2, 0.7)], 0.07, seg=6, mat="Metal", fillet=0.2)
        cx, cy, ch, cr = 0.85, -0.55, 4.0, 0.30
        LV = dict(ring=R - 0.14, antenna=(1.0, 1.15, 0.1 + 0.85 + 0.06, 0.8), band3=("cyl", cx, cy, 1.5, cr, 0.14),
                  modules=[(-1.55, -0.9, 0.0, 30.0, 0.55)], band4=("cyl", cx, cy, 1.85, cr, 0.14),
                  annex=[(0.1, -1.9, 0.0, 0.0, 0.5)],
                  crown=(cx, cy, ch - 0.3, cr + 0.02), beacon=(cx, cy, ch + cr * 0.5, 0.35),
                  emblem=((1.05 + 0.285, 1.15, 0.5), (1, 0, 0), 0.12))
    elif k == 1:                                 # M: two spheres, tall column, pipe rack
        for yy in (-1.25, 1.25):
            sphere_tank(b, -1.3, yy, 1.02, 1.35)
        column(b, 1.2, 0.0, 0.36, 5.8, platforms=2)
        pipe_rack(b, (-1.3, 0.0, 0.0), (0.7, 0.0, 0.0), h=1.5)
        LVK.kiosk(b, 1.45, -1.9, rot=0.0, w=0.62, d=0.55, h=0.95)
        cx, cy, ch, cr = 1.2, 0.0, 5.8, 0.36
        LV = dict(ring=R - 0.14, antenna=(1.4, -1.9, 0.1 + 0.95 + 0.06, 0.9), band3=("cyl", cx, cy, 2.1, cr, 0.16),
                  modules=[(1.4, 1.95, 0.0, 0.0, 0.7)], band4=("cyl", cx, cy, 2.45, cr, 0.16),
                  annex=[(-2.75, 0.0, 0.0, 90.0, 0.65)],
                  crown=(cx, cy, ch - 0.32, cr + 0.02), beacon=(cx, cy, ch + cr * 0.5, 0.4),
                  emblem=((1.45 + 0.32, -1.9, 0.55), (1, 0, 0), 0.14))
    elif k == 2:                                 # L: three spheres, column, flare stack
        for (x, y) in ((-1.85, -1.55), (-1.85, 0.9), (0.3, -2.25)):
            sphere_tank(b, x, y, 1.0, 1.3)
        column(b, 1.3, 0.2, 0.40, 6.8, platforms=2)
        flare(b, -0.4, 2.85, 6.0)
        pipe_rack(b, (-1.85, -0.4, 0.0), (0.8, -0.4, 0.0), h=1.6)
        LVK.kiosk(b, 2.55, -1.6, rot=0.0, w=0.7, d=0.6, h=1.05)
        cx, cy, ch, cr = 1.3, 0.2, 6.8, 0.40
        LV = dict(ring=R - 0.14, antenna=(2.5, -1.6, 0.1 + 1.05 + 0.06, 1.0), band3=("cyl", cx, cy, 2.3, cr, 0.18),
                  modules=[(1.9, 2.6, 0.0, 0.0, 0.78)], band4=("cyl", cx, cy, 2.7, cr, 0.18),
                  annex=[(-3.3, -0.35, 0.0, 90.0, 0.72)],
                  crown=(cx, cy, ch - 0.34, cr + 0.02), beacon=(cx, cy, ch + cr * 0.5, 0.45),
                  emblem=((2.55 + 0.36, -1.6, 0.6), (1, 0, 0), 0.16))
    else:                                        # XL: four spheres, two columns, flare, racks
        for (x, y) in ((-2.45, -1.75), (-2.45, 0.75), (-0.2, -2.9), (-0.2, 2.35)):
            sphere_tank(b, x, y, 1.05, 1.35)
        column(b, 1.55, -0.6, 0.44, 7.8, platforms=3)
        column(b, 1.9, 1.35, 0.34, 6.2, platforms=2)
        flare(b, -2.6, 3.6, 7.0)
        pipe_rack(b, (-2.45, -0.5, 0.0), (1.0, -0.5, 0.0), h=1.7, pipes=4)
        pipe_rack(b, (0.6, -0.5, 0.0), (0.6, 1.4, 0.0), h=1.7, pipes=2)
        LVK.kiosk(b, 3.35, -2.3, rot=0.0, w=0.8, d=0.7, h=1.15)
        cx, cy, ch, cr = 1.55, -0.6, 7.8, 0.44
        LV = dict(ring=R - 0.14, antenna=(3.3, -2.3, 0.1 + 1.15 + 0.06, 1.1), band3=("cyl", cx, cy, 2.5, cr, 0.2),
                  modules=[(3.5, 0.3, 0.0, 90.0, 0.85)], band4=("cyl", cx, cy, 2.95, cr, 0.2),
                  annex=[(-4.2, -0.5, 0.0, 90.0, 0.8)],
                  crown=(cx, cy, ch - 0.36, cr + 0.02), beacon=(cx, cy, ch + cr * 0.5, 0.5),
                  emblem=((3.35 + 0.41, -2.3, 0.65), (1, 0, 0), 0.17))
    return [b] + LVK.add_levels([b], LV)


# ======================================================================================
BUDGET = (3000, 4500, 6500, 9000)
MODELS = []
for bid, fn in (("regolith_harvester", build_harvester), ("fuel_refinery", build_refinery)):
    for k, sz in enumerate(SIZES):
        MODELS.append(dict(id="%s_%s" % (bid, sz), kind="exterior", footprint=radius(bid, k), accent="industry",
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
