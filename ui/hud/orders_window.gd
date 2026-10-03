extends PanelContainer
## Orders (V4_DESIGN §5 "more control over colonists"): pick one colonist or a group and give an
## order: go to a point, board a vehicle, drive to a point, explore an area, survey a point of
## interest, work at a structure, stay, return to base. Orders override the colonists' own choices
## until done. An order that would kill a colonist (no air on the way, radiation) is refused with
## the reason; "Confirm anyway" sends it again with force.
## A window of the window manager. The group: "Add" puts the selected colonist in it (the inspector's
## Orders button does the same). Data and commands: ui/v4_data.gd (SIM when it has orders, else the
## mock; else the window says orders are not available yet).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const V4 = preload("res://ui/v4_data.gd")

const Quarter = preload("res://ui/wm/quarter.gd")
const WIDTH := 430.0
var _scroll: ScrollContainer

var hud
var group: Array = []            # agent ids
var last_refused: Array = []     # [agent ids] of the last order (tests)
var _last_order := {}            # the last order payload, for "Confirm anyway"
var _reasons := {}               # agent id -> {code, text, confirmable} of the last refusal
var _head: HBoxContainer
var _list: VBoxContainer
var _msg: Label
var _force: Button
var _board: OptionButton
var _haul_item: OptionButton
var _verbs: GridContainer
var _haul_qty: SpinBox
var _body: VBoxContainer
var _na: Label
var _sig := ""

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
	_head.add_child(Kit.icon("orders", 22, P.CYAN))
	var t: Label = Kit.head("ORDERS", P.TEXT, 16, "head_wide")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(t)
	var close_b: Button = Kit.icon_button("close", func(): visible = false, "Close\nEsc. The orders go on.", "GhostButton", 16, 30)
	_head.add_child(close_b)
	Quarter.thin(close_b)
	v.add_child(Kit.gap(0, 6))
	_na = Kit.wrap("Orders are not available in this game.", 14, P.TEXT_2)
	_na.custom_minimum_size.x = 360
	v.add_child(_na)
	_body = Kit.vbox(8)
	_scroll = Kit.scroll(_body)   # a narrow window scrolls its form (the right quarter of a small view)
	_scroll.custom_minimum_size = Vector2(WIDTH - 42, 220)
	v.add_child(_scroll)
	var gh: HBoxContainer = Kit.hbox(8)
	_body.add_child(gh)
	var gl: Label = Kit.head("Colonists", P.CYAN, 12)
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gh.add_child(gl)
	gh.add_child(Kit.button("Add selected", func(): add_selected(), "Add selected\nPuts the selected colonist in the group. Select a colonist first.", "ChipButton", "people", 14))
	gh.add_child(Kit.button("Clear", func():
		group = []
		refresh(true), "Clear\nEmpties the group. Their orders go on.", "ChipButton", "close", 14))
	var well: PanelContainer = Kit.panel("WellPanel", false)
	_body.add_child(well)
	_list = Kit.seam_list(2)
	well.add_child(_list)
	_body.add_child(Kit.head("Give an order", P.CYAN, 12))
	var g := GridContainer.new()
	_verbs = g
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	_body.add_child(g)
	for spec in [["goto", "Go to…", "follow", "Go to\nClick a place on the ground (or a room). They walk there; the order ends when they arrive."],
			["stay_at", "Stay at…", "target", "Stay at\nClick a place. They walk there and stay until the order is cleared."],
			["stay", "Stay here", "pause", "Stay here\nThey stop and stay where they are (thirst, hunger and exhaustion still come first)."],
			["survey", "Survey…", "search", "Survey\nClick a point of interest (a cave, a wreck…) or a hazard site. They go there. Some points need somebody on foot or a scientist."],
			["work_at", "Work at…", "build", "Work at\nClick a structure. They take its tasks (any role) until none is left there. Then the order ends."],
			["repair", "Repair…", "wrench", "Repair\nClick a structure. They stop what they do, bring a spare part and repair it. It works from health 99 down. The colony repairs by itself only below health 70."],
			["maintain", "Keep in repair…", "wrench", "Keep in repair\nClick a machine. A standing order: they come back to it each time it wears. Cancel the order to end it."],
			["build", "Help build…", "build", "Help build\nClick a planned structure or a site. They carry its materials and build it."],
			["haul", "Haul…", "cat_logistics", "Haul\nChoose the item and the amount below, then click the structure that gets it. They fetch it from the nearest store."],
			["return", "Return to base", "home", "Return to base\nThey walk to the core of their home base."]]:
		var kind: String = spec[0]
		var b: Button = Kit.button(String(spec[1]), func(): _give(kind), String(spec[3]), "", String(spec[2]), 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	var hr: HBoxContainer = Kit.hbox(8)   # Haul: the item and the amount
	_body.add_child(hr)
	_haul_item = OptionButton.new()
	_haul_item.tooltip_text = "Item\nThe item to carry. Only items that are in a store are listed."
	_haul_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_haul_item.clip_text = true
	hr.add_child(_haul_item)
	_haul_qty = SpinBox.new()
	_haul_qty.min_value = 1
	_haul_qty.max_value = 99
	_haul_qty.value = 2
	_haul_qty.tooltip_text = "Amount\nHow many units to carry."
	_haul_qty.get_line_edit().tooltip_text = _haul_qty.tooltip_text
	hr.add_child(_haul_qty)
	var br: HBoxContainer = Kit.hbox(8)
	_body.add_child(br)
	_board = OptionButton.new()
	_board.tooltip_text = "Vehicle\nThe vehicle to board."
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(_board)
	br.add_child(Kit.button("Board", func(): _give("board"), "Board vehicle\nThey walk to the vehicle and take a seat.", "", "rover", 15))
	br.add_child(Kit.button("Cancel orders", func(): _cancel(), "Cancel orders\nThey go back to their own work.", "DangerButton", "close", 14))
	_msg = Kit.wrap("", 13, P.TEXT_2)
	_msg.custom_minimum_size.x = 360
	_body.add_child(_msg)
	_force = Kit.button("Confirm anyway", func(): _confirm_force(), "Confirm anyway\nSends the refused order again. The colonist may die.", "DangerButton", "sev_warning", 14)
	_force.visible = false
	_body.add_child(_force)
	visibility_changed.connect(func():
		if visible:
			refresh(true))

func register_window(wm) -> void:
	wm.register(self, "orders", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.end.x - sz.x, wa.position.y + 60.0))

