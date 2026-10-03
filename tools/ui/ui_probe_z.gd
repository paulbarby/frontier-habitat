extends SceneTree
## Probe (UI): the children of the HUD root, in drawing order (the last is on top).
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		root.size = Vector2i(1920, 1080)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
	if _n == 40:
		main.hud.work.visible = true
	if _n == 60:
		var i := 0
		for c in main.hud.hud_root.get_children():
			if c is Control and (c as Control).visible:
				print(i, " ", c.name, " ", c.get_class(), " ", (c as Control).get_global_rect())
			i += 1
		print("work index ", main.hud.work.get_index(), " inspector ", main.hud.inspector.get_index(), " inspector visible ", main.hud.inspector.visible)
		quit(0)
	return false
