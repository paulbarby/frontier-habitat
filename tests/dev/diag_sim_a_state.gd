extends SceneTree
## Diagnostic (read-only, SIM path): baseline of showcase_v5 for the repair-order investigation.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_sim_a_state.gd [save]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://content/saves/showcase_v5.fhsave"
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	sim.run_seconds(3.0)
	print("day ", snappedf(float(sim.state["tick"]) / 6000.0, 0.01), " night? ", sim.util.is_night(), " hazards level ", sim.hazards.level())
	print("bal repair_trigger_health=", sim.bal["repair_trigger_health"], " specialist_bonus=", sim.bal.get("specialist_bonus"), " task_backoff_seconds=", sim.bal["task_backoff_seconds"])
	print("colony priority: ", sim.state["policies"]["priority"])
	var roles := {}
	var plan_kinds := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var k: String = "%s/%s" % [a.get("kind", ""), a["role"]]
		roles[k] = int(roles.get(k, 0)) + 1
		plan_kinds[String(a["plan_kind"])] = int(plan_kinds.get(String(a["plan_kind"]), 0)) + 1
	print("roles: ", roles)
	print("plan kinds: ", plan_kinds)
	# Health below 100 (non-machines wear on the v2 health track).
	var low := 0
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "active" and float(b["health"]) < 100.0:
			low += 1
			if low <= 12:
				print("  health %.1f bld %d %s def=%s machine=%s prio=%d" % [float(b["health"]), id, b["name"], b["def"], str(sim.hazards.is_machine(b)), int(b["priority"])])
	print("buildings with health < 100: ", low)
	var tk := {}
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		var k2: String = "%s/%s/%s/role=%s" % [t["kind"], t["cat"], "owned" if int(t["owner"]) != -1 else "free", t["role"]]
		tk[k2] = int(tk.get(k2, 0)) + 1
	print("tasks: ", tk)
	var tot: Dictionary = sim.inv.totals()
	print("spare_parts: ", tot.get("spare_parts", {}))
	sim.dispose()
	quit(0)
