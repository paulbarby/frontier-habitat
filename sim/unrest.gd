extends RefCounted
## Unrest and the player's responses (docs/V5_DESIGN.md section 6.4). Numbers: content/society.json
## "unrest" and "responses".
##
## Stored per base in state.v5.unrest[base] = {value, target, stage, demand, dep (the department on
## strike), punish [[tick, unfair]], resp {response: tick}, lock_until}. Every update_every_s the
## value moves toward a target made from the stored satisfaction and attitude of the base's
## colonists (people.gd), the recent punishments, rations and deaths, less the commander's
## leadership and the security officers. A badly run colony (hungry, tired, punished) reaches
## protest, strike and riot; a well run one stays calm.

var sim
var _info_cache := {}         # base -> [tick, record] (the interface asks every frame)

func _init(s) -> void:
	sim = s

func reset() -> void:
	_info_cache = {}

func cfg() -> Dictionary:
	return sim.content["society"]["unrest"]

func _day_ticks() -> int:
	return int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))

func _bases() -> Array:
	if sim.bases.count() == 0:
		return [-1]
	var out: Array = sim.bases.ids().duplicate()
	out.sort()
	return out

func _home(a: Dictionary) -> int:
	return sim.bases.home_of(a) if sim.bases.count() > 0 else -1

## The stored record of a base (read only; {} before the first update).
func rec_of(base_id: int) -> Dictionary:
	return sim.state.get("v5", {}).get("unrest", {}).get(base_id, {})

func _rec_w(base_id: int) -> Dictionary:
	var u: Dictionary = sim.people.v5w()["unrest"]
	if not u.has(base_id):
		u[base_id] = {"value": 0.0, "target": 0.0, "stage": "calm", "demand": "", "dep": "", "punish": [], "resp": {}, "lock_until": -1}
	return u[base_id]

# ---------------------------------------------------------------- the update
## Every tick (sim.step): each base on its own tick of the update period.
func tick() -> void:
	var hz: int = int(sim.bal["tick_hz"])
	var every: int = int(sim.content["society"]["update_every_s"]) * hz
	var now: int = int(sim.state["tick"])
	for b in _bases():
		if posmod(now + int(b) * 7 + 3, every) == 0:
			_update(int(b), float(every) / float(hz))

