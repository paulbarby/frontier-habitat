extends RefCounted
## Room navigation grids (RENDER, V3_1 §4.1 and §4.4).
##
## For every room MODEL a top-down occupancy grid in model space (cell 0.1 m) is built once
## from the model's own triangles: furniture (Interior, WallsIn, Tall, and the wall-side
## items of the Walls group) between 0.20 m and 1.90 m above the floor blocks its cells; the
## wall ring itself is marked as wall. Tall parts keep their segment, because a room hides the
## Tall parts near its doorways. The grid serves the path check (a body inside furniture)
## and the path planner (string-pulling in free floor with a clearance).
##
## Values in `occ`: 0 free, 1 furniture, 2 wall. `tall` holds segment + 1 of a Tall part that
## covers the cell (0 = none); such a cell is blocked unless the room hides that segment.

const Models = preload("res://presentation/models.gd")
const CELL := 0.1
const FLOOR := 0.14
const LOW := 0.20      # m above the floor: lower items (rugs, trays at floor level) are walkable
const HIGH := 1.90     # m above the floor: higher items (ceiling lamps, shelves above heads) are not in the way

static var _grids := {}
static var _warned := {}
static var allow_live := false

## The grid of a template (built on first use). {} when the template has no wall ring.
static func grid_of(tpl: Dictionary) -> Dictionary:
	var key: String = String(tpl.get("key", ""))
	var base_key: String = key.get_slice("@", 0)
	if _grids.has(base_key):
		return _grids[base_key]
	var baked: Dictionary = _load_baked(tpl, base_key)
	if not baked.is_empty():
		_grids[base_key] = baked
		return baked
	# In the web build a model without a current baked grid is NOT rasterised live (70-140 ms,
	# a frame stall that makes the web audio crackle): the planner falls back to the room's
	# aisle graph. Run tools/render_nav_bake.gd before an export (render_export.mjs does).
	if OS.has_feature("web") and not allow_live:
		if not _warned.has(base_key):
			_warned[base_key] = true
			push_warning("RENDER nav: no current baked grid for %s (run tools/render_nav_bake.gd)" % base_key)
		_grids[base_key] = {}
		return {}
	var wall_r := 0.0
	for p in tpl.get("parts", []):
		wall_r = maxf(wall_r, float(p.get("wall_r", 0.0)))
	if wall_r <= 0.0:
		_grids[base_key] = {}
		return {}
	var half: float = wall_r + 0.4
	var n: int = int(ceil(2.0 * half / CELL))
	var occ := PackedByteArray()
	occ.resize(n * n)
	var tall := PackedInt32Array()
	tall.resize(n * n)
	# Wall cells (Walls, WallsIn) keep their wall segment: a doorway hides the segments of its
	# span, so a body walking through the opening is not "in the wall" there (V3.1).
	var wseg := PackedByteArray()
	wseg.resize(n * n)
	var wcode := PackedByteArray()
	wcode.resize(n * n)
	var g := {"n": n, "half": half, "wall_r": wall_r, "occ": occ, "tall": tall, "wseg": wseg, "wcode": wcode, "tris": 0}
	for p in tpl["parts"]:
		if bool(p.get("shadow_only", false)):
			continue
		var grp: String = p["group"]
		if not (grp in NAV_GROUPS):
			continue
		_raster_part(g, p, grp)
	_grids[base_key] = g
	return g

## A signature of the model parts the grid is made from (index counts): a baked grid is used
## only when the model has not changed since it was baked.
static func tri_sig(tpl: Dictionary) -> int:
	var s := 0
	for p in tpl["parts"]:
		if bool(p.get("shadow_only", false)) or not (String(p["group"]) in NAV_GROUPS):
			continue
		var mesh: Mesh = p["mesh"]
		for si in mesh.get_surface_count():
			var ic: int = mesh.surface_get_array_index_len(si)
			s = (s * 31 + (ic if ic > 0 else mesh.surface_get_array_len(si)) + si) % 2147483647
	return s

