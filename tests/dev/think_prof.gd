extends SceneTree
## Developer tool: where _think() spends its time in the grown 70-colonist colony.
##   node tools/godot.mjs script res://tests/dev/think_prof.gd

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const Agents = preload("res://sim/agents.gd")

class ProfAgents extends "res://sim/agents.gd":
	var prof := {}
	func _init(s) -> void:
		super(s)
	func _t(k: String, t0: int) -> void:
		prof[k] = int(prof.get(k, 0)) + Time.get_ticks_usec() - t0
	func _try_drink(a: Dictionary) -> bool:
		var t0 := Time.get_ticks_usec()
		var r: bool = super(a)
		_t("drink", t0)
		return r
	func _try_eat(a: Dictionary) -> bool:
		var t0 := Time.get_ticks_usec()
		var r: bool = super(a)
		_t("eat", t0)
		return r
	func _try_sleep(a: Dictionary) -> bool:
		var t0 := Time.get_ticks_usec()
		var r: bool = super(a)
		_t("sleep", t0)
		prof["sleep_%s#" % str(r)] = int(prof.get("sleep_%s#" % str(r), 0)) + 1
		return r
	func _try_work(a: Dictionary) -> bool:
		var t0 := Time.get_ticks_usec()
		var r: bool = super(a)
		_t("work", t0)
		return r
	func _try_rec(a: Dictionary) -> bool:
		var t0 := Time.get_ticks_usec()
		var r: bool = super(a)
		_t("rec", t0)
		return r
	func _try_heal(a: Dictionary) -> bool:
		var t0 := Time.get_ticks_usec()
		var r: bool = super(a)
		_t("heal", t0)
		return r
	func _return_seconds(a: Dictionary) -> float:
		var t0 := Time.get_ticks_usec()
		var r: float = super(a)
		_t("return_seconds", t0)
		var k: String = "ret_%s_%s#" % [a["where"], "bld%d" % int(a["bld"]) if a["where"] != "out" else "out"]
		prof[k] = int(prof.get(k, 0)) + 1
		_t("ret_us_" + ("out" if a["where"] == "out" else "in"), t0)
		return r
	func _walk_back(a: Dictionary) -> Dictionary:
		var rc: Dictionary = a.get("ret_c", {})
		var why := "hit"
		if rc.is_empty():
			why = "empty"
		elif int(rc["rev"]) != int(sim.state["rev"]["walk"]):
			why = "rev"
		elif int(sim.state["tick"]) - int(rc["t"]) >= WALK_BACK_TICKS:
			why = "time"
		elif (a["pos"] as Vector2).distance_to(rc["p"]) > WALK_BACK_METRES:
			why = "moved"
		prof["wb_" + why + "#"] = int(prof.get("wb_" + why + "#", 0)) + 1
		var t0 := Time.get_ticks_usec()
		var r: Dictionary = super(a)
		_t("walk_back", t0)
		return r
	func _plan_for_task(a: Dictionary, t: Dictionary) -> Dictionary:
		var t0 := Time.get_ticks_usec()
		var r: Dictionary = super(a, t)
		_t("plan_for_task", t0)
		prof["plan_for_task#"] = int(prof.get("plan_for_task#", 0)) + 1
		return r
	func _idle(a: Dictionary) -> void:
		var t0 := Time.get_ticks_usec()
		super(a)
		_t("idle", t0)
	func _do_go(a: Dictionary, step: Dictionary, dt: float) -> void:
		var t0 := Time.get_ticks_usec()
		super(a, step, dt)
		_t("act_go", t0)
	func _do_work(a: Dictionary, step: Dictionary, dt: float) -> void:
		var t0 := Time.get_ticks_usec()
		super(a, step, dt)
		_t("act_work_" + String(step.get("kind", "")), t0)
	func _do_sleep(a: Dictionary) -> void:
		var t0 := Time.get_ticks_usec()
		super(a)
		_t("act_sleep", t0)
	func _do_timed(a: Dictionary, seconds: float, dt: float, goal: String, mark: String) -> void:
		var t0 := Time.get_ticks_usec()
		super(a, seconds, dt, goal, mark)
		_t("act_timed", t0)
	func _assign_bed(a: Dictionary) -> int:
		var t0 := Time.get_ticks_usec()
		var r: int = super(a)
		_t("assign_bed", t0)
		return r
	func _start_personal(a: Dictionary, kind: String, bid: int, steps: Array, goal: String, slot: int) -> bool:
		var t0 := Time.get_ticks_usec()
		var r: bool = super(a, kind, bid, steps, goal, slot)
		_t("start_personal", t0)
		return r
	func _sync_use(a: Dictionary) -> void:
		var t0 := Time.get_ticks_usec()
		super(a)
		_t("sync_use", t0)
	func think_tick() -> void:
		var t0 := Time.get_ticks_usec()
		super()
		_t("think_total", t0)
	func act_tick() -> void:
		var t0 := Time.get_ticks_usec()
		super()
		_t("act_total", t0)
	func needs_tick() -> void:
		var t0 := Time.get_ticks_usec()
		super()
		_t("needs_total", t0)

func _init() -> void:
	var sim = Sim.new()
	sim.new_game(1001)
	var ref = Reference.new(sim, "all")
	for s in 12 * 600:
		ref.drive()
		sim.run_seconds(1.0)
	sim.state["flags"]["unlock_all"] = true
	var y := -110
	while sim.state["buildings"].size() < 150 and y <= 110:
		var x := -110
		while sim.state["buildings"].size() < 150 and x <= 110:
			var off := Vector2(x, y)
			if off.length() > 70.0:
				var def_id: String = "solar_array" if (x + y) % 2 == 0 else "battery"
				var pos: Vector2 = sim.place.snap_pos(sim.world.center + off)
				if sim.place.check_building(def_id, pos, 0.0) == "ok":
					sim.build.spawn_active(def_id, pos, 0.0)
			x += 9
		y += 9
	var guard := 0
	while sim.alive_count() < 70 and guard < 30:
		guard += 1
		sim.submit("admit_settlers", {"count": mini(6, 70 - sim.alive_count())})
		sim.run_seconds(45.0)
	sim.run_seconds(60.0)
	var pa = ProfAgents.new(sim)
	sim.agents = pa
	var t0 := Time.get_ticks_usec()
	for i in 3000:
		if int(sim.state["tick"]) % 10 == 0:
			ref.drive()
		sim.step()
	var total: float = float(Time.get_ticks_usec() - t0) / 1000.0
	print("%d alive, %.3f ms/tick" % [sim.alive_count(), total / 3000.0])
	var keys: Array = pa.prof.keys()
	keys.sort()
	for k in keys:
		if k.ends_with("#"):
			print("  %-16s %d calls" % [k, pa.prof[k]])
		else:
			print("  %-16s %.3f ms/tick" % [k, float(pa.prof[k]) / 1000.0 / 3000.0])
	quit(0)
