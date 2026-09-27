extends SceneTree
## RENDER debug: one airlock of a save: record, model, anchors, door kit geometry, openings.
##   node tools/godot.mjs script res://tools/render_lock_probe.gd <save> <airlock id>
var main
var n := 0
var save := "res://content/saves/scene_final.fhsave"
var lid := 141

func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() > 0:
		save = a[0]
	if a.size() > 1:
		lid = int(a[1])
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n > 12:
		return true
	if n == 3:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		main.set_speed(0)
	if n == 8:
		var v = main.view
		var b: Dictionary = main.sim.state["buildings"][lid]
		print("record: def %s pos %s rot %.3f radius %.2f size %s" % [b["def"], str(b["pos"]), float(b["rot"]), float(b["radius"]), str(b.get("size"))])
		var meta: Dictionary = v.bmeta[lid]
		print("model key %s scale %.3f" % [meta["tpl"].get("key"), float(meta["tpl"].get("scale", 1.0))])
		for an in meta["anchors"]:
			var t: Transform3D = meta["anchors"][an]
			if String(an).begins_with("Porch") or String(an).begins_with("Stand") or String(an).begins_with("Suit") or String(an).begins_with("Chamber"):
				var p := Vector2(t.origin.x, t.origin.z)
				print("  anchor %-10s %s  d %.2f" % [an, str(p.snappedf(0.01)), p.distance_to(b["pos"])])
		var g: Dictionary = v.airlock._geo(lid, meta)
		print("inner_x %s outer_x %s door_out %s" % [str(g.get("inner_x")), str(g.get("outer_x")), str(g.get("door_out"))])
		print("sim door_pos %s" % str(main.sim.nav.door_pos(b)))
		return true
	return false
