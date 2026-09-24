extends Node
## Game root. Owns the simulation, runs it at a fixed 10 Hz from an accumulator that is
## independent of render frames (spec 5), and turns player input into commands.
## Nothing here or in the interface writes to sim.state.
##
## Also: boot parameters and the window.__fh automation hook (docs/AAA_DESIGN.md §14),
## the title screen (a showcase colony behind the menu), settings, audio.

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const Reference = preload("res://sim/reference.gd")
const WorldView = preload("res://presentation/world_view.gd")
const CameraRig = preload("res://presentation/camera_rig.gd")
const Hud = preload("res://ui/hud.gd")
const Boot = preload("res://presentation/boot.gd")
const Settings = preload("res://ui/settings.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Audio = preload("res://ui/audio.gd")
const Sfx = preload("res://ui/sfx.gd")
const Profile = preload("res://ui/profile.gd")
const UiMock = preload("res://ui/mock.gd")

const TICK := 0.1
const MAX_STEPS_PER_FRAME := 10
const TITLE_TIME := 372.0

var sim
var view
var rig
var hud
var audio
var speed := 1
var paused_by_menu := false
var effective_speed := 1.0
var slowed := false
var on_title := false
var _acc := 0.0
var _autosave_clock := 0.0
var _demo = null
var _sent: Array = []            # command ids waiting for a result
var _step_ms := 0.0

# tool state
var tool := "select"             # select | place | link | demolish
var tool_def := ""
var tool_size := 1
var tool_rot := 0.0
var link_from := -1
var hover_point = null
var hover_pick := {}
var forced_hover = null          # automation: a fixed ground point for the tool
var tool_message := ""
var tool_ok := false
var tool_info := {"tool": "select"}
var persist_warning := ""
var _js_cb = null
var _shots: Array = []
var boot := {}
var _hook = null
var _boot_frames := 0
var _fps := 0.0
var _fps_clock := 0.0
var _quiet := false
var _proc_avg := 0.0
var _shake_on := true

func _ready() -> void:
	get_window().min_size = Vector2i(1024, 600)
	view = WorldView.new()
	add_child(view)
	rig = CameraRig.new()
	add_child(rig)
	audio = Audio.new()
	add_child(audio)
	Sfx.audio = audio
	hud = Hud.new()
	hud.main = self
	add_child(hud)
	if not OS.is_userfs_persistent():
		persist_warning = "This browser does not keep saved games. Use Export to keep a save file."
	Settings.load_all()
	# Boot parameters: URL query in the browser, user arguments on the desktop (§14).
	boot = Boot.params()
	var seed_value: int = int(boot.get("seed", "1001"))
	var want_title: bool = Boot.has(boot, "title") or (boot.is_empty() and not OS.has_feature("editor_hint"))
	if boot.has("title") and String(boot["title"]) == "0":
		want_title = false
	if want_title:
		go_title(false)
	elif boot.has("load") and FileAccess.file_exists(String(boot["load"])):
		_import_bytes(FileAccess.get_file_as_bytes(String(boot["load"])))
	else:
		start_new(seed_value, _options_from_boot())
	if Boot.has(boot, "demo"):
		run_demo()
	if boot.has("fast"):
		_fast_forward(float(boot["fast"]))
	if boot.has("speed"):
		set_speed(int(boot["speed"]))
	apply_settings()
	_hook = Boot.install_js_hook(_on_cmd)
	_boot_frames = 3
	if boot.has("open") and not on_title:
		hud.open_screen(String(boot["open"]))

func _options_from_boot() -> Dictionary:
	var o := {}
	if boot.has("planet"):
		o["planet"] = String(boot["planet"])
	if boot.has("difficulty"):
		o["difficulty"] = String(boot["difficulty"])
	if boot.has("hazards"):
		o["hazards"] = String(boot["hazards"])
	if debug_mode():
		o["debug"] = true
	return o

## Boot parameter debug=1: test-only commands (hazard_now, uimock) are accepted.
func debug_mode() -> bool:
	return Boot.has(boot, "debug")

## Runs the simulation now, without drawing, so a screenshot can show a later day.
func _fast_forward(secs: float) -> void:
	var n: int = int(secs * float(sim.bal["tick_hz"]))
	for i in n:
		_demo_drive()
		sim.step()

# ---------------------------------------------------------------- automation hook
## Text commands from window.__fh.cmd() (browser) — the automation interface.
func _on_cmd(text: String) -> String:
	var w: PackedStringArray = text.strip_edges().split(" ", false)
	if w.is_empty():
		return "empty"
	match w[0]:
		"speed":
			set_speed(int(w[1]))
		"fast":
			_fast_forward(float(w[1]))
		"demo":
			run_demo()
		"overlay":
			hud.set_overlay("" if w.size() < 2 or w[1] == "off" else w[1])
		"select":
			for id in sim.state["buildings"]:
				if sim.state["buildings"][id]["def"] == w[1]:
					select("building", id)
					focus_on(sim.state["buildings"][id]["pos"])
					if w.size() > 2:
						hud.inspector.set_tab(w[2])
					return "ok"
			return "not found"
		"agent":
			var n: int = int(w[1]) if w.size() > 1 else 0
			var i := 0
			for id in sim.state["agents"]:
				if sim.state["agents"][id]["state"] != "alive":
					continue
				if i == n:
					select("agent", id)
					focus_on(sim.state["agents"][id]["pos"])
					if w.size() > 2:
						hud.inspector.set_tab(w[2])
					return "ok"
				i += 1
			return "not found"
		"tab":
			if w.size() < 2:
				return "tab <name>"
			var top = hud.screens.top_screen()
			if top != null and top.has_method("set_tab"):
				top.set_tab(w[1])
			else:
				hud.inspector.set_tab(w[1])
		"open":
			if w.size() < 2:
				return "open <screen>"
			if not hud.open_screen(w[1], w[2] if w.size() > 2 else null):
				return "unknown screen"
		"close":
			hud.close_modal()
		"zoom":
			rig.target_distance = float(w[1])
		"yaw":
			rig.yaw = deg_to_rad(float(w[1]))
		"pitch":
			rig.pitch = deg_to_rad(float(w[1]))
		"place":
			# place <def> <size> <x> <y> [rot_deg]: submits the command, like a click.
			if w.size() < 5:
				return "place <def> <size> <x> <y> [rot]"
			var p := Vector2(float(w[3]), float(w[4]))
			var rot: float = deg_to_rad(float(w[5])) if w.size() > 5 else 0.0
			var code: String = _check_place(w[1], p, rot, int(w[2]))
			submit("place_building", {"def": w[1], "x": p.x, "y": p.y, "rot": rot, "size": int(w[2])})
			return code
		"tool":
			# tool <def> <size> [x y]: starts placement; with x y the ghost stays at that point.
			if w.size() < 2:
				cancel_tool()
				return "ok"
			if w[1] == "corridor" or w[1] == "cable":
				start_link(w[1])
			elif w[1] == "remove":
				start_demolish()
			else:
				start_place(w[1], int(w[2]) if w.size() > 2 else -1)
			forced_hover = Vector2(float(w[3]), float(w[4])) if w.size() > 4 else null
		"hover":
			forced_hover = null if w.size() < 3 else Vector2(float(w[1]), float(w[2]))
		"build":
			if w.size() > 1:
				hud.build_bar.toggle_tab(w[1])
		"title":
			if w.size() > 1 and w[1] == "off":
				leave_title()
			else:
				go_title(true)
		"newgame":
			var o := {}
			if w.size() > 2:
				o["planet"] = w[2]
			if w.size() > 3:
				o["difficulty"] = w[3]
			start_new(int(w[1]) if w.size() > 1 else 1001, o)
		"quality":
			Settings.set_value("quality", clampi(int(w[1]), 0, 3))
			apply_settings()
		"uiscale":
			Settings.set_value("ui_scale", clampf(float(w[1]), 0.6, 2.0))
			apply_settings()
		"hud":
			hud.set_hud_visible(w.size() < 2 or w[1] != "off")
		"time":
			if view.has_method("set_time_override"):
				view.set_time_override(-1.0 if w.size() < 2 or w[1] == "off" else float(w[1]))
		"award":
			hud.screens.award_popup(w[1] if w.size() > 1 else "first_breath", true)
		"chapter":
			hud.screens.chapter_banner(int(w[1]) if w.size() > 1 else 0)
		"toast":
			hud.toast(" ".join(w.slice(1)), "info")
		"fps":
			return "%.1f" % _fps
		"perf":
			# fps, draw calls, objects in frame, process ms (for the HUD budget).
			return "fps=%.1f draws=%d objects=%d process_ms_avg=%.2f" % [Engine.get_frames_per_second(),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				_proc_avg]
		"hudpart":
			# hudpart <module> on|off: hides one HUD module (for measurements).
			var m = hud.get(w[1]) if w.size() > 1 else null
			if m is CanvasItem:
				(m as CanvasItem).visible = w.size() < 3 or w[2] != "off"
				return "ok"
			return "unknown module"
		"screen":
			return hud.screen_name()
		# ---- version 3 (docs/V3_DESIGN.md §8)
		"hazard":
			# hazard <kind> [x y] [severity] [in_seconds]: a hazard now (or in N s, so the
			# forecast shows it), for tests and screenshots. A recorded command, so replays stay
			# deterministic. Needs the boot parameter debug=1.
			if not debug_mode():
				return "refused: start with debug=1"
			if w.size() < 2:
				return "hazard <kind> [x y] [severity]"
			var hp: Dictionary = {"kind": w[1], "severity": 1}
			if w.size() >= 4:
				var at := Vector2(float(w[2]), float(w[3]))
				hp["x"] = at.x
				hp["y"] = at.y
				hp["pos"] = at
				if w.size() >= 5:
					hp["severity"] = clampi(int(w[4]), 1, 3)
				if w.size() >= 6:
					hp["in"] = maxf(1.0, float(w[5]))
			elif w.size() == 3:
				hp["severity"] = clampi(int(w[2]), 1, 3)
			submit("hazard_now", hp)
			return "submitted"
		"follow":
			# follow <agent id>: select the colonist and the camera follows it.
			var fid: int = int(w[1]) if w.size() > 1 else -1
			if not sim.state["agents"].has(fid):
				return "not found"
			select("agent", fid)
			focus_on(sim.state["agents"][fid]["pos"])
			follow_selected()
		"goto":
			if w.size() < 3:
				return "goto <x> <y>"
			focus_on(Vector2(float(w[1]), float(w[2])))
		"interior":
			# interior <building id>: camera close over a room; the view opens the roof of the
			# selected room (RENDER's cutaway).
			var bid: int = int(w[1]) if w.size() > 1 else -1
			if not sim.state["buildings"].has(bid):
				return "not found"
			var ib: Dictionary = sim.state["buildings"][bid]
			select("building", bid)
			focus_on(ib["pos"])
			rig.target_distance = clampf(float(ib.get("radius", 5.0)) * 2.8 + 8.0, 14.0, 45.0)
			rig.pitch = deg_to_rad(58.0)
			if view.has_method("open_interior"):
				view.open_interior(bid)
		"uimock":
			# uimock hazards|maintenance|labs|all|off: made-up rows for layout checks (debug=1 only).
			if not debug_mode():
				return "refused: start with debug=1"
			hud.data.mock = {} if w.size() < 2 or w[1] == "off" else UiMock.build(sim, w[1])
			hud.hazard.rebuild()
		"alerts":
			# The toast rule counters (V3_DESIGN §2).
			var g = hud.watchers.gate
			return "live=%d held=%d toasts=%d" % [g.live_count(), g.held_count(), g.toasts_sent]
		"shake":
			Settings.set_value("camera_shake", w.size() < 2 or w[1] != "off")
			apply_settings()
		"shelter":
			# shelter on|off: the Shelter button of the hazard panel.
			if hud.data.shelter_on() != (w.size() < 2 or w[1] != "off"):
				hud.hazard.toggle_shelter(hud)
			return "on" if hud.data.mock.get("shelter", hud.data.shelter_on()) else "sent"
		"idof":
			# idof <def> | idof agent [n]: the id of the first structure of a def, or of the n-th
			# living colonist (for follow and interior).
			if w.size() > 1 and w[1] == "agent":
				var want: int = int(w[2]) if w.size() > 2 else 0
				var k := 0
				for aid in sim.state["agents"]:
					if sim.state["agents"][aid]["state"] == "alive":
						if k == want:
							return str(aid)
						k += 1
				return "not found"
			for bid2 in sim.state["buildings"]:
				if w.size() > 1 and sim.state["buildings"][bid2]["def"] == w[1]:
					return str(bid2)
			return "not found"
		"minimap":
			# minimap zoom|whole
			hud.minimap.set_zoomed(w.size() > 1 and w[1] == "zoom")
		_:
			return "unknown command"
	return "ok"

# ---------------------------------------------------------------- start, load, title
func start_new(seed_value: int, options: Dictionary = {}) -> void:
	if on_title:
		leave_title()
	_new_world(seed_value, options)
	Profile.note_game()
	var planet: String = String(sim.planet.get("name", "the planet"))
	hud.toast("Seed %d, %s. The lander is down. Build power, water and air before its air ends." % [seed_value, planet.to_lower()], "info", "ship")

func _new_world(seed_value: int, options: Dictionary) -> void:
	if sim != null:
		sim.dispose()
	sim = Sim.new()
	if debug_mode() and not options.has("debug"):
		options = options.duplicate()
		options["debug"] = true
	if options.is_empty() or hud.data.arg_count(sim, "new_game") < 3:
		sim.new_game(seed_value)
	else:
		sim.new_game(seed_value, "tutorial", options)
	_after_world_change()

func _after_world_change() -> void:
	view.setup(sim)
	var c: Vector2 = sim.world.center
	rig.bounds = Rect2(0, 0, sim.world.size, sim.world.size)
	rig.height_fn = Callable(sim.world, "height_at")
	rig.jump_to(Vector3(c.x + 14.0, sim.world.height_at(c.x, c.y), c.y))
	rig.follow_fn = Callable()
	cancel_tool()
	select("", -1)
	_acc = 0.0
	_demo = null
	hud.rebuild_all()
	hud.set_hud_visible(not on_title)

## The title screen: a showcase colony at dusk behind the menu.
func go_title(autosave: bool = true) -> void:
	if autosave and sim != null and not on_title and not bool(sim.state["progress"].get("lost", false)):
		Persistence.autosave(sim.state, int(sim.bal["autosave_slots"]))
	var path: String = showcase_path()
	var ok := false
	_quiet = true
	on_title = true
	if path != "":
		var res: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))
		if res["ok"]:
			_install(res["state"], "")
			ok = true
	if not ok:
		_new_world(1001, {})
	_quiet = false
	hud.set_hud_visible(false)
	set_speed(1)
	if view.has_method("set_time_override"):
		view.set_time_override(TITLE_TIME)
	_title_camera()
	hud.open_screen("title")

