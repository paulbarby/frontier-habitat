extends "res://ui/screens/screen.gd"
## Research: the tech tree by branch rows and tier columns with connection lines. Node
## cards show the state (done, active, queued, available, locked) as a word and a colour;
## tier-5 special research is gold and names its item needs. Click a node to see it on
## the right; Research now makes it active, Queue adds it to the queue.

const TechNode = preload("res://ui/widgets/tech_node.gd")

const NODE_W := 160.0
const NODE_H := 62.0
const COL_GAP := 34.0
const ROW_GAP := 14.0
const LABEL_W := 118.0
const BRANCH_ICON := {"eng": "build", "life": "o2", "agri": "cat_food", "ind": "cat_industry", "energy": "power", "sci": "flask", "space": "ship"}

var selected := ""
var _canvas: Control
var _nodes := {}
var _detail: VBoxContainer
var _queue_row: HBoxContainer
var _rate_label: Label
var _sig := ""
var _row_top := {}      # branch row -> y
var _rows_h := 0.0

class Canvas extends Control:
	var scr
	func _draw() -> void:
		scr.draw_links(self)

func _init() -> void:
	icon = "research"
	accent = P.VIOLET
	title = "Research"
	subtitle = "A research lab with a scientist makes research points (RP). Pick the next project."

func header_extra(row: HBoxContainer) -> void:
	var box: VBoxContainer = Kit.vbox(0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	box.add_child(Kit.head("Research rate", P.TEXT_3, 11))
	_rate_label = Kit.num("", 18, P.VIOLET, true)
	box.add_child(_rate_label)

func build() -> void:
	var d = hud.data
	if not d.research_available():
		content.add_child(Kit.wrap("Research is not available yet.", 15, P.TEXT_2))
		return
	var r: Dictionary = d.research()
	selected = String(r.get("active", ""))
	if selected == "":
		for t in d.techs():
			if d.tech_state(String(t)) == "available":
				selected = String(t)
				break
	var body: HBoxContainer = Kit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	# Tree
	_canvas = Canvas.new()
	_canvas.scr = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	var branches: Dictionary = d.branches()
	_layout_rows(branches, d.techs())
	_canvas.custom_minimum_size = Vector2(LABEL_W + 5.0 * NODE_W + 4.0 * COL_GAP + 12.0, _rows_h + 8.0)
	var sc: ScrollContainer = Kit.scroll(_canvas, true)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(sc)
	# Column heads
	for tier in range(1, 6):
		var h: Label = Kit.head("Tier %d" % tier if tier < 5 else "Tier 5  ·  special", P.GOLD if tier == 5 else P.TEXT_3, 11)
		h.position = Vector2(LABEL_W + float(tier - 1) * (NODE_W + COL_GAP), 4)
		_canvas.add_child(h)
	# Branch labels
	for b in branches:
		var br: Dictionary = branches[b]
		var y: float = _row_y(int(br.get("row", 0)))
		var col := Color(String(br.get("color", "#9FB3C8")))
		var lab: HBoxContainer = Kit.hbox(6)
		lab.position = Vector2(0, y + _row_h(int(br.get("row", 0))) * 0.5 - 10)
		lab.add_child(Kit.icon(String(BRANCH_ICON.get(String(b), "research")), 16, col))
		var l: Label = Kit.label(String(br.get("name", b)), "", 12, P.TEXT_2)
		l.custom_minimum_size.x = LABEL_W - 26
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.add_child(l)
		_canvas.add_child(lab)
	# Nodes (two techs can share a branch and tier: they sit side by side in half widths)
	var slots := {}
	var techs: Dictionary = d.techs()
	for t in techs:
		var k := "%s:%d" % [techs[t].get("branch", ""), int(techs[t].get("tier", 1))]
		slots[k] = int(slots.get(k, 0)) + 1
	var used := {}
	for t in techs:
		var tech: Dictionary = techs[t]
		var br2: String = String(tech.get("branch", "eng"))
		var tier2: int = int(tech.get("tier", 1))
		var k2 := "%s:%d" % [br2, tier2]
		var idx: int = int(used.get(k2, 0))
		used[k2] = idx + 1
		var node = TechNode.new()
		node.setup(d, String(t), String(BRANCH_ICON.get(br2, "research")), Color(String(branches.get(br2, {}).get("color", "#9FB3C8"))))
		node.position = Vector2(LABEL_W + float(tier2 - 1) * (NODE_W + COL_GAP), _row_y(int(branches.get(br2, {}).get("row", 0))) + float(idx) * (NODE_H + 6.0))
		node.size = Vector2(NODE_W, NODE_H)
		node.custom_minimum_size = node.size
		var tid: String = String(t)
		node.pressed.connect(func(): _select(tid))
		node.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
				_research_now(tid))
		_canvas.add_child(node)
		_nodes[tid] = node
	# Detail panel
	var dp: PanelContainer = Kit.panel("CardPanel", false)
	dp.custom_minimum_size.x = 310
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(dp)
	_detail = Kit.vbox(8)
	dp.add_child(Kit.scroll(_detail))
	# Queue strip
	var qp: PanelContainer = Kit.panel("WellPanel", false)
	content.add_child(qp)
	_queue_row = Kit.hbox(8)
	qp.add_child(_queue_row)
	_refresh_all()

