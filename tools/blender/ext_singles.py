"""
Frontier Habitat 2.0 - single-size exteriors: fusion_reactor, deep_drill, comms_tower, lander, landing_pad.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_singles.py -- [--only fusion_reactor,lander]

Output: assets/models/<id>.glb.
  fusion_reactor  Base, Plasma (glowing core and ring, emissive; the game may hide it when the reactor is off),
                  L2..L5. Accent = utilities.
  deep_drill      Base, Lights (work-light lenses), L2..L5. 14 m derrick. Produce = exotic crystal colour.
  comms_tower     Base, Lights (beacons: top and three mid lamps). 22 m lattice mast + 2 m top pole.
  lander          Base, Lights (window panes, landing lights), empties Anchor_Ramp (ramp foot, +X) and
                  Anchor_Engine (bell exit). Legs overhang the 5.5 m footprint by at most 1 m.
  landing_pad     Base, Lights (edge lights, floodlight faces).
"""
import os
import sys
import random
from math import sin, cos, pi, radians, sqrt, atan2, degrees

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402
from ext_common import Part, Anchor, T, RX, RY, RZ, S, polar, dome_profile   # noqa: E402
import ext_levels as LVK                                   # noqa: E402
from mathutils import Vector                               # noqa: E402

BLD = C.load_content("buildings.json")
ITEMS = C.load_content("items.json")["items"]


# ======================================================================================
# FUSION REACTOR
# ======================================================================================
def d_coil(p, R0, zc, hh, hw, inner, mat, thick=0.30, width=0.34):
    """a D-shaped magnet coil in the local XZ plane round the torus tube centred at (R0, zc)"""
    pts = [Vector((R0 - inner, 0, zc - hh * 0.8)), Vector((R0 - inner, 0, zc + hh * 0.8))]
    for k in range(1, 8):
        a = radians(90 - 180 * k / 8)
        pts.append(Vector((R0 - inner + 0.15 + (hw + inner - 0.15) * cos(a), 0, zc + hh * sin(a))))
    pts.append(Vector((R0 - inner, 0, zc - hh * 0.8)))
    p.beam_path(pts, width, thick, mat, up=(0, 1, 0))


