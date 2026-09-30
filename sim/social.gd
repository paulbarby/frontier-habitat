extends RefCounted
## Society (docs/V5_DESIGN.md sections 4 and 6.4): conversations, relationships, the social log
## and The Regolith Rag, and unrest. Lines: content/dialogue.json; headlines: content/tabloid.json.
##
## MILESTONE 1 (API stubs, deterministic): conversations are derived from who stands together now
## (pairs within 3 m in the same room) and the tick; relationships from the pair's ids and shared
## work; Rag issues from the event log of each day; unrest from satisfaction. Nothing is stored in
## the state yet (recent lines are kept in memory for the follow view). The real systems keep the
## same calls and store the graph, the log and the issues in state.social (schema 6).

const Rng = preload("res://sim/rng.gd")

const TALK_WINDOW := 200      # ticks: a pair may start one talk per 20 s window
const LINE_TICKS := 40        # ticks per line (4 s)
const TALK_CHANCE := 0.5      # chance a pair that stands together talks in a window
const TALK_CHANCE_SOCIAL := 0.85   # the same in a canteen, a kitchen or a room for leisure
const NEAR := 3.5             # m: two people this close can start a talk
const KEEP := 6.0             # m: a talk goes on while the two stay this close

var sim
var _recent := {}             # agent id -> [{tick, text, topic, to, emote}] (last 12, in memory)
var _talk_tick := -1
var _talks: Array = []
var _said := {}               # [pair key, start, line index] -> line (made once)
var _rag_cache := {}          # issue number -> issue (a finished day does not change)
var _unrest_cache := {}       # base id -> [game second, record]
var _iw_sec := -1
var _pairs_sig := -1          # roster signature of the Rag's couple and feud candidates
var _pairs: Array = []
var _feud_pair: Array = []
var _unrest_mem := {}         # base id -> {agent id: [satisfaction, attitude]}
var _unrest_cur := {}         # base id -> index of the next slice
var _iw := {}
var _iw_dome := false
var _iw_academy := false

## Cost rule (V5 section 13 budget): talks are kept as sessions. New pairs are searched at most
## once a game second (and only when somebody asks); the topic is chosen once per talk and each
## line is made once. A call on the same tick returns the stored list, and a call on a new tick
## only moves the talks on. Relationships are cached per game minute, finished Rag issues for
## ever, unrest per game second.

func _init(s) -> void:
	sim = s

## Clears the derived caches (a new state was loaded).
func reset() -> void:
	_recent = {}
	_talk_tick = -1
	_talks = []
	_said = {}
	_rag_cache = {}
	_unrest_cache = {}
	_iw_sec = -1
	_unrest_mem = {}
	_pairs_sig = -1
	_unrest_cur = {}

## Ticks per line of a talk (RENDER times the bubbles with it).
func line_ticks() -> int:
	return LINE_TICKS

func dlg() -> Dictionary:
	return sim.content["dialogue"]

func rag() -> Dictionary:
	return sim.content["tabloid"]

func _h(x: int, y: int) -> float:
	return Rng.hash2(x, y, int(sim.state.get("seed", 1)) ^ 0x7A1C)

func _first(a: Dictionary) -> String:
	return String(a.get("name", "")).split(" ")[0]

