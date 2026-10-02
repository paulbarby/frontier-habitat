extends Control
## The panel manager (docs/UI_PANELS.md; Paul, 2026-10-01: "use a unified interface system, not some
## ad hoc scope creep monster"). The ONE place that shows and places what the game shows by itself:
## alerts, events, requests, banners, messages, medals and chapters. Zones, top left, one column:
##   urgent line   at most one line: the most urgent item (click: its tab)
##   pop-ups      at most 3 new messages; each fades (5 s, 8 s for a warning) unless pinned
##   dock         tabs with count badges (Goals, Alerts, Events, Traffic, Requests, News) and the open
##                tab's cards; a quarter of the view wide at most, above the minimap; the body scrolls.
## Nothing goes into the centre zone (the middle half of the width and of the height).
## Every card has one look (the HudPanel glass, a priority colour on its left edge) and the same
## controls: Minimise, Pin, Close. The dock: Minimise, Pin, Close (key L opens it again).
## Each message type pops up, shows a badge only, or is off (Settings, Notifications; kept on the device).
## HUD modules hosted here keep their data code; they have no placement code of their own.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")
const Settings = preload("res://ui/settings.gd")

## type -> [name for Settings, tab, icon]
const TYPES := {
	"alert": ["Alerts", "alerts", "sev_warning"],
	"hazard": ["Hazards and countdowns", "events", "hazard"],
	"reactor": ["Reactor", "events", "reactor"],
	"unrest": ["Unrest and lockdown", "events", "people"],
	"request": ["Requests from people", "requests", "heart"],
	"traffic": ["Ships and traffic", "traffic", "ship"],
	"people": ["People's lives", "news", "heart"],
	"goal": ["Goals and chapters", "goals", "goals"],
	"award": ["Medals", "news", "medal"],
	"research": ["Research", "news", "research"],
	"build": ["Building", "news", "build"],
	"system": ["Game messages", "news", "sev_info"],
}
const MODES := ["popup", "badge", "off"]
const MODE_NAME := {"popup": "Pop up", "badge": "Badge only", "off": "Off"}
## [id, label, icon]
const TABS := [["goals", "Goals", "goals"], ["alerts", "Alerts", "sev_warning"], ["events", "Events", "hazard"],
	["traffic", "Traffic", "ship"], ["requests", "Requests", "heart"], ["news", "News", "newspaper"]]
const PRIO := ["info", "notice", "warning", "critical", "needs-answer"]
const PRIO_COL := {"info": Color("3EE0FF"), "notice": Color("9FB3C8"), "warning": Color("FFB547"), "critical": Color("FF5A5F"), "needs-answer": Color("F472B6")}
const MAX_POPS := 3
const FEED_MAX := 40
const BODY_KEEP := 200.0     # the dock body keeps this much room: pop-ups fold into News first
const NAMES_W := 340.0       # a dock this wide shows the tab names (3 columns, 2 rows), a narrower one icon + count

var hud
var tab := "goals"
var dock_open := true       # false: only the urgent line and the pop-ups show (key L)
var minimised := false      # the dock shows only its tabs
var pinned := false         # a window over the dock does not fold it
var collapsed := false      # folded by the window manager while a window covers the dock
var feed: Array = []        # News: [{type, text, priority, icon, t (engine s), seen}] newest first
var urgent_now: Dictionary = {}   # {text, tab, priority} shown in the urgent line (tests)
var _col: VBoxContainer
var _urgent: PanelContainer
var _urgent_text: Label
var _urgent_icon: TextureRect
var _pops: VBoxContainer
var _dock: PanelContainer
var _tabbar: GridContainer   # as many columns as fit (its height is known at once, unlike a flow)
var _tab_btn := {}          # tab -> Button
var _mute: Button
var _min_btn: Button
var _pin_btn: Button
var _body: ScrollContainer
var _pages := {}            # tab -> VBoxContainer
var _cards: Array = []      # [{tab, root, body, host, closed, pinned, min, summary: Callable, was_visible}]
var _news: VBoxContainer
var _news_sig := ""
var _flash := {}            # tab -> the urgent signature that flashed already
var _width := 320.0
var _poll := 0.0

