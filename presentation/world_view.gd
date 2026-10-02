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
const TerrainV4 = preload("res://presentation/terrain_v4.gd")
const Vehicles = preload("res://presentation/fx_vehicles.gd")
const Reactor = preload("res://presentation/fx_reactor.gd")
const Explore = preload("res://presentation/fx_explore.gd")
const Bubbles = preload("res://presentation/fx_bubbles.gd")
const Photo = preload("res://presentation/fx_photo.gd")
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
const NO_CUTAWAY := ["rover_depot", "fission_reactor", "crystal_refinery", "chemical_plant", "launch_pad", "outpost_core", "crevice_bridge"]
const MODEL_RADIUS := {"airlock": {1: 5.1, 2: 6.0}, "junction": {-1: 3.75}}
const ROOM_MODEL_SCALE := 1.0
## Is the model file of def/size the 1.5x build (its wall ring well beyond the content radius)?
var _big_cache := {}
func _model_is_big(def_id: String, size: int) -> bool:
	var k := "%s/%d" % [def_id, size]
	if _big_cache.has(k):
		return _big_cache[k]
	var res: Dictionary = Models.resolve(def_id, size)
	var big := false
	if String(res["path"]) != "":
		var tpl: Dictionary = Models._template_from_file(res["path"])
		var wr := 0.0
		for p in tpl["parts"]:
			wr = maxf(wr, float(p.get("wall_r", 0.0)))
		var d: Dictionary = sim.bdef(def_id)
		var cr: float = float(d.get("radius", 3.0))
		if size >= 0 and d.has("sizes") and (d["sizes"] as Dictionary).has("radius"):
			cr = float(d["sizes"]["radius"][clampi(size, 0, 3)])
		big = wr > cr * 1.15
	_big_cache[k] = big
	return big   # content radii are the model radii again (SIM 2026-09-27 14:16: 1.5 x in buildings.json)
var vehicles                # fx_vehicles (V4 §8)
var reactor                 # fx_reactor (V4 §4.2 disaster effects)
var explore                 # fx_explore (V4 §5: POIs, satellites, launches)
var _rx_h := -1
var demo_rate := 0.0         # view-side demos (vdemo) run at this rate while the game is paused
var v4 = null                # terrain_v4 (V4 pilot: placeholder planet + horizon map)
var _stage: Array = []       # staged base in a crater (evidence only, view-side)
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
var _cont_prev := -1.0     # main.gd's continuous game clock on the last frame (see sync)
var tick_age := 0.0        # game seconds since the last sim tick (main.gd's accumulator; 0 when unknown)
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
	_setup_v4()
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
	vehicles = Vehicles.new()
	vehicles.name = "Vehicles"
	add_child(vehicles)
	vehicles.setup(self)
	reactor = Reactor.new()
	reactor.name = "Reactor"
	add_child(reactor)
	reactor.setup(self)
	explore = Explore.new()
	explore.name = "Explore"
	add_child(explore)
	explore.setup(self)
	bubbles = Bubbles.new()
	bubbles.name = "Bubbles"
	add_child(bubbles)
	bubbles.setup(self)
	photos = Photo.new()
	photos.name = "Photos"
	add_child(photos)
	photos.setup(self)
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

# ---------------------------------------------------------------- V5 §8 super dome (RENDER draws)
## ART-B's dome (models.gd dome_template): one template, one group per node. Each frame: the build
## stage (which groups exist yet), the floor cutaway (floors above the viewed floor, the roof and the
## dome hidden), the lift cabs and the crane jib, and the glass uniforms (night, sun).
## Stages: 0 foundation, 1..5 level_n, 6 dome_frame, 7 dome_glass, 8 fit-out (venues one by one), 9 done.
## SIM gives no stage yet: from b.build_stage when present, else from the build progress.
var dome_view_floor := {}     # building id -> floor 1..5 the player views (UI floor selector); absent = top
const LIFT_STOPS := [0.0, 5.0, 9.2, 13.4, 17.6, 21.8]

func set_view_floor(bid: int, k: int) -> void:
	if k <= 0:
		dome_view_floor.erase(bid)
	else:
		dome_view_floor[bid] = k

func _dome_stage(b: Dictionary) -> float:
	if b.has("build_stage"):
		return float(b["build_stage"])
	if String(b["state"]) == "building":
		var p: float = clampf(float(b.get("progress", 0.0)) / maxf(1.0, float(b.get("work_total", 1.0))), 0.0, 0.999)
		return p * 9.0
	return 9.0

static func _dome_floor_of(g: String) -> int:
	if g.begins_with("D_Floor_") and g.length() > 8 and g[8].is_valid_int():
		return int(g[8])
	return 0

## Is group g built at stage s (float: 8.x = fit-out x done)?
static func _dome_built(g: String, s: float, rank: float) -> bool:
	var st: int = int(floor(s))
	if g == "D_Foundation":
		return true
	if g == "D_Site" or g.begins_with("D_Crane"):
		return st < 6
	if g.begins_with("D_Scaffold_"):
		return st == int(g.substr(11, 1))
	if g in ["D_Gates", "D_Lifts"] or g.begins_with("D_Lift_"):
		return st >= 1
	var fl: int = _dome_floor_of(g)
	if fl > 0:
		if g == "D_Floor_%d" % fl or g.begins_with("D_Floor_%d__Struct" % fl):
			return st >= fl
		return s >= 8.0 + rank
	if g.begins_with("D_Floor_Roof"):
		return st >= 5 if g.contains("Struct") else s >= 8.0 + rank
	if g == "D_Dome" or g.begins_with("D_Dome__Dome_Frame"):
		return st >= 6
	if g.begins_with("D_Dome"):
		return st >= 7
	return s >= 8.0 + rank

func _dome_update(b: Dictionary, meta: Dictionary, delta: float) -> void:
	var hnd: int = meta["h"]
	var tpl: Dictionary = meta["tpl"]
	var s: float = _dome_stage(b)
	# Finished (or back under construction): the other template.
	if (s >= 9.0) != String(tpl.get("key", "")).ends_with(":merged"):
		_drop_building(int(b["id"]))
		return
	# The floor the player views: the followed person's floor inside this dome, else the selector,
	# else the top floor when the camera is close (roof and dome off), else no cut.
	var k := 0
	# (2026-10-01: no floor cut for the followed person any more: roofs and upper floors stay on in the
	# over-the-shoulder view, V5 §15.5)
	if k == 0 and dome_view_floor.has(int(b["id"])):
		k = int(dome_view_floor[int(b["id"])])
	elif k == 0 and float(meta["open"]) > 0.5:
		k = 5
	var sig := "%d|%d" % [int(s * 20.0), k]
	if sig != String(meta.get("dome_sig", "")):
		meta["dome_sig"] = sig
		var groups: Array = (tpl.get("groups", {}) as Dictionary).keys()
		var fit: Array = groups.filter(func(g): return not _dome_is_structure(String(g)))
		fit.sort()
		var rank_of := {}
		for i in fit.size():
			rank_of[fit[i]] = float(i) / maxf(1.0, float(fit.size()))
		for g in groups:
			var gs: String = g
			var show: bool = _dome_built(gs, s, float(rank_of.get(gs, 0.0)))
			if k > 0 and show:
				var fl: int = _dome_floor_of(gs)
				if fl > k or gs.begins_with("D_Floor_Roof") or gs.begins_with("D_Dome"):
					show = false
			inst.set_hidden(hnd, gs, not show)
	# Lift cabs: each rides a loop over the stops (1.5 m/s, 4 s at each stop), phase per cab.
	for i in 4:
		var g2 := "D_Lift_%d" % i
		if not (tpl.get("groups", {}) as Dictionary).has(g2):
			continue
		inst.set_extra(hnd, g2, Transform3D(Basis(), Vector3(0.0, _lift_y(_time + float(i) * 11.0), 0.0)))
	# Crane jib turns slowly while it stands.
	if s < 6.0 and (tpl.get("groups", {}) as Dictionary).has("D_Crane__Crane_Jib"):
		var jp: Vector3 = (tpl.get("jib_pivot", Transform3D.IDENTITY) as Transform3D).origin
		var rot := Basis(Vector3.UP, sin(_time * 0.05) * 1.4)
		inst.set_extra(hnd, "D_Crane__Crane_Jib", Transform3D(Basis(), jp) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis(), -jp))
	var gm = tpl.get("dome_glass")
	if gm is ShaderMaterial:
		(gm as ShaderMaterial).set_shader_parameter("night", clampf(maxf(float(sky.night), v4_dark * 0.85), 0.0, 1.0))
		(gm as ShaderMaterial).set_shader_parameter("sun_dir", sky.sun_dir)

## V5 §7 multi-storey rooms (ART-HAB F<n>_ groups, the apartment block): viewing floor k hides every
## F<n>_* group with n > k and the Roof. k: the followed person's floor + 1, else the UI floor selector,
## else no cut. (Floor 0 keeps the plain group names.)
func _floors_update(b: Dictionary, meta: Dictionary) -> void:
	var k := -1
	# (2026-10-01: no floor cut for the followed person: roofs and upper floors stay on, V5 §15.5)
	if k < 0 and dome_view_floor.has(int(b["id"])):
		k = int(dome_view_floor[int(b["id"])]) - 1
	elif k < 0 and float(meta["open"]) > 0.5:
		k = int(sim.bdef(b["def"]).get("floors", 1)) - 1   # cutaway: the top floor viewed
	var sig := str(k)
	if sig == String(meta.get("floor_sig", "")):
		return
	meta["floor_sig"] = sig
	if interior != null:
		interior.mark_dirty()
	for g in (meta["tpl"].get("groups", {}) as Dictionary):
		var gs: String = g
		var fl: int = Models.floor_of_group(gs)
		if fl > 0:
			var hide: bool = k >= 0 and (fl > k or (fl == k and gs.ends_with("_WallTop")))
			inst.set_hidden(int(meta["h"]), gs, hide)
	if k >= 0:
		inst.set_hidden(int(meta["h"]), "Roof", true)
	else:
		# (the roof came back only with the next roof cutaway change: no floor cut = the roof as _apply_roof has it)
		inst.set_hidden(int(meta["h"]), "Roof", float(meta["open"]) >= 1.0)

static func _dome_is_structure(g: String) -> bool:
	if g in ["D_Foundation", "D_Site", "D_Gates", "D_Lifts", "D_Dome"] or g.begins_with("D_Crane") or g.begins_with("D_Scaffold_") or g.begins_with("D_Lift_") or g.begins_with("D_Dome__"):
		return true
	var fl: int = _dome_floor_of(g)
	if fl > 0 and (g == "D_Floor_%d" % fl or g.begins_with("D_Floor_%d__Struct" % fl)):
		return true
	return g.begins_with("D_Floor_Roof") and g.contains("Struct")

## A lift cab's height: a loop over the stops up and down, 1.5 m/s, 4 s dwell.
func _lift_y(t: float) -> float:
	var legs: Array = []
	var seq: Array = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1]
	var total := 0.0
	for j in seq.size():
		var a: float = LIFT_STOPS[seq[j]]
		var bb: float = LIFT_STOPS[seq[(j + 1) % seq.size()]]
		var dur: float = absf(bb - a) / 1.5
		legs.append([a, bb, dur])
		total += dur + 4.0
	var u: float = fposmod(t, total)
	for l in legs:
		if u < 4.0:
			return float(l[0])
		u -= 4.0
		if u < float(l[2]):
			return lerpf(float(l[0]), float(l[1]), smoothstep(0.0, 1.0, u / float(l[2])))
		u -= float(l[2])
	return 0.0

# ---------------------------------------------------------------- V5 §3 follow view (RENDER camera)
var bubbles
var photos                   # fx_photo: photo() for the Rag and portraits (V5 §4.4)
var follow_id := -1
var _follow_open := {}      # building id -> true: interior drawn under the closed roof (follow view)
var roofs_off := false      # Paul 2026-10-01: every roof and upper wall cut away (normal view only)
var fprobe                   # fx_follow_probe (measurement only, debug "fprobe")

## Over-the-shoulder follow of a person (V5 §3). UI binds V / the Follow button / Esc / Tab to
## follow_start, follow_stop and follow_next; the camera rig does the spring, orbit, zoom, Q/E swap.
func follow_start(id: int) -> bool:
	var r = rig()
	if r == null or not r.has_method("shoulder_start") or not sim.state["agents"].has(id) or agent_world_pos(id) == null:
		return false
	follow_id = id
	bubbles.follow_id = id
	r.shoulder_start(func(): return _follow_body(id))
	Models.near_fade(0.8, 1.4)
	r.collide_fn = _follow_collide
	if "slide_fn" in r:
		r.slide_fn = follow_slide
	if "ceil_fn" in r:
		r.ceil_fn = follow_ceiling
	return true

func follow_stop() -> void:
	var r = rig()
	if r != null and r.has_method("shoulder_stop"):
		r.shoulder_stop()
		r.target_distance = 22.0
		r.distance = 22.0
	follow_id = -1
	bubbles.follow_id = -1
	_follow_open = {}
	Models.near_fade(0.0, 0.001)

