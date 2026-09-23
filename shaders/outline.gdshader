// Selection outline (RENDER): inverted hull. Back faces pushed out along the normal by a
// width that stays constant on screen; drawn behind the model, so only a rim shows.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 color : source_color = vec4(0.25, 0.9, 1.0, 1.0);
uniform float width_px = 2.5;

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float dist = max(-vp.z, 0.1);
	float w = width_px / VIEWPORT_SIZE.y * dist * 2.0 / PROJECTION_MATRIX[1][1];
	vp.xyz += vn * w;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float pulse = 0.8 + 0.2 * sin(TIME * 4.0);
	ALBEDO = color.rgb * (1.2 * pulse);
}
