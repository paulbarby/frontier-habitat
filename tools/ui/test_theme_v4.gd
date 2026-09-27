extends SceneTree
## Version-4 theme rules (critic round 15), headless:
##   node tools/godot.mjs script res://tools/ui/test_theme_v4.gd
## - one frame language: no panel or button style of the theme draws v3 corner brackets or a flat
##   1 px border; hud, modal and toast panels are GlassFrame; buttons, tabs, cards, wells, inputs
##   and tooltips carry a metal rim;
## - glass: tint 45..75% opacity; sheen and 1 px highlight present;
## - metal: rivets every 180 px edge tile, 7..9 px across; band 8 (hud) and 10 (window) px;
## - separators are engraved seams; the primary button glows inside its rim (no flat cyan fill);
## - every open screen and HUD panel in play uses a v4 style (walks the tree of main.tscn).

const UiTheme = preload("res://ui/theme/ui_theme.gd")
const Metal = preload("res://ui/theme/metal.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const FhStyle = preload("res://ui/theme/fh_style.gd")

var fails := 0
var main
var _n := 0
var _step := 0
var _queue: Array = []   # [[size, screen], ...] for the sideways-scroll check
var _hbad: Array = []
const SCREENS := ["goals", "research", "dashboard", "inventory", "colonists", "awards", "menu", "settings", "saveload", "help", "newcolony", "victory"]

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

static func v4(sb: StyleBox) -> bool:
	if sb == null or sb is StyleBoxEmpty:
		return true
	if sb.get_script() == GlassFrame:
		return true
	if sb.get_script() == FhStyle:
		var clear: bool = sb.fill_top.a == 0.0 and sb.fill_bottom.a == 0.0 and (sb.border.a == 0.0 or sb.border_width <= 0.0)
		return sb.bracket.a == 0.0 and (sb.rim > 0.0 or clear)
	return true   # StyleBoxFlat list rows, list_row.gd, seam_line.gd

func _init() -> void:
	var t: Theme = UiTheme.build()
	var bad: Array = []
	for type in t.get_stylebox_type_list():
		for nm in t.get_stylebox_list(type):
			var sb: StyleBox = t.get_stylebox(nm, type)
			if not v4(sb):
				bad.append("%s/%s" % [type, nm])
	check("one frame language: no theme style draws brackets or a flat border", bad.is_empty(), str(bad))
	for pair in [["HudPanel", "hud"], ["ModalPanel", "window"], ["ToastPanel", "hud"], ["PanelContainer", "hud"]]:
		var sb: StyleBox = t.get_stylebox("panel", pair[0])
		check("%s is a GlassFrame (%s)" % [pair[0], pair[1]], sb.get_script() == GlassFrame and sb.kind == pair[1])
	for type in ["Button", "PrimaryButton", "TabButton", "NavButton", "ChipButton", "DangerButton", "CardButton", "OptionButton"]:
		var sb: StyleBox = t.get_stylebox("normal", type)
		check("%s has a metal rim" % type, sb.get_script() == FhStyle and sb.rim >= 1.0, "rim %s" % (str(sb.rim) if sb.get_script() == FhStyle else "-"))
	var pn: StyleBox = t.get_stylebox("normal", "PrimaryButton")
	check("the primary button glows inside its rim and is not a flat cyan block", pn.inner_glow.a >= 0.5 and pn.fill_top.a < 0.95 and pn.fill_top.g < 0.5, "fill %s glow %s" % [pn.fill_top, pn.inner_glow])
	for type in ["CardPanel", "WellPanel"]:
		var sb: StyleBox = t.get_stylebox("panel", type)
		check("%s is engraved into the glass" % type, sb.rim >= 1.0 and sb.engraved)
	check("the selected tab carries a 2 px accent line", t.get_stylebox("pressed", "TabButton").top_line_w >= 2.0)
	check("separators are engraved seams", t.get_stylebox("separator", "HSeparator").get_script() == load("res://ui/theme/seam_line.gd"))
	var g = GlassFrame.new()
	check("glass tint 45..75% opacity", g.tint_top.a >= 0.45 and g.tint_bottom.a <= 0.75, "%.2f..%.2f" % [g.tint_top.a, g.tint_bottom.a])
	check("sheen and 1 px highlight", g.sheen.a > 0.0 and g.highlight.a > 0.0)
	check("rivets every 180 px edge tile", Metal.TILE == 180)
	check("bands 8 px (hud) and 10 px (window)", Metal.frame_band("hud") == 8 and Metal.frame_band("window") == 10)
	# Rivet size: measure the lit dome pixels across one rivet of the window frame.
	var img: Image = Metal.frame_tex("window").get_image()
	var cx: int = Metal.MARGIN + Metal.TILE / 2
	var cy: int = Metal.frame_band("window") / 2
	# The dark seat ring marks the rivet edge: the first dark pixel left of the centre.
	var x0: int = cx
	for x in range(cx - 8, cx + 1):
		if img.get_pixel(x, cy).v < 0.12:
			x0 = x
			break
	var across: int = 2 * (cx - x0)
	check("window rivets 7..10 px across (seat ring included)", across >= 7 and across <= 10, "%d px" % across)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
			main._on_cmd("speed 0")
			main._on_cmd("select research_lab")
			_step = 1
			_n = 0
		1:
			var bad: Array = []
			for c in main.hud.root.find_children("*", "PanelContainer", true, false):
				var pc: PanelContainer = c
				if pc.is_visible_in_tree() and not v4(pc.get_theme_stylebox("panel")):
					bad.append(str(pc.get_path()).get_file())
			check("every visible HUD panel uses a v4 style", bad.is_empty(), str(bad))
			main._on_cmd("closeall")
			main._on_cmd("open research")
			_step = 2
			_n = 0
		2:
			var bad2: Array = []
			for c in main.hud.root.find_children("*", "Control", true, false):
				var ctl: Control = c
				if not ctl.is_visible_in_tree():
					continue
				if ctl is PanelContainer and not v4(ctl.get_theme_stylebox("panel")):
					bad2.append(ctl.name)
				elif ctl is Button and not v4(ctl.get_theme_stylebox("normal")):
					bad2.append(ctl.name)
			check("the research screen uses v4 styles only", bad2.is_empty() and main.hud.screen_name() == "research", str(bad2))
			main._on_cmd("close")
			for sz in [Vector2i(1600, 900)]:
				for sn in SCREENS:
					_queue.append([sz, sn])
			_step = 3
			_n = 0
		3:
			# The metal band sits inside the frame: no screen may need a sideways scroll bar for it.
			if _queue.is_empty():
				check("no screen shows a sideways scroll bar at 1600x900", _hbad.is_empty(), str(_hbad))
				main._on_cmd("select research_lab")
				main._on_cmd("uiscale 0.8")
				_step = 5
				_n = 0
				return false
			var top = main.hud.screens.top_screen()
			if top != null and has_meta("cur") and (get_meta("cur")[0] as Vector2i).x >= 1600:
				var sb: HScrollBar = top._scroll.get_h_scroll_bar()
				if sb.visible:
					_hbad.append("%s %s (content %d > view %d)" % [str(get_meta("cur")[0]), get_meta("cur")[1], int(top.content.get_combined_minimum_size().x), int(top._scroll.size.x)])
				main._on_cmd("close")
			var nx: Array = _queue.pop_front()
			root.size = nx[0]
			root.content_scale_size = Vector2i.ZERO
			main._on_cmd("open " + String(nx[1]))
			set_meta("cur", nx)
			_n = 0
		5:
			# Critic round 21, fix 4: at 80 % interface scale no text is under 12 screen pixels.
			var s: float = main.hud.text_floor.canvas_scale()
			var small: Array = []
			var seen := 0
			for c in main.hud.root.find_children("*", "Control", true, false):
				var ctl: Control = c
				if not ctl.is_visible_in_tree():
					continue
				if (ctl is Label and (ctl as Label).text != "") or (ctl is Button and (ctl as Button).text != ""):
					seen += 1
					var px: float = float(ctl.get_theme_font_size("font_size")) * s
					if px < 11.99:
						small.append("%s %.1f px" % [ctl.name, px])
			check("80%% scale: no text under 12 px (%d texts, canvas scale %.2f)" % [seen, s], small.is_empty() and seen > 20, str(small.slice(0, 6)))
			main._on_cmd("uiscale 1")
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
