extends "res://ui/screens/screen.gd"
## Vehicles (V4_DESIGN §5): every rover, hopper and the satellite, and the routes between bases.
## Tab Vehicles: a seam list on the left (kind, state, charge or fuel, cargo, crew, wear); the chosen
## vehicle on the right with its orders (go to a point, explore an area, return, charge) and a Show
## button. Tab Routes: each medium rover's route (load at base A, unload at base B) and a route
## builder. Data: ui/v4_data.gd (SIM when it has vehicles, else the mock; else "not available").
## Key R is taken (turn), so: the nav rail, or `open vehicles`.

const V4 = preload("res://ui/v4_data.gd")

var _v4
var _sel := -1
var _detail: VBoxContainer
var _list: VBoxContainer
var _list_well: Control
var _detail_scroll: ScrollContainer
var _route_from := -1
var _route_to := -1
var _route_load := {}
var _route_back := {}
var rows: Array = []        # vehicle ids in the list (tests)

const STATE_WORD := {"parked": "Parked", "driving": "Driving", "charging": "Charging", "exploring": "Exploring", "broken": "Broken"}

func _init() -> void:
	pauses = false
	icon = "rover"
	title = "Vehicles"
	subtitle = "Rovers and hoppers: charge or fuel, cargo, crew, orders and routes between bases."
	accent = P.CYAN
	tabs = [["vehicles", "Vehicles", "rover"], ["routes", "Routes", "route"]]

func build() -> void:
	_v4 = hud.v4

## Critic round 22: both tabs are sized to their content (they were large and mostly empty).
func fits_content() -> bool:
	return true

func build_tab(id: String, box: VBoxContainer) -> void:
	if _v4.vehicles().is_empty() and id == "vehicles":
		box.add_child(Kit.wrap("No vehicles yet. Build a rover depot (research Space 1), then build a rover from its panel.", 15, P.TEXT_2))
		return
	match id:
		"vehicles": _vehicles_tab(box)
		"routes": _routes_tab(box)

func _vehicles_tab(box: VBoxContainer) -> void:
	var row: HBoxContainer = Kit.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var left: VBoxContainer = Kit.vbox(6)
	left.custom_minimum_size.x = 420
	row.add_child(left)
	_list = Kit.seam_list(2)
	_list_well = Kit.well_scroll(_list)
	left.add_child(_list_well)
	var right: PanelContainer = Kit.panel("CardPanel", false)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 720
	row.add_child(right)
	_detail = Kit.vbox(10)
	_detail_scroll = Kit.scroll(_detail)
	right.add_child(_detail_scroll)
	rows = []
	for v in _v4.vehicles():
		rows.append(int(v["id"]))
		_list.add_child(_row(v))
	if _sel == -1 and not rows.is_empty():
		_sel = rows[0]
	_show(_sel)
	fit_scroll(_list_well, 560.0)

func _energy(v: Dictionary) -> Array:
	# [label, value 0..1]: hoppers burn fuel, rovers run on charge.
	if String(v["kind"]) == "hopper":
		return ["Fuel", float(v.get("fuel", 0.0))]
	if String(v["kind"]) == "satellite":
		return ["Power", 1.0]
	return ["Charge", float(v.get("charge", 0.0))]

func _row(v: Dictionary) -> Control:
	var b: Button = Kit.button("", Callable(), "%s\n%s, %s. Click to see it and give orders." % [String(v["name"]), _v4.vehicle_name(String(v["kind"])), String(STATE_WORD.get(v["state"], v["state"])).to_lower()], "ListButton")
	b.custom_minimum_size.y = 52
	b.toggle_mode = true
	b.set_pressed_no_signal(int(v["id"]) == _sel)
	var vid: int = int(v["id"])
	b.pressed.connect(func(): _show(vid))
	var h: HBoxContainer = Kit.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.add_child(Kit.icon(_icon(String(v["kind"])), 22, P.CYAN))
	var tv: VBoxContainer = Kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	tv.add_child(Kit.label(String(v["name"]), "BodyStrong", 14, P.TEXT))
	tv.add_child(Kit.label("%s · %s" % [_v4.vehicle_name(String(v["kind"])), String(STATE_WORD.get(v["state"], v["state"]))], "SmallLabel", 12, P.TEXT_2))
	var e: Array = _energy(v)
	var ev: VBoxContainer = Kit.vbox(2)
	ev.custom_minimum_size.x = 90
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ev)
	ev.add_child(Kit.label("%s %d%%" % [e[0], int(float(e[1]) * 100.0)], "SmallLabel", 12, P.level(float(e[1]) * 100.0, 40.0, 20.0)))
	var bar = Kit.bar(float(e[1]), P.level(float(e[1]) * 100.0, 40.0, 20.0), 4.0)
	bar.custom_minimum_size.x = 90
	ev.add_child(bar)
	return b

