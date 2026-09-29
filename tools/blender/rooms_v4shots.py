"""4.0 room identity shots (docs/V4_DESIGN.md section 3, critic subject room_identity): the pilot rooms together
from the game's overview camera (presentation/camera_rig.gd: vertical FOV 50 deg, pitch 52 deg) at 110 m and 250 m,
roofs on, no labels.

Run (pilot files): FH_V4PILOT=1 blender --background --factory-startup --python tools/blender/rooms_v4shots.py --
       [--files habitat_m,kitchen_m,workshop_m,research_lab_m] [--tag v4] [--night]
Output: art/interiors/v4_identity_<tag>_110m.png, _250m.png (and _night_ variants with --night)."""
import bpy
import os
import sys
from math import cos, sin, radians
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rooms_kit as K           # noqa: E402
import rooms_render as RR       # noqa: E402
import interior_render as IR    # noqa: E402

OUT = os.path.join(K.ROOT, "art", "interiors")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    files = (argv[argv.index("--files") + 1].split(",") if "--files" in argv
             else ["habitat_m", "kitchen_m", "workshop_m", "research_lab_m"])
    tag = argv[argv.index("--tag") + 1] if "--tag" in argv else "v4"
    night = "--night" in argv
    b = K.load_buildings()
    radii = []
    for f in files:
        tid, key = f.rsplit("_", 1)
        tid = IR.base_tid(tid)          # 5.0: variant files (residence_tube_executive_l)
        s_ = K.SIZE_KEYS.index(key)
        radii.append(K.v4_radius(tid, s_, float(b[tid]["sizes"]["radius"][s_])))
    # a 2 x N/2 cluster with 6 m between walls (a corridor's length)
    cols = 2
    pos = []
    step = max(radii) * 2 + 6.0
    for i in range(len(files)):
        pos.append(((i % cols) * step, (i // cols) * step))
    cx = sum(p[0] for p in pos) / len(pos)
    cy = sum(p[1] for p in pos) / len(pos)
    for dist in (110.0, 250.0):
        IR.setup(1600, 900, night=night, samples=48)
        for f, (x, y) in zip(files, pos):
            objs = IR.import_at(f, Matrix.Translation((x - cx, y - cy, 0.0)), hide=K.LEVELS)
            for o in objs:
                if o.name.split(".")[0].endswith(("_L2", "_L3", "_L4", "_L5")):
                    o.hide_render = True
        RR.ensure_ao()
        cam_d = bpy.data.cameras.new("v4cam")
        cam_d.sensor_fit = "VERTICAL"
        cam_d.angle_y = radians(50.0)
        cam = bpy.data.objects.new("v4cam", cam_d)
        bpy.context.scene.collection.objects.link(cam)
        pitch, yaw = radians(52.0), radians(-124.8)      # the game's default view (yaw -35 in Godot)
        eye = Vector((cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))) * dist
        cam.location = eye
        cam.rotation_euler = (-eye).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.camera = cam
        out = os.path.join(OUT, "v4_identity_%s%s_%dm.png" % (tag, "_night" if night else "", int(dist)))
        RR.render_to(out)
        print("  wrote", out)


main()
