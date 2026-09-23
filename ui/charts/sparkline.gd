extends Control
## Sparkline: a tiny area + line of the last values, with a dot on the newest value.
## points: [[x, value], ...]. show_range draws the min and max values.

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")

var points: Array = []:
	set(v):
		points = v
		queue_redraw()
var color := Color("3EE0FF")
var show_range := false
var zero_base := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var n: int = points.size()
	if n < 2:
		return
	var lo := INF
	var hi := -INF
	for p in points:
		lo = minf(lo, float(p[1]))
		hi = maxf(hi, float(p[1]))
	if zero_base:
		lo = minf(lo, 0.0)
	if hi - lo < 0.0001:
		hi = lo + 1.0
		lo -= 0.5
	var top: float = 12.0 if show_range else 2.0
	var r := Rect2(2, top, size.x - (34.0 if show_range else 6.0), size.y - top - 3.0)
	var x0: float = float(points[0][0])
	var x1: float = float(points[n - 1][0])
	var xs: float = r.size.x / maxf(0.0001, x1 - x0)
	var step: int = maxi(1, n / int(maxf(2.0, r.size.x)))
	var line := PackedVector2Array()
	var i := 0
	while i < n:
		var p: Array = points[i]
		line.append(Vector2(r.position.x + (float(p[0]) - x0) * xs, r.end.y - (float(p[1]) - lo) / (hi - lo) * r.size.y))
		i += step
	var last: Array = points[n - 1]
	var lp := Vector2(r.position.x + (float(last[0]) - x0) * xs, r.end.y - (float(last[1]) - lo) / (hi - lo) * r.size.y)
	if line[line.size() - 1] != lp:
		line.append(lp)
	for k in line.size() - 1:
		draw_polygon(PackedVector2Array([line[k], line[k + 1], Vector2(line[k + 1].x, r.end.y), Vector2(line[k].x, r.end.y)]),
			PackedColorArray([P.with_alpha(color, 0.22), P.with_alpha(color, 0.22), P.with_alpha(color, 0.0), P.with_alpha(color, 0.0)]))
	draw_polyline(line, color, 1.6, true)
	draw_circle(lp, 3.0, color)
	draw_circle(lp, 1.4, Color.WHITE)
	if show_range:
		var f: Font = Fonts.get_font("mono")
		draw_string(f, Vector2(r.end.x + 4, r.position.y + 8), _f(hi), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, P.TEXT_3)
		draw_string(f, Vector2(r.end.x + 4, r.end.y), _f(lo), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, P.TEXT_3)
		draw_string(Fonts.get_font("body"), Vector2(2, 9), "last %d samples" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.TEXT_3)

static func _f(v: float) -> String:
	if absf(v) >= 100.0 or absf(v - roundf(v)) < 0.05:
		return "%d" % int(roundf(v))
	return "%.1f" % v
