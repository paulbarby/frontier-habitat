extends "res://ui/screens/screen.gd"
## Colonists: every colonist with role, health, morale, nutrition, what they do and where.
## Click a row to select the colonist and move the camera there. Immigration settings
## (open, roles, cap) when the simulation has them.
## Tab Visitors (version 3.1): people from visiting ships, with kind, ship, time left, what they
## paid, what they do and where. Visitors are not in the colonist list.

var _rows := {}
var _vrows := {}
var _clock := 0
var _sort := "name"
## Paul, 2026-10-01: "scaling the UI should not cause UI elements to be hidden". Each column has
## its width at 100 % and the least width it may shrink to: [title, full, least, sort key].
## fit_view() shrinks every column (and the Settlers card) together when the area is narrower
## than the full widths; text cells cut with "..." and carry the full text as a tooltip.
const COLS := [["Name", 214, 150, "name"], ["Role", 110, 88, "role"], ["Health", 110, 96, "health"], ["Morale", 110, 96, "morale"],
	["Nutrition", 110, 96, "nutrition"], ["Dose", 84, 66, "dose"], ["Doing", 198, 110, ""], ["Where", 150, 84, ""]]
const VCOLS := [["Name", 214, 150], ["Kind", 110, 88], ["Ship", 190, 130], ["Leaves in", 90, 78], ["Paid", 70, 56], ["Health", 80, 64], ["Doing", 240, 130], ["Where", 160, 90]]
const SIDE_W := [300.0, 230.0]   # the Settlers card: full, least
var _k := 0.0                    # 0 = full widths, 1 = least widths
var _col_ctl: Array = []         # [Control, full width, least width]

func _init() -> void:
	icon = "colonists"
	title = "Colonists"
	tabs = [["colonists", "Colonists", "colonists"], ["priorities", "Priorities", "orders"], ["visitors", "Visitors", "people"]]

func _ready() -> void:
	if typeof(arg) == TYPE_STRING and String(arg) == "visitors":
		tab = "visitors"
	super._ready()

func build_tab(id: String, box: VBoxContainer) -> void:
	_rows = {}
	_vrows = {}
	_col_ctl = []
	if id == "visitors":
		_visitors(box)
	elif id == "priorities":
		_priorities(box)
	else:
		_colonists(box)

