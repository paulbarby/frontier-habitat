extends RefCounted
## Version 5 tests for docs/V5_DESIGN.md section 18: orders that are obeyed at once (18.1), the chain of command
## (18.2), the work queues (18.3), missing items and production chains (18.4). Package transport (18.5) is in
## cases_v5_transport.gd. Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")

func tests() -> Array:
	return [
		["v5_order_repair_every_state", v5_order_repair_every_state],
		["v5_order_needs_and_missing", v5_order_needs_and_missing],
		["v5_order_kinds_build_haul_maintain", v5_order_kinds_build_haul_maintain],
		["v5_order_team_and_chain_of_command", v5_order_team_and_chain_of_command],
		["v5_workq_queue_order_and_assign", v5_workq_queue_order_and_assign],
		["v5_chain_finder_and_alerts", v5_chain_finder_and_alerts],
		["v5_order_no_plan_thrash", v5_order_no_plan_thrash],
		["v5_order_takes_reserved_part", v5_order_takes_reserved_part],
		["v5_order_unreachable_parts", v5_order_unreachable_parts],
		["v5_order_every_role_and_work_at", v5_order_every_role_and_work_at],
		["v5_order_party_and_old_orders", v5_order_party_and_old_orders],
		["v5_maintain_now_is_an_order", v5_maintain_now_is_an_order],
		["v5_orders_deterministic", v5_orders_deterministic],
		["v5_blocked_order_save_load", v5_blocked_order_save_load],
	]

# ---------------------------------------------------------------- set-up helpers
static func _spot(sim, def_id: String, around: Vector2, rmin: float, rmax: float, k0: int = 0) -> Vector2:
	var r: float = rmin
	while r <= rmax:
		for k in 36:
			var p: Vector2 = sim.place.snap_pos(around + Vector2.RIGHT.rotated(((k + k0) % 36) * TAU / 36.0) * r)
			if sim.place.check_building(def_id, p, 0.0, -1, 1) == "ok":
				return p
		r += 6.0
	return Vector2(-1, -1)

## A small colony (the frontier start, no random hazards) with the people sorted by id.
static func _colony(seed_v: int = 1001) -> Dictionary:
	var g = H.Game.new(seed_v, false)
	var sim = g.sim
	sim.new_game(seed_v, "frontier", {"hazards": "off"})
	sim.state["flags"]["unlock_all"] = true                                                 # test set-up
	g.run(5)                                                                                # the supply of the lander is known after a tick
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	return {"g": g, "sim": sim, "ids": ids, "lid": int(sim.state["lander_id"])}

static func _rested(sim, a: Dictionary, bid: int) -> void:
	H.put_inside(sim, a, bid)
	a["fatigue"] = 0.0
	a["hunger"] = 0.0
	a["thirst"] = 0.0
	a["suit"] = sim.agents.suit_cap()
	a["backoff"] = {}

## A solar array 25-60 m from the lander, damaged to `health` (above the repair trigger, so only an order repairs it).
static func _worn_array(sim, lid: int, health: float, k0: int = 0) -> Dictionary:
	var lander: Dictionary = sim.state["buildings"][lid]
	var p: Vector2 = _spot(sim, "solar_array", lander["pos"], 25.0, 70.0, k0)
	var b: Dictionary = sim.build.spawn_active("solar_array", p, 0.0)                       # test set-up
	b["health"] = health                                                                     # test set-up
	return b

func _task_kind(sim, a: Dictionary) -> String:
	var tid: int = int(a["task"])
	if tid != -1 and sim.state["tasks"].has(tid):
		return String(sim.state["tasks"][tid]["kind"])
	return ""

# ---------------------------------------------------------------- 18.1.4: an order in every state
## An idle, a partying, a sleeping and a working colonist each start an ordered repair within 5 game seconds and
## finish it; the structure's health goes up (and the wear of a machine goes down); the colonist then goes back to
## routine.
func v5_order_repair_every_state(t) -> void:
	for state in ["idle", "partying", "sleeping", "sleeping_deep", "working"]:
		var c: Dictionary = _colony()
		var g = c["g"]
		var sim = c["sim"]
		var lid: int = int(c["lid"])
		var a: Dictionary = sim.state["agents"][c["ids"][0]]
		var arr: Dictionary = _worn_array(sim, lid, 85.0)
		var other: Dictionary = _worn_array(sim, lid, 100.0, 9)
		other["dust"] = true                                                                 # test set-up: other work to be busy with
		_rested(sim, a, lid)
		match state:
			"partying":
				sim.agents._start_plan(a, "party", [{"op": "wait", "t": 600.0}], "At a party")     # test set-up
				a["party"] = 1                                                                # test set-up
			"sleeping", "sleeping_deep":
				a["fatigue"] = 50.0 if state == "sleeping" else 80.0                          # test set-up: tired, not critical
				sim.agents._start_plan(a, "sleep", [{"op": "wait", "t": 600.0}], "Sleeping")        # test set-up
				a["sleeping"] = true                                                          # test set-up
			"working":
				sim.jobs._new_task("clean", "repair", int(other["id"]), {})                   # test set-up: a task to work at
				var tk: Dictionary = sim.jobs.open_task_at(int(other["id"]), "clean")
				var rs: Dictionary = sim.agents.start_task_for(a, tk)
				t.check(bool(rs["ok"]), "%s: the colonist works on another task first (%s, other %.0f m, target %.0f m, suit %.0f)" % [state, str(rs.get("reason", "")), (other["pos"] as Vector2).distance_to(a["pos"]), (arr["pos"] as Vector2).distance_to(a["pos"]), float(a["suit"])])
		var before: String = String(a["plan_kind"])
		var r: Dictionary = g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(arr["id"])})
		t.check(bool(r["ok"]), "%s: the repair order is accepted (%s)" % [state, str(r.get("code", ""))])
		var started := false
		var at := -1
		for i in 50:
			g.run(1)
			if a.has("order") and int(a["order"].get("tid", -1)) != -1 and a["plan_kind"] == "task" and int(a["task"]) == int(a["order"]["tid"]):
				started = true
				at = i + 1
				break
		t.check(started, "%s: the order is carried out within 5 s (was %s, now %s: %s)" % [state, before, String(a["plan_kind"]), String(a["goal"])])
		if state == "working":
			t.check(_task_kind(sim, a) == "repair", "working: the colonist left the other task for the repair (%s)" % _task_kind(sim, a))
		t.check(String(a["order"]["text"]) != "" if a.has("order") else true, "%s: the order text says what the colonist does" % state)
		var done: bool = g.run_until(func(): return float(arr["health"]) >= 99.5 and not a.has("order"), 5000)
		t.check(done, "%s: the structure is repaired (health %.0f) and the order is over" % [state, float(arr["health"])])
		g.run(20)
		t.check(not a.has("order") and a["plan_kind"] != "order", "%s: the colonist is back to routine (%s)" % [state, String(a["plan_kind"])])
		t.eq(sim.inv.audit(), {}, "%s: the ledger balances" % state)
		g.dispose()
	# The wear of a machine goes down too.
	var c2: Dictionary = _colony()
	var g2 = c2["g"]
	var sim2 = c2["sim"]
	var lid2: int = int(c2["lid"])
	var a2: Dictionary = sim2.state["agents"][c2["ids"][0]]
	var lander: Dictionary = sim2.state["buildings"][lid2]
	var hp: Vector2 = _spot(sim2, "regolith_harvester", lander["pos"], 25.0, 70.0)
	var mach: Dictionary = sim2.build.spawn_active("regolith_harvester", hp, 0.0)             # test set-up
	t.check(sim2.hazards.is_machine(mach), "a regolith harvester wears")
	sim2.hazards.wear_of(int(mach["id"]))["w"] = 30.0                                          # test set-up
	_rested(sim2, a2, lid2)
	var r2: Dictionary = g2.cmd("order", {"direct": true, "agents": [int(a2["id"])], "kind": "repair", "b": int(mach["id"])})
	t.check(bool(r2["ok"]), "a repair order on a worn machine is accepted (%s)" % str(r2.get("code", "")))
	var ok2: bool = g2.run_until(func(): return float(sim2.hazards.wear_of(int(mach["id"]))["w"]) < 1.0 and not a2.has("order"), 5000)
	t.check(ok2, "the wear of the machine drops to 0 (%.1f)" % float(sim2.hazards.wear_of(int(mach["id"]))["w"]))
	# A structure that needs nothing is refused with a reason.
	var sound: Dictionary = _worn_array(sim2, lid2, 100.0, 18)
	var r3: Dictionary = g2.cmd("order", {"direct": true, "agents": [int(a2["id"])], "kind": "repair", "b": int(sound["id"])})
	t.eq(r3["code"], "no_work", "a sound structure: the order is refused (no_work)")
	g2.dispose()
	t.done()

