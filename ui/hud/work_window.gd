extends PanelContainer
## The Work window (V5_DESIGN §18.3; Paul, 2026-10-04: I need a list of things to be done, a work queue, so I can change the
## order). Key M. Tabs: All and one per department (SIM: maintenance, industry, food, science, logistics, security). Each row is an
## open item of work (build, repair, maintain, haul, produce, research) with its reason, who has it and the time it waited. Orders
## and team orders are rows too. Click a row to select it: Top, Up, Down, Bottom move it, Assign to... gives it to a colonist, Cancel
## holds it (nobody takes it for ten minutes; Release lifts the hold). Drag a row onto another row of its department to put it
## before that one. The job choice of SIM follows the queue order, after orders and critical needs.
## A window of the window manager in the right quarter (Quarter). Data and commands: ui/v18_data.gd (sim.workq).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const Quarter = preload("res://ui/wm/quarter.gd")
const ListRow = preload("res://ui/theme/list_row.gd")
const WIDTH := 450.0
const MAX_ROWS := 60

## A row that can be dragged onto another row (Godot drag and drop).
class WorkRow extends PanelContainer:
	var win
	var key := ""
	var label := ""
	func _get_drag_data(_at: Vector2):
		var l := Label.new()
		l.text = label
		l.add_theme_font_size_override("font_size", 13)
		if get_viewport() != null and get_viewport().gui_is_dragging():
			set_drag_preview(l)
		else:
			l.free()
		return {"work_key": key}
	func _can_drop_data(_at: Vector2, data) -> bool:
		return typeof(data) == TYPE_DICTIONARY and (data as Dictionary).has("work_key") and String((data as Dictionary)["work_key"]) != key
	func _drop_data(_at: Vector2, data) -> void:
		win.drop_on(String((data as Dictionary)["work_key"]), key)

var hud
var dept := "all"
var selected := ""              # the key of the selected row
var rows_now: Array = []        # the rows shown (tests)
var _head: HBoxContainer
var _sub: Label
var _tabs: HFlowContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _msg: Label
var _sig := ""
var _tab_btn := {}

func _ready() -> void:
	var st = GlassFrame.new()
	st.kind = "window"
	st.header_h = 50.0
	st.content_margin_left = 20
	st.content_margin_right = 22
	st.content_margin_top = 12
	st.content_margin_bottom = 14
	add_theme_stylebox_override("panel", st)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	_head = Kit.hbox(10)
	_head.custom_minimum_size.y = 30
	v.add_child(_head)
	_head.add_child(Kit.icon("queue", 22, P.CYAN))
	var t: Label = Kit.head("WORK", P.TEXT, 16, "head_wide")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(t)
	var close_b: Button = Kit.icon_button("close", func(): visible = false, "Close\nEsc, or key M. The work goes on.", "GhostButton", 16, 30)
	_head.add_child(close_b)
	Quarter.thin(close_b)
	_sub = Kit.wrap("", 13, P.TEXT_2)
	v.add_child(_sub)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 4)
	_tabs.add_theme_constant_override("v_separation", 4)
	v.add_child(_tabs)
	_body = Kit.vbox(0)
	_list = Kit.seam_list(2)
	_body.add_child(_list)
	var well: PanelContainer = Kit.well_scroll(_body)
	_scroll = well.get_child(0) as ScrollContainer
	_scroll.custom_minimum_size = Vector2(WIDTH - 64, 300)
	v.add_child(well)
	_msg = Kit.wrap("", 13, P.TEXT_2)
	v.add_child(_msg)
	visibility_changed.connect(func():
		if visible:
			_sig = ""
			refresh(true))

func register_window(wm) -> void:
	wm.register(self, "work", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.end.x - sz.x, wa.position.y + 40.0))

func wm_close() -> void:
	visible = false

func toggle() -> void:
	visible = not visible

## Opens on a department tab ("all" or a department key).
func open_tab(key: String) -> void:
	dept = key
	selected = ""
	_sig = ""
	visible = true
	refresh(true)

