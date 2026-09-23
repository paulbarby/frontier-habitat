extends RefCounted
## Tooltip bodies. A tooltip text "Title\nbody…" shows the first line as a heading when
## it is short, and wraps the rest at a readable width.

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")

static func make(text: String, max_w: float = 340.0) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var lines: PackedStringArray = text.split("\n", true, 1)
	var body: String = text
	if lines.size() > 1 and lines[0].length() <= 40:
		var h := Label.new()
		h.text = lines[0].to_upper()
		h.add_theme_font_override("font", Fonts.get_font("head"))
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", P.CYAN)
		v.add_child(h)
		body = lines[1]
	if body.strip_edges() != "":
		var l := Label.new()
		l.text = body
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", P.TEXT)
		var font: Font = Fonts.get_font("body")
		var w: float = 0.0
		for line in body.split("\n"):
			w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
		if w > max_w:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = max_w
		v.add_child(l)
	return v
