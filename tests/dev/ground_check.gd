extends SceneTree
## Developer tool: the sim ground height range under every structure footprint and along
## every corridor of a save (max - min of world.height_at over a sample grid).
##   node tools/godot.mjs script res://tests/dev/ground_check.gd [save name] [id ...]

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var name: String = args[0] if args.size() > 0 else "showcase_v3_late"
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/%s.fhsave" % name))
	var sim = Sim.new()
	sim.load_state(dec["state"])
	var w = sim.world
	var worst := 0.0
	var worst_name := ""
	var over := 0
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["def"] == "meridian":
			continue
		var lo := 1e9
		var hi := -1e9
		if b["kind"] == "link":
			for k in 21:
				var p: Vector2 = (b["p0"] as Vector2).lerp(b["p1"], float(k) / 20.0)
				for off in [-1.2, 0.0, 1.2]:
					var q: Vector2 = p + ((b["p1"] as Vector2) - b["p0"]).normalized().orthogonal() * off
					var hh: float = w.height_at(q.x, q.y)
					lo = minf(lo, hh)
					hi = maxf(hi, hh)
		else:
			var r: float = float(b["radius"])
			for i in 9:
				for j in 9:
					var q: Vector2 = (b["pos"] as Vector2) + Vector2((i - 4) * r / 4.0, (j - 4) * r / 4.0)
					if q.distance_to(b["pos"]) > r:
						continue
					var hh: float = w.height_at(q.x, q.y)
					lo = minf(lo, hh)
					hi = maxf(hi, hh)
		var rng: float = hi - lo
		if rng > 0.02:
			over += 1
		if rng > worst:
			worst = rng
			worst_name = "%s (id %d, %.0f m from the lander)" % [b["name"], int(id), (b["pos"] as Vector2).distance_to(w.center)]
		if args.size() > 1 and str(id) in args:
			print("%d %s kind %s range %.3f m, height at centre %.3f, %.0f m from the lander" % [int(id), b["name"], b["kind"], rng, w.height_at(b["pos"].x, b["pos"].y), (b["pos"] as Vector2).distance_to(w.center)])
	print("%s: %d structures, %d with more than 2 cm of height range; worst %.3f m at %s" % [name, sim.state["buildings"].size(), over, worst, worst_name])
	quit(0)
