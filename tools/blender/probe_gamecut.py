"""Render a room the way the GAME draws its roof cutaway (presentation/world_view.gd _apply_roof): Roof, L2..L5 and
groups ending in Top / Status, PressureLight_*, Beacon, DecalR/DecalL hidden; everything else shown, including the
Walls group (Wall_* AND Upper_*, presentation/models.gd group_of).  Back faces are culled, as Godot does.

Run: blender --background --factory-startup --python tools/blender/probe_gamecut.py -- storehouse_m [out.png] [az]"""
import bpy
import os
import sys
from math import cos, sin, radians
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rooms_kit as K           # noqa: E402
import rooms_render as RR       # noqa: E402
import interior_render as IR    # noqa: E402


def hidden_in_cutaway(g):
    return (g == "Roof" or (len(g) == 2 and g[0] == "L") or g.endswith(("Top", "Status"))
            or g.startswith("PressureLight") or g in ("Beacon", "DecalR") or g.startswith("DecalL"))


UPPER_HIDDEN = False


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name = argv[0] if argv else "storehouse_m"
    out = argv[1] if len(argv) > 1 else os.path.join(IR.OUT_DIR, name + "_gamecut.png")
    az = float(argv[2]) if len(argv) > 2 and argv[2] != "-" else -60.0
    global UPPER_HIDDEN
    UPPER_HIDDEN = "--upper-hidden" in argv       # RENDER U1: Upper_* hide with the roof
    IR.setup(1600, 1060, night=False, samples=48)
    objs = IR.import_at(name, hide=())
    for o in objs:
        nm = o.name.split(".")[0]
        if o.type == "MESH" and (hidden_in_cutaway(K.game_group(nm)) or (UPPER_HIDDEN and nm.startswith("Upper_"))):
            o.hide_render = True
    for m in bpy.data.materials:
        m.use_backface_culling = True
    RR.ensure_ao()
    R = max(v for o in objs if o.type == "MESH" for v in (abs(c) for b in o.bound_box for c in b[:2]))
    pts = [Vector((x, y, z)) for x in (-R, R) for y in (-R, R) for z in (0.0, 2.8)]
    RR.place_camera(pts, azimuth=az, elevation=48.0, margin=1.0, aspect=1600 / 1060, focal=50.0)
    RR.render_to(out)
    print("  wrote", out)


main()
