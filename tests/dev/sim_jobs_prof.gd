extends SceneTree
## SIM probe: the cost of each job generator (jobs.tick_second) on showcase_v5.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(10.0)
	var names := ["_expire", "_index", "_gen_machine_inputs", "_gen_repair", "_gen_hazard_work", "_gen_research", "_gen_medical", "_gen_ship",
		"_gen_construction", "_gen_upgrades", "_gen_vehicles", "_gen_reactors", "_gen_dining", "_gen_venues", "_gen_trade", "_gen_water_fill",
		"_gen_clearing", "_gen_operate", "_gen_tend", "_gen_demolish"]
	var tot := {}
	for i in 60:
		sim.run_seconds(1.0)
		for n in names:
			if not sim.jobs.has_method(n):
				continue
			var t0: int = Time.get_ticks_usec()
			sim.jobs.call(n)
			tot[n] = float(tot.get(n, 0.0)) + float(Time.get_ticks_usec() - t0) / 1000.0
	var keys: Array = tot.keys()
	keys.sort_custom(func(x, y): return float(tot[x]) > float(tot[y]))
	for k in keys:
		print("  %-22s %7.3f ms a call" % [k, float(tot[k]) / 60.0])
	sim.dispose()
	quit(0)
