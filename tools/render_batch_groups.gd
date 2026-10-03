extends SceneTree
## RENDER (measure): visible instancer parts (draw calls before culling) by group, roofs off, a save.
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
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		return false
	if f == 100:
		main.rig.target_distance = 110.0
		main.view.set_roofs_off(true)
	if f < 260:
		return false
	var c := {}
	var tris := {}
	var tot := 0
	for key in main.view.inst.batches:
		var bt: Dictionary = main.view.inst.batches[key]
		for p in bt["parts"]:
			if not (p["mmi"] as MultiMeshInstance3D).visible:
				continue
			var g: String = String(p["part"]["group"])
			var gk: String = g.get_slice("_", 0) if not g.begins_with("D_") else "D_" + g.get_slice("_", 1)
			var mesh: Mesh = p["part"]["mesh"]
			var nsurf: int = mesh.get_surface_count()
			c[gk] = int(c.get(gk, 0)) + nsurf
			var used: int = int(bt["used"])
			tot += nsurf
	var arr: Array = c.keys()
	arr.sort_custom(func(a, b): return int(c[a]) > int(c[b]))
	for k in arr.slice(0, 25):
		print("%-16s surfaces %d" % [k, int(c[k])])
	print("TOTAL visible part surfaces %d, batches %d" % [tot, main.view.inst.batches.size()])
	return true
