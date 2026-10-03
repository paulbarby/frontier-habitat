extends SceneTree
## RENDER (measure): where the physics shape build time goes for one template: faces vs BVH (set_faces).
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
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		return false
	if f < 200:
		return false
	for key in main.view.inst.batches:
		if not String(key).contains("habitat_l"):
			continue
		var tpl: Dictionary = main.view.inst.batches[key]["tpl"]
		var t0 := Time.get_ticks_usec()
		var all := PackedVector3Array()
		var ta := 0
		var tf := 0
		for p in tpl["parts"]:
			var mesh: Mesh = p["mesh"]
			var t1 := Time.get_ticks_usec()
			for si in mesh.get_surface_count():
				var arr: Array = mesh.surface_get_arrays(si)
			ta += Time.get_ticks_usec() - t1
			var t2 := Time.get_ticks_usec()
			var fs: PackedVector3Array = mesh.get_faces()
			fs = (p["xf"] as Transform3D) * fs
			all.append_array(fs)
			tf += Time.get_ticks_usec() - t2
		var t3 := Time.get_ticks_usec()
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(all)
		var tb := Time.get_ticks_usec() - t3
		print("%s: get_arrays %.1f ms, get_faces+xf %.1f ms, set_faces %.1f ms (%d tris), total %.1f" % [String(key).get_file(), ta / 1000.0, tf / 1000.0, tb / 1000.0, all.size() / 3, (Time.get_ticks_usec() - t0) / 1000.0])
	return true
