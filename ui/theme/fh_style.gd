extends StyleBox
const PG = preload("res://ui/poly_guard.gd")
## FhStyle: the one drawn look of every panel, card and button.
## Chamfered corners, a vertical gradient fill, a 1 px border, optional corner brackets,
## an optional header strip and accent bar, and an optional outer glow.
## Strokes are drawn opaque (pre-blended over the panel colour), so the glass shader can
## blur only the translucent fill (ui/theme/glass.gd).

var fill_top := Color(0.075, 0.118, 0.196, 0.88)
var fill_bottom := Color(0.043, 0.071, 0.125, 0.86)
var border := Color(0.12, 0.33, 0.42, 1.0)
var border_width := 1.0            # <= 0: no border
## Chamfer size in px per corner: top-left, top-right, bottom-right, bottom-left.
var chamfer := PackedFloat32Array([10.0, 0.0, 10.0, 0.0])
var bracket := Color(0, 0, 0, 0)   # corner bracket colour (alpha 0 = none)
var bracket_len := 10.0
var bracket_width := 2.0
var header_h := 0.0                # header strip height (0 = none)
var header_color := Color(0.098, 0.157, 0.259, 0.92)
var header_line := Color(0, 0, 0, 0)
var accent := Color(0, 0, 0, 0)    # accent bar on the left edge (alpha 0 = none)
var accent_w := 3.0
var top_line := Color(0, 0, 0, 0)  # bright line along the top edge (alpha 0 = none)
var glow := Color(0, 0, 0, 0)      # outer glow colour (alpha 0 = none)
var glow_size := 6.0
var inset := 0.0                   # draw the shape inset by this many px

func _init() -> void:
	content_margin_left = 10
	content_margin_right = 10
	content_margin_top = 8
	content_margin_bottom = 8

