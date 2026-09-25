extends SceneTree
## RENDER path check (V3_1 §4.4, a delivery gate). Runs the game headless on
## showcase_v3_late and scene_final, 10 game minutes each at speed 4, and samples every
## colonist body every frame (30 fps) at its DRAWN position:
##  (a) wall: body inside a room's wall band (±0.25 m of the wall line) outside a door opening
##  (b) furniture: body on a furniture cell of a room (fx_nav grid) that it is not using
##  (c) outside intrusion: a body outside (sim where == "out") inside a structure footprint,
##      a corridor tube or a pad
##  (d) slide: a body that moves faster than 2 x its clip speed (a non-walking clip at
##      > 0.3 m/s game speed), or a jump of > 1.5 m in one frame (teleport)
##  (e) inside body in open ground (sim where == "in", drawn outside every room and tube)
## Writes art/npc/path_check.json.
##   node tools/godot.mjs script res://tools/render_path_check.gd [label] [minutes]

const Nav = preload("res://presentation/fx_nav.gd")
const DT := 1.0 / 30.0
const SAVES := ["res://content/saves/showcase_v3_late.fhsave", "res://build/web_render/scene_final.fhsave"]
const LOCO := ["walk", "run", "carry_walk", "injured_walk"]

var main
var label := "run"
var minutes := 10.0
var save_i := -1
var frames := 0
var frames_want := 0
var res := {}
var cur := {}
var last := {}      # agent id -> Vector3 drawn last frame
var last_fade := {}
var last_logic := {}
var last_off := {}
var _dbg := 0
var _dbg2 := 0
var ex := {}        # "kind:detail" -> count (for the report)
var t_start := 0

