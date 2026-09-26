"""
Frontier Habitat 2.0 - ART-A build driver for the ROOM buildings (Blender 5.2, --background only).

Rebuild everything (PowerShell or Git Bash, from the project root):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/rooms_build.py -- [--only habitat,greenhouse] [--sizes s,m,l,xl]
      [--no-thumbs] [--review] [--no-verify]

Writes, for each room type and size (content/buildings.json -> sizes.radius = [S, M, L, XL]):
  assets/models/<id>_<s|m|l|xl>.glb    and assets/models/<id>.glb = the M file (v1 loader fallback)
  assets/thumbs/<id>_<s|m|l|xl>.png    and assets/thumbs/<id>.png = M
Single-size types (airlock, junction, corridor): assets/models/<id>.glb, assets/thumbs/<id>.png.
Every file is exported to <name>.tmp.glb and renamed (another agent may import at any moment).
Checks: the exported file is read back (GLB JSON) AND re-imported into an empty Blender scene
(object names, materials, COLOR_0, triangles, radius vs footprint, tray positions) -> build_report.{md,json}.
--review also renders check sheets to tools/blender/previews/rooms/.
"""
import bpy
import os
import sys
import json
import math
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import rooms_kit as K        # noqa: E402

BUILDERS = {}
_MODULES = ("rooms_habitat", "rooms_agri", "rooms_life", "rooms_science", "rooms_industry", "rooms_links")
for _m in _MODULES:
    try:
        mod = __import__(_m)
        BUILDERS.update(getattr(mod, "BUILDERS", {}))
    except ModuleNotFoundError as exc:
        if exc.name != _m:
            raise

ORDER = ["habitat", "greenhouse", "kitchen", "storehouse", "oxygen_plant", "research_lab", "mine", "refinery",
         "polymer_plant", "workshop", "medical", "lounge", "airlock", "junction", "corridor",
         "glassworks", "electronics_fab", "fabricator", "fungus_farm", "algae_bioreactor", "water_recycler",
         "atmo_processor", "bio_lab", "cantina", "cold_storage", "research_assembler"]
FAMILY = {
    "habitat": "habitat", "lounge": "habitat", "cantina": "habitat", "medical": "habitat", "bio_lab": "habitat",
    "storehouse": "habitat", "cold_storage": "habitat",
    "greenhouse": "agri", "fungus_farm": "agri", "algae_bioreactor": "agri", "kitchen": "agri",
    "oxygen_plant": "life", "water_recycler": "life", "atmo_processor": "life",
    "research_lab": "science", "research_assembler": "science",
    "mine": "industry", "refinery": "industry", "polymer_plant": "industry", "workshop": "industry",
    "glassworks": "industry", "electronics_fab": "industry", "fabricator": "industry",
    "airlock": "links", "junction": "links", "corridor": "links",
}
# 3.0 (docs/V3_DESIGN.md section 7): builders with the detailed interiors and wall segments.  A v3 builder may
# raise NotImplementedError for a size it does not make yet; that size then uses the v2 builder.
V3_BUILDERS = {}
for _m in ("interior_rooms",):
    try:
        V3_BUILDERS.update(getattr(__import__(_m), "V3_BUILDERS", {}))
    except ModuleNotFoundError as exc:
        if exc.name != _m:
            raise
V3_BUDGET = (10000, 15000, 22000, 30000)
V3_MAX_MATERIALS = 14            # per object (Interior; each Wall_k); see docs/progress/ART-HAB.md
ROOM_MESHES = ["Base", "Roof", "Interior", "L2", "L3", "L4", "L5"]
ALLOWED = set(K.MATERIALS) | set(K.PER_FILE)
TRAY_TYPES = ("greenhouse", "fungus_farm")
AIRLOCK_R_OLD = 2.8                    # airlocks in old saves (RENDER: use airlock_r28.glb when R < 3.0)
AIRLOCK_RADII = {"m": 3.4, "l": 4.0}   # proposed to SIM (docs/requests/ART-HAB-to-SIM.md)
OVERHANG_PARTS = ("Porch", "PorchTop")      # 3.1: the airlock porch stands outside the footprint (the entrance itself)