func wm_close() -> void:
	visible = false

## Opens the window with the selected colonist in the group.
func open_for_selected() -> void:
	add_selected()
	visible = true

func add_selected() -> void:
	var view = hud.main.view
	if view.selected_kind == "agent" and not group.has(int(view.selected_id)):
		group.append(int(view.selected_id))
	refresh(true)

func refresh(force: bool = false) -> void:
	if visible:
		Quarter.fit(self, hud, "orders", WIDTH, _scroll, _body, 42.0)
		_verbs.columns = 1 if Quarter.width_for(hud, WIDTH) < 400.0 else 2   # a narrow quarter: one verb in each row
	if not visible:
		return
	var ok: bool = hud.v4.available("orders") or hud.v4.live("vehicles")
	_na.visible = not ok
	_body.visible = ok
	if not ok:
		return
	var sig: String = str(group)
	for aid in group:
		sig += str(hud.v4.order_of(int(aid)))
	sig += str(hud.v4.vehicles().size())
	if sig == _sig and not force:
		return
	_sig = sig
	Kit.clear(_list)
	var agents: Dictionary = hud.main.sim.state["agents"]
	for aid in group.duplicate():
		if not agents.has(aid) or String(agents[aid].get("state", "")) != "alive":
			group.erase(aid)
			continue
		_list.add_child(_row(int(aid)))
	if group.is_empty():
		_list.add_child(Kit.wrap("Select a colonist, then Add. Or use Orders in the colonist's panel.", 13, P.TEXT_2))
	var keep_item: String = String(_haul_item.get_item_metadata(_haul_item.selected)) if _haul_item.selected >= 0 else ""
	_haul_item.clear()
	var tot: Dictionary = hud.main.sim.inv.totals()
	var names: Array = tot.keys()
	names.sort_custom(func(x, y): return hud.data.item_name(String(x)) < hud.data.item_name(String(y)))
	for it in names:
		var free: int = int(tot[it].get("total", 0)) - int(tot[it].get("reserved", 0)) - int(tot[it].get("carried", 0))
		if free > 0 and String(hud.data.item_cat(String(it))) != "dish":
			_haul_item.add_item("%s (%d)" % [hud.data.item_name(String(it)), free])
			_haul_item.set_item_metadata(_haul_item.item_count - 1, String(it))
			if String(it) == keep_item:
				_haul_item.select(_haul_item.item_count - 1)
	_board.clear()
	for vv in hud.v4.vehicles():
		if String(vv["kind"]) != "satellite":
			_board.add_item("%s (%d of %d seats)" % [String(vv["name"]), (vv.get("crew", []) as Array).size(), int(vv.get("seats", 0))], int(vv["id"]))
	Kit.fit(self)

