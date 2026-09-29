"""
Frontier Habitat 5.0 - ART-NPC: modelled heads for the people (V5 section 1: "must hold up at 1.5 m").

One head per variant from a parameter set.  Method:
  * the head surface is a function of (theta, phi): theta from the left ear (+y) to the right ear (-y), phi round the
    y axis (0 = the front, +90 = up).  The poles are at the ears, so the face has no pole.
  * points: constraint loops (eye openings, lid rings, mouth slit, lip rings, nose outline) plus a Poisson-style fill
    with a spacing function (dense round the eyes, nose and mouth, coarse at the back); constrained Delaunay in the
    parameter plane with the eye openings and the mouth slit as holes.
  * 3D: an ellipsoid skull, a longer and forward lower face, a jaw taper, then feature displacements (nose, brows,
    eye sockets, cheekbones, lips, chin) defined in front coordinates (y, z).
  * eye openings get a lid margin that turns in onto the eyeball; the mouth slit gets a lip roll, a cavity and teeth.
  * bones: head; jaw (the lower face, lower lip, lower teeth, cavity floor); lids (upper lids).  The neck is a tube.
UV: cylindrical round the head's vertical axis (the face texture of the variant, people_textures.py).
"""
import os
import sys
import math
from math import sin, cos, pi, radians, degrees, sqrt, atan2, acos, asin, exp

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
from npc_common import Chain, sstep                              # noqa: E402
from mathutils import Vector                                     # noqa: E402
from mathutils.geometry import delaunay_2d_cdt                   # noqa: E402
from people_mesh import MeshData                                 # noqa: E402

HC = Vector((0.024, 0.0, 1.660))          # head centre (between the ears)

# face bones added to the v3 skeleton for the people rig
FACE_BONES = [
    ("jaw", "head", (0.004, 0.0, 1.628), (0.086, 0.0, 1.574)),
    ("lids", "head", (0.093, 0.0, 1.666), (0.123, 0.0, 1.666)),
]

BASE = dict(
    sex="m",
    rx=0.100, ry=0.077, rz=0.110,          # skull half depth, half width, half height
    chin_drop=0.16, muzzle=0.005, jaw_taper=0.10, jaw_width=0.06,
    eye_y=0.0325, eye_z=0.006, eye_w=0.0145, eye_up=0.0072, eye_low=0.0046, eye_tilt=0.0015, eye_r=0.0118,
    eye_x=0.071,                           # eyeball centre, forward of HC
    nose_tip=0.020, nose_len=1.0, nose_w=1.0, nose_bridge=0.0,
    brow=0.0055, cheek=0.0055, lip_up=0.0040, lip_low=0.0055, mouth_w=0.0240, mouth_z=-0.0560,
    chin=0.0170, chin_w=0.020, neck_r=0.057, adam=0.004,
    iris=0,                                # iris cell in people_eyes.png
)

VARIANTS = {
    "m1": dict(BASE),
    "f1": dict(BASE, sex="f", rx=0.096, ry=0.074, rz=0.104, chin_drop=0.13, muzzle=0.004, jaw_taper=0.20,
               jaw_width=0.0, eye_w=0.0152, eye_up=0.0074, eye_r=0.0120, nose_tip=0.0135, nose_len=0.88, nose_w=0.80,
               brow=0.0030,
               cheek=0.0070, lip_up=0.0060, lip_low=0.0078, mouth_w=0.0225, chin=0.0110, chin_w=0.015,
               neck_r=0.049, adam=0.0, iris=1),
}


