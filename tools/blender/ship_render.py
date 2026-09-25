"""
Frontier Habitat 3.1 - ART-B ship renders (art/ships/). Imports the EXPORTED ship_<kind>.glb.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ship_render.py -- --kinds trader[,shuttle,...] [--night]

Per kind:
  art/ships/<kind>_turnaround.png   8 views (every 45 deg), landed pose
  art/ships/<kind>_on_pad.png       landed on the current landing_pad.glb, ramp open, 3/4 game view
  art/ships/<kind>_flight.png       flight pose (legs folded, ramp and doors closed) 4 m above the pad
  art/ships/<kind>_night.png        (--night) on the pad at night: dark world, emissive parts only
Uses ext_render.py (read-only) for the scene, camera and contact sheet.
"""
import bpy
import os
import sys
from math import radians
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_render as R          # noqa: E402  (read-only use)
import ship_common as SC        # noqa: E402

GROUND = (0.52, 0.30, 0.17)


def pad_ship_place():
    """(deck height, ship yaw deg). Uses the pad's Anchor_Ship if it exists; otherwise deck 0.35 m and yaw 180 deg
    (nose to pad -X, ramp to pad +X where Anchor_Service is)."""
    import math
    g, _ = SC.C.read_glb(os.path.join(SC.MODEL_DIR, "landing_pad.glb"))
    for n in g["nodes"]:
        if n.get("name") == "Anchor_Ship":
            q = n.get("rotation", [0, 0, 0, 1])           # glTF (x, y, z, w); yaw about glTF +Y = Blender +Z
            yaw = math.degrees(2 * math.atan2(q[1], q[3]))
            return n.get("translation", [0, 0.35, 0])[1], yaw
    return 0.35, 180.0


def pose(objs, s):
    """s = 0 landed / open, 1 flight / folded / closed"""
    for ob in objs:
        d = ob.get("stow_deg")
        if d is not None and s:
            ob.matrix_world = ob.matrix_world @ Matrix.Rotation(radians(float(d) * s), 4, "X")


def load_ship(kind, z=0.0, s=0.0, yaw=0.0, lights=False):
    """lights=False hides the Lights node (day: dark glass, as in the game)"""
    objs = R.import_glb(os.path.join(SC.MODEL_DIR, "ship_%s.glb" % kind), hide=() if lights else ("Lights",))
    bpy.context.view_layer.update()
    M = Matrix.Translation((0, 0, z)) @ Matrix.Rotation(radians(yaw), 4, "Z")
    for ob in objs:
        if ob.parent is None:
            ob.matrix_world = M @ ob.matrix_world
    bpy.context.view_layer.update()
    if s == 0.0:                                   # landed: the engine glow is off (RENDER fades Plasma)
        for m in bpy.data.materials:
            if m.name.split(".")[0] == "Plasma" and m.node_tree:
                b = next((n for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
                if b:
                    b.inputs["Emission Strength"].default_value = 0.0
                    for l in list(b.inputs["Base Color"].links):
                        m.node_tree.links.remove(l)
                    b.inputs["Base Color"].default_value = (0.05, 0.06, 0.07, 1.0)
    pose(objs, s)
    bpy.context.view_layer.update()
    return objs


def fit(objs, az, el, size, margin=1.05, focal=R.FOCAL):
    lo, hi = R.world_bbox(objs)
    R.place_camera(lo, hi, azimuth=az, elevation=el, points=R.world_points(objs), margin=margin, aspect=size[0] / size[1],
                   focal=focal)


def turnaround(kind):
    tiles = []
    size = (520, 420)
    for k in range(8):
        az = -135.0 + 45.0 * k
        R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.62, 0.58, 0.55), ground=GROUND)
        objs = load_ship(kind)
        R.ao_materials()
        fit(objs, az, 18.0, size)
        out = os.path.join(SC.ART_DIR, "_tmp_%s_%d.png" % (kind, k))
        R.render_to(out)
        tiles.append(("az %d" % az, out))
    R.contact_sheet(tiles, os.path.join(SC.ART_DIR, "%s_turnaround.png" % kind), cols=4, tile=size)
    for _, o in tiles:
        os.remove(o)


