"""
Frontier Habitat - procedural 3D asset builder (Blender 5.2, Python / bpy).

VERSION 2.0 NOTE: this file is now the shared geometry library (Part, materials) of the v1 generator.
A plain run builds the 2.0 ROOM buildings through tools/blender/rooms_build.py (same arguments).
The v1 builders stay here for reference; run one only with --legacy-v1 --only <id>.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/build_assets.py -- [--only id1,id2] [--list]

Every model is made from code. No file is downloaded. No image texture is used.
Output: assets/models/<id>.glb (binary glTF, +Y up) and tools/blender/build_report.{json,md}.

Conventions (the Godot code depends on these):
  * metres, Blender Z up, model origin at ground level at the footprint centre
  * front = Blender +X  (glTF/Godot: +X).  Blender (x, y, z) -> glTF (x, z, -y)
  * rooms export the objects Base / Roof / Interior, exterior structures export Base (+ extras)
  * fixed material names (see MATERIALS), `Accent` changes colour per file
"""
import bpy
import bmesh
import sys
import os
import json
import math
import struct
import random
import time
import warnings
from contextlib import contextmanager
from math import sin, cos, pi, radians, degrees, sqrt, atan2, asin
from mathutils import Matrix, Vector

warnings.filterwarnings("ignore", category=DeprecationWarning)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models")
REPORT_JSON = os.path.join(HERE, "build_report.json")
REPORT_MD = os.path.join(HERE, "build_report.md")

# --------------------------------------------------------------------------------------
# Colours and materials
# --------------------------------------------------------------------------------------
ACCENTS = {
    "life_support": "#29b6c6",
    "food": "#6abf4b",
    "housing": "#f2c14e",
    "industry": "#e07a3a",
    "logistics": "#9b6bd6",
    "utilities": "#4a90d9",
    "medical": "#e85d75",
    "comfort": "#f08fc0",
    "science": "#7c8cff",       # 2.0
    "space": "#c9d3e0",         # 2.0
}

# name -> colour (sRGB hex) and Principled BSDF values.  Names are a contract with the game.
MATERIALS = {
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
    # colonist only
    "SuitMain":   dict(color="#e8eaed", rough=0.70),
    "SuitAccent": dict(color="#ff9f1c", rough=0.60),
    "Visor":      dict(color="#2a3140", metal=0.90, rough=0.15),
    "Pack":       dict(color="#7d8590", rough=0.60),
    # 2.0 (docs/AAA_DESIGN.md section 11). "Neon" is per file (category colour, emissive 3), like "Accent".
    "Trim":       dict(color="#b8c2cc", metal=0.85, rough=0.30),
    "L3Band":     dict(color="#3ee0ff", rough=0.40, emit="#3ee0ff", emit_strength=1.2),
    "L4Band":     dict(color="#a78bfa", rough=0.40, emit="#a78bfa", emit_strength=1.2),
    "L5Gold":     dict(color="#ffd166", metal=0.90, rough=0.30, emit="#ffd166", emit_strength=0.6),
    "Frost":      dict(color="#ddefff", rough=0.50),
    "Glow":       dict(color="#9cffb0", rough=0.40, emit="#9cffb0", emit_strength=3.0),
    "Plasma":     dict(color="#8fd8ff", rough=0.30, emit="#8fd8ff", emit_strength=5.0),
    # 3.0 (docs/V3_DESIGN.md section 7.3): bright modern interiors
    # 3.0 draw-call budget (RENDER): the Interior merges its plain materials into two palette materials; the
    # colour of every face is in its vertex colour (COLOR_0 = colour x baked AO).  Base colour white.
    "Palette":    dict(color="#ffffff", rough=0.70),
    # 3.1 door and airlock status lights (RENDER switches their colour)
    "StatusGreen": dict(color="#5ee07a", rough=0.30, emit="#5ee07a", emit_strength=3.0),
    "BeaconAmber": dict(color="#ffb020", rough=0.30, emit="#ffb020", emit_strength=3.0),
    # lounge seating (critic round 8): lighter than Cushion so it reads at the game camera; they merge into Palette
    "CushionLight": dict(color="#7d93b4", rough=0.90),
    "RugLight":   dict(color="#b4bfcc", rough=0.95),
    "PaletteMetal": dict(color="#ffffff", metal=0.60, rough=0.45),
    "LightStrip": dict(color="#eaf6ff", rough=0.30, emit="#eaf6ff", emit_strength=2.5),
    "Screen":     dict(color="#123c4c", rough=0.25, emit="#2fb8d8", emit_strength=0.45),
    "Wood":       dict(color="#b08560", rough=0.55),
    "Cushion":    dict(color="#3c4a5e", rough=0.90),
    "Floor":      dict(color="#d9d4cb", rough=0.65),
    "FloorDark":  dict(color="#6b6f76", rough=0.70),
}

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
        # BLENDED render method -> the glTF exporter writes alphaMode BLEND
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    # single-sided everywhere (glTF doubleSided=false) except thin leaves
    mat.use_backface_culling = not spec.get("double_sided", False)
    mat.diffuse_color = (*rgb, alpha)
    mat.metallic = spec.get("metal", 0.0)
    mat.roughness = spec.get("rough", 0.5)
    return mat


class MaterialSet:
    """One set per exported file, so `Accent` can change colour per file."""

    def __init__(self, accent_hex):
        self.accent_hex = accent_hex
        self.cache = {}

    def get(self, name):
        if name not in self.cache:
            if name == "Accent":
                if not self.accent_hex:
                    raise ValueError("this model has no accent colour but uses the Accent material")
                spec = dict(color=self.accent_hex, rough=0.55)
            elif name == "Neon":
                if not self.accent_hex:
                    raise ValueError("this model has no accent colour but uses the Neon material")
                spec = dict(color=self.accent_hex, rough=0.40, emit=self.accent_hex, emit_strength=3.0)
            else:
                spec = MATERIALS[name]
            self.cache[name] = make_material(name, spec)
        return self.cache[name]


