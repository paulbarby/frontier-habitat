extends Node3D
## Hazard visuals (RENDER, V3_DESIGN §4.5). Reads the simulation only (sim.hazards read API
## and state); never changes it. Every effect follows a real event:
##  meteor / meteor shower: target ring + countdown while forecast (cyan when a turret covers
##    it, red when not); a burning streak for the last 3 s; on impact a flash, a light, a
##    shockwave ring, fire, debris, dust, a scorch mark, a permanent crater in the terrain and a
##    smoke column; when a turret intercepts it, a tracer from the turret and an air burst.
##  wind storm: fast dust sheets, rotors spin up (state.env.wind_mult).
##  quake: camera shake (respects the "Camera shake" setting), dust puffs on every structure in
##    the radius, crack decals at the centre.
##  solar flare: aurora in the sky and a violet-green grade.
##  dust devil: a turning dust column that moves along its path (the path shows while forecast).
##  breach (rooms and corridors): a white air jet. Breakdowns: see world_view._status.

const Models = preload("res://presentation/models.gd")
const Rng = preload("res://sim/rng.gd")
const STREAK_SHADER = preload("res://shaders/streak.gdshader")
const DEVIL_SHADER = preload("res://shaders/dust_devil.gdshader")
const FLASH_SHADER = preload("res://shaders/flash_sprite.gdshader")
const METEOR_SPEED := 45.0            # m/s along the streak (slowed so the last seconds are on screen)
const LOCAL := ["meteor", "meteor_shower", "quake", "dust_devil"]

var view
var sim
var markers := {}                     # event id -> {nodes: [], label, kind}
var streaks := {}                     # key -> {node, mat, target, dir, eta, burst}
var watch := {}                       # meteor event id -> {pos, at, strikes_seen: {}}
var devils := {}                      # event id -> {node, mat}
var jets := {}                        # building id -> emitter key
var quakes := {}                      # event id -> seconds of shake left
var fading: Array = []                # [{node, t, life, kind, r0, r1, col}]
var flashes: Array = []               # [{light, t, life, e0}]
var crater_handles: Array = []       # crater.glb (+ meteor_rock.glb) instances, oldest first
var turret_yaw := {}                  # turret id -> current local yaw (rad)
var _seen_cr := {}                   # crater key -> true (SIM keeps the last 80)
var flare := 0.0
var wind_storm := 0.0
var _clock := 0.0
var _streak_mesh: ArrayMesh
var _devil_mesh: ArrayMesh
var _hz = null
var _now := 0.0
var stats := {"markers": 0, "streaks": 0, "impacts": 0, "bursts": 0, "jets": 0}

func setup(v) -> void:
	view = v
	sim = v.sim
	for c in get_children():
		c.queue_free()
	markers = {}
	streaks = {}
	watch = {}
	devils = {}
	jets = {}
	quakes = {}
	fading = []
	flashes = []
	_hz = sim.get("hazards")
	if _hz != null and not (_hz is Object and (_hz as Object).has_method("forecast")):
		_hz = null
	_streak_mesh = _make_strip()
	_devil_mesh = _make_tube()
	# A loaded game: the craters that are already there, without effects.
	_seen_cr = {}
	if _hz != null:
		var cr: Array = _hz.craters()
		view.terrain.add_craters(cr)
		for c in cr:
			_seen_cr[_ckey(c)] = true
			_crater_model(Vector2(float(c["x"]), float(c["y"])), float(c["r"]), false)

func _make_strip() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	for i in n:
		var x0: float = float(i) / n
		var x1: float = float(i + 1) / n
		for q in [[x0, -1.0], [x1, -1.0], [x1, 1.0], [x0, -1.0], [x1, 1.0], [x0, 1.0]]:
			st.set_uv(Vector2(q[0], q[1] * 0.5 + 0.5))
			st.add_vertex(Vector3(q[0], q[1], 0.0))
	var m: ArrayMesh = st.commit()
	m.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	return m

func _make_tube() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	var rings := 8
	for j in rings:
		var y0: float = float(j) / rings
		var y1: float = float(j + 1) / rings
		for i in seg:
			var a0: float = TAU * i / seg
			var a1: float = TAU * (i + 1) / seg
			var v := [Vector3(cos(a0), y0, sin(a0)), Vector3(cos(a1), y0, sin(a1)), Vector3(cos(a1), y1, sin(a1)), Vector3(cos(a0), y1, sin(a0))]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(v[k].x, 0, v[k].z))
				st.add_vertex(v[k])
	return st.commit()

