extends PanelContainer
## Top-right time panel: a day/night dial, the day and colony clock, the time to sunrise
## or sunset, and the speed controls (pause, 1x, 2x, 4x). The colony clock shows 06:00 at
## sunrise; countdowns are game minutes and seconds.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")

var hud
var _dial: Control
var _day: Label
var _clock: Label
var _sub: Label
var _speed := {}
var _slow: Label

class Dial extends Control:
	var t01 := 0.0         # time of day 0..1 from sunrise
	var day01 := 0.6        # share of the day with sunlight
	var night := false
	func _ready() -> void:
		custom_minimum_size = Vector2(46, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 3.0
		draw_circle(c, r + 2.0, Color(0.02, 0.04, 0.075, 0.9))
		# Day arc (amber) then night arc (blue), clockwise from the left horizon.
		var a0 := PI
		_arc(c, r, a0, a0 + TAU * day01, Color("FFB547"))
		_arc(c, r, a0 + TAU * day01, a0 + TAU, Color("3B5BA8"))
		var a: float = a0 + TAU * t01
		var m: Vector2 = c + Vector2(cos(a), sin(a)) * r
		draw_circle(m, 4.2, Color.WHITE)
		draw_circle(m, 2.4, Color("FFD166") if not night else Color("9FB8FF"))
		var icon: Texture2D = Icons.tex("moon" if night else "sun", 18)
		draw_texture_rect(icon, Rect2(c - Vector2(9, 9), Vector2(18, 18)), false, Color("9FB8FF") if night else Color("FFD166"))
	func _arc(c: Vector2, r: float, a0: float, a1: float, col: Color) -> void:
		var n: int = maxi(4, int((a1 - a0) / 0.12))
		var pts := PackedVector2Array()
		for i in n + 1:
			var a: float = lerpf(a0, a1, float(i) / n)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_polyline(pts, col, 3.0, true)

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -8
	offset_top = 8
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row: HBoxContainer = Kit.hbox(10)
	add_child(row)
	_dial = Dial.new()
	row.add_child(_dial)
	var v: VBoxContainer = Kit.vbox(-2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.custom_minimum_size.x = 116
	row.add_child(v)
	var top: HBoxContainer = Kit.hbox(8)
	v.add_child(top)
	_day = Kit.head("Day 1", P.CYAN, 13)
	top.add_child(_day)
	_clock = Kit.num("06:00", 17, P.TEXT, true)
	top.add_child(_clock)
	_sub = Kit.label("", "SmallLabel", 11, P.TEXT_2)
	v.add_child(_sub)
	_slow = Kit.label("", "SmallLabel", 11, P.AMBER)
	_slow.visible = false
	v.add_child(_slow)
	row.add_child(Kit.vsep())
	var speeds: HBoxContainer = Kit.hbox(3)
	speeds.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(speeds)
	for spec in [[0, "pause", "Pause\nSpace pauses and resumes. You can plan while paused."], [1, "play", "Normal speed\nKey 1."],
			[2, "speed2", "Double speed\nKey 2."], [4, "speed4", "Four times speed\nKey 3."]]:
		var n: int = spec[0]
		var b: Button = Kit.icon_button(spec[1], func(): hud.main.set_speed(n), spec[2], "SpeedButton", 18, 34)
		b.toggle_mode = true
		speeds.add_child(b)
		_speed[n] = b

func rebuild() -> void:
	refresh()

func refresh() -> void:
	var m = hud.main
	var s = m.sim
	var t: float = s.util.day_time()
	var day_len: float = float(s.bal["day_length"])
	var daylight: float = float(s.planet["daylight_seconds"])
	var night: bool = s.util.is_night()
	_dial.t01 = t / day_len
	_dial.day01 = daylight / day_len
	_dial.night = night
	_dial.queue_redraw()
	_day.text = "DAY %d" % s.util.day_number()
	var hours: float = fposmod(6.0 + t / day_len * 24.0, 24.0)
	_clock.text = "%02d:%02d" % [int(hours), int(fposmod(hours, 1.0) * 60.0)]
	var left: float = s.util.seconds_to_sunrise() if night else s.util.seconds_to_sunset()
	_sub.text = "%s in %s" % ["Sunrise" if night else "Sunset", Kit.clock(left)]
	var paused: bool = m.speed == 0 or m.paused_by_menu
	for k in _speed:
		(_speed[k] as Button).set_pressed_no_signal(m.speed == k)
	_slow.visible = false
	if m.paused_by_menu:
		_sub.text = "PAUSED BY MENU"
		_sub.add_theme_color_override("font_color", P.AMBER)
	elif m.slowed:
		_sub.text = "SLOWED: %.1fx real speed" % float(m.effective_speed)
		_sub.add_theme_color_override("font_color", P.AMBER)
	elif paused:
		_sub.text = "PAUSED  " + _sub.text
		_sub.add_theme_color_override("font_color", P.AMBER)
	else:
		_sub.add_theme_color_override("font_color", P.TEXT_2)
