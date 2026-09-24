extends SceneTree
## Developer tool: the long_perf colony (reference campaign to day 12, grown to 70) and
## what kills people in it.   node tools/godot.mjs script res://tests/dev/grow_deaths.gd [hazards]

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var hz_set := "normal"
	for a in OS.get_cmdline_user_args():
		if a in ["off", "mild", "normal", "hard"]:
			hz_set = a
	var sim = Sim.new()
	sim.new_game(1001, "tutorial", {"hazards": hz_set})
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
	for i in 4:
		sim.submit("admit_settlers", {"count": 12})
	sim.submit("admit_settlers", {"count": 2})
	var logged: int = int(sim.state["tick"])
	for k in 8:
		sim.run_seconds(60.0)
		var f: Dictionary = sim.metrics.forecast()
		print("t+%d s: alive %d beds %d meals %d water %.0f" % [(k + 1) * 60, sim.alive_count(), int(f["beds"]), int(f["meals"]), float(f["water"])])
	for e in sim.state["log"]:
		if int(e["tick"]) > logged and e["code"] in ["death", "hazard_impact", "breach", "fault", "alert"]:
			print("  t=%d %s: %s" % [int(e["tick"]) / 10, e["code"], e["text"]])
	quit(0)