# ------------------------------------------------------------------------------------------------------------------
# the surface
# ------------------------------------------------------------------------------------------------------------------
def base_point(th, ph, P):
    """Head-local point (origin HC) before the features."""
    dx, dy, dz = sin(th) * cos(ph), cos(th), sin(th) * sin(ph)
    x, y, z = P["rx"] * dx, P["ry"] * dy, P["rz"] * dz
    front = max(0.0, dx)
    if dz > 0:
        # the cranium: widest a little above the ears, a rounder (squarer) top, the back of the skull fuller
        y *= 1.0 + 0.11 * sin(pi * min(1.0, dz * 1.15)) * (1.0 - 0.3 * front)
        x *= 1.0 + 0.05 * sin(pi * dz) * max(0.0, -dx)
        z *= 1.0 - 0.06 * dz * dz
    if dz < 0:
        z *= 1.0 + P["chin_drop"] * front ** 1.5
        # the back underside (skull base) higher: the neck carries it
        z *= 1.0 - 0.28 * max(0.0, -dx) ** 1.2
        # a jaw: the underside from the chin back to the jaw angle is a flatter plane, not a round bowl
        under = sstep(-0.55, -0.95, dz) * sstep(-0.35, 0.15, dx)
        z *= 1.0 + 0.22 * under * (1.0 - 0.5 * front)
    # muzzle: mouth and chin forward
    x += P["muzzle"] * exp(-((z + 0.058) / 0.042) ** 2) * exp(-(y / 0.048) ** 2) * front
    # jaw taper towards the chin (front, low)
    y *= 1.0 - P["jaw_taper"] * sstep(-0.015, -0.105, z) * front ** 0.6
    y *= 1.0 + P["jaw_width"] * sstep(-0.03, -0.08, z) * sstep(0.9, 0.2, front)
    # the jaw angle below the ear: a firmer corner
    y *= 1.0 + 0.05 * exp(-((z + 0.078) / 0.022) ** 2) * sstep(-0.5, 0.1, dx) * sstep(0.95, 0.4, front)
    # occiput
    x -= 0.008 * max(0.0, -dx) * exp(-((z - 0.01) / 0.05) ** 2)
    return Vector((x, y, z))


def surface_normal(th, ph, P, h=2e-4):
    """Outward normal of the head surface from the function (smooth shading independent of the triangles)."""
    th = min(max(th, 0.02), pi - 0.02)
    p0 = surface(th, ph, P)
    a = surface(th + h, ph, P) - surface(th - h, ph, P)
    b = surface(th, ph + h, P) - surface(th, ph - h, P)
    n = b.cross(a)
    if n.length < 1e-12:
        return p0.normalized()
    n.normalize()
    if n.dot(p0) < 0:
        n = -n
    return n


def g2(y, z, cy, cz, sy, sz):
    return exp(-((y - cy) / sy) ** 2 - ((z - cz) / sz) ** 2)


def nose_disp(y, z, P):
    """Forward displacement of the nose (front coordinates, head-local)."""
    L = P["nose_len"]
    z_rad, z_tip, z_sub = 0.000, -0.029 * L, -0.040 * L
    ay = abs(y)
    if z > z_rad + 0.012 or z < z_sub - 0.006:
        return 0.0
    # profile height
    if z >= z_tip:
        t = max(0.0, min(1.0, (z_rad + 0.012 - z) / (z_rad + 0.012 - z_tip)))
        h = P["nose_tip"] * (0.10 + 0.90 * t ** 1.7) + P["nose_bridge"] * sin(pi * t)
        w = 0.0075 + (0.0125 - 0.0075) * t ** 2
    else:
        t = max(0.0, min(1.0, (z - z_sub) / (z_tip - z_sub)))     # 0 at subnasale, 1 at the tip
        h = P["nose_tip"] * (0.10 + 0.90 * sin(0.5 * pi * t) ** 0.8)
        w = 0.0125 + 0.004 * (1 - t)
    w *= P["nose_w"]
    d = h * exp(-(ay / w) ** 2.6)
    # a rounded tip (the lobule) and the alae (wings) at the base
    d += 0.0035 * P["nose_w"] * g2(ay, z, 0.0, z_tip + 0.0015, 0.0085, 0.0060)
    d += 0.0072 * P["nose_w"] * g2(ay, z, 0.0150 * P["nose_w"], -0.0335 * L, 0.0070, 0.0065)
    return d


def features(y, z, P, front):
    if front <= 0.0:
        return 0.0
    d = nose_disp(y, z, P)
    ay = abs(y)
    # glabella and brow ridge
    d += P["brow"] * exp(-((z - 0.025) / 0.009) ** 2) * sstep(0.058, 0.035, ay)
    d -= 0.0095 * g2(ay, z, 0.0, 0.008, 0.012, 0.008)                 # radix dip between the eyes (nasion)
    # eye sockets
    d -= 0.0105 * g2(ay, z, P["eye_y"], P["eye_z"] - 0.002, 0.019, 0.012)
    # cheekbones
    d += P["cheek"] * g2(ay, z, 0.046, -0.024, 0.018, 0.015)
    # upper lip with the philtrum, lower lip, the groove under it, the chin
    mz = P["mouth_z"]
    mw = P["mouth_w"]
    lipw = exp(-(ay / (mw * 0.92)) ** 3)
    d += P["lip_up"] * exp(-((z - (mz + 0.0065)) / 0.0058) ** 2) * lipw
    d -= 0.0014 * g2(ay, z, 0.0, mz + 0.012, 0.0035, 0.006)
    d += P["lip_low"] * exp(-((z - (mz - 0.0068)) / 0.0055) ** 2) * exp(-(ay / (mw * 0.80)) ** 3)
    d -= 0.0022 * g2(ay, z, 0.0, mz - 0.018, 0.016, 0.004)
    d += P["chin"] * g2(ay, z, 0.0, mz - 0.040, P["chin_w"], 0.016)
    return d * front


