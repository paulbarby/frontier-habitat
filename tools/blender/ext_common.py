"""
Frontier Habitat 2.0 - ART-B shared library for the exterior, special, crop, colonist and prop
generators (tools/blender/ext_*.py).  Blender 5.2, always run with --background.

The Part geometry builder, the material set-up and the GLB reader are COPIED from the v1 generator
tools/blender/build_assets.py (owned by ART-A; it is not imported and not edited).
New here:
  * vertex-colour ambient occlusion, baked with a BVH ray cast per face corner (COLOR_0)
  * atomic GLB export (<name>.tmp.glb, then os.replace)
  * empties (Anchor_*), per-file materials (Accent, Neon, Produce), 2.0 materials (Trim, L3Band ...)
  * a build driver that checks every file it writes and keeps tools/blender/ext_report.{json,md}

Conventions (AAA_DESIGN.md section 11): metres, Blender Z up, glTF +Y up, origin at ground level at the
footprint centre, front = +X.  Blender (x, y, z) -> glTF / Godot (x, z, -y).
"""
import bpy
import bmesh
import os
import sys
import json
import math
import struct
import random
import time
import warnings
from contextlib import contextmanager
from math import sin, cos, pi, radians, degrees, sqrt, atan2, asin
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

try:
    import numpy as np
except Exception:          # numpy ships with Blender; this is only a guard
    np = None

warnings.filterwarnings("ignore", category=DeprecationWarning)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MODEL_DIR = os.path.join(ROOT, "assets", "models")
THUMB_DIR = os.path.join(ROOT, "assets", "thumbs")
PREVIEW_DIR = os.path.join(HERE, "previews_ext")
REPORT_JSON = os.path.join(HERE, "ext_report.json")
REPORT_MD = os.path.join(HERE, "ext_report.md")
CONTENT_DIR = os.path.join(ROOT, "content")


def load_content(name):
    with open(os.path.join(CONTENT_DIR, name), "r", encoding="utf-8") as fh:
        return json.load(fh)


# --------------------------------------------------------------------------------------
# Colours and materials
# --------------------------------------------------------------------------------------
ACCENTS = {                                  # AAA_DESIGN.md section 1
    "life_support": "#29b6c6",
    "food": "#6abf4b",
    "housing": "#f2c14e",
    "industry": "#e07a3a",
    "logistics": "#9b6bd6",
    "utilities": "#4a90d9",
    "medical": "#e85d75",
    "comfort": "#f08fc0",
    "science": "#7c8cff",
    "space": "#c9d3e0",
}

# name -> colour (sRGB hex) and Principled BSDF values. Names are a contract with the game (section 11).
MATERIALS = {
    # v1 list (unchanged values)
    "Hull":       dict(color="#d9dde2", rough=0.60),
    "HullDark":   dict(color="#8a929c", rough=0.70),
    "Frame":      dict(color="#4a5058", metal=0.60, rough=0.50),
    "Metal":      dict(color="#9aa3ad", metal=0.80, rough=0.35),
    "Rubber":     dict(color="#2b2d33", rough=0.90),
    "Glass":      dict(color="#9fd4ea", rough=0.10, alpha=0.35),
    "Window":     dict(color="#ffd27a", rough=0.40, emit="#ffd27a", emit_strength=1.5),
    "Solar":      dict(color="#1b2a55", metal=0.70, rough=0.25),
    "Soil":       dict(color="#5a3d2b", rough=0.95),
    "Plant":      dict(color="#4caf50", rough=0.80, double_sided=True),
    "PlantDark":  dict(color="#2e7d32", rough=0.80, double_sided=True),
    "WaterBlue":  dict(color="#3aa0d8", rough=0.40),
    "Hazard":     dict(color="#f2b632", rough=0.60),
    "Ore":        dict(color="#6b4a3a", metal=0.30, rough=0.85),
    "OreVein":    dict(color="#c98a4b", rough=0.50),
    "Cargo":      dict(color="#c0c4c8", rough=0.60),
    "Fabric":     dict(color="#b35a4a", rough=0.95),
    "Light":      dict(color="#ffffff", rough=0.40, emit="#ffffff", emit_strength=3.0),
    "SuitMain":   dict(color="#e8eaed", rough=0.70),
    "SuitAccent": dict(color="#ff9f1c", rough=0.60),
    "Visor":      dict(color="#2a3140", metal=0.90, rough=0.15),
    "Pack":       dict(color="#7d8590", rough=0.60),
    # 2.0 additions (section 11)
    "Trim":       dict(color="#b8c2cc", metal=0.85, rough=0.30),
    "L3Band":     dict(color="#3ee0ff", rough=0.40, emit="#3ee0ff", emit_strength=1.2),
    "L4Band":     dict(color="#a78bfa", rough=0.40, emit="#a78bfa", emit_strength=1.2),
    "L5Gold":     dict(color="#ffd166", metal=0.90, rough=0.30, emit="#ffd166", emit_strength=0.6),
    "Frost":      dict(color="#ddefff", rough=0.50),
    "Glow":       dict(color="#9cffb0", rough=0.40, emit="#9cffb0", emit_strength=3.0),
    "Ember":      dict(color="#ff5a0a", rough=0.40, emit="#ff4a00", emit_strength=1.6),
    "Plasma":     dict(color="#8fd8ff", rough=0.30, emit="#8fd8ff", emit_strength=5.0),
    # 3.0 (docs/V3_DESIGN.md section 7.3), the same values as build_assets.MATERIALS
    "LightStrip": dict(color="#eaf6ff", rough=0.30, emit="#eaf6ff", emit_strength=2.5),
    "Screen":     dict(color="#123c4c", rough=0.25, emit="#2fb8d8", emit_strength=0.45),
    "Wood":       dict(color="#b08560", rough=0.55),
    "Cushion":    dict(color="#3c4a5e", rough=0.90),
    "Floor":      dict(color="#d9d4cb", rough=0.65),
    "FloorDark":  dict(color="#6b6f76", rough=0.70),
    # ART-B additions (documented in ext_report.md and docs/requests/ART-B-to-RENDER.md)
    "Skin":       dict(color="#d9a47e", rough=0.75),
    "Hair":       dict(color="#4a3326", rough=0.85),
}
# per-file colours: Accent (category), Neon (category colour, emissive 3), Produce (crop colour)
PER_FILE = ("Accent", "Neon", "Produce")
DOUBLE_SIDED = {n for n, s in MATERIALS.items() if s.get("double_sided")} | {"Produce"}
EMISSIVE = {n for n, s in MATERIALS.items() if "emit" in s} | {"Neon"}
SHARP_ANGLE = 50.0   # degrees; edges sharper than this get split normals on smooth faces


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(h):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def make_material(name, spec):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    if bsdf is None:
        nt.nodes.clear()
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    rgb = hex_to_linear(spec["color"])
    alpha = spec.get("alpha", 1.0)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Metallic"].default_value = spec.get("metal", 0.0)
    bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.5)
    bsdf.inputs["Alpha"].default_value = alpha
    if "emit" in spec:
        bsdf.inputs["Emission Color"].default_value = (*hex_to_linear(spec["emit"]), 1.0)
        bsdf.inputs["Emission Strength"].default_value = spec.get("emit_strength", 1.0)
    else:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    if alpha < 1.0:
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    mat.use_backface_culling = not spec.get("double_sided", False)
    mat.diffuse_color = (*rgb, alpha)
    mat.metallic = spec.get("metal", 0.0)
    mat.roughness = spec.get("rough", 0.5)
    return mat


