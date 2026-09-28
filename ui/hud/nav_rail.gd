extends PanelContainer
## Right-edge navigation rail: one icon button per screen, with its key in the tooltip.
## A small badge marks something that waits for the player (an idle research lab, a
## finished chapter, a new medal).
## Paul, 2026-09-28: the rail is one metal-framed glass strip (the HUD frame with its rivets), the
## buttons have the metal rim and bevel, a hover glow and a lit selected state in the accent colour
## (an accent bar on the left edge), and engraved seams group them: screens | world | help | menu.
## The styles are the theme's baked nine-patch styles (ui/theme/fh_style.gd), shared by every button.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const UiTheme = preload("res://ui/theme/ui_theme.gd")

var hud
var _box: VBoxContainer
var _buttons := {}
var _badges := {}
var _seams: Array = []
static var _styles := {}   # shared rail button styles (one set for every button: one baked texture each)

const ITEMS := [
	["goals", "goals", "Goals\nThe mission: chapters, goals and rewards. Key G."],
	["research", "research", "Research\nThe tech tree, the active project and the queue. Key T."],
	["dashboard", "dashboard", "Colony dashboard\nCharts of life support, food, industry, people and research. Key C."],
	["inventory", "inventory", "Inventory\nEvery item: stock, trend, days of supply, spoilage. Key I."],
	["colonists", "colonists", "Colonists\nEvery colonist: role, health, morale, nutrition, task. Key P."],
	["awards", "awards", "Awards\nMedals of this colony and of this device. Key V."],
	["|", "", ""],
	["vehicles", "rover", "Vehicles\nRovers, hoppers and the satellite: charge, cargo, crew, orders and routes between bases."],
	["codex", "codex", "Codex\nEvery structure, item, research project and hazard: where it comes from, what uses it, crafting trees. Key K."],
]

static func _rail_styles() -> Dictionary:
	if not _styles.is_empty():
		return _styles
	# Normal: dark glass in a metal rim (raised bevel). Hover: brighter glass and a cyan glow inside
	# the rim. Pressed (selected): lit glass, a strong glow and the accent bar on the left edge.
	var n = UiTheme.rimmed(Color(0.08, 0.13, 0.21, 0.55), Color(0.05, 0.085, 0.145, 0.62), [6, 0, 6, 0], [6, 6, 6, 6], 2.0)
	n.rim_tint = Color(0.92, 0.95, 1.0, 1.0)
	var h = UiTheme.rimmed(Color(0.12, 0.22, 0.34, 0.82), Color(0.08, 0.15, 0.25, 0.86), [6, 0, 6, 0], [6, 6, 6, 6], 2.0)
	h.inner_glow = P.with_alpha(P.CYAN, 0.55)
	h.rim_tint = Color(1.15, 1.2, 1.25, 1.0)
	var p = UiTheme.rimmed(Color(0.09, 0.33, 0.44, 0.92), Color(0.05, 0.21, 0.29, 0.94), [6, 0, 6, 0], [6, 6, 6, 6], 2.0, true)
	p.inner_glow = P.with_alpha(P.CYAN, 0.85)
	p.accent = P.CYAN
	p.accent_w = 3.0
	_styles = {"normal": n, "hover": h, "pressed": p}
	return _styles

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -6
	offset_top = 76
	# The HUD's glass frame (metal edge, rivets), with narrow margins: a strip, not a panel.
	add_theme_stylebox_override("panel", UiTheme.glass_frame("hud", [6, 9, 6, 9]))
	Glass.attach(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = Kit.vbox(4)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	for it in ITEMS:
		if String(it[0]) == "|":
			_seam()
			continue
		var name: String = it[0]
		_add(name, it[1], it[2], func(): hud.toggle_screen(name))
	_seam()
	_add("advisor", "advisor", "Advisor\nWhat to do next: the biggest problems, the next goal steps, unused potential. Key N.", func(): hud.toggle_advisor())
	_add("find", "search", "Find\nType a name or a type: the list shows every match; click one to go there. Key /.", func(): hud.toggle_find())
	_add("overlay", "overlay", "Overlay\nShows the power, water, air or walking network. Key O. Right click turns it off.", func(): hud.cycle_overlay())
	(_buttons["overlay"] as Button).gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			hud.set_overlay(""))
	_seam()
	_add("menu", "menu", "Menu\nSave, load, settings, new colony. Esc.", func(): hud.toggle_menu())

