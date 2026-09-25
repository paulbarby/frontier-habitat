extends Node
## Music director (docs/V3_1_DESIGN.md §2.1). Plays the mood music on the Music bus.
##
## State, from presentation/main.gd twice a second: "title", "day", "night" or "tension".
## - A change of state crossfades to that state's track in FADE seconds (two players).
## - The same state never restarts its track.
## - Day tracks alternate (mus_day_1, mus_day_2).
## - Tension holds at least TENSION_HOLD seconds after its cause clears.
## - When a track ends, a silence gap of 5..20 s follows, then the next track of the state.
##   The gap comes from a local counter, never from the simulation's random streams.
##   The tension track loops without a gap.
## - cue(name): a short cue (mus_arrival) over the music, which dips by DUCK_DB meanwhile.
## Tracks: the "music" table of res://assets/audio/manifest.json {id: {file, db}}.
## Silent and safe when a file is missing.

const FADE := 4.0
const TENSION_HOLD := 30.0
const DUCK_DB := -10.0
const OFF_DB := -60.0
const STATE_TRACKS := {"title": ["mus_title"], "day": ["mus_day_1", "mus_day_2"], "night": ["mus_night"], "tension": ["mus_tension"]}

var tracks := {}          # id -> {stream, db}
var state := ""           # state now playing (after the tension hold)
var track := ""           # track id now playing ("" in a gap)
var _players: Array = []  # two players, crossfaded
var _cur := 0             # index of the current player
var _cue: AudioStreamPlayer
var _day_turn := 0        # which day track is next
var _count := 0           # local counter for the gaps
var _gap_left := -1.0     # seconds of silence left (-1 = not in a gap)
var _tension_since_clear := -1.0
var _want := ""
var _duck := 0.0
var force := ""           # debug: a fixed state (automation `mus`), "" = from the game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = OFF_DB
		p.finished.connect(_on_finished.bind(i))
		add_child(p)
		_players.append(p)
	_cue = AudioStreamPlayer.new()
	_cue.bus = "Music"
	_cue.finished.connect(func(): _duck_to(0.0))
	add_child(_cue)

func add_track(id: String, stream: AudioStream, db: float) -> void:
	if id == "mus_tension" and "loop" in stream:
		stream.set("loop", true)
	tracks[id] = {"stream": stream, "db": db}

## Called twice a second. `tension_now`: a cause is present now (active hazard not covered,
## a critical alert, a hull breach).
func update(title: bool, night: bool, tension_now: bool, delta: float) -> void:
	if force != "":
		title = force == "title"
		night = force == "night"
		tension_now = force == "tension"
	var s := "title" if title else ("night" if night else "day")
	if not title:
		if tension_now:
			_tension_since_clear = 0.0
		elif _tension_since_clear >= 0.0:
			_tension_since_clear += delta
			if _tension_since_clear >= TENSION_HOLD:
				_tension_since_clear = -1.0
		if _tension_since_clear >= 0.0:
			s = "tension"
	else:
		_tension_since_clear = -1.0
	_want = s
	if s != state:
		state = s
		_gap_left = -1.0
		_start(_next_track(s))
	elif _gap_left >= 0.0:
		_gap_left -= delta
		if _gap_left < 0.0:
			_start(_next_track(s))

func _next_track(s: String) -> String:
	var list: Array = STATE_TRACKS.get(s, [])
	if list.is_empty():
		return ""
	if s == "day":
		var id: String = list[_day_turn % list.size()]
		_day_turn += 1
		return id
	return list[0]

## Crossfade to a track (FADE seconds). "" fades to silence.
func _start(id: String) -> void:
	var old: AudioStreamPlayer = _players[_cur]
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", OFF_DB, FADE)
		tw.tween_callback(old.stop)
	track = ""
	if id == "" or not tracks.has(id):
		return
	_cur = 1 - _cur
	var p: AudioStreamPlayer = _players[_cur]
	var t: Dictionary = tracks[id]
	p.stop()
	p.stream = t["stream"]
	p.volume_db = OFF_DB
	p.play()
	create_tween().tween_property(p, "volume_db", float(t["db"]) + _duck, FADE)
	track = id

func _on_finished(i: int) -> void:
	if i != _cur or track == "":
		return
	# The track ended: a gap of 5..20 s, then the next one (see update()).
	_count += 1
	_gap_left = 5.0 + float((_count * 7) % 16)
	track = ""

## A short cue over the music (a ship lands). The music dips while it plays.
func cue(id: String) -> void:
	if not tracks.has(id) or _cue.playing:
		return
	_cue.stream = tracks[id]["stream"]
	_cue.volume_db = float(tracks[id]["db"])
	_cue.play()
	_duck_to(DUCK_DB)

func _duck_to(db: float) -> void:
	_duck = db
	var p: AudioStreamPlayer = _players[_cur]
	if p.playing and track != "":
		create_tween().tween_property(p, "volume_db", float(tracks[track]["db"]) + db, 1.0)

## For the automation hook and reports.
func describe() -> String:
	var gap := ("gap %.0f s" % _gap_left) if _gap_left >= 0.0 else "no gap"
	var hold := ("tension hold %.0f s" % (TENSION_HOLD - _tension_since_clear)) if _tension_since_clear > 0.0 else ""
	return "state=%s track=%s %s %s tracks=%d" % [state, track if track != "" else "-", gap, hold, tracks.size()]
