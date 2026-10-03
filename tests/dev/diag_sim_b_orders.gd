extends SceneTree
## Diagnostic (SIM path, no game file edited): why an ordered repair does not happen.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_sim_b_orders.gd [scenario ...]
## Scenarios: s1 s2 s3 s4 s5 s6 s7 s8 (default: all)
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const SAVE := "res://content/saves/showcase_v5.fhsave"
const HZ := 10

func _load(spares := 6):
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(SAVE))["state"])
	sim.run_seconds(3.0)
	# The save has no workshop and its only 4 spare parts lie in a ground pile that colonists cannot reach.
	# Test set-up: put spare parts in Storehouse 1 (a reachable store) so the ORDER path is what is measured.
	if spares > 0:
		var ids: Array = sim.state["buildings"].keys()
		ids.sort()
		for id in ids:
			var b: Dictionary = sim.state["buildings"][id]
			if b["def"] == "storehouse" and b["state"] == "active":
				sim.inv.add_new_forced(int(b["inv_out"]), "spare_parts", spares, "diag")
				break
	return sim

func _agent(sim, role: String, skip := [], allow_job := false) -> Dictionary:
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["kind"] != "human" or String(a["role"]) != role or skip.has(aid):
			continue
		if a["where"] != "in" or a.has("order") or a.has("v5_hold") or a.has("jailed") or a.has("party") or sim.education.in_class(a):
			continue
		if a.has("job") and not allow_job:
			continue
		return a
	return {}

func _bld(sim, def: String) -> Dictionary:
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.state["buildings"][id]
		if b["def"] == def and b["state"] == "active":
			return b
	return {}

func _clear(sim, a: Dictionary) -> void:
	sim.agents.abort_plan(a, "diag")
	a["hunger"] = 5.0
	a["thirst"] = 5.0
	a["fatigue"] = 5.0
	a["health"] = 100.0

func _strip(sim, item: String) -> int:
	var n := 0
	for iid in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][iid]
		if inv["items"].has(item):
			n += int(inv["items"][item])
			inv["items"].erase(item)
	return n

func _tasks_for(sim, bid: int) -> Array:
	var out: Array = []
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if int(t["bld"]) == bid:
			out.append("%s#%d state=%s owner=%d emerg=%d role=%s reason=%s res=%s" % [t["kind"], tid, t["state"], int(t["owner"]), int(t["emergency"]), t["role"], t["reason"], t["res"]])
	return out

func _order(sim, a: Dictionary, kind: String, extra := {}) -> Dictionary:
	var p := {"agents": [int(a["id"])], "kind": kind}
	p.merge(extra)
	var r: Dictionary = sim.orders.cmd_order(p)   # same call the "order" command makes (commands.gd:116)
	return r

func _ts(sim) -> float:
	return float(sim.state["tick"]) / float(HZ)

func _snap(sim, a: Dictionary) -> String:
	return "t=%.0f plan_kind=%s goal='%s' where=%s order=%s task=%d hunger=%.0f fatigue=%.0f" % [_ts(sim), a["plan_kind"], a["goal"], a["where"], str(a["order"]["kind"]) if a.has("order") else "-", int(a["task"]), float(a["hunger"]), float(a["fatigue"])]

func _init() -> void:
	var want: Array = Array(OS.get_cmdline_user_args())
	if want.is_empty():
		want = ["s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11"]
	for s in want:
		print("=================== ", s)
		call("_" + s)
	quit(0)

# ----- S1: when does a worn structure get a repair task? (spares / no spares)
func _s1() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var sto: Dictionary = _bld(sim, "storehouse")
	print("spare_parts in colony: ", sim.inv.totals().get("spare_parts", {}))
	hab["health"] = 60.0
	sim.run_seconds(2.0)
	print("[with spares] Habitat health 60 ->", _tasks_for(sim, int(hab["id"])), " block='", hab["block"], "'")
	var removed: int = _strip(sim, "spare_parts")
	# the repair task already made keeps its hold; remove it too, then make a fresh worn building
	sim.jobs.cancel_tasks_for_building(int(hab["id"]), "diag")
	print("stripped spare_parts: ", removed)
	sto["health"] = 60.0
	sim.run_seconds(5.0)
	print("[NO spares] Storehouse health 60 -> tasks:", _tasks_for(sim, int(sto["id"])), " block='", sto["block"], "' state=", sto["state"])
	var codes: Array = []
	for k in sim.state["issues"]:
		codes.append(String(sim.state["issues"][k].get("code", "")))
	print("alert codes present: ", codes)
	var a: Dictionary = _agent(sim, "grower")
	_clear(sim, a)
	var r: Dictionary = _order(sim, a, "work_at", {"b": int(sto["id"])})
	print("order accepted: ", r["ok"], " ", r["code"])
	for i in 6:
		sim.run_seconds(10.0)
		print("  ", _snap(sim, a))
	print("[NO spares] order still held after 60 s: ", a.has("order"), " tasks:", _tasks_for(sim, int(sto["id"])))
	sim.dispose()

