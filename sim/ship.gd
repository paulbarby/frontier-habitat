extends RefCounted
## The Meridian (docs/AAA_DESIGN.md section 9): the crashed colony ship. It is a building
## record (def "meridian", kind "special") with a capsule footprint: `length` along the
## direction `rot`, radius `radius`. The footprint blocks walking and building. It is not
## part of the power, water or air networks.
##
## Repair stages (balance.json ship.stages): 0 Wreck (survey work), 1 Hull, 2 Systems,
## 3 Engines (materials delivered, then exterior work), 4 Test flight (the ship lifts,
## hovers and lands over flight_seconds), 5 Operational (readiness falls every day;
## maintenance tasks restore it; supply runs after research space_2).
##
## state.ship = {id, stage, phase, progress, readiness, runs, next_run_tick, away,
##               return_tick, program, auto_runs, flight_t, maint}
##   phase: "deliver" | "work" (stages 0..3)
##   program: "auto" (starts when the Meridian chapter opens) | "on" | "hold"
##   flight_t: 0..1 while the test flight runs, else -1 (the view animates it)

const Text = preload("res://sim/text.gd")

var sim

const SHIP_SLOTS := 4

func _init(s) -> void:
	sim = s

## How many colonists may work on the hull at once.
func work_slots() -> int:
	return SHIP_SLOTS

static func fresh_state() -> Dictionary:
	return {"id": -1, "stage": 0, "phase": "work", "progress": 0.0, "readiness": 0.0, "runs": 0,
		"next_run_tick": -1, "away": false, "return_tick": -1, "program": "auto", "auto_runs": true,
		"flight_t": -1.0, "maint": 0.0, "cargo": ""}

func sh() -> Dictionary:
	return sim.state["ship"]

func cfg() -> Dictionary:
	return sim.bal["ship"]

func record() -> Dictionary:
	return sim.state["buildings"].get(int(sh()["id"]), {})

func stage_name(i: int) -> String:
	var st: Array = cfg()["stages"]
	if i < st.size():
		return String(st[i]["name"])
	return "Operational"

# ---------------------------------------------------------------- geometry
## The two ends of the capsule's axis.
static func segment_of(b: Dictionary) -> Array:
	var half: float = maxf(0.0, float(b.get("length", 44.0)) * 0.5 - float(b["radius"]))
	var dirv := Vector2(cos(float(b["rot"])), sin(float(b["rot"])))
	return [(b["pos"] as Vector2) - dirv * half, (b["pos"] as Vector2) + dirv * half]

static func is_ship(b: Dictionary) -> bool:
	return String(b.get("def", "")) == "meridian"

## Distance from a point to the capsule surface (negative inside).
static func surface_distance(b: Dictionary, p: Vector2) -> float:
	var seg: Array = segment_of(b)
	return Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) - float(b["radius"])

## Outdoor work and delivery places along both sides and both ends of the hull.
func access_candidates(b: Dictionary) -> Array:
	var seg: Array = segment_of(b)
	var dirv: Vector2 = ((seg[1] as Vector2) - seg[0]).normalized() if (seg[1] as Vector2) != seg[0] else Vector2.RIGHT
	var side: Vector2 = dirv.orthogonal()
	var off: float = float(b["radius"]) + 1.2
	var out: Array = []
	for f in [0.5, 0.2, 0.8, 0.0, 1.0]:
		var c: Vector2 = (seg[0] as Vector2).lerp(seg[1], f)
		out.append(c + side * off)
		out.append(c - side * off)
	out.append((seg[1] as Vector2) + dirv * off)
	out.append((seg[0] as Vector2) - dirv * off)
	return out

