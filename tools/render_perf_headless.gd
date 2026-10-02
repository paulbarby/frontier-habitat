extends SceneTree
## RENDER: CPU cost of the view per frame, headless (fixed 1/60 s frames), so it does not depend on other
## programs loading the machine the way the web fps does. Cases on one save: overview (110 m), all roofs
## off, follow view indoors, follow view in the super dome. Prints view ms (median, p95), sim ms, fx_npc ms
## and the per-module split (world_view prof). GPU cost is not measured here (tools/render_perf.mjs).
##   node tools/godot.mjs script res://tools/render_perf_headless.gd [save] [frames=300]
var main
var save := "res://content/saves/showcase_v5.fhsave"
var nfr := 300
var f := 0
var ci := -1
var cases := ["overview", "roofs_off", "follow_in", "follow_dome"]
var only := ""
var rows: Array = []
var phase := 0
var report := {}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		save = a[0]
	if a.size() > 1:
		nfr = int(a[1])
	if a.size() > 2:
		cases = Array(a[2].split(","))
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _step() -> void:
	main.set_process(false)
	var t0: int = Time.get_ticks_usec()
	main._process(1.0 / 60.0)
	var t1: int = Time.get_ticks_usec()
	if main.rig != null:
		main.rig.set_process(false)
		main.rig._process(1.0 / 60.0)
	rows.append([(t1 - t0) / 1000.0, float(main.get("_t_sim")), float(main.get("_t_view")), float(main.view.npc.npc_ms) if main.view.npc != null else 0.0])

func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	if phase == 0:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		main.step_cap_us = 1 << 30
		main.set_speed(1)
		phase = 1
		f = 0
		return false
	if phase == 1:
		_step()
		f += 1
		if f < 240:
			return false
		phase = 2
	if f == 240 or rows.size() >= nfr:
		if ci >= 0:
			_finish(cases[ci])
		ci += 1
		if ci >= cases.size():
			var fo := FileAccess.open("res://build/web_render/perf_headless.json", FileAccess.WRITE)
			fo.store_string(JSON.stringify(report, " "))
			return true
		_setup(cases[ci])
		rows = []
		main.view.stats()   # reset the module sums
		f = 241
		for k in 30:
			_step()
		rows = []
		main.view.stats()
		return false
	_step()
	return false

func _setup(c: String) -> void:
	main.view.follow_stop()
	main.view.set_roofs_off(false)
	match c:
		"overview":
			main.rig.target_distance = 110.0
			main.rig.distance = 110.0
		"roofs_off":
			main.rig.target_distance = 110.0
			main.rig.distance = 110.0
			main.view.set_roofs_off(true)
		"follow_in":
			main.view.debug_cmd("fprobe start 600 in")
		"follow_dome":
			main.view.debug_cmd("fprobe start 600 b:super_dome")

func _finish(c: String) -> void:
	var tot: Array = rows.map(func(r): return float(r[0]))
	var vw: Array = rows.map(func(r): return float(r[2]))
	var sm: Array = rows.map(func(r): return float(r[1]))
	var np: Array = rows.map(func(r): return float(r[3]))
	var st: Dictionary = main.view.stats()
	var rep := {"frames": rows.size(), "total_med": _pc(tot, 0.5), "total_p95": _pc(tot, 0.95), "view_med": _pc(vw, 0.5), "view_p95": _pc(vw, 0.95),
		"sim_med": _pc(sm, 0.5), "sim_p95": _pc(sm, 0.95), "npc_med": _pc(np, 0.5), "prof": st.get("prof", {}), "npc": (st.get("npc", {}) as Dictionary).get("prof_ms", []),
		"bodies": (st.get("npc", {}) as Dictionary).get("bodies", 0), "instances": st.get("instances", 0)}
	report[c] = rep
	print("PERF %s: frame %.1f ms (p95 %.1f) | view %.1f (p95 %.1f) | sim %.1f (p95 %.1f) | npc %.1f | bodies %d" % [c, rep["total_med"], rep["total_p95"], rep["view_med"], rep["view_p95"], rep["sim_med"], rep["sim_p95"], rep["npc_med"], int(rep["bodies"])])
	print("   prof ", JSON.stringify(rep["prof"]))
	var ns: Dictionary = st.get("npc", {})
	print("   npc ", JSON.stringify(rep["npc"]), " body %s write %s lamps %s walk %s bodies/frame %s dyn %s why %s" % [ns.get("body_ms"), ns.get("write_ms"), ns.get("lamps_ms"), ns.get("walk_ms"), ns.get("bodies_per_frame"), ns.get("dyn_rows"), JSON.stringify(ns.get("blend_why_per_frame"))])

static func _pc(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return snappedf(float(b[clampi(int(q * (b.size() - 1)), 0, b.size() - 1)]), 0.01)
