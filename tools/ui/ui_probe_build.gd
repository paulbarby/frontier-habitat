extends SceneTree
## Probe (UI, 2026-10-03): the rects of the bottom rows (tab row, palette, hint) at the test sizes and scales.
var main
var _n := 0
var _cases: Array = []
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
		for s in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
			for sc in [0.8, 1.0, 1.4]:
				_cases.append([s, sc])
	if _n > 8 and (_n - 9) % 40 == 0 and (_n - 9) / 40 < _cases.size():
		var c: Array = _cases[(_n - 9) / 40]
		root.size = c[0]
		root.content_scale_size = Vector2i.ZERO
		main._on_cmd("uiscale %s" % str(c[1]))
		main.cancel_tool()
		main.hud.build_bar.close_drawer()
	if _n > 8 and (_n - 9) % 40 == 12 and (_n - 9) / 40 < _cases.size():
		main.hud.build_bar.toggle_tab("industry")
	if _n > 8 and (_n - 9) % 40 == 22 and (_n - 9) / 40 < _cases.size():
		var bb = main.hud.build_bar
		var c: Array = _cases[(_n - 9) / 40]
		var vp: Vector2 = main.hud.root.get_viewport_rect().size
		print("CASE ", c[0], " ", c[1], " view ", vp, " zone ", Rect2(vp * 0.25, vp * 0.5), " tabs ", bb._tab_panel.get_global_rect(), " drawer ", bb._drawer.get_global_rect(), " vis ", bb._drawer.visible)
		main.start_place("refinery", 1)
	if _n > 8 and (_n - 9) % 40 == 32 and (_n - 9) / 40 < _cases.size():
		var vp: Vector2 = main.hud.root.get_viewport_rect().size
		print("   placing: hint ", main.hud.hint.get_global_rect(), " vis ", main.hud.hint.visible, " drawer vis ", main.hud.build_bar._drawer.visible)
	if _n > 9 + 40 * _cases.size() + 5 and _cases.size() > 0:
		quit(0)
		return true
	return false
