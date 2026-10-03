extends PanelContainer
## Right-side inspector for the selected structure or colonist.
## Structure tabs (only the ones that apply): Overview, Production, Crops, Menu, Upgrade,
## Staff, Stats. Colonist tabs: Status, Nutrition.
## The content is rebuilt only when its structure changes; numbers update in place through
## small bindings, so hover and tooltips stay stable.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")
const Sections = preload("res://ui/hud/inspector_sections.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")

const WIDTH := 392.0
## At narrow views the window is as wide as the right quarter allows (Paul, 2026-10-03: no window in the centre zone, the
## middle half of the view): its left edge stays at or right of 75 % of the width. Never narrower than MIN_WIDTH.
const MIN_WIDTH := 236.0
var width := WIDTH
var _last_scroll_h := -1.0

var hud
var tab := "overview"
var _kind := ""
var _id := -1
var _sig := ""
var _title: Label
var _sub: Label
var _icon: TextureRect
var _badges: HFlowContainer
var _tabs: HFlowContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _footer: HFlowContainer
var _binds: Array = []       # [Callable] run on every refresh
var last_staff: Dictionary = {}   # the answer to the last venue staff order (tests)
var last_party: Dictionary = {}   # the answer to the last "Throw a party" (tests)
var _accent := P.CYAN
var sections
var _head: HBoxContainer
var _style
var _tab_seam: HSeparator

func _ready() -> void:
	# Version 4 (V4_DESIGN §7): a window in the glass-and-metal style with a title plate; the
	# window manager (ui/wm/window_manager.gd) places it, drags it by its header, remembers where
	# it was left, closes it with Esc (last window first). Pilot window of the new theme.
	_style = GlassFrame.new()
	_style.kind = "window"
	_style.header_h = 58.0
	# Right margin: the 10 px frame band plus 12 px of glass, so no line touches the frame
	# (critic round 15, fix 7). Long text wraps inside that width.
	_style.content_margin_left = 20
	_style.content_margin_right = 22
	_style.content_margin_top = 13
	_style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", _style)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	sections = Sections.new(self)
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	var head: HBoxContainer = Kit.hbox(6)
	head.custom_minimum_size.y = 34
	_head = head
	v.add_child(head)
	v.add_child(Kit.gap(0, 4))
	_icon = Kit.icon("info", 26, P.CYAN)
	head.add_child(_icon)
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	_title = Kit.head("", P.TEXT, 16, "head_wide")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wraps in a small window (was clipped)
	_title.custom_minimum_size.x = 60
	tv.add_child(_title)
	_sub = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wraps in a small window (was clipped)
	_sub.custom_minimum_size.x = 60
	tv.add_child(_sub)
	var show_b: Button = Kit.icon_button("target", func(): _focus(), "Show\nMoves the camera here.", "GhostButton", 16, 26)
	head.add_child(show_b)
	var close_b: Button = Kit.icon_button("close", func(): hud.main.select("", -1), "Close\nRight click on the ground or Esc clears the selection.", "GhostButton", 16, 26)
	head.add_child(close_b)
	for hb in [show_b, close_b]:   # thin margins: the header row is no wider than 26 px a button (a narrow window)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var st: StyleBox = (hb as Button).get_theme_stylebox(state)
			if st != null:
				var d: StyleBox = st.duplicate()
				d.content_margin_left = 4.0
				d.content_margin_right = 4.0
				d.content_margin_top = 4.0
				d.content_margin_bottom = 4.0
				(hb as Button).add_theme_stylebox_override(state, d)
		(hb as Button).custom_minimum_size = Vector2(26, 26)
	_badges = HFlowContainer.new()   # badges wrap in a narrow window
	_badges.add_theme_constant_override("h_separation", 6)
	_badges.add_theme_constant_override("v_separation", 4)
	v.add_child(_badges)
	# Tabs flow onto a second row when their names do not fit (text floor, critic round 21): never clipped.
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 3)
	_tabs.add_theme_constant_override("v_separation", 3)
	v.add_child(_tabs)
	_tab_seam = Kit.sep()   # engraved seam between the tabs and the content (fix 8)
	_tab_seam.visible = false
	v.add_child(_tab_seam)
	_body = Kit.vbox(8)
	_scroll = Kit.scroll(_body)
	_scroll.custom_minimum_size = Vector2(WIDTH - 42, 120)
	v.add_child(_scroll)
	_footer = HFlowContainer.new()
	_footer.add_theme_constant_override("h_separation", 6)
	_footer.add_theme_constant_override("v_separation", 6)
	v.add_child(_footer)

