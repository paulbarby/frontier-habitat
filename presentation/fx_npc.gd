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
const SKIN_SHADER = preload("res://shaders/npc_skin.gdshader")

const FPS := 30.0
const FLOOR_Z := 0.14            # rooms_kit.py: top of the floor in every room
const FILES := {"suit": "res://assets/models/astronaut_suit.glb", "in": "res://assets/models/astronaut_indoor.glb"}
const META_FILE := "res://assets/models/astronaut_anims.json"
const LOOPS := ["idle", "idle_look", "walk", "run", "carry_walk", "carry_idle", "work_console", "work_bench", "talk",
	"repair_kneel", "sit_idle", "sit_eat", "sit_type", "sleep", "injured_walk", "dead"]
const ENTER_EXIT := {"sit_enter": ["stand", "sit"], "sit_exit": ["sit", "stand"], "lie_enter": ["stand", "lie"], "lie_exit": ["lie", "stand"],
	"kneel_enter": ["stand", "kneel"], "kneel_exit": ["kneel", "stand"], "collapse": ["stand", "lie"]}
const ALL_CLIPS := ["idle", "idle_look", "walk", "run", "carry_walk", "carry_idle", "work_console", "work_bench", "talk",
	"kneel_enter", "repair_kneel", "kneel_exit", "sit_enter", "sit_idle", "sit_eat", "sit_type", "sit_exit",
	"lie_enter", "sleep", "lie_exit", "injured_walk", "collapse", "dead", "cheer"]
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
var forced_goto := {}            # test staging only (__fhr "runto"): agent id -> [Vector2, speed m/s]
var force_cpu := false            # test only (__fhr "npccpu 1"): every near body on the CPU row path
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
	for variant in ["suit", "in"]:
		var lib: Dictionary = load_lib(variant, fixture)
		status[variant] = String(lib.get("status", "missing"))
		if bool(lib.get("ok", false)):
			libs[variant] = lib
			lib["head_bone"] = (lib["names"] as Array).find("head")
			_make_mm(variant, lib)
		else:
			_log("lib_" + variant, "RENDER npc: %s falls back to the v2 rigid colonist (%s)" % [FILES[variant], lib.get("status", "?")])
	_setup_dyn()
	_make_lamps()

## The dynamic-row texture (blended poses) shared by every astronaut material.
func _setup_dyn() -> void:
	if libs.is_empty():
		return
	var any: Dictionary = libs.values()[0]
	_dyn_w = int(any["tex_info"]["row_w"])
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
	elif ResourceLoader.exists(FILES[variant]):
		var ps = load(FILES[variant])
		if ps is PackedScene:
			root = (ps as PackedScene).instantiate()
	if root == null:
		_libs[key] = {"ok": false, "status": "missing file"}
		return _libs[key]
	var meta: Dictionary = Fixture.meta() if fixture else _read_meta()
	# Both variants share one skeleton and one clip set (§3.2): reuse the suit's baked clips
	# when the skeleton matches, so the indoor model costs only its mesh.
	var share = null
	if variant == "in" and _libs.has("suit" + (":fixture" if fixture else "")):
		share = _libs["suit" + (":fixture" if fixture else "")]
		if not bool(share.get("ok", false)):
			share = null
	var lib: Dictionary = bake(root, meta, share)
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
	for c in ALL_CLIPS:
		if not anims.has(c):
			missing.append(c)
	if not anims.has("idle") or not anims.has("walk"):
		return {"ok": false, "status": "no idle/walk clip (missing: %s)" % ", ".join(missing)}
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
		for c in ALL_CLIPS:
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
		parts.append({"mesh": mesh, "head": head_id, "name": nm})
	# Shadow proxy: the body's surfaces merged into one surface, drawn SHADOWS_ONLY, so the
	# shadow pass costs one draw call per variant instead of one per material. Heads cast no
	# shadow (the body shadow covers them). If the mesh data cannot be read, the body casts
	# its own shadow as before.
	for p in parts.duplicate():
		if int(p["head"]) < 0:
			var pm: ArrayMesh = _skin_shadow_mesh(p["mesh"])
			if pm != null:
				p["proxied"] = true
				parts.append({"mesh": pm, "head": -1, "name": String(p["name"]) + "_shadow", "shadow_only": true})
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
	m.shader = SKIN_SHADER
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
	if mname.begins_with("SuitAccent"):
		mode = 1
	elif mname.begins_with("Skin"):
		mode = 2
	elif mname.begins_with("Hair"):
		mode = 3
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
		mmi.custom_aabb = AABB(Vector3(-100, -60, -100), Vector3(1100, 260, 1100))
		if bool(part.get("shadow_only", false)):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif int(part["head"]) >= 0 or bool(part.get("proxied", false)):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		list.append({"mm": m, "mmi": mmi, "head": int(part["head"])})
	mm[variant] = {"parts": list, "heads": int(lib["heads"])}

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
	var role: int = int(ROLE_INDEX.get(String(a.get("role", "")), 5))
	var head: int = int(Rng.hash2(id, 23, 5) * 4.0) % 4
	var tone: int = int(Rng.hash2(id, 29, 7) * 6.0) % 6
	return role * 64 + head * 8 + tone

