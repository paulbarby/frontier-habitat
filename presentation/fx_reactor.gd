extends Node3D
## Reactor disaster effects (RENDER, V4_DESIGN §4.2): the meltdown sequence warning -> critical
## -> breach on a fission reactor, and radiation zones.
##
## - warning: red lamps round the reactor pulse slowly, one alarm; the reactor's Lights group red.
## - critical: fast pulse, steam from the reactor, amber-red.
## - breach: a flash, fireball, debris and a dark dust cloud, a shock ring on the ground to the
##   blast radius, camera shake, a scorched crater; then a radiation zone.
## - radiation zone: a hazard-hatched disc with a pulsing edge and green-yellow motes rising.
##
## Data: SIM's meltdown is not published yet (SIM milestone 5). This reads, when present,
## `b.reactor.stage` ("", "warning", "critical", "breach") on a building and
## `state.rad_zones` [{x, y, r, level}]; `set_stage()` / `add_zone()` stage it for evidence
## (`reactor <id> <stage>`). Nothing is written to sim.state. Lights come from a pool made at
## setup and parked (a light first shown mid-game costs a shader-compile frame, V3.1).

const POOL := 6
var view
var sim
var stages := {}          # building id -> {stage, t, forced}
var zones := {}           # key -> {pos: Vector3, r, decal, emitter}
var _pool: Array = []     # OmniLight3D
var _flash: OmniLight3D
var _flash_t := -1.0
var _shock: MeshInstance3D
var _shock_t := -1.0
var _shock_r := 60.0
var stats := {"reactors": 0, "zones": 0}
var _shock2: MeshInstance3D
var _shock2_t := -1.0
var _column_key := ""
var _column_t := -1.0
func _column_pos() -> Vector3:
	var e: Dictionary = view.fx.emitters.get(_column_key, {})
	return e.get("pos", Vector3.ZERO)

func setup(v) -> void:
	view = v
	sim = v.sim
	for i in POOL:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.omni_attenuation = 1.2
		add_child(l)
		view.sky.park(l)
		_pool.append(l)
	_flash = OmniLight3D.new()
	_flash.shadow_enabled = false
	add_child(_flash)
	view.sky.park(_flash)

## Evidence / tests until SIM publishes the meltdown.
func set_stage(bid: int, stage: String) -> void:
	stages[bid] = {"stage": stage, "t": 0.0, "forced": true, "done": false}

## A staged reactor (evidence): the model at pos, driven through the stages by `rxdemo`.
func stage_at(key: int, pos: Vector2, r: float, stage: String) -> void:
	var s: Dictionary = stages.get(key, {"t": 0.0, "done": false, "staged": true})
	s["stage"] = stage
	s["t"] = 0.0
	s["pos"] = pos
	s["r"] = r
	s["forced"] = true
	s["staged"] = true
	stages[key] = s

