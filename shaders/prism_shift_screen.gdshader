// V5 §4.5 PRISM SHIFT arcade cabinet screen (RENDER; ART-B §7.1): the attract loop of Paul's neon
// tunnel racer. A hexagonal neon tunnel rushing towards the viewer, its rings cycling magenta,
// cyan and gold, a glowing prism ship weaving near the bottom, a speed streak field, a blinking
// "insert coin" bar, CRT scan lines and a vignette. UV 0..1 (u to the player's right, v up).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform float brightness = 1.7;

float hex_d(vec2 p) {
	p = abs(p);
	return max(p.x * 0.866025 + p.y * 0.5, p.y);
}

vec3 neon(float k) {
	vec3 a = vec3(1.0, 0.31, 0.85);   // magenta
	vec3 b = vec3(0.2, 0.95, 1.0);    // cyan
	vec3 c = vec3(1.0, 0.8, 0.25);    // gold
	float f = fract(k);
	return f < 0.333 ? mix(a, b, f * 3.0) : (f < 0.666 ? mix(b, c, (f - 0.333) * 3.0) : mix(c, a, (f - 0.666) * 3.0));
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	float t = TIME;
	// Godot's UV.y runs down the quad (the title bar showed at the bottom): v up as ART-B specified.
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 p = (uv - vec2(0.5, 0.56)) * vec2(1.33, 1.0);
	// The tunnel bends: its vanishing point drifts.
	p -= vec2(sin(t * 0.7) * 0.06, cos(t * 0.5) * 0.04);
	float d = hex_d(p) + 1e-3;
	float depth = 0.12 / d + t * 2.4;
	float dz = abs(fract(depth + 0.5) - 0.5);
	float ring = 1.0 - smoothstep(0.0, max(fwidth(depth) * 3.0, 0.04), dz);
	float ang = atan(p.y, p.x);
	float spoke = 1.0 - smoothstep(0.0, 0.012, abs(fract(ang / 1.0472 + 0.5) - 0.5) * d);
	vec3 col = vec3(0.0);
	col += neon(floor(depth + 0.5) * 0.17 + t * 0.05) * ring * (0.25 + 0.9 * smoothstep(0.02, 0.5, d));
	col += neon(t * 0.1 + 0.5) * spoke * 0.5 * smoothstep(0.05, 0.4, d);
	// The tunnel walls: a dim neon haze that brightens towards the viewer.
	col += neon(depth * 0.05 + t * 0.03) * 0.10 * smoothstep(0.05, 0.6, d);
	// Speed streaks.
	float streak = step(0.985, fract(sin(floor(ang * 40.0) * 91.7) * 43758.5)) * smoothstep(0.1, 0.5, d) * fract(-depth * 0.5);
	col += vec3(0.8, 0.9, 1.0) * streak * 0.8;
	// The core glow at the vanishing point.
	col += neon(t * 0.2) * 0.06 / (d * 8.0 + 0.2);
	// The prism ship: a glowing triangle near the bottom, weaving left and right.
	vec2 sp = (uv - vec2(0.5 + sin(t * 1.3) * 0.18, 0.24 + sin(t * 2.1) * 0.02)) * vec2(1.33, 1.0);
	float roll = sin(t * 1.3 + 1.2) * 0.35;
	sp = mat2(vec2(cos(roll), sin(roll)), vec2(-sin(roll), cos(roll))) * sp;
	vec2 a = vec2(0.0, 0.10);
	vec2 b = vec2(-0.11, -0.05);
	vec2 c = vec2(0.11, -0.05);
	float e = min(min(seg(sp, a, b), seg(sp, b, c)), seg(sp, c, a));
	float inside = step(0.0, (b.x - a.x) * (sp.y - a.y) - (b.y - a.y) * (sp.x - a.x)) * step(0.0, (c.x - b.x) * (sp.y - b.y) - (c.y - b.y) * (sp.x - b.x)) * step(0.0, (a.x - c.x) * (sp.y - c.y) - (a.y - c.y) * (sp.x - c.x));
	vec3 prism = mix(vec3(0.2, 0.95, 1.0), vec3(1.0, 0.31, 0.85), clamp(sp.x * 6.0 + 0.5, 0.0, 1.0));
	col = mix(col, prism * 0.35 + vec3(0.05), inside * 0.9);
	col += vec3(1.0) * smoothstep(0.006, 0.0, e) + prism * smoothstep(0.03, 0.0, e) * 0.6;
	// Engine trail under the ship.
	float trail = smoothstep(0.025, 0.0, abs(sp.x)) * smoothstep(-0.05, -0.22, sp.y) * step(sp.y, -0.05);
	col += vec3(1.0, 0.5, 0.2) * trail * (0.6 + 0.4 * sin(t * 30.0));
	// Title bar and blinking "insert coin" bar.
	col += neon(t * 0.3) * step(0.9, uv.y) * step(uv.y, 0.94) * step(0.2, uv.x) * step(uv.x, 0.8) * 0.8;
	col += vec3(1.0, 0.85, 0.3) * step(0.04, uv.y) * step(uv.y, 0.07) * step(0.35, uv.x) * step(uv.x, 0.65) * step(0.5, fract(t * 1.2));
	// CRT: scan lines, a slow roll bar, vignette.
	col *= 0.82 + 0.18 * sin(uv.y * 360.0);
	col *= 0.92 + 0.08 * smoothstep(0.0, 0.1, abs(fract(uv.y - t * 0.15) - 0.5));
	vec2 vg = uv - 0.5;
	col *= 1.0 - dot(vg, vg) * 1.2;
	// Unshaded: the colour is the albedo (EMISSION is not added in unshaded mode).
	ALBEDO = col * brightness;
}