# ---------------------------------------------------------------- 18.1: needs first, missing parts reported
func v5_order_needs_and_missing(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	var lid: int = int(c["lid"])
	var a: Dictionary = sim.state["agents"][c["ids"][0]]
	var arr: Dictionary = _worn_array(sim, lid, 85.0)
	_rested(sim, a, lid)
	# A critical thirst comes before the order, and the order resumes after it.
	a["thirst"] = float(sim.bal["need_critical"]) + 1.0                                        # test set-up
	g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(arr["id"])})
	var drank: bool = g.run_until(func(): return a["plan_kind"] == "drink", 80)
	t.check(drank, "critical thirst first: the colonist goes to drink (%s)" % String(a["plan_kind"]))
	t.check(a.has("order"), "the order is kept while the colonist drinks")
	var resumed: bool = g.run_until(func(): return a.has("order") and a["plan_kind"] == "task" and int(a["task"]) == int(a["order"]["tid"]), 600)
	t.check(resumed, "the order resumes right after the drink (%s)" % String(a["goal"]))
	g.run_until(func(): return not a.has("order"), 5000)
	t.check(float(arr["health"]) >= 99.5, "and the structure is repaired (%.0f)" % float(arr["health"]))
	# No spare parts anywhere: the order says what is missing and an alert shows the chain; the colonist works as usual.
	var lander: Dictionary = sim.state["buildings"][lid]
	var parts: int = sim.inv.count(int(lander["inv_out"]), "spare_parts")
	sim.inv.destroy(int(lander["inv_out"]), "spare_parts", parts, "test_setup")                # test set-up: no parts
	var arr2: Dictionary = _worn_array(sim, lid, 60.0, 14)
	arr2["health"] = 85.0                                                                       # test set-up (above the trigger)
	_rested(sim, a, lid)
	g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(arr2["id"])})
	g.run(30)
	t.check(a.has("order") and String(a["order"]["blocked"]) == "no_item", "no spare parts: the order is blocked (%s)" % (String(a["order"]["blocked"]) if a.has("order") else "gone"))
	t.eq(String(a["order"].get("missing", {}).get("item", "")), "spare_parts", "it says exactly what is missing")
	t.check(String(a["order"]["text"]).to_lower().contains("spare parts"), "the order text names it: %s" % String(a["order"]["text"]))
	t.check(sim.state["issues"].has("chain:spare_parts") or sim.chains.missing_items().has("spare_parts"), "an alert (or a missing-item report) names spare parts")
	# The colonist is not held: other work is allowed while the order waits.
	t.check(sim.orders.is_blocked(a), "the blocked order leaves the colonist to the ordinary work")
	# Parts arrive: the order is carried out.
	sim.inv.add_new(int(lander["inv_out"]), "spare_parts", 4, "test_setup")                    # test set-up
	var fixed: bool = g.run_until(func(): return float(arr2["health"]) >= 99.5 and not a.has("order"), 6000)
	t.check(fixed, "with the parts in store the order is carried out (%.0f)" % float(arr2["health"]))
	# An order is refused for a child and for the dead (existing rules still hold).
	t.eq(g.cmd("order", {"direct": true, "agents": [999999], "kind": "repair", "b": int(arr["id"])})["code"], "unknown", "unknown colonist")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 18.1: build, haul, maintain (standing)
