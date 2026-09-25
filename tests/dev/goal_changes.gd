extends SceneTree
## Developer tool: prints every goal change of every colonist between two ticks.
##   node tools/godot.mjs script res://tests/dev/goal_changes.gd <from> <to>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var a0 := 24000
	var a1 := 26000
	var args: Array = OS.get_cmdline_user_args()
	if args.size() > 1:
		a0 = int(args[0]); a1 = int(args[1])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(a0)
	var last := {}
	while g.tick() <= a1:
		g.step()
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			var key: String = "%s|%s" % [a["goal"], a["where"]]
			if last.get(aid, "") != key:
				last[aid] = key
				print("t=%d %s [%s] %s '%s' task %d pos %s" % [g.tick(), a["name"], a["role"], a["where"], a["goal"], int(a["task"]), str((a["pos"] as Vector2) - sim.world.center)])
	quit(0)
