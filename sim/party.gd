extends RefCounted
## Idle talk, innuendo, celebration events, party offers, parties and party drama
## (docs/V5_DESIGN.md section 16). Text: content/celebrations.json; numbers: content/society.json "celebrations".
##
## Stored (schema 6, state.v5.party; old saves get an empty record on first use):
##   seq, ev_seq, events [{id, kind, tick, who, text, reason, base, party, offer}] (last 40),
##   offers {id: {id, event, kind "party_offer", base, tick, expires, text, reason, who, cost, places [bld ids]}},
##   parties {id: {id, base, building, reason {kind, who, text}, start, end, phase, guests, honoured, invited,
##                 present, score {fun, attendance, drama}, drama [{kind, big, text, tick, actors}], small_at [ticks],
##                 big_at, big_kind, toast_until, toast {speaker, text}, sing, auto, hours}},
##   big_until (tick: no big drama before), last_big (the last party had a big drama), bday_day.
## On an agent: party (party id) while the person is invited; chat_t (tick of the last idle talk).
## Cost rule: the idle-partner index is made once a tick and only when somebody asks; everything else runs
## once a second and only has work while a party, an offer or a birthday exists.

const Rng = preload("res://sim/rng.gd")

const KINDS := ["birthday", "promotion", "goal", "medal", "structure", "wedding", "adoption", "record"]

var sim
var _idle_tick := -1
var _idle_by_bld := {}

func _init(s) -> void:
	sim = s

func reset() -> void:
	_idle_tick = -1
	_idle_by_bld = {}

func cfg() -> Dictionary:
	return sim.content["society"]["celebrations"]

func lines() -> Dictionary:
	return sim.content["celebrations"]

func _h(x: int, y: int) -> float:
	return Rng.hash2(x, y, int(sim.state.get("seed", 1)) ^ 0xC31E)

func _hz() -> int:
	return int(sim.bal["tick_hz"])

func _day() -> int:
	return int(float(sim.bal["day_length"]) * float(_hz()))

func _w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("party"):
		v["party"] = {"seq": 0, "ev_seq": 0, "events": [], "offers": {}, "parties": {}, "big_until": -1, "last_big": false, "bday_day": -1}
	return v["party"]

func _r() -> Dictionary:
	return sim.state.get("v5", {}).get("party", {})

## The setting "Cheeky dialogue" (on by default): off turns innuendo lines into mild flirt lines.
func cheeky() -> bool:
	return bool(sim.state.get("options", {}).get("cheeky", true))

func _first(a: Dictionary) -> String:
	return String(a.get("name", "")).split(" ")[0]

func _adult(a: Dictionary) -> bool:
	return not a.is_empty() and a["state"] == "alive" and String(a.get("kind", "")) != "child" and String(a.get("kind", "")) != "visitor"

# ---------------------------------------------------------------- talk topics (rules 1 and 2)
## Which orientation lets a be drawn to b (the same test as social.compatible, one side only).
func _drawn(ia: Dictionary, ib: Dictionary) -> bool:
	var at: String = String(ia["attraction"])
	if at == "":
		return false
	var same: bool = ia["sex"] == ib["sex"]
	return at == "both" or (at == "same") == same

## {topic, heat} for a talk that starts now between x (who starts it) and y: flirt and cheeky innuendo
## only between two adults with matching attraction and a good relation; an awkward talk when x is bold
## and y is taken or not drawn to x; else the ordinary topic (and sometimes a joke or a rivalry).
func talk_plan(x: Dictionary, y: Dictionary, salt: int) -> Dictionary:
	var c: Dictionary = cfg()
	var partying: bool = int(x.get("party", -1)) != -1 and int(x.get("party", -1)) == int(y.get("party", -2)) and _party_on(int(x["party"]))
	var hp: Dictionary = sim.hr.talk_topic(x, y, salt)
	if not hp.is_empty():
		return hp
	var ix: Dictionary = sim.people.identity(x)
	var iy: Dictionary = sim.people.identity(y)
	var xid: int = int(x["id"])
	var yid: int = int(y["id"])
	var rel: Dictionary = sim.relations.rel_of(xid, yid)
	var aff: float = float(rel.get("aff", 0.0))
	var att: float = float(rel.get("att", 0.0))
	var st: String = String(rel.get("status", "stranger"))
	if not ix["child"] and not iy["child"]:
		var f: Dictionary = c["flirt"]
		var px: int = sim.relations.partner_of(xid)
		var py: int = sim.relations.partner_of(yid)
		var taken: bool = (px != -1 and px != yid) or (py != -1 and py != xid)
		var interested: bool = ["affair", "fling", "dating", "partners", "married"].has(st)
		var bold: bool = sim.people.has_trait(x, "romantic") or sim.people.has_trait(x, "charming") or sim.people.has_trait(x, "party-animal")
		if sim.social.compatible(x, y):
			if taken and not interested:
				if bold and String(ix["kind"]) == "colonist" and _h(salt, xid + 5) < float(c["awkward"]["chance"]):
					return {"topic": "awkward", "heat": 0}
			elif (att >= float(f["att"]) and aff >= float(f["aff"])) or interested:
				var p: float = 0.35 + minf(0.3, att / 250.0) + (0.2 if interested else 0.0) + (0.25 if partying else 0.0)
				if _h(salt, xid + 17) < p:
					var inn_ok: bool = cheeky() and (att >= float(f["innuendo_att"]) and aff >= float(f["innuendo_aff"]) or (interested and att >= float(f["innuendo_att"]) - 15.0))
					if inn_ok and _h(salt, yid + 29) < 0.65:
						var hot: bool = (att >= float(f["hot_att"]) and aff >= float(f["hot_aff"])) or (interested and att >= float(f["hot_att"]) - 10.0)
						return {"topic": "innuendo", "heat": 3 if hot and _h(salt, 41) < 0.6 else 2}
					return {"topic": "flirt", "heat": 1}
		elif _drawn(ix, iy) and not _drawn(iy, ix) and bold and String(ix["kind"]) == "colonist" and _h(salt, xid + 7) < float(c["awkward"]["chance"]) * 0.7:
			return {"topic": "awkward", "heat": 0}
	if partying and _h(salt, xid + 3) < 0.7:
		return {"topic": "party_talk", "heat": 0}
	if aff <= float(c["topics"]["rival_aff"]) and _h(salt, xid + 13) < 0.5:
		return {"topic": "rivalry", "heat": 0}
	var topic: String = sim.social.topic_for(x, y, salt)
	if ["small_talk", "leisure"].has(topic) and _h(salt, xid + 23) < (0.35 if sim.people.has_trait(x, "funny") else 0.12):
		topic = "joke"
	return {"topic": topic, "heat": 0}

