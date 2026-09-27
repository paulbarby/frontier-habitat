extends SceneTree
## RENDER check (V4 vehicles on SIM's records): a frontier game, a rover depot L with a small
## rover, a medium rover and a hopper at its bays (spawned the way SIM builds them), crew sent to
## board, a drive, a hop and a vehicle order at the depot. Prints the view's state every 2 s.
##   node tools/godot.mjs script res://tools/render_vehicle_sim.gd
var main
var n := 0
var ids := {}
var depot := {}
var sent := {}

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n == 3:
		main.start_new(1001, {"scenario": "frontier"})
		main.set_speed(1)
	if n == 5:
		var sim = main.sim
		var c: Vector2 = sim.world.center
		depot = sim.build.spawn_active("rover_depot", c + Vector2(40, -30), 0.0, 2)
		var bays: Array = sim.vehicles.bays(depot)
		print("depot %d bays %s" % [int(depot["id"]), str(bays.map(func(b): return [b["i"], b["kind"], b["pos"]]))])
		for e in [["small_rover", 0], ["hopper", 1], ["medium_rover", 2]]:
			var bay: Dictionary = bays[mini(int(e[1]), bays.size() - 1)]
			var v: Dictionary = sim.vehicles.spawn(e[0], bay["pos"], int(depot["id"]))
			v["bay"] = int(bay["i"])
			v["rot"] = float(bay.get("rot", 0.0))
			ids[e[0]] = int(v["id"])
		v_charge_low()
		var crew: Array = sim.state["agents"].keys().slice(0, 4)
		print("board small: ", sim.submit("vehicle_board", {"id": ids["small_rover"], "agents": crew.slice(0, 2)}))
		print("board hopper: ", sim.submit("vehicle_board", {"id": ids["hopper"], "agents": crew.slice(2, 3)}))
	if n > 5:
		main.set_process(false)
		main._process(1.0 / 30.0)
		var f: int = n - 5
		var sim = main.sim
		var c: Vector2 = sim.world.center
		var vs: Dictionary = sim.vehicles.get_v(ids["small_rover"])
		if not sent.has("s") and (vs["crew"] as Array).size() >= 1:
			sent["s"] = f
		if sent.has("s") and not sent.has("sd") and f - int(sent["s"]) > 30 * 4:
			sent["sd"] = true
			print("t %d drive: " % (f / 30), sim.submit("vehicle_drive", {"id": ids["small_rover"], "x": c.x + 180.0, "y": c.y + 60.0}))
		var vh: Dictionary = sim.vehicles.get_v(ids["hopper"])
		if not sent.has("h") and (vh["crew"] as Array).size() >= 1:
			sent["h"] = true
			print("t %d hop: " % (f / 30), sim.submit("vehicle_drive", {"id": ids["hopper"], "x": c.x - 250.0, "y": c.y + 200.0}))
		if f == 30 * 20:
			depot["vorder"] = {"kind": "small_rover", "progress": 3.0, "work_total": 10.0, "state": "work", "cost": {}, "inv": -1, "block": ""}
		if f % 60 == 0:
			var rows: Array = sim.vehicles.list()
			var s := "t %3d" % (f / 30)
			for r in rows:
				s += " | %s %s crew %s pos %s hop %s" % [r["kind"], r["state"], str(r["crew"]), str((r["pos"] as Vector2).snappedf(0.1)), str(r.get("hopping", false))]
			print(s)
			var raw: String = main.view.debug_cmd("vinfo")
			if JSON.parse_string(raw) == null:
				print("   RAW ", raw.substr(0, 600))
				return false
			var vi: Array = JSON.parse_string(raw)
			print("   view: ", ", ".join(vi.map(func(x): return "%s %s pos %s hgt %s spd %s crew %s" % [x["kind"], x["mode"], str(x["pos"]), str(x["hgt"]), str(x["speed"]), str((x["crew"] as Array).map(func(c): return String(c).get_slice(" ", 0)))])))
			print("   builds: %d, hidden agents %d" % [main.view.vehicles._builds.size(), main.view.vehicles._hide.size()])
		# A save for the web shots: crew aboard, the rover and the hopper under way, an order at the depot.
		if sent.has("h") and not sent.has("saved") and (sim.vehicles.get_v(ids["hopper"])["state"] == "driving") and sim.vehicles.get_v(ids["small_rover"])["state"] == "driving":
			sent["saved"] = true
			var fs := FileAccess.open("res://build/web_render/vehicles.fhsave", FileAccess.WRITE)
			fs.store_buffer(sim.save_bytes())
			fs.close()
			print("saved vehicles.fhsave at t %d" % (f / 30))
		if f > 30 * 60:
			return true
	return false

func v_charge_low() -> void:
	for k in ids:
		var v: Dictionary = main.sim.vehicles.get_v(ids[k])
		v["charge"] = float(v["charge"]) * 0.5