func _colonists(box: VBoxContainer) -> void:
	var s = hud.main.sim
	var d = hud.data
	# Summary line
	var alive: Array = []
	for aid in s.state["agents"]:
		if s.state["agents"][aid]["state"] == "alive" and not hud.data.is_visitor(s.state["agents"][aid]):
			alive.append(aid)
	var roles := {}
	for aid in alive:
		var r: String = String(s.state["agents"][aid]["role"])
		roles[r] = int(roles.get(r, 0)) + 1
	var parts: Array = []
	for r in s.bal.get("roles", roles.keys()):
		if roles.has(r):
			parts.append("%d %s" % [roles[r], String(s.bal["role_names"].get(r, r)).to_lower() + ("s" if int(roles[r]) != 1 else "")])
	set_subtitle("%s  ·  %s  ·  %s" % [Kit.plural(alive.size(), "colonist"), ", ".join(parts), Kit.plural(int(s.state["progress"].get("deaths", 0)), "death")])
	var body: HBoxContainer = Kit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var left: VBoxContainer = Kit.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var head: HBoxContainer = Kit.hbox(10)
	# Dose (SIM milestone 6): mSv, amber from 250, red from 750; sort puts the highest first.
	for c in COLS:
		var key: String = c[3]
		if key != "":
			var b: Button = Kit.button(String(c[0]).to_upper(), func():
				_sort = key
				_fill(), "Sort by %s" % String(c[0]).to_lower(), "GhostButton")
			b.custom_minimum_size.y = 26
			b.clip_text = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 11)
			head.add_child(_sized(b, c[1], c[2]))
		else:
			head.add_child(_sized(Kit.head(c[0], P.TEXT_3, 10), c[1], c[2]))
	left.add_child(head)
	var list: VBoxContainer = Kit.seam_list(2)   # v4: rows with seams in a darker well
	list.name = "List"
	left.add_child(Kit.well_scroll(list))
	# Immigration
	var im: Dictionary = s.state.get("policies", {}).get("immigration", {})
	var right: VBoxContainer = card("Settlers", "people", P.CYAN)
	var rp: PanelContainer = card_panel(right)
	body.add_child(_sized(rp, SIDE_W[0], SIDE_W[1]))
	if im.is_empty():
		right.add_child(Kit.wrap("Settler settings are not available yet.", 13, P.TEXT_3))
	else:
		var open := CheckButton.new()
		open.text = "Settlers may come"
		open.tooltip_text = "Settlers may come\nThe shuttle brings new colonists when the colony has free beds, air and food."
		open.button_pressed = bool(im.get("open", true))
		open.focus_mode = Control.FOCUS_NONE
		open.toggled.connect(func(on): _immigration({"open": on}))
		right.add_child(open)
		right.add_child(Kit.dim("Roles that may come", 12))
		var allowed: Array = im.get("roles", [])
		for r in s.bal.get("roles", []):
			var rr: String = String(r)
			var cb := CheckBox.new()
			cb.text = String(s.bal["role_names"].get(rr, rr))
			cb.tooltip_text = "%s\nSettlers of this role may come on the shuttle." % cb.text
			cb.button_pressed = allowed.has(rr)
			cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(func(on):
				var cur: Array = (hud.main.sim.state["policies"]["immigration"].get("roles", []) as Array).duplicate()
				if on and not cur.has(rr):
					cur.append(rr)
				elif not on:
					cur.erase(rr)
				_immigration({"roles": cur}))
			right.add_child(cb)
		var caprow: HBoxContainer = Kit.hbox(8)
		caprow.add_child(Kit.dim("Most colonists", 12))
		var cap := SpinBox.new()
		cap.tooltip_text = "Most colonists\nNo more settlers come when the colony has this many colonists."
		cap.get_line_edit().tooltip_text = cap.tooltip_text
		cap.min_value = 8
		cap.max_value = 200
		cap.step = 1
		cap.value = float(im.get("cap", 100))
		cap.value_changed.connect(func(v): _immigration({"cap": int(v)}))
		caprow.add_child(cap)
		right.add_child(caprow)
	right.add_child(Kit.wrap("Settlers need beds, air and food. The Meridian's supply runs bring them when the colony has room.", 12, P.TEXT_2))
	_fill()

func _immigration(change: Dictionary) -> void:
	var im: Dictionary = (hud.main.sim.state["policies"].get("immigration", {}) as Dictionary).duplicate(true)
	for k in change:
		im[k] = change[k]
	hud.main.submit("set_immigration", {"roles": im.get("roles", []), "cap": int(im.get("cap", 100)), "open": bool(im.get("open", true))})

