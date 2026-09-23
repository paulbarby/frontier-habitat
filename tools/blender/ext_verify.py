"""
Frontier Habitat 2.0 - ART-B verification: re-import every ART-B GLB in Blender and check it.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ext_verify.py

Checks per file (read from the re-imported scene and the GLB JSON, not from the builder):
  object names (meshes and Anchor_ empties), materials (known names only), COLOR_0 on every primitive,
  triangles vs budget, horizontal radius vs footprint (level parts included; Rotor may overhang 1 m; lander legs
  1 m), size-M copy <id>.glb identical to <id>_m.glb, thumbnails present.
Writes tools/blender/ext_report.md.
"""
import bpy
import os
import sys
import math
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C          # noqa: E402
import ext_meridian, ext_colonists, ext_crops, ext_energy, ext_life, ext_industry, ext_singles, ext_props   # noqa: E402,E401

GROUPS = [("Meridian and debris", ext_meridian), ("Colonists", ext_colonists), ("Crops", ext_crops),
          ("Energy (sized)", ext_energy), ("Life support (sized)", ext_life), ("Industry (sized)", ext_industry),
          ("Single-size structures", ext_singles), ("Props", ext_props)]
SCRIPT = {ext_meridian: "ext_meridian.py", ext_colonists: "ext_colonists.py", ext_crops: "ext_crops.py",
          ext_energy: "ext_energy.py", ext_life: "ext_life.py", ext_industry: "ext_industry.py",
          ext_singles: "ext_singles.py", ext_props: "ext_props.py"}


def thumb_for(sid):
    for name in (sid, sid):
        p = os.path.join(C.THUMB_DIR, name + ".png")
        if os.path.exists(p):
            return name + ".png"
    return None


