"""Frontier Habitat 4.0 room identity (docs/V4_DESIGN.md section 3): every family reads differently from the
overview camera without labels.

  1. a family silhouette on the roof and upper wall (see the builders' V4 branches and `family_extras`);
  2. a large roof badge: the family icon in the family colour (Accent, tinted per category by the game) on a
     dark disc with a light rim, draped on the roof (dome or deck), about 0.9 x the room radius across;
  3. a stronger family band (interior_kit.wall_profile_v3 band, taller and proud, with a Neon pin line).

The icons are 2D shapes in a unit circle, triangulated with mathutils.geometry.tessellate_polygon (holes as extra
loops) and subdivided so they follow a curved roof.
"""
from math import sin, cos, radians, pi, sqrt, atan2, degrees, hypot

from mathutils import Vector, geometry

from rooms_kit import T, RX, RZ, WALL_TOP


# --------------------------------------------------------------------------------------
# icon shapes: {family: [shape, ...]}, shape = [outer loop, hole loop, ...], loops CCW, unit circle
# --------------------------------------------------------------------------------------
def _circle(r, n=28, cx=0.0, cy=0.0, a0=0.0):
    return [(cx + r * cos(a0 + 2 * pi * k / n), cy + r * sin(a0 + 2 * pi * k / n)) for k in range(n)]


def _ellipse(a, b, rot, n=36):
    c, s = cos(radians(rot)), sin(radians(rot))
    out = []
    for k in range(n):
        t = 2 * pi * k / n
        x, y = a * cos(t), b * sin(t)
        out.append((c * x - s * y, s * x + c * y))
    return out


def _rot(loop, deg):
    c, s = cos(radians(deg)), sin(radians(deg))
    return [(c * x - s * y, s * x + c * y) for x, y in loop]


def _gear(n=10, ro=0.74, ri=0.56, hole=0.25):
    pts = []
    for k in range(n):
        a = 2 * pi * k / n
        d = pi / n
        for (aa, rr) in ((a - d * 0.95, ri), (a - d * 0.45, ro), (a + d * 0.45, ro), (a + d * 0.95, ri)):
            pts.append((rr * cos(aa), rr * sin(aa)))
    return [[pts, list(reversed(_circle(hole, 20)))]]


def _leaf():
    a, b = Vector((-0.55, -0.55)), Vector((0.62, 0.62))
    d = (b - a)
    n = Vector((-d.y, d.x)).normalized()
    side1, side2, vein = [], [], []
    for k in range(17):
        t = k / 16.0
        w = 0.40 * sin(pi * t) ** 0.85
        c = a + d * t
        side1.append(tuple(c + n * w))
        side2.append(tuple(c - n * w))
    outer = side2 + list(reversed(side1[1:-1]))
    for k in range(3, 14):
        t = k / 16.0
        c = a + d * t
        vein.append(c)
    hole = [tuple(c + n * 0.025) for c in vein] + [tuple(c - n * 0.025) for c in reversed(vein)]
    stem = [(-0.80, -0.74), (-0.74, -0.80), (-0.50, -0.56), (-0.56, -0.50)]
    return [[outer, list(reversed(hole))], [stem]]


def _atom():
    shapes = []
    for rot in (0.0, 60.0, 120.0):
        o = _ellipse(0.80, 0.30, rot)
        i = _ellipse(0.66, 0.18, rot)
        shapes.append([o, list(reversed(i))])
    shapes.append([_circle(0.14, 16)])
    return shapes


def _heart():
    pts = []
    for k in range(40):
        t = 2 * pi * k / 40
        x = 16 * sin(t) ** 3
        y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
        pts.append((x / 22.0, y / 22.0 + 0.08))
    return [[pts]]


def _drop():
    pts = []
    for k in range(32):
        t = 2 * pi * k / 32
        # teardrop: point at the top
        x = 0.55 * sin(t) * sin(t / 2) ** 0.9
        y = -0.62 * cos(t) + 0.05
        pts.append((x, y))
    return [[pts]]


