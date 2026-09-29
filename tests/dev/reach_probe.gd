extends SceneTree
## Developer tool (Paul: "OUT OF REACH" 30-50 m from an airlock): a Frontier game with the small
## test base, exterior plans 20-50 m from its airlock, one game day; prints each plan's state,
## block and the path details from the airlock door to its access points.
##   node tools/godot.mjs script res://tests/dev/reach_probe.gd [seed]
const H = preload("res://tests/helpers.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var seed_v: int = int(a[0]) if a.size() > 0 else 1001
	var g = H.Game.new(seed_v, false)
	var sim = g.sim
	sim.new_game(seed_v, "frontier")
	sim.state["flags"]["unlock_all"] = true
	var res: Dictionary = H.layout(sim, H.CORE_STEPS + [{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"}])
	print("layout errors ", res["errors"])
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.8, true)
	var lock: Dictionary = sim.state["buildings"][res["ids"]["L1"]]
	var door: Vector2 = sim.nav.door_pos(lock)
	print("airlock at %s door %s; suit reach %.1f m, suit cap %.0f s, out speed %.2f" % [str(lock["pos"]), str(door), sim.agents.suit_reach_metres(), sim.agents.suit_cap(), sim.util.out_speed()])
	var plans := {}
	var defs := ["reservoir", "fuel_refinery", "water_extractor", "regolith_harvester", "battery", "solar_array", "wind_turbine", "comms_tower"]
	var k := 0
	for def_id in defs:
		for r in [22.0, 30.0, 38.0, 46.0, 54.0]:
			var placed := false
			for j in 24:
				var p: Vector2 = sim.place.snap_pos(door + Vector2.RIGHT.rotated(float(j + k * 3) * TAU / 24.0) * r)
				if sim.place.check_building(def_id, p, 0.0) == "ok":
					var cr: Dictionary = g.cmd("place_building", {"def": def_id, "x": p.x, "y": p.y, "rot": 0.0})
					if bool(cr["ok"]):
						plans[int(cr["id"])] = p.distance_to(door)
						placed = true
						break
			if placed:
				break
		k += 1
	sim.inv.add_new_forced(int(sim.state["buildings"][sim.state["lander_id"]]["inv_out"]), "metal", 200, "test")
	sim.inv.add_new_forced(int(sim.state["buildings"][sim.state["lander_id"]]["inv_out"]), "electronics", 40, "test")
	sim.inv.add_new_forced(int(sim.state["buildings"][sim.state["lander_id"]]["inv_out"]), "polymer", 100, "test")
	for s in 12:
		g.run(500)
		H.fill_utilities(sim, 1.0, 0.8, true)
	for id in plans:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty():
			continue
		var pts: Array = sim.nav.access_points(b)
		var best := ""
		for q in pts:
			var rt: Dictionary = sim.nav.plan({"b": -1, "p": door}, {"b": -1, "p": q})
			best += " [%s ok %s len %.0f]" % [str((q as Vector2).round()), str(rt["ok"]), float(rt.get("len", -1.0))]
		print("%s %d at %.0f m: state %s block '%s' unreach_rev %d/%d access %d%s" % [b["def"], int(id), float(plans[id]), b["state"], b["block"], int(b["unreach_rev"]), int(sim.state["rev"]["walk"]), pts.size(), best])
	g.dispose()
	quit(0)
