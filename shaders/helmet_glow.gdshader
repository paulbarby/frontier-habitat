// Helmet lamp halo of suited colonists at night (RENDER): a camera-facing additive glow,
// pulled a little towards the camera so the helmet does not hide it.
//   INSTANCE COLOR = lamp colour; INSTANCE_CUSTOM.x = halo size (m), 0 = off
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform float intensity = 1.0;

varying vec4 col;

void vertex() {
	col = COLOR;
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = INSTANCE_CUSTOM.x;
	VERTEX = c + vec3(VERTEX.xy * s, 0.0) + normalize(-c) * 0.3;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float q = dot(d, d);
	float a = exp(-q * 4.5) * (1.0 - smoothstep(0.55, 1.0, q)) * 0.7 + exp(-q * 60.0) * 1.8;
	ALBEDO = col.rgb * a * intensity;
}
