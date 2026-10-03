extends SceneTree
## RENDER grounding check (Paul 2026-10-01: "people float when they run"; V5 DoD 2: planted feet within 1 cm).
## Runs a save headless (fixed 1/60 s frames, speed 1 then 4) and, for every drawn body each frame, measures
## the clearance of its lower foot over the floor it stands on:
##   pose clearance  = min over both feet of min(ankle y - standing ankle y, toe y - standing toe y)
##                     (model space; the standing heights from frame 0 of the library's idle clip)
##   ground offset   = drawn body y - the floor under it (a room's floor top x its model scale, a corridor's
##                     floor, the terrain outside)
##   clearance       = ground offset + pose clearance
## A foot is "planted" at least once per stride: per body the MINIMUM clearance over every 0.8 s window
## (a walk or run cycle) is the planted-foot height. Fails: a window minimum over +1 cm (floats) or under
## -1 cm (sinks), while the body walks, runs or stands (not sitting, lying, kneeling or in a vehicle).
## Writes art/npc/ground_check.json.
##   node tools/godot.mjs script res://tools/render_ground_check.gd [save] [secs_per_speed=20]
const Npc = preload("res://presentation/fx_npc.gd")
var main
var save := "res://content/saves/showcase_v5.fhsave"
var secs := 20.0
var f := 0
var phase := 0
var speed_i := 0
const SPEEDS := [1, 4]
const DT := 1.0 / 60.0
const WIN := 0.8
var ref := {}            # lib key -> [ankle L y, toe L y, ankle R y, toe R y]
var hist := {}           # agent id -> [[t, clearance, key]]
var res := {"windows": 0, "float": 0, "sink": 0, "by_key": {}, "worst_float": [], "worst_sink": [], "offset_hist": {}}
var t := 0.0
var vals := {}           # key@speed -> [window minimum mm]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		save = a[0]
	if a.size() > 1:
		secs = float(a[1])
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if phase == 0:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		main.view.npc.plan_budget_us = 1 << 30
		main.step_cap_us = 1 << 30
		main.set_speed(SPEEDS[speed_i])
		phase = 1
		f = 0
		return false
	main.set_process(false)
	main._process(DT)
	if main.rig != null:
		main.rig.set_process(false)
		main.rig._process(DT)
	if f < 240:
		return false
	t += DT
	_sample()
	if f >= 240 + int(secs / DT):
		speed_i += 1
		if speed_i >= SPEEDS.size():
			_write()
			return true
		main.set_speed(SPEEDS[speed_i])
		f = 0
		hist = {}
	return false

func _ref(lib: Dictionary) -> Array:
	# (per library: a LOD1 library shares the LOD0 clips but has its own skeleton rest, 2026-10-03)
	var k: String = String(lib.get("pvariant", "")) + String(lib.get("status", "")) + (":lod1" if bool(lib.get("lod1", false)) else "")
	if ref.has(k):
		return ref[k]
	var names: Array = lib["names"]
	var row: int = int(Npc._row_f(lib, "idle", 0.0))
	var r := []
	for bn in ["foot.L", "toe.L", "foot.R", "toe.R"]:
		var bi: int = names.find(bn)
		r.append(Npc.bone_at(lib, row, bi).origin.y if bi >= 0 else 0.0)
	ref[k] = r
	return r

func _floor_under(rec: Dictionary, a: Dictionary) -> float:
	var npc = main.view.npc
	var p: Vector3 = Npc._dp(rec)
	if String(a.get("where", "")) == "out" or String(rec.get("var", "")) == "suit":
		return main.view.h(p.x, p.z)
	var rid: int = npc._room_at(Vector2(p.x, p.z))
	if rid >= 0:
		var b: Dictionary = main.sim.state["buildings"][rid]
		var fy: float = npc._floor_y(b)
		if int(main.sim.bdef(b["def"]).get("floors", 1)) > 1 and main.sim.get("floors") != null:
			# (the real floor the body is nearest to: the model's floor tops; SIM's floor index may differ
			# from the floor of the anchor a body stands at, and the body is drawn at the anchor)
			var nf: int = int(main.sim.bdef(b["def"]).get("floors", 1))
			var best := INF
			for k in nf:
				var ly: float = npc.level_y(b, k, 0.0)
				if absf(ly - Npc._dp(rec).y) < absf(best - Npc._dp(rec).y):
					best = ly
			fy = best
		return fy
	return INF   # corridors: their floor is the walker's own reference (not measured here)

