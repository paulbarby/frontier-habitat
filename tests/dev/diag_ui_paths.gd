extends SceneTree
## Diagnostic (UI path, read-only on game files): sends exactly the payloads the UI sends for
## "Maintain now" (inspector + dashboard: submit("maintain", {id})) and for the Orders window
## "Work at..." (v4_data._order_payload -> {"agents":[id], "kind":"work_at", "b": id}), then
## shows what the sim does with them.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_ui_paths.gd [save]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

var sim

func _load(path: String):
	var s = Sim.new()
	s.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	return s

func _res(cid: int) -> String:
	return str(sim.cmds.results.get(cid, "(no result yet)"))

func _tasks_for(bid: int) -> Array:
	var out: Array = []
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if int(t["bld"]) == bid:
			out.append("%s/%s/owner=%s/emerg=%s/res=%s" % [t["kind"], t["state"], t["owner"], t["emergency"], t.get("res", "")])
	return out

func _wear(bid: int) -> String:
	var r: Dictionary = sim.hazards.hs()["wear"].get(bid, {})
	if r.is_empty():
		return "(no wear record)"
	return "w=%.1f fail_at=%.1f n=%d broken=%s" % [float(r["w"]), float(r["fail_at"]), int(r["n"]), r["broken"]]

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://content/saves/showcase_v5.fhsave"
	sim = _load(path)
	sim.run_seconds(5.0)
	print("== UI path probe, save ", path, " tick ", sim.state["tick"])
	var tot: Dictionary = sim.inv.totals()
	print("stock: spare_parts=", tot.get("spare_parts", {}).get("total", 0), " electronics=", tot.get("electronics", {}).get("total", 0), " polymer=", tot.get("polymer", {}).get("total", 0))
	# Pick machines with a wear record, worst first.
	var rows: Array = []
	for id in sim.hazards.hs()["wear"]:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty():
			continue
		var r: Dictionary = sim.hazards.hs()["wear"][id]
		rows.append([float(r["w"]) / maxf(0.001, float(r["fail_at"])), int(id), String(b["name"]), String(b["state"])])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	for r in rows.slice(0, 6):
		print("  machine %d %s state=%s ratio=%.2f" % [r[1], r[2], r[3], r[0]])
	if rows.is_empty():
		print("no wear records")
		sim.dispose()
		quit(0)
		return
	# --- A. "Maintain now" on the worst machine (inspector / dashboard button).
	var worn: Array = rows[0]
	var wid: int = worn[1]
	print("\n-- A. Maintain now on ", worn[2], " (id ", wid, ", ratio ", snappedf(worn[0], 0.01), ")")
	print("   before: ", _wear(wid), " maint_first=", sim.state["buildings"][wid].get("maint_first", false), " tasks=", _tasks_for(wid))
	var cid: int = sim.submit("maintain", {"id": wid})
	sim.run_seconds(2.0)
	print("   command result: ", _res(cid))
	print("   after 2 s: maint_first=", sim.state["buildings"][wid].get("maint_first", false), " tasks=", _tasks_for(wid))
	for k in 6:
		sim.run_seconds(30.0)
		print("   +%d s: %s state=%s tasks=%s" % [(k + 1) * 30 + 2, _wear(wid), sim.state["buildings"][wid]["state"], _tasks_for(wid)])
	# --- B. "Maintain now" on a low-wear machine (button still shows when the wear record exists).
	if rows.size() > 2:
		var low: Array = rows[rows.size() - 1]
		var lid: int = low[1]
		print("\n-- B. Maintain now on lowest-wear machine ", low[2], " (id ", lid, ", ratio ", snappedf(low[0], 0.01), ")")
		var cid2: int = sim.submit("maintain", {"id": lid})
		sim.run_seconds(2.0)
		print("   command result: ", _res(cid2), " maint_first=", sim.state["buildings"][lid].get("maint_first", false), " wants_maintenance=", sim.hazards.wants_maintenance(sim.state["buildings"][lid]), " tasks=", _tasks_for(lid))
	# --- C. Orders window: Work at... a worn machine, for a technician and for a non-technician.
	var sim2 = _load(path)
	sim = sim2
	sim.run_seconds(5.0)
	rows = []
	for id in sim.hazards.hs()["wear"]:
		var b2: Dictionary = sim.state["buildings"].get(id, {})
		if b2.is_empty() or String(b2["state"]) != "active":
			continue
		var r2: Dictionary = sim.hazards.hs()["wear"][id]
		rows.append([float(r2["w"]) / maxf(0.001, float(r2["fail_at"])), int(id), String(b2["name"])])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	var target: Array = rows[0]
	var tid_b: int = target[1]
	print("\n-- C. Orders window Work at on ", target[2], " (id ", tid_b, ", ratio ", snappedf(target[0], 0.01), ", wants_maintenance=", sim.hazards.wants_maintenance(sim.state["buildings"][tid_b]), ")")
	var tech := -1
	var other := -1
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["kind"] == "visitor":
			continue
		if String(a["role"]) == "technician" and tech == -1:
			tech = int(aid)
		elif String(a["role"]) != "technician" and String(a["role"]) != "security" and other == -1:
			other = int(aid)
	for who in [tech, other]:
		if who == -1:
			continue
		var a2: Dictionary = sim.state["agents"][who]
		var pay := {"agents": [who], "kind": "work_at", "b": tid_b}
		var chk: Dictionary = sim.orders.check(a2, pay)
		print("   colonist ", who, " ", a2["name"], " role=", a2["role"], " goal-before=", a2["goal"], " check=", chk)
		var cid3: int = sim.submit("order", pay)
		sim.run_seconds(2.0)
		print("   command result: ", _res(cid3), " order=", a2.get("order", "none"))
		for k in 4:
			sim.run_seconds(30.0)
			print("   +%d s: goal=%s plan_kind=%s where=%s order=%s %s tasks=%s" % [(k + 1) * 30 + 2, a2["goal"], a2["plan_kind"], a2["where"], a2.has("order"), _wear(tid_b), _tasks_for(tid_b)])
	sim.dispose()
	quit(0)