# ---------------------------------------------------------------- per frame
func sync(delta: float, focus: Vector3) -> void:
	_now += delta
	var gr: float = maxf(float(view.game_rate), 0.0)
	_update_fading(delta)
	if _hz == null:
		return
	_clock -= delta
	var poll: bool = _clock <= 0.0
	if poll:
		_clock = 0.2
		_poll(focus)
	_update_streaks(delta * gr)
	_update_devils(delta)
	_update_quakes(delta, focus)
	_aim_turrets(delta)
	# Whole-map weather, eased.
	var fl_t := 0.0
	var ws_t := 0.0
	for ev in _cached_events:
		match String(ev["kind"]):
			"solar_flare":
				fl_t = maxf(fl_t, 1.0 if ev["phase"] == "active" else (0.25 if ev["phase"] == "warning" else 0.0))
			"wind_storm":
				if ev["phase"] == "active":
					ws_t = maxf(ws_t, 0.5 + 0.25 * float(ev["severity"]))
				elif ev["phase"] == "warning":
					ws_t = maxf(ws_t, 0.15)
	flare = move_toward(flare, fl_t, delta * 0.4)
	wind_storm = move_toward(wind_storm, ws_t, delta * 0.35)
	view.sky.aurora = flare
	view.post.flare = flare * 0.8
	view.fx.wind_storm = wind_storm
	view.post.wind = wind_storm
	var haze: float = maxf(float(view.sky.storm) if view.sky != null else 0.0, wind_storm)
	var keep: Array = []
	for w in _haze_mats:
		var hm = w.get_ref()
		if hm != null:
			(hm as ShaderMaterial).set_shader_parameter("glow", 1.0 + 2.2 * haze)
			keep.append(w)
	_haze_mats = keep

var _cached_events: Array = []
# Critic round 8: warning rings and quake cracks stay readable in a dust or wind storm. Their
# materials draw after the storm dust (render priority) and glow brighter with the haze.
var _haze_mats: Array = []
var haze_prio := 20

func _haze_proof(mi: MeshInstance3D) -> void:
	var m = mi.material_override
	if not (m is ShaderMaterial):
		return
	var dm: ShaderMaterial = (m as ShaderMaterial).duplicate()
	dm.render_priority = haze_prio
	mi.material_override = dm
	_haze_mats.append(weakref(dm))

