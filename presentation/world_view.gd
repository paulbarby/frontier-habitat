extends Node3D
## Draws the simulation (RENDER). It only READS sim.state and the derived stats; it never
## changes them (spec 13). Every visual follows real state: a carried crate is a real unit
## in a carrier inventory, a growing crop is a real tray, a spinning rotor is real wind,
## a worn footpath is where colonists really walked.
## Sim space (x, y) maps to world (x, height, z = y). Sim rotation r maps to rotation.y = -r.
##
## API used by main.gd and the interface (docs/AAA_DESIGN.md §12):
##   setup(sim), sync(delta), h(x, y), to3(p, lift), ground_point(camera, screen),
##   pick(p, include_agents), select(kind, id), set_overlay(name), agent_world_pos(id),
##   set_ghost(def_id, size, pos, rot, valid), clear_ghost(),
##   set_link_preview(p0, p1, kind, valid)  (p0 = null hides it),
##   set_quality(level 0..3), set_time_override(second_of_day or -1),
##   focus_event(kind, id), stats() -> Dictionary, rig() -> the camera rig.
##
## Structures that are simply standing ("active") are drawn through fx_instancer (one
## MultiMesh per model part). Blueprints, construction sites, broken structures and
## demolitions are one-off node trees with the construction and hologram shaders.

const Models = preload("res://presentation/models.gd")
const Instancer = preload("res://presentation/fx_instancer.gd")
const FxSky = preload("res://presentation/fx_sky.gd")
const FxTerrain = preload("res://presentation/fx_terrain.gd")
const Post = preload("res://presentation/fx_post.gd")
const Particles = preload("res://presentation/fx_particles.gd")
const Ghost = preload("res://presentation/fx_ghost.gd")
const Overlay = preload("res://presentation/fx_overlay.gd")
const Icons = preload("res://presentation/fx_icons.gd")
const Ship = preload("res://presentation/fx_ship.gd")
const Npc = preload("res://presentation/fx_npc.gd")
const Doors = preload("res://presentation/fx_doors.gd")
const Airlock = preload("res://presentation/fx_airlock.gd")
const Traffic = preload("res://presentation/fx_traffic.gd")
const Interior = preload("res://presentation/fx_interior.gd")
const Hazards = preload("res://presentation/fx_hazards.gd")
const Rng = preload("res://sim/rng.gd")
const CONSTRUCT_SHADER = preload("res://shaders/construct.gdshader")
const HOLO_SHADER = preload("res://shaders/hologram.gdshader")
const DECAL_SHADER = preload("res://shaders/ground_decal.gdshader")
const OUTLINE_SHADER = preload("res://shaders/outline.gdshader")

const HOLO_COLORS := {"blueprint": Color(0.35, 0.82, 1.0), "building": Color(1.0, 0.74, 0.32), "demolish": Color(1.0, 0.32, 0.26), "broken": Color(1.0, 0.45, 0.2)}

var sim
var sky
var terrain
var post
var fx
var ghost
var overlays
var icons
var ship
var npc                    # fx_npc: skinned astronauts (falls back to the v2 rigid colonists)
var npc_fixture := false   # test only: the procedural rig instead of the GLBs
var doors                  # fx_doors: doorways, wall cuts, corridor ribs
var airlock                # fx_airlock: the airlock cycle (V3_1 §5.3)
var traffic                # fx_traffic: visiting ships landing and taking off (V3_1 §6.3)
var interior               # fx_interior: interior lights and light pools
var hazards                # fx_hazards: meteors, storms, quakes, flares, dust devils, breaches
var inst                   # fx_instancer shared by structures, figures, crops, crates, rocks
var bmeta := {}            # building id -> visual record
var ameta := {}            # agent id -> visual record
var pmeta := {}            # pile inventory id -> {handles: []}
var selected_kind := ""
var selected_id := -1
var overlay := ""          # "", "power", "water", "air", "walk"
var camera_distance := 60.0
var quality := 2
var time_override := -1.0
var heightmap: ImageTexture
var decal_mat_cache := {}
var _time := 0.0
var _sim_seconds := -1.0
var _sel_ring: MeshInstance3D
var _outline: Node3D
var _outline_sig := ""
var _status_clock := 0.0
var _sites_clock := 0.0
var _rev_sig := ""
var _labels := {}          # building id -> Label3D (important blocks only)
var _dep_labels: Array = []
var labels_visible := true
var _dep_rings: Array = []
var _construct_mats := {}
var _holo_mats := {}
var _js_cb = null
var _js_obj = null
var _fps_clock := 0.0
var _frame_ms := 0.0
var _worst_ms := 0.0
var _setup_ms := 0.0
var _forced_storm := -1.0
var _forced_flight := -1.0
var _shake := 0.0
var _pending_load := false
var _measuring := false
var _debug_node := -1
var _frozen := false
var _focus_now := Vector3.ZERO
var _frame := 0
var game_rate := 1.0       # game seconds per real second, smoothed (0 while paused)
var shake_enabled := true  # settings "Camera shake" (UI sets it); quake and impact shakes respect it

# ---------------------------------------------------------------- setup
func setup(s) -> void:
	var t0: int = Time.get_ticks_usec()
	sim = s
	for c in get_children():
		c.queue_free()
	bmeta = {}
	ameta = {}
	pmeta = {}
	_labels = {}
	_dep_labels = []
	_dep_rings = []
	_outline = null
	_outline_sig = ""
	_rev_sig = ""
	_sim_seconds = -1.0
	_range_set = -1
	inst = Instancer.new()
	inst.name = "Instances"
	add_child(inst)
	sky = FxSky.new()
	sky.name = "Sky"
	add_child(sky)
	sky.build()
	_build_heightmap()
	terrain = FxTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(sim, inst, quality)
	post = Post.new()
	post.name = "Post"
	add_child(post)
	fx = Particles.new()
	fx.name = "Particles"
	add_child(fx)
	fx.setup(self)
	ghost = Ghost.new()
	ghost.name = "Ghost"
	add_child(ghost)
	ghost.setup(self)
	overlays = Overlay.new()
	overlays.name = "Overlays"
	add_child(overlays)
	overlays.setup(self)
	icons = Icons.new()
	icons.name = "Icons"
	add_child(icons)
	icons.setup(self)
	ship = Ship.new()
	ship.name = "Ship"
	add_child(ship)
	ship.setup(self)
	npc = Npc.new()
	npc.name = "Astronauts"
	add_child(npc)
	npc.setup(self, npc_fixture)
	doors = Doors.new()
	doors.name = "Doorways"
	add_child(doors)
	doors.setup(self)
	airlock = Airlock.new()
	airlock.name = "Airlocks"
	add_child(airlock)
	airlock.setup(self)
	traffic = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(self)
	interior = Interior.new()
	interior.name = "InteriorLights"
	add_child(interior)
	interior.setup(self)
	hazards = Hazards.new()
	hazards.name = "Hazards"
	add_child(hazards)
	hazards.setup(self)
	_sel_ring = decal_ring(1.0, 0.86, 96, Color(0.35, 0.92, 1.0, 1.0), 0)
	_sel_ring.visible = false
	add_child(_sel_ring)
	_build_deposit_labels()
	set_quality(quality)
	_install_js()
	# A brand-new colony opens with the camera fly-in (skippable by any input).
	if int(sim.state["tick"]) < 20:
		var r = rig()
		if r != null and r.has_method("play_intro"):
			r.play_intro()
	_setup_ms = (Time.get_ticks_usec() - t0) / 1000.0

func h(x: float, y: float) -> float:
	return sim.world.height_at(x, y)

func to3(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, h(p.x, p.y) + lift, p.y)

func rig():
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return null
	return cam.get_parent()

func _build_heightmap() -> void:
	var w = sim.world
	var img := Image.create_from_data(w.hn, w.hn, false, Image.FORMAT_RF, (w.heights as PackedFloat32Array).to_byte_array())
	img.convert(Image.FORMAT_RH)
	heightmap = ImageTexture.create_from_image(img)

## Ore deposits: a dashed amber ring on the ground; the word only close up.
func _build_deposit_labels() -> void:
	# All rings are one mesh in world space (one draw call, not one per deposit). The decal
	# shader reads only UV, so the dash pattern is the same as with separate rings.
	var src: Array = ring_mesh(0.96, 96).surface_get_arrays(0)
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var suv: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
	var av := PackedVector3Array()
	var auv := PackedVector2Array()
	var an := PackedVector3Array()
	var deps: Array = sim.state["deposits"]
	for d in deps:
		var r: float = float(d["r"]) + 1.2
		var o := Vector3(float(d["x"]), 0, float(d["y"]))
		for v in sv:
			av.append(o + v * r)
			an.append(Vector3.UP)
		auv.append_array(suv)
	if not av.is_empty() and suv.size() == sv.size():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = av
		arrays[Mesh.ARRAY_NORMAL] = an
		arrays[Mesh.ARRAY_TEX_UV] = auv
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var ring := MeshInstance3D.new()
		ring.mesh = am
		ring.material_override = decal_material(Color(1.0, 0.7, 0.35, 0.55), 1, 40.0, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.extra_cull_margin = 16.0
		ring.name = "DepositRings"
		ring.set_instance_shader_parameter("icolor", Color(1, 1, 1, 1))
		ring.set_instance_shader_parameter("ipulse", 0.0)
		add_child(ring)
		_dep_rings.append(ring)
	for d in deps:
		var lab := Label3D.new()
		lab.text = "ORE"
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.fixed_size = true
		lab.pixel_size = 0.0007
		lab.font_size = 20
		lab.outline_size = 6
		lab.modulate = Color(1.0, 0.8, 0.55, 0.9)
		lab.outline_modulate = Color(0.05, 0.03, 0.02, 0.8)
		lab.position = to3(Vector2(d["x"], d["y"]), 1.6)
		lab.name = "DepositLabel"
		add_child(lab)
		_dep_labels.append(lab)

# ---------------------------------------------------------------- shared materials
## A flat ring (outer radius 1, inner `inner`), draped on the terrain by the decal shader.
func decal_ring(radius: float, inner: float, segments: int, color: Color, mode: int, dashes: float = 48.0, speed: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ring_mesh(inner, segments)
	mi.material_override = decal_material(color, mode, dashes, speed)
	mi.scale = Vector3(radius, 1.0, radius)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16.0
	# Instance uniforms are not reliably initialised to their defaults in the Compatibility
	# renderer: an unset icolor read as 0 and the decal vanished (2026-09-25). Set them.
	mi.set_instance_shader_parameter("icolor", Color(1, 1, 1, 1))
	mi.set_instance_shader_parameter("ipulse", 0.0)
	return mi

func decal_material(color: Color, mode: int, dashes: float = 48.0, speed: float = 0.0, lift: float = 0.12) -> ShaderMaterial:
	var key := "%s|%d|%.1f|%.2f|%.2f" % [color.to_html(), mode, dashes, speed, lift]
	if decal_mat_cache.has(key):
		return decal_mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = DECAL_SHADER
	m.set_shader_parameter("heightmap", heightmap)
	m.set_shader_parameter("hstep", float(sim.world.hstep))
	m.set_shader_parameter("hn", float(sim.world.hn))
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("dashes", dashes)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("lift", lift)
	m.render_priority = 1
	decal_mat_cache[key] = m
	return m

static var _ring_meshes := {}
static func ring_mesh(inner: float, segments: int) -> ArrayMesh:
	var key := "%.3f:%d" % [inner, segments]
	if _ring_meshes.has(key):
		return _ring_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radial: int = 1 if inner > 0.001 else 6
	for i in segments:
		var a0: float = TAU * i / segments
		var a1: float = TAU * (i + 1) / segments
		for k in radial:
			var r0: float = lerpf(inner, 1.0, float(k) / radial)
			var r1: float = lerpf(inner, 1.0, float(k + 1) / radial)
			var v := [Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a1) * r0, 0, sin(a1) * r0), Vector3(cos(a1) * r1, 0, sin(a1) * r1), Vector3(cos(a0) * r1, 0, sin(a0) * r1)]
			var uv := [Vector2(float(i) / segments, float(k) / radial), Vector2(float(i + 1) / segments, float(k) / radial), Vector2(float(i + 1) / segments, float(k + 1) / radial), Vector2(float(i) / segments, float(k + 1) / radial)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uv[idx])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[idx])
	var m: ArrayMesh = st.commit()
	_ring_meshes[key] = m
	return m

## A flat strip from local (0,0,0) to (length,0,0), `width` wide, subdivided every 2 m so
## the decal shader can drape it. UV.x = metres along, UV.y = 0..1 across.
static func strip_mesh(length: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = maxi(1, int(ceil(length / 2.0)))
	for i in n:
		var x0: float = length * i / n
		var x1: float = length * (i + 1) / n
		var v := [Vector3(x0, 0, -width * 0.5), Vector3(x1, 0, -width * 0.5), Vector3(x1, 0, width * 0.5), Vector3(x0, 0, width * 0.5)]
		var uv := [Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, 1), Vector2(x0, 1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[idx])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[idx])
	return st.commit()

func holo_material(color: Color, strength: float = 1.0) -> ShaderMaterial:
	var key := "%s|%.2f" % [color.to_html(), strength]
	if not _holo_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = HOLO_SHADER
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("strength", strength)
		m.render_priority = 2
		_holo_mats[key] = m
	return _holo_mats[key]

