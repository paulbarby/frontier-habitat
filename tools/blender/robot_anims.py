"""
Frontier Habitat 5.0 - ART-NPC: clips for the club robot dancer (V5 section 1).

Every clip is a loop that starts and ends on R0 (the v3 stand pose at the origin, facing +X), so the clips chain.
Poses are authored in a BODY frame and placed by a heading h (deg about Z) and a body origin (x, y): rotate_pose().

  robot_idle      4 s   servo idle: head scans, small weight shifts
  robot_dance_a   4 s   popping / robot hits on the beat (120 bpm), held poses with a servo settle
  robot_dance_b   4 s   liquid arm wave from hand to hand, body roll, knee bounce
  robot_dance_c   8 s   a pirouette on the left foot (passe), a big arm circle with a squat, isolations, a bow
  robot_pole      8 s   acrobatic pole spin: turn to the pole, grip, a tucked fireman spin once round the pole,
                        land, a lean with one arm out, release, a V pose.  Performance, not sexual.
The pole is at POLE_LOCAL (the anchor stands 0.35 m in front of it, facing the room).
"""
import os
import sys
from math import sin, cos, pi, radians, degrees, exp, atan2

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
import npc_anims as A                                            # noqa: E402
from npc_anims import Pose, add, set_arm_ik, elbow_to, fill_arm_targets, keyed_clip, ik_to_fk, STAND, TAU, FPS, ANK  # noqa
from npc_common import sym, set_foot, ankle_from_pivot           # noqa: E402
from mathutils import Vector                                     # noqa: E402

POLE_LOCAL = (-0.35, 0.0)
POLE_R = 0.045
R0 = Pose(STAND)


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def seg(t, t0, t1):
    return ease((t - t0) / (t1 - t0)) if t1 > t0 else float(t >= t1)


def lerp(a, b, u):
    return a + (b - a) * u


def rot2(x, y, h):
    c, s = cos(radians(h)), sin(radians(h))
    return x * c - y * s, x * s + y * c


# ------------------------------------------------------------------------------------------------------------------
# body frame -> world
# ------------------------------------------------------------------------------------------------------------------
def rotate_pose(P, h, origin=(0.0, 0.0)):
    """The body-frame pose P turned by h degrees about Z and moved to origin (x, y)."""
    Q = Pose(P)
    ox, oy = origin
    x, y = rot2(P.g("hips.x"), P.g("hips.y"), h)
    Q["hips.x"], Q["hips.y"] = x + ox, y + oy
    Q["hips.rz"] = P.g("hips.rz") + h
    for s in ("L", "R"):
        x, y = rot2(P.g("foot.%s.x" % s), P.g("foot.%s.y" % s), h)
        Q["foot.%s.x" % s], Q["foot.%s.y" % s] = x + ox, y + oy
        Q["foot.%s.yaw" % s] = P.g("foot.%s.yaw" % s) + h
        x, y = rot2(P.g("arm.%s.x" % s), P.g("arm.%s.y" % s), h)
        Q["arm.%s.x" % s], Q["arm.%s.y" % s] = x + ox, y + oy
        Q["hand.%s.wz" % s] = P.g("hand.%s.wz" % s) + h
        x, y = rot2(P.g("arm.%s.px" % s), P.g("arm.%s.py" % s), h)
        Q["arm.%s.px" % s], Q["arm.%s.py" % s] = x, y
    if P.g("head.aim") > 0:
        Q["head.wz"] = P.g("head.wz") + h
    return Q


def mix(P0, P1, u):
    """Linear blend of two poses (all parameters; hand world eulers are blended as numbers: use for small turns)."""
    Q = Pose()
    for k in set(P0) | set(P1):
        Q[k] = lerp(P0.g(k), P1.g(k), u)
    return Q


# ------------------------------------------------------------------------------------------------------------------
# arm vocabulary (left-side values; R mirrored)
# ------------------------------------------------------------------------------------------------------------------
DOWN = dict(ua=(-19.0, -3.0, 6.0), fa=(1.0, -14.0, 8.0), hd=(3.0, -6.0, 0.0))
OUT = dict(ua=(60.0, 0.0, 0.0), fa=(0.0, -6.0, 0.0), hd=(0.0, 0.0, 0.0))
OUT_UP = dict(ua=(60.0, 0.0, 0.0), fa=(78.0, 0.0, 0.0), hd=(0.0, 0.0, 0.0))
OUT_DOWN = dict(ua=(60.0, 0.0, 0.0), fa=(-70.0, 0.0, 0.0), hd=(0.0, 0.0, 0.0))
SECOND = dict(ua=(42.0, -10.0, 0.0), fa=(0.0, -12.0, -6.0), hd=(0.0, -6.0, 0.0))
FIRST = dict(ua=(-4.0, -50.0, 12.0), fa=(0.0, -40.0, -46.0), hd=(0.0, -8.0, -10.0))
FIFTH = dict(ua=(138.0, -8.0, 0.0), fa=(40.0, -8.0, 0.0), hd=(10.0, 0.0, 0.0))     # arms rounded over the head
BOX = dict(ua=(60.0, 0.0, 0.0), fa=(0.0, 0.0, -84.0), hd=(0.0, 0.0, 0.0))
FWD = dict(ua=(-22.0, -80.0, 0.0), fa=(0.0, -6.0, 0.0), hd=(0.0, 0.0, 0.0))
UP = dict(ua=(146.0, -6.0, 0.0), fa=(0.0, -6.0, 0.0), hd=(0.0, 0.0, 0.0))
V = dict(ua=(118.0, -8.0, 0.0), fa=(0.0, -4.0, 0.0), hd=(0.0, 0.0, 0.0))
PRESENT = dict(ua=(84.0, -28.0, 0.0), fa=(0.0, -16.0, 0.0), hd=(0.0, 10.0, 0.0))
ACROSS = dict(ua=(-6.0, -46.0, 16.0), fa=(0.0, -24.0, -84.0), hd=(0.0, 0.0, 0.0))


