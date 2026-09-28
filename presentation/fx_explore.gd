extends Node3D
## Exploration on screen (RENDER, V4_DESIGN §5; SIM milestone 7, sim/explore.gd):
## - points of interest: once `found`, each kind has a look on the ground (wreck, derelict probe,
##   meteorite field, cave, anomaly, rich deposit), a dashed ring in its colour and a light pillar
##   that fades when the POI is `visited`. The moment it is found: a pulse and a ring that runs out.
## - satellites (sim.explore.sats()): in orbit at 420 m over the band being mapped, moving west to
##   east in step with SIM's band timer, a scan line on the ground across the band.
## - a launch from the pad (log `satellite_launched`): arms clear, ignition, lift-off (the pad's
##   own model plays it; the instanced pad is hidden meanwhile).
## Nothing is written to sim.state.

const Models = preload("res://presentation/models.gd")
const KIND_COL := {"wreck": Color(1.0, 0.62, 0.3), "derelict_probe": Color(0.4, 0.85, 1.0), "meteorite_field": Color(0.95, 0.45, 0.35),
	"cave": Color(0.7, 0.55, 1.0), "anomaly": Color(1.0, 0.4, 0.95), "rich_deposit": Color(1.0, 0.82, 0.3)}
const ORBIT_H := 420.0
const POI_MODEL := {"wreck": "poi_wreck", "derelict_probe": "poi_probe", "cave": "poi_cave", "meteorite_field": "poi_meteorites", "anomaly": "poi_anomaly"}

var view
var sim
var pois := {}          # poi id -> {nodes: [], handles: [], ring, pillar, found_t, visited}
var sats := {}          # sat id -> {node, beam, line}
var _launch := {}       # pad id -> {node, t}
var _log_tick := -1
var _first := true
var _beam_mat: StandardMaterial3D
var stats := {"pois": 0, "sats": 0}

func setup(v) -> void:
	view = v
	sim = v.sim

func _ex():
	var ex = sim.get("explore")
	if ex == null or not (ex as Object).has_method("active") or not ex.active():
		return null
	return ex

func sync(delta: float) -> void:
	var ex = _ex()
	if ex == null:
		return
	_sync_pois(ex, delta)
	_sync_sats(ex, delta)
	_sync_launch(delta)
	_first = false

# ---------------------------------------------------------------- points of interest
func _sync_pois(ex, delta: float) -> void:
	var night: float = float(view.sky.night) if view.sky != null else 0.0
	for p in ex.pois():
		if not bool(p.get("found", false)):
			continue
		var id: int = int(p["id"])
		if not pois.has(id):
			pois[id] = _make_poi(p)
			if not _first:
				_discover(pois[id])
		var e: Dictionary = pois[id]
		var visited: bool = bool(p.get("visited", false))
		e["age"] = float(e.get("age", 99.0)) + delta
		var col: Color = KIND_COL.get(String(p["kind"]), Color(1, 1, 1))
		var ring: MeshInstance3D = e["ring"]
		ring.set_instance_shader_parameter("icolor", Color(1, 1, 1, 0.45) if visited else Color(1, 1, 1, 1))
		var pil: MeshInstance3D = e["pillar"]
		pil.visible = not visited
		if not visited:
			var k: float = 0.6 + 0.4 * sin(float(view._time) * 1.7 + float(id))
			(pil.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, (0.22 + 0.25 * night) * k)
		# The found moment: a ring that runs out to 60 m in 2 s.
		var rr = e.get("reveal")
		if rr != null:
			var u: float = clampf(float(e["age"]) / 2.0, 0.0, 1.0)
			(rr as MeshInstance3D).scale = Vector3(lerpf(4.0, 60.0, u), 1, lerpf(4.0, 60.0, u))
			(rr as MeshInstance3D).set_instance_shader_parameter("icolor", Color(1, 1, 1, 1.0 - u))
			if u >= 1.0:
				(rr as Node).queue_free()
				e.erase("reveal")
		if e.has("lab"):
			(e["lab"] as Label3D).visible = view.labels_visible and float(view.camera_distance) < 260.0
	stats["pois"] = pois.size()

