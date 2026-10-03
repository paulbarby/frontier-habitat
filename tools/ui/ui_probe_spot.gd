extends SceneTree
## Probe (UI, 2026-10-03): a free place near the camera of showcase_v5 for the build shots.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n < 6:
		return false
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	var f: Vector3 = main.rig.focus
	print("focus ", f, " center ", main.sim.world.center)
	print("spot habitat ", main._on_cmd("findspot habitat 1 40"))
	print("spot greenhouse ", main._on_cmd("findspot greenhouse 1 40"))
	quit(0)
	return true
