extends SceneTree
## Developer tool: which v4 deposits a rover reaches from the lander, per seed.
##   node tools/godot.mjs script res://tests/dev/reach_v4.gd <seed> [seed...]
const Sim = preload("res://sim/sim.gd")

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var sim = Sim.new()
		sim.new_game(int(a), "frontier")
		var w = sim.world
		var line := "seed %s:" % a
		for d in w.deposit_sites:
			if d["kind"] in ["helium3", "deep_ice", "uranium", "thorium", "rare_earth", "exotic"]:
				var r: Dictionary = sim.nav.vehicle_path(w.center, Vector2(d["x"], d["y"]), "rover")
				line += " %s:%s" % [d["kind"], "Y" if r["ok"] else "n"]
		print(line)
		sim.dispose()
	quit(0)
