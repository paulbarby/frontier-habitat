extends SceneTree
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(10.0)
	sim.jobs._index(true)
	var near: Vector2 = sim.state["buildings"].values()[5]["pos"]
	for res in ["meals", "spare_parts", "metal", "gifts"]:
		var t0: int = Time.get_ticks_usec()
		for i in 500:
			sim.jobs.find_source(res, near)
		print(res, " find_source us ", float(Time.get_ticks_usec() - t0) / 500.0)
	var t1: int = Time.get_ticks_usec()
	for i in 500:
		sim.bases.base_at(near)
	print("base_at us ", float(Time.get_ticks_usec() - t1) / 500.0, " bases ", sim.bases.count())
	var t2: int = Time.get_ticks_usec()
	for i in 500:
		sim.bases._base_at_scan(near)
	print("scan us ", float(Time.get_ticks_usec() - t2) / 500.0)
	var lst: Array = sim.jobs._src_index.get("meals", [])
	var roles := {}
	for i2 in lst:
		var r2: String = String(sim.state["inventories"][i2]["role"])
		roles[r2] = int(roles.get(r2, 0)) + 1
	print("meals index ", lst.size(), roles)
	quit()