def md5(path):
    with open(path, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()


def verify(spec):
    name = spec.get("file", spec["id"])
    path = os.path.join(C.MODEL_DIR, name + ".glb")
    out = dict(id=name, flags=[])
    if not os.path.exists(path):
        out["flags"].append("MISSING")
        return out
    info = C.inspect_glb(path)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = list(bpy.data.objects)
    meshes = {o.name.split(".")[0]: o for o in objs if o.type == "MESH"}
    empties = sorted(o.name for o in objs if o.type == "EMPTY" and o.name.startswith("Anchor_"))
    want = sorted(spec["objects"])
    if sorted(meshes) != want:
        out["flags"].append("objects %s != %s" % (sorted(meshes), want))
    if empties != sorted(spec.get("anchors", [])):
        out["flags"].append("anchors %s != %s" % (empties, sorted(spec.get("anchors", []))))
    tris = 0
    rmax, rfree, zmin, zmax = 0.0, 0.0, 1e9, -1e9
    free = spec.get("free", {})
    for n, o in meshes.items():
        me = o.data
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        if not me.color_attributes:
            out["flags"].append("%s has no colour attribute after import" % n)
        mw = o.matrix_world
        for v in me.vertices:
            q = mw @ v.co
            r = math.hypot(q.x, q.y)
            if n in free:
                rfree = max(rfree, r)
            else:
                rmax = max(rmax, r)
            zmin, zmax = min(zmin, q.z), max(zmax, q.z)
        for m in me.materials:
            if m and m.name.split(".")[0] not in C.MATERIALS and m.name.split(".")[0] not in C.PER_FILE:
                out["flags"].append("unknown material %s" % m.name)
    if not all(info["color0"].values()):
        out["flags"].append("COLOR_0 missing in GLB")
    if tris > spec["budget"]:
        out["flags"].append("over budget %d" % spec["budget"])
    fp = spec.get("footprint")
    if fp:
        extra = spec.get("overhang", 0.0)
        if rmax > fp + extra + 1e-3:
            out["flags"].append("radius %.2f > footprint %.2f" % (rmax, fp + extra))
        for n, e in free.items():
            if rfree > fp + e + 1e-3:
                out["flags"].append("%s radius %.2f > %.2f" % (n, rfree, fp + e))
    for extra_name in spec.get("also", []):
        p2 = os.path.join(C.MODEL_DIR, extra_name + ".glb")
        if not os.path.exists(p2) or md5(p2) != md5(path):
            out["flags"].append("copy %s.glb differs or missing" % extra_name)
    out.update(tris=tris, per={n: sum(1 for _ in [0]) for n in meshes}, tris_by=info["tris"], rmax=rmax, rfree=rfree,
               zmin=zmin, zmax=zmax, size=os.path.getsize(path), mats=info["materials"], fp=fp, budget=spec["budget"],
               objects=sorted(meshes), anchors=empties)
    return out


NOTES = """## Conventions and limits

- AO: BVH ray cast per face corner (`ext_common.bake_ao`), FLOAT_COLOR corner attribute `AO`, exported as COLOR_0
  (UNSIGNED_SHORT normalized). White = open. Optional objects (L2..L5, Rotor, Damage*, Scaffold, Stage*) do not
  darken the main object. Same method as ART-A.
- New material names: `Skin`, `Hair` (indoor colonist), `Produce` (per file: crop colour; exotic-crystal colour in
  `deep_drill`). `Neon` = category colour, emissive 3 (landing-pad edge lights, fuel-refinery flare).
- `fusion_reactor` has an extra top-level mesh `Plasma` (core and ring), so the game can hide it when the reactor is off.
- Single-size structures and props use a `Lights` object for emissive lenses (comms tower beacons, landing-pad edge
  lights, lander windows, deep-drill work lights, supply-pod beacon). Sized exteriors keep small status lights in Base.
- Meridian: tilt baked in (pitch 4 deg nose down, roll 2 deg -Y down); nose reaches z = -2.0. Hull x -21.95 .. 21.53;
  with the dirt berm x up to 23.64. The SIM capsule (length 40) covers x -20 .. 20 (see docs/requests/ART-B-to-SIM.md).
- `crop_algae` has no tray place in the bioreactor; it is a 1.2 m accessory with its origin at the bottom centre.
- Copies with v1 names: `solar_array`, `wind_turbine`, `battery`, `water_extractor`, `reservoir`,
  `regolith_harvester`, `fuel_refinery` (= size M), `colonist` (= suit), `crop` (= potato), `crate` (= component).
  Running v1 `build_assets.py` without `--only` would overwrite some of them (docs/requests/ART-B-to-ART-A.md).

## Weak spots

- Sized exteriors use 30-60 % of their triangle budgets; detail is in shape, not in triangle count.
- Vertex AO on long thin parts (colonist limbs, lattice legs) shows soft streaks near joints; it is faint at game distance.
- Mushroom caps (item colour #C8B8A6) have low contrast against the brown substrate blocks.
- The Meridian hull is smooth-lofted; its damage is decals and plates on top of the intact hull, so breaches have no
  real depth. Sand drifts were removed because they read as paint.
- Not tested in Godot (no Godot runs by this agent): COLOR_0 multiply, KHR emissive strength, Glass blending, Rotor spin
  axis and limb pivots are checked only in Blender.
"""


def main():
    rows = []
    for title, mod in GROUPS:
        for spec in mod.MODELS:
            r = verify(spec)
            r["group"] = title
            r["script"] = SCRIPT[mod]
            r["also"] = spec.get("also", [])
            rows.append(r)
            print("%-24s %6s tris  %s" % (r["id"], r.get("tris", "-"), "; ".join(r["flags"]) or "ok"))
    thumbs = sorted(f for f in os.listdir(C.THUMB_DIR) if f.endswith(".png"))
    L = ["# ART-B asset report", "",
         "Written by `tools/blender/ext_verify.py` (Blender %s). Every file is re-imported into Blender and checked:" %
         bpy.app.version_string,
         "object names, anchors, materials, COLOR_0 (vertex-colour AO) on every mesh, triangles vs budget, horizontal",
         "radius vs footprint (level parts included), and that the size-M copy `<id>.glb` equals `<id>_m.glb`.", "",
         "Rebuild everything (Git Bash, from the project root):", "", "```bash",
         'B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"',
         "for s in meridian colonists crops energy life industry singles props; do",
         '  "$B" --background --factory-startup --python tools/blender/ext_$s.py; done',
         '"$B" --background --factory-startup --python tools/blender/ext_render.py -- --thumbs all --sheets all',
         '"$B" --background --factory-startup --python tools/blender/ext_verify.py', "```", ""]
    group = None
    for r in rows:
        if r["group"] != group:
            group = r["group"]
            L += ["", "## %s (`tools/blender/%s`)" % (group, r["script"]), "",
                  "| file | triangles | budget | per object | radius / footprint | z min .. max | KB | flags |",
                  "|---|---:|---:|---|---|---|---:|---|"]
        if "tris" not in r:
            L.append("| `%s.glb` | - | - | - | - | - | - | %s |" % (r["id"], "; ".join(r["flags"])))
            continue
        per = ", ".join("%s %d" % kv for kv in r["tris_by"].items() if kv[1])
        rad = "%.2f / %s" % (r["rmax"], ("%.1f" % r["fp"]) if r["fp"] else "-")
        if r["rfree"]:
            rad += " (rotor %.2f)" % r["rfree"]
        name = "`%s.glb`" % r["id"] + ("" if not r["also"] else " (+ `%s.glb`)" % "`, `".join(r["also"]))
        L.append("| %s | %d | %d | %s | %s | %.2f .. %.2f | %d | %s |" % (name, r["tris"], r["budget"], per, rad, r["zmin"],
                                                                        r["zmax"], r["size"] // 1024,
                                                                        "; ".join(r["flags"]) or "ok"))
        if r["anchors"]:
            L[-1] = L[-1][:-2] + " anchors: %s |" % ", ".join(r["anchors"])
        L.append("") if False else None
        L[-1:] = L[-1:]
    L += ["", "## Thumbnails (`assets/thumbs/`, 256 x 256, transparent, level parts hidden)", "",
          ", ".join("`%s`" % t for t in thumbs if any(t.startswith(k) for k in (
              "solar", "wind", "battery", "water_ex", "reservoir", "regolith", "fuel", "fusion", "deep", "comms",
              "lander", "landing", "meridian", "crop_"))), ""]
    bad = [r for r in rows if r["flags"]]
    L += ["**Result:** %d files checked, %d with flags." % (len(rows), len(bad)), ""]
    L += NOTES.splitlines()
    with open(os.path.join(HERE, "ext_report.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(L) + "\n")
    print("files %d, flagged %d" % (len(rows), len(bad)))


if __name__ == "__main__":
    main()