# ----- S2: control. Free colonist, spares present, order work_at a worn building. Then what after?
func _s2() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	# take technicians out of the pool so only the order can do it (what the player sees: nobody else comes)
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	print("tasks on Habitat before the order: ", _tasks_for(sim, bid))
	var a: Dictionary = _agent(sim, "grower")
	_clear(sim, a)
	print("colonist ", a["name"], " role ", a["role"])
	var r: Dictionary = _order(sim, a, "work_at", {"b": bid})
	print("order: ", r["ok"], " ", r["code"], " | ", _snap(sim, a))
	var t0: float = _ts(sim)
	var started := -1.0
	var done := -1.0
	var h0: float = float(hab["health"])
	for i in 400:
		sim.run_seconds(1.0)
		a["hunger"] = 5.0
		a["fatigue"] = 5.0
		if started < 0.0 and a["plan_kind"] == "task":
			started = _ts(sim) - t0
			print("  task started after %.0f s: %s" % [started, _snap(sim, a)])
		if done < 0.0 and float(hab["health"]) > h0 + 1.0:
			done = _ts(sim) - t0
			print("  repair done after %.0f s: health %.1f" % [done, float(hab["health"])])
			break
	print("after repair: ", _snap(sim, a))
	sim.run_seconds(3.0)
	print("3 s later    : ", _snap(sim, a))
	# another worn building appears while he holds the order
	var sto: Dictionary = _bld(sim, "storehouse")
	sto["health"] = 55.0
	for i in 12:
		sim.run_seconds(5.0)
		a["hunger"] = 5.0
		a["fatigue"] = 5.0
	print("60 s later with a SECOND worn building (Storehouse health 55, tasks %s): " % str(_tasks_for(sim, int(sto["id"]))))
	print("   ", _snap(sim, a))
	print("order still present: ", a.has("order"))
	sim.dispose()

# ----- S3: sleeping colonist gets a work_at order
func _s3() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	var a: Dictionary = _agent(sim, "grower")
	_clear(sim, a)
	a["fatigue"] = 80.0
	var ok: bool = sim.agents._try_sleep(a)
	print("started sleep plan: ", ok, " | ", _snap(sim, a), " night=", sim.util.is_night())
	sim.run_seconds(8.0)
	print("sleeping now: ", _snap(sim, a))
	var r: Dictionary = _order(sim, a, "work_at", {"b": bid})
	print("order: ", r["ok"], " | ", _snap(sim, a))
	var t0: float = _ts(sim)
	var last := ""
	for i in 300:
		sim.run_seconds(1.0)
		var s: String = "%s|%s" % [a["plan_kind"], a["goal"]]
		if s != last:
			print("  +%3.0f s  %s" % [_ts(sim) - t0, _snap(sim, a)])
			last = s
		if a["plan_kind"] == "task":
			break
	print("order given at t=%.0f; colonist started repairing at +%.0f s" % [t0, _ts(sim) - t0])
	sim.dispose()

