extends SceneTree
## RENDER: the surfaces under a model-space point (x, z) of a model or the merged dome: every triangle hit by a
## vertical ray, its height and group/material (where is the real floor top?).
##   node tools/godot.mjs script res://tools/render_floor_probe.gd <model|dome> <x> <z> [ymax]
const Models = preload("res://presentation/models.gd")
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var tpl: Dictionary = Models.dome_template(true) if a[0] == "dome" else Models._template_from_file("res://assets/models/%s.glb" % a[0])
	var x: float = float(a[1])
	var z: float = float(a[2])
	var ymax: float = float(a[3]) if a.size() > 3 else 3.0
	var hits: Array = []
	for p in tpl["parts"]:
		var mesh: Mesh = p["mesh"]
		var xf: Transform3D = p["xf"]
		for si in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var ii: PackedInt32Array = idx if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0 else PackedInt32Array(range(v.size()))
			var mn: String = mesh.surface_get_material(si).resource_name if mesh.surface_get_material(si) != null else "?"
			for t in range(0, ii.size() - 2, 3):
				var A: Vector3 = xf * v[ii[t]]
				var B: Vector3 = xf * v[ii[t + 1]]
				var C: Vector3 = xf * v[ii[t + 2]]
				var h = Geometry3D.ray_intersects_triangle(Vector3(x, ymax, z), Vector3.DOWN, A, B, C)
				if h != null and (h as Vector3).y > -1.0:
					hits.append([snappedf((h as Vector3).y, 0.001), String(p["group"]), mn])
	hits.sort_custom(func(p1, p2): return p1[0] > p2[0])
	for h in hits.slice(0, 40):
		print("HIT y %.3f %s %s" % h)
	quit(0)
