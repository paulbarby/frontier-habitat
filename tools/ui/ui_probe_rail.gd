extends SceneTree
## Probe (UI agent, 2026-10-01): the nav rail's height.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:
		root.size = Vector2i(1600, 900)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	if _n == 40:
		var nav = main.hud.nav
		print("rail ", nav.get_global_rect(), " min ", nav.get_combined_minimum_size(), " side ", nav._side, " off ", nav.offset_top)
		for c in nav._box.get_children():
			print("  ", c.get_class(), " ", c.name, " min ", (c as Control).get_combined_minimum_size())
		quit(0)
		return true
	return false
