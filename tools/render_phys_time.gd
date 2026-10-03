extends SceneTree
## RENDER (measure): time to build the follow camera's physics shapes (fx_cam_phys._shapes_of) per template.
var main
var f := 0
func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		return false
	if f < 200:
		return false
	var CP = load("res://presentation/fx_cam_phys.gd")
	var rows: Array = []
	var tot := 0
	for key in main.view.inst.batches:
		var tpl: Dictionary = main.view.inst.batches[key]["tpl"]
		var t0: int = Time.get_ticks_usec()
		var sh: Array = CP._shapes_of(tpl)
		var us: int = Time.get_ticks_usec() - t0
		tot += us
		var nf := 0
		for e in sh:
			nf += (e[1] as ConcavePolygonShape3D).get_faces().size() / 3
		rows.append([us, String(key).get_file(), sh.size(), nf])
	var mx := 0
	var n := 0
	var all0: int = Time.get_ticks_usec()
	while not CP._order.is_empty():
		var tj: int = Time.get_ticks_usec()
		CP.step(0)
		mx = maxi(mx, Time.get_ticks_usec() - tj)
		n += 1
	print("jobs %d, longest step %.1f ms, all %.1f ms" % [n, mx / 1000.0, (Time.get_ticks_usec() - all0) / 1000.0])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 12):
		print("%7.1f ms  %s shapes %d tris %d" % [r[0] / 1000.0, r[1], r[2], r[3]])
	print("total %.1f ms over %d templates" % [tot / 1000.0, rows.size()])
	return true
