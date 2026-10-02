"""
Frontier Habitat 5.0 - ART-NPC: motion capture -> our clips (retarget + cleanup).  Paul approved the CC0 Quaternius pack
and the CMU database (2026-10-02, via the orchestrator; files in D:/Tools/mocap, never in the repo).

  blender --background --factory-startup --python tools/blender/npc_mocap.py -- --clips walk,run [--list]

For each clip in CLIPS: import the CMU BVH take, sample it at 30 fps, retarget it to OUR skeleton (the v3 bind, s = 1)
as Pose parameters (the same parameters every hand-keyed clip uses), clean it up, and write
tools/blender/mocap/<clip>.json.  The people build (people_clips.mocap_override) bakes these Poses through the normal
pipeline (height retarget, contacts, limits, guard), so a mocap clip is a drop-in replacement.

Retarget (world delta with an anatomical rest match):
  D_ours[b](t) = G . Dm[m](t) . G0^-1 . C[b]
  Dm  = the mocap joint's world turn from its rest;  G = heading (the take's mean facing -> +X);  G0 = the rest heading;
  C   = our bind frame -> the mocap rest frame (bone direction + an anatomical reference: left for the torso and feet,
        forward for arms and legs).
  Local Pose angles: Q = D[parent]^-1 . D[b] as world-aligned XYZ Euler (npc_common.qeuler).
  Legs stay IK: ankle targets from the mocap ankles (scaled by leg length, travel removed), foot pitch / yaw / roll
  from the foot's turn, knee pole from the mocap knee, toe bend.
Cleanup: ground from the planted balls of the feet; the walking travel removed (in place, the game moves the root); a
loop cut at two heel strikes with the seam residual spread over the loop; planted feet locked (no slide beyond the
in-place travel, flat on the floor); every bone under 14 deg/frame (npc_verify: 15) by the bake despike.
"""
import bpy
import os
import sys
import json
import math
from math import degrees, radians, atan2

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
from mathutils import Vector, Quaternion, Matrix   # noqa: E402

MOCAP = os.environ.get("NPC_MOCAP", r"D:/Tools/mocap")
OUT = os.path.join(HERE, "mocap")
FPS = 30
CREDIT = ("CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu; NSF EIA-0196217), BVH conversion by B. Hahne; "
          "retargeted by ART-NPC")

# clip -> take, kind (gait: a loop of two steps with travel removed; loop: a still loop; segment: a one-shot range),
# seconds (start, end) to search in, and options
# the takes of subjects 140-143 are 60 fps although their files say 120 (the walk cadence: a 0.57 s stride cycle at
# 120 is a 1.14 s cycle at 60, the normal one; the stride length is normal either way)
TAKE_FPS = {"140": 60.0, "141": 60.0, "142": 60.0, "143": 60.0}
# clip -> take, kind (gait: two steps with the travel removed; loop: a still loop), span in RAW file frames to search,
# the cycle length range in 30 fps frames (gait) or the loop length in seconds (loop)
CLIPS = {
    "walk": dict(take="143_32", kind="gait", span=(84, 245), period=(26, 40)),
    "run": dict(take="143_01", kind="gait", span=(8, 100), period=(16, 26)),      # 3.4 m/s: the colony pace
    "jog": dict(take="143_42", kind="gait", span=(165, 250), period=(16, 28)),    # 2.6 m/s
    "idle": dict(take="140_06", kind="loop", span=(20, 296), length=4.0, rest="stand"),       # (the standing part: later it crouches)
    "talk": dict(take="18_08", kind="loop", span=(0, 99999), length=4.0, calm=3.0),
    "talk_gesture_a": dict(take="19_08", kind="loop", span=(0, 99999), length=4.0, calm=1.0),
    "talk_idle": dict(take="18_08", kind="loop", span=(0, 99999), length=4.0, calm=3.0, rest="stand"),
    "sit_idle": dict(take="114_05", kind="loop", span=(0, 99999), length=5.0, rest="sit"),
    "dance_a": dict(take="141_12", kind="loop", span=(0, 99999), length=4.0, rest="stand"),
    "dance_b": dict(take="113_04", kind="loop", span=(0, 99999), length=4.0, rest="stand"),
}

