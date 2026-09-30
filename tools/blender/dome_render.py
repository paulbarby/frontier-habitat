"""
Frontier Habitat 5.0 - ART-B super dome renders (art/dome/). Imports the EXPORTED dome_*.glb files.
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/dome_render.py [-- --only overview_day,overview_night,atrium,gallery,cutaway]
"""
import bpy
import os
import sys
import math
from math import radians, cos, sin
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_render as R          # noqa: E402  (read-only use)
import dome_common as D         # noqa: E402

FILES = ["dome_shell.glb", "dome_floor1.glb", "dome_floor2.glb", "dome_floor3.glb", "dome_floor4.glb",
         "dome_floor5.glb", "dome_atrium.glb"]
STAGE_FILE = "dome_scaffold.glb"
GROUND = (0.52, 0.30, 0.17)
SUIT = os.path.join(D.MODEL_DIR, "astronaut_indoor.glb")


def base(o):
    return o.name.split(".")[0]


def load(hide_groups=(), hide_prefix=(), stages=False):
    objs = []
    for f in FILES + ([STAGE_FILE] if stages else []):
        objs += R.import_glb(os.path.join(D.MODEL_DIR, f))
    bpy.context.view_layer.update()
    hidden = set()
    for o in objs:
        top = o
        while top.parent is not None:
            top = top.parent
        chain, q = [], o
        while q is not None:
            chain.append(base(q))
            q = q.parent
        if base(top) in hide_groups or base(o) in hide_groups or any(c.startswith(hide_prefix) for c in chain if hide_prefix):
            hidden.add(o)
    for o in hidden:
        o.hide_render = True
        o.hide_viewport = True
    return [o for o in objs if o not in hidden], {base(o): o for o in objs}


def people(by, names, clip="idle", frame=0):
    """indoor colonists at anchors (scale reference)"""
    out = []
    for n in names:
        a = by.get(n)
        if a is None:
            continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=SUIT)
        objs = [o for o in bpy.data.objects if o not in before]
        rig = next((o for o in objs if o.type == "ARMATURE"), None)
        if rig is not None:
            ad = rig.animation_data or rig.animation_data_create()
            for tr in list(ad.nla_tracks):
                ad.nla_tracks.remove(tr)
            act = bpy.data.actions.get(clip)
            if act:
                ad.action = act
                if act.slots and ad.action_slot is None:
                    ad.action_slot = act.slots[0]
        for o in objs:
            if o.type == "MESH" and not any(m.type == "ARMATURE" for m in o.modifiers):
                o.hide_render = True                   # the importer's bone-shape sphere
            if o.parent is None:
                o.matrix_world = a.matrix_world @ o.matrix_world
        out += objs
    bpy.context.scene.frame_set(frame)
    return out


def glare():
    """night: a bloom pass so lit windows and signs glow (best effort: the compositor API changed in 5.x)"""
    sc = bpy.context.scene
    try:
        tree = bpy.data.node_groups.new("DomeComp", "CompositorNodeTree")
        sc.compositing_node_group = tree
        rl = tree.nodes.new("CompositorNodeRLayers")
        gl = tree.nodes.new("CompositorNodeGlare")
        gl.inputs["Type"].default_value = "Bloom"                 # Blender 5.x: the glare type is a menu socket
        gl.inputs["Quality"].default_value = "High"
        for sock, val in (("Threshold", 0.45), ("Size", 0.75), ("Strength", 1.25), ("Saturation", 1.2)):
            if sock in gl.inputs:
                gl.inputs[sock].default_value = val
        out = tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        go = tree.nodes.new("NodeGroupOutput")
        tree.links.new(rl.outputs["Image"], gl.inputs["Image"])
        tree.links.new(gl.outputs["Image"], go.inputs[0])
        return True
    except Exception as exc:
        print("glare not available:", exc)
        return False


