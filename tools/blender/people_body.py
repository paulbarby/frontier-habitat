"""
Frontier Habitat 5.0 - ART-NPC: body shapes and garment builders for the people (built in the v3 1.80 m frame; the
variant scale is applied to the rig and every mesh at the end).

  torso(md, spec, ...)   ring loft: superellipse sections (front, back, half width, exponent, x offset) per height,
                         plus shaping (bust, chest, glutes) and fold displacements; open at the neck and the bottom
  limb(md, pts, st, ...) loft along a joint polyline with per-station radii and fold functions (elbow, knee)
  hand(md, s, ...)       five fingers with three segments, knuckles, nails, a thumb pad
  shoe(md, s, kind)      work boot / sneaker
Weight rules come from npc_common (torso_rule, arm_rule, leg_rule, Chain).
"""
import os
import sys
from math import sin, cos, pi, radians, sqrt, exp, atan2

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
from npc_common import (Chain, sstep, torso_rule, arm_rule, leg_rule, side_vec, frame_from,     # noqa: E402
                        SH_JOINT, EL_JOINT, WR_JOINT, _UA, _FA, HIP_JOINT, KNEE_JOINT, ANKLE_JOINT, PALM_N)
from mathutils import Vector, Matrix                             # noqa: E402

# ------------------------------------------------------------------------------------------------------------------
# body proportions (1.80 m frame): torso sections  (z, front, back, half width, exponent, x0)
# ------------------------------------------------------------------------------------------------------------------
TORSO_M = [
    (0.870, 0.055, 0.070, 0.080, 2.2, -0.010),
    (0.905, 0.092, 0.108, 0.150, 2.4, -0.010),
    (0.950, 0.098, 0.114, 0.164, 2.5, -0.008),
    (1.000, 0.097, 0.112, 0.162, 2.5, -0.006),
    (1.060, 0.094, 0.100, 0.152, 2.4, -0.002),
    (1.120, 0.100, 0.100, 0.156, 2.5, 0.002),
    (1.190, 0.110, 0.104, 0.166, 2.6, 0.006),
    (1.260, 0.121, 0.108, 0.176, 2.7, 0.009),
    (1.320, 0.122, 0.108, 0.184, 2.7, 0.010),
    (1.375, 0.112, 0.104, 0.200, 2.6, 0.008),
    (1.415, 0.100, 0.098, 0.196, 2.5, 0.004),
    (1.445, 0.086, 0.088, 0.168, 2.3, 0.000),
    (1.470, 0.074, 0.078, 0.124, 2.2, -0.002),
    (1.495, 0.064, 0.068, 0.084, 2.1, 0.000),
]
TORSO_F = [
    (0.870, 0.055, 0.075, 0.086, 2.2, -0.012),
    (0.905, 0.094, 0.118, 0.166, 2.4, -0.012),
    (0.950, 0.098, 0.124, 0.180, 2.5, -0.010),
    (1.000, 0.093, 0.110, 0.164, 2.5, -0.006),
    (1.060, 0.084, 0.092, 0.128, 2.3, -0.004),
    (1.120, 0.088, 0.092, 0.132, 2.4, 0.000),
    (1.190, 0.098, 0.096, 0.146, 2.5, 0.004),
    (1.260, 0.104, 0.098, 0.156, 2.6, 0.006),
    (1.320, 0.104, 0.098, 0.162, 2.6, 0.006),
    (1.375, 0.098, 0.094, 0.172, 2.5, 0.006),
    (1.415, 0.090, 0.090, 0.170, 2.4, 0.003),
    (1.445, 0.078, 0.080, 0.146, 2.3, 0.000),
    (1.470, 0.066, 0.070, 0.110, 2.2, -0.002),
    (1.495, 0.057, 0.061, 0.074, 2.1, 0.000),
]


