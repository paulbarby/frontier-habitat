extends Node3D
## Network overlays (RENDER): power, water and air. Every network gets one colour. Links
## that carry it become flowing lines on the ground; every structure on it gets a ring;
## a structure that is not joined gets a red dashed ring. One label per network gives
## its numbers. The walk overlay is drawn by the terrain shader (fx_terrain).

const PALETTE := [Color("3ee0ff"), Color("ffb547"), Color("5ee07a"), Color("a78bfa"), Color("f08fc0"), Color("ffd166"), Color("29b6c6"), Color("e07a3a")]
const Models = preload("res://presentation/models.gd")

var view
var mode := ""
var _nodes: Array = []
var _rev := -1
var _labels := {}      # comp -> Label3D
var _clock := 0.0

func setup(v) -> void:
	view = v

func set_mode(name: String) -> void:
	if name == mode:
		return
	mode = name
	_rev = -1
	_clear()

func _clear() -> void:
	for n in _nodes:
		(n as Node).queue_free()
	_nodes = []
	for c in _labels:
		(_labels[c] as Node).queue_free()
	_labels = {}

func sync(delta: float) -> void:
	if mode == "":
		return
	var sim = view.sim
	var rev: int = int(sim.state["rev"].get("power", 0)) * 1000 + int(sim.state["rev"].get("atmo", 0)) * 7 + sim.state["buildings"].size()
	if rev != _rev:
		_rev = rev
		_rebuild()
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.5
		_update_labels()

func _comp_data() -> Array:
	var sim = view.sim
	if mode == "air":
		return [sim.topo.atmo_comp, sim.topo.atmo_members]
	return [sim.topo.power_comp, sim.topo.power_members]

func _rebuild() -> void:
	_clear()
	var sim = view.sim
	var cd: Array = _comp_data()
	var comp_of: Dictionary = cd[0]
	var members: Dictionary = cd[1]
	var index := {}
	var n := 0
	for comp in members:
		index[comp] = n
		n += 1
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active":
			continue
		if b["kind"] == "link":
			if mode == "air" and b["def"] != "corridor":
				continue
			var ca = comp_of.get(b["a"], comp_of.get(b["b"], null))
			var col: Color = PALETTE[int(index[ca]) % PALETTE.size()] if ca != null and index.has(ca) else Color(0.6, 0.6, 0.6)
			var p0: Vector2 = b["p0"]
			var p1: Vector2 = b["p1"]
			var mi := MeshInstance3D.new()
			mi.mesh = view.strip_mesh(p0.distance_to(p1), 1.9 if b["def"] == "corridor" else 1.1)
			mi.material_override = view.decal_material(col, 2, 48.0, 1.4, 0.35 if b["def"] == "corridor" else 0.18)
			mi.position = Vector3(p0.x, 0, p0.y)
			mi.rotation = Vector3(0, -(p1 - p0).angle(), 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 16.0
			add_child(mi)
			_nodes.append(mi)
			continue
		if b["def"] == "meridian":
			continue
		if mode == "air" and b["kind"] == "exterior":
			continue
		var joined: bool = comp_of.has(id)
		var c: Color = PALETTE[int(index[comp_of[id]]) % PALETTE.size()] if joined and index.has(comp_of[id]) else Color(1.0, 0.35, 0.3)
		var ring: MeshInstance3D = view.decal_ring(float(b["radius"]) + 0.9, 0.9, 64, c, 0 if joined else 1, 32.0, 0.4)
		ring.position = Vector3(b["pos"].x, 0, b["pos"].y)
		add_child(ring)
		_nodes.append(ring)
	for comp in members:
		if not blds.has(comp):
			continue
		var lab := Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.fixed_size = true
		lab.pixel_size = 0.00095
		lab.font_size = 24
		lab.outline_size = 8
		lab.outline_modulate = Color(0.02, 0.04, 0.08, 0.92)
		lab.modulate = (PALETTE[int(index[comp]) % PALETTE.size()] as Color).lerp(Color.WHITE, 0.35)
		lab.render_priority = 12
		lab.position = view.to3(blds[comp]["pos"], 9.0)
		lab.set_meta("n", int(index[comp]) + 1)
		add_child(lab)
		_labels[comp] = lab
	_update_labels()

func _update_labels() -> void:
	var sim = view.sim
	for comp in _labels:
		var lab: Label3D = _labels[comp]
		var n: int = int(lab.get_meta("n", 1))
		var text := ""
		if mode == "power":
			var ps: Dictionary = sim.util.power_stats.get(comp, {})
			if not ps.is_empty():
				text = "POWER NET %d\nmake %.1f P   need %.1f P\nstored %.1f / %.0f E" % [n, sim.util.to_rate(ps["gen"]), sim.util.to_rate(ps["demand"]), sim.util.units(ps["stored"]), sim.util.units(ps["cap"])]
		elif mode == "water":
			var ws: Dictionary = sim.util.water_stats.get(comp, {})
			if not ws.is_empty():
				text = "WATER NET %d\nwater %.0f / %.0f\nin %.0f/day   out %.0f/day" % [n, sim.util.units(ws["stock"]), sim.util.units(ws["cap"]), sim.util.to_rate(ws["in"]), sim.util.to_rate(ws["out"])]
		else:
			var st: Dictionary = sim.util.atmo_stats.get(comp, {})
			if not st.is_empty():
				if bool(st.get("lander", false)):
					text = "LANDER AIR\n%d people   %s" % [st["people"], "ok" if bool(st["supplied"]) else "ENDED"]
				else:
					text = "AIR %d\noxygen %.1f / %.1f\nmake %.0f/day   breathe %.0f/day\n%d people" % [n, sim.util.units(st["stock"]), sim.util.units(st["cap"]), sim.util.to_rate(st["make"]), sim.util.to_rate(st["breathe"]), st["people"]]
		lab.text = text
		lab.visible = text != ""