## A zone on the ground: "rad" (radiation: yellow hatch, rising motes) or "toxic" (chemical leak:
## green hatch, low haze). `k` 0..1 = its strength now (a zone halves / runs out over time).
func add_zone(key: String, pos: Vector2, r: float, kind: String = "rad", k: float = 1.0) -> void:
	var y: float = view.h(pos.x, pos.y)
	if not zones.has(key):
		var col: Color = Color(1.0, 0.86, 0.18, 0.9) if kind == "rad" else Color(0.5, 1.0, 0.3, 0.9)
		# Critic round 22: the zone is a ground stain (mode 8) with a soft breathing edge; the hard
		# hatched ring (mode 7) shows only with the radiation layer on or a warning (someone inside).
		var d: MeshInstance3D = view.decal_ring(r, 0.001, 96, col, 7)
		d.position = Vector3(pos.x, y, pos.y)
		d.scale = Vector3(r, 1, r)
		d.visible = false
		add_child(d)
		var stain_col: Color = Color(0.4, 0.38, 0.1, 1.0) if kind == "rad" else Color(0.24, 0.4, 0.12, 1.0)
		var st: MeshInstance3D = view.decal_ring(r, 0.001, 96, stain_col, 8)
		st.position = Vector3(pos.x, y, pos.y)
		st.scale = Vector3(r, 1, r)
		add_child(st)
		var key2 := "rad_%s" % key
		view.fx.emitter_set(key2, "rad_motes" if kind == "rad" else "smoke", Vector3(pos.x, y + 0.5, pos.y), 1.0)
		view.fx.emitter_radius(key2, r * 0.8)
		zones[key] = {"pos": Vector3(pos.x, y, pos.y), "r": r, "decal": d, "stain": st, "emitter": key2, "kind": kind}
	var z: Dictionary = zones[key]
	var kk: float = clampf(k, 0.15, 1.0)
	(z["decal"] as MeshInstance3D).set_instance_shader_parameter("icolor", Color(1, 1, 1, kk))
	if z.get("stain") != null:
		(z["stain"] as MeshInstance3D).set_instance_shader_parameter("icolor", Color(1, 1, 1, clampf(0.35 + kk * 0.65, 0.0, 1.0)))
	view.fx.emitter_set(String(z["emitter"]), "rad_motes" if String(z["kind"]) == "rad" else "smoke", (z["pos"] as Vector3) + Vector3(0, 0.5, 0), kk)
	z["seen"] = true

func drop_zone(key: String) -> void:
	if not zones.has(key):
		return
	(zones[key]["decal"] as Node).queue_free()
	if zones[key].get("stain") != null:
		(zones[key]["stain"] as Node).queue_free()
	view.fx.emitter_stop(String(zones[key]["emitter"]))
	zones.erase(key)

# ---------------------------------------------------------------- SIM (milestone 6)
var _log_tick := -1
var _bpos := {}           # risky structure id -> [Vector2, radius] (known after it is destroyed)

func _sim_sync() -> void:
	var rx = sim.get("reactors")
	if rx == null or not (rx as Object).has_method("list"):
		return
	var seen := {}
	for row in rx.list():
		var bid: int = int(row["id"])
		seen[bid] = true
		var st: String = "" if String(row["stage"]) == "ok" else String(row["stage"])
		var s: Dictionary = stages.get(bid, {})
		if s.is_empty() or (String(s["stage"]) != st and not bool(s.get("forced", false))):
			stages[bid] = {"stage": st, "t": 0.0, "forced": false, "done": true, "sim": true}
			s = stages[bid]
		s["pos"] = row["pos"]
		s["blast"] = float(row.get("blast_r", 60.0))
	for bid in stages.keys():
		if bool(stages[bid].get("sim", false)) and not seen.has(bid) and String(stages[bid]["stage"]) != "breach":
			stages.erase(bid)
	# Risky structures gone since the last sync: SIM logs reactor_breach and unstable_blast with no
	# entity, so the explosion is placed at the structure of that def that has just gone.
	var gone := {}
	for bid2 in _bpos.keys():
		if not sim.state["buildings"].has(bid2):
			gone[bid2] = _bpos[bid2]
			_bpos.erase(bid2)
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["def"]) in ["fission_reactor", "crystal_refinery", "chemical_plant"]:
			_bpos[int(id)] = [b["pos"], float(b.get("radius", 8.0)), String(b["def"])]
	# Zones: radiation halves every half_s; a toxic zone runs out at `until`.
	var now_s: float = float(sim.state["tick"]) / float(sim.bal["tick_hz"])
	for z in zones.values():
		z["seen"] = false
	if (rx as Object).has_method("zones"):
		for z in rx.zones():
			var kind: String = String(z.get("kind", "rad"))
			var key := "%s_%d_%d_%d" % [kind, int(z["x"]), int(z["y"]), int(z.get("t0", 0))]
			var k := 1.0
			if kind == "rad":
				var age: float = now_s - float(z.get("t0", 0)) / float(sim.bal["tick_hz"])
				k = pow(0.5, maxf(age, 0.0) / maxf(float(z.get("half_s", 1.0)), 1.0))
			add_zone(key, Vector2(float(z["x"]), float(z["y"])), float(z["r"]), kind, k)
	for key in zones.keys():
		if not bool(zones[key].get("seen", true)) and not String(key).begins_with("dbg") and not String(key).begins_with("b"):
			drop_zone(key)
	# The moment of an explosion: SIM's log.
	var log: Array = sim.state.get("log", [])
	var last: int = _log_tick
	for i in range(log.size() - 1, -1, -1):
		var e: Dictionary = log[i]
		if int(e["tick"]) <= _log_tick:
			break
		last = maxi(last, int(e["tick"]))
		var ents: Array = e.get("ents", [])
		match String(e["code"]):
			"reactor_breach":
				var rid: int = int(ents[0]) if not ents.is_empty() else _blown(gone, "fission_reactor")
				var bp = _bpos.get(rid, gone.get(rid))
				var st2: Dictionary = stages.get(rid, {})
				if bp == null and st2.is_empty():
					continue
				var p2: Vector2 = st2.get("pos", bp[0] if bp != null else Vector2.ZERO)
				if _log_tick >= 0:
					_explode(Vector3(p2.x, view.h(p2.x, p2.y), p2.y), float(st2.get("blast", float(rx.rcfg()["blast_r"]) if (rx as Object).has_method("rcfg") else 60.0)))
					stats["sim_blasts"] = int(stats.get("sim_blasts", 0)) + 1
				stages.erase(rid)
			"unstable_blast":
				var uid: int = int(ents[0]) if not ents.is_empty() else _blown(gone, "crystal_refinery")
				var bp2 = _bpos.get(uid, gone.get(uid))
				if bp2 != null and _log_tick >= 0:
					var p3: Vector2 = bp2[0]
					_explode(Vector3(p3.x, view.h(p3.x, p3.y), p3.y), 14.0, 0.35)
					stats["sim_blasts"] = int(stats.get("sim_blasts", 0)) + 1
	_log_tick = last if _log_tick >= 0 or log.is_empty() else int(log[-1]["tick"])

