"""
Frontier Habitat 2.0 - crop models (AAA_DESIGN.md sections 4 and 11).

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_crops.py -- [--only potato,wheat]

Output: assets/models/crop_<crop>.glb for potato, wheat, greens, tomato, soybean, herbs, mushroom, algae
(and crop.glb = crop_potato, the v1 name). Objects Stage1, Stage2, Stage3, all at the origin; the game shows one.

  * bed crops: the bed is 2.8 m (X) x 1.2 m (Y); origin = centre of the soil surface (tray soil top z = 0.55 in
    the room). Nothing leaves the bed.
  * mushroom: a rack with three shelves of substrate blocks on the same 2.8 x 1.2 bed, 1.45 m tall.
  * algae: a bundle of seven glass tubes, 1.2 m across, 1.9 m tall, origin at the bottom centre. A small
    accessory for the algae bioreactor (ART-A makes the room and its big tubes); it has no tray places.
Material `Produce` = the crop colour from content/items.json (per file).
"""
import os
import sys
import random
from math import sin, cos, pi, radians, sqrt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402
from ext_common import Part, T, RX, RY, RZ, S              # noqa: E402
from mathutils import Vector                               # noqa: E402

BX, BY = 1.40, 0.60          # half size of the bed


def clampxy(x, y, m=0.0):
    return max(-BX + m, min(BX - m, x)), max(-BY + m, min(BY - m, y))


def leaf(p, base, ang, length, width, lift, droop, mat, fold=0.25, rng=None):
    """folded leaf from `base`, pointing along `ang` (deg, in XY), rising `lift` deg, tip dropping `droop` m"""
    a = radians(ang)
    d = Vector((cos(a), sin(a), 0.0))
    s = Vector((-sin(a), cos(a), 0.0))
    up = Vector((0, 0, 1))
    el = radians(lift)
    ax = d * cos(el) + up * sin(el)
    b = Vector(base)
    mid = b + ax * (length * 0.5)
    tip = b + ax * length - up * droop
    ml = mid + s * (width / 2) + up * (width * fold * 0.5)
    mr = mid - s * (width / 2) + up * (width * fold * 0.5)
    mc = mid - up * (width * fold * 0.25)

    def c(q):
        x, y = clampxy(q.x, q.y)
        return (x, y, max(q.z, 0.005))
    i0, il, ir, ic, it = p.v(c(b)), p.v(c(ml)), p.v(c(mr)), p.v(c(mc)), p.v(c(tip))
    p.f([i0, ir, ic], mat)
    p.f([i0, ic, il], mat)
    p.f([ic, ir, it], mat)
    p.f([ic, it, il], mat)


def blade(p, base, ang, h, w, lean, mat):
    """thin grass blade: one tapered quad (2 triangles)"""
    a = radians(ang)
    s = Vector((-sin(a), cos(a), 0.0)) * (w / 2)
    d = Vector((cos(a), sin(a), 0.0))
    b = Vector(base)
    top = b + Vector((0, 0, h)) + d * lean
    q = [b - s, b + s, top + s * 0.25, top - s * 0.25]
    p.f([p.v((*clampxy(v.x, v.y), v.z)) for v in q], mat)


def stem(p, a, b, r, mat="PlantDark"):
    p.cyl(a, b, r, r * 0.7, seg=3, mat=mat, smooth=False, cap0=False, cap1=False)


def blob(p, c, r, mat, seg=5, rings=3, scale=(1, 1, 1)):
    x, y = clampxy(c[0], c[1], r * 0.5)
    p.sphere((x, y, c[2]), r, mat, seg=seg, rings=rings, scale=scale)


def grid(nx, ny, mx, my, rng, jit=0.03):
    for iy in range(ny):
        for ix in range(nx):
            x = -BX + mx + (2 * BX - 2 * mx) * (ix / max(1, nx - 1))
            y = -BY + my + (2 * BY - 2 * my) * (iy / max(1, ny - 1)) if ny > 1 else 0.0
            yield x + rng.uniform(-jit, jit), y + rng.uniform(-jit, jit)


