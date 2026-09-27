extends SceneTree
## Developer tool: airlock cycles and new structures in 10 game minutes of a save.
##   node tools/godot.mjs script res://tests/dev/lock_cycles.gd <save name>
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var name: String = String(a[0]) if a.size() > 0 else "showcase_v31"
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/%s.fhsave" % name))
	var sim = Sim.new()
	sim.load_state(dec["state"])
	var ids0: Dictionary = {}
	for id in sim.state["buildings"]:
		ids0[id] = sim.state["buildings"][id]["state"]
	var cycles := 0
	var was := {}
	for i in 6000:
		sim.step()
		for id in sim.state["buildings"]:
			var lock: Dictionary = sim.state["buildings"][id].get("lock", {})
			if lock.is_empty():
				continue
			var on: bool = not (lock["cyc"] as Dictionary).is_empty()
			if on and not bool(was.get(id, false)):
				cycles += 1
			was[id] = on
	var changed: Array = []
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if not ids0.has(id) or ids0[id] != b["state"]:
			changed.append("%s %s" % [b["name"], b["state"]])
	print("%s: %d airlock cycles in 10 min; rules %s; speed in %.1f; structures new or changed: %s" % [name, cycles, str(sim.state.get("rules", "none")), float(sim.bal["speed_indoor"]), str(changed)])
	quit(0)
