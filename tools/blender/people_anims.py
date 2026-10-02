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
from mathutils import Vector, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
import npc_anims as A                                            # noqa: E402
from npc_anims import (relax_wrists, Pose, add, setp, addsym, set_arm_ik, elbow_to, fill_arm_targets, ik_to_fk, keyed_clip,  # noqa
                       periodic, bump, STAND, SIT, TAU, FPS, ANK)
from npc_common import sym, set_foot                             # noqa: E402

# furniture for the new clips (character space, metres; the stool origin is the stool's centre on the floor)
BAR_STOOL = dict(seat_z=0.76, footrest_z=0.30, footrest_r=0.20, counter_x=0.33, counter_z=1.07)
HUG = dict(distance=0.48, facing_deg=180.0, sync_s=0.0)      # (2026-10-02: 0.44 -> 0.48: the arms were 2-3 cm deep in the partner)
# hug wrists at the hold (partner at +d): x behind the partner's centre, y outward, z (1.80 m frame)
HUG_ARMS = dict(R=(0.20, 0.290, 1.370), L=(0.19, 0.285, 1.060))   # (2026-10-02: 3 cm less round the partner: B's hand reached A's spine)
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
    # v5 planned clips (people_clips.py)
    "sit_bench": ("seat", 0.45, ()), "sit_class": ("seat", 0.46, ("L", "R")),
    "drink_bar": ("seat", BAR_STOOL["seat_z"], (), (BAR_STOOL["seat_z"] + 0.187) - 0.98),
    "lounge_pool": ("seat", 0.35, (), (0.35 + 0.115) - 0.98),
    "sleep_cell": ("bed", 0.45, ()), "lie_enter_r": ("bed", 0.55, ()), "sleep_r": ("bed", 0.55, ()),
    "lie_exit_r": ("bed", 0.55, ()), "sleep_turn": ("bed", 0.55, ()), "drive_sit": ("seat", 0.46, ("L", "R")),
    "play_arcade": (None, 0.0, ("L", "R")), "shop_browse": (None, 0.0, ("R",)),
    # enter / exit clips of the stool, bunk and lounger states (2026-10-03)
    "stool_enter": ("seat", BAR_STOOL["seat_z"], (), (BAR_STOOL["seat_z"] + 0.187) - 0.98),
    "stool_exit": ("seat", BAR_STOOL["seat_z"], (), (BAR_STOOL["seat_z"] + 0.187) - 0.98),
    "bunk_enter": ("bed", 0.45, ()), "bunk_exit": ("bed", 0.45, ()),
    "lounger_enter": ("seat", 0.35, (), (0.35 + 0.115) - 0.98), "lounger_exit": ("seat", 0.35, (), (0.35 + 0.115) - 0.98),
}
STOOL_TRANS = ("stool_enter", "stool_exit")    # stand <-> stool: the stool offsets fade in with the seated weight
LIE_CLIPS = ("collapse", "dead", "fall_down", "get_up")                 # on the ground: LIE_LIFT
BED_CLIPS = ("lie_enter", "sleep", "lie_exit", "sleep_cell", "lie_enter_r", "sleep_r", "lie_exit_r", "sleep_turn",
             "bunk_enter", "bunk_exit")
STOOL_CLIPS = ("sit_bar_stool", "drink_bar")
# the settled hips offset of each support (s = 1), for the blend weight
SETTLED = {"seat": A.SIT.g("hips.z"), "bed": -0.20}    # (2026-10-02: bed -0.20: seated on the edge = settled; children sank 4 cm)

POS_KEYS = ("hips.", "foot.", "arm.", "prop.")


SEAT_DROP = -0.040        # the people pelvis sits 4 cm lower on a chair than the suit / jumpsuit body
LIE_LIFT = 0.014          # and lies 1.4 cm higher on the ground
STOOL_ADJ = 0.0           # the bar-stool hips (per body; the MPFB builds calibrate it, 0 for the procedural pilot)
FOOT_DZ = 0.0             # this body's ankle height above the sole minus the v3 one (x s); MPFB builds set it
COLLAPSE_ADJ = 0.0        # the kneeling part of collapse (per body, calibrated)
SOLE_DZ = 0.0             # the outfits' common sole thickness (calibrated: the lowest sole on the floor in idle)
KNEEL_ADJ = 0.0           # the kneeling hips (per body; MPFB builds calibrate it)
BED_ADJ = 0.0             # the lying hips on a bed (per body; MPFB builds calibrate it: torso on the mattress)
BED_BACK = 0.0            # the same lying on the back (sleep_turn; per body, calibrated)
BED_ROLL = 0.0            # and half way through the roll (sleep_turn; per body, calibrated)
ARM_IN = 0.0              # deg: standing FK arms closer to the body (MPFB builds: 5)
WORLD_FEET = {"sit_bar_stool", "drink_bar"}
LOCO_CLIPS = {"walk", "run", "carry_walk", "injured_walk", "jog", "child_run", "hold_hands_walk", "hold_hands_walk_r",
              "handcuffed_walk", "escort_walk"}