## Paul 2026-10-01 (V5 §15.5): one view state that cuts away every roof and upper wall in the colony at
## once (the same cutaway as near the camera: nothing above 1.40 m but the allowed parts). Off = the
## automatic cutaway near the camera. The follow view ignores it (roofs stay on there). UI: button, key, setting.
func set_roofs_off(on: bool) -> void:
	roofs_off = on

func in_follow() -> bool:
	return follow_id >= 0

## The next living person (Tab), by id order.
func follow_next() -> int:
	var ids: Array = []
	for id in sim.state["agents"]:
		if sim.state["agents"][id]["state"] == "alive" and agent_world_pos(int(id)) != null:
			ids.append(int(id))
	ids.sort()
	if ids.is_empty():
		return -1
	var nx: int = ids[0]
	for id in ids:
		if id > follow_id:
			nx = id
			break
	follow_start(nx)
	return nx

## [ground point, body yaw, eye height, indoors, game rate] of the followed person, or null.
func _follow_body(id: int):
	if not sim.state["agents"].has(id) or sim.state["agents"][id]["state"] != "alive":
		follow_id = -1
		bubbles.follow_id = -1
		return null
	var p = agent_world_pos(id)
	if p == null:
		return null
	var yaw := 0.0
	var eye := 1.65
	if npc != null and npc.agents.has(id):
		yaw = float(npc.agents[id]["yaw"])
		var clip: String = String(npc.agents[id]["sm"].cur)
		if clip in ["sleep", "lie_enter", "lie_exit", "collapse", "dead"]:
			eye = 0.7
		elif clip.begins_with("sit") or clip in ["drive_sit", "ride_sit"]:
			eye = 1.2
		elif clip.begins_with("kneel") or clip == "repair_kneel":
			eye = 1.05
	var indoor: bool = String(sim.state["agents"][id].get("where", "")) != "out"
	return [p, yaw, eye, indoor, game_rate]

## The rooms and exteriors whose walls a point or a segment meets (xz circles).
func _follow_circles(center: Vector3, reach: float) -> Array:
	var out: Array = []
	var c2 := Vector2(center.x, center.z)
	for id in bmeta:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty() or b["kind"] == "link" or not (b["kind"] in ["room", "exterior"]):
			continue
		var r: float = float(b["radius"]) * (1.0 if b["kind"] == "room" else 0.8)
		var bp: Vector2 = b["pos"]
		if bp.distance_to(c2) < r + reach:
			out.append([int(id), bp, r, b["kind"] == "room"])
	return out

## The camera never passes a wall (V5 §3; roofs on, Paul 2026-10-01). Returns the eye moved out of every
## wall: `margin` m clear of it, PUSHED to the nearest clear point (a continuous move as the person walks
## along a wall). A first-hit pull along the line from the shoulder jumped by up to 1.4 m in one frame
## when the line swept past a wall edge (2026-10-01). Then, unless point_only: if the pushed eye cannot
## see the shoulder (a wall between them), it is pulled in along that line to the first wall.
## Indoors (SIM where != out): the eye stays inside the union of the rooms and corridors round the person
## (a doorway is no wall). Outdoors: it stays out of every structure circle and ship / vehicle box.
func _follow_collide(pivot: Vector3, eye: Vector3, margin: float = 0.3, point_only: bool = false, knee: float = 0.0) -> Vector3:
	var fb = agent_world_pos(follow_id) if follow_id >= 0 else null
	var fin: bool = follow_id >= 0 and String(sim.state["agents"].get(follow_id, {}).get("where", "out")) != "out"
	var rg = rig()
	if rg != null and "collide_smooth" in rg:
		rg.collide_smooth = false
	if fb != null and fin:
		var vols: Array = _follow_volumes(pivot, (eye - pivot).length() + 2.0 + knee)
		if _vol_inside(vols, fb as Vector3, 0.0):
			if knee > 0.0:
				# Indoors with a knee: the soft wall rule (2026-10-02). One smooth function of the free eye, no
				# springs, no hard clamp after it: see _vol_soft.
				if rg != null and "collide_smooth" in rg:
					rg.collide_smooth = true
				# (knee 0.8: the camera's target; a small knee = the guard on the sprung eye, against the real wall)
				# (2026-10-02: the guard's zone, margin + knee, must lie inside the target's margin, or every
				# frame of spring lag near a wall bends the eye: 84 % of the 4x camera jerk. Target margins 0.5 / 0.45,
				# guard 0.05 + knee 0.2: 0.2-0.25 m of room for the spring.)
				if knee > 0.5:
					# An eye far outside the walls (a wall right behind the person) is first drawn in along the
					# boom toward the shoulder, by how deep outside it is (continuous): the nearest-point rule
					# alone swept the target 2 m sideways round a corner in 0.25 s (2026-10-02).
					var h_free: float = float(_vol_field(vols, Vector2(eye.x, eye.z), 0.5, 0.45, -FOLLOW_TARGET_TAU)[0])
					var e2: Vector3 = eye
					if h_free < 0.0:
						e2 = pivot + (eye - pivot) * clampf(1.0 + h_free / FOLLOW_BOOM_IN, 0.35, 1.0)
					return _vol_soft(vols, e2, knee, 0.5, 0.45, -FOLLOW_TARGET_TAU)
				return _vol_soft(vols, eye, knee, 0.05, 0.05, -FOLLOW_UNION_TAU)
			var q: Vector3 = eye if _vol_inside(vols, eye, margin) else _vol_project(vols, eye, margin)
			if point_only and q.distance_to(eye) > 0.05:
				_fc_note("t%.2f indoor hard %.2f" % [_time, q.distance_to(eye)])
			# (no sight-line pull indoors: the camera stays inside the rooms and corridors; at a doorway a wall
			# edge may hide the person for a moment. The pull along the sight line jumped as the line swept
			# past the door frame and dragged the camera, 2026-10-01.)
			return q
	# Outdoors: out of the structure circles (the person is outside them) ...
	var q2: Vector3 = eye
	var a := Vector2(pivot.x, pivot.z)
	var ap: Vector2 = Vector2((fb as Vector3).x, (fb as Vector3).z) if fb != null else a
	for c in _follow_circles(eye, margin + 0.5):
		var cp: Vector2 = c[1]
		var r: float = float(c[2])
		# (the PERSON inside this circle, not the shoulder point: a person walking 0.4 m off a wall has the
		# shoulder inside the circle; the wall was skipped and the camera ran into it, 2026-10-01)
		if ap.distance_to(cp) < r - 0.05:
			continue
		var e2 := Vector2(q2.x, q2.z)
		var dd: float = e2.distance_to(cp)
		if dd < r + margin:
			var dir: Vector2 = (e2 - cp) / maxf(dd, 0.001) if dd > 0.001 else (a - cp).normalized()
			var np: Vector2 = cp + dir * (r + margin)
			q2 = Vector3(np.x, q2.y, np.y)
			if point_only and r + margin - dd > 0.05:
				_fc_note("t%.2f circle %d %s r%.2f in %.2f" % [_time, int(c[0]), String(sim.state["buildings"][c[0]]["def"]), r, r + margin - dd])
	# ... and out of the ship and vehicle boxes (pushed out on the shortest side, in xz).
	for ab in _follow_obstacles():
		var bx: AABB = (ab as AABB).grow(margin)
		if bx.has_point(pivot) or not bx.has_point(q2):
			continue
		var outs := [bx.position.x - q2.x, bx.end.x - q2.x, bx.position.z - q2.z, bx.end.z - q2.z]
		var k := 0
		for i in 4:
			if absf(outs[i]) < absf(outs[k]):
				k = i
		if k < 2:
			q2.x += outs[k]
		else:
			q2.z += outs[k]
		if point_only and absf(outs[k]) > 0.05:
			_fc_note("t%.2f box %.2f" % [_time, absf(outs[k])])
	if point_only:
		return q2
	# The sight line from the shoulder to the pushed eye: a structure (its wall, no margin) across it
	# pulls the eye in to the first one.
	var d3: Vector3 = q2 - pivot
	var d: Vector2 = Vector2(d3.x, d3.z)
	if d.length() < 0.01:
		return q2
	var best: float = 1.0
	for c in _follow_circles(pivot, d.length() + 1.0):
		var cp: Vector2 = c[1]
		var r: float = float(c[2])
		if a.distance_to(cp) < r - 0.05:
			continue
		var f: Vector2 = a - cp
		var qa: float = d.dot(d)
		var qb: float = 2.0 * f.dot(d)
		var qc: float = f.dot(f) - r * r
		if ap.distance_to(cp) < r - 0.05:
			continue
		var disc: float = qb * qb - 4.0 * qa * qc
		if disc < 0.0:
			continue
		var t: float = (-qb - sqrt(disc)) / (2.0 * qa)
		if t > 0.0 and t < best:
			best = t
	for ab in _follow_obstacles():
		var bx2: AABB = ab as AABB
		if bx2.has_point(pivot):
			continue
		var hit = bx2.intersects_segment(pivot, q2)
		if hit != null:
			best = minf(best, ((hit as Vector3) - pivot).length() / maxf(d3.length(), 0.001))
	if best >= 1.0:
		return q2
	return pivot.lerp(q2, clampf(best - margin / maxf(d3.length(), 0.01), 0.08, 1.0))

## The point inside the volumes (margin off the walls) nearest p, in xz (y kept).
static func _vol_project(vols: Array, p: Vector3, margin: float) -> Vector3:
	var q := Vector2(p.x, p.z)
	var best := Vector2.INF
	var bd := INF
	for v in vols:
		var c: Vector2
		if v[0] == "room":
			var cp: Vector2 = v[1]
			var r: float = maxf(float(v[2]) - margin, 0.05)
			c = q if q.distance_to(cp) <= r else cp + (q - cp).normalized() * r
		else:
			var s: Vector2 = Geometry2D.get_closest_point_to_segment(q, v[1], v[2])
			var r2: float = maxf(float(v[3]) - (clampf(margin, 0.3, 0.5) if margin > 0.0 else 0.0), 0.05)
			c = q if q.distance_to(s) <= r2 else s + (q - s).normalized() * r2
		var dd: float = c.distance_to(q)
		if dd < bd:
			bd = dd
			best = c
	if best == Vector2.INF:
		return p
	return Vector3(best.x, p.y, best.y)

const FOLLOW_UNION_TAU := 0.2  # m: smoothing of the union of the volumes (log-sum-exp; the guard: weighted mean)
const FOLLOW_TARGET_TAU := 0.4 # m: the camera target's union (weighted mean): a wider fillet where a corridor meets a room
const FOLLOW_BOOM_IN := 1.5    # m: an eye this far outside the walls is drawn in to 35 % of the boom first
## The soft wall rule (2026-10-02; the indoor camera jerk regression: springs after a hard projection made a kinked
## path). Depth field H(q) = log-sum-exp over the rooms and corridors of their depth inside a margin: R - m_room
## - |q - c| for a room, r - m_tube - dist(q, axis) for a corridor; H >= 0 is "the eye may be here". The eye keeps
## its place while H >= knee; below that its depth becomes phi(H) = knee exp(-(knee - H) / knee) (phi(knee) = knee,
## phi' = 1 there, phi > 0 always: the eye never reaches the margin; a wall far outside gives the margin itself).
## The eye is moved along the field's gradient to that depth (3 Newton steps on the same target). Position and
## velocity are continuous in the eye; the acceleration is bounded by v^2 / knee. y is kept. Where two volumes
## meet (a corridor mouth) the nearest region point still flips between them over a short distance: the camera
## rig takes that out with a spring (camera_rig, SH_W_SMOOTH).
func _vol_soft(vols: Array, p: Vector3, knee: float, m_room: float, m_tube: float, tau: float = FOLLOW_UNION_TAU) -> Vector3:
	var q := Vector2(p.x, p.z)
	var h0 := _vol_field(vols, q, m_room, m_tube, tau)
	if h0[0] >= knee:
		fc_win = "free"
		return p
	var target: float = knee * exp(-(knee - float(h0[0])) / knee)
	var cur := q
	var n := 0
	for it in 3:
		var f: Array = _vol_field(vols, cur, m_room, m_tube, tau)
		var gr: Vector2 = f[1]
		var dh: float = target - float(f[0])
		if gr.length() < 0.05 or absf(dh) < 0.002:
			break
		cur += gr.normalized() * dh
		n += 1
	var fin: Array = _vol_field(vols, cur, m_room, m_tube, tau)
	fc_win = "%d/%.2f" % [n, float(fin[0])]
	if float(fin[0]) < -0.02:
		# (the field is a smoothed union: in a rare notch it can over-estimate; the hard rule stands)
		fc_win += "h"
		return _vol_project(vols, p, maxf(m_room, 0.05))
	return Vector3(cur.x, p.y, cur.y)

