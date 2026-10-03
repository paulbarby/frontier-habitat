extends SceneTree
## Package transport UI (V5_DESIGN §18.5), headless, on showcase_v5, with the debug demo network (SIM has no transport yet):
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

func _plan() -> void:
	Input.use_accumulated_input = false
	root.size = Vector2i(1600, 900)
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	main.boot["debug"] = "1"
	main._on_cmd("closeall")
	q(func(): check("no network: an empty transport", hud_().v18.transport()["hubs"].is_empty() and not hud_().v18.transport_live()), 4)
	q(func(): check("the demo command builds a network", String(main._on_cmd("transport demo")).begins_with("demo network")), 4)
	q(func(): _cycle(), 10)
	q(func(): _overlay_check(), 4)
	q(func(): _hub_open(), 10)
	q(func(): _hub_check(), 4)
	q(func(): _tube_open(), 10)
	q(func(): _tube_check(), 4)
	q(func(): _broken(), 10)
	q(func(): _broken_check(), 4)

func _cycle() -> void:
	# Key O until the transport overlay (the last step), at most 12 steps.
	var n := 0
	while hud_().overlay_name() != "transport" and n < 12:
		hud_().cycle_overlay()
		n += 1
	check("key O reaches the transport overlay as the last step", hud_().overlay_name() == "transport" and hud_().transport_marks.on and String(main.view.overlay) == "", "%d steps" % n)

func _overlay_check() -> void:
	var tm = hud_().transport_marks
	check("the overlay draws tubes, hubs and capsules", tm.tubes_drawn >= 1 and tm.hubs_drawn >= 2 and tm.capsules_drawn >= 2, "%d tubes %d hubs %d capsules" % [tm.tubes_drawn, tm.hubs_drawn, tm.capsules_drawn])
	hud_().cycle_overlay()
	check("the next step turns it off", hud_().overlay_name() == "" and not tm.on)
	hud_().set_overlay("")

func _hub_open() -> void:
	var net: Dictionary = hud_().v18.transport()
	var hid: int = int(net["hubs"][0]["b"])
	set_meta("hub", hid)
	main.select("building", hid)

func _hub_check() -> void:
	var sec = hud_().inspector.find_child("TransportSection", true, false)
	check("a hub shows the section Package transport", sec != null)
	var txt := ""
	if sec != null:
		for l in sec.find_children("*", "Label", true, false):
			txt += (l as Label).text + " "
	check("it says Transport hub and lists the capsules in transit", txt.contains("Transport hub") and txt.contains("In transit"), txt.left(200))
	var nb = hud_().inspector.find_child("ShowNetwork", true, false)
	check("it has Show the network", nb != null)
	if nb != null:
		(nb as Button).pressed.emit()
		check("the button turns the overlay on", hud_().overlay_name() == "transport")
		hud_().set_overlay("")

func _tube_open() -> void:
	var net: Dictionary = hud_().v18.transport()
	var tid := -1
	for t in net["tubes"]:
		if int(t["b"]) >= 0:
			tid = int(t["b"])
			break
	set_meta("tube", tid)
	main.select("", -1)
	main.select("building", tid)

func _tube_check() -> void:
	var sec = hud_().inspector.find_child("TransportSection", true, false)
	var txt := ""
	if sec != null:
		for l in sec.find_children("*", "Label", true, false):
			txt += (l as Label).text + " "
	check("a tube shows the section with its role and load", sec != null and txt.contains("Transport tube") and txt.contains("%"), txt.left(200))

func _broken() -> void:
	main._on_cmd("transport demo broken")
	main.select("", -1)
	var bad := -1
	for t in hud_().v18.transport()["tubes"]:
		if not bool(t["ok"]):
			bad = int(t["b"])
	set_meta("bad", bad)
	main.select("building", bad)
	hud_().set_overlay("transport")

func _broken_check() -> void:
	var sec = hud_().inspector.find_child("TransportSection", true, false)
	var txt := ""
	if sec != null:
		for l in sec.find_children("*", "Label", true, false):
			txt += (l as Label).text + " "
	check("a broken tube says broken", txt.contains("broken"), txt.left(200))
	check("the overlay still draws (the broken tube in red)", hud_().transport_marks.tubes_drawn >= 2)
	main._on_cmd("transport off")
	check("transport off clears the demo", hud_().v18.transport()["hubs"].is_empty())