# ----- S4: party guest gets a work_at order; and a "go" order for contrast
func _s4() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	var a: Dictionary = _agent(sim, "grower")
	var b2: Dictionary = _agent(sim, "grower", [int(a["id"])])
	for x in [a, b2]:
		_clear(sim, x)
	var venue_id: int = int(a["bld"])
	# exactly what party.gd:456-457 does for every guest
	for x in [a, b2]:
		x["party"] = 1
		var ok: bool = sim.agents._start_personal(x, "party", venue_id, [{"op": "wait", "t": 160.0}], "Going to the party", -1)
		print("guest ", x["name"], " party plan started: ", ok)
	sim.run_seconds(10.0)
	print("partying: ", _snap(sim, a))
	_order(sim, a, "work_at", {"b": bid})
	var tgo: float = _ts(sim)
	print("work_at given to A at t=%.0f: %s" % [tgo, _snap(sim, a)])
	# contrast: a "go" order to B (aborts the plan at once, orders.gd:241)
	var hp: Vector2 = hab["pos"]
	var rr: Dictionary = _order(sim, b2, "go", {"x": hp.x, "y": hp.y})
	print("go given to B: ", rr["ok"], " ", rr["code"], " | ", _snap(sim, b2))
	var lastA := ""
	var lastB := ""
	for i in 420:
		sim.run_seconds(1.0)
		a["hunger"] = minf(float(a["hunger"]), 20.0)
		a["fatigue"] = minf(float(a["fatigue"]), 20.0)
		var sa: String = "%s|%s" % [a["plan_kind"], a["goal"]]
		if sa != lastA:
			print("  A +%3.0f s  %s" % [_ts(sim) - tgo, _snap(sim, a)])
			lastA = sa
		var sb: String = "%s|%s" % [b2["plan_kind"], b2["goal"]]
		if sb != lastB:
			print("  B +%3.0f s  %s" % [_ts(sim) - tgo, _snap(sim, b2)])
			lastB = sb
		if a["plan_kind"] == "task" and (a["goal"] as String).begins_with("Repairing"):
			break
	print("A (work_at while partying) began repairing at +%.0f s; party was 160 s long" % (_ts(sim) - tgo))
	sim.dispose()

# ----- S5: ordinary needs come BEFORE a work_at order (agents.gd:524-531 before 537)
func _s5() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	var cases := [["hunger", 65.0], ["thirst", 65.0], ["fatigue", 65.0], ["health", 50.0], ["none", 0.0]]
	var skip: Array = []
	for c in cases:
		var a: Dictionary = _agent(sim, "grower", skip)
		skip.append(int(a["id"]))
		_clear(sim, a)
		if c[0] != "none":
			a[c[0]] = c[1]
		_order(sim, a, "work_at", {"b": bid})
		# keep the task free of other claimants: only the order's colonist may take it
		sim.run_seconds(2.0)
		print("need %-8s=%.0f with work_at order -> %s" % [c[0], c[1], _snap(sim, a)])
		sim.agents.abort_plan(a, "diag")
		a.erase("order")
		sim.jobs.cancel_tasks_for_building(bid, "diag")
		sim.run_seconds(2.0)
	sim.dispose()

# ----- S6: a WORN machine (V3 wear) - when does a maintain task exist?
func _s6() -> void:
	var sim = _load()
	var wear: Dictionary = sim.hazards.hs()["wear"]
	var mid := -1
	for id in wear:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if not b.is_empty() and b["state"] == "active" and sim.hazards.is_machine(b):
			mid = int(id)
			break
	var m: Dictionary = sim.state["buildings"][mid]
	var rec: Dictionary = wear[mid]
	print("machine ", m["name"], " fault ", rec["fault"], " item ", sim.hazards.fault_item(String(rec["fault"])), " fail_at ", rec["fail_at"], " health field ", m["health"], " risk_frac ", sim.hazards.risk_frac())
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	for k in sim.state["tasks"].keys():
		var t: Dictionary = sim.state["tasks"][k]
		if int(t["bld"]) == mid:
			sim.jobs.fail(k, "diag")
	rec["w"] = float(rec["fail_at"]) * 0.5
	sim.run_seconds(3.0)
	print("wear 50%% of threshold: wants_maintenance=%s tasks=%s" % [str(sim.hazards.wants_maintenance(m)), str(_tasks_for(sim, mid))])
	var a: Dictionary = _agent(sim, "scientist")
	_clear(sim, a)
	_order(sim, a, "work_at", {"b": mid})
	sim.run_seconds(30.0)
	print("work_at on a machine at 50%% wear, 30 s later: %s" % _snap(sim, a))
	rec["w"] = float(rec["fail_at"]) * 0.8
	sim.run_seconds(3.0)
	print("wear 80%% of threshold: wants_maintenance=%s tasks=%s" % [str(sim.hazards.wants_maintenance(m)), str(_tasks_for(sim, mid))])
	print("   ordered colonist now: ", _snap(sim, a))
	# no item in stock for that fault
	var item: String = sim.hazards.fault_item(String(rec["fault"]))
	var a2: Dictionary = _agent(sim, "operator")
	_clear(sim, a2)
	sim.agents.abort_plan(a, "diag")
	for k in sim.state["tasks"].keys():
		var t2: Dictionary = sim.state["tasks"][k]
		if int(t2["bld"]) == mid:
			sim.jobs.fail(k, "diag")
	var removed: int = _strip(sim, item)
	sim.run_seconds(3.0)
	print("stripped %d %s -> wants_maintenance=%s tasks=%s block='%s'" % [removed, item, str(sim.hazards.wants_maintenance(m)), str(_tasks_for(sim, mid)), m["block"]])
	_order(sim, a2, "work_at", {"b": mid})
	sim.run_seconds(30.0)
	print("work_at with no %s in stock, 30 s later: %s" % [item, _snap(sim, a2)])
	var codes: Array = []
	for k in sim.state["issues"]:
		codes.append(String(sim.state["issues"][k].get("code", "")) + ":" + str(sim.state["issues"][k].get("text", "")).substr(0, 60))
	print("alerts: ", codes)
	sim.dispose()

