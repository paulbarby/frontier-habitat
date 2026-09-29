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
	for aid in sim.state["agents"]:
		for r in sim.social.relationships_of(int(aid)):
			rel_n += 1
			ok_rel = ok_rel and float(r["affinity"]) >= -100.0 and float(r["affinity"]) <= 100.0 and float(r["attraction"]) >= 0.0 and float(r["attraction"]) <= 100.0
	t.check(rel_n > 0 and ok_rel, "relationships in range (%d)" % rel_n)
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
			t.eq(int(u["beds"]), 3, "a penthouse has 3 bedrooms")
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
