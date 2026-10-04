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
## Tracks: the "music" table of res://assets/audio/manifest.json {id: {file, db, name, mood, tags, states, default_on}}.
## Music panel (Settings, V5 section 19.5): each track has a name, a mood (calm | steady | tense | event) and tags (rhythmic, tense). The player
## turns tracks off (Settings music_off), picks the moods that may play (music_moods), shuffles, skips, or plays one now. Calm music plays by
## day and by night; a tense track plays only while there is real danger (state "tension"); a track that is off or whose mood is off never plays.
## Silent and safe when a file is missing.

const Settings = preload("res://ui/settings.gd")
const FADE := 4.0
const TENSION_HOLD := 30.0
const DUCK_DB := -10.0
const OFF_DB := -60.0
const STATE_TRACKS := {"title": ["mus_title"], "day": ["mus_day_1", "mus_day_2"], "night": ["mus_night"], "tension": ["mus_tension"]}

var tracks := {}          # id -> {stream, db, name, mood, tags, states, default_on}
var shuffle := false      # Settings music_shuffle: a random track of the state, not the next one
var pinned := ""          # a track the player chose to play now: it plays to its end, then the state music goes on
signal track_changed(id: String)
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
	shuffle = bool(Settings.get_value("music_shuffle"))
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

func add_track(id: String, stream: AudioStream, db: float, meta: Dictionary = {}) -> void:
	if id == "mus_tension" and "loop" in stream:
		stream.set("loop", true)
	tracks[id] = {"stream": stream, "db": db, "name": String(meta.get("name", id)), "mood": String(meta.get("mood", "tense" if id == "mus_tension" else "calm")), "tags": meta.get("tags", []),
		"states": meta.get("states", _states_of(id)), "default_on": bool(meta.get("default_on", true))}

func _states_of(id: String) -> Array:
	var out: Array = []
	for s in STATE_TRACKS:
		if (STATE_TRACKS[s] as Array).has(id):
			out.append(s)
	return out

# ---------------------------------------------------------------- the Music panel (Settings)
const MOODS := ["calm", "steady", "tense"]

## The playlist for the panel: [{id, name, mood, tags, states, on (the player's choice), plays (on and its mood is allowed), seconds}].
func playlist() -> Array:
	var out: Array = []
	var ids: Array = tracks.keys()
	ids.sort_custom(func(a, b): return _order(a) < _order(b))
	for id in ids:
		var t: Dictionary = tracks[id]
		out.append({"id": id, "name": String(t["name"]), "mood": String(t["mood"]), "tags": t["tags"], "states": t["states"], "on": is_on(id), "plays": plays(id),
			"seconds": float((t["stream"] as AudioStream).get_length()) if t["stream"] != null else 0.0})
	return out

func _order(id: String) -> int:
	return ["mus_title", "mus_day_1", "mus_day_2", "mus_night", "mus_tension", "mus_arrival"].find(id)

## The player's choice for a track: off list in the settings, else the track's default.
func is_on(id: String) -> bool:
	var off = Settings.get_value("music_off")
	if typeof(off) == TYPE_ARRAY:
		return not (off as Array).has(id)
	return bool(tracks.get(id, {}).get("default_on", true))

func set_on(id: String, on: bool) -> void:
	var off: Array = []
	for t in tracks:
		if not is_on(String(t)):
			off.append(String(t))
	off.erase(id)
	if not on:
		off.append(id)
	Settings.set_value("music_off", off)
	if not on and track == id:
		skip()

func mood_allowed(mood: String) -> bool:
	var m = Settings.get_value("music_moods")
	return not (typeof(m) == TYPE_ARRAY) or (m as Array).has(mood) or mood == "event"

func set_mood_allowed(mood: String, on: bool) -> void:
	var m: Array = (Settings.get_value("music_moods") as Array).duplicate() if typeof(Settings.get_value("music_moods")) == TYPE_ARRAY else MOODS.duplicate()
	m.erase(mood)
	if on:
		m.append(mood)
	Settings.set_value("music_moods", m)
	if track != "" and not plays(track):
		skip()

## True when the track may play now: it is on, its mood is allowed, and (the title music aside) it is not a cue.
func plays(id: String) -> bool:
	return tracks.has(id) and is_on(id) and mood_allowed(String(tracks[id]["mood"]))

func set_shuffle(on: bool) -> void:
	shuffle = on
	Settings.set_value("music_shuffle", on)

## The line for the panel: {id, name, mood, tags, state, gap (seconds of silence left, -1 = none)}.
func now_playing() -> Dictionary:
	if track == "":
		return {"id": "", "name": "", "mood": "", "tags": [], "state": state, "gap": _gap_left}
	var t: Dictionary = tracks[track]
	return {"id": track, "name": String(t["name"]), "mood": String(t["mood"]), "tags": t["tags"], "state": state, "gap": -1.0}

## Skip: the next track of the state now (also out of a gap).
func skip() -> void:
	pinned = ""
	_gap_left = -1.0
	_start(_next_track(state))

## Play a track now (the player's choice from the list); it plays to its end, then the music of the state goes on.
func play_now(id: String) -> void:
	if not tracks.has(id):
		return
	pinned = id
	_gap_left = -1.0
	_start(id)

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
		if pinned != "" and s != "tension":
			return   # a track the player chose plays to its end; real danger interrupts it
		pinned = ""
		_gap_left = -1.0
		_start(_next_track(s))
	elif _gap_left >= 0.0:
		_gap_left -= delta
		if _gap_left < 0.0:
			_start(_next_track(s))

## The next track of a state: the tracks of that state that may play (on, mood allowed), in turn or shuffled. Day and night fall back to
## any calm track when the player turned the state's own tracks off; the tension state has no fallback (tense music only in danger).
func _next_track(s: String) -> String:
	var list: Array = []
	for id in tracks:
		if (tracks[id]["states"] as Array).has(s) and plays(String(id)):
			list.append(String(id))
	list.sort_custom(func(a, b): return _order(a) < _order(b))
	if list.is_empty() and (s == "day" or s == "night"):
		for id in tracks:
			if (tracks[id]["mood"] == "calm") and not (tracks[id]["states"] as Array).has("title") and plays(String(id)):
				list.append(String(id))
		list.sort_custom(func(a, b): return _order(a) < _order(b))
	if list.is_empty():
		return ""
	if shuffle and list.size() > 1:
		_count += 1
		var pick: String = list[(_count * 2654435761 >> 5) % list.size()]
		if pick == track:
			pick = list[(list.find(pick) + 1) % list.size()]
		return pick
	if s == "day" or list.size() > 1:
		var id2: String = list[_day_turn % list.size()]
		_day_turn += 1
		return id2
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
	track_changed.emit(id)

func _on_finished(i: int) -> void:
	if i != _cur or track == "":
		return
	pinned = ""
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
