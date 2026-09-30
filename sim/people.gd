extends RefCounted
## People (docs/V5_DESIGN.md sections 1, 2, 5, 6): identity, looks, traits, skills, rank,
## outfit, satisfaction, attitude and home of every colonist, visitor and child.
## Numbers and lists: content/people.json.
##
## MILESTONE 1 (API stubs): every value is derived from the seed, the person's id and name,
## and the live state (role, activity, morale, beds); nothing is stored, so saves and digests
## do not change. Later milestones store what changes over time (skills that grow, ranks the
## player appoints, partners, homes, attitude) in state.people and keep these calls.

const Rng = preload("res://sim/rng.gd")

const SAT_W := {"needs": 3.0, "food": 1.5, "housing": 1.0, "comfort": 1.0, "social": 1.0, "work": 1.0, "fairness": 1.0, "safety": 1.0, "freedom": 0.5}
const SAT_BAD := {"needs": "Hungry, thirsty or tired", "food": "Poor diet", "housing": "Housing below what they expect", "comfort": "No leisure lately",
	"social": "Lonely", "work": "Overworked", "fairness": "Feels treated unfairly", "safety": "Feels unsafe", "freedom": "No freedom"}
const SAT_GOOD := {"needs": "Well rested and fed", "food": "Good food", "housing": "Likes their home", "comfort": "Enough leisure",
	"social": "Good friends", "work": "Likes the work", "fairness": "Feels treated fairly", "safety": "Feels safe", "freedom": "Free to come and go"}

var sim
var _id_cache := {}          # agent id -> identity (derived; the same every call)
var _rank_tick := -1
var _skill_cache := {}       # agent id -> [day, role, skills] (skills change once a day in the stub)
var _ranks := {}             # agent id -> rank record
var _rank_sig := -1          # roster signature of _ranks (ids, roles, beds, the day, appointments)
var _sig_tick := -1
var _role_hash := {}
var _captains := {}          # "base:department" -> agent id of the captain
var _dep_of := {}            # role -> department (content, fixed)
var _sat_cache := {}         # agent id -> [phase key, satisfaction record]
var _att_cache := {}         # agent id -> [phase key, attitude record]
var _list_tick := -1
var _row_cache := {}         # agent id -> [phase key, list row]
var _budget_tick := -1
var _budget := 0             # refreshes left on this tick for the calls that scan everybody
var _list: Array = []

## Cost rule (V5 section 13 budget): every call here is cheap enough for the frame. Values that
## change slowly are cached: identity for ever, skills per day, ranks per roster change (checked
## once a game minute), satisfaction and attitude per person for one game second. The second of
## each person starts at its own tick ((tick + id) / tick_hz), so a scan of all people refreshes
## about a tenth of them on each tick, not all of them on one tick.

func _init(s) -> void:
	sim = s

## Clears the derived caches (a new state was loaded).
func reset() -> void:
	_id_cache = {}
	_skill_cache = {}
	_ranks = {}
	_rank_tick = -1
	_rank_sig = -1
	_captains = {}
	_sat_cache = {}
	_att_cache = {}
	_list_tick = -1
	_list = []
	_row_cache = {}
	_budget_tick = -1

## The key of a person's cached game second: it changes on a different tick for each person.
func _phase(id: int) -> int:
	return (int(sim.state["tick"]) + id) / int(sim.bal["tick_hz"])

## Calls that scan everybody (the crew list, unrest, the Rag poll, talk topics) refresh at most
## a tenth of the people (and at least 8) on one tick; the others keep a value a few seconds old.
func _take_budget() -> bool:
	var tick: int = int(sim.state["tick"])
	if tick != _budget_tick:
		_budget_tick = tick
		_budget = maxi(8, sim.state["agents"].size() / int(sim.bal["tick_hz"]) + 1)
	if _budget <= 0:
		return false
	_budget -= 1
	return true

## satisfaction(a) for the scans: the last value when it is not yet this second's and this tick
## has no refresh left.
func satisfaction_soon(a: Dictionary) -> Dictionary:
	var id: int = int(a["id"])
	var hit = _sat_cache.get(id)
	if hit != null and int(hit[0]) != _phase(id) and not _take_budget():
		return hit[1]
	return satisfaction(a)

## attitude(a) for the scans (the same rule).
func attitude_soon(a: Dictionary) -> Dictionary:
	var id: int = int(a["id"])
	var hit = _att_cache.get(id)
	if hit != null and int(hit[0]) != _phase(id) and not _take_budget():
		return hit[1]
	return attitude(a)

## A save from before schema 6 (persistence._v5_to_v6 marks state.v5.migrated): each base gets one
## commander, the colonist who has been there longest (then the lowest id). Done once at the load;
## every other rank is SIM's proposal as in a new game.
func ensure_commanders() -> void:
	var v: Dictionary = sim.state.get("v5", {})
	if not bool(v.get("migrated", false)) or bool(v.get("seniority_done", false)):
		return
	v["seniority_done"] = true
	if not v.has("appoint"):
		v["appoint"] = {}
	var nb: int = sim.bases.count()
	var best := {}
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
			continue
		var b: int = sim.bases.home_of(a) if nb > 0 else -1
		if not best.has(b) or int(a.get("born", 0)) < int(best[b].get("born", 0)):
			best[b] = a
	for b in best:
		var key: String = "%d:commander" % int(b)
		if not v["appoint"].has(key):
			v["appoint"][key] = int(best[b]["id"])
	ranks_dirty()

## Fills the caches after a load, so the first scan in a frame does not pay for everybody.
func prewarm() -> void:
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive":
			attitude(a)
	list()

func cfg() -> Dictionary:
	return sim.content["people"]

func soc() -> Dictionary:
	return sim.content["society"]

# ---------------------------------------------------------------- stored state (schema 6: state.v5)
## Read only: state.v5 or {} (the interface never writes the state).
func v5r() -> Dictionary:
	return sim.state.get("v5", {})

