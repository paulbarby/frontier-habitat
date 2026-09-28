extends SceneTree
## RENDER: size (AABB) of the POI models.
func _init() -> void:
	for id in ["poi_wreck", "poi_probe", "poi_cave", "poi_meteorites", "poi_anomaly"]:
		var ps: PackedScene = load("res://assets/models/%s.glb" % id)
		var n: Node3D = ps.instantiate()
		var ab := AABB()
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf: Transform3D = Transform3D.IDENTITY
			var p: Node = m
			while p != null and p != n:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var b: AABB = xf * m.get_aabb()
			ab = b if first else ab.merge(b)
			first = false
		print("POIM %s size %s pos %s meshes %d" % [id, str(ab.size.snapped(Vector3.ONE * 0.1)), str(ab.position.snapped(Vector3.ONE * 0.1)), n.find_children("*", "MeshInstance3D", true, false).size()])
		n.free()
	quit(0)