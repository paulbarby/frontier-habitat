extends SceneTree
## Critic r42 verify (PT-7), part 3: the outdoor ground piles in showcase_v5.fhsave at load and
## after 1 game day, and which atmosphere group each airlock belongs to. Read only.

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _piles(sim, label: String) -> void:
	var invs: Dictionary = sim.state["inventories"]
	for iid in invs:
		var iv: Dictionary = invs[iid]
		if String(iv.get("ot", "")) != "g":
			continue
		var tot := 0
		var items: Dictionary = iv.get("items", iv.get("stock", {}))
		print("%s PILE inv=%d oid=%s pos=%s keys=%s" % [label, int(iid), str(iv.get("oid")), str(sim.inv.position_of(int(iid))), str(iv.keys())])
		print("     contents=%s" % str(items).left(600))
	var tot_meals: int = int(sim.metrics.forecast()["meals"])
	print("%s meals(all)=%d" % [label, tot_meals])

func _initialize() -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://showcase_v5.fhsave"))
	var sim = Sim.new()
	sim.load_state(dec["state"])
	_piles(sim, "load")
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if not b["lock"].is_empty() or b["def"] == "storehouse":
			print("BLD %d %s def=%s atmo_comp=%s pos=%s" % [int(id), b["name"], b["def"], str(sim.topo.atmo_comp.get(id, "none")), str(b["pos"])])
	var hz: int = int(sim.bal["tick_hz"])
	for i in 600 * hz:
		sim.step()
	_piles(sim, "day+1")
	quit(0)