# ---------------------------------------------------------------- idle talk (rule 1)
## A crisis that needs everybody: a shelter order, or a critical alert about air, a hazard or a reactor (a
## standing critical notice such as a breach already being repaired does not stop people talking).
func _crisis() -> bool:
	if sim.hazards.sheltered():
		return true
	var sev: int = int(cfg()["idle"]["crit_severity"])
	for k in sim.state["issues"]:
		var iss: Dictionary = sim.state["issues"][k]
		if int(iss.get("severity", 0)) < sev or not bool(iss.get("live", true)):
			continue
		var code: String = String(iss.get("code", ""))
		if code.contains("air") or code.contains("oxygen") or code.begins_with("hazard") or code.begins_with("reactor"):
			return true
	return false

func _is_idle(a: Dictionary) -> bool:
	if a["state"] != "alive" or a["where"] != "in" or bool(a.get("sleeping", false)) or a.has("lift") or a.has("party"):
		return false
	if String(a.get("kind", "")) == "child" or String(a.get("kind", "")) == "visitor" or a.has("jailed") or a.has("v5_hold"):
		return false
	var pk: String = String(a.get("plan_kind", ""))
	return pk == "idle" or (a["plan"] as Array).is_empty()

func _idle_list(bld: int) -> Array:
	var tick: int = int(sim.state["tick"])
	if tick != _idle_tick:
		_idle_tick = tick
		_idle_by_bld = {}
		var agents: Dictionary = sim.state["agents"]
		for aid in agents:
			var a: Dictionary = agents[aid]
			if _is_idle(a):
				var b: int = int(a["bld"])
				if not _idle_by_bld.has(b):
					_idle_by_bld[b] = []
				_idle_by_bld[b].append(a)
	return _idle_by_bld.get(bld, [])

## Called from agents._think when a person has nothing to do. A person with no job and no need picks
## another idle person in the same room within near_m and starts a talk session with them (the two
## stand and talk for the whole talk). Returns true when a talk started.
func idle_seek(a: Dictionary) -> bool:
	var c: Dictionary = cfg()["idle"]
	var now: int = int(sim.state["tick"])
	if now - int(a.get("chat_t", -1000000)) < int(c["gap_s"]) * _hz() or _h(int(a["id"]), now) >= float(c["chance"]):
		return false
	if not _is_idle(a) or sim.relations.in_talk(int(a["id"])):
		return false
	var list: Array = _idle_list(int(a["bld"]))
	if list.size() < 2 or _crisis():
		return false
	var near: float = float(sim.content["society"]["social"]["near_m"]) * 2.3
	var best: Dictionary = {}
	var best_v := -1e9
	for b in list:
		if int(b["id"]) == int(a["id"]) or sim.relations.in_talk(int(b["id"])) or now - int(b.get("chat_t", -1000000)) < int(c["gap_s"]) * _hz() / 2:
			continue
		if (a["pos"] as Vector2).distance_to(b["pos"]) > near:
			continue
		var rel: Dictionary = sim.relations.rel_of(int(a["id"]), int(b["id"]))
		var v: float = float(rel.get("aff", 0.0)) + float(rel.get("att", 0.0)) + 20.0 * _h(int(a["id"]) * 31 + int(b["id"]), now / 100)
		if v > best_v or (v == best_v and int(b["id"]) < int(best["id"])):
			best_v = v
			best = b
	if best.is_empty():
		return false
	if not sim.relations.start_talk_now(a, best, true):
		return false
	a["chat_t"] = now
	best["chat_t"] = now
	return true

# ---------------------------------------------------------------- events (rule 3)
func _add_event(kind: String, who: Array, text: String, reason: String) -> Dictionary:
	var r: Dictionary = _w()
	var id: int = int(r["ev_seq"]) + 1
	r["ev_seq"] = id
	var base := -1
	if not who.is_empty() and sim.state["agents"].has(int(who[0])) and sim.bases.count() > 0:
		base = int(sim.bases.home_of(sim.state["agents"][int(who[0])]))
	elif sim.bases.count() > 0:
		base = int(sim.bases.ids()[0])
	var ev := {"id": id, "kind": kind, "tick": int(sim.state["tick"]), "who": who.duplicate(), "text": text, "reason": reason, "base": base, "party": -1, "offer": -1}
	(r["events"] as Array).append(ev)
	while (r["events"] as Array).size() > 40:
		(r["events"] as Array).pop_front()
	return ev

## The last n celebration events (newest first).
func events(n: int = 20) -> Array:
	var out: Array = []
	var arr: Array = _r().get("events", [])
	for i in range(arr.size() - 1, maxi(-1, arr.size() - 1 - n), -1):
		out.append((arr[i] as Dictionary).duplicate(true))
	return out

