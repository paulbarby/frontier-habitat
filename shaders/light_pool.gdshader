// Warm light pools on room floors under the ceiling lamps (RENDER, V3_DESIGN §7.3): the
// cheap stand-in for a real light in every room. One MultiMesh for all of them. Additive,
// depth-tested (furniture hides the pool under it), no fog, no shadows.
//   INSTANCE COLOR = light colour x strength; INSTANCE_CUSTOM.x = radius (m)
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity = 1.0;

varying vec4 col;

void vertex() {
	col = COLOR;
	float r = max(INSTANCE_CUSTOM.x, 0.1);
	VERTEX.xz *= r;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float q = dot(d, d);
	float a = exp(-q * 3.2) * (1.0 - smoothstep(0.75, 1.0, q));
	ALBEDO = col.rgb * a * intensity;
}
