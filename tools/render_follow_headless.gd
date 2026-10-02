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
var sets: Array = []   # rig.<var>=<float> | view.<var>=<float> | npc.<var>=<float> (A/B switches)

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
		main.view.npc.plan_budget_us = 1 << 30
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
	print("%s: frames %d hops %d | straight n %d head %.3f px cam %.3f mm spd %.2f %% | walk n %d head %.3f px cam %.3f mm | pops %d clip_sw/min %.1f" % [cases[ci], int(rep.get("frames", 0)), int(rep.get("hops", 0)),
		int(s.get("n", 0)), float(s.get("head_jit_px", 0)), float(s.get("cam_jerk_mm", 0)), float(s.get("speed_rip_pct", 0)), int(w.get("n", 0)), float(w.get("head_jit_px", 0)), float(w.get("cam_jerk_mm", 0)), int(rep.get("pops", 0)), float(rep.get("clip_sw_min", 0))])
	main.view.debug_cmd("fprobe stop")
	main.view.follow_stop()
	phase = 0
	return false
