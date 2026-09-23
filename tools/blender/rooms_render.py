"""
Frontier Habitat 2.0 - ART-A renderer for the room buildings: build-menu thumbnails and review sheets.

It imports the EXPORTED files (assets/models/*.glb), so a picture shows what the game receives.  The glTF importer
multiplies COLOR_0 (the baked AO) into Base Color, as the game loader does; `ensure_ao` adds that multiply only
where the importer did not.

Thumbnails (shared with ART-B, docs/requests/ART-B-to-ART-A.md): EEVEE 64 samples, 256 x 256, transparent, view
transform Standard, lens 70 mm / sensor 36 mm, azimuth -42 deg from +X toward -Y, elevation 40 deg, framing = the
visible mesh vertices (L2..L5 hidden) with margin 1.08, sun toward (0.12, -0.72, 0.68) strength 3.2, world grey 0.55.

Run alone (after rooms_build.py):
  blender --background --factory-startup --python tools/blender/rooms_render.py -- [--only habitat] [--thumbs] [--review]
"""
import bpy
import os
import sys
import math
from math import radians, sin, cos, tan, atan
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import rooms_kit as K        # noqa: E402
import numpy as np           # noqa: E402

CAM_AZIMUTH = -42.0
CAM_ELEVATION = 40.0
FOCAL = 70.0
SUN_DIR = (0.12, -0.72, 0.68)
SUN_ENERGY = 3.2
WORLD_RGB = (0.55, 0.56, 0.58)
GROUND = (0.52, 0.30, 0.17)


def flat_material(name, rgb, rough=0.9):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


def setup_scene(w, h=None, transparent=True, world_rgb=WORLD_RGB, samples=64, ground=None, sun_energy=SUN_ENERGY,
                sun_dir=SUN_DIR):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = w
    sc.render.resolution_y = h or w
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
    except Exception:
        pass
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


def ensure_ao():
    """The glTF importer already multiplies COLOR_0 into Base Color (Mix node fed by a Color Attribute node).
    Add the multiply only to a material that does not have it."""
    added = 0
    for m in bpy.data.materials:
        if not m.users or m.node_tree is None or m.name in ("GroundMat", "RingMat"):
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
        if bsdf is None:
            continue
        has_vc = any(n.bl_idname in ("ShaderNodeVertexColor", "ShaderNodeAttribute") for n in nt.nodes)
        if has_vc:
            continue
        inp = bsdf.inputs["Base Color"]
        vc = nt.nodes.new("ShaderNodeVertexColor")
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        if inp.is_linked:
            nt.links.new(inp.links[0].from_socket, mix.inputs[6])
        else:
            mix.inputs[6].default_value = inp.default_value[:]
        nt.links.new(vc.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], inp)
        added += 1
    return added


def import_glb(path, offset=(0, 0, 0), hide=()):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    for o in objs:
        o.location = o.location + Vector(offset)
        if o.name.split(".")[0] in hide:
            o.hide_render = True
            o.hide_viewport = True
    return objs


def visible_meshes(objs):
    return [o for o in objs if o.type == "MESH" and not o.hide_render]


