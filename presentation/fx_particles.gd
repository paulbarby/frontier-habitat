extends Node3D
## GPU particles (RENDER). Each effect kind is ONE MultiMesh of camera-facing quads; each
## instance is one particle whose whole motion is computed in the vertex shader from its
## seed and the time (shaders/particles_inc.gdshaderinc). The CPU writes a slot once when
## an emitter starts, so smoke, steam, sparks and dust cost no per-frame script work.
## Kinds: smoke, smoke_dark, steam, spray, sparks, sparks_idle, dust, pulse, plume,
## dust_ring, site_sparks, site_dust; plus the camera dust field, the storm field and the
## lamp halos / beacons.

const MIX = preload("res://shaders/particles_mix.gdshader")
const ADD = preload("res://shaders/particles_add.gdshader")
const GLOW = preload("res://shaders/glow_sprite.gdshader")

const KINDS := {
	"smoke": {"add": false, "cap": 320, "per": 20, "life": 6.0, "dir": Vector3(0, 1, 0), "spread": 0.18, "speed": [0.5, 1.0], "gravity": Vector3(0, 0.12, 0), "size": [0.45, 2.8], "c0": Color(0.36, 0.33, 0.31, 0.5), "c1": Color(0.6, 0.55, 0.5, 0.0), "wind": 0.45, "r": 0.2},
	"smoke_dark": {"add": false, "cap": 160, "per": 18, "life": 5.0, "dir": Vector3(0, 1, 0), "spread": 0.25, "speed": [0.6, 1.2], "gravity": Vector3(0, 0.1, 0), "size": [0.6, 3.0], "c0": Color(0.12, 0.11, 0.1, 0.7), "c1": Color(0.3, 0.28, 0.27, 0.0), "wind": 0.5, "r": 0.4},
	"steam": {"add": false, "cap": 320, "per": 14, "life": 3.0, "dir": Vector3(0, 1, 0), "spread": 0.2, "speed": [0.9, 1.6], "gravity": Vector3(0, 0.2, 0), "size": [0.35, 1.9], "c0": Color(0.95, 0.95, 0.95, 0.42), "c1": Color(1, 1, 1, 0.0), "wind": 0.6, "r": 0.2},
	"spray": {"add": true, "cap": 256, "per": 40, "life": 1.3, "dir": Vector3(0, 1, 0), "spread": 0.35, "speed": [2.5, 4.5], "gravity": Vector3(0, -7.0, 0), "size": [0.09, 0.2], "c0": Color(0.55, 0.8, 1.0, 0.5), "c1": Color(0.7, 0.9, 1.0, 0.0), "wind": 0.2, "r": 0.25},
	"sparks": {"add": true, "cap": 512, "per": 0, "life": 0.9, "dir": Vector3(0, 0.8, 0), "spread": 0.9, "speed": [2.0, 5.5], "gravity": Vector3(0, -9.8, 0), "size": [0.06, 0.03], "c0": Color(1.0, 0.7, 0.3, 1.0), "c1": Color(1.0, 0.35, 0.1, 0.0), "wind": 0.0, "r": 0.3, "stretch": 1.2},
	"sparks_idle": {"add": true, "cap": 160, "per": 10, "life": 0.8, "dir": Vector3(0, 0.6, 0), "spread": 0.9, "speed": [1.5, 3.5], "gravity": Vector3(0, -9.8, 0), "size": [0.05, 0.02], "c0": Color(1.0, 0.75, 0.35, 1.0), "c1": Color(1.0, 0.4, 0.1, 0.0), "wind": 0.0, "r": 0.4, "stretch": 1.2},
	"dust": {"add": false, "cap": 400, "per": 0, "life": 2.8, "dir": Vector3(0, 0.25, 0), "spread": 1.0, "speed": [0.8, 2.6], "gravity": Vector3(0, -0.25, 0), "size": [0.5, 2.6], "c0": Color(0.66, 0.46, 0.32, 0.55), "c1": Color(0.72, 0.53, 0.38, 0.0), "wind": 0.5, "r": 0.8},
	"pulse": {"add": true, "cap": 24, "per": 3, "life": 1.8, "dir": Vector3(0, 1, 0), "spread": 0.0, "speed": [0.0, 0.0], "gravity": Vector3.ZERO, "size": [0.8, 3.6], "c0": Color(0.55, 0.85, 1.0, 0.9), "c1": Color(0.4, 0.7, 1.0, 0.0), "wind": 0.0, "r": 0.01},
	"plume": {"add": true, "cap": 160, "per": 36, "life": 0.55, "dir": Vector3(0, -1, 0), "spread": 0.08, "speed": [9.0, 15.0], "gravity": Vector3.ZERO, "size": [0.9, 2.4], "c0": Color(0.75, 0.9, 1.0, 0.9), "c1": Color(1.0, 0.55, 0.3, 0.0), "wind": 0.0, "r": 0.5},
	"dust_ring": {"add": false, "cap": 320, "per": 60, "life": 2.4, "dir": Vector3(0, 0.12, 0), "spread": 0.1, "speed": [0.2, 0.6], "gravity": Vector3(0, -0.1, 0), "size": [1.2, 4.5], "c0": Color(0.66, 0.47, 0.33, 0.6), "c1": Color(0.72, 0.55, 0.4, 0.0), "wind": 0.3, "r": 3.0, "spawn": 1, "radial": 9.0},
	"site_sparks": {"add": true, "cap": 400, "per": 14, "life": 0.7, "dir": Vector3(0, 0.7, 0), "spread": 0.9, "speed": [1.5, 3.5], "gravity": Vector3(0, -9.8, 0), "size": [0.05, 0.02], "c0": Color(1.0, 0.8, 0.4, 1.0), "c1": Color(1.0, 0.45, 0.15, 0.0), "wind": 0.0, "r": 1.0, "spawn": 1, "stretch": 1.2},
	# V3 hazards (fx_hazards.gd). "yaw": INSTANCE_CUSTOM.w turns the direction per emitter.
	"air_jet": {"add": false, "cap": 240, "per": 24, "life": 0.9, "dir": Vector3(1, 0.12, 0), "spread": 0.1, "speed": [6.0, 11.0], "gravity": Vector3(0, 0.4, 0), "size": [0.12, 1.7], "c0": Color(0.96, 0.98, 1.0, 0.7), "c1": Color(1, 1, 1, 0.0), "wind": 0.3, "r": 0.12, "yaw": 1},
	"debris": {"add": false, "cap": 480, "per": 0, "life": 2.4, "dir": Vector3(0, 1, 0), "spread": 0.85, "speed": [7.0, 21.0], "gravity": Vector3(0, -9.0, 0), "size": [0.3, 0.2], "c0": Color(0.16, 0.12, 0.1, 1.0), "c1": Color(0.24, 0.17, 0.13, 0.9), "wind": 0.0, "r": 1.0},
	"impact_dust": {"add": false, "cap": 420, "per": 0, "life": 7.0, "dir": Vector3(0, 0.3, 0), "spread": 1.0, "speed": [1.5, 7.0], "gravity": Vector3(0, -0.25, 0), "size": [1.5, 10.0], "c0": Color(0.6, 0.42, 0.29, 0.75), "c1": Color(0.7, 0.52, 0.38, 0.0), "wind": 0.6, "r": 2.0, "radial": 7.0},
	"fire": {"add": true, "cap": 240, "per": 0, "life": 0.8, "dir": Vector3(0, 1, 0), "spread": 1.0, "speed": [2.0, 9.0], "gravity": Vector3(0, 1.5, 0), "size": [1.4, 4.5], "c0": Color(1.0, 0.86, 0.55, 1.0), "c1": Color(1.0, 0.28, 0.05, 0.0), "wind": 0.0, "r": 1.0},
	"devil": {"add": false, "cap": 320, "per": 40, "life": 3.2, "dir": Vector3(0, 1, 0), "spread": 0.22, "speed": [3.0, 8.0], "gravity": Vector3(0, -0.4, 0), "size": [0.7, 4.0], "c0": Color(0.64, 0.46, 0.32, 0.42), "c1": Color(0.7, 0.52, 0.38, 0.0), "wind": 0.8, "r": 2.5},
	# V4 radiation zone (fx_reactor): slow, faint green-yellow motes rising over the zone.
	"rad_motes": {"add": true, "cap": 360, "per": 30, "life": 4.0, "dir": Vector3(0, 1, 0), "spread": 0.3, "speed": [0.2, 0.6], "gravity": Vector3(0, 0.05, 0), "size": [0.08, 0.2], "c0": Color(0.75, 1.0, 0.35, 0.85), "c1": Color(0.9, 1.0, 0.4, 0.0), "wind": 0.2, "r": 10.0, "spawn": 1},
	# V4 breach (critic round 22): a tall dust column that rises for 8-10 s over a reactor blast.
	"dust_column": {"add": false, "cap": 480, "per": 110, "life": 9.0, "dir": Vector3(0, 1, 0), "spread": 0.14, "speed": [4.0, 10.0], "gravity": Vector3(0, -0.3, 0), "size": [5.0, 22.0], "c0": Color(0.36, 0.27, 0.2, 0.9), "c1": Color(0.62, 0.48, 0.36, 0.0), "wind": 0.35, "r": 6.0},
	"site_dust": {"add": false, "cap": 240, "per": 8, "life": 3.2, "dir": Vector3(0, 0.3, 0), "spread": 0.6, "speed": [0.3, 0.9], "gravity": Vector3(0, -0.05, 0), "size": [0.5, 2.0], "c0": Color(0.66, 0.47, 0.33, 0.38), "c1": Color(0.72, 0.55, 0.4, 0.0), "wind": 0.5, "r": 1.0, "spawn": 1},
}

