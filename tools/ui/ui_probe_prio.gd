extends SceneTree
## Probe (UI, 2026-10-03): x of the Priorities columns in the header, the colony row and a list row.
##   node tools/godot.mjs script res://tools/ui/ui_probe_prio.gd
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
	if _n == 20:
		main._on_cmd("open colonists")
		main._on_cmd("tab priorities")
	if _n == 40:
		var top = main.hud.screens.top_screen()
		for l in top.content.find_children("*", "Label", true, false):
			if (l as Label).text in ["CONSTRUCTION", "FOOD", "RESET", "All colonists", "Technician"]:
				print("label %s x=%.1f w=%.1f" % [(l as Label).text, (l as Label).global_position.x, (l as Label).size.x])
		var shown := 0
		for b in top.content.find_children("*", "Button", true, false):
			if b.has_meta("job") and shown < 4:
				print("cell %s agent=%s x=%.1f w=%.1f" % [b.get_meta("job"), str(b.get_meta("agent")) if b.has_meta("agent") else "colony", (b as Button).global_position.x, (b as Button).size.x])
				shown += 1
		var ids: Array = []
		for k in main.sim.state["agents"]:
			if String(main.sim.state["agents"][k]["name"]).begins_with("Asha Verrin") or String(main.sim.state["agents"][k]["name"]).begins_with("Bram Achebe"):
				ids.append("%s=%s" % [str(k), main.sim.state["agents"][k]["name"]])
		print("ids ", ids)
		quit(0)
	return false
