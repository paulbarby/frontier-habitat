"""
Frontier Habitat 5.0 - ART-NPC: mesh data for the people (heads, hair, hands, outfits).

MeshData keeps, per vertex, a position and a weight rule (npc_common rules: bone name, dict, Chain or callable), and per
face corner a UV.  to_object() makes a skinned Blender object on the rig with UVs, materials, vertex groups and an
Armature modifier.  Materials come from PEOPLE_MATERIALS (names are the contract names in people_manifest.json).
"""
import bpy
import os
import sys
from math import radians
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402

# name: (base colour sRGB hex, roughness, metallic, texture file or None, emission hex or None)
PEOPLE_MATERIALS = {
    # tinted by the game: Skin (skin tone, replace-albedo like v3 mode 2; the face texture multiplies),
    # Hair (hair colour, mode 3), SuitAccent (department / role colour, mode 1), ClothTint (per-person clothes colour)
    "Skin":       ("#d9a47e", 0.62, 0.0, None, None),
    "Hair":       ("#4a3326", 0.55, 0.0, None, None),
    "SuitAccent": ("#ff9f1c", 0.55, 0.0, None, None),
    "ClothTint":  ("#6b7a8f", 0.80, 0.0, None, None),
    # plain (not tinted)
    "Eye":        ("#ffffff", 0.08, 0.0, "people_eyes.png", None),
    "Mouth":      ("#1c0808", 0.80, 0.0, None, None),
    "LipInner":   ("#8a4646", 0.45, 0.0, None, None),
    "Teeth":      ("#e9e4d8", 0.35, 0.0, None, None),
    "Coverall":   ("#56606e", 0.82, 0.0, None, None),
    "Denim":      ("#34496b", 0.86, 0.0, None, None),
    "Cotton":     ("#e8e6e1", 0.85, 0.0, None, None),
    "Leather":    ("#2e2724", 0.55, 0.0, None, None),
    "Sole":       ("#1d1d1f", 0.90, 0.0, None, None),
    "Rubber":     ("#2b2d33", 0.90, 0.0, None, None),
    "Metal":      ("#b8c2cc", 0.35, 0.85, None, None),
    "Frame":      ("#4a5058", 0.50, 0.60, None, None),
    "Screen":     ("#123c4c", 0.25, 0.0, None, "#2fb8d8"),
    "Nail":       ("#e7c2b0", 0.35, 0.0, None, None),
}


def hex_rgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


_MATS = {}


def material(name, texture_dir=None, texture=None):
    """Principled material; an optional image texture multiplies the base colour (the glTF exporter writes it as
    baseColorTexture with the factor)."""
    key = (name, texture)
    if key in _MATS:
        try:
            _MATS[key].name                      # the scene may have been reset since
            return _MATS[key]
        except ReferenceError:
            del _MATS[key]
    col, rough, metal, tex, emit = PEOPLE_MATERIALS[name]
    tex = texture or tex
    m = bpy.data.materials.new(name if texture is None else name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*hex_rgb(col), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*hex_rgb(emit), 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.45
    if tex and texture_dir:
        path = os.path.join(texture_dir, tex)
        if os.path.exists(path):
            img = bpy.data.images.load(path, check_existing=True)
            tn = nt.nodes.new("ShaderNodeTexImage")
            tn.image = img
            # base colour factor x texture: a Mix (multiply) node is not exported; use the texture straight and put
            # the factor into the material: glTF baseColorFactor = the Base Color socket's default when linked is
            # ignored, so bake the factor into the texture instead (see people_textures.py)
            nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    _MATS[key] = m
    return m


class MeshData:
    def __init__(self, name):
        self.name = name
        self.verts = []
        self.rules = []
        self.faces = []          # tuples of vertex indices
        self.fmat = []
        self.fsmooth = []
        self.fuv = []            # per face: list of (u, v) per corner, or None
        self.normals = {}        # vertex index -> analytic normal (custom normals; others use the mesh normal)
        self._rule = [None]

    class _W:
        def __init__(self, md, rule):
            self.md, self.rule = md, rule

        def __enter__(self):
            self.md._rule.append(self.rule)
            return self.md

        def __exit__(self, *a):
            self.md._rule.pop()

    def w(self, rule):
        return MeshData._W(self, rule)

    def v(self, p, rule=None):
        self.verts.append(Vector(p))
        self.rules.append(rule if rule is not None else self._rule[-1])
        return len(self.verts) - 1

    def f(self, idx, mat, smooth=True, uv=None):
        self.faces.append(tuple(idx))
        self.fmat.append(mat)
        self.fsmooth.append(smooth)
        self.fuv.append(uv)

    def tris(self):
        return sum(len(f) - 2 for f in self.faces)

    def append(self, other):
        off = len(self.verts)
        self.verts += other.verts
        self.rules += other.rules
        for f, m, s, uv in zip(other.faces, other.fmat, other.fsmooth, other.fuv):
            self.f([i + off for i in f], m, s, uv)

    def weights(self):
        return [N.limit_normalise(N.resolve_weights(r, p)) for r, p in zip(self.rules, self.verts)]


def to_object(md, rig, texture_dir=None, textures=None):
    """Skinned object on the rig.  textures: {material name: image file} for this object (face texture)."""
    textures = textures or {}
    mesh = bpy.data.meshes.new(md.name)
    mesh.from_pydata([tuple(v) for v in md.verts], [], md.faces)
    names = []
    for m in md.fmat:
        if m not in names:
            names.append(m)
    for n in names:
        mesh.materials.append(material(n, texture_dir, textures.get(n)))
    lookup = {n: i for i, n in enumerate(names)}
    mesh.polygons.foreach_set("material_index", [lookup[m] for m in md.fmat])
    uvl = mesh.uv_layers.new(name="UVMap")
    li = 0
    for poly, uv in zip(mesh.polygons, md.fuv):
        for k in range(poly.loop_total):
            uvl.data[poly.loop_start + k].uv = uv[k] if uv else (0.02, 0.98)
    mesh.update()
    if mesh.validate(verbose=False):
        print("    WARNING: validate() changed", md.name, len(mesh.polygons), "of", len(md.faces), "faces kept")
    attr = mesh.attributes.get("sharp_face") or mesh.attributes.new("sharp_face", "BOOLEAN", "FACE")
    if len(mesh.polygons) == len(md.fsmooth):
        attr.data.foreach_set("value", [not s for s in md.fsmooth])
    mesh.update()
    if md.normals and len(mesh.vertices) == len(md.verts):
        vn = [Vector(v.normal) for v in mesh.vertices]
        for i, n in md.normals.items():
            vn[i] = Vector(n).normalized()
        mesh.normals_split_custom_set_from_vertices([tuple(n) for n in vn])
        mesh.update()
    ob = bpy.data.objects.new(md.name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    if rig is not None:
        ws = md.weights()
        groups = {n: ob.vertex_groups.new(name=n) for n in N.BONE_NAMES}
        for vi, w in enumerate(ws):
            for b, x in w.items():
                groups[b].add([vi], x, "REPLACE")
        ob.parent = rig
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
    return ob
