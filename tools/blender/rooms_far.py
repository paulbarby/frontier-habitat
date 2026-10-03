"""
Frontier Habitat 5.0 - ART-HAB: far meshes for the room files (coordinator / RENDER 2026-10-03: the all-roofs-off view
spends about 10 ms on buildings, 3.2 M triangles, 821 draw calls).

Run from the project root, after rooms_build.py:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/rooms_far.py -- [--only habitat_m,lounge] [--report path]

For every room file assets/models/<id>.glb it writes assets/models/<id>_far.glb: the same building with few objects
and few materials, for distances beyond about 80 m (GROUPS: every group by default).  The objects carry the GAME GROUP names, so RENDER's group rules
work unchanged on the far template (roof on / off, cutaway, upgrade levels):
    Base      Base, Wall_* (no doorway mask at that distance), Decal_<seg>_Base/Lights/Wall*, Porch, the airlock's
              static door frames (OuterFrame, *FrameCap), ChamberLight
    Interior  Interior, Tall_* (no doorway hiding at that distance)
    Roof      Roof, Upper_* (WallsUp), Decal_<seg>_Roof, RoofChamber, PorchTop, OuterFrameTop   (hidden in the cutaway)
    L2 .. L5  L<n>, Decal_<seg>_L<n>                                                            (by upgrade level)
Left out (drawn from the near model, or not needed at 80 m): RoofCeil (ceiling, near the camera only), PorchTop_Part
(partition tops), NameSign (the game turns it), door leaves, Status, Beacon, PressureLight_*, and every anchor.
The multi-storey apartment block has no far file (its floor groups keep the near model).

Materials per object: "Palette" (every opaque face: its material colour - the category accent for Accent - is
multiplied into the vertex colour with the baked AO), one glow material (the most used emissive material; the
others fold into it), and "Glass" where the roof has glass (wall windows and vitrines become opaque Palette).
Triangles: faces smaller than MIN_AREA (Base, Interior) or MIN_AREA_SHELL (Roof, L<n>) go: text, bolts, glyph covers,
sub-pixel at 80 m; so do faces that look down (normal z < DOWN_Z: undersides, the inside of the roof), which the far
camera (outside, above) never sees.  No collapse decimate (it smeared the corner colours into dark wedges; RATIO 1.0).
"""
import bpy
import bmesh
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import build_assets as BA          # noqa: E402
import rooms_kit as K              # noqa: E402

MIN_AREA = 0.0200                  # m2 (14 x 14 cm): Base, Interior (the cutaway at 80 m)
MIN_AREA_SHELL = 0.0050            # m2 (7 x 7 cm): Roof, L2..L5 (the badge, the roof silhouette)
DOWN_Z = -0.5                      # faces whose normal points this far down go
RATIO = 1.0                        # collapse decimation smears the corner colours (tested 0.3 / 0.45): off
MAX_GLOW = 1
SKIP_FILES = ("apartment_block",)
# 2026-10-03: every group (roof-off and roof-on views; 28.3 MB of pck, measured).  "--groups Base,Interior" gives
# the roof-off set only (18.9 MB).
GROUPS = ("Base", "Interior", "Roof", "L2", "L3", "L4", "L5")   # coordinator 2026-10-03: all groups
ALL_GROUPS = ("Base", "Interior", "Roof", "L2", "L3", "L4", "L5")
REPORT = os.path.join(HERE, "far_report.json")


def far_group(n):
    if len(n) > 3 and n[0] == "F" and n[1].isdigit() and n[2] == "_":
        return None
    if n.startswith(("RoofCeil", "CeilTop", "PorchTop_Part", "PartTop", "NameSign", "Beacon", "PressureLight")):
        return None
    if n.startswith(("RoofChamber", "PorchTop", "OuterFrameTop")):
        return "Roof"
    if n.startswith(("OuterFrame", "InnerFrameCap", "OuterFrameCap", "ChamberLight", "Porch")):
        return "Base"
    if n.endswith(("Status",)) or "DoorL" in n or "DoorR" in n or n.startswith(("InnerLights", "OuterLights")):
        return None
    g = K.game_group(n)
    if g in ("Base", "Walls", "WallsIn", "DecalB", "Lights"):
        return "Base"
    if g in ("Interior", "Tall"):
        return "Interior"
    if g in ("Roof", "WallsUp", "DecalR"):
        return "Roof"
    if len(g) == 2 and g[0] == "L":
        return g
    if g.startswith("DecalL"):
        return "L" + g[6:]
    return None


