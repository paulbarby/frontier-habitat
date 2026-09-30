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
var _fit_on := false             # the frame is sized to its content now (fits_content())
var _hdr_row: HBoxContainer      # the title, tabs and extras (inside a sideways clip area)
## Rich tooltips for the screen tabs ("Title\nwhat the page shows"), by "screen:tab".
const TAB_TIPS := {
	"research:tree": "Tree\nEvery research project by branch and tier. Click one to see it; the queue runs in order.",
	"research:labs": "Labs and packs\nEach lab, its scientists, output and focus, and the research packs in stock.",
	"dashboard:overview": "Overview\nThe headline numbers and their charts, and the alerts now.",
	"dashboard:life": "Life support\nOxygen, water and power over time, per network.",
	"dashboard:food": "Food\nCrops, dishes, spoilage and the nutrition of the colonists.",
	"dashboard:industry": "Industry\nWhat each machine makes, and what waits for input or workers.",
	"dashboard:population": "People\nColonists, roles, morale and health over time.",
	"dashboard:research": "Research\nResearch points per day and the projects done.",
	"dashboard:hazards": "Hazards\nForecast events, machines near failure and maintenance.",
	"inventory:all": "All items\nEvery item in the colony.", "inventory:raw": "Raw resources\nOre, sand, ice and crystal.",
	"inventory:material": "Materials\nSteel, glass, polymer, biomass.", "inventory:component": "Components\nParts for building, repair and the ship.",
	"inventory:medical": "Medical\nMedicine and its shelf life.", "inventory:water": "Water\nWater cans in storage (network water is on the dashboard).",
	"inventory:crop": "Crops\nHarvested crops and how long they keep.", "inventory:dish": "Dishes\nCooked food: one dish feeds one colonist for a day.",
	"colonists:colonists": "Colonists\nEvery colonist: role, health, morale, nutrition, what they do and where.",
	"colonists:priorities": "Priorities\nFor each colonist and kind of job: first, normal, last or never.",
	"vehicles:vehicles": "Vehicles\nEvery vehicle: charge or fuel, cargo, crew, wear; give it orders.",
	"vehicles:routes": "Routes\nMedium rovers that carry goods and people between two bases, again and again.",
	"colonists:visitors": "Visitors\nTourists and other guests: their ship, when they leave, what they paid.",
	"awards:colony": "This colony\nMedals earned by this colony.", "awards:device": "This device\nMedals earned by any colony on this device.",
	"help:rules": "Rules\nHow the colony lives: air, water, power, food, work.", "help:keys": "Controls\nEvery key and mouse action.",
	"help:mission": "Mission\nThe five chapters and the victory.",
	"codex:item": "Items\nEvery item: where it comes from, what uses it, its crafting tree.",
	"codex:structure": "Structures\nEvery structure: cost, power, workers, what it makes, what unlocks it.",
	"codex:tech": "Research\nEvery research project: cost, what it needs and what it unlocks.",
	"codex:hazard": "Hazards\nEvery hazard and what to do about it.",
}
var _frame_style                 # this screen's own GlassFrame: the title plate follows the header height
var _hp: Control

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
	frame = Kit.panel("ModalPanel", true)
	# Version 4: the header is a brushed title plate of the GlassFrame, as tall as the header.
	_frame_style = load("res://ui/theme/ui_theme.gd").panel_style("modal")
	_frame_style.accent = Color(accent.r, accent.g, accent.b, 0.85)
	frame.add_theme_stylebox_override("panel", _frame_style)
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

## Critic round 22: a screen (or one of its tabs) with little in it is sized to its content,
## centred, instead of filling the view. Screens override this; lists in it use fit_scroll().
func fits_content() -> bool:
	return false

## The width the header needs: the title block, every tab button and Close, with their gaps.
func _hdr_width() -> float:
	# The row's own minimum (it sits in a clip area, so the frame does not see it) + Close (38) and
	# the gap (6) + the plate margins (22 + 14) + the frame's metal band and padding (about 40).
	return (_hdr_row.get_combined_minimum_size().x if _hdr_row != null else 600.0) + 6.0 + 38.0 + 36.0 + 40.0