func _make_poi(p: Dictionary) -> Dictionary:
	var kind: String = String(p["kind"])
	var c := Vector2(float(p["x"]), float(p["y"]))
	var y: float = view.h(c.x, c.y)
	var col: Color = KIND_COL.get(kind, Color(1, 1, 1))
	var e := {"handles": [], "age": 99.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["id"]) * 7919 + 3
	var add := func(ids: Array, pos: Vector2, s: float, yaw: float, tilt: float, sink: float):
		var tpl: Dictionary = Models.prop(ids, s)
		var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), tilt), Vector3(pos.x, view.h(pos.x, pos.y) - sink, pos.y)).scaled_local(Vector3(s, s, s))
		(e["handles"] as Array).append(view.inst.add(tpl, xf))
	# Critic round 22: a readable model or mark 6-12 m across. ART-HAB's poi_* models when present
	# (authored at size), else the procedural look below; a ground mark under every POI.
	var mark: MeshInstance3D = view.decal_ring(1.0, 0.001, 48, Color(col.r, col.g, col.b, 0.75) if kind == "anomaly" else Color(0.07, 0.05, 0.04, 0.85), 9 if kind == "anomaly" else 5)
	mark.position = Vector3(c.x, y, c.y)
	mark.scale = Vector3(6.0, 1, 6.0)
	add_child(mark)
	e["mark"] = mark
	var art: String = String(POI_MODEL.get(kind, ""))
	if art != "" and Models.has_model(art):
		var ayaw: float = rng.randf() * TAU
		if kind == "cave":
			# The cave mouth is the model's +X (ART-HAB): turn it toward the approach, the nearest base
			# (lander or outpost core).
			var home := Vector2(-1, -1)
			for b in sim.state["buildings"].values():
				if String(b["def"]) in ["lander", "outpost_core"]:
					var bp: Vector2 = b["pos"]
					if home.x < 0.0 or bp.distance_to(c) < home.distance_to(c):
						home = bp
			if home.x >= 0.0:
				var dv: Vector2 = (home - c).normalized()
				ayaw = atan2(-dv.y, dv.x)
		# On a slope the model stands on the highest ground under its 10 m footprint (not buried).
		var hi: float = y
		for k in 8:
			var aa: float = TAU * float(k) / 8.0
			hi = maxf(hi, view.h(c.x + cos(aa) * 4.0, c.y + sin(aa) * 4.0))
		add.call([art], c, 1.0, ayaw, 0.0, -(hi - y) * 0.7)
		kind = "art"
	match kind:
		"art":
			pass
		"wreck":
			add.call(["ship_courier", "ship_trader"], c, 0.8, rng.randf() * TAU, deg_to_rad(18.0), 1.6)
			for k in 7:
				var q: Vector2 = c + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14))
				add.call(["fragments", "rock_c"], q, rng.randf_range(0.5, 1.1), rng.randf() * TAU, 0.0, 0.1)
		"derelict_probe":
			add.call(["satellite"], c, 2.6, rng.randf() * TAU, deg_to_rad(35.0), 1.2)
			for k in 5:
				var qp: Vector2 = c + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
				add.call(["fragments", "rock_c"], qp, rng.randf_range(0.5, 0.9), rng.randf() * TAU, 0.0, 0.1)
		"meteorite_field":
			for k in 9:
				var q2: Vector2 = c + Vector2(rng.randf_range(-22, 22), rng.randf_range(-22, 22))
				add.call(["meteor_rock", "rock_b"], q2, rng.randf_range(0.8, 2.2), rng.randf() * TAU, 0.0, 0.2)
				var sc: MeshInstance3D = view.decal_ring(1.0, 0.001, 32, Color(0.08, 0.06, 0.05, 0.8), 5)
				sc.position = Vector3(q2.x, view.h(q2.x, q2.y), q2.y)
				sc.scale = Vector3(3.5, 1, 3.5)
				add_child(sc)
		"cave":
			var mouth: MeshInstance3D = view.decal_ring(1.0, 0.001, 32, Color(0.02, 0.02, 0.03, 0.95), 5)
			mouth.position = Vector3(c.x, y, c.y)
			mouth.scale = Vector3(7.0, 1, 7.0)
			add_child(mouth)
			for k in 5:
				var a: float = TAU * float(k) / 5.0
				add.call(["boulder_a", "rock_a"], c + Vector2(cos(a), sin(a)) * 7.5, rng.randf_range(1.6, 3.0), a, 0.0, 0.3)
		"anomaly":
			add.call(["fragments", "meteor_rock"], c, 3.4, 0.0, 0.0, 0.3)
			for k in 4:
				var a2: float = TAU * float(k) / 4.0 + 0.4
				add.call(["rock_f", "meteor_rock"], c + Vector2(cos(a2), sin(a2)) * 4.5, 1.6, a2, deg_to_rad(20.0), 0.4)
			view.fx.emitter_set("poi_%d" % int(p["id"]), "pulse", Vector3(c.x, y + 1.5, c.y), 1.0)
		"rich_deposit":
			for k in 8:
				var q3: Vector2 = c + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
				add.call(["rock_f", "rock_a"], q3, rng.randf_range(0.6, 1.4), rng.randf() * TAU, 0.0, 0.2)
	var ring: MeshInstance3D = view.decal_ring(1.0, 0.9, 96, Color(col.r, col.g, col.b, 0.9), 1, 36.0, 0.2)
	ring.position = Vector3(c.x, y, c.y)
	ring.scale = Vector3(24.0, 1, 24.0)
	add_child(ring)
	e["ring"] = ring
	# A light pillar: readable from the overview camera.
	var pil := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 1.4
	cm.height = 60.0
	cm.radial_segments = 8
	cm.cap_top = false
	cm.cap_bottom = false
	pil.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, 0.3)
	pil.material_override = m
	pil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pil.position = Vector3(c.x, y + 30.0, c.y)
	add_child(pil)
	e["pillar"] = pil
	var lab := Label3D.new()
	lab.text = String(sim.explore.poi_name(p)) if (sim.explore as Object).has_method("poi_name") else kind
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.fixed_size = true
	lab.pixel_size = 0.0008
	lab.font_size = 22
	lab.outline_size = 6
	lab.modulate = Color(col.r, col.g, col.b, 0.95)
	lab.position = Vector3(c.x, y + 8.0, c.y)
	add_child(lab)
	e["lab"] = lab
	e["pos"] = Vector3(c.x, y, c.y)
	return e

