extends PanelContainer
## "Who?" (V5_DESIGN §18.1, §18.2; Paul, 2026-10-04): the window behind Repair now (the inspector button and the WORN or BROKEN
## badge) and behind Assign to... in the Work window. Two ways to give the work:
##   Team order  a head of a department (a Captain, or the Base Commander for every department) allocates it to the best free
##               people and reports back in the dock (SIM: an order given to a head is a team order)
##   One person  the colonist goes at once, also from a party, from sleep or from the routine; the maintenance department first
## "Keep it in repair" makes the order a standing one (SIM kind maintain): the colonist comes back when it wears again.
## A window of the window manager in the right quarter (Quarter). Data and commands: ui/v18_data.gd.
## Modes: "repair" (a structure) and "assign" (a row of the Work window).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const Quarter = preload("res://ui/wm/quarter.gd")
const WIDTH := 400.0

var hud
var mode := "repair"
var bid := -1                 # the structure
var row: Dictionary = {}      # the Work window row (mode assign)
var _scroll: ScrollContainer
var _body: VBoxContainer
var _head: HBoxContainer
var _title: Label
var _sub: Label
var _team_head: Label
var _team_note: Label
var _heads: VBoxContainer
var _people: VBoxContainer
var _standing: CheckBox
var _msg: Label
var last_text := ""           # the last report (tests)
var last_ok := false

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
	_head.add_child(Kit.icon("wrench", 22, P.AMBER))
	_title = Kit.head("REPAIR NOW", P.TEXT, 16, "head_wide")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_head.add_child(_title)
	var close_b: Button = Kit.icon_button("close", func(): visible = false, "Close\nEsc.", "GhostButton", 16, 30)
	_head.add_child(close_b)
	Quarter.thin(close_b)
	_sub = Kit.wrap("", 13, P.TEXT_2)
	v.add_child(_sub)
	_body = Kit.vbox(8)
	_scroll = Kit.scroll(_body)
	_scroll.custom_minimum_size = Vector2(WIDTH - 42, 240)
	v.add_child(_scroll)
	_team_head = Kit.head("Team order", P.CYAN, 12)
	_body.add_child(_team_head)
	_team_note = Kit.wrap("A head of department gets the people of the department to do it, and reports back in the dock.", 12, P.TEXT_2)
	_body.add_child(_team_note)
	_heads = Kit.vbox(4)
	_body.add_child(_heads)
	_body.add_child(Kit.head("One person", P.CYAN, 12))
	_body.add_child(Kit.wrap("The colonist stops what they do and goes, also from a party or from sleep. Maintenance people are first, then the nearest.", 12, P.TEXT_2))
	var well: PanelContainer = Kit.panel("WellPanel", false)
	_body.add_child(well)
	_people = Kit.seam_list(2)
	well.add_child(_people)
	_standing = CheckBox.new()
	_standing.text = "Keep it in repair"
	_standing.tooltip_text = "Keep it in repair\nA standing order: when this structure wears or breaks again, the colonist comes back to it."
	_standing.focus_mode = Control.FOCUS_NONE
	v.add_child(_standing)
	_msg = Kit.wrap("", 13, P.TEXT_2)
	v.add_child(_msg)
	visibility_changed.connect(func():
		if visible:
			_fill())

func register_window(wm) -> void:
	wm.register(self, "assign", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.end.x - sz.x, wa.position.y + 80.0))

func wm_close() -> void:
	visible = false

## Repair now: who repairs this structure.
func open_repair(structure_id: int) -> void:
	mode = "repair"
	bid = structure_id
	row = {}
	_show()

## Assign to...: who takes this row of the Work window.
func open_assign(r: Dictionary) -> void:
	mode = "assign"
	row = r
	bid = int(r.get("b", -1))
	_show()

func _show() -> void:
	_msg.text = ""
	_standing.button_pressed = false
	visible = true
	_fill()
	hud.wm.raise("assign")

