extends RefCounted
## Version 5 tests (docs/V5_DESIGN.md): people, society, floors, the new buildings.
## Milestone 1: the API stubs return plausible, deterministic data.
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")
const Pacer = preload("res://tests/pacer.gd")
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
		["v5_fight_arrest_jail", v5_fight_arrest_jail],
		["v5_lock_down_and_party", v5_lock_down_and_party],
		["v5_families_and_children", v5_families_and_children],
		["v5_venues_and_tourism", v5_venues_and_tourism],
		["v5_dome_build_stages", v5_dome_build_stages],
		["v5_rag_stored_issues", v5_rag_stored_issues],
		["v5_multistorey_paths", v5_multistorey_paths],
		["v5_migration_old_saves", v5_migration_old_saves],
		["v5_eggs", v5_eggs],
		["v5_showcase", v5_showcase],
		["long_v5_perf_showcase", long_v5_perf_showcase],
		["v5_showcase_deterministic", v5_showcase_deterministic],
		["v5_protest_and_riot", v5_protest_and_riot],
		["v5_planet_hazards", v5_planet_hazards],
		["v5_flee_privilege_skills", v5_flee_privilege_skills],
		["v5_liner_family_shared_home", v5_liner_family_shared_home],
		["v5_leave_request_ends_with_ship", v5_leave_request_ends_with_ship],
		["v5_best_dressed_by_clothes", v5_best_dressed_by_clothes],
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
	# The academy (TEST SET-UP: an active academy joined by a corridor to the base).
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var acad: Dictionary = H.attach(sim, "academy", lander, 1)
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
		var seen_in_class := false
		var moved_without := false
		var last_p: float = 0.0
		while sim.education.in_class(student) and waited < 4000:
			for s5 in 10:
				sim.run_seconds(5.0)
				var c5: Dictionary = sim.state["v5"]["courses"].get(int(student["id"]), {})
				if c5.is_empty():
					break
				var here: bool = student["where"] == "in" and int(student["bld"]) == int(acad["id"]) and sim.agents._step_op(student) == "class"
				if here:
					seen_in_class = seen_in_class or sim.people.action(student) == "sit_class"
				elif float(c5["progress"]) > last_p + 0.0001 and student["where"] == "in" and int(student["bld"]) != int(acad["id"]):
					moved_without = true
				last_p = float(c5["progress"])
			waited += 50
			trace.append("%d:%s/%s th%d fa%d hp%d %s" % [waited, student["state"], student["where"], int(student["thirst"]), int(student["fatigue"]), int(student["health"]), student["goal"]])
		t.check(seen_in_class, "the student walked to the academy and sat in class (action sit_class)")
		t.check(not moved_without, "the course moves on only in class")
		var v1: int = int(sim.people.skills(student)[sk])
		t.check(sim.people.level_of(float(v1)) == lv0 + 1 and not sim.education.in_class(student), "the course raises the level in %d s (%s %d L%d -> %d L%d; %s)" % [waited, sk, v0, lv0, v1, sim.people.level_of(float(v1)), str(sim.people.rec_of(int(student["id"])).get("hist", []).slice(-2)) + " " + String(student["state"]) + " " + String(student.get("cause", "")) + " " + String(student["role"]) + " " + str(trace.slice(-3)) + " " + str(sim.people.rec_of(int(student["id"])).keys())])
		t.check(not student.has("v5_nowork") or sim.unrest.on_strike(student), "the graduate works again")
	# The dance egg.
	var dancer: Dictionary = ppl[3]
	t.check(bool(_cmd(sim, "egg", {"kind": "dance", "agent": int(dancer["id"])}).get("ok", false)) and sim.people.action(dancer) == "dance_c", "the dance egg (dance_c)")
	t.check(sim.eggs.found("dance") and not sim.social.recent_lines(int(dancer["id"]), 1).is_empty(), "the dance egg is found and the dancer says a line")
	sim.run_seconds(25.0)
	t.check(sim.people.action(dancer) != "dance_c", "the dance ends")
	t.check(sim.awards.earned("egg_dance"), "award Dance Floor Director")
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

# ---------------------------------------------------------------- V5 milestone: security, families, venues, Rag
## A person by id, alive, of the colony (not a visitor, not a child), inside, awake.
static func _awake_inside(sim, skip: Array = []) -> Array:
	var out: Array = []
	for a in _colonists(sim):
		if a["where"] == "in" and not bool(a.get("sleeping", false)) and not skip.has(int(a["id"])) and float(a["health"]) > 60.0 and not a.has("lift"):
			out.append(a)
	return out

