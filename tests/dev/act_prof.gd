extends SceneTree
## Developer tool: time of act_tick by plan step op, on the grown colony of profile.gd.
##   node tools/godot.mjs script res://tests/dev/act_prof.gd [ticks]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var ticks: int = int(args[0]) if args.size() > 0 else 2000
	var sim = Sim.new()
	sim.new_game(1001)
	var ref = Reference.new(sim, "all")
	for s in 12 * 600:
		ref.drive()
		sim.run_seconds(1.0)
	_grow(sim)
	var t := {}
	var n := {}
	var ag = sim.agents
	for i in ticks:
		if int(sim.state["tick"]) % 10 == 0:
			ref.drive()
		sim.state["tick"] = int(sim.state["tick"]) + 1
		var tick: int = int(sim.state["tick"])
		var second: bool = tick % 10 == 0
		sim.cmds.apply_pending()
		sim.util.env_tick()
		if second:
			sim.hazards.tick_second()
			sim.traffic.tick_second()
		if bool(sim.state["topo_dirty"]):
			sim.topo.rebuild(true)
		sim.util.power_tick(); sim.util.water_tick(); sim.util.atmo_tick(); ag.needs_tick()
		if second:
			sim.build.tick_second(); sim.upgrades.tick_second(); sim.ship.tick_second(); sim.jobs.tick_second()
		ag.think_tick()
		ag.locks_tick()
		var dt: float = 0.1
		for aid in sim.state["agents"].keys():
			if not sim.state["agents"].has(aid):
				continue
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] != "alive" or a["where"] == "lock":
				continue
			var plan: Array = a["plan"]
			if plan.is_empty() or int(a["pi"]) >= plan.size():
				continue
			var step: Dictionary = plan[a["pi"]]
			var op: String = step["op"]
			var key: String = op
			if op == "go":
				var r: Dictionary = a["route"]
				key = "go:" + ("new" if r.is_empty() or int(r.get("rev", -1)) != int(sim.state["rev"]["walk"]) else String(r["legs"][mini(int(a["li"]), r["legs"].size() - 1)]["m"]) if not r.is_empty() else "?")
			var t0: int = Time.get_ticks_usec()
			match op:
				"go": ag._do_go(a, step, dt)
				"work": ag._do_work(a, step, dt)
				"eat": ag._do_eat(a, step, dt)
				"drink": ag._do_drink(a, step, dt)
				"sleep": ag._do_sleep(a)
				_: pass
			t[key] = int(t.get(key, 0)) + Time.get_ticks_usec() - t0
			n[key] = int(n.get(key, 0)) + 1
		sim.ship.tick()
		if second:
			sim.prod.crops_second(); sim.prod.auto_second(); sim.prod.spoil_second(); sim.prod.wear_second()
			ag.morale_second(); sim.research.tick_second(); sim.alerts.tick_second(); sim.metrics.tick_second(); sim.goals.tick_second(); sim.awards.tick_second()
	var keys: Array = t.keys()
	keys.sort_custom(func(x, y): return t[x] > t[y])
	for k in keys:
		print("  %-12s %8.1f ms  %6.3f ms/tick  %7d calls  %5.1f us/call" % [k, t[k] / 1000.0, t[k] / 1000.0 / ticks, n[k], float(t[k]) / float(n[k])])
	quit(0)

func _grow(sim) -> void:
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
