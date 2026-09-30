extends SceneTree
## Probe (UI agent, 2026-10-01): content width against area for every screen, in a view.
##   node tools/godot.mjs script res://tools/ui/ui_probe_all_widths.gd <w> <h> <scale>
const SCREENS := [["menu", null], ["settings", null], ["saveload", null], ["help", null], ["newcolony", null],
	["research", null], ["research", "labs"], ["goals", null], ["awards", null], ["dashboard", null], ["dashboard", "life"], ["dashboard", "food"], ["dashboard", "hazards"],
	["dashboard", "industry"], ["dashboard", "population"], ["dashboard", "research"], ["inventory", null], ["colonists", null], ["colonists", "priorities"], ["colonists", "visitors"], ["shuttle", 9102], ["trade", null]]
var main
var _n := 0
var _i := -1
var _args: PackedStringArray

func _init() -> void:
	_args = OS.get_cmdline_user_args()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	_n += 1
	if _n == 5:
		main.boot["debug"] = "1"
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		main._on_cmd("speed 0")
		main._on_cmd("uimock all")
		root.size = Vector2i(int(_args[0]), int(_args[1]))
		root.content_scale_size = Vector2i.ZERO
		main._on_cmd("uiscale %s" % _args[2])
	if _n < 25:
		return false
	var k: int = (_n - 25) % 10
	if k == 0:
		_i += 1
		if _i >= SCREENS.size():
			quit(0)
			return true
		main.hud.open_screen(SCREENS[_i][0], SCREENS[_i][1])
	elif k == 9:
		var top = main.hud.screens.top_screen()
		var cw: float = top.content.get_combined_minimum_size().x
		print("%s %s %s: content %.0f area %.0f (view %s)" % ["BAD " if cw > top._scroll.size.x + 0.5 else "ok  ", SCREENS[_i][0], str(SCREENS[_i][1]), cw, top._scroll.size.x, str(main.hud.root.get_viewport_rect().size)])
		if top._hdr_row != null:
			var hsc: Control = top._hdr_row.get_parent()
			print("     header %s row %.0f clip %.0f" % ["BAD" if top._hdr_row.get_combined_minimum_size().x > hsc.size.x + 0.5 else "ok", top._hdr_row.get_combined_minimum_size().x, hsc.size.x])
		main.hud.close_modal()
	return false
