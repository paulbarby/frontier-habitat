extends SceneTree
## SIM probe: the perf calibration reading (tests/helpers.gd calib_stats: [median, mean] slice, ms per 1,000 scattered
## accesses), 4 times. Run it beside a perf test to see the load.
const H = preload("res://tests/helpers.gd")
func _init() -> void:
	var r: Array = []
	for i in 4:
		var c: Array = H.calib_stats()
		r.append("%.3f/%.3f" % [c[0], c[1]])
	print("CALIB median/mean %s" % str(r))
	quit(0)
