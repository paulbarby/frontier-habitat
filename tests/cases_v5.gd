extends RefCounted
## Version 5 tests (docs/V5_DESIGN.md): people, society, floors, the new buildings.
## Milestone 1: the API stubs return plausible, deterministic data.
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")

func tests() -> Array:
	return [
		["v5_people_api", v5_people_api],
		["v5_social_api", v5_social_api],
		["v5_buildings_and_floors", v5_buildings_and_floors],
		["v5_unrest_protest_and_strike", v5_unrest_protest_and_strike],
		["v5_discipline_and_reviews", v5_discipline_and_reviews],
		["v5_appoint_home_enrol", v5_appoint_home_enrol],
		["v5_society_deterministic", v5_society_deterministic],
		["v5_floors_and_lifts", v5_floors_and_lifts],
		["v5_dialogue_content", v5_dialogue_content],
		["long_v5_relationships_10_days", long_v5_relationships],
		["v5_affair_and_visitor_fling", v5_affair_and_visitor_fling],
	]

static func _showcase():
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	return sim

## Every person has a valid identity, skills, rank, outfit, home, satisfaction and attitude, and
## the same save gives the same answers.
func v5_people_api(t) -> void:
	var sim = _showcase()
	var twin = _showcase()
	var c: Dictionary = sim.content["people"]
	var bad: Array = []
	var commanders := {}
	var captains := {}
	for row in sim.people.list():
		var a: Dictionary = sim.state["agents"][row["id"]]
		var idn: Dictionary = sim.people.identity(a)
		if not c["variants"].has(idn["variant"]) or (idn["sex"] != "m" and idn["sex"] != "f"):
			bad.append("%s variant %s" % [row["name"], idn["variant"]])
		if int(idn["age"]) < 6 or int(idn["age"]) > 64 or float(idn["height"]) < 1.2 or float(idn["height"]) > 2.0:
			bad.append("%s age/height" % row["name"])
		var tr: Array = idn["traits"]
		if tr.size() < 2 or tr.size() > 3:
			bad.append("%s traits %s" % [row["name"], str(tr)])
		for pair in c["trait_conflicts"]:
			if tr.has(pair[0]) and tr.has(pair[1]):
				bad.append("%s conflicting traits" % row["name"])
		for k in ["skin", "hair"]:
			if float(idn["tint"][k]) < 0.0 or float(idn["tint"][k]) > 1.0:
				bad.append("%s tint" % row["name"])
		if not (c["outfits"] as Array).has(row["outfit"]):
			bad.append("%s outfit %s" % [row["name"], row["outfit"]])
		if a["where"] == "out" and row["outfit"] != "suit":
			bad.append("%s outside without a suit" % row["name"])
		for sk in sim.people.skills(a):
			var v: int = int(sim.people.skills(a)[sk])
			if v < 0 or v > 100:
				bad.append("%s skill %s" % [row["name"], sk])
		var sat: Dictionary = sim.people.satisfaction(a)
		if float(sat["value"]) < 0.0 or float(sat["value"]) > 100.0 or (sat["components"] as Dictionary).size() != 9:
			bad.append("%s satisfaction" % row["name"])
		var att: float = float(sim.people.attitude(a)["value"])
		if att < -100.0 or att > 100.0:
			bad.append("%s attitude" % row["name"])
		if row["rank"] == "commander":
			commanders[row["base"]] = int(commanders.get(row["base"], 0)) + 1
		if row["rank"] == "captain":
			var key: String = "%s:%s" % [str(row["base"]), row["department"]]
			captains[key] = int(captains.get(key, 0)) + 1
		var b2: Dictionary = twin.state["agents"][row["id"]]
		if twin.people.identity(b2) != idn or twin.people.outfit(b2) != row["outfit"] or twin.people.rank(b2) != sim.people.rank(a):
			bad.append("%s not deterministic" % row["name"])
	t.eq(bad, [], "every person is valid and deterministic")
	t.check(sim.people.list().size() >= 10, "people listed (%d)" % sim.people.list().size())
	var one := true
	for b in commanders:
		one = one and int(commanders[b]) == 1
	t.check(one and commanders.size() >= 1, "one commander per base: %s" % str(commanders))
	var cap_ok := true
	for k in captains:
		cap_ok = cap_ok and int(captains[k]) == 1
	t.check(cap_ok, "at most one captain per department and base: %s" % str(captains))
	var some: Dictionary = sim.people.list()[0]
	t.eq(sim.state.has("people"), false, "milestone 1 stores nothing in the save")
	t.check(String(sim.people.rank(sim.state["agents"][some["id"]])["title"]) != "", "a rank title")
	twin.dispose()
	sim.dispose()
	t.done()

