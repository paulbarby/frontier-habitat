// Soft particles blended normally (smoke, steam, dust). See particles_inc.gdshaderinc.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;
#include "res://shaders/particles_inc.gdshaderinc"
uniform vec3 light_col : source_color = vec3(1.0);
uniform float light_amt = 0.6;

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
	float n = 0.75 + 0.25 * sin(q.x * 5.0 + v_col.a * 9.0) * sin(q.y * 4.0 + 1.7);
	float a = (1.0 - smoothstep(0.25, 1.0, r)) * n;
	vec3 lit = v_col.rgb * mix(vec3(1.0), light_col, light_amt) * (0.85 + 0.3 * (1.0 - q.y) * 0.5);
	ALBEDO = lit;
	ALPHA = clamp(a * v_col.a, 0.0, 1.0);
}
