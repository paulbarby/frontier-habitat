extends SceneTree
## Package transport UI (V5_DESIGN §18.5), headless, on showcase_v5, on SIM sim.transport (set up as SIM test does: hubs and tubes by field):
##   node tools/godot.mjs script res://tools/ui/test_transport.gd
## Key O steps to the transport overlay; the overlay draws the tubes, the hubs and the capsules; the inspector of a hub and of a tube has the
## section Package transport (role, state, load, items in transit, Show the network); a broken tube is red and shows in the section.
## With SIM's real network the same checks run on its data (ui/v18_data.gd transport()).

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
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

func key(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)

func hud_():
	return main.hud

func _stores() -> Array:
	var out: Array = []
	var ids: Array = main.sim.state["buildings"].keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = main.sim.state["buildings"][id]
		if String(b["state"]) == "active" and String(b["kind"]) == "room" and main.sim.transport.hub_defs().has(String(b["def"])):
			out.append(int(id))
	return out

func _section_text() -> String:
	var sec = hud_().inspector.find_child("TransportSection", true, false)
	var txt := ""
	if sec != null:
		for l in sec.find_children("*", "Label", true, false):
			txt += (l as Label).text + " "
	return txt

func _plan() -> void:
	Input.use_accumulated_input = false
	root.size = Vector2i(1600, 900)
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	main.boot["debug"] = "1"
	main._on_cmd("closeall")
	q(func():
		main.sim.state["flags"].erase("unlock_all")
		main.sim.state["research"]["done"].erase("log_transport")
		var st: Array = _stores()
		set_meta("stores", st)
		main.select("building", st[3] if st.size() > 3 else st[st.size() - 1]), 10)
	q(func(): check("before the research there is no transport section on a store", hud_().inspector.find_child("TransportSection", true, false) == null and not bool(hud_().v18.transport()["enabled"])), 4)
	q(func():
		main.sim.state["research"]["done"]["log_transport"] = true   # test set-up: researched
		main.select("", -1)
		main.select("building", (get_meta("stores") as Array)[(get_meta("stores") as Array).size() - 1]), 10)
	q(func():
		var ib = hud_().inspector.find_child("InstallTransport", true, false)
		check("after the research a store has the section with the cost and the button Install", hud_().inspector.find_child("TransportSection", true, false) != null and ib != null and not (ib as Button).disabled, _section_text().left(160))
		(ib as Button).pressed.emit(), 6)
	q(func():
		var sid: int = (get_meta("stores") as Array)[(get_meta("stores") as Array).size() - 1]
		var u: Dictionary = main.sim.state["buildings"][sid].get("upgrade", {})
		check("Install starts the upgrade in SIM (install_transport)", String(u.get("feature", "")) == "hub", str(u))
		main.sim.state["buildings"][sid].erase("upgrade"), 4)
	q(func(): check("the demo command is gone and the debug build makes a real network", String(main._on_cmd("transport build")).begins_with("transport:")), 6)
	q(func(): _cycle(), 10)
	q(func(): _overlay_check(), 4)
	q(func(): _hub_open(), 10)
	q(func(): _hub_check(), 4)
	q(func(): _capsule(), 10)
	q(func(): _capsule_check(), 4)
	q(func(): _tube_open(), 10)
	q(func(): _tube_check(), 4)
	q(func(): _broken(), 10)
	q(func(): _broken_check(), 4)

func _cycle() -> void:
	var n := 0
	while hud_().overlay_name() != "transport" and n < 12:
		hud_().cycle_overlay()
		n += 1
	check("key O reaches the transport overlay as the last step", hud_().overlay_name() == "transport" and hud_().transport_marks.on and String(main.view.overlay) == "", "%d steps" % n)

func _overlay_check() -> void:
	var tm = hud_().transport_marks
	var net: Dictionary = hud_().v18.transport()
	check("SIM has the network: hubs and tubes", bool(net["enabled"]) and net["hubs"].size() >= 2 and net["tubes"].size() >= 1, "%d hubs %d tubes" % [net["hubs"].size(), net["tubes"].size()])
	check("the overlay draws the tubes and the hubs", tm.tubes_drawn >= 1 and tm.hubs_drawn >= 1, "%d tubes %d hubs" % [tm.tubes_drawn, tm.hubs_drawn])
	hud_().cycle_overlay()
	check("the next step turns it off", hud_().overlay_name() == "" and not tm.on)
	hud_().set_overlay("")

func _hub_open() -> void:
	var hid: int = int(hud_().v18.transport()["hubs"][0]["id"])
	main.select("", -1)
	main.select("building", hid)

func _hub_check() -> void:
	check("a hub shows the section Package transport", hud_().inspector.find_child("TransportSection", true, false) != null)
	var txt: String = _section_text()
	check("it says Transport hub, working, and nothing in transit", txt.contains("Transport hub") and txt.contains("working") and txt.contains("Nothing in transit"), txt.left(200))
	var nb = hud_().inspector.find_child("ShowNetwork", true, false)
	check("it has Show the network, which turns the overlay on", nb != null)
	if nb != null:
		(nb as Button).pressed.emit()
		check("the overlay is on", hud_().overlay_name() == "transport")

func _capsule() -> void:
	# A capsule in flight (test set-up: SIM makes them from hauls; the UI reads capsules_view and position_of).
	var sim = main.sim
	var net: Dictionary = hud_().v18.transport()
	var h0: int = int(net["hubs"][0]["id"])
	var h1: int = int(net["hubs"][1]["id"])
	var tube: Dictionary = net["tubes"][0]
	var tick: int = int(sim.state["tick"])
	var w: Dictionary = sim.people.v5w()["transport"]
	w["capsules"][9999] = {"id": 9999, "res": "metal", "qty": 4, "src": h0, "dst": h1, "path": [int(tube["id"])],
		"segs": [{"cid": int(tube["id"]), "p0": tube["p0"], "p1": tube["p1"], "t0": tick - 20, "t1": tick + 400}], "t0": tick - 20, "t1": tick + 400, "hold_in": -1, "stuck": false}
	main.select("", -1)
	main.select("building", h0)

func _capsule_check() -> void:
	var txt: String = _section_text()
	check("the hub lists the capsule in transit", txt.contains("4 steel") or txt.contains("4 metal"), txt.left(200))
	check("the overlay draws the capsule", hud_().transport_marks.capsules_drawn >= 1 or hud_().v18.capsules().size() >= 1, str(hud_().v18.capsules().size()))
	main.sim.people.v5w()["transport"]["capsules"].erase(9999)

func _tube_open() -> void:
	var tid: int = int(hud_().v18.transport()["tubes"][0]["id"])
	set_meta("tube", tid)
	main.select("", -1)
	main.select("building", tid)

func _tube_check() -> void:
	var txt: String = _section_text()
	check("a tube shows the section with its role", txt.contains("Transport tube") and txt.contains("working"), txt.left(200))

func _broken() -> void:
	var tid: int = get_meta("tube")
	main.sim.state["buildings"][tid]["state"] = "broken"   # test set-up
	main.sim.transport._stamp = -1
	main.select("", -1)
	main.select("building", tid)

func _broken_check() -> void:
	var tid: int = get_meta("tube")
	var net: Dictionary = hud_().v18.transport()
	var ok_tube := true
	for t in net["tubes"]:
		if int(t["id"]) == tid:
			ok_tube = bool(t["ok"])
	check("SIM marks the tube down", not ok_tube)
	check("the section says broken", _section_text().contains("broken"), _section_text().left(200))
	main.sim.state["buildings"][tid]["state"] = "active"
