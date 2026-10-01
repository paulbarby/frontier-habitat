extends RefCounted
## Follow-view smoothness probe (RENDER, V5 §3; Paul 2026-10-01 "the follow cam shakes and the person
## jitters"). Measurement only: world_view debug `fprobe start <secs> [in|out|any] | get | csv | stop`.
##
## The camera rig calls record() at the END of its follow frame (after the body moved and the camera
## was placed), so each sample holds the body and the camera of the SAME drawn frame.
## report() gives, over the frames where the person walks at a steady pace:
##   head_jit_px   RMS second difference of the head's screen position (px)
##   cam_jerk_mm   RMS second difference of the camera position (mm)
##   cam_yaw_deg   RMS second difference of the camera yaw (deg)
##   speed_rip_pct RMS of (frame speed - local mean) / local mean (%) of the drawn body
##   yaw_rip_deg   RMS second difference of the drawn body yaw (deg)
##   pops          frames where the wall pull-in changed the eye distance by > 8 % in one frame
##   clip_sw_min   locomotion state changes (idle / walk / run / other clip) per minute while moving

var view
var on := false
var secs := 20.0
var want := "any"         # which walker to pick when the person stops: in | out | any | keep
var t := 0.0
var rows: Array = []      # one Dictionary per frame
var cut_left := 0.0       # s: frames after a camera cut are not measured
var _still_t := 0.0
var hops := 0
var _last_bp = null
const H60 := 1.0 / 60.0

func _init(v) -> void:
	view = v

func start(s: float, w: String) -> String:
	secs = s
	want = w
	t = 0.0
	rows = []
	hops = 0
	_still_t = 0.0
	_last_bp = null
	on = true
	cut_left = 1.0
	if want != "keep" or view.follow_id < 0:
		var id: int = pick_walker(want, -1)
		if id < 0 or not view.follow_start(id):
			on = false
			return "no walker"
	return "probe %d s on %d" % [int(secs), view.follow_id]

## Remaining length of the person's current SIM walk (the legs of the same kind: in or out).
func sim_left(a: Dictionary) -> float:
	var rt = a.get("route", {})
	if typeof(rt) != TYPE_DICTIONARY or not (rt as Dictionary).has("legs"):
		return 0.0
	var legs: Array = rt["legs"]
	var li: int = int(a.get("li", 0))
	if li >= legs.size():
		return 0.0
	var m0: String = String(legs[li].get("m", ""))
	var p: Vector2 = a["pos"]
	var sum := 0.0
	for k in range(li, legs.size()):
		var leg: Dictionary = legs[k]
		if String(leg.get("m", "")) != m0:
			break
		var pts: Array = leg.get("pts", [])
		var i0: int = int(a.get("wi", 0)) if k == li else 0
		for i in range(i0, pts.size()):
			sum += p.distance_to(pts[i])
			p = pts[i]
	return sum

## The living person with the longest walk ahead (where == want unless want == any).
func pick_walker(w: String, not_id: int) -> int:
	var best := -1
	# (in a structure named by b:<def> any walk counts; else a person in it who stands, walks later)
	var bl := -1.0 if w.begins_with("b:") else 6.0
	for id in view.sim.state["agents"]:
		var a: Dictionary = view.sim.state["agents"][id]
		if a["state"] != "alive" or int(id) == not_id:
			continue
		if w in ["in", "out"] and String(a.get("where", "")) != w:
			continue
		if w.begins_with("b:"):
			# b:<def part>: a person in a structure of that type now (b:super_dome, b:apartment)
			var bb: Dictionary = view.sim.state["buildings"].get(int(a.get("bld", -1)), {})
			if bb.is_empty() or not String(bb["def"]).contains(w.substr(2)):
				continue
		if view.npc == null or not view.npc.agents.has(id):
			continue
		var l: float = sim_left(a)
		if l > bl:
			bl = l
			best = int(id)
	return best

