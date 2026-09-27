extends SceneTree
## Developer tool: times the debug `reveal` command (and a satellite band) in one tick on
## showcase_v4, for several radii, split into the reveal itself and the rest of the tick.
##   node tools/godot.mjs script res://tests/dev/reveal_time.gd
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	for r in [100.0, 400.0, 1000.0, 4000.0]:
		var sim = Sim.new()
		sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"], {"debug": true})
		var c: Vector2 = sim.world.center
		var poi: Dictionary = {}
		for p in sim.explore.pois():
			if not bool(p["found"]) and poi.is_empty():
				poi = p
		var at := Vector2(poi["x"], poi["y"]) if not poi.is_empty() else c + Vector2(600, -300)
		sim.step()
		var t0: int = Time.get_ticks_usec()
		var n: int = sim.explore.reveal(at, r)
		var t1: int = Time.get_ticks_usec()
		sim.submit("reveal", {"x": at.x + 3.0, "y": at.y, "r": r})
		sim.step()
		var t2: int = Time.get_ticks_usec()
		var worst := 0.0
		for i in 20:
			var t3: int = Time.get_ticks_usec()
			sim.step()
			worst = maxf(worst, float(Time.get_ticks_usec() - t3) / 1000.0)
		print("r %d: reveal() %.2f ms (%d cells), next tick with a reveal command %.2f ms, worst of the next 20 ticks %.2f ms, found %s" % [int(r), float(t1 - t0) / 1000.0, n, float(t2 - t1) / 1000.0, worst, str(poi.get("found", "-"))])
		sim.dispose()
	var s2 = Sim.new()
	s2.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))["state"])
	var t4: int = Time.get_ticks_usec()
	s2.explore.reveal_band(12, true)
	print("satellite band %.2f ms" % (float(Time.get_ticks_usec() - t4) / 1000.0))
	s2.dispose()
	quit(0)