## Space the inspector takes on the right edge (toasts move left of it); 0 when it was moved away.
func width_used() -> float:
	if not visible:
		return 0.0
	var vp: Vector2 = get_viewport_rect().size
	var r: Rect2 = get_global_rect()
	return (vp.x - r.position.x) if r.end.x > vp.x - 120.0 else 0.0

## Window manager: Esc and "close all" clear the selection.
func wm_close() -> void:
	hud.main.select("", -1)

func register_window(wm) -> void:
	wm.register(self, "inspector", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.end.x - sz.x, wa.position.y))

func selection_changed() -> void:
	var kind: String = hud.main.view.selected_kind
	var id: int = hud.main.view.selected_id
	if kind != _kind or id != _id:
		_kind = kind
		_id = id
		# "": the structure picks its first tab (Storage for a storehouse, else Overview).
		tab = "" if kind == "building" else "status"
		_sig = ""
		if kind != "":
			modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(self, "modulate:a", 1.0, 0.16)
	refresh()

func rebuild() -> void:
	_kind = ""
	_id = -1
	_sig = ""
	visible = false

func set_tab(t: String) -> void:
	tab = t
	_sig = ""
	refresh()

func _focus() -> void:
	var st: Dictionary = hud.main.sim.state
	if _kind == "building" and st["buildings"].has(_id):
		hud.main.focus_on(st["buildings"][_id]["pos"])
	elif _kind == "agent" and st["agents"].has(_id):
		hud.main.focus_on(st["agents"][_id]["pos"])