# our bone -> (mocap joint whose world turn drives it, rest direction (from, to), anatomical reference)
L, F = "left", "fwd"
MAP = {
    "hips": ("Hips", ("Hips", "LowerBack:up"), L),
    "spine": ("LowerBack", ("LowerBack", "Spine1"), L),
    "chest": ("Spine1", ("Spine1", "Neck"), L),
    "neck": ("Neck1", ("Neck1", "Head"), L),
    "head": ("Head", ("Head", "Head:tail"), L),
}
for _s, _m in (("L", "Left"), ("R", "Right")):
    MAP.update({
        "shoulder." + _s: (_m + "Shoulder", (_m + "Shoulder", _m + "Arm"), F),
        "upper_arm." + _s: (_m + "Arm", (_m + "Arm", _m + "ForeArm"), F),
        "forearm." + _s: (_m + "ForeArm", (_m + "ForeArm", _m + "Hand"), F),
        "hand." + _s: (_m + "Hand", (_m + "Hand", _m + "HandIndex1"), F),
        "thigh." + _s: (_m + "UpLeg", (_m + "UpLeg", _m + "Leg"), F),
        "shin." + _s: (_m + "Leg", (_m + "Leg", _m + "Foot"), F),
        "foot." + _s: (_m + "Foot", (_m + "Foot", _m + "ToeBase"), L),
        "toe." + _s: (_m + "ToeBase", (_m + "ToeBase", _m + "ToeBase:tail"), L),
    })
FK_ORDER = ["hips", "spine", "chest", "neck", "head"] + ["%s.%s" % (b, s) for s in ("L", "R")
                                                          for b in ("shoulder", "upper_arm", "forearm", "hand")]
# mocap rest axes (Blender BVH import, axis_forward -Z, axis_up Y): left +X, forward -Y, up +Z
M_LEFT, M_FWD, M_UP = Vector((1, 0, 0)), Vector((0, -1, 0)), Vector((0, 0, 1))
O_LEFT, O_FWD = Vector((0, 1, 0)), Vector((1, 0, 0))
G0 = Quaternion((0, 0, 1), radians(90.0))           # mocap rest axes -> ours


def load_take(take):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = os.path.join(MOCAP, "cmu", take + ".bvh")
    bpy.ops.import_anim.bvh(filepath=path, global_scale=1.0, frame_start=0, use_fps_scale=False,
                            update_scene_fps=False, update_scene_duration=True, axis_forward='-Z', axis_up='Y',
                            rotate_mode='NATIVE')
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    ft = 1.0 / 120.0
    with open(path) as fh:
        for line in fh:
            if line.startswith("Frame Time"):
                ft = float(line.split(":")[1])
                break
    a, b = arm.animation_data.action.frame_range
    fps = TAKE_FPS.get(take.split("_")[0], 1.0 / ft)
    return arm, fps, int(a), int(b)


def joint_pos(arm, name):
    if name.endswith(":tail"):
        return arm.matrix_world @ arm.pose.bones[name[:-5]].tail
    if name.endswith(":up"):
        return None
    return arm.matrix_world @ arm.pose.bones[name].head


def rest_pos(arm, name):
    if name.endswith(":tail"):
        return arm.data.bones[name[:-5]].tail_local.copy()
    return arm.data.bones[name].head_local.copy()