def surface(th, ph, P):
    b = base_point(th, ph, P)
    front = max(0.0, sin(th) * cos(ph))
    front = sstep(0.15, 0.55, front)
    d = features(b.y, b.z, P, front)
    return b + Vector((d, 0.0, 0.0))


# parameter plane: u = (90 deg - theta) * RU (left +), v = phi * RV
RU, RV = 0.078, 0.108


def to_uv(th, ph):
    return ((pi / 2 - th) * RU, ph * RV)


def from_uv(u, v):
    return (pi / 2 - u / RU, v / RV)


def front_to_param(y, z, P):
    """(theta, phi) of the front surface point whose head-local (y, z) is about (y, z) (a few Newton steps)."""
    th = acos(max(-0.999, min(0.999, y / P["ry"])))
    ph = asin(max(-0.999, min(0.999, z / (P["rz"] * sin(th)))))
    for _ in range(12):
        p = base_point(th, ph, P)
        ey, ez = y - p.y, z - p.z
        if abs(ey) < 1e-6 and abs(ez) < 1e-6:
            break
        h = 1e-4
        py = (base_point(th + h, ph, P) - p) / h
        pz = (base_point(th, ph + h, P) - p) / h
        det = py.y * pz.z - py.z * pz.y
        if abs(det) < 1e-12:
            break
        dth = (ey * pz.z - ez * pz.y) / det
        dph = (py.y * ez - py.z * ey) / det
        th += max(-0.2, min(0.2, dth))
        ph += max(-0.2, min(0.2, dph))
    return th, ph


# ------------------------------------------------------------------------------------------------------------------
# loops (front coordinates)
# ------------------------------------------------------------------------------------------------------------------
def almond(P, s, scale=1.0, n=16):
    """Eye opening outline, side s (+1 left, -1 right), counter-clockwise in (u, v): (y, z) points."""
    cy, cz = s * P["eye_y"], P["eye_z"]
    w, hu, hl, tilt = P["eye_w"] * scale, P["eye_up"] * scale, P["eye_low"] * scale, P["eye_tilt"]
    pts = []
    for k in range(n):
        a = 2 * pi * k / n
        c, sn = cos(a), sin(a)
        yy = cy + s * w * c                                    # +c = the outer corner
        if sn >= 0:
            zz = cz + hu * sn ** 0.85 * (1 + 0.18 * (-c))      # upper lid peaks a little towards the inner corner
        else:
            zz = cz + hl * sn * (1 - 0.1 * c)
        zz += tilt * c                                        # the outer corner a little higher
        pts.append((yy, zz))
    if s < 0:
        pts = list(reversed(pts))
    return pts


def mouth_loop(P, scale_w=1.0, open_h=0.0010, n_half=7):
    """Mouth slit (thin lens): left corner -> upper -> right corner -> lower.  (y, z) points."""
    mw, mz = P["mouth_w"] * scale_w, P["mouth_z"]
    up, low = [], []
    for k in range(n_half + 1):
        t = -1 + 2 * k / n_half                               # -1 .. 1 across
        y = mw * t
        bow = 0.0012 * exp(-(t / 0.25) ** 2) - 0.0006 * t * t  # cupid's bow in the middle, corners slightly down
        up.append((y, mz + open_h * (1 - t * t) + bow * 0.5))
        low.append((y, mz - open_h * (1 - t * t) - 0.0004 * (1 - t * t)))
    pts = up + list(reversed(low[1:-1]))
    return pts, len(up)


def ring(pts, scale, cy, cz):
    return [(cy + (y - cy) * scale, cz + (z - cz) * scale) for (y, z) in pts]