## The indoor guard as a SLIDE (2026-10-02): from last frame's eye `from` (inside the rooms and corridors) toward
## the sprung eye `to` in 4 cm steps; a step that leaves the walls (margin 0.05 m) is pushed back onto them along
## the nearest volume's normal. The eye moves continuously by construction. The projection of the sprung eye
## alone flipped between a room and a corridor where they meet: 0.6 m one-frame camera jumps at 4x.
## Returns `to` unchanged outdoors; the soft guard when `from` is not inside (a new view, a jump).
func follow_slide(shoulder: Vector3, from: Vector3, to: Vector3) -> Vector3:
	var fb = agent_world_pos(follow_id) if follow_id >= 0 else null
	if fb == null or String(sim.state["agents"].get(follow_id, {}).get("where", "out")) == "out":
		return to
	var vols: Array = _follow_volumes(shoulder, (to - shoulder).length() + 2.5)
	if not _vol_inside(vols, fb as Vector3, 0.0):
		return to
	var p := Vector2(from.x, from.z)
	var q := Vector2(to.x, to.z)
	if float(_vol_field(vols, p, 0.05, 0.05, 0.0)[0]) < -0.01:
		return _vol_soft(vols, to, 0.2, 0.05, 0.05, -FOLLOW_UNION_TAU)
	var n: int = clampi(int(ceil(p.distance_to(q) / 0.04)), 1, 60)
	for i in n:
		var np: Vector2 = p + (q - p) / float(n - i)
		for _k in 2:
			var f: Array = _vol_field(vols, np, 0.05, 0.05, 0.0)
			if float(f[0]) >= 0.0:
				break
			var g: Vector2 = f[1]
			if g.length() < 0.01:
				np = p
				break
			np += g.normalized() * (-float(f[0]))
		p = np
	fc_win = "slide"
	return Vector3(p.x, to.y, p.y)

## [H, grad H (xz, pointing to larger H)] at q: the smoothed union depth of the volumes (see _vol_soft).
static func _vol_field(vols: Array, q: Vector2, m_room: float, m_tube: float, tau: float = FOLLOW_UNION_TAU) -> Array:
	var hs: Array = []
	var gs: Array = []
	var hmax := -INF
	for v in vols:
		var cp: Vector2
		var rh: float
		if v[0] == "room":
			cp = v[1]
			rh = float(v[2]) - m_room
		else:
			cp = Geometry2D.get_closest_point_to_segment(q, v[1], v[2])
			rh = float(v[3]) - m_tube
		var d: float = q.distance_to(cp)
		var hv: float = rh - d
		hs.append(hv)
		gs.append((cp - q) / d if d > 0.0005 else Vector2.ZERO)
		hmax = maxf(hmax, hv)
	if hs.is_empty():
		return [-INF, Vector2.ZERO]
	if tau == 0.0:
		# the exact union (the slide): the deepest volume and its gradient
		var im: int = hs.find(hmax)
		return [hmax, gs[im]]
	if tau < 0.0:
		# The guard (tau < 0, |tau| used): the softmax-WEIGHTED MEAN of the depths, never above the true union
		# depth (log-sum-exp over-estimates it by up to tau ln 2 = 0.14 m where two volumes meet, and the guarded
		# eye stood 0.09 m outside the walls there; the exact max flips between the volumes, 2026-10-02).
		# grad = mean_w(g) + cov_w(h, g) / tau.
		var ta: float = -tau
		var ws := 0.0
		var hm := 0.0
		var gm := Vector2.ZERO
		var hg := Vector2.ZERO
		for i in hs.size():
			var wi: float = exp((float(hs[i]) - hmax) / ta)
			ws += wi
			hm += wi * float(hs[i])
			gm += wi * (gs[i] as Vector2)
			hg += wi * float(hs[i]) * (gs[i] as Vector2)
		hm /= ws
		gm /= ws
		hg /= ws
		return [hm, gm + (hg - hm * gm) / ta]
	var wsum := 0.0
	var gacc := Vector2.ZERO
	for i in hs.size():
		var w: float = exp((float(hs[i]) - hmax) / tau)
		wsum += w
		gacc += (gs[i] as Vector2) * w
	return [hmax + tau * log(wsum), gacc / wsum]

## Measurement: how deep p (xz) is inside the union of the rooms and corridors round the followed person,
## from the wall itself (max over volumes of radius - distance); 99 outdoors or when the person is outdoors.
func follow_depth(p: Vector3) -> float:
	if follow_id < 0 or String(sim.state["agents"].get(follow_id, {}).get("where", "out")) == "out":
		return 99.0
	var best := -INF
	var q := Vector2(p.x, p.z)
	for v in _follow_volumes(p, 0.0):
		if v[0] == "room":
			best = maxf(best, float(v[2]) - q.distance_to(v[1]))
		else:
			best = maxf(best, float(v[3]) - Geometry2D.get_closest_point_to_segment(q, v[1], v[2]).distance_to(q))
	return best if best > -INF else -9.0

## Does the line a-b stay inside the volumes (8 cm steps)?
static func _vol_line_inside(vols: Array, a: Vector3, b: Vector3, margin: float) -> bool:
	var n: int = maxi(2, int(ceil(a.distance_to(b) / 0.08)))
	for i in n + 1:
		if not _vol_inside(vols, a.lerp(b, float(i) / float(n)), margin):
			return false
	return true

## The last point inside the volumes on a-b before the first exit (8 cm steps, refined by halving).
static func _vol_first_exit(vols: Array, a: Vector3, b: Vector3, margin: float) -> Vector3:
	var n: int = maxi(2, int(ceil(a.distance_to(b) / 0.08)))
	var last_in := 0.0
	for i in n + 1:
		var t: float = float(i) / float(n)
		if _vol_inside(vols, a.lerp(b, t), margin):
			last_in = t
		else:
			var lo: float = last_in
			var hi: float = t
			for _k in 5:
				var mid: float = (lo + hi) * 0.5
				if _vol_inside(vols, a.lerp(b, mid), margin):
					lo = mid
				else:
					hi = mid
			return a.lerp(b, maxf(lo, 0.08))
	return b

var fc_win := ""             # measurement: the soft wall rule's winner volume / candidates (m = blended, f = blend refused)
var fc_dbg: Array = []       # measurement: the last hard pull-in causes (fprobe get)
## Adds one pull-in cause to fc_dbg (measurement), keeping only the last FC_DBG_MAX (it had no cap).
const FC_DBG_MAX := 400
func _fc_note(t: String) -> void:
	fc_dbg.append(t)
	if fc_dbg.size() > 2 * FC_DBG_MAX:
		fc_dbg = fc_dbg.slice(fc_dbg.size() - FC_DBG_MAX)
const FOLLOW_TUBE_R := 1.15   # m: corridor inside radius for the camera (fx_npc_path.TUBE_R)
## Rooms (xz circles) and corridors (xz capsules) within `reach` of p: [["room", centre, r, id] | ["tube", p0, p1, r, id]].
func _follow_volumes(p: Vector3, reach: float) -> Array:
	var out: Array = []
	var q := Vector2(p.x, p.z)
	for id in bmeta:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty():
			continue
		if b["kind"] == "room":
			var r: float = float(b["radius"])
			if (b["pos"] as Vector2).distance_to(q) < r + reach:
				out.append(["room", b["pos"], r, int(id)])
		elif b["def"] == "corridor":
			var c: Vector2 = Geometry2D.get_closest_point_to_segment(q, b["p0"], b["p1"])
			if c.distance_to(q) < FOLLOW_TUBE_R + reach:
				out.append(["tube", b["p0"], b["p1"], FOLLOW_TUBE_R, int(id)])
	return out

## Is p (xz) inside one of the volumes, `margin` m off its wall? (a corridor keeps at most 0.35 m)
static func _vol_inside(vols: Array, p: Vector3, margin: float) -> bool:
	var q := Vector2(p.x, p.z)
	for v in vols:
		if v[0] == "room":
			if q.distance_to(v[1]) < float(v[2]) - margin:
				return true
		else:
			if Geometry2D.get_closest_point_to_segment(q, v[1], v[2]).distance_to(q) < float(v[3]) - (clampf(margin, 0.3, 0.5) if margin > 0.0 else 0.0):
				return true
	return false

## The ceiling (world y) over a camera point p for a person standing at `feet` (Paul 2026-10-01: the
## camera stays under the ceiling): a room's from its model height, a corridor 2.3 m over its floor, a
## floor of a multi-storey building (super dome, apartment block) 3.4 m over the person's feet. INF outdoors.
func follow_ceiling(feet: Vector3, p: Vector3) -> float:
	if follow_id >= 0 and String(sim.state["agents"].get(follow_id, {}).get("where", "out")) == "out":
		return INF
	var vols: Array = _follow_volumes(p, 0.0)
	var best := INF
	for v in vols:
		if not _vol_inside([v], p, 0.0):
			continue
		var c := INF
		if v[0] == "room":
			var b: Dictionary = sim.state["buildings"][v[3]]
			var meta: Dictionary = bmeta[v[3]]
			if String(b["def"]) == "super_dome" or int(sim.bdef(b["def"]).get("floors", 1)) > 1:
				c = feet.y + 3.4
			else:
				# The underside of the roof over the camera point, from the model (_roof_ceiling).
				c = _roof_ceiling(b, meta, p)
				if c == INF:
					c = (meta["xf"] as Transform3D).origin.y + clampf(float(meta["top"]) - 0.6, 2.4, 6.0)
		else:
			var b2: Dictionary = sim.state["buildings"][v[4]]
			c = _roof_ceiling(b2, bmeta[v[4]], p) if bmeta.has(v[4]) else INF
			if c == INF:
				c = feet.y + 2.3
		best = minf(best, c)
	# (a point outside every room and corridor, e.g. the eye pressed to a wall: the ceiling over the person;
	# INF here let the eye jump 0.9 m up for a frame, 2026-10-02)
	if best == INF and p.distance_to(feet) > 0.05:
		var pf := Vector3(feet.x, p.y, feet.z)
		if not _follow_volumes(pf, 0.0).is_empty():
			return follow_ceiling(feet, pf)
	return best

## Paul 2026-10-01 (roofs on in the follow view): the roof shell is drawn single-sided (from outside), so
## from inside a room the upper walls and the roof were see-through. The shell materials of the Roof group
## (PaletteShell, Accent, Glass) become two-sided per template (their back faces light as a ceiling). Seen
## from outside nothing changes (the front faces hide the back faces).
func _roof_inside(tpl: Dictionary) -> void:
	if bool(tpl.get("roof_ds", false)):
		return
	tpl["roof_ds"] = true
	for part in (tpl.get("parts", []) as Array):
		if String(part["group"]) != "Roof":
			continue
		var m: Mesh = part["mesh"]
		if not (m is ArrayMesh):
			continue
		for si in m.get_surface_count():
			var mat = m.surface_get_material(si)
			if mat is BaseMaterial3D and String(mat.resource_name) in ["PaletteShell", "Accent", "Glass"] and (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK:
				var dm: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
				dm.cull_mode = BaseMaterial3D.CULL_DISABLED
				(m as ArrayMesh).surface_set_material(si, dm)

const ROOF_CELL := 0.4
## The ceiling (world y) over p in a room or corridor: the lowest roof surface above 1.6 m (model space)
## in a 0.4 m grid of the template's Roof triangles, built once per template. INF where the model has none.
func _roof_ceiling(b: Dictionary, meta: Dictionary, p: Vector3) -> float:
	var tpl: Dictionary = meta["tpl"]
	if not tpl.has("roof_grid"):
		tpl["roof_grid"] = _build_roof_grid(tpl)
	var g: Dictionary = tpl["roof_grid"]
	if g.is_empty():
		return INF
	var xf: Transform3D = meta["xf"]
	var s: float = float(tpl.get("scale", 1.0))
	var full: Transform3D = xf * Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3.ZERO)
	var lp: Vector3 = full.affine_inverse() * p
	# Bilinear over the 4 nearest cell centres (a nearest-cell lookup stepped by up to 0.9 m between two
	# cells and dropped the camera in one frame, 2026-10-01); a missing neighbour takes the lowest found.
	var cells: Dictionary = g["cells"]
	var gx: float = lp.x / ROOF_CELL - 0.5
	var gz: float = lp.z / ROOF_CELL - 0.5
	var x0: int = int(floor(gx))
	var z0: int = int(floor(gz))
	var fx: float = gx - x0
	var fz: float = gz - z0
	var vals: Array = [cells.get(Vector2i(x0, z0), INF), cells.get(Vector2i(x0 + 1, z0), INF), cells.get(Vector2i(x0, z0 + 1), INF), cells.get(Vector2i(x0 + 1, z0 + 1), INF)]
	var lo := INF
	for v in vals:
		lo = minf(lo, float(v))
	if lo == INF:
		return INF
	for i in 4:
		if float(vals[i]) == INF:
			vals[i] = lo
	var ly: float = lerpf(lerpf(float(vals[0]), float(vals[1]), fx), lerpf(float(vals[2]), float(vals[3]), fx), fz)
	return (full * Vector3(lp.x, ly, lp.z)).y

