extends SceneTree
## RENDER (debug): a multi-storey building's floor tops (fx_npc level_y) against the drawn floor (rays down) at its
## anchors.   node tools/godot.mjs script res://tools/render_level_probe.gd <save> <building id>
const CamPhys = preload("res://presentation/fx_cam_phys.gd")
const Npc = preload("res://presentation/fx_npc.gd")
var main
var f := 0
var save := ""
var bid := -1
var cp
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	save = a[0]
	bid = int(a[1])
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		return false
	if f < 200:
		return false
	if cp == null:
		cp = CamPhys.new(main.view.inst, main.view.get_world_3d())
		cp.sync_all()
		return false
	if f < 203:
		return false
	var b: Dictionary = main.sim.state["buildings"][bid]
	var meta: Dictionary = main.view.bmeta[bid]
	var nf: int = int(main.sim.bdef(b["def"]).get("floors", 1))
	var tops: Array = Npc._floor_tops(meta, nf)
	var npc = main.view.npc
	var lv: Array = []
	for i in tops.size():
		lv.append(npc.level_y(b, i, 0.0))
	print("building %d %s floors %d tops (model) %s level_y %s" % [bid, b["def"], nf, str(tops), str(lv)])
	var by_level := {}
	for an in meta["anchors"]:
		var o: Vector3 = (meta["anchors"][an] as Transform3D).origin
		var best := -1
		for i in lv.size():
			if absf(o.y - float(lv[i])) < 0.3:
				best = i
		if best < 0:
			continue
		var p := o + Vector3(0, 0.6, 0)
		var d: float = cp.ray(p, p + Vector3(0, -1.0, 0))
		if d == INF:
			continue
		var fy: float = p.y - d
		var arr: Array = by_level.get_or_add(best, [])
		arr.append(snappedf((fy - float(lv[best])) * 1000.0, 0.1))
	for i in by_level:
		var arr: Array = by_level[i]
		arr.sort()
		var hist := {}
		for v in arr:
			hist[v] = int(hist.get(v, 0)) + 1
		print("  level %d: %d anchors, drawn floor - level_y (mm) histogram %s" % [i, arr.size(), str(hist)])
	return true
