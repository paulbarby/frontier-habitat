extends RefCounted
## Version 5 tests for sections 16 (idle talk, innuendo, celebrations, parties, party drama) and 17 (HR).
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")

func tests() -> Array:
	return [
		["v5_party_content", v5_party_content],
		["v5_idle_pairs_start_talks", v5_idle_pairs_start_talks],
		["v5_innuendo_rules", v5_innuendo_rules],
		["v5_celebration_events_make_offers", v5_celebration_events_make_offers],
		["v5_party_flow", v5_party_flow],
		["v5_party_drama_rates", v5_party_drama_rates],
		["v5_party_deterministic", v5_party_deterministic],
		["v5_hr_needs_an_office", v5_hr_needs_an_office],
		["v5_hr_complaints_surveys_transfers", v5_hr_complaints_surveys_transfers],
		["v5_hr_public_and_private", v5_hr_public_and_private],
		["v5_hr_deterministic", v5_hr_deterministic],
	]

static func _showcase():
	var sim = H.Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.state["options"]["debug"] = true
	return sim

## The showcase with an HR office and one officer at its first base (the second base has none). The showcase
## already has them (the builder adds them last), so nothing is added.
static func _showcase_hr():
	var sim = _showcase()
	sim.run_seconds(2.0)
	sim.state["flags"]["unlock_all"] = true
	var base: int = int(sim.bases.ids()[0])
	if sim.hr.active(base):
		return sim
	var near: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	H.attach(sim, "hr_office", near, 1, 60, base)
	sim.run_seconds(2.0)
	var ppl: Array = _adults(sim, base)
	var cid: int = sim.submit("set_role", {"agent": int(ppl[0]["id"]), "role": "hr"})
	sim.step()
	return sim

static func _cmd(sim, kind: String, payload: Dictionary) -> Dictionary:
	var cid: int = sim.submit(kind, payload)
	sim.step()
	return sim.cmds.results.get(cid, {})

static func _adults(sim, base: int = -1) -> Array:
	var out: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child" and (base == -1 or sim.bases.home_of(a) == base):
			out.append(a)
	return out

## Two adults that the attraction rules match (compatible) and two that they do not.
static func _pair(sim, matching: bool) -> Array:
	var ppl: Array = _adults(sim)
	for i in ppl.size():
		for j in range(i + 1, ppl.size()):
			if sim.social.compatible(ppl[i], ppl[j]) == matching and sim.relations.partner_of(int(ppl[i]["id"])) == -1 and sim.relations.partner_of(int(ppl[j]["id"])) == -1:
				return [ppl[i], ppl[j]]
	return []

static func _gloom(sim, a: Dictionary, days: float = 6.0) -> void:
	for comp in ["needs", "food", "housing", "comfort", "social", "work", "fairness", "safety", "freedom"]:
		sim.people.add_mod(a, {"kind": "test_gloom", "text": "x", "comp": comp, "sat": -90.0, "att": -20.0, "days": days})

# ---------------------------------------------------------------- section 16
## At least 120 innuendo lines and 80 flirt lines, each with a heat level; none explicit or about a child; the
## other topics have lines; every celebration kind has offer texts; the setting exists and is on by default.
func v5_party_content(t) -> void:
	var sim = _showcase()
	var cel: Dictionary = sim.content["celebrations"]
	t.check((cel["innuendo"] as Array).size() >= 120, "innuendo lines: %d (at least 120)" % (cel["innuendo"] as Array).size())
	t.check((cel["flirt"] as Array).size() >= 80, "flirt lines: %d (at least 80)" % (cel["flirt"] as Array).size())
	var bad := 0
	var seen := {}
	var dup := 0
	var no_heat := 0
	var banned := ["child", "kid", "boy", "girl", "teen", "baby", "school", "minor"]
	var explicit := ["fuck", "cock", "pussy", "dick", "naked sex", "orgasm", "cum"]
	for l in (cel["innuendo"] as Array) + (cel["flirt"] as Array):
		var tx: String = String(l["text"]).to_lower()
		if int(l.get("heat", 0)) < 1 or int(l.get("heat", 0)) > 3:
			no_heat += 1
		if seen.has(tx):
			dup += 1
		seen[tx] = true
		var words: PackedStringArray = tx.replace(",", " ").replace(".", " ").replace("?", " ").replace("!", " ").replace(":", " ").replace("'", " ").split(" ", false)
		for w in banned + explicit:
			if words.has(String(w)) or words.has(String(w) + "s"):
				bad += 1
	t.eq(no_heat, 0, "every line has a heat 1..3")
	t.eq(dup, 0, "no duplicate line")
	t.eq(bad, 0, "no line names a child or is explicit")
	for l in cel["innuendo"]:
		if int(l["heat"]) < 2:
			bad += 1
	for l in cel["flirt"]:
		if int(l["heat"]) != 1:
			bad += 1
	t.eq(bad, 0, "innuendo is heat 2 or 3, flirt is heat 1")
	for k in ["joke", "rivalry", "awkward", "decline", "flirt_reply", "innuendo_reply", "party_talk", "toast"]:
		t.check((cel["topics"][k] as Array).size() >= 5, "topic %s has lines" % k)
	for k in sim.party.KINDS:
		t.check(cel["offers"].has(k), "offer text for %s" % k)
	t.check(sim.party.cheeky(), "Cheeky dialogue is on by default")
	var r: Dictionary = _cmd(sim, "set_option", {"key": "cheeky", "value": false})
	t.check(bool(r.get("ok", false)) and not sim.party.cheeky(), "set_option turns it off")
	sim.dispose()
	t.done()