# ----- S7: a free technician claims the repair first; the ordered colonist is left with nothing
func _s7() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	sim.run_seconds(2.0)
	print("tasks:", _tasks_for(sim, bid))
	var a: Dictionary = _agent(sim, "grower")
	var b2: Dictionary = _agent(sim, "scientist")
	_clear(sim, a)
	_clear(sim, b2)
	_order(sim, a, "work_at", {"b": bid})
	_order(sim, b2, "work_at", {"b": bid})
	sim.run_seconds(2.0)
	print("A grower  : ", _snap(sim, a))
	print("B scientst: ", _snap(sim, b2))
	print("tasks:", _tasks_for(sim, bid))
	sim.run_seconds(40.0)
	print("+40 s A: ", _snap(sim, a))
	print("+40 s B: ", _snap(sim, b2))
	print("tasks:", _tasks_for(sim, bid), " health ", hab["health"])
	sim.dispose()

# ----- S8: one repair task per building, so a team order cannot work as a team
func _s8() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 40.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	var team: Array = []
	var skip: Array = []
	for i in 4:
		var x: Dictionary = _agent(sim, "grower", skip)
		skip.append(int(x["id"]))
		_clear(sim, x)
		_order(sim, x, "work_at", {"b": bid})
		team.append(x)
	sim.run_seconds(3.0)
	for x in team:
		print("  ", x["name"], " ", _snap(sim, x))
	print("tasks on the habitat: ", _tasks_for(sim, bid))
	sim.dispose()

# ----- S9: a colonist with a venue job (shop staff) never reaches _try_work: duty_think (agents.gd:535) wins every second
func _s9() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	var a: Dictionary = _agent(sim, "grower", [], true)
	if not a.has("job"):
		# any colonist that holds a venue job
		for aid in sim.state["agents"]:
			var x2: Dictionary = sim.state["agents"][aid]
			if x2["state"] == "alive" and x2.has("job") and x2["where"] == "in" and x2["kind"] == "human":
				a = x2
				break
	print("colonist ", a["name"], " role ", a["role"], " job ", a.get("job"), " venue ", a.get("job_venue"))
	_clear(sim, a)
	print("tasks:", _tasks_for(sim, bid))
	_order(sim, a, "work_at", {"b": bid})
	var last := ""
	for i in 200:
		sim.run_seconds(1.0)
		a["hunger"] = 5.0
		a["fatigue"] = 5.0
		var sn: String = "%s|%s" % [a["plan_kind"], a["goal"]]
		if sn != last:
			print("  ", _snap(sim, a))
			last = sn
	print("tasks after 200 s:", _tasks_for(sim, bid), " health ", hab["health"])
	sim.dispose()

# ----- S10: roles that never call _try_work (agents.gd:537): security, hr, child
func _s10() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	for role in ["security", "hr"]:
		var a: Dictionary = _agent(sim, role, [], true)
		if a.is_empty():
			print("no free ", role)
			continue
		_clear(sim, a)
		var r: Dictionary = _order(sim, a, "work_at", {"b": bid})
		print(role, " order accepted: ", r["ok"], " ", r["code"])
		sim.run_seconds(60.0)
		print("  after 60 s: ", _snap(sim, a), " tasks:", _tasks_for(sim, bid))
		sim.agents.abort_plan(a, "diag")
		a.erase("order")
	sim.dispose()

