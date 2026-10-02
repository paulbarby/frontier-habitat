extends SceneTree
## RENDER: groups, materials and triangle counts of a model template (what the cutaway can hide).
##   node tools/godot.mjs script res://tools/render_tpl_groups.gd corridor
const Models = preload("res://presentation/models.gd")
func _init() -> void:
	for id in OS.get_cmdline_user_args():
		var tpl: Dictionary = Models._template_from_file("res://assets/models/%s.glb" % id)
		print(id, " aabb ", tpl.get("aabb"))
		for p in tpl["parts"]:
			var m: Mesh = p["mesh"]
			var mats: Array = []
			var tr := 0
			for s in m.get_surface_count():
				var mt: Material = m.surface_get_material(s)
				var tdesc := ""
				if mt is BaseMaterial3D:
					tdesc = "t%d a%.2f" % [(mt as BaseMaterial3D).transparency, (mt as BaseMaterial3D).albedo_color.a]
				mats.append("%s(%s)" % [mt.resource_name if mt else "?", tdesc])
				tr += (m.surface_get_array_index_len(s) if m.surface_get_array_index_len(s) > 0 else m.surface_get_array_len(s)) / 3
			print("  ", p["group"], " tris ", tr, " ", ", ".join(mats), " aabb ", m.get_aabb())
	quit(0)