def arms(P, s, a):
    """Set side s ('L', 'R' or 'LR') to the arm shape a (FK)."""
    for side in (("L", "R") if s == "LR" else (s,)):
        sg = 1.0 if side == "L" else -1.0
        for b, key in (("upper_arm", "ua"), ("forearm", "fa"), ("hand", "hd")):
            rx, ry, rz = a[key]
            P["%s.%s.rx" % (b, side)] = rx * sg
            P["%s.%s.ry" % (b, side)] = ry
            P["%s.%s.rz" % (b, side)] = rz * sg
        P["arm.%s.ik" % side] = 0.0
    return P


def body(**kw):
    """R0 with offsets (hips__z=-0.04 ...), FK arms."""
    P = add(R0, **kw)
    for s in ("L", "R"):
        P["arm.%s.ik" % s] = 0.0
    return P


def finish(P):
    return fill_arm_targets(P)


def settle(t, hits, bones=("chest.rz", "head.rz"), amp=0.8):
    """A servo settle after each hit: a small damped wobble (added)."""
    out = {}
    for th in hits:
        d = t - th
        if 0.0 <= d < 0.35:
            w = amp * exp(-d / 0.08) * sin(TAU * 13.0 * d)
            for b in bones:
                out[b] = out.get(b, 0.0) + w
    return out


# ------------------------------------------------------------------------------------------------------------------
# robot_idle (4 s)
# ------------------------------------------------------------------------------------------------------------------
def idle_fn(n=120):
    def fn(f):
        t = f / FPS
        u = f / n
        P = Pose(R0)
        # a scan: look left, hold, look right, hold (smooth), and a slow weight shift
        P["head.rz"] = R0.g("head.rz") + 22.0 * sin(TAU * u) * (0.6 + 0.4 * cos(TAU * u) ** 2)
        P["head.ry"] = R0.g("head.ry") + 2.5 * sin(TAU * 2 * u)
        P["hips.y"] = 0.018 * sin(TAU * u)
        P["hips.rx"] = -1.5 * sin(TAU * u)
        P["chest.rz"] = 4.0 * (sin(TAU * u + 0.4) - sin(0.4))
        P["hips.z"] = R0.g("hips.z") - 0.004 * (1 - cos(TAU * 2 * u))
        for s, sg in (("L", 1.0), ("R", -1.0)):
            P["hand.%s.ry" % s] = R0.g("hand.%s.ry" % s) + 4.0 * (1 - cos(TAU * 2 * u)) / 2
        return finish(P)
    return fn, n


# ------------------------------------------------------------------------------------------------------------------
# robot_dance_a (4 s): hits on the beat, holds, a servo settle
# ------------------------------------------------------------------------------------------------------------------
def dance_a_keys():
    P1 = arms(body(hips__z=-0.040, head__ry=-2.0), "LR", OUT)
    P2 = arms(arms(body(hips__z=-0.040, head__rz=20.0, chest__rx=-5.0), "L", OUT_UP), "R", OUT_DOWN)
    P3 = arms(body(hips__z=-0.065, chest__rx=0.0), "LR", OUT)
    P4 = arms(arms(body(hips__z=-0.040, head__rz=-20.0, chest__rx=5.0), "L", OUT_DOWN), "R", OUT_UP)
    P5 = arms(body(hips__z=-0.050, chest__rz=14.0, head__rz=18.0, hips__rz=4.0), "LR", BOX)
    P6 = arms(body(hips__z=-0.050, chest__rz=-14.0, head__rz=-18.0, hips__rz=-4.0), "LR", BOX)
    P7 = arms(body(hips__z=-0.080, head__ry=8.0, chest__ry=4.0), "LR", dict(FWD, ua=(-16.0, -70.0, 0.0)))
    ks = [(0.00, R0, 0.00), (0.45, P1, 0.05), (0.80, P2, 0.20), (1.30, P3, 0.20), (1.80, P4, 0.10), (2.40, P5, 0.10),
          (2.80, P6, 0.08), (3.45, P7, 0.07)]
    keys = []
    for t, P, hold in ks:
        P = finish(Pose(P))
        keys.append((t, P, {"hold": True}))
        if hold > 0:
            keys.append((t + hold, P, {"hold": True}))
    return keys, [0.80, 1.30, 1.80, 2.40, 2.80, 3.45]


