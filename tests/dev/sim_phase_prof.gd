extends SceneTree
## SIM probe: worst and mean cost of each once-a-second system, called in its own phase, on a save.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v5.fhsave"
	var secs: int = int(a[1]) if a.size() > 1 else 300
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	sim.run_seconds(10.0)
	var tot := {}
	var mx := {}
	var cnt := 0
	var hz: int = int(sim.bal["tick_hz"])
	for s in secs:
		for i in hz:
			var tick: int = int(sim.state["tick"]) + 1
			var phase: int = tick % hz
			var names := {}
			if phase == 3:
				names = {"explore": func(): sim.explore.tick_second(), "ship": func(): sim.ship.tick_second()}
			if phase == 0:
				names = {"hazards": func(): sim.hazards.tick_second(), "traffic": func(): sim.traffic.tick_second()}
			# These are called a tick early, from outside: only the ones that do not change the order of the step.
			for n in names:
				pass
			sim.step()
		# After the second: time the systems again as a stand-alone call (idempotent enough for a probe).
		for pair in [["explore", func(): sim.explore.tick_second()], ["ship", func(): sim.ship.tick_second()], ["security", func(): sim.security.tick_second()], ["leisure", func(): sim.leisure.tick_second()], ["families", func(): sim.families.tick_second()], ["metrics", func(): sim.metrics.tick_second()], ["prod_crops", func(): sim.prod.crops_second()], ["prod_auto", func(): sim.prod.auto_second()], ["prod_spoil", func(): sim.prod.spoil_second()], ["prod_wear", func(): sim.prod.wear_second()], ["alerts", func(): sim.alerts.tick_second()], ["unrest", func(): sim.unrest.tick()], ["hazards", func(): sim.hazards.tick_second()], ["build", func(): sim.build.tick_second()], ["upgrades", func(): sim.upgrades.tick_second()], ["research", func(): sim.research.tick_second()], ["goals", func(): sim.goals.tick_second()], ["awards", func(): sim.awards.tick_second()], ["vehicles", func(): sim.vehicles.tick_second()], ["reactors", func(): sim.reactors.tick_second()]]:
			var t0: int = Time.get_ticks_usec()
			(pair[1] as Callable).call()
			var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
			tot[pair[0]] = float(tot.get(pair[0], 0.0)) + ms
			mx[pair[0]] = maxf(float(mx.get(pair[0], 0.0)), ms)
		cnt += 1
	var keys: Array = tot.keys()
	keys.sort_custom(func(x, y): return float(mx[x]) > float(mx[y]))
	for k in keys:
		print("  %-12s mean %6.3f ms  worst %6.2f ms" % [k, float(tot[k]) / cnt, float(mx[k])])
	sim.dispose()
	quit(0)