func _title_camera() -> void:
	var sum := Vector2.ZERO
	var n := 0
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b.get("kind", "")) != "link" and String(b["def"]) != "meridian":
			sum += b["pos"]
			n += 1
	var center: Vector2 = sum / n if n > 0 else sim.world.center
	if rig.has_method("photo_orbit"):
		rig.photo_orbit(view.to3(center), 78.0, 26.0, 0.035)
	else:
		rig.jump_to(view.to3(center))
		rig.target_distance = 95.0
		rig.pitch = deg_to_rad(24.0)

func leave_title() -> void:
	if not on_title:
		return
	on_title = false
	if rig.has_method("stop_photo"):
		rig.stop_photo()
	if view.has_method("set_time_override"):
		view.set_time_override(-1.0)
	hud.screens.close_all()
	hud.set_hud_visible(true)

## The newest showcase save shipped with the game.
static func showcase_path() -> String:
	var best := ""
	var dir := "res://content/saves"
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if f.begins_with("showcase") and f.ends_with(".fhsave") and f > best.get_file():
				best = dir.path_join(f)
	return best

## The newest save on this device ("" when there is none).
static func latest_slot() -> String:
	var best := ""
	var t := -1
	for s in Persistence.list_slots():
		if int(s["modified"]) > t:
			t = int(s["modified"])
			best = String(s["slot"])
	return best