def dance_a_fn():
    keys, hits = dance_a_keys()
    fn, n = keyed_clip(keys, loop=True, length=4.0)

    def g(f):
        P = Pose(fn(f))
        t = f / FPS
        for k, v in settle(t, hits).items():
            P[k] = P.g(k) + v
        P["hips.z"] = P.g("hips.z") - 0.024 * (0.5 - 0.5 * cos(TAU * t / 0.5))      # knee bounce on every beat
        return P
    return g, n



# ------------------------------------------------------------------------------------------------------------------
# robot_dance_b (4 s): a step routine: step-touch right and left with "running man" arms (beats 1-4), then a full
# turn to the left in four pivot steps with the arms out (beats 5-8); a knee bounce on every beat
# ------------------------------------------------------------------------------------------------------------------
TURN_B = (1.95, 3.85)
PIVOT_B = (0.10, 0.0)          # the turn is about a point 10 cm forward (the arms stay clear of the pole behind)
RUN_ARMS = dict(ua=(10.0, -10.0, 0.0), fa=(0.0, -88.0, 0.0), hd=(0.0, -10.0, 0.0))
TURN_ARMS = dict(ua=(-19.0, -6.0, 6.0), fa=(1.0, -30.0, 8.0), hd=(3.0, -6.0, 0.0))   # close to the sides
STEPS_B = [("L", 1.97, 2.42, 2.47, None), ("R", 2.40, 2.88, 2.92, None), ("L", 2.86, 3.34, 3.38, None),
           ("R", 3.32, 3.82, 3.85, None), ("L", 3.78, 3.98, 3.85, None)]


def dance_b_fn(n=120):
    down = arms(body(), "LR", DOWN)
    run = arms(body(), "LR", RUN_ARMS)
    wide = arms(body(), "LR", TURN_ARMS)
    def frame(t):
        h = spin_h(t, *TURN_B, total=360.0, ramp=0.3)
        px, py = rot2(PIVOT_B[0], PIVOT_B[1], h)
        return h, (PIVOT_B[0] - px, PIVOT_B[1] - py)
    st = Stepper(frame, STEPS_B, lift=0.05, pivot=0.9, pivot_windows=(TURN_B,))

    def fn(f):
        t = f / FPS
        beat = t / 0.5
        e_run = seg(t, 0.0, 0.45) * (1 - seg(t, 1.75, 2.15))
        e_wide = seg(t, 1.90, 2.30) * (1 - seg(t, 3.55, 3.98))
        P = mix(mix(down, run, e_run), wide, e_wide * (1 - e_run))
        # running-man arm swing on the beat
        for side, sg in (("L", 1.0), ("R", -1.0)):
            P["upper_arm.%s.ry" % side] = P.g("upper_arm.%s.ry" % side) - 20.0 * e_run * sin(TAU * beat / 2 + (0 if side == "L" else pi))
        P["hips.z"] = P.g("hips.z") - 0.026 * (0.5 - 0.5 * cos(TAU * beat))            # knee bounce on every beat
        P["head.ry"] = P.g("head.ry") + 4.0 * (0.5 - 0.5 * cos(TAU * beat))
        if t < TURN_B[0]:
            # step-touch: right out and back (beats 1-2), left out and back (beats 3-4), in the body frame
            u = t / TURN_B[0]
            side = sin(TAU * u)
            P["hips.y"] = 0.05 * side
            P["hips.rx"] = -4.0 * side
            P["chest.rz"] = 8.0 * side
            for sd, sg in (("L", 1.0), ("R", -1.0)):
                lift = max(0.0, -sg * side) ** 2
                x, y, yaw = stance_body(sd)
                P["foot.%s.x" % sd] = x
                P["foot.%s.y" % sd] = y + sg * 0.07 * lift
                P["foot.%s.z" % sd] = ANK.z + 0.05 * sin(pi * lift)
                P["foot.%s.yaw" % sd] = yaw
                P["foot.%s.pitch" % sd] = -10.0 * lift
            return rotate_pose(finish(P), 0.0)
        h, o = frame(t)
        Q = rotate_pose(finish(P), h, o)
        put_feet(Q, st, t)
        return Q
    return fn, n


# ------------------------------------------------------------------------------------------------------------------
# feet on the ground: planted in the world between steps
# ------------------------------------------------------------------------------------------------------------------
def stance_body(s, P=R0):
    return (P.g("foot.%s.x" % s), P.g("foot.%s.y" % s), P.g("foot.%s.yaw" % s))


