extends SceneTree
## RENDER debug: node names, positions and AABBs of a model file (first argument = model id).
func _init() -> void:
	var ids: PackedStringArray = OS.get_cmdline_user_args()
	for id in ids:
		var ps: PackedScene = load("res://assets/models/%s.glb" % id)
		if ps == null:
			print("missing ", id)
			continue
		var root: Node = ps.instantiate()
		print("== ", id)
		_walk(root, root, 0)
		root.free()
	quit()

func _walk(n: Node, root: Node, depth: int) -> void:
	if n is Node3D and n != root:
		var g: Transform3D = (n as Node3D).global_transform if (n as Node3D).is_inside_tree() else _gx(n as Node3D, root)
		var extra := ""
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var ab: AABB = g * (n as MeshInstance3D).mesh.get_aabb()
			var mats: Array = []
			for si in (n as MeshInstance3D).mesh.get_surface_count():
				var m: Material = (n as MeshInstance3D).mesh.surface_get_material(si)
				mats.append(m.resource_name if m != null else "")
			extra = " aabb %s..%s mats %s" % [str(ab.position.snappedf(0.01)), str(ab.end.snappedf(0.01)), str(mats)]
		var ex: String = ""
		if n.has_meta("extras"):
			ex = " extras " + str(n.get_meta("extras"))
		print("%s%s pos %s fwdX %s%s%s" % ["  ".repeat(depth), n.name, str(g.origin.snappedf(0.01)), str(g.basis.x.snappedf(0.01)), extra, ex])
	for c in n.get_children():
		_walk(c, root, depth + 1)

func _gx(n: Node3D, root: Node) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
