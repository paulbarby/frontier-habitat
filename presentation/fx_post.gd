extends CanvasLayer
## Full-screen grade (RENDER). A CanvasLayer at layer -5 reads the 3D image through the
## screen texture and draws it back graded. The interface (HUD at layer 10) is drawn
## after it, so the grade never touches text or panels.

const SHADER = preload("res://shaders/post_grade.gdshader")

var rect: ColorRect
var mat: ShaderMaterial
var _time := 0.0
var _flash := 0.0

func _init() -> void:
	layer = -5
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	add_child(rect)

func set_enabled(on: bool) -> void:
	visible = on

func flash(amount: float) -> void:
	_flash = maxf(_flash, amount)

func apply(g: Dictionary, delta: float) -> void:
	_time += delta
	_flash = move_toward(_flash, 0.0, delta * 1.5)
	if g.is_empty():
		return
	var w: Color = g["warm"]
	var c: Color = g["cool"]
	mat.set_shader_parameter("warm", Vector3(w.r, w.g, w.b))
	mat.set_shader_parameter("cool", Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("contrast", g["contrast"])
	mat.set_shader_parameter("saturation", g["saturation"])
	mat.set_shader_parameter("vignette", g["vignette"])
	mat.set_shader_parameter("grain", g["grain"])
	mat.set_shader_parameter("storm", g.get("storm", 0.0))
	mat.set_shader_parameter("time", _time)
	mat.set_shader_parameter("flash", _flash)
