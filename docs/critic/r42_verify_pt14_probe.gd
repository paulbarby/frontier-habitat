extends SceneTree
## Critic r42 verify (PT-14): read only. Lists every structure in showcase_v5.fhsave that is not
## active (plans, blueprints, sites) with its block reason as SAVED, then steps the sim and prints
## the unreachable / suit_range alerts at load, +60 s, +600 s and +1800 s.
## Note: the working-tree sim is newer than build e9b1d35; the SAVED data (part 1) is exact.

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const SAVE := "C:/Users/paulb/Claude/frontier-habitat/build/web_v5play3/showcase_v5.fhsave"

func _dump_plans(state: Dictionary, label: String) -> void:
	var blds: Dictionary = state["buildings"]
	var n := 0
	var states := {}
	for id in blds:
		var b: Dictionary = blds[id]
		states[b["state"]] = int(states.get(b["state"], 0)) + 1
		if b["state"] != "active":
			n += 1
			print("  [%s] id=%d name='%s' def=%s state=%s block='%s' pos=(%.0f,%.0f) base=%s" % [label, int(id), String(b.get("name", "?")), String(b.get("def", "?")), String(b["state"]), String(b.get("block", "")), b.get("pos", Vector2()).x, b.get("pos", Vector2()).y, str(b.get("base", "?"))])
	print("  [%s] buildings=%d not-active=%d by state=%s" % [label, blds.size(), n, str(states)])

func _dump_alerts(sim, label: String) -> void:
	var iss: Dictionary = sim.state.get("issues", {})
	var keys := []
	for k in iss:
		keys.append(String(k))
		var s := String(k)
		if s.begins_with("unreachable") or s == "range" or s.begins_with("materials"):
			print("  [%s] ALERT %s live=%s :: %s" % [label, s, str(iss[k].get("live", true)), String(iss[k].get("text", ""))])
	print("  [%s] tick=%d day=%.2f issue keys=%s" % [label, int(sim.state["tick"]), float(int(sim.state["tick"])) / 6000.0, str(keys)])

func _initialize() -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(SAVE))
	print("decode ok=", dec.get("ok", false))
	var st: Dictionary = dec["state"]
	print("SAVED tick=%d day=%.2f agents=%d" % [int(st["tick"]), float(int(st["tick"])) / 6000.0, (st["agents"] as Dictionary).size()])
	_dump_plans(st, "saved")
	if st.has("issues"):
		var iss: Dictionary = st["issues"]
		for k in iss:
			var s := String(k)
			if s.begins_with("unreachable") or s == "range":
				print("  [saved] ALERT %s :: %s" % [s, String(iss[k].get("text", ""))])
	var sim = Sim.new()
	sim.load_state(st)
	var hz: int = int(sim.bal["tick_hz"])
	var marks := [0, 60, 600, 1800]
	var t := 0
	for m in marks:
		while t < m:
			for i in hz:
				sim.step()
			t += 1
		_dump_alerts(sim, "t+%d" % m)
		if m == 1800:
			_dump_plans(sim.state, "t+%d" % m)
	quit(0)
