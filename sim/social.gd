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
var _scan_sec := -1           # the tick of the last search for new pairs
var _sessions := {}           # pair key -> {a, b, w, start, lines, topic, bld, said {line index: line}}
var _done := {}               # pair key -> the window of its last talk (one talk per window)
var _rel_cache := {}          # agent id -> [game minute, n, list]
var _rag_cache := {}          # issue number -> issue (a finished day does not change)
var _unrest_cache := {}       # base id -> [game second, record]
var _iw_sec := -1
var _pairs_sig := -1          # roster signature of the Rag's couple and feud candidates
var _pairs: Array = []
var _feud_pair: Array = []
var _unrest_mem := {}         # base id -> {agent id: [satisfaction, attitude]}
var _unrest_cur := {}         # base id -> index of the next slice
var _iw := {}

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
	_scan_sec = -1
	_sessions = {}
	_done = {}
	_rel_cache = {}
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
func _can_talk(a: Dictionary) -> bool:
	return a["state"] == "alive" and a["where"] == "in" and not bool(a.get("sleeping", false)) and String(a.get("plan_kind", "")) != "safety"

func _social_room(bld: int) -> bool:
	var b: Dictionary = sim.state["buildings"].get(bld, {})
	if b.is_empty():
		return false
	var cat: String = String(sim.bdef(b["def"]).get("category", ""))
	return cat == "comfort" or String(b["def"]) == "kitchen"

## Every talk going on now: [{id, a, b (agent ids), speaker, listener, topic, line, emote, anim,
##  started (tick), line_index, lines, building, pos (Vector2, between the two)}].
func talks() -> Array:
	var tick: int = int(sim.state["tick"])
	if tick == _talk_tick:
		return _talks
	_talk_tick = tick
	var agents: Dictionary = sim.state["agents"]
	# Each room is searched for new pairs once a game second, on its own tick of the second
	# ((room id + tick) % tick_hz == 0), so the search is spread over the ticks. A call that
	# skips ticks searches the rooms of the skipped ticks too (at most one second of them).
	var hz: int = int(sim.bal["tick_hz"])
	if _scan_sec == -1 or tick - _scan_sec >= hz or tick < _scan_sec:
		_scan(tick, -1)
	else:
		for t in range(_scan_sec + 1, tick + 1):
			_scan(t, t % hz)
	_scan_sec = tick
	_talks = []
	var gone: Array = []
	var keys: Array = _sessions.keys()
	keys.sort()
	for key in keys:
		var s: Dictionary = _sessions[key]
		var x: Dictionary = agents.get(int(s["a"]), {})
		var y: Dictionary = agents.get(int(s["b"]), {})
		var li: int = (tick - int(s["start"])) / LINE_TICKS
		if x.is_empty() or y.is_empty() or li >= int(s["lines"]) or not _can_talk(x) or not _can_talk(y) or int(x["bld"]) != int(s["bld"]) or int(y["bld"]) != int(s["bld"]):
			gone.append(key)
			continue
		var speaker: Dictionary = x if li % 2 == 0 else y
		var listener: Dictionary = y if li % 2 == 0 else x
		var said: Dictionary = s["said"]
		if not said.has(li):
			var ln: Dictionary = line_for(speaker, listener, String(s["topic"]), int(key) * 31 + int(s["w"]) * 7 + li, int(s["bld"]))
			said[li] = ln
			_remember(int(speaker["id"]), int(s["start"]) + li * LINE_TICKS, ln, String(s["topic"]), int(listener["id"]))
		var line: Dictionary = said[li]
		_talks.append({"id": int(key) * 1000 + int(s["w"]) % 1000, "a": int(s["a"]), "b": int(s["b"]), "speaker": int(speaker["id"]), "listener": int(listener["id"]),
			"topic": s["topic"], "line": line["text"], "emote": line["emote"], "anim": line["anim"], "started": int(s["start"]), "line_index": li, "lines": int(s["lines"]),
			"building": int(s["bld"]), "pos": ((x["pos"] as Vector2) + (y["pos"] as Vector2)) * 0.5})
	for key in gone:
		_sessions.erase(key)
	return _talks

