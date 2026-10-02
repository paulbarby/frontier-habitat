extends SceneTree
## RENDER seat check (Paul 2026-10-01: "people sit inside desks"; V5 DoD 3: no seated or lying body overlaps
## furniture, every room type). For every room model with Seat / Work / Bed anchors, a body of the tallest and
## the shortest adult variant (and a child at the bunks) is posed at each anchor exactly as fx_npc places it
## (the stand point, the anchor's facing, the seated / lying loop clips at 4 times each), and its limbs
## (capsules round the bones: torso 0.12 m, thigh 0.07 m, shin 0.05 m, arm 0.045 m, head 0.10 m) are
## tested against the room's furniture triangles (Interior, Tall, F<k>_Interior / _Terrace).
## Not counted: the furniture the body uses (the chair under and behind the hips; the bed under and over a
## lying body), and ground-level items (rugs, floor panels under 5 cm).
## An overlap = a limb deeper than TOL inside a furniture surface. Writes art/npc/seat_check.json.
##   node tools/godot.mjs script res://tools/render_seat_check.gd [filter] [tol_cm=2]
const Npc = preload("res://presentation/fx_npc.gd")
const Models = preload("res://presentation/models.gd")
const FLOOR_Z := 0.14
const CELL := 0.25
const SIT_CLIPS := ["sit_idle", "sit_type", "sit_eat"]
const LIE_CLIPS := ["sleep"]
const FURN_GROUPS := ["Interior", "Tall"]
## [bone a, bone b (or "" = a short stub along the parent direction), radius]
const SEGS := [
	["hips", "spine", 0.12], ["spine", "chest", 0.12], ["chest", "neck", 0.1], ["neck", "head", 0.05],
	["head", "", 0.1],
	["upper_arm.L", "forearm.L", 0.045], ["forearm.L", "hand.L", 0.04], ["hand.L", "", 0.035],
	["upper_arm.R", "forearm.R", 0.045], ["forearm.R", "hand.R", 0.04], ["hand.R", "", 0.035],
	["thigh.L", "shin.L", 0.07], ["shin.L", "foot.L", 0.05], ["foot.L", "toe.L", 0.045],
	["thigh.R", "shin.R", 0.07], ["shin.R", "foot.R", 0.05], ["foot.R", "toe.R", 0.045],
]
var tol := 0.02
var fix_mode := false   # "fix": compute the seat placement fixes and write presentation/navgrid/seat_fix.res
var fixes := {}         # model -> {anchor: metres back}
const SEAT_FIX_MAX := 0.08
const FIX_FILE := "res://presentation/navgrid/seat_fix.res"
var sit_clips: Array = SIT_CLIPS
var shift := 0.0   # sensitivity test only: every body moved this far forward (m)
var defs := {}
var report := {"models": {}, "anchors": 0, "poses": 0, "overlaps": 0, "worst": [], "by_seg": {}}

func _init() -> void:
	var filt := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tol_cm="):
			tol = float(a.substr(7)) / 100.0
		elif a == "fix":
			fix_mode = true
		elif a.begins_with("clips="):
			sit_clips = Array(a.substr(6).split(","))
		elif a.begins_with("shift_cm="):
			shift = float(a.substr(9)) / 100.0
		else:
			filt = a
	if not fix_mode and ResourceLoader.exists(FIX_FILE):
		var fr = load(FIX_FILE)
		if fr != null and (fr as Resource).has_meta("fix"):
			fixes = (fr as Resource).get_meta("fix")
	var bj = JSON.parse_string(FileAccess.get_file_as_string("res://content/buildings.json"))
	defs = bj if bj is Dictionary else {}
	var libs := {}
	for v in ["p_m3", "p_f2", "p_c1"]:
		var lib: Dictionary = Npc.load_lib(v)
		if bool(lib.get("ok", false)):
			libs[v] = lib
		else:
			print("no lib ", v)
	var t0: int = Time.get_ticks_msec()
	var dir := DirAccess.open("res://assets/models")
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".glb") and (filt == "" or f.contains(filt)):
			files.append(f)
	files.sort()
	for f in files:
		var name: String = f.get_basename()
		if name.begins_with("people_") or name.begins_with("astronaut") or name.begins_with("robot") or name.begins_with("rock") or name.begins_with("boulder") or name.begins_with("ship_") or name.begins_with("crate"):
			continue
		var tpl: Dictionary = Models._template_from_file("res://assets/models/" + f)
		var anchors: Dictionary = tpl.get("anchors", {})
		var use: Array = []
		for an in anchors:
			var s: String = String(an)
			if s.begins_with("Seat_") or s.begins_with("Work_") or s.begins_with("Bed_"):
				use.append(s)
		if use.is_empty():
			continue
		use.sort()
		_check_model(name, tpl, use, libs)
	report["ms"] = Time.get_ticks_msec() - t0
	report["tol_m"] = tol
	(report["worst"] as Array).sort_custom(func(x, y): return float(x["depth"]) > float(y["depth"]))
	report["worst"] = (report["worst"] as Array).slice(0, 60)
	report["pass"] = int(report["overlaps"]) == 0
	if fix_mode:
		var r := Resource.new()
		r.set_meta("fix", fixes)
		ResourceSaver.save(r, FIX_FILE, ResourceSaver.FLAG_COMPRESS)
		print("SEAT FIX: %s" % JSON.stringify(fixes))
	report["fixes"] = fixes
	var fo := FileAccess.open("res://art/npc/seat_check.json", FileAccess.WRITE)
	fo.store_string(JSON.stringify(report, " "))
	print("  overlaps by limb (deepest per anchor): ", JSON.stringify(report["by_seg"]))
	print("SEAT CHECK: %d models, %d anchors, %d poses, %d overlaps (> %.0f mm) | %s | %d ms" % [(report["models"] as Dictionary).size(), report["anchors"], report["poses"], report["overlaps"], tol * 1000.0, "PASS" if report["pass"] else "FAIL", report["ms"]])
	for w in (report["worst"] as Array).slice(0, 25):
		print("  %s %s %s %s: %s %.0f mm into %s at %s" % [w["model"], w["anchor"], w["variant"], w["clip"], w["seg"], float(w["depth"]) * 1000.0, w["part"], w["at"]])
	quit(0)

