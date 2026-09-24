extends SceneTree
## Developer tool: power components of the grown 70-colonist colony (sizes, kinds).
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

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
	sim.run_seconds(2.0)
	var sizes := {}
	for comp in sim.topo.power_members:
		var n: int = (sim.topo.power_members[comp] as Array).size()
		sizes[n] = int(sizes.get(n, 0)) + 1
	print("components by size: ", sizes)
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		sim.util.power_tick()
	print("power_tick alone: %.3f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0 / 1000.0))
	quit(0)
