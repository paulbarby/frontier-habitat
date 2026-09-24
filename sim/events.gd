extends RefCounted
## The version-2 dust storm read API, kept for the interface and old views. Version 3
## moved every hazard into sim/hazards.gd (kind "dust_storm" there); hazards keeps
## state.events.storm as a mirror in the v2 shape:
##   {phase: "none" | "warning" | "active", at, end, count, scheduled}
## Nothing here changes state.

var sim

func _init(s) -> void:
	sim = s

func cfg() -> Dictionary:
	return sim.bal.get("storm", {})

func enabled() -> bool:
	return bool(cfg().get("enabled", false)) and bool(sim.state.get("options", {}).get("storms", true)) and sim.hazards.level() > 0.0

## The storm record ({} before the first storm is planned or when storms are off).
func storm() -> Dictionary:
	return sim.state.get("events", {}).get("storm", {})

## Kept for old callers: hazards.tick_second() does the work now.
func tick_second() -> void:
	pass

## Seconds until the next storm starts (-1 when none is known), for the interface.
func seconds_to_storm() -> float:
	var st: Dictionary = storm()
	if st.is_empty() or not bool(st.get("scheduled", false)) or String(st["phase"]) == "active":
		return -1.0
	return maxf(0.0, float(int(st["at"]) - int(sim.state["tick"])) / float(sim.bal["tick_hz"]))

func active() -> bool:
	return String(storm().get("phase", "none")) == "active"