func _poll(focus: Vector3) -> void:
	var fc: Array = _hz.forecast()
	var ac: Array = _hz.active()
	_cached_events = fc + ac
	var tick: int = int(sim.state["tick"])
	var hzr: float = float(sim.bal["tick_hz"])
	var seen := {}
	for ev in _cached_events:
		var id: int = int(ev["id"])
		seen[id] = true
		var kind: String = ev["kind"]
		if kind in LOCAL:
			_marker(ev)
		if kind == "meteor" and ev["phase"] != "active":
			if not watch.has(id):
				watch[id] = {"pos": ev["pos"], "at": int(ev["at"]), "sev": int(ev["severity"]), "strikes": {}}
			_want_streak("m%d" % id, id, ev["pos"], float(ev["eta_s"]), bool(ev["countered"]), int(ev["severity"]))
		elif kind == "meteor_shower":
			if not watch.has(id):
				watch[id] = {"pos": ev["pos"], "at": int(ev["at"]), "sev": int(ev["severity"]), "strikes": {}, "shower": true}
			var strikes: Array = ev.get("strikes", [])
			for k in strikes.size():
				var s: Dictionary = strikes[k]
				if not bool(s["done"]):
					_want_streak("s%d:%d" % [id, k], id, s["pos"], float(s["eta_s"]) + (float(ev["eta_s"]) if ev["phase"] != "active" else 0.0), bool(ev["countered"]), int(ev["severity"]))
		elif kind == "quake" and ev["phase"] == "active" and not quakes.has(id):
			_quake_start(ev, focus)
		elif kind == "dust_devil" and ev["phase"] == "active":
			_devil(ev)
	# Markers of events that are over.
	for id in markers.keys():
		if not seen.has(id) or _phase_of(id) == "active" and String(markers[id]["kind"]) in ["meteor", "quake", "dust_devil"]:
			_drop_marker(id)
	for id in devils.keys():
		if not seen.has(id):
			(devils[id]["node"] as Node).queue_free()
			view.fx.emitter_stop("devil%d" % id)
			devils.erase(id)
	# Interceptions: a watched meteor whose time came.
	for id in watch.keys():
		var w: Dictionary = watch[id]
		var full: Dictionary = _hz.event(id)
		if bool(w.get("shower", false)):
			for hit in full.get("hits", []):
				if (hit as Dictionary).has("turret"):
					var hk: String = "%s" % str(hit["pos"])
					if not (w["strikes"] as Dictionary).has(hk):
						w["strikes"][hk] = true
						_air_burst(hit["pos"], int(hit["turret"]), int(w["sev"]))
			if not seen.has(id):
				watch.erase(id)
			continue
		if tick >= int(w["at"]):
			var res: Dictionary = full.get("result", {})
			if int(res.get("intercepted", 0)) > 0:
				var turret: int = -1
				for hit in full.get("hits", []):
					if (hit as Dictionary).has("turret"):
						turret = int(hit["turret"])
				_air_burst(w["pos"], turret, int(w["sev"]))
			watch.erase(id)
	# Impacts: every new crater.
	var cr: Array = _hz.craters()
	var now_keys := {}
	for c in cr:
		var ck: String = _ckey(c)
		now_keys[ck] = true
		if not _seen_cr.has(ck):
			_impact(Vector2(float(c["x"]), float(c["y"])), float(c["r"]), focus)
	_seen_cr = now_keys
	# Breaches: a white air jet on every breached room or corridor.
	var keep := {}
	var blds: Dictionary = sim.state["buildings"]
	for bid in blds:
		var b: Dictionary = blds[bid]
		if not bool(b.get("breach", false)):
			continue
		keep[bid] = true
		var key: String = "jet%d" % bid
		var yaw := 0.0
		var p := Vector3.ZERO
		if b["kind"] == "link":
			var p0: Vector2 = b["p0"]
			var p1: Vector2 = b["p1"]
			var t: float = 0.3 + Rng.hash2(int(bid), 5, 9) * 0.4
			var q: Vector2 = p0.lerp(p1, t)
			var side: float = 1.0 if Rng.hash2(int(bid), 7, 1) > 0.5 else -1.0
			var n: Vector2 = (p1 - p0).normalized().orthogonal() * side
			p = view.to3(q + n * 1.15, 1.35)
			yaw = -n.angle()
		else:
			var a: float = Rng.hash2(int(bid), 3, 3) * TAU
			var r: float = float(b["radius"]) - 0.35
			var c2: Vector2 = b["pos"]
			p = view.to3(c2 + Vector2(cos(a), sin(a)) * r, 1.05)
			yaw = -a
		view.fx.emitter_set(key, "air_jet", p, 1.0, yaw)
		jets[bid] = key
	for bid in jets.keys():
		if not keep.has(bid):
			view.fx.emitter_stop(jets[bid])
			jets.erase(bid)
	stats["markers"] = markers.size()
	stats["streaks"] = streaks.size()
	stats["jets"] = jets.size()

static func _ckey(c: Dictionary) -> String:
	return "%.1f:%.1f:%d" % [float(c["x"]), float(c["y"]), int(c.get("tick", 0))]

func _phase_of(id: int) -> String:
	for ev in _cached_events:
		if int(ev["id"]) == id:
			return String(ev["phase"])
	return ""

