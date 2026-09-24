"""
Frontier Habitat 3.0 - ART-NPC: the EVA suit body (astronaut_suit.glb), one skinned mesh `Body`.
Built in the bind pose of npc_common.SKELETON (A-pose, faces +X, left = +Y).  Every vertex carries a weight rule.

Round 1 critic fixes (docs/critic/round_1.md, npc_suit): flush helmet lamp housings with a forward lens; green and
amber pack status lights; chest box with a lit Screen, two accent buttons and a 2.5 cm hose from the pack; hard
shells (HUT, helmet) in SuitHard (rough 0.45) with a HUT seam; three Trim ribs at knees and elbows; smoother legs
(14 sides); pelvis 2-3 cm smaller; 8-sided gloved fingers in two pairs with rounded tips; chamfered pack parts.
"""
import os
import sys
from math import radians, sin, cos, pi, sqrt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
from npc_common import (SkinPart, Chain, sstep, tube_path, frame_from, superellipse, side_vec,  # noqa: E402
                        torso_rule, arm_rule, leg_rule, ribs, build_hand,
                        SH_JOINT, EL_JOINT, WR_JOINT, _UA, _FA,
                        HIP_JOINT, KNEE_JOINT, ANKLE_JOINT)
from ext_common import T, S                                      # noqa: E402
from mathutils import Vector, Matrix                             # noqa: E402

SEG_TORSO = 18
SEG_ARM = 12
SEG_LEG = 14


# --------------------------------------------------------------------------------------
# torso: pelvis, waist bearing and bellows, hard upper torso (HUT)
# --------------------------------------------------------------------------------------
# (z, front depth, back depth, half width, exponent, x offset, material of the band ABOVE this ring)
TORSO_RINGS = [
    (0.840, 0.048, 0.058, 0.066, 2.2, -0.005, "SuitMain"),
    (0.866, 0.090, 0.110, 0.132, 2.4, -0.005, "SuitMain"),
    (0.905, 0.108, 0.130, 0.164, 2.6, -0.005, "SuitMain"),
    (0.945, 0.114, 0.134, 0.172, 2.7, -0.005, "SuitMain"),
    (0.975, 0.122, 0.134, 0.178, 2.6, -0.005, "Trim"),        # waist bearing
    (0.988, 0.136, 0.146, 0.192, 2.6, -0.005, "Trim"),
    (1.012, 0.136, 0.146, 0.192, 2.6, -0.005, "Trim"),
    (1.022, 0.124, 0.134, 0.176, 2.6, -0.005, "SuitMain"),    # waist bellows
    (1.050, 0.134, 0.144, 0.187, 2.6, -0.005, "SuitMain"),
    (1.084, 0.124, 0.134, 0.176, 2.6, -0.005, "SuitMain"),
    (1.116, 0.133, 0.143, 0.185, 2.6, -0.005, "SuitMain"),
    (1.140, 0.126, 0.136, 0.178, 2.6, -0.005, "Frame"),       # HUT lower edge
    (1.150, 0.150, 0.150, 0.194, 2.8, 0.000, "Frame"),
    (1.162, 0.150, 0.150, 0.194, 2.8, 0.000, "SuitHard"),
    (1.220, 0.160, 0.150, 0.196, 2.9, 0.005, "SuitHard"),
    (1.300, 0.168, 0.152, 0.200, 3.0, 0.008, "SuitHard"),
    (1.334, 0.167, 0.152, 0.206, 3.0, 0.008, "Frame"),        # HUT seam line
    (1.341, 0.167, 0.152, 0.208, 3.0, 0.008, "SuitHard"),
    (1.375, 0.166, 0.152, 0.220, 3.0, 0.008, "SuitHard"),
    (1.430, 0.152, 0.146, 0.222, 2.8, 0.004, "SuitHard"),
    (1.475, 0.128, 0.130, 0.188, 2.5, 0.000, "SuitHard"),
    (1.505, 0.100, 0.104, 0.140, 2.2, 0.000, "SuitHard"),
    (1.520, 0.080, 0.084, 0.098, 2.0, 0.000, "SuitHard"),
]


