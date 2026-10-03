extends SceneTree
## Diagnostic (UI path): after "Maintain now" on four worn machines, trace the maintain tasks
## second by second for 240 s: created, claimed, failed, source resting.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	for bid in [991, 665, 227, 108]:
		sim.submit("maintain", {"id": bid})
	var last := ""
	for s in 240:
		sim.run_seconds(1.0)
		var parts: Array = []
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if t["kind"] == "maintain":
				parts.append("%d:b%d:%s:owner%s:reason=%s" % [tid, t["bld"], t["state"], t["owner"], t["reason"]])
		parts.sort()
		var rest: bool = sim.jobs._source_resting(3639)
		var line: String = "tasks=%s pile_resting=%s unreach_src=%s" % [str(parts), rest, str(sim.state.get("unreach_src", {}))]
		if line != last:
			print("t+%3d s  %s" % [s + 1, line])
			last = line
	var wear: Dictionary = sim.hazards.hs()["wear"]
	for bid in [991, 665, 227, 108]:
		print("bld ", bid, " w=", snappedf(float(wear[bid]["w"]), 0.1), " n=", wear[bid]["n"], " maint_first=", sim.state["buildings"][bid].get("maint_first", false), " state=", sim.state["buildings"][bid]["state"])
	print("stat maintenance=", sim.state["stats"].get("maintenance", "?") if sim.state.has("stats") else "?")
	sim.dispose()
	quit(0)