func _update(base_id: int, dt_s: float) -> void:
	var c: Dictionary = cfg()
	var r: Dictionary = _rec_w(base_id)
	var now: int = int(sim.state["tick"])
	var day: int = _day_ticks()
	sim.people._refresh_ranks(true)
	var ppl: Dictionary = sim.people.v5r().get("people", {})
	var n := 0
	var sat := 0.0
	var att := 0.0
	var low := 0
	var rations := 0
	var lows := {}
	var dep_sat := {}
	var dep_n := {}
	var officers := 0
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
			continue
		if base_id != -1 and _home(a) != base_id:
			continue
		var pr: Dictionary = ppl.get(int(aid), {})
		if pr.is_empty():
			continue
		n += 1
		sat += float(pr["sat"])
		att += float(pr["att"])
		if float(pr["sat"]) < float(c["low_sat"]):
			low += 1
		if sim.people.has_mod(a, "ration_cut"):
			rations += 1
		var lo: String = String(pr.get("low", ""))
		if lo != "":
			lows[lo] = int(lows.get(lo, 0)) + 1
		var dep: String = sim.people.department(a)
		if dep != "":
			dep_sat[dep] = float(dep_sat.get(dep, 0.0)) + float(pr["sat"])
			dep_n[dep] = int(dep_n.get(dep, 0)) + 1
		if String(a["role"]) == "security":
			officers += 1
	if n == 0:
		return
	sat /= n
	att /= n
	# Punishments and deaths of the last days.
	var keep: Array = []
	var pun := 0.0
	for p in r["punish"]:
		if int(p[0]) + int(float(c["punish_days"]) * day) > now:
			keep.append(p)
			pun += float(c["punish_unfair"]) if bool(p[1]) else float(c["punish"])
	r["punish"] = keep
	var deaths := 0
	var lg: Array = sim.state["log"]
	for i in range(lg.size() - 1, -1, -1):
		var e: Dictionary = lg[i]
		if int(e["tick"]) + int(float(c["death_days"]) * day) <= now:
			break
		if String(e["code"]) == "death":
			deaths += 1
	var lead := 0.0
	var cmd_id := -1
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(sim.people.rank(a)["rank"]) == "commander" and (base_id == -1 or int(sim.people.rank(a)["base"]) == base_id):
			cmd_id = int(aid)
			lead = float(c["leadership"]) * float(sim.people.skills(a)["leadership"]) / 100.0
			break
	var sec: float = minf(float(c["security_max"]), float(c["security_per_officer"]) * officers)
	var target: float = (float(c["sat_ref"]) - sat) * float(c["per_sat_point"]) + maxf(0.0, -att) * float(c["per_att_point"])
	target += float(low) / float(n) * float(c["low_share"]) + pun + float(rations) * float(c["ration"]) + float(deaths) * float(c["death"])
	target -= lead + sec
	target = clampf(target, 0.0, 100.0)
	r["target"] = snappedf(target, 0.1)
	r["sat"] = snappedf(sat, 0.1)
	r["att"] = snappedf(att, 0.1)
	r["commander"] = cmd_id
	r["causes"] = _causes(c, sat, att, low, n, pun, rations, deaths, lead, sec)
	var v: float = float(r["value"])
	var step_up: float = float(c["rise_per_day"]) * dt_s / float(sim.bal["day_length"])
	var step_down: float = float(c["fall_per_day"]) * dt_s / float(sim.bal["day_length"])
	if target > v:
		v = minf(target, v + step_up)
	else:
		v = maxf(target, v - step_down)
	r["value"] = snappedf(v, 0.01)
	# The demand: the most common lowest part of satisfaction.
	var best := ""
	var best_n := -1
	var lk: Array = lows.keys()
	lk.sort()
	for k in lk:
		if int(lows[k]) > best_n:
			best_n = int(lows[k])
			best = k
	var dmap := {"needs": "rest", "food": "food", "housing": "housing", "comfort": "leisure", "social": "leisure", "work": "rest", "fairness": "fair", "safety": "safety", "freedom": "fair"}
	if rations > 0 or pun > 0.0:
		best = "fairness" if pun >= float(rations) * float(c["ration"]) else "food"
	var dkey: String = String(dmap.get(best, "rest"))
	# The department that strikes: the one with the lowest mean satisfaction.
	var worst := ""
	var worst_v := 1e9
	var dk: Array = dep_sat.keys()
	dk.sort()
	for d in dk:
		var m: float = float(dep_sat[d]) / float(dep_n[d])
		if m < worst_v:
			worst_v = m
			worst = d
	var old: String = String(r["stage"])
	var stage: String = _stage(v, old)
	r["stage"] = stage
	r["demand"] = String(c["demands"].get(dkey, "")) if _rank_of(stage) >= _rank_of("protest") else ""
	r["demand_key"] = dkey
	r["dep"] = worst if stage == "strike" else ""
	if stage != old:
		_stage_changed(base_id, old, stage, r)
	_info_cache.erase(base_id)
	_info_cache.erase(-1)

