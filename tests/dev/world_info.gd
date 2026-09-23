extends SceneTree
## Developer tool: where the Meridian, the deposits and the rocks near the base are.
##   node tools/godot.mjs script res://tests/dev/world_info.gd

const Sim = preload("res://sim/sim.gd")

func _init() -> void:
	for s in [1001, 1002, 1003, 1004, 1005]:
		var sim = Sim.new()
		sim.new_game(s)
		var c: Vector2 = sim.world.center
		var ship: Dictionary = sim.ship.record()
		var rel: Vector2 = (ship["pos"] as Vector2) - c
		print("seed %d: ship at (%.1f, %.1f) rot %.0f deg, dist %.1f, %d sites" % [s, rel.x, rel.y, rad_to_deg(float(ship["rot"])), rel.length(), sim.world.meridian_sites.size()])
		for d in sim.state["deposits"]:
			var dp: Vector2 = Vector2(d["x"], d["y"]) - c
			if dp.length() < 90.0:
				print("   deposit (%.1f, %.1f) r %.1f" % [dp.x, dp.y, float(d["r"])])
		var near: Array = []
		for r in sim.world.rocks:
			var rp: Vector2 = Vector2(r["x"], r["y"]) - c
			if rp.length() < 80.0:
				near.append("(%.0f,%.0f)" % [rp.x, rp.y])
		print("   rocks within 80 m: ", " ".join(near))
		sim.dispose()
	quit(0)
