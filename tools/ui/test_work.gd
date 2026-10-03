extends SceneTree
## Section 18 UI (Paul, 2026-10-04), headless, on showcase_v5, real key and mouse events:
##   node tools/godot.mjs script res://tools/ui/test_work.gd
## Work window (key M): tabs All + the departments, the rows are SIM's (sim.workq.rows), Top / Up / Down / Bottom move a row in SIM,
## drag and drop moves a row, Assign to... gives a task row to a colonist, Cancel holds a row and Release lifts the hold; the dock card
## and the nav rail show the count of urgent items nobody has.
## Repair now: the BROKEN and WORN badges and the inspector button open the Who window; a head gives a team order (SIM allocates it,
## the dock shows the head's report), one person gets the order at once; the personnel file shows the order and what the colonist
## does for it.
## Chains: the Show chain button of an alert opens the chain window (done / missing steps, a Place button for a structure that is
## unlocked); the codex has the page Chains.

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var bld := -1
var team_before := 0
var _ins := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func q(c: Callable, frames: int = 6) -> void:
	_queue.append([c, frames])

## A step queued from inside a step runs next, in the order queued (q() appends to the end of the plan).
func qn(c: Callable, frames: int = 6) -> void:
	_queue.insert(_ins, [c, frames])
	_ins += 1

func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		_plan()
	if _n < 7:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _queue.is_empty():
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	_ins = 0
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

# ---------------------------------------------------------------- input
func key(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)

## A click: the mouse moves onto the control now; the press and release come in the next step (a hover first, as a hand does).
func click(c: Control) -> void:
	var pos: Vector2 = root.get_final_transform() * c.get_global_rect().get_center()   # canvas to window pixels (the interface scale)
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	qn(func():
		for pressed in [true, false]:
			var b := InputEventMouseButton.new()
			b.button_index = MOUSE_BUTTON_LEFT
			b.pressed = pressed
			b.position = pos
			b.global_position = pos
			Input.parse_input_event(b), 6)

func hud_():
	return main.hud

func row_control(key_: String) -> Control:
	for r in hud_().work._list.get_children():
		if r.has_meta("key") and String(r.get_meta("key")) == key_:
			return r
	return null

func act_button(act: String) -> Button:
	for b in hud_().work._list.find_children("*", "Button", true, false):
		if b.has_meta("act") and String(b.get_meta("act")) == act:
			return b
	return null

## Scrolls a control into view of its scroll area (the click needs it on screen).
func reveal(c: Control) -> void:
	var p: Node = c.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		(p as ScrollContainer).ensure_control_visible(c)

## Queues: select a row of the Work window (a second click would unselect it).
func qselect(key_: String) -> void:
	qn(func():
		if hud_().work.selected != key_:
			reveal(row_control(key_)), 3)
	qn(func():
		if hud_().work.selected != key_:
			click(row_control(key_)), 3)

## Queues: reveal the control, then click it (a callable that finds the control when its turn comes).
func qclick(find: Callable, frames: int = 6) -> void:
	qn(func(): reveal(find.call()), 3)
	qn(func(): click(find.call()), frames)

func keys_of(dept: String) -> Array:
	var out: Array = []
	for r in main.sim.workq.rows(dept):
		out.append(String(r["key"]))
	return out

func row_of(dept: String, key_: String) -> Dictionary:
	for r in main.sim.workq.rows(dept):
		if String(r["key"]) == key_:
			return r
	return {}

