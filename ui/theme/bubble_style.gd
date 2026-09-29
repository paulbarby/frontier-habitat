extends RefCounted
## The glass speech bubble style (V5_DESIGN §3, §10) that the UI supplies to RENDER's bubbles
## (presentation/fx_bubbles.gd ui_style(dict)). The same glass as the HUD panels: a dark blue-grey
## body at 80 %, a cool rim, a warm gold rim on the followed person's bubble, the name in the cyan
## accent, the text in the HUD text colour, Inter at the text floor size.
## Keys: bg, border, follow_border, text, name, radius, font_size, font (Font), shadow, emote colours.

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")

static func style() -> Dictionary:
	return {
		"bg": Color(0.055, 0.085, 0.13, 0.80),
		"border": Color(0.55, 0.78, 0.95, 0.60),
		"follow_border": Color(1.0, 0.82, 0.40, 0.95),
		"text": P.TEXT,
		"name": P.CYAN,
		"radius": 10,
		"font_size": P.fs(14),
		"font": Fonts.get_font("body_md"),
		"shadow": Color(0, 0, 0, 0.40),
		"emote": {"heart": Color("F472B6"), "anger": Color("FF5A5F"), "zzz": Color("A5B4FC"), "music": Color("6EE7A8"),
			"sweat": Color("7DD3FC"), "credit": Color("FFD166"), "question": Color("E5E7EB")},
	}

## Gives the style to RENDER's bubbles (when the view has them).
static func apply(view) -> void:
	if view == null:
		return
	var b = view.get("bubbles")
	if b != null and b is Object and (b as Object).has_method("ui_style"):
		b.ui_style(style())
		var f: Font = Fonts.get_font("body_md")
		if "font" in b:
			b.font = f