# ---------------------------------------------------------------- forecast markers
func _marker(ev: Dictionary) -> void:
	var id: int = int(ev["id"])
	var kind: String = ev["kind"]
	var phase: String = ev["phase"]
	if phase == "active" and kind != "meteor_shower":
		return
	var countered: bool = bool(ev["countered"])
	var col: Color = Color(0.3, 0.9, 1.0, 0.9) if countered else (Color(1.0, 0.3, 0.22, 0.95) if kind != "quake" and kind != "dust_devil" else Color(1.0, 0.7, 0.25, 0.9))
	var sig: String = "%s|%s" % [phase, str(countered)]
	if markers.has(id) and markers[id]["sig"] == sig:
		_marker_label(ev)
		return
	if markers.has(id):
		_drop_marker(id)
	var nodes: Array = []
	var p: Vector2 = ev["pos"]
	var r: float = maxf(2.0, float(ev["radius"]))
	match kind:
		"meteor":
			var ring: MeshInstance3D = view.decal_ring(r, 0.0, 96, col, 6)
			ring.material_override = (ring.material_override as ShaderMaterial).duplicate()
			ring.position = Vector3(p.x, 0, p.y)
			add_child(ring)
			nodes.append(ring)
		"meteor_shower":
			var zone: MeshInstance3D = view.decal_ring(r, 0.97, 128, col, 1, 64.0, 0.6)
			zone.position = Vector3(p.x, 0, p.y)
			add_child(zone)
			nodes.append(zone)
			for s in ev.get("strikes", []):
				if bool(s["done"]):
					continue
				var sr: MeshInstance3D = view.decal_ring(float(s["r"]), 0.0, 64, col, 6)
				sr.material_override = (sr.material_override as ShaderMaterial).duplicate()
				sr.position = Vector3((s["pos"] as Vector2).x, 0, (s["pos"] as Vector2).y)
				add_child(sr)
				nodes.append(sr)
		"quake":
			var q: MeshInstance3D = view.decal_ring(r, 0.985, 160, col, 1, 96.0, 0.3)
			q.position = Vector3(p.x, 0, p.y)
			add_child(q)
			nodes.append(q)
		"dust_devil":
			var path: Array = ev.get("path", [p, p])
			var a: Vector2 = path[0]
			var b: Vector2 = path[1]
			var line := MeshInstance3D.new()
			line.mesh = view.strip_mesh(maxf(1.0, a.distance_to(b)), 1.2)
			line.material_override = view.decal_material(col, 2, 48.0, 1.2, 0.2)
			line.set_instance_shader_parameter("icolor", Color(1, 1, 1, 1))
			line.set_instance_shader_parameter("ipulse", 0.0)
			var ring2: MeshInstance3D = view.decal_ring(float(ev["radius"]) * 1.5, 0.9, 64, col, 1, 24.0, 0.5)
			ring2.position = Vector3(a.x, 0, a.y)
			add_child(ring2)
			nodes.append(ring2)
			line.position = Vector3(a.x, 0, a.y)
			line.rotation = Vector3(0, -(b - a).angle(), 0)
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			line.extra_cull_margin = 64.0
			add_child(line)
			nodes.append(line)
	for nd in nodes:
		if nd is MeshInstance3D:
			_haze_proof(nd)
	var lab := Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.fixed_size = true
	lab.pixel_size = 0.0009
	lab.font_size = 22
	lab.outline_size = 7
	lab.outline_modulate = Color(0.02, 0.03, 0.05, 0.9)
	lab.modulate = col.lerp(Color.WHITE, 0.35)
	lab.render_priority = 11
	lab.position = view.to3(p, 3.0)
	add_child(lab)
	nodes.append(lab)
	markers[id] = {"nodes": nodes, "label": lab, "kind": kind, "sig": sig}
	_marker_label(ev)

func _marker_label(ev: Dictionary) -> void:
	var m: Dictionary = markers.get(int(ev["id"]), {})
	if m.is_empty():
		return
	var lab: Label3D = m["label"]
	var names := {"meteor": "METEOR", "meteor_shower": "METEOR SHOWER", "quake": "QUAKE", "dust_devil": "DUST DEVIL"}
	var t: int = int(ceil(float(ev["eta_s"])))
	lab.text = "%s  %d s%s" % [names.get(String(ev["kind"]), "HAZARD"), t, "\nCOVERED" if bool(ev["countered"]) else ""]
	lab.visible = view.labels_visible and view.time_override < 0.0 and not view._photo_mode()

func _drop_marker(id: int) -> void:
	for n in markers[id]["nodes"]:
		(n as Node).queue_free()
	markers.erase(id)

