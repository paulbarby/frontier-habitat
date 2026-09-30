extends SceneTree
## Developer tool: can a person at a point walk to an airlock (showcase_v4), with and without the
## academy that the v5 enrol test placed at once at (1260.5, 1275)?
##   node tools/godot.mjs script res://tests/dev/pocket_probe.gd [x y]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _check(sim, p: Vector2, label: String) -> void:
	var best := 1e9
	var bdoor := Vector2.ZERO
	for comp in sim.topo.locks_by_comp:
		for lid in sim.topo.locks_by_comp[comp]:
			var d: Vector2 = sim.nav.door_pos(sim.state["buildings"][lid])
			if d.distance_to(p) < best:
				best = d.distance_to(p)
				bdoor = d
	var w = sim.nav.nearest_walkable(p, 6)
	var r: Dictionary = sim.nav.path_out(w if w != null else p, sim.nav.nearest_walkable(bdoor, 6))
	var ret: Dictionary = sim.nav.nearest_supplied_lock(p)
	print("%s: walkable %s, nearest walkable %s, airlock door %s at %.0f m, path ok %s %s, return_secs %s" % [label, str(sim.nav.is_walkable(p)), str(sim.nav.nearest_walkable(p, 6)), str(bdoor.round()), best, str(r.get("ok")), str(r.get("reason", "")), str(ret)])

func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var p := Vector2(1228, 1246)
	if args.size() >= 2:
		p = Vector2(float(args[0]), float(args[1]))
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	_check(sim, p, "before")
	var q := Vector2(1260.5, 1275.0)
	print("academy check: ", sim.place.check_building("academy", q, 0.0, -1, 1))
	var b: Dictionary = sim.build.spawn_active("academy", q, 0.0, 1)
	sim.step()
	_check(sim, p, "after")
	var near: Array = []
	for id in sim.state["buildings"]:
		var s: Dictionary = sim.state["buildings"][id]
		if (s["pos"] as Vector2).distance_to(p) < 60.0:
			near.append("%s %s r%.1f d%.0f" % [s["def"], str((s["pos"] as Vector2).round()), float(s.get("radius", 0.0)), (s["pos"] as Vector2).distance_to(p)])
	print("near: ", near)
	sim.dispose()
	quit(0)
