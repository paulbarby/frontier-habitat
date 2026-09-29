"""
Frontier Habitat 5.0 - ART-NPC: hair for the people (material `Hair`: the game tints it per person, V3 mode 3; the
strand texture people_hair.png multiplies, streaks along the flow).

Hair = a cap over the scalp (a grid in azimuth / elevation round the head centre; each point sits on the head surface
of people_face plus a thickness with clumps) and, for longer styles, a curtain (outer and inner surfaces, a closed
hem).  Styles are parameter sets per variant.
"""
import os
import sys
from math import sin, cos, pi, radians, degrees, atan2, acos, sqrt, exp
import random

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import people_face as PF                                         # noqa: E402
from people_mesh import MeshData                                 # noqa: E402
from mathutils import Vector                                     # noqa: E402

STYLES = {
    # line: hairline elevation (deg) by azimuth (deg, 0 = front, 90 = left, 180 = back); thick(az, el) in m
    "m1": dict(kind="crop", line=[(0, 31), (18, 32), (34, 38), (48, 26), (70, 16), (84, 2), (95, 18), (120, 6),
                                  (150, -22), (180, -40)],
               top=0.016, side=0.0016, back=0.0022, quiff=0.016, clump=0.0040, clumps=34, sideburn=True,
               fade=14.0, side_fall=True),
    "f1": dict(kind="bob", line=[(0, 31), (25, 30), (45, 26), (70, 20), (90, 16), (120, 6), (150, -20), (180, -36)],
               top=0.011, side=0.009, back=0.010, quiff=0.0, clump=0.0028, clumps=34, part=-22.0,
               curtain_from=60.0, tip_z=-0.112, flare=0.014, fringe=True),
}


def hairline(style, az):
    """Elevation of the hairline at azimuth az (deg, symmetric)."""
    a = abs(((az + 180.0) % 360.0) - 180.0)
    L = style["line"]
    for (a0, e0), (a1, e1) in zip(L[:-1], L[1:]):
        if a0 <= a <= a1:
            t = (a - a0) / (a1 - a0)
            t = t * t * (3 - 2 * t)
            return e0 + (e1 - e0) * t
    return L[-1][1]


def head_point(P, az, el):
    """Point on the head surface in direction (az, el) from HC, and its normal (both world)."""
    a, e = radians(az), radians(el)
    d = Vector((cos(e) * cos(a), cos(e) * sin(a), sin(e)))
    q = d.copy()
    for _ in range(8):
        # the head function is not radial: aim the parameter direction so the surface point lies along d
        th = acos(max(-1.0, min(1.0, q.y)))
        ph = atan2(q.z, q.x)
        dd = PF.surface(th, ph, P).normalized()
        err = d - dd
        if err.length < 1e-5:
            break
        q = (q + err).normalized()
    th = acos(max(-1.0, min(1.0, q.y)))
    ph = atan2(q.z, q.x)
    p = PF.surface(th, ph, P)
    n = PF.surface_normal(th, ph, P)
    return PF.HC + p, n