# ----- S11: baseline with NO order. Everybody normal. How long until a worn building is repaired? Who takes it? Score ranking of a free technician.
func _s11() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	var t0: float = _ts(sim)
	var h0: float = float(hab["health"])
	var seen := false
	var owner_seen := -1
	for i in 600:
		sim.run_seconds(1.0)
		var ts: Array = _tasks_for(sim, bid)
		if not seen and not ts.is_empty():
			seen = true
			print("  +%3.0f s task created: %s" % [_ts(sim) - t0, str(ts)])
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if int(t["bld"]) == bid and int(t["owner"]) != -1 and owner_seen != int(t["owner"]):
				owner_seen = int(t["owner"])
				var o: Dictionary = sim.state["agents"][owner_seen]
				print("  +%3.0f s claimed by %s role=%s state=%s | %s" % [_ts(sim) - t0, o["name"], o["role"], t["state"], _snap(sim, o)])
		if float(hab["health"]) > h0 + 1.0:
			print("  +%3.0f s repaired: health %.1f" % [_ts(sim) - t0, float(hab["health"])])
			break
	if float(hab["health"]) <= h0 + 1.0:
		print("  NOT repaired after 600 s. tasks:", _tasks_for(sim, bid))
	# ranking for the first free technician, now
	var tech: Dictionary = _agent(sim, "technician", [], true)
	hab["health"] = 55.0
	sim.run_seconds(2.0)
	if not tech.is_empty():
		var rows: Array = []
		for tid in sim.state["tasks"]:
			var t2: Dictionary = sim.state["tasks"][tid]
			if int(t2["owner"]) != -1 or t2["state"] != "open":
				continue
			if t2["role"] != "" and t2["role"] != tech["role"]:
				continue
			rows.append([sim.jobs.score(t2, tech), "%s/%s bld=%d emerg=%d role=%s" % [t2["kind"], t2["cat"], int(t2["bld"]), int(t2["emergency"]), t2["role"]]])
		rows.sort_custom(func(x, y): return x[0] > y[0])
		print("score ranking for free technician ", tech["name"], " (top 10 of ", rows.size(), "):")
		for r in rows.slice(0, 10):
			print("   %.1f  %s" % [r[0], r[1]])
	sim.dispose()

# ----- S12: why does a second worn structure (Storehouse 1) get no repair task while spares exist?
func _s12() -> void:
	var sim = _load()
	var sto: Dictionary = _bld(sim, "storehouse")
	var hab: Dictionary = _bld(sim, "habitat")
	var air: Dictionary = _bld(sim, "airlock")
	print("storehouse id ", sto["id"], " kind ", sto["kind"], " def ", sto["def"], " health ", sto["health"], " base ", sim.bases.base_of(int(sto["id"])))
	sto["health"] = 55.0
	hab["health"] = 55.0
	air["health"] = 55.0
	sim.run_seconds(3.0)
	for b in [sto, hab, air]:
		var src: int = sim.jobs.find_source("spare_parts", b["pos"])
		print("%s id %d health %.0f state %s: find_source=%d tasks=%s" % [b["name"], b["id"], float(b["health"]), b["state"], src, str(_tasks_for(sim, int(b["id"])))])
	var tot: Dictionary = sim.inv.totals()
	print("spare_parts totals: ", tot.get("spare_parts", {}))
	for iid in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][iid]
		if int(inv["items"].get("spare_parts", 0)) > 0:
			print("  inv ", iid, " role ", inv["role"], " items ", inv["items"].get("spare_parts"), " held_out ", inv["held_out"].get("spare_parts", 0))
	print("holds with spare_parts:")
	for hid in sim.state["holds"]:
		var h: Dictionary = sim.state["holds"][hid]
		if h["res"] == "spare_parts":
			print("   ", h)
	sim.dispose()

# ----- S13: s2 tail, with detail: after the Habitat repair, a second worn structure appears
func _s13() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	var a: Dictionary = _agent(sim, "grower")
	_clear(sim, a)
	_order(sim, a, "work_at", {"b": bid})
	var h0: float = float(hab["health"])
	for i in 400:
		sim.run_seconds(1.0)
		a["hunger"] = 5.0
		a["fatigue"] = 5.0
		if float(hab["health"]) > h0 + 1.0:
			break
	print("repaired; ", _snap(sim, a))
	var sto: Dictionary = _bld(sim, "storehouse")
	sto["health"] = 55.0
	for i in 6:
		sim.run_seconds(5.0)
		a["hunger"] = 5.0
		a["fatigue"] = 5.0
		print("  +%d s sto health %.1f state %s tasks %s find_source=%d" % [(i + 1) * 5, float(sto["health"]), sto["state"], str(_tasks_for(sim, int(sto["id"]))), sim.jobs.find_source("spare_parts", sto["pos"])])
	print("spare_parts: ", sim.inv.totals().get("spare_parts", {}))
	sim.dispose()