## The simulation's copy, made when first needed: {people {id: record}, appoint, unrest, courses}.
func v5w() -> Dictionary:
	if not sim.state.has("v5"):
		sim.state["v5"] = {"people": {}, "appoint": {}, "unrest": {}, "courses": {}}
	return sim.state["v5"]

## A person's stored record (read only; {} before the first update):
## {att, sat, low (lowest component), mods [{kind, text, comp, sat, att, until, flags...}],
##  hist [{tick, text}], review {grade, tick}, skill_bonus {skill: points}, demoted_until, unit}.
func rec_of(id: int) -> Dictionary:
	return v5r().get("people", {}).get(id, {})

func rec_w(a: Dictionary) -> Dictionary:
	var ppl: Dictionary = v5w()["people"]
	var id: int = int(a["id"])
	if not ppl.has(id):
		ppl[id] = {"att": float(attitude_target(a, float(_satisfaction(a)["value"]))["value"]), "sat": 50.0, "low": "", "mods": [], "hist": []}
	return ppl[id]

## A dated line in a person's history (last 30 kept).
func note(a: Dictionary, text: String) -> void:
	var h: Array = rec_w(a)["hist"]
	h.append({"tick": int(sim.state["tick"]), "text": text})
	while h.size() > 30:
		h.pop_front()

## Adds a timed effect: m = {kind, text, comp, sat, att, days, flags...}.
func add_mod(a: Dictionary, m: Dictionary) -> void:
	var r: Dictionary = rec_w(a)
	var mm: Dictionary = m.duplicate()
	mm["until"] = int(sim.state["tick"]) + int(float(m.get("days", 1.0)) * float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))
	mm.erase("days")
	r["mods"].append(mm)
	_apply_flags(a, r)
	invalidate(int(a["id"]))

## Removes the active effects of these kinds (amnesty, a met demand).
func end_mods(a: Dictionary, kinds: Array) -> void:
	var r: Dictionary = rec_w(a)
	var keep: Array = []
	for m in r["mods"]:
		if not kinds.has(String(m["kind"])):
			keep.append(m)
	r["mods"] = keep
	_apply_flags(a, r)
	invalidate(int(a["id"]))

func has_mod(a: Dictionary, kind: String) -> bool:
	var now: int = int(sim.state["tick"])
	for m in rec_of(int(a["id"])).get("mods", []):
		if String(m["kind"]) == kind and int(m["until"]) > now:
			return true
	return false

## A demotion: no post is proposed for this person until the tick given (the rank check reads it).
func set_demoted(a: Dictionary, until: int) -> void:
	var appt: Dictionary = v5w()["appoint"]
	if not appt.has("demoted"):
		appt["demoted"] = {}
	appt["demoted"][int(a["id"])] = until
	rec_w(a)["demoted_until"] = until
	ranks_dirty()

func clear_demoted(a: Dictionary) -> void:
	var appt: Dictionary = v5w()["appoint"]
	if appt.has("demoted"):
		appt["demoted"].erase(int(a["id"]))
	rec_w(a).erase("demoted_until")
	ranks_dirty()

## Drops the query caches of one person (after an order changed them).
func invalidate(id: int) -> void:
	_sat_cache.erase(id)
	_att_cache.erase(id)
	_row_cache.erase(id)
	_skill_cache.erase(id)
	_list_tick = -1

## The agent ids with id % m == r, ascending (cost: a tick asks for one bucket instead of scanning
## every person). Made again when the set of agents changes (a new id, a removed one, a load).
var _bk_state = null
var _bk_n := -1
var _bk := {}                  # m -> [[ids with id % m == 0], [.. == 1], ...]

func ids_mod(m: int, r: int) -> Array:
	var agents: Dictionary = sim.state["agents"]
	if not is_same(_bk_state, agents) or agents.size() != _bk_n:
		_bk_state = agents
		_bk_n = agents.size()
		_bk = {}
	if not _bk.has(m):
		var lists: Array = []
		for i in m:
			lists.append([])
		var ids: Array = agents.keys()
		ids.sort()
		for aid in ids:
			(lists[int(aid) % m] as Array).append(int(aid))
		_bk[m] = lists
	return _bk[m][posmod(r, m)]

## Every tick (sim.step): the people whose turn it is (every update_every_s, by id) get their
## satisfaction and attitude stored and their work flags set. About 1/100 of the people a tick.
func tick() -> void:
	var hz: int = int(sim.bal["tick_hz"])
	var every: int = int(soc()["update_every_s"]) * hz
	var now: int = int(sim.state["tick"])
	var agents: Dictionary = sim.state["agents"]
	# (now + id) % every == 0  <=>  id % every == -now mod every
	# The ranks are made again once a game minute (stored: see _refresh_ranks).
	if now % (60 * hz) == 0 or not sim.state.get("v5", {}).has("ranks"):
		store_ranks()
	var due: Array = ids_mod(every, -now).duplicate()
	if due.is_empty():
		return
	v5w()
	_refresh_ranks(true)
	due.sort()
	var ppl: Dictionary = sim.state["v5"]["people"]
	for aid in due:
		var a: Dictionary = agents[aid]
		if a["state"] != "alive":
			if ppl.has(int(aid)):
				ppl.erase(int(aid))
			continue
		_update(a)

func _update(a: Dictionary) -> void:
	var r: Dictionary = rec_w(a)
	var now: int = int(sim.state["tick"])
	var keep: Array = []
	for m in r["mods"]:
		if int(m["until"]) > now:
			keep.append(m)
	r["mods"] = keep
	var s: Dictionary = _satisfaction(a, true)
	var lo := ""
	var lov := 1e9
	for k in s["components"]:
		if float(s["components"][k]) < lov:
			lov = float(s["components"][k])
			lo = k
	r["sat"] = float(s["value"])
	r["low"] = lo
	var tg: float = float(attitude_target(a, float(s["value"]), true)["value"])
	r["att"] = snappedf(float(r["att"]) + (tg - float(r["att"])) * float(soc()["attitude"]["rate"]), 0.01)
	_grow(a, r, now)
	_apply_flags(a, r)