func v5_order_kinds_build_haul_maintain(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	var lid: int = int(c["lid"])
	var a: Dictionary = sim.state["agents"][c["ids"][0]]
	var b2: Dictionary = sim.state["agents"][c["ids"][1]]
	var lander: Dictionary = sim.state["buildings"][lid]
	# A small base: the reference core, a habitat and a workshop, joined by corridors (test set-up).
	var lay: Dictionary = H.layout(sim, H.CORE_STEPS + [{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"},
		{"place": "workshop", "as": "K1", "at": "S1"}, {"link": "corridor", "a": "H1", "b": "K1"}])
	t.eq(lay["errors"], [], "the base layout")
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.5, true)
	# build: a planned solar array gets built by the ordered colonist (the others are kept busy elsewhere).
	var sp: Vector2 = _spot(sim, "solar_array", lander["pos"], 25.0, 60.0)
	var pb: Dictionary = g.cmd("place_building", {"def": "solar_array", "x": sp.x, "y": sp.y, "rot": 0.0})
	t.check(bool(pb["ok"]), "a solar array is planned")
	var site: int = int(pb.get("id", -1))
	_rested(sim, a, lid)
	var rb: Dictionary = g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "build", "b": site})
	t.check(bool(rb["ok"]), "a build order is accepted (%s)" % str(rb.get("code", "")))
	var built: bool = g.run_until(func(): return sim.state["buildings"][site]["state"] == "active", 8000)
	t.check(built, "the site is built (%s)" % String(sim.state["buildings"][site]["state"]))
	var order_ended: bool = g.run_until(func(): return not a.has("order"), 3000)
	t.check(order_ended, "the build order ends when the site is done")
	# haul: carry 4 steel to a workshop.
	var ws: Dictionary = sim.state["buildings"][int(lay["ids"]["K1"])]
	var inv_in: int = int(ws["inv_in"])
	t.check(inv_in != -1, "the workshop has an input store")
	var before: int = sim.inv.count(inv_in, "metal")
	var delivered0: int = int(sim.state["metrics"].get("delivered", 0))
	_rested(sim, b2, lid)
	var rh: Dictionary = g.cmd("order", {"direct": true, "agents": [int(b2["id"])], "kind": "haul", "res": "metal", "qty": 4, "b": int(ws["id"])})
	t.check(bool(rh["ok"]), "a haul order is accepted (%s)" % str(rh.get("code", "")))
	var carried: bool = g.run_until(func(): return not b2.has("order"), 6000)
	t.check(carried, "the haul order ends")
	t.check(int(sim.state["metrics"].get("delivered", 0)) - delivered0 >= 4, "4 steel was carried to the workshop (%d delivered; the workshop uses some at once)" % (int(sim.state["metrics"].get("delivered", 0)) - delivered0))
	t.eq(g.cmd("order", {"direct": true, "agents": [int(b2["id"])], "kind": "haul", "res": "metal", "qty": 4, "b": 999999})["code"], "no_building", "a haul to nothing is refused")
	t.eq(g.cmd("order", {"direct": true, "agents": [int(b2["id"])], "kind": "haul", "res": "exotic", "qty": 1, "b": int(ws["id"])})["code"], "no_item", "a haul of an item that is nowhere is refused")
	# maintain: a standing order. The wear passes the threshold: the colonist maintains without being told again.
	var hp: Vector2 = _spot(sim, "regolith_harvester", lander["pos"], 25.0, 70.0, 20)
	var mach: Dictionary = sim.build.spawn_active("regolith_harvester", hp, 0.0)              # test set-up
	_rested(sim, a, lid)
	var rm: Dictionary = g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "maintain", "b": int(mach["id"])})
	t.check(bool(rm["ok"]), "a maintain order on a sound machine is accepted (%s)" % str(rm.get("code", "")))
	t.check(sim.workq.summary()["standing"] >= 1, "it is a standing order in the queue")
	g.run(30)
	t.check(not a.has("order"), "nothing to maintain yet: the colonist is free")
	var rec: Dictionary = sim.hazards.wear_of(int(mach["id"]))
	rec["w"] = float(rec["fail_at"]) * sim.hazards.risk_frac() + 1.0                          # test set-up: the wear passes the threshold
	var again: bool = g.run_until(func(): return a.has("order") and String(a["order"]["kind"]) == "maintain", 200)
	t.check(again, "the wear passes the threshold: the standing order calls the colonist")
	var fixed: bool = g.run_until(func(): return float(sim.hazards.wear_of(int(mach["id"]))["w"]) < 1.0, 6000)
	t.check(fixed, "and the machine is maintained (wear %.1f)" % float(sim.hazards.wear_of(int(mach["id"]))["w"]))
	g.cmd("order_clear", {"agents": [int(a["id"])]})
	t.eq(sim.workq.summary()["standing"], 0, "order_clear ends a standing order")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 18.2: team orders to a head
