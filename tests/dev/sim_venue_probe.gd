extends SceneTree
## SIM probe: who relaxes where once a shop is open (v5 venues).
const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	sim.state["flags"]["unlock_all"] = true
	sim.run_seconds(5.0)
	var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
	var shop: Dictionary = H.attach(sim, "retail", lander, 1)
	H.attach_power(sim, lander)
	var store: int = int(sim.state["buildings"][int(sim.state["lander_id"])]["inv_out"])
	for item in ["snacks", "clothing", "gifts", "gadgets", "luxury_goods"]:
		sim.inv.add_new_forced(store, item, 12, "scenario")
	var rec := {}
	var venues := 0
	for s in 6000:
		sim.step()
		for a in sim.state["agents"].values():
			if a["state"] == "alive" and String(a.get("plan_kind", "")) == "rec" and sim.agents._step_op(a) == "rec":
				var nm: String = String(sim.state["buildings"].get(int(a["bld"]), {}).get("def", "?")) + ":" + String(a.get("venue", "-"))
				rec[nm] = int(rec.get(nm, 0)) + 1
		if s % 1000 == 0:
			print("t %d open %s why %s stock %s rec %s" % [s, str(sim.leisure.is_open(shop, "shop")), sim.leisure.why_closed(shop, "shop"), str(sim.inv.get_inv(int(shop["inv_in"]))["items"]), str(rec)])
	quit(0)