# ---------------------------------------------------------------- placement
## Places the wreck on a new game, and on a version-1 save that has none. The site list
## comes from world generation (deterministic per seed); the first site that no structure
## of this game overlaps is used.
func place_initial() -> void:
	if int(sh()["id"]) != -1 and sim.state["buildings"].has(int(sh()["id"])):
		return
	var sites: Array = sim.world.meridian_sites
	if sites.is_empty():
		return
	var chosen: Dictionary = sites[0]
	for s in sites:
		if _clear_of_buildings(Vector2(s["x"], s["y"]), float(s["rot"])):
			chosen = s
			break
	var b: Dictionary = sim.build.spawn_active("meridian", Vector2(chosen["x"], chosen["y"]), float(chosen["rot"]))
	b["name"] = "The Meridian"
	b["length"] = capsule_length()
	b["radius"] = capsule_radius()
	b["inv_site"] = sim.inv.create_inv("b", b["id"], "ship", 100000)
	sh()["id"] = b["id"]
	sim.topo.mark_dirty()

## Footprint of the wreck (balance.json ship; buildings.json meridian.shape says the same).
func capsule_length() -> float:
	return float(cfg().get("capsule_length", sim.bdef("meridian").get("shape", {}).get("capsule_length", 44.0)))

func capsule_radius() -> float:
	return float(cfg().get("capsule_radius", sim.bdef("meridian").get("shape", {}).get("capsule_radius", 7.0)))

func _clear_of_buildings(pos: Vector2, rot: float) -> bool:
	var probe := {"pos": pos, "rot": rot, "radius": capsule_radius(), "length": capsule_length()}
	var seg: Array = segment_of(probe)
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var o: Dictionary = blds[id]
		if o["kind"] == "link":
			if seg_distance(seg[0], seg[1], o["p0"], o["p1"]) < float(probe["radius"]) + 3.0:
				return false
			continue
		if Geometry2D.get_closest_point_to_segment(o["pos"], seg[0], seg[1]).distance_to(o["pos"]) < float(probe["radius"]) + float(o["radius"]) + 4.0:
			return false
	return true

static func seg_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	var d: float = Geometry2D.get_closest_point_to_segment(a0, b0, b1).distance_to(a0)
	d = minf(d, Geometry2D.get_closest_point_to_segment(a1, b0, b1).distance_to(a1))
	d = minf(d, Geometry2D.get_closest_point_to_segment(b0, a0, a1).distance_to(b0))
	d = minf(d, Geometry2D.get_closest_point_to_segment(b1, a0, a1).distance_to(b1))
	return d

# ---------------------------------------------------------------- program
func meridian_chapter() -> int:
	var ch: Array = sim.content["chapters"]
	for i in ch.size():
		if String(ch[i]["id"]) == "meridian":
			return i
	return 3

## True while colonists should work on the repair stages.
func repairing() -> bool:
	var s: Dictionary = sh()
	if record().is_empty() or int(s["stage"]) > 3:
		return false
	match String(s["program"]):
		"on":
			return true
		"hold":
			return false
	return sim.goals.chapter() >= meridian_chapter()

## Materials the ship inventory should hold now: {item: units}.
func wants() -> Dictionary:
	var s: Dictionary = sh()
	var stage: int = int(s["stage"])
	if stage <= 3:
		if repairing() and s["phase"] == "deliver":
			return cfg()["stages"][stage]["deliver"]
		return {}
	if stage == 5 and String(s["program"]) != "hold":
		var out: Dictionary = {}
		var m: Dictionary = cfg()["maintenance"]["items"]
		for k in m:
			out[k] = int(m[k]) * 2
		if runs_unlocked():
			out["rocket_fuel"] = int(out.get("rocket_fuel", 0)) + int(cfg()["supply_run"]["fuel"])
		return out
	return {}

## What still has to be carried to the ship ({} when nothing).
func missing() -> Dictionary:
	var b: Dictionary = record()
	var out := {}
	if b.is_empty():
		return out
	var w: Dictionary = wants()
	for k in w:
		var need: int = int(w[k]) - sim.inv.count(b["inv_site"], k)
		if need > 0:
			out[k] = need
	return out