# ------------------------------------------------------------------------------------------------------------------
def spacing(y, z, front, P):
    """Target point spacing (m) at a front point."""
    if front < 0.3:
        return 0.016
    s = 0.0085
    ay = abs(y)
    # face zone
    if ay < 0.065 and -0.115 < z < 0.055:
        s = 0.0060
    if ay < 0.022 and -0.048 < z < 0.020:                    # nose
        s = 0.0038
    if abs(ay - P["eye_y"]) < 0.024 and abs(z - P["eye_z"]) < 0.016:
        s = 0.0040
    if ay < P["mouth_w"] + 0.012 and abs(z - P["mouth_z"]) < 0.020:
        s = 0.0040
    return s


def build_head(variant):
    P = VARIANTS[variant]
    md = MeshData("Head_%s" % variant)
    # ---- constraint loops in (y, z) front coordinates ----
    loops = []                         # (points (y,z), closed, kind)
    eye_open = {}
    for s in (1, -1):
        op = almond(P, s, 1.0, 18)
        eye_open[s] = op
        loops.append((op, "hole", "eye%d" % s))
        cy = s * P["eye_y"]
        loops.append((ring(op, 1.45, cy, P["eye_z"]), "ring", "lid%d" % s))
        loops.append((ring(op, 2.05, cy, P["eye_z"]), "ring", "orbit%d" % s))
    mo, nu = mouth_loop(P)
    loops.append((mo, "hole", "mouth"))
    mo2, _ = mouth_loop(P, 1.10, 0.0070)
    loops.append((mo2, "ring", "lips"))
    mo3, _ = mouth_loop(P, 1.30, 0.0135)
    loops.append((mo3, "ring", "lipring"))
    # ---- 2D points ----
    pts2, keys = [], {}

    def addp(uv, tag=None):
        pts2.append(uv)
        return len(pts2) - 1
    loop_idx = []
    for (lp, kind, name) in loops:
        ids = []
        for (y, z) in lp:
            th, ph = front_to_param(y, z, P)
            ids.append(addp(to_uv(th, ph)))
        loop_idx.append((ids, kind, name))
    # domain: theta in [T0, T1], phi in [-pi, pi]
    T0, T1 = radians(12.0), radians(168.0)
    umax = (pi / 2 - T0) * RU
    vmax = pi * RV
    # boundary: rows at u = +-umax, columns at v = +-vmax
    nb_v = 40
    border_l, border_r = [], []
    for k in range(nb_v + 1):
        v = -vmax + 2 * vmax * k / nb_v
        border_l.append(addp((umax, v)))
        border_r.append(addp((-umax, v)))
    nb_u = 14
    border_b, border_t = [], []                       # at v = -vmax / +vmax (the back seam), excluding corners
    for k in range(1, nb_u):
        u = umax - 2 * umax * k / nb_u
        border_b.append(addp((u, -vmax)))
        border_t.append(addp((u, vmax)))
    # fill points (dart throwing on a jittered grid, spacing from the front position)
    import random
    rnd = random.Random(7 + len(variant))
    step = 0.0019
    cand = []
    nu_, nv_ = int(2 * umax / step), int(2 * vmax / step)
    for i in range(nu_):
        for j in range(nv_):
            u = -umax + (i + 0.5 + 0.3 * (rnd.random() - 0.5)) * step
            v = -vmax + (j + 0.5 + 0.3 * (rnd.random() - 0.5)) * step
            cand.append((u, v))
    rnd.shuffle(cand)
    # a coarse grid of accepted points for neighbour queries
    cell = 0.004
    grid = {}

    def gkey(u, v):
        return (int((u + 1) / cell), int((v + 1) / cell))

    def put(i):
        u, v = pts2[i]
        grid.setdefault(gkey(u, v), []).append(i)
    for i in range(len(pts2)):
        put(i)

    def sp_at(u, v):
        th, ph = from_uv(u, v)
        b = base_point(th, ph, P)
        front = max(0.0, sin(th) * cos(ph))
        return spacing(b.y, b.z, front, P), b, front
    # the holes: reject candidates inside the eye openings and the mouth (point in polygon in uv)
    holes_uv = [[pts2[i] for i in ids] for ids, kind, name in loop_idx if kind == "hole"]

    def inside(poly, u, v):
        c = False
        n = len(poly)
        for k in range(n):
            (u1, v1), (u2, v2) = poly[k], poly[(k + 1) % n]
            if (v1 > v) != (v2 > v) and u < (u2 - u1) * (v - v1) / (v2 - v1 + 1e-12) + u1:
                c = not c
        return c
    for (u, v) in cand:
        if abs(u) > umax - 0.004 or abs(v) > vmax - 0.004:
            continue
        s, b, front = sp_at(u, v)
        s *= 0.92
        if any(inside(h, u, v) for h in holes_uv):
            continue
        ku, kv = gkey(u, v)
        ok = True
        r = int(s / cell) + 1
        for a in range(-r, r + 1):
            for c in range(-r, r + 1):
                for i in grid.get((ku + a, kv + c), ()):
                    pu, pv = pts2[i]
                    if (pu - u) ** 2 + (pv - v) ** 2 < s * s:
                        ok = False
                        break
                if not ok:
                    break
            if not ok:
                break
        if ok:
            i = addp((u, v))
            put(i)
    # ---- constrained triangulation ----
    edges = []
    faces_in = []
    # outer polygon: bottom edge (v = -vmax) by rising u, the u = +umax side, the top edge back, the u = -umax side
    poly = [border_r[0]]
    bb = sorted(border_b, key=lambda i: pts2[i][0])
    poly += bb
    poly += border_l
    bt = sorted(border_t, key=lambda i: -pts2[i][0])
    poly += bt
    poly += list(reversed(border_r))[:-1]
    faces_in.append(poly)
    for ids, kind, name in loop_idx:
        if kind == "hole":
            faces_in.append(ids)
        for k in range(len(ids)):
            edges.append((ids[k], ids[(k + 1) % len(ids)]))
    vco = [Vector((u, v)) for (u, v) in pts2]
    out = delaunay_2d_cdt(vco, edges, faces_in, 2, 1e-7)
    overts, oedges, ofaces, orig_v = out[0], out[1], out[2], out[3]
    # ---- 3D ----
    params = [from_uv(p.x, p.y) for p in overts]
    pos = [surface(th, ph, P) for th, ph in params]
    # map output verts back to loop membership
    out_of = {}
    for oi, origs in enumerate(orig_v):
        for o in origs:
            out_of[o] = oi
    loops_out = {name: [out_of[i] for i in ids] for ids, kind, name in loop_idx}
    # merge the back seam: v = -vmax and v = +vmax columns are the same points
    return build_head_mesh(md, P, overts, ofaces, pos, params, loops_out, out_of, border_b, border_t, border_l,
                           border_r, umax, vmax, variant)