var view
var quality := 2
var pools := {}          # kind -> {mm, mmi, mat, cap, free: [], burst_i, burst_lo, wind}
var emitters := {}       # key -> {kind, slots: [], pos, inten, radius, seeds}
var _now := 0.0
var _rng := RandomNumberGenerator.new()
var _field: MultiMeshInstance3D
var _field_mat: ShaderMaterial
var _storm: MultiMeshInstance3D
var _storm_mat: ShaderMaterial
var _glow: MultiMeshInstance3D
var _glow_mat: ShaderMaterial
var _lamp_sig := ""
var wind_storm := 0.0      # V3 wind storm 0..1 (fx_hazards): fast pale dust sheets
var indoor_hide := false   # V5 §19.9: the follow camera is inside a habitat: no weather particles at all
const WEATHER_KINDS := ["dust", "devil", "dust_column", "impact_dust", "dust_ring"]
const HUGE_AABB := AABB(Vector3(-900, -200, -900), Vector3(4400, 700, 4400))   # the 2,560 m v4 map too

var field_on := true        # the camera dust motes (off for critic stills: `toggle dust 0`)
## Planet (Paul 2026-10-01, V5 15.7): "airless" = no dust in the air, no devils, no storm sheets, no drift;
## "cold" = the camera motes are ice glitter (pale blue-white). world_view sets it on load.
var planet := "dry":
	set(v):
		if v == planet:
			return
		planet = v
		_planet_colours()
		if v == "airless":
			# (emitters made before the switch stop: steam, smoke and dust need air)
			for ek in emitters.keys():
				if String(emitters[ek]["kind"]) in AIRLESS_NO:
					emitter_stop(ek)
