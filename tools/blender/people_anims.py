"""
Frontier Habitat 5.0 - ART-NPC: clips for the people (V5 section 1).

  * every v3 clip (npc_anims) plus the new v5 clips, baked per variant on that variant's rig;
  * retarget(): a variant is the v3 rig scaled by s (its height / 1.80).  Positions in a pose scale by s; clips that
    rest on the world keep the world heights: seats and beds (the hips are lifted by h (1 - s) as the body settles),
    hands on desks, consoles, benches and panels (their targets are not scaled);
  * face: blinks in every clip (lids), jaw motion in the talking clips;
  * pairs: npc_pairs.json gives the partner offset for paired clips.
Pilot clips: talk_gesture_a, laugh, argue, hug, sit_bar_stool, dance_a.
"""
import os
import sys
import zlib
from math import sin, cos, pi, radians, exp

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
import npc_anims as A                                            # noqa: E402
from npc_anims import (Pose, add, setp, addsym, set_arm_ik, elbow_to, fill_arm_targets, ik_to_fk, keyed_clip,  # noqa
                       periodic, bump, STAND, SIT, TAU, FPS, ANK)
from npc_common import sym, set_foot                             # noqa: E402

# furniture for the new clips (character space, metres; the stool origin is the stool's centre on the floor)
BAR_STOOL = dict(seat_z=0.76, footrest_z=0.30, footrest_r=0.20, counter_x=0.33, counter_z=1.07)
HUG = dict(distance=0.44, facing_deg=180.0, sync_s=0.0)
# hug wrists at the hold (partner at +d): x behind the partner's centre, y outward, z (1.80 m frame)
HUG_ARMS = dict(R=(0.23, 0.260, 1.300), L=(0.21, 0.260, 1.080))
if os.environ.get("NPC_HUG"):                                          # tuning: "d rx ry rz lx ly lz"
    _h = [float(x) for x in os.environ["NPC_HUG"].split()]
    HUG["distance"], HUG_ARMS["R"], HUG_ARMS["L"] = _h[0], tuple(_h[1:4]), tuple(_h[4:7])

# contact rules per clip: (support kind, support height, arms on the world: sides)
CONTACT = {
    "sit_enter": ("seat", 0.46, ()), "sit_idle": ("seat", 0.46, ()), "sit_exit": ("seat", 0.46, ()),
    "sit_eat": ("seat", 0.46, ("L",)), "sit_type": ("seat", 0.46, ("L", "R")),
    "sit_bar_stool": ("seat", BAR_STOOL["seat_z"], (), (BAR_STOOL["seat_z"] + 0.187) - 0.98),
    "lie_enter": ("bed", 0.55, ()), "sleep": ("bed", 0.55, ()), "lie_exit": ("bed", 0.55, ()),
    "work_console": (None, 0.0, ("L", "R")), "work_bench": (None, 0.0, ("L", "R")),
    "repair_kneel": (None, 0.0, ("L", "R")),
}
# the settled hips offset of each support (s = 1), for the blend weight
SETTLED = {"seat": A.SIT.g("hips.z"), "bed": None}

POS_KEYS = ("hips.", "foot.", "arm.", "prop.")


SEAT_DROP = -0.040        # the people pelvis sits 4 cm lower on a chair than the suit / jumpsuit body
LIE_LIFT = 0.014          # and lies 1.4 cm higher on the ground
STOOL_ADJ = 0.0           # the bar-stool hips (per body; the MPFB builds calibrate it, 0 for the procedural pilot)
FOOT_DZ = 0.0             # this body's ankle height above the sole minus the v3 one (x s); MPFB builds set it
KNEEL_ADJ = 0.0           # the kneeling hips (per body; MPFB builds calibrate it)
ARM_IN = 0.0              # deg: standing FK arms closer to the body (MPFB builds: 5)
WORLD_FEET = {"sit_bar_stool"}