def head_rule(P):
    """Bone weights of a head-surface point (head-local position p): head, jaw (lower face), neck (bottom)."""
    mz = P["mouth_z"]

    def rule(pw):
        p = pw - HC
        out = {}
        front = sstep(-0.01, 0.04, p.x)
        # jaw: below the mouth line at the front, fading to the sides; the jaw angle follows a little
        j = sstep(mz + 0.002, mz - 0.010, p.z) * front * sstep(0.070, 0.045, abs(p.y))
        j = max(j, 0.6 * sstep(-0.045, -0.085, p.z) * sstep(0.02, 0.06, p.x + 0.02) * sstep(0.08, 0.05, abs(p.y)))
        j = min(1.0, j)
        n = sstep(-0.075, -0.125, p.z) * (1 - front)
        out["jaw"] = j
        out["neck"] = n * (1 - j)
        out["head"] = max(0.0, 1.0 - j - out["neck"])
        return out
    return rule


def build_head_mesh(md, P, overts, ofaces, pos, params, loops_out, out_of, border_b, border_t, border_l, border_r,
                    umax, vmax, variant):
    rule = head_rule(P)
    # seam merge: vertices on v = +vmax map to the matching v = -vmax vertex (same u)
    n = len(overts)
    remap = list(range(n))
    lo = {}
    for i, p in enumerate(overts):
        if abs(p.y + vmax) < 1e-6:
            lo[round(p.x, 6)] = i
    for i, p in enumerate(overts):
        if abs(p.y - vmax) < 1e-6:
            j = lo.get(round(p.x, 6))
            if j is not None:
                remap[i] = j
    vid = {}
    for i in range(n):
        if remap[i] == i:
            vid[i] = md.v(HC + pos[i], rule)
            md.normals[vid[i]] = surface_normal(params[i][0], params[i][1], P)
    for i in range(n):
        if remap[i] != i:
            vid[i] = vid[remap[i]]
    mouth_set = set(loops_out["mouth"])
    for f in ofaces:
        ids = [vid[i] for i in f]
        if len(set(ids)) < 3:
            continue
        # CDT faces come counter-clockwise in (u, v); u = left, v = up -> on the surface that faces outward? check
        md.f(ids, "Skin", True)
    # pole caps at the ears (u = +-umax rows)
    for side, row in ((1, "l"), (-1, "r")):
        rim = [i for i in range(n) if abs(overts[i].x - side * umax) < 1e-6]
        rim.sort(key=lambda i: overts[i].y)
        th = pi / 2 - side * (pi / 2)
        pole = md.v(HC + surface(0.0 if side > 0 else pi, 0.0, P), rule)
        rimv = []
        for i in rim:
            if vid[i] not in rimv:
                rimv.append(vid[i])
        for k in range(len(rimv)):
            a, b = rimv[k], rimv[(k + 1) % len(rimv)]
            if a == b:
                continue
            md.f((a, b, pole) if side > 0 else (b, a, pole), "Skin", True)
    fix_orientation(md, HC)
    add_eyelids(md, P, loops_out, vid)
    add_mouth(md, P, loops_out, vid)
    add_eyes(md, P)
    add_neck(md, P)
    add_ears(md, P)
    cylindrical_uv(md)
    return md