def _crate():
    o = [(-0.62, -0.62), (0.62, -0.62), (0.62, 0.62), (-0.62, 0.62)]
    i = [(-0.46, -0.46), (-0.46, 0.46), (0.46, 0.46), (0.46, -0.46)]
    bar = [(-0.46, -0.36), (-0.36, -0.46), (0.46, 0.36), (0.36, 0.46)]
    bar2 = [(0.36, -0.46), (0.46, -0.36), (-0.36, 0.46), (-0.46, 0.36)]
    return [[o, i], [bar], [bar2]]


ICONS = {
    "housing": [[[(-0.62, -0.66), (-0.16, -0.66), (-0.16, -0.20), (0.16, -0.20), (0.16, -0.66), (0.62, -0.66),
                  (0.62, 0.12), (0.0, 0.74), (-0.62, 0.12)]],
                [[(0.30, 0.30), (0.48, 0.30), (0.48, 0.66), (0.30, 0.66)]]],
    "food": _leaf(),
    "industry": _gear(),
    "science": _atom(),
    "medical": [[[(-0.18, -0.70), (0.18, -0.70), (0.18, -0.18), (0.70, -0.18), (0.70, 0.18), (0.18, 0.18),
                  (0.18, 0.70), (-0.18, 0.70), (-0.18, 0.18), (-0.70, 0.18), (-0.70, -0.18), (-0.18, -0.18)]]],
    "comfort": _heart(),
    # 5.0 (critic round 33): one icon per civic type
    "shop": [[[(-0.55, -0.70), (0.55, -0.70), (0.48, 0.22), (-0.48, 0.22)]],
             [[(0.34 * cos(radians(t)), 0.22 + 0.40 * sin(radians(t))) for t in range(0, 181, 15)] +
              [(0.20 * cos(radians(t)), 0.22 + 0.26 * sin(radians(t))) for t in range(180, -1, -15)]]],
    "academy": [[[(0.0, 0.66), (-0.80, 0.28), (0.0, -0.10), (0.80, 0.28)]],
                [[(-0.44, -0.46), (0.44, -0.46), (0.44, 0.10), (-0.44, 0.10)]],
                [[(0.56, -0.52), (0.66, -0.52), (0.66, 0.26), (0.56, 0.26)]],
                [_circle(0.09, 12, 0.61, -0.58)]],
    "security": [[[(-0.60, 0.66), (-0.60, 0.02), (-0.38, -0.45), (0.0, -0.80), (0.38, -0.45), (0.60, 0.02),
                   (0.60, 0.66), (0.0, 0.76)],
                  [(0.30 * cos(radians(90 + 36 * k)) * (1.0 if k % 2 == 0 else 0.42),
                    0.02 + 0.30 * sin(radians(90 + 36 * k)) * (1.0 if k % 2 == 0 else 0.42)) for k in range(10)]]],
    "jail": [[[(-0.52, -0.72), (0.52, -0.72), (0.52, 0.12), (-0.52, 0.12)], _circle(0.11, 14, 0.0, -0.24)],
             [[(0.36 * cos(radians(t)), 0.10 + 0.52 * sin(radians(t))) for t in range(0, 181, 15)] +
              [(0.22 * cos(radians(t)), 0.10 + 0.38 * sin(radians(t))) for t in range(180, -1, -15)]]],
    # 5.0 distillery (SIM 2026-10-01): a bottle with a label and a tumbler with an ice cube
    "distillery": [[[(-0.55, -0.72), (-0.07, -0.72), (-0.07, 0.14), (-0.19, 0.30), (-0.19, 0.60), (-0.15, 0.64),
                     (-0.15, 0.76), (-0.47, 0.76), (-0.47, 0.64), (-0.43, 0.60), (-0.43, 0.30), (-0.55, 0.14)],
                    [(-0.47, -0.42), (-0.47, -0.08), (-0.15, -0.08), (-0.15, -0.42)]],
                   [[(0.09, -0.72), (0.53, -0.72), (0.60, -0.02), (0.02, -0.02)],
                    [(0.22, -0.52), (0.22, -0.30), (0.40, -0.30), (0.40, -0.52)]]],
    # 5.0: civic (security office, jail): a shield with a bar
    "civic": [[[(-0.62, 0.62), (-0.62, -0.05), (0.0, -0.78), (0.62, -0.05), (0.62, 0.62), (0.0, 0.76)],
               [(-0.11, -0.46), (0.11, -0.46), (0.11, 0.46), (-0.11, 0.46)]]],
    "life_support": _drop(),
    "logistics": _crate(),
    "utilities": [[[(0.10, 0.78), (-0.42, -0.06), (-0.04, -0.06), (-0.18, -0.78), (0.44, 0.10), (0.04, 0.10),
                    (0.22, 0.78)]]],
}
ICON_MAT = {"security": "SignalRedGlow", "jail": "PrisonOrangeGlow", "shop": "Light"}   # critic 37: bright bag      # security red, jail amber (critic round 33)