def build_torso(p):
    with p.w(torso_rule()):
        ids = []
        apex = p.v((-0.005, 0.0, 0.830))
        for (z, af, ab, b, n, x0, mat) in TORSO_RINGS:
            pts = superellipse(af, ab, b, n, SEG_TORSO)
            ids.append([p.v((x0 + x, y, z)) for x, y in pts])
        seg = SEG_TORSO
        for i in range(seg):                                       # crotch cap
            j = (i + 1) % seg
            p.f([apex, ids[0][j], ids[0][i]], "SuitMain", True)
        for k in range(len(ids) - 1):
            mat = TORSO_RINGS[k][6]
            for i in range(seg):
                j = (i + 1) % seg
                p.f([ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]], mat, True)
        top = p.v((0.0, 0.0, 1.522))                               # under the neck ring (hidden)
        for i in range(0, seg, 2):
            j = (i + 2) % seg
            p.f([ids[-1][i], ids[-1][i + 1], ids[-1][j], top], "Frame", True)
    with p.w("chest"):
        # chest control box: lit screen with a UI pattern, two role-colour buttons, one knob
        p.box((0.185, 0.0, 1.245), (0.075, 0.215, 0.125), "Pack", bevel=0.016, mats={"-x": None})
        p.box((0.2215, 0.0, 1.265), (0.006, 0.160, 0.066), "Frame", mats={"-x": None})          # bezel
        p.box((0.2250, 0.0, 1.265), (0.004, 0.140, 0.052), "Screen", mats={"-x": None})
        for (y0, y1, z0, z1) in ((-0.058, 0.058, 1.279, 1.286), (-0.058, 0.020, 1.266, 1.271),
                                 (-0.058, -0.010, 1.255, 1.260), (0.030, 0.058, 1.249, 1.269)):
            p.box((0.2275, (y0 + y1) / 2, (z0 + z1) / 2), (0.002, y1 - y0, z1 - z0), "LightStrip", mats={"-x": None})
        for y in (0.045, 0.075):
            p.cyl((0.220, y, 1.212), (0.234, y, 1.212), 0.011, seg=8, mat="SuitAccent", cap0=False)
        p.cyl((0.220, -0.060, 1.212), (0.236, -0.060, 1.212), 0.012, seg=8, mat="Trim", cap0=False)
        # purge valve on the left chest
        p.cyl((0.150, 0.130, 1.37), (0.182, 0.138, 1.37), 0.020, seg=10, mat="Trim", cap0=False)
        p.cyl((0.182, 0.138, 1.37), (0.190, 0.140, 1.37), 0.014, seg=10, mat="Frame", cap0=False)
        p.box((0.160, -0.128, 1.30), (0.014, 0.070, 0.028), "SuitAccent", bevel=0.004, mats={"-x": None})   # name tag
        # umbilical hose (2.5 cm): pack lower right, round the right waist, into the chest box
        hose = [(-0.215, -0.175, 1.035), (-0.10, -0.232, 1.06), (0.05, -0.222, 1.12), (0.16, -0.105, 1.192)]
        p.tube(hose, 0.0125, seg=6, mat="Frame", fillet=0.06, caps=False)
        for a, b in ((hose[0], (-0.20, -0.178, 1.04)), (hose[-1], (0.150, -0.112, 1.187))):
            d = (Vector(b) - Vector(a)).normalized()
            p.cyl(tuple(Vector(a) - d * 0.012), tuple(Vector(a) + d * 0.022), 0.018, seg=8, mat="Trim", cap0=False,
                  cap1=False)


