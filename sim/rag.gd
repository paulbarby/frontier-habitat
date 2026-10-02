extends RefCounted
## The social log and The Regolith Rag (docs/V5_DESIGN.md section 4.3). Texts: content/tabloid.json;
## numbers and the log codes that make stories: content/society.json "rag".
##
## Stored (schema 6) in state.v5:
##   slog [{tick, kind, actors [ids], place (building id or -1), heat, text, code}]   the social log
##   rag  {issue number: issue}   the last `keep` issues, each made once at the turn of its day
##   rag_day                     the day index of the last issue made
## Issue n covers game day n (ticks (n-1)*day .. n*day) and is printed at dawn of day n+1. Days
## before the v5 state existed (an old save) are made from the event log as before (social.gd).

const Rng = preload("res://sim/rng.gd")

var sim
var _rev := -1

func _init(s) -> void:
	sim = s

func cfg() -> Dictionary:
	return sim.content["society"]["rag"]

func tab() -> Dictionary:
	return sim.content["tabloid"]

func _day_ticks() -> int:
	return int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))

func _h(x: int, y: int) -> float:
	return Rng.hash2(x, y, int(sim.state.get("seed", 1)) ^ 0x4A61)

func _v() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("slog"):
		v["slog"] = []
	if not v.has("rag"):
		v["rag"] = {}
	if not v.has("rag_day"):
		v["rag_day"] = int(sim.state["tick"]) / _day_ticks()
	return v

# ---------------------------------------------------------------- the social log
## A notable social event. kind: a story kind of tabloid.json; actors: agent ids; place: a building
## id or -1; heat: 0..100 (how juicy).
func note(kind: String, actors: Array, place: int, heat: int, text: String, code: String = "") -> void:
	var v: Dictionary = _v()
	var sl: Array = v["slog"]
	sl.append({"tick": int(sim.state["tick"]), "kind": kind, "actors": actors.duplicate(), "place": place, "heat": heat, "text": text, "code": code})
	var cap: int = int(cfg()["slog_keep"])
	while sl.size() > cap:
		sl.pop_front()

## Called by sim.log_event for every entry: the codes of content "rag.codes" go to the social log.
func from_log(code: String, text: String, ents: Array, extra: Dictionary) -> void:
	var codes: Dictionary = cfg()["codes"]
	var c: String = code
	if code == "unrest":
		c = String(extra.get("stage", ""))
		if not ["protest", "strike", "riot"].has(c) or text.begins_with("Unrest in"):
			return
	elif code == "unrest_response":
		if String(extra.get("response", "")) != "party":
			return
		c = "party"
	elif code == "discipline" and String(extra.get("action", "")) == "demote":
		c = "demotion"
	if not codes.has(c):
		return
	var actors: Array = []
	var place := -1
	for x in ents:
		if sim.state["agents"].has(int(x)):
			actors.append(int(x))
		elif sim.state["buildings"].has(int(x)) and place == -1:
			place = int(x)
	if extra.has("place"):
		place = int(extra["place"])
	if c == "commissioned" and place != -1:
		var d: String = String(sim.state["buildings"][place]["def"])
		if (cfg()["skip_defs"] as Array).has(d) or String(sim.state["buildings"][place].get("kind", "")) == "link":
			return
	var heat: int = int(codes[c][1])
	if c == "discipline" and bool(extra.get("unfair", false)):
		heat += 15
	note(String(codes[c][0]), actors, place, heat, text, code)

## The newest n entries of the social log (newest first), for the interface.
func log_rows(n: int = 50) -> Array:
	var sl: Array = sim.state.get("v5", {}).get("slog", [])
	var out: Array = []
	for i in range(sl.size() - 1, maxi(-1, sl.size() - 1 - n), -1):
		out.append(sl[i])
	return out

