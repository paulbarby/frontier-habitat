extends SceneTree
## Developer tool: a purchase in showcase_v31 and where the goods go.
const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v31.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	var row: Dictionary = {}
	for r in sim.traffic.ships():
		if r["kind"] == "trader" and r["phase"] == "landed":
			row = r
	print("trader t_s %.0f" % float(row["t_s"]))
	sim.submit("trade", {"id": int(row["id"]), "buy": {"composite": 4}})
	sim.step()
	for s in 20:
		sim.run_seconds(45.0)
		var line := "t+%d:" % ((s + 1) * 45)
		for inv_id in sim.state["inventories"]:
			var inv: Dictionary = sim.state["inventories"][inv_id]
			var n: int = int(inv["items"].get("composite", 0))
			if n > 0:
				line += " %s/%s:%d(held %d)" % [inv["role"], str(inv["oid"]), n, int(inv["held_out"].get("composite", 0))]
		for tid in sim.state["tasks"]:
			var tk: Dictionary = sim.state["tasks"][tid]
			if String(tk.get("res", "")) == "composite":
				line += " task %s %s owner %d reason %s;" % [tk["kind"], tk["state"], int(tk["owner"]), str(tk.get("reason", ""))]
		print(line)
	quit(0)
