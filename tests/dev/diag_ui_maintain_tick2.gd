extends SceneTree
## Diagnostic (UI path): who uses the spare-parts pile around the moment its rest ends.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	for bid in [991, 665, 227, 108]:
		sim.submit("maintain", {"id": bid})
	var t0: int = int(sim.state["tick"])
	var last := ""
	for i in 560:
		sim.step()
		var n: int = int(sim.state["tick"]) - t0
		if n < 515:
			continue
		var parts: Array = []
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if String(t.get("res", "")) == "spare_parts" or t["kind"] in ["maintain", "repair"]:
				parts.append("%d:%s:b%d:%s:owner%s:src%s:reason=%s" % [tid, t["kind"], t["bld"], t["state"], t["owner"], t.get("src"), t["reason"]])
		parts.sort()
		var line: String = "tasks=%s resting=%s" % [str(parts), sim.jobs._source_resting(3639)]
		if line != last:
			print("tick+%4d (phase %d) %s" % [n, int(sim.state["tick"]) % 10, line])
			last = line
	sim.dispose()
	quit(0)
