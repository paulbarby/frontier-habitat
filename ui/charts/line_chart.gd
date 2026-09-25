extends "res://ui/charts/chart_base.gd"
const PG = preload("res://ui/poly_guard.gd")
## Line, area and stacked-area chart of time series.
## series: [{name, color, points: [[tick, value], ...]}]. X is game time (ticks),
## labelled in days. mode: "line", "area" or "stacked".

var series: Array = []:
	set(v):
		series = v
		queue_redraw()
var mode := "line"
var ticks_per_day := 6000.0
var y_min_zero := true
var y_max_fixed := -1.0
var value_format := ""        # e.g. "%.1f"; "" = automatic
var bands: Array = []         # [{from, to, color}] horizontal bands (target zones)
var refs: Array = []          # [{value, color, label}] horizontal reference lines

func _draw() -> void:
	draw_frame()
	var legend: Array = []
	for s in series:
		legend.append([s.get("name", ""), s.get("color", P.CYAN)])
	draw_legend(legend)
	var pr: Rect2 = plot_rect()
	# Ranges
	var x0 := INF
	var x1 := -INF
	var y0 := INF
	var y1 := -INF
	var stacked: bool = mode == "stacked"
	var n_max := 0
	for s in series:
		var pts: Array = s.get("points", [])
		n_max = maxi(n_max, pts.size())
		for p in pts:
			x0 = minf(x0, float(p[0]))
			x1 = maxf(x1, float(p[0]))
			if not stacked:
				y0 = minf(y0, float(p[1]))
				y1 = maxf(y1, float(p[1]))
	if n_max < 2 or x1 <= x0:
		draw_empty()
		return
	if stacked:
		# Stacks are summed by sample index (all series share the sampling clock).
		var tops: Array = []
		for s in series:
			var pts: Array = s.get("points", [])
			for i in pts.size():
				if tops.size() <= i:
					tops.append(0.0)
				tops[i] = float(tops[i]) + maxf(0.0, float(pts[i][1]))
		y0 = 0.0
		y1 = 0.0
		for v in tops:
			y1 = maxf(y1, float(v))
	for r in refs:
		y1 = maxf(y1, float(r["value"]))
	if y_min_zero:
		y0 = minf(0.0, y0)
	if y_max_fixed > 0.0:
		y1 = y_max_fixed
	else:
		y1 = nice_max(y1 if y1 > y0 else y0 + 1.0)
	var ys: float = pr.size.y / maxf(0.0001, y1 - y0)
	var xs: float = pr.size.x / (x1 - x0)
	# Bands and grid
	for b in bands:
		var a: float = pr.end.y - (clampf(float(b["from"]), y0, y1) - y0) * ys
		var c: float = pr.end.y - (clampf(float(b["to"]), y0, y1) - y0) * ys
		draw_rect(Rect2(pr.position.x, c, pr.size.x, a - c), b["color"], true)
	for t in nice_ticks(y0, y1, 4):
		var y: float = pr.end.y - (float(t) - y0) * ys
		draw_line(Vector2(pr.position.x, y), Vector2(pr.end.x, y), P.GRID, 1.0)
		draw_string(_mono, Vector2(2, y + 4), _f(float(t)), HORIZONTAL_ALIGNMENT_RIGHT, pad.x - 8.0, 10, P.TEXT_3)
	var dx0: float = x0 / ticks_per_day
	var dx1: float = x1 / ticks_per_day
	for t in nice_ticks(dx0, dx1, maxi(2, int(pr.size.x / 110.0))):
		var x: float = pr.position.x + (float(t) * ticks_per_day - x0) * xs
		draw_line(Vector2(x, pr.position.y), Vector2(x, pr.end.y), Color(P.GRID.r, P.GRID.g, P.GRID.b, 0.06), 1.0)
		var lab: String
		if dx1 - dx0 < 1.0:
			# Short spans: the colony clock (06:00 at sunrise, as the time panel shows).
			var hrs: float = fposmod(6.0 + fposmod(float(t), 1.0) * 24.0, 24.0)
			lab = "%02d:%02d" % [int(hrs), int(fposmod(hrs, 1.0) * 60.0)]
		elif absf(float(t) - roundf(float(t))) < 0.001:
			lab = "Day %d" % (int(t) + 1)
		else:
			lab = "D%.1f" % (float(t) + 1.0)
		# Keep the label inside the chart: the last one right-aligns at the edge.
		var lw: float = _font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var lx: float = clampf(x - lw * 0.5, 2.0, size.x - lw - 4.0)
		draw_string(_font, Vector2(lx, pr.end.y + 15), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, P.TEXT_3)
	draw_line(Vector2(pr.position.x, pr.end.y), Vector2(pr.end.x, pr.end.y), P.LINE_SOFT, 1.0)
	# Series (stacked: each series sits on the sum of the ones before it, by sample index)
	var base := PackedFloat32Array()
	for si in series.size():
		var s: Dictionary = series[si]
		var pts: Array = s.get("points", [])
		if pts.size() < 2:
			continue
		if base.size() < pts.size():
			base.resize(pts.size())
		var col: Color = s.get("color", P.CYAN)
		var line := PackedVector2Array()
		var low := PackedVector2Array()
		var step: int = maxi(1, pts.size() / int(maxf(2.0, pr.size.x / 1.5)))
		var idx: Array = range(0, pts.size(), step)
		if int(idx[idx.size() - 1]) != pts.size() - 1:
			idx.append(pts.size() - 1)
		for i in idx:
			var v: float = float(pts[i][1])
			var b0: float = 0.0
			if stacked:
				b0 = base[i]
				v = b0 + maxf(0.0, v)
			var x: float = pr.position.x + (float(pts[i][0]) - x0) * xs
			line.append(Vector2(x, pr.end.y - (v - y0) * ys))
			low.append(Vector2(x, pr.end.y - (b0 - y0) * ys))
		if stacked:
			for k in pts.size():
				base[k] += maxf(0.0, float(pts[k][1]))
		if mode == "area" or stacked:
			_draw_strip(line, low, col, stacked)
		draw_polyline(line, col, 2.0, true)
	for r in refs:
		var y: float = pr.end.y - (float(r["value"]) - y0) * ys
		_dashed(Vector2(pr.position.x, y), Vector2(pr.end.x, y), r.get("color", P.TEXT_2))
		draw_string(_font, Vector2(pr.end.x - 150, y - 4), String(r.get("label", "")), HORIZONTAL_ALIGNMENT_RIGHT, 148, 10, r.get("color", P.TEXT_2))
	# Hover
	if pr.has_point(hover):
		var hx: float = x0 + (hover.x - pr.position.x) / xs
		draw_line(Vector2(hover.x, pr.position.y), Vector2(hover.x, pr.end.y), Color(1, 1, 1, 0.35), 1.0)
		var rows: Array = []
		for s in series:
			var pts: Array = s.get("points", [])
			if pts.is_empty():
				continue
			var k: int = _nearest(pts, hx)
			var val: float = float(pts[k][1])
			rows.append([s.get("name", ""), _f(val) + (" " + unit if unit != "" else ""), s.get("color", P.CYAN)])
			if not stacked:
				var py: float = pr.end.y - (val - y0) * ys
				draw_circle(Vector2(pr.position.x + (float(pts[k][0]) - x0) * xs, py), 3.5, s.get("color", P.CYAN))
		var day: float = hx / ticks_per_day
		var head: String = "Day %d  %d%%" % [int(day) + 1, int(fposmod(day, 1.0) * 100.0)]
		draw_tip(hover, head, rows)

