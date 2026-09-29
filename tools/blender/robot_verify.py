"""
Frontier Habitat 5.0 - ART-NPC: checks for the robot dancer (called by npc_verify.py at the end of its run).

File and skeleton (the 24 v3 bones), budget, AO and weights, clips (names, durations, no scale keys, root still),
per-frame bone steps < 15 deg, exact loop seams, every clip starts on the same pose (chains with no blend), nothing
below the podium top, feet on the podium (0.80 m radius round the pole), nothing inside the pole (gripping hands
may press up to 2 cm into it).
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
import people_verify as PV      # noqa: E402

MANIFEST = os.path.join(N.MODEL_DIR, "robot_manifest.json")
PATH = os.path.join(N.MODEL_DIR, "robot_dancer.glb")
STEP_LIMIT = 15.0
BUDGET = 24000
PODIUM_R = 0.80
V3_BONES = ["root", "hips", "spine", "chest", "neck", "head"] + [
    "%s.%s" % (b, s) for s in ("L", "R") for b in ("shoulder", "upper_arm", "forearm", "hand", "prop", "thigh",
                                                     "shin", "foot", "toe")]


def import_robot():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    bpy.context.scene.render.fps = N.FPS               # the importer converts clip time to the scene rate
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=PATH)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    ob = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.split(".")[0] == "Robot_dancer")
    return rig, ob


def vertex_bones(ob):
    names = {g.index: g.name for g in ob.vertex_groups}
    out = []
    for v in ob.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        out.append(names.get(best.group, "") if best else "")
    return np.array(out)


def run(check, gltf_facts):
    if not os.path.exists(MANIFEST) or not os.path.exists(PATH):
        check("robot: robot_dancer.glb and robot_manifest.json", False, "missing")
        return
    M = json.load(open(MANIFEST, encoding="utf-8"))
    F = gltf_facts(PATH)
    check("robot: one skinned mesh Robot_dancer", F["skinned_mesh_nodes"] == ["Robot_dancer"],
          "%s" % F["skinned_mesh_nodes"])
    check("robot: skeleton = the 24 v3 bones", sorted(F["joints"]) == sorted(V3_BONES), "%d joints" % len(F["joints"]))
    par_ok = all(F["skeleton"].get(b, {}).get("parent") == p for b, p in list(N.PARENT.items())[:24])
    check("robot: bone parents as v3", par_ok, "ok" if par_ok else "differs")
    tris = F["tris_by"].get("Robot_dancer", 0)
    check("robot: <= %d triangles" % BUDGET, 0 < tris <= BUDGET, "%d" % tris)
    check("robot: COLOR_0 (AO), <= 4 weights, normalised",
          F["color0"] and not F["joints_1"] and F["max_influences"] <= 4 and F["weight_sum_err"] < 2e-3,
          "max influences %d, max |sum - 1| %.5f" % (F["max_influences"], F["weight_sum_err"]))
    missing = [c for c in M["clips"] if c not in F["animations"]]
    check("robot: every clip of the manifest (%d)" % len(M["clips"]), not missing,
          "missing %s" % missing if missing else ", ".join(M["clips"]))
    bad = [c for c, a in F["animations"].items() if c in M["clips"] and
           abs(a["duration"] - M["clips"][c]["frames"] / N.FPS) > 0.5 / N.FPS]
    check("robot: durations match the manifest", not bad, "%s" % bad if bad else "ok")
    scale = [c for c, a in F["animations"].items() if a["scale_nodes"]]
    roots = [c for c, a in F["animations"].items() if a["root_moves"] > 1e-5]
    check("robot: no scale keys, root never moves", not scale and not roots, "scale %s, root %s" % (scale, roots))

    rig, ob = import_robot()
    vb = vertex_bones(ob)
    hand = {"L": np.array([b.startswith("hand.L") for b in vb]), "R": np.array([b.startswith("hand.R") for b in vb])}
    px, py = M["anchor"]["pole_local"]
    pr = M["anchor"]["pole_radius_m"]
    worst_step, worst_seam, zmin = (0.0, ""), (0.0, ""), (9.0, "")
    worst_chain = (0.0, "")
    podium = (0.0, "")
    pole_body, pole_hand = (0, ""), (0.0, "")
    ref0 = None
    for c, m in M["clips"].items():
        if PV.set_clip(rig, c, 1) is None:
            continue
        PV.set_clip(rig, c, 0)                       # frame 0 after another frame: the depsgraph is current
        n = m["frames"]
        prev = first = None
        for f in range(0, n + 1):
            bpy.context.scene.frame_set(f)
            R = PV.bone_rots(rig)
            hips = rig.pose.bones["hips"].location.copy()
            if first is None:
                first = (R, hips)
                if ref0 is None:
                    ref0 = (R, hips, c)
                else:
                    a = max(PV.rot_angle(ref0[0][b], R[b]) for b in R)
                    d = (ref0[1] - hips).length
                    if a + d * 100 > worst_chain[0]:
                        worst_chain = (a + d * 100, "%s start vs %s start: %.2f deg, %.1f mm" % (c, ref0[2], a, d * 1000))
            if prev is not None:
                for b in R:
                    a = PV.rot_angle(prev[b], R[b])
                    if a > worst_step[0]:
                        worst_step = (a, "%s %s f%d" % (c, b, f))
            prev = R
            if f % 2 == 0:
                co = PV.world_co(ob)
                z = co[:, 2].min()
                if z < zmin[0]:
                    zmin = (z, "%s f%d" % (c, f))
                low = co[:, 2] < 0.25
                if low.any():
                    r = np.sqrt((co[low, 0] - px) ** 2 + (co[low, 1] - py) ** 2).max()
                    if r > podium[0]:
                        podium = (r, "%s f%d" % (c, f))
                dist = np.sqrt((co[:, 0] - px) ** 2 + (co[:, 1] - py) ** 2)
                inside = dist < pr
                gripping = hand["L"] | hand["R"]
                nb = int((inside & ~gripping).sum())
                if nb > pole_body[0]:
                    pole_body = (nb, "%s f%d" % (c, f))
                if (inside & gripping).any():
                    depth = pr - dist[inside & gripping].min()
                    if depth > pole_hand[0]:
                        pole_hand = (depth, "%s f%d" % (c, f))
        a = max(PV.rot_angle(first[0][b], prev[b]) for b in prev)
        if a > worst_seam[0]:
            worst_seam = (a, c)
    check("robot: bone step per frame < %.0f deg (every clip)" % STEP_LIMIT, worst_step[0] < STEP_LIMIT,
          "%.2f deg (%s)" % worst_step)
    check("robot: loop seams <= 1 deg", worst_seam[0] <= 1.0, "%.3f deg (%s)" % worst_seam)
    check("robot: every clip starts on the same pose (chain with no blend; <= 1 deg, 1 mm)", worst_chain[0] <= 1.1,
          worst_chain[1] or "all equal")
    check("robot: never below the podium top (z >= -0.01)", zmin[0] >= -0.01, "%.4f m (%s)" % zmin)
    check("robot: feet stay on the podium (<= %.2f m from the pole axis, below 0.25 m)" % (PODIUM_R - 0.05),
          podium[0] <= PODIUM_R - 0.05, "%.3f m (%s)" % podium)
    check("robot: nothing inside the pole (r %.3f m; gripping hands <= 2 cm into it)" % pr,
          pole_body[0] == 0 and pole_hand[0] <= 0.02,
          "body vertices inside: %d (%s); hand depth %.3f m (%s)" % (pole_body + pole_hand))
