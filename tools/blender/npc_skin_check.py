"""
Frontier Habitat 5.0 - ART-NPC: skinning check (ORCH-to-ART-NPC 2026-10-01 item 2: weights at shoulders, neck, spine and
hips).  For one body mesh and a set of clips it measures how far the surface is squeezed or stretched: every mesh edge
against its length in the bind pose, over the frames of the clips.  A collapsed shoulder, a pinched neck, a candy-wrapper
twist or a folded hip show as edges at less than 55 % (or more than 180 %) of their rest length.

  blender --background --factory-startup --python tools/blender/npc_skin_check.py -- --body m1 [--outfit casual_a]
          [--clips idle,work_bench,...] [--step 4] [--out art/people/skin_m1.json]

Prints per region (by the bone that moves each end of the edge: neck, shoulder, spine, hips) the worst squeeze and
stretch, and the clip and frame where it happens.  Only edges longer than 6 mm at rest count.
"""
import bpy
import os
import sys
import json
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
import people_verify as PV      # noqa: E402

REGIONS = {
    "neck": ("neck", "head"),
    "shoulder": ("shoulder.L", "shoulder.R", "upper_arm.L", "upper_arm.R", "chest"),
    "spine": ("spine", "chest", "hips"),
    "hips": ("hips", "thigh.L", "thigh.R"),
    "elbow": ("upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R"),
    "knee": ("thigh.L", "thigh.R", "shin.L", "shin.R"),
}


def load(body, outfit):
    rig, meshes = PV.import_person(body)
    ob = meshes["Outfit_" + outfit]
    return rig, ob


def measure(body="m1", outfit="casual_a", clips=None, step=4, verbose=True):
    rig, ob = load(body, outfit)
    me = ob.data
    names = {g.index: g.name for g in ob.vertex_groups}
    nv = len(me.vertices)
    top = []
    for v in me.vertices:
        top.append(names.get(max(v.groups, key=lambda g: g.weight).group, "?") if v.groups else "?")
    top = np.array(top)
    ev = np.array([[e.vertices[0], e.vertices[1]] for e in me.edges])
    # bind pose
    PV.set_clip(rig, "idle", 0)
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    rig.animation_data.action = None
    bpy.context.view_layer.update()
    rest = PV.world_co(ob)
    L0 = np.linalg.norm(rest[ev[:, 0]] - rest[ev[:, 1]], axis=1)
    keep = L0 > 0.006
    ev, L0 = ev[keep], L0[keep]
    masks = {}
    for rg, bones in REGIONS.items():
        in_ = np.isin(top[ev[:, 0]], bones) & np.isin(top[ev[:, 1]], bones)
        # an edge that spans two different bones of the region (the joint itself)
        masks[rg] = in_ & (top[ev[:, 0]] != top[ev[:, 1]])
    worst = {rg: dict(min=(9.0, "", 0), max=(0.0, "", 0)) for rg in REGIONS}
    names_all = clips or [c for c in json.load(open(PV.MANIFEST))["clips"]]
    for c in names_all:
        act = next((a for a in bpy.data.actions if a.name.split("_Rig")[0] == c), None)
        if act is None:
            continue
        n = int(round(act.frame_range[1]))
        for f in range(0, n + 1, step):
            PV.set_clip(rig, c, f)
            co = PV.world_co(ob)
            r = np.linalg.norm(co[ev[:, 0]] - co[ev[:, 1]], axis=1) / L0
            for rg, m in masks.items():
                if not m.any():
                    continue
                lo, hi = float(np.percentile(r[m], 2)), float(np.percentile(r[m], 98))
                if lo < worst[rg]["min"][0]:
                    worst[rg]["min"] = (lo, c, f)
                if hi > worst[rg]["max"][0]:
                    worst[rg]["max"] = (hi, c, f)
    if verbose:
        print("SKIN %s %s: %d edges" % (body, outfit, len(L0)))
        for rg, w in worst.items():
            print("  %-9s squeeze(p2) %.2f (%s f%d)   stretch(p98) %.2f (%s f%d)" % (
                rg, w["min"][0], w["min"][1], w["min"][2], w["max"][0], w["max"][1], w["max"][2]))
    return worst


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    body = argv[argv.index("--body") + 1] if "--body" in argv else "m1"
    outfit = argv[argv.index("--outfit") + 1] if "--outfit" in argv else "casual_a"
    clips = argv[argv.index("--clips") + 1].split(",") if "--clips" in argv else None
    step = int(argv[argv.index("--step") + 1]) if "--step" in argv else 4
    w = measure(body, outfit, clips, step)
    if "--out" in argv:
        with open(argv[argv.index("--out") + 1], "w") as fh:
            json.dump({rg: {k: list(v) for k, v in d.items()} for rg, d in w.items()}, fh, indent=1)


if __name__ == "__main__":
    main()
