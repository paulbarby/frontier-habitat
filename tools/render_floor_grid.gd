extends SceneTree
## RENDER (debug): the drawn floor round a point (rays down against the physics shapes of every structure copy).
##   node tools/godot.mjs script res://tools/render_floor_grid.gd <save> x y z [radius=1.0] [step=0.25]
## Prints a grid of floor heights relative to y (mm) and the group hit at the centre.
const CamPhys = preload("res://presentation/fx_cam_phys.gd")
var main
var f := 0
var save := ""
var c := Vector3.ZERO
var rad := 1.0
var step := 0.25
var cp
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	save = a[0]
	c = Vector3(float(a[1]), float(a[2]), float(a[3]))
	if a.size() > 4:
		rad = float(a[4])
	if a.size() > 5:
		step = float(a[5])
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		if OS.get_cmdline_user_args().has("nofar"):
			main.view.far_lod_on = false
		return false
	if f < 200:
		return false
	if cp == null:
		cp = CamPhys.new(main.view.inst, main.view.get_world_3d())
		cp.sync_all()
		return false
	if f < 203:
		return false
	var n: int = int(round(rad / step))
	print("floor round %s (mm vs y %.3f), rows z, columns x, step %.2f m" % [str(c), c.y, step])
	for iz in range(-n, n + 1):
		var line := "z%+5.2f:" % [iz * step]
		for ix in range(-n, n + 1):
			var p := Vector3(c.x + ix * step, c.y + 0.6, c.z + iz * step)
			var d: float = cp.ray(p, p + Vector3(0, -1.4, 0))
			line += (" %+6.1f" % [(p.y - d - c.y) * 1000.0]) if d != INF else "   none"
		print(line)
	var p0 := Vector3(c.x, c.y + 0.6, c.z)
	cp.ray(p0, p0 + Vector3(0, -1.4, 0))
	print("centre hit: %s" % String(cp.dbg_last))
	for dz in [-0.25, 0.0, 0.25]:
		for dx in [-0.25, 0.0, 0.25]:
			var p1 := Vector3(c.x + dx, c.y + 0.6, c.z + dz)
			var d1: float = cp.ray(p1, p1 + Vector3(0, -1.4, 0))
			print("  %+.2f %+.2f: %s %s" % [dx, dz, ("%+.1f" % [(p1.y - d1 - c.y) * 1000.0]) if d1 != INF else "none", String(cp.dbg_last)])
	return true