def people_fix(P, clip):
    """Contact corrections for the people bodies (s = 1 frame), before the height retarget."""
    Q = Pose(P)
    kind = CONTACT.get(clip, (None,))[0]
    hz = P.g("hips.z")
    if kind == "seat" and clip != "sit_bar_stool":
        w = max(0.0, min(1.0, hz / A.SIT.g("hips.z")))
        Q["hips.z"] = hz + SEAT_DROP * w
        for side in ("L", "R"):
            world = CONTACT.get(clip, (None, 0, ()))[2]
            if side not in world and Q.g("arm.%s.ik" % side) > 0:
                Q["arm.%s.z" % side] = Q.g("arm.%s.z" % side) + SEAT_DROP * w
    if clip in ("kneel_enter", "repair_kneel", "kneel_exit") and KNEEL_ADJ:
        w = max(0.0, min(1.0, hz / A.KNEEL.g("hips.z")))
        Q["hips.z"] = hz + KNEEL_ADJ * w
        for side in ("L", "R"):
            if Q.g("arm.%s.ik" % side) > 0 and side not in CONTACT.get(clip, (None, 0, ()))[2]:
                Q["arm.%s.z" % side] = Q.g("arm.%s.z" % side) + KNEEL_ADJ * w
    if ARM_IN:
        stand = max(0.0, min(1.0, (hz + 0.12) / 0.06))           # standing poses only
        for side, sg in (("L", -1.0), ("R", 1.0)):
            f = stand * (1.0 - max(0.0, min(1.0, Q.g("arm.%s.ik" % side))))
            k = "upper_arm.%s.rx" % side
            Q[k] = Q.g(k) + sg * ARM_IN * f
    if clip == "sit_bar_stool" and STOOL_ADJ:
        Q["hips.z"] = Q.g("hips.z") + STOOL_ADJ
    if clip in ("collapse", "dead", "lie_enter", "sleep", "lie_exit"):
        w = max(0.0, min(1.0, (-hz - 0.55) / 0.25))
        Q["hips.z"] = Q.g("hips.z") + LIE_LIFT * w
        for side in ("L", "R"):                     # the bigger people hands: fingertips clear of the floor
            if Q.g("arm.%s.ik" % side) > 0:
                Q["arm.%s.z" % side] = Q.g("arm.%s.z" % side) + 0.022 * w
    return Q


def retarget(P, s, clip, settled_z=None):
    """The pose for a variant of scale s (and this body's ankle height: FOOT_DZ)."""
    Q = _retarget(P, s, clip, settled_z)
    if FOOT_DZ:
        for side in ("L", "R"):                               # full for a flat foot, fading as it pitches onto the toes
            flat = max(0.0, 1.0 - abs(Q.g("foot.%s.pitch" % side)) / 25.0)
            Q["foot.%s.z" % side] = Q.g("foot.%s.z" % side) + FOOT_DZ * flat
    return Q


def _retarget(P, s, clip, settled_z=None):
    P = people_fix(P, clip)
    if abs(s - 1.0) < 1e-6:
        return P
    spec = CONTACT.get(clip, (None, 0.0, ()))
    kind, h, world = spec[0], spec[1], spec[2]
    if len(spec) > 3 and settled_z is None:
        settled_z = spec[3]
    Q = Pose(P)
    for k, v in P.items():
        parts = k.split(".")
        if parts[-1] not in ("x", "y", "z"):
            continue
        if not k.startswith(POS_KEYS):
            continue
        if k.startswith("arm.") and len(parts) == 3 and parts[1] in world:
            continue                                          # hands on the world stay where the world is
        if k.startswith("foot.") and clip in WORLD_FEET:
            continue                                          # feet on furniture (the stool footrest) stay there
        Q[k] = v * s
    if kind:
        hz = P.g("hips.z")
        ref = settled_z if settled_z is not None else (SETTLED.get(kind) or -0.33)
        w = max(0.0, min(1.0, hz / ref)) if ref < 0 else 0.0
        dz = w * h * (1.0 - s)
        Q["hips.z"] = Q.g("hips.z") + dz
        for side in ("L", "R"):
            if side not in world and Q.g("arm.%s.ik" % side) > 0:
                Q["arm.%s.z" % side] = Q.g("arm.%s.z" % side) + dz
    return Q


# ------------------------------------------------------------------------------------------------------------------
# face overlays
# ------------------------------------------------------------------------------------------------------------------
def blink_times(name, dur, loop):
    """Deterministic blink starts (s) for a clip: every 2.4-4.2 s, clear of the loop seam."""
    h = zlib.crc32(name.encode()) & 0xffff
    t = 0.6 + (h % 100) / 100.0 * 1.2
    out = []
    k = 1
    while t < dur - (0.35 if loop else 0.25):
        out.append(t)
        t += 2.4 + ((h >> (k % 12)) % 18) / 10.0
        k += 1
    return out


