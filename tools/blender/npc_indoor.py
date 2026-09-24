"""
Frontier Habitat 3.0 - ART-NPC: the indoor colonist (astronaut_indoor.glb): skinned mesh `Body` (jumpsuit) and four
skinned head meshes `Head_0` .. `Head_3` (the game shows one per colonist).  Same skeleton, same bind pose and the
same joint blends as the suit (npc_common), so every clip plays on both.

Jumpsuit dark navy (`Jumpsuit` #243247) with `SuitAccent` shoulder panels, collar and cuffs (the role colour),
belt, zip, chest and thigh pockets, knee pads (they give the kneeling knee the suit's contact height), work boots.
`Skin` (hands, neck, face) and `Hair` are tinted per colonist by the game.  Calm face: small dark eyes, brows, nose,
ears; nothing more.  Hair variants differ by silhouette: 0 short crop, 1 top bun, 2 chin-length bob, 3 ponytail.
"""
import os
import sys
from math import radians, sin, cos, pi, sqrt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
from npc_common import (SkinPart, Chain, tube_path, frame_from, superellipse, side_vec, sstep,  # noqa: E402
                        torso_rule, arm_rule, leg_rule, build_hand,
                        SH_JOINT, EL_JOINT, WR_JOINT, _UA, _FA, HIP_JOINT, KNEE_JOINT, ANKLE_JOINT)
from ext_common import T, S                                      # noqa: E402
from mathutils import Vector, Matrix                             # noqa: E402
import npc_suit as SU                                            # noqa: E402  (boot builder)

SEG_T = 14
SEG_ARM = 10
SEG_LEG = 10

# (z, front depth, back depth, half width, exponent, x offset, material of the band ABOVE this ring)
TORSO = [
    (0.885, 0.050, 0.064, 0.074, 2.2, -0.012, "Jumpsuit"),
    (0.905, 0.090, 0.126, 0.136, 2.4, -0.016, "Jumpsuit"),
    (0.940, 0.100, 0.130, 0.160, 2.5, -0.012, "Jumpsuit"),
    (0.978, 0.100, 0.112, 0.162, 2.5, -0.006, "Frame"),        # belt
    (1.020, 0.104, 0.116, 0.166, 2.5, -0.006, "Frame"),
    (1.030, 0.097, 0.108, 0.158, 2.5, -0.004, "Jumpsuit"),
    (1.090, 0.098, 0.098, 0.150, 2.4, 0.000, "Jumpsuit"),
    (1.170, 0.110, 0.100, 0.156, 2.6, 0.006, "Jumpsuit"),
    (1.260, 0.122, 0.104, 0.166, 2.7, 0.010, "Jumpsuit"),
    (1.340, 0.120, 0.104, 0.176, 2.7, 0.010, "Jumpsuit"),
    (1.400, 0.106, 0.100, 0.200, 2.5, 0.006, "shoulder"),       # shoulder panels start
    (1.440, 0.090, 0.088, 0.186, 2.3, 0.002, "shoulder"),
    (1.468, 0.064, 0.064, 0.112, 2.2, 0.000, "Jumpsuit"),
]


def _torso_mat(k, x, y):
    m = TORSO[k][6]
    if m == "shoulder":
        return "SuitAccent" if abs(y) > 0.075 else "Jumpsuit"
    return m


