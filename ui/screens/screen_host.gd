extends Control
## Opens and closes the full screens (ui/screens/*.gd) over the HUD, one at a time, with
## dialogs (confirm) on top. Also shows the non-modal medal pop-ups and chapter banners.
## A screen that `pauses` stops the simulation while it is open.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Sfx = preload("res://ui/sfx.gd")

const SCREENS := {
	"menu": "res://ui/screens/menu_screen.gd",
	"settings": "res://ui/screens/settings_screen.gd",
	"saveload": "res://ui/screens/saveload_screen.gd",
	"help": "res://ui/screens/help_screen.gd",
	"newcolony": "res://ui/screens/newcolony_screen.gd",
	"research": "res://ui/screens/research_screen.gd",
	"goals": "res://ui/screens/goals_screen.gd",
	"victory": "res://ui/screens/victory_screen.gd",
	"awards": "res://ui/screens/awards_screen.gd",
	"dashboard": "res://ui/screens/dashboard_screen.gd",
	"inventory": "res://ui/screens/inventory_screen.gd",
	"colonists": "res://ui/screens/colonists_screen.gd",
	"lost": "res://ui/screens/lost_screen.gd",
	"title": "res://ui/screens/title_screen.gd",
	"confirm": "res://ui/screens/confirm_dialog.gd",
}
const ALIASES := {"colony": ["dashboard", "overview"], "nutrition": ["dashboard", "food"], "load": ["saveload", "load"],
	"save": ["saveload", "save"], "tech": ["research", null], "keys": ["help", "keys"], "pause": ["menu", null],
	"hazards": ["dashboard", "hazards"], "maintenance": ["dashboard", "hazards"], "labs": ["research", "labs"]}

const OVER_TITLE := ["settings", "newcolony", "saveload", "awards", "help"]

var hud
var _stack: Array = []
var _popups: Control
var _medals: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popups = Control.new()
	_popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)
	_medals = VBoxContainer.new()
	_medals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medals.add_theme_constant_override("separation", 8)
	_medals.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_medals.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_medals.offset_top = 80
	_popups.add_child(_medals)

static func names() -> Array:
	return SCREENS.keys() + ALIASES.keys()

func open(name: String, arg = null) -> bool:
	if ALIASES.has(name):
		var al: Array = ALIASES[name]
		name = al[0]
		if arg == null:
			arg = al[1]
	if not SCREENS.has(name):
		return false
	if name != "confirm":
		# One full screen at a time: a new one replaces the old. The title screen stays
		# under the screens it opens (settings, new colony, load, awards, help).
		for s in _stack.duplicate():
			if String(s.get("screen_name")) == "title" and OVER_TITLE.has(name):
				continue
			_remove(s)
	var script = load(SCREENS[name])
	if script == null:
		return false
	var s: Control = script.new()
	s.set("hud", hud)
	s.set("host", self)
	s.set("arg", arg)
	s.set("screen_name", name)
	add_child(s)
	move_child(_popups, get_child_count() - 1)
	_stack.append(s)
	_update_pause()
	Sfx.play("open")
	return true

func close(s: Control) -> void:
	if not _stack.has(s):
		return
	if s.has_method("on_close"):
		s.on_close()
	_stack.erase(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.12)
	tw.tween_callback(s.queue_free)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_pause()
	Sfx.play("close")

func _remove(s: Control) -> void:
	if s.has_method("on_close"):
		s.on_close()
	_stack.erase(s)
	s.queue_free()
	_update_pause()

func close_top() -> void:
	if _stack.is_empty():
		return
	var top: Control = _stack[_stack.size() - 1]
	if top.get("closable") == false:
		return
	close(top)

func close_all() -> void:
	for s in _stack.duplicate():
		_remove(s)

func is_open() -> bool:
	return not _stack.is_empty()

func current() -> String:
	if _stack.is_empty():
		return ""
	var top: Control = _stack[_stack.size() - 1]
	return String(top.get("screen_name"))

func top_screen() -> Control:
	return null if _stack.is_empty() else _stack[_stack.size() - 1]

func _update_pause() -> void:
	var p := false
	for s in _stack:
		if bool(s.get("pauses")):
			p = true
	if hud != null and hud.main != null:
		hud.main.paused_by_menu = p

func refresh() -> void:
	for s in _stack:
		if is_instance_valid(s):
			s.refresh()

func confirm(title: String, lines: Array, on_yes: Callable, yes_text: String = "Yes", danger: bool = false) -> void:
	open("confirm", {"title": title, "lines": lines, "on_yes": on_yes, "yes": yes_text, "danger": danger})

# ---------------------------------------------------------------- medal pop-ups
## Several medals at once share one stack; each card stays about four seconds and never
## takes the mouse. Never on the title screen.
func award_popup(id: String, first: bool = true) -> void:
	if hud.main.on_title:
		return
	while _medals.get_child_count() >= 3:
		var old: Node = _medals.get_child(0)
		_medals.remove_child(old)
		old.queue_free()
	var pop = load("res://ui/screens/award_popup.gd").new()
	pop.hud = hud
	pop.award_id = id
	pop.first_time = first
	_medals.add_child(pop)

## Screen rect of the medal pop-up on show (empty when none).
func popup_rect() -> Rect2:
	if _medals != null and _medals.get_child_count() > 0:
		return _medals.get_global_rect()
	return Rect2()

func chapter_banner(index: int) -> void:
	var chs: Array = hud.data.chapters()
	if index < 0 or index >= chs.size():
		return
	var b := VBoxContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.offset_top = 150
	var t: Label = Kit.head("Chapter %d of %d" % [index + 1, chs.size()], P.CYAN, 14, "head_wide")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(t)
	var n: Label = Kit.label(String(chs[index].get("name", "")).to_upper(), "DisplayLabel", 46, P.TEXT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_constant_override("outline_size", 10)
	n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.add_child(n)
	var dsc: Label = Kit.label(String(chs[index].get("desc", "")), "", 16, P.TEXT_2)
	dsc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dsc.add_theme_constant_override("outline_size", 6)
	dsc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.add_child(dsc)
	_popups.add_child(b)
	b.modulate.a = 0.0
	var tw := b.create_tween()
	tw.tween_property(b, "modulate:a", 1.0, 0.5)
	tw.tween_interval(3.5)
	tw.tween_property(b, "modulate:a", 0.0, 0.8)
	tw.tween_callback(b.queue_free)
	Sfx.play("chapter")
