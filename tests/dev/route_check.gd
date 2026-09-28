extends SceneTree
## Developer tool: the showcase vehicles after a minute: state, block, route leg, and the time of
## a rover path from each vehicle to the landing base and the camp.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	for row in sim.vehicles.list():
		var v: Dictionary = sim.vehicles.get_v(int(row["id"]))
		var bay: Dictionary = sim.vehicles.bay_of(v)
		var from: Vector2 = bay["exit"] if not bay.is_empty() else v["pos"]
		var t0: int = Time.get_ticks_usec()
		var r: Dictionary = sim.nav.vehicle_path(from, sim.world.center + Vector2(0, 300), "rover")
		print("%s at %s bay %d: rover path out ok %s in %.1f ms; rover_ok(from) %s" % [row["name"], str(row["pos"]), int(row["bay"]), str(r["ok"]), float(Time.get_ticks_usec() - t0) / 1000.0, str(sim.nav.rover_ok(from))])
	sim.run_seconds(60.0)
	for row in sim.vehicles.list():
		print("after 60 s: %s state %s block '%s' route %s" % [row["name"], row["state"], row["block"], str(row["route"])])
	sim.dispose()
	quit(0)