def _spec(mset, nm):
    return K._spec_of(mset, nm)


def _kind(mset, nm):
    sp = _spec(mset, nm)
    if nm == "Glass" or sp.get("alpha", 1.0) < 1.0:
        return "glass"
    if sp.get("emit"):
        return "glow"
    return "opaque"


def convert(o, mset, glow_keep, glass=True):
    """Corner colours *= material colour on opaque faces; material slots -> Palette / glow / Glass."""
    me = o.data
    names = [m.name.split(".")[0] if m else "Palette" for m in me.materials] or ["Palette"]
    attr = me.color_attributes.active_color or (me.color_attributes[0] if me.color_attributes else None)
    if attr is None:
        attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for d in attr.data:
            d.color = (1.0, 1.0, 1.0, 1.0)
    point = attr.domain == "POINT"
    cols = [0.0] * (len(attr.data) * 4)
    attr.data.foreach_get("color", cols)
    if point:
        # corner colours from the point colours (the palette faces need their own colour)
        pc = cols
        cols = [0.0] * (len(me.loops) * 4)
        for li, lp in enumerate(me.loops):
            cols[li * 4:li * 4 + 4] = pc[lp.vertex_index * 4:lp.vertex_index * 4 + 4]
    targets = {}
    for nm in set(names):
        k = _kind(mset, nm)
        if k == "glass" and glass:
            targets[nm] = "Glass"
        elif k == "glass":
            targets[nm] = "Palette"            # wall windows and vitrines: opaque, tinted, at 80 m
        elif k == "glow":
            targets[nm] = nm if nm in glow_keep else nearest_glow(mset, nm, glow_keep)
        else:
            targets[nm] = "Palette"
    for p in me.polygons:
        src = names[min(p.material_index, len(names) - 1)]
        if targets[src] == "Palette" and src not in ("Palette", "PaletteMetal"):
            sp_ = _spec(mset, src)
            r, g, b = BA.hex_to_linear(sp_.get("emit", sp_.get("color", "#ffffff")) if sp_.get("emit")
                                       else sp_.get("color", "#ffffff"))
            for li in p.loop_indices:
                cols[li * 4] *= r
                cols[li * 4 + 1] *= g
                cols[li * 4 + 2] *= b
    # one corner attribute of the same name on every object, so the join keeps every object's colours
    for a_ in list(me.color_attributes):
        me.color_attributes.remove(a_)
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    attr.data.foreach_set("color", cols)
    me.color_attributes.active_color = attr
    me.color_attributes.active_color_name = "Col"
    me.color_attributes.default_color_name = "Col"     # the exporter writes the render colour (COLOR_0)
    order = sorted(set(targets.values()))
    orig = [min(p.material_index, len(names) - 1) for p in me.polygons]
    me.materials.clear()
    slot = {}
    for nm in order:
        me.materials.append(mset.get(nm) if nm != "Palette" else mset.get("Palette"))
        slot[nm] = len(me.materials) - 1
    for p, oi in zip(me.polygons, orig):
        p.material_index = slot[targets[names[oi]]]


def nearest_glow(mset, nm, keep):
    if not keep:
        return "Palette"
    c = BA.hex_to_linear(_spec(mset, nm).get("emit", _spec(mset, nm).get("color", "#ffffff")))

    def d(q):
        e = BA.hex_to_linear(_spec(mset, q).get("emit", _spec(mset, q).get("color", "#ffffff")))
        return sum((a - b) ** 2 for a, b in zip(c, e))
    return min(keep, key=d)