def sprout(p, x, y, h, rng, mat="Plant"):
    stem(p, (x, y, 0.0), (x, y, h), 0.008)
    a = rng.uniform(0, 180)
    for da in (0.0, 180.0):
        leaf(p, (x, y, h - 0.004), a + da, h * 0.85, h * 0.55, 25, h * 0.15, mat)


# ======================================================================================
# POTATO: soil ridges, bushy plants, white flowers, tubers at the ridge sides
# ======================================================================================
def ridges(p, rows):
    for y in rows:
        p.prism_x([(y - 0.20, 0.0), (y + 0.20, 0.0), (y + 0.07, 0.10), (y - 0.07, 0.10)], -1.36, 1.36, "Soil", cap0=True,
                  cap1=True)


def bush(p, x, y, r, h, n, rng, mats=("Plant", "PlantDark"), lift=(15, 55), stalk=True):
    if stalk:
        stem(p, (x, y, 0.0), (x, y, h * 0.7), 0.012)
    for k in range(n):
        a = 360.0 * k / n + rng.uniform(-15, 15)
        z = h * rng.uniform(0.25, 0.85)
        ln = r * rng.uniform(0.8, 1.15) * (1.15 - z / h * 0.5)
        leaf(p, (x, y, z), a, ln, ln * 0.55, rng.uniform(*lift), ln * 0.25, mats[k % len(mats)])
    # top cap leaves
    for k in range(3):
        leaf(p, (x, y, h * 0.8), 120 * k + rng.uniform(0, 60), r * 0.6, r * 0.4, 50, 0.0, mats[0])


def build_potato(spec):
    rng = random.Random(101)
    rows = (-0.38, 0.0, 0.38)
    s1, s2, s3 = Part("Stage1"), Part("Stage2"), Part("Stage3")
    for part in (s1, s2, s3):
        ridges(part, rows)
    xs = [-1.2 + 0.4 * k for k in range(7)]
    with s1.at(T(0, 0, 0.095)):
        for y in rows:
            for x in xs:
                sprout(s1, x + rng.uniform(-0.04, 0.04), y, rng.uniform(0.07, 0.10), rng)
    with s2.at(T(0, 0, 0.09)):
        for y in rows:
            for x in xs:
                bush(s2, x + rng.uniform(-0.04, 0.04), y, 0.17, 0.26, 6, rng)
    for y in rows:
        for k, x in enumerate(xs):
            xx = x + rng.uniform(-0.04, 0.04)
            with s3.at(T(0, 0, 0.09)):
                bush(s3, xx, y, 0.24, 0.40, 7, rng, mats=("Plant", "PlantDark", "PlantDark"))
                if k % 2 == 0:
                    for j in range(2):                       # small white flowers on top
                        fx, fy = clampxy(xx + rng.uniform(-0.08, 0.08), y + rng.uniform(-0.08, 0.08), 0.03)
                        s3.box((fx, fy, 0.40 + rng.uniform(0, 0.05)), (0.05, 0.05, 0.02), "Frost", mats={"-z": None})
            if k % 2 == 1:                                   # tubers showing at the ridge side
                side = rng.choice((-1, 1))
                blob(s3, (xx + rng.uniform(-0.1, 0.1), y + side * 0.16, 0.05), 0.055, "Produce", seg=5, rings=3,
                     scale=(1.3, 1.0, 0.8))
    return [s1, s2, s3]


# ======================================================================================
# WHEAT: rows of blades -> tall green stalks -> golden stalks with ears
# ======================================================================================
def ear(p, x, y, z, ang, lean, mat):
    a = radians(ang)
    d = Vector((cos(a), sin(a), 0))
    top = Vector((x, y, z)) + d * lean * 0.3
    L, Wd = 0.09, 0.022
    c = Vector((x, y, z)) + (top - Vector((x, y, z))) * 0.5
    pts = [(x, y, z - 0.01), (top.x, top.y, top.z + L), (c.x + Wd, c.y, c.z + L * 0.5), (c.x - Wd, c.y, c.z + L * 0.5),
           (c.x, c.y + Wd, c.z + L * 0.5), (c.x, c.y - Wd, c.z + L * 0.5)]
    pts = [(*clampxy(q[0], q[1]), q[2]) for q in pts]
    p.convex(pts, [(0, 2, 4), (0, 4, 3), (0, 3, 5), (0, 5, 2), (1, 4, 2), (1, 3, 4), (1, 5, 3), (1, 2, 5)], mat)


