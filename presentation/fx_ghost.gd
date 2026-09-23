extends Node3D
## Placement ghost and link preview (RENDER, §12 set_ghost / clear_ghost / set_link_preview).
## The ghost is the real model drawn with the hologram shader (green = can place, red =
## cannot), a footprint ring on the ground, the airlock door strip and, while placing,
## a dashed suit-range ring around every airlock that has air.

const Models = preload("res://presentation/models.gd")

const OK_COL := Color(0.36, 1.0, 0.55)
const BAD_COL := Color(1.0, 0.34, 0.28)
const RANGE_COL := Color(0.24, 0.88, 1.0)

var view
var node: Node3D
var node_key := ""
var ring: MeshInstance3D
var door: MeshInstance3D
var range_rings: Array = []
var _range_sig := ""
var link_node: Node3D
var link_key := ""
var link_strip: MeshInstance3D
var _valid := true
var _range_clock := 0.0

func setup(v) -> void:
	view = v
	ring = view.decal_ring(1.0, 0.9, 96, OK_COL, 0)
	ring.visible = false
	add_child(ring)
	door = MeshInstance3D.new()
	door.visible = false
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(door)

func _radius_for(def: Dictionary, size: int) -> float:
	if def.has("sizes") and (def["sizes"] as Dictionary).has("radius"):
		var arr: Array = def["sizes"]["radius"]
		return float(arr[clampi(size, 0, arr.size() - 1)])
	return float(def.get("radius", 3.0))

func set_ghost(def_id: String, size: int, pos: Vector2, rot: float, valid: bool) -> void:
	var sim = view.sim
	if not sim.content["buildings"].has(def_id):
		clear()
		return
	var def: Dictionary = sim.bdef(def_id)
	var r: float = _radius_for(def, size)
	var key := "%s:%d" % [def_id, size]
	if key != node_key or node == null:
		node_key = key
		if node != null:
			node.queue_free()
		var sz: int = size if def.has("sizes") else -1
		var tpl: Dictionary = Models.building(def_id, sz, r, float(def.get("radius", r)), def["kind"], def.get("category", "logistics"))
		node = Models.node_from(tpl)
		for g in ["Interior", "Lights", "Scaffold", "L2", "L3", "L4", "L5", "Damage1", "Damage2", "Damage3"]:
			var gn = node.find_child(g, false, false)
			if gn != null:
				(gn as Node3D).visible = false
		add_child(node)
		_valid = not valid
		# Door strip for airlocks: the side the corridor-free door faces.
		if bool(def.get("airlock", false)):
			var length: float = float(sim.bal.get("door_strip_length", 3.5))
			var half: float = float(sim.bal.get("door_strip_half_width", 1.6))
			door.mesh = view.strip_mesh(length, half * 2.0)
			door.set_meta("offset", r)
			door.visible = true
		else:
			door.visible = false
	if valid != _valid:
		_valid = valid
		var col: Color = OK_COL if valid else BAD_COL
		var hm: ShaderMaterial = view.holo_material(col, 1.25)
		for mi in Models.meshes(node):
			(mi as MeshInstance3D).material_override = hm
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.material_override = view.decal_material(col, 0)
		door.material_override = view.decal_material(col, 2, 48.0, 1.2, 0.1)
	var base: Vector3 = view.to3(pos, 0.04)
	node.visible = true
	node.position = base
	node.rotation = Vector3(0, -rot, 0)
	ring.visible = true
	ring.position = Vector3(pos.x, 0, pos.y)
	ring.scale = Vector3(r + 0.25, 1, r + 0.25)
	if door.visible:
		var dirv := Vector2(cos(rot), sin(rot))
		var start: Vector2 = pos + dirv * float(door.get_meta("offset", r))
		door.position = Vector3(start.x, 0, start.y)
		door.rotation = Vector3(0, -rot, 0)
	_update_ranges()

func _update_ranges() -> void:
	var sim = view.sim
	var reach: float = sim.agents.suit_reach_metres() / 1.25
	var centers: Array = []
	for comp in sim.topo.locks_by_comp:
		if not sim.util.comp_supplied(comp):
			continue
		for lid in sim.topo.locks_by_comp[comp]:
			if sim.state["buildings"].has(lid):
				centers.append(sim.nav.door_pos(sim.state["buildings"][lid]))
	var sig := "%.1f|" % reach
	for c in centers:
		sig += "%.1f,%.1f;" % [c.x, c.y]
	if sig == _range_sig:
		for rr in range_rings:
			(rr as MeshInstance3D).visible = true
		return
	_range_sig = sig
	for rr in range_rings:
		(rr as MeshInstance3D).queue_free()
	range_rings = []
	for c in centers:
		var rr: MeshInstance3D = view.decal_ring(reach, 0.985, 160, RANGE_COL, 1, 90.0, 0.25)
		rr.position = Vector3(c.x, 0, c.y)
		add_child(rr)
		range_rings.append(rr)
		var fill: MeshInstance3D = view.decal_ring(reach, 0.0, 96, Color(RANGE_COL, 0.12), 3)
		fill.position = Vector3(c.x, 0, c.y)
		add_child(fill)
		range_rings.append(fill)

func clear() -> void:
	if node != null:
		node.visible = false
	ring.visible = false
	door.visible = false
	for rr in range_rings:
		(rr as MeshInstance3D).visible = false

## Corridor or cable preview between two sim points. p0 == null hides it.
func set_link(p0, p1, kind: String, valid: bool) -> void:
	if p0 == null or p1 == null:
		if link_node != null:
			link_node.visible = false
		if link_strip != null:
			link_strip.visible = false
		return
	var a: Vector2 = p0
	var b: Vector2 = p1
	var length: float = a.distance_to(b)
	if length < 0.2:
		set_link(null, null, kind, valid)
		return
	var col: Color = OK_COL if valid else BAD_COL
	if link_strip == null:
		link_strip = MeshInstance3D.new()
		link_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(link_strip)
	var width: float = 2.6 if kind == "corridor" else 0.7
	link_strip.mesh = view.strip_mesh(length, width)
	link_strip.material_override = view.decal_material(col, 2, 48.0, 1.5, 0.1)
	link_strip.position = Vector3(a.x, 0, a.y)
	link_strip.rotation = Vector3(0, -(b - a).angle(), 0)
	link_strip.visible = true
	if kind != "corridor":
		if link_node != null:
			link_node.visible = false
		return
	if link_key != "corridor" or link_node == null:
		link_key = "corridor"
		if link_node != null:
			link_node.queue_free()
		link_node = Models.node_from(Models.prop(["corridor"], 1.2, "room", "logistics"))
		add_child(link_node)
	var hm: ShaderMaterial = view.holo_material(col, 1.25)
	for mi in Models.meshes(link_node):
		(mi as MeshInstance3D).material_override = hm
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y0: float = view.h(a.x, a.y)
	var y1: float = view.h(b.x, b.y)
	var basis := Basis(Vector3.UP, -(b - a).angle()) * Basis(Vector3(0, 0, 1), atan2(y1 - y0, length))
	link_node.transform = Transform3D(basis * Basis.from_scale(Vector3(length, 1, 1)), Vector3((a.x + b.x) * 0.5, (y0 + y1) * 0.5 + 0.05, (a.y + b.y) * 0.5))
	link_node.visible = true
