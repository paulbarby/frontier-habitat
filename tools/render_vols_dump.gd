extends SceneTree
## RENDER debug: rooms and corridors near a point of a save (the follow camera's wall volumes).
## godot.mjs script res://tools/render_vols_dump.gd <save> <x> <z> <reach>
var main
var n := 0
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	var a := OS.get_cmdline_user_args()
	var save: String = a[0] if a.size() > 0 else "res://content/saves/showcase_v3_late.fhsave"
	var c := Vector2(float(a[1]) if a.size() > 1 else 449.0, float(a[2]) if a.size() > 2 else 413.0)
	var reach: float = float(a[3]) if a.size() > 3 else 14.0
	main._import_bytes(FileAccess.get_file_as_bytes(save))
	var out: Array = []
	for bid in main.sim.state["buildings"]:
		var b: Dictionary = main.sim.state["buildings"][bid]
		if b["kind"] == "room":
			if (b["pos"] as Vector2).distance_to(c) < float(b["radius"]) + reach:
				out.append({"k": "room", "id": int(bid), "def": String(b["def"]), "x": b["pos"].x, "z": b["pos"].y, "r": float(b["radius"])})
		elif b["def"] == "corridor":
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(c, b["p0"], b["p1"])
			if q.distance_to(c) < reach:
				out.append({"k": "tube", "id": int(bid), "x0": b["p0"].x, "z0": b["p0"].y, "x1": b["p1"].x, "z1": b["p1"].y})
	print("VOLS " + JSON.stringify(out))
	quit(0)
	return true