## Rows are as tall as the most techs one tier of the branch holds (usually one).
func _layout_rows(branches: Dictionary, techs: Dictionary) -> void:
	var per_row := {}
	var count := {}
	for t in techs:
		var br: String = String(techs[t].get("branch", ""))
		var k := "%s:%d" % [br, int(techs[t].get("tier", 1))]
		count[k] = int(count.get(k, 0)) + 1
		var row: int = int(branches.get(br, {}).get("row", 0))
		per_row[row] = maxi(int(per_row.get(row, 1)), int(count[k]))
	var rows := 0
	for b in branches:
		rows = maxi(rows, int(branches[b].get("row", 0)) + 1)
	var y := 26.0
	_row_top = {}
	for r in rows:
		_row_top[r] = y
		y += float(per_row.get(r, 1)) * (NODE_H + 6.0) - 6.0 + ROW_GAP
	_rows_h = y
	_row_top["n"] = per_row

func _row_y(row: int) -> float:
	return float(_row_top.get(row, 26.0 + float(row) * (NODE_H + ROW_GAP)))

func _row_h(row: int) -> float:
	var per_row: Dictionary = _row_top.get("n", {})
	var n: int = int(per_row.get(row, 1))
	return float(n) * (NODE_H + 6.0) - 6.0

## Curved links from each prerequisite to the techs that need it.
func draw_links(c: Control) -> void:
	var d = hud.data
	var techs: Dictionary = d.techs()
	for t in techs:
		if not _nodes.has(t):
			continue
		var to: Control = _nodes[t]
		for req in techs[t].get("requires", []):
			if not _nodes.has(req):
				continue
			var from: Control = _nodes[req]
			var a := Vector2(from.position.x + from.size.x, from.position.y + from.size.y * 0.5)
			var b := Vector2(to.position.x, to.position.y + to.size.y * 0.5)
			var done: bool = d.tech_done(String(req))
			var col: Color = P.with_alpha(P.GREEN, 0.75) if done else P.with_alpha(P.TEXT_3, 0.55)
			if d.tech_state(String(t)) == "done":
				col = P.with_alpha(P.GREEN, 0.9)
			if selected == String(t) or selected == String(req):
				col = P.VIOLET
			var pts := PackedVector2Array()
			var dx: float = maxf(20.0, (b.x - a.x) * 0.5)
			for i in 17:
				var s: float = float(i) / 16.0
				var p0: Vector2 = a
				var p1: Vector2 = a + Vector2(dx, 0)
				var p2: Vector2 = b - Vector2(dx, 0)
				var p3: Vector2 = b
				var q: Vector2 = p0 * pow(1.0 - s, 3) + p1 * 3.0 * pow(1.0 - s, 2) * s + p2 * 3.0 * (1.0 - s) * s * s + p3 * s * s * s
				pts.append(q)
			c.draw_polyline(pts, col, 2.0 if done else 1.5, true)
			c.draw_circle(b, 3.0, col)

func _select(t: String) -> void:
	selected = t
	_refresh_all()

func _research_now(t: String) -> void:
	var st: String = hud.data.tech_state(t)
	if st == "available" or st == "queued":
		hud.main.submit("research", {"tech": t})
		hud.toast("Research: %s is now the active project." % hud.data.tech_name(t), "research", "research")

func _queue(t: String) -> void:
	var q: Array = (hud.data.research().get("queue", []) as Array).duplicate()
	if not q.has(t):
		q.append(t)
	hud.main.submit("research_queue", {"techs": q})

func _unqueue(t: String) -> void:
	var q: Array = (hud.data.research().get("queue", []) as Array).duplicate()
	q.erase(t)
	hud.main.submit("research_queue", {"techs": q})