def rest_frames(arm):
    """C[b]: our bind frame -> the mocap rest frame (in our axes, rest heading)."""
    C = {}
    for b, (m, (a, z), ref) in MAP.items():
        if z.endswith(":up"):
            ym = M_UP.copy()
        else:
            ym = rest_pos(arm, z) - rest_pos(arm, a)
            if ym.length < 1e-6:
                ym = M_UP.copy()
        um = M_LEFT if ref == L else M_FWD
        y0 = (N.BIND_TAIL[b] - N.BIND_HEAD[b]).normalized()
        u0 = O_LEFT if ref == L else O_FWD
        ym_o, um_o = (G0 @ ym).normalized(), (G0 @ um)
        um_o = (um_o - ym_o * um_o.dot(ym_o)).normalized()
        u0 = (u0 - y0 * u0.dot(y0)).normalized()
        C[b] = N.q_from_frames(u0, y0, um_o, ym_o)
        if b.startswith("shoulder."):
            # the clavicle's rest direction is a joint layout, not a pose: the CMU T-pose clavicle points 34 deg up and
            # matching it raised our shoulders into a shrug.  The clavicles take only the capture's change from rest.
            C[b] = Quaternion()
    return C


def sample(arm, f0, f1, step):
    """World turn delta (from rest) and joint positions per sampled frame."""
    sc = bpy.context.scene
    rest_q = {pb.name: pb.bone.matrix_local.to_quaternion() for pb in arm.pose.bones}
    names = sorted(set(m for m, _, _ in MAP.values()) | {"LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot",
                                                         "LeftLeg", "RightLeg", "LeftUpLeg", "RightUpLeg", "Hips"})
    out = []
    f = float(f0)
    while f <= f1 + 1e-6:
        fi = int(math.floor(f))
        sc.frame_set(fi, subframe=f - fi)
        rec = {"D": {}, "P": {}}
        for n in names:
            pb = arm.pose.bones[n]
            rec["D"][n] = ((arm.matrix_world @ pb.matrix).to_quaternion() @ rest_q[n].inverted()).normalized()
            rec["P"][n] = arm.matrix_world @ pb.head
            rec["P"][n + ":tail"] = arm.matrix_world @ pb.tail
        out.append(rec)
        f += step
    return out


def leg_len(arm):
    a = rest_pos(arm, "LeftUpLeg")
    b = rest_pos(arm, "LeftLeg")
    c = rest_pos(arm, "LeftFoot")
    return (b - a).length + (c - b).length


OUR_LEG = (N.KNEE_JOINT - N.HIP_JOINT).length + (N.ANKLE_JOINT - N.KNEE_JOINT).length


def heading(frames):
    """The mean facing (Hips forward) in the mocap xy plane -> G (that facing onto +X)."""
    acc = Vector((0.0, 0.0, 0.0))
    for r in frames:
        v = r["D"]["Hips"] @ M_FWD
        acc += Vector((v.x, v.y, 0.0))
    ang = atan2(acc.y, acc.x)
    return Quaternion((0, 0, 1), -ang)


