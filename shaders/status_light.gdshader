// Status lights of doors and airlocks (RENDER, V3.1): the colour comes from the instance's
// custom colour (green free, amber busy or cycling, red locked); no custom = the base colour.
shader_type spatial;
render_mode cull_back, unshaded, shadows_disabled;

uniform vec4 base : source_color = vec4(0.37, 0.88, 0.48, 1.0);
uniform float energy = 2.2;

varying vec3 col;

void vertex() {
	col = INSTANCE_CUSTOM.rgb;
	if (dot(col, col) < 0.0001) {
		col = base.rgb;
	}
}

void fragment() {
	ALBEDO = col * (0.55 + 0.25 * min(energy, 3.0));
}