# --------------------------------------------------------------------------------------
# life-support backpack (PLSS)
# --------------------------------------------------------------------------------------
def build_pack(p):
    with p.w("chest"):
        p.box((-0.272, 0.0, 1.265), (0.235, 0.420, 0.500), "Pack", bevel=0.040, mats={"+x": None})   # main body
        # rear: two white thermal covers with a recessed seam between them, a service panel with a hose port
        p.box((-0.3935, 0.0, 1.345), (0.022, 0.340, 0.235), "SuitMain", bevel=0.010, mats={"+x": None})
        p.box((-0.3935, 0.0, 1.117), (0.022, 0.340, 0.205), "SuitMain", bevel=0.010, mats={"+x": None})
        p.box((-0.3995, 0.120, 1.405), (0.010, 0.050, 0.070), "SuitAccent", bevel=0.004, mats={"+x": None})  # role patch
        p.box((-0.4050, -0.070, 1.100), (0.010, 0.120, 0.080), "Frame", bevel=0.004, mats={"+x": None})
        p.cyl((-0.403, 0.075, 1.100), (-0.422, 0.075, 1.100), 0.026, seg=10, mat="Trim", cap0=False)
        p.cyl((-0.422, 0.075, 1.100), (-0.428, 0.075, 1.100), 0.017, seg=10, mat="Frame", cap0=False)
        # lower module (battery), 3 cm clear of a seat under a seated colonist, and its latch
        p.box((-0.27, 0.0, 1.000), (0.19, 0.34, 0.060), "Frame", bevel=0.018)
        p.box((-0.3665, 0.0, 1.000), (0.010, 0.10, 0.028), "Trim", bevel=0.004, mats={"+x": None})
        # side vents: 3 slats per side
        for sy in (-1, 1):
            for k in range(3):
                z = 1.215 + 0.045 * k
                p.box((-0.30, sy * 0.211, z), (0.14, 0.012, 0.018), "Frame", mats={"-y" if sy > 0 else "+y": None})
        # top: grab rail, green and amber status lights, short antenna
        for a, b in (((-0.20, -0.13, 1.505), (-0.20, -0.13, 1.545)), ((-0.20, 0.13, 1.505), (-0.20, 0.13, 1.545)),
                     ((-0.20, -0.14, 1.545), (-0.20, 0.14, 1.545))):
            p.beam(a, b, 0.018, 0.018, "Trim")
        for sy, lm in ((1, "LightGreen"), (-1, "LightAmber")):
            p.cyl((-0.355, sy * 0.150, 1.510), (-0.355, sy * 0.150, 1.524), 0.021, seg=8, mat="Frame", cap0=False)
            p.cyl((-0.355, sy * 0.150, 1.524), (-0.355, sy * 0.150, 1.538), 0.015, seg=8, mat=lm, cap0=False)
        p.cyl((-0.33, -0.17, 1.515), (-0.33, -0.17, 1.70), 0.006, seg=5, mat="Frame", cap0=False)
        p.cyl((-0.33, -0.17, 1.70), (-0.33, -0.17, 1.716), 0.011, seg=6, mat="SuitAccent")
        # pack mounts where the pack meets the HUT
        for sy in (-1, 1):
            p.box((-0.16, sy * 0.15, 1.44), (0.05, 0.05, 0.06), "Frame", bevel=0.01)


# --------------------------------------------------------------------------------------
# helmet, visor, lamps, neck ring
# --------------------------------------------------------------------------------------
HC = Vector((0.035, 0.0, 1.668))     # helmet centre
HR = 0.168                           # helmet radius (horizontal); vertical 0.185


def helmet_pt(r, az, lat, sy=0.93, sz=1.10):
    a, l = radians(az), radians(lat)
    return HC + Vector((r * cos(l) * cos(a), r * cos(l) * sin(a) * sy, r * sin(l) * sz))


