"""Frontier Habitat 4.0 buildings (docs/V4_DESIGN.md sections 1, 4.2, 5): ART-HAB.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_v4.py -- [--only rover_depot_m,boulder_a]

Output (assets/models/):
  boulder_a .. boulder_f.glb   Rock. 1 m nominal radius, origin at the base centre, base sunk 10 %; RENDER scales
                               them to 2-10 m (a, b slabs; c, d rounded; e split; f stacked).  ~400-700 tris.
  rover_depot_m / _l.glb       Base, Roof, Lights.  A vehicle hangar on an apron: M 2 small-rover bays, L 2 small
                               + 1 medium bay (ART-B's bays), open roll-up doors on +X, a charging post in every
                               bay, a gantry crane, the rover badge on the roof.  Anchor_Bay_<i> per bay (floor,
                               bay centre, local +X = the way out).
  fission_reactor.glb          Base, Roof, Lights.  Containment dome with a radiation trefoil, two cooling
                               towers, a turbine hall, coolant pipes, a hazard fence with red beacons.
  crystal_refinery.glb         Base, Lights.  A ribbed containment vessel with glowing exotic crystal (L4Band),
                               angled blast walls, emergency vent stacks, a hazard ring.
  chemical_plant.glb           Base, Lights.  A bunded tank farm, a distillation column with platforms, a pipe
                               rack, a scrubber stack, green toxic-warning lamps.
  crevice_bridge_s / _l.glb    Base, Lights.  A truss bridge for rovers: deck 4.4 m wide, 10 / 18 m long (span
                               8 / 15 m); Anchor_End_A / _B at the deck ends.
  outpost_core.glb             Base, Lights.  The Outpost Kit core (SIM): a small lander hab on three legs, ramp and
                               hatch on +X, beacon mast, folded solar wing; Anchor_Bed_0..3, Anchor_Stand_0..1,
                               Anchor_Ramp.
"""
import os
import sys
import random
from math import sin, cos, pi, radians, sqrt, atan2, degrees, hypot

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402
from ext_common import Part, Anchor, T, RX, RY, RZ, S, polar   # noqa: E402
from mathutils import Vector, noise                        # noqa: E402
import rooms_identity as RI                                # noqa: E402

# extra icons for the 4.0 buildings (same format as rooms_identity.ICONS)
RI.ICONS.setdefault("rover", [[[(-0.78, -0.30), (0.78, -0.30), (0.78, 0.10), (0.46, 0.14), (0.30, 0.42),
                                (-0.40, 0.42), (-0.62, 0.10), (-0.78, 0.10)]],
                              [RI._circle(0.20, 14, -0.46, -0.36)], [RI._circle(0.20, 14, 0.46, -0.36)]])
RI.ICONS.setdefault("radiation", [[[(0.26 * cos(radians(a)), 0.26 * sin(radians(a))) for a in range(a0, a0 + 61, 10)] +
                                   [(0.78 * cos(radians(a)), 0.78 * sin(radians(a))) for a in range(a0 + 60, a0 - 1, -10)]]
                                  for a0 in (30, 150, 270)] + [[RI._circle(0.16, 14)]])
RI.ICONS.setdefault("crystal", [[[(0.0, 0.78), (0.46, 0.24), (0.0, -0.78), (-0.46, 0.24)],
                                 [(0.0, 0.44), (-0.22, 0.20), (0.0, -0.40), (0.22, 0.20)]]])
RI.ICONS.setdefault("toxic", [[[(0.0, 0.80), (0.74, -0.52), (-0.74, -0.52)],
                               [(0.0, 0.52), (-0.50, -0.36), (0.50, -0.36)]],
                              [[(-0.07, 0.30), (0.07, 0.30), (0.05, -0.08), (-0.05, -0.08)]],
                              [RI._circle(0.07, 10, 0.0, -0.22)]])


def flat(z):
    return lambda x, y: z


# ======================================================================================
# BOULDERS (RENDER request, critic round 18 fix 5)
# ======================================================================================
def _ico(sub=2):
    """Unit icosphere (verts, faces), `sub` subdivisions."""
    t = (1.0 + sqrt(5.0)) / 2.0
    vs = [Vector(v).normalized() for v in ((-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t),
                                           (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1))]
    fs = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
          (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
          (8, 6, 7), (9, 8, 1)]
    for _ in range(sub):
        cache = {}
        nf = []

        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in cache:
                vs.append(((vs[a] + vs[b]) / 2).normalized())
                cache[k] = len(vs) - 1
            return cache[k]
        for (a, b, c) in fs:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        fs = nf
    return vs, fs


def stone(p, c, scale, seed, rough=0.22, facets=0.0, sub=2, flat_base=True, cut=None, mat="Rock"):
    """A weathered stone: an icosphere displaced by low-frequency noise (rounded, lumpy), scaled (sx, sy, sz),
    optionally faceted (planar cuts), the base flattened at -10 % of the height; `cut` = (normal, offset) splits
    it with a plane (the kept side)."""
    vs, fs = _ico(sub)
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    sx, sy, sz = scale
    pts = []
    for v in vs:
        n1 = noise.noise(v * 1.3 + off)
        n2 = noise.noise(v * 3.1 + off * 1.7)
        r = 1.0 + rough * n1 + 0.35 * rough * n2
        q = v * r
        if facets:
            # planar facets: pull points onto a few random planes (a cleaved, slabby look)
            rng = random.Random(seed)
            for _ in range(5):
                nrm = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.4, 1))).normalized()
                d = rng.uniform(0.62, 0.85)
                s_ = q.dot(nrm)
                if s_ > d:
                    q = q - nrm * (s_ - d) * facets
        q = Vector((q.x * sx, q.y * sy, q.z * sz))
        if cut is not None:
            nrm, d = cut
            s_ = q.dot(nrm) - d
            if s_ > 0:
                q = q - nrm * s_
        pts.append(q)
    zmin = min(q.z for q in pts)
    base = zmin + (max(q.z for q in pts) - zmin) * 0.12
    for q in pts:
        if flat_base and q.z < base:
            q.z = base
    lift = -base - 0.10 * (max(q.z for q in pts) - base)       # the base sits 10 % below the origin
    ids = [p.v((c[0] + q.x, c[1] + q.y, c[2] + q.z + lift)) for q in pts]
    for (a, b, d) in fs:
        p.f([ids[a], ids[b], ids[d]], mat, smooth=not facets)


def dust_skirt(p, r, seed, n=18):
    """A low irregular dust skirt round the base (Dust): an outer ring at ground level rising to the stone's foot."""
    rng = random.Random(seed)
    outer, inner = [], []
    for k in range(n):
        a = 2 * pi * k / n
        ro_ = r * rng.uniform(1.25, 1.55)
        ri_ = r * rng.uniform(0.80, 0.90)
        outer.append(p.v((ro_ * cos(a), ro_ * sin(a), -0.02)))
        inner.append(p.v((ri_ * cos(a), ri_ * sin(a), 0.05)))
    for k in range(n):
        j = (k + 1) % n
        p.f([outer[k], outer[j], inner[j], inner[k]], "Dust")


