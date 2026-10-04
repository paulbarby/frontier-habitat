extends SceneTree
## RENDER doorway gate (Paul 2026-10-03: "beams at every door entrance" in the follow view with the roofs on).
## Loads saves headless with every roof closed and every room drawn as in the follow view (interior, ceiling,
## partition tops), builds the follow camera's physics bodies (fx_cam_phys: the DRAWN parts, hidden groups and
## doorway-masked wall segments left out) and passes a follow camera through up to N doorways of different room
## types and sizes, both ways: the eye 1.8 m over the floor, the person 1.6 m ahead on the same line.
## Per camera step (0.1 m, while the door plane lies between the lens and the person):
##   beam: a ray from the lens to the person (head, chest) or to the upper door opening (1.7-2.1 m, three across)
##         meets roof, ceiling or band geometry (groups Roof, CeilTop, WallsUp, PartTop) in the door opening
##         (within 0.75 m of the door plane, between the jambs) -> a bad frame;
##   gap:  a ray from the lens to the wall above the door head (2.30-2.58 m, three across; only rays at most 10 deg
##         above the horizon, the top of the follow camera's frame) finds no surface
##         within 0.75 m past the door plane (sky or void above the door) -> a bad frame (the upper patch stands 0.32 m inside the ring).
## Target: 0 bad frames.
## Also (V5 §19.4, orchestrator 2026-10-04):
##   prop: a ray down through the door's clear zone (1.90 m wide, 2.36 m into the room, 0.24-2.40 m over the floor,
##         5 x 6 points) meets a drawn Interior or Tall part (hidden Tall parts are out of the physics) -> a prop;
##   every doorway at an angle content/door_blocked.json now blocks (old saves) is tested too (beam, gap, prop),
##   whatever its room type.
##   node tools/godot.mjs script res://tools/render_doorway_gate.gd [n=20]
const CamPhys = preload("res://presentation/fx_cam_phys.gd")
const SAVES := ["res://content/saves/showcase_v3_late.fhsave", "res://content/saves/showcase_v5.fhsave", "res://build/web_render/doors8.fhsave"]
const BEAM_GROUPS := ["Roof", "CeilTop", "WallsUp", "PartTop"]
const DOOR_ZONE := 0.75   # m either side of the door plane: the opening (frame, housing, wall)
var main
var f := 0
var si := 0
var n_want := 20
var phase := 0
var doors: Array = []
var di := 0
var cp
var wait := 0
var seen_keys := {}
var total := {"doors": 0, "frames": 0, "beam": 0, "gap": 0, "prop": 0, "zone_doors": 0, "blocked_doors": 0, "blocked_found": 0}
var fails: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			n_want = int(a.substr(2))
	CamPhys.include_glass = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	match phase:
		0:
			if si >= SAVES.size():
				_report()
				return true
			if not FileAccess.file_exists(SAVES[si]):
				si += 1
				return false
			main._import_bytes(FileAccess.get_file_as_bytes(SAVES[si]))
			# (the follow view never draws far meshes (world_view._far_lod: follow_id < 0 only); the gate's camera
			# is not a follow camera, so far copies with roofs came in from 80 m: 1,020 false beams, 2026-10-04)
			main.view.far_lod_on = false
			wait = 240
			phase = 1
		1:
			wait -= 1
			if wait == 120:
				main.view._no_cutaway = true
				main.view.force_show_in = true
				main.view.debug_cmd("cutaway 0")
			if wait > 0:
				return false
			cp = CamPhys.new(main.view.inst, main.view.get_world_3d())
			doors = _pick_doors()
			di = 0
			phase = 2
		2:
			if di >= doors.size() or (int(total["doors"]) >= n_want and not bool(doors[di].get("blocked", false))):
				cp.clear()
				si += 1
				phase = 0
				return false
			var d: Dictionary = doors[di]
			cp.sync(d["pos"], float(f) * 10.0)
			while not CamPhys._order.is_empty():
				CamPhys.step(1000000)
			cp.sync(d["pos"], float(f) * 10.0 + 5.0)
			wait = 3
			phase = 3
		3:
			wait -= 1
			if wait > 0:
				return false
			_test_door(doors[di])
			di += 1
			phase = 2
	return false

