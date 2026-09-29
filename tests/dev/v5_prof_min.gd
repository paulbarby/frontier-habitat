extends SceneTree
## Developer tool: the minimum v5 timing (talks, talks_near, list, unrest, Rag and the step by
## phase of the second) with calls that exist in every v5 build, for before/after numbers.
##   node tools/godot.mjs script res://tests/dev/v5_prof_min.gd [save] [extra colonists]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v3_late.fhsave"
	var extra: int = int(a[1]) if a.size() > 1 else 0
	var sim = Sim.new()
	var st: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))["state"]
	if extra > 0:
		var ids: Array = st["agents"].keys()
		var next: int = 900000
		var k := 0
		while k < extra:
			for aid in ids:
				if k >= extra:
					break
				var src: Dictionary = st["agents"][aid]
				if src["state"] != "alive":
					continue
				var c: Dictionary = src.duplicate(true)
				next += 1
				c["id"] = next
				c["pos"] = (src["pos"] as Vector2) + Vector2(0.5, 0.3)
				st["agents"][next] = c
				k += 1
	sim.load_state(st)
	sim.run_seconds(2.0)
	var n := 0
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid]["state"] == "alive":
			n += 1
	print("%s, %d people" % [path, n])
	var fa: Dictionary = sim.state["agents"][sim.state["agents"].keys()[0]]
	var rows := {}
	for name in ["talks", "talks_near", "list", "unrest"]:
		var tot := 0.0
		var mx := 0.0
		for i in 100:
			sim.step()
			var t0: int = Time.get_ticks_usec()
			match name:
				"talks": sim.social.talks()
				"talks_near": sim.social.talks_near(fa["pos"], 30.0)
				"list": sim.people.list()
				"unrest": sim.social.unrest(-1)
			var ms: float = _ms(t0)
			tot += ms
			mx = maxf(mx, ms)
		print("  %-11s every tick: mean %.3f max %.3f ms" % [name, tot / 100.0, mx])
	var t1: int = Time.get_ticks_usec()
	sim.social.rag_issues(30)
	print("  rag_issues(30) first call %.2f ms" % _ms(t1))
	var hz: int = int(sim.bal["tick_hz"])
	var by: Array = []
	for p in hz:
		by.append([])
	var all: Array = []
	for i in 600:
		var t0: int = Time.get_ticks_usec()
		sim.step()
		var ms: float = _ms(t0)
		by[int(sim.state["tick"]) % hz].append(ms)
		all.append(ms)
	var row: Array = []
	for p in hz:
		var arr: Array = by[p]
		arr.sort()
		row.append("p%d %.2f/%.2f" % [p, arr[arr.size() / 2], arr.back()])
	all.sort()
	print("  step median/max by phase: " + " ".join(row))
	print("  step all: median %.3f max %.3f ms" % [all[all.size() / 2], all.back()])
	sim.dispose()
	quit(0)
