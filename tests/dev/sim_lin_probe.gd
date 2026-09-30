extends SceneTree
## SIM probe: agent 88 (Lin) in showcase_v4 for 200 s: where, plan, suit (does she die without set-up?).
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	var a: Dictionary = sim.state["agents"][88]
	var v: Dictionary = sim.vehicles.get_v(int(a.get("veh", -1)))
	print("load: %s %s veh %s crew %s vstate %s vpos %s plan %s pi %s route_legs %s queued %s" % [a["state"], a["where"], str(a.get("veh", -1)), str(v.get("crew", [])), str(v.get("state", "")), str(v.get("pos", "")), str(a["plan"].map(func(x): return x["op"])), str(a["pi"]), str((a["route"] as Dictionary).get("legs", []).size()), str(a["queued"])])
	for s in 200:
		sim.run_seconds(1.0)
		if s % 5 == 0 or a["state"] != "alive":
			print("%d %s %s bld %s pos %s suit %.0f plan %s goal %s veh %s ret %.1f" % [s, a["state"], a["where"], str(a["bld"]), str(a["pos"]), float(a["suit"]), a["plan_kind"], a["goal"], str(a.get("veh", -1)), float(a.get("return_secs", 0.0))])
		if a["state"] != "alive":
			break
	quit(0)
