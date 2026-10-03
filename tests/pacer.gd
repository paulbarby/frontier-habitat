extends RefCounted
## Perf calibration in blocks (orchestrator decision 2026-10-02; tests/helpers.gd has the workload and the
## quiet readings). A perf test runs in blocks of about 100 ticks; the fixed workload is read at every block
## boundary (outside the timed part), and the block's raw time is scaled by the factor of its two neighbouring
## readings: min(1, (quiet / reading) ^ CALIB_POWER). A neighbour that starts or stops during the test then
## moves only the blocks it touched. Reading: the mean slice for a test that checks a mean of windows, the median
## slice for one that checks the median tick.

const H = preload("res://tests/helpers.gd")

var mean_of_slices: bool
var power: float
var slices: int
var readings: Array = []      # ms, one more than blocks
var raw: Array = []           # raw ms of each block
var ticks: Array = []         # ticks of each block

func _init(mean_of_slices_: bool = true, power_: float = H.CALIB_POWER, slices_: int = 60) -> void:
	mean_of_slices = mean_of_slices_
	power = power_
	slices = slices_

## The first reading (call once before the first block).
func start() -> void:
	readings.append(H.calib_ms(mean_of_slices, slices))

## A block of n ticks took raw_ms: the next reading is taken here.
func block(raw_ms: float, n: int) -> void:
	raw.append(raw_ms)
	ticks.append(n)
	readings.append(H.calib_ms(mean_of_slices, slices))

func factor_of(i: int) -> float:
	var c: float = (float(readings[i]) + float(readings[i + 1])) * 0.5
	return H.calib_factor([c], mean_of_slices, power)

## Scaled ms a tick of blocks [from, to).
func per_tick(from: int, to: int) -> float:
	var sum := 0.0
	var n := 0
	for i in range(from, to):
		sum += float(raw[i]) * factor_of(i)
		n += int(ticks[i])
	return sum / float(maxi(1, n))

## Raw ms a tick of blocks [from, to).
func raw_per_tick(from: int, to: int) -> float:
	var sum := 0.0
	var n := 0
	for i in range(from, to):
		sum += float(raw[i])
		n += int(ticks[i])
	return sum / float(maxi(1, n))

## The mean factor over all blocks (for the result line).
func mean_factor() -> float:
	var s := 0.0
	for i in raw.size():
		s += factor_of(i)
	return s / float(maxi(1, raw.size()))

func reading_text() -> String:
	var s: Array = readings.duplicate()
	s.sort()
	return "%.2f / %.2f / %.2f ms (min / median / max of %d)" % [s[0], s[s.size() / 2], s[s.size() - 1], s.size()]