static func _icon(kind: String) -> String:
	var Icons = load("res://ui/theme/icons.gd")
	for n in [kind, "rover", "ship"]:
		if Icons.has(n):
			return n
	return "info"

func _show(id: int) -> void:
	_sel = id
	if _detail_scroll != null:
		(func(): if is_instance_valid(_detail_scroll): fit_scroll(_detail_scroll, 620.0)).call_deferred()
	for i in _list.get_child_count():
		var c = _list.get_child(i)
		if c is Button:
			(c as Button).set_pressed_no_signal(i < rows.size() and rows[i] == id)
	Kit.clear(_detail)
	var v: Dictionary = _v4.vehicle(id)
	if v.is_empty():
		return
	var h: HBoxContainer = Kit.hbox(12)
	_detail.add_child(h)
	h.add_child(Kit.icon(_icon(String(v["kind"])), 36, P.CYAN))
	var tv: VBoxContainer = Kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	tv.add_child(Kit.label(String(v["name"]).to_upper(), "TitleLabel", 20, P.TEXT))
	tv.add_child(Kit.label("%s · %s · base: %s" % [_v4.vehicle_name(String(v["kind"])), String(STATE_WORD.get(v["state"], v["state"])),
		String(hud.main.sim.bases.name_of(int(v.get("base", 1)))) if "bases" in hud.main.sim and hud.main.sim.bases != null else "-"], "DimLabel", 13, P.TEXT_2))
	h.add_child(Kit.icon_button("target", func(): _go(v), "Show\nMoves the camera to the vehicle.", "GhostButton", 18, 34))
	var g: GridContainer = Kit.grid(2, 16, 4)
	_detail.add_child(g)
	var e: Array = _energy(v)
	_fact(g, e[0], "%d%%" % int(float(e[1]) * 100.0))
	_fact(g, "Range now", "%d m" % int(float(v.get("range_m", 0.0)) * float(e[1])))
	var cargo: Dictionary = v.get("cargo", {})
	var used := 0
	for it in cargo:
		used += int(cargo[it])
	_fact(g, "Cargo", "%d of %d" % [used, int(v.get("cargo_cap", 0))])
	_fact(g, "Crew", "%d of %d seats" % [(v.get("crew", []) as Array).size(), int(v.get("seats", 0))])
	_fact(g, "Wear", "%d%%" % int(float(v.get("wear", 0.0))))
	if not cargo.is_empty():
		var f := HFlowContainer.new()
		f.add_theme_constant_override("h_separation", 10)
		for it in cargo:
			f.add_child(Kit.chip(load("res://ui/theme/icons.gd").item(String(it)), str(cargo[it]), hud.data.item_color(String(it)), hud.data.item_name(String(it)), true, 16))
		_detail.add_child(f)
	var crew: Array = v.get("crew", [])
	if not crew.is_empty():
		var names: Array = []
		for aid in crew:
			names.append(String(hud.main.sim.state["agents"].get(aid, {}).get("name", "?")))
		_detail.add_child(Kit.wrap("On board: " + ", ".join(names) + ".", 14, P.TEXT))
	var blk: String = String(v.get("block", ""))
	if blk != "":
		var bl: Label = Kit.wrap("Stopped: " + (blk if blk.begins_with("route") else _v4.refusal_text(blk)), 14, P.AMBER)
		bl.custom_minimum_size.x = 380
		_detail.add_child(bl)
	_detail.add_child(Kit.sep())
	_detail.add_child(Kit.head("Orders", P.CYAN, 12))
	var act := HFlowContainer.new()
	act.add_theme_constant_override("h_separation", 8)
	act.add_theme_constant_override("v_separation", 6)
	_detail.add_child(act)
	var vid: int = id
	act.add_child(Kit.button("Drive to…", func(): _pick_drive(vid), "Drive to\nClick a place on the ground. The driver takes the safest path (rovers) or hops there (hopper).", "", "follow", 15))
	act.add_child(Kit.button("Return", func(): _do(vid, "return"), "Return\nBack to a free bay of its depot (else the nearest depot): it charges, refuels and is repaired there.", "", "home", 15))
	act.add_child(Kit.button("Stop", func(): _do(vid, "stop"), "Stop\nStops where it is. The crew stays aboard; a route ends.", "", "pause", 15))
	act.add_child(Kit.button("Board…", func(): _board(vid), "Board\nThe colonists in the Orders group (else the selected colonist) walk to it and get in.", "", "people", 15))
	act.add_child(Kit.button("Get out", func(): _do(vid, "alight"), "Get out\nEveryone gets out beside it, in suits.", "", "evacuate", 15))
	act.add_child(Kit.button("Explore area…", func(): _pick_drive(vid, "explore"), "Explore area\nClick a place: the driver takes it round 8 points on a 150 m circle there (points it cannot reach are left out).", "", "search", 15))
	# Cargo with the stores of the base where it stands (SIM vehicle_cargo: stores within 85 m).
	_detail.add_child(Kit.head("Cargo", P.CYAN, 12))
	var cg := HFlowContainer.new()
	cg.add_theme_constant_override("h_separation", 6)
	cg.add_theme_constant_override("v_separation", 6)
	_detail.add_child(cg)
	cg.add_child(Kit.button("Unload all", func(): _do(vid, "cargo", {"unload": true}), "Unload all\nEverything in the cargo goes to the stores within 85 m.", "", "import", 14))
	for it in ["metal", "polymer", "electronics", "spare_parts", "composite", "rocket_fuel", "outpost_kit"]:
		if not hud.data.items().has(it):
			continue
		var iid: String = it
		var n: int = 1 if iid == "outpost_kit" else 5
		cg.add_child(Kit.button("+%d %s" % [n, hud.data.item_name(iid).to_lower()], func(): _do(vid, "cargo", {"load": {iid: n}}),
			"Load %d %s\nFrom the stores within 85 m (it must stand still)." % [n, hud.data.item_name(iid).to_lower()], "ChipButton", load("res://ui/theme/icons.gd").item(iid), 14))
	# Outpost Kit from the cargo (SIM deploy_outpost with the vehicle's cargo inventory).
	if int((v.get("cargo", {}) as Dictionary).get("outpost_kit", 0)) > 0:
		act.add_child(Kit.button("Deploy Outpost Kit…", func(): _pick_outpost(vid), "Deploy Outpost Kit\nClick a place within 30 m of the vehicle and at least 300 m from other bases: a new base with air for 3 days.", "PrimaryButton", "home", 15))
	var msg: Label = Kit.wrap("", 13, P.TEXT_2)
	msg.name = "Msg"
	msg.custom_minimum_size.x = 380
	_detail.add_child(msg)