func _name_of(id: int) -> String:
	return String(sim.state["agents"].get(id, {}).get("name", "someone"))

## Called by sim.log_event for every entry: the log codes that are a reason to celebrate.
func on_log(code: String, text: String, ents: Array, extra: Dictionary) -> void:
	match code:
		"promotion", "wedding", "adoption", "arcade_record", "goal", "chapter", "award", "commissioned", "dome_stage":
			pass
		_:
			return
	var who: Array = []
	for e in ents:
		if sim.state["agents"].has(int(e)) and String(sim.state["agents"][int(e)].get("kind", "")) != "child":
			who.append(int(e))
	match code:
		"promotion":
			_celebrate("promotion", who.slice(0, 1), text, "a promotion")
		"wedding":
			_celebrate("wedding", who.slice(0, 2), text, "a wedding")
		"adoption":
			_celebrate("adoption", who.slice(0, 2), text, "a new family member")
		"arcade_record":
			_celebrate("record", who.slice(0, 1), text, "an arcade record")
		"goal":
			_celebrate("goal", [], text, text.trim_prefix("Goal: ").trim_suffix(".").to_lower())
		"chapter":
			_celebrate("goal", [], text, text.get_slice(".", 0).to_lower())
		"award":
			_celebrate("medal", [], text, text.get_slice("(", 0).trim_prefix("Award: ").strip_edges().to_lower())
		"commissioned", "dome_stage":
			var bid := -1
			for e in ents:
				if sim.state["buildings"].has(int(e)):
					bid = int(e)
					break
			if bid == -1 and extra.has("place"):
				bid = int(extra["place"])
			if bid == -1 or not sim.state["buildings"].has(bid):
				return
			var def: String = String(sim.state["buildings"][bid]["def"])
			if not (cfg()["structure_defs"] as Array).has(def):
				return
			if code == "dome_stage" and int(extra.get("stage", 0)) < 9:
				return
			if code == "commissioned" and def == "super_dome":
				return
			_celebrate("structure", [], text, String(sim.bdef(def)["name"]).to_lower())

## A celebration event: stored, and (when there is a venue and room) a party offer for the player.
func _celebrate(kind: String, who: Array, text: String, reason: String, force: bool = false) -> Dictionary:
	var ev: Dictionary = _add_event(kind, who, text, reason)
	sim.log_event("birthday" if kind == "birthday" else "celebration", text, who, 0, {"kind": kind, "event": int(ev["id"])})
	var off: Dictionary = _make_offer(ev, force)
	if not off.is_empty():
		ev["offer"] = int(off["id"])
	return ev

## Debug command "celebrate" {kind, agent}: an event (tests, the UI debug console); the offer is made even
## without friends or a free offer slot.
func cmd_celebrate(p: Dictionary) -> Dictionary:
	var kind: String = String(p.get("kind", ""))
	if not KINDS.has(kind):
		return {"ok": false, "code": "invalid", "text": "Unknown celebration."}
	var who: Array = []
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	if not a.is_empty():
		who.append(int(a["id"]))
	var reason: String = String(p.get("reason", kind))
	var ev: Dictionary = _celebrate(kind, who, "%s: %s." % [kind.capitalize(), reason], reason, true)
	return {"ok": true, "code": "ok", "text": "A %s event." % kind, "event": int(ev["id"]), "offer": int(ev["offer"])}

# ---------------------------------------------------------------- venues and offers
## Buildings of a base that can hold a party: [{building, name, cap, quality}] (best first).
func venues(base: int) -> Array:
	var out: Array = []
	var defs: Array = cfg()["venue_defs"]
	var blds: Dictionary = sim.state["buildings"]
	for bid in blds:
		var b: Dictionary = blds[bid]
		if b["state"] != "active" or bool(b["demolish"]) or not defs.has(String(b["def"])) or not sim.util.building_supplied(int(bid)):
			continue
		if sim.bases.count() > 0 and base != -1 and int(sim.bases.base_of(int(bid))) != base:
			continue
		var d: Dictionary = sim.bd(b)
		var cap: int = int(cfg()["dome_guests_cap"]) if String(b["def"]) == "super_dome" else clampi(int(d.get("occupants", 6)) * 2, int(cfg()["guests_min"]), int(cfg()["guests_cap"]))
		out.append({"building": int(bid), "name": String(b["name"]), "cap": cap, "quality": float(d.get("morale_bonus", 0.0)) + (20.0 if String(b["def"]) == "super_dome" else 0.0)})
	out.sort_custom(func(x, y): return float(x["quality"]) > float(y["quality"]) if float(x["quality"]) != float(y["quality"]) else int(x["building"]) < int(y["building"]))
	return out

func _popular(a: Dictionary) -> int:
	var s: Dictionary = sim.relations.summary(int(a["id"]))
	return int(s["friends"]) + int(s["best_friends"]) + (1 if int(s["partner"]) != -1 else 0)

func _expected_guests(base: int, cap: int) -> int:
	var n := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if _adult(a) and (sim.bases.count() == 0 or base == -1 or sim.bases.home_of(a) == base):
			n += 1
	return clampi(n / 2, int(cfg()["guests_min"]), cap)

func party_cost(guests: int) -> int:
	return int(ceil(float(guests) / float(sim.content["society"]["party"]["per_people"])))

func _offer_options() -> Array:
	return [{"id": "throw", "text": "Throw the party", "effect": "Uses drinks and snacks from the base stock. Guests dance and talk for 1 to 3 minutes. Satisfaction rises. Something may go wrong."},
		{"id": "skip", "text": "Skip it", "effect": "No cost. Friends may gather by themselves, without drinks."}]