func _fill() -> void:
	var s = hud.main.sim
	var b: Dictionary = s.state["buildings"].get(bid, {})
	var repair: bool = mode == "repair"
	_title.text = "REPAIR NOW" if repair else "ASSIGN TO"
	_team_head.visible = repair
	_team_note.visible = repair
	_heads.visible = repair
	_standing.visible = repair
	if repair:
		if b.is_empty():
			_sub.text = "That structure is gone."
			return
		var ws: Dictionary = hud.v18.wear_state(b)
		var sound: bool = String(ws["need"]) == ""
		_title.text = "MAINTAIN NOW" if (sound or String(ws["need"]) == "maintain") and String(ws["state"]) == "" else "REPAIR NOW"
		_standing.disabled = sound
		if sound:
			_standing.button_pressed = true   # a structure in order has only the standing order: SIM kind maintain
		var cond: String = "broken" if String(ws["state"]) == "broken" else ("worn" + (", wear %d %%" % int(float(ws["wear"])) if float(ws["wear"]) > 0.0 else "") if String(ws["state"]) == "worn" else "in order")
		_sub.text = "%s is %s." % [String(b["name"]), cond]
	else:
		_sub.text = String(row.get("text", ""))
	Kit.clear(_heads)
	if repair:
		var hs: Array = hud.v18.heads(bid)
		if hs.is_empty():
			_heads.add_child(Kit.wrap("No head of department yet. Appoint one in the Crew window (key U).", 12, P.TEXT_3))
		for h in hs:
			var hid: int = int(h["id"])
			var btn: Button = Kit.button("", func(): _give(hid), "Team order\n%s %s allocates the work to the best free people (%d). The report shows in the dock." % [String(h["title"]), String(h["name"]), int(h["size"])], "ListButton")
			btn.custom_minimum_size.y = 40
			btn.set_meta("head", hid)
			var hb: HBoxContainer = Kit.hbox(8)
			hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			hb.offset_left = 8
			hb.offset_right = -8
			hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(hb)
			hb.add_child(Kit.icon("people", 18, P.CYAN))
			var tv: VBoxContainer = Kit.vbox(-2)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(tv)
			var l1: Label = Kit.label("%s: %s" % [String(h["dept_name"]), String(h["name"])], "", 14, P.TEXT)
			l1.clip_text = true
			l1.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l1.custom_minimum_size.x = 80
			tv.add_child(l1)
			var l2: Label = Kit.label("%s, %d people" % [String(h["title"]), int(h["size"])], "SmallLabel", 12, P.TEXT_2)
			l2.clip_text = true
			l2.custom_minimum_size.x = 80
			tv.add_child(l2)
			hb.add_child(Kit.label("Team", "SmallLabel", 12, P.CYAN))
			_heads.add_child(btn)
	Kit.clear(_people)
	for c in hud.v18.candidates(bid, 30, repair):
		var aid: int = int(c["id"])
		var btn2: Button = Kit.button("", func(): _give(aid), "%s\nGive the order to this colonist now.%s" % [String(c["name"]), (" They have another order: it ends." if bool(c["order"]) else "")], "ListButton")
		btn2.custom_minimum_size.y = 34
		btn2.set_meta("agent", aid)
		var pb: HBoxContainer = Kit.hbox(8)
		pb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pb.offset_left = 8
		pb.offset_right = -8
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn2.add_child(pb)
		var nm: Label = Kit.label(String(c["name"]), "", 14, P.TEXT)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.custom_minimum_size.x = 100
		pb.add_child(nm)
		var info: Label = Kit.label("%s · %d m" % [String(c["role_name"]), int(float(c["dist"]))], "SmallLabel", 12, P.TEXT_2)
		info.clip_text = true
		pb.add_child(info)
		_people.add_child(btn2)
	if _people.get_child_count() == 0:
		_people.add_child(Kit.wrap("No colonist can take this order now.", 13, P.TEXT_3))

## The order goes to `aid`: a colonist, or a head of a department (SIM makes it a team order).
func _give(aid: int) -> void:
	var r: Dictionary
	if mode == "repair":
		r = hud.v18.repair_order(aid, bid, _standing.button_pressed)
	else:
		r = hud.v18.work_assign(row, [aid])
	last_text = String(r.get("text", ""))
	last_ok = bool(r.get("ok", false))
	if last_ok:
		_msg.text = last_text
		_msg.add_theme_color_override("font_color", P.TEXT_2)
		visible = false
	else:
		_msg.text = "Refused: " + (last_text if last_text != "" else hud.v4.refusal_text(String(r.get("code", ""))))
		_msg.add_theme_color_override("font_color", P.AMBER)

func refresh() -> void:
	if visible:
		Quarter.fit(self, hud, "assign", WIDTH, _scroll, _body, 42.0)
