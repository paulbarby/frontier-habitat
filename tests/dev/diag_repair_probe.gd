extends SceneTree
## Diagnostic probe (read-only): what the showcase_v5 save holds for a repair-order repro.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_repair_probe.gd [save] [warm_seconds]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://content/saves/showcase_v5.fhsave"
	var warm: float = float(args[1]) if args.size() > 1 else 5.0
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(path))["state"])
	sim.run_seconds(warm)
	print("tick ", sim.state["tick"], " day ", snappedf(float(sim.state["tick"]) / 6000.0, 0.01), " hazards setting ", sim.hazards.setting(), " level ", sim.hazards.level())
	print("priority policy: ", sim.state["policies"]["priority"])
	var wear: Dictionary = sim.hazards.hs()["wear"]
	print("wear records: ", wear.size())
	var rows: Array = []
	for id in wear:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty():
			continue
		var r: Dictionary = wear[id]
		rows.append([float(r["w"]) / maxf(0.001, float(r["fail_at"])), id, b["name"], b["state"], snappedf(float(r["w"]), 0.1), float(r["fail_at"]), r["fault"], bool(b.get("maint_first", false)), bool(sim.hazards.wants_maintenance(b))])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	for r in rows.slice(0, 14):
		print("  wear ratio %.2f bld %d %s state=%s w=%s fail_at=%s fault=%s maint_first=%s wants_maint=%s" % r)
	print("risk_frac ", sim.hazards.risk_frac())
	# Tasks on the board by kind / state
	var kinds := {}
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		var k: String = "%s/%s/%s" % [t["kind"], t["state"], "owned" if int(t["owner"]) != -1 else "free"]
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("tasks: ", kinds)
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] == "maintain" or t["kind"] == "repair":
			print("  task ", tid, " ", t["kind"], " bld ", t["bld"], " state ", t["state"], " owner ", t["owner"], " res ", t["res"], " src ", t["src"], " emergency ", t["emergency"], " reason ", t["reason"], " retry ", t["retry"])
	var tot: Dictionary = sim.inv.totals()
	print("spare_parts total: ", tot.get("spare_parts", {}), " electronics ", tot.get("electronics", {}), " polymer ", tot.get("polymer", {}))
	# colonists
	var plan_kinds := {}
	var roles := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var k2: String = "%s/%s" % [a.get("kind", ""), a["role"]]
		roles[k2] = int(roles.get(k2, 0)) + 1
		var pk: String = "%s" % a["plan_kind"]
		plan_kinds[pk] = int(plan_kinds.get(pk, 0)) + 1
	print("roles: ", roles)
	print("plan kinds now: ", plan_kinds)
	print("bases: ", sim.bases.ids())
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a["role"]) == "technician":
			print("  tech ", aid, " ", a["name"], " where=", a["where"], " bld=", a["bld"], " plan_kind=", a["plan_kind"], " goal=", a["goal"], " nowork=", a.has("v5_nowork"))
	sim.dispose()
	quit(0)
