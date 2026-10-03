extends SceneTree
## RENDER (debug): materials of the dome parts under the Club's dance floor anchors (dark floor between LED tiles).
var main
var f := 0
func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes("res://build/web_render/dome_v5.fhsave"))
		return false
	if f < 240:
		return false
	var v = main.view
	for bid in v.bmeta:
		var meta: Dictionary = v.bmeta[bid]
		if String(meta.get("def", "")) != "super_dome":
			continue
		var tpl: Dictionary = meta["tpl"]
		var dz: Array = []
		for an in (tpl.get("anchors", {}) as Dictionary):
			if String(an).contains("Dance_club") or String(an).contains("Dancer_club"):
				dz.append((tpl["anchors"][an] as Transform3D).origin)
				print("  anchor ", an, " ", (tpl["anchors"][an] as Transform3D).origin)
		print("club anchors (model): ", dz.size())
		var seen := {}
		for p in tpl["parts"]:
			var mesh: Mesh = p["mesh"]
			for si in mesh.get_surface_count():
				var arr: Array = mesh.surface_get_arrays(si)
				var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var near := 0
				var ys := {}
				for k in range(0, vv.size(), 1):
					var q: Vector3 = (p["xf"] as Transform3D) * vv[k]
					for a in dz:
						if absf(q.y - (a as Vector3).y) < 0.15 and Vector2(q.x - a.x, q.z - a.z).length() < 4.0:
							near += 1
							ys[snappedf(q.y - (a as Vector3).y, 0.005)] = true
							break
				if near > 6:
					var mt: Material = mesh.surface_get_material(si)
					var nm: String = mt.resource_name if mt != null else "-"
					var alb := ""
					if mt is BaseMaterial3D:
						alb = str((mt as BaseMaterial3D).albedo_color)
					elif mt is ShaderMaterial:
						alb = str((mt as ShaderMaterial).get_shader_parameter("albedo"))
					var key: String = "%s|%s" % [p["group"], nm]
					if not seen.has(key):
						seen[key] = true
						print("  %s surface %d mat %s (%s) albedo %s verts near %d dy %s" % [p["group"], si, nm, mt.get_class() if mt != null else "-", alb, near, str(ys.keys())])
	return true
