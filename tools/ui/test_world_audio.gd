extends SceneTree
## Test of world sounds (docs/V3_1_DESIGN.md §2.2): audio.world(name, pos), headless.
##   node tools/godot.mjs script res://tools/ui/test_world_audio.gd
## Checks: plays near the camera focus, silent (refused) beyond 120 m, at most 3 of one name
## (a nearer one replaces the farthest), fall-off levels, loops stop by world_stop and max_s,
## world_move, and ship_touchdown starts the arrival cue.

var main
var fails := 0
var _n := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _process(_d: float) -> bool:
	_n += 1
	if _n < 10:
		return false
	var a = main.audio
	var f: Vector3 = main.rig.focus
	check("falloff: 0 dB within 12 m, silent at 120 m", is_equal_approx(a.falloff_db(5.0), 0.0) and a.falloff_db(120.0) <= -80.0 and a.falloff_db(60.0) < -3.0,
		"60 m = %.1f dB" % a.falloff_db(60.0))
	var h1: int = a.world("door_slide", f + Vector3(5, 0, 0))
	check("a sound near the focus plays", h1 > 0, str(h1))
	check("a sound 130 m away is refused", a.world("door_slide", f + Vector3(130, 0, 0)) == -1)
	var h2: int = a.world("door_slide", f + Vector3(40, 0, 0))
	var h3: int = a.world("door_slide", f + Vector3(80, 0, 0))
	check("3 of one name play", h2 > 0 and h3 > 0 and a.world_count("door_slide") == 3, str(a.world_count("door_slide")))
	check("a 4th farther one is refused", a.world("door_slide", f + Vector3(100, 0, 0)) == -1 and a.world_count("door_slide") == 3)
	var h4: int = a.world("door_slide", f + Vector3(2, 0, 0))
	check("a 4th nearer one replaces the farthest", h4 > 0 and a.world_count("door_slide") == 3, str(a.world_count("door_slide")))
	check("another name is not limited by door_slide", a.world("airlock_seal", f) > 0)
	var lp: int = a.world("airlock_pump", f + Vector3(10, 0, 0))
	check("a loop plays", lp > 0 and a.world_count("airlock_pump") == 1)
	a.world_move(lp, f + Vector3(90, 0, 0))
	a._process(0.1)
	var db := 0.0
	for pl in a._wrec:
		if int(a._wrec[pl]["handle"]) == lp:
			db = (pl as AudioStreamPlayer).volume_db
	check("world_move lowers the level of a moving source", db < -12.0 - 6.0, "%.1f dB" % db)
	a.world_stop(lp)
	check("world_stop stops a loop", a.world_count("airlock_pump") == 0)
	var lp2: int = a.world("ship_descent", f)
	a._process(41.0)
	check("a forgotten loop stops after max_s", lp2 > 0 and a.world_count("ship_descent") == 0)
	a.world("ship_touchdown", f)
	check("ship_touchdown starts the arrival cue", a.music._cue.stream != null and a.music._duck < 0.0, "duck %.0f dB" % a.music._duck)
	print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
	return false