static func _build_roof_grid(tpl: Dictionary) -> Dictionary:
	var cells := {}
	for part in (tpl.get("parts", []) as Array):
		if String(part["group"]) != "Roof":
			continue
		var xf: Transform3D = part["xf"]
		var f: PackedVector3Array = (part["mesh"] as Mesh).get_faces()
		for i in range(0, f.size() - 2, 3):
			var a: Vector3 = xf * f[i]
			var b: Vector3 = xf * f[i + 1]
			var c: Vector3 = xf * f[i + 2]
			if minf(a.y, minf(b.y, c.y)) < 1.6:
				continue
			var x0: int = int(floor(minf(a.x, minf(b.x, c.x)) / ROOF_CELL))
			var x1: int = int(floor(maxf(a.x, maxf(b.x, c.x)) / ROOF_CELL))
			var z0: int = int(floor(minf(a.z, minf(b.z, c.z)) / ROOF_CELL))
			var z1: int = int(floor(maxf(a.z, maxf(b.z, c.z)) / ROOF_CELL))
			for cx in range(x0, x1 + 1):
				for cz in range(z0, z1 + 1):
					var q := Vector2((cx + 0.5) * ROOF_CELL, (cz + 0.5) * ROOF_CELL)
					var bc = Geometry2D.point_is_inside_triangle(q, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
					var y: float
					if bc:
						# barycentric height
						var v0 := Vector2(b.x - a.x, b.z - a.z)
						var v1 := Vector2(c.x - a.x, c.z - a.z)
						var v2 := q - Vector2(a.x, a.z)
						var den: float = v0.x * v1.y - v1.x * v0.y
						if absf(den) < 1e-6:
							continue
						var u: float = (v2.x * v1.y - v1.x * v2.y) / den
						var w: float = (v0.x * v2.y - v2.x * v0.y) / den
						y = a.y + u * (b.y - a.y) + w * (c.y - a.y)
					elif (x1 - x0) == 0 or (z1 - z0) == 0:
						# a thin triangle that covers no cell centre: its lowest point counts for its cell
						y = minf(a.y, minf(b.y, c.y))
					else:
						continue
					var key := Vector2i(cx, cz)
					cells[key] = minf(float(cells.get(key, INF)), y)
	return {} if cells.is_empty() else {"cells": cells}

var _obst: Array = []
var _obst_t := -10.0
## World boxes of the ships (pad ship and visiting traffic) and the vehicles, rebuilt twice a second.
func _follow_obstacles() -> Array:
	if _time - _obst_t < 0.5:
		return _obst
	_obst_t = _time
	_obst = []
	var nodes: Array = []
	if traffic != null:
		for r in traffic.ships.values():
			if r.get("node") != null:
				nodes.append(r["node"])
	if ship != null and ship.node != null:
		nodes.append(ship.node)
	if vehicles != null:
		for r in vehicles.vehicles.values():
			nodes.append(r["node"])
	for nd in nodes:
		if not is_instance_valid(nd) or not (nd as Node3D).is_visible_in_tree():
			continue
		var box := AABB()
		var first := true
		for vi in (nd as Node).find_children("*", "MeshInstance3D", true, false):
			var b3: AABB = (vi as MeshInstance3D).global_transform * (vi as MeshInstance3D).get_aabb()
			box = b3 if first else box.merge(b3)
			first = false
		if not first:
			_obst.append(box)
	return _obst

## Line of sight for bubbles: no closed (not cut away) wall between two heads.
func follow_los(a3: Vector3, b3: Vector3) -> bool:
	var a := Vector2(a3.x, a3.z)
	var b2 := Vector2(b3.x, b3.z)
	for c in _follow_circles(a3, a.distance_to(b2) + 1.0):
		var cp: Vector2 = c[1]
		var r: float = c[2]
		var ia: bool = a.distance_to(cp) < r
		var ib: bool = b2.distance_to(cp) < r
		if ia == ib and not ia:
			# both outside: blocked only if the segment passes through the building
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(cp, a, b2)
			if q.distance_to(cp) >= r:
				continue
		elif ia == ib:
			continue
		var open: bool = bmeta.has(c[0]) and float(bmeta[c[0]].get("open", 0.0)) > 0.5
		if not open:
			return false
	return true

## Follow view each frame: the rooms round the person and the camera open (roof and upper walls
## cut away), as the cutaway rule does near the camera.
func _follow_sync() -> void:
	if follow_id < 0:
		_follow_indoor(Vector3.INF)
		if not _follow_open.is_empty():
			_follow_open = {}
		return
	var r = rig()
	if r == null or not r.in_shoulder():
		follow_id = -1
		bubbles.follow_id = -1
		_follow_open = {}
		Models.near_fade(0.0, 0.001)
		return
	var p = agent_world_pos(follow_id)
	if p == null:
		return
	var cam: Vector3 = r.camera.global_position
	_follow_open = {}
	for c in _follow_circles(p, 6.0) + _follow_circles(cam, 3.0):
		_follow_open[c[0]] = true
	# Corridors the person is in or next to.
	for id in bmeta:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty() or b["def"] != "corridor":
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), b["p0"], b["p1"])
		if q.distance_to(Vector2(p.x, p.z)) < 5.0:
			_follow_open[int(id)] = true
	_follow_indoor(cam)

var _indoor := 0.0
var _fill: OmniLight3D
## The follow camera inside a room under its roof (Paul 2026-10-01): the sky drops the outdoor haze and
## lifts the ambient (fx_sky.indoor), and a soft fill light rides above the camera (no shadow, 7 m) so the
## interior reads with the roof on. Eased over about 0.5 s (a doorway is not a flash).
func _follow_indoor(cam: Vector3) -> void:
	var want: float = 0.0
	if cam != Vector3.INF and follow_id >= 0:
		var fb = agent_world_pos(follow_id)
		if fb != null and follow_ceiling(fb as Vector3, cam) < INF:
			want = 1.0
	_indoor = move_toward(_indoor, want, get_process_delta_time() * 2.0)
	sky.indoor = _indoor
	if _indoor <= 0.0:
		if _fill != null:
			_fill.visible = false
		return
	if _fill == null:
		_fill = OmniLight3D.new()
		_fill.name = "FollowFill"
		_fill.shadow_enabled = false
		_fill.omni_range = 7.0
		_fill.omni_attenuation = 1.4
		_fill.light_color = Color("ffe9d2")
		add_child(_fill)
	_fill.visible = true
	_fill.light_energy = 0.9 * _indoor
	if cam != Vector3.INF:
		_fill.global_position = cam + Vector3(0.0, 0.25, 0.0)

var _clip_clock := 0.0
## Paul 2026-10-01: weather particles (storm field, camera dust, dust bursts, devils) are never drawn inside a
## room or corridor (roof on or off, any camera). The rooms and corridors within 75 m of the focus and the
## camera go to the particle shader (fx_particles.set_clip; the nearest 32 of each).
func _weather_clip(focus: Vector3, cam: Vector3) -> void:
	var rooms: Array = []
	var tubes: Array = []
	for id in bmeta:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty() or String(b.get("state", "")) == "blueprint":
			continue
		if b["kind"] == "room":
			var bp: Vector2 = b["pos"]
			var d: float = minf(bp.distance_to(Vector2(focus.x, focus.z)), bp.distance_to(Vector2(cam.x, cam.z)))
			if d < 75.0 + float(b["radius"]):
				var meta: Dictionary = bmeta[id]
				var top: float = (meta["xf"] as Transform3D).origin.y + float(meta.get("top", 4.0)) + 0.3
				rooms.append([d, Vector4(bp.x, bp.y, float(b["radius"]) + 0.15, top)])
		elif b["def"] == "corridor":
			var p0: Vector2 = b["p0"]
			var p1: Vector2 = b["p1"]
			var mid: Vector2 = (p0 + p1) * 0.5
			var d2: float = minf(Geometry2D.get_closest_point_to_segment(Vector2(focus.x, focus.z), p0, p1).distance_to(Vector2(focus.x, focus.z)),
				Geometry2D.get_closest_point_to_segment(Vector2(cam.x, cam.z), p0, p1).distance_to(Vector2(cam.x, cam.z)))
			if d2 < 75.0:
				tubes.append([d2, Vector4(p0.x, p0.y, p1.x, p1.y), h(mid.x, mid.y) + 2.8])
	rooms.sort_custom(func(x, y): return x[0] < y[0])
	tubes.sort_custom(func(x, y): return x[0] < y[0])
	var ty := PackedFloat32Array()
	for t in tubes.slice(0, 32):
		ty.append(float(t[2]))
	fx.set_clip(rooms.slice(0, 32).map(func(x): return x[1]), tubes.slice(0, 32).map(func(x): return x[1]), ty)

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
	var deps: Array = sim.state["deposits"]
	_build_deposit_rings()
	for d in deps:
		var lab := Label3D.new()
		lab.text = String(d.get("kind", "ore")).to_upper().replace("_", " ") if d.has("kind") else "ORE"
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.fixed_size = true
		lab.pixel_size = 0.0007
		lab.font_size = 20
		lab.outline_size = 6
		lab.modulate = Color(1.0, 0.8, 0.55, 0.9)
		lab.outline_modulate = Color(0.05, 0.03, 0.02, 0.8)
		lab.position = to3(Vector2(d["x"], d["y"]), 1.6)
		lab.name = "DepositLabel"
		lab.set_meta("dep", d)
		add_child(lab)
		_dep_labels.append(lab)

func _build_deposit_rings() -> void:
	var src: Array = ring_mesh(0.96, 96).surface_get_arrays(0)
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var suv: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
	var deps: Array = sim.state["deposits"]
	_build_ring_mesh(deps.filter(func(d): return _dep_known(d)), "DepositRings", sv, suv, 1.0)
	_build_ring_mesh(deps.filter(func(d): return not _dep_known(d)), "DepositRingsUnknown", sv, suv, 0.0)
	_dep_known_n = deps.filter(func(d): return _dep_known(d)).size()

## SIM 2026-09-27: a deposit is known when surveyed (older maps: always).
func _dep_known(d: Dictionary) -> bool:
	return bool(d.get("surveyed", true))
var _dep_known_n := -1
var _dep_ring_nodes := {}
var _dep_clock := 0.0

