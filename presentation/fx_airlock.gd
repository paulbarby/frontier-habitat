extends Node3D
## Airlock cycle (V3_1 §5.3, RENDER). The simulation gives `b.lock.cyc` = {phase, pt, dir,
## agents, t, total} and `b.lock.queue` = [{a, dir}]. This module shows it on ART-HAB's airlock
## kit (airlock_m, airlock_l, airlock_r28):
##   - the inner and outer doors (InnerDoorL/R, OuterDoorL/R and their *Top parts) slide open and
##     shut by phase; a door never closes on a body that is still in its opening;
##   - the chamber light goes amber, then red (outbound) or green (inbound); the three pressure
##     lamps (PressureLight_0..2) show the chamber pressure; the door status strips are green
##     (may open), amber (moving) or red (locked); the Beacon blinks amber while it cycles;
##   - vent mist while it pumps; door_slide when a door moves (the phase sounds are UI's);
##   - `goals`: where each rider and each queued body stands (fx_npc reads it): riders walk to
##     Anchor_Chamber_<i>; bodies that must change clothes go to Anchor_Suit_<i> first (the swap
##     plays there, never in the chamber, never outside); outbound queue in the suit room,
##     inbound queue on the porch, 0.8 m apart.

const Models = preload("res://presentation/models.gd")
const SLIDE := 0.75          # m: leaf travel (as the doorway kit)
const MOVE_T := 0.6          # s: a door opens or closes
const HOLD_D := 0.9          # m: a door does not close while a body is this near its opening
const QUEUE_GAP := 0.8
const LAMP_OFF := Color(0.28, 0.05, 0.04)
const DARK := Color(0.08, 0.05, 0.02)

var view
var sim
var locks := {}              # airlock id -> view state
var goals := {}              # agent id -> {pos, yaw, zone, bid, want_var}
var stats := {"cycling": 0, "riders": 0, "queued": 0, "ms": 0.0}
var _ids: Array = []
var _ids_n := -1
var _by_bld := {}
var _near_b := {}

func setup(v) -> void:
	view = v
	sim = v.sim

# ---------------------------------------------------------------- geometry
## Door lines and anchors of an airlock model, in world space (cached per building).
func _geo(bid: int, meta: Dictionary) -> Dictionary:
	var key: String = String(meta["tpl"].get("key", ""))
	if meta.has("lockgeo"):
		var lg0: Dictionary = meta["lockgeo"]
		if String(lg0["key"]) == key and (lg0["xf"] as Transform3D) == (meta["xf"] as Transform3D):
			return lg0
	var tpl: Dictionary = meta["tpl"]
	var s: float = float(tpl.get("scale", 1.0))
	var xf: Transform3D = meta["xf"]
	var xs := Transform3D(xf.basis * Basis.from_scale(Vector3(s, s, s)), xf.origin)
	var g := {"key": key, "xf": xf, "kit": false, "xs": xs, "s": s}
	var inner_x := INF
	var outer_x := INF
	for p in tpl["parts"]:
		var grp: String = p["group"]
		if grp != "InnerDoorL" and grp != "OuterDoorL":
			continue
		var ab: AABB = (p.get("xf", Transform3D.IDENTITY) as Transform3D) * (p["mesh"] as Mesh).get_aabb()
		var cx: float = ab.position.x + ab.size.x * 0.5
		if grp == "InnerDoorL":
			inner_x = cx
		else:
			outer_x = cx
	if inner_x == INF or outer_x == INF:
		meta["lockgeo"] = g
		return g
	g["kit"] = true
	g["inner_x"] = inner_x
	g["outer_x"] = outer_x
	var fy: float = xf.origin.y
	g["door_in"] = xs * Vector3(inner_x, 0.14, 0.0)
	g["door_out"] = xs * Vector3(outer_x, 0.14, 0.0)
	g["centre"] = xs * Vector3((inner_x + outer_x) * 0.5, 0.14, 0.0)
	var fwd: Vector3 = xf.basis.x.normalized()
	g["fwd"] = fwd
	for kind in ["Chamber", "Suit", "Stand", "Porch"]:
		var lst: Array = []
		var i := 0
		while meta["anchors"].has("%s_%d" % [kind, i]):
			var t: Transform3D = meta["anchors"]["%s_%d" % [kind, i]]
			var q: Vector3 = t.origin
			if kind == "Porch":
				q.y = view.h(q.x, q.z)
			lst.append({"pos": q, "yaw": _yaw_of(t.basis.x)})
			i += 1
		g[kind] = lst
	if (g["Chamber"] as Array).is_empty():
		g["Chamber"] = [{"pos": g["centre"], "yaw": _yaw_of(fwd)}]
	if (g["Suit"] as Array).is_empty():
		g["Suit"] = [{"pos": xs * Vector3(inner_x - 0.9, 0.14, 0.0), "yaw": _yaw_of(-fwd)}]
	if (g["Stand"] as Array).is_empty():
		g["Stand"] = g["Suit"]
	if (g["Porch"] as Array).is_empty():
		var pp: Vector3 = xs * Vector3(outer_x + 1.2, 0.0, 0.0)
		pp.y = view.h(pp.x, pp.z)
		g["Porch"] = [{"pos": pp, "yaw": _yaw_of(-fwd)}]
	g["fy"] = fy
	meta["lockgeo"] = g
	return g

