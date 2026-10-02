extends RefCounted
## The HR department (docs/V5_DESIGN.md section 17): complaints, feedback rounds, transfers off world, and the
## HR officer who is loved in public and gossiped about in private. Everything here exists only while an HR
## office (structure hr_office) is active, powered and has an officer (role "hr"). Text: content/hr.json;
## numbers: content/society.json "hr".
##
## Stored (schema 6, state.v5.hr; an old save gets an empty record on first use):
##   complaints {id: {id, agent, category, target {kind, id, name}, tick, state ("walking"|"open"|"hr_working"|"resolved"),
##                    text, office, base, deadline, resolve_at, outcome, needs_player, expires}},
##   transfers {id: {id, agent, reason, text, tick, expires, base, department, state ("open"|"approved"|"left"), ship}},
##   surveys {base: {tick, day, base, depts, top3, morale_trend}}, rep {officer id: {public, private}},
##   last {agent id: {complaint, transfer} (days)}, refusals {base: n}, day (last daily scan), survey_day {base: day}.
## On an agent: hr_visit ("queue" | "interview" | "kiosk") while the person is at the HR office.

const Rng = preload("res://sim/rng.gd")

var sim
var _oc_tick := -1
var _oc_any := false

func _init(s) -> void:
	sim = s

## Is there any active HR office at all? Made once a tick, and only when asked (talks ask).
func _any_office() -> bool:
	var tick: int = int(sim.state["tick"])
	if tick != _oc_tick:
		_oc_tick = tick
		_oc_any = not offices(-1).is_empty()
	return _oc_any

func cfg() -> Dictionary:
	return sim.content["society"]["hr"]

func lines() -> Dictionary:
	return sim.content["hr"]

func _h(x: int, y: int) -> float:
	return Rng.hash2(x, y, int(sim.state.get("seed", 1)) ^ 0x48A5)

func _hz() -> int:
	return int(sim.bal["tick_hz"])

func _day() -> int:
	return int(float(sim.bal["day_length"]) * float(_hz()))

func _w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("hr"):
		v["hr"] = {"complaints": {}, "transfers": {}, "surveys": {}, "rep": {}, "last": {}, "refusals": {}, "day": -1, "survey_day": {}}
	return v["hr"]

func _r() -> Dictionary:
	return sim.state.get("v5", {}).get("hr", {})

func _first(a: Dictionary) -> String:
	return String(a.get("name", "")).split(" ")[0]

func _adult(a: Dictionary) -> bool:
	return not a.is_empty() and a["state"] == "alive" and String(a.get("kind", "")) != "child" and String(a.get("kind", "")) != "visitor"

func _home(a: Dictionary) -> int:
	return int(sim.bases.home_of(a)) if sim.bases.count() > 0 else -1

# ---------------------------------------------------------------- the office and its staff
## The active HR offices of a base (-1: all): powered and supplied, not being removed.
func offices(base: int = -1) -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for bid in blds:
		var b: Dictionary = blds[bid]
		if String(b["def"]) != "hr_office" or b["state"] != "active" or bool(b["demolish"]) or not sim.util.building_supplied(int(bid)):
			continue
		if base != -1 and sim.bases.count() > 0 and int(sim.bases.base_of(int(bid))) != base:
			continue
		out.append(int(bid))
	return out

## Officer posts of a base: the sum over its active offices (size S 1, M 2, L 3).
func slots(base: int = -1) -> int:
	var n := 0
	var sl: Array = cfg()["slots"]
	for bid in offices(base):
		n += int(sl[clampi(int(sim.state["buildings"][bid].get("size", 1)), 0, sl.size() - 1)])
	return n

## The HR officers of a base: colonists with the role hr, as many as there are posts (lowest ids first).
func officers(base: int = -1) -> Array:
	var out: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	var limit: int = slots(base)
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if String(a.get("role", "")) != "hr" or not _adult(a):
			continue
		if base != -1 and sim.bases.count() > 0 and _home(a) != base:
			continue
		if out.size() < limit:
			out.append(int(aid))
	return out

## True while an HR office is active and has an officer (base -1: any base).
func active(base: int = -1) -> bool:
	return slots(base) > 0 and not officers(base).is_empty()

func is_officer(a: Dictionary) -> bool:
	return String(a.get("role", "")) == "hr" and _adult(a)

## Where an officer stands: the officer goes to the office desk and works there (people.duty_think).
func desk_think(a: Dictionary) -> bool:
	var base: int = _home(a)
	var offs: Array = offices(base)
	if offs.is_empty() or not officers(base).has(int(a["id"])):
		return false
	var ids: Array = officers(base)
	var bid: int = int(offs[ids.find(int(a["id"])) % offs.size()])
	if int(a["bld"]) == bid and a["where"] == "in":
		sim.agents._start_plan(a, "hr", [{"op": "wait", "t": 20.0}], "At the HR desk")
		return true
	return sim.agents._start_personal(a, "hr", bid, [{"op": "wait", "t": 20.0}], "Going to the HR desk", ids.find(int(a["id"])))