## Cold planet (critic round 41 follow-up: the dust stayed orange): the ground and storm dust kinds are pale ice
## and snow, keeping each kind's alpha.
const ICE_KINDS := ["dust", "dust_ring", "impact_dust", "devil", "dust_column", "site_dust"]
func _kind_cols(kind: String) -> Array:
	var k: Dictionary = KINDS[kind]
	if planet == "cold" and kind in ICE_KINDS:
		return [Color(0.80, 0.85, 0.92, (k["c0"] as Color).a), Color(0.90, 0.93, 0.97, (k["c1"] as Color).a)]
	return [k["c0"], k["c1"]]
func _planet_colours() -> void:
	for kind in pools:
		var cc: Array = _kind_cols(kind)
		(pools[kind]["mat"] as ShaderMaterial).set_shader_parameter("color0", cc[0])
		(pools[kind]["mat"] as ShaderMaterial).set_shader_parameter("color1", cc[1])
	if _storm != null and _storm.material_override is ShaderMaterial:
		var sc: Color = Color(0.86, 0.9, 0.96, 0.55) if planet == "cold" else Color(0.72, 0.5, 0.34, 0.55)
		(_storm.material_override as ShaderMaterial).set_shader_parameter("color0", sc)
		(_storm.material_override as ShaderMaterial).set_shader_parameter("color1", sc)
