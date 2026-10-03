extends SceneTree
## Diagnostic (UI path): why does "Maintain now" (submit maintain {id}) not make a task in showcase_v5?
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_ui_maintain_why.gd
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	var wear: Dictionary = sim.hazards.hs()["wear"]
	for bid in [991, 665, 227, 108]:
		var b: Dictionary = sim.state["buildings"][bid]
		var rec: Dictionary = wear[bid]
		var item: String = sim.hazards.fault_item(String(rec["fault"]))
		print("bld %d %s fault=%s item=%s wants=%s parked=%s demolish=%s" % [bid, b["name"], rec["fault"], item, sim.hazards.wants_maintenance(b), sim.jobs._parked(b), b["demolish"]])
		var tot: Dictionary = sim.inv.totals().get(item, {})
		print("   colony total of item: ", tot)
		var src: int = sim.jobs.find_source(item, b["pos"])
		print("   find_source -> ", src, (" available=%d" % sim.inv.available(src, item)) if src != -1 else "")
		# where does the item sit?
		for iid in sim.state["inventories"]:
			var inv: Dictionary = sim.state["inventories"][iid]
			if int(inv["items"].get(item, 0)) > 0:
				print("     inv ", iid, " role=", inv["role"], " ot=", inv["ot"], " oid=", inv["oid"], " items=", inv["items"].get(item, 0), " held_out=", inv["held_out"].get(item, 0))
	# All repair/maintain/patch tasks on the board.
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] in ["maintain", "repair", "patch"]:
			print("task ", tid, " ", t["kind"], " bld ", t["bld"], " state ", t["state"], " owner ", t["owner"], " res ", t.get("res"), " src ", t.get("src"), " emerg ", t["emergency"], " reason ", t["reason"])
	# Now order Maintain now for each of the 4 worst and look 10 s later.
	for bid in [991, 665, 227, 108]:
		var cid: int = sim.submit("maintain", {"id": bid})
	sim.run_seconds(10.0)
	for tid in sim.state["tasks"]:
		var t2: Dictionary = sim.state["tasks"][tid]
		if t2["kind"] in ["maintain", "repair", "patch"]:
			print("after Maintain now x4: task ", tid, " ", t2["kind"], " bld ", t2["bld"], " state ", t2["state"], " owner ", t2["owner"], " res ", t2.get("res"), " emerg ", t2["emergency"], " reason ", t2["reason"])
	sim.dispose()
	quit(0)