## A complainant on the way to the office (people.duty_think).
func visit_think(a: Dictionary) -> bool:
	var office: int = int(a.get("hr_office", -1))
	if office == -1 or not sim.state["buildings"].has(office):
		a.erase("hr_visit")
		a.erase("hr_office")
		return false
	if int(a["bld"]) == office and a["where"] == "in":
		return false
	return sim.agents._start_personal(a, "hr_visit", office, [{"op": "wait", "t": 12.0}], "Going to HR", -1)

# ---------------------------------------------------------------- reputation (rule 6)
func _rep_w(id: int) -> Dictionary:
	var r: Dictionary = _w()
	if not r["rep"].has(id):
		r["rep"][id] = {"public": float(cfg()["rep_public_start"]), "private": float(cfg()["rep_private_start"])}
	return r["rep"][id]

## {public 0..100 (what people say to the officer's face), private -100..100 (behind their back), officer}.
func reputation(agent_id: int) -> Dictionary:
	var a: Dictionary = sim.state["agents"].get(agent_id, {})
	var rec: Dictionary = _r().get("rep", {}).get(agent_id, {})
	return {"public": float(rec.get("public", cfg()["rep_public_start"])), "private": float(rec.get("private", cfg()["rep_private_start"])), "officer": not a.is_empty() and is_officer(a)}

func _bump_rep(id: int, pub: float, priv: float) -> void:
	var rp: Dictionary = _rep_w(id)
	rp["public"] = clampf(float(rp["public"]) + pub, 0.0, 100.0)
	rp["private"] = clampf(float(rp["private"]) + priv, -100.0, 100.0)

## Topic of a talk when an HR officer is in it (public praise) or the talk is behind their back (gossip):
## {topic, heat} or {}. Never between children.
func talk_topic(x: Dictionary, y: Dictionary, salt: int) -> Dictionary:
	if not _any_office():
		return {}
	var ox: bool = is_officer(x)
	var oy: bool = is_officer(y)
	var base: int = _home(x)
	var c: Dictionary = cfg()
	if ox != oy:
		var off: Dictionary = x if ox else y
		var other: Dictionary = y if ox else x
		if _adult(other) and active(_home(off)) and _h(salt, int(other["id"]) + 3) < float(c["praise_chance"]):
			_bump_rep(int(off["id"]), float(c["praise_up"]), 0.0)
			return {"topic": "hr_praise", "heat": 0}
		return {}
	if ox and oy:
		return {}
	if not _adult(x) or not _adult(y):
		return {}
	var offs: Array = officers(base)
	if offs.is_empty() or not active(base):
		return {}
	if _h(salt, int(x["id"]) + 9) < float(c["gossip_chance"]):
		_bump_rep(int(offs[int(_h(salt, 4) * offs.size()) % offs.size()]), 0.0, float(c["private_down"]))
		return {"topic": "hr_gossip", "heat": 0}
	return {}

## The officer a gossip line is about (first officer of the base).
func officer_name(a: Dictionary) -> String:
	var offs: Array = officers(_home(a))
	if offs.is_empty():
		return "the HR officer"
	return _first(sim.state["agents"][int(offs[0])])

# ---------------------------------------------------------------- requests of the player
func has_request(id: int) -> bool:
	var r: Dictionary = _r()
	return r.get("complaints", {}).has(id) or r.get("transfers", {}).has(id)

func _options_of(c: Dictionary) -> Array:
	var spec: Dictionary = lines()["complaint"][String(c["category"])]
	var out: Array = []
	var a: String = _first(sim.state["agents"].get(int(c["agent"]), {}))
	for o in spec["options"]:
		out.append({"id": String(o["id"]), "text": String(o["text"]), "effect": String(o["effect"]).replace("{a}", a)})
	return out

func _complaint_text(c: Dictionary) -> String:
	var spec: Dictionary = lines()["complaint"][String(c["category"])]
	var a: String = _first(sim.state["agents"].get(int(c["agent"]), {}))
	var b: String = String(c["target"].get("name", "someone"))
	return String(spec["text"]).replace("{a}", a).replace("{b}", b)

func _crow(c: Dictionary) -> Dictionary:
	return {"id": int(c["id"]), "agent": int(c["agent"]), "category": String(c["category"]), "target": (c["target"] as Dictionary).duplicate(), "tick": int(c["tick"]),
		"state": String(c["state"]), "text": String(c["text"]), "options": _options_of(c) if String(c["state"]) == "open" else [], "base": int(c["base"]), "outcome": String(c.get("outcome", ""))}

