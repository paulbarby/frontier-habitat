extends SceneTree
## Probe (UI agent, 2026-10-01): prints the minimum width tree of a screen at an interface scale.
##   node tools/godot.mjs script res://tools/ui/ui_probe_screen_width.gd <scale> <screen> [tab]
var main
var _n := 0
var _args: PackedStringArray

func _init() -> void:
	_args = OS.get_cmdline_user_args()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _dump(c: Node, depth: int, lim: float) -> void:
	if depth > 14 or not (c is Control):
		return
	var w: float = (c as Control).get_combined_minimum_size().x
	if w < lim:
		return
	print("%s%s %s min=%.0f size=%.0f" % ["  ".repeat(depth), c.get_class(), c.name, w, (c as Control).size.x])
	for ch in c.get_children():
		_dump(ch, depth + 1, lim)

func _process(_d: float) -> bool:
	_n += 1
	if _n == 5:
		main.boot["debug"] = "1"
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		main._on_cmd("speed 0")
		main._on_cmd("uimock all")
		root.size = Vector2i(int(_args[3]) if _args.size() > 3 else 1920, int(_args[4]) if _args.size() > 4 else 1080)
		root.content_scale_size = Vector2i.ZERO
		main._on_cmd("uiscale %s" % _args[0])
	if _n == 25:
		var arg = null if _args.size() < 3 or _args[2] == "-" else _args[2]
		main.hud.open_screen(_args[1], arg)
	if _n == 40:
		var top = main.hud.screens.top_screen()
		print("view ", main.hud.root.get_viewport_rect().size, " area ", top._scroll.size.x, " content ", top.content.get_combined_minimum_size().x)
		_dump(top.content, 0, float(_args[5]) if _args.size() > 5 else 300.0)
		quit(0)
		return true
	return false