def blink_amount(t, starts):
    a = 0.0
    for t0 in starts:
        d = t - t0
        if 0.0 <= d < 0.10:
            x = d / 0.10
            a = max(a, x * x * (3 - 2 * x))
        elif 0.10 <= d < 0.13:
            a = 1.0
        elif 0.13 <= d < 0.29:
            x = (d - 0.13) / 0.16
            a = max(a, 1.0 - x * x * (3 - 2 * x))
    return max(0.0, min(1.0, a))


BLINK_DEG = 50.0
LID_REST = 0.0            # deg: the upper lids a little lower at rest (per body; no fixed stare), MPFB builds set it


def talk_jaw(t, dur, loop, rate=4.4, amp=9.0, seed=1, pause=(0.35, 0.55)):
    """Syllables: jaw open/close pulses with short pauses (periodic over dur for loops)."""
    if loop:
        n = max(1, int(round(rate * dur)))
        f = n / dur
    else:
        f = rate
    ph = 2 * pi * f * t
    env = 0.5 + 0.5 * sin(2 * pi * t / dur * (2 if loop else 1) + seed)
    gate = 1.0 if env > pause[0] else env / pause[0]
    return amp * max(0.0, sin(ph)) ** 1.5 * (0.55 + 0.45 * sin(ph * 0.37 + seed)) * gate


# expressions: weights 0..1 per clip over time (u = t / dur); loops use periodic or constant terms
def _env(u, a=0.12, b=0.12):
    """0 -> 1 -> 0 over a one-shot clip (smooth in over a, out over b)."""
    return max(0.0, min(1.0, u / a, (1.0 - u) / b))


def _bump(u, c, w):
    d = (u - c + 0.5) % 1.0 - 0.5
    x = d / w
    return (1.0 - x * x) ** 2 if abs(x) < 1.0 else 0.0


EXPRESSIONS = {
    # name: fn(u) -> dict(smile, laugh, frown, surprise)
    "idle": lambda u: dict(smile=0.10, surprise=0.35 * _bump(u, 0.55, 0.08)),
    "idle_look": lambda u: dict(surprise=0.45 * _bump(u, 0.30, 0.07) + 0.3 * _bump(u, 0.75, 0.07)),
    "talk": lambda u: dict(smile=0.30 + 0.15 * sin(TAU * u * 2), surprise=0.5 * _bump(u, 0.2, 0.06) + 0.4 * _bump(u, 0.65, 0.06)),
    "talk_gesture_a": lambda u: dict(smile=0.40 + 0.20 * sin(TAU * u), surprise=0.55 * _bump(u, 0.30, 0.07)),
    "laugh": lambda u: dict(laugh=_env(u, 0.18, 0.25)),
    "argue": lambda u: dict(frown=0.85 + 0.15 * sin(TAU * u * 2), surprise=0.0),
    "hug": lambda u: dict(smile=0.9 * _env(u, 0.15, 0.2)),
    "cheer": lambda u: dict(laugh=_env(u, 0.12, 0.25)),
    "dance_a": lambda u: dict(smile=0.65 + 0.15 * sin(TAU * u * 2)),
    "sit_bar_stool": lambda u: dict(smile=0.30 + 0.20 * sin(TAU * u)),
    "sit_eat": lambda u: dict(smile=0.25),
    "work_console": lambda u: dict(frown=0.30), "work_bench": lambda u: dict(frown=0.30),
    "repair_kneel": lambda u: dict(frown=0.35), "sit_type": lambda u: dict(frown=0.20),
    "injured_walk": lambda u: dict(frown=0.80, laugh=0.0), "collapse": lambda u: dict(frown=0.8 * _env(u, 0.1, 0.3)),
}