func complaints() -> Array:
	var out: Array = []
	var cs: Dictionary = _r().get("complaints", {})
	var ids: Array = cs.keys()
	ids.sort()
	for id in ids:
		out.append(_crow(cs[id]))
	return out

func _trow(t: Dictionary) -> Dictionary:
	return {"id": int(t["id"]), "agent": int(t["agent"]), "reason": String(t["reason"]), "text": String(t["text"]), "tick": int(t["tick"]), "department": String(t["department"]),
		"state": String(t["state"]), "base": int(t["base"]), "ship": int(t.get("ship", -1))}

func transfers() -> Array:
	var out: Array = []
	var ts: Dictionary = _r().get("transfers", {})
	var ids: Array = ts.keys()
	ids.sort()
	for id in ids:
		out.append(_trow(ts[id]))
	return out

## The rows of the Requests tab: open complaints (the ones that need the player) and open transfer requests.
func request_rows() -> Array:
	var out: Array = []
	var r: Dictionary = _r()
	if r.is_empty():
		return out
	var ids: Array = r["complaints"].keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = r["complaints"][id]
		if String(c["state"]) == "open":
			out.append({"id": int(id), "kind": "hr_complaint", "agent": int(c["agent"]), "other": int(c["target"].get("id", -1)), "ship": -1, "tick": int(c["tick"]), "text": String(c["text"]),
				"options": _options_of(c), "expires": int(c["expires"]), "reason": String(c["category"]), "place_choices": [], "base": int(c["base"])})
	var tids: Array = r["transfers"].keys()
	tids.sort()
	for id in tids:
		var t: Dictionary = r["transfers"][id]
		if String(t["state"]) == "open":
			var a: String = _first(sim.state["agents"].get(int(t["agent"]), {}))
			var opts: Array = []
			for o in lines()["transfer"]["options"]:
				opts.append({"id": String(o["id"]), "text": String(o["text"]), "effect": String(o["effect"]).replace("{a}", a)})
			out.append({"id": int(id), "kind": "hr_transfer", "agent": int(t["agent"]), "other": -1, "ship": -1, "tick": int(t["tick"]), "text": String(t["text"]), "options": opts,
				"expires": int(t["expires"]), "reason": String(t["reason"]), "place_choices": [], "base": int(t["base"])})
	return out

## The last feedback round of a base ({} before the first; base -1: the first base with a round).
func survey(base: int = -1) -> Dictionary:
	var sv: Dictionary = _r().get("surveys", {})
	if base != -1:
		return (sv[base] as Dictionary).duplicate(true) if sv.has(base) else {}
	var ks: Array = sv.keys()
	ks.sort()
	return (sv[ks[0]] as Dictionary).duplicate(true) if not ks.is_empty() else {}

