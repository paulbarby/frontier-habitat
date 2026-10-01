extends SceneTree
## Probe (UI agent, 2026-10-01): what makes a dock tab wider than the dock.
var main
var _n := 0
var _tabs := ["alerts", "events", "traffic", "goals", "requests"]
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _dump(c: Node, depth: int, lim: float) -> void:
	if depth > 18 or not (c is Control) or not (c as Control).visible:
		return
	var w: float = (c as Control).get_combined_minimum_size().x
	if w < lim:
		return
	var t := ""
	if c is Label:
		t = " '" + (c as Label).text.left(30) + "'"
	elif c is Button:
		t = " [" + (c as Button).text.left(20) + "]"
	print("%s%s %s min=%.0f%s" % ["  ".repeat(depth), c.get_class(), c.name, w, t])
	for ch in c.get_children():
		_dump(ch, depth + 1, lim)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:
		root.size = Vector2i(1280, 720)
		root.content_scale_size = Vector2i.ZERO
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
		main._on_cmd("unrest protest")
		main.boot["debug"] = "1"
		main._on_cmd("uimock all")
		main._on_cmd("uiscale 1")
	var k: int = (_n - 30) / 20
	if _n >= 30 and (_n - 30) % 20 == 0 and k < _tabs.size():
		main.hud.panels.open_tab(_tabs[k], true)
	if _n >= 30 and (_n - 30) % 20 == 19 and k < _tabs.size():
		print("TAB ", _tabs[k], " width ", main.hud.panels._width)
		_dump(main.hud.panels._pages[_tabs[k]], 0, main.hud.panels._width - 90.0)
	if _n > 30 + 20 * _tabs.size():
		quit(0)
		return true
	return false