## Doors of distinct room types and sizes (template key), the save's order.
func _pick_doors() -> Array:
	var out: Array = []
	var v = main.view
	for d in v.doors.doors:
		var rid: int = int(d["room"])
		if not v.bmeta.has(rid):
			continue
		var key: String = String(v.bmeta[rid].get("tpl", {}).get("key", "?")).get_file()
		var blocked: bool = _door_blocked(rid, d["pos"])
		if blocked:
			total["blocked_found"] = int(total["blocked_found"]) + 1
		if seen_keys.has(key) and not blocked:
			continue
		seen_keys[key] = true
		var b: Dictionary = main.sim.state["buildings"][rid]
		var c: Vector2 = b["pos"]
		var p: Vector3 = d["pos"]
		var inward := Vector3(c.x - p.x, 0.0, c.y - p.z).normalized()
		out.append({"pos": p, "in": inward, "key": key + (" BLOCKED" if blocked else ""), "room": rid, "def": String(b["def"]), "blocked": blocked})
	out.sort_custom(func(x, y): return bool(x.get("blocked", false)) and not bool(y.get("blocked", false)))
	# Junction mouths (no doorway kit: the corridor meets the junction ring): up to 3 per save.
	var nj := 0
	for lid in main.sim.state["buildings"]:
		var l: Dictionary = main.sim.state["buildings"][lid]
		if String(l.get("def", "")) != "corridor" or nj >= 3:
			continue
		for end in ["p0", "p1"]:
			var e: Vector2 = l[end]
			for jid in v.bmeta:
				var jb: Dictionary = main.sim.state["buildings"].get(jid, {})
				if jb.is_empty() or String(jb["def"]) != "junction":
					continue
				var jc: Vector2 = jb["pos"]
				var jr: float = float(jb["radius"])
				if e.distance_to(jc) < jr + 1.5 and nj < 3:
					var other: Vector2 = l["p1"] if end == "p0" else l["p0"]
					var dv: Vector2 = (other - jc).normalized()
					var jy: float = (v.bmeta[jid]["xf"] as Transform3D).origin.y
					var mp := Vector3(jc.x + dv.x * (jr - 0.32), jy, jc.y + dv.y * (jr - 0.32))
					out.append({"pos": mp, "in": Vector3(-dv.x, 0.0, -dv.y), "key": "junction mouth %d" % nj, "room": int(jid), "def": "junction"})
					nj += 1
	return out

## Is this doorway at a model angle content/door_blocked.json blocks for its room model?
func _door_blocked(rid: int, p: Vector3) -> bool:
	var v = main.view
	var b: Dictionary = main.sim.state["buildings"][rid]
	var key: String = String(v.bmeta[rid].get("tpl", {}).get("key", "")).get_file().get_slice("@", 0).get_slice(":", 0).trim_suffix(".glb")
	var db: Dictionary = main.sim.content.get("door_blocked", {})
	var rec = db.get(key, db.get(String(b["def"]), null))
	if not (rec is Dictionary):
		return false
	var c: Vector2 = b["pos"]
	var phi: float = atan2(-(p.z - c.y), p.x - c.x)
	var beta: float = fposmod(rad_to_deg(phi - float(b.get("rot", 0.0))), 360.0)
	for span in (rec.get("blocked", []) as Array):
		var a0: float = float(span[0])
		var a1: float = float(span[1])
		for bb in [beta, beta - 360.0, beta + 360.0]:
			if bb > a0 + 0.5 and bb < a1 - 0.5:
				return true
	return false

## Drawn props in the door's clear zone (rays down through a 5 x 6 grid).
func _zone_props(d: Dictionary) -> String:
	var p: Vector3 = d["pos"]
	var nin: Vector3 = d["in"]
	var side: Vector3 = nin.cross(Vector3.UP).normalized()
	var fy: float = p.y + 0.14
	var b: Dictionary = main.sim.state["buildings"].get(int(d["room"]), {})
	var sc: float = 1.0
	if main.view.bmeta.has(int(d["room"])):
		sc = float(main.view.bmeta[int(d["room"])].get("tpl", {}).get("scale", 1.0))
	for lat in [-0.8, -0.4, 0.0, 0.4, 0.8]:
		for dep in [0.4, 0.8, 1.2, 1.6, 2.0, 2.3]:
			var q: Vector3 = p + nin * dep * sc + side * lat * sc
			var a := Vector3(q.x, fy + 2.40, q.z)
			var hit: float = cp.ray(a, Vector3(q.x, fy + 0.24, q.z))
			if hit < INF:
				var dl: String = String(cp.dbg_last)
				# (a door at an angle door_blocked.json now blocks (old saves): only hideable Tall parts count; the
				# furniture that blocked the angle stays, and the walk test below must pass)
				if dl.contains(":Tall") or (dl.contains(":Interior") and not bool(d.get("blocked", false))):
					return "%s at lat %.1f depth %.1f, %.2f m down" % [dl, lat, dep, hit]
	return ""