func _fact(g: GridContainer, name: String, value: String) -> void:
	g.add_child(Kit.dim(name, 13))
	var v: Label = Kit.num(value, 13, P.TEXT)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.add_child(v)

func _go(v: Dictionary) -> void:
	host.close(self)
	hud.main.focus_on(v["pos"])

func _say(r: Dictionary, done: String) -> void:
	var m: Label = _detail.find_child("Msg", true, false) if _detail != null and is_instance_valid(_detail) else null
	var ok: bool = bool(r.get("ok", false)) or String(r.get("code", "")) == "submitted"
	var text: String = done if ok else "Refused: " + _v4.refusal_text(String(r.get("code", "")))
	if m != null and is_instance_valid(m):
		m.text = text
	else:
		hud.toast(text, "info" if ok else "warn")

func _do(vid: int, kind: String, p: Dictionary = {}) -> void:
	var r: Dictionary = _v4.vehicle_cmd(kind, vid, p)
	_say(r, {"return": "Going back to a depot.", "stop": "Stopped.", "alight": "The crew gets out.", "cargo": "Cargo moved."}.get(kind, "Order given."))
	if kind == "cargo" and bool(r.get("ok", false)):
		_show(vid)

func _board(vid: int) -> void:
	var ids: Array = hud.orders.group.duplicate()
	if ids.is_empty() and hud.main.view.selected_kind == "agent":
		ids = [hud.main.view.selected_id]
	if ids.is_empty():
		_say({"ok": false, "code": "no_one"}, "")
		var m: Label = _detail.find_child("Msg", true, false)
		if m != null:
			m.text = "Nobody to board: select a colonist, or put colonists in the Orders group."
		return
	_say(_v4.vehicle_cmd("board", vid, {"agents": ids}), "%s walking to it." % Kit.plural(ids.size(), "colonist"))