func _make_offer(ev: Dictionary, force: bool = false) -> Dictionary:
	var r: Dictionary = _w()
	var base: int = int(ev["base"])
	var who: Array = ev["who"]
	if not force:
		if ev["kind"] == "birthday" and not who.is_empty() and _popular(sim.state["agents"][int(who[0])]) < int(cfg()["birthday_min_friends"]):
			return {}
		var open := 0
		for oid in r["offers"]:
			var o: Dictionary = r["offers"][oid]
			if int(o["base"]) == base:
				open += 1
				if o["kind"] == "party_offer" and String(o["reason"]) == String(ev["reason"]) and o["who"] == who:
					return {}
		if open >= int(cfg()["max_offers_per_base"]):
			return {}
	var vs: Array = venues(base)
	if vs.is_empty():
		return {}
	var id: int = sim.relations.next_request_id()
	var texts: Array = lines()["offers"][String(ev["kind"])]
	var nm: String = _name_of(int(who[0])) if not who.is_empty() else "the colony"
	var text: String = String(texts[int(_h(id, 3) * texts.size()) % texts.size()]).replace("{name}", nm).replace("{reason}", String(ev["reason"]))
	var cap: int = int(vs[0]["cap"])
	var places: Array = []
	for v in vs:
		places.append(int(v["building"]))
	var off := {"id": id, "event": int(ev["id"]), "kind": "party_offer", "base": base, "tick": int(sim.state["tick"]), "who": who.duplicate(), "reason": String(ev["reason"]),
		"expires": int(sim.state["tick"]) + int(cfg()["offer_valid_s"]) * _hz(), "text": text, "cost": party_cost(_expected_guests(base, cap)), "places": places, "ekind": String(ev["kind"])}
	r["offers"][id] = off
	sim.log_event("party_offer", text, who, 1, {"offer": id, "place": int(places[0])})
	return off

func has_offer(id: int) -> bool:
	return _r().get("offers", {}).has(id)

func _offer_row(o: Dictionary) -> Dictionary:
	var choices: Array = []
	for bid in o["places"]:
		if sim.state["buildings"].has(int(bid)):
			var b: Dictionary = sim.state["buildings"][int(bid)]
			choices.append({"building": int(bid), "name": String(b["name"]), "cost": party_cost(_expected_guests(int(o["base"]), 30))})
	return {"id": int(o["id"]), "kind": "party_offer", "agent": int(o["who"][0]) if not (o["who"] as Array).is_empty() else -1, "other": -1, "ship": -1,
		"tick": int(o["tick"]), "text": String(o["text"]), "options": _offer_options(), "expires": int(o["expires"]), "reason": String(o["reason"]), "place_choices": choices,
		"base": int(o["base"]), "cost": int(o["cost"])}

## The party_offer rows of the Requests tab (relations.requests adds them).
func request_rows() -> Array:
	var out: Array = []
	var offers: Dictionary = _r().get("offers", {})
	var ids: Array = offers.keys()
	ids.sort()
	for id in ids:
		out.append(_offer_row(offers[id]))
	return out

func offers() -> Array:
	return request_rows()

## answer_request for a party offer: answer "throw" (place, hours) or "skip".
func answer(p: Dictionary) -> Dictionary:
	var r: Dictionary = _w()
	var id: int = int(p.get("id", -1))
	if not r["offers"].has(id):
		return {"ok": false, "code": "invalid", "text": "No such request."}
	var o: Dictionary = r["offers"][id]
	var ans: String = String(p.get("answer", ""))
	if ans == "skip":
		r["offers"].erase(id)
		return {"ok": true, "code": "ok", "text": "No party. Friends may still gather."}
	if ans != "throw":
		return {"ok": false, "code": "invalid", "text": "Answer throw or skip."}
	var bld: int = int(p.get("place", o["places"][0] if not (o["places"] as Array).is_empty() else -1))
	var res: Dictionary = start_party(int(o["base"]), bld, int(p.get("hours", cfg()["hours_default"])), {"kind": String(o["ekind"]), "who": o["who"], "text": String(o["text"]), "reason": String(o["reason"])}, false)
	if bool(res.get("ok", false)):
		r["offers"].erase(id)
		for ev in r["events"]:
			if int(ev["id"]) == int(o["event"]):
				ev["party"] = int(res["party"])
	return res

# ---------------------------------------------------------------- parties (rules 4 and 5)
## Command "throw_party" {building, hours (1..3), reason?}: a party without an offer (same cost).
func cmd_throw(p: Dictionary) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(int(p.get("building", -1)), {})
	if b.is_empty():
		return {"ok": false, "code": "invalid", "text": "Choose a place."}
	var base: int = int(sim.bases.base_of(int(b["id"]))) if sim.bases.count() > 0 else -1
	return start_party(base, int(b["id"]), int(p.get("hours", cfg()["hours_default"])), {"kind": "manual", "who": [], "text": "A party at the %s." % String(b["name"]).to_lower(), "reason": "a party"}, false)

func _party_on(pid: int) -> bool:
	var pt: Dictionary = _r().get("parties", {}).get(pid, {})
	return not pt.is_empty() and String(pt["phase"]) == "on"

