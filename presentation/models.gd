extends RefCounted
## Model library (RENDER). Loads the Blender-made .glb files from res://assets/models and
## turns each one into a TEMPLATE: a flat list of mesh parts grouped by their top-level
## object name (docs/AAA_DESIGN.md §11), plus the Anchor_* empties.
##
## File order for a structure: <id>_<s|m|l|xl>.glb -> <id>.glb (scaled by radius) -> a
## primitive stand-in, so the game always runs while the art is still being made.
##
## Materials are shared: every imported material is replaced once by a library copy.
## A surface that has a vertex colour array (baked AO, COLOR_0) gets a copy with
## vertex_color_use_as_albedo on. Emissive materials are registered so the view can turn
## windows and lamps up at night with one call (set_night).

const CATEGORY_COLOR := {
	"life_support": Color("29b6c6"), "food": Color("6abf4b"), "housing": Color("f2c14e"),
	"industry": Color("e07a3a"), "logistics": Color("9b6bd6"), "utilities": Color("4a90d9"),
	"medical": Color("e85d75"), "comfort": Color("f08fc0"), "science": Color("7c8cff"), "space": Color("c9d3e0"),
}
const ROLE_COLOR := {
	"technician": Color("ff9f1c"), "grower": Color("5ac85a"), "operator": Color("4a90d9"), "medic": Color("e85d75"),
	"scientist": Color("a78bfa"),
}
const RES_COLOR := {
	"metal": Color("9aa3ad"), "polymer": Color("e8d9a0"), "spare_parts": Color("c07a3a"), "meals": Color("f2c14e"),
	"water": Color("3aa0d8"), "raw_food": Color("6abf4b"), "biomass": Color("3f7d3a"), "ore": Color("6b4a3a"), "medicine": Color("e85d75"),
	"silicate": Color("d8c8a8"), "exotic": Color("b58cff"), "glass": Color("9fd4ea"), "electronics": Color("4ad0a0"),
	"hull_plate": Color("c9d3e0"), "composite": Color("5b6b7d"), "rocket_fuel": Color("ff7a45"),
	"potato": Color("c9a066"), "wheat": Color("e8c86a"), "soybean": Color("a8c070"), "tomato": Color("e0503a"),
	"greens": Color("6abf4b"), "mushroom": Color("c8b8a8"), "algae": Color("3fb07a"), "herbs": Color("4f9a4a"),
}
const SIZE_SUFFIX := ["s", "m", "l", "xl"]
## Top-level object names of the asset contract. Anything else is static geometry ("Base").
const GROUPS := ["Interior", "Roof", "Rotor", "Lights", "Scaffold", "EngineGlow", "Plasma", "Damage1", "Damage2", "Damage3",
	"Stage1", "Stage2", "Stage3", "Body", "ArmL", "ArmR", "LegL", "LegR", "L2", "L3", "L4", "L5", "Hull",
	"DoorLTop", "DoorRTop", "DoorL", "DoorR", "FrameTop", "Sign", "Turret", "Base"]
## V3 §7.2: Wall_00..Wall_31 are merged into one "Walls" group (segment id in UV2.x).
const WALL_SEGMENTS := 32
## Materials that the instancer recolours per instance (INSTANCE_CUSTOM.rgb).
const TINTABLE := ["SuitAccent", "Cargo", "Skin", "Hair"]
## Groups that never cast a shadow (inside a closed room, or light sources).
const NO_SHADOW := ["Interior", "Tall", "WallsIn", "Lights", "EngineGlow", "Plasma", "Stage1", "Stage2", "Stage3"]
## Materials used only inside rooms (V3 §7.3): they get the interior fill light anywhere.
const INTERIOR_ONLY := ["Floor", "FloorDark", "Wood", "Cushion", "Fabric", "Screen"]
## Night fill of interiors (emission = albedo x AO x fill): day, night.
const FILL_DAY := 0.05
const FILL_NIGHT := 0.36

static var _scenes := {}         # path -> PackedScene or null
static var _templates := {}      # key -> template Dictionary
static var _lib := {}            # material key -> Material
static var _mats := {}           # flat/ghost material cache (v1 helpers)
static var _prepared := {}       # mesh instance id -> true
static var _night: Array = []    # [{mat, base, name}]
static var _night_sm: Array = [] # wall-cut ShaderMaterials with emission: [{mat, base, name}]
static var _fill_mats: Array = [] # interior and wall ShaderMaterials with a "fill" parameter
static var _int_mats := {}        # source material id -> interior ShaderMaterial
static var _int_shader: Shader
static var _night_f := -1.0
static var _tint_mats := {}      # source material id -> ShaderMaterial
static var _tint_shader: Shader

# ---------------------------------------------------------------- files
static var _exists := {}
static func has_model(id: String) -> bool:
	if not _exists.has(id):
		_exists[id] = ResourceLoader.exists("res://assets/models/%s.glb" % id)
	return _exists[id]

## Resolves the file for a structure of a given size (-1 = no size). Returns
## {"path": String or "", "sized": bool}.
static func resolve(id: String, size: int = -1) -> Dictionary:
	if size >= 0 and size < SIZE_SUFFIX.size():
		var sized := "%s_%s" % [id, SIZE_SUFFIX[size]]
		if has_model(sized):
			return {"path": "res://assets/models/%s.glb" % sized, "sized": true}
	if has_model(id):
		return {"path": "res://assets/models/%s.glb" % id, "sized": false}
	return {"path": "", "sized": false}

static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]

