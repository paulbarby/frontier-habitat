extends SceneTree
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var path := "res://content/saves/showcase_v5.fhsave"
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	sim.run_seconds(20.0)
	sim.agents.prof_ops = {}
	sim.agents.prof_n = {}
	var n := 3000
	for i in n:
		sim.step()
	for k in sim.agents.prof_ops:
		print("  %-8s %.3f ms/tick  %d calls  %.2f us/call" % [k, float(sim.agents.prof_ops[k]) / n / 1000.0, int(sim.agents.prof_n[k]), float(sim.agents.prof_ops[k]) / float(sim.agents.prof_n[k])])
	sim.dispose()
	quit(0)
