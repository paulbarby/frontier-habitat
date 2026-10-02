extends SceneTree
## RENDER (debug): the follow camera's physics sight bodies (fx_cam_phys) round the followed person.
##   node tools/godot.mjs script res://tools/render_phys_debug.gd [save] [want]
var main
var f := 0
var save := "res://content/saves/showcase_v3_late.fhsave"
var want := "in"
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: save = a[0]
	if a.size() > 1: want = a[1]
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		return false
	main.set_process(false)
	main._process(1.0 / 60.0)
	main.rig.set_process(false)
	main.rig._process(1.0 / 60.0)
	if f == 360:
		print(main.view.debug_cmd("fprobe start 30 " + want))
	if f > 380 and f % 60 == 0:
		var v = main.view
		var cp = v.camphys
		var keys := {}
		if cp != null:
			for h in cp._bodies:
				var k: String = String(cp._bodies[h].get("key", "-")).get_file()
				keys[k] = int(keys.get(k, 0)) + 1
		var bp: Vector3 = v.agent_world_pos(v.follow_id) + Vector3(0, 1.3, 0)
		var hs := ""
		if cp != null:
			for k in 8:
				var dd := Vector3(cos(k * PI / 4.0), 0.0, sin(k * PI / 4.0))
				var t: float = cp.ray(bp, bp + dd * 10.0)
				hs += " %.1f(%s)" % [t, cp.dbg_last if t < INF else ""]
			var td: float = cp.ray(bp, bp + Vector3(0, -3, 0))
			hs += " down %.2f %s" % [td, cp.dbg_last]
		print("rays:" + hs)
		var rr := ""
		for bid in v._room_r:
			rr += " %s %.2f/%.2f" % [main.sim.state["buildings"][bid]["def"], float(v._room_r[bid]), float(main.sim.state["buildings"][bid]["radius"])]
		print("room_r:" + rr)
		print("f%d %s | bodies %d %s" % [f, v.debug_cmd("framecheck"), cp.body_count() if cp != null else -1, str(keys).left(600)])
	return f >= 380 + 400
