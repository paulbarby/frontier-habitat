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
const V5Data = preload("res://ui/v5_data.gd")
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
var _burn_ms := 0.0
var _t_sim := 0.0
var _t_view := 0.0
var _t_aud := 0.0
var _split := {"n": 0.0, "sim": 0.0, "view": 0.0, "hud": 0.0, "proc": 0.0, "frame": 0.0}
var _spikes: Array = []          # frame times over 100 ms since the last `spikes` command
# Web loading screen (Paul, 2026-09-29; the shell is templates/web_shell.src.html): the game reports
# its start-up to window.__fh_load(0..1, stage) and sets window.__fh.loaded when the first real frame
# shows (RENDER's load cover has lifted), so the loader fades straight onto the game.
var _load_done := false
var _load_frames := 0
var _load_cover_seen := false
var _load_last := -1

func _ready() -> void:
	_web_load(0.05, "Loading the colony", true)
	# Smallest desktop window. The browser canvas has no limit; the bounds keeper
	# (ui/hud/bounds_keeper.gd) keeps every window inside any view, tested down to 800 x 600.
	get_window().min_size = Vector2i(800, 600)
	view = WorldView.new()
	add_child(view)
	rig = CameraRig.new()
	add_child(rig)
	audio = Audio.new()
	audio.main = self
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
	if boot.has("scenario"):
		o["scenario"] = String(boot["scenario"])   # V4: "frontier" = the 2,560 m planet
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
		"rsearch":
			# Research screen: type in the project search ("rsearch" alone clears it); Enter step.
			var rs = hud.screens.top_screen()
			if rs == null or not rs.has_method("goto_first_match"):
				return "open research first"
			rs._search.text = " ".join(w.slice(1))
			rs.apply_search()
			rs.goto_first_match()
			return rs._match_label.text
		"storage":
			# storage <def> : read only, for screenshots and tests: "id used/cap full|free" of each
			# structure of that type (ui/storage.gd summary).
			var S = load("res://ui/storage.gd")
			var outs: Array = []
			for sid in sim.state["buildings"]:
				var sb: Dictionary = sim.state["buildings"][sid]
				if w.size() > 1 and String(sb["def"]) != w[1]:
					continue
				var sm: Dictionary = S.summary(sim, sb)
				if int(sm["cap"]) > 0:
					outs.append("%d %d/%d %s" % [int(sid), int(sm["used"]), int(sm["cap"]), "full" if bool(sm["full"]) else "free"])
			return ", ".join(outs)
		"codexwide":
			# Codex: Wide view on (1) or off (0); no argument toggles.
			var cs = hud.screens.top_screen()
			if cs == null or not cs.has_method("set_wide"):
				return "open codex first"
			cs.set_wide((w[1] != "0") if w.size() > 1 else not cs.wide)
			return "wide %s" % str(cs.wide)
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
				# tool corridor|cable [from_id [x y]]: the first end already chosen.
				start_link(w[1])
				if w.size() > 2 and sim.state["buildings"].has(int(w[2])):
					link_from = int(w[2])
				forced_hover = Vector2(float(w[3]), float(w[4])) if w.size() > 4 else null
				return "ok"
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
			if w.size() > 4:
				o["scenario"] = w[4]
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
			if w.size() > 1 and (w[1] == "agent" or w[1] == "visitor"):
				var want: int = int(w[2]) if w.size() > 2 else 0
				var k := 0
				for aid in sim.state["agents"]:
					if sim.state["agents"][aid]["state"] == "alive" and (w[1] == "agent" or hud.data.is_visitor(sim.state["agents"][aid])):
						if k == want:
							return str(aid)
						k += 1
				return "not found"
			for bid2 in sim.state["buildings"]:
				if w.size() > 1 and sim.state["buildings"][bid2]["def"] == w[1]:
					return str(bid2)
			return "not found"
		# ---- version 3.1 audio (docs/V3_1_DESIGN.md §1, §2)
		"volume":
			# volume <master|music|sfx|ui|ambience> <0..1>: the Settings sliders.
			if w.size() < 3:
				return "volume <bus> <0..1>"
			var key: String = "vol_" + w[1].to_lower()
			if not Settings.DEFAULTS.has(key):
				return "unknown bus"
			Settings.set_value(key, clampf(float(w[2]), 0.0, 1.0))
			apply_settings()
		"music":
			return audio.describe()
		"mus":
			# mus <title|day|night|tension|auto>: fixes the music state (tests); auto = from the game.
			audio.music.force = "" if w.size() < 2 or w[1] == "auto" else w[1]
			return audio.describe()
		"maxfps":
			# maxfps <n>: Engine.max_fps (0 = no cap). Web warning (measured 2026-09-25): a cap below
			# the display rate silences the audio of the web build. Use `burn` to test a slow machine.
			Engine.max_fps = maxi(0, int(w[1])) if w.size() > 1 else 0
		"prof":
			# prof: times the heavier HUD work in this build (ms each).
			var out: Array = []
			for spec in [["minimap_paint", func(): hud.minimap._paint()], ["kpis", func(): hud.data.kpis()],
					["goals", func(): hud.goals.refresh()], ["hazard", func(): hud.hazard.refresh()], ["sim_step", func(): sim.step()]]:
				var t0: int = Time.get_ticks_usec()
				(spec[1] as Callable).call()
				out.append("%s=%.1f" % [spec[0], float(Time.get_ticks_usec() - t0) / 1000.0])
			return " ".join(out)
		"simprof":
			# simprof <n>: runs n simulation ticks now; returns mean, max and the ticks over 50 ms.
			var n: int = int(w[1]) if w.size() > 1 else 100
			var mx := 0.0
			var tot := 0.0
			var slow: Array = []
			for i in n:
				var t0: int = Time.get_ticks_usec()
				sim.step()
				var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
				tot += ms
				mx = maxf(mx, ms)
				if ms > 50.0:
					slow.append("t%d:%.0f" % [int(sim.state["tick"]), ms])
			return "mean=%.2f max=%.1f slow=%s" % [tot / maxf(1.0, n), mx, str(slow)]
		"split":
			# split: mean ms per frame since the last call (sim, view, hud, process, frame), then resets.
			var nn: float = maxf(1.0, float(_split["n"]))
			var sr: String = "frames=%d sim=%.2f view=%.2f hud=%.2f process=%.2f frame=%.2f step_ms=%.3f" % [int(nn), _split["sim"] / nn, _split["view"] / nn, _split["hud"] / nn, _split["proc"] / nn, _split["frame"] / nn, _step_ms]
			_split = {"n": 0.0, "sim": 0.0, "view": 0.0, "hud": 0.0, "proc": 0.0, "frame": 0.0}
			return sr
		"spikes":
			# spikes: frames longer than 50 ms since the last call ("time:ms:game seconds"), then resets.
			var sp: String = "n=%d %s" % [_spikes.size(), str(_spikes)]
			_spikes = []
			return sp
		"burn":
			# burn <ms>: busy-waits this long every frame, like a slow machine (0 = off). For the
			# audio latency test (tools/ui/audio_glitch_probe.mjs --burn).
			_burn_ms = maxf(0.0, float(w[1])) if w.size() > 1 else 0.0
		"world":
			# world <name> <x> <y>: a world sound at a content point (tests of V3_1 §2.2).
			if w.size() < 4:
				return "world <name> <x> <y>"
			return str(audio.world(w[1], Vector2(float(w[2]), float(w[3]))))
		# ---- version 3.1 ships (docs/V3_1_DESIGN.md §6.5)
		"traffic":
			# traffic: one line per ship and arrival. traffic <id> grant|deny: answers an arrival.
			if w.size() >= 3:
				submit("traffic_answer", {"id": int(w[1]), "grant": w[2] != "deny"})
				return "sent"
			var lines: Array = []
			for r in hud.traffic.rows():
				lines.append("%d %s %s %s %s pad=%d" % [int(r.get("id", -1)), String(r.get("kind", "")), String(r.get("phase", "")), String(r.get("answer", "")), hud.traffic.when_text(r), int(r.get("pad", -1))])
			var pads: Array = []
			for pid in sim.state["buildings"]:
				var pb: Dictionary = sim.state["buildings"][pid]
				if String(pb["def"]) == "landing_pad":
					pads.append("%d:%s:powered=%s:ship=%s" % [pid, pb["state"], str(pb.get("powered", "")), str(pb.get("ship", -1))])
			return "credits=%d pads=%s | %s" % [hud.data.credits(), str(pads), " | ".join(lines) if not lines.is_empty() else "no ships"]
		"ship":
			# ship <kind>: a ship of that kind in 60 s (or ship <kind> <seconds>). Needs debug=1.
			if not debug_mode():
				return "refused: start with debug=1"
			if w.size() < 2:
				return "ship <trader|shuttle|liner|medical|science|inspector> [seconds]"
			submit("traffic_now", {"kind": w[1], "in": float(w[2]) if w.size() > 2 else 60.0})
			return "submitted"
		"trade":
			# trade [id]: opens the trade screen (the first landed trader or science ship without an id).
			# trade <id> buy|sell <item> <n>: sends one trade command.
			if w.size() >= 5:
				var tp: Dictionary = {"id": int(w[1]), "buy": {}, "sell": {}}
				tp["buy" if w[2] == "buy" else "sell"][w[3]] = int(w[4])
				var tcid = submit("trade", tp)
				var tres: Dictionary = sim.cmds.results.get(tcid, {})
				return String(tres.get("code", "sent")) + ((" cost=%d" % int(tres["cost"])) if tres.has("cost") else "")
			if not hud.open_screen("trade", int(w[1]) if w.size() > 1 else null):
				return "unknown screen"
		"cable":
			# cable <id>: a cable from structure <id> to the nearest structure on a power network
			# (tests and screenshots). Returns the placement check code.
			var cid0: int = int(w[1]) if w.size() > 1 else -1
			if not sim.state["buildings"].has(cid0):
				return "not found"
			var from_p: Vector2 = sim.state["buildings"][cid0]["pos"]
			var best := -1
			var best_d := 1e9
			for oid in sim.state["buildings"]:
				var ob: Dictionary = sim.state["buildings"][oid]
				if oid == cid0 or String(ob.get("kind", "")) == "link" or ob["state"] != "active" or not sim.topo.power_comp.has(oid):
					continue
				var dd: float = (ob["pos"] as Vector2).distance_to(from_p)
				if dd < best_d and String(sim.place.check_link("cable", cid0, oid)["code"]) == "ok":
					best_d = dd
					best = oid
			if best == -1:
				return "no powered structure to join"
			submit("place_link", {"def": "cable", "a": cid0, "b": best})
			return "cable to %d (%.0f m)" % [best, best_d]
		"findblocked":
			# findblocked: two structures a corridor between which SIM refuses with door_blocked
			# (tests and screenshots): "a b", or "none".
			var ids: Array = sim.state["buildings"].keys()
			for ia in ids:
				var ba: Dictionary = sim.state["buildings"][ia]
				if String(ba.get("kind", "")) != "room" or ba["state"] != "active":
					continue
				for ib in ids:
					if ib == ia:
						continue
					var bb2: Dictionary = sim.state["buildings"][ib]
					if String(bb2.get("kind", "")) == "link" or (bb2["pos"] as Vector2).distance_to(ba["pos"]) > 40.0:
						continue
					if String(sim.place.check_link("corridor", ia, ib).get("code", "")) == "door_blocked":
						return "%d %d" % [ia, ib]
			return "none"
		"posof":
			# posof <id>: "x y rot_deg radius" of a structure.
			var pb2: Dictionary = sim.state["buildings"].get(int(w[1]) if w.size() > 1 else -1, {})
			if pb2.is_empty():
				return "not found"
			return "%.1f %.1f %.1f %.1f" % [pb2["pos"].x, pb2["pos"].y, rad_to_deg(float(pb2.get("rot", 0.0))), float(pb2.get("radius", 0.0))]
		"findspot":
			# findspot <def> [size] [min_m]: the first valid place on rings round the lander, at least
			# min_m away (tests and screenshots): "x y", or "none".
			if w.size() < 2:
				return "findspot <def> [size] [min_m]"
			var fsz: int = int(w[2]) if w.size() > 2 else 1
			var c0: Vector2 = hud.data.colony_center()
			var r0: float = float(w[3]) if w.size() > 3 else 20.0
			var rr: float = r0
			while rr < 260.0:
				for k in 36:
					var q: Vector2 = sim.place.snap_pos(c0 + Vector2(rr, 0).rotated(TAU * float(k) / 36.0))
					if _check_place(w[1], q, 0.0, fsz) == "ok":
						return "%.1f %.1f" % [q.x, q.y]
				rr += 6.0
			return "none"
		# ---- version 4 window manager (docs/V4_DESIGN.md §7)
		"closeall":
			return str(close_all_windows())
		"glass":
			# glass on|off: the background blur behind panels (Settings: Glass blur).
			Settings.set_value("glass", w.size() < 2 or w[1] != "off")
			apply_settings()
		"esc":
			# esc: as the Esc key without a tool: the last window closes.
			if hud.is_modal_open():
				hud.close_modal()
				return "screen"
			return "window" if hud.wm.close_last() else "none"
		"find":
			# find [text]: opens the Find window with that text; returns the number of matches and the first ones.
			hud.find.search(" ".join(w.slice(1)))
			var names: Array = []
			for r in hud.find.results.slice(0, 5):
				names.append("%s #%d %s" % [r["name"], r["id"], r["status"]])
			return "%d: %s" % [hud.find.results.size(), ", ".join(names)]
		"order":
			# order <kind> [x y]: gives the order to the order group, else the selected colonist.
			var ids: Array = hud.orders.group.duplicate() if not hud.orders.group.is_empty() else ([view.selected_id] if view.selected_kind == "agent" else [])
			var tgt = Vector2(float(w[2]), float(w[3])) if w.size() > 3 else null
			if hud.orders.visible:
				hud.orders._send(w[1] if w.size() > 1 else "stay", ids, tgt)   # through the window: its message and confirm step
				return hud.orders._msg.text
			var r: Dictionary = hud.v4.command("order_give", {"agents": ids, "kind": w[1] if w.size() > 1 else "stay", "target": tgt, "force": false})
			return "%s refused %s" % [r["code"], str(r["refused"])]
		"orders":
			# orders: opens the orders window with the selected colonist.
			hud.orders.open_for_selected()
			return str(hud.orders.group)
		"simcmd":
			# simcmd <kind> <json payload>: a SIM command (debug only; SIM refuses its debug commands
			# without debug). For screenshots with SIM's debug spawns (spawn_vehicle, place_finished).
			if not debug_mode():
				return "debug only"
			var pl = JSON.parse_string(" ".join(w.slice(2))) if w.size() > 2 else {}
			if typeof(pl) != TYPE_DICTIONARY:
				return "bad json"
			var cid = submit(w[1], pl)
			if sim.cmds.results.has(cid):
				return JSON.stringify(sim.cmds.results[cid])
			return "submitted %s" % str(cid)
		"reactor":
			# reactor [scram|restart|cool|evacuate]: opens the reactor window, or acts on the first
			# reactor (SIM commands). "reactor stage <ok|warning|critical|breach>": SIM's debug
			# reactor_stage (debug=1 only).
			hud.reactor_win.visible = true
			var rs0: Array = hud.v4.reactors()
			var res_txt := ""
			if w.size() > 2 and w[1] == "stage" and not rs0.is_empty():
				var cid = submit("reactor_stage", {"id": int(rs0[0]["id"]), "stage": w[2]})
				res_txt = JSON.stringify(sim.cmds.results.get(cid, {"submitted": true})) + " "
			elif w.size() > 1 and not rs0.is_empty():
				var rr: Dictionary = hud.v4.command("reactor_" + w[1], {"id": int(rs0[0]["id"])})
				res_txt = "%s %s " % [rr["code"], JSON.stringify(rr.get("result", {}))]
			hud.reactor_win.refresh(true)
			var rs: Array = hud.v4.reactors()
			return res_txt + ("none" if rs.is_empty() else "%s %s heat %.1f next %s in %.0f s" % [rs[0]["name"], rs[0]["phase"], float(rs[0]["heat"]), str(rs[0].get("next_stage", "")), float(rs[0]["next_phase_s"])])
		"rag":
			# rag [n]: opens "The Regolith Rag" on the newest issue (or back issue n, 0 = newest).
			hud.rag.visible = true
			if w.size() > 1:
				hud.rag.show_issue(clampi(int(w[1]), 0, maxi(0, hud.rag._issues.size() - 1)))
			var iss: Array = hud.rag._issues
			return "%d issues; shown %d: %s; %d name links" % [iss.size(), hud.rag.shown, String(iss[hud.rag.shown]["lead"]["headline"]) if not iss.is_empty() else "-", hud.rag.links.size()]
		"unrest":
			# unrest <calm|grumbling|slowdown|protest|strike|riot|off> [value]: shows that stage (the UI's
			# view only; SIM is not changed). For screenshots of the banner.
			if w.size() < 2 or w[1] == "off":
				hud.v5.unrest_override = {}
				return "off"
			var val: float = float(w[2]) if w.size() > 2 else {"calm": 5.0, "grumbling": 30.0, "slowdown": 45.0, "protest": 60.0, "strike": 75.0, "riot": 90.0}.get(w[1], 50.0)
			hud.v5.unrest_override = {"value": val, "stage": w[1], "causes": [{"text": "Low satisfaction", "delta": val * 0.7}, {"text": "Ration cuts seen as unfair", "delta": val * 0.3}], "demand": "Full rations now!"}
			hud.unrest_banner._update()
			return "unrest %s %d" % [w[1], int(val)]
		"shoulder":
			# shoulder [off|next]: the over-the-shoulder follow of the selected person (key V).
			if w.size() > 1 and w[1] == "off":
				follow_end()
				return "off"
			if w.size() > 1 and w[1] == "next":
				follow_next_person()
				return str(view.follow_id)
			if view.selected_kind != "agent":
				return "select a person first"
			return "following %d" % view.selected_id if follow_person(view.selected_id) else "cannot follow"
		"person":
			# person [tab]: opens the personnel file of the selected person (tab: file, social, review).
			# person ask <action>: the confirm of a review or discipline action (screenshots; nothing is sent).
			if view.selected_kind != "agent":
				return "select a person first"
			if w.size() > 2 and w[1] == "ask":
				hud.open_person(view.selected_id, "review")
				var is_review: bool = V5Data.REVIEWS.any(func(r): return String(r[0]) == w[2])
				var nm: String = w[2].capitalize()
				for r in V5Data.REVIEWS + V5Data.ACTIONS:
					if String(r[0]) == w[2]:
						nm = String(r[1])
				hud.person._ask(w[2], nm, "review" if is_review else "discipline")
				return "asked"
			hud.open_person(view.selected_id, w[1] if w.size() > 1 else "file")
			return "ok"
		"raglayout":
			# raglayout <standard|special|quiet|auto>: shows the Rag in that layout (screenshots, tests).
			hud.rag.force_layout = "" if w.size() < 2 or w[1] == "auto" else w[1]
			hud.rag.visible = true
			hud.rag.show_issue(maxi(0, hud.rag.shown))
			return hud.rag.layout
		"ragscroll":
			# ragscroll <px>: scrolls the Rag page (screenshots); returns the page height.
			hud.rag._scroll.scroll_vertical = int(w[1]) if w.size() > 1 else 0
			return "page %d, view %d" % [int(hud.rag._paper.size.y), int(hud.rag._scroll.size.y)]
		"advisor":
			# advisor: opens the advisor window and returns its tips, one per line.
			hud.advisor.visible = true
			hud.advisor.refresh(true)
			var lines: Array = []
			for tp in hud.advisor.tips:
				lines.append("%s: %s" % [tp["kind"], tp["title"]])
			return "\n".join(lines)
		"findlabels":
			# findlabels off|all|<category>: the label layer of the Find window.
			var which: String = "" if w.size() < 2 or w[1] == "off" else w[1]
			hud.find_marks.set_labels(which)
			var idx: int = hud.find._label_ids.find(which)
			if idx >= 0:
				hud.find._labels.select(idx)
			return "labels " + (which if which != "" else "off")
		"findmark":
			# findmark <def>|off: marks every structure of that type on the map.
			hud.find_marks.set_def("" if w.size() < 2 or w[1] == "off" else w[1])
			return "%d marked" % hud.find_marks.marks.size()
		"wm":
			# wm: open windows, back to front, with their rects.
			var parts: Array = []
			for wid in hud.wm.open_ids():
				parts.append("%s %s" % [wid, str(hud.wm._wins[wid]["win"].get_global_rect())])
			return " | ".join(parts) if not parts.is_empty() else "none"
		"drag":
			# drag <id> <x> <y>: moves a window as a drag would (title bar kept in view), then snaps
			# and remembers it.
			if w.size() < 4 or not hud.wm._wins.has(w[1]):
				return "drag <id> <x> <y>"
			hud.wm.move_to(w[1], Vector2(float(w[2]), float(w[3])))
			hud.wm.snap(w[1])
			hud.wm.remember(w[1])
			return str(hud.wm._wins[w[1]]["win"].get_global_rect())
		"minimap":
			# minimap zoom|whole
			hud.minimap.set_zoomed(w.size() > 1 and w[1] == "zoom")
		_:
			return "unknown command"
	return "ok"