## Title screen "Continue": the newest save, or a new colony.
func continue_game() -> void:
	var slot: String = latest_slot()
	if slot == "":
		leave_title()
		start_new(1001)
		return
	load_game(slot)

# ---------------------------------------------------------------- settings
func apply_settings() -> void:
	if view != null and view.has_method("set_quality"):
		view.set_quality(int(Settings.get_value("quality")))
	var sc: float = clampf(float(Settings.get_value("ui_scale")), 0.6, 2.0)
	if not is_equal_approx(get_tree().root.content_scale_factor, sc):
		get_tree().root.content_scale_factor = sc
	Glass.set_enabled(bool(Settings.get_value("glass")))
	rig.edge_pan = bool(Settings.get_value("edge_pan"))
	rig.pan_speed = float(Settings.get_value("camera_speed"))
	# Camera shake (quakes, landings, impacts). RENDER's rig and view read `shake_enabled`
	# when they have it; until then _process stops the rig's shake itself.
	_shake_on = bool(Settings.get_value("camera_shake"))
	for o in [rig, view]:
		if o != null and "shake_enabled" in o:
			o.set("shake_enabled", _shake_on)
	if audio != null:
		audio.apply_volumes()

# ---------------------------------------------------------------- main loop
func _process(delta: float) -> void:
	var run_speed: int = 0 if paused_by_menu else speed
	if run_speed > 0 and not bool(sim.state["progress"]["lost"]):
		_acc += delta * run_speed
		var steps := 0
		var t0: int = Time.get_ticks_usec()
		while _acc >= TICK and steps < MAX_STEPS_PER_FRAME:
			_demo_drive()
			sim.step()
			_acc -= TICK
			steps += 1
			if Time.get_ticks_usec() - t0 > 14000:
				break
		if steps > 0:
			_step_ms = lerpf(_step_ms, float(Time.get_ticks_usec() - t0) / 1000.0 / steps, 0.1)
		# If the simulation cannot keep pace it never skips logical ticks: the backlog is
		# dropped, time runs slower, and the player is told (acceptance 15).
		slowed = _acc > TICK * 6.0
		if slowed:
			_acc = 0.0
		effective_speed = lerpf(effective_speed, float(steps) * TICK / maxf(delta, 0.0001), 0.05)
		if not on_title:
			_autosave_clock += delta
			if _autosave_clock >= float(sim.bal["autosave_interval_real_seconds"]):
				_autosave_clock = 0.0
				var res: Dictionary = Persistence.autosave(sim.state, int(sim.bal["autosave_slots"]))
				hud.toast("Autosaved." if res["ok"] else "Autosave failed: " + String(res["error"]), "save" if res["ok"] else "warn")
	_poll_results()
	view.camera_distance = rig.distance
	view.sync(delta)
	_update_tool()
	_take_shots()
	if _boot_frames > 0:
		_boot_frames -= 1
	_proc_avg = lerpf(_proc_avg, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.05)
	_fps_clock += delta
	if _fps_clock >= 0.5:
		_fps_clock = 0.0
		_fps = Engine.get_frames_per_second()
		if view.has_method("stats"):
			_fps = float(view.stats().get("fps", _fps))
		audio.ambience(sim.util.is_night(), on_title)
	Boot.set_state(_hook, _boot_frames == 0, int(sim.state["tick"]), sim.util.day_number())
	Boot.set_extra(_hook, _fps, "title" if on_title and hud.screen_name() == "title" else hud.screen_name())
	# Camera shake off (Settings) while the rig has no `shake_enabled` flag of its own: the
	# rig runs after this node, so a zero here means no shake this frame.
	if not _shake_on and not ("shake_enabled" in rig) and "_shake" in rig:
		rig.set("_shake", 0.0)