def card(p, x, y, ang, h, wb, wt, head_h=0.0, head_w=0.0, mat="Plant", head_mat="Produce"):
    """one vertical plane through (x, y): a stalk quad and an optional head (double-sided materials)"""
    a = radians(ang)
    u = Vector((cos(a), sin(a), 0.0))
    b = Vector((x, y, 0.0))
    z1 = h - head_h

    def P(o, z):
        q = b + u * o
        return (*clampxy(q.x, q.y), z)
    p.f([p.v(P(-wb / 2, 0.0)), p.v(P(wb / 2, 0.0)), p.v(P(wt / 2, z1)), p.v(P(-wt / 2, z1))], mat)
    if head_h > 0:
        zm = z1 + head_h * 0.45
        p.f([p.v(P(-wt / 2, z1)), p.v(P(wt / 2, z1)), p.v(P(head_w / 2, zm)), p.v(P(-head_w / 2, zm))], head_mat)
        p.f([p.v(P(-head_w / 2, zm)), p.v(P(head_w / 2, zm)), p.v(P(head_w * 0.2, h)), p.v(P(-head_w * 0.2, h))], head_mat)


def build_wheat(spec):
    rng = random.Random(202)
    s1, s2, s3 = Part("Stage1"), Part("Stage2"), Part("Stage3")
    for x, y in grid(14, 5, 0.08, 0.08, rng, 0.03):
        for k in range(4):
            blade(s1, (x, y, 0), rng.uniform(0, 360), rng.uniform(0.06, 0.11), 0.02, 0.02, "Plant")
    for x, y in grid(13, 5, 0.1, 0.1, rng, 0.03):
        a0 = rng.uniform(0, 60)
        for k in range(3):
            card(s2, x, y, a0 + 60 * k, rng.uniform(0.32, 0.42), 0.10, 0.16, mat="Plant" if k % 2 else "PlantDark")
    for x, y in grid(13, 5, 0.1, 0.1, rng, 0.03):
        a0 = rng.uniform(0, 60)
        for k in range(3):
            card(s3, x, y, a0 + 60 * k, rng.uniform(0.62, 0.74), 0.10, 0.17, head_h=0.16, head_w=0.22, mat="Produce",
                 head_mat="Produce")
    return [s1, s2, s3]


# ======================================================================================
# GREENS (lettuce): rosettes -> open heads -> big round heads
# ======================================================================================
def rosette(p, x, y, r, layers, per, rng, mats, h0=0.0, cup=1.0):
    for L in range(layers):
        f = 1.0 - L / max(1, layers)
        n = max(3, int(per * (0.6 + 0.4 * f)))
        rr = r * (0.45 + 0.55 * f)
        for k in range(n):
            a = 360.0 * k / n + L * 23 + rng.uniform(-10, 10)
            lift = 20 + (1 - f) * 45 * cup
            leaf(p, (x, y, h0 + 0.01 + L * r * 0.18), a, rr, rr * 0.8, lift, rr * 0.12 * f, mats[L % len(mats)], fold=0.35)


def build_greens(spec):
    rng = random.Random(303)
    s1, s2, s3 = Part("Stage1"), Part("Stage2"), Part("Stage3")
    for x, y in grid(8, 3, 0.18, 0.18, rng, 0.02):
        rosette(s1, x, y, 0.07, 1, 4, rng, ("Plant",))
    for x, y in grid(7, 3, 0.2, 0.2, rng, 0.02):
        rosette(s2, x, y, 0.15, 2, 6, rng, ("Plant", "Produce"))
    for x, y in grid(6, 2, 0.24, 0.3, rng, 0.02):
        rosette(s3, x, y, 0.24, 3, 8, rng, ("Produce", "Plant", "Produce"), cup=1.3)
        blob(s3, (x, y, 0.14), 0.09, "Plant", seg=6, rings=3, scale=(1, 1, 0.9))
    # a second offset row keeps the bed full
    for x, y in grid(5, 1, 0.5, 0.6, rng, 0.02):
        rosette(s3, x, y, 0.19, 2, 7, rng, ("PlantDark", "Produce"), cup=1.3)
    return [s1, s2, s3]