def build_fusion(spec):
    b, pl = Part("Base"), Part("Plasma")
    Z0 = 0.46
    zc = Z0 + 2.25
    # two-step round foundation with a painted edge
    b.lathe([(4.7, -0.05), (4.7, 0.20), (4.55, 0.26), (3.55, 0.26), (3.55, 0.40), (3.45, Z0), (0.0, Z0)],
            lambda k, i: ("Frame", "Hazard" if i % 2 == 0 else "Frame", "HullDark", "Frame", "Frame", "HullDark")[k], seg=32,
            smooth=False)
    # core: pedestal, glass shell, glowing plasma ball (separate object)
    b.lathe([(1.05, Z0), (1.05, Z0 + 0.35), (0.80, Z0 + 0.5), (0.62, zc - 1.05), (0.0, zc - 1.05)],
            lambda k, i: ("Frame", "HullDark", "Accent", "Frame")[k], seg=16)
    b.sphere((0, 0, zc), 1.18, "Glass", seg=20, rings=10)
    b.torus(1.19, 0.06, "Trim", seg=20, tseg=4, z=zc)
    b.vcyl(0, 0, zc + 1.12, zc + 1.32, 0.34, seg=12, mat="Frame")
    b.vcyl(0, 0, zc + 1.32, zc + 1.42, 0.24, seg=12, mat="Accent")
    pl.sphere((0, 0, zc), 0.80, "Plasma", seg=16, rings=8)
    # coil torus
    R0 = 2.45
    b.torus(R0, 0.52, "Glass", seg=36, tseg=10, z=zc)
    pl.torus(R0, 0.16, "Plasma", seg=36, tseg=6, z=zc)
    for dz in (-0.58, 0.58):
        b.torus(R0, 0.07, "Trim", seg=36, tseg=4, z=zc + dz)
    for i in range(12):
        with b.at(RZ(30.0 * i + 15.0)):
            d_coil(b, R0, zc, 0.95, 0.80, 0.70, "Accent" if i % 2 == 0 else "Frame")
            if i % 2 == 0:                                       # support leg under every other coil
                b.beam((R0 + 0.2, 0, Z0), (R0 + 0.1, 0, zc - 0.95), 0.2, 0.2, "Frame")
                b.box0(R0 + 0.2, 0, Z0, 0.5, 0.5, 0.1, "HullDark")
    # spokes from the torus to the core pedestal
    for i in range(4):
        with b.at(RZ(45.0 + 90.0 * i)):
            b.beam((0.7, 0, zc - 1.0), (R0 - 0.6, 0, zc - 0.3), 0.14, 0.14, "Frame")
            b.tube([(R0 + 0.6, 0.0, zc - 0.7), (R0 + 1.1, 0.0, Z0 + 0.35), (R0 + 1.6, 0.0, Z0 + 0.35)], 0.09, seg=6,
                   mat="Metal", fillet=0.25)
    # two radiator wings on +Y and -Y
    for sy in (-1, 1):
        y0 = sy * 4.35
        b.box0(0, y0, 0.0, 5.6, 0.5, 0.35, "Frame")
        for x in (-2.4, 0.0, 2.4):
            b.beam((x, y0 - sy * 0.15, 0.3), (x, y0 + sy * 0.55, 3.2), 0.12, 0.12, "Frame")
            b.beam((x, y0 + sy * 0.2, 0.3), (x, y0 + sy * 0.55, 3.2), 0.08, 0.08, "Metal")
        with b.at(T(0, y0 + sy * 0.38, 1.85), RX(-sy * 14.0)):
            for j in range(6):
                x = -2.5 + j * 1.0
                b.box((x, 0, 0), (0.94, 0.07, 2.9), "Trim", mats={"edge": "Frame"})
                for q in range(3):
                    b.box((x, sy * 0.04, -1.0 + q), (0.9, 0.02, 0.05), "Frame", mats={"-y" if sy > 0 else "+y": None})
            b.box((0, 0, 1.5), (6.0, 0.12, 0.12), "Accent")
            b.box((0, 0, -1.5), (6.0, 0.12, 0.10), "Frame")
        b.tube([(-1.2, sy * 2.6, Z0 + 0.3), (-1.2, sy * 3.9, Z0 + 0.3), (-1.2, y0, 0.35)], 0.12, seg=8, mat="Metal",
               fillet=0.3)
        b.tube([(1.2, sy * 2.6, Z0 + 0.3), (1.2, sy * 3.9, Z0 + 0.3), (1.2, y0, 0.35)], 0.12, seg=8, mat="Metal",
               fillet=0.3)
    # control building (+X) and water intake (-X)
    LVK.kiosk(b, 4.75, 0.0, rot=0.0, w=1.2, d=1.6, h=1.9)
    b.box0(4.1, 0.0, 0.0, 1.1, 0.25, 0.12, "Frame")
    b.vcyl(-4.6, 0.9, 0.0, 1.5, 0.45, seg=12, mat="Hull")
    b.vcyl(-4.6, 0.9, 0.8, 1.05, 0.46, seg=12, mat="WaterBlue", cap0=False, cap1=False)
    b.vcyl(-4.6, 0.9, 1.5, 1.6, 0.5, seg=12, mat="Frame")
    b.tube([(-4.6, 0.4, 0.5), (-4.0, 0.0, 0.5), (-3.3, 0.0, Z0 + 0.3)], 0.08, seg=6, mat="Metal", fillet=0.2)
    LV = dict(ring=6.15, antenna=(4.55, 0.4, 0.1 + 1.9 + 0.06, 1.4),
              band3=("cyl", 0, 0, zc - 0.07, 1.18, 0.14), modules=[(-4.6, -1.3, 0.0, 0.0, 1.0)],
              band4=("cyl", 0, 0, zc - 0.62, 1.01, 0.14), annex=[(-2.2, -5.3, 0.0, 0.0, 1.0), (-2.2, 5.3, 0.0, 0.0, 1.0)],
              crown=(0, 0, zc + 0.95, 0.66), beacon=(0, 0, zc + 1.42, 0.5),
              emblem=((4.75 + 0.61, 0.0, 1.1), (1, 0, 0), 0.3))
    return [b, pl] + LVK.add_levels([b], LV)


# ======================================================================================
# DEEP CORE DRILL
# ======================================================================================
def crystal(p, rng, x, y, z, h, r, mat="Produce"):
    a = rng.uniform(0, 2 * pi)
    tilt = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 1.0)).normalized()
    pts = []
    for k in range(5):
        ang = a + 2 * pi * k / 5
        pts.append((x + r * cos(ang), y + r * sin(ang), z))
    top = Vector((x, y, z)) + tilt * h
    for k in range(5):
        ang = a + 2 * pi * k / 5
        pts.append((top.x - tilt.x * h * 0.25 + r * 0.8 * cos(ang), top.y - tilt.y * h * 0.25 + r * 0.8 * sin(ang),
                    top.z - h * 0.25))
    pts.append(tuple(top + tilt * r * 0.8))
    p.hull(pts, mat)