func _def_of(name: String) -> Dictionary:
	var best := ""
	for k in defs:
		if name.begins_with(String(k) + "_") and String(k).length() > best.length():
			best = k
	return defs.get(best, {})

## Furniture triangles of a template (model space) in a 2D hash (cell CELL m) over xz.
func _tris(tpl: Dictionary) -> Dictionary:
	var tris: Array = []   # [a, b, c, part name]
	for p in tpl["parts"]:
		if bool(p.get("shadow_only", false)):
			continue
		var grp: String = String(p["group"])
		var furn: bool = grp in FURN_GROUPS or grp.begins_with("Tall") or (grp.begins_with("F") and (grp.ends_with("_Interior") or grp.ends_with("_Terrace")))
		if not furn:
			continue
		var mesh: Mesh = p["mesh"]
		var xf: Transform3D = p["xf"]
		for si in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			var mname: String = mesh.surface_get_material(si).resource_name if mesh.surface_get_material(si) != null else "?"
			var n: int = (ix as PackedInt32Array).size() if ix != null else vs.size()
			for t in range(0, n, 3):
				var a: Vector3 = xf * vs[ix[t] if ix != null else t]
				var b: Vector3 = xf * vs[ix[t + 1] if ix != null else t + 1]
				var c: Vector3 = xf * vs[ix[t + 2] if ix != null else t + 2]
				# ground-level items (rugs, floor panels): feet stand on them
				if maxf(a.y, maxf(b.y, c.y)) < _floor_of(a.y) + 0.05:
					continue
				tris.append([a, b, c, "%s/%s" % [grp, mname]])
	var grid := {}
	for ti in tris.size():
		var t: Array = tris[ti]
		var lo := Vector2(minf(t[0].x, minf(t[1].x, t[2].x)), minf(t[0].z, minf(t[1].z, t[2].z)))
		var hi := Vector2(maxf(t[0].x, maxf(t[1].x, t[2].x)), maxf(t[0].z, maxf(t[1].z, t[2].z)))
		for gx in range(int(floor(lo.x / CELL)), int(floor(hi.x / CELL)) + 1):
			for gz in range(int(floor(lo.y / CELL)), int(floor(hi.y / CELL)) + 1):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					grid[key] = []
				grid[key].append(ti)
	return {"tris": tris, "grid": grid}

## The floor top under a model-space height (the apartment block: floors every 3.6 m).
static func _floor_of(y: float) -> float:
	var k: int = maxi(0, int(floor((y - 0.1) / 3.6)))
	return 3.6 * k + FLOOR_Z