# ---------------------------------------------------------------- conversations (section 4.1)
## Every talk going on now: [{id, a, b (agent ids), speaker, listener, topic, line, emote, anim,
##  started (tick), line_index, lines, building, pos (Vector2, between the two)}]. The talks are
## simulation state (relations.gd starts and ends them); the lines are made here once each.
func talks() -> Array:
	var tick: int = int(sim.state["tick"])
	if tick == _talk_tick:
		return _talks
	_talk_tick = tick
	var agents: Dictionary = sim.state["agents"]
	var st: Dictionary = sim.state.get("v5", {}).get("talks", {})
	_talks = []
	for key in st:
		var s: Dictionary = st[key]
		var x: Dictionary = agents.get(int(s["a"]), {})
		var y: Dictionary = agents.get(int(s["b"]), {})
		var li: int = (tick - int(s["start"])) / LINE_TICKS
		if x.is_empty() or y.is_empty() or li >= int(s["lines"]) or li < 0:
			continue
		var speaker: Dictionary = x if li % 2 == 0 else y
		var listener: Dictionary = y if li % 2 == 0 else x
		var lk: Array = [key, int(s["start"]), li]
		var line = _said.get(lk)
		if line == null:
			line = line_for(speaker, listener, String(s["topic"]), (int(key % 2147483647) * 31 + int(s["w"]) * 7 + li) % 2147483647, int(s["bld"]), li % 2 == 1)
			_said[lk] = line
			_remember(int(speaker["id"]), int(s["start"]) + li * LINE_TICKS, line, String(s["topic"]), int(listener["id"]))
		_talks.append({"id": [key, int(s["start"])].hash(), "a": int(s["a"]), "b": int(s["b"]), "speaker": int(speaker["id"]), "listener": int(listener["id"]),
			"topic": s["topic"], "line": line["text"], "emote": line["emote"], "anim": line["anim"], "started": int(s["start"]), "line_index": li, "lines": int(s["lines"]),
			"building": int(s["bld"]), "pos": ((x["pos"] as Vector2) + (y["pos"] as Vector2)) * 0.5})
	if _said.size() > 2000:
		_said = {}
	return _talks

func _remember(sid: int, at: int, line: Dictionary, topic: String, to: int) -> void:
	var arr: Array = _recent.get(sid, [])
	arr.append({"tick": at, "text": line["text"], "topic": topic, "to": to, "emote": line["emote"]})
	while arr.size() > 12:
		arr.pop_front()
	_recent[sid] = arr

## A line a person says outside a talk (a shout at a protest, a fight, the dance egg): it shows in
## recent_lines (the follow HUD and the bubbles of the followed person).
func say(a: Dictionary, text: String, topic: String, to: int) -> void:
	if text == "":
		return
	var emotes: Dictionary = dlg().get("emotes", {})
	_remember(int(a["id"]), int(sim.state["tick"]), {"text": text, "emote": String(emotes.get(topic, ""))}, topic, to)

## A line of a topic for this person (trait variants first), slots filled; "" for an unknown topic.
func pick_line(topic: String, a: Dictionary, salt: int) -> String:
	if not dlg()["topics"].has(topic):
		return ""
	return String(line_for(a, a, topic, absi(salt) % 2147483647, int(a.get("bld", -1)))["text"])

