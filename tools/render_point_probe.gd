extends SceneTree
const Models = preload("res://presentation/models.gd")
## RENDER (debug): what stands at a world point (x z) on a save: structures whose circle holds it, terrain height.
##   node tools/godot.mjs script res://tools/render_point_probe.gd <save> x z
var main
var f := 0
var save := ""
var px := 0.0
var pz := 0.0
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	save = a[0]
	px = float(a[1])
	pz = float(a[2])
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		return false
	if f < 120:
		return false
	var q := Vector2(px, pz)
	print("terrain h %.3f" % main.view.h(px, pz))
	for bid in main.sim.state["buildings"]:
		var b: Dictionary = main.sim.state["buildings"][bid]
		if b.has("pos") and (b["pos"] as Vector2).distance_to(q) < float(b.get("radius", 1.0)) + 1.5:
			var y0: float = (main.view.bmeta[bid]["xf"] as Transform3D).origin.y if main.view.bmeta.has(bid) else -1.0
			print("  %s %d kind %s r %.1f d %.2f origin y %.3f state %s" % [b["def"], int(bid), b["kind"], float(b["radius"]), (b["pos"] as Vector2).distance_to(q), y0, b.get("state", "")])
			if main.view.bmeta.has(bid):
				var mxf: Transform3D = main.view.bmeta[bid]["xf"]
				var tpl: Dictionary = main.view.bmeta[bid].get("tpl", {})
				var xs := Transform3D(mxf.basis * Basis.from_scale(Models.scale3(tpl)), mxf.origin)
				print("    model point %s (model %s)" % [str((xs.affine_inverse() * Vector3(px, y0, pz)).snappedf(0.01)), String(tpl.get("key", ""))])
		elif b.has("p0"):
			var c: Vector2 = Geometry2D.get_closest_point_to_segment(q, b["p0"], b["p1"])
			if c.distance_to(q) < 2.0:
				print("  %s %d (link) d %.2f" % [b["def"], int(bid), c.distance_to(q)])
	return true
