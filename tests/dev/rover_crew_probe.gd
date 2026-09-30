extends SceneTree
## Developer tool: the v5_appoint_home_enrol set-up (an academy placed at once near the lander),
## then the vehicle of one colonist every 20 s: state, returning, near air, route, crew needs.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	sim.run_seconds(10.0)
	var args: Array = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "academy":
		var spot := Vector2(-1, -1)
		var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
		for rr in range(20, 200, 6):
			for k in 24:
				var q: Vector2 = sim.place.snap_pos(lander + Vector2(rr, 0).rotated(TAU * float(k) / 24.0))
				if spot.x < 0.0 and sim.place.check_building("academy", q, 0.0, -1, 1) == "ok":
					spot = q
			if spot.x >= 0.0:
				break
		print("academy at ", spot, " ", sim.build.spawn_active("academy", spot, 0.0, 1).get("id"))
	var a: Dictionary = sim.state["agents"][86]
	if args.size() > 1 and args[1] == "class":
		a["v5_nowork"] = true   # probe: the no-work flag of a student
	var vid: int = int(a.get("veh", -1))
	var out_n := 0
	for s in 60:
		sim.run_seconds(10.0 if a["where"] != "vehicle" else 20.0)
		if args.size() > 1 and args[1] == "class":
			a["v5_nowork"] = true
		var v: Dictionary = sim.vehicles.get_v(vid)
		if a["where"] == "vehicle":
			print("t%d agent %s thirst %.0f hp %.0f | %s state %s returning %s near_air %s pos %s" % [(s + 1) * 20, a["state"], float(a["thirst"]), float(a["health"]), v.get("name"), v.get("state"), str(v.get("returning")), str(sim.vehicles.near_air(v)), str((v["pos"] as Vector2).round())])
		else:
			out_n += 1
			print("out: %s where %s suit %.0f hp %.0f th %.0f fa %.0f kind %s goal '%s' plan %d rescue %s ret %s pos %s bld %d cause %s" % [a["state"], a["where"], float(a["suit"]), float(a["health"]), float(a["thirst"]), float(a["fatigue"]), a["plan_kind"], a["goal"], (a["plan"] as Array).size(), str(a.get("rescue")), str(a.get("return_secs")), str((a["pos"] as Vector2).round()), int(a["bld"]), str(a.get("cause"))])
			if a["state"] != "alive" or out_n > 25 or a["where"] == "in":
				break
	sim.dispose()
	quit(0)