## One mesh of dashed rings for `deps` (one draw call). known = 1 shows without the overlay.
func _build_ring_mesh(deps: Array, nm: String, sv: PackedVector3Array, suv: PackedVector2Array, known: float) -> void:
	var av := PackedVector3Array()
	var auv := PackedVector2Array()
	var an := PackedVector3Array()
	for d in deps:
		var r: float = float(d["r"]) + 1.2
		var o := Vector3(float(d["x"]), 0, float(d["y"]))
		for v in sv:
			av.append(o + v * r)
			an.append(Vector3.UP)
		auv.append_array(suv)
	if av.is_empty() and _dep_ring_nodes.has(nm) and is_instance_valid(_dep_ring_nodes[nm]) and (_dep_ring_nodes[nm] as Node).is_inside_tree():
		(_dep_ring_nodes[nm] as MeshInstance3D).mesh = null
	if not av.is_empty() and suv.size() == sv.size():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = av
		arrays[Mesh.ARRAY_NORMAL] = an
		arrays[Mesh.ARRAY_TEX_UV] = auv
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# The two ring nodes are kept and get the new mesh (a new instance made mid-game was at
		# times not lit by fx_sky's always-on spot and compiled an omni-only program).
		var old = _dep_ring_nodes.get(nm)
		var ring: MeshInstance3D = null
		if old != null and is_instance_valid(old) and (old as Node).is_inside_tree():
			ring = old
		if ring != null:
			ring.mesh = am
			var rab0: AABB = am.get_aabb()
			ring.custom_aabb = AABB(rab0.position - Vector3(0, 200, 0), rab0.size + Vector3(0, 900, 0))
			return
		ring = MeshInstance3D.new()
		_dep_ring_nodes[nm] = ring
		ring.mesh = am
		ring.material_override = decal_material(Color(1.0, 0.7, 0.35, 0.55), 1, 40.0, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.extra_cull_margin = 16.0
		# A box with height: the flat (y = 0) mesh box was missed by fx_sky's always-on spot, and a
		# rebuilt ring mesh (a deposit found) then compiled an omni-only program (67-83 ms web frame).
		var rab: AABB = am.get_aabb()
		ring.custom_aabb = AABB(rab.position - Vector3(0, 200, 0), rab.size + Vector3(0, 900, 0))
		ring.name = nm
		ring.set_meta("known", known)

		ring.set_instance_shader_parameter("icolor", Color(1, 1, 1, 1))
		ring.set_instance_shader_parameter("ipulse", 0.0)
		add_child(ring)
		_dep_rings.append(ring)

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
		# Game seconds per view second. The sim steps in 0.1 s ticks, so sim_dt / delta is 0 on most
		# frames and large on one: a time average of it rippled +-6 % at 10 Hz, and every drawn
		# body's speed and clip rate rippled with it (follow view jitter, 2026-10-01). The clock that
		# main.gd runs the ticks from (stepped time + its accumulator) is continuous: its rate is
		# exact on every frame (1, 2, 4 ... or 0 when paused). Old way when that clock is not there.
		var mp = get_parent()
		var acc = mp.get("_acc") if mp != null else null
		if acc != null:
			var cont: float = secs + float(acc)
			tick_age = float(acc)
			var cdt: float = 0.0 if _cont_prev < 0.0 else clampf(cont - _cont_prev, 0.0, 30.0)
			_cont_prev = cont
			game_rate = lerpf(game_rate, clampf(cdt / delta, 0.0, 1000.0), 1.0 - exp(-delta * 6.0))
		else:
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
	_planet_check()
	sky.update(t, day_len, daylight, delta, focus, camera_distance, wind)
	_v4_light(focus)
	post.apply(sky.grade, delta)
	Models.set_night(maxf(sky.night, v4_dark * 0.85), float(sky.storm))
	Models.animate(_time)
	tp = _prof("sky", tp)
	_camera_range()
	terrain.update_lod(delta, cam)
	terrain.fog_tick()
	if not _skip.has("paths"): terrain.update_paths(sim_dt)
	tp = _prof("paths", tp)
	_made_now = 0
	_sync_buildings(delta)
	tp = _prof("buildings", tp)
	# A colony just built (a load): do the one-time work now, in this (load) frame, instead of
	# in the frames after it (V3.1 stall trace: 60-240 ms frames in the first second).
	if _made_now >= 20:
		_boot_prewarm(cam)
		tp = _prof("boot", tp)
	if not _skip.has("airlock"): airlock.sync(delta)
	tp = _prof("airlock", tp)
	if npc.sync(delta):
		if not ameta.is_empty():
			for id in ameta.keys():
				_drop_agent(id)
	else:
		_sync_agents(delta)
	tp = _prof("agents", tp)
	if not _skip.has("doors"): doors.sync(delta, _body_points())
	if not _skip.has("interior"): interior.sync(delta, focus, sky.night)
	tp = _prof("doors", tp)
	if not _skip.has("hazards"): hazards.sync(delta, focus)
	tp = _prof("hazards", tp)
	_sync_piles()
	if not _skip.has("ship"): ship.sync(delta, sim_dt)
	if not _skip.has("traffic"): traffic.sync(delta)
	if not _skip.has("vehicles"): vehicles.sync(delta)
	if not _skip.has("reactor"): reactor.sync(delta)
	if not _skip.has("explore"): explore.sync(delta)
	_follow_sync()
	bubbles.sync(delta)
	photos.sync(delta)
	_fly_step(delta)
	_sync_selection(delta)
	overlays.sync(delta)
	tp = _prof("misc", tp)
	_status_clock -= delta
	if _status_clock <= 0.0:
		_status_clock = 0.2
		if not _skip.has("status"): _sync_status()
		_sync_stock()
	_sites_clock -= delta
	if _sites_clock <= 0.0:
		_sites_clock = 1.0
		if not _skip.has("sites"): _refresh_sites()
	tp = _prof("status", tp)
	_clip_clock -= delta
	if _clip_clock <= 0.0:
		_clip_clock = 0.25
		_weather_clip(focus, cam.global_position if cam != null else focus)
	if not _skip.has("fx"): fx.sync(delta, sim_dt, cam, focus, wind, sky.night, sky.storm, sky.sun_dir)
	tp = _prof("fx", tp)
	var show_words: bool = labels_visible and time_override < 0.0 and not _photo_mode()
	# V4 (critic round 20): on the v4 map the deposit rings and words show only with the resource
	# overlay (a survey will add per-deposit visibility when SIM publishes it).
	# SIM: a deposit counts once surveyed; unsurveyed ones show only with the resource overlay.
	var ov_res: bool = overlay in ["resources", "deposits"]
	_dep_clock -= delta
	if _dep_clock <= 0.0:
		_dep_clock = 2.0
		var kn: int = (sim.state["deposits"] as Array).filter(func(d): return _dep_known(d)).size()
		if kn != _dep_known_n:
			# Only the two ring meshes change (a label reads its deposit's surveyed flag live):
			# rebuilding ~100 Label3D each time the fog found a deposit cost 120-150 ms frames.
			_build_deposit_rings()
	for lab in _dep_labels:
		var dk: bool = _dep_known(lab.get_meta("dep", {}))
		(lab as Label3D).visible = show_words and camera_distance < 55.0 and ((overlay == "" and dk) or ov_res)
	for rg in _dep_rings:
		(rg as MeshInstance3D).visible = labels_visible and not _photo_mode() and (float(rg.get_meta("known", 1.0)) > 0.5 or ov_res)
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
var _force_open_all := false
## Groups that stand above the cut on purpose: furniture inside the room (shelves, tanks,
## racks: seen through the open roof) and wall items hidden by doorways.
const CUT_ALLOWED := ["Interior", "Stock", "Tall"]
func _cut_check() -> Dictionary:
	var out := {}
	var blds: Dictionary = sim.state["buildings"]
	for rid in bmeta:
		var b: Dictionary = blds.get(rid, {})
		var meta: Dictionary = bmeta[rid]
		if b.is_empty() or String(b["kind"]) != "room" or meta["mode"] != "inst":
			continue
		var key: String = "%s_%d" % [b["def"], int(b.get("size", 1))]
		var fy: float = (meta["xf"] as Transform3D).origin.y
		var hs: Array = [["room", int(meta["h"])]]
		for dd in doors.doors:
			if int(dd["room"]) == int(rid):
				hs.append(["door", int(dd["h"])])
		for ph in doors.cut_patches.get(rid, []):
			hs.append(["patch", int(ph)])
		var mask: int = int(doors.masks.get(rid, 0))
		var bad := {}
		var ok := {}
		for e in hs:
			if not inst.handles.has(e[1]):
				continue
			var he: Dictionary = inst.handles[e[1]]
			var bt: Dictionary = inst.batches[he["key"]]
			for pp in bt["parts"]:
				var part: Dictionary = pp["part"]
				var g: String = part["group"]
				if bool(part.get("shadow_only", false)) or (he["hidden"] as Dictionary).has(g):
					continue
				# The drawn transform, with the group extra (cutaway wall Y scale of a scaled record).
				var px: Transform3D = inst._part_xf(he, part)
				var ab0: AABB = px * (part["mesh"] as Mesh).get_aabb()
				if ab0.end.y - fy <= 1.45:
					continue
				var top := -1.0
				var mesh: Mesh = part["mesh"]
				for si in mesh.get_surface_count():
					var arr: Array = mesh.surface_get_arrays(si)
					var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var uv2 = arr[Mesh.ARRAY_TEX_UV2]
					var use_mask: bool = bool(part.get("mask", false)) and uv2 is PackedVector2Array and (uv2 as PackedVector2Array).size() == vv.size() and e[0] == "room"
					for vi in vv.size():
						if use_mask:
							var sg: int = int((uv2 as PackedVector2Array)[vi].x + 0.5) - 1
							if sg >= 0 and (mask >> sg) & 1 == 1:
								continue
						var yy: float = (px * vv[vi]).y - fy
						if yy > top:
							top = yy
				if top > 1.45:
					var k2: String = "%s %s" % [e[0], g]
					var tgt: Dictionary = ok if g in CUT_ALLOWED else bad
					tgt[k2] = snappedf(maxf(float(tgt.get(k2, 0.0)), top), 0.01)
		if not out.has(key):
			out[key] = {"rooms": 0, "above_cut": {}, "allowed": {}}
		out[key]["rooms"] = int(out[key]["rooms"]) + 1
		for k3 in bad:
			out[key]["above_cut"][k3] = maxf(float(out[key]["above_cut"].get(k3, 0.0)), float(bad[k3]))
		for k4 in ok:
			out[key]["allowed"][k4] = maxf(float(out[key]["allowed"].get(k4, 0.0)), float(ok[k4]))
	return out
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
		_warm_om = om
		_warm_sp = sp
		# Models first used mid-game (a pile of bought goods, a supply pod, meteor props, a ship
		# kind not on a pad yet): drawn once, tiny, in front of the camera (V3.1 stall trace).
		_warm_handles = []
		if cam != null:
			var fwd: Vector3 = -cam.global_transform.basis.z
			var wx := Transform3D(Basis.from_scale(Vector3(0.01, 0.01, 0.01)), cam.global_position + fwd * 3.0)
			for f in ["crate_raw", "crate_material", "crate_component", "crate_medical", "crate_food", "crate", "supply_pod", "meteor_rock", "crater", "fragments", "meteor_turret",
					# V4 points of interest found mid-game (fx_explore: a satellite band finds a derelict probe, 66-133 ms)
					"satellite", "boulder_a", "rock_a", "rock_b", "rock_c", "rock_f", "ship_courier", "ship_trader",
					"poi_wreck", "poi_probe", "poi_cave", "poi_meteorites", "poi_anomaly"]:
				if Models.has_model(f):
					_warm_handles.append(inst.add(Models.prop([f], 0.5, "exterior", "logistics"), wx))
			for k in ["trader", "shuttle", "liner", "medical", "science", "courier"]:
				if Models.has_model("ship_" + k):
					var sn: Node3D = Models.node_from(Models.prop(["ship_" + k], 1.0, "exterior", "logistics"))
					add_child(sn)
					sn.global_transform = wx
					_warm_nodes.append(sn)
			# The build / blueprint hologram material (unshaded, transparent, both sides).
			var gb := MeshInstance3D.new()
			gb.mesh = BoxMesh.new()
			gb.material_override = Models.ghost_material(Color(0.35, 0.9, 1.0, 0.28))
			add_child(gb)
			gb.global_transform = Transform3D(Basis.from_scale(Vector3(0.02, 0.02, 0.02)), cam.global_position + fwd * 3.0)
			_warm_nodes.append(gb)
			fx.prewarm(cam.global_position + fwd * 3.0)
			var wdec: MeshInstance3D = decal_ring(1.0, 0.5, 16, Color(1, 1, 1, 0.01), 1)
			add_child(wdec)
			wdec.global_position = cam.global_position + fwd * 30.0
			_warm_nodes.append(wdec)
			if explore != null:
				_warm_nodes.append_array(explore.warm_nodes(wx))
			if vehicles != null:
				_warm_nodes.append_array(vehicles.warm_nodes(Transform3D(Basis.from_scale(Vector3(0.01, 0.01, 0.01)), cam.global_position - cam.global_transform.basis.z * 3.0)))
	# Hold the night until the sky is fully dark and every structure's Lights are on (at most
	# 40 frames); the flame, dust and mist warm-up of fx_traffic runs in the same frames.
	# (at least 1.3 s: the night lamp sites, helmet lamps and light pools refresh once a second)
	if _night_warm == 1 and (float(sky.night) < 0.97 or _time - _warm_t0 < 1.3 or _warm_frames < 34) and _time - _warm_t0 < 4.0:
		_night_warm = 2
	# First the sunset itself (the sun at the horizon: 108-150 ms of first-use work, UI trace),
	# then full night.
	time_override = 360.0 if _time - _warm_t0 < 0.6 else 420.0
	_warm_lights(_warm_frames)
	_warm_frames += 1
	_night_warm -= 1
	if _night_warm == 0:
		boot_info["warm_frames"] = _warm_frames
		boot_info["warm_night"] = snappedf(float(sky.night), 0.01)
		boot_info["warm_s"] = snappedf(_time - _warm_t0, 0.01)
		_cover_hold = 0.0
		time_override = _warm_restore
		_warm_restore = -2.0
		if sky.always_omni != null:
			sky.always_omni.visible = true
			sky.always_spot.visible = true
		for nd in _warm_nodes:
			if is_instance_valid(nd):
				(nd as Node).queue_free()
		_warm_nodes = []
		for hh in _warm_handles:
			inst.remove(hh)
		_warm_handles = []
## The Compatibility renderer compiles a separate program for each material under each light
## mix: base pass, omni only, spot only, both, and the additive passes of shadowed lights. The
## warm-up lights change mix every frame so a rover driving under a base lamp, or a structure a
## head light first reaches, finds its programs ready (showcase_v4 WebGL trace 2026-09-28: 22
## program links at 30-290 ms each in the first 2 minutes).
var _warm_om: OmniLight3D = null
var _warm_sp: SpotLight3D = null
func _warm_lights(f: int) -> void:
	if not is_instance_valid(_warm_om) or not is_instance_valid(_warm_sp):
		return
	# 0 both, 1 omni, 2 spot, 3 shadowed omni, 4 shadowed spot, 5 both + omni shadow,
	# 6 both + spot shadow, 7 none
	# (fx_sky's always-on omni and spot put every object in the "both" mix; no shadowed omni or
	# spot exists in the game, so the other mixes are not warmed any more)
	var ph: int = 0
	var om_on: bool = ph in [0, 1, 3, 5, 6]
	var sp_on: bool = ph in [0, 2, 4, 5, 6]
	_warm_om.visible = true
	_warm_sp.visible = true
	_warm_om.light_energy = 1.0 if om_on else 0.0
	_warm_om.omni_range = 600.0 if om_on else 0.001
	_warm_sp.light_energy = 1.0 if sp_on else 0.0
	_warm_sp.spot_range = 600.0 if sp_on else 0.001
	_warm_om.shadow_enabled = ph == 3 or ph == 5
	_warm_sp.shadow_enabled = ph == 4 or ph == 6
	# The first-deposit stall (1 run in 3: a ground decal drawn with the omni only, 67-100 ms):
	# for the last 12 warm-up frames fx_sky's always-on spot and omni take turns off, so the
	# omni-only, spot-only and no-light programs of everything in view are made under the cover.
	if sky.always_omni != null and sky.always_spot != null:
		var q: int = ((f - 20) / 3) % 4 if f >= 20 and f < 32 else 0
		sky.always_omni.visible = q != 2 and q != 3
		sky.always_spot.visible = q != 1 and q != 3

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

## The planet's look (Paul 2026-10-01, V5 15.7: terrain, rocks, sky, light, fog and weather follow the
## planet option). Applied when the loaded planet changes; airless has no storm, dust or wind effects.
var _planet_seen := ""
func _planet_check() -> void:
	var pl: String = String(sim.state.get("planet", "dry"))
	if pl == _planet_seen:
		return
	_planet_seen = pl
	sky.planet_name = pl
	if terrain != null and terrain.has_method("apply_planet"):
		terrain.apply_planet(pl)
	if fx != null and fx.get("particles") != null:
		fx.particles.planet = pl
	elif fx != null and "planet" in fx:
		fx.planet = pl

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
		"building": return "inst" if String(b["def"]) == "super_dome" else "node:building"
		"broken": return "node:broken"
	return "inst"

func _template(b: Dictionary) -> Dictionary:
	var def: Dictionary = sim.bdef(b["def"])
	if b["kind"] == "link":
		return Models.prop([String(b["def"])], 1.2, "room", "logistics")
	var size: int = int(b.get("size", 1)) if def.has("sizes") else -1
	if String(b["def"]) == "super_dome" and Models.has_model("dome_shell"):
		# The finished dome is the merged template (119 surfaces, not 460: V5 §0 draw calls).
		return Models.dome_template(_dome_stage(b) >= 9.0)
	# Old-save airlocks (record radius 2.8 m, before the 3.4 m airlock): ART-HAB's own R 2.8
	# model, unscaled (ART-HAB F0; never airlock_m scaled down).
	if String(b["def"]) == "airlock" and float(b["radius"]) < 3.0 and Models.has_model("airlock_r28"):
		return Models.status_tinted(Models.building("airlock_r28", -1, float(b["radius"]), float(b["radius"]), b["kind"], def.get("category", "logistics")))
	var s_r: float = -1.0
	# V4 (ART-HAB 2026-09-27, V1): every room model except the airlock and the junction is built at
	# 1.5 x the content radius (content keeps the v3 numbers; SIM scales rooms on v4 maps). The
	# model is drawn at record radius / its own radius, so old saves and v4 maps are both right.
	var mk: float = ROOM_MODEL_SCALE if (String(b["kind"]) == "room" and not (String(b["def"]) in ["airlock", "junction"])) else 1.0
	if size >= 0 and (def["sizes"] as Dictionary).has("radius"):
		var ra: Array = def["sizes"]["radius"]
		s_r = float(ra[clampi(size, 0, ra.size() - 1)]) * mk
	var m_r: float = float(def.get("radius", b["radius"])) * mk
	# Model files whose built radius is not the content radius (ART-HAB 4.0 rebuilt the airlock at
	# 5.1 / 6.0 m and the junction at 3.75 m; content keeps 3.4 / 4.0 and 2.5): draw them at the
	# record radius from their real size.
	var mr: Dictionary = MODEL_RADIUS.get(String(b["def"]), {})
	if not mr.is_empty() and not _model_is_big(String(b["def"]), size):
		mr = {}   # (ART-HAB is rebuilding them at the content radius: then no override)
	if not mr.is_empty():
		if mr.has(size):
			s_r = float(mr[size])
		if mr.has(-1):
			m_r = float(mr[-1])
	# V5 (ART-HAB 2026-09-29): variant files <id>_<variant>_<size>.glb (residence tube executive), else <id>_<size>.
	var model_id: String = String(b["def"])
	var variant: String = String(b.get("variant", ""))
	if variant != "" and size >= 0 and size < Models.SIZE_SUFFIX.size() and Models.has_model("%s_%s_%s" % [model_id, variant, Models.SIZE_SUFFIX[size]]):
		model_id = "%s_%s" % [model_id, variant]
	var tb: Dictionary = Models.building(model_id, size, float(b["radius"]), m_r, b["kind"], def.get("category", "logistics"), s_r)
	if mr.has(-1) and size < 0 and absf(float(b["radius"]) - m_r) > 0.05:
		tb = Models._with_scale(tb, float(b["radius"]) / m_r)
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
var _nodelog: Array = []
func _on_node_added(n: Node) -> void:
	if _nodelog.size() < 400:
		_nodelog.append("%.1f %s %s<%s" % [Time.get_ticks_msec() / 1000.0, n.get_class(), String(n.name).left(24), String(n.get_parent().name).left(20) if n.get_parent() != null else ""])
var _skip := {}             # measurement only (__fhr "skip <module>"): modules not synced
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
	_roof_inside(tpl)
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
		if gs.ends_with("Top") or gs.ends_with("Status") or gs.begins_with("PressureLight") or gs == "Beacon" or gs == "DecalR" or gs == "WallsUp":
			inst.set_hidden(hnd, gs, o > 0.0)
		elif gs.begins_with("DecalL"):
			inst.set_hidden(hnd, gs, o > 0.0 or lvl < int(gs.substr(6)))
	if not bool(meta["glass_roof"]):
		# (closed roof: the interior is not drawn, unless the follow camera is in or next to the room)
		var shut: bool = o <= 0.0 and not bool(meta.get("show_in", false))
		inst.set_hidden(hnd, "Interior", shut)
		inst.set_hidden(hnd, "Tall", shut)
		inst.set_hidden(hnd, "WallsIn", shut)
	# Coordinator 2026-09-26: a record drawn larger than its model (old-save radius, uniform
	# scale s > 1) would carry the cut up to 1.40 * s. In the cutaway the wall groups get Y scale
	# 1/s, so the cut stays at 1.40 m in world space. Floors, doors and walk grids keep scale s.
	var s: float = float(meta["tpl"].get("scale", 1.0))
	if room and s > 1.001:
		for g in ["Walls", "WallsIn"]:
			if o > 0.0:
				inst.set_extra(hnd, g, Transform3D(Basis.from_scale(Vector3(1.0, 1.0 / s, 1.0)), Vector3.ZERO))
			else:
				inst.clear_extra(hnd, g)

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
			var want: float = 1.0 if (near or _force_open_all or roofs_off or (selected_kind == "building" and selected_id == id)) else 0.0
			# Paul 2026-10-01 (V5 §15.5): in the over-the-shoulder view every roof and upper wall stays ON
			# (an enclosed feel); the rooms round the person and the camera draw their interior under it.
			# The "all roofs off" toggle does not apply there.
			if follow_id >= 0:
				want = 0.0
			var show_in: bool = follow_id >= 0 and _follow_open.has(id)
			if show_in != bool(meta.get("show_in", false)):
				meta["show_in"] = show_in
				_apply_roof(b, meta)
			# 4.0 exteriors whose roof is part of the silhouette (depot hangar, reactor, plants, pad):
			# never cut away (UI shot 2026-09-27: the depot read as a plain box without it).
			if String(b["def"]) in NO_CUTAWAY:
				want = 0.0
			var o: float = float(meta["open"])
			if o != want:
				meta["open"] = move_toward(o, want, delta * 3.5)
				_apply_roof(b, meta)
		if String(b["def"]) == "super_dome":
			_dome_update(b, meta, delta)
		elif bool(meta["tpl"].get("has_floors", false)):
			_floors_update(b, meta)
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
	"suit_range": 7, "off": 8, "building": 9, "unreachable": 7, "full": 4, "no_reservoir": 1, "demolish": 11, "alert": 10, "wear": 3}
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
		"output_blocked": return {"code": "output_blocked", "text": "FULL", "color": Color("ffb547")}
		"deposit_empty": return {"code": "deposit_empty"}
	if b["kind"] == "room" and not sim.util.building_supplied(b["id"]):
		return {"code": "no_air"}
	if bool(b.get("breach", false)):
		return {"code": "no_air", "text": "HULL BREACH"}
	# Storage full (Paul 2026-09-28): a FULL tag, as WORN and BROKEN.
	if _stock_full(b):
		return {"code": "full", "text": "FULL", "color": Color("ffb547")}
	# Worn machines above the forecast share of their failure threshold (V3 §4.3).
	var w2: Dictionary = _wear_of(int(b["id"]))
	if not w2.is_empty() and float(w2.get("fail_at", 100.0)) > 0.0 and float(w2.get("w", 0.0)) >= float(w2.get("fail_at", 100.0)) * 0.75:
		return {"code": "wear", "text": "WORN %d%%" % int(round(100.0 * float(w2["w"]) / float(w2["fail_at"]))), "color": Color("ffb547")}
	return {}

