"""
Frontier Habitat 5.0 - ART-NPC: outfits (V5 section 1).  One outfit = one skinned mesh `Outfit_<id>` that contains the
garments AND the skin they leave visible (forearms, hands), so no body part can poke through.  Built in the v3 1.80 m
frame; people_build.py scales the variant.

Pilot: uniform_engineering, casual_a (male and female cuts).
"""
import os
import sys
from math import sin, cos, pi, radians, exp

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
from npc_common import (Chain, sstep, torso_rule, arm_rule, leg_rule, side_vec, frame_from,     # noqa: E402
                        SH_JOINT, EL_JOINT, WR_JOINT, _UA, _FA, HIP_JOINT, KNEE_JOINT, ANKLE_JOINT)
from mathutils import Vector, Matrix                             # noqa: E402
from people_mesh import MeshData                                 # noqa: E402
import people_body as B                                          # noqa: E402

TR = torso_rule(pelvis_thigh=0.5)


def arm_pts(s):
    sh, el, wr = side_vec(SH_JOINT, s), side_vec(EL_JOINT, s), side_vec(WR_JOINT, s)
    ua = side_vec(_UA, s)
    return [sh - ua * 0.045, sh, el, wr], (el - sh).length + 0.045, (el - sh).length + 0.045 + (wr - el).length


def leg_pts(s):
    hip, kn, an = side_vec(HIP_JOINT, s), side_vec(KNEE_JOINT, s), side_vec(ANKLE_JOINT, s)
    th = (kn - hip).normalized()
    return [hip - th * 0.07, hip, kn, an], 0.07 + (kn - hip).length, 0.07 + (kn - hip).length + (an - kn).length


def sleeve(md, s, sex, mat, end_s, loose=1.0, cuff_mat=None, cuff=True, folds=True):
    pts, s_el, s_wr = arm_pts(s)
    f = 0.92 if sex == "f" else 1.0
    st = [
        # a closed, rounded deltoid cap: when the arm drops from the bind pose the part that turns out of the torso
        # is a smooth shoulder, never an open tube end
        (0.000, 0.006 * f * loose, 0.006 * f * loose, mat, 0.0, 0.016),
        (0.014, 0.028 * f * loose, 0.030 * f * loose, mat, 0.0, 0.014),
        (0.032, 0.044 * f * loose, 0.046 * f * loose, mat, 0.0, 0.010),
        (0.058, 0.055 * f * loose, 0.058 * f * loose, mat, 0.0, 0.005),
        (0.100, 0.061 * f * loose, 0.063 * f * loose, mat, 0.0, 0.001),
        (0.160, 0.060 * f * loose, 0.062 * f * loose, mat),
        (s_el - 0.040, 0.055 * f * loose, 0.057 * f * loose, mat),
        (s_el + 0.010, 0.054 * f * loose, 0.054 * f * loose, mat),
        (s_el + 0.080, 0.053 * f * loose, 0.051 * f * loose, mat),
        (s_wr - 0.080, 0.046 * f * loose, 0.045 * f * loose, mat),
    ]
    st = [x for x in st if x[0] < end_s - 0.012]
    if cuff:
        r = st[-1][1] * 0.98
        st += [(end_s - 0.012, r, r, cuff_mat or mat), (end_s, r * 1.02, r * 1.02, cuff_mat or mat),
               (end_s + 0.002, r * 0.86, r * 0.86, cuff_mat or mat)]
    fold = B.joint_folds(s_el - 0.005, amp=0.0035, width=0.055, n=4, inner=pi) if folds else None
    k0 = len(md.faces)
    rings = B.limb(md, pts, st, seg=22, rule=arm_rule(s), fold=fold)
    B.orient_all(md, k0, len(md.faces), B.poly_axis(pts))
    return rings


def bare_arm(md, s, sex, start_s):
    """Skin from start_s (inside the sleeve) to the wrist; the hand continues it."""
    pts, s_el, s_wr = arm_pts(s)
    f = 0.88 if sex == "f" else 1.0
    st = [(0.060, 0.056 * f, 0.058 * f), (0.145, 0.050 * f, 0.052 * f), (s_el - 0.040, 0.043 * f, 0.044 * f),
          (s_el + 0.005, 0.041 * f, 0.040 * f), (s_el + 0.070, 0.044 * f, 0.041 * f), (s_wr - 0.070, 0.036 * f, 0.032 * f),
          (s_wr - 0.010, 0.029 * f, 0.024 * f), (s_wr + 0.012, 0.027 * f, 0.021 * f)]
    st = [(a, b, c, "Skin") for (a, b, c) in st if a >= start_s - 0.001]
    k0 = len(md.faces)
    B.limb(md, pts, st, seg=16, rule=arm_rule(s))
    B.orient_all(md, k0, len(md.faces), B.poly_axis(pts))


