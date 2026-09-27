extends SceneTree
## Rich tooltips and clipped lines (coordinator 2026-09-27), headless:
##   node tools/godot.mjs script res://tools/ui/test_tooltips_clip.gd
## In the HUD (with the inspector, Find and advisor open) and on every screen, in a 1280x720 window
## (the canvas scale is 0.8, so the text floor is on):
## - every button, check box, slider and text field has a tooltip;
## - no label cuts its text silently: a clipped one-line label shows an ellipsis (and its tooltip),
##   other labels wrap.

const SCREENS := ["goals", "research", "dashboard", "inventory", "colonists", "awards", "menu", "settings", "saveload", "help", "newcolony", "codex", "vehicles", "victory"]
var main
var fails := 0
var _n := 0
var _i := -1
var _phase := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

static func interactive(c: Control) -> bool:
	return c is BaseButton or c is LineEdit or (c is Range and not (c is ScrollBar) and not (c is ProgressBar))

func scan(place: String) -> void:
	var no_tip: Array = []
	var cut: Array = []
	for c in main.hud.root.find_children("*", "Control", true, false):
		var ctl: Control = c
		if not ctl.is_visible_in_tree():
			continue
		if interactive(ctl) and ctl.tooltip_text == "" and not (ctl is LineEdit and ctl.get_parent() is SpinBox and (ctl.get_parent() as Control).tooltip_text != ""):
			no_tip.append("%s '%s'" % [ctl.get_class(), str(ctl.get("text")) if ctl.get("text") != null else ""])
		if ctl is Label:
			var l: Label = ctl
			if l.clip_text and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and l.autowrap_mode == TextServer.AUTOWRAP_OFF:
				var f: Font = l.get_theme_font("font")
				var w: float = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
				if w > l.size.x + 1.0:
					cut.append("'%s' (%d > %d px)" % [l.text.left(30), int(w), int(l.size.x)])
	check("%s: every control has a tooltip" % place, no_tip.is_empty(), str(no_tip.slice(0, 6)))
	check("%s: no line cut without an ellipsis" % place, cut.is_empty(), str(cut.slice(0, 6)))

func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		root.size = Vector2i(1280, 720)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		main._on_cmd("speed 0")
		main._on_cmd("select research_lab")
		main._on_cmd("find lab")
		main._on_cmd("advisor")
	if _n > 14 and _n % 6 == 0:
		if _i == -1:
			scan("HUD")
			main._on_cmd("closeall")
			main._on_cmd("select kitchen")
			main.hud.orders.visible = true
			main._on_cmd("reactor")
			_i = -2
			return false
		if _i == -2:
			scan("HUD, kitchen inspector, orders and reactor windows")
			main._on_cmd("closeall")
			_i = 0
			return false
		if _i >= SCREENS.size():
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
			return false
		if _phase == 0:
			main._on_cmd("open " + SCREENS[_i])
			_phase = 1
		else:
			scan("screen " + SCREENS[_i])
			main._on_cmd("close")
			_phase = 0
			_i += 1
	return false
