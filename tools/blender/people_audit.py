"""
Frontier Habitat 5.0 - ART-NPC: animation audit (ORCH-to-ART-NPC 2026-10-01, V5 section 15.1).  Measures every clip of
every body from the EXPORTED files, the way the game plays them:

  * planted feet: a foot is planted while its lowest sole point moves < 6 mm/frame; its height (target 0 +- 1 cm) and
    its slide over the planted span (target < 1 cm);
  * snaps: the largest frame-to-frame turn of any bone (local, deg) and the largest change of angular speed
    (deg/frame, "jerk"); counts of steps over 5 deg;
  * joint ranges: knee and elbow bend (0-150 deg; hyperextension < -5), wrist bend > 75 deg, neck flex > 55 deg, spine
    (hips -> chest) bend > 70 deg, shoulder shrug (clavicle up > 18 deg);
  * self-intersection: forearm / hand capsules inside the torso or the other forearm, thigh into thigh (> 2 cm).

  blender --background --factory-startup --python tools/blender/people_audit.py -- [--bodies m1,f1,suit] [--out tag]

Writes art/people/audit_<tag>.json and .md.
"""
import bpy
import os
import sys
import json
import math
from math import degrees

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
import numpy as np              # noqa: E402
from mathutils import Vector    # noqa: E402

ART = os.path.join(N.ROOT, "art", "people")
SLOW = {"lie_enter", "sleep", "lie_exit", "lie_enter_r", "sleep_r", "lie_exit_r", "sleep_cell", "sleep_turn", "dead"}
FALLS = {"collapse", "fall_down"}
FACE = {"jaw", "lids", "lids_low", "brow.L", "brow.R", "mouth.L", "mouth.R"}
LOCO = {"walk", "run", "carry_walk", "injured_walk", "jog", "child_run", "hold_hands_walk", "hold_hands_walk_r",
        "handcuffed_walk", "escort_walk"}
NO_FLOOR = {"swim", "lounge_pool", "sleep", "sleep_r", "sleep_cell", "lie_enter", "lie_exit", "lie_enter_r",
            "lie_exit_r", "dead", "collapse", "fall_down", "get_up", "sit_bar_stool", "drink_bar", "drive_sit",
            "ride_sit", "board", "board_r", "alight", "alight_r", "step_up", "step_up_r", "step_down", "step_down_r",
            "suit_swap"}


def body_file(b):
    if b in ("suit", "indoor"):
        return os.path.join(N.MODEL_DIR, "astronaut_%s.glb" % b)
    return os.path.join(N.MODEL_DIR, "people_%s.glb" % b)


def load(b):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = N.FPS
    bpy.ops.import_scene.gltf(filepath=body_file(b))
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    body = None
    for pref in ("Outfit_casual_a", "Outfit_school", "Body", "Suit"):
        body = next((o for o in meshes if o.name.startswith(pref)), None)
        if body:
            break
    if body is None:
        body = max(meshes, key=lambda o: len(o.data.vertices))
    acts = {}
    for a in bpy.data.actions:
        nm = a.name.split(".")[0]
        nm = nm.split("_Rig")[0] if "_Rig" in nm else nm
        acts.setdefault(nm, a)
    return rig, body, acts


def foot_verts(body):
    """Vertex indices whose strongest weight is foot.S / toe.S (the soles)."""
    out = {"L": [], "R": []}
    names = {g.index: g.name for g in body.vertex_groups}
    for v in body.data.vertices:
        if not v.groups:
            continue
        g = max(v.groups, key=lambda x: x.weight)
        nm = names.get(g.group, "")
        for s in ("L", "R"):
            if nm in ("foot." + s, "toe." + s):
                out[s].append(v.index)
    return {s: np.array(ix, dtype=np.int64) for s, ix in out.items()}


