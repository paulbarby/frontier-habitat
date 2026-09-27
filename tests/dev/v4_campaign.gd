extends SceneTree
## Developer tool: the reference campaign ("all") on the v4 map (scenario "frontier").
##   node tools/godot.mjs script res://tests/dev/v4_campaign.gd [days] [seed]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const H = preload("res://tests/helpers.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var days: int = int(a[0]) if a.size() > 0 else 3
	var seed_value: int = int(a[1]) if a.size() > 1 else 1001
	var sim = Sim.new()
	sim.new_game(seed_value, "frontier")
	var ref = Reference.new(sim, "all")
	for d in days:
		var t0: int = Time.get_ticks_usec()
		for s in 600:
			ref.drive()
			sim.run_seconds(1.0)
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / 6000.0
		print("day %d: pop %d deaths %d stage %d techs %d structures %d windows %d | %.2f ms/tick | audit %s" % [d + 1, sim.alive_count(), int(sim.state["progress"]["deaths"]), int(sim.state["progress"]["stage"]), sim.state["research"]["done"].size(), sim.state["buildings"].size(), sim.nav.wins.size(), ms, str(sim.inv.audit())])
	print("refused: ", H.refused_commands(sim).slice(0, 10))
	print("failures: ", ref.failures)
	quit(0)