def glass_preview(night=False):
    """what RENDER is asked to do in the game (critic round 24 fix 3): the glass gets a faint tint and a fresnel
    reflection, 20 % opaque facing the camera, up to 60 % at grazing angles"""
    for m in bpy.data.materials:
        if m.name.split(".")[0] != "Glass" or m.node_tree is None:
            continue
        nt = m.node_tree
        b = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
        if b is None:
            continue
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.45
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["To Min"].default_value = 0.12
        mr.inputs["To Max"].default_value = 0.85
        nt.links.new(lw.outputs["Facing"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], b.inputs["Alpha"])
        b.inputs["Roughness"].default_value = 0.03
        b.inputs["Base Color"].default_value = (0.55, 0.72, 0.8, 1.0)
        try:
            b.inputs["Specular IOR Level"].default_value = 1.0
        except Exception:
            pass
        if night:                                                  # city light caught at grazing angles
            mm = nt.nodes.new("ShaderNodeMath")
            mm.operation = "MULTIPLY"
            mm.inputs[1].default_value = 0.8
            nt.links.new(mr.outputs["Result"], mm.inputs[0])
            b.inputs["Emission Color"].default_value = (1.0, 0.72, 0.45, 1.0)
            nt.links.new(mm.outputs["Value"], b.inputs["Emission Strength"])
    sc = bpy.context.scene
    for key in ("use_raytracing", "use_ssr"):
        try:
            setattr(sc.eevee, key, True)
        except Exception:
            pass
    for m in bpy.data.materials:                                   # as in the game: single-sided unless marked
        if m.name.split(".")[0] not in ("Glass", "Water", "Plant", "PlantDark"):
            m.use_backface_culling = True


def sky():
    """a gradient sky so the glass has something to reflect (horizon pale, zenith darker)"""
    w = bpy.context.scene.world
    nt = w.node_tree
    bg = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.78, 0.62, 0.52, 1.0)
    ramp.color_ramp.elements[1].position = 0.6
    ramp.color_ramp.elements[1].color = (0.36, 0.42, 0.56, 1.0)
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])


def night_lights(by):
    for n, o in by.items():
        if n.startswith("Light_Lamp_"):
            ld = bpy.data.lights.new("L", "POINT")
            ld.energy, ld.color, ld.shadow_soft_size = 700.0, (1.0, 0.78, 0.5), 0.3
        elif n.startswith("Light_Pool_"):
            ld = bpy.data.lights.new("L", "POINT")
            ld.energy, ld.color = 900.0, (0.25, 0.85, 1.0)
        else:
            continue
        lo = bpy.data.objects.new("L", ld)
        lo.location = o.matrix_world.translation
        bpy.context.scene.collection.objects.link(lo)


def cam(pos, target, focal=35.0):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new("Cam")
    cd.lens = focal
    cd.sensor_width = 36.0
    cd.clip_start = 0.1
    cd.clip_end = 2000.0
    co = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(co)
    co.location = Vector(pos)
    d = Vector(target) - Vector(pos)
    co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.camera = co
    return co


def orbit(az, el, dist, target=(0, 0, 12.0), focal=35.0):
    t = Vector(target)
    p = t + Vector((cos(radians(el)) * cos(radians(az)), cos(radians(el)) * sin(radians(az)), sin(radians(el)))) * dist
    return cam(p, t, focal)


def day(size, sun=3.0):
    R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.62, 0.58, 0.55), ground=GROUND, samples=32,
                  sun_energy=sun, sun_dir=(0.45, -0.35, 0.82))
    sky()


def night(size):
    R.setup_scene(size[0], size[1], transparent=False, world_rgb=(0.012, 0.016, 0.03), ground=(0.06, 0.045, 0.035),
                  samples=32, sun_energy=0.12, sun_dir=(0.3, 0.5, 0.8))


def overview_day(dist=150.0, name="pilot_overview_day"):
    size = (1800, 1100)
    day(size)
    load()
    R.ao_materials()
    glass_preview()
    orbit(-42.0, 32.0, dist, focal=40.0 if dist < 200 else 45.0)
    R.render_to(os.path.join(D.ART_DIR, name + ".png"))


def overview_night(dist=150.0, name="pilot_overview_night"):
    size = (1800, 1100)
    night(size)
    objs, by = load()
    R.ao_materials()
    glass_preview(night=True)
    night_lights(by)
    for k in range(6):                                                 # soft fill in the atrium and the ring
        ld = bpy.data.lights.new("P", "POINT")
        ld.energy = 12000.0
        ld.color = (1.0, 0.85, 0.65)
        lo = bpy.data.objects.new("P", ld)
        lo.location = D.pol(12.0 if k % 2 else 27.0, 60.0 * k, 8.0)
        bpy.context.scene.collection.objects.link(lo)
    glare()
    orbit(-42.0, 32.0, dist, focal=40.0 if dist < 200 else 45.0)
    R.render_to(os.path.join(D.ART_DIR, name + ".png"))


