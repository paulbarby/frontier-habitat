extends SceneTree
## Developer tool: why "around" placement fails next to a structure of the reference.
##   node tools/godot.mjs script res://tests/dev/around_dbg.gd [seed] [alias] [def] [day]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1002
	var al: String = args[1] if args.size() > 1 else "M1"
	var def: String = args[2] if args.size() > 2 else "refinery"
	var day: float = float(args[3]) if args.size() > 3 else 4.0
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	for s in int(day * 600):
		ref.drive()
		sim.run_seconds(1.0)
	if not ref.alias.has(al):
		print("no alias ", al, " aliases ", ref.alias.keys())
		for f in ref.failures:
			print("REF ", f)
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["def"] == "mine":
				print("mine id %d at %s state %s block %s" % [id, str(b["pos"]), b["state"], b["block"]])
		for i in ref.steps.size():
			var st: Dictionary = ref.steps[i]
			if String(st.get("as", "")) == al or String(st.get("b", "")) == al:
				print("step %d done %s ring %s: %s" % [i, str(ref.done.has(i)), str(ref.ring.get(i, -1)), str(st)])
		for d in sim.state["deposits"]:
			print("deposit ", d)
		quit(0)
		return
	var a: Dictionary = sim.state["buildings"][ref.alias[al]]
	print("%s at %s r %.1f state %s, lander %s" % [al, str(a["pos"]), float(a["radius"]), a["state"], str(sim.world.center)])
	var rad: float = float(sim.sizes.def_for(def, 1)["radius"])
	for gap in [3.0, 8.0, 15.0, 20.0]:
		var reasons := {}
		for j in 24:
			var p: Vector2 = (a["pos"] as Vector2) + Vector2(float(a["radius"]) + rad + gap, 0).rotated(j * TAU / 24.0)
			var r: String = sim.place.check_building(def, sim.place.snap_pos(p), 0.0)
			reasons[r] = int(reasons.get(r, 0)) + 1
		print("gap %.0f: %s" % [gap, str(reasons)])
	for f in ref.failures:
		print("REF ", f)
	quit(0)
