extends SceneTree
## Developer tool: how often the graphs are rebuilt in the v3perf colony (3000 ticks).
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const Prof = preload("res://tests/dev/profile.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.new_game(1001)
	var ref = Reference.new(sim, "all")
	for s in 12 * 600:
		ref.drive()
		sim.run_seconds(1.0)
	var p = Prof.new()
	p._grow_v3perf(sim, ref)
	var w0: int = int(sim.state["rev"]["walk"])
	var p0: int = int(sim.state["rev"]["power"])
	var paths0: int = sim.nav._paths.size()
	var rebuilds := 0
	var last_p: int = p0
	for i in 3000:
		if int(sim.state["tick"]) % 10 == 0:
			ref.drive()
		sim.step()
		if int(sim.state["rev"]["power"]) != last_p:
			last_p = int(sim.state["rev"]["power"])
			rebuilds += 1
	print("power rev +%d, walk rev +%d, path cache %d -> %d" % [int(sim.state["rev"]["power"]) - p0, int(sim.state["rev"]["walk"]) - w0, paths0, sim.nav._paths.size()])
	quit(0)