def to_pose(r, C, G, k, trend, ground, prev_e):
    """One sampled mocap frame -> our Pose (s = 1)."""
    P = N.Pose()
    D = {}
    Gi0 = G0.inverted()
    for b, (m, _, _) in MAP.items():
        D[b] = (G @ r["D"][m] @ Gi0 @ C[b]).normalized()
    # FK angles (world-aligned XYZ in the parent's frame)
    for b in FK_ORDER:
        par = N.PARENT[b]
        q = D[b] if par == "root" else (D[par].inverted() @ D[b])
        e = q.to_euler("XYZ", prev_e[b]) if b in prev_e else q.to_euler("XYZ")
        prev_e[b] = e
        P[b + ".rx"], P[b + ".ry"], P[b + ".rz"] = degrees(e.x), degrees(e.y), degrees(e.z)

    def ours(p):
        q = G @ (p - trend)
        return Vector((q.x * k, q.y * k, (p.z - ground) * k))
    # the pelvis: the mid point of the mocap hip joints -> our hip joints' mid point; our hips head is 4.5 cm above it
    mid = ours((r["P"]["LeftUpLeg"] + r["P"]["RightUpLeg"]) * 0.5)
    up = D["hips"] @ Vector((0.0, 0.0, N.BIND_HEAD["hips"].z - N.HIP_JOINT.z))
    hp = mid + up
    P["hips.x"], P["hips.y"], P["hips.z"] = hp.x - N.BIND_HEAD["hips"].x, hp.y, hp.z - N.BIND_HEAD["hips"].z
    for s, mm in (("L", "Left"), ("R", "Right")):
        an = ours(r["P"][mm + "Foot"])
        P["foot.%s.x" % s], P["foot.%s.y" % s], P["foot.%s.z" % s] = an.x, an.y, an.z
        e = D["foot." + s].to_euler("XYZ", prev_e.get("foot." + s)) if ("foot." + s) in prev_e else D["foot." + s].to_euler("XYZ")
        prev_e["foot." + s] = e
        P["foot.%s.roll" % s], P["foot.%s.pitch" % s], P["foot.%s.yaw" % s] = degrees(e.x), degrees(e.y), degrees(e.z)
        tq = D["foot." + s].inverted() @ D["toe." + s]
        P["toe.%s.ry" % s] = degrees(tq.to_euler("XYZ").y)
        # knee pole: the mocap knee's side of the hip-ankle line, as knee.out about the foot yaw
        hip, kn, ak = ours(r["P"][mm + "UpLeg"]), ours(r["P"][mm + "Leg"]), an
        d = (ak - hip).normalized()
        pv = (kn - hip) - d * (kn - hip).dot(d)
        if pv.length > 1e-4:
            ang = degrees(atan2(pv.y, pv.x))
            out = ang - P["foot.%s.yaw" % s]
            out = (out + 180.0) % 360.0 - 180.0
            P["knee.%s.out" % s] = max(-40.0, min(40.0, out))
            P["knee.%s.w" % s] = pv.length / max(1e-6, (kn - hip).length)     # how bent: the pole's reliability
    for s in ("L", "R"):
        P["arm.%s.ik" % s] = 0.0
    P["scap.off"] = 1.0                 # the capture has its own shoulder motion: no solver shoulder rhythm
    return P


SOLE = [N.HEEL_PIVOT - N.ANKLE_JOINT + Vector((0.0, dy, 0.0)) for dy in (-0.035, 0.0, 0.035)] +        [Vector((N.BALL_JOINT.x, N.BALL_JOINT.y + dy, 0.0)) - N.ANKLE_JOINT for dy in (-0.045, 0.0, 0.045)]


def sole_ankle_z(P, s):
    """The ankle height at which OUR foot's lowest sole point (heel or ball) touches the floor, for this foot turn."""
    q = N.qeuler(P["foot.%s.roll" % s], P["foot.%s.pitch" % s], P["foot.%s.yaw" % s])
    return -min((q @ v).z for v in SOLE)


def knee_poles(frames):
    """The knee pole is unreliable on a straight leg (it flipped 33 deg between two frames of the walk): weight each
    frame by the knee bend and smooth over 7 frames (loop)."""
    n = len(frames) - 1
    for s in ("L", "R"):
        o = [P.get("knee.%s.out" % s, 0.0) for P in frames[:n]]
        w = [min(1.0, P.get("knee.%s.w" % s, 0.0) / 0.25) ** 2 for P in frames[:n]]
        for i, P in enumerate(frames[:n]):
            num = den = 0.0
            for d in range(-3, 4):
                j = (i + d) % n
                ww = w[j] * (1.0 - abs(d) / 4.0)
                num += o[j] * ww
                den += ww
            P["knee.%s.out" % s] = num / den if den > 1e-6 else 0.0
        for P in frames:
            P.pop("knee.%s.w" % s, None)
        frames[-1] = dict(frames[0])
    return frames


