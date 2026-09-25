"""
Frontier Habitat 3.0 - ART-NPC animation clips (V3_DESIGN.md section 3.3), shared by both variants (RENDER bakes the
suit's clips once and reuses them for the indoor model, so the clip data must be identical in both files).

Every clip is a function frame -> Pose (npc_common.Pose).  Loops return exactly the same pose on the first and the
last frame.  Enter / exit clips start and end exactly on the rest pose of their pose state:
  stand = idle frame 0 (STAND), sit = sit_idle frame 0 (SIT), lie = sleep frame 0 (LIE), kneel = repair_kneel frame 0
  (KNEEL).  collapse starts on STAND and ends on dead frame 0 (DEAD, on the ground); cheer starts and ends on STAND.
Pose angles are degrees about world-aligned axes in the parent's frame (X forward, Y left, Z up).  For an upward
bone ry > 0 leans forward; for a hanging arm ry < 0 swings it forward; rx < 0 brings the left arm to the body.

Which body a contact pose is tuned to: SIT both (within 1 cm), LIE the indoor body (beds are indoors),
KNEEL and DEAD the suit (the indoor jumpsuit has knee pads of the same size).
"""
import os
import sys
from math import sin, cos, pi, radians, degrees, sqrt, ceil

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                                  # noqa: E402
from npc_common import Pose, sym, set_foot, ankle_from_pivot, Timeline, qeuler, sstep   # noqa: E402
from mathutils import Vector, Quaternion                                # noqa: E402

FPS = N.FPS
TAU = 2 * pi
ANK = N.ANKLE_JOINT
HEEL = N.HEEL_PIVOT
BALL = N.BALL_JOINT

# furniture contract (section 3.3 / 6); the same numbers go into astronaut_anims.json
FURNITURE = dict(seat_z=0.46, seat_back=0.30, bed_z=0.55, bed_back=0.55, console_z=1.0, console_ahead=0.45,
                 bench_z=0.9, panel_ahead=0.45, panel_z=0.4)
# crate carried at prop.R: the bone origin is the crate's bottom centre, its axes are the character axes
CARRY = dict(bone="prop.R", origin="crate bottom centre", size=0.40, bottom_centre=(0.39, 0.0, 0.78))
# (bottom_centre is given for the chest at rest; the crate then rides the right hand)


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def add(P, **kw):
    """P[k] += v; keys use '__' for '.' (hips__z=...)."""
    Q = Pose(P)
    for k, v in kw.items():
        k = k.replace("__", ".")
        Q[k] = Q.g(k) + v
    return Q


def setp(P, **kw):
    """P[k] = v; keys use '__' for '.'."""
    Q = Pose(P)
    for k, v in kw.items():
        Q[k.replace("__", ".")] = v
    return Q


def addsym(P, **kw):
    Q = Pose(P)
    for k, v in kw.items():
        b, comp = k.replace("__", ".").rsplit(".", 1)
        lk = "%s.L.%s" % (b, comp)
        rk, sg = N.mirror_key(lk)
        Q[lk] = Q.g(lk) + v
        Q[rk] = Q.g(rk) + v * sg
    return Q


_SOLVER = None


def solver():
    global _SOLVER
    if _SOLVER is None:
        _SOLVER = N.Solver()
    return _SOLVER


# --------------------------------------------------------------------------------------
# hands and arm IK helpers
# --------------------------------------------------------------------------------------
def hand_world_euler(direction, palm):
    """Euler (wx, wy, wz) for a LEFT hand whose fingers point along `direction` with the palm facing `palm`."""
    d = Vector(direction).normalized()
    pn = Vector(palm)
    pn = (pn - d * pn.dot(d)).normalized()
    q = N.q_from_frames(N.PALM_N, N._FA, pn, d)
    e = q.to_euler("XYZ")
    return degrees(e.x), degrees(e.y), degrees(e.z)


def set_arm_ik(P, s, wrist, hand_dir, palm, w=1.0, pole=0.0, chest=0.0):
    """Wrist target and hand orientation for side s (values for the LEFT side; mirrored for R)."""
    sg = 1.0 if s == "L" else -1.0
    P["arm.%s.ik" % s] = w
    P["arm.%s.x" % s] = wrist[0]
    P["arm.%s.y" % s] = wrist[1] * sg
    P["arm.%s.z" % s] = wrist[2]
    P["arm.%s.pole" % s] = pole
    P["arm.%s.chest" % s] = chest
    wx, wy, wz = hand_world_euler(hand_dir, palm)
    P["hand.%s.wx" % s] = wx * sg
    P["hand.%s.wy" % s] = wy
    P["hand.%s.wz" % s] = wz * sg
    return P


def elbow_to(P, s, direction, w=1.0):
    """Elbow pole in character space (world terms, NOT mirrored for the right side)."""
    P["arm.%s.pw" % s] = w
    P["arm.%s.px" % s], P["arm.%s.py" % s], P["arm.%s.pz" % s] = direction
    return P


def fill_arm_targets(P, sides=("L", "R")):
    """IK targets that match the FK arm of this pose (so FK <-> IK blends do not jump).  Only for sides with ik = 0."""
    Q = Pose(P)
    todo = [s for s in sides if Q.g("arm.%s.ik" % s) <= 0.0]
    if not todo:
        return P
    for s in todo:
        Q["arm.%s.ik" % s] = 0.0
    D, _, pos, _ = solver().solve(Q)
    for s in todo:
        wr = pos["hand." + s]
        P["arm.%s.x" % s], P["arm.%s.y" % s], P["arm.%s.z" % s] = wr.x, wr.y, wr.z
        e = D["hand." + s].to_euler("XYZ")
        P["hand.%s.wx" % s], P["hand.%s.wy" % s], P["hand.%s.wz" % s] = degrees(e.x), degrees(e.y), degrees(e.z)
        P["arm.%s.ik" % s] = 0.0
        P["arm.%s.chest" % s] = 0.0
        P.setdefault("arm.%s.pole" % s, 0.0)
    return P


def ik_to_fk(P, sides=("L", "R")):
    """The same pose with the arms as FK angles (ik = 0): a key after which the clip can move in FK with no
    FK/IK mismatch (the IK solution's local rotations become the FK parameters)."""
    Q = Pose(P)
    _, L, _, _ = solver().solve(P)
    for s in sides:
        for b in ("upper_arm", "forearm", "hand"):
            e = L["%s.%s" % (b, s)].to_euler("XYZ")
            Q["%s.%s.rx" % (b, s)], Q["%s.%s.ry" % (b, s)], Q["%s.%s.rz" % (b, s)] = degrees(e.x), degrees(e.y), degrees(e.z)
        Q["arm.%s.ik" % s] = 0.0
    return fill_arm_targets(Q, sides)


def fk(P):
    return fill_arm_targets(Pose(P))


def feet(P, x=None, y=0.115, yaw=7.0, knee_out=3.0, sides=("L", "R")):
    for s in sides:
        set_foot(P, s, (ANK.x if x is None else x, y, ANK.z), yaw=yaw, knee_out=knee_out)
    return P


# --------------------------------------------------------------------------------------
# rest poses of the pose states
# --------------------------------------------------------------------------------------
def make_stand():
    """Arms 9 deg from the body (bind is 30 deg), elbows bent 14 deg, palms to the thighs (critic r1 #5)."""
    P = Pose()
    P["hips.z"] = -0.010
    P["spine.ry"] = 1.5
    P["chest.ry"] = -1.0
    P["neck.ry"] = 2.0
    P["head.ry"] = -2.5
    sym(P, **{"shoulder.rx": -2.0,
              "upper_arm.rx": -19.0, "upper_arm.ry": -3.0, "upper_arm.rz": 6.0,
              "forearm.rx": 1.0, "forearm.ry": -14.0, "forearm.rz": 8.0,
              "hand.rx": 3.0, "hand.ry": -6.0})
    return feet(P)


STAND = fill_arm_targets(make_stand())


def make_sit():
    P = Pose()
    P["hips.x"] = -0.245
    P["hips.z"] = -0.351
    P["hips.ry"] = -7.0
    P["spine.ry"] = 7.0
    P["chest.ry"] = 0.0
    P["neck.ry"] = 4.0
    P["head.ry"] = 0.0
    sym(P, **{"shoulder.rx": -1.0, "upper_arm.rx": -12.0, "upper_arm.ry": -30.0, "forearm.ry": -45.0,
              "hand.ry": -10.0})
    for s in ("L", "R"):
        set_foot(P, s, (-0.020, 0.125, ANK.z), yaw=8.0, knee_out=6.0)
        # gloves rest ON the thighs (1 cm higher than the pilot: critic r1 animation #4)
        set_arm_ik(P, s, (-0.045, 0.158, 0.676), (1.0, 0.03, -0.26), (0.0, 0.12, -1.0), w=1.0, pole=10.0)
    return P


SIT = make_sit()


