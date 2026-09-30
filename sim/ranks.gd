extends RefCounted
## Appointments (docs/V5_DESIGN.md section 5.1). The player appoints the commander of a base and
## the captain and first hands of a department; SIM proposes the rest (people.gd _refresh_ranks).
## Stored in state.v5.appoint: "base:commander" -> id, "base:dep:captain" -> id,
## "base:dep:first_hand" -> [ids] (at most per_department).

var sim

func _init(s) -> void:
	sim = s

## The agent id of a base's commander (-1: any base; the lowest id), or -1 when there is none.
func commander(base_id: int = -1) -> int:
	var best := -1
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var rk: Dictionary = sim.people.rank(a)
		if String(rk["rank"]) == "commander" and (base_id == -1 or int(rk["base"]) == base_id) and (best == -1 or int(aid) < best):
			best = int(aid)
	return best

## Command "set_role" {agent, role}: retraining (V5 section 6.5). A security officer needs the
## security skill at role_skill (content security) or more (the academy teaches it); the other roles
## are open to any adult colonist. A post in the old department is left.
func cmd_set_role(p: Dictionary) -> Dictionary:
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	var role: String = String(p.get("role", ""))
	if a.is_empty() or a["state"] != "alive" or String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
		return {"ok": false, "code": "invalid", "text": "Only a colonist can change jobs."}
	var roles: Array = (sim.bal["roles"] as Array).duplicate()
	roles.append("security")
	if not roles.has(role):
		return {"ok": false, "code": "invalid", "text": "Unknown role."}
	if role == String(a["role"]):
		return {"ok": true, "code": "ok", "text": "No change."}
	var need: int = int(sim.content["society"]["security"]["role_skill"])
	if role == "security" and int(sim.people.skills(a)["security"]) < need:
		return {"ok": false, "code": "refused", "text": "A security officer needs security %d or more (a course at the academy)." % need}
	var appt: Dictionary = sim.people.v5w()["appoint"]
	var id: int = int(a["id"])
	for k in appt.keys():
		if k == "demoted" or String(k).ends_with(":commander"):
			continue
		var v = appt[k]
		if typeof(v) == TYPE_ARRAY:
			(v as Array).erase(id)
		elif int(v) == id:
			appt.erase(k)
	sim.agents.abort_plan(a, "new_role")
	var old: String = String(a["role"])
	a["role"] = role
	sim.people.invalidate(id)
	sim.people.ranks_dirty()
	var names: Dictionary = sim.bal["role_names"]
	sim.people.note(a, "Changed job: %s to %s." % [String(names.get(old, old)).to_lower(), String(names.get(role, role)).to_lower()])
	sim.log_event("new_role", "%s is now a %s." % [String(a["name"]), String(names.get(role, role)).to_lower()], [id], 1)
	return {"ok": true, "code": "ok", "text": "%s is now a %s." % [String(a["name"]), String(names.get(role, role)).to_lower()]}

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
	sim.people.ranks_dirty()
	sim.people._refresh_ranks(true)
	var title: String = String(sim.people.rank(a)["title"])
	sim.people.add_mod(a, {"kind": "promoted", "text": "Appointed " + title, "comp": "work", "sat": 10.0, "att": 8.0, "days": 2.0})
	sim.people.note(a, "Appointed %s." % title)
	if old_holder != -1 and old_holder != id and sim.state["agents"].has(old_holder):
		var o: Dictionary = sim.state["agents"][old_holder]
		if o["state"] == "alive":
			sim.people.add_mod(o, {"kind": "replaced", "text": "Lost the post of " + r.replace("_", " "), "comp": "fairness", "sat": -8.0, "att": -6.0, "days": 2.0})
			sim.people.note(o, "Replaced by %s." % String(a["name"]))
			# V5 section 5.1: a promotion makes a rival of the one who lost the post.
			var rr: Dictionary = sim.relations._rel_w(a, o)
			rr["aff"] = clampf(float(rr["aff"]) - 25.0, -100.0, 100.0)
			sim.relations._update_status(rr, a, o, "")
	sim.log_event("promotion", "%s is now %s." % [String(a["name"]), title], [id], 1, {"rank": r, "department": dep})
	return {"ok": true, "code": "ok", "text": "%s is now %s." % [String(a["name"]), title], "replaced": old_holder}
