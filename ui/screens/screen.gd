extends Control
## Base of every full screen: a dimmed, blurred backdrop and one large glass frame with a
## header (icon, title, subtitle, tabs, close) and a content area. Subclasses override
## build() and refresh(), and build_tab(id) when they have tabs.
## `compact` screens (dialogs) are a centred frame of `compact_size`.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")

var hud
var host
var arg = null
var screen_name := ""
var pauses := false
var title := ""
var subtitle := ""
var icon := ""
var accent := P.CYAN
var tabs: Array = []            # [[id, label, icon], ...]
var tab := ""
var compact := false
var compact_size := Vector2(560, 300)
var margins := Vector4(36, 28, 36, 28)
var closable := true
var dim := 0.58
var content: VBoxContainer
var frame: PanelContainer
var _tab_buttons := {}
var _subtitle_label: Label
var _scroll: ScrollContainer     # holds `content`: a screen larger than the view scrolls
var _hdr: Control
var _last_vp := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, dim)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bb)
	frame = Kit.panel("ModalPanel", true, [18, 0, 18, 0])
	if compact:
		frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		frame.custom_minimum_size = compact_size
		frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
		frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.offset_left = margins.x
		frame.offset_top = margins.y
		frame.offset_right = -margins.z
		frame.offset_bottom = -margins.w
	add_child(frame)
	var outer: VBoxContainer = Kit.vbox(0)
	frame.add_child(outer)
	_hdr = _hdrer()
	outer.add_child(_hdr)
	# Window bounds (Paul, 2026-09-25): the content sits in a scroll area, so a screen never
	# needs more room than the view has. ui/hud/bounds_keeper.gd calls fit_view() each frame.
	content = Kit.vbox(10)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(content)
	var m: MarginContainer = Kit.margin(_scroll, 22, 16, 22, 18)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(m)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	if not tabs.is_empty() and tab == "":
		tab = String(tabs[0][0])
	build()
	if not tabs.is_empty():
		_build_tab_content()
	fit_view(get_viewport_rect().size)
	# Enter: a fade only. (A slide moved the frame with a tween; with the bounds keeper that
	# would fight the clamp, and a compact dialog could keep a stale position.)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

## Window bounds: sizes this screen for a view of `vp` (each frame, from
## ui/hud/bounds_keeper.gd). Compact dialogs: at most the view width minus 16 px; the content
## area as tall as the content but no taller than the view allows (then it scrolls); centred.
## Full screens: the frame keeps its margins but never less than 8 px from the edge.
func fit_view(vp: Vector2) -> void:
	if frame == null or _scroll == null:
		return
	if compact:
		frame.custom_minimum_size = Vector2(minf(compact_size.x, vp.x - 16.0), 0.0)
		_scroll.custom_minimum_size.y = content.get_combined_minimum_size().y
		var excess: float = frame.get_combined_minimum_size().y - (vp.y - 16.0)
		if excess > 0.0:
			_scroll.custom_minimum_size.y = maxf(40.0, _scroll.custom_minimum_size.y - excess)
		var sz: Vector2 = frame.get_combined_minimum_size()
		if not frame.size.is_equal_approx(sz) or vp != _last_vp:
			frame.size = sz
			frame.position = ((vp - sz) * 0.5).floor()
	elif vp != _last_vp:
		var mx: float = minf(margins.x, maxf(8.0, vp.x * 0.02))
		var my: float = minf(margins.y, maxf(8.0, vp.y * 0.02))
		frame.offset_left = mx
		frame.offset_right = -mx
		frame.offset_top = my
		frame.offset_bottom = -my
	_last_vp = vp

