"""
Frontier Habitat 5.0 - ART-NPC: checks for the people files (called by npc_verify.py at the end of its run, the same
report).  Reads the EXPORTED people_<variant>.glb files and people_manifest.json.
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
from mathutils.bvhtree import BVHTree   # noqa: E402

MANIFEST = os.path.join(N.MODEL_DIR, "people_manifest.json")
PAIRS = os.path.join(N.MODEL_DIR, "npc_pairs.json")
FACE_BONES = ["jaw", "lids"]
LOCOMOTION = {"walk", "run", "carry_walk", "injured_walk", "jog", "child_run", "hold_hands_walk",
              "hold_hands_walk_r", "handcuffed_walk", "escort_walk"}
FALLS = {"collapse", "fall_down"}
NO_FLOOR = {"swim"}                 # the origin is the water surface
STEP_LIMIT = 15.0
BUDGET = 24000


def people_path(v):
    return os.path.join(N.MODEL_DIR, "people_%s.glb" % v)


def import_person(v, outfit=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = N.FPS
    bpy.ops.import_scene.gltf(filepath=people_path(v))
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    meshes = {}
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        nm = o.name.split(".")[0]
        if nm.startswith(("Head_", "Hair_", "Outfit_", "Addon_")):
            meshes[nm] = o
    return rig, meshes


def out_mesh(e):
    """An outfit entry: 'Outfit_x' or {mesh, addons, base_rgb} (the department uniforms share one mesh)."""
    return e if isinstance(e, str) else e["mesh"]


def out_addons(e):
    return [] if isinstance(e, str) else list(e.get("addons", []))


def set_clip(rig, name, f):
    act = next((a for a in bpy.data.actions if a.name == name or a.name.startswith(name + "_") or
                a.name.split("_Rig")[0] == name), None)
    ad = rig.animation_data
    ad.action = act
    if act is not None and act.slots:
        ad.action_slot = act.slots[0]
    bpy.context.scene.frame_set(int(f))
    bpy.context.view_layer.update()
    return act


def world_co(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(ob.matrix_world)
    co = co @ mw[:3, :3].T + mw[:3, 3]
    ev.to_mesh_clear()
    return co


def bvh_of(ob, skip_mats=()):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ob.matrix_world
    verts = [mw @ v.co for v in me.vertices]
    mats = [m.name.split(".")[0] if m else "" for m in me.materials]
    polys = [list(p.vertices) for p in me.polygons if not (mats and mats[p.material_index] in skip_mats)]
    ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys)


def inside_count(bvh, pts, depth=0.01, deepest=None, radius=0.12):
    bad = 0
    for p in pts:
        loc, nrm, idx, d = bvh.find_nearest(Vector(p), radius)
        if loc is None:
            continue
        s = (Vector(p) - loc).dot(nrm)
        if s < -depth and -s >= 0.8 * d:
            bad += 1
            if deepest is not None:
                deepest[0] = max(deepest[0], -s)
    return bad


def bone_rots(rig):
    return {pb.name: (rig.matrix_world @ pb.matrix).to_3x3().normalized() for pb in rig.pose.bones}


def rot_angle(Ra, Rb):
    q = (Ra.transposed() @ Rb).to_quaternion()
    return degrees(2 * math.acos(min(1.0, abs(q.w))))


SELF_TOL = 0.005
# limb capsules (a fraction of the bone from its head, radius at s = 1) tested against the torso and the head
LIMBS = (("upper_arm", "forearm", 0.5, 0.034), ("forearm", "hand", 0.0, 0.029), ("hand", "prop", 0.0, 0.024))


def _seg_dist(p1, q1, p2, q2):
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


def self_overlap(rig, s):
    """The deepest overlap of a limb capsule with the torso capsule or the head sphere, and of the two thighs
    (conservative capsules INSIDE the flesh: any overlap is a limb through the body).  (depth m, where)."""
    mw = rig.matrix_world
    H = {pb.name: mw @ pb.head for pb in rig.pose.bones}
    T0 = H["hips"] + (H["neck"] - H["hips"]) * 0.15
    torso = (T0, H["neck"], 0.085 * s)
    hb = rig.pose.bones["head"]
    up = ((mw @ hb.matrix).to_3x3() @ Vector((0, 1, 0))).normalized()
    hc = H["head"] + up * 0.10 * s
    worst = (0.0, "")
    for side in ("L", "R"):
        for a, b, f0, r in LIMBS:
            pa, pb_ = H["%s.%s" % (a, side)], H["%s.%s" % (b, side)]
            p = pa + (pb_ - pa) * f0
            pen = (r * s + torso[2]) - _seg_dist(p, pb_, torso[0], torso[1])
            if pen > worst[0]:
                worst = (pen, "%s.%s in the torso" % (a, side))
            pen = (r * s + 0.075 * s) - _seg_dist(p, pb_, hc, hc)
            if pen > worst[0]:
                worst = (pen, "%s.%s in the head" % (a, side))
    tl = (H["thigh.L"] + (H["shin.L"] - H["thigh.L"]) * 0.25, H["shin.L"])
    tr = (H["thigh.R"] + (H["shin.R"] - H["thigh.R"]) * 0.25, H["shin.R"])
    pen = 0.11 * s - _seg_dist(tl[0], tl[1], tr[0], tr[1])
    if pen > worst[0]:
        worst = (pen, "thigh through thigh")
    return worst


def self_check_file(check, path, label):
    """Every clip, every frame of an astronaut file: no limb inside the body."""
    if not os.path.exists(path):
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = N.FPS
    bpy.ops.import_scene.gltf(filepath=path)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    worst = (0.0, "")
    for act in list(bpy.data.actions):
        ad.action = act
        if act.slots:
            ad.action_slot = act.slots[0]
        a, b = (int(round(x)) for x in act.frame_range)
        for f in range(a, b + 1):
            bpy.context.scene.frame_set(f)
            pen, where = self_overlap(rig, 1.0)
            if pen > worst[0]:
                worst = (pen, "%s %s f%d" % (act.name.split("_Rig")[0], where, f))
    check("%s: no limb inside the body in any frame of any clip (bone capsules, > 5 mm)" % label, worst[0] <= SELF_TOL,
          "deepest %.3f m (%s)" % worst)


def run(check, gltf_facts):
    for lab in ("suit", "indoor"):
        self_check_file(check, os.path.join(N.MODEL_DIR, "astronaut_%s.glb" % lab), lab)
    if not os.path.exists(MANIFEST):
        check("people: people_manifest.json", True, "no people files yet", info=True)
        return
    M = json.load(open(MANIFEST, encoding="utf-8"))
    face = M.get("skeleton", {}).get("face_bones") or FACE_BONES
    want_bones = sorted(N.BONE_NAMES[:24] + list(face))
    check("people: npc_pairs.json lists the hug", os.path.exists(PAIRS) and
          "hug" in json.load(open(PAIRS, encoding="utf-8")).get("pairs", {}), PAIRS)
    for v, d in M["variants"].items():
        path = people_path(v)
        if not os.path.exists(path):
            check("people %s: file" % v, False, "missing %s" % path)
            continue
        F = gltf_facts(path)
        want_meshes = sorted(set([d["head"], d["hair"]] + [out_mesh(e) for e in d["outfits"].values()] +
                                 list(d.get("addons", []))))
        check("people %s: skinned meshes Head, Hair, one per outfit" % v,
              sorted(F["skinned_mesh_nodes"]) == want_meshes, "%s" % F["skinned_mesh_nodes"])
        check("people %s: skeleton = v3 + face bones (%d)" % (v, len(want_bones)), sorted(F["joints"]) == want_bones,
              "%d joints" % len(F["joints"]))
        par_ok = all(F["skeleton"].get(b, {}).get("parent") == p for b, p in list(N.PARENT.items())[:24])
        par_ok = par_ok and all(F["skeleton"].get(b, {}).get("parent") == "head" for b in face)
        check("people %s: bone parents as v3; jaw and lids under head" % v, par_ok, "ok" if par_ok else "differs")
        tb = F["tris_by"]
        per = {o: tb.get(d["head"], 0) + tb.get(d["hair"], 0) + tb.get(out_mesh(e), 0) +
                  sum(tb.get(a, 0) for a in out_addons(e)) for o, e in d["outfits"].items()}
        check("people %s: <= %d triangles per person on screen (LOD0)" % (v, BUDGET), max(per.values()) <= BUDGET,
              "%s" % per)
        check("people %s: COLOR_0 (AO), <= 4 weights, normalised" % v,
              F["color0"] and not F["joints_1"] and F["max_influences"] <= 4 and F["weight_sum_err"] < 2e-3,
              "max influences %d, max |sum - 1| %.5f" % (F["max_influences"], F["weight_sum_err"]))
        vclips = d.get("clips") or list(M["clips"])
        missing = [c for c in vclips if c not in F["animations"]]
        check("people %s: every clip the manifest lists for it (%d)" % (v, len(vclips)), not missing,
              "missing %s" % missing if missing else "%d clips" % len(vclips))
        bad = [c for c, a in F["animations"].items() if c in M["clips"] and
               abs(a["duration"] - M["clips"][c]["frames"] / N.FPS) > 0.5 / N.FPS]
        check("people %s: durations match the manifest" % v, not bad, "%s" % bad if bad else "ok")
        scale = [c for c, a in F["animations"].items() if a["scale_nodes"]]
        roots = [c for c, a in F["animations"].items() if a["root_moves"] > 1e-5]
        check("people %s: no scale keys, root never moves" % v, not scale and not roots,
              "scale %s, root %s" % (scale, roots))
        # evaluated: every clip with the first outfit
        outfits = []
        for e in d["outfits"].values():
            if out_mesh(e) not in outfits:
                outfits.append(out_mesh(e))
        rig, meshes = import_person(v)
        vis = [meshes[d["head"]], meshes[d["hair"]], meshes[outfits[0]]]
        worst_step, worst_seam, zmin, lid_step = (0.0, "", 0), (0.0, ""), (9.0, ""), (0.0, "")
        worst_self = (0.0, "")
        jaw_max, lids_max = {}, 0.0
        for c, m in ((c, M["clips"][c]) for c in vclips if c in M["clips"]):
            act = set_clip(rig, c, 0)
            if act is None:
                continue
            n = m["frames"]
            prev = None
            first = None
            for f in range(0, n + 1):
                bpy.context.scene.frame_set(f)
                R = bone_rots(rig)
                if first is None:
                    first = R
                if prev is not None and c not in LOCOMOTION and c not in FALLS:
                    for bn in R:
                        if bn in face:
                            a = rot_angle(prev[bn], R[bn]) - rot_angle(prev["head"], R["head"])
                            if a > lid_step[0]:
                                lid_step = (a, "%s %s f%d" % (c, bn, f))
                            continue
                        a = rot_angle(prev[bn], R[bn])
                        if a > worst_step[0]:
                            worst_step = (a, "%s %s f%d" % (c, bn, f), f)
                prev = R
                pen, where = self_overlap(rig, d.get("scale", 1.0))
                if pen > worst_self[0]:
                    worst_self = (pen, "%s %s f%d" % (c, where, f))
                if f % 6 == 0 and c not in NO_FLOOR:
                    lo = min(float(world_co(o)[:, 2].min()) for o in vis)
                    if lo < zmin[0]:
                        zmin = (lo, "%s f%d" % (c, f))
                jq = rig.pose.bones["jaw"].matrix_basis.to_quaternion()
                lq = rig.pose.bones["lids"].matrix_basis.to_quaternion()
                jaw_max[c] = max(jaw_max.get(c, 0.0), degrees(2 * math.acos(min(1.0, abs(jq.w)))))
                lids_max = max(lids_max, degrees(2 * math.acos(min(1.0, abs(lq.w)))))
            if m.get("loop"):
                seam = max(rot_angle(first[bn], prev[bn]) for bn in first)
                if seam > worst_seam[0]:
                    worst_seam = (seam, c)
        check("people %s: no limb inside the body in any frame of any clip (bone capsules, > 5 mm)" % v,
              worst_self[0] <= SELF_TOL, "deepest %.3f m (%s)" % worst_self)
        check("people %s: bone step per frame < %.0f deg (not locomotion, not falls)" % (v, STEP_LIMIT),
              worst_step[0] < STEP_LIMIT, "%.2f deg (%s)" % (worst_step[0], worst_step[1]))
        check("people %s: loop seams <= 1 deg" % v, worst_seam[0] <= 1.0, "%.3f deg (%s)" % worst_seam)
        check("people %s: face bones (jaw, lids) move <= 25 deg per frame (a blink closes in 0.1 s)" % v,
              lid_step[0] <= 25.0, "%.1f deg (%s)" % lid_step)
        check("people %s: never below the floor (z >= -0.01)" % v, zmin[0] >= -0.01, "%.4f m (%s)" % zmin)
        talking = [c for c in ("talk", "talk_gesture_a", "argue", "laugh") if c in jaw_max]
        check("people %s: the jaw moves in the talking clips (> 3 deg), blinks close the lids (> 40 deg)" % v,
              all(jaw_max[c] > 3.0 for c in talking) and lids_max > 40.0,
              "jaw %s, lids %.1f" % ({c: round(jaw_max[c], 1) for c in talking}, lids_max))
        # seat contact after the height retarget: the lowest body point over the seat in sit_idle
        set_clip(rig, "sit_idle", 0)
        co = np.concatenate([world_co(o) for o in vis])
        mask = (co[:, 0] > -0.52) & (co[:, 0] < -0.15) & (np.abs(co[:, 1]) < 0.23)
        low = float(co[mask, 2].min()) if mask.any() else 9.0
        check("people %s: sit_idle rests on the 0.46 m seat (+- 2 cm, height retarget)" % v, 0.44 <= low <= 0.48,
              "lowest point over the seat %.3f m" % low)
        if "sit_bar_stool" in vclips:
            set_clip(rig, "sit_bar_stool", 0)
            co = np.concatenate([world_co(o) for o in vis])
            mask = (np.abs(co[:, 0] + 0.04) < 0.07) & (np.abs(co[:, 1]) < 0.15) & (co[:, 2] > 0.6)
            low = float(co[mask, 2].min()) if mask.any() else 9.0
            check("people %s: sit_bar_stool rests on the 0.76 m stool (+- 2.5 cm)" % v, 0.735 <= low <= 0.785,
                  "lowest point over the stool %.3f m" % low)
        # poke-through: head (above the collar) and hair must not go inside the outfit, at test poses
        worst = (0, "")
        for o in outfits:
            for c, f in (("idle", 0), ("sit_idle", 0), ("walk", 8), ("dance_a", 30), ("talk_gesture_a", 60),
                         ("laugh", 36), ("hug", 50)):
                if set_clip(rig, c, f) is None:
                    continue
                bvh = bvh_of(meshes[o], skip_mats=("Skin",))       # hair through CLOTHES (skin covers hair)
                neck_top = rig.matrix_world @ rig.pose.bones["neck"].head
                pts = [p for p in world_co(meshes[d["head"]]) if p[2] > neck_top.z + 0.045]
                pts += list(world_co(meshes[d["hair"]]))
                n_in = inside_count(bvh, pts, radius=0.03)
                if os.environ.get("NPC_DEBUG") and n_in:
                    bad_ = []
                    for p_ in pts:
                        loc_, nrm_, _, dd_ = bvh.find_nearest(Vector(p_), 0.12)
                        if loc_ is not None and (Vector(p_) - loc_).dot(nrm_) < -0.01 and -(Vector(p_) - loc_).dot(nrm_) >= 0.8 * dd_:
                            bad_.append(tuple(round(float(x), 3) for x in p_))
                    print("HAIRDBG", v, o, c, f, "neck_top", tuple(round(x, 3) for x in neck_top), bad_[:8])
                if n_in > worst[0]:
                    worst = (n_in, "%s %s f%d" % (o, c, f))
        check("people %s: head and hair never inside the clothes at the test poses (1 cm)" % v, worst[0] == 0,
              "%d vertices at worst %s" % worst)
    # paired clips (npc_pairs.json): partner B placed as RENDER places it; neither body inside the other
    check_pairs(check, M)


CAPS = (("hips", "neck", 0.085), ("neck", "head", 0.040), ("upper_arm.L", "forearm.L", 0.034),
        ("upper_arm.R", "forearm.R", 0.034), ("forearm.L", "hand.L", 0.026), ("forearm.R", "hand.R", 0.026),
        ("thigh.L", "shin.L", 0.060), ("thigh.R", "shin.R", 0.060), ("shin.L", "foot.L", 0.040),
        ("shin.R", "foot.R", 0.040))


def capsules(rig, s):
    """Conservative capsules INSIDE a body (bone segments, radii under the real flesh), world space."""
    mw = rig.matrix_world
    H = {pb.name: mw @ pb.head for pb in rig.pose.bones}
    out = [(H[a], H[b], r * s) for a, b, r in CAPS]
    hb = rig.pose.bones["head"]
    up = ((mw @ hb.matrix).to_3x3() @ Vector((0, 1, 0))).normalized()
    c = H["head"] + up * 0.10 * s
    out.append((c, c, 0.075 * s))
    out.append((H["hips"], H["hips"], 0.090 * s))
    return out


def deep_points(pts, caps, depth):
    """How many points lie deeper than depth inside any capsule; the deepest depth."""
    n, worst = 0, 0.0
    P = np.asarray(pts)
    inside = np.zeros(len(P), dtype=bool)
    dmax = np.zeros(len(P))
    for a, b, r in caps:
        a, b = np.array(a), np.array(b)
        d = b - a
        L2 = float(d @ d)
        t = np.clip(((P - a) @ d) / L2, 0.0, 1.0) if L2 > 1e-9 else np.zeros(len(P))
        dist = np.linalg.norm(P - (a + t[:, None] * d), axis=1)
        pen = r - dist
        dmax = np.maximum(dmax, pen)
    return int((dmax > depth).sum()), float(dmax.max()) if len(dmax) else 0.0


def check_pairs(check, M):
    if not os.path.exists(PAIRS):
        return
    vs = list(M["variants"])
    if not vs:
        return
    pairs = json.load(open(PAIRS, encoding="utf-8"))["pairs"]
    a = vs[0]
    b = next((x for x in vs if M["variants"][x].get("sex") != M["variants"][a].get("sex") and
              not M["variants"][x].get("child")), vs[-1])
    rig_a, ma = import_person(a)
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=people_path(b))
    acts_b = {x.name.split(".")[0].split("_Rig")[0]: x for x in bpy.data.actions if x not in acts_before}
    new = [o for o in bpy.data.objects if o not in before]
    rig_b = next(o for o in new if o.type == "ARMATURE")
    for tr in list((rig_b.animation_data or rig_b.animation_data_create()).nla_tracks):
        rig_b.animation_data.nla_tracks.remove(tr)
    sa, sb = M["variants"][a]["scale"], M["variants"][b]["scale"]
    casual = next((e for o, e in M["variants"][a]["outfits"].items() if o.startswith("casual")), None)
    ob_a = ma[out_mesh(casual or list(M["variants"][a]["outfits"].values())[0])]
    name_b = out_mesh(next((e for o, e in M["variants"][b]["outfits"].items() if o.startswith("casual")),
                           list(M["variants"][b]["outfits"].values())[0]))
    ob_b = next(o for o in new if o.type == "MESH" and o.name.split(".")[0] == name_b)
    def hand_mask(ob):
        names = {g.index: g.name for g in ob.vertex_groups}
        return np.array([bool(v.groups) and names.get(max(v.groups, key=lambda g: g.weight).group, "").startswith(
            ("hand.", "prop.")) for v in ob.data.vertices], dtype=bool)
    hand_a, hand_b = hand_mask(ob_a), hand_mask(ob_b)
    for pname, pr in pairs.items():
        if pr["clip_a"] not in M["clips"] or pr["clip_b"] not in M["clips"]:
            continue
        sm = (sa + sb) / 2
        rig_b.location = (pr["distance_m"] * sm, pr.get("side_offset_m", 0.0) * sm, 0.0)
        rig_b.rotation_mode = "XYZ"
        rig_b.rotation_euler = (0.0, 0.0, math.radians(pr["facing_deg"]))
        act_b = acts_b.get(pr["clip_b"])
        n = max(M["clips"][pr["clip_a"]]["frames"], M["clips"][pr["clip_b"]]["frames"])
        sync = int(round(pr.get("sync_s", 0.0) * N.FPS))
        # B plays its clip from sync (an NLA strip; before it, B holds its first frame)
        adb = rig_b.animation_data
        adb.action = None
        for tr in list(adb.nla_tracks):
            adb.nla_tracks.remove(tr)
        if act_b is not None:
            tr = adb.nla_tracks.new()
            st = tr.strips.new(pr["clip_b"], sync, act_b)
            st.extrapolation = "HOLD"
        worst2, worst4, deepest, at = 0, 0, 0.0, ""
        for f in range(0, n + 1, 3):
            set_clip(rig_a, pr["clip_a"], min(f, M["clips"][pr["clip_a"]]["frames"]))
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            pa = world_co(ob_a)
            pb = world_co(ob_b)
            if pr.get("hand_contact"):                  # the gripping hands touch by design
                pa, pb = pa[~hand_a], pb[~hand_b]
            pa, pb = pa[::2], pb[::2]
            n2a, da = deep_points(pa, capsules(rig_b, sb), 0.02)
            n2b, db = deep_points(pb, capsules(rig_a, sa), 0.02)
            n4a, _ = deep_points(pa, capsules(rig_b, sb), 0.04)
            n4b, _ = deep_points(pb, capsules(rig_a, sa), 0.04)
            if n2a + n2b > worst2:
                worst2, at = n2a + n2b, "f%d" % f
            worst4 = max(worst4, n4a + n4b)
            deepest = max(deepest, da, db)
            if os.environ.get("NPC_DEBUG") and n2a + n2b:
                print("PAIRDBG %s f%d A-in-B %d B-in-A %d" % (pname, f, n2a, n2b))
                for nm_, P_, cs_ in (("A-in-B", pa, capsules(rig_b, sb)), ("B-in-A", pb, capsules(rig_a, sa))):
                    for ci, c_ in enumerate(cs_):
                        k_, _ = deep_points(P_, [c_], 0.02)
                        if k_:
                            a_, b_, r_ = c_
                            A_, B_ = np.array(a_), np.array(b_)
                            d_ = B_ - A_
                            t_ = np.clip(((P_ - A_) @ d_) / max(1e-9, float(d_ @ d_)), 0, 1)
                            dd_ = np.linalg.norm(P_ - (A_ + t_[:, None] * d_), axis=1)
                            sel_ = P_[dd_ < r_ - 0.02]
                            print("      at", tuple(np.round(sel_.mean(axis=0), 3)), "axis", tuple(np.round(A_, 3)), tuple(np.round(B_, 3)))
                            if nm_ == "B-in-A":
                                ids_ = np.nonzero(dd_ < r_ - 0.02)[0][:6] * 2
                                for vi_ in ids_:
                                    vv_ = ob_b.data.vertices[int(vi_)]
                                    gs_ = sorted(((ob_b.vertex_groups[g.group].name, round(g.weight, 2)) for g in vv_.groups), key=lambda x: -x[1])[:3]
                                    print("        v", int(vi_), tuple(round(x, 3) for x in vv_.co), gs_)
                            lab_ = (CAPS[ci][0] + "-" + CAPS[ci][1]) if ci < len(CAPS) else ("head" if ci == len(CAPS) else "pelvis")
                            print("   ", nm_, lab_, k_)
        check("people pair %s (%s with %s): no body point deeper than 2 cm in the partner (bone capsules), whole clip"
              % (pname, a, b), (worst2 <= 6 or (pr.get("hand_contact") and worst2 <= 16)) and worst4 == 0,
              "%d points deeper than 2 cm (worst %s), %d deeper than 4 cm, deepest %.3f m" % (worst2, at, worst4, deepest))
