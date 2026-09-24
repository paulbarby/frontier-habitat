extends SceneTree
## RENDER consistency check of the astronaut animation set (V3_DESIGN §3.5).
##   node tools/godot.mjs script res://tools/npc_check.gd            the real GLBs
##   node tools/godot.mjs script res://tools/npc_check.gd --fixture  the procedural test rig
## Loads both GLBs through the game's own baker (presentation/fx_npc.gd), finds every clip,
## then drives the game's own pose state machine (presentation/fx_npc_pose.gd) through every
## pose-to-pose transition, every loop-to-loop change inside each pose, locomotion (idle ->
## walk -> run -> walk -> idle), the carry layer on and off, and the one-shot clips. Every
## 30 fps frame is compared with the one before, as the GPU draws it (fx_npc.pose_globals).
## Rule (§3.5 as changed by the orchestrator, 2026-09-24): the per-frame limit catches POPS.
## A frame FAILS if its largest bone step is over 15 degrees AND over 1.25 x the largest
## in-clip step of the clips it shows (at their playback rate). Speed-matched locomotion has
## no fixed limit. The character root must never move more than 0.1 m in one frame.
## Writes art/npc/godot_check.json (the fixture run writes build/web_render/godot_check_fixture.json).

const Npc = preload("res://presentation/fx_npc.gd")
const Pose = preload("res://presentation/fx_npc_pose.gd")
const MAX_DEG := 15.0
const MAX_ROOT := 0.1
const DT := 1.0 / 30.0

var lib: Dictionary
var worst := {}
var clip_step := {}     # clip -> largest in-clip bone step per frame at 1x (degrees)

func _init() -> void:
	var fixture: bool = "--fixture" in OS.get_cmdline_user_args()
	var report := {"generated": Time.get_datetime_string_from_system(true), "source": "fixture" if fixture else "glb",
		"limits": {"bone_deg_per_frame": MAX_DEG, "root_m_per_frame": MAX_ROOT, "fps": 30}, "variants": {}, "tests": [], "failures": []}
	var libs := {}
	for v in ["suit", "in"]:
		var l: Dictionary = Npc.load_lib(v, fixture)
		var vr := {"file": Npc.FILES[v], "ok": bool(l.get("ok", false)), "status": l.get("status", "")}
		if bool(l.get("ok", false)):
			vr["bones"] = l["names"]
			vr["clips_found"] = (l["clips"] as Dictionary).keys()
			vr["clips_missing"] = l["missing"]
			vr["triangles"] = l["tris"]
			vr["head_variants"] = l["heads"]
			vr["bake_ms"] = snappedf(float(l["bake_ms"]), 0.1)
			vr["bind_poses_differ_between_meshes"] = l["bind_warn"]
			libs[v] = l
		report["variants"][v] = vr
	if libs.has("suit") and libs.has("in"):
		report["skeleton_identical"] = libs["suit"]["names"] == libs["in"]["names"] and libs["suit"]["parent"] == libs["in"]["parent"]
		report["clips_shared_bake"] = libs["in"]["shared"]
		if not bool(report["skeleton_identical"]):
			report["failures"].append("the two GLBs do not have the same skeleton")
	if libs.is_empty():
		report["failures"].append("no astronaut GLB could be loaded")
		_write(report, fixture)
		quit(1)
		return
	for v in libs:
		lib = libs[v]
		var clips: Dictionary = lib["clips"]
		clip_step = {}
		for c in clips:
			clip_step[c] = Npc._clip_max_step(lib["globals"], int(lib["nb"]), lib["parent"], int(clips[c]["row0"]), int(clips[c]["frames"]))
		report["variants"][v]["in_clip_max_step_deg"] = clip_step.duplicate()
		for m in lib["missing"]:
			report["failures"].append("%s: clip '%s' missing" % [v, m])
		for t in _tests(clips):
			var r: Dictionary = _run(t, clips)
			r["variant"] = v
			report["tests"].append(r)
			if not bool(r["ok"]):
				report["failures"].append("%s: %s: %s" % [v, r["name"], r["why"]])
	report["ok"] = (report["failures"] as Array).is_empty()
	report["summary"] = "%d tests, %d failures" % [(report["tests"] as Array).size(), (report["failures"] as Array).size()]
	_write(report, fixture)
	print("npc_check: %s (%s)" % ["PASS" if report["ok"] else "FAIL", report["summary"]])
	for f in (report["failures"] as Array).slice(0, 40):
		print("  FAIL ", f)
	quit(0 if report["ok"] else 1)

