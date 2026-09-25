extends SceneTree
## RENDER check of the airlock cycle (V3_1 §5.3). Loads saves, runs them at speed `speed`
## (default 1) for `minutes` game minutes, drives main._process(1/30) by hand and checks every
## frame, for every airlock with the kit:
##   closed_door   a body crosses a door plane inside its opening (|z| < 0.8 m) while that
##                 door is less than half open;
##   pump_open     a door more than 10 % open while the chamber pressure changes (0.05..0.95);
##   swap_chamber  a suit_swap clip playing in the chamber or outside;
##   wrong_clothes a body drawn outside (no room, no tube) in indoor clothes, or a body in a
##                 cycling chamber in indoor clothes;
##   riders_off    a rider outside the chamber while the chamber pressure changes.
## Prints a timeline of the first cycles and writes build/web_render/airlock_check_<label>.json.
##   node tools/godot.mjs script res://tools/render_airlock_check.gd [label] [minutes] [speed]

const DT := 1.0 / 30.0
const SAVES := ["res://content/saves/showcase_v31.fhsave", "res://content/saves/showcase_v3_late.fhsave"]
var main
var label := "run"
var minutes := 4.0
var speed := 1
var save_i := -1
var frames := 0
var frames_want := 0
var res := {}
var cur := {}
var timeline: Array = []
var _last := {}
var _side := {}
var trace_id := -1
var trace_lock := -1
var t_from := 0
var t_to := 1000000
var t_save := -1
var trace_save := ""

func _initialize() -> void:
	var nums: Array = []
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--"):
			continue
		if s.begins_with("tfrom="):
			t_from = int(s.substr(6))
			continue
		if s.begins_with("tto="):
			t_to = int(s.substr(4))
			continue
		if s.begins_with("tsave="):
			t_save = int(s.substr(6))
			continue
		if s.begins_with("lock="):
			trace_lock = int(s.substr(5))
			continue
		if s.begins_with("trace="):
			trace_id = int(s.substr(6))
			continue
		if s.is_valid_float():
			nums.append(float(s))
		else:
			label = s
	if nums.size() > 0:
		minutes = nums[0]
	if nums.size() > 1:
		speed = int(nums[1])
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _next_save() -> bool:
	save_i += 1
	if save_i >= SAVES.size():
		return false
	var path: String = SAVES[save_i]
	if not FileAccess.file_exists(path):
		print("missing save ", path)
		return _next_save()
	main._import_bytes(FileAccess.get_file_as_bytes(path))
	main.set_speed(speed)
	frames = 0
	frames_want = int(minutes * 60.0 / float(speed) / DT)
	cur = {"save": path.get_file(), "frames": 0, "cycles": 0, "swaps": 0, "closed_door": 0, "pump_open": 0,
		"swap_chamber": 0, "wrong_clothes": 0, "riders_off": 0, "pump_start_open": 0, "pump_starts": 0, "detail": []}
	res[path.get_file()] = cur
	_last = {}
	return true

func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	if save_i < 0 or frames >= frames_want:
		if not _next_save():
			_write()
			return true
		for k in 5:
			main._process(DT)
		return false
	main.set_process(false)
	main._process(DT)
	frames += 1
	cur["frames"] = frames
	if frames > 30:
		_sample()
	return false

func _bump(k: String, msg: String) -> void:
	cur[k] = int(cur[k]) + 1
	var ab: String = msg.get_slice(" ", 1) if msg.begins_with("airlock") else (msg.get_slice("airlock ", 1).get_slice(" ", 0) if msg.contains("airlock ") else "-")
	var pa: Dictionary = cur.get_or_add("by_airlock", {})
	pa[k + ":" + ab] = int(pa.get(k + ":" + ab, 0)) + 1
	var dl: Array = cur["detail"]
	var nk := 0
	for d0 in dl:
		if String(d0).begins_with(k + " "):
			nk += 1
	if nk < 6:
		dl.append("%s f%d %s" % [k, frames, msg])

