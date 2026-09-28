extends SceneTree
## Developer tool: corridors and structures near a point in a save (RENDER's path-check findings).
##   node tools/godot.mjs script res://tests/dev/tube_near.gd <save> <x> <y>
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(String(a[0])))["state"])
	var p := Vector2(float(a[1]), float(a[2]))
	print("tick %d, walkable here %s, corridor_r %.2f" % [int(sim.state["tick"]), str(sim.nav.is_walkable(p)), sim.corridor_r()])
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["kind"] == "link" and b["def"] == "corridor":
			var d: float = Geometry2D.get_closest_point_to_segment(p, b["p0"], b["p1"]).distance_to(p)
			if d < 12.0:
				print("corridor %d %s state %s %s-%s dist to axis %.2f" % [int(id), b["name"], b["state"], str(b["p0"]), str(b["p1"]), d])
		elif b["kind"] != "link" and (b["pos"] as Vector2).distance_to(p) < float(b["radius"]) + 12.0:
			print("%s %d %s r %.1f at %s dist %.2f" % [b["def"], int(id), b["state"], float(b["radius"]), str(b["pos"]), (b["pos"] as Vector2).distance_to(p)])
	sim.dispose()
	quit(0)