def overview_day_250():
    overview_day(250.0, "overview_250_day")


def overview_night_250():
    overview_night(250.0, "overview_250_night")


def atrium():
    size = (1800, 1000)
    day(size, sun=3.5)
    objs, by = load()
    glass_preview()
    people(by, ["Anchor_Lounger_1", "Anchor_Lounger_3", "Anchor_Plaza_0", "Anchor_Plaza_3", "Anchor_Bench_2",
                "Anchor_Venue_cafe", "Anchor_Venue_bar", "Anchor_Lifeguard"], clip="idle")
    R.ao_materials()
    cam(D.pol(19.6, -20.0, 10.2), (-3.0, 3.0, 1.0), focal=24.0)
    R.render_to(os.path.join(D.ART_DIR, "pilot_atrium_pool.png"))


def atrium_night():
    size = (1800, 1000)
    night(size)
    objs, by = load()
    glass_preview(night=True)
    night_lights(by)
    people(by, ["Anchor_Lounger_1", "Anchor_Plaza_0", "Anchor_Plaza_3", "Anchor_Venue_bar"], clip="idle")
    R.ao_materials()
    glare()
    cam(D.pol(19.6, -20.0, 10.2), (-3.0, 3.0, 1.0), focal=24.0)
    R.render_to(os.path.join(D.ART_DIR, "pilot_atrium_night.png"))


def gallery():
    size = (1800, 1000)
    day(size, sun=3.5)
    objs, by = load()
    people(by, ["Anchor_Venue_grocery", "Anchor_Venue_clinic", "Anchor_Seat_cafe_3", "Anchor_Seat_cafe_4",
                "Anchor_Venue_restaurant", "Anchor_Work_cafe_0"], clip="idle")
    R.ao_materials()
    cam(D.pol(21.4, 128.0, 1.75), D.pol(21.6, 88.0, 2.2), focal=22.0)
    R.render_to(os.path.join(D.ART_DIR, "pilot_gallery_L1.png"))


def cutaway():
    size = (1800, 1100)
    day(size, sun=3.5)
    load(hide_groups=("Floor_2", "Floor_3", "Floor_4", "Floor_5", "Floor_Roof", "Dome", "Lifts"))
    R.ao_materials()
    orbit(-60.0, 58.0, 95.0, target=(0, 0, 0.0), focal=35.0)
    R.render_to(os.path.join(D.ART_DIR, "pilot_cutaway_L1.png"))


UPPER = ("Floor_3", "Floor_4", "Floor_5", "Floor_Roof", "Dome", "Lifts")


def cutaway_L2():
    size = (1800, 1100)
    day(size, sun=3.5)
    load(hide_groups=UPPER)
    R.ao_materials()
    orbit(-60.0, 58.0, 95.0, target=(0, 0, 5.0), focal=35.0)
    R.render_to(os.path.join(D.ART_DIR, "L2_cutaway.png"))


def mood(view, name, lights=()):
    """an interior with the floors above removed, at night: emissives + a few coloured point lights"""
    size = (1800, 1000)
    night(size)
    objs, by = load(hide_groups=UPPER)
    glass_preview()
    for (pos, col, e) in lights:
        ld = bpy.data.lights.new("P", "POINT")
        ld.energy, ld.color = e, col
        lo = bpy.data.objects.new("P", ld)
        lo.location = pos
        bpy.context.scene.collection.objects.link(lo)
    R.ao_materials()
    glare()
    cam(*view)
    R.render_to(os.path.join(D.ART_DIR, name + ".png"))


def club():
    z = D.FLOOR_Z[1]
    mid = 232.5
    mood((D.pol(23.9, 262.0, z + 1.75), D.pol(31.0, 228.0, z + 1.2), 20.0), "L2_club",
         [(D.pol(28.0, mid - 8, z + 3.0), (1.0, 0.3, 0.85), 500.0), (D.pol(28.0, mid + 8, z + 3.0), (0.3, 0.8, 1.0), 500.0),
          (D.pol(31.5, mid, z + 3.2), (1.0, 0.7, 0.3), 300.0), (D.pol(25.0, 250.0, z + 3.0), (1.0, 0.8, 0.6), 200.0)])