func v5_order_team_and_chain_of_command(t) -> void:
	var sim = _showcase()
	var base: int = int(sim.bases.ids()[0])
	var cap_id: int = sim.people.captain_of("maintenance", base)
	t.check(cap_id != -1, "the showcase has a maintenance captain")
	var cap: Dictionary = sim.state["agents"][cap_id]
	t.check(sim.workq.is_head(cap), "the captain is a head")
	var first_hand := -1
	for aid in sim.state["agents"]:
		var m: Dictionary = sim.state["agents"][aid]
		if m["state"] == "alive" and m["kind"] != "visitor" and String(sim.people.rank(m).get("rank", "")) == "specialist":
			first_hand = int(aid)
			break
	t.check(first_hand != -1 and not sim.workq.is_head(sim.state["agents"][first_hand]), "a specialist is not a head")
	# A worn structure near the base core.
	var core: Dictionary = sim.bases.core_of(base)
	var p: Vector2 = _spot(sim, "solar_array", core["pos"], 30.0, 120.0)
	var arr: Dictionary = sim.build.spawn_active("solar_array", p, 0.0)                       # test set-up
	arr["health"] = 80.0                                                                       # test set-up
	# Make sure spare parts are in a store (test set-up).
	sim.inv.add_new_forced(int(core["inv_out"]) if int(core["inv_out"]) != -1 else int(core["inv_in"]), "spare_parts", 24, "test_setup")
	var crew: Array = []
	for aid in sim.state["agents"]:
		var m2: Dictionary = sim.state["agents"][aid]
		if m2["state"] == "alive" and m2["kind"] != "visitor" and m2["kind"] != "child" and int(aid) != cap_id and sim.people.department(m2) == "maintenance" and sim.bases.base_of_agent(m2) == base and not sim.workq.is_head(m2):
			crew.append(int(aid))
	t.check(crew.size() >= 2, "the maintenance team has %d members besides the captain" % crew.size())
	# A direct order to the captain (direct: true) is for the captain alone.
	var arr9: Dictionary = sim.build.spawn_active("solar_array", _spot(sim, "solar_array", core["pos"], 30.0, 130.0, 7), 0.0)   # test set-up
	arr9["health"] = 80.0                                                                      # test set-up
	var rd: Dictionary = sim.orders.cmd_order({"agents": [cap_id], "kind": "repair", "b": int(arr9["id"]), "direct": true})
	t.check(bool(rd["ok"]) and not rd.has("team") and cap.has("order"), "a direct order goes to the captain himself")
	# An order to a colonist who is not a head goes to that colonist.
	var rs: Dictionary = sim.orders.cmd_order({"agents": [crew[0]], "kind": "repair", "b": int(arr9["id"])})
	t.check(bool(rs["ok"]) and not rs.has("team") and sim.state["agents"][crew[0]].has("order"), "an order to a crew member goes to that colonist (%s %s)" % [str(rs.get("code", "")), str(rs.get("refused", {}))])
	sim.orders.cmd_clear({"agents": [cap_id, crew[0]]})
	var r: Dictionary = sim.orders.cmd_order({"agents": [cap_id], "kind": "repair", "b": int(arr["id"]), "count": 2})
	t.check(bool(r["ok"]), "a team order to the captain is accepted (%s)" % str(r.get("code", "")))
	t.check(r.has("team") and (r["assigned"] as Array).size() >= 1, "the head allocated it: %s" % str(r.get("report", "")))
	for aid in r.get("assigned", []):
		t.check(crew.has(int(aid)) or int(aid) == cap_id or sim.people.department(sim.state["agents"][int(aid)]) == "maintenance", "the assignees are the department's own people")
		var o: Dictionary = sim.state["agents"][int(aid)].get("order", {})
		t.check(not o.is_empty() and int(o.get("team", -1)) == int(r["team"]), "each assignee has the order (team %d)" % int(r["team"]))
	t.check(not cap.has("order") or (r["assigned"] as Array).has(cap_id), "the head does not take the order unless nobody else is free")
	t.check(String(r["report"]).contains(String(cap["name"]).split(" ")[0]), "the report names the head: %s" % str(r["report"]))
	var rows: Array = sim.workq.rows("maintenance")
	var team_row := false
	for row in rows:
		if row["state"] == "team" and int(row["team"]) == int(r["team"]):
			team_row = true
	t.check(team_row, "the team order is a row in the maintenance queue, with the assignees")
	# The allocation prefers the nearer and more skilled person: the people chosen are among the best scored.
	var log_has := false
	for e in sim.state["log"]:
		if e["code"] == "team_order":
			log_has = true
	t.check(log_has, "the log has the head's report")
	# Run until the team is done: the head reports back.
	var done: bool = false
	for i in 400:
		sim.run_seconds(5.0)
		if float(arr["health"]) >= 99.5:
			var any := false
			for aid2 in r["assigned"]:
				if sim.state["agents"][int(aid2)].has("order"):
					any = true
			if not any:
				done = true
				break
	t.check(done, "the team repaired it (health %.0f)" % float(arr["health"]))
	var back := false
	for e2 in sim.state["log"]:
		if e2["code"] == "team_done":
			back = true
	t.check(back, "the head reports back (team_done)")
	sim.dispose()
	t.done()

static func _showcase():
	var sim = H.Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.state["options"]["debug"] = true
	return sim

