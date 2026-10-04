extends SceneTree
## Watch mode (V5_DESIGN §19.6), headless, on showcase_v5, real key and mouse events:
##   node tools/godot.mjs script res://tools/ui/test_watch.gd
## F2 starts it (RENDER's director follows a person over the shoulder, the HUD is hidden, RENDER draws a caption); a log event with people (a fight) takes it to them;
## a key, a mouse button or a long mouse move ends it (RENDER) and the HUD comes back; F2 ends it too; the menu entry and the title button start it.
## The director itself is RENDER's (presentation/fx_watch.gd).

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var first := -1

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
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func key(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)

func hud_():
	return main.hud

func _plan() -> void:
	Input.use_accumulated_input = false
	root.size = Vector2i(1600, 900)
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	main._on_cmd("closeall")
	q(func(): key(KEY_F2), 40)
	q(func(): _started(), 4)
	q(func(): _event(), 90)
	q(func(): _event_check(), 4)
	q(func(): key(KEY_F2), 40)
	q(func(): check("F2 ends it and the HUD is back", not hud_().watch.active and hud_().hud_root.visible and not main.view.watch_state()["active"]), 4)
	q(func(): key(KEY_F2), 40)
	q(func(): key(KEY_X), 40)
	q(func(): check("a key ends it (RENDER) and the HUD is back", not hud_().watch.active and hud_().hud_root.visible and not main.view.watch_state()["active"]), 4)
	q(func(): key(KEY_F2), 40)
	q(func(): _click(), 40)
	q(func(): check("a mouse click ends it", not hud_().watch.active and hud_().hud_root.visible), 4)
	q(func(): key(KEY_F2), 40)
	q(func(): _moves(), 40)
	q(func(): check("a long mouse move ends it", not hud_().watch.active and hud_().hud_root.visible), 4)
	q(func(): _menu(), 12)
	q(func(): _menu_check(), 4)
	q(func(): _title(), 20)
	q(func(): _title_check(), 4)

func _started() -> void:
	var w = hud_().watch
	var st: Dictionary = main.view.watch_state()
	check("F2 starts Watch mode (RENDER's director) over the shoulder", w.active and bool(st["active"]) and main.in_follow())
	check("the HUD is hidden", not hud_().hud_root.visible)
	check("a caption names who and what", w.caption() != "", w.caption())

func _event() -> void:
	var sim = main.sim
	var ids: Array = []
	for r in hud_().v5.people():
		if String(r["kind"]) == "colonist" and int(r["id"]) != int(main.view.watch_state()["id"]):
			ids.append(int(r["id"]))
	set_meta("fa", ids[0])
	set_meta("fb", ids[1])
	sim.state["log"].append({"tick": int(sim.state["tick"]), "code": "fight", "text": "A fight.", "ents": [ids[0], ids[1]], "sev": 2})

func _event_check() -> void:
	var st: Dictionary = main.view.watch_state()
	check("a fight takes it to the people (RENDER jumps to an event)", [int(get_meta("fa")), int(get_meta("fb"))].has(int(st["id"])) or String(st["caption"]).contains("fight"), str(st))

func _click() -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = true
	b.position = Vector2(400, 300)
	Input.parse_input_event(b)

func _moves() -> void:
	for i in 8:
		var m2 := InputEventMouseMotion.new()
		m2.relative = Vector2(60, 0)
		m2.position = Vector2(300 + i * 60, 300)
		Input.parse_input_event(m2)

func _menu() -> void:
	main._on_cmd("closeall")
	hud_().toggle_menu()

func _menu_check() -> void:
	var top = hud_().screens.top_screen()
	var wb: Button = null
	if top != null:
		for b in top.content.find_children("*", "Button", true, false):
			if (b as Button).text == "Watch":
				wb = b
	check("the menu has Watch", wb != null)
	if wb != null:
		wb.pressed.emit()
		check("it starts Watch mode and closes the menu", hud_().watch.active and hud_().screens.top_screen() == null)
	hud_().watch.stop()

func _title() -> void:
	main.go_title(false)

func _title_check() -> void:
	var top = hud_().screens.top_screen()
	var found := false
	if top != null:
		for b in top.find_children("*", "Button", true, false):
			if (b as Button).tooltip_text.begins_with("Watch\n"):
				found = true
	check("the title screen has Watch", found)
	main.start_watch()
	check("the title Watch starts the tour on the colony", hud_().watch.active and not main.on_title)
	hud_().watch.stop()
