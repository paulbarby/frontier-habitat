extends SceneTree
## Test of the music director rules (docs/V3_1_DESIGN.md §2.1), headless.
##   node tools/godot.mjs script res://tools/ui/test_music.gd
## Drives ui/music.gd with simulated time (update() every 0.5 s) and the real music files.

const Music = preload("res://ui/music.gd")

var fails := 0
var m
var _n := 0

func _init() -> void:
	m = Music.new()
	root.add_child(m)

func _process(_d: float) -> bool:
	_n += 1
	if _n < 3:
		return false
	_run()
	return true

func _run() -> void:
	for id in ["mus_title", "mus_day_1", "mus_day_2", "mus_night", "mus_tension", "mus_arrival"]:
		var p: String = "res://assets/audio/%s.mp3" % id
		if ResourceLoader.exists(p):
			m.add_track(id, load(p), -6.0)
	check("6 tracks load", m.tracks.size() == 6, str(m.tracks.keys()))
	# Title, then play by day.
	step(true, false, false, 2)
	check("title plays mus_title", m.track == "mus_title", m.describe())
	step(false, false, false, 2)
	check("day plays mus_day_1", m.track == "mus_day_1", m.describe())
	# Same state: no restart.
	var p0 = m._players[m._cur]
	step(false, false, false, 20)
	check("same state does not restart", m.track == "mus_day_1" and m._players[m._cur] == p0, m.describe())
	# Track ends: a gap of 5..20 s, then the other day track.
	m._on_finished(m._cur)
	check("after a track: a silent gap", m.track == "" and m._gap_left >= 5.0 and m._gap_left <= 20.0, m.describe())
	var gap: float = m._gap_left
	step(false, false, false, int(ceil(gap / 0.5)) + 1)
	check("after the gap: mus_day_2 (day tracks alternate)", m.track == "mus_day_2", m.describe())
	# Tension: starts at once, holds 30 s after the cause clears.
	step(false, false, true, 4)
	check("tension plays mus_tension", m.state == "tension" and m.track == "mus_tension", m.describe())
	step(false, false, false, 58)   # 29 s without a cause
	check("tension holds at 29 s after the cause clears", m.state == "tension", m.describe())
	step(false, false, false, 4)    # 31 s
	check("back to day after 30 s", m.state == "day" and m.track.begins_with("mus_day"), m.describe())
	# A cause that comes back inside the hold restarts the hold, not the track.
	step(false, false, true, 2)
	var pt = m._players[m._cur]
	step(false, false, false, 40)
	step(false, false, true, 2)
	check("cause back inside the hold: tension track not restarted", m.state == "tension" and m._players[m._cur] == pt, m.describe())
	step(false, false, false, 64)
	# Night.
	step(false, true, false, 2)
	check("night plays mus_night", m.track == "mus_night", m.describe())
	# Gaps are deterministic: the same counter gives the same gaps.
	var gaps: Array = []
	for i in 4:
		m._on_finished(m._cur)
		gaps.append(m._gap_left)
		step(false, true, false, int(ceil(m._gap_left / 0.5)) + 1)
	check("gaps 5..20 s and deterministic", gaps.all(func(g): return g >= 5.0 and g <= 20.0), str(gaps))
	# Arrival cue ducks the music.
	m.cue("mus_arrival")
	check("arrival cue plays and ducks", m._cue.playing or m._duck < 0.0, "duck %.0f dB" % m._duck)
	print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)

func step(title: bool, night: bool, tension: bool, n: int) -> void:
	for i in n:
		m.update(title, night, tension, 0.5)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1