class Stepper:
    """frame(t) -> (h, origin); steps: [(side, t0, t1, t_target, body_pose_or_None)].  A step lifts the foot at t0 and
    puts it down at t1 on its stance place in the body frame at t_target."""

    def __init__(self, frame, steps, lift=0.07, pivot=0.0, pivot_windows=()):
        self.frame = frame
        self.steps = sorted(steps, key=lambda s: s[1])
        self.lift = lift
        self.pivot = pivot          # 0..1: a standing foot turns on its ball by this share of the body turn ...
        self.windows = pivot_windows    # ... inside these time windows only

    def _turned(self, t):
        return sum(self.frame(min(max(t, w0), w1))[0] - self.frame(w0)[0] for w0, w1 in self.windows)

    def planted(self, s, t, P=None):
        h, o = self.frame(t)
        x, y, yaw = stance_body(s, P or R0)
        x, y = rot2(x, y, h)
        return (x + o[0], y + o[1], yaw + h)

    def _pivot(self, pose, t_from, t):
        """A standing foot turned on its ball by pivot x the body turn since t_from (position kept)."""
        if self.pivot <= 0:
            return pose
        dh = self._turned(t) - self._turned(t_from)
        return (pose[0], pose[1], pose[2] + self.pivot * dh)

    def foot(self, s, t):
        """(x, y, z, yaw, pitch) of side s at time t (world)."""
        cur = self.planted(s, 0.0)
        t_land = 0.0
        for (side, t0, t1, tt, P) in self.steps:
            if side != s:
                continue
            if t <= t0:
                break
            cur = self._pivot(cur, t_land, t0)                     # where the standing foot has turned to
            nxt = self.planted(s, tt, P)
            dy = (nxt[2] - cur[2] + 180.0) % 360.0 - 180.0          # the shortest turn (feet are periodic in yaw)
            nxt = (nxt[0], nxt[1], cur[2] + dy)
            if t < t1:
                u = ease((t - t0) / (t1 - t0))
                bump = sin(pi * (t - t0) / (t1 - t0))
                return (lerp(cur[0], nxt[0], u), lerp(cur[1], nxt[1], u), ANK.z + self.lift * bump,
                        lerp(cur[2], nxt[2], u), -10.0 * bump)
            cur = nxt
            t_land = t1
        cur = self._pivot(cur, t_land, t)
        return (cur[0], cur[1], ANK.z, cur[2], 0.0)


def put_feet(Q, st, t, air=None):
    """Feet from the stepper (world); air: {side: (weight, world pose (x, y, z, yaw), rel, rp)} blends to a tuck."""
    for s in ("L", "R"):
        x, y, z, yaw, pitch = st.foot(s, t)
        rel, rp, kb = 0.0, 0.0, 0.0
        if air and s in air and air[s][0] > 0:
            w, (ax, ay, az, ayaw), r_rel, r_rp = air[s]
            ayaw = yaw + ((ayaw - yaw + 180.0) % 360.0 - 180.0)         # the shortest way (yaw is periodic)
            x, y, z, yaw = lerp(x, ax, w), lerp(y, ay, w), lerp(z, az, w), lerp(yaw, ayaw, w)
            pitch = lerp(pitch, 0.0, w)
            rel, rp, kb = r_rel * w, r_rp, w
        Q["foot.%s.x" % s], Q["foot.%s.y" % s], Q["foot.%s.z" % s] = x, y, z
        Q["foot.%s.yaw" % s] = yaw
        Q["foot.%s.pitch" % s] = pitch
        Q["foot.%s.rel" % s] = rel
        Q["foot.%s.rp" % s] = rp
        Q["knee.%s.body" % s] = kb
    return Q


# ------------------------------------------------------------------------------------------------------------------
# robot_dance_c (8 s): prep, pirouette on the left foot, land, arm circle with a squat, isolations, bow, R0
# ------------------------------------------------------------------------------------------------------------------
PIVOT = Vector((0.11, 0.0, N.BALL_JOINT.z))      # the left ball of the foot in the pirouette (body frame); 8 cm
                                                   # forward: the turned-out knee stays clear of the pole behind
SPIN_C = (0.90, 2.18)                              # the turn


def spin_h(t, t0, t1, total=-360.0, ramp=0.22):
    """Heading over a turn: accelerate for ramp of the time, constant, decelerate (trapezoid speed)."""
    if t <= t0:
        return 0.0
    if t >= t1:
        return total
    u = (t - t0) / (t1 - t0)
    r = ramp
    vmax = 1.0 / (1.0 - r)
    if u < r:
        d = 0.5 * vmax * u * u / r
    elif u > 1 - r:
        d = 1.0 - 0.5 * vmax * (1 - u) ** 2 / r
    else:
        d = 0.5 * vmax * r + vmax * (u - r)
    return total * d