## Pairs of free people who stand together may start a talk. phase -1: every room; else only the
## rooms with (id + phase) % tick_hz == 0.
func _scan(tick: int, phase: int) -> void:
	var hz: int = int(sim.bal["tick_hz"])
	var agents: Dictionary = sim.state["agents"]
	var busy := {}
	for key in _sessions:
		var s: Dictionary = _sessions[key]
		var x: Dictionary = agents.get(int(s["a"]), {})
		var y: Dictionary = agents.get(int(s["b"]), {})
		if x.is_empty() or y.is_empty() or (x["pos"] as Vector2).distance_to(y["pos"]) > KEEP:
			s["lines"] = 0      # ends on the next build of the list
			continue
		busy[int(s["a"])] = true
		busy[int(s["b"])] = true
	var by_bld := {}
	var ids: Array = agents.keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = agents[aid]
		var b: int = int(a["bld"])
		if (phase != -1 and posmod(b + phase, hz) != 0) or busy.has(int(aid)) or not _can_talk(a):
			continue
		if not by_bld.has(b):
			by_bld[b] = []
		by_bld[b].append(a)
	var w: int = tick / TALK_WINDOW
	var bids: Array = by_bld.keys()
	bids.sort()
	for b in bids:
		var list: Array = by_bld[b]
		if list.size() < 2:
			continue
		var chance: float = TALK_CHANCE_SOCIAL if _social_room(b) else TALK_CHANCE
		for i in list.size():
			var x: Dictionary = list[i]
			if busy.has(int(x["id"])):
				continue
			for j in range(i + 1, list.size()):
				var y: Dictionary = list[j]
				if busy.has(int(y["id"])) or (x["pos"] as Vector2).distance_to(y["pos"]) > NEAR:
					continue
				var key: int = int(x["id"]) * 100003 + int(y["id"])
				if int(_done.get(key, -1)) == w or _h(key, w) >= chance:
					continue
				_done[key] = w
				busy[int(x["id"])] = true
				busy[int(y["id"])] = true
				_sessions[key] = {"a": int(x["id"]), "b": int(y["id"]), "w": w, "start": tick, "lines": 2 + int(_h(key, w + 7) * 5.0) % 5,
					"topic": topic_for(x, y, key + w), "bld": b, "said": {}}
				break
	# The window marks of old windows are dropped.
	if _done.size() > 4000:
		var keep := {}
		for k in _done:
			if int(_done[k]) >= w - 1:
				keep[k] = _done[k]
		_done = keep

func _remember(sid: int, at: int, line: Dictionary, topic: String, to: int) -> void:
	var arr: Array = _recent.get(sid, [])
	arr.append({"tick": at, "text": line["text"], "topic": topic, "to": to, "emote": line["emote"]})
	while arr.size() > 12:
		arr.pop_front()
	_recent[sid] = arr

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

## Kept for callers of milestone 1; the talks now move on when they are asked for.
func tick_second() -> void:
	talks()

## The topic a person talks about: a critical need first (the talk is a status channel), then
## colony problems, then work, gossip, romance, leisure and small talk (weights from state).
## Topic weights from the colony's problems (once a game second).
func _issue_weights() -> Dictionary:
	var sec: int = int(sim.state["tick"]) / int(sim.bal["tick_hz"])
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
	_iw = w
	return _iw

func topic_for(a: Dictionary, other: Dictionary, salt: int) -> String:
	var idn: Dictionary = sim.people.identity(a)
	if idn["kind"] == "child":
		return "child"
	if idn["kind"] == "visitor":
		return "visitor_says"
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
	if sim.people.has_trait(a, "hot-headed") or float(sim.people.attitude_soon(a)["value"]) < -30.0:
		w["complaint"] = 2.0
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
func line_for(a: Dictionary, other: Dictionary, topic: String, salt: int, bld: int) -> Dictionary:
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
	text = text.replace("{place}", String(here.get("name", "lounge"))).replace("{resource}", "oxygen")
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

## A pair's relationship: {other, affinity -100..100, attraction 0..100, status, known}.
func relation(a: Dictionary, b: Dictionary) -> Dictionary:
	var lo: int = mini(int(a["id"]), int(b["id"]))
	var hi: int = maxi(int(a["id"]), int(b["id"]))
	var key: int = lo * 100003 + hi
	var aff: float = _h(key, 1) * 110.0 - 40.0
	if sim.people.department(a) == sim.people.department(b) and sim.people.department(a) != "":
		aff += 15.0
	aff = clampf(aff, -100.0, 100.0)
	var att: float = 0.0
	if compatible(a, b):
		att = _h(key, 2) * 100.0
	var status := "stranger"
	if aff >= 70.0:
		status = "best_friend"
	elif aff >= 40.0:
		status = "friend"
	elif aff >= 10.0:
		status = "acquaintance"
	elif aff <= -30.0:
		status = "enemy"
	elif aff <= -15.0:
		status = "rival"
	if att >= 88.0 and aff >= 30.0:
		status = "dating"
	elif att >= 75.0 and aff >= 0.0:
		status = "crush"
	return {"other": int(b["id"]), "affinity": snappedf(aff, 0.1), "attraction": snappedf(att, 0.1), "status": status, "known": status != "crush"}

