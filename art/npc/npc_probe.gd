## ART-NPC probe: loads the imported astronaut GLBs in Godot and prints what the game receives.
## Run: node tools/godot.mjs script res://art/npc/npc_probe.gd
## (Import first: node tools/godot.mjs import.)  RENDER's full check is tools/npc_check.gd.
extends SceneTree


func _find(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_find(c, cls, out)


func _init() -> void:
	var report := {}
	for v in ["suit", "indoor"]:
		var path := "res://assets/models/astronaut_%s.glb" % v
		if not ResourceLoader.exists(path):
			print("probe %s: not present" % v)
			continue
		var ps: PackedScene = load(path)
		var root: Node = ps.instantiate()
		var sk: Array = []
		var mi: Array = []
		var ap: Array = []
		_find(root, "Skeleton3D", sk)
		_find(root, "MeshInstance3D", mi)
		_find(root, "AnimationPlayer", ap)
		var r := {"skeletons": sk.size(), "meshes": [], "bones": [], "clips": {}}
		if sk.size() > 0:
			var s: Skeleton3D = sk[0]
			for i in s.get_bone_count():
				r["bones"].append(s.get_bone_name(i))
		for m in mi:
			var mm: MeshInstance3D = m
			var mats: Array = []
			for si in mm.mesh.get_surface_count():
				var mat := mm.mesh.surface_get_material(si)
				mats.append(mat.resource_name if mat else "?")
			r["meshes"].append({"name": mm.name, "skinned": mm.skin != null or mm.get_skeleton_path() != NodePath(""),
					"surfaces": mm.mesh.get_surface_count(), "materials": mats})
		if ap.size() > 0:
			var a: AnimationPlayer = ap[0]
			for nm in a.get_animation_list():
				var an: Animation = a.get_animation(nm)
				r["clips"][nm] = {"length": snappedf(an.length, 0.0001), "tracks": an.get_track_count()}
		# triangles from the mesh arrays (works headless only while the arrays are still on the CPU side)
		var tris := 0
		for m in mi:
			var mm2: MeshInstance3D = m
			for si in mm2.mesh.get_surface_count():
				var arr: Array = mm2.mesh.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		r["triangles_from_arrays"] = tris
		# crate contract: in carry_idle frame 0 the prop.R bone basis should be the character basis
		if ap.size() > 0 and sk.size() > 0 and (ap[0] as AnimationPlayer).has_animation("carry_idle"):
			get_root().add_child(root)
			var a2: AnimationPlayer = ap[0]
			a2.play("carry_idle")
			a2.seek(0.0, true)
			var s2: Skeleton3D = sk[0]
			s2.force_update_all_bone_transforms()
			var pr := s2.find_bone("prop.R")
			var g: Transform3D = s2.get_bone_global_pose(pr)
			var ang := rad_to_deg(g.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY))
			# the crate transform RENDER will get: prop.R global * carry.prop_R_offset (astronaut_anims.json)
			var meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/astronaut_anims.json"))
			if meta is Dictionary and (meta as Dictionary).has("carry") and (meta["carry"] as Dictionary).has("prop_R_offset"):
				var o: Dictionary = meta["carry"]["prop_R_offset"]
				var bx: Array = o["basis_x"]
				var by: Array = o["basis_y"]
				var bz: Array = o["basis_z"]
				var og: Array = o["origin"]
				var off := Transform3D(Basis(Vector3(bx[0], bx[1], bx[2]), Vector3(by[0], by[1], by[2]), Vector3(bz[0], bz[1], bz[2])),
						Vector3(og[0], og[1], og[2]))
				var cr: Transform3D = g * off
				r["crate"] = {"origin": [snappedf(cr.origin.x, 0.001), snappedf(cr.origin.y, 0.001), snappedf(cr.origin.z, 0.001)],
						"basis_angle_from_identity_deg": snappedf(rad_to_deg(cr.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)), 0.01)}
				print("probe %s: crate at %s" % [v, str(r["crate"])])
			r["carry_prop_R"] = {"origin": [snappedf(g.origin.x, 0.001), snappedf(g.origin.y, 0.001), snappedf(g.origin.z, 0.001)],
					"basis_angle_from_identity_deg": snappedf(ang, 0.01),
					"basis_x": [snappedf(g.basis.x.x, 0.01), snappedf(g.basis.x.y, 0.01), snappedf(g.basis.x.z, 0.01)],
					"basis_y": [snappedf(g.basis.y.x, 0.01), snappedf(g.basis.y.y, 0.01), snappedf(g.basis.y.z, 0.01)],
					"basis_z": [snappedf(g.basis.z.x, 0.01), snappedf(g.basis.z.y, 0.01), snappedf(g.basis.z.z, 0.01)]}
			get_root().remove_child(root)
		report[v] = r
		print("probe %s: triangles %d, carry prop.R %s" % [v, tris, str(r.get("carry_prop_R", {}))])
		print("probe %s: %d skeleton, %d bones, meshes %s" % [v, sk.size(), r["bones"].size(), str(r["meshes"])])
		print("probe %s clips: %s" % [v, str(r["clips"])])
		root.free()
	var f := FileAccess.open("res://art/npc/godot_probe.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, " "))
		f.close()
	quit()