def leg_reach(frames, lim=0.993):
    """Our legs are shorter / straighter than the capture's in places: a planted leg past 99.3 % of its length snaps
    the knee (the IK clamps).  The hips drop just enough, smoothed over 5 frames (loop)."""
    import npc_anims as A
    n = len(frames) - 1
    drop = []
    for P in frames[:n]:
        Q = N.Pose(P)
        z0 = Q.g("hips.z")
        need = [s for s in ("L", "R") if A.leg_reach(Q, s) > lim]
        if need:
            z1 = A.hips_for(Q, need, {s: lim for s in need})
            drop.append(min(0.0, z1 - z0))
        else:
            drop.append(0.0)
    sm = []
    for i in range(n):
        sm.append(min(drop[(i + d) % n] for d in range(-2, 3)))
    sm2 = [sum(sm[(i + d) % n] for d in range(-2, 3)) / 5.0 for i in range(n)]
    for i, P in enumerate(frames[:n]):
        P["hips.z"] = P.get("hips.z", 0.0) + min(sm2[i], drop[i])
    frames[-1] = dict(frames[0])
    return frames


def ground_feet(frames):
    """Feet on OUR foot shape: a foot near the floor (its sole within 2.5 cm) is put on it; no foot goes through it;
    the toes of a foot on the ball bend up to the floor (no toe tip under it)."""
    for P in frames:
        for s in ("L", "R"):
            if P["foot.%s.pitch" % s] > 0.0:
                P["toe.%s.ry" % s] = min(P.get("toe.%s.ry" % s, 0.0), -P["foot.%s.pitch" % s] + 2.0)
            z = P["foot.%s.z" % s]
            # a foot near the floor stands on its sole, not on its edge (the roll fades out over the last 4 cm)
            g0 = sole_ankle_z(P, s)
            P["foot.%s.roll" % s] *= max(0.0, min(1.0, (z - g0 - 0.01) / 0.04))
            g = sole_ankle_z(P, s)
            if z - g < 0.025:
                # within 2.5 cm: blend onto the floor (fully at 1 cm and below)
                t = max(0.0, min(1.0, (z - g - 0.010) / 0.015))
                P["foot.%s.z" % s] = g + (z - g) * t * t
            P["foot.%s.z" % s] = max(P["foot.%s.z" % s], g)
    return frames


XFADE = 6           # frames: the loop seam is a cross-fade of the capture past the cut into its start


def crossfade(frames, T, K, keys):
    """frames has T + 1 + K samples: the first K frames blend from the samples past the cut (T .. T+K) into their own
    (smoothstep), so position AND speed run on through the seam (a plain cut left 15-24 deg/frame^2 snaps)."""
    if K <= 0:
        return frames[:T + 1]
    out = [dict(P) for P in frames[:T + 1]]
    for i in range(K):
        w = (i + 1) / (K + 1)
        w = w * w * (3 - 2 * w)
        A_, B_ = frames[T + i], frames[i]
        for k_ in keys:
            a, b = A_.get(k_, 0.0), B_.get(k_, 0.0)
            if k_.endswith((".rx", ".ry", ".rz", ".roll", ".pitch", ".yaw", ".out")):
                a = b + ((a - b + 180.0) % 360.0 - 180.0)
            out[i][k_] = a + (b - a) * w
    out[T] = dict(frames[T])
    return out


def apart(frames, gap=0.075):
    """The feet keep a little apart across the line of travel (the jog take crosses the legs: thigh through thigh)."""
    for P in frames:
        for s, sg in (("L", 1.0), ("R", -1.0)):
            y = P["foot.%s.y" % s] * sg
            if y < gap:
                P["foot.%s.y" % s] = sg * (gap - (gap - y) * 0.25) if y > gap - 0.1 else sg * (gap - 0.025)
    return frames