def trouser_leg(md, s, sex, mat, hem_s=None, loose=1.0, slim=1.0, stack=True):
    pts, s_kn, s_an = leg_pts(s)
    f = 0.95 if sex == "f" else 1.0
    hem = hem_s if hem_s is not None else s_an - 0.045
    st = [
        (0.000, 0.090 * f * loose, 0.092 * f * loose, mat),
        (0.080, 0.101 * f * loose, 0.099 * f * loose, mat, -0.004),
        (0.220, 0.089 * f * loose, 0.087 * f * loose, mat, -0.002),
        (s_kn - 0.060, 0.068 * f * loose * slim, 0.068 * f * loose * slim, mat),
        (s_kn + 0.010, 0.065 * f * loose * slim, 0.066 * f * loose * slim, mat),
        (s_kn + 0.100, 0.064 * f * loose * slim, 0.063 * f * loose * slim, mat, -0.006),
        (s_an - 0.140, 0.058 * f * loose * slim, 0.058 * f * loose * slim, mat, -0.003),
        (hem - 0.020, 0.057 * f * loose * slim, 0.057 * f * loose * slim, mat),
        (hem, 0.058 * f * loose * slim, 0.058 * f * loose * slim, mat),
        (hem + 0.002, 0.050 * f * slim, 0.050 * f * slim, mat),
    ]
    folds = [B.joint_folds(s_kn - 0.02, amp=0.0035, width=0.07, n=3, inner=pi)]
    if stack:
        folds.append(B.joint_folds(hem - 0.035, amp=0.0040, width=0.035, n=3, inner=0.0, phase=1.3))
    k0 = len(md.faces)
    rings = B.limb(md, pts, st, seg=24, rule=leg_rule(s), fold=B.sum_folds(*folds))
    B.orient_all(md, k0, len(md.faces), B.poly_axis(pts))
    return rings


def belt(md, sex, z0, z1, mat="Leather", buckle="Metal", off=0.018):
    rings = B.TORSO_M if sex == "m" else B.TORSO_F
    k0 = len(md.faces)
    ids = B.torso(md, sex, [z0 - 0.002, z0, z1, z1 + 0.002], lambda z: off if z0 <= z <= z1 else off - 0.006,
                  lambda k, i, p: mat, seg=28, rule=TR)
    B.orient_all(md, k0, len(md.faces), lambda p: Vector((0.0, 0.0, p.z)))
    af, ab, b, n, x0 = B.ring_at(rings, (z0 + z1) / 2)
    x = x0 + af + off + 0.002
    with md.w(TR):
        plate(md, (x + 0.003, 0.0, (z0 + z1) / 2), (0.006, 0.050, (z1 - z0) + 0.008), buckle)


def plate(md, c, size, mat, nrm=(1, 0, 0)):
    """A box without its back face, facing nrm (outward normal)."""
    cx, cy, cz = c
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    n = Vector(nrm).normalized()
    up = Vector((0, 0, 1))
    side = up.cross(n).normalized()
    upv = n.cross(side).normalized()
    C = Vector(c)

    def P(a, b, d):
        return md.v(C + n * (hx * d) + side * (hy * a) + upv * (hz * b))
    f = [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)]
    bk = [P(-1, -1, -1), P(1, -1, -1), P(1, 1, -1), P(-1, 1, -1)]
    md.f(tuple(f), mat, False)
    for i in range(4):
        j = (i + 1) % 4
        md.f((bk[i], bk[j], f[j], f[i]), mat, False)


def surface_pt(sex, y, z, off, front=True):
    rings = B.TORSO_M if sex == "m" else B.TORSO_F
    af, ab, b, n, x0 = B.ring_at(rings, z)
    q = min(0.999, abs(y) / (b + off))
    k = (1.0 - q ** n) ** (1.0 / n)
    x = x0 + ((af + off) * k if front else -(ab + off) * k)
    d = B.body_shape(sex)(y, z, x)
    return Vector((x + (d if front else -d), y, z)), Vector((1 if front else -1, 0, 0))


