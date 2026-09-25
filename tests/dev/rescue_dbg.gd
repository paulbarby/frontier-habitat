extends SceneTree
## Developer tool: colonists outside who cannot get back to air. Runs the full reference
## campaign to a tick and prints every outside colonist with low air or a rescue flag.
##   node tools/godot.mjs script res://tests/dev/rescue_dbg.gd <tick>
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var target := 3790
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			target = int(a)
	var sim = Sim.new()
	sim.new_game(1001)
	var ref = Reference.new(sim, "all")
	while int(sim.state["tick"]) < target - 600:
		if int(sim.state["tick"]) % 10 == 0:
			ref.drive()
		sim.step()
	var seen := {}
	while int(sim.state["tick"]) < target:
		if int(sim.state["tick"]) % 10 == 0:
			ref.drive()
		sim.step()
		if int(sim.state["tick"]) % 50 != 0:
			continue
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] != "alive" or a["where"] != "out":
				continue
			if float(a["suit"]) > 40.0 and not bool(a["rescue"]):
				continue
			var p: Vector2 = a["pos"]
			var r: Dictionary = sim.nav.nearest_supplied_lock(p)
			print("t=%d %s suit %.0f rescue %s kind %s goal '%s' pos %s walkable %s -> lock %s" % [int(sim.state["tick"]), a["name"], float(a["suit"]), str(a["rescue"]), a["plan_kind"], a["goal"], str(p - sim.world.center), str(sim.nav.is_walkable(p)), str(r)])
			for comp in sim.topo.locks_by_comp:
				for lid in sim.topo.locks_by_comp[comp]:
					var lb: Dictionary = sim.state["buildings"][lid]
					var dp: Vector2 = sim.nav.door_pos(lb)
					var po: Dictionary = sim.nav.path_out(p, dp)
					print("    lock %s supplied %s door %s walkable %s path %s" % [lb["name"], str(sim.util.comp_supplied(comp)), str(dp - sim.world.center), str(sim.nav.is_walkable(dp)), str(po.get("ok"))])
	quit(0)
