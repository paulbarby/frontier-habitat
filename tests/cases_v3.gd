extends RefCounted
## Version 3 tests (docs/V3_DESIGN.md): alert hysteresis, the 810 m map, furniture use,
## research packs, hazards, breakdowns, save schema 3 and the v2 save migration.
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")
const WorldGen = preload("res://sim/world_gen.gd")
const Reference = preload("res://sim/reference.gd")

const BASE := [
	{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"},
]
const FOOD := [
	{"place": "kitchen", "as": "K1"}, {"link": "corridor", "a": "H1", "b": "K1"},
	{"place": "greenhouse", "as": "G1"}, {"link": "corridor", "a": "K1", "b": "G1"},
]
const LAB := [
	{"place": "research_lab", "as": "RL", "at": "S1"}, {"link": "corridor", "a": "H1", "b": "RL"},
]

func tests() -> Array:
	return [
		["v3_alert_output_blocked_300s", v3_alert_flicker],
		["v3_map_810_world_features", v3_map_world],
		["v3_buildable_area_all_seeds", v3_buildable],
		["v3_budgets_world_gen_and_nav", v3_budgets],
		["v3_suits_research", v3_suits],
		["v3_furniture_content_and_use", v3_furniture],
		["v3_research_packs_boost_and_conservation", v3_packs],
		["v3_research_packs_assembler_makes_packs", v3_assembler],
		["v3_lab_focus_and_supply_cargo", v3_focus_cargo],
		["v3_hazard_queue_horizon_and_hidden", v3_queue],
		["v3_hazard_meteor_breach_turret_sample", v3_meteor],
		["v3_hazard_weather_quake_flare_devil", v3_weather],
		["v3_breakdown_fault_and_maintenance", v3_breakdown],
		["v3_hazard_save_mid_event_digest", v3_hazard_save],
		["v3_v2_save_loads_on_256_map", v3_v2_save],
		["v3_showcase_saves_load_and_run", v3_showcase],
		["v3_junction_min_link_angle_55", v3_junction_angle],
		["long_v3_use_slots_unique", long_v3_slots],
		["long_v3_hazards_determinism_and_ledger", long_v3_determinism],
		["long_v3_perf_70_colonists", long_v3_perf],
	]

# ---------------------------------------------------------------- set-up helpers
func _custom(t, steps: Array, seed_value: int = 1001, opts: Dictionary = {}) -> Dictionary:
	var g = H.empty_game(seed_value)
	if not opts.is_empty():
		g.sim.new_game(seed_value, "tutorial", opts)
	var res: Dictionary = H.layout(g.sim, H.CORE_STEPS + steps)
	for e in res["errors"]:
		t.fail(e)
	return {"g": g, "ids": res["ids"]}

## A legal offset from the lander for a structure, near `near` (rings of up to 30 m).
static func _spot(sim, def_id: String, near: Vector2, size: int = 1, rot: float = 0.0) -> Vector2:
	for r in [0.0, 3.0, 6.0, 9.0, 12.0, 16.0, 20.0, 25.0, 30.0]:
		var n: int = 1 if r == 0.0 else 16
		for j in n:
			var off: Vector2 = near + Vector2(r, 0).rotated(j * TAU / float(n))
			var pos: Vector2 = sim.place.snap_pos(sim.world.center + off)
			if sim.place.check_building(def_id, pos, rot, -1, size) == "ok":
				return pos - sim.world.center
	return Vector2(INF, INF)

## Test set-up: research done without work.
func _grant(sim, techs: Array) -> void:
	for tech in techs:
		sim.state["research"]["done"][tech] = 0

func _ready_base(g) -> void:
	H.set_clock(g.sim, 1, 30.0)
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.7, true)