# ---------------------------------------------------------------- start, load, title
## Wall-clock cap of the simulation steps in one frame (14 ms). The RENDER gates set it very
## high so a run does the same steps every time (the cap made the path check differ run to run).
var step_cap_us := 14000

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
	var scen: String = String(options.get("scenario", "tutorial"))
	if options.has("scenario"):
		options = options.duplicate()
		options.erase("scenario")
	if options.is_empty() or hud.data.arg_count(sim, "new_game") < 3:
		sim.new_game(seed_value, scen) if scen != "tutorial" else sim.new_game(seed_value)
	else:
		sim.new_game(seed_value, scen, options)
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
	# Critic round 21, fix 1: a large interface scale in a small window would leave no room for
	# the HUD. The scale is limited so the interface keeps a logical view of at least 1300 x 660
	# (the top bar, time panel, minimap and build bar fit side by side).
	var unscaled: Vector2 = get_viewport().get_visible_rect().size * get_tree().root.content_scale_factor
	sc = clampf(minf(sc, minf(unscaled.x / 1300.0, unscaled.y / 660.0)), 0.6, 2.0)
	if not get_viewport().size_changed.is_connected(_on_view_resized):
		get_viewport().size_changed.connect(_on_view_resized)
	if not is_equal_approx(get_tree().root.content_scale_factor, sc):
		get_tree().root.content_scale_factor = sc
	Glass.set_enabled(bool(Settings.get_value("glass")))
	rig.edge_pan = bool(Settings.get_value("edge_pan"))
	rig.pan_speed = float(Settings.get_value("camera_speed"))
	# Camera shake (quakes, landings, impacts): RENDER's rig and view read `shake_enabled`.
	_shake_on = bool(Settings.get_value("camera_shake"))
	for o in [rig, view]:
		if o != null and "shake_enabled" in o:
			o.set("shake_enabled", _shake_on)
	if audio != null:
		audio.apply_volumes()