func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	for s in a:
		if s.begins_with("--"):
			continue
		if s.is_valid_float():
			minutes = float(s)
		else:
			label = s
	var scene: PackedScene = load("res://main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	t_start = Time.get_ticks_msec()

func _next_save() -> bool:
	save_i += 1
	if save_i >= SAVES.size():
		return false
	var path: String = SAVES[save_i]
	if not FileAccess.file_exists(path):
		print("missing save ", path)
		return _next_save()
	main._import_bytes(FileAccess.get_file_as_bytes(path))
	main.set_speed(4)
	if "noyield" in label:
		main.view.npc.door_yield = false
	main.rig.target_distance = 60.0
	main.rig.distance = 60.0
	var c: Vector2 = Vector2.ZERO
	var nb := 0
	for id in main.sim.state["buildings"]:
		var b: Dictionary = main.sim.state["buildings"][id]
		if b["kind"] == "room":
			c += b["pos"]
			nb += 1
	if nb > 0:
		main.focus_on(c / nb)
	frames = 0
	frames_want = int(minutes * 60.0 / 4.0 / DT)
	last = {}
	last_logic = {}
	last_off = {}
	cur = {"save": path.get_file(), "samples": 0, "inside_samples": 0, "outside_samples": 0,
		"a_wall": 0, "b_furniture": 0, "c_outside_intrusion": 0, "d_slide": 0, "d_teleport": 0, "e_void": 0,
		"a_by_room": {}, "b_by_room": {}, "c_by_what": {}, "d_by_clip": {}, "e_by_mode": {}, "a_by_mode": {}}
	res[path.get_file()] = cur
	return true

func _process(_delta: float) -> bool:
	if main == null or main.sim == null:
		return false
	if save_i < 0 or frames >= frames_want:
		if save_i >= 0:
			_finish_save()
		if not _next_save():
			_write()
			return true
		# Let the view build the new colony before sampling.
		for k in 5:
			main._process(DT)
		return false
	main.set_process(false)
	main._process(DT)
	frames += 1
	if frames > 30:
		_sample()
	return false

func _dump_grid(rid: int) -> void:
	var view = main.view
	var pl = view.npc.planner
	if not view.bmeta.has(rid):
		return
	var cg = pl.coarse(rid)
	var g: Dictionary = Nav.grid_of(view.bmeta[rid]["tpl"])
	if cg == null or g.is_empty():
		return
	var n: int = g["n"]
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var half: float = g["half"]
	var hb: int = int(view.doors.hb_masks.get(rid, 0))
	for j in n:
		for i in n:
			var q := Vector2((i + 0.5) * Nav.CELL - half, (j + 0.5) * Nav.CELL - half)
			var o: int = Nav.at(g, q, hb, int(view.doors.masks.get(rid, 0)))
			var col := Color(0.9, 0.9, 0.9)
			if pl.blocked_local(cg, q):
				col = Color(0.7, 0.75, 0.9)
			if o == 1:
				col = Color(0.8, 0.3, 0.2)
			elif o == 2:
				col = Color(0.2, 0.2, 0.2)
			img.set_pixel(i, j, col)
	for d in pl.doors_of(rid):
		for key in ["in", "out"]:
			var lq: Vector2 = pl._to_local(rid, d[key])
			var ii: int = int((lq.x + half) / Nav.CELL)
			var jj: int = int((lq.y + half) / Nav.CELL)
			for di in range(-1, 2):
				for dj in range(-1, 2):
					if ii + di >= 0 and jj + dj >= 0 and ii + di < n and jj + dj < n:
						img.set_pixel(ii + di, jj + dj, Color(0, 0.8, 0) if key == "in" else Color(0, 0.3, 1))
	img.resize(n * 3, n * 3, Image.INTERPOLATE_NEAREST)
	img.save_png("res://build/web_render/grid_%s_%d.png" % [main.sim.state["buildings"][rid]["def"], rid])

func _finish_save() -> void:
	for rid in [193, 51, 647, 195, 2101, 1534, 49, 645]:
		if main.sim.state["buildings"].has(rid):
			_dump_grid(rid)
	if main.sim.state["buildings"].has(193):
		var pl = main.view.npc.planner
		var b: Dictionary = main.sim.state["buildings"][193]
		for d in pl.doors_of(193):
			var line := []
			var dd: float = float(b["radius"]) - 0.75
			while dd > float(b["radius"]) - 2.6:
				var tp: Vector2 = (b["pos"] as Vector2) + (d["dir"] as Vector2) * dd
				line.append("%.2f:%s" % [dd, "F" if pl.free_in_room(193, Vector3(tp.x, 0.8, tp.y)) else "b"])
				dd -= 0.1
			print("KDOOR dir %s in %s R %.2f %s" % [str(d["dir"]), str(d["in"]), float(b["radius"]), " ".join(line)])
	var s: int = maxi(1, int(cur["samples"]))
	cur["b_furniture_pct"] = snappedf(100.0 * float(cur["b_furniture"]) / maxf(1.0, float(cur["inside_samples"])), 0.001)
	cur["frames"] = frames
	cur["game_minutes"] = snappedf(frames * DT * 4.0 / 60.0, 0.01)
	print("planner ", main.view.npc.planner.stats if main.view.npc.planner != null else {})
	print("%s: samples %d, (a) wall %d, (b) furniture %d (%.3f %% of %d inside), (c) outside %d, (d) slide %d, teleport %d, (e) void %d" % [
		cur["save"], s, cur["a_wall"], cur["b_furniture"], cur["b_furniture_pct"], cur["inside_samples"], cur["c_outside_intrusion"], cur["d_slide"], cur["d_teleport"], cur["e_void"]])
	print("   (f) body pairs under 0.40 m: doorway %d, corridor %d" % [int(cur.get("f_overlap_door", 0)), int(cur.get("f_overlap_tube", 0))])

## Which model parts (group/material) cover a local point in the furniture height band.
func _who(tpl: Dictionary, q: Vector2) -> Array:
	var out: Array = []
	for p in tpl["parts"]:
		var grp: String = p["group"]
		if bool(p.get("shadow_only", false)) or not (grp in ["Interior", "WallsIn", "Tall", "Walls"]):
			continue
		var mesh: Mesh = p["mesh"]
		var xf: Transform3D = p.get("local", Transform3D.IDENTITY)
		for si in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ii = arr[Mesh.ARRAY_INDEX]
			if not (ii is PackedInt32Array) or (ii as PackedInt32Array).is_empty():
				continue
			var k := 0
			while k + 2 < ii.size():
				var a: Vector3 = xf * v[ii[k]]
				var b: Vector3 = xf * v[ii[k + 1]]
				var c: Vector3 = xf * v[ii[k + 2]]
				k += 3
				var lo: float = minf(a.y, minf(b.y, c.y)) - 0.14
				var hi: float = maxf(a.y, maxf(b.y, c.y)) - 0.14
				if hi < 0.2 or lo > 1.9:
					continue
				var a2 := Vector2(a.x, a.z)
				var b2 := Vector2(b.x, b.z)
				var c2 := Vector2(c.x, c.z)
				if Geometry2D.point_is_inside_triangle(q, a2, b2, c2) or Geometry2D.get_closest_point_to_segment(q, a2, b2).distance_to(q) < 0.07 or Geometry2D.get_closest_point_to_segment(q, b2, c2).distance_to(q) < 0.07:
					var m: Material = mesh.surface_get_material(si)
					var tag: String = "%s/%s c%s" % [grp, (m.resource_name if m != null else ""), str(((a2 + b2 + c2) / 3.0).snappedf(0.1))]
					if not (tag in out):
						out.append(tag)
					if out.size() > 5:
						return out
	return out

func _bump(d: Dictionary, k: String) -> void:
	d[k] = int(d.get(k, 0)) + 1

## Door openings of a room: [{dir: Vector2, half: float (m)}].
func _openings(view, rid: int, room: Dictionary) -> Array:
	var out: Array = []
	var c: Vector2 = room["pos"]
	var rr: float = float(room["radius"])
	for d in view.doors.doors:
		if int(d["room"]) == rid:
			var dp: Vector3 = d["pos"]
			out.append({"dir": (Vector2(dp.x, dp.z) - c).normalized(), "half": 0.80})
	if String(room["def"]) == "junction":
		for lid in main.sim.state["buildings"]:
			var l: Dictionary = main.sim.state["buildings"][lid]
			if l["kind"] == "link" and l["def"] == "corridor" and (int(l.get("a", -1)) == rid or int(l.get("b", -1)) == rid):
				var other: Vector2 = l["p1"] if int(l.get("a", -1)) == rid else l["p0"]
				out.append({"dir": (other - c).normalized(), "half": 1.20})
	if String(room["def"]) == "airlock" and view.bmeta.has(rid):
		var bx: Vector3 = (view.bmeta[rid]["xf"] as Transform3D).basis.x
		out.append({"dir": Vector2(bx.x, bx.z).normalized(), "half": 0.80})
	return out

## Critic round 14: two standing bodies closer than 0.40 m (drawn) with one of them in a
## doorway zone (1.1 m round a doorway centre), or in a corridor tube.
func _door_overlaps(npc, agents: Dictionary) -> void:
	var cells := {}
	var P := {}
	for id in npc.agents:
		if not agents.has(id) or agents[id]["state"] != "alive":
			continue
		var r: Dictionary = npc.agents[id]
		if String(r["sm"].pose_state) != "stand" or float(r.get("fade", 1.0)) < 0.99:
			continue
		var p: Vector3 = npc._dp(r)
		P[id] = p
		var k: int = int(floor(p.x)) * 8192 + int(floor(p.z))
		if not cells.has(k):
			cells[k] = []
		(cells[k] as Array).append(id)
	for id in P:
		var p: Vector3 = P[id]
		var cx: int = int(floor(p.x))
		var cz: int = int(floor(p.z))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for oid in cells.get((cx + dx) * 8192 + cz + dz, []):
					if int(oid) <= int(id):
						continue
					var q: Vector3 = P[oid]
					if Vector2(p.x - q.x, p.z - q.z).length() >= 0.40:
						continue
					var where := ""
					if npc._door_near(p) != null or npc._door_near(q) != null:
						where = "door"
					elif String(npc.planner.region_of(p, true)["k"]) == "tube":
						where = "tube"
					if where != "":
						cur["f_overlap_" + where] = int(cur.get("f_overlap_" + where, 0)) + 1
						var ra: Dictionary = npc.agents[id]
						var rb: Dictionary = npc.agents[oid]
						var mv: String = ("M" if float(ra.get("speed", 0.0)) > 0.15 else "s") + ("M" if float(rb.get("speed", 0.0)) > 0.15 else "s")
						var ab: int = npc.view.airlock._airlock_ids().filter(func(x): return Vector2(p.x, p.z).distance_to(main.sim.state["buildings"][x]["pos"]) < float(main.sim.state["buildings"][x]["radius"]) + 1.5).size()
						var fk: String = "%s:%s:%s:%s-%s" % [where, mv, "airlock" if ab > 0 else "room", String(ra["mode"]), String(rb["mode"])]
						var fm: Dictionary = cur.get_or_add("f_by", {})
						fm[fk] = int(fm.get(fk, 0)) + 1
						var fl: Array = cur.get_or_add("f_detail", [])
						if fl.size() < 12 and frames % 50 == 0:
							fl.append("f%d %d %s %s goal %s | %d %s %s goal %s" % [frames, int(id), str(Vector2(p.x, p.z).snappedf(0.01)), String(agents[id]["where"]), str(ra.get("lockg", {}).get("zone", "-")), int(oid), str(Vector2(q.x, q.z).snappedf(0.01)), String(agents[oid]["where"]), str(rb.get("lockg", {}).get("zone", "-"))])

func _sample() -> void:
	var view = main.view
	var npc = view.npc
	if npc == null:
		return
	var blds: Dictionary = main.sim.state["buildings"]
	var agents: Dictionary = main.sim.state["agents"]
	var gr: float = maxf(float(npc.game_rate), 0.05)
	_door_overlaps(npc, agents)
	for id in npc.agents:
		if not agents.has(id):
			continue
		var a: Dictionary = agents[id]
		if a["state"] != "alive":
			continue
		var rec: Dictionary = npc.agents[id]
		var p: Vector3 = npc._dp(rec)
		var q := Vector2(p.x, p.z)
		cur["samples"] = int(cur["samples"]) + 1
		var mode: String = rec["mode"]
		var pz: Dictionary = rec["sm"].pose()
		var clip: String = pz["a"]
		# Slides and jumps.
		if last.has(id):
			var lp: Vector3 = last[id]
			var dist: float = Vector2(p.x - lp.x, p.z - lp.z).length()
			if dist > 1.5 and float(rec.get("fade", 1.0)) >= 0.999 and float(last_fade.get(id, 1.0)) >= 0.999:
				cur["d_teleport"] = int(cur["d_teleport"]) + 1
				_bump(cur["d_by_clip"], "jump:" + mode + ":" + String(a["where"]) + (":off" if (rec.get("off", Vector3.ZERO) as Vector3).length() > 0.3 else ""))
			elif dist <= 1.5 and dist > 0.05 and minf(float(rec.get("fade", 1.0)), float(last_fade.get(id, 1.0))) <= 0.001:
				# A short move while fully faded out (an airlock rider faded into the chamber): unseen.
				cur["d_fade_short"] = int(cur.get("d_fade_short", 0)) + 1
			elif dist > 1.5 and minf(float(rec.get("fade", 1.0)), float(last_fade.get(id, 1.0))) <= 0.001:
				# The fade jump (a gap over 25 m): the body is fully faded out on this frame, so
				# nothing is drawn moving. Counted apart, not as a slide.
				cur["d_hidden_jump"] = int(cur.get("d_hidden_jump", 0)) + 1
				cur["d_hidden_min_m"] = snappedf(minf(float(cur.get("d_hidden_min_m", 1e9)), dist), 0.01)
			else:
				var gs: float = dist / DT / gr
				if not (clip in LOCO) and String(pz.get("b", "")) == "" and gs > 0.3:
					cur["d_slide"] = int(cur["d_slide"]) + 1
					_bump(cur["d_by_clip"], clip + ":" + mode)
					var dl: Array = cur.get_or_add("d_detail", [])
					if dl.size() < 40:
						var lp0: Vector3 = last_logic.get(id, rec["pos"])
						dl.append("%s %s gs %.2f logical %.2f m/s off %s->%s pz %s speed %.2f tgt %.2f wp %d fade %.2f" % [clip, mode, gs, Vector2(rec["pos"].x - lp0.x, rec["pos"].z - lp0.z).length() / DT / gr, str(last_off.get(id, Vector3.ZERO)), str((rec.get("off", Vector3.ZERO) as Vector3).snappedf(0.01)), str(pz), float(rec.get("speed", 0.0)), (rec["pos"] as Vector3).distance_to(rec.get("tval", rec["pos"])), (rec.get("wp", []) as Array).size(), float(rec.get("fade", 1.0))])
		last_logic[id] = rec["pos"]
		last_off[id] = (rec.get("off", Vector3.ZERO) as Vector3).snappedf(0.01)
		last[id] = p
		last_fade[id] = float(rec.get("fade", 1.0))
		# Which room (drawn position) and the wall band.
		var in_room := -1
		for rid in blds:
			var r: Dictionary = blds[rid]
			if r["kind"] != "room" or not view.bmeta.has(rid) or view.bmeta[rid]["mode"] != "inst":
				continue
			var rr: float = float(r["radius"])
			var d: float = q.distance_to(r["pos"])
			if d > rr + 0.5:
				continue
			var g: Dictionary = Nav.grid_of(view.bmeta[rid]["tpl"]) if view.bmeta[rid].has("tpl") else {}
			if g.is_empty():
				continue
			var s: float = float(view.bmeta[rid]["tpl"].get("scale", 1.0))
			var wall_line: float = rr - 0.20 * s
			if absf(d - wall_line) <= 0.25:
				var dir: Vector2 = (q - (r["pos"] as Vector2)).normalized()
				var open := false
				for o in _openings(view, rid, r):
					if (o["dir"] as Vector2).dot(dir) > 0.0 and absf((o["dir"] as Vector2).cross(dir)) * d <= float(o["half"]):
						open = true
						break
				if not open:
					cur["a_wall"] = int(cur["a_wall"]) + 1
					_bump(cur["a_by_room"], String(r["def"]))
					_bump(cur["a_by_mode"], mode + ":" + String(a["where"]) + ":" + str(Vector2i(q)) + ":" + String(rec["var"]))
					var al: Array = cur.get_or_add("a_detail", [])
					if al.size() < 40:
						var wq0 = (rec.get("wp", []) as Array)
						al.append("%s d%.2f wall%.2f pos %s logical %s off %s mode %s where %s var %s clip %s reg %s wp0 %s goal %s fade %.2f" % [r["def"], d, wall_line, str(q.snappedf(0.01)), str(Vector2(rec["pos"].x, rec["pos"].z).snappedf(0.01)), str((rec.get("off", Vector3.ZERO) as Vector3).snappedf(0.01)), mode, a["where"], rec["var"], clip, str(npc.planner.region_of(rec["pos"], true)), str(wq0[0] if not wq0.is_empty() else ""), str(rec.get("wp_goal", "")), float(rec.get("fade", 1.0))] + " wp %s tval %s" % [str((rec.get("wp", []) as Array).slice(0, 6).map(func(w): return Vector2(w.x, w.z).snappedf(0.01))), str(rec.get("tval", ""))] + " c %s opens %s" % [str((r["pos"] as Vector2).snappedf(0.01)), str(_openings(view, rid, r).map(func(o): return "%.0f/%.1f" % [rad_to_deg((o["dir"] as Vector2).angle_to(dir)), o["half"]]))])
			if d < wall_line - 0.25:
				in_room = rid
				# Furniture.
				cur["inside_samples"] = int(cur["inside_samples"]) + 1
				var using := false
				# Just left a seat, bed or bench: it still stands in that furniture (the one it used).
				if rec.has("left_from") and p.distance_to(rec["left_from"]) < 1.2:
					using = true
				if String(rec["sm"].pose_state) != "stand" or rec["sm"].is_busy() or mode == "at_anchor" or mode == "leaving" or (mode == "to_anchor" and not rec["anchor"].is_empty() and p.distance_to(rec["anchor"].get("pos", Vector3.INF)) < 1.0):
					using = true
				if not using:
					var loc2: Vector2 = npc.planner._to_local(rid, p)
					var loc := Vector3(loc2.x, 0.0, loc2.y)
					var hb: int = int(view.doors.hb_masks.get(rid, 0))
					if Nav.at(g, Vector2(loc.x, loc.z) / 1.0, hb, int(view.doors.masks.get(rid, 0))) == 1:
						cur["b_furniture"] = int(cur["b_furniture"]) + 1
						var dz := 99.0
						for dd in npc.planner.doors_of(rid):
							var op: Vector2 = (r["pos"] as Vector2) + (dd["dir"] as Vector2) * (float(r["radius"]) - 0.45)
							dz = minf(dz, q.distance_to(op))
						_bump(cur.get_or_add("b_zone", {}), "door<1.5" if dz < 1.5 else ("door<3" if dz < 3.0 else "room"))
						if _dbg < 0 and frames > 300 and dz < 1.5 and (frames % 7) == 0:
							_dbg += 1
							var ws: Array = []
							var prevp: Vector3 = rec["pos"]
							for wq in (rec.get("wp", []) as Array).slice(0, 8):
								var cgd = npc.planner.coarse(rid)
								ws.append("%s free%s los%s" % [str(Vector2(wq.x, wq.z).snappedf(0.01)), str(npc.planner.free_in_room(rid, wq)), str(npc.planner.same_leg(prevp, wq, true))])
								prevp = wq
							print("DBG q%d fr%d room %s %d model %s d %.2f R %.2f loc %s who %s pos %s logical %s goal %s | %s" % [int(rec.get("wpq", -1)), frames, r["def"], rid, String(view.bmeta[rid]["tpl"].get("key", "")).get_file(), d, rr, str(loc2.snappedf(0.01)), str(_who(view.bmeta[rid]["tpl"], loc2)), str(q.snappedf(0.01)), str(Vector2(rec["pos"].x, rec["pos"].z).snappedf(0.01)), str(rec.get("wp_goal", Vector3.ZERO)), str(ws)])
						_bump(cur["b_by_room"], String(r["def"]))
						var lg2: Vector2 = npc.planner._to_local(rid, rec["pos"])
						var lg := Vector3(lg2.x, 0.0, lg2.y)
						_bump(cur.get_or_add("b_by_mode", {}), mode + ":" + clip + (":logical_free" if Nav.at(g, Vector2(lg.x, lg.z), hb, int(view.doors.masks.get(rid, 0))) == 0 else ":logical_blocked") + (":slot" if rec.has("slot") else "") + (":pfree" if npc.planner.free_in_room(rid, rec["pos"]) else ":pblk") + ":" + String(r["def"]) + ":q" + str(int(rec.get("wpq", -1))) + ":wp" + str((rec.get("wp", []) as Array).size()))
		# Outside bodies in structures, tubes and pads.
		var where: String = a["where"]
		if where == "out":
			cur["outside_samples"] = int(cur["outside_samples"]) + 1
			# A body still walking inside (a tube, on its way to the airlock) is not outside.
			var preg: Dictionary = npc.planner.region_of(rec["pos"], false) if npc.planner != null else {"k": "out"}
			if in_room < 0 and not (mode == "at_anchor") and preg["k"] == "out":
				var what := ""
				for bid in blds:
					var b: Dictionary = blds[bid]
					if b["kind"] == "link":
						if b["def"] != "corridor":
							continue
						var a0: Vector2 = b["p0"]
						var ab: Vector2 = (b["p1"] as Vector2) - a0
						var t: float = clampf((q - a0).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
						if q.distance_to(a0 + ab * t) < 1.1:
							what = "corridor"
							break
					else:
						var lim: float = float(b["radius"]) * (0.8 if b["kind"] == "exterior" else 1.0) - 0.2
						# The airlock and the lander hatch are the ways in; a body serving a machine
						# kneels at its Anchor_Service, which is inside the machine's circle.
						if (b["kind"] == "room" and String(b["def"]) == "airlock") or String(b["def"]) == "lander":
							continue
						# (a body getting up at a machine's Anchor_Service, which lies inside the machine's circle)
						if int(rec["use"].get("b", -2)) == int(bid) or (rec.has("left_from") and p.distance_to(rec["left_from"]) < 1.5) or (mode == "leaving" and not rec["anchor"].is_empty() and p.distance_to(rec["anchor"].get("pos", Vector3.INF)) < 0.5):
							continue
						if q.distance_to(b["pos"]) < lim:
							what = String(b["def"])
							break
				if what != "":
					cur["c_outside_intrusion"] = int(cur["c_outside_intrusion"]) + 1
					_bump(cur["c_by_what"], what + ":" + mode)
		elif where == "in" and in_room < 0:
			# Inside, not in a room: must be in a corridor tube.
			var ok := false
			for bid in blds:
				var b2: Dictionary = blds[bid]
				if b2["kind"] == "link" and b2["def"] == "corridor":
					var c0: Vector2 = b2["p0"]
					var cd: Vector2 = (b2["p1"] as Vector2) - c0
					var t2: float = clampf((q - c0).dot(cd) / maxf(cd.length_squared(), 0.0001), 0.0, 1.0)
					if q.distance_to(c0 + cd * t2) < 1.15:
						ok = true
						break
				elif b2["kind"] == "room" and q.distance_to(b2["pos"]) < float(b2["radius"]) + (2.2 if String(b2["def"]) == "airlock" else 0.3):
					# (an airlock's porch counts: the body is walking out of the outer door)
					ok = true
					break
				elif int(bid) == int(a.get("bld", -1)) and q.distance_to(b2["pos"]) < float(b2["radius"]) + 1.3:
					# (a room model without stand anchors, the lander: its ring positions)
					ok = true
					break
			if not ok:
				cur["e_void"] = int(cur["e_void"]) + 1
				if _dbg2 < 6 and frames > 400:
					_dbg2 += 1
					var wl: Array = []
					for wq in (rec.get("wp", []) as Array).slice(0, 6):
						wl.append(str(Vector2(wq.x, wq.z).snappedf(0.1)))
					print("EDBG pos %s sim %s bld %s goal %s regpos %s reggoal %s q %s slot %s wp %s" % [str(q.snappedf(0.1)), str(a["pos"]), str(a.get("bld", -1)), str(rec.get("wp_goal", Vector3.ZERO)), str(npc.planner.region_of(rec["pos"], true)), str(npc.planner.region_of(rec.get("wp_goal", Vector3.ZERO), true)), str(rec.get("slot_q", false)), str(rec.get("slot", "")), str(wl)])
				var nd := ""
				var ndd := 1e9
				for bid3 in blds:
					if blds[bid3]["kind"] == "link":
						continue
					var dd3: float = q.distance_to(blds[bid3]["pos"]) - float(blds[bid3]["radius"])
					if dd3 < ndd:
						ndd = dd3
						nd = String(blds[bid3]["def"])
				_bump(cur["e_by_mode"], mode + ":" + ("q" if bool(rec.get("slot_q", false)) else "") + ":" + String(rec["var"]) + ":" + nd + ":" + str(snappedf(ndd, 1.0)) + ":" + String(rec["use"].get("kind", "")))

func _write() -> void:
	var out := {"label": label, "date": Time.get_datetime_string_from_system(), "minutes_per_save": minutes, "speed": 4,
		"fps": 30, "wall_ms": Time.get_ticks_msec() - t_start, "saves": res,
		"targets": {"a_wall": 0, "c_outside_intrusion": 0, "d_slide": 0, "b_furniture_pct_max": 0.2}}
	var tot := {"a_wall": 0, "b_furniture": 0, "inside_samples": 0, "c_outside_intrusion": 0, "d_slide": 0, "d_teleport": 0, "e_void": 0, "samples": 0}
	for k in res:
		for f in tot:
			tot[f] = int(tot[f]) + int(res[k].get(f, 0))
	tot["b_furniture_pct"] = snappedf(100.0 * float(tot["b_furniture"]) / maxf(1.0, float(tot["inside_samples"])), 0.001)
	out["total"] = tot
	out["pass"] = int(tot["a_wall"]) == 0 and int(tot["c_outside_intrusion"]) == 0 and int(tot["d_slide"]) == 0 and int(tot["d_teleport"]) == 0 and float(tot["b_furniture_pct"]) <= 0.2
	var path := "res://art/npc/path_check.json" if label != "fixture" else "res://build/web_render/path_check_%s.json" % label
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	# Keep a copy per label (before / after).
	var f2 := FileAccess.open("res://build/web_render/path_check_%s.json" % label, FileAccess.WRITE)
	if f2 != null:
		f2.store_string(JSON.stringify(out, "  "))
		f2.close()
	print("TOTAL %s: samples %d | (a) wall %d | (b) furniture %d = %.3f %% | (c) outside %d | (d) slide %d, teleport %d | (e) void %d | %s" % [label, tot["samples"], tot["a_wall"], tot["b_furniture"], tot["b_furniture_pct"], tot["c_outside_intrusion"], tot["d_slide"], tot["d_teleport"], tot["e_void"], "PASS" if out["pass"] else "FAIL"])
	quit(0)