## V5 section 5.2: skills grow by doing the work, with diminishing returns (xp_per_s x (1 - skill /
## 100) for the role's main skill, half for its second), and fall a little (xp_decay_per_day) when the
## person has not worked for xp_decay_after_days. Stored as rec.xp {skill: points}, started from the
## days here (the rule before).
func _grow(a: Dictionary, r: Dictionary, now: int) -> void:
	var kind: String = String(a.get("kind", ""))
	if kind == "visitor" or kind == "child":
		return
	var c: Dictionary = cfg()
	var st: Dictionary = c["start_skill"]
	var mine: Array = c["role_skills"].get(String(a.get("role", "")), [])
	if mine.is_empty():
		return
	var dt: int = int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))
	if not r.has("xp"):
		var days: float = float(maxi(0, now / dt - int(a.get("born", 0)) / dt))
		var x0 := {}
		for sk in mine:
			x0[sk] = snappedf(minf(float(st["cap"]), days * float(st["per_day"])), 0.01)
		r["xp"] = x0
		r["worked"] = now
	var xp: Dictionary = r["xp"]
	var secs: float = float(soc()["update_every_s"])
	if String(a.get("plan_kind", "")) == "task" and sim.agents._step_op(a) == "work":
		r["worked"] = now
		var sks: Dictionary = skills(a)
		for i in mini(2, mine.size()):
			var sk: String = mine[i]
			var g: float = float(st["xp_per_s"]) * secs * (1.0 - float(sks.get(sk, 0)) / 100.0) * (1.0 if i == 0 else 0.5)
			xp[sk] = snappedf(minf(float(st["cap"]), float(xp.get(sk, 0.0)) + maxf(0.0, g)), 0.001)
	elif float(now - int(r.get("worked", now))) > float(st["xp_decay_after_days"]) * float(dt):
		for sk in xp.keys():
			xp[sk] = snappedf(maxf(0.0, float(xp[sk]) - float(st["xp_decay_per_day"]) * secs / float(sim.bal["day_length"])), 0.001)

## The flags the rest of the simulation reads on the agent (absent = normal):
## v5_nowork (no work: confined, jailed, in class, on strike), v5_norec (no leisure),
## v5_hunger (hunger rate), v5_work (work speed), jailed.
func _apply_flags(a: Dictionary, r: Dictionary) -> void:
	var now: int = int(sim.state["tick"])
	var nowork := false
	var norec := false
	var jail := false
	var hunger := 1.0
	var work := 1.0
	for m in r["mods"]:
		if int(m["until"]) <= now:
			continue
		nowork = nowork or bool(m.get("no_work", false))
		norec = norec or bool(m.get("no_rec", false))
		jail = jail or bool(m.get("jail", false))
		hunger = maxf(hunger, float(m.get("hunger_mult", 1.0)))
		work *= float(m.get("work_mult", 1.0))
	if float(r.get("att", 0.0)) <= float(soc()["attitude"]["slack_below"]):
		work *= float(soc()["attitude"]["slack_work_mult"])
	if sim.get("unrest") != null:
		work *= sim.unrest.work_mult(a)
		nowork = nowork or sim.unrest.on_strike(a)
	if sim.get("education") != null and sim.education.in_class(a):
		nowork = true
	_flag(a, "v5_nowork", nowork, true)
	_flag(a, "v5_norec", norec, true)
	_flag(a, "jailed", jail, true)
	_flag(a, "v5_hunger", hunger != 1.0, snappedf(hunger, 0.01))
	_flag(a, "v5_work", absf(work - 1.0) > 0.001, snappedf(work, 0.001))

func _flag(a: Dictionary, key: String, on: bool, value) -> void:
	if on:
		a[key] = value
	elif a.has(key):
		a.erase(key)

## What an order would do (the interface asks before the player confirms): {attitude, satisfaction,
## others (text), risk (text), unfair (bool), text, days, traits}. a: the agent or its id; action: a
## discipline action or a review grade. {} for an unknown action.
func predict(a, action: String, params: Dictionary = {}) -> Dictionary:
	var ag: Dictionary = a if typeof(a) == TYPE_DICTIONARY else sim.state["agents"].get(int(a), {})
	if ag.is_empty():
		return {}
	return sim.discipline.predict(ag, action, params)

## The animation a person plays now, for show (RENDER; "" = the ordinary clip of the activity):
## "dance_c" (the dance egg), "fight_idle" | "punch" | "hit_react" (in a fight), "fall_down" (knocked
## down), "handcuffed_walk" (taken to jail), "escort_walk" (an officer taking them), "sleep_cell",
## "protest_fist", "sit_class", "teach", "child_play", and the venue clips: "shop_browse",
## "sit_bench", "drink_bar", "play_arcade", "dance_a", "jog", "swim".
func action(a: Dictionary) -> String:
	if a["state"] != "alive":
		return ""
	var hold: String = String(a.get("v5_hold", ""))
	match hold:
		"fight":
			if float(a["health"]) <= float(soc()["security"]["down_health"]):
				return "fall_down"
			return ["fight_idle", "punch", "hit_react"][((int(sim.state["tick"]) / 12) + int(a["id"])) % 3]
		"cuffed":
			return "handcuffed_walk"
		"escort":
			return "escort_walk"
	if has_mod(a, "dance"):
		return "dance_c"
	var kind: String = String(a.get("plan_kind", ""))
	var op: String = sim.agents._step_op(a)
	if a.has("jailed") and bool(a.get("sleeping", false)):
		return "sleep_cell"
	if a.has("knocked_until") and int(a["knocked_until"]) > int(sim.state["tick"]):
		return "fall_down"
	match op:
		"protest":
			return "protest_fist"
		"class":
			return "sit_class"
		"teach":
			return "teach"
	if op == "rec" or (kind == "staff" and op == "staff"):
		if String(a.get("kind", "")) == "child" and op == "rec":
			return "child_play"
		var v: Dictionary = sim.leisure.venue_of(a) if sim.get("leisure") != null else {}
		if not v.is_empty():
			return String(v["act"])
	return ""

