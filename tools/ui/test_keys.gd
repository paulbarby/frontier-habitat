extends SceneTree
## Settings > Keys and How to play > Controls against the real input code (UI, 2026-10-02):
##   node tools/godot.mjs script res://tools/ui/test_keys.gd
## Part 1 (source): every KEY_ and MOUSE_BUTTON_ constant that presentation/main.gd (_unhandled_input, _input)
##   and presentation/camera_rig.gd test is a row of ui/keys.gd, and every constant of the table is tested by that code.
##   No other file under ui/ or presentation/ may handle a key (it would be a key the list does not know).
## Part 2 (screens): Settings > Keys and How to play > Controls show every row of the table.
## Part 3 (behaviour): each documented key is sent as a real input event (Input.parse_input_event) and does what the
##   table says: pause and speeds, the screens and windows, the dock, roofs, hide, rotate, sizes, follow from above,
##   over the shoulder (V, Tab, Q E, R, wheel, right drag, Esc), the overview camera (wheel, middle drag, Q E, W A S D).

const KeyList = preload("res://ui/keys.gd")

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var _saved := {}
var _v := {}

func _init() -> void:
	Input.use_accumulated_input = false   # every event reaches the game at once
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func q(c: Callable, frames: int = 4) -> void:
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
		var S = load("res://ui/settings.gd")
		for k in _saved:
			S.set_value(k, _saved[k])
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

# ---------------------------------------------------------------- input helpers
func key(code: int, shift: bool = false, ctrl: bool = false, alt: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.shift_pressed = shift
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)