# ---------------------------------------------------------------- the daily edition
## Every tick (cheap): at the turn of a day the issue of the day that ended is made and stored.
func tick() -> void:
	var now: int = int(sim.state["tick"])
	var dt: int = _day_ticks()
	if now % dt != 5:
		return
	var v: Dictionary = _v()
	var day: int = now / dt
	var last: int = int(v["rag_day"])
	if day <= last:
		return
	for n in range(maxi(last + 1, day), day + 1):
		v["rag"][n] = make_issue(n)
	v["rag_day"] = day
	var keys: Array = v["rag"].keys()
	keys.sort()
	while keys.size() > int(cfg()["keep"]):
		v["rag"].erase(keys.pop_front())
	sim.log_event("rag", "The Regolith Rag, issue %d, is out." % day, [], 0, {"issue": day})

## A stored issue ({} when that day has none stored).
func stored(n: int) -> Dictionary:
	return sim.state.get("v5", {}).get("rag", {}).get(n, {})

## Makes issue n from the social log, the relationships and the colony's state.
func make_issue(number: int) -> Dictionary:
	var dt: int = _day_ticks()
	var t0: int = (number - 1) * dt
	var t1: int = number * dt
	var cands: Array = []
	var seen := {}
	for e in sim.state.get("v5", {}).get("slog", []):
		var tk: int = int(e["tick"])
		if tk < t0 or tk >= t1:
			continue
		var acts: Array = (e["actors"] as Array).duplicate()
		acts.sort()
		var key: String = "%s:%s" % [e["kind"], str(acts)]
		if seen.has(key):
			var old: Array = cands[int(seen[key])]
			if int(e["heat"]) > int(old[3]):
				old[3] = int(e["heat"])
			continue
		seen[key] = cands.size()
		cands.append([String(e["kind"]), e["actors"], int(e["place"]), int(e["heat"]), tk, String(e["text"])])
	# The commander's poll: a fall of 10 points or more is a story.
	var poll: Dictionary = _poll(number)
	if float(poll["change"]) <= -10.0 and int(poll["commander"]) != -1:
		cands.append(["commander_scandal", [int(poll["commander"])], -1, 65, t1 - 1, ""])
	# Best dressed: a charming or party-loving person, chosen by the day.
	var bd: int = _best_dressed(number)
	if bd != -1:
		cands.append(["best_dressed", [bd], -1, 28, t1 - 2, ""])
	# Crushes nobody knows about (a hint only).
	var crush: Array = sim.relations.pairs_with(["crush"]) if sim.get("relations") != null else []
	if not crush.is_empty():
		var pr: Dictionary = crush[int(_h(number, 3) * crush.size()) % crush.size()]
		cands.append(["crush", [int(pr["a"]), int(pr["b"])], -1, 32, t1 - 3, ""])
	# A thin day: the poll and the couples fill the paper (a lead and 3 stories at least).
	if cands.size() < 4:
		cands.append(["poll", [int(poll["commander"])] if int(poll["commander"]) != -1 else [], -1, 12, t1 - 4, "", int(round(float(poll["approval"])))])
	if cands.size() < 4 and sim.get("relations") != null:
		for pr2 in sim.relations.pairs_with(["married", "partners", "dating", "best_friend"]):
			if cands.size() >= 4:
				break
			var kd: String = "couple" if String(pr2["status"]) != "best_friend" else "friends"
			cands.append([kd, [int(pr2["a"]), int(pr2["b"])], -1, 10, t1 - 5, ""])
	if cands.size() < 4:
		cands.append(["quiet", [], -1, 5, t1, ""])
	cands.sort_custom(func(x, y): return int(x[3]) > int(y[3]) if int(x[3]) != int(y[3]) else int(x[4]) < int(y[4]))
	var made: Array = []
	for i in mini(7, cands.size()):
		var c: Array = cands[i]
		made.append(_story(c[0], c[1], c[2], c[3], number * 101 + i, i == 0, int(c[6]) if c.size() > 6 else -1))
	var lead: Dictionary = made[0]
	var stories: Array = made.slice(1, 7)
	return {"number": number, "day": number, "masthead": tab()["masthead"], "tagline": tab()["tagline"], "lead": lead, "stories": stories,
		"gossip": _gossip(number), "couple_watch": _watch(["married", "partners", "dating", "fling", "affair"], number, true),
		"feud_watch": _watch(["enemy", "rival"], number, false), "poll": poll, "ads": _ads(number), "serious": _serious(),
		"stored": true}