class MaterialSet:
    """One set per exported file, so the per-file colours can change."""

    def __init__(self, accent_hex=None, produce_hex=None):
        self.accent_hex = accent_hex
        self.produce_hex = produce_hex
        self.cache = {}

    def spec(self, name):
        if name == "Accent":
            if not self.accent_hex:
                raise ValueError("this model has no accent colour but uses Accent")
            return dict(color=self.accent_hex, rough=0.55)
        if name == "Neon":
            if not self.accent_hex:
                raise ValueError("this model has no accent colour but uses Neon")
            return dict(color=self.accent_hex, rough=0.40, emit=self.accent_hex, emit_strength=3.0)
        if name == "Produce":
            if not self.produce_hex:
                raise ValueError("this model has no produce colour but uses Produce")
            return dict(color=self.produce_hex, rough=0.55, double_sided=True)
        return MATERIALS[name]

    def get(self, name):
        if name not in self.cache:
            self.cache[name] = make_material(name, self.spec(name))
        return self.cache[name]


# --------------------------------------------------------------------------------------
# Transform helpers
# --------------------------------------------------------------------------------------
def T(x=0.0, y=0.0, z=0.0):
    if isinstance(x, (tuple, list, Vector)):
        x, y, z = x
    return Matrix.Translation((x, y, z))


def RX(deg):
    return Matrix.Rotation(radians(deg), 4, "X")


def RY(deg):
    return Matrix.Rotation(radians(deg), 4, "Y")


def RZ(deg):
    return Matrix.Rotation(radians(deg), 4, "Z")


def S(x=1.0, y=None, z=None):
    if y is None:
        y = x
    if z is None:
        z = x
    m = Matrix.Identity(4)
    m[0][0], m[1][1], m[2][2] = x, y, z
    return m


def polar(r, deg, z=0.0):
    a = radians(deg)
    return (r * cos(a), r * sin(a), z)


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _basis(w):
    """Right-handed basis (u, v, w) with u x v = w."""
    w = Vector(w).normalized()
    if abs(w.z) > 0.999:
        u = Vector((1.0, 0.0, 0.0))
    else:
        u = Vector((0.0, 0.0, 1.0)).cross(w).normalized()
    v = w.cross(u).normalized()
    return u, v, w


def fillet_path(pts, radius, n=3):
    """Round the inner corners of a polyline (quadratic Bezier per corner)."""
    pts = [Vector(p) for p in pts]
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        p_prev, p, p_next = pts[i - 1], pts[i], pts[i + 1]
        d_in = (p - p_prev)
        d_out = (p_next - p)
        r = min(radius, d_in.length * 0.45, d_out.length * 0.45)
        a = p - d_in.normalized() * r
        b = p + d_out.normalized() * r
        for k in range(n + 1):
            t = k / n
            out.append((1 - t) ** 2 * a + 2 * (1 - t) * t * p + t ** 2 * b)
    out.append(pts[-1])
    return out


