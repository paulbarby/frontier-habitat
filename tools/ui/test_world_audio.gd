extends SceneTree
## Test of world sounds, headless (docs/V3_1_DESIGN.md §2.2 and Paul, 2026-09-26: effect sounds
## only when the camera is zoomed in and close).
##   node tools/godot.mjs script res://tools/ui/test_world_audio.gd
## Local sounds: nothing at 110 m zoom (overview) or at 50 m zoom (medium); audible at 15 m zoom
## within 8 m; the zoom and distance ramps; a loop fades out on zoom-out and back in on zoom-in.
## Big events: audible at 110 m zoom, lower than zoomed in. Also the per-name limit, world_stop,
## world_move, max_s, and the arrival cue on ship_touchdown.

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

func zoom(m: float) -> void:
	main.rig.distance = m
	main.rig.target_distance = m

func db_of(h: int) -> float:
	for pl in main.audio._wrec:
		if int(main.audio._wrec[pl]["handle"]) == h:
			return (pl as AudioStreamPlayer).volume_db
	return -999.0

func stop_all() -> void:
	for pl in main.audio._wrec.keys():
		(pl as AudioStreamPlayer).stop()
	main.audio._wrec.clear()

func _process(_d: float) -> bool:
	_n += 1
	if _n < 10:
		return false
	var a = main.audio
	var f: Vector3 = main.rig.focus
	# Ramps
	check("local gain: 1 at zoom 15 and 5 m, 0 at zoom 35, 0 at 25 m", is_equal_approx(a.gain("local", 5.0, 15.0), 1.0) and a.gain("local", 5.0, 35.0) == 0.0 and a.gain("local", 25.0, 15.0) == 0.0,
		"zoom 27.5: %.2f, 16.5 m: %.2f" % [a.gain("local", 5.0, 27.5), a.gain("local", 16.5, 15.0)])
	check("big gain: 1 zoomed in, 0.4 zoomed out, 0 beyond 500 m", is_equal_approx(a.gain("big", 10.0, 20.0), 1.0) and is_equal_approx(a.gain("big", 10.0, 150.0), 0.4) and a.gain("big", 520.0, 20.0) == 0.0)
	# Overview and medium zoom: no local sound, even at the focus.
	for zm in [110.0, 50.0]:
		zoom(zm)
		var any := false
		for nm in ["door_slide", "airlock_seal", "airlock_vent", "ramp", "turret_fire", "ship_touchdown", "ship_takeoff", "construct", "airlock"]:
			if a.world(nm, f + Vector3(2, 0, 0)) > 0:
				any = true
		check("zoom %d m: no local sound starts" % int(zm), not any, str(a.world_count()))
		stop_all()
	# Close zoom
	zoom(15.0)
	var h1: int = a.world("door_slide", f + Vector3(5, 0, 0))
	check("zoom 15 m, 5 m away: a local sound plays at full level", h1 > 0 and absf(db_of(h1) - float(a._world["door_slide"]["db"])) < 0.1, "%.1f dB" % db_of(h1))
	check("zoom 15 m, 30 m away: no local sound", a.world("door_slide", f + Vector3(30, 0, 0)) == -1)
	var h2: int = a.world("door_slide", f + Vector3(16, 0, 0))
	check("zoom 15 m, 16 m away: quieter than at 5 m", h2 > 0 and db_of(h2) < db_of(h1) - 3.0, "%.1f dB" % db_of(h2))
	var h3: int = a.world("door_slide", f + Vector3(20, 0, 0))
	check("3 of one name play; a 4th farther one is refused", h3 > 0 and a.world_count("door_slide") == 3 and a.world("door_slide", f + Vector3(22, 0, 0)) == -1)
	var h4: int = a.world("door_slide", f + Vector3(1, 0, 0))
	check("a 4th nearer one replaces the farthest", h4 > 0 and a.world_count("door_slide") == 3)
	stop_all()
	# A loop fades with the zoom.
	var lp: int = a.world("airlock_pump", f + Vector3(4, 0, 0))
	var near_db: float = db_of(lp)
	zoom(60.0)
	a._process(0.1)
	var far_db: float = db_of(lp)
	zoom(15.0)
	a._process(0.1)
	check("a loop goes silent zoomed out and comes back zoomed in", lp > 0 and far_db <= -79.0 and absf(db_of(lp) - near_db) < 0.1, "near %.1f, zoom 60 %.1f, back %.1f dB" % [near_db, far_db, db_of(lp)])
	a.world_move(lp, f + Vector3(24, 0, 0))
	a._process(0.1)
	check("world_move: a source moving away gets quieter", db_of(lp) < near_db - 10.0, "%.1f dB" % db_of(lp))
	a.world_stop(lp)
	check("world_stop stops a loop", a.world_count("airlock_pump") == 0)
	# Big events at the overview zoom.
	zoom(110.0)
	var mb: int = a.world("meteor_impact", f + Vector3(60, 0, 0))
	var mb_db: float = db_of(mb)
	zoom(15.0)
	a._process(0.1)
	check("zoom 110 m: a meteor impact 60 m away is heard, lower than zoomed in", mb > 0 and mb_db > -40.0 and mb_db < db_of(mb) - 3.0, "110 m zoom %.1f dB, 15 m zoom %.1f dB" % [mb_db, db_of(mb)])
	stop_all()
	zoom(110.0)
	check("zoom 110 m: storm and quake still play", a.world("storm_loop", f) > 0 and a.world("quake_rumble", f + Vector3(100, 0, 0)) > 0)
	stop_all()
	# max_s and the arrival cue
	zoom(15.0)
	var lp2: int = a.world("ship_descent", f)
	a._process(41.0)
	check("a forgotten loop stops after max_s", lp2 > 0 and a.world_count("ship_descent") == 0)
	a.world("ship_touchdown", f)
	check("ship_touchdown starts the arrival cue", a.music._duck < 0.0, "duck %.0f dB" % a.music._duck)
	print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
	return false