func _fill() -> void:
	var list: VBoxContainer = find_child("List", true, false)
	if list == null:
		return
	Kit.clear(list)
	_rows = {}
	_col_ctl = _col_ctl.filter(func(e): return is_instance_valid(e[0]) and not (e[0] as Node).is_queued_for_deletion())   # drop the old rows
	var s = hud.main.sim
	var d = hud.data
	var ids: Array = []
	for aid in s.state["agents"]:
		if s.state["agents"][aid]["state"] == "alive" and not d.is_visitor(s.state["agents"][aid]):
			ids.append(aid)
	ids.sort_custom(func(a, b): return _less(a, b))
	for aid in ids:
		var a: Dictionary = s.state["agents"][aid]
		var id: int = aid
		var b: Button = Kit.button("", func():
			host.close(self)
			hud.main.select("agent", id)
			hud.main.focus_on(hud.main.sim.state["agents"][id]["pos"]), "%s\nClick: close this screen, select the colonist and move the camera there." % String(s.state["agents"][aid]["name"]), "ListButton")
		b.custom_minimum_size.y = 34
		var h: HBoxContainer = Kit.hbox(10)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 8
		b.add_child(h)
		var nb: HBoxContainer = Kit.hbox(8)
		nb.add_child(Kit.icon(load("res://ui/theme/icons.gd").role(String(a["role"])), 18, P.ROLE.get(a["role"], P.CYAN)))
		nb.add_child(_cut_name(Kit.label(String(a["name"]), "", 14, P.TEXT)))
		h.add_child(_sized(nb, COLS[0][1] - 4, COLS[0][2] - 4))
		var rl: Label = _cut(Kit.label(String(s.bal["role_names"].get(a["role"], a["role"])), "", 13, P.TEXT_2))
		h.add_child(_sized(rl, COLS[1][1], COLS[1][2]))
		var hb: HBoxContainer = _bar(h)
		var mb: HBoxContainer = _bar(h)
		var nbar: HBoxContainer = _bar(h)
		var dose: Label = Kit.num("", 13, P.TEXT_2)
		dose.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(_sized(dose, COLS[5][1], COLS[5][2]))
		var doing: Label = _cut(Kit.label("", "", 13, P.TEXT))   # 260 before v4: the metal band and the dose column take the rest
		h.add_child(_sized(doing, COLS[6][1], COLS[6][2]))
		var where: Label = _cut(Kit.label("", "SmallLabel", 12, P.TEXT_2))
		h.add_child(_sized(where, COLS[7][1], COLS[7][2]))
		list.add_child(b)
		_rows[id] = {"h": hb, "m": mb, "n": nbar, "dose": dose, "doing": doing, "where": where}
	_update()

func _less(a: int, b: int) -> bool:
	var s = hud.main.sim
	var x: Dictionary = s.state["agents"][a]
	var y: Dictionary = s.state["agents"][b]
	match _sort:
		"role":
			return String(x["role"]) < String(y["role"]) if x["role"] != y["role"] else String(x["name"]) < String(y["name"])
		"health":
			return float(x["health"]) < float(y["health"])
		"morale":
			return float(x["morale"]) < float(y["morale"])
		"nutrition":
			return hud.data.agent_nutrition_score(x) < hud.data.agent_nutrition_score(y)
		"dose":
			return float(x.get("dose", 0.0)) > float(y.get("dose", 0.0))
	return String(x["name"]) < String(y["name"])

func _bar(h: HBoxContainer) -> HBoxContainer:
	var r: HBoxContainer = Kit.hbox(6)
	_sized(r, 110, 96)
	var b = Kit.bar(0.0, P.GREEN, 6.0)
	r.add_child(_sized(b, 72, 58))
	var n: Label = Kit.num("", 12, P.TEXT)
	r.add_child(n)
	h.add_child(r)
	return r

func _set_bar(r: HBoxContainer, v: float, warn: float = 50.0, bad: float = 25.0) -> void:
	if v < 0.0:
		r.get_child(0).value = 0.0
		(r.get_child(1) as Label).text = "-"
		return
	r.get_child(0).value = v / 100.0
	r.get_child(0).color = P.level(v, warn, bad)
	(r.get_child(1) as Label).text = "%d" % int(v)

func refresh() -> void:
	_clock += 1
	if _clock % 3 == 0:
		_update()
		_update_visitors()