## A construction material for ONE site (its build line moves on its own).
func _construct_material(src: Material, state: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CONSTRUCT_SHADER
	# Interior and wall-cut materials keep their library source in meta "src".
	if src is ShaderMaterial and src.has_meta("src"):
		src = src.get_meta("src")
	if src is BaseMaterial3D:
		var b: BaseMaterial3D = src
		m.set_shader_parameter("albedo", b.albedo_color)
		m.set_shader_parameter("roughness", b.roughness)
		m.set_shader_parameter("metallic", b.metallic)
		m.set_shader_parameter("use_vc", b.vertex_color_use_as_albedo)
		if b.emission_enabled:
			m.set_shader_parameter("emission", b.emission)
			m.set_shader_parameter("emission_energy", b.emission_energy_multiplier * 0.5)
	return m

# ---------------------------------------------------------------- per frame
func sync(delta: float) -> void:
	if _frozen:
		_publish_stats(delta)
		return
	var t_frame: int = Time.get_ticks_usec()
	_time += delta
	var secs: float = sim.seconds()
	var sim_dt: float = 0.0 if _sim_seconds < 0.0 else clampf(secs - _sim_seconds, 0.0, 30.0)
	_sim_seconds = secs
	if delta > 0.0:
		# A time average of sim seconds per view second. The ratio is NOT clamped low: the sim
		# steps in 0.1 s ticks, so one frame in many carries a large ratio (slow motion).
		game_rate = lerpf(game_rate, clampf(sim_dt / delta, 0.0, 1000.0), 1.0 - exp(-delta * 1.5))
	var cam: Camera3D = get_viewport().get_camera_3d()
	var focus: Vector3 = _focus()
	_focus_now = focus
	_frame += 1
	# Time of day (visual) and weather.
	var day_len: float = float(sim.bal["day_length"])
	var daylight: float = float(sim.planet["daylight_seconds"])
	_night_warmup()
	_cover_update(delta)
	var t: float = time_override if time_override >= 0.0 else sim.util.day_time()
	var storm: float = _storm_level()
	sky.storm = lerpf(sky.storm, storm, 1.0 - exp(-delta * 0.8))
	var wind: float = float(sim.state["env"].get("wind", 3.0))
	var tp: int = Time.get_ticks_usec()
	sky.update(t, day_len, daylight, delta, focus, camera_distance, wind)
	post.apply(sky.grade, delta)
	Models.set_night(sky.night)
	Models.animate(_time)
	tp = _prof("sky", tp)
	_camera_range()
	terrain.update_lod(delta, cam)
	terrain.update_paths(sim_dt)
	tp = _prof("paths", tp)
	_made_now = 0
	_sync_buildings(delta)
	tp = _prof("buildings", tp)
	# A colony just built (a load): do the one-time work now, in this (load) frame, instead of
	# in the frames after it (V3.1 stall trace: 60-240 ms frames in the first second).
	if _made_now >= 20:
		_boot_prewarm(cam)
		tp = _prof("boot", tp)
	airlock.sync(delta)
	tp = _prof("airlock", tp)
	if npc.sync(delta):
		if not ameta.is_empty():
			for id in ameta.keys():
				_drop_agent(id)
	else:
		_sync_agents(delta)
	tp = _prof("agents", tp)
	doors.sync(delta, _body_points())
	interior.sync(delta, focus, sky.night)
	tp = _prof("doors", tp)
	hazards.sync(delta, focus)
	tp = _prof("hazards", tp)
	_sync_piles()
	ship.sync(delta, sim_dt)
	traffic.sync(delta)
	_sync_selection(delta)
	overlays.sync(delta)
	tp = _prof("misc", tp)
	_status_clock -= delta
	if _status_clock <= 0.0:
		_status_clock = 0.2
		_sync_status()
	_sites_clock -= delta
	if _sites_clock <= 0.0:
		_sites_clock = 1.0
		_refresh_sites()
	tp = _prof("status", tp)
	fx.sync(delta, sim_dt, cam, focus, wind, sky.night, sky.storm, sky.sun_dir)
	tp = _prof("fx", tp)
	var show_words: bool = labels_visible and time_override < 0.0 and not _photo_mode()
	for lab in _dep_labels:
		(lab as Label3D).visible = show_words and camera_distance < 55.0 and overlay == ""
	for rg in _dep_rings:
		(rg as MeshInstance3D).visible = labels_visible and not _photo_mode()
	for id in _labels:
		(_labels[id] as Label3D).visible = show_words
	icons.visible = labels_visible and not _photo_mode()
	_shake = move_toward(_shake, 0.0, delta * 2.0)
	# Name plates and door signs (0.3 m) cannot be read from far: not drawn beyond 60 m.
	inst.set_far_hidden(["NameSign", "Sign"], camera_distance > 60.0)
	var vms: float = (Time.get_ticks_usec() - t_frame) / 1000.0
	_frame_ms = lerpf(_frame_ms, vms, 0.05)
	_log_stall(delta, vms)
	_frame_secs = {}
	_publish_stats(delta)

## World labels and badges on or off (the title screen turns them off). Photo orbit and a
## time override also hide the words.
func set_labels_visible(on: bool) -> void:
	labels_visible = on

var _made_now := 0
var _night_warm := 0
var _warm_frames := 0
var _warm_t0 := 0.0
var _warm_restore := -2.0
var _warm_nodes: Array = []
var _warm_handles: Array = []
var _warm_cover: CanvasLayer = null
## One-time work of a new colony: every terrain chunk mesh the camera needs, the walk grids of
## every room, and a night warm-up (see _night_warmup).
func _boot_prewarm(cam: Camera3D) -> void:
	var t0: int = Time.get_ticks_usec()
	var n: int = terrain.build_needed(cam)
	var t1: int = Time.get_ticks_usec()
	var g := 0
	if npc != null and npc.planner != null:
		for rid in bmeta:
			var b: Dictionary = sim.state["buildings"].get(rid, {})
			if b.is_empty() or String(b["kind"]) != "room" or bmeta[rid]["mode"] != "inst":
				continue
			npc.planner.coarse(int(rid))
			npc.planner.coarse(int(rid), 0.15)
			npc.planner.doors_of(int(rid))
			g += 1
	_warm_frames = 0
	if traffic != null:
		traffic._warm_n = 0
	boot_info = {"chunks": n, "chunk_ms": snappedf((t1 - t0) / 1000.0, 0.1), "rooms": g, "grid_ms": snappedf((Time.get_ticks_usec() - t1) / 1000.0, 0.1)}
	_night_warm = 3

## Night warm-up (V3.1 stall trace, UI: the first night frame cost 108-150 ms of shader and
## light-variant compiles). For 3 frames after a load the view is drawn at full night with an
## omni and a spot light near the focus, under an opaque cover, then the time is restored.
func _night_warmup() -> void:
	if _night_warm <= 0:
		return
	if _warm_restore < -1.5:
		_warm_restore = time_override
		time_override = 420.0
		_warm_t0 = _time
		_sites_clock = 0.0
		_warm_cover = CanvasLayer.new()
		_warm_cover.layer = 120
		var cr := ColorRect.new()
		cr.color = Color(0, 0, 0, 1)
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_warm_cover.add_child(cr)
		add_child(_warm_cover)
		var cam: Camera3D = get_viewport().get_camera_3d()
		var at: Vector3 = _focus_now + Vector3(0, 4, 0)
		var om := OmniLight3D.new()
		om.omni_range = 600.0
		om.light_energy = 1.0
		add_child(om)
		om.global_position = at
		var sp := SpotLight3D.new()
		sp.spot_range = 600.0
		sp.spot_angle = 89.0
		add_child(sp)
		sp.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at + Vector3(0, 150, 0))
		# (both reach every structure in view: each material meets an omni and a spot once)
		_warm_nodes = [om, sp]
		# Models first used mid-game (a pile of bought goods, a supply pod, meteor props, a ship
		# kind not on a pad yet): drawn once, tiny, in front of the camera (V3.1 stall trace).
		_warm_handles = []
		if cam != null:
			var fwd: Vector3 = -cam.global_transform.basis.z
			var wx := Transform3D(Basis.from_scale(Vector3(0.01, 0.01, 0.01)), cam.global_position + fwd * 3.0)
			for f in ["crate_raw", "crate_material", "crate_component", "crate_medical", "crate_food", "crate", "supply_pod", "meteor_rock", "crater", "fragments", "meteor_turret"]:
				if Models.has_model(f):
					_warm_handles.append(inst.add(Models.prop([f], 0.5, "exterior", "logistics"), wx))
			for k in ["trader", "shuttle", "liner", "medical", "science", "courier"]:
				if Models.has_model("ship_" + k):
					var sn: Node3D = Models.node_from(Models.prop(["ship_" + k], 1.0, "exterior", "logistics"))
					add_child(sn)
					sn.global_transform = wx
					_warm_nodes.append(sn)
	# Hold the night until the sky is fully dark and every structure's Lights are on (at most
	# 40 frames); the flame, dust and mist warm-up of fx_traffic runs in the same frames.
	# (at least 1.3 s: the night lamp sites, helmet lamps and light pools refresh once a second)
	if _night_warm == 1 and (float(sky.night) < 0.97 or _time - _warm_t0 < 1.3) and _time - _warm_t0 < 3.0:
		_night_warm = 2
	# First the sunset itself (the sun at the horizon: 108-150 ms of first-use work, UI trace),
	# then full night.
	time_override = 360.0 if _time - _warm_t0 < 0.6 else 420.0
	_warm_frames += 1
	_night_warm -= 1
	if _night_warm == 0:
		boot_info["warm_frames"] = _warm_frames
		boot_info["warm_night"] = snappedf(float(sky.night), 0.01)
		boot_info["warm_s"] = snappedf(_time - _warm_t0, 0.01)
		_cover_hold = 0.0
		time_override = _warm_restore
		_warm_restore = -2.0
		for nd in _warm_nodes:
			if is_instance_valid(nd):
				(nd as Node).queue_free()
		_warm_nodes = []
		for hh in _warm_handles:
			inst.remove(hh)
		_warm_handles = []
var boot_info := {}
## The load cover stays until the first-draw frames are over (shader compiles of a new colony):
## two frames in a row under 34 ms, at most 4 s. Stall counters restart when it lifts.
var _cover_hold := -1.0
var _cover_fast := 0
func _cover_update(delta: float) -> void:
	if _cover_hold < 0.0 or _warm_cover == null:
		return
	_cover_hold += delta
	_cover_fast = _cover_fast + 1 if delta < 0.034 else 0
	if _cover_fast >= 20 or _cover_hold > 5.0:
		boot_info["cover_s"] = snappedf(_cover_hold, 0.01)
		boot_info["cover_frames_over_50"] = int(stall_count["frame_over_50"])
		boot_info["cover_max_ms"] = snappedf(float(stall_count["max_frame_ms"]), 0.1)
		_warm_cover.queue_free()
		_warm_cover = null
		_cover_hold = -1.0
		stall_count = {"view_over_25": 0, "frame_over_50": 0, "frames": 0, "max_frame_ms": 0.0, "max_view_ms": 0.0}
		stalls = []

func _photo_mode() -> bool:
	var r = rig()
	return r != null and bool(r.get("_photo"))

## Running average of each part of sync() in milliseconds (stats()["prof"]).
var _prof_ms := {}
func _prof(name: String, t0: int) -> int:
	var t1: int = Time.get_ticks_usec()
	_prof_ms[name] = lerpf(float(_prof_ms.get(name, 0.0)), (t1 - t0) / 1000.0, 0.05)
	_frame_secs[name] = (t1 - t0) / 1000.0
	return t1