## A fight between enemies ends with an arrest by a security officer; the prisoner is walked to a
## cell (handcuffed_walk), wears prison clothes, stays in the jail and is released when the time is up.
func v5_fight_arrest_jail(t) -> void:
	var sim = _showcase()
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	sim.run_seconds(5.0)
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var jail: Dictionary = H.attach(sim, "jail", lander, 1)
	var office: Dictionary = H.attach(sim, "security_office", lander, 0)
	t.check(not jail.is_empty() and not office.is_empty(), "a jail and a security office for the test")
	if jail.is_empty():
		sim.dispose()
		t.done()
		return
	var ppl: Array = _awake_inside(sim)
	var off: Dictionary = ppl[ppl.size() - 1]
	var low: Dictionary = ppl[ppl.size() - 2]
	# TEST SET-UP: a colonist trained in security (the academy's job) becomes an officer.
	t.eq(String(_cmd(sim, "set_role", {"agent": int(low["id"]), "role": "security"}).get("code", "")), "refused", "an officer needs the security skill")
	sim.people.rec_w(off)["skill_bonus"] = {"security": 60}
	sim.people.invalidate(int(off["id"]))
	var r0: Dictionary = _cmd(sim, "set_role", {"agent": int(off["id"]), "role": "security"})
	t.check(bool(r0.get("ok", false)) and String(off["role"]) == "security", "set_role security: %s" % str(r0))
	var patrol := false
	for s0 in 60:
		sim.run_seconds(1.0)
		if String(off.get("plan_kind", "")) == "patrol" and sim.people.outfit(off) == "uniform_security":
			patrol = true
			break
	t.check(patrol, "the officer patrols in the security uniform")
	var x: Dictionary = {}
	var y: Dictionary = {}
	for a in _awake_inside(sim, [int(off["id"])]):
		if x.is_empty():
			x = a
		elif y.is_empty():
			y = a
	# TEST SET-UP: y stands in x's room; the two are enemies.
	H.put_inside(sim, y, int(x["bld"]))
	var rel: Dictionary = sim.relations._rel_w(x, y)
	rel["aff"] = -60.0
	rel["status"] = "enemy"
	sim.relations._bump()
	var fid: int = sim.security.start_fight(x, y, "test")
	t.check(fid != -1 and String(x.get("v5_hold", "")) == "fight", "a fight starts (%d)" % fid)
	t.check(["fight_idle", "punch", "hit_react"].has(sim.people.action(x)), "a fighter plays a fight clip: %s" % sim.people.action(x))
	var f0: Dictionary = sim.state["v5"]["fights"].get(fid, {})
	t.eq(int(f0.get("officer", -1)), int(off["id"]), "the officer is sent to the fight")
	var cuffed := false
	var ended := false
	for s in 1200:
		sim.step()
		if not sim.state["v5"]["fights"].has(fid):
			ended = true
		for a in [x, y]:
			if String(a.get("v5_hold", "")) == "cuffed" and sim.people.action(a) == "handcuffed_walk":
				cuffed = true
		if ended and (x.has("jailed") or y.has("jailed")) and s > 50:
			var pz: Dictionary = x if x.has("jailed") else y
			if int(pz["bld"]) == int(jail["id"]) and pz["where"] == "in" and not pz.has("v5_hold"):
				break
	t.check(ended, "the fight ended")
	t.check(not H.log_entries(sim, "fight").is_empty() and not H.log_entries(sim, "arrest").is_empty(), "fight and arrest are in the log")
	var pr: Dictionary = x if x.has("jailed") else y
	t.check(pr.has("jailed") and int(pr.get("cell_b", -1)) == int(jail["id"]), "the one with the worse attitude is jailed in a cell of the jail")
	t.check(cuffed, "the prisoner walked to the cell in handcuffs")
	t.check(int(pr["bld"]) == int(jail["id"]), "the prisoner reached the jail (in %s)" % str(pr["bld"]))
	t.eq(sim.people.outfit(pr), "prison", "a prisoner wears prison clothes")
	var left := false
	for k in 120:
		sim.run_seconds(5.0)
		if pr.has("jailed") and (pr["where"] != "in" or int(pr["bld"]) != int(jail["id"])) and String(pr.get("plan_kind", "")) != "jail" and String(pr.get("plan_kind", "")) != "safety":
			left = true
		if not pr.has("jailed"):
			break
	t.check(not left, "the prisoner stays in the jail (eats, drinks and sleeps there)")
	sim.run_seconds(2.0)
	t.check(not pr.has("jailed") and not pr.has("cell_b") and not H.log_entries(sim, "released").is_empty(), "released when the time is up")
	t.eq(sim.security.info(-1)["officers"], 1, "one officer")
	var rag_kinds := {}
	for e in sim.state["v5"]["slog"]:
		rag_kinds[String(e["kind"])] = true
	t.check(rag_kinds.has("fight") and rag_kinds.has("arrest"), "the fight and the arrest are in the social log: %s" % str(rag_kinds.keys()))
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## A lock-down keeps people in their rooms for 2 game hours; a party uses drinks, snacks or rations
## and is refused without them; the response effects are predicted.
func v5_lock_down_and_party(t) -> void:
	var sim = _showcase()
	sim.run_seconds(20.0)
	var base: int = int(sim.bases.ids()[0]) if sim.bases.count() > 0 else -1
	var eff: Dictionary = sim.unrest.response_effect(base, "party")
	t.check(eff.has("unrest") and String(eff["cost"]).contains("drinks"), "response_effect: %s" % str(eff))
	var items: Array = sim.content["society"]["party"]["items"]
	var need: int = sim.unrest._party_need(base)
	var before: int = sim.leisure.count_stock(base, items)
	var r1: Dictionary = _cmd(sim, "unrest_response", {"base": base, "response": "party"})
	if before >= need:
		t.check(bool(r1.get("ok", false)), "party accepted with stock (%d of %d): %s" % [need, before, str(r1)])
		t.eq(sim.leisure.count_stock(base, items), before - need, "the party used %d units" % need)
	else:
		t.eq(String(r1.get("code", "")), "no_stock", "a party without stock is refused")
	var r2: Dictionary = _cmd(sim, "unrest_response", {"base": base, "response": "lock_down"})
	t.check(bool(r2.get("ok", false)) and sim.unrest.locked(base) and bool(sim.unrest.info(base)["locked"]), "lock_down: the base is locked")
	var moved: Array = []
	var start := {}
	for a in _colonists(sim):
		if a["where"] == "in" and (a["plan"] as Array).is_empty():
			start[int(a["id"])] = int(a["bld"])
	for s in 300:
		sim.step()
		for a in _colonists(sim):
			var k: String = String(a.get("plan_kind", ""))
			if start.has(int(a["id"])) and (k == "task" or k == "rec" or k == "patrol" or k == "staff"):
				if not moved.has(int(a["id"])):
					moved.append(int(a["id"]))
	t.eq(moved, [], "nobody idle at the lock starts work or leisure elsewhere while locked")
	sim.run_seconds(40.0)
	t.check(not sim.unrest.locked(base), "the lock-down ends after 2 game hours")
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()
## Partners move in together; partners adopt through a medical bay; the child lives in their unit,
## never works, goes to school at the academy and grows up into a colonist.
func v5_families_and_children(t) -> void:
	var sim = _showcase()
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	sim.run_seconds(5.0)
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var tube: Dictionary = H.attach(sim, "residence_tube", lander, 2)
	var acad: Dictionary = H.attach(sim, "academy", lander, 1)
	var bay: int = -1
	for id in sim.state["buildings"]:
		if String(sim.state["buildings"][id]["def"]) == "medical" and sim.state["buildings"][id]["state"] == "active":
			bay = int(id)
	if bay == -1:
		bay = int(H.attach(sim, "medical", lander, 1).get("id", -1))
	t.check(not tube.is_empty() and not acad.is_empty() and bay != -1, "a residence tube, an academy and a medical bay")
	if tube.is_empty() or acad.is_empty():
		sim.dispose()
		t.done()
		return
	var x: Dictionary = {}
	var y: Dictionary = {}
	var ppl: Array = _colonists(sim)
	for i in ppl.size():
		for j in range(i + 1, ppl.size()):
			if x.is_empty() and sim.social.compatible(ppl[i], ppl[j]):
				x = ppl[i]
				y = ppl[j]
	t.check(not x.is_empty(), "a compatible pair")
	# TEST SET-UP: the two are partners (the romance chain is tested in long_v5_relationships).
	var rel: Dictionary = sim.relations._rel_w(x, y)
	rel["aff"] = 70.0
	rel["att"] = 80.0
	rel["status"] = "partners"
	sim.relations._bump()
	sim.families.on_partners(x, y)
	var ux: int = int(sim.people.rec_of(int(x["id"])).get("unit", -1))
	t.check(int(x["bed"]) == int(y["bed"]) and ux >= 0 and ux == int(sim.people.rec_of(int(y["id"])).get("unit", -2)), "partners share a unit (%s %d / %s)" % [str(x["bed"]), ux, str(y["bed"])])
	t.eq(sim.people.home(x)["kind"], "family", "their home is a family unit")
	t.check(not H.log_entries(sim, "move_in").is_empty(), "the move is in the log")
	var r1: Dictionary = _cmd(sim, "adopt", {"agent": int(x["id"])})
	t.check(bool(r1.get("ok", false)), "adopt: %s" % str(r1))
	sim.run_seconds(610.0)
	var kids: Array = sim.families.children_of(int(x["id"]))
	t.eq(kids.size(), 1, "the child came after a day")
	if kids.is_empty():
		sim.dispose()
		t.done()
		return
	var c: Dictionary = sim.state["agents"][kids[0]]
	var idn: Dictionary = sim.people.identity(c)
	t.check(bool(idn["child"]) and ["c1", "c2"].has(idn["variant"]) and int(idn["age"]) >= 6 and int(idn["age"]) <= 12, "a child: %s, %d" % [idn["variant"], int(idn["age"])])
	t.eq(String(sim.people.rank(c)["rank"]), "child", "rank child")
	t.check(not H.log_entries(sim, "adoption").is_empty(), "the adoption is in the log")
	var worked := false
	var school := false
	var discipline: Dictionary = _cmd(sim, "discipline", {"agent": int(c["id"]), "action": "ration_cut"})
	t.eq(String(discipline.get("code", "")), "refused", "a child is never disciplined")
	for s in 120:
		sim.run_seconds(5.0)
		if String(c.get("plan_kind", "")) == "task":
			worked = true
		if String(c.get("plan_kind", "")) == "class" and int(c["bld"]) == int(acad["id"]) and sim.people.outfit(c) == "school":
			school = true
	t.check(not worked, "a child takes no work")
	t.check(school, "the child went to school in the school uniform")
	t.check(int(c["bed"]) == int(x["bed"]), "the child lives in the parents' home")
	var sch: Dictionary = sim.state["v5"]["school"].get(int(c["id"]), {})
	t.check(not sch.is_empty(), "school points: %s" % str(sch))
	# TEST SET-UP: the child's days are over.
	c["child_at"] = int(sim.state["tick"]) - int(float(sim.content["society"]["families"]["child_grow_days"]) * 6000.0)
	sim.run_seconds(12.0)
	t.check(String(c["kind"]) != "child" and String(sim.people.identity(c)["kind"]) == "colonist" and not H.log_entries(sim, "grew_up").is_empty(), "the child grew up: %s" % String(c["role"]))
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## A retail module and a staffed venue: staff are proposed, carriers stock the goods store, visits
## use goods and raise comfort, and tourists pay credits (tourism).
func v5_venues_and_tourism(t) -> void:
	var sim = _showcase()
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	sim.run_seconds(5.0)
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var shop: Dictionary = H.attach(sim, "retail", lander, 1)
	H.attach_power(sim, lander)
	t.check(not shop.is_empty() and int(shop.get("inv_in", -1)) != -1, "a retail module with a goods store")
	if shop.is_empty():
		sim.dispose()
		t.done()
		return
	# TEST SET-UP: goods in the lander's store (as if made or bought).
	var store: int = int(sim.state["buildings"][int(sim.state["lander_id"])]["inv_out"])
	for item in ["snacks", "clothing", "gifts", "gadgets", "luxury_goods"]:
		sim.inv.add_new_forced(store, item, 12, "scenario")
	sim.run_seconds(40.0)
	var staff: Array = sim.leisure.staff_of(int(shop["id"]), "shop")
	t.eq(staff.size(), 1, "SIM proposed a shopkeeper")
	var stocked := false
	var open := false
	var used0: int = int(sim.state["ledger"].get("snacks", {}).get("consumed", 0)) + int(sim.state["ledger"].get("clothing", {}).get("consumed", 0))
	for s in 60:
		sim.run_seconds(10.0)
		if sim.inv.total(int(shop["inv_in"])) > 0:
			stocked = true
		if sim.leisure.is_open(shop, "shop"):
			open = true
	t.check(stocked, "carriers stocked the shop (%s)" % str(sim.inv.get_inv(int(shop["inv_in"]))["items"]))
	var rows: Array = sim.leisure.venues(shop)
	t.check(open, "the shop opened: %s" % str(rows))
	# People relax when they have no work (work comes first): TEST SET-UP: six colonists start a visit.
	var n_vis := 0
	for a in _colonists(sim):
		if n_vis >= 6 or a["where"] != "in" or a.has("v5_hold"):
			continue
		if sim.agents._start_personal(a, "rec", int(shop["id"]), [{"op": "rec"}], "Shopping", -1):
			sim.leisure.pick_venue(a, int(shop["id"]))
			n_vis += 1
	sim.run_seconds(120.0)
	var used := 0
	for item in ["snacks", "clothing", "gifts", "gadgets", "luxury_goods"]:
		used += int(sim.state["ledger"].get(item, {}).get("consumed", 0))
	t.check(used > 0, "visits used goods (%d)" % used)
	var q := 0
	for a in _colonists(sim):
		if a.has("rec_q_t"):
			q += 1
	t.check(q > 0, "%d people had a venue visit (comfort bonus)" % q)
	# A tourist at the shop pays (TEST SET-UP: a visitor record).
	var v: Dictionary = sim.agents.spawn("visitor", "Tourist 99", shop["pos"], int(shop["id"]))
	v["kind"] = "visitor"
	v["vkind"] = "liner"
	v["visit"] = {"ate": 0, "rec": 0, "slept": 0, "paid": 0, "treated": false, "study": 0.0, "tour": [], "toured": 0}
	v["venue"] = "shop"
	var c0: int = int(sim.state["credits"]["by"].get("tourism", 0))
	for k in 20:
		sim.step()
		sim.leisure.on_rec_end(v)
	t.check(int(sim.state["credits"]["by"].get("tourism", 0)) > c0, "a tourist pays at a venue (tourism %d)" % int(sim.state["credits"]["by"].get("tourism", 0)))
	t.eq(sim.traffic.credits_audit(), {}, "credits balance")
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## The super dome rises in its 9 stages (ART-B's ids; each is logged), then opens: 16 venues with floors, staff
## proposed, and an open dome doubles the tourists of a liner.
func v5_dome_build_stages(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var c: Vector2 = sim.world.center
	var p := Vector2(-1, -1)
	for r in range(80, 700, 20):
		for k in 24:
			var q: Vector2 = sim.place.snap_pos(c + Vector2.RIGHT.rotated(k * TAU / 24.0) * float(r))
			if p.x < 0.0 and sim.place.check_building("super_dome", q, 0.0, -1, 1) == "ok":
				p = q
	var res: Dictionary = g.cmd("place_building", {"def": "super_dome", "x": p.x, "y": p.y, "rot": 0.0, "size": 1})
	t.check(bool(res["ok"]), "a dome is planned")
	var b: Dictionary = sim.state["buildings"][int(res["id"])]
	t.eq(int(sim.leisure.dome_stage(b)["index"]), -1, "a blueprint is the site stage")
	# TEST SET-UP: every material on site (as if carried), freeze nothing.
	for item in b["cost"]:
		sim.inv.add_new_forced(int(b["inv_site"]), item, int(b["cost"][item]), "scenario")
	for s in 30:
		sim.step()
	t.eq(String(b["state"]), "building", "the dome is being built")
	var seen: Array = []
	for step in 90:
		sim.build.add_progress(b, float(b["work_total"]) / 80.0)                        # test set-up: builders' work
		for k in 10:
			sim.step()
		var st: Dictionary = sim.leisure.dome_stage(b)
		if not seen.has(int(st["index"])):
			seen.append(int(st["index"]))
		if String(b["state"]) == "active":
			break
	t.eq(String(b["state"]), "active", "the dome is finished")
	t.check(seen.has(0) and seen.has(7), "stages 0..7 seen: %s" % str(seen))
	t.check(H.log_entries(sim, "dome_stage").size() >= 7, "each stage is logged (%d)" % H.log_entries(sim, "dome_stage").size())
	var rows: Array = sim.leisure.venues(b)
	t.eq(rows.size(), 16, "16 venues")
	var floors := {}
	for rw in rows:
		floors[int(rw["floor"])] = true
	t.check(floors.has(0) and floors.has(1), "venues on floors 0 and 1")
	t.check(String(sim.leisure.why_closed(b, "bar")) != "", "the bar is closed without staff: %s" % sim.leisure.why_closed(b, "bar"))
	t.check(sim.leisure.why_closed(b, "plaza") == "" or not bool(b["powered"]), "the plaza needs no staff")
	t.eq(sim.place.check_building("super_dome", sim.place.snap_pos(p + Vector2(0, 150)), 0.0, -1, 1), "one_per_base", "one super dome a base")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

## The Rag is stored at the turn of each day: an issue with a lead of 3-6 sentences, 3 or more
## stories when the day had events, 3-5 gossip lines, watches with notes, a poll with the commander
## and the change, 3-4 ads and serious rows {text, severity}.
func v5_rag_stored_issues(t) -> void:
	var sim = _showcase()
	sim.run_seconds(1800.0)
	var issues: Array = sim.social.rag_issues(30)
	var stored := 0
	for iss in issues:
		if bool(iss.get("stored", false)):
			stored += 1
	t.check(stored >= 2, "issues stored in the game (%d of %d)" % [stored, issues.size()])
	var iss: Dictionary = issues[0]
	t.check(bool(iss.get("stored", false)), "the newest issue is stored")
	var sentences: int = String(iss["lead"]["text"]).count(". ") + 1
	t.check(sentences >= 3 and sentences <= 7, "a lead body of 3-6 sentences (%d): %s" % [sentences, iss["lead"]["text"]])
	t.check(iss["stories"].size() >= 3, "3 stories or more (%d)" % iss["stories"].size())
	t.check(iss["gossip"].size() >= 3 and iss["gossip"].size() <= 5, "3-5 gossip lines (%d)" % iss["gossip"].size())
	t.check(iss["ads"].size() >= 3 and iss["ads"].size() <= 4, "3-4 ads (%d)" % iss["ads"].size())
	t.check(iss["poll"].has("commander") and iss["poll"].has("change"), "the poll has the commander and the change: %s" % str(iss["poll"]))
	var ok_notes := true
	for w in iss["couple_watch"] + iss["feud_watch"]:
		ok_notes = ok_notes and String(w.get("note", "")) != ""
	t.check(ok_notes, "watch rows have a note")
	var ok_serious := true
	for s in iss["serious"]:
		ok_serious = ok_serious and typeof(s) == TYPE_DICTIONARY and s.has("text") and s.has("severity")
	t.check(ok_serious, "serious rows are {text, severity}")
	for st in [iss["lead"]] + iss["stories"]:
		if String(st["headline"]).contains("{") or String(st["text"]).contains("{"):
			t.fail("an unfilled slot: %s / %s" % [st["headline"], st["text"]])
	var n := 0
	for k in sim.content["tabloid"]["headlines"]:
		n += (sim.content["tabloid"]["headlines"][k] as Array).size()
	t.check(n >= 200, "200 headlines or more (%d)" % n)
	# The issue survives a save and a load unchanged.
	var st2: Dictionary = Persistence.decode(Persistence.encode(sim.state))["state"]
	var sim2 = H.Sim.new()
	sim2.load_state(st2)
	t.eq(sim2.social.rag_issue(int(iss["number"])), iss, "the stored issue loads unchanged")
	sim2.dispose()
	sim.dispose()
	t.done()

## Multi-storey paths: every bed, child bed, seat and stand of the apartment block and every unit
## and venue of the dome has a floor inside the building; the door and the centre of each are joined
## on the walking map; a floor change is a lift ride of lift_seconds.
func v5_multistorey_paths(t) -> void:
	var sim = _showcase()
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var blk: Dictionary = H.attach(sim, "apartment_block", lander, 1)
	t.check(not blk.is_empty(), "an apartment block joined to the base")
	if blk.is_empty():
		sim.dispose()
		t.done()
		return
	var bad: Array = []
	var f: Dictionary = sim.sizes.furniture("apartment_block", 1)
	for kind in ["bed", "child_bed", "seat", "stand"]:
		var cap: int = sim.agents._slot_cap(kind, int(blk["id"]))
		var per := {}
		for i in cap:
			var fl: int = sim.floors.slot_floor(blk, kind, i)
			if fl < 0 or fl > 2:
				bad.append("%s %d floor %d" % [kind, i, fl])
			per[fl] = int(per.get(fl, 0)) + 1
		if kind == "bed" and per.size() != 3:
			bad.append("beds on %d floors" % per.size())
	t.eq(bad, [], "every anchor of the block is on floor 0, 1 or 2")
	var a: Dictionary = _colonists(sim)[0]
	var r: Dictionary = sim.nav.plan(sim.agents.loc_of(a), {"b": int(blk["id"]), "p": sim.nav.slot_pos(blk, 3)})
	t.check(bool(r["ok"]), "the block is reachable on the walking map")
	var units: Array = sim.floors.units({"id": -1, "def": "super_dome", "size": 1})
	var uf := {}
	for u in units:
		uf[int(u["floor"])] = true
	t.check(units.size() == 30 and uf.has(2) and uf.has(4) and not uf.has(0), "30 dome units on floors 2-4")
	var vf := {}
	for v in sim.bdef("super_dome")["venues"]:
		vf[int(v["floor"])] = true
	t.check(vf.has(0) and vf.has(1) and vf.size() == 2, "dome venues on floors 0 and 1")
	t.near(sim.floors.lift_seconds("super_dome", 0, 4), 20.0, 0.01, "4 floors of the dome lift: 20 s")
	sim.dispose()
	t.done()

## Old saves load (schema 5 and the v3.1 schema): schema 6, one commander a base by seniority, no
## relationships, and a day runs with the ledger balanced.
func v5_migration_old_saves(t) -> void:
	for path in ["res://content/saves/showcase_v4.fhsave", "res://content/saves/showcase_v31.fhsave"]:
		var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))
		t.check(bool(dec["ok"]), "%s decodes" % path)
		if not bool(dec["ok"]):
			continue
		var sim = H.Sim.new()
		sim.load_state(dec["state"])
		t.eq(int(sim.state["schema"]), 6, "%s: schema 6" % path)
		t.eq(sim.state["v5"].get("rel", {}).size(), 0, "no relationships")
		var cmd := {}
		for row in sim.people.list():
			if row["rank"] == "commander":
				cmd[row["base"]] = int(cmd.get(row["base"], 0)) + 1
		var one := true
		for b in cmd:
			one = one and int(cmd[b]) == 1
		t.check(one and cmd.size() >= 1, "one commander a base: %s" % str(cmd))
		var oldest: int = -1
		var ob := 1 << 60
		for a in _colonists(sim):
			if int(a.get("born", 0)) < ob:
				ob = int(a.get("born", 0))
				oldest = int(a["id"])
		var cid: int = int(sim.state["v5"]["appoint"].get("%d:commander" % (int(sim.bases.ids()[0]) if sim.bases.count() > 0 else -1), -1))
		t.check(cid != -1, "the commander is appointed by seniority (%d; oldest %d)" % [cid, oldest])
		var n0: int = sim.alive_count()
		sim.run_seconds(600.0)
		t.check(sim.alive_count() >= n0 - 1, "a day runs (%d -> %d)" % [n0, sim.alive_count()])
		t.eq(sim.inv.audit(), {}, "ledger")
		sim.dispose()
	t.done()