# --------------------------------------------------------------------------------------
# Transform helpers
# --------------------------------------------------------------------------------------
def T(x=0.0, y=0.0, z=0.0):
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
# Part: accumulates the geometry of ONE exported object
# --------------------------------------------------------------------------------------
class Part:
    def __init__(self, name, origin=(0.0, 0.0, 0.0)):
        self.name = name
        self.origin = Vector(origin)      # object origin (world). Mesh data is stored relative to it.
        self.verts = []
        self.vover = []                   # per vertex: True = allowed to overhang the footprint
        self.faces = []
        self.fmat = []
        self.fsmooth = []
        self._stack = [Matrix.Identity(4)]
        self._flip = False
        self.overhang = False

    # ---- transform stack ------------------------------------------------------------
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

    # ---- raw geometry ---------------------------------------------------------------
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

    def convex(self, pts, faces, mat, smooth=False, mats=None):
        """Add a convex solid. Face winding is fixed automatically (normal away from the centroid)."""
        vs = [Vector(p) for p in pts]
        c = sum(vs, Vector((0, 0, 0))) / len(vs)
        ids = [self.v(p) for p in vs]
        for k, face in enumerate(faces):
            fv = [vs[i] for i in face]
            n = Vector((0, 0, 0))
            for a in range(len(fv)):                      # Newell normal
                p, q = fv[a], fv[(a + 1) % len(fv)]
                n += Vector(((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y)))
            fc = sum(fv, Vector((0, 0, 0))) / len(fv)
            order = list(face) if n.dot(fc - c) >= 0 else list(reversed(face))
            m = mats[k] if mats and mats[k] else mat
            self.f([ids[i] for i in order], m, smooth)

    # ---- loft: the base of most primitives ---------------------------------------------
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

    # ---- surface of revolution about local Z ------------------------------------------
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
        """Flat painted ring that faces up."""
        self.lathe([(r_out, z), (r_in, z)], mat, seg=seg, smooth=False, a0=a0, a1=a1, caps=False)

    def disc(self, r, z, mat, seg=24):
        self.lathe([(r, z), (0.0, z)], mat, seg=seg, smooth=False)

    def torus(self, R, r, mat, seg=24, tseg=8, z=0.0, smooth=True):
        prof = [(R + r * cos(2 * pi * k / tseg), z + r * sin(2 * pi * k / tseg)) for k in range(tseg)]
        self.lathe(prof, mat, seg=seg, smooth=smooth, wrap=True)

    def sphere(self, c, r, mat, seg=12, rings=6, smooth=True, scale=(1.0, 1.0, 1.0)):
        prof = [(r * cos(radians(-90 + 180 * k / rings)), r * sin(radians(-90 + 180 * k / rings)))
                for k in range(rings + 1)]
        prof[0] = (0.0, -r)
        prof[-1] = (0.0, r)
        with self.at(T(*c), S(*scale)):
            self.lathe(prof, mat, seg=seg, smooth=smooth)

    # ---- cylinder / cone between two points ---------------------------------------------
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

    # ---- pipe along a polyline (exact mitre joints) ----------------------------------------
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
                o = o - t_in * (o.dot(b) / max(t_in.dot(b), 0.2))   # project on the mitre plane
                ring.append(tuple(p + o))
            rings.append(ring)
            if j > 0 and j < len(dirs):
                u = q @ u
                v = q @ v
        self.loft(rings, mat, smooth, closed=True, cap0=caps, cap1=caps)

    # ---- rectangular beam between two points --------------------------------------------------
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

    def beam_path(self, pts, w, h=None, mat="Frame", up=(0, 0, 1)):
        """Rectangular section swept along a polyline. `up` may be one vector or a function of the point."""
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
        self.loft(rings, mat, False, closed=True, cap0=True, cap1=True)

    # ---- boxes ---------------------------------------------------------------------------------
    def box(self, c, s, mat, bevel=0.0, mats=None, smooth=False):
        """c = centre, s = size. mats = optional {'+x': name, '-z': name, ...} per main face."""
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        mats = mats or {}
        if bevel <= 0:
            P = [(cx + sx * hx, cy + sy * hy, cz + sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
            # index = ix*4 + iy*2 + iz
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
            faces.append([index[("x", s_, a, b_)] for a, b_ in cyc]); fm.append(mats.get("+x" if s_ > 0 else "-x"))
            faces.append([index[("y", a, s_, b_)] for a, b_ in cyc]); fm.append(mats.get("+y" if s_ > 0 else "-y"))
            faces.append([index[("z", a, b_, s_)] for a, b_ in cyc]); fm.append(mats.get("+z" if s_ > 0 else "-z"))
        edge_mat = mats.get("edge")
        for a in (-1, 1):
            for b_ in (-1, 1):
                faces.append([index[("x", a, b_, -1)], index[("y", a, b_, -1)], index[("y", a, b_, 1)], index[("x", a, b_, 1)]]); fm.append(edge_mat)
                faces.append([index[("x", a, -1, b_)], index[("z", a, -1, b_)], index[("z", a, 1, b_)], index[("x", a, 1, b_)]]); fm.append(edge_mat)
                faces.append([index[("y", -1, a, b_)], index[("z", -1, a, b_)], index[("z", 1, a, b_)], index[("y", 1, a, b_)]]); fm.append(edge_mat)
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    faces.append([index[("x", sx, sy, sz)], index[("y", sx, sy, sz)], index[("z", sx, sy, sz)]]); fm.append(edge_mat)
        self.convex(pts, faces, mat, smooth, mats=fm)

    def box0(self, x, y, z0, sx, sy, sz, mat, **kw):
        """Box that stands on z0 (centre x, y)."""
        self.box((x, y, z0 + sz / 2), (sx, sy, sz), mat, **kw)

    # ---- prisms -----------------------------------------------------------------------------------
    def prism(self, poly, z0, z1, mat, cap_mat=None, cap0=True, cap1=True, smooth=False):
        """Extrude a 2D polygon (x, y) along local Z. Winding is fixed automatically."""
        area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                   for i in range(len(poly)))
        if area < 0:
            poly = list(reversed(poly))
        rings = [[(x, y, z0) for x, y in poly], [(x, y, z1) for x, y in poly]]
        self.loft(rings, mat, smooth, closed=True, cap0=cap0, cap1=cap1, cap_mat=cap_mat)

    def prism_y(self, poly_xz, y0, y1, mat, **kw):
        """Polygon in the XZ plane, extruded along Y from y0 to y1."""
        with self.at(RX(90)):
            self.prism([(x, z) for x, z in poly_xz], -y1, -y0, mat, **kw)

    def prism_x(self, poly_yz, x0, x1, mat, **kw):
        """Polygon in the YZ plane, extruded along X from x0 to x1."""
        m = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        with self.at(m):
            self.prism(poly_yz, x0, x1, mat, **kw)

    # ---- a patch draped over a height function (painted markings on domes) ---------------------------
    def drape(self, x0, x1, y0, y1, zfun, mat, nx=6, ny=2, offset=0.03, smooth=True):
        ids = [[self.v((x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny,
                        zfun(x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny) + offset))
                for j in range(ny + 1)] for i in range(nx + 1)]
        for i in range(nx):
            for j in range(ny):
                self.f([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], mat, smooth)

    # ---- convex hull rock ---------------------------------------------------------------------------------
    def hull(self, pts, mat, vein=None, vein_mat="OreVein", vein_max=5):
        """Convex hull of a point cloud. vein = (point, normal, half_width): the faces nearest to that plane
        (inside the slab, at most vein_max of them) get vein_mat."""
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
        self.convex(vs, faces, mat, False, mats=fm)


def dome_profile(radius, z0, top, rings, t0=0.0, t1=90.0):
    """Quarter ellipse from (radius, z0) up to (0, top)."""
    pts = []
    for j in range(rings + 1):
        t = radians(t0 + (t1 - t0) * j / rings)
        pts.append((radius * cos(t), z0 + (top - z0) * sin(t)))
    return pts


# --------------------------------------------------------------------------------------
# Scene handling, export, checks
# --------------------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
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
    # Order matters in Blender 5: set_sharp_from_angle() DELETES the `sharp_face` attribute, and
    # polygons.foreach_set("use_smooth") does nothing while that attribute is missing.
    # So: mark sharp edges first, then write the flat/smooth flag per face into the attribute itself.
    mesh.set_sharp_from_angle(angle=radians(SHARP_ANGLE))
    attr = mesh.attributes.get("sharp_face") or mesh.attributes.new("sharp_face", "BOOLEAN", "FACE")
    attr.data.foreach_set("value", [not s for s in part.fsmooth])
    mesh.update()
    got = sum(1 for poly in mesh.polygons if poly.use_smooth)
    if got != sum(1 for s in part.fsmooth if s):
        print("    WARNING: smooth flags of %s did not stick (%d of %d)" % (part.name, got, sum(part.fsmooth)))
    obj = bpy.data.objects.new(part.name, mesh)
    obj.location = part.origin
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export_glb(path):
    bpy.ops.export_scene.gltf(
        filepath=path,
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
        export_vertex_color="NONE",
    )


def read_glb_json(path):
    with open(path, "rb") as fh:
        magic, version, length = struct.unpack("<4sII", fh.read(12))
        assert magic == b"glTF", "not a GLB file"
        clen, ctype = struct.unpack("<II", fh.read(8))
        return json.loads(fh.read(clen).decode("utf-8"))


def inspect_glb(path):
    """Read facts back out of the exported file (not out of the Blender scene)."""
    g = read_glb_json(path)
    scene = g["scenes"][g.get("scene", 0)]
    nodes = g.get("nodes", [])
    top = [nodes[i].get("name") for i in scene["nodes"]]
    tris = {}
    mats_used = set()
    for i in scene["nodes"]:
        n = nodes[i]
        count = 0
        if "mesh" in n:
            for prim in g["meshes"][n["mesh"]]["primitives"]:
                acc = g["accessors"][prim["indices"]] if "indices" in prim else g["accessors"][prim["attributes"]["POSITION"]]
                count += acc["count"] // 3
                if "material" in prim:
                    mats_used.add(g["materials"][prim["material"]]["name"])
        tris[n.get("name")] = count
    alpha = {m["name"]: m.get("alphaMode", "OPAQUE") for m in g.get("materials", [])}
    return dict(
        top=top, tris=tris, materials=sorted(mats_used), alpha=alpha,
        has_cameras="cameras" in g, has_animations="animations" in g, has_skins="skins" in g,
        has_lights="KHR_lights_punctual" in g.get("extensions", {}),
        child_nodes=any("children" in nodes[i] for i in scene["nodes"]),
        translations={nodes[i].get("name"): nodes[i].get("translation") for i in scene["nodes"]},
        has_images="images" in g,
    )


# --------------------------------------------------------------------------------------
# Rooms: shared shell (Base / Roof / Interior)
# --------------------------------------------------------------------------------------
FLOOR_Z = 0.14      # top of the floor in every room and in the corridor
WALL_TOP = 1.40     # the round wall (Base) stops here, the Roof starts here
WALL_T = 0.18


class Room:
    def __init__(self, spec):
        self.spec = spec
        R = spec["footprint"]
        self.R = R
        self.Rf = R - 0.10                        # foundation ring (largest radius of the model)
        self.Rw = spec.get("wall_r", R - 0.45)    # outer wall radius
        self.Ri = self.Rw - WALL_T                # inner wall radius
        self.H = spec["height"]
        self.Hv = spec.get("dome_apex", self.H)   # apex of the ellipse (higher than H when the dome is cut flat)
        self.seg = spec.get("seg", 32)
        self.base = Part("Base")
        self.roof = Part("Roof")
        self.interior = Part("Interior")

    def parts(self):
        return [self.base, self.roof, self.interior]

    # ---- dome maths ------------------------------------------------------------------------
    def dome_z(self, r):
        r = min(abs(r), self.Rw)
        return WALL_TOP + (self.Hv - WALL_TOP) * sqrt(max(0.0, 1.0 - (r / self.Rw) ** 2))

    def dome_at(self, x, y):
        return self.dome_z(math.hypot(x, y))

    def dome_point(self, t_deg, ang_deg):
        """Point and outward normal on the dome. t = 0 at the wall, 90 at the apex."""
        t, a = radians(t_deg), radians(ang_deg)
        h = self.Hv - WALL_TOP
        r, z = self.Rw * cos(t), WALL_TOP + h * sin(t)
        nr, nz = h * cos(t), self.Rw * sin(t)
        ln = math.hypot(nr, nz)
        return Vector((r * cos(a), r * sin(a), z)), Vector((nr / ln * cos(a), nr / ln * sin(a), nz / ln))

    def dome_normal_at(self, x, y):
        r = min(math.hypot(x, y), self.Rw * 0.999)
        t = degrees(math.acos(r / self.Rw))
        return self.dome_point(t, degrees(atan2(y, x)))[1]

    # ---- Base: foundation ring, floor, round wall with the accent band ---------------------------
    def build_base(self, gap=None):
        b, seg = self.base, self.seg
        Rf, Rw, Ri = self.Rf, self.Rw, self.Ri
        b.lathe([(Rf, -0.25), (Rf, 0.05), (Rf - 0.09, FLOOR_Z), (Rw - 0.02, FLOOR_Z)], "Frame", seg=seg)
        b.lathe([(Ri + 0.02, FLOOR_Z), (0.0, FLOOR_Z)], "HullDark", seg=seg, smooth=False)
        prof = [(Rw, FLOOR_Z), (Rw, 0.96), (Rw + 0.06, 1.02), (Rw + 0.06, 1.24), (Rw, 1.30),
                (Rw, WALL_TOP), (Ri, WALL_TOP), (Ri, FLOOR_Z)]
        mats = ["Hull", "Accent", "Accent", "Accent", "Hull", "Hull", "Hull"]
        if gap:
            b.lathe(prof, lambda k, i: mats[k], seg=seg, a0=gap, a1=360.0 - gap, cap_mat="Hull")
        else:
            b.lathe(prof, lambda k, i: mats[k], seg=seg)

    # ---- Roof: dome shell + dark seal ring ----------------------------------------------------------
    def build_dome(self, mat=None, rings=7, smooth=True, t1=90.0, flat_top=False, seal=True):
        prof = dome_profile(self.Rw, WALL_TOP, self.Hv, rings, t1=t1)
        if flat_top:
            prof.append((0.0, prof[-1][1]))
        fn = mat or (lambda k, i: "Accent" if k == 1 else "Hull")
        self.roof.lathe(prof, fn, seg=self.seg, smooth=smooth)
        if seal:
            self.roof.lathe([(self.Rw + 0.10, WALL_TOP - 0.01), (self.Rw + 0.10, WALL_TOP + 0.10),
                             (self.Rw - 0.03, WALL_TOP + 0.18)], "Frame", seg=self.seg)

    def porthole(self, part, pos, nor, r, rim=0.08, depth=0.10, seg=12, glow="Window"):
        part.cyl(pos - nor * 0.15, pos + nor * depth, r + rim, seg=seg, mat="Frame", cap0=False)
        part.cyl(pos, pos + nor * (depth + 0.02), r, seg=seg, mat=None, cap_mat=glow, cap0=False)


# ---- small furniture helpers ------------------------------------------------------------------------
def crate_prop(p, x, y, z0, size=0.6, mat="Cargo", band="Frame", rot=0.0, bevel=True):
    with p.at(T(x, y, z0), RZ(rot)):
        p.box0(0, 0, 0, size, size, size, mat, bevel=size * 0.08 if bevel else 0.0, mats={"-z": None})
        p.box0(0, 0, size * 0.36, size * 1.03, size * 1.03, size * 0.22, band, mats={"-z": None, "+z": None} if not bevel else None)


def stool(p, x, y, z0=None, top="Accent"):
    z0 = FLOOR_Z if z0 is None else z0
    p.vcyl(x, y, z0, z0 + 0.40, 0.10, seg=8, mat="Frame", cap1=False)
    p.vcyl(x, y, z0 + 0.40, z0 + 0.48, 0.19, seg=10, mat=top)


def round_table(p, x, y, r, h, z0=None, top="Hull"):
    z0 = FLOOR_Z if z0 is None else z0
    p.vcyl(x, y, z0, z0 + 0.06, r * 0.5, seg=10, mat="Frame")
    p.vcyl(x, y, z0 + 0.06, z0 + h - 0.06, 0.09, seg=8, mat="Frame", cap0=False, cap1=False)
    p.vcyl(x, y, z0 + h - 0.06, z0 + h, r, seg=16, mat=top)


# --------------------------------------------------------------------------------------
# ROOMS
# --------------------------------------------------------------------------------------
def build_junction(spec):
    rm = Room(spec)
    rm.build_base()
    rm.build_dome(rings=6)
    r, n = rm.roof, rm.interior
    r.vcyl(0, 0, rm.H - 0.22, rm.H + 0.10, 0.62, seg=16, mat="HullDark")      # hub cap
    r.vcyl(0, 0, rm.H + 0.10, rm.H + 0.16, 0.45, seg=16, mat="Accent")
    z = FLOOR_Z + 0.012                                                        # floor marking
    n.ring_flat(1.05, 1.25, z, "Accent", seg=24)
    n.disc(0.32, z, "Accent", seg=12)
    for k in range(8):
        with n.at(RZ(45.0 * k)):
            n.box((0.72, 0, z), (0.34, 0.10, 0.004), "Hazard", mats={"-z": None})
    return rm.parts()


def _bunk(p):
    """Local +X points to the wall (head end). The bed is 2.0 x 0.9."""
    F = FLOOR_Z
    p.box0(0, 0, F, 2.0, 0.9, 0.30, "Frame")
    p.box0(0, 0, F + 0.30, 1.92, 0.82, 0.13, "Hull")
    p.box0(-0.38, 0, F + 0.29, 1.18, 0.86, 0.17, "Accent")
    p.box0(0.66, 0, F + 0.43, 0.40, 0.58, 0.08, "Hull", bevel=0.03)
    p.box0(1.04, 0, F, 0.08, 0.9, 0.80, "HullDark")


def build_habitat(spec):
    rm = Room(spec)
    rm.build_base()
    rm.build_dome(rings=7)
    b, r, n = rm.base, rm.roof, rm.interior
    for k in range(8):                                   # portholes in the wall
        a = 45.0 * k
        rm.porthole(b, Vector(polar(rm.Rw, a, 0.58)), Vector(polar(1.0, a, 0.0)), 0.22, rim=0.07, depth=0.07, seg=10)
    for k in range(8):                                   # large glowing portholes on the dome
        pos, nor = rm.dome_point(33.0, 22.5 + 45.0 * k)
        rm.porthole(r, pos, nor, 0.36, rim=0.10, depth=0.12, seg=12)
    r.vcyl(0, 0, rm.H - 0.30, rm.H + 0.12, 1.05, seg=20, mat="HullDark")
    r.disc(0.78, rm.H + 0.135, "Window", seg=20)
    r.vcyl(0, 0, rm.H + 0.12, rm.H + 0.20, 0.85, 0.80, seg=20, mat="Frame", cap1=False)
    # interior: eight bunks on a ring of radius 3.3 m at 22.5 + 45k degrees, heads at the wall
    for k in range(8):
        with n.at(RZ(22.5 + 45.0 * k), T(3.3, 0, 0)):
            _bunk(n)
    round_table(n, 0, 0, 0.70, 0.74)
    for k in range(4):
        x, y, _ = polar(1.12, 45.0 + 90.0 * k)
        stool(n, x, y)
    return rm.parts()


def build_oxygen_plant(spec):
    rm = Room(spec)
    rm.build_base()

    def roof_mat(k, i):
        if k == 1:
            return "Accent"
        if 2 <= k <= 4 and i % 4 != 3:
            return "Glass"
        return "Hull"
    rm.build_dome(mat=roof_mat, rings=7)
    r, n = rm.roof, rm.interior
    # exhaust stack with the accent band
    r.vcyl(0, 0, rm.H - 0.30, rm.H - 0.02, 0.85, 0.70, seg=16, mat="Frame")
    r.vcyl(0, 0, rm.H - 0.35, rm.H + 1.15, 0.46, 0.40, seg=16, mat="HullDark", cap1=False)
    r.vcyl(0, 0, rm.H + 0.45, rm.H + 0.80, 0.50, seg=16, mat="Accent")
    r.vcyl(0, 0, rm.H + 1.10, rm.H + 1.25, 0.50, seg=16, mat="Frame")
    r.disc(0.36, rm.H + 1.255, "Rubber", seg=16)
    # interior: three electrolysis tanks + manifold + console
    F = FLOOR_Z
    for a in (90.0, 210.0, 330.0):
        x, y, _ = polar(1.55, a)
        n.vcyl(x, y, F, F + 0.18, 0.62, seg=14, mat="Frame")
        n.vcyl(x, y, F + 0.18, F + 1.95, 0.52, seg=14, mat="Metal", cap1=False)
        n.vcyl(x, y, F + 0.75, F + 1.15, 0.545, seg=14, mat="WaterBlue", cap0=False, cap1=False)
        with n.at(T(x, y, F + 1.95)):
            n.lathe(dome_profile(0.52, 0.0, 0.30, 3), "Accent", seg=14)
        n.tube([(x, y, F + 2.2), (x, y, F + 2.55), (0, 0, F + 2.55)], 0.07, seg=6, mat="Metal", fillet=0.25)
    n.vcyl(0, 0, F, F + 2.75, 0.20, seg=10, mat="HullDark")
    n.vcyl(0, 0, F + 2.40, F + 2.70, 0.30, seg=10, mat="Accent")
    with n.at(RZ(30.0), T(2.35, 0, 0)):
        n.box0(0, 0, F, 0.5, 1.1, 0.95, "Hull", bevel=0.05)
        n.box((-0.2, 0, F + 1.0), (0.12, 0.9, 0.34), "Frame")
        n.box((-0.265, 0, F + 1.0), (0.01, 0.8, 0.26), "Window")
    return rm.parts()


def build_airlock(spec):
    rm = Room(dict(spec, wall_r=2.30))
    rm.Rf = 2.62
    Rw = rm.Rw
    DOOR_X, HALF, POST = 2.70, 0.70, 0.17            # outer face of the frame, half width, post width
    gap = degrees(asin(HALF / Rw)) - 1.0
    rm.build_base(gap=gap)
    b, r, n = rm.base, rm.roof, rm.interior
    F = FLOOR_Z
    # heavy door frame with hazard blocks + lintel + door slab: all in Base so they stay visible
    for sy in (-1, 1):
        yc = sy * (HALF - POST / 2)
        b.box0(2.40, yc, 0.0, 0.60, POST, F + 2.10, "Frame")
        for k in range(5):
            m = "Hazard" if k % 2 == 0 else "Rubber"
            b.box0(DOOR_X - 0.02, yc, F + 0.02 + 0.415 * k, 0.05, POST - 0.01, 0.415, m, mats={"-x": None})
    b.box0(2.40, 0, F + 2.10, 0.60, 2 * HALF, 0.32, "Frame")
    w = 2 * HALF / 5
    for k in range(5):
        m = "Hazard" if k % 2 == 1 else "Rubber"
        b.box0(DOOR_X - 0.02, -HALF + w * (k + 0.5), F + 2.12, 0.05, w, 0.28, m, mats={"-x": None})
    b.box((2.66, 0, F + 1.05), (0.08, 2 * (HALF - POST), 2.10), "HullDark")          # door slab
    b.box((2.705, 0, F + 1.45), (0.012, 0.50, 0.34), "Window", mats={"-x": None})    # door window
    b.box((2.705, 0, F + 0.75), (0.012, 0.85, 0.10), "Accent", mats={"-x": None})
    b.box((2.36, 0, F - 0.05), (0.68, 2 * (HALF - POST), 0.10), "HullDark", mats={"-z": None})   # threshold
    # Roof: sturdy drum with a flat chamfered cap
    top = rm.H
    prof = [(Rw, WALL_TOP), (Rw, 1.85), (Rw + 0.05, 1.90), (Rw + 0.05, 2.25), (Rw, 2.30),
            (Rw, top - 0.50), (Rw - 0.40, top - 0.08), (Rw - 0.95, top), (0.0, top)]
    mats = ["Hull", "Accent", "Accent", "Accent", "Hull", "Hull", "HullDark", "HullDark"]
    r.lathe(prof, lambda k, i: mats[k], seg=rm.seg)
    r.lathe([(Rw + 0.10, WALL_TOP - 0.01), (Rw + 0.10, WALL_TOP + 0.10), (Rw - 0.03, WALL_TOP + 0.18)], "Frame", seg=rm.seg)
    for k in range(6):                                  # buttress ribs on the drum
        with r.at(RZ(30.0 + 60.0 * k)):
            r.prism_y([(Rw - 0.05, WALL_TOP + 0.05), (Rw + 0.24, WALL_TOP + 0.05), (Rw + 0.24, top - 0.80), (Rw - 0.05, top - 0.35)],
                      -0.13, 0.13, "Frame")
    for sy in (-1, 1):                                  # two pressure bottles on the cap
        r.cyl((-0.85, sy * 0.55, top + 0.30), (0.45, sy * 0.55, top + 0.30), 0.24, seg=10, mat="Metal")
        r.box0(-0.5, sy * 0.55, top, 0.12, 0.5, 0.14, "Frame")
        r.box0(0.1, sy * 0.55, top, 0.12, 0.5, 0.14, "Frame")
    r.vcyl(-1.0, 0, top, top + 0.30, 0.08, seg=8, mat="Frame")
    r.sphere((-1.0, 0, top + 0.36), 0.12, "Light", seg=8, rings=4)
    r.box0(2.32, 0, F + 2.42, 0.66, 1.20, 0.10, "HullDark")      # hood that joins the drum to the lintel
    # interior: benches and suit racks on both sides, X axis clear
    for sy in (-1, 1):
        n.box0(-0.1, sy * 1.30, F + 0.34, 1.8, 0.40, 0.08, "Hull", bevel=0.02)
        n.box0(-0.75, sy * 1.30, F, 0.10, 0.30, 0.34, "Frame")
        n.box0(0.55, sy * 1.30, F, 0.10, 0.30, 0.34, "Frame")
        n.box0(-0.1, sy * 1.86, F, 1.30, 0.10, 1.75, "HullDark")
        n.box0(-0.1, sy * 1.78, F + 1.62, 1.30, 0.22, 0.06, "Frame")
        for k in range(3):
            x = -0.55 + 0.45 * k
            n.box0(x, sy * 1.70, F + 0.62, 0.34, 0.20, 0.86, "Hull", bevel=0.04)
            n.box0(x, sy * 1.70, F + 1.10, 0.35, 0.21, 0.10, "Accent")
            n.sphere((x, sy * 1.68, F + 1.80), 0.15, "Hull", seg=8, rings=4)
    n.box((0.0, 0, F + 0.012), (3.2, 0.12, 0.004), "Hazard", mats={"-z": None})
    return rm.parts()


def build_kitchen(spec):
    rm = Room(spec)
    rm.build_base()
    rm.build_dome(rings=7)
    r, n = rm.roof, rm.interior
    F = FLOOR_Z
    # roof: two mushroom vents over the cooking line + a ventilation unit
    for sy in (-1, 1):
        x, y = -2.05, sy * 1.25
        z0 = rm.dome_at(x, y) - 0.25
        r.vcyl(x, y, z0, z0 + 1.05, 0.26, seg=12, mat="HullDark", cap1=False)
        with r.at(T(x, y, z0 + 1.0)):
            r.lathe([(0.0, 0.0), (0.62, 0.0), (0.62, 0.08), (0.30, 0.30), (0.0, 0.34)],
                    lambda k, i: "Frame" if k == 0 else "Accent", seg=12)
    zb = rm.dome_at(1.3, 0.0) - 0.45
    r.box0(1.3, 0, zb, 1.5, 1.9, 0.95, "Hull", bevel=0.08)
    for k in range(5):
        r.box((1.3, -0.72 + 0.36 * k, zb + 0.97), (1.2, 0.20, 0.06), "Accent")
    # interior: curved counter along the back wall (-X side) with cooking units
    a0, a1 = 110.0, 250.0
    r_in, r_out = rm.Ri - 0.85, rm.Ri - 0.06
    n.lathe([(r_out, F), (r_out, F + 0.90), (r_in, F + 0.90), (r_in, F)], "Hull", seg=10, a0=a0, a1=a1, smooth=False)
    n.lathe([(r_out + 0.01, F + 0.90), (r_out + 0.01, F + 0.96), (r_in - 0.04, F + 0.96), (r_in - 0.04, F + 0.90)], "Metal",
            seg=10, a0=a0 - 0.5, a1=a1 + 0.5, smooth=False)
    rc = (r_in + r_out) / 2
    for a in (150.0, 180.0, 210.0):                      # cooking units: hob plates
        with n.at(RZ(a), T(rc, 0, F + 0.96)):
            n.box0(0, 0, 0, 0.62, 0.70, 0.05, "Frame")
            n.vcyl(0.0, -0.17, 0.05, 0.065, 0.13, seg=8, mat="Window")
            n.vcyl(0.0, 0.17, 0.05, 0.065, 0.13, seg=8, mat="Window")
    # curved extraction hood on posts (it must stay under the dome)
    n.lathe([(r_out - 0.12, F + 1.62), (r_out - 0.12, F + 1.84), (r_in - 0.02, F + 1.84), (r_in - 0.02, F + 1.62)], "Accent",
            seg=6, a0=140.0, a1=220.0, smooth=False, wrap=True)
    for a in (142.0, 180.0, 218.0):
        x, y, _ = polar(r_out - 0.2, a)
        n.box0(x, y, F + 0.96, 0.08, 0.08, 0.68, "Frame")
    with n.at(RZ(122.0), T(rc, 0, F + 0.96)):            # sink
        n.box0(0, 0, 0, 0.5, 0.6, 0.04, "Metal")
        n.box((0, 0, 0.045), (0.36, 0.44, 0.01), "WaterBlue")
    with n.at(RZ(238.0), T(rc, 0, F + 0.96)):            # food crate on the counter
        n.box0(0, 0, 0, 0.45, 0.45, 0.30, "Cargo", bevel=0.03)
    for a in (98.0, 262.0):                              # tall fridge / pantry units at the counter ends
        with n.at(RZ(a), T(rm.Ri - 0.55, 0, 0)):
            n.box0(0, 0, F, 0.75, 0.95, 1.80, "Hull", bevel=0.05)
            n.box((-0.385, 0, F + 1.0), (0.012, 0.80, 1.45), "HullDark")
            n.box((-0.395, 0.30, F + 1.0), (0.02, 0.05, 0.6), "Frame")
    round_table(n, 0, 0, 1.0, 0.76)                      # dining table at the room centre, six stools on r = 1.48
    for k in range(6):
        x, y, _ = polar(1.48, 60.0 * k + 30.0)
        stool(n, x, y)
    return rm.parts()


def build_greenhouse(spec):
    rm = Room(spec)
    rm.build_base()
    rings = 6
    rm.build_dome(mat=lambda k, i: "Accent" if k == 0 else "Glass", rings=rings)
    r, n = rm.roof, rm.interior
    # frame ribs: sixteen meridians (on every second dome edge) + two hoops + hub
    for k in range(16):
        a = 360.0 * k / 16
        pts = []
        for j in range(rings + 1):
            pos, nor = rm.dome_point(90.0 * j / rings * 0.96, a)
            pts.append(pos + nor * 0.02)
        r.beam_path(pts, 0.12, 0.12, "Frame", up=lambda p: rm.dome_normal_at(p.x, p.y))
    for t in (30.0, 60.0):
        pos, nor = rm.dome_point(t, 0.0)
        r.lathe([(pos.x + 0.06, pos.z - 0.06), (pos.x + 0.08, pos.z + 0.06), (pos.x - 0.08, pos.z + 0.09)], "Frame",
                seg=rm.seg, smooth=False)
    r.vcyl(0, 0, rm.H - 0.14, rm.H + 0.14, 0.60, seg=12, mat="Frame")
    r.vcyl(0, 0, rm.H + 0.14, rm.H + 0.22, 0.40, seg=12, mat="Accent")
    # interior: four crop trays, soil surface at z = 0.55 (the game puts the crop model there)
    F = FLOOR_Z
    SOIL_Z, RIM_Z = 0.55, 0.63
    for cx, cy in ((2.2, 1.7), (2.2, -1.7), (-2.2, 1.7), (-2.2, -1.7)):
        def rect(hx, hy, z):
            return [(cx + hx, cy - hy, z), (cx + hx, cy + hy, z), (cx - hx, cy + hy, z), (cx - hx, cy - hy, z)]
        n.loft([rect(1.5, 0.7, F), rect(1.5, 0.7, RIM_Z), rect(1.42, 0.62, RIM_Z), rect(1.42, 0.62, SOIL_Z)],
               "Hull", smooth=False, closed=True, cap1=True, cap_mat="Soil")
        n.box((cx, cy, F + 0.20), (3.03, 1.43, 0.10), "Accent", mats={"+z": None, "-z": None})
    # grow lights on a frame above the trays
    ZB = 2.30
    for sy in (-1, 1):
        y = sy * 1.7
        n.beam((-4.0, y, ZB), (4.0, y, ZB), 0.10, 0.12, "Frame")
        for sx in (-1, 1):
            n.beam((sx * 4.0, y, F), (sx * 4.0, y, ZB), 0.10, 0.10, "Frame")
            n.box((sx * 2.2, y, ZB - 0.32), (2.7, 0.52, 0.08), "Light")           # light bar hangs under the beam
            for hx in (-1.0, 1.0):
                n.box((sx * 2.2 + hx, y, ZB - 0.17), (0.05, 0.05, 0.24), "Frame", mats={"+z": None, "-z": None})
    for x in (-4.0, 0.0, 4.0):
        n.beam((x, -1.7, ZB), (x, 1.7, ZB), 0.08, 0.10, "Frame")
    # water tank at the back
    n.vcyl(-4.55, 0, F, F + 1.1, 0.42, seg=12, mat="Hull", cap1=False)
    with n.at(T(-4.55, 0, F + 1.1)):
        n.lathe(dome_profile(0.42, 0.0, 0.22, 3), "WaterBlue", seg=12)
    n.tube([(-4.55, 0, F + 0.35), (-4.0, 0, F + 0.35), (-4.0, 0, F + 0.10)], 0.06, seg=6, mat="WaterBlue", fillet=0.12)
    return rm.parts()


STORE_T1 = 58.0     # the storehouse dome is cut flat at this profile angle


def build_storehouse(spec):
    apex = WALL_TOP + (spec["height"] - WALL_TOP) / sin(radians(STORE_T1))
    rm = Room(dict(spec, dome_apex=apex))
    rm.build_base()
    rm.build_dome(rings=5, t1=STORE_T1, flat_top=True)
    r, n = rm.roof, rm.interior
    top = spec["height"]
    r_top = rm.Rw * cos(radians(STORE_T1))
    for k in range(8):                                   # eight ribs up the flank
        a = 22.5 + 45.0 * k
        pts = []
        for j in range(6):
            pos, nor = rm.dome_point(STORE_T1 * j / 5, a)
            pts.append(pos + nor * 0.03)
        r.beam_path(pts, 0.34, 0.16, "HullDark", up=lambda p: rm.dome_normal_at(p.x, p.y))
    r.lathe([(r_top + 0.06, top - 0.14), (r_top + 0.06, top + 0.10), (r_top - 0.30, top + 0.10)], "Frame", seg=rm.seg, smooth=False)
    # big square cargo hatch on the flat top
    r.box0(0, 0, top, 2.8, 2.8, 0.22, "Frame", bevel=0.06)
    r.box0(0, 0, top + 0.22, 2.4, 2.4, 0.10, "Accent", bevel=0.04)
    r.box((0, 0, top + 0.33), (0.10, 2.4, 0.03), "Frame")
    for sx in (-1, 1):
        for sy in (-1, 1):
            r.box((sx * 1.25, sy * 1.25, top + 0.27), (0.44, 0.44, 0.12), "Hazard")
    # interior: six shelving racks along the wall, crates, centre clear
    F = FLOOR_Z
    rng = random.Random(7)
    r_out = rm.Ri - 0.08
    r_in = r_out - 0.85
    for k in range(6):
        ac = 30.0 + 60.0 * k
        a0, a1 = ac - 19.0, ac + 19.0
        for zs in (0.50, 1.05):                           # two shelf boards; the top level stays open so crates show
            n.lathe([(r_out, F + zs), (r_out, F + zs + 0.06), (r_in, F + zs + 0.06), (r_in, F + zs)], "Metal",
                    seg=3, a0=a0, a1=a1, smooth=False, wrap=True)
        for a in (a0 + 1.0, a1 - 1.0):
            for rr in (r_in + 0.05, r_out - 0.05):
                x, y, _ = polar(rr, a)
                n.box0(x, y, F, 0.08, 0.08, 1.70, "Frame")
            n.beam(polar(r_in + 0.05, a, F + 1.66), polar(r_out - 0.05, a, F + 1.66), 0.06, 0.06, "Frame")
        for rr in (r_in + 0.05, r_out - 0.05):
            n.beam(polar(rr, a0 + 1.0, F + 1.66), polar(rr, a1 - 1.0, F + 1.66), 0.06, 0.06, "Frame")
        for zs in (0.0, 0.56, 1.11):
            for a in (ac - 11.0, ac, ac + 11.0):
                if rng.random() < 0.25:
                    continue
                x, y, _ = polar((r_in + r_out) / 2, a)
                crate_prop(n, x, y, F + zs, size=rng.choice((0.40, 0.44, 0.46)), mat=rng.choice(("Cargo", "Cargo", "Hull")),
                           band=rng.choice(("Frame", "Accent")), rot=a, bevel=False)
    for (x, y, s, rot) in ((2.3, 1.4, 0.8, 10), (2.35, 0.5, 0.7, -5), (-2.2, -1.6, 0.8, 40), (-1.4, -2.35, 0.7, 12),
                           (-2.4, 1.9, 0.75, -20)):
        crate_prop(n, x, y, F, size=s, band="Accent" if s > 0.72 else "Frame", rot=rot)
    crate_prop(n, 2.3, 1.38, F + 0.8, size=0.6, rot=25)
    crate_prop(n, -2.2, -1.6, F + 0.8, size=0.55, band="Accent", rot=5)
    return rm.parts()


def build_mine(spec):
    rm = Room(spec)
    rm.build_base()
    rm.build_dome(rings=7)
    r, n = rm.roof, rm.interior
    F = FLOOR_Z
    # headframe: lattice tower through the roof (it belongs to Roof, so it hides with it)
    Z0, Z1 = 2.75, 5.45                                 # platform at 5.45, top of the sheave wheel at 6.6
    H0, H1 = 1.15, 0.58
    levels = [Z0, 3.65, 4.35, 4.95, Z1]

    def hw(z):
        return H0 + (H1 - H0) * (z - Z0) / (Z1 - Z0)
    corners = ((1, 1), (-1, 1), (-1, -1), (1, -1))
    for sx, sy in corners:
        r.beam((sx * hw(Z0), sy * hw(Z0), Z0), (sx * hw(Z1), sy * hw(Z1), Z1), 0.16, 0.16, "Frame")
    for z in levels[1:]:
        h = hw(z)
        for c in range(4):
            a, b_ = corners[c], corners[(c + 1) % 4]
            r.beam((a[0] * h, a[1] * h, z), (b_[0] * h, b_[1] * h, z), 0.10, 0.10, "Frame")
    for li in range(len(levels) - 1):
        za, zb = levels[li], levels[li + 1]
        ha, hb = hw(za), hw(zb)
        for c in range(4):
            a, b_ = corners[c], corners[(c + 1) % 4]
            if (li + c) % 2 == 0:
                r.beam((a[0] * ha, a[1] * ha, za), (b_[0] * hb, b_[1] * hb, zb), 0.07, 0.07, "Frame")
            else:
                r.beam((b_[0] * ha, b_[1] * ha, za), (a[0] * hb, a[1] * hb, zb), 0.07, 0.07, "Frame")
    r.box0(0, 0, Z1, 1.5, 1.5, 0.12, "HullDark")
    r.cyl((0, -0.10, Z1 + 0.62), (0, 0.10, Z1 + 0.62), 0.52, seg=14, mat="Accent")     # sheave wheel
    r.cyl((0, -0.16, Z1 + 0.62), (0, 0.16, Z1 + 0.62), 0.14, seg=8, mat="Frame")
    for sy in (-1, 1):
        r.beam((-0.40, sy * 0.24, Z1 + 0.12), (0, sy * 0.24, Z1 + 0.66), 0.08, 0.08, "Frame")
        r.beam((0.40, sy * 0.24, Z1 + 0.12), (0, sy * 0.24, Z1 + 0.66), 0.08, 0.08, "Frame")
    for sy in (-1, 1):                                                                 # back stays
        r.beam((-0.45, sy * 0.45, Z1 - 0.1), (-3.0, sy * 0.9, rm.dome_at(-3.0, 0.9) - 0.1), 0.14, 0.14, "Frame")
    # conveyor from the tower to the ore hopper on the -Y flank (toward the default camera)
    hx, hy = 0.6, -2.9
    hz = rm.dome_at(hx, hy)
    top_z = hz + 0.95
    r.beam((0.1, -0.5, 4.40), (hx, hy + 0.2, top_z + 0.45), 0.55, 0.10, "Rubber")
    r.beam((0.1, -0.5, 4.32), (hx, hy + 0.2, top_z + 0.37), 0.68, 0.07, "Frame")
    with r.at(T(hx, hy, 0)):
        r.convex([(-0.95, -0.95, top_z), (0.95, -0.95, top_z), (0.95, 0.95, top_z), (-0.95, 0.95, top_z),
                  (-0.5, -0.5, hz - 0.9), (0.5, -0.5, hz - 0.9), (0.5, 0.5, hz - 0.9), (-0.5, 0.5, hz - 0.9)],
                 [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "HullDark")
        r.box((0, 0, top_z + 0.02), (2.06, 2.06, 0.16), "Accent", mats={"-z": None})
        r.convex([(-0.85, -0.85, top_z + 0.10), (0.85, -0.85, top_z + 0.10), (0.85, 0.85, top_z + 0.10), (-0.85, 0.85, top_z + 0.10),
                  (0.0, 0.1, top_z + 0.55)], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (0, 1, 2, 3)], "Ore")
    # interior: shaft collar, cage, winch, ore carts, ore pile
    n.lathe([(1.35, F), (1.35, F + 0.45), (1.25, F + 0.55), (0.95, F + 0.55), (0.95, F)],
            lambda k, i: ("HullDark", "HullDark", "Hazard", "Frame")[k], seg=16)
    n.disc(0.96, F + 0.02, "Rubber", seg=16)
    n.box((0, 0, F + 1.25), (1.0, 1.0, 1.3), "Frame", mats={"+x": "HullDark", "-x": "HullDark"})
    n.box((0, 0, F + 1.95), (1.1, 1.1, 0.10), "Accent")
    n.vcyl(0, 0, F + 2.0, F + 3.2, 0.035, seg=5, mat="Rubber")
    with n.at(T(-2.5, 0, F)):                                # winch
        n.box0(0, 0, 0, 1.5, 1.7, 0.18, "Frame")
        n.cyl((0, -0.6, 0.72), (0, 0.6, 0.72), 0.46, seg=14, mat="Metal")
        n.cyl((0, -0.68, 0.72), (0, -0.6, 0.72), 0.58, seg=14, mat="Accent")
        n.cyl((0, 0.6, 0.72), (0, 0.68, 0.72), 0.58, seg=14, mat="Accent")
        n.box0(0, -0.95, 0.18, 0.7, 0.30, 0.95, "HullDark")
        n.box0(0, 0.95, 0.18, 0.7, 0.30, 0.95, "HullDark")
        n.box0(-0.2, 1.50, 0.0, 0.8, 0.6, 0.8, "Hull", bevel=0.05)
    n.tube([(-2.5, 0, F + 1.18), (-0.2, 0, F + 2.9)], 0.03, seg=5, mat="Rubber")
    for (x, y, rot) in ((1.6, -2.4, 20.0), (2.7, -1.2, 65.0)):   # ore carts
        with n.at(T(x, y, F), RZ(rot)):
            n.box0(0, 0, 0.18, 1.2, 0.8, 0.55, "HullDark", bevel=0.05)
            n.box((0, 0, 0.72), (1.05, 0.66, 0.14), "Ore", bevel=0.05)
            for sx in (-0.4, 0.4):
                n.cyl((sx, -0.44, 0.16), (sx, 0.44, 0.16), 0.16, seg=8, mat="Rubber")
    rng = random.Random(3)
    pts = [(rng.uniform(-0.9, 0.9), rng.uniform(-0.7, 0.7), rng.uniform(0.0, 0.75)) for _ in range(22)]
    pts = [(x, y, z * (1.0 - 0.6 * math.hypot(x / 0.9, y / 0.7) / 1.42)) for x, y, z in pts]
    pts += [(-0.9, -0.7, 0), (0.9, -0.7, 0), (0.9, 0.7, 0), (-0.9, 0.7, 0)]
    with n.at(T(1.0, 2.9, F), RZ(-20)):
        n.hull(pts, "Ore", vein=((0, 0, 0.3), (1, 0.3, 0.6), 0.12))
    return rm.parts()


def _ingot_stack(n, mat, layers, length):
    for layer, cnt in enumerate(layers):
        for k in range(cnt):
            y = (k - (cnt - 1) / 2) * 0.27
            z = 0.08 + layer * 0.16
            n.prism_x([(y - 0.12, z), (y + 0.12, z), (y + 0.08, z + 0.15), (y - 0.08, z + 0.15)], -length / 2, length / 2, mat)


def build_refinery(spec):
    rm = Room(spec)
    rm.build_base()
    rm.build_dome(rings=7)
    r, n = rm.roof, rm.interior
    F = FLOOR_Z
    fx, fy = -1.7, 1.1                                   # furnace position
    # chimney stack through the roof
    z0 = rm.dome_at(fx, fy) - 0.35
    r.vcyl(fx, fy, z0, z0 + 0.50, 0.90, 0.72, seg=16, mat="Frame")
    r.vcyl(fx, fy, z0 + 0.3, 6.0, 0.52, 0.40, seg=16, mat="HullDark", cap1=False)
    r.vcyl(fx, fy, 4.55, 5.05, 0.49, 0.46, seg=16, mat="Accent", cap0=False, cap1=False)
    r.vcyl(fx, fy, 5.9, 6.05, 0.50, seg=16, mat="Frame")
    r.disc(0.36, 6.055, "Rubber", seg=16)
    # heat exchanger with glowing slits + a thin second flue
    x2, y2 = 1.9, -1.3
    zb = rm.dome_at(x2, y2) - 0.5
    r.box0(x2, y2, zb, 1.7, 1.5, 1.05, "HullDark", bevel=0.08)
    for k in range(4):
        r.box((x2 - 0.6 + 0.4 * k, y2, zb + 1.07), (0.16, 1.2, 0.06), "Window")
    r.box((x2, y2, zb + 0.78), (1.74, 1.54, 0.16), "Accent")
    x3, y3 = 0.6, 2.4
    z3 = rm.dome_at(x3, y3) - 0.3
    r.vcyl(x3, y3, z3, z3 + 1.5, 0.24, seg=10, mat="Metal", cap1=False)
    r.vcyl(x3, y3, z3 + 1.4, z3 + 1.55, 0.32, seg=10, mat="Frame")
    # interior: furnace with a glowing mouth that faces the room centre, ingots, crucible, ore bin
    with n.at(T(fx, fy, F), RZ(degrees(atan2(-fy, -fx)))):   # local +X points to the room centre
        n.vcyl(0, 0, 0, 0.25, 1.40, seg=16, mat="Frame")
        n.lathe([(1.28, 0.25), (1.28, 1.25), (1.31, 1.28), (1.31, 1.62), (1.28, 1.65), (1.20, 2.0), (0.70, 2.32), (0.0, 2.36)],
                lambda k, i: ("HullDark", "Accent", "Accent", "Accent", "HullDark", "HullDark", "Frame")[k], seg=16)
        n.box((1.25, 0, 0.85), (0.50, 1.40, 1.20), "Frame", bevel=0.06)               # furnace mouth
        n.box((1.505, 0, 0.80), (0.02, 1.05, 0.80), "Window")
        n.prism_y([(1.30, 1.50), (2.05, 1.50), (2.05, 1.60), (1.30, 1.95)], -0.85, 0.85, "Frame")   # hood
        n.box0(1.95, 0, 0, 0.9, 1.3, 0.03, "Hazard")
        n.tube([(-0.3, 1.0, 1.0), (-0.3, 1.7, 1.0), (-0.3, 1.7, 0.2)], 0.12, seg=6, mat="Metal", fillet=0.2)
    with n.at(T(1.5, -1.5, F), RZ(35)):                       # casting table with a row of glowing moulds
        n.box0(0, 0, 0, 2.6, 1.0, 0.55, "HullDark", bevel=0.05)
        for k in range(5):
            n.box((-1.0 + 0.5 * k, 0, 0.57), (0.34, 0.70, 0.06), "Window" if k < 3 else "Metal")
    with n.at(T(2.7, 1.2, F), RZ(-30)):
        n.box0(0, 0, 0, 1.5, 1.0, 0.08, "Frame")
        _ingot_stack(n, "Metal", (3, 2, 1), 1.2)
    with n.at(T(1.0, 2.9, F), RZ(15)):
        n.box0(0, 0, 0, 1.2, 0.8, 0.08, "Frame")
        _ingot_stack(n, "OreVein", (2, 1), 1.0)
    with n.at(T(0.55, 0.15, F)):                             # crucible on a trolley
        n.box0(0, 0, 0.12, 1.0, 1.0, 0.12, "Frame")
        n.lathe([(0.32, 0.24), (0.48, 0.95), (0.40, 0.95), (0.0, 0.90)], lambda k, i: ("Metal", "Frame", "Window")[k], seg=12)
        for sx in (-0.35, 0.35):
            n.cyl((sx, -0.52, 0.12), (sx, 0.52, 0.12), 0.12, seg=8, mat="Rubber")
    with n.at(T(-0.4, -2.9, F), RZ(8)):                      # ore bin
        n.box0(0, 0, 0, 1.6, 1.0, 0.7, "Hull", bevel=0.05)
        n.box((0, 0, 0.72), (1.4, 0.8, 0.12), "Ore", bevel=0.04)
    return rm.parts()


def build_polymer_plant(spec):
    rm = Room(spec)
    rm.build_base()
    rm.build_dome(rings=7)
    r, n = rm.roof, rm.interior
    F = FLOOR_Z
    vats = ((-0.9, 1.75), (-0.9, -1.75))
    for (x, y) in vats:
        zd = rm.dome_at(x, y)
        # roof: vat heads that show through the dome
        r.vcyl(x, y, zd - 0.75, zd + 0.40, 1.18, seg=20, mat="Metal", cap0=False, cap1=False)
        r.vcyl(x, y, zd + 0.05, zd + 0.30, 1.22, seg=20, mat="Accent", cap0=False, cap1=False)
        with r.at(T(x, y, zd + 0.40)):
            r.lathe(dome_profile(1.18, 0.0, 0.45, 4), "Metal", seg=20)
        r.vcyl(x, y, zd + 0.80, zd + 1.0, 0.22, seg=10, mat="Frame")
        # interior: the vats
        n.vcyl(x, y, F, F + 0.2, 1.2, seg=18, mat="Frame")
        n.vcyl(x, y, F + 0.2, F + 2.25, 1.08, seg=18, mat="Metal")
        n.vcyl(x, y, F + 1.2, F + 1.6, 1.11, seg=18, mat="Accent", cap0=False, cap1=False)
        n.vcyl(x, y, F + 2.25, F + 2.40, 0.35, seg=10, mat="Frame")
    # roof pipes: a bridge pipe between the vat heads and a pipe down the front flank
    za = rm.dome_at(-0.9, 1.75) + 0.95
    r.tube([(-0.9, 1.75, za - 0.1), (-0.9, 1.75, za + 0.55), (-0.9, -1.75, za + 0.55), (-0.9, -1.75, za - 0.1)], 0.13, seg=8,
           mat="HullDark", fillet=0.35)
    pts = [(-0.9, 0.0, za + 0.55), (-0.2, 0.0, za + 0.55)]
    for x in (0.8, 1.6, 2.4, 3.1, 3.7, 4.2):
        pts.append((x, 0.0, rm.dome_at(x, 0.0) + 0.28))
    r.tube(pts, 0.13, seg=8, mat="HullDark", fillet=0.3)
    for x in (1.6, 3.1):
        r.box0(x, 0, rm.dome_at(x, 0.0) - 0.1, 0.22, 0.45, 0.42, "Frame")
    r.vcyl(2.4, 0, rm.dome_at(2.4, 0) + 0.10, rm.dome_at(2.4, 0) + 0.50, 0.24, seg=10, mat="Accent")
    # interior: press, pipes, pellet bins
    with n.at(T(2.1, 0.0, F)):
        n.box0(0, 0, 0, 1.5, 1.7, 0.35, "HullDark", bevel=0.05)
        for sy in (-0.7, 0.7):
            n.vcyl(0, sy, 0.35, 1.95, 0.10, seg=8, mat="Metal")
        n.box0(0, 0, 1.95, 1.3, 1.8, 0.35, "HullDark", bevel=0.05)
        n.box0(0, 0, 1.10, 1.0, 1.15, 0.16, "Metal")
        n.vcyl(0, 0, 1.26, 1.95, 0.20, seg=10, mat="Accent")
        n.box0(0, 0, 0.35, 1.0, 1.15, 0.10, "Fabric")
    n.tube([(-0.9, 1.75, F + 2.4), (-0.9, 1.75, F + 2.75), (-0.9, -1.75, F + 2.75), (-0.9, -1.75, F + 2.4)], 0.09, seg=6,
           mat="HullDark", fillet=0.3)
    n.tube([(0.18, 1.75, F + 0.6), (1.0, 1.75, F + 0.6), (1.0, 0.85, F + 0.6)], 0.08, seg=6, mat="HullDark", fillet=0.25)
    for (x, y, rot, m) in ((-3.3, 0.0, 0, "Accent"), (0.8, -3.2, 60, "Frame"), (1.6, 3.0, -50, "Accent")):
        with n.at(T(x, y, F), RZ(rot)):
            n.box0(0, 0, 0, 0.9, 1.3, 0.75, "Hull", bevel=0.05)
            n.box((0, 0, 0.77), (0.72, 1.12, 0.06), m)
    return rm.parts()


def build_medical(spec):
    rm = Room(spec)
    rm.build_base()
    rm.build_dome(rings=7)
    r, n = rm.roof, rm.interior
    F = FLOOR_Z
    # large plus sign draped over the dome
    W, L = 0.62, 2.75
    r.drape(-L, L, -W, W, rm.dome_at, "Accent", nx=12, ny=2, offset=0.05)
    r.drape(-W, W, W, L, rm.dome_at, "Accent", nx=2, ny=5, offset=0.05)
    r.drape(-W, W, -L, -W, rm.dome_at, "Accent", nx=2, ny=5, offset=0.05)
    # interior: two treatment beds, scanner arch over one, cabinet, monitor
    for sy in (-1, 1):
        with n.at(T(0.2, sy * 1.55, F)):
            n.box0(0, 0, 0, 0.5, 0.5, 0.45, "Frame")
            n.box0(0, 0, 0.45, 2.1, 0.85, 0.14, "HullDark", bevel=0.04)
            n.box0(0, 0, 0.59, 2.0, 0.78, 0.10, "Hull", bevel=0.03)
            n.box0(-0.30, 0, 0.60, 1.0, 0.80, 0.11, "Accent")
            n.box0(0.78, 0, 0.69, 0.34, 0.52, 0.07, "Hull", bevel=0.03)
    # scanner arch: half ring around the +Y bed, ring axis along X
    axis_x = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))     # local Z -> world X
    with n.at(T(0.75, 1.55, F + 0.45), axis_x):
        n.lathe([(0.98, -0.30), (0.98, 0.30), (0.74, 0.30), (0.74, -0.30)],
                lambda k, i: ("Hull", "Hull", "HullDark", "Hull")[k], seg=10, a0=0.0, a1=180.0, wrap=True)
        n.lathe([(0.995, -0.08), (0.995, 0.08)], "Accent", seg=10, a0=0.0, a1=180.0, caps=False)
    n.box0(0.75, 1.55 - 0.86, F, 0.62, 0.26, 0.47, "HullDark")
    n.box0(0.75, 1.55 + 0.86, F, 0.62, 0.26, 0.47, "HullDark")
    with n.at(RZ(180.0), T(rm.Ri - 0.52, 0, F)):            # cabinet with a monitor
        n.box0(0, 0, 0, 0.6, 1.9, 1.0, "Hull", bevel=0.05)
        n.box((-0.31, 0, 0.55), (0.012, 1.7, 0.12), "Accent")
        n.box0(0, -0.55, 1.0, 0.3, 0.5, 0.35, "Cargo", bevel=0.03)
        n.box0(0, 0.45, 1.0, 0.10, 0.7, 0.5, "Frame")
        n.box((-0.06, 0.45, 1.27), (0.012, 0.6, 0.36), "Window")
    with n.at(T(1.9, -0.6, F)):                             # monitor stand
        n.vcyl(0, 0, 0, 0.06, 0.28, seg=8, mat="Frame")
        n.vcyl(0, 0, 0.06, 1.25, 0.04, seg=6, mat="Metal")
        n.box((0, 0, 1.4), (0.08, 0.55, 0.4), "Frame")
        n.box((-0.046, 0, 1.4), (0.01, 0.47, 0.32), "Window")
    with n.at(RZ(300.0), T(rm.Ri - 0.45, 0, F)):            # medicine cabinet + wash basin
        n.box0(0, 0, 0, 0.55, 1.5, 1.7, "Hull", bevel=0.05)
        n.box((-0.28, 0, 1.15), (0.012, 1.3, 0.9), "Glass")
        n.box((-0.285, 0, 0.45), (0.012, 1.3, 0.10), "Accent")
    with n.at(RZ(60.0), T(rm.Ri - 0.45, 0, F)):
        n.box0(0, 0, 0, 0.55, 1.1, 0.85, "Hull", bevel=0.05)
        n.box((0, 0, 0.86), (0.36, 0.7, 0.02), "WaterBlue")
    with n.at(T(-0.55, -1.55, F)):                          # examination light on a boom over the -Y bed
        n.vcyl(0, -0.75, 0, 1.9, 0.04, seg=6, mat="Metal")
        n.beam((0, -0.75, 1.9), (0.5, -0.05, 1.9), 0.06, 0.06, "Metal")
        n.vcyl(0.5, -0.05, 1.72, 1.92, 0.26, 0.20, seg=10, mat="Hull")
    n.vcyl(-0.05, -1.60, F + 1.715, F + 1.72, 0.22, seg=10, mat="Light", cap1=False)     # lamp face (points down)
    n.vcyl(-2.0, 0.3, F, F + 0.45, 0.20, seg=8, mat="Frame")     # stool
    n.vcyl(-2.0, 0.3, F + 0.45, F + 0.53, 0.24, seg=10, mat="Accent")
    z = F + 0.012
    n.box((-1.3, 0, z), (0.9, 0.3, 0.004), "Accent", mats={"-z": None})
    n.box((-1.3, 0, z + 0.001), (0.3, 0.9, 0.004), "Accent", mats={"-z": None})
    return rm.parts()