# ---------------------------------------------------------------- meteors
## ART-HAB crater.glb: the rim crest is at radius 1.0, so it is scaled by the sim radius; the
## meteor rock lies in the middle of a fresh crater. At most 80 (SIM keeps 80 craters).
func _crater_model(p: Vector2, r: float, rock: bool) -> void:
	if not Models.has_model("crater"):
		return
	# Critic round 6: a crater model is a flat disc at the centre height; over structures and
	# corridors it showed as brown slabs through floors. Near a structure the crater stays a
	# ground mark only (splat texture). The height is not scaled with r (the rim was 1.1 m
	# high at r 8.7): at most 2x the model's 0.13 m.
	if not _crater_clear(p, r * 1.6):
		stats["craters_skipped"] = int(stats.get("craters_skipped", 0)) + 1
		return
	var yaw: float = Rng.hash2(int(p.x * 10.0), int(p.y * 10.0), 3) * TAU
	var base: Vector3 = view.to3(p, -0.03)
	var hs: Array = [view.inst.add(Models.prop(["crater"], r, "exterior", "space"), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(r, minf(r, 2.0), r)), base))]
	if rock and Models.has_model("meteor_rock"):
		var s: float = clampf(r * 0.12, 0.6, 1.4)
		hs.append(view.inst.add(Models.prop(["meteor_rock"], 1.0, "exterior", "space"), Transform3D(Basis(Vector3.UP, yaw * 1.7).scaled(Vector3(s, s, s)), base - Vector3(0, 0.1, 0))))
	crater_handles.append(hs)
	while crater_handles.size() > 80:
		for hh in crater_handles.pop_front():
			view.inst.remove(hh)

## True when no structure or corridor lies within `reach` of p (plus its own radius).
func _crater_clear(p: Vector2, reach: float) -> bool:
	for bid in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][bid]
		if b["kind"] == "link":
			var a: Vector2 = b["p0"]
			var ab: Vector2 = (b["p1"] as Vector2) - a
			var tt: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			if p.distance_to(a + ab * tt) < reach + 1.4:
				return false
		elif p.distance_to(b["pos"]) < reach + float(b["radius"]):
			return false
	return true

## Turrets turn towards the nearest meteor they could shoot (forecast or active), else rest.
func _aim_turrets(delta: float) -> void:
	var targets: Array = []
	for ev in _cached_events:
		if String(ev["kind"]) == "meteor" or String(ev["kind"]) == "meteor_shower":
			targets.append(ev["pos"])
	for bid in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][bid]
		if b["def"] != "meteor_turret" or not view.bmeta.has(bid) or view.bmeta[bid]["mode"] != "inst":
			continue
		var meta: Dictionary = view.bmeta[bid]
		var want := 0.0
		var best := 1e9
		for tp in targets:
			var d: float = (tp as Vector2).distance_to(b["pos"])
			if d < best and d < 90.0:
				best = d
				var local: Vector3 = (meta["xf"] as Transform3D).basis.inverse() * Vector3((tp as Vector2).x - b["pos"].x, 0, (tp as Vector2).y - b["pos"].y)
				want = atan2(-local.z, local.x)
		var cur: float = float(turret_yaw.get(bid, 0.0))
		cur += clampf(angle_difference(cur, want), -2.0 * delta, 2.0 * delta)
		turret_yaw[bid] = cur
		view.inst.set_extra(meta["h"], "Turret", Transform3D(Basis(Vector3.UP, cur), Vector3.ZERO))

## World position of a turret's muzzle: Anchor_Muzzle is the REST position (not parented to
## Turret), so its offset from the pivot turns with the turret yaw (ART-HAB P9).
func _muzzle(bid: int) -> Vector3:
	var meta: Dictionary = view.bmeta[bid]
	var tpl: Dictionary = meta["tpl"]
	var xf: Transform3D = meta["xf"]
	var s: float = float(tpl.get("scale", 1.0))
	if not (tpl["anchors"] as Dictionary).has("Muzzle"):
		return xf.origin + Vector3(0, float(meta["top"]) * 0.8, 0)
	var m: Vector3 = (tpl["anchors"]["Muzzle"] as Transform3D).origin
	var pv := Vector3(0, 1.3, 0)
	for part in tpl["parts"]:
		if part["group"] == "Turret":
			pv = (part["pivot"] as Transform3D).origin
			break
	var rot: Vector3 = pv + Basis(Vector3.UP, float(turret_yaw.get(bid, 0.0))) * (m - pv)
	return xf * (rot * s)