def build_boulder(spec):
    p = Part("Rock")
    v = spec["id"][-1]
    dust_skirt(p, (1.0 if v not in "ab" else 1.05), ord(v))
    if v == "a":                                      # flat slab
        stone(p, (0, 0, 0), (1.15, 0.90, 0.42), 11, rough=0.18, facets=0.9)
    elif v == "b":                                    # tilted slab pair
        stone(p, (0.10, 0, 0), (1.05, 0.80, 0.50), 23, rough=0.20, facets=0.8)
        stone(p, (-0.62, 0.45, -0.05), (0.45, 0.35, 0.30), 29, rough=0.20, facets=0.8, sub=1)
    elif v == "c":                                    # big rounded
        stone(p, (0, 0, 0), (1.0, 0.92, 0.80), 37, rough=0.24, sub=2)
    elif v == "d":                                    # rounded, egg-like with a bump
        stone(p, (0, 0, 0), (1.05, 0.85, 0.95), 41, rough=0.28, sub=2)
    elif v == "e":                                    # split in two
        n = Vector((1.0, 0.25, 0.0)).normalized()
        stone(p, (-0.10, -0.05, 0), (0.95, 0.90, 0.85), 53, rough=0.20, cut=(n, -0.06), sub=2)
        stone(p, (0.18, 0.05, 0), (0.95, 0.90, 0.80), 53, rough=0.20, cut=(-n, -0.06), sub=2)
    else:                                             # stacked
        stone(p, (0, 0, 0), (1.05, 0.95, 0.55), 61, rough=0.20, facets=0.5, sub=2)
        stone(p, (0.12, -0.08, 0.72), (0.55, 0.50, 0.45), 67, rough=0.24, sub=1)
    return [p]


# ======================================================================================
# ROVER DEPOT (V4 section 5; ART-B bays: small 6.5 x 4.4 / door 3.4 x 3.0, medium 10.0 x 5.0 / door 4.0 x 4.4)
# ======================================================================================
def build_depot(spec):
    b, ro, lt = Part("Base"), Part("Roof"), Part("Lights")
    large = spec["id"].endswith("_l")
    bays = [("small", 4.4), ("small", 4.4)] + ([("medium", 5.0)] if large else [])
    wall = 0.30
    depth = 10.9 if large else 7.4
    W = sum(w for _, w in bays) + wall * (len(bays) + 1)
    x0, x1 = (-7.0, -7.0 + depth) if large else (-5.4, -5.4 + depth)
    y0 = -W / 2
    H = 5.3 if large else 4.0
    R = spec["footprint"]
    apron = R - 0.8
    # apron slab with lane chevrons out of each bay and a hazard edge
    b.lathe([(R - 0.25, 0.0), (R - 0.25, 0.06), (R - 0.35, 0.10), (0.0, 0.10)],
            lambda k, i: ("Frame", "Frame", "FloorDark")[k], seg=48, smooth=False)
    z = 0.10
    # the hangar: back wall, side walls, dividers, roof deck
    b.box0((x0 + x1) / 2, y0 + wall / 2, z, depth, wall, H, "Hull", mats={"-z": None})
    b.box0((x0 + x1) / 2, -y0 - wall / 2, z, depth, wall, H, "Hull", mats={"-z": None})
    b.box0(x0 + wall / 2, 0.0, z, wall, W, H, "Hull", mats={"-z": None})
    yy = y0 + wall
    anchors = []
    for i, (kind, bw) in enumerate(bays):
        yc = yy + bw / 2
        door_w, door_h = (3.4, 3.0) if kind == "small" else (4.0, 4.4)
        # front wall pieces round the door, header over it
        for (ya, yb) in ((yy - (wall if i == 0 else 0), yc - door_w / 2), (yc + door_w / 2, yy + bw)):
            if yb > ya + 0.01:
                b.box0(x1 - wall / 2, (ya + yb) / 2, z, wall, yb - ya, H, "Hull", mats={"-z": None})
        b.box0(x1 - wall / 2, yc, z + door_h, wall, door_w, H - door_h, "Hull", mats={"-z": None})
        # hazard-striped jambs and the rolled-up door drum under the header
        for sy in (-1, 1):
            jy = yc + sy * (door_w / 2 + 0.06)
            for k in range(int(door_h / 0.3)):
                b.box((x1 + 0.005, jy, z + 0.15 + 0.3 * k), (0.02, 0.12, 0.28), "Hazard" if k % 2 == 0 else "Rubber",
                      mats={"-x": None})
        b.cyl((x1 - 0.35, yc - door_w / 2, z + door_h - 0.2), (x1 - 0.35, yc + door_w / 2, z + door_h - 0.2), 0.20,
              seg=10, mat="HullDark")
        lt.box((x1 + 0.02, yc, z + door_h + 0.25), (0.02, door_w * 0.6, 0.10), "BeaconAmber", mats={"-x": None})
        # bay floor: hazard edge lines, a parking box, the charging post at the back wall with cable and light
        bx0, bx1 = x0 + wall + 0.2, x1 - wall - 0.2
        for sy in (-1, 1):
            b.box(((bx0 + bx1) / 2, yc + sy * (bw / 2 - 0.25), z + 0.004), (bx1 - bx0, 0.08, 0.008), "Hazard",
                  mats={"-z": None})
        b.box((bx0 + 0.3, yc, z + 0.004), (0.08, bw - 0.6, 0.008), "Hazard", mats={"-z": None})
        px, py = x0 + wall + 0.35, yc - bw / 2 + 0.55
        b.box0(px, py, z, 0.40, 0.40, 1.55, "HullDark", bevel=0.03)
        b.box((px + 0.21, py, z + 1.25), (0.02, 0.26, 0.16), "Screen", mats={"-x": None})
        lt.box((px + 0.215, py, z + 1.45), (0.02, 0.20, 0.05), "StatusGreen", mats={"-x": None})
        b.tube([(px + 0.2, py, z + 1.0), (px + 0.7, py + 0.1, z + 0.4), (px + 1.3, py + 0.2, z + 0.05)], 0.035,
               seg=5, mat="Rubber", caps=False)
        # tool board and a shelf on the side wall
        b.box((bx0 + 2.2, yc - bw / 2 + 0.02 + (0.0 if i else wall * 0), z + 1.5), (1.6, 0.03, 0.9), "Frame",
              mats={"-y": None})
        # bay light strip under the roof
        lt.box(((bx0 + bx1) / 2, yc, z + H - 0.08), (bx1 - bx0 - 0.6, 0.18, 0.04), "LightStrip", mats={"+z": None})
        # the rover parks on this point, facing out through the door
        anchors.append(Anchor("Bay_%d" % i, ((x0 + x1) / 2 - 0.3, yc, z), forward=(1, 0, 0)))
        yy += bw + wall
        if i < len(bays) - 1:
            b.box0((x0 + x1) / 2, yy - wall / 2, z, depth, wall, H, "HullDark", mats={"-z": None})
    # critic round 22: bay portal frames with hazard stripes and a status lamp, a family band round the walls, roof
    # ribs, a side annex (office and workshop) on -Y
    yy = y0 + wall
    for kind, bw in bays:
        yc = yy + bw / 2
        door_w, door_h = (3.4, 3.0) if kind == "small" else (4.0, 4.4)
        for sy in (-1, 1):
            b.box0(x1 + 0.12, yc + sy * (door_w / 2 + 0.22), z, 0.24, 0.28, door_h + 0.35, "Frame")
        b.box0(x1 + 0.12, yc, z + door_h + 0.05, 0.24, door_w + 0.72, 0.30, "Frame")
        for k in range(int((door_w + 0.6) / 0.4)):
            yk = yc - door_w / 2 - 0.3 + 0.4 * k + 0.2
            b.box((x1 + 0.245, yk, z + door_h + 0.2), (0.02, 0.2, 0.26), "Hazard" if k % 2 == 0 else "Rubber",
                  mats={"-x": None})
        lt.box((x1 + 0.25, yc + door_w / 2 + 0.22, z + door_h - 0.3), (0.02, 0.16, 0.30), "StatusGreen",
               mats={"-x": None})
        yy += bw + wall
    for (xa, xb, yv, face) in ((x0, x1, y0, "+y"), (x0, x1, -y0, "-y")):
        b.box(((xa + xb) / 2, yv + (0.006 if face == "-y" else -0.006), z + H * 0.62), (xb - xa, 0.012, 0.42),
              "Accent", mats={face: None})
    b.box((x0 - 0.006, 0.0, z + H * 0.62), (0.012, W, 0.42), "Accent", mats={"+x": None})
    nrib = int(depth / 1.2)
    for k in range(nrib + 1):
        xr = x0 + depth * k / nrib
        ro.box0(xr, 0.0, z + H + 0.27, 0.14, W + 0.3, 0.22, "Frame")
    ax, ay = (x0 + x1) / 2 - 0.4, y0 - 1.25
    b.box0(ax, ay, z, 3.2, 2.4, 2.9, "Hull", bevel=0.05, mats={"-z": None})
    b.box0(ax, ay, z + 2.9, 3.4, 2.6, 0.18, "HullDark")
    b.box((ax, ay - 1.21, z + 2.3), (3.0, 0.02, 0.26), "Accent", mats={"+y": None})
    lt.box((ax - 0.5, ay - 1.21, z + 1.5), (1.4, 0.02, 0.6), "Window", mats={"+y": None})
    b.box((ax + 1.0, ay - 1.21, z + 1.0), (0.8, 0.02, 2.0), "HullDark", mats={"+y": None})
    b.box0(ax + 0.6, ay + 0.2, z + 3.08, 0.9, 0.9, 0.45, "HullDark")
    ro.vcyl(ax - 0.9, ay + 0.6, z + 3.08, z + 4.6, 0.04, seg=6, mat="Frame")
    lt.sphere((ax - 0.9, ay + 0.6, z + 4.68), 0.1, "BeaconAmber", seg=6, rings=3)
    # gantry crane over the last bay (repairs)
    yc = y0 + W - wall - bays[-1][1] / 2
    for sx in (x0 + 1.2, x1 - 1.2):
        b.beam((sx, yc - bays[-1][1] / 2 + 0.3, z + H - 0.45), (sx, yc + bays[-1][1] / 2 - 0.3, z + H - 0.45), 0.16,
               0.22, "Hazard")
    b.beam((x0 + 1.2, yc, z + H - 0.30), (x1 - 1.2, yc, z + H - 0.30), 0.18, 0.24, "Frame")
    b.box0((x0 + x1) / 2, yc, z + H - 0.95, 0.5, 0.5, 0.45, "HullDark")
    b.vcyl((x0 + x1) / 2, yc, z + H - 1.8, z + H - 0.95, 0.03, seg=4, mat="Metal", cap0=False)
    # roof deck: parapet, roof lights over each bay, a beacon, the rover badge
    ro.box0((x0 + x1) / 2, 0.0, z + H, depth + 0.3, W + 0.3, 0.25, "HullDark")
    ro.box0((x0 + x1) / 2, 0.0, z + H + 0.25, depth + 0.3, W + 0.3, 0.02, "Frame")
    for sy in (-1, 1):
        ro.box0((x0 + x1) / 2, sy * (W / 2), z + H + 0.25, depth + 0.3, 0.12, 0.18, "Accent")
    ro.box0(x1, 0.0, z + H + 0.25, 0.12, W + 0.3, 0.18, "Accent")
    zr = z + H + 0.27
    yy = y0 + wall
    for kind, bw in bays:
        lt.box((x0 + 1.4, yy + bw / 2, zr + 0.02), (1.2, bw * 0.55, 0.03), "Window", mats={"-z": None})
        yy += bw + wall
    ro.vcyl(x0 + 0.6, y0 + 0.6, zr, zr + 1.3, 0.05, seg=6, mat="Frame")
    lt.sphere((x0 + 0.6, y0 + 0.6, zr + 1.38), 0.12, "BeaconAmber", seg=8, rings=4)
    RI.badge(ro, "rover", (x0 + x1) / 2 + 0.6, 0.0, min(depth, W) * 0.34, flat(zr), lift=0.006)
    # apron chevrons in front of each door, and a personnel door + walkway on the -Y side
    yy = y0 + wall
    for kind, bw in bays:
        yc = yy + bw / 2
        for j in range(3):
            xa = x1 + 1.0 + 1.1 * j
            if xa + 0.6 > apron:
                break
            b.poly([(xa, yc - 0.9, z + 0.004), (xa + 0.55, yc, z + 0.004), (xa + 0.35, yc, z + 0.004),
                    (xa - 0.2, yc - 0.9, z + 0.004)], "Hull")
            b.poly([(xa + 0.35, yc, z + 0.004), (xa + 0.55, yc, z + 0.004), (xa, yc + 0.9, z + 0.004),
                    (xa - 0.2, yc + 0.9, z + 0.004)], "Hull")
        yy += bw + wall
    px = x1 - 1.4
    b.box((px, y0 - 0.02, z + 1.05), (1.0, 0.04, 2.1), "HullDark", mats={"+y": None})
    lt.box((px, y0 - 0.045, z + 2.2), (0.6, 0.02, 0.08), "StatusGreen", mats={"+y": None})
    return [b, ro, lt] + anchors


