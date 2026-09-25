extends SceneTree
## Developer tool: every refused player command and driver failure in the reference
## campaign ("all") up to a day, plus population.
##   node tools/godot.mjs script res://tests/dev/refusals.gd <days>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var days := float(OS.get_cmdline_user_args()[0])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	var seen := 0
	while g.tick() < int(days * 6000):
		g.step()
		if g.tick() % 6000 == 0:
			print("day %d pop %d deaths %d stage %d ship %d" % [g.tick() / 6000, sim.alive_count(), int(sim.state["progress"]["deaths"]), int(sim.state["progress"]["stage"]), int(sim.state["ship"]["stage"])])
	print("refused: ", H.refused_commands(sim))
	print("failures: ", g.ref.failures)
	quit(0)
