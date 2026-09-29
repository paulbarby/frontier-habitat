"""
Frontier Habitat 5.0 - super dome: the atrium (plaza, pool with loungers and a slide, fountain, park strip, event
stage) and the four glass lifts. ART-B. Blender --background only:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/dome_atrium.py
Writes assets/models/dome_atrium.glb (contract: dome_common.py docstring).
  Atrium            ground inside r 20 (floor 1)
  Lifts             4 glass shafts with bridges to the galleries (all floors)
  Lift_<i>          the cabs, i = 0..3; rest = at L1. Motion: translate along local +Z (Godot +Y) to extras.stops[k]
"""
import os
import sys
import math
from math import sin, cos, radians, pi

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dome_common as D                                    # noqa: E402
from dome_common import Group, pol, T, RZ, RX, RY, S, GRAPHITE, WHITE, TILE, INK   # noqa: E402
from vehicle_common import Node                            # noqa: E402
from mathutils import Vector, Matrix                       # noqa: E402

Z = D.GROUND
POOL_C = Vector((-6.0, 4.5, 0.0))       # pool centre
POOL_L, POOL_W, POOL_R = 15.0, 7.0, 2.2  # length, width, corner radius
POOL_DEPTH = 1.6
WATER_Z = Z - 0.10
FOUNTAIN_C = Vector((6.5, -6.0, 0.0))
STAGE_A, STAGE_R = 112.0, 15.5           # event stage at this bearing and radius
PARK_A0, PARK_A1 = 205.0, 290.0          # park strip arc
POOL_TILE = "Palette:#8fd0e0"
DECK = "Palette:#d8cdb8"
GRASS = "Palette:#5c9a45"


def pool_outline(inset=0.0, n_corner=4):
    """rounded rectangle around POOL_C (counter-clockwise), in the plane"""
    hx, hy, r = POOL_L / 2 - inset, POOL_W / 2 - inset, max(0.2, POOL_R - inset)
    pts = []
    for (cx, cy, a0) in ((hx - r, -hy + r, -90.0), (hx - r, hy - r, 0.0), (-hx + r, hy - r, 90.0), (-hx + r, -hy + r, 180.0)):
        for k in range(n_corner + 1):
            a = radians(a0 + 90.0 * k / n_corner)
            pts.append(Vector((POOL_C.x + cx + r * cos(a), POOL_C.y + cy + r * sin(a), 0.0)))
    return pts


def in_pool(x, y, pad=0.0):
    dx, dy = abs(x - POOL_C.x) - (POOL_L / 2 - POOL_R), abs(y - POOL_C.y) - (POOL_W / 2 - POOL_R)
    ox, oy = max(dx, 0.0), max(dy, 0.0)
    return math.hypot(ox, oy) + min(max(dx, dy), 0.0) < POOL_R + pad


def in_park(r, a):
    return 13.6 < r < 19.4 and PARK_A0 < (a % 360.0) < PARK_A1


def plaza(p):
    """paving in polar cells (1 m rings), coloured bands; cells under the pool, the fountain and the park are left out"""
    for i in range(20):
        r0, r1 = float(i), float(i + 1)
        n = max(6, int(2 * pi * r1 / 1.6))
        for j in range(n):
            a0, a1 = 360.0 * j / n, 360.0 * (j + 1) / n
            am = (a0 + a1) / 2
            c = pol((r0 + r1) / 2, am)
            if in_pool(c.x, c.y, pad=0.9) or (c - FOUNTAIN_C).length < 2.6 or in_park((r0 + r1) / 2, am):
                continue
            ring = i % 5
            col = D.PAVING if ring in (0, 2, 3) else ("Palette:#c9c0b0" if ring == 1 else "Palette:#a9a397")
            if i == 19:
                col = "Palette:#8e887d"
            if (j + i) % 7 == 0 and ring in (0, 3):
                col = "Palette:#d8cdb8"
            q = [pol(r0, a0, Z), pol(r1, a0, Z), pol(r1, a1, Z), pol(r0, a1, Z)] if r0 > 0 else [Vector((0, 0, Z)), pol(r1, a0, Z), pol(r1, a1, Z)]
            D.quad(p, q, Vector((0, 0, 1)), col)