## PRISM SHIFT records, the champion rule, P. Barby after the dome opens.
func v5_eggs(t) -> void:
	var sim = _showcase()
	var a: Dictionary = _colonists(sim)[0]
	for k in 5:
		sim.eggs.on_arcade(a)
		sim.step()
	var ar: Dictionary = sim.eggs.arcade()
	t.check(int(ar["best"]) > 0 and int(ar["holder"]) == int(a["id"]) and int(ar["plays"]) == 5, "arcade record %s" % str(ar))
	t.check(sim.eggs.found("prism_shift") and not H.log_entries(sim, "arcade_record").is_empty(), "the PRISM SHIFT egg is found with the first record")
	var champs := 0
	for id in 20000:
		if sim.eggs.is_champion(id):
			champs += 1
	t.check(champs >= 5 and champs <= 40, "about 1 in 1,000 is a champion (%d in 20,000)" % champs)
	var lines: Array = sim.content["dialogue"]["topics"]["barby"]
	t.check(lines.size() >= 3 and String(lines[0]).contains("made this place"), "P. Barby has lines of his own")
	# P. Barby only after a dome opens (TEST SET-UP: an active dome record, a liner's visitor).
	var v: Dictionary = sim.agents.spawn("visitor", "Tourist 77", a["pos"], int(a["bld"]))
	v["kind"] = "visitor"
	v["vkind"] = "liner"
	v["visit"] = {"ate": 0, "rec": 0, "slept": 0, "paid": 0, "treated": false, "study": 0.0, "tour": [], "toured": 0}
	sim.eggs.on_liner({"n": 0}, [int(v["id"])])
	t.check(not sim.eggs.found("barby"), "no P. Barby before the dome")
	var p := Vector2(-1, -1)
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	for r in range(120, 900, 20):
		for k in 24:
			var q: Vector2 = sim.place.snap_pos(lander + Vector2.RIGHT.rotated(k * TAU / 24.0) * float(r))
			if p.x < 0.0 and sim.place.check_building("super_dome", q, 0.0, -1, 1) == "ok":
				p = q
	sim.build.spawn_active("super_dome", p, 0.0, 1)
	var hit := -1
	for n in 200:
		if sim.eggs._h(n, 99) < 0.25:
			hit = n
			break
	sim.eggs.on_liner({"n": hit}, [int(v["id"])])
	t.check(sim.eggs.found("barby") and String(v["name"]) == "P. Barby" and bool(sim.people.identity(v)["vip"]) and String(sim.social.topic_for(v, a, 1)) == "barby", "P. Barby visits once the dome is open")
	sim.run_seconds(4.0)
	t.check(sim.awards.earned("egg_barby") and sim.awards.earned("egg_prism"), "the egg awards are earned")
	sim.dispose()
	t.done()