## A streak wanted this poll (created, or its countdown corrected).
func _want_streak(key: String, id: int, pos: Vector2, eta: float, countered: bool, sev: int) -> void:
	if eta > 3.3:
		if streaks.has(key):
			_drop_streak(key)
		return
	var target: Vector3 = view.to3(pos, 0.0)
	if streaks.has(key):
		var s: Dictionary = streaks[key]
		if absf(float(s["eta"]) - eta) > 0.35:
			s["eta"] = eta
		s["burst"] = countered
		return
	var a: float = Rng.hash2(id, 13, 3) * TAU
	var e: float = deg_to_rad(24.0 + 14.0 * Rng.hash2(id, 17, 5))
	var dir := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
	var mi := MeshInstance3D.new()
	mi.mesh = _streak_mesh
	var mat := ShaderMaterial.new()
	mat.shader = STREAK_SHADER
	mat.set_shader_parameter("width", 0.9 + 0.45 * float(sev))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	add_child(mi)
	streaks[key] = {"node": mi, "mat": mat, "target": target, "dir": dir, "eta": eta, "burst": countered, "sev": sev}
	_update_one(streaks[key])

func _drop_streak(key: String) -> void:
	(streaks[key]["node"] as Node).queue_free()
	streaks.erase(key)

func _update_streaks(dt_game: float) -> void:
	for key in streaks.keys():
		var s: Dictionary = streaks[key]
		s["eta"] = float(s["eta"]) - dt_game
		# An intercepted meteor bursts about 45 m up; a hit ends at the ground.
		var end_eta: float = (45.0 / sin(asin(clampf((s["dir"] as Vector3).y, 0.2, 1.0)))) / METEOR_SPEED if bool(s["burst"]) else 0.0
		if float(s["eta"]) <= end_eta - 0.05:
			_drop_streak(key)
			continue
		_update_one(s)

func _update_one(s: Dictionary) -> void:
	var eta: float = maxf(float(s["eta"]), 0.0)
	var head: Vector3 = (s["target"] as Vector3) + (s["dir"] as Vector3) * METEOR_SPEED * eta
	var trail: float = 30.0 + 20.0 * minf(eta, 1.0)
	var tail: Vector3 = head + (s["dir"] as Vector3) * trail
	var mat: ShaderMaterial = s["mat"]
	mat.set_shader_parameter("head", head)
	mat.set_shader_parameter("tail", tail)
	mat.set_shader_parameter("strength", clampf(1.25 - eta * 0.25, 0.3, 1.25))

func _impact(p: Vector2, r: float, focus: Vector3) -> void:
	stats["impacts"] = int(stats["impacts"]) + 1
	var pos: Vector3 = view.to3(p, 0.0)
	var fx = view.fx
	var d: float = pos.distance_to(focus)
	var near: float = clampf(1.0 - d / 260.0, 0.0, 1.0)
	fx.burst("fire", pos + Vector3(0, 1.0, 0), 70, r * 0.45)
	fx.burst("sparks", pos + Vector3(0, 0.5, 0), 90, r * 0.3)
	fx.burst("debris", pos + Vector3(0, 0.3, 0), 110, r * 0.5)
	fx.burst("impact_dust", pos + Vector3(0, 0.4, 0), 80, r * 0.7)
	fx.burst("dust_ring", pos, 60, r * 1.4)
	fx.emitter_set("crater_smoke%d" % int(_now * 10.0), "smoke_dark", pos + Vector3(0, 0.6, 0), 0.8)
	_later_stop("crater_smoke%d" % int(_now * 10.0), 25.0)
	view.post.flash(0.28 * (0.3 + 0.7 * near), Color(1.0, 0.82, 0.6))
	_flash_light(pos + Vector3(0, 5.0, 0), Color(1.0, 0.72, 0.42), 14.0, r * 7.0, 0.9)
	# Shockwave ring on the ground, and a scorch mark that fades over a few minutes.
	var ring: MeshInstance3D = view.decal_ring(r, 0.82, 96, Color(1.0, 0.85, 0.7, 0.9), 0)
	ring.material_override = (ring.material_override as ShaderMaterial).duplicate()
	ring.position = Vector3(p.x, 0, p.y)
	add_child(ring)
	fading.append({"node": ring, "t": 0.0, "life": 1.3, "kind": "wave", "r0": r, "r1": r * 7.0})
	var scorch: MeshInstance3D = view.decal_ring(r * 2.3, 0.0, 64, Color(0.08, 0.05, 0.04, 0.85), 5)
	scorch.material_override = (scorch.material_override as ShaderMaterial).duplicate()
	scorch.position = Vector3(p.x, 0, p.y)
	add_child(scorch)
	fading.append({"node": scorch, "t": 0.0, "life": 240.0, "kind": "fade"})
	view.terrain.add_crater(p, r)
	_crater_model(p, r, true)
	_shake(0.9 * near)