func start_party(base: int, bld: int, hours: int, reason: Dictionary, auto: bool) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(bld, {})
	if b.is_empty() or b["state"] != "active" or not (cfg()["venue_defs"] as Array).has(String(b["def"])):
		return {"ok": false, "code": "invalid", "text": "That place cannot hold a party."}
	if not sim.util.building_supplied(bld):
		return {"ok": false, "code": "no_air", "text": "The place has no air or power."}
	var r: Dictionary = _w()
	for pid in r["parties"]:
		if int(r["parties"][pid]["building"]) == bld and String(r["parties"][pid]["phase"]) != "over":
			return {"ok": false, "code": "busy", "text": "A party is already there."}
	hours = clampi(hours, int(cfg()["hours_min"]), int(cfg()["hours_max"]))
	var cap: int = int(cfg()["dome_guests_cap"]) if String(b["def"]) == "super_dome" else clampi(int(sim.bd(b).get("occupants", 6)) * 2, int(cfg()["guests_min"]), int(cfg()["guests_cap"]))
	var guests: Array = _recruit(base, reason, cap, auto)
	if guests.size() < int(cfg()["guests_min"]):
		return {"ok": false, "code": "no_guests", "text": "Not enough people can come now."}
	if not auto:
		var need: int = party_cost(guests.size())
		var items: Array = sim.content["society"]["party"]["items"]
		if sim.leisure.count_stock(base, items) < need:
			return {"ok": false, "code": "no_stock", "text": "A party needs %d drinks, snacks or rations; the base has %d." % [need, sim.leisure.count_stock(base, items)]}
		sim.leisure.take_stock(base, items, need, "party")
	var id: int = int(r["seq"]) + 1
	r["seq"] = id
	var now: int = int(sim.state["tick"])
	var start: int = now + int(cfg()["gather_s"]) * _hz()
	var secs: float = float(start - now) / float(_hz()) + float(hours) * float(cfg()["hour_s"])
	var honoured: Array = []
	for w in reason["who"]:
		if sim.state["agents"].has(int(w)) and sim.state["agents"][int(w)]["state"] == "alive":
			honoured.append(int(w))
	var pt := {"id": id, "base": base, "building": bld, "pos": b["pos"], "reason": {"kind": String(reason["kind"]), "who": (reason["who"] as Array).duplicate(), "text": String(reason["text"]), "reason": String(reason["reason"])},
		"start": start, "end": start + int(float(hours) * float(cfg()["hour_s"]) * float(_hz())), "phase": "gathering", "guests": [], "honoured": honoured, "invited": 0, "present": 0,
		"score": {"fun": 0.0, "attendance": 0.0, "drama": 0}, "drama": [], "small_at": [], "big_at": -1, "big_kind": "", "toast_until": -1, "toast": {}, "sing": -1, "auto": auto, "hours": hours}
	var invited: Array = []
	for g in guests:
		var a: Dictionary = sim.state["agents"][int(g)]
		a["party"] = id
		if sim.agents._start_personal(a, "party", bld, [{"op": "wait", "t": secs}], "Going to the party", -1):
			a["last_rec"] = now
			invited.append(int(g))
		else:
			a.erase("party")
	if invited.size() < int(cfg()["guests_min"]):
		for g in invited:
			var ag: Dictionary = sim.state["agents"][int(g)]
			ag.erase("party")
			sim.agents.abort_plan(ag, "party_off")
		r["seq"] = id - 1
		return {"ok": false, "code": "no_guests", "text": "Not enough people can walk there now."}
	pt["guests"] = invited
	pt["invited"] = invited.size()
	r["parties"][id] = pt
	sim.log_event("party_start", "%s for %s: %d guests at the %s." % ["A small gathering" if auto else "A party", String(reason.get("reason", "a party")), invited.size(), String(b["name"]).to_lower()], honoured, 1, {"party": id, "place": bld, "auto": auto})
	return {"ok": true, "code": "ok", "text": "The party starts in %d s with %d guests." % [int(cfg()["gather_s"]), invited.size()], "party": id}

func _bfriends(honoured: Array, a: Dictionary) -> bool:
	for h in honoured:
		var st: String = String(sim.relations.rel_of(int(h), int(a["id"])).get("status", ""))
		if ["friend", "best_friend", "dating", "partners", "married"].has(st):
			return true
	return false

## Guests: the honoured people, their friends, then others who are not busy; at most cap; none that a
## critical need, a cell, a class or a fight holds. An automatic gathering takes friends only.
func _recruit(base: int, reason: Dictionary, cap: int, auto: bool) -> Array:
	var hon: Array = []
	for w in reason["who"]:
		hon.append(int(w))
	var crit: float = float(sim.bal["need_critical"]) - 10.0
	var cands: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if not _adult(a) or a["where"] == "lock" or a["where"] == "vehicle" or a.has("jailed") or a.has("v5_hold") or a.has("lift") or a.has("party"):
			continue
		if sim.bases.count() > 0 and base != -1 and sim.bases.home_of(a) != base:
			continue
		if float(a["hunger"]) >= crit or float(a["thirst"]) >= crit or float(a["fatigue"]) >= 85.0 or String(a.get("plan_kind", "")) == "safety":
			continue
		if sim.education.in_class(a):
			continue
		# A colonist who has an order that can be carried out is busy with it (docs/V5_DESIGN.md 18.1).
		if a.has("order") and not sim.orders.is_blocked(a):
			continue
		var rank := 2
		if hon.has(int(aid)):
			rank = 0
		elif _bfriends(hon, a):
			rank = 1
		elif auto:
			continue
		else:
			var pk: String = String(a.get("plan_kind", ""))
			if not ((a["plan"] as Array).is_empty() or ["idle", "rec", "chat"].has(pk)):
				continue
		var v: float = float(rank) * 10.0 - (3.0 if sim.people.has_trait(a, "party-animal") else 0.0) + _h(int(aid), int(sim.state["tick"]) / 100)
		cands.append([v, int(aid)])
	cands.sort_custom(func(x, y): return float(x[0]) < float(y[0]) if float(x[0]) != float(y[0]) else int(x[1]) < int(y[1]))
	var out: Array = []
	for c in cands:
		if out.size() >= cap:
			break
		out.append(int(c[1]))
	return out