def build_deep_drill(spec):
    rng = random.Random(77)
    b, lt = Part("Base"), Part("Lights")
    H = 14.0
    FZ = 1.35                                           # drill floor height
    hw = 1.55
    # substructure + drill floor + stairs
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box0(sx * hw, sy * hw, 0.0, 0.3, 0.3, FZ, "Frame")
            b.box0(sx * hw, sy * hw, 0.0, 0.55, 0.55, 0.1, "HullDark")
    for sx in (-1, 1):
        b.beam((sx * hw, -hw, 0.2), (sx * hw, hw, FZ - 0.2), 0.08, 0.08, "Frame")
        b.beam((-hw, sx * hw, FZ - 0.2), (hw, sx * hw, 0.2), 0.08, 0.08, "Frame")
    b.box0(0, 0, FZ, 2 * hw + 0.4, 2 * hw + 0.4, 0.14, "HullDark")
    for sx, sy in ((1, 1), (1, -1), (-1, 1)):
        LVK.railing(b, [(sx * (hw + 0.15), -sy * (hw + 0.15), FZ + 0.14), (sx * (hw + 0.15), sy * (hw + 0.15), FZ + 0.14)],
                    h=0.9, post_every=1.0)
    for k in range(6):                                   # stair down on +X side toward the south
        z = FZ - 0.22 * (k + 1)
        b.box0(hw + 0.55, -hw + 0.4 + 0.28 * k, z, 0.8, 0.26, 0.05, "Frame")
    b.beam((hw + 0.15, -hw + 0.3, FZ), (hw + 0.15, -hw + 0.3 + 1.7, 0.0), 0.05, 0.1, "Hazard")
    b.beam((hw + 0.95, -hw + 0.3, FZ), (hw + 0.95, -hw + 0.3 + 1.7, 0.0), 0.05, 0.1, "Hazard")
    # derrick
    top = 0.36
    feet = [Vector((sx * (hw - 0.1), sy * (hw - 0.1), FZ + 0.14)) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]
    tops = [Vector((sx * top, sy * top, H)) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]
    for f, t in zip(feet, tops):
        b.beam(f, t, 0.17, 0.17, "Frame")
    nb = 8
    for j in range(1, nb + 1):
        q = j / nb
        ring = [f + (t - f) * q for f, t in zip(feet, tops)]
        prev = [f + (t - f) * ((j - 1) / nb) for f, t in zip(feet, tops)]
        for i in range(4):
            if i == 0 and j <= 2:
                continue                               # the V-door on +X
            b.beam(ring[i], ring[(i + 1) % 4], 0.09, 0.09, "Frame")
            a, c = (prev[i], ring[(i + 1) % 4]) if j % 2 else (prev[(i + 1) % 4], ring[i])
            b.beam(a, c, 0.06, 0.06, "Frame")
    # crown block, sheaves, travelling block, drill string, kelly
    b.box((0, 0, H + 0.2), (1.1, 1.1, 0.4), "Accent")
    for dy in (-0.25, 0.25):
        b.cyl((-0.3, dy, H + 0.55), (0.3, dy, H + 0.55), 0.24, seg=10, mat="Metal")
    zt = H * 0.58
    for dx in (-0.12, 0.12):
        b.beam((dx, 0, H), (dx, 0, zt + 0.5), 0.025, 0.025, "Metal")
    b.box((0, 0, zt), (0.55, 0.45, 0.9), "Hazard", bevel=0.06)
    b.box((0, 0, zt - 0.6), (0.2, 0.2, 0.35), "Frame")
    b.vcyl(0, 0, FZ + 0.14, zt - 0.8, 0.10, seg=8, mat="Metal", cap0=False)
    b.vcyl(0, 0, FZ + 0.14, FZ + 0.45, 0.45, seg=12, mat="Frame")          # rotary table
    b.vcyl(0, 0, 0.0, FZ, 0.35, seg=12, mat="HullDark")                     # BOP stack under the floor
    b.vcyl(0, 0, 0.35, 0.65, 0.42, seg=12, mat="Accent")
    # racking board with pipe stands
    zr = H * 0.62
    b.box((-0.9, 0, zr), (0.7, 1.4, 0.08), "Frame")
    for k in range(7):
        y = -0.55 + 0.18 * k
        b.cyl((-0.55, y, FZ + 0.2), (-0.95, y, zr + 0.4), 0.05, seg=5, mat="Metal", smooth=False)
    # drawworks
    b.box0(-1.0, 0.0, FZ + 0.14, 0.9, 1.4, 0.8, "HullDark", bevel=0.05)
    b.cyl((-1.0, -0.72, FZ + 0.7), (-1.0, 0.72, FZ + 0.7), 0.32, seg=12, mat="Metal")
    # crystal separator (-X, -Y) with glowing exotic crystals, mud tank, kiosk
    sx_, sy_ = -2.3, -1.25
    b.vcyl(sx_, sy_, 0.0, 0.18, 0.7, seg=14, mat="Frame")
    b.vcyl(sx_, sy_, 0.18, 2.0, 0.58, seg=14, mat="Glass", cap0=False, cap1=False)
    b.vcyl(sx_, sy_, 2.0, 2.25, 0.65, seg=14, mat="Accent")
    b.vcyl(sx_, sy_, 2.25, 2.4, 0.4, seg=14, mat="Frame")
    for k in range(9):
        a = rng.uniform(0, 2 * pi)
        d = rng.uniform(0.0, 0.35)
        crystal(b, rng, sx_ + d * cos(a), sy_ + d * sin(a), 0.18, rng.uniform(0.35, 0.9), rng.uniform(0.07, 0.12))
    for k in range(4):                                   # crystal bin
        crystal(b, rng, -1.2 + rng.uniform(-0.2, 0.2), -2.55 + rng.uniform(-0.15, 0.15), 0.42, rng.uniform(0.2, 0.35),
                rng.uniform(0.05, 0.08))
    b.box0(-1.2, -2.55, 0.0, 0.8, 0.6, 0.45, "HullDark", mats={"+z": None})
    b.box0(-1.2, -2.55, 0.0, 0.84, 0.64, 0.08, "Frame")
    b.tube([(sx_, sy_, 2.3), (sx_, sy_, 2.6), (-0.5, -0.5, 2.6), (-0.3, -0.3, FZ + 0.3)], 0.08, seg=6, mat="Metal",
           fillet=0.3)
    b.box0(-2.2, 1.25, 0.0, 1.0, 1.3, 0.85, "HullDark", bevel=0.05)       # mud tank
    b.box((-2.2, 1.25, 0.62), (1.04, 1.34, 0.12), "Accent")
    b.tube([(-1.7, 1.25, 0.7), (-1.2, 1.1, 1.2), (-0.4, 0.4, FZ + 0.2)], 0.07, seg=6, mat="Rubber", fillet=0.3)
    LVK.kiosk(b, 2.35, 1.6, rot=0.0, w=0.8, d=0.7, h=1.2)
    # work lights on the derrick (housings in Base, lenses in Lights)
    for (z, sx, sy) in ((H * 0.45, 1, -1), (H * 0.45, -1, 1), (H * 0.85, 1, 1)):
        q = feet[0] if (sx, sy) == (1, -1) else (feet[2] if (sx, sy) == (-1, 1) else feet[1])
        t_ = tops[0] if (sx, sy) == (1, -1) else (tops[2] if (sx, sy) == (-1, 1) else tops[1])
        c = q + (t_ - q) * ((z - q.z) / (t_.z - q.z))
        c = c + Vector((sx * 0.2, sy * 0.2, 0))
        b.box(tuple(c), (0.3, 0.3, 0.22), "Frame", bevel=0.03)
        lt.box(tuple(c + Vector((sx * 0.16, sy * 0.16, 0))), (0.14, 0.14, 0.16), "Light")
    LV = dict(ring=3.35, antenna=(2.25, 1.8, 0.1 + 1.2 + 0.06, 1.0),
              band3=("cyl", sx_, sy_, 0.55, 0.58, 0.14), modules=[(2.35, -1.55, 0.0, 0.0, 0.75)],
              band4=("cyl", sx_, sy_, 1.35, 0.58, 0.14), annex=[(0.9, -2.75, 0.0, 0.0, 0.7)],
              crown=(0, 0, H - 0.05, 0.55), beacon=(0.35, 0.35, H + 0.4, 0.6),
              emblem=((2.35 + 0.41, 1.6, 0.7), (1, 0, 0), 0.16))
    return [b, lt] + LVK.add_levels([b], LV)