## The structure a log entry with no entity is about: the one of `def` that has just gone; for a
## reactor that still stands, the hottest staged one (breach, then critical).
func _blown(gone: Dictionary, def: String) -> int:
	for id in gone:
		if gone[id].size() > 2 and String(gone[id][2]) == def:
			return int(id)
	if def == "fission_reactor":
		for want in ["breach", "critical", "warning"]:
			for id in stages:
				if String(stages[id]["stage"]) == want and bool(stages[id].get("sim", false)):
					return int(id)
	return -1

func sync(delta: float) -> void:
	var blds: Dictionary = sim.state["buildings"]
	# SIM's stages when it publishes them.
	for id in blds:
		var b: Dictionary = blds[id]
		var rx = b.get("reactor")
		if rx is Dictionary and (rx as Dictionary).has("stage"):
			var st: String = String(rx["stage"])
			if not stages.has(id) or (String(stages[id]["stage"]) != st and not bool(stages[id].get("forced", false))):
				stages[id] = {"stage": st, "t": 0.0, "forced": false, "done": false}
	_sim_sync()
	var used := 0
	var night: float = float(view.sky.night) if view.sky != null else 0.0
	for id in stages.keys():
		var s: Dictionary = stages[id]
		s["t"] = float(s["t"]) + delta
		if not blds.has(id) and String(s["stage"]) != "breach" and not s.has("staged"):
			stages.erase(id)
			continue
		var b: Dictionary = blds.get(id, {})
		var p: Vector2 = b["pos"] if not b.is_empty() else s.get("pos", Vector2.ZERO)
		s["pos"] = p
		var r: float = float(b.get("radius", 12.0)) if not b.is_empty() else float(s.get("r", 12.0))
		s["r"] = r
		var c3 := Vector3(p.x, view.h(p.x, p.y), p.y)
		match String(s["stage"]):
			"warning", "critical":
				var crit: bool = String(s["stage"]) == "critical"
				var hz: float = 3.0 if crit else 1.1
				var k: float = 0.5 + 0.5 * sin(float(s["t"]) * TAU * hz)
				for i in 3:
					if used >= _pool.size():
						break
					var l: OmniLight3D = _pool[used]
					used += 1
					var a: float = TAU * float(i) / 3.0 + float(s["t"]) * (1.2 if crit else 0.4)
					l.position = c3 + Vector3(cos(a) * r * 0.75, 5.0, sin(a) * r * 0.75)
					l.light_color = Color(1.0, 0.12, 0.06) if crit else Color(1.0, 0.25, 0.08)
					l.omni_range = r * 1.6
					l.light_energy = (1.5 + 3.5 * k) * (1.6 if crit else 1.0) * lerpf(0.6, 1.3, night)
				if crit:
					view.fx.emitter_set("rx_steam_%d" % id, "steam", c3 + Vector3(0, r * 0.6, 0), 1.6)
				# A red target ring on the ground (readable by day): the blast radius to clear.
				var ring: MeshInstance3D = s.get("ring")
				if ring == null:
					ring = view.decal_ring(1.0, 0.86, 96, Color(1.0, 0.2, 0.12, 1.0), 6)
					add_child(ring)
					s["ring"] = ring
				var br: float = float(s.get("blast", 60.0))
				ring.position = c3
				ring.scale = Vector3(br, 1, br)
				ring.set_instance_shader_parameter("ipulse", float(s["t"]) * (0.6 if crit else 0.2))
				if not bool(s.get("alarm", false)):
					s["alarm"] = true
					view.world_sound("alarm", c3)
			"breach":
				view.fx.emitter_stop("rx_steam_%d" % id)
				if s.get("ring") != null:
					(s["ring"] as Node).queue_free()
					s.erase("ring")
				if not bool(s["done"]):
					s["done"] = true
					_explode(c3, 60.0)
					add_zone("b%d" % id, p, 140.0)
				if float(s["t"]) < 45.0:
					view.fx.emitter_set("rx_smoke_%d" % id, "smoke_dark", c3 + Vector3(0, 2.0, 0), clampf(2.0 - float(s["t"]) / 30.0, 0.3, 2.0))
					view.fx.emitter_radius("rx_smoke_%d" % id, r * 0.8)
				else:
					view.fx.emitter_stop("rx_smoke_%d" % id)
	for i in range(used, _pool.size()):
		var l2: OmniLight3D = _pool[i]
		if not view.sky.parked(l2):
			view.sky.park(l2)
	_update_flash(delta)
	_zone_rings(delta)
	stats["reactors"] = stages.size()
	stats["zones"] = zones.size()