const POSE := {"couple": "hug", "move_in": "hug", "date": "kiss_brief", "breakup": "argue", "affair": "kiss_brief", "visitor_romance": "flirt_lean",
	"fight": "punch", "arrest": "handcuffed_walk", "release": "wave", "promotion": "cheer", "demotion": "sulk", "punishment": "sulk", "protest": "protest_fist",
	"strike": "protest_fist", "riot": "punch", "wedding": "hug", "death": "sulk", "ship": "wave", "new_building": "cheer", "quiet": "talk_idle",
	"feud": "argue", "defection": "wave", "family": "hug", "birthday": "cheer", "arcade": "play_arcade", "barby": "wave", "party": "dance_a",
	"graduate": "cheer", "dance": "dance_c", "best_dressed": "wave", "commander_scandal": "sulk", "crush": "flirt_lean", "poll": "talk_idle",
	"friends": "laugh", "research": "cheer", "award": "cheer", "hazard": "sulk", "goal": "cheer",
	"party_birthday": "cheer", "party_drama": "laugh", "party_scene": "argue", "awkward": "sulk", "hr": "talk_idle", "hr_transfer": "wave"}

func _names(actors: Array) -> Array:
	var out: Array = []
	for x in actors:
		var a: Dictionary = sim.state["agents"].get(int(x), {})
		if not a.is_empty():
			out.append(String(a["name"]))
	return out

func _fill(s: String, names: Array, place: String, n: int, upper: bool) -> String:
	var an: String = names[0] if names.size() > 0 else "Someone"
	var bn: String = names[1] if names.size() > 1 else "a mystery guest"
	if upper:
		an = an.to_upper()
		bn = bn.to_upper()
	var base: String = "the colony"
	if sim.bases.count() > 0:
		base = sim.bases.name_of(int(sim.bases.ids()[0]))
	var days: int = 1 + int(sim.state["tick"]) / _day_ticks()
	return s.replace("{a}", an).replace("{b}", bn).replace("{place}", place.to_upper() if upper else place).replace("{n}", str(maxi(2, n))).replace("{base}", base.to_upper() if upper else base).replace("{days}", str(days))

func _story(kind: String, actors: Array, place_id: int, heat: int, salt: int, lead: bool, n_set: int = -1) -> Dictionary:
	var heads: Array = tab()["headlines"].get(kind, tab()["headlines"]["quiet"])
	var names: Array = _names(actors)
	var agents: Array = []
	for x in actors:
		if sim.state["agents"].has(int(x)):
			agents.append(int(x))
	var place: String = "colony"
	if sim.state["buildings"].has(place_id):
		place = String(sim.state["buildings"][place_id]["name"])
	var n: int = maxi(names.size(), sim.alive_count() / 10) if n_set < 0 else n_set
	var h: String = _fill(String(heads[int(_h(salt, heat) * heads.size()) % heads.size()]), names, place, n, true)
	var bodies: Array = tab()["bodies"].get(kind, tab()["bodies"]["quiet"])
	var parts: Array = [_fill(String(bodies[int(_h(salt, 7) * bodies.size()) % bodies.size()]), names, place, n, false)]
	if lead:
		# A lead body of 3-6 sentences: the other body lines of the kind, then fillers.
		var want: int = 3 + int(_h(salt, 11) * 4.0) % 4
		for i in bodies.size():
			var line: String = _fill(String(bodies[i]), names, place, n, false)
			if parts.size() < want - 1 and not parts.has(line):
				parts.append(line)
		var fill: Array = tab()["fillers"]
		var k := 0
		while parts.size() < want and k < 12:
			var line2: String = _fill(String(fill[int(_h(salt, 20 + k) * fill.size()) % fill.size()]), names, place, n, false)
			k += 1
			if not parts.has(line2):
				parts.append(line2)
	return {"kind": kind, "headline": h, "text": " ".join(parts), "actors": agents, "place": place.to_upper(), "place_id": place_id, "heat": heat,
		"photo": {"agents": agents.slice(0, 3), "place_hint": _place_hint(place_id), "pose_hint": String(POSE.get(kind, "talk_idle"))}}