def onto_rest(frames, rest="stand"):
    """A standing (or seated) loop starts and ends on OUR rest pose (idle frame 0 is the 'stand' state every transition
    starts from): every FK bone turns by the capture's change from its first frame, applied to our rest turn
    (rotations, not Euler sums: an Euler offset swung an arm out); positions and foot angles shift by the offset."""
    import npc_anims as A
    S = N.Pose(A.STAND if rest == "stand" else A.ik_to_fk(A.SIT))
    F0 = dict(frames[0])
    fk = [b for b in FK_ORDER]
    q_rest = {b: N.qeuler(S.g(b + ".rx"), S.g(b + ".ry"), S.g(b + ".rz")) for b in fk}
    q_0 = {b: N.qeuler(F0.get(b + ".rx", 0.0), F0.get(b + ".ry", 0.0), F0.get(b + ".rz", 0.0)) for b in fk}
    prev = {}
    for P in frames:
        for b in fk:
            q = N.qeuler(P.get(b + ".rx", 0.0), P.get(b + ".ry", 0.0), P.get(b + ".rz", 0.0))
            qn = (q_rest[b] @ q_0[b].inverted() @ q).normalized()
            e = qn.to_euler("XYZ", prev[b]) if b in prev else qn.to_euler("XYZ")
            prev[b] = e
            P[b + ".rx"], P[b + ".ry"], P[b + ".rz"] = degrees(e.x), degrees(e.y), degrees(e.z)
        for k_ in list(S.keys()) + [k for k in F0 if k.startswith(("hips.", "foot.", "toe.", "knee."))]:
            if k_.startswith(("arm.", "hand.", "prop.", "scap.")) or k_.split(".")[0] in [x.split(".")[0] for x in fk]                     and k_.endswith((".rx", ".ry", ".rz")) and not k_.startswith(("foot", "toe")):
                continue
            d = S.g(k_) - F0.get(k_, 0.0)
            if k_.endswith((".roll", ".pitch", ".yaw", ".out", ".ry")):
                d = (d + 180.0) % 360.0 - 180.0
            P[k_] = P.get(k_, 0.0) + d
    return frames


def unwrap_seam(frames, keys):
    """Spread the loop residual (last sample vs the first) linearly over the loop, so the seam is exact."""
    n = len(frames) - 1
    for k_ in keys:
        a, b = frames[0].get(k_, 0.0), frames[-1].get(k_, 0.0)
        r = b - a
        if k_.endswith((".rx", ".ry", ".rz", ".roll", ".pitch", ".yaw", ".out")):
            r = (r + 180.0) % 360.0 - 180.0 if abs(r) > 180.0 else r
        for i, P in enumerate(frames):
            P[k_] = P.get(k_, 0.0) - r * i / n
    frames[-1] = dict(frames[0])
    return frames


def contacts(frames, s, v):
    """Planted frames of foot s in an in-place gait (the stance foot moves back at the travel speed v m/frame)."""
    out = []
    for i, P in enumerate(frames):
        j = (i + 1) % (len(frames) - 1)
        dx = frames[j]["foot.%s.x" % s] - P["foot.%s.x" % s]
        dy = frames[j]["foot.%s.y" % s] - P["foot.%s.y" % s]
        moving = math.hypot(dx + v, dy) > 0.012
        out.append((not moving) and P["foot.%s.z" % s] < N.ANKLE_JOINT.z + 0.035)
    return out


