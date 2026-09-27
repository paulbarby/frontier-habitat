extends SceneTree
## Developer tool: the long campaign (reference "all", seed 1001) with balance overrides,
## to tune the V4 rules. Prints chapters, the hull day, deaths and the tick time.
##   node tools/godot.mjs script res://tests/dev/campaign_try.gd key=value [key=value ...]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const H = preload("res://tests/helpers.gd")

func _init() -> void:
	var probe = Sim.new()
	var bal: Dictionary = probe.content["balance"]
	var tag := ""
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(a).split("=")
		if kv.size() == 2:
			bal[kv[0]] = float(kv[1]) if kv[1].is_valid_float() else kv[1]
			tag += "%s=%s " % [kv[0], kv[1]]
	probe.dispose()
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	var hull := -1.0
	var ch := {}
	var t0: int = Time.get_ticks_msec()
	for day in range(1, 31):
		g.run_to_tick(day * 6000)
		for i in sim.goals.chapter():
			if not ch.has(i + 1):
				ch[i + 1] = day
		if int(sim.state["ship"]["stage"]) >= 2 and hull < 0.0:
			var gs: Dictionary = sim.state["goals"]["status"].get("ship_hull", {})
			hull = float(int(gs.get("done_tick", day * 6000))) / 6000.0 + 1.0
		if hull > 0.0 and day >= 26:
			break
		if sim.alive_count() == 0:
			break
	var causes := {}
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		if ag["state"] == "dead":
			causes[ag["cause"]] = int(causes.get(ag["cause"], 0)) + 1
	print("RESULT %s| chapters %s hull %.1f alive %d deaths %s refused %d | %d s" % [tag, str(ch), hull, sim.alive_count(), str(causes), H.refused_commands(sim).size(), (Time.get_ticks_msec() - t0) / 1000])
	quit(0)
