"""
Frontier Habitat 3.0 - ART-NPC render sheets (imports the EXPORTED astronaut GLBs; what the game receives).

Used by npc_verify.py (--renders).  Sheets go to art/npc/:
  turnaround_<variant>.png  stand pose from 8 sides, close-ups, and the model at game size (30 / 55 / 80 px)
  clips_<variant>.png       every clip at 4 frames
  transitions.png           every pose change: loop end -> enter start ... enter end -> loop start
"""
import bpy
import os
import sys
import math
from math import radians, sin, cos, tan, atan
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
import ext_render as R          # noqa: E402  (read-only use: bitmap font and PNG helpers)
import numpy as np              # noqa: E402

TMP = os.path.join(N.ART_DIR, "_tmp")


def _tmpdir():
    """Scratch tiles; .gdignore keeps Godot from importing them."""
    os.makedirs(TMP, exist_ok=True)
    g = os.path.join(TMP, ".gdignore")
    if not os.path.exists(g):
        open(g, "w").close()


def _world(rgb_top=(0.42, 0.45, 0.50), strength=1.0):
    world = bpy.data.worlds.new("NpcWorld")
    if world.node_tree is None:
        world.use_nodes = True
    nt = world.node_tree
    bg = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBackground"), None)
    bg.inputs["Color"].default_value = (*rgb_top, 1.0)
    bg.inputs["Strength"].default_value = strength
    bpy.context.scene.world = world


def _light(kind, name, energy, direction=None, loc=None, size=1.0, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, kind)
    d.energy = energy
    d.color = color
    if kind == "SUN":
        d.angle = radians(3.0)
    if kind == "AREA":
        d.size = size
    ob = bpy.data.objects.new(name, d)
    if direction is not None:
        ob.rotation_euler = Vector(direction).to_track_quat("Z", "Y").to_euler()
    if loc is not None:
        ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    return ob