def people_fix(P, clip):
    """Contact corrections for the people bodies (s = 1 frame), before the height retarget."""
    Q = Pose(P)
    kind = CONTACT.get(clip, (None,))[0]
    hz = P.g("hips.z")
    if kind == "seat" and clip not in STOOL_CLIPS:
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
    if ARM_IN and clip not in LOCO_CLIPS and not P.g("scap.off"):
        stand = max(0.0, min(1.0, (hz + 0.12) / 0.06))           # standing poses only (gaits set their own)
        for side, sg in (("L", -1.0), ("R", 1.0)):
            f = stand * (1.0 - max(0.0, min(1.0, Q.g("arm.%s.ik" % side))))
            k = "upper_arm.%s.rx" % side
            Q[k] = Q.g(k) + sg * ARM_IN * f
            # IK arms that hang (wrist well below the shoulder): the wrist turns in about the shoulder by the same
            # angle, so IK clips match the FK idle at their ends
            wi = stand * max(0.0, min(1.0, Q.g("arm.%s.ik" % side)))
            if wi > 0:
                sh = N.SH_JOINT if side == "L" else Vector((N.SH_JOINT.x, -N.SH_JOINT.y, N.SH_JOINT.z))
                t = Vector((Q.g("arm.%s.x" % side), Q.g("arm.%s.y" % side), Q.g("arm.%s.z" % side)))
                low = max(0.0, min(1.0, (sh.z - 0.25 - t.z) / 0.15))
                if low > 0:
                    r = Quaternion((1.0, 0.0, 0.0), radians(sg * ARM_IN * wi * low)) @ (t - sh) + sh
                    Q["arm.%s.x" % side], Q["arm.%s.y" % side], Q["arm.%s.z" % side] = r.x, r.y, r.z
    if clip in STOOL_CLIPS and STOOL_ADJ:
        Q["hips.z"] = Q.g("hips.z") + STOOL_ADJ
    if clip in STOOL_TRANS and STOOL_ADJ:
        st = A.STAND.g("hips.x")
        w = max(0.0, min(1.0, (st - P.g("hips.x")) / 0.04))          # 0 standing (x 0) .. 1 on the stool (x -0.04)
        Q["hips.z"] = Q.g("hips.z") + STOOL_ADJ * w
    if clip in BED_CLIPS and (BED_ADJ or BED_BACK or BED_ROLL):       # on the mattress: the body rests ON it (per body)
        # (2026-10-02) on the side and on the back the lowest points differ (hip and thigh vs the back and heels): one
        # offset each, mixed by how far the pelvis lies on its side (its lateral axis up) or on its back (forward up)
        qh = N.qeuler(P.g("hips.rx"), P.g("hips.ry"), P.g("hips.rz"))
        ws = (qh @ Vector((0.0, 1.0, 0.0))).z ** 2
        wb = (qh @ Vector((1.0, 0.0, 0.0))).z ** 2
        dz = BED_ADJ * ws + BED_BACK * wb + BED_ROLL * 4.0 * ws * wb     # (mid-roll: its own offset)
        Q["hips.z"] = Q.g("hips.z") + dz
        # the whole body moves with the hips (2026-10-02: only the hips moved, so the feet and hands hung below the
        # mattress, 15 cm on the children)
        for side in ("L", "R"):
            Q["foot.%s.z" % side] = Q.g("foot.%s.z" % side) + dz
            if Q.g("arm.%s.ik" % side) > 0:
                Q["arm.%s.z" % side] = Q.g("arm.%s.z" % side) + dz
    if clip == "collapse" and COLLAPSE_ADJ:
        # the kneeling middle of the fall, per body (m3's knee went 1.2 cm into the floor); none at the ends
        w = max(0.0, min(1.0, (-hz - 0.25) / 0.25)) * max(0.0, min(1.0, (0.75 + hz) / 0.15))
        Q["hips.z"] = Q.g("hips.z") + COLLAPSE_ADJ * w
    if clip in LIE_CLIPS:
        # (2026-10-02) from the kneel down (m3's knee went 1.3 cm into the floor in collapse); the hands are kept on the
        # floor by the solver's surface guard now (the old +2.2 cm on IK hands only made get_up start 1.3 cm off dead)
        w = max(0.0, min(1.0, (-hz - 0.25) / 0.45))
        Q["hips.z"] = Q.g("hips.z") + LIE_LIFT * w
        # (2026-10-03) the lying legs rise with the body: their ankle targets are absolute, so the lowest shin (m3,
        # 1.2 cm under the floor in dead) stayed down while the hips rose
        for side in ("L", "R"):
            Q["foot.%s.z" % side] = Q.g("foot.%s.z" % side) + LIE_LIFT * w * max(0.0, min(1.0, Q.g("foot.%s.rel" % side)))
    return Q


