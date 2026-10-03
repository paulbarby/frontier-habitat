extends SceneTree
## Diagnostic probe (read-only): is there a spare-parts producer in showcase_v5, and what is it doing?
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	var defs := {}
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		var d: Dictionary = sim.bdef(b["def"])
		var recs: Array = d.get("recipes", [d.get("recipe", "")])
		if recs.has("spares") or recs.has("spares_alloy") or b["def"] == "workshop" or b["def"] == "parts_works":
			print("producer bld %d %s def=%s state=%s enabled=%s powered=%s block='%s' recipe=%s batch=%s" % [id, b["name"], b["def"], b["state"], str(b.get("enabled")), str(b.get("powered")), b["block"], str(b.get("recipe", "")), str(b["batch"]).substr(0, 100)])
		defs[b["def"]] = int(defs.get(b["def"], 0)) + 1
	print("defs: ", defs)
	print("research done ind_2: ", sim.research.is_done("ind_2"))
	sim.dispose()
	quit(0)