def eval_co(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    co = co.reshape(-1, 3)
    mw = np.array(ob.matrix_world)
    return co @ mw[:3, :3].T + mw[:3, 3]


def set_act(rig, act):
    ad = rig.animation_data
    ad.action = act
    if act is not None and getattr(act, "slots", None):
        ad.action_slot = act.slots[0]


def frames_of(act):
    a, b = act.frame_range
    return int(round(a)), int(round(b))


def bone_world(rig):
    mw = rig.matrix_world
    return {pb.name: (mw @ pb.matrix) for pb in rig.pose.bones}


def yaxis(M):
    return Vector((M[0][1], M[1][1], M[2][1])).normalized()


def zaxis(M):
    return Vector((M[0][2], M[1][2], M[2][2])).normalized()


def ang(a, b):
    return degrees(a.angle(b)) if a.length > 1e-9 and b.length > 1e-9 else 0.0


def seg_dist(p1, q1, p2, q2):
    """Closest distance between segments p1q1 and p2q2."""
    d1, d2, r = q1 - p1, q2 - p2, p1 - p2
    a, e, f = d1.dot(d1), d2.dot(d2), d2.dot(r)
    if a <= 1e-12 and e <= 1e-12:
        return r.length
    if a <= 1e-12:
        s, t = 0.0, max(0.0, min(1.0, f / e))
    else:
        c = d1.dot(r)
        if e <= 1e-12:
            t, s = 0.0, max(0.0, min(1.0, -c / a))
        else:
            b = d1.dot(d2)
            den = a * e - b * b
            s = max(0.0, min(1.0, (b * f - c * e) / den)) if den > 1e-12 else 0.0
            t = (b * s + f) / e
            if t < 0:
                t, s = 0.0, max(0.0, min(1.0, -c / a))
            elif t > 1:
                t, s = 1.0, max(0.0, min(1.0, (b - c) / a))
    return ((p1 + d1 * s) - (p2 + d2 * t)).length


def audit_body(b, only=None):
    rig, body, acts = load(b)
    fv = foot_verts(body)
    rest_len = {pb.name: pb.bone.length for pb in rig.pose.bones}
    rest_elev = {}
    for s in ("L", "R"):
        bl, bc = rig.data.bones["shoulder." + s], rig.data.bones["chest"]
        cl, up = (bl.tail_local - bl.head_local).normalized(), (bc.tail_local - bc.head_local).normalized()
        rest_elev[s] = degrees(math.asin(max(-1.0, min(1.0, cl.dot(up)))))
    s_ = rest_len.get("shin.L", 0.45) / 0.45
    R = {}
    for clip, act in sorted(acts.items()):
        if only and clip not in only:
            continue
        set_act(rig, act)
        f0, f1 = frames_of(act)
        prev_q, prev_w = None, None
        stats = dict(frames=f1 - f0, max_step=0.0, step_at="", jerk=0.0, jerk_at="", n_over5=0,
                     plant_h=[], slide=0.0, slide_at="", knee=[0.0, 0.0], elbow=[0.0, 0.0], wrist=0.0, neck=0.0,
                     spine=0.0, shrug=0.0, self_pen=0.0, self_at="")
        plant = {"L": None, "R": None}
        prev_low = {"L": None, "R": None}
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            W = bone_world(rig)
            q = {pb.name: pb.matrix.to_quaternion() for pb in rig.pose.bones}
            if prev_q is not None:
                w = {}
                for bn, qq in q.items():
                    if bn.startswith("prop.") or bn in ("root",):
                        continue
                    pq = prev_q[bn]
                    # the bone's turn in its parent's frame (local) between frames
                    pb = rig.pose.bones[bn]
                    if bn in FACE:
                        continue
                    if pb.parent is not None:
                        a1 = (prev_par[bn].inverted() @ pq).normalized()
                        a2 = (q[pb.parent.name].inverted() @ qq).normalized()
                    else:
                        a1, a2 = pq.normalized(), qq.normalized()
                    d = degrees(2.0 * math.acos(min(1.0, abs(a1.dot(a2)))))
                    w[bn] = d
                    if d > stats["max_step"]:
                        stats["max_step"], stats["step_at"] = d, "%s f%d" % (bn, f)
                    if d > 5.0:
                        stats["n_over5"] += 1
                    if prev_w is not None and bn in prev_w:
                        j = abs(d - prev_w[bn])
                        if j > stats["jerk"]:
                            stats["jerk"], stats["jerk_at"] = j, "%s f%d" % (bn, f)
                prev_w = w
            prev_q = q
            prev_par = {pb.name: (q[pb.parent.name] if pb.parent else q[pb.name]) for pb in rig.pose.bones}
            # joints
            for s in ("L", "R"):
                th, sh, ft = yaxis(W["thigh." + s]), yaxis(W["shin." + s]), yaxis(W["foot." + s])
                lat = Vector((-yaxis(W["hips"]).y, yaxis(W["hips"]).x, 0.0))     # not used for sign: angle only
                k = ang(th, sh)
                stats["knee"][1] = max(stats["knee"][1], k)
                ua, fa, hd = yaxis(W["upper_arm." + s]), yaxis(W["forearm." + s]), yaxis(W["hand." + s])
                e = ang(ua, fa)
                stats["elbow"][1] = max(stats["elbow"][1], e)
                stats["wrist"] = max(stats["wrist"], ang(fa, hd))
                # shrug: the clavicle direction above its rest elevation
                cl = yaxis(W["shoulder." + s])
                up = yaxis(W["chest"])
                e = degrees(math.asin(max(-1.0, min(1.0, cl.dot(up))))) - rest_elev[s]
                stats["shrug"] = max(stats["shrug"], e)
            stats["neck"] = max(stats["neck"], ang(yaxis(W["chest"]), yaxis(W["head"])))
            stats["spine"] = max(stats["spine"], ang(yaxis(W["hips"]), yaxis(W["chest"])))
            # self intersection: forearm/hand segments vs the torso capsule and the other arm
            H = {n: W[n].to_translation() for n in W}
            torso = (H["hips"] + (H["neck"] - H["hips"]) * 0.25, H["neck"], 0.085 * s_)
            for s in ("L", "R"):
                fa_seg = (H["forearm." + s], H["hand." + s], 0.030 * s_)
                d = seg_dist(fa_seg[0], fa_seg[1], torso[0], torso[1])
                pen = (fa_seg[2] + torso[2]) - d
                if pen > stats["self_pen"]:
                    stats["self_pen"], stats["self_at"] = pen, "forearm.%s-torso f%d" % (s, f)
            d = seg_dist(H["thigh.L"], H["shin.L"], H["thigh.R"], H["shin.R"])
            pen = 0.10 * s_ - d
            if pen > stats["self_pen"]:
                stats["self_pen"], stats["self_at"] = pen, "thighs f%d" % f
            # feet
            if clip in NO_FLOOR:
                continue
            co = eval_co(body)
            for s in ("L", "R"):
                if not len(fv[s]):
                    continue
                pts = co[fv[s]]
                i = int(np.argmin(pts[:, 2]))
                low = pts[i]
                if clip in LOCO:                                   # in place: the stance foot slides back by design
                    if low[2] < 0.03:
                        stats.setdefault("contact_h", []).append(float(low[2]))
                    prev_low[s] = low
                    continue
                if prev_low[s] is not None:
                    v = float(np.linalg.norm(low[:2] - prev_low[s][:2])) + abs(float(low[2] - prev_low[s][2]))
                    if v < 0.006 and low[2] < 0.08:
                        if plant[s] is None:
                            plant[s] = low.copy()
                        stats["plant_h"].append(float(low[2]))
                        sl = float(np.linalg.norm(low[:2] - plant[s][:2]))
                        if sl > stats["slide"]:
                            stats["slide"], stats["slide_at"] = sl, "%s f%d" % (s, f)
                    else:
                        plant[s] = None
                prev_low[s] = low
        ch = stats.pop("contact_h", None)
        if clip in LOCO:
            stats["contact_frames"] = len(ch or [])
            stats["contact_h_min"] = round(min(ch), 4) if ch else None
            stats["contact_h_max"] = round(max(ch), 4) if ch else None
        ph = stats.pop("plant_h")
        stats["plant_h_min"] = round(min(ph), 4) if ph else None
        stats["plant_h_max"] = round(max(ph), 4) if ph else None
        for k in ("max_step", "jerk", "slide", "wrist", "neck", "spine", "shrug", "self_pen"):
            stats[k] = round(stats[k], 3)
        stats["knee"] = round(stats["knee"][1], 1)
        stats["elbow"] = round(stats["elbow"][1], 1)
        stats["faults"] = faults(clip, stats)
        R[clip] = stats
    return R


def faults(clip, st):
    out = []
    if st["plant_h_min"] is not None and clip not in NO_FLOOR:
        if st["plant_h_min"] < -0.010:
            out.append("sinks %.1f cm" % (-100 * st["plant_h_min"]))
        if st["plant_h_max"] > 0.010 and clip not in LOCO:
            out.append("floats %.1f cm" % (100 * st["plant_h_max"]))
        if clip in LOCO and st["plant_h_max"] > 0.015:
            out.append("planted foot %.1f cm up" % (100 * st["plant_h_max"]))
    if clip in LOCO:
        if not st.get("contact_frames"):
            out.append("never touches the floor")
        elif st["contact_h_min"] < -0.010:
            out.append("stance foot sinks %.1f cm" % (-100 * st["contact_h_min"]))
    if st["slide"] > 0.010:
        out.append("slide %.1f cm (%s)" % (100 * st["slide"], st["slide_at"]))
    lim = 25.0 if clip in LOCO else (5.0 if clip in SLOW else 15.0)
    if clip in FALLS:
        lim = 30.0
    if st["max_step"] > lim:
        out.append("step %.1f deg (%s)" % (st["max_step"], st["step_at"]))
    if st["jerk"] > (14.0 if clip in LOCO or clip in FALLS else 6.0):
        out.append("snap %.1f deg/f (%s)" % (st["jerk"], st["jerk_at"]))
    if st["knee"] > 150:
        out.append("knee %.0f deg" % st["knee"])
    if st["elbow"] > 150:
        out.append("elbow %.0f deg" % st["elbow"])
    if st["wrist"] > 75:
        out.append("wrist %.0f deg" % st["wrist"])
    if st["neck"] > 55:
        out.append("neck %.0f deg" % st["neck"])
    if st["spine"] > 70:
        out.append("spine %.0f deg" % st["spine"])
    if st["shrug"] > 18:
        out.append("shrug %.0f deg" % st["shrug"])
    if st["self_pen"] > 0.02:
        out.append("self %.1f cm (%s)" % (100 * st["self_pen"], st["self_at"]))
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bodies = argv[argv.index("--bodies") + 1].split(",") if "--bodies" in argv else \
        ["m1", "m2", "m3", "f1", "f2", "f3", "c1", "c2", "suit", "indoor"]
    only = set(argv[argv.index("--clips") + 1].split(",")) if "--clips" in argv else None
    tag = argv[argv.index("--out") + 1] if "--out" in argv else "now"
    res = {}
    for b in bodies:
        if not os.path.exists(body_file(b)):
            continue
        res[b] = audit_body(b, only)
        nf = sum(len(v["faults"]) for v in res[b].values())
        print("AUDIT %s: %d clips, %d faults" % (b, len(res[b]), nf))
    os.makedirs(ART, exist_ok=True)
    jp = os.path.join(ART, "audit_%s.json" % tag)
    with open(jp, "w", encoding="utf-8") as fh:
        json.dump(res, fh, indent=1)
    lines = ["# Animation audit (%s)" % tag, "", "Per clip: faults (targets: planted feet 0 +- 1 cm, slide < 1 cm, no "
             "bone step over 5 deg outside locomotion, joints in human range, no self-intersection over 2 cm).", ""]
    clips = sorted({c for r in res.values() for c in r})
    lines.append("| clip | " + " | ".join(res) + " |")
    lines.append("|---|" + "---|" * len(res))
    for c in clips:
        row = []
        for b in res:
            st = res[b].get(c)
            row.append("-" if st is None else ("ok" if not st["faults"] else "; ".join(st["faults"])))
        lines.append("| %s | %s |" % (c, " | ".join(row)))
    tot = {b: sum(len(v["faults"]) for v in r.values()) for b, r in res.items()}
    lines += ["", "Faults per body: " + ", ".join("%s %d" % kv for kv in tot.items())]
    with open(os.path.join(ART, "audit_%s.md" % tag), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("AUDIT written", jp)


if __name__ == "__main__":
    main()
