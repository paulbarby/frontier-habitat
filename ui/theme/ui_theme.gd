extends RefCounted
## Builds the one Theme of the interface (docs/AAA_DESIGN.md §1, V4_DESIGN §7): glass panels in
## metal frames (ui/theme/glass_frame.gd), metal-rimmed buttons (ui/theme/rim.gd), cyan accents, uppercase letter-spaced headings,
## tabular numbers. Controls pick a look with `theme_type_variation`:
##   PanelContainer: HudPanel, CardPanel, WellPanel, ModalPanel, ToastPanel, HeaderPanel, FlatPanel
##   Button: PrimaryButton, GhostButton, TabButton, NavButton, ChipButton, DangerButton, CardButton, SpeedButton, ListButton
##   Label: HeadLabel, TitleLabel, DisplayLabel, NumLabel, NumBigLabel, DimLabel, SmallLabel

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const FhStyle = preload("res://ui/theme/fh_style.gd")

static func fh(fill_top: Color, fill_bottom: Color, border: Color, chamfer: Array = [8, 0, 8, 0], margins: Array = [10, 8, 10, 8]) -> StyleBox:
	var s = FhStyle.new()
	s.fill_top = fill_top
	s.fill_bottom = fill_bottom
	s.border = border
	s.chamfer = PackedFloat32Array(chamfer)
	s.content_margin_left = margins[0]
	s.content_margin_top = margins[1]
	s.content_margin_right = margins[2]
	s.content_margin_bottom = margins[3]
	return s

static func flat(color: Color, margins: Array = [0, 0, 0, 0], radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.content_margin_left = margins[0]
	s.content_margin_top = margins[1]
	s.content_margin_right = margins[2]
	s.content_margin_bottom = margins[3]
	s.set_corner_radius_all(radius)
	s.anti_aliasing = radius > 0
	return s

## Named panel looks, shared by the theme and by widgets that draw their own.
## Version 4 (critic round 15 rules): hud, modal and toast panels are GlassFrame (metal frame over
## glass); cards, wells and tooltips carry a thin metal rim (raised, or engraved for wells). The
## v3 cyan corner brackets are gone: one frame language.
static func glass_frame(kind: String, margins: Array) -> StyleBox:
	var s = load("res://ui/theme/glass_frame.gd").new()
	s.kind = kind
	s.content_margin_left = margins[0]
	s.content_margin_top = margins[1]
	s.content_margin_right = margins[2]
	s.content_margin_bottom = margins[3]
	return s

static func rimmed(fill_top: Color, fill_bottom: Color, chamfer: Array, margins: Array, w: float = 1.0, engraved: bool = false) -> StyleBox:
	var s = fh(fill_top, fill_bottom, Color(0, 0, 0, 0), chamfer, margins)
	s.rim = w
	s.engraved = engraved
	return s

## The selected tab: lit glass with a 2 px accent line in `accent` (the family colour).
static func tab_style(accent: Color) -> StyleBox:
	var s = rimmed(Color(0.13, 0.30, 0.42, 0.78), Color(0.07, 0.18, 0.27, 0.85), [6, 0, 0, 0], [12, 7, 12, 7], 1.0)
	s.top_line = accent
	s.top_line_w = 2.0
	s.inner_glow = Color(accent.r, accent.g, accent.b, 0.22)
	return s

static func panel_style(kind: String) -> StyleBox:
	match kind:
		"hud":
			return glass_frame("hud", [16, 12, 16, 12])
		"card":
			return rimmed(Color(0.085, 0.13, 0.21, 0.55), Color(0.06, 0.095, 0.16, 0.62), [7, 0, 7, 0], [9, 7, 9, 7], 1.0, true)
		"card_button":
			return rimmed(Color(0.085, 0.13, 0.21, 0.72), Color(0.06, 0.095, 0.16, 0.78), [7, 0, 7, 0], [9, 7, 9, 7], 2.0)
		"card_hover":
			var s = rimmed(Color(0.11, 0.18, 0.29, 0.82), Color(0.075, 0.125, 0.21, 0.86), [7, 0, 7, 0], [9, 7, 9, 7], 2.0)
			s.inner_glow = P.with_alpha(P.CYAN, 0.35)
			return s
		"card_selected":
			var s = rimmed(Color(0.10, 0.26, 0.34, 0.86), Color(0.06, 0.16, 0.23, 0.9), [7, 0, 7, 0], [9, 7, 9, 7], 2.0)
			s.inner_glow = P.with_alpha(P.CYAN, 0.6)
			return s
		"well":
			# A darker reading well behind lists and tables, sunk into the glass.
			return rimmed(Color(0.015, 0.03, 0.06, 0.62), Color(0.015, 0.03, 0.06, 0.70), [5, 0, 5, 0], [9, 7, 9, 7], 1.0, true)
		"modal":
			var s = glass_frame("window", [10, 10, 10, 12])
			# Critic round 21, fix 3: a 14 px frosted border zone, the body at about 88 %.
			s.tint_top = Color(0.09, 0.15, 0.24, 0.46)
			s.tint_bottom = Color(0.05, 0.08, 0.14, 0.56)
			s.frost_border = 14.0
			s.body_tint = Color(0.035, 0.06, 0.11, 0.85)
			return s
		"toast":
			var s = glass_frame("hud", [16, 9, 16, 9])
			s.accent_left = P.CYAN
			return s
		"tooltip":
			return rimmed(Color(0.07, 0.11, 0.19, 0.95), Color(0.045, 0.07, 0.12, 0.96), [6, 0, 6, 0], [11, 9, 11, 9], 2.0)
		"header":
			return rimmed(P.HEADER, Color(0.07, 0.115, 0.19, 0.92), [10, 0, 0, 0], [12, 6, 12, 6], 1.0)
		"flat":
			return fh(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), [0, 0, 0, 0], [0, 0, 0, 0])
	return glass_frame("hud", [16, 12, 16, 12])