def jobs(buildings, only=None, sizes=None):
    out = []
    for tid in ORDER:
        if only and tid not in only:
            continue
        if tid not in BUILDERS:
            continue
        if tid == "corridor" and "--v2" not in sys.argv:
            continue            # 3.0: tools/blender/interior_links.py builds corridor.glb (+ doorway, rib, patch)
        bdef = buildings.get(tid, {})
        radii = bdef.get("sizes", {}).get("radius")
        if radii and tid not in ("airlock", "junction", "corridor"):
            for s, key in enumerate(K.SIZE_KEYS):
                if sizes and key not in sizes:
                    continue
                out.append(dict(tid=tid, size=s, key=key, R=float(radii[s]), file="%s_%s" % (tid, key),
                                also=[tid] if s == 1 else [], bdef=bdef, single=False))
        elif tid == "airlock" and radii:
            # content has the M / L airlock (SIM, 2026-09-25): airlock_m (+ airlock.glb) and airlock_l
            for s_, key in ((1, "m"), (2, "l")):
                if sizes and key not in sizes:
                    continue
                out.append(dict(tid=tid, size=s_, key=key, R=float(radii[s_]), file="airlock_" + key,
                                also=[tid] if key == "m" else [], bdef=bdef, single=True))
            if not sizes or "m" in sizes:
                # airlocks of old saves keep R 2.8 (coordinator 2026-09-25): the new design at 2.8 m, 2 riders
                out.append(dict(tid=tid, size=1, key="r28", R=AIRLOCK_R_OLD, file="airlock_r28", also=[], bdef=bdef,
                                single=True))
        else:
            if sizes and "m" not in sizes:
                continue
            out.append(dict(tid=tid, size=1, key="", R=float(bdef.get("radius", 1.2)), file=tid, also=[], bdef=bdef,
                            single=True))
            if tid == "airlock" and not radii:
                # 3.1 (decision 2026-09-25): M and L airlocks; radii proposed to SIM until content has them
                for s_, key, R_ in ((1, "m", AIRLOCK_RADII["m"]), (2, "l", AIRLOCK_RADII["l"])):
                    out.append(dict(tid=tid, size=s_, key=key, R=R_, file="airlock_" + key, also=[], bdef=bdef,
                                    single=True))
    return out


def expected_trays(job):
    bdef = job["bdef"]
    offs = bdef.get("sizes", {}).get("tray_offsets")
    if offs:
        return [tuple(o) for o in offs[job["size"]]]
    return [tuple(o) for o in bdef.get("tray_offsets", [])]


DOOR_BLOCKED = os.path.join(K.ROOT, "docs", "requests", "ART-HAB-door_blocked.json")


# Door lanes (RENDER / coordinator 2026-09-25): every M / L / XL room keeps a 0.9 m lane from a doorway at any
# angle to the aisle ring (interior_kit.door_blocked).  These room types cannot yet; their blocked angles are listed
# in ART-HAB-door_blocked.json for SIM (docs/requests/ART-HAB-to-SIM.md).  S rooms are always listed.
LANE_LISTED = {
    "airlock": "fixed layout: chamber, pumps and bench fill the +X half",
    "greenhouse": "tray positions come from content (sizes.tray_offsets)",
    "fungus_farm": "rack rows reach the ring",
    "oxygen_plant": "electrolysis block and tank plinth reach the ring",
    "water_recycler": "tank group, UV line and pumps reach the ring",
}


# Minimum free door angle (coordinator 2026-09-25): S >= 120 deg, M and larger >= 180 deg.  Airlocks are the
# exception (only the suit-room side is free).  SIM refuses new links at the blocked angles.
AIRLOCK_STRUCTURE = {"chamberfloor", "chamber", "pump", "partition"}     # the chamber side: may block door lanes
LANE_MIN_FREE = {"s": 120.0, "m": 180.0, "l": 180.0, "xl": 180.0, "": 180.0}
DOOR_BLOCKED_CONTENT = os.path.join(K.ROOT, "content", "door_blocked.json")   # what the sim reads (authorised)