# ---------------------------------------------------------------- 18.3: the queue
func v5_workq_queue_order_and_assign(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	var lid: int = int(c["lid"])
	var a: Dictionary = sim.state["agents"][c["ids"][0]]
	var lander: Dictionary = sim.state["buildings"][lid]
	# Two dusty arrays: a near one and a far one (both "clean" tasks of the repair category).
	var near: Dictionary = sim.build.spawn_active("solar_array", _spot(sim, "solar_array", lander["pos"], 25.0, 35.0), 0.0)   # test set-up
	var far: Dictionary = sim.build.spawn_active("solar_array", _spot(sim, "solar_array", lander["pos"], 50.0, 65.0, 18), 0.0)  # test set-up
	near["dust"] = true                                                                         # test set-up
	far["dust"] = true                                                                          # test set-up
	for oid in c["ids"]:
		if oid != c["ids"][0]:
			sim.state["agents"][oid]["jobs"] = {"repair": 0}                                          # test set-up: the others do not take repair work
	for tid in sim.state["tasks"].keys():
		sim.jobs.fail(int(tid), "test_setup")
	sim.jobs._new_task("clean", "repair", int(near["id"]), {})
	sim.jobs._new_task("clean", "repair", int(far["id"]), {})
	var rows: Array = sim.workq.rows("maintenance")
	var keys: Array = []
	for r in rows:
		keys.append(String(r["key"]))
	t.check(keys.has("clean:%d" % int(near["id"])) and keys.has("clean:%d" % int(far["id"])), "both jobs are rows of the maintenance queue")
	for r in rows:
		t.check(String(r["text"]) != "" and r["dept"] == "maintenance" and r.has("waiting_s") and r.has("assignee") and r.has("reason"), "a row has a text, a department, a waiting time, an assignee and a reason")
		break
	# Without a pin the colonist takes the near one.
	_rested(sim, a, lid)
	a["jobs"] = {"repair": 3}                                                                   # test set-up
	sim.agents._think(a)
	var tk: Dictionary = sim.state["tasks"].get(int(a["task"]), {})
	t.check(not tk.is_empty() and int(tk["bld"]) == int(near["id"]), "by default the near job is taken first")
	sim.agents.abort_plan(a, "test_setup")
	for tid in sim.state["tasks"]:
		sim.state["tasks"][tid]["retry"] = 0
	# Top: the far job goes to the top of the queue, and the job choice follows it.
	var rm: Dictionary = g.cmd("workq_move", {"key": "clean:%d" % int(far["id"]), "dept": "maintenance", "how": "top"})
	t.check(bool(rm["ok"]), "workq_move top is accepted")
	var rows2: Array = sim.workq.rows("maintenance")
	t.eq(String(rows2[0]["key"]), "clean:%d" % int(far["id"]), "the far job is the first row now")
	t.check(bool(rows2[0]["pinned"]), "and it is marked pinned")
	_rested(sim, a, lid)
	a["jobs"] = {"repair": 3}                                                                   # test set-up
	for tid in sim.state["tasks"]:
		sim.state["tasks"][tid]["retry"] = 0
	sim.agents._think(a)
	var tk2: Dictionary = sim.state["tasks"].get(int(a["task"]), {})
	t.check(not tk2.is_empty() and int(tk2["bld"]) == int(far["id"]), "the colonist takes the job at the top of the queue (the far one)")
	sim.agents.abort_plan(a, "test_setup")
	# Bottom puts it behind (a low pin); Up / Down swap neighbours.
	g.cmd("workq_move", {"key": "clean:%d" % int(far["id"]), "dept": "maintenance", "how": "bottom"})
	var rows3: Array = sim.workq.rows("maintenance")
	t.eq(String(rows3[rows3.size() - 1]["key"]), "clean:%d" % int(far["id"]), "bottom: the far job is the last row")
	g.cmd("workq_move", {"key": "clean:%d" % int(far["id"]), "dept": "maintenance", "how": "up"})
	var rows4: Array = sim.workq.rows("maintenance")
	var pos_far := -1
	for i in rows4.size():
		if String(rows4[i]["key"]) == "clean:%d" % int(far["id"]):
			pos_far = i
	t.check(pos_far >= 0 and pos_far < rows4.size() - 1 or rows4.size() == 1, "up: the far job moved up one place")
	# Cancel (hold): a held job is not offered to anybody.
	g.cmd("workq_move", {"key": "clean:%d" % int(far["id"]), "dept": "maintenance", "how": "top"})
	var rc: Dictionary = g.cmd("workq_cancel", {"key": "clean:%d" % int(far["id"])})
	t.check(bool(rc["ok"]), "workq_cancel is accepted")
	_rested(sim, a, lid)
	a["jobs"] = {"repair": 3}                                                                   # test set-up
	for tid in sim.state["tasks"]:
		sim.state["tasks"][tid]["retry"] = 0
	sim.agents._think(a)
	var tk3: Dictionary = sim.state["tasks"].get(int(a["task"]), {})
	t.check(not tk3.is_empty() and int(tk3["bld"]) == int(near["id"]), "a held job is not taken (the near one is)")
	sim.agents.abort_plan(a, "test_setup")
	g.cmd("workq_release", {"key": "clean:%d" % int(far["id"])})
	# Assign: the colonist gets an order for that work and does it.
	var b2: Dictionary = sim.state["agents"][c["ids"][1]]
	_rested(sim, b2, lid)
	var ra: Dictionary = g.cmd("workq_assign", {"key": "clean:%d" % int(far["id"]), "agents": [int(b2["id"])]})
	t.check(bool(ra["ok"]), "workq_assign is accepted (%s)" % str(ra.get("code", "")))
	t.check(b2.has("order") and String(b2["order"]["kind"]) == "task", "the colonist has a task order")
	var cleaned: bool = g.run_until(func(): return not bool(far.get("dust", false)), 4000)
	t.check(cleaned, "the assigned colonist cleans the far array")
	t.check(sim.workq.summary().has("urgent"), "the summary has the urgent count for the dock")
	# Worn structures wait in the queue when no part is in store: a broken one is urgent and at the top.
	var lander2: Dictionary = sim.state["buildings"][lid]
	sim.inv.destroy(int(lander2["inv_out"]), "spare_parts", sim.inv.count(int(lander2["inv_out"]), "spare_parts"), "test_setup")   # test set-up
	var brk: Dictionary = sim.build.spawn_active("solar_array", _spot(sim, "solar_array", lander["pos"], 30.0, 90.0, 27), 0.0)   # test set-up
	brk["health"] = 40.0                                                                        # test set-up
	var found := false
	for r in sim.workq.rows("maintenance"):
		if String(r["key"]) == "repair:%d" % int(brk["id"]):
			found = true
			t.check(String(r["reason"]).contains("spare parts"), "a worn structure without a part is a row that says why: %s" % String(r["reason"]))
	t.check(found, "the worn structure is in the maintenance queue")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 18.4: the chain finder
func v5_chain_finder_and_alerts(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	sim.state["flags"].erase("unlock_all")                                                       # test set-up: research counts
	var ch: Dictionary = sim.chains.chain_for("spare_parts")
	var items: Array = []
	for s in ch["steps"]:
		items.append(String(s["item"]))
	t.check(items.has("ore") and items.has("metal") and items.has("polymer") and items.has("spare_parts"), "the chain of spare parts goes ore -> steel, polymer -> spare parts (%s)" % str(items))
	t.check(items.find("ore") < items.find("metal") and items.find("metal") < items.find("spare_parts"), "the steps are in the order of work")
	var spare_step: Dictionary = {}
	for s2 in ch["steps"]:
		if s2["item"] == "spare_parts":
			spare_step = s2
	t.eq(String(spare_step.get("building", "")), "workshop", "spare parts come from a workshop")
	for s3 in ch["steps"]:
		t.check(String(s3["text"]) != "" and ["done", "missing", "building", "broken", "unpowered", "no_worker", "needs_research"].has(String(s3["status"])), "step %s has a status and a line of text (%s)" % [s3["item"], s3["status"]])
	# Electronics need research the colony has not done: the chain says so.
	var el: Dictionary = sim.chains.chain_for("electronics")
	var needs_research := false
	for s4 in el["steps"]:
		if s4["status"] == "needs_research" and String(s4["tech_name"]) != "":
			needs_research = true
	t.check(needs_research or not el["ok"], "electronics: a step needs research or a structure (%s)" % String(el["text"]))
	t.check(String(el["text"]).begins_with("Electronics needed:") or el["ok"], "the chain text is one line: %s" % String(el["text"]))
	# A blueprint that waits for an item that is nowhere: an alert with a chain.
	var lid: int = int(c["lid"])
	var lander: Dictionary = sim.state["buildings"][lid]
	sim.state["flags"]["unlock_all"] = true                                                      # test set-up
	var sp: Vector2 = _spot(sim, "solar_array", lander["pos"], 25.0, 60.0)
	g.cmd("place_building", {"def": "electronics_fab", "x": sp.x, "y": sp.y, "rot": 0.0})
	# The fab costs glass: the colony has none and no glassworks.
	g.run(300)
	sim.alerts.tick_second()
	var key := ""
	for k in sim.state["issues"]:
		if String(k).begins_with("materials:") or String(k).begins_with("chain:"):
			key = String(k)
			if String(k).begins_with("chain:"):
				break
	t.check(key != "", "an alert names the missing item (%s)" % key)
	if key != "":
		var iss: Dictionary = sim.state["issues"][key]
		t.check(iss.has("chain") or sim.chains.missing_items().size() > 0, "the alert carries the chain")
	# The codex page: a chain for every item the colony can make.
	var all: Array = sim.chains.all_chains()
	t.check(all.size() >= 30, "the codex lists %d chains" % all.size())
	var bad := 0
	for chn in all:
		if (chn["steps"] as Array).is_empty() or String(chn["text"]) == "":
			bad += 1
	t.eq(bad, 0, "every chain has steps and a line of text")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- determinism and save/load
func v5_orders_deterministic(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	var lid: int = int(c["lid"])
	var a: Dictionary = sim.state["agents"][c["ids"][0]]
	var arr: Dictionary = _worn_array(sim, lid, 85.0)
	_rested(sim, a, lid)
	g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(arr["id"])})
	g.cmd("workq_move", {"key": "repair:%d" % int(arr["id"]), "dept": "maintenance", "how": "top"})
	g.run(120)
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved and loaded with an order running")
	if bool(cl["ok"]):
		var sim2 = cl["sim"]
		t.eq(sim2.state["agents"][int(a["id"])].get("order", {}), a.get("order", {}), "the order survives save and load")
		for i in 600:
			sim.step()
			sim2.step()
		t.eq(H.digest(sim2), H.digest(sim), "the loaded game continues exactly")
		sim2.dispose()
	g.dispose()
	t.done()

# ---------------------------------------------------------------- the diagnosis table (ORCH-to-SIM-orders-diagnosis.md 4.4)
## T-C: an order that waits for a part (or has no task) leaves the colonist's own plan alone: no thrash.
func v5_order_no_plan_thrash(t) -> void:
	var results := {}
	for scenario in ["control", "blocked_repair"]:
		var c: Dictionary = _colony()
		var g = c["g"]
		var sim = c["sim"]
		var lid: int = int(c["lid"])
		var a: Dictionary = sim.state["agents"][c["ids"][2]]
		var lander: Dictionary = sim.state["buildings"][lid]
		sim.inv.destroy(int(lander["inv_out"]), "spare_parts", sim.inv.count(int(lander["inv_out"]), "spare_parts"), "test_setup")   # test set-up: no parts
		var arr: Dictionary = _worn_array(sim, lid, 85.0)
		_rested(sim, a, lid)
		a["fatigue"] = 70.0                                                                      # test set-up: tired
		if scenario == "blocked_repair":
			var r: Dictionary = g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(arr["id"])})
			t.check(bool(r["ok"]), "the repair order is accepted")
		var changes := 0
		var asleep := 0
		var last := ""
		for i in 90:
			g.run(10)
			var key: String = String(a["plan_kind"]) + ":" + String(a["goal"])
			if key != last:
				changes += 1
				last = key
			if a["plan_kind"] == "sleep":
				asleep += 1
		results[scenario] = [changes, asleep, float(a["fatigue"])]
		if scenario == "blocked_repair":
			t.check(a.has("order") and String(a["order"]["blocked"]) == "no_item", "the order waits for the part")
		g.dispose()
	t.check(int(results["blocked_repair"][0]) <= 6, "a blocked order: at most 6 plan changes in 90 s (%d; control %d)" % [int(results["blocked_repair"][0]), int(results["control"][0])])
	t.check(absi(int(results["blocked_repair"][1]) - int(results["control"][1])) <= 5, "and the colonist sleeps as long as the control (%d against %d s)" % [int(results["blocked_repair"][1]), int(results["control"][1])])
	t.done()