# ---------------------------------------------------------------- templates
## A structure template. `radius` is the record radius (size-specific); `m_radius` is the
## radius the unsized model was made for (the def's base radius = size M).
static func building(def_id: String, size: int, radius: float, m_radius: float, kind: String, category: String) -> Dictionary:
	var r: Dictionary = resolve(def_id, size)
	if r["path"] != "":
		var key: String = r["path"]
		var tpl: Dictionary = _template_from_file(key)
		var s := 1.0
		if not bool(r["sized"]) and m_radius > 0.01 and size >= 0:
			s = radius / m_radius
		return _with_scale(tpl, s)
	var fkey := "fallback:%s:%.2f:%s" % [def_id, radius, kind]
	if not _templates.has(fkey):
		var node: Node3D = _fallback_node(def_id, radius, kind, CATEGORY_COLOR.get(category, Color.GRAY))
		_templates[fkey] = _parse(node, fkey)
		node.free()
	return _with_scale(_templates[fkey], 1.0)

## A prop or figure template by file id, falling back through `fallbacks` then a primitive.
static func prop(ids: Array, radius: float = 0.5, kind: String = "exterior", category: String = "logistics") -> Dictionary:
	for id in ids:
		if has_model(id):
			return _with_scale(_template_from_file("res://assets/models/%s.glb" % id), 1.0)
	var fkey := "fallback:%s:%.2f:%s" % [ids[0], radius, kind]
	if not _templates.has(fkey):
		var node: Node3D = _fallback_node(String(ids[0]), radius, kind, CATEGORY_COLOR.get(category, Color.GRAY))
		_templates[fkey] = _parse(node, fkey)
		node.free()
	return _with_scale(_templates[fkey], 1.0)

static func _with_scale(tpl: Dictionary, s: float) -> Dictionary:
	if absf(s - 1.0) < 0.001:
		return tpl
	var out: Dictionary = tpl.duplicate()
	out["scale"] = s
	out["key"] = "%s@%.3f" % [tpl["key"], s]
	return out

static func _template_from_file(path: String) -> Dictionary:
	if _templates.has(path):
		return _templates[path]
	var scene: PackedScene = _scene(path)
	var root: Node = scene.instantiate() if scene != null else null
	if root == null or not (root is Node3D):
		if root != null:
			root.free()
		var fb: Node3D = _fallback_node(path.get_file().get_basename(), 3.0, "room", Color.GRAY)
		_templates[path] = _parse(fb, path)
		fb.free()
		return _templates[path]
	_templates[path] = _parse(root as Node3D, path)
	root.free()
	return _templates[path]

static func group_of(n: String) -> String:
	if n.begins_with("Wall_") and n.length() >= 7 and n.substr(5, 2).is_valid_int():
		return "Walls"
	# Tall furniture (ART-HAB P5): hidden when a doorway is close; cut away with the Interior.
	if n.begins_with("Tall_") and n.substr(5).is_valid_int():
		return "Tall"
	for g in GROUPS:
		if n.begins_with(g):
			if (g == "L2" or g == "L3" or g == "L4" or g == "L5") and n.length() > 2 and n[2].is_valid_int():
				continue
			return g
	return "Base"