func record(rig, delta: float) -> void:
	if not on:
		return
	var id: int = view.follow_id
	if id < 0 or view.npc == null or not view.npc.agents.has(id):
		return
	var rec: Dictionary = view.npc.agents[id]
	var sm = rec["sm"]
	var cam: Camera3D = rig.camera
	var bp: Vector3 = view.npc.body_pos(id)
	var head: Vector3 = bp + Vector3(0.0, 1.6, 0.0)
	var sp: Vector2 = cam.unproject_position(head) if not cam.is_position_behind(head) else Vector2(-1, -1)
	var f: Vector3 = -cam.global_transform.basis.z
	var key: String = String(sm.cur)
	if sm.loco:
		key = "run" if sm.run_latch else "walk"
	var a: Dictionary = view.sim.state["agents"].get(id, {})
	rows.append({"t": t, "dt": delta, "gr": float(view.game_rate), "bp": bp, "yaw": float(rec["yaw"]), "key": key,
		"mode": String(rec["mode"]), "v": float(rec.get("v", 0.0)), "cam": cam.global_position, "cyaw": atan2(-f.z, f.x),
		"cpitch": asin(clampf(f.y, -1.0, 1.0)), "scr": sp, "pull": float(rig.get("_sh_pull")), "eye": float(rig.get("_sh_eyeh")),
		"cut": cut_left > 0.0, "tick": int(view.sim.state["tick"]), "where": String(a.get("where", "")), "off": (rec.get("off", Vector3.ZERO) as Vector3).length(),
		"id": id, "left": sim_left(a) if not a.is_empty() else 0.0, "wb": float(sm.pose()["wb"]),
		"far": int(bool(rec.get("far", false))), "rspd": float(rec.get("speed", 0.0)), "smspd": float(sm.speed), "yld": int(bool(rec.get("yielding", false))), "vcap": float(rec.get("v_cap", -1.0)), "gu": float(rec.get("g_u", 0.0))})
	# A body that jumps (a fade move over 25 m, a new person) is a camera cut: skipped too.
	if _last_bp != null and (_last_bp as Vector3).distance_to(bp) > 2.0:
		cut_left = 1.0
		rows[-1]["cut"] = true
	_last_bp = bp
	t += delta
	cut_left -= delta
	# A person who stops (reached the goal) is swapped for a new walker: the frames after the cut are skipped.
	var moving: bool = float(rec.get("v", 0.0)) > 0.2
	_still_t = 0.0 if moving else _still_t + delta
	if want != "keep" and (_still_t > 1.5 or (not a.is_empty() and sim_left(a) < 0.5 and not moving)):
		var nid: int = pick_walker(want, id)
		if nid >= 0 and sim_left(view.sim.state["agents"][nid]) > 1.0 and view.follow_start(nid):
			hops += 1
			cut_left = 1.0
			_still_t = 0.0
	if t >= secs:
		on = false

static func _rms(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x) * float(x)
	return sqrt(s / a.size())

## Frame i is "walking steady" when every frame in i-6..i+6 walks (loco, over 0.5 m/s game speed), no cut.
func _steady(i: int, straight: bool) -> bool:
	if i < 6 or i + 6 >= rows.size():
		return false
	var y0: float = float(rows[i - 6]["yaw"])
	for j in range(i - 6, i + 7):
		var r: Dictionary = rows[j]
		if bool(r["cut"]) or not (String(r["key"]) in ["walk", "run"]) or float(r["v"]) < 0.5 or int(r["id"]) != int(rows[i]["id"]):
			return false
		if straight and absf(angle_difference(y0, float(r["yaw"]))) > deg_to_rad(4.0):
			return false
	return true

