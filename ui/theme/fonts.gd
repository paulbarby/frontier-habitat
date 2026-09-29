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
	# Version 5: "The Regolith Rag" tabloid.
	"serif": "res://assets/fonts/SourceSerif4-400.woff2",
	"serif_i": "res://assets/fonts/SourceSerif4-400italic.woff2",
	"serif_sb": "res://assets/fonts/SourceSerif4-600.woff2",
	"heavy": "res://assets/fonts/Manrope-800.woff2",
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

## The Rag's condensed headline at one pixel size: Manrope 800, glyphs squeezed to 80 % (86 % for the
## masthead) and the advances closed by the same share (a transform squeezes the outlines, not the
## advances; a FontVariation over another FontVariation loses the weight, so each size is built here).
static var _rag := {}
static func rag_size(px: int, mast: bool = false) -> Font:
	var key: String = "%d:%s" % [px, mast]
	if _rag.has(key):
		return _rag[key]
	var sx: float = 0.86 if mast else 0.8
	var fv := FontVariation.new()
	fv.base_font = _file("heavy")
	fv.variation_opentype = {"weight": 800}
	fv.variation_transform = Transform2D(Vector2(sx, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	fv.spacing_glyph = -int(roundf(float(px) * (1.0 - sx) * 0.62))
	fv.spacing_space = int(roundf(float(px) * 0.12))
	_rag[key] = fv
	return fv

## A condensed cut of a font: glyphs squeezed to sx of their width (a FontVariation transform).
## Manrope is variable (wght 200-800, default 200): the weight is set here; space_px widens the
## space glyph, which the squeeze narrows too much.
static func _squeeze(base: Font, sx: float, spacing: int, weight: int = 800, space_px: int = 0) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	# The key is "weight" (or the OpenType tag as an int): a "wght" string key is ignored by Godot 4.4.
	fv.variation_opentype = {"weight": weight}
	fv.variation_transform = Transform2D(Vector2(sx, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	if spacing != 0:
		fv.spacing_glyph = spacing
	if space_px != 0:
		fv.spacing_space = space_px
	return fv

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
##   rag_head, rag_mast               Manrope 800 condensed (tabloid headlines, the masthead)
##   rag_body, rag_body_i, rag_body_b Source Serif 4 400 / italic / 600 (newsprint text)
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
		# The Rag: condensed heavy headlines (Manrope 800 squeezed to 80 % width), newsprint serif body.
		"rag_head": f = _squeeze(_file("heavy"), 0.8, 0, 800, 3)
		"rag_mast": f = _squeeze(_file("heavy"), 0.86, 1, 800, 6)
		"rag_label": f = _squeeze(_file("heavy"), 0.86, 1, 700, 3)
		"rag_body": f = _file("serif")
		"rag_body_i": f = _file("serif_i")
		"rag_body_b": f = _file("serif_sb")
		_: f = _variation(_file("inter"), 400, 0)
	_cache[name] = f
	return f