# --------------------------------------------------------------------------------------
# Part: accumulates the geometry of ONE exported object (copied from v1, extended)
# --------------------------------------------------------------------------------------
class Part:
    def __init__(self, name, origin=(0.0, 0.0, 0.0)):
        self.name = name
        self.origin = Vector(origin)
        self.verts = []
        self.vover = []
        self.faces = []
        self.fmat = []
        self.fsmooth = []
        self._stack = [Matrix.Identity(4)]
        self._flip = False
        self.overhang = False

    @contextmanager
    def at(self, *mats):
        m = Matrix.Identity(4)
        for k in mats:
            m = m @ k
        self._stack.append(self._stack[-1] @ m)
        self._flip = self._stack[-1].to_3x3().determinant() < 0
        try:
            yield self
        finally:
            self._stack.pop()
            self._flip = self._stack[-1].to_3x3().determinant() < 0

    def matrix(self):
        return self._stack[-1].copy()

    # ---- raw geometry ------------------------------------------------------------------
    def v(self, p):
        q = self._stack[-1] @ Vector(p)
        self.verts.append(q)
        self.vover.append(self.overhang)
        return len(self.verts) - 1

    def f(self, idx, mat, smooth=False):
        clean = []
        for i in idx:
            if not clean or clean[-1] != i:
                clean.append(i)
        if len(clean) > 1 and clean[0] == clean[-1]:
            clean.pop()
        if len(clean) < 3:
            return
        if self._flip:
            clean.reverse()
        self.faces.append(tuple(clean))
        self.fmat.append(mat)
        self.fsmooth.append(bool(smooth))

    def poly(self, pts, mat, smooth=False):
        """One polygon from points (in order; normal by right-hand rule)."""
        self.f([self.v(p) for p in pts], mat, smooth)

    def convex(self, pts, faces, mat, smooth=False, mats=None):
        """Add a convex solid. Face winding is fixed automatically (normal away from the centroid)."""
        vs = [Vector(p) for p in pts]
        c = sum(vs, Vector((0, 0, 0))) / len(vs)
        ids = [self.v(p) for p in vs]
        for k, face in enumerate(faces):
            fv = [vs[i] for i in face]
            n = Vector((0, 0, 0))
            for a in range(len(fv)):
                p, q = fv[a], fv[(a + 1) % len(fv)]
                n += Vector(((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y)))
            fc = sum(fv, Vector((0, 0, 0))) / len(fv)
            order = list(face) if n.dot(fc - c) >= 0 else list(reversed(face))
            m = mats[k] if mats and mats[k] else mat
            if m is None:
                continue
            self.f([ids[i] for i in order], m, smooth)

    # ---- loft ------------------------------------------------------------------------------
    def loft(self, rings, mat, smooth=True, closed=True, wrap=False, cap0=False, cap1=False,
             cap_mat=None, flip=False):
        """rings: list of point lists (same length, or length 1 = apex).
        Face normal = (direction of i) x (direction of ring order)."""
        idx = [[self.v(p) for p in ring] for ring in rings]
        nk = len(idx) if wrap else len(idx) - 1
        for k in range(nk):
            A, B = idx[k], idx[(k + 1) % len(idx)]
            n = max(len(A), len(B))
            cnt = n if closed else n - 1
            for i in range(cnt):
                j = (i + 1) % n
                a = A[i] if len(A) > 1 else A[0]
                b = A[j] if len(A) > 1 else A[0]
                c = B[j] if len(B) > 1 else B[0]
                d = B[i] if len(B) > 1 else B[0]
                m = mat(k, i) if callable(mat) else mat
                if m is None:
                    continue
                quad = [a, b, c, d]
                if flip:
                    quad.reverse()
                self.f(quad, m, smooth)
        cm = cap_mat or (mat if not callable(mat) else "Hull")
        if cap0 and len(idx[0]) > 2:
            face = list(reversed(idx[0]))
            self.f(list(reversed(face)) if flip else face, cm, False)
        if cap1 and len(idx[-1]) > 2:
            face = list(idx[-1])
            self.f(list(reversed(face)) if flip else face, cm, False)
        return idx

    # ---- surface of revolution about local Z --------------------------------------------
    def lathe(self, profile, mat, seg=24, smooth=True, a0=0.0, a1=360.0, caps=True, cap_mat=None,
              wrap=False, phase=0.0):
        """profile: [(r, z), ...]. Walk it counter-clockwise in the (r, z) half plane
        (up the outside, inward over the top, down the inside) to get outward normals."""
        full = abs((a1 - a0) - 360.0) < 1e-6
        n = seg if full else seg + 1
        angs = [radians(a0 + phase + (a1 - a0) * i / seg) for i in range(n)]
        rings = []
        for (r, z) in profile:
            if r < 1e-6:
                rings.append([(0.0, 0.0, z)])
            else:
                rings.append([(r * cos(a), r * sin(a), z) for a in angs])
        idx = self.loft(rings, mat, smooth, closed=full, wrap=wrap)
        if not full and caps:
            cm = cap_mat or (mat if not callable(mat) else "Hull")
            start = [ring[0] for ring in idx]
            end = [ring[-1] for ring in idx]
            self.f(start, cm, False)
            self.f(list(reversed(end)), cm, False)
        return idx

    def dome(self, radius, z0, height, mat, seg=24, rings=6, smooth=True, t1=90.0):
        prof = dome_profile(radius, z0, z0 + height, rings, t1=t1)
        return self.lathe(prof, mat, seg=seg, smooth=smooth)

    def ring_flat(self, r_in, r_out, z, mat, seg=24, a0=0.0, a1=360.0):
        self.lathe([(r_out, z), (r_in, z)], mat, seg=seg, smooth=False, a0=a0, a1=a1, caps=False)

    def disc(self, r, z, mat, seg=24):
        self.lathe([(r, z), (0.0, z)], mat, seg=seg, smooth=False)

    def torus(self, R, r, mat, seg=24, tseg=8, z=0.0, smooth=True, a0=0.0, a1=360.0):
        prof = [(R + r * cos(2 * pi * k / tseg), z + r * sin(2 * pi * k / tseg)) for k in range(tseg)]
        self.lathe(prof, mat, seg=seg, smooth=smooth, wrap=True, a0=a0, a1=a1, caps=False)

    def sphere(self, c, r, mat, seg=12, rings=6, smooth=True, scale=(1.0, 1.0, 1.0)):
        prof = [(r * cos(radians(-90 + 180 * k / rings)), r * sin(radians(-90 + 180 * k / rings)))
                for k in range(rings + 1)]
        prof[0] = (0.0, -r)
        prof[-1] = (0.0, r)
        with self.at(T(*c), S(*scale)):
            self.lathe(prof, mat, seg=seg, smooth=smooth)

    def hemi(self, c, r, mat, seg=12, rings=3, smooth=True, scale=(1.0, 1.0, 1.0), cap=True):
        """Upper half sphere standing on c (flat bottom)."""
        prof = [(r * cos(radians(90 * k / rings)), r * sin(radians(90 * k / rings))) for k in range(rings + 1)]
        prof[-1] = (0.0, r)
        if cap:
            prof = [(0.0, 0.0)] + prof
        with self.at(T(*c), S(*scale)):
            self.lathe(prof, mat, seg=seg, smooth=smooth)

    # ---- cylinder / cone between two points -------------------------------------------------
    def cyl(self, p0, p1, r0, r1=None, seg=12, mat="Metal", smooth=True, cap0=True, cap1=True,
            cap_mat=None, phase=0.0):
        p0, p1 = Vector(p0), Vector(p1)
        r1 = r0 if r1 is None else r1
        u, v, w = _basis(p1 - p0)
        rings = []
        for p, r in ((p0, r0), (p1, r1)):
            if r < 1e-6:
                rings.append([tuple(p)])
            else:
                rings.append([tuple(p + u * (r * cos(2 * pi * i / seg + phase)) + v * (r * sin(2 * pi * i / seg + phase)))
                              for i in range(seg)])
        self.loft(rings, mat, smooth, closed=True, cap0=cap0, cap1=cap1, cap_mat=cap_mat)

    def vcyl(self, x, y, z0, z1, r0, r1=None, **kw):
        self.cyl((x, y, z0), (x, y, z1), r0, r1, **kw)

    def tube(self, pts, r, seg=8, mat="Metal", smooth=True, caps=True, fillet=0.0, fillet_n=3):
        pts = [Vector(p) for p in pts]
        if fillet > 0:
            pts = fillet_path(pts, fillet, fillet_n)
        dirs = [(pts[i + 1] - pts[i]).normalized() for i in range(len(pts) - 1)]
        u, v, _ = _basis(dirs[0])
        rings = []
        for j, p in enumerate(pts):
            t_in = dirs[j - 1] if j > 0 else dirs[0]
            t_out = dirs[j] if j < len(dirs) else dirs[-1]
            if j > 0 and j < len(dirs):
                q = dirs[j - 1].rotation_difference(dirs[j])
            b = (t_in + t_out)
            b = b.normalized() if b.length > 1e-6 else t_in
            ring = []
            for i in range(seg):
                a = 2 * pi * i / seg
                o = u * (r * cos(a)) + v * (r * sin(a))
                o = o - t_in * (o.dot(b) / max(t_in.dot(b), 0.2))
                ring.append(tuple(p + o))
            rings.append(ring)
            if j > 0 and j < len(dirs):
                u = q @ u
                v = q @ v
        self.loft(rings, mat, smooth, closed=True, cap0=caps, cap1=caps)

    # ---- rectangular beam between two points ------------------------------------------------
    def beam(self, p0, p1, w, h=None, mat="Frame", up=None, caps=True):
        p0, p1 = Vector(p0), Vector(p1)
        h = w if h is None else h
        t = (p1 - p0).normalized()
        upv = Vector(up) if up is not None else Vector((0, 0, 1))
        if abs(t.dot(upv.normalized())) > 0.999:
            upv = Vector((1, 0, 0))
        u = upv.cross(t).normalized()
        v = t.cross(u).normalized()
        rings = []
        for p in (p0, p1):
            rings.append([tuple(p + u * (sx * w / 2) + v * (sy * h / 2))
                          for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))])
        self.loft(rings, mat, False, closed=True, cap0=caps, cap1=caps)

    def beam_path(self, pts, w, h=None, mat="Frame", up=(0, 0, 1), caps=True):
        h = w if h is None else h
        pts = [Vector(p) for p in pts]
        rings = []
        for j, p in enumerate(pts):
            if j == 0:
                t = pts[1] - pts[0]
            elif j == len(pts) - 1:
                t = pts[-1] - pts[-2]
            else:
                t = pts[j + 1] - pts[j - 1]
            t.normalize()
            upv = Vector(up(p)) if callable(up) else Vector(up)
            u = upv.cross(t).normalized()
            v = t.cross(u).normalized()
            rings.append([tuple(p + u * (sx * w / 2) + v * (sy * h / 2))
                          for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))])
        self.loft(rings, mat, False, closed=True, cap0=caps, cap1=caps)

    # ---- boxes --------------------------------------------------------------------------------
    def box(self, c, s, mat, bevel=0.0, mats=None, smooth=False):
        """c = centre, s = size. mats = optional {'+x': name, '-z': name, ..., 'edge': name}."""
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        mats = mats or {}
        if bevel <= 0:
            P = [(cx + sx * hx, cy + sy * hy, cz + sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
            F = {
                "+x": (4, 6, 7, 5), "-x": (0, 1, 3, 2),
                "+y": (2, 3, 7, 6), "-y": (0, 4, 5, 1),
                "+z": (1, 5, 7, 3), "-z": (0, 2, 6, 4),
            }
            ids = [self.v(p) for p in P]
            for key, face in F.items():
                m = mats.get(key, mat)
                if m is None:
                    continue
                self.f([ids[i] for i in face], m, smooth)
            return
        b = min(bevel, hx * 0.98, hy * 0.98, hz * 0.98)
        pts, index = [], {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    index[("x", sx, sy, sz)] = len(pts); pts.append((cx + sx * hx, cy + sy * (hy - b), cz + sz * (hz - b)))
                    index[("y", sx, sy, sz)] = len(pts); pts.append((cx + sx * (hx - b), cy + sy * hy, cz + sz * (hz - b)))
                    index[("z", sx, sy, sz)] = len(pts); pts.append((cx + sx * (hx - b), cy + sy * (hy - b), cz + sz * hz))
        faces, fm = [], []
        cyc = ((-1, -1), (1, -1), (1, 1), (-1, 1))
        for s_ in (-1, 1):
            faces.append([index[("x", s_, a, b_)] for a, b_ in cyc]); fm.append(mats.get("+x" if s_ > 0 else "-x", mat))
            faces.append([index[("y", a, s_, b_)] for a, b_ in cyc]); fm.append(mats.get("+y" if s_ > 0 else "-y", mat))
            faces.append([index[("z", a, b_, s_)] for a, b_ in cyc]); fm.append(mats.get("+z" if s_ > 0 else "-z", mat))
        edge_mat = mats.get("edge", mat)
        for a in (-1, 1):
            for b_ in (-1, 1):
                faces.append([index[("x", a, b_, -1)], index[("y", a, b_, -1)], index[("y", a, b_, 1)], index[("x", a, b_, 1)]]); fm.append(edge_mat)
                faces.append([index[("x", a, -1, b_)], index[("z", a, -1, b_)], index[("z", a, 1, b_)], index[("x", a, 1, b_)]]); fm.append(edge_mat)
                faces.append([index[("y", -1, a, b_)], index[("z", -1, a, b_)], index[("z", 1, a, b_)], index[("y", 1, a, b_)]]); fm.append(edge_mat)
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    faces.append([index[("x", sx, sy, sz)], index[("y", sx, sy, sz)], index[("z", sx, sy, sz)]]); fm.append(edge_mat)
        # convex() skips faces whose material is None
        vs = [Vector(p) for p in pts]
        cc = sum(vs, Vector((0, 0, 0))) / len(vs)
        ids = [self.v(p) for p in vs]
        for k, face in enumerate(faces):
            if fm[k] is None:
                continue
            fv = [vs[i] for i in face]
            n = Vector((0, 0, 0))
            for a in range(len(fv)):
                p, q = fv[a], fv[(a + 1) % len(fv)]
                n += Vector(((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y)))
            fc = sum(fv, Vector((0, 0, 0))) / len(fv)
            order = list(face) if n.dot(fc - cc) >= 0 else list(reversed(face))
            self.f([ids[i] for i in order], fm[k], smooth)

    def box0(self, x, y, z0, sx, sy, sz, mat, **kw):
        """Box that stands on z0 (centre x, y)."""
        self.box((x, y, z0 + sz / 2), (sx, sy, sz), mat, **kw)

    # ---- prisms -----------------------------------------------------------------------------
    def prism(self, poly, z0, z1, mat, cap_mat=None, cap0=True, cap1=True, smooth=False):
        area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                   for i in range(len(poly)))
        if area < 0:
            poly = list(reversed(poly))
        rings = [[(x, y, z0) for x, y in poly], [(x, y, z1) for x, y in poly]]
        self.loft(rings, mat, smooth, closed=True, cap0=cap0, cap1=cap1, cap_mat=cap_mat)

    def prism_y(self, poly_xz, y0, y1, mat, **kw):
        with self.at(RX(90)):
            self.prism([(x, z) for x, z in poly_xz], -y1, -y0, mat, **kw)

    def prism_x(self, poly_yz, x0, x1, mat, **kw):
        m = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        with self.at(m):
            self.prism(poly_yz, x0, x1, mat, **kw)

    def drape(self, x0, x1, y0, y1, zfun, mat, nx=6, ny=2, offset=0.03, smooth=True):
        ids = [[self.v((x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny,
                        zfun(x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny) + offset))
                for j in range(ny + 1)] for i in range(nx + 1)]
        for i in range(nx):
            for j in range(ny):
                self.f([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], mat, smooth)

    # ---- convex hull (rocks, debris) -------------------------------------------------------------
    def hull(self, pts, mat, vein=None, vein_mat="OreVein", vein_max=5, smooth=False, face_mat=None):
        """Convex hull of a point cloud. vein = (point, normal, half_width): the faces nearest to that
        plane get vein_mat. face_mat(centre, normal) -> material name or None (keeps mat)."""
        bm = bmesh.new()
        for p in pts:
            bm.verts.new(p)
        bm.verts.ensure_lookup_table()
        bmesh.ops.convex_hull(bm, input=list(bm.verts), use_existing_faces=False)
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        vs = [tuple(v.co) for v in bm.verts]
        faces = [[v.index for v in f.verts] for f in bm.faces]
        bm.free()
        fm = [None] * len(faces)
        if vein:
            cand = []
            for k, face in enumerate(faces):
                fc = sum((Vector(vs[i]) for i in face), Vector((0, 0, 0))) / len(face)
                d = abs((fc - Vector(vein[0])).dot(Vector(vein[1]).normalized()))
                if d < vein[2] and fc.z > 0.12:
                    cand.append((d, k))
            for d, k in sorted(cand)[:vein_max]:
                fm[k] = vein_mat
        if face_mat:
            for k, face in enumerate(faces):
                pv = [Vector(vs[i]) for i in face]
                fc = sum(pv, Vector((0, 0, 0))) / len(pv)
                n = (pv[1] - pv[0]).cross(pv[2] - pv[0])
                n = n.normalized() if n.length > 1e-9 else Vector((0, 0, 1))
                m = face_mat(fc, n)
                if m:
                    fm[k] = m
        self.convex(vs, faces, mat, smooth, mats=fm)


def dome_profile(radius, z0, top, rings, t0=0.0, t1=90.0):
    pts = []
    for j in range(rings + 1):
        t = radians(t0 + (t1 - t0) * j / rings)
        pts.append((radius * cos(t), z0 + (top - z0) * sin(t)))
    return pts


class Anchor:
    """An empty in the exported file (Anchor_<name>). Local +X of the node = `forward` (world)."""

    def __init__(self, name, pos, forward=(1, 0, 0), up=(0, 0, 1)):
        self.name = name
        self.pos = Vector(pos)
        self.forward = Vector(forward).normalized()
        self.up = Vector(up).normalized()


# --------------------------------------------------------------------------------------
# Scene handling
# --------------------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
                 bpy.data.images):
        for item in list(coll):
            coll.remove(item)


def part_to_object(part, mset):
    mesh = bpy.data.meshes.new(part.name)
    mesh.from_pydata([tuple(v - part.origin) for v in part.verts], [], part.faces)
    names = []
    for m in part.fmat:
        if m not in names:
            names.append(m)
    for n in names:
        mesh.materials.append(mset.get(n))
    lookup = {n: i for i, n in enumerate(names)}
    mesh.polygons.foreach_set("material_index", [lookup[m] for m in part.fmat])
    mesh.update()
    if mesh.validate(verbose=False):
        print("    WARNING: mesh.validate() changed the mesh of", part.name)
    # Blender 5: set_sharp_from_angle() deletes `sharp_face`, so write the per-face flag after it.
    mesh.set_sharp_from_angle(angle=radians(SHARP_ANGLE))
    attr = mesh.attributes.get("sharp_face") or mesh.attributes.new("sharp_face", "BOOLEAN", "FACE")
    if len(part.fsmooth) == len(mesh.polygons):
        attr.data.foreach_set("value", [not s for s in part.fsmooth])
    mesh.update()
    obj = bpy.data.objects.new(part.name, mesh)
    obj.location = part.origin
    bpy.context.scene.collection.objects.link(obj)
    return obj


def anchor_to_object(a):
    ob = bpy.data.objects.new("Anchor_" + a.name if not a.name.startswith("Anchor_") else a.name, None)
    ob.empty_display_type = "ARROWS"
    ob.empty_display_size = 0.5
    x = a.forward
    z = a.up - x * a.up.dot(x)
    if z.length < 1e-6:
        z = Vector((0, 0, 1)) if abs(x.z) < 0.9 else Vector((0, 1, 0))
        z = z - x * z.dot(x)
    z.normalize()
    y = z.cross(x)
    m = Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z)))
    ob.matrix_world = Matrix.Translation(a.pos) @ m.to_4x4()
    bpy.context.scene.collection.objects.link(ob)
    return ob


