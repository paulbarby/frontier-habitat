extends RefCounted
## The follow camera's sight tests against the DRAWN geometry (RENDER, 2026-10-03).
##
## The framing rule (critic round 41: no surface within 0.8 m across the frame centre, the person not hidden)
## was judged on the occluder grids (fx_occ, 0.2 m cells of the room models only) and the room volumes. Those
## miss what is drawn but is not a room model: doorway frames, corridor tubes, airlock and junction parts,
## crates; a 30-shot web sheet had 5-8 frames facing a surface the test called clear.
##
## Here every instancer handle (fx_instancer) within REACH m of the followed person gets a static physics body
## made of its drawn parts (one trimesh shape per group, the template's scale baked in); a group that is not
## drawn (hidden on that copy, its batch hidden, far-hidden) has its shape disabled. Rays are native physics
## queries (GodotPhysics3D, also in the web build): 11 per check, about 0.1 ms.
##
## Left out: glass, water, holograms, lights and decals (see-through or flat), name signs and people
## (fx_npc, fading near the lens). Roofs and ceiling liners count: a camera in a doorway under a room's eave saw
## the person past the roof's edge.

const Models = preload("res://presentation/models.gd")
const LAYER := 1 << 19
const REACH := 14.0
const SKIP_GROUPS := ["PorchTop", "NameSign", "Lights", "Rotor", "Beacon"]
static var include_glass := false   # measurement only (render_doorway_gate: glass closes a gap)
const JOB_TRIS := 700       # triangles per shape job (about 1 ms natively, 3-5 ms in the web build)

var inst
var space: RID
static var _shapes := {}    # template key -> [[group, ConcavePolygonShape3D], ...]
var _bodies := {}           # handle -> {rid, key, groups: [group...], xf}
var _at := Vector3.INF
var _cand: Array = []
var _cand_at := Vector3.INF
var _cand_t := -99.0
var _cand_probe := -1
var _t := -1.0
var _q := PhysicsRayQueryParameters3D.new()
var dbg_last := ""

func _init(instancer, world: World3D) -> void:
	inst = instancer
	space = world.space
	_q.collision_mask = LAYER
	_q.hit_back_faces = true
	_q.hit_from_inside = false

static func _use_group(g: String) -> bool:
	if g.begins_with("Decal") or g.contains("_Decal"):
		return false
	# (door leaves slide open with the instancer's per-copy extra transforms, which the static shape does not
	# follow: a closed leaf would block every doorway the person walks through)
	if g.begins_with("Door") or g.contains("_Door"):
		return false
	for sk in SKIP_GROUPS:
		if g == sk or g.begins_with(sk + "_") or g.ends_with("_" + sk):
			return false
	return true

## The shapes of a template, [] until they are built. Building is spread over frames (step): a room template has
## 10-50 k triangles and one trimesh build cost 30-65 ms natively (100+ ms frames in the web build, long-frame
## trace 2026-10-03); each job is one group (or one wall segment) of one template.
static var _jobs := {}        # template key -> {"jobs": [job...], "out": [[group, shape, seg]...]}
static var _order: Array = [] # template keys waiting, first come first served
static func _shapes_of(tpl: Dictionary) -> Array:
	var key: String = tpl["key"]
	if _shapes.has(key):
		return _shapes[key]
	if not _jobs.has(key):
		_jobs[key] = {"jobs": _plan(tpl), "out": []}
		_order.append(key)
	return []

