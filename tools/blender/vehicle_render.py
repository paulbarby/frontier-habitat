"""
Frontier Habitat 4.0 - ART-B vehicle renders (art/vehicles/). Imports the EXPORTED vehicle_<id>.glb.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/vehicle_render.py -- --ids rover_small

Per id:
  <id>_turnaround.png   8 views (every 45 deg), driving pose (tailgate closed, cargo on)
  <id>_scale.png        with the colonist (astronaut_suit.glb): one seated in Seat_2 (sit_idle), one at
                        Anchor_Board_1, one at the open tailgate
  <id>_poses.png        the animation nodes at work: steering, suspension on rough ground, tailgate open + empty
  <id>_night.png        at night: Lights on, spot lights at the Light_* empties, tail lights and beacon
Uses ext_render.py (read-only) for the scene, camera and contact sheet.
"""
import bpy
import os
import sys
import math
from math import radians
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_render as R          # noqa: E402  (read-only use)
import vehicle_common as V      # noqa: E402

GROUND = (0.52, 0.30, 0.17)
SUIT = os.path.join(V.MODEL_DIR, "astronaut_suit.glb")


def base(o):
    return o.name.split(".")[0]


FILES = {"satellite": "satellite.glb", "launch_pad": "launch_pad.glb"}
SPACE_IDS = ("satellite",)


def load_vehicle(vid, M=None, lights=False, cargo=True, gate=1.0, steer=0.0, travel=None, spin=0.0, fly=0.0, lift=0.0,
                 arms=0.0, rocket=0.0, wings=0.0, dish=0.0):
    hide = []
    if not lights:
        hide.append("Lights")
    if not cargo:
        hide.append("Cargo")
    objs = R.import_glb(os.path.join(V.MODEL_DIR, FILES.get(vid, "vehicle_%s.glb" % vid)), hide=tuple(hide))
    bpy.context.view_layer.update()
    by = {base(o): o for o in objs}
    travel = travel or {}
    for o in objs:
        n = base(o)
        if (n.startswith("Door_") or n == "Ramp") and o.get("stow_deg") is not None and gate:
            o.matrix_basis = o.matrix_basis @ Matrix.Rotation(radians(float(o["stow_deg"]) * gate), 4, "X")
        if n.startswith("Susp_"):
            w = n[5:]
            o.matrix_basis = Matrix.Translation(o.matrix_basis.to_3x3() @ Vector((0, 0, travel.get(w, 0.0)))) @ o.matrix_basis
        if n.startswith("Steer_") and steer:
            o.matrix_basis = o.matrix_basis @ Matrix.Rotation(radians(steer * float(o.get("steer_sign", 1))), 4, "Z")
        if n.startswith("Wheel_") and spin:
            o.matrix_basis = o.matrix_basis @ Matrix.Rotation(spin, 4, "X")
        if n.startswith("Arm_") and arms:
            o.matrix_basis = o.matrix_basis @ Matrix.Rotation(radians(float(o["stow_deg"]) * arms), 4, "X")
        if n == "Rocket" and rocket:
            o.matrix_basis = o.matrix_basis @ Matrix.Translation((0, 0, rocket))
        if n.startswith("Wing_") and wings:
            o.matrix_basis = o.matrix_basis @ Matrix.Rotation(radians(wings), 4, "X")
        if n == "Dish" and dish:
            o.matrix_basis = o.matrix_basis @ Matrix.Rotation(radians(dish), 4, "X")
        if n.startswith("Leg_") and fly:
            o.matrix_basis = o.matrix_basis @ Matrix.Rotation(radians(float(o["stow_deg"]) * fly), 4, "X")
    if lift:
        M = (Matrix.Identity(4) if M is None else M) @ Matrix.Translation((0, 0, lift))
    if not fly:                                        # landed / parked: the engine glow is off (RENDER fades Plasma)
        for m in bpy.data.materials:
            if m.name.split(".")[0] == "Plasma" and m.node_tree:
                bs = next((q for q in m.node_tree.nodes if q.bl_idname == "ShaderNodeBsdfPrincipled"), None)
                if bs:
                    bs.inputs["Emission Strength"].default_value = 0.0
                    for l in list(bs.inputs["Base Color"].links):
                        m.node_tree.links.remove(l)
                    bs.inputs["Base Color"].default_value = (0.05, 0.06, 0.07, 1.0)
    bpy.context.view_layer.update()                  # matrix_world must include the pose before M is applied
    if M is not None:
        for o in objs:
            if o.parent is None:
                o.matrix_world = M @ o.matrix_world
    bpy.context.view_layer.update()
    return objs, by