# ======================================================================================
# FISSION REACTOR (V4 4.2: huge power, a clear danger look)
# ======================================================================================
def cooling_tower(p, x, y, z0, h, r0, rw, r1, seg=20):
    """A hyperbolic cooling tower (thin shell with an inner face), a hazard band and a dark rim."""
    prof_o, prof_i = [], []
    n = 8
    for k in range(n + 1):
        t = k / n
        # hyperboloid-like radius: wide base, waist at 0.7 h, flared top
        tw = 0.72
        r = rw + (r0 - rw) * ((tw - t) / tw) ** 2 if t < tw else rw + (r1 - rw) * ((t - tw) / (1 - tw)) ** 2
        prof_o.append((r, z0 + h * t))
        prof_i.append((r - 0.18, z0 + h * t))
    with p.at(T(x, y, 0)):
        p.lathe(prof_o, "Hull", seg=seg, caps=False)
        p.lathe(list(reversed(prof_i)), "HullDark", seg=seg, caps=False)
        p.lathe([(prof_o[-1][0], prof_o[-1][1]), (prof_o[-1][0] + 0.06, prof_o[-1][1] + 0.12),
                 (prof_i[-1][0], prof_i[-1][1] + 0.12), (prof_i[-1][0], prof_i[-1][1])], "Frame", seg=seg, caps=False)
        p.lathe([(r0 * 1.0 + 0.02, z0 + 1.0), (r0 * 0.96 + 0.02, z0 + 1.6)], "Hazard", seg=seg, caps=False)
        for k in range(8):                            # legs at the base
            a = radians(360.0 * k / 8)
            p.beam((r0 * cos(a), r0 * sin(a), z0), ((r0 - 0.3) * cos(a), (r0 - 0.3) * sin(a), z0 + 0.9), 0.18, 0.18,
                   "Frame")
    return z0 + h + 0.12


