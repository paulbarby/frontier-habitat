extends SceneTree
## Developer tool: slope statistics of the v4 heights (spikes check).
const Sim = preload("res://sim/sim.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.new_game(int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 1001, "frontier")
	var w = sim.world
	var hn: int = w.hn
	var hist := {}
	var mx := 0.0
	for y in range(1, hn - 1):
		for x in range(1, hn - 1):
			var i: int = y * hn + x
			var h: float = w.heights[i]
			var s: float = maxf(maxf(absf(h - w.heights[i - 1]), absf(h - w.heights[i + 1])), maxf(absf(h - w.heights[i - hn]), absf(h - w.heights[i + hn]))) / w.hstep
			mx = maxf(mx, s)
			var b: int = mini(6, int(s / 0.5))
			hist[b] = int(hist.get(b, 0)) + 1
	print("max slope %.2f; histogram by 0.5: %s" % [mx, str(hist)])
	var mm := 0.0
	for y in range(1, hn - 1, 2):
		for x in range(1, hn - 1, 2):
			var p := Vector2(x * w.hstep, y * w.hstep)
			if w.near_mountain(p) > 0.0:
				continue
			var i: int = y * hn + x
			var h: float = w.heights[i]
			mm = maxf(mm, maxf(maxf(absf(h - w.heights[i - 1]), absf(h - w.heights[i + 1])), maxf(absf(h - w.heights[i - hn]), absf(h - w.heights[i + hn]))) / w.hstep)
	print("max slope on mountain ranges %.2f" % mm)
	quit(0)
