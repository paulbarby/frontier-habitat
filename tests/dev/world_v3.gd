extends SceneTree
## Developer tool: the 810 m map of a few seeds. World generation time, nav build time,
## buildable share for a room of radius 5, features, deposits and the Meridian.
##   node tools/godot.mjs script res://tests/dev/world_v3.gd [seed ...]

const Sim = preload("res://sim/sim.gd")
const WorldGen = preload("res://sim/world_gen.gd")

func _init() -> void:
	var seeds: Array = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			seeds.append(int(a))
	for a in OS.get_cmdline_args():
		if a.is_valid_int() and not seeds.has(int(a)):
			seeds.append(int(a))
	if seeds.is_empty():
		seeds = [1001, 1002, 1003, 1004, 1005]
	for s in seeds:
		var t0: int = Time.get_ticks_msec()
		var sim = Sim.new()
		sim.new_game(s)
		var total: int = Time.get_ticks_msec() - t0
		var w = sim.world
		var c: Vector2 = w.center
		print("seed %d: map %d m, world gen %d ms, nav base %d ms, new_game total %d ms" % [s, w.size, w.gen_msec, sim.nav.base_msec, total])
		print("  ridges %d, canyons %d, craters %d, flats %d, rocks %d, deposits %d" % [w.ridges.size(), w.canyons.size(), w.craters.size(), w.flats.size(), w.rocks.size(), w.deposit_sites.size()])
		var ex: Array = []
		for d in w.deposit_sites:
			var dd: float = Vector2(d["x"], d["y"]).distance_to(c)
			ex.append(("X" if bool(d.get("exotic", false)) else "") + str(int(dd)))
		print("  deposit distances: ", " ".join(ex))
		print("  basin %s  fault %s" % [str(w.basin), str(w.fault)])
		var ship: Dictionary = sim.ship.record()
		print("  meridian at %.1f m" % (ship["pos"] as Vector2).distance_to(c) if not ship.is_empty() else "  NO MERIDIAN")
		var t1: int = Time.get_ticks_msec()
		var ok := 0
		var n := 0
		var step := 6.0
		var y := step * 0.5
		while y < float(w.size):
			var x := step * 0.5
			while x < float(w.size):
				n += 1
				var p := Vector2(x, y)
				if _buildable(sim, p, 5.0):
					ok += 1
				x += step
			y += step
		print("  buildable (radius 5): %.1f %% of the map (%d samples, %d ms)" % [100.0 * ok / n, n, Time.get_ticks_msec() - t1])
		var plat := true
		for k in 64:
			var a: float = k * TAU / 64.0
			for r in [30.0, 60.0, 90.0, 115.0]:
				if w.slope_over(c + Vector2(cos(a), sin(a)) * r, 5.0) > 0.05:
					plat = false
		print("  plateau flat to 115 m: %s" % str(plat))
		var hz: Dictionary = w.hazard_at(c)
		print("  hazard at lander: %s" % str(hz))
		# Path timing: long trips.
		var t2: int = Time.get_ticks_msec()
		var found := 0
		for k in 20:
			var a: float = k * TAU / 20.0
			var r: Dictionary = sim.nav.path_out(c + Vector2(20, 0), c + Vector2(cos(a), sin(a)) * 300.0)
			if r["ok"]:
				found += 1
		print("  20 paths of about 300 m: %d found, %d ms" % [found, Time.get_ticks_msec() - t2])
		sim.dispose()
	quit(0)

func _buildable(sim, p: Vector2, r: float) -> bool:
	var w = sim.world
	if not w.in_map(p, float(w.margin) + r):
		return false
	for rock in w.rocks:
		if Vector2(rock["x"], rock["y"]).distance_to(p) < r + float(rock["r"]) + 0.3:
			return false
	return w.slope_over(p, r) <= float(sim.bal["max_slope_rooms"])