func _ready() -> void:
	name = "PanelManager"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col = Kit.vbox(6)
	_col.name = "Column"
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_col)
	# Urgent line
	_urgent = _frame("needs-answer")
	_urgent.name = "Urgent"
	_urgent.mouse_filter = Control.MOUSE_FILTER_STOP
	_urgent.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_urgent.visible = false
	var uh: HBoxContainer = Kit.hbox(8)
	_urgent.add_child(uh)
	_urgent_icon = Kit.icon("sev_warning", 16, P.AMBER)
	uh.add_child(_urgent_icon)
	_urgent_text = Kit.label("", "", 13, P.TEXT)
	_urgent_text.clip_text = true
	_urgent_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_urgent_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uh.add_child(_urgent_text)
	_urgent.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not urgent_now.is_empty():
			open_tab(String(urgent_now["tab"])))
	_col.add_child(_urgent)
	# Pop-ups
	_pops = Kit.vbox(4)
	_pops.name = "Popups"
	_pops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(_pops)
	# Dock
	_dock = PanelContainer.new()
	_dock.name = "Dock"
	_dock.theme_type_variation = "HudPanel"
	var dst = load("res://ui/theme/ui_theme.gd").panel_style("hud")
	dst.content_margin_left = 8    # narrow margins: the dock is a quarter of the view at most
	dst.content_margin_right = 8
	_dock.add_theme_stylebox_override("panel", dst)
	Glass.attach(_dock)
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_col.add_child(_dock)
	var dv: VBoxContainer = Kit.vbox(6)
	_dock.add_child(dv)
	# The dock controls sit on a slim row of their own, so the tab grid has the whole width (2026-10-02: beside
	# the controls the named tabs fitted in one column, six rows, and squeezed the body to 67 px at 1366x768).
	var head: HBoxContainer = Kit.hbox(4)
	head.alignment = BoxContainer.ALIGNMENT_END
	head.name = "DockControls"
	dv.add_child(head)
	_tabbar = GridContainer.new()
	_tabbar.columns = 6
	_tabbar.add_theme_constant_override("h_separation", 2)
	_tabbar.add_theme_constant_override("v_separation", 2)
	_tabbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_child(_tabbar)
	for t in TABS:
		var id: String = t[0]
		var b: Button = Kit.button("", func(): open_tab(id, true), "%s\n%s" % [t[1], _tab_tip(id)], "TabButton", String(t[2]), 14)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 30)
		b.set_meta("tab", id)
		b.set_meta("icon", b.icon)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_constant_override("h_separation", 3)
		_tabbar.add_child(b)
		_tab_btn[id] = b
	var ctl: HBoxContainer = Kit.hbox(0)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var dock_title: Label = Kit.label("DOCK", "SmallLabel", 11, P.TEXT_3)
	dock_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(dock_title)
	head.add_child(ctl)
	_mute = _ib("volume", func(): _toggle_mute(), "", "GhostButton", 14, 26)
	ctl.add_child(_mute)
	_min_btn = _ib("chevron_up", func(): minimise_dock(not minimised), "Minimise\nOnly the tabs show. Click again to open.", "GhostButton", 14, 26)
	ctl.add_child(_min_btn)
	_pin_btn = _ib("pin", func(): pin_dock(not pinned), "Pin\nThe dock stays open: a window over it does not fold it.", "GhostButton", 14, 26)
	_pin_btn.toggle_mode = true
	ctl.add_child(_pin_btn)
	ctl.add_child(_ib("close", func(): toggle_dock(false), "Close\nOnly the urgent line and the pop-ups stay. Key L opens the dock again.", "GhostButton", 14, 26))
	_body = ScrollContainer.new()
	_body.name = "Body"
	_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	dv.add_child(_body)
	var pages: VBoxContainer = Kit.vbox(0)
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(pages)
	for t in TABS:
		var pg: VBoxContainer = Kit.vbox(6)
		pg.name = "Page_" + String(t[0])
		pg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pg.visible = String(t[0]) == tab
		pages.add_child(pg)
		_pages[t[0]] = pg
	for id in _pages:
		var ph: Label = Kit.label("Nothing here now.", "SmallLabel", 12, P.TEXT_3)
		ph.name = "Empty"
		(_pages[id] as VBoxContainer).add_child(ph)
	_news = Kit.vbox(4)
	_news.name = "NewsFeed"
	_pages["news"].add_child(_news)
	dock_open = Settings.get_value("dock_open") != false
	_apply_tabs()

