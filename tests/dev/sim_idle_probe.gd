extends SceneTree
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	var n_call := 0
	var stage := {}
	for s in 30:
		sim.run_seconds(1.0)
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if not sim.party._is_idle(a):
				continue
			n_call += 1
			var now: int = int(sim.state["tick"])
			if sim.relations.in_talk(int(a["id"])):
				stage["in_talk"] = int(stage.get("in_talk", 0)) + 1
				continue
			if now - int(a.get("chat_t", -1000000)) < 400:
				stage["gap"] = int(stage.get("gap", 0)) + 1
				continue
			var list: Array = sim.party._idle_list(int(a["bld"]))
			if list.size() < 2:
				stage["alone"] = int(stage.get("alone", 0)) + 1
				continue
			if sim.party._crisis():
				stage["crisis"] = int(stage.get("crisis", 0)) + 1
				continue
			var near: float = float(sim.content["society"]["social"]["near_m"]) * 2.3
			var cnt := 0
			for b in list:
				if int(b["id"]) != int(a["id"]) and (a["pos"] as Vector2).distance_to(b["pos"]) <= near:
					cnt += 1
			stage["near_%d" % mini(cnt, 3)] = int(stage.get("near_%d" % mini(cnt, 3), 0)) + 1
	print("calls ", n_call, " stages ", stage, " near_m ", sim.content["society"]["social"]["near_m"], " crisis ", sim.party._crisis())
	for k in sim.state["issues"]:
		print(" issue ", k, " sev ", sim.state["issues"][k].get("severity"))
	sim.dispose()
	quit(0)
