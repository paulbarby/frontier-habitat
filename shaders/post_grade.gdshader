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
uniform float flare = 0.0;      // solar flare: violet-green grade
uniform vec3 flash_col = vec3(1.0);
uniform float wind = 0.0;       // wind storm: fast pale streaks racing across the screen
uniform float aurora = 0.0;     // solar flare: moving green-violet curtains over the view

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
	// Solar flare: a violet-green cast, strongest in the highlights.
	c = mix(c, c * vec3(0.86, 1.08, 0.98) + vec3(0.05, 0.0, 0.08) * (1.0 - l2), flare * 0.6);
	// Solar flare seen from above (critic round 8): slow green-violet curtains over the whole
	// view, stronger at the top of the screen (the sky side), additive and faint.
	if (aurora > 0.001) {
		vec2 au = SCREEN_UV * vec2(3.0, 1.0);
		float band = sin(au.x * 2.1 + time * 0.23 + sin(au.y * 3.0 + time * 0.17) * 1.6);
		float band2 = sin(au.x * 3.7 - time * 0.31 + au.y * 2.0);
		float curtain = smoothstep(0.35, 1.0, band) * 0.7 + smoothstep(0.55, 1.0, band2) * 0.5;
		vec3 ac = mix(vec3(0.15, 1.0, 0.55), vec3(0.65, 0.25, 1.0), smoothstep(0.2, 0.9, SCREEN_UV.y + band2 * 0.15));
		c += ac * curtain * aurora * (0.22 + 0.26 * (1.0 - SCREEN_UV.y));
	}
	// Wind storm (critic round 8): thin pale streaks that race across the view, unlike the
	// thick orange dust storm.
	if (wind > 0.001) {
		vec2 w = vec2(SCREEN_UV.x * 1.6 - time * 2.6, SCREEN_UV.y * 60.0 + SCREEN_UV.x * 9.0);
		float row = floor(w.y);
		float r1 = hash12(vec2(row, 7.0));
		float seg = fract(w.x * (0.6 + r1 * 0.8) + r1 * 13.0 - time * (0.8 + r1));
		float streak = smoothstep(0.0, 0.05, seg) * (1.0 - smoothstep(0.08, 0.35, seg)) * step(0.55, r1);
		streak *= smoothstep(0.0, 0.3, fract(w.y)) * (1.0 - smoothstep(0.5, 1.0, fract(w.y)));
		c = mix(c, vec3(0.92, 0.84, 0.72), streak * wind * 0.42);
		c = mix(c, vec3(dot(c, vec3(0.33))) * vec3(1.02, 0.98, 0.92), wind * 0.18);
	}
	c += flash_col * flash;
	COLOR = vec4(c, 1.0);
}
