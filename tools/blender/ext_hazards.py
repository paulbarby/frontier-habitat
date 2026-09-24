"""
Frontier Habitat 3.0 - ART-HAB: meteor defence turret and the meteor hazard props (Blender 5.2, --background only).

Run (project root):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_hazards.py -- [--only meteor_turret,meteor_rock,crater,fragments] [--thumbs]

assets/models/meteor_turret.glb  (content: radius 2.2, category utilities, one size)
  Base      armoured octagonal pedestal with hazard stripes, service hatch on +X, cable conduit, a radar mast with
            a small dish
  Turret    the turning part: a yoke with twin barrels, a sensor head and a cooling jacket.  Its object origin is the
            pivot on the pedestal top (0, 0, 1.30); it rotates about its local Z (Godot Y).  At rest the barrels
            point to +X, raised 20 degrees.
  Lights    status lamp (Light) on the mast and a charge ring (L3Band) round the pedestal top
  Anchor_Service (kneel point, +X side), Anchor_Muzzle (between the barrel tips, for the tracer)
assets/models/meteor_rock.glb   Base: a charred rock with glowing cracks, about 0.9 m (the falling meteor)
assets/models/crater.glb        Base: a crater of RADIUS 1.0 m (the game scales it uniformly to r 4..12 m): a
                                shallow bowl, a raised rim, ejecta blocks and rays; sits on the ground (z >= -0.12)
assets/models/fragments.glb     Base + Lights: a fragment pile, dark rock with violet exotic crystals (Lights:
                                the glowing crystal cores), about 1.6 m across
"""
import os
import sys
import random
from math import sin, cos, pi, radians, sqrt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402
from ext_common import Part, T, RX, RY, RZ, S, polar, Anchor  # noqa: E402
from mathutils import Vector                               # noqa: E402

PIVOT_Z = 1.30


def octagon(r, rot=22.5):
    return [(r * cos(radians(rot + 45 * k)), r * sin(radians(rot + 45 * k))) for k in range(8)]


def build_turret(spec):
    b, t, lt = Part("Base"), Part("Turret", origin=(0.0, 0.0, PIVOT_Z)), Part("Lights")
    # pedestal: stepped octagon with a hazard band, armour plates and a service hatch on +X
    b.prism(octagon(1.75), 0.0, 0.22, "Frame", cap0=False)
    b.prism(octagon(1.45), 0.22, 0.62, "HullDark", cap0=False)
    for k in range(8):
        a = 22.5 + 45 * k
        with b.at(RZ(a), T(1.33, 0, 0)):
            b.box((0.02, 0, 0.42), (0.08, 0.95, 0.30), "Hazard" if k % 2 else "Rubber", mats={"-x": None})
    b.prism(octagon(1.05), 0.62, 1.10, "Hull", cap0=False)
    b.lathe([(1.02, 1.10), (1.02, 1.18), (0.80, 1.22), (0.80, PIVOT_Z - 0.02)], "Frame", seg=16)
    with b.at(T(1.02, 0, 0.0)):
        b.box((0.03, 0, 0.86), (0.06, 0.62, 0.40), "Frame", mats={"-x": None})
        b.box((0.065, 0, 0.86), (0.012, 0.52, 0.30), "Accent", mats={"-x": None})
        b.box((0.07, 0.18, 0.86), (0.012, 0.06, 0.10), "Hazard", mats={"-x": None})
    for k in range(4):
        a = 45.0 + 90.0 * k
        x, y, _ = polar(1.55, a)
        b.box0(x, y, 0.0, 0.30, 0.30, 0.10, "Metal", mats={"-z": None})
    # cable conduit to the ground
    b.tube([(-1.05, -0.3, 0.9), (-1.6, -0.3, 0.9), (-1.9, -0.3, 0.05)], 0.06, seg=6, mat="Rubber", fillet=0.2)
    # radar mast with a small dish and the status lamp
    mx, my = -0.75, 0.75
    b.box0(mx, my, 1.10, 0.18, 0.18, 1.35, "Frame", mats={"-z": None})
    with b.at(T(mx, my, 2.50), RZ(135.0), RY(-25.0)):
        b.lathe([(0.0, 0.0), (0.18, 0.02), (0.34, 0.08), (0.42, 0.14)], "Hull", seg=12)
        b.lathe([(0.42, 0.13), (0.30, 0.05), (0.0, -0.02)], "Frame", seg=12)
        b.beam((0, 0, 0.0), (0, 0, 0.30), 0.03, 0.03, "Frame")
    lt.sphere((mx, my, 2.52 + 0.30), 0.06, "Light", seg=8, rings=4)
    lt.lathe([(1.03, 1.14), (1.03, 1.17), (0.98, 1.17)], "L3Band", seg=16)
    # turret (pivot at the origin of the Turret part): turntable, yoke, cradle, twin barrels, sensor
    with t.at(T(0, 0, PIVOT_Z)):
        t.lathe([(0.78, 0.0), (0.78, 0.10), (0.70, 0.16), (0.0, 0.16)], "Metal", seg=16)
        for sy in (-1, 1):
            with t.at(T(0, sy * 0.42, 0.16)):
                t.convex([(-0.45, -0.07, 0.0), (0.35, -0.07, 0.0), (0.35, 0.07, 0.0), (-0.45, 0.07, 0.0),
                          (0.22, -0.07, 0.62), (-0.30, -0.07, 0.62), (0.22, 0.07, 0.62), (-0.30, 0.07, 0.62)],
                         [(0, 1, 2, 3), (4, 5, 7, 6), (0, 1, 4, 5), (2, 3, 7, 6), (1, 2, 6, 4), (3, 0, 5, 7)],
                         "HullDark")
        with t.at(T(0, 0, 0.66), RY(-20.0)):
            t.box((-0.10, 0, 0.0), (0.95, 0.62, 0.46), "Hull", bevel=0.05)
            t.box((-0.10, 0, 0.24), (0.70, 0.40, 0.05), "Frame")
            t.box((0.20, 0, -0.24), (0.50, 0.50, 0.04), "Accent")
            for sy in (-0.16, 0.16):
                t.cyl((0.36, sy, 0.02), (1.55, sy, 0.02), 0.065, seg=8, mat="Metal")
                t.cyl((0.36, sy, 0.02), (0.80, sy, 0.02), 0.095, seg=8, mat="Frame")
                t.cyl((1.45, sy, 0.02), (1.60, sy, 0.02), 0.085, seg=8, mat="Frame")
            t.box((-0.35, 0.0, 0.34), (0.26, 0.22, 0.18), "Frame")
            t.box((-0.21, 0.0, 0.34), (0.012, 0.16, 0.10), "Screen", mats={"-x": None})
            for k in range(3):
                t.box((-0.45 + 0.10 * k, 0.0, -0.10), (0.04, 0.66, 0.30), "Trim")
    # muzzle point (world) at rest: barrels raised 20 deg
    L = 1.60
    mz = Vector((L * cos(radians(20.0)) - 0.10 * cos(radians(20.0)), 0.0, PIVOT_Z + 0.66 + L * sin(radians(20.0))))
    return [b, t, lt, Anchor("Muzzle", tuple(mz), forward=(cos(radians(20.0)), 0, sin(radians(20.0))))]