## Conversations, recent lines, relationships, Rag issues and unrest.
func v5_social_api(t) -> void:
	var sim = _showcase()
	var seen := 0
	var lines := {}
	var got_recent := false
	for i in 1200:
		sim.step()
		if i % 10 == 0:
			for talk in sim.social.talks():
				seen += 1
				if not sim.social.recent_lines(int(talk["speaker"]), 3).is_empty():
					got_recent = true
				lines[talk["line"]] = true
				if String(talk["line"]).contains("{"):
					t.fail("an unfilled slot: %s" % talk["line"])
					break
	t.check(seen > 0, "people talk (%d talk samples, %d distinct lines)" % [seen, lines.size()])
	t.check(got_recent, "recent_lines returns the speaker's lines")
	var pos: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	t.check(sim.social.talks_near(pos, 5000.0).size() == sim.social.talks().size(), "talks_near covers the map with a large radius")
	var rel_n := 0
	var ok_rel := true
	for key in sim.state["v5"].get("rel", {}):
		var r: Dictionary = sim.state["v5"]["rel"][key]
		rel_n += 1
		ok_rel = ok_rel and float(r["aff"]) >= -100.0 and float(r["aff"]) <= 100.0 and float(r["att"]) >= 0.0 and float(r["att"]) <= 100.0
	t.check(rel_n > 0 and ok_rel, "pairs who talked are stored, values in range (%d)" % rel_n)
	var issues: Array = sim.social.rag_issues(30)
	t.check(issues.size() >= 3, "Rag issues (%d)" % issues.size())
	if not issues.is_empty():
		var iss: Dictionary = issues[0]
		t.eq(iss["masthead"], "THE REGOLITH RAG", "the masthead")
		t.check(String(iss["lead"]["headline"]) != "" and not String(iss["lead"]["headline"]).contains("{"), "a lead headline: %s" % iss["lead"]["headline"])
		t.check(iss["lead"].has("photo") and iss["lead"]["photo"].has("pose_hint"), "the lead has a photo spec")
	var u: Dictionary = sim.social.unrest(-1)
	t.check(["calm", "grumbling", "slowdown", "protest", "strike", "riot"].has(u["stage"]), "unrest stage %s (%.1f)" % [u["stage"], float(u["value"])])
	sim.dispose()
	t.done()

