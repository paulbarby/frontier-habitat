extends VBoxContainer
## Right-edge navigation rail: one icon button per screen, with its key in the tooltip.
## A small badge marks something that waits for the player (an idle research lab, a
## finished chapter, a new medal).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")

var hud
var _buttons := {}
var _badges := {}

const ITEMS := [
	["goals", "goals", "Goals\nThe mission: chapters, goals and rewards. Key G."],
	["research", "research", "Research\nThe tech tree, the active project and the queue. Key T."],
	["dashboard", "dashboard", "Colony dashboard\nCharts of life support, food, industry, people and research. Key C."],
	["inventory", "inventory", "Inventory\nEvery item: stock, trend, days of supply, spoilage. Key I."],
	["colonists", "colonists", "Colonists\nEvery colonist: role, health, morale, nutrition, task. Key P."],
	["awards", "awards", "Awards\nMedals of this colony and of this device. Key V."],
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -8
	offset_top = 76
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in ITEMS:
		var name: String = it[0]
		_add(name, it[1], it[2], func(): hud.toggle_screen(name))
	add_child(Kit.gap(0, 6))
	_add("overlay", "overlay", "Overlay\nShows the power, water, air or walking network. Key O. Right click turns it off.", func(): hud.cycle_overlay())
	(_buttons["overlay"] as Button).gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			hud.set_overlay(""))
	_add("menu", "menu", "Menu\nSave, load, settings, new colony. Esc.", func(): hud.toggle_menu())

func _add(name: String, icon: String, tip: String, cb: Callable) -> void:
	var b: Button = Kit.icon_button(icon, cb, tip, "NavButton", 22, 46)
	b.toggle_mode = true
	add_child(b)
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

func rebuild() -> void:
	refresh()

func refresh() -> void:
	var open: String = hud.screen_name()
	for n in _buttons:
		(_buttons[n] as Button).set_pressed_no_signal(n == open or (n == "overlay" and hud.main.view.overlay != ""))
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
