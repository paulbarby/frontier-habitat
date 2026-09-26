extends Node
## Audio manager: buses Master, Music, SFX, UI and Ambience (default_bus_layout.tres), a small
## player pool, the music director (ui/music.gd), world sounds, and the sound list in
## res://assets/audio/manifest.json:
##   {"sounds": {"click": {"file": "click.mp3", "bus": "UI", "db": -8}, ...},
##    "loops":  {"wind": {"file": "amb_wind.mp3", "bus": "Ambience", "db": -14}, ...},
##    "music":  {"mus_day_1": {"file": "mus_day_1.mp3", "db": -6}, ...},
##    "world":  {"door_slide": {"file": "door_slide.mp3", "db": -8, "loop": false, "max_s": 0}, ...}}
## Every call is safe with no manifest and no files: the game is then silent.
##
## Web: the export uses Stream playback (project.godot audio/general/default_playback_type.web=0),
## so the engine mixes and bus volumes and fades reach the speakers (V3_1_DESIGN §1).
##
## World sounds (V3_1_DESIGN §2.2): world(name, pos) plays a sound at a place in the world.
## Level = zoom factor x distance factor (Paul, 2026-09-26: "only when the camera is zoomed in and
## close"), by the sound's "class" in the manifest; the numbers are the manifest's "world_rules":
## - local (default: doors, airlock, machines, construction, ramp, turret, ship landing):
##   zoom (camera distance to its focus) full at <= 20 m, silent at >= 35 m; source full within 8 m
##   of the focus, silent at 25 m. At the overview (about 110 m) and medium zoom: nothing.
## - big (meteor impact, quake rumble, storm loop): audible at every zoom: full within 40 m of the
##   focus, silent beyond 500 m; zoomed out (150 m and more) at 0.4 of the level.
## Levels follow the camera every frame: a loop fades out as you zoom out and back in as you zoom
## in. A one-shot that would be silent does not start. At most PER_NAME of one name play at a
## time (the farthest is replaced by a nearer one). A loop (manifest "loop": true) plays until
## world_stop(handle); "max_s" stops a forgotten loop. world_move(handle, pos) follows a source.

const Settings = preload("res://ui/settings.gd")
const Music = preload("res://ui/music.gd")
const MANIFEST := "res://assets/audio/manifest.json"
const BUSES := ["Music", "SFX", "UI", "Ambience"]
## Interface events that share one sound when the manifest has no entry of their own.
const FALLBACK := {"hover": "", "tick": "click", "select": "click", "open": "click", "close": "click", "place": "confirm",
	"toast": "", "alert_warning": "alert_warning", "alert_critical": "alert_critical", "construct": "construct",
	"chapter": "award", "error": "error"}
## Defaults of the manifest's "world_rules" (metres; "far_gain" = level when zoomed far out).
const RULES := {
	"local": {"zoom_full": 20.0, "zoom_off": 35.0, "near_full": 8.0, "near_off": 25.0},
	"big": {"zoom_full": 35.0, "zoom_far": 150.0, "far_gain": 0.4, "near_full": 40.0, "near_off": 500.0},
}
const PER_NAME := 3
const WORLD_POOL := 14
const LOOP_MAX_S := 60.0

var main                # presentation/main.gd (camera focus and zoom for world sounds)
var rules := RULES.duplicate(true)
var music
var _sounds := {}      # name -> {stream, bus, db}
var _loops := {}       # name -> {stream, bus, db}
var _world := {}       # name -> {stream, bus, db, loop, max_s}
var _pool: Array = []
var _loop_players := {}
var _last := {}        # name -> msec (no machine-gun repeats)
var _loop_on := {}     # loop name -> on
var _wpool: Array = [] # world players
var _wrec := {}        # player -> {name, pos, db, handle, t}
var _handle := 0
var played := {}       # world sound name -> times it started (tests, the `music` command)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# default_bus_layout.tres defines the buses; this only covers a project without it.
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
	for i in WORLD_POOL:
		var w := AudioStreamPlayer.new()
		w.bus = "SFX"
		w.finished.connect(func(): _wrec.erase(w))
		add_child(w)
		_wpool.append(w)
	music = Music.new()
	add_child(music)
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
	var wr = d.get("world_rules", {})
	if typeof(wr) == TYPE_DICTIONARY:
		for cls in wr:
			if typeof(wr[cls]) == TYPE_DICTIONARY:
				var base: Dictionary = rules.get(cls, {}).duplicate()
				for k in wr[cls]:
					base[k] = float(wr[cls][k])
				rules[cls] = base
	for key in ["sounds", "loops", "music", "world"]:
		var table: Dictionary = d.get(key, {})
		for name in table:
			var e: Dictionary = table[name]
			var path: String = "res://assets/audio/" + String(e.get("file", ""))
			if not ResourceLoader.exists(path):
				continue
			var st = load(path)
			if st == null or not (st is AudioStream):
				continue
			var db: float = float(e.get("db", 0.0))
			var rec := {"stream": st, "bus": String(e.get("bus", "SFX")), "db": db}
			match key:
				"loops":
					if "loop" in st:
						st.set("loop", true)
					_loops[name] = rec
				"music":
					music.add_track(String(name), st, db)
				"world":
					var lp: bool = bool(e.get("loop", false))
					if lp and "loop" in st:
						st = st.duplicate()
						st.set("loop", true)
						rec["stream"] = st
					rec["loop"] = lp
					rec["max_s"] = float(e.get("max_s", LOOP_MAX_S if lp else 0.0))
					rec["class"] = String(e.get("class", "local"))
					_world[name] = rec
				_:
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