def hazard_fence(p, lt, r, z, n=28, h=1.4, gap=None):
    """A fence ring of posts and two rails with hazard panels; red lamps on every 4th post."""
    for k in range(n):
        a0 = 360.0 * k / n
        if gap and any(abs(((a0 - g + 180) % 360) - 180) < w for g, w in gap):
            continue
        x, y, _ = polar(r, a0)
        p.vcyl(x, y, z, z + h, 0.05, seg=6, mat="Frame")
        if k % 4 == 0:
            lt.sphere((x, y, z + h + 0.08), 0.08, "Light", seg=6, rings=3)
        a1 = 360.0 * (k + 1) / n
        if gap and any(abs(((a1 - g + 180) % 360) - 180) < w for g, w in gap):
            continue
        x1, y1, _ = polar(r, a1)
        for zz in (z + 0.5, z + h - 0.1):
            p.cyl((x, y, zz), (x1, y1, zz), 0.03, seg=4, mat="Metal", cap0=False, cap1=False)
        mx, my = (x + x1) / 2, (y + y1) / 2
        p.poly([(x, y, z + 0.55), (x1, y1, z + 0.55), (x1, y1, z + 0.95), (x, y, z + 0.95)],
               "Hazard" if k % 2 == 0 else "Rubber")
        p.poly([(x, y, z + 0.95), (x1, y1, z + 0.95), (x1, y1, z + 0.55), (x, y, z + 0.55)],
               "Hazard" if k % 2 == 0 else "Rubber")


def build_reactor(spec):
    b, ro, lt = Part("Base"), Part("Roof"), Part("Lights")
    R = spec["footprint"]
    z = 0.10
    b.lathe([(R - 0.3, 0.0), (R - 0.3, 0.06), (R - 0.4, 0.10), (0.0, 0.10)],
            lambda k, i: ("Frame", "Frame", "FloorDark")[k], seg=64, smooth=False)
    # the containment building: a ribbed concrete drum with a hemispherical dome
    rc, hc = 4.6, 6.0
    b.lathe([(rc + 0.45, z), (rc + 0.45, z + 0.6), (rc, z + 0.7), (rc, z + hc)],
            lambda k, i: ("HullDark", "Frame", "Hull")[k], seg=32, smooth=True)
    for k in range(16):
        a = 360.0 * k / 16
        x_, y_, _ = polar(rc + 0.10, a)
        b.box0(x_, y_, z + 0.7, 0.30, 0.30, hc - 0.9, "HullDark", mats={"-z": None})
    b.lathe([(rc + 0.06, z + 2.0), (rc + 0.06, z + 2.7)], lambda k, i: "Hazard" if i % 2 == 0 else "Rubber",
            seg=32, caps=False, smooth=False)
    prof = [(rc * cos(radians(t)), z + hc + rc * 0.95 * sin(radians(t))) for t in range(0, 91, 10)]
    ro.lathe(prof, "Hull", seg=32)
    ztop = z + hc + rc * 0.95
    RI.badge(ro, "radiation", 0.0, 0.0, 2.3, lambda x, y: z + hc + rc * 0.95 * sqrt(max(0.0, 1 - (x * x + y * y) / rc ** 2)),
             lift=0.03, rot=0.0)
    ro.vcyl(0, 0, ztop - 0.1, ztop + 1.2, 0.06, seg=6, mat="Frame")
    lt.sphere((0, 0, ztop + 1.3), 0.16, "Light", seg=8, rings=4)
    # trefoil signs on the drum (flat plates facing out)
    for a in (40.0, 160.0, 280.0):
        x_, y_, _ = polar(rc + 0.26, a)
        with ro.at(T(x_, y_, z + 4.3), RZ(a), RY(-90.0)):
            RI.badge(ro, "radiation", 0.0, 0.0, 0.9, flat(0.0), lift=0.0, rot=90.0)
    # cooling towers
    top = ztop + 1.4
    for (tx, ty) in ((-6.9, 5.4), (-6.9, -5.4)):
        top = max(top, cooling_tower(b, tx, ty, z, 10.5, 2.6, 1.7, 2.1))
    # turbine hall and coolant pipes to the towers
    b.box0(6.8, 0.0, z, 4.0, 7.0, 4.2, "Hull", bevel=0.06, mats={"-z": None})
    b.box0(6.8, 0.0, z + 4.2, 4.2, 7.2, 0.25, "HullDark")
    b.box((8.81, 0.0, z + 2.8), (0.02, 5.6, 0.14), "Accent", mats={"-x": None})
    lt.box((8.82, 0.0, z + 3.3), (0.02, 4.2, 0.35), "Window", mats={"-x": None})
    for sy in (-1, 1):
        b.tube([(rc + 0.3, sy * 1.2, z + 1.6), (4.8, sy * 1.2, z + 1.6)], 0.28, seg=8, mat="Metal", caps=False)
        b.tube([(-rc - 0.2, sy * 2.0, z + 1.2), (-5.4, sy * 3.6, z + 1.2), (-5.4, sy * 3.6, z + 2.8)], 0.30, seg=8,
               mat="Metal", caps=False)
        b.box((-rc - 0.9, sy * 2.6, z + 1.2), (0.6, 0.6, 0.35), "Hazard")
    # coolant tanks
    for (cx, cy) in ((3.8, 6.2), (5.4, 6.8)):
        b.vcyl(cx, cy, z, z + 3.2, 0.7, seg=12, mat="Hull")
        b.vcyl(cx, cy, z + 2.4, z + 2.7, 0.72, seg=12, mat="WaterBlue", cap0=False, cap1=False)
    # the exclusion fence with red lamps, open at the turbine hall road (+X)
    hazard_fence(b, lt, R - 0.9, z, n=40, gap=((0.0, 9.0),))
    # warning lamps on the drum
    for a in (0.0, 90.0, 180.0, 270.0):
        x_, y_, _ = polar(rc + 0.5, a)
        lt.sphere((x_, y_, z + hc + 0.2), 0.14, "Light", seg=8, rings=4)
    # painted hazard ring on the ground round the drum
    b.ring_flat(rc + 0.9, rc + 1.3, z + 0.004, "Hazard", seg=48)
    return [b, ro, lt]


