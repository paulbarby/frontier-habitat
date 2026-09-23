extends RefCounted
## Acceptance tests of spec section 16, plus the phase 1 exit gate (spec 15).
## Two kinds of set-up are used (see helpers.gd): the reference layout played through
## submit(), and instant custom layouts. Direct field writes are TEST SET-UP only and are
## marked as such.

const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")

const BASE := [
	{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"},
]
const FOOD := [
	{"place": "kitchen", "as": "K1"}, {"link": "corridor", "a": "H1", "b": "K1"},
	{"place": "greenhouse", "as": "G1"}, {"link": "corridor", "a": "K1", "b": "G1"},
]

func tests() -> Array:
	return [
		["phase1_replay_10_days_save_load", phase1_replay],
		["a01_a05_conservation_and_reservations", a01_conservation],
		["a02_disconnected_district", a02_disconnected],
		["a03_night_transition_and_shedding", a03_night],
		["a04_transport_matters", a04_transport],
		["a06_emergency_ai_suit_return", a06_emergency],
		["a07_airlock_congestion", a07_airlock],
		["a08_crop_failure_and_recovery", a08_crop],
		["a09_save_continuity_exactly_once", a09_save],
		["a10_demolition_is_never_silent", a10_demolition],
		["a11_alert_causality_one_root", a11_alerts],
		["a12_opening_viability_all_seeds", a12_opening],
		["a14_loss_report_and_recovery", a14_loss],
		["u01_far_site_reports_suit_range", u01_far_site],
	]

# ---------------------------------------------------------------- reported by the player
## A plan on the far side of the station stopped all building with no reason shown.
## The cause was suit range after the lander air ended. It must be reported, and nobody
## may walk out to a place they cannot return from.
func u01_far_site(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	H.set_clock(g.sim, 4, 60.0)          # the lander hatch no longer has air
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.5, true)
	g.run(2)                              # let the air reading catch up before measuring reach
	var ctr: Vector2 = g.sim.world.center
	var reach: float = g.sim.agents.suit_reach_metres()
	t.check(reach > 60.0, "suit reach is a usable distance (%d m)" % int(reach))
	var site := -1
	for x in range(-int(reach) - 14, -int(reach) - 60, -4):
		for y in [0, 10, -10, 20, -20]:
			if site != -1:
				continue
			var p := Vector2(ctr.x + x, ctr.y + y)
			if g.sim.place.check_building("solar_array", p, 0.0) == "ok" and g.sim.agents.nearest_air_metres(p) > reach * 1.05:
				var r: Dictionary = g.cmd("place_building", {"def": "solar_array", "x": p.x, "y": p.y, "rot": 0.0})
				if r["ok"]:
					site = int(r["id"])
	if not t.check(site != -1, "a legal far site exists on this seed"):
		t.done()
		return
	# Carrying has no work time, so materials may still arrive; the building work cannot.
	var b: Dictionary = g.sim.state["buildings"][site]
	g.run_until(func(): return String(b["block"]) == "suit_range", 6000)
	t.eq(String(b["block"]), "suit_range", "the plan shows why nobody works on it")
	var issues: Array = H.issues_with_code(g.sim, "suit_range")
	t.check(not issues.is_empty(), "an alert names the cause")
	if not issues.is_empty():
		t.check(String(issues[0]["action"]).contains("airlock"), "and says what to do: %s" % issues[0]["action"])
	t.eq(H.alive_agents(g.sim).size(), 8, "nobody walked out to a place without a way back")
	t.note("reach %d m" % int(reach))
	t.done()

## Test set-up: nobody is tired, hungry or thirsty, so nobody walks anywhere by need.
func _calm(g) -> void:
	for a in H.alive_agents(g.sim):
		a["fatigue"] = 0.0
		a["hunger"] = 0.0
		a["thirst"] = 0.0

func _custom(t, steps: Array, seed_value: int = 1001) -> Dictionary:
	var g = H.empty_game(seed_value)
	var res: Dictionary = H.layout(g.sim, H.CORE_STEPS + steps)
	for e in res["errors"]:
		t.fail(e)
	return {"g": g, "ids": res["ids"]}

# ---------------------------------------------------------------- phase 1 gate
func phase1_replay(t) -> void:
	var a = H.reference_game(1001)
	a.run_to_tick(27013)          # day 5, mid-morning: carriers and a kitchen batch are in progress
	var mid: String = H.digest(a.sim)
	var clone: Dictionary = H.clone_by_save(a.sim)
	if not t.check(clone["ok"], "the save decodes"):
		t.done()
		return
	t.eq(Persistence.digest(clone["sim"].state), mid, "state digest right after load")
	var b = H.Game.new(1001, false)
	b.sim.dispose()
	b.sim = clone["sim"]
	b.ref = H.copy_reference(a.ref, b.sim)
	a.run_to_tick(60000)
	b.run_to_tick(60000)
	t.eq(H.digest(b.sim), H.digest(a.sim), "digest at day 10: saved-and-loaded game vs uninterrupted game")
	t.eq(a.sim.inv.audit(), {}, "ledger after 10 days")
	t.eq(H.alive_agents(a.sim).size(), 8, "colonists alive after 10 days")
	t.note("save %d bytes" % clone["bytes"])
	var c = H.reference_game(1001)
	var d = H.reference_game(1001)
	var e = H.reference_game(1002)
	c.run_to_tick(6000)
	d.run_to_tick(6000)
	e.run_to_tick(6000)
	t.eq(H.digest(c.sim), H.digest(d.sim), "two fresh runs of seed 1001")
	t.check(H.digest(c.sim) != H.digest(e.sim), "seed 1002 differs from seed 1001")
	t.done()

# ---------------------------------------------------------------- 1 and 5
func a01_conservation(t) -> void:
	var g = H.reference_game(1001)
	var extra := -1
	var killed := false
	var delivered_before_cancel := 0
	for s in 900:
		g.run(10)
		var p: Array = H.inventory_problems(g.sim)
		if not p.is_empty():
			t.fail("second %d: %s" % [s, p[0]])
		t.eq(g.sim.inv.audit(), {}, "ledger at second %d" % s)
		if s == 30:
			var c: Vector2 = g.sim.world.center
			var r: Dictionary = g.cmd("place_building", {"def": "solar_array", "x": c.x + 8.0, "y": c.y - 30.0, "rot": 0.0})
			t.check(r["ok"], "extra blueprint accepted: %s" % r.get("code", ""))
			extra = int(r.get("id", -1))
		if s == 110 and extra != -1 and g.sim.state["buildings"].has(extra):
			var site: Dictionary = g.sim.state["buildings"][extra]
			delivered_before_cancel = g.sim.inv.total(site["inv_site"]) if int(site["inv_site"]) != -1 else 0
			var r2: Dictionary = g.cmd("cancel", {"id": extra})
			t.check(r2["ok"], "cancel accepted")
			for hid in g.sim.state["holds"]:
				t.check(int(g.sim.state["tasks"].get(g.sim.state["holds"][hid]["owner"], {}).get("bld", -2)) != extra, "no hold is left for the cancelled plan")
		if s >= 140 and not killed:
			for tid in g.sim.state["tasks"]:
				var task: Dictionary = g.sim.state["tasks"][tid]
				if task["kind"] == "haul" and bool(task["picked"]):
					var victim: int = int(task["owner"])
					g.cmd("kill_agent", {"id": victim, "cause": "test"})
					killed = true
					t.check(not g.sim.state["tasks"].has(tid), "the dead carrier's task is gone")
					for hid in g.sim.state["holds"]:
						t.check(int(g.sim.state["holds"][hid]["owner"]) != tid, "the dead carrier's holds are released")
					break
	t.check(killed, "a carrier with cargo was found and killed")
	t.check(int(g.sim.state["metrics"].get("delivered", 0)) >= 20, "at least ten deliveries happened (%d units)" % int(g.sim.state["metrics"].get("delivered", 0)))
	t.note("%d units delivered, %d units were on the cancelled site" % [int(g.sim.state["metrics"].get("delivered", 0)), delivered_before_cancel])
	t.done()

# ---------------------------------------------------------------- 2
func a02_disconnected(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	var ids: Dictionary = c["ids"]
	H.set_clock(g.sim, 1, 420.0)      # night: no solar, so every unit of energy is accountable
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.5, true)
	g.run(20)
	var blds: Dictionary = g.sim.state["buildings"]
	t.check(blds[ids["H1"]]["powered"], "habitat is powered while joined")
	var cable: int = H.find_link(g.sim, "cable", ids["A1"], ids["O1"])
	H.unlink_now(g.sim, cable)
	g.run(5)
	var e0: int = H.battery_energy(g.sim, [ids["B1"]])
	var w0: int = H.reservoir_water(g.sim, [ids["R1"]])
	g.run(100)
	for k in ["O1", "L1", "H1", "W1"]:
		t.check(not bool(blds[ids[k]]["powered"]), "%s has no power after the only cable is cut" % k)
	t.eq(H.battery_energy(g.sim, [ids["B1"]]), e0, "the battery on the far side keeps its energy")
	t.eq(H.reservoir_water(g.sim, [ids["R1"]]), w0, "the reservoir is neither filled nor drained without power")
	t.check(not g.sim.topo.same_power(ids["B1"], ids["H1"]), "battery and habitat are different power components")
	# Atmosphere: cut the corridor, one person stays in the habitat.
	# Test set-up: one person in the habitat, everybody else in the lander, no work to do,
	# so only that one person breathes the habitat air.
	H.set_priorities(g, {"construction": 0, "food": 0, "industry": 0, "logistics": 0, "repair": 0})
	_calm(g)
	var person: Dictionary = H.alive_agents(g.sim)[0]
	for a in H.alive_agents(g.sim):
		H.put_inside(g.sim, a, int(g.sim.state["lander_id"]))
	H.put_inside(g.sim, person, ids["H1"])
	var corridor: int = H.find_link(g.sim, "corridor", ids["L1"], ids["H1"])
	H.unlink_now(g.sim, corridor)
	g.run(3)
	t.check(not g.sim.topo.same_atmo(ids["O1"], ids["H1"]), "cutting the corridor separates the air")
	var o_h: int = H.oxygen_of(g.sim, [ids["H1"]])
	var o_rest: int = H.oxygen_of(g.sim, [ids["O1"], ids["L1"]])
	g.run(30)
	t.check(H.oxygen_of(g.sim, [ids["H1"]]) < o_h, "the cut-off habitat only loses oxygen")
	t.eq(H.oxygen_of(g.sim, [ids["O1"], ids["L1"]]), o_rest, "the other side is not breathed by the cut-off room")
	t.eq(H.utility_problems(g.sim), [], "no stock is negative or over capacity")
	t.done()

# ---------------------------------------------------------------- 3
func a03_night(t) -> void:
	var c: Dictionary = _custom(t, BASE + [{"place": "kitchen", "as": "K1"}, {"link": "corridor", "a": "H1", "b": "K1"},
		{"place": "storehouse", "as": "S1"}, {"link": "corridor", "a": "H1", "b": "S1"}])
	var g = c["g"]
	var ids: Dictionary = c["ids"]
	H.set_clock(g.sim, 1, 400.0)
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.5, true)
	g.run(60)      # let the minimum-off timers of the first dark ticks end
	var comp: int = g.sim.topo.power_comp[ids["B1"]]
	var before: int = H.battery_energy(g.sim, [ids["B1"]])
	g.run(1)
	var ps: Dictionary = g.sim.util.power_stats[comp]
	t.eq(int(ps["gen"]), 0, "solar output at night")
	t.check(int(ps["served"]) > 0 and (ps["shed"] as Array).is_empty(), "every load runs from the battery")
	t.eq(before - H.battery_energy(g.sim, [ids["B1"]]), int(ps["served"]), "battery discharge in one tick equals the served demand")
	# A nearly empty battery: loads must go in priority order, comfort and industry first.
	var blds: Dictionary = g.sim.state["buildings"]
	blds[ids["B1"]]["energy"] = 30         # test set-up: enough for 3.0 P for one tick
	g.run(1)
	var order: Array = g.sim.state["policies"]["power_order"]
	var worst_on := -1
	var best_off := 999
	for k in ["W1", "O1", "L1", "H1", "K1", "S1"]:
		var b: Dictionary = blds[ids[k]]
		var cls: int = order.find(g.sim.bdef(b["def"])["power_class"])
		if bool(b["powered"]):
			worst_on = maxi(worst_on, cls)
		else:
			best_off = mini(best_off, cls)
	t.check(best_off < 999, "some loads were shed")
	t.check(worst_on <= best_off, "no lower class keeps power while a higher class is off (on up to class %d, off from class %d)" % [worst_on, best_off])
	t.check(not bool(blds[ids["S1"]]["powered"]) and not bool(blds[ids["K1"]]["powered"]), "industry and food are off before life support")
	t.eq(H.utility_problems(g.sim), [], "no stock is negative")
	t.done()

