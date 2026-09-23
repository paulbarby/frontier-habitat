extends SceneTree
## Quick look at one reference game. usage:
##   godot --headless --path . --script res://tests/smoke.gd -- [seed] [days]

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1001
	var days: float = float(args[1]) if args.size() > 1 else 3.0
	var t0: int = Time.get_ticks_msec()
	var sim = Sim.new()
	sim.new_game(seed_value)
	print("world: effective seed %d after %d attempts, %d ms" % [sim.world.effective_seed, sim.world.attempts, Time.get_ticks_msec() - t0])
	var ref = Reference.new(sim)
	var total: int = int(days * 600)
	for s in total:
		ref.drive()
		sim.run_seconds(1.0)
		if (s + 1) % 100 == 0 or s == total - 1:
			_report(sim)
	for e in sim.state["log"]:
		if e["code"] in ["unreachable", "death", "crop_lost", "broken"]:
			print("  LOG t=%d %s" % [int(e["tick"]) / 10, e["text"]])
	print("audit: ", sim.inv.audit())
	print("sim time %.0f s, wall %d ms" % [sim.seconds(), Time.get_ticks_msec() - t0])
	for c in sim.state["commands"]:
		if not c["ok"]:
			print("  REFUSED command: ", c["kind"], " ", c["payload"], " -> ", c["code"])
	quit(0)

func _report(sim) -> void:
	var st: Dictionary = sim.state
	var active := 0
	var planned := 0
	for id in st["buildings"]:
		if st["buildings"][id]["state"] == "active":
			active += 1
		else:
			planned += 1
	var f: Dictionary = sim.metrics.forecast()
	var o2 := 0.0
	for comp in sim.util.atmo_stats:
		o2 += sim.util.units(int(sim.util.atmo_stats[comp]["stock"]))
	var avg := {"hunger": 0.0, "thirst": 0.0, "fatigue": 0.0, "health": 0.0}
	var where := {}
	for aid in st["agents"]:
		var a: Dictionary = st["agents"][aid]
		if a["state"] != "alive":
			continue
		for k in avg:
			avg[k] += float(a[k]) / maxf(1.0, float(f["pop"]))
		where[a["goal"]] = int(where.get(a["goal"], 0)) + 1
	print("d%d %5.0fs pop %d | built %d plan %d | meals %d water %.0f o2 %.2f E %.1f/%.0f | hun %.0f thi %.0f fat %.0f hp %.0f | tasks %d | stage %d tut %d" % [
		sim.util.day_number(), sim.util.day_time(), f["pop"], active, planned, f["meals"], f["water"], o2, f["energy"], f["energy_cap"],
		avg["hunger"], avg["thirst"], avg["fatigue"], avg["health"], st["tasks"].size(), st["progress"]["stage"], st["progress"]["tutorial_step"]])
	print("      doing: ", where)
	var inc: Array = sim.alerts.incidents()
	for i in inc:
		if int(i["issue"]["severity"]) >= 2:
			print("      ALERT[%d] %s  (+%d consequences)" % [i["issue"]["severity"], i["issue"]["text"], i["consequences"].size()])
