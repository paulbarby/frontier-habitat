extends SceneTree
## Developer tool: the reference campaign ("all") at a tick: pending steps, stage, beds,
## and every structure not active with its block.
##   node tools/godot.mjs script res://tests/dev/ref_status.gd <tick>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var target := 12000
	var args: Array = OS.get_cmdline_user_args()
	if args.size() > 0:
		target = int(args[0])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(target)
	var f: Dictionary = sim.metrics.forecast()
	print("tick %d stage %d pop %d beds %d" % [target, int(sim.state["progress"]["stage"]), int(f["pop"]), int(f["beds"])])
	for i in g.ref._wanted():
		if g.ref.done.has(i):
			continue
		var st: Dictionary = g.ref.steps[i]
		if float(st["t"]) > sim.seconds():
			continue
		print("  pending %d %s" % [i, JSON.stringify(st)])
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] != "active":
			print("  %s %s block '%s' pos %s" % [b["name"], b["state"], b["block"], str(b.get("pos", ""))])
	print("failures ", g.ref.failures)
	quit(0)
