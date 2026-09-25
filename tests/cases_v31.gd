extends RefCounted
## Version 3.1 tests (docs/V3_1_DESIGN.md): airlock cycle phases, outside paths clear of
## structures, ships and visitors, credits and trade, save schema 4.
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")
const Reference = preload("res://sim/reference.gd")

func tests() -> Array:
	return [
		["v31_airlock_phases", v31_airlock_phases],
		["v31_outside_paths_clear", v31_outside_paths_clear],
		["v31_traffic_schedule_deterministic", v31_schedule],
		["v31_trader_trade_and_credits", v31_trade],
		["v31_liner_visitors_beds_and_fees", v31_liner],
		["v31_orbit_hold_deny_and_shuttle", v31_hold_deny_shuttle],
		["v31_save_mid_visit_and_schema_4", v31_save],
		["v31_medical_science_inspector_visits", v31_other_visits],
		["v31_airlock_sizes", v31_airlock_sizes],
		["v31_porch_zone", v31_porch_zone],
		["v31_showcase_save", v31_showcase_save],
		["v31_showcase_purchase", v31_showcase_purchase],
		["v31_settlers_by_person_and_orbit_time", v31_settlers_by_person],
		["v31_door_clearance", v31_door_clearance],
		["v31_indoor_walks_stay_indoors", v31_indoor_walks_stay_indoors],
		["v31_piles_clear_of_porches", v31_piles_clear_of_porches],
		["v31_visitors_raise_no_colony_alerts", v31_visitors_raise_no_colony_alerts],
	]

## A room placed near a spot and joined by a corridor to `to` (test set-up).
func _room(t, sim, def_id: String, near: Vector2, to: int) -> Dictionary:
	var errors: Array = []
	for r in [0.0, 4.0, 8.0, 12.0]:
		for j in (1 if r == 0.0 else 12):
			var off: Vector2 = near + Vector2(r, 0).rotated(j * TAU / 12.0)
			var pos: Vector2 = sim.place.snap_pos(sim.world.center + off)
			if sim.place.check_building(def_id, pos, 0.0) != "ok":
				continue
			var b: Dictionary = sim.build.spawn_active(def_id, pos, 0.0)
			if sim.place.check_link("corridor", to, int(b["id"]))["code"] == "ok":
				H.link_now(sim, "corridor", to, int(b["id"]), errors)
				return b
			b["demolish"] = true
			b["progress"] = sim.build.demolish_work_total(b)
			sim.build._try_finish_demolition(b)
	t.fail("no place for %s" % def_id)
	return {}

func v31_other_visits(t) -> void:
	var c: Dictionary = _port(t)
	var g = c["g"]
	var sim = g.sim
	var h1: int = int(c["ids"]["H1"])
	var med: Dictionary = _room(t, sim, "medical", Vector2(44, 10), h1)
	var lab: Dictionary = _room(t, sim, "research_lab", Vector2(30, -18), int(c["ids"]["S1"]))
	g.run(20)
	H.fill_utilities(sim, 1.0, 0.8, true)
	# Medical ship: patients come in hurt, get treated and pay.
	var r: Dictionary = g.cmd("traffic_now", {"kind": "medical", "in": 5})
	var id: int = int(r.get("id", -1))
	t.check(_run_until_phase(g, id, "landed", 1200), "the medical ship landed")
	var fees0: int = int(sim.state["credits"]["by"].get("fees", 0))
	var treated: bool = g.run_until(func(): return int(sim.state["credits"]["by"].get("fees", 0)) > fees0, 6000)
	t.check(sim.state["stats"].get("heals", 0) > 0 or treated, "patients were healed")
	t.check(treated, "a patient was treated in the medical bay and paid")
	t.check(_run_until_phase(g, id, "gone", 12000), "the medical ship left")
	# Science ship: visiting scientists add research in a lab.
	var rp0: float = float(sim.state["research"]["rp_total"]) + float(sim.state["research"]["bank"])
	var r2: Dictionary = g.cmd("traffic_now", {"kind": "science", "in": 5})
	var id2: int = int(r2.get("id", -1))
	t.check(_run_until_phase(g, id2, "landed", 1200), "the science ship landed")
	g.run(3000)
	var study := 0.0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["kind"] == "visitor" and String(a.get("vkind", "")) == "science":
			study += float(a["visit"]["study"])
	t.check(study > 1.0, "visiting scientists worked in the lab (%.1f RP)" % study)
	t.check(_run_until_phase(g, id2, "gone", 9000), "the science ship left")
	# Inspector: visits rooms and pays by the colony's state.
	var r3: Dictionary = g.cmd("traffic_now", {"kind": "inspector", "in": 5})
	var id3: int = int(r3.get("id", -1))
	t.check(_run_until_phase(g, id3, "gone", 9000), "the inspector came and left")
	t.check(int(sim.traffic.find(id3)["result"].get("fees", 0)) > 0, "the inspector paid (%d)" % int(sim.traffic.find(id3)["result"].get("fees", 0)))
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(sim.traffic.credits_audit(), {}, "credits balance")
	t.note("credits %s" % str(sim.state["credits"]["by"]))
	g.dispose()
	t.done()

