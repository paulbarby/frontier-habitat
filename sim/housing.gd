extends RefCounted
## Homes (docs/V5_DESIGN.md section 7): the player moves a person into a home with a free bed.
## The bed is the home (agents.gd keeps a valid bed); the unit is stored in the person's record.

var sim

func _init(s) -> void:
	sim = s

## Free beds of a housing structure (the lander and habitats included).
func free_beds(b: Dictionary) -> int:
	return int(sim.bd(b).get("beds", 0)) - sim.agents.beds_used(int(b["id"]))

## Command "set_home" {agent, building, unit (optional, -1)}.
func cmd_set_home(p: Dictionary) -> Dictionary:
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	var bid: int = int(p.get("building", -1))
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if a.is_empty() or a["state"] != "alive" or String(a.get("kind", "")) == "visitor":
		return {"ok": false, "code": "invalid", "text": "No such person."}
	if b.is_empty() or int(sim.bd(b).get("beds", 0)) <= 0:
		return {"ok": false, "code": "invalid", "text": "Choose a structure with beds."}
	if b["state"] != "active":
		return {"ok": false, "code": "refused", "text": "The home is not finished."}
	if int(a["bed"]) == bid:
		sim.people.rec_w(a)["unit"] = int(p.get("unit", -1))
		sim.people.invalidate(int(a["id"]))
		return {"ok": true, "code": "ok", "text": "Already lives here."}
	if free_beds(b) <= 0:
		return {"ok": false, "code": "full", "text": "No free bed there."}
	if sim.bases.count() > 1 and sim.bases.base_of(bid) != sim.bases.home_of(a):
		return {"ok": false, "code": "refused", "text": "That home is at another base."}
	sim.agents._set_bed(a, bid)
	var u: int = int(p.get("unit", -1))
	var r: Dictionary = sim.people.rec_w(a)
	if u >= 0:
		r["unit"] = u
	else:
		r.erase("unit")
	sim.people.invalidate(int(a["id"]))
	sim.people._rank_sig = -1
	sim.people.note(a, "Moved to %s." % String(b.get("name", b["def"])))
	return {"ok": true, "code": "ok", "text": "%s moved to %s." % [String(a["name"]), String(b.get("name", b["def"]))]}