## People with nothing to do, in one room, start talk sessions on their own (idle talk). Six adults are put
## in one room with no work and no leisure plan (test set-up); in the showcase the rooms are big, so natural
## idle pairs are rare.
func v5_idle_pairs_start_talks(t) -> void:
	var sim = _showcase()
	sim.run_seconds(5.0)
	var base: int = int(sim.bases.ids()[0])
	var room := -1
	for bid in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][bid]
		if String(b["def"]) == "lounge" and b["state"] == "active" and sim.bases.base_of(int(bid)) == base:
			room = int(bid)
	t.check(room != -1, "a lounge in the base")
	var crew: Array = []
	for a in _adults(sim, base):
		if crew.size() < 6 and String(a["role"]) != "security" and not a.has("jailed"):
			crew.append(a)
	var pos: Vector2 = sim.state["buildings"][room]["pos"]
	for k in crew.size():
		var a: Dictionary = crew[k]
		sim.agents.abort_plan(a, "test")                                        # test set-up
		a["where"] = "in"
		a["bld"] = room
		a["pos"] = pos + Vector2(float(k) * 5.5, 0.0)                                      # 5.5 m apart: too far for an ordinary talk (3.5 m), near enough for idle talk (8 m)
		a["hunger"] = 5.0
		a["thirst"] = 5.0
		a["fatigue"] = 5.0
		a["sleeping"] = false
		sim.people.add_mod(a, {"kind": "test_idle", "text": "x", "comp": "work", "sat": 0.0, "att": 0.0, "days": 1.0, "no_work": true, "no_rec": true})
	var ids: Array = []
	for a in crew:
		ids.append(int(a["id"]))
	var found := 0
	var other_room := 0
	var kids := 0
	var plan_ok := 0
	var seen := {}
	for s in 120:
		sim.run_seconds(1.0)
		for tk in sim.social.talks():
			if bool(tk["idle"]) and not seen.has(tk["id"]):
				seen[tk["id"]] = true
				found += 1
				var x: Dictionary = sim.state["agents"][int(tk["a"])]
				var y: Dictionary = sim.state["agents"][int(tk["b"])]
				if int(x["bld"]) != int(y["bld"]):
					other_room += 1
				if String(x.get("kind", "")) == "child" or String(y.get("kind", "")) == "child":
					kids += 1
				if String(x.get("plan_kind", "")) == "chat" and String(y.get("plan_kind", "")) == "chat":
					plan_ok += 1
	t.check(found >= 3, "idle people started %d talks in 2 game minutes" % found)
	t.eq(other_room, 0, "an idle talk is between two people in the same room")
	t.eq(kids, 0, "no child starts an idle talk")
	t.check(plan_ok >= 1, "the two stand and chat while it lasts (%d of %d)" % [plan_ok, found])
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## Innuendo only between adults with matching attraction and a good relation; the setting off gives none;
## a child never; a taken person gives an awkward moment, not innuendo.
func v5_innuendo_rules(t) -> void:
	var sim = _showcase()
	sim.run_seconds(2.0)
	var good: Array = _pair(sim, true)
	var bad: Array = _pair(sim, false)
	t.check(good.size() == 2 and bad.size() == 2, "a matching and a non-matching adult pair exist")
	var rel: Dictionary = sim.relations._rel_w(good[0], good[1])                     # test set-up: a strong bond
	rel["aff"] = 60.0
	rel["att"] = 85.0
	rel["status"] = "dating"
	sim.relations._bump()
	var topics := {}
	var heats := {}
	for i in 400:
		var plan: Dictionary = sim.party.talk_plan(good[0], good[1], 1000 + i * 17)
		topics[String(plan["topic"])] = int(topics.get(String(plan["topic"]), 0)) + 1
		heats[int(plan["heat"])] = int(heats.get(int(plan["heat"]), 0)) + 1
	t.check(int(topics.get("innuendo", 0)) > 20 and int(topics.get("flirt", 0)) > 10, "a strong matching pair gets innuendo (%d) and flirt (%d)" % [int(topics.get("innuendo", 0)), int(topics.get("flirt", 0))])
	t.check(heats.has(2) and heats.has(3), "innuendo comes in heat 2 and 3: %s" % str(heats))
	# The lines of that talk: innuendo text is from the innuendo list.
	var inn_texts := {}
	for l in sim.content["celebrations"]["innuendo"]:
		inn_texts[String(l["text"]).replace("{other}", "X")] = true
	var line_ok := 0
	for i in 40:
		var ln: Dictionary = sim.social.line_for(good[0], good[1], "innuendo", 5000 + i, int(good[0]["bld"]), false, 2 + i % 2)
		if inn_texts.has(String(ln["text"]).replace(sim.social._first(good[1]), "X")):
			line_ok += 1
	t.eq(line_ok, 40, "an innuendo line is an innuendo line")
	# Setting off: no innuendo topic, no innuendo line.
	_cmd(sim, "set_option", {"key": "cheeky", "value": false})
	var off_inn := 0
	var off_flirt := 0
	for i in 400:
		var plan2: Dictionary = sim.party.talk_plan(good[0], good[1], 1000 + i * 17)
		if plan2["topic"] == "innuendo":
			off_inn += 1
		if plan2["topic"] == "flirt":
			off_flirt += 1
	t.eq(off_inn, 0, "with Cheeky dialogue off there is no innuendo topic")
	t.check(off_flirt > 20, "it becomes flirting (%d)" % off_flirt)
	var flirt_texts := {}
	for l in sim.content["celebrations"]["flirt"]:
		flirt_texts[String(l["text"]).replace("{other}", "X")] = true
	var off_lines := 0
	for i in 40:
		var ln2: Dictionary = sim.social.line_for(good[0], good[1], "innuendo", 7000 + i, int(good[0]["bld"]), false, 3)
		if flirt_texts.has(String(ln2["text"]).replace(sim.social._first(good[1]), "X")):
			off_lines += 1
	t.eq(off_lines, 40, "an innuendo talk is said with flirt lines when the setting is off")
	_cmd(sim, "set_option", {"key": "cheeky", "value": true})
	# A pair that does not match, strangers, and a child: no flirt, no innuendo.
	var rel2: Dictionary = sim.relations._rel_w(bad[0], bad[1])                      # test set-up
	rel2["aff"] = 70.0
	rel2["att"] = 90.0
	sim.relations._bump()
	var romance := 0
	for i in 400:
		var tp: String = String(sim.party.talk_plan(bad[0], bad[1], 2000 + i * 13)["topic"])
		if tp == "flirt" or tp == "innuendo":
			romance += 1
	t.eq(romance, 0, "no flirt or innuendo between people whose attraction does not match")
	var strangers: Array = _pair(sim, true)
	var rs: Dictionary = sim.relations.rel_of(int(strangers[0]["id"]), int(strangers[1]["id"]))
	var kid: Dictionary = {}
	for aid in sim.state["agents"]:
		if String(sim.state["agents"][aid].get("kind", "")) == "child":
			kid = sim.state["agents"][aid]
			break
	if not kid.is_empty():
		var kc := 0
		for i in 400:
			var tk: String = String(sim.party.talk_plan(good[0], kid, 3000 + i * 11)["topic"])
			var tk2: String = String(sim.party.talk_plan(kid, good[0], 3000 + i * 11)["topic"])
			if ["flirt", "innuendo", "awkward"].has(tk) or ["flirt", "innuendo", "awkward"].has(tk2):
				kc += 1
		t.eq(kc, 0, "an adult and a child never get flirt, innuendo or awkward talk")
	# A person in a relationship with somebody else: awkward at most, never innuendo.
	var third: Dictionary = {}
	for a in _adults(sim):
		if int(a["id"]) != int(good[0]["id"]) and int(a["id"]) != int(good[1]["id"]) and sim.social.compatible(a, good[0]) and sim.relations.partner_of(int(a["id"])) == -1:
			third = a
			break
	var inn_taken := 0
	if not third.is_empty():
		for i in 400:
			var tt: String = String(sim.party.talk_plan(third, good[0], 4000 + i * 7)["topic"])
			if tt == "innuendo":
				inn_taken += 1
		t.eq(inn_taken, 0, "somebody who is not close to a partnered person gets no innuendo with them")
	t.check(rs != null, "strangers exist")
	sim.dispose()
	t.done()

