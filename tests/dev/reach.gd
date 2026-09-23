extends SceneTree
## Developer tool: plays the campaign to a day, then prints for every blueprint the walk
## from the nearest supplied airlock to its access points and whether the suit allows it.
##   node tools/godot.mjs script res://tests/dev/reach.gd -- [seed] [day] [group]

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1001
	var day: float = float(args[1]) if args.size() > 1 else 7.0
	var group: String = args[2] if args.size() > 2 else "all"
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, group)
	for s in int((day - 1.0) * 600):
		ref.drive()
		sim.run_seconds(1.0)
	var c: Vector2 = sim.world.center
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		var rel: Vector2 = (b["pos"] as Vector2) - c
		var line := "%-20s %-9s (%5.1f,%5.1f) block '%s'" % [b["name"], b["state"], rel.x, rel.y, b["block"]]
		if b["kind"] != "link" and b["state"] == "blueprint":
			var pts: Array = sim.nav.access_points(b)
			var best := 1e9
			for p in pts:
				var r: Dictionary = sim.nav.nearest_supplied_lock(p)
				if r["ok"]:
					best = minf(best, float(r["seconds"]))
			line += "  access %d, walk back %.1f s" % [pts.size(), best]
		if b["kind"] != "link":
			print(line)
		else:
			var ba: Dictionary = sim.state["buildings"].get(b["a"], {})
			var bb: Dictionary = sim.state["buildings"].get(b["b"], {})
			print("   %s %s %s-%s block '%s' health %.0f" % [b["name"], b["state"], ba.get("name", "?"), bb.get("name", "?"), b["block"], float(b["health"])])
	for e in sim.state["log"]:
		if e["code"] in ["demolished", "cancelled", "broken", "death", "unreachable"]:
			print("LOG t=%d %s" % [int(e["tick"]) / 10, e["text"]])
	for comp in sim.topo.locks_by_comp:
		for lid in sim.topo.locks_by_comp[comp]:
			var l: Dictionary = sim.state["buildings"][lid]
			print("lock %s supplied %s door (%.1f,%.1f)" % [l["name"], str(sim.util.comp_supplied(comp)), sim.nav.door_pos(l).x - c.x, sim.nav.door_pos(l).y - c.y])
	# A map of the walkable cells around the base: '#' solid, '.' free, 'D' doors.
	var rows: Array = []
	for y in range(-50, 51, 2):
		var row := ""
		for x in range(-40, 81, 2):
			var p := c + Vector2(x, y)
			row += "." if sim.nav.is_walkable(p) else "#"
		rows.append(row)
	for r in rows:
		print(r)
	quit(0)