def build_torso(p):
    with p.w(torso_rule(pelvis_thigh=0.5)):
        ids, pts_all = [], []
        apex = p.v((-0.012, 0.0, 0.875))
        for (z, af, ab, b, n, x0, mat) in TORSO:
            pts = superellipse(af, ab, b, n, SEG_T)
            ids.append([p.v((x0 + x, y, z)) for x, y in pts])
            pts_all.append(pts)
        for i in range(SEG_T):
            j = (i + 1) % SEG_T
            p.f([apex, ids[0][j], ids[0][i]], "Jumpsuit", True)
        for k in range(len(ids) - 1):
            for i in range(SEG_T):
                j = (i + 1) % SEG_T
                x, y = pts_all[k][i]
                p.f([ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]], _torso_mat(k, x, y), True)
        top = p.v((0.0, 0.0, 1.472))
        for i in range(SEG_T):
            j = (i + 1) % SEG_T
            p.f([ids[-1][i], ids[-1][j], top], "Jumpsuit", True)
    with p.w("chest"):
        # zip, chest pocket with a role-colour flap, name patch, belt buckle
        p.box((0.118, 0.0, 1.235), (0.008, 0.012, 0.330), "Trim", mats={"-x": None})
        p.box((0.118, 0.085, 1.250), (0.014, 0.070, 0.080), "Jumpsuit", bevel=0.005, mats={"-x": None})
        p.box((0.126, 0.085, 1.282), (0.008, 0.072, 0.022), "SuitAccent", bevel=0.003, mats={"-x": None})
        p.box((0.120, -0.085, 1.290), (0.010, 0.070, 0.030), "SuitAccent", bevel=0.003, mats={"-x": None})
        p.box((0.1255, -0.085, 1.290), (0.002, 0.050, 0.006), "Trim", mats={"-x": None})
    with p.w("hips"):
        p.box((0.107, 0.0, 1.002), (0.012, 0.050, 0.036), "Trim", bevel=0.004, mats={"-x": None})
    with p.w(torso_rule(pelvis_thigh=0.5)):
        for sy in (1, -1):
            p.sphere((-0.060, sy * 0.072, 0.905), 0.092, "Jumpsuit", seg=8, rings=4, scale=(0.95, 0.85, 0.80))
    # shoulder panel edge: a rounded 1.2 cm roll along the lower edge of each panel, from the front over the
    # shoulder to the back (reads as a bevelled panel that follows the shoulder curve)
    with p.w(torso_rule(pelvis_thigh=0.5)):
        z, af, ab, b, n, x0 = 1.400, 0.106, 0.100, 0.200, 2.5, 0.006
        e = 2.0 / n
        for sy in (1, -1):
            pts = []
            for t in range(-80, 81, 20):
                a = radians(90 + t) if sy > 0 else radians(-90 - t)
                c, s_ = cos(a), sin(a)
                x = (abs(c) ** e) * (af if c >= 0 else ab) * (1 if c >= 0 else -1)
                y = (abs(s_) ** e) * b * (1 if s_ >= 0 else -1)
                if abs(y) < 0.075:
                    continue
                pts.append(Vector((x0 + x * 1.03, y * 1.03, z + 0.004)))
            p.tube(pts, 0.006, seg=4, mat="SuitAccent", caps=False)
    # collar (role colour), open at the front, around the neck base; neck in skin
    with p.w(Chain(["chest", "neck"], [((0, 0, 1.49), (0, 0, 1), 0.02)])):
        p.lathe([(0.076, 1.450), (0.084, 1.464), (0.080, 1.520), (0.070, 1.526), (0.066, 1.480)], "SuitAccent",
                seg=SEG_T, smooth=True, a0=25.0, a1=335.0, caps=True, cap_mat="SuitAccent")
    with p.w(Chain(["chest", "neck", "head"], [((0, 0, 1.475), (0, 0, 1), 0.02), ((0, 0, 1.585), (0, 0, 1), 0.02)])):
        p.cyl((0.006, 0.0, 1.455), (0.020, 0.0, 1.585), 0.069, 0.063, seg=10, mat="Skin", cap0=False, cap1=False)


def build_arm(p, s):
    sh, el, wr = side_vec(SH_JOINT, s), side_vec(EL_JOINT, s), side_vec(WR_JOINT, s)
    ua, fa = side_vec(_UA, s), side_vec(_FA, s)
    pts = [sh - ua * 0.05, sh, el, wr, wr + fa * 0.05]
    s0 = 0.05
    s_el = s0 + (el - sh).length
    s_wr = s_el + (wr - el).length
    st = [
        (0.012, 0.012, 0.012, "Jumpsuit"),                     # rounded deltoid cap
        (0.026, 0.040, 0.042, "Jumpsuit"),
        (0.042, 0.058, 0.060, "Jumpsuit"),
        (s0 + 0.010, 0.072, 0.074, "Jumpsuit"),                # deltoid
        (s0 + 0.070, 0.066, 0.068, "Jumpsuit"),
        (s0 + 0.170, 0.057, 0.059, "Jumpsuit"),
        (s_el - 0.030, 0.051, 0.052, "Jumpsuit"),
        (s_el + 0.010, 0.050, 0.050, "Jumpsuit"),              # elbow
        (s_el + 0.070, 0.051, 0.050, "Jumpsuit"),              # forearm
        (s_wr - 0.055, 0.043, 0.043, "SuitAccent"),            # cuff
        (s_wr - 0.052, 0.046, 0.046, "SuitAccent"),
        (s_wr - 0.022, 0.046, 0.046, "SuitAccent"),
        (s_wr - 0.018, 0.037, 0.037, "Skin"),
        (s_wr + 0.000, 0.031, 0.031, "Skin"),                  # wrist, running into the hand
        (s_wr + 0.040, 0.030, 0.026, "Skin"),
    ]
    with p.w(arm_rule(s)):
        tube_path(p, pts, st, seg=SEG_ARM, ref=(1, 0, 0))
        if s == "L":
            # sleeve patch (role colour) on the outside of the upper arm
            u, v, w = frame_from(ua, (1, 0, 0))
            side = v if v.y > 0 else -v
            c = sh + ua * 0.10 + side * 0.066
            M = Matrix((side, ua.cross(side).normalized(), ua)).transposed().to_4x4()
            with p.at(T(*c), M):
                p.box((0.0, 0.0, 0.0), (0.008, 0.050, 0.055), "SuitAccent", bevel=0.003)
            # wrist unit with a small screen, on the forearm near the wrist
            u2, v2, w2 = frame_from(fa, (1, 0, 0))
            c2 = wr - fa * 0.075 + u2 * 0.046
            M2 = Matrix((u2, v2, w2)).transposed().to_4x4()
            with p.at(T(*c2), M2):
                p.box((0.0, 0.0, 0.0), (0.020, 0.048, 0.060), "Frame", bevel=0.006)
                p.box((0.0105, 0.0, 0.0), (0.002, 0.034, 0.040), "Screen", mats={"-x": None})
    build_hand(p, s, mat="Skin", palm_mat="Skin", scale=0.86, cuff=False, finger_seg=6)