def build_lounge(spec):
    rm = Room(spec)
    rm.build_base()

    def roof_mat(k, i):
        if k == 0:
            return "Accent"
        if 1 <= k <= 3:
            return "Hull" if i % 8 in (7, 0) else "Glass"
        return "Hull"
    rm.build_dome(mat=roof_mat, rings=7)
    r, n = rm.roof, rm.interior
    F = FLOOR_Z
    pos, nor = rm.dome_point(90.0 * 4 / 7, 0.0)
    r.lathe([(pos.x + 0.10, pos.z - 0.10), (pos.x + 0.10, pos.z + 0.08), (pos.x - 0.12, pos.z + 0.14)], "Accent", seg=rm.seg)
    r.vcyl(0, 0, rm.H - 0.2, rm.H + 0.12, 0.7, seg=16, mat="HullDark")
    r.sphere((0, 0, rm.H + 0.12), 0.45, "Accent", seg=12, rings=4, scale=(1, 1, 0.6))
    # interior: two curved sofas that face the centre, low table on a rug, plants, bar counter
    sofa = [(2.85, F), (2.85, F + 0.85), (2.55, F + 0.85), (2.55, F + 0.46), (1.95, F + 0.46), (1.95, F)]
    arm = [(2.88, F), (2.88, F + 0.66), (1.92, F + 0.66), (1.92, F)]
    for a0 in (35.0, 215.0):
        n.lathe(sofa, "Fabric", seg=8, a0=a0, a1=a0 + 110.0, smooth=False, cap_mat="Fabric")
        n.lathe(arm, "HullDark", seg=1, a0=a0 - 4.0, a1=a0, smooth=False)
        n.lathe(arm, "HullDark", seg=1, a0=a0 + 110.0, a1=a0 + 114.0, smooth=False)
    n.disc(1.75, F + 0.012, "Accent", seg=24)
    round_table(n, 0, 0, 0.75, 0.42, top="Hull")
    n.vcyl(0.2, 0.1, F + 0.42, F + 0.56, 0.12, 0.09, seg=8, mat="Accent")
    for (ang, rad, big) in ((165.0, 3.3, True), (345.0, 3.3, False)):      # plant pots
        px, py, _ = polar(rad, ang)
        n.vcyl(px, py, F, F + 0.55, 0.30, 0.42, seg=10, mat="HullDark", cap1=False)
        with n.at(T(px, py, F + 0.5)):
            n.disc(0.40, 0.0, "Soil", seg=10)
            n.sphere((0, 0, 0.50), 0.52, "Plant", seg=8, rings=4, smooth=False, scale=(1, 1, 0.9))
            if big:
                n.sphere((0.2, 0.1, 0.92), 0.32, "PlantDark", seg=6, rings=3, smooth=False)
    n.lathe([(rm.Ri - 0.10, F), (rm.Ri - 0.10, F + 1.0), (rm.Ri - 0.70, F + 1.0), (rm.Ri - 0.70, F)], "Hull", seg=5,
            a0=255.0, a1=285.0, smooth=False)
    n.lathe([(rm.Ri - 0.08, F + 1.0), (rm.Ri - 0.08, F + 1.06), (rm.Ri - 0.78, F + 1.06), (rm.Ri - 0.78, F + 1.0)], "Accent",
            seg=5, a0=254.0, a1=286.0, smooth=False)
    for a in (262.0, 270.0, 278.0):
        x, y, _ = polar(rm.Ri - 1.15, a)
        stool(n, x, y)
    return rm.parts()