def world_points(objs, limit=5000):
    pts = []
    for o in visible_meshes(objs):
        step = max(1, len(o.data.vertices) // limit)
        mw = o.matrix_world
        pts.extend(mw @ v.co for v in list(o.data.vertices)[::step])
    return pts


def place_camera(pts, azimuth=CAM_AZIMUTH, elevation=CAM_ELEVATION, focal=FOCAL, margin=1.08, aspect=1.0):
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
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    az, el = radians(azimuth), radians(elevation)
    d = Vector((cos(el) * cos(az), cos(el) * sin(az), sin(el)))
    target = (lo + hi) / 2
    quat = d.to_track_quat("Z", "Y")
    cam.rotation_euler = quat.to_euler()
    rot = quat.to_matrix()
    inv = rot.inverted()
    half = atan(18.0 / focal)
    dist = (hi - lo).length * 2.0 + 1.0
    for _ in range(8):
        pos = target + d * dist
        loc = [inv @ (c - pos) for c in pts]
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
    tmp = path[:-4] + ".tmp.png"
    bpy.context.scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    K._replace_retry(tmp, path)


# --------------------------------------------------------------------------------------
# thumbnails
# --------------------------------------------------------------------------------------
def render_thumb(file, out_names, size=256):
    path = os.path.join(K.MODEL_DIR, file + ".glb")
    setup_scene(size, transparent=True)
    objs = import_glb(path, hide=K.LEVELS)
    ensure_ao()
    bpy.context.view_layer.update()
    place_camera(world_points(objs), margin=1.08)
    first = os.path.join(K.THUMB_DIR, out_names[0] + ".png")
    render_to(first)
    for extra in out_names[1:]:
        K.copy_atomic(first, os.path.join(K.THUMB_DIR, extra + ".png"))
    return first


def thumbs(jobs):
    for j in jobs:
        names = [j["file"]] + list(j.get("also", []))
        render_thumb(j["file"], names)
        print("  thumb", names)


# --------------------------------------------------------------------------------------
# review renders
# --------------------------------------------------------------------------------------
def render_set(items, out, size=(1200, 640), azimuth=CAM_AZIMUTH, elevation=CAM_ELEVATION, margin=1.05,
               ground=GROUND, rings=True, focal=FOCAL):
    """items: [dict(file, offset, hide, R)] rendered together on an orange ground."""
    setup_scene(size[0], size[1], transparent=False, world_rgb=(0.62, 0.58, 0.55), samples=48, ground=ground)
    allo = []
    pts = []
    for it in items:
        path = os.path.join(K.MODEL_DIR, it["file"] + ".glb")
        if not os.path.exists(path):
            continue
        objs = import_glb(path, offset=it.get("offset", (0, 0, 0)), hide=it.get("hide", ()))
        allo += objs
        if rings and it.get("R"):
            ox, oy = it.get("offset", (0, 0, 0))[:2]
            add_ring(it["R"], center=(ox, oy))
            pts += [Vector((ox + it["R"] * cos(radians(a)), oy + it["R"] * sin(radians(a)), 0)) for a in range(0, 360, 30)]
    ensure_ao()
    bpy.context.view_layer.update()
    pts += world_points(allo)
    place_camera(pts, azimuth=azimuth, elevation=elevation, margin=margin, aspect=size[0] / size[1], focal=focal)
    render_to(out)
    return out


def add_ring(radius, z=0.006, width=0.04, rgb=(0.08, 0.06, 0.05), seg=96, center=(0, 0)):
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
    "/": "....#|...#.|...#.|..#..|.#...|.#...|#....", "+": ".....|..#..|..#..|#####|..#..|..#..|.....",
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


def load_png(path, bg=(0.86, 0.86, 0.86)):
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    arr = np.empty(w * h * 4, dtype=np.float32)
    im.pixels.foreach_get(arr)
    bpy.data.images.remove(im)
    a = arr.reshape(h, w, 4)[::-1].copy()
    rgb = a[:, :, :3] * a[:, :, 3:4] + np.array(bg, dtype=np.float32) * (1.0 - a[:, :, 3:4])
    return rgb


def save_png(arr, path):
    h, w, _ = arr.shape
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[:, :, :3] = np.clip(arr, 0.0, 1.0)
    im = bpy.data.images.new("sheet", w, h, alpha=False)
    im.pixels.foreach_set(rgba[::-1].ravel())
    tmp = path[:-4] + ".tmp.png"
    im.filepath_raw = tmp
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    K._replace_retry(tmp, path)


def compose(rows, out, pad=6, label_h=26, bg=(0.93, 0.93, 0.93)):
    """rows: [[(label, png path), ...], ...]; every image keeps its size."""
    imgs = [[(lab, load_png(p)) for lab, p in row if os.path.exists(p)] for row in rows]
    W = max(sum(im.shape[1] + pad for _, im in row) + pad for row in imgs if row)
    H = sum(max(im.shape[0] for _, im in row) + label_h + pad for row in imgs if row) + pad
    sheet = np.full((H, W, 3), bg, dtype=np.float32)
    y = pad
    for row in imgs:
        if not row:
            continue
        x = pad
        rh = max(im.shape[0] for _, im in row)
        for lab, im in row:
            sheet[y:y + im.shape[0], x:x + im.shape[1]] = im
            draw_text(sheet, lab, x + 4, y + im.shape[0] + 6, scale=2)
            x += im.shape[1] + pad
        y += rh + label_h + pad
    save_png(sheet, out)
    return out


def review(jobs):
    """Per type: sizes side by side (roof on), M open, M with L2..L5, XL with L2..L5; one sheet per type,
    and a thumbnail sheet per family."""
    os.makedirs(K.PREVIEW_DIR, exist_ok=True)
    tmpd = os.path.join(K.PREVIEW_DIR, "_parts")
    os.makedirs(tmpd, exist_ok=True)
    by_type = {}
    for j in jobs:
        by_type.setdefault(j["tid"], []).append(j)
    fam_rows = {}
    import rooms_build as RB0
    for tid, js in by_type.items():
        js = sorted(js, key=lambda j: j["size"])
        row = []
        if len(js) > 1:
            items, x = [], 0.0
            for k, j in enumerate(js):
                if k:
                    x += js[k - 1]["R"] + j["R"] + 1.5
                items.append(dict(file=j["file"], offset=(x, 0, 0), hide=K.LEVELS, R=j["R"]))
            row.append((tid, render_set(items, os.path.join(tmpd, tid + "_lineup.png"), size=(700, 250),
                                        elevation=32.0)))
        m = next((j for j in js if j["size"] == 1), js[0])
        big = js[-1]
        row.append(("m open", render_set([dict(file=m["file"], hide=("Roof",) + K.LEVELS, R=m["R"])],
                                          os.path.join(tmpd, tid + "_open.png"), size=(270, 250), elevation=50.0)))
        if not m.get("single"):
            row.append(("m l5", render_set([dict(file=m["file"], hide=(), R=m["R"])],
                                           os.path.join(tmpd, tid + "_l5.png"), size=(270, 250))))
        if big is not m:
            row.append(("xl l5 game side", render_set([dict(file=big["file"], hide=(), R=big["R"])],
                                                      os.path.join(tmpd, tid + "_xl_l5.png"), size=(270, 250),
                                                      azimuth=-125.0, elevation=48.0)))
        fam_rows.setdefault(RB0.FAMILY.get(tid, "other"), []).append(row)
        print("  review", tid)
    for f, rows in fam_rows.items():
        compose(rows, os.path.join(K.PREVIEW_DIR, "_review_%s.png" % f), label_h=22)
    if "--type-sheets" not in sys.argv:
        by_type = {}
    for tid, js in by_type.items():
        js = sorted(js, key=lambda j: j["size"])
        rows = []
        if len(js) > 1:
            items, x = [], 0.0
            for k, j in enumerate(js):
                if k:
                    x += js[k - 1]["R"] + j["R"] + 1.5
                items.append(dict(file=j["file"], offset=(x, 0, 0), hide=K.LEVELS, R=j["R"]))
            p1 = render_set(items, os.path.join(tmpd, tid + "_lineup.png"), size=(1140, 400), elevation=32.0)
            rows.append([("%s  s m l xl  roof on" % tid, p1)])
        m = next((j for j in js if j["size"] == 1), js[0])
        big = js[-1]
        p2 = render_set([dict(file=m["file"], hide=("Roof",) + K.LEVELS, R=m["R"])],
                        os.path.join(tmpd, tid + "_open.png"), size=(376, 320), elevation=50.0)
        row2 = [("%s open" % m["file"], p2)]
        if not m.get("single"):
            p3 = render_set([dict(file=m["file"], hide=(), R=m["R"])], os.path.join(tmpd, tid + "_l5.png"),
                            size=(376, 320))
            row2.append(("%s l5" % m["file"], p3))
        if big is not m:
            p4 = render_set([dict(file=big["file"], hide=(), R=big["R"])], os.path.join(tmpd, tid + "_xl_l5.png"),
                            size=(376, 320), azimuth=-125.0, elevation=48.0)
            row2.append(("%s l5 (game side)" % big["file"], p4))
        rows.append(row2)
        if big is not m and ("--open-xl" in sys.argv):
            p5 = render_set([dict(file=big["file"], hide=("Roof",) + K.LEVELS, R=big["R"])],
                            os.path.join(tmpd, tid + "_xl_open.png"), size=(560, 420), elevation=50.0)
            rows.append([("%s open" % big["file"], p5)])
        compose(rows, os.path.join(K.PREVIEW_DIR, tid + ".png"))
        print("  review sheet", tid)
    # family thumbnail sheets
    fam = {}
    import rooms_build as RB
    for j in jobs:
        fam.setdefault(RB.FAMILY.get(j["tid"], "other"), []).append(j)
    for f, js in fam.items():
        rows, row = [], []
        cur = None
        for j in sorted(js, key=lambda j: (RB.ORDER.index(j["tid"]), j["size"])):
            if cur is not None and j["tid"] != cur and row:
                rows.append(row)
                row = []
            cur = j["tid"]
            row.append((j["file"], os.path.join(K.THUMB_DIR, j["file"] + ".png")))
        if row:
            rows.append(row)
        compose(rows, os.path.join(K.PREVIEW_DIR, "_family_%s.png" % f))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    import rooms_build as RB
    only = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    sizes = None
    if "--sizes" in argv:
        sizes = [s.strip() for s in argv[argv.index("--sizes") + 1].split(",") if s.strip()]
    js = [j for j in RB.jobs(K.load_buildings(), only, sizes)
          if os.path.exists(os.path.join(K.MODEL_DIR, j["file"] + ".glb"))]
    if "--thumbs" in argv:
        thumbs(js)
    if "--review" in argv:
        review(js)


if __name__ == "__main__":
    main()