# --------------------------------------------------------------------------------------
# Vertex-colour ambient occlusion (BVH ray cast per face corner)
# --------------------------------------------------------------------------------------
def _hemisphere(n):
    """Cosine-weighted directions around +Z (Fibonacci spiral on the unit disc)."""
    ga = pi * (3.0 - sqrt(5.0))
    out = []
    for i in range(n):
        r = sqrt((i + 0.5) / n)
        a = i * ga
        x, y = r * cos(a), r * sin(a)
        out.append((x, y, sqrt(max(0.0, 1.0 - x * x - y * y))))
    return out


def _world_mesh_data(obj):
    """World-space vertex list and polygon list of a mesh object."""
    me = obj.data
    mw = obj.matrix_world
    verts = [mw @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    return verts, polys


def build_bvh(objs):
    verts, polys = [], []
    for ob in objs:
        vs, ps = _world_mesh_data(ob)
        off = len(verts)
        verts.extend(vs)
        polys.extend(tuple(i + off for i in p) for p in ps)
    if not polys:
        return None
    return BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)


def bake_ao(objs, occluders, dist=1.0, samples=40, strength=1.0, min_ao=0.18, ground_z=0.0, ground=True,
            gamma=1.0, two_sided_mats=None, seed=7, name="AO", inset=0.18, verbose=True):
    """objs: {name: object}. occluders: {name: [names of objects that shade it]} (the object itself is always
    included). Writes a FLOAT_COLOR corner attribute `name` (white = open) and makes it active.
    ground: an analytic plane at ground_z darkens points above it (points below it ignore it)."""
    two_sided_mats = set(two_sided_mats or DOUBLE_SIDED)
    rng = random.Random(seed)
    base_dirs = _hemisphere(samples)
    cache = {}
    t0 = time.time()
    total = 0
    for oname, ob in objs.items():
        if ob.type != "MESH" or len(ob.data.polygons) == 0:
            continue
        occ = [oname] + [n for n in occluders.get(oname, []) if n != oname and n in objs]
        key = tuple(sorted(set(occ)))
        if key not in cache:
            cache[key] = build_bvh([objs[n] for n in key])
        bvh = cache[key]
        me = ob.data
        mw = ob.matrix_world
        rot = mw.to_3x3()
        nverts = [mw @ v.co for v in me.vertices]
        loops_v = [0] * len(me.loops)
        me.loops.foreach_get("vertex_index", loops_v)
        cn = [0.0] * (len(me.loops) * 3)
        me.corner_normals.foreach_get("vector", cn)
        mat_names = [m.name if m else "" for m in me.materials]
        vals = [1.0] * len(me.loops)
        embedded = [False] * len(me.loops)
        for poly in me.polygons:
            ls, lt = poly.loop_start, poly.loop_total
            pv = [nverts[loops_v[li]] for li in range(ls, ls + lt)]
            centre = sum(pv, Vector((0, 0, 0))) / lt
            fn = (rot @ poly.normal).normalized()
            two = mat_names[poly.material_index] in two_sided_mats if mat_names else False
            for k, li in enumerate(range(ls, ls + lt)):
                p = pv[k] + (centre - pv[k]) * inset
                sides = (fn, -fn) if two else (fn,)
                acc, backs, cnt = 0.0, 0, 0
                for nrm in sides:
                    o = p + nrm * 0.004
                    u, v, w = _basis(nrm)
                    phi = rng.uniform(0.0, 2 * pi)
                    cp, sp = cos(phi), sin(phi)
                    uu = u * cp + v * sp
                    vv = v * cp - u * sp
                    for (dx, dy, dz) in base_dirs:
                        d = uu * dx + vv * dy + w * dz
                        hit = False
                        loc, hn, hi, hd = bvh.ray_cast(o, d, dist)
                        if loc is not None:
                            hit = True
                            if hn.dot(d) > 0.0:
                                backs += 1
                        if ground and o.z > ground_z + 1e-4 and d.z < -1e-6:
                            t = (ground_z - o.z) / d.z
                            if t < dist and (not hit or t < hd):
                                hd = t
                                hit = True
                        if hit:
                            q = hd / dist
                            acc += 1.0 - q * q
                        cnt += 1
                total += cnt
                occ_v = acc / max(1, cnt)
                if backs > 0.55 * cnt:
                    embedded[li] = True
                vals[li] = max(min_ao, 1.0 - strength * occ_v) ** gamma
        # embedded corners (inside another solid): half of the visible corners of the same face
        for poly in me.polygons:
            ls, lt = poly.loop_start, poly.loop_total
            vis = [vals[li] for li in range(ls, ls + lt) if not embedded[li]]
            ref = sum(vis) / len(vis) if vis else 1.0
            for li in range(ls, ls + lt):
                if embedded[li]:
                    vals[li] = max(min_ao, 0.55 * ref)
        # smooth: corners that share a vertex and a corner normal get the mean value
        groups = {}
        for li in range(len(me.loops)):
            k = (loops_v[li], round(cn[3 * li], 2), round(cn[3 * li + 1], 2), round(cn[3 * li + 2], 2))
            groups.setdefault(k, []).append(li)
        for lis in groups.values():
            if len(lis) > 1:
                m = sum(vals[li] for li in lis) / len(lis)
                for li in lis:
                    vals[li] = m
        attr = me.color_attributes.get(name) or me.color_attributes.new(name=name, type="FLOAT_COLOR", domain="CORNER")
        flat = []
        for val in vals:
            flat.extend((val, val, val, 1.0))
        attr.data.foreach_set("color", flat)
        me.color_attributes.active_color = attr
        try:
            me.color_attributes.render_color_index = list(me.color_attributes).index(attr)
        except Exception:
            pass
        me.update()
    if verbose:
        print("    AO: %d rays in %.1f s" % (total, time.time() - t0))


