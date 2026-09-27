extends SceneTree
## Developer tool: the haul tasks of one item in the reference campaign at a tick, and
## the colonists' goals (who is busy with what).
##   node tools/godot.mjs script res://tests/dev/haul_probe.gd <tick> <item>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var tick: int = int(a[0])
	var item: String = String(a[1]) if a.size() > 1 else "ore"
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(tick)
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if String(t.get("res", "")) != item:
			continue
		print("task %d %s cat %s owner %d state %s retry %d reason '%s' fails %d src %d dst %d qty %d score? emergency %d" % [tid, t["kind"], t["cat"], int(t["owner"]), t["state"], int(t["retry"]) - tick, t.get("reason", ""), int(t["fails"]), int(t["src"]), int(t["dst"]), int(t["qty"]), int(t["emergency"])])
	var goals := {}
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		var k: String = String(ag["goal"]).split(" ")[0]
		goals[k] = int(goals.get(k, 0)) + 1
	print("goals: ", goals)
	for aid in sim.state["agents"]:
		var ag2: Dictionary = sim.state["agents"][aid]
		if String(ag2["goal"]) != "Idle":
			continue
		print("idle %s [%s] where %s pos %s suit %.0f backoff %d" % [ag2["name"], ag2["role"], ag2["where"], str(ag2["pos"]), float(ag2["suit"]), (ag2["backoff"] as Dictionary).size()])
		var n := 0
		for tid in sim.state["tasks"]:
			var t3: Dictionary = sim.state["tasks"][tid]
			if int(t3["owner"]) != -1 or t3["state"] != "open" or String(t3.get("res", "")) != item:
				continue
			n += 1
			if n > 4:
				break
			var pl: Dictionary = sim.agents._plan_for_task(ag2, t3)
			print("   task %d role '%s' score %.1f plan %s %s src pos %s" % [tid, t3["role"], sim.jobs.score(t3, ag2), str(pl["ok"]), str(pl.get("reason", pl.get("goal", ""))), str(sim.inv.position_of(int(t3["src"])))])
	print("priorities: ", sim.state["policies"]["priority"])
	var open := {}
	for tid in sim.state["tasks"]:
		var t2: Dictionary = sim.state["tasks"][tid]
		var k2: String = "%s/%s/%s" % [t2["kind"], t2["cat"], t2["state"]]
		open[k2] = int(open.get(k2, 0)) + 1
	print("tasks: ", open)
	quit(0)
