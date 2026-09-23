extends RefCounted
## Builds the one Theme of the interface (docs/AAA_DESIGN.md §1): glass panels with
## chamfered corners and brackets, cyan accents, uppercase letter-spaced headings,
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
static func panel_style(kind: String) -> StyleBox:
	match kind:
		"hud":
			var s = fh(P.BG_TOP, P.BG, P.over_panel(P.CYAN, 0.30), [12, 0, 12, 0], [12, 10, 12, 10])
			s.bracket = P.with_alpha(P.CYAN, 0.9)
			s.bracket_len = 9.0
			return s
		"card":
			return fh(Color(0.085, 0.13, 0.21, 0.9), Color(0.06, 0.095, 0.16, 0.9), P.over_panel(P.CYAN, 0.18), [7, 0, 7, 0], [8, 6, 8, 6])
		"card_hover":
			var s = fh(Color(0.11, 0.18, 0.29, 0.94), Color(0.075, 0.125, 0.21, 0.94), P.over_panel(P.CYAN, 0.6), [7, 0, 7, 0], [8, 6, 8, 6])
			s.glow = P.with_alpha(P.CYAN, 0.35)
			s.glow_size = 5.0
			return s
		"card_selected":
			var s = fh(Color(0.10, 0.26, 0.34, 0.95), Color(0.06, 0.16, 0.23, 0.95), P.CYAN, [7, 0, 7, 0], [8, 6, 8, 6])
			s.glow = P.with_alpha(P.CYAN, 0.45)
			s.glow_size = 6.0
			return s
		"well":
			return fh(Color(0.02, 0.04, 0.075, 0.72), Color(0.02, 0.04, 0.075, 0.72), P.over_panel(P.CYAN, 0.12), [5, 0, 5, 0], [8, 6, 8, 6])
		"modal":
			var s = fh(Color(0.06, 0.10, 0.17, 0.95), Color(0.035, 0.06, 0.11, 0.95), P.over_panel(P.CYAN, 0.38), [18, 0, 18, 0], [0, 0, 0, 0])
			s.bracket = P.CYAN
			s.bracket_len = 16.0
			s.bracket_width = 2.0
			return s
		"toast":
			var s = fh(Color(0.07, 0.12, 0.2, 0.94), Color(0.045, 0.075, 0.13, 0.94), P.over_panel(P.CYAN, 0.35), [8, 0, 8, 0], [12, 8, 14, 8])
			s.accent = P.CYAN
			s.accent_w = 3.0
			return s
		"tooltip":
			var s = fh(Color(0.07, 0.11, 0.19, 0.97), Color(0.045, 0.07, 0.12, 0.97), P.over_panel(P.CYAN, 0.5), [6, 0, 6, 0], [10, 8, 10, 8])
			return s
		"header":
			return fh(P.HEADER, Color(0.07, 0.115, 0.19, 0.92), P.over_panel(P.CYAN, 0.3), [10, 0, 0, 0], [12, 6, 12, 6])
		"flat":
			return fh(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), [0, 0, 0, 0], [0, 0, 0, 0])
	return fh(P.BG_TOP, P.BG, P.over_panel(P.CYAN, 0.3))

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
	var bn = fh(Color(0.09, 0.15, 0.25, 0.92), Color(0.06, 0.105, 0.185, 0.92), P.over_panel(P.CYAN, 0.3), [6, 0, 6, 0], [12, 7, 12, 7])
	var bh = fh(Color(0.12, 0.21, 0.34, 0.96), Color(0.08, 0.145, 0.25, 0.96), P.over_panel(P.CYAN, 0.7), [6, 0, 6, 0], [12, 7, 12, 7])
	bh.glow = P.with_alpha(P.CYAN, 0.3)
	bh.glow_size = 4.0
	var bp = fh(Color(0.13, 0.42, 0.52, 0.96), Color(0.08, 0.28, 0.38, 0.96), P.CYAN, [6, 0, 6, 0], [12, 7, 12, 7])
	bp.glow = P.with_alpha(P.CYAN, 0.4)
	bp.glow_size = 5.0
	var bd = fh(Color(0.05, 0.08, 0.13, 0.7), Color(0.05, 0.08, 0.13, 0.7), P.over_panel(P.TEXT_3, 0.3), [6, 0, 6, 0], [12, 7, 12, 7])
	_button_set(t, "Button", bn, bh, bp, bd)
	_button_colors(t, "Button", P.TEXT, Color.WHITE, Color.WHITE, P.TEXT_3)

	# Primary: the one main action of a screen.
	t.set_type_variation("PrimaryButton", "Button")
	var pn = fh(Color(0.2, 0.78, 0.92, 0.95), Color(0.12, 0.58, 0.74, 0.95), P.CYAN, [8, 0, 8, 0], [16, 9, 16, 9])
	var ph = fh(Color(0.36, 0.9, 1.0, 1.0), Color(0.2, 0.7, 0.86, 1.0), Color.WHITE, [8, 0, 8, 0], [16, 9, 16, 9])
	ph.glow = P.with_alpha(P.CYAN, 0.55)
	ph.glow_size = 7.0
	var pp = fh(Color(0.1, 0.5, 0.62, 1.0), Color(0.08, 0.4, 0.52, 1.0), P.CYAN, [8, 0, 8, 0], [16, 9, 16, 9])
	var pd = fh(Color(0.12, 0.2, 0.28, 0.7), Color(0.1, 0.16, 0.22, 0.7), P.over_panel(P.TEXT_3, 0.3), [8, 0, 8, 0], [16, 9, 16, 9])
	_button_set(t, "PrimaryButton", pn, ph, pp, pd)
	_button_colors(t, "PrimaryButton", P.TEXT_DARK, P.TEXT_DARK, P.TEXT_DARK, P.TEXT_3)
	t.set_font("font", "PrimaryButton", Fonts.get_font("head"))
	t.set_font_size("font_size", "PrimaryButton", 15)

	# Ghost: no fill until hovered.
	t.set_type_variation("GhostButton", "Button")
	var gn = fh(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), [6, 0, 6, 0], [10, 6, 10, 6])
	var gh = fh(Color(0.12, 0.2, 0.32, 0.7), Color(0.08, 0.14, 0.24, 0.7), P.over_panel(P.CYAN, 0.45), [6, 0, 6, 0], [10, 6, 10, 6])
	var gp = fh(Color(0.1, 0.32, 0.42, 0.8), Color(0.07, 0.22, 0.3, 0.8), P.CYAN, [6, 0, 6, 0], [10, 6, 10, 6])
	_button_set(t, "GhostButton", gn, gh, gp, gn)
	_button_colors(t, "GhostButton", P.TEXT_2, Color.WHITE, P.CYAN, P.TEXT_3)

	# Tab: selected = pressed (toggle mode).
	t.set_type_variation("TabButton", "Button")
	var tn = fh(Color(0.06, 0.1, 0.17, 0.55), Color(0.05, 0.085, 0.15, 0.55), P.over_panel(P.CYAN, 0.14), [6, 0, 0, 0], [12, 7, 12, 7])
	var th = fh(Color(0.1, 0.17, 0.28, 0.85), Color(0.07, 0.12, 0.2, 0.85), P.over_panel(P.CYAN, 0.45), [6, 0, 0, 0], [12, 7, 12, 7])
	var tp = fh(Color(0.1, 0.3, 0.4, 0.95), Color(0.06, 0.18, 0.27, 0.95), P.over_panel(P.CYAN, 0.8), [6, 0, 0, 0], [12, 7, 12, 7])
	tp.top_line = P.CYAN
	_button_set(t, "TabButton", tn, th, tp, tn)
	_button_colors(t, "TabButton", P.TEXT_2, Color.WHITE, Color.WHITE, P.TEXT_3)
	t.set_font("font", "TabButton", Fonts.get_font("head"))
	t.set_font_size("font_size", "TabButton", 13)

	# Nav: square icon buttons of the right rail and the top bar.
	t.set_type_variation("NavButton", "Button")
	var nn = fh(Color(0.07, 0.12, 0.2, 0.86), Color(0.045, 0.075, 0.13, 0.86), P.over_panel(P.CYAN, 0.26), [7, 0, 7, 0], [6, 6, 6, 6])
	var nh = fh(Color(0.12, 0.21, 0.34, 0.95), Color(0.08, 0.14, 0.24, 0.95), P.over_panel(P.CYAN, 0.75), [7, 0, 7, 0], [6, 6, 6, 6])
	nh.glow = P.with_alpha(P.CYAN, 0.35)
	nh.glow_size = 5.0
	var np = fh(Color(0.12, 0.4, 0.5, 0.95), Color(0.07, 0.26, 0.35, 0.95), P.CYAN, [7, 0, 7, 0], [6, 6, 6, 6])
	np.glow = P.with_alpha(P.CYAN, 0.45)
	np.glow_size = 5.0
	_button_set(t, "NavButton", nn, nh, np, nn)
	_button_colors(t, "NavButton", P.TEXT_2, Color.WHITE, Color.WHITE, P.TEXT_3)

	# Speed: compact time controls.
	t.set_type_variation("SpeedButton", "Button")
	var sn = fh(Color(0.07, 0.12, 0.2, 0.0), Color(0.045, 0.075, 0.13, 0.0), P.over_panel(P.CYAN, 0.16), [5, 0, 5, 0], [6, 5, 6, 5])
	var sh = fh(Color(0.12, 0.21, 0.34, 0.9), Color(0.08, 0.14, 0.24, 0.9), P.over_panel(P.CYAN, 0.6), [5, 0, 5, 0], [6, 5, 6, 5])
	var sp = fh(Color(0.18, 0.62, 0.74, 0.95), Color(0.1, 0.42, 0.54, 0.95), P.CYAN, [5, 0, 5, 0], [6, 5, 6, 5])
	sp.glow = P.with_alpha(P.CYAN, 0.4)
	sp.glow_size = 4.0
	_button_set(t, "SpeedButton", sn, sh, sp, sn)
	_button_colors(t, "SpeedButton", P.TEXT_2, Color.WHITE, P.TEXT_DARK, P.TEXT_3)

	# Chip: size chips S/M/L/XL and other small toggles.
	t.set_type_variation("ChipButton", "Button")
	var cn = fh(Color(0.07, 0.11, 0.18, 0.9), Color(0.07, 0.11, 0.18, 0.9), P.over_panel(P.CYAN, 0.22), [3, 0, 3, 0], [6, 2, 6, 2])
	var chh = fh(Color(0.12, 0.2, 0.32, 0.95), Color(0.12, 0.2, 0.32, 0.95), P.over_panel(P.CYAN, 0.7), [3, 0, 3, 0], [6, 2, 6, 2])
	var cp = fh(Color(0.24, 0.82, 0.96, 1.0), Color(0.16, 0.66, 0.8, 1.0), P.CYAN, [3, 0, 3, 0], [6, 2, 6, 2])
	var cd = fh(Color(0.05, 0.07, 0.11, 0.7), Color(0.05, 0.07, 0.11, 0.7), P.over_panel(P.TEXT_3, 0.2), [3, 0, 3, 0], [6, 2, 6, 2])
	_button_set(t, "ChipButton", cn, chh, cp, cd)
	_button_colors(t, "ChipButton", P.TEXT_2, Color.WHITE, P.TEXT_DARK, P.TEXT_3)
	t.set_font("font", "ChipButton", Fonts.get_font("mono_b"))
	t.set_font_size("font_size", "ChipButton", 12)

	# Danger: removal and other destructive actions.
	t.set_type_variation("DangerButton", "Button")
	var dn = fh(Color(0.2, 0.07, 0.09, 0.9), Color(0.14, 0.05, 0.07, 0.9), P.over_panel(P.RED, 0.45), [6, 0, 6, 0], [12, 7, 12, 7])
	var dh = fh(Color(0.36, 0.1, 0.12, 0.95), Color(0.24, 0.07, 0.09, 0.95), P.RED, [6, 0, 6, 0], [12, 7, 12, 7])
	dh.glow = P.with_alpha(P.RED, 0.35)
	dh.glow_size = 4.0
	_button_set(t, "DangerButton", dn, dh, dh, bd)
	_button_colors(t, "DangerButton", Color("FFC7C9"), Color.WHITE, Color.WHITE, P.TEXT_3)

	# Card: a whole clickable card (build bar, research nodes, list rows).
	t.set_type_variation("CardButton", "Button")
	_button_set(t, "CardButton", panel_style("card"), panel_style("card_hover"), panel_style("card_selected"), panel_style("card"))
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
	var le = fh(Color(0.02, 0.04, 0.075, 0.85), Color(0.02, 0.04, 0.075, 0.85), P.over_panel(P.CYAN, 0.3), [5, 0, 5, 0], [10, 7, 10, 7])
	var lf = fh(Color(0.03, 0.06, 0.1, 0.95), Color(0.03, 0.06, 0.1, 0.95), P.CYAN, [5, 0, 5, 0], [10, 7, 10, 7])
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
	var sep := StyleBoxLine.new()
	sep.color = P.LINE_SOFT
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = P.LINE_SOFT
	vsep.thickness = 1
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