func _draw_strip(top: PackedVector2Array, low: PackedVector2Array, col: Color, stacked: bool) -> void:
	# Quads between the line and its base, so a concave area fills correctly.
	for i in top.size() - 1:
		var q := PackedVector2Array([top[i], top[i + 1], low[i + 1], low[i]])
		var a_top: float = 0.36 if stacked else 0.24
		var a_low: float = 0.3 if stacked else 0.03
		if PG.ok(q, "line_chart.gd:155"):
			draw_polygon(q, PackedColorArray([Color(col.r, col.g, col.b, a_top), Color(col.r, col.g, col.b, a_top), Color(col.r, col.g, col.b, a_low), Color(col.r, col.g, col.b, a_low)]))

func _dashed(a: Vector2, b: Vector2, c: Color) -> void:
	var d: float = a.distance_to(b)
	var dir: Vector2 = (b - a) / maxf(d, 0.001)
	var t := 0.0
	while t < d:
		draw_line(a + dir * t, a + dir * minf(d, t + 6.0), c, 1.0)
		t += 10.0

func _f(v: float) -> String:
	if value_format != "":
		return value_format % v
	return fmt(v)

static func _nearest(pts: Array, x: float) -> int:
	var lo := 0
	var hi: int = pts.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if float(pts[mid][0]) < x:
			lo = mid
		else:
			hi = mid
	return lo if absf(float(pts[lo][0]) - x) <= absf(float(pts[hi][0]) - x) else hi
