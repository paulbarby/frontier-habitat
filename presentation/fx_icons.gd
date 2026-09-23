extends Node3D
## Status badges above structures (RENDER): one MultiMesh of camera-facing quads drawn by
## shaders/status_icon.gdshader, so every badge on the map costs one draw call.
## Icon ids: 0 no power, 1 no water, 2 no air, 3 broken, 4 output full, 5 deposit empty,
## 6 waiting for materials, 7 too far / out of reach, 8 switched off, 9 construction
## progress ring, 10 alert, 11 removing.

const SHADER = preload("res://shaders/status_icon.gdshader")

var view
var mmi: MultiMeshInstance3D
var mat: ShaderMaterial
var _count := 0

func setup(v) -> void:
	view = v
	mmi = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = 64
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = 20
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-600, -100, -600), Vector3(1500, 400, 1500))
	add_child(mmi)

## list: [{pos: Vector3, icon: int, color: Color, progress: float, pulse: float}]
func set_icons(list: Array) -> void:
	var mm: MultiMesh = mmi.multimesh
	if list.size() > mm.instance_count:
		mm.visible_instance_count = 0
		mm.instance_count = maxi(list.size(), mm.instance_count * 2)
	for i in list.size():
		var e: Dictionary = list[i]
		mm.set_instance_transform(i, Transform3D(Basis(), e["pos"]))
		mm.set_instance_color(i, e["color"])
		mm.set_instance_custom_data(i, Color(float(e["icon"]), float(e.get("progress", 0.0)), float(e.get("pulse", 0.0)), 1.0))
	mm.visible_instance_count = list.size()
	_count = list.size()
	mmi.visible = view.overlay == "" or view.overlay == "walk"