## Stall log (UI item 6): every view frame over 25 ms with its sections, and every real
## frame over 50 ms (the whole engine frame, from delta).
var _frame_secs := {}
var stalls: Array = []
var stall_count := {"view_over_25": 0, "frame_over_50": 0, "frames": 0, "max_frame_ms": 0.0, "max_view_ms": 0.0}
var _last_proc_ms := 0.0
var _batch_keys := {}
var _new_batches: Array = []
var _child_n := 0
func _log_stall(delta: float, view_ms: float) -> void:
	if inst.batches.size() != _batch_keys.size():
		for bk in inst.batches:
			if not _batch_keys.has(bk):
				_batch_keys[bk] = true
				_new_batches.append("%.1fs %s" % [_time, String(bk).get_file()])
		while _new_batches.size() > 6:
			_new_batches.pop_front()
	var cn: int = get_child_count()
	# (the frame before this one: its process time; delta is that frame's full length)
	_last_proc_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	stall_count["frames"] = int(stall_count["frames"]) + 1
	stall_count["max_frame_ms"] = maxf(float(stall_count["max_frame_ms"]), delta * 1000.0)
	stall_count["max_view_ms"] = maxf(float(stall_count["max_view_ms"]), view_ms)
	if delta * 1000.0 > 50.0:
		stall_count["frame_over_50"] = int(stall_count["frame_over_50"]) + 1
		if stalls.size() < 40:
			stalls.append("%.1fs FRAME %.0f ms (view %.0f ms, last process %.0f ms, sim step avg %.1f ms x speed %d, mist %d, draws %d)" % [_time, delta * 1000.0, view_ms, _last_proc_ms, float(get_parent().get("_step_ms") if get_parent().get("_step_ms") != null else -1.0), int(get_parent().get("speed") if get_parent().get("speed") != null else 0), airlock.get_child_count() if airlock != null else 0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
			var hz_now: Array = []
			for ev in sim.hazards.active():
				hz_now.append(String(ev.get("kind", "")) + ":" + String(ev.get("phase", "")))
			var lg0: Array = sim.state.get("log", [])
			stalls.append("   new batches %s view children %d mem %.1f MB (max %.1f)" % [str(_new_batches), cn, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0])
			stalls.append("   hazards %s fx children %d hz children %d last log %s" % [str(hz_now), fx.get_child_count(), hazards.get_child_count(), str(lg0[-1].get("code", "")) if not lg0.is_empty() and lg0[-1] is Dictionary else ""])
			stalls.append("   night %.2f bld %d agents %d ships %s objects %d" % [float(sky.night), bmeta.size(), sim.state["agents"].size(), str(traffic.info().map(func(r): return String(r["kind"]) + ":" + String(r["phase"]) + ":" + str(r["hgt"]))) if traffic != null else "", int(Performance.get_monitor(Performance.OBJECT_COUNT))])
	if view_ms > 25.0:
		stall_count["view_over_25"] = int(stall_count["view_over_25"]) + 1
		var top: Array = []
		for k in _frame_secs:
			if float(_frame_secs[k]) > 3.0:
				top.append("%s %.0f" % [k, _frame_secs[k]])
		if stalls.size() < 40:
			stalls.append("%.1fs view %.0f ms: %s" % [_time, view_ms, ", ".join(top)])

func _focus() -> Vector3:
	var r = rig()
	if r != null and r.get("focus") != null:
		return r.focus
	return to3(sim.world.center)

func _storm_level() -> float:
	if _forced_storm >= 0.0:
		return _forced_storm
	# state.events.storm is a record that lives on between storms (sim/events.gd):
	# only phase "active" is a storm. It builds up over the last 20 s of the warning and
	# clears over the last 20 s of the storm.
	var ev = sim.state.get("events", {})
	if not (ev is Dictionary) or not (ev as Dictionary).has("storm") or not (ev["storm"] is Dictionary):
		return 0.0
	var s: Dictionary = ev["storm"]
	var hz: float = float(sim.bal["tick_hz"])
	var tick: float = float(sim.state["tick"])
	match String(s.get("phase", "none")):
		"warning":
			return clampf(1.0 - (float(s.get("at", 0)) - tick) / (20.0 * hz), 0.0, 1.0) * 0.6
		"active":
			return clampf((float(s.get("end", 0)) - tick) / (20.0 * hz), 0.0, 1.0)
	return 0.0

# ---------------------------------------------------------------- structures
func _vis_mode(b: Dictionary) -> String:
	if b["def"] == "meridian":
		return "ship"
	if b["def"] == "cable":
		return "cable:" + ("on" if b["state"] == "active" else b["state"])
	if bool(b.get("demolish", false)):
		return "node:demolish"
	match String(b["state"]):
		"blueprint": return "node:blueprint"
		"building": return "node:building"
		"broken": return "node:broken"
	return "inst"

func _template(b: Dictionary) -> Dictionary:
	var def: Dictionary = sim.bdef(b["def"])
	if b["kind"] == "link":
		return Models.prop([String(b["def"])], 1.2, "room", "logistics")
	var size: int = int(b.get("size", 1)) if def.has("sizes") else -1
	# Old-save airlocks (record radius 2.8 m, before the 3.4 m airlock): ART-HAB's own R 2.8
	# model, unscaled (ART-HAB F0; never airlock_m scaled down).
	if String(b["def"]) == "airlock" and float(b["radius"]) < 3.0 and Models.has_model("airlock_r28"):
		return Models.status_tinted(Models.building("airlock_r28", -1, float(b["radius"]), float(b["radius"]), b["kind"], def.get("category", "logistics")))
	var s_r: float = -1.0
	if size >= 0 and (def["sizes"] as Dictionary).has("radius"):
		var ra: Array = def["sizes"]["radius"]
		s_r = float(ra[clampi(size, 0, ra.size() - 1)])
	var tb: Dictionary = Models.building(b["def"], size, float(b["radius"]), float(def.get("radius", b["radius"])), b["kind"], def.get("category", "logistics"), s_r)
	# Airlock lights take their colour from the cycle (fx_airlock).
	return Models.status_tinted(tb) if String(b["def"]) == "airlock" else tb

func _bxf(b: Dictionary) -> Transform3D:
	if b["kind"] == "link":
		var p0: Vector2 = b["p0"]
		var p1: Vector2 = b["p1"]
		var y0: float = h(p0.x, p0.y)
		var y1: float = h(p1.x, p1.y)
		var length: float = maxf(0.5, float(b["length"]) + 0.5)
		var basis := Basis(Vector3.UP, -float(b["rot"])) * Basis(Vector3(0, 0, 1), atan2(y1 - y0, maxf(0.5, float(b["length"]))))
		return Transform3D(basis * Basis.from_scale(Vector3(length, 1, 1)), Vector3(b["pos"].x, (y0 + y1) * 0.5 + 0.05, b["pos"].y))
	return Transform3D(Basis(Vector3.UP, -float(b["rot"])), to3(b["pos"], 0.02))

var _mode_flips := {}
var _no_cutaway := false   # test only (__fhr "cutaway 0"): roofs stay on near the camera
func _sync_buildings(delta: float) -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in bmeta.keys():
		if not blds.has(id):
			_drop_building(id)
	var changed := false
	for id in blds:
		var b: Dictionary = blds[id]
		var mode: String = _vis_mode(b)
		if not bmeta.has(id):
			_make_building(b, mode)
			changed = true
			_made_now += 1
		elif bmeta[id]["mode"] != mode:
			_mode_flips[id] = "%s>%s" % [bmeta[id]["mode"], mode]
			_drop_building(id)
			_make_building(b, mode)
			changed = true
		# Slow work (level parts, crops, smoke) runs for each structure every 6th frame.
		_update_building(b, delta, (int(id) + _frame) % 6 == 0)
	if changed:
		doors.mark_dirty()
	var sig := "%d:%d" % [blds.size(), int(sim.state["rev"].get("walk", 0))]
	if changed or sig != _rev_sig:
		_rev_sig = sig
		terrain.update_contact(blds)
		terrain.hide_pebbles_under(blds)
		terrain.set_pads(_pads_of(blds))

## Terrain pads (critic round 6): the terrain mesh stays under every structure base and every
## corridor floor, so the ground never shows through a floor.
func _pads_of(blds: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = blds.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			var p0: Vector2 = b["p0"]
			var p1: Vector2 = b["p1"]
			out.append({"p0": p0, "p1": p1, "r": 1.4, "y0": h(p0.x, p0.y) + 0.05, "y1": h(p1.x, p1.y) + 0.05})
		else:
			var pos: Vector2 = b["pos"]
			out.append({"c": pos, "r": float(b["radius"]) + 0.3, "y": h(pos.x, pos.y) + 0.02})
	return out

func _make_building(b: Dictionary, mode: String) -> void:
	var id: int = b["id"]
	var meta := {"mode": mode, "def": b["def"], "h": -1, "node": null, "handles": [], "crops": [], "crop_sig": [],
		"open": 0.0, "level": -1, "rotor": 0.0, "lights": false, "light_th": 0.3 + Rng.hash2(id, 3, 11) * 0.35,
		"tpl": {}, "top": 3.0, "glass_roof": false, "anchors": {}, "xf": Transform3D.IDENTITY, "build_shown": 0.0}
	bmeta[id] = meta
	if mode == "ship":
		ship.attach(b)
		return
	if mode.begins_with("cable"):
		_make_cable(b, meta, mode)
		return
	var tpl: Dictionary = _template(b)
	meta["tpl"] = tpl
	var xf: Transform3D = _bxf(b)
	meta["xf"] = xf
	var s: float = float(tpl.get("scale", 1.0))
	var aabb: AABB = tpl["aabb"]
	meta["top"] = maxf(1.0, aabb.end.y * s)
	for p in tpl["parts"]:
		if p["group"] == "Roof":
			var mesh: Mesh = p["mesh"]
			for si in mesh.get_surface_count():
				var m: Material = mesh.surface_get_material(si)
				if m != null and m.resource_name == "Glass":
					meta["glass_roof"] = true
	var anchors := {}
	for a in tpl["anchors"]:
		anchors[a] = xf * Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3.ZERO) * (tpl["anchors"][a] as Transform3D)
	meta["anchors"] = anchors
	if mode == "inst":
		meta["h"] = inst.add(tpl, xf)
		inst.set_hidden(meta["h"], "Interior", not bool(meta["glass_roof"]))
		inst.set_hidden(meta["h"], "Tall", not bool(meta["glass_roof"]))
		inst.set_hidden(meta["h"], "WallsIn", not bool(meta["glass_roof"]))
		inst.set_hidden(meta["h"], "Lights", true)
		inst.set_hidden(meta["h"], "Scaffold", true)
		_apply_level(b, meta)
		if b["kind"] != "link" and _has_trays(b):
			_sync_crops(b, meta, true)
	else:
		var state: String = mode.substr(5)
		var node: Node3D = Models.node_from(tpl)
		node.transform = xf * node.transform
		# Solid part: per-surface construction materials. Hologram part: a sibling mesh
		# with the hologram material (next_pass on surface overrides does not draw in the
		# Compatibility renderer, tested 2026-09-24).
		var holo: ShaderMaterial = holo_material(HOLO_COLORS.get(state, Color(0.35, 0.82, 1.0)), 0.55 if state == "broken" else 0.85).duplicate()
		var mats: Array = []
		var by_src := {}
		for mi in Models.meshes(node):
			var m3: MeshInstance3D = mi
			var mesh: Mesh = m3.mesh
			for si in mesh.get_surface_count():
				var src: Material = mesh.surface_get_material(si)
				var sk: int = src.get_instance_id() if src != null else 0
				if not by_src.has(sk):
					by_src[sk] = _construct_material(src, state)
					mats.append(by_src[sk])
				m3.set_surface_override_material(si, by_src[sk])
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if state == "blueprint" else m3.cast_shadow
			var hm := MeshInstance3D.new()
			hm.mesh = mesh
			hm.material_override = holo
			hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hm.name = "Holo"
			m3.add_child(hm)
		add_child(node)
		meta["node"] = node
		meta["mats"] = mats
		meta["holo"] = holo
		meta["line"] = [INF, INF, -1.0]
		# Level parts above the current level stay hidden.
		var lvl: int = int(b.get("level", 1))
		for n in [2, 3, 4, 5]:
			var g = node.find_child("L%d" % n, false, false)
			if g != null:
				(g as Node3D).visible = lvl >= n
		for gname in ["Lights", "Scaffold"]:
			var g2 = node.find_child(gname, false, false)
			if g2 != null:
				(g2 as Node3D).visible = false
		if state == "building" or state == "blueprint":
			fx.site_start(id, xf.origin, float(b["radius"]) if b["kind"] != "link" else 1.5)

func _drop_building(id: int) -> void:
	var meta: Dictionary = bmeta[id]
	if meta["mode"] == "ship":
		ship.detach()
	if int(meta["h"]) != -1:
		inst.remove(meta["h"])
	for hh in meta["handles"]:
		inst.remove(hh)
	for c in meta["crops"]:
		inst.remove(c)
	if meta["node"] != null:
		(meta["node"] as Node3D).queue_free()
	fx.site_stop(id)
	fx.emitter_stop("b%d" % id)
	if _labels.has(id):
		(_labels[id] as Label3D).queue_free()
		_labels.erase(id)
	bmeta.erase(id)

func _apply_level(b: Dictionary, meta: Dictionary) -> void:
	var lvl: int = int(b.get("level", 1))
	if lvl == int(meta["level"]):
		return
	var first: bool = int(meta["level"]) == -1
	meta["level"] = lvl
	_apply_roof(b, meta)
	if not first:
		fx.burst("sparks", (meta["xf"] as Transform3D).origin + Vector3(0, float(meta["top"]) * 0.8, 0), 40)
		fx.burst("dust", (meta["xf"] as Transform3D).origin, 16)

## Roof and the level parts that stand on it open together (ART-A request 1); level parts
## above the level stay hidden.
func _apply_roof(b: Dictionary, meta: Dictionary) -> void:
	var hnd: int = meta["h"]
	var lvl: int = int(meta["level"])
	var o: float = float(meta["open"])
	var e: float = o * o * (3.0 - 2.0 * o)
	var k: float = maxf(0.02, 1.0 - e)
	var xf := Transform3D(Basis.from_scale(Vector3(k, k, k)), Vector3(0, e * 2.2, 0))
	var room: bool = b["kind"] == "room"
	var groups: Array = ["Roof"]
	for n in [2, 3, 4, 5]:
		if lvl < n:
			inst.set_hidden(hnd, "L%d" % n, true)
		elif room:
			groups.append("L%d" % n)
		else:
			inst.set_hidden(hnd, "L%d" % n, false)
	for g in groups:
		if o >= 1.0:
			inst.set_hidden(hnd, g, true)
		else:
			inst.set_hidden(hnd, g, false)
			if o <= 0.0:
				inst.clear_extra(hnd, g)
			else:
				inst.set_extra(hnd, g, xf)
	# V3.1 (ART-HAB D1/D2/R5): in the cutaway everything above 1.40 m goes: every group whose
	# name ends in Top or Status, the pressure lights, the beacon, roof decals; level decals
	# show with their level only.
	for g in (meta["tpl"].get("groups", {}) as Dictionary):
		var gs: String = g
		if gs.ends_with("Top") or gs.ends_with("Status") or gs.begins_with("PressureLight") or gs == "Beacon" or gs == "DecalR":
			inst.set_hidden(hnd, gs, o > 0.0)
		elif gs.begins_with("DecalL"):
			inst.set_hidden(hnd, gs, o > 0.0 or lvl < int(gs.substr(6)))
	if not bool(meta["glass_roof"]):
		inst.set_hidden(hnd, "Interior", o <= 0.0)
		inst.set_hidden(hnd, "Tall", o <= 0.0)
		inst.set_hidden(hnd, "WallsIn", o <= 0.0)

func _has_trays(b: Dictionary) -> bool:
	return (b.get("trays", []) as Array).size() > 0

func _update_building(b: Dictionary, delta: float, slow: bool = true) -> void:
	var id: int = b["id"]
	var meta: Dictionary = bmeta[id]
	var mode: String = meta["mode"]
	if mode == "ship" or mode.begins_with("cable"):
		return
	if mode == "inst":
		var hnd: int = meta["h"]
		if slow:
			_apply_level(b, meta)
		# Roof cutaway: nearby roofs open when the camera is close; the selected one always.
		if b["kind"] != "link" or b["def"] == "corridor":
			var near: bool = camera_distance < 44.0 and (meta["xf"] as Transform3D).origin.distance_to(_focus_now) < camera_distance * 1.1 + 8.0 and not _no_cutaway
			var want: float = 1.0 if (near or (selected_kind == "building" and selected_id == id)) else 0.0
			var o: float = float(meta["open"])
			if o != want:
				meta["open"] = move_toward(o, want, delta * 3.5)
				_apply_roof(b, meta)
		# Rotor spins with the real wind.
		if (meta["tpl"]["groups"] as Dictionary).has("Rotor"):
			var w: float = float(sim.state["env"].get("wind", 3.0))
			# A wind storm spins the rotors up (state.env.wind_mult, V3 §4.5).
			var wm: float = float(sim.state["env"].get("wind_mult", 1.0))
			meta["rotor"] = fmod(float(meta["rotor"]) + delta * (0.3 + w * 0.55) * wm * (1.0 if b["state"] == "active" else 0.0), TAU)
			inst.set_extra(hnd, "Rotor", Transform3D(Basis(meta["tpl"]["rotor_axis"], float(meta["rotor"])), Vector3.ZERO))
		# Lamps switch on one by one at dusk; comms-tower beacons blink.
		var lit: bool = sky.night > float(meta["light_th"]) and b["state"] == "active"
		if b["def"] == "comms_tower" and lit:
			lit = fmod(_time + float(id) * 0.37, 1.4) < 0.45
		if (meta["tpl"]["groups"] as Dictionary).has("Plasma"):
			var on: bool = b["state"] == "active" and bool(b.get("enabled", true)) and String(b.get("block", "")) == ""
			if on != bool(meta.get("plasma", true)):
				meta["plasma"] = on
				inst.set_hidden(hnd, "Plasma", not on)
		if lit != bool(meta["lights"]):
			meta["lights"] = lit
			inst.set_hidden(hnd, "Lights", not lit)
		if slow:
			if b["kind"] != "link" and _has_trays(b):
				_sync_crops(b, meta, false)
			_sync_building_fx(b, meta)
	else:
		var node: Node3D = meta["node"]
		var state: String = mode.substr(5)
		var base_y: float = (meta["xf"] as Transform3D).origin.y
		var top: float = float(meta["top"])
		var build_y := -100000.0
		var holo_y := -100000.0
		match state:
			"blueprint":
				build_y = -100000.0
				holo_y = -100000.0
			"building":
				var f: float = clampf(float(b["progress"]) / maxf(1.0, float(b["work_total"])), 0.0, 1.0)
				meta["build_shown"] = lerpf(float(meta["build_shown"]), f, 1.0 - exp(-delta * 4.0))
				build_y = base_y - 0.05 + float(meta["build_shown"]) * (top + 0.1)
				holo_y = build_y
				fx.site_update(id, build_y, true)
			"demolish", "broken":
				build_y = 100000.0
				holo_y = -100000.0
		if id == _debug_node:
			build_y = 100000.0
		var dark: float = 0.55 if state == "broken" else 0.0
		var line: Array = meta.get("line", [INF, INF, -1.0])
		if absf(float(line[0]) - build_y) > 0.002 or absf(float(line[1]) - holo_y) > 0.002 or float(line[2]) != dark:
			meta["line"] = [build_y, holo_y, dark]
			for m in meta.get("mats", []):
				(m as ShaderMaterial).set_shader_parameter("build_y", build_y)
				(m as ShaderMaterial).set_shader_parameter("tint_dark", dark)
			if meta.get("holo") != null:
				(meta["holo"] as ShaderMaterial).set_shader_parameter("holo_min_y", holo_y)
		if state == "broken":
			fx.emitter_set("b%d" % id, "smoke_dark", (meta["xf"] as Transform3D).origin + Vector3(0, top * 0.7, 0), 0.6)
			fx.emitter_set("b%d_sp" % id, "sparks_idle", (meta["xf"] as Transform3D).origin + Vector3(0, top * 0.5, 0), 0.5)

## Smoke from chimneys, steam, spray, fusion pulse: tied to real activity.
func _sync_building_fx(b: Dictionary, meta: Dictionary) -> void:
	var id: int = b["id"]
	var working: bool = b["state"] == "active" and bool(b.get("enabled", true)) and String(b.get("block", "")) == "" and (bool(b.get("powered", true)) or float(sim.bdef(b["def"]).get("power", 0.0)) <= 0.0)
	var anchors: Dictionary = meta["anchors"]
	var def: String = b["def"]
	var key := "b%d" % id
	if not working:
		fx.emitter_stop(key)
		fx.emitter_stop(key + "_2")
		fx.emitter_stop(key + "_v1")
		fx.emitter_stop(key + "_v2")
		return
	var xf: Transform3D = meta["xf"]
	var top: float = float(meta["top"])
	var vents: Array = []
	for a in anchors:
		var an: String = a
		if an.begins_with("Smoke") or an.begins_with("Fume"):
			vents.append(["smoke" if def in ["refinery", "glassworks", "fuel_refinery", "fabricator", "polymer_plant"] else "steam", (anchors[a] as Transform3D).origin])
		elif an.begins_with("Vent") or an.begins_with("Vapour") or an.begins_with("Steam"):
			vents.append(["steam", (anchors[a] as Transform3D).origin])
	if not vents.is_empty():
		for i in mini(3, vents.size()):
			fx.emitter_set(key + ("" if i == 0 else "_v%d" % i), vents[i][0], vents[i][1], 1.0)
	elif def in ["refinery", "glassworks", "kitchen", "fuel_refinery"]:
		fx.emitter_set(key, "smoke" if def != "kitchen" else "steam", xf.origin + Vector3(0, top + 0.2, 0), 0.8)
	elif def in ["oxygen_plant", "atmo_processor", "water_recycler"]:
		fx.emitter_set(key, "steam", xf.origin + Vector3(0, top + 0.1, 0), 0.6)
	if def == "water_extractor":
		var p: Vector3 = (anchors["Spray"] as Transform3D).origin if anchors.has("Spray") else xf.origin + Vector3(0, 0.6, 0)
		fx.emitter_set(key + "_2", "spray", p, 1.0)
	elif def == "fusion_reactor":
		var p2: Vector3 = (anchors["Core"] as Transform3D).origin if anchors.has("Core") else xf.origin + Vector3(0, top * 0.45, 0)
		fx.emitter_set(key + "_2", "pulse", p2, 1.0)

func _sync_crops(b: Dictionary, meta: Dictionary, force: bool) -> void:
	var trays: Array = b.get("trays", [])
	var def: Dictionary = sim.bdef(b["def"])
	var offs: Array = def.get("tray_offsets", [])
	if def.has("sizes") and (def["sizes"] as Dictionary).has("tray_offsets"):
		var arr: Array = def["sizes"]["tray_offsets"]
		var sz: int = clampi(int(b.get("size", 1)), 0, arr.size() - 1)
		offs = arr[sz]
	var sig: Array = []
	for i in trays.size():
		var tray: Dictionary = trays[i]
		if tray.is_empty() or String(tray.get("state", "empty")) == "empty":
			sig.append("")
			continue
		var crop: String = String(tray.get("crop", b.get("crop", "potato")))
		sig.append("%s:%d" % [crop, _stage_of(tray, crop)])
	if not force and sig == meta["crop_sig"]:
		return
	meta["crop_sig"] = sig
	for c in meta["crops"]:
		inst.remove(c)
	meta["crops"] = []
	var xf: Transform3D = meta["xf"]
	for i in trays.size():
		if sig[i] == "" or i >= offs.size():
			continue
		var parts: PackedStringArray = String(sig[i]).split(":")
		var tpl: Dictionary = Models.prop(["crop_" + parts[0], "crop"], 1.0, "exterior", "food")
		var o: Array = offs[i]
		var local := Transform3D(Basis(), Vector3(float(o[0]), 0.56, -float(o[1])))
		var hnd: int = inst.add(tpl, xf * local)
		var stage: int = int(parts[1])
		for s in [1, 2, 3]:
			inst.set_hidden(hnd, "Stage%d" % s, s != stage)
		meta["crops"].append(hnd)

func _stage_of(tray: Dictionary, crop: String) -> int:
	if String(tray.get("state", "")) == "ready":
		return 3
	var cycle: float = float(sim.bal.get("crop_cycle_seconds", 300.0))
	var crops = sim.content.get("crops", {})
	if crops is Dictionary and (crops as Dictionary).has(crop):
		var c: Dictionary = crops[crop]
		for k in ["cycle", "cycle_seconds", "cycle_s"]:
			if c.has(k) and float(c[k]) > 0.0:
				cycle = float(c[k])
				break
	var g: float = float(tray.get("growth", 0.0)) / maxf(1.0, cycle)
	return 1 if g < 0.34 else (2 if g < 0.75 else 3)

func _make_cable(b: Dictionary, meta: Dictionary, mode: String) -> void:
	var p0: Vector2 = b["p0"]
	var p1: Vector2 = b["p1"]
	var n: int = maxi(1, int(ceil(p0.distance_to(p1) / 3.0)))
	var seg_tpl: Dictionary = Models.prop(["cable_segment"], 0.2, "exterior", "utilities")
	var active: bool = mode == "cable:on"
	if (seg_tpl["key"] as String).begins_with("fallback"):
		seg_tpl = _cable_tpl()
	for i in n:
		var a: Vector3 = to3(p0.lerp(p1, float(i) / n), 0.07)
		var c: Vector3 = to3(p0.lerp(p1, float(i + 1) / n), 0.07)
		var dirv: Vector3 = c - a
		var length: float = dirv.length()
		if length < 0.01:
			continue
		var basis: Basis = Basis.looking_at(dirv / length, Vector3.UP) * Basis.from_scale(Vector3(1, 1, length))
		meta["handles"].append(inst.add(seg_tpl, Transform3D(basis, (a + c) * 0.5)))
	var post_tpl: Dictionary = _cable_post_tpl()
	for e in [p0, p1]:
		meta["handles"].append(inst.add(post_tpl, Transform3D(Basis(), to3(e, 0.0))))
	if not active:
		for hh in meta["handles"]:
			inst.set_custom(hh, Color(0.4, 0.8, 1.0))

## Meteor fragments: ART-HAB's prop when it exists, else a procedural cluster.
func _fragment_tpl() -> Dictionary:
	for mid in ["meteor_fragments", "fragment_pile", "fragments", "meteor_fragment"]:
		if Models.has_model(mid):
			return Models.prop([mid], 1.2, "exterior", "space")
	if _cable_tpl_cache.has("frag"):
		return _cable_tpl_cache["frag"]
	var root := Node3D.new()
	var rock := StandardMaterial3D.new()
	rock.resource_name = "HullDark"
	rock.albedo_color = Color("2a2522")
	rock.roughness = 0.35
	rock.metallic = 0.45
	var glow := StandardMaterial3D.new()
	glow.resource_name = "Glow"
	glow.albedo_color = Color("b58cff")
	glow.emission_enabled = true
	glow.emission = Color("a070ff")
	glow.emission_energy_multiplier = 2.2
	var rng := RandomNumberGenerator.new()
	rng.seed = 4040
	for i in 7:
		var mi := MeshInstance3D.new()
		mi.name = "Base_%d" % i
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.25, 0.55)
		sm.height = sm.radius * rng.randf_range(1.0, 1.5)
		sm.radial_segments = 7
		sm.rings = 4
		sm.material = rock
		mi.mesh = sm
		var a: float = TAU * i / 7.0
		mi.position = Vector3(cos(a) * rng.randf_range(0.3, 1.1), sm.height * 0.3, sin(a) * rng.randf_range(0.3, 1.1))
		mi.rotation = Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)
		root.add_child(mi)
	for i in 5:
		var cr := MeshInstance3D.new()
		cr.name = "Base_crystal_%d" % i
		var pm := CylinderMesh.new()
		pm.top_radius = 0.0
		pm.bottom_radius = rng.randf_range(0.08, 0.16)
		pm.height = rng.randf_range(0.5, 1.1)
		pm.radial_segments = 5
		pm.rings = 1
		pm.material = glow
		cr.mesh = pm
		var a2: float = rng.randf() * TAU
		cr.position = Vector3(cos(a2) * rng.randf_range(0.1, 0.8), pm.height * 0.4, sin(a2) * rng.randf_range(0.1, 0.8))
		cr.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		root.add_child(cr)
	var tpl: Dictionary = Models._parse(root, "proc:fragments")
	root.free()
	_cable_tpl_cache["frag"] = tpl
	return tpl