def build_helmet(p):
    with p.w("chest"):                                  # neck ring (on the HUT)
        p.lathe([(0.108, 1.500), (0.128, 1.505), (0.132, 1.528), (0.124, 1.545), (0.112, 1.548), (0.104, 1.530)],
                "Trim", seg=16, smooth=True)
    with p.w("head"):
        prof = []
        for k in range(11):
            lat = -52.0 + (142.0 * k / 10.0)
            prof.append((0.0, HR * 1.10) if k == 10 else (HR * cos(radians(lat)), HR * sin(radians(lat)) * 1.10))
        prof = [(prof[0][0] * 0.93, prof[0][1] + 0.004)] + prof
        with p.at(T(*HC), S(1.0, 0.93, 1.0)):
            p.lathe(prof, "SuitHard", seg=18, smooth=True)
        # visor: spherical patch in front, gold, with a dark frame rim
        na, nl = 10, 6
        az0, az1, l0, l1 = -74.0, 74.0, -44.0, 36.0
        rr = HR + 0.014
        grid = [[p.v(helmet_pt(rr, az0 + (az1 - az0) * i / na, l0 + (l1 - l0) * j / nl)) for j in range(nl + 1)]
                for i in range(na + 1)]
        for i in range(na):
            for j in range(nl):
                p.f([grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]], "Visor", True)
        border = [(az0 + (az1 - az0) * i / na, l0) for i in range(na + 1)] + \
                 [(az1, l0 + (l1 - l0) * j / nl) for j in range(1, nl + 1)] + \
                 [(az1 - (az1 - az0) * i / na, l1) for i in range(1, na + 1)] + \
                 [(az0, l1 - (l1 - l0) * j / nl) for j in range(1, nl)]
        cz = (l0 + l1) / 2
        rings = [[], [], []]
        for (a, l) in border:
            da, dl = a / 74.0, (l - cz) / 40.0
            ln = max(1e-6, sqrt(da * da + dl * dl))
            ea, el = da / ln, dl / ln
            rings[0].append(p.v(helmet_pt(rr, a, l)))
            rings[1].append(p.v(helmet_pt(rr + 0.006, a + ea * 3.0, l + el * 3.0)))
            rings[2].append(p.v(helmet_pt(HR - 0.002, a + ea * 7.5, l + el * 7.5)))
        nb = len(border)
        for r in range(2):
            for i in range(nb):
                j = (i + 1) % nb
                p.f([rings[r][i], rings[r + 1][i], rings[r + 1][j], rings[r][j]], "Frame", True)
        # role stripe over the top of the helmet (front brow to the back), a raised band
        n = 12
        rows = []
        for k in range(n + 1):
            lat = 44.0 + (180.0 - 44.0 - 10.0) * k / n
            az = 0.0 if lat <= 90.0 else 180.0
            ll = lat if lat <= 90.0 else 180.0 - lat
            row = []
            for w in (-1, 1):
                q = helmet_pt(HR + 0.006, az, ll)
                q.y += w * 0.024
                row.append(p.v(q))
            rows.append(row)
        for k in range(n):
            p.f([rows[k][0], rows[k][1], rows[k + 1][1], rows[k + 1][0]], "SuitAccent", True)
        for k in range(n):
            for w in (0, 1):
                a0, a1 = rows[k][w], rows[k + 1][w]
                q0, q1 = p.verts[a0].copy(), p.verts[a1].copy()
                b0 = p.v(q0 + (q0 - HC).normalized() * -0.006)
                b1 = p.v(q1 + (q1 - HC).normalized() * -0.006)
                p.f([a0, a1, b1, b0] if w == 0 else [a0, b0, b1, a1], "SuitAccent", True)
        # helmet lamps: flush 4 x 3 x 3 cm housings on the helmet sides behind the visor rim, lens facing forward
        for sy in (-1, 1):
            c = helmet_pt(HR, sy * 90.0, 16.0)
            c.y += sy * 0.006
            p.box((c.x, c.y, c.z), (0.040, 0.030, 0.030), "Pack", bevel=0.006)
            p.cyl((c.x + 0.020, c.y, c.z), (c.x + 0.0235, c.y, c.z), 0.0105, seg=10, mat="Light", cap0=False)