# ----- S14: who holds the spare parts? every repair / maintain / patch task, its owner and state; ranking for a free technician
func _s14() -> void:
	var sim = _load()
	sim.run_seconds(5.0)
	print("spare_parts: ", sim.inv.totals().get("spare_parts", {}))
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] == "repair" or t["kind"] == "maintain" or t["kind"] == "patch":
			var b: Dictionary = sim.state["buildings"].get(int(t["bld"]), {})
			var o: Dictionary = sim.state["agents"].get(int(t["owner"]), {})
			print("  %s#%d bld=%d %s (%s health %.0f) res=%s emerg=%d state=%s owner=%s picked=%s retry=%d reason=%s" % [t["kind"], tid, int(t["bld"]), b.get("name", "?"), b.get("state", "?"), float(b.get("health", 0)), t["res"], int(t["emergency"]), t["state"], String(o.get("name", "-")) + "/" + String(o.get("plan_kind", "")) + "/" + String(o.get("goal", "")), str(t["picked"]), int(t["retry"]) - int(sim.state["tick"]), t["reason"]])
	print("broken / breached / at-risk structures and whether they have a task:")
	for id in sim.state["buildings"]:
		var b2: Dictionary = sim.state["buildings"][id]
		if b2["state"] == "broken" or bool(b2.get("breach", false)) or sim.hazards.wants_maintenance(b2) or (b2["state"] == "active" and float(b2["health"]) < 70.0):
			var n := 0
			for tid in sim.state["tasks"]:
				var t2: Dictionary = sim.state["tasks"][tid]
				if int(t2["bld"]) == int(id) and (t2["kind"] == "repair" or t2["kind"] == "maintain" or t2["kind"] == "patch"):
					n += 1
			print("   %d %s state=%s health=%.0f breach=%s wants_maint=%s block='%s' tasks=%d" % [id, b2["name"], b2["state"], float(b2["health"]), str(b2.get("breach", false)), str(sim.hazards.wants_maintenance(b2)), b2["block"], n])
	sim.dispose()

# ----- S15: score ranking of every open task for 3 free technicians (where does an open, non-urgent repair rank?)
func _s15() -> void:
	var sim = _load()
	sim.run_seconds(5.0)
	var skip: Array = []
	for n in 3:
		var tech: Dictionary = _agent(sim, "technician", skip, true)
		if tech.is_empty():
			break
		skip.append(int(tech["id"]))
		var rows: Array = []
		for tid in sim.state["tasks"]:
			var t2: Dictionary = sim.state["tasks"][tid]
			if int(t2["owner"]) != -1 or t2["state"] != "open":
				continue
			if t2["role"] != "" and t2["role"] != tech["role"]:
				continue
			var b: Dictionary = sim.state["buildings"].get(int(t2["bld"]), {})
			rows.append([sim.jobs.score(t2, tech), "%s/%s #%d bld=%d %s emerg=%d bldprio=%s retry=%d" % [t2["kind"], t2["cat"], tid, int(t2["bld"]), String(b.get("name", "")), int(t2["emergency"]), str(b.get("priority", "-")), int(t2["retry"]) - int(sim.state["tick"])]])
		rows.sort_custom(func(x, y): return x[0] > y[0])
		print("technician ", tech["name"], " at ", tech["pos"], " (", rows.size(), " open tasks he may take):")
		for r in rows:
			print("   %.1f  %s" % [r[0], r[1]])
	sim.dispose()

# ----- S16: a party recruits honoured people and friends WITHOUT looking at their plan or their order (party.gd _recruit)
func _s16() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	var a: Dictionary = _agent(sim, "grower")
	var b2: Dictionary = _agent(sim, "grower", [int(a["id"])])
	var c2: Dictionary = _agent(sim, "grower", [int(a["id"]), int(b2["id"])])
	for x in [a, b2, c2]:
		_clear(sim, x)
	_order(sim, a, "work_at", {"b": bid})
	sim.run_seconds(3.0)
	print("A before the party: ", _snap(sim, a))
	var venue := -1
	var vd: Array = sim.content["society"]["celebrations"]["venue_defs"]
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "active" and vd.has(String(b["def"])) and sim.util.building_supplied(int(id)):
			venue = int(id)
			break
	var base: int = sim.bases.base_of(venue)
	var res: Dictionary = sim.party.start_party(base, venue, 2, {"kind": "manual", "who": [int(a["id"]), int(b2["id"]), int(c2["id"])], "text": "diag", "reason": "a party"}, true)
	print("start_party (auto, honouring A, B, C): ", res)
	print("A right after: ", _snap(sim, a))
	var t0: float = _ts(sim)
	var last := ""
	for i in 300:
		sim.run_seconds(1.0)
		a["hunger"] = minf(float(a["hunger"]), 20.0)
		a["fatigue"] = minf(float(a["fatigue"]), 20.0)
		var sn: String = "%s|%s" % [a["plan_kind"], a["goal"]]
		if sn != last:
			print("  +%3.0f s %s" % [_ts(sim) - t0, _snap(sim, a)])
			last = sn
		if a["plan_kind"] == "task":
			break
	sim.dispose()