def on_pad(kind, s=0.0, lift=0.0, name="on_pad", night=False, az=-42.0, el=32.0):
    size = (1400, 900)
    if night:
        R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.02, 0.03, 0.06), ground=(0.08, 0.06, 0.05),
                      sun_energy=0.15, sun_dir=(0.3, 0.5, 0.8))
    else:
        R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.62, 0.58, 0.55), ground=GROUND)
    pad = R.import_glb(os.path.join(SC.MODEL_DIR, "landing_pad.glb"))
    deck, yaw = pad_ship_place()
    objs = load_ship(kind, z=deck + lift, s=s, yaw=yaw, lights=night)
    R.ao_materials()
    bpy.context.view_layer.update()
    if night:                                       # round 12: a warm spot at every Flood_* empty
        for ob in list(objs):
            if ob.name.split(".")[0].startswith("Flood_"):
                ld = bpy.data.lights.new("FloodSpot", "SPOT")
                ld.energy = 1300.0
                ld.color = (1.0, 0.85, 0.63)
                ld.spot_size = radians(75.0)
                ld.spot_blend = 0.6
                ld.shadow_soft_size = 0.2
                lo = bpy.data.objects.new("FloodSpot", ld)
                aim = ob.matrix_world.to_3x3() @ Vector((1, 0, 0))
                q = (-aim).to_track_quat("Z", "Y")          # a spot shines along its local -Z
                lo.matrix_world = Matrix.Translation(ob.matrix_world.translation) @ q.to_matrix().to_4x4()
                bpy.context.scene.collection.objects.link(lo)
    if az == "ramp":                                # camera on the side where the ramp foot is (round 11 fix 5)
        import math
        a = next(o for o in objs if o.name.split(".")[0] == "Anchor_Ramp")
        p_ = a.matrix_world.translation
        az = math.degrees(math.atan2(p_.y, p_.x)) - 25.0
    fit(pad + objs, az, el, size, margin=1.02)
    R.render_to(os.path.join(SC.ART_DIR, "%s_%s.png" % (kind, name)))


FLEET = ["courier", "medical", "shuttle", "science", "trader", "liner"]


def fleet():
    """all six side by side (3/4 view) and from above, each on its own painted circle"""
    for name, az, el, size in (("fleet_lineup", -60.0, 24.0, (2000, 800)), ("fleet_top", -90.0, 89.0, (2000, 700))):
        R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.62, 0.58, 0.55), ground=GROUND)
        allo, x = [], 0.0
        for k, kind in enumerate(FLEET):
            rows = SC.json.load(open(SC.REPORT_JSON, encoding="utf-8"))
            r = rows["ship_" + kind]["radius"]
            x += r + (1.0 if k else 0.0)
            objs = load_ship(kind)
            M = Matrix.Translation((x, 0, 0))
            for ob in objs:
                if ob.parent is None:
                    ob.matrix_world = M @ ob.matrix_world
            R.add_ring(r, center=(x, 0))
            allo += objs
            x += r
        bpy.context.view_layer.update()
        R.ao_materials()
        fit(allo, az, el, size, margin=1.03)
        R.render_to(os.path.join(SC.ART_DIR, name + ".png"))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    kinds = argv[argv.index("--kinds") + 1].split(",") if "--kinds" in argv else ["trader"]
    if kinds == ["all"]:
        kinds = list(FLEET)
    os.makedirs(SC.ART_DIR, exist_ok=True)
    for kind in kinds:
        turnaround(kind)
        on_pad(kind, name="on_pad_rear", az=-42.0, el=32.0)      # critic round 9 fix 8: names swapped
        on_pad(kind, name="on_pad", az=150.0, el=26.0)
        on_pad(kind, s=1.0, lift=5.0, name="flight", az=-42.0, el=80.0)      # round 11 fix 7: near top-down, no parallax
        if "--night" in argv:
            on_pad(kind, name="night", night=True, az=150.0, el=26.0)
            on_pad(kind, name="night_ramp", night=True, az="ramp", el=24.0)
    if "--fleet" in argv:
        fleet()


if __name__ == "__main__":
    main()