func _build_tabs() -> void:
	Kit.clear(_tabs)
	_tab_btn = {}
	for d in hud.v18.work_depts():
		var key: String = d[0]
		var nm: String = d[1]
		var b: Button = Kit.button("", func():
			dept = key
			selected = ""
			_sig = ""
			refresh(true), ("%s\nThe open work of this department, in queue order." % nm) if key != "all" else "All\nThe open work of every department.", "TabButton")
		b.toggle_mode = true
		b.set_meta("dept", key)
		b.set_meta("name", nm)
		b.add_theme_font_size_override("font_size", 12)
		_tabs.add_child(b)
		_tab_btn[key] = b

func refresh(force: bool = false) -> void:
	if not visible:
		return
	Quarter.fit(self, hud, "work", WIDTH, _scroll, _body, 64.0, 520.0)   # 64: the window margins (42) and the well around the scroll area
	if _tab_btn.is_empty():
		_build_tabs()
	var v18 = hud.v18
	var items: Array = v18.work_items(dept)
	var sum: Dictionary = v18.summary()
	var sig: String = "%s|%s|" % [dept, selected]
	for it in items:
		sig += "%s:%d:%s:%d:%s|" % [it["key"], int(it["assignee"]), it["state"], int(float(it["waiting_s"]) / 10.0), it["reason"]]
	sig += str(sum["by_dept"]) + str(sum["urgent"])
	if sig == _sig and not force:
		return
	_sig = sig
	rows_now = items
	var total := 0
	for d in sum["by_dept"]:
		total += int(sum["by_dept"][d])
	for key in _tab_btn:
		var b: Button = _tab_btn[key]
		b.text = "%s %d" % [String(b.get_meta("name")), total if key == "all" else int(sum["by_dept"].get(key, 0))]
		b.set_pressed_no_signal(key == dept)
	_sub.text = "%s  ·  %d urgent and not assigned" % [Kit.plural(total, "item"), int(sum["urgent"])]
	Kit.clear(_list)
	var shown := 0
	var has_sel := false
	for it in items:
		if String(it["key"]) == selected:
			has_sel = true
		if shown >= MAX_ROWS:
			continue
		_list.add_child(_row(it))
		shown += 1
	if not has_sel:
		selected = ""
	if items.is_empty():
		_list.add_child(Kit.wrap("Nothing waits in this queue.", 13, P.TEXT_3))
	elif items.size() > MAX_ROWS:
		_list.add_child(Kit.wrap("%s not shown." % Kit.plural(items.size() - MAX_ROWS, "more item"), 12, P.TEXT_3))
	Kit.fit(self)

