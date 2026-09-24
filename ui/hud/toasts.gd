extends Control
## Notification toasts: top right, icon + text, newest on top, at most four. Each slides
## in from the right, stays five seconds (eight for warnings) and fades out.
## kind: info | good | warn | bad | award | research | goal

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const UiTheme = preload("res://ui/theme/ui_theme.gd")

const MAX := 4
const KIND := {
	"info": ["sev_info", Color("3EE0FF")], "good": ["sev_ok", Color("5EE07A")], "warn": ["sev_warning", Color("FFB547")],
	"bad": ["sev_critical", Color("FF5A5F")], "award": ["medal", Color("FFD166")], "research": ["research", Color("A78BFA")],
	"goal": ["goals", Color("3EE0FF")], "save": ["save", Color("5EE07A")],
}

var hud
var _box: VBoxContainer
var _last_text := ""
var _last_t := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = Kit.vbox(8)
	_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_box.offset_top = 76
	_box.offset_right = -70
	_box.custom_minimum_size.x = 360
	add_child(_box)

func _process(_delta: float) -> void:
	if hud == null:
		return
	var inset: float = hud.right_inset()
	_box.offset_right = -70.0 - (inset + 8.0 if inset > 0.0 else 0.0)
	var top := 76.0
	var pop: Rect2 = hud.screens.popup_rect()
	if pop.size.x > 0.0:
		top = maxf(top, pop.end.y + 10.0)
	var ban = hud.get("hazard_banner")
	if ban != null and (ban as Control).visible:
		top = maxf(top, (ban as Control).get_global_rect().end.y + 10.0)
	_box.offset_top = top

func push(text: String, kind: String = "info", icon: String = "") -> void:
	if text == "":
		return
	# The same text twice within two seconds is one toast.
	var now: int = Time.get_ticks_msec()
	if text == _last_text and now - _last_t < 2000:
		return
	_last_text = text
	_last_t = now
	if not KIND.has(kind):
		kind = _guess(text)
	var spec: Array = KIND[kind]
	var col: Color = spec[1]
	var p: PanelContainer = Kit.panel("ToastPanel", true, [8, 0, 8, 0])
	var st = UiTheme.panel_style("toast")
	st.accent = col
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.custom_minimum_size.x = 360
	var h: HBoxContainer = Kit.hbox(10)
	p.add_child(h)
	h.add_child(Kit.icon(icon if icon != "" else spec[0], 20, col))
	var l: Label = Kit.wrap(text, 14, P.TEXT)
	l.custom_minimum_size.x = 290
	h.add_child(l)
	_box.add_child(p)
	_box.move_child(p, 0)
	while _box.get_child_count() > MAX:
		var old: Node = _box.get_child(_box.get_child_count() - 1)
		_box.remove_child(old)
		old.queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	var life: float = 8.0 if kind in ["warn", "bad"] else 5.0
	tw.tween_interval(life)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			p.queue_free())
	var sound: String = {"research": "research", "goal": "goal", "award": "award"}.get(kind, "toast")
	if kind == "bad":
		sound = "alert_critical"
	elif kind == "warn":
		sound = "alert_warning"
	Kit.sfx(sound)

static func _guess(text: String) -> String:
	var t: String = text.to_lower()
	if t.begins_with("refused") or t.contains("failed") or t.contains("cannot"):
		return "warn"
	if t.begins_with("saved") or t.begins_with("autosaved") or t.begins_with("exported"):
		return "save"
	return "info"
