extends SceneTree
## Developer tool: packs exterior plans as tightly as placement allows 25-70 m from the test base's
## airlock (seeds vary the pattern) and prints every plan that reach_info says is not in reach.
##   node tools/godot.mjs script res://tests/dev/reach_cluster.gd [seeds=5]
const H = preload("res://tests/helpers.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var seeds: int = int(a[0]) if a.size() > 0 else 5
	var defs := ["reservoir", "fuel_refinery", "water_extractor", "regolith_harvester", "battery", "solar_array", "wind_turbine", "comms_tower", "meteor_turret"]
	var total := 0
	var bad := 0
	for sd in seeds:
		var g = H.Game.new(1001, false)
		var sim = g.sim
		sim.new_game(1001, "frontier")
		sim.state["flags"]["unlock_all"] = true
		var res: Dictionary = H.layout(sim, H.CORE_STEPS + [{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"}])
		g.run(2)
		H.fill_utilities(sim, 1.0, 0.8, true)
		var lock: Dictionary = sim.state["buildings"][res["ids"]["L1"]]
		var door: Vector2 = sim.nav.door_pos(lock)
		var n := 0
		for y in range(-70, 71, 3):
			for x in range(-70, 71, 3):
				var p: Vector2 = sim.place.snap_pos(door + Vector2(x, y).rotated(0.3 * sd))
				var dd: float = p.distance_to(door)
				if dd < 20.0 or dd > 70.0:
					continue
				var def_id: String = defs[(n + sd) % defs.size()]
				if sim.place.check_building(def_id, p, 0.0) == "ok":
					if n % 3 == 0:
						var cr: Dictionary = g.cmd("place_building", {"def": def_id, "x": p.x, "y": p.y, "rot": 0.0})
					else:
						sim.build.spawn_active(def_id, p, 0.0)      # built neighbours
						sim.topo.mark_dirty()
					n += 1
		g.run(2)
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["state"] != "blueprint" or b["kind"] == "link":
				continue
			total += 1
			var ri: Dictionary = sim.agents.reach_info(b)
			if not bool(ri["ok"]):
				bad += 1
				print("seed %d: %s %d at %.0f m from the door: %s | access %d" % [sd, b["def"], int(id), (b["pos"] as Vector2).distance_to(door), ri["text"], sim.nav.access_points(b).size()])
		g.dispose()
	print("%d plans, %d not in reach" % [total, bad])
	quit(0)