# ---------------------------------------------------------------- answers
func answer(p: Dictionary) -> Dictionary:
	var r: Dictionary = _w()
	var id: int = int(p.get("id", -1))
	var ans: String = String(p.get("answer", ""))
	if r["transfers"].has(id):
		return _answer_transfer(r["transfers"][id], ans)
	if not r["complaints"].has(id):
		return {"ok": false, "code": "invalid", "text": "No such request."}
	var c: Dictionary = r["complaints"][id]
	var a: Dictionary = sim.state["agents"].get(int(c["agent"]), {})
	if a.is_empty() or a["state"] != "alive":
		r["complaints"].erase(id)
		return {"ok": true, "code": "ok", "text": "The request no longer applies."}
	var ok := false
	for o in _options_of(c):
		if String(o["id"]) == ans:
			ok = true
	if not ok:
		return {"ok": false, "code": "invalid", "text": "Choose one of the options."}
	var officer: int = int(officers(int(c["base"]))[0]) if not officers(int(c["base"])).is_empty() else -1
	var skill: float = _skill_of(officer)
	var now: int = int(sim.state["tick"])
	match ans:
		"leave_to_hr":
			c["state"] = "hr_working"
			c["resolve_at"] = now + int(float(cfg()["work_days"]) * float(_day()))
			return {"ok": true, "code": "ok", "text": "HR is working on it."}
		"dismiss":
			sim.people.add_mod(a, {"kind": "hr_dismissed", "text": "A complaint was dismissed", "comp": "fairness", "sat": -6.0, "att": -5.0, "days": 2.0})
			if officer != -1:
				_bump_rep(officer, -2.0, 0.0)
			return _resolve(c, "dismissed", "The complaint is dismissed. %s is not happy." % _first(a))
		"leisure_day":
			sim.people.add_mod(a, {"kind": "leisure_day", "text": "A day off", "comp": "comfort", "sat": 8.0, "att": 3.0, "days": 1.0, "no_work": true})
			a["last_rec"] = now
			sim.agents.abort_plan(a, "leisure_day")
			return _resolve(c, "leisure_day", "%s has a day off." % _first(a))
		"mediate":
			var good: bool = _h(int(c["id"]), now / 100) < clampf(0.4 + 0.5 * skill / 100.0, 0.05, 0.95)
			if not good:
				sim.people.add_mod(a, {"kind": "hr_failed", "text": "Mediation failed", "comp": "social", "sat": -1.0, "att": -1.0, "days": 1.0})
				return _resolve(c, "failed", "HR could not bridge it.")
			if String(c["category"]) == "feud":
				var o: Dictionary = sim.state["agents"].get(int(c["target"].get("id", -1)), {})
				if not o.is_empty() and o["state"] == "alive":
					var rel: Dictionary = sim.relations._rel_w(a, o)
					rel["aff"] = clampf(float(rel["aff"]) + 14.0, -100.0, 100.0)
					sim.relations._update_status(rel, a, o, "")
					for x in [a, o]:
						sim.people.add_mod(x, {"kind": "mediated", "text": "A feud was mediated", "comp": "social", "sat": 4.0, "att": 3.0, "days": 2.0})
			else:
				sim.people.end_mods(a, ["warning", "extra_shift", "ration_cut", "confine", "demote"])
				sim.people.add_mod(a, {"kind": "mediated", "text": "Heard and cleared", "comp": "fairness", "sat": 6.0, "att": 4.0, "days": 2.0})
			if officer != -1:
				_bump_rep(officer, 1.0, 0.0)
			return _resolve(c, "fixed", "HR mediated. %s is calmer." % _first(a))
		"move_home":
			var res: Dictionary = _move_home(a)
			if not bool(res["ok"]):
				return res
			sim.people.add_mod(a, {"kind": "new_home", "text": "A better home", "comp": "housing", "sat": 4.0, "att": 3.0, "days": 2.0})
			if officer != -1:
				_bump_rep(officer, 1.0, 0.0)
			return _resolve(c, "fixed", String(res["text"]))
		"change_job":
			var role: String = _best_other_role(a)
			if role == "":
				return {"ok": false, "code": "refused", "text": "No other job fits."}
			var cr: Dictionary = sim.ranks.cmd_set_role({"agent": int(a["id"]), "role": role})
			if not bool(cr.get("ok", false)):
				return cr
			sim.people.add_mod(a, {"kind": "new_job", "text": "A new job", "comp": "work", "sat": 5.0, "att": 3.0, "days": 2.0})
			if officer != -1:
				_bump_rep(officer, 1.0, 0.0)
			return _resolve(c, "fixed", String(cr.get("text", "A new job.")))
	return {"ok": false, "code": "invalid", "text": "Unknown option."}

func _skill_of(officer_id: int) -> float:
	var o: Dictionary = sim.state["agents"].get(officer_id, {})
	if o.is_empty():
		return 0.0
	var sk: Dictionary = sim.people.skills(o)
	return maxf(float(sk.get("social", 0)), float(sk.get("leadership", 0)))

func _resolve(c: Dictionary, outcome: String, text: String) -> Dictionary:
	c["state"] = "resolved"
	c["outcome"] = outcome
	c["resolved_tick"] = int(sim.state["tick"])
	var a: Dictionary = sim.state["agents"].get(int(c["agent"]), {})
	sim.log_event("hr_resolved", "HR: %s (%s)" % [text, outcome], [int(c["agent"])], 0, {"complaint": int(c["id"]), "outcome": outcome})
	if not a.is_empty():
		sim.people.note(a, "HR: %s" % text)
	return {"ok": true, "code": "ok", "text": text}

func _best_other_role(a: Dictionary) -> String:
	var sk: Dictionary = sim.people.skills(a)
	var best := ""
	var bv := -1.0
	for role in sim.bal["roles"]:
		if String(role) == String(a["role"]):
			continue
		var mine: Array = sim.content["people"]["role_skills"].get(String(role), [])
		var v := 0.0
		for s in mine:
			v += float(sk.get(s, 0))
		if v > bv:
			bv = v
			best = String(role)
	return best

func _comfort_of(bid: int) -> float:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty():
		return -1.0
	return float(sim.bd(b).get("comfort", 0.0)) + 10.0 * float(sim.content["people"]["housing_quality"].get("executive" if String(b["def"]).contains("executive") else "family", 1))

func _move_home(a: Dictionary) -> Dictionary:
	var cur: float = _comfort_of(int(a.get("bed", -1)))
	var best := -1
	var bv: float = cur
	var blds: Dictionary = sim.state["buildings"]
	for bid in blds:
		var b: Dictionary = blds[bid]
		if b["state"] != "active" or int(sim.bd(b).get("beds", 0)) <= 0 or int(bid) == int(a.get("bed", -1)):
			continue
		if sim.bases.count() > 1 and int(sim.bases.base_of(int(bid))) != _home(a):
			continue
		if sim.housing.free_beds(b) <= 0:
			continue
		var v: float = _comfort_of(int(bid))
		if v > bv:
			bv = v
			best = int(bid)
	if best == -1:
		return {"ok": false, "code": "full", "text": "No better home is free."}
	return sim.housing.cmd_set_home({"agent": int(a["id"]), "building": best})