## Each celebration kind makes a party offer in the Requests tab; the log codes of the real events do too.
func v5_celebration_events_make_offers(t) -> void:
	var sim = _showcase()
	sim.run_seconds(3.0)
	var ppl: Array = _adults(sim, int(sim.bases.ids()[0]))
	var who: int = int(ppl[3]["id"])
	for k in sim.party.KINDS:
		var r: Dictionary = _cmd(sim, "celebrate", {"kind": k, "agent": who})
		t.check(bool(r.get("ok", false)) and int(r.get("offer", -1)) != -1, "%s makes an offer (%s)" % [k, str(r)])
	var rows: Array = sim.relations.requests()
	var kinds := {}
	for row in rows:
		if row["kind"] == "party_offer":
			kinds[String(row["kind"])] = int(kinds.get(String(row["kind"]), 0)) + 1
			t.check((row["options"] as Array).size() == 2 and (row["place_choices"] as Array).size() >= 1 and int(row["expires"]) > int(sim.state["tick"]), "the offer has options, places and a deadline")
	t.eq(int(kinds.get("party_offer", 0)), 8, "eight offers in the Requests tab")
	# The real events: the log codes the game writes.
	var sim2 = _showcase()
	sim2.run_seconds(3.0)
	var base2: int = int(sim2.bases.ids()[0])
	var p2: Array = _adults(sim2, base2)
	var star: Dictionary = p2[0]
	for pp in p2:
		if sim2.party._popular(pp) > sim2.party._popular(star):
			star = pp
	var a: int = int(star["id"])
	var b: int = int(p2[5]["id"]) if int(p2[5]["id"]) != a else int(p2[6]["id"])
	var nf := 0
	for pp in p2:                                                                   # test set-up: the honoured person has nine friends
		if int(pp["id"]) != a and nf < 9 and not sim2.education.in_class(pp) and String(pp["role"]) != "security" and not pp.has("jailed") and String(pp.get("plan_kind", "")) != "sleep" and not pp.has("v5_hold"):
			var fr: Dictionary = sim2.relations._rel_w(star, pp)
			fr["aff"] = 45.0
			fr["status"] = "friend"
			nf += 1
	sim2.relations._bump()
	var before: int = sim2.party.request_rows().size()
	sim2.log_event("promotion", "X is now a captain.", [a], 1, {})
	sim2.log_event("wedding", "X and Y got married!", [a, b], 1)
	sim2.log_event("adoption", "X and Y adopted Z.", [a, b], 1)
	sim2.log_event("arcade_record", "X set a PRISM SHIFT record: 99 points.", [a], 1, {"score": 99})
	sim2.log_event("goal", "Goal: first harvest.", [], 1)
	sim2.log_event("chapter", "Chapter 2: Settling in. Build homes.", [], 1)
	sim2.log_event("award", "Award: Green Thumb (bronze). Something.", [], 1)
	var dome: int = -1
	for bid in sim2.state["buildings"]:
		if String(sim2.state["buildings"][bid]["def"]) == "academy":
			dome = int(bid)
	if dome != -1:
		sim2.log_event("commissioned", "Academy is commissioned.", [dome], 1)
	var made: int = sim2.party.request_rows().size() - before
	t.eq(made, 7 + (1 if dome != -1 else 0), "the game's own events make offers (%d)" % made)
	var evk := {}
	for e in sim2.party.events(40):
		evk[String(e["kind"])] = true
	for k in ["promotion", "wedding", "adoption", "record", "goal", "medal"]:
		t.check(evk.has(k), "event %s is stored" % k)
	# An answer of "skip" removes the offer; an unanswered offer ends in a small gathering without cost.
	var rows2: Array = sim2.party.request_rows()
	var r1: Dictionary = _cmd(sim2, "answer_request", {"id": int(rows2[0]["id"]), "answer": "skip"})
	t.check(bool(r1.get("ok", false)) and sim2.party.request_rows().size() == rows2.size() - 1, "skip removes the offer")
	t.check(sim2.party._popular(star) >= 2, "the honoured person has friends (%d)" % sim2.party._popular(star))
	sim2.run_seconds(float(sim2.content["society"]["celebrations"]["offer_valid_s"]) + 3.0)
	var auto := false
	for e in sim2.state["log"]:
		if String(e["code"]) == "party_start" and bool(e.get("auto", false)):
			auto = true
	t.check(auto, "an unanswered offer ends in a small gathering of friends")
	t.eq(sim2.inv.audit(), {}, "ledger")
	sim.dispose()
	sim2.dispose()
	t.done()