## content/saves/showcase_v5.fhsave (tests/make_showcase_v5.gd): about 110 people with children, the
## civic buildings, a dome with venues, a jail with a prisoner, couples, Rag issues, unrest.
func v5_showcase(t) -> void:
	var path := "res://content/saves/showcase_v5.fhsave"
	if not FileAccess.file_exists(path):
		t.fail("no %s (run tests/make_showcase_v5.gd)" % path)
		t.done()
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var raw := StreamPeerBuffer.new()
	raw.data_array = bytes
	raw.seek(8)
	t.eq(raw.get_u32(), 6, "schema 6")
	var dec: Dictionary = Persistence.decode(bytes)
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	var people := 0
	var kids := 0
	for a in sim.state["agents"].values():
		if a["state"] == "alive":
			people += 1
			if String(a.get("kind", "")) == "child":
				kids += 1
	t.check(people >= 100, "100 people or more (%d)" % people)
	t.check(kids >= 6, "6 children or more (%d)" % kids)
	var defs := {}
	for b in sim.state["buildings"].values():
		if b["state"] == "active":
			defs[String(b["def"])] = int(defs.get(String(b["def"]), 0)) + 1
	for d in ["residence_tube", "apartment_block", "retail", "park", "academy", "security_office", "jail", "super_dome"]:
		t.check(defs.has(d), "has a %s" % d)
	t.check(sim.bases.count() >= 2, "2 bases")
	t.check(not sim.traffic._pads(true).is_empty(), "a powered landing pad (ships and tourists)")
	var prisoners := 0
	var students := 0
	for a in sim.state["agents"].values():
		if a["state"] == "alive" and a.has("jailed"):
			prisoners += 1
	for k in sim.state["v5"].get("courses", {}):
		students += 1
	t.check(prisoners >= 1, "a prisoner (%d)" % prisoners)
	t.check(students >= 1, "students at the academy (%d)" % students)
	var couples: Array = sim.relations.pairs_with(["dating", "partners", "married"])
	t.check(couples.size() >= 2, "2 couples or more (%d)" % couples.size())
	t.check(not sim.relations.pairs_with(["affair"]).is_empty(), "an affair about to break")
	var issues: Array = sim.social.rag_issues(30)
	var stored := 0
	for iss in issues:
		if bool(iss.get("stored", false)):
			stored += 1
	t.check(stored >= 5, "5 Rag issues (%d)" % stored)
	var u: float = float(sim.unrest.info(-1)["value"])
	t.check(u < 25.0, "calm unrest (%.1f)" % u)
	var dome: Dictionary = {}
	for b in sim.state["buildings"].values():
		if String(b["def"]) == "super_dome":
			dome = b
	var open := 0
	for rw in sim.leisure.venues(dome):
		if bool(rw["open"]):
			open += 1
	t.check(open >= 5, "the dome has open venues (%d)" % open)
	var tourists := 0
	for a in sim.state["agents"].values():
		if a["state"] == "alive" and String(a.get("kind", "")) == "visitor":
			tourists += 1
	t.note("%d people, %d children, %d visitors, unrest %.1f, %d open venues, %d stored issues" % [people, kids, tourists, u, open, stored])
	sim.run_seconds(60.0)
	t.eq(sim.inv.audit(), {}, "ledger after a minute")
	sim.dispose()
	t.done()