func _check_model(name: String, tpl: Dictionary, use: Array, libs: Dictionary) -> void:
	var def: Dictionary = _def_of(name)
	var wpose: String = String(def.get("furniture", {}).get("work_pose", "stand"))
	var tg: Dictionary = _tris(tpl)
	var mrep := {"anchors": 0, "overlaps": 0, "worst_mm": 0.0}
	var anchors: Dictionary = tpl["anchors"]
	# Child bunks (residence tube / apartment units: Bed 4i+2, 4i+3 where the unit has children).
	var child_beds := {}
	var fur: Dictionary = def.get("furniture", {})
	var cb = fur.get("child_beds", 0)
	var has_kids: bool = (cb is Array and int((cb as Array).max()) > 0) or (not (cb is Array) and int(cb) > 0)
	if has_kids and not name.contains("executive"):
		for an in use:
			if String(an).begins_with("Bed_"):
				var bi: int = int(String(an).substr(4))
				if bi % 4 >= 2 and bi < 40:
					child_beds[an] = true
	for an in use:
		var xf: Transform3D = anchors[an]
		var p: Vector3 = xf.origin
		if p.y < 0.05:
			p.y = FLOOR_Z
		var fx: Vector3 = xf.basis.x
		var yaw: float = -atan2(fx.z, fx.x)
		p += Vector3(cos(yaw), 0.0, -sin(yaw)) * shift
		var clips: Array = []
		var kind := "sit"
		if String(an).begins_with("Seat_"):
			clips = sit_clips
		elif String(an).begins_with("Bed_"):
			clips = LIE_CLIPS
			kind = "lie"
		elif wpose == "sit":
			clips = ["sit_type"]
		else:
			continue
		var vlist: Array = ["p_c1"] if child_beds.has(an) else ["p_m3", "p_f2"]
		report["anchors"] = int(report["anchors"]) + 1
		mrep["anchors"] = int(mrep["anchors"]) + 1
		var back := Vector3(-cos(yaw), 0.0, sin(yaw))
		var side := Vector3(sin(yaw), 0.0, cos(yaw))
		# The game's seat placement fix (fx_npc: presentation/navgrid/seat_fix.res: [back, side] m), as drawn.
		var hf = (fixes.get(name, {}) as Dictionary).get(an, [0.0, 0.0]) if not fix_mode else [0.0, 0.0]
		if not (hf is Array):
			hf = [float(hf), 0.0]
		var worst: Dictionary = _worst(libs, vlist, clips, p + back * float(hf[0]) + side * float(hf[1]), yaw, kind, tg)
		# fix mode: the smallest move (back 0-8 cm, sideways 0-6 cm, 2 cm steps) that clears a seated body
		if fix_mode and kind == "sit" and not worst.is_empty() and float(worst["depth"]) > tol:
			var cands: Array = []
			for bi in 5:
				for si in [0, 1, -1, 2, -2, 3, -3]:
					if bi == 0 and si == 0:
						continue
					cands.append([bi * 0.02, si * 0.02])
			cands.sort_custom(func(x, y): return Vector2(x[0], x[1]).length() < Vector2(y[0], y[1]).length())
			for c in cands:
				var w2: Dictionary = _worst(libs, vlist, clips, p + back * float(c[0]) + side * float(c[1]), yaw, kind, tg)
				if w2.is_empty() or float(w2["depth"]) <= tol:
					(fixes.get_or_add(name, {}) as Dictionary)[an] = [snappedf(float(c[0]), 0.01), snappedf(float(c[1]), 0.01)]
					worst = w2
					break
		if not worst.is_empty() and float(worst["depth"]) > tol:
			report["overlaps"] = int(report["overlaps"]) + 1
			var sgk: String = String(worst["seg"]).get_slice(".", 0)
			report["by_seg"][sgk] = int(report["by_seg"].get(sgk, 0)) + 1
			mrep["overlaps"] = int(mrep["overlaps"]) + 1
			worst["model"] = name
			worst["anchor"] = an
			(report["worst"] as Array).append(worst)
		if not worst.is_empty():
			mrep["worst_mm"] = maxf(float(mrep["worst_mm"]), snappedf(float(worst["depth"]) * 1000.0, 0.1))
	report["models"][name] = mrep

func _worst(libs: Dictionary, vlist: Array, clips: Array, p: Vector3, yaw: float, kind: String, tg: Dictionary) -> Dictionary:
	var worst: Dictionary = {}
	for v in vlist:
		if not libs.has(v):
			continue
		var lib: Dictionary = libs[v]
		for clip in clips:
			if not (lib["clips"] as Dictionary).has(clip):
				continue
			var len_s: float = float(lib["clips"][clip]["len"])
			for k in 4:
				var t: float = len_s * (0.08 + 0.28 * k)
				report["poses"] = int(report["poses"]) + 1
				var r: Dictionary = _pose_depth(lib, clip, t, p, yaw, kind, tg)
				if not r.is_empty() and (worst.is_empty() or float(r["depth"]) > float(worst["depth"])):
					r["variant"] = v.substr(2)
					r["clip"] = "%s@%.1f" % [clip, t]
					worst = r
	return worst

