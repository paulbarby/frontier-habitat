extends SceneTree
## Developer tool: where the mine and the refineries stand in the reference campaign, whether
## they are joined, and the open ore hauls with their reasons.
##   node tools/godot.mjs script res://tests/dev/ore_probe.gd <day>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var day: int = int(a[0]) if a.size() > 0 else 12
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(day * 6000)
	var c: Vector2 = sim.world.center
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["def"] in ["mine", "refinery", "storehouse", "lander", "airlock", "fabricator", "polymer_plant", "workshop"]:
			print("%s %d at %s (%.0f m) comp %s links %d" % [b["def"], id, str(((b["pos"] as Vector2) - c).round()), ((b["pos"] as Vector2) - c).length(),
				str(sim.topo.atmo_comp.get(id, -1)), (sim.topo.links_of.get(id, []) as Array).size()])
	var reasons := {}
	var owners := 0
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] == "haul":
			var k: String = "%s:%s:%s" % [t["res"], t["state"], t["reason"]]
			reasons[k] = int(reasons.get(k, 0)) + 1
	print(reasons)
	var roles := {}
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		if ag["state"] == "alive":
			var k2: String = "%s/%s" % [ag["role"], ag["plan_kind"]]
			roles[k2] = int(roles.get(k2, 0)) + 1
	print(roles)
	print("priority ", sim.state["policies"]["priority"])
	g.dispose()
	quit()