## A place name RENDER can use for the photo backdrop: bar, park, pool, corridor, jail, lounge ...
func _place_hint(bid: int) -> String:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty():
		return "corridor"
	var d: String = String(b["def"])
	match d:
		"super_dome":
			return "dome"
		"cantina", "lounge", "retail", "park", "jail", "academy", "kitchen":
			return d
	return String(sim.bdef(d).get("category", "corridor"))

## 3-5 gossip lines: hints about crushes and affairs from the relationships, then column lines.
func _gossip(number: int) -> Array:
	var out: Array = []
	var roles: Dictionary = sim.bal.get("role_names", {})
	if sim.get("relations") != null:
		for pr in sim.relations.pairs_with(["crush", "affair", "fling"]):
			if out.size() >= 2:
				break
			var a: Dictionary = sim.state["agents"].get(int(pr["a"]), {})
			var b: Dictionary = sim.state["agents"].get(int(pr["b"]), {})
			if a.is_empty() or b.is_empty():
				continue
			var ra: String = String(roles.get(String(a["role"]), String(a["role"]))).to_lower()
			var rb: String = String(roles.get(String(b["role"]), String(b["role"]))).to_lower()
			match String(pr["status"]):
				"crush":
					out.append("Which %s keeps finding reasons to talk to a certain %s? We know. You will too." % [ra, rb])
				"affair":
					out.append("A %s and a %s were seen leaving the same room. Separately. Very separately." % [ra, rb])
				"fling":
					out.append("A %s has a new favourite visitor. The ship leaves soon." % ra)
	# V5 section 17: the HR officer is loved in public and gossiped about in the gossip column.
	if sim.get("hr") != null and sim.hr.active() and _h(number, 17) < 0.7:
		var hg: Array = sim.content["hr"]["gossip"]
		out.append(String(hg[int(_h(number, 18) * hg.size()) % hg.size()]).replace("{officer}", sim.hr.officer_name(sim.state["agents"][int(sim.hr.officers(-1)[0])])).replace("{dept}", "department").replace("{other}", "someone"))
	var cols: Array = tab()["columns"]["gossip"]
	var want: int = 3 + int(_h(number, 5) * 3.0) % 3
	var k := 0
	while out.size() < want and k < 20:
		var line: String = String(cols[int(_h(number, 40 + k) * cols.size()) % cols.size()])
		k += 1
		if not out.has(line):
			out.append(line)
	return out

const NOTES := {"married": ["Still in love. The rest of us are jealous.", "Married and still holding hands."],
	"partners": ["Next stop: wedding bells?", "They finish each other's sentences."],
	"dating": ["It is early days. We are watching.", "Seen together every evening."],
	"fling": ["A holiday romance. How long can it last?", "The ship leaves soon. Tears ahead."],
	"affair": ["Somebody is going to find out.", "Careful. The walls are thin."],
	"enemy": ["They will not share a table.", "One more word and it gets physical."],
	"rival": ["Polite smiles, sharp elbows.", "Only one of them can win."]}

## Couple Watch or Feud Watch: up to 4 pairs {a, b, status, note}; the strongest first.
func _watch(statuses: Array, number: int, love: bool) -> Array:
	if sim.get("relations") == null:
		return []
	var rows: Array = sim.relations.pairs_with(statuses)
	rows.sort_custom(func(x, y):
		var vx: float = float(x["att"]) + float(x["aff"]) if love else -float(x["aff"])
		var vy: float = float(y["att"]) + float(y["aff"]) if love else -float(y["aff"])
		return vx > vy if vx != vy else int(x["a"]) < int(y["a"]))
	var out: Array = []
	for r in rows:
		if out.size() >= 4:
			break
		var st: String = String(r["status"])
		# An affair nobody found out yet is not printed.
		if st == "affair":
			continue
		var notes: Array = NOTES.get(st, ["Watch this space."])
		out.append({"a": int(r["a"]), "b": int(r["b"]), "status": st, "note": String(notes[int(_h(number, int(r["a"]) + int(r["b"])) * notes.size()) % notes.size()])})
	return out

