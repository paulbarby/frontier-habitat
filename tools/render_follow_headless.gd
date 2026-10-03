extends SceneTree
## RENDER: the follow-view probe (presentation/fx_follow_probe.gd) headless with a FIXED frame time, so
## two runs of the same case give the same numbers (the web probe depends on the machine's load).
## Same cases as tools/render_follow_probe.mjs. Writes build/web_render/fprobe_hl/<case>.json/.csv.
##   node tools/godot.mjs script res://tools/render_follow_headless.gd [cases=in1,in4] [secs=20] [fps=60] [out=fprobe_hl]
## Head jitter in px is measured in the headless viewport (its size is printed), not the browser's.
const CASES := {
	"in1": ["res://content/saves/showcase_v3_late.fhsave", "in", 1],
	"in4": ["res://content/saves/showcase_v3_late.fhsave", "in", 4],
	"out1": ["res://content/saves/showcase_v3_late.fhsave", "out", 1],
	"out4": ["res://content/saves/showcase_v3_late.fhsave", "out", 4],
	"dome1": ["res://build/web_render/dome_v5.fhsave", "b:super_dome", 1],
	"v5in1": ["res://content/saves/showcase_v5.fhsave", "in", 1],
	"v5in4": ["res://content/saves/showcase_v5.fhsave", "in", 4],
}
var main
var cases: Array = ["in1", "in4"]
var secs := 20.0
var dt := 1.0 / 60.0
var out_dir := "res://build/web_render/fprobe_hl"
var ci := -1
var frame := 0
var phase := 0
var want_frames := 0
var summary := {}
var sets: Array = []
var slice_t := Vector2(-1, -1)  # slice=T0,T1: a top-down picture of the drawn geometry, body and camera path
var slice_log: Array = []   # rig.<var>=<float> | view.<var>=<float> | npc.<var>=<float> (A/B switches)

func _initialize() -> void:
	for s in OS.get_cmdline_user_args():
		if s.begins_with("cases="):
			cases = Array(s.substr(6).split(","))
		elif s.begins_with("secs="):
			secs = float(s.substr(5))
		elif s.begins_with("fps="):
			dt = 1.0 / float(s.substr(4))
		elif s.begins_with("rig.") or s.begins_with("view.") or s.begins_with("npc."):
			sets.append(s)
		elif s.begins_with("slice="):
			var sv: PackedStringArray = s.substr(6).split(",")
			slice_t = Vector2(float(sv[0]), float(sv[1]))
		elif s.begins_with("out="):
			out_dir = "res://build/web_render/" + s.substr(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _step() -> void:
	main.set_process(false)
	main._process(dt)
	if main.rig != null:
		main.rig.set_process(false)
		main.rig._process(dt)

func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	if phase == 0:
		ci += 1
		if ci >= cases.size():
			var f := FileAccess.open(out_dir + "/summary.json", FileAccess.WRITE)
			f.store_string(JSON.stringify(summary, " "))
			return true
		var c: Array = CASES.get(cases[ci], [])
		if not c.is_empty():
			c = c.duplicate()
		if c.is_empty() or not FileAccess.file_exists(c[0]):
			print("skip ", cases[ci])
			return false
		main._import_bytes(FileAccess.get_file_as_bytes(c[0]))
		main.set_process(false)
		for nm in ["hud", "audio"]:
			var nd = main.get(nm)
			if nd != null and nd is Node:
				(nd as Node).process_mode = Node.PROCESS_MODE_DISABLED
		main.view.npc.plan_budget_us = 1 << 30
		main.view.cam_step_us = 1 << 30
		main.view.npc.no_far = true
		main.step_cap_us = 1 << 30
		main.set_speed(int(c[2]))
		for st in sets:
			var kv: PackedStringArray = String(st).split("=")
			var tgt = main.rig if kv[0].begins_with("rig.") else (main.view if kv[0].begins_with("view.") else main.view.npc)
			tgt.set(kv[0].get_slice(".", 1), float(kv[1]))
			print("set ", kv[0], " = ", tgt.get(kv[0].get_slice(".", 1)))
		frame = 0
		phase = 1
		return false
	if phase == 1:
		_step()
		frame += 1
		# 6 s of game before the probe (the view builds and the bodies settle), as the web probe waits.
		if frame >= int(6.0 / dt):
			var c: Array = CASES[cases[ci]]
			print("%s: %s (viewport %s)" % [cases[ci], main.view.debug_cmd("fprobe start %d %s" % [int(secs), c[1]]), str(main.get_viewport().get_visible_rect().size)])
			want_frames = int((secs + 0.5) / dt)
			frame = 0
			phase = 2
		return false
	_step()
	frame += 1
	var tt: float = frame * dt
	if slice_t.x >= 0.0 and tt >= slice_t.x and tt <= slice_t.y:
		var v = main.view
		var cp: Vector3 = main.rig.camera.global_position
		var oc: float = v.follow_occluder(cp)
		slice_log.append([v.agent_world_pos(v.follow_id), cp, v.follow_occ_n > 0, v.follow_occ_at, float(main.rig._sh_arm), main.rig.dbg_free])
		if frame % 6 == 0:
			print("t%.2f body %s cam %s occ %s %s arm %.2f free %s" % [tt, str((slice_log[-1][0] as Vector3).snapped(Vector3.ONE * 0.01)), str(cp.snapped(Vector3.ONE * 0.01)), str(slice_log[-1][2]), String(v.follow_occ_why), float(main.rig._sh_arm), str((main.rig.dbg_free as Vector3).snapped(Vector3.ONE * 0.01))])
	if slice_t.x >= 0.0 and tt > slice_t.y and not slice_log.is_empty():
		_slice_png()
		slice_log.clear()
	if frame < want_frames:
		return false
	var rep: Dictionary = main.view.fprobe.report()
	rep.erase("fc_dbg")
	rep["case"] = cases[ci]
	rep["dt"] = dt
	summary[cases[ci]] = rep
	var f := FileAccess.open(out_dir + "/%s.json" % cases[ci], FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, " "))
	f = FileAccess.open(out_dir + "/%s.csv" % cases[ci], FileAccess.WRITE)
	f.store_string(main.view.fprobe.csv(100000))
	var s: Dictionary = rep.get("straight", {})
	var w: Dictionary = rep.get("walk", {})
	print("%s: frames %d hops %d | straight n %d head %.3f px cam %.3f mm spd %.2f %% | walk n %d head %.3f px cam %.3f mm | pops %d clip_sw/min %.1f occluded %d wall_centre %d off_screen %d" % [cases[ci], int(rep.get("frames", 0)), int(rep.get("hops", 0)),
		int(s.get("n", 0)), float(s.get("head_jit_px", 0)), float(s.get("cam_jerk_mm", 0)), float(s.get("speed_rip_pct", 0)), int(w.get("n", 0)), float(w.get("head_jit_px", 0)), float(w.get("cam_jerk_mm", 0)), int(rep.get("pops", 0)), float(rep.get("clip_sw_min", 0)), int(rep.get("occluded_frames", -1)), int(rep.get("wall_centre_frames", -1)), int(rep.get("off_screen_frames", -1))])
	print("   arm [clamped, pulled, m] %s" % str(main.rig.dbg_arm))
	print("   search [fail, found] ", main.rig.dbg_search, " od ", snappedf(main.rig._sh_od, 0.01))
	main.rig.dbg_search = [0, 0]
	main.view.debug_cmd("fprobe stop")
	main.view.follow_stop()
	phase = 0
	return false