def colonist(M, clip="idle", frame=0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SUIT)
    objs = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in objs if o.type == "ARMATURE")
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    act = bpy.data.actions.get(clip) or next((a for a in bpy.data.actions if a.name.startswith(clip)), None)
    if act:
        ad.action = act
        if act.slots and ad.action_slot is None:
            ad.action_slot = act.slots[0]
    for o in objs:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
    bpy.context.scene.frame_set(int(frame))
    bpy.context.view_layer.update()
    return objs


def fit(objs, az, el, size, margin=1.05):
    lo, hi = R.world_bbox(objs)
    R.place_camera(lo, hi, azimuth=az, elevation=el, points=R.world_points(objs), margin=margin,
                   aspect=size[0] / size[1], focal=R.FOCAL)


SPACE = {"satellite"}  # ids rendered in space (no ground)


def day(size, vid=None):
    if vid in SPACE:
        R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.05, 0.07, 0.12), ground=None)
        return
    R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.62, 0.58, 0.55), ground=GROUND)


def turnaround(vid):
    tiles = []
    size = (560, 420)
    for k in range(8):
        az = -135.0 + 45.0 * k
        day(size, vid)
        objs, _ = load_vehicle(vid)
        R.ao_materials()
        fit(objs, az, 20.0, size)
        out = os.path.join(V.ART_DIR, "_tmp_%s_%d.png" % (vid, k))
        R.render_to(out)
        tiles.append(("az %d" % az, out))
    R.contact_sheet(tiles, os.path.join(V.ART_DIR, "%s_turnaround.png" % vid), cols=4, tile=size)
    for _, o in tiles:
        os.remove(o)


SCALE_JOBS = {
    "rover_small": (
        ("front 3/4: drive_sit on Seat_1, ride_sit on Seat_2, colonist at Anchor_Ground_1", 30.0, 22.0,
         [("Seat_1", "drive_sit", 0), ("Seat_2", "ride_sit", 0), ("Anchor_Ground_1", "idle", 0)], 1.0),
        ("rear 3/4 right: board_r (frame 24) at Anchor_Board_2, tailgate open, colonist at Anchor_Cargo",
         -130.0, 24.0, [("Seat_1", "drive_sit", 24), ("Anchor_Board_2", "board_r", 24), ("Anchor_Cargo", "idle", 24)],
         0.0)),
    "hopper": (
        ("front 3/4: colonist beside the hopper", 35.0, 20.0, [("Anchor_Side", "idle", 0)], 1.0),
        ("rear 3/4: hatch open, colonist at the ladder foot (Anchor_Board)", -140.0, 22.0,
         [("Anchor_Board", "idle", 0)], 0.0)),
    "launch_pad": (
        ("colonist at Anchor_Service, one on the lower arm platform", -50.0, 22.0,
         [("Anchor_Service", "idle", 0), ("Anchor_ArmDeck", "idle", 0)], 1.0),),
    "rover_medium": (
        ("front 3/4: colonist beside the front wheels", 35.0, 20.0, [("Anchor_Side", "idle", 0)], 1.0),
        ("rear 3/4: hatch open, ramp down, colonist at Anchor_Ramp and one on the ramp", -140.0, 22.0,
         [("Anchor_Ramp", "idle", 0), ("Anchor_RampMid", "idle", 0)], 0.0)),
}


def extra_anchor(by, name):
    """a named empty, or a render-only point derived from one"""
    if name in by:
        return by[name].matrix_world.copy()
    if name == "Anchor_Side" and "Seat_1" in by:          # 1 m outside the left wheels, beside the cab, facing -Y
        return Matrix.Translation((1.5, 2.3, 0.0)) @ Matrix.Rotation(radians(-90), 4, "Z")
    if name == "Anchor_ArmDeck" and "Arm_Lower" in by:     # on the tower platform at the lower arm, facing the rocket
        z = by["Arm_Lower"].matrix_world.translation.z - 0.02
        return Matrix.Translation((0.3, 3.2, z)) @ Matrix.Rotation(radians(-90), 4, "Z")
    if name == "Anchor_RampMid" and "Anchor_Ramp" in by:  # half way up the ramp, facing the hatch
        a = by["Anchor_Ramp"].matrix_world.translation
        return Matrix.Translation((a.x + 0.62, 0.0, 0.64)) @ Matrix.Rotation(radians(0), 4, "Z")
    return None


