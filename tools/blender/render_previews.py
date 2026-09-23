"""
Frontier Habitat - preview renderer (Blender 5.2).

It imports the EXPORTED files (assets/models/<id>.glb), not the builder scene. So a preview shows
what the game receives: object names, materials, normals, culling and origins.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/render_previews.py -- [--only id1,id2] [--size 512] [--no-sheet] [--overview]

Output (tools/blender/previews/):
  <id>.png                  3/4 view from above, sun light, neutral background, footprint circle on the ground
  <id>__open.png            rooms only: the same view with the `Roof` object hidden (shows `Interior`)
  _contact_sheet.png        all models, id under each
  _contact_sheet_open.png   all rooms without the roof
  _overview.png             (--overview) all buildings on one field, seen from a high game-like camera
"""
import bpy
import os
import sys
import math
import warnings
from math import radians, sin, cos, tan, atan
from mathutils import Vector

warnings.filterwarnings("ignore", category=DeprecationWarning)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_assets as BA   # noqa: E402  (the model table is the single source of truth)
import numpy as np          # noqa: E402  (numpy ships with Blender)

MODEL_DIR = BA.OUT_DIR
PREVIEW_DIR = os.path.join(HERE, "previews")

CAM_AZIMUTH = -42.0      # degrees from +X toward -Y: the camera sees the front (+X) and the -Y side
CAM_ELEVATION = 40.0
FOCAL = 70.0
SUN_DIR = (0.12, -0.72, 0.68)   # direction TO the sun: lights the -Y side, a little of the front, shadows fall to the right


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


def setup_scene(size, ground_rgb=(0.42, 0.42, 0.42), world_rgb=(0.55, 0.56, 0.58)):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = size
    sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    try:
        sc.eevee.taa_render_samples = 32
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
    sun_data.energy = 3.2
    sun_data.angle = radians(2.0)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = Vector(SUN_DIR).to_track_quat("Z", "Y").to_euler()
    sc.collection.objects.link(sun)
    # ground
    mesh = bpy.data.meshes.new("Ground")
    g = 400.0
    mesh.from_pydata([(-g, -g, -0.003), (g, -g, -0.003), (g, g, -0.003), (-g, g, -0.003)], [], [(0, 1, 2, 3)])
    mesh.materials.append(flat_material("GroundMat", ground_rgb))
    ground = bpy.data.objects.new("Ground", mesh)
    sc.collection.objects.link(ground)
    return sc


