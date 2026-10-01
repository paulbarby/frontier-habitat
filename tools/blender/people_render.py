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
LOOK = {"m1": dict(tone=3, hair=1, cloth=(0.60, 0.08, 0.05)), "f1": dict(tone=2, hair=2, cloth=(0.05, 0.20, 0.42)),
        "m2": dict(tone=0, hair=0, cloth=(0.10, 0.30, 0.12)), "m3": dict(tone=2, hair=0, cloth=(0.30, 0.30, 0.34)),
        "f2": dict(tone=1, hair=0, cloth=(0.55, 0.30, 0.05)), "f3": dict(tone=3, hair=0, cloth=(0.40, 0.08, 0.25)),
        "c1": dict(tone=4, hair=3, cloth=(0.05, 0.25, 0.50)), "c2": dict(tone=1, hair=0, cloth=(0.60, 0.20, 0.35))}
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


DEPT_STRIPE = {"uniform_engineering": (1.0, 0.35, 0.01), "uniform_science": (0.10, 0.35, 1.0),
               "uniform_food": (0.15, 0.65, 0.15), "uniform_medical": (0.85, 0.08, 0.08),
               "uniform_security": (0.80, 0.06, 0.06), "uniform_command": (0.95, 0.75, 0.20)}


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
    entry = manifest()["variants"][variant]["outfits"].get(outfit, "Outfit_" + outfit)
    keep_mesh = entry if isinstance(entry, str) else entry["mesh"]
    keep_add = [] if isinstance(entry, str) else entry.get("addons", [])
    base_rgb = None if isinstance(entry, str) else entry.get("base_rgb")
    meshes = []
    for o in new:
        if o.type != "MESH":
            continue
        nm = o.name.split(".")[0]
        if nm.startswith("Outfit_") and nm != keep_mesh:
            bpy.data.objects.remove(o)
            continue
        if nm.startswith("Addon_") and nm not in keep_add:
            bpy.data.objects.remove(o)
            continue
        if not (nm.startswith(("Outfit_", "Head_", "Hair_", "Addon_"))):
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
            elif base.startswith("Hair"):                  # Hair, Hair_brows, Hair_lashes
                tint(sl.material, HAIR_COLOURS[L["hair"]])
            elif base == "SuitAccent":
                acc = None if isinstance(entry, str) else entry.get("accent_rgb")
                tint(sl.material, tuple(acc) if acc else DEPT_STRIPE.get(outfit, DEPT))
            elif base.startswith("UniformBase") and base_rgb:
                tint(sl.material, tuple(base_rgb))
            elif base.startswith("ClothTint"):
                tint(sl.material, L["cloth"])
    rig.location = loc
    rig.rotation_mode = "XYZ"
    rig.rotation_euler = (0, 0, rot_z)
    return rig, meshes


def pose(rig, clip, frame):
    NR.set_clip(rig, clip, frame)


def manifest():
    return json.load(open(MANIFEST, encoding="utf-8"))


MAIN_OUTFITS = ("uniform_engineering", "casual_a", "casual_b", "casual_c", "swimwear", "school", "prison")


def variants_outfits():
    M = manifest()
    return [(v, o) for v, d in M["variants"].items() for o in d["outfits"] if o in MAIN_OUTFITS]


def sheet_uniforms():
    """Every department look of the one uniform cut (tints and add-ons as the game shows them), per variant."""
    tmpdir()
    rows = []
    for v, d in manifest()["variants"].items():
        row = []
        if not any(o.startswith("uniform_") for o in d["outfits"]):
            continue
        for k, o in enumerate([o for o in d["outfits"] if o.startswith("uniform_")]):
            studio(300, 560)
            rig, _ = import_person(v, o)
            pose(rig, "idle", 0)
            NR.clear_cameras()
            NR.camera((0.0, 0.0, 0.90), 25, 6, 4.6, lens=85)
            row.append(("%s %s" % (v, o[8:]), NR.render(os.path.join(TMP, "un_%s_%d.png" % (v, k)))))
        rows.append(row)
    out = os.path.join(ART, "people_uniforms.png")
    NR.compose(rows, out, title="uniforms: one cut, six departments (base colour, stripe, add-ons)")
    return out