# ---------------------------------------------------------------- 4
func a04_transport(t) -> void:
	var c: Dictionary = _custom(t, BASE + [{"place": "refinery", "as": "F1", "at": "S1"}, {"link": "corridor", "a": "H1", "b": "F1"}])
	var g = c["g"]
	var ids: Dictionary = c["ids"]
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.5, true)
	var lander_store: int = g.sim.state["buildings"][g.sim.state["lander_id"]]["inv_out"]
	g.sim.inv.add_new_forced(lander_store, "ore", 4, "test")       # test set-up: ore far from the refinery
	H.set_priorities(g, {"industry": 0})
	g.run_seconds(90.0)
	var f: Dictionary = g.sim.state["buildings"][ids["F1"]]
	t.eq(g.sim.prod.machine_block(f), "no_input", "refinery reason while nobody carries ore")
	t.eq(g.sim.inv.count(lander_store, "ore"), 4, "ore is still in the lander: no invisible inventory")
	t.eq(int(H.ledger_of(g.sim, "ore")["consumed"]), 0, "no ore was consumed")
	H.set_priorities(g, {"industry": 3})
	var ok: bool = g.run_until(func(): return int(g.sim.state["metrics"]["produced"].get("metal", 0)) >= 1, 6000)
	t.check(ok, "with carrying allowed the refinery makes metal")
	t.eq(int(H.ledger_of(g.sim, "ore")["consumed"]) % 2, 0, "ore is consumed in whole batches of 2")
	t.eq(g.sim.inv.audit(), {}, "ledger")
	t.done()