func _demo_drive() -> void:
	if _demo == null:
		return
	if int(sim.state["tick"]) % int(sim.bal["tick_hz"]) == 0:
		_demo.drive()
		if _demo.finished():
			_demo = null

func run_demo() -> void:
	_demo = Reference.new(sim)
	# The reference layout names seconds from the start of a game: shift it to now.
	var now: float = sim.seconds()
	for st in _demo.steps:
		st["t"] = float(st["t"]) + now
	hud.toast("Demo: the reference outpost is being planned. The colonists do the rest.", "info", "build")

func set_speed(n: int) -> void:
	if n != speed:
		Sfx.play("tick")
	speed = n

func submit(kind: String, payload: Dictionary) -> void:
	_sent.append(sim.submit(kind, payload))
	if speed == 0 or paused_by_menu:
		# Paused mode still accepts plans and policy changes (spec 12): apply them now.
		sim.cmds.apply_pending()
		if bool(sim.state["topo_dirty"]):
			sim.topo.rebuild(true)

func _poll_results() -> void:
	for cid in _sent.duplicate():
		if sim.cmds.results.has(cid):
			var r: Dictionary = sim.cmds.results[cid]
			_sent.erase(cid)
			sim.cmds.results.erase(cid)
			if not bool(r.get("ok", false)):
				hud.toast("Refused: " + _reason(String(r.get("code", ""))), "warn")
				Sfx.play("error")

