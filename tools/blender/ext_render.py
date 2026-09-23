"""
Frontier Habitat 2.0 - ART-B renderer: build-menu thumbnails and check renders.

It imports the EXPORTED files (assets/models/*.glb), so a render shows what the game receives. The COLOR_0
ambient occlusion is multiplied into Base Color, as the game loader does.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_render.py -- --thumbs all            # every ART-B thumbnail
      --python tools/blender/ext_render.py -- --thumbs solar_array,meridian
      --python tools/blender/ext_render.py -- --sheets all            # check renders in tools/blender/previews_ext/

Thumbnail camera and light (shared with ART-A, docs/requests/ART-B-to-ART-A.md): EEVEE, 256 x 256, transparent,
lens 70 mm, azimuth -42 deg, elevation 40 deg, sun toward (0.12, -0.72, 0.68) strength 3.2, world 0.55 grey.
"""
import bpy
import os
import sys
import math
import json
from math import radians, sin, cos, tan, atan
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C      # noqa: E402
import numpy as np          # noqa: E402

MODEL_DIR = C.MODEL_DIR
THUMB_DIR = C.THUMB_DIR
PREVIEW_DIR = C.PREVIEW_DIR

CAM_AZIMUTH = -42.0
CAM_ELEVATION = 40.0
FOCAL = 70.0
SUN_DIR = (0.12, -0.72, 0.68)
SUN_ENERGY = 3.2
WORLD_RGB = (0.55, 0.56, 0.58)
LEVELS = ("L2", "L3", "L4", "L5")


# --------------------------------------------------------------------------------------
# scene
# --------------------------------------------------------------------------------------
def flat_material(name, rgb, rough=0.9):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


