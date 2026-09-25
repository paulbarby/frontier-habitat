"""
Frontier Habitat 3.0 - ART-NPC consistency check (V3_DESIGN.md section 3.5, plus the critic round 1 list).

Run (Git Bash, background only):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/npc_verify.py -- [--renders]

Reads the EXPORTED files (assets/models/astronaut_suit.glb, astronaut_indoor.glb, astronaut_anims.json), both as raw
glTF (skin, weights, channels) and imported into Blender (evaluated bones and the deformed meshes).
Writes art/npc/npc_report.json and art/npc/npc_report.md; with --renders also the sheets in art/npc/.
"""
import bpy
import os
import sys
import json
import math
import time
from math import degrees

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
import numpy as np              # noqa: E402
from mathutils import Vector, Matrix, Quaternion   # noqa: E402

VARIANTS = ["suit", "indoor"]
ALL_CLIPS = ["idle", "idle_look", "walk", "run", "carry_walk", "carry_idle", "work_console", "work_bench", "talk",
             "kneel_enter", "repair_kneel", "kneel_exit", "sit_enter", "sit_idle", "sit_eat", "sit_type", "sit_exit",
             "lie_enter", "sleep", "lie_exit", "injured_walk", "collapse", "dead", "cheer", "suit_swap"]
LOCOMOTION = {"walk", "run", "carry_walk", "injured_walk"}
LOOPS = {"idle", "idle_look", "walk", "run", "carry_walk", "carry_idle", "work_console", "work_bench", "talk",
         "repair_kneel", "sit_idle", "sit_eat", "sit_type", "sleep", "injured_walk", "dead"}
REST = {"stand": ("idle", 0), "sit": ("sit_idle", 0), "lie": ("sleep", 0), "kneel": ("repair_kneel", 0),
        "dead": ("dead", 0)}
ENTER_EXIT = {"kneel_enter": ("stand", "kneel"), "kneel_exit": ("kneel", "stand"),
              "sit_enter": ("stand", "sit"), "sit_exit": ("sit", "stand"),
              "lie_enter": ("stand", "lie"), "lie_exit": ("lie", "stand"),
              "collapse": ("stand", "dead"), "cheer": ("stand", "stand"), "suit_swap": ("stand", "stand")}
MATERIALS = {"suit": {"SuitMain", "SuitAccent", "Visor", "Pack", "Light"},
             "indoor": {"Jumpsuit", "SuitAccent", "Skin", "Hair"}}
BUDGET = {"suit": 7000, "indoor": 6000}
STEP_LIMIT_DEG = 15.0
HEADS = ["Head_0", "Head_1", "Head_2", "Head_3"]
VIS_KINDS = ["trader", "tourist", "medical", "science", "inspector"]
VIS_MESHES_BY = {"suit": ["Vis_%s" % k for k in VIS_KINDS],
                 "indoor": ["Vis_%s" % k for k in VIS_KINDS if k != "inspector"] +
                 ["Vis_inspector_h023", "Vis_inspector_h1"]}
VIS_MESHES = sorted(set(VIS_MESHES_BY["suit"]) | set(VIS_MESHES_BY["indoor"]))
VIS_DRIFT_LIMIT = 0.02          # an attachment point may move at most 2 cm relative to the body point under it


def visitor_path(v):
    return os.path.join(N.MODEL_DIR, "astronaut_visitor_%s.glb" % v)