func _causes(c: Dictionary, sat: float, att: float, low: int, n: int, pun: float, rations: int, deaths: int, lead: float, sec: float) -> Array:
	var out: Array = []
	if sat < float(c["sat_ref"]):
		out.append({"text": "Low satisfaction (%d)" % int(sat), "delta": snappedf((float(c["sat_ref"]) - sat) * float(c["per_sat_point"]), 0.1)})
	if att < 0.0:
		out.append({"text": "Bad attitudes", "delta": snappedf(-att * float(c["per_att_point"]), 0.1)})
	if low > 0:
		out.append({"text": "%d of %d very unhappy" % [low, n], "delta": snappedf(float(low) / float(n) * float(c["low_share"]), 0.1)})
	if pun > 0.0:
		out.append({"text": "Recent punishments", "delta": snappedf(pun, 0.1)})
	if rations > 0:
		out.append({"text": "Rations cut (%d)" % rations, "delta": snappedf(float(rations) * float(c["ration"]), 0.1)})
	if deaths > 0:
		out.append({"text": "Deaths today (%d)" % deaths, "delta": snappedf(float(deaths) * float(c["death"]), 0.1)})
	if lead > 0.0:
		out.append({"text": "Commander's leadership", "delta": snappedf(-lead, 0.1)})
	if sec > 0.0:
		out.append({"text": "Security officers", "delta": snappedf(-sec, 0.1)})
	return out

func _rank_of(stage: String) -> int:
	var i := 0
	for s in cfg()["stages"]:
		if String(s[0]) == stage:
			return i
		i += 1
	return 0

## The stage for a value; going down needs the value "hysteresis" points under the threshold.
func _stage(v: float, old: String) -> String:
	var st: Array = cfg()["stages"]
	var h: float = float(cfg()["hysteresis"])
	var up := "calm"
	for s in st:
		if v >= float(s[1]):
			up = s[0]
	if _rank_of(up) >= _rank_of(old):
		return up
	# Lower: keep the old stage while the value is within the hysteresis band of its threshold.
	for s in st:
		if String(s[0]) == old and v >= float(s[1]) - h:
			return old
	return up

func _stage_changed(base_id: int, old: String, stage: String, r: Dictionary) -> void:
	var name: String = sim.bases.name_of(base_id) if base_id != -1 and sim.bases.count() > 0 else "The colony"
	var up: bool = _rank_of(stage) > _rank_of(old)
	var texts := {"calm": "%s is calm again.", "grumbling": "People in %s are grumbling.", "slowdown": "Work in %s slows down: people are unhappy.",
		"protest": "A protest starts in %s.", "strike": "A strike starts in %s.", "riot": "A riot starts in %s!"}
	var text: String = String(texts.get(stage, "%s: " + stage)) % name
	if not up and stage != "calm":
		text = "Unrest in %s falls to %s." % [name, stage]
	if stage == "riot" and up:
		# A new riot: its damage and injuries are counted from now.
		r["damaged"] = []
		r["injured"] = 0
		r["looted"] = 0
	var sev: int = 1 if _rank_of(stage) < _rank_of("protest") else (2 if stage != "riot" else 3)
	sim.log_event("unrest", text, [base_id] if base_id != -1 else [], sev, {"stage": stage, "demand": String(r.get("demand", ""))})
	# The people of the base get their work flags again (a strike starts or ends).
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and (base_id == -1 or _home(a) == base_id) and sim.people.rec_of(int(aid)).size() > 0:
			sim.people._apply_flags(a, sim.people.rec_w(a))

# ---------------------------------------------------------------- effects read by people.gd
func _stage_of_agent(a: Dictionary) -> String:
	var r: Dictionary = rec_of(_home(a))
	return String(r.get("stage", "calm"))

## Work speed factor from unrest: slowdown and above.
func work_mult(a: Dictionary) -> float:
	return float(cfg()["slowdown_mult"]) if _rank_of(_stage_of_agent(a)) >= _rank_of("slowdown") else 1.0

## True while a person does no work: their department strikes, or the base riots.
func on_strike(a: Dictionary) -> bool:
	var r: Dictionary = rec_of(_home(a))
	var st: String = String(r.get("stage", "calm"))
	if st == "riot":
		return true
	return st == "strike" and String(r.get("dep", "")) != "" and sim.people.department(a) == String(r["dep"])

## A punishment seen by the base (discipline.gd).
func add_punishment(base_id: int, unfair: bool) -> void:
	_rec_w(base_id)["punish"].append([int(sim.state["tick"]), unfair])