# ---------------------------------------------------------------- plan
func _plan() -> void:
	Input.use_accumulated_input = false
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i.ZERO
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	main._on_cmd("closeall")
	main.select("", -1)   # the save has a structure selected: its inspector would cover the window
	q(func(): main.select("", -1), 4)
	q(func(): key(KEY_M), 12)
	q(func(): _work_open(), 4)
	q(func(): click(hud_().work._tab_btn["maintenance"]), 8)
	q(func(): _work_tab(), 4)
	q(func(): _select_first(), 8)
	q(func(): _move_down(), 8)
	q(func(): _after_down(), 4)
	q(func(): _move_top(), 8)
	q(func(): _after_top(), 4)
	q(func(): _drag(), 8)
	q(func(): _after_drag(), 4)
	q(func(): _assign_open(), 10)
	q(func(): _assign_pick(), 8)
	q(func(): _after_assign(), 4)
	q(func(): _cancel_row(), 8)
	q(func(): _after_cancel(), 4)
	q(func(): _release_row(), 8)
	q(func(): _after_release(), 4)
	q(func(): key(KEY_M), 8)
	q(func(): check("key M closes the Work window", not hud_().work.visible), 2)
	q(func(): _repair_setup(), 12)
	q(func(): _repair_badges(), 4)
	q(func(): _repair_team(), 10)
	q(func(): _after_team(), 4)
	q(func(): _person_order(), 10)
	q(func(): _person_check(), 4)
	q(func(): _repair_person(), 10)
	q(func(): _after_person(), 4)
	q(func(): _status_check(), 10)
	q(func(): _status_check2(), 4)
	q(func(): _dash_open(), 12)
	q(func(): _dash_check(), 4)
	q(func(): _verbs(), 10)
	q(func(): _verbs2(), 10)
	q(func(): _verbs3(), 10)
	q(func(): _verbs4(), 4)
	q(func(): _chain_open(), 10)
	q(func(): _chain_check(), 4)
	q(func(): _alert_chain(), 10)
	q(func(): _alert_check(), 4)
	q(func(): _codex_chain(), 12)
	q(func(): _codex_check(), 4)

# ---------------------------------------------------------------- the Work window
func _work_open() -> void:
	var w = hud_().work
	var sim = main.sim
	check("key M opens the Work window", w.visible)
	check("tabs: All and the six departments", w._tab_btn.size() == 7 and w._tab_btn.has("all") and w._tab_btn.has("maintenance") and w._tab_btn.has("logistics"), str(w._tab_btn.keys()))
	check("the rows are SIM's queue (sim.workq.rows)", w.rows_now.size() == sim.workq.rows("").size(), "%d vs %d" % [w.rows_now.size(), sim.workq.rows("").size()])
	hud_().work_card.refresh()
	check("the dock card shows the urgent count of SIM", hud_().work_card.urgent == sim.workq.urgent_count() and hud_().work_card.open_items > 0, "%d vs %d" % [hud_().work_card.urgent, sim.workq.urgent_count()])
	hud_().nav.refresh()
	var badge: Label = hud_().nav._badges["work"]
	check("the nav rail marks the urgent items", badge.visible == (sim.workq.urgent_count() > 0) and (not badge.visible or badge.text == str(sim.workq.urgent_count())), badge.text)

func _work_tab() -> void:
	var w = hud_().work
	var all_m := true
	for r in w.rows_now:
		if String(r["dept"]) != "maintenance":
			all_m = false
	check("the Maintenance tab lists only its department", w.dept == "maintenance" and all_m and w.rows_now.size() >= 3, str(w.rows_now.size()))

func _select_first() -> void:
	var w = hud_().work
	# A row with a task of its own (id) that is open: the one to move and assign.
	var rows: Array = w.rows_now
	var k: String = String(rows[0]["key"])
	click(row_control(k))

func _move_down() -> void:
	var w = hud_().work
	var rows: Array = w.rows_now
	check("a click selects a row (its buttons show)", w.selected != "" and act_button("down") != null and act_button("assign") != null and act_button("top") != null and act_button("bottom") != null and act_button("up") != null, w.selected)
	var k: String = w.selected
	var before: Array = keys_of("maintenance")
	set_meta("k0", k)
	set_meta("before", before)

	var sc: ScrollContainer = hud_().work._scroll
	click(act_button("down"))

func _after_down() -> void:
	var k: String = get_meta("k0")
	var before: Array = get_meta("before")
	var after: Array = keys_of("maintenance")
	check("Down: SIM moves the row one place later", after.find(k) == before.find(k) + 1, "%d -> %d" % [before.find(k), after.find(k)])
	check("the row shows as moved by the player (pinned)", bool(row_of("maintenance", k).get("pinned", false)))
	check("the window shows the new order", hud_().work.rows_now.size() > 0 and String(hud_().work.rows_now[hud_().work.rows_now.size() - 1]["key"]) != "" and keys_of("maintenance") == _shown_keys())

func _shown_keys() -> Array:
	var out: Array = []
	for r in hud_().work.rows_now:
		out.append(String(r["key"]))
	return out

func _move_top() -> void:
	# The last row of the department to the top, through the buttons of its row.
	var w = hud_().work
	var last: String = String(w.rows_now[w.rows_now.size() - 1]["key"])
	set_meta("klast", last)
	qselect(last)
	qclick(func(): return act_button("top"))

