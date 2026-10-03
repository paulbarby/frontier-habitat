extends SceneTree
## Diagnostic (SIM path): why _gen_repair makes no task for a worn Habitat although spare parts exist.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_sim_c_source.gd
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(3.0)
	var invs: Dictionary = sim.state["inventories"]
	print("bases: ", sim.bases.ids(), " count ", sim.bases.count())
	for item in ["spare_parts", "electronics", "polymer"]:
		for iid in invs:
			var inv: Dictionary = invs[iid]
			var n: int = int(inv["items"].get(item, 0))
			if n <= 0:
				continue
			var ob: Dictionary = sim.state["buildings"].get(int(inv["oid"]), {}) if inv["ot"] == "b" else {}
			var base: int = sim.bases.base_of(int(inv["oid"])) if inv["ot"] == "b" else sim.bases.base_at(sim.inv.position_of(iid))
			print("  %s inv %d role=%s owner=%s %s state=%s base=%d n=%d held_out=%s" % [item, iid, inv["role"], str(inv["oid"]), String(ob.get("name", "-")), String(ob.get("state", "-")), base, n, str(inv["held_out"].get(item, 0))])
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.state["buildings"][id]
		if b["def"] == "habitat" and b["state"] == "active":
			b["health"] = 60.0
			print("Habitat ", id, " kind=", b["kind"], " base=", sim.bases.base_of(int(id)), " demolish=", b["demolish"], " state=", b["state"])
			var src: int = sim.jobs.find_source("spare_parts", b["pos"])
			print("  find_source(spare_parts) now = ", src)
			sim.jobs.tick_part(0)
			sim.jobs.tick_part(1)
			print("  after tick_part(0),(1): src=", sim.jobs.find_source("spare_parts", b["pos"]), " repair count key=", sim.jobs._count.get("repair:%d" % id, 0))
			for tid in sim.state["tasks"]:
				var t: Dictionary = sim.state["tasks"][tid]
				if int(t["bld"]) == int(id):
					print("  task ", tid, " ", t["kind"])
			break
	print("holds of spare_parts:")
	for hid in sim.state["holds"]:
		var h: Dictionary = sim.state["holds"][hid]
		if h["res"] == "spare_parts":
			print("   ", hid, " ", h)
	print("tasks that carry spare_parts:")
	for tid in sim.state["tasks"]:
		var t2: Dictionary = sim.state["tasks"][tid]
		if String(t2["res"]) == "spare_parts":
			print("   ", tid, t2["kind"], " bld ", t2["bld"], " owner ", t2["owner"])
	print("unreach_src: ", sim.state.get("unreach_src", {}))
	sim.dispose()
	quit(0)
