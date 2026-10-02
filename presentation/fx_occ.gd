extends RefCounted
## Sight-line occluders for the follow view (RENDER, orchestrator 2026-10-02: a dome pillar stood between the
## camera and the person and the near-fade dither drew it as a grainy half-transparent band over the body).
##
## For a structure MODEL: a top-down grid (cell CELL m, model space) whose cells hold a 64-bit mask of height
## bands (BAND m each, from the model's lowest point): bit k set = a steep solid surface (a wall, a pillar, a
## partition, a shelf side) lies in band k of that cell. Flat surfaces (floors, ceilings, table tops) and glass
## are left out: the camera has its own floor and ceiling rules, and glass does not hide the person.
## world_view.follow_occluder() walks the line from the person's chest and head to the eye through the grids
## of the structures round the person; the camera rig pulls the eye in to stand in front of the first
## occluder (camera_rig, SH_OCC_*). The grids are baked by tools/render_nav_bake.gd (presentation/navgrid/
## occ_<model>.res, a tri signature like fx_nav), so the web build never rasterises a model at run time.

const CELL := 0.2
const BAND := 0.3         # 62 bands (64-bit masks): 18.6 m
const STEEP := 0.7        # |normal.y| under this is a wall-like surface
const SKIP_GROUPS := ["Roof", "PorchTop", "Decal", "NameSign", "Lights", "Base", "Rotor", "Beacon"]
const BAKE_DIR := "res://presentation/navgrid/"
static var _grids := {}

## The grid of a template ({} = none, e.g. not baked in the web build). `key` is the template's base key.
static func grid_of(tpl: Dictionary) -> Dictionary:
	var key: String = String(tpl.get("key", "")).get_slice("@", 0)
	if _grids.has(key):
		return _grids[key]
	var name: String = _name_of(key)
	var path: String = BAKE_DIR + "occ_" + name + ".res"
	if ResourceLoader.exists(path):
		var r = load(path)
		if r != null and (r as Resource).has_meta("occ"):
			var d: Dictionary = (r as Resource).get_meta("occ")
			if int(d.get("sig", -1)) == sig(tpl):
				var cells := {}
				var ks: PackedInt32Array = d["keys"]
				var ms: PackedInt64Array = d["masks"]
				for i in ks.size():
					cells[ks[i]] = ms[i]
				_grids[key] = {"cells": cells, "y0": float(d["y0"]), "n": int(d["n"]), "o": Vector2(d["ox"], d["oz"])}
				return _grids[key]
	if OS.has_feature("web"):
		_grids[key] = {}
		return {}
	_grids[key] = build(tpl)
	return _grids[key]

static func _name_of(key: String) -> String:
	if key.begins_with("dome:"):
		return key.replace(":", "_")
	return key.get_file().get_basename()

## A signature of the parts the grid is made from (surface index counts).
static func sig(tpl: Dictionary) -> int:
	var s := 0
	for p in tpl.get("parts", []):
		if not _use_part(p):
			continue
		var mesh: Mesh = p["mesh"]
		for si in mesh.get_surface_count():
			var ic: int = mesh.surface_get_array_index_len(si)
			s = (s * 31 + (ic if ic > 0 else mesh.surface_get_array_len(si)) + si) % 2147483647
	return s

static func _use_part(p: Dictionary) -> bool:
	if bool(p.get("shadow_only", false)):
		return false
	var g: String = String(p.get("group", ""))
	for sk in SKIP_GROUPS:
		if g == sk or g.begins_with(sk + "_"):
			return false
	return not g.ends_with("Top")

