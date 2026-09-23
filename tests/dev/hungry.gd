extends SceneTree
## Developer tool: loads a save and follows every hungry colonist for a while.
##   node tools/godot.mjs script res://tests/dev/hungry.gd -- [save] [seconds]

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://content/saves/showcase_day9.fhsave"
	var secs: int = int(args[1]) if args.size() > 1 else 60
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))
	var sim = Sim.new()
	sim.load_state(dec["state"])
	_print(sim)
	for s in secs:
		sim.run_seconds(1.0)
		if s % 5 == 4:
			_print(sim)
	quit(0)

func _print(sim) -> void:
	var line := "t=%d " % int(sim.seconds())
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or float(a["hunger"]) < 60.0:
			continue
		var steps: Array = []
		for st in a["plan"]:
			steps.append(String(st["op"]) + ("(%s)" % str(st.get("dish", "")) if st["op"] == "eat" else ""))
		line += "\n   %s %s hunger %.0f where %s bld %d goal '%s' plan %s pi %d task %d" % [a["name"], a["role"], float(a["hunger"]), a["where"], int(a["bld"]), a["goal"], str(steps), int(a["pi"]), int(a["task"])]
	for key in sim.state["issues"]:
		var i: Dictionary = sim.state["issues"][key]
		if i["code"] == "starving":
			line += "\n   ALERT " + String(i["text"])
	print(line)
