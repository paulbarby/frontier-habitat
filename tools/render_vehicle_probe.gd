extends SceneTree
## RENDER debug (V4 vehicles): frontier game, the vehicle demo, the crew chain and a drive,
## headless; prints the vehicle state every second of view time.
##   node tools/godot.mjs script res://tools/render_vehicle_probe.gd
var main
var n := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n == 3:
		main.start_new(1001, {"scenario": "frontier"})
		main.set_speed(0)
	if n == 6:
		var v = main.view
		print(v.debug_cmd("vdemo"))
		print(v.debug_cmd("vboard 1 1"), v.debug_cmd("vboard 1 2"), v.debug_cmd("vboard 2 1"))
	if n > 6:
		main.set_process(false)
		main._process(1.0 / 30.0)
		var f: int = n - 6
		if f == 30 * 5:
			var c: Vector2 = main.sim.world.center
			print("drive: ", main.view.debug_cmd("vdrive 1 %d %d" % [int(c.x) + 150, int(c.y) + 90]))
			print("drive: ", main.view.debug_cmd("vdrive 2 %d %d" % [int(c.x) - 120, int(c.y) + 160]))
			main.view.debug_cmd("vhop 3 %d %d" % [int(c.x) + 200, int(c.y) - 60])
			main.view.debug_cmd("vlaunch 4")
		if f % 30 == 0:
			print("t %2d %s" % [f / 30, main.view.debug_cmd("vinfo")])
		if f > 30 * 40:
			return true
	return false
