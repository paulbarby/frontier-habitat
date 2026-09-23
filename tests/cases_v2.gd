extends RefCounted
## Version 2 unit tests (docs/AAA_DESIGN.md sections 2 to 10): sizes, levels, upgrades,
## research, crops, kitchens, nutrition, spoilage, goals, awards, the Meridian, charts,
## content integrity and the version-1 save migration.
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")
const Ship = preload("res://sim/ship.gd")

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
		["v2_content_integrity", v2_content],
		["v2_size_effective_defs", v2_sizes],
		["v2_level_multipliers", v2_levels],
		["v2_upgrade_flow_conserves_ledger", v2_upgrade],
		["v2_research_unlock_and_special_items", v2_research],
		["v2_crop_yields_per_type", v2_crops],
		["v2_kitchen_chooses_valid_dish", v2_kitchen],
		["v2_nutrition_decay_and_eat", v2_nutrition],
		["v2_spoilage_exact_and_cold_exempt", v2_spoilage],
		["v2_goals_sustain_timer_and_pod", v2_goals],
		["v2_awards_once_only", v2_awards],
		["v2_meridian_placement_all_seeds", v2_meridian_place],
		["v2_meridian_stages_and_runs", v2_meridian_stages],
		["v2_charts_series_and_daily", v2_series],
		["v2_migration_v1_save", v2_migration],
		["v2_dust_storm_timing_effects_and_save", v2_storm],
	]

func _custom(t, steps: Array, seed_value: int = 1001) -> Dictionary:
	var g = H.empty_game(seed_value)
	var res: Dictionary = H.layout(g.sim, H.CORE_STEPS + steps)
	for e in res["errors"]:
		t.fail(e)
	return {"g": g, "ids": res["ids"]}

## Test set-up: research done without work.
func _grant(sim, techs: Array) -> void:
	for tech in techs:
		sim.state["research"]["done"][tech] = 0

