// A structure being built (RENDER): solid below the build line, a hot weld line at it.
// Everything above the line is left to the hologram next pass (shaders/hologram.gdshader).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool use_vc = false;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform vec4 line_color : source_color = vec4(1.0, 0.72, 0.3, 1.0);
uniform float build_y = 100000.0;
uniform float tint_dark = 0.0;

varying vec3 wp;
varying vec3 vc;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vc = use_vc ? COLOR.rgb : vec3(1.0);
}

void fragment() {
	if (wp.y > build_y) {
		discard;
	}
	vec3 a = albedo.rgb * vc;
	a = mix(a, a * vec3(0.35, 0.3, 0.28), tint_dark);
	ALBEDO = a;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	float edge = 1.0 - smoothstep(0.0, 0.22, build_y - wp.y);
	EMISSION = emission.rgb * emission_energy + line_color.rgb * edge * 4.0;
}