def orient_face(md, k, want):
    """Flip face k (and its UVs) if its normal points against want(centroid) (a vector)."""
    f = md.faces[k]
    a, b, c = (md.verts[i] for i in f[:3])
    nrm = (b - a).cross(c - a)
    if len(f) == 4:
        nrm += (c - a).cross(md.verts[f[3]] - a)
    mid = sum((md.verts[i] for i in f), Vector()) / len(f)
    if nrm.dot(want(mid)) < 0:
        md.faces[k] = tuple(reversed(f))
        if md.fuv[k]:
            md.fuv[k] = list(reversed(md.fuv[k]))


def fix_orientation(md, centre):
    """Make every Skin face of the head shell point away from the centre."""
    for k, f in enumerate(md.faces):
        if md.fmat[k] != "Skin":
            continue
        a, b, c = (md.verts[i] for i in f[:3])
        nrm = (b - a).cross(c - a)
        mid = (a + b + c) / 3
        if nrm.dot(mid - centre) < 0:
            md.faces[k] = tuple(reversed(f))


def eye_centre(P, s):
    return HC + Vector((P["eye_x"], s * P["eye_y"], P["eye_z"]))


def add_eyelids(md, P, loops_out, vid):
    """The opening rim turns in onto the eyeball: a margin ring on the eyeball sphere (+0.4 mm)."""
    er = P["eye_r"]
    lids = Chain(["head", "lids"], [])
    for s in (1, -1):
        E = eye_centre(P, s)
        rim = [vid[i] for i in loops_out["eye%d" % s]]
        # project the rim onto the sphere of radius er + 1.0 mm round the eyeball (it hugs the eye)
        for i in rim:
            d = md.verts[i] - E
            md.verts[i] = E + d.normalized() * (er + 0.0012)
            md.normals.pop(i, None)
        inner = []
        for i in rim:
            d = md.verts[i] - E
            q = E + (d.normalized() * (er + 0.0003))
            q = E + ((q - E) * 0.985)
            upper = md.verts[i].z > E.z + 0.0005
            inner.append(md.v(q, {"lids": 1.0} if upper else {"head": 1.0}))
        # upper lid rim and the next rows ride the lids bone
        for i in rim:
            if md.verts[i].z > E.z + 0.0005:
                md.rules[i] = {"lids": 1.0}
        m = len(rim)
        for k in range(m):
            a, b = rim[k], rim[(k + 1) % m]
            c, d = inner[(k + 1) % m], inner[k]
            f0 = len(md.faces)
            md.f((a, b, c, d), "Skin", True)
            # the visible side of the lid edge faces the opening's centre line (through E along +x)
            orient_face(md, f0, lambda c_, E=E: Vector((0.0, E.y - c_.y, E.z - c_.z)))
        # the lid ring (1.45 x): the upper part follows the lids by half
        for i in (vid[j] for j in loops_out["lid%d" % s]):
            if md.verts[i].z > E.z + 0.002:
                md.rules[i] = {"lids": 0.55, "head": 0.45}
    return md