## Talks within radius of pos (the follow view and the bubbles).
func talks_near(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	for t in talks():
		if (t["pos"] as Vector2).distance_to(pos) <= radius:
			out.append(t)
	return out

## The last n lines a person said: [{tick, text, topic, to, emote}] (newest first). Lines are
## remembered in memory (not in the save) while somebody asks for talks.
func recent_lines(agent_id: int, n: int = 3) -> Array:
	talks()
	var arr: Array = _recent.get(agent_id, [])
	var out: Array = []
	for i in range(arr.size() - 1, -1, -1):
		out.append(arr[i])
		if out.size() >= n:
			break
	return out

## Kept for callers of milestone 1 (the talks are simulation state now).
func tick_second() -> void:
	pass

## The topic a person talks about: a critical need first (the talk is a status channel), then
## colony problems, then work, gossip, romance, leisure and small talk (weights from state).
## Topic weights from the colony's problems (once a game second).
func _issue_weights() -> Dictionary:
	# Once a tick (the simulation asks when a talk starts; the answer depends only on the state).
	var sec: int = int(sim.state["tick"])
	if sec == _iw_sec:
		return _iw
	_iw_sec = sec
	var w := {"small_talk": 3.0, "work": 2.0, "gossip": 1.0, "leisure": 1.0}
	for k in sim.state["issues"]:
		var iss: Dictionary = sim.state["issues"][k]
		var code: String = String(iss.get("code", ""))
		if code.contains("air") or code.contains("oxygen"):
			w["air"] = 4.0
		elif code.contains("food") or code.contains("meal"):
			w["food"] = 4.0
		elif code.contains("power"):
			w["power"] = 3.0
		elif code.begins_with("hazard") or code.begins_with("reactor"):
			w["hazard"] = 3.0
	# V5: talk follows what happened lately (the end of the log: the last game minutes).
	var now: int = int(sim.state["tick"])
	var hz: int = int(sim.bal["tick_hz"])
	var lg: Array = sim.state["log"]
	var codes := {}
	for i in range(lg.size() - 1, maxi(-1, lg.size() - 60), -1):
		var e: Dictionary = lg[i]
		if int(e["tick"]) < now - 300 * hz:
			break
		codes[String(e["code"])] = true
	if codes.has("death"):
		w["death"] = 3.0
	if codes.has("ship_landed") or codes.has("traffic_landed") or codes.has("settlers"):
		w["ship"] = 2.0
	if codes.has("research"):
		w["research"] = 1.5
	if codes.has("promotion"):
		w["rank"] = 2.0
	else:
		w["rank"] = 0.4
	if codes.has("discipline"):
		w["discipline"] = 2.0
	w["weather"] = 0.8
	w["home_planet"] = 0.6
	w["praise"] = 0.6
	var day: int = now / int(float(sim.bal["day_length"]) * float(hz))
	if day >= 2:
		w["news"] = 0.8
	if sim.get("unrest") != null:
		var st: String = String(sim.unrest.info(-1)["stage"])
		if st != "calm":
			w["unrest"] = 3.0 if ["grumbling", "slowdown"].has(st) else 6.0
	_iw = w
	_iw_dome = false
	_iw_academy = false
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "active":
			if String(b["def"]) == "super_dome":
				_iw_dome = true
			elif String(b["def"]) == "academy":
				_iw_academy = true
	return _iw

func topic_for(a: Dictionary, other: Dictionary, salt: int) -> String:
	var idn: Dictionary = sim.people.identity(a)
	if idn["kind"] == "child":
		return "school" if String(a.get("plan_kind", "")) == "class" and _h(int(a["id"]), salt) < 0.5 else "child"
	if String(idn.get("egg", "")) == "barby":
		return "barby"
	if idn["kind"] == "visitor":
		return "visitor_says"
	# V5: the person's situation first (in a cell, at a protest, a record on the arcade).
	if a.has("jailed"):
		return "jail"
	if String(a.get("plan_kind", "")) == "protest":
		return "protest"
	if a.has("arcade_last") and int(sim.state["tick"]) - int(a["arcade_last"]) < 600 * int(sim.bal["tick_hz"]) and _h(int(a["id"]), salt + 5) < 0.5:
		return "arcade_champion" if String(idn.get("egg", "")) == "champion" else "arcade"
	if sim.people.identity(other)["kind"] == "visitor":
		return "visitor"
	var crit: float = float(sim.bal["need_critical"])
	if float(a.get("hunger", 0.0)) >= crit:
		return "hungry"
	if float(a.get("fatigue", 0.0)) >= crit:
		return "tired"
	var w: Dictionary = _issue_weights().duplicate()
	if float(a.get("fatigue", 0.0)) > 60.0:
		w["overwork"] = 2.0
	if sim.people.has_trait(a, "gossip"):
		w["gossip"] = 3.0
	if sim.people.has_trait(a, "romantic") and compatible(a, other):
		w["romance"] = 2.0
	# V5: the person's own life (stored values only: the choice is simulation state).
	var rec: Dictionary = sim.people.rec_of(int(a["id"]))
	if sim.people.has_trait(a, "hot-headed") or float(rec.get("att", 0.0)) < -30.0:
		w["complaint"] = 2.0
	if sim.get("relations") != null:
		var rel: Dictionary = sim.relations.rel_of(int(a["id"]), int(other["id"]))
		if ["dating", "partners", "married", "affair", "fling", "crush"].has(String(rel.get("status", ""))):
			w["romance"] = 4.0
		elif String(rel.get("status", "")) == "ex":
			w["breakup"] = 3.0
		if sim.relations.partner_of(int(a["id"])) != -1:
			w["family"] = 1.0
	var now: int = int(sim.state["tick"])
	for m in rec.get("mods", []):
		if int(m["until"]) > now and ["ration_cut", "confine", "jail", "warning", "extra_shift", "demote", "praise", "gift", "friend_punished"].has(String(m["kind"])):
			w["discipline"] = 4.0
			break
	if sim.get("education") != null and sim.education.in_class(a):
		w["academy"] = 3.0
	elif _iw_academy:
		w["academy"] = 0.4
	if _iw_dome:
		w["dome"] = 1.5
	if String(rec.get("low", "")) == "housing":
		w["housing"] = 2.0
	if String(a.get("role", "")) == "security":
		w["security"] = 2.0
	if a.has("rec_q_t") and int(sim.state["tick"]) - int(a["rec_q_t"]) < 300 * int(sim.bal["tick_hz"]):
		w["venue"] = 2.0
	if String(a.get("venue", "")) != "" and sim.relations.partner_of(int(a["id"])) == int(other["id"]):
		w["date"] = 5.0
	if String(rec.get("low", "")) == "work":
		w["overwork"] = maxf(float(w.get("overwork", 0.0)), 1.5)
	var keys: Array = w.keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += float(w[k])
	var r: float = _h(int(a["id"]), salt) * total
	for k in keys:
		r -= float(w[k])
		if r < 0.0:
			return k
	return "small_talk"

## {text, emote, anim} for a line on a topic, with the speaker's trait variant when there is one.
func line_for(a: Dictionary, other: Dictionary, topic: String, salt: int, bld: int, reply: bool = false) -> Dictionary:
	# The listener's turn: often a short reply instead of a line on the topic.
	if reply and dlg()["topics"].has("reply") and _h(salt, 77) < 0.5:
		topic = "reply"
	var lines: Array = dlg()["topics"].get(topic, dlg()["topics"]["small_talk"])
	var flavoured: Array = []
	var plain: Array = []
	for l in lines:
		if typeof(l) == TYPE_DICTIONARY:
			if sim.people.has_trait(a, String(l.get("trait", ""))):
				flavoured.append(String(l["text"]))
		else:
			plain.append(String(l))
	var pool: Array = flavoured if not flavoured.is_empty() and _h(int(a["id"]), salt) < 0.6 else plain
	if pool.is_empty():
		pool = plain if not plain.is_empty() else ["..."]
	var text: String = pool[int(_h(salt, int(a["id"])) * pool.size()) % pool.size()]
	var here: Dictionary = sim.state["buildings"].get(bld, {})
	var cap: String = _captain_name(a)
	text = text.replace("{other}", _first(other)).replace("{building}", String(here.get("name", "base")).to_lower()).replace("{captain}", cap)
	text = text.replace("{base}", sim.bases.name_of(sim.bases.base_of_agent(a)) if sim.bases.count() > 0 else "the base").replace("{days}", str(1 + int(sim.seconds() / float(sim.bal["day_length"]))))
	text = text.replace("{place}", String(here.get("name", "lounge"))).replace("{resource}", "oxygen").replace("{commander}", _commander_name(a))
	var emotes: Dictionary = dlg().get("emotes", {})
	var emote: String = String(emotes.get(topic, ""))
	var anim := "talk_gesture_a" if int(salt) % 2 == 0 else "talk_gesture_b"
	match topic:
		"complaint", "overwork":
			anim = "argue"
			emote = "anger"
		"romance":
			anim = "flirt_lean"
			emote = "heart"
		"hungry", "tired":
			anim = "sulk"
		"leisure", "ship":
			anim = "laugh" if sim.people.has_trait(a, "funny") else anim
	return {"text": text, "emote": emote, "anim": anim}

func _commander_name(a: Dictionary) -> String:
	var base: int = int(sim.people.rank(a)["base"])
	var cid: int = int(sim.people.v5r().get("unrest", {}).get(base, {}).get("commander", -1))
	if cid == -1 or not sim.state["agents"].has(cid):
		return "the commander"
	return _first(sim.state["agents"][cid])

func _captain_name(a: Dictionary) -> String:
	var dep: String = sim.people.department(a)
	var cid: int = sim.people.captain_of(dep, int(sim.people.rank(a)["base"]))
	if cid == -1 or not sim.state["agents"].has(cid):
		return "the captain"
	return _first(sim.state["agents"][cid])

# ---------------------------------------------------------------- relationships (section 4.2)
## Can a and b be attracted to each other (both adults, both rules allow it)?
func compatible(a: Dictionary, b: Dictionary) -> bool:
	var ia: Dictionary = sim.people.identity(a)
	var ib: Dictionary = sim.people.identity(b)
	if ia["child"] or ib["child"] or String(ia["attraction"]) == "" or String(ib["attraction"]) == "" or int(a["id"]) == int(b["id"]):
		return false
	var same: bool = ia["sex"] == ib["sex"]
	var ok_a: bool = ia["attraction"] == "both" or (ia["attraction"] == "same") == same
	var ok_b: bool = ib["attraction"] == "both" or (ib["attraction"] == "same") == same
	return ok_a and ok_b

## A pair's relationship: {other, affinity -100..100, attraction 0..100, status, known, since, talks}
## (relations.gd; stored when the two have talked).
func relation(a: Dictionary, b: Dictionary) -> Dictionary:
	return sim.relations.relation(a, b)

## The people a person knows (strangers left out), strongest first (at most n).
func relationships_of(agent_id: int, n: int = 8) -> Array:
	return sim.relations.relationships_of(agent_id, n)

# ---------------------------------------------------------------- the Regolith Rag (section 4.3)
## The issues so far, newest first (at most n): one per finished day. Each:
## {number, day, masthead, tagline, lead {kind, headline, text, actors [ids], place, heat,
##  photo {agents [ids], place_hint, pose_hint}}, stories [same shape], gossip [text],
##  couple_watch [{a, b, status}], feud_watch [{a, b, status}], poll {approval 0..100, question},
##  ads [text], serious [text]}.
func rag_issues(n: int = 30) -> Array:
	var day_ticks: int = int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))
	var today: int = int(sim.state["tick"]) / day_ticks
	var out: Array = []
	var d: int = today
	var ctx: Dictionary = {}
	while d >= 1 and out.size() < n:
		# V5: issues made at the turn of the day are stored in the game (sim/rag.gd).
		var st: Dictionary = sim.rag.stored(d) if sim.get("rag") != null else {}
		if not st.is_empty():
			out.append(st)
			d -= 1
			continue
		if not _rag_cache.has(d):
			if ctx.is_empty():
				ctx = _rag_ctx()
			_rag_cache[d] = _rag_issue(d, ctx)
		out.append(_rag_cache[d])
		d -= 1
	return out