## The hard ring of a zone: with the radiation layer on, or while a colonist is inside it (a
## warning). Checked twice a second.
var _ring_clock := 0.0
func _zone_rings(delta: float) -> void:
	_ring_clock -= delta
	if _ring_clock > 0.0:
		return
	_ring_clock = 0.5
	var layer: bool = String(view.get("overlay")) in ["radiation", "rad"]
	var outs: Array = []
	for a in sim.state["agents"].values():
		if a["state"] == "alive" and a["where"] == "out":
			outs.append(a["pos"])
	for z in zones.values():
		var c: Vector3 = z["pos"]
		var inside := false
		for p in outs:
			if Vector2(c.x, c.z).distance_to(p) < float(z["r"]):
				inside = true
				break
		(z["decal"] as MeshInstance3D).visible = layer or inside or bool(z.get("force_ring", false))

## The blast: flash, fireball, debris, dust, shock ring, shake, scorched crater.
## blast = the destruction radius (the shock ring runs out to it); size scales the fireball.
func _explode(c3: Vector3, blast: float, size: float = 1.0) -> void:
	var r: float = 12.0 * size
	_flash.position = c3 + Vector3(0, 12.0 * size, 0)
	_flash.light_color = Color(1.0, 0.85, 0.6)
	_flash.omni_range = maxf(40.0, blast * 1.8)
	_flash.light_energy = 40.0 * size
	_flash_t = 0.0
	# Critic round 22: the fireball twice the size (count and spread), a dust column for ~9 s and
	# a second, slower shock ring out to twice the blast radius.
	view.fx.burst("fire", c3 + Vector3(0, 3.0 * size, 0), int(440 * size), r * 1.6, 0.0, 2.0 if size >= 0.9 else 1.0)
	view.fx.burst("fire", c3 + Vector3(0, 12.0 * size, 0), int(200 * size), r * 1.2, 0.0, 1.8 if size >= 0.9 else 1.0)
	if size >= 0.9:
		_column_key = "rx_column_%d_%d" % [int(c3.x), int(c3.z)]
		view.fx.emitter_set(_column_key, "dust_column", c3 + Vector3(0, 2.0, 0), 1.6)
		view.fx.emitter_radius(_column_key, r * 0.9)
		_column_t = 0.0
	view.fx.burst("debris", c3 + Vector3(0, 2.0, 0), int(360 * size), r * 0.6)
	view.fx.burst("impact_dust", c3, int(380 * size), r * 1.2)
	view.fx.burst("sparks", c3 + Vector3(0, 4.0, 0), int(300 * size), r)
	if view.terrain != null and view.terrain.has_method("add_crater"):
		view.terrain.add_crater(Vector2(c3.x, c3.z), r * 0.9)
	if _shock == null:
		_shock = view.decal_ring(1.0, 0.86, 128, Color(1.0, 0.8, 0.55, 1.0), 0)
		add_child(_shock)
	_shock.position = c3
	_shock_r = blast
	_shock_t = 0.0
	if _shock2 == null:
		_shock2 = view.decal_ring(1.0, 0.8, 128, Color(0.95, 0.72, 0.5, 0.8), 0)
		add_child(_shock2)
	_shock2.position = c3
	_shock2.visible = false
	_shock2_t = 0.0 if size >= 0.9 else -1.0
	var rg = view.rig()
	if rg != null and rg.has_method("shake"):
		rg.shake(2.0)
	view.world_sound("explosion", c3)