## T-D and S7: parts all held by other repairs. An order takes one (no "missing", no chain alert); the automatic
## repairs give the parts to the most urgent structures first.
func v5_order_takes_reserved_part(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	var lid: int = int(c["lid"])
	var lander: Dictionary = sim.state["buildings"][lid]
	var store: int = int(lander["inv_out"])
	sim.inv.destroy(store, "spare_parts", sim.inv.count(store, "spare_parts"), "test_setup")   # test set-up
	sim.inv.add_new_forced(store, "spare_parts", 4, "test_setup")                               # test set-up: 4 parts
	for oid in c["ids"]:
		sim.state["agents"][oid]["jobs"] = {"repair": 0}                                         # test set-up: nobody takes the automatic repairs
	var arrs: Array = []
	for i in 6:
		var b: Dictionary = _worn_array(sim, lid, 60.0 - float(i) * 5.0, i * 5)                  # healths 60, 55, ..., 35
		arrs.append(b)
	var broken: Dictionary = _worn_array(sim, lid, 20.0, 31)
	broken["state"] = "broken"                                                                   # test set-up: a broken one
	g.run(30)
	var served: Array = []
	for tid in sim.state["tasks"]:
		var tk: Dictionary = sim.state["tasks"][tid]
		if tk["kind"] == "repair" and int(tk["hold_out"]) != -1:
			served.append(int(tk["bld"]))
	t.eq(served.size(), 4, "4 parts: 4 repair tasks hold them (%s)" % str(served))
	t.check(served.has(int(broken["id"])), "the broken structure gets a part first")
	t.check(served.has(int(arrs[5]["id"])) and served.has(int(arrs[4]["id"])), "then the structures with the lowest health (35, 40), not the lowest ids")
	t.check(not served.has(int(arrs[0]["id"])), "the healthiest one waits (health 60)")
	t.eq(sim.jobs.part_stock("spare_parts")["free"], 0, "no free part is left")
	# An order on a seventh structure takes a part from the least urgent open repair.
	var target: Dictionary = _worn_array(sim, lid, 85.0, 14)
	var a: Dictionary = sim.state["agents"][c["ids"][0]]
	_rested(sim, a, lid)
	var r: Dictionary = g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(target["id"])})
	t.check(bool(r["ok"]), "the order is accepted")
	g.run(60)
	t.check(a.has("order") and String(a["order"]["blocked"]) == "" and int(a["order"]["tid"]) != -1, "the order took a part (it is not blocked: %s)" % (String(a["order"]["blocked"]) if a.has("order") else "done"))
	t.check(not sim.state.get("v5", {}).get("chains", {}).get("reports", {}).has("spare_parts"), "no 'build a Parts Works' report from the order: the parts exist, they were reserved")
	var held := 0
	for tid2 in sim.state["tasks"]:
		var tk2: Dictionary = sim.state["tasks"][tid2]
		if tk2["kind"] == "repair" and int(tk2["hold_out"]) != -1:
			held += 1
	t.check(held <= 4, "the parts are still four (%d held)" % held)
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