func _reason(code: String) -> String:
	var t: String = sim.place.reason_text(code)
	if t == code:
		t = code.replace("_", " ").capitalize() + "."
	return t

# ---------------------------------------------------------------- tools
func start_place(def_id: String, size: int = -1) -> void:
	cancel_tool()
	tool = "place"
	tool_def = def_id
	if size < 0:
		size = int(hud.build_bar.size_sel.get(def_id, 1))
	tool_size = size if hud.data.has_sizes(def_id) else 1
	Sfx.play("select")

func set_tool_size(n: int) -> void:
	if tool != "place" or not hud.data.has_sizes(tool_def):
		return
	n = clampi(n, 0, 3)
	if not bool(hud.data.size_allowed(tool_def, n).get("ok", false)):
		hud.toast("Size %s: %s" % [hud.data.SIZE_NAMES[n], String(hud.data.size_allowed(tool_def, n).get("text", ""))], "warn", "lock")
		Sfx.play("error")
		return
	tool_size = n
	hud.build_bar.size_sel[tool_def] = n
	Sfx.play("tick")

func start_link(def_id: String) -> void:
	cancel_tool()
	tool = "link"
	tool_def = def_id
	link_from = -1
	Sfx.play("select")

func start_demolish() -> void:
	cancel_tool()
	tool = "demolish"
	Sfx.play("select")