def add_mouth(md, P, loops_out, vid):
    """Lip roll into a cavity with teeth.  Upper half: head; lower half: jaw."""
    rim = [vid[i] for i in loops_out["mouth"]]
    for i in rim:
        md.normals.pop(i, None)
    mz = P["mouth_z"] + HC.z
    cx = sum(md.verts[i].x for i in rim) / len(rim)
    upper = [md.verts[i].z >= mz for i in rim]
    for i, up in zip(rim, upper):
        md.rules[i] = {"head": 1.0} if up else {"jaw": 1.0}
    rows = [rim]
    shapes = [(-0.004, 0.92, 1.0), (-0.012, 0.82, 1.8), (-0.030, 0.62, 4.0)]
    for dx, sw, sh in shapes:
        row = []
        for i, up in zip(rim, upper):
            p = md.verts[i]
            q = Vector((p.x + dx - 0.004 * (1 - (abs(p.y) / (P["mouth_w"] + 1e-6)) ** 2), p.y * sw,
                        mz + (p.z - mz) * sh + (0.003 if up else -0.004) * (sh - 1) / 3.0))
            row.append(md.v(q, {"head": 1.0} if up else {"jaw": 1.0}))
        rows.append(row)
    m = len(rim)
    axis = lambda c_: Vector((0.0, -c_.y * 0.3, mz - c_.z))            # noqa: E731  (into the mouth)
    for r in range(len(rows) - 1):
        mat = "LipInner" if r == 0 else "Mouth"
        for k in range(m):
            a, b = rows[r][k], rows[r][(k + 1) % m]
            c, d = rows[r + 1][(k + 1) % m], rows[r + 1][k]
            f0 = len(md.faces)
            md.f((a, d, c, b), mat, True, None)
            orient_face(md, f0, axis)
            if r == 0:
                md.fuv[f0] = None
    back = rows[-1]
    cen = md.v(sum((md.verts[i] for i in back), Vector()) / len(back) + Vector((-0.006, 0, 0)), {"head": 0.5, "jaw": 0.5})
    for k in range(m):
        f0 = len(md.faces)
        md.f((back[k], cen, back[(k + 1) % m]), "Mouth", True)
        orient_face(md, f0, lambda c_: Vector((1.0, 0.0, 0.0)))
    # teeth: an arc behind the lips, upper on the head, lower on the jaw
    tx = cx - 0.009
    for up in (True, False):
        arc = []
        for k in range(9):
            t = -1 + 2 * k / 8
            y = t * P["mouth_w"] * 0.95
            x = tx - 0.010 * t * t
            arc.append((x, y))
        z0 = mz + (0.0005 if up else -0.0005)
        z1 = mz + (0.0085 if up else -0.0070)
        top = [md.v((x, y, z0), {"head": 1.0} if up else {"jaw": 1.0}) for x, y in arc]
        bot = [md.v((x - 0.001, y, z1), {"head": 1.0} if up else {"jaw": 1.0}) for x, y in arc]
        for k in range(8):
            f0 = len(md.faces)
            md.f((top[k], top[k + 1], bot[k + 1], bot[k]), "Teeth", True)
            orient_face(md, f0, lambda c_: Vector((1.0, 0.0, 0.0)))


def add_eyes(md, P, seg=14, rings=9):
    """Eyeballs: iris towards +x.  UV: the front pole at the cell centre of people_eyes.png (4 cells in a row)."""
    er = P["eye_r"]
    cell = P["iris"]
    for s in (1, -1):
        E = eye_centre(P, s)
        ids = []
        for j in range(rings + 1):
            a = pi * j / rings                     # 0 = front pole
            row = []
            for i in range(seg):
                b = 2 * pi * i / seg
                d = Vector((cos(a), sin(a) * cos(b), sin(a) * sin(b)))
                d = Vector((d.x, d.y + 0.03 * s * d.x, d.z)).normalized()     # a slight outward look
                row.append(md.v(E + d * er, {"head": 1.0}))
            ids.append(row)
        for j in range(rings):
            for i in range(seg):
                k = (i + 1) % seg
                f = (ids[j][i], ids[j + 1][i], ids[j + 1][k], ids[j][k])
                uv = []
                for (jj, ii) in ((j, i), (j + 1, i), (j + 1, k), (j, k)):
                    a = pi * jj / rings
                    b = 2 * pi * ii / seg
                    r = min(1.0, a / (pi * 0.5)) * 0.5
                    uv.append(((cell + 0.5 + r * cos(b)) / 4.0, 0.5 + r * sin(b)))
                f0 = len(md.faces)
                md.f(f, "Eye", True, uv)
                orient_face(md, f0, lambda c, E=E: c - E)


