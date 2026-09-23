extends RefCounted
## Fonts of the interface. Inter for body text (variable: weights by FontVariation),
## Space Grotesk for headings and display text (wide tracking), JetBrains Mono for numbers.
## Fonts load at run time, so a missing import never breaks a parse check; a missing file
## falls back to the engine font.

const PATHS := {
	"inter": "res://assets/fonts/Inter.woff2",
	"grotesk": "res://assets/fonts/SpaceGrotesk-Regular.ttf",
	"grotesk_bold": "res://assets/fonts/SpaceGrotesk-Bold.ttf",
	"mono": "res://assets/fonts/JetBrainsMono-500.woff2",
	"mono_bold": "res://assets/fonts/JetBrainsMono-700.woff2",
}

static var _files := {}
static var _cache := {}

static func _file(key: String) -> Font:
	if _files.has(key):
		return _files[key]
	var f: Font = null
	var p: String = PATHS.get(key, "")
	if p != "" and ResourceLoader.exists(p):
		f = load(p) as Font
	if f == null:
		f = ThemeDB.fallback_font
	if f is FontFile:
		var ff: FontFile = f
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		ff.hinting = TextServer.HINTING_LIGHT
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		ff.generate_mipmaps = true
	_files[key] = f
	return f

static func _variation(base: Font, weight: int, spacing: int, features: Dictionary = {}) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	if weight > 0:
		fv.variation_opentype = {"wght": weight}
	if spacing != 0:
		fv.spacing_glyph = spacing
	if not features.is_empty():
		fv.opentype_features = features
	return fv

## Named fonts:
##   body, body_md, body_sb, body_b   Inter 400/500/600/700
##   head                             Space Grotesk Bold, +1 px tracking (small caps headings)
##   head_wide                        Space Grotesk Bold, +2 px tracking (section headings)
##   head_rg                          Space Grotesk Regular, +1 px
##   display                          Space Grotesk Bold, +6 px (the logo and screen titles)
##   title                            Space Grotesk Bold, +3 px
##   mono, mono_b                     JetBrains Mono 500/700 (tabular numbers)
static func get_font(name: String) -> Font:
	if _cache.has(name):
		return _cache[name]
	var f: Font
	match name:
		"body": f = _variation(_file("inter"), 400, 0)
		"body_md": f = _variation(_file("inter"), 500, 0)
		"body_sb": f = _variation(_file("inter"), 600, 0)
		"body_b": f = _variation(_file("inter"), 700, 0)
		"body_num": f = _variation(_file("inter"), 500, 0, {"tnum": 1})
		"head": f = _variation(_file("grotesk_bold"), 0, 1)
		"head_wide": f = _variation(_file("grotesk_bold"), 0, 2)
		"head_rg": f = _variation(_file("grotesk"), 0, 1)
		"title": f = _variation(_file("grotesk_bold"), 0, 3)
		"display": f = _variation(_file("grotesk_bold"), 0, 6)
		"mono": f = _file("mono")
		"mono_b": f = _file("mono_bold")
		_: f = _variation(_file("inter"), 400, 0)
	_cache[name] = f
	return f
