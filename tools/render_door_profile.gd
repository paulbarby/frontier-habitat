extends SceneTree
## RENDER (debug): the drawn floor along the axis of doorways (room centre -> door -> corridor), rays down against
## the physics shapes of every structure copy, relative to the room's floor (fx_npc._floor_y), in mm.
##   node tools/godot.mjs script res://tools/render_door_profile.gd <save> [defs=airlock,habitat] [max per def=2]
const CamPhys = preload("res://presentation/fx_cam_phys.gd")
var main
var f := 0
var save := ""
var defs: Array = ["airlock", "habitat", "mine", "kitchen"]
var per := 2
var cp
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	save = a[0]
	if a.size() > 1:
		defs = Array(a[1].split(","))
	if a.size() > 2:
		per = int(a[2])
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
	var blds: Dictionary = main.sim.state["buildings"]
	var seen := {}
	for d in main.view.doors.doors:
		var rid: int = int(d["room"])
		if not blds.has(rid):
			continue
		var df: String = String(blds[rid]["def"])
		if not defs.has(df) or int(seen.get(df, 0)) >= per:
			continue
		seen[df] = int(seen.get(df, 0)) + 1
		var c: Vector2 = blds[rid]["pos"]
		var dp: Vector3 = d["pos"]
		var od: Vector2 = (Vector2(dp.x, dp.z) - c).normalized()
		var rf: float = main.view.npc._floor_y(blds[rid])
		var rr: float = float(blds[rid]["radius"])
		var dd: float = Vector2(dp.x, dp.z).distance_to(c)
		var line := "%s %d R %.2f door at %.2f (R - %.2f):" % [df, rid, rr, dd, rr - dd]
		var s := -1.0
		while s <= 1.21:
			var q: Vector2 = Vector2(dp.x, dp.z) + od * s
			var a := Vector3(q.x, rf + 0.6, q.y)
			var hit: float = cp.ray(a, a + Vector3(0, -1.0, 0))
			line += " %+.2f:%s" % [s, ("%+.0f" % [((a.y - hit) - rf) * 1000.0]) if hit != INF else "-"]
			s += 0.05
		var tf = main.view.npc._tube_floor(Vector3(dp.x + od.x * (rr - dd + 0.25), dp.y, dp.z + od.y * (rr - dd + 0.25)))
		line += " | tube floor %+.0f" % [((tf as Vector2).x - rf) * 1000.0 if (tf as Vector2).x != INF else 9999.0]
		print(line)
	return true