func _pick_drive(vid: int, kind: String = "drive") -> void:
	host.close(self)
	hud.main.pick_point("%s: click a place on the ground. Right click cancels." % ("Drive to" if kind == "drive" else "Explore"), func(p: Vector2, _pick: Dictionary):
		var r: Dictionary = hud.v4.vehicle_cmd(kind, vid, {"target": p})
		var ok: bool = bool(r.get("ok", false)) or String(r.get("code", "")) == "submitted"
		hud.toast("%s: %s" % [String(hud.v4.vehicle(vid).get("name", "Vehicle")), "on the way." if ok else hud.v4.refusal_text(String(r.get("code", "")))], "info" if ok else "warn"))

## Outpost Kit: pick the place, preview it with sim.bases.check_outpost, then deploy from the cargo.
func _pick_outpost(vid: int) -> void:
	host.close(self)
	hud.main.pick_point("Deploy Outpost Kit: click the place (within 30 m of the vehicle). Right click cancels.", func(p: Vector2, _pick: Dictionary):
		var s = hud.main.sim
		var chk: String = String(s.bases.check_outpost(p, 0.0)) if "bases" in s and s.bases != null else "ok"
		if chk != "ok":
			hud.toast("Outpost Kit: " + hud.v4.refusal_text(chk), "warn")
			return
		var v: Dictionary = hud.v4.vehicle(vid)
		if (v.get("pos", p) as Vector2).distance_to(p) > 30.0:
			hud.toast("Outpost Kit: " + hud.v4.refusal_text("kit_far"), "warn")
			return
		var r: Dictionary = hud.v4.vehicle_cmd("deploy", vid, {"x": p.x, "y": p.y})
		var ok: bool = bool(r.get("ok", false)) or String(r.get("code", "")) == "submitted"
		hud.toast("Outpost Kit: " + ("a new base is set up." if ok else hud.v4.refusal_text(String(r.get("code", "")))), "info" if ok else "warn"))