# ---------------------------------------------------------------- lock-down and protests
## True while a lock-down holds the base: the doors between its rooms are closed (RENDER draws the
## corridor doors of the base closed), people stay in the room they are in (only critical needs
## move them), and riots start fewer fights and loot less.
func locked(base_id: int) -> bool:
	return int(rec_of(base_id).get("lock_until", -1)) > int(sim.state["tick"])

## {locked, until (tick), seconds_left} for the interface.
func lock_info(base_id: int) -> Dictionary:
	var u: int = int(rec_of(base_id).get("lock_until", -1))
	var now: int = int(sim.state["tick"])
	return {"locked": u > now, "until": u, "seconds_left": maxf(0.0, float(u - now) / float(sim.bal["tick_hz"]))}

func locked_in(a: Dictionary) -> bool:
	return a["where"] == "in" and locked(_home(a))

## Where a protest gathers: the dome (its plaza) or the largest leisure room of the base (-1: none).
func protest_place(base_id: int) -> int:
	var best := -1
	var best_v := -1
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] != "active" or bool(b["demolish"]) or not sim.topo.atmo_comp.has(int(id)):
			continue
		if base_id != -1 and sim.bases.count() > 1 and sim.bases.base_of(int(id)) != base_id:
			continue
		var v: int = int(sim.bd(b).get("recreation", 0)) + (1000 if String(b["def"]) == "super_dome" else 0)
		if v > best_v and (v > 0 or bool(sim.bdef(String(b["def"])).get("dining", false))):
			best_v = v
			best = int(id)
	return best

## During a protest or a strike the unhappiest people gather and shout the demand (people.duty_think).
func protest_think(a: Dictionary) -> bool:
	var base: int = _home(a)
	var r: Dictionary = rec_of(base)
	if not ["protest", "strike"].has(String(r.get("stage", "calm"))):
		return false
	if String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
		return false
	if float(sim.people.rec_of(int(a["id"])).get("sat", 100.0)) >= float(cfg()["low_sat"]):
		return false
	var pc: Dictionary = sim.content["society"]["protest"]
	var n := 0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and String(x.get("plan_kind", "")) == "protest" and _home(x) == base:
			n += 1
	if n >= int(pc["max_people"]):
		return false
	var place: int = protest_place(base)
	if place == -1:
		return false
	var demand: String = String(r.get("demand", ""))
	if sim.agents._start_personal(a, "protest", place, [{"op": "protest", "t": float(pc["protest_s"])}], "Protesting: %s" % demand, -1):
		if String(sim.state["buildings"][place]["def"]) == "super_dome":
			a["venue"] = "plaza"
		sim.social.say(a, demand, "protest", -1)
		return true
	return false

## What a response would do now, for the banner: {unrest (delta), cost (text), ready (bool)}.
func response_effect(base_id: int, response: String) -> Dictionary:
	var rc: Dictionary = sim.content["society"]["responses"].get(response, {})
	if rc.is_empty():
		return {}
	var d: float = float(rc["unrest"])
	var cost := ""
	match response:
		"meet_demand":
			cost = "Ends the cause of the demand: %s" % String(rec_of(base_id).get("demand", "nothing asked yet"))
		"leisure_day":
			cost = "Nobody works for a short time."
		"party":
			var need: int = _party_need(base_id)
			var have: int = sim.leisure.count_stock(base_id, sim.content["society"]["party"]["items"])
			cost = "Uses %d drinks, snacks or rations (%d in stock)." % [need, have]
		"amnesty":
			cost = "All prisoners go free. Security morale falls."
		"replace_captain":
			cost = "The captain of the striking department loses the post."
		"arrest_ringleaders":
			cost = "Two people are jailed. Unfair arrests add %d unrest." % int(rc.get("unfair_unrest", 0))
		"lock_down":
			cost = "Doors close for %d game hours. Unrest rises." % int(rc.get("lock_hours", 2))
	return {"unrest": d, "cost": cost, "ready": bool(_ready(rec_of(base_id)).get(response, true))}