func cancel_tool() -> void:
	tool = "select"
	tool_def = ""
	link_from = -1
	tool_message = ""
	forced_hover = null
	tool_info = {"tool": "select"}
	if view != null and view.sim != null:
		view.clear_ghost()
		view.set_link_preview(null, null)

func _mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _update_tool() -> void:
	rig.ui_blocks_mouse = _mouse_over_ui() or on_title
	hover_point = null
	hover_pick = {}
	if forced_hover != null:
		hover_point = forced_hover
		hover_pick = view.pick(hover_point, tool == "select")
	elif not _mouse_over_ui() and not on_title:
		hover_point = view.ground_point(rig.camera, get_viewport().get_mouse_position())
		if hover_point != null:
			hover_pick = view.pick(hover_point, tool == "select")
	_update_tool_state()

## Placement check with the size when the sim takes it (5th argument, §10).
func _check_place(def_id: String, p: Vector2, rot: float, size: int) -> String:
	if hud.data.arg_count(sim.place, "check_building") >= 5:
		return sim.place.check_building(def_id, p, rot, -1, size)
	return sim.place.check_building(def_id, p, rot)

func _update_tool_state() -> void:
	match tool:
		"place":
			_update_place()
		"link":
			_update_link()
		"demolish":
			tool_message = "Remove: click a structure. Plans are cancelled, finished structures are taken down."
			tool_info = {"tool": "demolish", "ok": true}

func _update_place() -> void:
	var d = hud.data
	var sdef: Dictionary = d.size_def(tool_def, tool_size)
	var info := {"tool": "place", "def": tool_def, "size": tool_size, "cost": sdef.get("cost", {}), "ok": false, "reason": "", "warning": ""}
	if hover_point == null:
		tool_ok = false
		info["reason"] = "Point at the ground to place it."
		view.clear_ghost()
		tool_info = info
		tool_message = info["reason"]
		return
	var p: Vector2 = sim.place.snap_pos(hover_point)
	var code: String = _check_place(tool_def, p, tool_rot, tool_size)
	tool_ok = code == "ok"
	var sa: Dictionary = d.size_allowed(tool_def, tool_size)
	if tool_ok and not bool(sa.get("ok", true)) and d.has_sizes(tool_def):
		tool_ok = false
		info["reason"] = String(sa.get("text", "This size is locked."))
	elif not tool_ok:
		info["reason"] = _reason(code)
	info["ok"] = tool_ok
	# Builders walk from an airlock with air and must get back on one suit.
	var reach: float = sim.agents.suit_reach_metres()
	var away: float = sim.agents.nearest_air_metres(p) * 1.25
	if tool_ok and away > reach:
		info["warning"] = "About %d m on foot from the nearest airlock with air. Suit range is about %d m. Build an airlock nearer first." % [int(away), int(reach)]
	tool_info = info
	tool_message = String(info["reason"])
	view.set_ghost(tool_def, tool_size, p, tool_rot, tool_ok)

