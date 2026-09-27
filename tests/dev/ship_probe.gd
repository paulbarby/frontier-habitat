extends SceneTree
## Developer tool: the Meridian repair in the reference campaign, one line a day from a day
## on: stage, phase, what the stage still needs, the fabricator and the hull plate stock.
##   node tools/godot.mjs script res://tests/dev/ship_probe.gd <from_day> <to_day>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var d0: int = int(a[0]) if a.size() > 0 else 18
	var d1: int = int(a[1]) if a.size() > 1 else 30
	for extra in a.slice(2):
		var kv: PackedStringArray = String(extra).split("=")
		if kv.size() == 2:
			var probe = preload("res://sim/sim.gd").new()
			probe.content["balance"][kv[0]] = float(kv[1])
			probe.dispose()
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	for day in range(1, d1 + 1):
		g.run_to_tick(day * 6000)
		if day < d0:
			continue
		var s: Dictionary = sim.state["ship"]
		var tot: Dictionary = sim.inv.totals()
		var line := "day %d: ship stage %d phase %s | plates %d metal %d polymer %d composite %d electronics %d spares %d | techs %d active %s" % [day, int(s["stage"]), str(s.get("phase", "")),
			int(tot.get("hull_plate", {}).get("total", 0)), int(tot.get("metal", {}).get("total", 0)), int(tot.get("polymer", {}).get("total", 0)),
			int(tot.get("composite", {}).get("total", 0)), int(tot.get("electronics", {}).get("total", 0)), int(tot.get("spare_parts", {}).get("total", 0)),
			sim.state["research"]["done"].size(), str(sim.state["research"]["active"])]
		print(line)
		print("   ship ", sim.ship.status() if sim.ship.has_method("status") else s)
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["def"] in ["fabricator", "refinery", "mine", "workshop", "polymer_plant"]:
				print("   %s %s L%d block '%s' recipe %s in %s out %s" % [b["name"], b["state"], int(b.get("level", 1)), b["block"], sim.prod.recipe_id(b),
					str(sim.inv.get_inv(int(b["inv_in"])).get("items", {})), str(sim.inv.get_inv(int(b["inv_out"])).get("items", {}))])
	quit(0)
