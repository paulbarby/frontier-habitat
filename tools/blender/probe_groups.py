"""Count the materials per game group (presentation/models.gd group_of) in every room GLB of build_report.json.

Run: blender --background --factory-startup --python tools/blender/probe_groups.py -- [--out file.json]
Prints, per group, the largest count and the files over the limit.  The draw-call cost of a room type is one call
per material of each merged group."""
import bpy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(ROOT, "assets", "models")
GROUPS = ["Interior", "Roof", "Rotor", "Lights", "Scaffold", "EngineGlow", "Plasma", "Damage1", "Damage2", "Damage3",
          "Stage1", "Stage2", "Stage3", "Body", "ArmL", "ArmR", "LegL", "LegR", "L2", "L3", "L4", "L5", "Hull",
          "DoorLTop", "DoorRTop", "DoorL", "DoorR", "FrameTop", "Sign", "Turret",
          "InnerDoorLTop", "InnerDoorRTop", "InnerDoorL", "InnerDoorR", "InnerStatus", "InnerLights",
          "OuterDoorLTop", "OuterDoorRTop", "OuterDoorL", "OuterDoorR", "OuterFrameTop", "OuterFrame", "OuterStatus",
          "OuterLights", "ChamberLight", "PressurePlateTop", "PressureLight_0", "PressureLight_1", "PressureLight_2",
          "Beacon", "Status", "NameSign", "Base"]
SHELL_MATS = ("Hull", "HullDark", "Accent", "Frame", "Trim", "Window", "Glass", "Metal", "Rubber")


def group_of(n):
    if n.startswith("Wall_") and n[5:7].isdigit():
        return "Walls"
    if n.startswith("Upper_") and n[6:8].isdigit():
        return "Walls"
    if n.startswith("Decal_") and n[6:8].isdigit():
        src = n[9:]
        if src.startswith("Roof"):
            return "DecalR"
        if len(src) >= 2 and src[0] == "L" and src[1].isdigit():
            return "DecalL" + src[1]
        return "DecalB"
    if n.startswith("Tall_") and n[5:].isdigit():
        return "Tall"
    for g in GROUPS:
        if n.startswith(g):
            if g in ("L2", "L3", "L4", "L5") and len(n) > 2 and n[2].isdigit():
                continue
            return g
    return "Base"


def count(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    mats = {}
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        g = group_of(o.name.split(".")[0])
        for m in o.data.materials:
            nm = m.name.split(".")[0] if m else ""
            if g == "Walls":
                g2 = "Walls" if nm in SHELL_MATS else "WallsIn"
            else:
                g2 = g
            mats.setdefault(g2, set()).add(nm)
    return {g: sorted(v) for g, v in mats.items()}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[argv.index("--out") + 1] if "--out" in argv else None
    rep = json.load(open(os.path.join(HERE, "build_report.json"), encoding="utf-8"))
    ids = [m["id"] for m in rep["models"]]
    if "--links" in argv:
        lr = json.load(open(os.path.join(HERE, "interior_links_report.json"), encoding="utf-8"))
        ids = [m["id"] for m in lr["models"]]
    res = {}
    for i in ids:
        p = os.path.join(MODELS, i + ".glb")
        if os.path.exists(p):
            res[i] = count(p)
    groups = sorted({g for v in res.values() for g in v}) if "--links" in argv else ("Base", "Walls", "Roof", "DecalB", "DecalR")
    for g in groups:
        cs = sorted(((len(v.get(g, [])), k) for k, v in res.items()), reverse=True)
        tot = sum(c for c, _ in cs)
        print("GROUP %-7s max %2d (%s)  sum %4d  over 6: %d" % (g, cs[0][0], cs[0][1], tot, sum(1 for c, _ in cs if c > 6)))
    if out:
        json.dump(res, open(out, "w", encoding="utf-8"), indent=1)


main()
