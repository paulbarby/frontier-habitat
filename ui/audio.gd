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
	# Paul 2026-09-27: door sounds only right up close. One door sound at a time; the same door not
	# again within "repeat_s".
	"door": {"zoom_full": 10.0, "zoom_off": 18.0, "near_full": 3.0, "near_off": 8.0, "max_at_once": 1.0, "repeat_s": 1.5},
}
const PER_NAME := 3
## Indoors (Paul, 2026-10-01: no storm or wind sounds inside the habitats, above all over the shoulder).
## Outdoor sounds play through their own buses (a copy of Ambience and of SFX, each with a low-pass
## filter). While the listener is inside a room, a corridor or the dome (the follow view of a person who
## is inside, or a close camera over one), those buses go down to INDOOR_DB with the filter at
## INDOOR_LP_HZ (a faint hull creak at most; V5 section 19.9: -40 dB, measured with tools/audio_probe.mjs: -24 dB gave an atmosphere 22 dB under the outdoor
## level, -40 dB gives 38 dB under it), and the room tone ("hum") carries the sound; both fade over about FADE_S.
const OUTDOOR_LOOPS := ["wind", "night"]
const OUTDOOR_WORLD := ["storm_loop"]
const OUTDOOR_BUS := {"Ambience": "OutdoorAmbience", "SFX": "OutdoorSFX"}
const INDOOR_DB := -40.0
const INDOOR_LP_HZ := 250.0
const ROOM_TONE_DB := 6.0     # the hum, indoors, louder by this
const FADE_S := 0.5
const CLOSE_M := 32.0          # a camera closer than this to its focus listens at the focus
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
var _door_last := {}   # door key (name + position to 0.5 m) -> msec of its last sound
var indoor_k := 0.0    # 0 outdoors .. 1 indoors, faded (tests, audio_probe)
var indoor_now := false
var _indoor_t := 0.0

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
					music.add_track(String(name), st, db, e)
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
		p.bus = _bus_for(name, String(rec["bus"]))
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
	if cls == "door":
		# At most max_at_once door sounds at a time, and one door not again within repeat_s.
		var r: Dictionary = rules["door"]
		var now: int = Time.get_ticks_msec()
		var key: String = "%s@%d,%d,%d" % [name, int(roundf(p3.x * 2.0)), int(roundf(p3.y * 2.0)), int(roundf(p3.z * 2.0))]
		if now - int(_door_last.get(key, -100000)) < int(float(r.get("repeat_s", 1.5)) * 1000.0):
			return -1
		var doors := 0
		for pl in _wrec:
			if String(_wrec[pl].get("class", "")) == "door":
				doors += 1
		if doors >= int(r.get("max_at_once", 1.0)):
			return -1
		_door_last[key] = now
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
	free.bus = _bus_for(name, String(rec.get("bus", "SFX")))
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
	_indoor_step(delta)
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

# ---------------------------------------------------------------- indoors (Paul, 2026-10-01)
## The bus an outdoor sound plays on (its base bus for the others).
func _bus_for(name: String, base: String) -> String:
	if (OUTDOOR_LOOPS.has(name) or OUTDOOR_WORLD.has(name)) and OUTDOOR_BUS.has(base):
		_ensure_outdoor_buses()
		return String(OUTDOOR_BUS[base])
	return base

func _ensure_outdoor_buses() -> void:
	for base in OUTDOOR_BUS:
		var nm: String = OUTDOOR_BUS[base]
		if AudioServer.get_bus_index(nm) != -1 or AudioServer.get_bus_index(base) == -1:
			continue
		AudioServer.add_bus()
		var i: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nm)
		AudioServer.set_bus_send(i, base)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(i, lp)

## True while the listener is indoors: following a person who is inside, or a close camera whose focus
## lies in a room with air, a corridor or the dome.
func listener_indoors() -> bool:
	if main == null or main.sim == null or main.rig == null:
		return false
	var s = main.sim
	if main.has_method("in_follow") and main.in_follow():
		var fid: int = int(main.view.get("follow_id")) if main.view.get("follow_id") != null else -1
		var a: Dictionary = s.state["agents"].get(fid, {})
		return not a.is_empty() and String(a.get("where", "")) == "in"
	if float(main.rig.distance) > CLOSE_M:
		return false
	var f: Vector3 = main.rig.focus
	var p := Vector2(f.x, f.z)
	if s.get("orders") != null and s.orders.has_method("room_at") and s.orders.room_at(p) != -1:
		return true
	# A corridor: the segment between the two structures it joins, about 2 m either side.
	for id in s.state["buildings"]:
		var l: Dictionary = s.state["buildings"][id]
		if String(l.get("kind", "")) != "link" or l["state"] != "active":
			continue
		var a2: Dictionary = s.state["buildings"].get(l.get("a", -1), {})
		var b2: Dictionary = s.state["buildings"].get(l.get("b", -1), {})
		if a2.is_empty() or b2.is_empty():
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, a2["pos"], b2["pos"])
		if q.distance_to(p) < 2.0:
			return true
	return false

## Each frame: the indoor factor fades toward its target (about FADE_S), the outdoor buses and the room
## tone follow it. The test runs ten times a second.
func _indoor_step(delta: float) -> void:
	_indoor_t += delta
	if _indoor_t >= 0.1:
		_indoor_t = 0.0
		indoor_now = listener_indoors()
	var target: float = 1.0 if indoor_now else 0.0
	if is_equal_approx(indoor_k, target) and indoor_k in [0.0, 1.0]:
		return
	indoor_k = move_toward(indoor_k, target, delta / FADE_S)
	for base in OUTDOOR_BUS:
		var i: int = AudioServer.get_bus_index(String(OUTDOOR_BUS[base]))
		if i == -1:
			continue
		AudioServer.set_bus_volume_db(i, INDOOR_DB * indoor_k)
		var lp = AudioServer.get_bus_effect(i, 0)
		if lp is AudioEffectLowPassFilter:
			(lp as AudioEffectLowPassFilter).cutoff_hz = exp(lerpf(log(20000.0), log(INDOOR_LP_HZ), indoor_k))
	var hum: AudioStreamPlayer = _loop_players.get("hum")
	if hum != null and bool(_loop_on.get("hum", false)) and _loops.has("hum"):
		hum.volume_db = float(_loops["hum"]["db"]) + ROOM_TONE_DB * indoor_k

## One line for the automation hook: music state and world sounds playing.
func describe() -> String:
	return "%s world=%d played=%s indoor=%.2f" % [music.describe() if music != null else "no music", world_count(), str(played), indoor_k]
