extends SceneTree
## Developer tool: generators and their state at a tick of the reference campaign.
##   node tools/godot.mjs script res://tests/dev/gen_state.gd <tick>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")
func _init() -> void:
	for extra in OS.get_cmdline_user_args().slice(1):
		var kv: PackedStringArray = String(extra).split("=")
		if kv.size() == 2:
			var probe = preload("res://sim/sim.gd").new()
			probe.content["balance"][kv[0]] = float(kv[1])
			probe.dispose()
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(int(OS.get_cmdline_user_args()[0]))
	var kinds := {}
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		var d: Dictionary = sim.bd(b)
		if d.has("gen_solar") or d.has("gen_wind") or d.has("gen_const") or d.has("energy_cap"):
			var k: String = "%s %s dust=%s trip=%s health=%.0f block=%s powered=%s" % [b["def"], b["state"], str(b.get("dust", false)), str(b.get("trip", false)), float(b["health"]), b["block"], str(b["powered"])]
			kinds[k] = int(kinds.get(k, 0)) + 1
	for k in kinds:
		print("%3d x %s" % [kinds[k], k])
	var tasks := {}
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		var k2: String = "%s/%s owner=%s reason=%s" % [t["kind"], t["state"], "yes" if int(t["owner"]) != -1 else "no", t.get("reason", "")]
		tasks[k2] = int(tasks.get(k2, 0)) + 1
	print(tasks)
	print("env sun %.2f wind %.2f" % [float(sim.state["env"]["sun"]), float(sim.state["env"]["wind"])])
	for comp in sim.util.power_stats:
		var ps: Dictionary = sim.util.power_stats[comp]
		if int(ps["demand"]) > 0:
			print("net %d: gen %.1f demand %.1f served %.1f stored %.1f/%.1f shed %d" % [comp, sim.util.to_rate(int(ps["gen"])), sim.util.to_rate(int(ps["demand"])), sim.util.to_rate(int(ps["served"])), float(ps["stored"]) / 60000.0, float(ps["cap"]) / 60000.0, (ps["shed"] as Array).size()])
	quit(0)
