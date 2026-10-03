shader_type spatial;
// Frost on structures at night on the cold planet (critic round 41; RENDER). A material_overlay pass on the
// roofs and upper walls of the instanced structures (fx_instancer.set_frost): white rime on the up-facing
// surfaces, a light rime on the walls, faded by `amount` (0 = the pass is not drawn at all).
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float amount = 0.0;
uniform vec3 frost_col : source_color = vec3(0.86, 0.91, 0.97);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec3(12.99, 78.23, 45.16))) * 43758.55);
	float b = fract(sin(dot(i + vec3(1, 0, 0), vec3(12.99, 78.23, 45.16))) * 43758.55);
	float c = fract(sin(dot(i + vec3(0, 1, 0), vec3(12.99, 78.23, 45.16))) * 43758.55);
	float d = fract(sin(dot(i + vec3(1, 1, 0), vec3(12.99, 78.23, 45.16))) * 43758.55);
	float e = fract(sin(dot(i + vec3(0, 0, 1), vec3(12.99, 78.23, 45.16))) * 43758.55);
	float g = fract(sin(dot(i + vec3(1, 0, 1), vec3(12.99, 78.23, 45.16))) * 43758.55);
	float h = fract(sin(dot(i + vec3(0, 1, 1), vec3(12.99, 78.23, 45.16))) * 43758.55);
	float k = fract(sin(dot(i + vec3(1, 1, 1), vec3(12.99, 78.23, 45.16))) * 43758.55);
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = smoothstep(0.2, 0.8, wn.y);
	float side = (1.0 - smoothstep(0.0, 0.5, abs(wn.y))) * 0.22;
	float nz = mix(0.7, 1.0, vn(wpos * 0.6));
	ALBEDO = frost_col;
	ROUGHNESS = 0.42;
	ALPHA = clamp((up * 0.88 + side) * nz, 0.0, 1.0) * amount;
}
