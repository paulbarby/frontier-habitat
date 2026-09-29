extends Control
## The lead photo of "The Regolith Rag" (V5_DESIGN §4.4). With RENDER's photo (a 512×384 texture) it
## shows it; until then a "paparazzi" placeholder: a warm, grainy flash shot of two silhouettes set by
## the pose (close for a kiss or a hug, apart with raised arms for an argument), a vignette and the
## snapper's stamp. Few draw calls: one gradient, the grain texture, a few shapes, one line of text.

const Fonts = preload("res://ui/theme/fonts.gd")

var texture: Texture2D
var pose := "talk"
var place := ""
static var _grain: Texture2D
static var _dots: Texture2D

## A halftone screen: a grid of soft dots (tiled over the photo, as newsprint printing).
static func dots() -> Texture2D:
	if _dots != null:
		return _dots
	var img := Image.create(8, 8, false, Image.FORMAT_LA8)
	for y in 8:
		for x in 8:
			var d: float = Vector2(x - 3.5, y - 3.5).length()
			var a: float = clampf(1.0 - (d - 1.4) / 1.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, 0.0 if a > 0.5 else 0.35 * (1.0 - a * 2.0)))
	_dots = ImageTexture.create_from_image(img)
	return _dots

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

static func grain() -> Texture2D:
	if _grain != null:
		return _grain
	var img := Image.create(128, 128, false, Image.FORMAT_LA8)
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_VALUE
	n.frequency = 0.9
	n.seed = 4242
	for y in 128:
		for x in 128:
			var v: float = n.get_noise_2d(x, y) * 0.5 + 0.5
			img.set_pixel(x, y, Color(v, v, v, 0.22))
	_grain = ImageTexture.create_from_image(img)
	return _grain

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if texture != null:
		draw_texture_rect(texture, r, false)
		draw_texture_rect(dots(), r, true, Color(1, 1, 1, 0.8))
		draw_texture_rect(grain(), r, true, Color(1, 1, 1, 0.5))
		return
	# Background: a warm corridor lit by a camera flash from the left.
	var top := Color(0.30, 0.22, 0.17)
	var bot := Color(0.10, 0.08, 0.07)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top.lightened(0.25), top, bot, bot.lightened(0.1)]))
	# A door frame and a wall light, so it reads as a place.
	var dx: float = size.x * 0.72
	draw_rect(Rect2(dx, size.y * 0.12, size.x * 0.16, size.y * 0.78), Color(0.05, 0.04, 0.04, 0.6), true)
	draw_rect(Rect2(dx + 6.0, size.y * 0.12 + 6.0, size.x * 0.16 - 12.0, size.y * 0.78 - 6.0), Color(0.55, 0.42, 0.28, 0.35), true)
	draw_circle(Vector2(size.x * 0.18, size.y * 0.16), size.y * 0.05, Color(1.0, 0.85, 0.6, 0.45))
	# Two silhouettes.
	var close: bool = pose in ["kiss_brief", "hug", "hold_hands_walk", "flirt_lean"]
	var gap: float = size.x * (0.13 if close else 0.24)
	var cx: float = size.x * 0.42
	for i in 2:
		var x: float = cx - gap * 0.5 if i == 0 else cx + gap * 0.5
		var h: float = size.y * (0.20 if i == 0 else 0.185)
		var head := Vector2(x, size.y * 0.40 - (0.0 if i == 0 else size.y * 0.02))
		var col := Color(0.04, 0.03, 0.03, 0.92)
		draw_circle(head, h * 0.36, col)
		var sh := PackedVector2Array([head + Vector2(-h * 0.9, h * 0.55), head + Vector2(h * 0.9, h * 0.55), head + Vector2(h * 1.15, size.y), head + Vector2(-h * 1.15, size.y)])
		draw_colored_polygon(sh, col)
		if pose in ["argue", "shout", "cheer"]:
			var arm_dir: float = -1.0 if i == 0 else 1.0
			draw_line(head + Vector2(arm_dir * h * 0.7, h * 0.7), head + Vector2(arm_dir * h * 1.6, -h * 0.4), col, h * 0.26)
	# Flash glare, vignette, grain.
	draw_circle(Vector2(size.x * 0.05, size.y * 0.5), size.y * 0.55, Color(1.0, 0.95, 0.85, 0.07))
	draw_texture_rect(dots(), r, true, Color(1, 1, 1, 0.9))
	draw_texture_rect(grain(), r, true, Color(1, 1, 1, 1))
	var v := Color(0, 0, 0, 0.45)
	var clear := Color(0, 0, 0, 0)
	var e: float = size.y * 0.18
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, e), Vector2(0, e)]), PackedColorArray([v, v, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, size.y - e), Vector2(size.x, size.y - e), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([clear, clear, v, v]))
	var f: Font = Fonts.rag_size(14)
	draw_string(f, Vector2(size.x - 128.0, size.y - 12.0), "RAG SNAP", HORIZONTAL_ALIGNMENT_RIGHT, 118.0, 14, Color(1, 1, 1, 0.55))