## An engraved seam between groups (the theme's HSeparator is a seam: ui/theme/seam_line.gd).
func _seam() -> void:
	var s: HSeparator = Kit.sep()
	s.custom_minimum_size.y = 6
	_box.add_child(s)
	_seams.append(s)

func _add(name: String, icon: String, tip: String, cb: Callable) -> void:
	var b: Button = Kit.icon_button(icon, cb, tip, "NavButton", 22, 46)
	var st: Dictionary = _rail_styles()
	b.add_theme_stylebox_override("normal", st["normal"])
	b.add_theme_stylebox_override("hover", st["hover"])
	b.add_theme_stylebox_override("pressed", st["pressed"])
	b.add_theme_stylebox_override("hover_pressed", st["pressed"])
	b.add_theme_stylebox_override("disabled", st["normal"])
	b.add_theme_color_override("icon_normal_color", Color("B7C6D6"))
	b.add_theme_color_override("icon_hover_color", Color.WHITE)
	b.add_theme_color_override("icon_pressed_color", Color("E8FDFF"))
	b.add_theme_color_override("icon_hover_pressed_color", Color.WHITE)
	b.toggle_mode = true
	_box.add_child(b)
	_buttons[name] = b
	var dot := Label.new()
	dot.text = ""
	dot.visible = false
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -14
	dot.offset_top = -3
	dot.add_theme_font_size_override("font_size", 11)
	dot.add_theme_color_override("font_color", P.TEXT_DARK)
	var bg := StyleBoxFlat.new()
	bg.bg_color = P.AMBER
	bg.set_corner_radius_all(7)
	bg.content_margin_left = 4
	bg.content_margin_right = 4
	dot.add_theme_stylebox_override("normal", bg)
	b.add_child(dot)
	_badges[name] = dot

## The rail fits the view height: in a short view the buttons get smaller (46 px down to 32 px).
var _side := 46.0
func _process(_d: float) -> void:
	var n: int = _buttons.size()
	var fixed: float = 18.0 + float(_seams.size()) * 10.0 + float(n + _seams.size() - 1) * 4.0   # frame margins, seams, gaps
	var room: float = get_viewport_rect().size.y - offset_top - 8.0 - fixed
	var want: float = clampf(floorf(room / maxf(1.0, float(n))), 32.0, 46.0)
	if absf(want - _side) >= 1.0:
		_side = want
		for b in _buttons.values():
			(b as Button).custom_minimum_size = Vector2(_side, _side)
		reset_size()

func rebuild() -> void:
	refresh()

func refresh() -> void:
	var open: String = hud.screen_name()
	for n in _buttons:
		(_buttons[n] as Button).set_pressed_no_signal(n == open or (n == "overlay" and hud.main.view.overlay != "") or (n == "find" and hud.find != null and hud.find.visible) or (n == "advisor" and hud.advisor != null and hud.advisor.visible))
	var d = hud.data
	# Research: an idle lab (no active project while research exists).
	var r: Dictionary = d.research()
	_badge("research", d.research_available() and String(r.get("active", "")) == "" and _has_lab(), "!", P.AMBER)
	# Awards: medals earned since the gallery was last opened.
	var new_awards: int = hud.watchers.unseen_awards() if hud.watchers.has_method("unseen_awards") else 0
	_badge("awards", new_awards > 0, str(new_awards), P.GOLD)
	var ov: String = hud.main.view.overlay
	(_buttons["overlay"] as Button).tooltip_text = "Overlay: %s\nShows the power, water, air or walking network. Key O. Right click turns it off." % ("off" if ov == "" else ov)

func _badge(name: String, on: bool, text: String, col: Color) -> void:
	var l: Label = _badges[name]
	l.visible = on
	l.text = text
	(l.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = col

func _has_lab() -> bool:
	for id in hud.main.sim.state["buildings"]:
		var b: Dictionary = hud.main.sim.state["buildings"][id]
		if String(b["def"]) == "research_lab" and b["state"] == "active":
			return true
	return false
