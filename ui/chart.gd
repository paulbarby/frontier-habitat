extends Control
## Small line chart of one column of the metrics history.

var history: Array = []
var column := 2
var title := ""
var color := Color("6abf4b")

func _ready() -> void:
	custom_minimum_size = Vector2(230, 86)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(1, 1, 1, 0.05), true)
	var font: Font = get_theme_default_font()
	var hi := 0.0001
	for row in history:
		hi = maxf(hi, float(row[column]))
	var last: float = float(history[history.size() - 1][column]) if not history.is_empty() else 0.0
	draw_string(font, Vector2(6, 15), "%s  now %s  max %s" % [title, _fmt(last), _fmt(hi)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
	if history.size() < 2:
		return
	var pts := PackedVector2Array()
	var n: int = history.size()
	for i in n:
		var x: float = 4.0 + (size.x - 8.0) * float(i) / float(n - 1)
		var y: float = size.y - 5.0 - (size.y - 27.0) * float(history[i][column]) / hi
		pts.append(Vector2(x, y))
	draw_polyline(pts, color, 2.0, true)

static func _fmt(v: float) -> String:
	return "%d" % int(v) if absf(v - roundf(v)) < 0.05 else "%.1f" % v