def dance_c_upper():
    """Upper body keys (body frame), 8 s."""
    Pprep = arms(body(hips__z=-0.060, hips__x=0.06, head__ry=-3.0), "LR", dict(SECOND, ua=(72.0, -10.0, 0.0)))
    Prise = arms(body(hips__z=0.030, hips__x=0.080, head__ry=-2.0), "LR", FIFTH)
    Pland = arms(body(hips__z=-0.070, head__ry=2.0), "LR", SECOND)
    Pup = arms(body(hips__z=-0.050, head__ry=-12.0, chest__ry=-6.0), "LR", UP)
    Pwide = arms(body(hips__z=-0.140, head__ry=0.0), "LR", V)
    Psq = arms(body(hips__z=-0.230, hips__x=-0.03, chest__ry=12.0, head__ry=6.0), "LR", OUT_DOWN)
    Prise2 = arms(body(hips__z=-0.050), "LR", OUT)
    Pbox_l = arms(body(hips__z=-0.050, chest__rz=14.0, head__rz=20.0), "LR", BOX)
    Pbox_r = arms(body(hips__z=-0.050, chest__rz=-14.0, head__rz=-20.0), "LR", BOX)
    Pbox_c = arms(body(hips__z=-0.050, head__ry=10.0), "LR", BOX)
    Pbow = arms(arms(body(hips__z=-0.040, hips__ry=16.0, spine__ry=10.0, chest__ry=10.0, head__ry=8.0), "R", ACROSS),
                "L", dict(ua=(26.0, 30.0, 0.0), fa=(0.0, -8.0, 0.0), hd=(0.0, 0.0, 0.0)))
    ks = [(0.00, R0, True), (0.45, Pprep, True), (0.90, Prise, True), (2.18, Prise, True), (2.75, Pland, True),
          (3.05, Pland, False), (3.48, Pup, False), (3.90, Pwide, False), (4.40, Psq, False), (4.95, Prise2, True),
          (5.30, Pbox_c, True), (5.55, Pbox_l, True), (5.75, Pbox_l, True), (6.05, Pbox_r, True), (6.25, Pbox_r, True),
          (6.55, Pbox_c, True), (7.05, Pbow, True), (7.30, Pbow, True), (7.85, R0, True)]
    return [(t, finish(Pose(P)), {"hold": h}) for t, P, h in ks]


def dance_c_fn():
    fn_u, n = keyed_clip(dance_c_upper(), loop=True, length=8.0)
    # the left foot moves to the pivot and back; the right foot lifts into passe and comes down
    pivot_pose = Pose(R0)
    ank = ankle_from_pivot(PIVOT, N.BALL_JOINT, 0.0, 0.0)
    L_piv = (ank.x, ank.y, 0.0)

    def fn(f):
        t = f / FPS
        h = spin_h(t, *SPIN_C)
        Pb = Pose(fn_u(f))
        # left foot (body frame): stance -> pivot (0.15..0.5), relevé (0.6..0.85 up, 2.15..2.35 down), back (2.5..2.9)
        lx, ly, lyaw = stance_body("L")
        u_in = seg(t, 0.15, 0.50) * (1 - seg(t, 2.50, 2.90))
        bump_in = sin(pi * max(0.0, min(1.0, (t - 0.15) / 0.35))) + sin(pi * max(0.0, min(1.0, (t - 2.5) / 0.4)))
        rel = seg(t, 0.60, 0.85) * (1 - seg(t, 2.15, 2.35))
        if rel > 0:
            a = ankle_from_pivot(PIVOT, N.BALL_JOINT, 38.0 * rel, 0.0)
            fx, fy, fz, fyaw, fp = a.x, a.y, a.z, 0.0, 38.0 * rel
            toe = -38.0 * rel
        else:
            fx, fy = lerp(lx, L_piv[0], u_in), lerp(ly, L_piv[1], u_in)
            fz, fyaw, fp = ANK.z + 0.05 * bump_in, lerp(lyaw, 0.0, u_in), -8.0 * bump_in
            toe = 0.0
        set_foot(Pb, "L", (fx, fy, fz), pitch=fp, yaw=fyaw, knee_out=3.0, toe=toe)
        # right foot: passe from 0.62 to 2.20 (lift 0.62..0.85, down 2.20..2.45)
        rx_, ry_, ryaw = stance_body("R")
        up = seg(t, 0.50, 0.86) * (1 - seg(t, 2.18, 2.62))
        passe = Vector((0.075, -0.015, 0.47))
        x = lerp(rx_, passe.x, up)
        y = lerp(ry_, passe.y, up)
        z = lerp(ANK.z, passe.z + (Pb.g("hips.z") - 0.03), up)
        # world values for the right side (set_foot would mirror them)
        Pb["foot.R.x"], Pb["foot.R.y"], Pb["foot.R.z"] = x, y, z
        Pb["foot.R.pitch"] = 0.0
        Pb["foot.R.yaw"] = lerp(ryaw, 24.0, up)
        Pb["knee.R.out"] = -lerp(3.0, 42.0, up)
        Pb["foot.R.rel"] = up
        Pb["foot.R.rp"] = 40.0
        Pb["knee.R.body"] = 0.0
        # the squat (3.85..4.95): knees out
        iso = seg(t, 4.95, 5.25) * (1 - seg(t, 6.40, 6.70))
        Pb["hips.z"] = Pb.g("hips.z") - 0.024 * iso * (0.5 - 0.5 * cos(TAU * t / 0.5))   # knee bounce on every beat
        sq = seg(t, 3.9, 4.4) * (1 - seg(t, 4.5, 4.95))
        for s in ("L", "R"):
            Pb["knee.%s.out" % s] = Pb.g("knee.%s.out" % s) + 14.0 * sq
        # turn about the pivot (the ball of the left foot), not the body origin
        px, py = rot2(PIVOT.x, PIVOT.y, h)
        return rotate_pose(Pb, h, (PIVOT.x - px, PIVOT.y - py))
    return fn, n


