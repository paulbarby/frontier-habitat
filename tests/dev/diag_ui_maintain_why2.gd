extends SceneTree
## Diagnostic (UI path): is the spare-parts pile a valid maintenance source?
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	sim.jobs._index(true)
	print("bases ", sim.bases.count(), " ids ", sim.bases.ids())
	print("src_index spare_parts: ", sim.jobs._src_index.get("spare_parts", []))
	var pile: Dictionary = sim.state["inventories"][3639]
	print("pile pos ", sim.inv.position_of(3639), " base_at pile ", sim.bases.base_at(sim.inv.position_of(3639)), " resting ", sim.jobs._source_resting(3639))
	for bid in [991, 665, 227, 108]:
		var b: Dictionary = sim.state["buildings"][bid]
		print("bld ", bid, " ", b["name"], " pos ", b["pos"], " base ", sim.bases.base_of(bid), " find_source=", sim.jobs.find_source("spare_parts", b["pos"]))
	# One real board pass: the 3 parts of the second, maintain now ordered first.
	for bid in [991, 665, 227, 108]:
		sim.submit("maintain", {"id": bid})
	sim.run_seconds(3.0)
	var n := 0
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] == "maintain":
			n += 1
			print("maintain task ", tid, " bld ", t["bld"], " state ", t["state"], " owner ", t["owner"])
	print("maintain tasks after 3 s: ", n)
	sim.dispose()
	quit(0)
