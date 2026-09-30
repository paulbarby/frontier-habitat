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
LOCOMOTION = {"walk", "run", "carry_walk", "injured_walk"}
FALLS = {"collapse"}
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


def bvh_of(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ob.matrix_world
    verts = [mw @ v.co for v in me.vertices]
    polys = [list(p.vertices) for p in me.polygons]
    ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys)


def inside_count(bvh, pts, depth=0.01, deepest=None):
    bad = 0
    for p in pts:
        loc, nrm, idx, d = bvh.find_nearest(Vector(p), 0.12)
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


def run(check, gltf_facts):
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
        missing = [c for c in M["clips"] if c not in F["animations"]]
        check("people %s: every clip of the manifest (%d)" % (v, len(M["clips"])), not missing,
              "missing %s" % missing if missing else "%d clips" % len(M["clips"]))
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
        jaw_max, lids_max = {}, 0.0
        for c, m in M["clips"].items():
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
                if f % 6 == 0:
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
        set_clip(rig, "sit_bar_stool", 0)
        co = np.concatenate([world_co(o) for o in vis])
        mask = (np.abs(co[:, 0] + 0.04) < 0.11) & (np.abs(co[:, 1]) < 0.15) & (co[:, 2] > 0.6)
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
                bvh = bvh_of(meshes[o])
                neck_top = rig.matrix_world @ rig.pose.bones["neck"].head
                pts = [p for p in world_co(meshes[d["head"]]) if p[2] > neck_top.z + 0.045]
                pts += list(world_co(meshes[d["hair"]]))
                n_in = inside_count(bvh, pts)
                if n_in > worst[0]:
                    worst = (n_in, "%s %s f%d" % (o, c, f))
        check("people %s: head and hair never inside the outfit at the test poses (1 cm)" % v, worst[0] == 0,
              "%d vertices at worst %s" % worst)
    # the hug pair: A and B at the npc_pairs distance, facing; count A inside B at the hold
    vs = list(M["variants"])
    if len(vs) >= 2 and os.path.exists(PAIRS):
        pr = json.load(open(PAIRS, encoding="utf-8"))["pairs"]["hug"]
        a, b = vs[0], vs[1]
        rig_a, ma = import_person(a)
        before = set(bpy.data.objects)
        acts_before = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=people_path(b))
        hug_b = next((x for x in bpy.data.actions if x not in acts_before and x.name.split(".")[0].startswith("hug")), None)
        new = [o for o in bpy.data.objects if o not in before]
        rig_b = next(o for o in new if o.type == "ARMATURE")
        for tr in list((rig_b.animation_data or rig_b.animation_data_create()).nla_tracks):
            rig_b.animation_data.nla_tracks.remove(tr)
        sa, sb = M["variants"][a]["scale"], M["variants"][b]["scale"]
        rig_b.location = (pr["distance_m"] * (sa + sb) / 2, 0.0, 0.0)
        rig_b.rotation_mode = "XYZ"
        rig_b.rotation_euler = (0.0, 0.0, math.radians(pr["facing_deg"]))
        ob_a = ma[out_mesh(list(M["variants"][a]["outfits"].values())[0])]
        name_b = out_mesh(list(M["variants"][b]["outfits"].values())[0])
        ob_b = next(o for o in new if o.type == "MESH" and o.name.split(".")[0] == name_b)
        worst, deep, n_deep = 0, [0.0], 0
        for f in range(12, 96, 4):
            set_clip(rig_a, "hug", f)
            rig_b.animation_data.action = hug_b
            if hug_b is not None and hug_b.slots:
                rig_b.animation_data.action_slot = hug_b.slots[0]
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            pts = world_co(ob_a)[::2]
            bvh = bvh_of(ob_b)
            worst = max(worst, inside_count(bvh, pts, depth=0.02, deepest=deep))
            n_deep = max(n_deep, inside_count(bvh, pts, depth=0.04))
        check("people pair hug (%s with %s): <= 60 vertices (every 2nd) deeper than 2 cm and <= 3 deeper than 4 cm "
              "(single contact points), whole clip" % (a, b), worst <= 60 and n_deep <= 3,
              "%d deeper than 2 cm, %d deeper than 4 cm, deepest %.3f m" % (worst, n_deep, deep[0]))
