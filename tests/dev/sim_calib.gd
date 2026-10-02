extends SceneTree
## SIM probe: a fixed GDScript workload (dictionary and array work like the sim's) timed 7 times; prints the
## minimum and the median in ms. Run beside a perf test to scale its number to an unloaded machine.
func _init() -> void:
	var times: Array = []
	for rep in 7:
		var d := {}
		for i in 300:
			d[i] = {"a": float(i), "b": Vector2(i, i * 2), "c": [i, i + 1], "s": "x%d" % (i % 7)}
		var t0: int = Time.get_ticks_usec()
		var acc := 0.0
		for r in 400:
			for k in d:
				var e: Dictionary = d[k]
				acc += float(e["a"]) * 0.5 + (e["b"] as Vector2).length() * 0.01 + float((e["c"] as Array)[1])
				if String(e["s"]) == "x3":
					e["a"] = float(e["a"]) + 0.001
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	print("CALIB min %.2f median %.2f ms" % [times[0], times[3]])
	quit(0)
