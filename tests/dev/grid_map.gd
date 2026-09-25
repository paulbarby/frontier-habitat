extends SceneTree
## Developer tool: ASCII map of the walking grid round the base at a tick
## ('#' solid, '+' weighted, '.' open, 'o' a path from A to B).
##   node tools/godot.mjs script res://tests/dev/grid_map.gd <tick> x0 y0 x1 y1 ax ay bx by
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var target: int = int(a[0])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(target)
	var x0 := int(a[1]); var y0 := int(a[2]); var x1 := int(a[3]); var y1 := int(a[4])
	var path := {}
	if a.size() > 8:
		var r: Dictionary = sim.nav.path_out(Vector2(float(a[5]), float(a[6])), Vector2(float(a[7]), float(a[8])))
		print("path ok %s len %s" % [str(r["ok"]), str(r.get("len"))])
		if r["ok"]:
			var pts: Array = r["pts"]
			for i in range(1, pts.size()):
				for k in 20:
					var q: Vector2 = (pts[i - 1] as Vector2).lerp(pts[i], k / 20.0)
					path[Vector2i(int(q.x), int(q.y))] = true
	for y in range(y0, y1):
		var line := "%3d " % y
		for x in range(x0, x1):
			var c := Vector2i(x, y)
			if path.has(c):
				line += "o"
			elif sim.nav.grid.is_point_solid(c):
				line += "#"
			elif sim.nav.grid.get_point_weight_scale(c) > 1.0:
				line += "+"
			else:
				line += "."
		print(line)
	quit(0)
