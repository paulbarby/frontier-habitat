extends "res://ui/charts/chart_base.gd"
## Donut chart. segments: [{name, value, color}]. The centre shows `center_value` and
## `center_label`; the legend lists every segment with its share. Hover highlights one.

var segments: Array = []:
	set(v):
		segments = v
		queue_redraw()
var center_value := ""
var center_label := ""
var thickness := 0.28      # ring thickness as a share of the radius
var legend_right := true

func _draw() -> void:
	draw_frame()
	var total := 0.0
	for s in segments:
		total += maxf(0.0, float(s.get("value", 0.0)))
	var area := Rect2(Vector2(0, 22), Vector2(size.x, size.y - 22))
	var ring_w: float = area.size.x * (0.5 if legend_right else 1.0)
	var r: float = minf(ring_w, area.size.y) * 0.5 - 10.0
	var c := Vector2(area.position.x + ring_w * 0.5, area.position.y + area.size.y * 0.5)
	if r < 8.0:
		return
	var inner: float = r * (1.0 - thickness)
	if total <= 0.0:
		_arc_band(c, inner, r, 0.0, TAU, Color(1, 1, 1, 0.06))
		draw_string(_font, Vector2(c.x - r, c.y + 5), "No data yet.", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 12, P.TEXT_3)
		return
	var a := -PI * 0.5
	var hover_i := -1
	var hv: Vector2 = hover - c
	var hover_ang: float = fposmod(atan2(hv.y, hv.x) + PI * 0.5, TAU) - PI * 0.5
	var hover_in: bool = hover.x >= 0.0 and hv.length() >= inner and hv.length() <= r + 6.0
	for i in segments.size():
		var s: Dictionary = segments[i]
		var sweep: float = TAU * maxf(0.0, float(s.get("value", 0.0))) / total
		if sweep <= 0.0:
			continue
		var col: Color = s.get("color", P.CYAN)
		var grow := 0.0
		if hover_in and hover_ang >= a and hover_ang < a + sweep:
			hover_i = i
			grow = 4.0
		_arc_band(c, inner, r + grow, a + 0.012, a + sweep - 0.012, col)
		a += sweep
	# Centre text
	draw_string(_mono_b(), Vector2(c.x - inner, c.y + 4), center_value, HORIZONTAL_ALIGNMENT_CENTER, inner * 2.0, int(clampf(inner * 0.42, 12.0, 26.0)), P.TEXT)
	draw_string(_font, Vector2(c.x - inner, c.y + 22), center_label, HORIZONTAL_ALIGNMENT_CENTER, inner * 2.0, 11, P.TEXT_2)
	# Legend
	if legend_right:
		var lx: float = area.position.x + ring_w + 4.0
		var ly: float = c.y - float(segments.size()) * 9.0 + 6.0
		for i in segments.size():
			var s: Dictionary = segments[i]
			var v: float = maxf(0.0, float(s.get("value", 0.0)))
			var col: Color = s.get("color", P.CYAN)
			var bright: bool = hover_i == -1 or hover_i == i
			draw_rect(Rect2(lx, ly - 8, 9, 9), col if bright else P.with_alpha(col, 0.35), true)
			draw_string(_font, Vector2(lx + 15, ly), String(s.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - lx - 70.0, 12, P.TEXT if bright else P.TEXT_3)
			draw_string(_mono, Vector2(size.x - 60, ly), "%d%%" % int(roundf(v / total * 100.0)), HORIZONTAL_ALIGNMENT_RIGHT, 52, 12, P.TEXT_2)
			ly += 18.0
	if hover_i >= 0:
		var s: Dictionary = segments[hover_i]
		draw_tip(hover, String(s.get("name", "")), [["Value", fmt(float(s.get("value", 0.0))), s.get("color", P.CYAN)], ["Share", "%d%%" % int(roundf(float(s.get("value", 0.0)) / total * 100.0)), P.TEXT_2]])

func _mono_b() -> Font:
	return Fonts.get_font("mono_b")

func _arc_band(c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	var n: int = maxi(3, int((a1 - a0) / 0.06))
	var pts := PackedVector2Array()
	for i in n + 1:
		var a: float = lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	for i in range(n, -1, -1):
		var a: float = lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r0)
	# Split into quads: the band is not convex.
	var half: int = n + 1
	for i in n:
		var q := PackedVector2Array([pts[i], pts[i + 1], pts[2 * half - 2 - i], pts[2 * half - 1 - i]])
		draw_colored_polygon(q, col)