## Units of `item` the repair still needs over this stage and the later ones, less what
## was delivered to this stage. The fabricator stops pressing plates at this number.
func future_need(item: String) -> int:
	var s: Dictionary = sh()
	var stage: int = int(s["stage"])
	var stages: Array = cfg()["stages"]
	var need := 0
	for i in range(stage, mini(4, stages.size())):
		need += int(stages[i]["deliver"].get(item, 0))
	if stage <= 3 and stage < stages.size():
		if String(s["phase"]) == "deliver":
			var b: Dictionary = record()
			if not b.is_empty():
				need -= sim.inv.count(b["inv_site"], item)
		else:
			need -= int(stages[stage]["deliver"].get(item, 0))
	return maxi(0, need)

## Kind of work open on the hull now: "repair" (stages 0..3), "maint" or "".
func work_kind() -> String:
	var s: Dictionary = sh()
	var stage: int = int(s["stage"])
	if stage <= 3:
		return "repair" if repairing() and s["phase"] == "work" else ""
	if stage == 5 and not bool(s["away"]) and String(s["program"]) != "hold":
		var mt: Dictionary = cfg()["maintenance"]
		if float(s["readiness"]) < float(mt["below"]) and _has_items(mt["items"]):
			return "maint"
	return ""

func _has_items(items: Dictionary) -> bool:
	var b: Dictionary = record()
	for k in items:
		if sim.inv.available(b["inv_site"], k) < int(items[k]):
			return false
	return true

func runs_unlocked() -> bool:
	return sim.research.is_done("space_2") or sim.unlocked_all()

func has_comms() -> bool:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["def"] == "comms_tower" and b["state"] == "active" and bool(b["powered"]):
			return true
	return false

## Why a supply run cannot leave now ("" = it can).
func run_block() -> String:
	var s: Dictionary = sh()
	if int(s["stage"]) < 5:
		return "not_operational"
	if not runs_unlocked():
		return "locked_research"
	if not has_comms():
		return "no_comms"
	if bool(s["away"]):
		return "away"
	if String(s["program"]) == "hold":
		return "hold"
	var sr: Dictionary = cfg()["supply_run"]
	if float(s["readiness"]) < float(sr["min_readiness"]):
		return "readiness"
	if sim.inv.available(record()["inv_site"], "rocket_fuel") < int(sr["fuel"]):
		return "no_fuel"
	return ""

# ---------------------------------------------------------------- commands
## The cargo the next supply run brings (V3_DESIGN section 5.1): "science" |
## "medical" | "industrial".
func cargo_choice() -> String:
	var c: String = String(sh().get("cargo", ""))
	var list: Dictionary = cfg()["supply_run"].get("cargos", {})
	if list.has(c):
		return c
	return String(cfg()["supply_run"].get("default_cargo", ""))

## The units a supply run brings back with the current choice.
func cargo_items() -> Dictionary:
	var list: Dictionary = cfg()["supply_run"].get("cargos", {})
	var c: String = cargo_choice()
	if list.has(c):
		return list[c]
	return cfg()["supply_run"]["cargo"]

## Command "ship": {action: "survey" | "supply_run" | "hold", cargo?}. "cargo" (science,
## medical, industrial) is kept for every later run until it is changed. A supply_run
## command with a cargo that cannot leave now still keeps the choice.
func command(action: String, p: Dictionary = {}) -> Dictionary:
	if p.has("cargo"):
		var want: String = String(p["cargo"])
		if not cfg()["supply_run"].get("cargos", {}).has(want):
			return {"ok": false, "code": "invalid"}
		sh()["cargo"] = want
	var s: Dictionary = sh()
	if record().is_empty():
		return {"ok": false, "code": "no_ship"}
	match action:
		"cargo":
			# Only the choice (the Meridian panel): no flight.
			return {"ok": true, "code": "ok"} if p.has("cargo") else {"ok": false, "code": "invalid"}
		"survey":
			s["program"] = "on"
			sim.log_event("ship", "Work on the Meridian starts: %s." % stage_name(int(s["stage"])).to_lower(), [s["id"]], 0)
			return {"ok": true, "code": "ok"}
		"hold":
			s["program"] = "hold"
			sim.log_event("ship", "Work on the Meridian is on hold.", [s["id"]], 0)
			return {"ok": true, "code": "ok"}
		"supply_run":
			s["auto_runs"] = true
			if String(s["program"]) == "hold":
				s["program"] = "on"
			var why: String = run_block()
			if why != "":
				return {"ok": false, "code": why}
			_depart()
			return {"ok": true, "code": "ok"}
	return {"ok": false, "code": "invalid"}