def build_workshop(spec):
    rm = Room(spec)
    rm.build_base()
    rm.build_dome(rings=7)
    r, n = rm.roof, rm.interior
    F = FLOOR_Z
    # roof crane: pedestal, slewing cab, boom, counterweight, hook
    top = rm.H
    r.vcyl(0, 0, top - 0.35, top + 0.10, 0.95, 0.80, seg=16, mat="Frame")
    r.vcyl(0, 0, top + 0.10, top + 0.95, 0.42, seg=12, mat="HullDark")
    with r.at(T(0, 0, top + 0.95), RZ(-25.0)):
        r.box0(0, 0, 0, 1.1, 0.9, 0.55, "Accent", bevel=0.08)
        r.box((0.56, 0, 0.30), (0.012, 0.6, 0.26), "Window")
        r.beam((0.3, 0, 0.62), (3.6, 0, 1.25), 0.26, 0.30, "Hazard")
        r.beam((0.3, 0, 0.30), (2.0, 0, 0.95), 0.10, 0.10, "Frame")
        r.box((-0.95, 0, 0.42), (0.9, 0.8, 0.5), "HullDark", bevel=0.06)
        r.vcyl(3.45, 0, 0.30, 1.10, 0.03, seg=5, mat="Rubber")
        r.box((3.45, 0, 0.22), (0.26, 0.20, 0.26), "Frame")
    # interior: benches along the wall, lathe machine, parts rack, tool trolley, robot arm
    for a in (60.0, 120.0):
        with n.at(RZ(a), T(rm.Ri - 0.62, 0, F)):
            n.box0(0, 0, 0.80, 0.9, 2.2, 0.08, "Metal")
            for sy in (-1.0, 1.0):
                n.box0(0, sy, 0, 0.8, 0.12, 0.80, "Frame")
            n.box0(0.1, 0, 0.25, 0.7, 1.9, 0.06, "HullDark")
            n.box0(0.30, 0, 0.88, 0.10, 2.2, 0.62, "HullDark")
            n.box0(0.0, -0.6, 0.88, 0.35, 0.45, 0.28, "Accent", bevel=0.03)
            n.box0(-0.1, 0.5, 0.88, 0.30, 0.30, 0.16, "Cargo")
            n.cyl((0.235, -0.2, 1.30), (0.235, 0.9, 1.30), 0.04, seg=5, mat="Hazard")
    with n.at(T(0.3, -2.3, F), RZ(8.0)):                    # lathe-like machine
        n.box0(0, 0, 0, 2.6, 0.75, 0.70, "HullDark", bevel=0.05)
        n.box0(-0.9, 0, 0.70, 0.75, 0.70, 0.65, "Accent", bevel=0.06)
        n.cyl((-0.52, 0, 1.05), (-0.30, 0, 1.05), 0.26, seg=12, mat="Metal")
        n.cyl((-0.30, 0, 1.05), (0.85, 0, 1.05), 0.09, seg=8, mat="Metal")
        n.box0(1.0, 0, 0.70, 0.35, 0.45, 0.50, "Frame")
        n.box0(0.2, -0.05, 0.70, 0.45, 0.60, 0.20, "Frame")
        n.box0(0.2, 0, 0.70, 1.9, 0.12, 0.06, "Metal")
    with n.at(RZ(200.0), T(rm.Ri - 0.48, 0, F)):            # parts rack
        for zs in (0.10, 0.65, 1.20, 1.70):
            n.box0(0, 0, zs, 0.6, 2.0, 0.05, "Metal")
        for sy in (-0.95, 0.95):
            for sx in (-0.26, 0.26):
                n.box0(sx, sy, 0, 0.06, 0.06, 1.75, "Frame")
        rng = random.Random(11)
        for zs in (0.15, 0.70, 1.25):
            for k in range(4):
                if rng.random() < 0.2:
                    continue
                n.box0(0, -0.66 + 0.44 * k, zs, 0.45, 0.36, rng.uniform(0.22, 0.38),
                       rng.choice(("Cargo", "Accent", "Metal", "Cargo")))
    with n.at(T(1.9, 0.6, F), RZ(30.0)):                    # tool trolley
        n.box0(0, 0, 0.12, 0.9, 0.55, 0.70, "Hazard", bevel=0.04)
        n.box0(0, 0, 0.82, 0.95, 0.60, 0.05, "Frame")
        for sx in (-0.33, 0.33):
            n.cyl((sx, -0.3, 0.1), (sx, 0.3, 0.1), 0.10, seg=8, mat="Rubber")
    with n.at(T(-2.2, -1.0, F), RZ(-35.0)):                 # robot arm on a plinth
        n.vcyl(0, 0, 0, 0.35, 0.40, seg=10, mat="Frame")
        n.beam((0, 0, 0.35), (0.2, 0, 1.35), 0.22, 0.22, "Hazard")
        n.beam((0.2, 0, 1.35), (1.2, 0, 1.0), 0.16, 0.16, "Hazard")
        n.sphere((0.2, 0, 1.35), 0.18, "Frame", seg=8, rings=4)
        n.box((1.25, 0, 0.92), (0.16, 0.26, 0.2), "Metal")
    return rm.parts()


