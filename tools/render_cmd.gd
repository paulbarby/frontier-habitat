extends SceneTree
## RENDER (debug): runs a save headless with fixed 1/60 s frames and sends commands at set frames.
##   node tools/godot.mjs script res://tools/render_cmd.gd <save> "<frame>:<cmd>|<frame>:<cmd>|..." [view|main]
## A command goes to main.cmd (game commands: zoom, pitch, speed) or, prefixed with "v ", to world_view.debug_cmd;
## each reply is printed.
var main
var f := 0
var save := ""
var steps: Array = []
var last := 0
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	save = a[0]
	for s in a[1].split("|"):
		var k: int = s.find(":")
		steps.append([int(s.left(k)), s.substr(k + 1)])
		last = maxi(last, int(s.left(k)))
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		return false
	if f > 2:
		# fixed 1/60 s frames (the sim and the view advance as in the game at 60 fps)
		main.set_process(false)
		main._process(1.0 / 60.0)
	for st in steps:
		if int(st[0]) == f:
			var c: String = st[1]
			var r
			if c == "debugon":
				main.boot["debug"] = "1"
				main.sim.state["options"]["debug"] = true
				r = "debug on"
			elif c.begins_with("ship "):
				main.sim.state["options"]["debug"] = true
				main.submit("traffic_now", {"kind": c.get_slice(" ", 1), "in": float(c.get_slice(" ", 2))})
				r = "submitted"
			elif c.begins_with("v "):
				r = main.view.debug_cmd(c.substr(2))
			else:
				r = main._on_cmd(c)
			print("CMD %d %s -> %s" % [f, c, str(r)])
	return f > last