def expression_pose(P, w):
    """Face bone offsets for expression weights (degrees about world-aligned axes in the head frame).
    mouth.S: pivot inside the cheek, the corner in front: ry < 0 lifts it, rz widens.  brow.S: pivot at the eye:
    ry < 0 raises the brow, rz moves it in.  lids_low: ry < 0 lifts the lower lids.  lids: ry > 0 closes the upper lids."""
    smile = w.get("smile", 0.0) + w.get("laugh", 0.0)
    laugh = w.get("laugh", 0.0)
    frown = w.get("frown", 0.0)
    surprise = w.get("surprise", 0.0)
    for s, sg in (("L", 1.0), ("R", -1.0)):
        P["mouth.%s.ry" % s] = P.g("mouth.%s.ry" % s) - 13.0 * smile + 9.0 * frown
        P["mouth.%s.rz" % s] = P.g("mouth.%s.rz" % s) + sg * (9.0 * smile - 3.0 * frown)
        P["brow.%s.ry" % s] = P.g("brow.%s.ry" % s) + 9.0 * frown - 11.0 * surprise - 3.0 * laugh
        P["brow.%s.rz" % s] = P.g("brow.%s.rz" % s) - sg * 6.0 * frown
    P["lids_low.ry"] = P.g("lids_low.ry") - 5.0 * smile - 3.0 * laugh + 3.0 * surprise
    P["lids.ry"] = P.g("lids.ry") + 10.0 * laugh + 6.0 * frown - 8.0 * surprise
    P["jaw.ry"] = P.g("jaw.ry") + 9.0 * laugh + 4.0 * surprise
    return P


def with_face(fn, name, frames, loop, jaw=None):
    dur = frames / FPS
    starts = blink_times(name, dur, loop)
    expr = EXPRESSIONS.get(name) if "mouth.L" in N.PARENT else None

    def g(f):
        P = Pose(fn(f))
        t = f / FPS
        P["lids.ry"] = P.g("lids.ry") + LID_REST + (BLINK_DEG - LID_REST) * blink_amount(t, starts)
        if jaw:
            P["jaw.ry"] = P.g("jaw.ry") + jaw(t, dur)
        if expr:
            expression_pose(P, expr(t / dur if dur > 0 else 0.0))
        return P
    return g


# ------------------------------------------------------------------------------------------------------------------
# new clips
# ------------------------------------------------------------------------------------------------------------------
def talk_gesture_a_keys():
    """Explaining: weight on the left leg, the right hand opens palm-up in front and sweeps out, a nod, the left hand
    joins once; loops in 4 s."""
    S = add(STAND, hips__y=0.018, hips__rx=-1.5, spine__rx=1.0, spine__ry=3.0, neck__ry=2.0, head__ry=1.0)
    set_foot(S, "R", (ANK.x + 0.03, 0.135, ANK.z), yaw=12.0, knee_out=6.0)
    S = fill_arm_targets(S)
    A1 = Pose(S)
    set_arm_ik(A1, "R", (0.265, 0.085, 1.150), (0.9, 0.1, 0.25), (0.0, 0.3, 1.0), w=1.0, pole=-20.0)
    A1.update({"head.ry": 4.0, "neck.rz": -4.0, "head.rz": -5.0})
    A2 = Pose(S)
    set_arm_ik(A2, "R", (0.235, 0.215, 1.180), (0.6, -0.6, 0.3), (0.0, 0.2, 1.0), w=1.0, pole=-10.0)
    A2.update({"head.ry": -2.0, "neck.rz": -7.0, "head.rz": -8.0, "chest.rz": -4.0})
    A3 = Pose(S)
    set_arm_ik(A3, "R", (0.270, 0.050, 1.220), (1.0, 0.2, 0.1), (0.0, 0.5, 1.0), w=1.0, pole=-25.0)
    set_arm_ik(A3, "L", (0.230, 0.120, 1.120), (0.9, -0.2, 0.2), (0.0, -0.3, 1.0), w=1.0, pole=-20.0)
    A3.update({"head.ry": 6.0, "neck.ry": 4.0, "head.rz": 2.0})
    A4 = Pose(S)
    set_arm_ik(A4, "R", (0.200, 0.160, 1.080), (0.8, 0.0, -0.3), (0.0, 0.4, 0.9), w=1.0, pole=-10.0)
    A4.update({"head.ry": 0.0, "head.rz": 4.0, "neck.rz": 3.0})
    keys = [S, A1, A2, A1, A3, A4, S]
    keys = [ik_to_fk(k) for k in keys]
    times = [0.0, 0.55, 1.15, 1.70, 2.40, 3.20, 4.0]
    return [(t, k) for t, k in zip(times, keys)]