def build_hair(variant):
    P = PF.VARIANTS[variant]
    S = STYLES[variant]
    md = MeshData("Hair_%s" % variant)
    rnd = random.Random(5)
    phases = [rnd.random() * 2 * pi for _ in range(4)]
    rule = {"head": 1.0}
    n_az = 72
    n_el = 16
    part = S.get("part", None)

    def thick(az, el, line):
        a = abs(((az + 180.0) % 360.0) - 180.0)
        se = max(0.0, sin(radians(el)))
        if S.get("side_fall"):
            se = max(0.0, (se - 0.45) / 0.55) ** 1.1                  # short sides: the volume is on top only
        else:
            se = se ** 0.8
        base = S["side"] + (S["top"] - S["side"]) * se
        if a > 110:
            base = base + (S["back"] - base) * min(1.0, (a - 110) / 50.0) * (1 - max(0.0, sin(radians(el))))
        base += S["quiff"] * exp(-((a) / 30.0) ** 2) * exp(-((el - (line + 18)) / 12.0) ** 2)
        edge = min(1.0, max(0.0, (el - line) / S.get("fade", 7.0)))           # taper to the hairline
        return base * (0.15 + 0.85 * edge * edge * (3 - 2 * edge))

    def clump(az, el):
        k = S["clumps"]
        v = sum(sin(radians(az) * k * (1 + 0.37 * i) + phases[i] + 0.08 * el * (1 + i)) for i in range(3)) / 3.0
        v = 0.5 + 0.5 * v
        # a parting line: a groove along az = part
        if part is not None:
            v -= 0.9 * exp(-((((az - part + 180) % 360) - 180) / 3.0) ** 2) * (el > 30)
        return S["clump"] * v

    grid = []
    for i in range(n_az + 1):
        az = -180.0 + 360.0 * i / n_az
        line = hairline(S, az)
        col = []
        for j in range(n_el + 1):
            t = j / n_el
            el = line + (89.0 - line) * (1 - (1 - t) ** 1.4)
            p, n = head_point(P, az, el)
            th_ = thick(az, el, line)
            q = p + n * (th_ + clump(az, el) * min(1.0, th_ / max(1e-6, S["top"])) * min(1.0, (el - line) / 6.0))
            vid = md.v(q, rule)
            md.normals[vid] = n
            col.append((vid, az, el))
        # a tucked edge under the hairline
        p, n = head_point(P, az, line - 1.5)
        tuck = md.v(p - n * 0.0015, rule)
        grid.append((col, tuck))
    for i in range(n_az):
        c0, t0 = grid[i]
        c1, t1 = grid[i + 1]
        for j in range(n_el):
            f = (c0[j][0], c1[j][0], c1[j + 1][0], c0[j + 1][0])
            uv = [(c0[j][1] / 24.0, c0[j][2] / 18.0), (c1[j][1] / 24.0, c1[j][2] / 18.0),
                  (c1[j + 1][1] / 24.0, c1[j + 1][2] / 18.0), (c0[j + 1][1] / 24.0, c0[j + 1][2] / 18.0)]
            md.f(f, "Hair", True, uv)
        md.f((t0, t1, c1[0][0], c0[0][0]), "Hair", True, [(0, 0), (0.1, 0), (0.1, 0.05), (0, 0.05)])
    # crown cap
    top = [grid[i][0][-1][0] for i in range(n_az)]
    p, n = head_point(P, 0.0, 90.0)
    c = md.v(p + n * (S["top"] + S["clump"] * 0.5), rule)
    md.normals[c] = n
    for i in range(n_az):
        md.f((top[i], top[(i + 1) % n_az], c), "Hair", True, [(0.1, 3.0), (0.2, 3.0), (0.15, 3.1)])
    if S["kind"] == "bob":
        curtain(md, P, S, rule, rnd)
    fix_hair_orientation(md)
    return md


def curtain(md, P, S, rule, rnd):
    """Sides and back hang to tip_z (head-local) from under the cap, open over the face: clumped strands (outer ridges),
    uneven and tapered tips, an inner surface, a closed hem."""
    a0 = S["curtain_from"]
    n_az = 72
    rows = 11
    outer, inner = [], []
    seeds = [rnd.random() for _ in range(n_az + 1)]
    for i in range(n_az + 1):
        az = a0 + (360.0 - 2 * a0) * i / n_az
        edge = min(i, n_az - i)                    # 0 at the face edges
        edge_w = min(1.0, edge / 5.0)
        line = hairline(S, az)
        el0 = line + 10.0
        p0, n0 = head_point(P, az, el0)
        top = p0 + n0 * 0.004                     # under the cap surface: the cap covers the join
        a = radians(az)
        radial = Vector((cos(a), sin(a), 0.0))
        # uneven tips: a clump pattern along the hem
        tip = S["tip_z"] + 0.012 * sin(a * 9.0 + 0.7) + 0.008 * sin(a * 23.0) + 0.006 * (seeds[i] - 0.5)
        oc, ic = [], []
        for j in range(rows + 1):
            t = j / rows
            z = (top.z - PF.HC.z) + (tip - (top.z - PF.HC.z)) * t
            el = degrees(atan2(z, 0.09))
            ph_, _ = head_point(P, az, max(-70.0, min(80.0, el)))
            r_head = sqrt((ph_.x - PF.HC.x) ** 2 + (ph_.y - PF.HC.y) ** 2)
            r_top = sqrt((top.x - PF.HC.x) ** 2 + (top.y - PF.HC.y) ** 2)
            r = max(r_head + 0.010, r_top * (1 - t) + (r_head + 0.013) * t) + S["flare"] * t ** 1.8 * (0.3 + 0.7 * edge_w)
            r = max(r, 0.075 + 0.02 * (1 - t))
            # the face edge hugs the head (no standing plate at the temples)
            r = (r_head + 0.005) + (r - r_head - 0.005) * (0.25 + 0.75 * edge_w)
            ridge = 0.0045 * max(0.0, sin(a * 29 + 1.3 * sin(a * 7))) ** 1.5 * min(1.0, t * 3)
            thick = (0.010 * (1 - 0.75 * t ** 2) + 0.002) * (0.35 + 0.65 * edge_w)
            if edge_w < 1.0:
                # sweep the front strands back as they fall (a curved frame round the face, not a flat cut)
                back = radians((1.0 - edge_w) * 14.0 * t) * (1 if az < 180 else -1)
                radial = Vector((cos(a + back), sin(a + back), 0.0))
            q = PF.HC + radial * (r + ridge) + Vector((0, 0, z))
            qi = PF.HC + radial * (r + ridge - thick) + Vector((0, 0, z + 0.004 * t))
            oc.append(md.v(q, rule))
            ic.append(md.v(qi, rule))
        outer.append((oc, az))
        inner.append(ic)
    axis = lambda c_: Vector((c_.x - PF.HC.x, c_.y - PF.HC.y, 0.0))            # noqa: E731
    for i in range(n_az):
        for j in range(rows):
            uv = [(outer[i][1] / 24.0, 3 - j * 0.35), (outer[i + 1][1] / 24.0, 3 - j * 0.35),
                  (outer[i + 1][1] / 24.0, 3 - (j + 1) * 0.35), (outer[i][1] / 24.0, 3 - (j + 1) * 0.35)]
            a, b = outer[i][0], outer[i + 1][0]
            k = len(md.faces)
            md.f((a[j], b[j], b[j + 1], a[j + 1]), "Hair", True, uv)
            PF.orient_face(md, k, axis)
            c, d = inner[i], inner[i + 1]
            k = len(md.faces)
            md.f((c[j], d[j], d[j + 1], c[j + 1]), "Hair", True, uv)
            PF.orient_face(md, k, lambda c_: -axis(c_))
        a, b = outer[i][0], outer[i + 1][0]
        c, d = inner[i], inner[i + 1]
        k = len(md.faces)
        md.f((a[-1], b[-1], d[-1], c[-1]), "Hair", True, [(0, 0), (0.1, 0), (0.1, 0.05), (0, 0.05)])
        PF.orient_face(md, k, lambda c_: Vector((0, 0, -1.0)))
    for i, sgn in ((0, -1.0), (n_az, 1.0)):
        o, inn = outer[i][0], inner[i]
        az = outer[i][1]
        tang = Vector((-sin(radians(az)), cos(radians(az)), 0.0)) * sgn
        for j in range(rows):
            k = len(md.faces)
            md.f((o[j], o[j + 1], inn[j + 1], inn[j]), "Hair", True, [(0, 0), (0.05, 0), (0.05, 0.1), (0, 0.1)])
            PF.orient_face(md, k, lambda c_, tang=tang: -tang)
    if S.get("fringe"):
        fringe(md, P, S, rule)