# ======================================================================================
# EXOTIC CRYSTAL REFINERY (V4 4.2: unstable, fire or explosion on power loss)
# ======================================================================================
def build_crystal(spec):
    b, lt = Part("Base"), Part("Lights")
    R = spec["footprint"]
    z = 0.10
    b.lathe([(R - 0.25, 0.0), (R - 0.25, 0.06), (R - 0.35, 0.10), (0.0, 0.10)],
            lambda k, i: ("Frame", "Frame", "FloorDark")[k], seg=48, smooth=False)
    b.ring_flat(R - 1.2, R - 0.8, z + 0.004, "Hazard", seg=48)
    # the containment vessel: heavy ribbed cylinder, glass window bands, domed cap with a vent
    rv, hv = 2.2, 4.6
    b.lathe([(rv + 0.5, z), (rv + 0.5, z + 0.5), (rv, z + 0.6)], lambda k, i: ("HullDark", "Frame")[k], seg=24)
    for j, (z0, z1) in enumerate(((0.6, 1.5), (1.5, 2.1), (2.1, 3.0), (3.0, 3.6), (3.6, hv))):
        mat = "Glass" if j in (1, 3) else "HullDark"
        b.lathe([(rv, z + z0), (rv, z + z1)], mat, seg=24, caps=False)
    for k in range(12):
        a = 360.0 * k / 12
        x_, y_, _ = polar(rv + 0.12, a)
        b.box0(x_, y_, z + 0.6, 0.26, 0.30, hv - 0.6, "Frame", mats={"-z": None})
    b.lathe([(rv + 0.1, z + hv), (rv * 0.7, z + hv + 0.8), (0.4, z + hv + 1.1)], "Hull", seg=24)
    b.vcyl(0, 0, z + hv + 1.0, z + hv + 2.2, 0.3, seg=10, mat="Metal")
    b.vcyl(0, 0, z + hv + 2.0, z + hv + 2.25, 0.34, seg=10, mat="Hazard", cap0=False, cap1=False)
    # the glowing crystal cluster inside (seen through the window bands)
    rng = random.Random(5)
    for k in range(9):
        a = rng.uniform(0, 360)
        rr = rng.uniform(0.0, 1.3)
        cx, cy, _ = polar(rr, a)
        h = rng.uniform(1.4, 3.2)
        tilt = rng.uniform(-18, 18)
        with lt.at(T(cx, cy, z + 0.6), RZ(a), RY(tilt)):
            lt.lathe([(0.0, 0.0), (0.26, 0.2), (0.22, h * 0.8), (0.0, h)], "L4Band", seg=6, smooth=False)
    # angled blast walls on four sides, emergency vent stacks with red lamps, a control booth
    for a in (45.0, 135.0, 225.0, 315.0):
        with b.at(RZ(a)):
            r0, r1 = rv + 2.3, rv + 2.9
            b.poly([(r0, -1.6, z), (r0, 1.6, z), (r1, 1.6, z + 2.6), (r1, -1.6, z + 2.6)], "HullDark")
            b.poly([(r1, -1.6, z + 2.6), (r1, 1.6, z + 2.6), (r0, 1.6, z), (r0, -1.6, z)], "Frame")
            for k in range(4):
                b.poly([(r0 - 0.01, -1.6 + 0.8 * k, z + 0.1), (r0 - 0.01, -1.2 + 0.8 * k, z + 0.1),
                        (r0 + 0.07, -1.2 + 0.8 * k, z + 0.5), (r0 + 0.07, -1.6 + 0.8 * k, z + 0.5)],
                       "Hazard" if k % 2 == 0 else "Rubber")
    top = z + hv + 2.3
    for a in (0.0, 180.0):
        x_, y_, _ = polar(rv + 1.3, a + 90.0)
        b.vcyl(x_, y_, z, z + 5.6, 0.22, seg=8, mat="Metal")
        b.vcyl(x_, y_, z + 5.0, z + 5.25, 0.25, seg=8, mat="Hazard", cap0=False, cap1=False)
        lt.sphere((x_, y_, z + 5.75), 0.14, "Light", seg=8, rings=4)
        top = max(top, z + 5.9)
    b.box0(R - 2.4, 0.0, z, 1.6, 2.0, 2.4, "Hull", bevel=0.05)
    b.box((R - 1.59, 0.0, z + 0.9), (0.02, 1.8, 0.16), "Accent", mats={"-x": None})
    lt.box((R - 1.59, 0.0, z + 1.6), (0.02, 1.4, 0.5), "Window", mats={"-x": None})
    RI.badge(b, "crystal", R - 2.4, 0.0, 0.75, flat(z + 2.4), lift=0.01, rot=0.0)
    for k in range(3):
        a = 120.0 * k + 60.0
        x_, y_, _ = polar(rv + 0.55, a)
        lt.box((x_, y_, z + 0.4), (0.25, 0.25, 0.08), "L4Band")
    return [b, lt]


# ======================================================================================
# CHEMICAL PLANT (V4 4.2: toxic leak)
# ======================================================================================
def build_chemical(spec):
    b, lt = Part("Base"), Part("Lights")
    R = spec["footprint"]
    z = 0.10
    b.lathe([(R - 0.25, 0.0), (R - 0.25, 0.06), (R - 0.35, 0.10), (0.0, 0.10)],
            lambda k, i: ("Frame", "Frame", "FloorDark")[k], seg=48, smooth=False)
    # the bunded tank farm on -X: a low wall round three tanks (one a sphere)
    bx, bw, bd = -3.4, 5.6, 7.2
    for (cx, cy, sx, sy) in ((bx, bd / 2, bw, 0.2), (bx, -bd / 2, bw, 0.2), (bx - bw / 2, 0, 0.2, bd),
                             (bx + bw / 2, 0, 0.2, bd)):
        b.box0(cx, cy, z, sx, sy, 0.7, "HullDark")
    b.box0(bx, 0, z, bw - 0.2, bd - 0.2, 0.02, "Rubber")
    for (cx, cy, r, h, band) in ((bx - 1.2, 2.0, 1.1, 3.4, "Glow"), (bx - 1.2, -2.0, 1.1, 3.4, "Hazard")):
        b.vcyl(cx, cy, z, z + h, r, seg=14, mat="Hull")
        b.vcyl(cx, cy, z + h - 0.9, z + h - 0.6, r + 0.02, seg=14, mat=band, cap0=False, cap1=False)
        b.hemi((cx, cy, z + h), r, "Hull", seg=14, rings=3)
    b.sphere((bx + 1.3, 0.0, z + 1.9), 1.4, "Hull", seg=16, rings=8)
    for k in range(4):
        a = radians(45 + 90 * k)
        b.beam((bx + 1.3 + 1.2 * cos(a), 1.2 * sin(a), z), (bx + 1.3 + 1.0 * cos(a), 1.0 * sin(a), z + 1.6), 0.14,
               0.14, "Frame")
    # the distillation column with platforms, a ladder and a flare/scrubber stack
    cx, cy = 2.6, 2.2
    b.vcyl(cx, cy, z, z + 8.5, 0.6, seg=12, mat="Metal")
    with b.at(T(cx, cy, 0.0)):
        for zz in (2.2, 4.4, 6.6):                    # platforms with a hand rail
            b.lathe([(0.62, z + zz - 0.08), (1.2, z + zz - 0.08), (1.2, z + zz), (0.62, z + zz)], "Frame", seg=12)
            b.lathe([(1.18, z + zz + 0.95), (1.22, z + zz + 0.95)], "Hazard", seg=12, caps=False)
            for k in range(6):
                a_ = radians(60.0 * k)
                b.cyl((1.2 * cos(a_), 1.2 * sin(a_), z + zz), (1.2 * cos(a_), 1.2 * sin(a_), z + zz + 1.0), 0.025,
                      seg=4, mat="Frame", cap0=False, cap1=False)
        b.box0(0.66, 0.0, z, 0.06, 0.45, 8.0, "Frame")
    b.vcyl(cx, cy, z + 8.5, z + 8.9, 0.4, seg=12, mat="Frame")
    lt.sphere((cx, cy, z + 9.05), 0.14, "Glow", seg=8, rings=4)
    sx, sy = 3.6, -3.4
    b.vcyl(sx, sy, z, z + 7.2, 0.35, 0.28, seg=10, mat="Metal")
    b.vcyl(sx, sy, z + 6.4, z + 6.7, 0.32, seg=10, mat="Hazard", cap0=False, cap1=False)
    lt.sphere((sx + 0.3, sy, z + 7.35), 0.12, "Light", seg=6, rings=3)
    # pipe rack between the farm and the column
    for xx in (-0.3, 1.0):
        for sy_ in (-2.8, 2.8):
            b.box0(xx, sy_, z, 0.14, 0.14, 2.6, "Frame")
        b.beam((xx, -2.8, z + 2.5), (xx, 2.8, z + 2.5), 0.12, 0.12, "Frame")
    for k, (yy, m) in enumerate(((-0.6, "Metal"), (0.0, "Glow"), (0.6, "Hazard"))):
        b.cyl((bx + bw / 2, yy, z + 2.7), (cx - 0.6, yy + 1.2, z + 2.7), 0.10, seg=6, mat=m, cap0=False, cap1=False)
    # the control hut with the toxic sign and green warning lamps round the site
    b.box0(R - 2.6, -1.0, z, 1.8, 2.4, 2.4, "Hull", bevel=0.05)
    b.box((R - 1.69, -1.0, z + 0.9), (0.02, 2.2, 0.16), "Accent", mats={"-x": None})
    lt.box((R - 1.69, -1.0, z + 1.6), (0.02, 1.6, 0.5), "Window", mats={"-x": None})
    RI.badge(b, "toxic", R - 2.6, -1.0, 0.8, flat(z + 2.4), lift=0.01, rot=0.0)
    for a in range(0, 360, 60):
        x_, y_, _ = polar(R - 0.8, a + 30)
        b.vcyl(x_, y_, z, z + 1.8, 0.05, seg=6, mat="Frame")
        lt.sphere((x_, y_, z + 1.9), 0.1, "Glow", seg=6, rings=3)
    b.ring_flat(R - 1.35, R - 1.05, z + 0.004, "Hazard", seg=48)
    return [b, lt]