def laugh_keys():
    """A hearty laugh: head back, shoulders shake, a hand to the belly; 2.4 s from stand to stand."""
    S = Pose(STAND)
    K1 = add(S, spine__ry=-3.0, chest__ry=-4.0, neck__ry=-8.0, head__ry=-12.0, hips__z=-0.01)
    set_arm_ik(K1, "L", (0.150, 0.100, 1.060), (0.2, -1.0, -0.2), (-1.0, 0.0, 0.0), w=1.0, pole=10.0)
    set_arm_ik(K1, "R", (0.180, -0.050, 1.300), (0.3, -1.0, 0.3), (-0.9, 0.0, 0.3), w=1.0, pole=-10.0)
    K2 = add(K1, spine__ry=10.0, chest__ry=6.0, neck__ry=12.0, head__ry=14.0, hips__z=-0.02)
    set_arm_ik(K2, "L", (0.160, 0.090, 1.020), (0.2, -1.0, -0.3), (-1.0, 0.0, 0.0), w=1.0, pole=10.0)
    K3 = add(K1, spine__ry=-2.0, neck__ry=-4.0, head__ry=-6.0)
    keys = [(0.0, S, {"hold": True}), (0.58, K1), (1.15, K2), (1.70, K3), (2.30, Pose(STAND), {"hold": True})]
    return [(t, ik_to_fk(k), *rest) for (t, k, *rest) in keys]


def laugh_fn():
    keys = laugh_keys()
    fn, n = keyed_clip(keys)

    def g(f):
        P = Pose(fn(f))
        t = f / FPS
        env = sin(pi * min(1.0, max(0.0, (t - 0.3) / 1.8))) ** 1.5
        shake = sin(2 * pi * 5.2 * t)
        P["chest.ry"] = P.g("chest.ry") + 2.2 * env * shake
        for s in ("L", "R"):
            P["shoulder.%s.rx" % s] = P.g("shoulder.%s.rx" % s) + (-1 if s == "L" else 1) * 3.0 * env * shake
        P["head.ry"] = P.g("head.ry") + 2.0 * env * sin(2 * pi * 5.2 * t + 0.6)
        P["jaw.ry"] = P.g("jaw.ry") + env * (7.0 + 3.0 * max(0.0, shake))
        return P
    return g, n


def argue_keys():
    """Arguing (CRITIC round 40: distinct from talk): a step in, the chin forward, the right hand jabs twice at the
    partner's chest, then both arms flung open ("what?"), a chop of the left hand; the weight stays forward.  3 s loop."""
    S = add(STAND, hips__x=0.030, hips__ry=3.0, spine__ry=8.0, chest__ry=4.0, neck__ry=9.0, head__ry=-7.0)
    set_foot(S, "L", (ANK.x + 0.11, 0.120, ANK.z), yaw=4.0, knee_out=4.0)
    set_foot(S, "R", (ANK.x - 0.05, 0.125, ANK.z), yaw=10.0, knee_out=3.0)
    S = fill_arm_targets(S)
    J1 = Pose(S)
    set_arm_ik(J1, "R", (0.400, 0.070, 1.250), (1.0, 0.05, 0.05), (0.0, 0.3, -1.0), w=1.0, pole=-30.0)
    set_arm_ik(J1, "L", (0.140, 0.230, 1.020), (0.6, -0.4, -0.6), (0.0, 0.2, -1.0), w=1.0, pole=10.0)
    J1.update({"chest.rz": -9.0, "spine.rz": -4.0, "neck.ry": 13.0, "head.ry": -9.0, "hips.x": 0.045})
    B1 = Pose(J1)
    set_arm_ik(B1, "R", (0.255, 0.110, 1.200), (0.9, -0.1, 0.3), (0.0, 0.4, -1.0), w=1.0, pole=-25.0)
    B1.update({"chest.rz": -4.0, "neck.ry": 10.0})
    J2 = Pose(J1)
    set_arm_ik(J2, "R", (0.430, 0.060, 1.280), (1.0, 0.0, 0.10), (0.0, 0.3, -1.0), w=1.0, pole=-30.0)
    J2.update({"chest.rz": -11.0, "spine.ry": 10.0, "neck.ry": 15.0, "head.ry": -11.0, "hips.x": 0.050})
    OPEN = add(S, hips__x=-0.01, spine__ry=-2.0, chest__ry=-5.0, neck__ry=2.0, head__ry=-4.0, head__rz=6.0)
    for sd in ("L", "R"):
        set_arm_ik(OPEN, sd, (0.230, 0.360, 1.180), (0.4, 1.0, 0.3), (0.0, -0.8, 0.6), w=1.0, pole=-20.0)
        OPEN["shoulder.%s.ry" % sd] = -6.0
    CHOP = Pose(S)
    set_arm_ik(CHOP, "L", (0.360, 0.120, 1.130), (0.9, -0.2, -0.5), (0.0, -1.0, 0.0), w=1.0, pole=-25.0)
    set_arm_ik(CHOP, "R", (0.180, 0.290, 1.030), (0.5, 0.3, -0.8), (0.0, -1.0, 0.0), w=1.0, pole=-10.0)
    CHOP.update({"chest.rz": 7.0, "neck.ry": 12.0, "head.ry": -8.0, "head.rz": -4.0, "hips.x": 0.045})
    keys = [S, J1, B1, J2, OPEN, CHOP, S]
    keys = [ik_to_fk(k) for k in keys]
    return [(t, k) for t, k in zip((0.0, 0.62, 0.90, 1.16, 1.95, 2.48, 3.0), keys)]