## Groups rasterised into the walk grid. The airlock door leaves (V3.1) are wall (code 2):
## the chamber is closed to the room planner; fx_airlock routes riders through its doors.
const NAV_GROUPS := ["Interior", "WallsIn", "Tall", "Walls", "InnerDoorL", "InnerDoorR", "OuterDoorL", "OuterDoorR"]
const BAKE_DIR := "res://presentation/navgrid/"
static var _room_meta = null

## ART-HAB's decal data for a room model id (e.g. "habitat_m"): shell, upper_z, upper_band,
## name_sign_deg. {} when unknown.
static func room_meta(id: String) -> Dictionary:
	if _room_meta == null:
		_room_meta = {}
		if ResourceLoader.exists(BAKE_DIR + "room_meta.res"):
			var r = load(BAKE_DIR + "room_meta.res")
			if r != null and (r as Resource).has_meta("rooms"):
				_room_meta = (r as Resource).get_meta("rooms")
	return _room_meta.get(id, {})

static func _load_baked(tpl: Dictionary, base_key: String) -> Dictionary:
	var name: String = base_key.get_file().get_basename()
	# A .res file (a Resource with the grid in its metadata): exported with the project.
	var path: String = BAKE_DIR + name + ".res"
	if not ResourceLoader.exists(path):
		return {}
	var r = load(path)
	if r == null or not (r as Resource).has_meta("nav"):
		return {}
	var d = (r as Resource).get_meta("nav")
	if not (d is Dictionary) or int(d.get("sig", -1)) != tri_sig(tpl) or not (d as Dictionary).has("wseg"):
		return {}
	var tall := PackedInt32Array()
	var tb: PackedByteArray = d["tall"]
	tall.resize(tb.size())
	for k in tb.size():
		tall[k] = tb[k]
	return {"n": int(d["n"]), "half": float(d["half"]), "wall_r": float(d["wall_r"]), "occ": d["occ"], "tall": tall, "wseg": d["wseg"], "wcode": d["wcode"], "tris": int(d.get("tris", 0)), "baked": true}

## Writes the grid of a template for the web build (tools/render_nav_bake.gd).
static func bake(tpl: Dictionary, name: String) -> bool:
	var g: Dictionary = grid_of(tpl)
	if g.is_empty():
		return false
	var tb := PackedByteArray()
	var tall: PackedInt32Array = g["tall"]
	tb.resize(tall.size())
	for k in tall.size():
		tb[k] = clampi(tall[k], 0, 255)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_DIR))
	var r := Resource.new()
	r.set_meta("nav", {"n": g["n"], "half": g["half"], "wall_r": g["wall_r"], "occ": g["occ"], "tall": tb, "wseg": g["wseg"], "wcode": g["wcode"], "tris": g["tris"], "sig": tri_sig(tpl)})
	return ResourceSaver.save(r, BAKE_DIR + name + ".res", ResourceSaver.FLAG_COMPRESS) == OK

static func _raster_part(g: Dictionary, p: Dictionary, grp: String) -> void:
	var mesh: Mesh = p["mesh"]
	var xf: Transform3D = p["xf"]
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		if arr.size() < Mesh.ARRAY_MAX:
			continue
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		var uv2 = arr[Mesh.ARRAY_TEX_UV2]
		var has_uv2: bool = uv2 is PackedVector2Array and (uv2 as PackedVector2Array).size() == v.size()
		var idx = arr[Mesh.ARRAY_INDEX]
		var ii := PackedInt32Array()
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			ii = idx
		else:
			ii.resize(v.size())
			for k in v.size():
				ii[k] = k
		var t := 0
		while t + 2 < ii.size():
			var a: Vector3 = xf * v[ii[t]]
			var b: Vector3 = xf * v[ii[t + 1]]
			var c: Vector3 = xf * v[ii[t + 2]]
			var seg: int = int((uv2 as PackedVector2Array)[ii[t]].x + 0.5) - 1 if has_uv2 else -1
			t += 3
			var lo: float = minf(a.y, minf(b.y, c.y)) - FLOOR
			var hi: float = maxf(a.y, maxf(b.y, c.y)) - FLOOR
			if hi < LOW or lo > HIGH:
				continue
			var code := 1
			if grp.ends_with("DoorL") or grp.ends_with("DoorR"):
				code = 2
			if grp == "Walls":
				var cen := Vector2((a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0)
				if cen.length() >= float(g["wall_r"]) - 0.36:
					code = 2
			var wtag: int = (seg + 1) if (grp == "Walls" or grp == "WallsIn") and seg >= 0 else 0
			_raster_tri(g, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), code, seg + 1 if grp == "Tall" else 0, wtag)
			g["tris"] = int(g["tris"]) + 1

