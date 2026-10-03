extends SceneTree
## Diagnostic (UI path): end to end, with spare parts made reachable (test set-up: the 4 stuck
## spare parts of showcase_v5 are destroyed and 20 are added to the nearest store).
## S1: the "Maintain now" payload. S2: the Orders window "Work at" payload for technicians in
## different states. S3: "Work at" on a machine that is not near failure. S4: a broken machine.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_ui_orders_e2e.gd
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const SAVE := "res://content/saves/showcase_v5.fhsave"

func _fresh():
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(SAVE))["state"])
	sim.run_seconds(5.0)
	if sim.state["inventories"].has(3639):
		sim.inv.destroy(3639, "spare_parts", 4, "diag")
	var ref: Vector2 = sim.state["buildings"][991]["pos"]
	var best := -1
	var bd := 1e18
	for iid in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][iid]
		if inv["role"] == "store" and inv["ot"] == "b" and sim.state["buildings"].has(inv["oid"]) and sim.state["buildings"][inv["oid"]]["state"] == "active":
			var d: float = sim.inv.position_of(iid).distance_to(ref)
			if d < bd and sim.inv.free_space(iid) >= 20:
				bd = d
				best = iid
	sim.inv.add_new(best, "spare_parts", 20, "diag")
	print("   (test set-up: 20 spare parts added to store inv ", best, " of building ", sim.state["inventories"][best]["oid"], " ", sim.state["buildings"][sim.state["inventories"][best]["oid"]]["name"], ", ", snappedf(bd, 0.1), " m from Refinery 3)")
	return sim

func _maint_done(sim, bid: int) -> int:
	return int(sim.hazards.hs()["wear"][bid]["n"])

func _techs(sim) -> Array:
	var out: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] != "visitor" and String(a["role"]) == "technician":
			out.append(int(aid))
	return out

func _watch(sim, label: String, bid: int, aid: int, secs: int) -> void:
	var a: Dictionary = sim.state["agents"][aid]
	var started := -1
	var last := ""
	for s in secs:
		sim.run_seconds(1.0)
		var line := "plan_kind=%s goal=%s order=%s n=%d" % [a["plan_kind"], a["goal"], a.has("order"), _maint_done(sim, bid)]
		if line != last:
			print("   t+%3d s  %s" % [s + 1, line])
			last = line
		if _maint_done(sim, bid) > 0:
			print("   -> maintenance DONE at t+%d s" % (s + 1))
			return
	print("   -> maintenance NOT done within ", secs, " s")

func _init() -> void:
	print("== S1. Maintain now (payload {id}) on Refinery 3, parts available, nobody ordered")
	var sim = _fresh()
	var cid: int = sim.submit("maintain", {"id": 991})
	var techs: Array = _techs(sim)
	print("   technicians: ", techs.size(), " plan kinds: ", techs.map(func(i): return sim.state["agents"][i]["plan_kind"]))
	var last := ""
	var t_task := -1
	var done_at := -1
	for s in 600:
		sim.run_seconds(1.0)
		if t_task < 0:
			for tid in sim.state["tasks"]:
				var t: Dictionary = sim.state["tasks"][tid]
				if t["kind"] == "maintain" and int(t["bld"]) == 991:
					t_task = s + 1
					var o: Dictionary = sim.state["agents"].get(int(t["owner"]), {})
					print("   maintain task exists at t+", t_task, " s, state=", t["state"], " emergency=", t["emergency"], " owner=", t["owner"], " ", o.get("name", "-"), " ", o.get("plan_kind", ""))
		if _maint_done(sim, 991) > 0 and done_at < 0:
			done_at = s + 1
			break
	print("   result: ", sim.cmds.results.get(cid), "; maintenance done at t+", done_at, " s (-1 = not within 600 s)")
	sim.dispose()
	# S2: each technician, one at a time, gets the Work at order for Refinery 3.
	print("\n== S2. Orders window Work at Refinery 3 (payload {agents,kind:work_at,b}) for each technician, parts available")
	var probe = _fresh()
	var tl: Array = _techs(probe)
	probe.dispose()
	for aid in tl:
		var s2 = _fresh()
		var a: Dictionary = s2.state["agents"][aid]
		print(" technician ", aid, " ", a["name"], " plan_kind=", a["plan_kind"], " goal=", a["goal"], " where=", a["where"], " fatigue=", snappedf(float(a["fatigue"]), 1.0), " hunger=", snappedf(float(a["hunger"]), 1.0))
		var chk: Dictionary = s2.orders.check(a, {"agents": [aid], "kind": "work_at", "b": 991})
		var c2: int = s2.submit("order", {"agents": [aid], "kind": "work_at", "b": 991})
		s2.run_seconds(1.0)
		print("   check ok=", chk["ok"], " result=", s2.cmds.results.get(c2).get("code"), " goal-now=", a["goal"], " plan_kind-now=", a["plan_kind"])
		_watch(s2, "S2", 991, aid, 240)
		s2.dispose()
	# S3: Work at a machine that is NOT near failure (wear ratio low).
	print("\n== S3. Work at Water Extractor 1 (id 104, ratio 0.2: no maintain task exists) for a technician")
	var s3 = _fresh()
	var ta: int = _techs(s3)[0]
	var a3: Dictionary = s3.state["agents"][ta]
	var c3: int = s3.submit("order", {"agents": [ta], "kind": "work_at", "b": 104})
	s3.run_seconds(1.0)
	print("   result=", s3.cmds.results.get(c3).get("code"), " wants_maintenance=", s3.hazards.wants_maintenance(s3.state["buildings"][104]))
	var last3 := ""
	for s in 240:
		s3.run_seconds(1.0)
		var line3 := "plan_kind=%s goal=%s order=%s" % [a3["plan_kind"], a3["goal"], a3.has("order")]
		if line3 != last3:
			print("   t+%3d s  %s" % [s + 1, line3])
			last3 = line3
	s3.dispose()
	# S4: a broken machine: wear forced to the failure point; then Work at.
	print("\n== S4. Broken machine (Mine 1 forced to failure), parts available")
	var s4 = _fresh()
	var rec: Dictionary = s4.hazards.hs()["wear"][665]
	rec["w"] = float(rec["fail_at"]) + 1.0
	s4.run_seconds(2.0)
	print("   Mine 1 state=", s4.state["buildings"][665]["state"], " fault=", rec["fault"])
	var t4: Array = _techs(s4)
	var last4 := ""
	var rep_at := -1
	for s in 400:
		s4.run_seconds(1.0)
		var tks: Array = []
		for tid in s4.state["tasks"]:
			var t: Dictionary = s4.state["tasks"][tid]
			if t["kind"] == "repair" and int(t["bld"]) == 665:
				tks.append("%s/owner%s" % [t["state"], t["owner"]])
		var line4 := "state=%s repair tasks=%s" % [s4.state["buildings"][665]["state"], str(tks)]
		if line4 != last4:
			print("   t+%3d s  %s" % [s + 1, line4])
			last4 = line4
		if s4.state["buildings"][665]["state"] == "active":
			rep_at = s + 1
			break
	print("   repaired by itself (no order) at t+", rep_at, " s (-1 = not within 400 s)")
	s4.dispose()
	quit(0)