# ---------------------------------------------------------------- set-up
const CORE_PLUS := [
	{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"},
	{"place": "kitchen", "as": "K1"}, {"link": "corridor", "a": "H1", "b": "K1"},
	{"place": "storehouse", "as": "S1"}, {"link": "corridor", "a": "H1", "b": "S1"},
]

static func _spot(sim, def_id: String, near: Vector2, size: int = 1) -> Vector2:
	for r in [0.0, 3.0, 6.0, 9.0, 12.0, 16.0, 20.0]:
		var n: int = 1 if r == 0.0 else 16
		for j in n:
			var off: Vector2 = near + Vector2(r, 0).rotated(j * TAU / float(n))
			var pos: Vector2 = sim.place.snap_pos(sim.world.center + off)
			if sim.place.check_building(def_id, pos, 0.0, -1, size) == "ok":
				return pos - sim.world.center
	return Vector2(INF, INF)

## A small base with a powered landing pad near the airlock (test set-up). debug on.
func _port(t, seed_value: int = 1001, extra: Array = []) -> Dictionary:
	var g = H.empty_game(seed_value)
	g.sim.new_game(seed_value, "tutorial", {"debug": true, "hazards": "off"})
	var sim = g.sim
	var res: Dictionary = H.layout(sim, H.CORE_STEPS + CORE_PLUS + extra)
	for e in res["errors"]:
		t.fail(e)
	sim.state["flags"]["unlock_all"] = true          # test set-up (the pad needs stage 1)
	var errors: Array = []
	var pad: Dictionary = H.spawn(sim, "landing_pad", _spot(sim, "landing_pad", Vector2(-6, 26)), 0.0, errors)
	if not pad.is_empty():
		H.link_now(sim, "cable", int(pad["id"]), int(res["ids"]["B1"]), errors)
	for e in errors:
		t.fail(e)
	H.set_clock(sim, 1, 30.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.8, true)
	return {"g": g, "ids": res["ids"], "pad": pad}

func _run_until_phase(g, id: int, phase: String, max_ticks: int) -> bool:
	return g.run_until(func(): return String(g.sim.traffic.find(id).get("phase", "")) == phase, max_ticks)

# ---------------------------------------------------------------- 6.1 schedule
func v31_schedule(t) -> void:
	var a: Dictionary = _port(t)
	var b: Dictionary = _port(t)
	var ga = a["g"]
	var gb = b["g"]
	var first_seen := {}
	while ga.tick() < 8 * 6000:
		ga.run(600)
		for x in ga.sim.traffic.queue_all():
			if not first_seen.has(int(x["id"])):
				first_seen[int(x["id"])] = [ga.tick(), int(x["at"])]
	gb.run_to_tick(8 * 6000)
	var qa: Array = []
	var qb: Array = []
	for x in ga.sim.traffic.queue_all() + ga.sim.state["traffic"]["done"] + ga.sim.traffic.ships():
		qa.append("%d:%s:%d" % [int(x["id"]), x["kind"], int(x["at"])])
	for x in gb.sim.traffic.queue_all() + gb.sim.state["traffic"]["done"] + gb.sim.traffic.ships():
		qb.append("%d:%s:%d" % [int(x["id"]), x["kind"], int(x["at"])])
	t.check(qa.size() >= 3, "ships were planned (%d)" % qa.size())
	t.eq(qb, qa, "the same seed gives the same ships")
	var early := 0
	for x in ga.sim.state["traffic"]["done"] + ga.sim.traffic.ships() + ga.sim.traffic.queue_all():
		if int(x["at"]) < 4 * 6000:
			early += 1
	t.eq(early, 0, "no ship before day 4")
	var late := 0
	for k in first_seen:
		if int(first_seen[k][1]) - int(first_seen[k][0]) < 6000:
			late += 1
	t.check(not first_seen.is_empty(), "arrivals were seen in the plan")
	t.eq(late, 0, "every arrival is planned at least one day before it comes")
	for x in ga.sim.traffic.forecast():
		t.check(float(x["eta_s"]) <= 600.0, "a forecast ship arrives within a day")
	var g3 = H.reference_game(1001)
	g3.run_to_tick(6 * 6000)
	t.eq(g3.sim.traffic.queue_all().size() + g3.sim.traffic.ships().size(), 0, "without a pad no ship is planned")
	t.eq(ga.sim.inv.audit(), {}, "ledger")
	t.eq(ga.sim.traffic.credits_audit(), {}, "credits balance")
	t.note("ships to day 8: %s" % ", ".join(qa))
	ga.dispose()
	gb.dispose()
	g3.dispose()
	t.done()

# ---------------------------------------------------------------- trade
func v31_trade(t) -> void:
	var c: Dictionary = _port(t)
	var g = c["g"]
	var sim = g.sim
	var r: Dictionary = g.cmd("traffic_now", {"kind": "trader", "in": 5})
	t.check(bool(r["ok"]), "debug trader ordered")
	var id: int = int(r.get("id", -1))
	t.check(_run_until_phase(g, id, "landed", 1200), "the trader landed")
	var arr: Dictionary = sim.traffic.find(id)
	t.eq(int(c["pad"].get("ship", -1)), id, "the pad holds the ship")
	var sells: Dictionary = arr["offer"]["sells"]
	var item: String = String(sells.keys()[0])
	var price: int = int(sells[item]["price"])
	var credits0: int = sim.traffic.credits()
	var n: int = mini(int(sells[item]["units"]), maxi(1, credits0 / price))
	var have0: int = int(sim.inv.totals().get(item, {}).get("total", 0))
	var tr: Dictionary = g.cmd("trade", {"id": id, "buy": {item: n}})
	t.check(bool(tr["ok"]), "buying %d %s is accepted: %s" % [n, item, tr["code"]])
	t.eq(sim.traffic.credits(), credits0 - n * price, "credits paid")
	t.eq(int(sim.inv.totals().get(item, {}).get("total", 0)), have0 + n, "the units are in the colony (a pile at the pad)")
	t.eq(g.cmd("trade", {"id": id, "buy": {item: 100000}})["code"], "no_stock", "cannot buy more than the ship has")
	var buys: Dictionary = arr["offer"]["buys"]
	var sitem: String = String(buys.keys()[0])
	var store: int = int(sim.state["buildings"][c["ids"]["S1"]]["inv_out"])
	sim.inv.add_new_forced(store, sitem, 4, "test")        # test set-up: goods to sell
	var sn: int = mini(4, int(buys[sitem]["units"]))
	var before: int = sim.traffic.credits()
	t.check(bool(g.cmd("trade", {"id": id, "sell": {sitem: sn}})["ok"]), "selling %d %s is accepted" % [sn, sitem])
	var target: int = before + sn * int(buys[sitem]["price"])
	var paid: bool = g.run_until(func(): return sim.traffic.credits() >= target, 3000)
	t.check(paid, "carriers took the goods to the ship and it paid (%d credits)" % (sim.traffic.credits() - before))
	t.eq(sim.inv.audit(), {}, "ledger with trade")
	t.eq(sim.traffic.credits_audit(), {}, "credits balance")
	t.check(_run_until_phase(g, id, "gone", 6000), "the trader left")
	t.eq(int(c["pad"].get("ship", -1)), -1, "the pad is free")
	t.eq(sim.inv.audit(), {}, "ledger after it left")
	var trade_invs := 0
	for inv_id in sim.state["inventories"]:
		if sim.state["inventories"][inv_id]["role"] == "trade":
			trade_invs += 1
	t.eq(trade_invs, 0, "the ship holds are gone")
	t.note("bought %d %s at %d, sold %d %s at %d" % [n, item, price, sn, sitem, int(buys[sitem]["price"])])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- visitors
func v31_liner(t) -> void:
	var c: Dictionary = _port(t, 1001, [{"place": "lounge", "as": "C1", "at": "G1"}, {"link": "corridor", "a": "K1", "b": "C1"}])
	var g = c["g"]
	var sim = g.sim
	var free0: int = sim.traffic.free_beds()
	var r: Dictionary = g.cmd("traffic_now", {"kind": "liner", "in": 5})
	var id: int = int(r.get("id", -1))
	t.check(_run_until_phase(g, id, "landed", 1200), "the liner landed")
	var arr: Dictionary = sim.traffic.find(id)
	var came: int = int(arr["result"].get("came", 0))
	t.check(came >= 1 and came <= maxi(0, free0), "tourists came, no more than the free beds (%d of %d, %d free)" % [came, int(arr["people"]), free0])
	var jobs_taken := 0
	var inside := false
	var ate := false
	var colonist_bed_lost := 0
	var meals0: int = int(sim.state["credits"]["by"].get("meals", 0))
	for s in 900:
		g.run(10)
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] != "alive":
				continue
			if a["kind"] == "visitor":
				if int(a["task"]) != -1:
					jobs_taken += 1
				if a["where"] == "in":
					inside = true
				if int(a["visit"]["ate"]) > 0:
					ate = true
			elif a["plan_kind"] == "sleep" and String(a.get("use", {}).get("kind", "")) == "stand" and String(sim.state["buildings"].get(int(a["bld"]), {}).get("def", "")) == "habitat":
				colonist_bed_lost += 1
		if String(sim.traffic.find(id).get("phase", "")) == "gone":
			break
	t.eq(jobs_taken, 0, "visitors never take a job")
	t.check(inside, "tourists walked in through the airlock")
	t.check(ate, "tourists ate (paid meals)")
	t.eq(colonist_bed_lost, 0, "no colonist lost a bed to a tourist")
	t.check(int(sim.state["credits"]["by"].get("meals", 0)) > meals0, "meals were paid")
	var done: Dictionary = sim.traffic.find(id)
	t.eq(String(done["phase"]), "gone", "the liner left after its stay")
	t.check(int(done["result"].get("fees", 0)) > 0, "the liner paid fees (%d)" % int(done["result"].get("fees", 0)))
	var visitors_left := 0
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid]["kind"] == "visitor" and sim.state["agents"][aid]["state"] == "alive":
			visitors_left += 1
	t.eq(visitors_left, int(done["result"].get("left_behind", 0)), "the visitors boarded or are counted as left behind")
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(sim.traffic.credits_audit(), {}, "credits balance")
	t.eq(sim.alive_count(), 8, "visitors are not counted as colonists")
	t.note("%d tourists, fees %d, meals %d credits, %d left behind" % [came, int(done["result"].get("fees", 0)), int(sim.state["credits"]["by"].get("meals", 0)), int(done["result"].get("left_behind", 0))])
	g.dispose()
	t.done()

