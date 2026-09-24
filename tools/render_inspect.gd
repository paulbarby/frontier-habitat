extends SceneTree
## RENDER: prints the node tree of GLB models (names, types, transforms, materials), to
## check the asset contract without a window.
##   node tools/godot.mjs script res://tools/render_inspect.gd <id> [<id> ...]

func _init() -> void:
	for id in OS.get_cmdline_user_args():
		var path: String = "res://assets/models/%s.glb" % id
		var ps = load(path)
		if ps == null:
			print("MISSING ", path)
			continue
		var root: Node = (ps as PackedScene).instantiate()
		print("== ", path)
		_walk(root, 0, Transform3D.IDENTITY)
		root.free()
	quit(0)

func _walk(n: Node, depth: int, parent_xf: Transform3D) -> void:
	var xf: Transform3D = parent_xf
	var line: String = "  ".repeat(depth) + String(n.name) + " [" + n.get_class() + "]"
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
		var o: Vector3 = xf.origin
		line += " at (%.2f, %.2f, %.2f)" % [o.x, o.y, o.z]
		var bx: Vector3 = xf.basis.x
		if not xf.basis.is_equal_approx(Basis()):
			line += " x->(%.2f, %.2f, %.2f)" % [bx.x, bx.y, bx.z]
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		var mats: Array = []
		for s in m.get_surface_count():
			var mt: Material = m.surface_get_material(s)
			if mt is BaseMaterial3D:
				var bm: BaseMaterial3D = mt
				mats.append("%s#%s%s" % [mt.resource_name, bm.albedo_color.to_html(false), (" e%.1f" % bm.emission_energy_multiplier) if bm.emission_enabled else ""])
			else:
				mats.append(mt.resource_name if mt != null else "-")
		line += " mats=" + str(mats)
	if n is AnimationPlayer:
		line += " anims=" + str((n as AnimationPlayer).get_animation_list())
	print(line)
	if depth < 3 or not (n is MeshInstance3D):
		for c in n.get_children():
			_walk(c, depth + 1, xf)
