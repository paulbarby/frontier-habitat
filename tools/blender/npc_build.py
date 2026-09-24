"""
Frontier Habitat 3.0 - ART-NPC build driver.

Run (Git Bash, never without --background):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/npc_build.py -- --variant suit

Writes assets/models/astronaut_<variant>.glb (atomic: .tmp.glb then rename) and assets/models/astronaut_anims.json.
One skinned mesh `Body` on the armature `Rig` (section 3.2 skeleton), every clip as a glTF animation, 30 fps,
COLOR_0 = baked ambient occlusion.
"""
import bpy
import os
import sys
import json
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C          # noqa: E402
import npc_common as N          # noqa: E402
import npc_anims as A           # noqa: E402

ANIMS_JSON = os.path.join(N.MODEL_DIR, "astronaut_anims.json")
BUDGET = {"suit": 7000, "indoor": 6000}


def build_variant(variant):
    t0 = time.time()
    C.reset_scene()
    sc = bpy.context.scene
    sc.render.fps = N.FPS
    sc.render.fps_base = 1.0
    if variant == "suit":
        import npc_suit
        parts = [npc_suit.build_suit_body()]
    elif variant == "indoor":
        import npc_indoor
        parts = npc_indoor.build_indoor_parts()
    else:
        raise SystemExit("unknown variant %s" % variant)
    rig = N.build_rig("Rig")
    mset = N.NpcMaterialSet()
    objs = {part.name: N.build_skinned_mesh(part, rig, mset) for part in parts}
    tris = sum(sum(len(f) - 2 for f in part.faces) for part in parts)
    print("  %s: %d vertices, %d triangles (%s)" % (variant, sum(len(p.verts) for p in parts), tris,
                                                   ", ".join("%s %d" % (p.name, sum(len(f) - 2 for f in p.faces)) for p in parts)))
    bpy.context.view_layer.update()
    if variant == "suit":
        occ = {"Body": ["Body"]}
    else:
        occ = {n: [n, "Body"] for n in objs}
        occ["Body"] = ["Body", "Head_0"]
    C.bake_ao(objs, occ, dist=0.16, samples=96, min_ao=0.42, strength=1.0)
    for ob in objs.values():
        N.smooth_ao(ob, iterations=4, floor={"SuitMain": 0.65, "SuitHard": 0.62, "Jumpsuit": 0.55, "Skin": 0.62,
                                             "Hair": 0.55})
    solver = N.Solver()
    solver.set_rest_from_rig(rig)
    meta = {}
    clips = A.all_clips()
    carry_offset(solver, dict((c[0], c[6]) for c in clips)["carry_idle"])
    for (name, kind, pf, pt, loop, frames, fn, extra) in clips:
        N.bake_clip(rig, solver, name, fn, frames)
        m = dict(frames=frames, duration_s=round(frames / N.FPS, 4), kind=kind, pose_from=pf, pose_to=pt, loop=loop)
        m.update(extra)
        meta[name] = m
        print("    clip %-10s %4d frames" % (name, frames))
    N.reset_pose(rig)
    path = os.path.join(N.MODEL_DIR, "astronaut_%s.glb" % variant)
    N.export_glb_skinned(path)
    print("  wrote", path, "%.1f s" % (time.time() - t0))
    return path, meta, tris


CARRY_OFFSET = {}


def carry_offset(solver, carry_idle_fn):
    """The crate rides prop.R at one fixed local transform.  Computed at carry_idle frame 0: the crate's bottom centre
    (given for the chest at rest in CARRY) with the character axes.  Godot sees the Blender bone axes unchanged
    (bone basis = C . R_blender, C: x->x, y->-z, z->y; measured with art/npc/npc_probe.gd), so the offset in the
    prop.R frame is: basis = R^T C^T, origin = R^T (crate - prop)."""
    from mathutils import Matrix, Vector
    P0 = carry_idle_fn(0)
    D, Q, pos, _ = solver.solve(P0)
    Rb = (D["prop.R"] @ solver.rest_q["prop.R"]).to_matrix()
    pb = pos["prop.R"]
    c = Vector(A.CARRY["bottom_centre"])
    cw = pos["chest"] + D["chest"] @ (c - solver.head["chest"])
    Cm = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
    ob = Rb.transposed() @ (cw - pb)
    Bm = Rb.transposed() @ Cm.transposed()
    CARRY_OFFSET.clear()
    CARRY_OFFSET.update(dict(
        prop_R_offset=dict(origin=[round(x, 5) for x in ob],
                           basis_x=[round(Bm[i][0], 5) for i in range(3)],
                           basis_y=[round(Bm[i][1], 5) for i in range(3)],
                           basis_z=[round(Bm[i][2], 5) for i in range(3)]),
        crate_bottom_centre_frame0_blender=[round(x, 5) for x in cw]))


def write_meta(meta):
    doc = {}
    if os.path.exists(ANIMS_JSON):
        try:
            with open(ANIMS_JSON, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
        except Exception:
            doc = {}
    doc["fps"] = N.FPS
    doc["height"] = 1.80
    doc["frames_note"] = ("frames = index of the last frame; the clip lasts frames / fps seconds. Loops: the last "
                          "frame equals the first. Locomotion: playback scale = ground speed / speed_mps; "
                          "stride_m = ground distance of one loop.")
    doc["skeleton"] = N.BONE_NAMES
    clips = doc.get("clips", {})
    clips.update(meta)
    doc["clips"] = clips
    doc["furniture"] = A.FURNITURE
    doc["carry"] = dict(A.CARRY, **CARRY_OFFSET)
    doc["carry"].pop("bottom_centre", None)
    doc["carry"]["note"] = ("prop.R has no keys in any clip (it keeps its place in the right hand). Attach the crate to "
                            "prop.R with the fixed local Transform3D prop_R_offset (Godot bone space: Basis(basis_x, "
                            "basis_y, basis_z) columns, origin); its origin is the crate's bottom centre. The crate "
                            "rides the right hand in carry_idle and carry_walk.")
    doc["collapse_ends_on"] = "dead frame 0 (on the ground); dead is the lie-state loop after collapse"
    doc["pose_rest"] = {k: {"clip": v[0], "frame": v[1]} for k, v in A.POSE_STATE_REST.items()}
    tmp = ANIMS_JSON + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=1)
    os.replace(tmp, ANIMS_JSON)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    variants = ["suit"]
    if "--variant" in argv:
        variants = argv[argv.index("--variant") + 1].split(",")
    allmeta = {}
    for v in variants:
        _, meta, _ = build_variant(v)
        allmeta.update(meta)
    write_meta(allmeta)
    print("done")


if __name__ == "__main__":
    main()
