// A burning streak between two world points, turned to face the camera about its own
// axis (RENDER, V3 §4.5): meteors in their last seconds (white-hot head, orange tail) and
// turret tracers. Mesh: a strip, VERTEX.x 0 (tail) .. 1 (head), VERTEX.y -1 .. 1.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec3 head = vec3(0.0, 10.0, 0.0);
uniform vec3 tail = vec3(0.0, 40.0, 0.0);
uniform float width = 1.2;
uniform vec4 head_col : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 tail_col : source_color = vec4(1.0, 0.35, 0.08, 1.0);
uniform float strength = 1.0;

varying vec2 v;

void vertex() {
	v = VERTEX.xy;
	vec3 p = mix(tail, head, VERTEX.x);
	vec3 axis = head - tail;
	float al = length(axis);
	axis = al > 0.0001 ? axis / al : vec3(0.0, 1.0, 0.0);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = normalize(cam - p);
	vec3 side = cross(axis, to_cam);
	side = length(side) > 0.0001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float w = width * mix(0.12, 1.0, pow(VERTEX.x, 2.0));
	// The head is a round blob: widen the last part and pull it past the head point.
	p += side * VERTEX.y * w + axis * smoothstep(0.9, 1.0, VERTEX.x) * width * 0.6;
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	float across = 1.0 - abs(v.y);
	float core = pow(across, 3.0);
	float glow = pow(across, 1.2) * 0.55;
	float along = v.x;
	vec3 c = mix(tail_col.rgb, head_col.rgb, pow(along, 1.8));
	float a = (core + glow) * smoothstep(0.0, 0.55, along) * strength;
	ALBEDO = c * a * (1.0 + 2.5 * smoothstep(0.85, 1.0, along) * core);
}
