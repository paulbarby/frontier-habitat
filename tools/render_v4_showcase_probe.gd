extends SceneTree
## RENDER check on content/saves/showcase_v4.fhsave (debug on): the view's state for vehicles,
## reactor stages (debug reactor_stage), zones, fog, POIs, satellites. Prints every 2 s.
##   node tools/godot.mjs script res://tools/render_v4_showcase_probe.gd
var main
var n := 0
var rid := -1

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n == 3:
		var ua: PackedStringArray = OS.get_cmdline_user_args()
		main._import_bytes(FileAccess.get_file_as_bytes(ua[0] if ua.size() > 0 else "res://content/saves/showcase_v4.fhsave"))
		main.sim.state["options"]["debug"] = true
		main.set_speed(4)
		var st: Dictionary = JSON.parse_string(main.view.debug_cmd("v4state"))
		print("STATE ", JSON.stringify(st).substr(0, 2500))
		for r in (st.get("reactors", []) as Array):
			rid = int(r[0])
	if n > 3:
		main.set_process(false)
		main._process(1.0 / 30.0)
		var f: int = n - 3
		var sim = main.sim
		if f == 30 * 4 and rid >= 0:
			print("stage warning: ", sim.submit("reactor_stage", {"id": rid, "stage": "warning"}))
		if f == 30 * 8 and rid >= 0:
			print("stage critical: ", sim.submit("reactor_stage", {"id": rid, "stage": "critical"}))
		if f == 30 * 12 and rid >= 0:
			print("stage breach: ", sim.submit("reactor_stage", {"id": rid, "stage": "breach"}))
			# (SIM's debug breach sets the heat to 100 and the coolant takes it back under 100 in the same
			# second: one second later the probe pushes it over, reported to SIM)
		if f == 30 * 13 and rid >= 0 and sim.state["buildings"].has(rid):
			sim.reactors.rx(sim.state["buildings"][rid])["heat"] = 130.0
		if f == 30 * 16:
			var c: Vector2 = sim.world.center
			print("reveal: ", sim.submit("reveal", {"x": c.x + 600.0, "y": c.y - 300.0, "r": 400.0}))
		if f % 60 == 0:
			var v = main.view
			print("t %2d reactor %s zones %d | pois %s sats %s | vehicles %s | fog rev %d | flash %.1f at %s blasts %d" % [f / 30, str(v.reactor.stages.values().map(func(s): return s["stage"])), v.reactor.zones.size(),
				str(v.explore.stats["pois"]), str(v.explore.stats["sats"]), str(v.vehicles.stats["vehicles"]), v.terrain.fog_rev, v.reactor._flash.light_energy, str(v.reactor._flash.position.round()), int(v.reactor.stats.get("sim_blasts", 0))])
		if f > 30 * 45:
			var st2: Dictionary = JSON.parse_string(main.view.debug_cmd("v4state"))
			print("END ", JSON.stringify(st2).substr(0, 1500))
			return true
	return false