func _write(report: Dictionary, fixture: bool) -> void:
	var path: String = "res://build/web_render/godot_check_fixture.json" if fixture else "res://art/npc/godot_check.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("wrote ", ProjectSettings.globalize_path(path))

## Every test: {name, steps: [{goal: [pose, loop], speed, carry, oneshot, secs}]}.
func _tests(clips: Dictionary) -> Array:
	var out: Array = []
	var sm = Pose.new(clips)
	# 0. Baseline: every clip on its own at 1x (the clip's own motion, no transition).
	for c in clips:
		out.append({"name": "clip %s at 1x" % c, "clip_only": c})
	var poses: Array = []
	for p in ["stand", "sit", "lie", "kneel"]:
		if sm.can_pose(p):
			poses.append(p)
	# 1. Every pose-to-pose transition (through stand when neither is stand).
	for p in poses:
		for q in poses:
			if p == q:
				continue
			out.append({"name": "pose %s -> %s" % [p, q], "setup": [p, Pose.REST[p]], "steps": [{"goal": [q, Pose.REST[q]], "until_settled": q, "secs": 0.8}]})
	# 2. Every loop-to-loop change inside each pose.
	for p in poses:
		var loops: Array = []
		for l in Pose.LOOPS[p]:
			if l == "loco" or l == "carry_idle" or l == "dead":
				continue
			if clips.has(l):
				loops.append(l)
		for a in loops:
			for b in loops:
				if a != b:
					out.append({"name": "loop %s: %s -> %s" % [p, a, b], "setup": [p, a], "pre": 0.7, "steps": [{"goal": [p, b], "secs": 1.4}]})
	# 3. Locomotion: start, walk, speed up to the simulation's pace (3.2 m/s outside, 3.6 m/s
	# inside at 1x), slow down, stop (speed / stride playback, capped per clip).
	var ramp: Array = []
	for i in 30:
		ramp.append({"goal": ["stand", "loco"], "speed": 1.05 * float(i + 1) / 30.0, "secs": DT})
	ramp.append({"goal": ["stand", "loco"], "speed": 1.05, "secs": 1.5})
	for i in 30:
		ramp.append({"goal": ["stand", "loco"], "speed": lerpf(1.05, 3.6, float(i + 1) / 30.0), "secs": DT})
	ramp.append({"goal": ["stand", "loco"], "speed": 3.6, "secs": 1.5})
	for i in 45:
		ramp.append({"goal": ["stand", "loco"], "speed": lerpf(3.6, 0.0, float(i + 1) / 45.0), "secs": DT})
	ramp.append({"goal": ["stand", "loco"], "speed": 0.0, "secs": 1.0})
	out.append({"name": "locomotion idle -> walk -> run -> stop", "setup": ["stand", "idle"], "steps": ramp})
	# 4. Carry layer on and off, walking and standing.
	out.append({"name": "carry on/off while walking", "setup": ["stand", "loco"], "setup_speed": 1.4, "steps": [
		{"goal": ["stand", "loco"], "speed": 1.4, "carry": true, "secs": 1.2}, {"goal": ["stand", "loco"], "speed": 1.4, "carry": false, "secs": 1.2}]})
	out.append({"name": "carry: walk -> stop -> walk", "setup": ["stand", "loco"], "setup_speed": 1.4, "setup_carry": true, "steps": [
		{"goal": ["stand", "loco"], "speed": 0.0, "carry": true, "secs": 1.2}, {"goal": ["stand", "loco"], "speed": 1.4, "carry": true, "secs": 1.2}]})
	# 5. Walk into a pose (arrive, stop, sit) and get up and walk away.
	for p in poses:
		if p == "stand":
			continue
		out.append({"name": "walk -> stop -> %s -> walk" % p, "setup": ["stand", "loco"], "setup_speed": 1.4, "steps": [
			{"goal": ["stand", "loco"], "speed": 0.0, "secs": 0.5}, {"goal": [p, Pose.REST[p]], "until_settled": p, "secs": 0.8},
			{"goal": ["stand", "loco"], "speed": 0.0, "until_settled": "stand", "secs": 0.3}, {"goal": ["stand", "loco"], "speed": 1.4, "secs": 1.0}]})
	# 6. One-shots.
	if clips.has("cheer"):
		out.append({"name": "oneshot cheer", "setup": ["stand", "idle"], "steps": [{"oneshot": "cheer", "goal": ["stand", "idle"], "secs": 2.6}]})
	if clips.has("collapse"):
		out.append({"name": "oneshot collapse -> dead", "setup": ["stand", "idle"], "steps": [{"oneshot": "collapse", "goal": ["stand", "idle"], "secs": 3.0}]})
	return out