def setup_scene(size_x, size_y=None, transparent=True, world_rgb=WORLD_RGB, samples=64, ground=None,
                sun_energy=SUN_ENERGY, sun_dir=SUN_DIR):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = size_x
    sc.render.resolution_y = size_y or size_x
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:
        pass
    try:
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "None"
    except Exception as exc:
        print("view transform:", exc)
    world = bpy.data.worlds.new("PreviewWorld")
    if world.node_tree is None:
        world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.bl_idname == "ShaderNodeBackground"), None)
    if bg is None:
        bg = world.node_tree.nodes.new("ShaderNodeBackground")
        out = world.node_tree.nodes.new("ShaderNodeOutputWorld")
        world.node_tree.links.new(bg.outputs["Background"], out.inputs["Surface"])
    bg.inputs["Color"].default_value = (*world_rgb, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = world
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = sun_energy
    sun_data.angle = radians(2.0)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = Vector(sun_dir).to_track_quat("Z", "Y").to_euler()
    sc.collection.objects.link(sun)
    if ground is not None:
        mesh = bpy.data.meshes.new("Ground")
        g = 600.0
        mesh.from_pydata([(-g, -g, -0.003), (g, -g, -0.003), (g, g, -0.003), (-g, g, -0.003)], [], [(0, 1, 2, 3)])
        mesh.materials.append(flat_material("GroundMat", ground))
        sc.collection.objects.link(bpy.data.objects.new("Ground", mesh))
    return sc


def add_ring(radius, z=0.006, width=0.05, rgb=(0.05, 0.05, 0.05), seg=96, center=(0, 0)):
    verts, faces = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        verts.append((center[0] + (radius - width) * cos(a), center[1] + (radius - width) * sin(a), z))
        verts.append((center[0] + (radius + width) * cos(a), center[1] + (radius + width) * sin(a), z))
    for i in range(seg):
        j = (i + 1) % seg
        faces.append((2 * i, 2 * i + 1, 2 * j + 1, 2 * j))
    mesh = bpy.data.meshes.new("FootprintRing")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(flat_material("RingMat", rgb))
    ob = bpy.data.objects.new("FootprintRing", mesh)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def ao_materials():
    """Multiply the first colour attribute of every mesh into Base Color (what the game loader does)."""
    done = set()
    for ob in bpy.data.objects:
        if ob.type != "MESH" or not ob.data.color_attributes:
            continue
        layer = ob.data.color_attributes[0].name
        for slot in ob.material_slots:
            m = slot.material
            if m is None or m.name in done or m.node_tree is None:
                continue
            done.add(m.name)
            nt = m.node_tree
            bsdf = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
            if bsdf is None or any(n.bl_idname == "ShaderNodeVertexColor" for n in nt.nodes):
                continue                      # the glTF importer already multiplies COLOR_0 (checked by ART-A)
            inp = bsdf.inputs["Base Color"]
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = layer
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0
            a_in = mix.inputs[6]
            b_in = mix.inputs[7]
            if inp.is_linked:
                src = inp.links[0].from_socket
                nt.links.new(src, a_in)
            else:
                a_in.default_value = inp.default_value[:]
            nt.links.new(vc.outputs["Color"], b_in)
            nt.links.new(mix.outputs[2], inp)


def import_glb(path, offset=(0, 0, 0), hide=(), only=None, rot_z=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    for o in objs:
        if o.parent is None:
            if rot_z:
                o.location = Vector(o.location).copy()
                o.rotation_euler.z += radians(rot_z)
                x, y = o.location.x, o.location.y
                c, s = cos(radians(rot_z)), sin(radians(rot_z))
                o.location.x, o.location.y = c * x - s * y, s * x + c * y
            o.location = o.location + Vector(offset)
    for o in objs:
        name = o.name.split(".")[0]
        if name in hide or (only is not None and o.type == "MESH" and name not in only):
            o.hide_render = True
            o.hide_viewport = True
    return objs


def visible_meshes(objs):
    return [o for o in objs if o.type == "MESH" and not o.hide_render]


def world_bbox(objs):
    pts = []
    for o in visible_meshes(objs):
        pts.extend(o.matrix_world @ Vector(c) for c in o.bound_box)
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def world_points(objs, limit=4000):
    pts = []
    for o in visible_meshes(objs):
        step = max(1, len(o.data.vertices) // limit)
        mw = o.matrix_world
        pts.extend(mw @ v.co for v in list(o.data.vertices)[::step])
    return pts


def place_camera(lo, hi, azimuth=CAM_AZIMUTH, elevation=CAM_ELEVATION, focal=FOCAL, margin=1.08, points=None,
                 aspect=1.0, ortho=False):
    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = focal
    cam_data.sensor_width = 36.0
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.clip_start = 0.1
    cam_data.clip_end = 5000.0
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    az, el = radians(azimuth), radians(elevation)
    d = Vector((cos(el) * cos(az), cos(el) * sin(az), sin(el)))
    target = (lo + hi) / 2
    quat = d.to_track_quat("Z", "Y")
    cam.rotation_euler = quat.to_euler()
    rot = quat.to_matrix()
    half = atan(18.0 / focal)
    corners = points or [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    dist = (hi - lo).length * 2.0 + 1.0
    for _ in range(8):
        pos = target + d * dist
        loc = [rot.inverted() @ (c - pos) for c in corners]
        xs = [p.x / -p.z for p in loc]
        ys = [p.y / -p.z for p in loc]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        target = target + (rot @ Vector((cx, cy, 0.0))) * dist
        need = max((max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2 * aspect) * margin
        dist = dist * need / tan(half)
    cam.location = target + d * dist
    return cam


def render_to(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# --------------------------------------------------------------------------------------
# thumbnails
# --------------------------------------------------------------------------------------
def render_thumb(glb_name, out_name=None, only=None, hide=LEVELS, size=256):
    path = os.path.join(MODEL_DIR, glb_name + ".glb")
    if not os.path.exists(path):
        print("MISSING", path)
        return None
    setup_scene(size, transparent=True)
    objs = import_glb(path, hide=hide, only=only)
    ao_materials()
    bpy.context.view_layer.update()
    lo, hi = world_bbox(objs)
    place_camera(lo, hi, points=world_points(objs), margin=1.08)
    out = os.path.join(THUMB_DIR, (out_name or glb_name) + ".png")
    render_to(out)
    return out


# --------------------------------------------------------------------------------------
# check renders: several files (or several copies of one file) side by side
# --------------------------------------------------------------------------------------
def render_arrangement(items, out, size=(1024, 640), azimuth=CAM_AZIMUTH, elevation=CAM_ELEVATION, ground=(0.52, 0.30, 0.17),
                       rings=True, focal=FOCAL, margin=1.05, world=(0.62, 0.58, 0.55), transparent=False):
    """items: list of dict(file, offset=(x,y,0), hide=(), only=None, ring=radius or None, rot=deg)."""
    setup_scene(size[0], size[1], transparent=transparent, world_rgb=world, ground=ground)
    allobjs = []
    for it in items:
        path = os.path.join(MODEL_DIR, it["file"] + ".glb")
        if not os.path.exists(path):
            print("MISSING", path)
            continue
        objs = import_glb(path, offset=it.get("offset", (0, 0, 0)), hide=it.get("hide", ()), only=it.get("only"),
                          rot_z=it.get("rot", 0.0))
        allobjs.extend(objs)
        if rings and it.get("ring"):
            off = it.get("offset", (0, 0, 0))
            add_ring(it["ring"], center=(off[0], off[1]))
    ao_materials()
    bpy.context.view_layer.update()
    lo, hi = world_bbox(allobjs)
    pts = world_points(allobjs)
    for it in items:
        if it.get("ring"):
            off = it.get("offset", (0, 0, 0))
            pts += [Vector((off[0] + it["ring"] * cos(radians(a)), off[1] + it["ring"] * sin(radians(a)), 0.0))
                    for a in range(0, 360, 20)]
    place_camera(lo, hi, azimuth=azimuth, elevation=elevation, points=pts, focal=focal, margin=margin,
                 aspect=size[0] / size[1])
    render_to(out)
    return out


# --------------------------------------------------------------------------------------
# contact sheet (numpy + a tiny bitmap font)
# --------------------------------------------------------------------------------------
FONT = {
    "a": ".....|.....|.###.|....#|.####|#...#|.####", "b": "#....|#....|#.##.|##..#|#...#|#...#|####.",
    "c": ".....|.....|.###.|#....|#....|#...#|.###.", "d": "....#|....#|.##.#|#..##|#...#|#...#|.####",
    "e": ".....|.....|.###.|#...#|#####|#....|.###.", "f": "..##.|.#..#|.#...|###..|.#...|.#...|.#...",
    "g": ".....|.....|.####|#...#|#...#|#...#|.####|....#|.###.", "h": "#....|#....|#.##.|##..#|#...#|#...#|#...#",
    "i": "..#..|.....|.##..|..#..|..#..|..#..|.###.", "j": "...#.|.....|..##.|...#.|...#.|...#.|...#.|#..#.|.##..",
    "k": "#....|#....|#..#.|#.#..|##...|#.#..|#..#.", "l": ".##..|..#..|..#..|..#..|..#..|..#..|.###.",
    "m": ".....|.....|##.#.|#.#.#|#.#.#|#...#|#...#", "n": ".....|.....|#.##.|##..#|#...#|#...#|#...#",
    "o": ".....|.....|.###.|#...#|#...#|#...#|.###.", "p": ".....|.....|####.|#...#|#...#|#...#|####.|#....|#....",
    "q": ".....|.....|.####|#...#|#...#|#...#|.####|....#|....#", "r": ".....|.....|#.##.|##..#|#....|#....|#....",
    "s": ".....|.....|.####|#....|.###.|....#|####.", "t": ".#...|.#...|###..|.#...|.#...|.#..#|..##.",
    "u": ".....|.....|#...#|#...#|#...#|#..##|.##.#", "v": ".....|.....|#...#|#...#|#...#|.#.#.|..#..",
    "w": ".....|.....|#...#|#...#|#.#.#|#.#.#|.#.#.", "x": ".....|.....|#...#|.#.#.|..#..|.#.#.|#...#",
    "y": ".....|.....|#...#|#...#|#...#|#...#|.####|....#|.###.", "z": ".....|.....|#####|...#.|..#..|.#...|#####",
    "0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.", "1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
    "2": ".###.|#...#|....#|...#.|..#..|.#...|#####", "3": "#####|...#.|..#..|...#.|....#|#...#|.###.",
    "4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.", "5": "#####|#....|####.|....#|....#|#...#|.###.",
    "6": "..##.|.#...|#....|####.|#...#|#...#|.###.", "7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
    "8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.", "9": ".###.|#...#|#...#|.####|....#|...#.|.##..",
    "_": ".....|.....|.....|.....|.....|.....|#####", "-": ".....|.....|.....|#####|.....|.....|.....",
    ".": ".....|.....|.....|.....|.....|.##..|.##..", " ": ".....|.....|.....|.....|.....|.....|.....",
    "(": "...#.|..#..|.#...|.#...|.#...|..#..|...#.", ")": ".#...|..#..|...#.|...#.|...#.|..#..|.#...",
    "+": ".....|..#..|..#..|#####|..#..|..#..|.....", "/": "....#|...#.|...#.|..#..|.#...|.#...|#....",
}


def draw_text(img, text, x, y, scale=2, color=(0.08, 0.08, 0.08)):
    for ch in text.lower():
        rows = FONT.get(ch, FONT[" "]).split("|")
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == "#":
                    y0, x0 = y + ry * scale, x + rx * scale
                    img[y0:y0 + scale, x0:x0 + scale, :3] = color
        x += 6 * scale


def load_png(path, bg=(0.80, 0.80, 0.80)):
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    arr = np.empty(w * h * 4, dtype=np.float32)
    im.pixels.foreach_get(arr)
    bpy.data.images.remove(im)
    a = arr.reshape(h, w, 4)[::-1, :, :].copy()
    rgb = a[:, :, :3] * a[:, :, 3:4] + np.array(bg, dtype=np.float32) * (1.0 - a[:, :, 3:4])
    return rgb


def save_png(arr, path):
    h, w, _ = arr.shape
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[:, :, :3] = np.clip(arr, 0.0, 1.0)
    im = bpy.data.images.new("sheet", w, h, alpha=False)
    im.pixels.foreach_set(rgba[::-1].ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def contact_sheet(items, out_path, cols=6, thumb=256, label_h=30, bg=(0.80, 0.80, 0.80), tile=None):
    """items: [(label, png path)]. tile = (w, h) for non-square images (nearest-neighbour resize)."""
    items = [(lab, p) for lab, p in items if p and os.path.exists(p)]
    if not items:
        return None
    tw_, th_ = tile if tile else (thumb, thumb)
    rows = (len(items) + cols - 1) // cols
    pad = 6
    W = cols * (tw_ + pad) + pad
    H = rows * (th_ + label_h + pad) + pad
    sheet = np.full((H, W, 3), 0.93, dtype=np.float32)
    for k, (label, path) in enumerate(items):
        img = load_png(path, bg=bg)
        if img.shape[0] != th_ or img.shape[1] != tw_:
            ys = (np.arange(th_) * img.shape[0] / th_).astype(int)
            xs = (np.arange(tw_) * img.shape[1] / tw_).astype(int)
            img = img[ys][:, xs]
        x0 = pad + (k % cols) * (tw_ + pad)
        y0 = pad + (k // cols) * (th_ + label_h + pad)
        sheet[y0:y0 + th_, x0:x0 + tw_] = img
        scale = 2
        tw = len(label) * 6 * scale
        draw_text(sheet, label, x0 + max(0, (tw_ - tw) // 2), y0 + th_ + 8, scale=scale)
    save_png(sheet, out_path)
    print("contact sheet:", out_path)
    return out_path


def views_sheet(name, jobs, cols=2, tile=(800, 460)):
    """jobs: [(label, items, azimuth, elevation)] -> one sheet tools/blender/previews_ext/<name>.png"""
    outs = []
    for k, (label, items, az, el) in enumerate(jobs):
        out = os.path.join(PREVIEW_DIR, "_tmp_%s_%d.png" % (name, k))
        render_arrangement(items, out, size=tile, azimuth=az, elevation=el)
        outs.append((label, out))
    sheet = contact_sheet(outs, os.path.join(PREVIEW_DIR, name + ".png"), cols=cols, tile=tile)
    for _, o in outs:
        try:
            os.remove(o)
        except OSError:
            pass
    return sheet


# --------------------------------------------------------------------------------------
# what ART-B renders
# --------------------------------------------------------------------------------------
SIZED = ["solar_array", "wind_turbine", "battery", "water_extractor", "reservoir", "regolith_harvester", "fuel_refinery"]
SINGLES = ["fusion_reactor", "deep_drill", "comms_tower", "lander", "landing_pad", "meridian"]
CROPS = ["potato", "wheat", "greens", "tomato", "soybean", "herbs", "mushroom", "algae"]
SIZE_KEYS = ["s", "m", "l", "xl"]


def thumb_jobs():
    jobs = []
    for sid in SIZED:
        for s in SIZE_KEYS:
            jobs.append(("%s_%s" % (sid, s), "%s_%s" % (sid, s), None))
    for sid in SINGLES:
        jobs.append((sid, sid, None))
    jobs.append(("meridian", "meridian_wreck", None))
    for c in CROPS:
        jobs.append(("crop_" + c, "crop_" + c, ["Stage3"]))
    return jobs


def do_thumbs(which):
    made = []
    for glb, out, only in thumb_jobs():
        base = glb.rsplit("_", 1)[0] if glb.split("_")[-1] in SIZE_KEYS else glb
        if which != ["all"] and glb not in which and base not in which and out not in which:
            continue
        hide = LEVELS
        if out == "meridian":
            hide = ("Damage1", "Damage2", "Damage3", "Scaffold")
        elif out == "meridian_wreck":
            hide = ("Scaffold", "Lights", "EngineGlow")
        p = render_thumb(glb, out, only=only, hide=hide)
        if p:
            made.append((out, p))
    if made:
        contact_sheet(made, os.path.join(PREVIEW_DIR, "_thumbs_sheet.png"), cols=8, thumb=256)
    return made


def footprint_of(sid, size_index=None):
    b = C.load_content("buildings.json")[sid]
    if size_index is not None and "sizes" in b and "radius" in b["sizes"]:
        return b["sizes"]["radius"][size_index]
    return b.get("radius")


def lineup_items(sid, levels_on):
    radii = [footprint_of(sid, k) for k in range(4)]
    items = []
    x = 0.0
    for k, sz in enumerate(SIZE_KEYS):
        x += radii[k] + (1.2 if k else 0.0)
        items.append(dict(file="%s_%s" % (sid, sz), offset=(x, 0, 0), hide=() if levels_on else LEVELS, ring=radii[k]))
        x += radii[k]
    return items


def sheet_lineup(sid):
    """S, M, L, XL side by side: level parts off, then all level parts on; and M at L1 .. L5"""
    r = footprint_of(sid, 1)
    lv = []
    x = 0.0
    for L in range(1, 6):
        hide = tuple("L%d" % q for q in range(L + 1, 6))
        lv.append(dict(file=sid + "_m", offset=(x, 0, 0), hide=hide, ring=r))
        x += 2 * r + 1.5
    jobs = [("%s  s m l xl  (level 1)" % sid, lineup_items(sid, False), -62, 32),
            ("%s  s m l xl  (all level parts)" % sid, lineup_items(sid, True), -62, 32),
            ("%s  m  level 1 2 3 4 5" % sid, lv, -70, 30)]
    return views_sheet(sid + "__sheet", jobs, cols=1, tile=(1400, 560))


def sheet_levels(file, radius):
    """One model at L1 .. L5 side by side."""
    items = []
    x = 0.0
    for lv in range(1, 6):
        hide = tuple("L%d" % k for k in range(lv + 1, 6))
        items.append(dict(file=file, offset=(x, 0, 0), hide=hide, ring=radius))
        x += 2 * radius + 1.5
    return render_arrangement(items, os.path.join(PREVIEW_DIR, file + "__levels.png"), size=(1600, 560), azimuth=-70, elevation=30)


def sheet_single(file, radius=None, name=None, azimuth=CAM_AZIMUTH, elevation=CAM_ELEVATION, hide=(), size=(900, 700),
                 only=None, ground=(0.52, 0.30, 0.17)):
    items = [dict(file=file, ring=radius, hide=hide, only=only)]
    return render_arrangement(items, os.path.join(PREVIEW_DIR, (name or file) + ".png"), size=size, azimuth=azimuth,
                              elevation=elevation, ground=ground)


def sheet_meridian():
    D = ("Damage1", "Damage2", "Damage3")
    F = [("wreck (stage 0)", ("Scaffold", "Lights", "EngineGlow")),
         ("stage 1: scaffold", ("Lights", "EngineGlow")),
         ("hull done: no damage1", ("Damage1", "Lights", "EngineGlow")),
         ("systems done: lights on", ("Damage1", "Damage2")),
         ("intact (all damage off)", D + ("Scaffold",)),
         ("only damage3 (engines)", ("Damage1", "Damage2", "Scaffold", "Lights", "EngineGlow"))]
    jobs = [(lab, [dict(file="meridian", hide=h)], -38, 30) for lab, h in F]
    jobs.append(("rear, intact", [dict(file="meridian", hide=D + ("Scaffold",))], 150, 22))
    jobs.append(("top, everything", [dict(file="meridian")], -90, 72))
    a = views_sheet("meridian__states", jobs, cols=2)
    b = sheet_row(["debris_a", "debris_b", "debris_c"], "debris__row.png", 5.0)
    return [a, b]


def sheet_singles():
    def lv_row(sid, r):
        items, x = [], 0.0
        for L in (1, 3, 5):
            hide = tuple("L%d" % q for q in range(L + 1, 6))
            items.append(dict(file=sid, offset=(x, 0, 0), hide=hide, ring=r))
            x += 2 * r + 1.5
        return items
    jobs = [("fusion_reactor  level 1 3 5", lv_row("fusion_reactor", 6.5), -62, 34),
            ("deep_drill  level 1 3 5", lv_row("deep_drill", 3.5), -62, 26),
            ("comms_tower", [dict(file="comms_tower", ring=2.5)], -42, 28),
            ("lander", [dict(file="lander", ring=5.5)], -42, 34),
            ("landing_pad", [dict(file="landing_pad", ring=9.0)], -42, 40),
            ("fusion_reactor close", [dict(file="fusion_reactor", hide=LEVELS, ring=6.5)], -42, 40)]
    return views_sheet("singles__sheet", jobs, cols=2, tile=(900, 560))


def sheet_crops():
    jobs = []
    for c in CROPS:
        items = [dict(file="crop_" + c, offset=(0, (1 - k) * 1.6, 0), only=["Stage%d" % (k + 1)]) for k in range(3)]
        jobs.append(("%s  stage 3 2 1 (front to back)" % c, items, -35, 38))
    return [views_sheet("crops__stages", jobs, cols=2, tile=(760, 470))]


def sheet_row(files, out, spacing, size=(1400, 600), azimuth=-50, elevation=25, ground=(0.52, 0.30, 0.17), focal=FOCAL):
    items = [dict(file=f, offset=(k * spacing, 0, 0)) for k, f in enumerate(files)]
    return render_arrangement(items, os.path.join(PREVIEW_DIR, out), size=size, azimuth=azimuth, elevation=elevation,
                              ground=ground, rings=False, focal=focal)


def do_sheets(which):
    made = []
    want = lambda k: which == ["all"] or k in which   # noqa: E731
    if want("meridian"):
        made += sheet_meridian()
    if want("colonists"):
        made.append(sheet_row(["colonist_suit", "colonist_indoor", "colonist_suit", "colonist_indoor"], "colonists__row.png", 1.2,
                              size=(1000, 700), azimuth=-30, elevation=12, focal=85))
        made.append(sheet_row(["colonist_suit", "colonist_indoor"], "colonists__far.png", 1.4,
                              size=(400, 300), azimuth=-42, elevation=45, focal=20))
    if want("crops"):
        made += sheet_crops()
    for sid in SIZED:
        if want(sid):
            made.append(sheet_lineup(sid))
    if want("singles"):
        made.append(sheet_singles())
    if want("props"):
        crates = [dict(file=f, offset=(k * 0.75, 0, 0)) for k, f in
                  enumerate(["crate_raw", "crate_material", "crate_component", "crate_food", "crate_medical"])]
        rocks = [dict(file=f, offset=((k % 4) * 4.4, -(k // 4) * 4.0, 0)) for k, f in
                 enumerate(["rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "rock_f", "pebbles"])]
        jobs = [("supply_pod", [dict(file="supply_pod")], -42, 30), ("crates raw material component food medical", crates, -40, 32),
                ("rocks a b c d / e f pebbles", rocks, -40, 34),
                ("debris a b c", [dict(file=f, offset=(k * 5.0, 0, 0)) for k, f in enumerate(["debris_a", "debris_b", "debris_c"])],
                 -42, 30)]
        made.append(views_sheet("props__sheet", jobs, cols=2, tile=(900, 520)))
    return made


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    os.makedirs(THUMB_DIR, exist_ok=True)
    if "--thumbs" in argv:
        which = [s.strip() for s in argv[argv.index("--thumbs") + 1].split(",") if s.strip()]
        do_thumbs(which)
    if "--sheets" in argv:
        which = [s.strip() for s in argv[argv.index("--sheets") + 1].split(",") if s.strip()]
        do_sheets(which)
    if "--view" in argv:          # --view file[,azimuth,elevation,hide1+hide2]
        spec = argv[argv.index("--view") + 1].split(",")
        f = spec[0]
        az = float(spec[1]) if len(spec) > 1 else CAM_AZIMUTH
        el = float(spec[2]) if len(spec) > 2 else CAM_ELEVATION
        hide = tuple(spec[3].split("+")) if len(spec) > 3 and spec[3] else ()
        tag = spec[4] if len(spec) > 4 else "view"
        render_arrangement([dict(file=f, hide=hide)], os.path.join(PREVIEW_DIR, "%s__%s.png" % (f, tag)), size=(1200, 800),
                           azimuth=az, elevation=el)


if __name__ == "__main__":
    main()
