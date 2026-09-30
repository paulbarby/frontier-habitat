extends RefCounted
## Reviews and discipline (docs/V5_DESIGN.md sections 6.2 and 6.3). Numbers: content/society.json
## "reviews" and "discipline". Each order adds a timed effect to the person (people.gd add_mod):
## a satisfaction change on one component, an attitude change, and flags (no work, no leisure,
## jail, hunger rate, work speed). Punishments are seen by the base (unrest) and by friends
## (their fairness falls); a punishment of a person whose attitude is fair or good is unfair.

var sim

func _init(s) -> void:
	sim = s

func soc() -> Dictionary:
	return sim.content["society"]

const COMP := {"praise": "social", "bonus_leisure": "comfort", "gift": "social", "warning": "fairness", "extra_shift": "work",
	"ration_cut": "food", "confine": "freedom", "demote": "fairness", "jail": "freedom",
	"excellent": "work", "good": "work", "needs_improvement": "work", "poor": "work"}

func _agent(p: Dictionary) -> Dictionary:
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	if a.is_empty() or a["state"] != "alive":
		return {}
	return a

func _spec(action: String) -> Dictionary:
	if soc()["discipline"].has(action):
		return soc()["discipline"][action]
	return soc()["reviews"].get(action, {})

## Attitude and satisfaction change of an action for this person (traits change the attitude).
func _effect(a: Dictionary, action: String, sp: Dictionary) -> Dictionary:
	var att: float = float(sp.get("attitude", 0.0))
	var trait_text: Array = []
	for tr in sp.get("traits", {}):
		if sim.people.has_trait(a, tr):
			att += float(sp["traits"][tr])
			trait_text.append(tr)
	return {"att": att, "sat": float(sp.get("satisfaction", 0.0)), "traits": trait_text}

## True when a punishment of this person would be seen as unfair (their attitude is fair or good).
func unfair(a: Dictionary, action: String) -> bool:
	var sp: Dictionary = _spec(action)
	if not bool(sp.get("punish", false)):
		return false
	return att_now(a) > float(soc()["unfair_attitude_from"])

## The attitude the simulation uses: the stored value, else the target now (never a query cache).
func att_now(a: Dictionary) -> float:
	var r: Dictionary = sim.people.rec_of(int(a["id"]))
	if r.has("att"):
		return float(r["att"])
	return float(sim.people.attitude_target(a, float(sim.people._satisfaction(a)["value"]))["value"])

## What an order would do, before the player confirms it (the interface shows it):
## {attitude (points), satisfaction (points), others (text), risk (text), unfair (bool), text,
##  days, traits [names that change the effect]}. action: a discipline action or a review grade.
func predict(a: Dictionary, action: String, params: Dictionary = {}) -> Dictionary:
	var sp: Dictionary = _spec(action)
	if sp.is_empty() or a.is_empty():
		return {}
	var e: Dictionary = _effect(a, action, sp)
	var uf: bool = unfair(a, action)
	var others: String = String(sp.get("others", "None."))
	if uf:
		others += " Seen as unfair: unrest rises more."
	var risk: String = String(sp.get("risk", ""))
	if action == "ration_cut" and float(a.get("hunger", 0.0)) > 50.0:
		risk = "Already hungry: health risk is high."
	if bool(sp.get("demote", false)) and not ["commander", "captain", "first_hand"].has(String(sim.people.rank(a)["rank"])):
		risk = "This person has no post to lose."
	var days: float = float(params.get("days", sp.get("days", 1.0)))
	return {"attitude": snappedf(e["att"], 0.1), "satisfaction": snappedf(e["sat"], 0.1), "others": others, "risk": risk, "unfair": uf,
		"text": String(sp.get("text", action)), "days": days, "traits": e["traits"]}

## Command "review" {agent, grade}: excellent, good, needs_improvement, poor.
func cmd_review(p: Dictionary) -> Dictionary:
	var a: Dictionary = _agent(p)
	var grade: String = String(p.get("grade", ""))
	if a.is_empty():
		return {"ok": false, "code": "invalid", "text": "No such person."}
	if not soc()["reviews"].has(grade):
		return {"ok": false, "code": "invalid", "text": "Unknown grade."}
	var sp: Dictionary = soc()["reviews"][grade]
	var e: Dictionary = _effect(a, grade, sp)
	sim.people.add_mod(a, {"kind": "review", "text": String(sp["text"]), "comp": COMP[grade], "sat": e["sat"], "att": e["att"], "days": float(sp["days"])})
	var r: Dictionary = sim.people.rec_w(a)
	r["att"] = clampf(float(r["att"]) + e["att"] * 0.5, -100.0, 100.0)
	r["review"] = {"grade": grade, "tick": int(sim.state["tick"])}
	sim.people.note(a, String(sp["text"]) + ".")
	return {"ok": true, "code": "ok", "text": String(sp["text"]), "attitude": snappedf(e["att"], 0.1)}