func _sample() -> void:
	var view = main.view
	var al = view.airlock
	var npc = view.npc
	var sim = main.sim
	var blds: Dictionary = sim.state["buildings"]
	for bid in al.locks:
		if not blds.has(bid) or not view.bmeta.has(bid):
			continue
		var g: Dictionary = view.bmeta[bid].get("lockgeo", {})
		if g.is_empty() or not bool(g["kit"]):
			continue
		var st: Dictionary = al.locks[bid]
		var b: Dictionary = blds[bid]
		var cyc: Dictionary = b.get("lock", {}).get("cyc", {})
		var phase: String = String(cyc.get("phase", ""))
		var dir: String = String(cyc.get("dir", ""))
		var key: String = "%s/%s" % [phase, dir]
		if String(_last.get(bid, "")) != key:
			if phase == "enter":
				cur["cycles"] = int(cur["cycles"]) + 1
			if phase == "pump":
				cur["pump_starts"] = int(cur.get("pump_starts", 0)) + 1
				if float(st["inner"]) > 0.05 or float(st["outer"]) > 0.05:
					_bump("pump_start_open", "airlock %d inner %.2f outer %.2f" % [int(bid), float(st["inner"]), float(st["outer"])])
			_last[bid] = key
			if timeline.size() < 80:
				timeline.append("%s f%d airlock %d r%.1f %s %s riders %s | inner %.2f outer %.2f p %.2f" % [cur["save"], frames, int(bid), float(b["radius"]), phase, dir, str(cyc.get("agents", [])), float(st["inner"]), float(st["outer"]), float(st["p"])])
		if int(bid) == trace_lock and frames % 6 == 0 and frames < 700 and save_i == 0:
			var rs: Array = []
			for rid0 in cyc.get("agents", []):
				var rr0 = npc.agents.get(int(rid0))
				if rr0 != null:
					rs.append("%d:%s:%s" % [int(rid0), str(rr0.get("lockg", {}).get("zone", "-")), str(((g["xs"] as Transform3D).affine_inverse() * (rr0["pos"] as Vector3)).snappedf(0.1))])
			print("LOCK f%d %s %s pt %.2f | inner %.2f outer %.2f p %.2f | %s" % [frames, phase, dir, float(cyc.get("pt", 0.0)), float(st["inner"]), float(st["outer"]), float(st["p"]), str(rs)])
		var xs: Transform3D = g["xs"]
		var inv: Transform3D = xs.affine_inverse()
		var total: float = maxf(0.1, float(cyc.get("total", 10.0)))
		var pump_len: float = total * 0.5
		var late_pump: bool = phase == "pump" and float(cyc.get("pt", 0.0)) < pump_len * 0.5
		if float(st["p"]) > 0.05 and float(st["p"]) < 0.95 and (float(st["inner"]) > 0.1 or float(st["outer"]) > 0.1):
			_bump("pump_open", "airlock %d inner %.2f outer %.2f" % [int(bid), float(st["inner"]), float(st["outer"])])
		var riders: Array = cyc.get("agents", [])
		for id in npc.agents:
			var rec: Dictionary = npc.agents[id]
			var p: Vector3 = npc._dp(rec)
			if Vector2(p.x, p.z).distance_to(b["pos"]) > float(b["radius"]) + 3.0:
				continue
			var l: Vector3 = inv * p
			for side in [["inner", "inner_x"], ["outer", "outer_x"]]:
				var sk: String = "%d:%d:%s" % [int(bid), int(id), side[0]]
				var sd: float = signf(l.x - float(g[side[1]]))
				var crossed: bool = _side.has(sk) and float(_side[sk]) != sd and absf(l.x - float(g[side[1]])) < 0.4
				_side[sk] = sd
				if crossed and absf(l.z) < 0.8 and float(st[side[0]]) < 0.5:
					_bump("closed_door", "airlock %d %s door %.2f body %d local %s %s phase %s where %s goal %s var %s" % [int(bid), side[0], float(st[side[0]]), int(id), str(l.snappedf(0.01)), dir, phase, str(sim.state["agents"].get(id, {}).get("where", "?")), str(rec.get("lockg", {}).get("zone", "-")), rec["var"]])
			var in_chamber: bool = l.x > float(g["inner_x"]) + 0.1 and l.x < float(g["outer_x"]) - 0.1 and absf(l.z) < 1.3
			var pz: Dictionary = rec["sm"].pose()
			if String(pz["a"]) == "suit_swap" and (in_chamber or l.x > float(g["outer_x"])):
				_bump("swap_chamber", "airlock %d body %d local %s" % [int(bid), int(id), str(l.snappedf(0.01))])
			if in_chamber and phase in ["seal", "pump", "open"] and String(rec["var"]) != "suit":
				_bump("wrong_clothes", "in chamber, airlock %d body %d %s" % [int(bid), int(id), phase])
			if phase == "pump" and riders.has(int(id)) and not in_chamber and float(st["p"]) > 0.05 and float(st["p"]) < 0.95 and float(st["inner"]) < 0.02 and float(st["outer"]) < 0.02:
				_bump("riders_off", "airlock %d body %d d %.2f zone %s k %d var %s pose %s local %s" % [int(bid), int(id), (rec["pos"] as Vector3).distance_to(rec["lockg"]["pos"]), rec["lockg"]["zone"], riders.find(int(id)), rec["var"], str(rec["sm"].pose()["a"]), str(l.snappedf(0.01))])
	if trace_id >= 0 and npc.agents.has(trace_id) and frames % 10 == 0 and frames >= t_from and frames <= t_to and (t_save < 0 or t_save == save_i):
		var tr: Dictionary = npc.agents[trace_id]
		var sa: Dictionary = sim.state["agents"].get(trace_id, {})
		print("TRACE f%d sim %s where %s bld %s | drawn %s var %s mode %s goal %s tval %s wp %s" % [frames, str(sa.get("pos")), sa.get("where"), sa.get("bld"), str(Vector2(tr["pos"].x, tr["pos"].z).snappedf(0.01)), tr["var"], tr["mode"], str(tr.get("lockg", {}).get("zone", "-")), str(tr.get("tval", "")), str((tr.get("wp", []) as Array).slice(0, 4).map(func(w): return Vector2(w.x, w.z).snappedf(0.01)))])
	# Indoor clothes outside.
	for id in npc.agents:
		var rec2: Dictionary = npc.agents[id]
		if String(rec2["var"]) != "in" or bool(rec2["dead"]):
			continue
		var p2: Vector3 = npc._dp(rec2)
		var reg: Dictionary = npc.planner.region_of(p2, true) if npc.planner != null else {"k": "room"}
		if reg["k"] == "out":
			var near_lock := false
			_bump("wrong_clothes", "outside in indoor clothes body %d at %s where %s mode %s goal %s hold %.1f swap %s" % [int(id), str(Vector2(p2.x, p2.z).snappedf(0.1)), str(sim.state["agents"].get(id, {}).get("where", "?")), rec2["mode"], str(rec2.get("lockg", {}).get("zone", "-")), float(rec2.get("var_hold", 0.0)), str(rec2.has("swap"))])
	cur["swaps"] = int(npc.stats_slots.get("swaps", 0))

func _write() -> void:
	print("planner ", main.view.npc.planner.stats)
	print("npc ", main.view.npc.stats().get("prof_ms", {}), " walk ", main.view.npc.stats().get("walk_ms", -1))
	var out := {"label": label, "minutes": minutes, "speed": speed, "saves": res, "timeline": timeline}
	var f := FileAccess.open("res://build/web_render/airlock_check_%s.json" % label, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	for line in timeline.slice(0, 40):
		print(line)
	for k in res:
		var c: Dictionary = res[k]
		print("%s: cycles %d swaps %d | pump starts %d with a door over 5%% open %d | closed_door %d pump_open %d swap_chamber %d wrong_clothes %d riders_off %d" % [k, c["cycles"], c["swaps"], c["pump_starts"], c["pump_start_open"], c["closed_door"], c["pump_open"], c["swap_chamber"], c["wrong_clothes"], c["riders_off"]])
		print("   by airlock: ", c.get("by_airlock", {}))
		for d in (c["detail"] as Array).slice(0, 30):
			print("   ", d)
	quit(0)