## The V5 duties of a person with nothing to do (agents._think, before work): school or play for a
## child, a course or a class to teach, a protest, a patrol for an officer, a shift at a venue.
## true: a plan started.
func duty_think(a: Dictionary) -> bool:
	if String(a.get("kind", "")) == "child":
		return sim.families.child_think(a)
	if sim.education.think(a):
		return true
	if a.has("v5_nowork"):
		return false
	if sim.unrest.protest_think(a):
		return true
	if String(a.get("role", "")) == "security":
		return sim.security.patrol_think(a)
	if a.has("job") and sim.leisure.staff_think(a):
		return true
	return false

func _h(id: int, salt: int) -> float:
	return Rng.hash2(id, salt, int(sim.state.get("seed", 1)) ^ 0x5EED)

func _pick(arr: Array, id: int, salt: int):
	return arr[clampi(int(_h(id, salt) * arr.size()), 0, arr.size() - 1)]

# ---------------------------------------------------------------- identity (V5 section 2)
## {id, name, sex ("m"|"f"), variant (m1..f3, c1, c2), child (bool), age, height (m),
##  tint {skin 0..1, hair 0..1, grey (bool)}, traits [2-3], attraction ("opposite"|"same"|"both"|""),
##  kind ("colonist"|"visitor"|"child"), vip (bool)}
func identity(a: Dictionary) -> Dictionary:
	var id: int = int(a["id"])
	if _id_cache.has(id):
		return _id_cache[id]
	var c: Dictionary = cfg()
	var child: bool = String(a.get("kind", "")) == "child"
	var first: String = String(a.get("name", "")).split(" ")[0]
	var sex: String = String(c["name_sex"].get(first, "m" if _h(id, 1) < 0.5 else "f"))
	var variant: String
	if child:
		variant = "c1" if sex == "m" else "c2"
	else:
		variant = "%s%d" % [sex, 1 + int(_h(id, 2) * 3.0) % 3]
	var ar: Array = c["age"]["child" if child else "adult"]
	var age: int = int(ar[0]) + int(_h(id, 3) * float(int(ar[1]) - int(ar[0]) + 1))
	# A child who grew up (families.gd) keeps a young adult age.
	if a.has("age_set"):
		age = int(a["age_set"])
	var vdef: Dictionary = c["variants"][variant]
	var height: float = snappedf(float(vdef["height"]) + (_h(id, 4) - 0.5) * 0.06, 0.01)
	var grey: bool = age >= int(c["tint"]["hair_grey_age"]) and _h(id, 5) < 0.7
	var tint := {"skin": snappedf(_h(id, 6), 0.001), "hair": 1.0 if grey else snappedf(_h(id, 7) * float(c["tint"]["hair"][1]), 0.001), "grey": grey}
	# 2-3 traits, no conflicting pair.
	var all: Array = c["traits"]
	var traits: Array = []
	var want: int = 2 + (1 if _h(id, 8) < 0.5 else 0)
	var k := 0
	while traits.size() < want and k < 40:
		var t: String = _pick(all, id, 20 + k)
		k += 1
		if traits.has(t) or _conflicts(t, traits):
			continue
		traits.append(t)
	var attraction := ""
	if not child and String(a.get("kind", "")) != "child":
		var w: Dictionary = c["attraction"]
		var r: float = _h(id, 9)
		attraction = "opposite" if r < float(w["opposite"]) else ("same" if r < float(w["opposite"]) + float(w["same"]) else "both")
	var kind: String = "child" if child else ("visitor" if String(a.get("kind", "")) == "visitor" else "colonist")
	# Easter eggs (V5 section 4.5): "barby" (the one-off tourist, a unique jacket) and "champion" (a
	# PRISM SHIFT champion, about 1 in 1,000).
	var egg := ""
	if String(a.get("vip", "")) == "barby":
		egg = "barby"
	elif not child and sim.get("eggs") != null and sim.eggs.is_champion(id):
		egg = "champion"
	var out := {"id": id, "name": a.get("name", ""), "sex": sex, "variant": variant, "child": child, "age": age, "height": height,
		"tint": tint, "traits": traits, "attraction": attraction, "kind": kind, "vip": egg == "barby", "egg": egg}
	if egg == "barby":
		out["sex"] = "m"
		out["variant"] = "m1"
		out["traits"] = ["funny", "charming"]
	_id_cache[id] = out
	return out

func _conflicts(t: String, have: Array) -> bool:
	for pair in cfg()["trait_conflicts"]:
		if (pair[0] == t and have.has(pair[1])) or (pair[1] == t and have.has(pair[0])):
			return true
	return false

func has_trait(a: Dictionary, t: String) -> bool:
	return (identity(a)["traits"] as Array).has(t)

