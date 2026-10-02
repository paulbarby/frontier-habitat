extends SceneTree
## SIM probe: celebrations, offers, a party and its drama on showcase_v5.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.state["options"]["debug"] = true
	sim.run_seconds(5.0)
	print("bases ", sim.bases.ids(), " venues ", sim.party.venues(int(sim.bases.ids()[0])).size())
	for v in sim.party.venues(int(sim.bases.ids()[0])):
		print("  venue ", v)
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	var who := -1
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) == "colonist" or String(a.get("kind", "")) == "":
			who = int(aid)
			break
	print("who ", who)
	for k in sim.party.KINDS:
		var cid: int = sim.submit("celebrate", {"kind": k, "agent": who})
		sim.step()
		print(k, " -> ", sim.cmds.results[cid])
	print("requests ", sim.relations.requests().size())
	var rows: Array = sim.party.request_rows()
	print(JSON.stringify(rows[0]).substr(0, 600))
	var off: Dictionary = rows[0]
	var cid2: int = sim.submit("answer_request", {"id": int(off["id"]), "answer": "throw"})
	sim.step()
	print("answer ", sim.cmds.results[cid2])
	for s in 200:
		sim.run_seconds(1.0)
		var ps: Array = sim.party.parties()
		if s % 20 == 0:
			for p in ps:
				print(" t=", s, " party ", p["id"], " ", p["phase"], " guests ", p["guests"].size(), " drama ", p["drama"].size(), " fun ", p["score"])
	for e in sim.state["log"]:
		if String(e["code"]).begins_with("party") or String(e["code"]) == "awkward":
			print("  LOG ", e["code"], " ", String(e["text"]).substr(0, 120))
	var talks := 0
	var heat := {}
	for s in 60:
		sim.run_seconds(1.0)
		for t in sim.social.talks():
			talks += 1
			heat[int(t["heat"])] = int(heat.get(int(t["heat"]), 0)) + 1
	print("talk rows ", talks, " heat ", heat)
	sim.dispose()
	quit(0)