def _signed_area(loop):
    return 0.5 * sum(loop[i][0] * loop[(i + 1) % len(loop)][1] - loop[(i + 1) % len(loop)][0] * loop[i][1]
                     for i in range(len(loop)))


def _tris(shape):
    """Triangles (as 2D point triples) of one shape with holes."""
    loops = [[Vector((x, y, 0.0)) for (x, y) in loop] for loop in shape]
    flat = [v for loop in loops for v in loop]
    out = []
    for (a, b, c) in geometry.tessellate_polygon(loops):
        pa, pb, pc = flat[a], flat[b], flat[c]
        if (pb - pa).cross(pc - pa).z < 0:
            pb, pc = pc, pb
        out.append((pa.xy, pb.xy, pc.xy))
    return out


def _subdivide(tri, maxe):
    a, b, c = tri
    if max((a - b).length, (b - c).length, (c - a).length) <= maxe:
        return [tri]
    ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
    out = []
    for t in ((a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)):
        out += _subdivide(t, maxe)
    return out


# --------------------------------------------------------------------------------------
# the badge
# --------------------------------------------------------------------------------------
GAME_UP = -35.0     # camera_rig.gd default yaw -35 deg: screen-up is model azimuth 55 deg, so icons turn by -35


def badge(p, family, cx, cy, rad, surf, lift=0.03, rot=GAME_UP, maxe=0.55):
    """A roof badge of radius `rad` centred on (cx, cy): a hull-grey disc one step darker than the roof
    (HullDark, critic round 17: not black, so it does not read as a helipad), a Frame rim, the family icon glowing in
    the family colour (Neon; the medical cross Hazard) at 0.80 rad.  surf(x, y) -> roof height; draped `lift` above."""
    na, nr = 48, 4

    def zf(x, y, dz):
        return surf(x, y) + lift + dz

    # disc (rings of quads, a fan in the middle), then the rim
    rings = [rad * 0.90 * k / nr for k in range(1, nr + 1)]
    prev = None
    for ri, r in enumerate(rings):
        cur = [(cx + r * cos(2 * pi * k / na), cy + r * sin(2 * pi * k / na)) for k in range(na)]
        ids = [p.v((x, y, zf(x, y, 0.0))) for x, y in cur]
        if prev is None:
            c0 = p.v((cx, cy, zf(cx, cy, 0.0)))
            for k in range(na):
                p.f([c0, ids[k], ids[(k + 1) % na]], "HullDark")
        else:
            for k in range(na):
                p.f([prev[k], ids[k], ids[(k + 1) % na], prev[(k + 1) % na]], "HullDark")
        prev = ids
    outer = [(cx + rad * cos(2 * pi * k / na), cy + rad * sin(2 * pi * k / na)) for k in range(na)]
    oid = [p.v((x, y, zf(x, y, 0.004))) for x, y in outer]
    iid = [p.v((x, y, zf(x, y, 0.004))) for x, y in
           [(cx + rad * 0.90 * cos(2 * pi * k / na), cy + rad * 0.90 * sin(2 * pi * k / na)) for k in range(na)]]
    for k in range(na):
        p.f([iid[k], oid[k], oid[(k + 1) % na], iid[(k + 1) % na]], "Frame")
    # the icon
    mat = ICON_MAT.get(family, "Neon")
    s = rad * 0.80
    cr, sr = cos(radians(rot)), sin(radians(rot))
    for shape in ICONS.get(family, ICONS["housing"]):
        for tri in _tris(shape):
            for (a, b, c) in _subdivide(tuple(Vector((cr * q.x - sr * q.y, sr * q.x + cr * q.y)) * s for q in tri),
                                        maxe):
                ids = []
                for q in (a, b, c):
                    x, y = cx + q.x, cy + q.y
                    ids.append(p.v((x, y, zf(x, y, 0.008))))
                p.f(ids, mat)