## V5 budget (section 0): the sim tick at about 110 people with the social systems. Median of the
## tick times over 1,500 ticks of showcase_v5 (<= 3.0 ms) and the worst tick (budget 12 ms; the test
## fails over 30 ms, as long_v4_tick_max: the worst tick depends on the machine's load).
func long_v5_perf_showcase(t) -> void:
	var path := "res://content/saves/showcase_v5.fhsave"
	if not FileAccess.file_exists(path):
		t.fail("no %s" % path)
		t.done()
		return
	var sim = H.Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	sim.run_seconds(30.0)
	var times: Array = []
	var raw_times: Array = []
	var pc = Pacer.new(false, 1.0)
	pc.start()
	for blk in 15:
		var bsum := 0.0
		var first: int = raw_times.size()
		for i in 100:
			var t0: int = Time.get_ticks_usec()
			sim.step()
			var ms0: float = float(Time.get_ticks_usec() - t0) / 1000.0
			raw_times.append(ms0)
			bsum += ms0
		pc.block(bsum, 100)                                                              # the next reading is outside the timed steps
		var f: float = pc.factor_of(blk)
		for i in range(first, raw_times.size()):
			times.append(float(raw_times[i]) * f)
	var factor: float = pc.mean_factor()
	var cal: String = pc.reading_text()
	var raw_sorted: Array = raw_times.duplicate()
	raw_sorted.sort()
	var raw_med: float = float(raw_sorted[raw_sorted.size() / 2])
	var raw_worst: float = float(raw_sorted[raw_sorted.size() - 1])
	var sorted_t: Array = times.duplicate()
	sorted_t.sort()
	var med: float = float(sorted_t[sorted_t.size() / 2])
	var worst: float = float(sorted_t[sorted_t.size() - 1])
	var p99: float = float(sorted_t[int(sorted_t.size() * 0.99)])
	var mean := 0.0
	for x in times:
		mean += float(x)
	mean /= float(times.size())
	t.note("%d people, scaled: median %.3f ms, mean %.3f ms, p99 %.2f ms, worst %.2f ms (raw median %.3f, raw worst %.2f; calibration %s, mean factor %.3f)" % [sim.state["agents"].size(), med, mean, p99, worst, raw_med, raw_worst, cal, factor])
	t.check(med <= 3.0, "scaled median tick %.3f ms (budget 3.0; raw %.3f, factor %.3f)" % [med, raw_med, factor])
	t.check(worst <= 30.0, "scaled worst tick %.2f ms (budget 12; fails over 30)" % worst)
	sim.dispose()
	t.done()