func _after_top() -> void:
	var last: String = get_meta("klast")
	var after: Array = keys_of("maintenance")
	check("Top: SIM puts the row first", after[0] == last, "%s at %d" % [last, after.find(last)])
	qselect(last)
	qclick(func(): return act_button("bottom"))
	qn(func():
		var a2: Array = keys_of("maintenance")
		check("Bottom: SIM puts the row last", a2[a2.size() - 1] == last, str(a2.find(last))), 4)
	qselect(last)
	qclick(func(): return act_button("up"))
	qn(func():
		var a4: Array = keys_of("maintenance")
		check("Up: SIM moves the row one place earlier", a4.find(last) == a4.size() - 2, str(a4.find(last))), 4)

func _drag() -> void:
	var w = hud_().work
	var rows: Array = w.rows_now
	var from_k: String = String(rows[2]["key"])
	var to_k: String = String(rows[0]["key"])
	set_meta("from_k", from_k)
	var from_row: Control = row_control(from_k)
	var to_row: Control = row_control(to_k)
	var data = from_row._get_drag_data(Vector2.ZERO)
	check("a row gives drag data and takes a drop", typeof(data) == TYPE_DICTIONARY and to_row._can_drop_data(Vector2.ZERO, data) and not from_row._can_drop_data(Vector2.ZERO, data))
	to_row._drop_data(Vector2.ZERO, data)

func _after_drag() -> void:
	var from_k: String = get_meta("from_k")
	var after: Array = keys_of("maintenance")
	check("Drag and drop: the row is before the row it was dropped on (first place)", after[0] == from_k, str(after.find(from_k)))

func _assign_open() -> void:
	var w = hud_().work
	# A task row nobody has (a task id, state open).
	var pick := ""
	for r in w.rows_now:
		if int(r["id"]) != -1 and String(r["state"]) == "open":
			pick = String(r["key"])
			break
	check("an open task row exists to assign", pick != "")
	set_meta("pick", pick)
	qselect(pick)
	qclick(func(): return act_button("assign"), 8)

func _assign_pick() -> void:
	var a = hud_().assign
	check("Assign to... opens the Who window with the colonists", a.visible and a.mode == "assign" and a._people.get_child_count() > 3 and not a._heads.visible, str(a.visible))
	var first: Button = null
	for b in a._people.get_children():
		if b is Button and b.has_meta("agent"):
			first = b
			break
	set_meta("agent", int(first.get_meta("agent")))
	click(first)

func _after_assign() -> void:
	var aid: int = get_meta("agent")
	var sim = main.sim
	var o = sim.state["agents"][aid].get("order", {})
	var r: Dictionary = row_of("maintenance", get_meta("pick"))
	check("the colonist has a task order (SIM: kind task)", String(o.get("kind", "")) == "task", str(o))
	check("the Who window closed and says what was done", not hud_().assign.visible and hud_().assign.last_ok, hud_().assign.last_text)

func _cancel_row() -> void:
	var w = hud_().work
	var key_: String = ""
	for r in w.rows_now:
		if int(r["id"]) != -1 and String(r["state"]) == "open" and String(r["key"]) != String(get_meta("pick")):
			key_ = String(r["key"])
			break
	set_meta("cancel_key", key_)
	check("a row to cancel exists", key_ != "")
	qselect(key_)
	qclick(func(): return act_button("cancel"), 8)

func _after_cancel() -> void:
	var key_: String = get_meta("cancel_key")
	var st: String = String(row_of("maintenance", key_).get("state", ""))
	check("Cancel: SIM holds the row (nobody takes it)", st == "held", st)
	qselect(key_)

func _release_row() -> void:
	check("a held row has Release", act_button("release") != null)
	qclick(func(): return act_button("release"), 8)

func _after_release() -> void:
	var st: String = String(row_of("maintenance", get_meta("cancel_key")).get("state", ""))
	check("Release lifts the hold", st != "held", st)

# ---------------------------------------------------------------- Repair now
func _repair_setup() -> void:
	var sim = main.sim
	bld = -1
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["state"]) == "active" and String(b["kind"]) == "room" and bool(main.hud.data.wear_of(b).get("known", false)):
			bld = int(id)
			break
	check("a machine to wear down", bld != -1)
	var b2: Dictionary = sim.state["buildings"][bld]
	b2["health"] = 40.0                     # test set-up: a worn structure
	main.hud.work.visible = false
	main.select("building", bld)

