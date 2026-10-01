extends SceneTree
## Probe (UI agent, 2026-10-01): the panel manager's layout chain after a request.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _chain(c: Control) -> void:
	var n: Node = c
	while n != null and n is Control:
		print("  %s %s vis=%s rect=%s min=%s" % [n.get_class(), n.name, (n as Control).visible, str((n as Control).get_global_rect()), str((n as Control).get_combined_minimum_size())])
		n = n.get_parent()
func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:
		root.size = Vector2i(1600, 900)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
		main._on_cmd("speed 0")
		var s = main.sim
		var ids: Array = s.state["agents"].keys()
		s.relations.add_request("shared_home", s.state["agents"][ids[0]], s.state["agents"][ids[1]], "Test pair want a shared home.")
		main.hud.request_card.update()
		main.hud.panels.open_tab("requests", true)
	if _n == 30 or _n == 60:
		print("frame ", _n)
		_chain(main.hud.request_card)
	if _n == 61:
		quit(0)
		return true
	return false