# ---------------------------------------------------------------- 6
func a06_emergency(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.5, true)
	var ctr: Vector2 = g.sim.world.center
	var r: Dictionary = g.cmd("place_building", {"def": "solar_array", "x": ctr.x + 8.0, "y": ctr.y - 22.0, "rot": 0.0})
	t.check(r["ok"], "site accepted")
	var site: Dictionary = g.sim.state["buildings"][r["id"]]
	for res in site["cost"]:
		g.sim.inv.add_new_forced(site["inv_site"], res, int(site["cost"][res]), "test")   # test set-up: materials on site
	site["work_total"] = 100000.0                                                        # test set-up: the work never ends
	var worker = null
	var ok: bool = g.run_until(func():
		for a in H.alive_agents(g.sim):
			if a["goal"] == "Building " + String(site["name"]) and a["where"] == "out" and String(a.get("plan_kind", "")) == "task" and int(a["pi"]) == 1:
				return true
		return false, 3000)
	if not t.check(ok, "somebody started exterior construction work"):
		t.done()
		return
	for a in H.alive_agents(g.sim):
		if a["goal"] == "Building " + String(site["name"]) and int(a["pi"]) == 1:
			worker = a
	worker["fatigue"] = 72.0      # tired and hungry, but not critical: only suit air may stop the work
	worker["hunger"] = 72.0
	var cap: float = float(g.sim.bal["suit_air_seconds"])
	var turned: bool = g.run_until(func(): return worker["plan_kind"] == "safety", 1500)
	t.check(turned, "the worker aborts the ordinary task for air")
	t.check(float(worker["suit"]) > 0.0 and float(worker["suit"]) <= cap * 0.5, "the abort happens at the return threshold, with air left (%.0f s)" % float(worker["suit"]))
	t.eq(int(worker["task"]), -1, "the task was released")
	var safe: bool = g.run_until(func(): return g.sim.agents.breathable(worker), 1500)
	t.check(safe, "the worker reaches supplied air")
	t.eq(float(worker["health"]), 100.0, "without any damage")
	t.note("turned back with %.0f s of air" % float(worker["suit"]))
	t.done()