var _cable_tpl_cache := {}
func _cable_tpl() -> Dictionary:
	if _cable_tpl_cache.has("seg"):
		return _cable_tpl_cache["seg"]
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Base"
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.1, 1.02)
	var m := StandardMaterial3D.new()
	m.resource_name = "Rubber"
	m.albedo_color = Color("2b2f36")
	m.roughness = 0.7
	box.material = m
	mi.mesh = box
	root.add_child(mi)
	var stripe := MeshInstance3D.new()
	stripe.name = "Base_Stripe"
	var sb := BoxMesh.new()
	sb.size = Vector3(0.17, 0.02, 0.18)
	var m2 := StandardMaterial3D.new()
	m2.resource_name = "Hazard"
	m2.albedo_color = Color("f2b632")
	sb.material = m2
	stripe.mesh = sb
	stripe.position = Vector3(0, 0.05, 0)
	root.add_child(stripe)
	var tpl: Dictionary = Models._parse(root, "proc:cable_seg")
	root.free()
	_cable_tpl_cache["seg"] = tpl
	return tpl

func _cable_post_tpl() -> Dictionary:
	if _cable_tpl_cache.has("post"):
		return _cable_tpl_cache["post"]
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Base"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.26
	cm.height = 0.6
	var m := StandardMaterial3D.new()
	m.resource_name = "Hazard"
	m.albedo_color = Color("f2b632")
	m.roughness = 0.5
	cm.material = m
	mi.mesh = cm
	mi.position = Vector3(0, 0.3, 0)
	root.add_child(mi)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lights"
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	var lm := StandardMaterial3D.new()
	lm.resource_name = "Light"
	lm.albedo_color = Color("5ee07a")
	lm.emission_enabled = true
	lm.emission = Color("5ee07a")
	lm.emission_energy_multiplier = 2.0
	sm.material = lm
	lamp.mesh = sm
	lamp.position = Vector3(0, 0.64, 0)
	root.add_child(lamp)
	var tpl: Dictionary = Models._parse(root, "proc:cable_post")
	root.free()
	_cable_tpl_cache["post"] = tpl
	return tpl

# ---------------------------------------------------------------- status: icons and the few labels that matter
const ICON := {"no_power": 0, "no_water": 1, "no_air": 2, "broken": 3, "output_blocked": 4, "deposit_empty": 5, "materials": 6,
	"suit_range": 7, "off": 8, "building": 9, "unreachable": 7, "no_reservoir": 1, "demolish": 11, "alert": 10, "wear": 3}
const ICON_COLOR := {"no_power": Color("ffb547"), "no_water": Color("3ee0ff"), "no_air": Color("ff5a5f"), "broken": Color("ff5a5f"),
	"output_blocked": Color("ffb547"), "deposit_empty": Color("ffb547"), "materials": Color("3ee0ff"), "suit_range": Color("ff5a5f"),
	"off": Color("9aa3ad"), "building": Color("ffd166"), "unreachable": Color("ff5a5f"), "no_reservoir": Color("ffb547"), "demolish": Color("ff5a5f"), "alert": Color("ffb547")}

func _status(b: Dictionary) -> Dictionary:
	var state: String = b["state"]
	if bool(b.get("demolish", false)):
		return {"code": "demolish", "text": "REMOVING"}
	var blk: String = String(b.get("block", ""))
	if blk == "suit_range":
		return {"code": "suit_range", "text": "TOO FAR FROM AN AIRLOCK"}
	if state == "blueprint":
		if blk.begins_with("materials:"):
			var res: String = blk.substr(10)
			var nm: String = String(sim.bal["resource_names"].get(res, res)) if sim.bal.has("resource_names") else res
			return {"code": "materials", "text": "WAITING: " + nm.to_upper()}
		if blk == "unreachable":
			return {"code": "unreachable", "text": "OUT OF REACH"}
		return {"code": "materials", "text": ""}
	if state == "building":
		return {"code": "building", "progress": clampf(float(b["progress"]) / maxf(1.0, float(b["work_total"])), 0.0, 1.0)}
	if state == "broken":
		# V3 breakdowns: the fault type (hazards wear record) names what the repair needs.
		var wr: Dictionary = _wear_of(int(b["id"]))
		if not wr.is_empty() and bool(wr.get("broken", false)):
			var fault: String = String(wr.get("fault", "mechanical"))
			return {"code": "broken", "text": "BROKEN: " + fault.to_upper(), "color": FAULT_COLOR.get(fault, Color("ff5a5f"))}
		return {"code": "broken", "text": "BROKEN"}
	if state != "active" or b["kind"] == "link" or b["def"] == "meridian":
		return {}
	if not bool(b.get("enabled", true)):
		return {"code": "off"}
	var def: Dictionary = sim.bdef(b["def"])
	if float(def.get("power", 0.0)) > 0.0 and not bool(b.get("powered", true)):
		return {"code": "no_power"}
	match blk:
		"no_water": return {"code": "no_water"}
		"no_reservoir": return {"code": "no_reservoir"}
		"output_blocked": return {"code": "output_blocked"}
		"deposit_empty": return {"code": "deposit_empty"}
	if b["kind"] == "room" and not sim.util.building_supplied(b["id"]):
		return {"code": "no_air"}
	if bool(b.get("breach", false)):
		return {"code": "no_air", "text": "HULL BREACH"}
	# Worn machines above the forecast share of their failure threshold (V3 §4.3).
	var w2: Dictionary = _wear_of(int(b["id"]))
	if not w2.is_empty() and float(w2.get("fail_at", 100.0)) > 0.0 and float(w2.get("w", 0.0)) >= float(w2.get("fail_at", 100.0)) * 0.75:
		return {"code": "wear", "text": "WORN %d%%" % int(round(100.0 * float(w2["w"]) / float(w2["fail_at"]))), "color": Color("ffb547")}
	return {}