func parties() -> Array:
	var out: Array = []
	var ps: Dictionary = _r().get("parties", {})
	var ids: Array = ps.keys()
	ids.sort()
	for id in ids:
		var pt: Dictionary = ps[id]
		if String(pt["phase"]) == "over":
			continue
		out.append(_row(pt))
	return out

func _row(pt: Dictionary) -> Dictionary:
	return {"id": int(pt["id"]), "base": int(pt["base"]), "building": int(pt["building"]), "pos": pt["pos"], "reason": (pt["reason"] as Dictionary).duplicate(true),
		"start": int(pt["start"]), "end": int(pt["end"]), "phase": String(pt["phase"]), "guests": (pt["guests"] as Array).duplicate(), "honoured": (pt["honoured"] as Array).duplicate(),
		"score": (pt["score"] as Dictionary).duplicate(), "drama": (pt["drama"] as Array).duplicate(true), "toast": (pt["toast"] as Dictionary).duplicate(), "auto": bool(pt["auto"])}

## A finished or running party by id ({} when unknown).
func party(id: int) -> Dictionary:
	var pt: Dictionary = _r().get("parties", {}).get(id, {})
	return _row(pt) if not pt.is_empty() else {}

func party_of(agent_id: int) -> int:
	var a: Dictionary = sim.state["agents"].get(agent_id, {})
	return int(a.get("party", -1)) if not a.is_empty() else -1

## The clip a guest plays now ("" = the ordinary one): dance_a, dance_c, drink_bar, toast or sing.
func action_of(a: Dictionary) -> String:
	var pt: Dictionary = _r().get("parties", {}).get(int(a.get("party", -1)), {})
	if pt.is_empty() or String(pt["phase"]) != "on" or int(a["bld"]) != int(pt["building"]) or a["where"] != "in":
		return ""
	var now: int = int(sim.state["tick"])
	if int(pt["sing"]) == int(a["id"]) and now < int(pt["toast_until"]) + 150:
		return "sing"
	if now < int(pt["toast_until"]):
		return "toast"
	match (now / 200 + int(a["id"])) % 5:
		0, 1:
			return "dance_a"
		2:
			return "dance_c"
		3:
			return "drink_bar"
	return ""

# ---------------------------------------------------------------- once a second
func tick_second() -> void:
	var r: Dictionary = _r()
	var now: int = int(sim.state["tick"])
	var day: int = now / _day()
	if r.is_empty() or int(r["bday_day"]) != day:
		_birthdays(day)
		r = _r()
	if r.is_empty():
		return
	var offers: Dictionary = r["offers"]
	if not offers.is_empty():
		for id in offers.keys():
			var o: Dictionary = offers[id]
			if now >= int(o["expires"]):
				offers.erase(id)
				_auto_gathering(o)
	var parties: Dictionary = r["parties"]
	if not parties.is_empty():
		for id in parties.keys():
			_party_second(parties[id], now)
			if String(parties[id]["phase"]) == "over" and now > int(parties[id]["end"]) + 600 * _hz():
				parties.erase(id)

func _birthdays(day: int) -> void:
	var r: Dictionary = _w()
	r["bday_day"] = day
	if day < 1:
		return
	var yd: int = int(cfg()["year_days"])
	var today: int = day % yd
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if not _adult(a) or int(_birthday_of(int(aid))) != today:
			continue
		if int(a.get("born", 0)) / _day() >= day:
			continue
		_celebrate("birthday", [int(aid)], "It is %s's birthday." % _first(a), "a birthday")

## A person's birthday: a day of the colony year (year_days game days), fixed by the person's id.
func _birthday_of(id: int) -> int:
	return int(_h(id, 91) * float(cfg()["year_days"])) % int(cfg()["year_days"])

func _auto_gathering(o: Dictionary) -> void:
	var vs: Array = venues(int(o["base"]))
	if vs.is_empty() or (o["who"] as Array).is_empty():
		return
	var res: Dictionary = start_party(int(o["base"]), int(vs[0]["building"]), 1, {"kind": String(o["ekind"]), "who": o["who"], "text": "Friends gathered for %s." % String(o["reason"]), "reason": String(o["reason"])}, true)
	if bool(res.get("ok", false)):
		for ev in _w()["events"]:
			if int(ev["id"]) == int(o["event"]):
				ev["party"] = int(res["party"])

func _present(pt: Dictionary) -> Array:
	var out: Array = []
	for g in pt["guests"]:
		var a: Dictionary = sim.state["agents"].get(int(g), {})
		if not a.is_empty() and a["state"] == "alive" and a["where"] == "in" and int(a["bld"]) == int(pt["building"]) and int(a.get("party", -1)) == int(pt["id"]):
			out.append(a)
	return out

func _party_second(pt: Dictionary, now: int) -> void:
	var b: Dictionary = sim.state["buildings"].get(int(pt["building"]), {})
	var phase: String = String(pt["phase"])
	if phase == "over":
		return
	if b.is_empty() or b["state"] != "active" or bool(b["demolish"]):
		_end_party(pt, "the place closed")
		return
	if phase == "gathering":
		if now >= int(pt["start"]):
			pt["phase"] = "on"
			_plan_drama(pt)
		return
	var pres: Array = _present(pt)
	pt["present"] = pres.size()
	pt["score"]["attendance"] = snappedf(float(pres.size()) / float(maxi(1, int(pt["invited"]))), 0.01)
	pt["score"]["fun"] = minf(100.0, float(pt["score"]["fun"]) + 0.25 * float(mini(pres.size(), 12)) / 6.0)
	if now >= int(pt["end"]):
		_end_party(pt, "")
		return
	if int(pt["toast_until"]) < 0 and now >= int(pt["start"]) + (int(pt["end"]) - int(pt["start"])) / 3 and not pres.is_empty():
		_toast(pt, pres)
	for t in (pt["small_at"] as Array).duplicate():
		if now >= int(t):
			(pt["small_at"] as Array).erase(t)
			_small_drama(pt, pres, now)
	if int(pt["big_at"]) != -1 and now >= int(pt["big_at"]):
		pt["big_at"] = -1
		_big_drama(pt, pres, now)

