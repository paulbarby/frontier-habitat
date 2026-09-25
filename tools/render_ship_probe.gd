extends SceneTree
## RENDER debug: visiting ships and visitors in a save, driven for `secs` game seconds.
##   node tools/godot.mjs script res://tools/render_ship_probe.gd [save] [secs] [speed] [ship kind to call]
var main
var n := 0
var frames := 0
var want := 0
var args: PackedStringArray
func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n == 3:
		var save: String = args[0] if args.size() > 0 else "showcase_v31.fhsave"
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/" + save))
		var sp: int = int(args[2]) if args.size() > 2 else 1
		main.set_speed(sp)
		want = int(float(args[1]) / float(sp) * 30.0) if args.size() > 1 else 60
		if args.size() > 3:
			if not main.sim.state.has("options"):
				main.sim.state["options"] = {}
			main.sim.state["options"]["debug"] = true
			print("CALL ", main.submit("traffic_now", {"kind": args[3], "in": 5.0}))
		return false
	if n < 3:
		return false
	main.set_process(false)
	main._process(1.0 / 30.0)
	frames += 1
	if frames % 60 == 0 or frames >= want:
		var sim = main.sim
		var rows: Array = sim.traffic.ships() if sim.get("traffic") != null else []
		var brief: Array = rows.map(func(r): return "%d %s %s t%.1f pad %d" % [int(r["id"]), r["kind"], r["phase"], float(r["t_s"]), int(r["pad"])])
		print("F%d sim %s | view %s" % [frames, str(brief), str(main.view.traffic.info())])
	if frames >= want:
		var npc = main.view.npc
		var vis := {}
		for id in npc.agents:
			var rec: Dictionary = npc.agents[id]
			var lk: int = int(rec["look"])
			if lk >= 512:
				vis[id] = "look %d v %d var %s pos %s" % [lk, lk / 64 - 8, rec["var"], str(Vector2(rec["pos"].x, rec["pos"].z).snappedf(0.1))]
		print("VISITORS ", vis.size(), " ", vis)
		print("GHOSTS ", npc._ghosts.size())
		print("LIB parts suit ", (npc.libs["suit"]["parts"] as Array).map(func(p): return String(p["name"])))
		print("STATS ", main.view.traffic.stats)
		quit(0)
		return true
	return false