# --------------------------------------------------------------------------------------
# silhouette parts
# --------------------------------------------------------------------------------------
def dome_windows(rm, p, t0, t1, n, width_deg, phase=0.0, skip=(), off=0.02, mat="Window", frame="Frame"):
    """A ring of `n` large window panes on the dome between elevations t0 and t1 (deg), each `width_deg` wide,
    with a Frame surround (habitat: 'low dome with windows')."""
    steps = 4
    for k in range(n):
        a = phase + 360.0 * k / n
        if any(abs(((a - s_ + 180.0) % 360.0) - 180.0) < width_deg for s_ in skip):
            continue
        for (ta, tb, aw, m, lift) in ((t0 - 1.5, t1 + 1.5, width_deg / 2 + 1.2, frame, off),
                                      (t0, t1, width_deg / 2, mat, off + 0.01)):
            grid = []
            for i in range(steps + 1):
                row = []
                ang = a - aw + 2 * aw * i / steps
                for j in range(3):
                    t = ta + (tb - ta) * j / 2
                    pos, nrm = rm.dpt(t, ang, lift)
                    row.append(p.v(tuple(pos)))
                grid.append(row)
            for i in range(steps):
                for j in range(2):
                    p.f([grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]], m)


def stack(p, lt, x, y, z0, h, r, bands=2):
    """An industrial stack: a tapered Metal pipe with Hazard bands, a Frame collar, a dark mouth and a warning
    lamp at the top (emissive Light, in the roof part so it lifts with the roof in the cutaway)."""
    p.vcyl(x, y, z0, z0 + 0.25, r * 1.5, seg=10, mat="Frame")
    p.vcyl(x, y, z0 + 0.25, z0 + h, r, r * 0.85, seg=10, mat="Metal", cap0=False, cap1=False)
    for k in range(bands):
        zb = z0 + h - 0.35 - 0.55 * k
        p.vcyl(x, y, zb - 0.22, zb, r * 0.87 + 0.012, seg=10, mat="Hazard", cap0=False, cap1=False)
    p.vcyl(x, y, z0 + h, z0 + h + 0.12, r * 0.95, seg=10, mat="Frame", cap0=False)
    p.cap_disc(r * 0.80, z0 + h + 0.121, "Rubber", seg=10)
    p.sphere((x + r * 0.95, y, z0 + h + 0.20), 0.09, "Light", seg=6, rings=3)
    return z0 + h + 0.3


def sensor_mast(p, lt, x, y, z0, h, dish=0.75):
    """Science: a lattice sensor mast (three legs, cross braces), a dish near the top, a whip antenna and a
    red beacon (Lights)."""
    r0, r1 = 0.55, 0.18
    legs = []
    for k in range(3):
        a = radians(90.0 + 120.0 * k)
        legs.append(((x + r0 * cos(a), y + r0 * sin(a), z0), (x + r1 * cos(a), y + r1 * sin(a), z0 + h)))
    for (a_, b_) in legs:
        p.cyl(a_, b_, 0.09, seg=6, mat="Frame")          # critic round 17: twice as thick
    nb = int(h / 0.7)
    for j in range(1, nb):
        t = j / nb
        pts = [tuple(Vector(a_).lerp(Vector(b_), t)) for (a_, b_) in legs]
        for i in range(3):
            p.cyl(pts[i], pts[(i + 1) % 3], 0.045, seg=4, mat="Metal", cap0=False, cap1=False)
    zt = z0 + h
    p.vcyl(x, y, zt, zt + 0.10, 0.22, seg=8, mat="Frame")
    # dish facing up and out
    with p.at(T(x + 0.35, y + 0.35, zt - 0.7), RX(-35.0)):     # a 1.5 m dish, tilted up and out
        prof = [(0.0, 0.0), (dish * 0.5, 0.07), (dish, 0.28), (dish * 0.96, 0.31), (0.0, 0.06)]
        p.lathe(prof, "Hull", seg=16)
        p.vcyl(0, 0, 0.06, 0.55, 0.03, seg=4, mat="Frame", cap0=False)
    p.beam((x, y, zt - 0.7), (x + 0.35, y + 0.35, zt - 0.7), 0.08, 0.08, "Frame")
    p.vcyl(x, y, zt + 0.10, zt + 1.4, 0.025, seg=4, mat="Metal", cap0=False)
    p.sphere((x, y, zt + 1.45), 0.18, "Light", seg=8, rings=4)
    return zt + 1.6


