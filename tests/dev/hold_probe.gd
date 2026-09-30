extends SceneTree
## Developer tool: showcase_v4 at a day: the holds on dishes and meals, their owner tasks, and
## the kitchens (state, block, recipe) and why nobody eats.
##   node tools/godot.mjs script res://tests/dev/hold_probe.gd [day]
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var day: float = float(a[0]) if a.size() > 0 else 14.0
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	sim.run_seconds(day * 600.0)
	for hid in sim.state["holds"]:
		var h: Dictionary = sim.state["holds"][hid]
		if sim.items.is_dish(h["res"]) or h["res"] == "meals":
			var t: Dictionary = sim.state["tasks"].get(int(h["owner"]), {})
			print("hold %s: inv %s %s x%d %s owner task %s" % [str(hid), str(h["inv"]), h["res"], int(h["qty"]), h["dir"], str(t.duplicate()) if not t.is_empty() else "(no task %d)" % int(h["owner"])])
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if ["kitchen", "cantina", "storehouse", "cold_storage"].has(String(b["def"])):
			print("%s %d %s block '%s' base %d recipe %s inv %s" % [b["def"], int(id), b["state"], b.get("block", ""), sim.bases.base_of(int(id)), str(b.get("recipe", b.get("dishes", ""))), str(sim.inv.get_inv(int(b.get("inv_out", b.get("inv", -1)))).get("items", {}) if b.has("inv_out") or b.has("inv") else "")])
	var x: Dictionary = {}
	for aid in sim.state["agents"]:
		var p: Dictionary = sim.state["agents"][aid]
		if p["state"] == "alive" and float(p["hunger"]) > 90.0:
			x = p
			break
	if not x.is_empty():
		print("hungry %d %s at base %d bld %d goal %s" % [int(x["id"]), x["name"], sim.bases.base_of_agent(x), int(x["bld"]), x["goal"]])
		print("try_eat: ", sim.agents._try_eat(x), " goal now ", x["goal"])
	sim.dispose()
	quit(0)