def reduce(o, min_area=MIN_AREA):
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    # small faces, and faces that look down (undersides, the roof's inside): the far camera is outside and above
    # (a sliver - a badge wedge, a stripe - stays: only faces that are small in both directions go)
    def tiny(f):
        if f.calc_area() >= min_area:
            return False
        return max(e.calc_length() for e in f.edges) < 2.0 * min_area ** 0.5
    small = [f for f in bm.faces if f.normal.z < DOWN_Z or tiny(f)]
    bmesh.ops.delete(bm, geom=small, context="FACES")
    bm.to_mesh(me)
    bm.free()
    if RATIO < 1.0 and len(me.polygons) > 200:
        mod = o.modifiers.new("far", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = RATIO
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)


def tris_of(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def build(fid, tid, cat, out_dir=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = os.path.join(K.MODEL_DIR, fid + ".glb")
    bpy.ops.import_scene.gltf(filepath=src)
    mset = K.MatSet(K.ACCENTS[cat])
    groups = {}
    t0 = 0
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        g = far_group(o.name.split(".")[0])
        t0 += tris_of(o)
        if g is None or g not in GROUPS:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        groups.setdefault(g, []).append(o)
    out = {}
    for g, objs in groups.items():
        # the glow materials this group keeps: the most used emissive ones
        use = {}
        for o in objs:
            names = [m.name.split(".")[0] if m else "" for m in o.data.materials]
            for p in o.data.polygons:
                nm = names[p.material_index] if names else ""
                if nm and _kind(mset, nm) == "glow":
                    use[nm] = use.get(nm, 0) + 1
        keep = sorted(use, key=lambda k: -use[k])[:MAX_GLOW]
        for o in objs:
            convert(o, mset, keep, glass=(g == "Roof"))
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        j = bpy.context.view_layer.objects.active
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        j.name = g
        j.data.name = g
        j.data.color_attributes.active_color_name = "Col"
        j.data.color_attributes.default_color_name = "Col"
        reduce(j, MIN_AREA if g in ("Base", "Interior") else MIN_AREA_SHELL)
        out[g] = dict(tris=tris_of(j), mats=sorted(m.name.split(".")[0] for m in j.data.materials))
    path = os.path.join(out_dir or K.MODEL_DIR, fid + "_far.glb")
    K.export_glb_atomic(path)
    return dict(id=fid, src_tris=t0, far_tris=sum(v["tris"] for v in out.values()),
                draws=sum(len(v["mats"]) for v in out.values()), groups=out, file_size=os.path.getsize(path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
    rep_path = argv[argv.index("--report") + 1] if "--report" in argv else REPORT
    out_dir = argv[argv.index("--out") + 1] if "--out" in argv else None
    global GROUPS
    if "--groups" in argv:
        v = argv[argv.index("--groups") + 1]
        GROUPS = ALL_GROUPS if v == "all" else tuple(v.split(","))
    rep = json.load(open(os.path.join(HERE, "build_report.json"), encoding="utf-8"))
    bl = K.load_buildings()
    rows = []
    for m in rep["models"]:
        tid = m["type"]
        if tid == "corridor" or tid in SKIP_FILES:
            continue
        if only and m["id"] not in only and tid not in only:
            continue
        cat = bl.get(tid, {}).get("category", "logistics")
        if cat not in K.ACCENTS:
            cat = "logistics"
        t = time.time()
        r = build(m["id"], tid, cat, out_dir)
        rows.append(r)
        print("FAR %-30s tris %6d -> %6d  draws %2d  %6.1f KB  %.1fs  %s" % (
            r["id"], r["src_tris"], r["far_tris"], r["draws"], r["file_size"] / 1024.0, time.time() - t,
            {g: v["mats"] for g, v in r["groups"].items()}))
        sys.stdout.flush()
    json.dump(dict(min_area=MIN_AREA, min_area_shell=MIN_AREA_SHELL, ratio=RATIO, rows=rows), open(rep_path, "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main()