# ---------------------------------------------------------------- 7
func a07_airlock(t) -> void:
	var c: Dictionary = _custom(t, BASE)
	var g = c["g"]
	var ids: Dictionary = c["ids"]
	H.set_clock(g.sim, 4, 100.0)       # day 4: the lander air has ended, the airlock is the only way to air
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.5, true)
	g.cmd("set_flag", {"key": "unlock_all", "value": true})
	g.cmd("admit_settlers", {"count": 2})
	var lock: Dictionary = g.sim.state["buildings"][ids["L1"]]
	var door: Vector2 = g.sim.nav.door_pos(lock)
	var people: Array = H.alive_agents(g.sim)
	t.eq(people.size(), 10, "ten colonists")
	var i := 0
	for a in people:
		H.put_outside(g.sim, a, door + Vector2(-1.0 - 0.6 * i, 0.5 * (i % 3)), 75.0)    # test set-up
		a["fatigue"] = 0.0
		i += 1
	var saw_alert := false
	var alert_text := ""
	var max_queue := 0
	var got_in := {}
	for s in 150:
		g.run(10)
		max_queue = maxi(max_queue, (lock["lock"]["queue"] as Array).size())
		for issue in H.issues_with_code(g.sim, "airlock_congestion"):
			saw_alert = true
			alert_text = issue["text"]
		for a in H.alive_agents(g.sim):
			if a["where"] == "in":
				got_in[a["id"]] = true      # some go out again later to work: that is fine
	t.eq(H.alive_agents(g.sim).size(), 10, "nobody died in the queue")
	t.eq(got_in.size(), 10, "all ten got inside")
	t.check(max_queue >= 5 and (lock["lock"]["queue"] as Array).size() <= 2, "the queue formed and cleared: nobody holds the door permanently")
	t.check(saw_alert, "the congestion alert appeared")
	t.check(alert_text.contains("seconds"), "the alert names the unsafe wait time: %s" % alert_text)
	t.note("longest queue %d" % max_queue)
	t.done()