func _toast(pt: Dictionary, pres: Array) -> void:
	var now: int = int(sim.state["tick"])
	var sp: Dictionary = pres[int(_h(int(pt["id"]), 5) * pres.size()) % pres.size()]
	var hon: String = _name_of(int(pt["honoured"][0])) if not (pt["honoured"] as Array).is_empty() else "everybody"
	var arr: Array = lines()["topics"]["toast"]
	var text: String = String(arr[int(_h(int(pt["id"]), 6) * arr.size()) % arr.size()]).replace("{name}", hon).replace("{reason}", String(pt["reason"].get("reason", "tonight")))
	pt["toast_until"] = now + 100
	pt["toast"] = {"speaker": int(sp["id"]), "text": text}
	sim.social.say(sp, text, "toast", int(pt["honoured"][0]) if not (pt["honoured"] as Array).is_empty() else -1)
	# One tipsy singer a party now and then.
	if _h(int(pt["id"]), 8) < 0.35 and pres.size() > 2:
		var sg: Dictionary = pres[int(_h(int(pt["id"]), 9) * pres.size()) % pres.size()]
		pt["sing"] = int(sg["id"])
		var sa: Array = lines()["topics"]["sing"]
		sim.social.say(sg, String(sa[int(_h(int(pt["id"]), 10) * sa.size()) % sa.size()]), "party_talk", -1)

## When the party turns on: 1 to 3 small dramas at random times, and a big one now and then.
func _plan_drama(pt: Dictionary) -> void:
	var c: Dictionary = cfg()["drama"]
	var r: Dictionary = _w()
	var now: int = int(sim.state["tick"])
	var span: int = maxi(100, int(pt["end"]) - now - 100)
	var n: int = int(c["small_min"]) + int(_h(int(pt["id"]), 11) * float(int(c["small_max"]) - int(c["small_min"]) + 1))
	n = mini(n, int(c["small_max"]))
	for i in n:
		(pt["small_at"] as Array).append(now + 50 + int(_h(int(pt["id"]), 20 + i) * float(span - 50)))
	var eligible: bool = now >= int(r["big_until"]) and not bool(r["last_big"]) and not bool(pt["auto"])
	var big := false
	if eligible and _h(int(pt["id"]), 12) < float(c["big_chance"]):
		big = true
		pt["big_at"] = now + int(float(span) * (0.45 + 0.3 * _h(int(pt["id"]), 13)))
	pt["big_kind"] = ""
	pt["big_planned"] = big
	r["last_big"] = big if not bool(pt["auto"]) else bool(r["last_big"])

func _pick2(pres: Array, salt: int) -> Array:
	if pres.size() < 2:
		return []
	var i: int = int(_h(salt, 1) * pres.size()) % pres.size()
	var j: int = (i + 1 + int(_h(salt, 2) * float(pres.size() - 1)) % (pres.size() - 1)) % pres.size()
	return [pres[i], pres[j]]

func _small_drama(pt: Dictionary, pres: Array, now: int) -> void:
	var arr: Array = lines()["drama_small"]
	if arr.is_empty() or pres.is_empty():
		return
	var e: Dictionary = arr[int(_h(int(pt["id"]) * 7 + now, 3) * arr.size()) % arr.size()]
	var two: Array = _pick2(pres, int(pt["id"]) * 13 + now)
	var a: Dictionary = pres[int(_h(int(pt["id"]) * 5 + now, 4) * pres.size()) % pres.size()]
	var b: Dictionary = two[1] if not two.is_empty() else a
	if two.size() == 2 and int(two[0]["id"]) != int(a["id"]):
		b = two[0]
	var text: String = String(e["text"]).replace("{a}", _first(a)).replace("{b}", _first(b))
	var c: Dictionary = cfg()["drama"]
	sim.people.add_mod(a, {"kind": "party_drama", "text": "A party mishap", "comp": "social", "sat": float(c["small_sat"]), "att": 0.0, "days": float(c["small_days"])})
	if int(a["id"]) != int(b["id"]) and String(e["id"]) in ["awkward_flirt", "wrong_name", "gossip", "slow_dance", "dance_off"]:
		var rel: Dictionary = sim.relations._rel_w(a, b)
		rel["aff"] = clampf(float(rel["aff"]) + (3.0 if String(e["id"]) in ["slow_dance", "dance_off"] else -2.0), -100.0, 100.0)
		sim.relations._status_changed()
	(pt["drama"] as Array).append({"kind": String(e["id"]), "big": false, "text": text, "tick": now, "actors": [int(a["id"]), int(b["id"])] if int(a["id"]) != int(b["id"]) else [int(a["id"])]})
	pt["score"]["drama"] = int(pt["score"]["drama"]) + 1
	pt["score"]["fun"] = minf(100.0, float(pt["score"]["fun"]) + 2.0)
	sim.log_event("party_drama", text, [int(a["id"]), int(b["id"])] if int(a["id"]) != int(b["id"]) else [int(a["id"])], 0, {"party": int(pt["id"]), "place": int(pt["building"]), "drama": String(e["id"])})

