"""
Frontier Habitat 2.0 - props: supply_pod, crate_<category>, rock_a .. rock_f, pebbles.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_props.py -- [--only supply_pod,rock_d]

Output (assets/models/):
  supply_pod.glb        Base, Lights (beacon lens). A landed drop pod, 1.65 m, fins, parachute pack, open side hatch
                        with crates; reward piles use it.
  crate_raw.glb         Crate. Ore tub with a heap. crate_material: strapped bar bundle. crate_component: equipment
  crate_material.glb    case. crate_food: insulated food box. crate_medical: white case with a cross.
  crate_component.glb   All 0.45 m. `Cargo` is the surface the game tints with the item colour (medical: the cross).
  crate_food.glb        crate.glb (the v1 name) = crate_component.
  crate_medical.glb
  rock_a .. rock_f.glb  Rock. a boulder pair, b cluster, c slab + shard (a-c have a few OreVein faces, as in v1),
                        d layered rock shelf, e weathered pillars, f ore outcrop with many OreVein faces.
  pebbles.glb           Pebbles. A 2 x 2 m scatter patch of small stones for instancing, origin at the centre.
"""
import os
import sys
import random
from math import sin, cos, pi, radians, sqrt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402
from ext_common import Part, T, RX, RY, RZ, S, polar       # noqa: E402
from mathutils import Vector                               # noqa: E402


# ======================================================================================
# SUPPLY POD
# ======================================================================================
def build_pod(spec):
    b, lt = Part("Base"), Part("Lights")
    prof = [(0.0, 0.02), (0.30, 0.02), (0.52, 0.10), (0.56, 0.22), (0.56, 0.30), (0.56, 0.62), (0.56, 0.72), (0.53, 0.80),
            (0.46, 1.05), (0.40, 1.22), (0.32, 1.32), (0.30, 1.40), (0.0, 1.40)]
    mats = ["HullDark", "HullDark", "Frame", "Accent", "Hull", "Hazard", "Hull", "Hull", "Hull", "Frame", "Frame", "Fabric"]
    b.lathe(prof, lambda k, i: mats[k] if not (k == 5 and i % 2) else "Rubber", seg=16)
    b.lathe([(0.575, 0.28), (0.575, 0.34), (0.555, 0.35)], "Frame", seg=16)
    # parachute pack and a spilled chute on the ground
    b.lathe([(0.29, 1.40), (0.29, 1.52), (0.22, 1.60), (0.0, 1.62)], "Fabric", seg=12)
    for k in range(4):
        with b.at(RZ(45.0 + 90.0 * k)):
            b.box((0.27, 0, 1.46), (0.04, 0.05, 0.16), "Frame")
    chute = [(0.55, 0.60), (1.25, 0.95), (1.55, 0.25), (1.2, -0.45), (0.62, -0.25)]
    b.poly([(x, y, 0.03) for x, y in reversed(chute)], "Fabric")
    b.poly([(x, y, 0.035) for x, y in reversed(chute[:3])], "Hull")
    for (x, y) in chute[1:4]:
        b.beam((0.1, 0.1, 1.45), (x, y, 0.05), 0.012, 0.012, "Frame")
    # four fins
    for k in range(4):
        with b.at(RZ(90.0 * k + 45.0)):
            b.prism_y([(0.50, 0.05), (0.86, 0.02), (0.86, 0.20), (0.52, 0.62)], -0.025, 0.025, "Accent")
            b.box((0.84, 0, 0.04), (0.1, 0.08, 0.06), "Frame")
    # open side hatch (+X) with crates inside, hatch door on the ground
    b.box((0.54, 0.0, 0.52), (0.06, 0.52, 0.44), "Rubber")
    b.box0(0.44, 0.0, 0.30, 0.2, 0.46, 0.012, "Frame")
    for (dy, dz, m) in ((-0.12, 0.31, "Cargo"), (0.12, 0.31, "Cargo"), (0.0, 0.53, "Cargo")):
        b.box0(0.5, dy, dz, 0.2, 0.2, 0.2, m)
    door = [(0.62, -0.28, 0.02), (0.62, 0.28, 0.02), (1.08, 0.3, 0.05), (1.08, -0.26, 0.05)]
    b.poly(list(reversed(door)), "Hull")
    b.poly([(x, y, z - 0.02) for x, y, z in door], "Frame")
    # beacon on the shoulder: housing in Base, lens in Lights
    b.vcyl(-0.35, 0.2, 1.1, 1.22, 0.05, seg=6, mat="Frame")
    lt.sphere((-0.35, 0.2, 1.26), 0.055, "Light", seg=6, rings=3)
    b.box((-0.47, -0.2, 0.9), (0.06, 0.16, 0.22), "HullDark")
    return [b, lt]