def pool(p, lt, wa):
    """deck, coping, basin walls and floor, lane lines, water surface, underwater lights"""
    deck = pool_outline(-0.9, 4)
    rim = pool_outline(0.0, 4)
    for k in range(len(rim)):
        a, b = rim[k], rim[(k + 1) % len(rim)]
        da, db = deck[k], deck[(k + 1) % len(deck)]
        D.quad(p, [a + Vector((0, 0, Z + 0.12)), b + Vector((0, 0, Z + 0.12)), db + Vector((0, 0, Z + 0.12)),
                   da + Vector((0, 0, Z + 0.12))], Vector((0, 0, 1)), WHITE)                                # coping / deck
        D.quad(p, [da + Vector((0, 0, Z)), db + Vector((0, 0, Z)), db + Vector((0, 0, Z + 0.12)), da + Vector((0, 0, Z + 0.12))],
               (da + db) / 2 - POOL_C, "Palette:#c3c9d1")
        D.quad(p, [a + Vector((0, 0, Z + 0.12)), b + Vector((0, 0, Z + 0.12)), b + Vector((0, 0, Z - 2.05)),
                   a + Vector((0, 0, Z - 2.05))], POOL_C - (a + b) / 2, POOL_TILE)                        # basin wall
        m = (a + b) / 2
        inward = (POOL_C - m)
        inward.z = 0
        inward.normalize()
        if k % 2 == 0:
            c = m + inward * 0.02 + Vector((0, 0, Z - 0.55))
            t = (b - a).normalized()
            lt.poly([c - t * 0.35 - Vector((0, 0, 0.12)), c + t * 0.35 - Vector((0, 0, 0.12)), c + t * 0.35 + Vector((0, 0, 0.12)),
                     c - t * 0.35 + Vector((0, 0, 0.12))], "SignCyan")                # fix 5: cyan underwater lights
    cen = Vector((POOL_C.x, POOL_C.y, Z - POOL_DEPTH))

    def depth_at(x):                                               # fix 6: 1.0 m at the -X end, 2.0 m at the +X end
        f = (x - (POOL_C.x - POOL_L / 2)) / POOL_L
        return Z - (1.0 + 1.0 * max(0.0, min(1.0, f)))
    for k in range(len(rim)):                                                          # basin floor (fan), darker deep end
        a, b = rim[k], rim[(k + 1) % len(rim)]
        mx = (a.x + b.x) / 2
        col = POOL_TILE if mx < POOL_C.x - 2 else ("Palette:#5aa8c8" if mx < POOL_C.x + 3 else "Palette:#2f6f98")
        p.poly([Vector((POOL_C.x, POOL_C.y, depth_at(POOL_C.x))), Vector((b.x, b.y, depth_at(b.x))),
                Vector((a.x, a.y, depth_at(a.x)))], col)
    for k in range(1, int(POOL_L)):                                                   # fix 8: floor tile grid (on the slope)
        x = POOL_C.x - POOL_L / 2 + k
        p.box((x, POOL_C.y, depth_at(x) + 0.006), (0.04, POOL_W - 0.6, 0.012), "Palette:#1f5f8a")
    for k in range(1, int(POOL_W)):
        y = POOL_C.y - POOL_W / 2 + k
        p.beam((POOL_C.x - POOL_L / 2 + 0.6, y, depth_at(POOL_C.x - POOL_L / 2 + 0.6) + 0.008),
               (POOL_C.x + POOL_L / 2 - 0.6, y, depth_at(POOL_C.x + POOL_L / 2 - 0.6) + 0.008), 0.04, 0.012, "Palette:#1f5f8a")
    for k in range(len(rim)):                                                          # tile border at the water line
        a, b = rim[k], rim[(k + 1) % len(rim)]
        m = (a + b) / 2
        inward = POOL_C - m
        inward.z = 0
        inward.normalize()
        D.quad(p, [a + inward * 0.01 + Vector((0, 0, Z - 0.02)), b + inward * 0.01 + Vector((0, 0, Z - 0.02)),
                   b + inward * 0.01 + Vector((0, 0, Z - 0.3)), a + inward * 0.01 + Vector((0, 0, Z - 0.3))], inward, "Palette:#1f5f8a")
    for k in (-1, 0, 1):                                                               # lane lines on the floor
        y = POOL_C.y + k * 1.75
        p.beam((POOL_C.x - POOL_L / 2 + 1.5, y, depth_at(POOL_C.x - POOL_L / 2 + 1.5) + 0.012),
               (POOL_C.x + POOL_L / 2 - 1.5, y, depth_at(POOL_C.x + POOL_L / 2 - 1.5) + 0.012), 0.22, 0.012, "Palette:#12324a")
    for k in (-0.5, 0.5):                                                              # lane ropes with floats
        y = POOL_C.y + k * 1.75
        n = int(POOL_L / 0.35)
        for j in range(n):
            x = POOL_C.x - POOL_L / 2 + 0.3 + j * (POOL_L - 0.6) / n
            p.cyl((x, y, WATER_Z + 0.02), (x + 0.2, y, WATER_Z + 0.02), 0.05, seg=5,
                  mat="Palette:#e0503a" if (j // 3) % 2 else "Palette:#f2f0ea")
    for k in range(len(rim)):                                                          # the water surface
        a, b = rim[k], rim[(k + 1) % len(rim)]
        wa.poly([Vector((POOL_C.x, POOL_C.y, WATER_Z)), Vector((a.x, a.y, WATER_Z)), Vector((b.x, b.y, WATER_Z))], "Water")
    for sx in (-1, 1):                                                                 # ladders
        c = Vector((POOL_C.x + sx * (POOL_L / 2 - 3.5), POOL_C.y + POOL_W / 2, Z))
        for dx in (-0.25, 0.25):
            p.tube([c + Vector((dx, -0.35, -0.6)), c + Vector((dx, -0.1, 0.5)), c + Vector((dx, 0.25, 0.5)), c + Vector((dx, 0.3, 0.12))],
                   0.03, seg=5, mat="Palette:#c3c9d1", fillet=0.1, fillet_n=2)


def slide(p):
    """a small tube slide: a ladder tower on the deck at the +X end, 1.25 turns down into the water"""
    base = Vector((POOL_C.x + POOL_L / 2 + 2.0, POOL_C.y - 0.5, Z))
    top_z = Z + 3.6
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.cyl(base + Vector((sx * 0.6, sy * 0.6, 0.12)), base + Vector((sx * 0.6, sy * 0.6, top_z - Z + 1.1)), 0.06, seg=5,
                  mat=GRAPHITE, cap0=False)
    p.box(tuple(base + Vector((0, 0, top_z - Z + 0.02))), (1.5, 1.5, 0.1), "Palette:#c3c9d1")
    for k in range(9):
        p.box(tuple(base + Vector((0.65, 0, 0.35 + k * (top_z - Z) / 9))), (0.1, 0.9, 0.05), GRAPHITE)
    for sy in (-1, 1):
        p.box(tuple(base + Vector((0, sy * 0.72, top_z - Z + 0.6))), (1.5, 0.04, 0.9), "Accent")
    pts = []
    n = 16
    for k in range(n + 1):
        f = k / n
        a = radians(-90.0 + 450.0 * f)
        c = base + Vector((-1.4 * cos(a) - 0.9 * f * 2.0, 1.4 * sin(a), top_z - Z + 0.1 - (top_z - WATER_Z - 0.2) * f))
        pts.append(c)
    p.tube(pts, 0.45, seg=8, mat="Accent", smooth=True)
    return base + Vector((0, 0, top_z - Z)), pts[-1]


def loungers(p, n_side=5):
    out = []
    for sy in (-1, 1):
        for k in range(n_side):
            x = POOL_C.x - POOL_L / 2 + 1.8 + k * (POOL_L - 3.6) / (n_side - 1)
            y = POOL_C.y + sy * (POOL_W / 2 + 2.2)
            with p.at(T(x, y, Z), RZ(90.0 * sy)):
                p.box((0, 0, 0.3), (0.7, 1.9, 0.08), "Palette:#e6e3dc")
                p.box((0, -0.75, 0.55), (0.7, 0.5, 0.06), "Palette:#e6e3dc")
                for sx in (-1, 1):
                    p.box((sx * 0.3, 0, 0.15), (0.05, 1.7, 0.3), GRAPHITE)
                p.box((0, 0.1, 0.36), (0.62, 1.2, 0.05), "Palette:#29b6c6" if k % 2 else "Palette:#e07a3a")
            out.append((Vector((x, y, Z)), 90.0 * sy))
            if k % 2 == 1:                                                      # umbrellas between loungers
                c = Vector((x + (POOL_L - 3.6) / (n_side - 1) / 2, y + sy * 0.6, Z))
                p.cyl(c, c + Vector((0, 0, 2.4)), 0.04, seg=4, mat=GRAPHITE, cap0=False)
                with p.at(T(*c)):
                    p.lathe([(1.4, 2.1), (0.0, 2.5)], "Palette:#f2f0ea", seg=8, smooth=False)
                    p.lathe([(0.0, 2.08), (1.4, 2.08)], "Palette:#e07a3a", seg=8, smooth=False)
    return out


def fountain(p, lt, wa):
    c = FOUNTAIN_C + Vector((0, 0, Z))
    with p.at(T(*c)):
        p.lathe([(2.45, 0.0), (2.45, 0.5), (2.2, 0.55), (2.2, 0.2)], WHITE, seg=24, smooth=False)
        p.lathe([(2.2, 0.2), (0.0, 0.2)], "Palette:#2f6fa0", seg=24, smooth=False)
        p.lathe([(0.55, 0.2), (0.4, 1.3), (1.2, 1.35), (1.2, 1.5), (0.3, 1.5), (0.22, 2.3), (0.55, 2.35), (0.55, 2.45),
                 (0.0, 2.45)], WHITE, seg=12, smooth=False)
    with wa.at(T(*c)):
        wa.lathe([(2.2, 0.42), (0.0, 0.42)], "Water", seg=24, smooth=False)
        wa.lathe([(1.15, 1.47), (0.0, 1.47)], "Water", seg=12, smooth=False)
        wa.lathe([(0.12, 2.45), (0.05, 3.4), (0.0, 3.5)], "Water", seg=8)
        for k in range(8):                                                      # arcs of water from the upper bowl
            a = 360.0 * k / 8
            pts = [pol(0.45, a, 2.4), pol(1.0, a, 2.75), pol(1.6, a, 2.2), pol(1.9, a, 0.45)]
            wa.tube(pts, 0.05, seg=4, mat="Water", caps=False, fillet=0.2, fillet_n=2)
    with lt.at(T(*c)):
        for k in range(8):
            q = pol(1.9, 22.5 + 45 * k, 0.22)
            lt.poly([q + Vector((0.12, 0.12, 0)), q + Vector((-0.12, 0.12, 0)), q + Vector((-0.12, -0.12, 0)),
                     q + Vector((0.12, -0.12, 0))], "Light")
    seats = []
    for k in range(6):                                                          # benches round the fountain
        a = 30.0 + 60.0 * k
        q = c + pol(3.6, a)
        D.colony_bench(p, q, a + 180.0)
        seats.append((q, a + 180.0))
    return seats


def park(p, lt):
    """grass strip with a kerb, trees, a path and benches along the ring (bearing PARK_A0..PARK_A1)"""
    n = 18
    for k in range(n):
        a0 = PARK_A0 + (PARK_A1 - PARK_A0) * k / n
        a1 = PARK_A0 + (PARK_A1 - PARK_A0) * (k + 1) / n
        D.sector_prism(p, 13.6, 19.4, a0, a1, Z, Z + 0.28, GRASS, None, WHITE, WHITE, n=1)
    for (a, e) in ((PARK_A0, -1), (PARK_A1, 1)):
        D.sector_prism(p, 13.6, 19.4, a - (0.4 if e < 0 else 0), a + (0.4 if e > 0 else 0), Z, Z + 0.3, WHITE, None, WHITE, WHITE,
                       ends=WHITE, n=1)
    for k in range(9):                                                          # trees
        a = PARK_A0 + 11.0 + k * (PARK_A1 - PARK_A0 - 17.0) / 8          # round 26: clear of the HOTEL sign
        r = 17.4 if k % 2 else 15.4
        D.tree(p, pol(r, a, Z + 0.28), h=5.0 + (k % 3) * 0.8, r=1.6 + (k % 2) * 0.3, seed=k)
    for k in range(6):                                                          # flower beds: leaves + blossoms
        a = PARK_A0 + 10.0 + k * 13.0
        for j in range(3):
            c = pol(14.4, a - 3.0 + 3.0 * j, Z + 0.28)
            D.leaf_cluster(p, c, s=0.45, n=6, seed=k * 3 + j, tilt=0.5)
            for b in range(4):
                q = c + pol(0.22, 90.0 * b + 45.0 * j, 0.22)
                p.box(tuple(q), (0.09, 0.09, 0.07), "Palette:" + ("#e85d75", "#f2c14e", "#b58cff")[(k + b) % 3])
    seats = []
    for k in range(4):
        a = PARK_A0 + 16.0 + k * 18.0
        q = pol(13.1, a, Z)
        D.colony_bench(p, q, a + 180.0)
        seats.append((q, a + 180.0))
    return seats


def stage(p, lt):
    c = pol(STAGE_R, STAGE_A, Z)
    with p.at(T(*c), RZ(STAGE_A + 180.0)):                    # local +X faces the atrium centre
        p.box((0, 0, 0.4), (5.0, 8.0, 0.8), "Palette:#2c3036", mats={"+z": D.WOOD})
        for k in range(3):
            p.box((2.7 + k * 0.3, 0, 0.13 + k * 0.13 - 0.1), (0.3, 3.0, 0.26 + k * 0.26), "Palette:#3a3f47")
        for sy in (-1, 1):                                     # truss towers + top truss
            p.box((-2.0, sy * 3.8, 3.6), (0.4, 0.4, 5.6), GRAPHITE)
        p.box((-2.0, 0, 6.5), (0.5, 8.0, 0.5), GRAPHITE)
        p.box((-2.0, 0, 5.95), (0.06, 6.0, 0.6), "Palette:#3a2f4f")                  # banner under the top truss
        p.box((-1.96, 0, 5.95), (0.03, 5.0, 0.2), "Accent")
    with lt.at(T(*c), RZ(STAGE_A + 180.0)):
        for k in range(6):
            lt.box((-1.7, -3.0 + k * 1.2, 6.15), (0.25, 0.25, 0.25), ("SignMagenta", "SignCyan", "SignAmber")[k % 3])
    return c


def lifts(p, lt, out):
    stops = [D.FLOOR_Z[k] for k in range(5)] + [D.ROOF_Z]
    for i, s in enumerate(D.LIFT_SECTORS):
        a = s * D.SEC
        c = pol(D.R_LIFT, a)
        with p.at(T(c.x, c.y, 0.0), RZ(a)):                # local +X = outwards (to the gallery)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    p.box((sx * 1.2, sy * 1.2, (Z + D.ROOF_Z + 2.8) / 2), (0.14, 0.14, D.ROOF_Z + 2.8 - Z), GRAPHITE)
            for k in range(4):                             # glass sides (gallery side open at the doors: glass anyway)
                ang = 90.0 * k
                with p.at(RZ(ang)):
                    p.poly([Vector((1.2, -1.15, Z)), Vector((1.2, 1.15, Z)), Vector((1.2, 1.15, D.ROOF_Z + 2.8)),
                            Vector((1.2, -1.15, D.ROOF_Z + 2.8))], "Glass")
            for z in stops:
                p.box((0, 0, z - 0.15), (2.54, 2.54, 0.12), GRAPHITE)          # floor bands
                if z > Z + 0.1:
                    p.box((1.2 + (D.R_IN - D.R_LIFT - 1.2) / 2 + 0.1, 0, z - 0.1), (D.R_IN - D.R_LIFT - 1.2 + 0.4, 1.8, 0.2), D.TILE)
            p.box((0, 0, D.ROOF_Z + 2.9), (2.7, 2.7, 0.25), WHITE)                     # machine head
            p.box((1.36, 0, D.ROOF_Z + 2.95), (0.02, 2.0, 0.1), "Accent")
        cab = Node("Lift_%d" % i, Matrix.Translation((c.x, c.y, Z)) @ Matrix.Rotation(radians(a), 4, "Z"), None,
                   {"floor": 1, "stops": [round(z - Z, 3) for z in stops], "axis": "translate local Z (Godot +Y)",
                    "speed_mps": 1.5})
        for sx in (-1, 1):
            for sy in (-1, 1):
                cab.box((sx * 0.95, sy * 0.95, 1.25), (0.08, 0.08, 2.5), "Palette:#c3c9d1")
        cab.box((0, 0, 0.06), (2.0, 2.0, 0.12), "Palette:#6b7078")
        cab.box((0, 0, 2.52), (2.0, 2.0, 0.08), WHITE)
        cab.poly([Vector((-0.8, -0.8, 2.47)), Vector((-0.8, 0.8, 2.47)), Vector((0.8, 0.8, 2.47)), Vector((0.8, -0.8, 2.47))], "Light")
        for k in range(3):                                                     # glass on three sides (door side +X)
            with cab.at(RZ(90.0 + 90.0 * k)):
                cab.poly([Vector((0.95, -0.92, 0.12)), Vector((0.95, 0.92, 0.12)), Vector((0.95, 0.92, 2.45)),
                          Vector((0.95, -0.92, 2.45))], "Glass")
        out.append(cab)
        for k, z in enumerate(stops):
            fl = k + 1 if k < 5 else 6
            out.append(D.anchor("Anchor_Lift_%d_%d" % (i, fl), pol(D.R_IN + 0.6 if z > Z + 0.1 else D.R_LIFT + 1.8, a, z),
                                forward=-pol(1.0, a), floor=fl, lift=i))


ESC_A0, ESC_A1, ESC_R = 153.0, 177.0, 18.9


def escalators(p, lt, out):
    """four stacked escalators (L1-L2, L2-L3, L3-L4, L4-L5) at the atrium edge, alternating direction"""
    for k in range(4):
        z0, z1 = D.FLOOR_Z[k], D.FLOOR_Z[k + 1]
        a_lo, a_hi = (ESC_A0, ESC_A1) if k % 2 == 0 else (ESC_A1, ESC_A0)
        b, t = pol(ESC_R, a_lo, z0), pol(ESC_R, a_hi, z1)
        d = (t - b)
        horiz = Vector((d.x, d.y, 0)).normalized()
        side = Vector((-horiz.y, horiz.x, 0))
        land0, land1 = b - horiz * 1.2, t + horiz * 1.2
        for e0, e1 in ((land0, b), (t, land1)):                                     # landings
            p.beam(e0 + Vector((0, 0, -0.1)), e1 + Vector((0, 0, -0.1)), 1.4, 0.2, "Palette:#8a929c", up=(0, 0, 1))
        for e in (land0, land1):                                                     # bridge to the gallery edge
            if e.z > D.GROUND + 0.5:
                ang = math.degrees(math.atan2(e.y, e.x))
                p.beam(pol(18.3, ang, e.z - 0.1), pol(20.25, ang, e.z - 0.1), 1.4, 0.2, "Palette:#8a929c", up=(0, 0, 1))
        p.beam(b + Vector((0, 0, -0.35)), t + Vector((0, 0, -0.35)), 1.3, 0.6, GRAPHITE, up=(0, 0, 1))   # truss
        n = int(d.length / 0.4)
        for j in range(n):                                                            # step nosings
            q = b + d * ((j + 0.5) / n)
            p.beam(q - side * 0.5 + Vector((0, 0, 0.02)), q + side * 0.5 + Vector((0, 0, 0.02)), 0.05, 0.03, "Palette:#c3c9d1")
        for sy in (-1, 1):                                                            # glass balustrades + rails
            o = side * (sy * 0.62)
            p.poly([b + o, t + o, t + o + Vector((0, 0, 0.95)), b + o + Vector((0, 0, 0.95))], "Glass")
            p.beam(land0 + o + Vector((0, 0, 1.0)), land1 + o + Vector((0, 0, 1.0)), 0.07, 0.06, "Palette:#1c2026")
            lt.beam(b + o + Vector((0, 0, -0.06)), t + o + Vector((0, 0, -0.06)), 0.03, 0.03, "LightStrip")
        out.append(D.anchor("Anchor_Escalator_%d_%d" % (k, 0), land0, forward=horiz, floor=k + 1, escalator=k,
                            to_floor=k + 2))
        out.append(D.anchor("Anchor_Escalator_%d_%d" % (k, 1), land1, forward=horiz, floor=k + 2, escalator=k,
                            to_floor=k + 1))


def build():
    out = [Group("Atrium", None, {"floor": 1, "stage": "fitout_atrium"}), Group("Lifts", None, {"floor": 0, "stage": "structure"})]
    p = Node("Atrium_Ground", None, "Atrium", {"floor": 1, "stage": "fitout_atrium"})
    lt = Node("Atrium_Lamps", None, "Atrium", {"floor": 1, "stage": "fitout_atrium"})
    wa = Node("Atrium_Water", None, "Atrium", {"floor": 1, "stage": "fitout_atrium"})
    plaza(p)
    pool(p, lt, wa)
    top, end = slide(p)
    lounge = loungers(p)
    fseats = fountain(p, lt, wa)
    pseats = park(p, lt)
    sc = stage(p, lt)
    for k, a in enumerate((20.0, 70.0, 160.0, 250.0, 300.0, 340.0)):
        D.lamp_post(p, lt, pol(18.2 if k % 2 else 11.5, a, Z), h=4.4)
        out.append(D.light_anchor("Light_Lamp_A%d" % k, pol(18.2 if k % 2 else 11.5, a, Z + 4.3), (0, 0, -1), "lamp",
                                  colour="#ffc88a", cone=110.0, rng=12.0))
    for k, (dx, dy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):              # palms on the pool deck corners
        D.palm(p, POOL_C + Vector((dx * (POOL_L / 2 + 1.3), dy * (POOL_W / 2 + 1.1), Z)), h=5.2 + 0.6 * k, seed=k)
    for k in range(4):                                                                # underwater light for RENDER
        out.append(D.light_anchor("Light_Pool_%d" % k, POOL_C + Vector((-POOL_L / 2 + 2 + k * (POOL_L - 4) / 3, 0, Z - 0.6)),
                                  (0, 0, 1), "pool", colour="#38d8ff", cone=160.0, rng=9.0))
    # lifeguard chair
    lg = POOL_C + Vector((-POOL_L / 2 - 1.6, -1.0, Z))
    for sx in (-1, 1):
        p.cyl(lg + Vector((sx * 0.3, -0.3, 0)), lg + Vector((sx * 0.3, 0.0, 1.6)), 0.04, seg=4, mat="Palette:#e6e3dc", cap0=False)
    p.box(tuple(lg + Vector((0, 0.05, 1.62))), (0.7, 0.6, 0.08), "Accent")
    out += [p, lt, wa]
    es = Node("Escalators", None, "Lifts", {"floor": 0, "stage": "structure"})
    escalators(es, lt, out)
    out.append(es)
    lf = Node("Lift_Shafts", None, "Lifts", {"floor": 0, "stage": "structure"})
    lifts(lf, lt, out)
    out.append(lf)
    # ---- anchors ----
    for k, (q, yaw) in enumerate(lounge):
        out.append(D.anchor("Anchor_Lounger_%d" % k, q, forward=pol(1.0, yaw + 90.0), floor=1, clip="lounge_pool"))
    for k in range(6):
        x = POOL_C.x - POOL_L / 2 + 2.5 + (k % 3) * (POOL_L - 5.0) / 2
        y = POOL_C.y + (-1.6 if k < 3 else 1.6)
        out.append(D.anchor("Anchor_Swim_%d" % k, (x, y, WATER_Z), forward=(1, 0, 0), floor=1, clip="swim"))
    out.append(D.anchor("Anchor_SlideTop", top, forward=(-1, 0, 0), floor=1))
    out.append(D.anchor("Anchor_SlideEnd", (end.x, end.y, WATER_Z), forward=(-1, 0, 0), floor=1))
    out.append(D.anchor("Anchor_Lifeguard", lg + Vector((0, 0.35, 1.66)), forward=(1, 0, 0), floor=1, clip="sit_idle"))
    for k, (q, yaw) in enumerate(fseats):
        out.append(D.anchor("Anchor_Bench_%d" % k, q, forward=pol(1.0, yaw), floor=1, clip="sit_bench"))
    for k, (q, yaw) in enumerate(pseats):
        out.append(D.anchor("Anchor_Bench_%d" % (k + len(fseats)), q, forward=pol(1.0, yaw), floor=1, clip="sit_bench"))
    out.append(D.anchor("Anchor_Stage", sc + Vector((0, 0, 0.8)), forward=-pol(1.0, STAGE_A), floor=1))
    for k in range(8):
        a = 22.5 + 45.0 * k
        q = pol(9.0, a, Z)
        if in_pool(q.x, q.y, 1.5) or (q - FOUNTAIN_C).length < 4.0:
            continue
        out.append(D.anchor("Anchor_Plaza_%d" % k, q, forward=pol(1.0, a + 180.0), floor=1))
    return out


def main():
    D.build_file("dome_atrium.glb", build, ao={"dist": 1.2, "samples": 12, "skip": ["Atrium_Lamps", "Atrium_Water"]})


if __name__ == "__main__":
    main()
