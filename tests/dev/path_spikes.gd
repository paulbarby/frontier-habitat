extends SceneTree
## Developer tool: runs a save and prints every tick over <ms> with the path searches, window
## builds and pocket fills of that tick (nav_v4 prof), and the slow agent thinks.
##   node tools/godot.mjs script res://tests/dev/path_spikes.gd <save> <seconds> [ms=8] [extra colonists]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v4.fhsave"
	var secs: float = float(a[1]) if a.size() > 1 else 300.0
	var lim: float = float(a[2]) if a.size() > 2 else 8.0
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	if not ("prof_on" in sim.nav):
		print("not the v4 nav")
		quit(0)
		return
	sim.nav.prof_on = true
	var sums := {}
	var cnt := {}
	var worst := 0.0
	var slow := 0
	for i in int(secs * 10.0):
		sim.nav.prof = []
		var t0: int = Time.get_ticks_usec()
		sim.step()
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		for e in sim.nav.prof:
			sums[e[0]] = float(sums.get(e[0], 0.0)) + float(e[1])
			cnt[e[0]] = int(cnt.get(e[0], 0)) + 1
		if ms > lim:
			slow += 1
			var parts: Array = []
			for e in sim.nav.prof:
				if float(e[1]) > 0.5:
					parts.append("%s %.1f %s" % [e[0], float(e[1]), e[2]])
			print("tick %d (phase %d): %.1f ms | %d nav ops | %s" % [int(sim.state["tick"]), int(sim.state["tick"]) % 10, ms, sim.nav.prof.size(), ", ".join(parts)])
	var out: Array = []
	for k in sums:
		out.append("%s %d calls %.1f ms (%.2f each)" % [k, cnt[k], sums[k], sums[k] / cnt[k]])
	print("totals: ", ", ".join(out))
	print("worst %.1f ms, %d ticks over %.0f ms" % [worst, slow, lim])
	sim.dispose()
	quit(0)