func _run(t: Dictionary, clips: Dictionary) -> Dictionary:
	if t.has("clip_only"):
		return _run_clip(t, clips)
	var sm = Pose.new(clips)
	sm.angle_fn = func(a, ta, b, tb): return Npc.pose_angle(lib, a, ta, b, tb)
	sm.speed = float(t.get("setup_speed", 0.0))
	sm.carry = bool(t.get("setup_carry", false))
	sm.set_goal(t["setup"][0], t["setup"][1])
	# Settle (not recorded).
	var guard := 0
	while guard < 600 and not (sm.settled_in(t["setup"][0]) and sm.fade <= 0.0 and not sm.is_busy()):
		sm.advance(DT)
		guard += 1
	for i in int(float(t.get("pre", 0.5)) / DT):
		sm.advance(DT)
	var prev = _sample(sm)
	var res := {"name": t["name"], "frames": 0, "max_deg": 0.0, "max_bone": "", "at_frame": -1, "max_root_m": 0.0, "max_hips_m": 0.0, "clips": []}
	var frame := 0
	for st in t["steps"]:
		sm.set_goal(st["goal"][0], st["goal"][1])
		if st.has("speed"):
			sm.speed = float(st["speed"])
		if st.has("carry"):
			sm.carry = bool(st["carry"])
		if st.has("oneshot"):
			sm.play_oneshot(st["oneshot"])
		var n: int = maxi(1, int(round(float(st.get("secs", 1.0)) / DT)))
		var until: String = String(st.get("until_settled", ""))
		var extra_guard := 0
		var i := 0
		while true:
			if until != "":
				if sm.settled_in(until) and sm.fade <= 0.0 and not sm.is_busy():
					if i >= n:
						break
				else:
					i = 0
					extra_guard += 1
					if extra_guard > 900:
						res["why"] = "did not reach pose %s (stuck in %s / %s)" % [until, sm.pose_state, sm.cur]
						res["ok"] = false
						return res
			elif i >= n:
				break
			sm.advance(DT)
			frame += 1
			i += 1
			var cur = _sample(sm)
			var pz: Dictionary = sm.pose()
			var allowed: float = MAX_DEG
			for key in ["a", "b", "c"]:
				var cn: String = String(pz[key])
				if cn != "" and clip_step.has(cn):
					allowed = maxf(allowed, 1.25 * float(clip_step[cn]) * sm.rate_of(cn))
			res["allowed"] = allowed
			var tag: String = "%s%s%s" % [pz["a"], ("+" + String(pz["b"])) if float(pz["wb"]) > 0.0 else "", ("|" + String(pz["c"])) if float(pz["wc"]) > 0.0 else ""]
			if (res["clips"] as Array).is_empty() or res["clips"][-1] != tag:
				(res["clips"] as Array).append(tag)
			_compare(prev, cur, frame, res, allowed)
			prev = cur
	res["frames"] = frame
	res["max_deg"] = snappedf(float(res["max_deg"]), 0.01)
	res["max_root_m"] = snappedf(float(res["max_root_m"]), 0.0001)
	res["max_hips_m"] = snappedf(float(res["max_hips_m"]), 0.0001)
	if (res["clips"] as Array).size() > 24:
		res["clips"] = (res["clips"] as Array).slice(0, 24) + ["..."]
	res.erase("allowed")
	var ok: bool = int(res.get("pops", 0)) == 0 and float(res["max_root_m"]) <= MAX_ROOT
	res["ok"] = ok
	if not ok:
		res["why"] = "%d pop frame(s): worst bone %s %.1f deg at frame %d (limit there %.1f); root moved %.3f m" % [int(res.get("pops", 0)), res.get("pop_bone", res["max_bone"]), float(res.get("pop_deg", res["max_deg"])), int(res.get("pop_frame", res["at_frame"])), float(res.get("pop_limit", MAX_DEG)), res["max_root_m"]]
	return res