## The v5 systems are part of the game state: showcase_v5 run twice for 90 s, the second time saved
## and loaded at a tick that is not the start of a second, ends in the same state.
func v5_showcase_deterministic(t) -> void:
	var path := "res://content/saves/showcase_v5.fhsave"
	if not FileAccess.file_exists(path):
		t.fail("no %s" % path)
		t.done()
		return
	var digests: Array = []
	for run in 2:
		var sim = H.Sim.new()
		sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
		for i in 453:
			sim.step()
		if run == 1:
			var st: Dictionary = Persistence.decode(Persistence.encode(sim.state))["state"]
			sim.dispose()
			sim = H.Sim.new()
			sim.load_state(st)
		for i in 447:
			sim.step()
		digests.append(Persistence.digest(sim.state))
		sim.dispose()
	t.eq(digests[0], digests[1], "the same digest with and without a save at tick +453")
	t.done()
## A protest gathers the unhappiest people at the protest place (protest_fist, the demand shouted);
## a riot starts fights, damages rooms (never under riot_min_health) and loots goods; the info counts it.
func v5_protest_and_riot(t) -> void:
	var sim = _showcase()
	sim.run_seconds(20.0)
	var base: int = int(sim.bases.ids()[0]) if sim.bases.count() > 0 else -1
	var ppl: Array = _colonists(sim)
	# TEST SET-UP: a protest with a demand; the people are very unhappy (stored satisfaction).
	var ur: Dictionary = sim.unrest._rec_w(base)
	ur["value"] = 60.0
	ur["stage"] = "protest"
	ur["demand"] = "Full rations now!"
	for a in ppl:
		sim.people.rec_w(a)["sat"] = 20.0
	var protest := false
	var shouted := false
	for s in 60:
		sim.run_seconds(1.0)
		ur["value"] = 60.0                                                                # test set-up: hold the stage
		ur["stage"] = "protest"
		for a in ppl:
			sim.people.rec_w(a)["sat"] = 20.0
			if String(a.get("plan_kind", "")) == "protest" and sim.agents._step_op(a) == "protest" and sim.people.action(a) == "protest_fist":
				protest = true
				for l in sim.social.recent_lines(int(a["id"]), 3):
					if String(l["text"]) == "Full rations now!":
						shouted = true
	t.check(protest, "people gather and protest (protest_fist)")
	t.check(shouted, "a protester shouts the demand")
	# TEST SET-UP: a riot.
	ur["value"] = 90.0
	ur["stage"] = "riot"
	ur["damaged"] = []
	ur["injured"] = 0
	ur["looted"] = 0
	var min_h := 100.0
	var fights := 0
	for s in 120:
		sim.run_seconds(1.0)
		ur["value"] = 90.0
		ur["stage"] = "riot"
		fights = maxi(fights, sim.security.fights().size())
	var info: Dictionary = sim.unrest.info(base)
	t.check(int(info["damage"]) > 0, "rooms are damaged in the riot (%d)" % int(info["damage"]))
	for rid in ur.get("damaged", []):
		min_h = minf(min_h, float(sim.state["buildings"][int(rid)]["health"]))
	t.check(min_h >= float(sim.content["society"]["security"]["riot_min_health"]) - 0.01, "never under riot_min_health (%.1f)" % min_h)
	t.check(not H.log_entries(sim, "fight").is_empty() or fights > 0, "fights break out in the riot")
	t.note("damage %d, injured %d, looted %d" % [int(info["damage"]), int(info["injured"]), int(info["looted"])])
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()
## Paul 2026-10-01 (V5 15.7): atmospheric events never happen on the airless planet. 40 days of the
## hazard planner per planet (hazards "hard"), events counted by kind; then 2 days of play on the
## airless planet; an old save's pending atmospheric event is dropped at load; wind turbines and
## atmosphere processors are refused there.
func v5_planet_hazards(t) -> void:
	var counts := {}
	for planet in ["dry", "cold", "airless"]:
		var g = H.Game.new(1001, false)
		var sim = g.sim
		sim.new_game(1001, "frontier", {"planet": planet, "hazards": "hard"})
		var seen := {}
		var per := {}
		var dt: int = sim.hazards.day_ticks()
		for d in 40:
			sim.state["tick"] = int(sim.state["tick"]) + dt                                  # test set-up: the planner only
			sim.hazards._plan()
			for ev in sim.hazards.hs()["queue"]:
				if not seen.has(int(ev["id"])):
					seen[int(ev["id"])] = true
					per[String(ev["kind"])] = int(per.get(String(ev["kind"]), 0)) + 1
		counts[planet] = per
		g.dispose()
	t.note("events in 40 days (hard): %s" % str(counts))
	var air := 0
	for k in ["dust_storm", "wind_storm", "dust_devil"]:
		air += int(counts["airless"].get(k, 0))
	t.eq(air, 0, "airless: 0 atmospheric events")
	t.check(int(counts["airless"].get("meteor", 0)) > 0 and int(counts["airless"].get("solar_flare", 0)) > 0 and int(counts["airless"].get("quake", 0)) > 0, "airless keeps meteors, flares and quakes")
	t.check(int(counts["dry"].get("dust_storm", 0)) > 0 and int(counts["dry"].get("dust_devil", 0)) > 0 and int(counts["dry"].get("wind_storm", 0)) > 0, "the dry world has dust and wind")
	t.check(int(counts["cold"].get("dust_devil", 0)) < int(counts["dry"].get("dust_devil", 0)), "the cold world has fewer dust devils than the dry world")
	# Two days of play on the airless planet: no atmospheric event starts, no wind power.
	var g2 = H.Game.new(1002, false)
	var s2 = g2.sim
	s2.new_game(1002, "frontier", {"planet": "airless", "hazards": "hard"})
	s2.state["hazards"]["start_tick"] = 0                                                 # test set-up: no quiet first days
	var bad: Array = []
	var wind_max := 0.0
	for i in 1200:
		s2.run_seconds(1.0)
		wind_max = maxf(wind_max, float(s2.state["env"]["wind"]))
		for ev in s2.hazards.hs()["active"]:
			if ["dust_storm", "wind_storm", "dust_devil"].has(String(ev["kind"])) and not bad.has(int(ev["id"])):
				bad.append(int(ev["id"]))
	t.eq(bad, [], "no atmospheric event runs on the airless planet")
	t.eq(wind_max, 0.0, "no wind on the airless planet")
	t.eq(s2.place.check_building("wind_turbine", s2.world.center + Vector2(60, 0), 0.0), "no_atmosphere", "a wind turbine is refused")
	# An old airless save that already has a wind turbine (TEST SET-UP: the record as an old build made it): it
	# stops, shows the block "no_atmosphere" and adds no power however hard the wind blows; on the dry planet the
	# same turbine runs and adds power.
	for planet in ["airless", "dry"]:
		var gw = H.Game.new(1003, false)
		var sw = gw.sim
		sw.new_game(1003, "frontier", {"planet": planet, "hazards": "off"})
		sw.state["flags"]["unlock_all"] = true
		var wt: Dictionary = sw.build.spawn_active("wind_turbine", sw.world.center + Vector2(60, 0), 0.0)
		var cable: Dictionary = H.link_now(sw, "cable", int(sw.state["lander_id"]), int(wt["id"]), [])
		sw.topo.rebuild(true)
		sw.run_seconds(3.0)
		var comp: int = int(sw.topo.power_comp.get(int(wt["id"]), -1))
		t.check(comp != -1, "%s: the turbine is on a network" % planet)
		sw.state["env"]["wind"] = 0.0
		sw.util.power_tick()
		var gen0: int = int(sw.util.power_stats[comp]["gen"])
		sw.state["env"]["wind"] = 6.0
		sw.util.power_tick()
		var gen6: int = int(sw.util.power_stats[comp]["gen"])
		if planet == "airless":
			t.check(String(wt["block"]) == "no_atmosphere" and not bool(wt["powered"]), "airless: the old wind turbine stops and shows no_atmosphere (block %s)" % String(wt["block"]))
			t.eq(gen6, gen0, "airless: wind 6 adds no power (%d and %d)" % [gen0, gen6])
		else:
			t.check(String(wt["block"]) != "no_atmosphere" and gen6 > gen0, "dry planet: the wind turbine runs and adds power (%d to %d)" % [gen0, gen6])
		gw.dispose()
	t.eq(String(s2.place.lock_info("atmo_processor")["kind"]), "planet", "the atmosphere processor is locked by the planet")
	t.check(s2.hazards.kinds_here().size() == 4 and not s2.hazards.kinds_here().has("dust_storm"), "kinds_here: %s" % str(s2.hazards.kinds_here()))
	# An old save on airless with a pending dust storm (TEST SET-UP: the event written as an old build did).
	var h: Dictionary = s2.hazards.hs()
	h["queue"].append({"id": 999, "kind": "dust_storm", "at": int(s2.state["tick"]) + 3000, "end": int(s2.state["tick"]) + 6000, "pos": Vector2.ZERO, "radius": 0.0, "severity": 1, "detected_tick": -1, "phase": "scheduled", "countered": false, "hits": [], "result": {}})
	h["next_at"]["dust_storm"] = int(s2.state["tick"]) + 3000
	var st: Dictionary = Persistence.decode(Persistence.encode(s2.state))["state"]
	var s3 = H.Sim.new()
	s3.load_state(st)
	var left := 0
	for ev in s3.hazards.hs()["queue"]:
		if String(ev["kind"]) == "dust_storm":
			left += 1
	t.eq(left, 0, "the pending dust storm of an old airless save is dropped at load")
	t.check(not s3.hazards.hs()["next_at"].has("dust_storm"), "its plan is dropped too")
	s3.dispose()
	t.eq(s2.inv.audit(), {}, "ledger")
	g2.dispose()
	t.done()