const FAULT_COLOR := {"mechanical": Color("ff9f1c"), "electrical": Color("3ee0ff"), "seal": Color("a78bfa")}

func _wear_of(bid: int) -> Dictionary:
	var hz = sim.state.get("hazards", {})
	if not (hz is Dictionary):
		return {}
	var wear = (hz as Dictionary).get("wear", {})
	if not (wear is Dictionary):
		return {}
	var rec = (wear as Dictionary).get(bid, (wear as Dictionary).get(str(bid), {}))
	return rec if rec is Dictionary else {}

func _sync_status() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var list: Array = []
	var keep := {}
	for id in blds:
		var b: Dictionary = blds[id]
		if not bmeta.has(id):
			continue
		var st: Dictionary = _status(b)
		if st.is_empty():
			continue
		var code: String = st["code"]
		var top: float = float(bmeta[id]["top"]) if b["kind"] != "link" else 2.6
		var pos: Vector3 = (bmeta[id]["xf"] as Transform3D).origin + Vector3(0, top + 1.4, 0)
		if b["def"] == "cable":
			pos = to3(b["pos"], 1.4)
		var urgent: bool = code in ["no_air", "broken", "suit_range", "no_power"]
		# Zoomed far out over the big map the badges would hide the colony: only urgent
		# ones up to 320 m, none beyond (the alert list still has every one).
		if camera_distance > 320.0 or (camera_distance > 180.0 and (not urgent or code == "no_power")):
			continue
		var icol: Color = st.get("color", ICON_COLOR.get(code, Color("ffb547")))
		list.append({"pos": pos, "icon": ICON.get(code, 10), "color": icol, "progress": float(st.get("progress", 0.0)), "pulse": 1.0 if urgent else 0.0})
		var text: String = String(st.get("text", ""))
		var show_text: bool = text != "" and (camera_distance < 75.0 or (selected_kind == "building" and selected_id == id)) and code != "materials" or (code == "materials" and text != "" and camera_distance < 45.0)
		if show_text:
			keep[id] = true
			var lab: Label3D = _labels.get(id)
			if lab == null:
				lab = Label3D.new()
				lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lab.no_depth_test = true
				lab.fixed_size = true
				lab.pixel_size = 0.00085
				lab.font_size = 22
				lab.outline_size = 7
				lab.outline_modulate = Color(0.02, 0.04, 0.08, 0.9)
				lab.render_priority = 10
				add_child(lab)
				_labels[id] = lab
			lab.text = text
			lab.modulate = (st.get("color", ICON_COLOR.get(code, Color("ffb547"))) as Color).lerp(Color.WHITE, 0.45)
			lab.position = pos + Vector3(0, -0.2, 0)
			lab.offset = Vector2(0, -26)
	for id in _labels.keys():
		if not keep.has(id):
			(_labels[id] as Label3D).queue_free()
			_labels.erase(id)
	icons.set_icons(list)

## Night lamps: airlock doors, the landing pad, the lander, beacons on tall structures.
func _refresh_sites() -> void:
	var sites: Array = []
	var beacons: Array = []
	var glows: Array = []
	for id in bmeta:
		var meta: Dictionary = bmeta[id]
		if meta["mode"] != "inst":
			continue
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty() or b["kind"] == "link":
			continue
		var def: Dictionary = sim.bdef(b["def"])
		var xf: Transform3D = meta["xf"]
		var anchors: Dictionary = meta["anchors"]
		if bool(def.get("airlock", false)):
			var dp: Vector2 = sim.nav.door_pos(b)
			var p := to3(dp, 2.6)
			if anchors.has("Door"):
				p = (anchors["Door"] as Transform3D).origin + Vector3(0, 0.6, 0)
			sites.append({"pos": p, "color": Color(1.0, 0.78, 0.5), "energy": 1.6, "range": 8.0})
			glows.append({"pos": p, "color": Color(1.0, 0.72, 0.4), "size": 1.2})
			var cyc = b.get("lock", {}).get("cyc", {}) if b.get("lock", {}) is Dictionary else {}
			if cyc is Dictionary and not (cyc as Dictionary).is_empty():
				beacons.append({"pos": p + Vector3(0, 0.5, 0), "color": Color(1.0, 0.62, 0.15), "rate": 3.0, "size": 1.0})
		elif b["def"] == "landing_pad":
			for k in 4:
				var a: float = TAU * k / 4.0 + PI * 0.25
				var lp: Vector3 = xf.origin + Vector3(cos(a), 0, sin(a)) * float(b["radius"]) * 0.85 + Vector3(0, 0.4, 0)
				beacons.append({"pos": lp, "color": Color(1.0, 0.3, 0.25), "rate": 1.0, "size": 0.9})
			sites.append({"pos": xf.origin + Vector3(0, 3.0, 0), "color": Color(0.85, 0.92, 1.0), "energy": 2.0, "range": 12.0})
		elif b["def"] == "lander":
			sites.append({"pos": xf.origin + Vector3(6.0, 2.0, 0), "color": Color(1.0, 0.8, 0.55), "energy": 1.4, "range": 9.0})
		if anchors.has("Beacon") and int(b.get("level", 1)) >= 5:
			beacons.append({"pos": (anchors["Beacon"] as Transform3D).origin, "color": Color(1.0, 0.25, 0.2), "rate": 0.8, "size": 1.0})
		elif b["def"] in ["wind_turbine", "comms_tower", "deep_drill", "mine"]:
			beacons.append({"pos": xf.origin + Vector3(0, float(meta["top"]) + 0.2, 0), "color": Color(1.0, 0.25, 0.2), "rate": 0.8, "size": 1.0})
		if anchors.has("Door") and not bool(def.get("airlock", false)):
			glows.append({"pos": (anchors["Door"] as Transform3D).origin + Vector3(0, 0.4, 0), "color": Color(1.0, 0.8, 0.55), "size": 0.8})
	sky.set_sites(sites)
	fx.set_lamps(glows, beacons)

# ---------------------------------------------------------------- agents
func _sync_agents(delta: float) -> void:
	var agents: Dictionary = sim.state["agents"]
	for id in ameta.keys():
		if not agents.has(id):
			_drop_agent(id)
	var suit_tpl: Dictionary = Models.prop(["colonist_suit", "colonist"], 0.4, "exterior", "housing")
	var in_tpl: Dictionary = Models.prop(["colonist_indoor", "colonist"], 0.4, "exterior", "housing")
	var tick: int = int(sim.state["tick"])
	for id in agents:
		var a: Dictionary = agents[id]
		var dead: bool = a["state"] != "alive"
		if dead and tick - int(a.get("death_tick", 0)) >= 1200:
			if ameta.has(id):
				_drop_agent(id)
			continue
		var inside: bool = a["where"] == "in"
		var tpl: Dictionary = in_tpl if inside else suit_tpl
		if not ameta.has(id):
			ameta[id] = {"h": -1, "tpl": "", "crate": -1, "crate_res": "", "pos": to3(a["pos"]), "yaw": 0.0, "tilt": 0.0, "moved": 0.0}
		var meta: Dictionary = ameta[id]
		var far: bool = (meta["pos"] as Vector3).distance_squared_to(_focus_now) > 14400.0 and camera_distance < 150.0
		if far and meta["tpl"] == tpl["key"] and (int(id) + _frame) % 3 != 0:
			continue
		if meta["tpl"] != tpl["key"]:
			if int(meta["h"]) != -1:
				inst.remove(meta["h"])
			var rc: Color = Models.ROLE_COLOR.get(a["role"], Color.WHITE)
			meta["h"] = inst.add(tpl, Transform3D(Basis(), meta["pos"]), Color(rc.r, rc.g, rc.b, Rng.hash2(id, 17, 3)))
			meta["tpl"] = tpl["key"]
		var pos: Vector2 = a["pos"]
		var y: float = h(pos.x, pos.y)
		if a["where"] != "out" and sim.state["buildings"].has(a["bld"]):
			var bb: Dictionary = sim.state["buildings"][a["bld"]]
			var bp: Vector2 = bb["pos"]
			y = h(bp.x, bp.y) + 0.18
			if bb["def"] == "lander":
				y += 1.6
		var spread := Vector3(sin(float(id) * 2.4), 0, cos(float(id) * 2.4)) * (0.35 if a["where"] != "out" else 0.25)
		var target := Vector3(pos.x, y, pos.y) + spread
		var before: Vector3 = meta["pos"]
		var now: Vector3 = target if before.distance_to(target) > 12.0 else before.lerp(target, 1.0 - exp(-delta * 14.0))
		meta["pos"] = now
		var moved: float = Vector2(now.x - before.x, now.z - before.z).length() / maxf(delta, 0.0001)
		meta["moved"] = lerpf(float(meta["moved"]), moved, 1.0 - exp(-delta * 8.0))
		if moved > 0.3:
			var want: float = -atan2(now.z - before.z, now.x - before.x)
			meta["yaw"] = lerp_angle(float(meta["yaw"]), want, 1.0 - exp(-delta * 10.0))
		var sleeping: bool = bool(a.get("sleeping", false))
		var tilt_target: float = deg_to_rad(88.0) if dead else (deg_to_rad(84.0) if sleeping else 0.0)
		meta["tilt"] = lerp_angle(float(meta["tilt"]), tilt_target, 1.0 - exp(-delta * 6.0))
		var basis := Basis(Vector3.UP, float(meta["yaw"])) * Basis(Vector3(0, 0, 1), float(meta["tilt"]))
		var xf := Transform3D(basis, now)
		var mv: float = float(meta["moved"])
		var swing: float = sin(_time * 9.0 + float(id)) * clampf(mv / 2.5, 0.0, 1.0) * 0.7
		var working: bool = String(a.get("plan_kind", "")) == "task" and mv < 0.2 and a["where"] != "lock" and not dead
		var arm: float = -0.9 + sin(_time * 7.0 + float(id)) * 0.35 if working else swing
		var extra := {
			"LegL": Transform3D(Basis(Vector3(0, 0, 1), swing), Vector3.ZERO),
			"LegR": Transform3D(Basis(Vector3(0, 0, 1), -swing), Vector3.ZERO),
			"ArmL": Transform3D(Basis(Vector3(0, 0, 1), -swing if not working else arm), Vector3.ZERO),
			"ArmR": Transform3D(Basis(Vector3(0, 0, 1), swing if not working else arm), Vector3.ZERO),
		}
		inst.set_all(meta["h"], xf, extra, {})
		# A carried crate is a real unit in the carrier inventory.
		var cargo: Dictionary = sim.inv.get_inv(a["inv"]).get("items", {}) if int(a.get("inv", -1)) != -1 else {}
		if cargo.is_empty() or dead:
			if int(meta["crate"]) != -1:
				inst.remove(meta["crate"])
				meta["crate"] = -1
				meta["crate_res"] = ""
		else:
			var res: String = cargo.keys()[0]
			var cxf := xf * Transform3D(Basis().scaled(Vector3(0.8, 0.8, 0.8)), Vector3(0.42, 0.95, 0))
			if meta["crate_res"] != res and int(meta["crate"]) != -1:
				inst.remove(meta["crate"])
				meta["crate"] = -1
			if int(meta["crate"]) == -1:
				meta["crate"] = inst.add(_crate_tpl(res), cxf, Models.RES_COLOR.get(res, Color.WHITE))
				meta["crate_res"] = res
			else:
				inst.set_xf(meta["crate"], cxf)

## Crate model by item category (ART-B): raw, material, component, food, medical.
func _crate_tpl(res: String) -> Dictionary:
	var items = sim.content.get("items", {})
	var cat := "component"
	if items is Dictionary and (items as Dictionary).has(res) and items[res] is Dictionary:
		cat = String(items[res].get("category", "component"))
	var file: String = {"raw": "crate_raw", "material": "crate_material", "component": "crate_component", "medical": "crate_medical",
		"crop": "crate_food", "dish": "crate_food", "water": "crate_material"}.get(cat, "crate")
	return Models.prop([file, "crate"], 0.3, "exterior", "logistics")

func _drop_agent(id: int) -> void:
	var meta: Dictionary = ameta[id]
	if int(meta["h"]) != -1:
		inst.remove(meta["h"])
	if int(meta["crate"]) != -1:
		inst.remove(meta["crate"])
	ameta.erase(id)

## Where every colonist body is now (doors open for them).
func _body_points() -> Array:
	if npc != null and npc.any_active():
		return npc.body_points()
	var out: Array = []
	for id in ameta:
		out.append(ameta[id]["pos"])
	return out

func agent_world_pos(id: int):
	if npc != null and npc.any_active():
		return npc.body_pos(id)
	if ameta.has(id):
		return ameta[id]["pos"]
	return null

# ---------------------------------------------------------------- piles and supply pods
func _sync_piles() -> void:
	var invs: Dictionary = sim.state["inventories"]
	for id in pmeta.keys():
		if not invs.has(id):
			for hh in pmeta[id]["handles"]:
				inst.remove(hh)
			pmeta.erase(id)
	for id in invs:
		var iv: Dictionary = invs[id]
		if iv["role"] != "pile" or pmeta.has(id):
			continue
		var p: Vector2 = iv["pos"]
		var base: Vector3 = to3(p, 0.0)
		var handles: Array = []
		if bool(iv.get("fragment", false)):
			# A meteor fragment site (V3 §4.3): dark glassy stones with glowing exotic shards.
			var yawf: float = Rng.hash2(id, 5, 1) * TAU
			handles.append(inst.add(_fragment_tpl(), Transform3D(Basis(Vector3.UP, yawf), base)))
		elif bool(iv.get("pod", false)):
			var pod_tpl: Dictionary = Models.prop(["supply_pod", "pod"], 1.0, "exterior", "logistics")
			var yaw: float = Rng.hash2(id, 5, 1) * TAU
			handles.append(inst.add(pod_tpl, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), 0.12), base)))
			fx.burst("dust", base, 24)
		else:
			var items: Dictionary = iv.get("items", {})
			var res: String = items.keys()[0] if not items.is_empty() else ""
			var crate_tpl: Dictionary = _crate_tpl(res)
			var col: Color = Models.RES_COLOR.get(res, Color("c07a3a"))
			var yaw2: float = Rng.hash2(id, 7, 1) * TAU
			var b := Basis(Vector3.UP, yaw2)
			for k in 3:
				var off := Vector3(k * 0.5 - 0.5, 0.0 if k < 2 else 0.45, 0.2 * k)
				if k == 2:
					off.x = -0.25
				handles.append(inst.add(crate_tpl, Transform3D(b, base + b * off + Vector3(0, 0.2 if int(iv.get("oid", 0)) > 0 else 0.0, 0)), col))
		pmeta[id] = {"handles": handles}

