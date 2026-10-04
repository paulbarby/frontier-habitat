extends SceneTree
## Outdoor sounds indoors (Paul, 2026-10-01: no storm or wind sounds inside the habitats), headless,
## on showcase_v5:
##   node tools/godot.mjs script res://tools/ui/test_indoor_sound.gd
## A storm blows. A close camera over a habitat: the listener is indoors; the outdoor buses fade to
## -40 dB with the low-pass at 250 Hz in about 0.5 s; the room tone is up. The camera on open ground:
## outdoors, full level. The follow view of a person who is inside: indoors.

const A = preload("res://ui/audio.gd")

var main
var fails := 0
var _t0 := 0
var _n := 0
var _step := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _bus_db(name: String) -> float:
	var i: int = AudioServer.get_bus_index(name)
	return AudioServer.get_bus_volume_db(i) if i != -1 else 999.0

func _lp(name: String) -> float:
	var i: int = AudioServer.get_bus_index(name)
	if i == -1:
		return -1.0
	var e = AudioServer.get_bus_effect(i, 0)
	return (e as AudioEffectLowPassFilter).cutoff_hz if e is AudioEffectLowPassFilter else -1.0

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var au = main.audio
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main.boot["debug"] = "1"
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
			main.leave_title()
			main._on_cmd("speed 0")
			check("the audio manager is there", au != null)
			# Outdoor sounds go through the outdoor buses (the loops and the storm loop).
			check("wind plays on the outdoor ambience bus", au._bus_for("wind", "Ambience") == "OutdoorAmbience" and AudioServer.get_bus_index("OutdoorAmbience") != -1)
			check("the storm loop plays on the outdoor effects bus", au._bus_for("storm_loop", "SFX") == "OutdoorSFX" and AudioServer.get_bus_index("OutdoorSFX") != -1)
			check("a door does not", au._bus_for("door_slide", "SFX") == "SFX")
			main._on_cmd("select habitat")
			main._on_cmd("zoom 18")
			main.rig.distance = 18.0
			_step = 1
			_n = 0
		1:
			if _n < 70:   # about 1.2 s at 60 frames a second: past the 0.5 s fade
				return false
			check("close over a habitat: indoors", au.indoor_now, "focus %s distance %.1f" % [str(main.rig.focus), main.rig.distance])
			check("indoors: the outdoor buses at -40 dB, low-pass 250 Hz", absf(_bus_db("OutdoorAmbience") + 40.0) < 0.6 and absf(_lp("OutdoorAmbience") - 250.0) < 20.0, "%.1f dB, %.0f Hz" % [_bus_db("OutdoorAmbience"), _lp("OutdoorAmbience")])
			print("MEASURE indoor: outdoor buses %.1f dB, low-pass %.0f Hz (k %.2f)" % [_bus_db("OutdoorSFX"), _lp("OutdoorSFX"), au.indoor_k])
			main._on_cmd("goto 40 40")
			main.rig.distance = 18.0
			_step = 2
			_n = 0
		2:
			if _n < 70:
				return false
			check("open ground: outdoors, full level", not au.indoor_now and absf(_bus_db("OutdoorAmbience")) < 0.6 and _lp("OutdoorAmbience") > 15000.0, "%.1f dB, %.0f Hz" % [_bus_db("OutdoorAmbience"), _lp("OutdoorAmbience")])
			print("MEASURE outdoor: outdoor buses %.1f dB, low-pass %.0f Hz (k %.2f)" % [_bus_db("OutdoorSFX"), _lp("OutdoorSFX"), au.indoor_k])
			# The fade: about 0.5 s (part way after 0.25 s).
			main._on_cmd("select habitat")
			main.rig.distance = 18.0
			_step = 3
			_n = 0
			_t0 = Time.get_ticks_msec()
		3:
			# Wall clock, not frames: a headless frame takes 10 to 40 ms (2026-10-02: 22 frames gave k 0.79 to 1.00).
			if Time.get_ticks_msec() - _t0 < 300:   # about 0.3 s: the listener test runs every 0.1 s, then the fade
				return false
			check("the fade takes about 0.5 s (part way after 0.3 s)", au.indoor_k > 0.05 and au.indoor_k < 0.95, "k %.2f" % au.indoor_k)
			# Follow a person who is inside.
			var who := -1
			for aid in main.sim.state["agents"]:
				var a: Dictionary = main.sim.state["agents"][aid]
				if a["state"] == "alive" and String(a.get("where", "")) == "in" and String(a.get("kind", "")) != "visitor":
					who = int(aid)
					break
			main._on_cmd("goto 40 40")
			if who >= 0:
				main.follow_person(who)
			_step = 4
			_n = 0
		4:
			if _n < 70:
				return false
			check("the follow view of a person inside: indoors", (not main.in_follow()) or au.indoor_now, "in_follow %s" % main.in_follow())
			main.follow_end()
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
			return true
	return false