# ---------------------------------------------------------------- 2. alerts
## V3_DESIGN section 2: a harvester whose output a carrier empties every few seconds for
## 300 s raises output_blocked once and never clears it in between.
func v3_alert_flicker(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	sim.state["flags"]["unlock_all"] = true                     # test set-up
	var errors: Array = []
	var off: Vector2 = _spot(sim, "regolith_harvester", Vector2(-12, -26))
	var rh: Dictionary = H.spawn(sim, "regolith_harvester", off, 0.0, errors)
	if not rh.is_empty():
		H.link_now(sim, "cable", int(rh["id"]), int(ids["B1"]), errors)
	for e in errors:
		t.fail(e)
	if rh.is_empty():
		t.done()
		return
	_ready_base(g)
	rh["out_rate"] = 60.0          # test set-up: a fast machine, so its buffer refills in seconds
	# The "carrier": a box that nothing else touches (a ground pile would be tidied away).
	var pile: int = sim.inv.create_inv("g", 0, "box", 100000, sim.world.center + Vector2(-30, 30))
	var full: bool = g.run_until(func(): return String(rh["block"]) == "output_blocked", 3000)
	t.check(full, "the harvester filled its output buffer")
	var raised := 0
	var cleared := 0
	var was := false
	var toggles := 0
	var last: String = String(rh["block"])
	var per_machine := 0
	for s in 300:
		if s % 5 == 0:
			sim.inv.move(int(rh["inv_out"]), pile, "silicate", 1)      # a carrier takes one unit
		for k in 10:
			g.step()
			if String(rh["block"]) != last:
				toggles += 1
				last = String(rh["block"])
		var on: bool = sim.state["issues"].has("output_blocked")
		if on and not was:
			raised += 1
		if was and not on:
			cleared += 1
		was = on
		for key in sim.state["issues"]:
			if String(key).begins_with("blocked:"):
				per_machine += 1
	t.check(toggles >= 20, "the buffer filled and emptied again and again (%d changes)" % toggles)
	t.eq(raised, 1, "output_blocked was raised once")
	t.eq(cleared, 0, "it never cleared in between")
	t.eq(per_machine, 0, "no per-machine blocked alert exists")
	var issue: Dictionary = sim.state["issues"].get("output_blocked", {})
	t.check(not issue.is_empty() and (issue["entities"] as Array).has(int(rh["id"])), "the one alert lists the harvester")
	t.note("%d block changes in 300 s, alert raised %d time" % [toggles, raised])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 1. map
func v3_map_world(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var w = sim.world
	var c: Vector2 = w.center
	t.eq(int(sim.state["map_size"]), 810, "a new game stores map_size 810")
	t.eq(int(w.size), 810, "the world is 810 m")
	t.eq(int(w.margin), 8, "map margin 8")
	t.eq(int(w.version), 3, "version-3 world")
	var flat := true
	for k in 64:
		var a: float = k * TAU / 64.0
		for r in [15.0, 40.0, 70.0, 100.0, 118.0]:
			if w.slope_over(c + Vector2(cos(a), sin(a)) * r, 5.0) > 0.02:
				flat = false
	t.check(flat, "the start plateau is flat to 120 m")
	t.check(w.ridges.size() >= 2, "rock ridges (%d)" % w.ridges.size())
	t.check(w.canyons.size() >= 1, "canyons (%d)" % w.canyons.size())
	t.check(w.craters.size() >= 5, "craters (%d)" % w.craters.size())
	t.check(w.flats.size() >= 3, "silicate flats (%d)" % w.flats.size())
	t.check(not w.basin.is_empty() and not w.fault.is_empty(), "an impact basin and a fault line")
	var exotic := 0
	var near := 0
	var far := 0
	var min_ex := 1e9
	for d in sim.state["deposits"]:
		var dist: float = Vector2(d["x"], d["y"]).distance_to(c)
		if bool(d.get("exotic", false)):
			exotic += 1
			min_ex = minf(min_ex, dist)
		elif dist < 150.0:
			near += 1
		else:
			far += 1
	t.check(exotic >= 1 and min_ex >= 200.0, "exotic fields at least 200 m out (%d, nearest %.0f m)" % [exotic, min_ex])
	t.check(near >= 2 and far >= 5, "ore fields near (%d) and far (%d)" % [near, far])
	var d0: float = Vector2(sim.state["deposits"][0]["x"], sim.state["deposits"][0]["y"]).distance_to(c)
	t.check(d0 < 50.0, "a deposit near the start (%.0f m)" % d0)
	var ship: Dictionary = sim.ship.record()
	var sd: float = (ship["pos"] as Vector2).distance_to(c) if not ship.is_empty() else -1.0
	t.check(sd >= 55.0 and sd <= 75.0, "the Meridian is 55..75 m from the lander (%.0f m)" % sd)
	# Hazard zones: 0.5..2.0; the basin is meteor-prone, the fault quake-prone.
	var ok_range := true
	for j in 20:
		for i in 20:
			var z: Dictionary = w.hazard_at(Vector2(20 + i * 40, 20 + j * 40))
			for k in z:
				if float(z[k]) < 0.5 or float(z[k]) > 2.0:
					ok_range = false
	t.check(ok_range, "hazard fields stay in 0.5..2.0")
	var bz: float = float(sim.world.hazard_at(Vector2(w.basin["x"], w.basin["y"]))["meteor"])
	var fp: Vector2 = Geometry2D.get_closest_point_to_segment(c, Vector2(w.fault["x0"], w.fault["y0"]), Vector2(w.fault["x1"], w.fault["y1"]))
	var fz: float = float(sim.hazards.zone_at(fp)["quake"])
	t.check(bz > 1.6, "the impact basin is meteor-prone (%.2f)" % bz)
	t.check(fz > 1.6, "the fault line is quake-prone (%.2f)" % fz)
	# The same seed gives the same world (a fresh generation, not the cache).
	var w2 = WorldGen.new()
	w2.margin = 8
	w2._generate_v3(1001, sim.planet, sim.bal, 810)
	t.check(w2.heights == w.heights and w2.rocks.size() == w.rocks.size() and w2.deposit_sites.size() == w.deposit_sites.size(), "a second generation is identical")
	t.note("%d ridges, %d canyons, %d craters, %d flats, %d rocks, %d deposits (%d exotic); ship %.0f m" % [w.ridges.size(), w.canyons.size(), w.craters.size(), w.flats.size(), w.rocks.size(), sim.state["deposits"].size(), exotic, sd])
	g.dispose()
	t.done()

## Share of the map where a room of radius 5 can stand (slope and rocks), V3_DESIGN 1.
static func buildable_share(sim, step: float = 8.0) -> float:
	var w = sim.world
	var ok := 0
	var n := 0
	var lim: float = float(sim.bal["max_slope_rooms"])
	var y: float = step * 0.5
	while y < float(w.size):
		var x: float = step * 0.5
		while x < float(w.size):
			n += 1
			var p := Vector2(x, y)
			var good: bool = w.in_map(p, float(w.margin) + 5.0) and w.slope_over(p, 5.0) <= lim
			if good:
				for rock in w.rocks:
					if absf(float(rock["x"]) - p.x) < 8.0 and absf(float(rock["y"]) - p.y) < 8.0 and Vector2(rock["x"], rock["y"]).distance_to(p) < 5.0 + float(rock["r"]) + 0.3:
						good = false
						break
			if good:
				ok += 1
			x += step
		y += step
	return float(ok) / float(maxi(1, n))

func v3_buildable(t) -> void:
	var parts: Array = []
	for s in [1001, 1002, 1003, 1004, 1005]:
		var g = H.empty_game(s)
		var share: float = buildable_share(g.sim)
		t.check(share >= 0.70, "seed %d: at least 70%% of the map is buildable (%.1f%%)" % [s, share * 100.0])
		parts.append("%d: %.1f%%" % [s, share * 100.0])
		g.dispose()
	t.note("buildable for a room of radius 5: " + ", ".join(parts))
	t.done()

## World generation and the nav build on this machine; the web build is slower (about
## 1.5 to 2 times for GDScript). Budgets: world gen 3 s (web), nav 1 s.
func v3_budgets(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var t0: int = Time.get_ticks_msec()
	var w2 = WorldGen.new()
	w2.margin = 8
	w2._generate_v3(4242, sim.planet, sim.bal, 810)
	var gen_ms: int = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	sim.nav._base_world = null
	sim.nav.rebuild()
	var nav_ms: int = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	sim.topo.rebuild(true)
	var re_ms: int = Time.get_ticks_msec() - t0
	t.check(gen_ms <= 1500, "world generation %d ms on this machine (web budget 3000 ms)" % gen_ms)
	t.check(nav_ms <= 500, "nav build %d ms on this machine (web budget 1000 ms)" % nav_ms)
	t.check(re_ms <= 100, "a map change rebuilds the graphs in %d ms" % re_ms)
	var c: Vector2 = sim.world.center
	var worst := 0
	var found := 0
	t0 = Time.get_ticks_msec()
	for k in 24:
		var a: float = k * TAU / 24.0
		var u0: int = Time.get_ticks_usec()
		var r: Dictionary = sim.nav.path_out(c + Vector2(20, 0), c + Vector2(cos(a), sin(a)) * 250.0)
		worst = maxi(worst, Time.get_ticks_usec() - u0)
		if r["ok"]:
			found += 1
	var paths_ms: int = Time.get_ticks_msec() - t0
	t.check(found >= 20, "long trips of 250 m find a path (%d of 24)" % found)
	t.note("world gen %d ms, nav build %d ms, graph rebuild %d ms, 24 paths of 250 m %d ms (worst %.1f ms); %s" % [gen_ms, nav_ms, re_ms, paths_ms, float(worst) / 1000.0, OS.get_processor_name()])
	g.dispose()
	t.done()

func v3_suits(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var base: float = sim.agents.suit_cap()
	var reach0: float = sim.agents.suit_reach_metres()
	_grant(sim, ["suit_1"])
	var s1: float = sim.agents.suit_cap()
	_grant(sim, ["suit_2"])
	var s2: float = sim.agents.suit_cap()
	t.near(s1, base * 1.5, 1e-6, "suit_1: +50% suit air")
	t.near(s2, base * 2.2, 1e-6, "suit_2: +120% suit air")
	t.check(sim.agents.suit_reach_metres() > reach0 * 2.0, "the reach from an airlock grows (%.0f m to %.0f m)" % [reach0, sim.agents.suit_reach_metres()])
	t.note("suit air %.0f / %.0f / %.0f s, reach %.0f / %.0f m" % [base, s1, s2, reach0, sim.agents.suit_reach_metres()])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 6. furniture
func v3_furniture(t) -> void:
	var c: Dictionary = _custom(t, BASE + FOOD + LAB)
	var g = c["g"]
	var sim = g.sim
	# Content: every room type has a furniture block that matches the sim's numbers.
	for id in sim.content["buildings"]:
		var d: Dictionary = sim.content["buildings"][id]
		if d["kind"] != "room":
			continue
		t.check(d.has("furniture"), "%s has furniture counts" % id)
		for size in sim.sizes.sizes_of(id):
			var f: Dictionary = sim.sizes.furniture(id, size)
			var e: Dictionary = sim.sizes.def_for(id, size)
			t.check(int(f["stands"]) >= 1, "%s size %d has a standing spot" % [id, size])
			if int(e.get("beds", 0)) > 0:
				t.eq(int(f["beds"]), int(e["beds"]), "%s size %d beds" % [id, size])
			if int(e.get("treatment_beds", 0)) > 0:
				t.eq(int(f["beds"]), int(e["treatment_beds"]), "%s size %d treatment beds" % [id, size])
			if e.has("work_slots") and not bool(e.get("automatic", false)):
				t.eq(int(f["work_slots"]), int(e["work_slots"]), "%s size %d work places" % [id, size])
			if int(e.get("trays", 0)) > 0:
				t.eq(int(f["work_slots"]), int(e["trays"]), "%s size %d: one work place per tray" % [id, size])
			t.check(["stand", "sit"].has(String(f["work_pose"])), "%s work pose" % id)
	# Behaviour: a day in a small base.
	_ready_base(g)
	g.cmd("research", {"tech": "agri_1"})
	var seen := {}
	var bad: Array = []
	for s in 700:
		g.run(10)
		var taken := {}
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] != "alive":
				continue
			var u: Dictionary = a.get("use", {})
			if u != sim.agents.use_of(int(aid)):
				bad.append("use_of differs")
			if u.is_empty():
				continue
			seen["%s/%s/%s" % [u["kind"], u["pose"], u["act"]]] = true
			var i: int = int(u["i"])
			if u["kind"] != "service":
				var b: Dictionary = sim.state["buildings"].get(int(u["b"]), {})
				if b.is_empty():
					bad.append("use names a missing building")
					continue
				var cap: int = sim.agents._slot_cap(String(u["kind"]), int(u["b"]))
				if i >= cap:
					bad.append("%s index %d of %d in %s" % [u["kind"], i, cap, b["def"]])
			if i >= 0:
				var key := "%d:%s:%d" % [int(u["b"]), u["kind"], i]
				if taken.has(key):
					bad.append("two colonists on %s" % key)
				taken[key] = true
	t.eq(bad.slice(0, 5), [], "every use names a real anchor, one colonist each")
	t.check(seen.has("bed/lie/sleep"), "colonists sleep in beds")
	t.check(seen.has("seat/sit/eat") or seen.has("stand/stand/eat"), "colonists eat at a seat")
	t.check(seen.has("work/sit/work"), "a scientist sits at a lab desk")
	t.note("uses seen: %s" % ", ".join(seen.keys()))
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 5. research packs
func v3_packs(t) -> void:
	var c: Dictionary = _custom(t, BASE + LAB)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	_ready_base(g)
	var lab: Dictionary = sim.state["buildings"][ids["RL"]]
	# Test set-up: no goal rewards in this test (their RP would count without packs).
	sim.state["goals"]["chapter"] = (sim.content["chapters"] as Array).size()
	# Tier 1 without packs: the base rate. With a basic pack in the lab: x2 and one pack used.
	g.cmd("research", {"tech": "eng_1"})
	var base_rp: float = sim.research.add_work(lab, 10.0)
	t.check(base_rp > 0.0, "tier 1 runs without packs (%.2f RP)" % base_rp)
	sim.inv.add_new_forced(int(lab["inv_in"]), "pack_basic", 1, "test")       # test set-up
	var boosted: float = sim.research.add_work(lab, 10.0)
	t.near(boosted, base_rp * 2.0, 1e-6, "a lab that holds the pack works x2")
	t.eq(int(H.ledger_of(sim, "pack_basic")["consumed"]), 1, "one basic pack was used for the boost")
	# Finish eng_1 by work; then eng_2 (tier 2) stops without packs.
	var done1: bool = g.run_until(func(): return sim.research.is_done("eng_1"), 20000)
	t.check(done1, "eng_1 done")
	(lab["acc"] as Dictionary).erase("rp:pack_basic")     # test set-up: no credit left from the boost
	g.cmd("research", {"tech": "eng_2"})
	g.run_seconds(300.0)
	t.near(float(sim.state["research"]["progress"].get("eng_2", 0.0)), 0.0, 1e-6, "research without packs stops at tier 2")
	t.eq(String(lab["block"]), "no_packs", "the lab says why")
	t.check(sim.research.lock_reason("eng_2").contains("packs"), "the lock reason names the packs: %s" % sim.research.lock_reason("eng_2"))
	var used0: int = int(H.ledger_of(sim, "pack_basic")["consumed"])
	var lander_store: int = sim.state["buildings"][sim.state["lander_id"]]["inv_out"]
	sim.inv.add_new_forced(lander_store, "pack_basic", 20, "test")        # test set-up: packs bought in
	var done2: bool = g.run_until(func(): return sim.research.is_done("eng_2"), 40000)
	t.check(done2, "with packs eng_2 is done")
	var used: int = int(H.ledger_of(sim, "pack_basic")["consumed"]) - used0
	t.eq(used, 9, "eng_2 used exactly its 9 basic packs")
	var created: int = int(H.ledger_of(sim, "pack_basic")["created"])
	t.eq(H.world_count(sim, "pack_basic") + int(H.ledger_of(sim, "pack_basic")["consumed"]), created, "every pack is somewhere or used (conservation)")
	t.eq(sim.inv.audit(), {}, "ledger {}")
	var info: Dictionary = sim.research.lab_info(lab)
	t.check(info.has("rate") and info.has("base_rate") and info.has("packs"), "lab_info has the rates and packs")
	# Migration of v2 special research that was paid with crystals: no packs needed.
	var st: Dictionary = sim.state.duplicate(true)
	st["schema"] = 2
	st.erase("hazards")
	st["research"].erase("packs_paid")
	st["research"]["paid"] = {"s_agri": 100}
	var mig: Dictionary = Persistence.migrate(st)
	t.eq(mig["research"]["packs_paid"], {"s_agri": true}, "a paid v2 special tech needs no packs after migration")
	g.dispose()
	t.done()

func v3_assembler(t) -> void:
	var c: Dictionary = _custom(t, BASE + LAB)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	_grant(sim, ["sci_packs_1"])
	var errors: Array = []
	var off: Vector2 = _spot(sim, "research_assembler", H.SLOT["K1"])
	var ra: Dictionary = H.spawn(sim, "research_assembler", off, 0.0, errors)
	if not ra.is_empty():
		H.link_now(sim, "corridor", int(ids["H1"]), int(ra["id"]), errors)
	for e in errors:
		t.fail(e)
	if ra.is_empty():
		t.done()
		return
	_ready_base(g)
	t.eq(sim.prod.recipe_id(ra), "pack_basic", "the default recipe is basic packs")
	t.eq(g.cmd("set_recipe", {"id": ra["id"], "recipe": "pack_applied"})["code"], "locked_research", "applied packs need sci_packs_2")
	var w0: int = sim.util.water_stock(int(sim.topo.power_comp.get(int(ra["id"]), -1)))
	var made: bool = g.run_until(func(): return int(sim.state["stats"]["produced"].get("pack_basic", 0)) >= 3, 6000)
	t.check(made, "the assembler made basic packs without staff (%d)" % int(sim.state["stats"]["produced"].get("pack_basic", 0)))
	var secs: float = sim.seconds()
	t.check(secs < 300.0, "about 40 s a pack (3 by %.0f s)" % secs)
	t.eq(sim.inv.audit(), {}, "ledger")
	t.note("3 packs by %.0f s; network water before %d" % [secs, w0])
	g.dispose()
	t.done()

func v3_focus_cargo(t) -> void:
	var c: Dictionary = _custom(t, BASE + LAB)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	_ready_base(g)
	var lab: Dictionary = sim.state["buildings"][ids["RL"]]
	g.cmd("research", {"tech": "eng_1"})
	var m0: float = sim.research.lab_mult(lab)
	t.check(bool(g.cmd("set_focus", {"id": ids["RL"], "branch": "eng"})["ok"]), "focus on Engineering")
	t.near(sim.research.lab_mult(lab), m0 * 1.25, 1e-6, "+25% for a tech of the focus branch")
	g.cmd("set_focus", {"id": ids["RL"], "branch": "agri"})
	t.near(sim.research.lab_mult(lab), m0 * 0.9, 1e-6, "-10% for other techs")
	t.eq(g.cmd("set_focus", {"id": ids["RL"], "branch": "nonsense"})["code"], "invalid", "an unknown branch is refused")
	t.eq(g.cmd("set_focus", {"id": ids["H1"], "branch": "eng"})["code"], "invalid", "only labs take a focus")
	# Supply-run cargo.
	t.check(bool(g.cmd("ship", {"action": "cargo", "cargo": "science"})["ok"]), "the cargo can be chosen without a flight")
	t.eq(String(sim.ship.info()["cargo"]), "science", "the choice is kept")
	t.eq(g.cmd("ship", {"action": "cargo", "cargo": "gold"})["code"], "invalid", "an unknown cargo is refused")
	var r: Dictionary = g.cmd("ship", {"action": "supply_run", "cargo": "medical"})
	t.eq(r["code"], "not_operational", "no flight before the ship works")
	t.eq(String(sim.ship.cargo_choice()), "medical", "but the new choice is kept")
	g.cmd("ship", {"action": "cargo", "cargo": "science"})
	var pods0: int = int(sim.state["goals"]["pods"])
	sim.ship._return()            # test set-up: the ship comes back from a flight
	var pod := {}
	for inv_id in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		if bool(inv.get("pod", false)):
			pod = inv["items"]
	t.eq(int(sim.state["goals"]["pods"]), pods0 + 1, "a supply pod landed")
	t.eq(pod, {"pack_basic": 12, "pack_applied": 4}, "the science cargo brings 12 basic and 4 applied packs")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 4. hazards
## The queue reaches horizon_days ahead; scheduled events are hidden from the forecast; a
## command does not change whether or where a queued event happens.
func v3_queue(t) -> void:
	var g1 = H.Game.new(1001, false)
	var g2 = H.Game.new(1001, false)
	for g in [g1, g2]:
		g.sim.new_game(1001, "tutorial", {"hazards": "hard"})
		g.ref = Reference.new(g.sim)
	var day: int = 6000
	g1.run_to_tick(6 * day)
	# Wait for a moment when the queue holds an event that is not detected yet.
	var guard := 0
	while guard < 200:
		guard += 1
		var any_hidden := false
		for ev in g1.sim.hazards.queue_all():
			if String(ev["phase"]) == "scheduled":
				any_hidden = true
		if any_hidden:
			break
		g1.run(600)
	g2.run_to_tick(g1.tick())
	var h1: Dictionary = g1.sim.state["hazards"]
	var q: Array = g1.sim.hazards.queue_all()
	var last_at := 0
	for ev in q:
		last_at = maxi(last_at, int(ev["at"]))
	t.check(not q.is_empty(), "events are queued (%d)" % q.size())
	for kind in h1["next_at"]:
		t.check(int(h1["next_at"][kind]) > g1.tick() + int(1.9 * float(day)), "%s is planned at least 2 days ahead" % kind)
	var hidden := 0
	for ev in q:
		if String(ev["phase"]) == "scheduled":
			hidden += 1
			for f in g1.sim.hazards.forecast():
				if int(f["id"]) == int(ev["id"]):
					t.fail("a scheduled event shows in the forecast")
	t.check(hidden > 0, "scheduled events are hidden (%d)" % hidden)
	# A command changes what happens, never whether or where: game 2 orders shelter and
	# changes priorities; the events queued now keep their time and place.
	var snap := {}
	for ev in q:
		snap[int(ev["id"])] = [ev["kind"], int(ev["at"]), ev["pos"]]
	g2.cmd("shelter", {"on": true})
	g2.cmd("set_priority", {"cat": "industry", "value": 3})
	g1.run_to_tick(g2.tick())
	g1.run(2 * day)
	g2.run(2 * day)
	var same := true
	var checked := 0
	for id in snap:
		var e1: Dictionary = g1.sim.hazards.event(int(id))
		var e2: Dictionary = g2.sim.hazards.event(int(id))
		if e1.is_empty() or e2.is_empty():
			continue
		checked += 1
		if String(e1["kind"]) != String(e2["kind"]) or int(e1["at"]) != int(e2["at"]):
			same = false
		if e1["kind"] != "dust_devil" and (e1["pos"] as Vector2) != (e2["pos"] as Vector2):
			same = false
	t.check(checked > 0 and same, "queued events keep their time and place (%d compared)" % checked)
	t.eq(g1.sim.inv.audit(), {}, "ledger")
	t.note("%d queued at day %.1f, %d hidden, last at day %.1f, %d compared" % [q.size(), float(g1.tick() - 2 * day) / float(day) + 1.0, hidden, float(last_at) / float(day) + 1.0, checked])
	g1.dispose()
	g2.dispose()
	t.done()

func _debug_game(t, steps: Array) -> Dictionary:
	var c: Dictionary = _custom(t, steps, 1001, {"debug": true, "hazards": "normal"})
	c["g"].sim.state["flags"]["unlock_all"] = true          # test set-up
	_ready_base(c["g"])
	return c

func v3_meteor(t) -> void:
	var c: Dictionary = _debug_game(t, BASE)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	var hab: Dictionary = sim.state["buildings"][ids["H1"]]
	var ng = H.empty_game(1001)
	t.eq(ng.cmd("hazard_now", {"kind": "meteor"})["code"], "debug_only", "hazard_now needs debug")
	ng.dispose()
	# A colonist stands outside next to the habitat.
	var who: Dictionary = H.alive_agents(sim)[0]
	var out_p = sim.nav.nearest_walkable((hab["pos"] as Vector2) + Vector2(0, float(hab["radius"]) + 2.0), 6)
	H.put_outside(sim, who, out_p, 80.0)
	var hp0: float = float(who["health"])
	var h0: float = float(hab["health"])
	var craters0: int = sim.hazards.craters().size()
	var rp0: float = float(sim.state["research"]["rp_total"]) + float(sim.state["research"]["bank"])
	sim.state["goals"]["chapter"] = (sim.content["chapters"] as Array).size()   # test set-up: no goal RP
	var r: Dictionary = g.cmd("hazard_now", {"kind": "meteor", "x": (hab["pos"] as Vector2).x, "y": (hab["pos"] as Vector2).y + 4.0, "severity": 2, "radius": 7.0})
	t.check(bool(r["ok"]), "debug meteor accepted")
	t.check(not sim.hazards.forecast().is_empty(), "the forecast shows it")
	g.run(30)
	t.check(bool(hab.get("breach", false)), "the habitat is breached")
	t.check(float(hab["health"]) < h0, "the habitat lost health (%.0f to %.0f)" % [h0, float(hab["health"])])
	t.check(float(who["health"]) < hp0, "the colonist outside was hurt (%.0f)" % float(who["health"]))
	t.eq(sim.hazards.craters().size(), craters0 + 1, "a crater is left")
	var sites: Array = sim.hazards.sites()
	t.check(not sites.is_empty() and int((sites[0]["units"] as Dictionary).get("exotic", 0)) >= 1, "a fragment site with exotic crystal")
	t.check(not H.log_entries(sim, "breach").is_empty() and not H.log_entries(sim, "hazard_impact").is_empty(), "the log has the impact and the breach")
	g.run(100)
	t.check(sim.state["issues"].has("breach"), "a breach alert shows")
	var sealed: bool = g.run_until(func(): return not bool(hab.get("breach", false)), 6000)
	t.check(sealed, "a technician sealed the breach (with steel: no hull plates)")
	t.check(int(sim.state["stats"].get("breaches_sealed", 0)) >= 1, "counted")
	# A turret with charge shoots the next meteor down.
	var errors: Array = []
	var toff: Vector2 = _spot(sim, "meteor_turret", H.SLOT["A2"] + Vector2(-10, 0))
	var tur: Dictionary = H.spawn(sim, "meteor_turret", toff, 0.0, errors)
	if not tur.is_empty():
		H.link_now(sim, "cable", int(tur["id"]), int(ids["B1"]), errors)
	for e in errors:
		t.fail(e)
	g.run(20)
	tur["charge"] = 100.0            # test set-up: a charged turret
	var cr1: int = sim.hazards.craters().size()
	var tp: Vector2 = tur["pos"]
	g.cmd("hazard_now", {"kind": "meteor", "x": tp.x + 25.0, "y": tp.y, "severity": 1})
	t.check(bool(sim.hazards.forecast()[0]["countered"]), "the forecast says the turret covers it")
	g.run(30)
	t.eq(sim.hazards.craters().size(), cr1, "no new crater: it was shot down")
	t.check(float(tur["charge"]) < 100.0, "the shot used charge (%.0f left)" % float(tur["charge"]))
	t.check(not H.log_entries(sim, "hazard_intercepted").is_empty(), "the log says so")
	# Field samples: a scientist surveys the fragment site near the base.
	var surveyed: bool = g.run_until(func(): return int(sim.state["stats"].get("surveys", 0)) >= 1, 12000)
	t.check(surveyed, "a scientist surveyed the fragment site")
	t.check(float(sim.state["research"]["rp_total"]) + float(sim.state["research"]["bank"]) >= rp0 + 40.0, "it gave 40 research points")
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(H.inventory_problems(sim), [], "reservations")
	g.dispose()
	t.done()

func v3_weather(t) -> void:
	var c: Dictionary = _debug_game(t, BASE + LAB)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	var env: Dictionary = sim.state["env"]
	# Wind storm.
	var a1: Dictionary = sim.state["buildings"][ids["A1"]]
	var h_a1: float = float(a1["health"])
	g.cmd("hazard_now", {"kind": "wind_storm", "severity": 3, "duration": 60.0})
	g.run(30)
	t.near(float(env["solar_mult"]), 0.7, 1e-6, "wind storm: solar x0.7")
	t.near(float(env["speed_mult"]), 0.6, 1e-6, "wind storm: walking outside x0.6")
	t.near(float(env["wind_mult"]), 1.8, 1e-6, "wind storm: turbines x1.8")
	g.run(620)
	t.check(float(a1["health"]) < h_a1, "exterior structures took damage (%.1f)" % float(a1["health"]))
	t.near(float(env["solar_mult"]), 1.0, 1e-6, "after the storm solar is back")
	# Quake near the corridors.
	var lk: Dictionary = sim.state["buildings"][ids["L1"]]
	var hl: float = float(lk["health"])
	g.cmd("hazard_now", {"kind": "quake", "x": (lk["pos"] as Vector2).x, "y": (lk["pos"] as Vector2).y, "severity": 3, "radius": 60.0})
	g.run(30)
	t.check(float(lk["health"]) < hl, "the quake damaged structures (airlock %.0f)" % float(lk["health"]))
	t.check(not H.log_entries(sim, "hazard_impact").is_empty(), "the log has the quake")
	# Solar flare: the lab trips, people outside take radiation, shelter brings them in.
	var lab: Dictionary = sim.state["buildings"][ids["RL"]]
	var who: Dictionary = H.alive_agents(sim)[1]
	var op = sim.nav.nearest_walkable(sim.nav.door_pos(lk) + Vector2(4, 0), 6)
	H.put_outside(sim, who, op, 80.0)
	var hp0: float = float(who["health"])
	g.cmd("hazard_now", {"kind": "solar_flare", "severity": 2, "duration": 60.0, "in": 5.0})
	g.run(80)
	var flare_alert := false
	for key in sim.state["issues"]:
		if String(key).begins_with("hazard:"):
			flare_alert = true
	t.check(flare_alert, "a flare alert shows")
	t.check(bool(lab.get("trip", false)) and not bool(lab["powered"]), "the research lab tripped off")
	t.check(float(who["health"]) < hp0 or who["where"] != "out", "radiation harms a colonist outside")
	g.cmd("shelter", {"on": true})
	var inside: bool = g.run_until(func(): return who["where"] != "out", 600)
	t.check(inside, "shelter: the colonist went inside")
	g.run(700)
	t.check(not bool(lab.get("trip", false)), "after the flare the lab works again")
	t.check(not sim.hazards.sheltered(), "the shelter order ended by itself")
	# Dust devil over the solar array.
	var ap: Vector2 = a1["pos"]
	g.cmd("hazard_now", {"kind": "dust_devil", "x": ap.x - 30.0, "y": ap.y, "dir": 0.0, "length": 60.0, "duration": 30.0})
	g.run(400)
	var dusted: bool = false
	for e in sim.state["hazards"]["done"]:
		if e["kind"] == "dust_devil":
			dusted = true
	t.check(dusted, "the dust devil passed")
	var cleaned: bool = g.run_until(func(): return not bool(a1.get("dust", false)), 6000)
	t.check(cleaned, "the dust was cleaned off the solar array")
	# Dust storm (the v2 storm, now a hazard kind).
	g.cmd("hazard_now", {"kind": "dust_storm", "duration": 30.0})
	g.run(30)
	t.near(float(env["solar_mult"]), float(sim.bal["storm"]["solar_mult"]), 1e-6, "dust storm: solar x0.2")
	t.check(sim.events.active(), "the v2 storm API sees it")
	g.run(400)
	t.check(not sim.events.active(), "and its end")
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(H.inventory_problems(sim), [], "reservations")
	g.dispose()
	t.done()

func v3_breakdown(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	_ready_base(g)
	var o2: Dictionary = sim.state["buildings"][ids["O1"]]
	t.check(sim.hazards.is_machine(o2), "the oxygen plant is a machine")
	var rec: Dictionary = sim.hazards.wear_of(int(o2["id"]))
	t.check(float(rec["fail_at"]) >= 60.0 and float(rec["fail_at"]) <= 100.0, "a threshold 60..100 (%.1f)" % float(rec["fail_at"]))
	var fa: float = float(rec["fail_at"])
	# The threshold is a pure function of the id and the repair count.
	var g2 = H.empty_game(1001)
	var res2: Dictionary = H.layout(g2.sim, H.CORE_STEPS + BASE)
	t.near(float(g2.sim.hazards.wear_of(int(res2["ids"]["O1"]))["fail_at"]), fa, 1e-9, "the same machine in the same game has the same threshold")
	g2.dispose()
	# Maintenance before the threshold.
	H.set_clock(sim, 2, 30.0)                 # test set-up: after start_day
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.7, true)
	rec["w"] = fa * 0.8                         # test set-up: well worn
	t.check(sim.hazards.wants_maintenance(o2), "at 80% of its threshold it wants maintenance")
	var risk: Array = sim.hazards.at_risk()
	t.check(not risk.is_empty() and int(risk[0]["id"]) == int(o2["id"]) and float(risk[0]["eta_s"]) > 0.0, "the forecast lists it with a time to failure")
	var maintained: bool = g.run_until(func(): return int(sim.state["stats"].get("maintenance", 0)) >= 1, 6000)
	t.check(maintained, "a technician did the maintenance")
	t.near(float(sim.hazards.wear_of(int(o2["id"]))["w"]), 0.0, 0.5, "wear is back to 0")
	t.eq(int(sim.hazards.wear_of(int(o2["id"]))["n"]), 1, "a new threshold was drawn")
	# A breakdown: wear reaches the threshold.
	var rec2: Dictionary = sim.hazards.wear_of(int(o2["id"]))
	rec2["w"] = float(rec2["fail_at"]) - 0.01   # test set-up
	g.run(20)
	t.eq(String(o2["state"]), "broken", "it broke down at its threshold")
	t.check(not H.log_entries(sim, "fault").is_empty(), "the log names the fault")
	var item: String = sim.hazards.repair_item(o2)
	t.eq(item, sim.hazards.fault_item(String(rec2["fault"])), "the repair needs the fault's item (%s)" % item)
	var lander_store: int = sim.state["buildings"][sim.state["lander_id"]]["inv_out"]
	sim.inv.add_new_forced(lander_store, item, 2, "test")          # test set-up: the part is in stock
	var fixed: bool = g.run_until(func(): return String(o2["state"]) == "active", 6000)
	t.check(fixed, "a technician repaired it")
	t.check(not bool(sim.hazards.wear_of(int(o2["id"]))["broken"]) and float(sim.hazards.wear_of(int(o2["id"]))["w"]) < 1.0, "the breakdown ended and wear is 0")
	# "maintain" puts one machine first.
	var w1: Dictionary = sim.state["buildings"][ids["W1"]]
	sim.hazards.wear_of(int(w1["id"]))["w"] = 5.0   # test set-up
	t.check(bool(g.cmd("maintain", {"id": w1["id"]})["ok"]), "maintain accepted")
	t.check(sim.hazards.wants_maintenance(w1), "the ordered machine wants maintenance at once")
	t.eq(g.cmd("maintain", {"id": ids["H1"]})["code"], "invalid", "a habitat is not a machine")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

## A save taken in the middle of a meteor shower and a wind storm continues exactly.
func v3_hazard_save(t) -> void:
	var c: Dictionary = _debug_game(t, BASE)
	var g = c["g"]
	var sim = g.sim
	g.cmd("hazard_now", {"kind": "wind_storm", "duration": 90.0})
	g.cmd("hazard_now", {"kind": "meteor_shower", "x": sim.world.center.x + 30.0, "y": sim.world.center.y - 30.0, "severity": 2, "in": 5.0})
	g.run(120)
	t.check(not (sim.state["hazards"]["active"] as Array).is_empty(), "events are active at the save")
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved and loaded")
	var sim2 = cl["sim"]
	for i in 900:
		sim.step()
		sim2.step()
	t.eq(H.digest(sim2), H.digest(sim), "the loaded game gives the same state after the events")
	t.check(int(sim.state["hazards"]["done_count"].get("meteor_shower", 0)) == 1, "the shower finished")
	t.eq(sim.inv.audit(), {}, "ledger")
	sim2.dispose()
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 3. saves
func v3_v2_save(t) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://content/saves/showcase_mid.fhsave")
	var raw := StreamPeerBuffer.new()
	raw.data_array = bytes
	raw.seek(8)
	t.eq(raw.get_u32(), 2, "the showcase save is schema 2")
	var dec: Dictionary = Persistence.decode(bytes)
	if not t.check(bool(dec["ok"]), "it decodes: %s" % dec.get("error", "")):
		t.done()
		return
	var s: Dictionary = dec["state"]
	t.eq(int(s["schema"]), 4, "migrated to schema 4 (through 3)")
	t.eq(int(s["map_size"]), 256, "map_size 256")
	var sim = H.Sim.new()
	sim.load_state(s)
	t.eq(int(sim.world.size), 256, "the old 256 m map")
	t.eq(int(sim.world.margin), 4, "with its old margin")
	t.eq(sim.inv.audit(), {}, "ledger after the load")
	t.eq(H.inventory_problems(sim), [], "reservations after the load")
	t.check(int(sim.state["hazards"]["start_tick"]) >= int(sim.state["tick"]) + 6000, "hazards wait one day after the load")
	var alive0: int = sim.alive_count()
	for i in 6000:
		sim.step()
		if i % 600 == 0 and not sim.inv.audit().is_empty():
			t.fail("ledger at tick %d" % i)
	t.eq(sim.inv.audit(), {}, "ledger after one day")
	t.eq(sim.alive_count(), alive0, "nobody died in the day after the load")
	var saved: PackedByteArray = sim.save_bytes()
	var rs := StreamPeerBuffer.new()
	rs.data_array = saved
	rs.seek(8)
	t.eq(rs.get_u32(), 4, "it saves as schema 4 (V3.1)")
	t.note("%d alive, day %.1f" % [sim.alive_count(), sim.seconds() / 600.0 + 1.0])
	sim.dispose()
	t.done()

## A junction takes new corridors at least 55 degrees apart (CRITIC measure: two 2.36 m
## tubes stop overlapping 2.7 m from the centre at 60 degrees); other rooms keep 28. A save
## with closer corridors (made before the rule) loads and keeps them.
func v3_junction_angle(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	sim.state["flags"]["unlock_all"] = true                      # test set-up
	var errors: Array = []
	var jc := Vector2(-45, 35)
	var j: Dictionary = H.spawn(sim, "junction", jc, 0.0, errors)
	var rooms := {}
	for deg in [0, 40, 300, 180, 220]:
		var off: Vector2 = jc + Vector2(15.0, 0).rotated(deg_to_rad(float(deg)))
		rooms[deg] = H.spawn(sim, "storehouse", off, 0.0, errors, 0)
	for e in errors:
		t.fail(e)
	if not errors.is_empty():
		g.dispose()
		t.done()
		return
	t.near(sim.place.link_min_angle(j), 55.0, 1e-9, "junction minimum angle")
	t.near(sim.place.link_min_angle(rooms[0]), 28.0, 1e-9, "other rooms keep 28")
	t.eq(g.cmd("place_link", {"def": "corridor", "a": j["id"], "b": rooms[0]["id"]})["code"], "ok", "first corridor")
	t.eq(sim.place.check_link("corridor", j["id"], rooms[40]["id"])["code"], "ports_full", "40 degrees from it: refused")
	t.eq(sim.place.check_link("corridor", j["id"], rooms[300]["id"])["code"], "ok", "60 degrees from it (the other side): accepted")
	# Test set-up: a corridor made under the old 28 degree rule (a v2 save).
	var jd: Dictionary = sim.content["buildings"]["junction"]
	jd["link_min_angle_deg"] = 28
	sim.sizes._cache.erase("junction")
	var old: Dictionary = H.link_now(sim, "corridor", int(j["id"]), int(rooms[180]["id"]), errors)
	H.link_now(sim, "corridor", int(j["id"]), int(rooms[220]["id"]), errors)
	jd["link_min_angle_deg"] = 55
	sim.sizes._cache.erase("junction")
	t.eq(errors, [], "set-up links made")
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "the save with a 40 degree pair loads")
	if bool(cl["ok"]):
		var sim2 = cl["sim"]
		t.check(sim2.state["buildings"].has(int(old["id"])), "the old corridor is still there")
		t.eq((sim2.topo.links_of.get(int(j["id"]), []) as Array).size(), 3, "all three corridors work")
		sim2.dispose()
	g.dispose()
	t.done()

## The 810 m showcase saves (tests/make_showcase_saves.gd) load, balance and run a minute.
func v3_showcase(t) -> void:
	for name in ["showcase_v3_mid", "showcase_v3_late"]:
		var path := "res://content/saves/%s.fhsave" % name
		if not t.check(FileAccess.file_exists(path), "%s exists" % name):
			continue
		var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))
		if not t.check(bool(dec["ok"]), "%s decodes" % name):
			continue
		var sim = H.Sim.new()
		sim.load_state(dec["state"])
		t.eq(int(sim.world.size), 810, "%s is on the 810 m map" % name)
		t.eq(String(sim.state["options"]["hazards"]), "normal", "%s has hazards normal" % name)
		var alive0: int = sim.alive_count()
		sim.run_seconds(60.0)
		t.eq(sim.inv.audit(), {}, "%s ledger after a minute" % name)
		t.eq(sim.alive_count(), alive0, "%s: nobody died in a minute" % name)
		if name == "showcase_v3_late":
			t.check(alive0 >= 60, "late: 60 or more colonists (%d)" % alive0)
			var have := {}
			for id in sim.state["buildings"]:
				have[sim.state["buildings"][id]["def"]] = true
			for d in ["research_assembler", "meteor_turret", "cantina", "bio_lab", "fungus_farm", "algae_bioreactor", "atmo_processor", "water_recycler", "junction", "airlock"]:
				t.check(have.has(d), "late has a %s" % d)
			t.check(not sim.hazards.sites().is_empty(), "late has a fragment site")
			t.check(not sim.hazards.at_risk().is_empty(), "late has a machine near its breakdown")
			t.check(not (sim.state["hazards"]["breached"] as Array).is_empty(), "late has a breached corridor")
		sim.dispose()
	t.done()

## Two living colonists never hold the same anchor (b, kind, i >= 0) at the same tick.
static func slot_clashes(sim) -> Array:
	var seen := {}
	var out: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var u: Dictionary = a.get("use", {})
		if u.is_empty() or int(u["i"]) < 0:
			continue
		var key := "%d:%s:%d" % [int(u["b"]), u["kind"], int(u["i"])]
		if seen.has(key):
			out.append("tick %d: %s held by %d and %d" % [int(sim.state["tick"]), key, int(seen[key]), int(aid)])
		seen[key] = int(aid)
	return out

func long_v3_slots(t) -> void:
	var bad: Array = []
	var g = H.Game.new(1001, false)
	g.sim.new_game(1001, "tutorial", {"hazards": "hard"})
	g.ref = Reference.new(g.sim, "all")
	var ticks := 0
	while g.tick() < 10 * 6000:
		g.step()
		ticks += 1
		if bad.size() < 5:
			bad.append_array(slot_clashes(g.sim))
	g.dispose()
	for name in ["showcase_v3_mid", "showcase_v3_late"]:
		var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/%s.fhsave" % name))
		if not t.check(bool(dec["ok"]), "%s decodes" % name):
			continue
		var sim = H.Sim.new()
		sim.load_state(dec["state"])
		if bad.size() < 5:
			bad.append_array(slot_clashes(sim))
		for i in 6000:
			sim.step()
			ticks += 1
			if bad.size() < 5:
				bad.append_array(slot_clashes(sim))
		sim.dispose()
	t.eq(bad.slice(0, 5), [], "no anchor is held by two colonists")
	t.note("%d ticks checked" % ticks)
	t.done()

# ---------------------------------------------------------------- long runs
## The reference campaign with hazards on "hard": the same seed and commands give the same
## digest, a save continues exactly, and the ledger balances every day.
func long_v3_determinism(t) -> void:
	var ga = H.Game.new(1001, false)
	ga.sim.new_game(1001, "tutorial", {"hazards": "hard"})
	ga.ref = Reference.new(ga.sim, "all")
	var gb = H.Game.new(1001, false)
	gb.sim.new_game(1001, "tutorial", {"hazards": "hard"})
	gb.ref = Reference.new(gb.sim, "all")
	var bad: Array = []
	for day in range(1, 11):
		ga.run_to_tick(day * 6000)
		gb.run_to_tick(day * 6000)
		if not ga.sim.inv.audit().is_empty():
			bad.append("day %d ledger %s" % [day, str(ga.sim.inv.audit())])
		var p: Array = H.inventory_problems(ga.sim)
		if not p.is_empty():
			bad.append("day %d: %s" % [day, p[0]])
	t.eq(bad, [], "ledger {} and reservations sound every day")
	t.eq(H.digest(gb.sim), H.digest(ga.sim), "two runs of the same seed give the same digest")
	var dc: Dictionary = ga.sim.state["hazards"]["done_count"]
	var total := 0
	for k in dc:
		total += int(dc[k])
	t.check(total >= 3, "hazards happened (%s)" % str(dc))
	var cl: Dictionary = H.clone_by_save(ga.sim)
	var gc = H.Game.new(1001, false)
	gc.sim.dispose()
	gc.sim = cl["sim"]
	gc.ref = H.copy_reference(ga.ref, gc.sim)
	ga.run(3000)
	gc.run(3000)
	t.eq(H.digest(gc.sim), H.digest(ga.sim), "a save taken on day 10 continues exactly")
	t.note("hazards %s; breakdowns %d, maintenance %d, breaches sealed %d; %d alive, %d deaths" % [str(dc), int(ga.sim.state["stats"].get("breakdowns", 0)),
		int(ga.sim.state["stats"].get("maintenance", 0)), int(ga.sim.state["stats"].get("breaches_sealed", 0)), ga.sim.alive_count(), int(ga.sim.state["progress"]["deaths"])])
	ga.dispose()
	gb.dispose()
	gc.dispose()
	t.done()

## The tick budget of V3_DESIGN section 0: 2.0 ms mean at 70 colonists (this machine).
func long_v3_perf(t) -> void:
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(12 * 6000)
	sim.state["flags"]["unlock_all"] = true                # test set-up
	var y := -110
	while sim.state["buildings"].size() < 150 and y <= 110:
		var x := -110
		while sim.state["buildings"].size() < 150 and x <= 110:
			var off := Vector2(x, y)
			if off.length() > 70.0:
				var def_id: String = "solar_array" if (x + y) % 2 == 0 else "battery"
				var pos: Vector2 = sim.place.snap_pos(sim.world.center + off)
				if sim.place.check_building(def_id, pos, 0.0) == "ok":
					sim.build.spawn_active(def_id, pos, 0.0)   # test set-up
			x += 9
		y += 9
	# Settlers come in small groups, so that the airlocks take them in before their suits
	# run out (50 at once queue outside one airlock and many die: that is not the budget).
	var guard := 0
	while sim.alive_count() < 70 and guard < 30:
		guard += 1
		g.cmd("admit_settlers", {"count": mini(6, 70 - sim.alive_count())})
		g.run(450)
	g.run(600)
	var pop: int = sim.alive_count()
	var n: int = sim.state["buildings"].size()
	# Three windows of 1000 ticks; the median is checked (other programs on this PC slow
	# single windows down; every window is on the result line).
	var wins: Array = []
	for w in 3:
		var t0: int = Time.get_ticks_usec()
		g.run(1000)
		wins.append(float(Time.get_ticks_usec() - t0) / 1000.0 / 1000.0)
	var sorted_w: Array = wins.duplicate()
	sorted_w.sort()
	var ms: float = float(sorted_w[1])
	t.check(pop >= 70 and n >= 150, "the colony has the size of the budget (%d people, %d structures)" % [pop, n])
	t.check(sim.alive_count() >= 68, "they are still alive while it is measured (%d)" % sim.alive_count())
	t.check(ms <= 2.0, "a tick takes at most 2.0 ms on this machine (median %.3f ms of %s)" % [ms, str(wins)])
	t.eq(sim.inv.audit(), {}, "ledger")
	t.note("%.3f ms per tick (median of 1000-tick windows %.3f / %.3f / %.3f) with %d colonists and %d structures, hazards normal (%s)" % [ms, wins[0], wins[1], wins[2], pop, n, OS.get_processor_name()])
	g.dispose()
	t.done()