func _answer_transfer(t: Dictionary, ans: String) -> Dictionary:
	var r: Dictionary = _w()
	var a: Dictionary = sim.state["agents"].get(int(t["agent"]), {})
	if a.is_empty() or a["state"] != "alive":
		r["transfers"].erase(int(t["id"]))
		return {"ok": true, "code": "ok", "text": "The request no longer applies."}
	var c: Dictionary = cfg()
	if ans == "approve":
		t["state"] = "approved"
		sim.log_event("hr_transfer_approved", "%s will leave on the next ship." % String(a["name"]), [int(a["id"])], 1, {"transfer": int(t["id"])})
		sim.people.note(a, "Transfer approved: leaving on the next ship.")
		sim.people.add_mod(a, {"kind": "transfer_ok", "text": "Going home soon", "comp": "freedom", "sat": 8.0, "att": 5.0, "days": 3.0})
		return {"ok": true, "code": "ok", "text": "%s leaves on the next ship with seats." % _first(a)}
	if ans == "refuse":
		sim.people.add_mod(a, {"kind": "transfer_refused", "text": "Transfer refused", "comp": "freedom", "sat": float(c["refuse_sat"]), "att": float(c["refuse_att"]), "days": float(c["refuse_days"])})
		sim.people.note(a, "Transfer refused.")
		var base: int = int(t["base"])
		r["refusals"][base] = int(r["refusals"].get(base, 0)) + 1
		sim.unrest.add_punishment(base, true)
		for k in int(float(c["refuse_unrest_each"])) - 1:
			sim.unrest.add_punishment(base, false)
		var last: Dictionary = _last(int(a["id"]))
		last["transfer"] = int(sim.state["tick"]) / _day()
		r["transfers"].erase(int(t["id"]))
		sim.log_event("hr_transfer_refused", "%s's transfer is refused." % String(a["name"]), [int(a["id"])], 1, {"transfer": int(t["id"])})
		return {"ok": true, "code": "ok", "text": "Refused. %s is unhappy." % _first(a)}
	return {"ok": false, "code": "invalid", "text": "Answer approve or refuse."}

func _last(id: int) -> Dictionary:
	var r: Dictionary = _w()
	if not r["last"].has(id):
		r["last"][id] = {"complaint": -1000, "transfer": -1000}
	return r["last"][id]

# ---------------------------------------------------------------- once a second
func tick_second() -> void:
	var r: Dictionary = _r()
	var now: int = int(sim.state["tick"])
	var day: int = now / _day()
	if r.is_empty() or int(r["day"]) != day:
		_daily(day)
		r = _r()
	if r.is_empty():
		return
	if r["complaints"].is_empty() and r["transfers"].is_empty():
		return
	# HR closed (the office is gone, unpowered or without an officer): what is open lapses.
	var bases_ok := {}
	for id in r["complaints"].keys():
		var c: Dictionary = r["complaints"][id]
		var b: int = int(c["base"])
		if not bases_ok.has(b):
			bases_ok[b] = active(b)
		if not bool(bases_ok[b]) and String(c["state"]) != "resolved":
			_clear_visit(c)
			r["complaints"].erase(id)
			continue
		_complaint_second(c, now)
	for id in r["transfers"].keys():
		var t: Dictionary = r["transfers"][id]
		var b2: int = int(t["base"])
		if String(t["state"]) == "open":
			if not bases_ok.has(b2):
				bases_ok[b2] = active(b2)
			if not bool(bases_ok[b2]):
				r["transfers"].erase(id)
			elif now >= int(t["expires"]):
				var a: Dictionary = sim.state["agents"].get(int(t["agent"]), {})
				if not a.is_empty():
					sim.people.add_mod(a, {"kind": "transfer_ignored", "text": "Nobody answered the transfer", "comp": "freedom", "sat": -6.0, "att": -6.0, "days": 2.0})
				r["transfers"].erase(id)
		elif String(t["state"]) == "approved":
			_depart(t)
		elif String(t["state"]) == "left" and now > int(t.get("left_tick", now)) + _day():
			r["transfers"].erase(id)

func _clear_visit(c: Dictionary) -> void:
	var a: Dictionary = sim.state["agents"].get(int(c["agent"]), {})
	if not a.is_empty():
		a.erase("hr_visit")
		a.erase("hr_office")
		if String(a.get("plan_kind", "")) == "hr_visit":
			sim.agents.abort_plan(a, "hr_closed")