# ----- S17: plan_for_task for each open repair task (technician and non-technician): ok or the reason
func _s17() -> void:
	var sim = _load()
	sim.run_seconds(5.0)
	var tech: Dictionary = _agent(sim, "technician", [], true)
	var gro: Dictionary = _agent(sim, "grower", [], true)
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] != "repair" or int(t["owner"]) != -1:
			continue
		var b: Dictionary = sim.state["buildings"][int(t["bld"])]
		var p1: Dictionary = sim.agents._plan_for_task(tech, t)
		var p2: Dictionary = sim.agents._plan_for_task(gro, t)
		print("repair#%d %s kind=%s exterior=%s: technician plan ok=%s %s | grower plan ok=%s %s | task.reason='%s'" % [tid, b["name"], b["kind"], str(b["kind"] == "exterior"), str(p1["ok"]), str(p1.get("reason", "")), str(p2["ok"]), str(p2.get("reason", "")), t["reason"]])
	sim.dispose()

# ----- S18: NO order, everybody normal, 600 s: what happens to the open repair tasks?
func _s18() -> void:
	var sim = _load()
	sim.run_seconds(2.0)
	var t0: float = _ts(sim)
	var seen := {}
	for i in 600:
		sim.run_seconds(1.0)
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if t["kind"] != "repair":
				continue
			var key: String = "%d|%s|%d" % [tid, t["state"], int(t["owner"])]
			if not seen.has(key):
				seen[key] = true
				var b: Dictionary = sim.state["buildings"].get(int(t["bld"]), {})
				var o: Dictionary = sim.state["agents"].get(int(t["owner"]), {})
				print("  +%3.0f s repair#%d %s (%s health %.0f) state=%s owner=%s %s" % [_ts(sim) - t0, tid, b.get("name", "?"), b.get("state", "?"), float(b.get("health", 0)), t["state"], o.get("name", "-"), o.get("role", "")])
	var left := 0
	for tid in sim.state["tasks"]:
		if sim.state["tasks"][tid]["kind"] == "repair":
			left += 1
	print("repair tasks left after 600 s: ", left, " | spare_parts: ", sim.inv.totals().get("spare_parts", {}), " | tasks_done repair: ", sim.state["metrics"]["tasks_done"].get("repair", 0), " maintain: ", sim.state["metrics"]["tasks_done"].get("maintain", 0))
	sim.dispose()

# ----- S19: worn MACHINE with plenty of spares (40): order work_at at 50% wear, then "Maintain now", then at 80%
func _s19() -> void:
	var sim = _load(40)
	var wear: Dictionary = sim.hazards.hs()["wear"]
	var mid := -1
	for id in wear:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if not b.is_empty() and b["state"] == "active" and sim.hazards.is_machine(b) and String(wear[id]["fault"]) == "mechanical":
			mid = int(id)
			break
	var m: Dictionary = sim.state["buildings"][mid]
	var rec: Dictionary = wear[mid]
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	rec["w"] = float(rec["fail_at"]) * 0.5
	var a: Dictionary = _agent(sim, "scientist")
	_clear(sim, a)
	_order(sim, a, "work_at", {"b": mid})
	sim.run_seconds(20.0)
	print("%s wear 50%%: wants_maintenance=%s tasks=%s | ordered scientist: %s" % [m["name"], str(sim.hazards.wants_maintenance(m)), str(_tasks_for(sim, mid)), _snap(sim, a)])
	var r: Dictionary = sim.cmds.results.get(sim.submit("maintain", {"id": mid}), {})
	sim.run_seconds(3.0)
	print("after 'Maintain now' (maint_first=%s): wants=%s tasks=%s | ordered scientist: %s" % [str(m.get("maint_first")), str(sim.hazards.wants_maintenance(m)), str(_tasks_for(sim, mid)), _snap(sim, a)])
	for i in 100:
		sim.run_seconds(1.0)
		a["hunger"] = 5.0
		a["fatigue"] = 5.0
		if a["plan_kind"] == "task":
			print("  ordered scientist takes it: ", _snap(sim, a))
			break
	sim.run_seconds(40.0)
	print("after 40 more s: wear w=%.1f maint_first=%s | %s" % [float(rec["w"]), str(m.get("maint_first")), _snap(sim, a)])
	sim.dispose()

