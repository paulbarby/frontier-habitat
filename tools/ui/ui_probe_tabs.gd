extends SceneTree
## Probe (UI, 2026-10-02): the dock tab buttons: widths, columns, rows, at the logical sizes the web build uses.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
		main._on_cmd("uiscale 0.8")
		for t in main.hud.panels.TYPES:
			main.hud.panels.post(t, "Test message of type %s." % t, "info")
	var sizes := [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1366, 768)]
	if _n >= 12 and _n % 12 == 0 and (_n / 12 - 1) < sizes.size():
		root.size = sizes[_n / 12 - 1]
		root.content_scale_size = Vector2i.ZERO
	if _n >= 20 and _n % 12 == 8 and _n < 60:
		var pm = main.hud.panels
		var ws: Array = []
		for id in pm._tab_btn:
			ws.append("%s %.0f" % [id, (pm._tab_btn[id] as Control).get_combined_minimum_size().x])
		print("vp ", root.size, " width ", pm._width, " cols ", pm._tabbar.columns, " tabbar h ", pm._tabbar.size.y, " dock h ", pm._dock.size.y, " body h ", pm._body.size.y, " | ", ", ".join(ws))
	if _n > 62:
		quit(0)
		return true
	return false
