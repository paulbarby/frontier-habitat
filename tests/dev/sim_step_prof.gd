extends SceneTree
## SIM probe: the cost of each system of sim.step() on a save (the same order as sim.gd step()).
##   node tools/godot.mjs script res://tests/dev/sim_step_prof.gd [save] [ticks]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

var tot := {}
var worst := {}

func _t(name: String, f: Callable) -> void:
	var t0: int = Time.get_ticks_usec()
	f.call()
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	tot[name] = float(tot.get(name, 0.0)) + ms
	worst[name] = maxf(float(worst.get(name, 0.0)), ms)

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v5.fhsave"
	var n: int = int(a[1]) if a.size() > 1 else 1500
	var sim = Sim.new()
	if path == "v3perf":
		var H = load("res://tests/helpers.gd")
		var Reference = load("res://sim/reference.gd")
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
		sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
		sim.run_seconds(20.0)
	var hz: int = int(sim.bal["tick_hz"])
	var steps: Array = []
	for i in n:
		var t_all: int = Time.get_ticks_usec()
		sim.state["tick"] = int(sim.state["tick"]) + 1
		var tick: int = int(sim.state["tick"])
		var phase: int = tick % hz
		_t("cmds", func(): sim.cmds.apply_pending())
		_t("env", func(): sim.util.env_tick())
		if phase == 0:
			_t("hazards", func(): sim.hazards.tick_second())
			_t("traffic", func(): sim.traffic.tick_second())
		if bool(sim.state["topo_dirty"]):
			_t("topo", func(): sim.topo.rebuild(true))
		_t("power", func(): sim.util.power_tick())
		_t("water", func(): sim.util.water_tick())
		_t("atmo", func(): sim.util.atmo_tick())
		_t("needs", func(): sim.agents.needs_tick())
		if phase == 1:
			_t("build", func(): sim.build.tick_second(); sim.upgrades.tick_second())
		if phase == 2:
			_t("vehicles2", func(): sim.vehicles.tick_second(); sim.reactors.tick_second())
		if phase == 3:
			_t("explore_ship", func(): sim.explore.tick_second(); sim.ship.tick_second())
		if phase == 4:
			_t("jobs", func(): sim.jobs.tick_second())
		_t("think", func(): sim.agents.think_tick())
		_t("locks", func(): sim.agents.locks_tick())
		_t("act", func(): sim.agents.act_tick())
		_t("veh", func(): sim.vehicles.tick(); sim.ship.tick())
		if phase == 5:
			_t("prod", func(): sim.prod.crops_second(); sim.prod.auto_second(); sim.prod.spoil_second(); sim.prod.wear_second())
		if phase == 6:
			_t("morale", func(): sim.agents.morale_second())
		if phase == 7:
			_t("research_goals_awards", func(): sim.research.tick_second(); sim.goals.tick_second(); sim.awards.tick_second())
		if phase == 8:
			_t("alerts", func(): sim.alerts.tick_second())
		_t("people", func(): sim.people.tick())
		_t("relations", func(): sim.relations.tick())
		_t("education", func(): sim.education.tick())
		_t("unrest", func(): sim.unrest.tick())
		_t("rag", func(): sim.rag.tick())
		if phase == 9:
			_t("security", func(): sim.security.tick_second())
			_t("leisure", func(): sim.leisure.tick_second())
			_t("families", func(): sim.families.tick_second())
		if phase == 0:
			_t("metrics", func(): sim.metrics.tick_second())
		steps.append(float(Time.get_ticks_usec() - t_all) / 1000.0)
	var keys: Array = tot.keys()
	keys.sort_custom(func(x, y): return float(tot[x]) > float(tot[y]))
	print("%d people, %d ticks" % [sim.state["agents"].size(), n])
	for k in keys:
		print("  %-24s %8.3f ms/tick   worst %7.2f ms" % [k, float(tot[k]) / float(n), float(worst[k])])
	steps.sort()
	print("  step median %.3f ms, p99 %.2f, worst %.2f" % [steps[steps.size() / 2], steps[int(steps.size() * 0.99)], steps.back()])
	sim.dispose()
	quit(0)
