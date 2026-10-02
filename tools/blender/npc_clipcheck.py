"""
Frontier Habitat 5.0 - ART-NPC: fast clip check on the solver (no meshes, no bake): for every clip of a body, the
largest WORLD bone turn per frame (the npc_verify people step rule, before the bake despike) and the deepest limb
capsule overlap with the torso / head / other thigh (the people_verify.self_overlap rule).  Seconds, not minutes.

  blender --background --factory-startup --python tools/blender/npc_clipcheck.py -- [--body suit|indoor|m1|...]
          [--clips punch,wave] [--all] [--curve punch:forearm.R]

Default body: suit (the v3 rig, s = 1); a people body uses that file's own rest joints and its height scale.
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
import people_mpfb as PM        # noqa: E402  (extends the skeleton with the face and expression bones)
import npc_anims as A           # noqa: E402
import people_anims as PA       # noqa: E402
import people_verify as PV      # noqa: E402
from mathutils import Vector, Quaternion    # noqa: E402

LOCO = {"walk", "run", "carry_walk", "injured_walk", "jog", "child_run", "hold_hands_walk", "hold_hands_walk_r",
        "handcuffed_walk", "escort_walk"}
FALLS = {"collapse", "fall_down"}
REACH_MAX = 0.93
FACE = set(N.BONE_NAMES[24:])


def load_body(b):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = os.path.join(N.MODEL_DIR, ("astronaut_%s.glb" % b) if b in ("suit", "indoor") else ("people_%s.glb" % b))
    bpy.ops.import_scene.gltf(filepath=path)
    return next(o for o in bpy.data.objects if o.type == "ARMATURE")


def overlap(solver, rig_s, pos, D):
    """people_verify.self_overlap on solver positions."""
    H = pos
    T0 = H["hips"] + (H["neck"] - H["hips"]) * 0.15
    torso = (T0, H["neck"], 0.085 * rig_s)
    up = (D["head"] @ solver.rest_q["head"] @ Vector((0, 1, 0))).normalized()
    hc = H["head"] + up * 0.10 * rig_s
    worst = (0.0, "")
    for side in ("L", "R"):
        for a, b, f0, r in PV.LIMBS:
            pa, pb_ = H["%s.%s" % (a, side)], H["%s.%s" % (b, side)]
            p = pa + (pb_ - pa) * f0
            pen = (r * rig_s + torso[2]) - PV._seg_dist(p, pb_, torso[0], torso[1])
            if pen > worst[0]:
                worst = (pen, "%s.%s in the torso" % (a, side))
            pen = (r * rig_s + 0.075 * rig_s) - PV._seg_dist(p, pb_, hc, hc)
            if pen > worst[0]:
                worst = (pen, "%s.%s in the head" % (a, side))
    tl = (H["thigh.L"] + (H["shin.L"] - H["thigh.L"]) * 0.25, H["shin.L"])
    tr = (H["thigh.R"] + (H["shin.R"] - H["thigh.R"]) * 0.25, H["shin.R"])
    pen = 0.11 * rig_s - PV._seg_dist(tl[0], tl[1], tr[0], tr[1])
    if pen > worst[0]:
        worst = (pen, "thigh through thigh")
    return worst


def clips_for(body):
    if body in ("suit", "indoor"):
        return [(c[0], c[4], c[5], c[6]) for c in A.all_clips()]
    return [(c[0], c[4], c[5], c[6]) for c in PA.people_clips()]


def check(body="suit", only=None, curves=(), verbose=True, probes=()):
    rig = load_body(body)
    solver = N.Solver()
    solver.set_rest_from_rig(rig)
    if body in ("suit", "indoor"):
        s = 1.0
    else:
        s = json.load(open(os.path.join(N.MODEL_DIR, "people_manifest.json")))["variants"][body]["scale"]
        PA.ARM_IN = 5.0 if PM.VARIANTS[body]["macro"]["weight"] < 0.58 else 0.0      # as the build sets it
    reach = {sd: (solver.head["forearm." + sd] - solver.head["upper_arm." + sd]).length +
                 (solver.head["hand." + sd] - solver.head["forearm." + sd]).length for sd in ("L", "R")}

    def clamp(P):
        _, _, pos, _ = solver.solve(P)
        for sd in ("L", "R"):
            if P.g("arm.%s.ik" % sd) <= 0 or P.g("arm.%s.chest" % sd) > 0:
                continue
            sh = pos["upper_arm." + sd]
            t = Vector((P.g("arm.%s.x" % sd), P.g("arm.%s.y" % sd), P.g("arm.%s.z" % sd)))
            d = t - sh
            if d.length > REACH_MAX * reach[sd]:
                t = sh + d.normalized() * REACH_MAX * reach[sd]
                P["arm.%s.x" % sd], P["arm.%s.y" % sd], P["arm.%s.z" % sd] = t.x, t.y, t.z
        return P
    rows = []
    for name, loop, n, fn in clips_for(body):
        if only and name not in only:
            continue
        # bake as bake_clip does (local deltas, continuity, despike), then FK back to world rotations / positions
        data = {b: [] for b in N.BONE_NAMES}
        hips_off = []
        prevq = {}
        for f in range(n + 1):
            P = fn(f)
            if body not in ("suit", "indoor"):
                P = PA.retarget(P, s, name)
            P = clamp(P)
            D_, Q_, pos_, ho = solver.solve(P)
            hips_off.append(ho)
            for b in N.BONE_NAMES:
                q = Q_.get(b, Quaternion())
                if b in prevq:
                    if prevq[b].dot(q) < 0:
                        q = -q
                elif q.w < 0:
                    q = -q
                prevq[b] = q
                data[b].append(q)
        L = N.despike_limit(name)
        if L:
            for b in N.BONE_NAMES:
                if b not in N.NO_SMOOTH_BONES:
                    N.despike(data[b], L)
            if L >= 12.0:
                N.despike_world(data, solver)
        prev = None
        ws, wo = (0.0, ""), (0.0, "")
        cur = {}
        for f in range(n + 1):
            D, pos = {"root": Quaternion()}, {"root": solver.head["root"].copy()}
            for b in N.BONE_NAMES:
                if b == "root":
                    continue
                par = N.PARENT[b]
                D[b] = D[par] @ data[b][f]
                pos[b] = (solver.head[b] + hips_off[f]) if b == "hips" else pos[par] + D[par] @ (solver.head[b] - solver.head[par])
            if prev is not None and name not in LOCO and name not in FALLS:
                for b in D:
                    if b in FACE or b.startswith("prop") or b == "root":
                        continue
                    a = 2.0 * degrees(math.acos(min(1.0, abs(prev[b].dot(D[b])))))
                    if a > ws[0]:
                        ws = (a, "%s f%d" % (b, f))
            for cn, bn in curves:
                if cn == name and prev is not None:
                    cur.setdefault(bn, []).append(2.0 * degrees(math.acos(min(1.0, abs(prev[bn].dot(D[bn]))))))
            pen, where = overlap(solver, s, pos, D)
            for cn, fr in probes:
                if cn == name and int(fr) == f:
                    print("PROBE %s f%d  pen %.1f mm %s" % (name, f, pen * 1000, where))
                    for b in ("hips", "spine", "chest", "neck", "head", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"):
                        print("   %-12s %s" % (b, tuple(round(x, 3) for x in pos[b])))
            if pen > wo[0]:
                wo = (pen, "%s f%d" % (where, f))
            prev = D
        rows.append((name, ws, wo))
        for bn, v in cur.items():
            print("CURVE %s %s: %s" % (name, bn, " ".join("%.1f" % x for x in v)))
    bad_s = [r for r in rows if r[1][0] > 15.0]
    bad_o = [r for r in rows if r[2][0] > 0.005]
    if verbose:
        print("== %s (s %.3f): %d clips; step > 15 deg: %d; overlap > 5 mm: %d" % (body, s, len(rows), len(bad_s), len(bad_o)))
        for r in sorted(rows, key=lambda r: -max(r[1][0] / 15.0, r[2][0] / 0.005)):
            flag = ("STEP " if r[1][0] > 15.0 else "") + ("OVERLAP" if r[2][0] > 0.005 else "")
            if flag or os.environ.get("NPC_ALL"):
                print("  %-16s step %5.1f (%s)  overlap %5.1f mm (%s)  %s" % (r[0], r[1][0], r[1][1], r[2][0] * 1000, r[2][1], flag))
    return rows


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bodies = argv[argv.index("--body") + 1].split(",") if "--body" in argv else ["suit"]
    only = set(argv[argv.index("--clips") + 1].split(",")) if "--clips" in argv else None
    curves = [tuple(x.split(":")) for x in argv[argv.index("--curve") + 1].split(",")] if "--curve" in argv else []
    if "--all" in argv:
        os.environ["NPC_ALL"] = "1"
    probes = [tuple(x.split(":")) for x in argv[argv.index("--probe") + 1].split(",")] if "--probe" in argv else []
    for b in bodies:
        check(b, only, curves, probes=probes)


if __name__ == "__main__":
    main()