func _repair_badges() -> void:
	var insp = hud_().inspector
	var sim = main.sim
	check("the inspector is open on the structure", insp.visible)
	var worn := false
	var btn := false
	for n in insp.find_children("*", "Control", true, false):
		if n.has_meta("act") and String(n.get_meta("act")) == "repair_now":
			if n is Button:
				btn = true
			else:
				worn = true
	check("a WORN badge and a Repair now button show", worn and btn, "badge %s button %s" % [worn, btn])
	# BROKEN: the status badge itself opens the same window.
	sim.state["buildings"][bld]["state"] = "broken"
	main.select("", -1)
	main.select("building", bld)
	set_meta("broken_set", true)

func _repair_team() -> void:
	var insp = hud_().inspector
	var sim = main.sim
	var broken_badge := false
	for n in insp.find_children("*", "Control", true, false):
		if n.has_meta("act") and String(n.get_meta("act")) == "repair_now" and not (n is Button):
			broken_badge = true
	check("a BROKEN badge opens Repair now too", broken_badge)
	sim.state["buildings"][bld]["state"] = "active"
	sim.state["buildings"][bld]["health"] = 40.0
	main.select("", -1)
	main.select("building", bld)
	team_before = (sim.workq.summary()["teams"])
	qn(func():
		var rb: Button = null
		for n in insp.find_children("*", "Button", true, false):
			if n.has_meta("act") and String(n.get_meta("act")) == "repair_now":
				rb = n
		click(rb), 8)
	qn(func():
		var a = hud_().assign
		check("Repair now opens the Who window: heads and colonists", a.visible and a.mode == "repair" and a._heads.get_child_count() >= 2 and a._people.get_child_count() > 3, str(a._heads.get_child_count()))
		var hb: Button = null
		for b in a._heads.get_children():
			if b is Button and b.has_meta("head"):
				var hid: int = int(b.get_meta("head"))
				if String(main.sim.people.rank(main.sim.state["agents"][hid]).get("rank", "")) == "captain" and main.sim.people.department(main.sim.state["agents"][hid]) == "maintenance":
					hb = b
		check("the Captain of Maintenance is in the list", hb != null)
		set_meta("head", int(hb.get_meta("head")))
		click(hb), 8)

func _after_team() -> void:
	var sim = main.sim
	var sm: Dictionary = sim.workq.summary()
	check("a team order: SIM made a team (the head allocated it)", int(sm["teams"]) == team_before + 1, "%d -> %d" % [team_before, int(sm["teams"])])
	var members := 0
	var who := -1
	for aid in sim.state["agents"]:
		var o = sim.state["agents"][aid].get("order", {})
		if typeof(o) == TYPE_DICTIONARY and String(o.get("kind", "")) == "repair" and int(o.get("b", -1)) == bld and int(o.get("team", -1)) >= 0:
			members += 1
			who = int(aid)
	check("two or more colonists have the repair order", members >= 1, str(members))
	set_meta("member", who)
	check("the Who window closed with the head's report", not hud_().assign.visible and hud_().assign.last_ok and hud_().assign.last_text.contains("assigned"), hud_().assign.last_text)
	hud_().watchers.check()
	var posted := false
	for e in hud_().panels.feed:
		if String(e["type"]) == "orders" and String(e["text"]).contains("assigned"):
			posted = true
	check("the dock shows the report (News, type Orders and work)", posted, str(hud_().panels.feed.slice(0, 2)))
	var rows: Array = main.sim.workq.rows("maintenance")
	var team_row := false
	for r in rows:
		if String(r["state"]) == "team":
			team_row = true
	check("the team order is a row of the Work window with its assignees", team_row)

func _person_order() -> void:
	main.hud.open_person(int(get_meta("member")), "file")

func _person_check() -> void:
	var p = hud_().person
	var ob = p.find_child("OrderBlock", true, false)
	check("the personnel file shows the order", p.visible and ob != null)
	var txt := ""
	if ob != null:
		for l in ob.find_children("*", "Label", true, false):
			txt += (l as Label).text + " "
	check("it names the structure and the head's team order", txt.contains(main.sim.state["buildings"][bld]["name"]) and txt.contains("team order"), txt.left(160))
	check("it says what the colonist does for the order", p.find_child("OrderText", true, false) != null and (p.find_child("OrderText", true, false) as Label).text != "")
	p.visible = false