## What all the issues made in one call share: the log by day (one pass), the couple and feud
## candidates and the approval now.
func _rag_ctx() -> Dictionary:
	var day_ticks: int = int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))
	var by_day := {}
	for e in sim.state["log"]:
		var d: int = int(e["tick"]) / day_ticks + 1
		if not by_day.has(d):
			by_day[d] = []
		by_day[d].append(e)
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	var alive: Array = []
	var approval := 0.0
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and sim.people.identity(a)["kind"] == "colonist":
			alive.append(a)
			approval += float(sim.people.satisfaction_soon(a)["value"])
	# Couples and feuds from the stored relationships.
	var pairs: Array = []
	for pr in sim.relations.pairs_with(["dating", "partners", "married", "fling", "crush"]):
		pairs.append([int(pr["a"]), int(pr["b"]), float(pr["att"]) + float(pr["aff"]) * 0.3])
	var feuds: Array = sim.relations.pairs_with(["enemy"])
	_feud_pair = [{"a": int(feuds[0]["a"]), "b": int(feuds[0]["b"]), "status": "enemy"}] if not feuds.is_empty() else []
	return {"by_day": by_day, "pairs": pairs, "feud": _feud_pair, "approval": snappedf(approval / maxf(1.0, alive.size()), 0.1)}