def sheet_tones():
    """The skin tint range (the game's palette) on each face, with the hair colours."""
    tmpdir()
    rows = []
    for v in manifest()["variants"]:
        row = []
        for k, tone in enumerate(range(len(SKIN_TONES))):
            studio(260, 300)
            rig, _ = import_person(v, "casual_a", look=dict(tone=tone, hair=k % len(HAIR_COLOURS)))
            pose(rig, "idle", 0)
            NR.clear_cameras()
            eyes = rig.matrix_world @ rig.pose.bones["lids"].head
            NR.camera(tuple(eyes + Vector((-0.04, 0.0, -0.05))), 12, 3, 0.9, lens=85)
            row.append(("%s tone %d hair %d" % (v, tone, k % len(HAIR_COLOURS)),
                        NR.render(os.path.join(TMP, "tn_%s_%d.png" % (v, k)))))
        rows.append(row)
    out = os.path.join(ART, "people_tones.png")
    NR.compose(rows, out, title="skin tint range and hair colours (the game tints Skin and Hair*)")
    return out


# ------------------------------------------------------------------------------------------------------------------
def sheet_closeup():
    """The follow view distance: 1.5 m from the camera (115 mm lens); per variant the work outfit (uniform or
    school) and casual_a, front and 3/4, idle frame 0."""
    tmpdir()
    rows = []
    M = manifest()
    for v, d in M["variants"].items():
        row = []
        work = "uniform_engineering" if "uniform_engineering" in d["outfits"] else "school"
        for o in (work, "casual_a"):
            for k, (az, el) in enumerate(((0, 4), (38, 6))):
                studio(420, 470)
                rig, _ = import_person(v, o)
                pose(rig, "idle", 0)
                eye = (rig.matrix_world @ rig.pose.bones["lids"].head).z
                NR.clear_cameras()
                NR.camera((0.03, 0.0, eye - 0.10 * d["scale"]), az, el, 1.5, lens=115)
                row.append(("%s %s az %d" % (v, o, az), NR.render(os.path.join(TMP, "cu_%s_%s_%d.png" % (v, o, k)))))
        rows.append(row)
    out = os.path.join(ART, "people_closeup.png")
    NR.compose(rows, out, title="people: 1.5 m from the camera (115 mm lens), work outfit and casual_a, idle frame 0")
    return out


def sheet_outfits(variants=("m1", "f1")):
    """Every outfit of two variants, front 3/4 and back 3/4 (idle)."""
    tmpdir()
    M = manifest()
    vs = [v for v in variants if v in M["variants"]]
    outs = [o for o in MAIN_OUTFITS if any(o in M["variants"][v]["outfits"] for v in vs)]
    rows = []
    for o in outs:
        row = []
        for v in vs:
            if o not in M["variants"][v]["outfits"]:
                continue
            for k, az in enumerate((-30, 150)):
                studio(300, 560)
                rig, _ = import_person(v, o)
                pose(rig, "idle", 0)
                NR.clear_cameras()
                NR.camera((0.0, 0.0, 0.90 * M["variants"][v]["scale"]), az, 6, 4.6, lens=85)
                row.append(("%s %s az %d" % (v, o, az), NR.render(os.path.join(TMP, "of_%s_%s_%d.png" % (v, o, k)))))
        rows.append(row)
    out = os.path.join(ART, "people_outfits.png")
    NR.compose(rows, out, title="outfits: every outfit on %s, front and back (idle)" % " and ".join(vs))
    return out