static func _button_set(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())

static func _button_colors(t: Theme, type: String, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	for pair in [["font_color", normal], ["font_hover_color", hover], ["font_pressed_color", pressed], ["font_hover_pressed_color", pressed],
			["font_focus_color", normal], ["font_disabled_color", disabled], ["icon_normal_color", normal], ["icon_hover_color", hover],
			["icon_pressed_color", pressed], ["icon_hover_pressed_color", pressed], ["icon_focus_color", normal], ["icon_disabled_color", disabled]]:
		t.set_color(pair[0], type, pair[1])

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = Fonts.get_font("body")
	t.default_font_size = 15

	# ------------------------------------------------------------ panels
	t.set_stylebox("panel", "PanelContainer", panel_style("hud"))
	t.set_stylebox("panel", "Panel", panel_style("hud"))
	for pair in [["HudPanel", "hud"], ["CardPanel", "card"], ["WellPanel", "well"], ["ModalPanel", "modal"], ["ToastPanel", "toast"],
			["HeaderPanel", "header"], ["FlatPanel", "flat"], ["CardHoverPanel", "card_hover"], ["CardSelectedPanel", "card_selected"]]:
		t.set_type_variation(pair[0], "PanelContainer")
		t.set_stylebox("panel", pair[0], panel_style(pair[1]))

	# ------------------------------------------------------------ labels
	t.set_color("font_color", "Label", P.TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_font("font", "Label", Fonts.get_font("body"))
	t.set_font_size("font_size", "Label", 15)
	var labels := [
		["HeadLabel", "head", 12, P.TEXT_2], ["TitleLabel", "title", 20, P.TEXT], ["DisplayLabel", "display", 44, P.TEXT],
		["NumLabel", "mono", 15, P.TEXT], ["NumBigLabel", "mono_b", 20, P.TEXT], ["DimLabel", "body", 13, P.TEXT_2],
		["SmallLabel", "body", 12, P.TEXT_3], ["BodyStrong", "body_sb", 15, P.TEXT], ["SubHeadLabel", "head_rg", 14, P.TEXT],
	]
	for l in labels:
		t.set_type_variation(l[0], "Label")
		t.set_font("font", l[0], Fonts.get_font(l[1]))
		t.set_font_size("font_size", l[0], l[2])
		t.set_color("font_color", l[0], l[3])

	# ------------------------------------------------------------ rich text
	t.set_font("normal_font", "RichTextLabel", Fonts.get_font("body"))
	t.set_font("bold_font", "RichTextLabel", Fonts.get_font("body_b"))
	t.set_font("italics_font", "RichTextLabel", Fonts.get_font("body_md"))
	t.set_font("mono_font", "RichTextLabel", Fonts.get_font("mono"))
	t.set_font_size("normal_font_size", "RichTextLabel", 15)
	t.set_font_size("bold_font_size", "RichTextLabel", 15)
	t.set_font_size("mono_font_size", "RichTextLabel", 14)
	t.set_color("default_color", "RichTextLabel", P.TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())

	# ------------------------------------------------------------ buttons
	t.set_font("font", "Button", Fonts.get_font("body_sb"))
	t.set_font_size("font_size", "Button", 14)
	t.set_constant("h_separation", "Button", 8)
	# Version 4 buttons (critic round 15 rules): a glass fill with a 2 px bevelled metal rim.
	var bn = rimmed(Color(0.10, 0.16, 0.26, 0.72), Color(0.06, 0.10, 0.18, 0.80), [6, 0, 6, 0], [12, 7, 12, 7], 2.0)
	var bh = rimmed(Color(0.13, 0.22, 0.35, 0.86), Color(0.08, 0.145, 0.25, 0.9), [6, 0, 6, 0], [12, 7, 12, 7], 2.0)
	bh.inner_glow = P.with_alpha(P.CYAN, 0.3)
	var bp = rimmed(Color(0.08, 0.28, 0.38, 0.92), Color(0.05, 0.18, 0.26, 0.94), [6, 0, 6, 0], [12, 7, 12, 7], 2.0, true)
	bp.inner_glow = P.with_alpha(P.CYAN, 0.5)
	var bd = rimmed(Color(0.05, 0.08, 0.13, 0.55), Color(0.05, 0.08, 0.13, 0.6), [6, 0, 6, 0], [12, 7, 12, 7], 2.0)
	bd.rim_tint = Color(0.6, 0.6, 0.6, 1.0)
	_button_set(t, "Button", bn, bh, bp, bd)
	_button_colors(t, "Button", P.TEXT, Color.WHITE, Color.WHITE, P.TEXT_3)
	# Drop-down lists (OptionButton) look like buttons; they are not a type variation of Button.
	var on = bn.clone()
	on.content_margin_right = 30   # room for the arrow
	var oh = bh.clone()
	oh.content_margin_right = 30
	var op = bp.clone()
	op.content_margin_right = 30
	_button_set(t, "OptionButton", on, oh, op, bd)
	_button_colors(t, "OptionButton", P.TEXT, Color.WHITE, Color.WHITE, P.TEXT_3)
	t.set_font("font", "OptionButton", Fonts.get_font("body"))
	t.set_font_size("font_size", "OptionButton", 14)
	t.set_color("font_focus_color", "OptionButton", P.TEXT)

	# Primary: the one main action of a screen. It glows inside its rim; not a flat cyan block.
	t.set_type_variation("PrimaryButton", "Button")
	var pn = rimmed(Color(0.07, 0.30, 0.40, 0.86), Color(0.04, 0.19, 0.28, 0.9), [8, 0, 8, 0], [16, 9, 16, 9], 2.0)
	pn.inner_glow = P.with_alpha(P.CYAN, 0.75)
	var ph = rimmed(Color(0.10, 0.40, 0.52, 0.92), Color(0.06, 0.26, 0.36, 0.94), [8, 0, 8, 0], [16, 9, 16, 9], 2.0)
	ph.inner_glow = P.with_alpha(Color("9FF3FF"), 0.95)
	ph.rim_tint = Color(1.15, 1.2, 1.25, 1.0)
	var pp = rimmed(Color(0.05, 0.22, 0.30, 0.95), Color(0.04, 0.16, 0.22, 0.96), [8, 0, 8, 0], [16, 9, 16, 9], 2.0, true)
	pp.inner_glow = P.with_alpha(P.CYAN, 0.9)
	var pd = rimmed(Color(0.10, 0.15, 0.20, 0.55), Color(0.08, 0.12, 0.17, 0.6), [8, 0, 8, 0], [16, 9, 16, 9], 2.0)
	pd.rim_tint = Color(0.6, 0.6, 0.6, 1.0)
	_button_set(t, "PrimaryButton", pn, ph, pp, pd)
	_button_colors(t, "PrimaryButton", Color("DDFBFF"), Color.WHITE, Color.WHITE, P.TEXT_3)
	t.set_font("font", "PrimaryButton", Fonts.get_font("head"))
	t.set_font_size("font_size", "PrimaryButton", 15)

	# Ghost: no fill until hovered.
	t.set_type_variation("GhostButton", "Button")
	var gn = fh(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), [6, 0, 6, 0], [10, 6, 10, 6])
	var gh = rimmed(Color(0.12, 0.2, 0.32, 0.6), Color(0.08, 0.14, 0.24, 0.65), [6, 0, 6, 0], [10, 6, 10, 6], 1.0)
	var gp = rimmed(Color(0.1, 0.32, 0.42, 0.75), Color(0.07, 0.22, 0.3, 0.8), [6, 0, 6, 0], [10, 6, 10, 6], 1.0, true)
	_button_set(t, "GhostButton", gn, gh, gp, gn)
	_button_colors(t, "GhostButton", P.TEXT_2, Color.WHITE, P.CYAN, P.TEXT_3)

	# Tab: selected = pressed (toggle mode).
	t.set_type_variation("TabButton", "Button")
	# Metal edges; the selected tab is lit glass with the accent line (screens and the inspector
	# tint that line with the family colour, see tab_style()).
	var tn = rimmed(Color(0.06, 0.1, 0.17, 0.45), Color(0.05, 0.085, 0.15, 0.5), [6, 0, 0, 0], [12, 7, 12, 7], 1.0)
	tn.rim_tint = Color(0.8, 0.8, 0.8, 1.0)
	var th = rimmed(Color(0.1, 0.17, 0.28, 0.72), Color(0.07, 0.12, 0.2, 0.75), [6, 0, 0, 0], [12, 7, 12, 7], 1.0)
	var tp = tab_style(P.CYAN)
	_button_set(t, "TabButton", tn, th, tp, tn)
	_button_colors(t, "TabButton", P.TEXT_2, Color.WHITE, Color.WHITE, P.TEXT_3)
	t.set_font("font", "TabButton", Fonts.get_font("head"))
	t.set_font_size("font_size", "TabButton", 13)

	# Nav: square icon buttons of the right rail and the top bar.
	t.set_type_variation("NavButton", "Button")
	var nn = rimmed(Color(0.07, 0.12, 0.2, 0.74), Color(0.045, 0.075, 0.13, 0.8), [7, 0, 7, 0], [6, 6, 6, 6], 2.0)
	var nh = rimmed(Color(0.12, 0.21, 0.34, 0.88), Color(0.08, 0.14, 0.24, 0.9), [7, 0, 7, 0], [6, 6, 6, 6], 2.0)
	nh.inner_glow = P.with_alpha(P.CYAN, 0.4)
	var np = rimmed(Color(0.10, 0.34, 0.44, 0.92), Color(0.06, 0.22, 0.30, 0.94), [7, 0, 7, 0], [6, 6, 6, 6], 2.0, true)
	np.inner_glow = P.with_alpha(P.CYAN, 0.7)
	_button_set(t, "NavButton", nn, nh, np, nn)
	_button_colors(t, "NavButton", P.TEXT_2, Color.WHITE, Color.WHITE, P.TEXT_3)

	# Speed: compact time controls.
	t.set_type_variation("SpeedButton", "Button")
	var sn = fh(Color(0.07, 0.12, 0.2, 0.0), Color(0.045, 0.075, 0.13, 0.0), Color(0, 0, 0, 0), [5, 0, 5, 0], [6, 5, 6, 5])
	var sh = rimmed(Color(0.12, 0.21, 0.34, 0.8), Color(0.08, 0.14, 0.24, 0.85), [5, 0, 5, 0], [6, 5, 6, 5], 1.0)
	var sp = rimmed(Color(0.08, 0.30, 0.40, 0.92), Color(0.05, 0.2, 0.28, 0.94), [5, 0, 5, 0], [6, 5, 6, 5], 1.0, true)
	sp.inner_glow = P.with_alpha(P.CYAN, 0.8)
	_button_set(t, "SpeedButton", sn, sh, sp, sn)
	_button_colors(t, "SpeedButton", P.TEXT_2, Color.WHITE, Color("DDFBFF"), P.TEXT_3)

	# Chip: size chips S/M/L/XL and other small toggles.
	t.set_type_variation("ChipButton", "Button")
	var cn = rimmed(Color(0.07, 0.11, 0.18, 0.8), Color(0.07, 0.11, 0.18, 0.8), [3, 0, 3, 0], [6, 2, 6, 2], 1.0)
	var chh = rimmed(Color(0.12, 0.2, 0.32, 0.9), Color(0.12, 0.2, 0.32, 0.9), [3, 0, 3, 0], [6, 2, 6, 2], 1.0)
	var cp = rimmed(Color(0.08, 0.32, 0.42, 0.95), Color(0.05, 0.22, 0.3, 0.95), [3, 0, 3, 0], [6, 2, 6, 2], 1.0, true)
	cp.inner_glow = P.with_alpha(P.CYAN, 0.85)
	var cd = rimmed(Color(0.05, 0.07, 0.11, 0.6), Color(0.05, 0.07, 0.11, 0.6), [3, 0, 3, 0], [6, 2, 6, 2], 1.0)
	cd.rim_tint = Color(0.6, 0.6, 0.6, 1.0)
	_button_set(t, "ChipButton", cn, chh, cp, cd)
	_button_colors(t, "ChipButton", P.TEXT_2, Color.WHITE, Color("DDFBFF"), P.TEXT_3)
	t.set_font("font", "ChipButton", Fonts.get_font("mono_b"))
	t.set_font_size("font_size", "ChipButton", 12)

	# Danger: removal and other destructive actions.
	t.set_type_variation("DangerButton", "Button")
	var dn = rimmed(Color(0.2, 0.07, 0.09, 0.8), Color(0.14, 0.05, 0.07, 0.85), [6, 0, 6, 0], [12, 7, 12, 7], 2.0)
	dn.inner_glow = P.with_alpha(P.RED, 0.35)
	var dh = rimmed(Color(0.36, 0.1, 0.12, 0.9), Color(0.24, 0.07, 0.09, 0.92), [6, 0, 6, 0], [12, 7, 12, 7], 2.0)
	dh.inner_glow = P.with_alpha(P.RED, 0.75)
	_button_set(t, "DangerButton", dn, dh, dh, bd)
	_button_colors(t, "DangerButton", Color("FFC7C9"), Color.WHITE, Color.WHITE, P.TEXT_3)

	# Card: a whole clickable card (build bar, research nodes). Raised metal rim.
	t.set_type_variation("CardButton", "Button")
	_button_set(t, "CardButton", panel_style("card_button"), panel_style("card_hover"), panel_style("card_selected"), panel_style("card_button"))
	_button_colors(t, "CardButton", P.TEXT, Color.WHITE, Color.WHITE, P.TEXT_3)

	# List row: flat until hovered.
	t.set_type_variation("ListButton", "Button")
	var ln = flat(Color(1, 1, 1, 0.0), [10, 6, 10, 6])
	var lh = flat(Color(0.24, 0.88, 1.0, 0.1), [10, 6, 10, 6])
	var lp = flat(Color(0.24, 0.88, 1.0, 0.2), [10, 6, 10, 6])
	_button_set(t, "ListButton", ln, lh, lp, ln)
	_button_colors(t, "ListButton", P.TEXT, Color.WHITE, Color.WHITE, P.TEXT_3)
	t.set_font("font", "ListButton", Fonts.get_font("body"))

	# ------------------------------------------------------------ tooltip
	t.set_stylebox("panel", "TooltipPanel", panel_style("tooltip"))
	t.set_font("font", "TooltipLabel", Fonts.get_font("body"))
	t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_color("font_color", "TooltipLabel", P.TEXT)

	# ------------------------------------------------------------ scroll bars
	for sb_type in ["VScrollBar", "HScrollBar"]:
		var track := flat(Color(0.02, 0.04, 0.07, 0.5), [3, 3, 3, 3], 3)
		t.set_stylebox("scroll", sb_type, track)
		t.set_stylebox("scroll_focus", sb_type, track)
		t.set_stylebox("grabber", sb_type, flat(P.with_alpha(P.CYAN, 0.35), [3, 3, 3, 3], 3))
		t.set_stylebox("grabber_highlight", sb_type, flat(P.with_alpha(P.CYAN, 0.6), [3, 3, 3, 3], 3))
		t.set_stylebox("grabber_pressed", sb_type, flat(P.with_alpha(P.CYAN, 0.85), [3, 3, 3, 3], 3))
	t.set_constant("scrollbar_h_separation", "ScrollContainer", 4)
	t.set_constant("scrollbar_v_separation", "ScrollContainer", 4)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# ------------------------------------------------------------ line edit
	var le = rimmed(Color(0.02, 0.04, 0.075, 0.8), Color(0.02, 0.04, 0.075, 0.8), [5, 0, 5, 0], [10, 7, 10, 7], 1.0, true)
	var lf = rimmed(Color(0.03, 0.06, 0.1, 0.92), Color(0.03, 0.06, 0.1, 0.92), [5, 0, 5, 0], [10, 7, 10, 7], 1.0, true)
	lf.inner_glow = P.with_alpha(P.CYAN, 0.5)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lf)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_font("font", "LineEdit", Fonts.get_font("mono"))
	t.set_font_size("font_size", "LineEdit", 15)
	t.set_color("font_color", "LineEdit", P.TEXT)
	t.set_color("caret_color", "LineEdit", P.CYAN)
	t.set_color("selection_color", "LineEdit", P.with_alpha(P.CYAN, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", P.TEXT_3)

	# ------------------------------------------------------------ slider
	t.set_stylebox("slider", "HSlider", flat(Color(0.02, 0.04, 0.075, 0.9), [0, 3, 0, 3], 2))
	t.set_stylebox("grabber_area", "HSlider", flat(P.with_alpha(P.CYAN, 0.8), [0, 3, 0, 3], 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(P.CYAN, [0, 3, 0, 3], 2))
	t.set_icon("grabber", "HSlider", _svg_tex(_KNOB % ["#E6EEF7", "#3EE0FF"], 20))
	t.set_icon("grabber_highlight", "HSlider", _svg_tex(_KNOB % ["#FFFFFF", "#8FF0FF"], 20))
	t.set_icon("grabber_disabled", "HSlider", _svg_tex(_KNOB % ["#6A7F97", "#3A4A5C"], 20))

	# ------------------------------------------------------------ toggles
	t.set_icon("checked", "CheckButton", _svg_tex(_TOGGLE_ON, 40, 22))
	t.set_icon("unchecked", "CheckButton", _svg_tex(_TOGGLE_OFF, 40, 22))
	t.set_icon("checked_disabled", "CheckButton", _svg_tex(_TOGGLE_OFF, 40, 22))
	t.set_icon("unchecked_disabled", "CheckButton", _svg_tex(_TOGGLE_OFF, 40, 22))
	t.set_icon("checked", "CheckBox", _svg_tex(_BOX_ON, 18))
	t.set_icon("unchecked", "CheckBox", _svg_tex(_BOX_OFF, 18))
	for type in ["CheckButton", "CheckBox"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 2
		e.content_margin_right = 2
		e.content_margin_top = 4
		e.content_margin_bottom = 4
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			t.set_stylebox(st, type, e)
		t.set_font("font", type, Fonts.get_font("body"))
		t.set_font_size("font_size", type, 14)
		_button_colors(t, type, P.TEXT, Color.WHITE, P.TEXT, P.TEXT_3)
		t.set_constant("h_separation", type, 10)

	# ------------------------------------------------------------ progress bar, separators
	t.set_stylebox("background", "ProgressBar", flat(Color(0.02, 0.04, 0.075, 0.85), [0, 0, 0, 0], 2))
	t.set_stylebox("fill", "ProgressBar", flat(P.CYAN, [0, 0, 0, 0], 2))
	t.set_font("font", "ProgressBar", Fonts.get_font("mono"))
	t.set_font_size("font_size", "ProgressBar", 11)
	# Separators are engraved seams (critic round 15): a dark hairline and a light one.
	var SeamLine = load("res://ui/theme/seam_line.gd")
	t.set_stylebox("separator", "HSeparator", SeamLine.new())
	var vsep = SeamLine.new()
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_constant("separation", "HSeparator", 8)
	t.set_constant("separation", "VSeparator", 8)

	# ------------------------------------------------------------ containers
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("h_separation", "GridContainer", 8)
	t.set_constant("v_separation", "GridContainer", 8)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)

	# ------------------------------------------------------------ popup menus (option buttons)
	t.set_stylebox("panel", "PopupMenu", panel_style("tooltip"))
	t.set_stylebox("hover", "PopupMenu", flat(P.with_alpha(P.CYAN, 0.2), [8, 4, 8, 4]))
	t.set_font("font", "PopupMenu", Fonts.get_font("body"))
	t.set_color("font_color", "PopupMenu", P.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "PopupPanel", panel_style("tooltip"))
	return t

# ---------------------------------------------------------------- small raster art
const _KNOB := "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 20 20'><circle cx='10' cy='10' r='8' fill='%s'/><circle cx='10' cy='10' r='3.2' fill='%s'/></svg>"
const _TOGGLE_ON := "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='22' viewBox='0 0 40 22'><rect x='1' y='1' width='38' height='20' rx='10' fill='#3EE0FF' fill-opacity='0.35' stroke='#3EE0FF' stroke-width='1.5'/><circle cx='29' cy='11' r='7' fill='#E6EEF7'/></svg>"
const _TOGGLE_OFF := "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='22' viewBox='0 0 40 22'><rect x='1' y='1' width='38' height='20' rx='10' fill='#06101C' fill-opacity='0.9' stroke='#6A7F97' stroke-width='1.5'/><circle cx='11' cy='11' r='7' fill='#6A7F97'/></svg>"
const _BOX_ON := "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 18 18'><rect x='1' y='1' width='16' height='16' rx='3' fill='#3EE0FF'/><path d='M4.5 9.2l3 3 6-6.4' fill='none' stroke='#06101C' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'/></svg>"
const _BOX_OFF := "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 18 18'><rect x='1.5' y='1.5' width='15' height='15' rx='3' fill='#06101C' stroke='#6A7F97' stroke-width='1.5'/></svg>"

static func _svg_tex(svg: String, w: int, h: int = -1) -> Texture2D:
	var img := Image.new()
	var err: int = img.load_svg_from_string(svg, 1.0)
	if err != OK or img.is_empty():
		img = Image.create(w, h if h > 0 else w, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.24, 0.88, 1.0, 0.8))
	return ImageTexture.create_from_image(img)