def hug_keys():
    """Paired, the same clip for both partners (npc_pairs.json: facing, HUG distance): the right arm high over the
    partner's left shoulder, the left arm round the waist, the head to the left; 3.2 s from stand to stand."""
    d = HUG["distance"]
    S = Pose(STAND)
    K1 = add(S, spine__ry=2.0, chest__ry=2.0, neck__ry=2.0, spine__rx=-4.0, neck__rz=10.0, head__rz=22.0)   # heads aside
    set_arm_ik(K1, "R", (0.230, 0.300, 1.250), (0.8, -0.5, 0.1), (-0.6, -0.8, 0.0), w=1.0, pole=-40.0)
    set_arm_ik(K1, "L", (0.220, 0.300, 1.100), (0.8, -0.5, 0.0), (-0.6, -0.8, 0.0), w=1.0, pole=-30.0)
    K2 = add(S, hips__x=-0.04, spine__ry=7.0, chest__ry=7.0, neck__ry=0.0, head__ry=2.0, spine__rx=-6.0,
             chest__rx=-2.0, neck__rz=14.0, head__rz=30.0, head__rx=-8.0)
    # hips back, chests in, lean to the own left: the heads pass side by side
    hr, hl = HUG_ARMS["R"], HUG_ARMS["L"]
    set_arm_ik(K2, "R", (d + hr[0], hr[1], hr[2]), (0.3, -1.0, -0.15), (-1.0, 0.0, 0.0), w=1.0, pole=-60.0)
    elbow_to(K2, "R", (0.05, -1.0, 0.05), 0.95)
    set_arm_ik(K2, "L", (d + hl[0], hl[1], hl[2]), (0.3, -1.0, 0.0), (-1.0, 0.0, 0.0), w=1.0, pole=-50.0)
    elbow_to(K2, "L", (0.05, 1.0, -0.15), 0.95)
    K3 = add(K2, hips__y=0.01, chest__rz=4.0, head__rz=4.0)
    # the hands go round the partner's sides on the way in and out (not through them)
    KM = add(S, spine__ry=2.5, chest__ry=2.5, neck__ry=3.0, spine__rx=-5.0, neck__rz=12.0, head__rz=26.0)
    set_arm_ik(KM, "R", (d + 0.04, 0.42, 1.30), (0.6, -0.8, 0.0), (-0.6, -0.8, 0.0), w=1.0, pole=-50.0)
    elbow_to(KM, "R", (0.0, -1.0, 0.0), 0.7)
    set_arm_ik(KM, "L", (d + 0.03, 0.40, 1.08), (0.6, -0.8, 0.0), (-0.6, -0.8, 0.0), w=1.0, pole=-40.0)
    elbow_to(KM, "L", (0.0, 1.0, -0.2), 0.7)
    keys = [(0.0, S, {"hold": True}), (0.75, KM), (1.20, K2), (1.65, K3), (2.05, K2), (2.50, KM),
            (3.30, Pose(STAND), {"hold": True})]
    return [(t, ik_to_fk(k), *rest) for (t, k, *rest) in keys]


