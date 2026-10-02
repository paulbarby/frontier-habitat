extends RefCounted
## Encounters, conversations and relationships (docs/V5_DESIGN.md sections 4.1 and 4.2).
## Numbers: content/society.json "social".
##
## Stored (schema 6) in state.v5:
##   talks {pair key: {a, b, start, lines, topic, bld, w}}   the conversations going on now
##   done  {pair key: window}                                 a pair talks once per talk window
##   rel   {pair key: {a, b, aff, att, status, since, last, talks, met}}
##   rel_rev                                                  +1 when a status changes
##   requests {id: {kind, agent, other, ship, tick, text}}    questions for the player
## The pair key is lo * 2^32 + hi (the two agent ids). A pair gets an entry when they first talk
## (the graph is sparse). Every tick, a tenth of the people (by id) may start a talk with someone
## who stands near them in the same room; the talk changes their affinity and attraction by
## topic, traits and department. Once a day each relationship moves on: dating, partners,
## marriage, break-up, affairs found out, visitor flings and requests to leave with a ship.

var sim
var _index_rev := -1
var _index := {}              # agent id -> [pair keys] (derived from state.v5.rel)
var _index_n := -1
var _by_phase := {}           # tick of the day -> [pair keys] (derived, with _index)
var _index_state = null       # the state.v5.rel the index was made from

func _init(s) -> void:
	sim = s

func reset() -> void:
	_index_rev = -1
	_index = {}
	_index_n = -1
	_by_phase = {}
	_index_state = null

func cfg() -> Dictionary:
	return sim.content["society"]["social"]

func _h(x: int, y: int) -> float:
	return sim.social._h(x, y)

static func key_of(x: int, y: int) -> int:
	return mini(x, y) * 4294967296 + maxi(x, y)

func v5r() -> Dictionary:
	return sim.state.get("v5", {})

func _w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	for k in ["talks", "done", "rel", "requests"]:
		if not v.has(k):
			v[k] = {}
	if not v.has("rel_rev"):
		v["rel_rev"] = 0
	return v

func _day_ticks() -> int:
	return int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))

func can_talk(a: Dictionary) -> bool:
	return a["state"] == "alive" and a["where"] == "in" and not bool(a.get("sleeping", false)) and String(a.get("plan_kind", "")) != "safety" and not a.has("lift")

func social_room(bld: int) -> bool:
	var b: Dictionary = sim.state["buildings"].get(bld, {})
	if b.is_empty():
		return false
	var cat: String = String(sim.bdef(b["def"]).get("category", ""))
	return cat == "comfort" or String(b["def"]) == "kitchen" or String(b["def"]) == "super_dome"