func _row(it: Dictionary) -> Control:
	var key: String = String(it["key"])
	var urgent: bool = bool(it["urgent"])
	var state: String = String(it["state"])
	var taken: bool = int(it["assignee"]) >= 0
	var col: Color = P.RED if urgent else (P.TEXT_3 if state == "held" else (P.CYAN if taken else P.AMBER))
	var row := WorkRow.new()
	row.win = self
	row.key = key
	row.label = String(it["text"])
	row.name = "Row_" + key.replace(":", "_")
	row.add_theme_stylebox_override("panel", ListRow.make(col))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("key", key)
	# Select on the release: the row is rebuilt by the selection, and a release without its row would reach the map.
	row.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			row.accept_event()
			if not ev.pressed:
				selected = "" if selected == key else key
				_sig = ""
				refresh(true))
	var v: VBoxContainer = Kit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var l1: HBoxContainer = Kit.hbox(6)
	l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l1)
	var grip: TextureRect = Kit.icon("list", 13, P.TEXT_3)
	grip.tooltip_text = "Drag\nDrag this row onto another row to put it before that one."
	grip.mouse_filter = Control.MOUSE_FILTER_PASS
	l1.add_child(grip)
	l1.add_child(Kit.icon(String(it.get("icon", "orders")), 16, col))
	var nm: Label = Kit.label(String(it["text"]), "BodyStrong", 14, P.TEXT)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size.x = 90
	nm.tooltip_text = String(it["text"])
	nm.mouse_filter = Control.MOUSE_FILTER_PASS
	l1.add_child(nm)
	if urgent:
		l1.add_child(Kit.badge("URGENT", P.RED))
	if bool(it.get("pinned", false)):
		var pin: TextureRect = Kit.icon("pin", 13, P.CYAN)
		pin.tooltip_text = "Moved by you\nThe job choice follows your place for this row."
		pin.mouse_filter = Control.MOUSE_FILTER_PASS
		l1.add_child(pin)
	var wt: Label = Kit.num(Kit.clock(float(it["waiting_s"])), 12, P.TEXT_2)
	wt.tooltip_text = "Waiting\nThe time this item has waited."
	wt.mouse_filter = Control.MOUSE_FILTER_PASS
	l1.add_child(wt)
	var reason: String = String(it["reason"])
	var who: String = _who(it)
	var l2: Label = Kit.label(("%s  ·  %s" % [reason, who]) if reason != "" else who, "SmallLabel", 12, P.TEXT_2 if taken or state == "held" else P.AMBER)
	l2.clip_text = true
	l2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l2.tooltip_text = l2.text
	l2.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(l2)
	if key == selected:
		var bt := HFlowContainer.new()
		bt.add_theme_constant_override("h_separation", 4)
		bt.add_theme_constant_override("v_separation", 4)
		v.add_child(bt)
		for spec in [["Top", "top", "chevron_up", "Top\nPut this item first in its queue."], ["Up", "up", "arrow_up", "Up\nOne place earlier."],
				["Down", "down", "arrow_down", "Down\nOne place later."], ["Bottom", "bottom", "chevron_down", "Bottom\nPut this item last in its queue."]]:
			var how: String = spec[1]
			var b: Button = Kit.button(String(spec[0]), func(): _move(it, how), String(spec[3]), "ChipButton", String(spec[2]), 12)
			b.custom_minimum_size.y = 26
			b.set_meta("act", how)
			bt.add_child(b)
		var asg: Button = Kit.button("Assign to...", func(): hud.assign.open_assign(it), "Assign to...\nGive this item to a colonist. They go at once.", "ChipButton", "people", 12)
		asg.custom_minimum_size.y = 26
		asg.set_meta("act", "assign")
		asg.disabled = state == "standing"
		if asg.disabled:
			asg.tooltip_text = "Assign to...\nA standing order stays with its colonist. Cancel it, or give a new order."
		bt.add_child(asg)
		if state == "held":
			var rl: Button = Kit.button("Release", func(): _release(it), "Release\nLift the hold: the colonists take this item again.", "ChipButton", "check", 12)
			rl.custom_minimum_size.y = 26
			rl.set_meta("act", "release")
			bt.add_child(rl)
		else:
			var cn: Button = Kit.button("Cancel", func(): _cancel(it), "Cancel\nNobody takes this item for ten minutes (a team order or a standing order ends). Release lifts the hold.", "ChipButton", "close", 12)
			cn.custom_minimum_size.y = 26
			cn.set_meta("act", "cancel")
			bt.add_child(cn)
	return row

func _who(it: Dictionary) -> String:
	var state: String = String(it["state"])
	if state == "team":
		return "Team of %s: %s" % [hud.v5.agent_name(int(it["assignee"])).get_slice(" ", 0), String(it["assignee_name"])]
	if state == "held":
		return "Held: nobody takes it"
	if state == "blocked":
		return "Not assigned"
	if int(it["assignee"]) >= 0:
		return String(it["assignee_name"]) if String(it["assignee_name"]) != "" else hud.v5.agent_name(int(it["assignee"]))
	return "Not assigned"

func _move(it: Dictionary, how: String) -> void:
	_say(hud.v18.work_move(it, how))
	_sig = ""
	refresh(true)

func drop_on(from_key: String, to_key: String) -> void:
	_say(hud.v18.work_drop(rows_now, from_key, to_key))
	_sig = ""
	refresh(true)

func _cancel(it: Dictionary) -> void:
	_say(hud.v18.work_cancel(it))
	selected = ""
	_sig = ""
	refresh(true)

func _release(it: Dictionary) -> void:
	_say(hud.v18.work_release(it))
	_sig = ""
	refresh(true)

func _say(r: Dictionary) -> void:
	_msg.text = String(r.get("text", "")) if bool(r.get("ok", false)) else "Refused: " + String(r.get("text", r.get("code", "")))
	_msg.add_theme_color_override("font_color", P.TEXT_2 if bool(r.get("ok", false)) else P.AMBER)
