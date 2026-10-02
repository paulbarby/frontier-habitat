extends SceneTree
## RENDER (debug): group AABBs of the drawn templates whose key contains a filter (after a save is loaded).
##   node tools/godot.mjs script res://tools/render_tpl_aabb.gd <filter> [save]
var main
var f := 0
var filt := "doorway"
var save := "res://content/saves/showcase_v3_late.fhsave"
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: filt = a[0]
	if a.size() > 1: save = a[1]
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		return false
	if f < 200:
		return false
	for key in main.view.inst.batches:
		if not String(key).contains(filt):
			continue
		var tpl: Dictionary = main.view.inst.batches[key]["tpl"]
		var gs := {}
		for p in tpl["parts"]:
			var ab: AABB = (p["xf"] as Transform3D) * (p["mesh"] as Mesh).get_aabb()
			var g: String = p["group"]
			gs[g] = (gs[g] as AABB).merge(ab) if gs.has(g) else ab
		print("%s scale %s" % [key, str(tpl.get("scale", 1.0))])
		for g in gs:
			var ab2: AABB = gs[g]
			print("   %-14s y %.2f..%.2f  x %.2f..%.2f z %.2f..%.2f" % [g, ab2.position.y, ab2.end.y, ab2.position.x, ab2.end.x, ab2.position.z, ab2.end.z])
	return true