func _complaint_second(c: Dictionary, now: int) -> void:
	var a: Dictionary = sim.state["agents"].get(int(c["agent"]), {})
	if a.is_empty() or a["state"] != "alive":
		sim.state["v5"]["hr"]["complaints"].erase(int(c["id"]))
		return
	match String(c["state"]):
		"walking":
			var at: bool = int(a["bld"]) == int(c["office"]) and a["where"] == "in"
			if at or now >= int(c["deadline"]):
				_file(c, a, now)
		"open":
			if a.has("hr_visit") and String(a.get("plan_kind", "")) != "hr_visit":
				a.erase("hr_visit")
				a.erase("hr_office")
			if now >= int(c["expires"]):
				answer({"id": int(c["id"]), "answer": "dismiss"})
		"hr_working":
			if now >= int(c["resolve_at"]):
				var officer: int = int(officers(int(c["base"]))[0]) if not officers(int(c["base"])).is_empty() else -1
				var p: float = float(cfg()["hr_resolve_base"]) + float(cfg()["hr_resolve_skill"]) * _skill_of(officer) / 100.0
				if _h(int(c["id"]), now / 100) < p:
					sim.people.add_mod(a, {"kind": "hr_fixed", "text": "HR sorted it out", "comp": "fairness", "sat": 6.0, "att": 3.0, "days": 2.0})
					if officer != -1:
						_bump_rep(officer, 1.0, 0.0)
					_resolve(c, "fixed", "HR sorted out %s's complaint." % _first(a))
				else:
					c["state"] = "open"
					c["needs_player"] = true
					c["expires"] = now + 3 * _day()
					c["outcome"] = "hr_failed"
		"resolved":
			if now > int(c.get("resolved_tick", now)) + _day():
				sim.state["v5"]["hr"]["complaints"].erase(int(c["id"]))

func _file(c: Dictionary, a: Dictionary, now: int) -> void:
	var cf: Dictionary = cfg()
	a["hr_visit"] = "kiosk" if _h(int(c["id"]), 5) < 0.3 else "interview"
	sim.people.add_mod(a, {"kind": "heard", "text": "Being heard by HR", "comp": "social", "sat": float(cf["heard_sat"]), "att": 1.0, "days": float(cf["heard_days"])})
	var spec_players: bool = bool(c["needs_player"])
	c["state"] = "open" if spec_players else "hr_working"
	c["resolve_at"] = now + int(float(cf["work_days"]) * float(_day()))
	c["expires"] = now + 3 * _day()
	var hl: Array = lines()["heard"]
	sim.log_event("hr_complaint", String(c["text"]), [int(a["id"])], 1, {"complaint": int(c["id"]), "category": String(c["category"]), "place": int(c["office"])})
	sim.social.say(a, String(hl[int(_h(int(c["id"]), 6) * hl.size()) % hl.size()]).replace("{a}", _first(a)), "complaint", -1)

# ---------------------------------------------------------------- daily: complaints, transfers, surveys
func _daily(day: int) -> void:
	var r: Dictionary = _w()
	r["day"] = day
	# The two reputations drift back toward their start values (a share a day).
	for id in r["rep"]:
		var rp: Dictionary = r["rep"][id]
		var back: float = float(cfg()["rep_back"])
		rp["public"] = float(rp["public"]) + (float(cfg()["rep_public_start"]) - float(rp["public"])) * back
		rp["private"] = float(rp["private"]) + (float(cfg()["rep_private_start"]) - float(rp["private"])) * back
	var bases: Array = [-1] if sim.bases.count() == 0 else sim.bases.ids()
	var cf: Dictionary = cfg()
	for base in bases:
		if not active(int(base)):
			continue
		var offs: Array = offices(int(base))
		var open := 0
		for id in r["complaints"]:
			if int(r["complaints"][id]["base"]) == int(base) and String(r["complaints"][id]["state"]) != "resolved":
				open += 1
		var ids: Array = sim.state["agents"].keys()
		ids.sort()
		for aid in ids:
			var a: Dictionary = sim.state["agents"][aid]
			if not _adult(a) or is_officer(a) or (sim.bases.count() > 0 and _home(a) != int(base)):
				continue
			var rec: Dictionary = sim.people.rec_of(int(aid))
			if rec.is_empty():
				continue
			var sat: float = float(rec.get("sat", 60.0))
			var last: Dictionary = _last(int(aid))
			var has_c := false
			for id in r["complaints"]:
				if int(r["complaints"][id]["agent"]) == int(aid) and String(r["complaints"][id]["state"]) != "resolved":
					has_c = true
			var cat: String = _category_of(a, rec)
			var grievance: bool = cat == "punishment" or cat == "feud"
			if not has_c and open < int(cf["max_open_per_base"]) and (sat < float(cf["complaint_sat"]) or grievance) and day - int(last["complaint"]) >= int(cf["complaint_gap_days"]) and _h(int(aid), day * 7 + 1) < float(cf["complaint_chance_day"]):
				last["complaint"] = day
				if _new_complaint(a, cat, rec, int(base), int(offs[int(_h(int(aid), 3) * offs.size()) % offs.size()])):
					open += 1
			var has_t := false
			for id in r["transfers"]:
				if int(r["transfers"][id]["agent"]) == int(aid):
					has_t = true
			if not has_t and sat < float(cf["transfer_sat"]) and day - int(last["transfer"]) >= int(cf["transfer_gap_days"]) and _h(int(aid), day * 7 + 2) < float(cf["transfer_chance_day"]):
				last["transfer"] = day
				_new_transfer(a, cat, int(base))
		var sd: Dictionary = r["survey_day"]
		if not sd.has(int(base)) or day - int(sd[int(base)]) >= int(cf["survey_days"]):
			sd[int(base)] = day
			_survey(int(base), day)

