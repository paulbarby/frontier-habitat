extends RefCounted
## Hazards (spec 11). Version 2 has the dust storm: a warning first (warning_seconds),
## then the storm (duration from the hazard stream): solar output x solar_mult and outdoor
## walking x speed_mult. Nothing happens before the scenario's no_disaster_days. The hazard
## random stream is separate from every other stream, and it is only drawn when a storm
## is scheduled, never in the first days.
##
## state.events.storm = {phase: "none" | "warning" | "active", at: tick the storm starts,
##                       end: tick it ends, count: storms so far, scheduled: bool}
## balance.json "storm" switches it on and holds the numbers.

const Rng = preload("res://sim/rng.gd")
const Text = preload("res://sim/text.gd")

var sim

func _init(s) -> void:
	sim = s

func cfg() -> Dictionary:
	return sim.bal.get("storm", {})

func enabled() -> bool:
	return bool(cfg().get("enabled", false)) and bool(sim.state.get("options", {}).get("storms", true))

## The storm record ({} when storms are off). The view draws "active" and can show the
## warning; "at" and "end" are ticks.
func storm() -> Dictionary:
	return sim.state.get("events", {}).get("storm", {})

func tick_second() -> void:
	if not enabled():
		return
	var ev: Dictionary = sim.state["events"]
	var tick: int = int(sim.state["tick"])
	var hz: int = int(sim.bal["tick_hz"])
	var day_ticks: int = int(sim.bal["day_length"]) * hz
	var c: Dictionary = cfg()
	var first_day: float = float(sim.content["scenarios"].get(sim.state["scenario"], {}).get("no_disaster_days", c.get("first_day", 5)))
	if not ev.has("storm"):
		# Schedule the first storm only once day `first_day` is near.
		if float(tick) < (first_day - 1.0) * float(day_ticks):
			return
		ev["storm"] = {"phase": "none", "at": -1, "end": -1, "count": 0, "scheduled": false}
	var st: Dictionary = ev["storm"]
	if not bool(st["scheduled"]):
		var earliest: int = maxi(tick, int(first_day * float(day_ticks)))
		var gap: float = Rng.range_float(sim.state["rng"], "hazard", float(c["interval_days"][0]), float(c["interval_days"][1]))
		if int(st["count"]) == 0:
			gap = Rng.range_float(sim.state["rng"], "hazard", 0.0, float(c["interval_days"][0]))
		var at: int = earliest + int(gap * float(day_ticks))
		at -= at % hz
		var dur: int = Rng.range_int(sim.state["rng"], "hazard", int(c["duration_seconds"][0]), int(c["duration_seconds"][1]))
		st["at"] = at
		st["end"] = at + dur * hz
		st["scheduled"] = true
		st["phase"] = "none"
	var warn: int = int(float(c["warning_seconds"]) * hz)
	match String(st["phase"]):
		"none":
			if tick >= int(st["at"]) - warn:
				st["phase"] = "warning"
				sim.log_event("storm_warning", "Dust storm in %s. Solar power will drop to %d%% and walking outside will be slower. Charge the batteries." % [
					Text.n(maxi(0, (int(st["at"]) - tick) / hz), "second"), int(float(c["solar_mult"]) * 100.0)], [], 2)
		"warning":
			if tick >= int(st["at"]):
				st["phase"] = "active"
				var env: Dictionary = sim.state["env"]
				env["solar_mult"] = float(c["solar_mult"])
				env["speed_mult"] = float(c["speed_mult"])
				sim.log_event("storm", "A dust storm is here. It lasts about %s." % Text.n((int(st["end"]) - int(st["at"])) / hz, "second"), [], 2)
		"active":
			if tick >= int(st["end"]):
				var env2: Dictionary = sim.state["env"]
				env2["solar_mult"] = 1.0
				env2["speed_mult"] = 1.0
				st["phase"] = "none"
				st["count"] = int(st["count"]) + 1
				st["scheduled"] = false
				sim.stat_add("storms", "", 1)
				sim.log_event("storm_end", "The dust storm is over.", [], 1)

## Seconds until the next storm starts (-1 when none is known), for the interface.
func seconds_to_storm() -> float:
	var st: Dictionary = storm()
	if st.is_empty() or not bool(st.get("scheduled", false)) or String(st["phase"]) == "active":
		return -1.0
	return maxf(0.0, float(int(st["at"]) - int(sim.state["tick"])) / float(sim.bal["tick_hz"]))

func active() -> bool:
	return String(storm().get("phase", "none")) == "active"
