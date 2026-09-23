"""
Frontier Habitat - import test for the exported files (Blender 5.2).

It imports every assets/models/<id>.glb into an EMPTY scene and checks what the game will see:
  * the top-level object names are exactly the ones in the model table
  * there are only mesh objects (no camera, light, empty, armature) and no animation
  * every material name is one of the fixed names (or `Accent`), and `Accent` has the category colour
  * rotation and scale are applied (identity); location is zero except for the joint/hub objects
  * nothing is below the allowed depth, and the geometry fits the footprint radius

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/verify_exports.py -- [--only id1,id2]
Exit code 1 when a check fails.
"""
import bpy
import os
import sys
import math
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_assets as BA   # noqa: E402

JOINT_OBJECTS = {"Rotor", "ArmL", "ArmR", "LegL", "LegR"}     # these keep their origin at the joint / hub


def linear_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def material_hex(mat):
    bsdf = next((n for n in mat.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    if bsdf is None:
        return None
    rgb = bsdf.inputs["Base Color"].default_value[:3]
    return "#" + "".join("%02x" % max(0, min(255, round(linear_to_srgb(c) * 255))) for c in rgb)


def verify(spec):
    problems = []
    path = os.path.join(BA.OUT_DIR, spec["id"] + ".glb")
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return ["file missing or empty"], {}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    objs = list(bpy.data.objects)
    top = sorted(o.name for o in objs if o.parent is None)
    if top != sorted(spec["objects"]):
        problems.append("top-level objects %s, expected %s" % (top, sorted(spec["objects"])))
    for o in objs:
        if o.type != "MESH":
            problems.append("non-mesh object %s (%s)" % (o.name, o.type))
        if o.parent is not None:
            problems.append("%s has a parent" % o.name)
        if any(abs(a) > 1e-5 for a in o.rotation_euler) or any(abs(s - 1.0) > 1e-5 for s in o.scale):
            problems.append("%s: rotation or scale is not applied" % o.name)
        if o.name not in JOINT_OBJECTS and o.location.length > 1e-5:
            problems.append("%s: origin is not at (0,0,0)" % o.name)
    if bpy.data.actions:
        problems.append("file has animation")
    mats = sorted(m.name for m in bpy.data.materials if m.users)
    for name in mats:
        if name != "Accent" and name not in BA.MATERIALS:
            problems.append("unknown material name " + name)
        elif name != "Accent":
            want = BA.MATERIALS[name]["color"].lower()
            got = material_hex(bpy.data.materials[name])
            if got != want:
                problems.append("%s colour %s, expected %s" % (name, got, want))
    if "Accent" in mats:
        got = material_hex(bpy.data.materials["Accent"])
        if got != (spec["accent_hex"] or "").lower():
            problems.append("Accent colour %s, expected %s" % (got, spec["accent_hex"]))
    zmin, rmax = 1e9, 0.0
    free = set(spec.get("free_objects", []))
    for o in objs:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            zmin = min(zmin, w.z)
            if o.name not in free:
                rmax = max(rmax, math.hypot(w.x, w.y))
    if zmin < spec["zmin"] - 1e-3:
        problems.append("zmin %.3f is below %.2f" % (zmin, spec["zmin"]))
    if spec["footprint"] and rmax > spec["footprint"] + spec.get("overhang", 0.0) + 1e-3:
        problems.append("radius %.3f exceeds footprint %.2f (+%.1f)" % (rmax, spec["footprint"], spec.get("overhang", 0.0)))
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == "MESH")
    return problems, dict(top=top, mats=mats, tris=tris, zmin=zmin, rmax=rmax)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
    failed = 0
    for spec in BA.MODELS:
        if only and spec["id"] not in only:
            continue
        problems, info = verify(spec)
        status = "OK  " if not problems else "FAIL"
        print("%s %-16s objects=%s tris=%s" % (status, spec["id"], info.get("top"), info.get("tris")))
        print("     materials=%s" % (info.get("mats"),))
        for p in problems:
            print("     !! " + p)
        failed += 1 if problems else 0
    print("verify_exports: %d model(s) failed" % failed)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