static func _mark(g: Dictionary, q: Vector2, code: int, tseg: int, wtag: int = 0) -> void:
	var n: int = g["n"]
	var half: float = g["half"]
	var i: int = int(floor((q.x + half) / CELL))
	var j: int = int(floor((q.y + half) / CELL))
	if i < 0 or j < 0 or i >= n or j >= n:
		return
	var k: int = j * n + i
	if tseg > 0:
		(g["tall"] as PackedInt32Array)[k] = tseg
		return
	if wtag > 0 and g.has("wseg"):
		var wc: PackedByteArray = g["wcode"]
		if wc[k] < code:
			wc[k] = code
			(g["wseg"] as PackedByteArray)[k] = wtag
		return
	var occ: PackedByteArray = g["occ"]
	if occ[k] < code:
		occ[k] = code

static func _raster_tri(g: Dictionary, a: Vector2, b: Vector2, c: Vector2, code: int, tseg: int, wtag: int = 0) -> void:
	# Edges (vertical panels project to lines).
	for e in [[a, b], [b, c], [c, a]]:
		var p0: Vector2 = e[0]
		var p1: Vector2 = e[1]
		var steps: int = maxi(1, int(ceil(p0.distance_to(p1) / (CELL * 0.5))))
		for s in steps + 1:
			_mark(g, p0.lerp(p1, float(s) / steps), code, tseg, wtag)
	# Interior of the triangle (cell centres).
	var area: float = (b - a).cross(c - a)
	if absf(area) < 1e-6:
		return
	var n: int = g["n"]
	var half: float = g["half"]
	var i0: int = maxi(0, int(floor((minf(a.x, minf(b.x, c.x)) + half) / CELL)))
	var i1: int = mini(n - 1, int(floor((maxf(a.x, maxf(b.x, c.x)) + half) / CELL)))
	var j0: int = maxi(0, int(floor((minf(a.y, minf(b.y, c.y)) + half) / CELL)))
	var j1: int = mini(n - 1, int(floor((maxf(a.y, maxf(b.y, c.y)) + half) / CELL)))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var q := Vector2((i + 0.5) * CELL - half, (j + 0.5) * CELL - half)
			var w0: float = (b - a).cross(q - a)
			var w1: float = (c - b).cross(q - b)
			var w2: float = (a - c).cross(q - c)
			if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) or (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0):
				_mark(g, q, code, tseg, wtag)

## Cell value at a model-space point: 0 free, 1 furniture, 2 wall, 3 outside the grid.
## `tall_hidden` = the room's mask of hidden Tall segments; `wall_hidden` = its mask of hidden
## wall segments (the doorway spans, fx_doors.masks).
static func at(g: Dictionary, q: Vector2, tall_hidden: int = 0, wall_hidden: int = 0) -> int:
	var n: int = g["n"]
	var half: float = g["half"]
	var i: int = int(floor((q.x + half) / CELL))
	var j: int = int(floor((q.y + half) / CELL))
	if i < 0 or j < 0 or i >= n or j >= n:
		return 3
	var k: int = j * n + i
	var o: int = (g["occ"] as PackedByteArray)[k]
	if o > 0:
		return o
	if g.has("wseg"):
		var ws: int = (g["wseg"] as PackedByteArray)[k]
		if ws > 0 and (wall_hidden & (1 << (ws - 1))) == 0:
			return (g["wcode"] as PackedByteArray)[k]
	var ts: int = (g["tall"] as PackedInt32Array)[k]
	if ts > 0 and (tall_hidden & (1 << (ts - 1))) == 0:
		return 1
	return 0
