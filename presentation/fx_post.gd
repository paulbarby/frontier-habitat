extends CanvasLayer
## Full-screen grade (RENDER). A CanvasLayer at layer -5 reads the 3D image through the
## screen texture and draws it back graded. The interface (HUD at layer 10) is drawn
## after it, so the grade never touches text or panels.

const SHADER = preload("res://shaders/post_grade.gdshader")

var rect: ColorRect
var mat: ShaderMaterial
var _time := 0.0
var _flash := 0.0
var _flash_col := Color(1, 1, 1)
var flare := 0.0                # solar flare grade 0..1 (fx_hazards)
var wind := 0.0                 # wind storm 0..1 (fx_hazards): screen streaks

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

func flash(amount: float, col: Color = Color(1, 1, 1)) -> void:
	if amount >= _flash:
		_flash_col = col
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
	mat.set_shader_parameter("flash_col", Vector3(_flash_col.r, _flash_col.g, _flash_col.b))
	mat.set_shader_parameter("flare", flare)
	mat.set_shader_parameter("aurora", flare)
	mat.set_shader_parameter("wind", wind)
