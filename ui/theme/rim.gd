extends RefCounted
## Metal rims and seams (V4_DESIGN §7, critic round 15 rules), shared by FhStyle, GlassFrame and
## the seam widgets. Each rim is ONE triangle-array draw command, so a button costs no more
## draw calls than the v3 1 px border did.
##   ring(ci, outer, inner, lit, dark, side)  a band between two outlines of the same vertex count;
##                                            each edge gets `lit` when it faces up or left, `dark`
##                                            when it faces down or right, `side` for the rest.
##   bevel(ci, r, chamfer, w, raised)         a bevelled metal rim `w` px wide inside `r`:
##                                            raised (buttons): light top-left, dark bottom-right;
##                                            recessed (wells, inputs): the other way round.
##   seam_h(ci, x0, x1, y) / seam_v(...)     an engraved hairline: a dark line, then a light one.


# Metal tones of the rim (the frame band of ui/theme/metal.gd, seen at 2 px).
const LIT := Color(0.66, 0.72, 0.79, 1.0)
const MID := Color(0.36, 0.41, 0.47, 1.0)
const DARK := Color(0.12, 0.15, 0.19, 1.0)
const SEAM_DARK := Color(0.0, 0.02, 0.05, 0.55)
const SEAM_LIGHT := Color(0.62, 0.80, 0.95, 0.20)

## The outline of `r` with chamfered corners, clockwise from the top-left (same as FhStyle.shape).
static func shape(r: Rect2, ch: PackedFloat32Array) -> PackedVector2Array:
	var m: float = minf(r.size.x, r.size.y) * 0.5
	var c := [minf(ch[0], m), minf(ch[1], m), minf(ch[2], m), minf(ch[3], m)]
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.end.x
	var y1: float = r.end.y
	var pts := PackedVector2Array()
	if c[0] > 0.0:
		pts.append_array(PackedVector2Array([Vector2(x0, y0 + c[0]), Vector2(x0 + c[0], y0)]))
	else:
		pts.append(Vector2(x0, y0))
	if c[1] > 0.0:
		pts.append_array(PackedVector2Array([Vector2(x1 - c[1], y0), Vector2(x1, y0 + c[1])]))
	else:
		pts.append(Vector2(x1, y0))
	if c[2] > 0.0:
		pts.append_array(PackedVector2Array([Vector2(x1, y1 - c[2]), Vector2(x1 - c[2], y1)]))
	else:
		pts.append(Vector2(x1, y1))
	if c[3] > 0.0:
		pts.append_array(PackedVector2Array([Vector2(x0 + c[3], y1), Vector2(x0, y1 - c[3])]))
	else:
		pts.append(Vector2(x0, y1))
	return pts
static func inner_chamfer(ch: PackedFloat32Array, w: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c in ch:
		out.append(maxf(c - w * 0.414, 0.01) if c > 0.0 else 0.0)
	return out

static func ring(ci: RID, outer: PackedVector2Array, inner: PackedVector2Array, lit: Color, dark: Color, side: Color) -> void:
	var n: int = outer.size()
	if n < 3 or inner.size() != n:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var j: int = (i + 1) % n
		var d: Vector2 = outer[j] - outer[i]
		var nrm := Vector2(d.y, -d.x).normalized()   # outward normal of a clockwise outline (y down)
		var f: float = nrm.x + nrm.y
		var c: Color = side
		if f < -0.3:
			c = lit
		elif f > 0.3:
			c = dark
		var b: int = pts.size()
		pts.append_array(PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]))
		cols.append_array(PackedColorArray([c, c, c, c]))
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, cols)

## A metal rim `w` px wide (1 or 2) along the inside of `r`. Two px: an outer bevel ring and an
## inner mid-tone ring, so it reads as a bevelled edge and not a line.
static func bevel(ci: RID, r: Rect2, ch: PackedFloat32Array, w: float, raised: bool, tint: Color = Color.WHITE) -> void:
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	var lit: Color = (LIT if raised else DARK) * tint
	var dark: Color = (DARK if raised else Color(0.5, 0.58, 0.66, 1.0)) * tint
	var side: Color = MID * tint
	lit.a = tint.a
	dark.a = tint.a
	side.a = tint.a
	var o: PackedVector2Array = shape(r, ch)
	var ch1: PackedFloat32Array = inner_chamfer(ch, 1.0)
	var i1: PackedVector2Array = shape(r.grow(-1.0), ch1)
	ring(ci, o, i1, lit, dark, side)
	if w >= 2.0:
		var i2: PackedVector2Array = shape(r.grow(-2.0), inner_chamfer(ch, 2.0))
		var m1: Color = side.lerp(lit, 0.35) if raised else side.darkened(0.3)
		var m2: Color = side.darkened(0.25) if raised else side.lerp(dark, 0.3)
		ring(ci, i1, i2, m1, m2, side)

static func seam_h(ci: RID, x0: float, x1: float, y: float, alpha: float = 1.0) -> void:
	RenderingServer.canvas_item_add_rect(ci, Rect2(x0, y, x1 - x0, 1.0), Color(SEAM_DARK.r, SEAM_DARK.g, SEAM_DARK.b, SEAM_DARK.a * alpha))
	RenderingServer.canvas_item_add_rect(ci, Rect2(x0, y + 1.0, x1 - x0, 1.0), Color(SEAM_LIGHT.r, SEAM_LIGHT.g, SEAM_LIGHT.b, SEAM_LIGHT.a * alpha))

static func seam_v(ci: RID, x: float, y0: float, y1: float, alpha: float = 1.0) -> void:
	RenderingServer.canvas_item_add_rect(ci, Rect2(x, y0, 1.0, y1 - y0), Color(SEAM_DARK.r, SEAM_DARK.g, SEAM_DARK.b, SEAM_DARK.a * alpha))
	RenderingServer.canvas_item_add_rect(ci, Rect2(x + 1.0, y0, 1.0, y1 - y0), Color(SEAM_LIGHT.r, SEAM_LIGHT.g, SEAM_LIGHT.b, SEAM_LIGHT.a * alpha))
