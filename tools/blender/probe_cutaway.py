"""List every object of the given room GLBs that the game's cutaway still shows (presentation/world_view.gd
_apply_roof) and that rises above WALL_TOP 1.40 m.

Run: blender --background --factory-startup --python tools/blender/probe_cutaway.py -- airlock_m,airlock_r28
Prints: file, object, game group, top z.  Nothing printed per file = the cutaway is clean."""
import bpy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rooms_kit as K        # noqa: E402

MODELS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "models")
WALL_TOP = 1.40


def hidden_in_cutaway(g):
    # hidden in the cutaway, or allowed above the cut (Interior, Tall: RENDER render_cut_check.gd)
    return (g == "Roof" or (len(g) == 2 and g[0] == "L") or g.endswith("Top") or g.endswith("Status")
            or g.startswith("PressureLight") or g in ("Beacon", "DecalR", "WallsUp", "Interior", "Tall")
            or g.startswith("DecalL"))


def probe(name, tol=0.006):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
    bad = []
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        nm = o.name.split(".")[0]
        g = K.game_group(nm)
        if hidden_in_cutaway(g):
            continue
        zt = max((o.matrix_world @ v.co).z for v in o.data.vertices)
        if zt > WALL_TOP + tol:
            bad.append((nm, g, round(zt, 3)))
    return bad


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv[0].split(",") if argv else ["airlock_m", "airlock_l", "airlock_r28"]
    if names == ["ALL"]:
        import json
        rep = json.load(open(os.path.join(HERE, "build_report.json"), encoding="utf-8"))
        names = [m["id"] for m in rep["models"] if m["id"] != "corridor"]
    bad_files = 0
    for n in names:
        bad = [b_ for b_ in probe(n) if b_[0] not in ("Porch",)]
        bad_files += 1 if bad else 0
        print("CUTAWAY %s: %d objects above %.2f" % (n, len(bad), WALL_TOP))
        for b in sorted(bad, key=lambda x: -x[2]):
            print("   ", b)
    print("CUTAWAY TOTAL: %d of %d files with drawn parts above the cut" % (bad_files, len(names)))


main()