def lock_feet(frames, v, still=False):
    """Planted feet: flat ones on the floor (ankle height), no slide beyond the in-place travel; 3-frame blends.
    The loop is circular: a plant that runs through the seam is one plant (2026-10-03: split plants put ramps at the
    seam, 9-10 deg/frame^2 knee snaps in idle)."""
    n = len(frames) - 1
    for s in ("L", "R"):
        c = contacts(frames, s, v)[:n]
        if all(c):
            runs = [(0, n - 1)]
        else:
            off = c.index(False)                       # start the scan on a free frame: runs never wrap mid-scan
            runs, i = [], 0
            while i < n:
                t = (off + i) % n
                if c[t]:
                    j = i
                    while j + 1 < n and c[(off + j + 1) % n]:
                        j += 1
                    runs.append((off + i, off + j))    # unwrapped indices; frames taken modulo n
                    i = j + 1
                else:
                    i += 1
        for a, b in runs:
            if b - a < 2:
                continue
            idx = [t % n for t in range(a, b + 1)]
            x0 = sum(frames[t]["foot.%s.x" % s] + v * (u - a) for u, t in zip(range(a, b + 1), idx)) / len(idx)
            y0 = sum(frames[t]["foot.%s.y" % s] for t in idx) / len(idx)
            whole = (b - a + 1) >= n
            for u, t in zip(range(a, b + 1), idx):
                P = frames[t]
                w = 1.0 if whole else min(1.0, (u - a + 1) / 3.0, (b - u + 1) / 3.0)
                w = w * w * (3 - 2 * w)
                # (a standing loop: a still foot is flat on the floor whatever small pitch the capture gives it)
                flat = 1.0 if still else max(0.0, 1.0 - abs(P["foot.%s.pitch" % s]) / 10.0)
                if still:
                    P["foot.%s.pitch" % s] *= 1.0 - w
                    P["toe.%s.ry" % s] = P.get("toe.%s.ry" % s, 0.0) * (1.0 - w)
                P["foot.%s.x" % s] += w * (x0 - v * (u - a) - P["foot.%s.x" % s])
                P["foot.%s.y" % s] += w * (y0 - P["foot.%s.y" % s])
                P["foot.%s.z" % s] += w * flat * (N.ANKLE_JOINT.z - P["foot.%s.z" % s])
                P["foot.%s.roll" % s] *= 1.0 - w * flat
    frames[-1] = dict(frames[0])
    return frames


def smooth_toes(frames, r=2):
    """Toe bends (noisy in the capture) smoothed over 5 frames, circular."""
    n = len(frames) - 1
    for s in ("L", "R"):
        k_ = "toe.%s.ry" % s
        v_ = [P.get(k_, 0.0) for P in frames[:n]]
        for i, P in enumerate(frames[:n]):
            P[k_] = sum(v_[(i + d) % n] for d in range(-r, r + 1)) / (2 * r + 1)
    frames[-1] = dict(frames[0])
    return frames