# ---------------------------------------------------------------- content
func v2_content(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var c: Dictionary = sim.content
	t.eq(c["items"].size(), 34, "item types")
	for id in c["items"]:
		var info: Dictionary = sim.items.info(id)
		t.check(String(info["name"]).length() > 1 and c["item_categories"].has(info["category"]), "item %s has a name and a known category" % id)
	for id in c["dishes"]:
		t.check(sim.items.is_dish(id), "dish %s is an item of category dish" % id)
		var n: Dictionary = c["dishes"][id]["nutrition"]
		t.eq(n.size(), 4, "dish %s nutrients" % id)
		for ing in c["dishes"][id]["ingredients"]:
			t.check(sim.items.is_crop(ing), "dish %s ingredient %s is a crop" % [id, ing])
	for id in c["crops"]:
		t.check(sim.items.is_crop(id), "crop %s is an item" % id)
		t.check(c["buildings"].has(c["crops"][id]["building"]), "crop %s grows in a known building" % id)
	for rid in c["recipes"]:
		var r: Dictionary = c["recipes"][rid]
		for k in r["inputs"]:
			t.check(sim.items.exists(k), "recipe %s input %s is an item" % [rid, k])
		for k in r["outputs"]:
			t.check(sim.items.exists(k), "recipe %s output %s is an item" % [rid, k])
	for id in c["buildings"]:
		var d: Dictionary = c["buildings"][id]
		var tech: String = String(d.get("research", ""))
		t.check(tech == "" or c["techs"].has(tech), "building %s research %s exists" % [id, tech])
		if d.has("recipe"):
			t.check(c["recipes"].has(d["recipe"]), "building %s recipe %s exists" % [id, d["recipe"]])
		for rid in d.get("recipes", []):
			t.check(c["recipes"].has(rid), "building %s recipe %s exists" % [id, rid])
		if bool(d.get("levels", false)) and String(d.get("family", "")) != "":
			t.check(sim.research.level_tech(id, 5) != "__none__" and c["techs"].has(sim.research.level_tech(id, 5)), "building %s has a level-5 tech" % id)
	t.eq(c["techs"].size(), 29, "techs")
	for id in c["techs"]:
		for req in c["techs"][id].get("requires", []):
			t.check(c["techs"].has(req), "tech %s requires known %s" % [id, req])
	t.eq(sim.research.level_tech("research_lab", 5), "s_hab", "research lab level 5 tech")
	t.eq(sim.research.level_tech("greenhouse", 5), "s_agri", "greenhouse level 5 tech")
	t.eq(sim.research.level_tech("habitat", 3), "eng_2", "habitat level 3 tech")
	# Every goal and award kind gives a real answer (not the unknown-kind fallback).
	var known := ["power_online", "network_water", "base_air", "all_housed", "o2_ratio", "water_days", "dish_days",
		"night_no_shed", "nutrition_avg", "morale_avg", "produced", "techs_done", "pop", "max_level", "ship_stage",
		"ship_readiness", "full_supply", "stat", "stored_total", "distinct_dishes", "distinct_buildings", "size_built",
		"power_gen", "lander_survived", "cooked", "goal_done", "no_death_days", "victory"]
	var goals := 0
	for ch in c["chapters"]:
		for gl in ch["goals"]:
			goals += 1
			t.check(known.has(gl["kind"]), "goal %s kind %s is evaluated" % [gl["id"], gl["kind"]])
	t.eq(c["chapters"].size(), 5, "chapters")
	t.eq(c["awards"].size(), 32, "awards")
	for id in c["awards"]:
		t.check(known.has(c["awards"][id]["kind"]), "award %s kind %s is evaluated" % [id, c["awards"][id]["kind"]])
	t.note("%d items, %d dishes, %d crops, %d techs, %d goals, %d awards" % [c["items"].size(), c["dishes"].size(), c["crops"].size(), c["techs"].size(), goals, c["awards"].size()])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- sizes
func v2_sizes(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var base: Dictionary = sim.bdef("habitat")
	var m: Dictionary = sim.sizes.def_for("habitat", 1)
	t.eq(m["cost"], base["cost"], "size M cost is the v1 cost")
	t.eq(float(m["radius"]), float(base["radius"]), "size M radius")
	t.eq(int(m["beds"]), 8, "size M beds")
	t.eq(float(m["power"]), float(base["power"]), "size M power")
	var s: Dictionary = sim.sizes.def_for("habitat", 0)
	var xl: Dictionary = sim.sizes.def_for("habitat", 3)
	t.eq([int(s["beds"]), int(sim.sizes.def_for("habitat", 2)["beds"]), int(xl["beds"])], [4, 14, 22], "habitat beds S, L, XL")
	t.eq(float(xl["radius"]), 8.5, "habitat XL radius")
	t.eq(s["cost"], {"metal": 3, "polymer": 2}, "habitat S cost = M x 0.6, rounded")
	t.eq(xl["cost"], {"metal": 13, "polymer": 10}, "habitat XL cost = M x 2.6, rounded")
	t.near(float(xl["power"]), 2.3, 1e-9, "habitat XL power = M x 2.3")
	t.near(float(sim.sizes.def_for("research_lab", 2)["input_cap"]), 23.0, 1e-9, "unlisted capacity follows capacity_mult (12 x 1.9)")
	t.eq(sim.sizes.sizes_of("airlock"), [1], "an airlock has one size")
	t.eq(sim.sizes.allowed("airlock", 0)["code"], "no_size", "no size S for an airlock")
	t.eq(sim.sizes.allowed("habitat", 0)["code"], "ok", "size S is free")
	var l: Dictionary = sim.sizes.allowed("habitat", 2)
	t.eq(l["code"], "locked_research", "size L before research")
	t.eq(l["research"], "eng_1", "size L names its research")
	t.eq(sim.sizes.allowed("habitat", 3)["research"], "eng_2", "size XL names its research")
	# The same gate through a player command.
	var ctr: Vector2 = sim.world.center
	var r: Dictionary = g.cmd("place_building", {"def": "habitat", "x": ctr.x + 30, "y": ctr.y, "rot": 0.0, "size": 2})
	t.eq(r["code"], "locked_research", "place an L habitat before Structural Engineering")
	t.check(sim.place.reason_detail("habitat", 2, "locked_research").contains("Structural Engineering"), "the hint names the tech")
	_grant(sim, ["eng_1"])
	r = g.cmd("place_building", {"def": "habitat", "x": ctr.x + 30, "y": ctr.y, "rot": 0.0, "size": 2})
	t.check(bool(r["ok"]), "size L after eng_1: %s" % r["code"])
	if bool(r["ok"]):
		var b: Dictionary = sim.state["buildings"][r["id"]]
		t.eq(int(b["size"]), 2, "record size")
		t.eq(float(b["radius"]), 7.0, "record radius is the L radius")
		t.eq(b["cost"], sim.sizes.def_for("habitat", 2)["cost"], "record cost is the L cost")
		t.eq(b["cost"], {"metal": 9, "polymer": 7}, "L cost = M x 1.7, rounded")
		t.near(float(b["work_total"]), 16.0 * 10.0 * 1.6, 1e-6, "construction work = units x 10 x work_mult")
	# Size-dependent placement: an M greenhouse needs more room than an S one.
	t.eq(sim.place.check_building("greenhouse", ctr + Vector2(0, -11), 0.0, -1, 0), "ok", "S greenhouse fits beside the lander")
	t.eq(sim.place.check_building("greenhouse", ctr + Vector2(0, -11), 0.0, -1, 1), "overlap", "M greenhouse does not fit there")
	# Locked building.
	t.eq(sim.place.check_building("fusion_reactor", ctr + Vector2(-30, -30), 0.0), "locked_research", "fusion reactor before research")
	# Sized trays and tray offsets come from the effective definition.
	var gh: Dictionary = sim.sizes.def_for("greenhouse", 3)
	t.eq(int(gh["trays"]), 12, "XL greenhouse trays")
	t.eq((gh["tray_offsets"] as Array).size(), 12, "XL greenhouse tray places")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- levels
func v2_levels(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	t.near(float(sim.sizes.eff("solar_array", 1, 3)["gen_solar"]), 18.0, 1e-9, "solar M level 3 = 12 x 1.5")
	t.near(float(sim.sizes.eff("solar_array", 3, 5)["gen_solar"]), 74.8, 1e-6, "solar XL level 5 = 34 x 2.2")
	t.near(float(sim.sizes.eff("oxygen_plant", 1, 3)["power"]), 2.4, 1e-9, "oxygen plant level 3 power = 2 x 1.2")
	t.near(float(sim.sizes.eff("oxygen_plant", 1, 2)["o2_out"]), 25.0, 1e-9, "oxygen plant level 2 output = 20 x 1.25")
	t.eq(int(sim.sizes.eff("storehouse", 1, 2)["storage"]), 188, "storehouse level 2 storage = 150 x 1.25, rounded")
	t.near(float(sim.sizes.eff("battery", 1, 4)["energy_cap"]), 18.0, 1e-9, "battery level 4 = 10 x 1.8")
	t.near(float(sim.sizes.eff("mine", 1, 5)["wear_mult"]), 0.5, 1e-9, "level 5 wear")
	t.near(float(sim.sizes.eff("habitat", 1, 2)["comfort"]), 3.0, 1e-9, "habitat level 2 comfort")
	t.near(float(sim.sizes.eff("habitat", 1, 5)["comfort"]), 14.0, 1e-9, "habitat level 5 comfort")
	t.eq(int(sim.sizes.eff("habitat", 1, 5)["beds"]), 8, "comfort levels do not change the beds")
	t.near(float(sim.sizes.eff("kitchen", 1, 3)["level_mult"]), 1.5, 1e-9, "kitchen level 3 work speed")
	# Upgrade checks.
	var errors: Array = []
	var hab: Dictionary = H.spawn(sim, "habitat", H.SLOT["H1"], 0.0, errors)
	var lock: Dictionary = H.spawn(sim, "airlock", H.SLOT["L1"], PI, errors)
	t.check(errors.is_empty(), "set-up: %s" % str(errors))
	t.eq(sim.upgrades.check(lock)["code"], "not_upgradable", "an airlock has no levels")
	var c: Dictionary = sim.upgrades.check(hab)
	t.eq(c["code"], "locked_research", "level 2 before Structural Engineering")
	t.eq(c["research"], "eng_1", "level 2 research")
	t.eq(c["cost"], {"metal": 3, "polymer": 2}, "level 2 cost = cost x 0.5, rounded")
	_grant(sim, ["eng_1"])
	c = sim.upgrades.check(hab)
	t.check(bool(c["ok"]) and int(c["to"]) == 2, "level 2 allowed after eng_1")
	hab["level"] = 2      # test set-up
	c = sim.upgrades.check(hab)
	t.eq(c["research"], "eng_2", "level 3 research")
	t.eq(c["cost"], {"metal": 4, "polymer": 3, "electronics": 2}, "level 3 cost = cost x 0.8 + 2 electronics")
	hab["level"] = 4      # test set-up
	c = sim.upgrades.check(hab)
	t.eq(c["research"], "s_hab", "level 5 needs the family's special research")
	t.eq(int(c["cost"].get("exotic", 0)), 3, "level 5 needs exotic crystals")
	hab["level"] = 5      # test set-up
	t.eq(sim.upgrades.check(hab)["code"], "max_level", "level 5 is the top")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- upgrades
func v2_upgrade(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	H.set_clock(sim, 1, 30.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.6, true)
	_grant(sim, ["eng_1"])
	var hab: Dictionary = sim.state["buildings"][ids["H1"]]
	var r: Dictionary = g.cmd("upgrade", {"id": ids["H1"]})
	t.check(bool(r["ok"]), "upgrade accepted: %s" % r["code"])
	t.eq(String(hab["upgrade"].get("state", "")), "deliver", "the upgrade waits for materials")
	t.eq(g.cmd("upgrade", {"id": ids["H1"]})["code"], "busy", "a second order is refused")
	var metal0: int = H.world_count(sim, "metal")
	var created0: int = int(H.ledger_of(sim, "metal")["created"])
	var ok := true
	var saw_work := false
	for s in 900:
		g.run(10)
		if not sim.inv.audit().is_empty() or not H.inventory_problems(sim).is_empty():
			ok = false
		if String(hab.get("upgrade", {}).get("state", "")) == "work":
			saw_work = true
		if int(hab["level"]) == 2:
			break
	t.check(ok, "ledger and reservations sound during the upgrade: %s %s" % [str(sim.inv.audit()), str(H.inventory_problems(sim).slice(0, 2))])
	t.check(saw_work, "materials were delivered, then the work started")
	t.eq(int(hab["level"]), 2, "the habitat reached level 2")
	t.eq(hab["upgrade"], {}, "no upgrade left open")
	# Goal rewards (supply pods) may add steel meanwhile: count them in.
	var rewards: int = int(H.ledger_of(sim, "metal")["created"]) - created0
	t.eq(metal0 + rewards - H.world_count(sim, "metal"), 3, "exactly the upgrade's steel was used")
	t.eq(int(H.ledger_of(sim, "metal")["consumed"]), 3, "the ledger shows the steel built in")
	t.eq(int(sim.state["stats"]["upgrades"]), 1, "stats count the upgrade")
	t.check(not H.log_entries(sim, "upgraded").is_empty(), "the log says so")
	# Cancel: materials already delivered stay recoverable.
	var o2: Dictionary = sim.state["buildings"][ids["O1"]]
	r = g.cmd("upgrade", {"id": ids["O1"]})
	t.check(bool(r["ok"]), "second upgrade accepted: %s" % r["code"])
	g.run_until(func(): return sim.inv.total(int(o2["upgrade"].get("inv", -1))) > 0 if not (o2["upgrade"] as Dictionary).is_empty() else false, 3000)
	var delivered: int = sim.inv.total(int(o2["upgrade"].get("inv", -1))) if not (o2["upgrade"] as Dictionary).is_empty() else 0
	r = g.cmd("cancel_upgrade", {"id": ids["O1"]})
	t.check(bool(r["ok"]), "cancel accepted")
	t.eq(o2["upgrade"], {}, "the upgrade is gone")
	t.eq(int(o2["level"]), 1, "the level did not change")
	t.eq(sim.inv.audit(), {}, "ledger after the cancel")
	t.eq(H.inventory_problems(sim), [], "reservations after the cancel")
	t.note("upgrade done at %.0f s; %d units were on the cancelled upgrade" % [sim.seconds(), delivered])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- research
func v2_research(t) -> void:
	var c: Dictionary = _custom(t, BASE + LAB)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	H.set_clock(sim, 1, 30.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.6, true)
	t.eq(sim.research.state_of("agri_1"), "available", "agri_1 before any order")
	t.eq(sim.research.state_of("agri_2"), "locked", "agri_2 before agri_1")
	var r: Dictionary = g.cmd("research", {"tech": "agri_2"})
	t.check(bool(r["ok"]), "ordering agri_2 is accepted and queues its prerequisite")
	t.eq(String(sim.state["research"]["active"]), "agri_1", "the missing prerequisite starts first")
	t.eq(sim.research.state_of("agri_2"), "queued", "agri_2 waits in the queue")
	t.eq(sim.place.check_building("fungus_farm", sim.world.center + Vector2(-30, -30), 0.0), "locked_research", "fungus farm before research")
	var set_before: Dictionary = g.cmd("set_crop", {"id": -5, "crop": "tomato"})
	t.check(not bool(set_before["ok"]), "set_crop on a missing building is refused")
	var done1: bool = g.run_until(func(): return sim.research.is_done("agri_1"), 12000)
	t.check(done1, "a scientist finished agri_1 (%.1f RP)" % float(sim.state["research"]["progress"].get("agri_1", 0.0)))
	t.check(sim.research.crop_unlocked("tomato"), "tomatoes are unlocked")
	t.eq(String(sim.state["research"]["active"]), "agri_2", "the queue moved on")
	t.check(sim.research.rp_rate() > 0.0, "the RP rate is positive (%.1f per day)" % sim.research.rp_rate())
	t.check(not H.log_entries(sim, "research").is_empty(), "the log names the finished project")
	var t_agri1: float = sim.seconds()
	# Special research: RP only count after the crystals are at a lab.
	_grant(sim, ["agri_2", "agri_3", "agri_4", "eng_1", "eng_2", "ind_1", "ind_2", "eng_3"])
	r = g.cmd("research", {"tech": "s_agri"})
	t.check(bool(r["ok"]), "s_agri ordered")
	t.eq(String(sim.state["research"]["active"]), "s_agri", "s_agri is active")
	t.eq(sim.research.items_needed(), {"exotic": 8}, "it waits for 8 exotic crystals")
	g.run_seconds(60.0)
	t.eq(float(sim.state["research"]["progress"].get("s_agri", 0.0)), 0.0, "no progress without the crystals")
	var lander_store: int = sim.state["buildings"][sim.state["lander_id"]]["inv_out"]
	sim.inv.add_new_forced(lander_store, "exotic", 8, "test")      # test set-up: crystals in the lander
	var paid: bool = g.run_until(func(): return sim.research.is_paid("s_agri"), 6000)
	t.check(paid, "carriers brought the crystals and the project is paid")
	t.eq(int(H.ledger_of(sim, "exotic")["consumed"]), 8, "the crystals were used up")
	g.run_seconds(120.0)
	t.check(float(sim.state["research"]["progress"].get("s_agri", 0.0)) > 0.0, "progress after payment")
	t.eq(sim.inv.audit(), {}, "ledger")
	t.note("agri_1 done at %.0f s" % t_agri1)
	g.dispose()
	t.done()

# ---------------------------------------------------------------- crops
func v2_crops(t) -> void:
	var c: Dictionary = _custom(t, BASE + FOOD)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	for id in sim.content["crops"]:
		var cr: Dictionary = sim.content["crops"][id]
		if int(cr["cycle_seconds"]) <= 0:
			continue
		var u: Dictionary = sim.prod.harvest_units(id)
		t.eq(int(u.get(id, 0)), int(cr["yield"]), "%s yield" % id)
		t.eq(int(u.get("biomass", 0)), int(cr["biomass"]), "%s biomass" % id)
	t.eq(sim.prod.crops_for("greenhouse"), ["greens", "potato", "wheat"], "greenhouse crops at the start")
	var gh: Dictionary = sim.state["buildings"][ids["G1"]]
	t.eq(String(gh["crop"]), "potato", "default crop")
	t.eq(g.cmd("set_crop", {"id": ids["G1"], "crop": "tomato", "tray": -1})["code"], "locked_research", "tomatoes before Crop Genetics")
	t.eq(g.cmd("set_crop", {"id": ids["G1"], "crop": "mushroom", "tray": -1})["code"], "invalid", "mushrooms do not grow in a greenhouse")
	_grant(sim, ["agri_1"])
	t.check(bool(g.cmd("set_crop", {"id": ids["G1"], "crop": "tomato", "tray": 1})["ok"]), "tray 1 plans tomatoes")
	t.check(bool(g.cmd("set_crop", {"id": ids["G1"], "crop": "wheat", "tray": -1})["ok"]), "all trays plan wheat")
	t.check(bool(g.cmd("set_crop", {"id": ids["G1"], "crop": "tomato", "tray": 0})["ok"]), "tray 0 plans tomatoes")
	# Test set-up: nobody tends the trays; the test seeds tray 0 itself.
	H.set_priorities(g, {"food": 0})
	H.set_clock(sim, 1, 20.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.9, true)
	sim.prod.finish_seed(gh, 0)
	t.eq(String(gh["trays"][0]["grow"]), "tomato", "tray 0 grows its plan")
	t.eq(String(gh["trays"][1]["crop"]), "wheat", "tray 1 was re-planned by the all-trays order")
	g.run_seconds(230.0)
	t.eq(String(gh["trays"][0]["state"]), "growing", "tomatoes still grow at 230 s")
	t.near(sim.prod.tray_fraction(gh["trays"][0]), 230.0 / 240.0, 0.01, "growth fraction uses the tomato cycle")
	g.run_seconds(15.0)
	t.eq(String(gh["trays"][0]["state"]), "ready", "tomatoes are ready after 240 s")
	t.check(sim.prod.finish_harvest(gh, 0), "harvest")
	t.eq(sim.inv.count(gh["inv_out"], "tomato"), 4, "4 tomatoes in the output")
	t.eq(sim.inv.count(gh["inv_out"], "biomass"), 1, "1 biomass")
	t.eq(int(sim.state["stats"]["harvests"]), 1, "harvest counted")
	_grant(sim, ["agri_4"])
	t.eq(int(sim.prod.harvest_units("potato")["potato"]), 6, "Gene-tuned Crops: 5 x 1.25 rounds to 6")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- kitchen
func v2_kitchen(t) -> void:
	var c: Dictionary = _custom(t, BASE + FOOD)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	var k: Dictionary = sim.state["buildings"][ids["K1"]]
	t.eq(sim.prod.menu_of(k), ["algae_bar", "flatbread", "garden_salad", "mashed_potato"], "level 1 menu")
	t.eq(sim.prod.menu_pick(k), "", "nothing to cook without ingredients")
	var want: Dictionary = sim.prod.kitchen_wants(k)
	t.check(want.has("potato") and want.has("wheat") and want.has("greens"), "the kitchen asks for its crops: %s" % str(want))
	sim.inv.add_new_forced(k["inv_in"], "potato", 4, "test")     # test set-up
	sim.inv.add_new_forced(k["inv_in"], "wheat", 2, "test")      # test set-up
	var pick: String = sim.prod.menu_pick(k)
	t.check(pick == "mashed_potato" or pick == "flatbread", "a level-1 dish with its ingredients present: %s" % pick)
	sim.inv.add_new_forced(k["inv_in"], "soybean", 1, "test")    # test set-up
	sim.inv.add_new_forced(k["inv_in"], "greens", 1, "test")     # test set-up
	for a in H.alive_agents(sim):
		a["nutrition"] = {"protein": 5.0, "carbs": 60.0, "fat": 20.0, "vitamins": 40.0}   # test set-up: protein shortage
	sim.prod._colony_tick = -1       # test set-up: the planner reads the colony once per second
	t.check(sim.prod.menu_pick(k) != "soy_stew", "soy stew needs a level-2 kitchen")
	k["level"] = 2                                               # test set-up
	t.eq(sim.prod.menu_pick(k), "soy_stew", "with a protein shortage the planner picks soy stew")
	t.check(bool(g.cmd("set_dish", {"id": ids["K1"], "dish": "soy_stew", "on": false})["ok"]), "the player switches soy stew off")
	t.check(sim.prod.menu_pick(k) != "soy_stew", "a switched-off dish is not cooked")
	g.cmd("set_dish", {"id": ids["K1"], "dish": "soy_stew", "on": true})
	# A batch consumes the ingredients at once and reserves room for its dishes.
	H.set_clock(sim, 1, 20.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.6, true)
	t.check(sim.prod.start_batch(k), "a batch starts")
	t.eq(String(k["batch"].get("dish", "")), "soy_stew", "the batch cooks soy stew")
	t.eq(k["batch"]["outputs"], {"soy_stew": 3}, "3 ingredients make 3 dishes")
	t.near(float(k["batch"]["work"]), 30.0, 1e-9, "work = 3 dishes x 10")
	t.eq(sim.inv.count(k["inv_in"], "soybean"), 0, "the soybean is used")
	sim.prod.work_batch(k, 30.0)
	t.eq(sim.inv.count(k["inv_out"], "soy_stew"), 3, "3 soy stews in the output")
	t.eq(int(sim.state["stats"]["cooked"].get("soy_stew", 0)), 3, "cooked counter")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- nutrition
func v2_nutrition(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var a: Dictionary = H.alive_agents(sim)[0]
	# A new colonist starts at the ration level (50), so no goal is met by the start values.
	t.eq(a["nutrition"], {"protein": 50.0, "carbs": 50.0, "fat": 50.0, "vitamins": 50.0}, "a new colonist")
	a["nutrition"] = {"protein": 70.0, "carbs": 70.0, "fat": 70.0, "vitamins": 70.0}   # test set-up
	# Design change (coordinator, 2026-09-24): the values are a moving average of the diet,
	# not a linear decay. A colonist who eats keeps the levels; only a critically hungry one
	# drifts toward 0 (hungry_drift_per_day 30).
	a["hunger"] = 0.0                                                                   # test set-up
	for i in 600:
		sim.nutrition.decay_second(a)
	t.near(float(a["nutrition"]["protein"]), 70.0, 1e-6, "a fed colonist keeps the levels for a day")
	a["hunger"] = float(sim.bal["need_critical"])                                       # test set-up
	for i in 600:
		sim.nutrition.decay_second(a)
	t.near(float(a["nutrition"]["protein"]), 40.0, 1e-6, "a day critically hungry: 70 - 30")
	a["hunger"] = 0.0                                                                   # test set-up
	sim.nutrition.eat(a, "mashed_potato")
	# n + (dish - n) x 0.4 from 40: protein 20 -> 32, carbs 80 -> 56, fat 30 -> 36, vitamins 35 -> 38
	t.near(float(a["nutrition"]["protein"]), 32.0, 1e-6, "protein moves 40% toward the dish")
	t.near(float(a["nutrition"]["carbs"]), 56.0, 1e-6, "carbs move 40% toward the dish")
	t.near(float(a["nutrition"]["fat"]), 36.0, 1e-6, "fat after mashed potatoes")
	t.near(float(a["nutrition"]["vitamins"]), 38.0, 1e-6, "vitamins after mashed potatoes")
	t.eq(a["diet"], ["mashed_potato"], "the diet remembers the dish")
	t.eq(sim.nutrition.deficient(a), [], "nothing below 20")
	# A one-dish diet settles at that dish's values.
	for i in 40:
		sim.nutrition.eat(a, "mashed_potato")
	t.near(float(a["nutrition"]["protein"]), 20.0, 1e-3, "only mashed potatoes: protein settles at 20")
	t.near(float(a["nutrition"]["fat"]), 30.0, 1e-3, "only mashed potatoes: fat settles at 30")
	# The start dishes in turn never starve anybody; a varied mid-game diet is well fed.
	var low := 100.0
	for i in 60:
		sim.nutrition.eat(a, ["mashed_potato", "flatbread", "garden_salad"][i % 3])
		for k in a["nutrition"]:
			low = minf(low, float(a["nutrition"][k]))
	t.check(low >= float(sim.bal["nutrition"]["starved_below"]), "start dishes in turn: lowest value %.1f is above starved_below" % low)
	t.check(not sim.nutrition.starved(a), "start dishes in turn: not starved")
	var wf := 0
	for i in 60:
		sim.nutrition.eat(a, ["soy_stew", "tofu_stirfry", "veggie_pizza"][i % 3])
		if i >= 20 and sim.nutrition.well_fed(a):
			wf += 1
	t.eq(wf, 40, "soy stew, stir-fry and pizza in turn: well fed after every meal (score %.1f)" % sim.nutrition.score(a))
	a["nutrition"] = {"protein": 19.0, "carbs": 80.0, "fat": 50.0, "vitamins": 50.0}   # test set-up
	t.eq(sim.nutrition.deficient(a), ["protein"], "protein below 20 is a deficiency")
	t.check(not sim.nutrition.starved(a), "not yet starved")
	t.near(sim.nutrition.work_mult(a), 0.9, 1e-9, "deficient work")
	a["nutrition"]["protein"] = 7.0                                                    # test set-up
	t.check(sim.nutrition.starved(a), "protein below 8: starved")
	a["nutrition"] = {"protein": 80.0, "carbs": 80.0, "fat": 80.0, "vitamins": 45.0}   # test set-up
	t.check(sim.nutrition.well_fed(a), "score 71, every value 40 or more: well fed")
	t.near(sim.nutrition.regen_mult(a), 1.5, 1e-9, "well fed heal faster")
	for d in ["flatbread", "garden_salad", "soy_stew", "herb_potatoes", "tofu_stirfry", "algae_bar"]:
		sim.nutrition.eat(a, d)
	t.eq((a["diet"] as Array).size(), 6, "the diet keeps six dishes")
	t.eq(a["diet"][0], "flatbread", "the oldest dish fell out")
	t.check(sim.nutrition.morale_delta(a) >= 5.0, "variety raises morale (%.1f)" % sim.nutrition.morale_delta(a))
	# Choice: with little protein, the protein dish wins; ties go by id.
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100, sim.world.center + Vector2(20, 20))
	sim.inv.add_new_forced(pile, "mashed_potato", 1, "test")   # test set-up
	sim.inv.add_new_forced(pile, "soy_stew", 1, "test")        # test set-up
	a["nutrition"] = {"protein": 5.0, "carbs": 90.0, "fat": 50.0, "vitamins": 60.0}   # test set-up
	a["diet"] = ["soy_stew", "soy_stew", "soy_stew"]                                # test set-up
	t.eq(sim.nutrition.choose(a, pile), "soy_stew", "protein first, even without novelty")
	a["nutrition"] = {"protein": 90.0, "carbs": 5.0, "fat": 90.0, "vitamins": 90.0}  # test set-up
	t.eq(sim.nutrition.choose(a, pile), "mashed_potato", "carbs first")
	var col: Dictionary = sim.nutrition.colony()
	t.eq(int(col["people"]), 8, "colony average over 8 people")
	t.check(col.has("score") and col.has("protein"), "colony() has every field")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- spoilage
func v2_spoilage(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	var sim = g.sim
	var pile: int = sim.inv.create_inv("g", 0, "pile", 1000, sim.world.center + Vector2(20, 22))
	sim.inv.add_new_forced(pile, "potato", 10, "test")        # test set-up
	sim.inv.add_new_forced(pile, "metal", 10, "test")         # test set-up: never spoils
	var kin: int = sim.inv.create_inv("b", 0, "in", 100)      # test set-up: a machine input buffer
	sim.inv.add_new_forced(kin, "potato", 10, "test")
	for i in 599:
		sim.prod.spoil_second()
	t.eq(sim.inv.count(pile, "potato"), 10, "599 s: nothing spoiled (10 potatoes, shelf 10 days)")
	sim.prod.spoil_second()
	t.eq(sim.inv.count(pile, "potato"), 9, "600 s: exactly one potato spoiled")
	t.eq(int(H.ledger_of(sim, "potato")["destroyed"]), 1, "the ledger says destroyed")
	t.eq(sim.inv.count(pile, "metal"), 10, "steel does not spoil")
	t.eq(sim.inv.count(kin, "potato"), 10, "input buffers do not spoil")
	t.eq(int(sim.state["stats"]["spoiled"].get("potato", 0)), 1, "spoiled counter")
	# Reserved units are being handled: they do not spoil.
	var h: int = sim.inv.hold_out(pile, "potato", 9, 999999)
	for i in 1200:
		sim.prod.spoil_second()
	t.eq(sim.inv.count(pile, "potato"), 9, "reserved units keep")
	sim.inv.release(h)
	# Cold storage keeps food.
	_grant(sim, ["agri_1", "log_1"])
	var errors: Array = []
	var cold: Dictionary = H.spawn(sim, "cold_storage", H.SLOT["S1"], 0.0, errors)
	t.check(errors.is_empty(), "set-up: %s" % str(errors))
	if not cold.is_empty():
		sim.inv.add_new_forced(cold["inv_out"], "tomato", 20, "test")   # shelf 4 days
		for i in 2400:
			sim.prod.spoil_second()
		t.eq(sim.inv.count(cold["inv_out"], "tomato"), 20, "cold storage: no tomato spoiled in 4 days")
	# The relaxed difficulty has no spoilage.
	var before: int = sim.inv.count(pile, "potato")
	sim.state["options"]["spoilage"] = false      # test set-up
	for i in 1200:
		sim.prod.spoil_second()
	t.eq(sim.inv.count(pile, "potato"), before, "spoilage off: nothing spoils")
	t.eq(sim.inv.audit(), {}, "ledger")
	var r = H.Sim.new()
	r.new_game(1001, "tutorial", {"difficulty": "relaxed"})
	t.eq(bool(r.state["options"]["spoilage"]), false, "a relaxed game has spoilage off")
	t.eq(int(sim.state["buildings"][sim.state["lander_id"]]["id"]), int(sim.state["lander_id"]), "lander")
	r.dispose()
	g.dispose()
	t.done()

# ---------------------------------------------------------------- goals
func v2_goals(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	var sim = g.sim
	var ids: Dictionary = c["ids"]
	H.set_clock(sim, 1, 10.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.8, true)
	t.eq(sim.goals.chapter(), 0, "chapter 1 is open")
	var list: Array = sim.goals.list()
	t.eq(String(list[0]["state"]), "active", "chapter 1 goals are active")
	t.eq(String(list[list.size() - 1]["state"]), "locked", "chapter 5 goals are locked")
	sim.goals._open_chapter(1)                     # test set-up: straight to chapter 2
	g.run_seconds(3.0)
	var st: Dictionary = sim.state["goals"]["status"]["o2_supply"]
	t.check(int(st["since"]) >= 0, "the oxygen condition holds (ratio %.2f)" % float(st["value"]))
	g.run_seconds(100.0)
	g.cmd("set_enabled", {"id": ids["O1"], "on": false})
	g.run_seconds(2.0)
	t.eq(int(st["since"]), -1, "switching the plant off breaks the timer")
	t.eq(String(st["state"]), "active", "and the goal is not done")
	g.cmd("set_enabled", {"id": ids["O1"], "on": true})
	g.run_seconds(3.0)
	var since: int = int(st["since"])
	t.check(since > 0, "the timer starts again")
	g.run_until(func(): return String(st["state"]) == "done", 7000)
	t.eq(String(st["state"]), "done", "the goal completes")
	t.near(float(int(st["done_tick"]) - since) / 10.0, 600.0, 1.01, "after exactly 600 s without a break")
	var pods: Array = []
	for inv_id in sim.state["inventories"]:
		if bool(sim.state["inventories"][inv_id].get("pod", false)):
			pods.append(inv_id)
	t.check(not pods.is_empty(), "a supply pod landed")
	var elec := 0
	for p in pods:
		elec += sim.inv.count(p, "electronics")
	t.check(elec >= 2 or int(H.ledger_of(sim, "electronics")["created"]) >= 2, "the pod holds the reward electronics")
	t.check(float(sim.state["research"]["bank"]) >= 20.0 or float(sim.state["research"]["rp_total"]) >= 20.0, "the RP reward was kept")
	t.check(not H.log_entries(sim, "goal").is_empty(), "the log names the goal")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- awards
func v2_awards(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	var sim = g.sim
	H.set_clock(sim, 1, 10.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.8, true)
	g.run_seconds(6.0)
	t.check(sim.state["awards"].has("first_breath"), "First Breath is earned when the base has air")
	var tick0: int = int(sim.state["awards"].get("first_breath", -1))
	g.run_seconds(30.0)
	t.eq(int(sim.state["awards"].get("first_breath", -2)), tick0, "the award keeps its first tick")
	var n := 0
	for e in H.log_entries(sim, "award"):
		if String(e["text"]).contains("First Breath"):
			n += 1
	t.eq(n, 1, "one log line for the award")
	var listed := false
	for a in sim.awards.list():
		if a["id"] == "first_breath":
			listed = int(a["earned"]) == tick0
	t.check(listed, "awards.list() reports it")
	t.check(sim.awards.points() >= 10, "tier points")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- the Meridian
func v2_meridian_place(t) -> void:
	var seeds: Array = H.Sim.new().content["scenarios"]["tutorial"]["tutorial_seeds"]
	var dists: Array = []
	for s in seeds:
		for planet in ["dry", "cold", "airless"]:
			if planet != "dry" and int(s) != 1001:
				continue
			var sim = H.Sim.new()
			sim.new_game(int(s), "tutorial", {"planet": planet})
			var ship: Dictionary = sim.ship.record()
			if not t.check(not ship.is_empty(), "seed %d %s: the Meridian exists" % [int(s), planet]):
				sim.dispose()
				continue
			var d: float = (ship["pos"] as Vector2).distance_to(sim.world.center)
			dists.append(int(d))
			t.check(d >= 54.9 and d <= 75.1, "seed %d %s: 55..75 m from the lander (%.1f)" % [int(s), planet, d])
			var seg: Array = Ship.segment_of(ship)
			var clear := true
			for rock in sim.world.rocks:
				var rp := Vector2(rock["x"], rock["y"])
				if Geometry2D.get_closest_point_to_segment(rp, seg[0], seg[1]).distance_to(rp) < float(ship["radius"]) + float(rock["r"]):
					clear = false
			t.check(clear, "seed %d %s: no rock under the hull" % [int(s), planet])
			t.check(not sim.nav.is_walkable(ship["pos"]), "seed %d %s: nobody walks through the hull" % [int(s), planet])
			t.eq(sim.place.check_building("battery", ship["pos"], 0.0), "overlap_ship", "seed %d %s: nothing is built on the hull" % [int(s), planet])
			t.check(sim.nav.access_points(ship).size() >= 4, "seed %d %s: work places around the hull (%d)" % [int(s), planet, sim.nav.access_points(ship).size()])
			t.check(int(sim.state["ship"]["stage"]) == 0 and sim.state["ship"]["id"] == ship["id"], "seed %d %s: state.ship names the wreck" % [int(s), planet])
			var again = H.Sim.new()
			again.new_game(int(s), "tutorial", {"planet": planet})
			var ship2: Dictionary = again.ship.record()
			t.check((ship2["pos"] as Vector2) == (ship["pos"] as Vector2) and float(ship2["rot"]) == float(ship["rot"]), "seed %d %s: the same place every time" % [int(s), planet])
			again.dispose()
			sim.dispose()
	t.note("distances %s" % str(dists))
	t.done()

func v2_meridian_stages(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var sh: Dictionary = sim.state["ship"]
	var b: Dictionary = sim.ship.record()
	t.eq(sim.ship.repairing(), false, "no work before the Meridian chapter or an order")
	t.check(bool(g.cmd("ship", {"action": "survey"})["ok"]), "survey ordered")
	t.check(sim.ship.repairing(), "the program runs")
	t.eq(sim.ship.work_kind(), "repair", "stage 0 is work (the survey)")
	sim.ship.add_work(60.0)
	sim.ship.tick_second()
	t.eq(int(sh["stage"]), 1, "surveyed: stage 1 (Hull)")
	t.eq(String(sh["phase"]), "deliver", "the hull needs parts first")
	t.eq(sim.ship.missing(), {"hull_plate": 30, "metal": 40}, "missing parts")
	for stage in [1, 2, 3]:
		var need: Dictionary = sim.bal["ship"]["stages"][stage]["deliver"]
		for k in need:
			sim.inv.add_new_forced(b["inv_site"], k, int(need[k]), "test")      # test set-up: parts delivered
		sim.ship.tick_second()
		t.eq(String(sh["phase"]), "work", "stage %d: parts built in" % stage)
		sim.ship.add_work(float(sim.bal["ship"]["stages"][stage]["work"]))
		sim.ship.tick_second()
		t.eq(int(sh["stage"]), stage + 1, "stage %d done" % stage)
	t.check(float(sh["flight_t"]) >= 0.0, "the test flight starts")
	for i in 401:
		sim.ship.tick()
	t.eq(int(sh["stage"]), 5, "operational after the flight")
	t.near(float(sh["readiness"]), 100.0, 1e-6, "readiness 100")
	for i in 600:
		sim.ship.tick_second()
	t.near(float(sh["readiness"]), 92.0, 0.01, "readiness falls 8 per day")
	t.eq(sim.ship.run_block(), "locked_research", "no supply run before Orbital Logistics")
	_grant(sim, ["space_2"])
	t.eq(sim.ship.run_block(), "no_comms", "no supply run without a comms tower")
	t.eq(sim.ship.work_kind(), "", "no maintenance above 90 %")
	for i in 600:
		sim.ship.tick_second()
	t.near(float(sh["readiness"]), 84.0, 0.01, "two days: 84 %")
	t.eq(sim.ship.work_kind(), "", "maintenance waits for its parts")
	sim.inv.add_new_forced(b["inv_site"], "rocket_fuel", 1, "test")     # test set-up
	sim.inv.add_new_forced(b["inv_site"], "spare_parts", 1, "test")     # test set-up
	t.eq(sim.ship.work_kind(), "maint", "maintenance can start")
	sim.ship.add_work(40.0)
	t.near(float(sh["readiness"]), 99.0, 0.01, "maintenance adds 15")
	t.eq(int(sim.state["stats"]["ship_maintenance"]), 1, "maintenance counted")
	t.eq(sim.inv.audit(), {}, "ledger")
	var info: Dictionary = sim.ship.info()
	t.check(info.has("stage_name") and info.has("readiness") and info.has("run_block"), "ship.info() fields")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- charts
func v2_series(t) -> void:
	var g = H.reference_game(1001)
	g.run_to_tick(6001)
	var sim = g.sim
	for name in ["pop", "morale", "nutrition", "o2_stock", "o2_make", "o2_use", "water_stock", "water_in", "water_out",
			"power_gen", "power_use", "energy", "food_days", "rp_rate", "ship_readiness"]:
		var s: Array = sim.metrics.series(name)
		t.eq(s.size(), 60, "series %s has one point per 10 s" % name)
	var pop: Array = sim.metrics.series("pop")
	t.eq(int(pop[0][0]), 100, "first sample at tick 100")
	t.near(float(pop[59][1]), 8.0, 1e-9, "pop value")
	var items: Array = sim.metrics.series("item:metal")
	t.eq(items.size(), 10, "item series every 60 s")
	t.eq((sim.state["metrics"]["daily"] as Array).size(), 1, "one daily row after day 1")
	var row: Dictionary = sim.state["metrics"]["daily"][0]
	t.eq(int(row["day"]), 1, "the row is day 1")
	t.check(row.has("produced") and row.has("consumed"), "the row has produced and consumed")
	t.note("save %d bytes with %d series" % [sim.save_bytes().size(), sim.metrics.series_names().size()])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- migration
func v2_migration(t) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://content/saves/showcase_day9.fhsave")
	t.check(bytes.size() > 1000, "the version-1 save is there")
	var raw := StreamPeerBuffer.new()
	raw.data_array = bytes
	raw.seek(8)
	t.eq(raw.get_u32(), 1, "it is schema 1")
	var dec: Dictionary = Persistence.decode(bytes)
	if not t.check(bool(dec["ok"]), "it decodes: %s" % dec.get("error", "")):
		t.done()
		return
	var s: Dictionary = dec["state"]
	t.eq(int(s["schema"]), 2, "migrated to schema 2")
	var raw_left := 0
	for iid in s["inventories"]:
		raw_left += int(s["inventories"][iid]["items"].get("raw_food", 0))
	t.eq(raw_left, 0, "no raw food is left in any inventory")
	t.check(not s["ledger"].has("raw_food"), "the ledger has no raw food")
	t.eq(int(s["ledger"]["potato"]["created"]), 192, "raw food created (192) became potatoes")
	var sim = H.Sim.new()
	sim.load_state(s)
	t.eq(sim.inv.audit(), {}, "ledger right after the load")
	t.eq(H.inventory_problems(sim), [], "reservations right after the load")
	var ship: Dictionary = sim.ship.record()
	t.check(not ship.is_empty(), "the Meridian was placed on the old map")
	var clear := true
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["def"] == "meridian" or b["kind"] == "link":
			continue
		if Ship.surface_distance(ship, b["pos"]) < float(b["radius"]):
			clear = false
	t.check(clear, "it overlaps no structure of the old colony")
	var alive0: int = sim.alive_count()
	var starving_seen: Array = []
	for i in 12000:
		sim.step()
		if i % 10 == 9:
			for key in sim.state["issues"]:
				var issue: Dictionary = sim.state["issues"][key]
				if issue["code"] == "starving" or issue["code"] == "thirsty":
					if starving_seen.size() < 3:
						starving_seen.append("t+%d s: %s" % [i / 10, issue["text"]])
		if i % 600 == 0:
			if not sim.inv.audit().is_empty():
				t.fail("ledger at tick %d: %s" % [i, str(sim.inv.audit())])
	t.eq(starving_seen, [], "no starving or thirst alert in the two days after the load")
	t.eq(sim.inv.audit(), {}, "ledger after two days")
	t.eq(H.inventory_problems(sim), [], "reservations after two days")
	t.eq(sim.alive_count(), alive0, "nobody died in the two days after the load")
	t.check(int(sim.state["stats"].get("cooked_total", 0)) > 0, "the old kitchen cooks dishes now")
	t.check(sim.goals.chapter() >= 1, "chapter 1 completes at once for a day-9 colony (chapter %d)" % sim.goals.chapter())
	t.note("%d alive, %d dishes cooked, chapter %d, save %d bytes" % [sim.alive_count(), int(sim.state["stats"].get("cooked_total", 0)), sim.goals.chapter() + 1, sim.save_bytes().size()])
	sim.dispose()
	t.done()

# ---------------------------------------------------------------- dust storm
## Stretch item 12: never before the scenario's no_disaster_days (5), a warning first,
## solar and outdoor speed cut while it lasts, restored after, and exact across a save.
func v2_storm(t) -> void:
	var g = H.reference_game(1001)
	var sim = g.sim
	var hz: int = int(sim.bal["tick_hz"])
	var day_ticks: int = int(sim.bal["day_length"]) * hz
	var first: int = int(sim.content["scenarios"]["tutorial"]["no_disaster_days"]) * day_ticks
	var early := 0
	while g.tick() < first:
		g.run(100)
		if sim.events.active() or float(sim.state["env"]["solar_mult"]) != 1.0:
			early += 1
	t.eq(early, 0, "no storm in the first %d days" % (first / day_ticks))
	var came: bool = g.run_until(func(): return sim.events.active(), 4 * day_ticks)
	if not t.check(came, "a storm comes within four days after that"):
		g.dispose()
		t.done()
		return
	var st: Dictionary = sim.events.storm().duplicate()   # the record is reused for the next storm
	t.check(g.tick() >= first, "the storm starts on or after day %d (tick %d)" % [first / day_ticks + 1, g.tick()])
	var warned := false
	for e in sim.state["log"]:
		if e["code"] == "storm_warning" and int(st["at"]) - int(e["tick"]) >= int(sim.bal["storm"]["warning_seconds"]) * hz:
			warned = true
	t.check(warned, "a warning came at least %d s before" % int(sim.bal["storm"]["warning_seconds"]))
	t.near(float(sim.state["env"]["solar_mult"]), float(sim.bal["storm"]["solar_mult"]), 1e-9, "solar output is cut")
	t.near(sim.util.out_speed(), float(sim.bal["speed_outdoor"]) * float(sim.bal["storm"]["speed_mult"]), 1e-9, "walking outside is slower")
	# A save taken during the storm continues exactly like the running game.
	var c: Dictionary = H.clone_by_save(sim)
	t.check(bool(c["ok"]), "saved during the storm")
	var sim2 = c["sim"]
	# Both games step without the reference driver from here, so only the save differs.
	var end_tick: int = int(st["end"])
	while sim.events.active() and int(sim.state["tick"]) < end_tick + 10:
		sim.step()
	t.check(not sim.events.active() and int(sim.state["tick"]) == end_tick, "the storm ends at its end tick")
	t.near(float(sim.state["env"]["solar_mult"]), 1.0, 1e-9, "solar output is back")
	t.near(float(sim.state["env"]["speed_mult"]), 1.0, 1e-9, "walking speed is back")
	t.eq(int(sim.state["stats"].get("storms", 0)), 1, "one storm counted")
	sim.run_seconds(30.0)
	while int(sim2.state["tick"]) < int(sim.state["tick"]):
		sim2.step()
	t.eq(H.digest(sim2), H.digest(sim), "the loaded game gives the same state after the storm")
	sim2.dispose()
	t.eq(sim.inv.audit(), {}, "ledger")
	t.note("storm from day %.2f for %d s" % [float(st["at"]) / float(day_ticks) + 1.0, (int(st["end"]) - int(st["at"])) / hz])
	# Storms off (a game option): nothing in the same days.
	var g2 = H.Game.new(1001, true)
	g2.sim.state["options"]["storms"] = false      # test set-up
	g2.run_to_tick(g.tick())
	t.check(g2.sim.events.storm().is_empty(), "with storms off no storm is made")
	g2.dispose()
	g.dispose()
	t.done()