# @@ROOMS@@

# --------------------------------------------------------------------------------------
# EXTERIOR STRUCTURES
# --------------------------------------------------------------------------------------
def build_lander(spec):
    p = Part("Base")
    # crew body: heat shield, drum with the accent band, cone, nose cap
    prof = [(0.80, 0.85), (2.30, 0.95), (3.00, 1.50), (3.00, 2.85), (3.00, 3.35), (2.80, 3.75), (1.45, 6.10), (1.00, 6.62), (0.0, 6.85)]
    mats = ["Frame", "HullDark", "Hull", "Accent", "Hull", "Hull", "HullDark", "HullDark"]
    p.lathe(prof, lambda k, i: mats[k], seg=24)
    p.lathe([(3.06, 1.42), (3.06, 1.62), (2.98, 1.66)], "Frame", seg=24)               # skirt ring
    # engine bell under the body
    p.lathe([(1.20, 0.22), (0.78, 0.62), (0.58, 0.90)], "Metal", seg=16)
    p.lathe([(0.58, 0.90), (0.72, 0.62), (1.12, 0.24)], "Rubber", seg=16)             # inside of the bell
    p.vcyl(0, 0, 0.80, 0.95, 0.95, seg=16, mat="Frame")
    # windows on the cone (the big one looks forward, +X)
    cone_n = Vector((2.35, 0.0, 1.35)).normalized()
    for k in range(8):
        a = 45.0 * k
        z = 4.75
        rad = 2.80 - (z - 3.75) * (1.35 / 2.35)
        big = (k == 0)
        with p.at(RZ(a)):
            pos = Vector((rad, 0, z))
            r = 0.42 if big else 0.27
            p.cyl(pos - cone_n * 0.12, pos + cone_n * 0.07, r + 0.08, seg=10, mat="Frame", cap0=False)
            p.cyl(pos, pos + cone_n * 0.09, r, seg=10, mat=None, cap_mat="Window", cap0=False)
    # hatch + ramp on +X. The ramp touches the ground at x = 5.0
    SILL = 1.58
    p.box((3.02, 0, SILL + 0.92), (0.20, 1.70, 2.04), "Frame", bevel=0.05)
    p.box((3.10, 0, SILL + 0.90), (0.08, 1.30, 1.72), "HullDark")
    p.box((3.145, 0, SILL + 1.30), (0.012, 0.60, 0.30), "Window", mats={"-x": None})
    p.box((3.145, 0, SILL + 0.55), (0.012, 1.10, 0.10), "Accent", mats={"-x": None})
    p.beam((3.05, 0, SILL - 0.06), (5.0, 0, 0.02), 1.40, 0.12, "Metal")
    for sy in (-1, 1):
        p.beam((3.05, sy * 0.74, SILL + 0.04), (5.0, sy * 0.74, 0.10), 0.08, 0.14, "Hazard")
    for k in range(5):
        t = (k + 0.7) / 5.6
        p.box((3.05 + 1.95 * t, 0, SILL - 0.06 + (0.02 - (SILL - 0.06)) * t + 0.075), (0.10, 1.30, 0.05), "Frame")
    # three propellant tanks between the legs (not on the hatch side)
    for a in (90.0, 180.0, 270.0):
        x, y, _ = polar(2.75, a)
        p.sphere((x, y, 1.75), 0.72, "Metal", seg=10, rings=6)
    # four legs with foot pads: they may overhang the footprint (the rule allows 1 m)
    p.overhang = True
    for a in (45.0, 135.0, 225.0, 315.0):
        with p.at(RZ(a)):
            p.cyl((2.95, 0, 3.05), (5.35, 0, 0.30), 0.15, seg=8, mat="Metal")
            p.cyl((2.95, 0, 3.05), (4.10, 0, 1.73), 0.24, seg=8, mat="HullDark")
            p.cyl((2.55, 0, 1.25), (5.20, 0, 0.42), 0.10, seg=6, mat="Frame")
            for sy in (-1, 1):
                p.cyl((2.75, sy * 0.95, 1.55), (5.20, 0, 0.42), 0.07, seg=6, mat="Frame")
            with p.at(T(5.35, 0, 0)):
                p.lathe([(0.68, 0.0), (0.68, 0.10), (0.36, 0.24), (0.0, 0.26)], "Frame", seg=12)
                p.sphere((0, 0, 0.30), 0.20, "Metal", seg=8, rings=4)
    p.overhang = False
    # antenna mast with a small dish, and two RCS blocks
    p.vcyl(0.55, 0.55, 6.30, 8.05, 0.045, seg=6, mat="Frame")
    with p.at(T(0.55, 0.55, 7.55), RY(55.0), RZ(0)):
        p.lathe([(0.0, 0.0), (0.46, 0.20), (0.41, 0.23), (0.0, 0.06)], "Hull", seg=12)
        p.vcyl(0, 0, 0.05, 0.38, 0.02, seg=4, mat="Frame")
    p.sphere((0.55, 0.55, 8.08), 0.07, "Light", seg=6, rings=3)
    for a in (22.5, 157.5, 202.5, 337.5):
        with p.at(RZ(a)):
            p.box((3.05, 0, 3.10), (0.30, 0.42, 0.34), "HullDark", bevel=0.04)
    return [p]


