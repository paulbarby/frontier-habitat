extends SceneTree
## Finds what makes the inspector wider than its design width: prints the deepest controls whose
## minimum width is more than the content width, per selected type and tab.
##   node tools/godot.mjs script res://tools/ui/probe_insp_width.gd

var main
var _n := 0
var _i := 0
const PICKS := ["research_lab", "kitchen", "farm", "habitat", "oxygen_plant", "landing_pad", "agent"]

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _walk(c: Node, limit: float, depth: int, out: Array) -> void:
	if not (c is Control) or not (c as Control).visible:
		return
	var ctl: Control = c
	var w: float = ctl.get_combined_minimum_size().x
	if w <= limit:
		return
	var deeper := false
	for k in c.get_children():
		if k is Control and (k as Control).visible and (k as Control).get_combined_minimum_size().x > limit:
			deeper = true
			_walk(k, limit, depth + 1, out)
	if not deeper:
		var txt := ""
		if ctl is Label:
			txt = (ctl as Label).text
		elif ctl is Button:
			txt = (ctl as Button).text
		out.append("%s %s w=%d '%s'" % [ctl.get_class(), ctl.name, int(w), txt.left(60)])

func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		root.size = Vector2i(1600, 900)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		main._on_cmd("speed 0")
	if _n > 10 and _n % 6 == 0:
		if _i >= PICKS.size() * 2:
			quit(0)
			return false
		var pick: String = PICKS[_i / 2]
		if _i % 2 == 0:
			print(main._on_cmd("select " + pick) if pick != "agent" else main._on_cmd("select agent"))
		else:
			var insp: Control = main.hud.inspector
			var tabs: Array = insp._tabs.get_children()
			print("== %s size %s tabs %d" % [pick, str(insp.size), tabs.size()])
			for tb in [null] + tabs:
				if tb != null:
					(tb as Button).pressed.emit()
					insp.refresh()
				var out: Array = []
				_walk(insp, 350.0 + 42.0, 0, out)
				print("  tab %s: %s" % [(tb as Button).text if tb != null else "-", str(out)])
		_i += 1
	return false