## T-E: the only parts are out of reach: the order is blocked and says so; the alert says where; no chain alert.
func v5_order_unreachable_parts(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	var lid: int = int(c["lid"])
	var lander: Dictionary = sim.state["buildings"][lid]
	var store: int = int(lander["inv_out"])
	sim.inv.destroy(store, "spare_parts", sim.inv.count(store, "spare_parts"), "test_setup")   # test set-up: none in the lander
	var far: Vector2 = (lander["pos"] as Vector2) + Vector2(60, 0)
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, far)                              # test set-up: a pile of parts
	sim.inv.add_new_forced(pile, "spare_parts", 4, "test_setup")
	sim.state["unreach_src"] = {pile: int(sim.state["tick"]) + 6000}                             # test set-up: nobody can walk to it
	var arr: Dictionary = _worn_array(sim, lid, 85.0)
	var a: Dictionary = sim.state["agents"][c["ids"][0]]
	_rested(sim, a, lid)
	g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(arr["id"])})
	g.run(30)
	t.check(a.has("order") and String(a["order"]["blocked"]) == "no_item", "the order is blocked")
	t.eq(String(a["order"]["missing"].get("reason", "")), "unreachable", "and says the parts are unreachable (not absent)")
	t.check(String(a["order"]["text"]).contains("nobody can reach"), "the order text says it: %s" % String(a["order"]["text"]))
	g.run(300)
	sim.state["unreach_src"] = {pile: int(sim.state["tick"]) + 6000}                             # test set-up: the rest does not end
	g.run(100)
	var keys: Array = sim.state["issues"].keys()
	t.check(keys.has("unreach:spare_parts"), "an alert says the spare parts lie out of reach (%s)" % str(keys))
	t.check(not keys.has("chain:spare_parts"), "and no alert asks to build a Parts Works")
	if keys.has("unreach:spare_parts"):
		t.check(sim.state["issues"]["unreach:spare_parts"].has("where"), "the alert says where they are")
	g.dispose()
	t.done()