## The new structures: size labels, radii, floors, units, door slots; each can be placed on the
## Frontier map; floors of an agent.
func v5_buildings_and_floors(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	t.eq(sim.sizes.size_label("apartment_block", 1), "XXL", "the apartment block is XXL")
	t.eq(sim.sizes.size_label("super_dome", 1), "XXXXL", "the super dome is XXXXL")
	t.eq(sim.floors.floors_of("apartment_block"), 3, "3 floors")
	t.eq(sim.floors.floors_of("super_dome"), 5, "5 floors")
	t.near(float(sim.bdef("super_dome")["radius"]), 48.0, 0.001, "dome radius 48 m")
	t.eq(sim.sizes.sizes_of("residence_tube"), [1, 2, 3], "residence tube M, L, XL")
	for sz in [1, 2, 3]:
		var probe := {"id": -1, "def": "residence_tube", "size": sz, "radius": float(sim.sizes.def_for("residence_tube", sz)["radius"])}
		t.eq(sim.place.max_links(probe), [4, 5, 6][sz - 1], "residence tube door slots at size %d" % sz)
	t.eq(sim.place.max_links({"id": -1, "def": "super_dome", "size": 1, "radius": 48.0}), 12, "the dome has 12 gates")
	var units: Array = sim.floors.units({"id": -1, "def": "apartment_block", "size": 1})
	var pent := 0
	for u in units:
		if u["quality"] == "penthouse":
			pent += 1
			t.eq(int(u["beds"]), 4, "a penthouse has 3 bedrooms (4 adult beds)")
			t.eq(int(u.get("child_beds", -1)), 0, "a penthouse has no child beds")
	t.eq(units.size(), 12, "10 units + 2 penthouses")
	t.eq(pent, 2, "two penthouses on the top floor")
	var c: Vector2 = sim.world.center
	var placed := {}
	for def_id in ["residence_tube", "apartment_block", "retail", "park", "academy", "security_office", "jail", "super_dome"]:
		var sz: int = int(sim.sizes.sizes_of(def_id)[0])
		for r in range(60, 700, 20):
			if placed.has(def_id):
				break
			for k in 24:
				var p: Vector2 = sim.place.snap_pos(c + Vector2.RIGHT.rotated(k * TAU / 24.0) * float(r))
				if sim.place.check_building(def_id, p, 0.0, -1, sz) == "ok":
					var res: Dictionary = g.cmd("place_building", {"def": def_id, "x": p.x, "y": p.y, "rot": 0.0, "size": sz})
					if bool(res["ok"]):
						placed[def_id] = int(res["id"])
						break
		t.check(placed.has(def_id), "%s can be placed" % def_id)
	var a: Dictionary = sim.state["agents"].values()[0]
	t.eq(int(sim.floors.agent_floor(a)["floor"]), 0, "a person in a one-storey building is on floor 0")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- V5 society (sections 5 and 6)
static func _cmd(sim, kind: String, payload: Dictionary) -> Dictionary:
	var cid: int = sim.submit(kind, payload)
	sim.step()
	return sim.cmds.results.get(cid, {})

static func _colonists(sim) -> Array:
	var out: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child":
			out.append(a)
	return out

## A well run colony stays calm; a starved, tired and punished colony reaches protest and strike
## (work stops in a department), and a fair response (meeting the demand) brings unrest down.
func v5_unrest_protest_and_strike(t) -> void:
	var sim = _showcase()
	sim.run_seconds(600.0)
	var calm: Dictionary = sim.unrest.info(-1)
	t.check(float(calm["value"]) < 40.0, "a well run colony is under slowdown after a day (%.1f, %s)" % [float(calm["value"]), calm["stage"]])
	var ppl: Array = _colonists(sim)
	# Punishments seen by everybody: ration cuts for a third of the colony.
	for i in ppl.size():
		if i % 3 == 0:
			var r: Dictionary = _cmd(sim, "discipline", {"agent": int(ppl[i]["id"]), "action": "ration_cut", "days": 3.0})
			if not bool(r.get("ok", false)):
				t.fail("ration cut refused: %s" % str(r))
	var seen := {}
	var struck_dep := ""
	var idle_striker := false
	for s in 900:
		# TEST SET-UP: every colonist starved of rest and food (a badly run colony).
		for a in ppl:
			if a["state"] == "alive":
				a["morale"] = 0.0
				a["fatigue"] = maxf(float(a["fatigue"]), 85.0)
				if a.has("nutrition"):
					for k in a["nutrition"]:
						a["nutrition"][k] = minf(float(a["nutrition"][k]), 25.0)
		sim.run_seconds(1.0)
		var u: Dictionary = sim.unrest.info(-1)
		seen[String(u["stage"])] = true
		if String(u["stage"]) == "strike" and struck_dep == "":
			struck_dep = String(u["department"])
		if struck_dep != "" and not idle_striker:
			for a in ppl:
				if a["state"] == "alive" and sim.people.department(a) == struck_dep and a.has("v5_nowork"):
					idle_striker = true
		if seen.has("strike") and s > 400:
			break
	var info: Dictionary = sim.unrest.info(-1)
	t.check(seen.has("protest"), "protest reached (stages %s, now %.1f)" % [str(seen.keys()), float(info["value"])])
	t.check(seen.has("strike"), "strike reached (department %s)" % struck_dep)
	t.check(idle_striker, "strikers stop work (v5_nowork on the %s department)" % struck_dep)
	t.check(String(info["demand"]) != "", "the protest names a demand: %s" % info["demand"])
	var before: float = float(info["value"])
	var base: int = int(sim.bases.ids()[0]) if sim.bases.count() > 0 else -1
	var res: Dictionary = _cmd(sim, "unrest_response", {"base": base, "response": "meet_demand"})
	t.check(bool(res.get("ok", false)), "meet_demand accepted: %s" % str(res))
	var again: Dictionary = _cmd(sim, "unrest_response", {"base": base, "response": "meet_demand"})
	t.eq(String(again.get("code", "")), "cooldown", "the same response again at once is refused")
	sim.run_seconds(300.0)
	var after: float = float(sim.unrest.info(-1)["value"])
	t.check(after < before - 20.0, "unrest falls after the demand is met and the colony recovers (%.1f -> %.1f)" % [before, after])
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## Reviews and discipline: predictions, stored attitude, flags (no work, hunger), the unfair flag,
## refusals, and friends who see a punishment.
func v5_discipline_and_reviews(t) -> void:
	var sim = _showcase()
	sim.run_seconds(30.0)
	var ppl: Array = _colonists(sim)
	var a: Dictionary = ppl[0]
	var b: Dictionary = ppl[1]
	var pr: Dictionary = sim.people.predict(a, "ration_cut")
	var ok_shape: bool = pr.has("attitude") and pr.has("satisfaction") and pr.has("others") and pr.has("risk") and pr.has("unfair")
	t.check(ok_shape, "predict gives attitude, satisfaction, others, risk, unfair: %s" % str(pr))
	t.check(sim.people.predict(int(a["id"]), "excellent").has("attitude"), "predict takes an id and a review grade")
	t.check(sim.people.predict(a, "nonsense").is_empty(), "predict of an unknown action is empty")
	# TEST SET-UP: a good attitude makes a punishment unfair.
	sim.people.rec_w(a)["att"] = 40.0
	t.check(bool(sim.people.predict(a, "confine")["unfair"]), "a punishment of a person with a good attitude is unfair")
	t.check(not bool(sim.people.predict(a, "praise")["unfair"]), "praise is never unfair")
	var att0: float = float(sim.people.rec_w(b)["att"])
	var r1: Dictionary = _cmd(sim, "review", {"agent": int(b["id"]), "grade": "excellent"})
	t.check(bool(r1.get("ok", false)) and float(sim.people.rec_of(int(b["id"]))["att"]) > att0, "an excellent review raises attitude (%.1f -> %.1f)" % [att0, float(sim.people.rec_of(int(b["id"]))["att"])])
	t.eq(String(sim.people.rec_of(int(b["id"]))["review"]["grade"]), "excellent", "the review is stored")
	var r2: Dictionary = _cmd(sim, "discipline", {"agent": int(a["id"]), "action": "confine", "days": 1.0})
	t.check(bool(r2.get("ok", false)) and bool(r2.get("unfair", false)), "confine accepted and marked unfair: %s" % str(r2))
	t.check(a.has("v5_nowork") and a.has("v5_norec"), "confined: no work, no leisure")
	var took := false
	for s in 120:
		sim.step()
		if String(a["plan_kind"]) == "task":
			took = true
	t.check(not took, "a confined person takes no task in 12 s")
	t.check(float(sim.people.satisfaction(a)["components"]["freedom"]) < 50.0, "freedom falls while confined")
	var hist: Array = sim.people.rec_of(int(a["id"]))["hist"]
	t.check(not hist.is_empty() and String(hist.back()["text"]).contains("Confined"), "the history records it")
	# Ration cut: hunger rises faster than a twin's.
	var c: Dictionary = ppl[2]
	var h0: float = float(c["hunger"])
	var r3: Dictionary = _cmd(sim, "discipline", {"agent": int(c["id"]), "action": "ration_cut"})
	t.check(bool(r3.get("ok", false)) and c.has("v5_hunger"), "ration cut sets the hunger rate (%s)" % str(c.get("v5_hunger")))
	var had_post: bool = ["commander", "captain", "first_hand"].has(String(sim.people.rank(c)["rank"]))
	var r4: Dictionary = _cmd(sim, "discipline", {"agent": int(c["id"]), "action": "demote"})
	t.check(bool(r4.get("ok", false)) == had_post, "demote only a person with a post (%s: %s)" % [sim.people.rank(c)["rank"], str(r4)])
	var r5: Dictionary = _cmd(sim, "discipline", {"agent": int(c["id"]), "action": "jail"})
	t.check(bool(r5.get("ok", false)) and String(r5["text"]).contains("no jail"), "jail without a jail confines instead: %s" % r5.get("text", ""))
	t.eq(String(_cmd(sim, "discipline", {"agent": 999999, "action": "praise"}).get("code", "")), "invalid", "an unknown person is refused")
	var friends_hit := 0
	for x in ppl:
		if sim.people.has_mod(x, "friend_punished"):
			friends_hit += 1
	t.note("%d friends saw the punishments" % friends_hit)
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## Appointments, homes, the academy and the dance egg.
func v5_appoint_home_enrol(t) -> void:
	var sim = _showcase()
	sim.run_seconds(10.0)
	var ppl: Array = _colonists(sim)
	# A captain: the member of a department who is not its proposed captain.
	var target: Dictionary = {}
	var dep := ""
	for a in ppl:
		var rk: Dictionary = sim.people.rank(a)
		if ["crew", "specialist", "trainee"].has(String(rk["rank"])) and String(rk["department"]) != "":
			target = a
			dep = String(rk["department"])
			break
	t.check(not target.is_empty(), "a crew member to promote")
	if target.is_empty():
		sim.dispose()
		t.done()
		return
	var r1: Dictionary = _cmd(sim, "appoint", {"agent": int(target["id"]), "rank": "captain", "department": dep})
	t.check(bool(r1.get("ok", false)), "appoint captain: %s" % str(r1))
	t.eq(String(sim.people.rank(target)["rank"]), "captain", "the rank is captain")
	var caps := 0
	for a in ppl:
		var rk: Dictionary = sim.people.rank(a)
		if String(rk["rank"]) == "captain" and String(rk["department"]) == dep and int(rk["base"]) == int(sim.people.rank(target)["base"]):
			caps += 1
	t.eq(caps, 1, "one captain in the department")
	var r2: Dictionary = _cmd(sim, "appoint", {"agent": int(target["id"]), "rank": "commander"})
	t.eq(String(sim.people.rank(target)["rank"]), "commander", "appointed commander (%s)" % str(r2.get("text", "")))
	t.eq(String(_cmd(sim, "appoint", {"agent": int(target["id"]), "rank": "king"}).get("code", "")), "invalid", "an unknown rank is refused")
	# Home: a structure with a free bed.
	var mover: Dictionary = ppl[ppl.size() - 1]
	var dest := -1
	for bid in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][bid]
		if b["state"] == "active" and int(bid) != int(mover["bed"]) and int(sim.bd(b).get("beds", 0)) > 0 and sim.housing.free_beds(b) > 0 and (sim.bases.count() < 2 or sim.bases.base_of(int(bid)) == sim.bases.home_of(mover)):
			dest = int(bid)
			break
	if dest != -1:
		var r3: Dictionary = _cmd(sim, "set_home", {"agent": int(mover["id"]), "building": dest})
		t.check(bool(r3.get("ok", false)) and int(mover["bed"]) == dest, "set_home moves the bed: %s" % str(r3))
		sim.run_seconds(30.0)
		t.eq(int(mover["bed"]), dest, "the new bed is kept")
	else:
		t.note("no structure with a free bed in the showcase (set_home not tested)")
	# The academy (TEST SET-UP: an active academy placed at once).
	var spot := Vector2(-1, -1)
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	for rr in range(20, 200, 6):
		for k in 24:
			var q: Vector2 = sim.place.snap_pos(lander + Vector2(rr, 0).rotated(TAU * float(k) / 24.0))
			if spot.x < 0.0 and sim.place.check_building("academy", q, 0.0, -1, 1) == "ok":
				spot = q
		if spot.x >= 0.0:
			break
	var acad: Dictionary = sim.build.spawn_active("academy", spot, 0.0, 1) if spot.x >= 0.0 else {}
	t.check(not acad.is_empty(), "an academy for the test")
	if not acad.is_empty():
		# ppl[1] is on the expedition rover far out: the vehicle brings them home first
		# (vehicles._needs_guard) and they must be able to walk from the depot to air.
		var student: Dictionary = ppl[1]
		# The student's weakest skill (the console teaches it without a teacher).
		var sk: String = "cooking"
		var lowv := 1000
		for k in sim.people.skills(student):
			if int(sim.people.skills(student)[k]) < lowv:
				lowv = int(sim.people.skills(student)[k])
				sk = k
		var v0: int = int(sim.people.skills(student)[sk])
		var lv0: int = sim.people.level_of(float(v0))
		var r4: Dictionary = _cmd(sim, "enrol", {"agent": int(student["id"]), "skill": sk, "building": int(acad["id"])})
		t.check(bool(r4.get("ok", false)), "enrol: %s" % str(r4))
		t.check(student.has("v5_nowork") and sim.education.in_class(student), "a student does no other work")
		t.eq(sim.education.students(int(acad["id"])).size(), 1, "students() lists the student")
		var seats: int = sim.education.seats(acad)
		var n_ok := 1
		for x in ppl:
			if n_ok >= seats + 2:
				break
			if int(x["id"]) != int(student["id"]) and bool(_cmd(sim, "enrol", {"agent": int(x["id"]), "skill": sk, "building": int(acad["id"])}).get("ok", false)):
				n_ok += 1
		t.eq(n_ok, seats, "the academy takes %d students, no more" % seats)
		var waited := 0
		var trace: Array = []
		while sim.education.in_class(student) and waited < 3000:
			sim.run_seconds(50.0)
			waited += 50
			trace.append("%d:%s/%s th%d fa%d hp%d %s" % [waited, student["state"], student["where"], int(student["thirst"]), int(student["fatigue"]), int(student["health"]), student["goal"]])
		var v1: int = int(sim.people.skills(student)[sk])
		t.check(sim.people.level_of(float(v1)) == lv0 + 1 and not sim.education.in_class(student), "the course raises the level in %d s (%s %d L%d -> %d L%d; %s)" % [waited, sk, v0, lv0, v1, sim.people.level_of(float(v1)), str(sim.people.rec_of(int(student["id"])).get("hist", []).slice(-2)) + " " + String(student["state"]) + " " + String(student.get("cause", "")) + " " + String(student["role"]) + " " + str(trace.slice(-3)) + " " + str(sim.people.rec_of(int(student["id"])).keys())])
		t.check(not student.has("v5_nowork") or sim.unrest.on_strike(student), "the graduate works again")
	# The dance egg.
	var dancer: Dictionary = ppl[3]
	t.check(bool(_cmd(sim, "egg", {"kind": "dance", "agent": int(dancer["id"])}).get("ok", false)) and sim.people.action(dancer) == "dance", "the dance egg")
	sim.run_seconds(25.0)
	t.eq(sim.people.action(dancer), "", "the dance ends")
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## The v5 state is part of the game: two runs with the same orders end in the same state, and a
## save in the middle continues the same way.
func v5_society_deterministic(t) -> void:
	var digests: Array = []
	for run in 2:
		var sim = _showcase()
		var ppl: Array = _colonists(sim)
		_cmd(sim, "discipline", {"agent": int(ppl[0]["id"]), "action": "ration_cut"})
		_cmd(sim, "review", {"agent": int(ppl[1]["id"]), "grade": "poor"})
		sim.run_seconds(120.0)
		# A save and load in the middle (the second run only): the same continuation.
		if run == 1:
			var bytes: PackedByteArray = Persistence.encode(sim.state)
			var st: Dictionary = Persistence.decode(bytes)["state"]
			sim.dispose()
			sim = H.Sim.new()
			sim.load_state(st)
		sim.run_seconds(120.0)
		t.check(sim.state.has("v5") and sim.state["v5"]["people"].size() > 0, "state.v5 kept (%d records)" % (sim.state["v5"]["people"].size() if sim.state.has("v5") else 0))
		digests.append(Persistence.digest(sim.state))
		sim.dispose()
	t.eq(digests[0], digests[1], "the same digest with and without a save in the middle")
	t.done()

