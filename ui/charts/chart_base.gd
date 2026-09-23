extends Control
## Shared parts of every chart: background well, title, legend, nice axis ticks, number
## format and an in-chart hover tooltip. Charts redraw only when their data or the hover
## position changes.

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")

var title := ""
var unit := ""
var show_legend := true
var show_bg := true
var pad := Vector4(46, 26, 12, 24)   # left, top, right, bottom (plot insets)
var hover := Vector2(-1, -1)
var _font: Font
var _mono: Font
var _head: Font

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true

func _ready() -> void:
	_font = Fonts.get_font("body")
	_mono = Fonts.get_font("mono")
	_head = Fonts.get_font("head")
	resized.connect(queue_redraw)
	mouse_exited.connect(func():
		hover = Vector2(-1, -1)
		queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = (event as InputEventMouseMotion).position
		queue_redraw()

func plot_rect() -> Rect2:
	return Rect2(pad.x, pad.y, maxf(10.0, size.x - pad.x - pad.z), maxf(10.0, size.y - pad.y - pad.w))

func draw_frame() -> void:
	if show_bg:
		draw_rect(Rect2(Vector2.ZERO, size), P.BG_DEEP, true)
		draw_rect(Rect2(Vector2.ZERO, size).grow(-0.5), P.LINE_SOFT, false, 1.0)
	if title != "":
		draw_string(_head, Vector2(10, 17), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TEXT_2)

## Legend on the top-right: [[name, color], ...]
func draw_legend(items: Array) -> void:
	if not show_legend or items.is_empty():
		return
	var x: float = size.x - 10.0
	for i in range(items.size() - 1, -1, -1):
		var name: String = String(items[i][0])
		var c: Color = items[i][1]
		var w: float = _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		x -= w
		draw_string(_font, Vector2(x, 16), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TEXT_2)
		x -= 12.0
		draw_rect(Rect2(x, 9, 8, 8), c, true)
		x -= 12.0

## Nice tick values between lo and hi, about `count` of them.
static func nice_ticks(lo: float, hi: float, count: int = 4) -> Array:
	if hi <= lo:
		hi = lo + 1.0
	var span: float = hi - lo
	var raw: float = span / float(maxi(1, count))
	var mag: float = pow(10.0, floor(log(raw) / log(10.0)))
	var step: float = mag
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if raw <= m * mag:
			step = m * mag
			break
	var out: Array = []
	var v: float = ceil(lo / step) * step
	while v <= hi + step * 0.001:
		out.append(v)
		v += step
	return out

static func nice_max(v: float) -> float:
	if v <= 0.0:
		return 1.0
	var mag: float = pow(10.0, floor(log(v) / log(10.0)))
	for m in [1.0, 1.2, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]:
		if v <= m * mag:
			return m * mag
	return 10.0 * mag

static func fmt(v: float) -> String:
	var a: float = absf(v)
	if a >= 10000.0:
		return "%.0fk" % (v / 1000.0)
	if a >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	if a >= 100.0 or absf(v - roundf(v)) < 0.01:
		return "%d" % int(roundf(v))
	if a >= 10.0:
		return "%.1f" % v
	return "%.2f" % v if a < 1.0 else "%.1f" % v

## A small tooltip box inside the chart near `at`: title + [[name, value, color], ...]
func draw_tip(at: Vector2, head: String, rows: Array) -> void:
	var w := 0.0
	w = maxf(w, _head.get_string_size(head.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	for r in rows:
		var tw: float = _font.get_string_size(String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + _mono.get_string_size(String(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 34.0
		w = maxf(w, tw)
	w += 16.0
	var h: float = 22.0 + 17.0 * rows.size()
	var pos := at + Vector2(14, -h * 0.5)
	if pos.x + w > size.x - 4.0:
		pos.x = at.x - 14.0 - w
	pos.y = clampf(pos.y, 4.0, maxf(4.0, size.y - h - 4.0))
	var r := Rect2(pos, Vector2(w, h))
	draw_rect(r, Color(0.035, 0.06, 0.11, 0.96), true)
	draw_rect(r.grow(-0.5), P.LINE_STRONG, false, 1.0)
	draw_string(_head, pos + Vector2(8, 15), head.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.CYAN)
	var y: float = pos.y + 33.0
	for row in rows:
		var c: Color = row[2] if row.size() > 2 else P.TEXT
		draw_rect(Rect2(pos.x + 8, y - 8, 7, 7), c, true)
		draw_string(_font, Vector2(pos.x + 20, y), String(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TEXT_2)
		var vw: float = _mono.get_string_size(String(row[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(_mono, Vector2(pos.x + w - 8 - vw, y), String(row[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TEXT)
		y += 17.0

func draw_empty(text: String = "No data yet.") -> void:
	var r: Rect2 = plot_rect()
	draw_string(_font, Vector2(r.position.x, r.get_center().y + 5), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, P.TEXT_3)
