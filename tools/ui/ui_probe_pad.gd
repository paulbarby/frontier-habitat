extends SceneTree
## Probe (UI, 2026-10-02): why test_ships_ui finds the new landing pad unpowered. Prints the power network of the pad.
##   node tools/godot.mjs script res://tools/ui/ui_probe_pad.gd
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func cmd(t: String) -> String:
	return String(main._on_cmd(t))
func _process(_d: float) -> bool:
	_n += 1
	if _n < 6:
		return false
	main.boot["debug"] = "1"
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	cmd("speed 0")
	var spot: String = cmd("findspot landing_pad 1 40")
	cmd("place landing_pad 1 " + spot)
	cmd("fast 400")
	var pad: int = int(cmd("idof landing_pad"))
	print("cable: ", cmd("cable " + str(pad)))
	cmd("fast 200")
	var s = main.sim
	var comp = s.topo.power_comp.get(pad, -1)
	print("pad ", pad, " comp ", comp, " day_time ", s.util.day_time(), " sun ", s.state["env"]["sun"])
	print("stats ", s.util.power_stats.get(comp, {}))
	var b: Dictionary = s.state["buildings"][pad]
	print("pad rec: state ", b["state"], " powered ", b["powered"], " enabled ", b["enabled"])
	var n_in := 0
	for id in s.state["buildings"]:
		if s.topo.power_comp.get(id, -2) == comp:
			n_in += 1
	print("members of the comp: ", n_in)
	for id in s.state["buildings"]:
		var q: Dictionary = s.state["buildings"][id]
		if String(q.get("kind", "")) == "link" and int(id) > pad - 5 and (q.get("a", -1) == pad or q.get("b", -1) == pad or q.get("from", -1) == pad or q.get("to", -1) == pad):
			print("link ", id, " ", q["def"], " state ", q["state"], " progress ", q.get("progress", "?"), " keys ", q.keys())
	var n_plan := 0
	for id in s.state["buildings"]:
		if String(s.state["buildings"][id]["state"]) != "active":
			n_plan += 1
	print("not active: ", n_plan)
	quit(0)
	return true
