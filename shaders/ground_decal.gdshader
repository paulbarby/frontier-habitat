// Ground-hugging marks (RENDER): selection and footprint rings, suit-range rings,
// network lines of the overlays. The mesh is flat; the vertex shader drapes it on the
// terrain by reading the height map, so marks follow the ground like a decal.
//   mode 0 ring (UV.y 0 inner .. 1 outer), 1 dashed ring, 2 flowing line, 3 soft disc,
//   4 ground cracks (quake, V3 §4.5), 5 scorch (fresh crater), 6 target ring with ticks (meteor forecast)
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
		float q = fract(UV.x * 4.0 + 0.125);
		float ticks = (1.0 - smoothstep(0.0, 0.02, abs(q - 0.5))) * step(0.72, r) * step(r, 0.92);
		float pr = fract(TIME * 0.8 + ipulse);
		float pulse = (1.0 - smoothstep(0.0, 0.035, abs(r - pr))) * (1.0 - pr);
		a = max(max(ring, ticks), pulse * 0.8) + (1.0 - r) * 0.08;
	} else {
		float r = UV.y;
		a = (1.0 - smoothstep(0.55, 1.0, r)) * 0.35 + smoothstep(0.85, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r)) * 0.6;
	}
	// glow > 1 (hazard marks in a dust or wind storm, critic round 8): brighter, thicker and
	// more opaque, so the mark reads through the storm grade.
	ALBEDO = c.rgb * min(glow, 1.7);
	ALPHA = clamp(a * c.a * max(1.0, glow * 0.75), 0.0, 1.0);
}