## The yaw fx_npc uses for a body facing world direction d (body forward = +X).
static func _yaw_of(d: Vector3) -> float:
	return atan2(-d.z, d.x)

## Model-space X of a world point (the axis from the suit room through the chamber to the porch).
func _local_x(g: Dictionary, p: Vector3) -> float:
	return ((g["xs"] as Transform3D).affine_inverse() * p).x

func _airlock_ids() -> Array:
	if view.bmeta.size() == _ids_n:
		return _ids
	_ids_n = view.bmeta.size()
	_ids = []
	var blds: Dictionary = sim.state["buildings"]
	for bid in view.bmeta:
		if blds.has(bid) and String(blds[bid]["def"]) == "airlock":
			_ids.append(int(bid))
	return _ids

# ---------------------------------------------------------------- per frame
func sync(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	goals.clear()
	# Doors and pressure run on game time (the cycle is in sim seconds).
	var gdt: float = delta * clampf(float(view.game_rate), 0.0, 50.0)
	var blds: Dictionary = sim.state["buildings"]
	var npc = view.npc
	var cyc_n := 0
	var rid_n := 0
	var q_n := 0
	var ids: Array = _airlock_ids()
	# Drawn bodies near each airlock ([id, drawn pos, walker pos]), found once per frame.
	_near_b = {}
	var circles: Array = []
	for lb in ids:
		var bl: Dictionary = blds.get(lb, {})
		if not bl.is_empty():
			circles.append([lb, bl["pos"], float(bl["radius"]) + 2.0])
	if not circles.is_empty():
		for id in npc.agents:
			var rec0: Dictionary = npc.agents[id]
			var wp0: Vector3 = rec0["pos"]
			for cc in circles:
				var c2: Vector2 = cc[1]
				if absf(wp0.x - c2.x) < cc[2] and absf(wp0.z - c2.y) < cc[2]:
					if not _near_b.has(cc[0]):
						_near_b[cc[0]] = []
					(_near_b[cc[0]] as Array).append([id, npc._dp(rec0), wp0])
					break
	# Indoor bodies by the airlock they are in (the simulation's `bld`).
	_by_bld = {}
	# (by position: the simulation walks a colonist that crosses an airlock through its centre)
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		if String(ag["where"]) != "in":
			continue
		var ap: Vector2 = ag["pos"]
		for lb in ids:
			var bb0: Dictionary = blds.get(lb, {})
			if not bb0.is_empty() and ap.distance_to(bb0["pos"]) < float(bb0["radius"]):
				if not _by_bld.has(lb):
					_by_bld[lb] = []
				(_by_bld[lb] as Array).append(int(aid))
				break
	for bid in ids:
		if not blds.has(bid) or not view.bmeta.has(bid):
			continue
		var meta: Dictionary = view.bmeta[bid]
		if meta["mode"] != "inst" or int(meta["h"]) < 0:
			continue
		var g: Dictionary = _geo(bid, meta)
		if not bool(g["kit"]):
			continue
		var b: Dictionary = blds[bid]
		var h: int = meta["h"]
		if not locks.has(bid) or int(locks[bid]["h"]) != h:
			locks[bid] = {"h": h, "inner": 0.0, "outer": 0.0, "inner_w": false, "outer_w": false, "p": 1.0, "phase": "", "dir": "",
				"snd": -1, "fx": null, "col": {}, "after": {}, "blink": 0.0}
		var st: Dictionary = locks[bid]
		var lock = b.get("lock", {})
		var cyc: Dictionary = (lock.get("cyc", {}) if lock is Dictionary else {}) as Dictionary
		var phase: String = String(cyc.get("phase", ""))
		var dir: String = String(cyc.get("dir", st["dir"]))
		var riders: Array = cyc.get("agents", [])
		var total: float = maxf(0.1, float(cyc.get("total", 10.0)))
		var pt: float = float(cyc.get("pt", 0.0))
		var shares: Array = sim.bal.get("airlock_phases", [0.15, 0.1, 0.5, 0.1, 0.15])
		var pump_len: float = maxf(0.1, total * float(shares[2]))
		if phase != "":
			cyc_n += 1
		# ---- riders
		var stands: Array = g["Stand"]
		var porch: Array = g["Porch"]
		var settled := true
		var chambers: Array = g["Chamber"]
		var suits: Array = g["Suit"]
		# Critic round 14: every waiting or changing body gets its own place (0.6 m apart):
		# suit anchors, stand anchors and suit-side aisle points in the suit room; the porch
		# anchors and then 0.8 m steps outward on the porch.
		var taken: Array = []
		var room_pts: Array = _room_places(g, view.bmeta[bid])
		var porch_pts: Array = []
		var q_pts: Array = []
		for m in 6:
			for pq0 in porch:
				var pp0: Vector3 = (pq0["pos"] as Vector3) + (g["fwd"] as Vector3) * (QUEUE_GAP * float(m))
				pp0.y = view.h(pp0.x, pp0.z)
				porch_pts.append({"pos": pp0, "yaw": pq0["yaw"], "kind": "porch"})
		var pick := func(pts: Array, start: int, suit_only: bool) -> Dictionary:
			for i in pts.size():
				var e: Dictionary = pts[(start + i) % pts.size()]
				if suit_only and String(e.get("kind", "")) != "suit":
					continue
				var free := true
				for tq in taken:
					if (tq as Vector3).distance_to(e["pos"]) < 0.6:
						free = false
						break
				if free:
					taken.append(e["pos"])
					return e
			return {}
		for k in riders.size():
			var aid: int = int(riders[k])
			rid_n += 1
			var rec = npc.agents.get(aid)
			var cg: Dictionary = chambers[k % chambers.size()]
			var cpos: Vector3 = cg["pos"] - (g["fwd"] as Vector3) * (0.55 * float(k / chambers.size()))
			var goal := {"pos": cpos, "yaw": cg["yaw"], "zone": "chamber", "bid": bid, "want_var": "suit"}
			# Wait at the door until it is open (its pressure side first; V3_1 §5.3).
			var gate_open: bool = float(st["inner"]) > 0.8 if dir == "out" else float(st["outer"]) > 0.8
			var in_cham: bool = rec != null and _is_chamber(g, rec["pos"])
			if dir == "out":
				if phase == "exit" and (float(st["outer"]) > 0.8 or not in_cham):
					var dp: Vector2 = sim.nav.door_pos(b)
					goal = {"pos": Vector3(dp.x, view.h(dp.x, dp.y), dp.y), "zone": "porch", "bid": bid, "want_var": "suit"}
				elif rec != null and String(rec["var"]) != "suit" and not in_cham:
					var sg: Dictionary = pick.call(room_pts, k, true)
					if sg.is_empty():
						sg = suits[k % suits.size()]
					goal = {"pos": sg["pos"], "yaw": sg["yaw"], "zone": "suit", "bid": bid, "want_var": "suit"}
			else:
				if (phase == "open" or phase == "exit") and (float(st["inner"]) > 0.8 or not in_cham):
					var sg2: Dictionary = pick.call(room_pts, k, true)
					if sg2.is_empty():
						sg2 = pick.call(room_pts, k, false)
					if not sg2.is_empty():
						goal = {"pos": sg2["pos"], "yaw": sg2["yaw"], "zone": "suit" if String(sg2["kind"]) == "suit" else "room", "bid": bid, "want_var": "in"}
					(st["after"] as Dictionary)[aid] = k
			if goal["zone"] == "chamber" and rec != null and not in_cham and not gate_open and phase == "enter":
				var sw: Dictionary = pick.call(room_pts, k, true) if String(rec["var"]) != "suit" and dir == "out" else {}
				if sw.is_empty() and String(rec["var"]) != "suit" and dir == "out":
					sw = suits[k % suits.size()]
				if not sw.is_empty():
					goal = {"pos": sw["pos"], "yaw": sw["yaw"], "zone": "suit", "bid": bid, "want_var": "suit"}
				else:
					var wq: Dictionary = pick.call(room_pts if dir == "out" else porch_pts, k, false)
					if not wq.is_empty():
						goal = {"pos": wq["pos"], "yaw": wq["yaw"], "zone": "wait", "bid": bid, "want_var": "suit"}
			# Seal or pump with this rider not yet in the chamber (a late walker): it fades into its
			# chamber place (0.3 s, V3_1 §4.3) so the door can shut on time.
			if rec != null and (phase == "seal" or phase == "pump") and not _is_chamber(g, rec["pos"]) and not rec.has("fade_to"):
				rec["fade_to"] = cpos
				rec["fade_var"] = "suit"
				stats["faded_in"] = int(stats.get("faded_in", 0)) + 1
			if phase == "seal" or phase == "pump":
				goal = {"pos": cpos, "yaw": cg["yaw"], "zone": "chamber", "bid": bid, "want_var": "suit"}
			goals[aid] = goal
			if rec != null and phase in ["enter", "seal", "pump"] and (goal["zone"] != "chamber" or (rec["pos"] as Vector3).distance_to(cpos) > 0.35):
				settled = false
		# ---- inbound riders after the cycle: the simulation puts them at the airlock centre
		# (chamber side of the inner door); they stay in the suit room until they walk on.
		for aid in (st["after"] as Dictionary).keys():
			var a = sim.state["agents"].get(aid)
			if a == null or String(a["where"]) != "in" or riders.has(aid):
				if a == null or String(a["where"]) == "out":
					(st["after"] as Dictionary).erase(aid)
				continue
			var sp: Vector2 = a["pos"]
			var lx: float = _local_x(g, Vector3(sp.x, g["fy"], sp.y))
			if (sp - (b["pos"] as Vector2)).length() > float(b["radius"]) or lx < float(g["inner_x"]) - 0.1:
				(st["after"] as Dictionary).erase(aid)
				continue
			var sg3: Dictionary = pick.call(room_pts, int(st["after"][aid]), true)
			if sg3.is_empty():
				sg3 = pick.call(room_pts, int(st["after"][aid]), false)
			if not sg3.is_empty():
				goals[aid] = {"pos": sg3["pos"], "yaw": sg3["yaw"], "zone": "suit" if String(sg3["kind"]) == "suit" else "room", "bid": bid, "want_var": "in"}
		# ---- other indoor bodies the simulation sends to this airlock: its centre is on the
		# chamber side of the inner door, so they wait in the suit room instead.
		for aid in _by_bld.get(bid, []):
			if goals.has(aid) or riders.has(aid):
				continue
			var a2 = sim.state["agents"].get(aid)
			if a2 == null or String(a2["where"]) != "in":
				continue
			var sp2: Vector2 = a2["pos"]
			if (sp2 - (b["pos"] as Vector2)).length() > float(b["radius"]):
				continue
			if _local_x(g, Vector3(sp2.x, g["fy"], sp2.y)) < float(g["inner_x"]) - 0.1:
				continue
			# (shared stand places, as before round 14: these bodies only pass through)
			var stn: Array = g["Stand"]
			var s6: Dictionary = stn[posmod(int(aid), stn.size())]
			if not s6.is_empty():
				goals[aid] = {"pos": s6["pos"], "yaw": s6["yaw"], "zone": "room", "bid": bid}
		# ---- queue: outbound in the suit room (suit up first), inbound on the porch.
		var queue: Array = (lock.get("queue", []) if lock is Dictionary else []) as Array
		var n_out := 0
		var n_in := 0
		for e in queue:
			var aid2: int = int(e.get("a", -1))
			var rec2 = npc.agents.get(aid2)
			if rec2 == null or goals.has(aid2):
				continue
			var near: bool = (rec2["pos"] as Vector3).distance_to(g["centre"]) < float(b["radius"]) + 6.0
			if not near:
				continue
			if String(e.get("dir", "")) == "out":
				var s4: Dictionary = pick.call(room_pts, n_out, true) if String(rec2["var"]) != "suit" else {}
				if not s4.is_empty():
					goals[aid2] = {"pos": s4["pos"], "yaw": s4["yaw"], "zone": "suit", "bid": bid, "want_var": "suit"}
				else:
					var s5: Dictionary = pick.call(room_pts, n_out, false)
					if s5.is_empty():
						continue
					goals[aid2] = {"pos": s5["pos"], "yaw": s5["yaw"], "zone": "queue", "bid": bid, "want_var": "suit"}
				n_out += 1
			else:
				var pq: Dictionary = pick.call(porch_pts, 0, false)
				if pq.is_empty():
					continue
				goals[aid2] = {"pos": pq["pos"], "yaw": pq["yaw"], "zone": "porch", "bid": bid, "want_var": "suit"}
				n_in += 1
			q_n += 1
		# ---- pressure (1 = base pressure in the chamber). It changes only with both doors shut.
		var pump_prog: float = clampf(1.0 - pt / pump_len, 0.0, 1.0) if phase == "pump" else (1.0 if phase in ["open", "exit"] else 0.0)
		var p: float = st["p"]
		var bodies: Array = _near_b.get(bid, [])
		var stray: bool = _stray_in_chamber(g, riders, bodies)
		var sealed: bool = float(st["inner"]) < 0.02 and float(st["outer"]) < 0.02 and not stray
		if sealed and phase != "":
			var p_entry: float = 1.0 if dir == "out" else 0.0
			var p_exit: float = 1.0 - p_entry
			var tgt_p: float = p_entry
			var rate: float = 1.0 / 0.3
			if phase == "pump" and settled:
				tgt_p = 1.0 - pump_prog if dir == "out" else pump_prog
				rate = 2.5 / pump_len
				if pump_prog > 0.99:
					rate = 1.0 / 0.8
			elif phase in ["open", "exit"]:
				tgt_p = p_exit
			p = move_toward(p, tgt_p, gdt * rate)
		st["p"] = p
		# Vent mist only while the pressure really changes (both doors shut).
		if st["fx"] != null and is_instance_valid(st["fx"]):
			(st["fx"] as CPUParticles3D).emitting = phase == "pump" and sealed and settled
		# ---- doors: the inner door opens only at base pressure, the outer only at vacuum, and
		# never both at once.
		var in_w := false
		var out_w := false
		match phase:
			"enter":
				in_w = dir == "out"
				out_w = dir == "in"
			"seal", "pump":
				# Critic round 14: the doors follow the simulation phase: shut during seal, shut
				# before pump. A rider not yet in the chamber is faded in (below).
				pass
			"open", "exit":
				in_w = dir == "in"
				out_w = dir == "out"
		# Idle: a body left in the chamber (a late rider) leaves by the door on the side whose
		# pressure matches.
		# Any phase: a body in the chamber that is not riding (a late rider of the last cycle)
		# holds the door of the matching pressure open until it is out.
		var locked: bool = phase == "seal" or phase == "pump"
		if locked:
			for e0 in bodies:
				if riders.has(e0[0]) or riders.has(int(e0[0])):
					continue
				var r0 = npc.agents.get(e0[0])
				if r0 == null or r0.has("fade_to"):
					continue
				var w0: Vector3 = e0[2]
				var l0: Vector3 = (g["xs"] as Transform3D).affine_inverse() * w0
				var in_open: bool = absf(l0.z) < 0.9 and (absf(l0.x - float(g["inner_x"])) < 0.45 or absf(l0.x - float(g["outer_x"])) < 0.45)
				if _is_chamber(g, w0) or in_open:
					var outside_side: bool = l0.x > float(g["outer_x"]) - 0.1
					var dest: Dictionary = pick.call(porch_pts if outside_side else room_pts, int(e0[0]), false)
					if not dest.is_empty():
						r0["fade_to"] = dest["pos"]
						stats["faded_out"] = int(stats.get("faded_out", 0)) + 1
		if stray and not locked:
			in_w = in_w or p > 0.97
			out_w = out_w or p < 0.03
		in_w = in_w and p > 0.97 and float(st["outer"]) < 0.02
		out_w = out_w and p < 0.03 and float(st["inner"]) < 0.02
		# Never close on a body in the opening (outside seal and pump: then the riders are in).
		if not locked and not in_w and float(st["inner"]) > 0.3 and _in_opening(g, bodies, float(g["inner_x"])):
			in_w = true
		if not locked and not out_w and float(st["outer"]) > 0.3 and _in_opening(g, bodies, float(g["outer_x"])):
			out_w = true
		var inst = view.inst
		for side in [["inner", "Inner", in_w, "door_in"], ["outer", "Outer", out_w, "door_out"]]:
			var k2: String = side[0]
			var want: bool = side[2]
			if want != bool(st[k2 + "_w"]):
				st[k2 + "_w"] = want
				view.world_sound("door_slide", g[side[3]])
			var o: float = st[k2]
			var tgt: float = 1.0 if want else 0.0
			if o != tgt:
				o = move_toward(o, tgt, gdt / MOVE_T)
				st[k2] = o
				var e2: float = o * o * (3.0 - 2.0 * o) * SLIDE
				var pre: String = side[1]
				for gg in [pre + "DoorL", pre + "DoorLTop"]:
					inst.set_extra(h, gg, Transform3D(Basis(), Vector3(0, 0, e2)))
				for gg in [pre + "DoorR", pre + "DoorRTop"]:
					inst.set_extra(h, gg, Transform3D(Basis(), Vector3(0, 0, -e2)))
		# ---- phase changes: sounds and vent mist
		if phase != String(st["phase"]):
			_on_phase(bid, st, g, String(st["phase"]), phase, dir)
			st["phase"] = phase
			st["dir"] = dir
		# ---- lights
		var breach: bool = bool(b.get("breach", false))
		var cham: Color
		if phase == "":
			cham = Models.STATUS_GREEN if p > 0.5 else Models.STATUS_RED
		elif phase in ["enter", "seal"]:
			cham = Models.STATUS_AMBER
		elif phase == "pump":
			cham = Models.STATUS_AMBER.lerp(Models.STATUS_RED, smoothstep(0.3, 0.9, pump_prog)) if dir == "out" \
				else Models.STATUS_RED.lerp(Models.STATUS_AMBER, smoothstep(0.0, 0.5, pump_prog)).lerp(Models.STATUS_GREEN, smoothstep(0.5, 0.95, pump_prog))
		else:
			cham = Models.STATUS_RED if dir == "out" else Models.STATUS_GREEN
		_col(st, h, "ChamberLight", cham)
		var inner_c: Color = Models.STATUS_RED if breach or p < 0.97 else Models.STATUS_GREEN
		if float(st["inner"]) > 0.001 and float(st["inner"]) < 0.999:
			inner_c = Models.STATUS_AMBER
		var outer_c: Color = Models.STATUS_GREEN if p < 0.03 and not breach else Models.STATUS_RED
		if phase == "" and not breach:
			outer_c = Models.STATUS_AMBER if p > 0.03 else Models.STATUS_GREEN
		if float(st["outer"]) > 0.001 and float(st["outer"]) < 0.999:
			outer_c = Models.STATUS_AMBER
		for gg in ["InnerStatus", "InnerLights"]:
			_col(st, h, gg, inner_c)
		for gg in ["OuterStatus", "OuterLights"]:
			_col(st, h, gg, outer_c)
		for i in 3:
			_col(st, h, "PressureLight_%d" % i, Models.STATUS_GREEN if p > (float(i) + 0.5) / 3.0 else LAMP_OFF)
		var blink: bool = phase != "" and fmod(float(view._time) * 1.6, 1.0) < 0.55
		_col(st, h, "Beacon", Models.STATUS_AMBER if blink else DARK)
	stats["cycling"] = cyc_n
	stats["riders"] = rid_n
	stats["queued"] = q_n
	stats["ms"] = snappedf(lerpf(float(stats["ms"]), (Time.get_ticks_usec() - t0) / 1000.0, 0.1), 0.001)

func _col(st: Dictionary, h: int, group: String, c: Color) -> void:
	var cc: Dictionary = st["col"]
	if cc.get(group) == c:
		return
	cc[group] = c
	view.inst.set_group_custom(h, group, Color(c.r, c.g, c.b, 1.0))

## A body within 0.45 m of a door plane, inside its opening (bodies = [id, drawn, walker]).
func _in_opening(g: Dictionary, bodies: Array, dx: float) -> bool:
	var inv: Transform3D = (g["xs"] as Transform3D).affine_inverse()
	for e in bodies:
		var l: Vector3 = inv * (e[1] as Vector3)
		if absf(l.x - dx) < 0.45 and absf(l.z) < 0.9:
			return true
	return false

## Standing places of the suit room: Suit anchors (kind suit), Stand anchors, then suit-side
## aisle points (cached per building).
func _room_places(g: Dictionary, meta: Dictionary) -> Array:
	if g.has("room_pts"):
		return g["room_pts"]
	var out: Array = []
	for e in g["Suit"]:
		out.append({"pos": e["pos"], "yaw": e["yaw"], "kind": "suit"})
	for e in g["Stand"]:
		out.append({"pos": e["pos"], "yaw": e["yaw"], "kind": "stand"})
	var fy: float = (meta["xf"] as Transform3D).origin.y + 0.14 * float(g["s"])
	for an in meta["anchors"]:
		if String(an).begins_with("Aisle_"):
			var ap: Vector3 = (meta["anchors"][an] as Transform3D).origin
			ap.y = fy
			if _local_x(g, ap) < float(g["inner_x"]) - 0.4:
				out.append({"pos": ap, "yaw": _yaw_of(g["fwd"]), "kind": "aisle"})
	g["room_pts"] = out
	return out

func _stray_in_chamber(g: Dictionary, riders: Array, bodies: Array) -> bool:
	for e in bodies:
		if riders.has(e[0]) or riders.has(int(e[0])):
			continue
		if _is_chamber(g, e[2]):
			return true
	return false

func _is_chamber(g: Dictionary, v: Vector3) -> bool:
	var l: Vector3 = (g["xs"] as Transform3D).affine_inverse() * v
	return l.x > float(g["inner_x"]) + 0.1 and l.x < float(g["outer_x"]) - 0.1 and absf(l.z) < 1.3

## Vent mist at a phase change. The phase sounds (airlock_seal, airlock_pump, airlock_vent)
## are UI's (ui/hud/world_sounds.gd reads lock.cyc); RENDER plays only door_slide.
func _on_phase(bid: int, st: Dictionary, g: Dictionary, from: String, to: String, dir: String) -> void:
	_mist(bid, st, g, to == "pump", dir)

func _mist(bid: int, st: Dictionary, g: Dictionary, on: bool, dir: String) -> void:
	var pa = st["fx"]
	if not on:
		if pa != null and is_instance_valid(pa):
			(pa as CPUParticles3D).emitting = false
		return
	var cam: Camera3D = view.get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(g["centre"]) > 120.0:
		return
	if pa == null or not is_instance_valid(pa):
		pa = _make_mist()
		add_child(pa)
		st["fx"] = pa
	var p2: CPUParticles3D = pa
	var xs: Transform3D = g["xs"]
	var s: float = g["s"]
	if dir == "out":
		# The air leaves through the vent above the outer door: a white jet outward.
		p2.global_transform = Transform3D(xs.basis.orthonormalized(), xs * Vector3(float(g["outer_x"]) + 0.3, 2.0, 0.0))
		p2.direction = Vector3(1, 0.35, 0)
		p2.spread = 22.0
		p2.initial_velocity_min = 1.6 * s
		p2.initial_velocity_max = 2.6 * s
		p2.emission_box_extents = Vector3(0.05, 0.08, 0.5) * s
		p2.gravity = Vector3(0, 0.25, 0)
	else:
		# Air comes in through the floor vents: mist rising in the chamber.
		p2.global_transform = Transform3D(xs.basis.orthonormalized(), xs * Vector3((float(g["inner_x"]) + float(g["outer_x"])) * 0.5, 0.3, 0.0))
		p2.direction = Vector3(0, 1, 0)
		p2.spread = 35.0
		p2.initial_velocity_min = 0.4 * s
		p2.initial_velocity_max = 0.9 * s
		p2.emission_box_extents = Vector3((float(g["outer_x"]) - float(g["inner_x"])) * 0.4, 0.05, 0.9) * s
		p2.gravity = Vector3(0, 0.05, 0)
	p2.restart()
	p2.emitting = true

static var _mist_mesh: QuadMesh = null
static var _mist_ramp: Gradient = null
static var _mist_curve: Curve = null
func _make_mist() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	if _mist_mesh != null:
		p.amount = 26
		p.lifetime = 1.3
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		p.mesh = _mist_mesh
		p.color_ramp = _mist_ramp
		p.scale_amount_curve = _mist_curve
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.emitting = false
		return p
	p.amount = 26
	p.lifetime = 1.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.55)
	m.disable_receive_shadows = true
	# A soft round puff (a plain quad reads as a square).
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 1))
	gg.set_color(1, Color(1, 1, 1, 0))
	gg.add_point(0.45, Color(1, 1, 1, 0.55))
	gt.gradient = gg
	m.albedo_texture = gt
	q.material = m
	p.mesh = q
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.0))
	gr.set_color(1, Color(1, 1, 1, 0.0))
	gr.add_point(0.15, Color(1, 1, 1, 0.55))
	gr.add_point(0.6, Color(1, 1, 1, 0.3))
	p.color_ramp = gr
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.4))
	cv.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = cv
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	_mist_mesh = q
	_mist_ramp = gr
	_mist_curve = cv
	return p

