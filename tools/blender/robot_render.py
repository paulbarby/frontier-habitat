"""
Frontier Habitat 5.0 - ART-NPC: render sheets for the robot dancer (imports the EXPORTED robot_dancer.glb).

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/robot_render.py -- --sheets turnaround,clips

art/npc/robot_turnaround.png (front, 3/4, side, back, a face close-up) and art/npc/robot_clips.png (every clip,
8 frames, on ART-B's podium size with the pole at pole_local), club light: dark room, a warm key, magenta and cyan rims.
"""
import bpy
import os
import sys
import json
from math import radians

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
import npc_render as NR         # noqa: E402
import ext_render as R          # noqa: E402

ART = os.path.join(N.ROOT, "art", "npc")
TMP = os.path.join(ART, "_tmp")
MANIFEST = os.path.join(N.MODEL_DIR, "robot_manifest.json")


def club(w, h):
    sc = NR.setup(w, h, ground=(0.05, 0.05, 0.06), samples=48)
    for o in list(bpy.data.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o)
    NR._light("AREA", "Key", 240.0, loc=(2.4, -1.6, 3.0), size=2.0, color=(1.0, 0.93, 0.86))
    NR._light("AREA", "RimM", 260.0, loc=(-2.2, 1.8, 2.4), size=1.2, color=(1.0, 0.25, 0.75))
    NR._light("AREA", "RimC", 220.0, loc=(-2.0, -2.2, 2.2), size=1.2, color=(0.2, 0.85, 1.0))
    NR._light("AREA", "Fill", 60.0, loc=(2.0, 2.4, 1.2), size=3.0, color=(0.7, 0.75, 1.0))
    for o in bpy.data.objects:
        if o.type == "LIGHT":
            o.rotation_euler = (o.location * -1).to_track_quat("-Z", "Y").to_euler()
    # a darker world so the chrome reflects a club, not a sky
    wd = bpy.context.scene.world
    if wd and wd.use_nodes:
        bg = next((n for n in wd.node_tree.nodes if n.bl_idname == "ShaderNodeBackground"), None)
        if bg:
            bg.inputs["Color"].default_value = (0.03, 0.025, 0.05, 1.0)
            bg.inputs["Strength"].default_value = 1.0
    return sc


def mat(name, rgb, metal=0.0, rough=0.5, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = 2.0
    return m


def podium(pole=True):
    """ART-B's podium (radius 0.8, top at the anchor z) and pole (radius 0.045), in anchor space."""
    M = json.load(open(MANIFEST, encoding="utf-8"))
    px, py = M["anchor"]["pole_local"]
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.80, depth=0.60, location=(px, py, -0.30))
    top = bpy.context.object
    top.data.materials.append(mat("Podium", (0.03, 0.025, 0.05), rough=0.35))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.81, minor_radius=0.012, location=(px, py, -0.05))
    bpy.context.object.data.materials.append(mat("Neon", (1.0, 0.2, 0.7), emit=(1.0, 0.2, 0.7)))
    if pole:
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.045, depth=3.2, location=(px, py, 1.6))
        bpy.context.object.data.materials.append(mat("PoleChrome", (0.9, 0.9, 0.92), metal=1.0, rough=0.12))


def import_robot(loc=(0, 0, 0)):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(N.MODEL_DIR, "robot_dancer.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    R.ao_materials()
    rig.location = loc
    rig.rotation_mode = "XYZ"
    return rig


def tmpdir():
    os.makedirs(TMP, exist_ok=True)
    g = os.path.join(TMP, ".gdignore")
    if not os.path.exists(g):
        open(g, "w").close()


def sheet_turnaround():
    tmpdir()
    row, row2 = [], []
    for k, az in enumerate((0, 35, 90, 180)):
        club(360, 620)
        podium(pole=False)
        rig = import_robot()
        NR.set_clip(rig, "robot_idle", 0)
        NR.clear_cameras()
        NR.camera((0.0, 0.0, 0.92), az, 6, 4.4, lens=70)
        row.append(("az %d" % az, NR.render(os.path.join(TMP, "rb_turn_%d.png" % k))))
    for k, (az, el, tgt, dist, lab) in enumerate(((20, 4, (0.03, 0, 1.66), 0.9, "face 3/4"),
                                                  (-50, 12, (0.03, -0.27, 0.86), 0.8, "hand"),
                                                  (30, 10, (0.02, 0, 1.30), 1.5, "torso at 1.5 m"),
                                                  (60, 8, (0.05, 0.1, 0.35), 1.2, "leg and foot"))):
        club(360, 620)
        rig = import_robot()
        NR.set_clip(rig, "robot_idle", 0)
        NR.clear_cameras()
        NR.camera(tgt, az, el, dist, lens=70)
        row2.append((lab, NR.render(os.path.join(TMP, "rb_detail_%d.png" % k))))
    out = os.path.join(ART, "robot_turnaround.png")
    NR.compose([row, row2], out, title="robot dancer: turnaround and details (club light)")
    return out


def sheet_clips():
    tmpdir()
    M = json.load(open(MANIFEST, encoding="utf-8"))
    rows = []
    for clip, m in M["clips"].items():
        n = m["frames"]
        club(300, 420)
        podium(pole=(clip == "robot_pole"))
        rig = import_robot()
        row = []
        frames = 8 if n <= 120 else 12
        for k in range(frames):
            f = int(round(n * k / frames))
            NR.set_clip(rig, clip, f)
            NR.clear_cameras()
            NR.camera((-0.12 if clip == "robot_pole" else 0.0, 0.0, 0.95), 25, 8, 4.6, lens=70)
            row.append(("%s %d" % (clip, f), NR.render(os.path.join(TMP, "rb_%s_%d.png" % (clip, k)))))
        rows.append(row)
    out = os.path.join(ART, "robot_clips.png")
    NR.compose(rows, out, title="robot dancer: every clip (pole clip with ART-B's podium and pole)")
    return out


SHEETS = dict(turnaround=sheet_turnaround, clips=sheet_clips)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = list(SHEETS)
    if "--sheets" in argv:
        names = argv[argv.index("--sheets") + 1].split(",")
    for nm in names:
        print("SHEET", SHEETS[nm]())


if __name__ == "__main__":
    main()