const FAULT_COLOR := {"mechanical": Color("ff9f1c"), "electrical": Color("3ee0ff"), "seal": Color("a78bfa")}

## Share of a storage structure's store in use, 0..1 (-1 = not a store). SIM's contents(b)
## (SIM-to-UI.md: capacity, used, full), only for structures whose inv_out is a store (contents
## scans every inventory, so it is not called for other structures). Cached 1 s per structure.
var _fill_cache := {}
func _stock_fill(b: Dictionary) -> float:
	var iid: int = int(b.get("inv_out", -1))
	if iid < 0 or String(sim.inv.get_inv(iid).get("role", "")) != "store":
		return -1.0
	var c = _fill_cache.get(int(b["id"]))
	if c != null and _time - float(c[1]) < 1.0:
		return float(c[0])
	var f := -1.0
	var ct: Dictionary = sim.inventory.contents(b) if sim.get("inventory") != null else {}
	if not ct.is_empty() and int(ct.get("capacity", 0)) > 0:
		f = 1.0 if bool(ct.get("full", false)) else clampf(float(ct["used"]) / float(ct["capacity"]), 0.0, 1.0)
	_fill_cache[int(b["id"])] = [f, _time, bool(ct.get("full", false))]
	return f

## SIM's own full flag (contents(b).full), the rule the panels use.
func _stock_full(b: Dictionary) -> bool:
	if _stock_fill(b) < 0.0:
		return false
	var c = _fill_cache.get(int(b["id"]))
	return c != null and (c as Array).size() > 2 and bool(c[2])
## The racks' crates of every storage room follow its fill level (models.gd "Stock" group).
func _sync_stock() -> void:
	for id in bmeta:
		var meta: Dictionary = bmeta[id]
		if not (meta.get("tpl", {}).get("groups", {}) as Dictionary).has("Stock"):
			continue
		var b: Dictionary = sim.state["buildings"].get(id, {})
		var f: float = maxf(_stock_fill(b), 0.0) if not b.is_empty() else 0.0
		if b.get("state", "") != "active":
			f = 0.0
		if absf(float(meta.get("stock_f", -1.0)) - f) > 0.004:
			meta["stock_f"] = f
			inst.set_group_custom(int(meta["h"]), "Stock", Color(f, 0, 0, 1))
	stats_stock = {}