def collar(md, sex, z0, z1, r0, r1, mat, open_front=0.0):
    """A ring collar round the neck base (stand collar), open at the front by +-open_front rad."""
    rule = Chain(["chest", "neck"], [((0, 0, 1.50), (0, 0, 1), 0.02)])
    n = 40
    a0 = open_front
    angs = [a0 + (2 * pi - 2 * a0) * i / (n - 1) for i in range(n)] if a0 > 0 else [2 * pi * i / n for i in range(n)]
    closed = a0 <= 0
    rows = []
    for z, r, t in ((z0, r0, 0.0), (z1, r1, 0.0), (z1 + 0.002, r1 - 0.004, 0.0), (z0 + 0.004, r0 - 0.006, 0.0)):
        rows.append([md.v((0.010 + r * cos(a), r * sin(a) * 0.95, z), rule) for a in angs])
    k0 = len(md.faces)
    for k in range(3):
        a, b = rows[k], rows[k + 1]
        m = len(a) if closed else len(a) - 1
        for i in range(m):
            j = (i + 1) % len(a)
            md.f((a[i], a[j], b[j], b[i]), mat, True)
    # outward / inward by row: rows 0-1 outside, 2-3 inside
    B.orient_all(md, k0, k0 + (len(angs) if closed else len(angs) - 1), lambda p: Vector((0.010, 0.0, p.z)))


# ------------------------------------------------------------------------------------------------------------------
def uniform_engineering(sex):
    md = MeshData("Outfit_uniform_engineering")
    stripe_z = (1.330, 1.352)

    def tmat(k, i, p):
        return "SuitAccent" if stripe_z[0] - 0.001 <= p.z < stripe_z[1] - 0.001 else "Coverall"
    zs = [0.868, 0.880, 0.905, 0.950, 1.000, 1.060, 1.120, 1.190, 1.260, stripe_z[0], stripe_z[1], 1.375, 1.415,
          1.445, 1.470, 1.488]

    def disp(y, z, x, t):
        # waist bunching (the coverall gathers under the belt) and a little slack at the back
        return 0.0028 * exp(-((z - 1.075) / 0.018) ** 2) * (0.6 + 0.4 * sin(t * 9)) + \
            0.002 * exp(-((z - 1.12) / 0.05) ** 2) * (1 if x < 0 else 0)
    k0 = len(md.faces)
    rings = B.torso(md, sex, zs, lambda z: 0.013 - 0.005 * sstep(1.45, 1.488, z), tmat, seg=40, disp=disp)
    B.orient_all(md, k0, len(md.faces), lambda p: Vector((0.0, 0.0, p.z)))
    B.cap(md, rings[0], Vector((-0.012, 0.0, 0.862)), "Coverall", flip=False)
    B.orient_all(md, len(md.faces) - 40, len(md.faces), lambda p: Vector((0.0, 0.0, 0.95)))
    collar(md, sex, 1.478, 1.530, 0.074 if sex == "m" else 0.066, 0.069 if sex == "m" else 0.061, "Coverall",
           open_front=radians(26))
    # zip and chest pockets with flaps, name tape
    with md.w(TR):
        for z in (0.93, 1.00, 1.08, 1.16, 1.24, 1.32, 1.40):
            pass
        for k in range(12):
            z = 0.93 + (1.435 - 0.93) * k / 12
            z2 = 0.93 + (1.435 - 0.93) * (k + 1) / 12
            p0, _ = surface_pt(sex, 0.0, z, 0.0145)
            p1, _ = surface_pt(sex, 0.0, z2, 0.0145)
            a, b = md.v(p0 + Vector((0, -0.004, 0))), md.v(p0 + Vector((0, 0.004, 0)))
            c, d = md.v(p1 + Vector((0, 0.004, 0))), md.v(p1 + Vector((0, -0.004, 0)))
            md.f((a, b, c, d), "Metal", True)
        for sy in (1, -1):
            y = sy * (0.072 if sex == "m" else 0.080)
            z = 1.245 if sex == "m" else 1.215
            p, n = surface_pt(sex, y, z, 0.013)
            plate(md, p + Vector((0.004, 0, 0)), (0.008, 0.075, 0.085), "Coverall")
            pf, _ = surface_pt(sex, y, z + 0.034, 0.013)
            plate(md, pf + Vector((0.010, 0, 0)), (0.006, 0.079, 0.026), "Coverall")
            plate(md, pf + Vector((0.0135, 0, -0.004)), (0.002, 0.012, 0.006), "Metal")
    # sleeves with the stripe band on the upper arm, cuffs; hands
    for s in ("L", "R"):
        pts, s_el, s_wr = arm_pts(s)
        sleeve(md, s, sex, "Coverall", s_wr - 0.040, loose=1.0, cuff_mat="Coverall")
        # the department band on the sleeve (a slightly raised ring)
        st = [(0.100, 0.066, 0.068, "SuitAccent"), (0.102, 0.068, 0.070, "SuitAccent"), (0.124, 0.067, 0.069, "SuitAccent"),
              (0.126, 0.064, 0.066, "SuitAccent")]
        f = 0.92 if sex == "f" else 1.0
        st = [(a, b * f, c * f, m) for (a, b, c, m) in st]
        k0 = len(md.faces)
        B.limb(md, pts, st, seg=18, rule=arm_rule(s))
        B.orient_all(md, k0, len(md.faces), B.poly_axis(pts))
        bare_arm(md, s, sex, s_wr - 0.070)
        B.hand(md, s, sex)
        trouser_leg(md, s, sex, "Coverall", loose=1.02)
        B.shoe(md, s, "boot", upper="Leather", sole="Sole", accent="Rubber")
    # tool belt, pouches, a tape measure
    belt(md, sex, 1.035, 1.070, off=0.0205)
    with md.w(TR):
        for (y, z, w, h) in ((-0.130, 1.000, 0.070, 0.085), (-0.075, 0.995, 0.050, 0.070), (0.125, 1.005, 0.060, 0.060)):
            p, n = surface_pt(sex, y, z, 0.030)
            nrm = Vector((1.0, y * 4.0, 0.0)).normalized()
            plate(md, p + nrm * 0.012, (0.024, w, h), "Leather", nrm=nrm)
            plate(md, p + nrm * 0.026 + Vector((0, 0, h * 0.35)), (0.004, w + 0.004, h * 0.32), "Leather", nrm=nrm)
    return md


