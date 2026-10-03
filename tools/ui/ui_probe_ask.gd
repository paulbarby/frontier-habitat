extends SceneTree
## Probe (UI, 2026-10-03): the size parts of the remove question in the hint.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
		root.size = Vector2i(1280, 720)
	if _n == 20:
		var bid := -1
		for id in main.sim.state["buildings"]:
			if String(main.sim.state["buildings"][id]["def"]) == "habitat":
				bid = int(id)
				break
		main.start_demolish()
		main.hud.ask_demolish(bid)
	if _n == 40:
		var h = main.hud.hint
		print("hint ", h.get_global_rect(), " min ", h.get_combined_minimum_size())
		for c in h._confirm_box.get_children():
			if c is HBoxContainer:
				for k in c.get_children():
					print("     kid ", k.get_class(), " min ", (k as Control).get_combined_minimum_size(), " ", k.name)
			print("  ", c.get_class(), " ", c.get_global_rect(), " min ", (c as Control).get_combined_minimum_size(), (" text " + (c as Label).text.left(80)) if c is Label else "")
		print("pending lines: ", h.pending.get("lines"))
		quit(0)
		return true
	return false