def retarget(P, s, clip, settled_z=None):
    """The pose for a variant of scale s (and this body's ankle height: FOOT_DZ)."""
    Q = _retarget(P, s, clip, settled_z)
    if clip in LIE_CLIPS:                                     # the same guard on the floor (2026-10-02)
        Q["bed.on"], Q["bed.z"], Q["bed.x0"], Q["bed.x1"] = 1.0, 0.0, -9.0, 9.0
    if clip in BED_CLIPS:                                     # the bed guard (npc_common Solver._bed_guard)
        Q["bed.z"] = CONTACT[clip][1]
        Q["bed.x0"], Q["bed.x1"] = -A.FURNITURE["bed_back"] - 0.45, -A.FURNITURE["bed_back"] + 0.45
    if FOOT_DZ or SOLE_DZ:
        for side in ("L", "R"):
            if Q.g("foot.%s.rel" % side) > 0.5:               # feet off the ground (lying): as before
                flat = max(0.0, 1.0 - abs(Q.g("foot.%s.pitch" % side)) / 25.0)
                Q["foot.%s.z" % side] = Q.g("foot.%s.z" % side) + FOOT_DZ * flat + SOLE_DZ
                continue
            # (2026-10-02) the ankle-height difference moves the ankle along the FOOT's up axis (a rigid offset in the
            # foot): the old fade with pitch left a foot on its toes 2.5 cm up in the kneel clips and slid planted toes
            up = N.qeuler(Q.g("foot.%s.roll" % side), Q.g("foot.%s.pitch" % side), Q.g("foot.%s.yaw" % side)) @                 Vector((0.0, 0.0, 1.0))
            Q["foot.%s.x" % side] = Q.g("foot.%s.x" % side) + FOOT_DZ * up.x
            Q["foot.%s.y" % side] = Q.g("foot.%s.y" % side) + FOOT_DZ * up.y
            Q["foot.%s.z" % side] = Q.g("foot.%s.z" % side) + FOOT_DZ * up.z + SOLE_DZ
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
        if k.startswith("foot.") and clip in STOOL_TRANS:
            # (2026-10-03) a foot on the stool's ring / footrest stays there; a foot on the floor scales like the stand
            sd = parts[1]
            u = max(0.0, min(1.0, (P.g("foot.%s.z" % sd) - 0.15) / 0.15))
            Q[k] = v * (s + (1.0 - s) * u)
            continue
        Q[k] = v * s
    if kind:
        hz = P.g("hips.z")
        ref = settled_z if settled_z is not None else (SETTLED.get(kind) or -0.33)
        st = A.STAND.g("hips.z")
        # (2026-10-02: measured from the standing hips, so a clip that starts standing starts exactly on idle)
        w = max(0.0, min(1.0, (hz - st) / (ref - st))) if ref < st else 0.0
        dz = w * h * (1.0 - s)
        Q["hips.z"] = Q.g("hips.z") + dz
        if kind == "bed":
            # (2026-10-02, c2 sat with her seat in the bed frame: x scaled about the stand point put a child 11 cm
            # from the mattress edge) on the bed, x scales about the mattress front edge when seated and about its
            # centre line when lying
            qh = N.qeuler(P.g("hips.rx"), P.g("hips.ry"), P.g("hips.rz"))
            lie = min(1.0, (qh @ Vector((0.0, 1.0, 0.0))).z ** 2 + (qh @ Vector((1.0, 0.0, 0.0))).z ** 2)
            bb = A.FURNITURE["bed_back"]
            # seated: about a point 12 cm in front of the stand point, so a small body sits a little forward and its
            # legs stay clear of the bed front (c2's legs and dress went 4 cm into the plinth under the mattress edge)
            x0 = 0.20 * (1.0 - lie) + (-bb) * lie
            dx = w * x0 * (1.0 - s)
            Q["hips.x"] = Q.g("hips.x") + dx
            for side in ("L", "R"):
                Q["foot.%s.x" % side] = Q.g("foot.%s.x" % side) + dx * max(0.0, min(1.0, (P.g("foot.%s.z" % side) - 0.15) / 0.15))
                if side not in world and Q.g("arm.%s.ik" % side) > 0:
                    Q["arm.%s.x" % side] = Q.g("arm.%s.x" % side) + dx
        if kind == "seat" and s < 0.85:                     # children: the feet dangle (they cannot reach the floor)
            for side in ("L", "R"):
                Q["foot.%s.z" % side] = Q.g("foot.%s.z" % side) + dz * 0.8
        if kind == "bed":                                   # the feet scale about the mattress top like the hips (children)
            for side in ("L", "R"):
                # (2026-10-02: not the feet still on the floor, while sitting on the bed edge: m3's toes went 1.9 cm
                # under the floor)
                up = max(0.0, min(1.0, (P.g("foot.%s.z" % side) - 0.15) / 0.15))
                if s < 0.85:
                    # children hop up onto the mattress: their crotch is not above it, so with the feet on the floor
                    # the legs stood straight and the body leaned into the bed front (2026-10-02, c2); the feet leave
                    # the floor as they sit and hang from the edge
                    up = max(up, w)
                Q["foot.%s.z" % side] = Q.g("foot.%s.z" % side) + dz * up
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
EYES_CLOSED = {"sleep", "sleep_r", "sleep_cell", "sleep_turn", "dead"}
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
    # v5 planned clips
    "talk_idle": lambda u: dict(smile=0.25 + 0.10 * sin(TAU * u)),
    "talk_gesture_b": lambda u: dict(smile=0.30, surprise=0.5 * _bump(u, 0.55, 0.08)),
    "listen_nod": lambda u: dict(smile=0.20 + 0.15 * (_bump(u, 0.2, 0.05) + _bump(u, 0.5, 0.05) + _bump(u, 0.8, 0.05))),
    "shout": lambda u: dict(frown=_env(u, 0.12, 0.25)),
    "sulk": lambda u: dict(frown=0.55),
    "wave": lambda u: dict(smile=0.8 * _env(u, 0.15, 0.2)),
    "handshake": lambda u: dict(smile=0.6 * _env(u, 0.2, 0.2)),
    "kiss_brief": lambda u: dict(smile=0.5 * _env(u, 0.15, 0.15)),
    "hold_hands_walk": lambda u: dict(smile=0.55), "hold_hands_walk_r": lambda u: dict(smile=0.55),
    "flirt_lean": lambda u: dict(smile=0.55 + 0.15 * sin(TAU * u), laugh=0.6 * _bump(u, 0.62, 0.06)),
    "slap": lambda u: dict(frown=_env(u, 0.1, 0.3)), "punch": lambda u: dict(frown=_env(u, 0.1, 0.3)),
    "hit_react": lambda u: dict(surprise=0.8 * _bump(u, 0.35, 0.12), frown=0.6 * _env(u, 0.35, 0.3)),
    "fall_down": lambda u: dict(surprise=0.7 * _env(u, 0.1, 0.5)), "get_up": lambda u: dict(frown=0.4 * _env(u, 0.2, 0.3)),
    "fight_idle": lambda u: dict(frown=0.9), "protest_fist": lambda u: dict(frown=0.7),
    "handcuffed_walk": lambda u: dict(frown=0.6), "escort_walk": lambda u: dict(frown=0.2),
    "sit_bench": lambda u: dict(smile=0.15), "drink_bar": lambda u: dict(smile=0.35),
    "dance_b": lambda u: dict(smile=0.65 + 0.15 * sin(TAU * u * 2)), "dance_c": lambda u: dict(smile=0.5, laugh=0.4 * _bump(u, 0.5, 0.1)),
    "lounge_pool": lambda u: dict(smile=0.30), "jog": lambda u: dict(frown=0.25),
    "play_arcade": lambda u: dict(smile=0.3 + 0.3 * _bump(u, 0.5, 0.1), surprise=0.4 * _bump(u, 0.8, 0.06)),
    "shop_browse": lambda u: dict(smile=0.20, surprise=0.3 * _bump(u, 0.45, 0.08)),
    "sit_class": lambda u: dict(frown=0.15), "teach": lambda u: dict(smile=0.3),
    "child_play": lambda u: dict(smile=0.7, laugh=0.6 * _bump(u, 0.75, 0.08)), "child_run": lambda u: dict(smile=0.6),
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
        if name in EYES_CLOSED:
            P["lids.ry"] = P.g("lids.ry") + BLINK_DEG                        # asleep: the eyes stay shut
        else:
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
    set_arm_ik(K1, "L", (0.190, 0.100, 1.060), (0.2, -1.0, -0.2), (-1.0, 0.0, 0.0), w=1.0, pole=10.0)
    set_arm_ik(K1, "R", (0.200, -0.050, 1.300), (0.3, -1.0, 0.3), (-0.9, 0.0, 0.3), w=1.0, pole=-10.0)
    elbow_to(K1, "L", (0.2, 1.0, -0.6), 1.0)          # elbows out at the sides (2026-10-01: arms through the body)
    elbow_to(K1, "R", (0.3, -1.0, -0.5), 1.0)
    K2 = add(K1, spine__ry=10.0, chest__ry=6.0, neck__ry=12.0, head__ry=14.0, hips__z=-0.02)
    set_arm_ik(K2, "L", (0.195, 0.090, 1.020), (0.2, -1.0, -0.3), (-1.0, 0.0, 0.0), w=1.0, pole=10.0)
    elbow_to(K2, "L", (0.2, 1.0, -0.6), 1.0)
    K3 = add(K1, spine__ry=-2.0, neck__ry=-4.0, head__ry=-6.0)
    keys = [(0.0, S, {"hold": True}), (0.58, K1), (1.15, K2), (1.70, K3), (2.30, Pose(STAND), {"hold": True})]
    return [(t, ik_to_fk(k), *rest) for (t, k, *rest) in keys]