def sheet_wardrobe():
    """Every variant (rows) in every outfit it has (columns), front 3/4."""
    tmpdir()
    M = manifest()
    rows = []
    for v, d in M["variants"].items():
        row = []
        for o in [o for o in MAIN_OUTFITS if o in d["outfits"]]:
            studio(240, 470)
            rig, _ = import_person(v, o)
            pose(rig, "idle", 0)
            NR.clear_cameras()
            NR.camera((0.0, 0.0, 0.90 * d["scale"]), -25, 6, 4.4 * max(0.8, d["scale"]), lens=85)
            row.append(("%s %s" % (v, o), NR.render(os.path.join(TMP, "wd_%s_%s.png" % (v, o)))))
        rows.append(row)
    out = os.path.join(ART, "people_wardrobe.png")
    NR.compose(rows, out, title="wardrobe: every variant in every outfit (front 3/4, idle)")
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
            eyes = rig.matrix_world @ rig.pose.bones["lids"].head          # the eye line (lids bone)
            NR.camera(tuple(eyes + Vector((-0.04, 0.0, -0.04))), az, 3, 0.75, lens=85)
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


PAIRS = os.path.join(N.MODEL_DIR, "npc_pairs.json")
CLIP_GROUPS = {
    "pilot": ["talk_gesture_a", "laugh", "argue", "hug", "sit_bar_stool", "dance_a"],
    "hug": ["hug"],
    "v3": ["idle", "idle_look", "walk", "run", "carry_walk", "carry_idle", "work_console", "work_bench", "talk", "kneel_enter",
           "repair_kneel", "kneel_exit", "sit_enter", "sit_idle", "sit_eat", "sit_type", "sit_exit", "injured_walk",
           "collapse", "dead", "cheer"],
    "sleep": ["lie_enter", "sleep", "sleep_turn", "lie_exit", "sleep_cell"],
    "social": ["talk_idle", "talk_gesture_b", "listen_nod", "wave", "shout", "sulk", "flirt_lean", "protest_fist",
               "fight_idle"],
    "paired": ["handshake", "kiss_brief", "hold_hands_walk", "slap", "punch", "escort_walk"],
    "venues": ["sit_bench", "drink_bar", "dance_b", "dance_c", "swim", "lounge_pool", "jog", "play_arcade",
               "shop_browse", "drive_sit"],
    "school": ["sit_class", "teach", "fall_down", "get_up", "hit_react"],
    "children": ["child_play", "child_run"],
}


def pair_of(clip):
    """The npc_pairs.json entry whose clip_a or clip_b is this clip: (entry, this clip is partner B)."""
    if not os.path.exists(PAIRS):
        return None, False
    for k, e in json.load(open(PAIRS, encoding="utf-8"))["pairs"].items():
        if e["clip_a"] == clip:
            return e, False
        if e["clip_b"] == clip:
            return e, True
    return None, False


def place_partner(e, sa, sb):
    """Partner B's location and turn from a pair entry (A at the origin facing +X)."""
    s = (sa + sb) / 2
    fac = radians(e.get("facing_deg", 180.0))
    return (e["distance_m"] * s, e.get("side_offset_m", 0.0) * s, 0.0), fac


def sheet_clips(group="pilot", variants=None, outfit="casual_a", frames=6):
    tmpdir()
    M = manifest()
    rows = []
    vs = variants or [v for v in ("m1", "f1") if v in M["variants"]] or list(M["variants"])
    for clip in CLIP_GROUPS[group]:
        if clip not in M["clips"]:
            continue
        n = M["clips"][clip]["frames"]
        e, _ = pair_of(clip)
        for v in (vs[:1] if e else vs):
            studio(300, 420)
            if clip in ("sit_bar_stool", "drink_bar"):
                stool_props()
            if clip in FURNITURE_PROPS:
                FURNITURE_PROPS[clip]()
            rig, _ = import_person(v, outfit)
            other = None
            if e:
                ov = vs[1] if len(vs) > 1 else v
                loc, fac = place_partner(e, M["variants"][v]["scale"], M["variants"][ov]["scale"])
                other, _ = import_person(ov, outfit, loc=loc, rot_z=fac)
            row = []
            for k in range(frames):
                f = int(round(n * k / (frames - 1)))
                pose(rig, e["clip_a"] if e else clip, f)
                if other is not None:
                    tb = max(0, f - int(round(e.get("sync_s", 0.0) * N.FPS)))
                    pose(other, e["clip_b"], tb)
                NR.clear_cameras()
                if e:
                    NR.camera((0.25, 0.0, 1.05), -80, 8, 3.8, lens=85)
                elif clip in ("sit_bar_stool", "drink_bar"):
                    NR.camera((0.1, 0.0, 1.0), -55, 8, 3.8, lens=85)
                elif clip in LOW_CLIPS:
                    NR.camera((0.0, 0.0, 0.55), -45, 18, 4.2, lens=85)
                else:
                    NR.camera((0.05, 0.0, 1.0), -35, 6, 3.8, lens=85)
                lab = "%s %s %d" % (v + ("+" + ov if e else ""), clip if not e else e["clip_a"] + ("/" + e["clip_b"] if e["clip_b"] != e["clip_a"] else ""), f)
                row.append((lab, NR.render(os.path.join(TMP, "cl_%s_%s_%d.png" % (clip, v, k)))))
            rows.append(row)
    out = os.path.join(ART, "people_clips%s.png" % ("" if group == "pilot" else "_" + group))
    NR.compose(rows, out, title="people clips (%s): %d frames each; pairs placed from npc_pairs.json" % (group, frames))
    return out


