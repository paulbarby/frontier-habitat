"""
Frontier Habitat 5.0 - ART-NPC: build the people files (Blender --background only).

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/people_build.py -- --variants m1,f1

Per variant: assets/models/people_<variant>.glb = the rig (v3 skeleton + jaw + lids, scaled to the variant's height),
Head_<variant> (head, eyes, teeth, ears; SkinFace + face texture), Hair_<variant>, Outfit_<id> for every outfit of the
variant, and every clip baked on that rig.  Writes assets/models/people_manifest.json and npc_pairs.json.
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
import people_face as PF        # noqa: E402
N.extend_skeleton(PF.FACE_BONES)
import people_mesh as PM        # noqa: E402
import people_hair as PH        # noqa: E402
import people_outfits as PO     # noqa: E402
import people_textures as PT    # noqa: E402
import people_anims as PA       # noqa: E402

MANIFEST = os.path.join(N.MODEL_DIR, "people_manifest.json")
PAIRS = os.path.join(N.MODEL_DIR, "npc_pairs.json")

VARIANTS = {
    "m1": dict(sex="m", height=1.80, outfits=["uniform_engineering", "casual_a"]),
    "f1": dict(sex="f", height=1.68, outfits=["uniform_engineering", "casual_a"]),
}
BUDGET = dict(lod0=24000, lod1=4000)


def add_texture(mat, image_path):
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    img = bpy.data.images.load(image_path, check_existing=True)
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = img
    nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    # the factor stays white: the game multiplies the tint on top (Skin: tone, Hair: hair colour)
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)


def build_variant(v):
    t0 = time.time()
    spec = VARIANTS[v]
    s = spec["height"] / 1.80
    C.reset_scene()
    sc = bpy.context.scene
    sc.render.fps = N.FPS
    sc.render.fps_base = 1.0
    os.makedirs(PT.TEX_DIR, exist_ok=True)
    eyes = os.path.join(PT.TEX_DIR, "people_eyes.png")
    hair_tex = os.path.join(PT.TEX_DIR, "people_hair.png")
    if not os.path.exists(eyes):
        PT.eyes_atlas(eyes)
    if not os.path.exists(hair_tex):
        PT.hair_texture(hair_tex)
    rig = N.build_rig("Rig")
    head_md = PF.build_head(v)
    hair_md = PH.build_hair(v)
    outfit_mds = [PO.OUTFITS[o](spec["sex"]) for o in spec["outfits"]]
    tris = {head_md.name: head_md.tris(), hair_md.name: hair_md.tris()}
    for md in outfit_mds:
        tris[md.name] = md.tris()
    objs = {}
    head = PM.to_object(head_md, rig, texture_dir=PT.TEX_DIR)
    objs[head.name] = head
    hair = PM.to_object(hair_md, rig)
    objs[hair.name] = hair
    for md in outfit_mds:
        ob = PM.to_object(md, rig, texture_dir=PT.TEX_DIR)
        objs[ob.name] = ob
    # face texture (baked from the geometry) and the hair strands
    PT.unwrap_skin(head)
    face = os.path.join(PT.TEX_DIR, "face_%s.png" % v)
    PT.bake_face(head, v, face)
    for m in head.data.materials:
        if m.name.split(".")[0] == "Skin":
            m.name = "SkinFace"
            add_texture(m, face)
    for m in hair.data.materials:
        add_texture(m, hair_tex)
    # scale the variant: weights and the face texture were made in the 1.80 m frame; now the mesh data and the rig's
    # bones take the variant's size (no object scale, no scale keys)
    if abs(s - 1.0) > 1e-6:
        from mathutils import Matrix
        for ob in objs.values():
            ob.data.transform(Matrix.Scale(s, 4))
            ob.data.update()
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = rig
        rig.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        for eb in rig.data.edit_bones:
            eb.head = eb.head * s
            eb.tail = eb.tail * s
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()
    # ambient occlusion: the head under its hair; each outfit on its own
    occ = {head.name: [head.name, hair.name], hair.name: [hair.name, head.name]}
    for md in outfit_mds:
        occ[md.name] = [md.name]
    C.bake_ao(objs, occ, dist=0.12 * s, samples=64, min_ao=0.45, strength=1.0, verbose=False)
    for ob in objs.values():
        N.smooth_ao(ob, iterations=3, floor={"SkinFace": 0.62, "Skin": 0.62, "Hair": 0.55, "Coverall": 0.55,
                                             "Cotton": 0.60, "ClothTint": 0.58, "Denim": 0.55})
    # clips
    solver = N.Solver()
    solver.set_rest_from_rig(rig)
    meta = {}
    for (name, kind, pf, pt, loop, frames, fn, extra) in PA.people_clips():
        fv = (lambda fn, name: (lambda f: PA.retarget(fn(f), s, name)))(fn, name)
        N.bake_clip(rig, solver, name, fv, frames)
        m = dict(frames=frames, duration_s=round(frames / N.FPS, 4), kind=kind, pose_from=pf, pose_to=pt, loop=loop)
        m.update(extra)
        meta[name] = m
    N.reset_pose(rig)
    path = os.path.join(N.MODEL_DIR, "people_%s.glb" % v)
    N.export_glb_skinned(path)
    print("  %s: %s  %.1f s" % (v, tris, time.time() - t0))
    return dict(tris=tris, clips=meta, scale=s, path=path)


def write_manifest(results):
    doc = {}
    if os.path.exists(MANIFEST):
        try:
            doc = json.load(open(MANIFEST, encoding="utf-8"))
        except Exception:
            doc = {}
    doc["version"] = "5.0-pilot"
    doc["status"] = ("PILOT: m1 and f1, outfits uniform_engineering and casual_a, 24 v3 clips + 6 new clips. "
                     "The other variants, children, outfits, clips, LOD1 and the robot dancers follow after the critic "
                     "pilot.  Names and structure below are final unless a note says otherwise.")
    doc["skeleton"] = dict(bones=N.BONE_NAMES, face_bones=[b[0] for b in PF.FACE_BONES],
                           note=("The v3 skeleton (same names, hierarchy and bind directions) plus jaw and lids under "
                                 "head.  jaw: the lower face, lower lip, lower teeth; lids: both upper eyelids (blink). "
                                 "Each variant's rig is the v3 rig scaled by its height / 1.80 (applied, no scale "
                                 "keys).  The astronaut_* files are unchanged."))
    variants = doc.get("variants", {})
    for v, r in results.items():
        spec = VARIANTS[v]
        variants[v] = dict(sex=spec["sex"], height_m=spec["height"], scale=round(r["scale"], 4),
                           file="people_%s.glb" % v, head="Head_%s" % v, hair="Hair_%s" % v,
                           outfits={o: "Outfit_%s" % o for o in spec["outfits"]},
                           triangles=r["tris"],
                           triangles_on_screen={o: r["tris"]["Head_%s" % v] + r["tris"]["Hair_%s" % v] +
                                                r["tris"]["Outfit_%s" % o] for o in spec["outfits"]})
    doc["variants"] = variants
    doc["outfits"] = {
        "uniform_engineering": dict(who=["technician", "operator"], stripe="SuitAccent (department colour)",
                                    look="coverall, tool belt, amber department stripe on chest and sleeves, work boots"),
        "casual_a": dict(who=["off duty"], look="m: white tee, jeans, belt, sneakers; f: fitted tee (ClothTint), slim "
                                                 "jeans, sneakers"),
    }
    doc["draw"] = dict(
        per_person=("Draw Head_<variant>, Hair_<variant> and ONE Outfit_<id> of the person's variant (the outfit mesh "
                    "includes the skin it leaves visible: forearms, hands).  Hide every other Outfit_*."),
        materials={
            "SkinFace": "tint like v3 Skin (mode 2, replace albedo by the skin tone); the face texture multiplies "
                        "(white = the tone).  Base colour factor is white.",
            "Skin": "tint like v3 Skin (mode 2): arms and hands in the outfit meshes",
            "Hair": "tint like v3 Hair (mode 3); people_hair.png multiplies (strands)",
            "SuitAccent": "the department / role colour (v3 mode 1)",
            "ClothTint": "a per-person clothes colour (new: please add a mode; until then it keeps its own colour)",
            "Eye": "plain, textured (people_eyes.png: 4 irises)",
            "others": "plain: Coverall, Cotton, Denim, Leather, Sole, Rubber, Metal, Nail, Mouth, Teeth",
        },
        vertex_color="COLOR_0.r = baked ambient occlusion (as v3)",
        lod="LOD0 only in the pilot (<= 24k triangles per person on screen).  LOD1 (<= 4k) follows.",
    )
    clips = {}
    for v, r in results.items():
        for name, m in r["clips"].items():
            clips.setdefault(name, m)
    doc["clips"] = clips
    doc["clips_note"] = ("Every clip is baked into every people_<variant>.glb on that variant's rig (heights differ; "
                         "seats, beds, desks and consoles keep their world heights).  Clip names, frames and pose "
                         "states are the same in every variant.  New pose state 'stool' (sit_bar_stool).  Pairs: "
                         "npc_pairs.json.  Vehicle clips stay in the astronaut files (people wear the suit outside).")
    doc["furniture"] = dict(bar_stool=PA.BAR_STOOL)
    doc["textures"] = dict(face="people_tex/face_<variant>.png (1024 px, embedded in the GLB)",
                           eyes="people_tex/people_eyes.png (embedded)", hair="people_tex/people_hair.png (embedded)")
    tmp = MANIFEST + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=1)
    os.replace(tmp, MANIFEST)
    with open(PAIRS + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(PA.pairs_json(), fh, indent=1)
    os.replace(PAIRS + ".tmp", PAIRS)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    vs = list(VARIANTS)
    if "--variants" in argv:
        vs = argv[argv.index("--variants") + 1].split(",")
    results = {}
    for v in vs:
        results[v] = build_variant(v)
    write_manifest(results)
    print("done")


if __name__ == "__main__":
    main()