## The moment a POI is found: a pulse at it and a ring that runs out.
func _discover(e: Dictionary) -> void:
	e["age"] = 0.0
	var p3: Vector3 = e["pos"]
	var rr: MeshInstance3D = view.decal_ring(1.0, 0.94, 96, Color(1, 1, 1, 1), 0)
	rr.position = p3
	add_child(rr)
	e["reveal"] = rr
	view.fx.burst("pulse", p3 + Vector3(0, 2, 0), 3)
	view.world_sound("poi_found", p3)

# ---------------------------------------------------------------- satellites
func _sync_sats(ex, _delta: float) -> void:
	if not (ex as Object).has_method("sats"):
		return
	var cfg: Dictionary = sim.content.get("terrain_v4", {}).get("explore", {})
	var band_s: float = float(cfg.get("band_s", 60.0))
	var nb: int = int(cfg.get("bands", 16))
	var size: float = float(sim.world.size)
	var seen := {}
	for s in ex.sats():
		var id: int = int(s["id"])
		seen[id] = true
		if not sats.has(id):
			sats[id] = _make_sat()
		var e: Dictionary = sats[id]
		var band: int = int(s.get("band", 0))
		var done: bool = int(s.get("bands_done", s.get("bands", 0))) >= nb
		var u: float = clampf(1.0 - float(s.get("next_s", band_s)) / band_s, 0.0, 1.0)
		var z: float = (float(band) + 0.5) * size / float(nb)
		var x: float = u * size
		if done:
			# Mapping finished: it keeps orbiting high over the map, no scan line.
			x = fposmod(float(view._time) * 30.0, size)
			z = size * 0.5
		var node: Node3D = e["node"]
		node.global_transform = Transform3D(Basis().scaled(Vector3(3.0, 3.0, 3.0)), Vector3(x, ORBIT_H, z))
		var ground: float = view.h(clampf(x, 0.0, size), clampf(z, 0.0, size))
		var beam: MeshInstance3D = e["beam"]
		# Critic round 23: no beam and no square frame; a soft light band slides along the strip.
		beam.visible = false
		beam.global_transform = Transform3D(Basis().scaled(Vector3(1.0, (ORBIT_H - ground), 1.0)), Vector3(x, (ORBIT_H + ground) * 0.5, z))
		var line: MeshInstance3D = e["line"]
		line.visible = not done and bool(s.get("uplink", true))
		line.position = Vector3(x, ground, z)
		line.scale = Vector3(size / float(nb) * 0.35, 1, size / float(nb) * 0.55)
	for id in sats.keys():
		if not seen.has(id):
			for k in ["node", "beam", "line"]:
				(sats[id][k] as Node).queue_free()
			sats.erase(id)
	stats["sats"] = sats.size()