# ======================================================================================
# TOMATO: seedlings with canes -> vines with yellow flowers -> vines with red fruit
# ======================================================================================
def trellis(p, h):
    for y in (-0.32, 0.32):
        for x in (-1.3, 1.3):
            p.box0(x, y, 0.0, 0.035, 0.035, h, "Frame")
        p.beam((-1.3, y, h - 0.02), (1.3, y, h - 0.02), 0.02, 0.02, "Frame")
        p.beam((-1.3, y, h * 0.55), (1.3, y, h * 0.55), 0.012, 0.012, "Metal")


def vine(p, x, y, h, rng, n_leaf, fruit, fruit_mat="Produce", flowers=0):
    pts = [Vector((x, y, 0.0))]
    for k in range(1, 5):
        pts.append(Vector((x + rng.uniform(-0.05, 0.05), y + rng.uniform(-0.04, 0.04), h * k / 4)))
    for a, b in zip(pts[:-1], pts[1:]):
        stem(p, a, b, 0.014)
    for k in range(n_leaf):
        z = h * rng.uniform(0.15, 0.95)
        a = rng.uniform(0, 360)
        L = rng.uniform(0.13, 0.19)
        leaf(p, (x, y, z), a, L, L * 0.6, rng.uniform(-10, 30), L * 0.3, "PlantDark" if k % 3 else "Plant")
    for k in range(fruit):
        z = h * rng.uniform(0.2, 0.8)
        a = radians(rng.uniform(0, 360))
        rr = rng.uniform(0.045, 0.06)
        ripe = rng.random() < 0.8
        blob(p, (x + 0.08 * cos(a), y + 0.08 * sin(a), z), rr, fruit_mat if ripe else "Plant", seg=5, rings=3)
    for k in range(flowers):
        z = h * rng.uniform(0.4, 0.9)
        a = radians(rng.uniform(0, 360))
        fx, fy = clampxy(x + 0.07 * cos(a), y + 0.07 * sin(a))
        p.box((fx, fy, z), (0.035, 0.035, 0.025), "Hazard")


def build_tomato(spec):
    rng = random.Random(404)
    s1, s2, s3 = Part("Stage1"), Part("Stage2"), Part("Stage3")
    trellis(s1, 0.55)
    trellis(s2, 0.75)
    trellis(s3, 0.95)
    xs = [-1.0, -0.33, 0.33, 1.0]
    for y in (-0.32, 0.32):
        for x in xs:
            sprout(s1, x + rng.uniform(-0.03, 0.03), y, rng.uniform(0.10, 0.14), rng)
            vine(s2, x, y, rng.uniform(0.45, 0.6), rng, 8, 0, flowers=3)
            vine(s3, x, y, rng.uniform(0.78, 0.9), rng, 8, 5, flowers=1)
    return [s1, s2, s3]


# ======================================================================================
# SOYBEAN: rows of trifoliate plants -> dense bushes -> yellowing bushes with pod clusters
# ======================================================================================
def trifoliate(p, x, y, z, ang, L, mat, rng):
    for da in (-40, 0, 40):
        leaf(p, (x, y, z), ang + da, L, L * 0.55, 30, L * 0.2, mat)


def pod(p, x, y, z, ang, mat):
    a = radians(ang)
    d = Vector((cos(a), sin(a), 0.0))
    s_ = Vector((-sin(a), cos(a), 0.0))
    b = Vector((x, y, z))
    q = [b - s_ * 0.012, b + s_ * 0.012, b + d * 0.035 + s_ * 0.016 + Vector((0, 0, -0.09)),
         b + d * 0.035 - s_ * 0.016 + Vector((0, 0, -0.09))]
    p.f([p.v((*clampxy(v.x, v.y), v.z)) for v in q], mat)