# ---------------------------------------------------------------- routes
## A route (SIM vehicle_route): unload + load at base A, drive to B, unload + load "back", drive to A,
## again and again while it has a driver. Stop ends it.
func _routes_tab(box: VBoxContainer) -> void:
	box.add_child(Kit.wrap("A vehicle on a route loads at one base, unloads at the other, and brings things back, again and again while it has a driver. A medium rover is the one for this: large cargo, six seats.", 14, P.TEXT_2, 860.0))
	var list: VBoxContainer = Kit.seam_list(4)
	var well: PanelContainer = Kit.well_scroll(list)
	box.add_child(well)
	(func(): if is_instance_valid(well): fit_scroll(well, 360.0)).call_deferred()
	var vs: Array = _v4.vehicles()
	for v in vs:
		var h: HBoxContainer = Kit.hbox(10)
		h.add_child(Kit.icon(_icon(String(v["kind"])), 20, P.CYAN))
		var r = v.get("route")
		var txt: String
		if r == null:
			txt = "%s: no route." % String(v["name"])
		else:
			txt = "%s: %s → %s, takes %s, brings back %s. %s so far." % [String(v["name"]), _base(int(r["from"])), _base(int(r["to"])),
				_items_text(r.get("load", {})), _items_text(r.get("back", {})), Kit.plural(int(r.get("trips", 0)), "delivery", "deliveries")]
		var l: Label = Kit.wrap(txt, 14, P.TEXT if r != null else P.TEXT_2)
		l.custom_minimum_size.x = 380
		h.add_child(l)
		var vid: int = int(v["id"])
		if r != null:
			h.add_child(Kit.button("Stop", func():
				_v4.vehicle_cmd("route_stop", vid)
				_build_tab_content(), "Stop the route\nThe vehicle stops; the crew stays aboard.", "", "close", 14))
		list.add_child(h)
	if vs.is_empty():
		list.add_child(Kit.label("No vehicle yet. Build one at a rover depot.", "", 14, P.TEXT_2))
		return
	var bases: Array = hud.main.sim.bases.list() if "bases" in hud.main.sim and hud.main.sim.bases != null else []
	box.add_child(Kit.head("New route", P.CYAN, 12))
	if bases.size() < 2:
		box.add_child(Kit.wrap("A route needs two bases. Found a second base with an Outpost Kit.", 14, P.TEXT_2, 860.0))
		return
	var b1 := OptionButton.new()
	var b2 := OptionButton.new()
	b1.tooltip_text = "Base A\nWhere the vehicle loads first."
	b2.tooltip_text = "Base B\nWhere it unloads, and loads what it brings back."
	for b in bases:
		b1.add_item(String(b["name"]), int(b["id"]))
		b2.add_item(String(b["name"]), int(b["id"]))
	b2.select(1)
	var vr := OptionButton.new()
	vr.tooltip_text = "Vehicle\nThe vehicle that runs the route (a medium rover is best)."
	for v in vs:
		vr.add_item("%s (%s)" % [String(v["name"]), _v4.vehicle_name(String(v["kind"])).to_lower()], int(v["id"]))
	var row: HBoxContainer = Kit.hbox(8)
	row.add_child(Kit.label("Vehicle", "", 14, P.TEXT_2))
	row.add_child(vr)
	row.add_child(Kit.label("A", "", 14, P.TEXT_2))
	row.add_child(b1)
	row.add_child(Kit.label("B", "", 14, P.TEXT_2))
	row.add_child(b2)
	box.add_child(row)
	box.add_child(_amount_row("Take to B:", _route_load))
	box.add_child(_amount_row("Bring back to A:", _route_back))
	var msg: Label = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	var go: Button = Kit.button("Start the route", func():
		if b1.selected < 0 or b2.selected < 0 or vr.selected < 0:
			msg.text = "Pick a vehicle and two bases."
			return
		if b1.get_selected_id() == b2.get_selected_id():
			msg.text = "The two bases must be different."
			return
		var r: Dictionary = _v4.vehicle_cmd("route", vr.get_selected_id(), {"from": b1.get_selected_id(), "to": b2.get_selected_id(), "load": _route_load.duplicate(), "back": _route_back.duplicate()})
		if bool(r.get("ok", false)) or String(r.get("code", "")) == "submitted":
			_route_load = {}
			_route_back = {}
			_build_tab_content()
		else:
			msg.text = "Refused: " + _v4.refusal_text(String(r.get("code", ""))), "Start the route\nThe vehicle starts at once when it has a driver.", "PrimaryButton", "route", 15)
	var gr: HBoxContainer = Kit.hbox(10)
	gr.add_child(go)
	gr.add_child(msg)
	box.add_child(gr)

func _items_text(d: Dictionary) -> String:
	if d.is_empty():
		return "nothing"
	var out: Array = []
	for it in d:
		out.append("%d %s" % [int(d[it]), hud.data.item_name(String(it)).to_lower()])
	return ", ".join(out)

## A row of item chips: click +10 (Outpost Kit +1), right click clears it.
func _amount_row(lead: String, target: Dictionary) -> Control:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 4)
	f.add_child(Kit.label(lead, "", 14, P.TEXT_2))
	for it in ["metal", "polymer", "electronics", "spare_parts", "composite", "water", "rocket_fuel", "outpost_kit"]:
		if not hud.data.items().has(it):
			continue
		var iid: String = it
		var step: int = 1 if iid == "outpost_kit" else 10
		var c: Button = Kit.button("%s %d" % [hud.data.item_name(iid), int(target.get(iid, 0))], Callable(), "%s\nClick: +%d. Right click: none." % [hud.data.item_name(iid), step], "ChipButton", load("res://ui/theme/icons.gd").item(iid), 14)
		c.pressed.connect(func():
			target[iid] = int(target.get(iid, 0)) + step
			c.text = "%s %d" % [hud.data.item_name(iid), int(target[iid])])
		c.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				target.erase(iid)
				c.text = "%s 0" % hud.data.item_name(iid))
		f.add_child(c)
	return f
func _base(id: int) -> String:
	return String(hud.main.sim.bases.name_of(id)) if "bases" in hud.main.sim and hud.main.sim.bases != null else str(id)
