extends RefCounted
## Debug-only commands for screenshots, the preview and tests (like hazard_now and
## traffic_now). They work only while state.options.debug is true (boot parameter debug=1, or
## sim.load_state(state, {debug: true})); otherwise the code is "debug_only". They are recorded
## commands, so a replay stays exact, and each one is written to the log.
##
##   spawn_vehicle {kind, x?, y?, depot?}   (alias debug_vehicle)
##       A finished vehicle: in a free bay of `depot`, else at (x, y), else beside the lander.
##       Result {ok, code, id}. Codes: invalid (kind), no_bay, no_place.
##   place_finished {def, x, y, rot?, size?}   (alias debug_building)
##       A finished structure after the normal placement check (research does not lock it). Result {ok, code, id}; codes are
##       the placement codes.
##   finish_building {id}
##       A planned or half-built structure is finished at once (delivered materials go to a pile
##       beside it, as at a normal completion). Codes: unknown, not_building.
##   reactor_stage {id, stage}   stage ok | warning | critical | breach: sets the core heat to that
##       stage's threshold (the next second runs the stage as usual; breach explodes).
##   reveal {x, y, r}: the fog is lifted within r of (x, y) (deposits there surveyed, POIs found).

var sim

func _init(s) -> void:
	sim = s

func _debug() -> bool:
	return bool(sim.state.get("options", {}).get("debug", false))

func run(kind: String, p: Dictionary) -> Dictionary:
	if not _debug():
		return {"ok": false, "code": "debug_only"}
	match kind:
		"spawn_vehicle", "debug_vehicle":
			return _vehicle(p)
		"place_finished", "debug_building":
			return _building(p)
		"finish_building":
			return _finish(p)
		"reveal":
			var rv: Dictionary = sim.explore.debug_reveal(p)
			if bool(rv["ok"]):
				sim.log_event("debug", "Debug: %d m revealed." % int(p.get("r", 100)), [], 1)
			return rv
		"reactor_stage":
			var r: Dictionary = sim.reactors.debug_stage(p)
			if bool(r["ok"]):
				sim.log_event("debug", "Debug: reactor %d set to %s." % [int(p.get("id", -1)), String(p.get("stage", ""))], [int(p.get("id", -1))], 1)
			return r
	return {"ok": false, "code": "invalid"}

func _vehicle(p: Dictionary) -> Dictionary:
	var kind: String = String(p.get("kind", ""))
	var k: Dictionary = sim.vehicles.kinds().get(kind, {})
	if k.is_empty():
		return {"ok": false, "code": "invalid"}
	var pos := Vector2(-1, -1)
	var depot := -1
	var bay := -1
	var d: Dictionary = sim.state["buildings"].get(int(p.get("depot", -1)), {})
	if not d.is_empty() and sim.vehicles.is_depot(d):
		bay = sim.vehicles.free_bay(d, String(k.get("bay", "small")))
		if bay == -1:
			return {"ok": false, "code": "no_bay"}
		pos = sim.vehicles.bay_pos(d, bay)
		depot = int(d["id"])
	elif p.has("x") and p.has("y"):
		pos = sim.vehicles.park_spot(Vector2(float(p["x"]), float(p["y"])))
	else:
		var lander: Dictionary = sim.state["buildings"].get(int(sim.state["lander_id"]), {})
		if lander.is_empty():
			return {"ok": false, "code": "no_place"}
		var q = sim.nav.nearest_walkable((lander["pos"] as Vector2) + Vector2(float(lander["radius"]) + 12.0, 0.0), 8)
		if q == null:
			return {"ok": false, "code": "no_place"}
		pos = q
	var v: Dictionary = sim.vehicles.spawn(kind, pos, depot)
	v["bay"] = bay
	if not d.is_empty():
		v["rot"] = float(d["rot"]) + PI
	sim.log_event("debug", "Debug: %s placed." % v["name"], [int(v["id"])], 1)
	return {"ok": true, "code": "ok", "id": int(v["id"])}

func _building(p: Dictionary) -> Dictionary:
	var def_id: String = String(p.get("def", ""))
	if not sim.content["buildings"].has(def_id):
		return {"ok": false, "code": "invalid"}
	var size: int = int(p.get("size", 1))
	var pos: Vector2 = sim.place.snap_pos(Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))
	var rot: float = sim.place.snap_rot(float(p.get("rot", 0.0)))
	var code: String = sim.place.check_building(def_id, pos, rot, -1, size)
	# Debug: research does not lock it (everything else of the placement check applies).
	if code != "ok" and code != "locked_research":
		return {"ok": false, "code": code}
	var b: Dictionary = sim.build.spawn_active(def_id, pos, rot, size)
	sim.topo.mark_dirty()
	sim.log_event("debug", "Debug: %s placed finished." % b["name"], [int(b["id"])], 1)
	return {"ok": true, "code": "ok", "id": int(b["id"])}

func _finish(p: Dictionary) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(int(p.get("id", -1)), {})
	if b.is_empty():
		return {"ok": false, "code": "unknown"}
	if b["state"] != "blueprint" and b["state"] != "building":
		return {"ok": false, "code": "not_building"}
	sim.jobs.cancel_tasks_for_building(int(b["id"]), "debug_finished")
	sim.build._commission(b, true)
	sim.log_event("debug", "Debug: %s finished at once." % b["name"], [int(b["id"])], 1)
	return {"ok": true, "code": "ok", "id": int(b["id"])}