def sit_bar_stool_base():
    """On a bar stool (BAR_STOOL): hips over the stool centre, the right foot on the footrest, the left lower on the
    ring, forearms on the counter."""
    B = BAR_STOOL
    P = Pose()
    P["hips.x"] = -0.040
    P["hips.z"] = (B["seat_z"] + 0.187) - 0.98                       # the pelvis, tilted on the stool, rests 0.187 m up
    P["hips.ry"] = -4.0
    P["spine.ry"] = 9.0
    P["chest.ry"] = 3.0
    P["neck.ry"] = -2.0
    P["head.ry"] = -3.0
    set_foot(P, "L", (0.130, 0.130, B["footrest_z"] + ANK.z + 0.012), pitch=-8.0, yaw=10.0, knee_out=8.0)
    set_foot(P, "R", (0.175, 0.095, B["footrest_z"] + ANK.z + 0.012 - 0.06), pitch=10.0, yaw=16.0, knee_out=10.0)
    for s, (x, y) in (("L", (0.300, 0.150)), ("R", (0.310, 0.060))):
        set_arm_ik(P, s, (x, y, B["counter_z"] + 0.030), (0.8, -0.35, -0.10), (0.0, 0.2, -1.0), w=1.0, pole=-40.0)
        P["arm.%s.stiff" % s] = 1.0
    return P


def sit_bar_stool_fn(n=150):
    base = sit_bar_stool_base()

    def fn(f):
        u = f / n

        def w(g):
            return g(u) - g(0.0)
        P = add(base,
                chest__ry=w(lambda u: 1.0 * sin(TAU * u)),
                spine__ry=w(lambda u: -0.5 * sin(TAU * u)),
                head__rz=w(lambda u: 14.0 * sin(TAU * u + 0.4) + 4.0 * sin(2 * TAU * u)),
                head__ry=w(lambda u: 3.0 * sin(2 * TAU * u + 1.0)),
                neck__rz=w(lambda u: 4.0 * sin(TAU * u + 0.4)))
        b = bump(u, 0.55, 0.10)
        P["arm.R.z"] = P.g("arm.R.z") + 0.07 * b
        P["arm.R.x"] = P.g("arm.R.x") - 0.03 * b
        return P
    return fn, n


def dance_a_fn(n=120):
    """120 bpm club groove, 8 beats in 4 s (CRITIC round 40: a real dance): a knee bounce on every beat, a side step
    and touch each 2 beats with the hips swinging over the standing leg, the chest twisting against the hips, arms
    bent and pumping in turn, beats 7-8 both arms up and back down; the head nods on the beat."""
    base = fill_arm_targets(add(STAND, hips__z=-0.035))
    for s in ("L", "R"):
        base["arm.%s.ik" % s] = 0.0
    sym(base, **{"upper_arm.rx": -22.0, "upper_arm.ry": 8.0, "forearm.ry": -82.0, "forearm.rx": 4.0,
                 "hand.ry": -4.0})
    base = fill_arm_targets(base)

    def fn(f):
        t = f / n                                   # 0..1 over 8 beats
        beat = t * 8.0
        bounce = 0.5 - 0.5 * cos(TAU * beat)        # 0 on the beat, 1 between: the knees give on each beat
        side = sin(TAU * t * 2)                     # a full side-to-side in 4 beats
        P = Pose(base)
        P["hips.y"] = 0.070 * side
        P["hips.z"] = base.g("hips.z") - 0.045 * (1.0 - bounce)
        P["hips.rx"] = -6.5 * side
        P["hips.rz"] = 8.0 * sin(TAU * t * 2 + 0.5)
        P["hips.ry"] = 4.0 + 2.0 * (1.0 - bounce)
        P["spine.rx"] = 3.0 * side
        P["chest.rx"] = 3.5 * side
        P["spine.rz"] = -5.0 * sin(TAU * t * 2 + 0.5)
        P["chest.rz"] = -7.0 * sin(TAU * t * 2 + 0.6)
        P["neck.ry"] = 4.0 * (1.0 - bounce)
        P["head.ry"] = -3.0 + 6.0 * (1.0 - bounce)
        P["head.rx"] = -4.0 * side
        for s, sg in (("L", 1.0), ("R", -1.0)):
            stance = max(0.0, sg * side)
            lift = max(0.0, -sg * side) ** 1.5
            y = 0.140 + 0.080 * lift
            z = ANK.z + 0.050 * sin(pi * lift)
            set_foot(P, s, (ANK.x + 0.02 * lift, y, z), yaw=8.0, knee_out=5.0 + 8.0 * lift, pitch=-18.0 * lift,
                     toe=12.0 * lift)
        # arms: alternating pumps (2 beats), both up on beats 6.5-8
        up = max(0.0, min(1.0, (beat - 5.7) / 1.15)) * max(0.0, min(1.0, (8.0 - beat) / 1.15))
        up = up * up * (3 - 2 * up)
        for s, sg in (("L", 1.0), ("R", -1.0)):
            ph = TAU * beat / 2 + (0.0 if s == "L" else pi)
            P["upper_arm.%s.ry" % s] = base.g("upper_arm.%s.ry" % s) - 26.0 * sin(ph) * (1 - up) + 70.0 * up
            P["upper_arm.%s.rx" % s] = base.g("upper_arm.%s.rx" % s) + sg * 10.0 * up
            P["forearm.%s.ry" % s] = base.g("forearm.%s.ry" % s) - 16.0 * sin(ph + 0.6) * (1 - up) + 30.0 * up
            P["shoulder.%s.rx" % s] = -3.0 * sg * (1.0 - bounce) + sg * 6.0 * up
        return P
    return fn, n


