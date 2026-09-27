extends RefCounted
## Space-age metal (docs/V4_DESIGN.md §7): procedural textures for the frames of glass panels,
## made once at start and cached. No image files.
##
## frame_tex(kind): a nine-patch texture SIZE x SIZE with margins MARGIN: a brushed gunmetal band
##   BAND px wide round a transparent centre (the glass shows there), chamfered top-left and
##   bottom-right corners, an outer bevel (light top-left edge, dark bottom-right edge), a dark inner
##   lip and a faint cyan inner glow line, a rivet in every corner, and in the middle of each edge
##   tile a rivet with a seam line at the tile start. Drawn with canvas_item_add_nine_patch in TILE
##   mode, the edge tiles repeat: a seam every TILE px and a rivet between seams.
## plate_tex(): a horizontal brushed plate for window title bars: light top edge, engraved seam at
##   the bottom (dark then light line). No rivets of its own (the frame carries them).
##
## kind "hud": 8 px band, for HUD bars. kind "window": 10 px, for windows. Rivets 7–9 px, domed, at the
## corners and one per 180 px edge tile (critic round 15).

const MARGIN := 24
const TILE := 180
const SIZE := MARGIN * 2 + TILE
const CHAMFER := 12.0

static var _cache := {}

static func frame_band(kind: String) -> int:
	return 8 if kind == "hud" else 10

## Brushed metal value at (x, y) for a band running along `along_x` (streaks follow the band).
static func _brushed(x: int, y: int, along_x: bool) -> float:
	var row: int = y if along_x else x
	var col: int = x if along_x else y
	# Per-row streak level (hash), plus a slow wave along the streak.
	var h: float = float(((row * 73856093) ^ 19349663) & 1023) / 1023.0
	var h2: float = float((((row * 83492791) ^ (col / 23) * 2654435761) & 1023)) / 1023.0
	return (h - 0.5) * 0.13 + (h2 - 0.5) * 0.05

static func _inside_chamfer(x: float, y: float, w: float, h: float, ch: float) -> bool:
	# Top-left and bottom-right corners cut at 45 degrees.
	if x + y < ch:
		return false
	if (w - x) + (h - y) < ch:
		return false
	return true

