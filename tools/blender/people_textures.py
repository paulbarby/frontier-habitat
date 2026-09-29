"""
Frontier Habitat 5.0 - ART-NPC: textures for the people.

  people_eyes.png           4 irises in a row (256 x 256 cells): sclera, iris fibres, limbal ring, pupil, catchlight.
  face_<variant>.png        1024 x 1024 multiplicative skin detail (white = the skin tone the game gives): brows, lash
                            lines, lid shading, lips, nostrils, cheek colour, stubble, fine noise.  The game tints Skin
                            by replacing the albedo, so the texture keeps its meaning on every skin tone.
The face texture is painted from the same feature definitions as the geometry (people_face.py): each skin triangle is
rasterised in UV space and every texel is evaluated at its 3D point, so colour and shape agree exactly.
"""
import bpy
import os
import sys
import math
from math import pi, sin, cos, exp, sqrt, atan2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import people_face as PF       # noqa: E402

TEX_DIR = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "models", "people_tex")

IRISES = [(0.28, 0.17, 0.09), (0.20, 0.34, 0.52), (0.22, 0.36, 0.20), (0.40, 0.30, 0.18)]   # brown, blue, green, hazel


def save_png(arr, path):
    """arr: H x W x 3 float (sRGB 0..1), row 0 = top."""
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    px = np.ones((h, w, 4), dtype=np.float32)
    px[:, :, :3] = np.clip(arr[::-1], 0, 1)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def eyes_atlas(path, cell=256):
    rng = np.random.default_rng(3)
    out = np.ones((cell, cell * 4, 3), dtype=np.float32)
    yy, xx = np.mgrid[0:cell, 0:cell]
    cx = cy = (cell - 1) / 2
    r = np.hypot(xx - cx, yy - cy) / (cell / 2)            # 1 = the cell edge (the eyeball's equator)
    ang = np.arctan2(yy - cy, xx - cx)
    for k, col in enumerate(IRISES):
        img = np.zeros((cell, cell, 3), dtype=np.float32)
        sclera = np.array([0.93, 0.91, 0.88]) - 0.10 * np.clip((r - 0.55) / 0.45, 0, 1)[..., None] * np.array([0.0, 0.25, 0.25])
        img[:] = sclera
        ri = 0.33                                           # iris radius (28 deg of the eyeball: 11.5 mm)
        fib = 0.75 + 0.25 * np.sin(ang * 38 + rng.random() * 6) * np.sin(ang * 13 + 1.0)
        base = np.array(col)
        iris = base[None, None, :] * (0.65 + 0.55 * (r / ri))[..., None] * fib[..., None]
        iris = np.clip(iris, 0, 1)
        m = r < ri
        img[m] = iris[m]
        ring = (r > ri - 0.05) & (r < ri + 0.01)
        img[ring] *= 0.35                                   # limbal ring
        img[r < 0.105] = (0.015, 0.012, 0.012)              # pupil
        cl = np.hypot(xx - (cx - cell * 0.055), yy - (cy - cell * 0.055)) < cell * 0.026
        img[cl] = (0.97, 0.97, 0.97)                        # catchlight
        out[:, k * cell:(k + 1) * cell] = img
    save_png(out, path)
    return path


# ---------------------------------------------------------------------------------------------------------------
def smooth_mask(d, w):
    """1 inside (d < 0), 0 outside, soft over w."""
    return np.clip(0.5 - d / w, 0.0, 1.0)


