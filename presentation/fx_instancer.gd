extends Node3D
## Draws many copies of a model template with ONE MultiMesh per mesh part (RENDER).
## WebGL pays per draw call, not per triangle, so 150 structures and 60 colonists cost a
## few hundred draw calls instead of thousands. Each copy ("handle") has a transform,
## hidden groups, per-group extra transforms (roof lift, rotor spin, limb swing) applied
## at the group pivot, and a custom colour (INSTANCE_CUSTOM) for tinted surfaces.

const Models = preload("res://presentation/models.gd")

var batches := {}     # template key -> {tpl, parts: [{mm, mmi, part}], cap, used, free: []}
var handles := {}     # handle -> {key, slot, xf, hidden: {}, extra: {}, custom}
var _next := 1
var shadows := true
static var _tinted_meshes := {}

func add(tpl: Dictionary, xf: Transform3D, custom: Color = Color(1, 1, 1, 1)) -> int:
	var key: String = tpl["key"]
	if not batches.has(key):
		_new_batch(tpl)
	var bt: Dictionary = batches[key]
	var slot: int
	if not (bt["free"] as Array).is_empty():
		slot = (bt["free"] as Array).pop_back()
	else:
		slot = int(bt["used"])
		bt["used"] = slot + 1
		if slot >= int(bt["cap"]):
			_grow(bt, maxi(8, int(bt["cap"]) * 2))
		for p in bt["parts"]:
			(p["mm"] as MultiMesh).visible_instance_count = int(bt["used"])
	var h := _next
	_next += 1
	var s: float = float(tpl.get("scale", 1.0))
	handles[h] = {"key": key, "slot": slot, "xf": Transform3D(xf.basis * Basis.from_scale(Vector3(s, s, s)), xf.origin) if absf(s - 1.0) > 0.001 else xf,
		"hidden": {}, "extra": {}, "custom": custom, "scale": s, "gcustom": {}}
	(bt.get("slots") as Dictionary)[slot] = h
	for g in bt["vis"]:
		_vis_delta(bt, g, 1)
	_write(h)
	return h

func remove(h: int) -> void:
	if not handles.has(h):
		return
	var e: Dictionary = handles[h]
	var bt: Dictionary = batches[e["key"]]
	var slot: int = e["slot"]
	for p in bt["parts"]:
		(p["mm"] as MultiMesh).set_instance_transform(slot, _zero((e["xf"] as Transform3D).origin))
	(bt["slots"] as Dictionary).erase(slot)
	(bt["free"] as Array).append(slot)
	for g in bt["vis"]:
		if not (e["hidden"] as Dictionary).has(g):
			_vis_delta(bt, g, -1)
	handles.erase(h)

func has(h: int) -> bool:
	return handles.has(h)

func set_xf(h: int, xf: Transform3D) -> void:
	if not handles.has(h):
		return
	var e: Dictionary = handles[h]
	var s: float = e["scale"]
	e["xf"] = Transform3D(xf.basis * Basis.from_scale(Vector3(s, s, s)), xf.origin) if absf(s - 1.0) > 0.001 else xf
	_write_xf(h)

## One write for everything that changes every frame (colonists).
func set_all(h: int, xf: Transform3D, extra: Dictionary, hidden: Dictionary) -> void:
	if not handles.has(h):
		return
	var e: Dictionary = handles[h]
	var s: float = e["scale"]
	e["xf"] = Transform3D(xf.basis * Basis.from_scale(Vector3(s, s, s)), xf.origin) if absf(s - 1.0) > 0.001 else xf
	e["extra"] = extra
	if hidden != e["hidden"]:
		var bt: Dictionary = batches[e["key"]]
		for g in bt["vis"]:
			var was: bool = (e["hidden"] as Dictionary).has(g)
			var now: bool = hidden.has(g)
			if was != now:
				_vis_delta(bt, g, 1 if was else -1)
		e["hidden"] = hidden
	_write_xf(h)