# ---------------------------------------------------------------- 8
func a08_crop(t) -> void:
	var c: Dictionary = _custom(t, BASE + FOOD)
	var g = c["g"]
	var ids: Dictionary = c["ids"]
	H.set_clock(g.sim, 1, 60.0)
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.8, true)
	var gh: Dictionary = g.sim.state["buildings"][ids["G1"]]
	gh["trays"][0] = {"state": "growing", "growth": 100.0, "interrupt": 0.0, "work": 0.0}    # test set-up
	g.run(100)
	var grown: float = float(gh["trays"][0]["growth"])
	t.check(grown > 100.0, "the crop grows with power and water")
	var cable: int = H.find_link(g.sim, "cable", ids["W1"], ids["O1"])
	H.unlink_now(g.sim, cable)
	g.run(600)
	t.near(float(gh["trays"][0]["growth"]), grown, 1.0, "growth pauses without water")
	t.check(float(gh["trays"][0]["interrupt"]) > 50.0, "the interruption timer runs (%.0f s)" % float(gh["trays"][0]["interrupt"]))
	var risk: Array = H.issues_with_code(g.sim, "crop_risk")
	t.check(not risk.is_empty() and float(risk[0]["forecast"]) > 0.0, "the alert shows a countdown")
	var errors: Array = []
	H.link_now(g.sim, "cable", ids["W1"], ids["O1"], errors)
	g.run(200)
	t.eq(String(gh["trays"][0]["state"]), "growing", "supply restored before the limit: the crop lives")
	t.check(float(gh["trays"][0]["growth"]) > grown + 5.0, "and it grows again")
	H.unlink_now(g.sim, H.find_link(g.sim, "cable", ids["W1"], ids["O1"]))
	g.run(800)
	t.eq(String(gh["trays"][0]["state"]), "empty", "past 120 s in total the crop dies")
	t.check(not H.log_entries(g.sim, "crop_lost").is_empty(), "the loss is in the event history")
	t.done()

