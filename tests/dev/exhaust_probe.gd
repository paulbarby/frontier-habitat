extends SceneTree
## Developer tool: follows one colonist of a save (index in id order) and prints fatigue, plan,
## goal, sleep and health every 20 s; with "class" the colonist is enrolled first (v5 no-work).
##   node tools/godot.mjs script res://tests/dev/exhaust_probe.gd [index] [class] [seconds]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var idx: int = int(args[0]) if args.size() > 0 else 1
	var mode: String = String(args[1]) if args.size() > 1 else ""
	var secs: int = int(args[2]) if args.size() > 2 else 900
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	sim.run_seconds(10.0)
	var ids: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child":
			ids.append(int(aid))
	ids.sort()
	var a: Dictionary = sim.state["agents"][ids[idx]]
	if mode == "class":
		a["v5_nowork"] = true   # probe: the no-work flag only (people.gd would set it again)
	print("agent %d %s %s bed %d" % [int(a["id"]), a["name"], a["role"], int(a["bed"])])
	for s in secs / 20:
		for k in 200:
			if mode == "class":
				a["v5_nowork"] = true
			sim.step()
		print("t%4d fat %5.1f hun %5.1f thi %5.1f hp %5.1f sleep %s kind %s goal '%s' where %s bld %d" % [(s + 1) * 20, float(a["fatigue"]), float(a["hunger"]), float(a["thirst"]), float(a["health"]), str(a["sleeping"]), a["plan_kind"], a["goal"], a["where"], int(a["bld"])])
		if a["state"] != "alive":
			print("dead: ", a.get("cause"))
			break
	sim.dispose()
	quit(0)
