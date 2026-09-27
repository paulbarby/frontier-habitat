extends Node3D
## Terrain v4 light (RENDER, V4_DESIGN §1.1) on SIM's 2,560 m planet (sim.world.version >= 4).
## fx_terrain draws sim.world itself; this node adds the horizon shadows:
##
## - HORIZON: SIM's layout (sim.world.horizon: the sun bearings of the day, b = bearing / PI *
##   (bins - 1), horizon elevation in degrees). The view bakes the same quantity once on the GPU
##   from sim.world.heights at 8 m cells (SIM's map is 32 m, for the solar output), so the shadow
##   edge on a crater floor is a few metres wide. One extra bin holds how much sky a point sees.
## - The sun is SIM's (sim.world.sun_angles: 32 deg at noon). fx_sky takes it through sun_fn.
## - Objects in a shadowed crater: world_view dims the key light and the ambient by SIM's
##   sun_vis / the sky openness at the camera focus (faded out as the camera rises); the terrain
##   shader undoes that for itself (key_comp, amb_comp).
##
## Also the evidence staging (`v4stage`): a small base with lamps on a deep crater floor, view-side.

const Models = preload("res://presentation/models.gd")
const BAKE_SHADER = preload("res://shaders/horizon_bake.gdshader")
const HZ_CELL := 4.0          # the view's bake (SIM's own map is 32 m)

var sim
var active := false
var hz_on := false
var hz_side := 0
var bins := 13
var vp: SubViewport
var hz_tex: Texture2D
var timings := {}
var _bake_frames := -1

func setup(s) -> void:
	sim = s
	var w = sim.world
	if int(w.get("version")) < 4:
		return
	var t0: int = Time.get_ticks_usec()
	bins = int(w.hz_bins) if int(w.hz_bins) > 1 else 13
	hz_side = int(ceil(float(w.size) / HZ_CELL)) + 1
	# Heights as a half-float texture (641 x 641 on the v4 map).
	var img := Image.create_from_data(int(w.hn), int(w.hn), false, Image.FORMAT_RF, (w.heights as PackedFloat32Array).to_byte_array())
	img.convert(Image.FORMAT_RH)
	var htex := ImageTexture.create_from_image(img)
	vp = SubViewport.new()
	vp.name = "HorizonBake"
	vp.size = Vector2i(hz_side * 4, hz_side)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.use_hdr_2d = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(hz_side * 4, hz_side)
	var m := ShaderMaterial.new()
	m.shader = BAKE_SHADER
	m.set_shader_parameter("hmap", htex)
	m.set_shader_parameter("hn", float(w.hn))
	m.set_shader_parameter("hstep", float(w.hstep))
	m.set_shader_parameter("side", float(hz_side))
	m.set_shader_parameter("cell", HZ_CELL)
	m.set_shader_parameter("bins", float(bins))
	m.set_shader_parameter("az_off", deg_to_rad(float((w.v4 as Dictionary).get("sun", {}).get("az_offset_deg", -40.0))))
	rect.material = m
	vp.add_child(rect)
	add_child(vp)
	hz_tex = vp.get_texture()
	hz_on = true
	active = true
	_bake_frames = 0
	timings = {"setup_ms": (Time.get_ticks_usec() - t0) / 1000.0, "hz_side": hz_side, "bins": bins, "atlas": [hz_side * 4, hz_side]}

## The sun of the v4 map now: {elev_deg, bearing, dir}. fx_sky uses it for the key light.
func sun_now(t: float, daylight: float, day_len: float) -> Dictionary:
	return sim.world.sun_angles(t, daylight, day_len)

## Sun visibility at (x, z) from SIM's own horizon map (the solar output's numbers).
func sun_vis(x: float, z: float, sun: Dictionary) -> float:
	if not active:
		return 1.0
	return sim.world.sun_vis(Vector2(x, z), float(sun["elev_deg"]), float(sun["bearing"]))

## How much sky a point sees, 0.12 (deep crater floor) .. 1 (open plain), from SIM's horizon
## map (mean over the day bearings); the shader uses the baked full circle, close to it.
func sky_open(x: float, z: float) -> float:
	var w = sim.world
	if not active or int(w.hz_side) <= 1:
		return 1.0
	var n: int = int(w.hz_side)
	var i: int = clampi(int(round(x / float(w.hz_cell))), 0, n - 1)
	var j: int = clampi(int(round(z / float(w.hz_cell))), 0, n - 1)
	var s := 0.0
	var base: int = (j * n + i) * int(w.hz_bins)
	for b in int(w.hz_bins):
		s += maxf(float(w.horizon[base + b]), 0.0)
	return clampf(1.0 - s / float(w.hz_bins) / 90.0 * 2.2, 0.12, 1.0)

## Shader parameters for this frame.
func apply_to(mat: ShaderMaterial, sun: Dictionary, key_is_sun: bool, key_comp: float, amb_comp: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("hz_on", 1.0 if hz_on else 0.0)
	if not hz_on:
		return
	mat.set_shader_parameter("hz_tex", hz_tex)
	mat.set_shader_parameter("hz_side", float(hz_side))
	mat.set_shader_parameter("hz_cell", HZ_CELL)
	mat.set_shader_parameter("hz_bins", float(bins))
	mat.set_shader_parameter("sun_bin", clampf(float(sun["bearing"]) / PI, 0.0, 1.0) * float(bins - 1))
	mat.set_shader_parameter("sun_el_deg", float(sun["elev_deg"]))
	mat.set_shader_parameter("sun_day", 1.0 if key_is_sun and float(sun["bearing"]) <= PI else 0.0)
	mat.set_shader_parameter("key_comp", key_comp)
	mat.set_shader_parameter("amb_comp", amb_comp)

## Debug: the baked horizon at a point against SIM's (degrees) for a few bearings.
func compare(x: float, z: float) -> String:
	if vp == null:
		return "no bake"
	var img: Image = vp.get_texture().get_image()
	if img == null:
		return "no image"
	var i: int = clampi(int(round(x / HZ_CELL)), 0, hz_side - 1)
	var j: int = clampi(int(round(z / HZ_CELL)), 0, hz_side - 1)
	var out := "view/sim deg:"
	for b in [0, 3, 6, 9, 12]:
		var px: Color = img.get_pixel(int(b / 4) * hz_side + i, j)
		var v: float = [px.r, px.g, px.b, px.a][b % 4] * 100.0 - 10.0
		var w = sim.world
		var n: int = int(w.hz_side)
		var si: int = clampi(int(round(x / float(w.hz_cell))), 0, n - 1)
		var sj: int = clampi(int(round(z / float(w.hz_cell))), 0, n - 1)
		out += " b%d %.1f/%.1f" % [b, v, float(w.horizon[(sj * n + si) * int(w.hz_bins) + b])]
	var sk: Color = img.get_pixel(int(bins / 4) * hz_side + i, j)
	out += " | sky hidden %.2f" % [sk.r, sk.g, sk.b, sk.a][bins % 4]
	return out