# --------------------------------------------------------------------------------------
# arms and gloves
# --------------------------------------------------------------------------------------
def build_arm(p, s):
    sh, el, wr = side_vec(SH_JOINT, s), side_vec(EL_JOINT, s), side_vec(WR_JOINT, s)
    ua, fa = side_vec(_UA, s), side_vec(_FA, s)
    pts = [sh - ua * 0.06, sh, el, wr]
    s0 = 0.06
    s_el = s0 + (el - sh).length
    s_wr = s_el + (wr - el).length
    st = [
        (0.000, 0.070, 0.072, "SuitMain"),
        (s0 - 0.01, 0.086, 0.088, "Trim"),                    # shoulder bearing
        (s0 + 0.020, 0.099, 0.101, "Trim"),
        (s0 + 0.042, 0.087, 0.089, "SuitMain"),
        (s0 + 0.080, 0.086, 0.088, "SuitAccent"),             # role stripe
        (s0 + 0.134, 0.088, 0.090, "SuitMain"),
        (s_el - 0.070, 0.080, 0.081, "SuitMain"),
    ]
    st += ribs(s_el - 0.004, 0.079, count=3, pitch=0.026, height=0.009)        # elbow bellows: 3 Trim ribs
    st += [
        (s_el + 0.075, 0.075, 0.076, "SuitMain"),
        (s_el + 0.140, 0.071, 0.071, "SuitMain"),
        (s_wr - 0.060, 0.066, 0.066, "Trim"),                 # wrist disconnect ring
        (s_wr - 0.020, 0.074, 0.074, "Trim"),
        (s_wr - 0.012, 0.064, 0.064, "Trim"),
        (s_wr + 0.000, 0.060, 0.060, "Trim"),
    ]
    with p.w(arm_rule(s)):
        tube_path(p, pts, st, seg=SEG_ARM, ref=(1, 0, 0))
        if s == "L":
            # wrist computer on the left forearm (top = outward and forward): lit screen
            u, v, w = frame_from(fa, (1, 0, 0))
            c = el + fa * 0.15 + u * 0.068
            M = Matrix((u, v, w)).transposed().to_4x4()
            with p.at(T(*c), M):
                p.box((0.0, 0.0, 0.0), (0.030, 0.075, 0.095), "Pack", bevel=0.010)
                p.box((0.0155, 0.0, 0.005), (0.004, 0.056, 0.062), "Frame", mats={"-x": None})
                p.box((0.0175, 0.0, 0.005), (0.003, 0.046, 0.050), "Screen", mats={"-x": None})
                p.box((0.0190, 0.0, 0.020), (0.002, 0.036, 0.007), "LightStrip", mats={"-x": None})
    build_hand(p, s, mat="Pack", palm_mat="Rubber")


# --------------------------------------------------------------------------------------
# legs and boots
# --------------------------------------------------------------------------------------
def build_leg(p, s):
    hip, kn, an = side_vec(HIP_JOINT, s), side_vec(KNEE_JOINT, s), side_vec(ANKLE_JOINT, s)
    th = (kn - hip).normalized()
    pts = [hip - th * 0.07, hip, kn, an]
    s0 = 0.07
    s_kn = s0 + (kn - hip).length
    s_an = s_kn + (an - kn).length
    st = [
        (0.000, 0.080, 0.082, "SuitMain"),
        (s0 - 0.01, 0.096, 0.098, "SuitMain"),
        (s0 + 0.040, 0.102, 0.104, "Trim"),                   # thigh bearing
        (s0 + 0.052, 0.112, 0.114, "Trim"),
        (s0 + 0.072, 0.112, 0.114, "Trim"),
        (s0 + 0.084, 0.103, 0.105, "SuitMain"),
        (s0 + 0.180, 0.099, 0.101, "SuitMain", -0.004),
        (s_kn - 0.075, 0.087, 0.088, "SuitMain"),
    ]
    st += ribs(s_kn - 0.004, 0.086, count=3, pitch=0.028, height=0.010, du=0.003)   # knee bellows: 3 Trim ribs
    st += [
        (s_kn + 0.075, 0.084, 0.085, "SuitMain", -0.004),
        (s_kn + 0.170, 0.083, 0.082, "SuitMain", -0.010),      # calf
        (s_an - 0.070, 0.073, 0.073, "SuitMain"),
    ]
    with p.w(leg_rule(s)):
        tube_path(p, pts, st, seg=SEG_LEG, ref=(1, 0, 0), cap1=True, cap_mat="SuitMain")
        sy = 1.0 if s == "L" else -1.0
        c = hip + th * 0.25 + Vector((0.01, sy * 0.096, 0.0))          # thigh pocket
        p.box(tuple(c), (0.10, 0.035, 0.12), "Pack", bevel=0.012, mats={"-y" if sy > 0 else "+y": None})
        build_boot(p, s)


