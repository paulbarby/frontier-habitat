extends SceneTree
## Diagnostic (read-only): what Paul's own autosave (copied to the scratchpad) holds.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_sim_d_paul_save.gd <abs path>
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(args[0]))["state"])
	print("tick ", sim.state["tick"], " day ", snappedf(float(sim.state["tick"]) / 6000.0, 0.01), " alive ", sim.alive_count(), " buildings ", sim.state["buildings"].size())
	var defs := {}
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		var k: String = "%s/%s" % [b["def"], b["state"]]
		defs[k] = int(defs.get(k, 0)) + 1
	print("buildings: ", defs)
	print("orders held: ")
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a.has("order"):
			print("  ", a["name"], " ", a["order"])
	print("spare_parts: ", sim.inv.totals().get("spare_parts", {}))
	sim.dispose()
	quit(0)
