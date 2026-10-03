"""
Frontier Habitat 5.0 - ART-NPC: LOD2 check sheet.  Per body and outfit: LOD0 (left) and LOD2 (right), tinted as the
game tints them (people_render palettes; the LOD2 vertex colour modes, people_mpfb.export_lod2), posed in walk, seen
from the top and from a high three-quarter view (the all-roofs-off camera), at a small pixel size.

  blender --background --factory-startup --python tools/blender/npc_lod2_sheet.py -- [--bodies m1,f1] [--out path]
"""
import bpy
import os
import sys
import json

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N          # noqa: E402
import npc_render as NR         # noqa: E402
import people_render as PR      # noqa: E402

OUTFITS_ADULT = ("uniform_engineering", "uniform_medical", "uniform_security", "uniform_command", "casual_a",
                 "casual_b", "swimwear")
OUTFITS_CHILD = ("school", "casual_a", "casual_b", "swimwear")


def lod2_tint(entry, outfit, L, mode, slot):
    if mode == 1:
        acc = None if isinstance(entry, str) else entry.get("accent_rgb")
        return tuple(acc) if acc else PR.DEPT_STRIPE.get(outfit, PR.DEPT)
    if mode == 2:
        return PR.SKIN_TONES[L["tone"]]
    if mode == 3:
        return PR.HAIR_COLOURS[L["hair"]]
    if mode == 5:
        return L["cloth"]
    if mode == 6:
        b = None if isinstance(entry, str) else entry.get("base_rgb")
        return tuple(b) if b else (1.0, 1.0, 1.0)
    return (1.0, 1.0, 1.0)


def import_lod2(v, outfit, loc):
    M = PR.manifest()["variants"][v]
    entry = M["outfits"].get(outfit, "Outfit_" + outfit)
    L = PR.LOOK[v]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(N.MODEL_DIR, M["lod2"]["file"]))
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    keep = M["lod2"]["meshes"][outfit]
    mesh = None
    for o in new:
        if o.type == "MESH":
            if o.name.split(".")[0] != keep:
                bpy.data.objects.remove(o)
            else:
                mesh = o
    me = mesh.data
    col = me.color_attributes[0]
    for d in col.data:
        r, g, b, a = d.color
        code = int(round(a * 255.0))
        t = lod2_tint(entry, outfit, L, code // 16, code % 16)
        d.color = (r * t[0], g * t[1], b * t[2], 1.0)
    mat = bpy.data.materials.new("lod2_view")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    ca = nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = col.name
    nt.links.new(ca.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    me.materials.clear()
    me.materials.append(mat)
    ad = rig.animation_data or rig.animation_data_create()
    rig.location = loc
    return rig, mesh


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    M = PR.manifest()["variants"]
    bodies = argv[argv.index("--bodies") + 1].split(",") if "--bodies" in argv else list(M)
    out = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(PR.ART, "people_lod2.png")
    PR.tmpdir()
    rows = []
    for v in bodies:
        row = []
        outs = OUTFITS_CHILD if M[v]["child"] else OUTFITS_ADULT
        for o in outs:
            if o not in M[v]["lod2"]["meshes"]:
                continue
            PR.studio(150, 130, ground=(0.36, 0.36, 0.36))
            rig2, mesh2 = import_lod2(v, o, (0.0, 0.45, 0.0))     # LOD2 on the right
            rig0, _ = PR.import_person(v, o, loc=(0.0, -0.45, 0.0))
            PR.pose(rig0, "walk", 6)
            NR.set_clip(rig2, "walk", 6)
            tri = M[v]["lod2"]["triangles"][o]
            for view, az, el in (("top", 0.0, 89.0), ("high", 35.0, 55.0)):
                NR.clear_cameras()
                NR.camera((0.0, 0.0, 0.8), az, el, 30.0, ortho=2.6)
                p = NR.render(os.path.join(PR.TMP, "lod2_%s_%s_%s.png" % (v, o, view)))
                row.append(("%s %s %s %d" % (v, o.replace("uniform_", "u_")[:9], view, tri), p))
        rows.append(row)
    NR.compose(rows, out, title="LOD0 (left) / LOD2 (right), walk f6, top and high 3/4 view; label: LOD2 triangles")
    print("wrote", out)


main()
