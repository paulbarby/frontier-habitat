extends SceneTree
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(3.0)
	var base: int = int(sim.bases.ids()[0])
	var ppl: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child" and sim.bases.home_of(a) == base:
			ppl.append(a)
	var star: Dictionary = ppl[0]
	var nf := 0
	for pp in ppl:
		if int(pp["id"]) != int(star["id"]) and nf < 4 and not sim.education.in_class(pp) and String(pp["role"]) != "security" and not pp.has("jailed") and String(pp.get("plan_kind", "")) != "sleep" and not pp.has("v5_hold"):
			var fr: Dictionary = sim.relations._rel_w(star, pp)
			fr["aff"] = 45.0
			fr["status"] = "friend"
			print("friend ", pp["id"], " where ", pp["where"], " kind ", pp.get("kind"), " hunger ", pp["hunger"], " thirst ", pp["thirst"], " fat ", pp["fatigue"], " plan ", pp["plan_kind"], " home ", sim.bases.home_of(pp), " party ", pp.has("party"), " lift ", pp.has("lift"))
			nf += 1
	sim.relations._bump()
	var vs: Array = sim.party.venues(base)
	print("venues ", vs.size())
	var reason := {"kind": "promotion", "who": [int(star["id"])], "text": "t", "reason": "a promotion"}
	var g: Array = sim.party._recruit(base, reason, 30, true)
	print("recruit auto ", g)
	var res: Dictionary = sim.party.start_party(base, int(vs[0]["building"]), 1, reason, true)
	print(res)
	sim.dispose()
	quit(0)