def build_soybean(spec):
    rng = random.Random(505)
    s1, s2, s3 = Part("Stage1"), Part("Stage2"), Part("Stage3")
    rows = (-0.36, 0.0, 0.36)
    xs = [-1.2 + 0.3 * k for k in range(9)]
    for y in rows:
        for x in xs:
            sprout(s1, x + rng.uniform(-0.03, 0.03), y, rng.uniform(0.06, 0.09), rng)
    for y in rows:
        for x in xs[::2]:
            xx = x + rng.uniform(-0.04, 0.04)
            stem(s2, (xx, y, 0), (xx, y, 0.26), 0.01)
            for k in range(4):
                trifoliate(s2, xx, y, 0.1 + 0.05 * k, 90 * k + rng.uniform(0, 40), 0.11, "Plant", rng)
    for y in rows:
        for x in (-1.08, -0.36, 0.36, 1.08):
            xx = x + rng.uniform(-0.04, 0.04)
            stem(s3, (xx, y, 0), (xx, y, 0.44), 0.014)
            for k in range(6):
                trifoliate(s3, xx, y, 0.14 + 0.055 * k, 60 * k + rng.uniform(0, 30), 0.17,
                           "Produce" if k >= 2 else "PlantDark", rng)
            for k in range(3):                                   # pod clusters round the stem
                a = 120 * k + rng.uniform(0, 40)
                for j in range(3):
                    pod(s3, xx + 0.04 * cos(radians(a)), y + 0.04 * sin(radians(a)), rng.uniform(0.16, 0.34),
                        a + rng.uniform(-25, 25), "Produce")
    return [s1, s2, s3]


# ======================================================================================
# HERBS: mixed clumps - chives (spikes), basil (broad rosettes), parsley (frilly), rosemary (needles)
# ======================================================================================
def chives(p, x, y, h, n, rng):
    a0 = rng.uniform(0, 45)
    for k in range(n):
        card(p, x + rng.uniform(-0.02, 0.02), y + rng.uniform(-0.02, 0.02), a0 + 180.0 * k / n, h * rng.uniform(0.85, 1.1),
             0.10, 0.05, mat="PlantDark")


def basil(p, x, y, r, h, rng):
    stem(p, (x, y, 0), (x, y, h), 0.012)
    for k in range(3):
        z = h * (0.25 + 0.3 * k)
        for j in range(5):
            leaf(p, (x, y, z), 72 * j + 36 * k + rng.uniform(-10, 10), r * (1.15 - 0.25 * k), r * 0.8, 20, r * 0.25,
                 "Plant", fold=0.45)


def parsley(p, x, y, r, rng):
    for k in range(9):
        a = 40.0 * k + rng.uniform(-10, 10)
        L = r * rng.uniform(0.8, 1.2)
        leaf(p, (x, y, 0.01), a, L, L * 0.55, 50, L * 0.2, "Produce", fold=0.6)
        leaf(p, (x, y, L * 0.45), a + 20, L * 0.6, L * 0.5, 30, L * 0.1, "Produce", fold=0.6)


def rosemary(p, x, y, h, rng):
    for k in range(6):
        a = radians(60 * k + rng.uniform(-15, 15))
        top = (x + 0.08 * cos(a), y + 0.08 * sin(a), h * rng.uniform(0.8, 1.0))
        stem(p, (x, y, 0), top, 0.009, "PlantDark")
        for j in range(3):
            z = top[2] * (0.4 + 0.2 * j)
            q = (x + (top[0] - x) * z / top[2], y + (top[1] - y) * z / top[2], z)
            leaf(p, q, rng.uniform(0, 360), 0.08, 0.035, 55, 0.0, "PlantDark", fold=0.15)


