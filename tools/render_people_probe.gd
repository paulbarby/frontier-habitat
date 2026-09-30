extends SceneTree
## RENDER: what a people_<v>.glb holds (meshes, surfaces, materials, skin binds, weights, clips).
##   node tools/godot.mjs script res://tools/render_people_probe.gd [m1]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var v: String = a[0] if a.size() > 0 else "m1"
	var n: Node = (load("res://assets/models/people_%s.glb" % v) as PackedScene).instantiate()
	for sk in n.find_children("*", "Skeleton3D", true, false):
		print("SKEL %s bones %d" % [sk.name, (sk as Skeleton3D).get_bone_count()])
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3: MeshInstance3D = mi
		var m: Mesh = m3.mesh
		print("MESH %s surf %d skin %s binds %d" % [m3.name, m.get_surface_count(), str(m3.skin != null), m3.skin.get_bind_count() if m3.skin != null else -1])
		for s in m.get_surface_count():
			var mat: Material = m.surface_get_material(s)
			var fmt: int = m.surface_get_format(s)
			var info := ""
			if mat is BaseMaterial3D:
				var b: BaseMaterial3D = mat
				info = "alb %s tex %s nrm %s transp %d cull %d scissor %.2f rough %.2f" % [b.albedo_color.to_html(), str(b.albedo_texture != null), str(b.normal_enabled), b.transparency, b.cull_mode, b.alpha_scissor_threshold, b.roughness]
			print("  S%d %s idx %d v %d 8w %s tan %s col %s uv2 %s | %s" % [s, mat.resource_name if mat else "-", m.surface_get_array_index_len(s), m.surface_get_array_len(s), str((fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0), str((fmt & Mesh.ARRAY_FORMAT_TANGENT) != 0), str((fmt & Mesh.ARRAY_FORMAT_COLOR) != 0), str((fmt & Mesh.ARRAY_FORMAT_TEX_UV2) != 0), info])
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		print("ANIMS %d" % (ap as AnimationPlayer).get_animation_list().size())
	n.free()
	quit(0)
