extends SceneTree
## Developer tool: the construction log (planned, started, finished) of the reference
## campaign to a tick, one line per event, with each structure's position.
##   node tools/godot.mjs script res://tests/dev/build_log.gd <tick>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var target := int(OS.get_cmdline_user_args()[0])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	var seen := {}
	while g.tick() < target:
		g.step()
		if g.tick() % 10 != 0:
			continue
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			var k: String = b["state"]
			if seen.get(id, "") != k:
				seen[id] = k
				print("t=%d %s %s %s" % [g.tick(), b["name"], k, str(b.get("pos", "")) if b["kind"] != "link" else "%s-%s" % [sim.state["buildings"].get(b["a"], {}).get("name", "?"), sim.state["buildings"].get(b["b"], {}).get("name", "?")]])
	quit(0)
