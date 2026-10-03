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
##   gap:  a ray from the lens to the wall above the door head (2.30-2.58 m, three across) finds no surface
##         within 0.75 m past the door plane (sky or void above the door) -> a bad frame (the upper patch stands 0.32 m inside the ring).
## Target: 0 bad frames.
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
var total := {"doors": 0, "frames": 0, "beam": 0, "gap": 0}
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
			if si >= SAVES.size() or int(total["doors"]) >= n_want:
				_report()
				return true
			if not FileAccess.file_exists(SAVES[si]):
				si += 1
				return false
			main._import_bytes(FileAccess.get_file_as_bytes(SAVES[si]))
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
			if di >= doors.size() or int(total["doors"]) >= n_want:
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
		if seen_keys.has(key):
			continue
		seen_keys[key] = true
		var b: Dictionary = main.sim.state["buildings"][rid]
		var c: Vector2 = b["pos"]
		var p: Vector3 = d["pos"]
		var inward := Vector3(c.x - p.x, 0.0, c.y - p.z).normalized()
		out.append({"pos": p, "in": inward, "key": key, "room": rid, "def": String(b["def"])})
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
	print("DOOR %-28s %-12s bad frames %d" % [d["key"], d["def"], bad_here])

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
	var ok: bool = int(total["beam"]) == 0 and int(total["gap"]) == 0
	print("DOORWAY GATE: %d doorways, %d frames, beam %d, gap %d | %s" % [int(total["doors"]), int(total["frames"]), int(total["beam"]), int(total["gap"]), "PASS" if ok else "FAIL"])
