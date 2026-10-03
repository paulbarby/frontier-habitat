extends SceneTree
## Diagnostic (UI path): per-tick view of a maintain task made after "Maintain now".
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	for bid in [991, 665, 227, 108]:
		sim.submit("maintain", {"id": bid})
	var last := ""
	var t0: int = int(sim.state["tick"])
	for i in 1300:
		sim.step()
		var parts: Array = []
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if t["kind"] == "maintain":
				var o: int = int(t["owner"])
				var ag: Dictionary = sim.state["agents"].get(o, {})
				parts.append("%d:b%d:%s:owner%s(%s,%s):reason=%s" % [tid, t["bld"], t["state"], o, ag.get("name", "-"), ag.get("role", "-"), t["reason"]])
		parts.sort()
		var line: String = "tasks=%s resting=%s" % [str(parts), sim.jobs._source_resting(3639)]
		if line != last:
			print("tick+%4d  %s" % [int(sim.state["tick"]) - t0, line])
			last = line
	sim.dispose()
	quit(0)
