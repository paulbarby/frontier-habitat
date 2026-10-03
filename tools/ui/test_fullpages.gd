extends SceneTree
## The full-page readers (coordinator, 2026-10-03: the Rag, the Codex and Crew stay full pages; the player opens them on
## purpose). Each one opens with its key (J, K, U), closes with the same key, and closes with Esc; Esc closes it before the
## menu opens. Real key events, headless, on showcase_v5:
##   node tools/godot.mjs script res://tools/ui/test_fullpages.gd
var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func q(c: Callable, frames: int = 8) -> void:
	_queue.append([c, frames])

func key(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _open(page: String) -> bool:
	var hud = main.hud
	if page == "rag":
		return hud.rag.visible
	return hud.screen_name() == page

func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		Input.use_accumulated_input = false
		root.size = Vector2i(1920, 1080)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
		main._on_cmd("closeall")
		for p in [["rag", KEY_J, "J"], ["codex", KEY_K, "K"], ["crew", KEY_U, "U"]]:
			var page: String = p[0]
			var code: int = p[1]
			var kn: String = p[2]
			q(func(): key(code), 12)
			q(func(): check("%s: key %s opens it" % [page, kn], _open(page), main.hud.screen_name()))
			q(func(): key(code), 12)
			q(func(): check("%s: key %s closes it" % [page, kn], not _open(page) and not main.hud.is_modal_open(), main.hud.screen_name()))
			q(func(): key(code), 12)
			q(func(): key(KEY_ESCAPE), 12)
			q(func(): check("%s: Esc closes it (and does not open the menu)" % page, not _open(page) and main.hud.screen_name() != "menu", main.hud.screen_name()))
		q(func(): main._on_cmd("closeall"), 4)
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