# ---------------------------------------------------------------- skills (V5 section 5.2)
## {skill: 0..100} for the 11 skills.
func skills(a: Dictionary) -> Dictionary:
	var c: Dictionary = cfg()
	var st: Dictionary = c["start_skill"]
	var id: int = int(a["id"])
	var mine: Array = c["role_skills"].get(String(a.get("role", "")), [])
	# Days here: whole game days since the person arrived (the day turns for everybody at once).
	var dt: int = int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))
	var days: float = float(maxi(0, int(sim.state["tick"]) / dt - int(a.get("born", 0)) / dt))
	var bonus: Dictionary = rec_of(id).get("skill_bonus", {})
	# V5 section 5.2: role skills grow with the work done (state: rec.xp, people._grow); before the
	# first update the days here stand in for it (the rule of saves before the change).
	var xp = rec_of(id).get("xp")
	var key: int = bonus.hash() ^ (xp.hash() if xp != null else 0)
	var hit = _skill_cache.get(id)
	if hit != null and hit[0] == days and hit[1] == String(a.get("role", "")) and hit[3] == key:
		return hit[2]
	var out := {}
	var i := 0
	for sk in c["skills"]:
		i += 1
		var v: float
		if mine.has(sk):
			v = lerpf(float(st["role_from"]), float(st["role_to"]), _h(id, 100 + i)) + (float(xp.get(sk, 0.0)) if xp != null else minf(float(st["cap"]), days * float(st["per_day"])))
		else:
			v = _h(id, 200 + i) * float(st["other_to"])
		if sk == "leadership" or sk == "social":
			v += 20.0 * _h(id, 300 + i)
		v += float(bonus.get(sk, 0))
		out[sk] = clampi(int(round(v)), 0, 100)
	_skill_cache[id] = [days, String(a.get("role", "")), out, key]
	return out

## Level 1..5 of a skill value.
func level_of(v: float) -> int:
	var fr: Array = cfg()["skill_levels"]["from"]
	var lv := 1
	for i in fr.size():
		if v >= float(fr[i]):
			lv = i + 1
	return lv

func level_name(v: float) -> String:
	return String(cfg()["skill_levels"]["names"][level_of(v) - 1])

## Work speed factor of a person's main role skill (L1 0.7 .. L5 1.4). Not applied to work yet.
func work_mult(a: Dictionary) -> float:
	var mine: Array = cfg()["role_skills"].get(String(a.get("role", "")), [])
	if mine.is_empty():
		return 1.0
	return float(cfg()["skill_levels"]["work_mult"][level_of(float(skills(a)[mine[0]])) - 1])

func department(a: Dictionary) -> String:
	var role: String = String(a.get("role", ""))
	if _dep_of.has(role):
		return _dep_of[role]
	var out := ""
	for d in cfg()["departments"]:
		if (cfg()["departments"][d]["roles"] as Array).has(role):
			out = d
			break
	_dep_of[role] = out
	return out

## The agent id of the captain of a department in a base (-1: none). Cached with the ranks.
func captain_of(dep: String, base: int) -> int:
	_refresh_ranks(false)
	return int(_captains.get("%d:%s" % [base, dep], -1))

# ---------------------------------------------------------------- ranks (V5 section 5.1)
## {rank ("commander"|"captain"|"first_hand"|"specialist"|"crew"|"trainee"|"visitor"|"child"),
##  name ("Base Commander", "Captain", ...), title ("Captain of Food", ...), department, base}
## Stub: SIM's proposal (the best candidates) is the rank; appointments come later.
func rank(a: Dictionary) -> Dictionary:
	_refresh_ranks(false)
	return _ranks.get(int(a["id"]), {"rank": "crew", "name": "Crew", "title": "Crew", "department": department(a), "base": -1})

## The ranks in force: state.v5.ranks {agent id: rank record} and state.v5.captains, made by the
## simulation once a game minute (people.tick) and at once after an order that changes them
## (ranks_dirty: appointments, demotions, a new role, a new home, a child who grew up). They are state,
## so a loaded game has the same ranks as the game that was saved (cost: no roster check a tick).
## A person who arrived since the last update has no record yet: rank() says crew.
func _refresh_ranks(force: bool = false) -> void:
	var v: Dictionary = sim.state.get("v5", {})
	if v.has("ranks"):
		if not is_same(_ranks, v["ranks"]):
			_ranks = v["ranks"]
			_captains = v.get("captains", {})
		return
	_compute_ranks(force)

## Makes the ranks now and stores them (simulation only: commands and ticks, never the interface).
func store_ranks() -> void:
	_rank_sig = -1
	_sig_tick = -1
	_rank_tick = -1
	_compute_ranks(true)
	var v: Dictionary = v5w()
	v["ranks"] = _ranks
	v["captains"] = _captains

## An order changed who holds a post, a role or a home: the ranks are made again now.
func ranks_dirty() -> void:
	store_ranks()