## Bystanders flee a fight; officers in luxury while the crew sleep in dorms raise unrest; role
## skills grow with the work done.
func v5_flee_privilege_skills(t) -> void:
	var sim = _showcase()
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	sim.run_seconds(5.0)
	var ppl: Array = _awake_inside(sim)
	var x: Dictionary = ppl[0]
	var room: int = int(x["bld"])
	var others: Array = []
	for a in ppl.slice(1, 5):
		H.put_inside(sim, a, room)                                                       # test set-up: four in one room
		others.append(a)
	var y: Dictionary = others[0]
	var fid: int = sim.security.start_fight(x, y, "test")
	sim.run_seconds(2.0)
	var f: Dictionary = sim.state["v5"]["fights"].get(fid, {})
	var fled := 0
	for a in others.slice(1):
		if String(a.get("goal", "")) == "Getting away from a fight" or (f.get("fled", []) as Array).has(int(a["id"])):
			fled += 1
	t.check(fid != -1 and fled >= 1, "bystanders flee the fight (%d of %d; fled %s)" % [fled, others.size() - 1, str(f.get("fled", []))])
	# Privilege: the commander in an executive home, the crew in dorms (habitats).
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var exe: Dictionary = H.attach(sim, "residence_tube", lander, 2)
	exe["variant"] = "executive"                                                          # test set-up
	var cmd: int = sim.ranks.commander(-1)
	t.check(cmd != -1 and not exe.is_empty(), "a commander and an executive tube")
	var r1: Dictionary = _cmd(sim, "set_home", {"agent": cmd, "building": int(exe["id"])})
	t.check(bool(r1.get("ok", false)) and int(sim.people.home(sim.state["agents"][cmd])["quality"]) >= 3, "the commander lives in an executive unit: %s" % str(r1))
	sim.run_seconds(25.0)
	var base: int = int(sim.bases.ids()[0]) if sim.bases.count() > 0 else -1
	var ur: Dictionary = sim.unrest.rec_of(base)
	var has_cause := false
	for c in ur.get("causes", []):
		if String(c["text"]).begins_with("Officers live in luxury"):
			has_cause = true
	t.check(float(ur.get("privilege", 0.0)) > 0.0 and has_cause, "privilege is an unrest cause (%.1f)" % float(ur.get("privilege", 0.0)))
	# Skills from work: somebody who worked gained work points in the main role skill.
	var before := {}
	for a in _colonists(sim):
		var xp: Dictionary = sim.people.rec_of(int(a["id"])).get("xp", {})
		var mine: Array = sim.content["people"]["role_skills"].get(String(a["role"]), [])
		if not mine.is_empty():
			before[int(a["id"])] = float(xp.get(mine[0], 0.0))
	sim.run_seconds(600.0)
	var grew := 0
	for aid in before:
		var a2: Dictionary = sim.state["agents"][aid]
		var mine2: Array = sim.content["people"]["role_skills"].get(String(a2["role"]), [])
		if mine2.is_empty():
			continue
		if float(sim.people.rec_of(int(aid)).get("xp", {}).get(mine2[0], 0.0)) > float(before[aid]) + 0.01:
			grew += 1
	t.check(grew >= 3, "role skills grew with work for %d people in a day" % grew)
	# Decay after days without work (TEST SET-UP: last work 5 days ago).
	var p: Dictionary = _colonists(sim)[0]
	var rec: Dictionary = sim.people.rec_w(p)
	rec["worked"] = int(sim.state["tick"]) - 5 * 6000
	var mine3: Array = sim.content["people"]["role_skills"].get(String(p["role"]), [])
	var x0: float = float(rec["xp"].get(mine3[0], 0.0))
	sim.people._grow(p, rec, int(sim.state["tick"]))
	t.check(float(rec["xp"].get(mine3[0], 0.0)) < x0 or x0 == 0.0, "unused skills fall a little (%.3f -> %.3f)" % [x0, float(rec["xp"].get(mine3[0], 0.0))])
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## A real tourist liner brings P. Barby once the dome is open; a shuttle brings a family; a pair with
## no free unit asks for a shared home, and both answers work.
func v5_liner_family_shared_home(t) -> void:
	var path := "res://content/saves/showcase_v5.fhsave"
	var sim = H.Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"], {"debug": true})
	# TEST SET-UP: the next arrival number is one whose liner carries P. Barby (the egg's hash).
	var ts: Dictionary = sim.traffic.ts()
	var k: int = int(ts["n"])
	while sim.eggs._h(100000 + k, 99) >= 0.25:
		k += 1
	ts["n"] = k
	# The liner of the showcase is still on the pad: wait until it has gone.
	for s0 in 90:
		if sim.traffic.ships().is_empty():
			break
		sim.run_seconds(10.0)
	t.check(sim.traffic.ships().is_empty(), "the pad is free")
	var barby := false
	if not sim.eggs.found("barby"):
		_cmd(sim, "traffic_now", {"kind": "liner", "in": 5.0})
		for s in 400:
			sim.run_seconds(1.0)
			if sim.eggs.found("barby"):
				barby = true
				break
	else:
		barby = true
	var named := false
	for a in sim.state["agents"].values():
		if a["state"] == "alive" and String(a["name"]) == "P. Barby":
			named = true
	t.check(barby and named and not H.log_entries(sim, "barby").is_empty(), "P. Barby came on a real liner")
	# A shuttle with a family (TEST SET-UP: an arrival number whose shuttle carries children). The
	# liner leaves the pad first.
	for s1 in 90:
		if sim.traffic.ships().is_empty():
			break
		sim.run_seconds(10.0)
	k = int(ts["n"])
	while sim.traffic._h(100000 + k, 760) >= float(sim.content["society"]["families"]["shuttle_family_chance"]) or sim.traffic._hi(100000 + k, 3, 2, 6) < 2:
		k += 1
	ts["n"] = k
	var kids0: int = 0
	for a in sim.state["agents"].values():
		if a["state"] == "alive" and String(a.get("kind", "")) == "child":
			kids0 += 1
	var r: Dictionary = _cmd(sim, "traffic_now", {"kind": "shuttle", "in": 5.0})
	_cmd(sim, "traffic_answer", {"id": int(r.get("id", -1)), "grant": true, "accept_idx": [0, 1]})
	var landed := false
	for s in 400:
		sim.run_seconds(1.0)
		var arr: Dictionary = sim.traffic.find(int(r.get("id", -1)))
		if not arr.is_empty() and arr.get("result", {}).has("settlers"):
			landed = true
			break
	var kids1: int = 0
	var with_parents := true
	for a in sim.state["agents"].values():
		if a["state"] == "alive" and String(a.get("kind", "")) == "child":
			kids1 += 1
			with_parents = with_parents and not (a.get("parents", []) as Array).is_empty()
	t.check(landed and kids1 > kids0 and with_parents, "a shuttle brought a family (%d -> %d children)" % [kids0, kids1])
	sim.dispose()
	# Shared home: showcase_v4 has no units, so a new pair must ask.
	var s2 = _showcase()
	var ppl: Array = _colonists(s2)
	var pairs: Array = []
	for i in ppl.size():
		for j in range(i + 1, ppl.size()):
			if pairs.size() < 2 and s2.social.compatible(ppl[i], ppl[j]) and s2.relations.partner_of(int(ppl[i]["id"])) == -1 and s2.relations.partner_of(int(ppl[j]["id"])) == -1:
				var used := false
				for pr in pairs:
					used = used or pr.has(ppl[i]) or pr.has(ppl[j])
				if not used:
					pairs.append([ppl[i], ppl[j]])
	for pr in pairs:
		var rel: Dictionary = s2.relations._rel_w(pr[0], pr[1])                         # test set-up: partners
		rel["aff"] = 70.0
		rel["att"] = 80.0
		rel["status"] = "partners"
		s2.relations._bump()
		s2.families.on_partners(pr[0], pr[1])
	var reqs: Array = s2.relations.requests()
	t.check(reqs.size() >= 2 and String(reqs[0]["kind"]) == "shared_home", "pairs without a free unit ask for a shared home (%d)" % reqs.size())
	if reqs.size() >= 2:
		var no: Dictionary = _cmd(s2, "answer_request", {"id": int(reqs[0]["id"]), "answer": "refuse"})
		var a0: Dictionary = s2.state["agents"][int(reqs[0]["agent"])]
		t.check(bool(no.get("ok", false)) and s2.people.has_mod(a0, "apart"), "refuse: they stay apart, unhappy")
		var lander: Vector2 = s2.state["buildings"][int(s2.state["lander_id"])]["pos"]
		var tube: Dictionary = H.attach(s2, "residence_tube", lander, 2)
		var yes: Dictionary = _cmd(s2, "answer_request", {"id": int(reqs[1]["id"]), "answer": "allow"})
		var a1: Dictionary = s2.state["agents"][int(reqs[1]["agent"])]
		var b1: Dictionary = s2.state["agents"][int(reqs[1]["other"])]
		t.check(bool(yes.get("ok", false)) and int(a1["bed"]) == int(tube.get("id", -2)) and int(b1["bed"]) == int(a1["bed"]), "allow after a tube is built: they move in together (%s)" % str(yes))
	t.eq(s2.inv.audit(), {}, "ledger")
	s2.dispose()
	t.done()