# ======================================================================================
# CRATES (0.45 m; `Cargo` is tinted by the game)
# ======================================================================================
def build_crate(spec):
    kind = spec["crate"]
    p = Part("Crate")
    if kind == "raw":                                 # ore tub: tapered bin + heap
        p.loft([[(sx * 0.19, sy * 0.19, 0.0) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))],
                [(sx * 0.225, sy * 0.225, 0.30) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))],
                [(sx * 0.19, sy * 0.19, 0.30) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))],
                [(sx * 0.17, sy * 0.17, 0.06) for sx, sy in ((1, -1), (1, 1), (-1, 1), (-1, -1))]],
               lambda k, i: "HullDark" if k == 0 else "Frame", smooth=False, closed=True, cap0=True, cap_mat="Frame")
        p.box((0, 0, 0.21), (0.46, 0.46, 0.05), "Hazard", mats={"+z": None, "-z": None})
        rng = random.Random(3)
        pts = [(rng.uniform(-0.18, 0.18), rng.uniform(-0.18, 0.18), 0.27 + rng.uniform(0, 0.05)) for _ in range(10)]
        pts += [(0.02, 0.0, 0.44), (-0.08, 0.06, 0.40), (0.1, -0.07, 0.39)]
        p.hull(pts, "Cargo")
        for sy in (-1, 1):
            p.beam((-0.12, sy * 0.235, 0.25), (0.12, sy * 0.235, 0.25), 0.03, 0.03, "Metal")
    elif kind == "material":                          # strapped bundle of bars on a pallet
        p.box0(0, 0, 0.0, 0.45, 0.45, 0.06, "Frame")
        for j in range(3):
            for i in range(4):
                y = -0.165 + 0.11 * i
                p.box0(0, y, 0.06 + 0.11 * j, 0.43, 0.10, 0.10, "Cargo", bevel=0.012 if j == 2 else 0.0,
                       mats=None if j == 2 else {"-z": None})
        for x in (-0.13, 0.13):
            p.box((x, 0, 0.225), (0.035, 0.455, 0.345), "Metal", mats={"-z": None, "+z": None})
            p.box((x, 0, 0.395), (0.035, 0.44, 0.012), "Metal", mats={"-z": None})
    elif kind == "component":                         # equipment case with handles and latches
        p.box0(0, 0, 0.0, 0.44, 0.44, 0.40, "Cargo", bevel=0.045)
        p.box((0, 0, 0.30), (0.452, 0.452, 0.03), "Frame", mats={"+z": None, "-z": None})
        p.box0(0, 0, 0.40, 0.36, 0.36, 0.03, "Frame")
        for sy in (-1, 1):
            p.box((0, sy * 0.232, 0.22), (0.16, 0.02, 0.04), "Metal")
            p.box((0.13, sy * 0.232, 0.30), (0.04, 0.02, 0.07), "Frame")
            p.box((-0.13, sy * 0.232, 0.30), (0.04, 0.02, 0.07), "Frame")
        p.box((0.226, 0.12, 0.12), (0.01, 0.05, 0.03), "Light")
        p.box((0.226, -0.06, 0.12), (0.01, 0.14, 0.06), "HullDark", mats={"-x": None})
    elif kind == "food":                              # insulated food box: ribbed, lid, vents, green band
        p.box0(0, 0, 0.0, 0.44, 0.44, 0.36, "Cargo", bevel=0.03)
        for k in range(3):
            p.box((0, 0, 0.08 + 0.1 * k), (0.452, 0.452, 0.025), "Frost", mats={"+z": None, "-z": None})
        p.box0(0, 0, 0.36, 0.45, 0.45, 0.07, "Frost", bevel=0.02)
        p.box((0, 0, 0.395), (0.456, 0.456, 0.03), "Accent", mats={"+z": None, "-z": None})
        for k in range(4):
            p.box((0.226, -0.09 + 0.06 * k, 0.28), (0.01, 0.035, 0.08), "Frame", mats={"-x": None})
    else:                                             # medical: white case, the cross is the tinted Cargo
        p.box0(0, 0, 0.0, 0.44, 0.44, 0.40, "Hull", bevel=0.045)
        p.box((0, 0, 0.30), (0.452, 0.452, 0.025), "Frame", mats={"+z": None, "-z": None})
        for (ax, sx) in (("x", 1), ("x", -1), ("y", 1), ("y", -1)):
            if ax == "x":
                p.box((sx * 0.222, 0, 0.17), (0.01, 0.20, 0.06), "Cargo", mats={"-x" if sx > 0 else "+x": None})
                p.box((sx * 0.222, 0, 0.17), (0.01, 0.06, 0.20), "Cargo", mats={"-x" if sx > 0 else "+x": None})
            else:
                p.box((0, sx * 0.222, 0.17), (0.20, 0.01, 0.06), "Cargo", mats={"-y" if sx > 0 else "+y": None})
                p.box((0, sx * 0.222, 0.17), (0.06, 0.01, 0.20), "Cargo", mats={"-y" if sx > 0 else "+y": None})
        p.box((0, 0, 0.402), (0.24, 0.07, 0.006), "Cargo", mats={"-z": None})
        p.box((0, 0, 0.402), (0.07, 0.24, 0.006), "Cargo", mats={"-z": None})
        p.box((0, 0, 0.43), (0.16, 0.04, 0.04), "Frame")
        for sx in (-0.07, 0.07):
            p.box((sx, 0, 0.415), (0.03, 0.03, 0.03), "Frame")
    return [p]


