extends SceneTree
## RENDER probe (2026-10-01): the corridor template's groups, part AABBs and material cull modes
## (is the tube visible from inside with the roof on?). node tools/godot.mjs script res://tools/render_tube_probe.gd
const Models = preload("res://presentation/models.gd")

func _init() -> void:
	for d in ["corridor", "habitat", "lounge"]:
		var tpl: Dictionary = Models.prop([d], 1.2, "room", "logistics")
		print("== %s groups %s" % [d, str((tpl.get("groups", {}) as Dictionary).keys())])
		for p in tpl["parts"]:
			var m: Mesh = p["mesh"]
			var ab: AABB = (p["xf"] as Transform3D) * m.get_aabb()
			var culls: Array = []
			for si in m.get_surface_count():
				var mat = m.surface_get_material(si)
				if mat is BaseMaterial3D:
					culls.append("%s:%d" % [String(mat.resource_name), int((mat as BaseMaterial3D).cull_mode)])
				elif mat != null:
					culls.append("%s:shader" % String(mat.resource_name))
			if d == "corridor" or String(p["group"]) in ["Roof", "WallsUp", "WallsIn"]:
				print("  %s y %.2f..%.2f z %.2f..%.2f %s" % [p["group"], ab.position.y, ab.end.y, ab.position.z, ab.end.z, str(culls)])
	quit()