func _sample() -> void:
	var npc = main.view.npc
	for id in npc.agents:
		var rec: Dictionary = npc.agents[id]
		var a: Dictionary = main.sim.state["agents"].get(id, {})
		if a.is_empty() or a["state"] != "alive" or String(a.get("where", "")) == "vehicle":
			continue
		var sm = rec["sm"]
		if sm.pose_state != "stand" or not (sm.phase in ["loop"]):
			hist.erase(id)
			continue
		var lib: Dictionary = npc.libs.get(String(rec.get("dk", rec.get("var", ""))), {})
		if lib.is_empty():
			continue
		var fl: float = _floor_under(rec, a)
		if fl == INF:
			hist.erase(id)
			continue
		# (multi-storey buildings and decks: the floor reference here is approximate; only the pose is
		# measured when the body is not within 0.25 m of the reference floor)
		var off_raw: float = Npc._dp(rec).y - fl
		if absf(off_raw) > 0.25:
			res["off_skipped"] = int(res.get("off_skipped", 0)) + 1
			var rk: String = String(main.sim.state["buildings"].get(main.view.npc._room_at(Vector2(Npc._dp(rec).x, Npc._dp(rec).z)), {}).get("def", "-"))
			var sk: Dictionary = res.get_or_add("skip_by", {})
			sk[rk] = int(sk.get(rk, 0)) + 1
			if int(res.get("dbg2", 0)) < 0 and rk != "airlock":
				res["dbg2"] = int(res.get("dbg2", 0)) + 1
				var fa2: Dictionary = main.sim.floors.agent_floor(a) if main.sim.get("floors") != null else {}
				print("SKIP id %d off %.2f pos %s %s floor %s key %s mode %s" % [int(id), off_raw, str(Npc._dp(rec).snapped(Vector3.ONE * 0.01)), rk, JSON.stringify(fa2), String(sm.cur), String(rec.get("mode", ""))])
			fl = Npc._dp(rec).y
		var pz: Dictionary = sm.pose()
		var names: Array = lib["names"]
		var r0: Array = _ref(lib)
		var cl := INF
		var k := 0
		for bn in ["foot.L", "toe.L", "foot.R", "toe.R"]:
			var bi: int = names.find(bn)
			if bi >= 0:
				cl = minf(cl, npc.bone_for_pose(lib, pz, bi).origin.y - float(r0[k]))
			k += 1
		var off: float = Npc._dp(rec).y - fl
		if (cl < -0.05 or off < -0.05 or off > 0.05) and int(res.get("dbg_n", 0)) < 14 and String(rec.get("var", "")) != "suit" and SPEEDS[speed_i] == 4:
			res["dbg_n"] = int(res.get("dbg_n", 0)) + 1
			print("DBG id %d cl %.3f off %.3f pos %s room %d %s speed %.2f lib %s" % [int(id), cl, off, str(Npc._dp(rec).snapped(Vector3.ONE * 0.01)), main.view.npc._room_at(Vector2(Npc._dp(rec).x, Npc._dp(rec).z)), String(main.sim.state["buildings"].get(main.view.npc._room_at(Vector2(Npc._dp(rec).x, Npc._dp(rec).z)), {}).get("def", "-")), float(rec.get("speed", 0)), String(rec.get("dk", ""))])
		var key: String = String(pz["a"]) if not sm.loco else ("run" if sm.run_latch else "walk")
		if not hist.has(id):
			hist[id] = []
		var h: Array = hist[id]
		h.append([t, off + cl, key, off])
		while not h.is_empty() and t - float(h[0][0]) > WIN:
			h.pop_front()
		if t - float(h[0][0]) >= WIN - DT * 1.5 and int(Engine.get_process_frames()) % 6 == 0:
			var mn := INF
			var same := true
			for e in h:
				mn = minf(mn, float(e[1]))
				if String(e[2]) != key:
					same = false
			if not same:
				continue
			res["windows"] = int(res["windows"]) + 1
			var bk: Dictionary = res["by_key"].get_or_add(key, {"n": 0, "float": 0, "sink": 0, "max_mm": -999.0, "min_mm": 999.0})
			bk["n"] = int(bk["n"]) + 1
			(vals.get_or_add(key + ("/suit" if String(rec.get("var", "")) == "suit" else "/in") + "@" + str(SPEEDS[speed_i]), []) as Array).append(mn * 1000.0)
			bk["max_mm"] = maxf(float(bk["max_mm"]), snappedf(mn * 1000.0, 0.1))
			bk["min_mm"] = minf(float(bk["min_mm"]), snappedf(mn * 1000.0, 0.1))
			var ob: String = "%d" % int(round(off * 100.0))
			res["offset_hist"][ob] = int(res["offset_hist"].get(ob, 0)) + 1
			if mn > 0.01:
				res["float"] = int(res["float"]) + 1
				bk["float"] = int(bk["float"]) + 1
				if (res["worst_float"] as Array).size() < 40:
					(res["worst_float"] as Array).append({"id": int(id), "key": key, "mm": snappedf(mn * 1000.0, 0.1), "off_mm": snappedf(off * 1000.0, 0.1), "speed": SPEEDS[speed_i], "lib": String(rec.get("dk", "")), "pos": str(Npc._dp(rec).snapped(Vector3.ONE * 0.01))})
			elif mn < -0.01:
				res["sink"] = int(res["sink"]) + 1
				bk["sink"] = int(bk["sink"]) + 1
				if (res["worst_sink"] as Array).size() < 40:
					(res["worst_sink"] as Array).append({"id": int(id), "key": key, "mm": snappedf(mn * 1000.0, 0.1), "off_mm": snappedf(off * 1000.0, 0.1), "speed": SPEEDS[speed_i], "lib": String(rec.get("dk", "")), "pos": str(Npc._dp(rec).snapped(Vector3.ONE * 0.01))})