# ---------------------------------------------------------------- routes (fx_npc_path)
const ORD := {"I": -1, "S": 0, "C": 1, "P": 2, "X": 2}

## Zone of p for airlock g: S suit room, C chamber, P porch side inside the wall, or, outside
## the building, I (indoors elsewhere) / X (outdoors).
func _zone(g: Dictionary, b: Dictionary, p: Vector3, inside: bool, pl) -> String:
	if Vector2(p.x, p.z).distance_to(b["pos"]) < float(b["radius"]) - 0.05:
		var l: Vector3 = (g["xs"] as Transform3D).affine_inverse() * p
		if l.x > float(g["outer_x"]):
			return "P"
		# The walkway beside the chamber (|z| > 1.3) belongs to the suit room.
		if l.x < float(g["inner_x"]) or absf(l.z) > 1.3:
			return "S"
		return "C"
	return "X" if String(pl.region_of(p, inside)["k"]) == "out" else "I"

## The polyline from a to b when it passes an airlock door or ends in a chamber; null
## otherwise (the planner's own route). The door leaves are wall in the walk grid, so the
## room planner never walks through a door; this route goes through the opening centre.
func route(a: Vector3, b: Vector3, inside: bool, pl):
	var blds: Dictionary = sim.state["buildings"]
	var found := -1
	for bid in _airlock_ids():
		if not blds.has(bid) or not view.bmeta.has(bid):
			continue
		var bb: Dictionary = blds[bid]
		var rr: float = float(bb["radius"]) + 0.5
		if Vector2(a.x, a.z).distance_to(bb["pos"]) < rr or Vector2(b.x, b.z).distance_to(bb["pos"]) < rr:
			found = bid
			break
	if found < 0:
		return null
	var meta: Dictionary = view.bmeta[found]
	if meta["mode"] != "inst":
		return null
	var g: Dictionary = _geo(found, meta)
	if not bool(g["kit"]):
		return null
	var bl: Dictionary = blds[found]
	var za: String = _zone(g, bl, a, inside, pl)
	var zb: String = _zone(g, bl, b, inside, pl)
	var oa: int = ORD[za]
	var ob: int = ORD[zb]
	# Nothing to do with the chamber: the normal planner.
	if (oa <= 0 and ob <= 0) or (oa == 2 and ob == 2):
		return null
	var xs: Transform3D = g["xs"]
	var ix: float = g["inner_x"]
	var ox: float = g["outer_x"]
	var i_s: Vector3 = xs * Vector3(ix - 0.5, 0.14, 0.0)
	var i_c: Vector3 = xs * Vector3(ix + 0.4, 0.14, 0.0)
	var o_c: Vector3 = xs * Vector3(ox - 0.4, 0.14, 0.0)
	var o_o: Vector3 = xs * Vector3(ox + 0.9, 0.0, 0.0)
	o_o.y = view.h(o_o.x, o_o.z)
	var mid: Array = []
	if oa < ob:
		if oa <= 0 and ob >= 1:
			mid.append_array([i_s, i_c])
		if oa <= 1 and ob >= 2:
			mid.append_array([o_c, o_o])
	elif oa > ob:
		if oa >= 2 and ob <= 1:
			mid.append_array([o_o, o_c])
		if oa >= 1 and ob <= 0:
			mid.append_array([i_c, i_s])
	var out: Array = []
	# From a to the first door point.
	if not mid.is_empty():
		var first: Vector3 = mid[0]
		match za:
			"X":
				out.append_array(pl.out_path(a, first))
			"I", "S":
				out.append_array(pl._plan(a, first, true))
			_:
				out.append(first)
		for k in range(1, mid.size()):
			out.append(mid[k])
	var last: Vector3 = mid[-1] if not mid.is_empty() else a
	match zb:
		"X":
			out.append_array(pl.out_path(last, b))
		"I", "S":
			out.append_array(pl._plan(last, b, true))
		_:
			out.append(b)
	# Drop repeats.
	var clean: Array = []
	for q in out:
		if clean.is_empty() or (clean[-1] as Vector3).distance_to(q) > 0.05:
			clean.append(q)
	return clean