# ---------------------------------------------------------------- world sounds (V3_1 §2.2)
func _focus() -> Vector3:
	if main != null and main.rig != null:
		return main.rig.focus
	return Vector3.ZERO

func _zoom() -> float:
	if main != null and main.rig != null:
		return float(main.rig.distance)
	return 0.0

## 1 at or below `full`, 0 at or above `off`, linear between.
static func ramp(v: float, full: float, off: float) -> float:
	if v <= full:
		return 1.0
	if v >= off:
		return 0.0
	return 1.0 - (v - full) / (off - full)

## Linear level 0..1 of a world sound of class `cls`, `d` m from the camera focus, camera `zoom` m
## from its focus (the rules above).
func gain(cls: String, d: float, zoom: float) -> float:
	var r: Dictionary = rules.get(cls, rules["local"])
	if cls == "big":
		var zf: float = lerpf(float(r["far_gain"]), 1.0, ramp(zoom, float(r["zoom_full"]), float(r["zoom_far"])))
		return zf * ramp(d, float(r["near_full"]), float(r["near_off"]))
	return ramp(zoom, float(r["zoom_full"]), float(r["zoom_off"])) * ramp(d, float(r["near_full"]), float(r["near_off"]))

static func gain_db(g: float) -> float:
	return linear_to_db(g) if g > 0.0001 else -80.0

## Plays sound `name` at `pos` (world metres, Vector3; a Vector2 content point also works).
## Returns a handle for world_stop / world_move, or -1 when it does not play (unknown name,
## a one-shot that would be silent at this zoom and distance, or PER_NAME nearer ones already play).
func world(name: String, pos) -> int:
	var rec: Dictionary = _world.get(name, _sounds.get(name, {}))
	if rec.is_empty():
		return -1
	if name == "ship_touchdown" and music != null:
		music.cue("mus_arrival")   # V3_1 §6.3: the arrival cue plays with the touchdown
	var p3: Vector3 = _to3(pos)
	var d: float = p3.distance_to(_focus())
	var cls: String = String(rec.get("class", "local"))
	var g: float = gain(cls, d, _zoom())
	if g <= 0.0001 and not bool(rec.get("loop", false)):
		return -1
	# At most PER_NAME of one name: replace the farthest when this one is nearer.
	var same: Array = []
	for pl in _wrec:
		if String(_wrec[pl]["name"]) == name:
			same.append(pl)
	if same.size() >= PER_NAME:
		var far_pl = null
		var far_d := -1.0
		for pl in same:
			var dd: float = (_wrec[pl]["pos"] as Vector3).distance_to(_focus())
			if dd > far_d:
				far_d = dd
				far_pl = pl
		if far_d <= d:
			return -1
		(far_pl as AudioStreamPlayer).stop()
		_wrec.erase(far_pl)
	var free: AudioStreamPlayer = null
	for pl in _wpool:
		if not _wrec.has(pl):
			free = pl
			break
	if free == null:
		return -1
	_handle += 1
	free.stream = rec["stream"]
	free.bus = String(rec.get("bus", "SFX"))
	free.volume_db = float(rec["db"]) + gain_db(g)
	free.pitch_scale = 1.0
	free.play()
	played[name] = int(played.get(name, 0)) + 1
	_wrec[free] = {"name": name, "pos": p3, "db": float(rec["db"]), "handle": _handle, "t": 0.0, "max_s": float(rec.get("max_s", 0.0)), "class": cls}
	return _handle

func world_stop(handle: int) -> void:
	for pl in _wrec.keys():
		if int(_wrec[pl]["handle"]) == handle:
			(pl as AudioStreamPlayer).stop()
			_wrec.erase(pl)

func world_move(handle: int, pos) -> void:
	for pl in _wrec:
		if int(_wrec[pl]["handle"]) == handle:
			_wrec[pl]["pos"] = _to3(pos)

func world_count(name: String = "") -> int:
	var n := 0
	for pl in _wrec:
		if name == "" or String(_wrec[pl]["name"]) == name:
			n += 1
	return n

func _to3(pos) -> Vector3:
	if typeof(pos) == TYPE_VECTOR3:
		return pos
	if typeof(pos) == TYPE_VECTOR2:
		if main != null and main.view != null:
			return main.view.to3(pos)
		return Vector3(pos.x, 0.0, pos.y)
	return _focus()

func _process(delta: float) -> void:
	if _wrec.is_empty():
		return
	# The camera moves and zooms: levels follow it. Loops past max_s stop.
	var f: Vector3 = _focus()
	var z: float = _zoom()
	for pl in _wrec.keys():
		var r: Dictionary = _wrec[pl]
		r["t"] = float(r["t"]) + delta
		if float(r["max_s"]) > 0.0 and float(r["t"]) > float(r["max_s"]):
			(pl as AudioStreamPlayer).stop()
			_wrec.erase(pl)
			continue
		(pl as AudioStreamPlayer).volume_db = float(r["db"]) + gain_db(gain(String(r["class"]), (r["pos"] as Vector3).distance_to(f), z))

## One line for the automation hook: music state and world sounds playing.
func describe() -> String:
	return "%s world=%d played=%s" % [music.describe() if music != null else "no music", world_count(), str(played)]
