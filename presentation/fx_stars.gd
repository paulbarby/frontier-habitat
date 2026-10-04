extends MultiMeshInstance3D
## Bright stars in their real patterns (V5 §19.10, Paul 2026-10-04): Orion, the Plough (Ursa Major), Cassiopeia,
## Cygnus, Scorpius, the Southern Cross, Leo, the Pleiades and the brightest single stars. Positions are J2000 right
## ascension / declination (public-domain catalogue values, rounded); the colony's sky turns round its pole with the
## time of day. Drawn as additive billboards 1,000 m from the camera, over the sky shader's faint random stars, by
## night and in the airless day sky; the ground and the buildings hide them (depth test).
## Original names (the colony's names for the patterns) are in NAMES for the UI.

const R := 1000.0
const LAT := 35.0             # deg: the colony's latitude (the pole stands this high over the north horizon)
## [right ascension h, declination deg, magnitude]
const CAT := [
	# Orion (the Hunter)
	[5.919, 7.41, 0.5], [5.242, -8.20, 0.13], [5.419, 6.35, 1.64], [5.796, -9.67, 2.06], [5.679, -1.94, 1.77],
	[5.604, -1.20, 1.69], [5.533, -0.30, 2.23], [5.585, 9.93, 3.4],
	# the Plough (Ursa Major)
	[11.062, 61.75, 1.8], [11.031, 56.38, 2.37], [11.897, 53.69, 2.44], [12.257, 57.03, 3.31], [12.900, 55.96, 1.77],
	[13.399, 54.93, 2.27], [13.792, 49.31, 1.86],
	# Cassiopeia
	[0.675, 56.54, 2.24], [0.153, 59.15, 2.28], [0.945, 60.72, 2.47], [1.430, 60.24, 2.68], [1.907, 63.67, 3.37],
	# Cygnus (the Swan)
	[20.690, 45.28, 1.25], [20.370, 40.26, 2.23], [20.770, 33.97, 2.48], [19.750, 45.13, 2.87], [19.512, 27.96, 3.05],
	# Scorpius
	[16.490, -26.43, 1.06], [17.560, -37.10, 1.62], [17.622, -43.00, 1.86], [16.006, -22.62, 2.29], [16.091, -19.81, 2.62],
	[16.836, -34.29, 2.29], [17.512, -37.30, 2.7], [15.981, -26.11, 2.89], [16.598, -28.22, 2.82], [16.864, -38.05, 3.0],
	[16.910, -42.36, 3.6], [17.203, -43.24, 3.3], [17.708, -39.03, 2.4],
	# the Southern Cross (Crux)
	[12.443, -63.10, 0.77], [12.795, -59.69, 1.25], [12.519, -57.11, 1.59], [12.252, -58.75, 2.79],
	# Leo
	[10.139, 11.97, 1.35], [11.818, 14.57, 2.14], [10.333, 19.84, 2.0], [11.235, 20.52, 2.56], [11.237, 15.43, 3.3],
	[10.122, 16.76, 3.5], [10.278, 23.42, 3.4], [9.764, 23.77, 2.98], [9.879, 26.01, 3.9],
	# the Pleiades
	[3.791, 24.11, 2.87], [3.819, 24.05, 3.6], [3.747, 24.11, 3.7], [3.763, 24.37, 3.9], [3.772, 23.95, 4.1], [3.753, 24.47, 4.3],
	# bright single stars
	[6.752, -16.72, -1.46], [6.399, -52.70, -0.74], [18.616, 38.78, 0.03], [14.261, 19.18, -0.05], [5.278, 46.00, 0.08],
	[7.655, 5.22, 0.34], [19.846, 8.87, 0.77], [4.599, 16.51, 0.85], [13.420, -11.16, 0.97], [7.755, 28.03, 1.14],
	[7.577, 31.89, 1.58], [22.961, -29.62, 1.16], [2.530, 89.26, 1.98], [14.660, -60.83, -0.27], [1.629, -57.24, 0.46],
]
## The colony's own names for the patterns (original names, §19.10), in CAT order of first star.
const NAMES := {"The Hunter": 0, "The Plough": 8, "The Throne": 15, "The Swan": 20, "The Scorpion": 25,
	"The Cross": 39, "The Lion": 43, "The Seven Sisters": 52}

var _mat: ShaderMaterial
var _dirs: Array = []

func _ready() -> void:
	name = "Constellations"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mmx := MultiMesh.new()
	mmx.transform_format = MultiMesh.TRANSFORM_3D
	mmx.use_colors = true
	mmx.mesh = q
	mmx.instance_count = CAT.size()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float vis = 0.0;
varying vec4 v_col;
void vertex() {
	v_col = COLOR;
	// billboard: the quad faces the camera, its size from the instance scale
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 w = c + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float core = exp(-r * r * 9.0);
	float halo = exp(-r * r * 2.2) * 0.25;
	ALBEDO = v_col.rgb * (core + halo) * vis * v_col.a * 2.6;
	ALPHA = 1.0;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material_override = _mat
	multimesh = mmx
	for i in CAT.size():
		var e: Array = CAT[i]
		var ra: float = float(e[0]) / 24.0 * TAU
		var de: float = deg_to_rad(float(e[1]))
		_dirs.append(Vector3(cos(de) * cos(ra), sin(de), cos(de) * sin(ra)))
		var m: float = float(e[2])
		var br: float = clampf(pow(2.512, (2.0 - m) * 0.5) * 0.45, 0.25, 1.0)
		# a slight colour by the star (blue-white bright ones, warm red giants: Betelgeuse, Antares, Aldebaran, Arcturus)
		var col := Color(0.92, 0.95, 1.0)
		if i in [0, 25, 61, 65]:
			col = Color(1.0, 0.72, 0.5)
		mmx.set_instance_color(i, Color(col.r, col.g, col.b, br))
	custom_aabb = AABB(Vector3(-R * 1.2, -R * 1.2, -R * 1.2), Vector3(R * 2.4, R * 2.4, R * 2.4))

## cam: camera position; day_frac 0..1 (the sky turns once a day); vis 0..1 (night, or the airless day).
func update_sky(cam: Vector3, day_frac: float, v: float) -> void:
	visible = v > 0.01
	_mat.set_shader_parameter("vis", v)
	if not visible:
		return
	global_position = cam
	# the pole tilted LAT deg over the north (-Z) horizon, the sky turning round it with the day
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(90.0 - LAT))
	var spin := Basis(Vector3.UP, day_frac * TAU)
	var b: Basis = tilt * spin
	for i in _dirs.size():
		var m: float = float(CAT[i][2])
		var size: float = clampf(16.0 - m * 3.0, 6.0, 22.0)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), b * (_dirs[i] as Vector3) * R))