func _hdrer() -> Control:
	var hp := PanelContainer.new()
	var st = load("res://ui/theme/ui_theme.gd").panel_style("header")
	st.chamfer = PackedFloat32Array([18, 0, 0, 0])
	st.header_line = Color(0, 0, 0, 0)
	st.fill_top = Color(0.1, 0.16, 0.26, 0.6)
	st.fill_bottom = Color(0.06, 0.1, 0.17, 0.3)
	st.border = Color(0, 0, 0, 0)
	st.content_margin_left = 22
	st.content_margin_right = 14
	st.content_margin_top = 12
	st.content_margin_bottom = 10
	hp.add_theme_stylebox_override("panel", st)
	hp.mouse_filter = Control.MOUSE_FILTER_PASS
	# Window bounds: the title, tabs and extras sit in a sideways clip area, so a narrow view
	# never makes the frame wider than the view; the close button stays outside it.
	var bar: HBoxContainer = Kit.hbox(6)
	hp.add_child(bar)
	var hsc := ScrollContainer.new()
	hsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	hsc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hsc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsc.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(hsc)
	var row: HBoxContainer = Kit.hbox(14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsc.add_child(row)
	if icon != "":
		var ic: TextureRect = Kit.icon(icon, 30, accent)
		row.add_child(ic)
	var tv: VBoxContainer = Kit.vbox(0)
	row.add_child(tv)
	var t: Label = Kit.label(title.to_upper(), "TitleLabel", 24 if not compact else 18, P.TEXT)
	tv.add_child(t)
	_subtitle_label = Kit.label(subtitle, "DimLabel", 13, P.TEXT_2)
	_subtitle_label.visible = subtitle != ""
	tv.add_child(_subtitle_label)
	row.add_child(Kit.gap(16))
	var tabs_row: HBoxContainer = Kit.hbox(4)
	tabs_row.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(tabs_row)
	for t2 in tabs:
		var id: String = t2[0]
		var b: Button = Kit.button(String(t2[1]), func(): set_tab(id), "", "TabButton", String(t2[2]) if t2.size() > 2 else "", 15)
		b.toggle_mode = true
		b.set_pressed_no_signal(id == tab)
		b.custom_minimum_size.y = 34
		tabs_row.add_child(b)
		_tab_buttons[id] = b
	row.add_child(Kit.spacer())
	header_extra(row)
	if closable:
		var close: Button = Kit.icon_button("close", func(): host.close(self), "Close\nEsc.", "GhostButton", 18, 38)
		bar.add_child(close)
	var v: VBoxContainer = Kit.vbox(0)
	v.add_child(hp)
	var line := ColorRect.new()
	line.color = P.with_alpha(accent, 0.55)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	return v

func set_subtitle(text: String) -> void:
	subtitle = text
	if _subtitle_label != null:
		_subtitle_label.text = text
		_subtitle_label.visible = text != ""

func set_tab(id: String) -> void:
	if id == tab:
		return
	tab = id
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == tab)
	_build_tab_content()

func _build_tab_content() -> void:
	for c in content.get_children():
		if c.has_meta("tab_content"):
			c.queue_free()
	var box: VBoxContainer = Kit.vbox(12)
	box.set_meta("tab_content", true)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(box)
	build_tab(tab, box)
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.14)

# ---------------------------------------------------------------- for subclasses
func build() -> void:
	pass

func build_tab(_id: String, _box: VBoxContainer) -> void:
	pass

func header_extra(_row: HBoxContainer) -> void:
	pass

func refresh() -> void:
	pass

func on_close() -> void:
	pass

## A glass card with an uppercase title, for sections inside a screen.
func card(title_text: String, icon_name: String = "", color: Color = P.TEXT_2) -> VBoxContainer:
	var p: PanelContainer = Kit.panel("CardPanel", false)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var v: VBoxContainer = Kit.vbox(8)
	p.add_child(v)
	if title_text != "":
		var h: HBoxContainer = Kit.hbox(7)
		if icon_name != "":
			h.add_child(Kit.icon(icon_name, 16, color))
		h.add_child(Kit.head(title_text, color, 12))
		v.add_child(h)
	v.set_meta("panel", p)
	return v

func card_panel(v: VBoxContainer) -> PanelContainer:
	return v.get_meta("panel")
