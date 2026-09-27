extends SceneTree
## RENDER debug (V4 terrain): starts a "frontier" game (SIM's 2,560 m planet) headless and prints
## the view build timings, the feature layout and SIM's sun visibility at a deep crater.
##   node tools/godot.mjs script res://tools/render_v4_probe.gd [seed]
var main
var n := 0
var seed := 1001

func _initialize() -> void:
	for s in OS.get_cmdline_user_args():
		if s.is_valid_int():
			seed = int(s)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n == 3:
		var t0: int = Time.get_ticks_usec()
		main.start_new(seed, {"scenario": "frontier"})
		print("start_new %.0f ms (world gen %s ms), view setup %.0f ms" % [(Time.get_ticks_usec() - t0) / 1000.0, str(main.sim.world.gen_msec), main.view._setup_ms])
		main.set_speed(0)
	if n == 6:
		print(main.view.debug_cmd("v4info"))
		var w = main.sim.world
		var dc: Dictionary = w.deep_craters[0]
		var c := Vector2(float(dc["x"]), float(dc["y"]))
		for t in [30.0, 90.0, 180.0, 270.0, 330.0]:
			var s: Dictionary = w.sun_angles(t, 360.0, 600.0)
			print("t %3.0f sun %.1f deg bearing %.2f | floor vis %.2f | rim vis %.2f" % [t, s["elev_deg"], s["bearing"], w.sun_vis(c, s["elev_deg"], s["bearing"]), w.sun_vis(c + Vector2(float(dc["r"]) + 10.0, 0), s["elev_deg"], s["bearing"])])
		print("sky_open floor %.2f, plain %.2f" % [main.view.v4.sky_open(c.x, c.y), main.view.v4.sky_open(w.center.x, w.center.y)])
		print("rocks %d (kind 3: %d)" % [w.rocks.size(), w.rocks.filter(func(r): return int(r["kind"]) == 3).size()])
		return true
	return false
