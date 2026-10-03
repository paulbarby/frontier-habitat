extends SceneTree
## Critic r42 verify (PT-7): the Airlock 4 queue and the starving colonist in showcase_v5.fhsave.
## Read only: loads the save into a bare Sim (run from a copy of the e9b1d35 tree), never writes it.
## Every 10 s of game time for 2 game days: the lockjam / starving / rescue issues, the queue at
## each airlock (who, why outside, suit air), the hungry agents (where, plan, hunger) and deaths.

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

var _seen_dead := {}

func _agent_line(sim, aid) -> String:
	var a: Dictionary = sim.state["agents"][aid]
	var bname: String = String(sim.state["buildings"].get(int(a["bld"]), {}).get("name", "-"))
	return "id=%d %s kind=%s role=%s where=%s bld=%s plan=%s goal=%s hunger=%.0f thirst=%.0f suit=%.0f health=%.0f pos=(%.0f,%.0f) bed=%d" % [
		int(aid), a["name"], a["kind"], a["role"], a["where"], bname, String(a["plan_kind"]), String(a["goal"]),
		float(a["hunger"]), float(a["thirst"]), float(a["suit"]), float(a["health"]), a["pos"].x, a["pos"].y, int(a["bed"])]

func _report(sim, label: String, verbose: bool) -> void:
	var tick: int = int(sim.state["tick"])
	var iss: Dictionary = sim.state["issues"]
	var keys: Array = []
	for k in iss:
		var ks := String(k)
		if ks.begins_with("lockjam") or ks == "starving" or ks == "rescue" or ks == "thirsty":
			keys.append(ks)
	var f: Dictionary = sim.metrics.forecast()
	print("--- %s tick=%d day=%.2f alive=%d meals=%d deaths=%d issues=%s" % [label, tick, float(tick) / 6000.0, sim.alive_count(), int(f["meals"]), int(sim.state["progress"]["deaths"]), str(keys)])
	for k in keys:
		var it: Dictionary = iss[k]
		print("   ISSUE %s: %s | ents=%s" % [k, String(it.get("text", "")), str(it.get("entities", []))])
		if k == "starving" or k == "rescue":
			for aid in it.get("entities", []):
				if sim.state["agents"].has(aid):
					print("      HUNGRY ", _agent_line(sim, aid))
	if verbose:
		var blds: Dictionary = sim.state["buildings"]
		for id in blds:
			var lock: Dictionary = blds[id]["lock"]
			if lock.is_empty() or lock["queue"].is_empty():
				continue
			print("   LOCK %d %s def=%s slots=%d queue=%d" % [int(id), blds[id]["name"], blds[id]["def"], sim.agents.lock_slots(blds[id]), lock["queue"].size()])
			for q in lock["queue"]:
				var qa: Dictionary = sim.state["agents"][q["a"]]
				print("      %s dir=%s %s" % ["Q", q["dir"], _agent_line(sim, q["a"])])
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "dead" and not _seen_dead.has(aid):
			_seen_dead[aid] = true
			if int(a.get("death_tick", -1)) >= 0 and label != "at load":
				print("   DEATH id=%d %s cause=%s tick=%d" % [int(aid), a["name"], String(a["cause"]), int(a.get("death_tick", -1))])

func _initialize() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://showcase_v5.fhsave")
	var dec: Dictionary = Persistence.decode(bytes)
	if not dec["ok"]:
		print("decode failed: ", dec["error"])
		quit(1)
		return
	var sim = Sim.new()
	sim.load_state(dec["state"])
	var dead0 := 0
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid]["state"] == "dead":
			_seen_dead[aid] = true
			dead0 += 1
	print("dead at load: ", dead0)
	# Airlocks and the doors they serve.
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if not b["lock"].is_empty():
			print("DOOR %d %s def=%s state=%s pos=(%.0f,%.0f) slots=%d base=%d" % [int(id), b["name"], b["def"], b["state"], b["pos"].x, b["pos"].y, sim.agents.lock_slots(b), sim.bases.base_of(id) if sim.bases.count() > 1 else -1])
	_report(sim, "at load", true)
	var hz: int = int(sim.bal["tick_hz"])
	var jam_samples := 0
	var starving_samples := 0
	var samples := 0
	var max_q := 0
	var min_suit := 1e9
	var secs := 0
	while secs < 1200:
		for i in 10 * hz:
			sim.step()
		secs += 10
		samples += 1
		var iss: Dictionary = sim.state["issues"]
		var jam := false
		for k in iss:
			if String(k).begins_with("lockjam"):
				jam = true
				min_suit = minf(min_suit, float(iss[k].get("value", 1e9)))
				max_q = maxi(max_q, int(iss[k].get("count", 0)))
		if jam:
			jam_samples += 1
		if iss.has("starving"):
			starving_samples += 1
		_report(sim, "t+%ds" % secs, secs % 60 == 0 or jam)
	print("SUMMARY samples=%d jam=%d starving=%d max_queue=%d min_suit=%.0f deaths=%d" % [samples, jam_samples, starving_samples, max_q, min_suit, int(sim.state["progress"]["deaths"])])
	quit(0)