func hold(code: int, on: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = on
	Input.parse_input_event(ev)

func mouse_button(btn: int, pressed: bool, alt: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	ev.alt_pressed = alt
	ev.position = Vector2(640, 360)
	ev.global_position = ev.position
	Input.parse_input_event(ev)

func mouse_move(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.position = Vector2(640, 360) + rel
	ev.global_position = ev.position
	Input.parse_input_event(ev)

# ---------------------------------------------------------------- part 1: the source
static func _strip(src: String) -> String:
	var out: Array = []
	for line in src.split("\n"):
		var l: String = line
		var i: int = l.find("#")
		if i >= 0:
			l = l.substr(0, i)
		out.append(l)
	return "\n".join(out)

## The body of `func <name>(` up to the next line that starts at column 0.
static func _body(src: String, fname: String) -> String:
	var a: int = src.find("func %s(" % fname)
	if a < 0:
		return ""
	var lines: PackedStringArray = src.substr(a).split("\n")
	var out: Array = [lines[0]]
	for i in range(1, lines.size()):
		var l: String = lines[i]
		if l != "" and not l.begins_with("\t") and not l.begins_with(" "):
			break
		out.append(l)
	return "\n".join(out)

static func _tokens(src: String, prefix: String) -> Array:
	var re := RegEx.new()
	re.compile("\\b%s[A-Z0-9_]+" % prefix)
	var out: Array = []
	for m in re.search_all(src):
		var t: String = m.get_string()
		if not out.has(t):
			out.append(t)
	out.sort()
	return out

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func _source_checks() -> void:
	var main_src: String = _strip(_read("res://presentation/main.gd"))
	var handled: String = _body(main_src, "_unhandled_input") + "\n" + _body(main_src, "_input")
	var rig_src: String = _strip(_read("res://presentation/camera_rig.gd"))
	var code: String = handled + "\n" + rig_src
	check("source: main.gd _unhandled_input found", handled.length() > 800, str(handled.length()))
	var keys_code: Array = _tokens(code, "KEY_")
	var mouse_code: Array = _tokens(code, "MOUSE_BUTTON_")
	var keys_doc: Array = KeyList.all_codes()
	keys_doc.sort()
	var mouse_doc: Array = KeyList.all_mouse()
	mouse_doc.sort()
	var undocumented: Array = keys_code.filter(func(k): return not keys_doc.has(k))
	var dead: Array = keys_doc.filter(func(k): return not keys_code.has(k))
	check("keys: every key the code tests is in the list", undocumented.is_empty(), "missing in ui/keys.gd: " + str(undocumented))
	check("keys: every key in the list is tested by the code", dead.is_empty(), "not in the input code: " + str(dead))
	var m_undoc: Array = mouse_code.filter(func(k): return not mouse_doc.has(k))
	var m_dead: Array = mouse_doc.filter(func(k): return not mouse_code.has(k))
	check("mouse: every button the code tests is in the list", m_undoc.is_empty(), "missing in ui/keys.gd: " + str(m_undoc))
	check("mouse: every button in the list is tested by the code", m_dead.is_empty(), "not in the input code: " + str(m_dead))
	# No other file may read keys.
	var other: Array = []
	for dir in ["res://ui", "res://presentation"]:
		_scan(dir, other)
	check("no other script under ui/ or presentation/ handles a key", other.is_empty(), str(other))
	print("INFO list: %d rows, %d keys, %d mouse buttons" % [KeyList.ROWS.size(), keys_doc.size(), mouse_doc.size()])
	# Every row has the fields the screens read, and its texts.
	var bad: Array = []
	for r in KeyList.ROWS:
		for f in ["g", "keys", "codes", "mouse", "short", "long"]:
			if not r.has(f):
				bad.append("%s lacks %s" % [str(r.get("keys", "?")), f])
		if not KeyList.GROUPS.has(String(r.get("g", ""))):
			bad.append("%s: group %s" % [str(r.get("keys", "?")), str(r.get("g", ""))])
		if String(r.get("keys", "")) == "" or String(r.get("short", "")) == "" or String(r.get("long", "")) == "":
			bad.append("empty text in %s" % str(r.get("keys", "?")))
	check("every row has its fields and texts", bad.is_empty(), str(bad))

func _scan(dir: String, found: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var path: String = "%s/%s" % [dir, f]
		if path == "res://presentation/main.gd" or path == "res://presentation/camera_rig.gd" or path == "res://ui/keys.gd":
			continue
		var s: String = _strip(_read(path))
		if s.contains("InputEventKey") or s.contains("physical_keycode") or not _tokens(s, "KEY_").is_empty() or s.contains("is_physical_key_pressed"):
			found.append(path)
	for sub in d.get_directories():
		_scan("%s/%s" % [dir, sub], found)

func _text_has(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	if node is Button and (node as Button).text.contains(needle):
		return true
	for c in node.get_children():
		if _text_has(c, needle):
			return true
	return false

# ---------------------------------------------------------------- the plan
func _plan() -> void:
	_source_checks()
	var S = load("res://ui/settings.gd")
	for k in ["roofs_off", "dock_open"]:
		_saved[k] = S.get_value(k)
	main.boot["debug"] = "1"
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	root.size = Vector2i(1600, 900)
	var hud = main.hud

	# ---- part 2: the screens show every row
	q(func(): hud.open_screen("settings"), 6)
	q(func():
		var top = hud.screens.top_screen()
		var missing: Array = []
		if top == null:
			missing.append("no settings screen")
		else:
			for i in KeyList.ROWS.size():
				var r: Dictionary = KeyList.ROWS[i]
				var kn: Node = top.find_child("Key_%d" % i, true, false)
				if kn == null or not (kn as Label).text == String(r["keys"]):
					missing.append(String(r["keys"]))
				elif not _text_has(top, String(r["short"])):
					missing.append("text of " + String(r["keys"]))
		check("Settings > Keys shows every row of the list", missing.is_empty(), str(missing))
		hud.screens.close_all(), 4)
	q(func(): hud.open_screen("help", "keys"), 6)
	q(func():
		var top = hud.screens.top_screen()
		var missing: Array = []
		if top == null:
			missing.append("no help screen")
		else:
			for r in KeyList.ROWS:
				if not _text_has(top, String(r["keys"])) or not _text_has(top, String(r["long"])):
					missing.append(String(r["keys"]))
		check("How to play > Controls shows every row of the list", missing.is_empty(), str(missing))
		hud.screens.close_all(), 4)

	# ---- part 3: time
	q(func(): main._on_cmd("speed 1"), 2)
	q(func(): key(KEY_SPACE), 3)
	q(func():
		check("Space pauses", main.speed == 0, str(main.speed))
		key(KEY_SPACE), 3)
	q(func():
		check("Space again resumes", main.speed == 1, str(main.speed))
		key(KEY_2), 3)
	q(func():
		check("2 sets speed 2x", main.speed == 2, str(main.speed))
		key(KEY_3), 3)
	q(func():
		check("3 sets speed 4x", main.speed == 4, str(main.speed))
		key(KEY_1), 3)
	q(func():
		check("1 sets speed 1x", main.speed == 1, str(main.speed))
		main._on_cmd("speed 0"), 2)

	# ---- the screens and windows
	for pair in [[KEY_G, "goals"], [KEY_T, "research"], [KEY_C, "dashboard"], [KEY_I, "inventory"], [KEY_P, "colonists"], [KEY_U, "crew"], [KEY_K, "codex"], [KEY_F1, "help"]]:
		var kc: int = pair[0]
		var sn: String = pair[1]
		q(func(): key(kc), 8)
		q(func():
			check("%s opens the %s screen" % [OS.get_keycode_string(kc), sn], hud.screen_name() == sn, hud.screen_name())
			key(kc), 6)
		q(func():
			check("%s again closes it" % OS.get_keycode_string(kc), not hud.is_modal_open(), hud.screen_name())
			hud.screens.close_all(), 4)
	q(func(): key(KEY_J), 4)
	q(func():
		check("J opens the Regolith Rag", hud.rag.visible)
		key(KEY_J), 4)
	q(func():
		check("J again closes it", not hud.rag.visible)
		key(KEY_N), 4)
	q(func():
		check("N opens the advisor", hud.advisor.visible)
		key(KEY_N), 4)
	q(func():
		check("N again closes it", not hud.advisor.visible)
		key(KEY_SLASH), 4)
	q(func():
		check("/ opens Find", hud.find.visible)
		hud.find.visible = false
		key(KEY_F, false, true), 4)
	q(func():
		check("Ctrl+F opens Find", hud.find.visible)
		hud.find.visible = false
		var before: String = main.view.overlay
		key(KEY_O)
		check("O steps the overlay", main.view.overlay != before, "%s -> %s" % [before, main.view.overlay])
		main._on_cmd("overlay off"), 4)
	q(func():
		var was: bool = hud.panels._dock.visible
		key(KEY_L)
		check("L toggles the left dock", hud.panels._dock.visible != was, "%s -> %s" % [was, hud.panels._dock.visible])
		key(KEY_L), 4)
	q(func():
		check("L again brings it back", hud.panels._dock.visible)
		_v["roofs"] = bool(load("res://ui/settings.gd").get_value("roofs_off"))
		key(KEY_Y), 3)
	q(func():
		check("Y toggles roofs off", bool(load("res://ui/settings.gd").get_value("roofs_off")) != _v["roofs"])
		key(KEY_Y), 3)
	q(func():
		check("Y again restores", bool(load("res://ui/settings.gd").get_value("roofs_off")) == _v["roofs"])
		_v["hud"] = hud.hud_visible()
		key(KEY_H), 3)
	q(func():
		check("H hides the interface", hud.hud_visible() != _v["hud"])
		key(KEY_H), 3)
	q(func():
		check("H again shows it", hud.hud_visible() == _v["hud"]), 2)

	# ---- Esc: opens the menu when nothing else is open; Shift+Esc closes every window
	q(func(): key(KEY_ESCAPE), 8)
	q(func():
		check("Esc with nothing open opens the menu", hud.screen_name() == "menu", hud.screen_name())
		key(KEY_ESCAPE), 6)
	q(func():
		check("Esc closes the menu", not hud.is_modal_open(), hud.screen_name())
		hud.rag.visible = true
		hud.advisor.visible = true
		key(KEY_ESCAPE, true), 6)
	q(func():
		check("Shift+Esc closes every window", not hud.rag.visible and not hud.advisor.visible and not hud.is_modal_open()), 2)

	# ---- placing: R, Shift+R, Z X [ ]
	q(func(): main.start_place("habitat", 1), 3)
	q(func():
		var r0: float = main.tool_rot
		key(KEY_R)
		check("R turns the placed structure by 15 degrees", is_equal_approx(fposmod(main.tool_rot - r0, TAU), deg_to_rad(15.0)), "%.3f" % (main.tool_rot - r0))
		key(KEY_R, true)
		var back: float = fposmod(main.tool_rot - r0, TAU)
		check("Shift+R turns it back", is_zero_approx(back) or is_equal_approx(back, TAU), "%.3f" % back)
		var s0: int = main.tool_size
		key(KEY_X)
		var up1: int = main.tool_size
		key(KEY_Z)
		check("X bigger, Z smaller (size while placing)", up1 == mini(s0 + 1, 3) and main.tool_size == s0 or up1 == s0, "%d %d %d" % [s0, up1, main.tool_size])
		key(KEY_BRACKETRIGHT)
		var up2: int = main.tool_size
		key(KEY_BRACKETLEFT)
		check("] bigger, [ smaller", up2 >= s0 and main.tool_size == s0, "%d %d %d" % [s0, up2, main.tool_size])
		key(KEY_ESCAPE), 4)
	q(func():
		check("Esc cancels the tool", main.tool == "select", main.tool)
		main.start_place("habitat", 1), 3)
	q(func():
		mouse_button(MOUSE_BUTTON_RIGHT, true)
		mouse_button(MOUSE_BUTTON_RIGHT, false)
		check("Right click cancels the tool", main.tool == "select", main.tool), 3)

	# ---- the overview camera
	q(func():
		var rig = main.rig
		var d0: float = rig.target_distance
		mouse_button(MOUSE_BUTTON_WHEEL_UP, true)
		mouse_button(MOUSE_BUTTON_WHEEL_UP, false)
		check("Mouse wheel zooms the colony view", rig.target_distance < d0, "%.1f -> %.1f" % [d0, rig.target_distance])
		var y0: float = rig._yaw_t
		mouse_button(MOUSE_BUTTON_MIDDLE, true)
		mouse_move(Vector2(60, 0))
		mouse_button(MOUSE_BUTTON_MIDDLE, false)
		check("Middle drag turns the colony view", absf(rig._yaw_t - y0) > 0.05, "%.3f -> %.3f" % [y0, rig._yaw_t])
		_v["yaw"] = rig._yaw_t
		hold(KEY_Q, true), 15)
	q(func():
		var rig = main.rig
		hold(KEY_Q, false)
		check("Q turns the colony view", absf(rig._yaw_t - float(_v["yaw"])) > 0.01, "%.3f -> %.3f" % [_v["yaw"], rig._yaw_t])
		_v["focus"] = rig.focus
		hold(KEY_D, true), 20)
	q(func():
		var rig = main.rig
		hold(KEY_D, false)
		check("D moves the camera", rig.focus.distance_to(_v["focus"]) > 0.05, "%.3f m" % rig.focus.distance_to(_v["focus"])), 2)

	# ---- follow from above (F), over the shoulder (V, Tab, Q E, R, wheel, right drag, Esc)
	q(func():
		var ids: Array = []
		for r in hud.v5.people():
			if String(r["kind"]) == "colonist":
				ids.append(int(r["id"]))
		_v["ids"] = ids
		main.select("agent", int(ids[0]))
		main.rig.follow_fn = Callable()
		key(KEY_F), 4)
	q(func():
		check("F follows the selected person from above", main.rig.follow_fn.is_valid())
		hold(KEY_W, true), 6)
	q(func():
		hold(KEY_W, false)
		check("A camera key ends the follow from above", not main.rig.follow_fn.is_valid())
		main.select("agent", int(_v["ids"][0]))
		key(KEY_V), 12)
	q(func():
		check("V goes over the shoulder", main.in_follow(), str(main.view.follow_id))
		check("V shows the follow card, dims the HUD to about 35 % and folds the dock", hud.follow_hud.visible and absf(hud.top_bar.modulate.a - 0.35) < 0.02 and hud.panels.minimised, "%s %s" % [str(hud.top_bar.modulate.a), str(hud.panels.minimised)])
		var rig = main.rig
		var s0: float = rig.sh_side
		key(KEY_E)
		check("E changes the shoulder", rig.sh_side == -s0)
		key(KEY_Q)
		check("Q changes it back", rig.sh_side == s0)
		var d0: float = rig.sh_dist
		mouse_button(MOUSE_BUTTON_WHEEL_UP, true)
		mouse_button(MOUSE_BUTTON_WHEEL_UP, false)
		check("Wheel zooms over the shoulder", rig.sh_dist < d0, "%.2f -> %.2f" % [d0, rig.sh_dist])
		var sel0: String = main.view.selected_kind
		mouse_button(MOUSE_BUTTON_RIGHT, true)
		mouse_move(Vector2(80, 30))
		mouse_button(MOUSE_BUTTON_RIGHT, false)
		check("Right drag goes round the person and tilts", absf(rig.sh_orbit) > 0.1 and absf(rig.sh_pitch) > 0.02, "orbit %.2f pitch %.2f" % [rig.sh_orbit, rig.sh_pitch])
		check("Right drag clears no selection", main.view.selected_kind == sel0 and main.in_follow(), "%s %s" % [main.view.selected_kind, str(main.in_follow())])
		mouse_button(MOUSE_BUTTON_MIDDLE, true)
		mouse_move(Vector2(40, 10))
		mouse_button(MOUSE_BUTTON_MIDDLE, false)
		check("Middle drag looks round", absf(rig.sh_look_yaw) > 0.05, "%.2f" % rig.sh_look_yaw)
		mouse_button(MOUSE_BUTTON_RIGHT, true, true)
		mouse_move(Vector2(-40, 0))
		mouse_button(MOUSE_BUTTON_RIGHT, false, true)
		var o0: float = rig.sh_orbit
		key(KEY_R)
		check("R: the camera goes back behind the person", is_zero_approx(rig.sh_orbit) and is_zero_approx(rig.sh_pitch) and is_zero_approx(rig.sh_look_yaw), "orbit %.2f (was %.2f)" % [rig.sh_orbit, o0])
		key(KEY_TAB), 6)
	q(func():
		check("Tab follows the next person", main.in_follow() and (main.view.follow_id != int(_v["ids"][0]) or _v["ids"].size() < 2), str(main.view.follow_id))
		key(KEY_ESCAPE), 6)
	q(func():
		check("Esc ends the over-the-shoulder view", not main.in_follow())
		main.select("agent", int(_v["ids"][0]))
		key(KEY_V), 12)
	q(func():
		check("V over the shoulder (second time)", main.in_follow())
		key(KEY_V), 6)
	q(func():
		check("V again ends it", not main.in_follow())
		main.select("", -1)
		key(KEY_V), 8)
	q(func():
		check("V with nobody selected opens the Awards", hud.screen_name() == "awards", hud.screen_name())
		hud.screens.close_all(), 4)

	# ---- Delete with a structure selected asks first
	q(func():
		var bid: int = -1
		for id in main.sim.state["buildings"]:
			var b: Dictionary = main.sim.state["buildings"][id]
			if String(b["def"]) == "habitat":
				bid = int(id)
				break
		check("the showcase has a habitat", bid >= 0)
		if bid >= 0:
			main.select("building", bid)
		key(KEY_DELETE), 8)
	q(func():
		check("Delete asks before it removes a structure", hud.is_modal_open(), hud.screen_name())
		hud.screens.close_all()
		main.select("", -1), 4)
	# ---- PgUp, PgDn step the floor of a multi-floor structure
	q(func():
		var bid: int = -1
		for id in main.sim.state["buildings"]:
			if String(main.sim.state["buildings"][id]["def"]) == "super_dome":
				bid = int(id)
				break
		check("the showcase has a super dome", bid >= 0)
		if bid >= 0:
			main.select("building", bid), 12)
	q(func():
		var fs = hud.floor_sel
		_v["f0"] = fs.floor_shown
		key(KEY_PAGEDOWN), 2)
	q(func():
		var fs = hud.floor_sel
		_v["f1"] = fs.floor_shown
		key(KEY_PAGEUP), 2)
	q(func():
		var fs = hud.floor_sel
		check("PgDn and PgUp step the floor", fs.visible and int(_v["f1"]) != int(_v["f0"]), "%s %s %s" % [str(_v["f0"]), str(_v["f1"]), str(fs.floor_shown)])
		main.select("", -1), 2)