## The deepest limb penetration of the posed body into furniture it does not use: {depth, seg, part, at} or {}.
func _pose_depth(lib: Dictionary, clip: String, t: float, p: Vector3, yaw: float, kind: String, tg: Dictionary) -> Dictionary:
	var body := Transform3D(Basis(Vector3.UP, yaw), p)
	var names: Array = lib["names"]
	var row: int = int(Npc._row_f(lib, clip, t))
	var pos := {}
	for bn in ["hips", "spine", "chest", "neck", "head", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]:
		var bi: int = names.find(bn)
		if bi < 0:
			return {}
		pos[bn] = body * Npc.bone_at(lib, row, bi).origin
	var hips: Vector3 = pos["hips"]
	var fwd: Vector3 = body.basis.x
	var feet_mid: Vector3 = ((pos["foot.L"] as Vector3) + (pos["foot.R"] as Vector3)) * 0.5
	var head: Vector3 = pos["head"]
	var best := {}
	for sg in SEGS:
		var a: Vector3 = pos[sg[0]]
		var b: Vector3
		if String(sg[1]) == "":
			# a stub: the head 0.12 m up the neck line; a hand 0.08 m on along the forearm
			var par: Vector3 = pos["neck"] if sg[0] == "head" else pos[String(sg[0]).replace("hand", "forearm")]
			b = a + (a - par).normalized() * (0.12 if sg[0] == "head" else 0.08)
		else:
			b = pos[sg[1]]
		var rad: float = float(sg[2])
		var n: int = maxi(2, int(ceil(a.distance_to(b) / 0.03)))
		for i in n + 1:
			var q: Vector3 = a.lerp(b, float(i) / float(n))
			var seen := {}
			for gx in range(int(floor((q.x - rad) / CELL)), int(floor((q.x + rad) / CELL)) + 1):
				for gz in range(int(floor((q.z - rad) / CELL)), int(floor((q.z + rad) / CELL)) + 1):
					for ti in tg["grid"].get(Vector2i(gx, gz), []):
						if seen.has(ti):
							continue
						seen[ti] = true
						var tri: Array = tg["tris"][ti]
						var cp: Vector3 = _closest_on_tri(q, tri[0], tri[1], tri[2])
						var d: float = cp.distance_to(q)
						if d >= rad:
							continue
						if _own(cp, kind, hips, fwd, feet_mid, head):
							continue
						var depth: float = rad - d
						if best.is_empty() or depth > float(best["depth"]):
							best = {"depth": depth, "seg": "%s-%s" % [sg[0], sg[1]], "part": tri[3], "at": "%.2f,%.2f,%.2f" % [cp.x, cp.y, cp.z]}
	return best

## Is a furniture point part of what the body uses? sit: the chair (within 0.3 m of the hips sideways, its seat front
## edge up to 0.32 m ahead and its back 0.42 m behind, below
## the hips + 0.65 m: seat, legs, backrest). lie: the bed (from 0.3 m past the feet to 0.3 m past the head,
## 0.5 m to each side, up to the hips + 0.35 m: mattress, pillow, blanket).
static func _own(cp: Vector3, kind: String, hips: Vector3, fwd: Vector3, feet: Vector3, head: Vector3) -> bool:
	if kind == "sit":
		var d := Vector2(cp.x - hips.x, cp.z - hips.z)
		# (behind the hips: the backrest; in front of the hips only the seat front edge, 0.18 m)
		var along: float = d.dot(Vector2(fwd.x, fwd.z))
		var side: float = absf(d.dot(Vector2(-fwd.z, fwd.x)))
		# (and the seat's front edge, 0.2-0.32 m ahead of the hips, low: no higher than the hips + 0.08 m;
		# a desk or table top is at least 0.4 m ahead and 0.25 m higher)
		if side < 0.3 and along >= 0.2 and along < 0.32 and cp.y < hips.y + 0.15:
			return true
		return cp.y < hips.y + 0.65 and side < 0.3 and along < 0.2 and along > -0.42
	var ax := Vector2(head.x - feet.x, head.z - feet.z)
	var l: float = ax.length()
	if l < 0.01:
		return false
	var u: Vector2 = ax / l
	var d2 := Vector2(cp.x - feet.x, cp.z - feet.z)
	var al: float = d2.dot(u)
	var sd: float = absf(d2.dot(Vector2(-u.y, u.x)))
	return al > -0.35 and al < l + 0.35 and sd < 0.5 and cp.y < hips.y + 0.35

## Closest point on triangle abc to p (Ericson, Real-Time Collision Detection 5.1.5).
static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var ap: Vector3 = p - a
	var d1: float = ab.dot(ap)
	var d2: float = ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp: Vector3 = p - b
	var d3: float = ab.dot(bp)
	var d4: float = ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc: float = d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cpv: Vector3 = p - c
	var d5: float = ab.dot(cpv)
	var d6: float = ac.dot(cpv)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb: float = d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va: float = d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den: float = 1.0 / (va + vb + vc)
	var v: float = vb * den
	var w: float = vc * den
	return a + ab * v + ac * w
