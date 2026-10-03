extends SceneTree
## RENDER (debug): the drawn corridor floor profile (rays down) against the walker's height rules.
const CamPhys = preload("res://presentation/fx_cam_phys.gd")
var main
var f := 0
func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		return false
	if f < 200:
		return false
	var cp = CamPhys.new(main.view.inst, main.view.get_world_3d())
	cp.sync_all()
	if f < 203:
		return false
	var n := 0
	for lid in main.sim.state["buildings"]:
		var l: Dictionary = main.sim.state["buildings"][lid]
		if String(l.get("def", "")) != "corridor" or n >= 4:
			continue
		n += 1
		var a: Vector2 = l["p0"]
		var b: Vector2 = l["p1"]
		var ya: float = main.view.h(a.x, a.y)
		var yb: float = main.view.h(b.x, b.y)
		var side: Vector2 = (b - a).normalized().orthogonal()
		var line := "corridor %d len %.1f:" % [int(lid), a.distance_to(b)]
		for t in [0.15, 0.3, 0.5, 0.7, 0.85]:
			var q: Vector2 = a.lerp(b, t)
			var yl: float = lerpf(ya, yb, t) + 0.05
			for lat in [-0.5, 0.0, 0.5]:
				var qq: Vector2 = q + side * lat
				var p := Vector3(qq.x, yl + 0.6, qq.y)
				var d: float = cp.ray(p, p + Vector3(0, -1.2, 0))
				line += " t%.2f/%+.1f: %s" % [t, lat, ("%+.3f %s" % [p.y - d - yl, String(cp.dbg_last).get_file().left(18)]) if d != INF else "none"]
			line += " | terrain-line %+.3f;" % [main.view.h(q.x, q.y) + 0.05 - yl]
		print(line)
	return true