def make_kneel():
    """Right knee down, left foot on the stand spot, hands at a panel 0.45 m ahead, 0.4 m high."""
    P = Pose()
    P.update({"hips.x": -0.141, "hips.z": -0.422, "hips.ry": 12.0, "hips.rz": -4.0,
              "spine.ry": 8.5, "chest.ry": 5.0, "neck.ry": -2.0, "head.ry": 7.0, "head.rz": 3.0})
    sym(P, **{"shoulder.rx": 1.0, "shoulder.rz": -16.0})      # shoulders forward: reach without leaning in
    set_foot(P, "L", (ANK.x + 0.02, 0.125, ANK.z), yaw=6.0, knee_out=8.0)
    # right foot behind on its toes: shin almost level, toes flat on the ground
    set_foot(P, "R", (-0.470, 0.115, 0.178), pitch=55.0, yaw=2.0, toe=-55.0, knee_out=0.0)
    # left hand holds the panel's edge (fingers forward, palm in); right hand points a tool at the panel
    set_arm_ik(P, "L", (0.300, 0.190, 0.430), (1.0, -0.15, 0.05), (0.0, -1.0, 0.0), w=1.0, pole=-10.0)
    set_arm_ik(P, "R", (0.285, 0.060, 0.385), (1.0, -0.10, 0.0), (0.0, -1.0, -0.3), w=1.0, pole=0.0)
    return P


KNEEL = make_kneel()


def _side_lying(P, hx, hy, hz, curl=1.0):
    """Lying on the LEFT side, head to +Y, facing +X (hips rolled -90 deg about X)."""
    P.update({"hips.x": hx, "hips.y": hy, "hips.z": hz, "hips.rx": -90.0, "hips.ry": 0.0, "hips.rz": 0.0})
    for s in ("L", "R"):
        P["knee.%s.body" % s] = 1.0
        P["foot.%s.rel" % s] = 1.0
        P["foot.%s.rp" % s] = 22.0
    return P