def build_leg(p, s):
    hip, kn, an = side_vec(HIP_JOINT, s), side_vec(KNEE_JOINT, s), side_vec(ANKLE_JOINT, s)
    th = (kn - hip).normalized()
    shd = (an - kn).normalized()
    pts = [hip - th * 0.06, hip, kn, an]
    s0 = 0.06
    s_kn = s0 + (kn - hip).length
    s_an = s_kn + (an - kn).length
    st = [
        (0.000, 0.080, 0.082, "Jumpsuit"),
        (s0 + 0.020, 0.110, 0.108, "Jumpsuit", -0.004),
        (s0 + 0.160, 0.097, 0.095, "Jumpsuit", 0.000),
        (s0 + 0.300, 0.072, 0.074, "Jumpsuit"),
        (s_kn - 0.010, 0.065, 0.066, "Jumpsuit"),
        (s_kn + 0.080, 0.063, 0.063, "Jumpsuit", -0.008),      # calf
        (s_kn + 0.220, 0.054, 0.054, "Jumpsuit", -0.004),
        (s_an - 0.090, 0.060, 0.060, "Jumpsuit"),               # trouser hem over the boot
        (s_an - 0.080, 0.054, 0.054, "Jumpsuit"),
    ]
    with p.w(leg_rule(s)):
        tube_path(p, pts, st, seg=SEG_LEG, ref=(1, 0, 0), cap1=True, cap_mat="Jumpsuit")
        sy = 1.0 if s == "L" else -1.0
    # knee pad: rubber shell over the knee cap and upper shin, rigid on the shin (kneeling contact = the suit's)
    u, v, w = frame_from(shd, (1, 0, 0))
    c = kn + u * 0.050 + shd * 0.045
    M = Matrix((u, v, w)).transposed().to_4x4()
    with p.w("shin." + s):
        with p.at(T(*c), M):
            p.box((0.0, 0.0, 0.0), (0.038, 0.096, 0.130), "Rubber", bevel=0.015, mats={"-x": None})
            p.box((0.0, 0.0, 0.060), (0.020, 0.098, 0.014), "Frame", mats={"-x": None})
    with p.w(leg_rule(s)):
        # seam lines down the outer side of the thigh and the shin
        for a0, a1, off in ((hip + th * 0.06, kn - th * 0.05, 0.098), (kn + shd * 0.05, an - shd * 0.10, 0.062)):
            d = (a1 - a0).normalized()
            o = Vector((0.0, sy, 0.0))
            o = (o - d * o.dot(d)).normalized()
            p.beam(tuple(a0 + o * off), tuple(a1 + o * (off - 0.004)), 0.004, 0.003, "Frame", up=tuple(o), caps=False)
        # thigh cargo pocket
        pc = hip + th * 0.25 + Vector((0.008, sy * 0.090, 0.0))
        p.box(tuple(pc), (0.09, 0.022, 0.11), "Jumpsuit", bevel=0.008, mats={"-y" if sy > 0 else "+y": None})
        p.box((pc.x, pc.y + sy * 0.011, pc.z + 0.045), (0.09, 0.004, 0.018), "SuitAccent", mats={"-y" if sy > 0 else "+y": None})
        SU.build_boot(p, s, shell="Frame", toe="Rubber", sole="Rubber", cuff=False, scale_w=0.84, top_scale=0.78)
        with p.at(T(an.x + 0.004, an.y, 0.0)):
            p.lathe([(0.064, 0.090), (0.064, 0.170), (0.058, 0.176), (0.052, 0.168)], "Frame", seg=10, smooth=True)


