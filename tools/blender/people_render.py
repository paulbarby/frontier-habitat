"""
Frontier Habitat 5.0 - ART-NPC: render sheets for the people (imports the EXPORTED people_<variant>.glb files).

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/people_render.py -- --sheets closeup,outfits,faces,clips

Sheets (art/people/): people_closeup.png (front and 3/4 at 1.5 m, every variant and outfit), people_outfits.png (four
sides), people_faces.png (face close-ups, blink and jaw), people_clips.png (the new clips, 6 frames each; the hug as a
pair).  Tints as the game applies them: skin tone x face texture, hair colour x strands, department colour.
"""
import bpy
import os
import sys
import json
from math import radians, sin, cos
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
import npc_render as NR         # noqa: E402
import ext_render as R          # noqa: E402

ART = os.path.join(N.ROOT, "art", "people")
TMP = os.path.join(ART, "_tmp")
MANIFEST = os.path.join(N.MODEL_DIR, "people_manifest.json")
# the game's palettes (shaders/npc_skin.gdshader, linear) and one department colour
SKIN_TONES = NR.SKIN_TONES
HAIR_COLOURS = [(0.010, 0.008, 0.007), (0.075, 0.035, 0.015), (0.34, 0.075, 0.018), (0.58, 0.40, 0.17)]
LOOK = {"m1": dict(tone=2, hair=1, cloth=(0.60, 0.08, 0.05)), "f1": dict(tone=4, hair=2, cloth=(0.05, 0.20, 0.42))}
DEPT = (1.0, 0.35, 0.01)          # technician amber


def tmpdir():
    os.makedirs(TMP, exist_ok=True)
    g = os.path.join(TMP, ".gdignore")
    if not os.path.exists(g):
        open(g, "w").close()


def studio(w, h, ground=(0.46, 0.44, 0.42)):
    sc = NR.setup(w, h, ground=ground, samples=48)
    # a softer, face-friendly light: a big warm key, a cool fill, a rim
    for o in list(bpy.data.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o)
    NR._light("AREA", "Key", 260.0, direction=(0.7, -0.55, 0.45), loc=(2.2, -1.7, 2.9), size=2.2, color=(1.0, 0.95, 0.9))
    NR._light("AREA", "Fill", 90.0, direction=(0.5, 0.8, 0.2), loc=(1.4, 2.4, 2.0), size=3.0, color=(0.85, 0.9, 1.0))
    NR._light("AREA", "Rim", 170.0, direction=(-0.8, 0.2, 0.5), loc=(-2.4, 0.6, 2.6), size=1.5, color=(1.0, 0.95, 0.9))
    for o in bpy.data.objects:
        if o.type == "LIGHT":
            o.rotation_euler = (o.location * -1).to_track_quat("-Z", "Y").to_euler()
    return sc


def tint(m, rgb):
    """Multiply the material's base colour (texture or constant) by rgb, as the game's tint does."""
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    if bsdf is None:
        return
    link = bsdf.inputs["Base Color"].links
    if link:
        src = link[0].from_socket
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        mix.inputs[7].default_value = (*rgb, 1.0)
        nt.links.new(src, mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)


