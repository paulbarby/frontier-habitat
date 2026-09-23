// Glowing particles blended additively (sparks, spray glints, engine plume, pulses).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;
#include "res://shaders/particles_inc.gdshaderinc"
uniform float boost = 2.0;

void vertex() {
	vec4 c;
	vec3 v = VERTEX;
	particle_vertex(v, UV, MODEL_MATRIX, INSTANCE_CUSTOM, VIEW_MATRIX, c);
	VERTEX = v;
	v_col = c;
	v_uv = UV;
}

void fragment() {
	vec2 q = (v_uv - 0.5) * 2.0;
	float r = length(q);
	float a = pow(max(1.0 - r, 0.0), 1.6);
	ALBEDO = v_col.rgb * boost * a * v_col.a;
	ALPHA = 1.0;
}