def casual_a(sex):
    md = MeshData("Outfit_casual_a")
    # tee: from the hips to the neck, crew neck; female fitted
    off_tee = 0.009 if sex == "m" else 0.0045
    zs = [0.985, 0.992, 1.010, 1.060, 1.120, 1.190, 1.260, 1.320, 1.375, 1.415, 1.445, 1.470, 1.486]
    top_mat = "Cotton" if sex == "m" else "ClothTint"

    def disp(y, z, x, t):
        # soft folds at the lower back and the hem
        return (0.0025 if sex == "m" else 0.0012) * exp(-((z - 1.03) / 0.03) ** 2) * (0.5 + 0.5 * sin(t * 7 + 1))
    k0 = len(md.faces)
    rings = B.torso(md, sex, zs, lambda z: off_tee + 0.004 * sstep(1.02, 0.985, z) - 0.004 * sstep(1.45, 1.486, z),
                    lambda k, i, p: top_mat, seg=40, disp=disp)
    B.orient_all(md, k0, len(md.faces), lambda p: Vector((0.0, 0.0, p.z)))
    # the hem turns in
    rings2 = B.torso(md, sex, [0.985, 0.998], lambda z: off_tee - 0.004, lambda k, i, p: top_mat, seg=40)
    B.orient_all(md, len(md.faces) - 40, len(md.faces), lambda p: Vector((0.0, 0.0, 2.0)))
    collar(md, sex, 1.478, 1.494, 0.068 if sex == "m" else 0.061, 0.066 if sex == "m" else 0.059, top_mat)
    for s in ("L", "R"):
        pts, s_el, s_wr = arm_pts(s)
        sleeve(md, s, sex, top_mat, 0.200 if sex == "m" else 0.170, loose=1.0 if sex == "m" else 0.96, folds=False)
        bare_arm(md, s, sex, 0.125 if sex == "m" else 0.105)
        B.hand(md, s, sex)
        trouser_leg(md, s, sex, "Denim", loose=1.0 if sex == "m" else 0.94, slim=1.0 if sex == "m" else 0.86)
        B.shoe(md, s, "sneaker", upper="Cotton", sole="Sole", accent="ClothTint" if sex == "m" else "Denim")
    # jeans top: the hips under the tee, waistband, belt loops, fly, back pockets
    k0 = len(md.faces)
    rings = B.torso(md, sex, [0.868, 0.880, 0.905, 0.950, 0.990, 1.005], 0.0115, lambda k, i, p: "Denim", seg=40)
    B.orient_all(md, k0, len(md.faces), lambda p: Vector((0.0, 0.0, p.z)))
    B.cap(md, rings[0], Vector((-0.012, 0.0, 0.862)), "Denim")
    B.orient_all(md, len(md.faces) - 40, len(md.faces), lambda p: Vector((0.0, 0.0, 0.95)))
    if sex == "m":
        belt(md, sex, 0.975, 1.000, off=0.0165)
    with md.w(TR):
        p, _ = surface_pt(sex, 0.012, 0.935, 0.0125)
        plate(md, p + Vector((0.002, 0, 0)), (0.003, 0.004, 0.075), "Denim")

    return md


OUTFITS = {"uniform_engineering": uniform_engineering, "casual_a": casual_a}