## The commander approval poll: {approval, question, commander (id or -1), change (points since the
## last issue)}.
func _poll(number: int) -> Dictionary:
	var sum := 0.0
	var n := 0
	var ppl: Dictionary = sim.state.get("v5", {}).get("people", {})
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
			continue
		var r: Dictionary = ppl.get(int(aid), {})
		sum += float(r.get("sat", 50.0))
		n += 1
	var approval: float = snappedf(sum / float(maxi(1, n)), 0.1)
	var prev: Dictionary = stored(number - 1)
	var change: float = snappedf(approval - float(prev.get("poll", {}).get("approval", approval)), 0.1)
	var cmd := -1
	var u: Dictionary = sim.unrest.info(-1) if sim.get("unrest") != null else {}
	for aid in sim.state["agents"]:
		var a2: Dictionary = sim.state["agents"][aid]
		if a2["state"] == "alive" and String(sim.people.rank(a2)["rank"]) == "commander":
			if cmd == -1 or int(aid) < cmd:
				cmd = int(aid)
	var who: String = "the commander"
	if cmd != -1:
		who = String(sim.state["agents"][cmd]["name"])
	return {"approval": approval, "question": "Do you approve of %s?" % who, "commander": cmd, "change": change, "unrest": String(u.get("stage", "calm"))}

## Best dressed by clothes (V5 section 4.3): the person who bought new clothes at a shop that day
## (leisure: a.clothes_t), else the best casual outfit worn that day by look (the outfit and the
## tint from people.identity; charming people carry it better). -1: nobody.
func _best_dressed(number: int) -> int:
	var dt: int = _day_ticks()
	var t0: int = (number - 1) * dt
	var best := -1
	var best_v := -1.0
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or String(a.get("kind", "")) == "child":
			continue
		var v := 0.0
		if int(a.get("clothes_t", -1)) >= t0:
			v += 100.0
		var outfit: String = sim.people.outfit(a)
		if not outfit.begins_with("casual") and outfit != "swimwear" and v <= 0.0:
			continue
		var idn: Dictionary = sim.people.identity(a)
		v += 10.0 * _h(number * 7 + outfit.hash() % 97, int(aid)) + 5.0 * absf(float(idn["tint"]["hair"]) - float(idn["tint"]["skin"]))
		if sim.people.has_trait(a, "charming") or sim.people.has_trait(a, "party-animal"):
			v += 6.0
		if v > best_v:
			best_v = v
			best = int(aid)
	return best
## 3-4 small ads: goods in stock at the shops, the next ship, then column lines.
func _ads(number: int) -> Array:
	var out: Array = []
	if sim.get("leisure") != null:
		for line in sim.leisure.ad_lines():
			if out.size() >= 2:
				break
			out.append(line)
	for f in sim.traffic.forecast():
		if out.size() >= 3:
			break
		out.append("ARRIVING SOON: %s. Beds and meals wanted." % String(f["name"]))
	var cols: Array = tab()["columns"]["ads"]
	var want: int = 3 + int(_h(number, 6) * 2.0) % 2
	var k := 0
	while out.size() < want and k < 20:
		var line2: String = String(cols[int(_h(number, 60 + k) * cols.size()) % cols.size()])
		k += 1
		if not out.has(line2):
			out.append(line2)
	return out

## The real problems (alerts of severity 2+ and unrest from protest up): [{text, severity}].
func _serious() -> Array:
	var out: Array = []
	var keys: Array = sim.state["issues"].keys()
	keys.sort()
	for k in keys:
		var iss: Dictionary = sim.state["issues"][k]
		if int(iss.get("severity", 0)) >= 2:
			out.append({"text": String(iss["text"]), "severity": int(iss["severity"])})
	if sim.get("unrest") != null:
		var u: Dictionary = sim.unrest.info(-1)
		if ["protest", "strike", "riot"].has(String(u["stage"])):
			out.append({"text": "Unrest: %s. Demand: %s" % [String(u["stage"]), String(u["demand"])], "severity": 3 if String(u["stage"]) == "riot" else 2})
	return out