def build_solar_array(spec):
    p = Part("Base")
    TILT, SLANT, THICK = 36.0, 1.95, 0.07
    ROW_Y = (-1.12, 1.12)
    ZC = 1.92                                             # height of the panel centre
    MOD_W, GAP, NMOD = 1.06, 0.05, 4
    total = NMOD * MOD_W + (NMOD - 1) * GAP
    for yc in ROW_Y:
        with p.at(T(0, yc, ZC), RX(TILT)):
            for k in range(NMOD):
                x = -total / 2 + MOD_W / 2 + k * (MOD_W + GAP)
                p.box((x, 0, 0), (MOD_W, SLANT, THICK), "Frame", mats={"+z": "Solar"})
                p.box((x, 0, THICK / 2 + 0.004), (0.03, SLANT, 0.006), "Frame", mats={"-z": None})
                p.box((x, 0, THICK / 2 + 0.004), (MOD_W, 0.03, 0.006), "Frame", mats={"-z": None})
            p.box((0, SLANT / 2 + 0.05, 0), (total + 0.10, 0.10, 0.12), "Accent")          # accent trim on the top edge
            p.box((0, -SLANT / 2 - 0.04, 0), (total + 0.10, 0.08, 0.10), "Frame")
            for yy in (-0.55, 0.55):
                p.box((0, yy, -THICK / 2 - 0.05), (total, 0.10, 0.10), "Frame")
        # posts: short one at the low (-Y) edge, tall one at the high (+Y) edge
        c, s = cos(radians(TILT)), sin(radians(TILT))
        for sx in (-1.55, 1.55):
            for yy in (-0.55, 0.55):
                top = ZC + yy * s - 0.10
                p.box0(sx, yc + yy * c, 0.0, 0.12, 0.12, top, "Frame")
            p.beam((sx, yc - 0.55 * c, 0.25), (sx, yc + 0.55 * c, ZC + 0.55 * s - 0.35), 0.07, 0.07, "Frame")
    for sx in (-1.55, 1.55):                               # ground skids
        p.box0(sx, 0, 0.0, 0.22, 3.5, 0.14, "HullDark")
    # junction box (accent) at the front, with a cable duct
    p.box0(2.55, 0.0, 0.0, 0.62, 0.80, 0.95, "Accent", bevel=0.06)
    p.box((2.55, 0, 1.0), (0.70, 0.88, 0.08), "HullDark")
    p.box((2.865, 0, 0.55), (0.012, 0.5, 0.3), "Frame", mats={"-x": None})
    p.sphere((2.55, 0.25, 1.09), 0.07, "Light", seg=6, rings=3)
    p.box0(2.0, 0.0, 0.0, 0.9, 0.16, 0.10, "Frame")
    return [p]


def build_wind_turbine(spec):
    b = Part("Base")
    HUB = Vector((0.0, -1.10, 9.0))
    r = Part("Rotor", origin=HUB)
    b.lathe([(1.50, -0.25), (1.50, 0.10), (1.38, 0.22), (0.0, 0.22)], "HullDark", seg=8, smooth=False, phase=22.5)
    b.vcyl(0, 0, 0.22, 0.40, 0.62, seg=12, mat="Frame")
    for k in range(8):
        x, y, _ = polar(0.50, 45.0 * k)
        b.vcyl(x, y, 0.40, 0.47, 0.05, seg=5, mat="Metal")
    b.lathe([(0.42, 0.40), (0.36, 1.30), (0.36, 1.75), (0.33, 2.2), (0.20, 8.55)],
            lambda k, i: ("Hull", "Accent", "Hull", "Hull")[k], seg=14)
    b.box0(0.40, 0, 0.40, 0.10, 0.5, 0.9, "HullDark")                     # service door on +X
    # nacelle along Y, hub on the -Y end
    b.vcyl(0, 0, 8.45, 8.70, 0.34, seg=12, mat="Frame")
    b.box((0, 0.10, 9.0), (0.80, 2.0, 0.80), "Hull", bevel=0.14)
    b.box((0, 0.55, 9.0), (0.84, 0.45, 0.84), "Accent", bevel=0.14)
    b.box((0, 1.0, 9.55), (0.06, 0.5, 0.35), "HullDark")                  # tail fin
    b.sphere((0, 0.6, 9.45), 0.08, "Light", seg=6, rings=3)
    b.cyl((0, -0.90, 9.0), (0, -1.02, 9.0), 0.30, seg=12, mat="Frame")
    # rotor: mesh data is relative to the hub centre, blades lie in the XZ plane and spin around local Y
    r.cyl(HUB + Vector((0, 0.08, 0)), HUB + Vector((0, -0.22, 0)), 0.34, seg=12, mat="Hull")
    r.cyl(HUB + Vector((0, -0.22, 0)), HUB + Vector((0, -0.62, 0)), 0.34, 0.0, seg=12, mat="Accent", cap0=False)
    for k in range(3):
        with r.at(T(*HUB), RY(120.0 * k)):
            rings = []
            for (z, c0, c1, th, tw) in ((0.22, -0.16, 0.16, 0.16, 0.0), (0.75, -0.34, 0.20, 0.10, 8.0),
                                         (2.0, -0.22, 0.12, 0.06, 4.0), (3.2, -0.10, 0.05, 0.03, 0.0)):
                ca, sa = cos(radians(tw)), sin(radians(tw))
                pts = [(c1, -th / 2), (c1, th / 2), (c0, th / 2), (c0, -th / 2)]      # (x, y) CCW seen from +Z
                rings.append([(x * ca - y * sa, x * sa + y * ca, z) for x, y in pts])
            r.loft(rings, "Hull", smooth=False, closed=True, cap0=True, cap1=True)
            r.box((-0.025, 0, 3.05), (0.16, 0.035, 0.30), "Hazard")
    return [b, r]


def build_battery(spec):
    p = Part("Base")
    # skid
    for sx in (-0.45, 0.45):
        p.box0(sx, 0, 0.0, 0.16, 2.80, 0.20, "Frame")
    p.box0(0, 0, 0.12, 1.30, 2.70, 0.10, "HullDark")
    for k in range(3):                                     # three cabinets side by side along Y, fronts face +X
        y = (k - 1) * 0.86
        p.box0(0, y, 0.22, 1.05, 0.80, 1.38, "Hull", bevel=0.06)
        p.box((0.53, y, 0.95), (0.012, 0.62, 0.95), "HullDark", mats={"-x": None})
        p.box((0.535, y, 1.43), (0.014, 0.80, 0.14), "Accent", mats={"-x": None})
        p.box((0.545, y + 0.22, 1.43), (0.03, 0.12, 0.08), "Light")
        for j in range(3):
            p.box((0.537, y - 0.12, 0.70 + 0.2 * j), (0.012, 0.30, 0.05), "Frame", mats={"-x": None})
        for j in range(5):                                 # cooling fins on the top
            p.box0(-0.05, y - 0.28 + 0.14 * j, 1.60, 0.85, 0.045, 0.16, "Metal")
        p.box0(0, y, 1.60, 0.95, 0.72, 0.03, "Frame")
    p.box((0, 0, 1.52), (1.09, 2.56, 0.10), "Accent", mats={"-z": None, "+z": None})     # accent band round the bank
    # rear radiator + bus duct
    p.box0(-0.62, 0, 0.30, 0.16, 2.3, 1.0, "Frame")
    for j in range(9):
        p.box0(-0.74, -1.0 + 0.25 * j, 0.35, 0.12, 0.05, 0.90, "Metal")
    p.tube([(0.3, 1.32, 0.45), (0.3, 1.50, 0.45), (0.3, 1.50, 0.08)], 0.06, seg=6, mat="Rubber", fillet=0.1)
    return [p]


def build_water_extractor(spec):
    p = Part("Base")
    APEX_Z = 4.15
    legs = (60.0, 180.0, 300.0)
    feet = [Vector(polar(2.08, a, 0.0)) for a in legs]
    tops = [Vector(polar(0.32, a, APEX_Z)) for a in legs]
    for f, t, a in zip(feet, tops, legs):
        p.beam(f + Vector((0, 0, 0.10)), t, 0.17, 0.17, "Frame")
        with p.at(T(f.x, f.y, 0.0), RZ(a)):
            p.box0(0, 0, 0.0, 0.62, 0.62, 0.14, "HullDark")
    for z in (1.45, 2.85):
        k = z / APEX_Z
        ring = [f + (t - f) * k for f, t in zip(feet, tops)]
        for i in range(3):
            p.beam(ring[i], ring[(i + 1) % 3], 0.10, 0.10, "Frame")
    for i in range(3):                                     # diagonal braces, lower bay
        a = feet[i] + (tops[i] - feet[i]) * (0.3 / APEX_Z)
        b_ = feet[(i + 1) % 3] + (tops[(i + 1) % 3] - feet[(i + 1) % 3]) * (1.45 / APEX_Z)
        p.beam(a, b_, 0.07, 0.07, "Frame")
    # crown block (accent) + top sheave
    p.vcyl(0, 0, APEX_Z - 0.12, APEX_Z + 0.22, 0.52, seg=6, mat="Accent", smooth=False)
    p.cyl((0, -0.09, APEX_Z + 0.40), (0, 0.09, APEX_Z + 0.40), 0.24, seg=10, mat="Frame")
    # wellhead + drill string + drive head
    p.lathe([(0.62, 0.0), (0.62, 0.22), (0.42, 0.30), (0.42, 0.62), (0.30, 0.70), (0.30, 1.0), (0.0, 1.0)],
            lambda k, i: ("HullDark", "HullDark", "WaterBlue", "HullDark", "HullDark", "HullDark")[k], seg=12)
    p.vcyl(0, 0, 1.0, APEX_Z, 0.085, seg=8, mat="Metal", cap0=False, cap1=False)
    p.box((0, 0, 2.25), (0.62, 0.62, 0.55), "HullDark", bevel=0.06)
    p.box((0, 0, 2.25), (0.66, 0.66, 0.16), "Accent")
    # pump skid on +X, pipe run with blue bands, outlet riser
    p.box0(1.25, 0, 0.0, 1.30, 1.10, 0.14, "Frame")
    p.box0(1.10, 0, 0.14, 0.80, 0.80, 0.75, "Hull", bevel=0.06)
    p.box((1.10, 0, 0.72), (0.84, 0.84, 0.16), "Accent")
    p.cyl((1.45, 0, 0.55), (1.95, 0, 0.55), 0.26, seg=10, mat="Metal")
    p.tube([(0.30, 0, 0.46), (0.75, 0, 0.46)], 0.10, seg=8, mat="Metal", caps=False)
    p.tube([(1.95, 0, 0.55), (2.25, 0, 0.55), (2.25, 0, 1.25), (2.25, -0.45, 1.25)], 0.09, seg=8, mat="Metal", fillet=0.16)
    p.cyl((2.25, 0, 0.75), (2.25, 0, 1.0), 0.12, seg=8, mat="WaterBlue")
    p.cyl((2.25, -0.45, 1.25), (2.25, -0.55, 1.25), 0.14, seg=8, mat="WaterBlue")
    # small separator tank on the -Y side
    sx, sy, _ = polar(1.45, 250.0)
    p.vcyl(sx, sy, 0.0, 0.12, 0.50, seg=12, mat="Frame")
    p.vcyl(sx, sy, 0.12, 1.55, 0.42, seg=12, mat="Hull", cap1=False)
    p.vcyl(sx, sy, 0.70, 1.00, 0.44, seg=12, mat="WaterBlue", cap0=False, cap1=False)
    with p.at(T(sx, sy, 1.55)):
        p.lathe(dome_profile(0.42, 0.0, 0.26, 3), "Hull", seg=12)
    p.tube([(sx, sy, 1.75), (sx, sy, 2.0), (sx * 0.2, sy * 0.2, 2.0), (sx * 0.2, sy * 0.2, 1.0)], 0.06, seg=6, mat="Metal", fillet=0.15)
    return [p]


def build_reservoir(spec):
    p = Part("Base")
    R, ZC = 1.40, 1.80
    # tank: lathe about local Z, then turned so the axis lies along X
    prof = [(0.0, -2.42), (0.72, -2.30), (1.16, -2.08), (R, -1.80), (R, -1.32), (R, -1.02), (R, 1.02), (R, 1.32), (R, 1.80),
            (1.16, 2.08), (0.72, 2.30), (0.0, 2.42)]
    mats = ["Hull", "Hull", "Hull", "Hull", "Accent", "Hull", "Accent", "Hull", "Hull", "Hull", "Hull"]
    with p.at(T(0, 0, ZC), RY(90.0)):
        p.lathe(prof, lambda k, i: mats[k], seg=20)
        # water level stripes on both upper shoulders (local angle 180 deg = up)
        for a0 in (118.0, 214.0):
            p.lathe([(R, -1.0), (R + 0.035, -1.0), (R + 0.035, 1.0), (R, 1.0)], "WaterBlue", seg=3, a0=a0, a1=a0 + 28.0, smooth=True)
    # cradle: two saddles on a skid
    for sx in (-1.15, 1.15):
        p.prism_x([(-1.30, 0.0), (1.30, 0.0), (1.30, 0.55), (0.95, 1.25), (-0.95, 1.25), (-1.30, 0.55)], sx - 0.20, sx + 0.20, "Frame")
    for sy in (-1.15, 1.15):
        p.box0(0, sy, 0.0, 3.4, 0.22, 0.16, "HullDark")
    # manhole + vent on top, inlet pipe to the back, outlet with valve to the front
    p.vcyl(0.0, 0, ZC + R - 0.10, ZC + R + 0.14, 0.42, seg=12, mat="HullDark")
    p.vcyl(0.0, 0, ZC + R + 0.14, ZC + R + 0.20, 0.30, seg=12, mat="Accent")
    p.tube([(-1.0, 0, ZC + R - 0.05), (-1.0, 0, ZC + R + 0.30), (-2.62, 0, ZC + R + 0.30), (-2.62, 0, 0.10)], 0.10, seg=8,
           mat="Metal", fillet=0.3)
    p.cyl((-2.62, 0, 0.9), (-2.62, 0, 1.25), 0.135, seg=8, mat="WaterBlue")
    p.tube([(2.30, 0, 0.95), (2.68, 0, 0.95), (2.68, 0, 0.10)], 0.11, seg=8, mat="Metal", fillet=0.2)
    p.cyl((2.42, 0, 0.95), (2.56, 0, 0.95), 0.15, seg=8, mat="WaterBlue")
    p.vcyl(2.68, 0, 0.0, 0.10, 0.20, seg=8, mat="Frame")
    p.vcyl(-2.62, 0, 0.0, 0.10, 0.20, seg=8, mat="Frame")
    # level gauge: a sight glass pipe beside the front end cap
    gx, gy = 2.55, -0.50
    p.vcyl(gx, gy, ZC - 0.80, ZC + 0.80, 0.07, seg=8, mat="Frame")
    p.vcyl(gx, gy, ZC - 0.62, ZC + 0.25, 0.09, seg=8, mat="WaterBlue", cap0=False, cap1=False)
    for dz in (-0.70, 0.70):
        p.cyl((1.80, gy, ZC + dz), (gx, gy, ZC + dz), 0.05, seg=6, mat="Frame")
    return [p]