func report() -> Dictionary:
	var out := {"frames": rows.size(), "secs": snappedf(t, 0.1), "hops": hops, "fc_dbg": (view.fc_dbg as Array).slice(maxi(0, (view.fc_dbg as Array).size() - 400)), "cam_faded_total": int(view.npc.stats_slots.get("cam_faded", 0)) if view.npc != null else -1}
	if rows.size() < 20:
		return out
	var dts: Array = rows.map(func(r): return float(r["dt"]))
	var sdt := 0.0
	var mx := 0.0
	for d in dts:
		sdt += d
		mx = maxf(mx, d)
	out["fps"] = snappedf(rows.size() / maxf(sdt, 0.001), 0.1)
	out["max_dt_ms"] = snappedf(mx * 1000.0, 0.1)
	# Pops of the wall pull-in (all frames, no cut).
	var pops := 0
	var pulled := 0
	for i in range(1, rows.size()):
		if bool(rows[i]["cut"]) or int(rows[i]["id"]) != int(rows[i - 1]["id"]):
			continue
		if float(rows[i]["pull"]) < 0.98:
			pulled += 1
		if absf(float(rows[i]["pull"]) - float(rows[i - 1]["pull"])) > 0.08:
			pops += 1
	out["pops"] = pops
	out["pulled_frames"] = pulled
	# Locomotion state changes while the person is moving (sim position moving in the last 0.5 s).
	var sw := 0
	var move_t := 0.0
	for i in range(1, rows.size()):
		var r: Dictionary = rows[i]
		if bool(r["cut"]) or int(r["id"]) != int(rows[i - 1]["id"]):
			continue
		if float(r["v"]) > 0.3 or float(rows[i - 1]["v"]) > 0.3:
			move_t += float(r["dt"])
			if String(r["key"]) != String(rows[i - 1]["key"]):
				sw += 1
	out["move_s"] = snappedf(move_t, 0.1)
	out["clip_sw"] = sw
	out["clip_sw_min"] = snappedf(sw / maxf(move_t / 60.0, 0.001), 0.1)
	for mode in ["walk", "straight"]:
		var hj: Array = []
		var cj: Array = []
		var cy: Array = []
		var cpj: Array = []
		var sr: Array = []
		var yr: Array = []
		var hr: Array = []
		var cr: Array = []
		var n := 0
		for i in range(1, rows.size() - 1):
			if not _steady(i, mode == "straight"):
				continue
			n += 1
			var r0: Dictionary = rows[i - 1]
			var r1: Dictionary = rows[i]
			var r2: Dictionary = rows[i + 1]
			var s0: Vector2 = r0["scr"]
			var s1: Vector2 = r1["scr"]
			var s2: Vector2 = r2["scr"]
			# Second differences per 1/60 s: each step is scaled by (1/60) / its frame time, so a late
			# frame (16.7 -> 33 ms, the browser's own drops) is not counted as a camera jerk. At an even
			# 60 fps this is the plain second difference.
			var k1: float = H60 / maxf(float(r1["dt"]), 0.001)
			var k2: float = H60 / maxf(float(r2["dt"]), 0.001)
			if s0.x >= 0.0 and s1.x >= 0.0 and s2.x >= 0.0:
				hj.append(((s2 - s1) * k2 - (s1 - s0) * k1).length())
				hr.append((s2 - 2.0 * s1 + s0).length())
			cj.append((((r2["cam"] as Vector3) - (r1["cam"] as Vector3)) * k2 - ((r1["cam"] as Vector3) - (r0["cam"] as Vector3)) * k1).length() * 1000.0)
			cr.append(((r2["cam"] as Vector3) - 2.0 * (r1["cam"] as Vector3) + (r0["cam"] as Vector3)).length() * 1000.0)
			cy.append(rad_to_deg(angle_difference(float(r1["cyaw"]), float(r2["cyaw"])) * k2 - angle_difference(float(r0["cyaw"]), float(r1["cyaw"])) * k1))
			cpj.append(rad_to_deg((float(r2["cpitch"]) - float(r1["cpitch"])) * k2 - (float(r1["cpitch"]) - float(r0["cpitch"])) * k1))
			yr.append(rad_to_deg(angle_difference(float(r1["yaw"]), float(r2["yaw"])) * k2 - angle_difference(float(r0["yaw"]), float(r1["yaw"])) * k1))
			# frame speed against the mean over i-6..i+6 (view seconds)
			var v1: float = Vector2((r1["bp"] as Vector3).x - (r0["bp"] as Vector3).x, (r1["bp"] as Vector3).z - (r0["bp"] as Vector3).z).length() / maxf(float(r1["dt"]), 0.0001)
			var dsum := 0.0
			var tsum := 0.0
			for j in range(i - 5, i + 7):
				var ra: Dictionary = rows[j - 1]
				var rb: Dictionary = rows[j]
				dsum += Vector2((rb["bp"] as Vector3).x - (ra["bp"] as Vector3).x, (rb["bp"] as Vector3).z - (ra["bp"] as Vector3).z).length()
				tsum += float(rb["dt"])
			var vm: float = dsum / maxf(tsum, 0.0001)
			if vm > 0.2:
				sr.append((v1 - vm) / vm * 100.0)
		out[mode] = {"n": n, "head_jit_px": snappedf(_rms(hj), 0.001), "cam_jerk_mm": snappedf(_rms(cj), 0.001), "cam_yaw_deg": snappedf(_rms(cy), 0.0001),
			"cam_pitch_deg": snappedf(_rms(cpj), 0.0001), "speed_rip_pct": snappedf(_rms(sr), 0.01), "yaw_rip_deg": snappedf(_rms(yr), 0.0001),
			"head_jit_raw_px": snappedf(_rms(hr), 0.001), "cam_jerk_raw_mm": snappedf(_rms(cr), 0.001)}
	return out

## Raw samples as CSV (analysis outside the game).
func csv(max_rows: int = 3000) -> String:
	var lines: PackedStringArray = ["t,dt,gr,bx,by,bz,yaw,key,mode,v,cx,cy,cz,cyaw,cpitch,sx,sy,pull,eye,cut,tick,where,off,id,left,wb,far,rspd,smspd,yld,vcap,gu"]
	for i in mini(rows.size(), max_rows):
		var r: Dictionary = rows[i]
		var b: Vector3 = r["bp"]
		var c: Vector3 = r["cam"]
		var s: Vector2 = r["scr"]
		lines.append("%.4f,%.5f,%.4f,%.4f,%.4f,%.4f,%.5f,%s,%s,%.4f,%.4f,%.4f,%.4f,%.5f,%.5f,%.2f,%.2f,%.4f,%.3f,%d,%d,%s,%.3f,%d,%.2f,%.3f,%d,%.3f,%.3f,%d,%.2f,%.3f" % [
			float(r["t"]), float(r["dt"]), float(r["gr"]), b.x, b.y, b.z, float(r["yaw"]), r["key"], r["mode"], float(r["v"]),
			c.x, c.y, c.z, float(r["cyaw"]), float(r["cpitch"]), s.x, s.y, float(r["pull"]), float(r["eye"]), int(bool(r["cut"])), int(r["tick"]), r["where"], float(r["off"]), int(r["id"]), float(r["left"]), float(r["wb"]), int(r["far"]), float(r["rspd"]), float(r["smspd"]), int(r["yld"]), float(r["vcap"]), float(r["gu"])])
	return "\n".join(lines)