def glass_vault(p, x0, x1, hw, z0, h, ribs=6, planters=True):
    """Food: a glass barrel vault along X from x0 to x1, half width hw, rise h above z0, Frame ribs and end
    arches, glazing (Glass), a low Frame sill; planter rows (Soil + PlantDark) under it."""
    n = 10
    arc = [(hw * cos(pi * k / n), z0 + 0.25 + h * sin(pi * k / n)) for k in range(n + 1)]   # y, z
    # sill
    p.box0((x0 + x1) / 2, hw - 0.06, z0, x1 - x0, 0.14, 0.25, "Frame")
    p.box0((x0 + x1) / 2, -hw + 0.06, z0, x1 - x0, 0.14, 0.25, "Frame")
    # glazing: one strip per arc segment between the end arches
    for k in range(n):
        (ya, za), (yb, zb) = arc[k], arc[k + 1]
        a, b, c, d = (x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)
        p.f([p.v(a), p.v(b), p.v(c), p.v(d)], "Glass")
    # end walls (glass fans) and ribs
    for xe, sgn in ((x0, -1), (x1, 1)):
        ids = [p.v((xe, y, z)) for (y, z) in arc]
        c0 = p.v((xe, 0.0, z0 + 0.25))
        for k in range(n):
            tri = [c0, ids[k], ids[k + 1]] if sgn > 0 else [c0, ids[k + 1], ids[k]]
            p.f(tri, "Glass")
    for j in range(ribs + 1):
        xr = x0 + (x1 - x0) * j / ribs
        for k in range(n):
            (ya, za), (yb, zb) = arc[k], arc[k + 1]
            p.beam((xr, ya, za), (xr, yb, zb), 0.07, 0.07, "Frame")
    p.beam((x0, 0.0, z0 + 0.25 + h), (x1, 0.0, z0 + 0.25 + h), 0.09, 0.09, "Frame")
    # grow lights (critic round 17: the vault glows at night): a Glow tube under the ridge and along each bed
    p.cyl((x0 + 0.3, 0.0, z0 + 0.12 + h), (x1 - 0.3, 0.0, z0 + 0.12 + h), 0.05, seg=6, mat="Glow")
    if planters:
        for sy in (-1, 1):
            yy = sy * hw * 0.45
            p.box0((x0 + x1) / 2, yy, z0, (x1 - x0) - 0.5, hw * 0.55, 0.40, "Hull")
            p.box0((x0 + x1) / 2, yy, z0 + 0.40, (x1 - x0) - 0.6, hw * 0.48, 0.02, "Soil")
            p.box0((x0 + x1) / 2, yy + sy * hw * 0.26, z0 + 0.40, (x1 - x0) - 0.6, 0.04, 0.03, "Glow")
            nplants = max(3, int((x1 - x0) / 0.55))
            for i in range(nplants):
                px = x0 + 0.4 + (x1 - x0 - 0.8) * (i + 0.5) / nplants
                p.sphere((px, yy, z0 + 0.62), 0.22, "PlantDark" if i % 2 else "Plant", seg=6, rings=3,
                         scale=(1.0, 1.0, 0.8))
    return z0 + 0.25 + h + 0.05


def dome_band(rm, p, mat="Accent", t0=0.4, t1=2.9, off=0.012):
    """A family-colour ring at the foot of a dome (elevation t0..t1 deg)."""
    prof = []
    for t in (t0, t1):
        pos, _ = rm.dpt(t, 0.0, off)
        prof.append((pos.x, pos.z))
    p.lathe([prof[0], prof[1]], mat, seg=rm.seg, smooth=False, caps=False)