## Floors: anchors are numbered floor by floor (slot_floor); a person takes the floor of the anchor
## they use; a change of floor is a lift ride that holds the person for lift_seconds; adults never
## take a child bed.
func v5_floors_and_lifts(t) -> void:
	var sim = _showcase()
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var spot := Vector2(-1, -1)
	for rr in range(60, 600, 10):
		for k in 24:
			var q: Vector2 = sim.place.snap_pos(lander + Vector2(rr, 0).rotated(TAU * float(k) / 24.0))
			if spot.x < 0.0 and sim.place.check_building("apartment_block", q, 0.0, -1, 1) == "ok":
				spot = q
		if spot.x >= 0.0:
			break
	var blk: Dictionary = sim.build.spawn_active("apartment_block", spot, 0.0, 1)       # test set-up
	t.check(not blk.is_empty(), "an apartment block for the test")
	if blk.is_empty():
		sim.dispose()
		t.done()
		return
	var cases := [["bed", 0, 0], ["bed", 9, 0], ["bed", 10, 1], ["bed", 19, 1], ["bed", 20, 2], ["bed", 27, 2], ["child_bed", 5, 0], ["child_bed", 15, 1],
		["seat", 4, 0], ["seat", 5, 1], ["seat", 12, 2], ["stand", 5, 2]]
	for c in cases:
		t.eq(sim.floors.slot_floor(blk, c[0], c[1]), c[2], "%s %d is on floor %d" % [c[0], c[1], c[2]])
	t.eq(sim.agents._slot_cap("bed", int(blk["id"])), 28, "28 adult beds (the 20 bunks are for children)")
	t.eq(sim.agents._slot_cap("child_bed", int(blk["id"])), 20, "20 child beds")
	# TEST SET-UP: a person inside the block takes a penthouse bed.
	var a: Dictionary = {}
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["where"] == "in":
			a = x
			break
	a["bld"] = int(blk["id"])
	a["pos"] = blk["pos"]
	a["use"] = {"kind": "bed", "b": int(blk["id"]), "i": 24, "pose": "lie", "act": "sleep"}
	sim.floors.on_use(a)
	var f: Dictionary = sim.floors.agent_floor(a)
	t.eq(int(f["floor"]), 2, "the penthouse bed is on floor 2")
	t.near(float(f["height"]), 7.2, 0.01, "floor 2 is 7.2 m up")
	t.check(not (f["lift"] as Dictionary).is_empty() and int(f["lift"]["from"]) == 0 and int(f["lift"]["to"]) == 2, "the person rides the lift from floor 0 to 2: %s" % str(f["lift"]))
	var ride: int = int(f["lift"]["t1"]) - int(f["lift"]["t0"])
	t.eq(ride, int(ceil(sim.floors.lift_seconds(blk, 0, 2) * float(sim.bal["tick_hz"]))), "the ride takes lift_seconds (%d ticks)" % ride)
	a["use"] = {"kind": "seat", "b": int(blk["id"]), "i": 11, "pose": "sit", "act": "relax"}
	sim.floors.on_use(a)
	t.eq(int(sim.floors.agent_floor(a)["floor"]), 2, "a penthouse seat on the same floor: no ride")
	sim.dispose()
	t.done()

