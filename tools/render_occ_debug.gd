extends SceneTree
## RENDER (debug): where the follow view's occluder test hits (fx_occ), on a save and a probe case.
##   node tools/godot.mjs script res://tools/render_occ_debug.gd <save> <want> [frames]
var main
var f := 0
var save := "res://build/web_render/dome_v5.fhsave"
var want := "b:super_dome"
var nmax := 600
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: save = a[0]
	if a.size() > 1: want = a[1]
	if a.size() > 2: nmax = int(a[2])
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		main.view.npc.plan_budget_us = 1 << 30
		main.step_cap_us = 1 << 30
		return false
	main.set_process(false)
	main._process(1.0 / 60.0)
	main.rig.set_process(false)
	main.rig._process(1.0 / 60.0)
	if f == 360:
		print(main.view.debug_cmd("fprobe start 30 " + want))
	if f > 380 and f % 30 == 0:
		var cam: Camera3D = main.rig.camera
		var al: float = main.view.follow_occluder(cam.global_position)
		var bp = main.view.agent_world_pos(main.view.follow_id)
		if main.view.follow_occ_n > 0:
			var hit: Vector3 = main.view.follow_occ_at
			var info := ""
			for bid in main.view.bmeta:
				var b: Dictionary = main.sim.state["buildings"][bid]
				if (b["pos"] as Vector2).distance_to(Vector2(hit.x, hit.z)) < float(b["radius"]) + 4.0:
					var meta: Dictionary = main.view.bmeta[bid]
					var tpl: Dictionary = meta.get("tpl", {})
					var sc: float = float(tpl.get("scale", 1.0))
					var lp: Vector3 = ((meta["xf"] as Transform3D) * Transform3D(Basis.from_scale(Vector3(sc, sc, sc)), Vector3.ZERO)).affine_inverse() * hit
					info += " %s(%s) local %s" % [b["def"], tpl.get("key", "?"), str(lp.snapped(Vector3.ONE * 0.01))]
			print("f%d body %s cam %s allow %.2f hit %s%s" % [f, str((bp as Vector3).snapped(Vector3.ONE * 0.01)), str(cam.global_position.snapped(Vector3.ONE * 0.01)), al, str(hit.snapped(Vector3.ONE * 0.01)), info])
		else:
			print("f%d clear" % f)
	return f >= 380 + nmax
