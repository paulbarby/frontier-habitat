// Holographic ghost (RENDER): fresnel rim, moving scan lines and a fine grid, drawn
// only above `holo_min_y` (world height). Plain uniforms: instance uniforms do not reach
// per-surface override materials in the 4.4 Compatibility renderer (tested). Used for the placement ghost (green / red),
// for blueprints, for the unbuilt part of a construction site and for demolition.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float strength = 1.0;
uniform float scan_speed = 0.9;
uniform float holo_min_y = -100000.0;
uniform float holo_fade = 1.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (wp.y < holo_min_y) {
		discard;
	}
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	float scan = smoothstep(0.55, 0.95, fract(wp.y * 2.2 - TIME * scan_speed));
	float fine = smoothstep(0.35, 0.5, abs(fract(wp.y * 9.0) - 0.5)) * 0.25;
	vec3 g = abs(fract(wp * 1.25) - 0.5);
	float grid = 1.0 - smoothstep(0.0, 0.04, min(min(g.x, g.y), g.z));
	float flick = 0.92 + 0.08 * sin(TIME * 23.0 + wp.y * 3.0);
	float a = (0.1 + fres * 0.55 + scan * 0.22 + grid * 0.18 + fine * 0.3) * strength * flick * holo_fade;
	float base = 1.0 - smoothstep(0.0, 0.35, wp.y - holo_min_y);
	a += base * 0.35 * step(-10000.0, holo_min_y) * strength * holo_fade;
	ALBEDO = color.rgb * (1.1 + fres * 0.8 + scan * 0.5);
	ALPHA = clamp(a, 0.0, 0.95);
}
