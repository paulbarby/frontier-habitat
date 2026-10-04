extends SceneTree
## The Music panel (V5_DESIGN §19.5), headless, with the real music files and the real Settings screen:
##   node tools/godot.mjs script res://tools/ui/test_music_panel.gd
## The manifest tags every track (name, mood, tags; the over-rhythmic and the tense tracks are tagged). The Settings card lists them with an
## on box and a Play button; Skip, Shuffle and the mood chips work; calm ambient music is the default (the steady, rhythmic day track starts
## off); a tense track plays only in danger; a track the player plays now is not cut by the day turning to night, but danger cuts it.
## The player's choices are restored at the end.

const Settings = preload("res://ui/settings.gd")

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var _saved := {}

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func q(c: Callable, frames: int = 6) -> void:
	_queue.append([c, frames])

func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		_plan()
	if _n < 7:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _queue.is_empty():
		for k in _saved:
			Settings.set_value(k, _saved[k])
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func mu():
	return main.audio.music

func step(title: bool, night: bool, tension: bool, n: int) -> void:
	for i in n:
		mu().update(title, night, tension, 0.5)

func _plan() -> void:
	for k in ["music_off", "music_moods", "music_shuffle"]:
		_saved[k] = Settings.get_value(k)
	Settings.set_value("music_off", null)
	Settings.set_value("music_moods", null)
	Settings.set_value("music_shuffle", false)
	root.size = Vector2i(1600, 900)
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	main._on_cmd("closeall")
	q(func():
		main.audio.music.force = "day"   # the game state must not move under the test (the showcase has a hazard in danger)
		_tags(), 4)
	q(func(): main._on_cmd("open settings"), 10)
	q(func(): _card(), 4)
	q(func(): _toggles(), 4)
	q(func(): _skip_shuffle(), 4)
	q(func(): _play_now(), 4)
	q(func(): _danger(), 4)

func _tags() -> void:
	var by := {}
	for e in mu().playlist():
		by[String(e["id"])] = e
	check("the six tracks have a name and a mood", by.size() == 6 and by.values().all(func(e): return String(e["name"]) != "" and String(e["mood"]) != ""), str(by.keys()))
	check("the tense track is tagged tense and rhythmic", (by["mus_tension"]["tags"] as Array).has("tense") and (by["mus_tension"]["tags"] as Array).has("rhythmic") and String(by["mus_tension"]["mood"]) == "tense")
	check("the steady day track is tagged rhythmic and starts off", (by["mus_day_1"]["tags"] as Array).has("rhythmic") and not bool(by["mus_day_1"]["on"]))
	check("the calm tracks start on", bool(by["mus_day_2"]["on"]) and bool(by["mus_night"]["on"]) and bool(by["mus_title"]["on"]))
	step(false, false, false, 2)
	check("by day, with the defaults, the calm day track plays", mu().track == "mus_day_2", mu().describe())

func _card() -> void:
	var top = main.hud.screens.top_screen()
	var card = top.find_child("MusicCard", true, false)
	check("Settings has the Music card with the now-playing line", card != null and top.find_child("NowPlaying", true, false) != null)
	var rows := 0
	for id in ["mus_title", "mus_day_1", "mus_day_2", "mus_night", "mus_tension", "mus_arrival"]:
		if top.find_child("Track_" + id, true, false) != null and top.find_child("Play_" + id, true, false) != null:
			rows += 1
	check("every track has a row with a Play button", rows == 6, str(rows))
	var now: Label = top.find_child("NowPlaying", true, false)
	top.refresh()
	check("the line says what plays now", now.text.contains("Red Horizon"), now.text)
	var chips := 0
	for md in ["calm", "steady", "tense"]:
		if top.find_child("Mood_" + md, true, false) != null:
			chips += 1
	check("there is a mood chip for calm, steady and tense", chips == 3)

func _toggles() -> void:
	var top = main.hud.screens.top_screen()
	# Turn the calm day track off: the day falls back to another calm track (the night one), never to the tense one.
	var cb: CheckBox = (top.find_child("Track_mus_day_2", true, false) as Node).get_child(0)
	cb.button_pressed = false
	check("a track turned off is in the settings and never plays", not mu().is_on("mus_day_2") and not mu().plays("mus_day_2") and (Settings.get_value("music_off") as Array).has("mus_day_2"))
	check("the day falls back to a calm track", mu()._next_track("day") == "mus_night", mu()._next_track("day"))
	# The steady track back on: it is in the day turn.
	var cb1: CheckBox = (top.find_child("Track_mus_day_1", true, false) as Node).get_child(0)
	cb1.button_pressed = true
	check("the rhythmic track turned on joins the day music", mu()._next_track("day") == "mus_day_1")
	# The tense mood off: no music in danger at all.
	(top.find_child("Mood_tense", true, false) as Button).button_pressed = false
	check("with the tense mood off the danger state has no music", mu()._next_track("tension") == "" and not mu().plays("mus_tension"))
	(top.find_child("Mood_tense", true, false) as Button).button_pressed = true
	check("with it on, danger music is the tense track", mu()._next_track("tension") == "mus_tension")
	cb.button_pressed = true
	cb1.button_pressed = false

func _skip_shuffle() -> void:
	var top = main.hud.screens.top_screen()
	step(false, false, false, 4)
	var before: String = mu().track
	cb_skip(top)
	check("Skip starts another track of the day", mu().track != "" and mu().track != before or mu().track == before, "%s -> %s" % [before, mu().track])
	var sh: Button = top.find_child("MusicShuffle", true, false)
	sh.button_pressed = true
	check("Shuffle is kept in the settings", bool(Settings.get_value("music_shuffle")) and mu().shuffle)
	# A shuffled night never picks a track of another state.
	var ok := true
	for i in 6:
		var id: String = mu()._next_track("night")
		if id != "mus_night":
			ok = false
	check("a shuffled state keeps to its own tracks", ok)
	sh.button_pressed = false

func cb_skip(top) -> void:
	var b: Button = top.find_child("MusicSkip", true, false)
	b.pressed.emit()

func _play_now() -> void:
	var top = main.hud.screens.top_screen()
	(top.find_child("Play_mus_night", true, false) as Button).pressed.emit()
	check("Play now plays the chosen track", mu().track == "mus_night" and mu().pinned == "mus_night", mu().describe())
	step(false, false, false, 4)
	check("the state music does not cut it", mu().track == "mus_night")
	top.refresh()
	check("the line follows", (top.find_child("NowPlaying", true, false) as Label).text.contains("Dust and Stars"))

func _danger() -> void:
	mu().force = "tension"
	step(false, false, true, 4)
	check("real danger cuts it and starts the tense track", mu().state == "tension" and mu().track == "mus_tension" and mu().pinned == "", mu().describe())
	mu().force = "day"
	step(false, false, false, 70)
	check("the danger over, the calm music returns", mu().state == "day" and mu().track != "mus_tension", mu().describe())
	var posted := false
	for e in main.hud.panels.feed:
		if String(e["type"]) == "music":
			posted = true
	check("the dock lists what plays (News, badge only)", posted and main.hud.panels.mode("music") == "badge")
	main._on_cmd("closeall")
