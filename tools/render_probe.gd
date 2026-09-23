extends SceneTree
## RENDER agent probe: prints the node tree of each model, its surfaces, materials and
## whether the mesh has a vertex colour array (baked AO).
##   node tools/godot.mjs script res://tools/render_probe.gd [model ids...]

func _init() -> void:
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		ids.append(a)
	if ids.is_empty():
		var d := DirAccess.open("res://assets/models")
		for f in d.get_files():
			if f.ends_with(".glb"):
				ids.append(f.get_basename())
	for id in ids:
		var path := "res://assets/models/%s.glb" % id
		if not ResourceLoader.exists(path):
			print("MISSING ", path)
			continue
		var scene: PackedScene = load(path)
		var root: Node = scene.instantiate()
		print("== ", id)
		_dump(root, 1, Transform3D.IDENTITY)
		root.free()
	quit(0)

func _dump(n: Node, depth: int, parent_xf: Transform3D) -> void:
	var pad := "  ".repeat(depth)
	var line := "%s%s (%s)" % [pad, n.name, n.get_class()]
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
		var p: Vector3 = (n as Node3D).position
		if p.length() > 0.001:
			line += " pos=(%.2f,%.2f,%.2f)" % [p.x, p.y, p.z]
		var r: Vector3 = (n as Node3D).rotation_degrees
		if r.length() > 0.01:
			line += " rot=(%.0f,%.0f,%.0f)" % [r.x, r.y, r.z]
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		if m != null:
			var aabb: AABB = m.get_aabb()
			line += " aabb=(%.2f,%.2f,%.2f)+(%.2f,%.2f,%.2f)" % [aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z]
			var surf: Array = []
			for s in m.get_surface_count():
				var mat: Material = m.surface_get_material(s)
				var fmt: int = (m as ArrayMesh).surface_get_format(s) if m is ArrayMesh else 0
				var has_col: bool = (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0
				var vc := ""
				if mat is BaseMaterial3D:
					vc = " vcalb=%s" % str((mat as BaseMaterial3D).vertex_color_use_as_albedo)
					var bm := mat as BaseMaterial3D
					vc += " alb=%s em=%s" % [bm.albedo_color.to_html(false), str(bm.emission_enabled)]
				surf.append("%s%s%s" % [mat.resource_name if mat != null else "<none>", " COLOR" if has_col else "", vc])
			line += "\n%s    surfaces: %s" % [pad, ", ".join(surf)]
	print(line)
	for c in n.get_children():
		_dump(c, depth + 1, xf)
