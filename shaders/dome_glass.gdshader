// V5 super dome glass (RENDER; ART-B §6.1, §7.6, critic round 26). A faint tint facing the camera,
// the sky reflected at grazing angles (opacity 0.12 facing -> 0.85 grazing, ART-B §9), a sun glint,
// and by night a warm emissive rim at grazing angles so the shell carries the city lights.
// Unshaded (the reflection and glint are computed here); double-sided; drawn in its own sorted
// pass before the other transparent surfaces (render_priority -2), no depth write.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.769, 0.871, 0.910);  // #C4DEE8 (ART-B §9)
uniform vec3 sky_zenith : source_color = vec3(0.52, 0.42, 0.36);
uniform vec3 sky_horizon : source_color = vec3(0.92, 0.74, 0.56);
uniform vec3 sun_dir = vec3(0.4, 0.6, 0.3);                    // world, towards the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.8);
uniform float night = 0.0;                                    // 0 day .. 1 night
uniform vec3 rim_color : source_color = vec3(1.0, 0.867, 0.702); // #FFDDB3 (ART-B §9: linear 1.0, 0.72, 0.45)
uniform float alpha_face = 0.12;
uniform float alpha_graze = 0.85;
uniform float fog_far = 3000.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 v = normalize(cam - wpos);
	vec3 n = normalize(wnrm);
	if (dot(n, v) < 0.0) {
		n = -n;   // seen from inside: the inner face
	}
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	// ART-B §9 (the Blender preview CRITIC scored): opacity from Layer Weight "Facing" (blend 0.45),
	// the sky-colour mix from Schlick with F0 0.08.
	float F = 1.0 - pow(ndv, 0.9);
	float A = mix(alpha_face, alpha_graze, F);
	float fres = 0.08 + 0.92 * pow(1.0 - ndv, 5.0);
	// The reflected sky: a vertical gradient from the horizon to the zenith, darker at night.
	vec3 r = reflect(-v, n);
	float up = clamp(r.y, -0.2, 1.0);
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.7, up));
	sky = mix(sky, sky * 0.08 + vec3(0.02, 0.025, 0.05), night);
	// Sun glint by day.
	vec3 sd = normalize(sun_dir);
	float glint = pow(max(dot(r, sd), 0.0), 220.0) * (1.0 - night) * step(0.0, sd.y);
	vec3 col = mix(tint * mix(0.55, 0.12, night), sky, clamp(fres * 1.25, 0.0, 1.0)) + sun_color * glint * 3.0;
	// Night: the warm rim (city light caught at grazing angles), strongest low on the dome.
	float low = 1.0 - smoothstep(4.0, 38.0, wpos.y - NODE_POSITION_WORLD.y);
	vec3 rim = rim_color * A * 0.8 * night * (0.55 + 0.45 * low);
	// A faint glow at the crown by night (the city light rising under the glass).
	float crown = smoothstep(18.0, 38.0, wpos.y - NODE_POSITION_WORLD.y);
	rim += rim_color * crown * 0.12 * night;
	ALBEDO = col + rim;
	ALPHA = clamp(A + glint * 0.6, 0.0, 0.95);
}