func v31_hold_deny_shuttle(t) -> void:
	var c: Dictionary = _port(t)
	var g = c["g"]
	var sim = g.sim
	sim.state["options"]["hazards"] = "normal"                      # test set-up: hazards on for the storm
	g.cmd("hazard_now", {"kind": "dust_storm", "duration": 60.0, "in": 1})
	var r: Dictionary = g.cmd("traffic_now", {"kind": "science", "in": 5})
	var id: int = int(r.get("id", -1))
	g.run(100)
	t.eq(String(sim.traffic.find(id)["phase"]), "orbit", "no landing during a dust storm: the ship holds in orbit")
	t.check(_run_until_phase(g, id, "landed", 2000), "it lands after the storm")
	t.check(_run_until_phase(g, id, "gone", 9000), "the science ship left after its stay")
	var r2: Dictionary = g.cmd("traffic_now", {"kind": "trader", "in": 30})
	var id2: int = int(r2.get("id", -1))
	t.check(bool(g.cmd("traffic_answer", {"id": id2, "grant": false})["ok"]), "deny accepted")
	g.run(400)
	t.eq(String(sim.traffic.find(id2)["phase"]), "denied", "a denied ship does not land")
	var pop0: int = sim.alive_count()
	var r3: Dictionary = g.cmd("traffic_now", {"kind": "shuttle", "in": 30})
	var id3: int = int(r3.get("id", -1))
	g.cmd("traffic_answer", {"id": id3, "grant": true, "accept": 1})
	g.run_until(func(): return ["landed", "boarding", "takeoff", "gone"].has(String(sim.traffic.find(id3)["phase"])), 6000)
	t.eq(sim.alive_count(), pop0 + 1, "one settler joined")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- saves
func v31_save(t) -> void:
	var c: Dictionary = _port(t)
	var g = c["g"]
	var sim = g.sim
	var r: Dictionary = g.cmd("traffic_now", {"kind": "liner", "in": 5})
	var id: int = int(r.get("id", -1))
	_run_until_phase(g, id, "landed", 1200)
	g.run(900)
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved mid-visit")
	var sim2 = cl["sim"]
	for i in 3000:
		sim.step()
		sim2.step()
	t.eq(H.digest(sim2), H.digest(sim), "the loaded game continues exactly")
	var bytes: PackedByteArray = sim.save_bytes()
	var raw := StreamPeerBuffer.new()
	raw.data_array = bytes
	raw.seek(8)
	t.eq(raw.get_u32(), 4, "saves are schema 4")
	sim2.dispose()
	g.dispose()
	for name in ["showcase_v3_late", "showcase_mid"]:
		var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/%s.fhsave" % name))
		t.check(bool(dec["ok"]), "%s loads" % name)
		if not bool(dec["ok"]):
			continue
		var s: Dictionary = dec["state"]
		t.eq(int(s["schema"]), 4, "%s migrated to 4" % name)
		t.eq(int(s["credits"]["balance"]), 0, "%s: credits 0" % name)
		var sim3 = H.Sim.new()
		sim3.load_state(s)
		sim3.run_seconds(60.0)
		t.eq(sim3.traffic.queue_all().size(), 0, "%s: no pad, no ship" % name)
		t.eq(sim3.inv.audit(), {}, "%s: ledger" % name)
		sim3.dispose()
	t.done()

