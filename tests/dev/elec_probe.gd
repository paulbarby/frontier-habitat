extends SceneTree
## Developer tool: where electronics go in the reference campaign (balance overrides allowed):
## per day produced / consumed, the electronics fab's state, and who holds electronics.
##   node tools/godot.mjs script res://tests/dev/elec_probe.gd <from_day> <to_day> key=value ...
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const H = preload("res://tests/helpers.gd")

func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var d0: int = int(args[0])
	var d1: int = int(args[1])
	var probe = Sim.new()
	for a in args.slice(2):
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() == 2:
			probe.content["balance"][kv[0]] = float(kv[1])
	probe.dispose()
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	var prev_p := 0
	var prev_c := 0
	for day in range(1, d1 + 1):
		g.run_to_tick(day * 6000)
		if day < d0:
			prev_p = int(sim.state["metrics"]["produced"].get("electronics", 0))
			prev_c = int(sim.state["stats"].get("consumed", {}).get("electronics", 0))
			continue
		var p: int = int(sim.state["metrics"]["produced"].get("electronics", 0))
		var c: int = int(sim.state["stats"].get("consumed", {}).get("electronics", 0))
		var fabs: Array = []
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["def"] == "electronics_fab" or b["def"] == "research_assembler" or b["def"] == "glassworks" or b["def"] == "regolith_harvester":
				fabs.append("%s %s blk '%s' rec %s in %s out %s" % [b["def"], b["state"], b["block"], sim.prod.recipe_id(b), str(sim.inv.get_inv(int(b["inv_in"])).get("items", {})) if int(b["inv_in"]) != -1 else "-", str(sim.inv.get_inv(int(b["inv_out"])).get("items", {})) if int(b["inv_out"]) != -1 else "-"])
		var holders := {}
		for hid in sim.state["holds"]:
			var h: Dictionary = sim.state["holds"][hid]
			if h["res"] == "electronics" and h["dir"] == "in":
				var inv: Dictionary = sim.inv.get_inv(int(h["inv"]))
				var who: String = str(inv.get("role", "?"))
				if inv.get("ot", "") == "b":
					who += ":" + String(sim.state["buildings"].get(int(inv["oid"]), {}).get("def", "?")) + ":" + String(sim.state["buildings"].get(int(inv["oid"]), {}).get("state", "?"))
				holders[who] = int(holders.get(who, 0)) + int(h["qty"])
		var bps: Array = []
		for id in sim.state["buildings"]:
			var b2: Dictionary = sim.state["buildings"][id]
			if b2["state"] == "blueprint" and String(b2["block"]) != "":
				bps.append("%s:%s" % [b2["def"], b2["block"]])
		print("day %d: electronics made %d used %d; stock %d | silicate %d metal %d | holds in %s | waiting %s" % [day, p - prev_p, c - prev_c,
			int(sim.inv.totals().get("electronics", {}).get("total", 0)), int(sim.inv.totals().get("silicate", {}).get("total", 0)), int(sim.inv.totals().get("metal", {}).get("total", 0)), str(holders), str(bps)])
		for f in fabs:
			print("   " + f)
		prev_p = p
		prev_c = c
	quit(0)