# (V5 §19.8, Paul 2026-10-04: no atmospheric effect of any kind on the airless planet: no dust, smoke or steam)
const AIRLESS_NO := ["devil", "dust_column", "dust", "site_dust", "dust_ring", "impact_dust", "smoke", "smoke_dark", "steam"]
const AIRLESS_LOW := []
var field_light := 1.0      # V4: motes dim in a shadowed crater (no bright streaks on a dark floor)
## Weather kinds clipped by the room / corridor volumes (Paul 2026-10-01: no storm inside habitats).
const CLIP_KINDS := ["dust", "devil", "impact_dust", "dust_column"]
var clip := {"rooms": [], "tubes": [], "tube_y": PackedFloat32Array(), "n_r": 0, "n_t": 0}

## The volumes near the field (world_view, a few times a second): rooms [Vector4(x, z, r, top)], corridors
## [Vector4(x0, z0, x1, z1)] with their top y. At most 32 of each (the nearest).
func set_clip(rooms: Array, tubes: Array, tube_y: PackedFloat32Array) -> void:
	var r: Array = rooms.slice(0, 32)
	var t: Array = tubes.slice(0, 32)
	var ty: PackedFloat32Array = tube_y.slice(0, 32)
	clip = {"rooms": r.duplicate(), "tubes": t.duplicate(), "tube_y": ty, "n_r": r.size(), "n_t": t.size()}
	while r.size() < 32:
		r.append(Vector4.ZERO)
	while t.size() < 32:
		t.append(Vector4.ZERO)
	while ty.size() < 32:
		ty.append(-1.0e6)
	var mats: Array = [_field_mat, _storm_mat]
	for k in CLIP_KINDS:
		if pools.has(k):
			mats.append(pools[k]["mat"])
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("clip_on", 1.0)
		(m as ShaderMaterial).set_shader_parameter("clip_room_n", int(clip["n_r"]))
		(m as ShaderMaterial).set_shader_parameter("clip_rooms", r)
		(m as ShaderMaterial).set_shader_parameter("clip_tube_n", int(clip["n_t"]))
		(m as ShaderMaterial).set_shader_parameter("clip_tubes", t)
		(m as ShaderMaterial).set_shader_parameter("clip_tube_y", ty)

func setup(v) -> void:
	view = v
	_rng.seed = 90210
	_field = _make_field(900, Color(0.78, 0.6, 0.45, 0.35), 0.035, 0.06, 0.0)
	_field_mat = _field.material_override
	_storm = _make_field(1800, Color(0.72, 0.5, 0.34, 0.55), 0.1, 0.1, 6.0)
	_planet_colours()
	_storm_mat = _storm.material_override
	_storm_mat.set_shader_parameter("field_size", Vector3(90, 24, 90))
	_glow = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = 0
	_glow.multimesh = mm
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GLOW
	_glow.material_override = _glow_mat
	_glow.custom_aabb = HUGE_AABB
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	set_quality(quality)

func set_quality(q: int) -> void:
	quality = q
	var amount: float = [0.25, 0.5, 0.8, 1.0][clampi(q, 0, 3)]
	if _field_mat != null:
		_field_mat.set_shader_parameter("field_amount", amount * 0.6)
		_storm_mat.set_shader_parameter("field_amount", amount)

func _mult() -> float:
	return [0.35, 0.6, 0.85, 1.0][clampi(quality, 0, 3)]