def build_meteor_rock(spec):
    """A charred rock split by cracks: the rock is cut into chunks by three planes, every chunk shrunk a little
    toward its own centre, and a glowing core (Window) fills the gaps - the glow is only in the cracks, inside
    the silhouette."""
    b = Part("Base")
    rng = random.Random(7)
    c0 = Vector((0.0, 0.0, 0.45))

    def shell(k, rmin, rmax, seed):
        rr = random.Random(seed)
        out = []
        for _ in range(k):
            u, v = rr.uniform(-1, 1), rr.uniform(0, 2 * pi)
            r = rr.uniform(rmin, rmax)
            w = sqrt(1 - u * u)
            out.append(Vector((r * w * cos(v) * 1.15, r * w * sin(v) * 0.9, r * u * 0.85)) + c0)
        return out
    pts = shell(160, 0.38, 0.45, 7)
    planes = [(Vector((0.9, 0.3, 0.3)).normalized(), 0.04), (Vector((-0.2, 1.0, 0.25)).normalized(), -0.05),
              (Vector((0.3, -0.35, 1.0)).normalized(), 0.08)]
    cells = {}
    for p_ in pts:
        key = tuple(1 if (p_ - c0).dot(nv) > off else 0 for nv, off in planes)
        cells.setdefault(key, []).append(p_)
    # points on the cut planes (inside the rock) so every chunk has a flat broken face
    inner = shell(260, 0.0, 0.40, 9)
    for q in inner:
        for nv, off in planes:
            d = (q - c0).dot(nv) - off
            if abs(d) < 0.03:
                qp = q - nv * d
                for side in (0, 1):
                    key = tuple((side if (nv2 is nv) else (1 if (qp - c0).dot(nv2) > off2 else 0))
                                for nv2, off2 in planes)
                    if key in cells:
                        cells[key].append(qp)
    for key, cp in cells.items():
        if len(cp) < 8:
            continue
        cen = sum(cp, Vector((0, 0, 0))) / len(cp)
        shrunk = [cen + (q - cen) * 0.95 for q in cp]
        b.hull([tuple(q) for q in shrunk], "Ore")
    core = shell(40, 0.30, 0.34, 11)
    b.hull([tuple(q) for q in core], "Ember")
    return [b]


