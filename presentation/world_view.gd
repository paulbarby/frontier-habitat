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
	var img := Image.create(w.hn, w.hn, false, Image.FORMAT_RF)
	for j in w.hn:
		for i in w.hn:
			img.set_pixel(i, j, Color(w.heights[j * w.hn + i], 0, 0))
	img.convert(Image.FORMAT_RH)
	heightmap = ImageTexture.create_from_image(img)

## Ore deposits: a dashed amber ring on the ground; the word only close up.
func _build_deposit_labels() -> void:
	for d in sim.state["deposits"]:
		var ring: MeshInstance3D = decal_ring(float(d["r"]) + 1.2, 0.96, 96, Color(1.0, 0.7, 0.35, 0.55), 1, 40.0, 0.0)
		ring.position = Vector3(float(d["x"]), 0, float(d["y"]))
		ring.name = "DepositRing"
		add_child(ring)
		_dep_rings.append(ring)
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
	var cam: Camera3D = get_viewport().get_camera_3d()
	var focus: Vector3 = _focus()
	_focus_now = focus
	_frame += 1
	# Time of day (visual) and weather.
	var day_len: float = float(sim.bal["day_length"])
	var daylight: float = float(sim.planet["daylight_seconds"])
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
	terrain.update_paths(sim_dt)
	tp = _prof("paths", tp)
	_sync_buildings(delta)
	tp = _prof("buildings", tp)
	_sync_agents(delta)
	tp = _prof("agents", tp)
	_sync_piles()
	ship.sync(delta, sim_dt)
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
	_frame_ms = lerpf(_frame_ms, (Time.get_ticks_usec() - t_frame) / 1000.0, 0.05)
	_publish_stats(delta)

## World labels and badges on or off (the title screen turns them off). Photo orbit and a
## time override also hide the words.
func set_labels_visible(on: bool) -> void:
	labels_visible = on

func _photo_mode() -> bool:
	var r = rig()
	return r != null and bool(r.get("_photo"))

## Running average of each part of sync() in milliseconds (stats()["prof"]).
var _prof_ms := {}
func _prof(name: String, t0: int) -> int:
	var t1: int = Time.get_ticks_usec()
	_prof_ms[name] = lerpf(float(_prof_ms.get(name, 0.0)), (t1 - t0) / 1000.0, 0.05)
	return t1

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
	return Models.building(b["def"], size, float(b["radius"]), float(def.get("radius", b["radius"])), b["kind"], def.get("category", "logistics"))

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
		elif bmeta[id]["mode"] != mode:
			_drop_building(id)
			_make_building(b, mode)
			changed = true
		# Slow work (level parts, crops, smoke) runs for each structure every 6th frame.
		_update_building(b, delta, (int(id) + _frame) % 6 == 0)
	var sig := "%d:%d" % [blds.size(), int(sim.state["rev"].get("walk", 0))]
	if changed or sig != _rev_sig:
		_rev_sig = sig
		terrain.update_contact(blds)
		terrain.hide_pebbles_under(blds)

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
	if not bool(meta["glass_roof"]):
		inst.set_hidden(hnd, "Interior", o <= 0.0)

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
			var near: bool = camera_distance < 44.0 and (meta["xf"] as Transform3D).origin.distance_to(_focus_now) < camera_distance * 1.1 + 8.0
			var want: float = 1.0 if (near or (selected_kind == "building" and selected_id == id)) else 0.0
			var o: float = float(meta["open"])
			if o != want:
				meta["open"] = move_toward(o, want, delta * 3.5)
				_apply_roof(b, meta)
		# Rotor spins with the real wind.
		if (meta["tpl"]["groups"] as Dictionary).has("Rotor"):
			var w: float = float(sim.state["env"].get("wind", 3.0))
			meta["rotor"] = fmod(float(meta["rotor"]) + delta * (0.3 + w * 0.55) * (1.0 if b["state"] == "active" else 0.0), TAU)
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
	"suit_range": 7, "off": 8, "building": 9, "unreachable": 7, "no_reservoir": 1, "demolish": 11, "alert": 10}
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
	return {}

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
		list.append({"pos": pos, "icon": ICON.get(code, 10), "color": ICON_COLOR.get(code, Color("ffb547")), "progress": float(st.get("progress", 0.0)), "pulse": 1.0 if urgent else 0.0})
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
			lab.modulate = (ICON_COLOR.get(code, Color("ffb547")) as Color).lerp(Color.WHITE, 0.45)
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

func agent_world_pos(id: int):
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
		if bool(iv.get("pod", false)):
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
		var g: String = p["group"]
		if g in ["Interior", "Lights", "Rotor", "Scaffold", "EngineGlow", "Plasma"] or (open and (g == "Roof" or (g.length() == 2 and g[0] == "L" and b["kind"] == "room"))):
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
	overlays.set_mode(name if name != "walk" else "")

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

## Camera shake and a short flash for big moments (optional hook).
func focus_event(kind: String, id: int = -1) -> void:
	match kind:
		"liftoff", "landing":
			_shake = 1.0
		"award", "goal":
			post.flash(0.12)
		"breach", "death":
			_shake = 0.5
	var r = rig()
	if r != null and r.has_method("shake"):
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
		"agent":
			# Follow the n-th living colonist (outside first if w[2] == "out").
			var want_out: bool = w.size() > 2 and w[2] == "out"
			var n: int = int(w[1])
			for aid in sim.state["agents"]:
				var a: Dictionary = sim.state["agents"][aid]
				if a["state"] != "alive" or (want_out and a["where"] != "out"):
					continue
				if n > 0:
					n -= 1
					continue
				var r5 = rig()
				if r5 != null and ameta.has(aid):
					var captured: int = aid
					r5.follow_fn = func(): return agent_world_pos(captured)
				return "%s %s %s" % [a["name"], a["role"], a["where"]]
			return "none"
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