def make_lie():
    """sleep frame 0: on the mattress (top 0.55 m, centre line 0.55 m behind the stand point), head to +Y.
    On the left side; the spine bends sideways so the lower shoulder rests on the mattress, not in it."""
    P = Pose()
    _side_lying(P, -0.505, 0.060, -0.232)
    P.update({"spine.ry": 10.0, "chest.ry": 8.0, "spine.rx": 9.0, "chest.rx": 9.0, "neck.ry": 8.0, "neck.rx": -6.0,
              "head.ry": 4.0, "head.rx": -6.0})
    set_foot(P, "L", (-0.33, 0.0, 0.640), knee_out=0.0)
    P["foot.L.y"] = -0.600
    set_foot(P, "R", (-0.29, 0.0, 0.800), knee_out=0.0)
    P["foot.R.y"] = -0.530
    for s in ("L", "R"):
        P["knee.%s.body" % s] = 1.0
        P["foot.%s.rel" % s] = 1.0
        P["foot.%s.rp" % s] = 24.0
    # bottom hand by the face on the mattress, top hand resting in front of the chest
    set_arm_ik(P, "L", (-0.140, 0.640, 0.615), (0.35, 1.0, 0.0), (1.0, 0.0, 0.0), w=1.0, pole=0.0)
    elbow_to(P, "L", (0.25, -1.0, 0.05))                 # bottom elbow along the mattress, towards the feet
    # (set_arm_ik mirrors y for the right side: these values put the right hand at y +0.30, pointing to +Y)
    set_arm_ik(P, "R", (-0.230, -0.300, 0.640), (0.6, -0.6, -0.3), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    return P


LIE = make_lie()


def make_dead():
    """dead frame 0: on the ground, on the left side, head to +Y, limp (tuned to the suit: nothing below z -0.01)."""
    P = Pose()
    _side_lying(P, -0.020, 0.140, -0.755)
    P.update({"spine.ry": 6.0, "chest.ry": 4.0, "spine.rx": 10.0, "chest.rx": 10.0, "neck.ry": 14.0, "neck.rx": -8.0,
              "head.ry": 10.0, "head.rx": -12.0})
    set_foot(P, "L", (-0.12, 0.0, 0.120), knee_out=0.0)
    P["foot.L.y"] = -0.720
    set_foot(P, "R", (0.02, 0.0, 0.215), knee_out=0.0)
    P["foot.R.y"] = -0.640
    for s in ("L", "R"):
        P["knee.%s.body" % s] = 1.0
        P["foot.%s.rel" % s] = 1.0
        P["foot.%s.rp" % s] = 30.0
    # bottom arm stretched forward on the ground, top arm fallen in front
    set_arm_ik(P, "L", (0.560, 0.700, 0.100), (1.0, 0.3, 0.0), (0.0, 1.0, 0.0), w=1.0, pole=0.0)
    elbow_to(P, "L", (0.0, -0.4, 1.0))                   # arm stretched along the ground, elbow not into it
    set_arm_ik(P, "R", (0.250, -0.300, 0.130), (0.8, -0.4, -0.2), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    return P


DEAD = make_dead()


# --------------------------------------------------------------------------------------
# clip machinery
# --------------------------------------------------------------------------------------
LAGS = {"upper_arm.": 0.07, "forearm.": 0.10, "hand.": 0.12, "arm.": 0.08, "head.": 0.06, "neck.": 0.03,
        "shoulder.": 0.04, "prop.": 0.12}
LAG_MAX = 0.12


def keyed_clip(keys, loop=False, length=None, lags=None):
    """Hermite timeline.  Non-loops: first and last keys ease, and the clip is padded by the largest lag so every
    bone ends exactly on the last key.  Loops: periodic spline of `length` seconds, no lag."""
    if loop and length is not None:
        keys = [k for k in keys if k[0] < length - 1e-6]      # the wrap supplies the end key (smooth seam)
    keys = euler_compat(keys)
    tl = Timeline(keys, loop=loop, length=length)
    if loop:
        n = int(round(tl.length * FPS))
    else:
        n = int(ceil((tl.keys[-1][0] + LAG_MAX) * FPS - 1e-6))
    lg = None if loop else (lags if lags is not None else LAGS)

    def fn(f):
        return tl.sample(f / FPS, lg)
    return fn, n


def euler_compat(keys):
    """Re-express each key's rotation triples (IK hand targets hand.S.wx/wy/wz and FK arm angles) as the Euler triple
    nearest to the previous key's, so the spline does not spin a joint through an equivalent angle."""
    out = []
    prev = {}
    for k in keys:
        t, P = k[0], Pose(k[1])
        for s in ("L", "R"):
            triples = [(("w", s), ["hand.%s.w%s" % (s, c) for c in "xyz"])]
            triples += [((bn, s), ["%s.%s.r%s" % (bn, s, c) for c in "xyz"]) for bn in ("upper_arm", "forearm", "hand")]
            for key, kk in triples:
                if not any(x in P for x in kk):
                    continue
                q = qeuler(P.g(kk[0]), P.g(kk[1]), P.g(kk[2]))
                e = q.to_euler("XYZ", prev[key]) if key in prev else q.to_euler("XYZ")
                P[kk[0]], P[kk[1]], P[kk[2]] = degrees(e.x), degrees(e.y), degrees(e.z)
                prev[key] = e
        out.append((t, P) + tuple(k[2:]))
    return out


def periodic(base, n, terms):
    """base + sum(term(u) - term(0)); u = f / n.  terms: {param: fn(u)}.  Exact seam."""
    def fn(f):
        u = f / n
        P = Pose(base)
        for k, g in terms.items():
            P[k] = P.g(k) + g(u) - g(0.0)
        return P
    return fn


def bump(u, c, w):
    """Smooth 0..1..0 bump centred on c (loop phase), half width w."""
    d = (u - c + 0.5) % 1.0 - 0.5
    x = d / w
    return (1.0 - x * x) ** 2 if abs(x) < 1.0 else 0.0


# --------------------------------------------------------------------------------------
# idle (4 s): weight shift 6.5 cm, upper-body turn 16 deg, a look at the wrist panel (critic r1 animation #3)
# --------------------------------------------------------------------------------------
IDLE_FRAMES = 120


def idle_keys():
    S0 = Pose(STAND)
    K1 = add(S0, hips__y=-0.034, hips__rx=-2.6, hips__rz=-1.0, hips__z=-0.006, spine__rx=1.6, chest__rx=1.0,
             spine__rz=7.5, chest__rz=9.5, head__rz=9.0, neck__rz=4.0, chest__ry=-1.2)
    K1 = addsym(K1, forearm__ry=-3.0)
    K1 = fill_arm_targets(K1)
    # look at the wrist panel: left forearm up in front of the chest, screen towards the face
    K2 = add(S0, hips__y=-0.030, hips__rx=-2.2, hips__rz=-2.0, spine__rz=2.0, chest__rz=4.0, spine__rx=1.2,
             neck__ry=10.0, head__ry=16.0, head__rz=10.0, chest__ry=2.0)
    set_arm_ik(K2, "L", (0.235, 0.115, 1.175), (0.35, -1.0, 0.10), (0.1, 0.0, -1.0), w=1.0, pole=-25.0)
    K2 = fill_arm_targets(K2, sides=("R",))
    K3 = Pose(K2)
    K3.update({"head.rz": K2.g("head.rz") + 3.0, "head.ry": K2.g("head.ry") + 2.0})
    K3["arm.L.z"] = K2.g("arm.L.z") + 0.012
    K4 = add(S0, hips__y=0.030, hips__rx=2.4, hips__rz=1.5, spine__rx=-1.4, chest__rx=-0.8, spine__rz=-1.5,
             chest__rz=-1.0, head__rz=-3.0, chest__ry=-1.0)
    K4 = fill_arm_targets(K4)
    return [(0.0, S0), (0.80, K1), (1.70, K2, {"hold": True}), (2.20, K3, {"hold": True}), (3.05, K4), (4.0, S0)]


def idle_fn():
    fn, n = keyed_clip(idle_keys(), loop=True, length=4.0)
    return fn, n


# --------------------------------------------------------------------------------------
# idle_look (6 s): looks around
# --------------------------------------------------------------------------------------
def idle_look_keys():
    S0 = Pose(STAND)
    L1 = add(S0, head__rz=26.0, neck__rz=10.0, chest__rz=9.0, spine__rz=5.0, hips__rz=2.0, hips__y=-0.015,
             hips__rx=-1.2, head__ry=-2.0)
    L1 = addsym(L1, forearm__ry=-2.0)
    L2 = add(L1, head__rz=3.0, head__ry=2.0)
    R1 = add(S0, head__rz=-24.0, neck__rz=-9.0, chest__rz=-8.0, spine__rz=-4.0, hips__rz=-2.0, hips__y=0.015,
             hips__rx=1.2, head__ry=-4.0)
    R2 = add(R1, head__rz=-3.0, head__ry=-6.0, neck__ry=-4.0)
    U1 = add(S0, head__ry=-14.0, neck__ry=-6.0, chest__ry=-2.0, head__rz=6.0)
    ks = [(0.0, S0), (0.9, L1), (1.9, L2, {"hold": True}), (2.8, R1), (3.8, R2, {"hold": True}), (4.7, U1),
          (6.0, S0)]
    return [(t, fill_arm_targets(Pose(P)), *o) for (t, P, *o) in ks]


# --------------------------------------------------------------------------------------
# gaits: walk, run, carry_walk, injured_walk.  Planted feet pivot on the heel, then flat, then on the toe joint.
# --------------------------------------------------------------------------------------
def foot_stance(u, F, stride):
    """u = phase since heel strike (0 .. stance).  Returns ankle, pitch, toe (left-side values)."""
    heel_x = F["heel_x"] - stride * u
    y, yaw = F["y"], F["yaw"]
    if u <= F["hs_end"]:
        pitch = -F["p_hs"] * (1.0 - ease(u / F["hs_end"])) if F["hs_end"] > 0 else 0.0
    elif u <= F["flat_end"]:
        pitch = 0.0
    else:
        x = (u - F["flat_end"]) / (F["stance"] - F["flat_end"])
        pitch = F["p_to"] * (x ** F.get("to_pow", 1.6))
    qy = qeuler(0, 0, yaw)
    if pitch <= 0.0:
        return ankle_from_pivot(Vector((heel_x, y, 0.0)), HEEL, pitch, yaw), pitch, 0.0
    ball_world = Vector((heel_x, y, 0.0)) + qy @ (BALL - HEEL)
    return ankle_from_pivot(ball_world, BALL, pitch, yaw), pitch, -pitch


def gait_foot(u, F, stride):
    st = F["stance"]
    if u < st:
        return foot_stance(u, F, stride)
    s = (u - st) / (1.0 - st)
    h = 1e-3
    a0, p0, _ = foot_stance(st, F, stride)
    v0 = (a0 - foot_stance(st - h, F, stride)[0]) / h
    a1, p1, _ = foot_stance(0.0, F, stride)
    v1 = (foot_stance(h, F, stride)[0] - a1) / h
    dur = 1.0 - st
    ank = Vector([N.hermite(a0[i], a1[i], v0[i] * dur, v1[i] * dur, s) for i in range(3)])
    k = F.get("lift_skew", 1.0)                         # < 1: the lift peaks early (heel kick of a run)
    ank.z += F["clear"] * sin(pi * (s ** k)) ** F.get("lift_pow", 0.75)
    ank.y = F["y"] + F.get("swing_out", 0.012) * sin(pi * s)
    mid = F.get("swing_pitch", -6.0)
    if s < 0.55:
        pitch = p0 + (mid - p0) * ease(s / 0.55)
    else:
        pitch = mid + (-F["p_hs"] - mid) * ease((s - 0.55) / 0.45)
    toe = -F["p_to"] * (1.0 - ease(s / F.get("toe_relax", 0.55)))
    return ank, pitch, toe


def gait_pose_raw(f, G):
    """Legs and pelvis orientation (hips height is solved afterwards); upper body from G['upper'](phi, P)."""
    n = G["frames"]
    phi = (f % n) / n
    P = Pose()
    for s in ("L", "R"):
        F = G["feet"][s]
        u = (phi - F["offset"]) % 1.0
        ank, pitch, toe = gait_foot(u, F, G["stride"])
        set_foot(P, s, (ank.x, ank.y, ank.z), pitch=pitch, yaw=F["yaw"], toe=toe, knee_out=F.get("knee_out", 2.0))
    G["upper"](phi, P)
    return P


def leg_reach(P, s):
    """d / (l1 + l2) for side s of pose P."""
    S_ = solver()
    D, _, pos, _ = S_.solve(P)
    hip = pos["thigh." + s]
    ank = Vector((P.g("foot.%s.x" % s), P.g("foot.%s.y" % s), P.g("foot.%s.z" % s)))
    return (ank - hip).length / (S_.len["thigh." + s] + S_.len["shin." + s])


def knee_flex(P, s):
    """Knee bend (deg, 0 = straight) of side s."""
    S_ = solver()
    D, _, _, _ = S_.solve(P)
    a = D["thigh." + s] @ (N.BIND_HEAD["shin." + s] - N.BIND_HEAD["thigh." + s]).normalized()
    b = D["shin." + s] @ (N.BIND_HEAD["foot." + s] - N.BIND_HEAD["shin." + s]).normalized()
    return degrees(a.angle(b))


def hips_for(P, legs, target):
    """Highest hips.z (bisection) at which every leg in `legs` has reach <= target[leg]."""
    lo, hi = -0.60, 0.10
    for _ in range(26):
        mid = (lo + hi) / 2
        Q = setp(P, hips__z=mid)
        ok = all(leg_reach(Q, s) <= target[s] for s in legs)
        if ok:
            lo = mid
        else:
            hi = mid
    return lo


def make_gait(G):
    """Frames 0..n (last = first).  Hips height: each planted leg reaches G['reach'](u) (a knee bend profile);
    in flight the hips follow a smooth arc between take-off and landing."""
    n = G["frames"]
    raw = [gait_pose_raw(f, G) for f in range(n)]
    z = [None] * n
    for f, P in enumerate(raw):
        phi = f / n
        legs, tgt = [], {}
        for s in ("L", "R"):
            F = G["feet"][s]
            u = (phi - F["offset"]) % 1.0
            if u < F["stance"]:
                legs.append(s)
                tgt[s] = G["reach"](u / F["stance"], s)
        if legs:
            z[f] = hips_for(P, legs, tgt) + G.get("hips_off", 0.0)
    if G.get("hips_curve"):
        # a set hip path (run: lowest at mid-stance, highest in flight), as high as the planted legs allow
        curve = G["hips_curve"]
        base = min(z[f] - curve(f / n) for f in range(n) if z[f] is not None)
        frames = [setp(P, hips__z=base + curve(f / n)) for f, P in enumerate(raw)]
        frames.append(frames[0])
        return frames
    # flight frames: parabola between the neighbouring stance values
    for f in range(n):
        if z[f] is not None:
            continue
        a = f
        while z[(a - 1) % n] is None:
            a -= 1
        b = f
        while z[(b + 1) % n] is None:
            b += 1
        za, zb = z[(a - 1) % n], z[(b + 1) % n]
        span = b - a + 2
        t = (f - a + 1) / span
        z[f] = za + (zb - za) * t + 4 * G.get("flight_h", 0.0) * t * (1 - t)
    # smooth (periodic), then never higher than the planted legs allow
    zz = z[:]
    for _ in range(G.get("smooth", 2)):
        zz = [(zz[(i - 1) % n] + 2 * zz[i] + zz[(i + 1) % n]) / 4.0 for i in range(n)]
    frames = []
    for f, P in enumerate(raw):
        Q = setp(P, hips__z=zz[f])
        # safety: planted legs must not over-reach after smoothing
        for s in ("L", "R"):
            F = G["feet"][s]
            if ((f / n - F["offset"]) % 1.0) < F["stance"] and leg_reach(Q, s) > 0.9985:
                Q = setp(Q, hips__z=hips_for(Q, [s], {s: 0.9985}))
        frames.append(Q)
    frames.append(frames[0])
    return frames


def _walk_upper(phi, P, arms=True, lean=1.0):
    c1 = cos(TAU * phi)
    P["hips.y"] = 0.020 * sin(TAU * (phi - 0.05))
    P["hips.rx"] = 2.5 * sin(TAU * (phi - 0.05))
    P["hips.rz"] = -5.5 * c1
    P["hips.ry"] = 3.0 * lean + 1.0 * cos(2 * TAU * (phi - 0.1))
    P["spine.rz"] = 3.2 * cos(TAU * (phi - 0.02))
    P["chest.rz"] = 3.8 * cos(TAU * (phi - 0.04))
    P["spine.rx"] = -1.6 * sin(TAU * (phi - 0.08))
    P["chest.rx"] = -1.0 * sin(TAU * (phi - 0.12))
    P["spine.ry"] = 2.5 * lean
    P["chest.ry"] = 0.5 * lean + 1.2 * cos(2 * TAU * (phi - 0.14))
    P["neck.ry"] = 0.0
    P["head.aim"] = 0.85
    P["head.wy"] = 4.0 + 0.8 * cos(2 * TAU * (phi - 0.2))
    if not arms:
        return
    for s, off in (("L", 0.0), ("R", 0.5)):
        sg = 1.0 if s == "L" else -1.0
        q = phi + off
        P["shoulder.%s.rx" % s] = -2.0 * sg
        P["shoulder.%s.rz" % s] = -2.5 * cos(TAU * (q - 0.03)) * sg
        P["upper_arm.%s.rx" % s] = -17.0 * sg
        P["upper_arm.%s.ry" % s] = -5.0 + 20.0 * cos(TAU * (q - 0.03))
        P["upper_arm.%s.rz" % s] = 6.0 * sg
        fl = 0.5 - 0.5 * cos(TAU * (q - 0.11))
        P["forearm.%s.ry" % s] = -15.0 - 20.0 * fl
        P["forearm.%s.rx" % s] = 1.0 * sg
        P["forearm.%s.rz" % s] = 8.0 * sg
        P["hand.%s.ry" % s] = -6.0 - 4.0 * fl
        P["hand.%s.rx" % s] = 3.0 * sg


def _foot(offset, stance, heel_x, **kw):
    F = dict(offset=offset, stance=stance, heel_x=heel_x, p_hs=16.0, p_to=34.0, y=0.105, yaw=5.0, clear=0.060,
             hs_end=0.10, flat_end=0.35)
    F.update(kw)
    return F


def walk_reach(u, s):
    """Knee bend 12-14 deg at heel strike and mid-stance (critic r1 animation #2): reach 0.992 -> about 13 deg."""
    return 0.9925


WALK = dict(frames=32, stride=1.12, reach=walk_reach, smooth=2,
            feet={"L": _foot(0.0, 0.60, 0.245), "R": _foot(0.5, 0.60, 0.245)},
            upper=lambda phi, P: _walk_upper(phi, P))


def _run_upper(phi, P):
    c1 = cos(TAU * phi)
    P["hips.y"] = 0.012 * sin(TAU * (phi - 0.10))
    P["hips.rx"] = 3.0 * sin(TAU * (phi - 0.10))
    P["hips.rz"] = -9.0 * c1
    P["hips.ry"] = 6.0 + 1.5 * cos(2 * TAU * (phi - 0.12))
    P["spine.rz"] = 5.5 * cos(TAU * (phi - 0.03))
    P["chest.rz"] = 6.5 * cos(TAU * (phi - 0.06))
    P["spine.rx"] = -1.8 * sin(TAU * (phi - 0.12))
    P["spine.ry"] = 3.0
    P["chest.ry"] = 1.0 + 2.0 * cos(2 * TAU * (phi - 0.18))
    P["head.aim"] = 0.9
    P["head.wy"] = 5.0 + 1.5 * cos(2 * TAU * (phi - 0.25))
    for s, off in (("L", 0.0), ("R", 0.5)):
        sg = 1.0 if s == "L" else -1.0
        q = phi + off
        sw = cos(TAU * (q - 0.04))                                   # +1 arm back, -1 arm forward
        P["shoulder.%s.rx" % s] = -1.0 * sg
        P["shoulder.%s.rz" % s] = -4.0 * sw * sg
        P["upper_arm.%s.rx" % s] = -16.0 * sg
        P["upper_arm.%s.ry" % s] = -10.0 + 34.0 * sw
        P["upper_arm.%s.rz" % s] = 10.0 * sg
        P["forearm.%s.ry" % s] = -68.0 - 10.0 * (0.5 - 0.5 * cos(TAU * (q - 0.12)))    # elbows 68-78 deg
        P["forearm.%s.rz" % s] = 16.0 * sg
        P["hand.%s.ry" % s] = -12.0
        P["hand.%s.rx" % s] = 6.0 * sg


def run_reach(u, s):
    """Upper limit for the planted leg (the hip path itself is RUN['hips_curve'])."""
    return 0.990


def run_hips(phi):
    """3.6 cm bob: lowest at mid-stance of each foot (phase 0.185 and 0.685), highest in flight."""
    return 0.018 * cos(2 * TAU * (phi - 0.165 - 0.25))


RUN = dict(frames=20, stride=2.27, reach=run_reach, smooth=1, flight_h=0.006, hips_curve=run_hips,
           feet={s: _foot(off, 0.33, 0.255, p_hs=7.0, p_to=44.0, hs_end=0.05, flat_end=0.15, clear=0.30,
                          lift_skew=0.62, lift_pow=0.9, swing_pitch=4.0, toe_relax=0.45, swing_out=0.018, y=0.095,
                          yaw=3.0, to_pow=1.3)
                 for s, off in (("L", 0.0), ("R", 0.5))},
           upper=_run_upper)


# carrying: arms and crate ride with the chest (chest-relative IK targets)
def carry_arms(P, w=1.0):
    c = CARRY["bottom_centre"]
    half = CARRY["size"] / 2
    for s in ("L", "R"):
        # wrists at the crate sides, back half, mid height; fingers forward, palms against the crate
        set_arm_ik(P, s, (0.305, half + 0.048, c[2] + half + 0.005), (1.0, 0.02, -0.10), (0.0, -1.0, 0.0),
                   w=w, pole=-15.0, chest=1.0)
    # the crate rides the right hand: prop.R keeps its bind pose in every clip (no prop keys); the crate's fixed
    # offset from prop.R is written to astronaut_anims.json (carry.prop_R_offset) by npc_build.py
    return P


def _carry_upper(phi, P):
    _walk_upper(phi, P, arms=False, lean=0.3)
    P["spine.ry"] = -2.5
    P["chest.ry"] = -2.0 + 1.0 * cos(2 * TAU * (phi - 0.14))
    P["hips.rz"] = -4.0 * cos(TAU * phi)
    P["chest.rz"] = 2.0 * cos(TAU * (phi - 0.04))
    sym(P, **{"shoulder.rx": 2.0})
    carry_arms(P)
    # elbow give: the load sinks 1.2 cm at each foot strike and comes back (about 5 deg at the elbows)
    give = 0.012 * (bump(phi, 0.07, 0.14) + bump(phi, 0.57, 0.14))
    for s in ("L", "R"):
        P["arm.%s.z" % s] -= give
        P["arm.%s.x" % s] += 0.3 * give


CARRY_WALK = dict(WALK, feet={"L": _foot(0.0, 0.60, 0.245), "R": _foot(0.5, 0.60, 0.245)}, upper=_carry_upper)


def _injured_upper(phi, P):
    # antalgic lurch over the hurt right leg, head down, left hand holding the right side, right arm stiff
    P["hips.y"] = -0.028 * bump(phi, 0.78, 0.26) + 0.012 * bump(phi, 0.30, 0.25)
    P["hips.rx"] = -3.5 * bump(phi, 0.78, 0.26) + 2.0 * bump(phi, 0.30, 0.25)
    P["hips.rz"] = -3.0 * cos(TAU * phi)
    P["hips.ry"] = 5.0
    P["spine.rx"] = 4.0 * bump(phi, 0.80, 0.28)
    P["spine.ry"] = 5.0
    P["chest.ry"] = 3.0 + 1.5 * bump(phi, 0.80, 0.22)
    P["chest.rz"] = 2.0 * cos(TAU * phi)
    P["head.aim"] = 0.7
    P["head.wy"] = 14.0
    P["head.wz"] = -4.0
    set_arm_ik(P, "L", (0.105, -0.06, 1.070), (-0.2, -1.0, -0.25), (0.3, 0.0, 0.2), w=1.0, pole=-30.0, chest=1.0)
    P.update({"shoulder.R.rx": 3.0, "upper_arm.R.rx": 19.0, "upper_arm.R.ry": -2.0 + 5.0 * cos(TAU * (phi - 0.6)),
              "forearm.R.ry": -24.0, "hand.R.ry": -8.0})


def injured_reach(u, s):
    return 0.990 if s == "L" else 0.9965                # the hurt right knee stays nearly straight in stance


INJURED = dict(frames=40, stride=0.90, reach=injured_reach, smooth=2,
               feet={"L": _foot(0.0, 0.67, 0.215, clear=0.055),
                     "R": _foot(0.55, 0.53, 0.180, clear=0.030, p_to=20.0, p_hs=8.0, swing_out=0.045, yaw=12.0,
                                knee_out=10.0)},
               upper=_injured_upper)


# --------------------------------------------------------------------------------------
# carry_idle (3 s)
# --------------------------------------------------------------------------------------
def carry_base():
    P = Pose(STAND)
    P.update({"spine.ry": -2.0, "chest.ry": -2.5, "neck.ry": 3.0, "head.ry": 4.0})
    sym(P, **{"shoulder.rx": 2.0})
    return carry_arms(P)


# --------------------------------------------------------------------------------------
# work poses
# --------------------------------------------------------------------------------------
def work_console_base():
    P = Pose(STAND)
    P.update({"hips.x": -0.010, "hips.ry": 4.0, "spine.ry": 6.0, "chest.ry": 4.0, "neck.ry": 12.0, "head.ry": 14.0})
    # fingers on the console top (1.0 m) at 0.40..0.50 m ahead: wrists just above, hands pitched down
    set_arm_ik(P, "L", (0.345, 0.125, 1.102), (1.0, -0.10, -0.40), (0.0, 0.40, -1.0), w=1.0, pole=-55.0)
    set_arm_ik(P, "R", (0.360, 0.090, 1.102), (1.0, 0.05, -0.40), (0.0, 0.40, -1.0), w=1.0, pole=-55.0)
    P["arm.L.stiff"] = P["arm.R.stiff"] = 1.0
    return P


def work_bench_base():
    P = Pose(STAND)
    P.update({"hips.x": -0.020, "hips.ry": 6.0, "spine.ry": 9.0, "chest.ry": 5.0, "neck.ry": 14.0, "head.ry": 20.0})
    for s in ("L", "R"):
        set_foot(P, s, (ANK.x - 0.01, 0.140, ANK.z), yaw=10.0, knee_out=5.0)
    # left hand holds the work on the bench (0.9 m), right hand works it with a tool held at prop.R
    set_arm_ik(P, "L", (0.300, 0.140, 1.019), (1.0, -0.25, -0.45), (0.0, 0.45, -1.0), w=1.0, pole=-55.0)
    set_arm_ik(P, "R", (0.330, 0.070, 1.037), (0.8, 0.45, -0.35), (0.0, -0.1, -1.0), w=1.0, pole=-50.0)
    P["arm.L.stiff"] = P["arm.R.stiff"] = 1.0
    return P


def talk_base():
    return Pose(STAND)


# --------------------------------------------------------------------------------------
# clip definitions
# --------------------------------------------------------------------------------------
def sit_enter_keys():
    S0 = Pose(STAND)
    K1 = add(S0, hips__z=-0.035, hips__x=-0.02, hips__ry=4.0, spine__ry=5.0, chest__ry=2.0, neck__ry=6.0, head__ry=4.0)
    K1 = fill_arm_targets(addsym(K1, upper_arm__ry=-6.0, forearm__ry=-4.0))
    K2 = Pose(STAND)
    K2.update({"hips.x": -0.135, "hips.z": -0.205, "hips.ry": 16.0, "spine.ry": 13.0, "chest.ry": 6.0,
               "neck.ry": -9.0, "head.ry": -8.0})
    sym(K2, **{"upper_arm.ry": -34.0, "upper_arm.rx": -12.0, "forearm.ry": -34.0, "hand.ry": -10.0})
    K2 = fill_arm_targets(K2)
    K3 = Pose(SIT)
    K3.update({"hips.x": -0.232, "hips.z": -0.332, "hips.ry": 3.0, "spine.ry": 10.0, "chest.ry": 4.0, "neck.ry": -2.0,
               "head.ry": -2.0})
    for s in ("L", "R"):
        K3["arm.%s.ik" % s] = 0.55
        K3["arm.%s.z" % s] = SIT.g("arm.%s.z" % s) + 0.06
        K3["arm.%s.x" % s] = SIT.g("arm.%s.x" % s) + 0.05
    K4 = Pose(SIT)
    K4.update({"hips.z": SIT.g("hips.z") - 0.005, "hips.ry": -9.0, "spine.ry": 5.0, "chest.ry": -0.5, "neck.ry": 5.0})
    for s in ("L", "R"):
        K4["arm.%s.z" % s] = SIT.g("arm.%s.z" % s) + 0.012
    return [(0.0, S0, {"hold": True}), (0.32, K1), (0.80, K2), (1.26, K3), (1.48, K4), (1.80, Pose(SIT), {"hold": True})]


def sit_exit_keys():
    K1 = Pose(SIT)
    K1.update({"hips.x": -0.228, "hips.ry": 9.0, "spine.ry": 15.0, "chest.ry": 6.0, "neck.ry": -8.0, "head.ry": -4.0})
    for s in ("L", "R"):
        K1["arm.%s.x" % s] = SIT.g("arm.%s.x" % s) + 0.025
        K1["arm.%s.z" % s] = SIT.g("arm.%s.z" % s) - 0.010
    K2 = Pose(K1)
    K2.update({"hips.x": -0.135, "hips.z": -0.245, "hips.ry": 17.0, "spine.ry": 14.0, "chest.ry": 6.0, "neck.ry": -10.0,
               "head.ry": -6.0})
    for s in ("L", "R"):
        K2["arm.%s.ik" % s] = 0.75
        K2["arm.%s.x" % s] = SIT.g("arm.%s.x" % s) + 0.08
        K2["arm.%s.z" % s] = SIT.g("arm.%s.z" % s) + 0.02
    K3 = Pose(STAND)
    K3.update({"hips.x": -0.035, "hips.z": -0.075, "hips.ry": 7.0, "spine.ry": 7.0, "chest.ry": 1.0, "neck.ry": -2.0,
               "head.ry": -3.0})
    sym(K3, **{"upper_arm.ry": -14.0, "forearm.ry": -24.0})
    K3 = fill_arm_targets(K3)
    K4 = fill_arm_targets(add(Pose(STAND), hips__z=-0.006))
    return [(0.0, Pose(SIT), {"hold": True}), (0.38, K1), (0.76, K2), (1.22, K3), (1.46, K4),
            (1.64, Pose(STAND), {"hold": True})]


def sit_idle_fn(n=150):
    def fn(f):
        u = f / n

        def w(g):
            return g(u) - g(0.0)
        P = add(SIT,
                chest__ry=w(lambda u: -1.2 * sin(TAU * u)),
                spine__ry=w(lambda u: 0.6 * sin(TAU * u)),
                hips__rx=w(lambda u: 0.8 * sin(TAU * u + 0.3)),
                spine__rx=w(lambda u: -0.6 * sin(TAU * u)),
                head__rz=w(lambda u: 9.0 * sin(TAU * u + 0.5) + 3.0 * sin(2 * TAU * u)),
                head__ry=w(lambda u: 3.0 * sin(2 * TAU * u + 0.8)),
                neck__rz=w(lambda u: 3.0 * sin(TAU * u + 0.3)),
                head__rx=w(lambda u: -1.2 * sin(TAU * u - 0.4)))
        P = addsym(P, shoulder__rx=w(lambda u: 0.8 * sin(TAU * u - 0.3)))
        tap = bump(u, 0.55, 0.03) + bump(u, 0.63, 0.03)
        P["arm.R.z"] = P.g("arm.R.z") + 0.020 * tap
        return P
    return fn, n


def sit_eat_keys():
    """Bowl in the left hand, spoon in the right: scoop, lift to the mouth, down; twice in 4 s."""
    B = Pose(SIT)
    B.update({"spine.ry": 12.0, "chest.ry": 4.0, "neck.ry": 8.0, "head.ry": 10.0})
    # left hand rests on the table beside the bowl (palm down); the right hand eats
    set_arm_ik(B, "L", (0.270, 0.135, 0.800), (1.0, -0.25, -0.35), (0.0, 0.15, -1.0), w=1.0, pole=10.0)
    scoop = set_arm_ik(Pose(B), "R", (0.205, 0.000, 0.895), (0.6, -0.5, -0.5), (0.0, -0.4, -1.0), w=1.0, pole=-5.0)
    up = set_arm_ik(Pose(B), "R", (0.160, 0.050, 1.100), (-0.1, -0.35, 0.95), (0.3, -1.0, 0.0), w=1.0, pole=-20.0)
    up.update({"head.ry": 2.0, "neck.ry": 2.0, "spine.ry": 10.0})
    chew = add(up, head__ry=-2.0)
    chew["arm.R.z"] = up.g("arm.R.z") - 0.03
    rest = Pose(scoop)
    rest["arm.R.z"] = scoop.g("arm.R.z") + 0.02
    ks = [(0.0, scoop), (0.45, up), (0.85, chew, {"hold": True}), (1.35, rest), (1.75, scoop),
          (2.2, up), (2.6, chew, {"hold": True}), (3.3, rest), (4.0, scoop)]
    return ks


def sit_type_base():
    P = Pose(SIT)
    P.update({"spine.ry": 12.0, "chest.ry": 5.0, "neck.ry": 8.0, "head.ry": 8.0})
    # desk top 0.74 m, keys 0.30..0.40 m ahead
    set_arm_ik(P, "L", (0.270, 0.125, 0.849), (1.0, -0.10, -0.40), (0.0, 0.40, -1.0), w=1.0, pole=-45.0)
    set_arm_ik(P, "R", (0.285, 0.090, 0.849), (1.0, 0.05, -0.40), (0.0, 0.40, -1.0), w=1.0, pole=-45.0)
    P["arm.L.stiff"] = P["arm.R.stiff"] = 1.0
    return P


def typing(base, n, taps=(("L", 0.10), ("R", 0.22), ("L", 0.36), ("R", 0.47), ("R", 0.60), ("L", 0.72),
                          ("R", 0.85), ("L", 0.93)), move=None):
    """Loop: alternating key taps (1.2 cm dips), a hand shift, head scanning."""
    def fn(f):
        u = f / n
        P = Pose(base)
        for s, c in taps:
            P["arm.%s.z" % s] = P.g("arm.%s.z" % s) - 0.012 * bump(u, c, 0.045)
        for s, c, dx, dy in (move or (("L", 0.55, 0.03, 0.05),)):
            b = bump(u, c, 0.16)
            P["arm.%s.x" % s] += dx * b
            P["arm.%s.y" % s] += dy * b * (1 if s == "L" else -1)
        P["head.rz"] = P.g("head.rz") + 4.0 * (sin(TAU * u) - 0.0)
        P["head.ry"] = P.g("head.ry") + 2.0 * sin(2 * TAU * u)
        P["chest.ry"] = P.g("chest.ry") + 0.8 * sin(TAU * u)
        return P
    return fn


def work_bench_fn(n=120):
    base = work_bench_base()

    def fn(f):
        u = f / n
        P = Pose(base)
        # three ratchet strokes: the tool hand swings about the forearm axis and pushes
        k = sin(3 * TAU * u)
        P["arm.R.x"] += 0.020 * k
        P["arm.R.y"] -= 0.025 * k
        P["hand.R.wz"] = P.g("hand.R.wz") + 22.0 * k
        P["hand.R.wx"] = P.g("hand.R.wx") + 10.0 * sin(3 * TAU * u + 0.5)
        P["arm.L.z"] += 0.006 * sin(TAU * u)
        P["chest.rz"] = -3.0 * sin(3 * TAU * u)
        P["spine.ry"] = base.g("spine.ry") + 1.0 * sin(3 * TAU * u)
        P["head.rz"] = 4.0 * sin(TAU * u)
        return P
    return fn, n


def talk_keys():
    S0 = Pose(STAND)
    G1 = add(S0, hips__y=0.012, hips__rx=1.0, chest__rz=-5.0, head__rz=-7.0, head__ry=-5.0)
    set_arm_ik(G1, "R", (0.300, 0.180, 1.285), (0.9, 0.2, 0.5), (0.0, -0.8, 0.4), w=1.0, pole=0.0)
    G1["arm.R.stiff"] = 0.6
    G1 = fill_arm_targets(G1, sides=("L",))
    G2 = Pose(G1)
    G2["arm.R.x"] += 0.05
    G2["arm.R.y"] -= 0.08
    G2["arm.R.z"] -= 0.03
    # the other hand answers: the left hand comes up as the right one opens out
    set_arm_ik(G2, "L", (0.270, 0.170, 1.200), (0.9, -0.2, 0.5), (0.0, -0.8, 0.4), w=1.0, pole=0.0)
    G2["arm.L.stiff"] = 0.6
    G2.update({"head.ry": 5.0, "head.rz": -3.0})
    G3 = add(S0, hips__y=-0.010, chest__rz=4.0, head__rz=5.0, head__ry=4.0)
    set_arm_ik(G3, "L", (0.300, 0.180, 1.285), (0.9, -0.2, 0.5), (0.0, -0.8, 0.4), w=1.0, pole=0.0)
    set_arm_ik(G3, "R", (0.240, 0.170, 1.080), (0.9, 0.1, 0.4), (0.0, -0.8, 0.3), w=0.6, pole=0.0)
    G3["arm.L.stiff"] = G3["arm.R.stiff"] = 0.6
    G4 = add(G3, head__ry=10.0)
    ks = [(0.0, S0), (0.7, G1), (1.3, G2), (1.8, G1), (2.5, G3), (3.1, G4), (4.0, S0)]
    return [(t, fill_arm_targets(Pose(P)), *o) for (t, P, *o) in ks]


def kneel_enter_keys():
    S0 = Pose(STAND)
    # weight onto the left foot, right heel up
    K1 = add(S0, hips__y=0.035, hips__rx=2.0, hips__z=-0.02, spine__ry=3.0)
    set_foot(K1, "R", (ANK.x - 0.06, 0.115, ANK.z + 0.03), pitch=16.0, yaw=7.0, toe=-16.0, knee_out=3.0)
    K1 = fill_arm_targets(K1)
    # right foot steps back onto its toes
    K2 = add(S0, hips__y=0.020, hips__x=-0.05, hips__z=-0.10, hips__ry=6.0, spine__ry=6.0, chest__ry=3.0,
             neck__ry=4.0)
    set_foot(K2, "R", (-0.440, 0.115, 0.170), pitch=48.0, yaw=3.0, toe=-48.0, knee_out=0.0)
    set_foot(K2, "L", (ANK.x + 0.02, 0.125, ANK.z), yaw=6.0, knee_out=6.0)
    K2 = fill_arm_targets(addsym(K2, upper_arm__ry=-8.0, forearm__ry=-8.0))
    # lowering, right knee on its way down
    K3 = Pose(KNEEL)
    K3.update({"hips.z": -0.300, "hips.x": -0.095, "hips.ry": 8.0, "spine.ry": 8.0, "chest.ry": 5.0, "neck.ry": 0.0,
               "head.ry": 0.0})
    set_foot(K3, "R", (-0.465, 0.115, 0.180), pitch=55.0, yaw=2.0, toe=-55.0, knee_out=0.0)
    for s in ("L", "R"):
        K3["arm.%s.ik" % s] = 0.0
    K3 = Pose(K3)
    sym(K3, **{"upper_arm.ry": -20.0, "upper_arm.rx": -15.0, "forearm.ry": -30.0})
    K3 = fill_arm_targets(K3)
    K4 = Pose(KNEEL)
    K4.update({"hips.z": KNEEL.g("hips.z") - 0.006, "spine.ry": 12.0, "chest.ry": 8.0})
    for s in ("L", "R"):
        K4["arm.%s.ik" % s] = 0.6
        K4["arm.%s.x" % s] = KNEEL.g("arm.%s.x" % s) - 0.05
    return [(0.0, S0, {"hold": True}), (0.28, K1), (0.62, K2), (1.02, K3), (1.30, K4), (1.62, Pose(KNEEL), {"hold": True})]


def repair_kneel_fn(n=120):
    base = KNEEL

    def fn(f):
        u = f / n
        P = Pose(base)
        k = sin(4 * TAU * u)                   # four wrench turns
        P["hand.R.wx"] = P.g("hand.R.wx") + 26.0 * k
        P["arm.R.z"] += 0.010 * sin(4 * TAU * u + 1.2)
        P["arm.R.x"] += 0.008 * (sin(TAU * u) - 0.0)
        P["arm.L.z"] += 0.020 * (sin(TAU * u))
        P["arm.L.y"] += 0.015 * sin(TAU * u)
        P["chest.rz"] = P.g("chest.rz") - 2.5 * sin(4 * TAU * u)
        P["head.rz"] = P.g("head.rz") + 5.0 * sin(TAU * u)
        P["head.ry"] = P.g("head.ry") + 2.0 * sin(2 * TAU * u)
        P["chest.ry"] = P.g("chest.ry") + 1.0 * sin(TAU * u)
        return P
    return fn, n


def kneel_exit_keys():
    K1 = Pose(KNEEL)
    for s in ("L", "R"):
        K1["arm.%s.ik" % s] = 0.0
    sym(K1, **{"upper_arm.ry": -25.0, "upper_arm.rx": -14.0, "forearm.ry": -40.0})
    K1.update({"spine.ry": 8.0, "chest.ry": 5.0, "neck.ry": 2.0, "head.ry": 2.0})
    K1 = fill_arm_targets(K1)
    # push up off the left leg, left hand on the left knee
    K2 = Pose(KNEEL)
    K2.update({"hips.z": -0.270, "hips.x": -0.085, "hips.ry": 16.0, "spine.ry": 14.0, "chest.ry": 6.0,
               "neck.ry": -6.0, "head.ry": -4.0})
    set_foot(K2, "R", (-0.450, 0.115, 0.175), pitch=52.0, yaw=2.0, toe=-52.0, knee_out=0.0)
    set_arm_ik(K2, "L", (0.140, 0.170, 0.640), (1.0, 0.0, -0.4), (0.0, 0.1, -1.0), w=1.0, pole=10.0)
    K2 = fill_arm_targets(K2, sides=("R",))
    K2["arm.R.ik"] = 0.0
    sym_r = {"upper_arm.R.ry": -20.0, "upper_arm.R.rx": 16.0, "forearm.R.ry": -30.0}
    K2.update(sym_r)
    K2 = fill_arm_targets(K2, sides=("R",))
    K3 = add(Pose(STAND), hips__z=-0.09, hips__x=-0.04, hips__ry=8.0, spine__ry=6.0, hips__y=0.02)
    set_foot(K3, "R", (-0.25, 0.115, 0.150), pitch=24.0, yaw=4.0, toe=-24.0, knee_out=0.0)
    K3 = fill_arm_targets(K3)
    K4 = add(Pose(STAND), hips__y=0.020, hips__z=-0.012)
    set_foot(K4, "R", (ANK.x - 0.02, 0.115, ANK.z + 0.035), pitch=6.0, yaw=7.0, knee_out=3.0)
    K4 = fill_arm_targets(K4)
    return [(0.0, Pose(KNEEL), {"hold": True}), (0.36, K1), (0.94, K2), (1.62, K3), (1.88, K4),
            (2.12, Pose(STAND), {"hold": True})]


def lie_enter_keys():
    S0 = Pose(STAND)
    # sit on the bed edge (mattress 0.55 m)
    K1 = Pose(SIT)
    K1.update({"hips.x": -0.285, "hips.z": -0.225, "hips.ry": -4.0, "spine.ry": 6.0})
    for s in ("L", "R"):
        set_arm_ik(K1, s, (-0.20, 0.30, 0.625), (0.25, 0.95, -0.12), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
        elbow_to(K1, s, (-1.0, 0.0, 0.1))            # propping arms are straight: fix the elbow plane
    K0b = Pose(STAND)
    K0b.update({"hips.x": -0.16, "hips.z": -0.18, "hips.ry": 16.0, "spine.ry": 12.0, "chest.ry": 5.0,
                "neck.ry": -8.0, "head.ry": -6.0})
    sym(K0b, **{"upper_arm.ry": -28.0, "upper_arm.rx": -12.0, "forearm.ry": -30.0})
    K0b = fill_arm_targets(K0b)
    # lean onto the left elbow towards the head end (+Y)
    K2 = Pose(K1)
    K2.update({"hips.rx": -32.0, "hips.y": 0.05, "hips.x": -0.33, "hips.z": -0.178, "spine.rx": -10.0, "spine.ry": 4.0,
               "head.rx": 8.0})
    set_arm_ik(K2, "L", (-0.26, 0.52, 0.63), (0.2, 1.0, -0.1), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    elbow_to(K2, "L", (-0.3, -0.6, -0.2), 0.6)
    set_arm_ik(K2, "R", (-0.05, 0.10, 0.80), (0.8, 0.4, -0.6), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    # legs lifted in front of the bed, knees up
    K3 = Pose(K2)
    K3.update({"hips.rx": -62.0, "hips.x": -0.43, "hips.y": 0.07, "hips.z": -0.195, "spine.rx": -4.0})
    set_foot(K3, "L", (0.02, 0.0, 0.72), knee_out=0.0)
    K3["foot.L.y"] = -0.25
    set_foot(K3, "R", (0.06, 0.0, 0.80), knee_out=0.0)
    K3["foot.R.y"] = -0.20
    for s in ("L", "R"):
        K3["knee.%s.body" % s] = 0.7
        K3["foot.%s.rel" % s] = 0.8
        K3["foot.%s.rp" % s] = 20.0
    set_arm_ik(K3, "L", (-0.18, 0.62, 0.62), (0.3, 1.0, 0.0), (1.0, 0.0, -0.6), w=1.0, pole=0.0)
    elbow_to(K3, "L", (0.2, -1.0, 0.0), 0.9)
    set_arm_ik(K3, "R", (-0.22, -0.28, 0.72), (0.6, -0.6, -0.4), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    K2b = Pose(K2)
    K2b.update({"hips.rx": -45.0, "hips.x": -0.38, "hips.z": -0.205})
    set_foot(K2b, "L", (0.20, 0.10, 0.36), knee_out=0.0)
    set_foot(K2b, "R", (0.22, 0.05, 0.42), knee_out=0.0)
    for s in ("L", "R"):
        K2b["foot.%s.rel" % s] = 0.5
        K2b["foot.%s.rp" % s] = 15.0
        K2b["knee.%s.body" % s] = 0.4
    K4 = Pose(LIE)
    K4.update({"hips.z": LIE.g("hips.z") + 0.012, "spine.ry": 6.0})
    set_arm_ik(K2b, "R", (-0.14, -0.08, 0.78), (0.7, -0.5, -0.5), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    # halfway from sitting on the edge to leaning: lift the hips 1 cm so the far thigh clears the mattress
    K1b = Pose({k: 0.5 * (K1.g(k) + K2.g(k)) for k in set(K1) | set(K2)})
    K1b["hips.z"] = K1b.g("hips.z") + 0.022
    return [(0.0, S0, {"hold": True}), (0.48, K0b), (1.12, K1), (1.50, K1b), (1.88, K2), (2.24, K2b), (2.78, K3), (3.24, K4),
            (3.60, Pose(LIE), {"hold": True})]


def lie_exit_keys():
    K1 = Pose(LIE)
    K1.update({"spine.ry": 16.0, "chest.ry": 10.0, "neck.ry": 14.0, "head.ry": 6.0})
    K2 = Pose(K1)
    K2.update({"hips.rx": -62.0, "hips.x": -0.44, "hips.y": 0.07, "hips.z": -0.212, "spine.rx": -6.0, "spine.ry": 8.0,
               "chest.ry": 4.0})
    set_foot(K2, "L", (0.04, 0.0, 0.70), knee_out=0.0)
    K2["foot.L.y"] = -0.25
    set_foot(K2, "R", (0.08, 0.0, 0.78), knee_out=0.0)
    K2["foot.R.y"] = -0.18
    for s in ("L", "R"):
        K2["knee.%s.body" % s] = 0.7
        K2["foot.%s.rel" % s] = 0.8
        K2["foot.%s.rp" % s] = 20.0
    set_arm_ik(K2, "L", (-0.22, 0.60, 0.63), (0.3, 1.0, 0.0), (1.0, 0.0, -0.6), w=1.0, pole=0.0)
    elbow_to(K2, "L", (0.1, -1.0, 0.0), 0.8)
    set_arm_ik(K2, "R", (-0.10, 0.10, 0.78), (0.8, 0.4, -0.6), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    K3 = Pose(SIT)
    K3.update({"hips.x": -0.285, "hips.z": -0.218, "hips.ry": -2.0, "spine.ry": 10.0, "hips.rx": -8.0, "hips.y": 0.02})
    for s in ("L", "R"):
        set_arm_ik(K3, s, (-0.20, 0.30, 0.640), (0.25, 0.95, -0.05), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
        elbow_to(K3, s, (-1.0, 0.0, 0.1))
    K4 = Pose(STAND)
    K4.update({"hips.x": -0.14, "hips.z": -0.16, "hips.ry": 17.0, "spine.ry": 12.0, "chest.ry": 5.0,
               "neck.ry": -8.0, "head.ry": -6.0})
    sym(K4, **{"upper_arm.ry": -24.0, "upper_arm.rx": -13.0, "forearm.ry": -30.0})
    K4 = fill_arm_targets(K4)
    K5 = fill_arm_targets(add(Pose(STAND), hips__z=-0.008))
    return [(0.0, Pose(LIE), {"hold": True}), (0.45, K1), (1.10, K2), (1.80, K3), (2.45, K4), (2.80, K5),
            (3.02, Pose(STAND), {"hold": True})]


def sleep_fn(n=180):
    def fn(f):
        u = f / n

        def w(g):
            return g(u) - g(0.0)
        P = add(LIE,
                chest__ry=w(lambda u: -1.8 * sin(TAU * u)),
                spine__ry=w(lambda u: 0.8 * sin(TAU * u)),
                hips__z=w(lambda u: 0.002 * sin(TAU * u)),
                head__ry=w(lambda u: 1.2 * sin(TAU * u - 0.6)),
                neck__ry=w(lambda u: 0.6 * sin(TAU * u - 0.4)))
        P = addsym(P, shoulder__rx=w(lambda u: 0.8 * sin(TAU * u - 0.3)))
        return P
    return fn, n


def collapse_keys():
    S0 = Pose(STAND)
    # stagger: head drops, knees give, one step of weight to the left
    K1 = add(S0, hips__z=-0.05, hips__y=0.03, hips__rx=3.0, spine__ry=10.0, chest__ry=8.0, neck__ry=16.0, head__ry=10.0,
             head__rz=6.0)
    K1 = fill_arm_targets(addsym(K1, upper_arm__ry=-10.0, forearm__ry=-10.0))
    # on both knees, slumped forward, arms hanging
    K2 = Pose()
    K2.update({"hips.x": -0.07, "hips.z": -0.385, "hips.ry": 14.0, "hips.y": 0.03, "spine.ry": 18.0, "chest.ry": 14.0,
               "neck.ry": 22.0, "head.ry": 14.0, "head.rz": 8.0})
    for s in ("L", "R"):
        set_foot(K2, s, (-0.430, 0.125, 0.192), pitch=50.0, yaw=3.0, toe=-50.0, knee_out=2.0)
    sym(K2, **{"upper_arm.rx": -16.0, "upper_arm.ry": -12.0, "forearm.ry": -10.0})
    # slumped on both knees: hands resting on the thighs
    set_arm_ik(K2, "L", (0.060, 0.170, 0.480), (1.0, 0.0, -0.3), (0.0, 0.1, -1.0), w=1.0, pole=0.0)
    set_arm_ik(K2, "R", (0.060, 0.170, 0.480), (1.0, 0.0, -0.3), (0.0, 0.1, -1.0), w=1.0, pole=0.0)
    elbow_to(K2, "L", (-0.9, 0.5, -0.1))
    # tipping over to the left
    K3 = Pose(K2)
    K3.update({"hips.rx": -48.0, "hips.x": -0.05, "hips.y": 0.10, "hips.z": -0.55, "spine.ry": 12.0, "chest.ry": 8.0,
               "neck.ry": 16.0, "head.rx": -12.0, "spine.rz": 3.0})
    for s in ("L", "R"):
        K3["knee.%s.body" % s] = 0.6
    set_foot(K3, "L", (-0.30, 0.0, 0.22), toe=-45.0, knee_out=0.0)
    K3["foot.L.y"] = -0.35
    set_foot(K3, "R", (-0.25, 0.0, 0.32), toe=-45.0, knee_out=0.0)
    K3["foot.R.y"] = -0.30
    for s in ("L", "R"):
        K3["foot.%s.rel" % s] = 0.7
        K3["foot.%s.rp" % s] = 35.0
    set_arm_ik(K3, "L", (0.300, 0.560, 0.200), (0.9, 0.4, -0.2), (0.0, 1.0, -0.5), w=1.0, pole=0.0)
    elbow_to(K3, "L", (0.5, 0.6, 0.6))
    set_arm_ik(K3, "R", (0.260, -0.020, 0.260), (0.8, 0.3, -0.3), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    # impact: slight compression below the rest
    K4 = add(DEAD, hips__z=0.004, spine__ry=2.0, neck__ry=4.0)
    return [(0.0, S0, {"hold": True}), (0.30, K1), (0.80, K2, {"hold": True}), (1.40, K3), (1.80, K4),
            (2.15, Pose(DEAD), {"hold": True})]


SWAP_CUT_FRAME = 30


def suit_swap_keys():
    """V3_1 section 5.4: suit up / suit off, 2.0 s.  Hands to the chest seals, then to the helmet sides and a hold
    across the middle: RENDER cuts between the suit and indoor models at frame 30 (1.0 s), where the pose is still
    and identical in both files (the clip data is shared)."""
    S0 = Pose(STAND)
    K1 = add(S0, neck__ry=12.0, head__ry=10.0, spine__ry=3.0, chest__ry=2.0)
    set_arm_ik(K1, "L", (0.215, 0.080, 1.245), (0.2, -1.0, 0.3), (-1.0, 0.0, 0.2), w=1.0, pole=-10.0)
    set_arm_ik(K1, "R", (0.215, 0.090, 1.220), (0.2, -1.0, 0.1), (-1.0, 0.0, 0.2), w=1.0, pole=-10.0)
    # both hands at the helmet sides (palms in), elbows out; the same pose serves the bare head
    K2 = add(S0, neck__ry=-2.0, head__ry=-3.0, spine__ry=-1.0, chest__ry=-2.0)
    for s in ("L", "R"):
        set_arm_ik(K2, s, (0.060, 0.225, 1.620), (0.15, -0.25, 1.0), (0.0, -1.0, 0.0), w=1.0, pole=-40.0)
    K3 = Pose(K2)
    K4 = add(S0, neck__ry=-2.0, head__ry=-3.0, spine__ry=-1.0, chest__ry=-2.0)   # torso and head as at the cut: nothing moves early
    for s in ("L", "R"):          # hands on the upper chest seals, elbows still out (close to the helmet pose)
        set_arm_ik(K4, s, (0.180, 0.145, 1.410), (0.28, -1.0, 0.1), (-1.0, 0.0, 0.2), w=1.0, pole=0.0)
        elbow_to(K4, s, (-0.15, 1.0 if s == "L" else -1.0, 0.15), 1.0)
    # the stand arms reached by IK (targets = the stand wrists), then the plain stand pose: a soft IK -> FK hand-over
    K4b = fill_arm_targets(Pose(STAND))
    for s in ("L", "R"):
        K4b["arm.%s.ik" % s] = 1.0
    # waypoints with the hands out in front, so the wrist never passes close to the shoulder (a folded arm)
    def front(P0, z):
        Q = Pose(P0)
        for s in ("L", "R"):
            set_arm_ik(Q, s, (0.300, 0.205, z), (0.4, -0.6, 0.6), (-0.4, -1.0, 0.0), w=1.0, pole=-25.0)
        return Q
    K1b = front(add(S0, neck__ry=4.0), 1.44)
    K3b = front(add(S0, neck__ry=2.0), 1.32)
    # hands lowering past the belt, elbows back and slightly out: splits the long drop from the chest to the stand
    K5 = add(S0, neck__ry=3.0, head__ry=2.0, spine__ry=1.0)
    for s in ("L", "R"):
        set_arm_ik(K5, s, (0.190, 0.130, 0.990), (0.3, -0.6, -0.7), (-0.8, -0.5, 0.1), w=1.0, pole=0.0)
        elbow_to(K5, s, (-0.25, 0.8 if s == "L" else -0.8, -0.8), 1.0)
        K5["arm.%s.stiff" % s] = 1.0      # straight wrist on the way down: only the arm swings to the stand
    # the way down is FK: the helmet pose, the front waypoint and the chest pose as FK angles, then the stand pose
    # every key as FK angles converted from its IK design: no IK weight changes anywhere in the clip, so the
    # hold across the cut frame is exactly still and no FK/IK blend can pop
    K1, K1b, K2, K3b, K4, K5 = (ik_to_fk(k) for k in (K1, K1b, K2, K3b, K4, K5))
    K3 = Pose(K2)
    # up: stand -> hands out in front -> helmet sides (hold across the cut); down: helmet -> chest seals -> stand
    return [(0.0, S0, {"hold": True}), (0.47, K1b), (0.80, K2, {"hold": True}), (0.95, K3, {"hold": True}),
            (1.30, K4), (1.595, K5), (1.88, Pose(STAND), {"hold": True})]


def cheer_keys():
    S0 = Pose(STAND)
    C0 = add(S0, hips__z=-0.05, hips__ry=6.0, spine__ry=6.0, chest__ry=4.0, head__ry=4.0)
    C0 = fill_arm_targets(addsym(C0, upper_arm__ry=12.0, forearm__ry=-30.0))
    # both fists up (V), chest open, head up; feet stay on the ground
    UP = add(S0, hips__z=0.0, hips__ry=-2.0, spine__ry=-5.0, chest__ry=-6.0, neck__ry=-8.0, head__ry=-12.0)
    UP = Pose(UP)
    sym(UP, **{"shoulder.rx": 14.0, "upper_arm.rx": 92.0, "upper_arm.ry": -22.0, "upper_arm.rz": 0.0,
               "forearm.ry": -30.0, "forearm.rz": 10.0, "hand.ry": -10.0})
    UP = fill_arm_targets(UP)
    PUMP = Pose(UP)
    sym(PUMP, **{"forearm.ry": -75.0, "upper_arm.rx": 80.0})
    PUMP["hips.z"] = -0.025
    PUMP = fill_arm_targets(PUMP)
    DOWN = fill_arm_targets(addsym(add(S0, hips__z=-0.015, spine__ry=2.0), upper_arm__ry=-6.0, forearm__ry=-10.0))
    return [(0.0, S0, {"hold": True}), (0.30, C0), (0.78, UP), (1.08, PUMP), (1.36, UP), (1.64, PUMP), (1.94, UP),
            (2.50, DOWN), (2.85, Pose(STAND), {"hold": True})]


# --------------------------------------------------------------------------------------
# clip table
# --------------------------------------------------------------------------------------
POSE_STATE_REST = {"stand": ("idle", 0), "sit": ("sit_idle", 0), "lie": ("sleep", 0), "kneel": ("repair_kneel", 0)}


def all_clips():
    """[(name, kind, pose_from, pose_to, loop, frames, fn, extra metadata)] - every clip of section 3.3."""
    out = []

    def gait(name, G, extra=None):
        frames = make_gait(G)
        n = G["frames"]
        speed = G["stride"] / (n / FPS)
        meta = dict(speed_mps=round(speed, 4), stride_m=G["stride"])
        meta.update(extra or {})
        out.append((name, "loop", "stand", "stand", True, n, (lambda fr: (lambda f: fr[f]))(frames), meta))

    fn, n = idle_fn()
    out.append(("idle", "loop", "stand", "stand", True, n, fn, {}))
    fn, n = keyed_clip(idle_look_keys(), loop=True, length=6.0)
    out.append(("idle_look", "loop", "stand", "stand", True, n, fn, {}))
    gait("walk", WALK)
    gait("run", RUN)
    gait("carry_walk", CARRY_WALK, dict(carry=True))
    cb = carry_base()
    out.append(("carry_idle", "loop", "stand", "stand", True, 90,
                periodic(cb, 90, {"chest.ry": lambda u: -1.0 * sin(TAU * u), "spine.ry": lambda u: 0.5 * sin(TAU * u),
                                  "hips.y": lambda u: 0.012 * sin(TAU * u), "hips.rx": lambda u: 1.0 * sin(TAU * u),
                                  "head.rz": lambda u: 6.0 * sin(TAU * u + 0.6),
                                  "arm.L.z": lambda u: 0.006 * sin(2 * TAU * u),
                                  "arm.R.z": lambda u: 0.006 * sin(2 * TAU * u)}), dict(carry=True)))
    out.append(("work_console", "loop", "stand", "stand", True, 120, typing(work_console_base(), 120), {}))
    fn, n = work_bench_fn()
    out.append(("work_bench", "loop", "stand", "stand", True, n, fn, {}))
    fn, n = keyed_clip(talk_keys(), loop=True, length=4.0)
    out.append(("talk", "loop", "stand", "stand", True, n, fn, {}))
    fn, n = keyed_clip(kneel_enter_keys())
    out.append(("kneel_enter", "enter", "stand", "kneel", False, n, fn, {}))
    fn, n = repair_kneel_fn()
    out.append(("repair_kneel", "loop", "kneel", "kneel", True, n, fn, {}))
    fn, n = keyed_clip(kneel_exit_keys())
    out.append(("kneel_exit", "exit", "kneel", "stand", False, n, fn, {}))
    fn, n = keyed_clip(sit_enter_keys())
    out.append(("sit_enter", "enter", "stand", "sit", False, n, fn, {}))
    fn, n = sit_idle_fn()
    out.append(("sit_idle", "loop", "sit", "sit", True, n, fn, {}))
    fn, n = keyed_clip(sit_eat_keys(), loop=True, length=4.0)
    out.append(("sit_eat", "loop", "sit", "sit", True, n, fn, {}))
    out.append(("sit_type", "loop", "sit", "sit", True, 120, typing(sit_type_base(), 120), {}))
    fn, n = keyed_clip(sit_exit_keys())
    out.append(("sit_exit", "exit", "sit", "stand", False, n, fn, {}))
    fn, n = keyed_clip(lie_enter_keys())
    out.append(("lie_enter", "enter", "stand", "lie", False, n, fn, {}))
    fn, n = sleep_fn()
    out.append(("sleep", "loop", "lie", "lie", True, n, fn, {}))
    fn, n = keyed_clip(lie_exit_keys())
    out.append(("lie_exit", "exit", "lie", "stand", False, n, fn, {}))
    gait("injured_walk", INJURED)
    fn, n = keyed_clip(collapse_keys())
    out.append(("collapse", "oneshot", "stand", "lie", False, n, fn, dict(ends_on="dead")))
    out.append(("dead", "hold", "lie", "lie", True, 30, lambda f: Pose(DEAD), {}))
    fn, n = keyed_clip(cheer_keys())
    out.append(("cheer", "oneshot", "stand", "stand", False, n, fn, {}))
    fn, n = keyed_clip(suit_swap_keys())
    out.append(("suit_swap", "oneshot", "stand", "stand", False, n, fn, dict(cut_frame=SWAP_CUT_FRAME)))
    return out
