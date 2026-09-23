extends RefCounted
## Factory functions of the design system. Every module builds its controls here, so one
## change of style changes the whole interface.

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const Icons = preload("res://ui/theme/icons.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const FhButton = preload("res://ui/widgets/fh_button.gd")
const GlowBar = preload("res://ui/widgets/glow_bar.gd")

const Sfx = preload("res://ui/sfx.gd")

static func sfx(name: String) -> void:
	Sfx.play(name)

# ---------------------------------------------------------------- text
static func label(text: String, variation: String = "", size: int = 0, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Uppercase, letter-spaced heading (Space Grotesk).
static func head(text: String, color: Color = P.TEXT_2, size: int = 12, font: String = "head") -> Label:
	var l: Label = label(text.to_upper(), "HeadLabel", size, color)
	if font != "head":
		l.add_theme_font_override("font", Fonts.get_font(font))
	return l

static func title(text: String, size: int = 20, color: Color = P.TEXT) -> Label:
	return label(text.to_upper(), "TitleLabel", size, color)

## Tabular number (JetBrains Mono).
static func num(text: String, size: int = 15, color: Color = P.TEXT, bold: bool = false) -> Label:
	return label(text, "NumBigLabel" if bold else "NumLabel", size, color)

static func dim(text: String, size: int = 13, color: Color = P.TEXT_2) -> Label:
	return label(text, "DimLabel", size, color)

static func wrap(text: String, size: int = 14, color: Color = P.TEXT_2, min_w: float = 0.0) -> Label:
	var l: Label = label(text, "", size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if min_w > 0.0:
		l.custom_minimum_size.x = min_w
	return l

static func rich(bbcode: String, size: int = 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("mono_font_size", size - 1)
	r.text = bbcode
	return r

# ---------------------------------------------------------------- icons
static func icon(name: String, px: int = 20, color: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.tex(name, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.modulate = color
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t

static func set_icon(t: TextureRect, name: String, px: int, color: Color) -> void:
	t.texture = Icons.tex(name, px)
	t.modulate = color

# ---------------------------------------------------------------- buttons
static func button(text: String, cb: Callable, tip: String = "", variation: String = "", icon_name: String = "", icon_px: int = 18) -> Button:
	var b = FhButton.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if variation != "":
		b.theme_type_variation = variation
	if icon_name != "":
		b.icon = Icons.tex(icon_name, icon_px)
		b.expand_icon = false
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	b.custom_minimum_size.y = 36
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func icon_button(icon_name: String, cb: Callable, tip: String = "", variation: String = "NavButton", px: int = 22, side: int = 42) -> Button:
	var b: Button = button("", cb, tip, variation, icon_name, px)
	b.custom_minimum_size = Vector2(side, side)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b

static func toggle(b: Button, on: bool) -> Button:
	b.toggle_mode = true
	b.set_pressed_no_signal(on)
	return b

# ---------------------------------------------------------------- layout
static func hbox(sep: int = 6, align: int = BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.alignment = align
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

static func grid(cols: int, h: int = 8, v: int = 8) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", h)
	g.add_theme_constant_override("v_separation", v)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func gap(w: float, h: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func sep() -> HSeparator:
	var s := HSeparator.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func vsep() -> VSeparator:
	var s := VSeparator.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func margin(child: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(child)
	return m

## A glass panel. `glass` adds the frosted backdrop.
static func panel(variation: String = "HudPanel", glass: bool = true, ch: Array = [12, 0, 12, 0]) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	if glass:
		Glass.attach(p, ch)
	return p

static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if horizontal else ScrollContainer.SCROLL_MODE_AUTO
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s

## Removes every child now and frees it. Layout sees the change in the same frame.
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

## Shrinks a free-standing panel to its content when the content got smaller.
static func fit(c: Control) -> void:
	var m: Vector2 = c.get_combined_minimum_size()
	if c.size.y > m.y + 0.5 or c.size.x > m.x + 0.5:
		c.reset_size()

# ---------------------------------------------------------------- data widgets
## Cost or amount chip: icon + tabular number. `ok` false colours it as missing.
static func chip(icon_name: String, text: String, color: Color = P.TEXT, tip: String = "", ok: bool = true, px: int = 16) -> HBoxContainer:
	var h: HBoxContainer = hbox(3)
	h.add_child(icon(icon_name, px, color if ok else P.RED))
	var n: Label = num(text, 13, P.TEXT if ok else P.RED)
	h.add_child(n)
	if tip != "":
		h.tooltip_text = tip
		h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h

static func bar(value: float, color: Color = P.CYAN, h: float = 8.0, target: float = -1.0) -> Control:
	var b = GlowBar.new()
	b.value = value
	b.color = color
	b.target = target
	b.custom_minimum_size = Vector2(40, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b

## A labelled bar row: NAME  [bar]  value
static func bar_row(name: String, value01: float, text: String, color: Color, name_w: float = 86.0, target: float = -1.0) -> HBoxContainer:
	var row: HBoxContainer = hbox(8)
	var l: Label = dim(name, 13)
	l.custom_minimum_size.x = name_w
	row.add_child(l)
	row.add_child(bar(value01, color, 8.0, target))
	var n: Label = num(text, 13, P.TEXT)
	n.custom_minimum_size.x = 46
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(n)
	return row

## A status badge: coloured dot + uppercase word.
static func badge(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = P.with_alpha(color, 0.16)
	s.border_color = P.with_alpha(color, 0.7)
	s.set_border_width_all(1)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: Label = head(text, color, 11)
	p.add_child(l)
	return p

# ---------------------------------------------------------------- numbers and time
static func fmt(v: float) -> String:
	var a: float = absf(v)
	if a >= 100000.0:
		return "%dk" % int(roundf(v / 1000.0))
	if a >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	if a >= 100.0 or absf(v - roundf(v)) < 0.05:
		return "%d" % int(roundf(v))
	if a >= 10.0:
		return "%.1f" % v
	return "%.1f" % v

static func signed(v: float) -> String:
	return ("+" if v >= 0.0 else "-") + fmt(absf(v))

static func clock(seconds: float) -> String:
	var s: int = int(maxf(0.0, seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]

static func days(d: float) -> String:
	if d >= 99.0:
		return "99+ d"
	return "%.1f d" % d

## "1 colonist", "2 colonists"; `many` for irregular plurals.
static func plural(n: int, one: String, many: String = "") -> String:
	if n == 1:
		return "1 " + one
	return "%d %s" % [n, many if many != "" else one + "s"]

static func pct(v01: float) -> String:
	return "%d%%" % int(roundf(clampf(v01, 0.0, 9.99) * 100.0))