## Flattens a model scene into parts. Transforms are relative to the model root.
static func _parse(root: Node3D, key: String) -> Dictionary:
	var parts: Array = []
	var anchors := {}
	var aabb := AABB()
	var first := true
	for top in root.get_children():
		if not (top is Node3D):
			continue
		var tname := String(top.name)
		if tname.begins_with("Anchor_"):
			anchors[tname.substr(7)] = (top as Node3D).transform
			continue
		var group: String = group_of(tname)
		var pivot: Transform3D = (top as Node3D).transform
		var stack: Array = [[top, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var e: Array = stack.pop_back()
			var n: Node3D = e[0]
			var rel: Transform3D = e[1]   # node -> top
			if n != top and String(n.name).begins_with("Anchor_"):
				anchors[String(n.name).substr(7)] = pivot * rel
				continue
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mesh: Mesh = (n as MeshInstance3D).mesh
				_prepare_mesh(mesh)
				var xf: Transform3D = pivot * rel
				var part := {"group": group, "mesh": mesh, "xf": xf, "pivot": pivot, "local": rel,
					"shadow": not (group in NO_SHADOW)}
				if group == "Walls":
					part["seg"] = int(tname.substr(5, 2))
				elif group == "Tall":
					part["seg"] = int(tname.substr(5))
				parts.append(part)
				var ab: AABB = xf * mesh.get_aabb()
				aabb = ab if first else aabb.merge(ab)
				first = false
			for c in n.get_children():
				if c is Node3D:
					stack.append([c, rel * (c as Node3D).transform])
	# Spin axis of a rotor: the thinnest side of its mesh bounds, in pivot space.
	var rotor_axis := Vector3(0, 0, 1)
	for p in parts:
		if p["group"] == "Rotor":
			var ab: AABB = (p["local"] as Transform3D) * (p["mesh"] as Mesh).get_aabb()
			var sz: Vector3 = ab.size
			rotor_axis = Vector3(1, 0, 0) if sz.x <= sz.y and sz.x <= sz.z else (Vector3(0, 1, 0) if sz.y <= sz.z else Vector3(0, 0, 1))
			break
	# Props that are small or inside rooms never cast a shadow.
	var fname: String = key.get_file()
	if fname.begins_with("crop") or fname.begins_with("crate") or key.contains(":crop") or key.contains(":crate"):
		for p in parts:
			p["shadow"] = false
	parts = _merge_groups(parts)
	# Outdoor hazard props reuse room material names (crater rim = Wood): no interior fill.
	if not (fname.begins_with("crater") or fname.begins_with("meteor_rock") or fname.begins_with("fragments")):
		_interior_materials(parts)
	parts = _shadow_proxies(parts)
	var groups := {}
	for p in parts:
		groups[p["group"]] = true
	return {"key": key, "parts": parts, "anchors": anchors, "aabb": aabb, "scale": 1.0, "groups": groups, "rotor_axis": rotor_axis}

## Several meshes of one group (not animated about their own pivot) become ONE mesh with
## one surface per material: fewer draw calls for every copy of the model.
static func _merge_groups(parts: Array) -> Array:
	var by_group := {}
	var order: Array = []
	for p in parts:
		var g: String = p["group"]
		if not by_group.has(g):
			by_group[g] = []
			order.append(g)
		by_group[g].append(p)
	var out: Array = []
	for g in order:
		var list: Array = by_group[g]
		if g == "Walls":
			# The wall shell (seen from outside, always drawn) and the wall-side furniture
			# (drawn only with the roof open, like the Interior): fewer draw calls per room type.
			var shell: Array = _merge_walls(list, true)
			var inside: Array = _merge_walls(list, false)
			for mw in shell:
				mw["group"] = "Walls"
				out.append(mw)
			for mw in inside:
				mw["group"] = "WallsIn"
				out.append(mw)
			continue
		if g == "Tall":
			for mw in _merge_walls(list, null):
				mw["group"] = g
				out.append(mw)
			continue
		if list.size() == 1 or g in ["Rotor", "Body", "ArmL", "ArmR", "LegL", "LegR"]:
			out.append_array(list)
			continue
		var by_mat := {}
		var keys: Array = []
		for p in list:
			var mesh: Mesh = p["mesh"]
			for si in mesh.get_surface_count():
				var m: Material = mesh.surface_get_material(si)
				var mk: int = m.get_instance_id() if m != null else 0
				if not by_mat.has(mk):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					by_mat[mk] = [st, m]
					keys.append(mk)
				(by_mat[mk][0] as SurfaceTool).append_from(mesh, si, p["xf"])
		var merged := ArrayMesh.new()
		for mk in keys:
			var st: SurfaceTool = by_mat[mk][0]
			if by_mat[mk][1] != null:
				st.set_material(by_mat[mk][1])
			st.commit(merged)
		var shadow := false
		for p in list:
			shadow = shadow or bool(p["shadow"])
		out.append({"group": g, "mesh": merged, "xf": Transform3D.IDENTITY, "pivot": Transform3D.IDENTITY, "local": Transform3D.IDENTITY, "shadow": shadow})
	return out

## Shadow proxies (draw-call budget, V3 §0.2): the shadow pass costs one draw call per
## SURFACE of every casting part, and a room has 10+ materials. Each casting part with more
## than one opaque surface gets a twin in the same group (so it follows hidden groups, roof
## lift, rotor spin and the wall doorway mask) that is ONE surface drawn shadows-only; the
## part itself stops casting. Transparent surfaces never cast (as before).
static var _proxy_mat: StandardMaterial3D
static func _shadow_proxies(parts: Array) -> Array:
	var out: Array = []
	for p in parts:
		out.append(p)
		if not bool(p["shadow"]) or bool(p.get("shadow_only", false)):
			continue
		var mesh: Mesh = p["mesh"]
		if mesh.get_surface_count() < 2:
			continue
		var walls: bool = p["group"] == "Walls" or p["group"] == "WallsIn" or p["group"] == "Tall"
		var av := PackedVector3Array()
		var an := PackedVector3Array()
		var a2 := PackedVector2Array()
		var ai := PackedInt32Array()
		for si in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(si)
			var src = m.get_meta("src") if m != null and m.has_meta("src") else m
			if src is BaseMaterial3D and ((src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or (src as BaseMaterial3D).resource_name == "Glass"):
				continue
			var arr: Array = mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			var base: int = av.size()
			av.append_array(v)
			var nrm = arr[Mesh.ARRAY_NORMAL]
			if nrm is PackedVector3Array and (nrm as PackedVector3Array).size() == v.size():
				an.append_array(nrm)
			else:
				var up := PackedVector3Array()
				up.resize(v.size())
				up.fill(Vector3.UP)
				an.append_array(up)
			if walls:
				var uv2 = arr[Mesh.ARRAY_TEX_UV2]
				if uv2 is PackedVector2Array and (uv2 as PackedVector2Array).size() == v.size():
					a2.append_array(uv2)
				else:
					var z := PackedVector2Array()
					z.resize(v.size())
					a2.append_array(z)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				var src_i: PackedInt32Array = idx
				var at: int = ai.size()
				ai.resize(at + src_i.size())
				for k in src_i.size():
					ai[at + k] = src_i[k] + base
			else:
				var at2: int = ai.size()
				ai.resize(at2 + v.size())
				for k in v.size():
					ai[at2 + k] = base + k
		if av.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = av
		arrays[Mesh.ARRAY_NORMAL] = an
		if walls:
			arrays[Mesh.ARRAY_TEX_UV2] = a2
		arrays[Mesh.ARRAY_INDEX] = ai
		var pm := ArrayMesh.new()
		pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if walls:
			pm.surface_set_material(0, wall_material(null))
		else:
			# Two-sided: a SHADOWS_ONLY instance with back-face culling casts no shadow from
			# an open shell (the Meridian hull cast none, tested 2026-09-24 in the browser).
			if _proxy_mat == null:
				_proxy_mat = StandardMaterial3D.new()
				_proxy_mat.resource_name = "ShadowProxy"
				_proxy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			pm.surface_set_material(0, _proxy_mat)
		var q: Dictionary = p.duplicate()
		q["mesh"] = pm
		q["shadow_only"] = true
		out.append(q)
		p["shadow"] = false
	return out

## Interior parts (and interior-only materials in any part) use the interior material:
## the library material plus the night fill (V3 §7.3). Screens get the UI pattern.
static func _interior_materials(parts: Array) -> void:
	for p in parts:
		if p["group"] == "Walls":
			continue
		var mesh: Mesh = p["mesh"]
		if not (mesh is ArrayMesh):
			continue
		var all: bool = p["group"] == "Interior"
		for si in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(si)
			if m == null or not (m is BaseMaterial3D):
				continue
			if all or m.resource_name in INTERIOR_ONLY:
				(mesh as ArrayMesh).surface_set_material(si, interior_material(m))

static func interior_material(src: Material) -> Material:
	var id: int = src.get_instance_id()
	if _int_mats.has(id):
		return _int_mats[id]
	# Critic round 8: interior Glass is transparent (the library material arrives opaque).
	if src.resource_name == "Glass":
		var g := ShaderMaterial.new()
		g.shader = load("res://shaders/glass.gdshader")
		g.resource_name = "Glass"
		g.set_meta("src", src)
		_int_mats[id] = g
		return g
	if _int_shader == null:
		_int_shader = load("res://shaders/interior.gdshader")
	var b: BaseMaterial3D = src
	var m := ShaderMaterial.new()
	m.shader = _int_shader
	m.resource_name = b.resource_name
	m.set_meta("src", b)
	m.set_shader_parameter("albedo", b.albedo_color)
	m.set_shader_parameter("roughness", b.roughness)
	m.set_shader_parameter("metallic", b.metallic)
	m.set_shader_parameter("specular", b.metallic_specular)
	m.set_shader_parameter("use_vc", b.vertex_color_use_as_albedo)
	if b.albedo_texture != null:
		m.set_shader_parameter("albedo_tex", b.albedo_texture)
		m.set_shader_parameter("use_tex", true)
	if b.emission_enabled:
		m.set_shader_parameter("emission", b.emission)
		m.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
		_night_sm.append({"mat": m, "base": maxf(0.2, b.emission_energy_multiplier), "name": b.resource_name})
	m.set_shader_parameter("mode", 1 if b.resource_name == "Screen" else 0)
	m.set_shader_parameter("fill_gain", 1.9 if b.resource_name.begins_with("Floor") else 1.0)
	m.set_shader_parameter("fill", lerpf(FILL_DAY, FILL_NIGHT, maxf(_night_f, 0.0)))
	_fill_mats.append(m)
	_int_mats[id] = m
	return m

## The 32 wall segments as ONE mesh, one surface per material, UV2.x = segment + 1, with
## wall-cut materials (shaders/wall_cut.gdshader) that hide the segments an instance masks.
## part["wall_r"] = the outer radius of the wall ring (doorways stand on it).
## Materials of the wall shell itself (outer face, band, trim, portholes).
const SHELL_MATS := ["Hull", "HullDark", "Accent", "Frame", "Trim", "Window", "Glass", "Metal", "Rubber"]

static func _merge_walls(list: Array, shell = null) -> Array:
	var by_mat := {}
	var keys: Array = []
	var rmax := 0.0
	var seg_pos := {}
	for p in list:
		var mesh: Mesh = p["mesh"]
		var xf: Transform3D = p["xf"]
		var seg: int = int(p.get("seg", 0))
		# The object's own origin (Tall parts: on the floor at the item, ART-HAB P5).
		seg_pos[seg] = (p["pivot"] as Transform3D).origin
		var nb: Basis = xf.basis.inverse().transposed()
		for si in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			var m: Material = mesh.surface_get_material(si)
			if shell != null:
				var is_shell: bool = m != null and m.resource_name in SHELL_MATS
				if is_shell != bool(shell):
					continue
			var mk: int = m.get_instance_id() if m != null else 0
			if not by_mat.has(mk):
				by_mat[mk] = {"mat": m, "v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "i": PackedInt32Array()}
				keys.append(mk)
			# Packed arrays are values: take each one out, grow it, put it back.
			var acc: Dictionary = by_mat[mk]
			var av: PackedVector3Array = acc["v"]
			var an: PackedVector3Array = acc["n"]
			var ac: PackedColorArray = acc["c"]
			var au: PackedVector2Array = acc["uv"]
			var a2: PackedVector2Array = acc["uv2"]
			var ai: PackedInt32Array = acc["i"]
			var base: int = av.size()
			var n: int = v.size()
			var vt: PackedVector3Array = xf * v
			av.append_array(vt)
			for q in vt:
				rmax = maxf(rmax, Vector2(q.x, q.z).length())
			var nrm = arr[Mesh.ARRAY_NORMAL]
			if nrm is PackedVector3Array and (nrm as PackedVector3Array).size() == n:
				an.append_array(Transform3D(nb, Vector3.ZERO) * (nrm as PackedVector3Array))
			else:
				var up := PackedVector3Array()
				up.resize(n)
				up.fill(Vector3.UP)
				an.append_array(up)
			var col = arr[Mesh.ARRAY_COLOR]
			if col is PackedColorArray and (col as PackedColorArray).size() == n:
				ac.append_array(col)
			else:
				var wc := PackedColorArray()
				wc.resize(n)
				wc.fill(Color(1, 1, 1, 1))
				ac.append_array(wc)
			var uv = arr[Mesh.ARRAY_TEX_UV]
			if uv is PackedVector2Array and (uv as PackedVector2Array).size() == n:
				au.append_array(uv)
			else:
				var z := PackedVector2Array()
				z.resize(n)
				au.append_array(z)
			var s2 := PackedVector2Array()
			s2.resize(n)
			s2.fill(Vector2(seg + 1, 0))
			a2.append_array(s2)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				var src: PackedInt32Array = idx
				var at: int = ai.size()
				ai.resize(at + src.size())
				for k in src.size():
					ai[at + k] = src[k] + base
			else:
				var at2: int = ai.size()
				ai.resize(at2 + n)
				for k in n:
					ai[at2 + k] = base + k
			acc["v"] = av
			acc["n"] = an
			acc["c"] = ac
			acc["uv"] = au
			acc["uv2"] = a2
			acc["i"] = ai
	var merged := ArrayMesh.new()
	for mk in keys:
		var acc: Dictionary = by_mat[mk]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = acc["v"]
		arrays[Mesh.ARRAY_NORMAL] = acc["n"]
		arrays[Mesh.ARRAY_COLOR] = acc["c"]
		arrays[Mesh.ARRAY_TEX_UV] = acc["uv"]
		arrays[Mesh.ARRAY_TEX_UV2] = acc["uv2"]
		arrays[Mesh.ARRAY_INDEX] = acc["i"]
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		merged.surface_set_material(merged.get_surface_count() - 1, wall_material(acc["mat"]))
	if merged.get_surface_count() == 0:
		return []
	return [{"group": "Walls", "mesh": merged, "xf": Transform3D.IDENTITY, "pivot": Transform3D.IDENTITY, "local": Transform3D.IDENTITY,
		"shadow": true, "mask": true, "wall_r": rmax, "segments": list.size(), "seg_pos": seg_pos}]

static var _wall_mats := {}
static var _wall_shader: Shader
static var _wall_shader_a: Shader
## The wall-cut copy of a library material (cached).
static func wall_material(src: Material) -> Material:
	var id: int = src.get_instance_id() if src != null else 0
	if _wall_mats.has(id):
		return _wall_mats[id]
	if _wall_shader == null:
		_wall_shader = load("res://shaders/wall_cut.gdshader")
		_wall_shader_a = load("res://shaders/wall_cut_alpha.gdshader")
	var m := ShaderMaterial.new()
	var alpha := false
	if src is BaseMaterial3D:
		var b: BaseMaterial3D = src
		# Critic round 8: Glass in the wall ring is see-through too (clean-room partitions).
		alpha = b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.resource_name == "Glass"
		m.resource_name = b.resource_name
		m.set_meta("src", b)
		m.set_shader_parameter("mode", 1 if b.resource_name == "Screen" else 0)
		m.set_shader_parameter("fill", lerpf(FILL_DAY, FILL_NIGHT, maxf(_night_f, 0.0)))
		_fill_mats.append(m)
		m.set_shader_parameter("albedo", b.albedo_color if b.resource_name != "Glass" else Color(0.62, 0.86, 0.95, 0.3))
		m.set_shader_parameter("roughness", b.roughness)
		m.set_shader_parameter("metallic", b.metallic)
		m.set_shader_parameter("specular", b.metallic_specular)
		m.set_shader_parameter("use_vc", b.vertex_color_use_as_albedo)
		if b.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
			m.set_shader_parameter("use_tex", true)
		if b.emission_enabled:
			m.set_shader_parameter("emission", b.emission)
			m.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
			_night_sm.append({"mat": m, "base": maxf(0.2, b.emission_energy_multiplier), "name": b.resource_name})
	m.shader = _wall_shader_a if alpha else _wall_shader
	_wall_mats[id] = m
	return m

## A copy of a template that casts no shadow (small parts on the wall line: doorways, patches,
## corridor ribs) — draw-call budget.
static func no_shadow(tpl: Dictionary) -> Dictionary:
	var key: String = String(tpl["key"]) + ":ns"
	if _templates.has(key):
		return _templates[key]
	var out: Dictionary = tpl.duplicate()
	out["key"] = key
	var parts: Array = []
	for p in tpl["parts"]:
		if bool(p.get("shadow_only", false)):
			continue
		var q: Dictionary = p.duplicate()
		q["shadow"] = false
		parts.append(q)
	out["parts"] = parts
	_templates[key] = out
	return out

## A copy of a template whose `Accent` surfaces take the per-instance colour (INSTANCE_CUSTOM):
## doorways and wall patches carry the room's category band (ART-HAB P4).
static func accent_tinted(tpl: Dictionary) -> Dictionary:
	var key: String = String(tpl["key"]) + ":accent"
	if _templates.has(key):
		return _templates[key]
	if _tint_shader == null:
		_tint_shader = load("res://shaders/tint.gdshader")
	var out: Dictionary = tpl.duplicate()
	out["key"] = key
	var parts: Array = []
	for p in tpl["parts"]:
		var q: Dictionary = p.duplicate()
		var mesh: Mesh = p["mesh"]
		var has := false
		for si in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(si)
			if m != null and m.resource_name == "Accent":
				has = true
		if has and mesh is ArrayMesh and not bool(p.get("shadow_only", false)):
			var copy: ArrayMesh = (mesh as ArrayMesh).duplicate()
			for si in copy.get_surface_count():
				var m2: Material = copy.surface_get_material(si)
				if m2 != null and m2.resource_name == "Accent" and m2 is BaseMaterial3D:
					var tm := ShaderMaterial.new()
					tm.shader = _tint_shader
					tm.resource_name = "AccentTint"
					tm.set_shader_parameter("albedo", Color(1, 1, 1))
					tm.set_shader_parameter("roughness", (m2 as BaseMaterial3D).roughness)
					tm.set_shader_parameter("metallic", (m2 as BaseMaterial3D).metallic)
					tm.set_shader_parameter("use_vc", (m2 as BaseMaterial3D).vertex_color_use_as_albedo)
					copy.surface_set_material(si, tm)
			q["mesh"] = copy
			q["custom"] = true
		parts.append(q)
	out["parts"] = parts
	_templates[key] = out
	return out

## A plain node tree built from a template (for one-off nodes: ghosts, construction sites).
## Children are named after their group; each group is its own Node3D.
## `proxies`: shadow proxies (one-surface SHADOWS_ONLY twins) are added and the proxied part
## casts no shadow. Without it the proxied part casts its own shadow again (ghosts and
## construction nodes replace the materials of every mesh, so they get no proxies).
static func node_from(tpl: Dictionary, proxies: bool = false) -> Node3D:
	var root := Node3D.new()
	var groups := {}
	var plist: Array = tpl["parts"]
	for pi in plist.size():
		var p: Dictionary = plist[pi]
		var so: bool = bool(p.get("shadow_only", false))
		if so and not proxies:
			continue
		var proxied: bool = pi + 1 < plist.size() and bool(plist[pi + 1].get("shadow_only", false))
		var g: String = p["group"]
		if not groups.has(g):
			var gn := Node3D.new()
			gn.name = g
			if g == "Rotor":
				gn.transform = p["pivot"]
			root.add_child(gn)
			groups[g] = gn
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.transform = p["local"] if g == "Rotor" else p["xf"]
		if so:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif proxied and not proxies:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(p["shadow"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(groups[g] as Node3D).add_child(mi)
	var s: float = float(tpl.get("scale", 1.0))
	if absf(s - 1.0) > 0.001:
		root.scale = Vector3(s, s, s)
	return root

## v1 entry point (main.gd uses it for its own placement ghost): a node tree for a def.
static func instantiate(id: String, radius: float = 3.0, kind: String = "room", category: String = "logistics") -> Node3D:
	var r: Dictionary = resolve(id, -1)
	if r["path"] == "":
		r = resolve(id, 1)
	if r["path"] != "":
		return node_from(_template_from_file(r["path"]))
	return _fallback_node(id, radius, kind, CATEGORY_COLOR.get(category, Color.GRAY))

# ---------------------------------------------------------------- materials
static func _prepare_mesh(mesh: Mesh) -> void:
	var mid: int = mesh.get_instance_id()
	if _prepared.has(mid):
		return
	_prepared[mid] = true
	if not (mesh is ArrayMesh):
		return
	for s in mesh.get_surface_count():
		var src: Material = mesh.surface_get_material(s)
		var has_col := false
		if mesh is ArrayMesh:
			has_col = ((mesh as ArrayMesh).surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0
		var m: Material = lib_material(src, has_col)
		if m != src and mesh is ArrayMesh:
			(mesh as ArrayMesh).surface_set_material(s, m)

## The shared library copy of an imported material.
static func lib_material(src: Material, has_col: bool) -> Material:
	if not (src is StandardMaterial3D):
		return src
	var sm: StandardMaterial3D = src
	var key := "%s|%s|%s|%.2f|%.2f|%s|%.2f|%d|%s" % [sm.resource_name, sm.albedo_color.to_html(), sm.emission.to_html(),
		sm.roughness, sm.metallic, str(sm.emission_enabled), sm.emission_energy_multiplier, sm.transparency, str(has_col)]
	if _lib.has(key):
		return _lib[key]
	var d: StandardMaterial3D = sm.duplicate()
	d.resource_name = sm.resource_name
	d.vertex_color_use_as_albedo = has_col
	d.vertex_color_is_srgb = false
	var n: String = sm.resource_name
	if n == "Glass":
		if d.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			d.albedo_color.a = minf(d.albedo_color.a, 0.38)
		d.roughness = minf(d.roughness, 0.12)
		d.metallic_specular = 0.9
	if d.emission_enabled:
		_night.append({"mat": d, "base": maxf(0.2, d.emission_energy_multiplier), "name": n})
	_lib[key] = d
	return d

## Windows and lamps: dim by day, bright at night. `f` 0 = full day, 1 = night.
static func set_night(f: float) -> void:
	if absf(f - _night_f) < 0.01:
		return
	_night_f = f
	for e in _night:
		if String(e["name"]) == "Glow" or String(e["name"]) == "Plasma":
			continue
		var k: float = _night_k(String(e["name"]), f)
		var m = e["mat"]
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).emission_energy_multiplier = float(e["base"]) * k
		elif m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter(String(e.get("param", "emission_energy")), float(e["base"]) * k)
	for e in _night_sm:
		(e["mat"] as ShaderMaterial).set_shader_parameter("emission_energy", float(e["base"]) * _night_k(String(e["name"]), f))
	var fill: float = lerpf(FILL_DAY, FILL_NIGHT, f)
	for m in _fill_mats:
		(m as ShaderMaterial).set_shader_parameter("fill", fill)

## Emission multiplier of a material family by night amount f (0 day .. 1 night).
## Interior strips and screens (V3 §7.3) are on day and night, a little brighter at night.
static func _night_k(n: String, f: float) -> float:
	match n:
		# The 3.0 rooms carry a continuous window band round the lower wall: at 1.55 it
		# bloomed to a white ring at night (2026-09-25). 0.75 keeps it warm and readable.
		"Window": return lerpf(0.18, 0.26, f)   # critic round 8: the band is no longer a white ring
		"Ember": return 1.0
		"Light": return lerpf(0.45, 2.1, f)
		"Neon": return lerpf(0.9, 1.7, f)
		"L3Band", "L4Band", "L5Gold": return lerpf(0.8, 1.6, f)
		# ART-HAB P8: no night boost for strips and screens (screens blew out).
		"LightStrip", "Screen", "LightGreen", "LightAmber": return 1.0
	return lerpf(0.7, 1.6, f)

## A ShaderMaterial copy of `src` whose albedo is multiplied by INSTANCE_CUSTOM.rgb.
static func tint_material(src: Material) -> Material:
	if not (src is BaseMaterial3D):
		return src
	var id: int = src.get_instance_id()
	if _tint_mats.has(id):
		return _tint_mats[id]
	if _tint_shader == null:
		_tint_shader = load("res://shaders/tint.gdshader")
	var b: BaseMaterial3D = src
	var m := ShaderMaterial.new()
	m.shader = _tint_shader
	m.set_shader_parameter("albedo", b.albedo_color)
	m.set_shader_parameter("roughness", b.roughness)
	m.set_shader_parameter("metallic", b.metallic)
	m.set_shader_parameter("use_vc", b.vertex_color_use_as_albedo)
	m.set_shader_parameter("mode", 1 if src.resource_name == "Skin" else (2 if src.resource_name == "Hair" else 0))
	_tint_mats[id] = m
	return m

## Glowing cores pulse (fusion Plasma, algae Glow): one call per frame, a few materials.
static func animate(t: float) -> void:
	for e in _night:
		var n: String = e["name"]
		if n.length() > 3 and (n == "Plasma" or n == "Glow"):
			var k: float = (1.0 + 0.35 * sin(t * (2.6 if n == "Plasma" else 1.1))) * (lerpf(1.0, 1.4, maxf(_night_f, 0.0)))
			(e["mat"] as StandardMaterial3D).emission_energy_multiplier = float(e["base"]) * k

static func flat_material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s:%.2f" % [color.to_html(), emission]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.75
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if emission > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = emission
		_mats[key] = m
	return _mats[key]

static func ghost_material(color: Color) -> StandardMaterial3D:
	var key := "ghost:" + color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]

static func _mat(color: Color, name: String, rough: float = 0.7, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	var key := "prim:%s:%s:%.2f:%.2f:%.2f" % [name, color.to_html(), rough, metal, emit]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.resource_name = name
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = emit
			_night.append({"mat": m, "base": emit, "name": name})
		_mats[key] = m
	return _mats[key]

# ---------------------------------------------------------------- primitive stand-ins
static func _mi(parent: Node3D, name: String, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _fallback_node(id: String, radius: float, kind: String, accent: Color) -> Node3D:
	var root := Node3D.new()
	var hull := _mat(Color("d9dde2"), "Hull", 0.55)
	var frame := _mat(Color("4a5058"), "Frame", 0.6, 0.3)
	var acc := _mat(accent, "Accent", 0.5)
	if id == "meridian":
		# Crashed colony ship: a 42 m capsule along X, tilted, nose half buried.
		var body := CapsuleMesh.new()
		body.radius = 6.0
		body.height = 40.0
		body.radial_segments = 24
		body.rings = 6
		_mi(root, "Hull", body, hull, Vector3(0, 3.2, 0), Vector3(0, 0, deg_to_rad(94.0)))
		var fin := BoxMesh.new()
		fin.size = Vector3(10, 0.8, 22)
		_mi(root, "Hull_Wing", fin, frame, Vector3(4, 2.0, 0))
		var d1 := BoxMesh.new()
		d1.size = Vector3(8, 3, 3)
		_mi(root, "Damage1", d1, _mat(Color("3a2c26"), "HullDark", 0.9), Vector3(-6, 7.5, 3), Vector3(0.3, 0.2, 0.4))
		var d2 := BoxMesh.new()
		d2.size = Vector3(4, 2, 5)
		_mi(root, "Damage2", d2, _mat(Color("2b2622"), "HullDark", 0.9), Vector3(8, 6.5, -4), Vector3(-0.3, 0.5, 0.2))
		var d3 := BoxMesh.new()
		d3.size = Vector3(3, 3, 3)
		_mi(root, "Damage3", d3, _mat(Color("2b2622"), "HullDark", 0.9), Vector3(18, 4, 0), Vector3(0.6, 0.1, 0.3))
		var sc := BoxMesh.new()
		sc.size = Vector3(30, 10, 15)
		_mi(root, "Scaffold", sc, _mat(Color(0.95, 0.7, 0.2, 0.25), "Hazard"), Vector3(0, 5, 0))
		var lt := BoxMesh.new()
		lt.size = Vector3(20, 0.3, 0.3)
		_mi(root, "Lights", lt, _mat(Color("ffd27a"), "Window", 0.4, 0.0, 2.0), Vector3(0, 5.5, 5.8))
		var eg := CylinderMesh.new()
		eg.top_radius = 1.6
		eg.bottom_radius = 1.6
		eg.height = 0.4
		_mi(root, "EngineGlow", eg, _mat(Color("8fd8ff"), "Plasma", 0.3, 0.0, 5.0), Vector3(21.5, 3.2, 0), Vector3(0, 0, deg_to_rad(90)))
		for sgn in [-1.0, 1.0]:
			var an := Node3D.new()
			an.name = "Anchor_Engine_L" if sgn < 0 else "Anchor_Engine_R"
			an.position = Vector3(22.0, 3.2, 2.2 * sgn)
			root.add_child(an)
		var ramp := Node3D.new()
		ramp.name = "Anchor_Ramp"
		ramp.position = Vector3(0, 0.5, 7.5)
		root.add_child(ramp)
		return root
	if id == "supply_pod" or id == "pod":
		var pod := CapsuleMesh.new()
		pod.radius = 0.7
		pod.height = 2.2
		_mi(root, "Base", pod, hull, Vector3(0, 1.0, 0))
		var band := CylinderMesh.new()
		band.top_radius = 0.74
		band.bottom_radius = 0.74
		band.height = 0.25
		_mi(root, "Base_Band", band, _mat(Color("ffb547"), "Hazard", 0.5), Vector3(0, 1.1, 0))
		var beacon := SphereMesh.new()
		beacon.radius = 0.12
		beacon.height = 0.24
		_mi(root, "Lights", beacon, _mat(Color("ff5a5f"), "Light", 0.3, 0.0, 3.0), Vector3(0, 2.15, 0))
		return root
	if id.begins_with("crop"):
		for st in 3:
			var h: float = [0.12, 0.35, 0.7][st]
			var bm := BoxMesh.new()
			bm.size = Vector3(2.7, h, 1.1)
			_mi(root, "Stage%d" % (st + 1), bm, _mat(Color("4caf50").darkened(0.15 * (2 - st)), "Plant", 0.8), Vector3(0, h * 0.5, 0))
		return root
	if id.begins_with("colonist"):
		var suit := _mat(Color("e8eaed"), "SuitMain", 0.6)
		var acc2 := _mat(Color("ff9f1c"), "SuitAccent", 0.6)
		var body := CapsuleMesh.new()
		body.radius = 0.25
		body.height = 0.95
		_mi(root, "Body", body, suit, Vector3(0, 1.3, 0))
		var head := SphereMesh.new()
		head.radius = 0.2
		head.height = 0.4
		_mi(root, "Body_Head", head, acc2, Vector3(0, 1.85, 0))
		for side in [["L", -1.0], ["R", 1.0]]:
			var leg := Node3D.new()
			leg.name = "Leg" + side[0]
			leg.position = Vector3(0, 0.86, 0.12 * side[1])
			root.add_child(leg)
			var lm := CapsuleMesh.new()
			lm.radius = 0.1
			lm.height = 0.86
			_mi(leg, "Mesh", lm, suit, Vector3(0, -0.43, 0))
			var arm := Node3D.new()
			arm.name = "Arm" + side[0]
			arm.position = Vector3(0, 1.34, 0.31 * side[1])
			root.add_child(arm)
			var am := CapsuleMesh.new()
			am.radius = 0.08
			am.height = 0.7
			_mi(arm, "Mesh", am, acc2, Vector3(0, -0.3, 0))
		return root
	if id == "crate":
		var bx := BoxMesh.new()
		bx.size = Vector3(0.45, 0.45, 0.45)
		_mi(root, "Base", bx, _mat(Color("c07a3a"), "Cargo", 0.7), Vector3(0, 0.225, 0))
		return root
	if kind == "exterior" or kind == "special":
		var box := BoxMesh.new()
		box.size = Vector3(radius * 1.3, 1.6, radius * 1.3)
		_mi(root, "Base", box, _mat(accent.lerp(Color.WHITE, 0.4), "Hull", 0.6), Vector3(0, 0.8, 0))
		var strip := BoxMesh.new()
		strip.size = Vector3(radius * 1.32, 0.2, radius * 1.32)
		_mi(root, "Base_Trim", strip, acc, Vector3(0, 1.3, 0))
		return root
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.96
	cyl.bottom_radius = radius * 0.98
	cyl.height = 1.4
	cyl.radial_segments = 32
	_mi(root, "Base", cyl, hull, Vector3(0, 0.7, 0))
	var ring := CylinderMesh.new()
	ring.top_radius = radius
	ring.bottom_radius = radius
	ring.height = 0.25
	ring.radial_segments = 32
	_mi(root, "Base_Ring", ring, acc, Vector3(0, 1.15, 0))
	var dome := SphereMesh.new()
	dome.radius = radius * 0.96
	dome.height = radius * 0.9
	dome.is_hemisphere = true
	dome.radial_segments = 32
	dome.rings = 8
	_mi(root, "Roof", dome, _mat(accent.lerp(Color.WHITE, 0.55), "Hull", 0.5), Vector3(0, 1.4, 0))
	var floor_m := CylinderMesh.new()
	floor_m.top_radius = radius * 0.9
	floor_m.bottom_radius = radius * 0.9
	floor_m.height = 0.1
	_mi(root, "Interior", floor_m, frame, Vector3(0, 0.2, 0))
	return root

# ---------------------------------------------------------------- v1 helpers (still used)
## Every MeshInstance3D below `node`.
static func meshes(node: Node) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

static func set_override(node: Node, mat: Material) -> void:
	for m in meshes(node):
		(m as MeshInstance3D).material_override = mat

## Replaces every surface whose material is called `mat_name` with a tinted copy.
static func tint_named(node: Node, mat_name: String, color: Color) -> void:
	for mi in meshes(node):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src: Material = mesh.surface_get_material(s)
			if src != null and src.resource_name == mat_name and src is BaseMaterial3D:
				var key := "tint:%s:%s:%d" % [mat_name, color.to_html(), src.get_instance_id()]
				if not _mats.has(key):
					var copy: BaseMaterial3D = src.duplicate()
					copy.albedo_color = color
					_mats[key] = copy
				(mi as MeshInstance3D).set_surface_override_material(s, _mats[key])
