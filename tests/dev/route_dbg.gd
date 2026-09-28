extends SceneTree
## Developer tool: why the showcase route rover has no route (ends, areas, pockets, A*).
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	var nav = sim.nav
	var v: Dictionary = sim.vehicles.get_v(int(sim.vehicles.list()[0]["id"]))
	var bay: Dictionary = sim.vehicles.bay_of(v)
	var camp: Vector2 = sim.vehicles.dock_point(2, v)
	print("bay %s exit %s taxi clear %s; camp dock %s" % [str(bay.get("pos")), str(bay.get("exit")), str(nav.taxi_clear(bay["pos"], bay["exit"])) if not bay.is_empty() else "-", str(camp)])
	for p in [bay.get("exit", v["pos"]), camp]:
		var c = nav._rover_end(p)
		if c == null:
			print("  end %s: no open cell" % str(p))
			continue
		var a: int = nav._rover_area(c)
		print("  end %s: cell %s area %d pocket %s (cells so far %d)" % [str(p), str(c), a, str(nav._rpocket.has(a)), nav._rcc.count(a)])
	var d: Dictionary = sim.state["buildings"][int(v["depot"])]
	print("apron open %s; depot at %s r %.1f rot %.2f" % [str(nav._apron_open({"pos": d["pos"], "bays": sim.vehicles.bays(d)})), str(d["pos"]), float(d["radius"]), float(d["rot"])])
	var e: Vector2 = bay["exit"]
	var c0 := Vector2i(int(e.x / 8), int(e.y / 8))
	var line := ""
	for dy in range(-4, 5):
		line = ""
		for dx in range(-4, 5):
			var q := Vector2i(c0.x + dx, c0.y + dy)
			if nav.rover.is_point_solid(q):
				line += "#"
			elif nav._rover_clear(e, Vector2((q.x + 0.5) * 8, (q.y + 0.5) * 8)):
				line += "."
			else:
				line += "x"
		print("   " + line)
	for t in nav._tubes:
		if (t[0] as Vector2).distance_to(e) < 60.0:
			print("   tube %s-%s" % [str(t[0]), str(t[1])])
	for dd in nav._discs:
		if (dd[0] as Vector2).distance_to(e) < 40.0:
			print("   disc %s r %.1f" % [str(dd[0]), float(dd[1])])
	var ca = nav._rover_end(bay["exit"])
	var cb = nav._rover_end(camp)
	if ca != null and cb != null:
		var raw: PackedVector2Array = nav.rover.get_point_path(ca, cb)
		print("A* %d points" % raw.size())
	sim.dispose()
	quit(0)