def add_neck(md, P):
    r = P["neck_r"]
    seg = 16
    stations = [(1.455, 1.25), (1.480, 1.10), (1.520, 1.00), (1.580, 0.98), (1.620, 0.95)]
    rule = Chain(["chest", "neck", "head"], [((0, 0, 1.490), (0, 0, 1), 0.025), ((0, 0, 1.585), (0, 0, 1), 0.025)])
    ids = []
    for z, sc in stations:
        row = []
        for i in range(seg):
            a = 2 * pi * i / seg
            x = 0.012 + (z - 1.44) * 0.12 + r * sc * cos(a) * (1.02 if cos(a) > 0 else 0.98)
            y = r * sc * sin(a)
            if P["adam"] > 0 and cos(a) > 0.85:
                x += P["adam"] * exp(-((z - 1.55) / 0.018) ** 2)
            row.append(md.v((x, y, z), rule))
        ids.append(row)
    for j in range(len(ids) - 1):
        for i in range(seg):
            k = (i + 1) % seg
            f0 = len(md.faces)
            md.f((ids[j][i], ids[j][k], ids[j + 1][k], ids[j + 1][i]), "Skin", True)
            orient_face(md, f0, lambda c_: Vector((c_.x - 0.02, c_.y, 0.0)))


def add_ears(md, P):
    """Ear: a rim (helix) round a shallow bowl, tilted back; lobes at the bottom."""
    for s in (1, -1):
        c = HC + Vector((-0.010, s * (P["ry"] - 0.004), -0.004))
        n = 12
        rim_o, rim_i, bowl = [], [], []
        for k in range(n):
            a = 2 * pi * k / n
            ex, ez = 0.017 * cos(a), 0.029 * sin(a) * (1.0 if sin(a) > 0 else 0.9)
            if sin(a) < -0.6:
                ex *= 0.8
            tilt = radians(14)
            px, pz = ex * cos(tilt) - ez * sin(tilt), ex * sin(tilt) + ez * cos(tilt)
            rim_o.append(md.v(c + Vector((px, s * 0.013, pz)), {"head": 1.0}))
            rim_i.append(md.v(c + Vector((px * 0.78, s * 0.016, pz * 0.82)), {"head": 1.0}))
            bowl.append(md.v(c + Vector((px * 0.55, s * 0.006, pz * 0.6)), {"head": 1.0}))
        root = [md.v(c + Vector((0.017 * cos(2 * pi * k / n) * 0.7, -s * 0.004, 0.026 * sin(2 * pi * k / n) * 0.7)),
                     {"head": 1.0}) for k in range(n)]
        cen = md.v(c + Vector((0.0, s * 0.002, 0.0)), {"head": 1.0})
        # the back side: its own vertices 1 mm behind (a thin shell seen from both sides)
        off = Vector((0.0, -s * 0.0012, 0.0))
        dup = {}

        def back(i):
            if i not in dup:
                dup[i] = md.v(md.verts[i] + off, {"head": 1.0})
            return dup[i]
        for k in range(n):
            j = (k + 1) % n
            for a, b in ((root, rim_o), (rim_o, rim_i), (rim_i, bowl)):
                f = (a[k], a[j], b[j], b[k])
                f0 = len(md.faces)
                md.f(f, "Skin", True)
                orient_face(md, f0, lambda c_, c=c: Vector((0.0, s, 0.0)))
                g = tuple(back(i) for i in f)
                f1 = len(md.faces)
                md.f(g, "Skin", True)
                orient_face(md, f1, lambda c_, c=c: Vector((0.0, -s, 0.0)))
            f = (bowl[k], bowl[j], cen)
            f0 = len(md.faces)
            md.f(f, "Skin", True)
            orient_face(md, f0, lambda c_: Vector((0.0, s, 0.0)))


def cylindrical_uv(md):
    """UV for the Skin faces: u round the vertical axis through the head centre (0.5 = front, seam at the back),
    v = height.  Faces that straddle the seam wrap."""
    z0, zh = HC.z - 0.23, 0.36
    for k, f in enumerate(md.faces):
        if md.fmat[k] != "Skin" or md.fuv[k] is not None:
            continue
        us = []
        for i in f:
            p = md.verts[i] - HC
            us.append(0.5 + atan2(p.y, p.x) / (2 * pi))
        if max(us) - min(us) > 0.5:
            us = [u + 1.0 if u < 0.5 else u for u in us]
            us = [u - 1.0 if min(us) > 1.0 else u for u in us]
        md.fuv[k] = [(u, (md.verts[i].z - z0) / zh) for u, i in zip(us, f)]