def write_door_blocked(rows):
    """docs/requests/ART-HAB-door_blocked.json: per room file, the model angles (deg, see the RENDER request P3)
    where a doorway would have less than 1.2 m of free floor in front of it (critic round 4)."""
    old, prev_changes = {}, []
    if os.path.exists(DOOR_BLOCKED):
        try:
            prev = json.load(open(DOOR_BLOCKED, encoding="utf-8"))
            old = prev.get("rooms", {})
            prev_changes = prev.get("changes", [])
        except Exception:
            old = {}
    before = {k: v.get("blocked") for k, v in old.items()}
    for r in rows:
        v = r.get("v3") or {}
        if "door_blocked" in v:
            for key in [r["id"]] + list(r.get("also") or []):      # the size-M copy (habitat.glb, airlock.glb ...)
                old[key] = dict(blocked=[list(x) for x in v["door_blocked"]], free_deg=v["door_free_deg"],
                                min_lane_m=v["door_clear_min"])
    changed = sorted(k for k, v in old.items() if before.get(k) != v.get("blocked"))
    changes = prev_changes
    if changed:
        changes = (prev_changes + [dict(at=time.strftime("%Y-%m-%d %H:%M"), rooms=changed)])[-20:]
        print("door_blocked.json CHANGED for %d files: %s  -> tell SIM (docs/requests/ART-HAB-to-SIM.md)"
              % (len(changed), ", ".join(changed)))
    doc = dict(generator="tools/blender/rooms_build.py", lane_m=0.9, changes=changes,
               rule="a doorway at a blocked angle has no 0.9 m lane from the door housing to the aisle ring",
               angles="model angle in degrees, 0 = model +X, counter-clockwise seen from above "
                      "(docs/requests/ART-HAB-to-RENDER.md P3)", rooms=old)
    for out_path in (DOOR_BLOCKED_CONTENT, DOOR_BLOCKED):       # the sim's copy and the docs copy: never apart
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, indent=1, sort_keys=True)


CUT_SHELL_GROUPS = ("Walls", "DecalB", "Base")     # shell groups the game shows in the roof cutaway


def cut_top_check(rm, objs, eps=0.006):
    """Paul 2026-09-26 (cutaway top edge): every shell piece the game shows in the roof cutaway ends flat at
    WALL_TOP with a closed top.  Checks, on the built objects:
      - no vertex of Wall_* (shell AND wall-side items), DecalB or Base objects (not the porch) above WALL_TOP + eps;
      - Upper_* pieces lie wholly at or above WALL_TOP - 0.02 (they must hide with the roof, RENDER U1);
      - no open (boundary) edge of a Wall_* object runs along the top at WALL_TOP: the top face is closed."""
    import bmesh
    out = []
    high, low_upper, open_top = [], [], []
    Rw, Ri = rm.Rw, rm.Ri
    for nm, o in objs.items():
        g = K.game_group(nm)
        vs = [v.co for v in o.data.vertices]
        if not vs:
            continue
        if nm.startswith("Upper_"):
            if min(v.z for v in vs) < K.WALL_TOP - 0.04:
                low_upper.append(nm)
            continue
        # every drawn vertex counts, wall-side items included (RENDER render_cut_check.gd: the game draws Walls and
        # WallsIn in the cutaway; only Interior and Tall may stand above the cut)
        shell = vs
        drawn = not (g == "Roof" or (len(g) == 2 and g[0] == "L") or g.endswith(("Top", "Status"))
                     or g.startswith("PressureLight") or g in ("Beacon", "DecalR", "Interior", "Tall")
                     or g.startswith("DecalL"))
        if drawn and nm not in OVERHANG_PARTS and shell and max(v.z for v in shell) > K.WALL_TOP + eps:
            high.append("%s %.2f" % (nm, max(v.z for v in shell)))
        if nm.startswith("Wall_"):
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
            n_open = 0
            for e in bm.edges:
                if not e.is_boundary:
                    continue
                a, b_ = e.verts[0].co, e.verts[1].co
                if a.z > K.WALL_TOP - 0.003 and b_.z > K.WALL_TOP - 0.003:
                    ra, rb = a.xy.length, b_.xy.length
                    rm_ = 0.5 * (ra + rb)
                    inside_wall = Ri + 0.005 < rm_ < Rw - 0.005        # buried in the wall thickness: unseen
                    if abs(ra - rb) < 0.5 * (a.xy - b_.xy).length and rm_ >= Ri - 0.01 and not inside_wall:
                        n_open += 1
            bm.free()
            if n_open:
                open_top.append("%s(%d)" % (nm, n_open))
    if high:
        out.append("cutaway: shell above %.2f m: %s" % (K.WALL_TOP, high[:6]))
    if low_upper:
        out.append("cutaway: Upper pieces below the cut: %s" % low_upper[:6])
    if open_top:
        out.append("cutaway: open wall top edges: %s" % open_top[:6])
    return out


