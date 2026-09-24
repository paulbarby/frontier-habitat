extends SceneTree
## Developer tool: every colonist's use in one building of a save.
##   node tools/godot.mjs script res://tests/dev/uses_in.gd <save name> <building id>

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var name: String = args[0] if args.size() > 0 else "showcase_v3_late"
	var bid: int = int(args[1]) if args.size() > 1 else 51
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/%s.fhsave" % name))
	var sim = Sim.new()
	sim.load_state(dec["state"])
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	print("building %d: %s size %d, furniture %s, beds %d, assigned %d" % [bid, b.get("name", "?"), int(b.get("size", 1)),
		str(sim.sizes.furniture(String(b.get("def", "")), int(b.get("size", 1)))), int(sim.bd(b).get("beds", 0)) if not b.is_empty() else 0, sim.agents.beds_used(bid)])
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and (int(a["bld"]) == bid or int(a.get("use", {}).get("b", -1)) == bid):
			print("  %d %s where %s bld %d bed %d goal '%s' use %s" % [int(aid), a["name"], a["where"], int(a["bld"]), int(a["bed"]), a["goal"], str(a.get("use", {}))])
	quit(0)
