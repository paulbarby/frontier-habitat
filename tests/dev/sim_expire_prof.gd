extends SceneTree
## SIM probe: tasks by kind on showcase_v5 and the cost of the checks in jobs._expire.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(30.0)
	var kinds := {}
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		var k: String = "%s/%s" % [t["kind"], "own" if int(t["owner"]) != -1 else "open"]
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("tasks %d: %s" % [sim.state["tasks"].size(), str(kinds)])
	var t0: int = Time.get_ticks_usec()
	var n := 0
	for i in 20:
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if t["kind"] == "haul" and not bool(t["picked"]):
				sim.jobs._cross_base(t)
				n += 1
	print("cross_base %.4f ms a call (%d calls)" % [float(Time.get_ticks_usec() - t0) / 1000.0 / float(maxi(1, n)), n])
	t0 = Time.get_ticks_usec()
	n = 0
	for i in 20:
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["state"] == "active" and not sim.prod.recipe_of(b).is_empty():
				sim.prod.machine_block(b)
				n += 1
	print("machine_block %.4f ms a call (%d calls)" % [float(Time.get_ticks_usec() - t0) / 1000.0 / float(maxi(1, n)), n])
	for i in 5:
		t0 = Time.get_ticks_usec()
		sim.jobs._expire()
		var e: float = float(Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		sim.jobs._index()
		var ix: float = float(Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		sim.jobs._gen_machine_inputs()
		var mi: float = float(Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		sim.jobs._gen_repair()
		var rp: float = float(Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		sim.jobs._gen_hazard_work()
		var hw: float = float(Time.get_ticks_usec() - t0) / 1000.0
		print("expire %.2f index %.2f machine_inputs %.2f repair %.2f hazard_work %.2f" % [e, ix, mi, rp, hw])
		sim.run_seconds(1.0)
	sim.dispose()
	quit(0)