# --------------------------------------------------------------------------------------
# heads
# --------------------------------------------------------------------------------------
HCI = Vector((0.026, 0.0, 1.652))     # head centre (1.2 cm lower than v1: shorter visible neck)
RX_, RY_, RZ_ = 0.104, 0.089, 0.118    # skull radii (x forward, y side 7 % wider, z up)


def head_pt(lat, az, r=1.0, dx=0.0):
    a, l = radians(az), radians(lat)
    return HCI + Vector((RX_ * r * cos(l) * cos(a) + dx, RY_ * r * cos(l) * sin(a), RZ_ * r * sin(l)))


def head_rule():
    return Chain(["neck", "head"], [((0, 0, 1.580), (0, 0, 1), 0.025)])


def curve_beam(p, pts, w, h, mat):
    for a, b in zip(pts[:-1], pts[1:]):
        p.beam(tuple(a), tuple(b), w, h, mat, caps=False)


def build_face(p):
    """Skull with a round jaw, ears, a small rounded nose, calm eyes with lids, soft curved brows, a mouth line."""
    seg = 14
    prof = [-90.0 + 180.0 * k / 10 for k in range(11)]
    ids = []
    for lat in prof:
        if abs(lat) >= 89.9:
            ids.append([p.v(head_pt(lat, 0))])
            continue
        ring = []
        for i in range(seg):
            az = 360.0 * i / seg
            q = head_pt(lat, az)
            front = max(0.0, cos(radians(az)))
            if lat < -20:                         # round jaw, chin slightly forward
                q.y *= 0.90 + 0.10 * (1.0 + sin(radians(lat)))
                q.x += 0.008 * front
            if -40 < lat < 10:                    # face plane slightly flatter
                q.x -= 0.005 * front ** 3
            ring.append(p.v(q))
        ids.append(ring)
    for k in range(len(ids) - 1):
        A, B = ids[k], ids[k + 1]
        for i in range(seg):
            j = (i + 1) % seg
            if len(A) == 1:
                p.f([A[0], B[j], B[i]], "Skin", True)
            elif len(B) == 1:
                p.f([A[i], A[j], B[0]], "Skin", True)
            else:
                p.f([A[i], A[j], B[j], B[i]], "Skin", True)
    # nose: small and round (1.2 cm out from the face, 40 % less than v1)
    c = head_pt(-13, 0, 1.0) + Vector((0.002, 0.0, -0.005))
    p.sphere(tuple(c), 0.012, "Skin", seg=6, rings=3, scale=(0.85, 0.95, 1.35))
    cb = head_pt(-3, 0, 1.0) + Vector((-0.002, 0.0, 0.0))                   # rounded bridge
    p.sphere(tuple(cb), 0.0085, "Skin", seg=6, rings=3, scale=(0.75, 1.05, 2.1))
    # ears
    for sy in (-1, 1):
        c = head_pt(-4, sy * 92, 1.0)
        c.x -= 0.012
        p.sphere(tuple(c), 0.024, "Skin", seg=5, rings=3, scale=(0.55, 0.40, 1.0))
    # eyes one step larger, with a lid line; brows lower, thin and curved (calm)
    for sy in (-1, 1):
        e = head_pt(3, sy * 24, 1.0)
        p.sphere(tuple(e + Vector((-0.005, 0, 0))), 0.011, "Frame", seg=6, rings=3, scale=(0.55, 1.0, 0.75))
        lid = [head_pt(7.5, sy * a, 1.012) for a in (15, 24, 33)]
        curve_beam(p, lid, 0.0035, 0.0022, "Frame")
        brow = [head_pt(10.5, sy * 11, 1.022), head_pt(13.0, sy * 22, 1.025), head_pt(11.0, sy * 34, 1.018)]
        curve_beam(p, brow, 0.0055, 0.0030, "Hair")
    # mouth: a 3 cm soft line with a slight upturn at the corners
    mouth = [head_pt(-35.5, 8.5, 1.004), head_pt(-37.0, 0.0, 1.006), head_pt(-35.5, -8.5, 1.004)]
    curve_beam(p, mouth, 0.0040, 0.0020, "Frame")


