extends SceneTree
## Critic r42 verify (PT-6): who the lander_expiry alert counts in showcase_v5.fhsave, and
## whether free beds exist for them. Read only: loads the save into a bare Sim, never writes it.

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _report(sim, label: String) -> void:
	var blds: Dictionary = sim.state["buildings"]
	var lid: int = int(sim.state["lander_id"])
	var left: float = sim.util.lander_seconds_left()
	var tick: int = int(sim.state["tick"])
	var day: float = float(tick) / 6000.0
	print("=== %s tick=%d day=%.3f lander=%d left=%.1f bases=%d" % [label, tick, day, lid, left, sim.bases.count()])
	var counts := {}
	var inside: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		counts[a["kind"]] = int(counts.get(a["kind"], 0)) + 1
		if a["kind"] != "visitor" and (int(a["bed"]) == lid or int(a["bed"]) == -1):
			inside.append(aid)
	print("alive by kind: ", counts)
	for aid in inside:
		var a: Dictionary = sim.state["agents"][aid]
		var base_id: int = sim.bases.base_of_agent(a) if sim.bases.count() > 1 else -1
		print("  COUNTED id=%d name=%s kind=%s bed=%d base=%d plan=%s in=%s pos=%s" % [int(aid), a["name"], a["kind"], int(a["bed"]), base_id, String(a.get("plan_kind", "")), "%s/%s fat=%.0f sleeping=%s role=%s" % [str(a["where"]), str(a["bld"]), float(a["fatigue"]), str(a["sleeping"]), str(a["role"])], str(a["pos"])])
	# Free supplied room beds (the same test _assign_bed applies), per base.
	var free_by_base := {}
	var total_beds := 0
	for e in sim.agents._bed_rooms():
		var bid: int = e[0]
		var beds: int = e[1]
		var b: Dictionary = blds[bid]
		total_beds += beds
		if b["state"] != "active" or bool(b["demolish"]) or not sim.util.building_supplied(bid):
			continue
		var used: int = sim.agents.beds_used(bid)
		if used < beds:
			var bb: int = sim.bases.base_of(bid) if sim.bases.count() > 1 else -1
			free_by_base[bb] = int(free_by_base.get(bb, 0)) + (beds - used)
	print("room beds total=%d free supplied by base=%s" % [total_beds, str(free_by_base)])
	var f: Dictionary = sim.metrics.forecast()
	print("forecast beds=%d pop=%d" % [int(f["beds"]), int(f["pop"])])
	var iss: Dictionary = sim.state["issues"]
	for k in iss:
		if String(k).begins_with("lander") or String(k).begins_with("core_expiry"):
			print("  ISSUE %s: %s | %s" % [k, iss[k].get("text", ""), iss[k].get("action", "")])

func _initialize() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://build/web_v5play3/showcase_v5.fhsave")
	var dec: Dictionary = Persistence.decode(bytes)
	if not dec["ok"]:
		print("decode failed: ", dec["error"])
		quit(1)
		return
	var sim = Sim.new()
	sim.load_state(dec["state"])
	_report(sim, "at load")
	# Step: 10 s, 60 s, then every 60 s of game time for one game day (600 s).
	var hz: int = int(sim.bal["tick_hz"])
	var marks := [10, 60, 120, 240, 360, 480, 600, 900]
	var done := 0
	for m in marks:
		for i in (m - done) * hz:
			sim.step()
		done = m
		_report(sim, "after %d s" % m)
	quit(0)
