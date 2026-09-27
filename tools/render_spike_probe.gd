extends SceneTree
## RENDER: what changes in the view of showcase_v4 in its first ~110 game seconds (log, POIs,
## vehicles, colonists outside), to match web frame spikes (main `spikes`: g<second>) with events.
##   node tools/godot.mjs script res://tools/render_spike_probe.gd
var main
var n := 0
var g0 := 0
var last := {}
var li := -1

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n > 30 * 200:
		return true
	if n < 3:
		return false
	var sim = main.sim
	if n == 3:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
		sim = main.sim
		g0 = int(sim.seconds())
		li = (sim.state["log"] as Array).size()
		print("start g", g0)
		main.set_speed(1)
		return false
	main.set_process(false)
	main._process(1.0 / 30.0)
	var v = main.view
	var g: int = int(sim.seconds())
	var outs := []
	for ag in sim.state["agents"].values():
		if ag["state"] == "alive" and ag["where"] != "in" and ag["where"] != "room":
			outs.append("%d:%s" % [int(ag["id"]), ag["where"]])
	var vr := []
	for r in v.vehicles.vehicles.values():
		var rw: Dictionary = r.get("row", {})
		vr.append("%s:%s c%d %s" % [r["id"], rw.get("state", "?"), (rw.get("crew", []) as Array).size(), str((r["crew"] as Array).map(func(c): return c["stage"]))])
	var now := {"pois": v.explore.stats.get("pois"), "out": str(outs), "veh": str(vr), "bld": sim.state["buildings"].size()}
	for k in now:
		if last.has(k) and str(last[k]) != str(now[k]):
			print("g%d %s %s -> %s" % [g, k, str(last[k]), str(now[k])])
	last = now
	var lg: Array = sim.state["log"]
	for i in range(li, lg.size()):
		print("g%d LOG %s" % [int(lg[i]["tick"]) / int(sim.bal["tick_hz"]), lg[i]["code"]])
	li = lg.size()
	if n % 90 == 0:
		print("g%d vpos %s" % [g, str(v.vehicles.vehicles.values().map(func(q): return Vector2i(q["pos"])))])
	return g > g0 + 112
