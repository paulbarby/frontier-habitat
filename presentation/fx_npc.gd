extends Node3D
## Astronauts (RENDER, V3_DESIGN §3 and §6).
##
## Models: assets/models/astronaut_suit.glb (outside) and astronaut_indoor.glb (inside),
## one skinned mesh each, the §3.2 skeleton and the §3.3 clips. A missing file, or a file
## without the idle and walk clips, falls back to the v2 rigid colonist (world_view draws it).
##
## Method (§3.4 lets RENDER choose): every clip frame is BAKED once into a float texture of
## bone matrices; every colonist of a variant is one instance of ONE MultiMesh, skinned in
## the vertex shader (shaders/npc_skin.gdshader). The CPU work per colonist and frame is the
## pose state machine (fx_npc_pose.gd) and 16 floats. Draw calls: one per material of each
## variant (about 6 + 6, plus shadows), whatever the number of colonists.
##
## Bodies: outside and in corridors a body follows the simulation position. When SIM sets
## agent.use (§6) the body walks from where it is (the doorway it came in by) to the
## furniture anchor through the room's Anchor_Aisle_* points, turns to the anchor, then plays
## the enter clip, the loop and, when the use ends, the exit clip. A missing anchor falls
## back to a standing ring position and is logged once.

const Pose = preload("res://presentation/fx_npc_pose.gd")
const Fixture = preload("res://presentation/fx_npc_fixture.gd")
const Models = preload("res://presentation/models.gd")
const Rng = preload("res://sim/rng.gd")
const NpcPath = preload("res://presentation/fx_npc_path.gd")
const ACCEL := 1.5               # m/s^2 (game time), V3_1 §4.1
const DECEL := 4.0               # m/s^2 (game time): the fastest slow-down before the stopping curve
const A_LAT := 4.5               # m/s^2 (game time): the most sideways acceleration on a bend (people slow down for corners; 3.0 dropped runners to a walk at every corner)
const CORNER_DEV := 0.025        # m: a small bend's rounding curve stays this close to the planned corner
const LOOK_AHEAD := 12.0         # m of path scanned for the bend speed limit
## The followed person (follow view) at 2x-4x: the speed changes at most this fast in VIEW time (m/s^2),
## so the camera that follows them does not surge (4x: 1.5 m/s^2 game = 24 m/s^2 on screen, 2026-10-02).
const FOLLOW_VIEW_ACCEL := 9.0
const TURN := 5.236              # rad/s (300 deg/s, game time)
const CARROT := 0.4              # m: look-ahead on the path (the corner rounding radius)
const FADE_GAP := 25.0           # m: a larger jump fades out and in instead of walking
const PLANS_PER_FRAME := 8
## Planning time per frame (µs): no new plan starts once it is spent (a frame-time spike guard;
## a body without a plan waits one frame).
const PLAN_BUDGET_US := 2500
var plan_budget_us := PLAN_BUDGET_US   # tests: a count-only budget (deterministic runs) with plan_budget_us = 1 << 30
const SKIN_SHADER = preload("res://shaders/npc_skin.gdshader")
const SKIN_SHADER_2S = preload("res://shaders/npc_skin_2s.gdshader")   # V5 hair cards (two-sided, alpha MASK)
## V5 people (MPFB, ART-NPC 2026-09-30): one library "p_<variant>" per people_<variant>.glb that exists.
## Indoors a person is drawn from the library of their SIM variant (sim.people.identity(a).variant);
## outside every person keeps the suit. Draw rule: Head_<v> + Hair_<v> + ONE Outfit_<id>.
const PEOPLE_MANIFEST := "res://assets/models/people_manifest.json"
## Casual clothes colours (linear after conversion), mode 5 (ClothTint), chosen per person.
const CLOTH_COLS := ["2b3a55", "7a2e35", "55603a", "3a3d42", "2f6f6a", "b08a2e", "5a6b8c", "d8d2c4"]
## Department stripes (SIM marks(a).stripe; content/people.json departments), mode 1 on people.
const STRIPES := ["amber", "blue", "green", "red", "", "gold"]
const STRIPE_COLS := ["e0902a", "3f7fd0", "4fa35a", "c8323a", "c9d3e0", "d8b54a", "c9d3e0", "c9d3e0"]

const CAM_FADE_R := 0.8         # m: another body this close to the follow camera fades out (critic round 41)
const LOD1_DIST := 12.0         # m from the camera: people_<v>_lod1.glb beyond this (ART-NPC manifest `draw`)
const FPS := 30.0
const FLOOR_Z := 0.14            # rooms_kit.py: top of the floor in every room
const FILES := {"suit": "res://assets/models/astronaut_suit.glb", "in": "res://assets/models/astronaut_indoor.glb"}
const META_FILE := "res://assets/models/astronaut_anims.json"
const LOOPS := ["idle", "idle_look", "walk", "run", "carry_walk", "carry_idle", "work_console", "work_bench", "talk",
	"repair_kneel", "sit_idle", "sit_eat", "sit_type", "sleep", "injured_walk", "dead", "drive_sit", "ride_sit"]
const ENTER_EXIT := {"sit_enter": ["stand", "sit"], "sit_exit": ["sit", "stand"], "lie_enter": ["stand", "lie"], "lie_exit": ["lie", "stand"],
	"kneel_enter": ["stand", "kneel"], "kneel_exit": ["kneel", "stand"], "collapse": ["stand", "lie"]}
const ALL_CLIPS := ["idle", "idle_look", "walk", "run", "carry_walk", "carry_idle", "work_console", "work_bench", "talk",
	"kneel_enter", "repair_kneel", "kneel_exit", "sit_enter", "sit_idle", "sit_eat", "sit_type", "sit_exit",
	"lie_enter", "sleep", "lie_exit", "injured_walk", "collapse", "dead", "cheer", "suit_swap",
	# V4 vehicle crews (ART-NPC 2026-09-27): seat loops, door clips and the step chain.
	"drive_sit", "ride_sit", "board", "board_r", "alight", "alight_r", "step_up", "step_up_r", "step_down", "step_down_r",
	# V5 people (people_manifest.json): social clips, the bar stool and a dance.
	"talk_gesture_a", "laugh", "argue", "hug", "sit_bar_stool", "dance_a"]
const VEHICLE_CLIPS := ["drive_sit", "ride_sit", "board", "board_r", "alight", "alight_r", "step_up", "step_up_r", "step_down", "step_down_r"]
const V5_CLIPS := ["talk_gesture_a", "laugh", "argue", "hug", "sit_bar_stool", "dance_a"]
## suit_swap (ART-NPC, V3_1 §5.4): the variant is cut at this clip time (frame 30 of 60).
const SWAP_CUT := 1.0
const ROLE_INDEX := {"technician": 0, "grower": 1, "operator": 2, "medic": 3, "scientist": 4}
## Buildings whose staff stand at a console (the rest work at a bench).
const CONSOLE_DEFS := ["research_lab", "electronics_fab", "medical", "bio_lab", "comms_tower", "oxygen_plant", "atmo_processor", "water_recycler", "research_assembler", "fabricator"]

static var _libs := {}          # variant -> baked library (shared by every view)

var view
var sim
var libs := {}                  # variant -> library Dictionary (ok == true)
var mm := {}                    # variant -> {mm: MultiMesh, mmi, cap, buf}
var agents := {}                # agent id -> body record
var status := {}                # variant -> "glb" | "fixture" | "missing: ..." (for stats and logs)
var use_fixture := false
var _logged := {}
var _frame := 0
var _buf_cache := {}
var npc_ms := 0.0
var game_rate := 1.0             # game seconds per real second (smoothed; 0 when paused)
var _tick_s := 0.1               # game seconds per sim tick (set in sync from bal.tick_hz)
var _follow_id := -1             # the person in the follow view (world_view.follow_id), -1 = none
var _cam_pos := Vector3.INF      # the camera (the frame before) for the follow-view near fade
var planner                     # fx_npc_path (created in setup)
var _plans_frame := 0
var _plan_us := 0
var _sep_dt := 0.016
var forced_goto := {}            # test staging only (__fhr "runto"): agent id -> [Vector2, speed m/s]
var force_cpu := false            # test only (__fhr "npccpu 1"): every near body on the CPU row path
var no_far := false               # measurement only (render_follow_headless): every body updated every frame, so the camera cannot change the walk
var forced_use := {}             # test staging only (__fhr "use"): agent id -> use (view side)
const DYN_ROWS := 128            # blended poses per frame (CPU slerp rows)
const DYN0 := 1000000            # shader row index of the first dynamic row
var _dyn_img: Image
var _dyn_tex: ImageTexture
var _dyn_buf := PackedFloat32Array()
var _dyn_w := 0
var _dyn_used := 0
# Per-body pose data (row A + fraction, row B + weight, look, carry row + weight) in a float
# texture, one texel per drawn body. The Compatibility renderer stores MultiMesh custom data
# as HALF floats: row 1000000+ (dynamic rows) overflowed and drew nothing, rows above 1024
# lost their fraction and rows above 2048 their odd numbers (found 2026-09-25). The custom
# data now carries only the body index (exact in half) and the look.
const BD_ROWS := 1024
var _bd_img: Image
var _bd_tex: ImageTexture
var _bd_buf := PackedFloat32Array()
var _bd_used := 0
var _awards_seen := -1
var _t_body := 0
var _t_write := 0
var _t_lamps := 0
var _t_walk := 0
var _n_body := 0
var _prof_frames := 0
var _why := {}
var _halo: MultiMeshInstance3D
var _halo_mat: ShaderMaterial
var _spot: MultiMeshInstance3D
var _spot_mat: ShaderMaterial
# Critic round 6: every body has its own spot.
const MIN_GAP := 0.45            # m: no two standing bodies closer than this (display positions)
const SLOT_GAP := 0.6            # m: spacing of the free standing points in a room
var _claims := {}                # "bid:kind:i" -> agent id (one body per furniture anchor)
var _room_grid := {}             # 16 m cell key -> [room ids]
var _room_n := -1
var _nb_cache := {}
var _door_cache := {}            # room id -> [{in, out, dir, link}] (from fx_doors, per rebuild)
var _door_rev := -1
const QUEUE_GAP := 0.8           # m between bodies queued in a corridor (critic round 8)              # aisle set hash -> link graph (see _aisle_route)
var stats_slots := {"claims": 0, "waiting": 0, "slotted": 0, "pushed": 0, "min_gap": 0.0, "close_pairs": 0}

# ---------------------------------------------------------------- library
func setup(v, fixture: bool = false) -> void:
	view = v
	sim = v.sim
	use_fixture = fixture
	for c in get_children():
		c.queue_free()
	mm = {}
	agents = {}
	libs = {}
	_awards_seen = -1
	_dyn_img = null
	var variants: Array = ["suit", "in"]
	if not fixture:
		for pv in people_variants():
			variants.append("p_" + pv)
		# LOD1 (ART-NPC: beyond 12 m, the same skeleton and bind, no clips: the LOD0 clips are shared)
		for pv in people_variants():
			if ResourceLoader.exists("res://assets/models/people_%s_lod1.glb" % pv):
				variants.append("p_%s_lod1" % pv)
	for variant in variants:
		var lib: Dictionary = load_lib(variant, fixture)
		status[variant] = String(lib.get("status", "missing"))
		if bool(lib.get("ok", false)):
			libs[variant] = lib
			lib["head_bone"] = (lib["names"] as Array).find("head")
			_make_mm(variant, lib)
		else:
			_log("lib_" + variant, "RENDER npc: %s falls back to the v2 rigid colonist (%s)" % [FILES.get(variant, variant), lib.get("status", "?")])
	# People carry the crate at prop.R like the astronauts (the people manifest has no carry block).
	if libs.has("suit"):
		for k in libs:
			if String(k).begins_with("p_") and libs[k].get("crate_offset") == null:
				libs[k]["crate_offset"] = libs["suit"].get("crate_offset")
	_setup_dyn()
	_make_lamps()
	planner = NpcPath.new(self)

## The dynamic-row texture (blended poses) shared by every astronaut material.
func _setup_dyn() -> void:
	if libs.is_empty():
		return
	# One dynamic row must hold the widest skeleton (people: 31 bones, astronauts: 24).
	_dyn_w = 0
	for k in libs:
		_dyn_w = maxi(_dyn_w, int(libs[k]["tex_info"]["row_w"]))
	_dyn_buf.resize(_dyn_w * DYN_ROWS * 4)
	_dyn_buf.fill(0.0)
	_dyn_img = Image.create_from_data(_dyn_w, DYN_ROWS, false, Image.FORMAT_RGBAF, _dyn_buf.to_byte_array())
	_dyn_tex = ImageTexture.create_from_image(_dyn_img)
	_bd_buf.resize(BD_ROWS * 4)
	_bd_buf.fill(-1.0)
	_bd_img = Image.create_from_data(1, BD_ROWS, false, Image.FORMAT_RGBAF, _bd_buf.to_byte_array())
	_bd_tex = ImageTexture.create_from_image(_bd_img)
	for v in libs:
		for part in libs[v]["parts"]:
			var mesh: Mesh = part["mesh"]
			for s in mesh.get_surface_count():
				var m: Material = mesh.surface_get_material(s)
				if m is ShaderMaterial:
					(m as ShaderMaterial).set_shader_parameter("dyn", _dyn_tex)
					(m as ShaderMaterial).set_shader_parameter("dyn0", DYN0)
					(m as ShaderMaterial).set_shader_parameter("bdata", _bd_tex)

func active(variant: String) -> bool:
	return libs.has(variant)

func any_active() -> bool:
	return not libs.is_empty()

## Loads (once per process) and bakes one variant. `fixture` builds the procedural test rig.
static func load_lib(variant: String, fixture: bool = false) -> Dictionary:
	var key: String = variant + (":fixture" if fixture else "")
	if _libs.has(key):
		return _libs[key]
	var root: Node = null
	var st := "glb"
	if fixture:
		root = Fixture.build("suit" if variant == "suit" else "indoor")
		st = "fixture"
	elif ResourceLoader.exists(_file_of(variant)):
		var ps = load(_file_of(variant))
		if ps is PackedScene:
			root = (ps as PackedScene).instantiate()
	if root == null:
		_libs[key] = {"ok": false, "status": "missing file"}
		return _libs[key]
	var people: bool = variant.begins_with("p_")
	var meta: Dictionary = Fixture.meta() if fixture else (_people_manifest() if people else _read_meta())
	# V3.1 visitors (ART-NPC): Vis_<kind> attachments on the same skeleton, drawn like Head_N.
	if not fixture and not people:
		_add_visitor_meshes(root, variant)
	_baking_variant = variant
	# Both variants share one skeleton and one clip set (§3.2): reuse the suit's baked clips
	# when the skeleton matches, so the indoor model costs only its mesh.
	var share = null
	if variant == "in" and _libs.has("suit" + (":fixture" if fixture else "")):
		share = _libs["suit" + (":fixture" if fixture else "")]
		if not bool(share.get("ok", false)):
			share = null
	if variant.ends_with("_lod1"):
		share = load_lib(variant.trim_suffix("_lod1"), fixture)
		if not bool(share.get("ok", false)):
			share = null
	_baking_people = people
	var lib: Dictionary = bake(root, meta, share)
	_baking_people = false
	lib["people"] = people
	if people and bool(lib.get("ok", false)):
		lib["pvariant"] = variant.substr(2).trim_suffix("_lod1")
		lib["lod1"] = variant.ends_with("_lod1")
		# UniformBase colour per outfit (mode 6), indexed by the outfit's idx.
		var ub := PackedColorArray()
		ub.resize(16)
		ub.fill(Color(1, 1, 1))
		var ot: Dictionary = outfit_table(lib)
		for oid in ot:
			ub[int(ot[oid]["idx"])] = ot[oid]["base"]
		for p in lib["parts"]:
			var pm: Mesh = p["mesh"]
			for s in pm.get_surface_count():
				var sm2 = pm.surface_get_material(s)
				if sm2 is ShaderMaterial:
					(sm2 as ShaderMaterial).set_shader_parameter("ubase_cols", ub)
	lib["crate_offset"] = _crate_offset(meta)
	lib["status"] = st if bool(lib.get("ok", false)) else String(lib.get("status", "bake failed"))
	root.free()
	_libs[key] = lib
	return lib

## ART-NPC round 3: the crate hangs from prop.R by a fixed local transform (bone space;
## basis_x/y/z are columns, origin = crate bottom centre). null when the file has none.
static func _crate_offset(meta: Dictionary):
	var c = meta.get("carry", {})
	if not (c is Dictionary) or not (c as Dictionary).has("prop_R_offset"):
		return null
	var o: Dictionary = c["prop_R_offset"]
	var v := func(a) -> Vector3: return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Transform3D(Basis(v.call(o["basis_x"]), v.call(o["basis_y"]), v.call(o["basis_z"])), v.call(o["origin"]))

const VIS_FILES := {"suit": "res://assets/models/astronaut_visitor_suit.glb", "in": "res://assets/models/astronaut_visitor_indoor.glb"}
const VIS_KINDS := ["trader", "tourist", "medical", "science", "inspector"]
## Look index v (ART-NPC visitors.looks) -> attachment kind index.
const VIS_LOOK_KIND := [0, 1, 1, 1, 2, 3, 4]
## The clips baked for a people library: the v3 set + every clip of people_manifest.json, but the mirrored
## bed-side set, the turn in bed and the vehicle seat (not drawn on people; 2026-10-02: 1,334 texture rows less).
const PEOPLE_SKIP := ["lie_enter_r", "sleep_r", "lie_exit_r", "sleep_turn", "drive_sit", "suit_swap"]
static func _people_clips(meta: Dictionary) -> Array:
	var out: Array = []
	for c in ALL_CLIPS:
		if not (c in PEOPLE_SKIP) and not (c in VEHICLE_CLIPS):
			out.append(c)
	var mc = meta.get("clips", {})
	if mc is Dictionary:
		var ks: Array = (mc as Dictionary).keys()
		ks.sort()
		for c in ks:
			if not (String(c) in out) and not (String(c) in PEOPLE_SKIP) and not (String(c) in VEHICLE_CLIPS):
				out.append(String(c))
	return out

static var _baking_variant := ""
static var _baking_people := false
static var _pman = null

static func _file_of(variant: String) -> String:
	if variant.begins_with("p_"):
		return "res://assets/models/people_%s.glb" % variant.substr(2)
	return String(FILES.get(variant, ""))

## people_manifest.json (cached); {} when it is missing.
static func _people_manifest() -> Dictionary:
	if _pman == null:
		_pman = {}
		if FileAccess.file_exists(PEOPLE_MANIFEST):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PEOPLE_MANIFEST))
			if parsed is Dictionary:
				_pman = parsed
	return _pman

## Manifest variants whose people_<v>.glb exists (pilot: m1, f1).
static func people_variants() -> Array:
	var out: Array = []
	var vs = _people_manifest().get("variants", {})
	if vs is Dictionary:
		for v in vs:
			if ResourceLoader.exists("res://assets/models/people_%s.glb" % v):
				out.append(String(v))
	return out
static var _vis_table = null