func clone() -> StyleBox:
	var s = get_script().new()
	for p in ["fill_top", "fill_bottom", "border", "border_width", "chamfer", "bracket", "bracket_len", "bracket_width",
			"header_h", "header_color", "header_line", "accent", "accent_w", "top_line", "glow", "glow_size", "inset",
			"content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		s.set(p, get(p))
	s.chamfer = chamfer.duplicate()
	return s

## The outline of `r` with chamfered corners, clockwise from the top-left.
static func shape(r: Rect2, ch: PackedFloat32Array) -> PackedVector2Array:
	var m: float = minf(r.size.x, r.size.y) * 0.5
	var tl: float = minf(ch[0], m)
	var tr: float = minf(ch[1], m)
	var br: float = minf(ch[2], m)
	var bl: float = minf(ch[3], m)
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.end.x
	var y1: float = r.end.y
	var pts := PackedVector2Array()
	if tl > 0.0:
		pts.append(Vector2(x0, y0 + tl))
		pts.append(Vector2(x0 + tl, y0))
	else:
		pts.append(Vector2(x0, y0))
	if tr > 0.0:
		pts.append(Vector2(x1 - tr, y0))
		pts.append(Vector2(x1, y0 + tr))
	else:
		pts.append(Vector2(x1, y0))
	if br > 0.0:
		pts.append(Vector2(x1, y1 - br))
		pts.append(Vector2(x1 - br, y1))
	else:
		pts.append(Vector2(x1, y1))
	if bl > 0.0:
		pts.append(Vector2(x0 + bl, y1))
		pts.append(Vector2(x0, y1 - bl))
	else:
		pts.append(Vector2(x0, y1))
	return pts

func _draw(ci: RID, rect: Rect2) -> void:
	var r: Rect2 = rect.grow(-inset)
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var pts: PackedVector2Array = shape(r, chamfer)
	# Outer glow: a few widening outlines with falling alpha.
	if glow.a > 0.0:
		for i in 3:
			var g: float = glow_size * float(i + 1) / 3.0
			var gp: PackedVector2Array = shape(r.grow(g), _grown_chamfer(g))
			gp.append(gp[0])
			var c := Color(glow.r, glow.g, glow.b, glow.a * (0.55 - 0.16 * float(i)))
			RenderingServer.canvas_item_add_polyline(ci, gp, PackedColorArray([c]), 2.0, true)
	# Fill: vertical gradient, exact on a convex polygon.
	if fill_top.a > 0.0 or fill_bottom.a > 0.0:
		var cols := PackedColorArray()
		for p in pts:
			var t: float = clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)
			cols.append(fill_top.lerp(fill_bottom, t))
		if PG.ok(pts, "fh_style.gd:95"):
			RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	# Header strip, clipped to the chamfered outline at the top.
	if header_h > 0.0:
		var hr := Rect2(r.position, Vector2(r.size.x, minf(header_h, r.size.y)))
		var hp: PackedVector2Array = shape(hr, PackedFloat32Array([chamfer[0], chamfer[1], 0.0, 0.0]))
		if PG.ok(hp, "fh_style.gd:100"):
			RenderingServer.canvas_item_add_polygon(ci, hp, PackedColorArray([header_color]))
		if header_line.a > 0.0:
			RenderingServer.canvas_item_add_line(ci, Vector2(r.position.x, r.position.y + hr.size.y), Vector2(r.end.x, r.position.y + hr.size.y), header_line, -1.0)
	if accent.a > 0.0:
		var top: float = r.position.y + chamfer[0]
		var bot: float = r.end.y - chamfer[3]
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x, top, accent_w, maxf(0.0, bot - top)), accent)
	if top_line.a > 0.0:
		RenderingServer.canvas_item_add_line(ci, Vector2(r.position.x + chamfer[0], r.position.y + 0.5), Vector2(r.end.x - chamfer[1], r.position.y + 0.5), top_line, 1.0)
	# Border
	if border_width > 0.0 and border.a > 0.0:
		# Half a pixel inside, so a 1 px line covers exactly one pixel row.
		var bp: PackedVector2Array = shape(r.grow(-0.5 * maxf(1.0, border_width)), chamfer)
		bp.append(bp[0])
		RenderingServer.canvas_item_add_polyline(ci, bp, PackedColorArray([border]), border_width if border_width > 1.0 else -1.0, false)
	# Corner brackets: an L on square corners, a bright bevel on chamfered ones.
	if bracket.a > 0.0:
		_brackets(ci, r)

func _grown_chamfer(g: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c in chamfer:
		out.append(c + g * 0.41 if c > 0.0 else 0.0)
	return out

func _brackets(ci: RID, r: Rect2) -> void:
	var L: float = bracket_len
	var w: float = bracket_width
	var o: float = 0.0
	var corners := [
		[Vector2(r.position.x, r.position.y), Vector2(1, 0), Vector2(0, 1), chamfer[0]],
		[Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1), chamfer[1]],
		[Vector2(r.end.x, r.end.y), Vector2(-1, 0), Vector2(0, -1), chamfer[2]],
		[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1), chamfer[3]],
	]
	for c in corners:
		var p: Vector2 = c[0]
		var ax: Vector2 = c[1]
		var ay: Vector2 = c[2]
		var ch: float = c[3]
		if ch > 0.0:
			var a: Vector2 = p + ay * ch
			var b: Vector2 = p + ax * ch
			RenderingServer.canvas_item_add_line(ci, a, b, bracket, w, true)
			RenderingServer.canvas_item_add_line(ci, b, b + ax * L * 0.6, bracket, w)
			RenderingServer.canvas_item_add_line(ci, a, a + ay * L * 0.6, bracket, w)
		else:
			var q: Vector2 = p + (ax + ay) * o
			RenderingServer.canvas_item_add_line(ci, q - ay * (w * 0.5) + ax * 0.0, q + ax * L, bracket, w)
			RenderingServer.canvas_item_add_line(ci, q, q + ay * L, bracket, w)