func set_hidden(h: int, group: String, hide: bool) -> void:
	if not handles.has(h):
		return
	var e: Dictionary = handles[h]
	if bool((e["hidden"] as Dictionary).get(group, false)) == hide:
		return
	if hide:
		e["hidden"][group] = true
	else:
		(e["hidden"] as Dictionary).erase(group)
	var bt: Dictionary = batches[e["key"]]
	if (bt["vis"] as Dictionary).has(group):
		_vis_delta(bt, group, -1 if hide else 1)
	_write_group(h, group)

func set_extra(h: int, group: String, t: Transform3D) -> void:
	if not handles.has(h):
		return
	handles[h]["extra"][group] = t
	_write_group(h, group)

func clear_extra(h: int, group: String) -> void:
	if not handles.has(h):
		return
	if (handles[h]["extra"] as Dictionary).erase(group):
		_write_group(h, group)

func set_custom(h: int, c: Color) -> void:
	if not handles.has(h):
		return
	var e: Dictionary = handles[h]
	if e["custom"] == c:
		return
	e["custom"] = c
	var bt: Dictionary = batches[e["key"]]
	for p in bt["parts"]:
		var mm: MultiMesh = p["mm"]
		if mm.use_custom_data:
			mm.set_instance_custom_data(int(e["slot"]), _custom_of(e, p["part"]))

## Custom data of ONE group of a copy (the wall segment mask of a room, V3 §7.2).
func set_group_custom(h: int, group: String, c: Color) -> void:
	if not handles.has(h):
		return
	var e: Dictionary = handles[h]
	if (e["gcustom"] as Dictionary).get(group) == c:
		return
	e["gcustom"][group] = c
	var bt: Dictionary = batches[e["key"]]
	for p in bt["parts"]:
		if p["part"]["group"] == group and (p["mm"] as MultiMesh).use_custom_data:
			(p["mm"] as MultiMesh).set_instance_custom_data(int(e["slot"]), c)

func _custom_of(e: Dictionary, part: Dictionary) -> Color:
	var g: String = part["group"]
	if (e["gcustom"] as Dictionary).has(g):
		return e["gcustom"][g]
	if bool(part.get("mask", false)):
		return Color(0, 0, 0, 0)
	return e["custom"]

func set_shadows(on: bool) -> void:
	shadows = on
	for key in batches:
		for p in batches[key]["parts"]:
			(p["mmi"] as MultiMeshInstance3D).cast_shadow = _cast_of(p["part"])

## Shadow proxies (models.gd) are drawn only into the shadow map.
func _cast_of(part: Dictionary) -> int:
	if bool(part.get("shadow_only", false)):
		return GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows and bool(part["shadow"])) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## World transform of a group pivot for a handle (effects anchor on it).
func world_xf(h: int) -> Transform3D:
	if not handles.has(h):
		return Transform3D.IDENTITY
	return handles[h]["xf"]

func count() -> int:
	return handles.size()

func draw_parts() -> int:
	var n := 0
	for key in batches:
		n += (batches[key]["parts"] as Array).size()
	return n

# ---------------------------------------------------------------- internals
func _new_batch(tpl: Dictionary) -> void:
	var parts: Array = []
	var room_r := 0.0
	for part in tpl["parts"]:
		room_r = maxf(room_r, float(part.get("wall_r", 0.0)))
	for part in tpl["parts"]:
		var mesh: Mesh = part["mesh"]
		var tint := false
		for s in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(s)
			if m != null and m.resource_name in Models.TINTABLE:
				tint = true
		if tint:
			mesh = _tinted(mesh)
		var custom: bool = tint or bool(part.get("mask", false)) or bool(part.get("custom", false))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = custom
		# Compatibility renderer: custom data without instance colours reads COLOR as zero,
		# which blackens vertex-coloured (AO) albedo. Tinted parts carry white colours.
		mm.use_colors = custom
		mm.mesh = mesh
		mm.instance_count = 8
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = _cast_of(part)
		mmi.name = "%s_%s%s" % [String(tpl["key"]).get_file().get_basename(), part["group"], "_shadow" if bool(part.get("shadow_only", false)) else ""]
		add_child(mmi)
		# ART-HAB J4 wall fall-off: interior surfaces dim towards the wall ring (interior.gdshader).
		if room_r > 0.0 and _has_interior_mat(mesh) and not OS.get_cmdline_args().has("--no-room-r") and not JavaScriptBridge.eval("location.search.indexOf('noroomr')>=0", true):
			mmi.set_instance_shader_parameter("room_r", room_r)
		parts.append({"mm": mm, "mmi": mmi, "part": part})
	var vis := {}
	for p in parts:
		vis[p["part"]["group"]] = 0
	batches[tpl["key"]] = {"tpl": tpl, "parts": parts, "cap": 8, "used": 0, "free": [], "slots": {}, "vis": vis}
	for p in parts:
		(p["mmi"] as MultiMeshInstance3D).visible = false

