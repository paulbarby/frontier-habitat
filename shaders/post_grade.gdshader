// Full-screen colour grade (RENDER): split toning by time of day, contrast, saturation,
// a soft vignette and very light film grain. Drawn on a CanvasLayer BELOW the interface
// (presentation/fx_post.gd), so it grades the 3D image and never touches the UI.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 warm = vec3(1.03, 1.0, 0.95);
uniform vec3 cool = vec3(0.95, 0.985, 1.05);
uniform float contrast = 1.07;
uniform float saturation = 1.05;
uniform float vignette = 0.22;
uniform float grain = 0.012;
uniform float storm = 0.0;
uniform float time = 0.0;
uniform float flash = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	// Split tone: cool shadows, warm highlights.
	c *= mix(cool, warm, smoothstep(0.08, 0.75, l));
	// S-curve contrast around mid grey.
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);
	c = c * c * (3.0 - 2.0 * c) * 0.18 + c * 0.82;
	// Saturation.
	float l2 = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l2), c, saturation);
	// Dust storm: flatten toward orange haze.
	c = mix(c, vec3(0.62, 0.42, 0.28) * (0.6 + l2 * 0.6), storm * 0.35);
	// Vignette (wider than tall).
	vec2 uv = (SCREEN_UV - 0.5) * vec2(1.25, 1.0);
	float v = 1.0 - smoothstep(0.25, 0.95, length(uv)) * vignette * 1.6;
	c *= v;
	// Grain: luminance-weighted so black stays black.
	float n = hash12(FRAGCOORD.xy + fract(time * 7.3) * 431.0) - 0.5;
	c += n * grain * (0.35 + l2);
	c += vec3(flash);
	COLOR = vec4(c, 1.0);
}