func rag_issue(number: int) -> Dictionary:
	# An issue is made once: its day is over (issue n covers day n, printed at its end).
	var st: Dictionary = sim.rag.stored(number) if sim.get("rag") != null else {}
	if not st.is_empty():
		return st
	if _rag_cache.has(number):
		return _rag_cache[number]
	var out: Dictionary = _rag_issue(number, _rag_ctx())
	_rag_cache[number] = out
	return out

func _rag_issue(number: int, ctx: Dictionary) -> Dictionary:
	var day_ticks: int = int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))
	var t0: int = (number - 1) * day_ticks
	var t1: int = number * day_ticks
	var stories: Array = []
	for e in ctx["by_day"].get(number, []):
		var tk: int = int(e["tick"])
		if tk < t0 or tk >= t1:
			continue
		var kind := ""
		var heat := 0
		match String(e["code"]):
			"death":
				kind = "death"
				heat = 90
			"commissioned":
				kind = "new_building"
				heat = 25
			"settlers", "ship_landed", "traffic_landed":
				kind = "ship"
				heat = 35
			"reactor_breach", "unstable_blast":
				kind = "fight"
				heat = 95
			"stage":
				kind = "promotion"
				heat = 40
		if kind == "":
			continue
		stories.append([kind, e["ents"], String(e["text"]), heat, number * 97 + stories.size()])
	# A couple story from the relationship stubs (the pair with the most attraction).
	var pair: Array = _top_pair(number, ctx["pairs"])
	if not pair.is_empty():
		stories.append(["couple" if number % 2 == 0 else "date", pair, "Our spies saw them together.", 60, number * 13])
	# The hottest first (ties: the earlier); only the lead and six stories are written.
	stories.sort_custom(func(x, y): return int(x[3]) > int(y[3]) if int(x[3]) != int(y[3]) else int(x[4]) < int(y[4]))
	if stories.is_empty():
		stories.append(["quiet", [], "Nothing happened. Or did it?", 5, number])
	var made: Array = []
	for st in stories.slice(0, 7):
		made.append(_story(st[0], st[1], st[2], st[3], st[4]))
	var lead: Dictionary = made[0]
	var rest: Array = made.slice(1, 7)
	var serious: Array = []
	for k in sim.state["issues"]:
		var iss: Dictionary = sim.state["issues"][k]
		if int(iss.get("severity", 0)) >= 2:
			serious.append(String(iss["text"]))
	var cols: Dictionary = rag()["columns"]
	if sim.get("rag") != null:
		# A day before the v5 state (an old save): the columns come from the colony now.
		return {"number": number, "day": number, "masthead": rag()["masthead"], "tagline": rag()["tagline"], "lead": lead, "stories": rest,
			"gossip": sim.rag._gossip(number), "couple_watch": sim.rag._watch(["married", "partners", "dating", "fling"], number, true),
			"feud_watch": sim.rag._watch(["enemy", "rival"], number, false), "poll": sim.rag._poll(number), "ads": sim.rag._ads(number),
			"serious": sim.rag._serious(), "stored": false}
	return {"number": number, "day": number, "masthead": rag()["masthead"], "tagline": rag()["tagline"], "lead": lead, "stories": rest,
		"gossip": [cols["gossip"][number % (cols["gossip"] as Array).size()]],
		"couple_watch": [{"a": pair[0], "b": pair[1], "status": "dating"}] if not pair.is_empty() else [],
		"feud_watch": ctx["feud"], "poll": {"approval": ctx["approval"], "question": "Do you approve of the commander?"},
		"ads": [cols["ads"][number % (cols["ads"] as Array).size()]], "serious": serious}

