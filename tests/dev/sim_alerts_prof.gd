extends SceneTree
## SIM probe: the cost of each alert check and of morale_second on showcase_v5.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(20.0)
	var names := ["_power_issues", "_water_issues", "_air_issues", "_building_issues", "_people_issues", "_supply_issues", "_nutrition_issues", "_progress_issues", "_hazard_issues"]
	var tot := {}
	var mx := {}
	for i in 40:
		sim.run_seconds(1.0)
		var found := {}
		for n in names:
			var t0: int = Time.get_ticks_usec()
			sim.alerts.call(n, found)
			var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
			tot[n] = float(tot.get(n, 0.0)) + ms
			mx[n] = maxf(float(mx.get(n, 0.0)), ms)
		var t1: int = Time.get_ticks_usec()
		sim.reactors.issues(found, sim.alerts)
		tot["reactors"] = float(tot.get("reactors", 0.0)) + float(Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		sim.agents.morale_second()
		var mm: float = float(Time.get_ticks_usec() - t1) / 1000.0
		tot["morale"] = float(tot.get("morale", 0.0)) + mm
		mx["morale"] = maxf(float(mx.get("morale", 0.0)), mm)
		t1 = Time.get_ticks_usec()
		sim.hazards.tick_second()
		mm = float(Time.get_ticks_usec() - t1) / 1000.0
		tot["hazards"] = float(tot.get("hazards", 0.0)) + mm
		mx["hazards"] = maxf(float(mx.get("hazards", 0.0)), mm)
	var keys: Array = tot.keys()
	keys.sort_custom(func(x, y): return float(tot[x]) > float(tot[y]))
	for k in keys:
		print("  %-20s %7.3f ms a call, max %6.2f" % [k, float(tot[k]) / 40.0, float(mx.get(k, 0.0))])
	sim.dispose()
	quit(0)