func _air_burst(p: Vector2, turret_id: int, sev: int) -> void:
	stats["bursts"] = int(stats["bursts"]) + 1
	var target: Vector3 = view.to3(p, 0.0)
	# Critic round 8: a bigger burst, low enough (30 m) to stay in the game camera's frame,
	# and a muzzle flash at the turret.
	var burst: Vector3 = target + Vector3(0, 24.0, 0)
	var fx = view.fx
	fx.burst("fire", burst, 110, 4.0)
	fx.burst("sparks", burst, 200, 3.0)
	fx.burst("smoke", burst, 40, 5.0)
	fx.burst("debris", burst, 30, 3.0)
	view.post.flash(0.16, Color(0.8, 0.95, 1.0))
	_flash_light(burst, Color(1.0, 0.8, 0.55), 16.0, 110.0, 0.9)
	_flash_sprite(burst, 16.0, Color(1.0, 0.75, 0.45), 1.3)
	_flash_sprite(burst, 30.0, Color(0.55, 0.35, 0.25), 2.4)
	var muzzle: Vector3 = target + Vector3(0, 3.0, 0)
	if turret_id >= 0 and view.bmeta.has(turret_id) and view.bmeta[turret_id]["mode"] == "inst":
		muzzle = _muzzle(turret_id)
	fx.burst("sparks", muzzle, 30, 0.6)
	_flash_light(muzzle, Color(0.7, 0.95, 1.0), 8.0, 18.0, 0.25)
	_flash_sprite(muzzle, 2.4, Color(0.75, 0.95, 1.0), 0.18)
	var mi := MeshInstance3D.new()
	mi.mesh = _streak_mesh
	var mat := ShaderMaterial.new()
	mat.shader = STREAK_SHADER
	mat.set_shader_parameter("head", burst)
	mat.set_shader_parameter("tail", muzzle)
	mat.set_shader_parameter("width", 0.6)
	mat.set_shader_parameter("head_col", Color(0.8, 1.0, 1.0))
	mat.set_shader_parameter("tail_col", Color(0.25, 0.85, 1.0))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	add_child(mi)
	fading.append({"node": mi, "t": 0.0, "life": 0.45, "kind": "tracer", "mat": mat})

