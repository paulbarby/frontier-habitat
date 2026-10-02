"""
Frontier Habitat 5.0 - ART-NPC: the v5 planned clips (art/people/v5_clip_plan.md section 3.3), on the v3 rig at
s = 1 (people_anims retargets them per variant).  Every clip is (name, kind, pose_from, pose_to, loop, frames, fn,
meta), fn(frame) -> Pose; loops start and end on their pose state's rest pose (exact seams), one-shots start and end
on STAND (or the state named in pose_to / meta ends_on).

Groups (plan section 4): social, paired, venues, school and cell, falls, children; plus drive_sit (the arcade racer,
ART-B) and mirrored lie clips lie_enter_r / sleep_r / lie_exit_r (ART-B item 4: the right side of a double bed).

Numbers other agents place things by are in FURNITURE (written to people_manifest.json "furniture") and PAIRS
(npc_pairs.json).
"""
import os
import sys
from math import sin, cos, pi, radians, degrees, atan2

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
import npc_anims as A                                            # noqa: E402
from npc_anims import (Pose, add, setp, addsym, set_arm_ik, elbow_to, fill_arm_targets, ik_to_fk, keyed_clip,  # noqa
                       periodic, bump, STAND, SIT, KNEEL, LIE, DEAD, TAU, FPS, ANK, make_gait, mirror_pose, shift_pose)
from npc_common import sym, set_foot                             # noqa: E402

# furniture and props (character space, metres, at s = 1; seats, desks, panels and shelves keep world heights)
FURNITURE = dict(
    bench=dict(seat_z=0.45, back=None, note="park / pool bench, no back; sit_bench (state sit)"),
    lounger=dict(seat_z=0.35, back_deg=40.0, hips_x=-0.10, note="pool lounger: the stand point is beside the "
                 "lounger at the hips, facing along it (+X to the feet); lounge_pool (state lounger)"),
    bunk=dict(top_z=0.45, note="jail bunk: sleep_cell (state bunk), the bed layout of lie / sleep lowered 0.10 m"),
    desk=dict(top_z=0.72, ahead=0.30, note="academy desk; sit_class (state sit, chair 0.46 m)"),
    board=dict(x=0.80, z=1.60, note="teach: the board 0.80 m ahead, its centre 1.60 m high"),
    arcade_panel=dict(ahead=0.40, top_z=0.98, note="upright cabinet control panel: play_arcade (ART-B: please put "
                      "the panel front edge 0.40 m ahead of the stand point, 0.98 m high)"),
    shelf=dict(ahead=0.45, z=1.10, note="shop shelf the hand reaches in shop_browse (prop.R carries the item)"),
    treadmill=dict(belt_z=0.24, note="jog: stand point on the belt 0.24 m up (ART-B)"),
    water=dict(note="swim: the origin is the water surface; the body floats face down along +X"),
)
PAIRS = {
    "handshake": dict(clip_a="handshake", clip_b="handshake", distance_m=0.80, facing_deg=180.0, sync_s=0.0,
                      side_offset_m=0.0, hand_contact=True,
                      note="right hands meet at (0.40, 0, 1.00) from A; prop.R of A and B meet"),
    "kiss_brief": dict(clip_a="kiss_brief", clip_b="kiss_brief", distance_m=0.53, facing_deg=180.0, sync_s=0.0,
                       side_offset_m=0.0, note="adults only; faces meet 0.6-1.2 s, no more"),
    "hold_hands_walk": dict(clip_a="hold_hands_walk", clip_b="hold_hands_walk_r", distance_m=0.0, facing_deg=0.0,
                            sync_s=0.0, side_offset_m=0.50, hand_contact=True, note="B walks at A's left (+Y), the same phase; A's left "
                            "hand holds B's right hand; move both along +X at the walk speed"),
    "slap": dict(clip_a="slap", clip_b="hit_react", distance_m=0.60, facing_deg=180.0, sync_s=0.47,
                 side_offset_m=0.0, note="contact at 0.92 s (A); B plays hit_react 0.47 s later (its hit at 0.45 s)"),
    "punch": dict(clip_a="punch", clip_b="hit_react", distance_m=0.70, facing_deg=180.0, sync_s=0.27,
                  side_offset_m=0.0, note="contact at 0.72 s (A); B plays hit_react 0.27 s later (its hit at 0.45 s)"),
    "escort": dict(clip_a="escort_walk", clip_b="handcuffed_walk", distance_m=0.0, facing_deg=0.0, sync_s=0.0,
                   side_offset_m=0.45, hand_contact=True, note="the prisoner B walks at the escort A's left (+Y), the same phase; A's "
                   "left hand holds B's right upper arm"),
}

ADULT_ONLY = {"kiss_brief", "flirt_lean", "slap", "punch", "hit_react", "fight_idle", "handcuffed_walk", "escort_walk",
              "drink_bar", "sit_bar_stool", "shout", "protest_fist", "sleep_cell", "teach", "argue", "hug"}
CHILD_ONLY = {"child_play", "child_run"}


def _ik(P):
    """A key pose with the arms as FK angles from its IK solution (2026-10-01: FK keys turn smoothly with no IK
    elbow flips between keys; the solver's FK elbow guard keeps the elbows outside the body)."""
    return ik_to_fk(Pose(P))


TIMES = {}           # contact times (s) that the retimed clips publish: slap_contact, punch_contact, hit_s
_LAST = [None]       # the keys of the last _ks call after the retime (clips that publish contact times read them)


def _ks(keys, loop=False, length=None, fk=True, retime=True, pin=()):
    """keyed_clip over [(t, Pose, opts?)]: arms in IK (default, with the elbow guard) or as FK angles (fk=True).
    retime: key intervals stretch until no bone turns more than A.WORLD_STEP_LIMIT deg in one frame (2026-10-02: the
    npc_verify step rule; the poses stay, the timing changes)."""
    ks = [(k[0], ik_to_fk(k[1]) if fk else _ik(k[1]), *k[2:]) for k in keys]
    if retime:
        ks, ln = A.retime_world(ks, loop=loop, length=length, pin=pin)
        length = ln if loop else length
    _LAST[0] = ks
    return keyed_clip(ks, loop=loop, length=length)


def _w(g, u):
    return g(u) - g(0.0)