# ---------------------------------------------------------------- the tick
func tick() -> void:
	var now: int = int(sim.state["tick"])
	var hz: int = int(sim.bal["tick_hz"])
	var c: Dictionary = cfg()
	var agents: Dictionary = sim.state["agents"]
	var v: Dictionary = _w()
	var talks: Dictionary = v["talks"]
	if now % hz == 5 and not v["requests"].is_empty():
		close_ship_requests(-1)
	var line_ticks: int = int(sim.social.LINE_TICKS)
	# 1. Talks end when their lines are said, or when the two part.
	var busy := {}
	var ended: Array = []
	for key in talks:
		var t: Dictionary = talks[key]
		var age: int = now - int(t["start"])
		# The lines are over: it ends. Whether the two parted is checked once a second of the
		# talk (cost: not every talk every tick).
		if age / line_ticks >= int(t["lines"]):
			ended.append(key)
			continue
		if age % hz == 0:
			var x: Dictionary = agents.get(int(t["a"]), {})
			var y: Dictionary = agents.get(int(t["b"]), {})
			if x.is_empty() or y.is_empty() or not can_talk(x) or not can_talk(y) or int(x["bld"]) != int(t["bld"]) or int(y["bld"]) != int(t["bld"]) or (x["pos"] as Vector2).distance_to(y["pos"]) > float(c["keep_m"]):
				ended.append(key)
				continue
		busy[int(t["a"])] = true
		busy[int(t["b"])] = true
	for key in ended:
		talks.erase(key)
	# 2. A tenth of the people (their turn by id) may start a talk with a room-mate. (Cost: the
	# rooms of this tick's slice are collected first; only people in those rooms are checked.)
	var slice: Array = []
	var rooms := {}
	# New talks are looked for on every second tick, for two buckets of people at once (each
	# person still once a second; cost: the room scan below runs half as often).
	if now % 2 == 1:
		_day_pass(now)
		return
	# (now + id) % hz == 0  <=>  id % hz == -now mod hz (people.ids_mod keeps the buckets).
	for aid in sim.people.ids_mod(hz, -now) + sim.people.ids_mod(hz, -now - 1):
		if busy.has(int(aid)):
			continue
		var a0: Dictionary = agents[aid]
		if can_talk(a0):
			slice.append(a0)
			rooms[int(a0["bld"])] = true
	if slice.is_empty():
		_day_pass(now)
		return
	var by_bld := {}
	for aid in agents:
		var a: Dictionary = agents[aid]
		var b: int = int(a["bld"])
		if not rooms.has(b) or not can_talk(a):
			continue
		if not by_bld.has(b):
			by_bld[b] = []
		by_bld[b].append(a)
	slice.sort_custom(func(p, q): return int(p["id"]) < int(q["id"]))
	for b in by_bld:
		(by_bld[b] as Array).sort_custom(func(p, q): return int(p["id"]) < int(q["id"]))
	var window: int = int(c["talk_window_s"]) * hz
	var w: int = now / window
	var done: Dictionary = v["done"]
	for x in slice:
		if busy.has(int(x["id"])):
			continue
		var room: Array = by_bld[int(x["bld"])]
		if room.size() < 2:
			continue
		var chance: float = float(c["talk_chance_social"]) if social_room(int(x["bld"])) else float(c["talk_chance"])
		for y in room:
			if int(y["id"]) == int(x["id"]) or busy.has(int(y["id"])) or (x["pos"] as Vector2).distance_to(y["pos"]) > float(c["near_m"]):
				continue
			var key: int = key_of(int(x["id"]), int(y["id"]))
			if int(done.get(key, -1)) == w or _h(key % 2147483647, w) >= chance:
				continue
			done[key] = w
			busy[int(x["id"])] = true
			busy[int(y["id"])] = true
			var topic: String = sim.social.topic_for(x, y, (key + w) % 2147483647)
			talks[key] = {"a": int(x["id"]), "b": int(y["id"]), "start": now, "lines": 2 + int(_h(key % 2147483647, w + 7) * 5.0) % 5,
				"topic": topic, "bld": int(x["bld"]), "w": w}
			_talked(x, y, topic, now)
			break
	# The window marks of old windows are dropped (once a window).
	if now % window == 0:
		var keep := {}
		for k in done:
			if int(done[k]) >= w - 1:
				keep[k] = done[k]
		v["done"] = keep
	_day_pass(now)

# ---------------------------------------------------------------- relationships
## The stored pair (read only; {} for strangers who never talked).
func rel_of(x: int, y: int) -> Dictionary:
	return v5r().get("rel", {}).get(key_of(x, y), {})

func _rel_w(x: Dictionary, y: Dictionary) -> Dictionary:
	var rel: Dictionary = _w()["rel"]
	var key: int = key_of(int(x["id"]), int(y["id"]))
	if not rel.has(key):
		rel[key] = {"a": mini(int(x["id"]), int(y["id"])), "b": maxi(int(x["id"]), int(y["id"])), "aff": 0.0, "att": 0.0, "status": "stranger",
			"since": int(sim.state["tick"]), "last": int(sim.state["tick"]), "talks": 0}
		_added(key, rel[key])
	return rel[key]

## After a direct write of state.v5.rel (tests, set-ups, a new game's families): the index is made again.
func _bump() -> void:
	var v: Dictionary = _w()
	v["rel_rev"] = int(v["rel_rev"]) + 1
	_index_rev = -1

## A status changed (the set of pairs did not): the index stays.
func _status_changed() -> void:
	var v: Dictionary = _w()
	v["rel_rev"] = int(v["rel_rev"]) + 1

## A new pair: added to the index in key order (the order a rebuild gives), without a rebuild.
func _added(key: int, r: Dictionary) -> void:
	var v: Dictionary = _w()
	v["rel_rev"] = int(v["rel_rev"]) + 1
	if _index_rev == -1 or not is_same(_index_state, v["rel"]):
		return
	_index_n += 1
	var ph: int = int(key % _day_ticks())
	if not _by_phase.has(ph):
		_by_phase[ph] = []
	var bp: Array = _by_phase[ph]
	bp.insert(bp.bsearch(key), key)
	for pid in [int(r["a"]), int(r["b"])]:
		if not _index.has(pid):
			_index[pid] = []
		var ix: Array = _index[pid]
		ix.insert(ix.bsearch(key), key)