def arcade():
    z = D.FLOOR_Z[1]
    mood((D.pol(26.0, 34.5, z + 1.9), D.pol(28.9, 37.5, z + 1.2), 26.0), "L2_arcade_prism",
         [(D.pol(29.0, 37.5, z + 3.0), (0.6, 0.8, 1.0), 900.0), (D.pol(26.0, 20.0, z + 3.0), (1.0, 0.5, 0.9), 700.0),
          (D.pol(26.0, 55.0, z + 3.0), (0.5, 1.0, 0.8), 700.0)])


def arcade_room():
    z = D.FLOOR_Z[1]
    mood((D.pol(23.4, 66.0, z + 3.2), D.pol(29.5, 30.0, z + 0.6), 20.0), "L2_arcade_room",
         [(D.pol(28.0, 25.0, z + 3.2), (0.6, 0.8, 1.0), 1200.0), (D.pol(28.0, 50.0, z + 3.2), (1.0, 0.5, 0.9), 1200.0)])


def hotel_room():
    """a hotel room on L3 with the floors above removed, by day and from inside the door"""
    z = D.FLOOR_Z[2]
    size = (1800, 1000)
    day(size, sun=3.5)
    load(hide_groups=("Floor_4", "Floor_5", "Floor_Roof", "Dome", "Lifts"))
    R.ao_materials()
    ang = 60.0
    import mathutils
    rot = mathutils.Matrix.Rotation(math.radians(ang), 3, "Z")
    cam(rot @ mathutils.Vector((24.2, 1.6, z + 2.6)), rot @ mathutils.Vector((30.5, -0.8, z + 0.6)), focal=18.0)
    R.render_to(os.path.join(D.ART_DIR, "L3_hotel_room_inside.png"))


def club_door():
    """the Club door from the L2 gallery: bouncer post, rope line, ADULTS ONLY / 21+ sign (tone rule)"""
    z = D.FLOOR_Z[1]
    size = (1800, 1000)
    night(size)
    objs, by = load(hide_groups=UPPER)
    glass_preview(night=True)
    people(by, ["Anchor_Bouncer_club_0"], clip="idle")
    for (pos, col, e) in ((D.pol(21.2, 240.0, z + 3.2), (1.0, 0.8, 0.6), 400.0), (D.pol(21.0, 232.0, z + 3.0), (1.0, 0.4, 0.9), 250.0)):
        ld = bpy.data.lights.new("P", "POINT")
        ld.energy, ld.color = e, col
        lo = bpy.data.objects.new("P", ld)
        lo.location = pos
        bpy.context.scene.collection.objects.link(lo)
    R.ao_materials()
    glare()
    cam(D.pol(19.3, 233.0, z + 2.5), D.pol(22.8, 241.5, z + 1.3), focal=16.0)
    R.render_to(os.path.join(D.ART_DIR, "L2_club_door.png"))


def bar_back():
    """critic round 34: the L1 bar's back bar (mirror, 3 shelves of bottles) and the window display, at night"""
    z = D.FLOOR_Z[0]
    size = (1800, 1000)
    night(size)
    objs, by = load(hide_groups=("Floor_2", "Floor_3", "Floor_4", "Floor_5", "Floor_Roof", "Dome", "Lifts"))
    glass_preview()
    for (pos, col, e) in ((D.pol(28.0, 226.0, z + 3.0), (1.0, 0.75, 0.5), 500.0), (D.pol(28.0, 240.0, z + 3.0), (1.0, 0.4, 0.8), 350.0)):
        ld = bpy.data.lights.new("P", "POINT")
        ld.energy, ld.color = e, col
        lo = bpy.data.objects.new("P", ld)
        lo.location = pos
        bpy.context.scene.collection.objects.link(lo)
    R.ao_materials()
    glare()
    cam(D.pol(26.0, 221.0, z + 1.7), D.pol(33.0, 232.0, z + 1.3), focal=22.0)
    R.render_to(os.path.join(D.ART_DIR, "L1_bar_back.png"))


