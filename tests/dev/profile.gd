extends SceneTree
## Developer tool: time per simulation system.
##   node tools/godot.mjs script res://tests/dev/profile.gd [seed] [days_before] [ticks] [big]
## "big" grows the colony to 60+ colonists and 150 structures first (as long_perf does).
## Plays the reference campaign to the given day, then runs `ticks` more ticks with the
## same order as sim.step(), timing each system.

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

var t := {}

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1001
	var days: float = float(args[1]) if args.size() > 1 else 8.0
	var ticks: int = int(args[2]) if args.size() > 2 else 3000
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	var w0: int = Time.get_ticks_msec()
	for s in int(days * 600):
		ref.drive()
		sim.run_seconds(1.0)
		if s % 600 == 0:
			print("day %d at %d ms" % [s / 600, Time.get_ticks_msec() - w0])
	if args.size() > 3 and args[3] == "big":
		_grow(sim)
	if args.size() > 3 and args[3] == "v3perf":
		_grow_v3perf(sim, ref)
	if sim.jobs.get("jp") != null:
		sim.jobs.get("jp").clear()
	if sim.inv.get("tp") != null:
		sim.inv.get("tp").clear()
	if sim.agents.get("_aprof") != null:
		sim.agents.get("_aprof").clear()
	if sim.util.get("pt") != null:
		sim.util.get("pt").clear()
	if sim.nav.get("pp") != null:
		sim.nav.get("pp").clear()
	if sim.agents.get("prof") != null:
		sim.agents.get("prof").clear()     # only when timers were added by hand
	var t_all0: int = Time.get_ticks_usec()
	for i in ticks:
		if int(sim.state["tick"]) % 10 == 0:
			_time("ref.drive", func(): ref.drive())
		_step(sim)
	var total: float = float(Time.get_ticks_usec() - t_all0) / 1000.0
	var keys: Array = t.keys()
	keys.sort_custom(func(a, b): return t[a] > t[b])
	print("%d ticks, %.1f ms, %.3f ms/tick, %d alive, %d buildings, %d inventories, %d tasks" % [ticks, total, total / ticks, sim.alive_count(), sim.state["buildings"].size(), sim.state["inventories"].size(), sim.state["tasks"].size()])
	for k in keys:
		print("  %-22s %8.1f ms  %6.3f ms/tick  %4.1f%%" % [k, float(t[k]) / 1000.0, float(t[k]) / 1000.0 / ticks, 100.0 * float(t[k]) / 1000.0 / total])
	var jq = sim.jobs.get("jp")
	if jq != null:
		for k in jq.keys():
			print("  jobs.%-15s %s" % [k, str(jq[k]) if k.ends_with("#") else "%.3f ms/tick" % (float(jq[k]) / 1000.0 / ticks)])
	var ip = sim.inv.get("tp")
	if ip != null:
		for k in ip.keys():
			print("  inv.%-15s %s" % [k, str(ip[k]) if k.ends_with("#") else "%.3f ms/tick" % (float(ip[k]) / 1000.0 / ticks)])
	var up = sim.util.get("pt")
	if up != null:
		for k in up.keys():
			print("  util.%-15s %s" % [k, str(up[k]) if k.ends_with("#") else "%.3f ms/tick" % (float(up[k]) / 1000.0 / ticks)])
	var np = sim.nav.get("pp")
	if np != null:
		for k in np.keys():
			print("  nav.%-15s %s" % [k, str(np[k]) if k.ends_with("#") else "%.3f ms/tick" % (float(np[k]) / 1000.0 / ticks)])
	var ap = sim.agents.get("_aprof")
	if ap != null:
		for k in ap.keys():
			print("  act.%-15s %s" % [k, str(ap[k]) if k.ends_with("#") else "%.3f ms/tick" % (float(ap[k]) / 1000.0 / ticks)])
	var pr = sim.agents.get("prof")
	if pr != null:
		for k in pr.keys():
			print("  agents.%-15s %8.1f" % [k, float(pr[k]) / (1000.0 if not k.ends_with("#") else 1.0)])
	quit(0)

## The set-up of long_v3_perf_70_colonists (tests/cases_v3.gd), with the driver.
func _grow_v3perf(sim, ref) -> void:
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
		for i in 450:
			if int(sim.state["tick"]) % 10 == 0:
				ref.drive()
			sim.step()
	for i in 600:
		if int(sim.state["tick"]) % 10 == 0:
			ref.drive()
		sim.step()
	print("grown (v3perf): %d alive, %d buildings" % [sim.alive_count(), sim.state["buildings"].size()])

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
	print("grown: %d alive, %d buildings" % [sim.alive_count(), sim.state["buildings"].size()])
	sim.run_seconds(60.0)
	print("settled")

func _time(key: String, f: Callable) -> void:
	var t0: int = Time.get_ticks_usec()
	f.call()
	t[key] = int(t.get(key, 0)) + Time.get_ticks_usec() - t0

func _step(sim) -> void:
	sim.state["tick"] = int(sim.state["tick"]) + 1
	var tick: int = int(sim.state["tick"])
	var second: bool = tick % int(sim.bal["tick_hz"]) == 0
	_time("cmds", func(): sim.cmds.apply_pending())
	_time("env", func(): sim.util.env_tick())
	if second:
		_time("hazards", func(): sim.hazards.tick_second())
		_time("traffic", func(): sim.traffic.tick_second())
	if bool(sim.state["topo_dirty"]):
		_time("topo.rebuild", func(): sim.topo.rebuild(true))
	_time("power", func(): sim.util.power_tick())
	_time("water", func(): sim.util.water_tick())
	_time("atmo", func(): sim.util.atmo_tick())
	_time("needs", func(): sim.agents.needs_tick())
	if second:
		_time("build.second", func(): sim.build.tick_second())
		_time("upgrades.second", func(): sim.upgrades.tick_second())
		_time("ship.second", func(): sim.ship.tick_second())
		# jobs.tick_second() part by part, in its own order.
		var j = sim.jobs
		for part in ["_expire", "_index", "_gen_machine_inputs", "_gen_repair", "_gen_hazard_work", "_gen_research", "_gen_medical", "_gen_ship", "_gen_construction", "_gen_upgrades", "_gen_dining", "_gen_trade", "_gen_water_fill", "_gen_clearing", "_gen_operate", "_gen_tend", "_gen_demolish"]:
			_time("jobs." + part, func(): j.call(part))
		if int(sim.state["tick"]) % (10 * int(sim.bal["tick_hz"])) == 0:
			_time("jobs._clean_piles", func(): j._clean_piles())
	_time("think", func(): sim.agents.think_tick())
	_time("locks", func(): sim.agents.locks_tick())
	_time("act", func(): sim.agents.act_tick())
	_time("ship.tick", func(): sim.ship.tick())
	if second:
		_time("crops", func(): sim.prod.crops_second())
		_time("auto", func(): sim.prod.auto_second())
		_time("spoil", func(): sim.prod.spoil_second())
		_time("wear", func(): sim.prod.wear_second())
		_time("morale", func(): sim.agents.morale_second())
		_time("research", func(): sim.research.tick_second())
		var al = sim.alerts
		var found := {}
		for part in ["_power_issues", "_water_issues", "_air_issues", "_building_issues", "_people_issues", "_supply_issues", "_nutrition_issues", "_progress_issues", "_hazard_issues"]:
			_time("alerts." + part, func(): al.call(part, found))
		_time("alerts._merge", func(): al._merge(found))
		_time("metrics", func(): sim.metrics.tick_second())
		_time("goals", func(): sim.goals.tick_second())
		_time("awards", func(): sim.awards.tick_second())