def default_occluders(names, optional_prefixes=("L2", "L3", "L4", "L5", "Rotor", "Damage", "Scaffold", "Stage")):
    """Main objects shade everything. Optional objects (shown or hidden by the game) shade only themselves;
    level parts are also shaded by the lower level parts (L3 is only visible together with L2)."""
    def optional(n):
        return any(n.startswith(p) for p in optional_prefixes)
    main = [n for n in names if not optional(n)]
    out = {}
    for n in names:
        occ = list(main)
        if n in ("L3", "L4", "L5"):
            lv = int(n[1])
            occ += ["L%d" % k for k in range(2, lv)]
        out[n] = occ
    return out


# --------------------------------------------------------------------------------------
# Export and read back
# --------------------------------------------------------------------------------------
def export_glb_atomic(path):
    tmp = path[:-4] + ".tmp.glb"
    if os.path.exists(tmp):
        os.remove(tmp)
    bpy.ops.export_scene.gltf(
        filepath=tmp,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_skins=False,
        export_morph=False,
        export_extras=False,
        export_materials="EXPORT",
        export_normals=True,
        export_tangents=False,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=True,
    )
    os.replace(tmp, path)


def read_glb(path):
    with open(path, "rb") as fh:
        magic, version, length = struct.unpack("<4sII", fh.read(12))
        assert magic == b"glTF", "not a GLB file"
        clen, ctype = struct.unpack("<II", fh.read(8))
        js = json.loads(fh.read(clen).decode("utf-8"))
        rest = fh.read()
    binary = b""
    if len(rest) >= 8:
        blen, btype = struct.unpack("<II", rest[:8])
        binary = rest[8:8 + blen]
    return js, binary


