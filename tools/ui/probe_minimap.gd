extends SceneTree
## Prints the minimap panel's child sizes (layout probe).
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		root.size = Vector2i(1600, 900)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	if _n == 20:
		var mm: Control = main.hud.minimap
		print("minimap ", mm.get_global_rect(), " min ", mm.get_combined_minimum_size())
		var v: Control = mm.get_child(mm.get_child_count() - 1) if not (mm.get_child(0) is Control) else mm.get_child(0)
		for c in mm.get_children():
			if c is Container:
				for k in c.get_children():
					if k is Control:
						print("  ", k.get_class(), " ", k.name, " size ", (k as Control).size, " min ", (k as Control).get_combined_minimum_size(), " vis ", (k as Control).visible)
						if k is HBoxContainer:
							for kk in k.get_children():
								print("     ", kk.get_class(), " min ", (kk as Control).get_combined_minimum_size())
		quit(0)
	return false
