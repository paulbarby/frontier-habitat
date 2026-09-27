extends SceneTree
## Developer tool: the reference campaign with balance overrides, one line a day: people,
## deaths, food stock, the colony's nutrient means, the lowest colonist value and the dishes.
##   node tools/godot.mjs script res://tests/dev/nutri_days.gd <days> key=value ...
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const H = preload("res://tests/helpers.gd")

func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var days: int = int(args[0])
	var probe = Sim.new()
	for a in args.slice(1):
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() == 2:
			probe.content["balance"][kv[0]] = float(kv[1])
	probe.dispose()
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	for d in range(1, days + 1):
		g.run_to_tick(d * 6000)
		var tot: Dictionary = sim.inv.totals()
		var food := {}
		for it in tot:
			if sim.items.is_dish(it) or sim.content["crops"].has(it):
				food[it] = int(tot[it]["total"])
		var lo := 100.0
		var lo_k := ""
		var sums := {}
		var n := 0
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] != "alive" or not a.has("nutrition"):
				continue
			n += 1
			for k in a["nutrition"]:
				sums[k] = float(sums.get(k, 0.0)) + float(a["nutrition"][k])
				if float(a["nutrition"][k]) < lo:
					lo = float(a["nutrition"][k])
					lo_k = k
		var means := {}
		for k in sums:
			means[k] = int(sums[k] / maxf(1, n))
		print("day %d pop %d deaths %d | means %s low %s %.0f | food %s" % [d, sim.alive_count(), int(sim.state["progress"]["deaths"]), str(means), lo_k, lo, str(food)])
	quit(0)