func _talked(x: Dictionary, y: Dictionary, topic: String, now: int) -> void:
	var c: Dictionary = cfg()
	var tc: Dictionary = c["talk"]
	var r: Dictionary = _rel_w(x, y)
	var tx: Array = sim.people.identity(x)["traits"]
	var ty: Array = sim.people.identity(y)["traits"]
	var d: float = float(tc["affinity"])
	for t in tx:
		if ty.has(t):
			d += float(tc["shared_trait"])
	for pair in sim.content["people"]["trait_conflicts"]:
		if (tx.has(pair[0]) and ty.has(pair[1])) or (tx.has(pair[1]) and ty.has(pair[0])):
			d += float(tc["conflict_trait"])
	var dx: String = sim.people.department(x)
	if dx != "" and dx == sim.people.department(y):
		d += float(tc["same_department"])
	if (tc["argue_topics"] as Array).has(topic) and (tx.has("hot-headed") or ty.has("hot-headed") or float(r["aff"]) < 0.0):
		d = float(tc["argue_affinity"])
	if topic == "gossip":
		d += float(tc["gossip_affinity"])
	r["aff"] = clampf(float(r["aff"]) + d, -100.0, 100.0)
	if sim.social.compatible(x, y):
		var da: float = float(tc["attraction_drift"]) * (1.0 + (float(tc["charming"]) if ty.has("charming") or tx.has("charming") else 0.0))
		if topic == "romance":
			da += float(tc["romance_attraction"])
		# Attraction grows toward a ceiling set by the pair (not everybody falls for everybody).
		var ceiling: float = 40.0 + 60.0 * _h(int(r["a"]) * 7 + 3, int(r["b"]))
		r["att"] = clampf(minf(float(r["att"]) + da, maxf(float(r["att"]), ceiling)), 0.0, 100.0)
	r["last"] = now
	r["talks"] = int(r["talks"]) + 1
	_update_status(r, x, y, topic)

const ROMANTIC := ["dating", "partners", "married", "affair", "fling"]

## A person's partner (dating, partners or married; -1: none), from the stored pairs.
func partner_of(id: int) -> int:
	var keys: Array = _keys_of(id)
	if keys.is_empty():
		return -1
	var rel: Dictionary = v5r()["rel"]
	for key in keys:
		var r: Dictionary = rel[key]
		var st: String = r["status"]
		if st == "dating" or st == "partners" or st == "married":
			return int(r["b"]) if int(r["a"]) == id else int(r["a"])
	return -1

func _update_status(r: Dictionary, x: Dictionary, y: Dictionary, topic: String) -> void:
	var sc: Dictionary = cfg()["status"]
	var st: String = String(r["status"])
	var old: String = st
	var aff: float = float(r["aff"])
	var att: float = float(r["att"])
	if ROMANTIC.has(st):
		pass
	elif topic == "romance" and att >= float(sc["dating_att"]) and aff >= float(sc["dating_aff"]):
		var px: int = partner_of(int(x["id"]))
		var py: int = partner_of(int(y["id"]))
		var visitor: bool = String(x.get("kind", "")) == "visitor" or String(y.get("kind", "")) == "visitor"
		if visitor:
			st = "fling"
		elif px == -1 and py == -1:
			st = "dating"
		else:
			st = "affair"
	elif st == "ex":
		pass
	else:
		st = "stranger"
		if aff >= float(sc["best_friend"]):
			st = "best_friend"
		elif aff >= float(sc["friend"]):
			st = "friend"
		elif aff >= float(sc["acquaintance"]):
			st = "acquaintance"
		elif aff <= float(sc["enemy"]):
			st = "enemy"
		elif aff <= float(sc["rival"]):
			st = "rival"
		if att >= float(sc["crush"]) and aff >= 0.0:
			st = "crush"
	if st != old:
		r["status"] = st
		r["since"] = int(sim.state["tick"])
		_status_changed()
		match st:
			"dating":
				sim.log_event("couple", "%s and %s are dating." % [String(x["name"]), String(y["name"])], [int(x["id"]), int(y["id"])], 1, {"place": int(x["bld"])})
			"fling":
				sim.log_event("fling", "%s has a fling with a visitor, %s." % [_colonist_name(x, y), _visitor_name(x, y)], [int(x["id"]), int(y["id"])], 1, {"place": int(x["bld"])})
			"enemy":
				sim.log_event("feud", "%s and %s cannot stand each other." % [String(x["name"]), String(y["name"])], [int(x["id"]), int(y["id"])], 0)