static func build(tpl: Dictionary) -> Dictionary:
	var ab: AABB = tpl.get("aabb", AABB())
	var o := Vector2(ab.position.x - 0.5, ab.position.z - 0.5)
	var n: int = int(ceil((maxf(ab.size.x, ab.size.z) + 1.0) / CELL))
	var y0: float = ab.position.y
	var cells := {}
	for p in tpl.get("parts", []):
		if not _use_part(p):
			continue
		var mesh: Mesh = p["mesh"]
		var xf: Transform3D = p["xf"]
		for si in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(si)
			var mn: String = mat.resource_name if mat != null else ""
			if mn.contains("Glass") or mn.contains("Water") or mn.contains("Holo") or mn.contains("Light"):
				continue
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				continue
			var arr: Array = mesh.surface_get_arrays(si)
			if arr.size() < Mesh.ARRAY_MAX:
				continue
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var ii := PackedInt32Array()
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				ii = idx
			else:
				ii.resize(v.size())
				for k0 in v.size():
					ii[k0] = k0
			var t := 0
			while t + 2 < ii.size():
				var a: Vector3 = xf * v[ii[t]]
				var b: Vector3 = xf * v[ii[t + 1]]
				var c: Vector3 = xf * v[ii[t + 2]]
				t += 3
				var nrm: Vector3 = (b - a).cross(c - a)
				if nrm.length() < 1e-6 or absf(nrm.normalized().y) >= STEEP:
					continue
				var lo: int = clampi(int(floor((minf(a.y, minf(b.y, c.y)) - y0) / BAND)), 0, 61)
				var hi: int = clampi(int(floor((maxf(a.y, maxf(b.y, c.y)) - y0) / BAND)), 0, 61)
				var mask := 0
				for k in range(lo, hi + 1):
					mask |= 1 << k
				# steep triangles project to thin shapes: mark along the edges (half-cell steps)
				for e in [[a, b], [b, c], [c, a]]:
					var p0 := Vector2((e[0] as Vector3).x, (e[0] as Vector3).z)
					var p1 := Vector2((e[1] as Vector3).x, (e[1] as Vector3).z)
					var steps: int = maxi(1, int(ceil(p0.distance_to(p1) / (CELL * 0.5))))
					for s2 in steps + 1:
						var q: Vector2 = p0.lerp(p1, float(s2) / steps) - o
						var i: int = int(floor(q.x / CELL))
						var j: int = int(floor(q.y / CELL))
						if i < 0 or j < 0 or i >= n or j >= n:
							continue
						var key: int = j * n + i
						cells[key] = int(cells.get(key, 0)) | mask
	return {"cells": cells, "y0": y0, "n": n, "o": o}

## Writes the grid of a template for the web build. Returns the cell count.
static func bake(tpl: Dictionary) -> int:
	var key: String = String(tpl.get("key", "")).get_slice("@", 0)
	var g: Dictionary = build(tpl)
	_grids[key] = g
	var ks := PackedInt32Array()
	var ms := PackedInt64Array()
	for k in g["cells"]:
		ks.append(int(k))
		ms.append(int(g["cells"][k]))
	var r := Resource.new()
	r.set_meta("occ", {"keys": ks, "masks": ms, "y0": g["y0"], "n": g["n"], "ox": (g["o"] as Vector2).x, "oz": (g["o"] as Vector2).y, "sig": sig(tpl)})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_DIR))
	ResourceSaver.save(r, BAKE_DIR + "occ_" + _name_of(key) + ".res", ResourceSaver.FLAG_COMPRESS)
	return ks.size()

## Is model-space point p (x, y, z) inside an occluding cell band?
static func blocked(g: Dictionary, p: Vector3) -> bool:
	var q := Vector2(p.x, p.z) - (g["o"] as Vector2)
	var n: int = g["n"]
	var i: int = int(floor(q.x / CELL))
	var j: int = int(floor(q.y / CELL))
	if i < 0 or j < 0 or i >= n or j >= n:
		return false
	var m: int = int((g["cells"] as Dictionary).get(j * n + i, 0))
	if m == 0:
		return false
	var b: int = int(floor((p.y - float(g["y0"])) / BAND))
	return b >= 0 and b < 62 and (m & (1 << b)) != 0
