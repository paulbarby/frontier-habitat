extends SceneTree
## Developer tool: loads a save and runs sim.step()'s systems one by one with timers (the same
## order as sim.gd step()); prints every tick over <ms> with the systems that took the time.
##   node tools/godot.mjs script res://tests/dev/spike_prof.gd <save> <seconds> [ms=15]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

var _t := {}
var _t0 := 0

func _mark(name: String) -> void:
	var now: int = Time.get_ticks_usec()
	_t[name] = float(_t.get(name, 0.0)) + float(now - _t0) / 1000.0
	_t0 = now

func _step(sim) -> void:
	_t = {}
	_t0 = Time.get_ticks_usec()
	sim.state["tick"] = int(sim.state["tick"]) + 1
	var tick: int = int(sim.state["tick"])
	var second: bool = tick % int(sim.bal["tick_hz"]) == 0
	sim.cmds.apply_pending(); _mark("cmds")
	sim.util.env_tick(); _mark("env")
	if second:
		sim.hazards.tick_second(); _mark("hazards")
		sim.traffic.tick_second(); _mark("traffic")
	if bool(sim.state["topo_dirty"]):
		sim.topo.rebuild(true); _mark("topo")
	sim.util.power_tick(); _mark("power")
	sim.util.water_tick(); _mark("water")
	sim.util.atmo_tick(); _mark("atmo")
	sim.agents.needs_tick(); _mark("needs")
	if second:
		sim.build.tick_second(); _mark("build")
		sim.upgrades.tick_second(); _mark("upgrades")
		sim.vehicles.tick_second(); _mark("vehicles_s")
		sim.reactors.tick_second(); _mark("reactors")
		sim.explore.tick_second(); _mark("explore")
		sim.ship.tick_second(); _mark("ship_s")
		var J = sim.jobs
		J._expire(); _mark("j_expire")
		J._index(); _mark("j_index")
		J._gen_machine_inputs(); _mark("j_inputs")
		J._gen_repair(); _mark("j_repair")
		J._gen_hazard_work(); _mark("j_hazard")
		J._gen_research(); _mark("j_research")
		J._gen_medical(); _mark("j_medical")
		J._gen_ship(); _mark("j_ship")
		J._gen_construction(); _mark("j_constr")
		J._gen_upgrades(); _mark("j_upg")
		J._gen_vehicles(); _mark("j_veh")
		J._gen_reactors(); _mark("j_reac")
		J._gen_dining(); _mark("j_dining")
		J._gen_trade(); _mark("j_trade")
		J._gen_water_fill(); _mark("j_water")
		J._gen_clearing(); _mark("j_clear")
		J._gen_operate(); _mark("j_operate")
		J._gen_tend(); _mark("j_tend")
		J._gen_demolish(); _mark("j_demol")
		if int(sim.state["tick"]) % (10 * int(sim.bal["tick_hz"])) == 0:
			J._clean_piles()
		_mark("j_piles")
	var n: int = int(sim.bal["tick_hz"])
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		if ag["state"] == "alive" and (tick + int(aid)) % n == 0:
			var ta: int = Time.get_ticks_usec()
			var g0: String = String(ag["goal"])
			sim.agents._think(ag)
			var dt: float = float(Time.get_ticks_usec() - ta) / 1000.0
			if dt > 10.0:
				print("   agent %d %s: %.1f ms, goal '%s' -> '%s', where %s pos %s, reason %s" % [int(aid), ag["role"], dt, g0, ag["goal"], ag["where"], str((ag["pos"] as Vector2).round()), str(ag.get("backoff", {}).size())])
	_mark("think")
	sim.agents.locks_tick(); _mark("locks")
	sim.agents.act_tick(); _mark("act")
	sim.vehicles.tick(); _mark("vehicles")
	sim.ship.tick(); _mark("ship")
	if second:
		sim.prod.crops_second(); sim.prod.auto_second(); sim.prod.spoil_second(); sim.prod.wear_second(); _mark("prod")
		sim.agents.morale_second(); _mark("morale")
		sim.research.tick_second(); _mark("research")
		sim.alerts.tick_second(); _mark("alerts")
		sim.metrics.tick_second(); sim.goals.tick_second(); sim.awards.tick_second(); _mark("metrics")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var path: String = String(a[0]) if a.size() > 0 else "res://content/saves/showcase_v4.fhsave"
	var secs: float = float(a[1]) if a.size() > 1 else 900.0
	var lim: float = float(a[2]) if a.size() > 2 else 15.0
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	var worst := 0.0
	for i in int(secs * 10.0):
		var w0: int = sim.nav.wins.size()
		_step(sim)
		var total := 0.0
		for k in _t:
			total += float(_t[k])
		worst = maxf(worst, total)
		if total > lim:
			var parts: Array = []
			for k in _t:
				if float(_t[k]) > 1.5:
					parts.append("%s %.1f" % [k, float(_t[k])])
			print("tick %d: %.1f ms | %s | windows %d->%d" % [int(sim.state["tick"]), total, ", ".join(parts), w0, sim.nav.wins.size()])
	print("worst %.1f ms" % worst)
	sim.dispose()
	quit(0)
