extends SceneTree
## Diagnostic (SIM path): the spare-parts chain in showcase_v5 - who makes them, where the 4 on the ground are.
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_sim_e_spares.gd
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(3.0)
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.state["buildings"][id]
		if b["def"] == "workshop" or b["def"] == "airlock":
			var rec: Dictionary = sim.prod.recipe_of(b) if b["state"] == "active" else {}
			print("%s %d %s state=%s base=%d recipe=%s enabled=%s powered=%s block='%s' pos=%s" % [b["def"], id, b["name"], b["state"], sim.bases.base_of(int(id)), String(b.get("recipe", "")), str(b["enabled"]), str(b["powered"]), b["block"], str(b["pos"])])
	var pile: Dictionary = sim.state["inventories"][3639]
	print("pile 3639: pos ", pile["pos"], " items ", pile["items"], " fragment=", pile.get("fragment", false), " base_at=", sim.bases.base_at(pile["pos"]), " nearest_air_m=", sim.agents.nearest_air_metres(pile["pos"]), " suit_reach=", sim.agents.suit_reach_metres())
	var pile2: Dictionary = sim.state["inventories"].get(3278, {})
	print("pile 3278: ", pile2.get("pos"), " items ", pile2.get("items"))
	print("unreach_src: ", sim.state.get("unreach_src", {}), " now tick ", sim.state["tick"])
	# how often spare parts were made / consumed
	var st: Dictionary = sim.state.get("stats", {})
	print("stats consumed/made keys sample: ", st.keys().slice(0, 12))
	sim.dispose()
	quit(0)
