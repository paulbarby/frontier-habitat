extends "res://ui/charts/chart_base.gd"
## Half-ring gauge: value between vmin and vmax, with coloured zones and a needle.
## zones: [{to, color}] in ascending order (the last zone ends at vmax).

var value := 0.0:
	set(v):
		value = v
		queue_redraw()
var vmin := 0.0
var vmax := 100.0
var zones: Array = []
var label := ""
var value_text := ""
var target := -1.0

func _draw() -> void:
	draw_frame()
	var top: float = 24.0 if title != "" else 6.0
	var r: float = minf(size.x * 0.5 - 12.0, size.y - top - 30.0)
	if r < 10.0:
		return
	var c := Vector2(size.x * 0.5, top + r + 4.0)
	var th: float = r * 0.2
	var a0 := PI
	var span := PI
	# Track and zones
	_band(c, r - th, r, a0, a0 + span, Color(1, 1, 1, 0.06))
	var from: float = vmin
	for z in zones:
		var to: float = clampf(float(z["to"]), vmin, vmax)
		_band(c, r - th * 0.35, r, a0 + span * (from - vmin) / (vmax - vmin), a0 + span * (to - vmin) / (vmax - vmin), P.with_alpha(z["color"], 0.55))
		from = to
	var t: float = clampf((value - vmin) / maxf(0.0001, vmax - vmin), 0.0, 1.0)
	var col: Color = _zone_color(value)
	_band(c, r - th, r - th * 0.4, a0, a0 + span * t, col)
	# Needle
	var na: float = a0 + span * t
	draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 2.0), Color.WHITE, 2.0, true)
	draw_circle(c, 4.0, Color.WHITE)
	if target >= vmin:
		var ta: float = a0 + span * clampf((target - vmin) / (vmax - vmin), 0.0, 1.0)
		draw_line(c + Vector2(cos(ta), sin(ta)) * (r - th - 3.0), c + Vector2(cos(ta), sin(ta)) * (r + 3.0), P.TEXT, 2.0)
	var vt: String = value_text if value_text != "" else fmt(value)
	draw_string(Fonts.get_font("mono_b"), Vector2(0, c.y + 22), vt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, col)
	if label != "":
		draw_string(_font, Vector2(0, c.y + 38), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, P.TEXT_2)

func _zone_color(v: float) -> Color:
	for z in zones:
		if v < float(z["to"]):
			return z["color"]
	return P.CYAN if zones.is_empty() else zones[zones.size() - 1]["color"]

func _band(c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	if a1 <= a0:
		return
	var n: int = maxi(2, int((a1 - a0) / 0.07))
	for i in n:
		var b0: float = lerpf(a0, a1, float(i) / n)
		var b1: float = lerpf(a0, a1, float(i + 1) / n)
		draw_colored_polygon(PackedVector2Array([c + Vector2(cos(b0), sin(b0)) * r1, c + Vector2(cos(b1), sin(b1)) * r1,
			c + Vector2(cos(b1), sin(b1)) * r0, c + Vector2(cos(b0), sin(b0)) * r0]), col)