## A leave_with_ship request ends when its ship takes off (UI-to-SIM 2026-10-01): removed, one
## defect_ended log line, the colonist stays with a short low mood. An old save with a request for
## a ship that is not there is cleaned within a second.
func v5_leave_request_ends_with_ship(t) -> void:
	var sim = _showcase()
	sim.run_seconds(2.0)
	var ppl: Array = _colonists(sim)
	var a: Dictionary = ppl[0]
	var b: Dictionary = ppl[1]
	var reqs: Dictionary = sim.relations._w()["requests"]
	# TEST SET-UP: requests written as an old save has them: one for a ship that is not there, one shared-home.
	reqs[9002] = {"id": 9002, "kind": "leave_with_ship", "agent": int(ppl[2]["id"]), "other": int(b["id"]), "ship": 7777, "tick": int(sim.state["tick"]), "text": "y"}
	reqs[9003] = {"id": 9003, "kind": "shared_home", "agent": int(ppl[3]["id"]), "other": int(ppl[4]["id"]), "ship": -1, "tick": int(sim.state["tick"]), "text": "z"}
	sim.run_seconds(1.5)
	t.check(not reqs.has(9002), "a request for a ship that is not there is dropped within a second")
	t.check(reqs.has(9003), "a shared-home request is not touched")
	# TEST SET-UP: a landed ship (a record of the right shape for _takeoff) and its request; no step runs before the take-off.
	var kind: String = String(sim.traffic.kinds().keys()[0])
	var arr := {"id": 7001, "kind": kind, "phase": "landed", "visitors": [], "stock_inv": -1, "buy_inv": -1, "result": {}, "t": 0, "at": 0}
	sim.traffic.ts()["ships"].append(arr)
	reqs[9001] = {"id": 9001, "kind": "leave_with_ship", "agent": int(a["id"]), "other": int(b["id"]), "ship": 7001, "tick": int(sim.state["tick"]), "text": "x"}
	t.eq(sim.relations.close_ship_requests(-1), 0, "a request for a landed ship stays")
	sim.traffic._takeoff(arr, int(sim.state["tick"]))
	t.check(not reqs.has(9001), "the request is removed when the ship takes off")
	t.check(reqs.has(9003), "the shared-home request is still there")
	var logged := 0
	for e in sim.state["log"]:
		if String(e["code"]) == "defect_ended":
			logged += 1
	t.eq(logged, 2, "one defect_ended line for each of the two requests that ended")
	t.check(sim.people.has_mod(a, "ship_gone"), "the colonist stays with a short low mood")
	sim.traffic.ts()["ships"].erase(arr)
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()

## Best dressed is chosen by clothes: a person who bought clothes that day wins over the traits; with no purchase it
## is still somebody in a casual outfit (or nobody), and the same day gives the same answer.
func v5_best_dressed_by_clothes(t) -> void:
	var sim = _showcase()
	sim.run_seconds(5.0)
	var dt: int = int(float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))
	var number: int = int(sim.state["tick"]) / dt + 2
	var ppl: Array = _colonists(sim)
	var pick: Dictionary = ppl[ppl.size() - 1]
	var before: int = sim.rag._best_dressed(number)
	t.eq(sim.rag._best_dressed(number), before, "the same day gives the same answer")
	pick["clothes_t"] = (number - 1) * dt + 5                                              # test set-up: bought clothes on that day
	t.eq(sim.rag._best_dressed(number), int(pick["id"]), "the person who bought clothes that day is best dressed")
	pick["clothes_t"] = (number - 3) * dt                                                  # bought two days before: no claim
	t.check(sim.rag._best_dressed(number) != int(pick["id"]) or before == int(pick["id"]), "an old purchase does not win by itself")
	sim.dispose()
	t.done()