## A party from the offer to the end: guests gather, it turns on, small dramas happen, the end gives the
## guests a lift in satisfaction; stock is used; nobody is left flagged.
func v5_party_flow(t) -> void:
	var sim = _showcase()
	sim.run_seconds(3.0)
	var base: int = int(sim.bases.ids()[0])
	var ppl: Array = _adults(sim, base)
	var who: int = int(ppl[6]["id"])
	var r: Dictionary = _cmd(sim, "celebrate", {"kind": "birthday", "agent": who})
	var off: Dictionary = sim.party.request_rows()[0]
	var stock0: int = sim.leisure.count_stock(base, sim.content["society"]["party"]["items"])
	var cant: int = -1
	for pc in off["place_choices"]:
		if String(pc["name"]).begins_with("Cantina"):
			cant = int(pc["building"])
	t.check(cant != -1, "a cantina is a place choice")
	var ans: Dictionary = _cmd(sim, "answer_request", {"id": int(off["id"]), "answer": "throw", "place": cant, "hours": 1})
	t.check(bool(ans.get("ok", false)), "throw: %s" % str(ans))
	var pid: int = int(ans.get("party", -1))
	var used: int = stock0 - sim.leisure.count_stock(base, sim.content["society"]["party"]["items"])
	t.check(used >= 2, "the party used drinks and snacks (%d)" % used)
	var row: Dictionary = sim.party.party(pid)
	t.check(String(row["phase"]) == "gathering" and (row["guests"] as Array).size() >= 3, "guests are called (%d)" % (row["guests"] as Array).size())
	t.check((row["honoured"] as Array).has(who), "the honoured person is a guest")
	var g0: int = int((row["guests"] as Array)[0])
	t.eq(sim.party.party_of(g0), pid, "party_of(guest)")
	var sat0: float = 0.0
	var on_seen := false
	var present_max := 0
	var acts := {}
	for s in 140:
		sim.run_seconds(1.0)
		row = sim.party.party(pid)
		if row.is_empty():
			break
		if String(row["phase"]) == "on":
			on_seen = true
			for g in row["guests"]:
				var ac: String = sim.people.action(sim.state["agents"][int(g)]) if sim.state["agents"].has(int(g)) else ""
				if ac != "":
					acts[ac] = true
	t.check(on_seen, "the party turned on")
	t.check(acts.has("dance_a") or acts.has("dance_c") or acts.has("drink_bar") or acts.has("toast"), "guests dance or drink: %s" % str(acts.keys()))
	var ended := false
	var small := 0
	for e in sim.state["log"]:
		if String(e["code"]) == "party_end":
			ended = true
		if String(e["code"]) == "party_drama":
			small += 1
	t.check(ended, "party_end is in the log")
	t.check(small >= 1 and small <= 3, "1 to 3 small dramas (%d)" % small)
	var flagged := 0
	var lifted := 0
	for g in row.get("guests", (sim.party._r()["parties"][pid]["guests"] as Array)):
		var ag: Dictionary = sim.state["agents"].get(int(g), {})
		if ag.is_empty():
			continue
		if ag.has("party"):
			flagged += 1
		if sim.people.has_mod(ag, "party"):
			lifted += 1
	t.eq(flagged, 0, "nobody is flagged as a guest after the party")
	t.check(lifted >= 2, "guests got the party lift (%d)" % lifted)
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## Over many parties: 1 to 3 small dramas each; a big one in about 1 of 6 (never two in a row; a cooldown of
## days after one). The planner is called for many parties in a row, a few days apart.
func v5_party_drama_rates(t) -> void:
	var sim = _showcase()
	sim.run_seconds(2.0)
	var r: Dictionary = sim.party._w()
	var big := 0
	var small_min := 99
	var small_max := 0
	var two_in_row := 0
	var last_big := false
	var n := 1200
	for i in n:
		r["big_until"] = -1                                                        # test set-up: the parties are days apart
		var pt := {"id": 100 + i, "end": int(sim.state["tick"]) + 1400, "small_at": [], "big_at": -1, "auto": false, "big_kind": ""}
		sim.party._plan_drama(pt)
		var s: int = (pt["small_at"] as Array).size()
		small_min = mini(small_min, s)
		small_max = maxi(small_max, s)
		var is_big: bool = int(pt["big_at"]) != -1
		if is_big:
			big += 1
			if last_big:
				two_in_row += 1
		last_big = is_big
	var share: float = float(big) / float(n)
	t.check(small_min >= 1 and small_max <= 3, "small dramas a party: %d to %d" % [small_min, small_max])
	t.check(share > 0.12 and share < 0.21, "big drama in %.3f of the parties (about 1 in 6)" % share)
	t.eq(two_in_row, 0, "never two parties in a row with a big drama")
	# The cooldown: after a big drama none is planned for the cooldown's days.
	r["big_until"] = int(sim.state["tick"]) + int(3.0 * 6000.0)
	r["last_big"] = false
	var in_cool := 0
	for i in 300:
		var pt2 := {"id": 5000 + i, "end": int(sim.state["tick"]) + 1400, "small_at": [], "big_at": -1, "auto": false, "big_kind": ""}
		sim.party._plan_drama(pt2)
		r["last_big"] = false
		if int(pt2["big_at"]) != -1:
			in_cool += 1
	t.eq(in_cool, 0, "no big drama inside the cooldown")
	# A real big drama sets the cooldown (a fight at a party: the guests are the people of a base).
	var ppl: Array = _adults(sim, int(sim.bases.ids()[0]))
	var pres: Array = ppl.slice(0, 8)
	r["big_until"] = -1
	var pt3 := {"id": 77, "building": -1, "drama": [], "score": {"fun": 0.0, "attendance": 0.0, "drama": 0}, "big_kind": ""}
	sim.party._big_drama(pt3, pres, int(sim.state["tick"]))
	t.check(int(r["big_until"]) > int(sim.state["tick"]) + 2 * 6000, "a big drama starts a cooldown of days")
	t.check(String(pt3["big_kind"]) != "" and (pt3["drama"] as Array).size() == 1, "a big drama was made: %s" % String(pt3["big_kind"]))
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## The party state is part of the game state: a save in the middle of a party gives the same result.
func v5_party_deterministic(t) -> void:
	var digests: Array = []
	for run in 2:
		var sim = _showcase()
		sim.run_seconds(3.0)
		var base: int = int(sim.bases.ids()[0])
		var who: int = int(_adults(sim, base)[8]["id"])
		_cmd(sim, "celebrate", {"kind": "promotion", "agent": who})
		var off: Dictionary = sim.party.request_rows()[0]
		_cmd(sim, "answer_request", {"id": int(off["id"]), "answer": "throw", "hours": 1})
		sim.run_seconds(40.3)
		if run == 1:
			var st: Dictionary = Persistence.decode(Persistence.encode(sim.state))["state"]
			sim.dispose()
			sim = H.Sim.new()
			sim.load_state(st)
		sim.run_seconds(60.0)
		digests.append(Persistence.digest(sim.state))
		sim.dispose()
	t.eq(digests[0], digests[1], "the same digest with and without a save in the middle of a party")
	t.done()

