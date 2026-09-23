extends "res://ui/charts/chart_base.gd"
## Grouped bar chart. categories: [label, ...]; series: [{name, color, values: [...]}].
## horizontal = true draws bars left to right with labels on the left (good for long
## names and item lists). `icons` (optional) = [texture, ...] per category.

var categories: Array = []
var series: Array = []:
	set(v):
		series = v
		queue_redraw()
var horizontal := false
var icons: Array = []
var value_format := ""
var target: Array = []        # optional per-category target marks
var label_w := 120.0

func _draw() -> void:
	draw_frame()
	var legend: Array = []
	for s in series:
		legend.append([s.get("name", ""), s.get("color", P.CYAN)])
	if series.size() > 1:
		draw_legend(legend)
	if categories.is_empty() or series.is_empty():
		draw_empty()
		return
	var vmax := 0.0
	for s in series:
		for v in s.get("values", []):
			vmax = maxf(vmax, float(v))
	for t in target:
		vmax = maxf(vmax, float(t))
	vmax = nice_max(vmax)
	if horizontal:
		_draw_h(vmax)
	else:
		_draw_v(vmax)

func _draw_v(vmax: float) -> void:
	var pr: Rect2 = plot_rect()
	for t in nice_ticks(0.0, vmax, 4):
		var y: float = pr.end.y - float(t) / vmax * pr.size.y
		draw_line(Vector2(pr.position.x, y), Vector2(pr.end.x, y), P.GRID, 1.0)
		draw_string(_mono, Vector2(2, y + 4), _f(float(t)), HORIZONTAL_ALIGNMENT_RIGHT, pad.x - 8.0, 10, P.TEXT_3)
	var n: int = categories.size()
	var group_w: float = pr.size.x / float(n)
	var bar_w: float = minf(28.0, group_w * 0.72 / float(series.size()))
	var hover_i := -1
	for i in n:
		var gx: float = pr.position.x + group_w * float(i) + (group_w - bar_w * series.size()) * 0.5
		if hover.x >= pr.position.x + group_w * i and hover.x < pr.position.x + group_w * (i + 1) and pr.has_point(hover):
			hover_i = i
			draw_rect(Rect2(pr.position.x + group_w * i, pr.position.y, group_w, pr.size.y), Color(1, 1, 1, 0.04), true)
		for si in series.size():
			var vals: Array = series[si].get("values", [])
			var v: float = float(vals[i]) if i < vals.size() else 0.0
			var h: float = v / vmax * pr.size.y
			var col: Color = series[si].get("color", P.CYAN)
			var r := Rect2(gx + bar_w * si, pr.end.y - h, bar_w - 2.0, h)
			draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
				PackedColorArray([col, col, col.darkened(0.45), col.darkened(0.45)]))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), col.lightened(0.4), true)
		var lab: String = String(categories[i])
		if icons.size() > i and icons[i] != null:
			draw_texture_rect(icons[i], Rect2(pr.position.x + group_w * (i + 0.5) - 8, pr.end.y + 4, 16, 16), false)
		else:
			draw_string(_font, Vector2(pr.position.x + group_w * i, pr.end.y + 15), lab, HORIZONTAL_ALIGNMENT_CENTER, group_w, 10, P.TEXT_3)
			# (centred inside its own group, so it never passes the right edge)
	if hover_i >= 0:
		var rows: Array = []
		for s in series:
			var vals: Array = s.get("values", [])
			rows.append([s.get("name", ""), _f(float(vals[hover_i]) if hover_i < vals.size() else 0.0), s.get("color", P.CYAN)])
		draw_tip(hover, String(categories[hover_i]), rows)

func _draw_h(vmax: float) -> void:
	var pr := Rect2(label_w, pad.y, maxf(10.0, size.x - label_w - 48.0), maxf(10.0, size.y - pad.y - 8.0))
	var n: int = categories.size()
	var row_h: float = minf(26.0, pr.size.y / float(n))
	var bar_h: float = minf(14.0, row_h * 0.7 / float(series.size()))
	var hover_i := -1
	for i in n:
		var y0: float = pr.position.y + row_h * i
		if hover.y >= y0 and hover.y < y0 + row_h and hover.x >= 0.0:
			hover_i = i
			draw_rect(Rect2(0, y0, size.x, row_h), Color(1, 1, 1, 0.04), true)
		var tx: float = 8.0
		if icons.size() > i and icons[i] != null:
			draw_texture_rect(icons[i], Rect2(8, y0 + row_h * 0.5 - 8, 16, 16), false)
			tx = 30.0
		draw_string(_font, Vector2(tx, y0 + row_h * 0.5 + 4), String(categories[i]), HORIZONTAL_ALIGNMENT_LEFT, label_w - tx - 6.0, 12, P.TEXT_2)
		var last := 0.0
		for si in series.size():
			var vals: Array = series[si].get("values", [])
			var v: float = float(vals[i]) if i < vals.size() else 0.0
			var col: Color = series[si].get("color", P.CYAN)
			var w: float = v / vmax * pr.size.x
			var by: float = y0 + (row_h - bar_h * series.size()) * 0.5 + bar_h * si
			var r := Rect2(pr.position.x, by, w, bar_h - 2.0)
			draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
				PackedColorArray([col.darkened(0.4), col, col, col.darkened(0.4)]))
			last = maxf(last, w)
		if target.size() > i and float(target[i]) > 0.0:
			var tx2: float = pr.position.x + float(target[i]) / vmax * pr.size.x
			draw_line(Vector2(tx2, y0 + 2), Vector2(tx2, y0 + row_h - 2), Color(1, 1, 1, 0.8), 1.5)
		var vals0: Array = series[0].get("values", [])
		draw_string(_mono, Vector2(pr.position.x + last + 6.0, y0 + row_h * 0.5 + 4), _f(float(vals0[i]) if i < vals0.size() else 0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TEXT)
	if hover_i >= 0 and series.size() > 1:
		var rows: Array = []
		for s in series:
			var vals: Array = s.get("values", [])
			rows.append([s.get("name", ""), _f(float(vals[hover_i]) if hover_i < vals.size() else 0.0), s.get("color", P.CYAN)])
		draw_tip(hover, String(categories[hover_i]), rows)

func _f(v: float) -> String:
	if value_format != "":
		return value_format % v
	return fmt(v)