func _story(kind: String, actors: Array, text: String, heat: int, salt: int) -> Dictionary:
	var heads: Array = rag()["headlines"].get(kind, rag()["headlines"]["quiet"])
	var h: String = heads[int(_h(salt, heat) * heads.size()) % heads.size()]
	var names: Array = []
	var agents: Array = []
	var place := "COLONY"
	for x in actors:
		var a: Dictionary = sim.state["agents"].get(int(x), {})
		if not a.is_empty():
			names.append(String(a["name"]).to_upper())
			agents.append(int(x))
		elif sim.state["buildings"].has(int(x)):
			place = String(sim.state["buildings"][int(x)]["name"]).to_upper()
	h = h.replace("{a}", names[0] if names.size() > 0 else "SOMEONE").replace("{b}", names[1] if names.size() > 1 else "A MYSTERY GUEST")
	h = h.replace("{place}", place).replace("{n}", str(maxi(2, names.size()))).replace("{base}", "THE COLONY")
	var pose := {"couple": "hug", "date": "kiss_brief", "breakup": "argue", "affair": "kiss_brief", "fight": "punch", "arrest": "handcuffed_walk",
		"promotion": "cheer", "protest": "protest_fist", "wedding": "hug", "death": "sulk", "ship": "wave", "new_building": "cheer", "quiet": "talk_idle"}
	return {"kind": kind, "headline": h, "text": text, "actors": agents, "place": place, "heat": heat,
		"photo": {"agents": agents, "place_hint": place.to_lower(), "pose_hint": String(pose.get(kind, "talk_idle"))}}

func _top_pair(salt: int, pairs: Array) -> Array:
	var best := -1.0
	var out: Array = []
	for pr in pairs:
		var v: float = float(pr[2]) + _h(salt, int(pr[0]) + int(pr[1])) * 20.0
		if v > best:
			best = v
			out = [int(pr[0]), int(pr[1])]
	return out