# ======================================================================================
# COMMS TOWER
# ======================================================================================
def build_comms(spec):
    b, lt = Part("Base"), Part("Lights")
    H = 22.0
    LVK.pad(b, 1.85, h=0.14, seg=12)
    angs = [radians(90 + 120 * i) for i in range(3)]
    rb, rt = 1.2, 0.34
    feet = [Vector((rb * cos(a), rb * sin(a), 0.14)) for a in angs]
    tops = [Vector((rt * cos(a), rt * sin(a), H)) for a in angs]
    for f, a in zip(feet, angs):
        b.box0(f.x, f.y, 0.0, 0.45, 0.45, 0.3, "Frame")
    for f, t in zip(feet, tops):
        b.beam(f, t, 0.14, 0.14, "Frame")
    nb = 14
    for j in range(1, nb + 1):
        q = j / nb
        ring = [f + (t - f) * q for f, t in zip(feet, tops)]
        prev = [f + (t - f) * ((j - 1) / nb) for f, t in zip(feet, tops)]
        for i in range(3):
            b.beam(ring[i], ring[(i + 1) % 3], 0.06, 0.06, "Frame" if j % 4 else "Accent")
            a, c = (prev[i], ring[(i + 1) % 3]) if j % 2 else (prev[(i + 1) % 3], ring[i])
            b.beam(a, c, 0.045, 0.045, "Metal")
    # platforms with hazard toe boards
    for zp in (8.0, 15.0):
        q = (zp - 0.14) / (H - 0.14)
        ring = [f + (t - f) * q for f, t in zip(feet, tops)]
        c = sum(ring, Vector((0, 0, 0))) / 3
        pts = [(c + (r - c) * 1.45) for r in ring]
        b.prism([(p_.x, p_.y) for p_ in pts], zp - 0.06, zp, "Frame")
        for i in range(3):
            b.beam(pts[i] + Vector((0, 0, 0.1)), pts[(i + 1) % 3] + Vector((0, 0, 0.1)), 0.03, 0.14, "Hazard")
            b.beam(pts[i] + Vector((0, 0, 0.95)), pts[(i + 1) % 3] + Vector((0, 0, 0.95)), 0.04, 0.04, "Hazard")
            b.beam(pts[i], pts[i] + Vector((0, 0, 0.95)), 0.04, 0.04, "Frame")
    # main dish at 15 m looking out over +X / -Y
    zd = 15.6
    q = (zd - 0.14) / (H - 0.14)
    leg = feet[2] + (tops[2] - feet[2]) * q
    base_pt = leg + Vector((0.35, -0.2, 0))
    b.beam(leg, base_pt, 0.12, 0.12, "Frame")
    with b.at(T(*base_pt), RZ(-40.0), RY(62.0)):
        b.lathe([(0.0, 0.0), (0.5, 0.06), (1.2, 0.34), (1.28, 0.42), (1.18, 0.42), (0.5, 0.14), (0.0, 0.08)],
                lambda k, i: "Hull" if k < 3 else ("Accent" if k == 3 else "Metal"), seg=18, smooth=True)
        for a in (0, 120, 240):
            b.cyl((1.15 * cos(radians(a)), 1.15 * sin(radians(a)), 0.4), (0, 0, 1.25), 0.025, seg=4, mat="Frame", smooth=False)
        b.vcyl(0, 0, 1.15, 1.4, 0.09, seg=6, mat="Frame")
        b.vcyl(0, 0, -0.35, 0.02, 0.18, seg=8, mat="Frame")
    # small dish at 11 m on another leg, panel antennas near the top
    q = (11.0 - 0.14) / (H - 0.14)
    leg = feet[1] + (tops[1] - feet[1]) * q
    with b.at(T(*(leg + Vector((-0.2, 0.25, 0)))), RZ(150.0), RY(70.0)):
        b.lathe([(0.0, 0.0), (0.55, 0.14), (0.6, 0.2), (0.0, 0.05)], lambda k, i: "Hull" if k < 1 else "Frame", seg=12)
    for i in range(3):
        a = angs[i] + radians(60)
        q = (19.5 - 0.14) / (H - 0.14)
        c = sum([f + (t - f) * q for f, t in zip(feet, tops)], Vector((0, 0, 0))) / 3
        pos = c + Vector((0.55 * cos(a), 0.55 * sin(a), 0))
        with b.at(T(*pos), RZ(degrees(a))):
            b.box((0.06, 0, 0), (0.12, 0.34, 1.5), "Hull", bevel=0.03)
            b.box((0.0, 0, 0.5), (0.2, 0.08, 0.08), "Frame")
            b.box((0.0, 0, -0.5), (0.2, 0.08, 0.08), "Frame")
    # top pole, beacon housings; lenses in Lights
    b.vcyl(0, 0, H - 0.1, H + 2.0, 0.07, 0.04, seg=6, mat="Metal")
    b.vcyl(0, 0, H - 0.15, H + 0.05, 0.42, seg=10, mat="Frame")
    b.vcyl(0, 0, H + 2.0, H + 2.12, 0.1, seg=8, mat="Frame")
    lt.sphere((0, 0, H + 2.22), 0.13, "Light", seg=8, rings=4)
    for i in range(3):
        f, t = feet[i], tops[i]
        q = (12.0 - 0.14) / (H - 0.14)
        c = f + (t - f) * q
        out = Vector((cos(angs[i]), sin(angs[i]), 0)) * 0.16
        b.box(tuple(c + out), (0.14, 0.14, 0.1), "Frame")
        lt.sphere(tuple(c + out * 1.9 + Vector((0, 0, 0.06))), 0.075, "Light", seg=6, rings=3)
        q = (H - 0.8 - 0.14) / (H - 0.14)
        c = f + (t - f) * q
        b.box(tuple(c + out), (0.12, 0.12, 0.1), "Frame")
        lt.sphere(tuple(c + out * 1.9 + Vector((0, 0, 0.06))), 0.07, "Light", seg=6, rings=3)
    # guy wires to three anchors, equipment shelter, cable duct
    for i in range(3):
        a = radians(30 + 120 * i)
        anc = Vector((2.12 * cos(a), 2.12 * sin(a), 0.0))
        q = (17.0 - 0.14) / (H - 0.14)
        c = sum([f + (t - f) * q for f, t in zip(feet, tops)], Vector((0, 0, 0))) / 3
        b.beam(anc + Vector((0, 0, 0.25)), c, 0.025, 0.025, "Metal")
        b.box0(anc.x, anc.y, 0.0, 0.34, 0.34, 0.28, "HullDark")
    LVK.kiosk(b, 0.95, -1.4, rot=-30.0, w=0.8, d=0.66, h=1.05)
    b.box0(0.5, -0.6, 0.0, 0.14, 0.9, 0.1, "Frame")
    return [b, lt]