def boot_outline():
    """Sole outline (x, y) for the left boot, counter-clockwise from the heel."""
    return [(-0.105, 0.000), (-0.098, -0.034), (-0.075, -0.052), (-0.030, -0.056), (0.030, -0.058), (0.090, -0.064),
            (0.120, -0.064), (0.150, -0.060), (0.190, -0.046), (0.212, -0.020), (0.215, 0.000), (0.212, 0.020),
            (0.190, 0.048), (0.150, 0.064), (0.120, 0.068), (0.090, 0.068), (0.030, 0.060), (-0.030, 0.058),
            (-0.075, 0.054), (-0.098, 0.036)]


def build_boot(p, s, shell="Pack", toe="Frame", sole="Rubber", cuff=True, scale_w=1.0, top_scale=1.0):
    sy = 1.0 if s == "L" else -1.0
    y0 = ANKLE_JOINT.y * sy
    outline = [(x, y0 + y * sy * scale_w) for x, y in boot_outline()]
    if sy < 0:
        outline = list(reversed(outline))
    p.prism(outline, 0.0, 0.046, sole, cap_mat=sole)                       # thick rubber sole
    sec = [(-0.100, 0.050, 0.175), (-0.070, 0.058, 0.205), (-0.020, 0.062, 0.215), (0.030, 0.063, 0.170),
           (0.080, 0.066, 0.130), (0.120, 0.066, 0.108), (0.160, 0.060, 0.092), (0.190, 0.048, 0.078),
           (0.207, 0.030, 0.064)]
    n = 8
    rings = []
    for (x, hw, top) in sec:
        top = 0.046 + (top - 0.046) * top_scale
        rings.append([(x, y0 + cos(pi * i / n) * hw * scale_w * sy, 0.046 + sin(pi * i / n) * (top - 0.046))
                      for i in range(n + 1)])
    ids = [[p.v(q) for q in r] for r in rings]
    for k in range(len(ids) - 1):
        mat = shell if sec[k][0] < 0.115 else toe
        for i in range(n):
            f = [ids[k][i], ids[k][i + 1], ids[k + 1][i + 1], ids[k + 1][i]]
            p.f(f if sy > 0 else list(reversed(f)), mat, True)
    capf, capt = list(reversed(ids[0])), list(ids[-1])
    if sy < 0:
        capf.reverse()
        capt.reverse()
    p.f(capf, shell, False)
    p.f(capt, toe, False)
    an = side_vec(ANKLE_JOINT, s)
    if cuff:
        with p.at(T(an.x + 0.005, an.y, 0.0)):
            p.lathe([(0.086, 0.110), (0.086, 0.215), (0.092, 0.220), (0.092, 0.244), (0.078, 0.250), (0.072, 0.236)],
                    lambda k, i: "Trim" if k >= 2 else shell, seg=12, smooth=True)
    p.box((0.198, y0, 0.052), (0.028, 0.080 * scale_w, 0.030), sole, bevel=0.010)             # toe bumper
    p.box((-0.104, y0, 0.110 * top_scale), (0.016, 0.070 * scale_w, 0.090 * top_scale), "Frame", bevel=0.006)


# --------------------------------------------------------------------------------------
def build_suit_body():
    p = SkinPart("Body")
    counts = {}

    def run(label, fn, *a):
        n0 = sum(len(f) - 2 for f in p.faces)
        fn(p, *a)
        counts[label] = counts.get(label, 0) + sum(len(f) - 2 for f in p.faces) - n0
    run("torso", build_torso)
    run("pack", build_pack)
    run("helmet", build_helmet)
    for s in ("L", "R"):
        run("arm+glove", build_arm, s)
        run("leg+boot", build_leg, s)
    print("    triangles by part:", counts)
    return p