static func _has_interior_mat(mesh: Mesh) -> bool:
	for s in mesh.get_surface_count():
		var m: Material = mesh.surface_get_material(s)
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.resource_path.ends_with("interior.gdshader"):
			return true
	return false

func _tinted(mesh: Mesh) -> Mesh:
	var id: int = mesh.get_instance_id()
	if _tinted_meshes.has(id):
		return _tinted_meshes[id]
	var copy: Mesh = mesh.duplicate()
	for s in copy.get_surface_count():
		var m: Material = copy.surface_get_material(s)
		if m != null and m.resource_name in Models.TINTABLE:
			copy.surface_set_material(s, Models.tint_material(m))
	_tinted_meshes[id] = copy
	return copy

func _grow(bt: Dictionary, cap: int) -> void:
	bt["cap"] = cap
	for p in bt["parts"]:
		var mm: MultiMesh = p["mm"]
		mm.instance_count = cap
		mm.visible_instance_count = int(bt["used"])
	# Rewrite every live instance (changing the count clears the buffer).
	var at := Vector3.ZERO
	for slot in bt["slots"]:
		_write(bt["slots"][slot])
		at = (handles[bt["slots"][slot]]["xf"] as Transform3D).origin
	for slot in bt["free"]:
		for p in bt["parts"]:
			(p["mm"] as MultiMesh).set_instance_transform(slot, _zero(at))

## A part whose group is hidden on every copy is not drawn at all (no empty draw call).
func _vis_delta(bt: Dictionary, group: String, d: int) -> void:
	var v: int = int(bt["vis"].get(group, 0)) + d
	bt["vis"][group] = v
	for p in bt["parts"]:
		if p["part"]["group"] == group:
			(p["mmi"] as MultiMeshInstance3D).visible = v > 0

func _zero(at: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), at)

func _part_xf(e: Dictionary, part: Dictionary) -> Transform3D:
	var g: String = part["group"]
	var xf: Transform3D = e["xf"]
	if (e["hidden"] as Dictionary).has(g):
		return _zero(xf.origin)
	var ex = (e["extra"] as Dictionary).get(g)
	if ex == null:
		return xf * (part["xf"] as Transform3D)
	return xf * (part["pivot"] as Transform3D) * (ex as Transform3D) * (part["local"] as Transform3D)

func _write(h: int) -> void:
	var e: Dictionary = handles[h]
	var bt: Dictionary = batches[e["key"]]
	var slot: int = e["slot"]
	for p in bt["parts"]:
		var mm: MultiMesh = p["mm"]
		mm.set_instance_transform(slot, _part_xf(e, p["part"]))
		if mm.use_custom_data:
			mm.set_instance_custom_data(slot, _custom_of(e, p["part"]))
			mm.set_instance_color(slot, Color(1, 1, 1, 1))

## Transforms only (custom colours do not change every frame).
func _write_xf(h: int) -> void:
	var e: Dictionary = handles[h]
	var bt: Dictionary = batches[e["key"]]
	var slot: int = e["slot"]
	for p in bt["parts"]:
		(p["mm"] as MultiMesh).set_instance_transform(slot, _part_xf(e, p["part"]))

func _write_group(h: int, group: String) -> void:
	var e: Dictionary = handles[h]
	var bt: Dictionary = batches[e["key"]]
	var slot: int = e["slot"]
	for p in bt["parts"]:
		if p["part"]["group"] == group:
			(p["mm"] as MultiMesh).set_instance_transform(slot, _part_xf(e, p["part"]))