def build_one(job):
    t0 = time.time()
    bdef = job["bdef"]
    cat = bdef.get("category", "logistics")
    rm = K.Room(job["tid"], job["size"], job["R"], cat, bdef, single=job["single"])
    built_v3 = False
    if job["tid"] in V3_BUILDERS and "--v2" not in sys.argv:
        try:
            V3_BUILDERS[job["tid"]](rm)
            built_v3 = True
        except NotImplementedError:
            rm = K.Room(job["tid"], job["size"], job["R"], cat, bdef, single=job["single"])
    if not built_v3:
        BUILDERS[job["tid"]](rm)
    path = os.path.join(K.MODEL_DIR, job["file"] + ".glb")
    also = [os.path.join(K.MODEL_DIR, a + ".glb") for a in job["also"]]
    objs, rays, secs = K.build_file(rm, path, also=also)
    flags = []
    if rm.v3:
        flags += cut_top_check(rm, objs)
    stats = {p.name: K.part_stats(p) for p in rm.parts() if p.faces}
    tris = sum(s["tris"] for s in stats.values())
    budget = (V3_BUDGET if rm.v3 else K.BUDGET)[job["size"]]
    if job["tid"] == "corridor":
        budget = 1200
    if tris > budget:
        flags.append("over budget %d > %d" % (tris, budget))
    radius = max(s["radius"] for n, s in stats.items() if n not in OVERHANG_PARTS)
    limit = job["R"] - K.MARGIN
    if job["tid"] != "corridor" and radius > limit + 1e-3:
        flags.append("radius %.3f > footprint-0.1 = %.2f" % (radius, limit))
    if job["tid"] == "airlock":
        # critic round 13: nothing the game's cutaway shows stands above WALL_TOP (world_view.gd _apply_roof hides
        # Roof, L2..L5, groups ending in Top / Status, PressureLight_*, Beacon, DecalR)
        def cut_hidden(g):
            return (g == "Roof" or (len(g) == 2 and g[0] == "L") or g.endswith(("Top", "Status"))
                    or g.startswith("PressureLight") or g in ("Beacon", "DecalR") or g.startswith("DecalL"))
        tall = sorted(n for n, s_ in stats.items() if s_["hi"][2] > K.WALL_TOP + 0.015
                      and not cut_hidden(K.game_group(n)))
        if tall:
            flags.append("cutaway: %s stand above %.2f m" % (tall, K.WALL_TOP))
    lo = [min(s["lo"][i] for s in stats.values()) for i in range(3)]
    hi = [max(s["hi"][i] for s in stats.values()) for i in range(3)]
    if job["tid"] != "corridor":
        flags += K.check_interior(rm)
    info = K.inspect_glb(path)
    want = list(ROOM_MESHES) if not job["single"] else ["Base", "Roof", "Interior"]
    # 3.1: a level part whose faces were all outer-wall decals is now only Decal_<seg>_L<n> objects
    want = [w for w in want if not (w in ("L2", "L3", "L4", "L5") and not rm.L[int(w[1])].faces)]
    if job["tid"] == "corridor":
        want = ["Base", "Roof"]
    if rm.lights.faces:
        want.append("Lights")
    want += [w.name for w in rm.walls if w.faces]
    want += [q.name for q in getattr(rm, "extra_parts", []) if q.faces]
    want += [q.name for q in getattr(rm, "decals", []) if q.faces]
    if rm.v3:
        import interior_kit as IK
        dh = getattr(rm, "door_half_v3", 0.0)
        empty = [k for k, w in enumerate(rm.walls) if not w.faces]
        bad = [k for k in empty if not (dh > 0 and min(abs(k * IK.SEG_DEG), abs(360 - (k + 1) * IK.SEG_DEG)) < dh)]
        if len(rm.walls) != IK.NSEG or bad:
            flags.append("v3: wall segments without geometry outside the door: %s" % bad)
        flags += IK.check_walls(rm)
        flags += IK.check_anchors(rm)
        flags += IK.check_furniture(rm)
        flags += IK.check_standpoints(rm)
        for oname, mats in info["mats_by"].items():
            if len(mats) > V3_MAX_MATERIALS:
                flags.append("%s has %d materials > %d" % (oname, len(mats), V3_MAX_MATERIALS))
            if (oname == "Interior" or oname.startswith("Tall_")) and len(mats) > K.MAX_SURFACES:
                flags.append("%s has %d surfaces > %d (draw-call budget)" % (oname, len(mats), K.MAX_SURFACES))
        # the game merges objects per group (presentation/models.gd): one draw call per material of each group
        by_group = {}
        for oname, mats in info["mats_by"].items():
            by_group.setdefault(K.game_group(oname), set()).update(mats)
        for g in ("Base", "Roof", "L2", "L3", "L4", "L5"):
            if len(by_group.get(g, ())) > K.MAX_SHELL_SURFACES:
                flags.append("group %s has %d surfaces > %d (shell draw-call budget): %s" %
                             (g, len(by_group[g]), K.MAX_SHELL_SURFACES, sorted(by_group[g])))
        shell_w = {m for m in by_group.get("Walls", ()) if m in K.WALL_SHELL}
        if len(shell_w) > K.MAX_SHELL_SURFACES:
            flags.append("wall shell has %d surfaces > %d: %s" % (len(shell_w), K.MAX_SHELL_SURFACES, sorted(shell_w)))
        rm.group_surfaces = {g: len(v) for g, v in by_group.items()}
        rm.group_surfaces["WallShell"] = len(shell_w)
        if len(info["materials"]) > IK.MAX_MATS_FILE:
            flags.append("file has %d materials > %d" % (len(info["materials"]), IK.MAX_MATS_FILE))
    if sorted(info["mesh_nodes"]) != sorted(want):
        flags.append("mesh objects %s != %s" % (sorted(info["mesh_nodes"]), sorted(want)))
    bad_e = [e for e in info["empties"] if not e.startswith("Anchor_")]
    if bad_e:
        flags.append("unexpected empties %s" % bad_e)
    miss = [n for n, ok in info["color0"].items() if not ok]
    if miss:
        flags.append("no COLOR_0 on %s" % miss)
    if info["child_nodes"]:
        flags.append("nodes have children")
    if info["extras"]:
        flags.append("file has %s" % info["extras"])
    unknown = [m for m in info["materials"] if m not in ALLOWED]
    if unknown:
        flags.append("unknown materials %s" % unknown)
    if "Glass" in info["alpha"] and info["alpha"]["Glass"] != "BLEND":
        flags.append("Glass alphaMode %s" % info["alpha"]["Glass"])
    glb_tris = sum(info["tris"].values())
    if glb_tris != tris:
        flags.append("GLB triangles %d != built %d" % (glb_tris, tris))
    if job["tid"] in TRAY_TYPES:
        want_t = sorted((round(x, 3), round(y, 3)) for x, y in expected_trays(job))
        got_t = sorted((round(x, 3), round(y, 3)) for x, y in rm.trays)
        if want_t != got_t:
            flags.append("trays %s != content %s" % (got_t, want_t))
    row = dict(id=job["file"], type=job["tid"], size=job["key"] or "-", footprint=job["R"], tris=tris, budget=budget,
               tris_by_object={n: s["tris"] for n, s in stats.items()}, bbox_min=[round(v, 3) for v in lo],
               bbox_max=[round(v, 3) for v in hi], max_radius=round(radius, 3), margin=round(job["R"] - radius, 3),
               anchors=[a[0] for a in rm.anchors], materials=info["materials"], file_size=os.path.getsize(path),
               color0=all(info["color0"].values()), also=job["also"], flags=flags,
               seconds=round(time.time() - t0, 1), ao_rays=rays, trays=[list(t) for t in rm.trays])
    if rm.v3:
        import interior_kit as IK
        walls_t = sum(stats[w.name]["tris"] for w in rm.walls if w.name in stats)
        row["v3"] = dict(anchor_counts=IK.anchor_counts(rm), wall_tris=walls_t,
                         interior_materials=info["mats_by"].get("Interior", []),
                         wall_materials=sorted({m for o, ms in info["mats_by"].items() if o.startswith("Wall_") for m in ms}),
                         file_materials=len(info["materials"]), info=getattr(rm, "info", {}),
                         anchors=[dict(name=a[0], pos=[round(c, 3) for c in a[1]], yaw=round(a[2] if len(a) > 2 else 0.0, 2))
                                  for a in rm.anchors])
        talls_t = sum(t for n, t in row["tris_by_object"].items() if n.startswith("Tall_"))
        row["tris_by_object"] = {n: t for n, t in row["tris_by_object"].items()
                                 if not n.startswith(("Wall_", "Tall_"))}
        row["tris_by_object"]["Wall_00..31"] = walls_t
        if talls_t:
            row["tris_by_object"]["Tall_*"] = talls_t
        row["v3"]["tall_parts"] = len([q for q in getattr(rm, "extra_parts", []) if q.faces])
        row["v3"]["surfaces"] = {k: list(v) for k, v in getattr(rm, "surfaces", {}).items()}
        row["v3"]["group_surfaces"] = getattr(rm, "group_surfaces", {})
        di = getattr(rm, "decal_info", None) or {}
        row["v3"]["decals"] = dict(decal_objects=len(di.get("decals", [])), upper_objects=len(di.get("upper", [])),
                                   upper_z=di.get("upper_z"), upper_band=di.get("upper_band"),
                                   shell=getattr(rm, "shell", None), name_sign_deg=getattr(rm, "name_sign_deg", None))
        if getattr(rm, "plan", None) is not None and rm.tid != "junction":
            spans, worst = IK.door_blocked(rm.plan)
            row["v3"]["door_blocked"] = spans
            row["v3"]["door_clear_min"] = worst
            row["v3"]["door_lane_hits"] = getattr(rm.plan, "lane_hits", {})
            row["v3"]["door_lane_ring"] = getattr(rm.plan, "lane_ring", None)
            row["v3"]["door_lane_hit_angles"] = {t: sorted(v) for t, v in getattr(rm.plan, "lane_hit_angles", {}).items()}
            need = LANE_MIN_FREE.get(job["key"], LANE_MIN_FREE["m"])
            free_ = round(360.0 - sum(b1 - b0 for b0, b1 in spans), 1)
            loose = set(getattr(rm.plan, "lane_hits", {})) - AIRLOCK_STRUCTURE
            if job["tid"] == "airlock" and loose:
                flags.append("airlock door lanes blocked by furniture %s (only the chamber may block)" % sorted(loose))
            if job["tid"] != "airlock" and free_ < need:
                flags.append("door lanes: %.0f deg free < %d (coordinator minimum for size %s); blocked by %s"
                             % (free_, need, job["key"] or "m", row["v3"]["door_lane_hits"]))
            row["v3"]["door_free_deg"] = round(360.0 - sum(b1 - b0 for b0, b1 in spans), 1)
    print("  %-24s %5d/%-5d tris  r=%.2f/%.2f  %4.1fs  %s%s" % (job["file"], tris, budget, radius, job["R"],
                                                              row["seconds"], "; ".join(flags) or "ok",
                                                              "  [v3]" if rm.v3 else ""))
    return row