func _update_link() -> void:
	var info := {"tool": "link", "def": tool_def, "cost": {}, "ok": false, "reason": "", "warning": "", "length": 0.0}
	if link_from == -1 or not sim.state["buildings"].has(link_from):
		link_from = -1
		info["reason"] = "Click the first structure."
		_link_preview(null, null, true)
	else:
		var a: Dictionary = sim.state["buildings"][link_from]
		var to_id: int = int(hover_pick.get("id", -1)) if hover_pick.get("kind", "") == "building" else -1
		if to_id != -1 and to_id != link_from:
			var chk: Dictionary = sim.place.check_link(tool_def, link_from, to_id)
			tool_ok = chk["code"] == "ok"
			info["ok"] = tool_ok
			if tool_ok:
				info["cost"] = chk["cost"]
				info["length"] = float(chk["length"])
				info["reason"] = "From %s. Click to build." % a["name"]
				_link_preview(chk["p0"], chk["p1"], true)
			else:
				info["reason"] = _reason(String(chk["code"]))
				_link_preview(a["pos"], sim.state["buildings"][to_id]["pos"], false)
		else:
			tool_ok = false
			info["reason"] = "From %s: click the second structure." % a["name"]
			_link_preview(a["pos"], hover_point, true)
	tool_info = info
	tool_message = String(info["reason"])

func _link_preview(p0, p1, ok: bool) -> void:
	view.set_link_preview(p0, p1, tool_def, ok)

# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if on_title:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if tool != "select":
				cancel_tool()
			else:
				select("", -1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# Work from the click position itself, not from the last frame's hover state.
			forced_hover = null
			hover_point = view.ground_point(rig.camera, mb.position)
			hover_pick = view.pick(hover_point, tool == "select") if hover_point != null else {}
			_update_tool_state()
			_left_click(mb.shift_pressed)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		match k.physical_keycode:
			KEY_SPACE: set_speed(0 if speed != 0 else 1)
			KEY_1: set_speed(1)
			KEY_2: set_speed(2)
			KEY_3: set_speed(4)
			KEY_R: tool_rot = fposmod(tool_rot + deg_to_rad(15.0) * (-1.0 if k.shift_pressed else 1.0), TAU)
			KEY_Z, KEY_BRACKETLEFT: set_tool_size(tool_size - 1)
			KEY_X, KEY_BRACKETRIGHT: set_tool_size(tool_size + 1)
			KEY_F: follow_selected()
			KEY_O: hud.cycle_overlay()
			KEY_G: hud.toggle_screen("goals")
			KEY_T: hud.toggle_screen("research")
			KEY_C: hud.toggle_screen("dashboard")
			KEY_I: hud.toggle_screen("inventory")
			KEY_P: hud.toggle_screen("colonists")
			KEY_V: hud.toggle_screen("awards")
			KEY_H: hud.set_hud_visible(not hud.hud_visible())
			KEY_F1: hud.toggle_screen("help")
			KEY_ESCAPE:
				if tool != "select":
					cancel_tool()
				elif hud.is_modal_open():
					hud.close_modal()
				elif hud.build_bar.is_open():
					hud.build_bar.close_drawer()
				elif view.selected_kind != "":
					select("", -1)
				else:
					hud.toggle_menu()
			KEY_DELETE:
				if view.selected_kind == "building":
					hud.ask_demolish(view.selected_id)

func _left_click(shift: bool) -> void:
	if hover_point == null:
		return
	match tool:
		"select":
			if hover_pick.is_empty():
				select("", -1)
			else:
				select(hover_pick["kind"], hover_pick["id"])
				Sfx.play("select")
		"place":
			if tool_ok:
				var p: Vector2 = sim.place.snap_pos(hover_point)
				submit("place_building", {"def": tool_def, "x": p.x, "y": p.y, "rot": tool_rot, "size": tool_size})
				Sfx.play("place")
				if not shift:
					cancel_tool()
			else:
				hud.toast(tool_message, "warn")
				Sfx.play("error")
		"link":
			if hover_pick.get("kind", "") != "building":
				return
			var id: int = int(hover_pick["id"])
			if sim.state["buildings"][id]["kind"] == "link":
				return
			if link_from == -1:
				link_from = id
				Sfx.play("tick")
			elif id != link_from:
				if tool_ok:
					submit("place_link", {"def": tool_def, "a": link_from, "b": id})
					Sfx.play("place")
					link_from = id if shift else -1
				else:
					hud.toast(tool_message, "warn")
					Sfx.play("error")
		"demolish":
			if hover_pick.get("kind", "") == "building":
				hud.ask_demolish(int(hover_pick["id"]))

func select(kind: String, id: int) -> void:
	view.select(kind, id)
	rig.follow_fn = Callable()
	hud.selection_changed()

func follow_selected() -> void:
	if view.selected_kind == "agent":
		var id: int = view.selected_id
		rig.follow_fn = func(): return view.agent_world_pos(id)

func focus_on(p: Vector2) -> void:
	rig.follow_fn = Callable()
	rig.jump_to(view.to3(p))

# ---------------------------------------------------------------- save / load
func save_game(slot: String) -> void:
	var res: Dictionary = Persistence.write_slot(slot, sim.state)
	hud.toast(("Saved to %s." % slot.replace("_", " ")) if res["ok"] else String(res["error"]), "save" if res["ok"] else "warn")

func load_game(slot: String) -> void:
	var res: Dictionary = Persistence.read_slot(slot)
	if not res["ok"]:
		hud.toast(String(res["error"]), "warn")
		return
	on_title_leave_before_install()
	_install(res["state"], "Loaded %s." % slot.replace("_", " "))

func on_title_leave_before_install() -> void:
	if on_title:
		leave_title()

func _install(state: Dictionary, message: String) -> void:
	if sim != null:
		sim.dispose()
	sim = Sim.new()
	# debug=1 with a loaded save: SIM turns on options.debug (hazard_now) when asked.
	if debug_mode() and hud.data.arg_count(sim, "load_state") >= 2:
		sim.load_state(state, {"debug": true})
	else:
		sim.load_state(state)
	_after_world_change()
	if not _quiet:
		hud.toast(message, "save")

func export_save() -> void:
	var bytes: PackedByteArray = sim.save_bytes()
	var fname := "frontier-habitat-day%d.fhsave" % sim.util.day_number()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, fname, "application/octet-stream")
		hud.toast("The save file was sent to your downloads.", "save")
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.fhsave ; Frontier Habitat save"])
	dlg.current_file = fname
	dlg.file_selected.connect(func(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			hud.toast("The file could not be written.", "warn")
		else:
			f.store_buffer(bytes)
			f.close()
			hud.toast("Exported to " + path, "save"))
	hud.add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func import_save() -> void:
	if OS.has_feature("web"):
		_js_cb = JavaScriptBridge.create_callback(_on_web_file)
		JavaScriptBridge.get_interface("window").fhImportCb = _js_cb
		JavaScriptBridge.eval("(function(){var i=document.createElement('input');i.type='file';i.accept='.fhsave';i.onchange=function(){var f=i.files[0];if(!f)return;var r=new FileReader();r.onload=function(){var b=new Uint8Array(r.result);var s='';for(var k=0;k<b.length;k++)s+=String.fromCharCode(b[k]);window.fhImportCb(btoa(s));};r.readAsArrayBuffer(f);};i.click();})();", true)
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.fhsave ; Frontier Habitat save"])
	dlg.file_selected.connect(func(path): _import_bytes(FileAccess.get_file_as_bytes(path)))
	hud.add_child(dlg)
	dlg.popup_centered_ratio(0.6)

func _on_web_file(args: Array) -> void:
	on_title_leave_before_install()
	_import_bytes(Marshalls.base64_to_raw(String(args[0])))

## Imported data is validated (magic, schema, shape) before anything is replaced.
func _import_bytes(bytes: PackedByteArray) -> void:
	var res: Dictionary = Persistence.decode(bytes)
	if not res["ok"]:
		hud.toast("Import refused: " + String(res["error"]), "warn")
		return
	_install(res["state"], "Imported save: day %d." % (int(res["state"]["tick"]) / 6000 + 1))

# ---------------------------------------------------------------- automatic screenshots
func _take_shots() -> void:
	if _shots.is_empty():
		return
	var s: Dictionary = _shots[0]
	if sim.seconds() < float(s["at"]):
		return
	_shots.pop_front()
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/shot_%05d.png" % [s["dir"], int(s["at"])])
	if _shots.is_empty():
		get_tree().quit()
