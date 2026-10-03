extends SceneTree
## ART-HAB scratch (2026-10-04, critic r42 PE-01): near vs far template colours as the game loads them.
##   node tools/godot.mjs script res://tools/arthab_farcheck.gd

const Models = preload("res://presentation/models.gd")

func _stats(path: String) -> void:
	var tpl: Dictionary = Models._template_from_file(path)
	var tot := Vector3.ZERO
	var cnt := 0
	for p in tpl["parts"]:
		var g: String = p["group"]
		if not (g in ["Base", "Walls", "Interior", "WallsIn"]):
			continue
		var mesh: Mesh = p["mesh"]
		for si in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(si)
			var arr: Array = mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm = arr[Mesh.ARRAY_NORMAL]
			var col = arr[Mesh.ARRAY_COLOR]
			var alb := Color(1, 1, 1)
			var use_vc := false
			var srgb := false
			var nm := ""
			if m is BaseMaterial3D:
				alb = (m as BaseMaterial3D).albedo_color.srgb_to_linear()
				use_vc = (m as BaseMaterial3D).vertex_color_use_as_albedo
				srgb = (m as BaseMaterial3D).vertex_color_is_srgb
				nm = m.resource_name
			var s := Vector3.ZERO
			var n := 0
			var up_n := 0
			for k in v.size():
				var xf: Transform3D = p["xf"]
				var w: Vector3 = xf * v[k]
				if w.y < 0.12 or w.y > 0.17:
					continue
				var c := Color(1, 1, 1)
				if use_vc and col is PackedColorArray and (col as PackedColorArray).size() == v.size():
					c = (col as PackedColorArray)[k]
				s += Vector3(alb.r * c.r, alb.g * c.g, alb.b * c.b)
				n += 1
				if nrm is PackedVector3Array and (nrm as PackedVector3Array).size() == v.size() and (xf.basis * (nrm as PackedVector3Array)[k]).y > 0.7:
					up_n += 1
			if n > 0:
				print("FARCHK %s %s %s surf %d mat %s vc %s srgb %s floor verts %d (up %d) mean %s" % [path.get_file(), g, str(p.get("shadow")), si, nm, str(use_vc), str(srgb), n, up_n, str(s / n)])
				tot += s
				cnt += n
	if cnt > 0:
		print("FARCHK %s TOTAL floor mean %s over %d" % [path.get_file(), str(tot / cnt), cnt])

func _init() -> void:
	for f in ["habitat_m", "habitat_m_far", "mine_m", "mine_m_far"]:
		_stats("res://assets/models/%s.glb" % f)
	quit()