func _row(aid: int) -> Control:
	var a: Dictionary = hud.main.sim.state["agents"][aid]
	var h: HBoxContainer = Kit.hbox(8)
	var role: String = String(a.get("role", ""))
	h.add_child(Kit.icon(load("res://ui/theme/icons.gd").role(role), 16, P.ROLE.get(role, P.CYAN)))
	var tv: VBoxContainer = Kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	tv.add_child(Kit.label(String(a.get("name", "")), "BodyStrong", 14, P.TEXT))
	var o: Dictionary = hud.v4.order_of(aid)
	var line: String
	var col: Color = P.TEXT_2
	if o.is_empty():
		line = "No order: " + String(a.get("goal", "Idle")).to_lower()
	elif String(o.get("status", "")) == "refused":   # mock only: SIM does not keep refused orders
		line = "Refused: %s %s" % [String(V4.ORDER_NAME.get(o["kind"], o["kind"])).to_lower(), hud.v4.refusal_text(String(o.get("reason", "")))]
		col = P.AMBER
	else:
		var oi: Dictionary = hud.v18.order_info(aid)
		line = "Order: %s%s" % [String(oi.get("name", V4.ORDER_NAME.get(o["kind"], o["kind"]))).to_lower(), (" " + String(oi["target"])) if String(oi.get("target", "")) != "" else ""]
		if String(oi.get("text", "")) != "":
			line += ". " + String(oi["text"])
		if bool(o.get("confirm", false)):
			line += " (risk accepted)"
		col = P.AMBER if String(oi.get("blocked", "")) != "" else P.CYAN
	var l: Label = Kit.wrap(line, 12, col)
	l.custom_minimum_size.x = 260
	tv.add_child(l)
	h.add_child(Kit.icon_button("close", func():
		group.erase(aid)
		refresh(true), "Remove from the group\nTheir order goes on.", "GhostButton", 12, 24))
	return h

func _give(kind: String) -> void:
	if group.is_empty():
		_msg.text = "The group is empty. Select a colonist and click Add selected."
		return
	var ids: Array = group.duplicate()
	match kind:
		"goto", "explore":
			hud.main.pick_point("%s: click a place on the ground. Right click cancels." % V4.ORDER_NAME[kind], func(p: Vector2, _pick: Dictionary): _send(kind, ids, p))
		"stay_at":
			hud.main.pick_point("Stay at: click a place on the ground. Right click cancels.", func(p: Vector2, _pick: Dictionary): _send("stay", ids, p))
		"survey":
			hud.main.pick_point("Survey: click a point of interest or a hazard site. Right click cancels.", func(p: Vector2, _pick: Dictionary):
				var poi: Dictionary = _poi_near(p)
				if not poi.is_empty():
					_send(kind, ids, {"poi": int(poi["id"])})
					if String(poi.get("need", "any")) != "any":
						_msg.text += " " + String(poi["need_text"])
					return
				var site: int = _site_near(p)
				if site < 0:
					hud.toast("Survey: no point of interest or hazard site there.", "warn")
					return
				_send(kind, ids, site))
		"work_at", "repair", "maintain", "build":
			var verb: String = String(V4.ORDER_NAME.get(kind, kind))
			hud.main.pick_point("%s: click a structure. Right click cancels." % verb, func(_p: Vector2, pick: Dictionary):
				# The structure under the click, also when a colonist stands on it (main.structure_at).
				var sid: int = int(pick.get("struct", -1))
				if sid < 0 and String(pick.get("kind", "")) == "building":
					sid = int(pick["id"])
				if sid < 0:
					hud.toast("%s: that is not a structure." % verb, "warn")
					return
				_send(kind, ids, sid))
		"haul":
			if _haul_item.selected < 0:
				_msg.text = "No item to carry: no store holds anything."
				return
			var res: String = String(_haul_item.get_item_metadata(_haul_item.selected))
			var qty: int = int(_haul_qty.value)
			hud.main.pick_point("Haul %d %s: click the structure that gets it. Right click cancels." % [qty, hud.data.item_name(res).to_lower()], func(_p: Vector2, pick: Dictionary):
				var sid: int = int(pick.get("struct", -1))
				if sid < 0:
					hud.toast("Haul: that is not a structure.", "warn")
					return
				_send(kind, ids, {"b": sid, "res": res, "qty": qty}))
		"board":
			if _board.selected < 0:
				_msg.text = "No vehicle to board."
				return
			if hud.v4.live("vehicles"):
				# Boarding is live in SIM (vehicle_board): the other orders are still the mock.
				var r: Dictionary = hud.v4.vehicle_cmd("board", _board.get_selected_id(), {"agents": ids})
				var ok: bool = bool(r.get("ok", false)) or String(r.get("code", "")) == "submitted"
				_msg.text = ("%s walking to the vehicle." % Kit.plural(ids.size(), "colonist")) if ok else ("Refused: " + hud.v4.refusal_text(String(r.get("code", ""))))
				_msg.add_theme_color_override("font_color", P.TEXT_2 if ok else P.AMBER)
				return
			_send(kind, ids, _board.get_selected_id())
		_:
			_send(kind, ids, null)

