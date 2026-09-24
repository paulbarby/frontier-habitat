extends SceneTree
## Developer tool: time long outdoor paths on the 810 m map, with and without jumping.
##   node tools/godot.mjs script res://tests/dev/path_probe.gd [seed]

const Sim = preload("res://sim/sim.gd")

func _init() -> void:
	var s := 1001
	for a in OS.get_cmdline_args():
		if a.is_valid_int():
			s = int(a)
	var sim = Sim.new()
	sim.new_game(s)
	var c: Vector2 = sim.world.center
	var g: AStarGrid2D = sim.nav.grid
	for jump in [true, false]:
		g.jumping_enabled = jump
		g.update() if false else null
		var total := 0
		var worst := 0
		var lens: Array = []
		for k in 20:
			var a: float = k * TAU / 20.0
			var from: Vector2i = sim.nav.cell_of(c + Vector2(20, 0))
			var to: Vector2i = sim.nav.cell_of(c + Vector2(cos(a), sin(a)) * 300.0)
			var t0: int = Time.get_ticks_usec()
			var raw: PackedVector2Array = g.get_point_path(from, to)
			var dt: int = Time.get_ticks_usec() - t0
			total += dt
			worst = maxi(worst, dt)
			var l := 0.0
			for i in range(1, raw.size()):
				l += raw[i].distance_to(raw[i - 1])
			lens.append("%d:%d/%dus" % [k, int(l), dt])
		print("jumping %s: total %d us, worst %d us" % [str(jump), total, worst])
		print("  ", " ".join(lens))
	# A path to an enclosed cell (fails): the worst case.
	g.jumping_enabled = true
	var t1: int = Time.get_ticks_usec()
	var bad: Vector2i = Vector2i(int(sim.world.rocks[0]["x"]), int(sim.world.rocks[0]["y"]))
	var r: PackedVector2Array = g.get_point_path(sim.nav.cell_of(c + Vector2(20, 0)), bad)
	print("to a solid cell: %d points, %d us" % [r.size(), Time.get_ticks_usec() - t1])
	sim.dispose()
	quit(0)