# ======================================================================================
# CREVICE BRIDGE (V4 section 1: crevices 3-15 m wide; rovers cross on bridges)
# ======================================================================================
def build_bridge(spec):
    b, lt = Part("Base"), Part("Lights")
    L = 18.0 if spec["id"].endswith("_l") else 10.0
    hw = 2.2
    zd = 0.35
    # abutments on the ground at each end
    for sx in (-1, 1):
        x0 = sx * (L / 2 - 1.0)
        b.box0(x0, 0, 0.0, 2.0, 2 * hw + 0.8, zd, "HullDark", bevel=0.04)
        for sy_ in (-1, 1):
            b.box((x0, sy_ * (hw + 0.41), zd * 0.5), (1.6, 0.02, 0.12), "Accent", mats={"+y" if sy_ < 0 else "-y": None})
        b.box((x0 + sx * 0.99, 0, zd / 2), (0.02, 2 * hw + 0.8, zd), "Hazard", mats={"-x": None} if sx < 0 else {"+x": None})
    # deck: a grating with hazard edges
    b.box0(0, 0, zd - 0.12, L - 0.2, 2 * hw, 0.12, "Frame", mats={"-z": "HullDark"})
    for k in range(int(L / 0.5)):
        xx = -L / 2 + 0.3 + 0.5 * k
        b.box((xx, 0, zd + 0.004), (0.06, 2 * hw - 0.4, 0.008), "Metal", mats={"-z": None})
    for sy in (-1, 1):
        b.box((0, sy * (hw - 0.12), zd + 0.004), (L - 0.4, 0.16, 0.008), "Hazard", mats={"-z": None})
    # Warren trusses on both sides
    th = 1.8 if L > 12 else 1.3
    n = int(L / 2.0)
    for sy in (-1, 1):
        y = sy * (hw + 0.1)
        b.beam((-L / 2 + 0.4, y, zd), (L / 2 - 0.4, y, zd), 0.18, 0.24, "Frame")
        b.beam((-L / 2 + 0.4 + L / n / 2, y, zd + th), (L / 2 - 0.4 - L / n / 2, y, zd + th), 0.16, 0.20, "Frame")
        for k in range(n):
            xa = -L / 2 + 0.4 + (L - 0.8) * k / n
            xb = -L / 2 + 0.4 + (L - 0.8) * (k + 0.5) / n
            xc = -L / 2 + 0.4 + (L - 0.8) * (k + 1) / n
            b.beam((xa, y, zd), (xb, y, zd + th), 0.10, 0.10, "Metal")
            b.beam((xb, y, zd + th), (xc, y, zd), 0.10, 0.10, "Metal")
        # a hand rail at 1 m and end lamps
        b.beam((-L / 2 + 0.4, y - sy * 0.1, zd + 1.0), (L / 2 - 0.4, y - sy * 0.1, zd + 1.0), 0.05, 0.05, "Hazard")
        for sx in (-1, 1):
            lt.sphere((sx * (L / 2 - 0.5), y, zd + th + 0.15 if L > 12 else zd + 1.45), 0.09, "BeaconAmber", seg=6,
                      rings=3)
    # cross bracing under the deck
    for k in range(n + 1):
        xx = -L / 2 + 0.4 + (L - 0.8) * k / n
        b.beam((xx, -hw, zd - 0.14), (xx, hw, zd - 0.14), 0.10, 0.12, "Frame")
    anchors = [Anchor("End_A", (-L / 2, 0.0, zd), forward=(-1, 0, 0)), Anchor("End_B", (L / 2, 0.0, zd))]
    return [b, lt] + anchors


