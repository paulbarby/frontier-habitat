extends SceneTree
## Developer tool: the reference campaign ("all"), one line a day: pop, deaths by cause,
## the worst alerts, and the log lines of deaths.
##   node tools/godot.mjs script res://tests/dev/death_days.gd <days>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var days: int = int(OS.get_cmdline_user_args()[0])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	var seen_log := 0
	for d in range(1, days + 1):
		g.run_to_tick(d * 6000)
		var issues: Array = []
		for k in sim.state["issues"]:
			var iss: Dictionary = sim.state["issues"][k]
			if int(iss["severity"]) >= 3:
				issues.append(String(iss["text"]).substr(0, 90))
		var f: Dictionary = sim.metrics.forecast()
		print("day %d pop %d deaths %d meals %d water %.0f o2 %.1f/%.1f energy %.0f | crit: %s" % [d, sim.alive_count(), int(sim.state["progress"]["deaths"]), int(f["meals"]), float(f["water"]), float(f["o2_make"]), float(f["o2_need"]), float(f["energy"]), str(issues)])
		var lg: Array = sim.state["log"]
		for e in lg:
			if int(e["tick"]) > seen_log and (String(e["code"]) == "death" or String(e["code"]).begins_with("hazard_start")):
				print("    t=%d %s" % [int(e["tick"]), e["text"]])
		if not lg.is_empty():
			seen_log = int(lg.back()["tick"])
	quit(0)