## Old-save airlocks (R 2.8): corridors at model angles 83, 259.5 and 270 deg open beside the
## chamber, onto the narrow walkway round the inner door housing (ART-HAB, 2026-09-25: no
## furniture change frees them). A path from such a doorway to the suit room (or back) goes
## round the housing by a corner point just past it, never through the chamber.
func walkway_route(rid: int, a: Vector3, b: Vector3, pl):
	if not _airlock_ids().has(rid) or not view.bmeta.has(rid):
		return null
	var g: Dictionary = _geo(rid, view.bmeta[rid])
	if not bool(g["kit"]):
		return null
	var wa: float = _walkway_side(g, a)
	var wb: float = _walkway_side(g, b)
	if wa == 0.0 and wb == 0.0:
		return null
	if wa != 0.0 and wb != 0.0:
		return [b]
	var sgn: float = wa if wa != 0.0 else wb
	var k: Vector3 = (g["xs"] as Transform3D) * Vector3(float(g["inner_x"]) - 0.55, 0.14, sgn * 1.6)
	k.y = a.y
	if wa != 0.0:
		return [k] + pl.room_path(rid, k, b)
	return pl.room_path(rid, a, k) + [b]

## +1 / -1: p is on the walkway beside the chamber (that side of it); 0: elsewhere.
func _walkway_side(g: Dictionary, p: Vector3) -> float:
	var l: Vector3 = (g["xs"] as Transform3D).affine_inverse() * p
	if l.x > float(g["inner_x"]) - 0.2 and l.x < float(g["outer_x"]) and absf(l.z) > 1.3:
		return signf(l.z)
	return 0.0

# ---------------------------------------------------------------- queries (fx_npc)
## True when p (drawn) is inside an airlock building (within its wall).
func inside_lock(p: Vector3) -> bool:
	var blds: Dictionary = sim.state["buildings"]
	for bid in _airlock_ids():
		if not blds.has(bid):
			continue
		var b: Dictionary = blds[bid]
		if Vector2(p.x, p.z).distance_to(b["pos"]) < float(b["radius"]) - 0.15:
			return true
	return false

## Debug / tests.
func info(bid: int) -> Dictionary:
	if not locks.has(bid):
		return {}
	var st: Dictionary = locks[bid]
	return {"inner": snappedf(float(st["inner"]), 0.01), "outer": snappedf(float(st["outer"]), 0.01), "p": snappedf(float(st["p"]), 0.01),
		"phase": st["phase"], "dir": st["dir"], "cols": (st["col"] as Dictionary).keys().size()}
