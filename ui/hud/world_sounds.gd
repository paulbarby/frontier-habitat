extends RefCounted
## World sounds that come from simulation state (docs/V3_1_DESIGN.md §2.2), played through
## main.audio.world(name, pos): level by distance from the camera focus, silent beyond 120 m,
## at most 3 of one name. Checked 5 times a second by ui/hud/watchers.gd.
##
## Split with RENDER (docs/requests/UI-to-RENDER.md 7): the UI plays what the simulation
## decides: airlock seal, pump and vent, meteor impacts (and each strike of a shower), quakes, turret
## intercepts, storms, ship landing / touchdown / take-off. RENDER plays what only the view
## knows: door_slide, ramp. So no sound plays twice.
##
## Airlock cycle (sim lock.cyc.phase, V3_1 §5.2): seal -> airlock_seal; pump -> airlock_pump
## (loop until the phase ends); open -> airlock_vent when going out (air leaves). The door
## opening itself is RENDER's door_slide (it plays it for every door, airlock doors too), so the
## UI plays no door_slide (RENDER-to-UI 2026-09-25: it was heard twice).

var hud
var _lock_phase := {}      # airlock id -> last phase ("" idle)
var _pump := {}            # airlock id -> world handle of the pump loop
var _events := {}          # hazard event id -> phase seen / strikes done
var _storm := -1           # handle of the storm loop
var _ships := {}           # arrival id -> phase
var _descent := {}         # arrival id -> handle of the descent loop
var _log_tick := -1

func _init(h) -> void:
	hud = h

func reset() -> void:
	for id in _pump:
		_audio().world_stop(int(_pump[id]))
	for id in _descent:
		_audio().world_stop(int(_descent[id]))
	if _storm != -1:
		_audio().world_stop(_storm)
	_lock_phase = {}
	_pump = {}
	_events = {}
	_storm = -1
	_ships = {}
	_descent = {}
	var log: Array = hud.main.sim.state.get("log", [])
	_log_tick = int(log[log.size() - 1]["tick"]) if not log.is_empty() else -1
	# What is going on at load is taken as known (no burst of sounds).
	check(true)

func _audio():
	return hud.main.audio

func check(quiet: bool = false) -> void:
	var a = _audio()
	if a == null:
		return
	var s = hud.main.sim
	_airlocks(s, a, quiet)
	_hazards(s, a, quiet)
	_ships_check(a, quiet)
	_log(s, a, quiet)

func _airlocks(s, a, quiet: bool) -> void:
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		var lock = b.get("lock", {})
		if typeof(lock) != TYPE_DICTIONARY or (lock as Dictionary).is_empty():
			continue
		var cyc: Dictionary = lock.get("cyc", {})
		var ph: String = String(cyc.get("phase", "")) if not cyc.is_empty() else ""
		var old: String = String(_lock_phase.get(id, ""))
		if ph == old:
			continue
		_lock_phase[id] = ph
		if old == "pump" and _pump.has(id):
			a.world_stop(int(_pump[id]))
			_pump.erase(id)
		if quiet:
			continue
		var p: Vector2 = b["pos"]
		match ph:
			"seal":
				a.world("airlock_seal", p)
			"pump":
				var h: int = a.world("airlock_pump", p)
				if h > 0:
					_pump[id] = h
			"open":
				if String(cyc.get("dir", "")) == "out":
					a.world("airlock_vent", p)

func _hazards(s, a, quiet: bool) -> void:
	var d = hud.data
	var storm := false
	for r in d.hazard_active():
		var kind: String = String(r["kind"])
		var id = r["id"]
		if kind == "wind_storm" or kind == "dust_storm":
			storm = true
		var seen = _events.get(id, null)
		if seen == null:
			_events[id] = 0
			if not quiet and r["pos"] != null:
				match kind:
					"meteor": a.world("meteor_impact", r["pos"])
					"quake": a.world("quake_rumble", r["pos"])
		# Meteor shower: one impact per strike as it lands.
		if kind == "meteor_shower" and s.get("hazards") != null and s.hazards.has_method("event"):
			var ev: Dictionary = s.hazards.event(int(id))
			var done := 0
			for st in ev.get("strikes", []):
				if bool(st.get("done", false)):
					done += 1
					if done > int(_events[id]) and not quiet:
						a.world("meteor_impact", st.get("pos", r["pos"]))
			_events[id] = maxi(int(_events[id]), done)
	# Storm: one loop at the camera focus while wind or dust blows.
	if storm and _storm == -1 and not quiet:
		_storm = a.world("storm_loop", a._focus())
	elif not storm and _storm != -1:
		a.world_stop(_storm)
		_storm = -1
	if _storm != -1:
		a.world_move(_storm, a._focus())

func _ships_check(a, quiet: bool) -> void:
	var d = hud.data
	var seen := {}
	for r in d.traffic_ships():
		var id: int = int(r.get("id", -1))
		var ph: String = String(r.get("phase", ""))
		seen[id] = true
		var old: String = String(_ships.get(id, ""))
		if ph == old:
			continue
		_ships[id] = ph
		var pos = r.get("pad_pos", null)
		if _descent.has(id) and ph != "landing":
			a.world_stop(int(_descent[id]))
			_descent.erase(id)
		if quiet or typeof(pos) != TYPE_VECTOR2:
			continue
		match ph:
			"landing":
				var h: int = a.world("ship_descent", pos)
				if h > 0:
					_descent[id] = h
			"landed":
				a.world("ship_touchdown", pos)   # also starts the mus_arrival cue
			"takeoff":
				a.world("ship_takeoff", pos)
	for id in _ships.keys():
		if not seen.has(id):
			_ships.erase(id)

## Turret intercepts: the log entry names the turret (its entity).
func _log(s, a, quiet: bool) -> void:
	var log: Array = s.state.get("log", [])
	var newest: int = _log_tick
	for i in range(log.size() - 1, -1, -1):
		var e: Dictionary = log[i]
		if int(e["tick"]) <= _log_tick:
			break
		newest = maxi(newest, int(e["tick"]))
		if quiet or String(e.get("code", "")) != "hazard_intercepted":
			continue
		var ents: Array = e.get("entities", [])
		var p = a._focus()
		if not ents.is_empty() and s.state["buildings"].has(int(ents[0])):
			p = s.state["buildings"][int(ents[0])]["pos"]
		a.world("turret_fire", p)
	_log_tick = newest