## One clip from its first frame past its last (loops: twice round, so the seam counts).
func _run_clip(t: Dictionary, clips: Dictionary) -> Dictionary:
	var c: String = t["clip_only"]
	var d: Dictionary = clips[c]
	var res := {"name": t["name"], "frames": 0, "max_deg": 0.0, "max_bone": "", "at_frame": -1, "max_root_m": 0.0, "max_hips_m": 0.0, "clips": [c]}
	var n: int = int(d["frames"]) * (2 if bool(d["loop"]) else 1)
	var prev = null
	for f in n + 1:
		var tt: float = float(f) / 30.0
		if bool(d["loop"]):
			tt = fposmod(tt, float(d["len"]))
		var s := {"q": [], "root": Vector3.ZERO, "hips": Vector3.ZERO}
		var cur = _sample_pz({"a": c, "ta": tt, "b": "", "tb": 0.0, "wb": 0.0, "c": "", "tc": 0.0, "wc": 0.0})
		if prev != null:
			_compare(prev, cur, f, res, 1e9)
		prev = cur
	res["frames"] = n
	res["max_deg"] = snappedf(float(res["max_deg"]), 0.01)
	res["max_root_m"] = snappedf(float(res["max_root_m"]), 0.0001)
	res["max_hips_m"] = snappedf(float(res["max_hips_m"]), 0.0001)
	# The clip on its own: information (its own steps are ART-NPC's check); the root must hold.
	res["ok"] = float(res["max_root_m"]) <= MAX_ROOT
	res["over_15_deg"] = float(res["max_deg"]) > MAX_DEG
	if not bool(res["ok"]):
		res["why"] = "the root moves %.3f m in one frame" % res["max_root_m"]
	return res

func _sample(sm) -> Dictionary:
	return _sample_pz(sm.pose())

## Local rotation of every bone and the root / hips positions of the drawn pose.
func _sample_pz(pz: Dictionary) -> Dictionary:
	var g: Array = Npc.pose_globals(lib, pz)
	var nb: int = lib["nb"]
	var parent: Array = lib["parent"]
	var q: Array = []
	for i in nb:
		var m: Transform3D = g[i]
		var p: int = parent[i]
		var local: Transform3D = m if p < 0 else (g[p] as Transform3D).affine_inverse() * m
		q.append(local.basis.orthonormalized().get_rotation_quaternion())
	var root_i: int = (lib["names"] as Array).find("root")
	var hips_i: int = (lib["names"] as Array).find("hips")
	return {"q": q, "root": (g[root_i] as Transform3D).origin if root_i >= 0 else Vector3.ZERO, "hips": (g[hips_i] as Transform3D).origin if hips_i >= 0 else Vector3.ZERO}

func _compare(a: Dictionary, b: Dictionary, frame: int, res: Dictionary, allowed: float) -> void:
	var names: Array = lib["names"]
	var deform: Array = lib["deform"]
	var worst_d := 0.0
	var worst_b := ""
	for i in (a["q"] as Array).size():
		# prop.* bones deform nothing (V3 §3.4): not part of the pop test.
		if not deform[i]:
			continue
		var d: float = rad_to_deg((a["q"][i] as Quaternion).angle_to(b["q"][i]))
		if d > worst_d:
			worst_d = d
			worst_b = names[i]
		if d > float(res["max_deg"]):
			res["max_deg"] = d
			res["max_bone"] = names[i]
			res["at_frame"] = frame
	if worst_d > allowed:
		res["pops"] = int(res.get("pops", 0)) + 1
		if worst_d - allowed > float(res.get("pop_over", -1.0)):
			res["pop_over"] = worst_d - allowed
			res["pop_deg"] = snappedf(worst_d, 0.01)
			res["pop_bone"] = worst_b
			res["pop_frame"] = frame
			res["pop_limit"] = snappedf(allowed, 0.01)
	res["max_root_m"] = maxf(float(res["max_root_m"]), (a["root"] as Vector3).distance_to(b["root"]))
	res["max_hips_m"] = maxf(float(res["max_hips_m"]), (a["hips"] as Vector3).distance_to(b["hips"]))
