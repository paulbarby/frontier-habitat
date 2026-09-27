extends SceneTree
## RENDER: which drawn things (visible GeometryInstance3D + their materials) appear in the view of
## showcase_v4 between two game seconds, to find what first-draws at a web frame spike.
##   node tools/godot.mjs script res://tools/render_vis_probe.gd -- <from_g> <to_g>
var main
var n := 0
var g0 := 0
var seen := {}
var lo := 0
var hi := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _key(gi: GeometryInstance3D) -> Array:
	var mats: Array = []
	if gi.material_override != null:
		mats.append(gi.material_override)
	if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
		var mi := gi as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(s)
			if m != null:
				mats.append(m)
	if gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null and (gi as MultiMeshInstance3D).multimesh.mesh != null:
		var mm: Mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		for s in mm.get_surface_count():
			if mm.surface_get_material(s) != null:
				mats.append(mm.surface_get_material(s))
	var out: Array = []
	if gi is Label3D:
		var l := gi as Label3D
		out.append("Label3D bb%d fixed%d nodt%d cut%d shaded%d dbl%d" % [l.billboard, int(l.fixed_size), int(l.no_depth_test), l.alpha_cut, int(l.shaded), int(l.double_sided)])
	elif gi is SpriteBase3D:
		out.append("Sprite3D")
	for m in mats:
		var desc: String = m.get_class()
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			desc += ":" + (m as ShaderMaterial).shader.resource_path.get_file()
		elif m is BaseMaterial3D:
			var b := m as BaseMaterial3D
			desc += ":sh%d tr%d cull%d dd%d nodt%d bb%d fog%d" % [b.shading_mode, b.transparency, b.cull_mode, b.depth_draw_mode, int(b.no_depth_test), b.billboard_mode, int(b.disable_fog)]
		out.append(desc)
	return out

func _process(_d: float) -> bool:
	n += 1
	if n > 30 * 260:
		return true
	if n < 3:
		return false
	var sim = main.sim
	if n == 3:
		var ua: PackedStringArray = OS.get_cmdline_user_args()
		lo = int(ua[0]) if ua.size() > 0 else 7340
		hi = int(ua[1]) if ua.size() > 1 else 7350
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
		main.set_speed(1)
		for c in ["goto 1262 1290", "yaw 200", "zoom 250", "pitch 55"]:
			main._on_cmd(c)
		return false
	main.set_process(false)
	main._process(1.0 / 30.0)
	var g: int = int(main.sim.seconds())
	if n % 15 != 0:
		return false
	var now := {}
	for gi in main.find_children("*", "GeometryInstance3D", true, false):
		if not (gi as Node3D).is_visible_in_tree():
			continue
		if gi is MultiMeshInstance3D:
			var mmx: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			if mmx == null or mmx.instance_count == 0 or mmx.visible_instance_count == 0:
				continue
		var cam: Camera3D = main.get_viewport().get_camera_3d()
		var ab: AABB = (gi as VisualInstance3D).get_aabb()
		if cam != null and not (gi is MultiMeshInstance3D) and not cam.is_position_in_frustum((gi as Node3D).global_transform * ab.get_center()):
			continue
		for d in _key(gi):
			var k := "%s|%s" % [gi.get_class(), d]
			if not now.has(k):
				now[k] = String(gi.name).left(28) + "<" + String(gi.get_parent().name).left(20)
	for k in now:
		if not seen.has(k) and g >= lo and seen.size() > 0:
			print("g%d NEW %s  e.g. %s" % [g, k, now[k]])
		seen[k] = true
	return g > hi
