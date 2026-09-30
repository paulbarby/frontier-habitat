extends SceneTree
## Developer tool: showcase_v4 run to day <from>, then every <step> s: alive, mean health, the lowest
## nutrients, hunger, where people are, the food stock and the kitchens' state.
##   node tools/godot.mjs script res://tests/dev/starve_probe.gd [from_day] [to_day] [step_s]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var from: int = int(a[0]) if a.size() > 0 else 13
	var to: int = int(a[1]) if a.size() > 1 else 16
	var step: float = float(a[2]) if a.size() > 2 else 60.0
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	sim.run_seconds(float(from) * 600.0)
	var n_steps: int = int(float(to - from) * 600.0 / step)
	for s in n_steps:
		sim.run_seconds(step)
		var alive := 0
		var hp := 0.0
		var hun := 0.0
		var lows := {}
		var where := {}
		var goals := {}
		for aid in sim.state["agents"]:
			var x: Dictionary = sim.state["agents"][aid]
			if x["state"] != "alive":
				continue
			alive += 1
			hp += float(x["health"])
			hun += float(x["hunger"])
			for k in x.get("nutrition", {}):
				lows[k] = minf(float(lows.get(k, 100.0)), float(x["nutrition"][k]))
			where[x["where"]] = int(where.get(x["where"], 0)) + 1
			goals[String(x["goal"]).left(18)] = int(goals.get(String(x["goal"]).left(18), 0)) + 1
		var tot: Dictionary = sim.inv.totals()
		var food := {}
		for it in tot:
			if sim.items.is_dish(it) or sim.content["crops"].has(it):
				if int(tot[it]["total"]) > 0:
					food[it] = int(tot[it]["total"])
		var lw := {}
		for k in lows:
			lw[k] = int(lows[k])
		print("t%.0f alive %d hp %.0f hunger %.0f low %s where %s food %s" % [sim.seconds(), alive, hp / maxf(1, alive), hun / maxf(1, alive), str(lw), str(where), str(food)])
		print("   goals ", goals)
		var locs: Array = []
		for inv_id in sim.state["inventories"]:
			var inv: Dictionary = sim.state["inventories"][inv_id]
			var items: Dictionary = inv["items"]
			for it in items:
				if (sim.items.is_dish(it) or it == "meals") and int(items[it]) > 0:
					locs.append("%s %s/%s:%s x%d held %d" % [inv["role"], str(inv.get("ot", "")), str(inv.get("oid", "")), it, int(items[it]), int(inv["held_out"].get(it, 0))])
		print("   food at ", locs.slice(0, 8))
		if alive == 0:
			break
	sim.dispose()
	quit(0)
