extends SceneTree
## Developer tool: for every site blocked by suit range at a tick, the outdoor walk from
## each airlock door to each access point, and the suit budget.
##   node tools/godot.mjs script res://tests/dev/site_reach.gd <tick>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var target := 30000
	var args: Array = OS.get_cmdline_user_args()
	if args.size() > 0:
		target = int(args[0])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(target)
	print("suit cap %.0f s, speed %.2f, task fraction %s" % [sim.agents.suit_cap(), sim.util.out_speed(), str(sim.bal["suit_task_fraction"])])
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["block"]) != "suit_range":
			continue
		var pts: Array = sim.nav.access_points(b)
		print("%s %s pos %s access %s" % [b["name"], b["state"], str(b.get("pos", "")), str(pts)])
		for comp in sim.topo.locks_by_comp:
			for lid in sim.topo.locks_by_comp[comp]:
				var lb: Dictionary = sim.state["buildings"][lid]
				var line := "   %s at %s rot %.2f r %.1f supplied %s door %s:" % [lb["name"], str(lb["pos"]), float(lb["rot"]), float(lb["radius"]), str(sim.util.comp_supplied(comp)), str(sim.nav.door_pos(lb))]
				for q in pts:
					var r: Dictionary = sim.nav.path_out(sim.nav.door_pos(lb), q)
					line += " %s" % str(snappedf(float(r.get("len", -1)), 0.1))
				print(line)
	quit(0)
