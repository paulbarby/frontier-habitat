extends SceneTree
## Developer tool: plays the reference campaign and prints every death with its cause and
## the alerts of that moment.
##   node tools/godot.mjs script res://tests/dev/deaths.gd [seed] [days]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1002
	var days: float = float(args[1]) if args.size() > 1 else 27.0
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	var seen := {}
	for s in int(days * 600):
		ref.drive()
		sim.run_seconds(1.0)
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "dead" and not seen.has(aid):
				seen[aid] = true
				var alerts: Array = []
				for k in sim.state["issues"]:
					if int(sim.state["issues"][k]["severity"]) >= 2:
						alerts.append(String(sim.state["issues"][k]["text"]).left(90))
				print("day %.2f %s (%s) died: %s at %s where %s; alerts %s" % [sim.util.days_elapsed() + 1.0, a["name"], a["role"], a["cause"], str(a["pos"]), a["where"], str(alerts)])
	print("storms ", sim.state["stats"].get("storms", 0))
	quit(0)
