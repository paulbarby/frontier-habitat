extends SceneTree
## SIM probe: microseconds per call of the older systems, each called many times on a save after a warm-up
## (the calls change the state only a little; compare before and after an edit on the same machine).
##   node tools/godot.mjs script res://tests/dev/sim_micro.gd [save|v3perf]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _time(name: String, reps: int, f: Callable) -> void:
	var best := 1e12
	for r in 3:
		var t0: int = Time.get_ticks_usec()
		for i in reps:
			f.call()
		best = minf(best, float(Time.get_ticks_usec() - t0) / float(reps))
	print("  %-28s %8.1f us" % [name, best])

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var mode: String = String(a[0]) if a.size() > 0 else "save"
	var sim
	if mode == "v3perf":
		var g = H.Game.new(1001, false)
		g.ref = Reference.new(g.sim, "all")
		sim = g.sim
		g.run_to_tick(12 * 6000)
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
			g.cmd("admit_settlers", {"count": mini(6, 70 - sim.alive_count())})
			g.run(450)
		g.run(600)
	else:
		sim = Sim.new()
		sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
		sim.run_seconds(30.0)
	print("%s: %d people, %d buildings, %d inventories, %d tasks" % [mode, sim.state["agents"].size(), sim.state["buildings"].size(), sim.state["inventories"].size(), sim.state["tasks"].size()])
	_time("util.env_tick", 2000, func(): sim.util.env_tick())
	_time("util.power_tick", 2000, func(): sim.util.power_tick())
	_time("util.water_tick", 2000, func(): sim.util.water_tick())
	_time("util.atmo_tick", 2000, func(): sim.util.atmo_tick())
	_time("agents.needs_tick", 2000, func(): sim.agents.needs_tick())
	_time("agents.locks_tick", 2000, func(): sim.agents.locks_tick())
	_time("agents.morale_second(0)", 500, func(): sim.agents.morale_second(0))
	_time("agents.morale_second(1)", 500, func(): sim.agents.morale_second(1))
	_time("metrics.forecast (new)", 300, func(): sim.metrics._fc_tick = -1; sim.metrics.forecast())
	_time("inv.totals", 300, func(): sim.inv.totals())
	_time("alerts.tick_second", 100, func(): sim.alerts.tick_second())
	for fn in ["_power_issues", "_water_issues", "_air_issues", "_building_issues", "_people_issues", "_supply_issues", "_nutrition_issues", "_progress_issues", "_hazard_issues"]:
		_time("  alerts." + fn, 100, func(): sim.alerts.call(fn, {}))
	_time("  alerts reactors.issues", 100, func(): sim.reactors.issues({}, sim.alerts))
	_time("  alerts._merge", 100, func(): sim.alerts._merge({}))
	_time("jobs._index(full)", 500, func(): sim.jobs._index(true))
	_time("jobs._expire", 200, func(): sim.jobs._expire())
	_time("jobs._gen_machine_inputs", 200, func(): sim.jobs._gen_machine_inputs())
	_time("jobs._gen_repair", 200, func(): sim.jobs._gen_repair())
	_time("jobs._gen_hazard_work", 200, func(): sim.jobs._gen_hazard_work())
	_time("jobs._gen_clearing", 200, func(): sim.jobs._gen_clearing())
	_time("jobs._gen_operate", 200, func(): sim.jobs._gen_operate())
	_time("jobs._gen_construction", 200, func(): sim.jobs._gen_construction())
	_time("prod.crops_second", 200, func(): sim.prod.crops_second())
	_time("prod.auto_second", 200, func(): sim.prod.auto_second())
	_time("prod.spoil_second", 200, func(): sim.prod.spoil_second())
	_time("prod.wear_second", 200, func(): sim.prod.wear_second())
	_time("agents.think_tick (1/10)", 500, func(): sim.agents.think_tick())
	sim.dispose()
	quit(0)