def fringe(md, P, S, rule):
    """A side-swept fringe: one sheet from the parting across the forehead; its lower edge scalloped (soft points),
    thicker at the root, tapered to the edge."""
    n = 18
    rows = 6
    outer, inner = [], []
    for i in range(n + 1):
        t = i / n
        scal = 0.5 + 0.5 * cos(t * 2 * pi * 3.5)                  # soft points along the edge
        drop = 6.0 + 9.0 * t + 3.0 * scal
        co, ci = [], []
        for j in range(rows + 1):
            v = j / rows
            az = S["part"] + (46.0 - S["part"]) * t + 10.0 * v ** 1.3 * (0.4 + t)
            line = hairline(S, az)
            el = line + 13.0 - (13.0 + drop) * v
            p, n_ = head_point(P, az, el)
            lift = 0.0105 + 0.005 * sin(pi * v) + 0.0015 * sin(t * 40.0) * v
            co.append(md.v(p + n_ * lift, rule))
            ci.append(md.v(p + n_ * (lift - 0.0045 * (1 - v) ** 0.8 - 0.0007), rule))
        outer.append(co)
        inner.append(ci)
    for i in range(n):
        for j in range(rows):
            uv = [(i * 0.08, 3 - j * 0.25), ((i + 1) * 0.08, 3 - j * 0.25), ((i + 1) * 0.08, 3 - (j + 1) * 0.25),
                  (i * 0.08, 3 - (j + 1) * 0.25)]
            k = len(md.faces)
            md.f((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]), "Hair", True, uv)
            PF.orient_face(md, k, lambda c_: c_ - PF.HC)
            k = len(md.faces)
            md.f((inner[i][j], inner[i + 1][j], inner[i + 1][j + 1], inner[i][j + 1]), "Hair", True, uv)
            PF.orient_face(md, k, lambda c_: PF.HC - c_)
        k = len(md.faces)
        md.f((outer[i][-1], outer[i + 1][-1], inner[i + 1][-1], inner[i][-1]), "Hair", True,
             [(0, 0), (0.1, 0), (0.1, 0.05), (0, 0.05)])
        PF.orient_face(md, k, lambda c_: Vector((0.3, 0, -1.0)))
    for i in (0, n):
        for j in range(rows):
            md.f((outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j]), "Hair", True,
                 [(0, 0), (0.05, 0), (0.05, 0.1), (0, 0.1)])


def fix_hair_orientation(md):
    """Cap and curtain outer faces point away from the head centre (the inner curtain faces were built reversed)."""
    return md
