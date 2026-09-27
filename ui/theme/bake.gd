extends RefCounted
## Baked nine-patch textures for the version-4 look (coordinator 2026-09-27: HUD draw calls back
## to 250 or fewer). The v4 rims, glows, glass tint, sheen and drop shadow were drawn as polygons
## and triangle arrays: two to five draw commands per button or panel, which the GL Compatibility
## batcher does not merge. Here each look is painted ONCE into a small texture and drawn as ONE
## nine-patch; controls of the same look share the texture, so the batcher can merge them too.
##   rim_tex(style)                         FhStyle with a metal rim: fill + inner glow + top line + rim
##   glass_fill_tex(top, bottom, sheen, highlight, ch, cut_top)   GlassFrame tint + sheen + highlight
##   shadow_tex(color)                      the soft drop shadow of windows
## Each returns {tex, m (margins: Vector4 left, top, right, bottom), size}. Cached by a key of the
## look; the caches stay small (one entry per theme look).

const Rim = preload("res://ui/theme/rim.gd")

static var _cache := {}

static func _key(parts: Array) -> String:
	return str(parts.hash())

## Inward distance of p to the nearest edge of a convex clockwise outline, and that edge's outward normal.
static func _edge(p: Vector2, pts: PackedVector2Array) -> Array:
	var best: float = INF
	var bn := Vector2.ZERO
	var n: int = pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var d: Vector2 = b - a
		var nrm := Vector2(d.y, -d.x).normalized()
		var din: float = -(p - a).dot(nrm)
		if din < best:
			best = din
			bn = nrm
	return [best, bn]