func _floor_y(b: Dictionary) -> float:
	var meta = view.bmeta.get(int(b["id"]))
	var base: float = view.h(b["pos"].x, b["pos"].y) + 0.02
	if meta != null:
		base = (meta["xf"] as Transform3D).origin.y
	return base + FLOOR_Z

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
		"bed": nm = "Bed_%d" % i
		"seat": nm = "Seat_%d" % i
		"work": nm = "Work_%d" % i
		"stand": nm = "Stand_%d" % i
	var floor_y: float = _floor_y(b) if b["kind"] != "exterior" else view.h(b["pos"].x, b["pos"].y) + 0.02
	if i >= 0 and anchors.has(nm) or kind == "service" and anchors.has(nm):
		var xf: Transform3D = anchors[nm]
		var local_y: float = xf.origin.y - (view.bmeta[bid]["xf"] as Transform3D).origin.y
		var p: Vector3 = xf.origin
		if local_y < 0.05:
			p.y = floor_y
		var fx: Vector3 = xf.basis.x
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
	var ang: float = float(b["rot"]) + 0.4 + TAU * float(posmod(i if i >= 0 else int(use.get("seq", 0)), 8)) / 8.0
	var c: Vector2 = b["pos"]
	var q: Vector2 = c + Vector2(cos(ang), sin(ang)) * r
	var face: Vector2 = (c - q).normalized()
	return {"pos": Vector3(q.x, floor_y, q.y), "yaw": -atan2(face.y, face.x), "aisles": [], "found": false}

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
		"bed":
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
			_drop(id)
	var lists := {"suit": [], "in": []}
	var focus: Vector3 = view._focus_now
	var cam_d: float = float(view.camera_distance)
	# Animation runs in game time: 2x speed plays the clips at 2x, a pause freezes them.
	game_rate = float(view.game_rate)
	_dyn_used = 0
	_bd_used = 0
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
		if not libs.has(variant):
			variant = "suit" if libs.has("suit") else "in"
		var lib: Dictionary = libs[variant]
		if not agents.has(id):
			agents[id] = _new_rec(a, lib)
		var rec: Dictionary = agents[id]
		if rec["var"] != variant:
			rec["var"] = variant
		# Far bodies (and everything when zoomed far out) update at a lower rate.
		var far: bool = (rec["pos"] as Vector3).distance_squared_to(focus) > 8100.0 or cam_d > 160.0
		rec["far"] = far
		var step: float = delta
		if far:
			var k: int = 3
			if (int(id) + _frame) % k != 0:
				(lists[variant] as Array).append([rec, lib])
				continue
			step = delta * k
		var tb0: int = Time.get_ticks_usec()
		_update_body(a, rec, lib, step, dead)
		_t_body += Time.get_ticks_usec() - tb0
		_n_body += 1
		(lists[variant] as Array).append([rec, lib])
	var ts1: int = Time.get_ticks_usec()
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
	_halo.custom_aabb = AABB(Vector3(-100, -60, -100), Vector3(1100, 260, 1100))
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
		var sz: float = 0.0 if dead else 0.55
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