def setup(w, h, ground=(0.50, 0.33, 0.22), grid=False, samples=32, night=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.fps = N.FPS
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:
        pass
    try:
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "None"
    except Exception:
        pass
    _world((0.36, 0.38, 0.43), 0.9)
    # key (warm sun), fill (cool, opposite side), rim (behind)
    _light("SUN", "Key", 3.4, direction=(0.55, -0.55, 0.62), color=(1.0, 0.95, 0.88))
    _light("SUN", "Fill", 0.9, direction=(0.3, 0.8, 0.35), color=(0.80, 0.88, 1.0))
    _light("SUN", "Rim", 2.2, direction=(-0.8, 0.15, 0.45), color=(1.0, 0.92, 0.85))
    if ground is not None:
        mesh = bpy.data.meshes.new("Ground")
        g = 40.0
        mesh.from_pydata([(-g, -g, 0.0), (g, -g, 0.0), (g, g, 0.0), (-g, g, 0.0)], [], [(0, 1, 2, 3)])
        m = R.flat_material("GroundMat", ground, rough=0.95)
        mesh.materials.append(m)
        sc.collection.objects.link(bpy.data.objects.new("Ground", mesh))
        if grid:
            add_grid()
    return sc


def add_grid(step=0.25, half=4.0, width=0.006):
    verts, faces = [], []
    k = int(half / step)
    for i in range(-k, k + 1):
        x = i * step
        for (a0, a1, b0, b1) in ((x - width, x + width, -half, half), (-half, half, x - width, x + width)):
            n = len(verts)
            verts += [(a0, b0, 0.001), (a1, b0, 0.001), (a1, b1, 0.001), (a0, b1, 0.001)]
            faces.append((n, n + 1, n + 2, n + 3))
    mesh = bpy.data.meshes.new("Grid")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(R.flat_material("GridMat", (0.30, 0.19, 0.12), rough=0.95))
    bpy.context.scene.collection.objects.link(bpy.data.objects.new("Grid", mesh))


def add_box(name, c, s, rgb=(0.35, 0.38, 0.42)):
    mesh = bpy.data.meshes.new(name)
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    P = [(c[0] + sx * hx, c[1] + sy * hy, c[2] + sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    F = [(4, 6, 7, 5), (0, 1, 3, 2), (2, 3, 7, 6), (0, 4, 5, 1), (1, 5, 7, 3), (0, 2, 6, 4)]
    mesh.from_pydata(P, [], F)
    mesh.materials.append(R.flat_material(name + "Mat", rgb, rough=0.7))
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def add_seat():
    """Seat to the section 3.3 contract: top 0.46 m, centre 0.30 m behind the stand point."""
    add_box("Seat", (-0.30, 0.0, 0.43), (0.44, 0.46, 0.06), (0.24, 0.29, 0.37))
    add_box("SeatLeg", (-0.30, 0.0, 0.20), (0.08, 0.08, 0.40), (0.30, 0.32, 0.35))


def add_props(kind):
    """Furniture built to the section 3.3 numbers (stand point at the origin, facing +X)."""
    if not kind:
        return
    if kind == "seat":
        add_seat()
    elif kind == "bed":        # mattress top 0.55 m, centre line 0.55 m behind, head end +Y
        add_box("BedBase", (-0.55, 0.0, 0.20), (0.78, 1.84, 0.40), (0.30, 0.32, 0.35))
        add_box("Mattress", (-0.55, 0.0, 0.475), (0.94, 2.04, 0.15), (0.62, 0.66, 0.72))
        add_box("Pillow", (-0.55, 0.82, 0.59), (0.58, 0.30, 0.08), (0.85, 0.86, 0.88))
    elif kind == "console":    # top 1.0 m; hands 0.40-0.50 m ahead
        add_box("Console", (0.63, 0.0, 0.50), (0.50, 0.90, 1.00), (0.24, 0.29, 0.37))
        add_box("ConsoleScreen", (0.84, 0.0, 1.25), (0.05, 0.60, 0.40), (0.10, 0.45, 0.55))
    elif kind == "bench":      # top 0.9 m
        add_box("Bench", (0.62, 0.0, 0.45), (0.50, 1.00, 0.90), (0.40, 0.33, 0.26))
    elif kind == "panel":      # machine face 0.45 m ahead, panel centre 0.4 m high
        add_box("Machine", (0.75, 0.0, 0.55), (0.60, 0.90, 1.10), (0.30, 0.34, 0.40))
        add_box("Panel", (0.448, 0.0, 0.40), (0.006, 0.40, 0.30), (0.75, 0.55, 0.20))
    elif kind == "desk":       # top 0.74 m (sit_type, sit_eat)
        add_seat()
        add_box("DeskTop", (0.50, 0.0, 0.72), (0.56, 1.00, 0.04), (0.45, 0.36, 0.28))
        add_box("DeskLeg", (0.74, 0.0, 0.35), (0.06, 0.80, 0.70), (0.30, 0.32, 0.35))
    elif kind == "crate":
        s = 0.40
        ob = add_box("Crate", (0.0, 0.0, s / 2), (s, s, s), (0.55, 0.45, 0.30))
        bpy.context.scene["crate_follow"] = 1


def _follow_crate(rig):
    ob = bpy.data.objects.get("Crate")
    if ob is None:
        return
    pb = rig.pose.bones.get("prop.R")
    ob.location = (rig.matrix_world @ pb.matrix).translation
    ob.location.z -= 0.0          # the crate mesh is built with its bottom at the origin (see add_props)


PROP_FOR = {"sit_enter": "seat", "sit_idle": "seat", "sit_exit": "seat", "sit_eat": "desk", "sit_type": "desk",
            "lie_enter": "bed", "sleep": "bed", "lie_exit": "bed", "work_console": "console", "work_bench": "bench",
            "kneel_enter": "panel", "repair_kneel": "panel", "kneel_exit": "panel", "carry_idle": "crate",
            "carry_walk": "crate"}


def import_astronaut(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in objs if o.type == "ARMATURE")
    ad = rig.animation_data or rig.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    R.ao_materials()
    return rig, objs


def action_for(name):
    exact = bpy.data.actions.get(name)
    if exact:
        return exact
    for a in bpy.data.actions:
        if a.name.split("_Rig")[0] == name or a.name.startswith(name + "_"):
            return a
    return None


def set_clip(rig, name, frame):
    act = action_for(name)
    ad = rig.animation_data
    ad.action = act
    if act.slots and ad.action_slot is None:
        ad.action_slot = act.slots[0]
    bpy.context.scene.frame_set(int(frame))
    bpy.context.view_layer.update()
    _follow_crate(rig)


def camera(target, azimuth, elevation, dist, lens=85.0, ortho=None):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cd.sensor_width = 36.0
    cd.clip_start = 0.05
    cd.clip_end = 200.0
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    az, el = radians(azimuth), radians(elevation)
    d = Vector((cos(el) * cos(az), cos(el) * sin(az), sin(el)))
    cam.location = Vector(target) + d * dist
    cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    sc.camera = cam
    return cam


def clear_cameras():
    for o in list(bpy.data.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o)


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def compose(rows, out, pad=6, label_h=26, bg=0.93, title=None):
    """rows: list of rows; row = list of (label, png path).  Tiles keep their own size."""
    imgs = [[(lab, R.load_png(p)) for lab, p in row] for row in rows]
    W = max(sum(im.shape[1] + pad for _, im in row) + pad for row in imgs)
    title_h = 34 if title else 0
    H = title_h + sum(max(im.shape[0] for _, im in row) + label_h + pad for row in imgs) + pad
    sheet = np.full((H, W, 3), bg, dtype=np.float32)
    if title:
        R.draw_text(sheet, title, pad + 4, 8, scale=3)
    y = title_h + pad
    for row in imgs:
        x = pad
        rh = max(im.shape[0] for _, im in row)
        for lab, im in row:
            h, w = im.shape[:2]
            sheet[y:y + h, x:x + w] = im
            R.draw_text(sheet, lab, x + 4, y + h + 6, scale=2)
            x += w + pad
        y += rh + label_h + pad
    R.save_png(sheet, out)
    return out


def upscale_nearest(path, out, factor):
    im = R.load_png(path)
    big = np.repeat(np.repeat(im, factor, axis=0), factor, axis=1)
    R.save_png(big, out)
    return out


# --------------------------------------------------------------------------------------
HEADS = ["Head_0", "Head_1", "Head_2", "Head_3"]


def show_head(objs, k):
    """Indoor model: show Head_k only (the game draws one head per colonist)."""
    for o in objs:
        nm = o.name.split(".")[0]
        if nm in HEADS:
            o.hide_render = nm != "Head_%d" % k
            o.hide_viewport = o.hide_render


# RENDER's palettes (shaders/npc_skin.gdshader, linear): six skin tones, four hair colours; hair = (tone + head*3) % 4
SKIN_TONES = [(0.21, 0.09, 0.04), (0.37, 0.17, 0.07), (0.55, 0.30, 0.15), (0.72, 0.44, 0.26), (0.85, 0.57, 0.38),
              (0.91, 0.60, 0.42)]   # tone 5: warmer value proposed to RENDER (was 0.93, 0.68, 0.52)
HAIR_COLOURS = [(0.016, 0.012, 0.010), (0.055, 0.030, 0.017), (0.160, 0.055, 0.020), (0.360, 0.240, 0.110)]


def set_mat_rgb(name, rgb):
    """Base colour of an imported material (before the AO multiply that ao_materials() inserts)."""
    for m in bpy.data.materials:
        if m.name.split(".")[0] != name or m.node_tree is None:
            continue
        nt = m.node_tree
        done = False
        for n in nt.nodes:                        # the multiply that carries the base colour (the other input is COLOR_0)
            if n.bl_idname == "ShaderNodeMix":
                for i in (6, 7):
                    if not n.inputs[i].is_linked:
                        n.inputs[i].default_value = (*rgb, 1.0)
                        done = True
            elif n.bl_idname == "ShaderNodeMixRGB":
                for i in (1, 2):
                    if not n.inputs[i].is_linked:
                        n.inputs[i].default_value = (*rgb, 1.0)
                        done = True
            elif n.bl_idname == "ShaderNodeRGB":
                n.outputs[0].default_value = (*rgb, 1.0)
                done = True
        bsdf = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
        if not done and bsdf is not None and not bsdf.inputs["Base Color"].is_linked:
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)


def clip_camera(name):
    """(target, azimuth, elevation, distance) that shows a clip best."""
    if name in ("lie_enter", "sleep", "lie_exit"):
        return (-0.35, 0.0, 0.62), -55, 26, 6.0
    if name in ("walk", "run", "injured_walk", "carry_walk"):
        return (0.0, 0.0, 0.88), -90, 6, 5.1
    if name in ("kneel_enter", "repair_kneel", "kneel_exit"):
        return (0.05, 0.0, 0.62), -70, 12, 4.8
    if name in ("collapse", "dead"):
        return (0.0, 0.15, 0.55), -50, 28, 5.6
    if name.startswith("sit"):
        return (-0.05, 0.0, 0.80), -70, 10, 5.0
    return (0.05, 0.0, 0.88), -60, 8, 5.1


def turnaround(variant, glb):
    _tmpdir()
    tiles = []
    setup(420, 620)
    rig, objs = import_astronaut(glb)
    show_head(objs, 0)
    set_clip(rig, "idle", 0)
    for k, az in enumerate((0, 45, 90, 135, 180, 225, 270, 315)):
        clear_cameras()
        camera((0.0, 0.0, 0.93), az, 6.0, 4.5, lens=85)
        tiles.append(("az %d" % az, render(os.path.join(TMP, "turn_%d.png" % k))))
    bpy.context.scene.render.resolution_x = 620
    bpy.context.scene.render.resolution_y = 620
    close = []
    if variant == "suit":
        shots = (((0.03, 0.0, 1.62), 35, 8, 1.9, "helmet"), ((-0.1, 0.0, 1.28), 150, 14, 2.6, "pack"),
                 ((0.12, 0.0, 1.22), 20, 6, 1.5, "chest box"), ((0.05, 0.0, 0.25), 25, 18, 1.9, "legs and boots"))
    else:
        shots = (((0.03, 0.0, 1.62), 30, 6, 1.5, "face"), ((0.0, 0.0, 1.30), 150, 12, 2.4, "back"),
                 ((0.05, 0.25, 0.85), 30, 10, 1.6, "arm and hand"), ((0.05, 0.0, 0.25), 25, 18, 1.9, "legs and boots"))
    for k, (tgt, az, el, dist, lab) in enumerate(shots):
        clear_cameras()
        camera(tgt, az, el, dist, lens=85)
        close.append((lab, render(os.path.join(TMP, "close_%d.png" % k))))
    rows = [tiles[:4], tiles[4:], close]
    if variant == "indoor":
        heads = []
        for k in range(4):
            show_head(objs, k)
            clear_cameras()
            camera((0.03, 0.0, 1.64), 40, 6, 1.5, lens=85)
            heads.append(("Head_%d" % k, render(os.path.join(TMP, "head_%d.png" % k))))
        rows.append(heads)
        small = []
        for k in range(4):
            bpy.context.scene.render.resolution_x = int(55 / 0.62)
            bpy.context.scene.render.resolution_y = int(55 / 0.62)
            show_head(objs, k)
            clear_cameras()
            camera((0.0, 0.0, 0.9), -40, 50, 60.0, lens=85, ortho=1.8 / 0.62)
            raw = render(os.path.join(TMP, "headgame_%d.png" % k))
            small.append(("Head_%d 55 px x3" % k, upscale_nearest(raw, os.path.join(TMP, "headgame_up_%d.png" % k), 3)))
        rows.append(small)
        tones = []
        bpy.context.scene.render.resolution_x = 360
        bpy.context.scene.render.resolution_y = 360
        heads_for_tone = (0, 1, 3, 2, 1, 3)      # with RENDER's rule this row shows all 4 hair colours and 4 heads
        for t in range(6):
            head = heads_for_tone[t]
            show_head(objs, head)
            set_mat_rgb("Skin", SKIN_TONES[t])
            set_mat_rgb("Hair", HAIR_COLOURS[(t + head * 3) % 4])
            clear_cameras()
            camera((0.03, 0.0, 1.60), 25, 4, 1.9, lens=85)
            tones.append(("tone %d hair %d" % (t, (t + head * 3) % 4), render(os.path.join(TMP, "tone_%d.png" % t))))
        rows.append(tones)
        set_mat_rgb("Skin", (0.72, 0.44, 0.26))
        set_mat_rgb("Hair", HAIR_COLOURS[1])
        show_head(objs, 0)
    game = []
    for k, px in enumerate((30, 55, 80)):
        H = int(px / 0.62)
        bpy.context.scene.render.resolution_x = H
        bpy.context.scene.render.resolution_y = H
        clear_cameras()
        camera((0.0, 0.0, 0.9), -40, 50, 60.0, lens=85, ortho=1.8 / 0.62)
        raw = render(os.path.join(TMP, "game_%d.png" % k))
        f = max(1, 300 // H)
        game.append(("%d px x%d" % (px, f), upscale_nearest(raw, os.path.join(TMP, "game_up_%d.png" % k), f)))
    rows.append(game)
    out = os.path.join(N.ART_DIR, "turnaround_%s.png" % variant)
    compose(rows, out, title="astronaut_%s  stand pose (idle frame 0)" % variant)
    return out


def clip_sheet(variant, glb, clips):
    """clips: [(name, frames)]; every clip at 4 frames, two clips per row, furniture to the section 3.3 numbers."""
    _tmpdir()
    tiles = []
    for name, n in clips:
        setup(300, 400, grid=name in ("walk", "run", "injured_walk", "carry_walk"))
        add_props(PROP_FOR.get(name, ""))
        rig, objs = import_astronaut(glb)
        show_head(objs, 0)
        tgt, az, el, dist = clip_camera(name)
        for k in range(4):
            f = int(round(n * k / 4))
            set_clip(rig, name, f)
            clear_cameras()
            camera(tgt, az, el, dist, lens=85)
            tiles.append(("%s %d" % (name, f), render(os.path.join(TMP, "clip_%s_%d.png" % (name, k)))))
    rows = [tiles[i:i + 8] for i in range(0, len(tiles), 8)]
    out = os.path.join(N.ART_DIR, "clips_%s.png" % variant)
    compose(rows, out, title="astronaut_%s: %d clips, 4 frames each (frame number under each)" % (variant, len(clips)))
    return out


def deform_sheet(variant, glb, shots):
    """Close-ups of the skinning at the joints.  shots: [(label, clip, frame, target, azimuth, elevation, dist)]"""
    _tmpdir()
    tiles = []
    for k, (lab, clip, frame, tgt, az, el, dist) in enumerate(shots):
        setup(480, 480, grid=False)
        add_props(PROP_FOR.get(clip, ""))
        rig, objs = import_astronaut(glb)
        show_head(objs, 0)
        set_clip(rig, clip, frame)
        clear_cameras()
        camera(tgt, az, el, dist, lens=85)
        tiles.append((lab, render(os.path.join(TMP, "deform_%s_%d.png" % (variant, k)))))
    out = os.path.join(N.ART_DIR, "deform_%s.png" % variant)
    compose([tiles[i:i + 4] for i in range(0, len(tiles), 4)], out, title="astronaut_%s skinning at the joints" % variant)
    return out


def transitions_sheet(rows_spec, title):
    """rows_spec: [(variant, glb, label, [(clip, frame, label)])] -> art/npc/transitions.png"""
    _tmpdir()
    rows = []
    for k, (variant, glb, label, steps) in enumerate(rows_spec):
        setup(260, 360)
        add_props(PROP_FOR.get(steps[1][0], ""))
        rig, objs = import_astronaut(glb)
        show_head(objs, k % 4)
        tgt, az, el, dist = clip_camera(steps[1][0])
        row = []
        for j, (clip, frame, lab) in enumerate(steps):
            set_clip(rig, clip, frame)
            clear_cameras()
            camera(tgt, az, el, dist + 0.2, lens=85)
            row.append(("%s %s" % (variant[0], lab), render(os.path.join(TMP, "tr_%d_%d.png" % (k, j)))))
        rows.append(row)
    out = os.path.join(N.ART_DIR, "transitions.png")
    compose(rows, out, title=title)
    return out


CHAINS = [("stand to sit", "idle", "sit_enter", "sit_idle"), ("sit to stand", "sit_idle", "sit_exit", "idle"),
          ("stand to kneel", "idle", "kneel_enter", "repair_kneel"), ("kneel to stand", "repair_kneel", "kneel_exit", "idle"),
          ("stand to lie", "idle", "lie_enter", "sleep"), ("lie to stand", "sleep", "lie_exit", "idle"),
          ("collapse", "idle", "collapse", "dead"), ("cheer", "idle", "cheer", "idle")]


def all_sheets(facts, clips_meta, meta):
    out = []
    order = ["idle", "idle_look", "walk", "run", "carry_idle", "carry_walk", "work_console", "work_bench", "talk",
             "injured_walk", "kneel_enter", "repair_kneel", "kneel_exit", "sit_enter", "sit_idle", "sit_eat", "sit_type",
             "sit_exit", "lie_enter", "sleep", "lie_exit", "collapse", "dead", "cheer"]
    variants = [v for v in ("suit", "indoor") if facts.get(v)]
    for v in variants:
        glb = os.path.join(N.MODEL_DIR, "astronaut_%s.glb" % v)
        out.append(turnaround(v, glb))
        out.append(clip_sheet(v, glb, [(c, clips_meta[c]["frames"]) for c in order
                                       if c in clips_meta and c in facts[v]["animations"]]))
        se = clips_meta.get("sit_enter", {}).get("frames", 0)
        out.append(deform_sheet(v, glb, [
            ("sit hips and knees", "sit_idle", 0, (-0.05, 0.0, 0.55), -60, 15, 2.2),
            ("sit from the back", "sit_idle", 0, (-0.2, 0.0, 0.6), -150, 20, 2.4),
            ("sit_enter elbows", "sit_enter", se // 2, (0.0, 0.0, 0.9), -30, 10, 2.6),
            ("walk knee and hip", "walk", 8, (0.0, 0.0, 0.55), -90, 5, 2.3),
            ("run push-off", "run", 5, (-0.1, 0.0, 0.45), -80, 8, 2.4),
            ("hand" if v == "indoor" else "glove", "idle", 0, (0.07, 0.40, 0.86), 20, 5, 0.9),
            ("carry grip", "carry_idle", 0, (0.3, 0.0, 0.95), -40, 20, 2.2),
            ("kneel knee", "repair_kneel", 0, (0.0, 0.0, 0.3), -100, 10, 2.2)]))
    spec = []
    for label, a, e, b in CHAINS:
        n = clips_meta.get(e, {}).get("frames", 0)
        na = clips_meta.get(a, {}).get("frames", 0)
        steps = [(a, na, "%s end" % a), (e, 0, "%s 0" % e), (e, n // 3, "%s %d" % (e, n // 3)),
                 (e, 2 * n // 3, "%s %d" % (e, 2 * n // 3)), (e, n, "%s %d" % (e, n)), (b, 0, "%s 0" % b)]
        for v in variants:
            spec.append((v, os.path.join(N.MODEL_DIR, "astronaut_%s.glb" % v), label, steps))
    out.append(transitions_sheet(spec, "transitions  s = suit  i = indoor"))
    return out