func _make_field(n: int, col: Color, s0: float, s1: float, stretch: float) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3.ZERO))
		mm.set_instance_custom_data(i, Color(float(i) / n, 1.0, -1.0, 0.0))
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = MIX
	m.set_shader_parameter("field", 1.0)
	m.set_shader_parameter("size0", s0)
	m.set_shader_parameter("size1", s1)
	m.set_shader_parameter("color0", col)
	m.set_shader_parameter("color1", col)
	m.set_shader_parameter("stretch", stretch)
	m.set_shader_parameter("light_amt", 0.0)
	mmi.material_override = m
	mmi.custom_aabb = HUGE_AABB
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

func _pool(kind: String) -> Dictionary:
	if pools.has(kind):
		return pools[kind]
	var k: Dictionary = KINDS[kind]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	var cap: int = int(k["cap"])
	mm.instance_count = cap
	for i in cap:
		mm.set_instance_transform(i, _off())
		mm.set_instance_custom_data(i, Color(0, 0, -1, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = HUGE_AABB
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = ADD if bool(k["add"]) else MIX
	m.set_shader_parameter("life", k["life"])
	m.set_shader_parameter("dir", k["dir"])
	m.set_shader_parameter("spread", k["spread"])
	m.set_shader_parameter("speed_min", k["speed"][0])
	m.set_shader_parameter("speed_max", k["speed"][1])
	m.set_shader_parameter("gravity", k["gravity"])
	m.set_shader_parameter("size0", k["size"][0])
	m.set_shader_parameter("size1", k["size"][1])
	var cc: Array = _kind_cols(kind)
	m.set_shader_parameter("color0", cc[0])
	m.set_shader_parameter("color1", cc[1])
	m.set_shader_parameter("spawn", int(k.get("spawn", 0)))
	m.set_shader_parameter("stretch", float(k.get("stretch", 0.0)))
	m.set_shader_parameter("radial", float(k.get("radial", 0.0)))
	m.set_shader_parameter("yaw_dir", int(k.get("yaw", 0)))
	m.render_priority = 3
	mmi.material_override = m
	add_child(mmi)
	# Continuous emitters take slots from the bottom; the top quarter is a ring buffer
	# for bursts (all of it for burst-only kinds).
	var cont: int = cap - cap / 4 if int(k["per"]) > 0 else 0
	var free: Array = []
	for i in range(cont - 1, -1, -1):
		free.append(i)
	pools[kind] = {"mm": mm, "mmi": mmi, "mat": m, "cap": cap, "free": free, "burst_i": cont, "burst_lo": cont, "wind": float(k["wind"])}
	return pools[kind]

func _off() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -500, 0))

## Continuous emitter. Same key again only moves it or changes its strength.
func emitter_set(key: String, kind: String, pos: Vector3, intensity: float, yaw: float = 0.0) -> void:
	if not KINDS.has(kind) or planet == "airless" and kind in AIRLESS_NO:
		return
	if planet == "airless" and kind in AIRLESS_LOW:
		intensity *= 0.35
	if emitters.has(key):
		var e: Dictionary = emitters[key]
		if e["kind"] == kind:
			if (e["pos"] as Vector3).distance_squared_to(pos) > 0.0004 or absf(float(e["inten"]) - intensity) > 0.05 or absf(float(e.get("yaw", 0.0)) - yaw) > 0.01:
				e["pos"] = pos
				e["inten"] = intensity
				e["yaw"] = yaw
				_write_emitter(e)
			return
		emitter_stop(key)
	var pool: Dictionary = _pool(kind)
	var n: int = maxi(1, int(round(float(KINDS[kind]["per"]) * _mult())))
	var slots: Array = []
	for i in n:
		if (pool["free"] as Array).is_empty():
			break
		slots.append((pool["free"] as Array).pop_back())
	var e2 := {"kind": kind, "slots": slots, "pos": pos, "inten": intensity, "radius": float(KINDS[kind]["r"]), "seeds": [], "yaw": yaw}
	for i in slots.size():
		e2["seeds"].append(_rng.randf())
	emitters[key] = e2
	_write_emitter(e2)