# ---------------------------------------------------------------- 9
func a09_save(t) -> void:
	var a = H.reference_game(1001)
	# Stop at a moment with cargo in hands and a kitchen batch in progress.
	var found: bool = a.run_until(func():
		if a.tick() < 15000:
			return false
		var cargo := false
		for ag in H.alive_agents(a.sim):
			cargo = cargo or a.sim.inv.total(ag["inv"]) > 0
		var batch := false
		for id in H.buildings_of(a.sim, "kitchen", true):
			batch = batch or a.sim.prod.has_batch(a.sim.state["buildings"][id])
		return cargo and batch, 20000)
	if not t.check(found, "a moment with cargo in transit and a batch in progress exists"):
		t.done()
		return
	var clone: Dictionary = H.clone_by_save(a.sim)
	var b = H.Game.new(1001, false)
	b.sim.dispose()
	b.sim = clone["sim"]
	b.ref = H.copy_reference(a.ref, b.sim)
	var target: int = a.tick() + 3000
	a.run_to_tick(target)
	b.run_to_tick(target)
	# Version 2: raw food is now potatoes, and kitchens cook dishes (mashed potatoes first).
	for res in ["meals", "potato", "mashed_potato", "metal", "polymer", "water"]:
		t.eq(H.world_count(b.sim, res), H.world_count(a.sim, res), "%s in the world, loaded vs control" % res)
		t.eq(H.ledger_of(b.sim, res), H.ledger_of(a.sim, res), "%s ledger, loaded vs control" % res)
	t.eq(b.sim.state["metrics"]["produced"], a.sim.state["metrics"]["produced"], "production counters")
	t.eq(int(b.sim.state["metrics"].get("delivered", 0)), int(a.sim.state["metrics"].get("delivered", 0)), "delivered units")
	t.eq(b.sim.inv.audit(), {}, "ledger of the loaded game")
	t.eq(H.inventory_problems(b.sim), [], "reservations of the loaded game")
	t.note("saved at tick %d" % (target - 3000))
	t.done()

# ---------------------------------------------------------------- 10
func a10_demolition(t) -> void:
	var c: Dictionary = _custom(t, BASE + [{"place": "storehouse", "as": "S1"}, {"link": "corridor", "a": "H1", "b": "S1"}])
	var g = c["g"]
	var ids: Dictionary = c["ids"]
	g.run(2)
	H.fill_utilities(g.sim, 1.0, 0.5, true)
	var store: Dictionary = g.sim.state["buildings"][ids["S1"]]
	store["cost"] = {"metal": 3, "polymer": 2}                        # test set-up: as if built normally
	g.sim.inv.add_new_forced(store["inv_out"], "metal", 10, "test")     # test set-up: stock inside
	var person: Dictionary = H.alive_agents(g.sim)[0]
	H.put_inside(g.sim, person, ids["S1"])                             # test set-up: occupied
	var metal_before: int = H.world_count(g.sim, "metal")
	# Version 2: finished goals drop supply pods (new units, stats.rewarded). They are not
	# part of the demolition, so they are counted out of the check below.
	var rewarded_before: int = int(g.sim.state["stats"].get("rewarded", {}).get("metal", 0))
	var r: Dictionary = g.cmd("demolish", {"id": ids["S1"]})
	t.check(r["ok"], "the order is accepted")
	t.check(str(r.get("warnings", [])).contains("inside"), "with a warning that people are inside")
	store["progress"] = 1e9                                            # test set-up: the work is done at once
	g.sim.build.tick_second()
	t.check(g.sim.state["buildings"].has(ids["S1"]), "an occupied structure does not vanish")
	var gone: bool = g.run_until(func(): return not g.sim.state["buildings"].has(ids["S1"]), 1200)
	t.check(gone, "it is removed after the occupant left")
	t.eq(String(person["state"]), "alive", "the occupant is alive")
	var piles := 0
	var pile_metal := 0
	for inv_id in g.sim.state["inventories"]:
		var inv: Dictionary = g.sim.state["inventories"][inv_id]
		if inv["role"] == "pile":
			piles += 1
			pile_metal += int(inv["items"].get("metal", 0))
	t.check(piles >= 1, "stock and salvage lie in a recoverable ground pile")
	var rewarded: int = int(g.sim.state["stats"].get("rewarded", {}).get("metal", 0)) - rewarded_before
	t.eq(H.world_count(g.sim, "metal") - rewarded, metal_before + 1, "all 10 metal kept, plus 1 salvage (50% of 3, rounded down)")
	t.eq(g.sim.inv.audit(), {}, "ledger")
	t.eq(H.inventory_problems(g.sim), [], "reservations")
	t.done()