# ======================================================================================
# LANDER (refresh of v1)
# ======================================================================================
SILL = 1.58


def build_lander(spec):
    b, lt = Part("Base"), Part("Lights")
    prof = [(0.80, 0.85), (2.30, 0.95), (3.00, 1.50), (3.00, 1.62), (3.00, 2.60), (3.00, 2.85), (3.00, 3.35), (2.95, 3.55),
            (2.80, 3.75), (2.25, 4.70), (1.95, 5.20), (1.45, 6.10), (1.25, 6.40), (1.00, 6.62), (0.0, 6.85)]
    mats = ["Frame", "HullDark", "Frame", "Hull", "Accent", "Accent", "Hull", "HullDark", "Hull", "Hull", "Hull",
            "HullDark", "Hull", "Hull"]
    b.lathe(prof, lambda k, i: mats[k] if not (k in (8, 9, 10) and i % 6 == 3) else "HullDark", seg=24)
    b.lathe([(3.07, 1.42), (3.07, 1.64), (2.99, 1.68)], "Frame", seg=24)
    b.lathe([(3.05, 3.30), (3.05, 3.40), (2.97, 3.43)], "Frame", seg=24)
    # engine bell
    b.lathe([(1.25, 0.20), (0.80, 0.62), (0.60, 0.90)], "Metal", seg=16)
    b.lathe([(0.60, 0.90), (0.74, 0.62), (1.16, 0.22)], "Rubber", seg=16)
    b.vcyl(0, 0, 0.80, 0.95, 0.95, seg=16, mat="Frame")
    # windows ring on the cone: dark glass in Base, glowing panes in Lights
    cone_n = Vector((0.95, 0.0, 0.55)).normalized()
    for k in range(8):
        a = 45.0 * k
        z = 4.55
        rad = 2.80 - (z - 3.75) * (0.55 / 0.95)
        big = (k == 0)
        r = 0.46 if big else 0.28
        with b.at(RZ(a)), lt.at(RZ(a)):
            pos = Vector((rad, 0, z))
            b.cyl(pos - cone_n * 0.14, pos + cone_n * 0.08, r + 0.09, seg=12, mat="Frame", cap0=False)
            b.cyl(pos, pos + cone_n * 0.09, r, seg=12, mat=None, cap_mat="Solar", cap0=False)
            lt.cyl(pos + cone_n * 0.095, pos + cone_n * 0.10, r * 0.92, seg=12, mat=None, cap_mat="Window", cap0=False)
    # hatch + ramp on +X
    b.box((3.02, 0, SILL + 0.92), (0.22, 1.74, 2.06), "Frame", bevel=0.05)
    b.box((3.11, 0, SILL + 0.90), (0.08, 1.30, 1.72), "HullDark")
    for sy in (-1, 1):
        for k in range(5):
            b.box((3.14, sy * 0.78, SILL + 0.1 + 0.36 * k), (0.03, 0.12, 0.34), "Hazard" if k % 2 == 0 else "Rubber",
                  mats={"-x": None})
    b.box((3.155, 0, SILL + 1.32), (0.012, 0.62, 0.32), "Solar", mats={"-x": None})
    lt.box((3.165, 0, SILL + 1.32), (0.012, 0.56, 0.27), "Window", mats={"-x": None})
    b.box((3.155, 0, SILL + 0.55), (0.012, 1.10, 0.10), "Accent", mats={"-x": None})
    b.beam((3.05, 0, SILL - 0.06), (5.0, 0, 0.02), 1.40, 0.12, "Metal")
    for sy in (-1, 1):
        b.beam((3.05, sy * 0.74, SILL + 0.04), (5.0, sy * 0.74, 0.10), 0.08, 0.14, "Hazard")
        LVK.railing(b, [(3.2, sy * 0.72, SILL - 0.02), (4.9, sy * 0.72, 0.12)], h=0.85, post_every=0.9, mat="Trim")
    for k in range(6):
        t = (k + 0.7) / 6.6
        b.box((3.05 + 1.95 * t, 0, SILL - 0.06 + (0.02 - (SILL - 0.06)) * t + 0.075), (0.10, 1.30, 0.05), "Frame")
    # cargo bay on -X: open door, crates inside and out
    b.box((-3.02, 0, 2.2), (0.22, 1.9, 1.6), "Frame", bevel=0.05)
    b.box((-3.1, 0, 2.2), (0.06, 1.6, 1.35), "Rubber")
    lt.box((-3.14, 0, 2.2), (0.012, 1.4, 1.1), "Window", mats={"+x": None})
    b.box((-3.3, 0, 1.45), (0.5, 1.7, 0.08), "Metal")
    for (x, y, z) in ((-3.7, -0.5, 0.0), (-3.7, 0.2, 0.0), (-4.2, -0.2, 0.0), (-3.7, -0.15, 0.45)):
        b.box0(x, y, z, 0.45, 0.45, 0.45, "Cargo", bevel=0.03)
        b.box0(x, y, z + 0.17, 0.46, 0.46, 0.1, "Frame")
    # three propellant tanks between the legs
    for a in (90.0, 270.0):
        x, y, _ = polar(2.72, a)
        b.sphere((x, y, 1.75), 0.72, "Metal", seg=12, rings=6)
        b.vcyl(x, y, 1.0, 1.1, 0.3, seg=8, mat="Frame")
    # four legs with shock absorbers and foot pads (may overhang 1 m)
    b.overhang = True
    for a in (45.0, 135.0, 225.0, 315.0):
        with b.at(RZ(a)):
            b.cyl((2.95, 0, 3.05), (5.30, 0, 0.30), 0.15, seg=8, mat="Metal")
            b.cyl((2.95, 0, 3.05), (4.05, 0, 1.80), 0.25, seg=8, mat="HullDark")
            b.cyl((4.05, 0, 1.80), (4.25, 0, 1.57), 0.27, seg=8, mat="Accent")
            b.cyl((2.55, 0, 1.25), (5.15, 0, 0.42), 0.10, seg=6, mat="Frame")
            for sy in (-1, 1):
                b.cyl((2.75, sy * 0.95, 1.55), (5.15, 0, 0.42), 0.07, seg=6, mat="Frame")
            with b.at(T(5.30, 0, 0)):
                b.lathe([(0.66, 0.0), (0.66, 0.10), (0.34, 0.24), (0.0, 0.26)], "Frame", seg=12)
                b.sphere((0, 0, 0.30), 0.19, "Metal", seg=8, rings=4)
    b.overhang = False
    # antenna mast with dish, RCS quads, landing lights
    b.vcyl(0.55, 0.55, 6.30, 8.05, 0.05, seg=6, mat="Frame")
    with b.at(T(0.55, 0.55, 7.55), RY(55.0)):
        b.lathe([(0.0, 0.0), (0.46, 0.20), (0.41, 0.23), (0.0, 0.06)], "Hull", seg=12)
        b.vcyl(0, 0, 0.05, 0.38, 0.02, seg=4, mat="Frame")
    b.vcyl(-0.6, -0.4, 6.4, 7.4, 0.02, seg=4, mat="Frame", smooth=False)
    lt.sphere((0.55, 0.55, 8.1), 0.08, "Light", seg=6, rings=3)
    for a in (22.5, 157.5, 202.5, 337.5):
        with b.at(RZ(a)):
            b.box((3.05, 0, 3.10), (0.30, 0.42, 0.34), "HullDark", bevel=0.04)
            for dz in (-0.1, 0.1):
                b.cyl((3.2, 0, 3.10 + dz), (3.34, 0, 3.10 + dz * 1.8), 0.05, 0.07, seg=5, mat="Frame", cap1=False)
    for a in (60.0, 120.0, 240.0, 300.0):
        with b.at(RZ(a)), lt.at(RZ(a)):
            b.box((2.55, 0, 1.05), (0.3, 0.3, 0.2), "Frame", bevel=0.03)
            lt.box((2.7, 0, 1.0), (0.04, 0.22, 0.13), "Light")
    anchors = [Anchor("Ramp", (5.05, 0.0, 0.0), forward=(1, 0, 0)), Anchor("Engine", (0.0, 0.0, 0.2), forward=(0, 0, -1),
                                                                           up=(1, 0, 0))]
    return [b, lt] + anchors