func _update() -> void:
	var s = hud.main.sim
	for id in _rows:
		var a: Dictionary = s.state["agents"].get(id, {})
		if a.is_empty():
			continue
		var r: Dictionary = _rows[id]
		_set_bar(r["h"], float(a["health"]))
		_set_bar(r["m"], float(a["morale"]))
		_set_bar(r["n"], hud.data.agent_nutrition_score(a), 70.0, 40.0)
		var dv: float = float(a.get("dose", 0.0))
		var dlv: Array = hud.v4.dose_level(dv)
		(r["dose"] as Label).text = "%d mSv" % int(dv) if dv >= 0.5 else "0"
		(r["dose"] as Label).add_theme_color_override("font_color", dlv[1] if String(dlv[0]) != "" else P.TEXT_2)
		(r["dose"] as Label).tooltip_text = "Radiation dose\n%d mSv%s. High from 250, dangerous from 750, sickness above 1,000." % [int(dv), (": " + String(dlv[0]).to_lower()) if String(dlv[0]) != "" else ""]
		(r["doing"] as Label).text = String(a.get("goal", ""))
		(r["doing"] as Label).tooltip_text = (r["doing"] as Label).text   # full text when the cell cuts it
		var where: String = "Outside" if a["where"] == "out" else String(s.state["buildings"].get(a["bld"], {}).get("name", "a room"))
		(r["where"] as Label).text = where
		(r["where"] as Label).tooltip_text = where

# ---------------------------------------------------------------- visitors (version 3.1)
func _visitors(box: VBoxContainer) -> void:
	var s = hud.main.sim
	var d = hud.data
	var ids: Array = []
	for aid in s.state["agents"]:
		var a: Dictionary = s.state["agents"][aid]
		if a["state"] == "alive" and d.is_visitor(a):
			ids.append(aid)
	set_subtitle("%s from visiting ships  ·  credits %d" % [Kit.plural(ids.size(), "visitor"), d.credits()])
	var head: HBoxContainer = Kit.hbox(10)
	for c in VCOLS:
		head.add_child(_sized(Kit.head(c[0], P.TEXT_3, 10), c[1], c[2]))
	box.add_child(head)
	var list: VBoxContainer = Kit.seam_list(2)
	box.add_child(Kit.well_scroll(list))
	if ids.is_empty():
		list.add_child(Kit.wrap("No visitors now. Tourist liners, medical and science ships and inspectors bring them. The traffic panel shows the next ships.", 14, P.TEXT_2))
		return
	ids.sort()
	for aid in ids:
		var a: Dictionary = s.state["agents"][aid]
		var id: int = aid
		var b: Button = Kit.button("", func():
			host.close(self)
			hud.main.select("agent", id)
			hud.main.focus_on(hud.main.sim.state["agents"][id]["pos"]), "%s\nClick: close this screen, select the colonist and move the camera there." % String(s.state["agents"][aid]["name"]), "ListButton")
		b.custom_minimum_size.y = 34
		var h: HBoxContainer = Kit.hbox(10)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 8
		b.add_child(h)
		var vk: String = String(a.get("vkind", ""))
		var nb: HBoxContainer = Kit.hbox(8)
		nb.add_child(Kit.icon(d.ship_icon(vk), 18, P.GOLD))
		nb.add_child(_cut_name(Kit.label(String(a["name"]), "", 14, P.TEXT)))
		h.add_child(_sized(nb, VCOLS[0][1] - 4, VCOLS[0][2] - 4))
		var cells: Array = []
		for ci in range(1, VCOLS.size()):
			var l2: Label = _cut(Kit.label("", "", 13, P.TEXT_2))
			h.add_child(_sized(l2, VCOLS[ci][1], VCOLS[ci][2]))
			cells.append(l2)
		(cells[0] as Label).text = String(d.ship_kind(vk).get("vname", vk.capitalize()))
		list.add_child(b)
		_vrows[id] = cells
	_update_visitors()

func _update_visitors() -> void:
	var s = hud.main.sim
	var d = hud.data
	for id in _vrows:
		var a: Dictionary = s.state["agents"].get(id, {})
		if a.is_empty():
			continue
		var cells: Array = _vrows[id]
		var info: Dictionary = visitor_info(hud, a)
		(cells[1] as Label).text = String(info["ship"])
		(cells[2] as Label).text = String(info["leaves"])
		(cells[3] as Label).text = "%d" % int(info["paid"])
		(cells[4] as Label).text = "%d" % int(float(a.get("health", 100.0)))
		(cells[5] as Label).text = String(a.get("goal", ""))
		(cells[6] as Label).text = "Outside" if a["where"] == "out" else String(s.state["buildings"].get(a.get("bld", -1), {}).get("name", "a room"))
		for cl in cells:
			(cl as Label).tooltip_text = (cl as Label).text

