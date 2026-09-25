extends SceneTree
## Developer tool: state, block and delivered materials of one structure over time.
##   node tools/godot.mjs script res://tests/dev/site_watch.gd <name_with_underscores> <from> <to> <every>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var who: String = String(a[0]).replace("_", " ")
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	g.run_to_tick(int(a[1]))
	while g.tick() < int(a[2]):
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["name"] == who:
				var near: Dictionary = {}
				if b["kind"] == "link":
					var pts: Array = sim.nav.access_points(b)
					if not pts.is_empty():
						near = sim.nav.nearest_supplied_lock(pts[0])
				print("t=%d %s block '%s' site %s range_wait %d unreach %d walk %d back %s" % [g.tick(), b["state"], b["block"], str(sim.inv.get_inv(int(b["inv_site"])).get("items", {})) if int(b.get("inv_site", -1)) != -1 else "-", int(b.get("range_wait", -1)) - g.tick(), int(b["unreach_rev"]), int(sim.state["rev"]["walk"]), str(near)])
		g.run(int(a[3]))
	quit(0)
