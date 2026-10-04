extends SceneTree
## A crop for each bed (V5_DESIGN §19.2), headless, on showcase_v5:
##   node tools/godot.mjs script res://tools/ui/test_farm_crops.gd
## The greenhouse inspector, tab Crops: the crop for every bed (chips), the farm menu (the share of beds and the yield for each crop,
## from SIM prod.farm_menu), and one crop box for each bed (SIM set_crop with a tray). A crop that is not researched is off.

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var gid := -1

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
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func _plan() -> void:
	root.size = Vector2i(1600, 900)
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	main._on_cmd("closeall")
	q(func():
		for id in main.sim.state["buildings"]:
			var b: Dictionary = main.sim.state["buildings"][id]
			if String(b["def"]) == "greenhouse" and String(b["state"]) == "active" and not (b.get("trays", []) as Array).is_empty():
				gid = int(id)
				break
		main.select("building", gid)
		main.hud.inspector.set_tab("crops"), 10)
	q(func(): _sections(), 4)
	q(func(): _bed(), 24)
	q(func(): _bed_check(), 4)
	q(func(): _all(), 6)
	q(func(): _all_check(), 4)

func _sections() -> void:
	var insp = main.hud.inspector
	check("a greenhouse is open on its Crops tab", gid != -1 and insp.visible)
	check("it has the crop for every bed, the farm menu and the beds", insp.find_child("CropAll", true, false) != null and insp.find_child("FarmMenu", true, false) != null and insp.find_child("FarmBeds", true, false) != null)
	var menu: Dictionary = main.sim.prod.farm_menu(main.sim.state["buildings"][gid])
	var beds: int = int(menu["beds"])
	var n_box := 0
	for i in beds:
		if insp.find_child("BedCrop_%d" % i, true, false) != null:
			n_box += 1
	check("every bed has its own crop box", beds > 0 and n_box == beds, "%d of %d" % [n_box, beds])
	var rows := 0
	for mc in menu["crops"]:
		if insp.find_child("Menu_" + String(mc["crop"]), true, false) != null:
			rows += 1
	check("the menu has a row for each crop in use", rows == (menu["crops"] as Array).size() and rows >= 1, str(rows))

func _bed() -> void:
	var insp = main.hud.inspector
	var b: Dictionary = main.sim.state["buildings"][gid]
	var menu: Dictionary = main.sim.prod.farm_menu(b)
	var cur: String = String(b["trays"][0].get("crop", ""))
	var other := ""
	for c in menu["allowed"]:
		if String(c) != cur:
			other = String(c)
			break
	set_meta("other", other)
	check("a second crop may be planted (research)", other != "", str(menu["allowed"]))
	var ob: OptionButton = insp.find_child("BedCrop_0", true, false)
	for k in ob.item_count:
		if String(ob.get_item_metadata(k)) == other:
			ob.select(k)
			ob.item_selected.emit(k)

func _bed_check() -> void:
	var b: Dictionary = main.sim.state["buildings"][gid]
	var other: String = get_meta("other")
	check("bed 1 is planned for the new crop (SIM set_crop with a tray)", String(b["trays"][0]["crop"]) == other, str(b["trays"][0]["crop"]))
	var n_other := 0
	for t in b["trays"]:
		if String(t["crop"]) != other:
			n_other += 1
	check("the other beds keep their crop", n_other == (b["trays"] as Array).size() - 1)
	var m: Dictionary = main.sim.prod.farm_menu(b)
	check("the menu shows two crops with their shares", (m["crops"] as Array).size() >= 2, str(m["crops"].size()))
	var rows2 := 0
	for mc in m["crops"]:
		if main.hud.inspector.find_child("Menu_" + String(mc["crop"]), true, false) != null:
			rows2 += 1
	check("the menu rows follow SIM (a growing bed keeps its crop until the harvest)", rows2 == (m["crops"] as Array).size(), str(rows2))

func _all() -> void:
	var b: Dictionary = main.sim.state["buildings"][gid]
	var menu: Dictionary = main.sim.prod.farm_menu(b)
	var pick: String = String(menu["allowed"][0])
	set_meta("pick", pick)
	var chip: Button = main.hud.inspector.find_child("All_" + pick, true, false)
	check("the chip for every bed is there and on", chip != null and not chip.disabled)
	chip.pressed.emit()

func _all_check() -> void:
	var b: Dictionary = main.sim.state["buildings"][gid]
	var pick: String = get_meta("pick")
	var all := true
	for t in b["trays"]:
		if String(t["crop"]) != pick:
			all = false
	check("the chip plants every bed", all and String(b["crop"]) == pick)