def _bed(z=0.55):
    NR.add_box("Bed", (-0.55, 0.05, z / 2), (0.90, 2.0, z), (0.42, 0.28, 0.26))


def _chair(z=0.46, back=True):
    NR.add_box("Seat", (-0.30, 0.0, z - 0.02), (0.44, 0.46, 0.04), (0.3, 0.3, 0.32))
    NR.add_box("SeatLeg", (-0.30, 0.0, (z - 0.04) / 2), (0.06, 0.06, z - 0.04), (0.45, 0.45, 0.47))
    if back:
        NR.add_box("Back", (-0.53, 0.0, z + 0.25), (0.04, 0.44, 0.50), (0.3, 0.3, 0.32))


def _desk(z, ahead):
    NR.add_box("Desk", (ahead + 0.25, 0.0, z - 0.02), (0.55, 1.0, 0.04), (0.45, 0.33, 0.22))


FURNITURE_PROPS = {
    "lie_enter": _bed, "sleep": _bed, "lie_exit": _bed, "sleep_turn": _bed, "lie_enter_r": _bed, "sleep_r": _bed,
    "lie_exit_r": _bed, "sleep_cell": lambda: _bed(0.45),
    "sit_enter": _chair, "sit_idle": _chair, "sit_exit": _chair, "sit_eat": lambda: (_chair(), _desk(0.74, 0.20)),
    "sit_type": lambda: (_chair(), _desk(0.74, 0.25)), "sit_class": lambda: (_chair(), _desk(0.72, 0.25)),
    "sit_bench": lambda: _chair(0.45, False), "drive_sit": lambda: _chair(0.46, False),
    "work_console": lambda: _desk(1.0, 0.40), "work_bench": lambda: _desk(0.90, 0.30),
    "play_arcade": lambda: _desk(0.98, 0.38), "lounge_pool": lambda: NR.add_box("Lounger", (0.15, 0.0, 0.17), (1.9, 0.6, 0.34), (0.8, 0.8, 0.82)),
}
LOW_CLIPS = {"lie_enter", "sleep", "lie_exit", "sleep_turn", "sleep_cell", "dead", "collapse", "fall_down", "get_up",
             "swim", "lounge_pool", "child_play", "repair_kneel", "kneel_enter", "kneel_exit"}


SHEETS = dict(wardrobe=sheet_wardrobe, closeup=sheet_closeup, outfits=sheet_outfits, faces=sheet_faces, clips=sheet_clips,
              uniforms=sheet_uniforms, tones=sheet_tones)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = list(SHEETS)
    if "--sheets" in argv:
        names = argv[argv.index("--sheets") + 1].split(",")
    for n in names:
        if n.startswith("clips:"):
            print("SHEET", sheet_clips(n[6:]))
            continue
        print("SHEET", SHEETS[n]())


if __name__ == "__main__":
    main()