def inspect_glb(path):
    """Facts read back out of the exported file (not out of the Blender scene)."""
    g, _ = read_glb(path)
    scene = g["scenes"][g.get("scene", 0)]
    nodes = g.get("nodes", [])
    top = [nodes[i].get("name") for i in scene["nodes"]]
    tris, mats_by_obj, color0 = {}, {}, {}
    mats_used = set()
    for i in scene["nodes"]:
        n = nodes[i]
        count = 0
        names = set()
        has_c = True
        if "mesh" in n:
            for prim in g["meshes"][n["mesh"]]["primitives"]:
                acc = g["accessors"][prim["indices"]] if "indices" in prim else g["accessors"][prim["attributes"]["POSITION"]]
                count += acc["count"] // 3
                if "material" in prim:
                    nm = g["materials"][prim["material"]]["name"]
                    mats_used.add(nm)
                    names.add(nm)
                if "COLOR_0" not in prim["attributes"]:
                    has_c = False
            color0[n.get("name")] = has_c
        tris[n.get("name")] = count
        mats_by_obj[n.get("name")] = sorted(names)
    alpha = {m["name"]: m.get("alphaMode", "OPAQUE") for m in g.get("materials", [])}
    return dict(
        top=top, tris=tris, materials=sorted(mats_used), mats_by_obj=mats_by_obj, alpha=alpha, color0=color0,
        mesh_nodes=[nodes[i].get("name") for i in scene["nodes"] if "mesh" in nodes[i]],
        empties=[nodes[i].get("name") for i in scene["nodes"] if "mesh" not in nodes[i]],
        has_cameras="cameras" in g, has_animations="animations" in g, has_skins="skins" in g,
        has_lights="KHR_lights_punctual" in g.get("extensions", {}),
        child_nodes=any("children" in nodes[i] for i in scene["nodes"]),
        translations={nodes[i].get("name"): nodes[i].get("translation") for i in scene["nodes"]},
        has_images="images" in g,
    )