## Ranks are proposed again when the roster changes (who lives, their roles and homes, the day
## of the skills, the appointments). Used directly only before the first stored ranks.
func _compute_ranks(force: bool = false) -> void:
	var hz: int = int(sim.bal["tick_hz"])
	var now: int = int(sim.state["tick"])
	var tick: int = now / (60 * hz)
	if not force and tick == _rank_tick and _rank_sig != -1:
		return
	# One check a tick at most (the simulation asks for several people on one tick).
	if force and now == _sig_tick and _rank_sig != -1:
		return
	_rank_tick = tick
	_sig_tick = now
	var nb: int = sim.bases.count()
	var day: int = now / int(float(sim.bal["day_length"]) * float(hz))
	var appt: Dictionary = v5r().get("appoint", {})
	var sig: int = day * 7919 + appt.hash() % 1000003
	# Demotions in force (a few at most) change the proposal while they last.
	for did in appt.get("demoted", {}):
		if int(appt["demoted"][did]) > now:
			sig = (sig * 31 + int(did)) & 0x3FFFFFFFFFFF
	# The roster: ids, roles and beds (a bed fixes the home base); cheap enough for every tick.
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var rh = _role_hash.get(a.get("role", ""))
		if rh == null:
			rh = String(a.get("role", "")).hash() & 0xFFFFFF
			_role_hash[a.get("role", "")] = rh
		var hb: int = int(a.get("bed", -1))
		if hb == -1 and nb > 1:
			hb = -1000 - sim.bases.base_of_agent(a)
		sig = (sig * 31 + int(aid) * 131 + int(rh) + hb * 17) & 0x3FFFFFFFFFFF
	if sig == _rank_sig:
		return
	var homes := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive":
			homes[int(aid)] = sim.bases.home_of(a) if nb > 0 else -1
	_rank_sig = sig
	_ranks = {}
	_captains = {}
	var c: Dictionary = cfg()
	var by_base := {}
	for aid in homes:
		var a: Dictionary = sim.state["agents"][aid]
		var idn: Dictionary = identity(a)
		if idn["kind"] != "colonist":
			_ranks[int(aid)] = {"rank": idn["kind"], "name": String(idn["kind"]).capitalize(), "title": String(idn["kind"]).capitalize(), "department": "", "base": sim.bases.base_of_agent(a) if nb > 0 else -1}
			continue
		var b: int = int(homes[aid])
		if not by_base.has(b):
			by_base[b] = []
		by_base[b].append(a)
	for b in by_base:
		var people: Array = by_base[b]
		people.sort_custom(func(x, y): return int(x["id"]) < int(y["id"]))
		var here := {}
		for a in people:
			here[int(a["id"])] = a
		# Commander: the appointed one, else the best leader (ties: the longest here, then id).
		var best: Dictionary = {}
		var appointed: int = int(appt.get("%d:commander" % b, -1))
		if here.has(appointed):
			best = here[appointed]
		else:
			var best_v := -1.0
			for a in people:
				if int(appt.get("demoted", {}).get(int(a["id"]), -1)) > now:
					continue
				var v: float = float(skills(a)["leadership"]) - float(a.get("born", 0)) / 1e9
				if v > best_v:
					best_v = v
					best = a
		var taken := {}
		if not best.is_empty():
			taken[int(best["id"])] = true
			_ranks[int(best["id"])] = {"rank": "commander", "name": c["ranks"]["commander"]["name"], "title": c["ranks"]["commander"]["name"], "department": "command", "base": b}
		for dep in c["departments"]:
			var dd: Dictionary = c["departments"][dep]
			var members: Array = []
			for a in people:
				if not taken.has(int(a["id"])) and (dd["roles"] as Array).has(String(a["role"])):
					members.append(a)
			var sk: String = dd["skill"]
			# Sort keys first (one skills() call per person, not one per comparison).
			var keyed: Array = []
			for a in members:
				var sks: Dictionary = skills(a)
				keyed.append([int(sks[sk]) + int(sks["leadership"]) / 4, int(a["id"]), a])
			keyed.sort_custom(func(x, y): return int(x[0]) > int(y[0]) if int(x[0]) != int(y[0]) else int(x[1]) < int(y[1]))
			members = []
			for kx in keyed:
				members.append(kx[2])
			# Appointed captain and first hands first, then the proposal; a person demoted in
			# the last days is not proposed for a post.
			var cap_id: int = int(appt.get("%d:%s:captain" % [b, dep], -1))
			var fh_ids: Array = appt.get("%d:%s:first_hand" % [b, dep], [])
			var head: Array = []
			var tail: Array = []
			var cap_row = null
			for a in members:
				var aid2: int = int(a["id"])
				if aid2 == cap_id:
					cap_row = a
				elif fh_ids.has(aid2):
					head.append(a)
				else:
					tail.append(a)
			var demoted: Array = []
			var free: Array = []
			for a in tail:
				if int(appt.get("demoted", {}).get(int(a["id"]), -1)) > now:
					demoted.append(a)
				else:
					free.append(a)
			if cap_row == null and not free.is_empty() and members.size() >= 2:
				cap_row = free.pop_front()
			members = ([cap_row] if cap_row != null else []) + head + free + demoted
			var fh_n: int = 0 if members.size() < 3 else (1 if members.size() < 6 else 2)
			fh_n = maxi(fh_n, head.size())
			for i in members.size():
				var a: Dictionary = members[i]
				var r: String
				if i == 0 and cap_row != null:
					r = "captain"
				elif i >= (1 if cap_row != null else 0) and i < (1 if cap_row != null else 0) + fh_n and int(appt.get("demoted", {}).get(int(a["id"]), -1)) <= now:
					r = "first_hand"
				else:
					var v2: int = int(skills(a)[sk])
					r = "specialist" if v2 >= int(c["ranks"]["specialist"]["skill_from"]) else ("crew" if v2 >= int(c["ranks"]["crew"]["skill_from"]) else "trainee")
				var nm: String = String(c["ranks"][r]["name"])
				var title: String = nm + (" of " + String(dd["name"]) if r == "captain" or r == "first_hand" else "")
				_ranks[int(a["id"])] = {"rank": r, "name": nm, "title": title, "department": dep, "base": b}
				if r == "captain":
					_captains["%d:%s" % [b, dep]] = int(a["id"])

# ---------------------------------------------------------------- outfit (V5 section 1)
## The outfit to draw now: "suit" outside; "prison" in jail; children "school" at the academy,
## else casual; on duty the role uniform (commander and captains "uniform_command"); off duty
## (asleep, at leisure, at home) casual_a/b/c (fixed per person); "swimwear" at a pool.
func outfit(a: Dictionary) -> String:
	if a["where"] == "out":
		return "suit"
	var idn: Dictionary = identity(a)
	var casual: String = ["casual_a", "casual_b", "casual_c"][int(_h(int(a["id"]), 11) * 3.0) % 3]
	if bool(a.get("jailed", false)):
		return "prison"
	var here: Dictionary = sim.state["buildings"].get(int(a.get("bld", -1)), {})
	# V5 section 8: the pool (swimwear), for everybody at the pool venue.
	if String(a.get("venue", "")) == "pool" and String(a.get("plan_kind", "")) == "rec":
		return "swimwear"
	if idn["child"]:
		return "school" if (not here.is_empty() and here["def"] == "academy") or String(a.get("plan_kind", "")) == "class" else casual
	if idn["kind"] == "visitor":
		return casual
	var kind: String = String(a.get("plan_kind", ""))
	# Staff of a venue work in the Food department's uniform; a student in class wears casual.
	if kind == "staff":
		return "uniform_food"
	if kind == "class" or kind == "protest":
		return casual
	if bool(a.get("sleeping", false)) or kind == "sleep" or kind == "rec":
		return casual
	if not here.is_empty() and String(sim.bdef(here["def"]).get("category", "")) == "housing" and not ["task", "patrol", "respond", "escort", "teach"].has(kind):
		return casual
	var r: String = String(rank(a)["rank"])
	if r == "commander" or r == "captain":
		return "uniform_command"
	return String(cfg()["role_uniform"].get(String(a.get("role", "")), "uniform_engineering"))

