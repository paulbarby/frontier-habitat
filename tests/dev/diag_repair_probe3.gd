extends SceneTree
## Diagnostic probe (read-only): the spare-parts pile in showcase_v5 and why find_source skips it.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	sim.jobs._index(true)
	var inv: Dictionary = sim.state["inventories"][3639]
	print("pile inv 3639: ", inv)
	print("_src_index spare_parts: ", sim.jobs._src_index.get("spare_parts", "none"))
	print("_far_piles: ", sim.jobs._far_piles)
	print("unreach_src: ", sim.state.get("unreach_src", {}))
	print("suit_reach_metres ", sim.agents.suit_reach_metres(), " nearest_air_metres(pile) ", sim.agents.nearest_air_metres(inv["pos"]))
	print("base_at(pile) ", sim.bases.base_at(inv["pos"]), " bases.count ", sim.bases.count())
	for id in [108, 227, 665, 991]:
		var b: Dictionary = sim.state["buildings"][id]
		print("  bld ", id, " pos ", b["pos"], " base_at ", sim.bases.base_at(b["pos"]), " base_of ", sim.bases.base_of(id))
	sim.dispose()
	quit(0)