# --------------------------------------------------------------------------------------
# the generic pass for every other room type: a badge on the largest smooth, free roof patch
# --------------------------------------------------------------------------------------
def _heightmap(parts, R, cell=0.2):
    """Max z of the triangles of `parts` on a square grid (numpy); -inf where nothing covers a cell."""
    import numpy as np
    n = int(2 * R / cell) + 3
    h = np.full((n, n), -np.inf)
    o = -R - cell
    for p in parts:
        V = [(v.x, v.y, v.z) for v in p.verts]
        for f in p.faces:
            for k in range(1, len(f) - 1):
                a, b, c = V[f[0]], V[f[k]], V[f[k + 1]]
                xs, ys = (a[0], b[0], c[0]), (a[1], b[1], c[1])
                i0, i1 = int((min(xs) - o) / cell), int((max(xs) - o) / cell) + 1
                j0, j1 = int((min(ys) - o) / cell), int((max(ys) - o) / cell) + 1
                i0, j0 = max(i0, 0), max(j0, 0)
                i1, j1 = min(i1, n - 1), min(j1, n - 1)
                if i1 < i0 or j1 < j0:
                    continue
                gx = o + cell * np.arange(i0, i1 + 1)
                gy = o + cell * np.arange(j0, j1 + 1)
                X, Y = np.meshgrid(gx, gy, indexing="ij")
                d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
                if abs(d) < 1e-9:
                    continue
                l1 = ((b[1] - c[1]) * (X - c[0]) + (c[0] - b[0]) * (Y - c[1])) / d
                l2 = ((c[1] - a[1]) * (X - c[0]) + (a[0] - c[0]) * (Y - c[1])) / d
                l3 = 1.0 - l1 - l2
                m = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
                if not m.any():
                    continue
                z = l1 * a[2] + l2 * b[2] + l3 * c[2]
                sub = h[i0:i1 + 1, j0:j1 + 1]
                h[i0:i1 + 1, j0:j1 + 1] = np.where(m, np.maximum(sub, z), sub)
    return h, o, cell


def free_roof_disc(rm, r_want, r_min, cell=0.2, reach=0.55, prefer="centre"):
    """(cx, cy, r, surf) of the largest smooth roof disc (radius r_want down to r_min) free of roof clutter and
    of every level part; surf(x, y) = the roof height there (bilinear on the height map).  None if none fits."""
    import numpy as np
    R = rm.R
    h, o, c = _heightmap([rm.roof], R, cell)
    lv = [q for q in (rm.L[n_] for n_ in (2, 3, 4, 5)) if q.faces] if getattr(rm, "levels", False) else []
    hl = _heightmap(lv, R, cell)[0] if lv else None
    n = h.shape[0]
    finite = np.isfinite(h)
    hp = np.where(finite, h, 0.0)
    # roughness: a cell standing more than 5 cm off the mean of its 3 x 3 neighbours is clutter or an edge
    pad = np.pad(hp, 1, mode="edge")
    nb = sum(pad[1 + di:n + 1 + di, 1 + dj:n + 1 + dj] for di in (-1, 0, 1) for dj in (-1, 0, 1)) / 9.0
    rough = (np.abs(hp - nb) > 0.05) | ~finite
    if hl is not None:
        rough |= np.isfinite(hl) & (hl > hp + 0.03)
    gx = o + c * np.arange(n)
    X, Y = np.meshgrid(gx, gx, indexing="ij")
    best = None
    r = r_want
    while r >= r_min - 1e-6 and best is None:
        cand = []
        lim = rm.Rw * reach
        step = 0.4
        m_ = int(lim / step)
        for i in range(-m_, m_ + 1):
            for j in range(-m_, m_ + 1):
                x, y = i * step, j * step
                if hypot(x, y) > lim or hypot(x, y) + r > rm.Rw - 0.25:
                    continue
                disc = (X - x) ** 2 + (Y - y) ** 2 <= (r + 0.15) ** 2
                if rough[disc].any():
                    continue
                cand.append((hypot(x, y), x, y))
        if cand:
            cand.sort(reverse=(prefer == "edge"))
            best = (cand[0][1], cand[0][2], r)
        r -= 0.1 * rm.Rw * 0.25
    if best is None:
        return None

    def surf(x, y):
        fi, fj = (x - o) / c, (y - o) / c
        i0, j0 = int(fi), int(fj)
        ti, tj = fi - i0, fj - j0
        v = (hp[i0, j0] * (1 - ti) * (1 - tj) + hp[i0 + 1, j0] * ti * (1 - tj) + hp[i0, j0 + 1] * (1 - ti) * tj +
             hp[i0 + 1, j0 + 1] * ti * tj)
        return float(v)
    return best[0], best[1], best[2], surf