def laugh_fn():
    keys = A.retime_world(laugh_keys())[0]
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
    elbow_to(J1, "R", (-0.2, -1.0, -0.4), 1.0)
    elbow_to(J1, "L", (0.0, 1.0, -0.4), 1.0)
    B1 = Pose(J1)
    set_arm_ik(B1, "R", (0.255, 0.110, 1.200), (0.9, -0.1, 0.3), (0.0, 0.4, -1.0), w=1.0, pole=-25.0)
    B1.update({"chest.rz": -4.0, "neck.ry": 10.0})
    elbow_to(B1, "R", (-0.3, -1.0, -0.4), 1.0)
    J2 = Pose(J1)
    set_arm_ik(J2, "R", (0.430, 0.060, 1.280), (1.0, 0.0, 0.10), (0.0, 0.3, -1.0), w=1.0, pole=-30.0)
    J2.update({"chest.rz": -11.0, "spine.ry": 10.0, "neck.ry": 15.0, "head.ry": -11.0, "hips.x": 0.050})
    elbow_to(J2, "R", (-0.1, -1.0, -0.3), 1.0)
    OPEN = add(S, hips__x=-0.01, spine__ry=-2.0, chest__ry=-5.0, neck__ry=2.0, head__ry=-4.0, head__rz=6.0)
    for sd in ("L", "R"):
        set_arm_ik(OPEN, sd, (0.230, 0.360, 1.180), (0.4, 1.0, 0.3), (0.0, -0.8, 0.6), w=1.0, pole=-20.0)
        OPEN["shoulder.%s.ry" % sd] = -6.0
        elbow_to(OPEN, sd, (0.0, 1.0 if sd == "L" else -1.0, -0.7), 1.0)
    CHOP = Pose(S)
    set_arm_ik(CHOP, "L", (0.360, 0.120, 1.130), (0.9, -0.2, -0.5), (0.0, -1.0, 0.0), w=1.0, pole=-25.0)
    set_arm_ik(CHOP, "R", (0.180, 0.290, 1.030), (0.5, 0.3, -0.8), (0.0, -1.0, 0.0), w=1.0, pole=-10.0)
    CHOP.update({"chest.rz": 7.0, "neck.ry": 12.0, "head.ry": -8.0, "head.rz": -4.0, "hips.x": 0.045})
    elbow_to(CHOP, "L", (-0.2, 1.0, -0.4), 1.0)
    elbow_to(CHOP, "R", (0.0, -1.0, -0.5), 1.0)
    keys = [S, J1, B1, J2, OPEN, CHOP, S]
    keys = [ik_to_fk(k) for k in keys]
    return [(t, k) for t, k in zip((0.0, 0.66, 0.96, 1.24, 2.05, 2.62, 3.4), keys)]


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
    elbow_to(K2, "R", (0.05, -1.0, 0.30), 0.95)             # (2026-10-02: the high elbow up, the low elbow down: the
                                                              # partners' upper arms crossed 2.9 cm deep)
    set_arm_ik(K2, "L", (d + hl[0], hl[1], hl[2]), (0.3, -1.0, 0.0), (-1.0, 0.0, 0.0), w=1.0, pole=-50.0)
    elbow_to(K2, "L", (0.05, 1.0, -0.50), 0.95)
    K3 = add(K2, hips__y=0.01, chest__rz=4.0, head__rz=4.0)
    # the hands go round the partner's sides on the way in and out (not through them)
    KM = add(S, spine__ry=2.5, chest__ry=2.5, neck__ry=3.0, spine__rx=-5.0, neck__rz=12.0, head__rz=26.0)
    set_arm_ik(KM, "R", (d + 0.04, 0.46, 1.38), (0.6, -0.8, 0.0), (-0.6, -0.8, 0.0), w=1.0, pole=-50.0)
    elbow_to(KM, "R", (0.0, -1.0, 0.45), 0.8)          # (2026-10-02: the high elbow over the partner's low elbow)
    # (2026-10-02: the low arm passes under the partner's high arm: its elbow went through the partner's forearm)
    set_arm_ik(KM, "L", (d + 0.03, 0.40, 1.02), (0.6, -0.8, 0.0), (-0.6, -0.8, 0.0), w=1.0, pole=-40.0)
    elbow_to(KM, "L", (0.0, 1.0, -0.6), 0.8)
    keys = [(0.0, S, {"hold": True}), (0.75, KM), (1.20, K2), (1.65, K3), (2.05, K2), (2.50, KM),
            (3.30, Pose(STAND), {"hold": True})]
    # (2026-10-02) IK between the arm keys: the wrists go round the partner on straight paths and the elbow poles hold
    # the high arm over the partner's low arm (in FK the partners' upper arms crossed 3 cm deep on the way in)
    return [(t, relax_wrists(fill_arm_targets(Pose(k))), *rest) for (t, k, *rest) in keys]


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
    keys_, ln_ = A.retime_world(argue_keys(), loop=True, length=3.4)
    fn, n = keyed_clip(keys_, loop=True, length=ln_)
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
    # the v5 planned clips (people_clips.py): face overlays, jaw in the talking ones
    import people_clips as PC
    jaws = {"talk_idle": lambda t, d: talk_jaw(t, d, True, rate=3.8, amp=3.0),
            "talk_gesture_b": lambda t, d: talk_jaw(t, d, True, rate=4.4, amp=5.0),
            "shout": lambda t, d: (14.0 * max(0.0, min(1.0, (t - 0.45) / 0.1, (1.45 - t) / 0.15)) *
                                   (0.75 + 0.25 * sin(TAU * 3.0 * t))),
            "protest_fist": lambda t, d: 10.0 * (0.5 - 0.5 * cos(TAU * t)) * max(0.0, min(1.0, t / 0.3, (d - t) / 0.3)),
            "teach": lambda t, d: talk_jaw(t, d, True, rate=4.0, amp=4.0)}
    for c in PC.v5_clips():
        name, kind, pf, pt, loop, n, fn, meta = c
        out.append((name, kind, pf, pt, loop, n, with_face(fn, name, n, loop, jaws.get(name)), meta))
    jaws.update({k: (lambda t, d, kw=kw: talk_jaw(t, d, True, **kw)) for k, kw in talking.items()})
    out = [(c[0], c[1], c[2], c[3], c[4], c[5], step_lift(c[6], c[5], c[4]), c[7]) if c[0] in STEP_CLIPS else c
           for c in out]
    out = [(c[0], c[1], c[2], c[3], c[4], c[5], pivot_hold(c[6], c[5], c[4]), c[7]) if c[0] in PIVOT_CLIPS else c
           for c in out]
    out = [(c[0], c[1], c[2], c[3], c[4], c[5], smooth_params(c[6], c[5], c[4], SMOOTH_CLIPS[c[0]]), c[7])
           if c[0] in SMOOTH_CLIPS else c for c in out]
    return mocap_override(out, jaws)