# ---------------------------------------------------------------- 11
func a11_alerts(t) -> void:
	# A wind turbine gives exactly 3.0 P; the player has put food first. The kitchen (1 P)
	# and the greenhouse (2 P) run, the water extractor is shed, the trays get no water.
	var g = H.empty_game(1001)
	var steps: Array = [{"place": "wind_turbine", "as": "A1"}]
	for st in H.CORE_STEPS:
		if st.get("as", "") in ["A1", "B1"] or st.get("a", "") == "B1" or st.get("b", "") == "B1":
			continue
		steps.append(st)
	var res: Dictionary = H.layout(g.sim, steps + BASE + FOOD)
	for e in res["errors"]:
		t.fail(e)
	var ids: Dictionary = res["ids"]
	H.set_clock(g.sim, 1, 420.0)
	g.run(2)
	H.fill_utilities(g.sim, 0.0, 0.0, true)
	g.cmd("set_power_order", {"order": ["food", "life_support", "medical", "industry", "comfort"]})
	var gh: Dictionary = g.sim.state["buildings"][ids["G1"]]
	gh["trays"][0] = {"state": "growing", "growth": 50.0, "interrupt": 0.0, "work": 0.0}     # test set-up
	for s in 300:
		g.sim.state["env"]["wind_raw"] = 3.0          # test set-up: steady wind
		g.sim.state["env"]["wind_target"] = 3.0
		g.step()
	t.check(bool(gh["powered"]), "the greenhouse has power")
	t.check(not bool(g.sim.state["buildings"][ids["W1"]]["powered"]), "the water extractor is shed")
	var roots := 0
	var crop_under_power := false
	for inc in g.sim.alerts.incidents():
		var code: String = inc["issue"]["code"]
		if code in ["power_short", "no_water", "crop_risk", "no_source"]:
			roots += 1
		if code == "power_short":
			for cons in inc["consequences"]:
				crop_under_power = crop_under_power or cons["code"] == "crop_risk"
	t.eq(roots, 1, "one primary incident for the whole chain")
	t.check(crop_under_power, "the crop failure hangs under the power incident")
	t.done()

# ---------------------------------------------------------------- 12
func a12_opening(t) -> void:
	var seeds: Array = H.Sim.new().content["scenarios"]["tutorial"]["tutorial_seeds"]
	for s in seeds:
		var g = H.reference_game(int(s))
		g.run_to_tick(18000)
		t.eq(H.alive_agents(g.sim).size(), 8, "seed %d: colonists alive at the end of day 3" % int(s))
		t.eq(H.refused_commands(g.sim), [], "seed %d: every reference command was accepted" % int(s))
		t.eq(g.sim.inv.audit(), {}, "seed %d: ledger" % int(s))
		t.check(bool(g.sim.state["flags"]["base_air"]), "seed %d: the base has its own air" % int(s))
		# Version 2 (design section 5): kitchens cook dishes from crops; "meals" is now only
		# the emergency ration. The check counts cooked dishes instead of produced meals.
		t.check(int(g.sim.state["stats"].get("cooked_total", 0)) > 0, "seed %d: dishes were cooked from grown food" % int(s))
		t.note("seed %d: %d dishes cooked" % [int(s), int(g.sim.state["stats"].get("cooked_total", 0))])
		g.dispose()
	t.done()

# ---------------------------------------------------------------- 14
func a14_loss(t) -> void:
	var g = H.reference_game(1001)
	g.run_to_tick(1500)
	var bytes: PackedByteArray = g.sim.save_bytes()
	for a in H.alive_agents(g.sim):
		g.cmd("kill_agent", {"id": int(a["id"]), "cause": "test"})
	g.run(20)
	t.check(bool(g.sim.state["progress"]["lost"]), "the game knows it is lost")
	var rep: Dictionary = g.sim.metrics.failure_report()
	t.eq(int(rep["causes"].get("test", 0)), 8, "the report counts the deaths by cause")
	t.check((rep["events"] as Array).size() >= 8, "the report lists the events in order")
	var dec: Dictionary = Persistence.decode(bytes)
	t.check(dec["ok"], "the earlier save still decodes")
	var sim2 = H.Sim.new()
	sim2.load_state(dec["state"])
	sim2.run_seconds(60.0)
	t.eq(sim2.alive_count(), 8, "the restored game has all eight colonists and runs on")
	t.check(not bool(sim2.state["progress"]["lost"]), "and it is not lost")
	t.done()
