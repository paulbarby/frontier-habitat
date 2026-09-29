extends SceneTree
## Developer tool: time of the v5 people and social calls on a save (UI and RENDER call these
## from the frame), and the step time of the ticks around them.
##   node tools/godot.mjs script res://tests/dev/v5_prof.gd [save] [extra colonists]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0

func _time(name: String, reps: int, f: Callable, bump: Callable) -> void:
	var worst := 0.0
	var tot := 0.0
	for i in reps:
		bump.call()
		var t0: int = Time.get_ticks_usec()
		f.call()
		var ms: float = _ms(t0)
		tot += ms
		worst = maxf(worst, ms)
	print("  %-26s mean %7.3f ms  max %7.3f ms" % [name, tot / reps, worst])

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v3_late.fhsave"
	var extra: int = int(a[1]) if a.size() > 1 else 0
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	if extra > 0:
		# Clones of living colonists (new ids, the same room) to reach a target head count.
		var ids: Array = sim.state["agents"].keys()
		var next: int = int(sim.state.get("next_id", 100000))
		var k := 0
		while k < extra:
			for aid in ids:
				if k >= extra:
					break
				var src: Dictionary = sim.state["agents"][aid]
				if src["state"] != "alive":
					continue
				var c: Dictionary = src.duplicate(true)
				next += 1
				c["id"] = next
				c["pos"] = (src["pos"] as Vector2) + Vector2(0.5, 0.3)
				sim.state["agents"][next] = c
				k += 1
		sim.state["next_id"] = next + 1
		sim.people.reset()
		sim.social.reset()
		sim.people.prewarm()   # as load_state does for a save with this many people
	sim.run_seconds(2.0)
	var n := 0
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid]["state"] == "alive":
			n += 1
	print("save %s, %d people alive" % [path, n])
	var nop := func(): pass
	var bump := func(): sim.state["tick"] = int(sim.state["tick"]) + 1
	var bump_min := func(): sim.state["tick"] = int(sim.state["tick"]) + 600
	var first: int = int(sim.state["agents"].keys()[0])
	var fa: Dictionary = sim.state["agents"][first]
	_time("talks() first call", 1, func(): sim.social.talks(), bump)
	_time("talks() new tick", 200, func(): sim.social.talks(), bump)
	_time("talks() same tick", 20, func(): sim.social.talks(), nop)
	_time("talks_near new tick", 200, func(): sim.social.talks_near(fa["pos"], 30.0), bump)
	_time("recent_lines", 20, func(): sim.social.recent_lines(first, 3), bump)
	_time("rank refresh (minute)", 5, func(): sim.people.rank(fa), bump_min)
	_time("rank (cached)", 20, func(): sim.people.rank(fa), nop)
	_time("satisfaction x1", 20, func(): sim.people.satisfaction(fa), bump)
	_time("attitude x1", 20, func(): sim.people.attitude(fa), bump)
	_time("people.list()", 50, func(): sim.people.list(), bump)
	_time("relationships_of", 10, func(): sim.social.relationships_of(first, 8), bump)
	_time("unrest(-1)", 10, func(): sim.social.unrest(-1), bump)
	var bump_sec := func(): sim.state["tick"] = int(sim.state["tick"]) + 10
	_time("talks() once a second", 30, func(): sim.social.talks(), bump_sec)
	_time("unrest once a second", 30, func(): sim.social.unrest(-1), bump_sec)
	_time("list() once a second", 30, func(): sim.people.list(), bump_sec)
	_time("rag context", 3, func(): sim.social._rag_ctx(), bump)
	_time("rag_issues(30)", 3, func(): sim.social.rag_issues(30), bump)
	_time("rag_issues(1)", 5, func(): sim.social.rag_issues(1), bump)
	# Step times by phase of the second (tick % tick_hz), then all ticks.
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
	print("  step all ticks: median %.3f max %.3f ms" % [all[all.size() / 2], all.back()])
	sim.dispose()
	quit(0)