## Department stripe colour and rank insignia for RENDER: {stripe ("amber"|"blue"|...|""), insignia (rank id)}.
func marks(a: Dictionary) -> Dictionary:
	var dep: String = department(a)
	var r: Dictionary = rank(a)
	return {"stripe": String(cfg()["departments"].get(dep, {}).get("stripe", "")), "insignia": String(r["rank"])}

# ---------------------------------------------------------------- home (V5 section 7)
## {kind ("none"|"dorm"|"family"|"executive"|"penthouse"), quality 0..4, building (id or -1),
##  unit (index or -1), floor}. Stub: the building of the person's bed.
func home(a: Dictionary) -> Dictionary:
	var bid: int = int(a.get("bed", -1))
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty():
		return {"kind": "none", "quality": 0, "building": -1, "unit": -1, "floor": 0}
	var def: Dictionary = sim.bdef(b["def"])
	var kind := "dorm"
	var unit := -1
	var fl := 0
	if def.has("units"):
		var units: Array = sim.floors.units(b)
		if not units.is_empty():
			var pick: int = int(_h(int(a["id"]), 12) * units.size()) % units.size()
			var want_u: int = int(rec_of(int(a["id"])).get("unit", -1))
			if want_u >= 0 and want_u < units.size():
				pick = want_u
			var u: Dictionary = units[pick]
			kind = String(u["quality"])
			unit = int(u["index"])
			fl = int(u["floor"])
	elif def.has("variants"):
		kind = String(def["variants"].get(String(b.get("variant", def.get("variant", "family"))), {}).get("quality", "family"))
		unit = int(_h(int(a["id"]), 12) * 4.0)
	return {"kind": kind, "quality": int(cfg()["housing_quality"].get(kind, 1)), "building": bid, "unit": unit, "floor": fl}

# ---------------------------------------------------------------- satisfaction and attitude (V5 section 6.1)
## {value 0..100, components {needs, food, housing, comfort, social, work, fairness, safety, freedom},
##  reasons [{component, text, delta}] (the lowest first)}. "needs" is the v3 morale.
func satisfaction(a: Dictionary) -> Dictionary:
	var id: int = int(a["id"])
	var ph: int = _phase(id)
	var hit = _sat_cache.get(id)
	if hit != null and int(hit[0]) == ph:
		return hit[1]
	var out: Dictionary = _satisfaction(a)
	_sat_cache[id] = [ph, out]
	return out

## lite: no reasons (the simulation's own update needs the value and the components only).
func _satisfaction(a: Dictionary, lite: bool = false) -> Dictionary:
	var comp := {}
	var reasons: Array = []
	comp["needs"] = clampf(float(a.get("morale", 50.0)), 0.0, 100.0)
	var food: float = 60.0
	if a.has("nutrition"):
		food = clampf(sim.nutrition.score(a), 0.0, 100.0)
	comp["food"] = food
	var h: Dictionary = home(a)
	var want: int = 3 if ["commander", "captain"].has(String(rank(a)["rank"])) else 1
	comp["housing"] = clampf(50.0 + 20.0 * float(int(h["quality"]) - want), 0.0, 100.0)
	var day_t: float = float(sim.bal["tick_hz"]) * float(sim.bal["day_length"])
	var gap_days: float = float(int(sim.state["tick"]) - int(a.get("last_rec", -1000000))) / day_t
	comp["comfort"] = clampf(90.0 - gap_days * 25.0, 10.0, 90.0)
	# V5 section 9: a visit to an open venue with its goods adds its quality for a day.
	if a.has("rec_q_t") and float(int(sim.state["tick"]) - int(a["rec_q_t"])) < float(soc()["leisure"]["rec_q_days"]) * day_t:
		comp["comfort"] = minf(100.0, float(comp["comfort"]) + float(a.get("rec_q", 0.0)))
	# V5 section 4.2: friends, a partner and enemies (relations.gd).
	var so: Dictionary = sim.relations.summary(int(a["id"])) if sim.get("relations") != null else {"friends": 0, "best_friends": 0, "partner": -1, "enemies": 0}
	var social: float = 50.0 + 6.0 * minf(4.0, float(so["friends"])) + 10.0 * minf(2.0, float(so["best_friends"])) + (15.0 if int(so["partner"]) != -1 else 0.0) - 6.0 * minf(3.0, float(so["enemies"]))
	comp["social"] = clampf(social + (8.0 if has_trait(a, "charming") else 0.0) - (8.0 if has_trait(a, "shy") else 0.0), 0.0, 100.0)
	# Partners who do not share a home (V5 section 7).
	if int(so["partner"]) != -1:
		var pa: Dictionary = sim.state["agents"].get(int(so["partner"]), {})
		if not pa.is_empty() and (int(pa["bed"]) != int(a["bed"]) or int(rec_of(int(pa["id"])).get("unit", -1)) != int(rec_of(int(a["id"])).get("unit", -1))):
			comp["housing"] = clampf(float(comp["housing"]) - 10.0, 0.0, 100.0)
	comp["work"] = clampf(75.0 - maxf(0.0, float(a.get("fatigue", 0.0)) - 60.0), 0.0, 100.0)
	comp["fairness"] = 70.0
	var safety: float = 90.0 - float(a.get("dose", 0.0)) / 10.0 - (30.0 if sim.hazards.sheltered() else 0.0)
	comp["safety"] = clampf(safety - (100.0 - float(a.get("health", 100.0))) * 0.3, 0.0, 100.0)
	comp["freedom"] = 20.0 if bool(a.get("jailed", false)) else (40.0 if a.has("v5_norec") else 80.0)
	# V5 section 6: reviews, discipline and punishments seen move one component each.
	var now: int = int(sim.state["tick"])
	for m in rec_of(int(a["id"])).get("mods", []):
		if int(m["until"]) > now and comp.has(String(m.get("comp", ""))):
			comp[m["comp"]] = clampf(float(comp[m["comp"]]) + float(m.get("sat", 0.0)), 0.0, 100.0)
	var w: Dictionary = SAT_W
	var s := 0.0
	var ws := 0.0
	for k in comp:
		s += float(comp[k]) * float(w[k])
		ws += float(w[k])
		comp[k] = snappedf(float(comp[k]), 0.1)
	if lite:
		return {"value": snappedf(s / ws, 0.1), "components": comp, "reasons": reasons}
	var texts: Dictionary = SAT_BAD
	var good: Dictionary = SAT_GOOD
	var keys: Array = comp.keys()
	keys.sort_custom(func(x, y): return float(comp[x]) < float(comp[y]) if float(comp[x]) != float(comp[y]) else String(x) < String(y))
	for k in keys:
		var v: float = float(comp[k])
		if v < 50.0:
			reasons.append({"component": k, "text": texts[k], "delta": snappedf(v - 50.0, 0.1)})
		elif v >= 75.0:
			reasons.append({"component": k, "text": good[k], "delta": snappedf(v - 50.0, 0.1)})
	return {"value": snappedf(s / ws, 0.1), "components": comp, "reasons": reasons}