def build_crater(spec):
    """Unit crater: the rim crest at radius 1.0 (RENDER scales it by the sim radius r); a raised rim round a nearly
    flat scorched floor, broad soft ejecta lobes to about 2.1 (the terrain splat of RENDER reaches 2.4), a few
    blocks.  All on the ground.  Non-metal materials only (a metal rim caught the sun as a dashed ring)."""
    b = Part("Base")
    prof = [(1.32, 0.0), (1.14, 0.045), (1.00, 0.11), (0.92, 0.10), (0.80, 0.045), (0.60, 0.016), (0.30, 0.012),
            (0.0, 0.012)]
    # a light sand rim (Wood) round a dark scorched bowl (Soil); the ejecta start dark and end in sand tan
    rim_mats = ["Wood", "Wood", "Wood", "Soil", "Soil", "Soil", "Soil"]
    b.lathe(prof, lambda k, i: rim_mats[k], seg=36, smooth=True)
    rng = random.Random(11)
    n_lobes = 8
    for k in range(n_lobes):
        a = radians(360.0 * k / n_lobes + rng.uniform(-18, 18))
        w = radians(rng.uniform(10.0, 20.0))
        r0, r1 = 1.18, rng.uniform(1.45, 1.95)
        ex = rng.uniform(1.4, 2.8)
        steps = 6
        left, right = [], []
        for t in range(steps + 1):
            f = t / steps
            r = r0 + (r1 - r0) * f
            ww = w * sqrt(max(0.0, 1.0 - f ** ex)) * (r0 / r) + radians(0.5)
            left.append(Vector((r * cos(a - ww), r * sin(a - ww), 0.005)))
            right.append(Vector((r * cos(a + ww), r * sin(a + ww), 0.005)))
        tip = Vector(((r1 + 0.03) * cos(a), (r1 + 0.03) * sin(a), 0.005))
        for t in range(steps):      # dark near the rim, fading to a light tan at the ends
            b.poly([left[t], left[t + 1], right[t + 1], right[t]], "Soil" if t < steps * 0.34 else "Wood")
        b.poly([left[-1], tip, right[-1]], "Wood")
    for k in range(6):
        a = rng.uniform(0, 360)
        r = rng.uniform(1.15, 1.6)
        x, y, _ = polar(r, a)
        s_ = rng.uniform(0.05, 0.10)
        pts = [(x + rng.uniform(-s_, s_), y + rng.uniform(-s_, s_), rng.uniform(0.0, s_ * 0.8)) for _ in range(8)]
        pts += [(x - s_, y - s_, 0.0), (x + s_, y - s_, 0.0), (x + s_, y + s_, 0.0), (x - s_, y + s_, 0.0)]
        b.hull(pts, "Ore")
    return [b]


def build_fragments(spec):
    b, lt = Part("Base"), Part("Lights")
    rng = random.Random(23)
    for k in range(7):
        a = rng.uniform(0, 360)
        r = rng.uniform(0.0, 0.55)
        x, y, _ = polar(r, a)
        s = rng.uniform(0.14, 0.26)
        pts = [(x + rng.uniform(-s, s), y + rng.uniform(-s, s), rng.uniform(0.0, s * 1.3)) for _ in range(9)]
        pts += [(x - s, y - s, 0.0), (x + s, y - s, 0.0), (x + s, y + s, 0.0), (x - s, y + s, 0.0)]
        b.hull(pts, "Ore")
    for k in range(9):
        a = rng.uniform(0, 360)
        r = rng.uniform(0.05, 0.65)
        x, y, _ = polar(r, a)
        h = rng.uniform(0.22, 0.55)
        tilt = rng.uniform(-25, 25)
        with b.at(T(x, y, 0.05), RZ(rng.uniform(0, 360)), RY(tilt)):
            b.prism([(0.05, 0.0), (0.0, 0.045), (-0.05, 0.0), (0.0, -0.045)], 0.0, h, "L4Band", cap0=False)
            b.convex([(0.05, 0, h), (0, 0.045, h), (-0.05, 0, h), (0, -0.045, h), (0, 0, h + 0.10)],
                     [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], "L4Band")
        with lt.at(T(x, y, 0.05), RZ(rng.uniform(0, 360))):
            lt.sphere((0, 0, 0.06), 0.05, "L4Band", seg=6, rings=3)
    return [b, lt]


MODELS = [
    dict(id="meteor_turret", kind="exterior", footprint=2.2, accent="utilities", budget=4500,
         objects=["Base", "Turret", "Lights"], anchors=["Anchor_Muzzle"], ao=dict(dist=0.9, samples=32),
         free={"Turret": 0.0}, builder=build_turret),
    dict(id="meteor_rock", kind="prop", footprint=None, accent=None, budget=600, objects=["Base"],
         ao=dict(dist=0.4, samples=24), builder=build_meteor_rock),
    dict(id="crater", kind="prop", footprint=None, accent=None, budget=900, objects=["Base"], zmin=-0.13,
         ao=dict(dist=0.3, samples=24), builder=build_crater),
    dict(id="fragments", kind="prop", footprint=None, accent=None, budget=1500, objects=["Base", "Lights"],
         ao=dict(dist=0.4, samples=24), builder=build_fragments),
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
        rows.append(C.build_model(spec, spec["builder"]))
    C.write_reports(rows)
    if "--thumbs" in argv:
        import ext_render as R
        R.render_thumb("meteor_turret", "meteor_turret")


if __name__ == "__main__":
    main()