func _make_sat() -> Dictionary:
	var ps: PackedScene = load("res://assets/models/satellite.glb") if ResourceLoader.exists("res://assets/models/satellite.glb") else null
	var node: Node3D = ps.instantiate() if ps != null else Node3D.new()
	add_child(node)
	# At 420 m the model is a few pixels: a soft beacon glow (billboard) marks it in the sky.
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(9.0, 9.0)
	glow.mesh = q
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.no_depth_test = false
	gm.albedo_color = Color(0.7, 0.92, 1.0, 0.9)
	gm.albedo_texture = _glow_tex()
	glow.material_override = gm
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.name = "BeaconGlow"
	node.add_child(glow)
	if _beam_mat == null:
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mat.albedo_color = Color(0.35, 0.85, 1.0, 0.12)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 9.0
	cm.height = 1.0
	cm.radial_segments = 12
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	# The scan line: a flowing band across the strip being mapped (north-south at the satellite).
	var line: MeshInstance3D = view.decal_ring(1.0, 0.001, 48, Color(0.62, 0.92, 1.0, 0.55), 9)
	add_child(line)
	return {"node": node, "beam": beam, "line": line}

## Load warm-up (world_view._night_warmup): a satellite with its glow, beam and scan line at xf.
## The beam first entered the camera mid-game and its new material cost a 83-150 ms web frame
## (showcase_v4 WebGL trace 2026-09-28: 5 program links at g7347).
func warm_nodes(xf: Transform3D) -> Array:
	var e: Dictionary = _make_sat()
	var out: Array = []
	for k in ["node", "beam", "line"]:
		var nd: Node3D = e[k]
		nd.global_transform = xf
		out.append(nd)
	return out

var _glow: Texture2D
func _glow_tex() -> Texture2D:
	if _glow == null:
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		g.width = 64
		g.height = 64
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.18, Color(1, 1, 1, 0.55))
		g.gradient = gr
		_glow = g
	return _glow

# ---------------------------------------------------------------- launch
func _sync_launch(delta: float) -> void:
	var log: Array = sim.state.get("log", [])
	var last: int = _log_tick
	for i in range(log.size() - 1, -1, -1):
		var e: Dictionary = log[i]
		if int(e["tick"]) <= _log_tick:
			break
		last = maxi(last, int(e["tick"]))
		if String(e["code"]) == "satellite_launched" and _log_tick >= 0:
			var ents: Array = e.get("ents", [])
			if not ents.is_empty():
				_start_launch(int(ents[0]))
	_log_tick = last if _log_tick >= 0 or log.is_empty() else int(log[-1]["tick"])
	for pid in _launch.keys():
		var L: Dictionary = _launch[pid]
		L["t"] = float(L["t"]) + delta
		if float(L["t"]) > 40.0:
			view.vehicles.remove(int(L["vid"]))
			if view.bmeta.has(pid):
				for g in (view.bmeta[pid]["tpl"].get("groups", {}) as Dictionary):
					view.inst.set_hidden(int(view.bmeta[pid]["h"]), g, false)
			_launch.erase(pid)

## The pad's own model plays the launch (fx_vehicles' launch pad), the instanced pad hidden.
func _start_launch(pid: int) -> void:
	if _launch.has(pid) or not view.bmeta.has(pid):
		return
	var meta: Dictionary = view.bmeta[pid]
	var vid: int = view.vehicles.add("launch_pad", meta["xf"])
	if vid < 0:
		return
	for g in (meta["tpl"].get("groups", {}) as Dictionary):
		view.inst.set_hidden(int(meta["h"]), g, true)
	view.vehicles.launch(vid)
	_launch[pid] = {"vid": vid, "t": 0.0}

## Debug / evidence: play a launch on pad `pid` now.
func test_launch(pid: int) -> String:
	_start_launch(pid)
	return "launch %s" % str(_launch.has(pid))