func _tab_tip(id: String) -> String:
	return {"goals": "The open chapter and its goals.", "alerts": "What is failing now, why and what to do.",
		"events": "Hazard countdowns and the forecast, the reactor, unrest and lockdown.", "traffic": "Ships coming, landed and leaving.",
		"requests": "Questions from people that need your answer.", "news": "Every message, newest first."}.get(id, "")

## A small icon button whose icon texture (drawn at twice its size) does not widen it.
static func _ib(icon: String, cb: Callable, tip: String, variation: String, px: int, side: int) -> Button:
	var b: Button = Kit.icon_button(icon, cb, tip, variation, px, side)
	b.add_theme_constant_override("icon_max_width", px)
	return b

## A frame with the one look: the HUD glass and a priority colour on its left edge.
func _frame(priority: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "ToastPanel"
	var st = load("res://ui/theme/ui_theme.gd").panel_style("toast")
	st.content_margin_left = 10   # narrow margins: the dock is a quarter of the view at most
	st.content_margin_right = 8
	st.accent_left = PRIO_COL.get(priority, P.CYAN)
	p.add_theme_stylebox_override("panel", st)
	Glass.attach(p)
	return p

# ---------------------------------------------------------------- hosting
## A card in a tab that shows a HUD module. The module keeps its data code; its own frame, glass and
## placement go (one look, one placement authority). summary: Callable -> String for the minimised line.
func host(tab_id: String, m: Control, title: String, icon: String, summary: Callable = Callable()) -> PanelContainer:
	var card: PanelContainer = _frame("info")
	card.name = "Card_" + title.replace(" ", "")
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var v: VBoxContainer = Kit.vbox(4)
	card.add_child(v)
	var h: HBoxContainer = Kit.hbox(6)
	v.add_child(h)
	var ic: TextureRect = Kit.icon(icon, 14, P.TEXT_2)
	h.add_child(ic)
	h.add_child(Kit.head(title, P.TEXT_2, 11))
	var sm: Label = Kit.label("", "SmallLabel", 11, P.TEXT_3)
	sm.clip_text = true
	sm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sm)
	var rec := {"tab": tab_id, "root": card, "host": m, "closed": false, "pinned": false, "min": false, "summary": summary, "sum_label": sm, "was_visible": m.visible, "title": title}
	var mb: Button = _ib("chevron_up", func(): _card_min(rec, not bool(rec["min"])), "Minimise\nOnly this line shows.", "GhostButton", 12, 22)
	h.add_child(mb)
	var pb: Button = _ib("pin", func(): rec["pinned"] = not bool(rec["pinned"]), "Pin\nThis card stays open; Close and the window manager leave it.", "GhostButton", 12, 22)
	pb.toggle_mode = true
	h.add_child(pb)
	h.add_child(_ib("close", func(): _card_close(rec), "Close\nHidden until it changes, or until you open this tab again.", "GhostButton", 12, 22))
	rec["min_btn"] = mb
	rec["pin_btn"] = pb
	# The module: out of the HUD root, into the card; no frame, no glass, no fixed width of its own.
	if m.get_parent() != null:
		m.get_parent().remove_child(m)
	Glass.detach(m)
	if m is PanelContainer:
		m.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.position = Vector2.ZERO
	m.custom_minimum_size.x = 0.0
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.set_meta("docked", true)
	# A slot between the card and the module: Minimise hides the slot, so the module's own visible
	# (a banner shows and hides itself) stays its own.
	var slot: VBoxContainer = Kit.vbox(0)
	slot.name = "Slot"
	v.add_child(slot)
	slot.add_child(m)
	rec["slot"] = slot
	(_pages[tab_id] as VBoxContainer).add_child(card)
	if tab_id == "news":
		_pages["news"].move_child(_news, _pages["news"].get_child_count() - 1)
	_cards.append(rec)
	return card

func _card_min(rec: Dictionary, on: bool) -> void:
	rec["min"] = on
	(rec["min_btn"] as Button).icon = Icons.tex("chevron_down" if on else "chevron_up", 12)
	_layout_card(rec)

