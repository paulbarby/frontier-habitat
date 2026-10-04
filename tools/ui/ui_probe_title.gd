extends SceneTree
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main.leave_title()
	if _n == 20:
		print("go title")
		main.hud.watch.start()
	if _n == 40:
		print("start watch")
		main.hud.watch.stop()
	if _n == 60:
		quit(0)
	return false