def scale(vid):
    """crew clips of ART-NPC on the seat anchors: drive_sit, ride_sit, board_r (mid), a colonist at the tailgate"""
    size = (1400, 900)
    tiles = []
    jobs = SCALE_JOBS[vid]
    for name, az, el, crew, gate in jobs:
        day(size)
        objs, by = load_vehicle(vid, gate=gate)
        allo = list(objs)
        for anchor, clip, frame in crew:
            M = extra_anchor(by, anchor)
            if M is not None:
                allo += colonist(M, clip, frame)
        R.ao_materials()
        fit(allo, az, el, size, margin=1.04)
        out = os.path.join(V.ART_DIR, "_tmp_scale_%d.png" % len(tiles))
        R.render_to(out)
        tiles.append((name, out))
    R.contact_sheet(tiles, os.path.join(V.ART_DIR, "%s_scale.png" % vid), cols=2, tile=(1000, 643))
    for _, o in tiles:
        os.remove(o)


POSE_JOBS = {
    "rover_small": (("steer 25 deg (front left, rear right)", dict(steer=25.0), 60.0, 55.0),
                    ("suspension, left side: FL +0.12 m, ML 0, RL -0.10 m",
                     dict(travel={"FL": 0.12, "MR": -0.15, "RL": -0.10, "FR": 0.05}), 90.0, 6.0),
                    ("tailgate open, bed empty", dict(gate=0.0, cargo=False), -140.0, 38.0)),
    "rover_medium": (("steer 20 deg (axle 1 left, axle 4 right)", dict(steer=20.0), 60.0, 55.0),
                     ("suspension, left side: 1L +0.156 m, 2L 0, 3L -0.10 m, 4L -0.195 m",
                      dict(travel={"1L": 0.156, "3L": -0.10, "4L": -0.195}), 90.0, 6.0),
                     ("hatch open, ramp down, rack empty", dict(gate=0.0, cargo=False), -140.0, 30.0)),
    "launch_pad": (("arms connected, rocket on the mount", dict(), -60.0, 24.0),
                   ("arms clear (stow), rocket lifting 6 m", dict(arms=1.0, rocket=6.0), -60.0, 18.0),
                   ("from above", dict(), -90.0, 86.0)),
    "satellite": (("orbit icon: from above (sun face)", dict(), -90.0, 89.0),
                  ("3/4 from below: scanner and dish (nadir)", dict(), -40.0, -35.0),
                  ("wings tracking 40 deg, dish 20 deg", dict(wings=40.0, dish=20.0), -40.0, 25.0)),
    "hopper": (("landed, hatch open", dict(gate=0.0), -140.0, 24.0),
               ("flight: legs folded, 3 m up, hover glow", dict(fly=1.0, lift=3.0), -40.0, 18.0),
               ("from above", dict(), -90.0, 86.0)),
}


def poses(vid):
    size = (900, 640)
    tiles = []
    jobs = POSE_JOBS[vid]
    for name, kw, az, el in jobs:
        day(size, vid)
        objs, _ = load_vehicle(vid, **kw)
        R.ao_materials()
        fit(objs, az, el, size)
        out = os.path.join(V.ART_DIR, "_tmp_pose_%d.png" % len(tiles))
        R.render_to(out)
        tiles.append((name, out))
    R.contact_sheet(tiles, os.path.join(V.ART_DIR, "%s_poses.png" % vid), cols=3, tile=size)
    for _, o in tiles:
        os.remove(o)


def spot(ob, energy, colour, cone):
    ld = bpy.data.lights.new("Spot", "SPOT")
    ld.energy = energy
    ld.color = colour
    ld.spot_size = radians(min(cone, 170.0))
    ld.spot_blend = 0.5
    ld.shadow_soft_size = 0.08
    lo = bpy.data.objects.new("Spot", ld)
    aim = ob.matrix_world.to_3x3() @ Vector((1, 0, 0))
    q = (-aim).to_track_quat("Z", "Y")
    lo.matrix_world = Matrix.Translation(ob.matrix_world.translation) @ q.to_matrix().to_4x4()
    bpy.context.scene.collection.objects.link(lo)