## The view changed size: the interface-scale limit is checked again (apply_settings).
var _resizing := false
func _on_view_resized() -> void:
	if _resizing:
		return
	_resizing = true
	apply_settings.call_deferred()
	(func(): _resizing = false).call_deferred()

# ---------------------------------------------------------------- main loop
func _process(delta: float) -> void:
	if delta > 0.05 and _spikes.size() < 200:
		# "time:frame ms:game s|sim view hud (ms of the frame before)": the rest of a long frame is
		# engine work outside scripts (rendering, shader compiles, audio decode).
		_spikes.append("%.1fs:%dms:g%d|sim%.0f view%.0f hud%.0f aud%.0f" % [float(Time.get_ticks_msec()) / 1000.0, int(delta * 1000.0), int(sim.seconds()) if sim != null else -1,
			_t_sim, _t_view, hud.last_ms if hud != null else 0.0, _t_aud])
		_t_aud = 0.0
	var run_speed: int = 0 if paused_by_menu else speed
	if run_speed > 0 and not bool(sim.state["progress"]["lost"]):
		_acc += delta * run_speed
		var steps := 0
		var t0: int = Time.get_ticks_usec()
		_t_sim = 0.0
		while _acc >= TICK and steps < MAX_STEPS_PER_FRAME:
			_demo_drive()
			sim.step()
			_acc -= TICK
			steps += 1
			if Time.get_ticks_usec() - t0 > step_cap_us:
				break
		_t_sim = float(Time.get_ticks_usec() - t0) / 1000.0
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
	var tv0: int = Time.get_ticks_usec()
	view.sync(delta)
	_t_view = float(Time.get_ticks_usec() - tv0) / 1000.0
	_update_tool()
	_take_shots()
	if _boot_frames > 0:
		_boot_frames -= 1
	_proc_avg = lerpf(_proc_avg, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.05)
	# "split": where the process time goes (sim steps, view sync, HUD, whole process), means per frame.
	_split["n"] += 1.0
	_split["sim"] += _t_sim
	_split["view"] += _t_view
	_split["hud"] += float(hud.last_ms) if hud != null else 0.0
	_split["proc"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_split["frame"] += delta * 1000.0
	if _burn_ms > 0.0:
		var until: int = Time.get_ticks_usec() + int(_burn_ms * 1000.0)
		while Time.get_ticks_usec() < until:
			pass
	_fps_clock += delta
	if _fps_clock >= 0.5:
		_fps_clock = 0.0
		_fps = Engine.get_frames_per_second()
		if view.has_method("stats"):
			_fps = float(view.stats().get("fps", _fps))
		var ta0: int = Time.get_ticks_usec()
		audio.ambience(sim.util.is_night(), on_title)
		# Mood music (V3_1 §2.1): title, day, night or tension.
		audio.music.update(on_title, sim.util.is_night(), not on_title and hud.tension_now(), 0.5)
		_t_aud = float(Time.get_ticks_usec() - ta0) / 1000.0
	Boot.set_state(_hook, _boot_frames == 0, int(sim.state["tick"]), sim.util.day_number())
	Boot.set_extra(_hook, _fps, "title" if on_title and hud.screen_name() == "title" else hud.screen_name())
	_web_load_step()

## Web only. Reports a start-up stage to the loading screen of the HTML shell (0..1 of the game's part,
## which the shell shows as 90-100 %). first: also sets window.__fh.loaded = false, so the shell waits
## for the game's own end mark instead of its 1.5 s guess.
func _web_load(p: float, stage: String, first: bool = false) -> void:
	if not OS.has_feature("web"):
		return
	var pc: int = int(p * 100.0)
	if pc == _load_last and not first:
		return
	_load_last = pc
	var js: String = "window.__fh_load && window.__fh_load(%.3f, %s);" % [clampf(p, 0.0, 1.0), JSON.stringify(stage)]
	if first:
		js = "window.__fh = window.__fh || {ready:false, tick:0, day:0, last:'', fps:0, title:''}; window.__fh.loaded = false; " + js
	JavaScriptBridge.eval(js, true)

## Once a frame until the game is visible: "Building the planet" while the first frames build the
## world, "Preparing graphics" while RENDER's load cover warms the shaders (its hold time and fast
## frames give the progress), then loaded = true when the cover lifts (the first real frame). A start
## without a cover ends after 240 frames.
func _web_load_step() -> void:
	if _load_done or not OS.has_feature("web") or view == null:
		return
	_load_frames += 1
	var wc = view.get("_warm_cover")
	if wc != null:
		_load_cover_seen = true
	var lifted: bool = _load_cover_seen and wc == null
	if lifted or (not _load_cover_seen and _load_frames > 240) or _load_frames > 3600:
		_load_done = true
		if _hook != null:
			_hook["fh"].loaded = true
		_web_load(1.0, "Ready")
		return
	if wc != null:
		var hold: float = float(view.get("_cover_hold"))
		var fast: int = int(view.get("_cover_fast"))
		_web_load(0.55 + 0.4 * clampf(maxf(hold / 4.0, float(fast) / 20.0), 0.0, 1.0), "Preparing graphics")
	else:
		_web_load(0.3 + 0.25 * clampf(float(_load_frames) / 40.0, 0.0, 1.0), "Building the planet")

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

## Returns the command id. While paused the command is applied at once, so the caller can
## read sim.cmds.results[id] (main still toasts a refusal).
func submit(kind: String, payload: Dictionary):
	var cid = sim.submit(kind, payload)
	_sent.append(cid)
	if speed == 0 or paused_by_menu:
		# Paused mode still accepts plans and policy changes (spec 12): apply them now.
		sim.cmds.apply_pending()
		if bool(sim.state["topo_dirty"]):
			sim.topo.rebuild(true)
	return cid

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
		if code in ["locked", "locked_research"]:
			# The full requirement with the colony's progress (ui/data.gd lock_info), not SIM's bare
			# "This structure is not unlocked yet." (Paul was stuck on it, 2026-09-28).
			var li: Dictionary = d.lock_info(tool_def, tool_size)
			if String(li.get("full", "")) != "":
				info["reason"] = String(li["full"]).replace("\n", " ")
	info["ok"] = tool_ok
	# Builders walk from an airlock with air and must get back on one suit.
	var reach: float = sim.agents.suit_reach_metres()
	var away: float = sim.agents.nearest_air_metres(p) * 1.25
	if tool_ok and away > reach:
		info["warning"] = "About %d m on foot from the nearest airlock with air. Suit range is about %d m. Build an airlock nearer first." % [int(away), int(reach)]
	elif tool_ok and String(hud.data.bdef(tool_def).get("kind", "")) == "room" and not hud.data.blocked_sectors(tool_def, tool_size).is_empty():
		# Door sectors (V3.1): the ring shows them; R turns the room.
		info["warning"] = "Red on the ring: no corridor can join there (equipment%s). Turn the room with R." % (", chamber and porch" if tool_def == "airlock" else "")
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
			if cancel_pick():
				pass
			elif tool != "select":
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
			KEY_F:
				if k.ctrl_pressed or k.meta_pressed:
					hud.toggle_find()   # version 4 Find (V4_DESIGN §3.4)
				else:
					follow_selected()
			KEY_SLASH: hud.toggle_find()
			KEY_N: hud.toggle_advisor()   # version 4 advisor (V4_DESIGN §6)
			KEY_J: hud.toggle_rag()       # version 5 "The Regolith Rag" (V5_DESIGN §4.3)
			KEY_K: hud.toggle_screen("codex")   # version 4 codex (V4_DESIGN §6)
			KEY_O: hud.cycle_overlay()
			KEY_G: hud.toggle_screen("goals")
			KEY_T: hud.toggle_screen("research")
			KEY_C: hud.toggle_screen("dashboard")
			KEY_I: hud.toggle_screen("inventory")
			KEY_P: hud.toggle_screen("colonists")
			KEY_U: hud.toggle_screen("crew")   # version 5 crew: org chart, housing, academy
			KEY_V:
				# Version 5: V follows the selected person over the shoulder; without one, the awards.
				if in_follow():
					follow_end()
				elif view.selected_kind == "agent":
					follow_person(view.selected_id)
				else:
					hud.toggle_screen("awards")
			KEY_TAB:
				if in_follow():
					follow_next_person()
			KEY_PAGEUP: hud.floor_sel.step(1)
			KEY_PAGEDOWN: hud.floor_sel.step(-1)
			KEY_H: hud.set_hud_visible(not hud.hud_visible())
			KEY_F1: hud.toggle_screen("help")
			KEY_ESCAPE:
				# Shift+Esc closes every window (V4 window manager); Esc closes the last one first.
				if cancel_pick():
					pass
				elif in_follow() and not hud.is_modal_open():
					follow_end()
				elif k.shift_pressed:
					close_all_windows()
				elif tool != "select":
					cancel_tool()
				elif hud.is_modal_open():
					hud.close_modal()
				elif hud.wm != null and hud.wm.close_last():
					pass
				elif hud.build_bar.is_open():
					hud.build_bar.close_drawer()
				elif view.selected_kind != "":
					select("", -1)
				else:
					hud.toggle_menu()
			KEY_DELETE:
				if view.selected_kind == "building":
					hud.ask_demolish(view.selected_id)

## Point picking for orders (version 4): the next left click on the ground calls cb(point, pick)
## instead of the tool; right click or Esc cancels. The hint shows until then.
var pick_cb := Callable()
func pick_point(hint: String, cb: Callable) -> void:
	pick_cb = cb
	hud.toast(hint, "info", "follow")

func cancel_pick() -> bool:
	if not pick_cb.is_valid():
		return false
	pick_cb = Callable()
	hud.toast("Order cancelled.", "info")
	return true

func _left_click(shift: bool) -> void:
	if hover_point == null:
		return
	if pick_cb.is_valid():
		var cb: Callable = pick_cb
		pick_cb = Callable()
		cb.call(hover_point, hover_pick)
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

## Closes every window: the screens and the floating windows (V4_DESIGN §7).
func close_all_windows() -> int:
	var n: int = hud.screens.get_child_count() if hud.is_modal_open() else 0
	hud.screens.close_all()
	return n + (hud.wm.close_all() if hud.wm != null else 0)

# ---------------------------------------------------------------- V5 §3 follow view (UI side)
## The over-the-shoulder follow of a person: RENDER's camera (view.follow_start), the UI's follow HUD
## (ui/hud/follow_hud.gd), the rest of the HUD dimmed. Keys while following: Tab next person, Esc exit,
## the Konami code (§4.5 egg). Returns false when the person cannot be followed.
func follow_person(id: int) -> bool:
	if view == null or not view.has_method("follow_start") or not view.follow_start(id):
		hud.toast("This person cannot be followed now.", "warn", "follow")
		return false
	select("agent", id)
	if hud.is_modal_open():
		hud.close_modal()
	hud.follow_changed(id)
	return true

func follow_end() -> void:
	if view != null and view.has_method("follow_stop") and view.in_follow():
		view.follow_stop()
	hud.follow_changed(-1)

func in_follow() -> bool:
	return view != null and view.has_method("in_follow") and view.in_follow()

func follow_next_person() -> void:
	if in_follow():
		var nx: int = view.follow_next()
		if nx >= 0:
			select("agent", nx)
			hud.follow_changed(nx)

# Konami code (V5 §4.5, egg 3): ↑↑↓↓←→←→BA in the follow view.
const KONAMI := [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]
var _konami_i := 0
func _konami_key(code: int) -> bool:
	if code == KONAMI[_konami_i]:
		_konami_i += 1
		if _konami_i >= KONAMI.size():
			_konami_i = 0
			return true
	else:
		_konami_i = 1 if code == KONAMI[0] else 0
	return false

## The dance egg: SIM makes the person (and nearby friends) dance and gives the award when it has
## the command "egg"; the UI records the find for the codex and shows it at once.
func dance_egg() -> void:
	var id: int = view.follow_id if view != null else -1
	if id < 0:
		return
	submit("egg", {"kind": "dance", "agent": id})
	if view.has_method("egg_dance"):
		view.egg_dance(id)
	hud.egg_found("dance", id)

func _input(event: InputEvent) -> void:
	# In the follow view the camera takes the arrow keys: the code is read here, before it.
	if event is InputEventKey and event.pressed and not event.echo and in_follow():
		if _konami_key((event as InputEventKey).physical_keycode):
			dance_egg()

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
