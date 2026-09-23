extends SceneTree
## Developer tool: airlocks, the Meridian and suit reach at a day of the reference campaign.
##   node tools/godot.mjs script res://tests/dev/locks_dbg.gd [seed] [day]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1004
	var day: float = float(args[1]) if args.size() > 1 else 24.0
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	for s in int(day * 600):
		ref.drive()
		sim.run_seconds(1.0)
	var c: Vector2 = sim.world.center
	print("reach %.0f m, lander %s" % [sim.agents.suit_reach_metres(), str(c)])
	var ship: Dictionary = sim.ship.record()
	print("ship at %s (%.0f m)" % [str(ship["pos"]), (ship["pos"] as Vector2).distance_to(c)])
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if bool(sim.bdef(b["def"]).get("airlock", false)) or b["def"] == "junction":
			var al := ""
			for k in ref.alias:
				if int(ref.alias[k]) == int(id):
					al += k + " "
			print("%s %d [%s] at %s d_ship %.0f state %s block '%s' supplied %s" % [b["def"], id, al, str(b["pos"]), Vector2(b["pos"]).distance_to(ship["pos"]), b["state"], b["block"], str(sim.util.building_supplied(id))])
	for f in ref.failures:
		print("REF ", f)
	if ref.alias.has("LW"):
		var lw: Dictionary = sim.state["buildings"].get(ref.alias["LW"], {})
		print("LW links:")
		for id in sim.state["buildings"]:
			var l: Dictionary = sim.state["buildings"][id]
			if l["kind"] == "link" and (int(l["a"]) == int(lw["id"]) or int(l["b"]) == int(lw["id"])):
				print("  %s %d-%d state %s block '%s'" % [l["def"], l["a"], l["b"], l["state"], l["block"]])
		print("LW site items ", sim.inv.get_inv(lw["inv_site"]).get("items", {}), " cost ", sim.bd(lw).get("cost", {}), " progress ", lw["progress"])
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if int(t["bld"]) == int(lw["id"]):
				print("  task ", t["kind"], " ", t["state"], " reason ", t.get("reason", ""), " retry ", t["retry"])
	quit(0)
