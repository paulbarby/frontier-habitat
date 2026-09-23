// Ground-hugging marks (RENDER): selection and footprint rings, suit-range rings,
// network lines of the overlays. The mesh is flat; the vertex shader drapes it on the
// terrain by reading the height map, so marks follow the ground like a decal.
//   mode 0 ring (UV.y 0 inner .. 1 outer), 1 dashed ring, 2 flowing line, 3 soft disc
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform float hstep = 2.0;
uniform float hn = 129.0;
uniform vec4 color : source_color = vec4(0.25, 0.9, 1.0, 1.0);
uniform int mode = 0;
uniform float dashes = 48.0;
uniform float speed = 0.0;
uniform float lift = 0.12;
uniform float glow = 1.0;
instance uniform vec4 icolor : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float ipulse = 0.0;

float terrain_h(vec2 xz) {
	vec2 uv = (xz / hstep + 0.5) / hn;
	return texture(heightmap, uv).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w.y = terrain_h(w.xz) + lift;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec4 c = color * icolor;
	float a = 0.0;
	if (mode == 0) {
		float e = min(UV.y, 1.0 - UV.y);
		a = smoothstep(0.0, 0.25, e) * 0.85 + 0.15;
		float pulse = 0.75 + 0.25 * sin(TIME * 3.0 + ipulse * 6.28);
		a *= pulse;
	} else if (mode == 1) {
		float e = min(UV.y, 1.0 - UV.y);
		float d = step(0.45, fract(UV.x * dashes - TIME * speed));
		a = smoothstep(0.0, 0.3, e) * d * 0.9;
	} else if (mode == 2) {
		float across = abs(UV.y - 0.5) * 2.0;
		float core = 1.0 - smoothstep(0.35, 1.0, across);
		float flow = smoothstep(0.0, 0.25, fract(UV.x * 0.35 - TIME * speed)) * (1.0 - smoothstep(0.35, 0.6, fract(UV.x * 0.35 - TIME * speed)));
		a = core * (0.45 + 0.55 * flow);
	} else {
		float r = UV.y;
		a = (1.0 - smoothstep(0.55, 1.0, r)) * 0.35 + smoothstep(0.85, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r)) * 0.6;
	}
	ALBEDO = c.rgb * glow;
	ALPHA = clamp(a * c.a, 0.0, 1.0);
}