# --------------------------------------------------------------------------------------
# Build driver
# --------------------------------------------------------------------------------------
def part_stats(part):
    tris = sum(len(f) - 2 for f in part.faces)
    if not part.verts:
        return dict(tris=0, bbox=((0, 0, 0), (0, 0, 0)), radius=0.0, radius_overhang=0.0)
    xs = [v.x for v in part.verts]; ys = [v.y for v in part.verts]; zs = [v.z for v in part.verts]
    rad = max((math.hypot(v.x, v.y) for v, o in zip(part.verts, part.vover) if not o), default=0.0)
    rad_over = max((math.hypot(v.x, v.y) for v, o in zip(part.verts, part.vover) if o), default=0.0)
    return dict(tris=tris, bbox=((min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))), radius=rad,
                radius_overhang=rad_over)


LEVEL_PARTS = ("L2", "L3", "L4", "L5")


def service_anchor(parts):
    """Kneel point in front of the +X face of the Base (the service panel is 0.45 m ahead at 0.40 m)."""
    base = [p for p in parts if p.name in ("Base", "Turret")]
    for (zlo, zhi, yw) in ((0.15, 0.90, 0.35), (0.10, 1.40, 0.80), (0.0, 3.0, 1.60)):
        xs = [v.x for p in base for v in p.verts if zlo <= v.z <= zhi and abs(v.y) <= yw]
        if xs:
            return Anchor("Service", (max(xs) + 0.45, 0.0, 0.0), forward=(-1, 0, 0))
    return None