def hair_cap(p, top_r=1.10, low_back=-20.0, low_side=5.0, front=28.0, seg=12, rings=5, mat="Hair", flare=0.0,
             edge=0.0):
    """Hair shell over the skull: covers the top and back; the hairline in front is at latitude `front`,
    at the sides `low_side`, at the back `low_back`.  flare adds volume towards the lower edge (bob)."""
    rows = []
    for k in range(rings + 1):
        t = k / rings
        row = []
        for i in range(seg + 1):
            az = -180.0 + 360.0 * i / seg
            f = cos(radians(az))                      # 1 front, -1 back
            if f >= 0:
                low = low_side + (front - low_side) * f
            else:
                low = low_side + (low_back - low_side) * (-f)
            lat = low + (90.0 - low) * t
            r = top_r + flare * (1.0 - t) * (1.0 - max(0.0, f))
            if k == 1:
                r += edge                                  # a raised roll just above the hairline
            row.append(p.v(head_pt(lat, az, r)))
        rows.append(row)
    for k in range(rings):
        for i in range(seg):
            p.f([rows[k][i], rows[k][i + 1], rows[k + 1][i + 1], rows[k + 1][i]], mat, True)
    for i in range(seg):                                 # rim skirt tucked into the skull (edge thickness)
        a, b = rows[0][i], rows[0][i + 1]
        qa, qb = p.verts[a].copy(), p.verts[b].copy()
        ia = p.v(HCI + (qa - HCI) * 0.93)
        ib = p.v(HCI + (qb - HCI) * 0.93)
        p.f([a, ia, ib, b], mat, True)


def build_head(k):
    """Four silhouettes that differ at 55 px: 0 tight crop, 1 high bun, 2 full jaw-length bob, 3 long ponytail."""
    p = SkinPart("Head_%d" % k)
    with p.w(head_rule()):
        build_face(p)
        if k == 0:                                   # tight crop
            hair_cap(p, top_r=1.055, low_back=-16.0, low_side=10.0, front=40.0, rings=4, edge=0.045)
        elif k == 1:                                 # high bun, 35 % bigger
            hair_cap(p, top_r=1.06, low_back=-20.0, low_side=8.0, front=36.0)
            c = head_pt(74, 180, 1.0) + Vector((0.012, 0, 0.055))
            p.sphere(tuple(c), 0.062, "Hair", seg=8, rings=4, scale=(1.0, 1.0, 0.85))
            p.cyl(tuple(c - Vector((0, 0, 0.056))), tuple(c - Vector((0, 0, 0.036))), 0.036, seg=8, mat="SuitAccent",
                  cap0=False, cap1=False)
        elif k == 2:                                 # jaw-length bob with 2 cm more volume: a wide silhouette
            hair_cap(p, top_r=1.17, low_back=-64.0, low_side=-60.0, front=30.0, rings=6, flare=0.14)
        else:                                        # ponytail to the collar, 3 cm further out
            hair_cap(p, top_r=1.06, low_back=-24.0, low_side=6.0, front=36.0)
            a = head_pt(12, 180, 1.05)
            pts = [a, a + Vector((-0.070, 0, -0.030)), a + Vector((-0.125, 0, -0.120)), a + Vector((-0.120, 0, -0.205))]
            p.cyl(tuple(a + Vector((0.01, 0, 0.005))), tuple(a + Vector((-0.040, 0, -0.016))), 0.024, seg=6,
                  mat="Hair", cap0=False, cap1=False)
            p.cyl(tuple(a + Vector((-0.040, 0, -0.016))), tuple(pts[1]), 0.030, seg=8, mat="Trim", cap0=False,
                  cap1=False)
            p.tube(pts[1:], 0.038, seg=6, mat="Hair", caps=True, fillet=0.03)
    return p


# --------------------------------------------------------------------------------------
def build_indoor_parts():
    p = SkinPart("Body")
    counts = {}

    def run(label, fn, *a):
        n0 = sum(len(f) - 2 for f in p.faces)
        fn(p, *a)
        counts[label] = counts.get(label, 0) + sum(len(f) - 2 for f in p.faces) - n0
    run("torso", build_torso)
    for s in ("L", "R"):
        run("arm+hand", build_arm, s)
        run("leg+boot", build_leg, s)
    heads = [build_head(k) for k in range(4)]
    for h in heads:
        counts[h.name] = sum(len(f) - 2 for f in h.faces)
    print("    triangles by part:", counts)
    return [p] + heads
