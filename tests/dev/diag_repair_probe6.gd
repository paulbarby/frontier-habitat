extends SceneTree
## Diagnostic probe: who reserves spare parts the moment they appear in a store?
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(5.0)
	print("before: holds on spare_parts: ", _holds(sim))
	sim.inv.add_new_forced(342, "spare_parts", 6, "diag")
	for s in 3:
		sim.run_seconds(1.0)
		print("t+", s + 1, " holds on spare_parts: ", _holds(sim))
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["res"] == "spare_parts":
			var dst_owner := ""
			if int(t["dst"]) != -1 and sim.state["inventories"].has(int(t["dst"])):
				var di: Dictionary = sim.state["inventories"][int(t["dst"])]
				var ob: Dictionary = sim.state["buildings"].get(int(di["oid"]), {})
				dst_owner = "%s(%s) role=%s state=%s" % [ob.get("name", "?"), ob.get("def", "?"), di["role"], ob.get("state", "?")]
			print("  task %d kind=%s cat=%s state=%s owner=%d bld=%d('%s') qty=%d emerg=%d dst=%d -> %s" % [tid, t["kind"], t["cat"], t["state"], int(t["owner"]), int(t["bld"]), sim.state["buildings"].get(int(t["bld"]), {}).get("name", "-"), int(t["qty"]), int(t["emergency"]), int(t["dst"]), dst_owner])
	sim.dispose()
	quit(0)
func _holds(sim) -> Array:
	var out: Array = []
	for hid in sim.state["holds"]:
		var h: Dictionary = sim.state["holds"][hid]
		if h["res"] == "spare_parts":
			out.append("hold %d inv %d %s qty %d owner(task) %d" % [hid, int(h["inv"]), h["dir"], int(h["qty"]), int(h["owner"])])
	return out