## The dialogue (section 4.1 and the request: 600 lines or more, 25 topics or more): every slot is
## one the game fills, every trait exists, and a day of the showcase uses many topics.
func v5_dialogue_content(t) -> void:
	var sim = _showcase()
	var d: Dictionary = sim.content["dialogue"]["topics"]
	var n := 0
	var bad: Array = []
	var slots := ["{other}", "{building}", "{place}", "{captain}", "{commander}", "{base}", "{days}", "{resource}"]
	var traits: Array = sim.content["people"]["traits"]
	var re := RegEx.new()
	re.compile("[{][a-z_]+[}]")
	for topic in d:
		for l in d[topic]:
			n += 1
			var text: String = String(l["text"]) if typeof(l) == TYPE_DICTIONARY else String(l)
			if typeof(l) == TYPE_DICTIONARY and not traits.has(String(l.get("trait", ""))):
				bad.append("%s: unknown trait %s" % [topic, l.get("trait")])
			for m in re.search_all(text):
				if not slots.has(m.get_string()):
					bad.append("%s: unknown slot %s" % [topic, m.get_string()])
			if text.length() > 70:
				bad.append("%s: long line (%d)" % [topic, text.length()])
	t.check(n >= 600, "600 lines or more (%d)" % n)
	t.check(d.size() >= 25, "25 topics or more (%d)" % d.size())
	t.eq(bad, [], "slots, traits and lengths")
	var topics := {}
	var lines := {}
	for i in 6000:
		sim.step()
		if i % 20 == 0:
			for talk in sim.social.talks():
				topics[talk["topic"]] = true
				lines[talk["line"]] = true
				if String(talk["line"]).contains("{"):
					bad.append("unfilled: " + String(talk["line"]))
	t.check(topics.size() >= 8, "a day of talk uses 8 topics or more (%d: %s)" % [topics.size(), str(topics.keys())])
	t.check(lines.size() >= 60, "60 different lines or more in a day (%d)" % lines.size())
	t.eq(bad, [], "no unfilled slot in play")
	sim.dispose()
	t.done()