# ---------------------------------------------------------------- per tick / second
## Per tick: only the test flight moves (the view animates flight_t).
func tick() -> void:
	var s: Dictionary = sh()
	if float(s["flight_t"]) < 0.0:
		return
	var secs: float = float(cfg()["stages"][4].get("flight_seconds", 40))
	s["flight_t"] = float(s["flight_t"]) + 1.0 / (secs * float(sim.bal["tick_hz"]))
	if float(s["flight_t"]) >= 1.0:
		s["flight_t"] = -1.0
		s["stage"] = 5
		s["readiness"] = 100.0
		s["phase"] = "work"
		s["next_run_tick"] = int(sim.state["tick"])
		sim.log_event("ship_flight", "The Meridian flew and landed again. It is operational. Keep its readiness up with maintenance.", [s["id"]], 1)

func tick_second() -> void:
	var s: Dictionary = sh()
	var b: Dictionary = record()
	if b.is_empty():
		return
	var stage: int = int(s["stage"])
	if stage <= 3:
		if not repairing():
			return
		var st: Dictionary = cfg()["stages"][stage]
		if s["phase"] == "deliver":
			var need: Dictionary = st["deliver"]
			for k in need:
				if sim.inv.count(b["inv_site"], k) < int(need[k]):
					return
			for k in need:
				sim.inv.consume(b["inv_site"], k, int(need[k]), "ship_repair")
				sim.stat_add("consumed", k, int(need[k]))
			s["phase"] = "work"
			s["progress"] = 0.0
			sim.log_event("ship", "The Meridian: every part for %s is there. The repair work starts." % stage_name(stage).to_lower(), [b["id"]], 0)
		elif float(s["progress"]) >= float(st["work"]) - 0.0001:
			_stage_done(stage)
		return
	if stage == 5:
		var day: float = float(sim.bal["day_length"])
		s["readiness"] = maxf(0.0, float(s["readiness"]) - float(cfg()["readiness_decay_per_day"]) / day)
		var tick: int = int(sim.state["tick"])
		if bool(s["away"]):
			if tick >= int(s["return_tick"]):
				_return()
		elif bool(s["auto_runs"]) and tick >= int(s["next_run_tick"]) and run_block() == "":
			_depart()

func _stage_done(stage: int) -> void:
	var s: Dictionary = sh()
	s["stage"] = stage + 1
	s["progress"] = 0.0
	sim.stat_add("ship_stages", "", 1)
	var nxt: int = stage + 1
	if nxt <= 3:
		var deliver: Dictionary = cfg()["stages"][nxt]["deliver"]
		s["phase"] = "deliver" if not deliver.is_empty() else "work"
		sim.log_event("ship", "The Meridian: %s done. Next: %s." % [stage_name(stage).to_lower(), stage_name(nxt).to_lower()], [s["id"]], 1)
	else:
		s["phase"] = "work"
		s["readiness"] = 100.0
		s["flight_t"] = 0.0
		sim.log_event("ship", "The Meridian: the engines are ready. The test flight starts.", [s["id"]], 1)

## Work by a colonist at the hull: repair stages or maintenance.
func add_work(work_points: float) -> void:
	var s: Dictionary = sh()
	match work_kind():
		"repair":
			var total: float = float(cfg()["stages"][int(s["stage"])]["work"])
			s["progress"] = minf(total, float(s["progress"]) + work_points)
		"maint":
			var mt: Dictionary = cfg()["maintenance"]
			s["maint"] = float(s["maint"]) + work_points
			if float(s["maint"]) >= float(mt["work"]):
				var b: Dictionary = record()
				for k in mt["items"]:
					sim.inv.consume(b["inv_site"], k, int(mt["items"][k]), "maintenance")
					sim.stat_add("consumed", k, int(mt["items"][k]))
				s["maint"] = 0.0
				s["readiness"] = minf(100.0, float(s["readiness"]) + float(mt["readiness"]))
				sim.stat_add("ship_maintenance", "", 1)