def build_model(spec, builder):
    """spec keys: id, kind, footprint (m or None), accent (category or None), produce (hex or None),
    objects (expected top-level mesh names), anchors (expected empty names), budget (triangles),
    overhang (m, for Part.overhang geometry), free ({object: extra metres allowed beyond footprint}),
    ao (dict of bake_ao arguments), zmin, file (output name without .glb; default id), also (extra copies)."""
    t0 = time.time()
    reset_scene()
    out = builder(spec)
    parts = [p for p in out if isinstance(p, Part)]
    anchors = [a for a in out if isinstance(a, Anchor)]
    # 3.0 (docs/V3_DESIGN.md section 6): every exterior machine has Anchor_Service, a kneel point 0.45 m in front of
    # its front (+X) face at panel height (0.40); the person faces the machine (-X).
    if spec.get("kind") == "exterior" and spec.get("service", True) and not any(a.name == "Service" for a in anchors):
        sa = service_anchor(parts)
        if sa is not None:
            anchors.append(sa)
            spec = dict(spec)
            spec["anchors"] = list(spec.get("anchors", [])) + ["Anchor_Service"]
    mset = MaterialSet(ACCENTS.get(spec.get("accent")) if spec.get("accent") else None, spec.get("produce"))
    objs = {}
    for part in parts:
        if not part.faces:
            print("    WARNING: empty part", part.name)
            continue
        objs[part.name] = part_to_object(part, mset)
    for a in anchors:
        anchor_to_object(a)
    bpy.context.view_layer.update()
    ao = dict(spec.get("ao", {}))
    occ = ao.pop("occluders", None) or default_occluders(list(objs.keys()))
    bake_ao(objs, occ, **ao)
    name = spec.get("file", spec["id"])
    os.makedirs(MODEL_DIR, exist_ok=True)
    path = os.path.join(MODEL_DIR, name + ".glb")
    export_glb_atomic(path)
    for extra in spec.get("also", []):
        export_glb_atomic(os.path.join(MODEL_DIR, extra + ".glb"))

    flags = []
    stats = {p.name: part_stats(p) for p in parts if p.faces}
    tris = sum(s["tris"] for s in stats.values())
    base_tris = sum(s["tris"] for n, s in stats.items() if n not in LEVEL_PARTS)
    mins = [min(s["bbox"][0][i] for s in stats.values()) for i in range(3)]
    maxs = [max(s["bbox"][1][i] for s in stats.values()) for i in range(3)]
    free = spec.get("free", {})
    radius = max((s["radius"] for n, s in stats.items() if n not in free), default=0.0)
    radius_over = max((s["radius_overhang"] for n, s in stats.items() if n not in free), default=0.0)
    info = inspect_glb(path)
    if sorted(info["mesh_nodes"]) != sorted(spec["objects"]):
        flags.append("mesh objects %s != %s" % (sorted(info["mesh_nodes"]), sorted(spec["objects"])))
    if sorted(info["empties"]) != sorted(spec.get("anchors", [])):
        flags.append("empties %s != %s" % (sorted(info["empties"]), sorted(spec.get("anchors", []))))
    missing_c = [n for n, ok in info["color0"].items() if not ok]
    if missing_c:
        flags.append("no COLOR_0 on %s" % missing_c)
    if info["child_nodes"]:
        flags.append("exported nodes have children")
    for key in ("has_cameras", "has_animations", "has_skins", "has_lights", "has_images"):
        if info[key]:
            flags.append(key)
    glb_tris = sum(info["tris"].values())
    if glb_tris != tris:
        flags.append("GLB triangles %d != built %d" % (glb_tris, tris))
    unknown = [m for m in info["materials"] if m not in PER_FILE and m not in MATERIALS]
    if unknown:
        flags.append("unknown materials %s" % unknown)
    if "Glass" in info["alpha"] and info["alpha"]["Glass"] != "BLEND":
        flags.append("Glass alphaMode is %s" % info["alpha"]["Glass"])
    if spec.get("accent") and spec.get("kind") in ("exterior", "special") and "Accent" not in info["materials"]:
        flags.append("no Accent detail")
    if tris > spec["budget"]:
        flags.append("over triangle budget %d" % spec["budget"])
    fp = spec.get("footprint")
    if fp:
        if radius > fp + 1e-4:
            flags.append("EXCEEDS FOOTPRINT: r=%.3f > %.2f" % (radius, fp))
        if radius_over > fp + spec.get("overhang", 0.0) + 1e-4:
            flags.append("overhang parts exceed footprint + %.1f: r=%.3f" % (spec.get("overhang", 0.0), radius_over))
        for n, extra in free.items():
            if n in stats:
                r = max(stats[n]["radius"], stats[n]["radius_overhang"])
                if r > fp + extra + 1e-4:
                    flags.append("%s exceeds footprint + %.1f: r=%.3f" % (n, extra, r))
    if mins[2] < spec.get("zmin", -0.30) - 1e-4:
        flags.append("goes below z=%.2f (z min %.3f)" % (spec.get("zmin", -0.30), mins[2]))
    for chk in spec.get("checks", []):
        msg = chk(stats)
        if msg:
            flags.append(msg)
    row = dict(
        id=name, kind=spec.get("kind"), footprint=fp, tris=tris, tris_base=base_tris, budget=spec["budget"],
        tris_by_object={n: s["tris"] for n, s in stats.items()},
        bbox_min=[round(v, 3) for v in mins], bbox_max=[round(v, 3) for v in maxs],
        max_radius=round(radius, 3), max_radius_overhang=round(radius_over, 3),
        max_radius_free={n: round(max(stats[n]["radius"], stats[n]["radius_overhang"]), 3) for n in free if n in stats},
        file_size=os.path.getsize(path), objects=info["top"], materials=info["materials"],
        color0=all(info["color0"].values()), flags=flags, seconds=round(time.time() - t0, 1),
        also=spec.get("also", []),
    )
    print("  %-26s %6d tris  r=%.2f/%s  %s" % (name, tris, radius, fp, "; ".join(flags) or "ok"))
    return row


def write_reports(rows, notes=None):
    existing = {}
    if os.path.exists(REPORT_JSON):
        try:
            with open(REPORT_JSON, "r", encoding="utf-8") as fh:
                existing = {r["id"]: r for r in json.load(fh)["models"]}
        except Exception:
            existing = {}
    for r in rows:
        existing[r["id"]] = r
    order = ["meridian", "debris", "colonist", "crop_", "solar_array", "wind_turbine", "battery", "water_extractor",
             "reservoir", "regolith_harvester", "fuel_refinery", "fusion_reactor", "deep_drill", "comms_tower",
             "lander", "landing_pad", "supply_pod", "crate_", "rock_", "pebbles"]

    def key(r):
        for k, o in enumerate(order):
            if r["id"].startswith(o):
                return (k, r["id"])
        return (len(order), r["id"])
    ordered = sorted(existing.values(), key=key)
    with open(REPORT_JSON, "w", encoding="utf-8") as fh:
        json.dump(dict(blender=bpy.app.version_string, models=ordered), fh, indent=1)
    return ordered