## Relationships over 10 game days of the showcase: friendships and romance form from talks, and
## two runs from the same save give the same graph (section 11: "reproducible").
func long_v5_relationships(t) -> void:
	var digests: Array = []
	var summary := ""
	for run in 2:
		var sim = _showcase()
		sim.run_seconds(10.0 * 600.0)
		var counts := {}
		var rel: Dictionary = sim.state["v5"].get("rel", {})
		for k in rel:
			var st: String = String(rel[k]["status"])
			counts[st] = int(counts.get(st, 0)) + 1
		var codes := {}
		for e in sim.state["log"]:
			if ["couple", "partners", "wedding", "breakup", "affair", "fling", "feud"].has(String(e["code"])):
				codes[e["code"]] = int(codes.get(e["code"], 0)) + 1
		var max_att := 0.0
		var max_talks := 0
		var sum_talks := 0
		for k in rel:
			max_att = maxf(max_att, float(rel[k]["att"]))
			max_talks = maxi(max_talks, int(rel[k]["talks"]))
			sum_talks += int(rel[k]["talks"])
		summary = "%d pairs %s; log %s; talks %d (max %d a pair), max attraction %.0f" % [rel.size(), str(counts), str(codes), sum_talks, max_talks, max_att]
		digests.append(var_to_str(rel).hash())
		if run == 0:
			t.check(int(counts.get("friend", 0)) + int(counts.get("best_friend", 0)) >= 5, "5 or more friendships in 10 days (%s)" % str(counts))
			var romance: int = 0
			for st in ["crush", "dating", "partners", "married", "affair", "fling", "ex"]:
				romance += int(counts.get(st, 0))
			t.check(romance >= 1, "romance happens (%s)" % str(counts))
			t.eq(sim.inv.audit(), {}, "ledger")
		sim.dispose()
	t.eq(digests[0], digests[1], "the same graph in two runs")
	t.note(summary)
	t.done()