def add_ring(radius, z=0.006, width=0.05, rgb=(0.05, 0.05, 0.05), seg=96):
    verts, faces = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        verts.append(((radius - width) * cos(a), (radius - width) * sin(a), z))
        verts.append(((radius + width) * cos(a), (radius + width) * sin(a), z))
    for i in range(seg):
        j = (i + 1) % seg
        faces.append((2 * i, 2 * i + 1, 2 * j + 1, 2 * j))
    mesh = bpy.data.meshes.new("FootprintRing")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(flat_material("RingMat", rgb))
    ob = bpy.data.objects.new("FootprintRing", mesh)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def world_bbox(objs):
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        pts.extend(o.matrix_world @ Vector(c) for c in o.bound_box)
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def world_points(objs, limit=6000):
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        step = max(1, len(o.data.vertices) // limit)
        mw = o.matrix_world
        pts.extend(mw @ v.co for v in list(o.data.vertices)[::step])
    return pts


def place_camera(lo, hi, azimuth=CAM_AZIMUTH, elevation=CAM_ELEVATION, focal=FOCAL, margin=1.06, points=None):
    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = focal
    cam_data.sensor_width = 36.0
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.clip_start = 0.1
    cam_data.clip_end = 2000.0
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
    # centre the projected box, then choose the distance so every corner is inside the frame
    dist = (hi - lo).length * 2.0 + 1.0
    for _ in range(6):
        pos = target + d * dist
        loc = [rot.inverted() @ (c - pos) for c in corners]
        xs = [p.x / -p.z for p in loc]
        ys = [p.y / -p.z for p in loc]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        target = target + (rot @ Vector((cx, cy, 0.0))) * dist
        need = max(max(xs) - min(xs), max(ys) - min(ys)) / 2 * margin
        dist = dist * need / tan(half)
    cam.location = target + d * dist
    return cam


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_model(spec, size):
    path = os.path.join(MODEL_DIR, spec["id"] + ".glb")
    if not os.path.exists(path):
        print("MISSING", path)
        return []
    setup_scene(size)
    objs = import_glb(path)
    if spec["id"] == "crop":
        # PREVIEW ONLY: in the file the three stages share the origin. Here they sit side by side on a soil strip.
        for o in objs:
            if o.name.startswith("Stage"):
                o.location.y += (2 - int(o.name[-1])) * 1.45
        soil = bpy.data.meshes.new("SoilStrip")
        soil.from_pydata([(-1.5, -2.2, 0.0), (1.5, -2.2, 0.0), (1.5, 2.2, 0.0), (-1.5, 2.2, 0.0)], [], [(0, 1, 2, 3)])
        soil.materials.append(flat_material("SoilMat", (0.10, 0.05, 0.03)))
        bpy.context.scene.collection.objects.link(bpy.data.objects.new("SoilStrip", soil))
    bpy.context.view_layer.update()
    lo, hi = world_bbox(objs)
    pts = world_points(objs)
    if spec["footprint"]:
        add_ring(spec["footprint"])
        pts += [Vector((spec["footprint"] * cos(radians(a)), spec["footprint"] * sin(radians(a)), 0.0)) for a in range(0, 360, 15)]
    place_camera(lo, hi, azimuth=CAM_AZIMUTH, elevation=CAM_ELEVATION, points=pts)
    out = [os.path.join(PREVIEW_DIR, spec["id"] + ".png")]
    render_to(out[0])
    if spec["kind"] == "room":
        for o in objs:
            if o.name == "Roof":
                o.hide_render = True
        out.append(os.path.join(PREVIEW_DIR, spec["id"] + "__open.png"))
        render_to(out[1])
    print("rendered", spec["id"], [o.name for o in objs if o.type == "MESH"])
    return out


# --------------------------------------------------------------------------------------
# overview: every building on one orange field, high camera (what the player sees)
# --------------------------------------------------------------------------------------
def render_overview(size=1600):
    sc = setup_scene(size, ground_rgb=(0.52, 0.27, 0.12), world_rgb=(0.62, 0.55, 0.50))
    sc.render.resolution_x = size
    sc.render.resolution_y = int(size * 0.62)
    specs = [m for m in BA.MODELS if m["footprint"]]
    cols = 7
    pitch = 14.0
    lo = Vector((1e9, 1e9, 0))
    hi = Vector((-1e9, -1e9, 0))
    for k, spec in enumerate(specs):
        path = os.path.join(MODEL_DIR, spec["id"] + ".glb")
        if not os.path.exists(path):
            continue
        cx = (k % cols) * pitch
        cy = -(k // cols) * pitch * 1.15
        for o in import_glb(path):
            o.location = o.location + Vector((cx, cy, 0))
        lo.x, lo.y = min(lo.x, cx - 7), min(lo.y, cy - 7)
        hi.x, hi.y = max(hi.x, cx + 7), max(hi.y, cy + 7)
    hi.z = 6.0
    place_camera(lo, hi, azimuth=-90.0, elevation=58.0, focal=50.0, margin=1.02)
    sc.camera.data.sensor_fit = "HORIZONTAL"
    render_to(os.path.join(PREVIEW_DIR, "_overview.png"))


# --------------------------------------------------------------------------------------
# contact sheet (numpy + a tiny bitmap font, no extra packages)
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
}


def draw_text(img, text, x, y, scale=2, color=(0.08, 0.08, 0.08)):
    """img: H x W x 3 array with row 0 at the TOP."""
    for ch in text.lower():
        rows = FONT.get(ch, FONT[" "]).split("|")
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == "#":
                    y0, x0 = y + ry * scale, x + rx * scale
                    img[y0:y0 + scale, x0:x0 + scale, :] = color
        x += 6 * scale


def load_png(path):
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    arr = np.empty(w * h * 4, dtype=np.float32)
    im.pixels.foreach_get(arr)
    bpy.data.images.remove(im)
    return arr.reshape(h, w, 4)[::-1, :, :3].copy()          # row 0 at the top


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


def contact_sheet(items, out_path, cols=7, thumb=256, label_h=30):
    """items: [(label, png path)]"""
    items = [(lab, p) for lab, p in items if os.path.exists(p)]
    if not items:
        return
    rows = (len(items) + cols - 1) // cols
    pad = 6
    W = cols * (thumb + pad) + pad
    H = rows * (thumb + label_h + pad) + pad
    sheet = np.full((H, W, 3), 0.93, dtype=np.float32)
    for k, (label, path) in enumerate(items):
        img = load_png(path)
        f = max(1, img.shape[0] // thumb)
        hh, ww = (img.shape[0] // f) * f, (img.shape[1] // f) * f
        small = img[:hh, :ww].reshape(hh // f, f, ww // f, f, 3).mean(axis=(1, 3))[:thumb, :thumb]
        x0 = pad + (k % cols) * (thumb + pad)
        y0 = pad + (k // cols) * (thumb + label_h + pad)
        sheet[y0:y0 + small.shape[0], x0:x0 + small.shape[1]] = small
        scale = 2
        tw = len(label) * 6 * scale
        draw_text(sheet, label, x0 + max(0, (thumb - tw) // 2), y0 + thumb + 8, scale=scale)
    save_png(sheet, out_path)
    print("contact sheet:", out_path)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    global PREVIEW_DIR, CAM_AZIMUTH, CAM_ELEVATION
    only = None
    size = 512
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    if "--size" in argv:
        size = int(argv[argv.index("--size") + 1])
    if "--azimuth" in argv:          # checks from other sides, e.g. --azimuth 138 --outdir <scratch folder>
        CAM_AZIMUTH = float(argv[argv.index("--azimuth") + 1])
    if "--elevation" in argv:
        CAM_ELEVATION = float(argv[argv.index("--elevation") + 1])
    if "--outdir" in argv:
        PREVIEW_DIR = os.path.abspath(argv[argv.index("--outdir") + 1])
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for spec in BA.MODELS:
        if only and spec["id"] not in only:
            continue
        render_model(spec, size)
    if "--overview" in argv:
        render_overview()
    if "--no-sheet" not in argv:
        contact_sheet([(m["id"], os.path.join(PREVIEW_DIR, m["id"] + ".png")) for m in BA.MODELS],
                      os.path.join(PREVIEW_DIR, "_contact_sheet.png"))
        contact_sheet([(m["id"] + " (open)", os.path.join(PREVIEW_DIR, m["id"] + "__open.png"))
                       for m in BA.MODELS if m["kind"] == "room"],
                      os.path.join(PREVIEW_DIR, "_contact_sheet_open.png"), cols=5)


if __name__ == "__main__":
    main()