def build_clip(name, spec):
    arm, fps, a, b = load_take(spec["take"])
    step = fps / FPS
    C = rest_frames(arm)
    k = OUR_LEG / leg_len(arm)
    s0 = max(a, int(spec["span"][0]))
    s1 = min(b, int(spec["span"][1]))
    raw = sample(arm, s0, s1, step)
    G = heading(raw)
    # ground: the planted balls of the feet (5th percentile of the lower ball), our ball height 0.035 m
    balls = sorted(min(r["P"]["LeftToeBase"].z, r["P"]["RightToeBase"].z) for r in raw)
    ground = balls[len(balls) // 20] - N.BALL_JOINT.z / k
    meta = dict(source=spec["take"], credit=CREDIT, fps=FPS)
    if spec["kind"] == "gait":
        # cycle: left ankle height period (autocorrelation), cut at two successive left minima in the middle
        z = [r["P"]["LeftFoot"].z for r in raw]
        n0 = len(z)
        best = (1e9, 30)
        for T in range(*spec.get("period", (14, 60))):
            e = sum((z[i] - z[i + T]) ** 2 for i in range(n0 - T)) / (n0 - T)
            if e < best[0]:
                best = (e, T)
        T = best[1]
        mid = n0 // 2 - T // 2
        i0 = min(range(mid, mid + T), key=lambda i: z[i])
        K = min(XFADE, len(raw) - (i0 + T + 1))
        seg = raw[i0:i0 + T + 1 + K]
        hp0, hp1 = seg[0]["P"]["Hips"], seg[T]["P"]["Hips"]
        travel = (G @ (hp1 - hp0))
        travel.z = 0.0
        speed = travel.length * k / (T / FPS)
        v_frame = travel.length * k / T
        frames = []
        prev = {}
        for i, r in enumerate(seg):
            trend = hp0 + (hp1 - hp0) * (i / T)
            trend = Vector((trend.x, trend.y, 0.0))
            P = to_pose(r, C, G, k, trend, ground, prev)
            frames.append(dict(P))
        # the stance foot moves back at the travel speed: the in-place convention of our gaits
        # (to_pose measured the ankles against the moving trend, which already gives exactly that)
        keys = sorted(set().union(*[set(P) for P in frames]))
        frames = crossfade(frames, T, K, keys)
        frames = unwrap_seam(frames, keys)
        frames = lock_feet(frames, v_frame)
        frames = ground_feet(apart(leg_reach(knee_poles(frames))))
        meta.update(speed_mps=round(speed, 3), stride_m=round(travel.length * k, 3))
    else:
        T = int(round(spec["length"] * FPS))
        # the most loopable window: the start whose pose after T frames is nearest to it (feet and hips)
        calm = spec.get("calm", 0.0)
        legs = leg_len(arm)

        def dist(i):
            A, B = raw[i]["P"], raw[i + T]["P"]
            d = sum((A[n] - B[n]).length for n in ("Hips", "LeftFoot", "RightFoot", "LeftHand", "RightHand", "Head"))
            if calm:
                # (2026-10-03) a calmer window: hands above the chest or far out to the side cost
                big = 0.0
                for r in raw[i:i + T + 1:3]:
                    ch, hp = r["P"]["Spine1"], r["P"]["Hips"]
                    for h in ("LeftHand", "RightHand"):
                        q = r["P"][h]
                        big += max(0.0, q.z - ch.z) + max(0.0, Vector((q.x - hp.x, q.y - hp.y)).length - 0.45 * legs)
                d += calm * big
            return d
        cand = range(0, max(1, len(raw) - T - 1))
        i0 = min(cand, key=dist)
        K = min(XFADE, len(raw) - (i0 + T + 1))
        seg = raw[i0:i0 + T + 1 + K]
        hpm = sum((r["P"]["Hips"] for r in seg), Vector()) / len(seg)
        trend = Vector((hpm.x, hpm.y, 0.0))
        frames, prev = [], {}
        for r in seg:
            frames.append(dict(to_pose(r, C, G, k, trend, ground, prev)))
        keys = sorted(set().union(*[set(P) for P in frames]))
        frames = crossfade(frames, T, K, keys)
        frames = unwrap_seam(frames, keys)
        if spec.get("rest"):
            frames = onto_rest(frames, spec["rest"])
        frames = lock_feet(frames, 0.0, still=True)
        frames = ground_feet(leg_reach(knee_poles(smooth_toes(frames))))
        if spec.get("rest"):
            frames = onto_rest(frames, spec["rest"])        # frame 0 exactly on the rest pose again (pose state)
        meta.update(window_s=[round((s0 + i0 * step) / fps, 3), round((s0 + (i0 + T) * step) / fps, 3)])
    meta["frames"] = len(frames) - 1
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".json"), "w") as fh:
        json.dump(dict(meta=meta, frames=[{k_: round(v_, 5) for k_, v_ in P.items()} for P in frames]), fh)
    print("MOCAP %s: %s, %d frames, k %.4f, %s" % (name, spec["take"], len(frames) - 1, k,
                                                 {k_: v_ for k_, v_ in meta.items() if k_ not in ("credit",)}))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv[argv.index("--clips") + 1].split(",") if "--clips" in argv else list(CLIPS)
    for n in names:
        build_clip(n, CLIPS[n])


if __name__ == "__main__":
    main()