# ======================================================================================
# OUTPOST CORE (SIM request, V4 section 2: the Outpost Kit's deployed lander hab)
# ======================================================================================
def build_outpost(spec):
    b, lt = Part("Base"), Part("Lights")
    zf = 1.2                                          # floor of the hab
    rh, hh = 2.3, 2.6
    # the hab drum on three legs
    prof = [(0.0, zf - 0.35), (rh - 0.2, zf - 0.35), (rh, zf - 0.15), (rh, zf + hh), (rh - 0.4, zf + hh + 0.5),
            (0.8, zf + hh + 0.75), (0.0, zf + hh + 0.78)]
    mats = ["HullDark", "Frame", "Hull", "Hull", "Hull", "Frame"]
    b.lathe(prof, lambda k, i: mats[k], seg=24)
    b.lathe([(rh + 0.02, zf + 1.3), (rh + 0.02, zf + 1.55)], "Accent", seg=24, caps=False)
    for k in range(6):                                # window strip (lit)
        a = 60.0 * k + 30.0
        if abs(((a + 180) % 360) - 180) < 40:
            continue
        x_, y_, _ = polar(rh + 0.015, a)
        with lt.at(T(x_, y_, zf + 1.9), RZ(a)):
            lt.box((0.0, 0.0, 0.0), (0.02, 0.8, 0.35), "Window", mats={"-x": None})
    for k in range(3):
        a = 120.0 * k + 60.0
        with b.at(RZ(a)):
            b.cyl((rh - 0.3, 0, zf - 0.2), (3.7, 0, 0.25), 0.12, seg=8, mat="Metal")
            b.cyl((rh - 0.6, 0, zf + 0.4), (3.2, 0, 0.6), 0.08, seg=6, mat="Frame")
            with b.at(T(3.75, 0, 0)):
                b.lathe([(0.55, 0.0), (0.55, 0.08), (0.28, 0.2), (0.0, 0.22)], "Frame", seg=10)
    # ramp and hatch on +X
    b.box((rh + 0.02, 0, zf + 0.95), (0.06, 1.1, 1.9), "HullDark", mats={"-x": None})
    b.box((rh + 0.05, 0, zf + 2.0), (0.04, 1.3, 0.12), "Hazard", mats={"-x": None})
    b.poly([(rh, -0.6, zf - 0.05), (rh, 0.6, zf - 0.05), (4.3, 0.6, 0.05), (4.3, -0.6, 0.05)], "Frame")
    b.poly([(4.3, -0.6, 0.02), (4.3, 0.6, 0.02), (rh, 0.6, zf - 0.08), (rh, -0.6, zf - 0.08)], "HullDark")
    for sy in (-1, 1):
        b.beam((rh, sy * 0.62, zf + 0.9), (4.2, sy * 0.62, 0.95), 0.04, 0.04, "Hazard")
    lt.box((rh + 0.06, 0, zf + 2.15), (0.02, 0.6, 0.06), "StatusGreen", mats={"-x": None})
    # critic round 22: a lit ring deck round the hab (struts, a rail, a LightStrip rim) and a flag mast
    rd0, rd1 = rh + 0.02, rh + 1.25
    b.lathe([(rd1, zf - 0.42), (rd1, zf - 0.30), (rd0, zf - 0.30), (rd0, zf - 0.42)], "Frame", seg=24, caps=False)
    b.lathe([(rd0, zf - 0.30), (rd1, zf - 0.30)], "FloorDark", seg=24, caps=False) if False else None
    b.lathe([(rd1, zf - 0.30), (rd0, zf - 0.30)], "FloorDark", seg=24, caps=False)
    lt.lathe([(rd1 + 0.01, zf - 0.40), (rd1 + 0.01, zf - 0.33)], "LightStrip", seg=24, caps=False)
    for k in range(12):
        a_ = 30.0 * k + 15.0
        if abs(((a_ + 180) % 360) - 180) < 20:
            continue
        x_, y_, _ = polar(rd1 - 0.05, a_)
        b.vcyl(x_, y_, zf - 0.30, zf + 0.75, 0.025, seg=4, mat="Metal", cap0=False)
        x2, y2, _ = polar(rd1 - 0.05, a_ + 30.0)
        if abs(((a_ + 30.0 + 180) % 360) - 180) >= 20:
            b.cyl((x_, y_, zf + 0.75), (x2, y2, zf + 0.75), 0.025, seg=4, mat="Hazard", cap0=False, cap1=False)
        x3, y3, _ = polar(rh - 0.2, a_)
        b.cyl((x_, y_, zf - 0.42), (x3 * 0.9, y3 * 0.9, zf - 1.1), 0.05, seg=5, mat="Frame")
    fx, fy = polar(rd1 - 0.1, 200.0)[:2]
    b.vcyl(fx, fy, zf - 0.30, zf + 5.2, 0.05, seg=6, mat="Metal")
    b.sphere((fx, fy, zf + 5.25), 0.07, "Frame", seg=6, rings=3)
    b.box((fx, fy - 0.62, zf + 4.8), (0.02, 1.2, 0.7), "Accent")
    lt.sphere((fx, fy, zf + 5.35), 0.07, "BeaconAmber", seg=6, rings=3)
    # beacon mast and the folded solar wing
    b.vcyl(-0.6, 0.9, zf + hh + 0.6, zf + hh + 2.4, 0.05, seg=6, mat="Frame")
    lt.sphere((-0.6, 0.9, zf + hh + 2.5), 0.12, "BeaconAmber", seg=8, rings=4)
    with b.at(T(-rh - 0.25, -0.4, zf + 0.9), RZ(0.0)):
        b.box0(0, 0, 0, 0.4, 1.6, 1.6, "Frame")
        for k in range(4):
            b.box((-0.21 + 0.0, 0, 0.1 + 0.37 * k + 0.18), (0.02, 1.5, 0.33), "Solar", mats={"+x": None})
    # inside: four bunks round the wall, two stand points (anchors only; the hull is closed)
    anchors = []
    for i, a in enumerate((70.0, 140.0, 220.0, 290.0)):
        x_, y_, _ = polar(rh - 0.75, a)
        anchors.append(Anchor("Bed_%d" % i, (x_, y_, zf), forward=(-cos(radians(a)), -sin(radians(a)), 0)))
    anchors.append(Anchor("Stand_0", (0.6, 0.5, zf), forward=(-1, 0, 0)))
    anchors.append(Anchor("Stand_1", (0.6, -0.5, zf), forward=(-1, 0, 0)))
    anchors.append(Anchor("Ramp", (4.3, 0.0, 0.05), forward=(1, 0, 0)))
    return [b, lt] + anchors


# ======================================================================================
# HIGH-END EXTERIORS (SIM list 2026-09-27): fuel rod plant, He-3 separator, graphene reactor
# ======================================================================================
def _apron(b, R):
    b.lathe([(R - 0.25, 0.0), (R - 0.25, 0.06), (R - 0.35, 0.10), (0.0, 0.10)],
            lambda k, i: ("Frame", "Frame", "FloorDark")[k], seg=48, smooth=False)
    return 0.10


def build_fuel_rod(spec):
    """A fenced bunker, a centrifuge cascade hall, a radiation trefoil and a hot-cell window."""
    b, ro, lt = Part("Base"), Part("Roof"), Part("Lights")
    R = spec["footprint"]
    z = _apron(b, R)
    bx, by = -1.6, 0.8
    b.prism([(bx - 2.2, by - 1.8), (bx + 2.2, by - 1.8), (bx + 2.0, by + 1.8), (bx - 2.0, by + 1.8)], z, z + 2.4,
            "HullDark", cap1=False)
    ro.box0(bx, by, z + 2.4, 4.2, 3.8, 0.35, "Hull")
    b.box((bx + 2.12, by, z + 1.2), (0.03, 1.2, 0.6), "Glass", mats={"-x": None})
    lt.box((bx + 2.10, by, z + 1.2), (0.02, 1.1, 0.5), "Plasma", mats={"-x": None})
    RI.badge(ro, "radiation", bx, by, 1.5, flat(z + 2.75), lift=0.01, rot=0.0)
    hx, hy = 2.6, -2.2
    b.box0(hx, hy, z, 3.4, 2.6, 2.6, "Hull", bevel=0.05, mats={"-z": None})
    ro.box0(hx, hy, z + 2.6, 3.6, 2.8, 0.12, "Frame")
    lt.box((hx, hy, z + 2.73), (3.0, 0.5, 0.02), "Window", mats={"-z": None})
    for k in range(6):
        cx = hx - 1.25 + 0.5 * k
        for cy in (hy - 0.55, hy + 0.55):
            ro.vcyl(cx, cy, z + 2.72, z + 3.3, 0.14, seg=8, mat="Metal")
    b.box((hx + 1.71, hy, z + 1.9), (0.02, 2.2, 0.14), "Accent", mats={"-x": None})
    b.box0(2.4, 2.6, z, 1.4, 1.0, 0.3, "Frame")
    b.vcyl(2.4, 2.6, z + 0.3, z + 1.6, 0.42, seg=12, mat="Metal")
    b.vcyl(2.4, 2.6, z + 1.2, z + 1.4, 0.44, seg=12, mat="Hazard", cap0=False, cap1=False)
    hazard_fence(b, lt, R - 0.8, z, n=28, gap=((0.0, 14.0),))
    b.ring_flat(R - 1.35, R - 1.1, z + 0.004, "Hazard", seg=48)
    return [b, ro, lt]