func _category_of(a: Dictionary, rec: Dictionary) -> String:
	var now: int = int(sim.state["tick"])
	for m in rec.get("mods", []):
		if int(m["until"]) > now and ["warning", "extra_shift", "ration_cut", "confine", "demote", "punishment"].has(String(m["kind"])):
			return "punishment"
	var foe: int = _foe_of(a)
	if foe != -1:
		return "feud"
	match String(rec.get("low", "")):
		"housing":
			return "home"
		"fairness", "freedom":
			return "punishment"
		"work", "needs":
			return "overwork"
		"social":
			return "feud" if foe != -1 else "condition"
		"comfort", "safety", "food":
			return "condition"
	return "pay"

func _foe_of(a: Dictionary) -> int:
	for pr in sim.relations.relationships_of(int(a["id"]), 12):
		if String(pr["status"]) == "enemy" or String(pr["status"]) == "rival":
			return int(pr["other"])
	return -1

func _new_complaint(a: Dictionary, cat: String, rec: Dictionary, base: int, office: int) -> bool:
	var r: Dictionary = _w()
	var id: int = sim.relations.next_request_id()
	var target := {"kind": "condition", "id": -1, "name": "the conditions"}
	if cat == "feud":
		var foe: int = _foe_of(a)
		if foe == -1:
			cat = "condition"
		else:
			target = {"kind": "person", "id": foe, "name": _first(sim.state["agents"].get(foe, {}))}
	elif cat == "home":
		target = {"kind": "condition", "id": int(a.get("bed", -1)), "name": "the home"}
	elif cat == "overwork" or cat == "pay":
		target = {"kind": "department", "id": -1, "name": sim.people.department(a)}
	var needs: bool = cat == "feud" or cat == "punishment" or _h(int(a["id"]), int(sim.state["tick"]) / 100) < 0.35
	var now: int = int(sim.state["tick"])
	var c := {"id": id, "agent": int(a["id"]), "category": cat, "target": target, "tick": now, "state": "walking", "text": "", "office": office, "base": base,
		"deadline": now + 90 * _hz(), "resolve_at": -1, "outcome": "", "needs_player": needs, "expires": now + 3 * _day()}
	c["text"] = _complaint_text(c)
	r["complaints"][id] = c
	a["hr_visit"] = "queue"
	a["hr_office"] = office
	if a["where"] == "in" and String(a.get("plan_kind", "")) != "safety":
		sim.agents.abort_plan(a, "hr_visit")
	var cl: Array = lines()["complaint_lines"]
	sim.social.say(a, String(cl[int(_h(id, 2) * cl.size()) % cl.size()]), "complaint", -1)
	return true

func _new_transfer(a: Dictionary, cat: String, base: int) -> void:
	var r: Dictionary = _w()
	var id: int = sim.relations.next_request_id()
	var key: String = cat if lines()["reasons"].has(cat) else "unhappy"
	var reason: String = String(lines()["reasons"][key])
	var now: int = int(sim.state["tick"])
	var t := {"id": id, "agent": int(a["id"]), "reason": key, "text": String(lines()["transfer"]["text"]).replace("{a}", _first(a)).replace("{reason}", reason), "tick": now,
		"expires": now + int(float(cfg()["transfer_offer_days"]) * float(_day())), "base": base, "department": sim.people.department(a), "state": "open", "ship": -1}
	r["transfers"][id] = t
	sim.log_event("hr_transfer_request", String(t["text"]), [int(a["id"])], 1, {"transfer": id})