func _write_emitter(e: Dictionary) -> void:
	var pool: Dictionary = pools[e["kind"]]
	var mm: MultiMesh = pool["mm"]
	var r: float = maxf(0.01, float(e["radius"]))
	var xf := Transform3D(Basis.from_scale(Vector3(r, r, r)), e["pos"])
	for i in (e["slots"] as Array).size():
		var slot: int = e["slots"][i]
		mm.set_instance_transform(slot, xf)
		mm.set_instance_custom_data(slot, Color(e["seeds"][i], e["inten"], -1.0, float(e.get("yaw", 0.0))))

func emitter_radius(key: String, r: float) -> void:
	if emitters.has(key) and absf(float(emitters[key]["radius"]) - r) > 0.01:
		emitters[key]["radius"] = r
		_write_emitter(emitters[key])

func emitter_stop(key: String) -> void:
	if not emitters.has(key):
		return
	var e: Dictionary = emitters[key]
	var pool: Dictionary = pools[e["kind"]]
	for slot in e["slots"]:
		(pool["mm"] as MultiMesh).set_instance_transform(slot, _off())
		(pool["free"] as Array).append(slot)
	emitters.erase(key)

## Load warm-up (world_view._night_warmup): every pool made now, one particle of each at pos,
## and one glow sprite, so each particle shader meets the warm-up light mixes. A pool made
## mid-game (the first POI pulse) cost a 480-680 ms web frame (showcase_v4, 2026-09-28).
func prewarm(pos: Vector3) -> void:
	for kind in KINDS:
		burst(kind, pos, 1, 0.01)
	var mm: MultiMesh = _glow.multimesh
	if mm.instance_count == 0:
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(0.01, 0.01, 0.01)), pos))
		mm.set_instance_color(0, Color(1, 1, 1, 1))
		mm.set_instance_custom_data(0, Color(0, 0, 0.01, 1))
		_lamp_sig = "warm"

## One-shot particles (dust puff, sparks shower).
func burst(kind: String, pos: Vector3, n: int, radius: float = -1.0, yaw: float = 0.0, inten: float = 1.0) -> void:
	if not KINDS.has(kind) or planet == "airless" and kind in AIRLESS_NO:
		return
	if planet == "airless" and kind in AIRLESS_LOW and n > 1:
		n = maxi(1, n / 3)
	var pool: Dictionary = _pool(kind)
	var mm: MultiMesh = pool["mm"]
	var lo: int = pool["burst_lo"]
	var cap: int = pool["cap"]
	var r: float = float(KINDS[kind]["r"]) if radius < 0.0 else radius
	var xf := Transform3D(Basis.from_scale(Vector3(r, r, r)), pos)
	for i in int(n * _mult()):
		var slot: int = pool["burst_i"]
		pool["burst_i"] = lo + ((slot - lo + 1) % maxi(1, cap - lo))
		mm.set_instance_transform(slot, xf)
		mm.set_instance_custom_data(slot, Color(_rng.randf(), inten, _now - _rng.randf() * 0.1, yaw))

## Construction sites: sparks at the build line, dust at the base.
func site_start(id: int, origin: Vector3, radius: float) -> void:
	emitter_set("site%d_d" % id, "site_dust", origin + Vector3(0, 0.2, 0), 1.0)
	emitter_radius("site%d_d" % id, radius + 0.8)

func site_update(id: int, build_y: float, active: bool) -> void:
	var key := "site%d_s" % id
	if not active:
		emitter_stop(key)
		return
	var d: Dictionary = emitters.get("site%d_d" % id, {})
	if d.is_empty():
		return
	var o: Vector3 = d["pos"]
	emitter_set(key, "site_sparks", Vector3(o.x, build_y, o.z), 1.0)
	emitter_radius(key, maxf(0.6, float(d["radius"]) - 1.3))

func site_stop(id: int) -> void:
	emitter_stop("site%d_d" % id)
	emitter_stop("site%d_s" % id)

