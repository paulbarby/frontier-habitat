extends SceneTree
## Developer tool: the deposits near the start of a reference game and what stands on them.
##   node tools/godot.mjs script res://tests/dev/dep_near.gd <tick>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")
func _init() -> void:
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	g.run_to_tick(int(OS.get_cmdline_user_args()[0]))
	var sim = g.sim
	for d in sim.state["deposits"]:
		var p := Vector2(d["x"], d["y"])
		if p.distance_to(sim.world.center) > 200.0:
			continue
		var near := ""
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["kind"] != "link" and (b["pos"] as Vector2).distance_to(p) < float(b["radius"]) + float(d["r"]) + 3.0:
				near += " %s(%s)" % [b["name"], b["state"]]
		print("deposit at %s (%.0f m, r %.1f, ore %d):%s" % [str(p - sim.world.center), p.distance_to(sim.world.center), float(d["r"]), int(d["ore"]), near])
	quit(0)
