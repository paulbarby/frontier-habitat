extends SceneTree
## Developer tool: the V4 perf budget (100 colonists + 6 vehicles on the 2,560 m map). Prints the
## colony size, the time per tick in 1000-tick windows and a profile of the systems.
##   node tools/godot.mjs script res://tests/dev/v4_perf.gd [days=12] [pop=100]
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var days: int = int(args[0]) if args.size() > 0 else 12
	var pop_want: int = int(args[1]) if args.size() > 1 else 100
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	g.ref = Reference.new(sim, "all")
	var t0: int = Time.get_ticks_msec()
	g.run_to_tick(days * 6000)
	print("day %d: pop %d, structures %d, %.0f s" % [days, sim.alive_count(), sim.state["buildings"].size(), float(Time.get_ticks_msec() - t0) / 1000.0])
	sim.state["flags"]["unlock_all"] = true
	var guard := 0
	while sim.alive_count() < pop_want and guard < 40:
		guard += 1
		g.cmd("admit_settlers", {"count": mini(8, pop_want - sim.alive_count())})
		g.run(250)
	g.run(300)
	print("pop %d" % sim.alive_count())
	var free: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] != "visitor":
			free.append(a)
	var c: Vector2 = sim.world.center
	for k in 6:
		var kind: String = "hopper" if k == 5 else ("small_rover" if k % 2 == 0 else "medium_rover")
		var p = sim.nav.nearest_walkable(c + Vector2.RIGHT.rotated(k * TAU / 6.0) * 160.0, 10)
		var r: Dictionary = g.cmd("spawn_vehicle", {"kind": kind, "x": p.x, "y": p.y})
		var v: Dictionary = sim.vehicles.get_v(int(r["id"]))
		var a: Dictionary = free[k]
		H.put_outside(sim, a, v["pos"] + Vector2(2, 0), sim.agents.suit_cap())
		sim.vehicles.board(a, int(v["id"]))
		g.cmd("vehicle_explore", {"id": int(v["id"]), "x": v["pos"].x, "y": v["pos"].y, "r": 600.0})
	g.run(300)
	var wins: Array = []
	for w in 3:
		var t1: int = Time.get_ticks_usec()
		g.run(1000)
		wins.append(float(Time.get_ticks_usec() - t1) / 1000.0 / 1000.0)
	var moving := 0
	for vid in sim.vehicles.ids():
		if sim.vehicles.get_v(vid)["state"] == "driving":
			moving += 1
	print("pop %d, structures %d, vehicles %d (%d driving), ms per tick %s" % [sim.alive_count(), sim.state["buildings"].size(), sim.vehicles.count(), moving, str(wins)])
	var causes := {}
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		if ag["state"] == "dead":
			causes[ag["cause"]] = int(causes.get(ag["cause"], 0)) + 1
	print("deaths ", causes)
	var f: Dictionary = sim.metrics.forecast()
	print("beds %d meals %d o2 %.1f/%.1f" % [int(f["beds"]), int(f["meals"]), float(f["o2_make"]), float(f["o2_need"])])
	g.dispose()
	quit(0)