## An approved transfer: the person boards the next ship that has landed and has seats (a colonist of the
## ship's passengers; at most 2 a ship).
func _depart(t: Dictionary) -> void:
	var a: Dictionary = sim.state["agents"].get(int(t["agent"]), {})
	if a.is_empty() or a["state"] != "alive":
		sim.state["v5"]["hr"]["transfers"].erase(int(t["id"]))
		return
	var kinds: Dictionary = sim.traffic.kinds()
	for arr in sim.traffic.ts()["ships"]:
		if String(arr["phase"]) != "landed":
			continue
		var k: Dictionary = kinds.get(String(arr["kind"]), {})
		if int((k.get("visitors", [0, 0]) as Array)[1]) <= 0:
			continue
		var taken := 0
		for vid in arr["visitors"]:
			var v: Dictionary = sim.state["agents"].get(int(vid), {})
			if not v.is_empty() and bool(v.get("transfer", false)):
				taken += 1
		if taken >= 2:
			continue
		sim.traffic.make_passenger(a, int(arr["id"]))
		a["transfer"] = true
		(arr["visitors"] as Array).append(int(a["id"]))
		sim.agents.abort_plan(a, "transfer")
		t["state"] = "left"
		t["ship"] = int(arr["id"])
		t["left_tick"] = int(sim.state["tick"])
		sim.people.invalidate(int(a["id"]))
		sim.people.ranks_dirty()
		sim.log_event("defected", "%s leaves the colony on a transfer." % String(a["name"]), [int(a["id"])], 1)
		_after_leaving(a)
		return

## The people who liked the leaver are sad; the ones who fought with them are relieved.
func _after_leaving(a: Dictionary) -> void:
	var cf: Dictionary = cfg()
	for pr in sim.relations.relationships_of(int(a["id"]), 12):
		var o: Dictionary = sim.state["agents"].get(int(pr["other"]), {})
		if o.is_empty() or o["state"] != "alive":
			continue
		var st: String = String(pr["status"])
		if st == "friend" or st == "best_friend" or st == "partners" or st == "married" or st == "dating":
			sim.people.add_mod(o, {"kind": "friend_left", "text": "A friend left the colony", "comp": "social", "sat": float(cf["approve_sad_sat"]), "att": -1.0, "days": float(cf["approve_days"])})
		elif st == "enemy" or st == "rival":
			sim.people.add_mod(o, {"kind": "foe_left", "text": "A rival left the colony", "comp": "social", "sat": float(cf["approve_relief_sat"]), "att": 1.0, "days": float(cf["approve_days"])})

## A feedback round: per department the people, mean satisfaction and the change since the last round, the
## three most common complaint categories (stored and still open complaints plus the lowest components), and
## the morale trend.
func _survey(base: int, day: int) -> void:
	var r: Dictionary = _w()
	var dep_sat := {}
	var dep_n := {}
	var low := {}
	var total := 0.0
	var n := 0
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if not _adult(a) or (sim.bases.count() > 0 and base != -1 and _home(a) != base):
			continue
		var rec: Dictionary = sim.people.rec_of(int(aid))
		if rec.is_empty():
			continue
		var d: String = sim.people.department(a)
		if d == "":
			d = "general"
		dep_sat[d] = float(dep_sat.get(d, 0.0)) + float(rec["sat"])
		dep_n[d] = int(dep_n.get(d, 0)) + 1
		total += float(rec["sat"])
		n += 1
		var cat: String = _category_of(a, rec)
		if float(rec["sat"]) < 60.0:
			low[cat] = int(low.get(cat, 0)) + 1
	for id in r["complaints"]:
		var c: Dictionary = r["complaints"][id]
		if int(c["base"]) == base:
			low[String(c["category"])] = int(low.get(String(c["category"]), 0)) + 2
	var prev: Dictionary = r["surveys"].get(base, {})
	var prev_d := {}
	for row in prev.get("depts", []):
		prev_d[String(row["dept"])] = float(row["sat"])
	var depts: Array = []
	var dk: Array = dep_sat.keys()
	dk.sort()
	for d in dk:
		var m: float = snappedf(float(dep_sat[d]) / float(dep_n[d]), 0.1)
		depts.append({"dept": d, "n": int(dep_n[d]), "sat": m, "trend": snappedf(m - float(prev_d.get(d, m)), 0.1)})
	var cats: Array = low.keys()
	cats.sort_custom(func(x, y): return int(low[x]) > int(low[y]) if int(low[x]) != int(low[y]) else String(x) < String(y))
	var top3: Array = []
	for k in mini(3, cats.size()):
		top3.append({"category": cats[k], "count": int(low[cats[k]])})
	var mean: float = snappedf(total / float(maxi(1, n)), 0.1)
	var change: float = snappedf(mean - float(prev.get("mean", mean)), 0.1)
	var st: Dictionary = lines()["survey_text"]
	r["surveys"][base] = {"tick": int(sim.state["tick"]), "day": day, "base": base, "depts": depts, "top3": top3, "mean": mean, "morale_trend": change}
	sim.log_event("hr_survey", "%s: mean satisfaction %d. %s" % [String(st["title"]), int(mean), String(st["morale_up"] if change > 1.0 else (st["morale_down"] if change < -1.0 else st["morale_flat"]))], [], 0, {"base": base})
