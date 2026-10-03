extends SceneTree
## Diagnostic probe (read-only): why no maintain task exists for worn machines in showcase_v5.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_repair_probe2.gd [warm_seconds]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var warm: float = float(args[0]) if args.size() > 0 else 5.0
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(warm)
	var invs: Dictionary = sim.state["inventories"]
	print("--- where spare_parts / electronics / polymer sit (role, owner type/id, base, items, held_out)")
	for item in ["spare_parts", "electronics", "polymer"]:
		for iid in invs:
			var inv: Dictionary = invs[iid]
			var n: int = int(inv["items"].get(item, 0))
			if n <= 0:
				continue
			var base := -2
			if inv["ot"] == "b":
				base = sim.bases.base_of(int(inv["oid"]))
			else:
				base = sim.bases.base_at(sim.inv.position_of(iid))
			var ob: Dictionary = sim.state["buildings"].get(int(inv["oid"]), {}) if inv["ot"] == "b" else {}
			print("  %s inv %d role=%s ot=%s oid=%s (%s %s) base=%d n=%d held_out=%s pos=%s" % [item, iid, inv["role"], inv["ot"], str(inv["oid"]), String(ob.get("name", "-")), String(ob.get("state", "-")), base, n, str(inv["held_out"].get(item, 0)), str(sim.inv.position_of(iid))])
	sim.jobs._index(true)
	print("--- worn machines: base, find_source, available (after _index(true))")
	var wear: Dictionary = sim.hazards.hs()["wear"]
	for id in wear:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty() or not sim.hazards.wants_maintenance(b):
			continue
		var item: String = sim.hazards.fault_item(String(wear[id]["fault"]))
		var src: int = sim.jobs.find_source(item, b["pos"])
		print("  bld %d %s base=%d item=%s find_source=%d available=%s" % [id, b["name"], sim.bases.base_of(int(id)), item, src, str(sim.inv.available(src, item)) if src != -1 else "n/a"])
	print("--- direct _gen_hazard_work() now")
	var before: int = sim.state["tasks"].size()
	sim.jobs._gen_hazard_work()
	print("  tasks before ", before, " after ", sim.state["tasks"].size())
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] == "maintain":
			print("  new maintain task ", t["id"], " bld ", t["bld"], " src ", t["src"], " res ", t["res"])
	for id in wear:
		var mb: Dictionary = sim.state["buildings"].get(id, {})
		if not mb.is_empty() and sim.hazards.wants_maintenance(mb):
			print("  bld ", id, " parked=", sim.jobs._parked(mb), " demolish=", mb["demolish"], " count maintain=", sim.jobs._count.get("maintain:%d" % id, 0))
	print("--- generator reserves: spare_parts in-flight holds")
	for hid in sim.state["holds"]:
		var h: Dictionary = sim.state["holds"][hid]
		if h["res"] == "spare_parts":
			print("  hold ", hid, " ", h)
	print("--- does anything make spare_parts? recipes:")
	for rid in sim.content["recipes"]:
		var r: Dictionary = sim.content["recipes"][rid]
		if JSON.stringify(r).find("spare_parts") != -1:
			print("  recipe ", rid, " ", JSON.stringify(r).substr(0, 260))
	sim.dispose()
	quit(0)