def build_herbs(spec):
    rng = random.Random(606)
    s1, s2, s3 = Part("Stage1"), Part("Stage2"), Part("Stage3")
    kinds = ["chives", "basil", "parsley", "rosemary"]
    cells = list(grid(7, 2, 0.2, 0.28, rng, 0.02))
    for idx, (x, y) in enumerate(cells):
        kind = kinds[(idx + (idx // 7)) % 4]
        sprout(s1, x, y, 0.07, rng, "Plant" if kind != "chives" else "PlantDark")
        sprout(s1, x + 0.09, y - 0.06, 0.06, rng)
        for (part, f) in ((s2, 0.6), (s3, 1.0)):
            if kind == "chives":
                chives(part, x, y, 0.34 * f + 0.05, 4, rng)
                if f == 1.0:
                    for j in range(3):                          # round flower heads
                        blob(part, (x + rng.uniform(-0.04, 0.04), y + rng.uniform(-0.04, 0.04), 0.36 + 0.03 * j), 0.03,
                             "Fabric", seg=4, rings=2)
            elif kind == "basil":
                basil(part, x, y, 0.13 * f + 0.03, 0.26 * f + 0.05, rng)
            elif kind == "parsley":
                parsley(part, x, y, 0.19 * f + 0.03, rng)
            else:
                rosemary(part, x, y, 0.40 * f + 0.05, rng)
    return [s1, s2, s3]


# ======================================================================================
# MUSHROOM: a three-shelf rack with substrate blocks; pins -> buttons -> open caps
# ======================================================================================
SHELVES = (0.04, 0.52, 1.00)


def rack(p):
    for x in (-1.34, 1.34):
        for y in (-0.52, 0.52):
            p.box0(x, y, 0.0, 0.05, 0.05, 1.45, "Frame")
    for z in SHELVES:
        p.box0(0, 0, z, 2.72, 1.08, 0.035, "HullDark", mats={"-z": None} if z < 0.1 else None)
    for y in (-0.52, 0.52):
        p.beam((-1.34, y, 1.43), (1.34, y, 1.43), 0.04, 0.04, "Frame")


BLOCKS = [(-1.04, -0.25), (0.0, -0.25), (1.04, -0.25), (-0.52, 0.25), (0.52, 0.25)]


def blocks(p):
    for z in SHELVES:
        for (x, y) in BLOCKS:
            p.box0(x, y, z + 0.035, 0.60, 0.44, 0.22, "Soil", mats={"-z": None})


def mushroom(p, x, y, z, h, r, lean=(0.0, 0.0)):
    top = Vector((x + lean[0], y + lean[1], z + h))
    p.cyl((x, y, z), top, r * 0.28, r * 0.22, seg=3, mat="Frost", smooth=False, cap0=False, cap1=False)
    with p.at(T(*top)):
        p.lathe([(0.0, -0.25 * r), (r, 0.0), (0.0, r * 0.5)], "Produce", seg=5, smooth=True)


def oyster(p, x, y, z, side, r):
    """a flat shelf cap growing out of a block side (side = +1 / -1 along Y), double-sided Produce"""
    c = Vector((x, y + side * 0.005, z))
    pts = [c + Vector((r * cos(radians(a)), side * r * 0.9 * sin(radians(a)), 0.02 * sin(radians(a)))) for a in (0, 45, 90, 135, 180)]
    top = c + Vector((0, side * r * 0.35, 0.035))
    for i in range(4):
        p.f([p.v(tuple(top)), p.v(tuple(pts[i])), p.v(tuple(pts[i + 1]))], "Produce")
        p.f([p.v(tuple(c)), p.v(tuple(pts[i + 1])), p.v(tuple(pts[i]))], "Produce")


def cluster(p, rng, x, y, z, n, h, r):
    for k in range(n):
        a = radians(360.0 * k / n + rng.uniform(-20, 20))
        d = rng.uniform(0.03, 0.12)
        mushroom(p, x + d * cos(a), y + d * sin(a), z, h * rng.uniform(0.8, 1.2), r * rng.uniform(0.8, 1.2),
                 lean=(0.05 * cos(a) * h, 0.05 * sin(a) * h))


def build_mushroom(spec):
    rng = random.Random(707)
    stages = [Part("Stage1"), Part("Stage2"), Part("Stage3")]
    for st, (n, h, r, ro) in zip(stages, ((3, 0.035, 0.025, 0.0), (3, 0.06, 0.06, 0.07), (3, 0.10, 0.10, 0.12))):
        rack(st)
        blocks(st)
        for z in SHELVES:
            for (x, y) in BLOCKS:
                top = z + 0.035 + 0.22
                cluster(st, rng, x + rng.uniform(-0.1, 0.1), y + rng.uniform(-0.06, 0.06), top, n, h, r)
                if ro > 0:
                    for side in (-1, 1):
                        oyster(st, x + rng.uniform(-0.12, 0.12), y + side * 0.22, z + 0.035 + rng.uniform(0.08, 0.15), side, ro)
    return stages


# ======================================================================================
# ALGAE: seven glass tubes on a plinth, the culture rises and glows
# ======================================================================================
def build_algae(spec):
    rng = random.Random(808)
    stages = [Part("Stage1"), Part("Stage2"), Part("Stage3")]
    tubes = [(0.0, 0.0)] + [(0.40 * cos(radians(60 * k + 30)), 0.40 * sin(radians(60 * k + 30))) for k in range(6)]
    H0, H1 = 0.22, 1.72
    for si, st in enumerate(stages):
        st.vcyl(0, 0, 0.0, 0.08, 0.59, seg=12, mat="Frame")
        st.vcyl(0, 0, 0.08, 0.22, 0.56, seg=12, mat="Accent")
        st.vcyl(0, 0, H1, H1 + 0.10, 0.58, seg=12, mat="Frame")
        st.vcyl(0, 0, H1 + 0.10, H1 + 0.16, 0.40, seg=12, mat="Metal")
        st.tube([(0, 0, H1 + 0.16), (0, 0, H1 + 0.30), (0.3, 0, H1 + 0.30), (0.52, 0, H1 + 0.14)], 0.05, seg=6, mat="Metal",
                fillet=0.08)
        level = (0.35, 0.72, 0.97)[si]
        for (x, y) in tubes:
            st.vcyl(x, y, H0, H1, 0.16, seg=10, mat="Glass", cap0=False, cap1=False)
            top = H0 + (H1 - H0) * level
            mat = ("Produce", "Produce", "Glow")[si]
            st.vcyl(x, y, H0, top, 0.14, seg=8, mat=mat, cap0=False)
            if si == 1:
                st.vcyl(x, y, top - 0.12, top, 0.142, seg=8, mat="Glow", cap0=False, cap1=False)
            for k in range((0, 1, 3)[si]):                  # bubbles
                bz = rng.uniform(H0 + 0.1, top - 0.05)
                st.sphere((x + rng.uniform(-0.07, 0.07), y + rng.uniform(-0.07, 0.07), bz), 0.025, "Frost", seg=4, rings=2)
        for k in range(6):                                  # clamp rings
            a = radians(60 * k)
            st.box((0.56 * cos(a), 0.56 * sin(a), 0.95), (0.05, 0.05, 1.4), "Frame")
    return stages


# ======================================================================================
def stage_budget(stats):
    over = ["%s %d" % (n, s["tris"]) for n, s in stats.items() if s["tris"] > 1500]
    return ("stage over 1500 triangles: " + ", ".join(over)) if over else None


def bed_check(stats):
    for n, s in stats.items():
        (x0, y0, z0), (x1, y1, z1) = s["bbox"]
        if x0 < -1.401 or x1 > 1.401 or y0 < -0.601 or y1 > 0.601:
            return "%s leaves the 2.8 x 1.2 bed: x %.2f..%.2f y %.2f..%.2f" % (n, x0, x1, y0, y1)
    return None


def algae_check(stats):
    for n, s in stats.items():
        (x0, y0, z0), (x1, y1, z1) = s["bbox"]
        if max(abs(x0), abs(x1), abs(y0), abs(y1)) > 0.62:
            return "%s wider than 1.2 m" % n
    return None


ITEMS = C.load_content("items.json")["items"]
BUILDERS = dict(potato=build_potato, wheat=build_wheat, greens=build_greens, tomato=build_tomato,
                soybean=build_soybean, herbs=build_herbs, mushroom=build_mushroom, algae=build_algae)
MODELS = []
for crop, fn in BUILDERS.items():
    checks = [stage_budget] + ([algae_check] if crop == "algae" else [bed_check])
    MODELS.append(dict(id="crop_" + crop, kind="crop", footprint=None, accent="food", produce=ITEMS[crop]["color"],
                       budget=4500, objects=["Stage1", "Stage2", "Stage3"], zmin=-0.01, checks=checks,
                       also=["crop"] if crop == "potato" else [],
                       ao=dict(dist=0.22, samples=32, min_ao=0.35,
                               occluders={"Stage1": [], "Stage2": [], "Stage3": []}),
                       builder=fn))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    rows = []
    for spec in MODELS:
        if only and spec["id"][5:] not in only and spec["id"] not in only:
            continue
        print("building", spec["id"], "...")
        rows.append(C.build_model(spec, spec["builder"]))
    C.write_reports(rows)


if __name__ == "__main__":
    main()
