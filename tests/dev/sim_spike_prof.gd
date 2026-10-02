extends SceneTree
## SIM probe: which job generator makes a slow tick (needs the temporary prof_g timers in jobs.gd).
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(20.0)
	var n := 30000
	var big := {}
	for i in n:
		sim.jobs.prof_g = {}
		var t0: int = Time.get_ticks_usec()
		sim.step()
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		if ms > 12.0:
			var parts: Array = []
			for k in sim.jobs.prof_g:
				if float(sim.jobs.prof_g[k]) > 0.5:
					parts.append("%s %.1f" % [k, float(sim.jobs.prof_g[k])])
			print("slow tick %d (phase %d) %.1f ms: %s" % [int(sim.state["tick"]), int(sim.state["tick"]) % 10, ms, ", ".join(parts)])
	sim.dispose()
	quit(0)
