extends RefCounted
## Easter eggs (docs/V5_DESIGN.md section 4.5). Hidden: the awards egg_prism, egg_barby and egg_dance
## (content/awards.json, "hidden": true) are earned when the egg is found (state.v5.eggs {id: tick};
## goals.eval_kind "egg" reads it), and the codex shows an egg only after that.
## 1. PRISM SHIFT: a visit to the dome's gaming lounge is a game on the PRISM SHIFT cabinet. Scores
##    come from a hash of the player and the tick; a new record is a Rag story ("ARCADE KING"). About
##    one person in a thousand is a PRISM SHIFT champion (people.identity egg "champion") with lines
##    of their own. The egg is found with the first record.
## 2. P. Barby: at most once a game, after a super dome opens, a tourist liner brings "P. Barby"
##    (identity egg "barby", vip) who says lines of his own. The Rag leads with the visit.
## 3. Dance code: the Konami code in the follow view (UI) submits {kind: "dance", agent}: the person
##    and their friends in the same room dance (people.action "dance_c"); the egg is found.

const Rng = preload("res://sim/rng.gd")

var sim

func _init(s) -> void:
	sim = s

func _h(x: int, y: int) -> float:
	return Rng.hash2(x, y, int(sim.state.get("seed", 1)) ^ 0xE665)

func _v() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("eggs"):
		v["eggs"] = {}
	if not v.has("arcade"):
		v["arcade"] = {"best": 0, "holder": -1, "plays": 0}
	return v

func found(id: String) -> bool:
	return sim.state.get("v5", {}).get("eggs", {}).has(id)

func _find(id: String) -> void:
	var v: Dictionary = _v()
	if not v["eggs"].has(id):
		v["eggs"][id] = int(sim.state["tick"])

## {best, holder (agent id), plays} of the PRISM SHIFT cabinet.
func arcade() -> Dictionary:
	return sim.state.get("v5", {}).get("arcade", {"best": 0, "holder": -1, "plays": 0}).duplicate()

## A PRISM SHIFT champion (about 1 in 1,000 people).
func is_champion(id: int) -> bool:
	return _h(id, 4242) < 0.001

## A game on the cabinet (leisure.on_rec_end at the gaming lounge).
func on_arcade(a: Dictionary) -> void:
	var v: Dictionary = _v()
	var ar: Dictionary = v["arcade"]
	ar["plays"] = int(ar["plays"]) + 1
	var skill: float = 0.5 + 0.5 * float(sim.people.skills(a).get("piloting", 0)) / 100.0
	var score: int = int((20000.0 + 80000.0 * _h(int(a["id"]), int(sim.state["tick"]))) * skill)
	if is_champion(int(a["id"])):
		score = maxi(score, int(ar["best"]) + 1000 + int(_h(int(a["id"]), 7) * 5000.0))
	a["arcade_last"] = int(sim.state["tick"])
	if score > int(ar["best"]):
		ar["best"] = score
		ar["holder"] = int(a["id"])
		sim.log_event("arcade_record", "%s set a PRISM SHIFT record: %d points." % [String(a["name"]), score], [int(a["id"])], 1, {"score": score})
		_find("prism_shift")

## A tourist liner landed (traffic._land): the one visit of P. Barby, after the dome opened.
func on_liner(arr: Dictionary, visitors: Array) -> void:
	if found("barby") or visitors.is_empty():
		return
	var dome := false
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["def"]) == "super_dome" and b["state"] == "active":
			dome = true
			break
	if not dome or _h(int(arr.get("n", 0)), 99) >= 0.25:
		return
	var a: Dictionary = sim.state["agents"].get(int(visitors[0]), {})
	if a.is_empty():
		return
	a["name"] = "P. Barby"
	a["vip"] = "barby"
	sim.people._id_cache.erase(int(a["id"]))
	_find("barby")
	sim.log_event("barby", "A tourist named P. Barby came to see the dome.", [int(a["id"])], 1)

## The dance code: friends in the same room join in (social.cmd_egg calls it).
func on_dance(a: Dictionary) -> int:
	_find("dance")
	var n := 0
	for rel in sim.relations.relationships_of(int(a["id"]), 8):
		if not ["friend", "best_friend", "dating", "partners", "married"].has(String(rel["status"])):
			continue
		var f: Dictionary = sim.state["agents"].get(int(rel["other"]), {})
		if f.is_empty() or f["state"] != "alive" or f["where"] != "in" or int(f["bld"]) != int(a["bld"]) or f.has("v5_hold") or f.has("jailed"):
			continue
		sim.people.add_mod(f, {"kind": "dance", "text": "Dancing", "comp": "comfort", "sat": 5.0, "att": 1.0, "days": 20.0 / float(sim.bal["day_length"])})
		n += 1
	sim.social.say(a, sim.social.pick_line("dance_egg", a, int(sim.state["tick"])), "dance_egg", -1)
	sim.log_event("dance", "%s started dancing%s." % [String(a["name"]), (" and %d friends joined in" % n) if n > 0 else ""], [int(a["id"])], 0, {"place": int(a["bld"])})
	return n