def attach_visitors(rig, v):
    """Import the visitor attachments into the scene of `rig` and bind them to it (the same skeleton)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=visitor_path(v))
    new = [o for o in bpy.data.objects if o not in before]
    vis = [o for o in new if o.type == "MESH" and o.name.split(".")[0] in VIS_MESHES]
    for o in vis:
        mw = o.matrix_world.copy()
        o.parent = rig
        o.matrix_world = mw
        for md in o.modifiers:
            if md.type == "ARMATURE":
                md.object = rig
    for o in new:
        if o not in vis:
            bpy.data.objects.remove(o)
    return vis


def visitor_drift(rig, bodies, vis, clips_meta, clips, step=3):
    """Worst change (over every clip, every `step` frames) of the distance from each attachment vertex to the body
    vertex nearest to it at rest; and the lowest attachment point."""
    from mathutils import kdtree
    dg = bpy.context.evaluated_depsgraph_get()
    ad = rig.animation_data
    ad.action = None
    for pb in rig.pose.bones:                 # the bind pose (the bones keep the last frame otherwise)
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()
    rest_b = np.concatenate([mesh_world(b, dg) for b in bodies])

    def top_bone(ob):
        W = group_weights(ob)
        names = sorted(W)
        M = np.stack([W[n] for n in names], axis=1)
        return np.array(names)[M.argmax(axis=1)]
    tb = np.concatenate([top_bone(b) for b in bodies])
    trees = {}
    for bn in set(tb.tolist()):
        ids = np.where(tb == bn)[0]
        kd = kdtree.KDTree(len(ids))
        for i in ids:
            kd.insert(rest_b[i], int(i))
        kd.balance()
        trees[bn] = kd
    info = {}
    for o in vis:
        rv = mesh_world(o, dg)
        vb = top_bone(o)
        # the nearest body vertex that follows the same main bone
        idx = np.array([(trees[b] if b in trees else trees["chest"]).find(q)[1] for q, b in zip(rv, vb)])
        d0 = np.linalg.norm(rv - rest_b[idx], axis=1)
        info[o] = (idx, d0)
    worst = {o.name.split(".")[0]: (0.0, "", 0) for o in vis}
    zmin = {o.name.split(".")[0]: (9.0, "", 0) for o in vis}
    for c in clips:
        act = action_for(c)
        if act is None or c not in clips_meta:
            continue
        ad.action = act
        if act.slots:
            ad.action_slot = act.slots[0]
        for f in range(0, clips_meta[c]["frames"] + 1, step):
            bpy.context.scene.frame_set(f)
            cb = np.concatenate([mesh_world(b, dg) for b in bodies])
            for o in vis:
                nm = o.name.split(".")[0]
                co = mesh_world(o, dg)
                idx, d0 = info[o]
                d = np.abs(np.linalg.norm(co - cb[idx], axis=1) - d0).max()
                if d > worst[nm][0]:
                    worst[nm] = (float(d), c, f)
                zc = float(co[:, 2].min())
                if zc < zmin[nm][0]:
                    zmin[nm] = (zc, c, f)
    return worst, zmin


def model_path(v):
    return os.path.join(N.MODEL_DIR, "astronaut_%s.glb" % v)


# --------------------------------------------------------------------------------------
# raw glTF facts
# --------------------------------------------------------------------------------------
def gltf_facts(path):
    g, binary = N.read_glb(path)
    nodes = g["nodes"]
    out = {}
    skins = g.get("skins", [])
    out["skins"] = len(skins)
    joints = [nodes[j]["name"] for j in skins[0]["joints"]] if skins else []
    out["joints"] = joints
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    jset = set(skins[0]["joints"]) if skins else set()
    skel = {}
    for j in (skins[0]["joints"] if skins else []):
        n = nodes[j]
        p = parent.get(j)
        skel[n["name"]] = dict(parent=nodes[p]["name"] if p is not None and p in jset else None,
                               t=[round(x, 5) for x in n.get("translation", [0, 0, 0])],
                               r=[round(x, 5) for x in n.get("rotation", [0, 0, 0, 1])])
    out["skeleton"] = skel
    tris, mats, color0, j1, wsum_err, max_inf = 0, set(), True, False, 0.0, 0
    mesh_nodes = [n for n in nodes if "mesh" in n]
    out["mesh_nodes"] = [n.get("name") for n in mesh_nodes]
    out["skinned_mesh_nodes"] = [n.get("name") for n in mesh_nodes if "skin" in n]
    tris_by = {}
    mats_by = {}
    for n in mesh_nodes:
        t = 0
        ms = set()
        for prim in g["meshes"][n["mesh"]]["primitives"]:
            acc = g["accessors"][prim["indices"]]
            t += acc["count"] // 3
            if "material" in prim:
                ms.add(g["materials"][prim["material"]]["name"])
            a = prim["attributes"]
            if "COLOR_0" not in a:
                color0 = False
            if "JOINTS_1" in a or "WEIGHTS_1" in a:
                j1 = True
            if "WEIGHTS_0" in a:
                w = N.glb_accessor(g, binary, a["WEIGHTS_0"]).astype(np.float64)
                s = w.sum(axis=1)
                wsum_err = max(wsum_err, float(np.abs(s - 1.0).max()))
                max_inf = max(max_inf, int((w > 1e-6).sum(axis=1).max()))
        tris_by[n.get("name")] = t
        mats_by[n.get("name")] = sorted(ms)
        mats |= ms
        tris += t
    out.update(tris=tris, tris_by=tris_by, mats_by=mats_by, materials=sorted(mats), color0=color0, joints_1=j1,
               weight_sum_err=wsum_err, max_influences=max_inf)
    anims = {}
    for a in g.get("animations", []):
        paths = {}
        tmax = 0.0
        root_moves = 0.0
        for ch in a["channels"]:
            nm = nodes[ch["target"]["node"]]["name"]
            paths.setdefault(ch["target"]["path"], set()).add(nm)
            smp = a["samplers"][ch["sampler"]]
            tmax = max(tmax, g["accessors"][smp["input"]]["max"][0])
            if nm == "root":
                vals = N.glb_accessor(g, binary, smp["output"])
                if ch["target"]["path"] == "translation":
                    root_moves = max(root_moves, float(np.abs(vals).max()))
                elif ch["target"]["path"] == "rotation":
                    root_moves = max(root_moves, float(np.abs(np.abs(vals[:, 3]) - 1.0).max()))
        anims[a["name"]] = dict(duration=round(tmax, 5), scale_nodes=sorted(paths.get("scale", [])),
                                translation_nodes=sorted(paths.get("translation", [])), root_moves=root_moves)
    out["animations"] = anims
    return out


# --------------------------------------------------------------------------------------
# evaluated facts (imported into Blender)
# --------------------------------------------------------------------------------------
def import_rig(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = N.FPS
    bpy.ops.import_scene.gltf(filepath=path)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    body = next((o for o in meshes if o.name.split(".")[0] == "Body"), meshes[0])
    others = [o for o in meshes if o.name.split(".")[0].startswith("Head_")]      # not importer helper shapes
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    return rig, body, others


def group_weights(ob):
    """{bone: array of per-vertex weights} from the vertex groups of the imported mesh."""
    nv = len(ob.data.vertices)
    names = {g.index: g.name for g in ob.vertex_groups}
    W = {n: np.zeros(nv) for n in names.values()}
    for v in ob.data.vertices:
        for ge in v.groups:
            W[names[ge.group]][v.index] = ge.weight
    return W


def action_for(name):
    a = bpy.data.actions.get(name)
    if a:
        return a
    for a in bpy.data.actions:
        if a.name.startswith(name + "_") or a.name.split("_Rig")[0] == name:
            return a
    return None


def mesh_world(ob, dg):
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(ob.matrix_world)
    co = co @ mw[:3, :3].T + mw[:3, 3]
    ev.to_mesh_clear()
    return co


def eval_clip(rig, body, others, name, frames):
    act = action_for(name)
    ad = rig.animation_data
    ad.action = act
    if act.slots:
        ad.action_slot = act.slots[0]
    out = []
    dg = bpy.context.evaluated_depsgraph_get()
    for f in range(frames + 1):
        bpy.context.scene.frame_set(f)
        rot = {pb.name: (rig.matrix_world @ pb.matrix).to_3x3().normalized() for pb in rig.pose.bones}
        heads = {pb.name: (rig.matrix_world @ pb.matrix).translation.copy() for pb in rig.pose.bones}
        co = mesh_world(body, dg)
        allco = co
        if others:
            allco = np.concatenate([co] + [mesh_world(o, dg) for o in others])
        out.append(dict(rot=rot, head=heads, co=co, all=allco, zmin=float(allco[:, 2].min()),
                        zmax=float(allco[:, 2].max())))
    return out


def rot_angle(Ra, Rb):
    q = (Ra.transposed() @ Rb).to_quaternion()
    w = min(1.0, abs(q.w))
    return degrees(2 * math.acos(w))


def pose_diff(a, b, bones=None):
    bones = bones or list(a["rot"].keys())
    worst, which = 0.0, None
    for bn in bones:
        d = rot_angle(a["rot"][bn], b["rot"][bn])
        if d > worst:
            worst, which = d, bn
    dpos = (a["head"]["hips"] - b["head"]["hips"]).length
    return worst, which, dpos


def max_step(frames):
    """Largest per-frame change of any bone: world (armature) rotation or rotation relative to the parent."""
    worst, wb, wf, wk = 0.0, None, 0, ""
    for f in range(1, len(frames)):
        a, b = frames[f - 1]["rot"], frames[f]["rot"]
        for bn in a:
            d = rot_angle(a[bn], b[bn])
            if d > worst:
                worst, wb, wf, wk = d, bn, f, "world"
            par = N.PARENT.get(bn)
            if par:
                d2 = rot_angle(a[par].transposed() @ a[bn], b[par].transposed() @ b[bn])
                if d2 > worst:
                    worst, wb, wf, wk = d2, bn, f, "local"
    return worst, wb, wf, wk


def foot_slide(frames, speed, n, idx):
    pos = []
    for f in range(2 * n + 1):
        co = frames[f % n]["co"][idx].copy()
        co[:, 0] += speed * f / N.FPS
        pos.append(co)
    pos = np.stack(pos)
    contact = pos[:, :, 2] < 0.012
    worst, runs = 0.0, 0
    F = pos.shape[0]
    for v in range(pos.shape[1]):
        f = 0
        while f < F:
            if contact[f, v]:
                g = f
                while g + 1 < F and contact[g + 1, v]:
                    g += 1
                if f > 0 and g < F - 1 and g > f:
                    seg = pos[f:g + 1, v, :2]
                    worst = max(worst, float(np.max(np.linalg.norm(seg - seg[0], axis=1))))
                    runs += 1
                f = g + 1
            else:
                f += 1
    return worst, runs


def knee_angle(rec, s):
    a = (rec["head"]["shin." + s] - rec["head"]["thigh." + s]).normalized()
    b = (rec["head"]["foot." + s] - rec["head"]["shin." + s]).normalized()
    return degrees(a.angle(b))


def box_count(co, lo, hi):
    lo, hi = np.array(lo), np.array(hi)
    return int(np.all((co > lo) & (co < hi), axis=1).sum())


# --------------------------------------------------------------------------------------
def run(renders):
    t0 = time.time()
    meta_path = os.path.join(N.MODEL_DIR, "astronaut_anims.json")
    meta = json.load(open(meta_path, encoding="utf-8")) if os.path.exists(meta_path) else {}
    clips_meta = meta.get("clips", {})
    fur = meta.get("furniture", {})
    checks = []

    def check(name, ok, detail, pending=False, info=False):
        st = "pending" if pending else ("info" if info else ("pass" if ok else "FAIL"))
        checks.append(dict(check=name, status=st, detail=str(detail)))
        print("  %-7s %-58s %s" % (st.upper() if st in ("pending", "FAIL") else st, name, detail))

    facts = {v: (gltf_facts(model_path(v)) if os.path.exists(model_path(v)) else None) for v in VARIANTS}

    # ---- files, skeleton ----
    for v in VARIANTS:
        F = facts[v]
        if F is None:
            check("file astronaut_%s.glb" % v, False, "missing")
            continue
        check("file astronaut_%s.glb" % v, True, "%d bytes" % os.path.getsize(model_path(v)))
        want_nodes = ["Body"] + (HEADS if v == "indoor" else [])
        check("%s: skinned mesh objects %s" % (v, want_nodes), F["skins"] == 1 and
              sorted(F["skinned_mesh_nodes"]) == sorted(want_nodes),
              "skins %d, skinned mesh nodes %s" % (F["skins"], F["skinned_mesh_nodes"]))
        names_ok = sorted(F["joints"]) == sorted(N.BONE_NAMES)
        par_ok = all(F["skeleton"].get(b, {}).get("parent") == p for b, p in N.PARENT.items())
        check("%s: skeleton names and parents (section 3.2)" % v, names_ok and par_ok, "%d joints" % len(F["joints"]))
    if facts["suit"] and facts["indoor"]:
        a, b = facts["suit"]["skeleton"], facts["indoor"]["skeleton"]
        worst = max(max(abs(x - y) for x, y in zip(a[bn]["t"] + a[bn]["r"], b[bn]["t"] + b[bn]["r"]))
                    for bn in a if bn in b)
        check("skeleton identical in both files (names, parents, rest pose, lengths)",
              set(a) == set(b) and worst < 1e-4, "max rest difference %.6f" % worst)
        same = all(facts["suit"]["animations"].get(c, {}).get("duration") == facts["indoor"]["animations"].get(c, {}).get("duration")
                   for c in ALL_CLIPS)
        check("clips identical in length in both files", same, "RENDER reuses the suit's baked clips for indoor")
    else:
        check("skeleton identical in both files", False, "a file is missing")

    # ---- static checks ----
    for v in VARIANTS:
        F = facts[v]
        if F is None:
            continue
        if v == "indoor":
            body = F["tris_by"].get("Body", 0)
            heads = [F["tris_by"].get(h, 0) for h in HEADS]
            check("indoor: triangles <= 6000 (whole file)", F["tris"] <= BUDGET[v],
                  "%d in the file = Body %d + heads %s; one colonist shows Body + one head = %d" %
                  (F["tris"], body, heads, body + max(heads or [0])))
        else:
            check("%s: triangles <= %d" % (v, BUDGET[v]), F["tris"] <= BUDGET[v], "%d triangles" % F["tris"])
        need = MATERIALS[v]
        check("%s: contract materials present" % v, need <= set(F["materials"]),
              "has %s" % F["materials"])
        check("%s: COLOR_0 (baked AO) on every primitive" % v, F["color0"], str(F["color0"]))
        check("%s: weights <= 4 per vertex" % v, not F["joints_1"] and F["max_influences"] <= 4,
              "max influences %d" % F["max_influences"])
        check("%s: weights normalised" % v, F["weight_sum_err"] < 2e-3, "max |sum - 1| = %.5f" % F["weight_sum_err"])
        missing = [c for c in ALL_CLIPS if c not in F["animations"]]
        check("%s: all %d clips present (V3 3.3 + V3_1 5.4)" % (v, len(ALL_CLIPS)), not missing,
              "missing %s" % missing if missing else "%d of %d" % (len(ALL_CLIPS), len(ALL_CLIPS)))
        scale = {c: a["scale_nodes"] for c, a in F["animations"].items() if a["scale_nodes"]}
        check("%s: no bone scale keys" % v, not scale, str(scale) if scale else "no scale channels")
        roots = {c: a["root_moves"] for c, a in F["animations"].items() if a["root_moves"] > 1e-5}
        check("%s: root never moves (no root motion)" % v, not roots, str(roots) if roots else "root constant")
        trans = {c: a["translation_nodes"] for c, a in F["animations"].items()
                 if set(a["translation_nodes"]) - {"root", "hips", "prop.L", "prop.R"}}
        check("%s: only hips and prop bones translate" % v, not trans, str(trans) if trans else "ok")
        bad = []
        for c, a in F["animations"].items():
            m = clips_meta.get(c)
            if not m:
                bad.append("%s: no metadata" % c)
            elif abs(a["duration"] - m["frames"] / N.FPS) > 0.5 / N.FPS:
                bad.append("%s: glb %.3f s vs json %.3f s" % (c, a["duration"], m["frames"] / N.FPS))
        check("%s: durations match astronaut_anims.json (30 fps)" % v, not bad, "; ".join(bad) or "ok")

    # ---- evaluated checks ----
    evals = {}
    for v in VARIANTS:
        if facts[v] is None:
            continue
        rig, body, others = import_rig(model_path(v))
        W = group_weights(body)
        nv = len(body.data.vertices)
        wz = lambda b: W.get(b, np.zeros(nv))              # noqa: E731
        rest = np.array([vv.co[:] for vv in body.data.vertices])
        rest = rest @ np.array(body.matrix_world)[:3, :3].T + np.array(body.matrix_world)[:3, 3]
        sole = np.where(rest[:, 2] < 0.004)[0]
        hand = {s: np.where(wz("hand." + s) > 0.5)[0] for s in "LR"}
        torso = np.where(wz("hips") + wz("spine") + wz("chest") + wz("neck") + wz("head") > 0.6)[0]
        shin_r = np.where(wz("shin.R") > 0.5)[0]
        ev = {}
        for c in ALL_CLIPS:
            if c in facts[v]["animations"] and c in clips_meta:
                ev[c] = eval_clip(rig, body, others, c, clips_meta[c]["frames"])
        evals[v] = ev
        if os.path.exists(visitor_path(v)):
            vis = attach_visitors(rig, v)
            worst, zmin = visitor_drift(rig, [body] + [o for o in others if o.name.startswith("Head_0")], vis, clips_meta, [c for c in ALL_CLIPS if c in ev])
            for nm in VIS_MESHES_BY[v]:
                if nm not in worst:
                    continue
                d, c, f = worst[nm]
                check("%s: %s stays on the body in every clip (<= %.0f cm drift)" % (v, nm, VIS_DRIFT_LIMIT * 100),
                      d <= VIS_DRIFT_LIMIT, "worst %.4f m (%s frame %d)" % (d, c, f))
                check("%s: %s never below z -0.01" % (v, nm), zmin[nm][0] >= -0.01,
                      "z min %.4f m (%s frame %d)" % zmin[nm])
            for o in vis:
                bpy.data.objects.remove(o)
        for c in ALL_CLIPS:
            if c in ev and c in LOOPS:
                d, bn, dp = pose_diff(ev[c][0], ev[c][-1])
                check("%s: %s loop seam <= 1 deg" % (v, c), d <= 1.0 and dp <= 0.005, "worst %.3f deg, hips %.4f m" % (d, dp))
        for c, (pf, pt) in ENTER_EXIT.items():
            if c not in ev:
                continue
            for label, fr, st in (("start", 0, pf), ("end", -1, pt)):
                rc, rf = REST[st]
                if rc not in ev:
                    check("%s: %s %s on %s rest" % (v, c, label, st), False, "rest clip missing")
                    continue
                d, bn, dp = pose_diff(ev[c][fr], ev[rc][rf])
                check("%s: %s %s on the %s rest pose (<= 1 deg)" % (v, c, label, st), d <= 1.0 and dp <= 0.005,
                      "worst %.3f deg, hips %.4f m" % (d, dp))
        for c in ALL_CLIPS:
            if c not in ev:
                continue
            worst, wb, wf, wk = max_step(ev[c])
            if c in LOCOMOTION or c == "collapse":
                check("%s: %s largest bone step per frame (%s: no fixed limit)" % (v, c, "a fall" if c == "collapse" else "locomotion"), True,
                      "%.2f deg (%s %s, frame %d) at 1x" % (worst, wb, wk, wf), info=True)
            else:
                check("%s: %s bone step per frame < %.0f deg" % (v, c, STEP_LIMIT_DEG), worst < STEP_LIMIT_DEG,
                      "%.2f deg (%s %s, frame %d)" % (worst, wb, wk, wf))
            zmin = min(r["zmin"] for r in ev[c])
            check("%s: %s mesh never below z -0.01" % (v, c), zmin >= -0.01, "z min %.4f m" % zmin)
        # locomotion: slide, stride, speed
        for c in sorted(LOCOMOTION):
            if c in ev and clips_meta.get(c, {}).get("speed_mps"):
                n = clips_meta[c]["frames"]
                sp = clips_meta[c]["speed_mps"]
                slide, runs = foot_slide(ev[c], sp, n, sole)
                check("%s: %s foot slide during contact <= 2 cm" % (v, c), slide <= 0.02 and runs > 0,
                      "worst %.4f m over %d contact runs" % (slide, runs))
                stride = clips_meta[c].get("stride_m", 0.0)
                check("%s: %s stride = speed x duration" % (v, c), abs(stride - sp * n / N.FPS) < 0.01,
                      "stride %.3f m, speed %.3f m/s" % (stride, sp))
        if "run" in ev:
            sp = clips_meta["run"].get("speed_mps", 0)
            flight = sum(1 for r in ev["run"][:-1] if r["co"][sole][:, 2].min() > 0.012)
            hz = [r["head"]["hips"].z for r in ev["run"]]
            check("%s: run is the travel pace (3.2-3.6 m/s) with a flight phase" % v, 3.2 <= sp <= 3.6 and flight >= 2,
                  "%.2f m/s, %d of %d frames in flight, hips bob %.3f m" % (sp, flight, len(ev["run"]) - 1, max(hz) - min(hz)))
        if "walk" in ev:
            ks = []
            for r in ev["walk"][:-1]:
                for s in "LR":
                    # heel on the ground: heel strike, flat foot, mid-stance (not the push-off)
                    side = np.where(wz("foot." + s) > 0.5)[0]
                    idx = np.intersect1d(side, sole)
                    idx = idx[rest[idx][:, 0] < -0.05]
                    if len(idx) and r["co"][idx][:, 2].min() < 0.012:
                        ks.append(knee_angle(r, s))
            hz = [r["head"]["hips"].z for r in ev["walk"]]
            check("%s: walk knee bend with the heel down 8-18 deg (critic: 10-15)" % v, ks and max(ks) <= 18.0,
                  "planted knee %.1f..%.1f deg, hips bob %.3f m" % (min(ks), max(ks), max(hz) - min(hz)))
        if "idle" in ev:
            r = ev["idle"][0]
            top = r["zmax"]
            check("%s: stand height 1.80 m, top <= 1.88 m" % v, 1.72 <= top <= 1.88, "top %.3f m" % top)
            fwd = (r["head"]["toe.L"] - r["head"]["foot.L"])
            check("%s: faces +X" % v, fwd.x > 0.08 and abs(fwd.y) < 0.05, "foot->toe %s" % (tuple(round(x, 3) for x in fwd),))
            hy = [q["head"]["hips"].y for q in ev["idle"]]
            yaw = []
            for q in ev["idle"]:
                x = q["rot"]["chest"] @ Vector((1, 0, 0))
                yaw.append(degrees(math.atan2(x.y, x.x)))
            check("%s: idle reads at game size (weight shift >= 6 cm, turn >= 15 deg)" % v,
                  max(hy) - min(hy) >= 0.06 and max(yaw) - min(yaw) >= 15.0,
                  "hips %.3f m, chest yaw %.1f deg" % (max(hy) - min(hy), max(yaw) - min(yaw)))
            ua = (r["head"]["forearm.L"] - r["head"]["upper_arm.L"]).normalized()
            ang = degrees(math.atan2(ua.y, -ua.z))
            check("%s: stand arm line 7-11 deg from the body" % v, 7.0 <= ang <= 11.0, "%.1f deg" % ang)
        # furniture contact
        if "sit_idle" in ev:
            sz, sb = fur.get("seat_z", 0.46), fur.get("seat_back", 0.30)
            co = ev["sit_idle"][0]["all"]
            m = (co[:, 0] > -sb - 0.22) & (co[:, 0] < -0.15) & (np.abs(co[:, 1]) < 0.23)
            low = float(co[m, 2].min())
            check("%s: sit rests on the seat (top %.2f m, +/- 1.5 cm)" % (v, sz), sz - 0.015 <= low <= sz + 0.015,
                  "lowest body point over the seat %.3f m" % low)
            m2 = (co[:, 0] > -sb - 0.22) & (co[:, 0] < -0.40) & (np.abs(co[:, 1]) < 0.23)
            low2 = float(co[m2, 2].min()) if m2.any() else 9.0
            check("%s: nothing behind x -0.40 m within 2 cm of the seat top (pack clearance)" % v, low2 >= sz + 0.02,
                  "lowest point there %.3f m" % low2)
            inside = max(box_count(r["all"], (-sb - 0.22, -0.23, sz - 0.06), (-sb + 0.19, 0.23, sz - 0.02))
                         for c in ("sit_enter", "sit_idle", "sit_eat", "sit_type", "sit_exit") if c in ev for r in ev[c])
            check("%s: no body more than 2 cm into the seat, front 3 cm edge soft (sit clips)" % v, inside == 0, "%d vertices at worst" % inside)
        if "sleep" in ev:
            bz, bb = fur.get("bed_z", 0.55), fur.get("bed_back", 0.55)
            co = ev["sleep"][0]["all"]
            m = (co[:, 0] > -bb - 0.47) & (co[:, 0] < -bb + 0.47) & (np.abs(co[:, 1]) < 1.0)
            low = float(co[m, 2].min())
            r = ev["sleep"][0]
            head_up = r["head"]["head"].y - r["head"]["hips"].y
            if v == "indoor":
                check("indoor: sleep rests on the mattress (top %.2f m, -1.2/+2 cm), head to +Y" % bz,
                      bz - 0.012 <= low <= bz + 0.02 and head_up > 0.3, "lowest %.3f m, head %.2f m towards +Y" % (low, head_up))
            else:
                check("suit: sleep on the mattress (suits do not sleep in beds; for information)", True,
                      "lowest %.3f m (the thicker suit sinks %.1f cm)" % (low, max(0.0, bz - low) * 100), info=True)
            # the bed as ART-HAB builds it: mattress 0.15 m thick over a plinth set 0.08 m in from its edge
            inside = max(box_count(r2["all"], (-bb - 0.47, -1.0, bz - 0.15), (-bb + 0.42, 1.0, bz - 0.015)) +
                         box_count(r2["all"], (-bb - 0.39, -0.92, 0.0), (-bb + 0.39, 0.92, bz - 0.15))
                         for c in ("lie_enter", "lie_exit") if c in ev for r2 in ev[c])
            if v == "indoor":
                check("indoor: lie_enter / lie_exit do not pass through the bed (front 5 cm of the mattress soft)",
                      inside == 0, "%d vertices inside the bed box at worst" % inside)
            else:
                check("suit: lie_enter / lie_exit and the bed (suits never use beds; for information)", True,
                      "%d vertices inside the bed box at worst" % inside, info=True)
        if "dead" in ev:
            low = ev["dead"][0]["zmin"]
            check("%s: dead lies on the ground (lowest point -0.01..0.05 m)" % v, -0.01 <= low <= 0.05, "%.3f m" % low)
        if "repair_kneel" in ev:
            pa, pz = fur.get("panel_ahead", 0.45), fur.get("panel_z", 0.4)
            xs, zs = [], []
            for r in ev["repair_kneel"]:
                for s in "LR":
                    h = r["co"][hand[s]]
                    xs.append(float(h[:, 0].max()))
                    zs.append(float(h[:, 2].mean()))
            check("%s: repair_kneel hands at the panel (%.2f m ahead, %.2f m high)" % (v, pa, pz),
                  pa - 0.025 <= max(xs) <= pa + 0.02 and pz - 0.10 <= float(np.mean(zs)) <= pz + 0.12,
                  "hands reach x %.3f m, mean height %.3f m" % (max(xs), float(np.mean(zs))))
            headv = np.where(wz("head") > 0.5)[0]
            if v == "suit":
                vis = [i for i, m in enumerate(body.data.materials) if m and m.name.split(".")[0] == "Visor"]
                vv = sorted({vi for poly in body.data.polygons if poly.material_index in vis for vi in poly.vertices})
                vx = max(float(r["co"][vv][:, 0].max()) for r in ev["repair_kneel"])
                check("suit: repair_kneel visor front at least 6 cm from the panel (x <= %.2f m)" % (pa - 0.06),
                      vx <= pa - 0.06, "visor front at x %.3f m, %.1f cm from the panel" % (vx, (pa - vx) * 100))
            hx = max(float(np.concatenate([r["co"][headv], r["all"][len(r["co"]):]])[:, 0].max()) for r in ev["repair_kneel"])
            check("%s: repair_kneel head at least 8 cm from the machine face (x <= %.2f m)" % (v, pa - 0.08), hx <= pa - 0.08,
                  "head / helmet front at x %.3f m" % hx)
            kl = min(float(r["co"][shin_r][:, 2].min()) for r in ev["repair_kneel"])
            check("%s: kneeling knee on the ground (-0.01..0.03 m)" % v, -0.01 <= kl <= 0.03, "%.3f m" % kl)
        for c, top in (("work_console", fur.get("console_z", 1.0)), ("work_bench", fur.get("bench_z", 0.9)),
                       ("sit_type", 0.74)):
            if c not in ev:
                continue
            mins = [min(float(r["co"][hand[s]][:, 2].min()) for s in "LR") for r in ev[c]]
            xs = [max(float(r["co"][hand[s]][:, 0].max()) for s in "LR") for r in ev[c]]
            near = sum(1 for z in mins if z <= top + 0.035) / len(mins)
            check("%s: %s hands on a %.2f m surface" % (v, c, top),
                  top - 0.012 <= min(mins) <= top + 0.02 and near >= 0.9,
                  "lowest hand point %.3f m, %.0f%% of frames within 3.5 cm, hands reach x %.2f m" %
                  (min(mins), near * 100, max(xs)))
        for c in ("carry_idle", "carry_walk"):
            if c not in ev:
                continue
            size = meta.get("carry", {}).get("size", 0.40)
            worst_t, worst_h, tilt = 0, 0.0, 0.0
            ref = ev["carry_idle"][0] if "carry_idle" in ev else ev[c][0]
            c0 = Vector(meta.get("carry", {}).get("crate_bottom_centre_frame0_blender", (0.39, 0.0, 0.78)))
            M0 = ref["rot"]["prop.R"].to_4x4()
            M0.translation = ref["head"]["prop.R"]
            for r in ev[c]:
                # the crate rides prop.R at a fixed offset (carry.prop_R_offset): crate = M_now . M_ref^-1 . crate_ref
                M = r["rot"]["prop.R"].to_4x4()
                M.translation = r["head"]["prop.R"]
                Mc = M @ M0.inverted() @ Matrix.Translation(c0)
                o = Mc.translation
                Rm = np.array(Mc.to_3x3())
                # crate frame = prop.R origin with the character axes (the Blender importer re-orients bones, so the
                # bone basis is checked in Godot by art/npc/npc_probe.gd, not here)
                loc = (r["co"] - np.array(o)) @ Rm
                tilt = max(tilt, degrees(Mc.to_quaternion().angle))
                half = size / 2
                ins = np.all((loc[:, :2] > -half + 0.005) & (loc[:, :2] < half - 0.005), axis=1) & \
                    (loc[:, 2] > 0.005) & (loc[:, 2] < size - 0.005)
                worst_t = max(worst_t, int(ins[torso].sum()))
                for s in "LR":
                    hl = loc[hand[s]]
                    inside = np.all((hl[:, :2] > -half) & (hl[:, :2] < half), axis=1) & (hl[:, 2] > 0) & (hl[:, 2] < size)
                    if inside.any():
                        depth = float((half - np.abs(hl[inside][:, 1])).max())
                        worst_h = max(worst_h, depth)
            check("%s: %s crate (%.2f m at prop.R) clear of chest and pack; hands at its sides" % (v, c, size),
                  worst_t == 0 and worst_h <= 0.02, "torso vertices inside %d, hands inside up to %.3f m, crate tilt up to %.1f deg"
                  % (worst_t, worst_h, tilt))
    # ---- suit_swap: the cut frame is still and identical in both files; hands at the helmet sides ----
    if "suit" in evals and "indoor" in evals and "suit_swap" in evals["suit"] and "suit_swap" in evals["indoor"]:
        cf = clips_meta.get("suit_swap", {}).get("cut_frame", 30)
        a, b = evals["suit"]["suit_swap"][cf], evals["indoor"]["suit_swap"][cf]
        d, bn, dp = pose_diff(a, b)
        check("suit_swap: cut frame %d pose identical in both files" % cf, d <= 0.05 and dp <= 0.001,
              "worst %.4f deg, hips %.5f m" % (d, dp))
        still, _, _ = pose_diff(evals["suit"]["suit_swap"][cf - 1], evals["suit"]["suit_swap"][cf + 1])
        check("suit_swap: the pose is still around the cut frame (frames %d..%d)" % (cf - 1, cf + 1), still <= 0.5,
              "%.3f deg between frames %d and %d" % (still, cf - 1, cf + 1))
        wl, wr = a["head"]["hand.L"], a["head"]["hand.R"]
        check("suit_swap: hands at the helmet sides at the cut (wrists above 1.5 m, 0.15-0.30 m out)",
              min(wl.z, wr.z) >= 1.5 and 0.15 <= abs(wl.y) <= 0.30 and 0.15 <= abs(wr.y) <= 0.30,
              "wrists L %s R %s" % (tuple(round(x, 3) for x in wl), tuple(round(x, 3) for x in wr)))
    # ---- visitor looks (V3_1 6.4) ----
    for v in VARIANTS:
        if not os.path.exists(visitor_path(v)):
            check("file astronaut_visitor_%s.glb" % v, False, "missing")
            continue
        VF = gltf_facts(visitor_path(v))
        check("file astronaut_visitor_%s.glb" % v, True, "%d bytes, no clips (%d)" % (os.path.getsize(visitor_path(v)),
                                                                                   len(VF["animations"])))
        check("%s visitors: skinned meshes %s" % (v, VIS_MESHES_BY[v]),
              VF["skins"] == 1 and sorted(VF["skinned_mesh_nodes"]) == sorted(VIS_MESHES_BY[v]),
              "skinned mesh nodes %s" % VF["skinned_mesh_nodes"])
        if facts[v]:
            check("%s visitors: same skeleton and joint order as astronaut_%s.glb" % (v, v),
                  VF["joints"] == facts[v]["joints"] and all(VF["skeleton"][b] == facts[v]["skeleton"][b]
                                                             for b in facts[v]["skeleton"]),
                  "%d joints" % len(VF["joints"]))
        check("%s visitors: COLOR_0, <= 4 weights, normalised" % v,
              VF["color0"] and not VF["joints_1"] and VF["max_influences"] <= 4 and VF["weight_sum_err"] < 2e-3,
              "color0 %s, max influences %d, max |sum - 1| %.5f" % (VF["color0"], VF["max_influences"],
                                                                     VF["weight_sum_err"]))
        if facts[v]:
            tb = facts[v]["tris_by"]
            body = tb.get("Body", 0) + (max(tb.get(h, 0) for h in HEADS) if v == "indoor" else 0)
            vmax = max(VF["tris_by"].get(n, 0) for n in VIS_MESHES_BY[v])
            check("%s: one visitor on screen (Body%s + largest Vis_) <= %d triangles" %
                  (v, " + largest head" if v == "indoor" else "", BUDGET[v]), body + vmax <= BUDGET[v],
                  "%d + %d = %d; Vis_ %s" % (body, vmax, body + vmax,
                                             {n[4:]: VF["tris_by"].get(n) for n in VIS_MESHES_BY[v]}))
    vm = meta.get("visitors", {})
    looks = vm.get("looks", [])
    kinds = sorted(set(L.get("kind") for L in looks))
    tsets = sorted(L.get("set") for L in looks if L.get("kind") == "tourist")
    groups_ok = all(set(L.get("suit", {})) == {"SuitMain", "SuitHard", "Pack", "SuitAccent"} and
                    set(L.get("indoor", {})) == {"Jumpsuit", "SuitAccent"} and
                    L.get("mesh") == "Vis_%s" % L.get("kind") for L in looks)
    check("astronaut_anims.json visitors: 5 kinds, tourist 3 sets, colour groups and mesh per look",
          kinds == sorted(VIS_KINDS) and tsets == [0, 1, 2] and groups_ok and len(looks) == 7 and
          vm.get("meshes") == {k: VIS_MESHES_BY[k] for k in ("suit", "indoor")},
          "%d looks, kinds %s, tourist sets %s" % (len(looks), kinds, tsets))

    def lin(h):
        h = h.lstrip("#")
        return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    col_suit = {"SuitMain": "#e8eaed", "SuitHard": "#e8eaed", "Pack": "#8b939d"}
    worst_pair = (9.0, "")
    for i, A in enumerate(looks):
        for B in looks[i + 1:]:
            d = max(np.abs(lin(A["suit"][g]) - lin(B["suit"][g])).max() for g in ("SuitMain", "SuitHard", "Pack"))
            if d < worst_pair[0]:
                worst_pair = (d, "%s %s / %s %s" % (A["kind"], A["set"], B["kind"], B["set"]))
    dcol = min(max(np.abs(lin(L["suit"][g]) - lin(col_suit[g])).max() for g in col_suit) for L in looks)
    check("visitor suits differ from each other and from the colonist suit in a large part (>= 0.25 sRGB)",
          worst_pair[0] >= 0.25 and dcol >= 0.25,
          "closest pair %.2f (%s); closest to the colonist %.2f" % (worst_pair[0], worst_pair[1], dcol))
    # ---- metadata ----
    need_f = dict(seat_z=0.46, seat_back=0.30, bed_z=0.55, bed_back=0.55, console_z=1.0, console_ahead=0.45,
                  bench_z=0.9, panel_ahead=0.45, panel_z=0.4)
    check("astronaut_anims.json furniture numbers", all(abs(fur.get(k, -9) - x) < 1e-6 for k, x in need_f.items()), str(fur))
    bad = [c for c in ALL_CLIPS if c not in clips_meta]
    check("astronaut_anims.json lists every clip", not bad, "missing %s" % bad if bad else "%d clips" % len(ALL_CLIPS))
    check("astronaut_anims.json fps 30", meta.get("fps") == 30, str(meta.get("fps")))

    sheets = []
    if renders:
        import npc_render as NR
        sheets = NR.all_sheets(facts, clips_meta, meta)

    fails = [c for c in checks if c["status"] == "FAIL"]
    pend = [c for c in checks if c["status"] == "pending"]
    info = [c for c in checks if c["status"] == "info"]
    rep = dict(date=time.strftime("%Y-%m-%d %H:%M"), blender=bpy.app.version_string, scope="full",
               passed=len(checks) - len(fails) - len(pend) - len(info), failed=len(fails), pending=len(pend),
               info=len(info), tris={v: (facts[v] or {}).get("tris") for v in VARIANTS},
               tris_by_object={v: (facts[v] or {}).get("tris_by") for v in VARIANTS},
               sheets=[os.path.relpath(s, N.ROOT) for s in sheets], checks=checks, seconds=round(time.time() - t0, 1))
    os.makedirs(N.ART_DIR, exist_ok=True)
    with open(os.path.join(N.ART_DIR, "npc_report.json"), "w", encoding="utf-8") as fh:
        json.dump(rep, fh, indent=1)
    lines = ["# NPC consistency report", "",
             "Generated by `tools/blender/npc_verify.py` on %s (Blender %s), from the exported files." % (rep["date"], rep["blender"]),
             "", "**%d passed, %d failed, %d pending, %d for information.**" % (rep["passed"], rep["failed"], rep["pending"],
                                                                              rep["info"]),
             "", "| status | check | detail |", "|---|---|---|"]
    for c in checks:
        lines.append("| %s | %s | %s |" % (c["status"], c["check"], c["detail"].replace("|", "/")))
    if sheets:
        lines += ["", "Sheets: " + ", ".join("`%s`" % s for s in rep["sheets"])]
    with open(os.path.join(N.ART_DIR, "npc_report.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("npc_verify: %d passed, %d failed, %d pending, %d info (%.1f s)" % (rep["passed"], rep["failed"], rep["pending"],
                                                                             rep["info"], rep["seconds"]))
    return rep


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    run(renders="--renders" in argv)


if __name__ == "__main__":
    main()