func _colonist_name(x: Dictionary, y: Dictionary) -> String:
	return String(y["name"]) if String(x.get("kind", "")) == "visitor" else String(x["name"])

func _visitor_name(x: Dictionary, y: Dictionary) -> String:
	return String(x["name"]) if String(x.get("kind", "")) == "visitor" else String(y["name"])

# ---------------------------------------------------------------- once a day
## Each relationship moves on once a game day, on its own tick (pair key), so the work is spread.
func _day_pass(now: int) -> void:
	var rel: Dictionary = v5r().get("rel", {})
	if rel.is_empty():
		return
	var day: int = _day_ticks()
	var phase: int = now % day
	var sc: Dictionary = cfg()["status"]
	_keys_of(-1)
	var keys: Array = _by_phase.get(phase, []).duplicate()
	for key in keys:
		if not rel.has(key):
			continue
		var r: Dictionary = rel[key]
		var x: Dictionary = sim.state["agents"].get(int(r["a"]), {})
		var y: Dictionary = sim.state["agents"].get(int(r["b"]), {})
		if x.is_empty() or y.is_empty() or x["state"] != "alive" or y["state"] != "alive":
			rel.erase(key)
			_bump()
			continue
		var st: String = String(r["status"])
		var days: float = float(now - int(r["since"])) / float(day)
		# Old friendships fade when the two do not meet.
		if float(now - int(r["last"])) / float(day) > 3.0 and not ROMANTIC.has(st):
			r["aff"] = move_toward(float(r["aff"]), 0.0, float(cfg()["decay_per_day"]))
		match st:
			"dating":
				if float(r["aff"]) < float(sc["breakup_aff"]):
					_break_up(r, x, y, "")
				elif days >= float(sc["partners_days"]) and float(r["aff"]) >= float(sc["partners_aff"]):
					_set_status(r, "partners")
					sim.log_event("partners", "%s and %s are now partners." % [String(x["name"]), String(y["name"])], [int(x["id"]), int(y["id"])], 1)
					# V5 section 4.2: partners move in together (families.gd).
					if sim.get("families") != null:
						sim.families.on_partners(x, y)
			"partners":
				if float(r["aff"]) < float(sc["breakup_aff"]):
					_break_up(r, x, y, "")
				elif days >= float(sc["married_days"]) and _h(int(key % 2147483647), now / day) < float(sc["wedding_chance"]):
					_set_status(r, "married")
					sim.log_event("wedding", "%s and %s got married!" % [String(x["name"]), String(y["name"])], [int(x["id"]), int(y["id"])], 1)
					for aid in sim.state["agents"]:
						var p: Dictionary = sim.state["agents"][aid]
						if p["state"] == "alive" and String(p.get("kind", "")) != "visitor":
							sim.people.add_mod(p, {"kind": "wedding", "text": "A wedding in the colony", "comp": "social", "sat": 5.0, "att": 1.0, "days": 1.0})
			"married":
				if float(r["aff"]) < float(sc["breakup_aff"]) - 20.0:
					_break_up(r, x, y, "")
			"affair":
				_affair_day(key, r, x, y, now)
			"fling":
				_fling_day(key, r, x, y, now)

func _set_status(r: Dictionary, st: String) -> void:
	r["status"] = st
	r["since"] = int(sim.state["tick"])
	_status_changed()

func _break_up(r: Dictionary, x: Dictionary, y: Dictionary, why: String) -> void:
	_set_status(r, "ex")
	r["aff"] = minf(float(r["aff"]), -10.0)
	for p in [x, y]:
		sim.people.add_mod(p, {"kind": "breakup", "text": "A break-up", "comp": "social", "sat": -15.0, "att": -5.0, "days": 2.0})
		sim.people.note(p, "Broke up with %s." % String((y if p == x else x)["name"]))
	sim.log_event("breakup", "%s and %s broke up%s." % [String(x["name"]), String(y["name"]), (": " + why) if why != "" else ""], [int(x["id"]), int(y["id"])], 1)

