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
var _rank_sig := -1          # roster signature of _ranks (ids, roles, homes, the day)
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

## Fills the caches after a load, so the first scan in a frame does not pay for everybody.
func prewarm() -> void:
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive":
			attitude(a)
	list()

func cfg() -> Dictionary:
	return sim.content["people"]

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
	var out := {"id": id, "name": a.get("name", ""), "sex": sex, "variant": variant, "child": child, "age": age, "height": height,
		"tint": tint, "traits": traits, "attraction": attraction, "kind": kind, "vip": false}
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
	var days: float = float(int((int(sim.state["tick"]) - int(a.get("born", 0))) / int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))))
	var hit = _skill_cache.get(id)
	if hit != null and hit[0] == days and hit[1] == String(a.get("role", "")):
		return hit[2]
	var out := {}
	var i := 0
	for sk in c["skills"]:
		i += 1
		var v: float
		if mine.has(sk):
			v = lerpf(float(st["role_from"]), float(st["role_to"]), _h(id, 100 + i)) + days * float(st["per_day"])
		else:
			v = _h(id, 200 + i) * float(st["other_to"])
		if sk == "leadership" or sk == "social":
			v += 20.0 * _h(id, 300 + i)
		out[sk] = clampi(int(round(v)), 0, int(st["cap"]))
	_skill_cache[id] = [days, String(a.get("role", "")), out]
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
	_refresh_ranks()
	return int(_captains.get("%d:%s" % [base, dep], -1))

# ---------------------------------------------------------------- ranks (V5 section 5.1)
## {rank ("commander"|"captain"|"first_hand"|"specialist"|"crew"|"trainee"|"visitor"|"child"),
##  name ("Base Commander", "Captain", ...), title ("Captain of Food", ...), department, base}
## Stub: SIM's proposal (the best candidates) is the rank; appointments come later.
func rank(a: Dictionary) -> Dictionary:
	_refresh_ranks()
	return _ranks.get(int(a["id"]), {"rank": "crew", "name": "Crew", "title": "Crew", "department": department(a), "base": -1})

func _refresh_ranks() -> void:
	# Ranks are proposed again when the roster changes (who lives, their roles and homes, the
	# day of the skills); the roster is checked once a game minute (60 s).
	var hz: int = int(sim.bal["tick_hz"])
	var tick: int = int(sim.state["tick"]) / (60 * hz)
	if tick == _rank_tick and _rank_sig != -1:
		return
	_rank_tick = tick
	var nb: int = sim.bases.count()
	var day: int = int(sim.state["tick"]) / int(float(sim.bal["day_length"]) * float(hz))
	var sig: int = day * 7919
	var homes := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var hb: int = sim.bases.home_of(a) if nb > 0 else -1
		homes[int(aid)] = hb
		sig = (sig * 31 + int(aid) * 131 + String(a.get("role", "")).hash() + hb * 17) & 0x3FFFFFFFFFFF
	if sig == _rank_sig:
		return
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
		# Commander: the best leader (ties: the longest here, then id).
		var best: Dictionary = {}
		var best_v := -1.0
		for a in people:
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
			var fh_n: int = 0 if members.size() < 3 else (1 if members.size() < 6 else 2)
			for i in members.size():
				var a: Dictionary = members[i]
				var r: String
				if i == 0 and members.size() >= 2:
					r = "captain"
				elif i >= 1 and i <= fh_n:
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
	if idn["child"]:
		return "school" if not here.is_empty() and here["def"] == "academy" else casual
	if idn["kind"] == "visitor":
		return casual
	var kind: String = String(a.get("plan_kind", ""))
	if bool(a.get("sleeping", false)) or kind == "sleep" or kind == "rec":
		return casual
	if not here.is_empty() and String(sim.bdef(here["def"]).get("category", "")) == "housing" and kind != "task":
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
			var u: Dictionary = units[int(_h(int(a["id"]), 12) * units.size()) % units.size()]
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

func _satisfaction(a: Dictionary) -> Dictionary:
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
	var gap_days: float = float(int(sim.state["tick"]) - int(a.get("last_rec", -1000000))) / (float(sim.bal["tick_hz"]) * float(sim.bal["day_length"]))
	comp["comfort"] = clampf(90.0 - gap_days * 25.0, 10.0, 90.0)
	comp["social"] = clampf(45.0 + 30.0 * _h(int(a["id"]), 13) + (10.0 if has_trait(a, "charming") else 0.0) - (10.0 if has_trait(a, "shy") else 0.0), 0.0, 100.0)
	comp["work"] = clampf(75.0 - maxf(0.0, float(a.get("fatigue", 0.0)) - 60.0), 0.0, 100.0)
	comp["fairness"] = 70.0
	var safety: float = 90.0 - float(a.get("dose", 0.0)) / 10.0 - (30.0 if sim.hazards.sheltered() else 0.0)
	comp["safety"] = clampf(safety - (100.0 - float(a.get("health", 100.0))) * 0.3, 0.0, 100.0)
	comp["freedom"] = 20.0 if bool(a.get("jailed", false)) else 80.0
	var w: Dictionary = SAT_W
	var s := 0.0
	var ws := 0.0
	for k in comp:
		s += float(comp[k]) * float(w[k])
		ws += float(w[k])
		comp[k] = snappedf(float(comp[k]), 0.1)
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
	var sat: float = float(satisfaction(a)["value"])
	var v: float = (sat - 50.0) * 1.2
	var reasons: Array = [{"text": "Satisfaction %d" % int(sat), "delta": snappedf(v, 0.1)}]
	var mods := {"loyal": 12.0, "workaholic": 8.0, "calm": 5.0, "honest": 4.0, "lazy": -12.0, "hot-headed": -8.0, "greedy": -5.0}
	for t in identity(a)["traits"]:
		if mods.has(t):
			v += float(mods[t])
			reasons.append({"text": "Trait: %s" % t, "delta": mods[t]})
	return {"value": snappedf(clampf(v, -100.0, 100.0), 0.1), "trend": 0.0, "reasons": reasons}

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
			"activity": String(a.get("goal", "")), "home": home(a)}]
		out.append(_row_cache[int(aid)][1])
	_list_tick = int(sim.state["tick"])
	_list = out
	return out