## A camera-facing additive glow that grows and fades (burst and muzzle flash).
func _flash_sprite(p: Vector3, size: float, col: Color, life: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = FLASH_SHADER
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("k", 1.0)
	m.render_priority = 21
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 64.0
	mi.position = p
	add_child(mi)
	fading.append({"node": mi, "t": 0.0, "life": life, "kind": "flash", "mat": m})

func _flash_light(p: Vector3, col: Color, energy: float, rng: float, life: float) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	add_child(l)
	flashes.append({"light": l, "t": 0.0, "life": life, "e0": energy})

var _stops: Array = []
func _later_stop(key: String, secs: float) -> void:
	_stops.append([key, _now + secs])

func _update_fading(delta: float) -> void:
	var i := 0
	while i < fading.size():
		var f: Dictionary = fading[i]
		f["t"] = float(f["t"]) + delta
		var k: float = clampf(float(f["t"]) / float(f["life"]), 0.0, 1.0)
		var n: Node3D = f["node"]
		match String(f["kind"]):
			"wave":
				var r: float = lerpf(float(f["r0"]), float(f["r1"]), 1.0 - pow(1.0 - k, 2.0))
				n.scale = Vector3(r, 1, r)
				(n as GeometryInstance3D).set_instance_shader_parameter("icolor", Color(1, 1, 1, 1.0 - k))
			"fade":
				(n as GeometryInstance3D).set_instance_shader_parameter("icolor", Color(1, 1, 1, 1.0 - k * k))
			"tracer":
				(f["mat"] as ShaderMaterial).set_shader_parameter("strength", 1.0 - k)
			"flash":
				(f["mat"] as ShaderMaterial).set_shader_parameter("k", 1.0 - k)
		if k >= 1.0:
			n.queue_free()
			fading.remove_at(i)
			continue
		i += 1
	var j := 0
	while j < flashes.size():
		var fl: Dictionary = flashes[j]
		fl["t"] = float(fl["t"]) + delta
		var kk: float = clampf(float(fl["t"]) / float(fl["life"]), 0.0, 1.0)
		(fl["light"] as OmniLight3D).light_energy = float(fl["e0"]) * (1.0 - kk) * (1.0 - kk)
		if kk >= 1.0:
			(fl["light"] as Node).queue_free()
			flashes.remove_at(j)
			continue
		j += 1
	var s := 0
	while s < _stops.size():
		if _now >= float(_stops[s][1]):
			view.fx.emitter_stop(String(_stops[s][0]))
			_stops.remove_at(s)
			continue
		s += 1

func _shake(amount: float) -> void:
	if amount <= 0.01 or not bool(view.shake_enabled):
		return
	var r = view.rig()
	if r != null and r.has_method("shake"):
		r.shake(amount)

# ---------------------------------------------------------------- quakes, devils
func _quake_start(ev: Dictionary, focus: Vector3) -> void:
	var id: int = int(ev["id"])
	quakes[id] = {"left": maxf(1.0, float(ev.get("end_s", 6.0))), "pos": ev["pos"], "r": float(ev["radius"])}
	var p: Vector2 = ev["pos"]
	var r: float = float(ev["radius"])
	var n := 0
	for bid in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][bid]
		if b["kind"] == "link" or n >= 30:
			continue
		if (b["pos"] as Vector2).distance_to(p) <= r:
			view.fx.burst("dust", view.to3(b["pos"], 0.2), 14, float(b["radius"]) + 1.0)
			n += 1
	var cr: MeshInstance3D = view.decal_ring(clampf(r * 0.3, 8.0, 30.0), 0.0, 96, Color(0.09, 0.06, 0.05, 0.9), 4)
	cr.material_override = (cr.material_override as ShaderMaterial).duplicate()
	_haze_proof(cr)
	cr.position = Vector3(p.x, 0, p.y)
	cr.rotation.y = Rng.hash2(id, 3, 1) * TAU
	add_child(cr)
	fading.append({"node": cr, "t": 0.0, "life": 480.0, "kind": "fade"})
	view.fx.burst("impact_dust", view.to3(p, 0.3), 40, 6.0)

func _update_quakes(delta: float, focus: Vector3) -> void:
	for id in quakes.keys():
		var q: Dictionary = quakes[id]
		q["left"] = float(q["left"]) - delta * maxf(float(view.game_rate), 0.0)
		var d: float = view.to3(q["pos"]).distance_to(focus)
		var k: float = clampf(1.3 - d / maxf(20.0, float(q["r"]) * 1.4), 0.0, 1.0)
		_shake(0.45 * k)
		if float(q["left"]) <= 0.0:
			quakes.erase(id)

func _devil(ev: Dictionary) -> void:
	var id: int = int(ev["id"])
	if not devils.has(id):
		var mi := MeshInstance3D.new()
		mi.mesh = _devil_mesh
		var mat := ShaderMaterial.new()
		mat.shader = DEVIL_SHADER
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		devils[id] = {"node": mi, "mat": mat, "w": float(ev["radius"]), "path": ev.get("path", [ev["pos"], ev["pos"]]), "at": int(ev["at"]), "end": int(ev["end"])}
	var dv: Dictionary = devils[id]
	dv["pos"] = ev["pos"]

func _update_devils(delta: float) -> void:
	var hzr: float = float(sim.bal["tick_hz"])
	for id in devils:
		var dv: Dictionary = devils[id]
		var path: Array = dv["path"]
		var span: float = maxf(1.0, float(int(dv["end"]) - int(dv["at"])))
		var f: float = clampf((float(sim.state["tick"]) - float(dv["at"])) / span, 0.0, 1.0)
		var p: Vector2 = (path[0] as Vector2).lerp(path[1], f)
		var w: float = maxf(3.0, float(dv["w"]))
		var base: Vector3 = view.to3(p, 0.0)
		var mi: MeshInstance3D = dv["node"]
		mi.transform = Transform3D(Basis.from_scale(Vector3(w * 0.9, 26.0, w * 0.9)), base)
		var fade: float = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.9, 1.0, f))
		(dv["mat"] as ShaderMaterial).set_shader_parameter("strength", fade)
		view.fx.emitter_set("devil%d" % id, "devil", base + Vector3(0, 0.5, 0), fade)
		view.fx.emitter_radius("devil%d" % id, w)