def hotel_room_night():
    z = D.FLOOR_Z[2]
    size = (1800, 1000)
    night(size)
    objs, by = load(hide_groups=("Floor_4", "Floor_5", "Floor_Roof", "Dome", "Lifts"))
    import mathutils
    for n, o in by.items():
        if n.startswith("Anchor_Lamp_3_4_"):
            ld = bpy.data.lights.new("L", "POINT")
            ld.energy, ld.color, ld.shadow_soft_size = 60.0, (1.0, 0.72, 0.42), 0.15
            lo = bpy.data.objects.new("L", ld)
            lo.location = o.matrix_world.translation
            bpy.context.scene.collection.objects.link(lo)
    R.ao_materials()
    glare()
    rot = mathutils.Matrix.Rotation(math.radians(60.0), 3, "Z")
    cam(rot @ mathutils.Vector((24.2, 1.6, z + 2.6)), rot @ mathutils.Vector((30.5, -0.8, z + 0.6)), focal=18.0)
    R.render_to(os.path.join(D.ART_DIR, "L3_hotel_room_night.png"))


def gym_view():
    z = D.FLOOR_Z[1]
    size = (1800, 1000)
    day(size, sun=3.5)
    load(hide_groups=UPPER)
    R.ao_materials()
    cam(D.pol(22.0, 102.0, z + 3.4), D.pol(29.0, 125.0, z + 0.6), focal=22.0)
    R.render_to(os.path.join(D.ART_DIR, "L2_gym.png"))


FITOUT = ("Shell_", "Lamps_", "Venue", "Unit_", "Roof_Garden", "Roof_Lamps", "ArcadeScreen", "Atrium", "Promenade", "Lift_")


def stages():
    """construction stages: foundation + site + crane, level 2 with scaffold, dome frame, finished"""
    size = (1100, 720)
    tiles = []
    floors = ["Floor_%d" % n for n in range(1, 6)]
    jobs = (("1 foundation, site, crane", floors + ["Floor_Roof", "Dome", "Lifts", "Gates"] + ["Scaffold_%d" % n for n in range(1, 6)], FITOUT),
            ("2 level 2 structure, scaffold", ["Floor_3", "Floor_4", "Floor_5", "Floor_Roof", "Dome", "Scaffold_1", "Scaffold_3",
                                              "Scaffold_4", "Scaffold_5"], FITOUT),
            ("3 dome frame (structure complete)", ["Scaffold_%d" % n for n in range(1, 6)] + ["Crane", "Dome_Glass", "Dome_Lights"], FITOUT),
            ("4 finished, fitted out", ["Scaffold_%d" % n for n in range(1, 6)] + ["Crane", "Site"], ()))
    for k, (name, hide, pref) in enumerate(jobs):
        day(size)
        load(hide_groups=tuple(hide), hide_prefix=tuple(pref), stages=True)
        R.ao_materials()
        glass_preview()
        orbit(-42.0, 30.0, 165.0, focal=40.0)
        out = os.path.join(D.ART_DIR, "_tmp_stage_%d.png" % k)
        R.render_to(out)
        tiles.append((name, out))
    R.contact_sheet(tiles, os.path.join(D.ART_DIR, "build_stages.png"), cols=2, tile=size)
    for _, o in tiles:
        os.remove(o)


def cutaway_L4():
    size = (1800, 1100)
    day(size, sun=3.5)
    load(hide_groups=("Floor_5", "Floor_Roof", "Dome", "Lifts"))
    R.ao_materials()
    orbit(-60.0, 58.0, 95.0, target=(0, 0, 13.0), focal=35.0)
    R.render_to(os.path.join(D.ART_DIR, "L4_cutaway_units.png"))


def cutaway_L3():
    size = (1800, 1100)
    day(size, sun=3.5)
    load(hide_groups=("Floor_4", "Floor_5", "Floor_Roof", "Dome", "Lifts"))
    R.ao_materials()
    cam(D.pol(40.0, -30.0, 30.0), D.pol(27.0, 0.0, 9.5), focal=30.0)
    R.render_to(os.path.join(D.ART_DIR, "L3_hotel_rooms.png"))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    jobs = argv[argv.index("--only") + 1].split(",") if "--only" in argv else [
        "overview_day", "overview_night", "overview_day_250", "overview_night_250", "atrium", "atrium_night", "gallery",
        "cutaway"]
    os.makedirs(D.ART_DIR, exist_ok=True)
    for j in jobs:
        globals()[j]()


if __name__ == "__main__":
    main()
