// Burst and muzzle flash (RENDER, fx_hazards): a camera-facing additive glow that grows as it
// fades. k = 1 at the start .. 0 at the end.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec4 col : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float size = 4.0;
uniform float k = 1.0;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = size * (0.55 + 0.45 * (1.0 - k * k));
	VERTEX = c + vec3(VERTEX.xy * s, 0.0);
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float q = dot(d, d);
	float a = exp(-q * 3.0) * (1.0 - smoothstep(0.6, 1.0, q)) + exp(-q * 30.0) * 2.0;
	ALBEDO = col.rgb * a * k * 2.2;
}