extends SceneTree
## RENDER: the connected pieces of a storage room's Interior mesh (to find the crates on the racks).
##   node tools/godot.mjs script res://tools/render_stock_probe.gd [file]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var f: String = a[0] if a.size() > 0 else "storehouse_m"
	var n: Node = (load("res://assets/models/%s.glb" % f) as PackedScene).instantiate()
	for mi in n.find_children("Interior*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var arr: Array = m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var comps: Array = components(v, idx)
			var hist := {}
			for c in comps:
				var ab: AABB = c["aabb"]
				var k := "%.1fx%.1fx%.1f@y%.1f" % [ab.size.x, ab.size.y, ab.size.z, ab.position.y]
				hist[k] = int(hist.get(k, 0)) + 1
			var keys := hist.keys()
			keys.sort_custom(func(x, y): return hist[x] > hist[y])
			var out := []
			for k in keys.slice(0, 25):
				out.append("%s:%d" % [k, hist[k]])
			print("COMP %s surf %d (%s) comps %d | %s" % [f, s, m.surface_get_material(s).resource_name, comps.size(), " ".join(out)])
	n.free()
	quit(0)

static func components(v: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var key := {}
	var rep := PackedInt32Array()
	rep.resize(v.size())
	for i in v.size():
		var q := Vector3i(roundi(v[i].x * 1000.0), roundi(v[i].y * 1000.0), roundi(v[i].z * 1000.0))
		if not key.has(q):
			key[q] = i
		rep[i] = key[q]
	var parent := PackedInt32Array()
	parent.resize(v.size())
	for i in v.size():
		parent[i] = i
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	var ntri: int = idx.size() / 3 if idx.size() > 0 else v.size() / 3
	for t in ntri:
		var i0: int = rep[idx[t * 3] if idx.size() > 0 else t * 3]
		for k in [1, 2]:
			var ik: int = rep[idx[t * 3 + k] if idx.size() > 0 else t * 3 + k]
			var ra: int = find.call(i0)
			var rb: int = find.call(ik)
			if ra != rb:
				parent[ra] = rb
	var comp := {}
	for t in ntri:
		var r: int = find.call(rep[idx[t * 3] if idx.size() > 0 else t * 3])
		if not comp.has(r):
			comp[r] = {"tris": PackedInt32Array(), "aabb": AABB(v[idx[t * 3] if idx.size() > 0 else t * 3], Vector3.ZERO)}
		comp[r]["tris"].append(t)
		for k in 3:
			var vi: int = idx[t * 3 + k] if idx.size() > 0 else t * 3 + k
			comp[r]["aabb"] = (comp[r]["aabb"] as AABB).expand(v[vi])
	return comp.values()
