extends SceneTree
## Lists interactive controls without a tooltip, in the HUD and on every screen (probe for the
## "rich tooltips on every control" task). Prints: place, class, text/icon, parent script.
##   node tools/godot.mjs script res://tools/ui/probe_tooltips.gd

const SCREENS := ["goals", "research", "dashboard", "inventory", "colonists", "awards", "menu", "settings", "saveload", "help", "newcolony", "codex", "victory"]
var main
var _n := 0
var _i := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

static func interactive(c: Control) -> bool:
	return c is BaseButton or c is LineEdit or c is Range and not (c is ScrollBar) and not (c is ProgressBar)

func report(place: String) -> void:
	var seen := {}
	for c in main.hud.root.find_children("*", "Control", true, false):
		var ctl: Control = c
		if not ctl.is_visible_in_tree() or not interactive(ctl):
			continue
		if ctl.tooltip_text != "":
			continue
		var label: String = ctl.get("text") if ctl.get("text") != null else ""
		var owner_script: String = ""
		var p: Node = ctl.get_parent()
		while p != null and owner_script == "":
			if p.get_script() != null and String(p.get_script().resource_path).begins_with("res://ui/"):
				owner_script = String(p.get_script().resource_path).get_file()
			p = p.get_parent()
		var key: String = "%s|%s|%s" % [ctl.get_class(), label, owner_script]
		seen[key] = int(seen.get(key, 0)) + 1
	for k in seen:
		print("%s: %s x%d" % [place, k, seen[k]])

var _phase := 0
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		root.size = Vector2i(1600, 900)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		main._on_cmd("speed 0")
		main._on_cmd("select research_lab")
		main._on_cmd("find lab")
		main._on_cmd("advisor")
	if _n > 12 and _n % 6 == 0:
		if _i == -1:
			report("HUD")
			main._on_cmd("closeall")
			_i = 0
			return false
		if _i >= SCREENS.size():
			print("DONE")
			quit(0)
			return false
		if _phase == 0:
			main._on_cmd("open " + SCREENS[_i])
			_phase = 1
		elif _phase == 1:
			report("screen " + SCREENS[_i])
			main._on_cmd("close")
			_phase = 0
			_i += 1
	return false