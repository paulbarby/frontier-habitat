// Ground-hugging marks (RENDER): selection and footprint rings, suit-range rings,
// network lines of the overlays. The mesh is flat; the vertex shader drapes it on the
// terrain by reading the height map, so marks follow the ground like a decal.
//   mode 0 ring (UV.y 0 inner .. 1 outer), 1 dashed ring, 2 flowing line, 3 soft disc,
//   4 ground cracks (quake, V3 §4.5), 5 scorch (fresh crater), 6 target ring with ticks (meteor forecast),
//   7 radiation zone (hatch + hard ring), 8 zone ground stain, 9 soft ground glow
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

float dh(float x) {
	return fract(sin(x * 91.345) * 47453.5453);
}

float vn(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(dh(i), dh(i + 1.0), f * f * (3.0 - 2.0 * f));
}

varying vec2 wxz;

float h2(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}
// 2D value noise in world metres (irregular blotches, no polar pattern).
float vn2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float terrain_h(vec2 xz) {
	vec2 uv = (xz / hstep + 0.5) / hn;
	return texture(heightmap, uv).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wxz = w.xz;
	w.y = terrain_h(w.xz) + lift;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	// An unset instance uniform can read as all zero in the Compatibility renderer (a decal
	// vanished, 2026-09-25): all-zero means "not set" (a fade keeps rgb at 1).
	vec4 ic = icolor == vec4(0.0) ? vec4(1.0) : icolor;
	vec4 c = color * ic;
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
	} else if (mode == 4) {
		// Jagged radial cracks with side branches, thinner and fainter outwards.
		float r = UV.y;
		float ang = UV.x * 6.2831853;
		float best = 1.0;
		for (int i = 0; i < 9; i++) {
			float fi = float(i);
			float a0 = dh(fi + 1.7) * 6.2831853;
			float reach = 0.45 + 0.55 * dh(fi + 9.1);
			float wig = (vn(r * 7.0 + fi * 13.0) - 0.5) * 0.3 + (vn(r * 23.0 + fi * 7.0) - 0.5) * 0.07;
			float da = abs(mod(ang - a0 - wig + 3.14159265, 6.2831853) - 3.14159265) * max(r, 0.05);
			float wdt = 0.011 * max(1.0, glow * 0.7) * (1.25 - r) * (1.0 - smoothstep(reach - 0.12, reach, r));
			best = min(best, da / max(wdt, 0.0001));
		}
		a = (1.0 - smoothstep(0.5, 1.0, best)) * 0.85 * (1.0 - smoothstep(0.75, 1.0, r));
	} else if (mode == 5) {
		// Scorch round a fresh crater: dark, soft, fading outwards.
		float r = UV.y;
		a = (1.0 - smoothstep(0.2, 1.0, r)) * 0.75;
	} else if (mode == 6) {
		// Meteor target: a ring, four ticks, a pulsing inner ring.
		float r = UV.y;
		float e = abs(r - 0.96);
		float ring = 1.0 - smoothstep(0.0, 0.03 * max(1.0, glow * 0.8), e);
		// At least 3-4 px wide at any zoom (critic round 22: the warning ring was a hairline).
		ring = max(ring, 1.0 - smoothstep(1.6, 2.2, e / max(fwidth(r), 1e-5)));
		float q = fract(UV.x * 4.0 + 0.125);
		float ticks = (1.0 - smoothstep(0.0, 0.02, abs(q - 0.5))) * step(0.72, r) * step(r, 0.92);
		float pr = fract(TIME * 0.8 + ipulse);
		float pulse = (1.0 - smoothstep(0.0, 0.035, abs(r - pr))) * (1.0 - pr);
		a = max(max(ring, ticks), pulse * 0.8) + (1.0 - r) * 0.08;
	} else if (mode == 7) {
		// Radiation zone (V4 4.2): a hazard-hatched disc, a pulsing boundary, denser toward the centre.
		float r = UV.y;
		// Critic round 23: irregular blotches in world space, not a spiral hatch.
		float hatch = smoothstep(0.45, 0.65, vn2(wxz * 0.12 + vec2(TIME * 0.02, 0.0)) * 0.65 + vn2(wxz * 0.45) * 0.35);
		float edge = 1.0 - smoothstep(0.0, 0.025, abs(r - 0.97));
		edge = max(edge, 1.0 - smoothstep(1.6, 2.2, abs(r - 0.97) / max(fwidth(r), 1e-5)));
		float pr = fract(TIME * 0.35 + ipulse);
		float wave = (1.0 - smoothstep(0.0, 0.03, abs(r - pr))) * (1.0 - pr) * 0.6;
		a = (1.0 - smoothstep(0.6, 1.0, r)) * (0.16 + 0.12 * hatch) + edge * (0.55 + 0.35 * sin(TIME * 2.4)) + wave;
	} else if (mode == 8) {
		// Radiation / toxic ground stain (critic round 22): blotchy, strongest at the centre,
		// a soft edge that breathes slowly; no hard ring (that one is mode 7, with the layer on).
		float r = UV.y;
		float ang = UV.x * 6.2831853;
		// Critic round 23: world-space value noise (irregular), not noise on the polar UV.
		float n1 = vn2(wxz * 0.035) * 0.6 + vn2(wxz * 0.11 + vec2(5.3, 1.7)) * 0.4;
		float n2 = vn2(wxz * 0.22 + vec2(2.1, 7.9)) * 0.6 + vn2(wxz * 0.7) * 0.4;
		float rr = r + (n1 - 0.5) * 0.16;
		float breathe = 0.5 + 0.5 * sin(TIME * 0.9 + ipulse * 6.28);
		float fill = 1.0 - smoothstep(0.35, 0.95 + 0.03 * breathe, rr);
		a = fill * (0.42 + 0.26 * n2) + (1.0 - smoothstep(0.0, 0.1, abs(rr - 0.9))) * (0.18 + 0.14 * breathe);
	} else if (mode == 9) {
		// Soft glow on the ground (hopper landing light, POI anomaly): no edge at all.
		float r = UV.y;
		a = pow(max(1.0 - r, 0.0), 1.6) * 0.95;
	} else {
		float r = UV.y;
		a = (1.0 - smoothstep(0.55, 1.0, r)) * 0.35 + smoothstep(0.85, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r)) * 0.6;
	}
	// glow > 1 (hazard marks in a dust or wind storm, critic round 8): brighter, thicker and
	// more opaque, so the mark reads through the storm grade.
	ALBEDO = c.rgb * min(glow, 1.7);
	ALPHA = clamp(a * c.a * max(1.0, glow * 0.75), 0.0, 1.0);
}
