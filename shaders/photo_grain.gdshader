// V5 §4.4 paparazzi look for tabloid photos (RENDER fx_photo): film grain, a flash hot spot,
// lifted blacks, slight desaturation and contrast, vignette, a faint chromatic fringe.
shader_type canvas_item;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 d = uv - 0.5;
	float ca = 0.0025 * length(d) * 2.0;
	vec3 c;
	c.r = texture(TEXTURE, uv + d * ca).r;
	c.g = texture(TEXTURE, uv).g;
	c.b = texture(TEXTURE, uv - d * ca).b;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, 0.78);
	c = (c - 0.5) * 1.18 + 0.5;
	c += vec3(0.035, 0.03, 0.028);                         // lifted blacks
	c *= 1.0 + 0.35 * exp(-dot(d - vec2(-0.05, -0.08), d - vec2(-0.05, -0.08)) * 7.0);   // flash
	c *= 1.0 - dot(d, d) * 1.35;                           // vignette
	float g = h(floor(uv * vec2(512.0, 384.0))) - 0.5;
	c += g * 0.11;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
