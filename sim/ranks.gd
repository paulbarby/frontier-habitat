extends RefCounted
## Appointments (docs/V5_DESIGN.md section 5.1). The player appoints the commander of a base and
## the captain and first hands of a department; SIM proposes the rest (people.gd _refresh_ranks).
## Stored in state.v5.appoint: "base:commander" -> id, "base:dep:captain" -> id,
## "base:dep:first_hand" -> [ids] (at most per_department).

var sim

func _init(s) -> void:
	sim = s

## Command "appoint" {agent, rank (commander | captain | first_hand), department, base}.
func cmd_appoint(p: Dictionary) -> Dictionary:
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	var r: String = String(p.get("rank", ""))
	if a.is_empty() or a["state"] != "alive" or String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
		return {"ok": false, "code": "invalid", "text": "Only a colonist can take a post."}
	if not ["commander", "captain", "first_hand"].has(r):
		return {"ok": false, "code": "invalid", "text": "Unknown rank."}
	var base: int = int(p.get("base", -1))
	var home: int = sim.bases.home_of(a) if sim.bases.count() > 0 else -1
	if base == -1:
		base = home
	if base != home:
		return {"ok": false, "code": "refused", "text": "This person lives at another base."}
	var deps: Dictionary = sim.content["people"]["departments"]
	var dep: String = String(p.get("department", sim.people.department(a)))
	if r != "commander":
		if not deps.has(dep):
			return {"ok": false, "code": "invalid", "text": "Unknown department."}
		if not (deps[dep]["roles"] as Array).has(String(a["role"])):
			return {"ok": false, "code": "refused", "text": "%s works in another department." % String(a["name"]).split(" ")[0]}
	var appt: Dictionary = sim.people.v5w()["appoint"]
	var id: int = int(a["id"])
	# One post per person: the old one is left.
	for k in appt.keys():
		if k == "demoted":
			continue
		var v = appt[k]
		if typeof(v) == TYPE_ARRAY:
			(v as Array).erase(id)
		elif int(v) == id:
			appt.erase(k)
	var old_holder := -1
	match r:
		"commander":
			old_holder = int(appt.get("%d:commander" % base, -1))
			appt["%d:commander" % base] = id
		"captain":
			old_holder = int(appt.get("%d:%s:captain" % [base, dep], -1))
			appt["%d:%s:captain" % [base, dep]] = id
		"first_hand":
			var key: String = "%d:%s:first_hand" % [base, dep]
			var arr: Array = appt.get(key, [])
			var cap: int = int(sim.content["people"]["ranks"]["first_hand"]["per_department"])
			while arr.size() >= cap:
				old_holder = int(arr.pop_front())
			arr.append(id)
			appt[key] = arr
	var rec: Dictionary = sim.people.rec_w(a)
	sim.people.clear_demoted(a)
	sim.people._rank_sig = -1
	sim.people._refresh_ranks(true)
	var title: String = String(sim.people.rank(a)["title"])
	sim.people.add_mod(a, {"kind": "promoted", "text": "Appointed " + title, "comp": "work", "sat": 10.0, "att": 8.0, "days": 2.0})
	sim.people.note(a, "Appointed %s." % title)
	if old_holder != -1 and old_holder != id and sim.state["agents"].has(old_holder):
		var o: Dictionary = sim.state["agents"][old_holder]
		if o["state"] == "alive":
			sim.people.add_mod(o, {"kind": "replaced", "text": "Lost the post of " + r.replace("_", " "), "comp": "fairness", "sat": -8.0, "att": -6.0, "days": 2.0})
			sim.people.note(o, "Replaced by %s." % String(a["name"]))
	sim.log_event("promotion", "%s is now %s." % [String(a["name"]), title], [id], 1, {"rank": r, "department": dep})
	return {"ok": true, "code": "ok", "text": "%s is now %s." % [String(a["name"]), title], "replaced": old_holder}
