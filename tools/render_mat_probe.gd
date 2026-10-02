extends SceneTree
## RENDER debug: the runtime materials (class, shader, cull) of the parts of the first structure of a def in a save.
##   node tools/godot.mjs script res://tools/render_mat_probe.gd <save> <def>
var main
var n := 0
func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	n += 1
	var a := OS.get_cmdline_user_args()
	if n == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(a[0]))
		return false
	if n < 8:
		main._process(1.0 / 60.0)
		return false
	for bid in main.view.bmeta:
		var b: Dictionary = main.sim.state["buildings"].get(bid, {})
		if b.is_empty() or String(b["def"]) != a[1]:
			continue
		var tpl: Dictionary = main.view.bmeta[bid]["tpl"]
		print(a[1], " ", tpl.get("key"))
		for p in tpl["parts"]:
			var m: Mesh = p["mesh"]
			for s in m.get_surface_count():
				var mt: Material = m.surface_get_material(s)
				var d := mt.get_class()
				if mt is ShaderMaterial:
					d += " " + String((mt as ShaderMaterial).shader.resource_path)
				elif mt is BaseMaterial3D:
					d += " cull %d transp %d" % [(mt as BaseMaterial3D).cull_mode, (mt as BaseMaterial3D).transparency]
				print("  ", p["group"], " ", mt.resource_name, " ", d)
		break
	return true