func _test_door(d: Dictionary) -> void:
	var p: Vector3 = d["pos"]
	var nin: Vector3 = d["in"]
	var fy: float = p.y + 0.14
	var side: Vector3 = nin.cross(Vector3.UP).normalized()
	total["doors"] = int(total["doors"]) + 1
	var bad_here := 0
	for way in [1.0, -1.0]:
		var walk: Vector3 = nin * way
		for k in range(0, 51):
			var off: float = -2.5 + 0.1 * k
			var cam: Vector3 = p + walk * off + Vector3(0.0, fy - p.y + 1.8, 0.0)
			var pers: Vector3 = p + walk * (off + 1.6) + Vector3(0.0, fy - p.y, 0.0)
			# (only while the door plane lies between the lens and the person)
			if not (off < -0.05 and off + 1.6 > 0.05):
				continue
			total["frames"] = int(total["frames"]) + 1
			var why := ""
			var targets: Array = [pers + Vector3(0, 1.6, 0), pers + Vector3(0, 1.25, 0)]
			for h in [1.7, 2.1]:
				for lat in [-0.45, 0.0, 0.45]:
					targets.append(p + side * lat + Vector3(0.0, fy - p.y + h, 0.0))
			for t in targets:
				var hit: float = cp.ray(cam, t)
				# (only a hit in the door opening counts: within DOOR_ZONE m of the door plane and between the
				# jambs; the airlock's chamber walls further in are walls, not beams across the door)
				var hp: Vector3 = cam + (t - cam).normalized() * hit if hit < INF else Vector3.INF
				if hit < INF and (absf((hp - p).dot(nin)) > DOOR_ZONE or absf((hp - p).dot(side)) > 0.8):
					hit = INF
				if hit < INF:
					var g: String = String(cp.dbg_last).get_slice(":", String(cp.dbg_last).count(":"))
					# (orchestrator 2026-10-03: an airlock's chamber walls and inner door frame are RoofChamber,
					# which group_of files under Roof; they are walls a walker goes round, not roof beams)
					if g == "Roof" and String(cp.dbg_last).begins_with("airlock"):
						g = "RoofChamber"
					for bg in BEAM_GROUPS:
						if g == bg or g.begins_with(bg + "_") or g.ends_with("_" + bg):
							why = "beam %s at %.2f m (%s)" % [cp.dbg_last, hit, str((t - p).snapped(Vector3.ONE * 0.01))]
							break
				if why != "":
					break
			if why == "":
				var dpl: float = absf(off)   # distance from the lens to the door plane along the walk
				for h2 in [2.30, 2.45, 2.58]:
					for lat2 in [-0.6, 0.0, 0.6]:
						var t2: Vector3 = p + side * lat2 + Vector3(0.0, fy - p.y + h2, 0.0)
						var dl: float = cam.distance_to(t2)
						# (only what the follow camera can show: it looks along the walk, about 15 deg down, 50 deg
						# frame; a point over 10 deg above the horizon is above the frame)
						var tv: Vector3 = t2 - cam
						if atan2(tv.y, Vector2(tv.x, tv.z).length()) > deg_to_rad(10.0):
							continue
						var hit2: float = cp.ray(cam, cam + (t2 - cam).normalized() * (dl + 0.75))
						if hit2 == INF:
							why = "gap at h %.2f lat %.1f cam %s target %s; along the ray: %s" % [h2, lat2, str(cam.snapped(Vector3.ONE * 0.01)), str(t2.snapped(Vector3.ONE * 0.01)), _hits_along(cam, cam + (t2 - cam).normalized() * (dl + 6.0))]
							break
						if hit2 < dl - 0.35 - dpl * 0.0:
							pass   # (something nearer the lens hides the area: no gap visible)
					if why != "":
						break
			if why != "":
				bad_here += 1
				if why.begins_with("beam"):
					total["beam"] = int(total["beam"]) + 1
				else:
					total["gap"] = int(total["gap"]) + 1
				if fails.size() < 60:
					fails.append("%s %s (%s) %s cam off %.1f: %s" % [d["def"], d["key"], str(d["room"]), "in" if way > 0 else "out", off, why])
	if String(d["def"]) != "junction" and String(d["def"]) != "airlock":
		total["zone_doors"] = int(total["zone_doors"]) + 1
		var zp: String = _zone_props(d)
		if zp != "":
			total["prop"] = int(total["prop"]) + 1
			if fails.size() < 60:
				fails.append("%s %s (%s) prop in the clear zone: %s" % [d["def"], d["key"], str(d["room"]), zp])
	if bool(d.get("blocked", false)):
		total["blocked_doors"] = int(total["blocked_doors"]) + 1
	# the walk: the entry lane (0.8-1.6 m in from the door point; the walk grid keeps a wall band nearer, the axis and 0.3 m either side) is free floor in
	# the room's walk grid (fx_npc planner)
	if String(d["def"]) != "junction" and main.view.npc != null and main.view.npc.planner != null:
		var pl = main.view.npc.planner
		var blocked_at := ""
		# a walk from 0.8 m outside the door into the room (its free centre point): the planner finds a path, and
		# the path stays within 3 x the straight distance (a lane round the furniture is fine)
		var rb: Dictionary = main.sim.state["buildings"][int(d["room"])]
		var fy2: float = p.y + 0.14
		var a2: Vector3 = p - nin * 0.8 + Vector3(0, fy2 - p.y, 0)
		var goal: Vector3 = pl.indoor_snap(Vector3((rb["pos"] as Vector2).x, fy2, (rb["pos"] as Vector2).y))
		var path: Array = pl.plan(a2, goal, true)
		var plen := 0.0
		var prev: Vector3 = a2
		for wpt in path:
			plen += Vector2((wpt as Vector3).x - prev.x, (wpt as Vector3).z - prev.z).length()
			prev = wpt
		var straight: float = Vector2(goal.x - a2.x, goal.z - a2.z).length()
		if path.is_empty() or Vector2(prev.x - goal.x, prev.z - goal.z).length() > 1.0:
			blocked_at = "no path to the room"
		elif plen > 3.0 * straight + 2.0:
			blocked_at = "path %.1f m for %.1f m" % [plen, straight]
		total["walk_doors"] = int(total.get("walk_doors", 0)) + 1
		if blocked_at != "":
			total["walk"] = int(total.get("walk", 0)) + 1
			if fails.size() < 60:
				fails.append("%s %s (%s) walk blocked %s" % [d["def"], d["key"], str(d["room"]), blocked_at])
	print("DOOR %-28s %-12s bad frames %d" % [d["key"], d["def"], bad_here])
	if bad_here > 0 and String(d["def"]) == "junction":
		var near := ""
		for h in main.view.inst.handles:
			var e: Dictionary = main.view.inst.handles[h]
			var o: Vector3 = (e["xf"] as Transform3D).origin
			if o.distance_to(p) < 3.0 and String(e["key"]).contains("upper"):
				near += " %s@%s y%.2f sy%.2f%s" % [String(e["key"]).get_file().left(22), str((o - p).snapped(Vector3.ONE * 0.1)), o.y - p.y, (e["xf"] as Transform3D).basis.y.length(), "(body)" if cp._bodies.has(h) and (cp._bodies[h]["rid"] as RID).is_valid() else "(no body)"]
		print("   near:", near)
		# a ray from 1 m inside the junction to each upper patch centre: does physics see it?
		for h in main.view.inst.handles:
			var e2: Dictionary = main.view.inst.handles[h]
			var o2: Vector3 = (e2["xf"] as Transform3D).origin
			if o2.distance_to(p) < 3.0 and String(e2["key"]).contains("upper") and o2.y - p.y > 2.0:
				var c2: Vector3 = (e2["xf"] as Transform3D) * Vector3(0.0, 0.5, 0.0)
				var from: Vector3 = p + nin * 1.0 + Vector3(0, 1.8, 0)
				var hh: float = cp.ray(from, c2 + (c2 - from).normalized() * 0.5)
				print("   patch centre %s from %s: hit %s %s | basis %s" % [str((c2 - p).snapped(Vector3.ONE * 0.01)), str((from - p).snapped(Vector3.ONE * 0.01)), str(hh), cp.dbg_last if hh < INF else "", str((e2["xf"] as Transform3D).basis)])
				break
		print("   p %s in %s" % [str(p), str(nin)])

func _hits_along(a: Vector3, b: Vector3) -> String:
	var out := ""
	var s0: Vector3 = a
	var u: Vector3 = (b - a).normalized()
	for i in 4:
		var h: float = cp.ray(s0, b)
		if h == INF:
			break
		out += "%.2f %s; " % [a.distance_to(s0 + u * h), cp.dbg_last]
		s0 = s0 + u * (h + 0.02)
	return out if out != "" else "nothing within 6 m"

func _report() -> void:
	for l in fails:
		print("  FAIL ", l)
	var ok: bool = int(total["beam"]) == 0 and int(total["gap"]) == 0 and int(total["prop"]) == 0 and int(total.get("walk", 0)) == 0
	print("DOORWAY GATE: %d doorways, %d frames, beam %d, gap %d | clear zone: %d doorways, %d with a prop | walk lane blocked %d of %d | blocked-angle doorways (old saves): %d found, %d tested | %s" % [int(total["doors"]), int(total["frames"]), int(total["beam"]), int(total["gap"]), int(total["zone_doors"]), int(total["prop"]), int(total.get("walk", 0)), int(total.get("walk_doors", 0)), int(total["blocked_found"]), int(total["blocked_doors"]), "PASS" if ok else "FAIL"])
