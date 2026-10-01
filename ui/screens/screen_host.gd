extends Control
## Opens and closes the full screens (ui/screens/*.gd) over the HUD, one at a time, with
## dialogs (confirm) on top. Medals and chapters go to the panel manager (docs/UI_PANELS.md).
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
	"trade": "res://ui/screens/trade_screen.gd",
	"shuttle": "res://ui/screens/shuttle_screen.gd",
	"codex": "res://ui/screens/codex_screen.gd",
	"vehicles": "res://ui/screens/vehicles_screen.gd",
	"crew": "res://ui/screens/crew_screen.gd",
}
const ALIASES := {"colony": ["dashboard", "overview"], "nutrition": ["dashboard", "food"], "load": ["saveload", "load"],
	"save": ["saveload", "save"], "tech": ["research", null], "keys": ["help", "keys"], "pause": ["menu", null],
	"hazards": ["dashboard", "hazards"], "maintenance": ["dashboard", "hazards"], "labs": ["research", "labs"],
	"visitors": ["colonists", "visitors"]}

const OVER_TITLE := ["settings", "newcolony", "saveload", "awards", "help"]

var hud
var _stack: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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

# ---------------------------------------------------------------- medals and chapters (panel manager)
## A medal: a message of type "award" in the panel manager (one look; never in the centre). Never on the
## title screen.
func award_popup(id: String, first: bool = true) -> void:
	if hud.main.on_title or hud.panels == null:
		return
	var a: Dictionary = hud.data.awards_def().get(id, {})
	var tier: String = String(a.get("tier", "bronze"))
	hud.panels.post("award", "%s MEDAL: %s. %s%s" % [tier.to_upper(), String(a.get("name", id)).to_upper(), String(a.get("desc", "")), "  First on this device." if first else ""], "notice", "medal")

## A new chapter: a message of type "goal" in the panel manager; the Goals tab flashes.
func chapter_banner(index: int) -> void:
	var chs: Array = hud.data.chapters()
	if index < 0 or index >= chs.size() or hud.panels == null:
		return
	hud.panels.post("goal", "CHAPTER %d OF %d: %s. %s" % [index + 1, chs.size(), String(chs[index].get("name", "")).to_upper(), String(chs[index].get("desc", ""))], "warning", "goals")
	hud.panels._flash_tab("goals", "chapter %d" % index)
	Sfx.play("chapter")