def build_landing_pad(spec):
    p = Part("Base")
    SEG = 48
    TOP = 0.35
    p.lathe([(8.90, 0.0), (8.90, 0.25), (8.78, TOP), (0.0, TOP)], lambda k, i: ("Frame", "Hazard", "HullDark")[k], seg=SEG)
    z = TOP + 0.012
    p.ring_flat(7.35, 7.85, z, "Accent", seg=SEG)
    p.ring_flat(3.55, 3.85, z, "Hull", seg=SEG)
    p.ring_flat(0.75, 1.05, z, "Hazard", seg=24)
    for k in range(4):                                     # centre marking: four bars
        with p.at(RZ(90.0 * k)):
            p.box((2.15, 0, z), (1.9, 0.62, 0.004), "Hazard", mats={"-z": None})
    for k in range(8):                                     # approach ticks on the outer ring
        with p.at(RZ(45.0 * k + 22.5)):
            p.box((6.55, 0, z), (0.9, 0.30, 0.004), "Hull", mats={"-z": None})
    for k in range(8):                                     # eight edge lights
        x, y, _ = polar(8.40, 45.0 * k + 22.5)
        p.vcyl(x, y, TOP, TOP + 0.16, 0.17, seg=8, mat="Frame")
        p.sphere((x, y, TOP + 0.18), 0.13, "Light", seg=8, rings=4)
    # control kiosk at the edge on -X
    with p.at(T(-7.95, 0, TOP)):
        p.box0(0, 0, 0, 1.30, 1.70, 2.05, "Hull", bevel=0.10)
        p.box((0.20, 0, 1.45), (0.95, 1.74, 0.42), "Window", mats={"-x": None})
        p.box((0, 0, 1.92), (1.34, 1.74, 0.16), "Accent")
        p.box0(0, 0, 2.05, 1.0, 1.3, 0.10, "HullDark")
        p.vcyl(-0.3, 0.5, 2.15, 3.1, 0.03, seg=5, mat="Frame")
        p.sphere((-0.3, 0.5, 3.12), 0.07, "Light", seg=6, rings=3)
        p.box0(0.70, -0.4, 0, 0.12, 0.55, 1.0, "HullDark")
    return [p]


# @@EXTERIORS@@

# --------------------------------------------------------------------------------------
# CORRIDOR, COLONIST, PROPS
# --------------------------------------------------------------------------------------
def build_corridor(spec):
    """One segment, exactly 1.0 m long on X. The game scales it on X, so nothing here depends on X detail
    except the two end ribs."""
    b, r = Part("Base"), Part("Roof")
    F = FLOOR_Z
    HALF, WALL_H, WT = 1.18, 1.00, 0.18            # wall faces at y = 1.18, the outer stripe reaches y = 1.20 exactly
    b.box((0, 0, (F - 0.05) / 2), (1.0, 2 * (HALF - WT), F + 0.05), "HullDark", mats={"+y": None, "-y": None, "-z": None})
    for sy in (-1, 1):
        yc = sy * (HALF - WT / 2)
        b.box((0, yc, (WALL_H - 0.05) / 2), (1.0, WT, WALL_H + 0.05), "Hull", mats={"-z": None, "+z": "Frame"})
        b.box((0, sy * (HALF + 0.01), 0.62), (1.0, 0.02, 0.20), "HullDark", mats={"-y" if sy > 0 else "+y": None})
        b.box((0, sy * (HALF - WT - 0.01), 0.20), (1.0, 0.02, 0.12), "Frame", mats={"+y" if sy > 0 else "-y": None, "-z": None})
    # arched roof: glass shell over the full length + one frame rib at each end
    N = 12

    def arc(ry, rz, x):
        return [(x, ry * cos(pi * i / N), WALL_H + rz * sin(pi * i / N)) for i in range(N + 1)]
    r.loft([arc(1.155, 1.355, -0.5), arc(1.155, 1.355, 0.5)], lambda k, i: "Hull" if i in (0, N - 1) else "Glass",
           smooth=True, closed=False)
    for (x0, x1) in ((-0.5, -0.41), (0.41, 0.5)):
        r.loft([arc(1.20, 1.40, x0), arc(1.20, 1.40, x1), arc(1.08, 1.28, x1), arc(1.08, 1.28, x0)], "Frame",
               smooth=True, closed=False, wrap=True)
    return [b, r]


def build_colonist(spec):
    HIP_Z, HIP_Y = 0.86, 0.115
    SH_Z, SH_Y = 1.34, 0.315
    body = Part("Body")
    body.box((0, 0, 0.88), (0.27, 0.40, 0.22), "SuitMain", bevel=0.04)                 # pelvis
    body.box((0, 0, 1.18), (0.32, 0.48, 0.50), "SuitMain", bevel=0.07)                 # torso
    body.box((0, 0, 1.20), (0.335, 0.495, 0.10), "SuitAccent")                         # chest band
    body.box((0.17, 0, 1.06), (0.06, 0.22, 0.13), "Pack")                              # chest control unit
    body.box((0.205, 0.05, 1.08), (0.012, 0.06, 0.04), "SuitAccent", mats={"-x": None})
    for sy in (-1, 1):
        body.box((0, sy * 0.30, 1.41), (0.27, 0.21, 0.11), "SuitAccent", bevel=0.04)   # shoulder pads
    body.vcyl(0, 0, 1.40, 1.47, 0.15, seg=10, mat="Pack")                              # neck ring
    R, SEG, RINGS = 0.215, 12, 8
    prof = [(R * cos(radians(-90 + 180 * k / RINGS)), R * sin(radians(-90 + 180 * k / RINGS))) for k in range(RINGS + 1)]
    prof[0], prof[-1] = (0.0, -R), (0.0, R)

    def helmet_mat(k, i):
        return "Visor" if (i in (0, 1, SEG - 2, SEG - 1) and k in (3, 4, 5)) else "SuitMain"
    with body.at(T(0.01, 0, 1.585)):
        body.lathe(prof, helmet_mat, seg=SEG)
    body.box((-0.27, 0, 1.17), (0.22, 0.40, 0.58), "Pack", bevel=0.05)                 # life-support pack
    body.box((-0.385, 0, 1.30), (0.012, 0.22, 0.08), "SuitAccent", mats={"+x": None})
    body.vcyl(-0.30, 0.13, 1.46, 1.68, 0.012, seg=4, mat="Pack")
    parts = [body]
    for name, sy in (("ArmL", 1), ("ArmR", -1)):                                       # left = +Y when facing +X
        a = Part(name, origin=(0.0, sy * SH_Y, SH_Z))
        a.sphere((0, sy * SH_Y, SH_Z), 0.095, "SuitMain", seg=8, rings=4)
        a.cyl((0, sy * SH_Y, SH_Z), (0.02, sy * (SH_Y + 0.03), 0.86), 0.078, 0.064, seg=8, mat="SuitMain")
        a.cyl((0.02, sy * (SH_Y + 0.03), 0.90), (0.02, sy * (SH_Y + 0.03), 0.86), 0.076, seg=8, mat="SuitAccent")
        a.sphere((0.025, sy * (SH_Y + 0.03), 0.80), 0.075, "Pack", seg=8, rings=4)
        parts.append(a)
    for name, sy in (("LegL", 1), ("LegR", -1)):
        g = Part(name, origin=(0.0, sy * HIP_Y, HIP_Z))
        g.cyl((0, sy * HIP_Y, HIP_Z + 0.02), (0, sy * HIP_Y, 0.12), 0.108, 0.088, seg=8, mat="SuitMain")
        g.box((0.085, sy * HIP_Y, 0.50), (0.05, 0.13, 0.14), "SuitAccent")
        g.box((0.045, sy * HIP_Y, 0.07), (0.30, 0.18, 0.14), "Pack", bevel=0.04)
        parts.append(g)
    return parts


def build_crate(spec):
    p = Part("Crate")
    # total size is 0.45 x 0.45 x 0.45: the body is 8 mm lower so the lid straps end at z = 0.45
    # and the body is 10 mm narrower so the band (5 mm proud) ends at +/-0.225
    p.box0(0, 0, 0.0, 0.44, 0.44, 0.442, "Cargo", bevel=0.04)                     # 44 triangles
    p.box0(0, 0, 0.165, 0.45, 0.45, 0.12, "Frame", mats={"-z": None})             # band, 10 triangles
    p.box((0, 0, 0.445), (0.10, 0.37, 0.010), "Frame", mats={"-z": None})          # cross straps on the lid, 10 + 10
    p.box((0, 0, 0.4445), (0.37, 0.10, 0.010), "Frame", mats={"-z": None})
    return [p]


def build_rock(spec):
    rng = random.Random(spec["seed"])
    p = Part("Rock")

    def boulder(cx, cy, rx, ry, rz, n, sink=0.25, vein_w=0.05, cuts_n=5):
        """Random points on a jittered, faceted ellipsoid -> convex hull. The flat underside sits 3 cm in the ground."""
        cuts = []                                           # random fracture planes give large flat facets
        for _ in range(cuts_n):
            nz = rng.uniform(0.15, 1.0)
            a = rng.uniform(0.0, 2 * pi)
            s = sqrt(1.0 - nz * nz)
            cuts.append((Vector((s * cos(a), s * sin(a), nz)), rng.uniform(0.55, 0.80)))
        pts = []
        for _ in range(n):
            z = rng.uniform(-sink, 1.0)
            a = rng.uniform(0.0, 2 * pi)
            s = sqrt(max(0.0, 1.0 - z * z))
            u = Vector((s * cos(a), s * sin(a), z)) * rng.uniform(0.92, 1.0)
            for cn, cd in cuts:
                t = u.dot(cn) - cd
                if t > 0:
                    u -= cn * t
            pts.append((cx + rx * u.x, cy + ry * u.y, max(rz * u.z, -0.03)))
        nrm = (rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0.5, 1.0))
        p.hull(pts, "Ore", vein=((cx + rng.uniform(-0.15, 0.15) * rx, cy, rz * rng.uniform(0.35, 0.6)), nrm, vein_w * 2.0),
               vein_max=3 if n < 40 else 5)

    v = spec["id"][-1]
    if v == "a":        # one large boulder with a small companion, 2.5 m across
        boulder(-0.10, 0.0, 1.10, 0.95, 1.35, 90, vein_w=0.07)
        boulder(0.98, -0.55, 0.42, 0.38, 0.45, 26, vein_w=0.04)
    elif v == "b":      # cluster of three, 2.6 m across
        boulder(-0.45, 0.05, 0.85, 0.80, 1.05, 60, vein_w=0.06)
        boulder(0.72, -0.25, 0.60, 0.62, 0.70, 44, vein_w=0.05)
        boulder(0.15, 0.85, 0.45, 0.42, 0.50, 28, vein_w=0.04)
    else:               # low slab with a leaning shard, 1.4 m across
        boulder(0.0, 0.0, 0.72, 0.58, 0.42, 50, vein_w=0.035)
        pts = []
        for _ in range(30):
            t = rng.uniform(0.0, 1.0)
            a = rng.uniform(0.0, 2 * pi)
            w = 0.27 * (1.0 - 0.72 * t) * rng.uniform(0.85, 1.0)
            pts.append((-0.15 + 0.42 * t + w * cos(a), 0.05 + 0.10 * t + w * sin(a), max(-0.03, 1.10 * t)))
        p.hull(pts, "Ore", vein=((0.05, 0.08, 0.62), (0.3, 0.1, 1.0), 0.05))
    return [p]


def _leaf(part, base, ang, length, width, z_mid, z_tip, mat, segs=1, clamp=(1.4, 0.6)):
    """Folded leaf that points along `ang` (degrees). Plant materials are double sided in the glTF."""
    ca, sa = cos(radians(ang)), sin(radians(ang))

    def pt(u, v, z):
        x, y = base[0] + u * ca - v * sa, base[1] + u * sa + v * ca
        return (max(-clamp[0], min(clamp[0], x)), max(-clamp[1], min(clamp[1], y)), base[2] + z)
    r0 = part.v(pt(0, 0, 0))
    ml = part.v(pt(length * 0.5, width / 2, z_mid))
    mr = part.v(pt(length * 0.5, -width / 2, z_mid))
    if segs == 1:
        tip = part.v(pt(length, 0, z_tip))
        part.f([r0, mr, tip], mat)
        part.f([r0, tip, ml], mat)
    else:
        mc = part.v(pt(length * 0.55, 0, z_mid - width * 0.18))
        tip = part.v(pt(length, 0, z_tip))
        part.f([r0, mr, mc], mat)
        part.f([r0, mc, ml], mat)
        part.f([mc, mr, tip], mat)
        part.f([mc, tip, ml], mat)


def build_crop(spec):
    """Three growth stages in one file, all at the origin. Bed = 2.8 m (X) x 1.2 m (Y), origin on the soil."""
    rng = random.Random(5)
    s1, s2, s3 = Part("Stage1"), Part("Stage2"), Part("Stage3")

    def grid(nx, ny, jit, margin_x, margin_y):
        for iy in range(ny):
            for ix in range(nx):
                x = -1.4 + margin_x + (2.8 - 2 * margin_x) * (ix / (nx - 1))
                y = -0.6 + margin_y + (1.2 - 2 * margin_y) * (iy / (ny - 1))
                yield x + rng.uniform(-jit, jit), y + rng.uniform(-jit, jit)

    for x, y in grid(12, 5, 0.03, 0.10, 0.10):              # Stage1: sprouts, 0.1 m
        h = rng.uniform(0.05, 0.07)
        a = rng.uniform(0, 180)
        s1.convex([(x - 0.012, y - 0.008, 0), (x + 0.012, y - 0.008, 0), (x, y + 0.014, 0), (x, y, h)],
                  [(0, 1, 3), (1, 2, 3), (2, 0, 3)], "PlantDark")
        for da in (0.0, 180.0):
            _leaf(s1, (x, y, h - 0.005), a + da, rng.uniform(0.06, 0.085), 0.05, 0.035, rng.uniform(0.03, 0.045), "Plant")
    for x, y in grid(8, 4, 0.04, 0.17, 0.15):               # Stage2: leafy rosettes, 0.35 m
        a0 = rng.uniform(0, 60)
        hh = rng.uniform(0.27, 0.35)
        s2.convex([(x - 0.05, y - 0.05, 0), (x + 0.05, y - 0.05, 0), (x + 0.05, y + 0.05, 0), (x - 0.05, y + 0.05, 0), (x, y, hh)],
                  [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], "Plant")
        for k in range(6):
            _leaf(s2, (x, y, 0.02), a0 + 60.0 * k + rng.uniform(-8, 8), rng.uniform(0.17, 0.22), 0.13,
                  rng.uniform(0.15, 0.22), rng.uniform(0.10, 0.30), "PlantDark" if k % 2 else "Plant", segs=2)
    for x, y in grid(7, 3, 0.05, 0.20, 0.18):               # Stage3: tall plants with fruit, 0.7 m
        hh = rng.uniform(0.62, 0.70)
        a0 = rng.uniform(0, 120)
        s3.cyl((x, y, 0.0), (x, y, hh - 0.08), 0.028, 0.014, seg=4, mat="PlantDark", smooth=False, cap0=False, cap1=False)
        for k in range(3):
            _leaf(s3, (x, y, 0.16), a0 + 120.0 * k, rng.uniform(0.26, 0.32), 0.16, 0.14, 0.04, "PlantDark", segs=2)
        for k in range(3):
            _leaf(s3, (x, y, 0.38), a0 + 60.0 + 120.0 * k, rng.uniform(0.20, 0.26), 0.13, 0.11, 0.06, "Plant")
        for k in range(3):
            _leaf(s3, (x, y, hh - 0.12), a0 + 120.0 * k + 30.0, 0.15, 0.09, 0.10, 0.12, "Plant")
        for k in range(2):
            fa = radians(a0 + 45.0 + 180.0 * k + rng.uniform(-30, 30))
            fz = rng.uniform(0.24, 0.46)
            fx = max(-1.34, min(1.34, x + 0.085 * cos(fa)))
            fy = max(-0.54, min(0.54, y + 0.085 * sin(fa)))
            q = 0.055
            s3.convex([(fx + q, fy, fz), (fx - q, fy, fz), (fx, fy + q, fz), (fx, fy - q, fz), (fx, fy, fz + q * 1.1), (fx, fy, fz - q * 1.1)],
                      [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)], "OreVein")
    return [s1, s2, s3]