func refresh() -> void:
	if _canvas == null:
		return
	var r: Dictionary = hud.data.research()
	var sig := "%s|%s|%s|%s" % [r.get("active", ""), str(r.get("queue", [])), str(r.get("done", {}).keys()), selected]
	if sig != _sig:
		_refresh_all()
	else:
		for t in _nodes:
			_nodes[t].refresh(t == selected)
		_update_rate()

func _update_rate() -> void:
	var d = hud.data
	_rate_label.text = "%s RP/day" % Kit.fmt(d.rp_rate())
	var a: String = String(d.research().get("active", ""))
	if a != "":
		var eta: float = d.tech_eta_seconds(a)
		set_subtitle("Active: %s  ·  %s of %s RP  ·  %s" % [d.tech_name(a), Kit.fmt(d.tech_progress(a)), Kit.fmt(d.tech_cost(a)), ("done in about " + Kit.clock(eta)) if eta >= 0.0 else "no research points are made now"])
	else:
		set_subtitle("No active project. Pick one: click a node, then Research now. Double click works too.")

func _refresh_all() -> void:
	var r: Dictionary = hud.data.research()
	_sig = "%s|%s|%s|%s" % [r.get("active", ""), str(r.get("queue", [])), str(r.get("done", {}).keys()), selected]
	for t in _nodes:
		_nodes[t].refresh(t == selected)
	_canvas.queue_redraw()
	_update_rate()
	_fill_detail()
	_fill_queue()

func _fill_queue() -> void:
	var d = hud.data
	Kit.clear(_queue_row)
	_queue_row.add_child(Kit.icon("queue", 16, P.VIOLET))
	_queue_row.add_child(Kit.head("Queue", P.TEXT_2, 12))
	var r: Dictionary = d.research()
	var a: String = String(r.get("active", ""))
	if a != "":
		_queue_row.add_child(Kit.badge("NOW: " + d.tech_name(a).to_upper(), P.VIOLET))
	var q: Array = r.get("queue", [])
	if q.is_empty():
		_queue_row.add_child(Kit.label("Empty. Queued projects start one after another.", "SmallLabel", 12, P.TEXT_3))
	var n := 1
	for t in q:
		if String(t) == a:
			continue
		var tt: String = String(t)
		var chip: HBoxContainer = Kit.hbox(2)
		chip.add_child(Kit.num("%d." % n, 12, P.TEXT_3))
		chip.add_child(Kit.label(d.tech_name(tt), "", 13, P.TEXT))
		chip.add_child(Kit.icon_button("close", func(): _unqueue(tt), "Remove from the queue", "GhostButton", 11, 22))
		_queue_row.add_child(chip)
		n += 1

