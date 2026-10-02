extends SceneTree
## SIM probe: which calibration workload size tracks the cost of the sim under load. Each round reloads showcase_v5
## (the same ticks every round), times 300 ticks, then times calibration variants of 300, 1500 and 6000 records.
## Prints: S median/mean (ms a tick), then per variant median/mean (ms for 1,000 accesses).
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _calib(n: int) -> Array:
	var big := {}
	for i in n:
		big[i] = {"a": float(i), "b": Vector2(i, i * 2), "c": [i, i + 1, i + 2], "s": "x%d" % (i % 13), "t": {"u": i}}
	var times: Array = []
	var k := 12345
	var acc := 0.0
	for slice in 120:
		var t0: int = Time.get_ticks_usec()
		for r in 1000:
			k = (k * 1103515245 + 12345) & 0x7fffffff
			var e: Dictionary = big[k % n]
			acc += float(e["a"]) * 0.5 + (e["b"] as Vector2).length() * 0.01 + float((e["c"] as Array)[1]) + float((e["t"] as Dictionary)["u"])
			if String(e["s"]) == "x3":
				e["a"] = float(e["a"]) + 0.001
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var sum := 0.0
	for x in times:
		sum += float(x)
	times.sort()
	return [float(times[times.size() / 2]), sum / float(times.size())]

func _init() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave")
	var rounds: int = int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 30
	for round in rounds:
		var sim = Sim.new()
		sim.load_state(Persistence.decode(bytes)["state"])
		for i in 200:
			sim.step()
		var ts: Array = []
		for i in 300:
			var t0: int = Time.get_ticks_usec()
			sim.step()
			ts.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		sim.dispose()
		var sum := 0.0
		for x in ts:
			sum += float(x)
		ts.sort()
		var c1: Array = _calib(300)
		var c2: Array = _calib(1500)
		var c3: Array = _calib(6000)
		print("R %.3f %.3f | %.3f %.3f | %.3f %.3f | %.3f %.3f" % [ts[150], sum / 300.0, c1[0], c1[1], c2[0], c2[1], c3[0], c3[1]])
	quit(0)