## Lamp halos (steady) and beacons (blinking). Rebuilt only when the list changes.
func set_lamps(glows: Array, beacons: Array) -> void:
	var sig := "%d:%d" % [glows.size(), beacons.size()]
	for g in glows:
		sig += "%.1f,%.1f;" % [g["pos"].x, g["pos"].z]
	for g in beacons:
		sig += "%.1f,%.1f,%.1f;" % [g["pos"].x, g["pos"].z, g["rate"]]
	if sig == _lamp_sig:
		return
	_lamp_sig = sig
	var mm: MultiMesh = _glow.multimesh
	mm.instance_count = glows.size() + beacons.size()
	var i := 0
	for g in glows:
		mm.set_instance_transform(i, Transform3D(Basis(), g["pos"]))
		mm.set_instance_color(i, g["color"])
		mm.set_instance_custom_data(i, Color(0.0, 0.0, float(g.get("size", 1.0)), 1.0))
		i += 1
	for g in beacons:
		mm.set_instance_transform(i, Transform3D(Basis(), g["pos"]))
		mm.set_instance_color(i, g["color"])
		mm.set_instance_custom_data(i, Color(_rng.randf(), float(g.get("rate", 1.0)), float(g.get("size", 1.0)), 1.4))
		i += 1

func sync(delta: float, sim_dt: float, cam: Camera3D, focus: Vector3, wind: float, night: float, storm: float, sun_dir: Vector3) -> void:
	_now += delta
	var wv := Vector3(0.83, 0.0, 0.55) * (0.4 + wind * 0.35)
	if planet == "airless":
		wv = Vector3.ZERO
		storm = 0.0
		wind_storm = 0.0
	var light := Color(1.0, 0.92, 0.82).lerp(Color(0.32, 0.36, 0.5), night)
	for kind in pools:
		var m: ShaderMaterial = pools[kind]["mat"]
		m.set_shader_parameter("now", _now)
		m.set_shader_parameter("wind", wv * float(pools[kind]["wind"]))
		if not bool(KINDS[kind]["add"]):
			m.set_shader_parameter("light_col", light)
	# Camera dust: a few motes drift through the air near the focus; many in a storm.
	var center: Vector3 = focus + Vector3(0, 4.0, 0)
	_field_mat.set_shader_parameter("now", _now)
	_field_mat.set_shader_parameter("wind", wv * 1.4)
	_field_mat.set_shader_parameter("field_center", center)
	_field_mat.set_shader_parameter("field_size", Vector3(70, 12, 70))
	var fc := Color(0.8, 0.62, 0.46) if planet != "cold" else Color(0.86, 0.92, 1.0)
	_field_mat.set_shader_parameter("color0", Color(fc.r, fc.g, fc.b, 0.28 * (1.0 - night * 0.6) * field_light))
	_field.visible = quality >= 1 and field_on and planet != "airless" and not indoor_hide
	var st2: float = maxf(storm, wind_storm)
	_storm.visible = st2 > 0.02 and not indoor_hide
	for wk in WEATHER_KINDS:
		if pools.has(wk):
			(pools[wk]["mmi"] as Node3D).visible = not indoor_hide
	if _storm.visible:
		# A wind storm: paler, thinner sheets that race by; a dust storm: thick orange dust.
		var ws: float = wind_storm / maxf(st2, 0.001) if wind_storm > storm else 0.0
		_storm_mat.set_shader_parameter("now", _now)
		_storm_mat.set_shader_parameter("wind", Vector3(0.83, -0.05, 0.55) * lerpf(14.0, 26.0, ws))
		_storm_mat.set_shader_parameter("field_center", center)
		var c0: Color = Color(0.74, 0.52, 0.36, 0.5 * st2).lerp(Color(0.86, 0.72, 0.58, 0.32 * st2), ws)
		_storm_mat.set_shader_parameter("color0", c0.lerp(Color(0.2, 0.16, 0.14, c0.a), night))
		_storm_mat.set_shader_parameter("field_amount", st2 * lerpf(1.0, 0.7, ws) * [0.25, 0.5, 0.8, 1.0][clampi(quality, 0, 3)])
	_glow_mat.set_shader_parameter("now", _now)
	_glow_mat.set_shader_parameter("night", night)