def import_person(variant, outfit, look=None, loc=(0, 0, 0), rot_z=0.0):
    """Import people_<variant>.glb, keep one outfit, tint like the game.  Returns (rig, meshes)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(N.MODEL_DIR, "people_%s.glb" % variant))
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    R.ao_materials()
    L = dict(LOOK[variant], **(look or {}))
    meshes = []
    for o in new:
        if o.type != "MESH":
            continue
        nm = o.name.split(".")[0]
        if nm.startswith("Outfit_") and nm != "Outfit_" + outfit:
            bpy.data.objects.remove(o)
            continue
        if not (nm.startswith(("Outfit_", "Head_", "Hair_"))):
            bpy.data.objects.remove(o)
            continue
        meshes.append(o)
        for sl in o.material_slots:
            if sl.material is None:
                continue
            sl.material = sl.material.copy()
            base = sl.material.name.split(".")[0]
            if base.startswith("Skin"):
                tint(sl.material, SKIN_TONES[L["tone"]])
            elif base == "Hair":
                tint(sl.material, HAIR_COLOURS[L["hair"]])
            elif base == "SuitAccent":
                tint(sl.material, DEPT)
            elif base == "ClothTint":
                tint(sl.material, L["cloth"])
    rig.location = loc
    rig.rotation_mode = "XYZ"
    rig.rotation_euler = (0, 0, rot_z)
    return rig, meshes


def pose(rig, clip, frame):
    NR.set_clip(rig, clip, frame)


def manifest():
    return json.load(open(MANIFEST, encoding="utf-8"))


def variants_outfits():
    M = manifest()
    return [(v, o) for v, d in M["variants"].items() for o in d["outfits"]]


# ------------------------------------------------------------------------------------------------------------------
def sheet_closeup():
    """The follow view distance: 1.5 m from the camera; front and 3/4, idle."""
    tmpdir()
    rows = []
    for v, o in variants_outfits():
        studio(640, 720)
        rig, _ = import_person(v, o)
        pose(rig, "idle", 0)
        h = 1.66 * (rig.dimensions.z if False else 1.0)
        top = max(p.head.z for p in rig.data.bones) * 1.0
        eye = 1.66 * manifest()["variants"][v]["scale"]
        row = []
        for k, (az, el) in enumerate(((0, 4), (38, 6), (-38, 6))):
            NR.clear_cameras()
            NR.camera((0.03, 0.0, eye - 0.16), az, el, 1.5, lens=50)
            row.append(("%s %s az %d, 1.5 m" % (v, o, az), NR.render(os.path.join(TMP, "cu_%s_%s_%d.png" % (v, o, k)))))
        rows.append(row)
    out = os.path.join(ART, "people_closeup.png")
    NR.compose(rows, out, title="people pilot: the follow-view distance (1.5 m), idle frame 0")
    return out


def sheet_outfits():
    tmpdir()
    rows = []
    for v, o in variants_outfits():
        studio(360, 640)
        rig, _ = import_person(v, o)
        pose(rig, "idle", 0)
        row = []
        for k, az in enumerate((-30, 60, 150, 240)):
            NR.clear_cameras()
            NR.camera((0.0, 0.0, 0.88), az, 6, 5.0, lens=85)
            row.append(("%s %s az %d" % (v, o, az), NR.render(os.path.join(TMP, "of_%s_%s_%d.png" % (v, o, k)))))
        rows.append(row)
    out = os.path.join(ART, "people_outfits.png")
    NR.compose(rows, out, title="people pilot outfits: four sides (idle)")
    return out


def sheet_faces():
    tmpdir()
    rows = []
    for v in manifest()["variants"]:
        studio(520, 520)
        rig, _ = import_person(v, "casual_a")
        s = manifest()["variants"][v]["scale"]
        row = []
        shots = (("idle", 0, 0, "front"), ("idle", 0, 35, "3/4"), ("idle", 0, 88, "profile"),
                 ("laugh", 36, 20, "laugh"), ("talk_gesture_a", 17, 25, "talking"))
        for k, (clip, fr, az, lab) in enumerate(shots):
            pose(rig, clip, fr)
            hb = rig.pose.bones["head"]
            hp = rig.matrix_world @ hb.head
            tgt = hp + (rig.matrix_world.to_3x3() @ (hb.matrix.to_3x3() @ Vector((0.0, 0.07, 0.04)))) * 1.0
            NR.clear_cameras()
            fwd = rig.matrix_world.to_3x3() @ Vector((1, 0, 0))
            NR.camera(tuple(hp + Vector((0.035, 0.0, 0.085)) * s), az, 3, 0.55, lens=85)
            row.append(("%s %s" % (v, lab), NR.render(os.path.join(TMP, "fc_%s_%d.png" % (v, k)))))
        rows.append(row)
    out = os.path.join(ART, "people_faces.png")
    NR.compose(rows, out, title="people pilot faces (casual_a): front, 3/4, profile, laughing, talking")
    return out


def stool_props():
    NR.add_box("Stool", (0.0, 0.0, 0.74), (0.36, 0.36, 0.04), (0.22, 0.22, 0.24))
    NR.add_box("StoolLeg", (0.0, 0.0, 0.37), (0.06, 0.06, 0.72), (0.4, 0.4, 0.42))
    NR.add_box("Footrest", (0.0, 0.0, 0.30), (0.42, 0.42, 0.02), (0.6, 0.6, 0.62))
    NR.add_box("Counter", (0.55, 0.0, 0.53), (0.44, 1.2, 1.06), (0.35, 0.22, 0.14))
    NR.add_box("CounterTop", (0.52, 0.0, 1.07), (0.52, 1.24, 0.04), (0.2, 0.2, 0.22))


def sheet_clips():
    tmpdir()
    M = manifest()
    rows = []
    new = ["talk_gesture_a", "laugh", "argue", "hug", "sit_bar_stool", "dance_a"]
    for clip in new:
        n = M["clips"][clip]["frames"]
        for v in M["variants"]:
            studio(300, 420)
            if clip == "sit_bar_stool":
                stool_props()
            rig, _ = import_person(v, "casual_a")
            other = None
            if clip == "hug":
                ov = [x for x in M["variants"] if x != v][0] if len(M["variants"]) > 1 else v
                d = 0.30 * (M["variants"][v]["scale"] + M["variants"][ov]["scale"]) / 2
                other, _ = import_person(ov, "casual_a", loc=(d, 0, 0), rot_z=radians(180))
            row = []
            for k in range(6):
                f = int(round(n * k / 5))
                pose(rig, clip, f)
                if other is not None:
                    pose(other, clip, f)
                NR.clear_cameras()
                if clip == "hug":
                    NR.camera((0.15, 0.0, 1.1), -70, 8, 3.6, lens=85)
                elif clip == "sit_bar_stool":
                    NR.camera((0.1, 0.0, 1.0), -55, 8, 3.8, lens=85)
                else:
                    NR.camera((0.05, 0.0, 1.0), -35, 6, 3.8, lens=85)
                row.append(("%s %s %d" % (v, clip, f), NR.render(os.path.join(TMP, "cl_%s_%s_%d.png" % (clip, v, k)))))
            rows.append(row)
    out = os.path.join(ART, "people_clips.png")
    NR.compose(rows, out, title="people pilot: the 6 new clips, 6 frames each (hug as a pair: m1 with f1)")
    return out


SHEETS = dict(closeup=sheet_closeup, outfits=sheet_outfits, faces=sheet_faces, clips=sheet_clips)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = list(SHEETS)
    if "--sheets" in argv:
        names = argv[argv.index("--sheets") + 1].split(",")
    for n in names:
        print("SHEET", SHEETS[n]())


if __name__ == "__main__":
    main()