def night(vid):
    size = (1400, 900)
    tiles = []
    for name, az, el in (("night, front: head / work / landing / flood lights", 125.0, 30.0),
                         ("night, rear: tail, hatch or bed lamp, beacon, amber markers", -145.0, 26.0)):
        R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.02, 0.03, 0.06), ground=(0.08, 0.06, 0.05),
                      sun_energy=0.15, sun_dir=(0.3, 0.5, 0.8))
        objs, by = load_vehicle(vid, lights=True)
        for o in objs:
            n = base(o)
            if n.startswith("Light_"):
                role = o.get("role")
                if role == "head":
                    spot(o, 1500.0, (1.0, 0.93, 0.82), 45.0)
                elif role == "work":
                    spot(o, 500.0, (1.0, 0.93, 0.82), 70.0)
                elif role == "flood":
                    spot(o, 4000.0, (1.0, 0.93, 0.82), 40.0)
                elif role == "aviation":
                    pl = bpy.data.lights.new("Aviation", "POINT")
                    pl.energy = 30.0
                    pl.color = (1.0, 0.2, 0.15)
                    po = bpy.data.objects.new("Aviation", pl)
                    po.location = o.matrix_world.translation
                    bpy.context.scene.collection.objects.link(po)
                elif role in ("hatch", "landing"):
                    spot(o, 250.0 if role == "hatch" else 400.0, (1.0, 0.9, 0.75), 80.0)
                elif role == "bed":
                    spot(o, 30.0, (1.0, 0.88, 0.7), 80.0)
                elif role == "beacon":
                    pl = bpy.data.lights.new("Beacon", "POINT")
                    pl.energy = 25.0
                    pl.color = (1.0, 0.65, 0.15)
                    po = bpy.data.objects.new("Beacon", pl)
                    po.location = o.matrix_world.translation
                    bpy.context.scene.collection.objects.link(po)
        R.ao_materials()
        if az > 0 and "Light_HeadL" in by:          # frame the lit ground ahead of the vehicle as well
            R.place_camera(Vector((-2.4, -3.5, 0.0)), Vector((11.0, 3.5, 2.6)), azimuth=az, elevation=el, margin=1.02,
                           aspect=size[0] / size[1], focal=R.FOCAL)
        else:
            fit(objs, az, el, size, margin=1.3)
        out = os.path.join(V.ART_DIR, "_tmp_night_%d.png" % len(tiles))
        R.render_to(out)
        tiles.append((name, out))
    R.contact_sheet(tiles, os.path.join(V.ART_DIR, "%s_night.png" % vid), cols=2, tile=(1000, 643))
    for _, o in tiles:
        os.remove(o)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ids = argv[argv.index("--ids") + 1].split(",") if "--ids" in argv else ["rover_small"]
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else ["turnaround", "scale", "poses", "night"]
    os.makedirs(V.ART_DIR, exist_ok=True)
    for vid in ids:
        for job in only:
            globals()[job](vid)



def context(vid):
    """satellite in context (critic round 19 fix 5): in orbit over the planet limb, sun from the side"""
    import bmesh
    size = (1600, 900)
    R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.01, 0.012, 0.025), ground=None,
                  sun_energy=4.0, sun_dir=(0.35, -0.8, 0.45))
    objs, by = load_vehicle(vid, lights=True, wings=20.0)
    me = bpy.data.meshes.new("Planet")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=48, radius=60.0)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    pl = bpy.data.objects.new("Planet", me)
    pl.location = (-8.0, 10.0, -66.0)
    mat = bpy.data.materials.new("PlanetMat")
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (0.36, 0.17, 0.08, 1.0)
    bs.inputs["Roughness"].default_value = 0.95
    me.materials.append(mat)
    bpy.context.scene.collection.objects.link(pl)
    for o in objs:                                   # the planet is far below: no satellite shadow on it
        try:
            o.visible_shadow = False
        except AttributeError:
            pass
    for o in objs:                                   # a slight roll so the wings catch the light
        if o.parent is None:
            o.matrix_world = Matrix.Rotation(radians(-18.0), 4, "X") @ o.matrix_world
    bpy.context.view_layer.update()
    R.ao_materials()
    lo, hi = R.world_bbox(objs)
    R.place_camera(lo - Vector((2.0, 2.0, 4.5)), hi + Vector((2.0, 2.0, 0.5)), azimuth=-35.0, elevation=20.0,
                   margin=1.0, aspect=size[0] / size[1], focal=R.FOCAL)
    R.render_to(os.path.join(V.ART_DIR, "%s_context.png" % vid))


if __name__ == "__main__":
    main()