def face_colour(p, P, rnd, nrm=None):
    """Multiplicative skin detail for head-local points p (N x 3), normals nrm (N x 3).  Returns N x 3."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    down = np.ones(len(p)) if nrm is None else np.clip((-nrm[:, 2] - 0.55) / 0.25, 0, 1)
    ay = np.abs(y)
    col = np.ones((len(p), 3), dtype=np.float32)
    front = np.clip((x - 0.02) / 0.05, 0, 1)
    male = P["sex"] == "m"

    def mul(mask, c):
        nonlocal col
        c = np.array(c, dtype=np.float32)
        col = col * (1.0 - mask[:, None] + mask[:, None] * c[None, :])

    # fine noise (pores, unevenness)
    n = 1.0 + 0.035 * (rnd.random(len(p)) - 0.5)
    col *= n[:, None]
    # cheeks: a warm tint; nose tip and ears a little redder
    mul(np.exp(-((ay - 0.042) / 0.018) ** 2 - ((z + 0.025) / 0.018) ** 2) * front, (1.0, 0.90, 0.88) if not male else (1.0, 0.94, 0.92))
    mul(np.exp(-(ay / 0.010) ** 2 - ((z + 0.028) / 0.010) ** 2) * front, (1.0, 0.92, 0.90))
    # eyes: lid shading, the crease, the lash lines
    ey, ez = P["eye_y"], P["eye_z"]
    w, hu, hl = P["eye_w"], P["eye_up"], P["eye_low"]
    for s in (1, -1):
        dy = (y - s * ey) * s                               # + = outwards
        t = np.clip(dy / w, -1.2, 1.2)
        up = ez + hu * np.clip(1 - t * t, 0, 1) ** 0.5 * (1 + 0.18 * (-t)) + P["eye_tilt"] * t
        low = ez - hl * np.clip(1 - t * t, 0, 1) ** 0.5 + P["eye_tilt"] * t
        inside_w = np.abs(t) < 1.05
        # upper lid (between the lash line and the crease 4-6 mm above)
        lid = inside_w & (z > up) & (z < up + 0.0065 * np.clip(1 - 0.6 * t * t, 0.2, 1)) & (x > 0.03)
        mul(lid.astype(np.float32) * 0.9, (0.86, 0.78, 0.76) if not male else (0.90, 0.84, 0.82))
        crease = inside_w & (np.abs(z - (up + 0.0068 * np.clip(1 - 0.5 * t * t, 0.2, 1))) < 0.0012) & (x > 0.03)
        mul(crease.astype(np.float32) * 0.6, (0.72, 0.62, 0.60))
        lash = (np.abs(t) < 1.02) & (np.abs(z - up) < (0.0009 if male else 0.0012) * (1.2 - 0.5 * np.abs(t))) & (x > 0.03)
        mul(lash.astype(np.float32), (0.16, 0.12, 0.11))
        lash2 = (np.abs(t) < 0.95) & (np.abs(z - low) < 0.00045) & (x > 0.03)
        mul(lash2.astype(np.float32) * 0.7, (0.45, 0.36, 0.33))
        # under-eye softness
        mul(np.exp(-((dy + 0.002) / 0.012) ** 2 - ((z - (ez - 0.011)) / 0.004) ** 2) * front, (0.93, 0.88, 0.88))
        # brows: from the inner end rising to a peak two thirds out, then the tail
        bt = np.clip((dy + 0.019) / 0.042, 0, 1)                           # 0 inner end .. 1 tail
        bz = ez + 0.0140 + 0.0058 * np.sin(np.clip(bt * 1.3, 0, 1) * pi * 0.60) - 0.0030 * np.clip(bt - 0.78, 0, 1) * 4.5
        thick = (0.0028 if male else 0.0019) * (1.15 - 0.75 * bt) + 0.0007
        inb = (dy > -0.020) & (dy < 0.024) & (x > 0.03)
        hairs = 0.55 + 0.45 * np.clip(np.sin(y * 3100 + z * 1900 + 3 * np.sin(z * 700)) * 0.5 + 0.5 + 0.3 * (rnd.random(len(p)) - 0.5), 0, 1)
        bm = smooth_mask(np.abs(z - bz) - thick, 0.0016) * inb * hairs * smooth_mask(-dy - 0.019, 0.004)
        mul(bm, (0.30, 0.23, 0.18) if male else (0.40, 0.30, 0.24))
    # lips
    mz, mw = P["mouth_z"], P["mouth_w"]
    t = np.clip(ay / mw, 0, 1.3)
    top = mz + (0.0082 if not male else 0.0068) * np.clip(1 - t * t, 0, 1) ** 0.55 - 0.0014 * np.exp(-(ay / 0.0028) ** 2)
    top += 0.0006 * np.exp(-((ay - 0.0052) / 0.002) ** 2)                 # the cupid's bow peaks
    bot = mz - (0.0108 if not male else 0.0092) * np.clip(1 - t * t, 0, 1) ** 0.7
    lip = smooth_mask(np.maximum(z - top, bot - z), 0.0008) * (t < 1.02) * (x > 0.05)
    mul(lip, (0.80, 0.55, 0.55) if not male else (0.90, 0.74, 0.70))
    mul(smooth_mask(np.abs(z - mz) - 0.0006, 0.0005) * (t < 1.0) * (x > 0.05), (0.45, 0.30, 0.30))
    # nostrils (under the nose base), the alar crease
    L = P["nose_len"]
    for s in (1, -1):
        d = ((y - s * 0.0068 * P["nose_w"]) / 0.0030) ** 2 + ((z + 0.0395 * L) / 0.0019) ** 2
        mul(smooth_mask(d - 1.0, 0.8) * (x > 0.06) * down, (0.38, 0.28, 0.25))
        cr = np.exp(-((np.hypot(y - s * 0.0155 * P["nose_w"], z + 0.0335 * L) - 0.0078) / 0.0009) ** 2)
        side = np.clip((s * y - 0.012 * P["nose_w"]) / 0.004, 0, 1)
        mul(cr * 0.45 * (x > 0.06) * side * (z > -0.040 * L) * (z < -0.028 * L), (0.82, 0.70, 0.66))
    # stubble / shadow of the beard (men)
    if male and P.get("stubble", 0.0) > 0:
        beard = (np.exp(-((z + 0.07) / 0.035) ** 2) * (ay < 0.07) + np.exp(-((z - (mz + 0.011)) / 0.004) ** 2) * (ay < mw + 0.004))
        beard *= (1 - lip) * (x > 0.0) * (z < -0.035)
        grain = 0.7 + 0.3 * rnd.random(len(p))
        mul(np.clip(beard, 0, 1) * P["stubble"] * grain, (0.80, 0.78, 0.80))
    return col


def unwrap_skin(ob):
    """Smart UV project of the Skin faces only (the eyes keep their atlas UVs)."""
    me = ob.data
    skin = [i for i, m in enumerate(me.materials) if m and m.name.split(".")[0] == "Skin"]
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in me.polygons:
        p.select = p.material_index in skin
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(70.0), island_margin=0.006, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return skin


def bake_face(ob, variant, path, size=1024):
    """Rasterise every Skin triangle in UV space; evaluate face_colour at the interpolated 3D point."""
    P = PF.VARIANTS[variant]
    me = ob.data
    skin = [i for i, m in enumerate(me.materials) if m and m.name.split(".")[0] == "Skin"]
    me.calc_loop_triangles()
    uvl = me.uv_layers.active.data
    co = np.array([v.co[:] for v in me.vertices]) - np.array(PF.HC[:])
    vn = np.array([v.normal[:] for v in me.vertices])
    img = np.ones((size, size, 3), dtype=np.float32)
    filled = np.zeros((size, size), dtype=bool)
    rnd = np.random.default_rng(11)
    for tri in me.loop_triangles:
        if tri.material_index not in skin:
            continue
        uv = np.array([uvl[l].uv[:] for l in tri.loops]) * size
        p3 = co[list(tri.vertices)]
        x0, y0 = np.floor(uv.min(axis=0)).astype(int)
        x1, y1 = np.ceil(uv.max(axis=0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay_), (bx, by), (cx, cy) = uv
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay_ - cy)
        if abs(den) < 1e-12:
            continue
        l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
        l2 = ((cy - ay_) * (gx - cx) + (ax - cx) * (gy - cy)) / den
        l3 = 1 - l1 - l2
        m = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
        if not m.any():
            continue
        pts = l1[m][:, None] * p3[0] + l2[m][:, None] * p3[1] + l3[m][:, None] * p3[2]
        n3 = vn[list(tri.vertices)]
        nn = l1[m][:, None] * n3[0] + l2[m][:, None] * n3[1] + l3[m][:, None] * n3[2]
        c = face_colour(pts, P, rnd, nn)
        iy = (gy[m] - 0.5).astype(int)
        ix = (gx[m] - 0.5).astype(int)
        img[iy, ix] = c
        filled[iy, ix] = True
    # dilate into the gutters (mipmaps and filtering never pull white edges into the face)
    for _ in range(6):
        grow = ~filled
        acc = np.zeros_like(img)
        cnt = np.zeros(filled.shape, dtype=np.float32)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.roll(img, dy, 0), dx, 1)
            fs = np.roll(np.roll(filled, dy, 0), dx, 1)
            acc += sh * fs[..., None]
            cnt += fs
        new = grow & (cnt > 0)
        img[new] = acc[new] / cnt[new][:, None]
        filled |= new
    save_png(img[::-1], path)          # UV v = 0 at the bottom: flip so row 0 is the top
    return path


def hair_texture(path, size=512):
    """Tiling strand streaks (multiplicative, along v): many thin strands of varied brightness, a few clumps."""
    rng = np.random.default_rng(21)
    u = np.arange(size) / size
    col = np.ones(size, dtype=np.float32) * 0.90
    for k in range(900):
        c = rng.random()
        w = 0.0006 + 0.0016 * rng.random()
        a = 0.05 + 0.12 * rng.random()
        sgn = 1 if rng.random() < 0.45 else -1
        d = np.abs(((u - c + 0.5) % 1.0) - 0.5)
        col += sgn * a * np.exp(-(d / w) ** 2)
    col = np.clip(col, 0.35, 1.18) / 1.18
    img = np.repeat(col[None, :], size, axis=0)
    # slow waves along the strands
    v = np.arange(size)[:, None] / size
    img = img * (0.94 + 0.06 * np.sin(2 * np.pi * (v * 2 + u[None, :] * 3)))
    save_png(np.repeat(img[..., None], 3, axis=2), path)
    return path