# --------------------------------------------------------------------------------------
# Re-import test (what the game receives)
# --------------------------------------------------------------------------------------
def linear_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def verify_file(job):
    path = os.path.join(K.MODEL_DIR, job["file"] + ".glb")
    problems = []
    K.reset_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    objs = list(bpy.data.objects)
    meshes = [o for o in objs if o.type == "MESH"]
    empties = [o for o in objs if o.type == "EMPTY"]
    for o in objs:
        if o.parent is not None:
            problems.append("%s has a parent" % o.name)
        if o.type not in ("MESH", "EMPTY"):
            problems.append("object %s is %s" % (o.name, o.type))
    for o in empties:
        if not o.name.startswith("Anchor_"):
            problems.append("empty %s is not Anchor_*" % o.name)
    for o in meshes:
        loc_ok = o.location.length <= 1e-5 or o.name.startswith("Tall_")     # Tall_* keep their floor origin
        if not loc_ok or any(abs(a) > 1e-5 for a in o.rotation_euler) or \
                any(abs(s - 1) > 1e-5 for s in o.scale):
            problems.append("%s transform is not identity" % o.name)
        if not o.data.color_attributes:
            problems.append("%s has no colour attribute (COLOR_0)" % o.name)
    cat = job["bdef"].get("category", "logistics")
    want_hex = K.ACCENTS[cat]
    for m in bpy.data.materials:
        if not m.users:
            continue
        nm = m.name.split(".")[0]
        if nm not in ALLOWED:
            problems.append("material %s not allowed" % m.name)
        if nm in ("Accent", "Neon") and m.node_tree:
            bsdf = next((n for n in m.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
            if bsdf is not None and not bsdf.inputs["Base Color"].is_linked:
                rgb = bsdf.inputs["Base Color"].default_value[:3]
                got = "#" + "".join("%02x" % max(0, min(255, round(linear_to_srgb(c) * 255))) for c in rgb)
                if got != want_hex:
                    problems.append("%s colour %s != %s" % (nm, got, want_hex))
    tris = 0
    rmax = 0.0
    zmin = 1e9
    ao_min, ao_max = 1.0, 0.0
    soil = []
    for o in meshes:
        me = o.data
        tris += sum(len(p.vertices) - 2 for p in me.polygons)
        for v in me.vertices:
            if o.name not in OVERHANG_PARTS:
                rmax = max(rmax, math.hypot(v.co.x, v.co.y))
            zmin = min(zmin, v.co.z)
        if me.color_attributes:
            ca = me.color_attributes[0]
            vals = [0.0] * (len(ca.data) * 4)
            ca.data.foreach_get("color", vals)
            lum = vals[0::4]
            if lum:
                ao_min, ao_max = min(ao_min, min(lum)), max(ao_max, max(lum))
        if o.name == "Interior" and job["tid"] in TRAY_TYPES:
            for p in me.polygons:
                mat = me.materials[p.material_index].name.split(".")[0] if me.materials else ""
                if mat != "Soil":
                    continue
                zs = [me.vertices[i].co.z for i in p.vertices]
                if max(abs(z - K.SOIL_Z) for z in zs) < 0.004 and p.normal.z > 0.99:
                    soil.append((p.center.x, p.center.y, p.area))
    if job["tid"] != "corridor" and rmax > job["R"] - K.MARGIN + 1e-3:
        problems.append("re-import radius %.3f > %.2f" % (rmax, job["R"] - K.MARGIN))
    if zmin < -0.25:
        problems.append("z min %.3f" % zmin)
    tray_err = None
    if job["tid"] in TRAY_TYPES:
        clusters = []
        for x, y, a in soil:
            for c in clusters:
                if math.hypot(c[0] / c[2] - x, c[1] / c[2] - y) < 1.2:
                    c[0] += x * a
                    c[1] += y * a
                    c[2] += a
                    c[3] += a
                    break
            else:
                clusters.append([x * a, y * a, a, a])
        got = sorted((c[0] / c[2], c[1] / c[2]) for c in clusters)
        want = sorted(expected_trays(job))
        if len(got) != len(want):
            problems.append("found %d soil trays, content has %d" % (len(got), len(want)))
        else:
            tray_err = max(math.hypot(g[0] - w[0], g[1] - w[1]) for g, w in zip(got, want))
            if tray_err > 0.01:
                problems.append("tray position error %.3f m" % tray_err)
    return problems, dict(tris=tris, rmax=rmax, zmin=zmin, ao_min=ao_min, ao_max=ao_max, tray_err=tray_err,
                          meshes=sorted(o.name for o in meshes), empties=sorted(o.name for o in empties))


# --------------------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------------------
def write_reports(rows):
    existing = {}
    if os.path.exists(K.REPORT_JSON):
        try:
            with open(K.REPORT_JSON, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            if data.get("generator") == "rooms_build.py":
                existing = {r["id"]: r for r in data["models"]}
        except Exception:
            existing = {}
    for r in rows:
        existing[r["id"]] = r
        for a in r.get("also") or []:
            existing.pop(a, None)          # a copy is not its own row (airlock.glb = airlock_m since 2026-09-25)
    order = {tid: k for k, tid in enumerate(ORDER)}

    def key(r):
        return (order.get(r["type"], 99), "s m l xl -".split().index(r["size"]) if r["size"] in "s m l xl -".split() else 9)
    ordered = sorted(existing.values(), key=key)
    with open(K.REPORT_JSON, "w", encoding="utf-8") as fh:
        json.dump(dict(generator="rooms_build.py", blender=bpy.app.version_string, models=ordered), fh, indent=1)
    lines = ["# Build report - room buildings (ART-A, Frontier Habitat 2.0)", "",
             "Written by `tools/blender/rooms_build.py` (Blender %s). Rebuild command:" % bpy.app.version_string, "",
             "```",
             "\"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe\" --background --factory-startup "
             "--python tools/blender/rooms_build.py -- [--only id1,id2] [--sizes s,m,l,xl] [--no-thumbs] [--review]",
             "```", "",
             "Blender coordinates (Z up). `max r` = largest horizontal distance of any vertex from the origin; "
             "`margin` = footprint radius - max r (must be >= 0.10). Budgets: v2 files S 3000, M 4500, L 6500, XL 9000; "
             "3.0 files (interior + Wall_00..31, flagged [v3]) S 10000, M 15000, L 22000, XL 30000 "
             "triangles (all objects, L2..L5 included); 3.0 files: at most 14 materials per object. `verify` = re-import test in an empty Blender scene "
             "(objects, materials, COLOR_0, radius, trays).", "",
             "| file | tris / budget | per object | size X x Y x Z (m) | max r | footprint | margin | AO min..max | anchors | bytes | flags |",
             "|---|---:|---|---|---:|---:|---:|---|---|---:|---|"]
    for r in ordered:
        dims = " x ".join("%.1f" % (b - a) for a, b in zip(r["bbox_min"], r["bbox_max"]))
        per = ", ".join("%s %d" % kv for kv in r["tris_by_object"].items())
        v = r.get("verify", {})
        aor = "%.2f..%.2f" % (v.get("ao_min", 0), v.get("ao_max", 0)) if v else "-"
        fl = list(r["flags"]) + list(r.get("verify_problems", []))
        lines.append("| `%s` | %d / %d | %s | %s | %.2f | %.2f | %.2f | %s | %s | %d | %s |" % (
            r["id"], r["tris"], r["budget"], per, dims, r["max_radius"], r["footprint"], r["margin"], aor,
            " ".join(a.replace("Anchor_", "") for a in r.get("anchors", [])) or "-", r["file_size"],
            "; ".join(fl) or "ok"))
    lines += ["", "M files are also written as `<id>.glb` (v1 file names). Thumbnails: `assets/thumbs/<id>_<size>.png` "
              "(+ `<id>.png` = M), 256 x 256, transparent, EEVEE, lens 70 mm, azimuth -42 deg, elevation 40 deg, "
              "roof on, L2..L5 hidden (same camera and light as ART-B)."]
    with open(K.REPORT_MD, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = sizes = None
    if "--only" in argv:
        only = [s.strip() for s in argv[argv.index("--only") + 1].split(",") if s.strip()]
        unknown = [s for s in only if s not in BUILDERS]
        if unknown:
            raise SystemExit("no builder for: " + ", ".join(unknown))
    if "--sizes" in argv:
        sizes = [s.strip() for s in argv[argv.index("--sizes") + 1].split(",") if s.strip()]
    os.makedirs(K.MODEL_DIR, exist_ok=True)
    os.makedirs(K.THUMB_DIR, exist_ok=True)
    buildings = K.load_buildings()
    todo = jobs(buildings, only, sizes)
    print("rooms_build: %d files" % len(todo))
    rows = []
    t0 = time.time()
    for job in todo:
        try:
            rows.append(build_one(job))
        except Exception:
            traceback.print_exc()
            print("  FAILED", job["file"])
    if "--no-verify" not in argv:
        byid = {r["id"]: r for r in rows}
        for job in todo:
            if job["file"] not in byid:
                continue
            problems, info = verify_file(job)
            byid[job["file"]]["verify"] = info
            byid[job["file"]]["verify_problems"] = problems
            print("  verify %-24s %s  AO %.2f..%.2f%s" % (job["file"], "; ".join(problems) or "ok", info["ao_min"],
                                                        info["ao_max"],
                                                        ("  tray err %.4f" % info["tray_err"]) if info["tray_err"] is not None else ""))
    write_reports(rows)
    write_door_blocked(rows)
    if "--no-thumbs" not in argv or "--review" in argv:
        import rooms_render
        done = [j for j in todo if any(r["id"] == j["file"] for r in rows)]
        if "--no-thumbs" not in argv:
            rooms_render.thumbs(done)
        if "--review" in argv:
            rooms_render.review(done)
    bad = [r["id"] for r in rows if r["flags"] or r.get("verify_problems")]
    print("rooms_build: %d built, %d with flags %s, %.0f s" % (len(rows), len(bad), bad, time.time() - t0))


if __name__ == "__main__":
    main()