# ---------------------------------------------------------------- selection
func select(kind: String, id: int) -> void:
	selected_kind = kind
	selected_id = id
	_outline_sig = ""

func _sync_selection(delta: float) -> void:
	_sel_ring.visible = false
	var want_sig := ""
	if selected_kind == "building" and sim.state["buildings"].has(selected_id):
		var b: Dictionary = sim.state["buildings"][selected_id]
		var r: float
		var c: Vector2 = b["pos"]
		if b["def"] == "meridian":
			r = 24.0
		elif b["kind"] == "link":
			r = maxf(1.6, float(b["length"]) * 0.5 + 0.8)
		else:
			r = float(b["radius"]) + 0.7
		_sel_ring.visible = true
		_sel_ring.position = Vector3(c.x, 0.0, c.y)
		_sel_ring.scale = Vector3(r, 1.0, r)
		if bmeta.has(selected_id) and bmeta[selected_id]["mode"] == "inst" and b["kind"] != "link":
			want_sig = "%d:%d:%d" % [selected_id, int(b.get("level", 1)), 1 if float(bmeta[selected_id]["open"]) > 0.5 else 0]
	elif selected_kind == "agent" and ameta.has(selected_id):
		var p: Vector3 = ameta[selected_id]["pos"]
		_sel_ring.visible = true
		_sel_ring.position = Vector3(p.x, 0.0, p.z)
		_sel_ring.scale = Vector3(0.8, 1.0, 0.8)
	if want_sig != _outline_sig:
		_outline_sig = want_sig
		if _outline != null:
			_outline.queue_free()
			_outline = null
		if want_sig != "":
			_outline = _make_outline(selected_id)

func _make_outline(id: int) -> Node3D:
	var meta: Dictionary = bmeta[id]
	var b: Dictionary = sim.state["buildings"][id]
	var tpl: Dictionary = meta["tpl"]
	var root := Node3D.new()
	var lvl: int = int(b.get("level", 1))
	var open: bool = float(meta["open"]) > 0.5
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	for p in tpl["parts"]:
		if bool(p.get("shadow_only", false)):
			continue
		var g: String = p["group"]
		# Wall segments are left out: the outline shader does not know the doorway mask, so
		# hidden segments would show as cyan shells (critic round 2).
		# Critic round 13: only the body of the structure (Base, roof, levels). Decal bands drew
		# 2-3 stacked cyan rings on rooms, and the airlock's door, housing, status and *Top parts
		# (hidden in the cutaway) drew as solid cyan slabs.
		var body_part: bool = g == "Base" or g == "Roof" or (g.length() == 2 and g[0] == "L" and g[1].is_valid_int()) or g == "Rotor"
		if not body_part or g in ["Rotor"] or (open and (g == "Roof" or (g.length() == 2 and g[0] == "L" and b["kind"] == "room"))):
			continue
		if g.length() == 2 and g[0] == "L" and int(g[1]) > lvl:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.transform = p["xf"]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var s: float = float(tpl.get("scale", 1.0))
	root.transform = (meta["xf"] as Transform3D) * Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3.ZERO)
	add_child(root)
	return root

# ---------------------------------------------------------------- picking
func ground_point(cam: Camera3D, screen: Vector2):
	var from: Vector3 = cam.project_ray_origin(screen)
	var dir: Vector3 = cam.project_ray_normal(screen)
	if dir.y > -0.02:
		return null
	var y := 0.0
	var hit := Vector3.ZERO
	for i in 6:
		var t: float = (y - from.y) / dir.y
		hit = from + dir * t
		y = h(hit.x, hit.z)
	return Vector2(hit.x, hit.z)

## Returns {"kind", "id"} for what is under the cursor, or {}.
func pick(p: Vector2, include_agents: bool = true) -> Dictionary:
	if include_agents:
		var best := -1
		var best_d := 1.6
		for id in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][id]
			if a["state"] != "alive":
				continue
			var d: float = (a["pos"] as Vector2).distance_to(p)
			if d < best_d:
				best_d = d
				best = id
		if best != -1:
			return {"kind": "agent", "id": best}
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["def"] == "meridian":
			var dirv := Vector2(cos(float(b["rot"])), sin(float(b["rot"])))
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, b["pos"] - dirv * 16.0, b["pos"] + dirv * 16.0)
			if q.distance_to(p) <= 7.0:
				return {"kind": "building", "id": id}
			continue
		if b["kind"] != "link" and (b["pos"] as Vector2).distance_to(p) <= float(b["radius"]):
			return {"kind": "building", "id": id}
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			var cp: Vector2 = Geometry2D.get_closest_point_to_segment(p, b["p0"], b["p1"])
			if cp.distance_to(p) < (1.4 if b["def"] == "corridor" else 0.8):
				return {"kind": "building", "id": id}
	return {}

# ---------------------------------------------------------------- overlays
func set_overlay(name: String) -> void:
	overlay = name
	terrain.set_walk_overlay(name == "walk")
	var hz_ok: bool = terrain.set_hazard_overlay(name == "hazard", _hazard_fn())
	if name == "hazard" and not hz_ok:
		_log_once("hazard_overlay", "RENDER: hazard overlay needs sim.world.hazard_at(pos) or sim.hazards.zone_at(pos); not there yet")
	overlays.set_mode(name if name in ["power", "water", "air"] else "")

## The hazard zone field of V3 §1: sim.world.hazard_at(pos) (or sim.hazards.zone_at).
func _hazard_fn() -> Callable:
	if sim.world != null and sim.world.has_method("hazard_at"):
		return Callable(sim.world, "hazard_at")
	var hz = sim.get("hazards")
	if hz != null and hz is Object and (hz as Object).has_method("zone_at"):
		return Callable(hz, "zone_at")
	return Callable()

var _logged := {}
func _log_once(key: String, text: String) -> void:
	if _logged.has(key):
		return
	_logged[key] = true
	print(text)

## The camera may zoom out to see the whole map (about 450 m on the 810 m map, V3 §1).
var _range_set := -1
func _camera_range() -> void:
	var gn: int = int(sim.world.size)
	if _range_set == gn:
		return
	var r = rig()
	if r == null:
		return
	_range_set = gn
	r.max_distance = clampf(gn * 0.56, 200.0, 460.0)
	if r.camera != null:
		r.camera.far = maxf(1400.0, gn * 1.6 + 1300.0)

# ---------------------------------------------------------------- placement ghost (§12)
## A holographic ghost of `def_id` at sim position `pos`, rotation `rot` (sim radians).
## valid = green, not valid = red. Shows the footprint, the airlock door strip and, while
## placing, the suit-range rings around every airlock that has air.
func set_ghost(def_id: String, size: int, pos: Vector2, rot: float, valid: bool) -> void:
	ghost.set_ghost(def_id, size, pos, rot, valid)

func clear_ghost() -> void:
	ghost.clear()

## A preview of a corridor or cable from p0 to p1 (sim positions). p0 == null hides it.
func set_link_preview(p0, p1, kind: String = "corridor", valid: bool = true) -> void:
	ghost.set_link(p0, p1, kind, valid)

# ---------------------------------------------------------------- quality, time, events
## 0 = low (no shadows, 75% render scale, no pebbles), 1 = medium, 2 = high, 3 = ultra.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 3)
	if sky != null:
		sky.set_quality(quality)
	if terrain != null:
		terrain.set_quality(quality)
	if fx != null:
		fx.set_quality(quality)
	if interior != null:
		interior.set_quality(quality)
	if inst != null:
		inst.set_shadows(quality >= 1)
	if post != null:
		post.set_enabled(quality >= 1)
	if is_inside_tree():
		var vp: Viewport = get_viewport()
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = [0.75, 0.9, 1.0, 1.0][quality]
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]

## Visual time of day in seconds (0 = sunrise), or -1 to follow the simulation.
func set_time_override(sec: float) -> void:
	time_override = sec

## Interior view of a room (UI "interior <id>", V3 §8): select it (the roof opens) and frame
## it from a medium angle; the room stays open while selected.
func open_interior(id: int) -> void:
	if not sim.state["buildings"].has(id):
		return
	var b: Dictionary = sim.state["buildings"][id]
	select("building", id)
	var r = rig()
	if r != null:
		r.jump_to(to3(b["pos"]))
		r.target_distance = clampf(float(b["radius"]) * 2.8 + 8.0, 14.0, 45.0)
		r.pitch = deg_to_rad(58.0)
	if bmeta.has(id) and bmeta[id]["mode"] == "inst" and b["kind"] != "link":
		bmeta[id]["open"] = 1.0
		_apply_roof(b, bmeta[id])

## Camera shake and a short flash for big moments (optional hook).
func focus_event(kind: String, id: int = -1) -> void:
	match kind:
		"liftoff", "landing":
			_shake = 1.0
		"award", "goal":
			post.flash(0.12)
		"breach", "death":
			_shake = 0.5
	if not shake_enabled:
		_shake = 0.0
	var r = rig()
	if r != null and r.has_method("shake") and shake_enabled:
		r.shake(_shake)

# ---------------------------------------------------------------- measurement and the debug hook
func stats() -> Dictionary:
	var vp_rid: RID = get_viewport().get_viewport_rid() if is_inside_tree() else RID()
	if vp_rid.is_valid() and not _measuring:
		_measuring = true
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	return {
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"render_cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu(), 0.01) if vp_rid.is_valid() else 0.0,
		"render_gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid), 0.01) if vp_rid.is_valid() else 0.0,
		"fps": Engine.get_frames_per_second(),
		"view_ms": snappedf(_frame_ms, 0.01),
		"worst_ms": snappedf(_worst_ms, 0.1),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"instances": inst.count() if inst != null else 0,
		"batches": inst.draw_parts() if inst != null else 0,
		"structures": sim.state["buildings"].size(),
		"colonists": sim.state["agents"].size(),
		"quality": quality,
		"setup_ms": snappedf(_setup_ms, 0.1),
		"terrain": terrain.timings if terrain != null else {},
		"prof": _prof_snapshot(),
		"npc": npc.stats() if npc != null else {},
		"doors": doors.stats if doors != null else {},
		"airlock": airlock.stats if airlock != null else {},
		"boot": boot_info,
		"traffic": traffic.stats if traffic != null else {},
		"interior": interior.stats if interior != null else {},
		"hazards": hazards.stats if hazards != null else {},
		"lod": terrain.lod_counts if terrain != null else [],
	}

func _prof_snapshot() -> Dictionary:
	var out := {}
	for k in _prof_ms:
		out[k] = snappedf(float(_prof_ms[k]), 0.01)
	return out

func _publish_stats(delta: float) -> void:
	if _pending_load:
		var b64 = JavaScriptBridge.eval("window.__fhr_file || ''", true)
		if typeof(b64) == TYPE_STRING and String(b64) != "":
			_pending_load = false
			JavaScriptBridge.eval("window.__fhr_file='';", true)
			var main = get_parent()
			if main != null and main.has_method("_import_bytes"):
				main.call_deferred("_import_bytes", Marshalls.base64_to_raw(String(b64)))
	_worst_ms = maxf(_worst_ms * 0.995, delta * 1000.0)
	_fps_clock -= delta
	if _fps_clock > 0.0 or _js_obj == null:
		return
	_fps_clock = 0.5
	var s: Dictionary = stats()
	_js_obj.fps = s["fps"]
	_js_obj.view_ms = s["view_ms"]
	_js_obj.draw_calls = s["draw_calls"]
	_js_obj.primitives = s["primitives"]
	_js_obj.stats = JSON.stringify(s)

## window.__fhr: RENDER's own test hook (visual only, never touches the simulation).
##   time <sec|-1> · quality <0..3> · ghost <def> <size> <x> <y> <rot_deg> <valid 0|1> · ghost off
##   link <x0> <y0> <x1> <y1> <corridor|cable> <valid> · link off · storm <0..1|-1>
##   flight <0..1|-1> · intro · photo <on|off> · focus <x> <y> · select <building|agent> <id>
##   shake · stats
func _install_js() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.__fhr = window.__fhr || {fps:0, view_ms:0, draw_calls:0, primitives:0, stats:'{}', last:''};", true)
	_js_obj = JavaScriptBridge.get_interface("__fhr")
	_js_cb = JavaScriptBridge.create_callback(func(args: Array):
		var text: String = String(args[0]) if args.size() > 0 else ""
		_js_obj.last = debug_cmd(text))
	_js_obj.cmd = _js_cb