func work_done() -> bool:
	return work_kind() == ""

func _depart() -> void:
	var s: Dictionary = sh()
	var sr: Dictionary = cfg()["supply_run"]
	var b: Dictionary = record()
	sim.inv.consume(b["inv_site"], "rocket_fuel", int(sr["fuel"]), "supply_run")
	sim.stat_add("consumed", "rocket_fuel", int(sr["fuel"]))
	var day_ticks: int = int(sim.bal["day_length"]) * int(sim.bal["tick_hz"])
	var tick: int = int(sim.state["tick"])
	s["away"] = true
	s["readiness"] = maxf(0.0, float(s["readiness"]) - float(sr["readiness_cost"]))
	s["return_tick"] = tick + int(float(sr["away_days"]) * day_ticks)
	s["next_run_tick"] = tick + int(float(sr["every_days"]) * day_ticks)
	sim.jobs.cancel_tasks_for_building(b["id"], "ship_away")
	sim.log_event("ship_run", "The Meridian left on a supply run. It returns in %s." % Text.n(int(float(sr["away_days"]) * float(sim.bal["day_length"])), "second"), [b["id"]], 1)

func _return() -> void:
	var s: Dictionary = sh()
	var sr: Dictionary = cfg()["supply_run"]
	s["away"] = false
	s["runs"] = int(s["runs"]) + 1
	sim.stat_add("ship_runs", "", 1)
	sim.goals.drop_pod(cargo_items(), "supply_run")
	var n: int = sim.cmds.immigrants(int(sr.get("settlers", 0)))
	var text: String = "The Meridian is back from its supply run. A supply pod landed next to the lander."
	if n > 0:
		text += " %s came with it." % Text.n(n, "settler")
	sim.log_event("ship_run", text, [s["id"]], 1)

# ---------------------------------------------------------------- for the interface
## {id, stage, stage_name, phase, progress, work_total, readiness, runs, away, flight_t,
##  program, deliver{}, delivered{}, missing{}, run_block, next_run_in, can_run}
func info() -> Dictionary:
	var s: Dictionary = sh()
	var b: Dictionary = record()
	var stage: int = int(s["stage"])
	var total := 0.0
	var deliver := {}
	if stage <= 3:
		total = float(cfg()["stages"][stage]["work"])
		deliver = cfg()["stages"][stage]["deliver"]
	elif stage == 5:
		total = float(cfg()["maintenance"]["work"])
	var delivered := {}
	if not b.is_empty():
		delivered = (sim.inv.get_inv(b["inv_site"]).get("items", {}) as Dictionary).duplicate()
	var rb: String = run_block()
	var next_in := -1.0
	if int(s["next_run_tick"]) >= 0:
		next_in = maxf(0.0, float(int(s["next_run_tick"]) - int(sim.state["tick"])) / float(sim.bal["tick_hz"]))
	return {"id": int(s["id"]), "stage": stage, "stage_name": stage_name(stage), "phase": s["phase"],
		"progress": float(s["progress"]) if stage <= 3 else float(s["maint"]), "work_total": total,
		"readiness": float(s["readiness"]), "runs": int(s["runs"]), "away": bool(s["away"]),
		"flight_t": float(s["flight_t"]), "program": s["program"], "repairing": repairing(),
		"deliver": deliver, "delivered": delivered, "missing": missing(), "run_block": rb,
		"next_run_in": next_in, "can_run": rb == "", "cargo": cargo_choice(), "cargo_items": cargo_items(),
		"cargos": cfg()["supply_run"].get("cargos", {})}