# (2026-10-03) audit: 68 foot-slide faults.  In these keyed clips a foot target moves across the floor between two
# keys (a step, a weight shift) and the foot slid flat on the floor (punch 12.6 cm, hit_react 8.7 cm, flirt_lean
# 7.3 cm, ...).  step_lift lifts the moving foot on a half-sine over each move: the slide becomes a step.
STEP_CLIPS = {"punch", "hit_react", "flirt_lean", "dance_c", "kneel_enter", "kneel_exit", "child_play", "fight_idle",
              "sit_enter", "sit_exit", "slap", "stool_enter", "stool_exit"}
STEP_MOVE = 0.0004           # m/frame: slower than this, the foot target is still
STEP_MIN = 0.010             # m: a shorter move is not lifted (under the 1 cm slide rule)
STEP_H = 0.035               # m: the largest lift
STEP_RATE = 0.012            # m/frame: the step's mean speed
STEP_WMIN = 6                # frames: the shortest step (0.2 s)
STEP_BAND = 0.04             # m: only a foot within this of the standing foot height (on the floor) is lifted


# (2026-10-03) audit: 100 snap faults (a bone's turn rate changes too fast between frames, deg/frame^2).  In keyed
# clips the snap sits on a key where the Hermite spline turns sharply (fall_down 34 at the forearm, the gaits' shin
# 15-17 at heel strike).  smooth_params runs a [1 2 1]/4 low-pass over the pose parameters (the joint angles, the IK
# targets) `passes` times; a one-shot keeps its first and last frames exact (the pose transitions stay the same).
# The face (lids, jaw, brows, mouth) is not filtered: the talking jaw keeps its rate.
# (2026-10-03 b: sit_eat out (the filter on its IK hand turns made 4 snaps 10); 2 passes did not reach the
# slow clips' 6 deg/f2, so talk / drink_bar / swim etc. take 4-6)
SMOOTH_CLIPS = {"fall_down": 4, "collapse": 2, "get_up": 4, "talk": 6, "drink_bar": 6, "dance_c": 2,
                "kneel_exit": 4, "kneel_enter": 1, "sit_enter": 2, "sit_exit": 1, "play_arcade": 4, "swim": 4,
                "swim_enter": 3, "swim_exit": 3, "stool_enter": 3, "stool_exit": 3,
                "injured_walk": 2, "carry_walk": 2, "hold_hands_walk": 2, "hold_hands_walk_r": 2, "escort_walk": 2,
                "handcuffed_walk": 2, "child_run": 2, "jog": 2}