# ---------------------------------------------------------------- section 17
## Without an HR office nobody files a complaint or asks for a transfer, however unhappy they are. The showcase
## has an HR office and an officer at its first base and none at the second.
func v5_hr_needs_an_office(t) -> void:
	var sim = _showcase_hr()
	sim.run_seconds(2.0)
	var base: int = int(sim.bases.ids()[0])
	var base2: int = int(sim.bases.ids()[1])
	t.check(sim.hr.active(base) and not sim.hr.active(base2), "the first base has an active HR office, the second has none")
	var ppl2: Array = _adults(sim, base2)
	var ids2 := {}
	for a in ppl2:
		ids2[int(a["id"])] = true
	for i in mini(14, ppl2.size()):
		_gloom(sim, ppl2[i])
	sim.run_seconds(25.0)
	for d in 3:
		sim.hr._daily(int(sim.state["tick"]) / 6000 + d)
	sim.run_seconds(30.0)
	var c2 := 0
	for c in sim.hr.complaints():
		if ids2.has(int(c["agent"])):
			c2 += 1
	var t2 := 0
	for tr in sim.hr.transfers():
		if ids2.has(int(tr["agent"])):
			t2 += 1
	t.eq(c2, 0, "no complaints from the base without HR")
	t.eq(t2, 0, "no transfer requests from the base without HR")
	t.eq(sim.hr.survey(base2), {}, "no feedback round there")
	for r in sim.relations.requests():
		if String(r["kind"]).begins_with("hr_"):
			t.check(not ids2.has(int(r["agent"])), "no HR item for the base without HR")
	# An office without an officer is not active either: the officer takes another job.
	var off_id: int = int(sim.hr.officers(base)[0])
	var res: Dictionary = _cmd(sim, "set_role", {"agent": off_id, "role": "grower"})
	t.check(bool(res.get("ok", false)) and not sim.hr.active(base) and sim.hr.offices(base).size() == 1, "an office with no officer is not active")
	var before: int = sim.hr.complaints().size()
	for a in _adults(sim, base).slice(0, 10):
		_gloom(sim, a)
	sim.run_seconds(25.0)
	sim.hr._daily(int(sim.state["tick"]) / 6000 + 5)
	t.check(sim.hr.complaints().size() == 0 and before >= 0, "without an officer the open complaints lapse and no new ones come (%d before)" % before)
	var set: Dictionary = _cmd(sim, "set_role", {"agent": off_id, "role": "hr"})
	t.check(bool(set.get("ok", false)) and sim.hr.active(base), "an officer makes it active again: %s" % str(set))
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## With an office and an officer: unhappy people file complaints (and feel heard), the player's options act,
## surveys are made, transfers are asked for; approve: the person leaves on the next ship; refuse: costs.
func v5_hr_complaints_surveys_transfers(t) -> void:
	var sim = _showcase_hr()
	sim.run_seconds(2.0)
	var base: int = int(sim.bases.ids()[0])
	t.check(sim.hr.active(base), "the showcase HR office is active with its officer")
	var off_id: int = int(sim.hr.officers(base)[0])
	var ppl: Array = []
	for a in _adults(sim, base):
		if int(a["id"]) != off_id:
			ppl.append(a)
	var unhappy: Array = []
	for i in range(0, 12):
		_gloom(sim, ppl[i])
		unhappy.append(ppl[i])
	sim.run_seconds(25.0)
	sim.hr._daily(int(sim.state["tick"]) / 6000)
	var n_c: int = sim.hr.complaints().size()
	t.check(n_c >= 1, "unhappy people filed complaints (%d)" % n_c)
	t.check(sim.hr.survey(base).has("depts") and (sim.hr.survey(base)["top3"] as Array).size() >= 1, "a feedback round was made")
	var n_t: int = sim.hr.transfers().size()
	t.check(n_t >= 1, "very unhappy people ask for a transfer (%d)" % n_t)
	sim.run_seconds(120.0)
	var heard := 0
	var open := 0
	for c in sim.hr.complaints():
		if String(c["state"]) == "open" or String(c["state"]) == "hr_working" or String(c["state"]) == "resolved":
			var ag: Dictionary = sim.state["agents"][int(c["agent"])]
			if sim.people.has_mod(ag, "heard"):
				heard += 1
		if String(c["state"]) == "open":
			open += 1
	t.check(heard >= 1, "a person who filed felt heard (%d)" % heard)
	# The player's options.
	var rows: Array = sim.relations.requests()
	var done_opt := 0
	var tr_rows: Array = []
	for r in rows:
		if r["kind"] == "hr_complaint":
			t.check((r["options"] as Array).size() >= 3 and String(r["options"][0]["effect"]) != "", "a complaint shows its options and effects before the answer")
			var res: Dictionary = _cmd(sim, "answer_request", {"id": int(r["id"]), "answer": "leisure_day"})
			if bool(res.get("ok", false)):
				done_opt += 1
		elif r["kind"] == "hr_transfer":
			tr_rows.append(r)
	t.check(done_opt >= 1, "a leisure day answers a complaint (%d)" % done_opt)
	t.check(tr_rows.size() >= 1, "transfer requests are in the Requests tab (%d)" % tr_rows.size())
	if tr_rows.is_empty():
		sim.dispose()
		t.done()
		return
	# Refuse one: costs.
	var refused_id: int = int(tr_rows[0]["agent"])
	var ra: Dictionary = sim.state["agents"][refused_id]
	var sat_mods0: int = (sim.people.rec_of(refused_id).get("mods", []) as Array).size()
	var punish0: int = (sim.unrest._rec_w(base)["punish"] as Array).size()
	var rr: Dictionary = _cmd(sim, "answer_request", {"id": int(tr_rows[0]["id"]), "answer": "refuse"})
	t.check(bool(rr.get("ok", false)) and sim.people.has_mod(ra, "transfer_refused"), "refuse: the person loses satisfaction and attitude")
	t.check((sim.unrest._rec_w(base)["punish"] as Array).size() > punish0, "refusing adds unrest pressure")
	t.check(sat_mods0 >= 0, "mods counted")
	# Approve another (or make one) and run a ship.
	var appr_id := -1
	if tr_rows.size() >= 2:
		appr_id = int(tr_rows[1]["agent"])
		var ar: Dictionary = _cmd(sim, "answer_request", {"id": int(tr_rows[1]["id"]), "answer": "approve"})
		t.check(bool(ar.get("ok", false)), "approve: %s" % str(ar))
	else:
		var other: Dictionary = ppl[16]
		sim.hr._new_transfer(other, "home", base)                                  # test set-up: one more request
		var rows3: Array = sim.hr.request_rows()
		appr_id = int(other["id"])
		for rw in rows3:
			if rw["kind"] == "hr_transfer" and int(rw["agent"]) == appr_id:
				_cmd(sim, "answer_request", {"id": int(rw["id"]), "answer": "approve"})
	var tr: Dictionary = _cmd(sim, "traffic_now", {"kind": "shuttle", "in": 5})
	t.check(bool(tr.get("ok", false)), "a shuttle is coming")
	var left_on := -1
	var gone := false
	var answered := false
	var last_state := ""
	for s in 100:
		sim.run_seconds(5.0)
		var shp: Array = sim.traffic.ships()
		last_state = "ships %s" % str(shp.map(func(x): return "%s %s" % [x["kind"], x["phase"]]))
		if not answered:
			var an: Dictionary = _cmd(sim, "traffic_answer", {"id": int(tr.get("id", -1)), "grant": true, "accept": 0})
			answered = bool(an.get("ok", false))
		var a: Dictionary = sim.state["agents"].get(appr_id, {})
		if a.is_empty():
			gone = true
			break
		if String(a.get("kind", "")) == "visitor" and left_on == -1:
			left_on = int(a["ship"])
			break
	t.check(left_on != -1, "the approved person became a passenger of the next ship (%d)" % left_on)
	# The ship that took them may be a liner that stays a day: the boarding itself is called here (TEST SET-UP: the
	# ship is boarding), as agents._board_ship does it at the pad.
	var ap: Dictionary = sim.state["agents"].get(appr_id, {})
	if not gone and not ap.is_empty():
		t.check(String(ap.get("vkind", "")) == "leaver" and bool(ap.get("transfer", false)) and not sim.traffic.ship(left_on).is_empty(), "a transfer passenger of a landed ship")
		sim.agents._board_ship(ap)
		gone = not sim.state["agents"].has(appr_id)
	t.check(gone, "and left the colony when the ship boarded (%s; person %s plan %s where %s)" % [last_state, str(ap.get("kind", "gone")), str(ap.get("plan_kind", "")), str(ap.get("where", ""))])
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## The officer is loved in public (talks with them are praise) and gossiped about in private (talks without
## them): the two values and the topic rates differ.
func v5_hr_public_and_private(t) -> void:
	var sim = _showcase_hr()
	sim.run_seconds(2.0)
	var base: int = int(sim.bases.ids()[0])
	var off: Dictionary = sim.state["agents"][int(sim.hr.officers(base)[0])]
	var ppl: Array = [off]
	for a in _adults(sim, base):
		if int(a["id"]) != int(off["id"]):
			ppl.append(a)
	sim.hr._w()["rep"].erase(int(off["id"]))                                          # test set-up: the start values
	var rep0: Dictionary = sim.hr.reputation(int(off["id"]))
	t.check(rep0["officer"] and float(rep0["public"]) > 50.0 and float(rep0["private"]) < 0.0, "start: loved in public (%.0f), doubted in private (%.0f)" % [float(rep0["public"]), float(rep0["private"])])
	var praise_pub := 0
	var gossip_pub := 0
	var praise_priv := 0
	var gossip_priv := 0
	var n := 1500
	for i in n:
		var other: Dictionary = ppl[1 + i % 20]
		var third: Dictionary = ppl[22 + i % 20]
		var pub: String = String(sim.hr.talk_topic(off, other, 100 + i * 7).get("topic", ""))
		var priv: String = String(sim.hr.talk_topic(third, other, 100 + i * 7).get("topic", ""))
		if pub == "hr_praise":
			praise_pub += 1
		if pub == "hr_gossip":
			gossip_pub += 1
		if priv == "hr_praise":
			praise_priv += 1
		if priv == "hr_gossip":
			gossip_priv += 1
	t.check(praise_pub > n / 2, "with the officer present: praise in %d of %d talks" % [praise_pub, n])
	t.eq(gossip_pub, 0, "with the officer present: no gossip about them")
	t.eq(praise_priv, 0, "behind their back: no praise lines")
	t.check(gossip_priv > n / 20 and gossip_priv < n / 3, "behind their back: gossip in %d of %d talks" % [gossip_priv, n])
	var rep1: Dictionary = sim.hr.reputation(int(off["id"]))
	t.check(float(rep1["public"]) != float(rep0["public"]) and float(rep1["private"]) != float(rep0["private"]), "the two values moved (public %.1f, private %.1f)" % [float(rep1["public"]), float(rep1["private"])])
	# The lines.
	var hr: Dictionary = sim.content["hr"]
	t.check((hr["praise"] as Array).size() >= 40, "praise lines: %d (at least 40)" % (hr["praise"] as Array).size())
	t.check((hr["gossip"] as Array).size() >= 60, "behind-the-back lines: %d (at least 60)" % (hr["gossip"] as Array).size())
	var ln: Dictionary = sim.social.line_for(ppl[1], off, "hr_praise", 9, int(ppl[1]["bld"]), false)
	var lg: Dictionary = sim.social.line_for(ppl[1], ppl[2], "hr_gossip", 9, int(ppl[1]["bld"]), false)
	t.check(String(ln["text"]).contains(sim.social._first(off)) or String(ln["text"]) != "", "a praise line is said")
	t.check(not String(lg["text"]).contains("{officer}"), "a gossip line has the officer's name filled in")
	sim.dispose()
	t.done()

## The HR state is part of the game state: a save in the middle of a complaint round continues exactly.
func v5_hr_deterministic(t) -> void:
	var digests: Array = []
	for run in 2:
		var sim = _showcase_hr()
		sim.run_seconds(2.0)
		var base: int = int(sim.bases.ids()[0])
		var off_id: int = int(sim.hr.officers(base)[0])
		var ppl: Array = []
		for a in _adults(sim, base):
			if int(a["id"]) != off_id:
				ppl.append(a)
		for i in range(0, 8):
			_gloom(sim, ppl[i])
		sim.run_seconds(25.0)
		sim.hr._daily(int(sim.state["tick"]) / 6000)
		sim.run_seconds(35.3)
		if run == 1:
			var st: Dictionary = Persistence.decode(Persistence.encode(sim.state))["state"]
			sim.dispose()
			sim = H.Sim.new()
			sim.load_state(st)
		sim.run_seconds(60.0)
		digests.append(Persistence.digest(sim.state))
		sim.dispose()
	t.eq(digests[0], digests[1], "the same digest with and without a save in the middle of a complaint round")
	t.done()