func _update_body(a: Dictionary, rec: Dictionary, lib: Dictionary, dt: float, dead: bool) -> void:
	var sm = rec["sm"]
	var pos: Vector2 = a["pos"]
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
		else:
			y = view.h(pos.x, pos.y) + 0.05 + FLOOR_Z
	var spread := Vector3(sin(float(a["id"]) * 2.4), 0, cos(float(a["id"]) * 2.4)) * (0.35 if inside else 0.2)
	var target := Vector3(pos.x, y, pos.y) + spread
	# Furniture use (§6).
	var use: Dictionary = {} if dead else _use_of(a)
	var ukey: String = "" if use.is_empty() else "%s:%d:%d:%s:%s" % [use.get("kind", ""), int(use.get("b", -1)), int(use.get("i", 0)), use.get("pose", ""), use.get("act", "")]
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
				rec["path"] = _path_to(rec["pos"], an)
				if rec["mode"] != "at_anchor":
					rec["mode"] = "to_anchor"
				# A body far away (a loaded game, a staged shot) is placed at once.
				if (rec["pos"] as Vector3).distance_to(an["pos"]) > 18.0:
					rec["pos"] = an["pos"]
					rec["yaw"] = float(an["yaw"])
					rec["path"] = []
					rec["mode"] = "at_anchor"
		if ukey == "" or rec["anchor"].is_empty():
			if rec["mode"] == "at_anchor" or rec["mode"] == "to_anchor":
				rec["mode"] = "leaving"
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
				now = _walk_path(rec, before, dt, 1.1 * maxf(game_rate, 0.0))
				if (rec["path"] as Array).is_empty():
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
				rec["catch"] = 1.0
		_:
			pass
	if rec["mode"] == "follow":
		if rec["use_key"] != "" and not rec["anchor"].is_empty():
			rec["mode"] = "to_anchor"
			rec["path"] = _path_to(before, rec["anchor"])
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
		var rid: int = _room_at(Vector2(target.x, target.z)) if inside else -1
		if rid < 0 and inside:
			rid = _room_at(Vector2(before.x, before.z))
		var room_meta = view.bmeta.get(rid) if rid >= 0 else null
		var aisles: Array = _aisles_of(room_meta) if room_meta != null else []
		if not aisles.is_empty():
			target.y = _floor_y(blds[rid])
			if rec.has("slot") and int(rec.get("slot_room", -1)) == rid:
				var sl: Vector3 = rec["slot"]
				target = Vector3(sl.x, target.y, sl.z)
				if bool(rec.get("slot_q", false)):
					target = sl
			elif (Vector2(target.x, target.z) - (blds[rid]["pos"] as Vector2)).length() < float(blds[rid]["radius"]) * 0.9:
				var snap: Vector3 = _nearest(aisles, target)
				target = Vector3(snap.x, target.y, snap.z)
		var dist: float = before.distance_to(target)
		if forced_goto.has(int(a["id"])):
			# Test staging: walk or run straight to a point at a set speed (frame strips).
			var fg: Array = forced_goto[int(a["id"])]
			var gp: Vector2 = fg[0]
			var gt := Vector3(gp.x, view.h(gp.x, gp.y), gp.y)
			now = before.move_toward(gt, float(fg[1]) * dt * maxf(game_rate, 0.0))
			var rr: int = _room_at(Vector2(now.x, now.z))
			now.y = _floor_y(blds[rr]) if rr >= 0 else view.h(now.x, now.z) + (0.05 + FLOOR_Z if inside else 0.0)
		elif dist > 0.6 and dist <= 12.0 and (not aisles.is_empty() or _room_at(Vector2(before.x, before.z)) >= 0 or _room_at(Vector2(target.x, target.z)) >= 0):
			if (rec.get("route_to", Vector3.INF) as Vector3).distance_to(target) > 0.8:
				rec["route_to"] = target
				rec["route"] = _route_rooms(before, target)
			rec["path"] = rec["route"]
			now = _walk_path(rec, before, dt, 3.6 * maxf(game_rate, 0.0))
			rec["route"] = rec["path"]
			rec["path"] = []
		elif dist > 12.0:
			now = target
		elif float(rec["catch"]) > 0.0 and dist > 0.3:
			# Catching up after a furniture use: walk, do not slide.
			now = before + (target - before).normalized() * minf(dist, 2.2 * dt)
		else:
			rec["catch"] = 0.0
			now = before.lerp(target, 1.0 - exp(-dt * 12.0))
		goal = ["stand", "loco"]
		if not dead and String(a.get("plan_kind", "")) == "task" and float(rec["speed"]) < 0.2 and a["where"] != "lock" and before.distance_to(target) < 0.4:
			var wb: Dictionary = blds.get(bld, {})
			goal = ["stand", "work_console" if not wb.is_empty() and String(wb["def"]) in CONSOLE_DEFS else "work_bench"]
		elif not dead and bool(a.get("sleeping", false)) and not inside:
			goal = ["lie", "sleep"]
	rec["pos"] = now
	var moved: float = Vector2(now.x - before.x, now.z - before.z).length() / maxf(dt, 0.0001)
	rec["speed"] = lerpf(float(rec["speed"]), moved, 1.0 - exp(-dt * 8.0))
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
	_sync_crate(rec, lib, cargo, dead)