## A list in a scroll area (Kit.well_scroll) as tall as its rows, up to max_h (then it scrolls).
## For screens sized to their content: a scroll area alone measures no height.
static func fit_scroll(well: Control, max_h: float = 520.0) -> void:
	var sc: ScrollContainer = well if well is ScrollContainer else null
	if sc == null:
		for c in well.get_children():
			if c is ScrollContainer:
				sc = c
	if sc == null or sc.get_child_count() == 0:
		return
	var inner: Control = sc.get_child(0)
	sc.custom_minimum_size.y = minf(inner.get_combined_minimum_size().y + 4.0, max_h)
	well.size_flags_vertical = Control.SIZE_FILL

## Window bounds: sizes this screen for a view of `vp` (each frame, from
## ui/hud/bounds_keeper.gd). Compact dialogs: at most the view width minus 16 px; the content
## area as tall as the content but no taller than the view allows (then it scrolls); centred.
## Full screens: the frame keeps its margins but never less than 8 px from the edge.
func fit_view(vp: Vector2) -> void:
	if frame == null or _scroll == null:
		return
	if _hp != null and _frame_style != null:
		var hh: float = _hp.size.y + 1.0
		if absf(hh - _frame_style.header_h) > 0.5:
			_frame_style.header_h = hh
			frame.queue_redraw()
	var fit: bool = not compact and fits_content()
	if fit:
		if not _fit_on:
			_fit_on = true
			frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		var cm: Vector2 = content.get_combined_minimum_size()
		# At least as wide as the header needs (title, subtitle, every tab and Close): the tab strip
		# clips instead of widening the frame.
		var hw: float = _hdr_width() - 64.0 - 20.0
		_scroll.custom_minimum_size = Vector2(minf(maxf(cm.x, hw), vp.x - 16.0 - 64.0 - 20.0), cm.y)
		var excess2: float = frame.get_combined_minimum_size().y - (vp.y - 16.0)
		if excess2 > 0.0:
			_scroll.custom_minimum_size.y = maxf(40.0, _scroll.custom_minimum_size.y - excess2)
		var sz2: Vector2 = frame.get_combined_minimum_size()
		sz2.x = minf(sz2.x, vp.x - 16.0)
		if not frame.size.is_equal_approx(sz2) or vp != _last_vp:
			frame.size = sz2
			frame.position = ((vp - sz2) * 0.5).floor()
		_last_vp = vp
		return
	if _fit_on:
		# Back to a full screen (another tab): margins again.
		_fit_on = false
		_scroll.custom_minimum_size = Vector2.ZERO
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_last_vp = Vector2.ZERO
	if compact:
		# + 20: the version-4 metal band (10 px a side) sits inside the frame; the content keeps its width.
		frame.custom_minimum_size = Vector2(minf(compact_size.x + 20.0, vp.x - 16.0), 0.0)
		# Paul, 2026-10-01: content wider than compact_size (a long row, another interface scale)
		# widens the frame up to the view, so nothing (the Back button) hides past a side scroll.
		var cmin: Vector2 = content.get_combined_minimum_size()
		var side: float = 44.0 + 20.0
		if _frame_style != null:
			side = 44.0 + _frame_style.get_margin(SIDE_LEFT) + _frame_style.get_margin(SIDE_RIGHT)
		_scroll.custom_minimum_size.x = minf(cmin.x, maxf(0.0, vp.x - 16.0 - side))
		_scroll.custom_minimum_size.y = cmin.y
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
	_hp = hp
	var st = load("res://ui/theme/ui_theme.gd").panel_style("flat")   # the frame draws the plate behind it
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
	_hdr_row = row
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
		b.tooltip_text = String(TAB_TIPS.get("%s:%s" % [screen_name, id], "%s\nShows this page." % String(t2[1])))
		var ts = load("res://ui/theme/ui_theme.gd").tab_style(accent)
		b.add_theme_stylebox_override("pressed", ts)
		b.add_theme_stylebox_override("hover_pressed", ts)
		tabs_row.add_child(b)
		_tab_buttons[id] = b
	row.add_child(Kit.spacer())
	header_extra(row)
	if closable:
		var close: Button = Kit.icon_button("close", func(): host.close(self), "Close\nEsc.", "GhostButton", 18, 38)
		bar.add_child(close)
	var v: VBoxContainer = Kit.vbox(0)
	v.add_child(hp)
	v.add_child(Kit.gap(0, 3))   # room for the seam and the accent line the frame draws under the plate
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
