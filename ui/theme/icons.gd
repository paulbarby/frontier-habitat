extends RefCounted
## Icon textures. The drawings live in res://assets/ui/icons/icons.json (written by
## tools/ui/make_icons.mjs). Each icon is rasterised at the pixel size it is drawn at
## (times 2, with mipmaps, so it stays sharp at any interface scale).
## Fallbacks, in order: the imported .svg texture, then a plain disc.

const MANIFEST := "res://assets/ui/icons/icons.json"

static var _svg := {}
static var _loaded := false
static var _cache := {}
static var _svg_ok := true

static func _load_manifest() -> void:
	_loaded = true
	if not FileAccess.file_exists(MANIFEST):
		return
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		_svg = d

static func has(name: String) -> bool:
	if not _loaded:
		_load_manifest()
	return _svg.has(name) or ResourceLoader.exists("res://assets/ui/icons/%s.svg" % name)

## Texture of icon `name` for drawing at `px` logical pixels.
static func tex(name: String, px: int = 24) -> Texture2D:
	if not _loaded:
		_load_manifest()
	var key := "%s@%d" % [name, px]
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	var src: String = _svg.get(name, "")
	if src != "" and _svg_ok:
		var img := Image.new()
		# The drawings are 48 px wide; rasterise at twice the drawn size.
		var err: int = img.load_svg_from_string(src, maxf(0.25, float(px) * 2.0 / 48.0))
		if err == OK and not img.is_empty():
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
		else:
			_svg_ok = false
	if t == null and ResourceLoader.exists("res://assets/ui/icons/%s.svg" % name):
		t = load("res://assets/ui/icons/%s.svg" % name) as Texture2D
	if t == null:
		t = _disc(px)
	_cache[key] = t
	return t

static func _disc(px: int) -> Texture2D:
	var n: int = maxi(4, px * 2)
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(n * 0.32 - d, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Icon names for content ids.
static func item(id: String) -> String:
	if id == "water":
		return "water_can"
	return id

static func category(cat: String) -> String:
	return "cat_" + cat

static func role(r: String) -> String:
	return "role_" + r
