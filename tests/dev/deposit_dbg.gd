extends SceneTree
## Developer tool: why a mine cannot stand on each deposit at a given day of the reference.
##   node tools/godot.mjs script res://tests/dev/deposit_dbg.gd [seed] [day]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1002
	var day: float = float(args[1]) if args.size() > 1 else 2.0
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	for s in int(day * 600):
		ref.drive()
		sim.run_seconds(1.0)
	var c: Vector2 = sim.world.center
	for d in sim.state["deposits"]:
		var mid := Vector2(d["x"], d["y"])
		var reasons := {}
		for r in [0.0, 2.0, 4.0]:
			for j in 16:
				var p: Vector2 = mid + Vector2(r, 0).rotated(j * TAU / 16.0)
				var why: String = sim.place.check_building("mine", sim.place.snap_pos(p), 0.0)
				reasons[why] = int(reasons.get(why, 0)) + 1
		var near := []
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["kind"] != "link" and (b["pos"] as Vector2).distance_to(mid) < 16.0:
				near.append("%s@%.0f" % [b["def"], (b["pos"] as Vector2).distance_to(mid)])
		print("deposit %d at %.0f m r %.1f: %s near %s" % [d["id"], mid.distance_to(c), float(d["r"]), str(reasons), str(near)])
	quit(0)