func _fill_detail() -> void:
	var d = hud.data
	Kit.clear(_detail)
	if selected == "" or not d.techs().has(selected):
		_detail.add_child(Kit.wrap("Click a project to see what it unlocks.", 14, P.TEXT_2))
		return
	var t: Dictionary = d.techs()[selected]
	var st: String = d.tech_state(selected)
	var special: bool = int(t.get("tier", 1)) >= 5
	var col: Color = P.GOLD if special else P.VIOLET
	_detail.add_child(Kit.head("Tier %d  ·  %s" % [int(t.get("tier", 1)), String(d.branches().get(String(t.get("branch", "")), {}).get("name", ""))], col, 11))
	_detail.add_child(Kit.label(String(t.get("name", selected)).to_upper(), "TitleLabel", 20, P.TEXT))
	var stc: Color = {"done": P.GREEN, "active": P.CYAN, "queued": P.VIOLET, "available": P.CYAN, "locked": P.TEXT_3}.get(st, P.TEXT_3)
	var badges: HBoxContainer = Kit.hbox(6)
	badges.add_child(Kit.badge(st.to_upper(), stc))
	if special:
		badges.add_child(Kit.badge("SPECIAL", P.GOLD))
	_detail.add_child(badges)
	_detail.add_child(Kit.wrap(String(t.get("desc", "")), 14, P.TEXT))
	# Cost and progress
	var cost: float = d.tech_cost(selected)
	var prog: float = d.tech_progress(selected) if st != "done" else cost
	_detail.add_child(Kit.bar_row("Progress", prog / maxf(1.0, cost), "%s/%s" % [Kit.fmt(prog), Kit.fmt(cost)], col, 64.0))
	if st == "active":
		var eta: float = d.tech_eta_seconds(selected)
		_detail.add_child(Kit.label("Done in about %s at %s RP/day." % [Kit.clock(eta), Kit.fmt(d.rp_rate())] if eta >= 0.0 else "No research points are made now. A research lab needs a scientist.", "SmallLabel", 12, P.TEXT_2))
	# Special items
	var items: Dictionary = t.get("items", {})
	if not items.is_empty():
		var paid: bool = d.research().get("paid", {}).has(selected)
		_detail.add_child(Kit.head("Delivered to a research lab first", P.GOLD, 11))
		var f := HFlowContainer.new()
		f.add_theme_constant_override("h_separation", 10)
		for it in items:
			var have: int = d.total_of(String(it))
			f.add_child(Kit.chip(Icons.item(String(it)), "%d" % int(items[it]), d.item_color(String(it)), "%s: %d in the colony" % [d.item_name(String(it)), have], paid or have >= int(items[it]), 16))
		_detail.add_child(f)
		_detail.add_child(Kit.label("Delivered." if paid else "Not delivered yet. Carriers bring them when the project is active.", "SmallLabel", 12, P.GREEN if paid else P.AMBER))
	# Requirements
	var req: Array = t.get("requires", [])
	if not req.is_empty():
		_detail.add_child(Kit.head("Needs", P.TEXT_2, 11))
		for q in req:
			var ok: bool = d.tech_done(String(q))
			var row: HBoxContainer = Kit.hbox(6)
			row.add_child(Kit.icon("sev_ok" if ok else "lock", 14, P.GREEN if ok else P.AMBER))
			var qq: String = String(q)
			var lb: Button = Kit.button(d.tech_name(qq), func(): _select(qq), "", "ListButton")
			lb.custom_minimum_size.y = 24
			row.add_child(lb)
			_detail.add_child(row)
	# Unlocks
	var un: Array = _unlock_lines(t)
	if not un.is_empty():
		_detail.add_child(Kit.head("Unlocks", P.TEXT_2, 11))
		for u in un:
			var row2: HBoxContainer = Kit.hbox(8)
			row2.add_child(Kit.icon(u[0], 16, u[2]))
			row2.add_child(Kit.wrap(u[1], 13, P.TEXT))
			_detail.add_child(row2)
	# Actions
	_detail.add_child(Kit.gap(0, 4))
	if st == "available" or st == "queued":
		var now: Button = Kit.button("Research now", func(): _research_now(selected), "Research now\nMakes it the active project. The current project keeps its points.", "PrimaryButton", "research", 16)
		_detail.add_child(now)
	if st == "available":
		_detail.add_child(Kit.button("Add to queue", func(): _queue(selected), "Queue\nStarts after the projects before it.", "", "queue", 16))
	elif st == "queued":
		_detail.add_child(Kit.button("Remove from queue", func(): _unqueue(selected), "", "", "close", 14))
	elif st == "locked":
		_detail.add_child(Kit.label("Finish the projects it needs first.", "SmallLabel", 12, P.AMBER))

func _unlock_lines(t: Dictionary) -> Array:
	var d = hud.data
	var out: Array = []
	var un: Dictionary = t.get("unlocks", {})
	for b in un.get("buildings", []):
		var bd: Dictionary = d.bdef(String(b))
		out.append([String(load("res://ui/widgets/build_card.gd").GLYPH.get(String(b), "build")), "Structure: %s" % String(bd.get("name", b)), P.cat(String(bd.get("category", "logistics")))])
	for c in un.get("crops", []):
		out.append([String(c), "Crop: %s" % d.item_name(String(c)), d.item_color(String(c))])
	for r in un.get("recipes", []):
		out.append(["list", "Recipe: %s" % String(d.recipes().get(String(r), {}).get("name", r)), P.CATEGORY["industry"]])
	for s in un.get("sizes", []):
		out.append(["size", "Size %s for every structure" % d.SIZE_NAMES[clampi(int(s), 0, 3)], P.CYAN])
	for l in un.get("levels", []):
		out.append(["upgrade", "Upgrades to level %d" % int(l), P.VIOLET])
	for x in un.get("ship", []):
		out.append(["ship", "The Meridian can fly %s" % String(x).replace("_", " ") + "s", P.CATEGORY["space"]])
	var bonus: Dictionary = t.get("bonus", {})
	for k in bonus:
		out.append(["trend_up", "%s +%d%%" % [String(k).replace("_mult", "").replace("_", " ").capitalize(), int(roundf(float(bonus[k]) * 100.0))], P.GREEN])
	var fams: Array = t.get("families", [])
	if String(t.get("family", "")) != "" and fams.is_empty():
		fams = [t["family"]]
	for f in fams:
		out.append(["level", "Level 5 for the %s family" % String(f), P.GOLD])
	return out