smooth_params = A.smooth_params


# (2026-10-03 b) the slides left after step_lift are a foot that turns about its ankle while its target stays still
# (kneel: the heel comes up, the toes scrape 3-4 cm; flirt_lean / fight_idle: the toes lift).  pivot_hold keeps the
# contact point (the ball when the heel is up, the heel when the toes are up) where it was at the start of the still
# span and moves the ankle instead; the correction is gone again when the foot turns back, and it fades out over the
# next move when it is not.
PIVOT_CLIPS = {"kneel_enter", "kneel_exit", "repair_kneel", "flirt_lean", "fight_idle", "sit_enter", "sit_exit",
               "dance_c", "child_play"}
PIVOT_FADE = 3               # frames
PIVOT_LOW = 0.02             # m: the contact point (ball or heel) within this of its standing height is on the floor
PIVOT_DRIFT = 0.004          # m/frame: a contact point slower than this is held (the audit counts < 6 mm as planted)


def pivot_hold(fn, n, loop):
    if n < 4:
        return fn
    m = n if loop else n + 1
    poses = [fn(f) for f in range(m)]
    off = {s: [None] * m for s in ("L", "R")}
    db, dh = Vector(A.BALL) - Vector(A.ANK), Vector(A.HEEL) - Vector(A.ANK)
    rest_b, rest_h = A.BALL.z, A.HEEL.z
    for s in ("L", "R"):
        kx, ky, kz = ("foot.%s.%s" % (s, c) for c in "xyz")
        if not all(kx in P for P in poses):
            continue
        pt, kind, ok = [], [], []
        for P in poses:
            q = N.qeuler(P.g("foot.%s.roll" % s), P.g("foot.%s.pitch" % s), P.g("foot.%s.yaw" % s))
            a = Vector((P[kx], P[ky], P[kz]))
            cb, ch = a + q @ db, a + q @ dh
            if cb.z - rest_b < ch.z - rest_h:
                pt.append(cb), kind.append("b"), ok.append(cb.z - rest_b < PIVOT_LOW and P.g("foot.%s.rel" % s) < 0.01)
            else:
                pt.append(ch), kind.append("h"), ok.append(ch.z - rest_h < PIVOT_LOW and P.g("foot.%s.rel" % s) < 0.01)
        nxt = lambda f: (f + 1) % m if loop else min(m - 1, f + 1)
        contact = [ok[f] and kind[nxt(f)] == kind[f] and
                   ((pt[nxt(f)].x - pt[f].x) ** 2 + (pt[nxt(f)].y - pt[f].y) ** 2) ** 0.5 < PIVOT_DRIFT
                   for f in range(m)]
        order = list(range(m))
        if loop:                                     # start at a frame out of contact: no span wraps the seam
            free = [f for f in range(m) if not contact[f]]
            if not free:
                continue
            order = [(free[0] + k) % m for k in range(m)]
        spans, cur = [], []
        for f in order:
            if contact[f] or (cur and ok[f] and kind[f] == kind[cur[-1]]):
                if cur and kind[f] != kind[cur[-1]]:
                    spans.append(cur)
                    cur = []
                cur.append(f)
                if not contact[f]:                   # the last frame of the span (the foot leaves next)
                    spans.append(cur)
                    cur = []
            elif cur:
                spans.append(cur)
                cur = []
        if cur:
            spans.append(cur)
        for sp in spans:
            a, b = pt[sp[0]], pt[sp[-1]]
            if not loop and sp[-1] == m - 1 and sp[0] != 0:
                a = b                                # a one-shot ends exactly on its last key (pose transitions)
            for k, f in enumerate(sp):
                u = k / float(len(sp) - 1) if (not loop and sp[0] == 0 and sp[-1] == m - 1 and len(sp) > 1) else 0.0
                h = a.lerp(b, u)
                off[s][f] = Vector((h.x - pt[f].x, h.y - pt[f].y, 0.0))
        held = [o is not None for o in off[s]]       # fade a left-over correction out over the next frames
        last, age = None, 0
        for f in (order + order[:PIVOT_FADE + 1]) if loop else order:
            if held[f]:
                last, age = off[s][f], 0
            elif last is not None:
                age += 1
                w = max(0.0, 1.0 - age / float(PIVOT_FADE + 1))
                o = last * w                         # a quick small step back onto the key path (a slow fade
                o.z = 0.6 * last.length * sin(pi * w)    # would read as a slide)
                off[s][f] = o
                if w == 0.0:
                    last = None
    if not any(o is not None and o.length > 1e-5 for s in off for o in off[s]):
        return fn

    def out(f):
        P = fn(f)
        fi = int(f) % m if loop else max(0, min(n, int(f)))
        for s in ("L", "R"):
            o = off[s][fi]
            if o is not None and o.length > 1e-5:
                P = Pose(P)
                P["foot.%s.x" % s] = P.g("foot.%s.x" % s) + o.x
                P["foot.%s.y" % s] = P.g("foot.%s.y" % s) + o.y
                P["foot.%s.z" % s] = P.g("foot.%s.z" % s) + o.z
        return P
    return out