static func _over(dst: Color, src: Color) -> Color:
	var a: float = src.a + dst.a * (1.0 - src.a)
	if a <= 0.0001:
		return Color(0, 0, 0, 0)
	var r: float = (src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / a
	var g: float = (src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / a
	var b: float = (src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / a
	return Color(r, g, b, a)

## A FhStyle with rim > 0 (buttons, tabs, cards, wells, inputs, tooltips).
static func rim_tex(s) -> Dictionary:
	var ch: PackedFloat32Array = s.chamfer
	var key: String = "rim:" + _key([s.fill_top, s.fill_bottom, ch, s.rim, s.engraved, s.rim_tint, s.inner_glow, s.top_line, s.top_line_w])
	if _cache.has(key):
		return _cache[key]
	var gi: float = maxf(s.rim, 1.0)
	var cmax: float = maxf(maxf(ch[0], ch[1]), maxf(ch[2], ch[3]))
	var m: int = int(ceil(maxf(cmax, gi + (4.5 if s.inner_glow.a > 0.0 else 0.0)) + 2.0))
	var w: int = 2 * m + 8
	var h: int = 2 * m + 12
	var raised: bool = not s.engraved
	var t: Color = s.rim_tint
	var lit: Color = (Rim.LIT if raised else Rim.DARK) * t
	var dark: Color = (Rim.DARK if raised else Color(0.5, 0.58, 0.66, 1.0)) * t
	var side: Color = Rim.MID * t
	lit.a = t.a
	dark.a = t.a
	side.a = t.a
	var m1: Color = side.lerp(lit, 0.35) if raised else side.darkened(0.3)
	var m2: Color = side.darkened(0.25) if raised else side.lerp(dark, 0.3)
	var pts: PackedVector2Array = Rim.shape(Rect2(0, 0, w, h), ch)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		# Fill rows: top colour in the top margin, bottom colour in the bottom margin, a ramp in
		# the centre rows, so a stretched centre keeps a smooth gradient at any height.
		var ft: float = clampf(float(y - m) / float(h - 2 * m - 1), 0.0, 1.0)
		var fill: Color = s.fill_top.lerp(s.fill_bottom, ft)
		for x in w:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var e: Array = _edge(p, pts)
			var d: float = e[0]
			if d <= -0.5:
				continue
			var nrm: Vector2 = e[1]
			var f: float = nrm.x + nrm.y
			var c: Color = fill
			if s.inner_glow.a > 0.0 and d >= gi and d < gi + 4.5:
				var k: int = int((d - gi) / 1.5)
				var ig: Color = s.inner_glow
				c = _over(c, Color(ig.r, ig.g, ig.b, ig.a * (0.7 - 0.22 * float(k))))
			if s.top_line.a > 0.0 and p.y >= s.rim and p.y < s.rim + maxf(1.0, s.top_line_w) and p.x >= ch[0] and p.x <= float(w) - ch[1]:
				c = _over(c, s.top_line)
			if d < 1.0:
				c = _over(c, lit if f < -0.3 else (dark if f > 0.3 else side))
			elif d < 2.0 and s.rim >= 2.0:
				c = _over(c, m1 if f < -0.3 else (m2 if f > 0.3 else side))
			c.a *= clampf(d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, c)
	var out := {"tex": ImageTexture.create_from_image(img), "m": Vector4(m, m, m, m), "size": Vector2(w, h)}
	_cache[key] = out
	return out

## GlassFrame glass: tint gradient, the sheen fading over the top SHEEN px, the 1 px highlight at the
## top edge, the chamfer cut at the bottom right (and top left when cut_top).
const SHEEN := 48
static func glass_fill_tex(top: Color, bottom: Color, sheen: Color, highlight: Color, ch: float, cut_top: bool) -> Dictionary:
	var key: String = "glass:" + _key([top, bottom, sheen, highlight, ch, cut_top])
	if _cache.has(key):
		return _cache[key]
	var ml: int = int(ceil(ch)) + 2
	var mt: int = SHEEN
	var mb: int = int(ceil(ch)) + 2
	var w: int = 2 * ml + 8
	var h: int = mt + 8 + mb
	var pts: PackedVector2Array = Rim.shape(Rect2(0, 0, w, h), PackedFloat32Array([ch if cut_top else 0.0, 0.0, ch, 0.0]))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var tint: Color = top if y < mt else (bottom if y >= h - mb else top.lerp(bottom, float(y - mt) / 7.0))
		var sh_a: float = sheen.a * (1.0 - clampf((float(y) + 0.5) / float(mt), 0.0, 1.0))
		for x in w:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d: float = _edge(p, pts)[0]
			if d <= -0.5:
				continue
			var c: Color = _over(tint, Color(sheen.r, sheen.g, sheen.b, sh_a))
			if y == 0 and highlight.a > 0.0 and cut_top:
				c = _over(c, highlight)
			c.a *= clampf(d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, c)
	var out := {"tex": ImageTexture.create_from_image(img), "m": Vector4(ml, mt, ml, mb), "size": Vector2(w, h)}
	_cache[key] = out
	return out

## HUD panels (GlassFrame kind "hud", no title plate): the metal frame of ui/theme/metal.gd with the
## glass tint, a short sheen and the 1 px highlight painted into its transparent centre, so frame and
## glass are ONE nine-patch (tiled like the frame, draw_center on). The tint is the top colour in the
## top margin, the bottom colour in the bottom margin, their mean in the tiled middle.
static func frame_glass_tex(kind: String, top: Color, bottom: Color, sheen: Color, highlight: Color) -> Texture2D:
	var Metal = load("res://ui/theme/metal.gd")
	var key: String = "fg:" + _key([kind, top, bottom, sheen, highlight])
	if _cache.has(key):
		return _cache[key]
	var src: Image = (Metal.frame_tex(kind) as Texture2D).get_image()
	var n: int = src.get_width()
	var band: float = float(Metal.frame_band(kind))
	var mg: int = Metal.MARGIN
	var ch: float = maxf(0.0, Metal.CHAMFER - band * 0.6)
	var inner := Rect2(Vector2(band - 1.0, band - 1.0), Vector2(float(n) - 2.0 * band + 2.0, float(n) - 2.0 * band + 2.0))
	var pts: PackedVector2Array = Rim.shape(inner, PackedFloat32Array([ch, 0.0, ch, 0.0]))
	var mid: Color = top.lerp(bottom, 0.5)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var tint: Color = top if y < mg else (bottom if y >= n - mg else mid)
		var sh_a: float = sheen.a * (1.0 - clampf((float(y) + 0.5 - inner.position.y) / float(mg - int(band) + 1), 0.0, 1.0))
		for x in n:
			var fc: Color = src.get_pixel(x, y)
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d: float = _edge(p, pts)[0]
			var c := Color(0, 0, 0, 0)
			if d > -0.5:
				c = _over(tint, Color(sheen.r, sheen.g, sheen.b, sh_a))
				if y == int(inner.position.y) and highlight.a > 0.0 and p.x > inner.position.x + ch:
					c = _over(c, highlight)
				c.a *= clampf(d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, _over(c, fc))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Soft drop shadow: a rectangle with a 10 px fall-off, drawn as a nine-patch round the window.
static func shadow_tex(col: Color) -> Dictionary:
	var key: String = "shadow:" + _key([col])
	if _cache.has(key):
		return _cache[key]
	var m := 14
	var w: int = 2 * m + 4
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	for y in w:
		for x in w:
			var dx: float = maxf(0.0, maxf(float(m) - (float(x) + 0.5), (float(x) + 0.5) - float(w - m)))
			var dy: float = maxf(0.0, maxf(float(m) - (float(y) + 0.5), (float(y) + 0.5) - float(w - m)))
			var dd: float = sqrt(dx * dx + dy * dy)
			var a: float = col.a * clampf(1.0 - dd / float(m), 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a * a))
	var out := {"tex": ImageTexture.create_from_image(img), "m": Vector4(m, m, m, m), "size": Vector2(w, w)}
	_cache[key] = out
	return out

## Draws a baked look as one nine-patch.
static func draw(ci: RID, rect: Rect2, b: Dictionary, modulate: Color = Color.WHITE) -> void:
	var m: Vector4 = b["m"]
	RenderingServer.canvas_item_add_nine_patch(ci, rect, Rect2(Vector2.ZERO, b["size"]), (b["tex"] as Texture2D).get_rid(),
		Vector2(m.x, m.y), Vector2(m.z, m.w), RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true, modulate)

## True when a nine-patch with these margins fits the rect.
static func fits(rect: Rect2, b: Dictionary) -> bool:
	var m: Vector4 = b["m"]
	return rect.size.x >= m.x + m.z + 1.0 and rect.size.y >= m.y + m.w + 1.0