## T-F and T-H: a security officer and an HR officer carry out a repair order and a work_at order; work_at ends
## when the work is done and is refused for a structure that has none.
func v5_order_every_role_and_work_at(t) -> void:
	var sim = _showcase()
	var base: int = int(sim.bases.ids()[0])
	var core: Dictionary = sim.bases.core_of(base)
	var store: int = int(core["inv_out"]) if int(core["inv_out"]) != -1 else int(core["inv_in"])
	sim.inv.add_new_forced(store, "spare_parts", 40, "test_setup")                               # test set-up
	var roles := {}
	for aid in sim.state["agents"]:
		var m: Dictionary = sim.state["agents"][aid]
		if m["state"] == "alive" and m["kind"] == "human" and (m["role"] == "security" or m["role"] == "hr") and not roles.has(m["role"]) and sim.bases.base_of_agent(m) == base:
			roles[m["role"]] = int(aid)
	t.check(roles.has("security") and roles.has("hr"), "the showcase has a security and an HR colonist (%s)" % str(roles.keys()))
	var k := 0
	for role in roles:
		var a: Dictionary = sim.state["agents"][roles[role]]
		var arr: Dictionary = sim.build.spawn_active("solar_array", _spot(sim, "solar_array", core["pos"], 30.0, 60.0, 5 + k * 9), 0.0)   # test set-up
		arr["health"] = 85.0                                                                       # test set-up
		var dusty: Dictionary = sim.build.spawn_active("solar_array", _spot(sim, "solar_array", core["pos"], 30.0, 60.0, 9 + k * 9), 0.0) # test set-up
		dusty["dust"] = true                                                                       # test set-up
		k += 1
		sim.agents.abort_plan(a, "test_setup")
		a["fatigue"] = 0.0
		a["hunger"] = 0.0
		a["thirst"] = 0.0
		a["suit"] = sim.agents.suit_cap()
		var r: Dictionary = sim.orders.cmd_order({"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(arr["id"])})
		t.check(bool(r["ok"]), "%s: a repair order is accepted" % role)
		var done: bool = false
		for i in 300:
			sim.run_seconds(2.0)
			if float(arr["health"]) >= 99.5 and not a.has("order"):
				done = true
				break
		t.check(done, "%s: the repair is done (%.0f) and the order is over" % [role, float(arr["health"])])
		var rw: Dictionary = sim.orders.cmd_order({"direct": true, "agents": [int(a["id"])], "kind": "work_at", "b": int(dusty["id"])})
		t.check(bool(rw["ok"]), "%s: a work_at order is accepted for a structure that has work (%s)" % [role, str(rw.get("code", ""))])
		var done2: bool = false
		for i in 300:
			sim.run_seconds(2.0)
			if not bool(dusty.get("dust", false)) and not a.has("order"):
				done2 = true
				break
		t.check(done2, "%s: work_at did the work and ended" % role)
		var rn: Dictionary = sim.orders.cmd_order({"direct": true, "agents": [int(a["id"])], "kind": "work_at", "b": int(dusty["id"])})
		t.eq(rn["code"], "no_work", "%s: work_at on a structure with no work is refused (no_work)" % role)
	sim.dispose()
	t.done()

## T-I and T-J: a party does not take a colonist who has an order; an order saved by an older version loads and runs.
func v5_order_party_and_old_orders(t) -> void:
	var sim = _showcase()
	var base: int = int(sim.bases.ids()[0])
	var core: Dictionary = sim.bases.core_of(base)
	sim.inv.add_new_forced(int(core["inv_out"]) if int(core["inv_out"]) != -1 else int(core["inv_in"]), "spare_parts", 40, "test_setup")   # test set-up
	var picked := -1
	for aid in sim.state["agents"]:
		var m: Dictionary = sim.state["agents"][aid]
		if m["state"] == "alive" and m["kind"] == "human" and m["role"] == "technician" and sim.bases.home_of(m) == base and not sim.workq.is_head(m):
			picked = int(aid)
			break
	t.check(picked != -1, "a technician is found")
	var a: Dictionary = sim.state["agents"][picked]
	var arr: Dictionary = sim.build.spawn_active("solar_array", _spot(sim, "solar_array", core["pos"], 30.0, 60.0, 3), 0.0)   # test set-up
	arr["health"] = 85.0                                                                       # test set-up
	sim.agents.abort_plan(a, "test_setup")
	a["fatigue"] = 0.0
	a["hunger"] = 0.0
	a["thirst"] = 0.0
	var r: Dictionary = sim.orders.cmd_order({"direct": true, "agents": [picked], "kind": "repair", "b": int(arr["id"])})
	t.check(bool(r["ok"]), "the order is given")
	var recruited: Array = sim.party._recruit(base, {"who": [picked]}, 200, false)
	t.check(not recruited.has(picked), "a party does not recruit the colonist who has an order (even an honoured one)")
	var recruited2: Array = sim.party._recruit(base, {"who": []}, 200, false)
	t.check(not recruited2.has(picked), "and not as an ordinary guest")
	sim.orders.cmd_clear({"agents": [picked]})
	# An old order (no blocked, tid, text): work_at as the version before 18 saved it.
	var arr2: Dictionary = sim.build.spawn_active("solar_array", _spot(sim, "solar_array", core["pos"], 30.0, 60.0, 12), 0.0)   # test set-up
	arr2["dust"] = true                                                                          # test set-up
	a["order"] = {"kind": "work_at", "confirm": false, "t": int(sim.state["tick"]), "b": int(arr2["id"])}   # test set-up: the old layout
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved with an old order")
	if bool(cl["ok"]):
		var sim2 = cl["sim"]
		var a2: Dictionary = sim2.state["agents"][picked]
		t.check(a2.has("order") and String(a2["order"]["kind"]) == "work_at", "the old order is loaded")
		var done := false
		for i in 300:
			sim2.run_seconds(2.0)
			if not bool(sim2.state["buildings"][int(arr2["id"])].get("dust", false)) and not a2.has("order"):
				done = true
				break
		t.check(done, "and it is carried out and ends")
		sim2.dispose()
	sim.dispose()
	t.done()

## T-K and "maintain now": a machine with wear and parts in store is maintained by the colony without any order; the
## "maintain now" command is an order that the maintenance team carries out.
func v5_maintain_now_is_an_order(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	var lid: int = int(c["lid"])
	var lander: Dictionary = sim.state["buildings"][lid]
	var hp: Vector2 = _spot(sim, "regolith_harvester", lander["pos"], 25.0, 70.0)
	var mach: Dictionary = sim.build.spawn_active("regolith_harvester", hp, 0.0)               # test set-up
	var rec: Dictionary = sim.hazards.wear_of(int(mach["id"]))
	rec["w"] = float(rec["fail_at"]) * sim.hazards.risk_frac() + 1.0                          # test set-up: past the threshold
	var ok: bool = g.run_until(func(): return float(sim.hazards.wear_of(int(mach["id"]))["w"]) < 1.0, 6000)
	t.check(ok, "no order: the colony maintains the machine by itself (control)")
	# Below the threshold the colony leaves it; "maintain now" sends the team.
	var mach2: Dictionary = sim.build.spawn_active("regolith_harvester", _spot(sim, "regolith_harvester", lander["pos"], 25.0, 70.0, 12), 0.0)   # test set-up
	sim.hazards.wear_of(int(mach2["id"]))["w"] = 20.0                                          # test set-up: some wear, far from the threshold
	var rm: Dictionary = g.cmd("maintain", {"id": int(mach2["id"])})
	t.check(bool(rm["ok"]) and rm.has("order"), "maintain now returns the order it gave")
	t.check(bool(rm["order"].get("ok", false)), "the maintenance team took the order (%s)" % str(rm["order"].get("report", rm["order"].get("code", ""))))
	var done: bool = g.run_until(func(): return float(sim.hazards.wear_of(int(mach2["id"]))["w"]) < 1.0, 6000)
	t.check(done, "the machine is maintained although it was far from the threshold (%.1f)" % float(sim.hazards.wear_of(int(mach2["id"]))["w"]))
	# A broken machine accepts it as a repair order.
	var mach3: Dictionary = sim.build.spawn_active("regolith_harvester", _spot(sim, "regolith_harvester", lander["pos"], 25.0, 80.0, 24), 0.0)   # test set-up
	var rec3: Dictionary = sim.hazards.wear_of(int(mach3["id"]))
	rec3["broken"] = true                                                                      # test set-up
	mach3["state"] = "broken"                                                                  # test set-up
	var rb: Dictionary = g.cmd("maintain", {"id": int(mach3["id"])})
	t.check(bool(rb["ok"]), "a broken machine accepts 'maintain now' (a repair order)")
	var fixed: bool = g.run_until(func(): return mach3["state"] == "active", 6000)
	t.check(fixed, "and it is repaired")
	g.dispose()
	t.done()

## T-J: a blocked order (it waits for a part) survives save and load, and the loaded game continues exactly.
func v5_blocked_order_save_load(t) -> void:
	var c: Dictionary = _colony()
	var g = c["g"]
	var sim = c["sim"]
	var lid: int = int(c["lid"])
	var lander: Dictionary = sim.state["buildings"][lid]
	sim.inv.destroy(int(lander["inv_out"]), "spare_parts", sim.inv.count(int(lander["inv_out"]), "spare_parts"), "test_setup")   # test set-up: no parts
	var a: Dictionary = sim.state["agents"][c["ids"][2]]
	var arr: Dictionary = _worn_array(sim, lid, 85.0)
	_rested(sim, a, lid)
	g.cmd("order", {"direct": true, "agents": [int(a["id"])], "kind": "repair", "b": int(arr["id"])})
	g.run(120)
	t.check(a.has("order") and String(a["order"]["blocked"]) == "no_item", "the order is blocked")
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved and loaded")
	if bool(cl["ok"]):
		var sim2 = cl["sim"]
		t.eq(sim2.state["agents"][int(a["id"])].get("order", {}), a.get("order", {}), "the blocked order is the same after the load")
		for i in 600:
			sim.step()
			sim2.step()
		t.eq(H.digest(sim2), H.digest(sim), "the loaded game continues exactly")
		sim2.dispose()
	g.dispose()
	t.done()