## An affair is found out (scandal, the cheated partner breaks up); a colonist in love with a
## visitor asks to leave with the ship; the player's answer is applied.
func v5_affair_and_visitor_fling(t) -> void:
	var sim = _showcase()
	sim.run_seconds(5.0)
	var ppl: Array = _colonists(sim)
	var a: Dictionary = ppl[0]
	var b: Dictionary = ppl[1]
	var c: Dictionary = ppl[2]
	# TEST SET-UP: a and b are partners; a has an affair with c.
	var rel: Dictionary = sim.relations._w()["rel"]
	var now: int = int(sim.state["tick"])
	rel[sim.relations.key_of(int(a["id"]), int(b["id"]))] = {"a": mini(int(a["id"]), int(b["id"])), "b": maxi(int(a["id"]), int(b["id"])), "aff": 60.0, "att": 80.0, "status": "partners", "since": now, "last": now, "talks": 30}
	rel[sim.relations.key_of(int(a["id"]), int(c["id"]))] = {"a": mini(int(a["id"]), int(c["id"])), "b": maxi(int(a["id"]), int(c["id"])), "aff": 50.0, "att": 90.0, "status": "affair", "since": now, "last": now, "talks": 30}
	sim.relations._bump()
	t.eq(sim.relations.partner_of(int(a["id"])), int(b["id"]), "a's partner is b")
	var found := false
	for d in 12:
		sim.run_seconds(600.0)
		for e in sim.state["log"]:
			if String(e["code"]) == "affair":
				found = true
		if found:
			break
	t.check(found, "the affair is found out within 12 days (a scandal in the log; %s %s %s, pairs %d)" % [a["state"], b["state"], c["state"], sim.state["v5"]["rel"].size()])
	t.eq(String(sim.relations.relation(a, b)["status"]), "ex", "the cheated partner breaks up")
	# A visitor fling and the request to leave.
	var vis: Dictionary = {}
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and String(x.get("kind", "")) == "visitor":
			vis = x
			break
	if vis.is_empty():
		t.note("no visitor in the showcase at this time (fling not tested)")
	else:
		var col: Dictionary = ppl[3]
		rel[sim.relations.key_of(int(col["id"]), int(vis["id"]))] = {"a": mini(int(col["id"]), int(vis["id"])), "b": maxi(int(col["id"]), int(vis["id"])), "aff": 50.0, "att": 95.0, "status": "fling", "since": now, "last": now, "talks": 20}
		sim.relations._bump()
		var asked := false
		for d in 12:
			sim.run_seconds(100.0)
			if not sim.relations.requests().is_empty():
				asked = true
				break
		t.check(asked, "the colonist asks to leave with the visitor's ship")
		if asked:
			var q: Dictionary = sim.relations.requests()[0]
			var cid: int = sim.submit("answer_request", {"id": int(q["id"]), "answer": "refuse"})
			sim.step()
			t.check(bool(sim.cmds.results[cid]["ok"]) and sim.people.has_mod(col, "refused_leave"), "refuse: the colonist stays, unhappy")
			t.check(sim.relations.requests().is_empty(), "the request is answered")
	sim.dispose()
	t.done()
