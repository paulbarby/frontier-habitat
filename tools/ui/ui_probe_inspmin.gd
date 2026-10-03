extends SceneTree
## Probe (UI, 2026-10-03): the minimum widths of the inspector's rows in a narrow view.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		root.size = Vector2i(1280, 720)
		root.content_scale_size = Vector2i.ZERO
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
	if _n == 20:
		main._on_cmd("select research_lab upgrade")
	if _n == 40:
		var ins = main.hud.inspector
		print("scroll custom ", ins._scroll.custom_minimum_size, " size ", ins._scroll.size, " body min ", ins._body.get_combined_minimum_size(), " wa ", main.hud.wm.work_area())
		print("width ", ins.width, " rect ", ins.get_global_rect(), " min ", ins.get_combined_minimum_size())
		var v: Control = ins.get_child(0)
		for c in v.get_children():
			print("  ", c.get_class(), " vis ", c.visible, " min ", (c as Control).get_combined_minimum_size())
			if c is HBoxContainer or c is HFlowContainer:
				for k in c.get_children():
					print("      ", k.get_class(), " min ", (k as Control).get_combined_minimum_size(), " ", k.name)
		quit(0)
		return true
	return false
