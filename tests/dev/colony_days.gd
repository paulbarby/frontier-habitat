extends SceneTree
## Developer tool: a save run for N game days; one line a day: alive, deaths by cause, unrest,
## mean satisfaction and attitude, food and water stock.
##   node tools/godot.mjs script res://tests/dev/colony_days.gd [save] [days]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v4.fhsave"
	var days: int = int(a[1]) if a.size() > 1 else 30
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	for d in days:
		sim.run_seconds(600.0)
		var alive := 0
		var causes := {}
		var sat := 0.0
		var att := 0.0
		var n := 0
		var nowork := 0
		for aid in sim.state["agents"]:
			var x: Dictionary = sim.state["agents"][aid]
			if x["state"] == "alive":
				alive += 1
				if x.has("v5_nowork"):
					nowork += 1
				var r: Dictionary = sim.people.rec_of(int(aid))
				if not r.is_empty():
					sat += float(r["sat"])
					att += float(r["att"])
					n += 1
			elif x["state"] == "dead":
				causes[x.get("cause", "?")] = int(causes.get(x.get("cause", "?"), 0)) + 1
		var u: Dictionary = sim.unrest.info(-1)
		print("day %d: alive %d, no work %d, deaths %s, unrest %.0f %s (%s), sat %.0f att %.0f, issues %s" % [d + 1, alive, nowork, str(causes), float(u["value"]), u["stage"], u["demand"], sat / maxf(1, n), att / maxf(1, n), str(sim.state["issues"].keys().slice(0, 6))])
		if alive == 0:
			break
	sim.dispose()
	quit(0)