func _slice_png() -> void:
	var c := Vector3.ZERO
	for e in slice_log:
		c += e[0]
	c /= slice_log.size()
	var half := 5.0
	var px := 0.05
	var n: int = int(2.0 * half / px)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	var cph = main.view.camphys
	var fy: float = (slice_log[0][0] as Vector3).y
	# walls at three heights: 1.25 (red), 1.6 (green), 1.8 (blue) over the floor
	var cols := [Color(0.9, 0.3, 0.3), Color(0.3, 0.7, 0.3), Color(0.3, 0.3, 0.9)]
	var hs := [1.25, 1.6, 1.8]
	for k in 3:
		for j in n:
			for i in n:
				var p := Vector3(c.x - half + i * px, fy + hs[k], c.z - half + j * px)
				if cph.ray(p, p + Vector3(px, 0, 0)) < INF or cph.ray(p, p + Vector3(0, 0, px)) < INF:
					var o: Color = img.get_pixel(i, j)
					img.set_pixel(i, j, o * cols[k] if o != Color(1, 1, 1) else cols[k])
	var to_px = func(p: Vector3) -> Vector2i: return Vector2i(int((p.x - c.x + half) / px), int((p.z - c.z + half) / px))
	for idx in slice_log.size():
		var e: Array = slice_log[idx]
		var b: Vector2i = to_px.call(e[0])
		var q: Vector2i = to_px.call(e[1])
		var f2: Vector2i = to_px.call(e[5])
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			if Rect2i(0, 0, n, n).has_point(b + d):
				img.set_pixel(b.x + d.x, b.y + d.y, Color(0, 0, 0))
			if Rect2i(0, 0, n, n).has_point(q + d):
				img.set_pixel(q.x + d.x, q.y + d.y, Color(1, 0.5, 0) if e[2] else Color(0, 0.8, 0.9))
			if Rect2i(0, 0, n, n).has_point(f2 + d):
				img.set_pixel(f2.x + d.x, f2.y + d.y, Color(0.8, 0, 0.8))
		if idx % 30 == 0:
			for t in 20:
				var m: Vector2i = Vector2i(lerp(Vector2(b), Vector2(q), t / 20.0))
				if Rect2i(0, 0, n, n).has_point(m):
					img.set_pixel(m.x, m.y, Color(0.5, 0.5, 0.5))
	img.save_png(out_dir + "/slice.png")
	print("slice centre %s -> %s/slice.png" % [str(c), out_dir])
