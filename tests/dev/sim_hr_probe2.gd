extends SceneTree
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const H = preload("res://tests/helpers.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.state["flags"]["unlock_all"] = true
	sim.run_seconds(5.0)
	var base: int = int(sim.bases.ids()[0])
	var near: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var office: Dictionary = H.attach(sim, "hr_office", near, 1, 60, base)
	sim.run_seconds(2.0)
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	var col: Array = []
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child" and sim.bases.home_of(a) == base:
			col.append(a)
	var sid: int = sim.submit("set_role", {"agent": int(col[0]["id"]), "role": "hr"})
	sim.step()
	for i in range(1, 13):
		for comp in ["needs", "food", "housing", "comfort", "social", "work", "fairness", "safety", "freedom"]:
			sim.people.add_mod(col[i], {"kind": "test_gloom", "text": "x", "comp": comp, "sat": -90.0, "att": -20.0, "days": 6.0})
	sim.run_seconds(25.0)
	sim.hr._daily(int(sim.state["tick"]) / 6000)
	for c in sim.hr.complaints():
		var a: Dictionary = sim.state["agents"][int(c["agent"])]
		print("complaint ", c["id"], " agent ", a["id"], " where ", a["where"], " bld ", a["bld"], " plan_kind ", a["plan_kind"], " visit ", a.get("hr_visit"), " office ", a.get("hr_office"), " nowork ", a.has("v5_nowork"))
	for s in 6:
		sim.run_seconds(3.0)
		for c in sim.hr.complaints():
			var a: Dictionary = sim.state["agents"][int(c["agent"])]
			print(" t=", (s + 1) * 3, " ", c["id"], " where ", a["where"], " bld ", a["bld"], " plan ", a["plan_kind"], " ", a["goal"], " state ", c["state"])
	sim.dispose()
	quit(0)
