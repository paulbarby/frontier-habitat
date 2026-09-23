extends Control
## One headline number of the top bar: icon, value, trend arrow and a sub line
## (days of supply, rate). Hover shows a breakdown and a sparkline of its history.
## Click opens the matching dashboard page.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Icons = preload("res://ui/theme/icons.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const Spark = preload("res://ui/charts/sparkline.gd")

signal clicked(key: String)

var key := ""
var tint := P.CYAN
var tip_title := ""
var tip_lines: Array = []       # [[name, value, color?], ...]
var tip_note := ""
var series: Array = []          # [[tick, value], ...] for the sparkline (or series_key)
var series_key := ""            # read from `data` only when the tooltip opens
var data

var series_color := P.CYAN
var _icon_name := ""
var _val_text := "-"
var _sub_text := ""
var _trend := 99
var _trend_good_up := true
var _state := 0                 # 0 ok, 1 warn, 2 bad
var _hover := false
var _min_w := 100.0

## One control, drawn by hand: icon, value, trend arrow, sub line (few canvas items).
func setup(k: String, icon_name: String, color: Color, min_w: float = 104.0) -> void:
	key = k
	tint = color
	series_color = color
	_icon_name = icon_name
	_min_w = min_w
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(min_w, 36)
	tooltip_text = " "
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())

## state: 0 normal, 1 warning (amber), 2 critical (red). trend: -1, 0, 1, or 99 = hide.
func set_value(value: String, sub: String, state: int = 0, trend: int = 99, trend_good_up: bool = true) -> void:
	if value == _val_text and sub == _sub_text and state == _state and trend == _trend and trend_good_up == _trend_good_up:
		return
	_val_text = value
	_sub_text = sub
	_state = state
	_trend = trend
	_trend_good_up = trend_good_up
	var f: Font = Fonts.get_font("mono_b")
	var w: float = 28.0 + f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + (16.0 if trend != 99 else 0.0)
	var w2: float = 28.0 + Fonts.get_font("body").get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var want: float = maxf(_min_w, maxf(w, w2))
	if absf(want - custom_minimum_size.x) > 0.5:
		custom_minimum_size.x = want
	queue_redraw()

func _draw() -> void:
	var h: float = size.y
	if _hover:
		draw_rect(Rect2(Vector2(-4, -3), size + Vector2(8, 6)), Color(0.24, 0.88, 1.0, 0.08), true)
		draw_rect(Rect2(Vector2(-4, h + 2), Vector2(size.x + 8, 1)), P.with_alpha(tint, 0.9), true)
	if _state > 0:
		draw_rect(Rect2(Vector2(-4, -3), Vector2(2, h + 6)), P.AMBER if _state == 1 else P.RED, true)
	draw_texture_rect(Icons.tex(_icon_name, 20), Rect2(Vector2(0, h * 0.5 - 10), Vector2(20, 20)), false, tint)
	var c: Color = P.TEXT if _state == 0 else (P.AMBER if _state == 1 else P.RED)
	var mf: Font = Fonts.get_font("mono_b")
	draw_string(mf, Vector2(26, h * 0.5 + 2), _val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c)
	if _trend != 99:
		var name: String = "trend_up" if _trend > 0 else ("trend_down" if _trend < 0 else "trend_flat")
		var good: bool = (_trend > 0) == _trend_good_up
		var tc: Color = P.TEXT_3 if _trend == 0 else (P.GREEN if good else P.AMBER)
		var tx: float = 26.0 + mf.get_string_size(_val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 4.0
		draw_texture_rect(Icons.tex(name, 12), Rect2(Vector2(tx, h * 0.5 - 12), Vector2(12, 12)), false, tc)
	draw_string(Fonts.get_font("body"), Vector2(26, h * 0.5 + 15), _sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TEXT_2 if _state == 0 else c)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(key)
		accept_event()

func _make_custom_tooltip(_for_text: String) -> Object:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.custom_minimum_size.x = 250
	var h := Label.new()
	h.text = tip_title.to_upper()
	h.add_theme_font_override("font", Fonts.get_font("head"))
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", tint)
	v.add_child(h)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 2)
	for line in tip_lines:
		var a := Label.new()
		a.text = String(line[0])
		a.add_theme_font_size_override("font_size", 13)
		a.add_theme_color_override("font_color", P.TEXT_2)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(a)
		var b := Label.new()
		b.text = String(line[1])
		b.add_theme_font_override("font", Fonts.get_font("mono"))
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", line[2] if line.size() > 2 else P.TEXT)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(b)
	v.add_child(g)
	var pts: Array = series
	if series_key != "" and data != null:
		pts = data.series(series_key)
	if pts.size() >= 2:
		var sp = Spark.new()
		sp.points = pts
		sp.color = series_color
		sp.custom_minimum_size = Vector2(250, 46)
		sp.show_range = true
		v.add_child(sp)
	if tip_note != "":
		var n := Label.new()
		n.text = tip_note
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size.x = 250
		n.add_theme_font_size_override("font_size", 12)
		n.add_theme_color_override("font_color", P.TEXT_2)
		v.add_child(n)
	var c := Label.new()
	c.text = "Click: open the colony dashboard."
	c.add_theme_font_size_override("font_size", 11)
	c.add_theme_color_override("font_color", P.TEXT_3)
	v.add_child(c)
	return v