# ---------------------------------------------------------------- unrest (section 6.4)
## {value 0..100, stage ("calm"|"grumbling"|"slowdown"|"protest"|"strike"|"riot"), causes [{text, delta}],
##  demand ("" or text)} for one base (-1: the whole colony). Stub: from satisfaction and attitude.
func unrest(base_id: int = -1) -> Dictionary:
	# V5 section 6.4: the stored model (sim/unrest.gd). The rolling estimate below is kept for a
	# state without v5 data (before the first update).
	if sim.get("unrest") != null:
		if base_id == -1:
			if not sim.state.get("v5", {}).get("unrest", {}).is_empty():
				return sim.unrest.info(-1)
		elif not sim.unrest.rec_of(base_id).is_empty():
			return sim.unrest.info(base_id)
	var tick: int = int(sim.state["tick"])
	var hit = _unrest_cache.get(base_id)
	if hit != null and int(hit[0]) == tick:
		return hit[1]
	var out: Dictionary = _unrest(base_id)
	_unrest_cache[base_id] = [tick, out]
	return out

## Command "egg" {kind: "dance", agent}: the person dances for 20 s (V5 section 4.5).
func cmd_egg(p: Dictionary) -> Dictionary:
	var kind: String = String(p.get("kind", ""))
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	if kind != "dance":
		return {"ok": false, "code": "invalid", "text": "Unknown."}
	if a.is_empty() or a["state"] != "alive":
		return {"ok": false, "code": "invalid", "text": "No such person."}
	sim.people.add_mod(a, {"kind": "dance", "text": "Dancing", "comp": "comfort", "sat": 5.0, "att": 1.0, "days": 20.0 / float(sim.bal["day_length"])})
	var n: int = sim.eggs.on_dance(a) if sim.get("eggs") != null else 0
	return {"ok": true, "code": "ok", "text": "%s dances%s." % [_first(a), (" and %d friends join in" % n) if n > 0 else ""], "joined": n}

func _unrest(base_id: int) -> Dictionary:
	var sat := 0.0
	var att := 0.0
	var n := 0
	var mem: Dictionary = _unrest_mem.get(base_id, {})
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	var slice: int = maxi(1, ids.size() / int(sim.bal["tick_hz"]) + 1)
	var cur: int = int(_unrest_cur.get(base_id, 0))
	var seen := {}
	for i in ids.size():
		var aid: int = int(ids[i])
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or sim.people.identity(a)["kind"] != "colonist":
			continue
		if base_id != -1 and sim.bases.count() > 0 and sim.bases.home_of(a) != base_id:
			continue
		var turn: bool = posmod(i - cur, ids.size()) < slice
		if turn or not mem.has(aid):
			mem[aid] = [float(sim.people.satisfaction_soon(a)["value"]), float(sim.people.attitude_soon(a)["value"])]
		seen[aid] = true
		sat += float(mem[aid][0])
		att += float(mem[aid][1])
		n += 1
	for k in mem.keys():
		if not seen.has(k):
			mem.erase(k)
	_unrest_mem[base_id] = mem
	_unrest_cur[base_id] = (cur + slice) % maxi(1, ids.size())
	if n == 0:
		return {"value": 0.0, "stage": "calm", "causes": [], "demand": ""}
	sat /= n
	att /= n
	var v: float = clampf((60.0 - sat) * 1.5 + maxf(0.0, -att) * 0.5, 0.0, 100.0)
	var causes: Array = []
	if sat < 60.0:
		causes.append({"text": "Low satisfaction (%d)" % int(sat), "delta": snappedf((60.0 - sat) * 1.5, 0.1)})
	if att < 0.0:
		causes.append({"text": "Bad attitudes", "delta": snappedf(-att * 0.5, 0.1)})
	var stage := "calm"
	for s in [["grumbling", 25.0], ["slowdown", 40.0], ["protest", 55.0], ["strike", 70.0], ["riot", 85.0]]:
		if v >= float(s[1]):
			stage = s[0]
	var demand := ""
	if stage == "protest" or stage == "strike" or stage == "riot":
		demand = "Better food and more rest!"
	return {"value": snappedf(v, 0.1), "stage": stage, "causes": causes, "demand": demand}