func _update_flash(delta: float) -> void:
	if _flash_t >= 0.0:
		_flash_t += delta
		_flash.light_energy = maxf(40.0 * exp(-_flash_t * 2.2), 0.0005)
		if _flash_t > 4.0:
			_flash_t = -1.0
			view.sky.park(_flash)
	if _shock_t >= 0.0 and _shock != null:
		_shock_t += delta
		var u: float = clampf(_shock_t / 1.4, 0.0, 1.0)
		var rr: float = lerpf(2.0, _shock_r, 1.0 - pow(1.0 - u, 2.0))
		_shock.scale = Vector3(rr, 1, rr)
		_shock.set_instance_shader_parameter("icolor", Color(1, 1, 1, 1.0 - u))
		_shock.visible = u < 1.0
		if u >= 1.0:
			_shock_t = -1.0
	# The second ring: starts 0.6 s later, slow (5 s), out to twice the blast radius.
	if _shock2_t >= 0.0 and _shock2 != null:
		_shock2_t += delta
		var u2: float = clampf((_shock2_t - 0.6) / 5.0, 0.0, 1.0)
		var rr2: float = lerpf(4.0, _shock_r * 2.0, 1.0 - pow(1.0 - u2, 1.6))
		_shock2.scale = Vector3(rr2, 1, rr2)
		_shock2.set_instance_shader_parameter("icolor", Color(1, 1, 1, 0.85 * (1.0 - u2)))
		_shock2.visible = _shock2_t > 0.6 and u2 < 1.0
		if u2 >= 1.0:
			_shock2_t = -1.0
	if _column_t >= 0.0:
		_column_t += delta
		view.fx.emitter_set(_column_key, "dust_column", _column_pos(), clampf(1.6 - _column_t / 7.0, 0.2, 1.6))
		if _column_t > 9.0:
			view.fx.emitter_stop(_column_key)
			_column_t = -1.0