def ring_at(rings, z):
    if z <= rings[0][0]:
        return tuple(rings[0][1:6])
    for a, b in zip(rings[:-1], rings[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            t = t * t * (3 - 2 * t)
            return tuple(a[i] + (b[i] - a[i]) * t for i in range(1, 6))
    return tuple(rings[-1][1:6])


def se_pt(af, ab, b, n, t):
    c, s = cos(t), sin(t)
    e = 2.0 / n
    return ((abs(c) ** e) * (af if c >= 0 else ab) * (1 if c >= 0 else -1), (abs(s) ** e) * b * (1 if s >= 0 else -1))


def body_shape(sex):
    """Displacement (outward, m) of the bare torso at (y, z, front flag)."""
    def f(y, z, x):
        ay = abs(y)
        d = 0.0
        if sex == "f":
            if x > 0:
                d += 0.040 * exp(-((ay - 0.070) / 0.042) ** 2 - ((z - 1.270) / 0.046) ** 2) * min(1.0, x / 0.06)
        else:
            if x > 0:
                d += 0.007 * exp(-((ay - 0.070) / 0.050) ** 2 - ((z - 1.300) / 0.045) ** 2) * min(1.0, x / 0.06)
        if x < 0:
            d += (0.010 if sex == "f" else 0.006) * exp(-((ay - 0.070) / 0.055) ** 2 - ((z - 0.930) / 0.050) ** 2) \
                * min(1.0, -x / 0.06)
        return d
    return f


# ------------------------------------------------------------------------------------------------------------------
def torso(md, sex, zs, off, mat_fn, seg=28, disp=None, rule=None, open_front=0.0, uv=False):
    """Ring loft over the torso sections at heights zs.  off: garment offset (m, float or fn(z)).
    mat_fn(k, i, y, z, x) -> material of the face above ring k at segment i.  disp(y, z, x, angle) -> extra outward
    displacement.  Returns the list of rings (vertex ids)."""
    rings = TORSO_M if sex == "m" else TORSO_F
    shape = body_shape(sex)
    rule = rule or torso_rule(pelvis_thigh=0.5)
    ids = []
    for z in zs:
        af, ab, b, n, x0 = ring_at(rings, z)
        o = off(z) if callable(off) else off
        row = []
        for i in range(seg):
            t = 2 * pi * i / seg
            x, y = se_pt(af + o, ab + o, b + o, n, t)
            nx, ny = cos(t), sin(t)
            d = shape(y, z, x)
            if disp:
                d += disp(y, z, x, t)
            p = Vector((x0 + x + nx * d, y + ny * d * 0.6, z))
            row.append(md.v(p, rule))
        ids.append(row)
    for k in range(len(zs) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            md.f((ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]), mat_fn(k, i, md.verts[ids[k][i]]), True)
    return ids


def cap(md, ring, centre, mat, flip=False):
    c = md.v(centre, md.rules[ring[0]])
    n = len(ring)
    for i in range(n):
        f = (ring[i], ring[(i + 1) % n], c)
        md.f(tuple(reversed(f)) if flip else f, mat, True)


def bridge(md, a, b, mat, flip=False):
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        f = (a[i], a[j], b[j], b[i])
        md.f(tuple(reversed(f)) if flip else f, mat, True)


# ------------------------------------------------------------------------------------------------------------------
def limb(md, pts, st, seg=16, rule=None, fold=None, ref=(1, 0, 0), start_cap=False, end_cap=False, cap_mat=None):
    """Loft along a polyline.  st: [(s, ru, rv, mat, du, dv)] arc-length stations; ru along the frame's u (ref), rv
    along v.  fold(s, ang) -> radial offset (m).  Returns the rings."""
    pts = [Vector(p) for p in pts]
    segs = [(pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)]
    total = sum(segs)

    def at(s):
        s = max(0.0, min(total, s))
        acc = 0.0
        for i, L in enumerate(segs):
            if s <= acc + L or i == len(segs) - 1:
                t = (s - acc) / L if L > 0 else 0.0
                p = pts[i].lerp(pts[i + 1], t)
                d0 = (pts[i + 1] - pts[i]).normalized()
                # blend the direction near the joints (smooth bends)
                d = d0
                if t < 0.25 and i > 0:
                    dp = (pts[i] - pts[i - 1]).normalized()
                    d = dp.lerp(d0, 0.5 + 2 * t).normalized()
                elif t > 0.75 and i < len(segs) - 1:
                    dn = (pts[i + 2] - pts[i + 1]).normalized()
                    d = d0.lerp(dn, (t - 0.75) * 2).normalized()
                return p, d
            acc += L
        return pts[-1], (pts[-1] - pts[-2]).normalized()
    rings = []
    for (s, ru, rv, mat, *rest) in st:
        du = rest[0] if len(rest) > 0 else 0.0
        dv = rest[1] if len(rest) > 1 else 0.0
        p, d = at(s)
        u, v, w = frame_from(d, ref)
        row = []
        for i in range(seg):
            a = 2 * pi * i / seg
            r_off = fold(s, a) if fold else 0.0
            q = p + u * (du + (ru + r_off) * cos(a)) + v * (dv + (rv + r_off) * sin(a))
            row.append(md.v(q, rule))
        rings.append((row, mat))
    for k in range(len(rings) - 1):
        a, mat = rings[k]
        b, _ = rings[k + 1]
        for i in range(seg):
            j = (i + 1) % seg
            md.f((a[i], a[j], b[j], b[i]), mat, True)
    if start_cap:
        p, d = at(st[0][0])
        cap(md, rings[0][0], p - d * 0.004, cap_mat or rings[0][1], flip=True)
    if end_cap:
        p, d = at(st[-1][0])
        cap(md, rings[-1][0], p + d * 0.004, cap_mat or rings[-1][1])
    return [r for r, _ in rings]


def orient_all(md, k0, k1, centre_fn):
    """Flip faces k0..k1-1 whose normals point towards centre_fn(centroid) (a point on the axis)."""
    for k in range(k0, k1):
        f = md.faces[k]
        a, b, c = (md.verts[i] for i in f[:3])
        nrm = (b - a).cross(c - a)
        if len(f) == 4:
            nrm += (c - a).cross(md.verts[f[3]] - a)
        mid = sum((md.verts[i] for i in f), Vector()) / len(f)
        if nrm.dot(mid - centre_fn(mid)) < 0:
            md.faces[k] = tuple(reversed(f))
            if md.fuv[k]:
                md.fuv[k] = list(reversed(md.fuv[k]))


def seg_axis(a, b):
    """centre_fn for a straight limb segment a-b: the closest point on the axis."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L2 = d.dot(d)

    def f(p):
        t = max(0.0, min(1.0, (p - a).dot(d) / L2)) if L2 > 0 else 0.0
        return a + d * t
    return f


def poly_axis(pts):
    segs = [seg_axis(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]

    def f(p):
        best = None
        for g in segs:
            q = g(p)
            if best is None or (p - q).length < (p - best).length:
                best = q
        return best
    return f


# ------------------------------------------------------------------------------------------------------------------
# folds: small ridges where cloth bunches
# ------------------------------------------------------------------------------------------------------------------
def joint_folds(s_joint, amp=0.004, width=0.06, n=3, inner=0.0, phase=0.0):
    """Radial offset near a joint: n ridges, strongest on the inner side (angle `inner`)."""
    def f(s, a):
        t = (s - s_joint) / width
        if abs(t) > 1.2:
            return 0.0
        env = exp(-t * t * 2.2)
        side = 0.35 + 0.65 * max(0.0, cos(a - inner))
        ridges = 0.5 + 0.5 * cos(2 * pi * (t * n * 0.5 + 0.12 * sin(3 * a + phase)))
        return amp * env * side * ridges
    return f


def sum_folds(*fs):
    def f(s, a):
        return sum(g(s, a) for g in fs if g)
    return f


# ------------------------------------------------------------------------------------------------------------------
# hands (skin), relaxed: fingers slightly curled, thumb forward
# ------------------------------------------------------------------------------------------------------------------
def hand(md, s, sex="m", scale=1.0, skin="Skin", nail="Nail"):
    sg = 1.0 if s == "L" else -1.0
    wr = side_vec(WR_JOINT, s)
    fa = side_vec(_FA, s)
    pn = Vector((PALM_N.x, PALM_N.y * sg, PALM_N.z))           # palm normal (towards the body)
    side = fa.cross(pn).normalized() * sg                       # towards the thumb (forward)
    if side.x < 0:
        side = -side
    k = scale * (0.98 if sex == "f" else 1.08)
    rule_h = {"hand." + s: 1.0}
    k0 = len(md.faces)
    # palm: a flattened loft from the wrist to the knuckles
    st = [(0.000, 0.028, 0.020), (0.020, 0.036, 0.016), (0.055, 0.041, 0.0145), (0.080, 0.039, 0.013)]
    rows = []
    for (d, w, t) in st:
        c = wr + fa * (d * k)
        row = []
        for i in range(12):
            a = 2 * pi * i / 12
            q = c + side * (w * k * cos(a)) + pn * (t * k * sin(a) * (1.0 if sin(a) > 0 else 0.9))
            row.append(md.v(q, rule_h))
        rows.append(row)
    for r in range(len(rows) - 1):
        for i in range(12):
            j = (i + 1) % 12
            md.f((rows[r][i], rows[r][j], rows[r + 1][j], rows[r + 1][i]), skin, True)
    cap(md, rows[0], wr - fa * 0.004 * k, skin, flip=True)
    kbase = wr + fa * 0.080 * k
    # fingers: (offset along side, length scale, curl deg per joint, spread deg)
    fingers = [(0.027, 0.88, 13.0, 3.0), (0.009, 1.00, 15.0, 0.8), (-0.009, 0.97, 17.0, -1.2), (-0.026, 0.80, 19.0, -3.0)]
    seglen = [0.044, 0.027, 0.021]
    for (o, ls, curl, spread) in fingers:
        p = kbase + side * (o * k) + fa * (0.004 * k * (1 - abs(o) / 0.03))
        d = (fa + side * (spread / 57.3)).normalized()
        axis = side.cross(d).normalized()
        pts = [p]
        dd = d.copy()
        for j, L in enumerate(seglen):
            ang = radians(curl * (1.0 + 0.3 * j))
            dd = Matrix.Rotation(ang, 3, axis) @ dd
            p = p + dd * (L * ls * k)
            pts.append(p)
        radii = [0.0105, 0.0096, 0.0087, 0.0077]
        _finger(md, pts, [r * k * (0.95 if ls < 0.85 else 1.0) for r in radii], side, rule_h, skin, nail)
    # thumb: from the side of the palm, forward and a little towards the palm
    tb = wr + fa * (0.020 * k) + side * (0.030 * k) + pn * (0.004 * k)
    d = (fa * 0.55 + side * 0.65 + pn * 0.35).normalized()
    axis = side.cross(d).normalized()
    pts = [tb]
    dd = d.copy()
    for L, ang in ((0.040, 10.0), (0.032, 14.0), (0.026, 16.0)):
        dd = Matrix.Rotation(radians(ang), 3, pn.cross(dd).normalized()) @ dd
        tb = tb + dd * (L * k)
        pts.append(tb)
    _finger(md, pts, [r * k for r in (0.014, 0.0115, 0.0098, 0.0085)], pn, rule_h, skin, nail)
    return len(md.faces) - k0


def _finger(md, pts, radii, up, rule, skin, nail, seg=8):
    """A finger along pts with a rounded tip and a nail on the back (the side facing away from the palm)."""
    rows = []
    for j, p in enumerate(pts):
        d = (pts[min(j + 1, len(pts) - 1)] - pts[max(j - 1, 0)]).normalized()
        u = (up - d * up.dot(d)).normalized()
        v = d.cross(u).normalized()
        r = radii[j]
        row = [md.v(p + u * (r * cos(2 * pi * i / seg) * 0.92) + v * (r * sin(2 * pi * i / seg)), rule) for i in range(seg)]
        rows.append((row, u, v, d, r))
    for j in range(len(rows) - 1):
        a, b = rows[j][0], rows[j + 1][0]
        for i in range(seg):
            k = (i + 1) % seg
            md.f((a[i], a[k], b[k], b[i]), skin, True)
    # tip dome
    row, u, v, d, r = rows[-1]
    mid = [md.v(pts[-1] + d * (r * 0.55) + u * (r * cos(2 * pi * i / seg) * 0.66) + v * (r * sin(2 * pi * i / seg) * 0.7), rule)
           for i in range(seg)]
    for i in range(seg):
        k = (i + 1) % seg
        md.f((row[i], row[k], mid[k], mid[i]), skin, True)
    tip = md.v(pts[-1] + d * (r * 0.95), rule)
    for i in range(seg):
        md.f((mid[i], mid[(i + 1) % seg], tip), skin, True)
    # nail: a thin plate on the back (-u: away from the palm) of the last segment
    p0, p1 = pts[-2].lerp(pts[-1], 0.45), pts[-1] + d * (r * 0.35)
    back = -u
    wv = v * (r * 0.62)
    q = [p0 + back * (r * 1.02) - wv, p0 + back * (r * 1.02) + wv, p1 + back * (r * 0.92) + wv, p1 + back * (r * 0.92) - wv]
    ids = [md.v(x, rule) for x in q]
    md.f(ids, nail, True)


# ------------------------------------------------------------------------------------------------------------------
# shoes
# ------------------------------------------------------------------------------------------------------------------
def shoe(md, s, kind="boot", upper="Leather", sole="Sole", accent=None, scale=1.0):
    """kind: boot (ankle-high work boot) or sneaker.  Built round the v3 foot (ankle joint, ball at +0.13)."""
    sg = 1.0 if s == "L" else -1.0
    an = side_vec(ANKLE_JOINT, s)
    y0 = an.y
    rule = leg_rule(s)
    # sole outline (left foot), counter-clockwise from the heel
    out = [(-0.100, 0.000), (-0.094, -0.030), (-0.070, -0.045), (-0.020, -0.047), (0.040, -0.049), (0.095, -0.052),
           (0.140, -0.050), (0.180, -0.040), (0.205, -0.020), (0.212, 0.000), (0.207, 0.020), (0.188, 0.040),
           (0.150, 0.053), (0.100, 0.053), (0.040, 0.046), (-0.020, 0.044), (-0.070, 0.042), (-0.094, 0.028)]
    out = [(x * scale, y * scale) for x, y in out]
    th = 0.030 if kind == "boot" else 0.026
    k0 = len(md.faces)
    with md.w(rule):
        bot = [md.v((x + an.x + 0.012, y0 + y * sg, 0.0)) for x, y in out]
        top = [md.v((x * 1.01 + an.x + 0.012, y0 + y * sg * 1.01, th)) for x, y in out]
        bridge(md, bot, top, sole)
        cap(md, bot, (an.x + 0.06, y0, 0.0), sole, flip=True)
        # upper: sections along the foot from the heel to the toe; each an arch from one sole side to the other
        n = 10
        secs = [(-0.098, 0.043, 0.100 if kind == "sneaker" else 0.16), (-0.080, 0.048, 0.110 if kind == "sneaker" else 0.17),
                (-0.040, 0.050, 0.105 if kind == "sneaker" else 0.16), (0.010, 0.050, 0.092 if kind == "sneaker" else 0.13),
                (0.060, 0.052, 0.080 if kind == "sneaker" else 0.100), (0.110, 0.052, 0.068), (0.150, 0.049, 0.060),
                (0.185, 0.038, 0.052), (0.205, 0.020, 0.044)]
        rows = []
        for (x, hw, h) in secs:
            row = []
            for i in range(n + 1):
                a = pi * i / n
                yy = cos(a) * hw * scale
                zz = th + sin(a) ** 0.8 * (h - th)
                row.append(md.v((x * scale + an.x + 0.012, y0 + yy * sg, zz)))
            rows.append(row)
        for r in range(len(rows) - 1):
            mat = upper
            if kind == "boot" and secs[r][0] > 0.10:
                mat = accent or "Leather"
            if kind == "sneaker" and accent and abs(secs[r][0] - 0.02) < 0.035:
                mat = accent
            for i in range(n):
                f = (rows[r][i], rows[r][i + 1], rows[r + 1][i + 1], rows[r + 1][i])
                md.f(f, mat, True)
        # heel and toe caps
        cap(md, rows[0], Vector((secs[0][0] * scale + an.x + 0.006, y0, th + 0.05)), upper, flip=True)
        cap(md, rows[-1], Vector((secs[-1][0] * scale + an.x + 0.02, y0, th + 0.01)), upper)
        # collar round the ankle opening
        cx = an.x - 0.012
        ring = []
        topz = 0.165 if kind == "boot" else 0.105
        for i in range(12):
            a = 2 * pi * i / 12
            ring.append(md.v((cx + 0.050 * cos(a) * scale, y0 + 0.044 * sin(a) * sg * scale, topz * scale)))
        ring2 = [md.v((cx + 0.047 * cos(2 * pi * i / 12) * scale, y0 + 0.041 * sin(2 * pi * i / 12) * sg * scale,
                       (topz - 0.045) * scale)) for i in range(12)]
        bridge(md, ring2, ring, upper if kind == "boot" else (accent or upper))
    orient_all(md, k0, len(md.faces), lambda p: Vector((an.x + 0.05, y0, 0.06)))
    return md