func _party_need(base_id: int) -> int:
	var n := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and (base_id == -1 or _home(a) == base_id):
			n += 1
	return int(ceil(float(n) / float(sim.content["society"]["party"]["per_people"])))

# ---------------------------------------------------------------- query
## {value 0..100, target, stage, causes [{text, delta}], demand ("" or text), department (on strike),
##  responses {response: ready (bool)}} for one base (-1: the whole colony: the base with the most).
func info(base_id: int = -1) -> Dictionary:
	var tick: int = int(sim.state["tick"])
	var hit = _info_cache.get(base_id)
	if hit != null and int(hit[0]) == tick:
		return hit[1]
	var r: Dictionary = {}
	if base_id == -1:
		var best := -1.0
		for b in _bases():
			var x: Dictionary = rec_of(int(b))
			if not x.is_empty() and float(x["value"]) > best:
				best = float(x["value"])
				r = x
	else:
		r = rec_of(base_id)
	var out: Dictionary
	if r.is_empty():
		out = {"value": 0.0, "target": 0.0, "stage": "calm", "causes": [], "demand": "", "department": "", "responses": _ready({}), "damage": 0, "injured": 0, "looted": 0, "locked": false}
	else:
		out = {"value": snappedf(float(r["value"]), 0.1), "target": float(r.get("target", 0.0)), "stage": String(r["stage"]), "causes": r.get("causes", []),
			"demand": String(r.get("demand", "")), "department": String(r.get("dep", "")), "responses": _ready(r),
			"damage": (r.get("damaged", []) as Array).size(), "injured": int(r.get("injured", 0)), "looted": int(r.get("looted", 0)),
			"locked": int(r.get("lock_until", -1)) > tick}
	_info_cache[base_id] = [tick, out]
	return out

func _ready(r: Dictionary) -> Dictionary:
	var out := {}
	var now: int = int(sim.state["tick"])
	var day: int = _day_ticks()
	for k in sim.content["society"]["responses"]:
		var used: int = int(r.get("resp", {}).get(k, -1000000000))
		out[k] = used + int(float(sim.content["society"]["responses"][k]["cooldown_days"]) * day) <= now
	return out

