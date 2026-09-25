extends SceneTree
## RENDER debug: building records and the planner region of points in a save.
##   node tools/godot.mjs script res://tools/render_bld_probe.gd <save file> <id,id,...> [x:y ...]
var main
var n := 0
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n == 3:
		var a: PackedStringArray = OS.get_cmdline_user_args()
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/" + a[0]))
		return false
	if n < 8:
		main._process(1.0 / 30.0)
		return false
	var a2: PackedStringArray = OS.get_cmdline_user_args()
	var blds: Dictionary = main.sim.state["buildings"]
	for s in a2[1].split(","):
		var b: Dictionary = blds.get(int(s), {})
		var keys := ["id", "def", "kind", "pos", "radius", "rot", "p0", "p1", "a", "b", "length", "state"]
		var o := {}
		for k in keys:
			if b.has(k):
				o[k] = b[k]
		print("BLD ", s, " ", o)
	for i in range(2, a2.size()):
		var xy: PackedStringArray = a2[i].split(":")
		var p := Vector3(float(xy[0]), 0.8, float(xy[1]))
		var pl = main.view.npc.planner
		print("PT ", a2[i], " region in ", pl.region_of(p, true), " region out ", pl.region_of(p, false), " room_at ", main.view.npc._room_at(Vector2(p.x, p.z)))
	quit(0)
	return true
