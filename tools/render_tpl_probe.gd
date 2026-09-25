extends SceneTree
## RENDER debug: groups of a model template (after Models parsing) with their height range.
##   node tools/godot.mjs script res://tools/render_tpl_probe.gd <model id> [min top]
const Models = preload("res://presentation/models.gd")
func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var tpl: Dictionary = Models._template_from_file("res://assets/models/%s.glb" % a[0])
	var min_top: float = float(a[1]) if a.size() > 1 else 0.0
	var by := {}
	for p in tpl["parts"]:
		if bool(p.get("shadow_only", false)):
			continue
		var ab: AABB = (p["xf"] as Transform3D) * (p["mesh"] as Mesh).get_aabb()
		var g: String = p["group"]
		if not by.has(g):
			by[g] = ab
		else:
			by[g] = (by[g] as AABB).merge(ab)
	for g in by:
		var ab2: AABB = by[g]
		if ab2.end.y >= min_top:
			print("%-18s y %.2f..%.2f  x %.2f..%.2f  z %.2f..%.2f" % [g, ab2.position.y, ab2.end.y, ab2.position.x, ab2.end.x, ab2.position.z, ab2.end.z])
	quit()
