// Lamp halos and blinking beacons (RENDER): additive camera-facing sprites. Static
// instances; INSTANCE_CUSTOM: x phase, y blink rate (0 = steady), z size (m), w intensity.
// COLOR = lamp colour. `night` scales everything so halos only show after dusk.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;
uniform float now = 0.0;
uniform float night = 1.0;
varying vec4 v_col;
varying vec2 v_uv;

void vertex() {
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float size = INSTANCE_CUSTOM.z;
	float blink = 1.0;
	if (INSTANCE_CUSTOM.y > 0.0) {
		float ph = fract(now * INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.x);
		blink = smoothstep(0.0, 0.05, ph) * (1.0 - smoothstep(0.12, 0.3, ph));
	}
	float vis = length(MODEL_MATRIX[0].xyz) > 0.01 ? 1.0 : 0.0;
	VERTEX = c + vec3((UV - 0.5) * 2.0 * size, 0.0) + vec3(0.0, 0.0, 0.25);
	v_col = vec4(COLOR.rgb, blink * INSTANCE_CUSTOM.w * vis * mix(0.15, 1.0, night));
	v_uv = UV;
}

void fragment() {
	vec2 q = (v_uv - 0.5) * 2.0;
	float r = length(q);
	float core = exp(-r * r * 22.0);
	float halo = exp(-r * r * 4.0) * 0.35;
	float streak = exp(-abs(q.y) * 30.0) * exp(-abs(q.x) * 2.5) * 0.25;
	ALBEDO = v_col.rgb * (core * 2.5 + halo + streak) * v_col.a;
	ALPHA = 1.0;
}
