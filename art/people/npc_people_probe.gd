extends SceneTree
# ART-NPC probe: load the people scenes and list every material's albedo texture (shared external textures bound?)
func _init() -> void:
	for v in ["m1", "f1"]:
		var ps: PackedScene = load("res://assets/models/people_%s.glb" % v)
		if ps == null:
			print("PROBE %s: load failed" % v)
			continue
		var root := ps.instantiate()
		var n_tex := 0
		var n_missing := 0
		var shown := {}
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = mi.mesh
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				if m is BaseMaterial3D:
					var t: Texture2D = m.albedo_texture
					if t == null:
						n_missing += 1
					else:
						n_tex += 1
						if not shown.has(m.resource_name):
							shown[m.resource_name] = t.resource_path
		print("PROBE %s: %d textured surfaces, %d without albedo texture" % [v, n_tex, n_missing])
		for k in shown:
			print("PROBE %s   %s -> %s" % [v, k, shown[k]])
		root.free()
	quit()