## Big drama: a public break-up, a jealous scene, an affair revealed, a proposal or a fight, from what the
## guests have (couples, an affair, enemies). None is made when nothing fits.
func _big_drama(pt: Dictionary, pres: Array, now: int) -> void:
	var r: Dictionary = _w()
	var ids := {}
	for a in pres:
		ids[int(a["id"])] = a
	var cands: Array = []
	for pr in sim.relations.pairs_with(["dating", "partners", "married", "affair", "enemy", "rival"]):
		if ids.has(int(pr["a"])) and ids.has(int(pr["b"])):
			cands.append(pr)
	var kinds: Array = []
	var by_kind := {}
	for pr in cands:
		var st: String = String(pr["status"])
		var ks: Array = []
		match st:
			"dating", "partners":
				ks = ["breakup", "proposal", "jealous"]
			"married":
				ks = ["jealous"]
			"affair":
				ks = ["affair"]
			"enemy", "rival":
				ks = ["fight"]
		for k in ks:
			if not by_kind.has(k):
				by_kind[k] = []
				kinds.append(k)
			by_kind[k].append(pr)
	if kinds.is_empty() and pres.size() >= 2:
		var two: Array = _pick2(pres, int(pt["id"]) * 31)
		by_kind["fight"] = [{"a": int(two[0]["id"]), "b": int(two[1]["id"]), "status": "stranger"}]
		kinds.append("fight")
	if kinds.is_empty():
		return
	kinds.sort()
	var kind: String = kinds[int(_h(int(pt["id"]), 14) * kinds.size()) % kinds.size()]
	var list: Array = by_kind[kind]
	var pr2: Dictionary = list[int(_h(int(pt["id"]), 15) * list.size()) % list.size()]
	var a: Dictionary = sim.state["agents"][int(pr2["a"])]
	var b: Dictionary = sim.state["agents"][int(pr2["b"])]
	var arr: Array = lines()["drama_big"][kind]
	var text: String = String(arr[int(_h(int(pt["id"]), 16) * arr.size()) % arr.size()]).replace("{a}", _first(a)).replace("{b}", _first(b))
	var rel: Dictionary = sim.relations._rel_w(a, b)
	match kind:
		"breakup":
			sim.relations._break_up(rel, a, b, "in public")
		"jealous":
			rel["aff"] = clampf(float(rel["aff"]) - 12.0, -100.0, 100.0)
			sim.relations._status_changed()
			for x in [a, b]:
				sim.people.add_mod(x, {"kind": "party_scene", "text": "A scene at the party", "comp": "social", "sat": -6.0, "att": -3.0, "days": 1.0})
		"affair":
			sim.relations.reveal_affair(rel, a, b)
		"proposal":
			sim.relations._set_status(rel, "married")
			rel["aff"] = clampf(float(rel["aff"]) + 10.0, -100.0, 100.0)
			sim.log_event("wedding", "%s and %s got engaged at the party and married on the spot!" % [_first(a), _first(b)], [int(a["id"]), int(b["id"])], 1)
			for x in [a, b]:
				sim.people.add_mod(x, {"kind": "party_scene", "text": "A proposal", "comp": "social", "sat": 12.0, "att": 6.0, "days": 2.0})
		"fight":
			sim.security.start_fight(a, b, "a fight at a party")
	(pt["drama"] as Array).append({"kind": kind, "big": true, "text": text, "tick": now, "actors": [int(a["id"]), int(b["id"])]})
	pt["score"]["drama"] = int(pt["score"]["drama"]) + 3
	pt["big_kind"] = kind
	r["big_until"] = now + int(float(cfg()["drama"]["big_cooldown_days"]) * float(_day()))
	sim.log_event("party_drama_big", text, [int(a["id"]), int(b["id"])], 2, {"party": int(pt["id"]), "place": int(pt["building"]), "drama": kind})

func _end_party(pt: Dictionary, why: String) -> void:
	pt["phase"] = "over"
	var c: Dictionary = cfg()["effects"]
	var fun: float = float(pt["score"]["fun"])
	var pres: Array = _present(pt)
	var sat: float = float(c["sat_base"]) + fun * float(c["sat_per_fun"])
	for g in pt["guests"]:
		var a: Dictionary = sim.state["agents"].get(int(g), {})
		if a.is_empty() or a["state"] != "alive":
			continue
		var here: bool = a["where"] == "in" and int(a["bld"]) == int(pt["building"])
		if here:
			sim.people.add_mod(a, {"kind": "party", "text": "A good party", "comp": "social", "sat": sat, "att": float(c["att"]), "days": float(c["days"])})
		a.erase("party")
		if String(a.get("plan_kind", "")) == "party":
			sim.agents.abort_plan(a, "party_over")
	# Friendships grow: each guest present meets a few others.
	var np: int = pres.size()
	if np > 1:
		for i in np:
			for k in int(c["aff_pairs"]):
				var j: int = (i + 1 + int(_h(int(pt["id"]) * 3 + i, 40 + k) * float(np - 1))) % np
				if j == i:
					continue
				var rel: Dictionary = sim.relations._rel_w(pres[i], pres[j])
				rel["aff"] = clampf(float(rel["aff"]) + float(c["aff_gain"]), -100.0, 100.0)
				rel["last"] = int(sim.state["tick"])
		sim.relations._status_changed()
	pt["score"]["attendance"] = snappedf(float(np) / float(maxi(1, int(pt["invited"]))), 0.01)
	sim.log_event("party_end", "The party is over%s: %d guests, fun %d, %d bits of drama." % [(" (" + why + ")") if why != "" else "", np, int(fun), int(pt["score"]["drama"])], pt["honoured"], 0, {"party": int(pt["id"]), "place": int(pt["building"]), "fun": int(fun)})