# ======================================================================================
# ROCKS
# ======================================================================================
def boulder(p, rng, cx, cy, rx, ry, rz, n, sink=0.25, veins=0, cuts_n=5, mat="Ore", yaw=0.0):
    """jittered, faceted ellipsoid (convex hull); the flat bottom sits 3 cm in the ground"""
    cuts = []
    for _ in range(cuts_n):
        nz = rng.uniform(0.15, 1.0)
        a = rng.uniform(0.0, 2 * pi)
        s = sqrt(1.0 - nz * nz)
        cuts.append((Vector((s * cos(a), s * sin(a), nz)), rng.uniform(0.55, 0.82)))
    pts = []
    cy_, sy_ = cos(radians(yaw)), sin(radians(yaw))
    for _ in range(n):
        z = rng.uniform(-sink, 1.0)
        a = rng.uniform(0.0, 2 * pi)
        s = sqrt(max(0.0, 1.0 - z * z))
        u = Vector((s * cos(a), s * sin(a), z)) * rng.uniform(0.9, 1.0)
        for cn, cd in cuts:
            t = u.dot(cn) - cd
            if t > 0:
                u -= cn * t
        x, y = rx * u.x, ry * u.y
        pts.append((cx + x * cy_ - y * sy_, cy + x * sy_ + y * cy_, max(rz * u.z, -0.03)))
    if veins:
        nrm = (rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0.3, 1.0))
        p.hull(pts, mat, vein=((cx, cy, rz * rng.uniform(0.35, 0.6)), nrm, max(rx, ry) * 0.12), vein_max=veins)
    else:
        p.hull(pts, mat)