static func frame_tex(kind: String = "window") -> Texture2D:
	var key := "frame:" + kind
	if _cache.has(key):
		return _cache[key]
	var band: int = frame_band(kind)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var top := Color("6C7783")
	var bot := Color("363E47")
	var s := float(SIZE)
	for y in SIZE:
		for x in SIZE:
			var fx: float = float(x) + 0.5
			var fy: float = float(y) + 0.5
			if not _inside_chamfer(fx, fy, s, s, CHAMFER):
				continue
			# Distance into the panel from the outer edge (chamfer counted as an edge too).
			var d_tl: float = ((fx + fy) - CHAMFER) * 0.7071
			var d_br: float = (((s - fx) + (s - fy)) - CHAMFER) * 0.7071
			var lit_d: float = minf(minf(fx, fy), d_tl)          # top, left and top-left edges catch light
			var dark_d: float = minf(minf(s - fx, s - fy), d_br) # bottom, right and bottom-right are in shade
			var d_edge: float = minf(lit_d, dark_d)
			var lit: bool = lit_d <= dark_d
			if d_edge > float(band):
				continue
			var horizontal: bool = minf(fy, s - fy) <= minf(fx, s - fx)
			var t: float = fy / s
			var c: Color = top.lerp(bot, t)
			var v: float = _brushed(x, y, horizontal)
			c = Color(c.r + v, c.g + v, c.b + v * 1.1, 1.0)
			# Bevel: outer 1 px light on top/left, dark on bottom/right; inner lip dark.
			if d_edge < 1.0:
				c = c.lightened(0.35) if lit else c.darkened(0.45)
			elif d_edge < 2.0:
				c = c.lightened(0.12) if lit else c.darkened(0.15)
			elif d_edge > float(band) - 1.0:
				c = Color(0.05, 0.08, 0.1, 1.0)            # inner lip (shadow into the glass)
			elif d_edge > float(band) - 2.0:
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	# Faint cyan glow line just inside the band (the glass edge catches light).
	var glow := Color(0.36, 0.86, 1.0, 0.28)
	for i in range(band, SIZE - band):
		for pt in [Vector2i(i, band), Vector2i(i, SIZE - band - 1), Vector2i(band, i), Vector2i(SIZE - band - 1, i)]:
			if _inside_chamfer(float(pt.x) + 0.5, float(pt.y) + 0.5, s, s, CHAMFER + float(band) * 1.4):
				img.set_pixel(pt.x, pt.y, glow)
	# Seams at the start of each edge tile: an engraved line across the band.
	var mid: float = float(band) * 0.5
	for e in [MARGIN, SIZE - MARGIN]:
		for k in band:
			_px(img, e, k, Color(0.08, 0.1, 0.12, 1.0))
			_px(img, e + 1, k, Color(0.52, 0.58, 0.64, 1.0))
			_px(img, e, SIZE - 1 - k, Color(0.08, 0.1, 0.12, 1.0))
			_px(img, e + 1, SIZE - 1 - k, Color(0.52, 0.58, 0.64, 1.0))
			_px(img, k, e, Color(0.08, 0.1, 0.12, 1.0))
			_px(img, k, e + 1, Color(0.52, 0.58, 0.64, 1.0))
			_px(img, SIZE - 1 - k, e, Color(0.08, 0.1, 0.12, 1.0))
			_px(img, SIZE - 1 - k, e + 1, Color(0.52, 0.58, 0.64, 1.0))
	# Rivets: corners and mid tile of each edge.
	var r: float = 3.5 if kind == "hud" else 4.3
	var c0 := MARGIN + TILE / 2
	for p in [Vector2(c0, mid), Vector2(c0, s - mid), Vector2(mid, c0), Vector2(s - mid, c0),
			Vector2(CHAMFER + r + 3.0, mid), Vector2(s - mid, s - CHAMFER - r - 3.0), Vector2(s - mid - 2.0, mid), Vector2(mid, s - mid - 2.0)]:
		_rivet(img, p, r)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if img.get_pixel(x, y).a < 0.5:
		return
	img.set_pixel(x, y, c)

## A domed rivet: dark ring, lit body (light from the top left), a specular dot.
static func _rivet(img: Image, c: Vector2, r: float) -> void:
	for y in range(int(c.y - r - 2), int(c.y + r + 2)):
		for x in range(int(c.x - r - 2), int(c.x + r + 2)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d: float = p.distance_to(c)
			if d > r + 0.9:
				continue
			var col: Color
			if d > r:
				# Dark seat ring, with a light rim on the lower right (the rivet sits in a recess).
				col = Color(0.04, 0.05, 0.07, 1.0) if (p.x - c.x) + (p.y - c.y) < 0.0 else Color(0.5, 0.56, 0.62, 1.0)
			else:
				# Dome: surface normal from the sphere height, lit from the top left and above.
				var q: Vector2 = (p - c) / r
				var z: float = sqrt(maxf(0.0, 1.0 - q.length_squared()))
				var n := Vector3(q.x, q.y, z)
				var l: float = clampf(n.dot(Vector3(-0.5, -0.5, 0.71)), 0.0, 1.0)
				col = Color(0.22, 0.25, 0.29).lerp(Color(0.86, 0.9, 0.95), l)
				var spec: float = pow(l, 18.0)
				col = col.lerp(Color(1, 1, 1), spec)
			img.set_pixel(x, y, col)

## Title bar plate for windows: 64 x h, margins 16. No rivets (critic round 15: the end rivet read as a stray pixel).
static func plate_tex(h: int = 34) -> Texture2D:
	var key := "plate:%d" % h
	if _cache.has(key):
		return _cache[key]
	var w := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top := Color("5E6873")
	var bot := Color("2E353E")
	for y in h:
		for x in w:
			var c: Color = top.lerp(bot, float(y) / float(h))
			var v: float = _brushed(x, y, true)
			c = Color(c.r + v, c.g + v, c.b + v * 1.1, 0.96)
			if y == 0:
				c = c.lightened(0.3)
			elif y == h - 2:
				c = Color(0.06, 0.08, 0.1, 1.0)
			elif y == h - 1:
				c = Color(0.46, 0.52, 0.58, 1.0)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