def _sm(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def _win(t, a, b, c, d):
    """0 before a, up to 1 at b, 1 to c, down to 0 at d (smooth)."""
    if t <= a or t >= d:
        return 0.0
    if t < b:
        return _sm((t - a) / (b - a))
    if t <= c:
        return 1.0
    return 1.0 - _sm((t - c) / (d - c))


# ------------------------------------------------------------------------------------------------------------------
# social
# ------------------------------------------------------------------------------------------------------------------
def talk_idle_fn(n=120):
    """Small talk while standing: small hand shifts, nods at 1.0 s and 2.8 s, weight shift."""
    def fn(f):
        u = f / n
        P = add(STAND,
                hips__y=_w(lambda u: 0.018 * sin(TAU * u), u),
                hips__rx=_w(lambda u: 1.4 * sin(TAU * u), u),
                chest__rz=_w(lambda u: 3.0 * sin(TAU * u + 0.5), u),
                head__rz=_w(lambda u: 6.0 * sin(TAU * u + 0.9), u),
                head__ry=7.0 * bump(u, 0.25, 0.06) + 7.0 * bump(u, 0.70, 0.06),
                neck__ry=2.0 * bump(u, 0.25, 0.06) + 2.0 * bump(u, 0.70, 0.06))
        P = addsym(P, forearm__ry=-6.0 * bump(u, 0.45, 0.14))
        P["forearm.R.ry"] = P.g("forearm.R.ry") - 10.0 * bump(u, 0.15, 0.10)
        P["forearm.L.ry"] = P.g("forearm.L.ry") - 8.0 * bump(u, 0.85, 0.10)
        return P
    return fn, n


def talk_gesture_b_keys():
    """Explaining b: counting on the fingers (1.0), a shrug (2.2), open arms (3.2); loops in 4 s."""
    S = add(STAND, spine__ry=2.0, head__ry=2.0)
    C1 = Pose(S)
    set_arm_ik(C1, "L", (0.250, 0.080, 1.120), (0.8, -0.4, 0.2), (0.0, 0.0, 1.0), w=1.0, pole=-20.0)
    set_arm_ik(C1, "R", (0.235, 0.020, 1.160), (0.7, 0.6, -0.2), (0.0, 0.3, -1.0), w=1.0, pole=-25.0)
    C1.update({"head.ry": 8.0, "neck.ry": 3.0, "head.rz": 4.0})
    C2 = Pose(C1)
    set_arm_ik(C2, "R", (0.240, 0.050, 1.150), (0.7, 0.6, -0.2), (0.0, 0.3, -1.0), w=1.0, pole=-25.0)
    SH = add(S, spine__ry=-1.0, head__rz=-8.0, head__ry=-3.0)
    SH = addsym(SH, shoulder__rx=9.0)
    for s in ("L", "R"):
        set_arm_ik(SH, s, (0.200, 0.270, 1.020), (0.6, 0.8, 0.0), (0.0, -0.3, 1.0), w=1.0, pole=-10.0)
    OP = add(S, chest__ry=-3.0, head__ry=-2.0)
    for s in ("L", "R"):
        set_arm_ik(OP, s, (0.260, 0.380, 1.200), (0.6, 0.8, 0.2), (0.3, -0.3, 1.0), w=1.0, pole=-25.0)
    return _ks([(0.0, S), (0.7, C1), (1.05, C2), (1.4, C1), (2.2, SH), (3.2, OP), (4.0, S)], loop=True, length=4.0)


def listen_nod_fn(n=120):
    """Listening, arms folded: head tilted 8 deg, nods at 0.8, 2.0 and 3.2 s."""
    base = add(STAND, hips__y=0.015, hips__rx=1.2, head__rz=8.0, spine__ry=1.0)
    set_arm_ik(base, "L", (0.175, -0.090, 1.135), (0.10, -1.0, 0.05), (-1.0, 0.0, -0.2), w=1.0, pole=-35.0)
    set_arm_ik(base, "R", (0.160, -0.075, 1.095), (0.10, -1.0, 0.05), (-1.0, 0.0, 0.2), w=1.0, pole=-35.0)
    elbow_to(base, "L", (-0.1, 1.0, -0.3), 0.8)
    elbow_to(base, "R", (-0.1, -1.0, -0.3), 0.8)
    folded = _ik(base)
    # enter and leave the fold inside the loop: 0-0.5 s from stand, 3.6-4.0 s back to stand
    fn_k, _ = keyed_clip([(0.0, _ik(STAND)), (0.6, folded), (3.4, folded), (4.0, _ik(STAND))], loop=True, length=4.0)

    def fn(f):
        u = f / n
        P = fn_k(f)
        nod = bump(u, 0.20, 0.05) + bump(u, 0.50, 0.05) + bump(u, 0.80, 0.05)
        P["head.ry"] = P.g("head.ry") + 8.0 * nod
        P["neck.ry"] = P.g("neck.ry") + 2.0 * nod
        P["head.rz"] = P.g("head.rz") + 8.0 * _win(u, 0.1, 0.2, 0.8, 0.9)
        return P
    return fn, n


def shout_keys():
    """Shouting at someone: lean in (0.3), mouth wide 0.5-1.4 (jaw), the right fist down at 0.9; 2.0 s."""
    S = Pose(STAND)
    L = add(S, hips__x=0.030, spine__ry=10.0, chest__ry=6.0, neck__ry=10.0, head__ry=-12.0)
    L = addsym(L, shoulder__rx=5.0)
    set_arm_ik(L, "R", (0.180, 0.200, 1.330), (0.5, -0.2, 0.8), (0.0, -0.8, 0.3), w=1.0, pole=-10.0)
    set_arm_ik(L, "L", (0.150, 0.230, 1.020), (0.5, -0.3, -0.8), (0.0, -1.0, 0.0), w=1.0, pole=0.0)
    D = Pose(L)
    set_arm_ik(D, "R", (0.300, 0.140, 1.050), (0.8, -0.1, -0.5), (0.0, -1.0, 0.0), w=1.0, pole=-10.0)
    D.update({"spine.ry": 13.0, "neck.ry": 12.0, "head.ry": -10.0, "hips.z": -0.02})
    E = Pose(L)
    set_arm_ik(E, "R", (0.220, 0.190, 1.150), (0.6, -0.1, 0.2), (0.0, -1.0, 0.0), w=1.0, pole=-10.0)
    return _ks([(0.0, S, {"hold": True}), (0.35, L), (0.75, L), (1.00, D), (1.35, E), (1.70, add(S, spine__ry=3.0)),
                (2.15, Pose(STAND), {"hold": True})])


def sulk_fn(n=150):
    """Sulking: shoulders down, head down 15 deg, arms hanging forward, a kick at the floor at 3.0 s; 5 s loop."""
    down = add(STAND, spine__ry=5.0, chest__ry=4.0, neck__ry=6.0, head__ry=10.0, hips__y=-0.02, hips__rx=-1.5)
    down = addsym(down, shoulder__rx=-5.0, shoulder__ry=4.0, upper_arm__ry=-4.0, forearm__ry=-6.0)
    down = fill_arm_targets(down)
    fn_k, _ = keyed_clip([(0.0, Pose(STAND)), (0.8, down), (4.3, down), (5.0, Pose(STAND))], loop=True, length=5.0)

    def fn(f):
        t = f / FPS
        P = fn_k(f)
        k = _win(t, 2.6, 3.0, 3.0, 3.5)
        sw = sin(pi * max(0.0, min(1.0, (t - 2.6) / 0.9)))
        set_foot(P, "R", (ANK.x + 0.10 * k + 0.05 * sw, -0.115, ANK.z + 0.05 * k * sw), pitch=-10.0 * k,
                 yaw=7.0, knee_out=3.0)
        P["foot.R.y"] = -0.115
        P["head.rz"] = P.g("head.rz") + 5.0 * sin(TAU * f / n)
        return P
    return fn, n


def wave_keys():
    """A wave: the right hand up by 0.4 s, three waves (2 Hz) to 1.9 s, down by 2.3 s."""
    S = Pose(STAND)
    U = add(S, chest__rz=4.0, head__rz=-3.0, head__ry=-2.0)
    set_arm_ik(U, "R", (0.110, 0.300, 1.560), (0.05, 0.10, 1.0), (1.0, 0.0, 0.0), w=1.0, pole=-20.0)
    keys = [(0.0, S, {"hold": True}), (0.60, U), (2.10, U), (2.80, Pose(STAND), {"hold": True})]
    fn_k, n = _ks(keys)
    t_up, t_dn = _LAST[0][1][0], _LAST[0][2][0]          # the hand is up / starts down (after the retime)

    def fn(f):
        t = f / FPS
        P = fn_k(f)
        w = _win(t, t_up - 0.05, t_up + 0.10, t_dn - 0.20, t_dn - 0.02)
        P["hand.R.rz"] = P.g("hand.R.rz") + 22.0 * w * sin(TAU * 2.0 * (t - t_up))
        P["forearm.R.rz"] = P.g("forearm.R.rz") + 9.0 * w * sin(TAU * 2.0 * (t - t_up) - 0.4)
        return P
    return fn, n


# ------------------------------------------------------------------------------------------------------------------
# paired
# ------------------------------------------------------------------------------------------------------------------
def handshake_keys():
    """Both partners play it (0.80 m apart, facing): right hands meet at (0.40, 0, 1.00), three pumps to 1.8 s,
    release by 2.1 s."""
    S = Pose(STAND)
    H = add(S, hips__x=0.02, spine__ry=4.0, chest__rz=-4.0, head__ry=2.0)
    set_arm_ik(H, "R", (0.330, 0.020, 1.000), (1.0, -0.05, 0.05), (0.0, -1.0, 0.0), w=1.0, pole=-10.0)
    Up = Pose(H)
    Up["arm.R.z"] = H.g("arm.R.z") + 0.035
    Dn = Pose(H)
    Dn["arm.R.z"] = H.g("arm.R.z") - 0.035
    return _ks([(0.0, S, {"hold": True}), (0.50, H), (0.75, Up), (1.00, Dn), (1.25, Up), (1.50, Dn), (1.80, H),
                (2.10, add(S, hips__x=0.01)), (2.40, Pose(STAND), {"hold": True})])


def kiss_brief_keys():
    """A brief kiss (adults; 0.36 m apart, facing): lean in, heads tilted opposite ways (each to its own right),
    faces meet 0.6-1.2 s, part by 1.7 s; hands on the partner's upper arms.  No more."""
    S = Pose(STAND)
    # heads tilted and moved to each one's own right (side bend): the faces meet beside each other (2026-10-01)
    K = add(S, hips__x=0.005, spine__ry=3.0, chest__ry=2.0, neck__ry=3.0, head__ry=2.0, head__rz=-15.0, neck__rz=-6.0,
            spine__rx=4.0, chest__rx=4.0, neck__rx=4.0, head__rx=6.0)
    for s in ("L", "R"):
        # hands rest on the partner's upper arms, fingers down along them (2026-10-02: they pointed inward, the
        # fingertips went 3 cm into the partner's chest)
        set_arm_ik(K, s, (0.310, 0.200, 1.220), (0.25, -0.05, -0.95), (1.0, 0.0, 0.0), w=1.0, pole=-25.0)
    M = Pose(K)
    M.update({"hips.x": 0.010, "spine.ry": 4.0, "neck.ry": 4.0, "head.ry": 3.0})
    return _ks([(0.0, S, {"hold": True}), (0.60, add(S, hips__x=0.015, spine__ry=2.0)), (0.95, M), (1.50, M),
                (2.05, add(S, hips__x=0.01)), (2.45, Pose(STAND), {"hold": True})])


def _gait_with(upper):
    G = dict(A.WALK)
    G["upper"] = upper
    return G


def hold_hands_upper(phi, P):
    A._walk_upper(phi, P, lean=0.8)
    sw = cos(TAU * (phi - 0.03))
    set_arm_ik(P, "L", (0.020 + 0.035 * sw, 0.215, 0.880), (0.5, 0.35, -0.8), (0.0, 1.0, 0.0), w=1.0, pole=10.0)
    P["head.aim"] = 0.6
    P["head.wz"] = 8.0


def handcuffed_upper(phi, P):
    A._walk_upper(phi, P, arms=False, lean=1.4)
    sym(P, **{"shoulder.rx": -4.0, "shoulder.ry": -6.0})
    for s in ("L", "R"):
        set_arm_ik(P, s, (-0.170, 0.045, 0.960), (-0.3, -1.0, -0.4), (-1.0, 0.0, 0.0), w=1.0, pole=40.0, chest=0.0)
    P["head.aim"] = 0.8
    P["head.wy"] = 16.0


def escort_upper(phi, P):
    A._walk_upper(phi, P, lean=1.0)
    set_arm_ik(P, "L", (-0.020, 0.195, 1.200), (0.1, 0.2, -1.0), (0.0, 1.0, 0.0), w=1.0, pole=-30.0)
    P["head.aim"] = 0.7
    P["head.wz"] = 6.0


def flirt_lean_fn(n=120):
    """Flirting: the weight on the left leg, the right knee in, the left hand on the hip, the head tilted, a light
    laugh at 2.4 s; 4 s loop."""
    L = add(STAND, hips__y=0.055, hips__rx=-5.0, spine__rx=3.0, chest__rx=3.0, head__rz=10.0, head__ry=-4.0,
            chest__rz=-6.0)
    set_foot(L, "R", (ANK.x + 0.06, -0.080, ANK.z + 0.012), yaw=-8.0, knee_out=-6.0, pitch=10.0, toe=-10.0)
    L["foot.R.y"] = -0.080
    set_arm_ik(L, "L", (0.020, 0.262, 1.000), (0.35, -0.3, -0.9), (-0.3, -1.0, 0.0), w=1.0, pole=25.0)
    elbow_to(L, "L", (-0.2, 1.0, 0.1), 0.9)
    base = _ik(L)
    fn_k, _ = keyed_clip([(0.0, _ik(STAND)), (0.7, base), (3.4, base), (4.0, _ik(STAND))], loop=True, length=4.0)

    def fn(f):
        t = f / FPS
        P = fn_k(f)
        lg = _win(t, 2.2, 2.4, 2.6, 2.9)
        P["head.ry"] = P.g("head.ry") - 6.0 * lg
        P["chest.ry"] = P.g("chest.ry") - 2.0 * lg
        P["hips.rz"] = P.g("hips.rz") + 4.0 * sin(TAU * t / 4.0)
        return P
    return fn, n


def slap_keys():
    """A slap (paired with hit_react, 0.60 m): wind-up 0.3 s, the open right hand at the partner's left cheek at
    0.5 s, recoil 0.9 s, stand by 1.5 s."""
    S = Pose(STAND)
    W = add(S, chest__rz=12.0, spine__rz=5.0, head__ry=-2.0)
    set_arm_ik(W, "R", (0.080, 0.380, 1.420), (0.3, 0.3, 0.9), (1.0, 0.0, 0.0), w=1.0, pole=-30.0)
    elbow_to(W, "R", (-0.3, -1.0, 0.1), 1.0)
    C = add(S, hips__x=0.030, chest__rz=-14.0, spine__rz=-6.0, spine__ry=4.0, head__ry=-3.0)
    set_arm_ik(C, "R", (0.420, 0.030, 1.520), (0.3, -0.4, 0.85), (0.0, -1.0, 0.1), w=1.0, pole=-20.0)
    elbow_to(C, "R", (0.1, -1.0, -0.2), 1.0)
    Mid = add(S, chest__rz=4.0, spine__rz=2.0)
    set_arm_ik(Mid, "R", (0.220, 0.460, 1.450), (0.6, 0.3, 0.6), (1.0, 0.0, 0.0), w=1.0, pole=-20.0)
    elbow_to(Mid, "R", (0.0, -1.0, 0.1), 1.0)
    R = add(S, chest__rz=-6.0, hips__x=0.01)
    set_arm_ik(R, "R", (0.300, 0.050, 1.300), (0.5, -0.6, 0.3), (0.0, -1.0, 0.0), w=1.0, pole=-10.0)
    elbow_to(R, "R", (0.2, -1.0, -0.6), 1.0)
    r = _ks([(0.0, S, {"hold": True}), (0.55, W), (0.75, Mid), (0.92, C), (1.30, R), (1.95, Pose(STAND), {"hold": True})])
    TIMES["slap_contact"] = _LAST[0][3][0]
    return r


def punch_keys():
    """A clumsy punch (paired with hit_react, 0.70 m): guard, wind-up 0.25 s, the right fist at the partner's
    chest at 0.45 s, recover by 0.9 s, stand by 1.5 s."""
    S = Pose(STAND)
    G = add(S, hips__z=-0.03, chest__rz=10.0, hips__rz=4.0)
    set_foot(G, "L", (ANK.x + 0.10, 0.130, ANK.z), yaw=6.0, knee_out=4.0)
    set_arm_ik(G, "R", (0.130, 0.220, 1.300), (0.7, -0.3, 0.3), (0.0, -1.0, 0.3), w=1.0, pole=-40.0)
    set_arm_ik(G, "L", (0.240, 0.140, 1.380), (0.5, -0.4, 0.6), (0.0, -1.0, 0.0), w=1.0, pole=-30.0)
    elbow_to(G, "R", (-0.5, -1.0, -0.5), 1.0)
    elbow_to(G, "L", (0.1, 1.0, -0.8), 1.0)
    C = add(S, hips__x=0.050, hips__z=-0.03, chest__rz=-16.0, hips__rz=-8.0, spine__ry=6.0)
    set_foot(C, "L", (ANK.x + 0.14, 0.130, ANK.z), yaw=6.0, knee_out=4.0)
    set_arm_ik(C, "R", (0.520, 0.020, 1.300), (1.0, 0.0, 0.0), (0.0, -0.6, -0.8), w=1.0, pole=-50.0)
    set_arm_ik(C, "L", (0.230, 0.150, 1.320), (0.5, -0.4, 0.6), (0.0, -1.0, 0.0), w=1.0, pole=-30.0)
    elbow_to(C, "R", (-0.2, -1.0, -0.6), 1.0)
    elbow_to(C, "L", (0.1, 1.0, -0.8), 1.0)
    R = add(S, hips__x=0.02, chest__rz=-4.0)
    set_foot(R, "L", (ANK.x + 0.06, 0.125, ANK.z), yaw=6.0, knee_out=3.0)
    r = _ks([(0.0, S, {"hold": True}), (0.42, G), (0.72, C), (1.15, R), (1.80, Pose(STAND), {"hold": True})])
    TIMES["punch_contact"] = _LAST[0][2][0]
    return r


def hit_react_keys():
    """Taking a hit at 0.45 s: the head snaps aside, a step back (0.15 m), the left hand to the face, recovery;
    stand by 1.5 s."""
    S = Pose(STAND)
    H = add(S, hips__x=-0.060, head__rz=16.0, neck__rz=6.0, head__ry=-8.0, spine__ry=-4.0, chest__rz=8.0)
    B = add(S, hips__x=-0.090, hips__z=-0.02, head__rz=10.0, spine__ry=4.0)
    set_foot(B, "R", (ANK.x - 0.150, -0.120, ANK.z), yaw=10.0, knee_out=3.0)
    B["foot.R.y"] = -0.120
    set_arm_ik(B, "L", (0.150, 0.100, 1.520), (0.1, -0.5, 0.9), (-1.0, -0.3, 0.0), w=1.0, pole=-20.0)
    elbow_to(B, "L", (0.2, 1.0, -0.5), 1.0)
    Rc = add(S, hips__x=-0.030, head__rz=4.0)
    set_foot(Rc, "R", (ANK.x - 0.060, -0.118, ANK.z), yaw=8.0, knee_out=3.0)
    Rc["foot.R.y"] = -0.118
    r = _ks([(0.0, S, {"hold": True}), (0.40, S), (0.55, H), (0.98, B), (1.35, Rc), (1.70, Pose(STAND), {"hold": True})])
    TIMES["hit_s"] = _LAST[0][2][0] - 0.10
    return r


# ------------------------------------------------------------------------------------------------------------------
# falls and fights
# ------------------------------------------------------------------------------------------------------------------
def fall_down_keys():
    """Knees buckle (0.3 s), a side fall (0.9 s), on the ground (like collapse, shorter); ends on dead frame 0."""
    ks = A.collapse_keys()
    times = [0.0, 0.25, 0.55, 0.95, 1.22, 1.45]
    return [(t,) + tuple(k[1:]) for t, k in zip(times, ks)]


def get_up_keys():
    """From the ground (dead frame 0): onto the elbow and knees (0.8 s), one knee (1.5 s), up (2.1 s), stand."""
    ck = [k[1] for k in A.collapse_keys()]           # S0, K1 stagger, K2 on knees, K3 tipping, K4 impact, DEAD
    K3 = Pose(ck[3])
    K2 = Pose(ck[2])
    K2["arm.L.y"], K2["arm.R.y"] = 0.200, -0.200       # hands on the thighs a little wider (2026-10-02: forearm in the hip)
    ONE = Pose(KNEEL)
    for s in ("L", "R"):
        ONE["arm.%s.ik" % s] = 0.0
    sym(ONE, **{"upper_arm.ry": -22.0, "upper_arm.rx": -5.0, "forearm.ry": -35.0})
    ONE.update({"spine.ry": 10.0, "chest.ry": 5.0, "neck.ry": 2.0, "head.ry": 2.0})
    ONE = fill_arm_targets(ONE)
    HALF = add(Pose(STAND), hips__z=-0.10, hips__x=-0.04, hips__ry=9.0, spine__ry=7.0, hips__y=0.02)
    set_foot(HALF, "R", (-0.24, -0.115, 0.150), pitch=24.0, yaw=4.0, toe=-24.0, knee_out=0.0)
    HALF["foot.R.y"] = -0.115
    HALF = fill_arm_targets(HALF)
    # the first key is the dead pose WITH the fingertip lift people_fix gives it (the arms here become FK angles before
    # the retarget, so the lift would be lost: the hands sank 2 cm into the floor, m2 and c2)
    D0 = Pose(DEAD)
    for s_ in ("L", "R"):
        if D0.g("arm.%s.ik" % s_) > 0:
            D0["arm.%s.z" % s_] = D0.g("arm.%s.z" % s_) + 0.022
    return [(0.0, D0, {"hold": True}), (0.55, K3), (1.10, K2), (1.65, ONE), (2.15, HALF),
            (2.50, Pose(STAND), {"hold": True})]


def fight_idle_fn(n=60):
    """Fists up, the left foot forward, a bounce at 2 Hz; 2 s loop."""
    G = add(STAND, hips__z=-0.045, hips__x=0.0, chest__rz=12.0, hips__rz=6.0, spine__ry=6.0, neck__ry=4.0,
            head__ry=-8.0)
    set_foot(G, "L", (ANK.x + 0.14, 0.140, ANK.z), yaw=10.0, knee_out=5.0)
    set_foot(G, "R", (ANK.x - 0.10, -0.140, ANK.z), yaw=25.0, knee_out=5.0)
    G["foot.R.y"] = -0.140
    set_arm_ik(G, "L", (0.250, 0.140, 1.390), (0.35, -0.25, 0.90), (0.0, -1.0, 0.0), w=1.0, pole=-40.0)
    set_arm_ik(G, "R", (0.220, 0.140, 1.370), (0.35, -0.25, 0.90), (0.0, -1.0, 0.0), w=1.0, pole=-40.0)
    elbow_to(G, "L", (0.1, 1.0, -0.8), 1.0)
    elbow_to(G, "R", (0.1, -1.0, -0.8), 1.0)
    g = _ik(G)
    fn_k, _ = keyed_clip([(0.0, _ik(STAND)), (0.70, g), (1.30, g), (2.0, _ik(STAND))], loop=True, length=2.0)

    def fn(f):
        u = f / n
        P = fn_k(f)
        w = _win(u, 0.15, 0.25, 0.75, 0.85)
        P["hips.z"] = P.g("hips.z") - 0.018 * w * (0.5 - 0.5 * cos(2 * TAU * u))
        P["head.rz"] = P.g("head.rz") + 4.0 * w * sin(TAU * u)
        return P
    return fn, n


def protest_fist_keys():
    """At a protest: the right fist raised beside the head (the elbow out and down), pumped twice (1 Hz) while the
    person shouts; about 2.4 s loop.  2026-10-02: the arm is keyed as a raised fist in IK (the old FK pose swung the
    arm across the chest, 1.5-3 cm into the torso)."""
    S = Pose(STAND)
    UP = add(S, spine__ry=-2.0, chest__ry=-3.0, head__ry=-8.0, chest__rz=-3.0)
    set_arm_ik(UP, "R", (0.110, 0.285, 1.700), (0.05, 0.05, 1.0), (-0.3, -0.9, 0.0), w=1.0, pole=-20.0)
    elbow_to(UP, "R", (0.0, -1.0, -0.35), 1.0)
    HI = add(UP, head__ry=-5.0, chest__ry=-2.0, hips__z=-0.006)
    set_arm_ik(HI, "R", (0.120, 0.280, 1.835), (0.05, 0.05, 1.0), (-0.3, -0.9, 0.0), w=1.0, pole=-20.0)
    elbow_to(HI, "R", (0.0, -1.0, -0.35), 1.0)
    return _ks([(0.0, S), (0.50, UP), (0.74, HI), (0.98, UP), (1.28, UP), (1.52, HI), (1.76, UP)], loop=True, length=2.4)


# ------------------------------------------------------------------------------------------------------------------
# venues
# ------------------------------------------------------------------------------------------------------------------
def sit_bench_fn(n=150):
    """On a bench with no back (0.45 m): from the sit rest pose lean forward, forearms on the thighs, look round,
    back to the rest pose; 5 s loop."""
    F = Pose(SIT)
    F.update({"spine.ry": 24.0, "chest.ry": 8.0, "hips.ry": 2.0, "neck.ry": -14.0, "head.ry": -8.0})
    for s in ("L", "R"):
        set_arm_ik(F, s, (0.130, 0.120, 0.660), (0.8, -0.4, -0.3), (0.0, 0.3, -1.0), w=1.0, pole=0.0)
    fn_k, _ = keyed_clip([(0.0, Pose(SIT)), (0.9, F), (4.2, F), (5.0, Pose(SIT))], loop=True, length=5.0)

    def fn(f):
        t = f / FPS
        P = fn_k(f)
        w = _win(t, 0.9, 1.2, 3.9, 4.2)
        P["head.rz"] = P.g("head.rz") + 18.0 * w * sin(TAU * (t - 0.9) / 3.3)
        return P
    return fn, n


def drink_bar_fn(n=150):
    """At the bar on a stool: the glass (prop.R) comes up from the counter 1.0-1.6 s, a drink (head back), down by
    2.2 s; otherwise as sit_bar_stool."""
    import people_anims as PA
    base = PA.sit_bar_stool_base()
    B = PA.BAR_STOOL
    up = Pose(base)
    set_arm_ik(up, "R", (0.220, 0.080, 1.400), (-0.1, -0.5, 0.85), (-0.9, -0.2, 0.3), w=1.0, pole=-30.0)
    elbow_to(up, "R", (0.5, -0.8, -0.4), 1.0)
    up["arm.R.stiff"] = 0.0
    up.update({"head.ry": -12.0, "neck.ry": -5.0})
    bf, uf = _ik(base), _ik(up)
    fn_k, _ = keyed_clip([(0.0, bf), (1.0, bf), (1.6, uf), (1.9, uf), (2.4, bf), (5.0, bf)], loop=True, length=5.0)

    def fn(f):
        t = f / FPS
        P = fn_k(f)
        P["head.rz"] = P.g("head.rz") + 10.0 * sin(TAU * t / 5.0) * _win(t, 2.4, 2.8, 4.4, 4.9)
        return P
    return fn, n


def _turned(P, th):
    """The whole standing body turned by th degrees about the vertical through the origin (a pivot turn): hips turn
    and the foot targets (with their yaw) go round with it."""
    Q = Pose(P)
    c, s_ = cos(radians(th)), sin(radians(th))
    Q["hips.rz"] = Q.g("hips.rz") + th
    hx, hy = Q.g("hips.x"), Q.g("hips.y")
    Q["hips.x"], Q["hips.y"] = hx * c - hy * s_, hx * s_ + hy * c
    for sd in ("L", "R"):
        x, y = Q.g("foot.%s.x" % sd), Q.g("foot.%s.y" % sd)
        Q["foot.%s.x" % sd], Q["foot.%s.y" % sd] = x * c - y * s_, x * s_ + y * c
        Q["foot.%s.yaw" % sd] = Q.g("foot.%s.yaw" % sd) + (th if sd == "L" else -th)
    return Q


def dance_b_fn(n=120):
    """120 bpm two-step: step right and close (beats 1-2), step left and close (3-4), repeat; the arms swing across
    the body; a knee dip on every beat."""
    base = fill_arm_targets(add(STAND, hips__z=-0.030))
    for s in ("L", "R"):
        base["arm.%s.ik" % s] = 0.0
    sym(base, **{"upper_arm.rx": -18.0, "upper_arm.ry": 12.0, "forearm.ry": -70.0, "forearm.rz": 20.0})
    base = fill_arm_targets(base)

    def fn(f):
        t = f / n
        beat = 8.0 * t
        dip = 0.5 + 0.5 * cos(TAU * beat)
        side = sin(TAU * t * 2 - pi / 2) * 0.5 + 0.5          # 0 -> 1 -> 0 twice (right, then left)
        side = 2.0 * side - 1.0
        P = Pose(base)
        P["hips.y"] = -0.080 * side
        P["hips.z"] = base.g("hips.z") - 0.035 * dip
        P["hips.rx"] = 5.0 * side
        P["chest.rz"] = 10.0 * sin(TAU * t * 2)
        P["spine.rz"] = 4.0 * sin(TAU * t * 2)
        P["head.ry"] = -2.0 + 5.0 * dip
        for s, sg in (("L", 1.0), ("R", -1.0)):
            lead = max(0.0, -sg * side)                        # this foot leads the step
            set_foot(P, s, (ANK.x + 0.03 * lead, sg * (0.125 + 0.10 * lead) - 0.080 * side * 0.0, ANK.z +
                            0.035 * sin(pi * lead)), yaw=8.0, knee_out=4.0 + 5.0 * lead, pitch=-8.0 * lead)
            P["foot.%s.y" % s] = sg * (0.125 + 0.10 * lead)
            ph = TAU * t * 2 + (0.0 if s == "L" else pi)
            P["upper_arm.%s.rz" % s] = base.g("upper_arm.%s.rz" % s) + sg * 22.0 * sin(ph)
            P["upper_arm.%s.ry" % s] = base.g("upper_arm.%s.ry" % s) + 12.0 * cos(ph)
        return P
    return fn, n


def dance_c_fn(n=120):
    """120 bpm (the Konami egg dance, V5 4.5): a bounce on every beat, both arms up on beats 4 and 8, a half turn
    over beats 5-6 and back over beats 7-8."""
    base = fill_arm_targets(add(STAND, hips__z=-0.030))
    for s in ("L", "R"):
        base["arm.%s.ik" % s] = 0.0
    sym(base, **{"upper_arm.rx": -24.0, "forearm.ry": -60.0})
    base = fill_arm_targets(base)

    def fn(f):
        t = f / n
        beat = 8.0 * t
        dip = 0.5 + 0.5 * cos(TAU * beat)
        P = Pose(base)
        P["hips.z"] = base.g("hips.z") - 0.040 * dip
        P["head.ry"] = -3.0 + 6.0 * dip
        P["chest.ry"] = 3.0 * dip
        up = _win(beat, 2.2, 3.1, 3.4, 4.1) + _win(beat, 5.9, 6.8, 7.1, 7.9)      # (rises 0.9 beat: < 15 deg/f)
        for s, sg in (("L", 1.0), ("R", -1.0)):
            P["upper_arm.%s.rx" % s] = base.g("upper_arm.%s.rx" % s) + sg * 95.0 * up
            P["upper_arm.%s.ry" % s] = base.g("upper_arm.%s.ry" % s) - 20.0 * up
            P["forearm.%s.ry" % s] = base.g("forearm.%s.ry" % s) + 40.0 * up
            # (2026-10-02: no shoulder key: the solver's shoulder rhythm lifts the clavicles with the arms)
            set_foot(P, s, (ANK.x, sg * 0.135, ANK.z + 0.008), yaw=8.0, knee_out=5.0)
            P["foot.%s.y" % s] = sg * 0.135
        th = 120.0 * (_sm((beat - 3.6) / 2.4) if beat < 6.0 else 1.0 - _sm((beat - 6.0) / 1.95))
        th = th if beat >= 3.6 else 0.0
        return _turned(P, th)
    return fn, n


def swim_fn(n=40):
    """Breaststroke, face down along +X at the water line (the origin is the water surface): arms sweep out and
    back, then glide forward; the legs draw up and kick back; the head lifts to breathe at the pull.  1.33 s loop."""
    def fn(f):
        u = f / n
        P = Pose()
        P["hips.x"] = -0.30
        P["hips.z"] = -0.985
        P["hips.ry"] = 82.0 + 3.0 * sin(TAU * u)
        P["spine.ry"] = -8.0 - 6.0 * bump(u, 0.35, 0.25)
        P["chest.ry"] = -8.0 - 6.0 * bump(u, 0.35, 0.25)
        P["neck.ry"] = -28.0 - 14.0 * bump(u, 0.35, 0.22)
        P["head.ry"] = -20.0 - 10.0 * bump(u, 0.35, 0.22)
        P["hips.z"] = P.g("hips.z") + 0.03 * bump(u, 0.40, 0.25)
        # arms: glide (forward), sweep out, pull in to the chest, extend (u)
        for s in ("L", "R"):
            if u < 0.30:
                k = u / 0.30
                wr = (0.78 - 0.10 * k, 0.12 + 0.25 * _sm(k), -0.06 - 0.02 * k)
            elif u < 0.55:
                k = (u - 0.30) / 0.25
                wr = (0.68 - 0.24 * _sm(k), 0.37 - 0.25 * _sm(k), -0.08 - 0.06 * sin(pi * k))
            else:
                k = (u - 0.55) / 0.45
                wr = (0.44 + 0.34 * _sm(k), 0.12, -0.08 + 0.02 * _sm(k))
            sw_ = sin(pi * min(1.0, u / 0.55))
            set_arm_ik(P, s, wr, (1.0, 0.25 * sw_, -0.1), (0.0, 0.4 * sw_, -1.0), w=1.0, pole=-60.0)
        # legs: extended (u < 0.35), draw up to the hips (0.35-0.65), kick out and together (0.65-1)
        for s, sg in (("L", 1.0), ("R", -1.0)):
            if u < 0.35:
                k = 0.0
            elif u < 0.65:
                k = _sm((u - 0.35) / 0.30)
            else:
                k = 1.0 - _sm((u - 0.65) / 0.35)
            x = -1.18 + 0.42 * k
            y = sg * (0.10 + 0.22 * k)
            set_foot(P, s, (x, y, -0.06 + 0.10 * k), knee_out=0.0)
            P["foot.%s.y" % s] = y
            P["foot.%s.rel" % s] = 1.0
            P["foot.%s.rp" % s] = 45.0 - 35.0 * k
            P["knee.%s.body" % s] = 0.6
        return P
    return fn, n


def lounge_pool_fn(n=150):
    """On a pool lounger (seat 0.35 m, back raised 40 deg): reclined, legs out, the right hand behind the head, the
    left on the belly; slow breathing and a look round; 5 s loop (state lounger)."""
    fr = FURNITURE["lounger"]
    B = Pose()
    B["hips.x"] = fr["hips_x"]
    B["hips.z"] = (fr["seat_z"] + 0.115) - 0.98
    B["hips.ry"] = -48.0
    B["spine.ry"] = 4.0
    B["chest.ry"] = 2.0
    B["neck.ry"] = 22.0
    B["head.ry"] = 18.0
    for s, sg in (("L", 1.0), ("R", -1.0)):
        set_foot(B, s, (0.62, sg * 0.13, fr["seat_z"] + 0.075), knee_out=2.0)
        B["foot.%s.y" % s] = sg * 0.13
        B["foot.%s.rel" % s] = 1.0
        B["foot.%s.rp" % s] = 10.0
        B["knee.%s.body" % s] = 0.5
    set_foot(B, "R", (0.46, -0.16, fr["seat_z"] + 0.16), knee_out=0.0)
    B["foot.R.y"] = -0.16
    set_arm_ik(B, "R", (-0.330, 0.140, 1.080), (-0.2, 0.9, 0.2), (1.0, 0.0, 0.2), w=1.0, pole=60.0)
    set_arm_ik(B, "L", (0.020, 0.080, 0.600), (0.4, -0.9, 0.0), (0.2, 0.0, -1.0), w=1.0, pole=10.0)

    def fn(f):
        u = f / n
        P = add(B, chest__ry=_w(lambda u: -1.0 * sin(TAU * u), u), head__rz=_w(lambda u: 14.0 * sin(TAU * u + 0.6), u))
        return P
    return fn, n


def jog_gait():
    G = dict(A.RUN)
    G.update(frames=24, stride=1.60, hips_curve=lambda phi: 0.012 * cos(2 * TAU * (phi - 0.165 - 0.25)),
             feet={s: A._foot(off, 0.40, 0.235, p_hs=8.0, p_to=36.0, hs_end=0.06, flat_end=0.18, clear=0.20,
                              lift_skew=0.7, lift_pow=0.9, swing_pitch=2.0, toe_relax=0.5, swing_out=0.015, y=0.10,
                              yaw=4.0, to_pow=1.3) for s, off in (("L", 0.0), ("R", 0.5))})
    return G


def child_run_gait():
    G = dict(A.RUN)
    G.update(frames=18, stride=1.80)
    return G


def play_arcade_fn(n=120):
    """At an upright cabinet: the left hand on the stick, the right on the buttons (taps), the body moves with the
    game; 4 s loop (panel FURNITURE['arcade_panel'])."""
    pz, ax = FURNITURE["arcade_panel"]["top_z"], FURNITURE["arcade_panel"]["ahead"]
    P = Pose(STAND)
    P.update({"hips.x": 0.010, "hips.ry": 3.0, "spine.ry": 6.0, "chest.ry": 3.0, "neck.ry": 8.0, "head.ry": 4.0})
    set_arm_ik(P, "L", (ax - 0.055, 0.110, pz + 0.070), (0.6, -0.1, 0.6), (-0.3, -0.9, 0.0), w=1.0, pole=-45.0)
    set_arm_ik(P, "R", (ax - 0.040, 0.050, pz + 0.075), (1.0, 0.1, -0.35), (0.0, 0.3, -1.0), w=1.0, pole=-45.0)
    P["arm.L.stiff"] = P["arm.R.stiff"] = 1.0
    tap = A.typing(P, n, taps=(("R", 0.08), ("R", 0.16), ("R", 0.31), ("R", 0.44), ("R", 0.52), ("R", 0.66),
                               ("R", 0.81), ("R", 0.90)), move=(("L", 0.3, 0.012, 0.02), ("L", 0.7, -0.01, -0.02)))

    def fn(f):
        u = f / n
        Q = tap(f)
        Q["chest.rz"] = Q.g("chest.rz") + 4.0 * sin(2 * TAU * u)
        Q["hips.y"] = Q.g("hips.y") + 0.01 * sin(TAU * u)
        return Q
    return fn, n


def shop_browse_keys():
    """Browsing a shelf (FURNITURE['shelf']): look (0-1.0), reach and pick an item (prop.R) at 1.5 s, look at it,
    put it back at 3.5 s, look along the shelf; 5 s loop."""
    sh = FURNITURE["shelf"]
    S = add(STAND, neck__ry=6.0, head__ry=6.0, head__rz=12.0, chest__rz=4.0)
    R = add(STAND, hips__x=0.02, spine__ry=6.0, neck__ry=4.0, head__ry=2.0, chest__rz=-4.0)
    set_arm_ik(R, "R", (sh["ahead"] - 0.10, 0.060, sh["z"]), (1.0, 0.1, 0.0), (0.0, 1.0, 0.0), w=1.0, pole=-20.0)
    L = add(STAND, neck__ry=12.0, head__ry=14.0)
    set_arm_ik(L, "R", (0.220, 0.040, 1.200), (0.3, 0.8, 0.3), (-0.3, 0.2, 0.9), w=1.0, pole=-25.0)
    return _ks([(0.0, S), (0.9, S), (1.65, R), (2.25, L), (2.95, L), (3.55, R), (4.25, add(STAND, head__rz=-14.0,
                                                                                         neck__ry=5.0)),
                (5.0, S)], loop=True, length=5.0)


def sit_class_fn(n=150):
    """At a school desk (FURNITURE['desk']): writing with the right hand, the left hand on the paper; looks up to
    the teacher at 2.6-3.4 s; from and back to the sit rest pose; 5 s loop."""
    dk = FURNITURE["desk"]
    W = Pose(SIT)
    W.update({"spine.ry": 14.0, "chest.ry": 6.0, "neck.ry": 10.0, "head.ry": 14.0})
    set_arm_ik(W, "L", (dk["ahead"] - 0.02, 0.140, dk["top_z"] + 0.045), (1.0, -0.3, -0.3), (0.0, 0.2, -1.0), w=1.0,
               pole=-30.0)
    set_arm_ik(W, "R", (dk["ahead"] - 0.03, 0.040, dk["top_z"] + 0.055), (0.9, 0.3, -0.4), (0.0, 0.5, -1.0), w=1.0,
               pole=-35.0)
    U = Pose(W)
    U.update({"neck.ry": 0.0, "head.ry": -6.0, "spine.ry": 8.0})
    fn_k, _ = keyed_clip([(0.0, _ik(SIT)), (0.8, _ik(W)), (2.5, _ik(W)), (2.8, _ik(U)), (3.4, _ik(U)), (3.7, _ik(W)),
                          (4.3, _ik(W)), (5.0, _ik(SIT))], loop=True, length=5.0)

    def fn(f):
        t = f / FPS
        P = fn_k(f)
        wr = _win(t, 0.8, 1.0, 2.4, 2.6) + _win(t, 3.7, 3.9, 4.2, 4.4)
        P["forearm.R.rz"] = P.g("forearm.R.rz") + 4.0 * wr * sin(TAU * 3.0 * t)
        P["hand.R.rx"] = P.g("hand.R.rx") + 6.0 * wr * sin(TAU * 3.0 * t + 0.7)
        return P
    return fn, n


def teach_keys():
    """Teaching: point at the board (FURNITURE['board']) with the right hand, then turn to the class with open
    hands and back; 5 s loop."""
    bd = FURNITURE["board"]
    S = Pose(STAND)
    Pt = add(S, head__ry=-8.0, neck__ry=-4.0, chest__rz=-4.0)
    set_arm_ik(Pt, "R", (0.380, 0.150, 1.420), (0.9, -0.1, 0.4), (0.0, 1.0, 0.0), w=1.0, pole=-40.0)
    Tn = add(S, hips__rz=18.0, spine__rz=16.0, chest__rz=22.0, head__rz=20.0, neck__ry=2.0)
    for s in ("L", "R"):
        set_arm_ik(Tn, s, (0.200, 0.260, 1.080), (0.6, 0.8, 0.1), (0.0, -0.5, 0.8), w=1.0, pole=-10.0)
    return _ks([(0.0, S), (0.9, Pt), (2.1, Pt), (2.9, Tn), (3.9, Tn), (5.0, S)], loop=True, length=5.0)


def sleep_cell_fn(n=180):
    """sleep on the jail bunk (FURNITURE['bunk']: 0.45 m, 0.10 m under the bed): the sleep loop moved down."""
    fn0, _ = A.sleep_fn(n)
    dz = FURNITURE["bunk"]["top_z"] - A.FURNITURE["bed_z"]

    def fn(f):
        return shift_pose(fn0(f), (0.0, 0.0, dz))
    return fn, n


HAND_LIFT = 0.0
HR_X, HR_Y = -0.250, 0.240
HAND_OUT = 0.30


def sleep_turn_keys():
    """Sleep, turning over (Paul 2026-10-01): from the left side onto the back (2.3 s), a few breaths, back onto
    the left side; every bone under 4.5 deg per frame (retimed).  Starts and ends on sleep frame 0."""
    bz = A.FURNITURE["bed_z"]
    S0 = Pose(LIE)
    SUP = Pose()
    SUP.update({"hips.x": -0.505, "hips.y": 0.060, "hips.z": -0.252, "hips.rx": -90.0, "hips.ry": -90.0,
                "spine.ry": 2.0, "chest.ry": 1.0, "neck.ry": 10.0, "head.ry": 4.0, "head.rz": 8.0})
    for s, dx in (("L", 0.105), ("R", -0.105)):
        set_foot(SUP, s, (-0.505 + dx, 0.0, bz + 0.108), knee_out=0.0)
        SUP["foot.%s.y" % s] = -0.83
        SUP["knee.%s.body" % s] = 1.0
        SUP["foot.%s.rel" % s] = 1.0
        SUP["foot.%s.rp" % s] = 30.0
    # the hands rest on the belly, the elbows on the mattress beside the body
    set_arm_ik(SUP, "L", (-0.450, -0.020, bz + 0.360), (0.6, -0.8, 0.0), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    elbow_to(SUP, "L", (1.0, 0.2, -0.6), 1.0)
    set_arm_ik(SUP, "R", (-0.560, 0.000, bz + 0.360), (-0.6, -0.8, 0.0), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    SUP["arm.R.y"] = 0.000
    elbow_to(SUP, "R", (-1.0, 0.2, -0.6), 1.0)
    H = Pose({k: 0.5 * (S0.g(k) + SUP.g(k)) for k in set(S0) | set(SUP)})
    H["hips.z"] = H.g("hips.z") + 0.012          # (2026-10-02: 0.02 lifted m3 0.5 cm over the 3.5 cm band)
    set_arm_ik(H, "R", (HR_X, -HR_Y, bz + 0.360), (0.3, -0.9, 0.0), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    elbow_to(H, "R", (0.0, 0.2, 1.0), 1.0)             # the top elbow goes over the top while rolling (no flip)
    # the left hand crosses above the belly while the body rolls (2026-10-02: the forearm went through the torso)
    sv = A.solver()
    hs, hu = sv.solve(S0)[2]["hand.L"], sv.solve(SUP)[2]["hand.L"]
    hm = (hs + hu) * 0.5
    set_arm_ik(H, "L", (hm.x + HAND_OUT, hm.y, hm.z + HAND_LIFT), (0.6, -0.8, 0.0), (0.0, 0.0, -1.0), w=1.0, pole=0.0)
    elbow_to(H, "L", (1.0, 0.2, -0.3), 1.0)
    SUP2 = add(SUP, chest__ry=-1.5, head__rz=-6.0)
    keys = [(0.0, S0, {"hold": True}), (1.2, H), (2.3, SUP), (4.4, SUP2), (5.6, H), (6.8, Pose(LIE), {"hold": True})]
    return A.retime_keys(A.fk_keys(keys))


def child_play_fn(n=120):
    """(children) crouched, playing with a toy on the floor (prop.R), a jump at 3.0 s; 4 s loop."""
    C = add(STAND, hips__z=-0.36, hips__x=-0.10, hips__ry=28.0, spine__ry=14.0, chest__ry=6.0, neck__ry=-12.0,
            head__ry=-8.0)
    for s, sg in (("L", 1.0), ("R", -1.0)):
        set_foot(C, s, (ANK.x + 0.02, sg * 0.14, ANK.z), yaw=14.0, knee_out=14.0)
        C["foot.%s.y" % s] = sg * 0.14
    set_arm_ik(C, "R", (0.300, 0.050, 0.200), (0.9, 0.2, -0.3), (0.0, 0.3, -1.0), w=1.0, pole=-20.0)
    set_arm_ik(C, "L", (0.260, 0.160, 0.220), (0.9, -0.2, -0.3), (0.0, -0.3, -1.0), w=1.0, pole=-20.0)
    Cs = _ik(C)
    J = add(STAND, hips__z=0.05, spine__ry=-4.0, head__ry=-10.0)
    J = addsym(J, upper_arm__rx=24.0, upper_arm__ry=24.0, forearm__ry=-18.0)      # (2026-10-02: < 15 deg/frame)
    J = fill_arm_targets(J)
    for s, sg in (("L", 1.0), ("R", -1.0)):
        set_foot(J, s, (ANK.x, sg * 0.125, ANK.z + 0.10), pitch=20.0, yaw=7.0, knee_out=3.0)
        J["foot.%s.y" % s] = sg * 0.125
    fn_k, _ = keyed_clip([(0.0, _ik(STAND)), (0.6, Cs), (2.3, Cs), (2.65, add(Cs, hips__z=0.10)), (3.1, _ik(J)),
                          (3.42, _ik(add(STAND, hips__z=-0.05))), (4.0, _ik(STAND))], loop=True, length=4.0)

    def fn(f):
        t = f / FPS
        P = fn_k(f)
        w = _win(t, 0.6, 0.8, 2.1, 2.3)
        P["forearm.R.ry"] = P.g("forearm.R.ry") - 8.0 * w * sin(TAU * t * 0.8)
        P["hand.R.rz"] = P.g("hand.R.rz") + 12.0 * w * cos(TAU * t * 0.8)
        return P
    return fn, n


# ------------------------------------------------------------------------------------------------------------------
_CACHE = []


def v5_clips():
    """[(name, kind, pose_from, pose_to, loop, frames, fn, meta)] at s = 1, without the face overlays (built once
    per run: the clips do not depend on the body; people_anims.retarget adapts them)."""
    if not _CACHE:
        _CACHE.extend(_v5_clips())
    return list(_CACHE)


def _v5_clips():
    out = []

    def add_(name, kind, pf, pt, loop, fn, n, meta=None):
        out.append((name, kind, pf, pt, loop, n, fn, dict(meta or {})))

    def gait(name, G, extra=None):
        frames = make_gait(G)
        n = G["frames"]
        meta = dict(speed_mps=round(G["stride"] / (n / FPS), 4), stride_m=G["stride"])
        meta.update(extra or {})
        out.append((name, "loop", "stand", "stand", True, n, (lambda fr: (lambda f: fr[f]))(frames), meta))
        return frames

    fn, n = talk_idle_fn()
    add_("talk_idle", "loop", "stand", "stand", True, fn, n)
    fn, n = talk_gesture_b_keys()
    add_("talk_gesture_b", "loop", "stand", "stand", True, fn, n)
    fn, n = listen_nod_fn()
    add_("listen_nod", "loop", "stand", "stand", True, fn, n)
    fn, n = shout_keys()
    add_("shout", "oneshot", "stand", "stand", False, fn, n)
    fn, n = sulk_fn()
    add_("sulk", "loop", "stand", "stand", True, fn, n)
    fn, n = wave_keys()
    add_("wave", "oneshot", "stand", "stand", False, fn, n)
    fn, n = handshake_keys()
    add_("handshake", "oneshot", "stand", "stand", False, fn, n, dict(pair="handshake"))
    fn, n = kiss_brief_keys()
    add_("kiss_brief", "oneshot", "stand", "stand", False, fn, n, dict(pair="kiss_brief", adults_only=True))
    frames = gait("hold_hands_walk", _gait_with(hold_hands_upper), dict(pair="hold_hands_walk"))
    out.append(("hold_hands_walk_r", "loop", "stand", "stand", True, len(frames) - 1,
                (lambda fr: (lambda f: mirror_pose(fr[f])))(frames),
                dict(pair="hold_hands_walk", mirror_of="hold_hands_walk", speed_mps=out[-1][7]["speed_mps"],
                     stride_m=out[-1][7]["stride_m"])))
    fn, n = flirt_lean_fn()
    add_("flirt_lean", "loop", "stand", "stand", True, fn, n, dict(adults_only=True))
    fn, n = slap_keys()
    add_("slap", "oneshot", "stand", "stand", False, fn, n, dict(pair="slap", contact_s=round(TIMES["slap_contact"], 2)))
    fn, n = punch_keys()
    add_("punch", "oneshot", "stand", "stand", False, fn, n, dict(pair="punch", contact_s=round(TIMES["punch_contact"], 2)))
    fn, n = hit_react_keys()
    add_("hit_react", "oneshot", "stand", "stand", False, fn, n, dict(hit_s=round(TIMES["hit_s"], 2)))
    for nm, key in (("slap", "slap_contact"), ("punch", "punch_contact")):       # B's hit lands when A's hand does
        pr = PAIRS[nm]
        pr["sync_s"] = round(TIMES[key] - TIMES["hit_s"], 2)
        pr["note"] = ("contact at %.2f s (A); B plays hit_react %.2f s later (its hit at %.2f s)" %
                      (TIMES[key], pr["sync_s"], TIMES["hit_s"]))
    fn, n = keyed_clip(fall_down_keys())
    add_("fall_down", "oneshot", "stand", "lie", False, fn, n, dict(ends_on="dead", fall=True))
    fn, n = _ks(get_up_keys())
    add_("get_up", "exit", "lie", "stand", False, fn, n, dict(starts_on="dead"))
    fn, n = fight_idle_fn()
    add_("fight_idle", "loop", "stand", "stand", True, fn, n)
    fn, n = protest_fist_keys()
    add_("protest_fist", "loop", "stand", "stand", True, fn, n)
    gait("handcuffed_walk", _gait_with(handcuffed_upper), dict(pair="escort"))
    gait("escort_walk", _gait_with(escort_upper), dict(pair="escort"))
    fn, n = sit_bench_fn()
    add_("sit_bench", "loop", "sit", "sit", True, fn, n, dict(furniture="bench"))
    fn, n = drink_bar_fn()
    add_("drink_bar", "loop", "stool", "stool", True, fn, n, dict(furniture="bar_stool", prop="glass on prop.R"))
    fn, n = dance_b_fn()
    add_("dance_b", "loop", "stand", "stand", True, fn, n, dict(bpm=120))
    fn, n = dance_c_fn()
    add_("dance_c", "loop", "stand", "stand", True, fn, n, dict(bpm=120, egg="Konami dance (V5 4.5)"))
    fn, n = swim_fn()
    add_("swim", "loop", "water", "water", True, fn, n, dict(furniture="water", speed_mps=0.8))
    fn, n = lounge_pool_fn()
    add_("lounge_pool", "loop", "lounger", "lounger", True, fn, n, dict(furniture="lounger"))
    gait("jog", jog_gait(), dict(furniture="treadmill"))
    fn, n = play_arcade_fn()
    add_("play_arcade", "loop", "stand", "stand", True, fn, n, dict(furniture="arcade_panel"))
    fn, n = shop_browse_keys()
    add_("shop_browse", "loop", "stand", "stand", True, fn, n, dict(furniture="shelf", prop="item on prop.R"))
    fn, n = sit_class_fn()
    add_("sit_class", "loop", "sit", "sit", True, fn, n, dict(furniture="desk"))
    fn, n = teach_keys()
    add_("teach", "loop", "stand", "stand", True, fn, n, dict(furniture="board"))
    fn, n = sleep_cell_fn()
    add_("sleep_cell", "loop", "bunk", "bunk", True, fn, n, dict(furniture="bunk"))
    fn, n = keyed_clip(sleep_turn_keys())
    add_("sleep_turn", "oneshot", "lie", "lie", False, fn, n, dict(furniture="bed", note="turns onto the back and "
                                                                "back; play it now and then inside sleep"))
    fn, n = child_play_fn()
    add_("child_play", "loop", "stand", "stand", True, fn, n, dict(children_only=True, prop="toy on prop.R"))
    gait("child_run", child_run_gait(), dict(children_only=True))
    # the arcade racer (ART-B: PRISM SHIFT is a sit-down racer that uses drive_sit) and the right side of a bed
    base = {c[0]: c for c in A.all_clips()}
    c = base["drive_sit"]
    out.append(("drive_sit", c[1], "vehicle", "vehicle", c[4], c[5], c[6], dict(c[7], note="arcade racer seat")))
    for nm in ("lie_enter", "sleep", "lie_exit"):
        c = base[nm]
        out.append((nm + "_r", c[1], c[2], c[3], c[4], c[5], (lambda g: (lambda f: mirror_pose(g(f))))(c[6]),
                    dict(c[7], mirror_of=nm, note="the right side of a double bed: the head to -Y")))
    return out