def build_rock(spec):
    rng = random.Random(spec["seed"])
    p = Part("Rock")
    v = spec["id"][-1]
    if v == "a":        # large boulder with a small companion, 2.5 m across
        boulder(p, rng, -0.10, 0.0, 1.10, 0.95, 1.30, 90, veins=4)
        boulder(p, rng, 0.98, -0.55, 0.42, 0.38, 0.45, 30, veins=2)
        boulder(p, rng, -0.9, 0.85, 0.25, 0.22, 0.2, 18)
    elif v == "b":      # cluster of three, 2.6 m across
        boulder(p, rng, -0.45, 0.05, 0.85, 0.80, 1.05, 64, veins=3)
        boulder(p, rng, 0.72, -0.25, 0.60, 0.62, 0.70, 44, veins=2)
        boulder(p, rng, 0.15, 0.85, 0.45, 0.42, 0.50, 30)
    elif v == "c":      # low slab with a leaning shard, 1.4 m
        boulder(p, rng, 0.0, 0.0, 0.72, 0.58, 0.40, 50, veins=2)
        pts = []
        for _ in range(30):
            t = rng.uniform(0.0, 1.0)
            a = rng.uniform(0, 2 * pi)
            w = 0.27 * (1.0 - 0.72 * t) * rng.uniform(0.85, 1.0)
            pts.append((-0.15 + 0.42 * t + w * cos(a), 0.05 + 0.10 * t + w * sin(a), max(-0.03, 1.10 * t)))
        p.hull(pts, "Ore", vein=((0.05, 0.08, 0.62), (0.3, 0.1, 1.0), 0.05), vein_max=2)
    elif v == "d":      # layered rock shelf: three stacked slabs, 3.2 m long
        for k, (h0, h1, rx, ry, dx) in enumerate(((0.0, 0.45, 1.6, 1.05, 0.0), (0.42, 0.78, 1.25, 0.82, -0.18),
                                                  (0.75, 1.02, 0.8, 0.55, -0.35))):
            pts = []
            for _ in range(26):
                a = rng.uniform(0, 2 * pi)
                r = rng.uniform(0.82, 1.0)
                z = rng.choice((h0, h1)) + rng.uniform(-0.03, 0.03)
                pts.append((dx + rx * r * cos(a), ry * r * sin(a) * (1 + 0.15 * cos(a)), max(-0.03, z)))
            p.hull(pts, "Ore",
                   face_mat=(lambda c, n: "OreVein" if (n.z < 0.45 and k == 1) else None))
        boulder(p, rng, 1.35, 0.75, 0.35, 0.3, 0.32, 18)
    elif v == "e":      # weathered pillars, up to 2.2 m tall
        for (x, y, h, r) in ((0.0, 0.0, 2.2, 0.42), (0.55, -0.35, 1.4, 0.32), (-0.45, 0.4, 1.0, 0.3)):
            pts = []
            for _ in range(34):
                t = rng.uniform(0.0, 1.0)
                a = rng.uniform(0, 2 * pi)
                w = r * (1.0 - 0.35 * t + 0.25 * sin(t * 5.0)) * rng.uniform(0.85, 1.0)
                pts.append((x + w * cos(a) + 0.08 * t, y + w * sin(a), max(-0.03, h * t)))
            p.hull(pts, "Ore")
        boulder(p, rng, 0.2, 0.55, 0.3, 0.25, 0.25, 16)
    else:               # ore outcrop: jagged cluster with many OreVein faces
        for (x, y, rx, rz, n) in ((0.0, 0.0, 0.9, 1.05, 60), (0.75, 0.35, 0.5, 0.75, 34), (-0.6, -0.45, 0.55, 0.6, 30),
                                  (0.3, -0.7, 0.35, 0.4, 20)):
            boulder(p, rng, x, y, rx, rx * 0.9, rz, n, veins=5 if n > 30 else 3, yaw=rng.uniform(0, 90))
    return [p]


def build_pebbles(spec):
    rng = random.Random(99)
    p = Part("Pebbles")
    for k in range(34):
        x, y = rng.uniform(-0.95, 0.95), rng.uniform(-0.95, 0.95)
        r = rng.uniform(0.04, 0.13) if k % 5 else rng.uniform(0.12, 0.2)
        pts = [(x + rng.uniform(-r, r), y + rng.uniform(-r, r) * 0.9, rng.uniform(-0.02, r * 0.7)) for _ in range(7)]
        p.hull(pts, "Ore" if k % 4 else "HullDark")
    return [p]


# ======================================================================================
MODELS = [dict(id="supply_pod", kind="prop", footprint=None, accent="logistics", budget=1500, objects=["Base", "Lights"],
               zmin=-0.01, ao=dict(dist=0.3, samples=40), builder=build_pod)]
for kind, acc in (("raw", "industry"), ("material", "industry"), ("component", "industry"), ("food", "food"),
                  ("medical", "medical")):
    MODELS.append(dict(id="crate_" + kind, kind="prop", footprint=None, accent=acc, budget=400, objects=["Crate"],
                       crate=kind, zmin=-0.01, also=["crate"] if kind == "component" else [],
                       ao=dict(dist=0.08, samples=40, min_ao=0.45), builder=build_crate))
for v, seed in zip("abcdef", (11, 23, 37, 41, 53, 67)):
    MODELS.append(dict(id="rock_" + v, kind="prop", footprint=None, accent=None, budget=600, objects=["Rock"], seed=seed,
                       zmin=-0.05, ao=dict(dist=0.6, samples=40, min_ao=0.35), builder=build_rock))
MODELS.append(dict(id="pebbles", kind="prop", footprint=None, accent=None, budget=600, objects=["Pebbles"], zmin=-0.05,
                   ao=dict(dist=0.15, samples=24, min_ao=0.4), builder=build_pebbles))


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
