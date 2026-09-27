extends SceneTree
## New colony map choice (SIM request 2026-09-27: "frontier" is the default of the new-game screen;
## "tutorial" stays as the first-landing option), headless:
##   node tools/godot.mjs script res://tools/ui/test_newcolony_map.gd

var main
var fails := 0
var _n := 0
var _step := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _yes() -> void:
	var top = main.hud.screens.top_screen()
	var a: Dictionary = top.arg
	main.hud.screens.close(top)
	(a["on_yes"] as Callable).call()

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	match _step:
		0:
			main._on_cmd("newgame")
			main._on_cmd("open newcolony")
			var sc = main.hud.screens.top_screen()
			check("the new-colony screen defaults to the Frontier map", sc != null and sc._scenario == "frontier" and sc._scen_btns["frontier"].button_pressed, str(sc._scenario) if sc != null else "-")
			sc._seed.text = "4242"
			sc._start()
			_yes()
			_step = 1
			_n = 0
		1:
			check("Land the colony on Frontier makes the 2,560 m planet", int(main.sim.world.size) == 2560, "size %s" % str(main.sim.world.size))
			main._on_cmd("open newcolony")
			var sc2 = main.hud.screens.top_screen()
			sc2._pick_scenario("tutorial")
			sc2._seed.text = "4242"
			sc2._start()
			_yes()
			_step = 2
			_n = 0
		2:
			check("First landing makes the 810 m map", int(main.sim.world.size) == 810, "size %s" % str(main.sim.world.size))
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
