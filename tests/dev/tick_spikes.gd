extends SceneTree
## Developer tool: loads a save and times every tick; prints the slow ticks (over <ms>) with the
## log codes of that tick, and the time of the explore system alone on those ticks.
##   node tools/godot.mjs script res://tests/dev/tick_spikes.gd <save> <seconds> [ms=8]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v4.fhsave"
	var secs: float = float(a[1]) if a.size() > 1 else 600.0
	var lim: float = float(a[2]) if a.size() > 2 else 8.0
	var sim = Sim.new()
	var t_load: int = Time.get_ticks_usec()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	print("load %.1f ms" % (float(Time.get_ticks_usec() - t_load) / 1000.0))
	var n: int = int(secs * 10.0)
	var worst := 0.0
	var total := 0.0
	var slow := 0
	for i in n:
		var log_n: int = (sim.state["log"] as Array).size()
		var w0: int = sim.nav.wins.size() if "wins" in sim.nav else -1
		var mk0: int = int(sim.nav.get("made")) if "made" in sim.nav else -1
		var rev0: int = int(sim.state["rev"]["walk"])
		var t0: int = Time.get_ticks_usec()
		sim.step()
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		var lg: Array = sim.state["log"]
		var codes: Array = []
		for j in range(maxi(0, log_n - 1), lg.size()):
			if int(lg[j]["tick"]) == int(sim.state["tick"]):
				codes.append(lg[j]["code"])
		if codes.has("poi_found") or codes.has("deposit_found") or ms > lim:
			var te: int = Time.get_ticks_usec()
			sim.explore.tick_second()
			print("tick %d (second %d): %.2f ms, log %s, explore.tick_second again %.2f ms, walk rev %d->%d, nav windows %d->%d" % [int(sim.state["tick"]), int(sim.state["tick"]) / 10, ms, str(codes), float(Time.get_ticks_usec() - te) / 1000.0,
				rev0, int(sim.state["rev"]["walk"]), w0, sim.nav.wins.size() if "wins" in sim.nav else -1])
			slow += 1
			if slow > 40:
				break
	print("ticks %d, mean %.3f ms, worst %.2f ms" % [n, total / n, worst])
	sim.dispose()
	quit(0)