# ------------------------------------------------------------------------------------------------------------------
# robot_pole (8 s)
# ------------------------------------------------------------------------------------------------------------------
PB_GRIP = (0.16, -0.28)                  # the pole in the body frame while gripping: front right, 18 cm from the shoulder
POLE_T = dict(turn=(0.0, 1.40), swing=(1.40, 1.90), spin=(1.90, 3.4), land=(3.4, 3.7), lean=(3.7, 5.4),
              back=(5.55, 6.85), show=(6.85, 8.0))
H_GRIP, H_SWING, H_SPIN, H_LAND = 240.0, 210.0, -90.0, -120.0


def pole_heading(t):
    T = POLE_T
    if t < T["turn"][1]:
        return spin_h(t, *T["turn"], total=H_GRIP, ramp=0.25)
    if t < T["swing"][1]:
        return lerp(H_GRIP, H_SWING, seg(t, *T["swing"]))
    if t < T["spin"][1]:
        t0, t1 = T["spin"]
        return H_SWING + spin_h(t, t0, t1, total=H_SPIN - H_SWING, ramp=0.18)
    if t < T["land"][1]:
        return lerp(H_SPIN, H_LAND, seg(t, *T["land"]))
    if t < T["back"][0]:
        return H_LAND
    if t < T["back"][1]:
        return H_LAND + spin_h(t, *T["back"], total=-360.0 - H_LAND, ramp=0.25)
    return -360.0


def pole_pb(t):
    """The pole position in the body frame."""
    a1 = degrees(atan2(PB_GRIP[1], PB_GRIP[0]))                       # front right (-60 deg)
    r0, r1 = abs(POLE_LOCAL[0]), (PB_GRIP[0] ** 2 + PB_GRIP[1] ** 2) ** 0.5
    if t < POLE_T["back"][0]:
        u = seg(t, *POLE_T["turn"])
        a = lerp(180.0, a1, u)                                        # behind -> left -> front -> front right
    else:
        u = 1.0 - seg(t, *POLE_T["back"])
        a = lerp(180.0, a1, u)                                        # front right -> front -> left -> behind
    bump = 0.15 if t < POLE_T["back"][0] else 0.18                   # wider on the way round (clear of arms, legs)
    r = lerp(r0, r1, u) + bump * sin(pi * u)
    a = radians(a)
    return (r * cos(a), r * sin(a))


def pole_frame(t):
    h = pole_heading(t)
    px, py = pole_pb(t)
    x, y = rot2(-px, -py, h)
    return h, (POLE_LOCAL[0] + x, POLE_LOCAL[1] + y)


def grip(P, s, pb, z, hips_dz=0.0, w=1.0, off=0.0, offn=0.0):  # noqa: E302
    """Side s grips the pole at body-frame point (pb, z): thumb up, palm towards the pole (from the shoulder)."""
    sg = 1.0 if s == "L" else -1.0
    sh = Vector((N.SH_JOINT.x, sg * N.SH_JOINT.y, N.SH_JOINT.z + hips_dz))
    d = Vector((pb[0] - sh.x, pb[1] - sh.y, 0.0)).normalized()     # the fingers: from the shoulder to the pole
    up = Vector((0.0, 0.0, 1.0))                                    # the thumb: up the pole
    n = up.cross(d) if s == "R" else d.cross(up)                 # R: thumb = d x n; L: thumb = n x d
    g = Vector((pb[0], pb[1], z))
    wrist = g - d * 0.060 - n * 0.059 + d * off + n * offn
    mir = (lambda v: Vector((v.x, -v.y, v.z))) if s == "R" else (lambda v: v)
    set_arm_ik(P, s, tuple(mir(wrist)), tuple(mir(d)), tuple(mir(n)), w=w)
    P["arm.%s.ik" % s] = w
    elbow_to(P, s, GRIP_ELBOW[s], 0.8 * w)
    return P


GRIP_ELBOW = {"R": (0.0, -0.5, -0.87), "L": (0.2, 0.4, -0.9)}
# thumb up for the left hand, down for the right: both fists then open towards the front, so both hands meet the pole
# from in front of the body (clear of the pole as it sweeps round the right side in the turn)
GRIP_THUMB = {"R": 1.0, "L": 1.0}
AWAY = (0.0, -0.12)        # the hand beside the pole, 12 cm off it along the palm normal
OFF = 0.085                # beside the pole, level with the grip: the wrist then slides on along the fingers
# per side: IK weight in (the target starts ON the FK arm), a curve (through ctrl) to AWAY, onto the pole; the
# release in reverse; the IK weight goes out where the target is back on the FK arm.
REACH = {
    # the right hand rises along the right side of the body (the fist opens at the heel: it meets the pole from the
    # right and behind); the left hand crosses in front of the chest
    "R": dict(w_in=(0.26, 0.56), path=(0.40, 1.42), on=(1.42, 1.62), off=(4.96, 5.24), back=(5.24, 6.12),
              w_out=(6.00, 6.42), ctrl_in=(0.06, -0.42, 1.24), ctrl_out=(0.02, -0.47, 1.20)),
    "L": dict(w_in=(1.00, 1.24), path=(1.10, 1.58), on=(1.58, 1.76), off=(3.60, 3.86), back=(3.86, 4.60),
              w_out=(4.57, 4.67), ctrl_in=(0.32, 0.08, 1.12), ctrl_out=(0.30, 0.28, 1.26)),
}