## An affair is found out with a chance a day (more with gossips in the base). The cheated partner
## breaks up with the cheat; the scandal is in the log (and the Rag).
func _affair_day(key: int, r: Dictionary, x: Dictionary, y: Dictionary, now: int) -> void:
	var c: Dictionary = cfg()
	var gossips := 0
	for aid in sim.state["agents"]:
		var p: Dictionary = sim.state["agents"][aid]
		if p["state"] == "alive" and sim.people.has_trait(p, "gossip"):
			gossips += 1
	var chance: float = float(c["discover_chance"]) + float(c["discover_per_gossip"]) * gossips
	if _h(int(key % 2147483647) + 11, now / _day_ticks()) >= chance:
		return
	var cheat: Dictionary = x if partner_of(int(x["id"])) != -1 else y
	var other: Dictionary = y if cheat == x else x
	var pid: int = partner_of(int(cheat["id"]))
	var partner: Dictionary = sim.state["agents"].get(pid, {})
	sim.log_event("affair", "Scandal! %s was seen with %s." % [String(cheat["name"]), String(other["name"])], [int(cheat["id"]), int(other["id"])] + ([pid] if pid != -1 else []), 2)
	if not partner.is_empty():
		var pr: Dictionary = _rel_w(cheat, partner)
		pr["aff"] = clampf(float(pr["aff"]) - 40.0, -100.0, 100.0)
		_break_up(pr, cheat, partner, "an affair")
		var jr: Dictionary = _rel_w(other, partner)
		jr["aff"] = clampf(float(jr["aff"]) - 30.0, -100.0, 100.0)
		_update_status(jr, other, partner, "")
	_set_status(r, "dating")

## A fling with a visitor: when the visitor's ship is about to leave and the attraction is strong,
## the colonist asks to leave with it (a request for the player); else it ends when the visitor goes.
func _fling_day(key: int, r: Dictionary, x: Dictionary, y: Dictionary, now: int) -> void:
	var vis: Dictionary = x if String(x.get("kind", "")) == "visitor" else y
	var col: Dictionary = y if vis == x else x
	if String(col.get("kind", "")) == "visitor":
		return
	var reqs: Dictionary = _w()["requests"]
	for rid in reqs:
		if int(reqs[rid]["agent"]) == int(col["id"]):
			return
	if float(r["att"]) >= float(cfg()["defect_att"]) and _h(int(key % 2147483647) + 23, now / _day_ticks()) < float(cfg()["defect_chance"]):
		var rid2: int = int(_w().get("req_seq", 0)) + 1
		_w()["req_seq"] = rid2
		reqs[rid2] = {"id": rid2, "kind": "leave_with_ship", "agent": int(col["id"]), "other": int(vis["id"]), "ship": int(vis.get("ship", -1)), "tick": now,
			"text": "%s wants to leave with %s on the ship. Let them go?" % [String(col["name"]), String(vis["name"])]}
		sim.log_event("defect_request", "%s asks to leave the colony with %s." % [String(col["name"]), String(vis["name"])], [int(col["id"]), int(vis["id"])], 2, {"request": rid2})

## A question for the player (requests()): kind "leave_with_ship" or "shared_home". One open request
## of a kind per person.
func add_request(kind: String, x: Dictionary, y: Dictionary, text: String) -> int:
	var reqs: Dictionary = _w()["requests"]
	for rid in reqs:
		if String(reqs[rid]["kind"]) == kind and int(reqs[rid]["agent"]) == int(x["id"]):
			return int(rid)
	var rid2: int = int(_w().get("req_seq", 0)) + 1
	_w()["req_seq"] = rid2
	reqs[rid2] = {"id": rid2, "kind": kind, "agent": int(x["id"]), "other": int(y["id"]), "ship": -1, "tick": int(sim.state["tick"]), "text": text}
	sim.log_event("request_" + kind, text, [int(x["id"]), int(y["id"])], 1, {"request": rid2})
	return rid2

