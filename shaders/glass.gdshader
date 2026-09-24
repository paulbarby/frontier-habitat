// Interior glass (RENDER, critic round 8): holo cones, clean-room partitions, specimen cases.
// Transparent (alpha about 0.3), cyan tint, a bright fresnel edge so the shape still reads.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.62, 0.86, 0.95, 0.30);
uniform vec3 edge_col : source_color = vec3(0.45, 0.9, 1.0);
uniform float edge = 0.9;

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	EMISSION = edge_col * f * edge;
	ALPHA = clamp(tint.a + f * 0.45, 0.0, 0.85);
}