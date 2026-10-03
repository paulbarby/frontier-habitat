extends SceneTree
## Diagnostic probe (read-only, ORCH): does an order that has no work to do (work_at on a structure with no task,
## or a blocked repair order) make the colonist start and drop ordinary plans every second (orders.drive)?
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_orch_thrash.gd [scenario] [seconds]
## scenario: control | work_at_idle | repair_blocked
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scen: String = args[0] if args.size() > 0 else "work_at_idle"
	var secs: float = float(args[1]) if args.size() > 1 else 60.0
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	var subj: Dictionary = {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["role"] == "technician" and a["where"] == "in" and not a.has("v5_nowork") and not a.has("order") and a["kind"] != "child" and not sim.workq.is_head(a):
			subj = a
			break
	if subj.is_empty():
		print("no subject")
		quit(1)
		return
	# A structure with no task and no wear need (work_at has nothing to take there).
	var target := -1
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] != "active" or b["kind"] == "link" or b["kind"] == "special":
			continue
		if sim.hazards.is_machine(b) or float(b["health"]) < 99.5:
			continue
		var has_task := false
		for tid in sim.state["tasks"]:
			if int(sim.state["tasks"][tid]["bld"]) == id:
				has_task = true
		if not has_task:
			target = id
			break
	var worn := -1
	var wear: Dictionary = sim.hazards.hs()["wear"]
	var best := 0.0
	for id in wear:
		var b2: Dictionary = sim.state["buildings"].get(id, {})
		if b2.is_empty() or b2["state"] != "active":
			continue
		var r: float = float(wear[id]["w"]) / maxf(0.001, float(wear[id]["fail_at"]))
		if r > best:
			best = r
			worn = id
	print("scenario ", scen, " subject ", subj["id"], " ", subj["name"], " target(no task) ", target, " worn machine ", worn, " spare parts ", sim.inv.totals().get("spare_parts", {}))
	sim.agents.abort_plan(subj, "diag")
	subj["fatigue"] = 70.0
	subj["hunger"] = 0.0
	subj["thirst"] = 0.0
	var res := {}
	if scen == "parts_held":
		var store := -1
		for id3 in sim.state["buildings"]:
			var b3: Dictionary = sim.state["buildings"][id3]
			if String(b3["name"]) == "Storehouse 1":
				store = int(b3["inv_out"]) if int(b3["inv_out"]) != -1 else int(b3["inv_in"])
		sim.inv.add_new_forced(store, "spare_parts", 6, "diag")
		sim.run_seconds(3.0)
		var reps := 0
		for tid4 in sim.state["tasks"]:
			if sim.state["tasks"][tid4]["kind"] == "repair":
				reps += 1
		print("after stocking: spare_parts totals ", sim.inv.totals().get("spare_parts", {}), " repair tasks ", reps)
		var low := -1
		var lowh := 100.0
		for id5 in sim.state["buildings"]:
			var b5: Dictionary = sim.state["buildings"][id5]
			if b5["state"] != "active" or b5["kind"] == "link" or b5["kind"] == "special":
				continue
			var has_rep := false
			for tid5 in sim.state["tasks"]:
				var t5: Dictionary = sim.state["tasks"][tid5]
				if int(t5["bld"]) == id5 and t5["kind"] == "repair":
					has_rep = true
			if not has_rep and float(b5["health"]) < lowh:
				lowh = float(b5["health"])
				low = id5
		print("order target (health ", lowh, ", no repair task): ", low, " ", sim.state["buildings"][low]["name"])
		worn = low
		res = sim.orders.cmd_order({"agents": [subj["id"]], "kind": "repair", "b": worn, "direct": true})
	match scen:
		"work_at_idle":
			res = sim.orders.cmd_order({"agents": [subj["id"]], "kind": "work_at", "b": target, "direct": true})
		"repair_blocked":
			res = sim.orders.cmd_order({"agents": [subj["id"]], "kind": "repair", "b": worn, "direct": true})
	print("order result: ", res)
	var changes := 0
	var last := ""
	var sleep_ticks := 0
	var plan_ticks := {}
	var ticks: int = int(secs * 10.0)
	var f0: float = float(subj["fatigue"])
	for i in range(ticks):
		sim.step()
		var key := "%s|%s" % [subj["plan_kind"], subj["goal"]]
		if key != last:
			changes += 1
			if changes <= 25:
				var ob: String = "none"
				if subj.has("order"):
					ob = str((subj["order"] as Dictionary).get("blocked", "-"))
				print("  t+%.1f s  plan_kind=%s goal='%s' fatigue=%.1f order_blocked=%s" % [float(i) / 10.0, subj["plan_kind"], subj["goal"], float(subj["fatigue"]), ob])
			last = key
		plan_ticks[String(subj["plan_kind"])] = int(plan_ticks.get(String(subj["plan_kind"]), 0)) + 1
		if bool(subj.get("sleeping", false)):
			sleep_ticks += 1
	print("RESULT ", scen, ": plan changes=", changes, " in ", secs, " s; sleeping seconds=", snappedf(float(sleep_ticks) / 10.0, 0.1), " fatigue ", snappedf(f0, 0.1), " -> ", snappedf(float(subj["fatigue"]), 0.1), " plan_kind ticks=", plan_ticks)
	sim.dispose()
	quit(0)