# ======================================================================================
# LANDING PAD (refresh of v1)
# ======================================================================================
def build_pad(spec):
    b, lt = Part("Base"), Part("Lights")
    SEG = 48
    TOP = 0.35

    b.lathe([(8.90, 0.0), (8.90, 0.20), (8.90, 0.30), (8.78, TOP), (8.2, TOP), (0.0, TOP)],
            lambda k, i: ("Frame", "Hazard" if (i // 2) % 2 == 0 else "Rubber", "Frame", "HullDark", "HullDark")[k],
            seg=SEG, smooth=False)
    z = TOP + 0.012
    for r0, r1, m in ((7.35, 7.85, "Accent"), (5.45, 5.55, "Frame"), (3.55, 3.85, "Hull"), (0.75, 1.05, "Hazard")):
        b.ring_flat(r0, r1, z, m, seg=SEG if r1 > 2 else 24)
    for k in range(12):                                   # radial panel seams
        with b.at(RZ(15.0 + 30.0 * k)):
            b.box((6.45, 0, z - 0.004), (2.2, 0.06, 0.004), "Frame", mats={"-z": None})
            b.box((2.4, 0, z - 0.004), (2.2, 0.06, 0.004), "Frame", mats={"-z": None})
    for k in range(4):                                    # centre marking: four bars with chevrons
        with b.at(RZ(90.0 * k)):
            b.box((2.15, 0, z), (1.9, 0.62, 0.004), "Hazard", mats={"-z": None})
            for j in range(3):
                b.poly([(4.35 + 0.45 * j, -0.35, z), (4.65 + 0.45 * j, 0.0, z), (4.35 + 0.45 * j, 0.35, z)], "Hull")
    for k in range(8):                                    # approach ticks
        with b.at(RZ(45.0 * k + 22.5)):
            b.box((6.55, 0, z), (0.9, 0.30, 0.004), "Hull", mats={"-z": None})
    for k in range(16):                                   # edge lights
        x, y, _ = polar(8.40, 22.5 * k + 11.25)
        b.vcyl(x, y, TOP, TOP + 0.14, 0.15, seg=8, mat="Frame")
        b.vcyl(x, y, TOP + 0.14, TOP + 0.2, 0.12, seg=8, mat="Frost")
        lt.hemi((x, y, TOP + 0.2), 0.12, "Light" if k % 2 else "Neon", seg=8, rings=2)
    # control kiosk with a small tower on -X
    with b.at(T(-7.8, 0.0, TOP)):
        b.box0(0, 0, 0, 1.5, 1.9, 2.1, "Hull", bevel=0.10)
        b.box((0.3, 0, 1.55), (0.95, 1.94, 0.40), "Solar", mats={"-x": None})
        b.box((0, 0, 1.98), (1.54, 1.94, 0.16), "Accent")
        b.box0(0, 0, 2.1, 1.1, 1.3, 0.10, "HullDark")
        b.box0(-0.2, 0.3, 2.2, 0.8, 0.8, 0.9, "Hull", bevel=0.06)
        b.box((0.21, 0.3, 2.75), (0.02, 0.62, 0.3), "Solar")
        b.vcyl(-0.3, 0.5, 3.1, 4.2, 0.03, seg=5, mat="Frame")
        b.box0(0.78, -0.45, 0, 0.12, 0.55, 1.0, "HullDark")
    lt.box((-7.8 + 0.31, 0.0, TOP + 1.55), (0.012, 1.84, 0.34), "Window", mats={"-x": None})
    lt.box((-7.8 + 0.22, 0.3, TOP + 2.75), (0.02, 0.56, 0.25), "Window")
    lt.sphere((-7.8 - 0.3, 0.5, TOP + 4.25), 0.08, "Light", seg=6, rings=3)
    # fuel station on +Y: hose reel, pump, pipe to the pad edge
    with b.at(T(0.0, 7.85, TOP), RZ(90.0)):
        b.box0(0, 0, 0, 0.8, 1.4, 1.2, "Hull", bevel=0.06)
        b.box((0, 0, 0.9), (0.84, 1.44, 0.14), "Hazard")
        with b.at(T(0.0, 0.0, 0.6), RY(90)):
            b.cyl((0, 0, 0.42), (0, 0, 0.62), 0.4, seg=12, mat="Frame")
            b.cyl((0, 0, 0.44), (0, 0, 0.6), 0.3, seg=12, mat="Rubber")
    # floodlight masts on the rim (+X/-Y and +X/+Y)
    for sy in (-1, 1):
        x, y, _ = polar(8.3, 180 - sy * 40 + 180)
        b.vcyl(x, y, TOP, TOP + 3.0, 0.07, seg=6, mat="Frame")
        b.box((x, y, TOP + 3.1), (0.5, 0.3, 0.25), "Frame", bevel=0.03)
        d = Vector((-x, -y, -3.0)).normalized()
        lt.box(tuple(Vector((x, y, TOP + 3.1)) + d * 0.16), (0.36, 0.26, 0.16), "Light")
    return [b, lt]


# ======================================================================================
MODELS = [
    dict(id="fusion_reactor", kind="exterior", footprint=6.5, accent="utilities", budget=9000,
         objects=["Base", "Plasma", "L2", "L3", "L4", "L5"], ao=dict(dist=1.4, samples=32), builder=build_fusion),
    dict(id="deep_drill", kind="exterior", footprint=3.5, accent="industry", produce=ITEMS["exotic"]["color"],
         budget=6500, objects=["Base", "Lights", "L2", "L3", "L4", "L5"], ao=dict(dist=1.0, samples=32),
         builder=build_deep_drill),
    dict(id="comms_tower", kind="exterior", footprint=2.5, accent="logistics", budget=4500,
         objects=["Base", "Lights"], ao=dict(dist=0.8, samples=32), builder=build_comms),
    dict(id="lander", kind="special", footprint=5.5, overhang=1.0, accent="logistics", budget=6500,
         objects=["Base", "Lights"], anchors=["Anchor_Ramp", "Anchor_Engine"], ao=dict(dist=1.2, samples=32),
         builder=build_lander),
    dict(id="landing_pad", kind="exterior", footprint=9.0, accent="logistics", budget=9000,
         objects=["Base", "Lights"], ao=dict(dist=1.2, samples=24), builder=build_pad),
]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    rows = []
    for spec in MODELS:
        if only and spec["id"] not in only:
            continue
        print("building", spec["id"], "...")
        rows.append(C.build_model(spec, spec["builder"]))
    C.write_reports(rows)


if __name__ == "__main__":
    main()
