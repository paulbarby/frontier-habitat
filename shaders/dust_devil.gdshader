// A turning dust column (RENDER, V3 §4.5 dust devil). Mesh: an open cylinder, height 1,
// radius 1 (scaled by the node); the column narrows at the ground, leans with the wind and
// its streaky dust turns round the axis.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 dust : source_color = vec4(0.66, 0.48, 0.34, 0.55);
uniform float strength = 1.0;
uniform float spin = 2.4;
uniform vec3 lean = vec3(0.25, 0.0, 0.1);

varying vec3 lp;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
	float y = VERTEX.y;
	float r = mix(0.25, 1.0, pow(y, 0.6)) * (1.0 + 0.12 * sin(y * 9.0 + TIME * 3.0));
	VERTEX.xz *= r;
	VERTEX += lean * y * y;
}

void fragment() {
	float ang = atan(lp.z, lp.x);
	float y = lp.y;
	vec2 q = vec2(ang * 2.0 + TIME * spin - y * 3.0, y * 6.0 - TIME * 1.5);
	float s = n2(q * vec2(1.6, 1.0)) * 0.6 + n2(q * vec2(4.0, 2.5)) * 0.4;
	float a = smoothstep(0.35, 0.8, s) * dust.a * strength;
	a *= smoothstep(0.0, 0.08, y) * (1.0 - smoothstep(0.7, 1.0, y));
	ALBEDO = dust.rgb * (0.75 + 0.35 * s);
	ALPHA = clamp(a, 0.0, 1.0);
}
