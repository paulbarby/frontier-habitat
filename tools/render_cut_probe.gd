extends SceneTree
## RENDER debug (Paul cutaway, 2026-09-26): the GLB nodes of a room model that stand above the
## 1.40 m wall cut and are not in a roof / upper / allowed group. Model units (before scale).
##   node tools/godot.mjs script res://tools/render_cut_probe.gd <def> [<def> ...]
const Models = preload("res://presentation/models.gd")
const SKIP := ["Interior", "Tall", "WallsUp", "Roof"]
func _init() -> void:
	for id in OS.get_cmdline_user_args():
		var r: Dictionary = Models.resolve(id, 1)
		var path: String = String(r.get("path", "res://assets/models/%s.glb" % id))
		var ps: PackedScene = load(path)
		if ps == null:
			print("missing ", id, " ", r)
			continue
		var root: Node = ps.instantiate()
		print("== ", id, " ", path)
		_walk(root, root)
		root.free()
	quit()

func _walk(n: Node, root: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var g: Transform3D = _gx(n as Node3D, root)
		var mesh: Mesh = (n as MeshInstance3D).mesh
		var top := -INF
		for si in mesh.get_surface_count():
			var vv: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in vv:
				top = maxf(top, (g * v).y)
		var grp: String = Models.group_of(String(n.name))
		if top > 1.42 and not (grp in SKIP) and not grp.ends_with("Top") and not grp.ends_with("Status"):
			var mats: Array = []
			for si in mesh.get_surface_count():
				var m: Material = mesh.surface_get_material(si)
				mats.append(m.resource_name if m != null else "")
			print("  %-28s group %-10s top %.3f mats %s" % [n.name, grp, top, str(mats)])
			# Where the vertices above 1.42 are: material, radius from the model centre (x/y plane).
			for si in mesh.get_surface_count():
				var vv2: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
				var cnt := 0
				var rmin := INF
				var rmax := -INF
				var tmax := -INF
				for v in vv2:
					var w: Vector3 = g * v
					if w.y > 1.42:
						cnt += 1
						var r: float = Vector2(w.x, w.z).length()
						rmin = minf(rmin, r)
						rmax = maxf(rmax, r)
						tmax = maxf(tmax, w.y)
				if cnt > 0:
					print("      %-12s %4d verts above 1.42 | top %.3f | radius %.2f..%.2f" % [mats[si], cnt, tmax, rmin, rmax])
	for c in n.get_children():
		_walk(c, root)

func _gx(n: Node3D, root: Node) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
