extends SceneTree
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	var nav = sim.nav
	for k in 3:
		var x0: int = 1152 + 64 * k
		var t0: int = Time.get_ticks_usec()
		var w: Dictionary = nav._make_window(x0, 1152)
		var t1: int = Time.get_ticks_usec()
		nav._mark_window(w)
		var t2: int = Time.get_ticks_usec()
		var c := Vector2i(x0 + 160, 1152 + 160)
		var q = nav._nearest_in(w, Vector2(c), 8)
		nav._area_of(w, nav.cell_of(q))
		var t3: int = Time.get_ticks_usec()
		print("make %.1f ms (includes one mark), mark again %.1f ms, first area fill %.1f ms" % [float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0, float(t3 - t2) / 1000.0])
	sim.dispose()
	quit(0)