# @@PROPS@@

# --------------------------------------------------------------------------------------
# MODEL TABLE (the data that drives the build)
# --------------------------------------------------------------------------------------
ROOM_OBJECTS = ["Base", "Roof", "Interior"]

MODELS = [
    dict(id="lander",          footprint=5.5, kind="special",  accent="logistics",    objects=["Base"], overhang=1.0, height=7.0),
    dict(id="solar_array",     footprint=3.2, kind="exterior", accent="utilities",    objects=["Base"], height=2.6),
    dict(id="wind_turbine",    footprint=1.6, kind="exterior", accent="utilities",    objects=["Base", "Rotor"], free_objects=["Rotor"], height=9.0),
    dict(id="battery",         footprint=1.8, kind="exterior", accent="utilities",    objects=["Base"], height=1.8),
    dict(id="water_extractor", footprint=2.6, kind="exterior", accent="life_support", objects=["Base"], height=4.5),
    dict(id="reservoir",       footprint=3.0, kind="exterior", accent="life_support", objects=["Base"], height=3.2),
    dict(id="oxygen_plant",    footprint=3.6, kind="room",     accent="life_support", height=3.6, seg=24),
    dict(id="airlock",         footprint=2.8, kind="room",     accent="life_support", height=3.0, seg=24, drum=True),
    dict(id="habitat",         footprint=5.5, kind="room",     accent="housing",      height=4.2),
    dict(id="kitchen",         footprint=4.6, kind="room",     accent="food",         height=3.8),
    dict(id="greenhouse",      footprint=6.0, kind="room",     accent="food",         height=4.4),
    dict(id="storehouse",      footprint=5.5, kind="room",     accent="logistics",    height=3.8),
    dict(id="mine",            footprint=5.0, kind="room",     accent="industry",     height=3.6),
    dict(id="refinery",        footprint=5.0, kind="room",     accent="industry",     height=3.8),
    dict(id="polymer_plant",   footprint=5.0, kind="room",     accent="industry",     height=3.8),
    dict(id="medical",         footprint=4.5, kind="room",     accent="medical",      height=3.6),
    dict(id="lounge",          footprint=5.0, kind="room",     accent="comfort",      height=3.8),
    dict(id="workshop",        footprint=5.0, kind="room",     accent="industry",     height=3.8),
    dict(id="landing_pad",     footprint=9.0, kind="exterior", accent="logistics",    objects=["Base"], height=0.35),
    dict(id="junction",        footprint=2.5, kind="room",     accent="logistics",    height=2.8, seg=24),
    dict(id="corridor",        footprint=None, kind="segment", accent=None,           objects=["Base", "Roof"], zmin=-0.05),
    dict(id="colonist",        footprint=None, kind="unit",    accent=None,           objects=["Body", "ArmL", "ArmR", "LegL", "LegR"],
         tri_budget=1500, zmin=-0.05),
    dict(id="crate",           footprint=None, kind="prop",    accent=None,           objects=["Crate"], tri_budget=100, zmin=-0.05),
    dict(id="rock_a",          footprint=None, kind="prop",    accent=None,           objects=["Rock"], tri_budget=300, zmin=-0.05, seed=11),
    dict(id="rock_b",          footprint=None, kind="prop",    accent=None,           objects=["Rock"], tri_budget=300, zmin=-0.05, seed=23),
    dict(id="rock_c",          footprint=None, kind="prop",    accent=None,           objects=["Rock"], tri_budget=300, zmin=-0.05, seed=37),
    dict(id="crop",            footprint=None, kind="prop",    accent=None,           objects=["Stage1", "Stage2", "Stage3"],
         tri_budget=3600, object_budget=1200, zmin=-0.05),
]
for _m in MODELS:
    if _m["kind"] == "room":
        _m.setdefault("objects", ROOM_OBJECTS)
    _m.setdefault("tri_budget", 4000)
    _m.setdefault("zmin", -0.30)
    _m["accent_hex"] = ACCENTS.get(_m["accent"]) if _m["accent"] else None
MODEL_BY_ID = {m["id"]: m for m in MODELS}


def builder_for(spec):
    name = "build_rock" if spec["id"].startswith("rock_") else "build_" + spec["id"]
    return globals().get(name)


# --------------------------------------------------------------------------------------
# Build + checks
# --------------------------------------------------------------------------------------
def part_stats(part):
    tris = sum(len(f) - 2 for f in part.faces)
    xs = [v.x for v in part.verts]; ys = [v.y for v in part.verts]; zs = [v.z for v in part.verts]
    rad = max((math.hypot(v.x, v.y) for v, o in zip(part.verts, part.vover) if not o), default=0.0)
    rad_over = max((math.hypot(v.x, v.y) for v, o in zip(part.verts, part.vover) if o), default=0.0)
    return dict(tris=tris, bbox=((min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))), radius=rad, radius_overhang=rad_over)


def check_interior(spec, parts, flags):
    """Interior must stay inside the wall and under the roof shell."""
    part = next((p for p in parts if p.name == "Interior"), None)
    if part is None or not part.verts:
        flags.append("Interior is empty")
        return
    rm = Room(dict(spec, wall_r=2.30)) if spec.get("drum") else Room(spec)
    if spec["id"] == "storehouse":
        rm.Hv = WALL_TOP + (spec["height"] - WALL_TOP) / sin(radians(STORE_T1))
    worst_r, worst_z = 0.0, -9.0
    for v in part.verts:
        r = math.hypot(v.x, v.y)
        worst_r = max(worst_r, r - rm.Ri)
        lim = spec["height"] - 0.5 if spec.get("drum") else min(rm.dome_z(r), spec["height"])
        worst_z = max(worst_z, v.z - lim)
    if worst_r > 0.0:
        flags.append("Interior passes the inner wall by %.2f m" % worst_r)
    if worst_z > -0.02:
        flags.append("Interior passes the roof shell by %.2f m" % (worst_z + 0.02))


def build_model(spec):
    t0 = time.time()
    fn = builder_for(spec)
    if fn is None:
        raise RuntimeError("no builder function for " + spec["id"])
    reset_scene()
    parts = fn(spec)
    mset = MaterialSet(spec["accent_hex"])
    for part in parts:
        part_to_object(part, mset)
    path = os.path.join(OUT_DIR, spec["id"] + ".glb")
    if os.path.exists(path):
        os.remove(path)
    export_glb(path)

    flags = []
    stats = {p.name: part_stats(p) for p in parts}
    free = set(spec.get("free_objects", []))
    tris = sum(s["tris"] for s in stats.values())
    mins = [min(s["bbox"][0][i] for s in stats.values()) for i in range(3)]
    maxs = [max(s["bbox"][1][i] for s in stats.values()) for i in range(3)]
    radius = max((s["radius"] for n, s in stats.items() if n not in free), default=0.0)
    radius_over = max((s["radius_overhang"] for n, s in stats.items() if n not in free), default=0.0)
    radius_free = max((max(s["radius"], s["radius_overhang"]) for n, s in stats.items() if n in free), default=0.0)

    if not os.path.exists(path) or os.path.getsize(path) == 0:
        flags.append("GLB missing or empty")
        info = {}
    else:
        info = inspect_glb(path)
        if sorted(info["top"]) != sorted(spec["objects"]):
            flags.append("top-level objects %s != %s" % (info["top"], spec["objects"]))
        if info["child_nodes"]:
            flags.append("exported nodes have children")
        for key in ("has_cameras", "has_animations", "has_skins", "has_lights", "has_images"):
            if info[key]:
                flags.append(key)
        glb_tris = sum(info["tris"].values())
        if glb_tris != tris:
            flags.append("GLB triangle count %d != built %d" % (glb_tris, tris))
        unknown = [m for m in info["materials"] if m != "Accent" and m not in MATERIALS]
        if unknown:
            flags.append("unknown materials %s" % unknown)
        if "Accent" in info["materials"] and not spec["accent_hex"]:
            flags.append("Accent used without an accent colour")
        if spec["accent_hex"] and "Accent" not in info["materials"]:
            flags.append("no Accent detail")
        if "Glass" in info["alpha"] and info["alpha"]["Glass"] != "BLEND":
            flags.append("Glass alphaMode is %s" % info["alpha"]["Glass"])
        if spec["kind"] != "unit" and any(m in info["materials"] for m in ("SuitMain", "SuitAccent", "Visor", "Pack")):
            flags.append("colonist-only material used")
    if tris > spec["tri_budget"]:
        flags.append("over triangle budget %d" % spec["tri_budget"])
    if "object_budget" in spec:
        for n, s in stats.items():
            if s["tris"] > spec["object_budget"]:
                flags.append("%s over %d triangles" % (n, spec["object_budget"]))
    fp = spec["footprint"]
    if fp:
        if radius > fp + 1e-4:
            flags.append("EXCEEDS FOOTPRINT: r=%.3f > %.2f" % (radius, fp))
        elif radius > fp - 0.1 + 1e-3:
            flags.append("inside footprint but margin is %.2f m" % (fp - radius))
        if radius_over > fp + spec.get("overhang", 0.0) + 1e-4:
            flags.append("overhang parts exceed footprint + %.1f: r=%.3f" % (spec.get("overhang", 0.0), radius_over))
    if mins[2] < spec["zmin"] - 1e-4:
        flags.append("goes below z=%.2f (zmin=%.3f)" % (spec["zmin"], mins[2]))
    if spec["kind"] == "room":
        check_interior(spec, parts, flags)
    return dict(
        id=spec["id"], kind=spec["kind"], footprint=fp, tris=tris,
        tris_by_object={n: s["tris"] for n, s in stats.items()},
        bbox_min=[round(v, 3) for v in mins], bbox_max=[round(v, 3) for v in maxs],
        max_radius=round(radius, 3), max_radius_overhang_parts=round(radius_over, 3),
        max_radius_free_objects=round(radius_free, 3),
        file_size=os.path.getsize(path) if os.path.exists(path) else 0,
        objects=info.get("top", []), materials=info.get("materials", []),
        translations=info.get("translations", {}), flags=flags, seconds=round(time.time() - t0, 2),
    )


def print_table(rows):
    print("")
    print("%-16s %6s  %-44s %16s %6s %9s  %s" % ("id", "tris", "bbox min .. max (Blender x,y,z)", "max XY radius", "foot", "bytes", "flags"))
    print("-" * 150)
    for r in rows:
        bbox = "(%.2f,%.2f,%.2f)..(%.2f,%.2f,%.2f)" % (*r["bbox_min"], *r["bbox_max"])
        rad = "%.2f" % r["max_radius"]
        if r["max_radius_overhang_parts"] > r["max_radius"]:
            rad += " legs %.2f" % r["max_radius_overhang_parts"]
        if r["max_radius_free_objects"] > 0:
            rad += " rotor %.2f" % r["max_radius_free_objects"]
        print("%-16s %6d  %-44s %16s %6s %9d  %s" % (r["id"], r["tris"], bbox, rad,
              ("%.1f" % r["footprint"]) if r["footprint"] else "-", r["file_size"], "; ".join(r["flags"]) or "ok"))
    print("")


def write_reports(rows):
    existing = {}
    if os.path.exists(REPORT_JSON):
        try:
            with open(REPORT_JSON, "r", encoding="utf-8") as fh:
                existing = {r["id"]: r for r in json.load(fh)["models"]}
        except Exception:
            existing = {}
    for r in rows:
        existing[r["id"]] = r
    ordered = [existing[m["id"]] for m in MODELS if m["id"] in existing]
    with open(REPORT_JSON, "w", encoding="utf-8") as fh:
        json.dump(dict(blender=bpy.app.version_string, models=ordered), fh, indent=1)
    lines = ["# Build report", "", "Written by `build_assets.py`. Blender " + bpy.app.version_string + ".",
             "Coordinates are Blender coordinates (Z up). `max r` is the largest horizontal distance of a vertex from the origin.", "",
             "| id | triangles | per object | X x Y (m) | z min | z max | max r | footprint | bytes | flags |",
             "|---|---:|---|---|---:|---:|---:|---:|---:|---|"]
    for r in ordered:
        size = " x ".join("%.2f" % (b - a) for a, b in list(zip(r["bbox_min"], r["bbox_max"]))[:2])
        per = ", ".join("%s %d" % kv for kv in r["tris_by_object"].items())
        rad = "%.2f" % r["max_radius"]
        if r["max_radius_overhang_parts"] > r["max_radius"]:
            rad += " (legs %.2f)" % r["max_radius_overhang_parts"]
        if r["max_radius_free_objects"] > 0:
            rad += " (rotor %.2f)" % r["max_radius_free_objects"]
        lines.append("| `%s` | %d | %s | %s | %.2f | %.2f | %s | %s | %d | %s |" % (
            r["id"], r["tris"], per, size, r["bbox_min"][2], r["bbox_max"][2], rad,
            ("%.1f" % r["footprint"]) if r["footprint"] else "-", r["file_size"], "; ".join(r["flags"]) or "ok"))
    with open(REPORT_MD, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--legacy-v1" not in argv:
        # Version 2.0: the room buildings are made by tools/blender/rooms_build.py (ART-A); the exteriors,
        # specials, crops and colonists by tools/blender/ext_*.py (ART-B).  The v1 builders below stay as a
        # library and for reference.  A plain run of this file builds the 2.0 rooms, so it can never write
        # v1 files over the 2.0 files.
        import rooms_build
        rooms_build.main()
        return
    only = None
    if "--list" in argv:
        for m in MODELS:
            print(m["id"])
        return
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
        unknown = [s for s in only if s not in MODEL_BY_ID]
        if unknown:
            raise SystemExit("unknown model id: " + ", ".join(unknown))
    if not only:
        raise SystemExit("--legacy-v1 needs --only id1,id2 (a full v1 run would overwrite the 2.0 files)")
    os.makedirs(OUT_DIR, exist_ok=True)
    rows = []
    for spec in MODELS:
        if only and spec["id"] not in only:
            continue
        if builder_for(spec) is None:
            print("SKIP (no builder yet):", spec["id"])
            continue
        print("building", spec["id"], "...")
        rows.append(build_model(spec))
    print_table(rows)
    write_reports(rows)
    bad = [r["id"] for r in rows if r["flags"]]
    print("models built: %d, with flags: %d %s" % (len(rows), len(bad), bad))


if __name__ == "__main__":
    main()
