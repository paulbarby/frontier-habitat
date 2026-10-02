extends SceneTree
## RENDER (debug): what DRAWN geometry a follow camera faces. Casts a fan of rays from a camera point toward a
## person's chest against the triangles of every mesh in the scene (MeshInstance3D, MultiMeshInstance3D) and
## prints the nearest hits with the node path, so a wall the framing test (fx_occ grids, volumes) misses can
## be named.
##   node tools/godot.mjs script res://tools/render_ray_probe.gd <save> "cx,cy,cz;bx,by,bz" ["..." ...]
var main
var f := 0
var save := "res://content/saves/showcase_v3_late.fhsave"
var pairs: Array = []
var _faces := {}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		save = a[0]
	for i in range(1, a.size()):
		var pp: PackedStringArray = a[i].split(";")
		var c: PackedStringArray = pp[0].split(",")
		var b: PackedStringArray = pp[1].split(",")
		pairs.append([Vector3(float(c[0]), float(c[1]), float(c[2])), Vector3(float(b[0]), float(b[1]), float(b[2]))])
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		return false
	if f < 400:
		return false
	var geo: Array = []
	_collect(root, geo)
	# (the instancer's MultiMeshes hold no transforms under the headless dummy renderer: its handles do)
	var ins = main.view.inst
	for h in ins.handles:
		var e: Dictionary = ins.handles[h]
		var bt: Dictionary = ins.batches[e["key"]]
		for p in bt["parts"]:
			var part: Dictionary = p["part"]
			var px: Transform3D = (e["xf"] as Transform3D) * (part["xf"] as Transform3D)
			geo.append([str(e["key"]).get_file() + ":" + String(part["group"]) + (" HIDDEN" if (e["hidden"] as Dictionary).has(part["group"]) else ""), part["mesh"], [px]])
	print("geometry nodes: %d buildings %d" % [geo.size(), main.view.bmeta.size()])
	for pr in pairs:
		var bd := ""
		for bid in main.view.bmeta:
			var b: Dictionary = main.sim.state["buildings"][bid]
			var dd: float = (b["pos"] as Vector2).distance_to(Vector2(pr[0].x, pr[0].z))
			if dd < float(b["radius"]) + 3.0:
				bd += " %s r%.1f d%.1f" % [b["def"], float(b["radius"]), dd]
		print("near %s:%s" % [str(pr[0]), bd])
	for pr in pairs:
		_probe(pr[0], pr[1], geo)
	return true

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, (n as MeshInstance3D).mesh, [(n as MeshInstance3D).global_transform]])
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and (n as MultiMeshInstance3D).multimesh.mesh != null:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		var xs: Array = []
		var gx: Transform3D = (n as MultiMeshInstance3D).global_transform
		var cnt: int = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		for i in cnt:
			xs.append(gx * mm.get_instance_transform(i))
		out.append([n, mm.mesh, xs])
	for c in n.get_children():
		_collect(c, out)

func _faces_of(m: Mesh) -> PackedVector3Array:
	if not _faces.has(m):
		_faces[m] = m.get_faces()
	return _faces[m]

func _probe(cam: Vector3, body: Vector3, geo: Array) -> void:
	var chest: Vector3 = body + Vector3(0.0, 1.3, 0.0)
	var f0: Vector3 = (chest - cam).normalized()
	var rt: Vector3 = f0.cross(Vector3.UP).normalized()
	var up: Vector3 = rt.cross(f0).normalized()
	print("== cam %s body %s dist %.2f" % [str(cam), str(body), cam.distance_to(chest)])
	var reach := 1.2
	var seg_box := AABB(cam - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	var near: Array = []
	for g in geo:
		var m: Mesh = g[1]
		var ab: AABB = m.get_aabb()
		for x in g[2]:
			if ((x as Transform3D) * ab).intersects(seg_box):
				near.append([g[0], m, x])
	for ay in [-0.4, -0.2, 0.0, 0.2, 0.4]:
		for ap in [-0.15, 0.0, 0.15]:
			var d: Vector3 = (f0 + rt * tan(ay) + up * tan(ap)).normalized()
			var best := INF
			var who := ""
			for e in near:
				var inv: Transform3D = (e[2] as Transform3D).affine_inverse()
				var o: Vector3 = inv * cam
				var dl: Vector3 = (inv.basis * d)
				var fs: PackedVector3Array = _faces_of(e[1])
				var k := 0
				while k + 2 < fs.size():
					var hit = Geometry3D.ray_intersects_triangle(o, dl, fs[k], fs[k + 1], fs[k + 2])
					if hit != null:
						var t: float = ((e[2] as Transform3D) * (hit as Vector3)).distance_to(cam)
						if t < best:
							best = t
							if e[0] is String:
								who = "inst %s mesh=%s" % [e[0], (e[1] as Mesh).resource_name]
							else:
								var nd: Node = e[0]
								who = "%s vis=%s mesh=%s" % [str(nd.get_path()).right(70), str((nd as Node3D).is_visible_in_tree()), (e[1] as Mesh).resource_name]
					k += 3
			print("  ray y%+.1f p%+.2f: %s %s" % [ay, ap, "%.2f" % best if best < INF else "none", who])