func _write() -> void:
	res["save"] = save
	res["pass"] = int(res["float"]) == 0 and int(res["sink"]) == 0
	var fo := FileAccess.open("res://art/npc/ground_check.json", FileAccess.WRITE)
	fo.store_string(JSON.stringify(res, " "))
	print("GROUND CHECK %s: %d windows, float %d, sink %d | %s" % [save.get_file(), res["windows"], res["float"], res["sink"], "PASS" if res["pass"] else "FAIL"])
	for k in res["by_key"]:
		print("  ", k, " ", JSON.stringify(res["by_key"][k]))
	var ks: Array = vals.keys()
	ks.sort()
	for k in ks:
		var v: Array = vals[k]
		v.sort()
		var pc := func(q: float) -> float: return snappedf(float(v[clampi(int(q * (v.size() - 1)), 0, v.size() - 1)]), 0.1)
		print("  %s: n %d  p1 %.1f  p5 %.1f  p50 %.1f  p95 %.1f  p99 %.1f mm" % [k, v.size(), pc.call(0.01), pc.call(0.05), pc.call(0.5), pc.call(0.95), pc.call(0.99)])
		res["pct_" + k] = {"n": v.size(), "p1": pc.call(0.01), "p5": pc.call(0.05), "p50": pc.call(0.5), "p95": pc.call(0.95), "p99": pc.call(0.99)}
	print("  ground offset histogram (cm): ", JSON.stringify(res["offset_hist"]))
	for w in (res["worst_float"] as Array).slice(0, 8):
		print("  float ", JSON.stringify(w))
	for w in (res["worst_sink"] as Array).slice(0, 8):
		print("  sink ", JSON.stringify(w))