## A leave_with_ship request ends when its ship takes off (UI-to-SIM 2026-10-01): the colonist stays,
## the visitor leaves alone. One log line (code defect_ended) and a short low mood; the request is removed.
## ship_id -1 closes every request whose ship is no longer on the ground (old saves) or whose
## colonist is dead or already a visitor.
func close_ship_requests(ship_id: int = -1) -> int:
	var reqs: Dictionary = v5r().get("requests", {})
	if reqs.is_empty():
		return 0
	var closed := 0
	for rid in reqs.keys():
		var q: Dictionary = reqs[rid]
		if String(q["kind"]) != "leave_with_ship":
			continue
		var a: Dictionary = sim.state["agents"].get(int(q["agent"]), {})
		var sid: int = int(q.get("ship", -1))
		var gone := false
		if ship_id != -1:
			gone = sid == ship_id
		else:
			var arr: Dictionary = sim.traffic.ship(sid)
			gone = arr.is_empty() or String(arr["phase"]) == "takeoff"
		var void_req: bool = a.is_empty() or a["state"] != "alive" or String(a.get("kind", "")) == "visitor"
		if not gone and not void_req:
			continue
		reqs.erase(rid)
		closed += 1
		if void_req:
			continue
		var o: Dictionary = sim.state["agents"].get(int(q["other"]), {})
		var on: String = String(o.get("name", "the visitor"))
		sim.people.add_mod(a, {"kind": "ship_gone", "text": "Watched a loved one's ship leave", "comp": "social", "sat": -5.0, "att": -2.0, "days": 2.0})
		sim.people.note(a, "Stayed when %s's ship left." % on)
		sim.log_event("defect_ended", "%s stays. %s's ship has gone without an answer." % [String(a["name"]), on], [int(a["id"])] + ([int(o["id"])] if not o.is_empty() else []), 1, {"request": int(rid)})
	return closed

## Command "answer_request" {id, answer: "allow" | "refuse"}. shared_home: "allow" tries again to
## house the pair (a home may exist now); "refuse" leaves them apart (both unhappy).
func cmd_answer_request(p: Dictionary) -> Dictionary:
	var reqs: Dictionary = _w()["requests"]
	var rid: int = int(p.get("id", -1))
	if not reqs.has(rid):
		return {"ok": false, "code": "invalid", "text": "No such request."}
	var q: Dictionary = reqs[rid]
	var a: Dictionary = sim.state["agents"].get(int(q["agent"]), {})
	var ans: String = String(p.get("answer", ""))
	if ans != "allow" and ans != "refuse":
		return {"ok": false, "code": "invalid", "text": "Answer allow or refuse."}
	reqs.erase(rid)
	if a.is_empty() or a["state"] != "alive":
		return {"ok": true, "code": "ok", "text": "The request no longer applies."}
	if String(q["kind"]) == "shared_home":
		var o: Dictionary = sim.state["agents"].get(int(q["other"]), {})
		if o.is_empty() or o["state"] != "alive":
			return {"ok": true, "code": "ok", "text": "The request no longer applies."}
		if ans == "allow":
			sim.families.on_partners(a, o)
			var together: bool = int(a["bed"]) == int(o["bed"]) and int(sim.people.rec_of(int(a["id"])).get("unit", -2)) == int(sim.people.rec_of(int(o["id"])).get("unit", -3))
			return {"ok": together, "code": "ok" if together else "full", "text": "They moved in together." if together else "There is still no free home for two."}
		for x in [a, o]:
			sim.people.add_mod(x, {"kind": "apart", "text": "Not allowed a shared home", "comp": "housing", "sat": -10.0, "att": -5.0, "days": 3.0})
		return {"ok": true, "code": "ok", "text": "They stay apart. They are not happy."}
	if ans == "allow":
		var ship: int = int(q["ship"])
		var arr: Dictionary = sim.traffic.ship(ship)
		if arr.is_empty():
			return {"ok": false, "code": "refused", "text": "The ship has gone."}
		# The colonist becomes a passenger of that ship and leaves with it.
		a["kind"] = "visitor"
		a["ship"] = ship
		a.erase("order")
		sim.people.note(a, "Left the colony with a visitor.")
		sim.log_event("defected", "%s left the colony for love." % String(a["name"]), [int(a["id"])], 2)
		sim.people.invalidate(int(a["id"]))
		sim.people.ranks_dirty()
		return {"ok": true, "code": "ok", "text": "%s will leave with the ship." % String(a["name"])}
	sim.people.add_mod(a, {"kind": "refused_leave", "text": "Not allowed to leave", "comp": "freedom", "sat": -20.0, "att": -15.0, "days": 3.0})
	sim.people.note(a, "Was not allowed to leave with the ship.")
	return {"ok": true, "code": "ok", "text": "%s stays. They are not happy." % String(a["name"])}