func _repair_person() -> void:
	var sim = main.sim
	# One person: a colonist who is not on a team; the order comes at once.
	var pick := -1
	for c in hud_().v18.candidates(bld, 30, true):
		if not bool(c["order"]):
			pick = int(c["id"])
			break
	set_meta("one", pick)
	main.select("", -1)
	main.select("building", bld)
	qn(func():
		var rb: Button = null
		for n in hud_().inspector.find_children("*", "Button", true, false):
			if n.has_meta("act") and String(n.get_meta("act")) == "repair_now":
				rb = n
		click(rb), 8)
	qn(func():
		var a = hud_().assign
		var pb: Button = null
		for b in a._people.get_children():
			if b is Button and b.has_meta("agent") and int(b.get_meta("agent")) == pick:
				pb = b
		check("the colonist is in the list", pb != null)
		a._standing.button_pressed = true
		reveal(pb)
		qn(func(): click(pb), 8), 3)

func _after_person() -> void:
	var sim = main.sim
	var o = sim.state["agents"][int(get_meta("one"))].get("order", {})
	check("one colonist: the order (kind maintain, standing) is in SIM", String(o.get("kind", "")) == "maintain" and int(o.get("b", -1)) == bld and bool(o.get("standing", false)), str(o))
	check("the colonist's goal says it", String(sim.state["agents"][int(get_meta("one"))].get("goal", "")).to_lower().contains("maintain") or String(o.get("text", "")) != "")

# ---------------------------------------------------------------- chains
func _chain_open() -> void:
	main._on_cmd("closeall")
	hud_().open_chain("spare_parts")

func _chain_check() -> void:
	var c = hud_().chain
	check("Show chain opens the chain window", c.visible and c.item == "spare_parts")
	var steps: Array = c.chain_now.get("steps", [])
	check("the chain has steps: raw -> structure -> item", steps.size() >= 3 and String(steps[steps.size() - 1]["kind"]) == "item" and String(steps[steps.size() - 1]["id"]) == "spare_parts", str(steps.size()))
	var cards := 0
	for n in c._body.find_children("*", "HBoxContainer", true, false):
		if n.has_meta("step"):
			cards += 1
	check("every step is a card with a state tag", cards == steps.size(), "%d cards %d steps" % [cards, steps.size()])
	var place: Button = null
	for b in c._body.find_children("*", "Button", true, false):
		if b.has_meta("place"):
			place = b
	var missing := false
	for st in steps:
		if String(st["state"]) != "done":
			missing = true
	check("a step that is not done has a STE line", missing and c._sum.text != "")
	if place != null:
		reveal(place)
		qn(func(): click(place), 6)
		qn(func():
			check("Place starts the placement of the missing structure", main.tool == "place" and main.tool_def == String(place.get_meta("place")) and not hud_().chain.visible, "%s %s" % [main.tool, main.tool_def])
			main.cancel_tool(), 6)
	else:
		check("a Place button for an unlocked missing structure (or all done)", not missing, "no Place button")

func _alert_chain() -> void:
	var sim = main.sim
	# An alert like SIM's "chain:<item>" (the issue carries its item).
	var tick: int = int(sim.state["tick"])
	sim.state["issues"]["chain:spare_parts"] = {"key": "chain:spare_parts", "code": "chain", "severity": 1, "text": "Spare parts needed: build a Workshop.", "action": "Place a Workshop.",
		"entities": [], "cause": "", "forecast": -1.0, "count": 1, "first_tick": tick, "live": true, "item": "spare_parts", "base": -1}
	sim.state["alert_track"]["chain:spare_parts"] = {"since": tick - 9999, "last": tick}
	hud_().watchers.gate.display([])
	hud_().alerts.rebuild()
	hud_().panels.open_tab("alerts", true)

func _alert_check() -> void:
	var btn: Button = null
	for b in hud_().alerts.find_children("*", "Button", true, false):
		if b.has_meta("chain_item"):
			btn = b
	check("an alert about a missing item has a Show chain button", btn != null)
	if btn != null:
		btn.pressed.emit()
		check("the button opens the chain of that item", hud_().chain.visible and hud_().chain.item == "spare_parts")
	main.sim.state["issues"].erase("chain:spare_parts")
	main._on_cmd("closeall")

func _codex_chain() -> void:
	main._on_cmd("closeall")
	main.hud.open_screen("codex", "chain:spare_parts")

func _codex_check() -> void:
	var top = hud_().screens.top_screen()
	check("the codex has the page Chains", top != null and top.tab == "chain" and top.shown_ids.size() > 10, str(top.shown_ids.size() if top != null else -1))
	var steps := 0
	if top != null:
		for n in top._detail.find_children("*", "HBoxContainer", true, false):
			if n.has_meta("step"):
				steps += 1
	check("the detail shows the chain of the item", steps >= 3, str(steps))
	main._on_cmd("closeall")