# ---------------------------------------------------------------- the player's responses
## Command "unrest_response" {base, response}: meet_demand, leisure_day, party, amnesty,
## replace_captain, arrest_ringleaders, lock_down.
func cmd_unrest_response(p: Dictionary) -> Dictionary:
	var resp: String = String(p.get("response", ""))
	var rc: Dictionary = sim.content["society"]["responses"]
	if not rc.has(resp):
		return {"ok": false, "code": "invalid", "text": "Unknown response."}
	var base_id: int = int(p.get("base", -1))
	if base_id == -1:
		var worst := -1.0
		for b in _bases():
			var x: Dictionary = rec_of(int(b))
			if not x.is_empty() and float(x["value"]) > worst:
				worst = float(x["value"])
				base_id = int(b)
	if base_id != -1 and sim.bases.count() > 0 and not sim.bases.ids().has(base_id):
		return {"ok": false, "code": "invalid", "text": "No such base."}
	var r: Dictionary = _rec_w(base_id)
	sim.people._refresh_ranks(true)
	if not bool(_ready(r)[resp]):
		return {"ok": false, "code": "cooldown", "text": "This response was used a short time ago."}
	var cfgr: Dictionary = rc[resp]
	var delta: float = float(cfgr["unrest"])
	# A party uses drinks, snacks or rations: refused without enough in stock.
	if resp == "party":
		var need: int = _party_need(base_id)
		var items: Array = sim.content["society"]["party"]["items"]
		var have: int = sim.leisure.count_stock(base_id, items)
		if have < need:
			return {"ok": false, "code": "no_stock", "text": "A party needs %d drinks, snacks or rations; the base has %d." % [need, have]}
		sim.leisure.take_stock(base_id, items, need, "party")
	var people: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and (base_id == -1 or _home(a) == base_id):
			people.append(a)
	people.sort_custom(func(x, y): return int(x["id"]) < int(y["id"]))
	var now: int = int(sim.state["tick"])
	match resp:
		"meet_demand":
			var key: String = String(r.get("demand_key", ""))
			for a in people:
				match key:
					"food":
						sim.people.end_mods(a, ["ration_cut"])
					"fair":
						sim.people.end_mods(a, ["confine", "jail", "ration_cut"])
					"rest":
						sim.people.end_mods(a, ["extra_shift"])
						a["fatigue"] = minf(float(a["fatigue"]), 30.0)
					"leisure":
						a["last_rec"] = now
			r["punish"] = []
		"leisure_day", "party":
			for a in people:
				a["last_rec"] = now
				sim.people.add_mod(a, {"kind": resp, "text": String(cfgr["text"]), "comp": "comfort", "sat": 10.0, "att": 3.0, "days": 1.0})
		"amnesty":
			for a in people:
				sim.people.end_mods(a, ["jail", "confine"])
				# Security morale falls: their arrests were for nothing.
				if String(a["role"]) == "security":
					sim.people.add_mod(a, {"kind": "amnesty", "text": "Prisoners let go", "comp": "work", "sat": -8.0, "att": -6.0, "days": 2.0})
		"replace_captain":
			var dep: String = String(r.get("dep", ""))
			var appt: Dictionary = sim.people.v5w()["appoint"]
			var key2: String = "%d:%s:captain" % [base_id, dep]
			for a in people:
				var rk: Dictionary = sim.people.rank(a)
				if String(rk["rank"]) == "captain" and (dep == "" or String(rk["department"]) == dep):
					appt.erase("%d:%s:captain" % [base_id, String(rk["department"])])
					sim.people.add_mod(a, {"kind": "demote", "text": "Replaced as captain", "comp": "fairness", "sat": -10.0, "att": -8.0, "days": 3.0})
					sim.people.set_demoted(a, now + 3 * _day_ticks())
					sim.people.note(a, "Replaced as captain after unrest.")
					break
			appt.erase(key2)
			sim.people._rank_sig = -1
		"arrest_ringleaders":
			# The two with the worst attitude; fair only when their attitude is bad.
			var ranked: Array = people.duplicate()
			ranked.sort_custom(func(x, y):
				var ax: float = float(sim.people.rec_of(int(x["id"])).get("att", 0.0))
				var ay: float = float(sim.people.rec_of(int(y["id"])).get("att", 0.0))
				return ax < ay if ax != ay else int(x["id"]) < int(y["id"]))
			var unfair := false
			for a in ranked.slice(0, 2):
				if float(sim.people.rec_of(int(a["id"])).get("att", 0.0)) > float(sim.content["society"]["unfair_attitude_from"]):
					unfair = true
				# Officers of the base take them to the cells (security.gd).
				var off: Dictionary = {}
				for oid in sim.security.officers(base_id):
					var o: Dictionary = sim.state["agents"][oid]
					if not o.has("v5_hold") and not o.has("jailed") and o["where"] == "in":
						off = o
						break
				sim.security.arrest(a, off, 1.0)
			if unfair:
				delta += float(cfgr["unfair_unrest"])
		"lock_down":
			r["lock_until"] = now + int(float(cfgr["lock_hours"]) / 24.0 * float(_day_ticks()))
	r["value"] = clampf(float(r["value"]) + delta, 0.0, 100.0)
	r["resp"][resp] = now
	r["stage"] = _stage(float(r["value"]), String(r["stage"]))
	_info_cache.clear()
	var name: String = sim.bases.name_of(base_id) if base_id != -1 and sim.bases.count() > 0 else "the colony"
	sim.log_event("unrest_response", "%s (%s)." % [String(cfgr["text"]).trim_suffix("."), name], [base_id] if base_id != -1 else [], 1, {"response": resp})
	return {"ok": true, "code": "ok", "text": String(cfgr["text"]), "unrest": snappedf(float(r["value"]), 0.1)}
