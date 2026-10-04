extends SceneTree
## Vehicles made clear (V5_DESIGN §19.3), headless:
##   node tools/godot.mjs script res://tools/ui/test_vehicles_guide.gd
## A new colony (no vehicle): the Vehicles window lists the five steps with the next one marked. The showcase (a depot and rovers): the
## detail of a vehicle says what it does and what to do next; Drive to, Explore area and Return are the main buttons; Drive to waits for a click
## on the map and then sends the vehicle (SIM vehicle_drive); the depot panel shows the next step; a hint shows once, the first time a depot exists.

const Settings = preload("res://ui/settings.gd")

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var _saved = null

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
		Settings.set_value("hint_vehicles", _saved)
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func _plan() -> void:
	_saved = Settings.get_value("hint_vehicles")
	Settings.set_value("hint_vehicles", false)
	root.size = Vector2i(1600, 900)
	main.leave_title()
	main.start_new(1001, {"scenario": "frontier"})
	main._on_cmd("speed 0")
	main._on_cmd("closeall")
	q(func(): main._on_cmd("open vehicles"), 10)
	q(func(): _empty(), 4)
	q(func():
		main._on_cmd("closeall")
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title(), 20)
	q(func(): _hint(), 4)
	q(func(): main._on_cmd("open vehicles"), 10)
	q(func(): _detail(), 4)
	q(func(): _drive(), 8)
	q(func(): _sent(), 4)
	q(func(): _depot_open(), 10)
	q(func(): _depot_check(), 4)

func _empty() -> void:
	var top = main.hud.screens.top_screen()
	var g = top.find_child("VehicleGuide", true, false) if top != null else null
	check("no vehicle: the window lists the steps", g != null)
	var steps := 0
	for id in ["depot", "vehicle", "crew", "destination", "go"]:
		if g != null and g.find_child("Step_" + id, true, false) != null:
			steps += 1
	check("all five steps are there", steps == 5, str(steps))
	var nx: Dictionary = main.hud.v4.vehicle_next()
	check("the next step is the first one not done", not nx.is_empty() and String(nx["id"]) in ["research", "depot"], str(nx))
	main._on_cmd("closeall")

func _hint() -> void:
	main.hud.watchers.reset()
	main.hud.watchers._grace_tick = -1
	main.hud.watchers.check()
	var posted := false
	for e in main.hud.panels.feed:
		if String(e["text"]).begins_with("Vehicles."):
			posted = true
	check("the first depot brings one hint", posted and bool(Settings.get_value("hint_vehicles")))
	var n0: int = main.hud.panels.feed.size()
	main.hud.watchers.check()
	check("it shows once", main.hud.panels.feed.size() == n0)

func _detail() -> void:
	var top = main.hud.screens.top_screen()
	var st = top.find_child("VehicleStatus", true, false) if top != null else null
	var nl = top.find_child("VehicleNext", true, false) if top != null else null
	check("a vehicle says what it does now, why it waits and what to do next (SIM status)", st != null and nl != null and (st as Label).text != "" and (nl as Label).text.begins_with("Next:"), (st as Label).text + " | " + (nl as Label).text if st != null else "none")
	var db = top.find_child("DriveTo", true, false)
	check("with nobody aboard Drive to is off and its tooltip says why", db != null and (db as Button).disabled and (db as Button).tooltip_text.contains("Nobody is aboard"), (db as Button).tooltip_text if db != null else "none")
	check("Board is the lit button", (top.find_child("BoardVehicle", true, false) as Button).theme_type_variation == "PrimaryButton")
	var ok := true
	for nm in ["DriveTo", "ExploreArea", "ReturnToDepot"]:
		var b = top.find_child(nm, true, false)
		if b == null or (b as Button).theme_type_variation != "PrimaryButton":
			ok = false
	check("Drive to, Explore area and Return are the main buttons", ok)

func _drive() -> void:
	var top = main.hud.screens.top_screen()
	set_meta("vid", int(top._sel))
	top._pick_drive(int(top._sel))
	check("Drive to waits for a click on the map", main.pick_cb.is_valid() and main.hud.screens.top_screen() == null)

func _sent() -> void:
	var vid: int = get_meta("vid")
	var v: Dictionary = main.hud.v4.vehicle(vid)
	var p: Vector2 = (v["pos"] as Vector2) + Vector2(60, 0)
	var cb: Callable = main.pick_cb
	main.pick_cb = Callable()
	cb.call(p, {})
	var v2: Dictionary = main.hud.v4.vehicle(vid)
	var driving: bool = String(v2.get("state", "")) in ["driving", "exploring"] or String(v2.get("block", "")) != ""
	var pops: String = " ".join(main.hud.panels.popup_texts())
	check("the click sends it: SIM drives it, or a message says why not", driving or pops.contains(String(v2["name"])), pops.left(120) + " / " + str(v2.get("state", "")))
	check("a toast or the state tells the player", String(v2.get("state", "")) != "")

func _depot_open() -> void:
	main._on_cmd("closeall")
	main._on_cmd("select rover_depot vehicles")

func _depot_check() -> void:
	var nl = main.hud.inspector.find_child("VehicleNextStep", true, false)
	var nx: Dictionary = main.hud.v4.vehicle_next()
	check("the depot panel shows the next step while one is open", nx.is_empty() or (nl != null and (nl as Label).text.begins_with("Next step:")), str(nx))
	main._on_cmd("closeall")