## The people a person knows (strangers left out), strongest first (at most n).
func relationships_of(agent_id: int, n: int = 8) -> Array:
	var a: Dictionary = sim.state["agents"].get(agent_id, {})
	if a.is_empty():
		return []
	var minute: int = int(sim.state["tick"]) / (60 * int(sim.bal["tick_hz"]))
	var hit = _rel_cache.get(agent_id)
	if hit != null and int(hit[0]) == minute and int(hit[1]) == n:
		return hit[2]
	var res: Array = _relationships_of(a, agent_id, n)
	_rel_cache[agent_id] = [minute, n, res]
	return res

func _relationships_of(a: Dictionary, agent_id: int, n: int) -> Array:
	var out: Array = []
	var base: int = sim.bases.home_of(a) if sim.bases.count() > 0 else -1
	for oid in sim.state["agents"]:
		var b: Dictionary = sim.state["agents"][oid]
		if int(oid) == agent_id or b["state"] != "alive":
			continue
		if sim.bases.count() > 1 and sim.bases.home_of(b) != base:
			continue
		var r: Dictionary = relation(a, b)
		if r["status"] != "stranger":
			out.append(r)
	out.sort_custom(func(x, y): return absf(float(x["affinity"])) + float(x["attraction"]) > absf(float(y["affinity"])) + float(y["attraction"]) if absf(float(x["affinity"])) + float(x["attraction"]) != absf(float(y["affinity"])) + float(y["attraction"]) else int(x["other"]) < int(y["other"]))
	return out.slice(0, n)

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
	# The couple and feud candidates change with the roster (checked once a game minute).
	sim.people._refresh_ranks()
	if _pairs_sig == int(sim.people._rank_sig):
		return {"by_day": by_day, "pairs": _pairs, "feud": _feud_pair, "approval": snappedf(approval / maxf(1.0, alive.size()), 0.1)}
	var pairs: Array = []
	for i in alive.size():
		for j in range(i + 1, mini(alive.size(), i + 12)):
			# Cheap tests first: attraction over 50 needs a compatible pair and a high hash.
			var lo: int = mini(int(alive[i]["id"]), int(alive[j]["id"]))
			var hi: int = maxi(int(alive[i]["id"]), int(alive[j]["id"]))
			if _h(lo * 100003 + hi, 2) * 100.0 <= 50.0 or not compatible(alive[i], alive[j]):
				continue
			var r: Dictionary = relation(alive[i], alive[j])
			if float(r["attraction"]) > 50.0:
				pairs.append([int(alive[i]["id"]), int(alive[j]["id"]), float(r["attraction"]) + float(r["affinity"]) * 0.3])
	_pairs_sig = int(sim.people._rank_sig)
	_pairs = pairs
	_feud_pair = _feud(0)
	return {"by_day": by_day, "pairs": pairs, "feud": _feud_pair, "approval": snappedf(approval / maxf(1.0, alive.size()), 0.1)}

func rag_issue(number: int) -> Dictionary:
	# An issue is made once: its day is over (issue n covers day n, printed at its end).
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

func _feud(_salt: int) -> Array:
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for i in ids.size():
		var a: Dictionary = sim.state["agents"][ids[i]]
		if a["state"] != "alive":
			continue
		for j in range(i + 1, mini(ids.size(), i + 10)):
			# An enemy has affinity -30 or less; the same department adds 15 to the hash part.
			var lo: int = mini(int(ids[i]), int(ids[j]))
			var hi: int = maxi(int(ids[i]), int(ids[j]))
			if _h(lo * 100003 + hi, 1) * 110.0 - 40.0 > -30.0:
				continue
			var b: Dictionary = sim.state["agents"][ids[j]]
			if b["state"] == "alive" and relation(a, b)["status"] == "enemy":
				return [{"a": int(ids[i]), "b": int(ids[j]), "status": "enemy"}]
	return []

# ---------------------------------------------------------------- unrest (section 6.4)
## {value 0..100, stage ("calm"|"grumbling"|"slowdown"|"protest"|"strike"|"riot"), causes [{text, delta}],
##  demand ("" or text)} for one base (-1: the whole colony). Stub: from satisfaction and attitude.
func unrest(base_id: int = -1) -> Dictionary:
	var tick: int = int(sim.state["tick"])
	var hit = _unrest_cache.get(base_id)
	if hit != null and int(hit[0]) == tick:
		return hit[1]
	var out: Dictionary = _unrest(base_id)
	_unrest_cache[base_id] = [tick, out]
	return out

## The mean satisfaction and attitude of a base's colonists. Each call (at most one a tick) asks
## a tenth of them again, in turn; the others keep the values of their last turn.
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