func debug_cmd(text: String) -> String:
	var w: PackedStringArray = text.strip_edges().split(" ", false)
	if w.is_empty():
		return "empty"
	match w[0]:
		"labels":
			set_labels_visible(w.size() > 1 and w[1] == "1")
		"deselect":
			select("", -1)
		"time":
			set_time_override(float(w[1]))
		"quality":
			set_quality(int(w[1]))
		"ghost":
			if w.size() < 7:
				clear_ghost()
			else:
				set_ghost(w[1], int(w[2]), Vector2(float(w[3]), float(w[4])), deg_to_rad(float(w[5])), w[6] == "1")
		"link":
			if w.size() < 7:
				set_link_preview(null, null)
			else:
				set_link_preview(Vector2(float(w[1]), float(w[2])), Vector2(float(w[3]), float(w[4])), w[5], w[6] == "1")
		"storm":
			_forced_storm = float(w[1])
		"flight":
			_forced_flight = float(w[1])
			ship.forced_flight = _forced_flight
		"intro":
			var r = rig()
			if r != null and r.has_method("play_intro"):
				if w.size() > 1 and w[1] == "off":
					r.skip_intro()
				else:
					r.play_intro()
		"photo":
			var r2 = rig()
			if r2 != null and r2.has_method("photo_orbit"):
				if w.size() > 1 and w[1] == "off":
					r2.stop_photo()
				else:
					r2.photo_orbit(_focus(), 70.0, 22.0, 0.05)
		"focus":
			var r3 = rig()
			if r3 != null:
				r3.jump_to(to3(Vector2(float(w[1]), float(w[2]))))
		"select":
			select(w[1], int(w[2]))
		"shake":
			focus_event("liftoff")
		"stats":
			return JSON.stringify(stats())
		"npc":
			# npc fixture | glb : the procedural test rig or the real GLBs (test only).
			npc_fixture = w.size() > 1 and w[1] == "fixture"
			npc.setup(self, npc_fixture)
			for id in ameta.keys():
				_drop_agent(id)
			return JSON.stringify(npc.stats())
		"use":
			# Test staging (view only): use <agent id> <kind> <building> <i> <pose> <act> | use clear
			#   | use fill <building>: every colonist inside that room takes a bed, seat, work or stand anchor.
			if w.size() > 1 and w[1] == "clear":
				npc.forced_use = {}
				return "ok"
			if w.size() > 2 and (w[1] == "nth" or w[1] == "clearone" or w[1] == "nthout"):
				# use nth <n> <kind> <b> <i> <pose> <act> | use clearone <n>: the n-th living colonist by id.
				var ids3: Array = []
				for aid3 in sim.state["agents"]:
					if sim.state["agents"][aid3]["state"] == "alive" and (w[1] != "nthout" or sim.state["agents"][aid3]["where"] == "out"):
						ids3.append(aid3)
				ids3.sort()
				var nn: int = int(w[2])
				if nn >= ids3.size():
					return "none"
				if w[1] == "clearone":
					npc.forced_use.erase(int(ids3[nn]))
					return "cleared %d" % int(ids3[nn])
				npc.forced_use[int(ids3[nn])] = {"kind": w[3], "b": int(w[4]), "i": int(w[5]), "pose": w[6], "act": w[7]}
				return "agent %d" % int(ids3[nn])
			if w.size() > 2 and w[1] == "fill":
				var bid: int = int(w[2])
				var kinds := [["bed", "lie", "sleep"], ["bed", "lie", "sleep"], ["seat", "sit", "eat"], ["seat", "sit", "relax"], ["work", "stand", "work"], ["stand", "stand", "talk"], ["bed", "lie", "sleep"], ["seat", "sit", "eat"]]
				var n := 0
				var used := {}
				var ids: Array = sim.state["agents"].keys()
				ids.sort()
				for aid in ids:
					var ag: Dictionary = sim.state["agents"][aid]
					if ag["state"] != "alive" or n >= kinds.size():
						continue
					var k: Array = kinds[n]
					var i: int = int(used.get(k[0], 0))
					used[k[0]] = i + 1
					npc.forced_use[int(aid)] = {"kind": k[0], "b": bid, "i": i, "pose": k[1], "act": k[2]}
					n += 1
				return "%d staged" % n
			if w.size() >= 7:
				npc.forced_use[int(w[1])] = {"kind": w[2], "b": int(w[3]), "i": int(w[4]), "pose": w[5], "act": w[6]}
				return "ok"
			return "use <agent> <kind> <b> <i> <pose> <act> | use fill <b> | use clear"
		"find":
			# find <def> [n]: id and position of the n-th structure of a type (tests and shots).
			# find <id>: id and position of that structure.
			if w[1].is_valid_int() and sim.state["buildings"].has(int(w[1])):
				var bq: Dictionary = sim.state["buildings"][int(w[1])]
				return "%d %.1f %.1f" % [int(w[1]), bq["pos"].x, bq["pos"].y]
			var n2: int = int(w[2]) if w.size() > 2 else 0
			var ids2: Array = sim.state["buildings"].keys()
			ids2.sort()
			for bid in ids2:
				var bb: Dictionary = sim.state["buildings"][bid]
				if bb["def"] == w[1]:
					if n2 > 0:
						n2 -= 1
						continue
					return "%d %.1f %.1f" % [bid, bb["pos"].x, bb["pos"].y]
			return "none"
		"defs":
			# defs: structure types in the colony with their count (tests and shots).
			var cnt := {}
			for bid in sim.state["buildings"]:
				var dn: String = sim.state["buildings"][bid]["def"]
				cnt[dn] = int(cnt.get(dn, 0)) + 1
			return str(cnt)
		"craters":
			# craters: sim craters with the distance to the nearest structure centre (tests).
			var o2: Array = []
			if hazards != null and hazards._hz != null:
				for c in hazards._hz.craters():
					var cp := Vector2(float(c["x"]), float(c["y"]))
					var best := 1e9
					for bid in sim.state["buildings"]:
						best = minf(best, cp.distance_to(sim.state["buildings"][bid]["pos"]))
					o2.append("%.0f,%.0f r%.1f near%.1f" % [cp.x, cp.y, float(c["r"]), best])
			return str(o2)
		"tallparts":
			# tallparts <room id>: drawn groups of the room and its doorway kits whose top is above
			# 1.45 m (the cutaway rule check, critic round 13).
			var rid0: int = int(w[1])
			var hs: Array = []
			if bmeta.has(rid0):
				hs.append(["room", int(bmeta[rid0]["h"])])
			for dd in doors.doors:
				if int(dd["room"]) == rid0:
					hs.append(["door", int(dd["h"])])
			var out0: Array = []
			for e in hs:
				if not inst.handles.has(e[1]):
					continue
				var he: Dictionary = inst.handles[e[1]]
				var bt: Dictionary = inst.batches[he["key"]]
				var sc: float = float(he.get("scale", 1.0))
				for pp in bt["parts"]:
					var part: Dictionary = pp["part"]
					if bool(part.get("shadow_only", false)) or (he["hidden"] as Dictionary).has(part["group"]):
						continue
					var ab0: AABB = (part["xf"] as Transform3D) * (part["mesh"] as Mesh).get_aabb()
					if ab0.end.y * sc > 1.45:
						out0.append("%s %s %.2f" % [e[0], part["group"], ab0.end.y * sc])
			return "open %.2f | %s" % [float(bmeta[rid0]["open"]) if bmeta.has(rid0) else -1.0, ", ".join(out0)]
		"visitors":
			# visitors: id vkind x z of every visitor body (tests and shots).
			var vl: Array = []
			for vid in npc.agents:
				var va: Dictionary = sim.state["agents"].get(vid, {})
				if String(va.get("kind", "")) == "visitor":
					var vp: Vector3 = npc._dp(npc.agents[vid])
					vl.append("%d %s %.1f %.1f" % [int(vid), String(va.get("vkind", "")), vp.x, vp.z])
			return ";".join(vl)
		"ships":
			# ships: the view state of visiting ships (height, legs, ramp, doors, floods).
			return str(traffic.info())
		"airlock":
			# airlock <id>: the view state of an airlock's cycle (doors, pressure, phase).
			return str(airlock.info(int(w[1])))
		"doors":
			# doors <room id> 1|0: hold that room's doors open (tests and shots; view only).
			if w.size() > 2 and w[2] == "red":
				doors.force_red[int(w[1])] = true
			elif w.size() > 2 and w[2] == "1":
				doors.force_open[int(w[1])] = true
			else:
				doors.force_open.erase(int(w[1]))
			var dl: Array = []
			for d in doors.doors:
				if int(d["room"]) == int(w[1]) or int(d["link"]) == int(w[1]):
					dl.append("r%d l%d o%.2f" % [int(d["room"]), int(d["link"]), float(d["open"])])
			return str(dl) + " rebuilds " + str(doors.stats.get("rebuilds", 0)) + " flips " + str(_mode_flips)
		"hzdebug":
			return JSON.stringify(hazards._cached_events.map(func(e): return {"id": e["id"], "kind": e["kind"], "phase": e["phase"], "eta": e["eta_s"]}))
		"drawlist":
			# Measurement: estimated draw calls by owner (visible surfaces; x2 for shadow casters).
			var acc := {}
			var stack: Array = [self]
			while not stack.is_empty():
				var nd: Node = stack.pop_back()
				for ch in nd.get_children():
					stack.append(ch)
				if not (nd is GeometryInstance3D) or not (nd as Node3D).is_visible_in_tree():
					continue
				var mesh: Mesh = null
				if nd is MeshInstance3D:
					mesh = (nd as MeshInstance3D).mesh
				elif nd is MultiMeshInstance3D and (nd as MultiMeshInstance3D).multimesh != null:
					var mmx: MultiMesh = (nd as MultiMeshInstance3D).multimesh
					if mmx.instance_count == 0 or mmx.visible_instance_count == 0:
						continue
					mesh = mmx.mesh
				if mesh == null:
					continue
				var gi: GeometryInstance3D = nd
				var sc: int = mesh.get_surface_count()
				var d: int = (0 if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY else sc) + (sc if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0)
				var key: String = String(nd.name).get_slice("_", 0) if nd.get_parent() == inst else String(nd.get_parent().name)
				if nd.get_parent() == inst:
					var nm: String = String(nd.name)
					key = "inst:" + (nm.substr(nm.rfind("_") + 1) if not nm.ends_with("_shadow") else "shadowproxy")
				if w.size() > 1 and key == w[1]:
					key = "%s/%s" % [key, nd.name]
				acc[key] = int(acc.get(key, 0)) + d
			var arr: Array = []
			for k in acc:
				arr.append([acc[k], k])
			arr.sort_custom(func(x, y): return x[0] > y[0])
			var total := 0
			for e in arr:
				total += int(e[0])
			if w.size() > 1:
				arr = arr.filter(func(e): return String(e[1]).begins_with(w[1] + "/"))
				for e in arr:
					e[1] = String(e[1]).substr(w[1].length() + 1)
			return "total %d | %s" % [total, str(arr.slice(0, 80))]
		"probe_mesh":
			# Measurement only: can this platform read mesh data back? (V3 walls, astronauts)
			var ps = load("res://assets/models/%s.glb" % (w[1] if w.size() > 1 else "habitat_m"))
			if ps == null:
				return "no model"
			var root: Node = (ps as PackedScene).instantiate()
			var out2 := []
			for mi in Models.meshes(root):
				var m3: MeshInstance3D = mi
				if m3.mesh == null or out2.size() > 3:
					continue
				var arr: Array = m3.mesh.surface_get_arrays(0)
				var sd: Dictionary = RenderingServer.mesh_get_surface(m3.mesh.get_rid(), 0)
				out2.append("%s: arrays %d verts, faces %d, rs vertex_data %d bytes, format %d, compressed %s" % [m3.name, (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if arr.size() > 0 and arr[0] != null else -1,
					m3.mesh.get_faces().size(), (sd.get("vertex_data", PackedByteArray()) as PackedByteArray).size(), int(sd.get("format", 0)), str((int(sd.get("format", 0)) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0)])
			var st2 := SurfaceTool.new()
			st2.begin(Mesh.PRIMITIVE_TRIANGLES)
			for q in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]:
				st2.add_vertex(q)
			var am: ArrayMesh = st2.commit()
			out2.append("surfacetool mesh: %d verts back" % (am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			root.free()
			return " | ".join(out2)
		"bigmap":
			# Test aid until SIM stores map_size (V3 1): a new game on a bigger map.
			var main = get_parent()
			var sz: int = int(w[1]) if w.size() > 1 else 810
			for sc in sim.content["scenarios"]:
				sim.content["scenarios"][sc]["map_size"] = sz
			sim.new_game(int(sim.state.get("seed", 1001)))
			if main != null and main.has_method("_after_world_change"):
				main._after_world_change()
			return "map %d" % int(sim.world.size)
		"agent":
			# Follow the n-th living colonist (outside first if w[2] == "out").
			var want_out: bool = w.size() > 2 and (w[2] == "out" or w[2] == "carrier")
			var want_cargo: bool = w.size() > 2 and w[2] == "carrier"
			var n: int = int(w[1])
			for aid in sim.state["agents"]:
				var a: Dictionary = sim.state["agents"][aid]
				if a["state"] != "alive" or (want_out and a["where"] != "out"):
					continue
				if want_cargo and (int(a.get("inv", -1)) == -1 or (sim.inv.get_inv(a["inv"]).get("items", {}) as Dictionary).is_empty()):
					continue
				# agent <n> corridor | fast: in a corridor, or moving at run pace (body speed).
				if w.size() > 2 and w[2] == "corridor":
					var cb: int = int(a.get("bld", -1))
					if a["where"] != "in" or not sim.state["buildings"].has(cb) or sim.state["buildings"][cb]["kind"] != "link":
						continue
				if w.size() > 2 and w[2] == "fastout" and a["where"] != "out":
					continue
				if w.size() > 3 and w[3] == "corr":
					var cb2: int = int(a.get("bld", -1))
					if not sim.state["buildings"].has(cb2) or sim.state["buildings"][cb2]["kind"] != "link":
						continue
				if w.size() > 2 and (w[2] == "fast" or w[2] == "fastout"):
					var br = npc.agents.get(aid) if npc != null else null
					if br == null or float(br["speed"]) < 2.8 or int(br["crate"]) != -1:
						continue
				if n > 0:
					n -= 1
					continue
				var r5 = rig()
				if r5 != null and (ameta.has(aid) or (npc != null and npc.agents.has(aid))):
					var captured: int = aid
					r5.follow_fn = func(): return agent_world_pos(captured)
					var jp = agent_world_pos(captured)
					if jp != null:
						r5.jump_to(jp)
				return "%s %s %s id%d" % [a["name"], a["role"], a["where"], int(aid)]
			return "none"
		"npcpose":
			# npcpose <agent id>: the body record (tests).
			if npc == null or not npc.agents.has(int(w[1])):
				return "none"
			var nr: Dictionary = npc.agents[int(w[1])]
			var rp: Vector3 = nr["pos"]
			var rr: int = npc._room_at(Vector2(rp.x, rp.z))
			if w.size() > 2 and w[2] == "room":
				if rr < 0:
					return "no room"
				var rm2 = bmeta.get(rr)
				return "room %d %s aisles %d slots %d" % [rr, sim.state["buildings"][rr]["def"], npc._aisles_of(rm2).size() if rm2 != null else -1, npc._slots_of(rm2).size() if rm2 != null else -1]
			return "var=%s mode=%s speed=%.2f pos=%s off=%s pose=%s gr=%.3f" % [nr["var"], nr["mode"], float(nr["speed"]), str(nr["pos"]), str(nr.get("off", Vector3.ZERO)), str(nr["sm"].pose()), npc.game_rate]
		"npccpu":
			npc.force_cpu = w.size() > 1 and w[1] == "1"
			return "ok"
		"runto":
			# runto <agent id> <x> <y> <m/s> | runto clear: test staging, the body goes straight there.
			if w[1] == "clear":
				npc.forced_goto = {}
			else:
				npc.forced_goto[int(w[1])] = [Vector2(float(w[2]), float(w[3])), float(w[4]) if w.size() > 4 else 3.4]
			return "ok"
		"breachdoor":
			# breachdoor: "x z yaw" of a doorway whose room or corridor is breached (red state shots).
			for d in doors.doors:
				var bl: Dictionary = sim.state["buildings"]
				if bool(bl.get(int(d["room"]), {}).get("breach", false)) or bool(bl.get(int(d["link"]), {}).get("breach", false)):
					return "%.2f %.2f %d %d" % [(d["pos"] as Vector3).x, (d["pos"] as Vector3).z, int(d["room"]), int(d["link"])]
			return "none"
		"doorpos":
			# doorpos <room id>: world x z of each doorway of that room and its open value (tests).
			var dp: Array = []
			for d in doors.doors:
				if int(d["room"]) == int(w[1]):
					dp.append("%.2f %.2f %.2f" % [(d["pos"] as Vector3).x, (d["pos"] as Vector3).z, float(d["open"])])
			return ",".join(dp)
		"cutaway":
			# cutaway 0|1: 0 keeps every roof on at close zoom (roof-on shots); 1 is normal.
			_no_cutaway = w.size() > 1 and w[1] == "0"
			return "ok"
		"ilights":
			interior.lights_off = w.size() > 1 and w[1] == "0"
			return "ok"
		"npcput":
			# npcput <agent id> <x> <z>: test staging, puts the drawn body there (it then walks).
			if npc == null or not npc.agents.has(int(w[1])):
				return "none"
			var pr: Dictionary = npc.agents[int(w[1])]
			var pp := Vector2(float(w[2]), float(w[3]))
			var prr: int = npc._room_at(pp)
			pr["pos"] = Vector3(pp.x, npc._floor_y(sim.state["buildings"][prr]) if prr >= 0 else h(pp.x, pp.y), pp.y)
			pr["mode"] = "follow"
			pr["path"] = []
			pr["route"] = []
			pr.erase("route_to")
			return "ok"
		"hazeprio":
			hazards.haze_prio = int(w[1])
			return "ok"
		"hznodes":
			var hl: Array = []
			for ch in hazards.get_children():
				if ch is MeshInstance3D:
					var mm0 = (ch as MeshInstance3D).material_override
					hl.append("%s vis%s pos%s sc%s prio%s glow%s" % [ch.name, str((ch as Node3D).is_visible_in_tree()), str((ch as Node3D).global_position.snappedf(0.1)), str((ch as Node3D).scale.snappedf(0.1)), str(mm0.render_priority if mm0 != null else -999), str(mm0.get_shader_parameter("glow") if mm0 is ShaderMaterial else "")])
			return str(hl)
		"testring":
			# testring x z mode [prio]: a decal ring for render tests.
			var tr := decal_ring(6.0, 0.0 if int(w[3]) != 0 else 0.8, 96, Color(1.0, 0.3, 0.22, 0.95), int(w[3]))
			if not (w.size() > 6 and w[6] == "nodup"):
				tr.material_override = (tr.material_override as ShaderMaterial).duplicate()
			if w.size() > 4 and not (w.size() > 6 and w[6] == "nodup"):
				(tr.material_override as ShaderMaterial).render_priority = int(w[4])
			if w.size() > 5 and not (w.size() > 6 and w[6] == "nodup"):
				(tr.material_override as ShaderMaterial).set_shader_parameter("glow", float(w[5]))
			var hm0 = (tr.material_override as ShaderMaterial).get_shader_parameter("heightmap")
			tr.set_meta("dbg", "hm %s hn %s hs %s" % [str(hm0), str((tr.material_override as ShaderMaterial).get_shader_parameter("hn")), str((tr.material_override as ShaderMaterial).get_shader_parameter("hstep"))])
			tr.position = Vector3(float(w[1]), 0, float(w[2]))
			add_child(tr)
			return tr.get_meta("dbg")
		"decalinfo":
			var dl2: Array = []
			for ch in get_children():
				if ch is MeshInstance3D and (ch as MeshInstance3D).material_override is ShaderMaterial and ((ch as MeshInstance3D).material_override as ShaderMaterial).shader == DECAL_SHADER:
					var mi5: MeshInstance3D = ch
					dl2.append("%s vis%s gp%s sc%s aabb%s prio%d col%s icol%s layers%d" % [mi5.name, str(mi5.is_visible_in_tree()), str(mi5.global_position.snappedf(0.1)), str(mi5.scale.snappedf(0.1)), str(mi5.get_aabb()), mi5.material_override.render_priority, str(mi5.material_override.get_shader_parameter("color")), str(mi5.get_instance_shader_parameter("icolor")), mi5.layers])
			return str(dl2)
		"stalls":
			# stalls [reset]: frames over 50 ms and view frames over 25 ms with their sections.
			if w.size() > 1 and w[1] == "reset":
				stalls = []
				stall_count = {"view_over_25": 0, "frame_over_50": 0, "frames": 0, "max_frame_ms": 0.0, "max_view_ms": 0.0}
				return "ok"
			return JSON.stringify({"count": stall_count, "log": stalls})
		"decalcheck":
			# decalcheck: for every doorway, the visible Decal_<seg> segments that meet the opening
			# plus 0.4 m on each side (ART-HAB D2 acceptance: must be 0). Per room type.
			var seg: float = TAU / float(Models.WALL_SEGMENTS)
			var bad := {}
			var checked := {}
			for d in doors.doors:
				var rid: int = int(d["room"])
				if not bmeta.has(rid):
					continue
				var room: Dictionary = sim.state["buildings"][rid]
				var meta2: Dictionary = bmeta[rid]
				var s2: float = float(meta2["tpl"].get("scale", 1.0))
				var rw: float = maxf(1.5, float(room["radius"]) - 0.32 * s2)
				var l3: Vector3 = (meta2["xf"] as Transform3D).affine_inverse() * (d["pos"] as Vector3)
				var beta: float = atan2(-l3.z, l3.x)
				var ph: float = asin(minf(0.99, (0.75 + 0.40) / rw))
				var mask: int = int(doors.masks.get(rid, 0))
				var tk: String = "%s_%d" % [room["def"], int(room.get("size", 1))]
				checked[tk] = int(checked.get(tk, 0)) + 1
				for p in meta2["tpl"]["parts"]:
					if not String(p["group"]).begins_with("Decal"):
						continue
					for sk in (p.get("seg_pos", {}) as Dictionary):
						if mask & (1 << int(sk)):
							continue
						var a0: float = float(sk) * seg
						var a1: float = a0 + seg
						var lo: float = beta - ph
						var hi: float = beta + ph
						for sh in [-TAU, 0.0, TAU]:
							if a1 > lo + sh and a0 < hi + sh:
								bad[tk] = int(bad.get(tk, 0)) + 1
			return JSON.stringify({"doorways_checked": checked, "decal_segments_in_openings": bad})
		"followid":
			# followid <agent id>: the camera follows that body (tests and shots).
			var r6 = rig()
			var fa: int = int(w[1])
			if r6 != null:
				r6.follow_fn = func(): return agent_world_pos(fa)
				var jp2 = agent_world_pos(fa)
				if jp2 != null:
					r6.jump_to(jp2)
			return "ok"
		"timescale":
			# timescale <x>: Engine.time_scale (frame strips: 0.1 = 10x slower, game and view).
			Engine.time_scale = clampf(float(w[1]), 0.01, 4.0)
			return "ok"
		"vtime":
			# vtime: view time in game seconds, and the followed body speed (frame strips).
			var rv = rig()
			var fo: String = ""
			if rv != null:
				fo = " focus %s follow %s" % [str(rv.focus.snappedf(0.1)), str(rv.follow_fn.is_valid())]
				if rv.follow_fn.is_valid():
					fo += " body %s" % str(rv.follow_fn.call())
			return "%.4f sim %.4f gr %.3f%s" % [_time, sim.seconds(), game_rate, fo]
		"findstate":
			# Focus the camera on the first structure in a state (blueprint, building, ...).
			for id in sim.state["buildings"]:
				var b: Dictionary = sim.state["buildings"][id]
				if String(b["state"]) == w[1] and b["kind"] != "link":
					var r4 = rig()
					if r4 != null:
						r4.jump_to(to3(b["pos"]))
					return "%s %d mode=%s" % [b["def"], id, bmeta[id]["mode"] if bmeta.has(id) else "-"]
			return "none"
		"shipinfo":
			# shipinfo: per ship group, its meshes as surfaces:cast_shadow (tests).
			if ship == null or ship.body == null:
				return "no ship"
			if w.size() > 1:
				# shipinfo orig|proxy|none: which meshes cast the ship shadow (A/B test).
				for g in ship.body.get_children():
					for mi in g.get_children():
						if mi is MeshInstance3D:
							var gi3: MeshInstance3D = mi
							var is_px: bool = gi3.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY or gi3.has_meta("px")
							if is_px:
								gi3.set_meta("px", true)
								gi3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if w[1] == "proxy" else (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if w[1] == "show" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
								gi3.visible = w[1] == "proxy" or w[1] == "show"
								if w[1] == "proxy" and w.size() > 2:
									var pmx := StandardMaterial3D.new()
									pmx.cull_mode = BaseMaterial3D.CULL_DISABLED if w[2] == "two" else BaseMaterial3D.CULL_FRONT
									gi3.material_override = pmx
							else:
								gi3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if w[1] == "orig" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
								gi3.visible = w[1] != "show"
			var so := ""
			var hull_g = ship.body.get_node_or_null("Hull")
			if hull_g != null:
				for mi in hull_g.get_children():
					var mh: Mesh = (mi as MeshInstance3D).mesh
					for si in mh.get_surface_count():
						var smm: Material = mh.surface_get_material(si)
						var cls: String = smm.get_class() if smm != null else "null"
						var cull := -1
						if smm is BaseMaterial3D:
							cull = (smm as BaseMaterial3D).cull_mode
						var srcm = smm.get_meta("src") if smm != null and smm.has_meta("src") else null
						so += "[%s %s cull%d src=%s n=%d] " % [smm.resource_name if smm != null else "", cls, cull, str(srcm.get_class() if srcm != null else ""), mh.surface_get_array_len(si)]
				so += " || "
			for g in ship.body.get_children():
				so += "%s(%s):" % [g.name, str((g as Node3D).is_visible_in_tree())]
				for mi in g.get_children():
					if mi is MeshInstance3D:
						var mm3: Mesh = (mi as MeshInstance3D).mesh
						var vc := 0
						var tr := ""
						for si in mm3.get_surface_count():
							vc += mm3.surface_get_array_len(si)
							var sm: Material = mm3.surface_get_material(si)
							var sm_src = sm.get_meta("src") if sm != null and sm.has_meta("src") else sm
							if sm_src is BaseMaterial3D and (sm_src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
								tr += "T"
						so += "%d/%d/v%d%s/%s/%s," % [mm3.get_surface_count(), (mi as MeshInstance3D).cast_shadow, vc, tr, str(mm3.get_aabb().size.snappedf(0.01)), str(mm3.surface_get_format(0) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES != 0)]
				so += " "
			return so
		"nodeinfo":
			var nid: int = int(w[1])
			if not bmeta.has(nid) or bmeta[nid]["node"] == null:
				return "no node"
			var nd: Node3D = bmeta[nid]["node"]
			var ms2: Array = Models.meshes(nd)
			var out := "mode=%s vis=%s pos=%s meshes=%d" % [bmeta[nid]["mode"], str(nd.is_visible_in_tree()), str(nd.global_position), ms2.size()]
			if ms2.size() > 0:
				var m0: MeshInstance3D = ms2[0]
				out += " surf=%d ov0=%s by=%s hy=%s aabb=%s" % [m0.mesh.get_surface_count(), str(m0.get_surface_override_material(0)), str(m0.get_instance_shader_parameter("build_y")), str(m0.get_instance_shader_parameter("holo_min_y")), str(m0.get_aabb())]
			if w.size() > 2 and w[2] == "plain":
				for mi in ms2:
					(mi as MeshInstance3D).material_override = holo_material(Color(0.35, 0.82, 1.0), 1.25)
			if w.size() > 2 and w[2] == "solid":
				var cm := ShaderMaterial.new()
				cm.shader = CONSTRUCT_SHADER
				cm.set_shader_parameter("albedo", Color(0.9, 0.2, 0.2))
				for mi in ms2:
					(mi as MeshInstance3D).material_override = cm
				_debug_node = nid
			if w.size() > 2 and w[2] == "surf":
				for mi in ms2:
					var m3: MeshInstance3D = mi
					for si in m3.mesh.get_surface_count():
						m3.set_surface_override_material(si, holo_material(Color(1.0, 0.2, 1.0), 1.25))
			return out
		"ghostinfo":
			var gn: Node3D = ghost.node
			if gn == null:
				return "no ghost node"
			var ms: Array = Models.meshes(gn)
			var vis := 0
			for mi in ms:
				if (mi as MeshInstance3D).is_visible_in_tree():
					vis += 1
			return "key=%s visible=%s pos=%s meshes=%d visible_meshes=%d mat=%s" % [ghost.node_key, str(gn.visible), str(gn.global_position), ms.size(), vis, str((ms[0] as MeshInstance3D).material_override) if ms.size() > 0 else "-"]
		"toggle":
			# Measurement only: switch one render feature off or on.
			var on: bool = w.size() > 2 and w[2] == "1"
			match w[1]:
				"shadows": sky.key.shadow_enabled = on
				"post": post.visible = on
				"glow": sky.env.glow_enabled = on
				"fog": sky.env.fog_enabled = on
				"particles": fx.visible = on
				"terrain": terrain.mesh_inst.visible = on
				"pebbles":
					for p in terrain._pebbles:
						(p["mmi"] as MultiMeshInstance3D).visible = on
				"instances": inst.visible = on
				"icons": icons.visible = on
				"msaa": get_viewport().msaa_3d = Viewport.MSAA_2X if on else Viewport.MSAA_DISABLED
				"ui":
					for c in get_tree().root.get_children():
						for cc in c.get_children():
							if cc is CanvasLayer and cc != post:
								(cc as CanvasLayer).visible = on
								cc.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
				"sky": sky.env.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR
				"view": _frozen = not on
		"loadurl":
			# Test data only: fetch a save file next to the page and hand it to main.
			if OS.has_feature("web") and w.size() > 1:
				JavaScriptBridge.eval("window.__fhr_file='';fetch('%s').then(r=>r.arrayBuffer()).then(b=>{const u=new Uint8Array(b);let s='';for(let i=0;i<u.length;i++)s+=String.fromCharCode(u[i]);window.__fhr_file=btoa(s);});" % w[1], true)
				_pending_load = true
		_:
			return "unknown command"
	return "ok"

## World sound (V3_1 §2.2): UI plays it with distance fall-off from the camera focus.
## Returns UI's handle (for world_stop / world_move), or -1.
func world_sound(name: String, pos: Vector3) -> int:
	var au = _audio()
	if au != null and (au as Object).has_method("world"):
		var r = au.world(name, pos)
		return int(r) if r != null else -1
	return -1

func world_stop(handle: int) -> void:
	var au = _audio()
	if handle >= 0 and au != null and (au as Object).has_method("world_stop"):
		au.world_stop(handle)

func world_move(handle: int, pos: Vector3) -> void:
	var au = _audio()
	if handle >= 0 and au != null and (au as Object).has_method("world_move"):
		au.world_move(handle, pos)

func _audio():
	var m = get_parent()
	while m != null and not (m.get("audio") != null):
		m = m.get_parent()
	return m.get("audio") if m != null else null