# ---------------------------------------------------------------- 5.2 airlock phases
## Every cycle runs enter, seal, pump, open, exit in order, pt counts down inside a phase,
## the cycle length is unchanged (10 s powered), and two games give the same phases.
func v31_airlock_phases(t) -> void:
	var g = H.reference_game(1001)
	var sim = g.sim
	var seen := {}
	var order_ok := true
	var len_ok := true
	var cycles := 0
	var last := {}
	var trace: Array = []
	var early_pump := 0
	while g.tick() < 3 * 6000:
		g.step()
		for id in sim.state["buildings"]:
			var info: Dictionary = sim.agents.lock_info(int(id))
			if info.is_empty():
				continue
			if not bool(info["cycling"]):
				last.erase(id)
				continue
			var ph: String = info["phase"]
			seen[ph] = true
			var prev = last.get(id)
			if prev == null:
				cycles += 1
				if ph != "enter" and ph != "seal":
					order_ok = false
				var tot: float = float(info["total"])
				if absf(tot - 10.0) > 0.01 and absf(tot - 20.0) > 0.01:
					len_ok = false
			elif String(prev[0]) != ph:
				if ph == "pump" and float(info["total"]) - float(info["t"]) < 3.0 * float(info["total"]) / 10.0 - 0.11:
					early_pump += 1
				var i0: int = sim.agents.PHASES.find(String(prev[0]))
				var i1: int = sim.agents.PHASES.find(ph)
				if i1 != i0 + 1:
					order_ok = false
			elif float(info["pt"]) > float(prev[1]) + 0.0001:
				order_ok = false
			last[id] = [ph, float(info["pt"])]
			if trace.size() < 400:
				trace.append("%d:%s:%.2f" % [int(id), ph, float(info["pt"])])
	t.check(cycles >= 20, "airlocks cycled (%d cycles)" % cycles)
	# Critic round 13: pump starts only after the source-side door has shut.
	var lens: Array = sim.agents._phase_lengths(10.0)
	t.eq(lens, [2.0, 1.0, 4.5, 1.0, 1.5], "10 s cycle: enter 2, seal 1, pump 4.5, open 1, exit 1.5")
	t.check(float(lens[1]) >= float(sim.bal["airlock_door_seconds"]) + 0.3, "seal covers the door closing (%.1f s) with a margin" % float(sim.bal["airlock_door_seconds"]))
	t.eq(sim.agents._phase_lengths(20.0)[2], 14.5, "an unpowered 20 s cycle pumps longer")
	t.check(early_pump == 0, "pump never starts before enter + seal are over (%d early)" % early_pump)
	for ph in ["enter", "seal", "pump", "open", "exit"]:
		t.check(seen.has(ph), "phase %s seen" % ph)
	t.check(order_ok, "phases in order, pt counts down")
	t.check(len_ok, "cycle length 10 s (20 s unpowered)")
	var g2 = H.reference_game(1001)
	var trace2: Array = []
	while g2.tick() < 3 * 6000:
		g2.step()
		if trace2.size() >= trace.size():
			break
		for id in g2.sim.state["buildings"]:
			var info2: Dictionary = g2.sim.agents.lock_info(int(id))
			if not info2.is_empty() and bool(info2["cycling"]) and trace2.size() < 400:
				trace2.append("%d:%s:%.2f" % [int(id), info2["phase"], float(info2["pt"])])
	t.eq(trace2.slice(0, trace.size()), trace, "the same phases in a second run")
	t.note("%d cycles" % cycles)
	g.dispose()
	g2.dispose()
	t.done()

# ---------------------------------------------------------------- 4.2 outside paths
## Problems for a body outside now: inside a structure footprint (or its clearance less the
## grid cell), inside a corridor tube, or a path point in a blocked cell.
static func outside_problems(sim) -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["where"] != "out":
			continue
		var p: Vector2 = a["pos"]
		for id in blds:
			var b: Dictionary = blds[id]
			if b["state"] == "blueprint":
				continue
			if b["kind"] == "link":
				if b["def"] == "corridor" and Geometry2D.get_closest_point_to_segment(p, b["p0"], b["p1"]).distance_to(p) < 1.2:
					out.append("tick %d: %s in the tube of %s" % [int(sim.state["tick"]), a["name"], b["name"]])
				continue
			var d: float
			if b["def"] == "meridian":
				d = sim.ship.surface_distance(b, p) + float(b["radius"])
			else:
				d = p.distance_to(b["pos"])
			if d < float(b["radius"]):
				out.append("tick %d: %s inside %s (%.2f m from the centre, radius %.1f)" % [int(sim.state["tick"]), a["name"], b["name"], d, float(b["radius"])])
		var route: Dictionary = a.get("route", {})
		if route.is_empty() or int(a["li"]) >= (route.get("legs", []) as Array).size():
			continue
		var leg: Dictionary = route["legs"][a["li"]]
		if leg["m"] != "out":
			continue
		var pts: Array = leg["pts"]
		for i in range(1, pts.size() - 1):
			if not sim.nav.is_walkable(pts[i]):
				out.append("tick %d: %s path point %s is in a blocked cell" % [int(sim.state["tick"]), a["name"], str(pts[i])])
	return out

## The reference campaign with hazards: no body outside is ever inside a structure, a
## corridor tube or a blocked path cell (V3_1_DESIGN 4.2).
func v31_outside_paths_clear(t) -> void:
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	var bad: Array = []
	var samples := 0
	var outside := 0
	while g.tick() < 8 * 6000:
		g.step()
		if g.tick() % 5 == 0:
			samples += 1
			for aid in sim.state["agents"]:
				if sim.state["agents"][aid]["where"] == "out":
					outside += 1
			if bad.size() < 8:
				bad.append_array(outside_problems(sim))
	t.eq(bad.slice(0, 8), [], "no body outside inside a structure, a tube or a blocked cell")
	t.check(outside > 1000, "people walked outside (%d body samples)" % outside)
	# The grid: cells whose centre is within the footprint + BODY_R (0.3 m) are solid; the band
	# of nav_clearance beyond that is weighted (or solid for a neighbour).
	var clear: float = float(sim.bal["nav_clearance"])
	var holes := 0
	var cheap := 0
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "blueprint" or b["kind"] == "link" or b["def"] == "meridian":
			continue
		var c: Vector2 = b["pos"]
		var rr: float = float(b["radius"])
		for y in range(int(c.y - rr - 3.0), int(c.y + rr + 3.0)):
			for x in range(int(c.x - rr - 3.0), int(c.x + rr + 3.0)):
				var q := Vector2(x + 0.5, y + 0.5)
				var d: float = q.distance_to(c)
				if d <= rr + 0.28 and sim.nav.is_walkable(q):
					holes += 1
				elif d > rr + 0.32 and d <= rr + 0.3 + clear - 0.01 and sim.nav.is_walkable(q) and not sim.nav.is_weighted(q):
					cheap += 1
	t.eq(holes, 0, "every footprint (plus 0.3 m) is solid on the grid")
	t.eq(cheap, 0, "every clearance band is weighted")
	t.note("%d samples, %d outside body samples" % [samples, outside])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- critic round 10: airlock sizes
