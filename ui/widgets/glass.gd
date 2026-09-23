extends Node2D
## Frosted glass behind a panel: draws the blurred screen inside the panel outline.
## It is a Node2D, so containers do not lay it out, and it inherits the panel's modulate,
## so a fading panel fades its blur too. One blur shader for every panel.
##   Glass.attach(panel, chamfer)   adds a backdrop to `panel`
##   Glass.enabled = false          turns every backdrop off (setting "Glass blur")

const FhStyle = preload("res://ui/theme/fh_style.gd")

static var enabled := true
static var _material: ShaderMaterial
static var _all: Array = []

var chamfer := PackedFloat32Array([12.0, 0.0, 12.0, 0.0])

const SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float radius = 5.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 acc = texture(screen_tex, SCREEN_UV).rgb * 0.16;
	acc += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.09;
	acc += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb * 0.09;
	acc += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.09;
	acc += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb * 0.09;
	acc += texture(screen_tex, SCREEN_UV + px * 0.7).rgb * 0.07;
	acc += texture(screen_tex, SCREEN_UV - px * 0.7).rgb * 0.07;
	acc += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y) * 0.7).rgb * 0.07;
	acc += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y) * 0.7).rgb * 0.07;
	acc += texture(screen_tex, SCREEN_UV + vec2(px.x * 2.0, 0.0)).rgb * 0.05;
	acc += texture(screen_tex, SCREEN_UV - vec2(px.x * 2.0, 0.0)).rgb * 0.05;
	acc += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y * 2.0)).rgb * 0.05;
	acc += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y * 2.0)).rgb * 0.05;
	// Slight cool tint and darkening, like smoked glass.
	acc = mix(acc, vec3(0.05, 0.09, 0.15), 0.35);
	COLOR = vec4(acc, COLOR.a);
}
"""

static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material

static func attach(panel: Control, ch: Array = [12, 0, 12, 0]) -> Node2D:
	var g = load("res://ui/widgets/glass.gd").new()
	g.chamfer = PackedFloat32Array(ch)
	g.show_behind_parent = true
	g.material = material()
	g.visible = enabled
	panel.add_child(g)
	panel.resized.connect(g.queue_redraw)
	return g

static func set_enabled(on: bool) -> void:
	enabled = on
	for g in _all.duplicate():
		if is_instance_valid(g):
			g.visible = on
		else:
			_all.erase(g)

func _enter_tree() -> void:
	_all.append(self)

func _exit_tree() -> void:
	_all.erase(self)

func _draw() -> void:
	var p: Control = get_parent() as Control
	if p == null:
		return
	var pts: PackedVector2Array = FhStyle.shape(Rect2(Vector2.ZERO, p.size), chamfer)
	draw_colored_polygon(pts, Color.WHITE)