func _send(kind: String, ids: Array, target) -> void:
	_last_order = {"agents": ids, "kind": kind, "target": target, "force": false}
	var r: Dictionary = hud.v4.command("order_give", _last_order)
	last_refused = r.get("refused", [])
	_reasons = r.get("reasons", {})
	if String(r.get("code", "")) == "not_available":
		_msg.text = "%s comes with the simulation's orders (not yet). Boarding a vehicle works now." % V4.ORDER_NAME.get(kind, kind)
		_msg.add_theme_color_override("font_color", P.AMBER)
		_force.visible = false
		return
	if last_refused.is_empty():
		_msg.text = "%s: order given to %s." % [V4.ORDER_NAME.get(kind, kind), Kit.plural(ids.size(), "colonist")]
		_msg.add_theme_color_override("font_color", P.TEXT_2)
		_force.visible = false
	else:
		# The reasons are SIM's own texts; only some refusals can be confirmed (air margin, staying
		# outside, radiation): then "Confirm anyway" shows.
		var texts: Array = []
		var any_conf := false
		for aid in last_refused:
			var rs: Dictionary = _reasons.get(aid, {})
			var t: String = String(rs.get("text", "")) if String(rs.get("text", "")) != "" else hud.v4.refusal_text(String(rs.get("code", "")))
			if not texts.has(t):
				texts.append(t)
			any_conf = any_conf or bool(rs.get("confirmable", false))
		var given: int = ids.size() - last_refused.size()
		_msg.text = ("%s given. " % Kit.plural(given, "order") if given > 0 else "") + "Refused for %s: %s" % [Kit.plural(last_refused.size(), "colonist"), " ".join(texts)]
		_msg.add_theme_color_override("font_color", P.AMBER)
		_force.visible = any_conf
	refresh(true)

func _confirm_force() -> void:
	if _last_order.is_empty():
		return
	var again: Dictionary = _last_order.duplicate()
	var conf: Array = []
	for aid in last_refused:
		if bool((_reasons.get(aid, {}) as Dictionary).get("confirmable", true)):
			conf.append(aid)
	again["agents"] = conf
	again["force"] = true
	hud.confirm("Send the order anyway?", ["%s may die: %s" % [Kit.plural(last_refused.size(), "colonist"), _msg.text.get_slice(": ", 1)]], func():
		hud.v4.command("order_give", again)
		last_refused = []
		_force.visible = false
		_msg.text = "Order sent anyway."
		refresh(true), "Send anyway", true)

## The nearest found point of interest not yet visited within 40 m of p (SIM milestone 7), or {}.
func _poi_near(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := 40.0
	for poi in hud.v4.pois():
		if bool(poi.get("visited", false)):
			continue
		var dd: float = (poi["pos"] as Vector2).distance_to(p)
		if dd < bd:
			bd = dd
			best = poi
	return best

## The nearest hazard site not yet surveyed within 40 m of p (SIM sim.hazards.hs().sites), or -1.
func _site_near(p: Vector2) -> int:
	var hz = hud.main.sim.get("hazards")
	if hz == null or not hz.has_method("hs"):
		return -1
	var best := -1
	var bd := 40.0
	var sites: Dictionary = hz.hs().get("sites", {})
	for sid in sites:
		var st: Dictionary = sites[sid]
		if bool(st.get("surveyed", false)) or not st.has("pos"):
			continue
		var dd: float = (st["pos"] as Vector2).distance_to(p)
		if dd < bd:
			bd = dd
			best = int(sid)
	return best

func _cancel() -> void:
	hud.v4.command("order_cancel", {"agents": group.duplicate()})
	_msg.text = "Orders cancelled."
	_force.visible = false
	refresh(true)