NO_BADGE = ("airlock", "junction", "corridor", "medical")    # medical: its big red roof cross is the sign


def family_extras(rm):
    """V4_DESIGN 3.1 silhouettes for the families whose builders lack them: industry stacks, a logistics crane,
    a science sensor mast; each on a free roof spot near the edge."""
    fam = rm.cat
    added = []
    if fam == "industry":
        for k in range(2 if rm.size >= 1 else 1):
            got = free_roof_disc(rm, 0.65, 0.5, reach=0.85, prefer="edge")
            if not got:
                break
            x, y, r, surf = got
            z0 = surf(x, y)
            rm.top_z = max(rm.top_z, stack(rm.roof, rm.lights, x, y, z0 - 0.02, 4.2 + 0.4 * rm.size, 0.34))
            added.append("stack")
    elif fam == "logistics":
        # critic round 22: a lighter roof deck than industry's and a big cargo crane (a 6-8 m jib) that reads at 250 m
        lighten_deck(rm)
        got = free_roof_disc(rm, 1.1, 0.8, reach=0.85, prefer="edge")
        if got:
            x, y, r, surf = got
            yaw = degrees(atan2(-y, -x)) + 20.0
            rm.top_z = max(rm.top_z, cargo_crane(rm.roof, rm, x, y, surf(x, y) - 0.02, jib=6.0 + 0.6 * rm.size,
                                                 yaw=yaw))
            added.append("crane")
    elif fam == "science" and rm.tid != "research_lab":
        got = free_roof_disc(rm, 0.7, 0.55, reach=0.8, prefer="edge")
        if got:
            x, y, r, surf = got
            rm.top_z = max(rm.top_z, sensor_mast(rm.roof, rm.lights, x, y, surf(x, y) - 0.03, 4.0 + 0.4 * rm.size))
            added.append("mast")
    return added


def lighten_deck(rm):
    """Logistics: the flat deck faces of the roof (HullDark / Frame / Rubber) become Hull (a light roof)."""
    D = getattr(rm, "D", None)
    if not D:
        return
    ro = rm.roof
    for i, f in enumerate(ro.faces):
        if ro.fmat[i] in ("HullDark", "Frame", "Rubber"):
            zs = [ro.verts[k].z for k in f]
            if max(zs) - min(zs) < 0.01 and abs(zs[0] - (D + 0.02)) < 0.05:
                ro.fmat[i] = "Hull"