def build_he3(spec):
    """Cold-trap tanks with frost, cryo pipes and a vacuum chamber."""
    b, lt = Part("Base"), Part("Lights")
    R = spec["footprint"]
    z = _apron(b, R)
    for k, a in enumerate((110.0, 180.0, 250.0)):
        x_, y_, _ = polar(3.6, a)
        b.vcyl(x_, y_, z, z + 3.6, 0.85, seg=14, mat="Hull")
        b.hemi((x_, y_, z + 3.6), 0.85, "Hull", seg=14, rings=3)
        for zz in (0.5, 1.4, 2.3):
            b.vcyl(x_, y_, z + zz, z + zz + 0.35, 0.87, seg=14, mat="Frost", cap0=False, cap1=False)
        b.tube([(x_, y_, z + 3.2), (x_ * 0.4, y_ * 0.4, z + 3.4), (0.3, 0.0, z + 2.6)], 0.08, seg=6, mat="Frost",
               caps=False)
    with b.at(T(1.2, 0.0, z + 1.3), RY(90.0)):
        b.cyl((0, 0, -1.8), (0, 0, 1.8), 1.0, seg=16, mat="Metal", cap0=False, cap1=False)
        with b.at(T(0, 0, 1.8)):
            b.lathe([(1.0, 0.0), (0.7, 0.5), (0.0, 0.62)], "Metal", seg=16)
        with b.at(T(0, 0, -1.8), RX(180.0)):
            b.lathe([(1.0, 0.0), (0.7, 0.5), (0.0, 0.62)], "Metal", seg=16)
        for k in range(4):
            b.cyl((0.0, 0.95, -1.2 + 0.8 * k), (0.0, 1.25, -1.2 + 0.8 * k), 0.14, seg=8, mat="Frame")
    for sx in (-0.9, 0.9, 2.8):
        b.box0(1.2 + sx - 0.9, 0.0, z, 0.3, 1.8, 0.6, "Frame")
    b.box0(4.2, -1.8, z, 0.9, 0.5, 1.4, "HullDark", bevel=0.03)
    b.box((4.66, -1.8, z + 1.0), (0.02, 0.4, 0.3), "Screen", mats={"-x": None})
    b.box((4.66, -1.8, z + 0.6), (0.02, 0.4, 0.1), "Accent", mats={"-x": None})
    b.vcyl(-1.2, 2.8, z, z + 2.8, 0.2, seg=8, mat="Frost")
    lt.sphere((-1.2, 2.8, z + 2.95), 0.1, "L3Band", seg=6, rings=3)
    for k in range(4):
        b.vcyl(3.8 - 0.45 * k, 2.2, z, z + 0.9, 0.18, seg=10, mat="Accent" if k % 2 else "Hull")
    b.ring_flat(R - 1.1, R - 0.85, z + 0.004, "Hazard", seg=48)
    return [b, lt]


def build_graphene(spec):
    """A vapour-deposition tower with a glowing quartz column."""
    b, lt = Part("Base"), Part("Lights")
    R = spec["footprint"]
    z = _apron(b, R)
    h = 7.0
    for sx in (-0.9, 0.9):
        for sy in (-0.9, 0.9):
            b.vcyl(sx, sy, z, z + h, 0.10, seg=6, mat="Frame")
    for zz in (1.6, 3.2, 4.8, 6.4):
        for (p0, p1) in (((-0.9, -0.9), (0.9, -0.9)), ((0.9, -0.9), (0.9, 0.9)), ((0.9, 0.9), (-0.9, 0.9)),
                         ((-0.9, 0.9), (-0.9, -0.9))):
            b.beam((p0[0], p0[1], z + zz), (p1[0], p1[1], z + zz), 0.08, 0.08, "Frame")
    b.vcyl(0, 0, z + 0.4, z + h - 0.4, 0.45, seg=14, mat="Glass", cap0=False, cap1=False)
    lt.vcyl(0, 0, z + 0.5, z + h - 0.5, 0.22, seg=10, mat="Plasma")
    for zz in (1.0, 2.6, 4.2, 5.8):
        b.vcyl(0, 0, z + zz, z + zz + 0.25, 0.5, seg=14, mat="Accent", cap0=False, cap1=False)
    b.vcyl(0, 0, z, z + 0.4, 0.8, seg=14, mat="HullDark")
    b.vcyl(0, 0, z + h - 0.4, z + h, 0.7, seg=14, mat="HullDark")
    b.vcyl(0, 0, z + h, z + h + 0.9, 0.12, seg=8, mat="Metal")
    lt.sphere((0, 0, z + h + 1.0), 0.12, "Light", seg=6, rings=3)
    for k in range(3):
        x_, y_, _ = polar(3.0, 200.0 + 40.0 * k)
        b.vcyl(x_, y_, z, z + 1.6, 0.35, seg=10, mat="Hull")
        b.vcyl(x_, y_, z + 1.2, z + 1.35, 0.36, seg=10, mat="Hazard", cap0=False, cap1=False)
        b.tube([(x_, y_, z + 1.5), (x_ * 0.4, y_ * 0.4, z + 1.8), (0.0, 0.0, z + 0.4)], 0.05, seg=5, mat="Metal",
               caps=False)
    b.box0(3.2, 1.6, z, 0.8, 1.2, 1.6, "Hull", bevel=0.03)
    b.box((3.61, 1.6, z + 1.1), (0.02, 0.9, 0.4), "Screen", mats={"-x": None})
    b.box((3.61, 1.6, z + 0.6), (0.02, 0.9, 0.1), "Accent", mats={"-x": None})
    b.ring_flat(R - 1.0, R - 0.75, z + 0.004, "Hazard", seg=48)
    return [b, lt]


# ======================================================================================
MODELS = [dict(id="boulder_" + v, kind="prop", footprint=None, accent=None, budget=1400, objects=["Rock"],
               ao=dict(dist=0.8, samples=24), vc_gradient=(0.50, 0.80), builder=build_boulder, zmin=-0.30)
          for v in "abcdef"] + [
    dict(id="rover_depot_m", kind="exterior", footprint=9.0, accent="logistics", budget=9000,
         objects=["Base", "Roof", "Lights"], anchors=["Anchor_Bay_0", "Anchor_Bay_1"], service=False,
         ao=dict(dist=1.2, samples=24), builder=build_depot),
    dict(id="rover_depot_l", kind="exterior", footprint=12.0, accent="logistics", budget=12000,
         objects=["Base", "Roof", "Lights"], anchors=["Anchor_Bay_0", "Anchor_Bay_1", "Anchor_Bay_2"], service=False,
         ao=dict(dist=1.2, samples=24), builder=build_depot),
    dict(id="fission_reactor", kind="exterior", footprint=12.0, accent="utilities", budget=15000,
         objects=["Base", "Roof", "Lights"], service=False, ao=dict(dist=1.4, samples=24), builder=build_reactor),
    dict(id="crystal_refinery", kind="exterior", footprint=8.0, accent="industry", budget=9000,
         objects=["Base", "Lights"], service=False, ao=dict(dist=1.2, samples=24), builder=build_crystal),
    dict(id="chemical_plant", kind="exterior", footprint=9.0, accent="industry", budget=11000,
         objects=["Base", "Lights"], service=False, ao=dict(dist=1.2, samples=24), builder=build_chemical),
    dict(id="crevice_bridge_s", kind="special", footprint=None, accent="logistics", budget=4000,
         objects=["Base", "Lights"], anchors=["Anchor_End_A", "Anchor_End_B"], ao=dict(dist=1.0, samples=20),
         builder=build_bridge),
    dict(id="crevice_bridge_l", kind="special", footprint=None, accent="logistics", budget=6000,
         objects=["Base", "Lights"], anchors=["Anchor_End_A", "Anchor_End_B"], ao=dict(dist=1.0, samples=20),
         builder=build_bridge),
    dict(id="fuel_rod_plant", kind="exterior", footprint=8.0, accent="industry", budget=9000,
         objects=["Base", "Roof", "Lights"], service=False, ao=dict(dist=1.2, samples=24), builder=build_fuel_rod),
    dict(id="he3_separator", kind="exterior", footprint=7.0, accent="industry", budget=9000,
         objects=["Base", "Lights"], service=False, ao=dict(dist=1.2, samples=24), builder=build_he3),
    dict(id="graphene_reactor", kind="exterior", footprint=6.0, accent="industry", budget=7000,
         objects=["Base", "Lights"], service=False, ao=dict(dist=1.2, samples=24), builder=build_graphene),
    dict(id="outpost_core", kind="special", footprint=4.5, accent="logistics", budget=7000,
         objects=["Base", "Lights"], anchors=["Anchor_Bed_0", "Anchor_Bed_1", "Anchor_Bed_2", "Anchor_Bed_3",
                                              "Anchor_Stand_0", "Anchor_Stand_1", "Anchor_Ramp"],
         ao=dict(dist=1.0, samples=24), builder=build_outpost),
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
