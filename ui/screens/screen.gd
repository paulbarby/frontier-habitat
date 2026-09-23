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
	outer.add_child(_header())
	var m: MarginContainer = Kit.margin(Kit.vbox(10), 22, 16, 22, 18)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(m)
	content = m.get_child(0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	if not tabs.is_empty() and tab == "":
		tab = String(tabs[0][0])
	build()
	if not tabs.is_empty():
		_build_tab_content()
	# Enter: fade and a small rise.
	modulate.a = 0.0
	frame.pivot_offset = frame.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	frame.position.y += 14.0
	tw.tween_property(frame, "position:y", frame.position.y - 14.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _header() -> Control:
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
	var row: HBoxContainer = Kit.hbox(14)
	hp.add_child(row)
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
		row.add_child(close)
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