## Open requests for the player: [{id, kind, agent, other, ship, tick, text}] (oldest first).
func requests() -> Array:
	var out: Array = []
	var reqs: Dictionary = v5r().get("requests", {})
	var ids: Array = reqs.keys()
	ids.sort()
	for rid in ids:
		out.append(reqs[rid].duplicate())
	return out

# ---------------------------------------------------------------- queries
func _keys_of(id: int) -> Array:
	var v: Dictionary = v5r()
	var rel: Dictionary = v.get("rel", {})
	if _index_rev == -1 or rel.size() != _index_n or not is_same(_index_state, rel):
		_index_rev = 0
		_index_state = rel
		_index_n = rel.size()
		_index = {}
		_by_phase = {}
		var day: int = _day_ticks()
		var keys: Array = rel.keys()
		keys.sort()
		for k in keys:
			var r: Dictionary = rel[k]
			var ph: int = int(k % day)
			if not _by_phase.has(ph):
				_by_phase[ph] = []
			_by_phase[ph].append(k)
			for pid in [int(r["a"]), int(r["b"])]:
				if not _index.has(pid):
					_index[pid] = []
				_index[pid].append(k)
	return _index.get(id, [])

## A pair's relationship as the other person sees it: {other, affinity, attraction, status, known, since,
## talks}. Strangers: status "stranger", known false.
func relation(a: Dictionary, b: Dictionary) -> Dictionary:
	var r: Dictionary = rel_of(int(a["id"]), int(b["id"]))
	if r.is_empty():
		return {"other": int(b["id"]), "affinity": 0.0, "attraction": 0.0, "status": "stranger", "known": false, "since": -1, "talks": 0}
	var st: String = String(r["status"])
	return {"other": int(b["id"]), "affinity": snappedf(float(r["aff"]), 0.1), "attraction": snappedf(float(r["att"]), 0.1), "status": st,
		"known": st != "crush" and st != "affair", "since": int(r["since"]), "talks": int(r["talks"])}

## The people a person knows (strangers left out), strongest first (at most n).
func relationships_of(agent_id: int, n: int = 8) -> Array:
	var a: Dictionary = sim.state["agents"].get(agent_id, {})
	if a.is_empty():
		return []
	var out: Array = []
	for key in _keys_of(agent_id):
		var r: Dictionary = v5r()["rel"][key]
		var oid: int = int(r["b"]) if int(r["a"]) == agent_id else int(r["a"])
		var b: Dictionary = sim.state["agents"].get(oid, {})
		if b.is_empty() or b["state"] != "alive" or String(r["status"]) == "stranger":
			continue
		out.append(relation(a, b))
	out.sort_custom(func(x, y):
		var vx: float = absf(float(x["affinity"])) + float(x["attraction"]) + (100.0 if ROMANTIC.has(String(x["status"])) else 0.0)
		var vy: float = absf(float(y["affinity"])) + float(y["attraction"]) + (100.0 if ROMANTIC.has(String(y["status"])) else 0.0)
		return vx > vy if vx != vy else int(x["other"]) < int(y["other"]))
	return out.slice(0, n)

## {friends, best_friends, partner (id or -1), enemies, ex_recent (bool)} for satisfaction.
func summary(id: int) -> Dictionary:
	var fr := 0
	var bf := 0
	var en := 0
	var partner := -1
	var keys: Array = _keys_of(id)
	if not keys.is_empty():
		var rel: Dictionary = v5r()["rel"]
		for key in keys:
			var r: Dictionary = rel[key]
			var st: String = r["status"]
			if st == "friend":
				fr += 1
			elif st == "best_friend":
				bf += 1
			elif st == "enemy" or st == "rival":
				en += 1
			elif st == "dating" or st == "partners" or st == "married":
				partner = int(r["b"]) if int(r["a"]) == id else int(r["a"])
	return {"friends": fr, "best_friends": bf, "partner": partner, "enemies": en}

## The pairs with a status, for the Rag's Couple Watch and Feud Watch: [{a, b, status, aff, att}].
func pairs_with(statuses: Array) -> Array:
	var out: Array = []
	var rel: Dictionary = v5r().get("rel", {})
	var keys: Array = rel.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = rel[k]
		if statuses.has(String(r["status"])):
			out.append({"a": int(r["a"]), "b": int(r["b"]), "status": String(r["status"]), "aff": float(r["aff"]), "att": float(r["att"])})
	return out