## The dock is narrow: a one-line text that fills its row wraps, and a long button text is cut (with its
## tooltip), so no module makes the dock wider than a quarter of the view (Paul: the centre stays free).
## Modules rebuild their rows, so this runs on the open tab four times a second; a node is done once.
func _soften(n: Node) -> void:
	for c in n.get_children():
		if c is Control and not c.has_meta("dock_soft"):
			c.set_meta("dock_soft", true)
			var fills: bool = n is VBoxContainer or (int((c as Control).size_flags_horizontal) & Control.SIZE_EXPAND) != 0
			if c is Label and fills and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF and not (c as Label).clip_text:
				(c as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			elif c is Button and fills and (c as Button).text.length() > 12:
				(c as Button).clip_text = true
				(c as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				if (c as Button).tooltip_text == "":
					(c as Button).tooltip_text = (c as Button).text
		_soften(c)

## A card's priority colour: what its module shows now.
func _card_prio(m: Control) -> String:
	if m == hud.get("request_card"):
		return "needs-answer"
	if m == hud.get("reactor_banner"):
		return "critical"
	if m == hud.get("hazard_banner"):
		return "warning"
	if m == hud.get("unrest_banner"):
		return {"riot": "critical", "protest": "warning", "strike": "warning"}.get(String(m.shown_stage), "notice")
	if m == hud.get("alerts"):
		return ["info", "notice", "warning", "critical"][clampi(int(m.worst_sev), 0, 3)]
	return "info"

func _card_close(rec: Dictionary) -> void:
	if bool(rec["pinned"]):
		return
	rec["closed"] = true
	_layout_card(rec)

func _layout_card(rec: Dictionary) -> void:
	var m: Control = rec["host"]
	var card: Control = rec["root"]
	# A module that hides itself (a banner with nothing to show) hides its card; one that shows again
	# opens a closed card again (it changed).
	if m.visible and not bool(rec["was_visible"]):
		rec["closed"] = false
	rec["was_visible"] = m.visible
	card.visible = m.visible and not bool(rec["closed"])
	var st = card.get_theme_stylebox("panel")
	if st != null and "accent_left" in st:
		st.accent_left = PRIO_COL.get(_card_prio(m), P.CYAN)
	(rec["slot"] as Control).visible = not bool(rec["min"])
	if rec["summary"] is Callable and (rec["summary"] as Callable).is_valid():
		(rec["sum_label"] as Label).text = String((rec["summary"] as Callable).call())

# ---------------------------------------------------------------- messages
## A message (docs/UI_PANELS.md §5). It goes to News; it pops up when its type is set to Pop up.
func post(type: String, text: String, priority: String = "info", icon: String = "") -> void:
	if text == "":
		return
	if not TYPES.has(type):
		type = "system"
	var ic: String = icon if icon != "" else String(TYPES[type][2])
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	# The same text twice within two seconds is one message.
	if not feed.is_empty() and String(feed[0]["text"]) == text and now - float(feed[0]["t"]) < 2.0:
		return
	feed.push_front({"type": type, "text": text, "priority": priority, "icon": ic, "t": now, "seen": tab == "news" and dock_open and not minimised})
	if feed.size() > FEED_MAX:
		feed.resize(FEED_MAX)
	var md: String = mode(type)
	if md == "popup":   # on the title the whole HUD is hidden; nothing else to check
		_popup(type, text, priority, ic)
	if md != "off" and priority in ["warning", "critical", "needs-answer"]:
		_flash_tab(String(TYPES[type][1]), text)
	var sound: String = {"award": "award", "goal": "goal", "research": "research"}.get(type, "toast")
	if priority == "critical":
		sound = "alert_critical"
	elif priority == "warning":
		sound = "alert_warning"
	if md != "off":
		Kit.sfx(sound)
	_news_sig = ""

func _popup(type: String, text: String, priority: String, icon: String) -> void:
	var p: PanelContainer = _frame(priority)
	p.name = "Pop"
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.set_meta("type", type)
	var h: HBoxContainer = Kit.hbox(8)
	p.add_child(h)
	h.add_child(Kit.icon(icon, 18, PRIO_COL.get(priority, P.CYAN)))
	var l: Label = Kit.wrap(text, 13, P.TEXT)
	l.custom_minimum_size.x = maxf(100.0, _width - 190.0)   # a wrapped line needs a width to measure its height
	h.add_child(l)
	var pin: Button = _ib("pin", Callable(), "Pin\nThis message stays until you close it.", "GhostButton", 12, 22)
	pin.toggle_mode = true
	h.add_child(pin)
	h.add_child(_ib("minus", func(): _drop(p), "Minimise\nTo the News tab (its badge counts it).", "GhostButton", 12, 22))
	h.add_child(_ib("close", func(): _drop(p, true), "Close\nThe message stays in the News tab.", "GhostButton", 12, 22))
	_pops.add_child(p)
	_pops.move_child(p, 0)
	while _pops.get_child_count() > MAX_POPS:
		var old: Node = _pops.get_child(_pops.get_child_count() - 1)
		_pops.remove_child(old)
		old.queue_free()
	p.modulate.a = 0.0
	var life: float = 8.0 if priority in ["warning", "critical", "needs-answer"] else 5.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(life)
	tw.tween_callback(func():
		if is_instance_valid(p) and not pin.button_pressed:
			var t2 := p.create_tween()
			t2.tween_property(p, "modulate:a", 0.0, 0.4)
			t2.tween_callback(func(): _drop(p)))

func _drop(p: Control, read: bool = false) -> void:
	if not is_instance_valid(p):
		return
	if read:
		for e in feed:
			if String(e["text"]) == ((p.get_child(0) as HBoxContainer).get_child(1) as Label).text:
				e["seen"] = true
	if p.get_parent() != null:
		p.get_parent().remove_child(p)
	p.queue_free()

## The pop-ups shown now (tests): their texts.
func popup_texts() -> Array:
	var out: Array = []
	for p in _pops.get_children():
		if p.is_queued_for_deletion():
			continue
		out.append(((p.get_child(0) as HBoxContainer).get_child(1) as Label).text)
	return out

# ---------------------------------------------------------------- settings: per type
func mode(type: String) -> String:
	var v = Settings.get_value("notify_" + type)
	return String(v) if v != null and String(v) in MODES else "popup"

func set_mode(type: String, m: String) -> void:
	Settings.set_value("notify_" + type, m)
	_apply_tabs()

func _types_of(tab_id: String) -> Array:
	var out: Array = []
	for t in TYPES:
		if String(TYPES[t][1]) == tab_id:
			out.append(t)
	return out

## The tab's mute button: its types to Badge only (no pop-ups), or back to Pop up.
func _toggle_mute() -> void:
	var ts: Array = _types_of(tab)
	var muted: bool = ts.all(func(t): return mode(t) != "popup")
	for t in ts:
		if mode(t) != "off" or muted:
			Settings.set_value("notify_" + t, "popup" if muted else "badge")
	_apply_tabs()

# ---------------------------------------------------------------- dock controls
func open_tab(id: String, by_player: bool = false) -> void:
	tab = id
	if by_player:
		for rec in _cards:
			if String(rec["tab"]) == id:
				rec["closed"] = false
	dock_open = true
	minimised = false
	if id == "news":
		for e in feed:
			e["seen"] = true
	_apply_tabs()

func toggle_dock(on = null) -> void:
	dock_open = (not dock_open) if on == null else bool(on)
	Settings.set_value("dock_open", dock_open)
	_apply_tabs()

func minimise_dock(on: bool) -> void:
	minimised = on
	_apply_tabs()

func pin_dock(on: bool) -> void:
	pinned = on
	if on and collapsed:
		fold_set(false)
	_apply_tabs()

## Window manager (ui/wm/window_manager.gd): a window over the dock folds it to its tabs, unless pinned.
func fold_set(on: bool) -> void:
	collapsed = on and not pinned
	_apply_tabs()

func _apply_tabs() -> void:
	if _dock == null:
		return
	_dock.visible = dock_open
	for id in _tab_btn:
		(_tab_btn[id] as Button).set_pressed_no_signal(id == tab)
	for id in _pages:
		(_pages[id] as Control).visible = id == tab
	_body.visible = not minimised and not collapsed
	_min_btn.icon = Icons.tex("chevron_down" if minimised or collapsed else "chevron_up", 14)
	_pin_btn.set_pressed_no_signal(pinned)
	var ts: Array = _types_of(tab)
	var muted: bool = not ts.is_empty() and ts.all(func(t): return mode(t) != "popup")
	_mute.icon = Icons.tex("mute" if muted else "volume", 14)
	_mute.disabled = ts.is_empty()
	_mute.tooltip_text = ("Pop-ups for this tab: %s\nClick: %s." % ["off (badge only)" if muted else "on", "pop up again" if muted else "badge only, no pop-ups"]) if not ts.is_empty() else "This tab has no messages to mute."

# ---------------------------------------------------------------- counts, urgency, flash
## {count, priority} of a tab now.
func tab_state(id: String) -> Dictionary:
	var n := 0
	var pr := "info"
	match id:
		"alerts":
			var al = hud.get("alerts")
			n = int(al.live_count) if al != null else 0
			var sv: int = int(al.worst_sev) if al != null else 0
			pr = "critical" if sv >= 3 else ("warning" if sv == 2 else ("notice" if sv == 1 else "info"))
		"events":
			var hz = hud.get("hazard")
			n = (hz._rows as Array).size() if hz != null and "_rows" in hz else 0
			if hud.get("hazard_banner") != null and hud.hazard_banner.visible:
				pr = _max_prio(pr, "warning")
			if hud.get("reactor_banner") != null and hud.reactor_banner.visible:
				n += 1
				pr = _max_prio(pr, "critical" if String(hud.reactor_banner.shown_phase) in ["critical", "breach"] else "warning")
			if hud.get("unrest_banner") != null and hud.unrest_banner.visible:
				n += 1
				pr = _max_prio(pr, "critical" if String(hud.unrest_banner.shown_stage) == "riot" else "warning")
		"traffic":
			var tr = hud.get("traffic")
			n = (tr.rows_now as Array).size() if tr != null and "rows_now" in tr else 0
		"requests":
			n = hud.v5.requests().size() if hud.v5 != null else 0
			if n > 0:
				pr = "needs-answer"
		"news":
			for e in feed:
				if not bool(e["seen"]) and mode(String(e["type"])) != "off":
					n += 1
					pr = _max_prio(pr, String(e["priority"]))
		"goals":
			var g = hud.get("goals")
			n = int(g.open_count()) if g != null and g.has_method("open_count") else 0
	# A type set to Off shows no badge.
	if _types_of(id).all(func(t): return mode(t) == "off") and not _types_of(id).is_empty():
		n = 0
	return {"count": n, "priority": pr}

static func _max_prio(a: String, b: String) -> String:
	return a if PRIO.find(a) >= PRIO.find(b) else b

func _flash_tab(id: String, sig: String) -> void:
	if not _tab_btn.has(id) or String(_flash.get(id, "")) == sig:
		return
	_flash[id] = sig
	var b: Button = _tab_btn[id]
	var tw := b.create_tween()
	tw.tween_property(b, "modulate", Color(1.6, 1.6, 1.6), 0.2)
	tw.tween_property(b, "modulate", Color.WHITE, 0.4)

## The urgent line: a request > a reactor in danger > a hazard countdown > loud unrest or a lockdown >
## a critical alert. {} when nothing is urgent.
func urgent() -> Dictionary:
	if hud == null or hud.main == null or hud.main.sim == null:
		return {}
	var reqs: Array = []
	var rc = hud.get("request_card")
	for q in (hud.v5.requests() if hud.v5 != null else []):
		if rc == null or not rc.later.has(int(q.get("id", -1))):
			reqs.append(q)
	if not reqs.is_empty() and mode("request") != "off":
		return {"text": "REQUEST: " + String(reqs[0].get("text", "")) + ("  (+%d more)" % (reqs.size() - 1) if reqs.size() > 1 else ""), "tab": "requests", "priority": "needs-answer", "icon": "heart"}
	var rb = hud.get("reactor_banner")
	if rb != null and rb.visible and mode("reactor") != "off":
		return {"text": String(rb._text.text), "tab": "events", "priority": "critical", "icon": "reactor"}
	var hb = hud.get("hazard_banner")
	if hb != null and hb.visible and mode("hazard") != "off":
		return {"text": String(hb._title.text), "tab": "events", "priority": "warning", "icon": "hazard"}
	var ub = hud.get("unrest_banner")
	if ub != null and ub.visible and mode("unrest") != "off":
		return {"text": String(ub._text.text) + ((" · " + String(ub._lock.text)) if String(ub.shown_stage) != "lockdown" and ub._lock.visible else ""), "tab": "events", "priority": "critical" if String(ub.shown_stage) == "riot" else "warning", "icon": "people" if String(ub.shown_stage) != "lockdown" else "lock"}
	for i in hud.main.sim.alerts.incidents():
		if int(i.get("issue", {}).get("severity", 1)) >= 3 and mode("alert") != "off":
			return {"text": String(i["issue"]["text"]), "tab": "alerts", "priority": "critical", "icon": "sev_critical"}
	return {}

## The tab buttons with narrow side margins (the theme's 12 px each side made a named tab 122 px wide, so
## only two fitted in a row).
var names_shown := false     # the tabs show their names (read by tests)
var _tabs_tight := false
func _tighten_tabs() -> void:
	_tabs_tight = true
	for b in _tab_btn.values():
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			var st: StyleBox = (b as Button).get_theme_stylebox(state)
			if st == null:
				continue
			var d: StyleBox = st.duplicate()
			d.content_margin_left = 5.0
			d.content_margin_right = 5.0
			(b as Button).add_theme_stylebox_override(state, d)

# ---------------------------------------------------------------- each frame: the one placement
func _process(delta: float) -> void:
	if hud == null:
		return
	if not _tabs_tight and is_inside_tree():
		_tighten_tabs()
	var vp: Vector2 = get_viewport_rect().size
	# Width: a quarter of the view less 16 px (300-380); never into the centre zone (docs/UI_PANELS.md §2).
	_width = clampf(floorf(vp.x * 0.25 - 16.0), 260.0, 380.0)
	var top: float = 76.0
	if hud.top_bar != null and hud.top_bar.visible:
		top = hud.top_bar.get_global_rect().end.y + 8.0
	# The follow card holds the top left (2026-10-02: the dock and the urgent line lay under it and showed through):
	# the column starts under the card.
	if hud.follow_hud != null and hud.follow_hud.visible:
		top = maxf(top, hud.follow_hud.get_global_rect().end.y + 8.0)
	var floor_y: float = vp.y - 8.0
	if hud.minimap != null and hud.minimap.visible:
		floor_y = hud.minimap.get_global_rect().position.y - 8.0
	_col.position = Vector2(8.0, top)
	_col.custom_minimum_size.x = _width
	_col.size.x = _width
	_dock.custom_minimum_size.x = _width
	for c in _pops.get_children():
		(c as Control).custom_minimum_size.x = _width
		var pl: Label = ((c as Control).get_child(0) as HBoxContainer).get_child(1) as Label
		pl.custom_minimum_size.x = maxf(100.0, _width - 190.0)
	# The body: as tall as the open tab, at most what is left above the minimap.
	var page: Control = _pages[tab]
	# A short view: the oldest pop-ups fold into the dock (they are in News; its tab counts them) so the dock
	# body keeps about BODY_KEEP px (coordinator, 2026-10-01: 80 px at 1280x720 was too little).
	var head_h: float = _dock.get_combined_minimum_size().y - (_body.get_combined_minimum_size().y if _body.visible else 0.0)
	var urg_h: float = _urgent.get_combined_minimum_size().y + 6.0 if _urgent.visible else 0.0
	var pop_room: float = floor_y - top - urg_h - (head_h + BODY_KEEP if dock_open else 0.0)
	while _pops.get_child_count() > 0 and _pops.get_combined_minimum_size().y + 6.0 > pop_room:
		var old: Node = _pops.get_child(_pops.get_child_count() - 1)
		_pops.remove_child(old)
		old.queue_free()
	# What is above the body: the urgent line, the pop-ups and the dock's header (measured, also while hidden).
	var used: float = (_urgent.get_combined_minimum_size().y + 6.0 if _urgent.visible else 0.0) + (_pops.get_combined_minimum_size().y + 6.0 if _pops.get_child_count() > 0 else 0.0)
	used += _dock.get_combined_minimum_size().y - (_body.get_combined_minimum_size().y if _body.visible else 0.0)
	var room: float = maxf(0.0, floor_y - top - used)
	_body.custom_minimum_size.y = minf(page.get_combined_minimum_size().y + 4.0, room)
	_col.reset_size()
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	for rec in _cards:
		_layout_card(rec)
	_soften(_pages[tab])
	for id in _pages:
		var any: bool = String(id) == "news"
		for rec in _cards:
			if String(rec["tab"]) == id and (rec["root"] as Control).visible:
				any = true
		(_pages[id] as Node).get_node("Empty").visible = not any
	# Urgent line
	urgent_now = urgent()
	_urgent.visible = not urgent_now.is_empty()
	if _urgent.visible:
		_urgent_text.text = String(urgent_now["text"])
		_urgent.tooltip_text = "%s\nClick: the %s tab." % [String(urgent_now["text"]), String(urgent_now["tab"]).capitalize()]
		var col: Color = PRIO_COL.get(String(urgent_now["priority"]), P.AMBER)
		Kit.set_icon(_urgent_icon, String(urgent_now["icon"]), 16, col)
		var st = _urgent.get_theme_stylebox("panel")
		if st != null and "accent_left" in st:
			st.accent_left = col
		_flash_tab(String(urgent_now["tab"]), String(urgent_now["text"]).left(24))
	# Tabs: label = count badge; colour = the most urgent item.
	# Names (no icon, a little smaller) from NAMES_W: three tabs fit a row, so the tabs take two rows. Narrower:
	# icon + count.
	var named: bool = _width >= NAMES_W
	names_shown = named
	for t in TABS:
		var id: String = t[0]
		var s: Dictionary = tab_state(id)
		var b: Button = _tab_btn[id]
		var n: int = int(s["count"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.icon = null if named else (b.get_meta("icon") as Texture2D)
		b.add_theme_font_size_override("font_size", 11 if named else 12)
		b.text = ("%s%s" % [t[1], (" %d" % n) if n > 0 else ""]) if named else (("%d" % n) if n > 0 else "")
		b.add_theme_color_override("font_color", PRIO_COL.get(String(s["priority"]), P.TEXT_2) if n > 0 else P.TEXT_2)
		b.add_theme_color_override("icon_normal_color", PRIO_COL.get(String(s["priority"]), P.TEXT_2) if n > 0 and String(s["priority"]) != "info" else P.TEXT_2)
		b.tooltip_text = "%s%s\n%s" % [t[1], (" · %d" % n) if n > 0 else "", _tab_tip(id)]
	# Columns: as many tab buttons as fit beside the dock controls (the widest button sets the column).
	var bw := 0.0
	for b2 in _tab_btn.values():
		bw = maxf(bw, (b2 as Control).get_combined_minimum_size().x)
	var avail: float = _width - 16.0
	var cols: int = clampi(int(floorf((avail + 2.0) / (bw + 2.0))), 1, TABS.size())
	if names_shown and cols > 3:
		cols = 3   # named tabs: 3 by 2, even rows
	elif cols > 3 and cols < TABS.size():
		cols = 3 if TABS.size() % 3 == 0 and cols < 6 else cols
	if _tabbar.columns != cols:
		_tabbar.columns = cols
	if tab == "news" and _body.is_visible_in_tree():
		_fill_news()

func _fill_news() -> void:
	var sig: String = "%d:%s" % [feed.size(), String(feed[0]["text"]) if not feed.is_empty() else ""]
	if sig == _news_sig:
		return
	_news_sig = sig
	Kit.clear(_news)
	if feed.is_empty():
		_news.add_child(Kit.label("No messages yet.", "SmallLabel", 12, P.TEXT_3))
	for e in feed:
		var h: HBoxContainer = Kit.hbox(6)
		h.add_child(Kit.icon(String(e["icon"]), 14, PRIO_COL.get(String(e["priority"]), P.CYAN)))
		var l: Label = Kit.wrap(String(e["text"]), 12, P.TEXT if not bool(e["seen"]) else P.TEXT_2)
		h.add_child(l)
		_news.add_child(h)
		e["seen"] = true

## The rects the manager shows now (tests): the urgent line, each pop-up, the dock.
func shown_rects() -> Array:
	var out: Array = []
	for c in [_urgent, _dock]:
		if (c as Control).is_visible_in_tree():
			out.append((c as Control).get_global_rect())
	for p in _pops.get_children():
		out.append((p as Control).get_global_rect())
	return out