## Command "discipline" {agent, action, days (optional)}: praise, bonus_leisure, gift, warning,
## extra_shift, ration_cut, confine, demote, jail.
func cmd_discipline(p: Dictionary) -> Dictionary:
	var a: Dictionary = _agent(p)
	var action: String = String(p.get("action", ""))
	if a.is_empty():
		return {"ok": false, "code": "invalid", "text": "No such person."}
	if not soc()["discipline"].has(action):
		return {"ok": false, "code": "invalid", "text": "Unknown action."}
	if String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
		return {"ok": false, "code": "refused", "text": "Only colonists can be given this order."}
	if action == "demote" and not ["commander", "captain", "first_hand"].has(String(sim.people.rank(a)["rank"])):
		return {"ok": false, "code": "refused", "text": "This person has no post to lose."}
	return apply(a, action, p)

## Applies a discipline action (also used by the unrest responses). params: days, silent.
func apply(a: Dictionary, action: String, params: Dictionary = {}) -> Dictionary:
	var sp: Dictionary = soc()["discipline"][action]
	var e: Dictionary = _effect(a, action, sp)
	var uf: bool = unfair(a, action)
	var days: float = clampf(float(params.get("days", sp.get("days", 1.0))), 0.25, 5.0)
	var now: int = int(sim.state["tick"])
	var m := {"kind": action, "text": String(sp["text"]), "comp": COMP[action], "sat": e["sat"], "att": e["att"], "days": days}
	for k in ["no_work", "no_rec", "jail", "hunger_mult", "work_mult"]:
		if sp.has(k):
			m[k] = sp[k]
	if action == "jail" and not _has_jail(a):
		# Without a jail the person is confined to quarters instead (weaker).
		m.erase("jail")
		m["text"] = "Confined to quarters (no jail)"
	sim.people.add_mod(a, m)
	var r: Dictionary = sim.people.rec_w(a)
	r["att"] = clampf(float(r["att"]) + e["att"], -100.0, 100.0)
	if sp.has("fatigue"):
		a["fatigue"] = minf(100.0, float(a["fatigue"]) + float(sp["fatigue"]))
	if bool(sp.get("leisure", false)):
		a["last_rec"] = now
	if bool(sp.get("demote", false)):
		_demote(a, now)
	sim.people.note(a, String(m["text"]) + (" (unfair)" if uf else "") + ".")
	if bool(sp.get("punish", false)):
		var base: int = sim.bases.home_of(a) if sim.bases.count() > 0 else -1
		sim.unrest.add_punishment(base, uf)
		_friends_see(a, uf)
		if not bool(params.get("silent", false)):
			sim.log_event("discipline", "%s: %s." % [String(a["name"]), String(m["text"]).to_lower()], [int(a["id"])], 1, {"action": action, "unfair": uf})
	return {"ok": true, "code": "ok", "text": String(m["text"]), "unfair": uf, "attitude": snappedf(e["att"], 0.1)}

func _has_jail(a: Dictionary) -> bool:
	var base: int = sim.bases.home_of(a) if sim.bases.count() > 0 else -1
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["def"]) == "jail" and b["state"] == "active" and (base == -1 or sim.bases.base_of(int(id)) == base):
			return true
	return false

func _demote(a: Dictionary, now: int) -> void:
	var appt: Dictionary = sim.people.v5w()["appoint"]
	var id: int = int(a["id"])
	for k in appt.keys():
		if k == "demoted":
			continue
		var v = appt[k]
		if typeof(v) == TYPE_ARRAY:
			(v as Array).erase(id)
		elif int(v) == id:
			appt.erase(k)
	sim.people.set_demoted(a, now + 3 * int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"])))
	sim.people._rank_sig = -1

## Friends of a punished person see it: their fairness falls for some days.
func _friends_see(a: Dictionary, uf: bool) -> void:
	var fc: Dictionary = soc()["friends_fairness"]
	var d: float = float(fc["unfair"]) if uf else float(fc["punish"])
	for rel in sim.relations.relationships_of(int(a["id"]), 8):
		if not ["friend", "best_friend", "dating", "partner"].has(String(rel["status"])):
			continue
		var f: Dictionary = sim.state["agents"].get(int(rel["other"]), {})
		if f.is_empty() or f["state"] != "alive":
			continue
		sim.people.add_mod(f, {"kind": "friend_punished", "text": "A friend was punished", "comp": "fairness", "sat": d, "att": d * 0.3, "days": float(fc["days"])})
