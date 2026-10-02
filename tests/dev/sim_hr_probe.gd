extends SceneTree
## SIM probe: an HR office on showcase_v5, unhappy people, complaints, a transfer and its ship.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const H = preload("res://tests/helpers.gd")
func _cmd(sim, kind: String, p: Dictionary) -> Dictionary:
	var id: int = sim.submit(kind, p)
	sim.step()
	return sim.cmds.results.get(id, {})
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.state["options"]["debug"] = true
	sim.state["flags"]["unlock_all"] = true
	sim.run_seconds(5.0)
	var base: int = int(sim.bases.ids()[0])
	var near: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var office: Dictionary = H.attach(sim, "hr_office", near, 1, 60, base)
	print("office ", office.get("id", "none"), " base ", sim.bases.base_of(int(office.get("id", -1))))
	sim.run_seconds(2.0)
	var col: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child" and sim.bases.home_of(a) == base:
			col.append(a)
	print("colonists in base ", col.size())
	print("set_role ", _cmd(sim, "set_role", {"agent": int(col[0]["id"]), "role": "hr"}))
	print("active ", sim.hr.active(base), " offices ", sim.hr.offices(base), " slots ", sim.hr.slots(base), " officers ", sim.hr.officers(base))
	for i in range(1, 13):
		var a: Dictionary = col[i]
		for comp in ["needs", "food", "housing", "comfort", "social", "work", "fairness", "safety", "freedom"]:
			sim.people.add_mod(a, {"kind": "test_gloom", "text": "x", "comp": comp, "sat": -90.0, "att": -20.0, "days": 6.0})
	sim.run_seconds(25.0)
	print("sat of col1 ", sim.people.rec_of(int(col[1]["id"])).get("sat"))
	sim.hr._daily(int(sim.state["tick"]) / 6000)
	print("complaints ", sim.hr.complaints().size(), " transfers ", sim.hr.transfers().size())
	for s in 40:
		sim.run_seconds(5.0)
		if s % 4 == 0:
			var parts: Array = []
			for c in sim.hr.complaints():
				parts.append("%d:%s/%s" % [c["id"], c["category"], c["state"]])
			print(" t=", s * 5, " ", parts, " requests ", sim.relations.requests().size())
	var rows: Array = sim.relations.requests()
	for r in rows:
		print("  REQ ", r["kind"], " ", String(r["text"]).substr(0, 80), " opts ", (r["options"] as Array).size())
	# answers
	var tr_ids: Array = []
	for r in rows:
		if r["kind"] == "hr_complaint":
			var opt: String = String(r["options"][0]["id"])
			print("  answer ", r["id"], " ", opt, " -> ", _cmd(sim, "answer_request", {"id": int(r["id"]), "answer": opt}))
		else:
			tr_ids.append(r)
	if tr_ids.size() >= 2:
		print("  approve ", _cmd(sim, "answer_request", {"id": int(tr_ids[0]["id"]), "answer": "approve"}))
		print("  refuse ", _cmd(sim, "answer_request", {"id": int(tr_ids[1]["id"]), "answer": "refuse"}))
	print("  ship ", _cmd(sim, "traffic_now", {"kind": "shuttle", "in": 5}))
	for s in 40:
		sim.run_seconds(5.0)
		var tp: Array = []
		for t in sim.hr.transfers():
			tp.append("%d:%s ship %d" % [t["id"], t["state"], t["ship"]])
		var ships: Array = []
		for sh in sim.traffic.ships():
			ships.append("%s %s" % [sh["kind"], sh["phase"]])
		if s % 4 == 0:
			print(" t=", s * 5, " transfers ", tp, " ships ", ships, " alive ", sim.alive_count())
	print("survey ", JSON.stringify(sim.hr.survey(base)).substr(0, 200))
	for e in sim.state["log"]:
		if String(e["code"]).begins_with("hr_") or String(e["code"]) == "defected":
			print("  LOG ", e["code"], " ", String(e["text"]).substr(0, 100))
	sim.dispose()
	quit(0)