def cargo_crane(p, rm, x, y, z0, jib=6.5, yaw=0.0, h=3.2):
    """A slewing cargo crane: a lattice mast, a cab, a long Hazard-yellow jib with a counter-jib and weights, a hook
    block; the jib turns so it stays over the roof (clipped to the footprint)."""
    from math import cos as _c, sin as _s
    Rlim = rm.R - 0.1 - 0.35
    # turn (and if need be shorten) the jib so its tip and the counter-jib stay inside the footprint
    ok = False
    for _ in range(3):
        for _ in range(60):
            tx, ty = x + jib * _c(radians(yaw)), y + jib * _s(radians(yaw))
            cx_, cy_ = x - 0.32 * jib * _c(radians(yaw)), y - 0.32 * jib * _s(radians(yaw))
            if hypot(tx, ty) <= Rlim and hypot(cx_, cy_) <= Rlim:
                ok = True
                break
            yaw += 6.0
        if ok:
            break
        jib *= 0.85
    p.box0(x, y, z0, 1.1, 1.1, 0.25, "Frame")
    for sx in (-0.35, 0.35):
        for sy in (-0.35, 0.35):
            p.vcyl(x + sx, y + sy, z0 + 0.25, z0 + h, 0.06, seg=5, mat="Hazard")
    for zz in (1.0, 2.0, 3.0):
        if zz < h - 0.2:
            for (a_, b_) in (((-0.35, -0.35), (0.35, 0.35)), ((0.35, -0.35), (-0.35, 0.35))):
                p.cyl((x + a_[0], y + a_[1], z0 + zz - 0.5), (x + b_[0], y + b_[1], z0 + zz), 0.03, seg=4,
                      mat="Frame", cap0=False, cap1=False)
    zt = z0 + h
    with p.at(T(x, y, zt), RZ(yaw)):
        p.box0(0.0, 0.0, 0.0, 1.0, 1.0, 0.3, "Frame")
        p.box0(0.35, -0.55, 0.3, 0.7, 0.6, 0.6, "Hull", bevel=0.03)
        p.box((0.71, -0.55, 0.6), (0.02, 0.5, 0.3), "Window", mats={"-x": None})
        p.beam((0.0, 0.0, 0.55), (jib, 0.0, 0.55), 0.34, 0.34, "Hazard")
        p.beam((0.0, 0.0, 0.55), (-jib * 0.30, 0.0, 0.55), 0.30, 0.30, "Hazard")
        p.box0(-jib * 0.30 + 0.4, 0.0, 0.2, 0.8, 0.7, 0.55, "HullDark")
        p.vcyl(0.0, 0.0, 0.3, 1.9, 0.07, seg=5, mat="Frame")
        p.cyl((0.0, 0.0, 1.9), (jib * 0.7, 0.0, 0.72), 0.03, seg=4, mat="Metal", cap0=False, cap1=False)
        p.cyl((0.0, 0.0, 1.9), (-jib * 0.28, 0.0, 0.72), 0.03, seg=4, mat="Metal", cap0=False, cap1=False)
        p.vcyl(jib * 0.85, 0.0, -0.9, 0.38, 0.015, seg=4, mat="Metal", cap0=False, cap1=False)
        p.box0(jib * 0.85, 0.0, -1.2, 0.3, 0.3, 0.3, "Accent")
    return zt + 2.0


def identity_pass(rm):
    """Every room type without its own 4.0 branch: the family silhouette part (family_extras), the family badge
    on the largest free smooth roof patch and a family-colour ring at a dome's foot.  Builders with their own
    branch set rm.badge_done."""
    if rm.tid in NO_BADGE or getattr(rm, "badge_done", False):
        return False
    if getattr(rm, "shell", None) == "dome" and getattr(rm, "H", None):
        dome_band(rm, rm.roof)
    if not getattr(rm, "no_extras", False):
        family_extras(rm)
    got = free_roof_disc(rm, 0.36 * rm.Rw, 0.22 * rm.Rw)
    if got is None:
        # no smooth free patch (glass roofs, busy decks): a flat badge plate on a short mast over the roof crown
        cx, cy, r = 0.0, 0.0, 0.30 * rm.Rw
        top = _max_roof_z(rm, cx, cy, r)
        z = top + 0.25
        rm.roof.vcyl(cx, cy, top - 0.4, z - 0.06, 0.18, seg=10, mat="Frame")
        rm.roof.vcyl(cx, cy, z - 0.08, z, r + 0.06, seg=48, mat="Frame")
        badge(rm.roof, getattr(rm, "badge_family", rm.cat), cx, cy, r, lambda x_, y_: z, lift=0.004)
        rm.top_z = max(rm.top_z, z + 0.05)
        print("  identity: badge plate over the crown on", rm.tid, rm.size)
        rm.badge_done = True
        return True
    cx, cy, r, surf = got
    badge(rm.roof, getattr(rm, "badge_family", rm.cat), cx, cy, r, surf, lift=0.02)
    rm.badge_done = True
    return True


def _max_roof_z(rm, cx, cy, r):
    """The highest roof or level vertex over the disc (cx, cy, r)."""
    z = WALL_TOP
    for p in [rm.roof] + ([rm.L[n_] for n_ in (2, 3, 4, 5)] if getattr(rm, "levels", False) else []):
        for v in p.verts:
            if hypot(v.x - cx, v.y - cy) <= r + 0.1:
                z = max(z, v.z)
    return z
