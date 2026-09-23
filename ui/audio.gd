extends Node
## Audio manager: buses Master, Music, SFX, UI and Ambience, a small player pool, and the
## sound list in res://assets/audio/manifest.json:
##   {"sounds": {"click": {"file": "ui_click.ogg", "bus": "UI", "db": -4}, ...},
##    "loops": {"wind": {"file": "amb_wind.ogg", "bus": "Ambience", "db": -10}, ...}}
## Every call is safe with no manifest and no files: the game is then silent.

const Settings = preload("res://ui/settings.gd")
const MANIFEST := "res://assets/audio/manifest.json"
const BUSES := ["Music", "SFX", "UI", "Ambience"]
## Interface events that share one sound when the manifest has no entry of their own.
const FALLBACK := {"hover": "", "tick": "click", "select": "click", "open": "click", "close": "click", "place": "confirm",
	"toast": "", "alert_warning": "alert_warning", "alert_critical": "alert_critical", "construct": "construct",
	"chapter": "award", "error": "error"}

var _sounds := {}      # name -> {stream, bus, db}
var _loops := {}       # name -> {stream, bus, db}
var _pool: Array = []
var _loop_players := {}
var _last := {}        # name -> msec (no machine-gun repeats)
var _loop_on := {}     # loop name -> on

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_load_manifest()
	apply_volumes()

func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	for key in ["sounds", "loops"]:
		var table: Dictionary = d.get(key, {})
		for name in table:
			var e: Dictionary = table[name]
			var path: String = "res://assets/audio/" + String(e.get("file", ""))
			if not ResourceLoader.exists(path):
				continue
			var st = load(path)
			if st == null or not (st is AudioStream):
				continue
			var rec := {"stream": st, "bus": String(e.get("bus", "SFX")), "db": float(e.get("db", 0.0))}
			if key == "loops" and "loop" in st:
				st.set("loop", true)
			if key == "loops":
				_loops[name] = rec
			else:
				_sounds[name] = rec

func has_sounds() -> bool:
	return not _sounds.is_empty() or not _loops.is_empty()

func apply_volumes() -> void:
	_set_bus("Master", float(Settings.get_value("vol_master")))
	_set_bus("Music", float(Settings.get_value("vol_music")))
	_set_bus("SFX", float(Settings.get_value("vol_sfx")))
	_set_bus("UI", float(Settings.get_value("vol_ui")))
	_set_bus("Ambience", float(Settings.get_value("vol_ambience")))

func _set_bus(name: String, v: float) -> void:
	var i: int = AudioServer.get_bus_index(name)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))

## Interface and game sounds by event name. Unknown names are silent.
func play_ui(name: String) -> void:
	var rec: Dictionary = _sounds.get(name, {})
	if rec.is_empty() and FALLBACK.has(name) and String(FALLBACK[name]) != "":
		rec = _sounds.get(String(FALLBACK[name]), {})
	if rec.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_last.get(name, -1000)) < 60:
		return
	_last[name] = now
	for p in _pool:
		var pl: AudioStreamPlayer = p
		if not pl.playing:
			pl.stream = rec["stream"]
			pl.bus = rec["bus"]
			pl.volume_db = rec["db"]
			pl.pitch_scale = 1.0
			pl.play()
			return

## Looping ambience: start or stop one loop by name (with a short fade).
func loop(name: String, on: bool) -> void:
	var rec: Dictionary = _loops.get(name, {})
	if rec.is_empty() or bool(_loop_on.get(name, false)) == on:
		return
	_loop_on[name] = on
	var p: AudioStreamPlayer = _loop_players.get(name)
	if p == null:
		p = AudioStreamPlayer.new()
		p.stream = rec["stream"]
		p.bus = rec["bus"]
		p.volume_db = -60.0
		add_child(p)
		_loop_players[name] = p
	var tw := create_tween()
	if on:
		if not p.playing:
			p.play()
		tw.tween_property(p, "volume_db", float(rec["db"]), 1.5)
	else:
		tw.tween_property(p, "volume_db", -60.0, 1.5)
		tw.tween_callback(p.stop)

## Day, dusk and night ambience follow the simulation clock.
func ambience(night: bool, inside_title: bool) -> void:
	loop("wind", true)
	loop("hum", not inside_title)
	loop("night", night)
