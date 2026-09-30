extends SceneTree
## Developer tool: per-tick cost of the v5 society work (people.tick, unrest.tick,
## education.tick, the forced rank check) on a save, with extra cloned colonists.
##   node tools/godot.mjs script res://tests/dev/v5_society_prof.gd [save] [extra]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v3_late.fhsave"
	var extra: int = int(a[1]) if a.size() > 1 else 0
	var sim = Sim.new()
	var st: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))["state"]
	var ids: Array = st["agents"].keys()
	var next := 900000
	var k := 0
	while k < extra:
		for aid in ids:
			if k >= extra:
				break
			if st["agents"][aid]["state"] != "alive":
				continue
			var c: Dictionary = st["agents"][aid].duplicate(true)
			next += 1
			c["id"] = next
			st["agents"][next] = c
			k += 1
	sim.load_state(st)
	sim.run_seconds(60.0)
	var tot := {"people": 0.0, "unrest": 0.0, "edu": 0.0, "ranks": 0.0, "step": 0.0}
	var n := 600
	for i in n:
		sim.state["tick"] = int(sim.state["tick"]) + 1
		var t0: int = Time.get_ticks_usec()
		sim.people._refresh_ranks(true)
		var t1: int = Time.get_ticks_usec()
		sim.people.tick()
		var t2: int = Time.get_ticks_usec()
		sim.unrest.tick()
		var t3: int = Time.get_ticks_usec()
		sim.education.tick()
		var t4: int = Time.get_ticks_usec()
		sim.state["tick"] = int(sim.state["tick"]) - 1
		sim.step()
		var t5: int = Time.get_ticks_usec()
		tot["ranks"] += float(t1 - t0) / 1000.0
		tot["people"] += float(t2 - t1) / 1000.0
		tot["unrest"] += float(t3 - t2) / 1000.0
		tot["edu"] += float(t4 - t3) / 1000.0
		tot["step"] += float(t5 - t4) / 1000.0
	var out: Array = []
	for key in tot:
		out.append("%s %.3f" % [key, tot[key] / n])
	print("%d agents, mean ms per tick: %s" % [sim.state["agents"].size(), ", ".join(out)])
	sim.dispose()
	quit(0)