## Moves the Vis_* meshes of the visitor file under the body skeleton (same rig, verified by
## ART-NPC), so the bake treats them like the body meshes.
static func _add_visitor_meshes(root: Node, variant: String) -> void:
	var path: String = VIS_FILES.get(variant, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var ps = load(path)
	if not (ps is PackedScene):
		return
	var vroot: Node = (ps as PackedScene).instantiate()
	var skels: Array = _find(root, "Skeleton3D")
	if skels.is_empty():
		vroot.free()
		return
	var sk: Skeleton3D = skels[0]
	for mi in _find(vroot, "MeshInstance3D"):
		var m3: MeshInstance3D = mi
		if not String(m3.name).begins_with("Vis_"):
			continue
		var skin: Skin = m3.skin
		var mesh: Mesh = m3.mesh
		var nm: String = String(m3.name)
		var copy := MeshInstance3D.new()
		copy.name = nm
		copy.mesh = mesh
		copy.skin = skin
		for s in mesh.get_surface_count():
			if m3.get_surface_override_material(s) != null:
				copy.set_surface_override_material(s, m3.get_surface_override_material(s))
		sk.add_child(copy)
	vroot.free()

## Visitor colours by look (0..6) for material `mname` of the variant being baked (linear).
static func _vis_cols(mname: String) -> PackedColorArray:
	if _vis_table == null:
		_vis_table = _read_meta().get("visitors", {})
	var out := PackedColorArray()
	var key: String = "suit_linear" if _baking_variant == "suit" else "indoor_linear"
	var looks: Array = (_vis_table as Dictionary).get("looks", [])
	for i in 7:
		var c := Color(-1, -1, -1, 0)
		if i < looks.size():
			var tab: Dictionary = (looks[i] as Dictionary).get(key, {})
			if tab.has(mname):
				var a: Array = tab[mname]
				c = Color(float(a[0]), float(a[1]), float(a[2]), 1.0)
		out.append(c)
	return out

static func _read_meta() -> Dictionary:
	if not FileAccess.file_exists(META_FILE):
		return {}
	var f := FileAccess.open(META_FILE, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

static func _find(n: Node, cls: String) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x.is_class(cls):
			out.append(x)
		for c in x.get_children():
			stack.append(c)
	return out

## Transform of `n` relative to `root` (product of the Node3D transforms in between).
static func _rel_xf(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var x: Node = n
	while x != null and x != root:
		if x is Node3D:
			xf = (x as Node3D).transform * xf
		x = x.get_parent()
	return xf

## Bakes a GLB (or fixture) scene: bone matrices of every clip frame into a texture, the
## skinned meshes into one ArrayMesh with one surface per material.
static func bake(root: Node, meta: Dictionary, share = null) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var skels: Array = _find(root, "Skeleton3D")
	if skels.is_empty():
		return {"ok": false, "status": "no Skeleton3D"}
	var sk: Skeleton3D = skels[0]
	var nb: int = sk.get_bone_count()
	var names: Array = []
	var parent: Array = []
	for i in nb:
		names.append(sk.get_bone_name(i))
		parent.append(sk.get_bone_parent(i))
	# Parents before children.
	var order: Array = []
	var done := {}
	while order.size() < nb:
		var moved := false
		for i in nb:
			if done.has(i):
				continue
			if int(parent[i]) < 0 or done.has(int(parent[i])):
				order.append(i)
				done[i] = true
				moved = true
		if not moved:
			return {"ok": false, "status": "skeleton loop"}
	var K: Transform3D = _rel_xf(sk, root)
	var chest: int = sk.find_bone("chest")
	var upper := {}
	if chest >= 0:
		for i in order:
			var p: int = parent[i]
			if p == chest or upper.has(p):
				upper[i] = true
	# Slots: lower body (and chest) first, then the upper body.
	var slot_of: Array = []
	slot_of.resize(nb)
	var slots: Array = []
	for i in nb:
		if not upper.has(i):
			slot_of[i] = slots.size()
			slots.append(i)
	var upper_start: int = slots.size()
	for i in nb:
		if upper.has(i):
			slot_of[i] = slots.size()
			slots.append(i)
	var ns: int = slots.size()
	var row_w: int = (ns + 1) * 3
	# Bind poses (inverse bind matrices) from the first skin that names each bone.
	var meshes: Array = []
	for mi in _find(root, "MeshInstance3D"):
		var m3: MeshInstance3D = mi
		if m3.mesh == null or m3.mesh.get_surface_count() == 0:
			continue
		if m3.skin == null and (m3.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES) != 0:
			m3.skin = sk.create_skin_from_rest_transforms()
		if m3.skin != null:
			meshes.append(m3)
	if meshes.is_empty():
		return {"ok": false, "status": "no skinned mesh"}
	var bind: Array = []
	bind.resize(nb)
	var bind_warn := false
	for m3 in meshes:
		var skin: Skin = (m3 as MeshInstance3D).skin
		for bi in skin.get_bind_count():
			var bone: int = skin.get_bind_bone(bi)
			if bone < 0:
				bone = sk.find_bone(String(skin.get_bind_name(bi)))
			if bone < 0:
				continue
			var bp: Transform3D = skin.get_bind_pose(bi)
			if bind[bone] == null:
				bind[bone] = bp
			elif not (bind[bone] as Transform3D).is_equal_approx(bp):
				bind_warn = true
	for i in nb:
		if bind[i] == null:
			var g := Transform3D.IDENTITY
			var b: int = i
			while b >= 0:
				g = sk.get_bone_rest(b) * g
				b = sk.get_bone_parent(b)
			bind[i] = g.affine_inverse()
	# Clips.
	var anims := {}
	for ap in _find(root, "AnimationPlayer"):
		var player: AnimationPlayer = ap
		for an in player.get_animation_list():
			var short: String = String(an).get_slice("/", String(an).get_slice_count("/") - 1)
			anims[short] = player.get_animation(an)
	var clips := {}
	var missing: Array = []
	var clip_list: Array = _people_clips(meta) if _baking_people else ALL_CLIPS
	for c in clip_list:
		# Each file family owns its clips (decided 2026-10-01, RENDER-to-ART-NPC.md): the vehicle clips
		# are only in the astronaut files (people wear the suit outside); the V5 social clips are only in
		# the people files (the astronaut `in` body is a fallback; resolve_loop maps them to near clips).
		if (_baking_people and c in VEHICLE_CLIPS) or (not _baking_people and c in V5_CLIPS):
			continue
		if not anims.has(c):
			missing.append(c)
	if (not anims.has("idle") or not anims.has("walk")) and share == null:
		return {"ok": false, "status": "no idle/walk clip (missing: %s)" % ", ".join(missing)}
	if anims.is_empty():
		missing = []
	var mclips: Dictionary = meta.get("clips", {})
	var reuse: bool = share != null and share.get("names", []) == names
	if reuse:
		for i in nb:
			if not ((share["bind"] as Array)[i] as Transform3D).is_equal_approx(bind[i]):
				reuse = false
				break
	var rows_total := 0
	var clip_rows := {}
	if reuse:
		clips = share["clips"]
		rows_total = int(share["rows"])
	else:
		for c in clip_list:
			if not anims.has(c):
				continue
			var a: Animation = anims[c]
			var n: int = maxi(1, int(round(a.length * FPS)))
			var md: Dictionary = mclips.get(c, {})
			var loop: bool = bool(md.get("loop", c in LOOPS))
			var d := {"len": a.length, "loop": loop, "frames": n, "row0": rows_total,
				"speed": float(md.get("speed_mps", 0.0)), "stride": float(md.get("stride_m", 0.0)),
				"kind": String(md.get("kind", "loop" if loop else "oneshot"))}
			if ENTER_EXIT.has(c):
				d["pose_from"] = ENTER_EXIT[c][0]
				d["pose_to"] = ENTER_EXIT[c][1]
			clips[c] = d
			clip_rows[c] = a
			rows_total += n + 2
	# Texture of skin matrices + CPU copy of model-space bone globals (attachments, checks).
	var tex: ImageTexture = share["tex"] if reuse else null
	var globals := PackedFloat32Array()
	var locals := PackedFloat32Array()   # per row and bone: local rotation quaternion (4) + position (3)
	var rows_per_col := 4096
	var tex_info := {}
	if reuse:
		globals = share["globals"]
		locals = share["locals"]
		tex_info = share["tex_info"]
	else:
		var cols: int = int(ceil(float(rows_total) / rows_per_col))
		var tw: int = row_w * cols
		var th: int = mini(rows_total, rows_per_col)
		var px := PackedFloat32Array()
		px.resize(tw * th * 4)
		globals.resize(rows_total * nb * 12)
		locals.resize(rows_total * nb * 7)
		var rest_pos: Array = []
		var rest_rot: Array = []
		var rest_scl: Array = []
		for i in nb:
			var r: Transform3D = sk.get_bone_rest(i)
			rest_pos.append(r.origin)
			rest_rot.append(r.basis.get_rotation_quaternion())
			rest_scl.append(r.basis.get_scale())
		for c in clip_rows:
			var a: Animation = clip_rows[c]
			var tr_pos: Array = []
			var tr_rot: Array = []
			var tr_scl: Array = []
			tr_pos.resize(nb)
			tr_rot.resize(nb)
			tr_scl.resize(nb)
			tr_pos.fill(-1)
			tr_rot.fill(-1)
			tr_scl.fill(-1)
			for t in a.get_track_count():
				var path: NodePath = a.track_get_path(t)
				var bone_name: String = path.get_concatenated_subnames()
				var bi: int = sk.find_bone(bone_name)
				if bi < 0:
					continue
				match a.track_get_type(t):
					Animation.TYPE_POSITION_3D: tr_pos[bi] = t
					Animation.TYPE_ROTATION_3D: tr_rot[bi] = t
					Animation.TYPE_SCALE_3D: tr_scl[bi] = t
			var d: Dictionary = clips[c]
			var n: int = d["frames"]
			var row0: int = d["row0"]
			var G: Array = []
			G.resize(nb)
			for f in n + 2:
				var t: float = minf(float(mini(f, n)) / FPS, a.length)
				if bool(d["loop"]) and f == n + 1:
					t = 1.0 / FPS      # pad row of a loop = frame 1 (so row n -> n+1 wraps smoothly)
				for i in order:
					var pos: Vector3 = rest_pos[i]
					var rot: Quaternion = rest_rot[i]
					var scl: Vector3 = rest_scl[i]
					if int(tr_pos[i]) >= 0:
						pos = a.position_track_interpolate(tr_pos[i], t)
					if int(tr_rot[i]) >= 0:
						rot = a.rotation_track_interpolate(tr_rot[i], t)
					if int(tr_scl[i]) >= 0:
						scl = a.scale_track_interpolate(tr_scl[i], t)
					var local := Transform3D(Basis(rot).scaled(scl), pos)
					var lb: int = ((row0 + f) * nb + i) * 7
					var rq: Quaternion = rot.normalized()
					locals[lb] = rq.x
					locals[lb + 1] = rq.y
					locals[lb + 2] = rq.z
					locals[lb + 3] = rq.w
					locals[lb + 4] = pos.x
					locals[lb + 5] = pos.y
					locals[lb + 6] = pos.z
					var p: int = parent[i]
					G[i] = local if p < 0 else (G[p] as Transform3D) * local
				var row: int = row0 + f
				var col: int = row / rows_per_col
				var ry: int = row - col * rows_per_col
				var gchest: Transform3D = K * (G[chest] as Transform3D) if chest >= 0 else Transform3D.IDENTITY
				var gchest_inv: Transform3D = gchest.affine_inverse()
				for s in ns + 1:
					var m: Transform3D
					if s == ns:
						m = gchest
					else:
						var bi: int = slots[s]
						m = K * (G[bi] as Transform3D) * (bind[bi] as Transform3D)
						if s >= upper_start:
							m = gchest_inv * m
					var base: int = ((ry * tw) + col * row_w + s * 3) * 4
					var bx: Basis = m.basis
					var o: Vector3 = m.origin
					px[base] = bx.x.x
					px[base + 1] = bx.y.x
					px[base + 2] = bx.z.x
					px[base + 3] = o.x
					px[base + 4] = bx.x.y
					px[base + 5] = bx.y.y
					px[base + 6] = bx.z.y
					px[base + 7] = o.y
					px[base + 8] = bx.x.z
					px[base + 9] = bx.y.z
					px[base + 10] = bx.z.z
					px[base + 11] = o.z
				for i in nb:
					var g: Transform3D = K * (G[i] as Transform3D)
					var gb: int = (row * nb + i) * 12
					globals[gb] = g.basis.x.x
					globals[gb + 1] = g.basis.x.y
					globals[gb + 2] = g.basis.x.z
					globals[gb + 3] = g.basis.y.x
					globals[gb + 4] = g.basis.y.y
					globals[gb + 5] = g.basis.y.z
					globals[gb + 6] = g.basis.z.x
					globals[gb + 7] = g.basis.z.y
					globals[gb + 8] = g.basis.z.z
					globals[gb + 9] = g.origin.x
					globals[gb + 10] = g.origin.y
					globals[gb + 11] = g.origin.z
		var img := Image.create_from_data(tw, th, false, Image.FORMAT_RGBAF, px.to_byte_array())
		tex = ImageTexture.create_from_image(img)
		tex_info = {"row_w": row_w, "rows_per_col": rows_per_col, "upper_start": upper_start, "chest_slot": ns, "w": tw, "h": th}
	# Meshes: the imported skinned meshes are drawn AS THEY ARE (the web renderer cannot read
	# vertex data back, tested 2026-09-24), each by one MultiMesh, skinned in the shader from
	# the mesh's own BONE_INDICES / BONE_WEIGHTS through a bind -> slot table. Head_N nodes
	# (indoor model) get their own MultiMesh that holds only the colonists with that head.
	var parts: Array = []
	var heads := 0
	var tris := 0
	var mat_cache := {}
	for m3 in meshes:
		var mi3: MeshInstance3D = m3
		var head_id := -1
		var nm: String = String(mi3.name)
		if nm.begins_with("Head_") and nm.substr(5).is_valid_int():
			head_id = int(nm.substr(5))
			heads = maxi(heads, head_id + 1)
		var vis := -1
		var vis_heads := 0
		if nm.begins_with("Vis_"):
			var base: String = nm.substr(4)
			var hp: int = base.find("_h")
			if hp > 0 and base.substr(hp + 2).is_valid_int():
				for ch in base.substr(hp + 2):
					vis_heads |= 1 << int(ch)
				base = base.substr(0, hp)
			vis = VIS_KINDS.find(base)
		var skin: Skin = mi3.skin
		var bind_slot := PackedInt32Array()
		bind_slot.resize(64)
		for bi in mini(64, skin.get_bind_count()):
			var bone: int = skin.get_bind_bone(bi)
			if bone < 0:
				bone = sk.find_bone(String(skin.get_bind_name(bi)))
			bind_slot[bi] = int(slot_of[bone]) if bone >= 0 else 0
		var mesh: Mesh = mi3.mesh
		if mesh is ArrayMesh:
			(mesh as ArrayMesh).shadow_mesh = null
		for s in mesh.get_surface_count():
			var src: Material = mi3.get_surface_override_material(s) if mi3.get_surface_override_material(s) != null else mesh.surface_get_material(s)
			var mname: String = src.resource_name if src != null else "SuitMain"
			var mk: String = "%s|%d|%s" % [mname, head_id, str(bind_slot)]
			if not mat_cache.has(mk):
				mat_cache[mk] = _skin_material(src, mname, tex, tex_info, bind_slot, head_id)
			if mesh is ArrayMesh:
				(mesh as ArrayMesh).surface_set_material(s, mat_cache[mk])
			var idxc: int = mesh.surface_get_array_index_len(s)
			tris += (idxc if idxc > 0 else mesh.surface_get_array_len(s)) / 3
		var pt := {"mesh": mesh, "head": head_id, "name": nm}
		# V5 people: Outfit_<id> parts are drawn only for the people wearing that outfit; Head_<v>
		# (eyes, brows, lashes, teeth) and Hair_<v> for everyone, with no shadow of their own.
		if nm.begins_with("Outfit_"):
			pt["outfit"] = nm.substr(7)
		elif nm.begins_with("Addon_"):
			pt["addon"] = nm.substr(6)
			pt["face"] = true
		elif _baking_people and (nm.begins_with("Head_") or nm.begins_with("Hair_")):
			pt["face"] = true
		if vis >= 0:
			pt["vis"] = vis
			pt["vh"] = vis_heads
		parts.append(pt)
	# Shadow proxy: the body's surfaces merged into one surface, drawn SHADOWS_ONLY, so the
	# shadow pass costs one draw call per variant instead of one per material. Heads cast no
	# shadow (the body shadow covers them). If the mesh data cannot be read, the body casts
	# its own shadow as before.
	for p in parts.duplicate():
		if int(p["head"]) < 0 and not p.has("vis") and not p.has("face"):
			var pm: ArrayMesh = _skin_shadow_mesh(p["mesh"])
			if pm != null:
				p["proxied"] = true
				var sp := {"mesh": pm, "head": -1, "name": String(p["name"]) + "_shadow", "shadow_only": true}
				if p.has("outfit"):
					sp["outfit"] = p["outfit"]
				parts.append(sp)
	var prop_r: int = sk.find_bone("prop.R")
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	return {"ok": true, "parts": parts, "tex": tex, "tex_info": tex_info, "clips": clips, "rows": rows_total,
		"names": names, "parent": parent, "nb": nb, "globals": globals, "chest": chest, "prop_r": prop_r, "upper": upper,
		"slot_of": slot_of, "heads": heads, "tris": tris, "missing": missing, "bake_ms": ms, "bind_warn": bind_warn, "shared": reuse, "bind": bind,
		"locals": locals, "slots": slots, "K": K, "order": order, "upper_start": upper_start, "ns": ns, "deform": _deform_mask(names)}

## Bones that deform the mesh (prop.* do not: they only carry a crate or a tool).
static func _deform_mask(names: Array) -> Array:
	var out: Array = []
	for n in names:
		out.append(not String(n).begins_with("prop."))
	return out

## Largest change of any bone's local rotation between two frames of a clip (degrees).
static func _clip_max_step(g: PackedFloat32Array, nb: int, parent: Array, row0: int, frames: int) -> float:
	var worst := 0.0
	var prev: Array = []
	for f in frames + 1:
		var cur: Array = []
		for i in nb:
			var k: int = ((row0 + f) * nb + i) * 12
			var m := Basis(Vector3(g[k], g[k + 1], g[k + 2]), Vector3(g[k + 3], g[k + 4], g[k + 5]), Vector3(g[k + 6], g[k + 7], g[k + 8]))
			var p: int = parent[i]
			if p >= 0:
				var kp: int = ((row0 + f) * nb + p) * 12
				var mp := Basis(Vector3(g[kp], g[kp + 1], g[kp + 2]), Vector3(g[kp + 3], g[kp + 4], g[kp + 5]), Vector3(g[kp + 6], g[kp + 7], g[kp + 8]))
				m = mp.inverse() * m
			cur.append(m.orthonormalized().get_rotation_quaternion())
		if not prev.is_empty():
			for i in nb:
				worst = maxf(worst, rad_to_deg((prev[i] as Quaternion).angle_to(cur[i])))
		prev = cur
	return worst

## One-surface copy of a skinned mesh (vertex, bones, weights, index) that uses the material of
## surface 0. Returns null when the arrays cannot be read or the surfaces do not agree.
static func _skin_shadow_mesh(mesh: Mesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() < 2:
		return null
	var av := PackedVector3Array()
	var ab := PackedInt32Array()
	var aw := PackedFloat32Array()
	var ai := PackedInt32Array()
	var per := -1
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		if arr.size() < Mesh.ARRAY_MAX:
			return null
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			return null
		var bo = arr[Mesh.ARRAY_BONES]
		var we = arr[Mesh.ARRAY_WEIGHTS]
		if bo == null or we == null:
			return null
		var bones := PackedInt32Array(bo)
		var weights := PackedFloat32Array(we)
		var n: int = bones.size() / v.size()
		if (n != 4 and n != 8) or weights.size() != bones.size() or (per >= 0 and n != per):
			return null
		per = n
		var base: int = av.size()
		av.append_array(v)
		ab.append_array(bones)
		aw.append_array(weights)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			var src_i: PackedInt32Array = idx
			var at: int = ai.size()
			ai.resize(at + src_i.size())
			for k in src_i.size():
				ai[at + k] = src_i[k] + base
		else:
			var at2: int = ai.size()
			ai.resize(at2 + v.size())
			for k in v.size():
				ai[at2 + k] = base + k
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = av
	arrays[Mesh.ARRAY_BONES] = ab
	arrays[Mesh.ARRAY_WEIGHTS] = aw
	arrays[Mesh.ARRAY_INDEX] = ai
	var pm := ArrayMesh.new()
	pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
	if pm.get_surface_count() != 1 or pm.surface_get_array_len(0) != av.size():
		return null
	pm.surface_set_material(0, mesh.surface_get_material(0))
	return pm

static func _skin_material(src: Material, mname: String, tex: Texture2D, info: Dictionary, bind_slot: PackedInt32Array, head_id: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var hair: bool = mname.begins_with("Hair")
	m.shader = SKIN_SHADER_2S if _baking_people and hair else SKIN_SHADER
	if _baking_people:
		m.set_shader_parameter("people", true)
		m.set_shader_parameter("alpha_clip", hair)
		var cc := PackedColorArray()
		for h in CLOTH_COLS:
			cc.append(Color(h).srgb_to_linear())
		m.set_shader_parameter("cloth_cols", cc)
		var sc := PackedColorArray()
		for h in STRIPE_COLS:
			sc.append(Color(h).srgb_to_linear())
		m.set_shader_parameter("stripe_cols", sc)
	m.resource_name = mname
	m.set_shader_parameter("bind_slot", bind_slot)
	m.set_shader_parameter("head_id", head_id)
	m.set_shader_parameter("anim", tex)
	m.set_shader_parameter("row_w", int(info["row_w"]))
	m.set_shader_parameter("rows_per_col", int(info["rows_per_col"]))
	m.set_shader_parameter("upper_start", int(info["upper_start"]))
	m.set_shader_parameter("chest_slot", int(info["chest_slot"]))
	var roles := PackedColorArray()
	for rc in [Color("ff9f1c"), Color("5ac85a"), Color("4a90d9"), Color("e85d75"), Color("a78bfa"), Color("c9d3e0"), Color("c9d3e0"), Color("c9d3e0")]:
		roles.append((rc as Color).srgb_to_linear())
	m.set_shader_parameter("roles", roles)
	if src is BaseMaterial3D:
		var b: BaseMaterial3D = src
		m.set_shader_parameter("albedo", b.albedo_color)
		m.set_shader_parameter("roughness", b.roughness)
		m.set_shader_parameter("metallic", b.metallic)
		if b.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
			m.set_shader_parameter("use_tex", true)
		if b.emission_enabled:
			m.set_shader_parameter("emission", b.emission)
			m.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
	var mode := 0
	# V3.1 visitors: body colour groups take the visitor's colour (mode 4); SuitAccent (mode 1)
	# takes the visitor accent for role codes >= 8.
	var vc: PackedColorArray = _vis_cols(mname.get_slice(".", 0))
	m.set_shader_parameter("vis_cols", vc)
	if mname.begins_with("SuitMain") or mname.begins_with("SuitHard") or mname.begins_with("Pack") or mname.begins_with("Jumpsuit"):
		mode = 4
	if mname.begins_with("SuitAccent"):
		mode = 1
	elif mname.begins_with("Skin"):
		mode = 2
	elif mname.begins_with("Hair"):
		mode = 3
	elif mname.begins_with("ClothTint"):
		mode = 5
	elif mname.begins_with("UniformBase"):
		mode = 6
	m.set_shader_parameter("mode", mode)
	return m

func _make_mm(variant: String, lib: Dictionary) -> void:
	var list: Array = []
	for part in lib["parts"]:
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		# Instance colours stay white: the vertex colour (baked AO) must reach the shader.
		m.use_colors = true
		m.use_custom_data = true
		m.mesh = part["mesh"]
		m.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = m
		mmi.name = "Astronauts_%s_%s" % [variant, part["name"]]
		mmi.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(3000, 600, 3000))
		if bool(part.get("shadow_only", false)):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif int(part["head"]) >= 0 or bool(part.get("proxied", false)) or part.has("vis") or part.has("face"):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		list.append({"mm": m, "mmi": mmi, "head": int(part["head"]), "vis": int(part.get("vis", -1)), "vh": int(part.get("vh", 0)), "outfit": String(part.get("outfit", "")), "addon": String(part.get("addon", ""))})
	mm[variant] = {"parts": list, "heads": int(lib["heads"]), "people": bool(lib.get("people", false))}

## Frame row of clip `c` at time t (with the fraction to the next row).
func row_of(lib: Dictionary, c: String, t: float) -> float:
	var d: Dictionary = lib["clips"].get(c, lib["clips"]["idle"])
	var f: float = clampf(t, 0.0, float(d["len"])) * FPS
	var n: int = d["frames"]
	if f >= n:
		f = n
	return float(d["row0"]) + f

## Model-space transform of bone `bi` at a (whole) frame row.
static func bone_at(lib: Dictionary, row: int, bi: int) -> Transform3D:
	var g: PackedFloat32Array = lib["globals"]
	var k: int = (row * int(lib["nb"]) + bi) * 12
	return Transform3D(Vector3(g[k], g[k + 1], g[k + 2]), Vector3(g[k + 3], g[k + 4], g[k + 5]), Vector3(g[k + 6], g[k + 7], g[k + 8]), Vector3(g[k + 9], g[k + 10], g[k + 11]))

## The blended pose of one body, computed once per frame (row + crate share it).
func _globals_cached(rec: Dictionary, lib: Dictionary, pz: Dictionary) -> Array:
	if int(rec.get("g_frame", -1)) == _frame:
		return rec["g_cache"]
	var g: Array = pose_globals(lib, pz)
	rec["g_frame"] = _frame
	rec["g_cache"] = g
	return g

## Model-space transform of bone `bi` for a pose() output (the carried crate at prop.R).
func bone_for_pose(lib: Dictionary, pz: Dictionary, bi: int, rec = null) -> Transform3D:
	if needs_cpu(pz):
		if rec != null:
			return _globals_cached(rec, lib, pz)[bi]
		return pose_globals(lib, pz)[bi]
	var ra: int = int(row_of(lib, pz["a"], pz["ta"]))
	var g: Transform3D = bone_at(lib, ra, bi)
	if String(pz["c"]) != "" and float(pz["wc"]) > 0.5 and (lib["upper"] as Dictionary).has(bi) and int(lib["chest"]) >= 0:
		var rc: int = int(row_of(lib, pz["c"], pz["tc"]))
		var ch: int = lib["chest"]
		g = bone_at(lib, ra, ch) * bone_at(lib, rc, ch).affine_inverse() * bone_at(lib, rc, bi)
	return g

static func _row_f(lib: Dictionary, c: String, t: float) -> float:
	var d: Dictionary = lib["clips"].get(c, lib["clips"]["idle"])
	return float(d["row0"]) + minf(clampf(t, 0.0, float(d["len"])) * FPS, float(d["frames"]))

## A blend the GPU rows cannot draw exactly: a cross-fade, a walk/run mix, or the carry layer
## fading in or out. These are evaluated here on the CPU (quaternion slerp of the LOCAL bone
## rotations, V3 §3.4) and written into a dynamic row. A single clip, and the carry layer at
## full weight (an exact re-parenting at the chest), are drawn from the baked rows.
static func needs_cpu(pz: Dictionary) -> bool:
	if String(pz["b"]) != "" and float(pz["wb"]) > 0.001:
		return true
	var wc: float = float(pz["wc"]) if String(pz["c"]) != "" else 0.0
	return wc > 0.001 and wc < 0.999

static func _q_at(lib: Dictionary, row: int, i: int) -> Quaternion:
	var l: PackedFloat32Array = lib["locals"]
	var k: int = (row * int(lib["nb"]) + i) * 7
	return Quaternion(l[k], l[k + 1], l[k + 2], l[k + 3])

static func _p_at(lib: Dictionary, row: int, i: int) -> Vector3:
	var l: PackedFloat32Array = lib["locals"]
	var k: int = (row * int(lib["nb"]) + i) * 7
	return Vector3(l[k + 4], l[k + 5], l[k + 6])

## Local rotation and position of every bone of clip `c` at time t (frames slerped).
static func clip_locals(lib: Dictionary, c: String, t: float) -> Array:
	var f: float = _row_f(lib, c, t)
	var r0: int = int(floor(f))
	var k: float = f - r0
	var nb: int = lib["nb"]
	var qs: Array = []
	var ps: Array = []
	qs.resize(nb)
	ps.resize(nb)
	for i in nb:
		if k > 0.0001:
			qs[i] = _q_at(lib, r0, i).slerp(_q_at(lib, r0 + 1, i), k)
			ps[i] = _p_at(lib, r0, i).lerp(_p_at(lib, r0 + 1, i), k)
		else:
			qs[i] = _q_at(lib, r0, i)
			ps[i] = _p_at(lib, r0, i)
	return [qs, ps]

## The drawn pose as local rotations: A, slerped towards B by wb, the upper body slerped
## towards the carry clip by wc.
static func pose_locals(lib: Dictionary, pz: Dictionary) -> Array:
	var la: Array = clip_locals(lib, pz["a"], pz["ta"])
	var qs: Array = la[0]
	var ps: Array = la[1]
	var nb: int = lib["nb"]
	var wb: float = float(pz["wb"]) if String(pz["b"]) != "" else 0.0
	if wb > 0.0001:
		var lb: Array = clip_locals(lib, pz["b"], pz["tb"])
		for i in nb:
			qs[i] = (qs[i] as Quaternion).slerp(lb[0][i], wb)
			ps[i] = (ps[i] as Vector3).lerp(lb[1][i], wb)
	var wc: float = float(pz["wc"]) if String(pz["c"]) != "" else 0.0
	if wc > 0.0001:
		var lc: Array = clip_locals(lib, pz["c"], pz["tc"])
		var upper: Dictionary = lib["upper"]
		for i in nb:
			if upper.has(i):
				qs[i] = (qs[i] as Quaternion).slerp(lc[0][i], wc)
				ps[i] = (ps[i] as Vector3).lerp(lc[1][i], wc)
	return [qs, ps]

## Model-space bone transforms (the skeleton-to-model offset K included).
static func globals_of(lib: Dictionary, loc: Array) -> Array:
	var nb: int = lib["nb"]
	var parent: Array = lib["parent"]
	var g: Array = []
	g.resize(nb)
	for i in lib["order"]:
		var l := Transform3D(Basis(loc[0][i] as Quaternion), loc[1][i])
		var p: int = parent[i]
		g[i] = (lib["K"] as Transform3D) * l if p < 0 else (g[p] as Transform3D) * l
	return g

## Model-space matrices of every bone of a pose() output, as drawn: blended poses by the
## slerp path above; single clips from the baked frames (the GPU interpolates neighbouring
## frames, 1/30 s apart).
static func pose_globals(lib: Dictionary, pz: Dictionary) -> Array:
	if needs_cpu(pz):
		return globals_of(lib, pose_locals(lib, pz))
	var q := pz.duplicate()
	q["b"] = ""
	q["wb"] = 0.0
	if float(q["wc"]) < 0.5:
		q["c"] = ""
		q["wc"] = 0.0
	return globals_of(lib, pose_locals(lib, q))

## Largest local rotation change (degrees) of any deforming bone between two clip poses:
## sets the length of a cross-fade (V3 §3.4: angle / 300 deg/s, 0.25..0.6 s).
static func pose_angle(lib: Dictionary, a: String, ta: float, b: String, tb: float) -> float:
	var la: Array = clip_locals(lib, a, ta)
	var lb: Array = clip_locals(lib, b, tb)
	var deform: Array = lib["deform"]
	var worst := 0.0
	for i in int(lib["nb"]):
		if deform[i]:
			worst = maxf(worst, rad_to_deg((la[0][i] as Quaternion).angle_to(lb[0][i])))
	return worst

## One dynamic row of skin matrices for the shader, in the baked-row layout.
static func write_row(lib: Dictionary, g: Array, buf: PackedFloat32Array, row: int, row_w: int) -> void:
	var ns: int = lib["ns"]
	var slots: Array = lib["slots"]
	var ch: int = lib["chest"]
	var gc: Transform3D = g[ch] if ch >= 0 else Transform3D.IDENTITY
	var gci: Transform3D = gc.affine_inverse()
	var us: int = lib["upper_start"]
	var bind: Array = lib["bind"]
	for s in ns + 1:
		var m: Transform3D
		if s == ns:
			m = gc
		else:
			var bi: int = slots[s]
			m = (g[bi] as Transform3D) * (bind[bi] as Transform3D)
			if s >= us:
				m = gci * m
		var base: int = (row * row_w + s * 3) * 4
		var bx: Basis = m.basis
		buf[base] = bx.x.x
		buf[base + 1] = bx.y.x
		buf[base + 2] = bx.z.x
		buf[base + 3] = m.origin.x
		buf[base + 4] = bx.x.y
		buf[base + 5] = bx.y.y
		buf[base + 6] = bx.z.y
		buf[base + 7] = m.origin.y
		buf[base + 8] = bx.x.z
		buf[base + 9] = bx.y.z
		buf[base + 10] = bx.z.z
		buf[base + 11] = m.origin.z
# ---------------------------------------------------------------- bodies
func _log(key: String, text: String) -> void:
	if _logged.has(key):
		return
	_logged[key] = true
	print(text)

func _use_of(a: Dictionary) -> Dictionary:
	if forced_use.has(int(a["id"])):
		return forced_use[int(a["id"])]
	var ag = sim.get("agents")
	if ag != null and (ag as Object).has_method("use_of"):
		var u = ag.use_of(int(a["id"]))
		return u if u is Dictionary else {}
	var u2 = a.get("use", null)
	if u2 is Dictionary:
		return u2
	return _inferred_use(a)

## Until SIM writes agent.use (§6): a view-side guess so bodies still use beds and consoles.
## Sleepers take beds, workers take work anchors, in order of agent id.
var _infer_cache := {}
var _infer_tick := -1
func _inferred_use(a: Dictionary) -> Dictionary:
	if a["where"] != "in" or a["state"] != "alive":
		return {}
	var tick: int = int(sim.state["tick"])
	if tick != _infer_tick:
		_infer_tick = tick
		_infer_cache = {}
		var rank := {}
		var ids: Array = sim.state["agents"].keys()
		ids.sort()
		for id in ids:
			var x: Dictionary = sim.state["agents"][id]
			if x["where"] != "in" or x["state"] != "alive":
				continue
			var bid: int = int(x.get("bld", -1))
			if not sim.state["buildings"].has(bid):
				continue
			var kind := ""
			if bool(x.get("sleeping", false)):
				kind = "bed"
			elif String(x.get("plan_kind", "")) == "task" and _still(x):
				kind = "work"
			if kind == "":
				continue
			var k2: String = "%d:%s" % [bid, kind]
			var i: int = int(rank.get(k2, 0))
			rank[k2] = i + 1
			var def_id: String = sim.state["buildings"][bid]["def"]
			var pose: String = "lie" if kind == "bed" else ("sit" if def_id in ["research_lab"] and i % 2 == 1 else "stand")
			_infer_cache[id] = {"kind": kind, "b": bid, "i": i, "pose": pose, "act": "sleep" if kind == "bed" else "work", "inferred": true}
	return _infer_cache.get(int(a["id"]), {})

func _still(x: Dictionary) -> bool:
	var rec = agents.get(int(x["id"]))
	return rec == null or float(rec["speed"]) < 0.2

func _look(a: Dictionary) -> int:
	var id: int = int(a["id"])
	if String(a.get("kind", "")) == "visitor":
		# ART-NPC look code: (8 + v) * 64 + head * 8 + tone; tourists pick one of 3 sets.
		var vk: String = String(a.get("vkind", "trader"))
		var v: int = 0
		match vk:
			"liner", "tourist": v = 1 + int(Rng.hash2(id, 31, 3) * 3.0) % 3
			"medical", "patient": v = 4
			"science": v = 5
			"inspector", "courier": v = 6
			_: v = 0
		var vh: int = int(Rng.hash2(id, 23, 5) * 4.0) % 4
		var vt: int = int(Rng.hash2(id, 29, 7) * 6.0) % 6
		return (8 + v) * 64 + vh * 8 + vt
	var role: int = int(ROLE_INDEX.get(String(a.get("role", "")), 5))
	var head: int = int(Rng.hash2(id, 23, 5) * 4.0) % 4
	var tone: int = int(Rng.hash2(id, 29, 7) * 6.0) % 6
	return role * 64 + head * 8 + tone

func _floor_y(b: Dictionary) -> float:
	var meta = view.bmeta.get(int(b["id"]))
	var base: float = view.h(b["pos"].x, b["pos"].y) + 0.02
	if meta != null:
		base = (meta["xf"] as Transform3D).origin.y
		# (a room drawn at a scale, e.g. an old save's 0.667 x model: its floor top is FLOOR_Z x scale up;
		# the unscaled 0.14 m left people 4.7 cm in the air there, 2026-10-02)
		var sc: float = Models.scale3(meta.get("tpl", {})).y
		# (a multi-storey building: its ground floor's top from the model; the dome's plaza is 0.30 m up)
		var nf: int = int(sim.bdef(b["def"]).get("floors", 1))
		if nf > 1:
			var tops: Array = _floor_tops(meta, nf)
			if not tops.is_empty():
				return base + float(tops[0]) * sc
		return base + FLOOR_Z * sc
	return base + FLOOR_Z

## World y of the top of floor f of a multi-storey building, from its model's anchors (each floor's anchors
## stand on its floor top: the heights that most anchors share, one per floor); SIM's height when the model
## does not show the floors.
func level_y(b: Dictionary, f: int, sim_h: float) -> float:
	var meta = view.bmeta.get(int(b["id"]))
	if meta == null:
		return _floor_y(b) + sim_h
	var nf: int = int(sim.bdef(b["def"]).get("floors", 1))
	var tops: Array = _floor_tops(meta, nf)
	if f >= 0 and f < tops.size():
		return (meta["xf"] as Transform3D).origin.y + float(tops[f]) * Models.scale3(meta.get("tpl", {})).y
	return _floor_y(b) + sim_h

static func _floor_tops(meta: Dictionary, nf: int) -> Array:
	if meta.has("floor_tops"):
		return meta["floor_tops"]
	var tpl: Dictionary = meta.get("tpl", {})
	var hist := {}
	for an in (tpl.get("anchors", {}) as Dictionary):
		var yk: int = int(round((tpl["anchors"][an] as Transform3D).origin.y / 0.05))
		hist[yk] = int(hist.get(yk, 0)) + 1
	# clusters of neighbouring heights (within 0.25 m), weighted
	var keys: Array = hist.keys()
	keys.sort()
	var cl: Array = []   # [count, y of the most common height]
	for k in keys:
		if not cl.is_empty() and k - int(cl[-1][2]) <= 5:
			cl[-1][0] = int(cl[-1][0]) + int(hist[k])
			if int(hist[k]) > int(cl[-1][3]):
				cl[-1][1] = k * 0.05
				cl[-1][3] = int(hist[k])
			cl[-1][2] = k
		else:
			cl.append([int(hist[k]), k * 0.05, k, int(hist[k])])
	cl.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
	var tops: Array = []
	for c in cl.slice(0, nf):
		tops.append(float(c[1]))
	tops.sort()
	if tops.size() < nf or tops.is_empty() or float(tops[0]) > 1.0:
		tops = []
	meta["floor_tops"] = tops
	return tops

## The world stand point and facing of a furniture anchor, or {} when the room has none.
func _anchor(use: Dictionary) -> Dictionary:
	var bid: int = int(use.get("b", -1))
	# A survey of a fragment site: kneel where the colonist is (SIM: service with b = -1).
	if bid < 0 and String(use.get("kind", "")) == "service":
		return {"pos": Vector3.INF, "yaw": 0.0, "aisles": [], "found": true, "here": true}
	if not sim.state["buildings"].has(bid) or not view.bmeta.has(bid):
		return {}
	var b: Dictionary = sim.state["buildings"][bid]
	var anchors: Dictionary = view.bmeta[bid]["anchors"]
	var kind: String = String(use.get("kind", ""))
	var i: int = int(use.get("i", 0))
	var nm := "Service"
	match kind:
		"bed", "child_bed": nm = "Bed_%d" % _bed_anchor(b, kind, i)
		"seat": nm = "Seat_%d" % i
		"work": nm = "Work_%d" % i
		"stand": nm = "Stand_%d" % i
	var floor_y: float = _floor_y(b) if b["kind"] != "exterior" else view.h(b["pos"].x, b["pos"].y) + 0.02
	if i >= 0 and not anchors.has(nm) and kind != "service":
		nm = _alt_anchor(bid, kind, i, nm)
	if i >= 0 and anchors.has(nm) or kind == "service" and anchors.has(nm):
		var xf: Transform3D = anchors[nm]
		var local_y: float = xf.origin.y - (view.bmeta[bid]["xf"] as Transform3D).origin.y
		var p: Vector3 = xf.origin
		if local_y < 0.05:
			p.y = floor_y
		var fx: Vector3 = xf.basis.x
		# A seat whose model puts a table edge over the seated legs: the body sits this far further back
		# (tools/render_seat_check.gd fix -> presentation/navgrid/seat_fix.res, 2026-10-02).
		if kind == "seat" or kind == "work":
			var sfix: Vector2 = _seat_fix(view.bmeta[bid], nm)
			if sfix != Vector2.ZERO:
				var fh := Vector3(fx.x, 0.0, fx.z).normalized()
				var sh := Vector3(-fh.z, 0.0, fh.x)
				p += (-fh * sfix.x + sh * sfix.y) * float((view.bmeta[bid].get("tpl", {}) as Dictionary).get("scale", 1.0))
		# Several people at one Anchor_Service: side by side along the anchor's local Z.
		if kind == "service" and i > 0:
			var side: Vector3 = xf.basis.z.normalized()
			p += side * (0.85 * float((i + 1) / 2) * (1.0 if i % 2 == 1 else -1.0))
		var aisles: Array = []
		for an in anchors:
			if String(an).begins_with("Aisle_"):
				var ap: Vector3 = (anchors[an] as Transform3D).origin
				ap.y = floor_y
				aisles.append(ap)
		return {"pos": p, "yaw": -atan2(fx.z, fx.x), "aisles": aisles, "found": true}
	# i == -1: SIM found no free anchor of that kind (not an art fault).
	if i >= 0 or kind == "service":
		_log("anchor:%s:%d:%s" % [b["def"], int(b.get("size", 1)), nm], "RENDER npc: %s size %d has no Anchor_%s; using a standing ring position (ART-HAB)" % [b["def"], int(b.get("size", 1)), nm])
	# Fallback: a standing ring position, facing the centre.
	var r: float = float(b["radius"]) * (0.55 if b["kind"] != "exterior" else 1.0) + (0.9 if b["kind"] == "exterior" else 0.0)
	# The lander carries people on its deck (V3_1: never drawn standing outside its hull).
	if String(b["def"]) == "lander":
		r = float(b["radius"]) * 0.4
		floor_y = view.h(b["pos"].x, b["pos"].y) + 1.62
	var ang: float = float(b["rot"]) + 0.4 + TAU * float(posmod(i if i >= 0 else int(use.get("seq", 0)), 8)) / 8.0
	var c: Vector2 = b["pos"]
	var q: Vector2 = c + Vector2(cos(ang), sin(ang)) * r
	var face: Vector2 = (c - q).normalized()
	return {"pos": Vector3(q.x, floor_y, q.y), "yaw": -atan2(face.y, face.x), "aisles": [], "found": false}

static var _seat_fixes = null
static func _seat_fix(meta: Dictionary, anchor: String) -> Vector2:
	if _seat_fixes == null:
		_seat_fixes = {}
		if ResourceLoader.exists("res://presentation/navgrid/seat_fix.res"):
			var r = load("res://presentation/navgrid/seat_fix.res")
			if r != null and (r as Resource).has_meta("fix"):
				_seat_fixes = (r as Resource).get_meta("fix")
	if (_seat_fixes as Dictionary).is_empty():
		return Vector2.ZERO
	var model: String = String((meta.get("tpl", {}) as Dictionary).get("key", "")).get_slice("@", 0).get_file().get_basename()
	var f = ((_seat_fixes as Dictionary).get(model, {}) as Dictionary).get(anchor, null)
	if f is Array and (f as Array).size() >= 2:
		return Vector2(float(f[0]), float(f[1]))   # [back, side] m
	return Vector2(float(f), 0.0) if f != null else Vector2.ZERO

## A structure whose anchors carry a venue or floor in their names (the super dome: Seat_<venue>_<k>,
## Bed_<floor>_<unit>_<k>, Work_<venue>_<k>, Plaza_<k>): SIM's slot i of a kind -> the i-th of those
## anchors (sorted, wrapping). It replaced the standing ring of "no Anchor_Seat_6" (2026-10-02).
const ALT_PREFIX := {"seat": ["Seat_", "Bench_"], "bed": ["Bed_"], "child_bed": ["Bed_"], "work": ["Work_"], "stand": ["Stand_", "Plaza_", "Dance_"]}
func _alt_anchor(bid: int, kind: String, i: int, nm: String) -> String:
	var meta: Dictionary = view.bmeta[bid]
	var b: Dictionary = sim.state["buildings"][bid]
	# (on SIM's floor of that slot: the anchors between that floor's top and the next one's)
	var f := 0
	var nf: int = int(sim.bdef(b["def"]).get("floors", 1))
	if nf > 1 and sim.get("floors") != null:
		f = int(sim.floors.slot_floor(b, kind, i))
	var ck: String = "alt_%s_%d" % [kind, f]
	if not meta.has(ck):
		var tops: Array = _floor_tops(meta, nf) if nf > 1 else []
		var lo: float = (float(tops[f]) - 0.3) if f < tops.size() else -INF
		var hi: float = (float(tops[f + 1]) - 0.3) if f + 1 < tops.size() else INF
		var lst: Array = []
		var tpl_an: Dictionary = (meta.get("tpl", {}) as Dictionary).get("anchors", {})
		for pre in ALT_PREFIX.get(kind, []):
			for an in tpl_an:
				if String(an).begins_with(pre):
					var ly: float = (tpl_an[an] as Transform3D).origin.y
					if ly >= lo and ly < hi:
						lst.append(String(an))
		lst.sort()
		meta[ck] = lst
	var l: Array = meta[ck]
	return nm if l.is_empty() else String(l[i % l.size()])

## SIM numbers adult beds and children's bunks separately (agents: "bed" = beds - child_beds, "child_bed");
## the models number every bed of a unit together, unit by unit (ART-HAB: parents' beds, then the bunks:
## Bed 4u .. 4u+3). Slot i of a kind -> the Bed_<n> anchor. Without children's bunks n = i.
func _bed_anchor(b: Dictionary, kind: String, i: int) -> int:
	var fl = sim.get("floors")
	if i < 0 or fl == null or not fl.has_method("units"):
		return i
	var us: Array = fl.units(b)
	var kids := false
	for u in us:
		if int(u.get("child_beds", 0)) > 0:
			kids = true
	if not kids:
		return i
	var base := 0
	var acc := 0
	for u in us:
		var na: int = int(u["beds"])
		var nc: int = int(u.get("child_beds", 0))
		var n: int = na if kind == "bed" else nc
		if i < acc + n:
			return base + (i - acc) + (0 if kind == "bed" else na)
		acc += n
		base += na + nc
	return i

func _goal_for(use: Dictionary, b: Dictionary, found: bool) -> Array:
	var kind: String = String(use.get("kind", ""))
	var act: String = String(use.get("act", "idle"))
	var pose: String = String(use.get("pose", "stand"))
	if not found and kind == "service":
		return ["kneel", "repair_kneel"]
	if not found:
		# A missing anchor: stand at the ring position (§6).
		var l0: String = "work_console" if kind == "work" else ("talk" if act == "talk" else "idle_look")
		return ["stand", l0]
	match kind:
		"bed", "child_bed":
			return ["lie", "sleep"]
		"seat":
			return ["sit", {"eat": "sit_eat", "work": "sit_type"}.get(act, "sit_idle")]
		"work":
			if pose == "sit":
				return ["sit", "sit_type"]
			return ["stand", "work_console" if String(b["def"]) in CONSOLE_DEFS else "work_bench"]
		"stand":
			# A hull breach is sealed low on the wall: kneel (V3 §4.3 repair).
			if act == "repair" and bool(b.get("breach", false)):
				return ["kneel", "repair_kneel"]
			if act == "repair" or act == "work":
				return ["stand", "work_bench"]
			return ["stand", "talk" if act == "talk" else ("idle_look" if act == "idle" else "idle")]
		"service":
			return ["kneel", "repair_kneel"]
	return [pose, Pose.REST.get(pose, "idle")]

## The library key a person is drawn from indoors: "p_<variant>" (their SIM variant, else a
## pilot variant of the same sex), or the v3 indoor astronaut ("in") for children and when no
## people library is loaded.
var _pkey := {}
func _people_key(a: Dictionary) -> String:
	var id: int = int(a["id"])
	if _pkey.has(id):
		return _pkey[id]
	var k := "in"
	var pp = sim.get("people") if sim != null else null
	if pp != null and libs.has("in"):
		var idn: Dictionary = pp.identity(a)
		var v: String = String(idn.get("variant", ""))
		if libs.has("p_" + v):
			k = "p_" + v
		elif String(a.get("kind", "")) != "child" and not bool(idn.get("child", false)):
			var keys: Array = libs.keys()
			keys.sort()
			for lk in keys:
				if String(lk).begins_with("p_" + v.substr(0, 1)):
					k = lk
					break
	elif pp == null and not libs.has("in"):
		for lk in libs:
			if String(lk).begins_with("p_"):
				k = lk
				break
	_pkey[id] = k
	return k

## A body that changes library (suit <-> person at an airlock) keeps its clip state; the clip
## table and the pose-angle function follow the new library.
func _rebind(rec: Dictionary, lib: Dictionary) -> void:
	rec["sm"].clips = lib["clips"]
	rec["sm"].angle_fn = func(ca, ta, cb, tb): return pose_angle(lib, ca, ta, cb, tb)
	rec.erase("g_frame")

## Hair colour index (people shader, mode 3) from SIM's 0..0.85 hair parameter.
static func _hair_index(h: float) -> int:
	return 0 if h < 0.2 else (1 if h < 0.45 else (2 if h < 0.62 else 3))

## The outfits a people library holds (from its Outfit_<id> parts).
static func lib_outfits(lib: Dictionary) -> Array:
	if not lib.has("outfits"):
		var o: Array = []
		for k in outfit_table(lib):
			o.append(k)
		o.sort()
		lib["outfits"] = o
	return lib["outfits"]

## Outfit id -> {mesh (the Outfit_<mesh> part), addons [Addon_<name> parts], idx (0..7), base
## (linear UniformBase colour)}. From the manifest variant (a mesh name, or ART-NPC's
## {mesh, addons, base_rgb} form); outfits whose mesh the file lacks are left out. Without a
## manifest entry every Outfit_<id> part is one outfit.
static func outfit_table(lib: Dictionary) -> Dictionary:
	if lib.has("outfit_table"):
		return lib["outfit_table"]
	var have := {}
	var addons_have := {}
	for p in lib["parts"]:
		if p.has("outfit"):
			have[String(p["outfit"])] = true
		if p.has("addon"):
			addons_have[String(p["addon"])] = true
	var t := {}
	var mv = _people_manifest().get("variants", {}).get(String(lib.get("pvariant", "")), {})
	var outs = mv.get("outfits", {}) if mv is Dictionary else {}
	var ids: Array = (outs as Dictionary).keys() if outs is Dictionary else []
	ids.sort()
	for id in ids:
		var e = outs[id]
		var mesh: String = ""
		var adds: Array = []
		var base := Color(1, 1, 1)
		if e is String:
			mesh = String(e).trim_prefix("Outfit_")
		elif e is Dictionary:
			mesh = String(e.get("mesh", "")).trim_prefix("Outfit_")
			for ad in e.get("addons", []):
				if addons_have.has(String(ad).trim_prefix("Addon_")):
					adds.append(String(ad).trim_prefix("Addon_"))
			var rgb = e.get("base_rgb", null)
			if rgb is Array and (rgb as Array).size() >= 3:
				base = Color(float(rgb[0]), float(rgb[1]), float(rgb[2])).srgb_to_linear()
		if have.has(mesh) and t.size() < 16:
			t[String(id)] = {"mesh": mesh, "addons": adds, "idx": t.size(), "base": base}
	if t.is_empty():
		var ms: Array = have.keys()
		ms.sort()
		for m in ms:
			if t.size() < 16:
				t[m] = {"mesh": m, "addons": [], "idx": t.size(), "base": Color(1, 1, 1)}
	lib["outfit_table"] = t
	return t

## Sets a person's (or puppet's) outfit fields from an outfit id of the library.
static func set_outfit(lib: Dictionary, rec: Dictionary, id: String) -> void:
	var e: Dictionary = outfit_table(lib).get(id, {})
	rec["outfit"] = id
	rec["omesh"] = String(e.get("mesh", ""))
	rec["addons"] = e.get("addons", [])
	rec["oidx"] = int(e.get("idx", 0))

## SIM's outfit id -> an outfit the library has (same family first: casual_*, uniform_*).
static func outfit_for(lib: Dictionary, want: String) -> String:
	var outs: Array = lib_outfits(lib)
	if outs.is_empty() or outs.has(want):
		return want if outs.has(want) else ""
	var fam: String = "casual" if want.begins_with("casual") or want == "prison" or want == "school" else "uniform"
	for o in outs:
		if String(o).begins_with(fam):
			return o
	return outs[0]

## Look code, outfit and clothes colour of a person (people libraries), refreshed every 30 frames:
## role * 64 + hair colour * 8 + skin tone (0 dark .. 5 light, from identity.tint).
func _people_look(a: Dictionary, rec: Dictionary, lib: Dictionary) -> void:
	var id: int = int(a["id"])
	if rec.has("plook") and (id + _frame) % 30 != 0:
		return
	var role: int = int(rec["look"]) / 64
	var tone: int = int(rec["look"]) % 8
	var hc: int = (int(rec["look"]) / 8) % 4
	var want := "uniform_engineering"
	var pp = sim.get("people") if sim != null else null
	if pp != null:
		var t: Dictionary = pp.identity(a).get("tint", {})
		tone = 5 - clampi(int(float(t.get("skin", 0.5)) * 6.0), 0, 5)
		hc = 4 if bool(t.get("grey", false)) else _hair_index(float(t.get("hair", 0.3)))
		want = String(pp.outfit(a))
		if role < 8:
			# The stripe follows the department (role bits carry the stripe index on people).
			var si: int = STRIPES.find(String(pp.marks(a).get("stripe", "")))
			role = si if si >= 0 else 4
	rec["plook"] = role * 64 + hc * 8 + tone
	set_outfit(lib, rec, outfit_for(lib, want))
	rec["cloth"] = int(Rng.hash2(id, 41, 13) * 8.0) % 8

func _new_rec(a: Dictionary, lib: Dictionary) -> Dictionary:
	var p: Vector2 = a["pos"]
	var sm = Pose.new(lib["clips"])
	sm.angle_fn = func(ca, ta, cb, tb): return pose_angle(lib, ca, ta, cb, tb)
	sm.cur_t = Rng.hash2(int(a["id"]), 3, 9) * 3.0
	return {"pos": Vector3(p.x, view.h(p.x, p.y), p.y), "yaw": Rng.hash2(int(a["id"]), 11, 2) * TAU, "speed": 0.0, "sm": sm,
		"mode": "follow", "use_key": "", "use": {}, "anchor": {}, "path": [], "crate": -1, "crate_res": "", "var": "",
		"look": _look(a), "dead": false, "catch": 0.0}

## Places every astronaut body and fills the instance buffers. Returns false when no
## skinned variant is available (world_view then draws the v2 rigid colonists).
func sync(delta: float) -> bool:
	if libs.is_empty():
		return false
	var t0: int = Time.get_ticks_usec()
	_frame += 1
	var all: Dictionary = sim.state["agents"]
	var tick: int = int(sim.state["tick"])
	for id in agents.keys():
		if not all.has(id):
			# V3.1 pad decision: a visitor who boards leaves the simulation at the pad edge;
			# the view walks it up the ramp lane to the ramp foot and fades it out there.
			var gr0: Dictionary = agents[id]
			var foot: Vector3 = view.traffic.ramp_near(gr0["pos"], 16.0) if bool(gr0.get("visitor", false)) and view.get("traffic") != null else Vector3.INF
			if foot != Vector3.INF and not bool(gr0["dead"]):
				_ghosts[id] = {"rec": gr0, "foot": foot}
				_release(gr0, id)
				agents.erase(id)
			else:
				_drop(id)
	var lists := {}
	for lk in libs:
		lists[lk] = []
	_walk_ghosts(delta, lists)
	_sync_puppets(delta, lists)
	_build_occ()
	var focus: Vector3 = view._focus_now
	var cam_d: float = float(view.camera_distance)
	var cam3: Camera3D = view.get_viewport().get_camera_3d() if view.is_inside_tree() else null
	# Animation runs in game time: 2x speed plays the clips at 2x, a pause freezes them.
	game_rate = float(view.game_rate)
	_tick_s = 1.0 / maxf(float(sim.bal.get("tick_hz", 10)), 1.0)
	var fid = view.get("follow_id")
	_follow_id = int(fid) if fid != null else -1
	var c3: Camera3D = view.get_viewport().get_camera_3d() if view.is_inside_tree() else null
	_cam_pos = c3.global_position if c3 != null else Vector3.INF
	_dyn_used = 0
	_bd_used = 0
	_plans_frame = 0
	_plan_us = 0
	# A new award: colonists who stand free cheer (staggered).
	var aw: int = (sim.state.get("awards", {}) as Dictionary).size()
	if _awards_seen >= 0 and aw > _awards_seen:
		for rid in agents:
			agents[rid]["cheer_in"] = 0.2 + Rng.hash2(int(rid), aw, 7) * 0.9
	_awards_seen = aw
	var ts0: int = Time.get_ticks_usec()
	# Slots change slowly: every 4th frame (a body keeps its point in between).
	if _frame % 4 == 0 or _room_n < 0:
		_assign_slots(all)
	stats_slots["assign_ms"] = snappedf(lerpf(float(stats_slots.get("assign_ms", 0.0)), (Time.get_ticks_usec() - ts0) / 1000.0, 0.1), 0.01)
	for id in all:
		var a: Dictionary = all[id]
		var dead: bool = a["state"] != "alive"
		if dead and tick - int(a.get("death_tick", 0)) >= 1200:
			if agents.has(id):
				_drop(id)
			continue
		# V4 riders (SIM: where == "vehicle") are drawn by fx_vehicles in their seats; a body
		# getting in or out plays the vehicle chain there too, so it is not drawn here.
		if a["where"] == "vehicle" or (view.get("vehicles") != null and view.vehicles.hides(int(id))):
			if agents.has(id):
				var rv: Dictionary = agents[id]
				var vp: Vector2 = a["pos"]
				rv["pos"] = Vector3(vp.x, view.h(vp.x, vp.y), vp.y)
				rv["seen"] = false
				rv["wp"] = []
			continue
		var inside: bool = a["where"] == "in"
		# A body on (or walking to, or getting up from) a room anchor is indoors.
		if not inside and agents.has(id):
			var r0: Dictionary = agents[id]
			if String(r0["mode"]) in ["to_anchor", "at_anchor", "leaving"] and String((r0["use"] as Dictionary).get("kind", "service")) != "service":
				inside = true
		# A body waiting outside a full room (critic round 8) wears its suit.
		if agents.has(id) and bool(agents[id].get("q_out", false)) and bool(agents[id].get("slot_q", false)) and agents[id].has("slot") \
				and (agents[id]["pos"] as Vector3).distance_to(agents[id]["slot"]) < 2.5:
			inside = false
		var variant: String = "in" if inside else "suit"
		var lg = view.airlock.goals.get(int(id)) if view.airlock != null else null
		if lg != null and (lg as Dictionary).has("want_var"):
			variant = lg["want_var"]
		if not libs.has(variant):
			variant = "suit" if libs.has("suit") else "in"
		# V3_1 §5.3: the clothes change at an airlock suit anchor (suit_swap clip, cut at its
		# middle frame), never in the chamber and never outside.
		if agents.has(id) and agents[id].has("force_var") and libs.has(String(agents[id]["force_var"])):
			variant = agents[id]["force_var"]
			agents[id].erase("force_var")
			agents[id].erase("var_hold")
		elif agents.has(id) and String(agents[id]["var"]) != variant and libs.has(String(agents[id]["var"])):
			if _swap_rule(agents[id], variant, lg, delta) == "hold":
				variant = agents[id]["var"]
		elif agents.has(id):
			agents[id].erase("var_hold")
		# V5: indoors the body comes from the person's own people library when it exists.
		var dk: String = _people_key(a) if variant == "in" else variant
		# LOD1 beyond LOD1_DIST m from the camera (hysteresis 1 m; never the person in the follow view)
		if dk.begins_with("p_") and libs.has(dk + "_lod1") and agents.has(id) and int(id) != _follow_id and _cam_pos != Vector3.INF:
			var cdl: float = (agents[id]["pos"] as Vector3).distance_to(_cam_pos)
			var was: bool = String(agents[id].get("dk", "")).ends_with("_lod1")
			if cdl > LOD1_DIST + (-1.0 if was else 1.0):
				dk += "_lod1"
		var lib: Dictionary = libs[dk]
		if not agents.has(id):
			agents[id] = _new_rec(a, lib)
		var rec: Dictionary = agents[id]
		if rec["var"] != variant:
			rec["var"] = variant
		if String(rec.get("dk", "")) != dk:
			if rec.has("dk"):
				_rebind(rec, lib)
				rec.erase("plook")
			rec["dk"] = dk
		if bool(lib.get("people", false)):
			_people_look(a, rec, lib)
		# Far bodies (and everything when zoomed far out) update at a lower rate.
		# Off-screen bodies (outside the camera frustum, 2 m margin) update at the far rate too.
		var far: bool = (rec["pos"] as Vector3).distance_squared_to(focus) > 8100.0 or cam_d > 160.0 \
				or (cam3 != null and not cam3.is_position_in_frustum((rec["pos"] as Vector3) + Vector3(0, 1.0, 0)) and not cam3.is_position_in_frustum((rec["pos"] as Vector3) + (cam3.global_position - (rec["pos"] as Vector3)).normalized() * 2.0))
		# The person in the follow view is updated every frame (the frustum test uses the camera of the
		# frame before: on a quick turn the body tested "off screen" and moved every 3rd frame).
		if far and (int(id) == _follow_id or no_far):
			far = false
		rec["far"] = far
		var step: float = delta
		# V5 (the 8-10 ms fx_npc cost at 66 people, 2026-09-29): from 70 m camera distance every body
		# is updated every 2nd frame (a 0.14 m step at run speed, not visible from there); far and
		# off-screen bodies every 3rd as before.
		# (and, 2026-10-02 at 134 people, every body over 25 m from the camera: the follow view and close
		# overviews updated the whole colony every frame)
		var mid: bool = not far and (cam_d > 70.0 or (_cam_pos != Vector3.INF and (rec["pos"] as Vector3).distance_squared_to(_cam_pos) > 625.0)) and int(id) != _follow_id
		if far or mid:
			var k: int = 3 if far else 2
			if (int(id) + _frame) % k != 0:
				(lists[dk] as Array).append([rec, lib])
				continue
			step = delta * k
		var tb0: int = Time.get_ticks_usec()
		_update_body(a, rec, lib, step, dead)
		_t_body += Time.get_ticks_usec() - tb0
		_n_body += 1
		(lists[dk] as Array).append([rec, lib])
	var ts1: int = Time.get_ticks_usec()
	_sep_dt = delta
	_separate()
	stats_slots["sep_ms"] = snappedf(lerpf(float(stats_slots.get("sep_ms", 0.0)), (Time.get_ticks_usec() - ts1) / 1000.0, 0.1), 0.01)
	var tw0: int = Time.get_ticks_usec()
	for variant in lists:
		if mm.has(variant):
			_write_mm(variant, lists[variant])
	_t_write += Time.get_ticks_usec() - tw0
	if _dyn_used > 0 and _dyn_img != null:
		_dyn_img.set_data(_dyn_w, DYN_ROWS, false, Image.FORMAT_RGBAF, _dyn_buf.to_byte_array())
		_dyn_tex.update(_dyn_img)
	if _bd_used > 0 and _bd_img != null:
		_bd_img.set_data(1, BD_ROWS, false, Image.FORMAT_RGBAF, _bd_buf.to_byte_array())
		_bd_tex.update(_bd_img)
	var tl0: int = Time.get_ticks_usec()
	_sync_lamps(lists.get("suit", []))
	_t_lamps += Time.get_ticks_usec() - tl0
	_prof_frames += 1
	npc_ms = lerpf(npc_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.05)
	return true

# ---------------------------------------------------------------- helmet lamps
## At night every suited colonist shows its helmet lamps: a halo at the helmet and a warm
## spot on the ground ahead (critic: suited colonists must be easy to find at night).
func _make_lamps() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var st := SurfaceTool.new()
	st.create_from(q, 0)
	var arr: Array = st.commit_to_arrays()
	var cols := PackedColorArray()
	cols.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	cols.fill(Color(1, 1, 1, 1))
	arr[Mesh.ARRAY_COLOR] = cols
	var qm := ArrayMesh.new()
	qm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.use_colors = true
	hm.use_custom_data = true
	hm.mesh = qm
	_halo = MultiMeshInstance3D.new()
	_halo.multimesh = hm
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = load("res://shaders/helmet_glow.gdshader")
	_halo.material_override = _halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(3000, 600, 3000))
	add_child(_halo)
	var pst := SurfaceTool.new()
	pst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pq := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	var puv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in [0, 1, 2, 0, 2, 3]:
		pst.set_color(Color(1, 1, 1, 1))
		pst.set_uv(puv[k])
		pst.set_normal(Vector3.UP)
		pst.add_vertex(pq[k])
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_colors = true
	sm.use_custom_data = true
	sm.mesh = pst.commit()
	_spot = MultiMeshInstance3D.new()
	_spot.multimesh = sm
	_spot_mat = ShaderMaterial.new()
	_spot_mat.shader = load("res://shaders/light_pool.gdshader")
	_spot_mat.render_priority = 1
	_spot.material_override = _spot_mat
	_spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spot.custom_aabb = _halo.custom_aabb
	add_child(_spot)

func _sync_lamps(list: Array) -> void:
	if _halo == null:
		return
	var night: float = float(view.sky.night) if view.sky != null else 0.0
	var on: bool = night > 0.25 and not list.is_empty()
	_halo.visible = on
	_spot.visible = on
	if not on:
		return
	_halo_mat.set_shader_parameter("intensity", smoothstep(0.25, 0.8, night))
	# Critic round 6: close in (below 15 m) the ground pool is half the size and brightness.
	var kz: float = lerpf(0.5, 1.0, smoothstep(13.0, 17.0, float(view.camera_distance)))
	_spot_mat.set_shader_parameter("intensity", smoothstep(0.25, 0.8, night) * 0.5 * kz)
	var n: int = list.size()
	var hb := PackedFloat32Array()
	hb.resize(n * 20)
	var sb := PackedFloat32Array()
	sb.resize(n * 20)
	var k := 0
	for it in list:
		var rec: Dictionary = it[0]
		var lib: Dictionary = it[1]
		var body := Transform3D(Basis(Vector3.UP, float(rec["yaw"])), _dp(rec))
		var hi: int = int(lib.get("head_bone", -1))
		var hp := Vector3(0.14, 1.66, 0.0)
		if hi >= 0:
			var pz: Dictionary = rec["sm"].pose()
			var g: Transform3D = bone_at(lib, int(row_of(lib, pz["a"], pz["ta"])), hi)
			hp = g.origin + Vector3(0.16, 0.1, 0.0)
		var w: Vector3 = body * hp
		var dead: bool = bool(rec["dead"])
		# Critic round 13: the halo grows with the camera distance, so a suited body (a black
		# inspector too) can be found at night at 45 m.
		var sz: float = 0.0 if dead else 0.55 * clampf(float(view.camera_distance) / 16.0, 1.0, 3.2)
		_put(hb, k, Transform3D(Basis(), w), Color(1.0, 0.93, 0.78), Color(sz, 0, 0, 0))
		var ground: Vector3 = body * Vector3(2.0, 0.04, 0.0)
		ground.y = view.h(ground.x, ground.z) + 0.05 if rec["var"] == "suit" else ground.y
		_put(sb, k, Transform3D(Basis(), ground), Color(1.0, 0.9, 0.72), Color(0.0 if dead else 1.9 * kz, 0, 0, 0))
		k += 20
	var m1: MultiMesh = _halo.multimesh
	var m2: MultiMesh = _spot.multimesh
	if m1.instance_count != n:
		m1.instance_count = n
		m2.instance_count = n
	if n > 0:
		m1.buffer = hb
		m2.buffer = sb

static func _put(buf: PackedFloat32Array, k: int, xf: Transform3D, c: Color, cu: Color) -> void:
	var b: Basis = xf.basis
	buf[k] = b.x.x
	buf[k + 1] = b.y.x
	buf[k + 2] = b.z.x
	buf[k + 3] = xf.origin.x
	buf[k + 4] = b.x.y
	buf[k + 5] = b.y.y
	buf[k + 6] = b.z.y
	buf[k + 7] = xf.origin.y
	buf[k + 8] = b.x.z
	buf[k + 9] = b.y.z
	buf[k + 10] = b.z.z
	buf[k + 11] = xf.origin.z
	buf[k + 12] = c.r
	buf[k + 13] = c.g
	buf[k + 14] = c.b
	buf[k + 15] = c.a
	buf[k + 16] = cu.r
	buf[k + 17] = cu.g
	buf[k + 18] = cu.b
	buf[k + 19] = cu.a

var _pm := {}
var _pm_t := 0
func _prof_mark(k: String) -> void:
	var now: int = Time.get_ticks_usec()
	_pm[k] = int(_pm.get(k, 0)) + (now - _pm_t)
	_pm_t = now

## "now": change the clothes at once; "hold": keep them (walking to a suit anchor, or the
## suit_swap clip before its cut frame).
func _swap_rule(rec: Dictionary, want: String, lg, dt: float) -> String:
	rec["var_hold"] = float(rec.get("var_hold", 0.0)) + dt
	var sm = rec["sm"]
	if rec.has("swap"):
		var pz: Dictionary = sm.pose()
		if String(pz["a"]) == "suit_swap" and float(pz["ta"]) < SWAP_CUT and float(rec["var_hold"]) < 8.0:
			return "hold"
		rec.erase("swap")
		rec.erase("var_hold")
		stats_slots["swaps"] = int(stats_slots.get("swaps", 0)) + 1
		return "now"
	# Never indoor clothes out on the ground: keep the suit until the body is inside.
	if want == "in" and not bool(rec["dead"]) and String(planner.region_of(rec["pos"], true)["k"]) == "out":
		return "hold"
	# Not in an airlock, or held too long (a body that never reaches a suit anchor): at once.
	if bool(rec["dead"]) or float(rec["var_hold"]) > 12.0 or not view.airlock.inside_lock(rec["pos"]):
		rec.erase("var_hold")
		return "now"
	if lg != null and String(lg.get("zone", "")) == "suit" and (rec["pos"] as Vector3).distance_to(lg["pos"]) < 0.3 and float(rec["speed"]) < 0.3 and sm.pose_state == "stand":
		if not sm.has("suit_swap"):
			rec.erase("var_hold")
			return "now"
		sm.play_oneshot("suit_swap")
		rec["swap"] = true
		return "hold"
	return "hold"

func _update_body(a: Dictionary, rec: Dictionary, lib: Dictionary, dt: float, dead: bool) -> void:
	_pm_t = Time.get_ticks_usec()
	var sm = rec["sm"]
	# Fade out, move, fade in (V3_1 §4.3: a jump over 25 m is never a slide).
	if rec.has("fade_to"):
		rec["fade"] = float(rec.get("fade", 1.0)) - dt / 0.15
		if float(rec["fade"]) <= 0.0:
			rec["fade"] = 0.0
			rec["pos"] = rec["fade_to"]
			rec.erase("fade_to")
			if rec.has("fade_var"):
				# (unseen: a late airlock rider is suited in the fade)
				rec["force_var"] = rec["fade_var"]
				rec["var"] = rec["fade_var"]
				rec.erase("fade_var")
			if rec.has("swap") or String(sm.pose()["a"]) == "suit_swap":
				rec.erase("swap")
				sm.end_oneshot()
			rec["wp"] = []
			rec.erase("wp_goal")
			rec["v"] = 0.0
	elif float(rec.get("fade", 1.0)) < 1.0:
		rec["fade"] = minf(1.0, float(rec["fade"]) + dt / 0.15)
	var pos: Vector2 = a["pos"]
	rec["id"] = int(a["id"])
	rec["visitor"] = String(a.get("kind", "")) == "visitor"
	var inside: bool = a["where"] != "out"
	var bld: int = int(a.get("bld", -1))
	var blds: Dictionary = sim.state["buildings"]
	# Target from the simulation.
	var y: float = view.h(pos.x, pos.y)
	if inside and blds.has(bld):
		var bb: Dictionary = blds[bld]
		if (bb["pos"] as Vector2).distance_to(pos) <= float(bb["radius"]) + 0.2:
			y = _floor_y(bb)
			if bb["def"] == "lander":
				y += 1.6
			# V5 §7 multi-storey buildings: the person walks on their floor (SIM floors.agent_floor), at that
			# floor's top in the MODEL (the super dome's floors are 5.0 / 4.2 m apart, SIM's floor_height is 6:
			# people on floor 4 stood 6.2 m above it; the plaza is 0.30 m up, not 0.14; 2026-10-02).
			if int(sim.bdef(bb["def"]).get("floors", 1)) > 1 and sim.get("floors") != null:
				var fa: Dictionary = sim.floors.agent_floor(a)
				if int(fa.get("building", -1)) == bld:
					y = level_y(bb, int(fa.get("floor", 0)), float(fa.get("height", 0.0)))
				else:
					y = level_y(bb, 0, 0.0)
		else:
			y = view.h(pos.x, pos.y) + 0.05 + FLOOR_Z
	var spread := Vector3(sin(float(a["id"]) * 2.4), 0, cos(float(a["id"]) * 2.4)) * (0.35 if inside else 0.2)
	var target := Vector3(pos.x, y, pos.y) + spread
	# Airlock riders and queues (fx_airlock, V3_1 §5.3): chamber, suit and porch places.
	var lg = view.airlock.goals.get(int(a["id"])) if view.airlock != null and not dead else null
	if lg != null:
		target = lg["pos"]
		rec["lockg"] = lg
	else:
		rec.erase("lockg")
	# Furniture use (§6).
	# The simulation changes only on its ticks (10 a second): between two ticks the use and the
	# target are the ones of the last frame (colonist cost, V3.1 milestone 4).
	var tick_now: int = int(sim.state["tick"])
	var fresh: bool = int(rec.get("stick", -1)) != tick_now or String(rec["use_key"]) == "retry"
	rec["stick"] = tick_now
	var use: Dictionary = rec.get("use", {}) if not fresh else ({} if dead else _use_of(a))
	var ukey: String = String(rec["use_key"]) if not fresh else ("" if use.is_empty() else "%s:%d:%d:%s:%s" % [use.get("kind", ""), int(use.get("b", -1)), int(use.get("i", 0)), use.get("pose", ""), use.get("act", "")])
	if ukey != rec["use_key"]:
		rec["use_key"] = ukey
		rec["use"] = use
		_release(rec, int(a["id"]))
		if ukey != "":
			var an: Dictionary = _anchor(use)
			if bool(an.get("here", false)):
				an["pos"] = rec["pos"]
				an["yaw"] = rec["yaw"]
			elif not an.is_empty():
				# One body per anchor (critic round 6): a second user waits on a free point.
				var ck: String = "%d:%s:%d" % [int(use.get("b", -1)), String(use.get("kind", "")), int(use.get("i", 0))]
				var holder: int = int(_claims.get(ck, -1))
				if holder != -1 and holder != int(a["id"]) and agents.has(holder) and String(agents[holder].get("claim", "")) == ck:
					an = {}
					rec["wait_claim"] = ck
				else:
					_claims[ck] = int(a["id"])
					rec["claim"] = ck
			if an.is_empty():
				rec["anchor"] = {}
			else:
				rec["anchor"] = an
				rec.erase("wp_goal")
				# (a body at one anchor that is given another one walks there, never jumps)
				if rec["mode"] != "at_anchor" or (rec["pos"] as Vector3).distance_to(an["pos"]) > 0.3:
					rec["mode"] = "to_anchor"
				# A body far away (a loaded game, a staged shot) is placed at once.
				if not bool(rec.get("seen", false)):
					rec["pos"] = an["pos"]
					rec["yaw"] = float(an["yaw"])
					rec["mode"] = "at_anchor"
		if ukey == "" or rec["anchor"].is_empty():
			if rec["mode"] == "at_anchor" or rec["mode"] == "to_anchor":
				rec["mode"] = "leaving"
	_prof_mark("use")
	var before: Vector3 = rec["pos"]
	var now: Vector3 = before
	var want_yaw = null
	var goal: Array = ["stand", "loco"]
	match String(rec["mode"]):
		"to_anchor":
			if rec["anchor"].is_empty():
				rec["mode"] = "follow"
			elif sm.pose_state != "stand" or sm.is_busy():
				# Finish getting up first (a new use while seated elsewhere).
				goal = ["stand", "idle"]
			else:
				var ap: Vector3 = rec["anchor"]["pos"]
				var vmax: float = v_fast() if before.distance_to(ap) > 3.0 else 1.1
				now = _walk(rec, before, ap, dt, vmax, inside or String(rec["var"]) == "in")
				if now.distance_to(ap) < 0.03:
					now = ap
					var ay: float = float(rec["anchor"]["yaw"])
					want_yaw = ay
					goal = ["stand", "idle"]
					if absf(angle_difference(float(rec["yaw"]), ay)) < 0.09:
						rec["mode"] = "at_anchor"
		"at_anchor":
			now = rec["anchor"]["pos"]
			want_yaw = float(rec["anchor"]["yaw"])
			var b0: Dictionary = blds.get(int(rec["use"].get("b", -1)), {})
			goal = _goal_for(rec["use"], b0, bool(rec["anchor"].get("found", false)))
		"leaving":
			# The exit clip plays on the anchor; then the body rejoins the simulation.
			if sm.pose_state != "stand" or sm.is_busy():
				goal = ["stand", "idle"]
				now = before
			else:
				rec["mode"] = "follow"
				rec.erase("wp_goal")
				rec["left_from"] = (rec["anchor"].get("pos", before) if not rec["anchor"].is_empty() else before)
		_:
			pass
	_prof_mark("modes")
	if rec["mode"] == "follow":
		if rec["use_key"] != "" and not rec["anchor"].is_empty():
			rec["mode"] = "to_anchor"
			rec.erase("wp_goal")
		# Inside a room with aisle anchors the body walks the aisles and stops on the aisle
		# nearest the simulation position (the centre of a room is often a table).
		# A body waiting for a held anchor tries again once it is free.
		if rec.has("wait_claim"):
			var wk: String = rec["wait_claim"]
			var hold: int = int(_claims.get(wk, -1))
			if hold == -1 or not agents.has(hold) or String(agents[hold].get("claim", "")) != wk:
				rec["use_key"] = "retry"
		# The room comes from the POSITION, not from a.bld: a colonist who crosses a room on
		# the way to another walks this room's aisles too (critic round 6: a carrier walked
		# through the holo table).
		# The target changes only when the simulation position, the slot or the room
		# changes: cached (it was 1.7 ms a frame for 66 bodies).
		var tfast: Array = [rec.get("slot"), int(rec.get("slot_room", -1)), lg != null, target if lg != null else null]
		var tkey: String = String(rec.get("tkey", ""))
		if fresh or rec.get("tfast") != tfast:
			tkey = "%.2f,%.2f,%s,%d,%s,%s" % [target.x, target.z, str(rec.get("slot", "")), int(rec.get("slot_room", -1)), str(inside), str(lg != null)]
		rec["tfast"] = tfast
		var cached: bool = String(rec.get("tkey", "")) == tkey
		var rid: int = -2 if cached else (_room_at(Vector2(target.x, target.z)) if inside else -1)
		if cached:
			target = rec["tval"]
		elif lg != null:
			rid = -2
		elif rid < 0 and inside:
			rid = _room_at(Vector2(before.x, before.z))
			if rid < 0 and String(planner.region_of(target, true)["k"]) != "tube":
				# The simulation holds the body on a room wall: into that room.
				var rn: int = planner.room_near(target)
				if rn >= 0:
					rid = rn
					target = planner.pull_in(rn, target)
		var room_meta = view.bmeta.get(rid) if rid >= 0 else null
		var aisles: Array = _aisles_of(room_meta) if room_meta != null else []
		if cached or lg != null:
			pass
		elif not aisles.is_empty():
			target.y = _floor_y(blds[rid])
			if rec.has("slot") and int(rec.get("slot_room", -1)) == rid:
				var sl: Vector3 = rec["slot"]
				target = Vector3(sl.x, target.y, sl.z)
				if bool(rec.get("slot_q", false)):
					target = sl
			elif (Vector2(target.x, target.z) - (blds[rid]["pos"] as Vector2)).length() < float(blds[rid]["radius"]) * 0.9:
				var snap: Vector3 = _nearest(_free_aisles(rid, aisles), target)
				target = Vector3(snap.x, target.y, snap.z)
			target = planner.snap_free(rid, planner.pull_in(rid, target))
		elif rid >= 0 and inside:
			# A room without aisles (an airlock): off the wall band, on free floor.
			target = planner.snap_free(rid, planner.pull_in(rid, target))
		elif not inside:
			var ro: int = _room_at(Vector2(target.x, target.z))
			if ro >= 0:
				# A suited body the simulation still holds in an airlock chamber: off its wall.
				target = planner.snap_free(ro, planner.pull_in(ro, target))
			else:
				target = planner.outside_of_structures(target)
		elif inside and rid < 0:
			# In a corridor: on its centre line.
			var tr: Dictionary = planner.region_of(target, true)
			if tr["k"] == "tube":
				var l: Dictionary = blds[int(tr["id"])]
				var a0: Vector2 = l["p0"]
				var ab: Vector2 = (l["p1"] as Vector2) - a0
				var tq: float = clampf((Vector2(target.x, target.z) - a0).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var cp: Vector2 = a0 + ab * tq
				target = Vector3(cp.x, target.y, cp.y)
			else:
				target = planner.indoor_snap(target)
		if not cached:
			rec["tkey"] = tkey
			rec["tval"] = target
		var dist: float = before.distance_to(target)
		_prof_mark("target")
		if forced_goto.has(int(a["id"])):
			# Test staging: walk or run straight to a point at a set speed (frame strips).
			var fg: Array = forced_goto[int(a["id"])]
			var gp: Vector2 = fg[0]
			var gt := Vector3(gp.x, view.h(gp.x, gp.y), gp.y)
			now = before.move_toward(gt, float(fg[1]) * dt * maxf(game_rate, 0.0))
			var rr: int = _room_at(Vector2(now.x, now.z))
			now.y = _floor_y(blds[rr]) if rr >= 0 else view.h(now.x, now.z) + (0.05 + FLOOR_Z if inside else 0.0)
		elif not bool(rec.get("seen", false)) and bool(rec.get("visitor", false)) and view.get("traffic") != null and view.traffic.ramp_near(target, 16.0) != Vector3.INF:
			# A visitor the simulation puts at the pad edge comes down the ramp lane (V3.1).
			now = view.traffic.ramp_near(target, 16.0)
			rec["wp"] = [target]
			rec["wp_goal"] = target
		elif not bool(rec.get("seen", false)) or (lg != null and float(rec.get("age", 0.0)) < 1.0):
			# First frame of a body (a loaded game): it starts where the simulation has it
			# (an airlock rider or queued body: on its airlock place).
			now = target
		elif sm.is_busy() and sm.pose_state == "stand":
			now = before
		else:
			now = _walk(rec, before, target, dt, v_fast() if lg == null or dist > 2.0 else 1.3, inside)
		goal = ["stand", "loco"]
		if lg != null and lg.has("yaw") and now.distance_to(target) < 0.12:
			want_yaw = float(lg["yaw"])
		# (only while the goal itself stands: a body on a task WALK that stopped for one frame stood
		# still until the goal was 0.4 m away, then walked, then stopped: stop-go at 4x, 2026-10-01)
		if not dead and String(a.get("plan_kind", "")) == "task" and float(rec["speed"]) < 0.2 and float(rec.get("g_u", 0.0)) < 0.2 and a["where"] != "lock" and before.distance_to(target) < 0.4:
			var wb: Dictionary = blds.get(bld, {})
			goal = ["stand", "work_console" if not wb.is_empty() and String(wb["def"]) in CONSOLE_DEFS else "work_bench"]
			# A working body stands still (no creep over the last 0.4 m while the work clip plays).
			now = before
		elif not dead and bool(a.get("sleeping", false)) and not inside:
			goal = ["lie", "sleep"]
	_prof_mark("move")
	rec["pos"] = now
	rec["seen"] = true
	rec["age"] = float(rec.get("age", 0.0)) + dt
	var moved: float = Vector2(now.x - before.x, now.z - before.z).length() / maxf(dt, 0.0001)
	rec["speed"] = moved
	if want_yaw != null:
		rec["yaw"] = _turn(float(rec["yaw"]), float(want_yaw), dt)
	elif moved > 0.3:
		var wy: float = -atan2(now.z - before.z, now.x - before.x)
		rec["yaw"] = _turn(float(rec["yaw"]), wy, dt)
	# Critic round 3: a suited colonist never lies in a bed, and never eats (glove to a
	# closed visor): stand at the bed, sit idle at the table.
	if rec["var"] == "suit" and not dead:
		if goal[0] == "lie":
			goal = ["stand", "idle"]
		elif goal[1] == "sit_eat":
			goal = [goal[0], "sit_idle"]
	# Standing about: now and then look round (idle_look), deterministic per colonist.
	sm.idle_clip = "idle_look" if int(floor((view._time + float(a["id"]) * 3.7) / 8.0)) % 3 == 1 else "idle"
	# Cheer for a new award, if standing free.
	if float(rec.get("cheer_in", -1.0)) >= 0.0:
		rec["cheer_in"] = float(rec["cheer_in"]) - dt
		if float(rec["cheer_in"]) < 0.0:
			if not dead and sm.settled_in("stand") and float(rec["speed"]) < 0.2 and rec["mode"] == "follow":
				sm.play_oneshot("cheer")
			rec["cheer_in"] = -1.0
	# V5 shows (SIM 2026-10-01, sim.people.action): a fight, a dance (the Konami egg too), an escort, a
	# class, a venue act. A stand or sit loop replaces the goal's loop in the same pose (a walking body
	# keeps walking); the cuffed and escort walks replace the walk cycle; fall_down plays once and holds
	# until the action ends (then get_up). Clips of the stool, bunk, lounger and water poses are not
	# drawn yet (no enter / exit clips for those poses).
	var act: String = ""
	if not dead and bool(lib.get("people", false)):
		act = _action_cached(a, rec)
		if float(rec.get("egg_until", -1.0)) > view._time:
			act = "dance_c"
	sm.walk_override = act if act in WALK_ACTS and sm.has(act) else ""
	if act == "fall_down" and sm.has("fall_down"):
		if not bool(rec.get("knocked", false)):
			rec["knocked"] = true
			sm.play_oneshot("fall_down")
	elif bool(rec.get("knocked", false)):
		rec["knocked"] = false
		sm.revive()
	elif act != "" and sm.has(act) and not (act in WALK_ACTS) and not (act in ACT_UNREACHED):
		var ap: String = String(ACT_POSE.get(act, "stand"))
		if goal[0] == ap and (goal[1] != "loco" or float(rec["speed"]) < 0.2):
			goal = [ap, act]
		elif ap == "stand" and goal[1] == "loco" and float(rec["speed"]) < 0.2:
			goal = ["stand", act]
	rec["act"] = act
	# Pose machine.
	if dead:
		if not bool(rec["dead"]):
			rec["dead"] = true
			sm.play_oneshot("collapse")
	else:
		rec["dead"] = false
		sm.set_goal(goal[0], goal[1])
	# Speeds and clip time in GAME seconds (the body moves in real time on screen).
	var gr: float = maxf(game_rate, 0.0)
	sm.speed = float(rec["speed"]) / maxf(gr, 0.05) if gr > 0.02 else 0.0
	sm.injured = float(a.get("health", 100.0)) < 35.0
	var cargo: Dictionary = sim.inv.get_inv(a["inv"]).get("items", {}) if int(a.get("inv", -1)) != -1 else {}
	sm.carry = not cargo.is_empty() and not dead
	sm.advance(minf(dt * gr, 0.25))
	_prof_mark("pose")
	_sync_crate(rec, lib, cargo, dead)
	_prof_mark("crate")

const WALK_ACTS := ["handcuffed_walk", "escort_walk"]
const ACT_POSE := {"sit_class": "sit", "sit_bench": "sit"}
const ACT_UNREACHED := ["drink_bar", "sit_bar_stool", "sleep_cell", "lounge_pool", "swim"]

## sim.people.action(a), asked once per simulation tick per person (it walks the plan and the venues).
func _action_cached(a: Dictionary, rec: Dictionary) -> String:
	var tk: int = int(sim.state["tick"])
	if int(rec.get("act_tick", -1)) == tk:
		return String(rec.get("act_v", ""))
	var pp = sim.get("people")
	var v: String = String(pp.action(a)) if pp != null and pp.has_method("action") else ""
	rec["act_tick"] = tk
	rec["act_v"] = v
	return v

## The Konami dance (UI calls view.egg_dance, V5 4.5): the person and everyone within 6 m indoors dance
## for 12 s at once (SIM's own "dance" mod follows on its next tick).
func egg_dance(id: int) -> int:
	if not agents.has(id):
		return 0
	var c: Vector3 = agents[id]["pos"]
	var n := 0
	for k in agents:
		var r: Dictionary = agents[k]
		if String(r.get("var", "")) == "in" and (r["pos"] as Vector3).distance_to(c) < 6.0:
			r["egg_until"] = view._time + 12.0
			n += 1
	return n

## Turn with easing, at most 300 deg/s of GAME time (V3_1 §4.1): facing never snaps.
func _turn(y0: float, y1: float, dt: float) -> float:
	var d: float = angle_difference(y0, y1)
	var dtg: float = dt * maxf(game_rate, 0.0)
	var step: float = clampf(d * (1.0 - exp(-dtg * 9.0)), -TURN * dtg, TURN * dtg)
	return y0 + step

## Aisle points of a room that stand on free floor (cached per room).
func _free_aisles(rid: int, aisles: Array) -> Array:
	var meta: Dictionary = view.bmeta[rid]
	if meta.has("aisles_free"):
		return meta["aisles_free"]
	var out: Array = []
	for q in aisles:
		if planner.free_in_room(rid, q):
			out.append(q)
	if out.is_empty():
		out = aisles
	meta["aisles_free"] = out
	return out

## The walker (V3_1 §4.1-4.3): follows a planned path (fx_npc_path) to `goal` with a
## speed ramp (ACCEL), a look-ahead carrot that rounds the corners, and no jumps: a gap
## over FADE_GAP fades out and in. Returns the new position.
func _walk(rec: Dictionary, before: Vector3, goal: Vector3, dt: float, vmax: float, inside: bool) -> Vector3:
	var tw0: int = Time.get_ticks_usec()
	var r: Vector3 = _walk2(rec, before, goal, dt, vmax, inside)
	# An airlock door that is not open yet: wait at it (never walk through a closed leaf).
	if door_gate and r != before and view.airlock != null and not rec.has("fade_to") and view.airlock.door_blocks(before, r):
		rec["v"] = 0.0
		_t_walk += Time.get_ticks_usec() - tw0
		return before
	# Critic round 14: two bodies never pass through each other in a doorway; one waits.
	rec.erase("v_cap")
	rec.erase("yield_same")
	if door_yield and r != before and _door_yield(rec, before, r, dt):
		rec["v"] = 0.0
		# The one who waits steps aside (up to 0.55 m, on free floor), off the other's way; behind a
		# leader going the same way it only waits.
		r = before if bool(rec.get("yield_same", false)) else _step_aside(rec, before, r, dt, inside)
	else:
		rec["yielding"] = false
		rec["yield_t"] = 0.0
		rec.erase("yield_at")
	if r != before:
		rec["vdir"] = Vector2(r.x - before.x, r.z - before.z).normalized()
	_t_walk += Time.get_ticks_usec() - tw0
	return r

var door_yield := true      # (tests can turn it off to measure)
## The walker's top speed: above the sim's walking speed so the drawn body never falls behind
## (v3 rules 3.6 / 3.2 m/s: 3.4 as before; V4 new games cap 4.0 indoors, 3.5 outside: 4.2).
func v_fast() -> float:
	return 4.2 if (view.sim.state as Dictionary).has("rules") else 3.4

var door_gate := true       # airlock door gate (tests can turn it off to measure)

func _step_aside(rec: Dictionary, before: Vector3, next: Vector3, dt: float, inside: bool) -> Vector3:
	var dir := Vector2(next.x - before.x, next.z - before.z).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var op: Vector3 = rec.get("yield_from", before)
	if Vector2(op.x - before.x, op.z - before.z).dot(perp) > 0.0:
		perp = -perp
	var base: Vector3 = rec.get("yield_at", before)
	if not rec.has("yield_at"):
		rec["yield_at"] = before
		base = before
	var want := Vector3(base.x + perp.x * 0.55, before.y, base.z + perp.y * 0.55)
	var reg0: Dictionary = planner.region_of(before, inside)
	var reg1: Dictionary = planner.region_of(want, inside)
	if reg0["k"] != reg1["k"] or reg0.get("id", -1) != reg1.get("id", -1):
		return before
	if reg1["k"] == "room" and not planner.free_in_room(int(reg1["id"]), want):
		return before
	# 2026-09-27 (path check, one run in two: 16 samples): a body waiting in a corridor end stepped
	# aside into the wall band of the room the corridor meets. Never step into a room wall band.
	if _in_wall_band(want):
		return before
	# (0.25 m/s: slower than the slide limit of a standing clip; path check 2026-09-27: 0.57 m/s)
	return before.move_toward(want, 0.25 * dt * maxf(game_rate, 0.0))

## True when p lies within 0.45 m of a room's wall line (the path check's band is 0.25 m).
func _in_wall_band(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	var blds: Dictionary = view.sim.state["buildings"]
	for rid in view.bmeta:
		var b = blds.get(rid)
		if b == null or String(b["kind"]) != "room":
			continue
		var rr: float = float(b["radius"])
		var d: float = q.distance_to(b["pos"])
		if d > rr + 1.0:
			continue
		var s: float = float(view.bmeta[rid]["tpl"].get("scale", 1.0)) if view.bmeta[rid].has("tpl") else 1.0
		if absf(d - (rr - 0.20 * s)) < 0.45:
			return true
	return false
const DOOR_ZONE := 1.1     # m round a doorway centre
const BODY_GAP := 0.45     # m between two bodies in a doorway
var _occ := {}             # 1 m cell -> [agent ids] (walker positions, this frame)
var _dgrid := {}           # 4 m cell -> [door points]
var _dgrid_n := -1

var _alk_pts := {}
func _airlock_pt(v: Vector3) -> bool:
	return _alk_pts.has(Vector3i(int(round(v.x * 10.0)), 0, int(round(v.z * 10.0))))

func _build_occ() -> void:
	_occ = {}
	for id in agents:
		var p: Vector3 = agents[id]["pos"]
		var k: int = int(floor(p.x)) * 8192 + int(floor(p.z))
		if not _occ.has(k):
			_occ[k] = []
		(_occ[k] as Array).append(id)
	var pts: Array = []
	if view.doors != null:
		for d in view.doors.doors:
			pts.append(d["pos"])
	_n_room_doors = pts.size()
	if view.get("airlock") != null:
		for bid in view.airlock.locks:
			var m = view.bmeta.get(bid)
			if m != null and m.has("lockgeo") and bool(m["lockgeo"].get("kit", false)):
				pts.append(m["lockgeo"]["door_in"])
				pts.append(m["lockgeo"]["door_out"])
				for q0 in [m["lockgeo"]["door_in"], m["lockgeo"]["door_out"]]:
					_alk_pts[Vector3i(int(round((q0 as Vector3).x * 10.0)), 0, int(round((q0 as Vector3).z * 10.0)))] = true
	if pts.size() != _dgrid_n:
		_dgrid_n = pts.size()
		_dgrid = {}
		for q in pts:
			var v: Vector3 = q
			var k2: int = int(floor(v.x / 4.0)) * 4096 + int(floor(v.z / 4.0))
			if not _dgrid.has(k2):
				_dgrid[k2] = []
			(_dgrid[k2] as Array).append(v)

var _n_room_doors := 0
func _door_near(p: Vector3, rooms_only: bool = false):
	var cx: int = int(floor(p.x / 4.0))
	var cz: int = int(floor(p.z / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q in _dgrid.get((cx + dx) * 4096 + cz + dz, []):
				var v: Vector3 = q
				if Vector2(v.x - p.x, v.z - p.z).length() < DOOR_ZONE:
					if rooms_only and _airlock_pt(v):
						continue
					return v
	return null

## True: this body waits this frame. Rules at a doorway: keep BODY_GAP behind a body going the
## same way; give way to a body coming the other way that is nearer the doorway centre; wait
## for a body standing in the doorway (at most 3 s, then pass: separation moves them apart).
func _door_yield(rec: Dictionary, before: Vector3, now: Vector3, dt: float) -> bool:
	var dp = _door_near(now, true)
	if dp == null:
		return false
	var me: int = int(rec.get("id", -1))
	var dir := Vector2(now.x - before.x, now.z - before.z).normalized()
	var cx: int = int(floor(now.x))
	var cz: int = int(floor(now.z))
	var wait := false
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for oid in _occ.get((cx + dx) * 8192 + cz + dz, []):
				if int(oid) == me or not agents.has(oid):
					continue
				var o: Dictionary = agents[oid]
				if bool(o["dead"]) or String(o["sm"].pose_state) != "stand" or bool(o.get("yielding", false)):
					continue
				var op: Vector3 = o["pos"]
				var d_now: float = Vector2(op.x - now.x, op.z - now.z).length()
				var to_o := Vector2(op.x - before.x, op.z - before.z)
				if to_o.length() > 2.2 or to_o.dot(dir) <= 0.0:
					continue
				var od: Vector2 = o.get("vdir", Vector2.ZERO)
				var moving: bool = float(o.get("speed", 0.0)) > 0.15
				var o_door: float = Vector2(op.x - dp.x, op.z - dp.z).length()
				if moving and od.dot(dir) > 0.3:
					# Same way: keep the gap. Close behind, walk at the leader's pace (next frame's top
					# speed) instead of stop - ramp - catch up - stop (walk / idle flicker at doorways,
					# 2026-10-01); a hard stop only inside the gap, and no step aside behind a leader.
					if d_now < BODY_GAP + 0.35:
						rec["v_cap"] = float(o.get("v", 0.0))
					if d_now < BODY_GAP:
						wait = true
						rec["yield_same"] = true
				elif moving:
					# Coming the other way: whoever is nearer the doorway centre goes first.
					var me_door: float = Vector2(before.x - dp.x, before.z - dp.z).length()
					if o_door < DOOR_ZONE and (o_door < me_door or (absf(o_door - me_door) < 0.05 and int(oid) < me)):
						wait = true
				elif d_now < BODY_GAP and o_door < DOOR_ZONE:
					wait = float(rec.get("yield_t", 0.0)) < 3.0
				if wait:
					rec["yield_from"] = op
					break
			if wait:
				break
		if wait:
			break
	if wait:
		rec["yielding"] = true
		rec["yield_t"] = float(rec.get("yield_t", 0.0)) + dt
		stats_slots["door_waits"] = int(stats_slots.get("door_waits", 0)) + 1
	return wait

func _walk2(rec: Dictionary, before: Vector3, goal: Vector3, dt: float, vmax: float, inside: bool) -> Vector3:
	var gr: float = maxf(game_rate, 0.0)
	var dtg: float = dt * gr
	if dtg <= 0.0:
		return before
	if float(rec.get("fade", 1.0)) < 1.0 or rec.has("fade_to"):
		return before
	var gap: float = Vector2(goal.x - before.x, goal.z - before.z).length()
	if gap > FADE_GAP:
		rec["fade_to"] = goal
		rec["wp"] = []
		rec.erase("wp_goal")
		return before
	var wp: Array = rec.get("wp", [])
	var pend: Vector3 = rec.get("wp_goal", Vector3.INF)
	# A goal that moved but is still in sight of the last corner, in the same region, only
	# moves the path's end (no new plan).
	if pend != Vector3.INF and pend.distance_to(goal) > 0.8 and not wp.is_empty():
		var corner: Vector3 = wp[wp.size() - 2] if wp.size() > 1 else before
		if planner.same_leg(pend, goal, inside) and planner.same_leg(corner, goal, inside):
			wp[-1] = goal
			rec["wp_goal"] = goal
			pend = goal
	# A path walked to its end while the goal moved on in plain sight: on to the goal, no plan. At 4x
	# the plan budget ran out on most frames and such a body stood still every other frame (stop-go).
	if wp.is_empty() and gap > 0.05 and gap < 6.0 and pend != Vector3.INF and planner.same_leg(before, goal, inside):
		wp = [goal]
		rec["wp_goal"] = goal
		pend = goal
	# The person in the follow view always gets a plan (the budget is for the crowd).
	var pri: bool = int(rec.get("id", -1)) == _follow_id
	if pend.distance_to(goal) > 0.8 or (wp.is_empty() and gap > 0.05):
		if (_plans_frame < PLANS_PER_FRAME and _plan_us < plan_budget_us) or wp.is_empty() and gap < 1.5 or pri:
			_plans_frame += 1
			var tq0: int = Time.get_ticks_usec()
			wp = _round_corners(before, _trim_start(rec, before, planner.plan(before, goal, inside), inside))
			_plan_us += Time.get_ticks_usec() - tq0
			rec["wp_goal"] = goal
			rec["wpq"] = planner.quality
		elif wp.is_empty():
			rec["v"] = move_toward(float(rec.get("v", 0.0)), 0.0, ACCEL * dtg)
			return before
	elif not wp.is_empty() and (wp[-1] as Vector3).distance_to(goal) > 0.25:
		# The end drifts with the simulation: move it only when the last leg stays clear.
		var lc: Vector3 = wp[wp.size() - 2] if wp.size() > 1 else before
		if planner.same_leg(lc, goal, inside):
			wp[-1] = goal
			# (the path now ends at the goal: no re-plan when the goal is 0.8 m past the old plan's end)
			rec["wp_goal"] = goal
		elif (_plans_frame < PLANS_PER_FRAME and _plan_us < plan_budget_us) or pri:
			_plans_frame += 1
			var tq1: int = Time.get_ticks_usec()
			wp = _round_corners(before, _trim_start(rec, before, planner.plan(before, goal, inside), inside))
			_plan_us += Time.get_ticks_usec() - tq1
			rec["wp_goal"] = goal
			rec["wpq"] = planner.quality
	rec["wp"] = wp
	if wp.is_empty():
		rec["v"] = 0.0
		return before
	# Remaining length; the speed ramps up and down (ACCEL, game time).
	var remaining := 0.0
	var prev: Vector3 = before
	for q in wp:
		remaining += (q as Vector3).distance_to(prev)
		prev = q
	# The path's end moves to the goal only after the goal drifted 0.25 m (above): the rest of the
	# way to the goal counts too, so `remaining` grows on every step of the goal, not every 2nd-3rd.
	remaining += Vector2(goal.x - prev.x, goal.z - prev.z).length()
	# The goal is the simulation's position: it moves only on the 10 Hz ticks, in steps. Between two
	# steps `remaining` shrinks as the body walks, so the stopping curve below slowed the body on
	# every frame and the next step sped it up again (10-15 % speed ripple at 10 Hz, 2026-10-01).
	# The goal's own speed (its step over the ticks it took) times the game time since the last tick
	# (world_view.tick_age, from main.gd's tick clock) is added back: for a goal that walks at a
	# steady pace the effective distance is steady, at 1x and at 4x (several ticks in one frame).
	var tick_now: int = int(sim.state["tick"])
	var gprev: Vector3 = rec.get("g_prev", goal)
	var gtk: int = int(rec.get("g_tick", tick_now))
	var gu: float = float(rec.get("g_u", 0.0))
	var gstep: float = Vector2(goal.x - gprev.x, goal.z - gprev.z).length()
	if gstep > 0.002:
		var nt: int = maxi(tick_now - gtk, 1)
		gu = lerpf(gu, minf(gstep / (float(nt) * _tick_s), vmax), 0.5)
		rec["g_tick"] = tick_now
	elif tick_now - gtk > 3:
		gu = 0.0
	if not rec.has("g_tick"):
		rec["g_tick"] = tick_now
	rec["g_prev"] = goal
	rec["g_u"] = gu
	var ta = view.get("tick_age")
	var rem_eff: float = remaining + gu * (clampf(float(ta), 0.0, _tick_s) if ta != null else 0.0)
	if rec.has("v_cap"):
		# Behind a leader in a doorway: its pace; a leader that barely moves (under 0.25 m/s) is a stop,
		# not a creep (a creep at 0.03-0.3 m/s gave walk / idle / walk behind it, 2026-10-01).
		var vc: float = float(rec["v_cap"])
		vmax = minf(vmax, vc if vc >= 0.25 else 0.0)
	var v: float = float(rec.get("v", 0.0))
	# Speed changes: ACCEL (game time); for the followed person at 2x-4x at most FOLLOW_VIEW_ACCEL on screen.
	var acc: float = ACCEL
	if pri and gr > 1.0:
		acc = minf(ACCEL, FOLLOW_VIEW_ACCEL / (gr * gr))
	var vdes: float = minf(vmax, sqrt(2.0 * acc * rem_eff) + 0.05)
	# Bends ahead (2026-10-02): at most sqrt(A_LAT x radius) on each bend, braking at `acc` before it.
	# A runner took a 0.4 m corner at 3.4 m/s (3 g sideways; at 4x the follow camera swung through the body).
	vdes = minf(vdes, _bend_cap(before, wp, acc))
	if vdes > v:
		v = move_toward(v, vdes, acc * dtg)
	else:
		# Slow down at DECEL at most (a new slower top speed near an anchor dropped 3.4 -> 1.1 m/s in
		# one frame), but always fast enough to stop on the path's end.
		v = maxf(vdes, v - DECEL * dtg)
		v = minf(v, sqrt(2.0 * DECEL * remaining) + 0.05)
	rec["v"] = v
	# Move exactly along the (corner-rounded) polyline: a long frame step never cuts a corner.
	var left: float = v * dtg
	var now: Vector3 = before
	while left > 0.0 and not wp.is_empty():
		var q: Vector3 = wp[0]
		var d: float = now.distance_to(q)
		if d <= left:
			now = q
			left -= d
			wp.pop_front()
		else:
			now = now + (q - now) / d * left
			left = 0.0
	# The path ran out inside this frame while the goal is a little further on in plain sight (the
	# path's end follows the goal in 0.25 m steps): walk on to it (the body stopped dead for a frame).
	if left > 0.001 and wp.is_empty():
		var dg: float = Vector2(goal.x - now.x, goal.z - now.z).length()
		if dg > 0.01 and dg < 1.0 and planner.same_leg(now, goal, inside):
			now = now.move_toward(goal, left)
	rec["wp"] = wp
	return now

## The highest speed (game m/s) that still lets the body take every bend of `wp` within LOOK_AHEAD at
## sqrt(A_LAT x bend radius), braking at `acc`. The radius of a sampled curve is its segment length over
## its turn angle.
func _bend_cap(before: Vector3, wp: Array, acc: float) -> float:
	var cap := INF
	if wp.size() < 2:
		return cap
	var s := 0.0
	var p0: Vector3 = before
	for k in wp.size() - 1:
		var p1: Vector3 = wp[k]
		var p2: Vector3 = wp[k + 1]
		var a := Vector2(p1.x - p0.x, p1.z - p0.z)
		var b := Vector2(p2.x - p1.x, p2.z - p1.z)
		var la: float = a.length()
		var lb: float = b.length()
		s += la
		if s > LOOK_AHEAD:
			break
		if la > 0.005 and lb > 0.005:
			var th: float = absf(a.angle_to(b))
			if th > 0.02:
				var r: float = minf(maxf(la, 0.12), maxf(lb, 0.12)) / th
				var vc: float = sqrt(A_LAT * r)
				cap = minf(cap, sqrt(vc * vc + 2.0 * acc * s))
		p0 = p1
	return maxf(cap, 0.6)

## A new plan for a body that is already walking starts at a grid point near it, often a little
## behind or beside it: the body stepped back 0.3 m and turned 30-60 deg for one frame (follow view,
## 2026-10-01, 4x). Points behind the walking direction and under 0.6 m away are dropped while the
## next point is in plain sight (same leg).
func _trim_start(rec: Dictionary, before: Vector3, pts: Array, inside: bool) -> Array:
	var vd = rec.get("vdir")
	if vd == null or float(rec.get("v", 0.0)) < 0.3:
		return pts
	var d0: Vector2 = vd
	while pts.size() >= 2:
		var q: Vector3 = pts[0]
		var dq := Vector2(q.x - before.x, q.z - before.z)
		if dq.length() > 0.6 or dq.dot(d0) > 0.0:
			break
		if not planner.same_leg(before, pts[1], inside):
			# (no clear line to the next point, e.g. across a doorway: join the first leg at its point
			# nearest the body instead of walking back to its start; 2026-10-01, a body walked back and
			# forth 0.1 m a frame on every re-plan)
			var j: Vector3 = Geometry3D.get_closest_point_to_segment(before, q, pts[1])
			if j.distance_to(q) > 0.02:
				pts[0] = j
			break
		pts.pop_front()
	return pts

## Rounds every corner of a path (start `s`, then the points) with a curve of radius up to
## CARROT (0.4 m, V3_1 §4.1): quadratic curves sampled every ~0.12 m, inside the corner.
func _round_corners(s: Vector3, pts: Array) -> Array:
	if pts.size() < 2:
		return pts
	var all: Array = [s]
	all.append_array(pts)
	var out: Array = []
	for i in range(1, all.size()):
		var c: Vector3 = all[i]
		if i == all.size() - 1:
			out.append(c)
			break
		var a: Vector3 = all[i - 1]
		var b: Vector3 = all[i + 1]
		var li: float = a.distance_to(c)
		var lo: float = c.distance_to(b)
		if li < 0.01 or lo < 0.01:
			out.append(c)
			continue
		var u: Vector3 = (c - a) / li
		var w: Vector3 = (b - c) / lo
		var cosang: float = clampf(u.dot(w), -1.0, 1.0)
		var th: float = acos(cosang)
		if th < deg_to_rad(1.0):
			out.append(c)
			continue
		# (2026-10-02) Small bends are rounded too, with a longer curve that stays within CORNER_DEV of the
		# corner: an unrounded 2-8 deg bend turned the walk direction in one frame (at 4x 20-70 mm body jerk).
		var th2: float = tan(th * 0.5)
		var tt: float = minf(maxf(CARROT * th2, minf(0.6, 2.0 * CORNER_DEV / maxf(th2, 0.001))), minf(li, lo) * 0.45)
		var p0: Vector3 = c - u * tt
		var p2: Vector3 = c + w * tt
		var n: int = maxi(2, int(ceil((tt * 2.0) / 0.12)))
		for k in n + 1:
			var f: float = float(k) / n
			out.append(p0.lerp(c, f).lerp(c.lerp(p2, f), f))
	return out
## World positions (floor height) of a room's Anchor_Aisle_<i> points (cached per room).
func _aisles_of(meta: Dictionary) -> Array:
	if meta.has("aisles_w"):
		return meta["aisles_w"]
	var out: Array = []
	var fy: float = (meta["xf"] as Transform3D).origin.y + FLOOR_Z * Models.scale3(meta["tpl"]).y
	for an in meta["anchors"]:
		if String(an).begins_with("Aisle_"):
			var p: Vector3 = (meta["anchors"][an] as Transform3D).origin
			# An airlock's chamber is not a room to stroll through (V3_1 §5.3): suit room only.
			if String(meta.get("def", "")) == "airlock" and view.airlock != null:
				var lg0: Dictionary = view.airlock._geo(-1, meta)
				if bool(lg0.get("kit", false)) and view.airlock._local_x(lg0, p) > float(lg0["inner_x"]) - 0.3:
					continue
			out.append(Vector3(p.x, fy, p.z))
	meta["aisles_w"] = out
	return out

static func _nearest(pts: Array, p: Vector3) -> Vector3:
	var best: Vector3 = pts[0]
	for q in pts:
		if (q as Vector3).distance_squared_to(p) < best.distance_squared_to(p):
			best = q
	return best

## Shortest walk from `from` to `to` over the aisle points: two points are joined when they
## are within 1.75 m (ART-HAB P7); an isolated point joins its 2 nearest.
func _aisle_route(aisles: Array, from: Vector3, to: Vector3) -> Array:
	var n: int = aisles.size()
	var a1: int = 0
	var a2: int = 0
	for i in n:
		if (aisles[i] as Vector3).distance_squared_to(from) < (aisles[a1] as Vector3).distance_squared_to(from):
			a1 = i
		if (aisles[i] as Vector3).distance_squared_to(to) < (aisles[a2] as Vector3).distance_squared_to(to):
			a2 = i
	if from.distance_to(to) < (aisles[a1] as Vector3).distance_to(from) + 0.5:
		return [to]
	# The link graph of a room is built once (it was rebuilt on every route: n^2 log n).
	var hk: int = aisles.hash()
	var nb: Array = _nb_cache.get(hk, [])
	if nb.is_empty():
		for i in n:
			var d: Array = []
			for j in n:
				if j != i:
					d.append([(aisles[i] as Vector3).distance_to(aisles[j]), j])
			d.sort_custom(func(x, y): return x[0] < y[0])
			var near: Array = []
			for e in d:
				if float(e[0]) <= 1.75:
					near.append(e)
			nb.append(near if near.size() > 0 else d.slice(0, 2))
		_nb_cache[hk] = nb
	var dist: Array = []
	dist.resize(n)
	dist.fill(1e9)
	var prev: Array = []
	prev.resize(n)
	prev.fill(-1)
	var done := {}
	dist[a1] = 0.0
	for it in n:
		var u: int = -1
		for i in n:
			if not done.has(i) and (u < 0 or float(dist[i]) < float(dist[u])):
				u = i
		if u < 0 or float(dist[u]) >= 1e9:
			break
		done[u] = true
		for e in nb[u]:
			var v: int = e[1]
			if float(dist[u]) + float(e[0]) < float(dist[v]):
				dist[v] = float(dist[u]) + float(e[0])
				prev[v] = u
		for e in nb:
			pass
	var out: Array = [to]
	var k: int = a2
	while k >= 0:
		out.push_front(aisles[k])
		if k == a1:
			break
		k = prev[k]
	return out

func _path_to(from: Vector3, an: Dictionary) -> Array:
	var goal: Vector3 = an["pos"]
	var aisles: Array = an.get("aisles", [])
	# From another room or a corridor: through the doorways on their centre line.
	if _room_at(Vector2(from.x, from.z)) != _room_at(Vector2(goal.x, goal.z)):
		return _route_rooms(from, goal)
	if aisles.is_empty():
		return [goal]
	# Through the aisles to the aisle nearest the anchor, then onto the stand point.
	return _aisle_route(aisles, from, goal)
func _walk_path(rec: Dictionary, from: Vector3, dt: float, speed: float) -> Vector3:
	var path: Array = rec["path"]
	var p: Vector3 = from
	var left: float = speed * dt
	# Slow down on the last metre so the stop is not abrupt.
	while left > 0.0 and not path.is_empty():
		var nxt: Vector3 = path[0]
		var d: float = p.distance_to(nxt)
		if path.size() == 1:
			left = minf(left, maxf(d * 3.0 * dt, 0.35 * dt) if d < 1.0 else left)
		if d <= left:
			p = nxt
			left -= d
			path.pop_front()
		else:
			p = p + (nxt - p) / d * left
			left = 0.0
	return p

func _sync_crate(rec: Dictionary, lib: Dictionary, cargo: Dictionary, dead: bool) -> void:
	var inst = view.inst
	if cargo.is_empty() or dead:
		if int(rec["crate"]) != -1:
			inst.remove(rec["crate"])
			rec["crate"] = -1
			rec["crate_res"] = ""
		return
	var res: String = cargo.keys()[0]
	var body := Transform3D(Basis(Vector3.UP, float(rec["yaw"])), _dp(rec))
	var cxf: Transform3D
	var pr: int = int(lib["prop_r"])
	if pr >= 0 and (lib["clips"] as Dictionary).has("carry_walk"):
		# ART-NPC round 3: prop.R rides the right hand; the crate hangs from it by the file's
		# fixed prop_R_offset. The crate eases in with the carry layer (arms come up, crate grows in).
		var pz: Dictionary = rec["sm"].pose()
		var g: Transform3D = bone_for_pose(lib, pz, pr, rec)
		if lib.get("crate_offset") != null:
			g = g * (lib["crate_offset"] as Transform3D)
		var w: float = float(rec["sm"].carry_w)
		var e: float = w * w * (3.0 - 2.0 * w) * 0.85
		cxf = body * Transform3D(g.basis.orthonormalized().scaled(Vector3(maxf(e, 0.001), maxf(e, 0.001), maxf(e, 0.001))), g.origin)
	elif pr >= 0:
		var pz2: Dictionary = rec["sm"].pose()
		var g2: Transform3D = bone_for_pose(lib, pz2, pr)
		cxf = body * Transform3D(Basis().scaled(Vector3(0.8, 0.8, 0.8)), g2.origin + Vector3(0.05, -0.18, -0.12))
	else:
		cxf = body * Transform3D(Basis().scaled(Vector3(0.8, 0.8, 0.8)), Vector3(0.42, 0.95, 0))
	if rec["crate_res"] != res and int(rec["crate"]) != -1:
		inst.remove(rec["crate"])
		rec["crate"] = -1
	if int(rec["crate"]) == -1:
		rec["crate"] = inst.add(view._crate_tpl(res), cxf, Models.RES_COLOR.get(res, Color.WHITE))
		rec["crate_res"] = res
	else:
		inst.set_xf(rec["crate"], cxf)

var _ghosts := {}
## Boarding visitors (no longer in the simulation): straight up the ramp lane, then a fade.
func _walk_ghosts(delta: float, lists: Dictionary) -> void:
	var dtg: float = delta * maxf(float(view.game_rate), 0.0)
	for id in _ghosts.keys():
		var g: Dictionary = _ghosts[id]
		var rec: Dictionary = g["rec"]
		var foot: Vector3 = g["foot"]
		var before: Vector3 = rec["pos"]
		var now: Vector3 = before.move_toward(foot, 1.3 * dtg)
		rec["pos"] = now
		var mv: float = before.distance_to(now) / maxf(delta, 0.0001)
		rec["speed"] = mv
		if mv > 0.05:
			rec["yaw"] = _turn(float(rec["yaw"]), -atan2(now.z - before.z, now.x - before.x), delta)
		rec["sm"].speed = before.distance_to(now) / maxf(dtg, 0.0001) if dtg > 0.0 else 0.0
		rec["sm"].set_goal("stand", "loco")
		rec["sm"].advance(dtg)
		if now.distance_to(foot) < 0.15:
			rec["fade"] = float(rec.get("fade", 1.0)) - dtg / 0.4
		if float(rec.get("fade", 1.0)) <= 0.0:
			if int(rec["crate"]) != -1:
				view.inst.remove(rec["crate"])
			_ghosts.erase(id)
			continue
		var dkr: String = String(rec.get("dk", rec["var"])) if libs.has(String(rec.get("dk", rec["var"]))) else String(libs.keys()[0])
		var lib: Dictionary = libs[dkr]
		(lists[dkr] as Array).append([rec, lib])

# ---------------------------------------------------------------- puppets (V4 vehicle crews)
## View-only bodies driven by another module (fx_vehicles: boarding, seats, alighting). The
## owner sets rec.pos, rec.yaw, rec.fade and plays clips with rec.sm.force(); this node advances
## the clip and draws the body with the colonists. Nothing here is in sim.state.
var puppets := {}

func puppet(key: String, variant: String = "suit", role: String = "engineer") -> Dictionary:
	if puppets.has(key):
		return puppets[key]
	if libs.is_empty():
		return {}
	var lib: Dictionary = libs.get(variant, libs.values()[0])
	var rec: Dictionary = _new_rec({"id": absi(hash(key)) % 100000, "pos": Vector2.ZERO, "role": role}, lib)
	rec["var"] = variant if libs.has(variant) else String(libs.keys()[0])
	rec["mode"] = "puppet"
	if bool(lib.get("people", false)):
		# V5 people puppets (photo()): the owner may set outfit, plook and cloth.
		rec["dk"] = rec["var"]
		set_outfit(lib, rec, outfit_for(lib, "uniform_engineering"))
		rec["plook"] = (int(rec["look"]) / 64) * 64 + ((int(rec["look"]) / 8) % 4) * 8 + int(rec["look"]) % 8
		rec["cloth"] = absi(hash(key)) % 8
	puppets[key] = rec
	return rec

func puppet_free(key: String) -> void:
	puppets.erase(key)

func _sync_puppets(delta: float, lists: Dictionary) -> void:
	var dtg: float = delta * maxf(float(view.game_rate), float(view.get("demo_rate") if view.get("demo_rate") != null else 0.0))
	for key in puppets:
		var rec: Dictionary = puppets[key]
		if float(rec.get("fade", 1.0)) <= 0.0:
			continue
		rec["sm"].advance(dtg)
		var dkr: String = String(rec.get("dk", rec["var"])) if libs.has(String(rec.get("dk", rec["var"]))) else String(libs.keys()[0])
		var lib: Dictionary = libs[dkr]
		(lists[dkr] as Array).append([rec, lib])

func _drop(id: int) -> void:
	var rec: Dictionary = agents[id]
	_release(rec, id)
	if int(rec["crate"]) != -1:
		view.inst.remove(rec["crate"])
	agents.erase(id)

## Where the body is DRAWN (camera follow centres on it, critic round 6).
func body_pos(id: int):
	if agents.has(id):
		return _dp(agents[id])
	return null

## All bodies as [Vector3] (doors open when one is within 2 m).
func body_points() -> Array:
	var out: Array = []
	for id in agents:
		out.append(_dp(agents[id]))
	return out

## Display position: the logical position plus the separation offset.
static func _dp(rec: Dictionary) -> Vector3:
	return (rec["pos"] as Vector3) + (rec.get("off", Vector3.ZERO) as Vector3)

# ---------------------------------------------------------------- one body, one spot
## Doorways per room from fx_doors (rebuilt when the doors are): the point 1.05 m inside
## the door on its centre line, the point 0.9 m outside, the outward direction, the link.
func _doors_of(rid: int) -> Array:
	var dv = view.doors
	if dv == null:
		return []
	var rev: int = int(dv.stats.get("rebuilds", 0))
	if rev != _door_rev:
		_door_rev = rev
		_door_cache = {}
		var blds: Dictionary = sim.state["buildings"]
		for d in dv.doors:
			var r: int = int(d["room"])
			if not blds.has(r):
				continue
			var c: Vector2 = blds[r]["pos"]
			var dp: Vector3 = d["pos"]
			var dir: Vector2 = (Vector2(dp.x, dp.z) - c).normalized()
			var rr: float = float(blds[r]["radius"])
			var fy: float = _floor_y(blds[r])
			var pin: Vector2 = c + dir * maxf(0.6, rr - 1.05)
			var pout: Vector2 = c + dir * (rr + 0.9)
			if not _door_cache.has(r):
				_door_cache[r] = []
			(_door_cache[r] as Array).append({"in": Vector3(pin.x, fy, pin.y), "out": Vector3(pout.x, fy, pout.y), "dir": dir, "link": int(d["link"])})
		# The airlock's own outer door (model +X, ART-HAB P1): the way out for suited bodies.
		for bid in blds:
			var ab: Dictionary = blds[bid]
			if String(ab["def"]) != "airlock" or not view.bmeta.has(bid):
				continue
			var bx: Vector3 = (view.bmeta[bid]["xf"] as Transform3D).basis.x
			var odir := Vector2(bx.x, bx.z).normalized()
			var oc: Vector2 = ab["pos"]
			var orr: float = float(ab["radius"])
			var ofy: float = _floor_y(ab)
			var oin: Vector2 = oc + odir * maxf(0.6, orr - 1.05)
			var oout: Vector2 = oc + odir * (orr + 1.2)
			if not _door_cache.has(bid):
				_door_cache[bid] = []
			(_door_cache[bid] as Array).append({"in": Vector3(oin.x, ofy, oin.y), "out": Vector3(oout.x, view.h(oout.x, oout.y), oout.y), "dir": odir, "link": -1})
	return _door_cache.get(rid, [])

## The doorway of a room that faces point p best, or {}.
func _door_toward(rid: int, p: Vector3) -> Dictionary:
	var c: Vector2 = sim.state["buildings"][rid]["pos"]
	var best := {}
	var bd := -INF
	for d in _doors_of(rid):
		var s: float = (d["dir"] as Vector2).dot((Vector2(p.x, p.z) - c).normalized())
		if s > bd:
			bd = s
			best = d
	return best

## A walk from `from` to `to` that crosses room walls only through doorways, on the door
## centre line (critic round 8: bodies clipped the jambs). Inside a room it follows the
## aisle graph.
func _route_rooms(from: Vector3, to: Vector3) -> Array:
	var rb: int = _room_at(Vector2(from.x, from.z))
	var rt: int = _room_at(Vector2(to.x, to.z))
	var blds: Dictionary = sim.state["buildings"]
	if rb == rt:
		var ai: Array = _aisles_of(view.bmeta[rb]) if rb >= 0 and view.bmeta.has(rb) else []
		return _aisle_route(ai, from, to) if not ai.is_empty() else [to]
	var pts: Array = []
	var cur: Vector3 = from
	if rb >= 0:
		var d: Dictionary = _door_toward(rb, to)
		if not d.is_empty():
			var ai2: Array = _aisles_of(view.bmeta[rb]) if view.bmeta.has(rb) else []
			pts.append_array(_aisle_route(ai2, cur, d["in"]) if not ai2.is_empty() else [d["in"]])
			pts.append(d["out"])
			cur = d["out"]
	if rt >= 0:
		var d2: Dictionary = _door_toward(rt, cur)
		if not d2.is_empty():
			pts.append(d2["out"])
			pts.append(d2["in"])
			var ai3: Array = _aisles_of(view.bmeta[rt]) if view.bmeta.has(rt) else []
			pts.append_array(_aisle_route(ai3, d2["in"], to) if not ai3.is_empty() else [to])
			return pts
	pts.append(to)
	return pts

## Queue points of a room: along each of its corridors, from 0.9 m outside the doorway,
## QUEUE_GAP apart, stopping 1.5 m before the far end.
func _queue_points(rid: int) -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for d in _doors_of(rid):
		if int(d["link"]) < 0:
			continue
		var l: Dictionary = blds.get(int(d["link"]), {})
		var ln: float = 8.0
		if not l.is_empty():
			ln = (l["p0"] as Vector2).distance_to(l["p1"])
		var base: Vector3 = d["out"]
		var dir: Vector2 = d["dir"]
		var k := 0
		while 0.9 + k * QUEUE_GAP < ln - 1.5 and k < 12:
			var qp: Vector3 = base + Vector3(dir.x, 0, dir.y) * (k * QUEUE_GAP)
			# Only points inside the tube (V3_1 §4.4: an indoor body is never drawn on open ground).
			if planner.region_of(qp, true)["k"] == "tube" and planner.region_of(qp, false)["k"] == "tube":
				out.append(qp)
			k += 1
	return out

## Waiting points OUTSIDE a full room whose corridors are full too: two rings round the
## outer wall, 0.8 m apart, away from the doorways (the bodies there wear suits).
func _outside_points(rid: int) -> Array:
	var out: Array = []
	var b: Dictionary = sim.state["buildings"][rid]
	var c: Vector2 = b["pos"]
	var rr: float = float(b["radius"])
	var dirs: Array = []
	for d in _doors_of(rid):
		dirs.append(d["dir"])
	for ring in [1.5, 2.3]:
		var rad: float = rr + ring
		var n: int = int(floor(TAU * rad / QUEUE_GAP))
		for i in n:
			var ang: float = TAU * float(i) / float(n)
			var dv := Vector2(cos(ang), sin(ang))
			var near_door := false
			for dd in dirs:
				if dv.dot(dd) > cos(deg_to_rad(28.0)):
					near_door = true
					break
			if near_door:
				continue
			var q: Vector2 = c + dv * rad
			out.append(Vector3(q.x, view.h(q.x, q.y), q.y))
	return out

## Releases the furniture anchor this body holds.
func _release(rec: Dictionary, id: int) -> void:
	var ck: String = String(rec.get("claim", ""))
	if ck != "" and int(_claims.get(ck, -1)) == id:
		_claims.erase(ck)
	rec.erase("claim")
	rec.erase("wait_claim")

## Rooms by 16 m cell (rebuilt when the number of structures changes).
func _build_room_grid() -> void:
	if view.bmeta.size() == _room_n:
		return
	_room_n = view.bmeta.size()
	_room_grid = {}
	var blds: Dictionary = sim.state["buildings"]
	for bid in view.bmeta:
		if not blds.has(bid) or String(blds[bid]["kind"]) != "room":
			continue
		var c: Vector2 = blds[bid]["pos"]
		var r: float = float(blds[bid]["radius"])
		for cx in range(int(floor((c.x - r) / 16.0)), int(floor((c.x + r) / 16.0)) + 1):
			for cz in range(int(floor((c.y - r) / 16.0)), int(floor((c.y + r) / 16.0)) + 1):
				var key: int = cx * 4096 + cz
				if not _room_grid.has(key):
					_room_grid[key] = []
				(_room_grid[key] as Array).append(bid)

## The room whose floor holds p, or -1.
func _room_at(p: Vector2) -> int:
	var blds: Dictionary = sim.state["buildings"]
	for bid in _room_grid.get(int(floor(p.x / 16.0)) * 4096 + int(floor(p.y / 16.0)), []):
		if blds.has(bid) and p.distance_to(blds[bid]["pos"]) < float(blds[bid]["radius"]) * 0.97:
			return int(bid)
	return -1

## Free standing points of a room: the aisle points, the midpoints of the aisle links,
## the Anchor_Stand_* points; none closer than SLOT_GAP to another (cached per room).
func _slots_of(meta) -> Array:
	if meta == null:
		return []
	if meta.has("slots_w"):
		return meta["slots_w"]
	var aisles: Array = _aisles_of(meta)
	var raw: Array = aisles.duplicate()
	for i in aisles.size():
		for j in range(i + 1, aisles.size()):
			var a: Vector3 = aisles[i]
			var b: Vector3 = aisles[j]
			var d: float = a.distance_to(b)
			if d <= 1.75 and d >= SLOT_GAP * 2.0:
				raw.append(a.lerp(b, 0.5))
	var fy: float = (meta["xf"] as Transform3D).origin.y + FLOOR_Z * Models.scale3(meta["tpl"]).y
	for an in meta["anchors"]:
		if String(an).begins_with("Stand_"):
			var sp: Vector3 = (meta["anchors"][an] as Transform3D).origin
			raw.append(Vector3(sp.x, fy, sp.z))
	var out: Array = []
	for q in raw:
		var ok := true
		for o in out:
			if Vector2((q as Vector3).x - (o as Vector3).x, (q as Vector3).z - (o as Vector3).z).length() < SLOT_GAP:
				ok = false
				break
		if ok:
			out.append(q)
	meta["slots_w"] = out
	return out

## Standing points of a room that are on free floor (cached per room).
func _free_slots(rid: int) -> Array:
	var meta = view.bmeta.get(rid)
	if meta == null:
		return []
	if meta.has("slots_free"):
		return meta["slots_free"]
	var out: Array = []
	for q in _slots_of(meta):
		if planner.free_in_room(rid, q):
			out.append(q)
	meta["slots_free"] = out
	return out

## Gives every free body inside a room its own standing point (critic round 6): furniture
## anchors are held by their users; the others take the nearest free point, never within
## MIN_GAP of a taken one. A body keeps its point while it stays free and close to its goal.
func _assign_slots(all: Dictionary) -> void:
	_build_room_grid()
	var per_room := {}
	var slotted := 0
	var waiting := 0
	for id in agents:
		var rec: Dictionary = agents[id]
		if rec.has("wait_claim"):
			waiting += 1
		var a = all.get(id)
		if a == null:
			continue
		var m: String = rec["mode"]
		if m == "at_anchor" or m == "to_anchor" or m == "leaving":
			var an: Dictionary = rec["anchor"]
			if not an.is_empty() and an.has("pos") and (an["pos"] as Vector3) != Vector3.INF:
				var ap: Vector3 = an["pos"]
				var r2: int = _room_at(Vector2(ap.x, ap.z))
				if r2 >= 0:
					if not per_room.has(r2):
						per_room[r2] = {"want": [], "busy": []}
					per_room[r2]["busy"].append(ap)
			continue
		if rec.has("lockg"):
			# An airlock place (fx_airlock) is taken: no free-standing body is sent there too.
			var lgp: Vector3 = rec["lockg"]["pos"]
			var r3: int = _room_at(Vector2(lgp.x, lgp.z))
			if r3 >= 0:
				if not per_room.has(r3):
					per_room[r3] = {"want": [], "busy": []}
				per_room[r3]["busy"].append(lgp)
			rec.erase("slot")
			continue
		if a["where"] == "out" or a["state"] != "alive" or a["where"] == "lock" or rec.has("lockg"):
			rec.erase("slot")
			continue
		var sp: Vector2 = a["pos"]
		var rid: int = _room_at(sp)
		if rid < 0:
			rec.erase("slot")
			continue
		if not per_room.has(rid):
			per_room[rid] = {"want": [], "busy": []}
		per_room[rid]["want"].append([int(id), Vector3(sp.x, 0.0, sp.y)])
	for rid in per_room:
		var cands: Array = _free_slots(rid)
		var want: Array = per_room[rid]["want"]
		if cands.is_empty():
			for w in want:
				agents[w[0]].erase("slot")
			continue
		var taken: Array = (per_room[rid]["busy"] as Array).duplicate()
		want.sort_custom(func(x, y): return x[0] < y[0])
		for w in want:
			var rec: Dictionary = agents[w[0]]
			var goal: Vector3 = w[1]
			var best = null
			var bd := INF
			for c in cands:
				var cv: Vector3 = c
				var free := true
				for tk in taken:
					if Vector2(cv.x - (tk as Vector3).x, cv.z - (tk as Vector3).z).length() < MIN_GAP:
						free = false
						break
				if not free:
					continue
				var d: float = Vector2(cv.x - goal.x, cv.z - goal.z).length()
				if rec.has("slot") and int(rec.get("slot_room", -1)) == rid and (rec["slot"] as Vector3).distance_to(cv) < 0.05:
					d -= 0.8
				if d < bd:
					bd = d
					best = cv
			var queued := false
			if best == null:
				# Critic round 8: a full room queues the rest in its corridors, 0.8 m apart,
				# never inside the wall.
				var qlist: Array = _queue_points(rid)
				var ncorr: int = qlist.size()
				# (V3_1: an indoor body never waits outside; the airlock porch queue is §5.)
				for qi in qlist.size():
					var qv: Vector3 = qlist[qi]
					var qfree := true
					for tk in taken:
						if Vector2(qv.x - (tk as Vector3).x, qv.z - (tk as Vector3).z).length() < QUEUE_GAP - 0.05:
							qfree = false
							break
					if qfree:
						best = qv
						queued = true
						rec["q_out"] = qi >= ncorr
						break
			if best == null:
				rec.erase("slot")
				continue
			rec["slot"] = best
			rec["slot_room"] = rid
			rec["slot_q"] = queued
			if not queued:
				rec["q_out"] = false
			taken.append(best)
			slotted += 1
	stats_slots["slotted"] = slotted
	var nq := 0
	for id in agents:
		if bool(agents[id].get("slot_q", false)) and agents[id].has("slot"):
			nq += 1
	stats_slots["queued"] = nq
	stats_slots["waiting"] = waiting
	stats_slots["claims"] = _claims.size()

## Hard minimum gap between standing bodies (critic round 6), on the DRAWN positions:
## a body that is seated, lying or at its anchor does not move; the others are pushed
## apart (up to 5 passes). The logical position is not changed, so no walk plays in place.
func _separate() -> void:
	var ids: Array = agents.keys()
	var P := {}
	var fixed := {}
	for id in ids:
		var rec: Dictionary = agents[id]
		P[id] = rec["pos"]
		fixed[id] = String(rec["mode"]) == "at_anchor" or String(rec["sm"].pose_state) != "stand" or bool(rec["dead"]) \
			or (bool(rec.get("slot_q", false)) and rec.has("slot") and (rec["pos"] as Vector3).distance_to(rec["slot"]) < 0.15) \
			or (rec.has("lockg") and (rec["pos"] as Vector3).distance_to(rec["lockg"]["pos"]) < 0.2)
	var pushed := 0
	for it in 5:
		var grid := {}
		for id in ids:
			var p: Vector3 = P[id]
			var key: int = int(floor(p.x / MIN_GAP)) * 65536 + int(floor(p.z / MIN_GAP))
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(id)
		var moved := false
		for id in ids:
			if fixed[id]:
				continue
			var p: Vector3 = P[id]
			var cx: int = int(floor(p.x / MIN_GAP))
			var cz: int = int(floor(p.z / MIN_GAP))
			var push := Vector2.ZERO
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for j in grid.get((cx + dx) * 65536 + cz + dz, []):
						if j == id:
							continue
						var q: Vector3 = P[j]
						if absf(q.y - p.y) > 1.5:
							continue
						var d := Vector2(p.x - q.x, p.z - q.z)
						var l: float = d.length()
						if l >= MIN_GAP:
							continue
						var dir: Vector2
						if l < 0.02:
							var ang: float = Rng.hash2(mini(int(id), int(j)), maxi(int(id), int(j)), 41) * TAU
							dir = Vector2(cos(ang), sin(ang)) * (1.0 if int(id) < int(j) else -1.0)
						else:
							dir = d / l
						push += dir * (MIN_GAP + 0.02 - l) * (1.0 if fixed[j] else 0.5)
			if push != Vector2.ZERO:
				P[id] = p + Vector3(push.x, 0.0, push.y)
				moved = true
		if not moved:
			break
	var blds: Dictionary = sim.state["buildings"]
	for id in ids:
		var rec: Dictionary = agents[id]
		var off: Vector3 = (P[id] as Vector3) - (rec["pos"] as Vector3)
		if off.length() > 1.2:
			off = off.normalized() * 1.2
		# Stay inside the room it stands in.
		if off != Vector3.ZERO:
			var lp: Vector3 = rec["pos"]
			var rid: int = _room_at(Vector2(lp.x, lp.z))
			if rid >= 0:
				var c: Vector2 = blds[rid]["pos"]
				var lim: float = float(blds[rid]["radius"]) - 0.6
				var np := Vector2(lp.x + off.x, lp.z + off.z)
				if np.distance_to(c) > lim:
					np = c + (np - c).normalized() * lim
					off = Vector3(np.x - lp.x, 0.0, np.y - lp.z)
				# Never pushed into furniture (V3_1 §4.4 b): shorten the push until free.
				for k in 4:
					if planner.free_in_room(rid, lp + off):
						break
					off *= 0.5
				if not planner.free_in_room(rid, lp + off):
					off = Vector3.ZERO
			else:
				# In a corridor or outside: at most 0.45 m from the path line.
				off = off.limit_length(0.45)
			pushed += 1
		# The drawn offset changes slowly (a push is never a slide): 0.25 m/s of game time.
		var old_off: Vector3 = rec.get("off", Vector3.ZERO)
		off = old_off.move_toward(off, 0.15 * maxf(game_rate, 0.0) * _sep_dt + 0.0002)
		rec["off"] = off
	stats_slots["pushed"] = pushed
	if _frame % 30 != 0:
		return
	# Measured result (every 30th frame) (standing bodies only): the smallest gap and the pairs under MIN_GAP.
	var mg := INF
	var close := 0
	var grid2 := {}
	for id in ids:
		var q: Vector3 = _dp(agents[id])
		var key: int = int(floor(q.x / MIN_GAP)) * 65536 + int(floor(q.z / MIN_GAP))
		if not grid2.has(key):
			grid2[key] = []
		(grid2[key] as Array).append(id)
	for id in ids:
		if fixed[id]:
			continue
		var p: Vector3 = _dp(agents[id])
		var cx: int = int(floor(p.x / MIN_GAP))
		var cz: int = int(floor(p.z / MIN_GAP))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j in grid2.get((cx + dx) * 65536 + cz + dz, []):
					if j == id:
						continue
					var q: Vector3 = _dp(agents[j])
					if absf(q.y - p.y) > 1.5:
						continue
					var l: float = Vector2(p.x - q.x, p.z - q.z).length()
					mg = minf(mg, l)
					if l < MIN_GAP - 0.02:
						close += 1
	stats_slots["min_gap"] = snappedf(mg, 0.01) if mg < INF else -1.0
	stats_slots["close_pairs"] = close

func _write_mm(variant: String, list: Array) -> void:
	var e: Dictionary = mm[variant]
	var heads: int = maxi(1, int(e["heads"]))
	# One instance record: transform (12), colour (4, white), custom (4).
	var all := PackedFloat32Array()
	all.resize(list.size() * 20)
	var head_of := PackedInt32Array()
	head_of.resize(list.size())
	var fades := PackedFloat32Array()
	fades.resize(list.size())
	# V5 people: the look code of the people shader, the outfit shown and the clothes colour.
	var people: bool = bool(e.get("people", false))
	var outfit_of: Array = []
	var addons_of: Array = []
	var cloth := PackedFloat32Array()
	if people:
		outfit_of.resize(list.size())
		cloth.resize(list.size())
	var k := 0
	var n := 0
	for it in list:
		var rec: Dictionary = it[0]
		var lib: Dictionary = it[1]
		var p: Vector3 = _dp(rec)
		fades[n] = float(rec.get("fade", 1.0))
		# Follow view: another person who passes through the camera fades out (dithered) inside
		# 0.3-0.75 m of it, measured to the body's axis (feet to head), not only its root.
		# Critic round 41: any body within 0.8 m of the lens fades to nothing, smoothly IN TIME (0.25 s), so a
		# still frame shows it gone or whole, rarely half (the shader's dither also moves every frame).
		var cf: float = float(rec.get("camfade", 1.0))
		var cwant := 1.0
		if _follow_id >= 0 and int(rec.get("id", -1)) != _follow_id:
			var qa: Vector3 = Geometry3D.get_closest_point_to_segment(_cam_pos, p + Vector3(0, 0.1, 0), p + Vector3(0, 1.75, 0))
			var cd: float = qa.distance_to(_cam_pos)
			if cd < CAM_FADE_R:
				cwant = 0.0
				stats_slots["cam_faded"] = int(stats_slots.get("cam_faded", 0)) + 1
		cf = move_toward(cf, cwant, _sep_dt / 0.25)
		rec["camfade"] = cf
		fades[n] = minf(fades[n], cf * cf * (3.0 - 2.0 * cf))
		var look_v: float = float(rec["look"])
		if people:
			look_v = float(rec.get("plook", rec["look"]))
			outfit_of[n] = String(rec.get("omesh", ""))
			addons_of.append(rec.get("addons", []))
			# INSTANCE_CUSTOM.w = clothes colour (0..7) + 8 x outfit index (UniformBase colour).
			cloth[n] = float(int(rec.get("cloth", 0)) % 8 + 8 * int(rec.get("oidx", 0)))
		var yaw: float = rec["yaw"]
		var c: float = cos(yaw)
		var s: float = sin(yaw)
		# Basis(UP, yaw) rows: [c, 0, s], [0, 1, 0], [-s, 0, c]
		all[k] = c
		all[k + 1] = 0.0
		all[k + 2] = s
		all[k + 3] = p.x
		all[k + 4] = 0.0
		all[k + 5] = 1.0
		all[k + 6] = 0.0
		all[k + 7] = p.y
		all[k + 8] = -s
		all[k + 9] = 0.0
		all[k + 10] = c
		all[k + 11] = p.z
		all[k + 12] = 1.0
		all[k + 13] = 1.0
		all[k + 14] = 1.0
		all[k + 15] = 1.0
		var pz: Dictionary = rec["sm"].pose()
		var cpu: bool = needs_cpu(pz) or force_cpu
		if cpu and bool(rec.get("far", false)):
			# Far away the dominant pose is drawn (no CPU blend): nobody sees 0.3 s of blend at
			# 90 m, and the budget goes to the bodies near the camera.
			pz = pz.duplicate()
			if float(pz["wb"]) > 0.5:
				pz["a"] = pz["b"]
				pz["ta"] = pz["tb"]
			pz["b"] = ""
			pz["wb"] = 0.0
			if float(pz["wc"]) < 0.5:
				pz["c"] = ""
				pz["wc"] = 0.0
			else:
				pz["wc"] = 1.0
			cpu = false
		if cpu:
			if String(pz["b"]) != "" and float(pz["wb"]) > 0.001:
				_why["fade" if rec["sm"].fade > 0.0 else "run"] = int(_why.get("fade" if rec["sm"].fade > 0.0 else "run", 0)) + 1
			else:
				_why["carry"] = int(_why.get("carry", 0)) + 1
		if cpu and _dyn_used < DYN_ROWS and _dyn_img != null:
			# A blend: slerped on the CPU into a dynamic row (exact, no matrix lerp).
			write_row(lib, _globals_cached(rec, lib, pz), _dyn_buf, _dyn_used, _dyn_w)
			all[k + 16] = float(DYN0 + _dyn_used)
			all[k + 17] = -1.0
			all[k + 18] = look_v
			all[k + 19] = -1.0
			_dyn_used += 1
			head_of[n] = ((int(rec["look"]) / 8) % 8) % heads
			k += 20
			n += 1
			continue
		all[k + 16] = row_of(lib, pz["a"], pz["ta"])
		if String(pz["b"]) != "" and float(pz["wb"]) > 0.001:
			all[k + 17] = floor(row_of(lib, pz["b"], pz["tb"])) + clampf(float(pz["wb"]), 0.0, 1.0) * 0.998
		else:
			all[k + 17] = -1.0
		all[k + 18] = look_v
		if String(pz["c"]) != "" and float(pz["wc"]) > 0.001:
			all[k + 19] = floor(row_of(lib, pz["c"], pz["tc"])) + clampf(float(pz["wc"]), 0.0, 1.0) * 0.998
		else:
			all[k + 19] = -1.0
		head_of[n] = ((int(rec["look"]) / 8) % 8) % heads
		k += 20
		n += 1
	# Move the pose data into the body texture; the custom data keeps the body index + look.
	if _bd_img != null:
		for i in n:
			var gi: int = _bd_used + i
			if gi >= BD_ROWS:
				break
			var b0: int = i * 20 + 16
			_bd_buf[gi * 4] = all[b0]
			_bd_buf[gi * 4 + 1] = all[b0 + 1]
			_bd_buf[gi * 4 + 2] = all[b0 + 2]
			_bd_buf[gi * 4 + 3] = all[b0 + 3]
			all[b0] = float(gi)
			all[b0 + 1] = fades[i]
			all[b0 + 3] = cloth[i] if people else 0.0
		_bd_used = mini(BD_ROWS, _bd_used + n)
	for part in e["parts"]:
		var m: MultiMesh = part["mm"]
		var h: int = part["head"]
		var buf: PackedFloat32Array = all
		var cnt: int = n
		var vk: int = int(part.get("vis", -1))
		if vk >= 0:
			buf = PackedFloat32Array()
			cnt = 0
			var vh: int = int(part.get("vh", 0))
			for i in n:
				var lk: int = int(list[i][0]["look"])
				var v: int = lk / 64 - 8
				if v >= 0 and v < VIS_LOOK_KIND.size() and int(VIS_LOOK_KIND[v]) == vk and (vh == 0 or (vh & (1 << ((lk / 8) % 8))) != 0):
					buf.append_array(all.slice(i * 20, i * 20 + 20))
					cnt += 1
		elif people and String(part.get("addon", "")) != "":
			var ad: String = part["addon"]
			buf = PackedFloat32Array()
			cnt = 0
			for i in n:
				if (addons_of[i] as Array).has(ad):
					buf.append_array(all.slice(i * 20, i * 20 + 20))
					cnt += 1
		elif people and String(part.get("outfit", "")) != "":
			var of: String = part["outfit"]
			buf = PackedFloat32Array()
			cnt = 0
			for i in n:
				if outfit_of[i] == of:
					buf.append_array(all.slice(i * 20, i * 20 + 20))
					cnt += 1
		elif h >= 0:
			buf = PackedFloat32Array()
			cnt = 0
			for i in n:
				if head_of[i] == h:
					buf.append_array(all.slice(i * 20, i * 20 + 20))
					cnt += 1
		if m.instance_count != cnt:
			m.instance_count = cnt
		if cnt > 0:
			m.buffer = buf
func _why_avg(fr: float) -> Dictionary:
	var o := {}
	for k in _why:
		o[k] = snappedf(float(_why[k]) / fr, 0.1)
	return o

func stats() -> Dictionary:
	var fr: float = maxf(1.0, float(_prof_frames))
	var out := {"ms": snappedf(npc_ms, 0.01), "bodies": agents.size(), "game_rate": snappedf(game_rate, 0.01), "dyn_rows": _dyn_used,
		"body_ms": snappedf(_t_body / fr / 1000.0, 0.01), "bodies_per_frame": snappedf(_n_body / fr, 0.1), "write_ms": snappedf(_t_write / fr / 1000.0, 0.01), "lamps_ms": snappedf(_t_lamps / fr / 1000.0, 0.01), "walk_ms": snappedf(_t_walk / fr / 1000.0, 0.01), "prof_ms": _pm.keys().map(func(k): return "%s %.2f" % [k, _pm[k] / fr / 1000.0]), "blend_why_per_frame": _why_avg(fr), "slots": stats_slots.duplicate(), "planner": planner.stats.duplicate() if planner != null else {}}
	# V5 people: bodies per drawn library and outfit (evidence).
	var dks := {}
	for aid in agents:
		var r: Dictionary = agents[aid]
		var kk: String = String(r.get("dk", r["var"])) + ("/" + String(r["outfit"]) + "/" + String(r.get("omesh", "")) + "+" + ",".join(r.get("addons", [])) if r.has("outfit") and String(r.get("dk", "")).begins_with("p_") else "")
		dks[kk] = int(dks.get(kk, 0)) + 1
	out["draw_keys"] = dks
	out["pkey_sample"] = _pkey.values().slice(0, 6)
	_why = {}
	_t_body = 0
	_t_write = 0
	_t_lamps = 0
	_t_walk = 0
	_pm = {}
	_n_body = 0
	_prof_frames = 0
	for v in libs:
		var lib: Dictionary = libs[v]
		out[v] = {"status": status.get(v, ""), "tris": lib["tris"], "clips": (lib["clips"] as Dictionary).size(), "missing": lib["missing"], "rows": lib["rows"], "bake_ms": snappedf(float(lib["bake_ms"]), 0.1), "parts": (lib["parts"] as Array).size(), "heads": lib["heads"], "shared": lib["shared"], "part_names": (lib["parts"] as Array).map(func(p): return String(p["name"]) + ":" + String(p.get("outfit", ""))), "outfits": lib_outfits(lib) if bool(lib.get("people", false)) else []}
	for v in ["suit", "in"]:
		if not libs.has(v):
			out[v] = {"status": status.get(v, "missing")}
	return out