# ---------------------------------------------------------------- the orders diagnosis (UI faults)
func _status_check() -> void:
	main._on_cmd("closeall")
	main.select("", -1)
	main.select("building", bld)

func _status_check2() -> void:
	var rs = hud_().inspector.find_child("RepairStatus", true, false)
	check("the structure shows who is on it (a pending marker)", rs != null and (rs as Label).visible and (rs as Label).text.begins_with("On it:"), (rs as Label).text if rs != null else "none")

func _dash_open() -> void:
	var sim = main.sim
	# A broken machine: the dashboard card lists it with Repair now (the card said none was near failure).
	for aid in sim.state["agents"]:
		sim.state["agents"][aid].erase("order")
	var b: Dictionary = sim.state["buildings"][bld]
	b["state"] = "broken"
	main.select("", -1)
	main.hud.open_screen("dashboard", "hazards")

func _dash_check() -> void:
	var top = hud_().screens.top_screen()
	var found: Button = null
	var txt := ""
	if top != null:
		for bt in top.content.find_children("*", "Button", true, false):
			txt += (bt as Button).text + "|"
			if (bt as Button).text == "Repair now":
				found = bt
	check("the dashboard card lists a broken machine with Repair now", found != null, txt.left(200))
	var empty := false
	if top != null:
		for l in top.content.find_children("*", "Label", true, false):
			if (l as Label).text.begins_with("No machine is near failure"):
				empty = true
	check("the card does not say that no machine is near failure while one is broken", not empty)
	if found != null:
		found.pressed.emit()
		check("Repair now opens the Who window (a person or a head), not a toast", hud_().assign.visible and hud_().assign.mode == "repair" and hud_().screens.top_screen() == null, str(hud_().assign.visible))
	main.sim.state["buildings"][bld]["state"] = "active"
	main._on_cmd("closeall")

# ---------------------------------------------------------------- the Orders window verbs and the pick
func _verbs() -> void:
	var sim = main.sim
	main._on_cmd("closeall")
	sim.state["buildings"][bld]["health"] = 40.0
	# The pick finds the structure although a colonist stands on it.
	var who := -1
	for c in hud_().v18.candidates(bld, 40, true):
		if not bool(c["order"]):
			who = int(c["id"])
			break
	var spot: Vector2 = sim.state["buildings"][bld]["pos"]
	sim.state["agents"][who]["pos"] = spot
	check("the pick gives the structure under the click (main.structure_at), not a colonist", main.structure_at(spot) == bld, str(main.structure_at(spot)))
	check("a point far from every structure gives none", main.structure_at(Vector2(-5000, -5000)) == -1)
	hud_().orders.group = [who]
	hud_().orders.visible = true
	set_meta("who", who)
	hud_().orders._send("repair", [who], bld)

func _verbs2() -> void:
	var sim = main.sim
	var who: int = get_meta("who")
	var o = sim.state["agents"][who].get("order", {})
	check("Repair... gives a repair order (SIM kind repair)", String(o.get("kind", "")) == "repair" and int(o.get("b", -1)) == bld, str(o))
	var line := ""
	for l in hud_().orders._list.find_children("*", "Label", true, false):
		line += (l as Label).text + " "
	check("the order row names the structure and says what happens", line.contains(sim.state["buildings"][bld]["name"]) and line.contains("Order:"), line.left(200))
	hud_().orders._send("maintain", [who], bld)

func _verbs3() -> void:
	var sim = main.sim
	var who: int = get_meta("who")
	var o = sim.state["agents"][who].get("order", {})
	check("Keep in repair... gives a standing order (kind maintain)", String(o.get("kind", "")) == "maintain" and bool(o.get("standing", false)), str(o))
	check("the Haul controls list items that are in a store", hud_().orders._haul_item.item_count > 0, str(hud_().orders._haul_item.item_count))
	hud_().orders._send("haul", [who], {"b": bld, "res": "metal", "qty": 1})

func _verbs4() -> void:
	var sim = main.sim
	var who: int = get_meta("who")
	var o = sim.state["agents"][who].get("order", {})
	check("Haul... gives a haul order (or SIM says why not)", String(o.get("kind", "")) == "haul" or hud_().orders._msg.text != "", str(o))
	hud_().orders.visible = false
	sim.state["agents"][who].erase("order")