var stats_stock := {}

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
		# (a flat roof drew as a solid cyan slab on the 4.0 exteriors: their outline is the Base)
		if not body_part or g in ["Rotor"] or (open and (g == "Roof" or (g.length() == 2 and g[0] == "L" and b["kind"] == "room"))) or (g == "Roof" and String(b["def"]) in NO_CUTAWAY):
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
	# V4 map layers (UI buttons: radiation, sun, resources; explored with the fog).
	var lay_ok: bool = terrain.set_layer(name if name in ["radiation", "sun", "resources", "explored"] else "")
	if name in ["radiation", "sun", "resources", "explored"] and not lay_ok:
		_log_once("layer_" + name, "RENDER: map layer %s needs SIM data that this map does not have" % name)

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
	if gn > 1100:
		# V4: the 2,560 m planet; the whole map fits at about 1,400 m.
		r.max_distance = 1400.0
		if r.camera != null:
			r.camera.far = 5200.0

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
		"vdemo":
			# Vehicles demo (view-side until SIM's vehicles exist): x z of the group centre.
			demo_rate = 1.0
			var cx: float = float(w[1]) if w.size() > 2 else float(sim.world.center.x) + 30.0
			var cz: float = float(w[2]) if w.size() > 2 else float(sim.world.center.y) + 10.0
			var out := []
			for e in [["rover_small", Vector2(0, 0), 0.3], ["rover_medium", Vector2(0, 16), 0.0], ["hopper", Vector2(22, -6), 0.8], ["launch_pad", Vector2(-40, 30), 0.0], ["satellite", Vector2(0, 0), 0.0]]:
				var p: Vector2 = Vector2(cx, cz) + e[1]
				out.append(vehicles.add(e[0], Transform3D(Basis(Vector3.UP, e[2]), Vector3(p.x, h(p.x, p.y), p.y))))
			return "vehicles %s" % str(out)
		"vdrive":
			return str(vehicles.drive_to(int(w[1]), Vector2(float(w[2]), float(w[3]))))
		"vhop":
			vehicles.hop_to(int(w[1]), Vector2(float(w[2]), float(w[3])))
		"vboard":
			vehicles.board(int(w[1]), int(w[2]))
		"valight":
			vehicles.alight(int(w[1]))
		"vlaunch":
			vehicles.launch(int(w[1]))
		"camrange":
			var rc = rig()
			return "none" if rc == null else "distance %.0f target %.0f max %.0f far %.0f" % [rc.distance, rc.target_distance, rc.max_distance, rc.camera.far]
		"reactor":
			reactor.set_stage(int(w[1]), w[2] if w.size() > 2 else "")
		"simlog":
			# simlog [n]: the last n SIM log entries as "g<second> code" (matching frame spikes to events)
			var lg: Array = sim.state.get("log", [])
			var out := []
			for i in range(maxi(0, lg.size() - (int(w[1]) if w.size() > 1 else 20)), lg.size()):
				out.append("g%d %s" % [int(lg[i]["tick"]) / int(sim.bal["tick_hz"]), String(lg[i]["code"])])
			return JSON.stringify(out)
		"skip":
			# Measurement only: skip <module> [0]: that view module does not sync (frame-spike bisect).
			if w.size() > 2 and w[2] == "0":
				_skip.erase(w[1])
			elif w.size() > 1:
				_skip[w[1]] = true
			return str(_skip.keys())
		"lights":
			# Measurement only: every omni and spot light in the tree (shadowed first).
			var out := []
			for l in get_tree().root.find_children("*", "Light3D", true, false):
				if l is DirectionalLight3D:
					continue
				var lr: float = (l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
				out.append("%s sh%d vis%d e%.3f r%.1f y%.0f %s<%s" % ["O" if l is OmniLight3D else "S", int((l as Light3D).shadow_enabled), int((l as Node3D).is_visible_in_tree()), (l as Light3D).light_energy, lr, (l as Node3D).global_position.y, String(l.name).left(16), String(l.get_parent().name).left(16)])
			out.sort()
			return "%d %s" % [out.size(), str(out.slice(0, 60))]
		"nodelog":
			# Measurement only: nodelog on|get: every node added to the tree, with the time (s) and parent.
			if w.size() > 1 and w[1] == "on":
				_nodelog = []
				if not get_tree().node_added.is_connected(_on_node_added):
					get_tree().node_added.connect(_on_node_added)
				return "on"
			return JSON.stringify(_nodelog)
		"vtest":
			if w.size() > 2 and w[2] == "1":
				vehicles.test_off.erase(w[1])
			elif w.size() > 1:
				vehicles.test_off[w[1]] = true
			return str(vehicles.test_off.keys())
		"vspots":
			vehicles.spots_on = not (w.size() > 1 and w[1] == "0")
		"follow":
			# follow <agent id|next|off>: the V5 over-the-shoulder view (UI binds the keys).
			if w.size() < 2 or w[1] == "off":
				follow_stop()
				return "off"
			if w[1] == "next":
				return str(follow_next())
			if w[1] == "talk":
				# the speaker of a SIM talk going on now (evidence: bubbles from SIM's data)
				var soc = sim.get("social")
				if soc != null:
					for tk in soc.talks():
						if agent_world_pos(int(tk["speaker"])) != null and follow_start(int(tk["speaker"])):
							return str(int(tk["speaker"]))
				return "none"
			if w[1] == "near":
				# the living person nearest to x z (follow near <x> <z>)
				var q := Vector2(float(w[2]), float(w[3]))
				var best := -1
				var bd := 1e9
				for aid in sim.state["agents"]:
					var ag: Dictionary = sim.state["agents"][aid]
					if ag["state"] == "alive" and (ag["pos"] as Vector2).distance_to(q) < bd and agent_world_pos(int(aid)) != null:
						bd = (ag["pos"] as Vector2).distance_to(q)
						best = int(aid)
				return str(best) if follow_start(best) else "none"
			return "ok" if follow_start(int(w[1])) else "not found"
		"shoulder":
			# shoulder <dist 1.2-4> <orbit deg> <side 1|-1> [pitch deg]: the follow camera by command.
			var rs = rig()
			if rs == null:
				return "no rig"
			# shoulder <dist 0.5-8> <orbit deg> <side 1|-1> [tilt deg] [look yaw deg] [look pitch deg] | shoulder return
			if w.size() > 1 and w[1] == "return":
				rs.shoulder_return()
				return "return"
			rs.sh_side = (1.0 if float(w[3]) >= 0.0 else -1.0) if w.size() > 3 else rs.sh_side
			rs.set_shot(float(w[1]) if w.size() > 1 else rs.sh_dist, deg_to_rad(float(w[2])) if w.size() > 2 else rs.sh_orbit,
				deg_to_rad(float(w[4])) if w.size() > 4 else rs.sh_pitch, deg_to_rad(float(w[5])) if w.size() > 5 else rs.sh_look_yaw,
				deg_to_rad(float(w[6])) if w.size() > 6 else rs.sh_look_pitch)
			return "d %.2f orbit %.0f side %d" % [rs.sh_dist, rad_to_deg(rs.sh_orbit), int(rs.sh_side)]
		"bubbles":
			# bubbles stub|sim: evidence staging only (RENDER stub lines) or SIM's talks (default).
			bubbles.force_stub = w.size() > 1 and w[1] == "stub"
			return "stub" if bubbles.force_stub else "sim"
		"anchor":
			# anchor <name part>: world positions of matching anchors of any structure (evidence camera aim).
			var out_a := []
			for bid2 in bmeta:
				for an in (bmeta[bid2].get("anchors", {}) as Dictionary):
					if String(an).contains(w[1]):
						var ap: Vector3 = (bmeta[bid2]["anchors"][an] as Transform3D).origin
						out_a.append([an, snappedf(ap.x, 0.1), snappedf(ap.y, 0.1), snappedf(ap.z, 0.1)])
			return JSON.stringify(out_a.slice(0, 12))
		"viewanchor":
			# viewanchor <name part> [floor]: the over-the-shoulder camera on a structure's anchor (a stand
			# point: the arcade player, a bar stool), facing along the anchor's +X. Evidence camera.
			for bid3 in bmeta:
				for an2 in (bmeta[bid3].get("anchors", {}) as Dictionary):
					if String(an2).contains(w[1]):
						var ax: Transform3D = bmeta[bid3]["anchors"][an2]
						var fx: Vector3 = ax.basis.x.normalized()
						var ay: float = atan2(-fx.z, fx.x)
						if w.size() > 2:
							set_view_floor(int(bid3), int(w[2]))
						var rr = rig()
						if rr != null:
							rr.shoulder_start(func(): return [ax.origin, ay, 1.65, true])
							rr.collide_fn = Callable()
							rr.ceil_fn = Callable()
						return "%s at %s" % [an2, str(ax.origin.snapped(Vector3.ONE * 0.1))]
			return "not found"
		"viewfloor":
			# viewfloor <building id> <floor 1..5 | 0 = off>: the floor cutaway (UI's floor selector calls set_view_floor)
			set_view_floor(int(w[1]), int(w[2]))
			return str(dome_view_floor)
		"ragphoto":
			# ragphoto <id,id> <place> <pose>: queue a tabloid photo; photoshow: show every photo made on screen.
			var ids_p: Array = Array(w[1].split(",", false)).map(func(x): return int(x)) if w.size() > 1 else []
			photos.photo(ids_p, w[2] if w.size() > 2 else "default", w[3] if w.size() > 3 else "idle")
			return "queued %d" % photos._queue.size()
		"photoshow":
			var cl = get_node_or_null("PhotoShow")
			if cl != null:
				cl.queue_free()
				if w.size() > 1 and w[1] == "off":
					return "off"
			var layer2 := CanvasLayer.new()
			layer2.name = "PhotoShow"
			layer2.layer = 90
			add_child(layer2)
			var gx := 0
			for k in photos.cache:
				var tr := TextureRect.new()
				tr.texture = photos.cache[k]
				tr.position = Vector2(20 + (gx % 3) * 524, 20 + (gx / 3) * 396)
				tr.size = Vector2(512, 384)
				layer2.add_child(tr)
				var lb := Label.new()
				lb.text = String(k)
				lb.position = tr.position + Vector2(6, 386 - 24)
				lb.add_theme_color_override("font_color", Color(1, 1, 0.6))
				layer2.add_child(lb)
				gx += 1
			return "%d photos, %s" % [photos.cache.size(), str(photos.stats)]
		"roofs":
			# roofs off|on: Paul's all-roofs-off toggle (set_roofs_off).
			set_roofs_off(w.size() > 1 and w[1] == "off")
			return "roofs off" if roofs_off else "roofs on"
		"fprobe":
			# fprobe start <secs> [in|out|any|keep] | get | csv | stop: follow-view smoothness probe (measurement).
			var rp = rig()
			if rp == null:
				return "no rig"
			if fprobe == null:
				fprobe = load("res://presentation/fx_follow_probe.gd").new(self)
			var sub: String = w[1] if w.size() > 1 else "get"
			if sub == "start":
				rp.probe_fn = fprobe.record
				return fprobe.start(float(w[2]) if w.size() > 2 else 20.0, w[3] if w.size() > 3 else "any")
			if sub == "stop":
				fprobe.on = false
				rp.probe_fn = Callable()
				return "stopped"
			if sub == "csv":
				return fprobe.csv()
			if sub == "walker":
				return str(fprobe.pick_walker(w[2] if w.size() > 2 else "any", -1))
			var rep: Dictionary = fprobe.report()
			rep["running"] = fprobe.on
			return JSON.stringify(rep)
		"followinfo":
			var rf = rig()
			var fp = agent_world_pos(follow_id) if follow_id >= 0 else null
			return JSON.stringify({"id": follow_id, "name": String(sim.state["agents"].get(follow_id, {}).get("name", "")), "where": String(sim.state["agents"].get(follow_id, {}).get("where", "")),
				"cam": str(rf.camera.global_position.snapped(Vector3.ONE * 0.01)) if rf != null else "", "body": str(fp.snapped(Vector3.ONE * 0.01)) if fp != null else "",
				"cam_body_m": snappedf(rf.camera.global_position.distance_to(fp), 0.01) if (rf != null and fp != null) else -1, "open": _follow_open.keys().size(), "bubbles": bubbles.stats,
				"in": (_follow_circles(fp, 0.0).map(func(c): return String(sim.state["buildings"][c[0]]["def"]) + ("/open" if float(bmeta[c[0]].get("open", 0.0)) > 0.5 else "")) if fp != null else []),
				"cam_in": (_follow_circles(rf.camera.global_position, 0.0).map(func(c): return String(sim.state["buildings"][c[0]]["def"]) + ("/open" if float(bmeta[c[0]].get("open", 0.0)) > 0.5 else "")) if rf != null else []),
				"clip": String(npc.agents[follow_id]["sm"].cur) if (npc != null and npc.agents.has(follow_id)) else ""})
		"launchtest":
			return explore.test_launch(int(w[1]))
		"v4state":
			var o := {"pois": explore.stats, "reactor": reactor.stats, "vehicles": vehicles.stats, "fog_rev": terrain.fog_rev, "fog_ms": terrain.fog_ms, "fog_n": terrain.fog_n, "worst_ms": _worst_ms}
			var rx = sim.get("reactors")
			if rx != null:
				o["reactors"] = (rx.list() as Array).map(func(r): return [r["id"], r["stage"], r["pos"]])
				o["zones"] = (rx.zones() as Array).map(func(z): return [z["kind"], int(z["x"]), int(z["y"]), z["r"]])
			var ex = sim.get("explore")
			if ex != null and ex.active():
				o["pois_found"] = (ex.pois() as Array).filter(func(p): return p["found"]).map(func(p): return [p["id"], p["kind"], int(p["x"]), int(p["y"]), p["visited"]])
				o["sats"] = ex.sats()
				var sx := []
				for e in explore.sats.values():
					var sp: Vector3 = (e["node"] as Node3D).global_position
					sx.append([roundi(sp.x), roundi(sp.y), roundi(sp.z)])
				o["sat_xyz"] = sx
			var pads := []
			for bid in sim.state["buildings"]:
				if String(sim.state["buildings"][bid]["def"]) in ["launch_pad", "fission_reactor", "rover_depot", "outpost_core", "comms_tower", "chemical_plant", "crystal_refinery"]:
					pads.append([bid, sim.state["buildings"][bid]["def"], sim.state["buildings"][bid]["pos"]])
			o["key_buildings"] = pads
			var rcam = rig()
			if rcam != null:
				var cp: Vector3 = rcam.camera.global_position
				o["cam"] = [roundi(cp.x), roundi(cp.y), roundi(cp.z)]
			return JSON.stringify(o)
		"rxdemo":
			# Evidence until SIM's meltdown exists: a fission reactor model at x z, then stages.
			if w.size() > 3:
				reactor.stage_at(-7, Vector2(float(w[1]), float(w[2])), 12.0, w[3])
				if w[3] == "breach" and _rx_h >= 0:
					inst.remove(_rx_h)
					_rx_h = -1
				return "stage %s" % w[3]
			var pr := Vector2(float(w[1]), float(w[2]))
			var tr: Dictionary = Models.building("fission_reactor", -1, 12.0, 12.0, "exterior", "utilities")
			_rx_h = inst.add(tr, Transform3D(Basis(), Vector3(pr.x, h(pr.x, pr.y), pr.y)))
			reactor.stage_at(-7, pr, 12.0, "")
			return "reactor at %s" % str(pr)
		"radzone":
			reactor.add_zone("dbg%d" % reactor.zones.size(), Vector2(float(w[1]), float(w[2])), float(w[3]) if w.size() > 3 else 60.0)
		"base":
			return jump_base(-2 if (w.size() < 2 or w[1] == "next") else int(w[1]))
		"layer":
			set_overlay(w[1] if w.size() > 1 else "")
			return "layer %s" % terrain.layer
		"fogtest":
			# Evidence only until SIM publishes explored cells: explored = 450 m round the start
			# plus a 60 m band along a line to (x, z).
			var cell := 8.0
			var nf: int = int(ceil(float(sim.world.size) / cell)) + 1
			var img := Image.create(nf, nf, false, Image.FORMAT_R8)
			var c0: Vector2 = sim.world.center
			var tgt := Vector2(float(w[1]), float(w[2])) if w.size() > 2 else c0 + Vector2(700, 300)
			for j in nf:
				for i in nf:
					var p := Vector2(i, j) * cell
					var d0: float = p.distance_to(c0) - 450.0
					var d1: float = p.distance_to(Geometry2D.get_closest_point_to_segment(p, c0, tgt)) - 60.0
					img.set_pixel(i, j, Color(clampf(1.0 - minf(d0, d1) / 30.0, 0.0, 1.0), 0, 0))
			terrain.fog_debug = terrain._map_tex(img, cell * (nf - 1))
			return "fog %s" % str(terrain.set_fog(true))
		"vinfo":
			return JSON.stringify(vehicles.info())
		"vfollow":
			var rf = rig()
			var vid: int = int(w[1])
			if rf != null and not vehicles.vehicles.has(vid):
				rf.follow_fn = Callable()
			if rf != null and vehicles.vehicles.has(vid):
				var vn: Node3D = vehicles.vehicles[vid]["node"]
				var lift: float = float(w[2]) if w.size() > 2 else 0.0
				rf.follow_fn = func(): return vn.global_position + Vector3(0, lift, 0) if is_instance_valid(vn) else null
		"vclear":
			vehicles.clear()
			demo_rate = 0.0
		"v4stage":
			return _v4_stage(int(w[1]) if w.size() > 1 else 0)
		"v4scale":
			return _v4_scale_cue(int(w[1]) if w.size() > 1 else 0)
		"v4hz":
			return v4.compare(float(w[1]), float(w[2])) if v4 != null else "not a v4 map"
		"v4info":
			if v4 == null:
				return "not a v4 map"
			var wv = sim.world
			return JSON.stringify({"v4": v4.timings, "terrain": terrain.timings, "sun": sky.sun_now, "key": v4_key, "dark": v4_dark,
				"deep_craters": (wv.deep_craters as Array).map(func(c): return [snappedf(float(c["x"]), 1), snappedf(float(c["y"]), 1), snappedf(float(c["r"]), 1), snappedf(float(c["depth"]), 1)]),
				"plateaus": (wv.plateaus as Array).map(func(c): return [snappedf(float(c["x"]), 1), snappedf(float(c["y"]), 1), snappedf(float(c["r"]), 1), snappedf(float(c["h"]), 1)]),
				"mountains": (wv.mountains as Array).map(func(c): return [snappedf((c["peak"] as Vector2).x, 1), snappedf((c["peak"] as Vector2).y, 1), snappedf(float(c["height"]), 1)]),
				"crevices": (wv.crevices as Array).map(func(c): return [snappedf((c["pts"][0] as Vector2).x, 1), snappedf((c["pts"][0] as Vector2).y, 1), snappedf(float(c["w"]), 0.1), snappedf(float(c["d"]), 1)]),
				"boulder_fields": (wv.boulder_fields as Array).map(func(c): return [snappedf(float(c["x"]), 1), snappedf(float(c["y"]), 1), snappedf(float(c["r"]), 1)])})
		"cutcheck":
			# cutcheck open: every room's cutaway opens (test staging). cutcheck: per room type, every
			# drawn vertex (room, its doorway kits, its wall patches) above 1.45 m, by group; groups
			# meant to stand are listed apart (Paul, 2026-09-26).
			if w.size() > 1 and w[1] == "open":
				_force_open_all = true
				return "ok"
			if w.size() > 1 and w[1] == "off":
				_force_open_all = false
				return "ok"
			return JSON.stringify(_cut_check())
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
				"dust": fx.field_on = on
				"terrain": terrain.mesh_inst.visible = on
				"npc": npc.visible = on
				"npcshadow":
					for c in npc.get_children():
						if c is MultiMeshInstance3D and String(c.name).begins_with("Astronauts_p_"):
							(c as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				"crevices":
					var cn = terrain.mesh_inst.get_node_or_null("Crevices")
					if cn != null:
						cn.visible = on
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

# ---------------------------------------------------------------- V4 terrain light
## V4 maps (sim.world.version >= 4): the sim's sun, the horizon shadows (terrain_v4), a camera
## range for the 2,560 m planet, depth haze that never covers the focus.
func _setup_v4() -> void:
	v4 = null
	if int(sim.world.get("version")) < 4:
		return
	v4 = TerrainV4.new()
	v4.name = "TerrainV4"
	add_child(v4)
	v4.setup(sim)
	sky.sun_fn = Callable(v4, "sun_now")
	sky.fog_far = true

## The key light and the horizon (V4 1.1). The terrain shader applies the horizon per pixel.
## Objects: the key light is dimmed by SIM's sun visibility at the camera focus and the ambient by
## the sky openness there, faded out as the camera rises (at overview distance the terrain carries
## the shadow); the terrain shader undoes both for itself (key_comp, amb_comp). In a shadowed
## crater the base lamps and windows burn as at night.
var v4_key := 1.0
var v4_dark := 0.0
func _v4_light(focus: Vector3) -> void:
	if v4 == null or not v4.active:
		return
	var sun: Dictionary = sky.sun_now
	if sun.is_empty():
		return
	var vis: float = v4.sun_vis(focus.x, focus.z, sun) if sky.key_is_sun else 1.0
	var fade: float = smoothstep(90.0, 320.0, camera_distance)
	v4_key = maxf(0.06, lerpf(vis, 1.0, fade))
	sky.key.light_energy = maxf(sky.key.light_energy * v4_key, 0.002)
	var open: float = v4.sky_open(focus.x, focus.z)
	var amb: float = lerpf(open, 1.0, fade)
	sky.env.ambient_light_energy *= maxf(amb, 0.45)
	sky.env.ambient_light_color = (sky.env.ambient_light_color as Color).lerp(Color(0.52, 0.58, 0.72), (1.0 - amb) * 0.7)
	v4_dark = clampf((1.0 - vis) * (1.0 - sky.night), 0.0, 1.0) if sky.key_is_sun else 0.0
	sky.lamp_boost = v4_dark
	fx.field_light = lerpf(0.25, 1.0, minf(v4_key, amb))
	v4.apply_to(terrain.mat, sun, sky.key_is_sun, 1.0 / v4_key, 1.0 / maxf(amb, 0.45))
	if terrain.crevice_mat != null:
		v4.apply_to(terrain.crevice_mat, sun, sky.key_is_sun, 1.0 / v4_key, 1.0 / maxf(amb, 0.45))

## Evidence only (view-side, like `ship inspector`): a small base with bright lamps on the floor of
## a deep crater from SIM's map, and two figures by a giant boulder for scale. Nothing is written
## to sim.state.
func _v4_stage(which: int) -> String:
	if v4 == null:
		return "not a v4 map"
	var cr: Array = sim.world.deep_craters
	if cr.is_empty():
		return "no deep crater"
	var dc: Dictionary = cr[clampi(which, 0, cr.size() - 1)]
	var c := Vector2(float(dc["x"]), float(dc["y"]))
	for e in _stage:
		if e is Node:
			(e as Node).queue_free()
		else:
			inst.remove(int(e))
	_stage = []
	var plan: Array = [["habitat", Vector2(0, 0)], ["greenhouse", Vector2(19, 4)], ["workshop", Vector2(-6, 18)], ["research_lab", Vector2(-18, -6)], ["storehouse", Vector2(8, -19)]]
	for e in plan:
		var def: Dictionary = sim.bdef(e[0])
		if def.is_empty():
			continue
		var rr: float = float(def.get("radius", 4.0))
		if def.has("sizes") and (def["sizes"] as Dictionary).has("radius"):
			rr = float(def["sizes"]["radius"][1])
		var b := {"def": e[0], "kind": String(def.get("kind", "room")), "size": 1, "radius": rr}
		var p: Vector2 = c + e[1]
		_stage.append(inst.add(_template(b), Transform3D(Basis(Vector3.UP, 0.4), Vector3(p.x, h(p.x, p.y) + 0.05, p.y))))
	# Lamp pools: six warm floods on masts round the base (real lights, debug only).
	for k in 6:
		var l := OmniLight3D.new()
		var a: float = TAU * k / 6.0 + 0.3
		var lp: Vector2 = c + Vector2(cos(a), sin(a)) * 16.0
		l.position = Vector3(lp.x, h(lp.x, lp.y) + 6.0, lp.y)
		l.light_color = Color(1.0, 0.84, 0.62)
		l.light_energy = 5.0
		l.omni_range = 32.0
		l.omni_attenuation = 0.9
		add_child(l)
		_stage.append(l)
	return "staged %d on crater %d at %.0f,%.0f floor %.1f m (r %.0f, depth %.0f)" % [_stage.size(), which, c.x, c.y, h(c.x, c.y), float(dc["r"]), float(dc["depth"])]

## Two astronaut figures by the biggest boulder of a field, for scale (evidence only).
func _v4_scale_cue(field: int) -> String:
	var bf: Array = sim.world.boulder_fields
	if bf.is_empty():
		return "no boulder field"
	var f: Dictionary = bf[clampi(field, 0, bf.size() - 1)]
	var fc := Vector2(float(f["x"]), float(f["y"]))
	var best: Dictionary = {}
	for r in sim.world.rocks:
		if int(r["kind"]) != 3:
			continue
		if Vector2(float(r["x"]), float(r["y"])).distance_to(fc) > float(f["r"]) + 12.0:
			continue
		if best.is_empty() or float(r["r"]) > float(best["r"]):
			best = r
	if best.is_empty():
		return "no boulder in field"
	var bp := Vector2(float(best["x"]), float(best["y"]))
	var tpl: Dictionary = Models.prop(["astronaut_suit"], 0.4)
	for k in 2:
		var p: Vector2 = bp + Vector2(float(best["r"]) + 1.5 + k * 1.2, 0.8 * k)
		_stage.append(inst.add(tpl, Transform3D(Basis(Vector3.UP, 1.2 + k), Vector3(p.x, h(p.x, p.y), p.y))))
	return "figures by boulder r %.1f m at %.0f,%.0f" % [float(best["r"]), bp.x, bp.y]

# ---------------------------------------------------------------- multi-base camera (V4 §2)
## Fly the camera to a base (sim.bases): its structures' centre, zoomed to show them all.
## id -2 = the next base after the one nearest the camera. UI may call this from a base list,
## the Find window or a key. Returns the base name.
var _fly := {}
func jump_base(id: int) -> String:
	var bs = sim.get("bases")
	if bs == null:
		return "no bases"
	var ids: Array = bs.ids()
	if ids.is_empty():
		return "no bases"
	if id == -2:
		var here: int = bs.base_at(Vector2(_focus_now.x, _focus_now.z))
		var k: int = ids.find(here)
		id = int(ids[(k + 1) % ids.size()])
	if not (id in ids):
		return "no base %d" % id
	var pts: Array = []
	for bid in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][bid]
		if b["kind"] == "link" or bs.base_of(int(bid)) != id:
			continue
		pts.append([b["pos"] as Vector2, float(b.get("radius", 3.0))])
	var core: Dictionary = bs.core_of(id)
	if pts.is_empty() and not core.is_empty():
		pts.append([core["pos"] as Vector2, float(core.get("radius", 5.0))])
	if pts.is_empty():
		return "base %d has no structures" % id
	var c := Vector2.ZERO
	for p in pts:
		c += p[0]
	c /= float(pts.size())
	var ext := 20.0
	for p in pts:
		ext = maxf(ext, (p[0] as Vector2).distance_to(c) + float(p[1]))
	var r = rig()
	if r == null:
		return "no camera"
	_fly = {"from": r.focus, "to": Vector3(c.x, h(c.x, c.y), c.y), "d0": float(r.target_distance), "d1": clampf(ext * 2.2, 60.0, 420.0), "t": 0.0,
		"dur": clampf(Vector2(r.focus.x, r.focus.z).distance_to(c) / 900.0, 0.8, 2.2)}
	r.follow_fn = Callable()
	return "%s (%d structures)" % [bs.name_of(id), pts.size()]

func _fly_step(delta: float) -> void:
	if _fly.is_empty():
		return
	var r = rig()
	if r == null:
		_fly = {}
		return
	_fly["t"] = float(_fly["t"]) + delta
	var u: float = clampf(float(_fly["t"]) / float(_fly["dur"]), 0.0, 1.0)
	var e: float = u * u * (3.0 - 2.0 * u)
	# Rise out and back in on a long jump, so the planet reads between the bases.
	var hop: float = sin(PI * e) * clampf((_fly["from"] as Vector3).distance_to(_fly["to"]) * 0.35, 0.0, 600.0)
	r.jump_to((_fly["from"] as Vector3).lerp(_fly["to"], e))
	r.target_distance = lerpf(float(_fly["d0"]), float(_fly["d1"]), e) + hop
	if u >= 1.0:
		_fly = {}
