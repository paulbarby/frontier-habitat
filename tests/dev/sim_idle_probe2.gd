extends SceneTree
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	var base: int = int(sim.bases.ids()[0])
	var room := -1
	for bid in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][bid]
		if String(b["def"]) == "lounge" and b["state"] == "active" and sim.bases.base_of(int(bid)) == base:
			room = int(bid)
	print("room ", room)
	var crew: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child" and sim.bases.home_of(a) == base and String(a["role"]) != "security" and crew.size() < 6:
			crew.append(a)
	var pos: Vector2 = sim.state["buildings"][room]["pos"]
	for k in crew.size():
		var a: Dictionary = crew[k]
		sim.agents.abort_plan(a, "test")
		a["where"] = "in"
		a["bld"] = room
		a["pos"] = pos + Vector2(float(k) * 0.8, 0.0)
		a["hunger"] = 5.0
		a["thirst"] = 5.0
		a["fatigue"] = 5.0
		a["sleeping"] = false
		sim.people.add_mod(a, {"kind": "test_idle", "text": "x", "comp": "work", "sat": 0.0, "att": 0.0, "days": 1.0, "no_work": true, "no_rec": true})
	for s in 6:
		sim.run_seconds(1.0)
	var r: Array = []
	for a in crew:
		if sim.party._is_idle(a):
			var now: int = int(sim.state["tick"])
			var list: Array = sim.party._idle_list(int(a["bld"]))
			var res := {}
			res["in_talk"] = sim.relations.in_talk(int(a["id"]))
			res["chat_t"] = a.get("chat_t", -1)
			res["h"] = sim.party._h(int(a["id"]), now)
			res["list"] = list.size()
			res["crisis"] = sim.party._crisis()
			res["can_talk"] = sim.relations.can_talk(a)
			res["plan"] = a["plan_kind"]
			res["plan_n"] = (a["plan"] as Array).size()
			r.append(res)
	print(r)
	var tries := 0
	for a in crew:
		for k in 40:
			if sim.party.idle_seek(a):
				tries += 1
				break
			sim.state["tick"] = int(sim.state["tick"]) + 1
	print("seek ok ", tries)
	sim.dispose()
	quit(0)