def pole_lean(t):
    return seg(t, 4.0, 4.6) * (1 - seg(t, 5.1, 5.6))


def grip_z(s, t):
    """Grip heights: the hands slide 6 cm down in the spin; the right one 6 cm more for the lean (the arm keeps a bend)."""
    z = {"R": 1.72, "L": 1.23}[s] - 0.06 * seg(t, 1.6, 3.3)
    if s == "R":
        z -= 0.06 * pole_lean(t)
    return z


def world_hand_q(s, d, n):
    """Hand quaternion for side s with the fingers along d and the palm facing n (character space)."""
    sg = 1.0 if s == "L" else -1.0
    mir = (lambda v: Vector((v[0], -v[1], v[2]))) if s == "R" else (lambda v: Vector(v))
    wx, wy, wz = A.hand_world_euler(tuple(mir(d)), tuple(mir(n)))
    return N.qeuler(wx * sg, wy, wz * sg)


# the right hand turns through "palm down, fingers forward" on its way to and from the pole: a plain slerp passes an
# orientation where the palm normal lies along the forearm, where the solver cannot place the forearm twist
MID_Q = {}


def turn_q(s, q0, q1, u):
    def sl(a, b, x):
        return a.slerp(b if a.dot(b) >= 0 else -b, x)
    if s not in MID_Q:
        return sl(q0, q1, u)
    m = world_hand_q(s, *MID_Q[s])
    return sl(q0, m, u / 0.5) if u < 0.5 else sl(m, q1, (u - 0.5) / 0.5)      # u is eased already


def bez(a, c, b, u):
    return a * (1 - u) ** 2 + c * (2 * u * (1 - u)) + b * (u * u)


def arm_target(P, s):
    w = Vector((P.g("arm.%s.x" % s), P.g("arm.%s.y" % s), P.g("arm.%s.z" % s)))
    q = N.qeuler(P.g("hand.%s.wx" % s), P.g("hand.%s.wy" % s), P.g("hand.%s.wz" % s))
    return w, q


def set_target(P, s, w, q, weight, elbow_w=0.0):
    P["arm.%s.ik" % s] = weight
    P["arm.%s.x" % s], P["arm.%s.y" % s], P["arm.%s.z" % s] = w.x, w.y, w.z
    e = q.to_euler("XYZ")
    P["hand.%s.wx" % s], P["hand.%s.wy" % s], P["hand.%s.wz" % s] = degrees(e.x), degrees(e.y), degrees(e.z)
    P["arm.%s.pole" % s] = 0.0
    P["arm.%s.chest" % s] = 0.0
    if elbow_w > 0:
        elbow_to(P, s, GRIP_ELBOW[s], elbow_w)
    return P


def reach(Pb, s, t):
    """Side s of the body-frame pose Pb: FK, or IK along the reach / grip / release of REACH[s]."""
    R_ = REACH[s]
    weight = seg(t, *R_["w_in"]) * (1.0 - seg(t, *R_["w_out"]))
    if weight <= 0:
        return Pb
    Pf = Pose(Pb)
    Pf["arm.%s.ik" % s] = 0.0
    fk_w, fk_q = arm_target(fill_arm_targets(Pf, (s,)), s)             # the wrist and hand of the FK arm
    pb = pole_pb(t)
    dz = Pb.g("hips.z")

    def grip_at(off, offn, at=None):
        G = grip(Pose(Pb), s, pb if at is None else pole_pb(at), grip_z(s, t), dz, w=1.0, off=off, offn=offn)
        return arm_target(G, s)
    if t < R_["path"][1]:                                              # hanging -> beside the pole (where it will be)
        u = seg(t, *R_["path"])
        gw, gq = grip_at(*AWAY, at=R_["path"][1])
        w = bez(fk_w, Vector(R_["ctrl_in"]), gw, u)
        q = turn_q(s, fk_q, gq, u)
        el = 0.8 * u
    elif t < R_["off"][0]:                                             # AWAY -> OFF -> on the pole (and held)
        u = seg(t, *R_["on"])
        w, q = grip_at(lerp(AWAY[0], 0.0, u), lerp(AWAY[1], 0.0, u))
        el = 0.8
    elif t < R_["back"][0]:                                            # off the pole -> OFF -> AWAY
        u = seg(t, *R_["off"])
        w, q = grip_at(lerp(0.0, AWAY[0], u), lerp(0.0, AWAY[1], u))
        el = 0.8
    else:                                                              # beside the pole (where it was) -> the FK arm
        u = seg(t, *R_["back"])
        gw, gq = grip_at(*AWAY, at=R_["back"][0])
        w = bez(gw, Vector(R_["ctrl_out"]), fk_w, u)
        q = turn_q(s, gq, fk_q, u)
        el = 0.8 * (1 - u)
    return set_target(Pb, s, w, q, weight, el * weight)


