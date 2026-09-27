extends SceneTree
## Developer tool: the day each goal of the reference campaign is done, and the chapters.
##   node tools/godot.mjs script res://tests/dev/goal_days.gd <days>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")
func _init() -> void:
	var days: int = int(OS.get_cmdline_user_args()[0])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(days * 6000)
	var rows: Array = []
	for gid in sim.state["goals"]["status"]:
		var gs: Dictionary = sim.state["goals"]["status"][gid]
		rows.append([float(int(gs.get("done_tick", -1))) / 6000.0 + 1.0 if gs["state"] == "done" else 99.0, gid, gs["state"]])
	rows.sort()
	for r in rows:
		print("%-5.1f %s %s" % r)
	for i in (sim.content["chapters"] as Array).size():
		var ch: Dictionary = sim.content["chapters"][i]
		print("chapter %d goals %s" % [i + 1, str(ch.get("goals", []))])
	print("ship ", sim.state["ship"]["stage"], " techs ", sim.state["research"]["done"])
	quit(0)