# ----- S20: a colonist in the middle of an ordinary job gets work_at (no abort) and, for contrast, go (abort)
func _s20() -> void:
	var sim = _load()
	var hab: Dictionary = _bld(sim, "habitat")
	var bid: int = int(hab["id"])
	hab["health"] = 60.0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["role"] == "technician":
			x["jobs"] = {"repair": 0}
	sim.run_seconds(2.0)
	var picks: Array = []
	for aid in sim.state["agents"]:
		var x2: Dictionary = sim.state["agents"][aid]
		if x2["state"] == "alive" and x2["kind"] == "human" and x2["plan_kind"] == "task" and x2["role"] != "technician" and x2["where"] != "lock":
			var t: Dictionary = sim.state["tasks"].get(int(x2["task"]), {})
			if not t.is_empty() and (t["kind"] == "operate" or t["kind"] == "tend" or t["kind"] == "build"):
				picks.append(x2)
				if picks.size() >= 2:
					break
	if picks.size() < 2:
		print("no two colonists on an operate/tend/build job now")
		sim.dispose()
		return
	var w: Dictionary = picks[0]
	var g: Dictionary = picks[1]
	print("W (gets work_at): ", _snap(sim, w), " task kind ", sim.state["tasks"][int(w["task"])]["kind"])
	print("G (gets go     ): ", _snap(sim, g), " task kind ", sim.state["tasks"][int(g["task"])]["kind"])
	_order(sim, w, "work_at", {"b": bid})
	var hp: Vector2 = hab["pos"]
	_order(sim, g, "go", {"x": hp.x, "y": hp.y})
	var t0: float = _ts(sim)
	print("right after: W ", _snap(sim, w))
	print("right after: G ", _snap(sim, g))
	var lastW := ""
	for i in 240:
		sim.run_seconds(1.0)
		w["hunger"] = minf(float(w["hunger"]), 20.0)
		w["fatigue"] = minf(float(w["fatigue"]), 20.0)
		var sn: String = "%s|%s" % [w["plan_kind"], w["goal"]]
		if sn != lastW:
			print("  W +%3.0f s %s" % [_ts(sim) - t0, _snap(sim, w)])
			lastW = sn
		if w["plan_kind"] == "task" and String(w["goal"]).begins_with("Repairing"):
			break
	print("G now: ", _snap(sim, g))
	sim.dispose()

# ----- S21: why is the only spare-parts stock (ground pile 3639) never used? plan to it from a technician inside
func _s21() -> void:
	var sim = _load(0)
	sim.run_seconds(2.0)
	var pile: Dictionary = sim.state["inventories"][3639]
	print("pile 3639 pos ", pile["pos"], " items ", pile["items"], " oid ", pile["oid"], " ot ", pile["ot"])
	var seen := {}
	var n := 0
	for aid in sim.state["agents"]:
		var tech: Dictionary = sim.state["agents"][aid]
		if tech["state"] != "alive" or tech["role"] != "technician" or tech["where"] != "in" or tech["kind"] != "human":
			continue
		var to: Dictionary = sim.agents._inv_loc(3639, tech["pos"])
		var r: Dictionary = sim.nav.plan(sim.agents.loc_of(tech), to)
		var base_a: int = sim.bases.base_of_agent(tech)
		var key := "base=%d ok=%s" % [base_a, str(r["ok"])]
		if not seen.has(key):
			seen[key] = 0
		seen[key] = int(seen[key]) + 1
		if n < 3:
			n += 1
			print("  tech ", tech["name"], " base ", base_a, " bld ", tech["bld"], " to=", to, " plan ok=", r["ok"], " ", String(r.get("reason", "")), " suit_ok=", sim.agents._air_ok(tech, r["legs"], 0.0, int(to["b"]), to["p"]) if r["ok"] else "-")
	print("technicians by base and plan-to-pile result: ", seen)
	print("pile base_at: ", sim.bases.base_at(pile["pos"]), " bases: ", sim.bases.ids())
	sim.dispose()