def pole_upper():
    """Body-frame keys of the pole clip: torso and FK arm shapes (the IK reaches go on top in pole_fn)."""
    turn = arms(body(hips__z=-0.03, chest__rz=-14.0, chest__rx=4.0, head__rz=-20.0, head__ry=-6.0), "LR", DOWN)
    swing = add(turn, hips__z=-0.06)
    hang = arms(body(hips__z=-0.20, chest__rz=-16.0, chest__rx=8.0, spine__rx=4.0, head__rz=-12.0, head__ry=4.0),
                "LR", DOWN)
    hang2 = add(hang, hips__z=-0.06, head__ry=-8.0)
    landed = arms(body(hips__z=-0.12, chest__rz=-10.0, head__ry=2.0), "LR", DOWN)
    lean = arms(arms(body(hips__z=-0.04, spine__rx=-7.0, chest__rx=-8.0, chest__rz=-8.0, head__rx=-6.0,
                          head__rz=24.0, head__ry=-10.0), "L", PRESENT), "R", DOWN)
    lean_hi = arms(Pose(lean), "L", dict(ua=(128.0, -14.0, 0.0), fa=(0.0, -10.0, 0.0), hd=(0.0, 6.0, 0.0)))
    vpose = arms(body(hips__z=-0.02, head__ry=-8.0), "LR", dict(V, ua=(100.0, -8.0, 0.0)))
    ks = [(0.00, R0, True), (0.35, add(turn, chest__rz=8.0, head__rz=10.0), False), (1.20, turn, False),
          (1.65, swing, False), (2.18, hang, False), (3.30, hang2, False), (3.55, landed, False),
          (3.95, add(landed, hips__z=0.09), False), (4.62, lean, False), (5.10, lean_hi, True),
          (5.24, lean_hi, False), (6.12, arms(body(hips__z=-0.03, head__rz=10.0), "LR", DOWN), False),
          (6.80, arms(body(hips__z=-0.02), "LR", DOWN), False), (7.35, vpose, True), (7.48, vpose, True),
           (7.95, R0, True)]
    return [(tt, finish(Pose(P)), {"hold": h}) for tt, P, h in ks]


POLE_STEPS = [("L", 0.04, 0.32, 0.36, None), ("R", 0.30, 0.60, 0.64, None), ("L", 0.58, 0.88, 0.92, None),
              ("R", 0.86, 1.16, 1.20, None), ("L", 1.14, 1.38, 1.40, None),
              ("L", 3.10, 3.11, 3.70, None), ("R", 3.10, 3.11, 3.70, None),       # landing targets (set in the air)
              ("R", 5.52, 5.88, 5.94, None), ("L", 5.86, 6.22, 6.26, None), ("R", 6.14, 6.52, 6.56, None),
              ("L", 6.44, 6.88, 6.85, None), ("R", 6.80, 7.14, 6.85, None)]
AIR = {"L": (1.76, 2.16), "R": (1.80, 2.22)}          # take-off (tuck) windows; landing LAND


LAND = (3.28, 3.70)


def pole_fn():
    fn_u, n = keyed_clip(pole_upper(), loop=True, length=8.0)
    st = Stepper(pole_frame, POLE_STEPS, pivot=0.8, pivot_windows=(POLE_T["turn"], POLE_T["back"]))

    def fn(f):
        t = f / FPS
        h, o = pole_frame(t)
        Pb = Pose(fn_u(f)) if t < 7.95 else Pose(R0)      # the last key is R0 (raw triples: no wrap spin)
        dz = Pb.g("hips.z")
        for s in ("R", "L"):
            Pb = reach(Pb, s, t)
        Q = rotate_pose(Pb, h, o)
        air = {}
        for s, (bx, by) in (("L", (0.10, 0.075)), ("R", (0.14, -0.045))):
            w = seg(t, *AIR[s]) * (1 - seg(t, *LAND))
            if w <= 0:
                continue
            x, y = rot2(bx, by, h)
            air[s] = (w, (x + o[0], y + o[1], dz + 0.50, h + (6.0 if s == "L" else -12.0)), 1.0, 34.0)
        put_feet(Q, st, t, air)
        return Q
    return fn, n


# ------------------------------------------------------------------------------------------------------------------
def robot_clips():
    """[(name, fn, frames, info)]"""
    out = []
    fn, n = idle_fn()
    out.append(("robot_idle", fn, n, dict(kind="loop", note="servo idle between shows")))
    fn, n = dance_a_fn()
    out.append(("robot_dance_a", fn, n, dict(kind="loop", bpm=120, note="popping: hits on the beat, holds")))
    fn, n = dance_b_fn()
    out.append(("robot_dance_b", fn, n, dict(kind="loop", bpm=120, note="step routine: step-touch with running-man "
                                                                         "arms, then a full turn in four pivot steps")))
    fn, n = dance_c_fn()
    out.append(("robot_dance_c", fn, n, dict(kind="loop", bpm=120, note="pirouette, arm circle and squat, "
                                             "isolations, bow; stays within 0.3 m of the origin")))
    fn, n = pole_fn()
    out.append(("robot_pole", fn, n, dict(kind="loop", note="acrobatic: grip, a tucked spin once round the pole, "
                                          "land, lean, release, V pose; needs the pole at pole_local")))
    return out
