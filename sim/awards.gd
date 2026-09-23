extends RefCounted
## Awards (docs/AAA_DESIGN.md section 8): medals in four tiers. The conditions use the
## same checks as the goals (goals.eval_kind) plus the lifetime counters in state.stats.
## state.awards = {award id: tick earned}. An award is earned once and never lost.
## state.award_track = {award id: tick its sustained condition became true}.

var sim

func _init(s) -> void:
	sim = s

func all() -> Dictionary:
	return sim.content["awards"]

func earned(id: String) -> bool:
	return sim.state["awards"].has(id)

## Every award with its state, in content order:
## [{id, name, tier, desc, earned (tick or -1), value, target}]
func list() -> Array:
	var out: Array = []
	var aw: Dictionary = all()
	for id in aw:
		var a: Dictionary = aw[id]
		var r: Array = sim.goals.eval_kind(String(a["kind"]), a.get("params", {}))
		out.append({"id": id, "name": a["name"], "tier": a["tier"], "desc": a.get("desc", ""),
			"earned": int(sim.state["awards"].get(id, -1)), "value": float(r[1]), "target": float(r[2])})
	return out

## Points of every earned award (tier points from awards.json).
func points() -> int:
	var n := 0
	var tiers: Dictionary = sim.content["award_tiers"]
	for id in sim.state["awards"]:
		if all().has(id):
			n += int(tiers.get(all()[id]["tier"], {}).get("points", 0))
	return n

## Checked every other second: medals do not need a faster response.
func tick_second() -> void:
	var tick: int = int(sim.state["tick"])
	var hz: int = int(sim.bal["tick_hz"])
	if (tick / hz) % 2 != 0:
		return
	var aw: Dictionary = all()
	var track: Dictionary = sim.state["award_track"]
	var got: Dictionary = sim.state["awards"]
	for id in aw:
		if got.has(id):
			continue
		var a: Dictionary = aw[id]
		var r: Array = sim.goals.eval_kind(String(a["kind"]), a.get("params", {}))
		var sustain: int = int(float(a.get("sustain", 0)) * hz)
		if not bool(r[0]):
			track.erase(id)
			continue
		if sustain > 0:
			if not track.has(id):
				track[id] = tick
			if tick - int(track[id]) < sustain:
				continue
			track.erase(id)
		got[id] = tick
		var tier: Dictionary = sim.content["award_tiers"].get(a["tier"], {})
		sim.log_event("award", "Award: %s (%s). %s" % [a["name"], String(tier.get("name", a["tier"])).to_lower(), a.get("desc", "")], [], 1)