static func _plan(tpl: Dictionary) -> Array:
	var s3: Vector3 = Models.scale3(tpl)
	var sb := Basis.from_scale(s3)
	var by_g := {}      # group -> job (unmasked surfaces)
	var jobs: Array = []
	for p in tpl.get("parts", []):
		if bool(p.get("shadow_only", false)):
			continue
		var g: String = String(p.get("group", ""))
		if not _use_group(g):
			continue
		var mesh: Mesh = p["mesh"]
		var xf: Transform3D = Transform3D(sb, Vector3.ZERO) * (p["xf"] as Transform3D)
		for si in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(si)
			var mn: String = mat.resource_name if mat != null else ""
			if (mn.contains("Glass") and not include_glass) or mn.contains("Water") or mn.contains("Holo") or mn.contains("Light") or mn.contains("Decal"):
				continue
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and not (include_glass and mn.contains("Glass")):
				continue
			# (big surfaces in index ranges of JOB_TRIS triangles: one job is a few ms)
			var il := 0
			var n_idx := 0
			if mesh is ArrayMesh:
				il = (mesh as ArrayMesh).surface_get_array_index_len(si)
				n_idx = il if il > 0 else (mesh as ArrayMesh).surface_get_array_len(si)
			else:
				var ar0: Array = mesh.surface_get_arrays(si)
				il = (ar0[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if ar0[Mesh.ARRAY_INDEX] is PackedInt32Array else 0
				n_idx = il if il > 0 else (ar0[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var i0 := 0
			if bool(p.get("mask", false)):
				while i0 < n_idx:
					var i1m: int = mini(n_idx, i0 + JOB_TRIS * 3)
					jobs.append({"g": g, "masked": true, "items": [[mesh, si, xf, i0, i1m, il > 0]]})
					i0 = i1m
				continue
			while i0 < n_idx:
				var i1: int = mini(n_idx, i0 + JOB_TRIS * 3)
				if not by_g.has(g) or int(by_g[g]["tris"]) + (i1 - i0) / 3 > JOB_TRIS:
					by_g[g] = {"g": g, "masked": false, "items": [], "tris": 0}
					jobs.append(by_g[g])
				by_g[g]["items"].append([mesh, si, xf, i0, i1, il > 0])
				by_g[g]["tris"] = int(by_g[g]["tris"]) + (i1 - i0) / 3
				i0 = i1
	return jobs

## Runs queued shape jobs for about budget_us (at least one). Returns true when a template was completed.
static func step(budget_us: int) -> bool:
	var t0: int = Time.get_ticks_usec()
	var done_any := false
	while not _order.is_empty() and (Time.get_ticks_usec() - t0 < budget_us or not done_any):
		var key: String = _order[0]
		var jb: Dictionary = _jobs[key]
		if (jb["jobs"] as Array).is_empty():
			_shapes[key] = jb["out"]
			_jobs.erase(key)
			_order.pop_front()
			done_any = true
			continue
		var job: Dictionary = (jb["jobs"] as Array).pop_front()
		(jb["out"] as Array).append_array(_run_job(job))
		done_any = true
	return done_any

static func _run_job(job: Dictionary) -> Array:
	var out: Array = []
	var g: String = job["g"]
	if not bool(job["masked"]):
		var am := ArrayMesh.new()
		for it in job["items"]:
			var arr: Array = (it[0] as Mesh).surface_get_arrays(int(it[1]))
			if arr.size() < Mesh.ARRAY_MAX or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var a2: Array = []
			a2.resize(Mesh.ARRAY_MAX)
			a2[Mesh.ARRAY_VERTEX] = (it[2] as Transform3D) * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			var idx = arr[Mesh.ARRAY_INDEX]
			var i0: int = int(it[3])
			var i1: int = int(it[4])
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				a2[Mesh.ARRAY_INDEX] = (idx as PackedInt32Array).slice(i0, i1)
			elif i0 > 0 or i1 < (a2[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				a2[Mesh.ARRAY_VERTEX] = (a2[Mesh.ARRAY_VERTEX] as PackedVector3Array).slice(i0, i1)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
			if am.get_surface_count() >= 250:
				out.append([g, _trimesh(am), -1])
				am = ArrayMesh.new()
		if am.get_surface_count() > 0:
			out.append([g, _trimesh(am), -1])
		return out
	# (the wall segments a copy hides at its doorways, fx_doors masks: UV2.x = segment + 1; one shape per
	# segment, so the doorway's hidden segments are no wall for the camera either)
	var it0: Array = job["items"][0]
	var arr0: Array = (it0[0] as Mesh).surface_get_arrays(int(it0[1]))
	var v: PackedVector3Array = (it0[2] as Transform3D) * (arr0[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var idx0 = arr0[Mesh.ARRAY_INDEX]
	var uv2 = arr0[Mesh.ARRAY_TEX_UV2]
	var has_uv: bool = uv2 is PackedVector2Array and (uv2 as PackedVector2Array).size() == v.size()
	var ii: PackedInt32Array = idx0 if idx0 is PackedInt32Array and (idx0 as PackedInt32Array).size() > 0 else PackedInt32Array(range(v.size()))
	ii = ii.slice(int(it0[3]), int(it0[4]))
	var per := {}
	var t := 0
	while t + 2 < ii.size():
		var sg: int = int((uv2 as PackedVector2Array)[ii[t]].x + 0.5) - 1 if has_uv else -1
		if not per.has(sg):
			per[sg] = PackedVector3Array()
		per[sg].append(v[ii[t]])
		per[sg].append(v[ii[t + 1]])
		per[sg].append(v[ii[t + 2]])
		t += 3
	for sg in per:
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(per[sg])
		out.append([g, sh, int(sg)])
	return out

static func _trimesh(am: ArrayMesh) -> ConcavePolygonShape3D:
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(am.get_faces())
	return sh

## Keeps the bodies of the drawn copies within REACH of p (refreshed after 2 m or 0.25 s; group visibility
## every call of `sync`).
func sync(p: Vector3, now: float) -> void:
	if _at.distance_to(p) < 2.0 and now - _t < 0.25:
		return
	_at = p
	_t = now
	# (the handles near p from a candidate list rebuilt every 2 s or 6 m: the instancer holds ~5,000 copies, a
	# full pass on every sync cost several ms a call in the web build)
	if _cand_at.distance_to(p) > 6.0 or now - _cand_t > 2.0 or not inst.handles.has(_cand_probe):
		_cand_at = p
		_cand_t = now
		_cand = []
		for h0 in inst.handles:
			var o0: Vector3 = (inst.handles[h0]["xf"] as Transform3D).origin
			if absf(o0.x - p.x) < REACH + 8.0 and absf(o0.z - p.z) < REACH + 8.0:
				_cand.append(h0)
				# (queue the shapes of everything within reach + 8 m now, so a structure's body is ready before
				# the person gets near: a body appearing mid-walk moved the camera arm in one step)
				var bt0: Dictionary = inst.batches.get(inst.handles[h0]["key"], {})
				if not bt0.is_empty():
					_shapes_of(bt0["tpl"])
		_cand_probe = _cand[0] if not _cand.is_empty() else -1
	var want := {}
	for h in _cand:
		if not inst.handles.has(h):
			continue
		var e: Dictionary = inst.handles[h]
		var o: Vector3 = (e["xf"] as Transform3D).origin
		if absf(o.x - p.x) > REACH or absf(o.z - p.z) > REACH:
			continue
		var bt: Dictionary = inst.batches.get(e["key"], {})
		if bt.is_empty():
			continue
		want[h] = true
		if not _bodies.has(h):
			var shs: Array = _shapes_of(bt["tpl"])
			if shs.is_empty():
				if not _shapes.has(e["key"]):
					want.erase(h)   # (not built yet: no body; asked again next sync)
					continue
				_bodies[h] = {"rid": RID(), "groups": [], "key": e["key"]}
				continue
			var rid: RID = PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
			PhysicsServer3D.body_set_collision_layer(rid, LAYER)
			PhysicsServer3D.body_set_collision_mask(rid, 0)
			var gs: Array = []
			var segs: Array = []
			# (a copy drawn with its own stretch on top of the template's scale, a corridor tube to its length:
			# its own shapes with that stretch in them)
			var xb: Basis = (e["xf"] as Transform3D).basis
			var kk: Basis = xb.orthonormalized().inverse() * xb * Basis.from_scale(Models.scale3(bt["tpl"])).inverse()
			var own: bool = not kk.is_equal_approx(Basis.IDENTITY)
			var keep: Array = []
			for sg in shs:
				var shp: Shape3D = sg[1]
				if own:
					var fs: PackedVector3Array = (sg[1] as ConcavePolygonShape3D).get_faces()
					for i in fs.size():
						fs[i] = kk * fs[i]
					var sh2 := ConcavePolygonShape3D.new()
					sh2.backface_collision = true
					sh2.set_faces(fs)
					shp = sh2
					keep.append(sh2)
				PhysicsServer3D.body_add_shape(rid, shp.get_rid())
				gs.append(sg[0])
				segs.append(sg[2])
			PhysicsServer3D.body_set_space(rid, space)
			_bodies[h] = {"rid": rid, "groups": gs, "segs": segs, "key": e["key"], "own": keep}
		var bd: Dictionary = _bodies[h]
		if not (bd["rid"] as RID).is_valid():
			continue
		# (the copy's transform without its scale: the scale is in the shape)
		var xf: Transform3D = e["xf"]
		var ux := Transform3D(xf.basis.orthonormalized(), xf.origin)
		if bd.get("xf") != ux:
			PhysicsServer3D.body_set_state(bd["rid"], PhysicsServer3D.BODY_STATE_TRANSFORM, ux)
			bd["xf"] = ux
		var hid: Dictionary = e["hidden"]
		var vis: Dictionary = bt.get("vis", {})
		var gs2: Array = bd["groups"]
		var sgs: Array = bd["segs"]
		var gc: Dictionary = e.get("gcustom", {})
		for i in gs2.size():
			var g: String = gs2[i]
			var off: bool = hid.has(g) or int(vis.get(g, 1)) <= 0 or inst.far_hidden.has(g)
			if not off and int(sgs[i]) >= 0 and gc.has(g):
				var mc: Color = gc[g]
				var m: int = int(mc.r) | (int(mc.g) << 16)
				off = (m >> int(sgs[i])) & 1 == 1
			PhysicsServer3D.body_set_shape_disabled(bd["rid"], i, off)
	if not _order.is_empty():
		_t = minf(_t, now - 0.17)   # (shapes still being built: look again in 0.08 s)
	for h in _bodies.keys():
		if not want.has(h):
			if (_bodies[h]["rid"] as RID).is_valid():
				PhysicsServer3D.free_rid(_bodies[h]["rid"])
			_bodies.erase(h)

## Distance from a to the first drawn surface toward b (INF = clear), and what it is (dbg_last).
func ray(a: Vector3, b: Vector3) -> float:
	var ss: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
	if ss == null:
		return INF
	_q.from = a
	_q.to = b
	var r: Dictionary = ss.intersect_ray(_q)
	if r.is_empty():
		return INF
	dbg_last = ""
	for h in _bodies:
		if _bodies[h]["rid"] == r.get("rid"):
			var gs: Array = _bodies[h]["groups"]
			var si: int = int(r.get("shape", -1))
			dbg_last = "%s:%s" % [String(_bodies[h].get("key", "?")).get_file(), gs[si] if si >= 0 and si < gs.size() else "?"]
			break
	return a.distance_to(r["position"])

## How far a sphere of radius r moves from a toward b before it touches a drawn surface (|b - a| = clear).
## A sphere that already touches one at a: falls back to the thin ray.
var _sph := SphereShape3D.new()
var _sq := PhysicsShapeQueryParameters3D.new()
func sweep(a: Vector3, b: Vector3, r: float) -> float:
	var ss: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
	var l: float = a.distance_to(b)
	if ss == null or l < 0.001:
		return l
	_sph.radius = r
	_sq.shape = _sph
	_sq.transform = Transform3D(Basis.IDENTITY, a)
	_sq.motion = b - a
	_sq.collision_mask = LAYER
	var res: PackedFloat32Array = ss.cast_motion(_sq)
	if res.size() < 2:
		return l
	if res[0] <= 0.0 and res[1] <= 0.0:
		var t: float = ray(a, b)
		return l if t == INF else t
	return l * res[0]

func body_count() -> int:
	return _bodies.size()

func clear() -> void:
	for h in _bodies:
		if (_bodies[h]["rid"] as RID).is_valid():
			PhysicsServer3D.free_rid(_bodies[h]["rid"])
	_bodies.clear()
	_at = Vector3.INF