## Turn at up to 5 rad/s with easing: facing eases, it never snaps.
func _turn(y0: float, y1: float, dt: float) -> float:
	var d: float = angle_difference(y0, y1)
	var step: float = clampf(d * (1.0 - exp(-dt * 9.0)), -5.0 * dt, 5.0 * dt)
	return y0 + step

## World positions (floor height) of a room's Anchor_Aisle_<i> points (cached per room).
func _aisles_of(meta: Dictionary) -> Array:
	if meta.has("aisles_w"):
		return meta["aisles_w"]
	var out: Array = []
	var fy: float = (meta["xf"] as Transform3D).origin.y + FLOOR_Z * float(meta["tpl"].get("scale", 1.0))
	for an in meta["anchors"]:
		if String(an).begins_with("Aisle_"):
			var p: Vector3 = (meta["anchors"][an] as Transform3D).origin
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
			out.append(base + Vector3(dir.x, 0, dir.y) * (k * QUEUE_GAP))
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
	var fy: float = (meta["xf"] as Transform3D).origin.y + FLOOR_Z * float(meta["tpl"].get("scale", 1.0))
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
		if a["where"] == "out" or a["state"] != "alive":
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
		var cands: Array = _slots_of(view.bmeta.get(rid))
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
				qlist.append_array(_outside_points(rid))
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
			or (bool(rec.get("slot_q", false)) and rec.has("slot") and (rec["pos"] as Vector3).distance_to(rec["slot"]) < 0.15)
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
			pushed += 1
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
	var k := 0
	var n := 0
	for it in list:
		var rec: Dictionary = it[0]
		var lib: Dictionary = it[1]
		var p: Vector3 = _dp(rec)
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
			all[k + 18] = float(rec["look"])
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
		all[k + 18] = float(rec["look"])
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
			all[b0 + 1] = 0.0
			all[b0 + 3] = 0.0
		_bd_used = mini(BD_ROWS, _bd_used + n)
	for part in e["parts"]:
		var m: MultiMesh = part["mm"]
		var h: int = part["head"]
		var buf: PackedFloat32Array = all
		var cnt: int = n
		if h >= 0:
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
		"body_ms": snappedf(_t_body / fr / 1000.0, 0.01), "bodies_per_frame": snappedf(_n_body / fr, 0.1), "write_ms": snappedf(_t_write / fr / 1000.0, 0.01), "lamps_ms": snappedf(_t_lamps / fr / 1000.0, 0.01), "blend_why_per_frame": _why_avg(fr), "slots": stats_slots.duplicate()}
	_why = {}
	_t_body = 0
	_t_write = 0
	_t_lamps = 0
	_n_body = 0
	_prof_frames = 0
	for v in libs:
		var lib: Dictionary = libs[v]
		out[v] = {"status": status.get(v, ""), "tris": lib["tris"], "clips": (lib["clips"] as Dictionary).size(), "missing": lib["missing"], "rows": lib["rows"], "bake_ms": snappedf(float(lib["bake_ms"]), 0.1), "parts": (lib["parts"] as Array).size(), "heads": lib["heads"], "shared": lib["shared"]}
	for v in ["suit", "in"]:
		if not libs.has(v):
			out[v] = {"status": status.get(v, "missing")}
	return out
