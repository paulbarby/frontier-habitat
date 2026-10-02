extends SceneTree
## SIM probe: which calibration workload tracks the cost of the sim under load. Prints, for 8 rounds in one
## process (the sim loaded): A = small workload (calib_ms), B = large-footprint workload, S = ms a tick of the sim.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const H = preload("res://tests/helpers.gd")

var big := {}

func _build_big() -> void:
	for i in 40000:
		big[i] = {"a": float(i), "b": Vector2(i, i * 2), "c": [i, i + 1, i + 2], "s": "x%d" % (i % 13), "t": {"u": i}}

func _calib_b() -> float:
	var best := 1e9
	for rep in 5:
		var t0: int = Time.get_ticks_usec()
		var acc := 0.0
		var k := 12345
		for r in 60000:
			k = (k * 1103515245 + 12345) & 0x7fffffff
			var e: Dictionary = big[k % 40000]
			acc += float(e["a"]) * 0.5 + (e["b"] as Vector2).length() * 0.01 + float((e["c"] as Array)[1]) + float((e["t"] as Dictionary)["u"])
			if String(e["s"]) == "x3":
				e["a"] = float(e["a"]) + 0.001
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
	return best

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(30.0)
	_build_big()
	for round in 8:
		var a: float = H.calib_ms()
		var b: float = _calib_b()
		var ts: Array = []
		for i in 300:
			var t0: int = Time.get_ticks_usec()
			sim.step()
			ts.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		ts.sort()
		print("A %.1f  B %.1f  S median %.3f  S mean %.3f" % [a, b, ts[150], (ts.reduce(func(x, y): return x + y, 0.0) / ts.size())])
	sim.dispose()
	quit(0)