## Airlock M (3.4 m, 2 riders) and L (4.0 m, 4 riders); S and XL do not exist; L needs
## eng_1; one L cycle carries four; airlocks of an old save keep 2.8 m and 2 riders.
func v31_airlock_sizes(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	t.eq(sim.sizes.sizes_of("airlock"), [1, 2], "airlock sizes are M and L")
	var m: Dictionary = sim.sizes.def_for("airlock", 1)
	var l: Dictionary = sim.sizes.def_for("airlock", 2)
	t.eq([float(m["radius"]), int(m["airlock_slots"])], [3.4, 2], "M: 3.4 m, 2 riders")
	t.eq([float(l["radius"]), int(l["airlock_slots"])], [4.0, 4], "L: 4.0 m, 4 riders")
	t.eq(int(sim.sizes.furniture("airlock", 2)["stands"]), 4, "L: 4 standing places")
	var spot: Vector2 = sim.place.snap_pos(sim.world.center + _spot(sim, "airlock", Vector2(-20, 20), 1))
	for s in [0, 3]:
		t.eq(sim.place.check_building("airlock", spot, 0.0, -1, s), "no_size", "size %s is refused" % sim.sizes.size_name(s))
	t.eq(sim.place.check_building("airlock", spot, 0.0, -1, 2), "locked_research", "L waits for research")
	t.eq(sim.sizes.allowed("airlock", 2)["research"], "eng_1", "L needs Engineering 1")
	t.eq(float(sim.sizes.def_for("landing_pad", 1)["radius"]), 11.5, "a new landing pad is 11.5 m")
	g.dispose()

	# One L cycle carries four people.
	g = H.empty_game(1001)
	sim = g.sim
	sim.state["flags"]["unlock_all"] = true          # test set-up
	var steps: Array = H.CORE_STEPS.duplicate(true)
	for st in steps:
		if st.get("as", "") == "L1":
			st["size"] = 2
	var res: Dictionary = H.layout(sim, steps + CORE_PLUS)
	for e in res["errors"]:
		t.fail(e)
	H.set_clock(sim, 1, 30.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.8, true)
	var lock: Dictionary = sim.state["buildings"][res["ids"]["L1"]]
	t.eq([float(lock["radius"]), sim.agents.lock_slots(lock)], [4.0, 4], "the L airlock record")
	var door: Vector2 = sim.nav.door_pos(lock)
	var outside: Array = []
	for aid in sim.state["agents"]:
		if outside.size() < 4:
			var a: Dictionary = sim.state["agents"][aid]
			H.put_outside(sim, a, door + Vector2(0.9 * outside.size(), 1.0), 20.0)      # test set-up
			outside.append(aid)
	# Test set-up: the airlock is busy for 4 s, so all four stand in the queue when it frees.
	lock["lock"]["cyc"] = {"agents": [], "dir": "out", "t": 4.0, "total": 10.0, "phase": "pump", "pt": 0.0}
	var most := [0]          # an array: a lambda gets a copy of a plain local
	g.run_until(func():
		var info: Dictionary = sim.agents.lock_info(int(lock["id"]))
		if bool(info.get("cycling", false)):
			most[0] = maxi(int(most[0]), (info["riders"] as Array).size())
		return int(most[0]) >= 4, 1200)
	t.eq(int(most[0]), 4, "four people ride one cycle")
	g.dispose()

	# An old save keeps its airlocks as they were.
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	var sim3 = H.Sim.new()
	sim3.load_state(dec["state"])
	var n := 0
	for id in sim3.state["buildings"]:
		var b: Dictionary = sim3.state["buildings"][id]
		if b["def"] == "airlock":
			n += 1
			if absf(float(b["radius"]) - 2.8) > 0.001 or sim3.agents.lock_slots(b) != 2 or int(b.get("size", 1)) != 1:
				t.fail("%s changed on load: radius %.1f, %d riders" % [b["name"], float(b["radius"]), sim3.agents.lock_slots(b)])
	t.check(n > 0, "the old save has airlocks (%d)" % n)
	sim3.dispose()
	t.done()

# ---------------------------------------------------------------- critic round 10: porch zone
## 2.5 m in front of every airlock outer door stays clear: placement refuses a structure or
## a corridor there (also a new airlock facing one); the walking grid makes the porch
## expensive, so a path past an airlock goes round it, and a path to the door ends on it.
func v31_porch_zone(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	sim.state["flags"]["unlock_all"] = true          # test set-up
	var res: Dictionary = H.layout(sim, H.CORE_STEPS + CORE_PLUS)
	for e in res["errors"]:
		t.fail(e)
	g.run(2)
	var lock: Dictionary = sim.state["buildings"][res["ids"]["L1"]]
	var st: Dictionary = sim.place.door_strip(lock)
	t.eq([snappedf(float(st["porch_length"]), 0.1), snappedf((st["p1"] as Vector2).distance_to(st["p0"]), 0.1)], [2.5, 3.5], "porch 2.5 m inside a 3.5 m strip")
	var ids: Array = []
	for z in sim.place.door_strips():
		ids.append(int(z["id"]))
	t.check(ids.has(int(lock["id"])), "door_strips() lists the airlock")
	t.eq(sim.place.door_strip_for("airlock", lock["pos"], lock["rot"], 1)["half_width"], st["half_width"], "the preview gives the same zone")
	t.eq(sim.place.door_strip_for("habitat", lock["pos"], 0.0, 1), {}, "no zone for a room without a door")
	# A small structure right in front of the door is refused.
	var dirv := Vector2(cos(float(lock["rot"])), sin(float(lock["rot"])))
	var front: Vector2 = sim.place.snap_pos((st["p0"] as Vector2) + dirv * 4.5)
	t.eq(sim.place.check_building("battery", front, 0.0), "blocks_entrance", "a battery on the porch is refused")
	# A new airlock whose door faces an existing corridor is refused.
	var tube: Dictionary = {}
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["kind"] == "link" and b["def"] == "corridor":
			tube = b
			break
	var bad := 0
	var tried := 0
	var nrm: Vector2 = ((tube["p1"] as Vector2) - tube["p0"]).normalized().orthogonal()
	for f in [0.3, 0.5, 0.7]:
		var mid: Vector2 = (tube["p0"] as Vector2).lerp(tube["p1"], f)
		for s in [1.0, -1.0]:
			for d in [5.5, 6.5, 7.5]:
				var pos: Vector2 = sim.place.snap_pos(mid + nrm * s * d)
				# Only places where the same airlock turned away from the tube is legal count.
				if sim.place.check_building("airlock", pos, sim.place.snap_rot((nrm * s).angle())) != "ok":
					continue
				tried += 1
				if sim.place.check_building("airlock", pos, sim.place.snap_rot((-nrm * s).angle())) == "blocked_entrance":
					bad += 1
	t.check(tried > 0 and bad == tried, "an airlock facing a corridor is refused (%d of %d)" % [bad, tried])
	# Walking grid: the porch cells cost more; a path across the front of the door goes round.
	t.check(sim.nav.is_weighted((st["p0"] as Vector2) + dirv * 1.5), "the porch is weighted on the grid")
	var side: Vector2 = dirv.orthogonal()
	var a: Vector2 = (st["p0"] as Vector2) + dirv * 1.5 + side * 7.0
	var b2: Vector2 = (st["p0"] as Vector2) + dirv * 1.5 - side * 7.0
	var r: Dictionary = sim.nav.path_out(a, b2)
	t.check(bool(r["ok"]), "a path passes the airlock")
	var on_porch := 0
	if bool(r["ok"]):
		var pts: Array = r["pts"]
		for i in range(1, pts.size()):
			var p0: Vector2 = pts[i - 1]
			var p1: Vector2 = pts[i]
			for k in 10:
				var q: Vector2 = p0.lerp(p1, float(k) / 10.0)
				var cp: Vector2 = Geometry2D.get_closest_point_to_segment(q, st["p0"], (st["p0"] as Vector2) + dirv * float(st["porch_length"]))
				if cp.distance_to(q) < 1.0:
					on_porch += 1
	t.eq(on_porch, 0, "the path past the airlock keeps off its porch")
	var to_door: Dictionary = sim.nav.path_out(a, sim.nav.door_pos(lock))
	t.check(bool(to_door["ok"]) and (to_door["pts"].back() as Vector2).distance_to(sim.nav.door_pos(lock)) < 0.01, "a path to the door ends on the porch")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 7 showcase save
## content/saves/showcase_v31.fhsave (tests/make_showcase_v31.gd): a late colony with two
## pads, a trader and a liner landed, tourists in a cantina and an airlock in mid-cycle.
func v31_showcase_save(t) -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v31.fhsave"))
	if not t.check(bool(dec["ok"]), "showcase_v31 loads"):
		t.done()
		return
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	t.eq(int(sim.state["schema"]), 4, "schema 4")
	t.eq(H.buildings_of(sim, "landing_pad", true).size() >= 2, true, "two pads or more")
	var kinds: Array = sim.traffic.ships().map(func(x): return "%s:%s" % [x["kind"], x["phase"]])
	t.check(kinds.has("trader:landed") and kinds.has("liner:landed"), "a trader and a liner landed (%s)" % str(kinds))
	var in_cantina := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] == "visitor" and a["where"] == "in" and String(sim.state["buildings"].get(int(a["bld"]), {}).get("def", "")) == "cantina":
			in_cantina += 1
	t.check(in_cantina >= 2, "tourists in a cantina (%d)" % in_cantina)
	var cycling := 0
	for id in sim.state["buildings"]:
		var info: Dictionary = sim.agents.lock_info(int(id))
		if not info.is_empty() and bool(info["cycling"]):
			cycling += 1
	t.check(cycling >= 1, "an airlock is mid-cycle (%d)" % cycling)
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(sim.traffic.credits_audit(), {}, "credits ledger")
	sim.run_seconds(30.0)
	t.eq(sim.inv.audit(), {}, "ledger after 30 s")
	sim.dispose()
	t.done()

## A purchase in the showcase save: credits go down by the price, the goods lie as a pile at
## the pad, carriers take them into storage, and both ledgers stay {}.
func v31_showcase_purchase(t) -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v31.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	t.check(sim.traffic.credits() >= 500, "the showcase has credits to spend (%d)" % sim.traffic.credits())
	var row: Dictionary = {}
	for r in sim.traffic.ships():
		if r["kind"] == "trader" and r["phase"] == "landed":
			row = r
	if not t.check(not row.is_empty(), "a landed trader"):
		sim.dispose()
		t.done()
		return
	var sells: Dictionary = row["offer"]["sells"]
	var keys: Array = sells.keys()
	keys.sort()
	var item: String = String(keys[0])
	var price: int = int(sells[item]["price"])
	var n: int = mini(int(row["stock"].get(item, 0)), mini(4, sim.traffic.credits() / price))
	var stored0: int = _in_role(sim, item, "store")
	var c0: int = sim.traffic.credits()
	sim.submit("trade", {"id": int(row["id"]), "buy": {item: n}})
	sim.step()
	t.check(n > 0, "something to buy (%d %s at %d)" % [n, item, price])
	t.eq(sim.traffic.credits(), c0 - n * price, "credits went down by the price")
	t.eq(_in_role(sim, item, "pile"), n, "the goods lie at the pad")
	var stored := false
	# A late colony is busy: the pile waits for a free carrier (measured: first pick-up after
	# about 450 s, all stored after about 1000 s).
	for s in 360:
		sim.run_seconds(5.0)
		if _in_role(sim, item, "pile") == 0 and _in_role(sim, item, "carry") == 0:
			stored = true
			break
	t.check(stored, "carriers took the goods off the pad")
	var kept: int = _in_role(sim, item, "store") + _in_role(sim, item, "in") + _in_role(sim, item, "out") + _in_role(sim, item, "fill")
	t.check(kept >= stored0 + n, "the goods are in storage or at a machine (%d, was %d in storage)" % [kept, stored0])
	t.eq(sim.inv.audit(), {}, "item ledger")
	t.eq(sim.traffic.credits_audit(), {}, "credits ledger")
	t.note("bought %d %s for %d credits" % [n, item, n * price])
	sim.dispose()
	t.done()

static func _in_role(sim, item: String, role: String) -> int:
	var n := 0
	for inv_id in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		if inv["role"] == role:
			n += int(inv["items"].get(item, 0))
	return n

## traffic_answer with accept_idx: exactly the chosen settlers join (by index into
## offer.roles); a bad index is refused; the count form still works (v31_orbit_hold_deny_and_shuttle).
## In orbit, a row's t_s counts down to the time the ship gives up and leaves.
func v31_settlers_by_person(t) -> void:
	var c: Dictionary = _port(t)
	var g = c["g"]
	var sim = g.sim
	var r: Dictionary = g.cmd("traffic_now", {"kind": "shuttle", "in": 30})
	var id: int = int(r.get("id", -1))
	var roles: Array = sim.traffic.find(id)["offer"]["roles"]
	t.check(roles.size() >= 2, "the shuttle brings %d settlers" % roles.size())
	t.eq(g.cmd("traffic_answer", {"id": id, "accept_idx": [roles.size()]})["code"], "invalid", "an index outside the list is refused")
	var pick: Array = [roles.size() - 1, 0, 0]
	t.check(bool(g.cmd("traffic_answer", {"id": id, "grant": true, "accept_idx": pick})["ok"]), "accept_idx accepted")
	var row: Dictionary = {}
	for f in sim.traffic.forecast():
		if int(f["id"]) == id:
			row = f
	t.eq(row.get("accept_idx", []), [0, roles.size() - 1], "the row shows the choice, sorted, no repeats")
	var before: Dictionary = {}
	for aid in sim.state["agents"]:
		before[aid] = true
	g.run_until(func(): return ["landed", "boarding", "takeoff", "gone"].has(String(sim.traffic.find(id)["phase"])), 6000)
	var got: Array = []
	for aid in sim.state["agents"]:
		if not before.has(aid) and sim.state["agents"][aid]["kind"] != "visitor":
			got.append(String(sim.state["agents"][aid]["role"]))
	got.sort()
	var want: Array = [String(roles[0]), String(roles[roles.size() - 1])]
	want.sort()
	t.eq(got, want, "exactly the chosen settlers joined")
	# Orbit time left: a dust storm keeps a ship in orbit; t_s counts down to its leaving.
	sim.state["options"]["hazards"] = "normal"                      # test set-up: hazards on for the storm
	g.cmd("hazard_now", {"kind": "dust_storm", "duration": 120.0, "in": 1})
	var r2: Dictionary = g.cmd("traffic_now", {"kind": "science", "in": 5})
	var id2: int = int(r2.get("id", -1))
	g.run(100)
	var t1 := -1.0
	for s in sim.traffic.ships():
		if int(s["id"]) == id2 and s["phase"] == "orbit":
			t1 = float(s["t_s"])
	var hold: float = float(sim.content["ships"]["orbit_hold_h"]) * float(sim.content["ships"]["hour_seconds"])
	t.check(t1 > hold - 15.0 and t1 <= hold, "in orbit t_s counts down from the hold time (%.1f of %.0f s)" % [t1, hold])
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- door clearance (ART-HAB data)
## A new corridor may not leave a room at a model angle in that room's blocked ranges
## (content/door_blocked.json, by size key): the airlock's chamber and porch side
## (-53.5..53.5) above all. The model angle is rot - world angle. link_sectors() gives the
## free sides for the ghost; an existing link of an old save stays.
func v31_door_clearance(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	sim.state["flags"]["unlock_all"] = true          # test set-up
	t.check(not sim.place.door_ranges("airlock", 1).is_empty(), "airlock M has blocked door angles")
	t.eq(sim.place.door_ranges("greenhouse", 0), [], "greenhouse S has none")
	t.near(sim.place.model_angle(0.5, 0.5 - deg_to_rad(30.0)), 30.0, 1e-6, "model angle = rot - world angle")
	# The airlock: never on the chamber and porch side, at any rotation.
	for k in 24:
		var rot: float = k * TAU / 24.0
		for off in [-50.0, 0.0, 50.0]:
			if sim.place.link_angle_ok_for("airlock", 1, rot, rot - deg_to_rad(off)):
				t.fail("airlock rot %d deg: a link %d deg off the door side is allowed" % [k * 15, int(off)])
		t.check(sim.place.link_angle_ok_for("airlock", 1, rot, rot + PI), "airlock rot %d deg: the back is free" % (k * 15))
	# Sectors agree with the angle test.
	var bad := 0
	for def_size in [["airlock", 1], ["airlock", 2], ["oxygen_plant", 1], ["greenhouse", 2], ["habitat", 0], ["kitchen", 1]]:
		for rk in [0, 5, 13]:
			var rot2: float = rk * TAU / 24.0
			var secs: Array = sim.place.link_sectors_for(def_size[0], def_size[1], rot2)
			for a in 72:
				var w: float = a * TAU / 72.0 + 0.013
				var inside := false
				for sc in secs:
					var f: float = float(sc["from"])
					for ww in [w, w + TAU, w - TAU]:
						if ww > f + 0.001 and ww < float(sc["to"]) - 0.001:
							inside = true
				var near_edge := false
				for sc in secs:
					for e in [float(sc["from"]), float(sc["to"])]:
						if absf(fposmod(w - e + PI, TAU) - PI) < 0.03:
							near_edge = true
				if not near_edge and inside != sim.place.link_angle_ok_for(def_size[0], def_size[1], rot2, w):
					bad += 1
	t.eq(bad, 0, "link_sectors_for agrees with link_angle_ok_for")
	t.eq(sim.place.link_sectors_for("junction", 1, 0.0), [{"from": 0.0, "to": TAU}], "a junction is free all round")
	# check_link refuses a corridor on the porch side of an airlock, with the reason.
	var res: Dictionary = H.layout(sim, H.CORE_STEPS + CORE_PLUS)
	for e in res["errors"]:
		t.fail(e)
	var lock: Dictionary = sim.state["buildings"][res["ids"]["L1"]]
	var dirv := Vector2(cos(float(lock["rot"])), sin(float(lock["rot"])))
	var errors: Array = []
	var front: Dictionary = {}
	for d in [10.0, 12.0, 14.0, 16.0]:
		for deg in [30.0, -30.0, 40.0, -40.0, 20.0, -20.0]:
			if not front.is_empty():
				break
			var q: Vector2 = (lock["pos"] as Vector2) + dirv.rotated(deg_to_rad(deg)) * d
			var qs: Vector2 = sim.place.snap_pos(q)
			if sim.place.check_building("junction", qs, 0.0) == "ok":
				front = sim.build.spawn_active("junction", qs, 0.0)          # test set-up
	if front.is_empty():
		t.fail("no junction in front of the airlock")
	else:
		var chk: Dictionary = sim.place.check_link("corridor", int(front["id"]), int(lock["id"]))
		t.eq(chk["code"], "door_blocked", "a corridor onto the airlock's porch side is refused")
		t.eq(sim.place.reason_text("door_blocked"), "The door would open onto equipment. Choose another side of the room.", "the reason the UI shows")
		t.eq(g.cmd("place_link", {"def": "corridor", "a": int(front["id"]), "b": int(lock["id"])})["code"], "door_blocked", "the command gives the same code")
	# An existing link at a blocked angle stays (old saves): the rule is for new links only.
	var o2: Dictionary = sim.state["buildings"][res["ids"]["O1"]]
	var n_links := 0
	for id in sim.state["buildings"]:
		var l: Dictionary = sim.state["buildings"][id]
		if l["kind"] == "link" and l["def"] == "corridor":
			n_links += 1
	o2["rot"] = float(o2["rot"]) + PI * 0.5                  # test set-up: a turned room, as an old save may have
	g.run(20)
	var n_after := 0
	for id in sim.state["buildings"]:
		var l: Dictionary = sim.state["buildings"][id]
		if l["kind"] == "link" and l["def"] == "corridor" and l["state"] == "active":
			n_after += 1
	t.eq(n_after, n_links, "existing corridors stay")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- indoor walks stay indoors
## Problems for bodies indoors now: a body with where == "in" that is in no room footprint
## and no corridor tube (RENDER-to-SIM 2026-09-25: a colonist walked across open ground).
static func indoor_problems(sim) -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["where"] != "in":
			continue
		var p: Vector2 = a["pos"]
		var ok := false
		var own: Dictionary = blds.get(int(a["bld"]), {})
		if not own.is_empty() and own["kind"] != "link" and p.distance_to(own["pos"]) <= float(own["radius"]) + 0.05:
			continue
		for id in blds:
			var b: Dictionary = blds[id]
			if b["kind"] == "link":
				if b["def"] == "corridor" and Geometry2D.get_closest_point_to_segment(p, b["p0"], b["p1"]).distance_to(p) <= 1.25:
					ok = true
					break
			elif b["def"] != "meridian" and p.distance_to(b["pos"]) <= float(b["radius"]) + 0.05:
				ok = true
				break
		if not ok:
			out.append("tick %d: %s (%d) indoors at %s, bld %s, in no room or corridor" % [int(sim.state["tick"]), a["name"], int(aid), str(p), str(blds.get(int(a["bld"]), {}).get("name", "?"))])
	return out

## Every tick: in the reference campaign (4 days) and in showcase_v3_late (10 game minutes,
## 60+ colonists, the save of the report), no body indoors is outside the rooms and corridors.
func v31_indoor_walks_stay_indoors(t) -> void:
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var bad: Array = []
	var samples := 0
	while g.tick() < 4 * 6000:
		g.step()
		samples += 1
		if bad.size() < 6:
			bad.append_array(indoor_problems(g.sim))
	t.eq(bad.slice(0, 6), [], "reference campaign: every body indoors is in a room or a corridor (%d ticks)" % samples)
	g.dispose()
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	var bad2: Array = []
	for i in 6000:
		sim.step()
		if bad2.size() < 6:
			bad2.append_array(indoor_problems(sim))
	t.eq(bad2.slice(0, 6), [], "showcase_v3_late: every body indoors is in a room or a corridor (6000 ticks)")
	sim.dispose()
	t.done()

# ---------------------------------------------------------------- critic round 13: piles off porches
## Crate piles and drop points keep 2.5 m from every airlock outer door and off its strip:
## a colonist who drops cargo on a porch, a drop point of an airlock, and every new pile of
## the reference campaign (3 days).
func v31_piles_clear_of_porches(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	sim.state["flags"]["unlock_all"] = true          # test set-up
	var res: Dictionary = H.layout(sim, H.CORE_STEPS + CORE_PLUS)
	for e in res["errors"]:
		t.fail(e)
	g.run(2)
	var lock: Dictionary = sim.state["buildings"][res["ids"]["L1"]]
	var door: Vector2 = sim.nav.door_pos(lock)
	t.check(sim.place.in_porch(door), "the queue spot is on the porch")
	var a: Dictionary = sim.state["agents"].values()[0]
	H.put_outside(sim, a, door, 80.0)                                   # test set-up
	sim.inv.add_new_forced(int(a["inv"]), "metal", 2, "test")             # test set-up: cargo in hand
	sim.agents._drop_cargo(a)
	var pile_pos = null
	for inv_id in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		if inv["role"] == "pile" and int(inv["items"].get("metal", 0)) == 2:
			pile_pos = inv["pos"]
	t.check(pile_pos != null and not sim.place.in_porch(pile_pos), "cargo dropped on a porch lands off it (%s)" % str(pile_pos))
	t.check(pile_pos != null and (pile_pos as Vector2).distance_to(sim.place.door_strip(lock)["p0"]) >= 2.5, "at least 2.5 m from the door")
	t.check(not sim.place.in_porch(sim.build.drop_point(lock)), "an airlock's drop point is off its porch")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	var g2 = H.reference_game(1001)
	var seen := {}
	var bad: Array = []
	while g2.tick() < 3 * 6000:
		g2.step()
		if g2.tick() % 10 != 0:
			continue
		for inv_id in g2.sim.state["inventories"]:
			if seen.has(inv_id):
				continue
			var inv2: Dictionary = g2.sim.state["inventories"][inv_id]
			if inv2["role"] != "pile" or int(inv2["oid"]) != 0:
				continue
			seen[inv_id] = true
			if g2.sim.place.in_porch(inv2["pos"]) and bad.size() < 5:
				bad.append("tick %d: pile %d at %s" % [g2.tick(), int(inv_id), str(inv2["pos"])])
	t.eq(bad, [], "no new ground pile on a porch in 3 days of the reference game (%d piles)" % seen.size())
	t.note("%d new ground piles checked" % seen.size())
	g2.dispose()
	t.done()

# ---------------------------------------------------------------- visitors are not the colony
## Integration report: showcase_v31 showed "The lander air has ended. 6 people have no other
## bed" for the liner's tourists. Visitors never raise a colony alert (lander air, beds,
## hunger, thirst, nutrition, suit or air, breach, rescue); a tourist without a bed is a
## notice of the traffic panel.
static func _found(sim) -> Dictionary:
	var al = sim.alerts
	var found := {}
	for part in ["_power_issues", "_water_issues", "_air_issues", "_building_issues", "_people_issues", "_supply_issues", "_nutrition_issues", "_progress_issues", "_hazard_issues"]:
		al.call(part, found)
	var out := {}
	for k in found:
		if int(found[k]["severity"]) >= 2:
			out[k] = [int(found[k]["severity"]), int(found[k]["count"])]
	return out

func v31_visitors_raise_no_colony_alerts(t) -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v31.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	sim.run_seconds(5.0)
	t.check(not _found(sim).has("lander_expiry"), "showcase_v31: no lander alert for the tourists")
	var visitors: Array = []
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid]["state"] == "alive" and sim.state["agents"][aid]["kind"] == "visitor":
			visitors.append(aid)
	t.check(visitors.size() >= 2, "visitors are here (%d)" % visitors.size())
	# Test set-up: every free room bed goes to a new colonist, so the tourists have none.
	var f: Dictionary = sim.metrics.forecast()
	var spare: int = int(f["beds"]) - int(f["pop"])
	if spare > 0:
		sim.cmds._land(spare, ["technician"])
		sim.alive_changed()
		for aid in sim.state["agents"]:
			var c: Dictionary = sim.state["agents"][aid]
			if c["kind"] != "visitor" and int(c["bed"]) == -1:
				sim.agents._assign_bed(c)          # test set-up: the newcomers take the free beds
	sim.run_seconds(2.0)
	var no_bed := 0
	for nt in sim.traffic.notices():
		if nt["code"] == "tourists_no_bed":
			no_bed = int(nt["count"])
			t.check(String(nt["text"]).ends_with("no bed. The fee drops."), "the notice: %s" % nt["text"])
	t.check(no_bed > 0, "the traffic panel says tourists have no bed (%d)" % no_bed)
	# Test set-up: the visitors are in every kind of trouble a colonist can be in.
	for vid in visitors:
		var v: Dictionary = sim.state["agents"][vid]
		v["hunger"] = 99.0
		v["thirst"] = 99.0
		v["health"] = 30.0
		v["rescue"] = true
		v["bed"] = -1
		for k in v.get("nutrition", {}):
			v["nutrition"][k] = 3.0
		v["starved"] = true
	var bad: Dictionary = _found(sim)
	# The same moment with the visitors well: the colony alerts must be the same.
	for vid in visitors:
		var v2: Dictionary = sim.state["agents"][vid]
		v2["hunger"] = 0.0
		v2["thirst"] = 0.0
		v2["health"] = 100.0
		v2["rescue"] = false
		for k in v2.get("nutrition", {}):
			v2["nutrition"][k] = 60.0
		v2["starved"] = false
	var good: Dictionary = _found(sim)
	t.eq(bad, good, "visitors in trouble change no warning or critical alert")
	t.check(not bad.has("lander_expiry"), "no lander alert")
	t.eq(int(sim.metrics.forecast()["visitors"]), visitors.size(), "the forecast counts visitors for food, water and air")
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()