# ------------------------------------------------------------------------------------------------------------------
PILOT_NEW = ["talk_gesture_a", "laugh", "argue", "hug", "sit_bar_stool", "dance_a"]
V3_CLIPS = ["idle", "idle_look", "walk", "run", "carry_walk", "carry_idle", "work_console", "work_bench", "talk",
            "kneel_enter", "repair_kneel", "kneel_exit", "sit_enter", "sit_idle", "sit_eat", "sit_type", "sit_exit",
            "lie_enter", "sleep", "lie_exit", "injured_walk", "collapse", "dead", "cheer"]


def people_clips():
    """[(name, kind, from, to, loop, frames, fn, meta)] on the v3 rig (s = 1): the v3 clips, the new clips, with the
    face overlays."""
    base = {c[0]: c for c in A.all_clips()}
    out = []
    talking = {"talk": dict(rate=4.2, amp=4.5), "talk_gesture_a": dict(rate=4.4, amp=5.0),
               "argue": dict(rate=5.2, amp=7.0, pause=(0.25, 0.4))}
    for name in V3_CLIPS:
        c = base[name]
        jaw = None
        if name in talking:
            kw = talking[name]
            jaw = (lambda t, dur, loop=c[4], kw=kw: talk_jaw(t, dur, loop, **kw))
        fn = with_face(c[6], name, c[5], c[4], jaw)
        out.append((c[0], c[1], c[2], c[3], c[4], c[5], fn, dict(c[7])))
    fn, n = keyed_clip(talk_gesture_a_keys(), loop=True, length=4.0)
    kw = talking["talk_gesture_a"]
    out.append(("talk_gesture_a", "loop", "stand", "stand", True, n,
                with_face(fn, "talk_gesture_a", n, True, lambda t, d, kw=kw: talk_jaw(t, d, True, **kw)), {}))
    fn, n = laugh_fn()
    out.append(("laugh", "oneshot", "stand", "stand", False, n, with_face(fn, "laugh", n, False), {}))
    fn, n = keyed_clip(argue_keys(), loop=True, length=3.0)
    kw = talking["argue"]
    out.append(("argue", "loop", "stand", "stand", True, n,
                with_face(fn, "argue", n, True, lambda t, d, kw=kw: talk_jaw(t, d, True, **kw)), {}))
    fn, n = keyed_clip(hug_keys())
    out.append(("hug", "oneshot", "stand", "stand", False, n, with_face(fn, "hug", n, False),
                dict(pair="hug")))
    fn, n = sit_bar_stool_fn()
    out.append(("sit_bar_stool", "loop", "stool", "stool", True, n, with_face(fn, "sit_bar_stool", n, True),
                dict(furniture="bar_stool")))
    fn, n = dance_a_fn()
    out.append(("dance_a", "loop", "stand", "stand", True, n, with_face(fn, "dance_a", n, True), dict(bpm=120)))
    return out


def pairs_json():
    return {
        "note": ("Paired clips: both partners play the clip with the same start time (sync_s); partner B stands at "
                 "distance_m along partner A's forward axis and faces A (facing_deg 180).  Distances are for two "
                 "1.80 m people; scale by the mean of the two variant scales."),
        "pairs": {
            "hug": dict(clip_a="hug", clip_b="hug", distance_m=HUG["distance"], facing_deg=HUG["facing_deg"],
                        sync_s=HUG["sync_s"], side_offset_m=0.0),
        },
    }