## Paul, 2026-10-01: sets a column control to the width of now (between full and least) and
## keeps it, so fit_view() can change it when the area changes.
func _sized(c: Control, full: float, least: float) -> Control:
	c.custom_minimum_size.x = lerpf(full, least, _k)
	_col_ctl.append([c, full, least])
	return c

## A text cell that cuts with "..." when its column is narrow; the tooltip has the full text.
## (No expand flag: the cells keep the header's column widths.)
static func _cut(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	if l.tooltip_text == "":
		l.tooltip_text = l.text
	return l

## The name in a row: fills the name cell and cuts; the row button's tooltip has the full name.
static func _cut_name(l: Label) -> Label:
	_cut(l)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Paul, 2026-10-01: the columns (and the Settlers card) shrink together, just enough for the
## area of this view. The area does not follow the content (it is the screen's scroll area), so
## this does not feed back. Steps of 5 % keep a drag-resize from resizing every frame.
func fit_view(vp: Vector2) -> void:
	super.fit_view(vp)
	if tab == "priorities" or _scroll == null or _scroll.size.x <= 0.0 or _col_ctl.is_empty():
		return
	var cols: Array = VCOLS if tab == "visitors" else COLS
	var full: float = 10.0 * float(cols.size() - 1)
	var least: float = full
	for c in cols:
		full += float(c[1])
		least += float(c[2])
	if tab != "visitors":
		full += 16.0 + SIDE_W[0]
		least += 16.0 + SIDE_W[1]
	var k: float = clampf((full - (_scroll.size.x - 6.0)) / (full - least), 0.0, 1.0)
	k = ceilf(k * 20.0 - 0.001) / 20.0
	if is_equal_approx(k, _k):
		return
	_k = k
	for e in _col_ctl:
		if is_instance_valid(e[0]):
			(e[0] as Control).custom_minimum_size.x = lerpf(float(e[1]), float(e[2]), _k)

## {ship, leaves, paid} of a visitor, in words (also used by the inspector card).
static func visitor_info(h, a: Dictionary) -> Dictionary:
	var d = h.data
	var sid: int = int(a.get("ship", -1))
	var row: Dictionary = d.traffic_row(sid) if sid >= 0 else {}
	var ship: String = "left behind: waits for the next ship" if sid < 0 else (String(row.get("name", "ship %d" % sid)) + (" (%s)" % String(d.SHIP_PHASE.get(String(row.get("phase", "")), "")).to_lower() if not row.is_empty() else ""))
	var leaves := "-"
	if not row.is_empty():
		match String(row.get("phase", "")):
			"landed": leaves = Kit.clock(float(row.get("t_s", 0.0)))
			"boarding": leaves = "boarding"
			"takeoff": leaves = "now"
	return {"ship": ship, "leaves": leaves, "paid": int(a.get("visit", {}).get("paid", 0))}

# ---------------------------------------------------------------- job priorities (version 4, SIM milestone 4)
## One row per colonist, one column per job category (SIM: construction, food, industry, logistics,
## repair): 3 = first, 2 = normal, 1 = last, – = not allowed. A cell in grey follows the colony
## priority; a bright one is the colonist's own. Click a cell to step 3 → 2 → 1 → – → 3 (SIM
## set_jobs); Colony on the row goes back to the colony priorities (set_jobs clear).
## Critic round 22: the Priorities tab is sized to its content (the other tabs fill the view).
func fits_content() -> bool:
	return tab == "priorities"

func _priorities(box: VBoxContainer) -> void:
	var v4 = hud.v4
	if not v4.available("orders"):
		box.add_child(Kit.wrap("Job priorities are not available in this game.", 15, P.TEXT_2))
		return
	box.add_child(Kit.wrap("Click a cell: 3 = does this first, 2 = normal, 1 = last, – = never. Grey = the colony priority; bright = this colonist's own. Thirst, hunger, exhaustion and orders still come first.", 14, P.TEXT_2, 900.0))
	var cats: Array = v4.job_categories()
	var head: HBoxContainer = Kit.hbox(6)
	var nl: Label = Kit.head("Colonist", P.TEXT_2, 11)
	nl.custom_minimum_size.x = 214
	head.add_child(nl)
	for j in cats:
		var jl: Label = Kit.head(v4.job_name(String(j)), P.TEXT_2, 11)
		jl.custom_minimum_size.x = 110
		jl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(jl)
	box.add_child(Kit.margin(head, 8, 0, 0, 0))
	var list: VBoxContainer = Kit.seam_list(2)
	var pwell: PanelContainer = Kit.well_scroll(list)
	box.add_child(pwell)
	(func(): if is_instance_valid(pwell): fit_scroll(pwell, 600.0)).call_deferred()
	var s = hud.main.sim
	var ids: Array = []
	for aid in s.state["agents"]:
		var a: Dictionary = s.state["agents"][aid]
		if String(a.get("state", "")) == "alive" and not hud.data.is_visitor(a):
			ids.append(int(aid))
	ids.sort_custom(func(x, y): return String(s.state["agents"][x]["name"]).naturalnocasecmp_to(String(s.state["agents"][y]["name"])) < 0)
	for aid in ids:
		var a: Dictionary = s.state["agents"][aid]
		var row: HBoxContainer = Kit.hbox(6)
		var nh: HBoxContainer = Kit.hbox(6)
		nh.custom_minimum_size.x = 214
		var role: String = String(a.get("role", ""))
		nh.add_child(Kit.icon(Icons.role(role), 14, P.ROLE.get(role, P.CYAN)))
		var nm: Label = Kit.label(String(a["name"]), "", 13, P.TEXT)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.tooltip_text = "%s\n%s" % [String(a["name"]), String(s.bal["role_names"].get(role, role))]
		nm.mouse_filter = Control.MOUSE_FILTER_PASS
		nh.add_child(nm)
		row.add_child(nh)
		var cells: Array = []
		for j in cats:
			var jj: String = String(j)
			var id2: int = aid
			var c: Button = Kit.button("", Callable(), "%s: %s\nClick: 3 first, 2 normal, 1 last, – never." % [String(a["name"]), v4.job_name(jj)], "ChipButton")
			c.custom_minimum_size = Vector2(110, 26)
			c.set_meta("job", jj)
			c.pressed.connect(func():
				var cur: int = v4.priority(id2, jj)
				var nxt: int = {3: 2, 2: 1, 1: 0, 0: 3}.get(cur, 2)
				v4.command("set_priority", {"agent": id2, "job": jj, "value": nxt})
				_prio_cells(id2, cells))
			row.add_child(c)
			cells.append(c)
		var rid: int = aid
		row.add_child(Kit.button("Colony", func():
			v4.command("reset_priority", {"agent": rid})
			_prio_cells(rid, cells), "Colony priorities\nThis colonist follows the colony priorities again.", "GhostButton", "", 14))
		_prio_cells(aid, cells)
		list.add_child(row)

func _prio_cells(aid: int, cells: Array) -> void:
	var v4 = hud.v4
	for c in cells:
		var j: String = String((c as Button).get_meta("job"))
		var v: int = v4.priority(aid, j)
		(c as Button).text = _prio_text(v)
		var own: bool = v4.is_own(aid, j)
		(c as Button).add_theme_color_override("font_color", P.TEXT if own else P.TEXT_3)

static func _prio_text(v: int) -> String:
	return "–" if v <= 0 else str(v)