extends SceneTree
## Probe (UI): what sim.vehicles.status / depot_status / guide give on showcase_v5.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
	if _n == 30:
		var s = main.sim
		print("guide ", s.vehicles.guide()); var hh = main.hud; print("live ", hh.v4.live("vehicles"), " status ", hh.v4.vehicle_status(s.vehicles.list()[0]))
		for v in s.vehicles.list():
			print("status ", s.vehicles.status(int(v["id"])))
		for id in s.state["buildings"]:
			if String(s.state["buildings"][id]["def"]) == "rover_depot":
				print("depot ", s.vehicles.depot_status(int(id)))
		quit(0)
	return false