def step_lift(fn, n, loop):
    if n < 2:
        return fn
    base = {s: STAND.g("foot.%s.z" % s) for s in ("L", "R")}
    lift = {s: [0.0] * (n + 1) for s in ("L", "R")}
    newxy = {s: {} for s in ("L", "R")}
    poses = [fn(f) for f in range(n + 1)]
    for s in ("L", "R"):
        kx, ky, kz = ("foot.%s.%s" % (s, c) for c in "xyz")
        if not all(kx in P and ky in P and kz in P for P in poses):
            continue
        xy = [(P[kx], P[ky]) for P in poses]
        z = [P[kz] for P in poses]
        sp = [((xy[(f + 1) % (n + 1)][0] - xy[f][0]) ** 2 + (xy[(f + 1) % (n + 1)][1] - xy[f][1]) ** 2) ** 0.5
              for f in range(n + 1)]
        order = list(range(n + 1))
        if loop:                                    # start the scan at a still frame so no move wraps the seam
            still = [f for f in range(n) if sp[f] < STEP_MOVE]
            if not still:
                continue
            order = [(still[0] + i) % n for i in range(n)]
        seg = []

        def close(seg):
            if len(seg) < 2:
                return
            d = [0.0]
            for f in seg[:-1]:
                d.append(d[-1] + sp[f])
            D = d[-1]
            if D < STEP_MIN or max(z[f] for f in seg) > base[s] + STEP_BAND:
                return
            h = min(STEP_H, 0.5 * D)
            # (2026-10-03 b) a quick step, not a slow lifted glide: the audit counts a foot that moves slower than
            # 6 mm/frame as planted (and then sliding or floating).  The foot covers the same path in a window of
            # w frames (about 1.2 cm/frame), centred where the slow move was half done; before the window it waits
            # at the start, after it at the end.
            k = len(seg) - 1
            w = max(STEP_WMIN, min(k, int(round(D / STEP_RATE))))
            mid = next(i for i, dd in enumerate(d) if dd >= 0.5 * D)
            i0 = max(0, min(k - w, mid - w // 2))
            for i, f in enumerate(seg):
                u = max(0.0, min(1.0, (i - i0) / float(w)))
                u = u * u * (3.0 - 2.0 * u)
                want = u * D                                  # distance along the original path
                j = max(0, min(k - 1, next((j for j in range(k) if d[j + 1] >= want), k - 1)))
                a = (want - d[j]) / max(1e-9, d[j + 1] - d[j])
                a = max(0.0, min(1.0, a))
                p0, p1 = xy[seg[j]], xy[seg[j + 1]]
                newxy[s][f] = (p0[0] + (p1[0] - p0[0]) * a, p0[1] + (p1[1] - p0[1]) * a)
                lift[s][f] = max(lift[s][f], h * sin(pi * u))
        for f in order:
            if sp[f] >= STEP_MOVE:
                seg.append(f)
            else:
                if seg:
                    seg.append(f)
                    close(seg)
                seg = []
        if seg:
            close(seg)
        if loop:
            lift[s][n] = lift[s][0]
            if 0 in newxy[s]:
                newxy[s][n] = newxy[s][0]
    if not any(any(v) for v in lift.values()):
        return fn

    def out(f):
        P = fn(f)
        fi = int(f) % (n + 1) if loop else max(0, min(n, int(f)))
        for s in ("L", "R"):
            if lift[s][fi] or fi in newxy[s]:
                P = Pose(P)
                P["foot.%s.z" % s] = P.g("foot.%s.z" % s) + lift[s][fi]
                if fi in newxy[s]:
                    P["foot.%s.x" % s], P["foot.%s.y" % s] = newxy[s][fi]
        return P
    return out


# ------------------------------------------------------------------------------------------------------------------
# motion capture (npc_mocap.py writes tools/blender/mocap/<clip>.json; CMU data, credit in art/people/people_credits.md)
# ------------------------------------------------------------------------------------------------------------------
MOCAP_DIR = os.path.join(HERE, "mocap")
MOCAP_USE = [x for x in os.environ.get("NPC_MOCAP_USE", "walk,run,idle,talk_idle").split(",") if x]
# (2026-10-03: walk, run, idle (adults), talk_idle pass the audit with no fault and read natural; jog, sit_idle,
# dance_a/b, talk, talk_gesture_a do not yet)


def mocap_clip(name):
    """(fn, frames, meta) of a retargeted capture, or None."""
    import json
    path = os.path.join(MOCAP_DIR, name + ".json")
    if not os.path.exists(path):
        return None
    d = json.load(open(path, encoding="utf-8"))
    frames = d["frames"]
    n = len(frames) - 1

    def fn(f):
        return Pose(frames[int(f) % n] if n else frames[0])
    return fn, n, d["meta"]


IS_CHILD = False             # set per body by the build (people_mpfb)
MOCAP_ADULTS = {"idle"}      # captures that stay hand-keyed on the children (c2's idle: a 9 deg/frame^2 knee snap)
# (2026-10-03) the children keep the captured walk (the manifest has one frame count per clip: hand-keyed 32 vs 34)
# with a low-pass: c2's shin snapped 28 deg/f2 at toe-off
MOCAP_CHILD_SMOOTH = {"walk": 3}


def mocap_override(clips, jaws):
    out = []
    for c in clips:
        name, kind, pf, pt, loop, n, fn, meta = c
        m = mocap_clip(name) if name in MOCAP_USE and not (IS_CHILD and name in MOCAP_ADULTS) else None
        if m is None:
            out.append(c)
            continue
        mfn, mn, mmeta = m
        if IS_CHILD and name in MOCAP_CHILD_SMOOTH:
            mfn = A.smooth_params(mfn, mn, loop, MOCAP_CHILD_SMOOTH[name])
        meta = dict(meta)
        for k in ("speed_mps", "stride_m"):
            if k in mmeta:
                meta[k] = mmeta[k]
        meta["source"] = "motion capture: CMU %s (mocap.cs.cmu.edu), retargeted" % mmeta["source"]
        out.append((name, kind, pf, pt, loop, mn, with_face(mfn, name, mn, loop, jaws.get(name)), meta))
    return out


def pairs_json():
    import people_clips as PC
    pairs = {"hug": dict(clip_a="hug", clip_b="hug", distance_m=HUG["distance"], facing_deg=HUG["facing_deg"],
                         sync_s=HUG["sync_s"], side_offset_m=0.0, hand_contact=True, arm_contact=True,
                         note="arms round the partner's back, heads side by side; the hands rest on the partner's back and the high "
                         "forearm on the partner's shoulder (arm_contact)")}
    pairs.update({k: dict(v) for k, v in PC.PAIRS.items()})
    return {
        "note": ("Paired clips.  Partner A plays clip_a at time 0, partner B plays clip_b from sync_s.  B stands at "
                 "distance_m along A's forward axis (+X) and side_offset_m along A's left (+Y), turned facing_deg about "
                 "the vertical from A's facing (180 = facing A, 0 = the same way).  Distances are for two 1.80 m "
                 "people; scale them by the mean of the two variant scales.  Walking pairs move both roots together "
                 "along +X at the clip's speed_mps."),
        "pairs": pairs,
    }