## The width the right quarter allows: the work area's right edge less 75 % of the view.
func fit_width() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var right: float = hud.wm.work_area().end.x if hud != null and hud.wm != null else vp.x - 78.0
	var w: float = clampf(floorf(right - vp.x * 0.75) - 1.0, MIN_WIDTH, WIDTH)
	if absf(w - width) > 0.5:
		width = w
		custom_minimum_size.x = w
		_scroll.custom_minimum_size.x = w - 42.0
		# Narrow: a row that cannot shrink scrolls sideways; it never widens the window into the centre zone.
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if w < WIDTH - 0.5 else ScrollContainer.SCROLL_MODE_DISABLED
		# The title and the line under it keep to one line in a narrow window (the tooltip has all of it).
		var narrow: bool = w < WIDTH - 0.5
		for hl in [_title, _sub]:
			(hl as Label).autowrap_mode = TextServer.AUTOWRAP_OFF if narrow else TextServer.AUTOWRAP_WORD_SMART
			(hl as Label).clip_text = narrow
			(hl as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if narrow else TextServer.OVERRUN_NO_TRIMMING
		reset_size()

## In a narrow window (the right quarter of a small view) nothing may be wider than the content: a long
## one-line label wraps, a long button text is cut (the tooltip has it), a fixed minimum width is the content width.
func _relax(n: Node, avail: float) -> void:
	for c in n.get_children():
		if not (c is Control):
			continue
		var ctl: Control = c
		if int(ctl.get_meta("narrow", -1)) != int(width):
			ctl.set_meta("narrow", int(width))
			if ctl.custom_minimum_size.x > avail:
				ctl.custom_minimum_size.x = avail
			if ctl is Label:
				var lb: Label = ctl
				if lb.autowrap_mode == TextServer.AUTOWRAP_OFF and not lb.clip_text and lb.text.length() > 14:
					if n is VBoxContainer:
						lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					else:
						lb.clip_text = true
						lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
						if lb.tooltip_text == "":
							lb.tooltip_text = lb.text
			elif ctl is OptionButton:
				(ctl as OptionButton).fit_to_longest_item = false
				(ctl as Button).clip_text = true
				ctl.custom_minimum_size.x = minf(ctl.custom_minimum_size.x, avail * 0.8)
			elif ctl is Button and (ctl as Button).text.length() > 10:
				(ctl as Button).clip_text = true
				(ctl as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				if (ctl as Button).tooltip_text == "":
					(ctl as Button).tooltip_text = (ctl as Button).text
		_relax(c, avail)

func refresh() -> void:
	fit_width()
	_refresh_inner()
	# After the content is rebuilt: in a narrow window nothing may be wider than the content.
	if width < WIDTH - 0.5 and _body != null:
		_relax(_body, width - 42.0)
		_relax(_footer, width - 42.0)
		_title.tooltip_text = _title.text
		_sub.tooltip_text = _sub.text
		# A narrow window is taller (its header, tabs and footer wrap): the scroll area takes what is left of the work area.
		if visible:
			_fit_height()

func _refresh_inner() -> void:
	var st: Dictionary = hud.main.sim.state
	var kind: String = hud.main.view.selected_kind
	var id: int = hud.main.view.selected_id
	if kind != _kind or id != _id:
		selection_changed()
		return
	var rec: Dictionary = {}
	if kind == "building":
		rec = st["buildings"].get(id, {})
	elif kind == "agent":
		rec = st["agents"].get(id, {})
	if rec.is_empty():
		if visible:
			visible = false
		if kind != "":
			hud.main.view.select("", -1)
			_kind = ""
			_id = -1
		return
	# The over-the-shoulder view (V5 §3) has its own card; the inspector stays hidden until it ends.
	if hud.follow_hud != null and hud.follow_hud.visible:
		visible = false
		return
	# The personnel file of this person takes the inspector's place (critic round 30, fix 2).
	if kind == "agent" and hud.person != null and hud.person.visible and int(hud.person.agent_id) == id:
		visible = false
		return
	visible = true
	_fit_height()
	Kit.fit(self)
	var sig: String = sections.signature(kind, rec, tab)
	if sig != _sig:
		_sig = sig
		_rebuild_content(kind, rec)
	for b in _binds:
		(b as Callable).call()

func _fit_height() -> void:
	var bottom: float = hud.build_bar.tabs_top() - 10.0 if hud.build_bar != null else get_viewport_rect().size.y - 90.0
	# What the window needs besides the scroll area (header, badges, tabs, footer): measured, since a narrow window
	# wraps its header and footer onto more lines.
	var chrome: float = 190.0
	var col: Node = get_child(0)
	if col is VBoxContainer:
		var hsum := 0.0
		var cnt := 0
		for c in col.get_children():
			if c is Control and (c as Control).visible and c != _scroll:
				hsum += (c as Control).get_combined_minimum_size().y
				cnt += 1
		chrome = maxf(190.0, hsum + float(cnt) * 8.0 + 27.0 + 30.0)   # (+30: the rows wrap a frame after the width changed)
	var room: float = bottom - global_position.y - chrome
	var need: float = _body.get_combined_minimum_size().y + 4.0
	_scroll.custom_minimum_size.y = clampf(minf(need, room), 60.0, 560.0)
	# Measured: when the whole window is still taller than the work area (the header, tabs and footer wrap in a
	# narrow window), the scroll area gives up the difference (it converges in a refresh or two).
	if hud.wm != null and width < WIDTH - 0.5:
		var excess: float = get_combined_minimum_size().y - hud.wm.work_area().size.y
		if excess > 0.0:
			_scroll.custom_minimum_size.y = maxf(60.0, _scroll.custom_minimum_size.y - excess - 2.0)
		# At its default place (never dragged) the window goes back to the top of the work area once its height settles
		# (a tall first frame had pushed it up over the top bar).
		var rec: Dictionary = hud.wm._wins.get("inspector", {})
		if not rec.is_empty() and bool(rec.get("auto", false)) and absf(_scroll.custom_minimum_size.y - _last_scroll_h) > 0.5:
			_last_scroll_h = _scroll.custom_minimum_size.y
			reset_size()
			hud.wm.place("inspector")

func _rebuild_content(kind: String, rec: Dictionary) -> void:
	_binds = []
	Kit.clear(_badges)
	Kit.clear(_tabs)
	_tab_seam.visible = false
	Kit.clear(_body)
	Kit.clear(_footer)
	if kind == "building":
		sections.building(rec)
	else:
		sections.agent(rec)
	_add_why(kind, int(rec["id"]))
	if kind == "agent" and not hud.data.is_visitor(rec):
		# Version 4 orders (V4_DESIGN §5): opens the orders window with this colonist in the group.
		_footer.add_child(Kit.button("Orders…", func(): hud.orders.open_for_selected(), "Orders\nGo to, board a vehicle, explore, survey, work at, stay, return. Opens the orders window with this colonist.", "", "orders", 15))
	queue_redraw()

## "Why is this stopped?" (V4_DESIGN §6): a dark well at the top of the body with the reason and
## the fix, shown while the structure or colonist is stopped (ui/why.gd). Updated on every refresh.
func _add_why(kind: String, id: int) -> void:
	var Why = load("res://ui/why.gd")
	var well: PanelContainer = Kit.panel("WellPanel", false)
	well.mouse_filter = Control.MOUSE_FILTER_PASS
	var v: VBoxContainer = Kit.vbox(3)
	well.add_child(v)
	var head: HBoxContainer = Kit.hbox(6)
	v.add_child(head)
	head.add_child(Kit.icon("info", 14, P.AMBER))
	var t: Label = Kit.head("", P.AMBER, 12)
	head.add_child(t)
	var why: Label = Kit.wrap("", 13, P.TEXT)
	why.custom_minimum_size.x = 300
	v.add_child(why)
	var fix: Label = Kit.wrap("", 13, P.TEXT_2)
	fix.custom_minimum_size.x = 300
	v.add_child(fix)
	_body.add_child(well)
	_body.move_child(well, 0)
	var upd := func():
		var st: Dictionary = hud.main.sim.state
		var r: Dictionary = st["buildings" if kind == "building" else "agents"].get(id, {})
		if r.is_empty():
			return
		var w: Dictionary = Why.structure(hud, r) if kind == "building" else Why.agent(hud, r)
		var show: bool = bool(w["stopped"]) or (kind == "agent" and not (w["why"] as Array).is_empty())
		well.visible = show
		if not show:
			return
		t.text = ("WHY: " if bool(w["stopped"]) else "") + String(w["title"]).to_upper()
		t.add_theme_color_override("font_color", w["color"])
		why.text = " ".join(w["why"])
		fix.text = ("Fix: " + " ".join(w["fix"])) if not (w["fix"] as Array).is_empty() else ""
		fix.visible = fix.text != ""
	upd.call()
	bind(upd)

# ---------------------------------------------------------------- used by sections
func set_header(icon_name: String, color: Color, title: String, sub: String) -> void:
	_accent = color
	if _style != null:
		_style.accent = Color(color.r, color.g, color.b, 0.9)   # family colour under the title plate
	Kit.set_icon(_icon, icon_name, 26, color)
	_title.text = title.to_upper()
	_sub.text = sub

func add_badge(c: Control) -> void:
	_badges.add_child(c)

func add_tabs(list: Array) -> void:
	# list: [[id, label], ...]; hidden when there is only one tab.
	if list.size() <= 1:
		return
	var ids: Array = []
	for t in list:
		ids.append(t[0])
	if not ids.has(tab):
		tab = ids[0]
	_tab_seam.visible = true
	var UiTheme = load("res://ui/theme/ui_theme.gd")
	var ts = UiTheme.tab_style(_accent)   # lit glass, family accent line
	ts.content_margin_left = 3
	ts.content_margin_right = 3
	var narrow := {}
	for t in list:
		var id: String = t[0]
		var b: Button = Kit.button(t[1], func(): set_tab(id), "%s\nShows this page of the inspector." % String(t[1]), "TabButton")
		b.add_theme_stylebox_override("pressed", ts)
		b.add_theme_stylebox_override("hover_pressed", ts)
		b.toggle_mode = true
		b.set_pressed_no_signal(id == tab)
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # tabs share the width; never widen the window
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_font_override("font", load("res://ui/theme/fonts.gd").get_font("body_sb"))
		b.add_theme_constant_override("h_separation", 0)
		_tabs.add_child(b)
		# Narrow side margins (3 px), so six tab names fit in the 350 px content width.
		for st in ["normal", "hover", "disabled"]:
			if not narrow.has(st):
				var sb = b.get_theme_stylebox(st)
				narrow[st] = sb.clone() if sb.has_method("clone") else sb.duplicate()
				narrow[st].content_margin_left = 3
				narrow[st].content_margin_right = 3
			b.add_theme_stylebox_override(st, narrow[st])

func body() -> VBoxContainer:
	return _body

func footer() -> HFlowContainer:
	return _footer

func bind(cb: Callable) -> void:
	_binds.append(cb)

func _draw() -> void:
	pass