## {value -100..100, trend (per day, stub 0), reasons [{text, delta}]}.
func attitude(a: Dictionary) -> Dictionary:
	var id: int = int(a["id"])
	var ph: int = _phase(id)
	var hit = _att_cache.get(id)
	if hit != null and int(hit[0]) == ph:
		return hit[1]
	var out: Dictionary = _attitude(a)
	_att_cache[id] = [ph, out]
	return out

func _attitude(a: Dictionary) -> Dictionary:
	var tg: Dictionary = attitude_target(a, float(satisfaction(a)["value"]))
	var rec: Dictionary = rec_of(int(a["id"]))
	var v: float = float(tg["value"])
	var trend := 0.0
	if rec.has("att"):
		v = float(rec["att"])
		# Points a day toward the target at the present gap.
		var per_day: float = float(sim.bal["day_length"]) / float(soc()["update_every_s"])
		trend = snappedf((float(tg["value"]) - v) * float(soc()["attitude"]["rate"]) * per_day, 0.1)
	return {"value": snappedf(clampf(v, -100.0, 100.0), 0.1), "trend": trend, "target": tg["value"], "reasons": tg["reasons"]}

## Where a person's attitude goes: {value, reasons [{text, delta}]} from satisfaction, traits and
## the active reviews and discipline.
func attitude_target(a: Dictionary, sat: float, lite: bool = false) -> Dictionary:
	var ac: Dictionary = soc()["attitude"]
	var v: float = (sat - 50.0) * float(ac["from_satisfaction"])
	var reasons: Array = [] if lite else [{"text": "Satisfaction %d" % int(sat), "delta": snappedf(v, 0.1)}]
	var mods: Dictionary = ac["traits"]
	for tr in identity(a)["traits"]:
		if mods.has(tr):
			v += float(mods[tr])
			if not lite:
				reasons.append({"text": "Trait: %s" % tr, "delta": float(mods[tr])})
	var now: int = int(sim.state["tick"])
	for m in rec_of(int(a["id"])).get("mods", []):
		if int(m["until"]) > now and float(m.get("att", 0.0)) != 0.0:
			v += float(m["att"])
			if not lite:
				reasons.append({"text": String(m.get("text", m["kind"])), "delta": float(m["att"])})
	return {"value": snappedf(clampf(v, -100.0, 100.0), 0.1), "reasons": reasons}

# ---------------------------------------------------------------- lists
## One row per living person (colonists, visitors, children) for the crew list and the follow HUD.
func list() -> Array:
	# One list per tick (the crew screen and the HUD ask on the same frame).
	if _list_tick == int(sim.state["tick"]):
		return _list
	var out: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var ph: int = _phase(int(aid))
		var hit = _row_cache.get(int(aid))
		if hit != null and (int(hit[0]) == ph or not _take_budget()):
			out.append(hit[1])
			continue
		var idn: Dictionary = identity(a)
		var r: Dictionary = rank(a)
		_row_cache[int(aid)] = [ph, {"id": int(aid), "name": a["name"], "kind": idn["kind"], "sex": idn["sex"], "variant": idn["variant"], "age": idn["age"],
			"role": a["role"], "rank": r["rank"], "title": r["title"], "department": r["department"], "base": r["base"],
			"outfit": outfit(a), "satisfaction": float(satisfaction(a)["value"]), "attitude": float(attitude(a)["value"]),
			"activity": String(a.get("goal", "")), "home": home(a), "job": String(a.get("job", "")), "prisoner": a.has("jailed"),
			"hold": String(a.get("v5_hold", "")), "egg": String(idn.get("egg", ""))}]
		out.append(_row_cache[int(aid)][1])
	_list_tick = int(sim.state["tick"])
	_list = out
	return out
