extends CanvasLayer
## The interface root (docs/AAA_DESIGN.md §13). It answers four questions at all times:
## what is failing, why, how long is left, what can the player do. It reads the simulation
## through ui/data.gd and sends commands through main.submit(); it never edits state.
## Every status is a word or a number as well as a colour.
##
## Layout (logical 1600 x 900, anchored, so it holds from 1280 x 720 up):
##   top-left KPI bar · top-right time panel · right nav rail · bottom-left minimap · bottom build
##   bar · right inspector · left column: the panel manager (docs/UI_PANELS.md, Paul 2026-10-01):
##   urgent line, pop-ups and the tabbed dock (goals, alerts, events, traffic, requests, news).
##   The centre of the view stays free.
## Screens (research, goals, dashboard, ...) open over the HUD from ui/screens/.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const UiTheme = preload("res://ui/theme/ui_theme.gd")
const Data = preload("res://ui/data.gd")
const TopBar = preload("res://ui/hud/top_bar.gd")
const TimePanel = preload("res://ui/hud/time_panel.gd")
const NavRail = preload("res://ui/hud/nav_rail.gd")
const GoalsTracker = preload("res://ui/hud/goals_tracker.gd")
const AlertsPanel = preload("res://ui/hud/alerts_panel.gd")
const BuildBar = preload("res://ui/hud/build_bar.gd")
const Inspector = preload("res://ui/hud/inspector.gd")
const Minimap = preload("res://ui/hud/minimap.gd")
const PanelManager = preload("res://ui/hud/panel_manager.gd")
const PlaceHint = preload("res://ui/hud/place_hint.gd")
const ScreenHost = preload("res://ui/screens/screen_host.gd")
const Watchers = preload("res://ui/hud/watchers.gd")
const HazardPanel = preload("res://ui/hud/hazard_panel.gd")
const HazardBanner = preload("res://ui/hud/hazard_banner.gd")
const TrafficPanel = preload("res://ui/hud/traffic_panel.gd")
const SectorOverlay = preload("res://ui/hud/sector_overlay.gd")
const BoundsKeeper = preload("res://ui/hud/bounds_keeper.gd")
const WindowManager = preload("res://ui/wm/window_manager.gd")
const FindWindow = preload("res://ui/hud/find_window.gd")
const FindMarks = preload("res://ui/hud/find_marks.gd")
const PoiMarks = preload("res://ui/hud/poi_marks.gd")

const OVERLAYS := ["", "power", "water", "air", "walk", "hazard", "radiation", "sun", "resources"]

var main
var data
var root: Control
var hud_root: Control
var top_bar
var time_panel
var nav
var goals
var alerts
var build_bar
var inspector
var minimap
var toasts      # = panels (old name: hud.toast and the tests)
var panels      # the panel manager: the one place for alerts, events, requests and messages
var hint
var screens
var watchers
var hazard
var hazard_banner
var traffic
var sectors
var bounds      # keeps every window inside the view (ui/hud/bounds_keeper.gd)
var wm          # window manager (ui/wm/window_manager.gd, version 4)
var find        # Find window (version 4, §3.4)
var text_floor  # ui/text_floor.gd
var advisor     # Advisor window (version 4, §6)
var v4          # ui/v4_data.gd: orders, vehicles, reactors (SIM when live, else the mock)
var v5          # ui/v5_data.gd: people, social, the Rag (SIM when live, else preview data)
var v18         # ui/v18_data.gd: repair orders, the chain of command, work queues, production chains, package transport (V5 §18)
var rag         # "The Regolith Rag" window (version 5, §4.3)
var person      # personnel file window (version 5, §6.2)
var follow_hud  # follow view card (version 5, §3)
var unrest_banner # protest / strike / riot banner (version 5, §6.4)
var party_card    # parties now (version 5, §16): Events tab
var request_card  # a person asks the player (leave with a ship; version 5, §4.2)
var floor_sel   # floor selector of a multi-storey building (version 5, §7)
var orders      # Orders window (version 4, §5)
var work        # Work window: the queues of every department (version 5, §18.3)
var assign      # Who? window: Repair now and Assign to... (version 5, §18.1)
var work_card   # the dock card of the work queue
var chain       # production chain window (version 5, §18.4)
var transport_marks  # the package transport network on the map (version 5, §18.5)
var watch           # Watch mode: a hands-off tour for demos (version 5, §19.6)
var reactor_win # Reactor controls window (version 4, §4.2)
var reactor_banner
var find_marks  # marks of one structure type on the map, set from Find
var poi_marks   # points of interest in the 3D view (SIM milestone 7)
var codex_wide := false   # the codex Wide view, kept between openings (ui/screens/codex_screen.gd)
var base_filter := -1   # version 4: -1 = all bases, else the base id the alerts and inventory show
var cargo_choice := ""   # supply-run cargo picked in the Meridian panel ("" = the ship's kept choice)
var kpi := {}
var _clock := 0.0
var _beat := 0
var _hud_visible := true
var last_ms := 0.0      # time of the last HUD refresh (main.gd `spikes`)

# ---------------------------------------------------------------- construction
func _ready() -> void:
	layer = 10
	data = Data.new(main)
	v4 = load("res://ui/v4_data.gd").new(self)
	v5 = load("res://ui/v5_data.gd").new(self)
	v18 = load("res://ui/v18_data.gd").new(self)
	root = Control.new()
	root.name = "UiRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	add_child(root)
	hud_root = Control.new()
	hud_root.name = "Hud"
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_root)
	# Text floor: no text under 12 screen pixels at any scale (critic round 21).
	text_floor = load("res://ui/text_floor.gd").new()
	text_floor.hud = self
	add_child(text_floor)
	# One glass drawer for every HUD panel, window and toast (draw-call budget, version 4).
	var gs = load("res://ui/widgets/glass_shared.gd").new()
	gs.name = "GlassShared"
	gs.visible = load("res://ui/widgets/glass.gd").enabled
	hud_root.add_child(gs)
	load("res://ui/widgets/glass.gd").shared = gs
	sectors = _add(SectorOverlay.new())   # door sectors while placing rooms and corridors; under every panel
	find_marks = _add(FindMarks.new())    # Find: marks of one type on the map; under every panel
	poi_marks = _add(PoiMarks.new())      # points of interest tags; under every panel
	transport_marks = _add(load("res://ui/hud/transport_marks.gd").new())   # package transport network; under every panel
	minimap = _add(Minimap.new())
	build_bar = _add(BuildBar.new())
	hint = _add(PlaceHint.new())
	goals = _add(GoalsTracker.new())
	alerts = _add(AlertsPanel.new())
	hazard = _add(HazardPanel.new())
	hazard_banner = _add(HazardBanner.new())
	traffic = _add(TrafficPanel.new())
	panels = _add(PanelManager.new())     # over the map and the build bar, under the windows
	toasts = panels
	inspector = _add(Inspector.new())
	find = _add(FindWindow.new())
	advisor = _add(load("res://ui/hud/advisor_window.gd").new())
	orders = _add(load("res://ui/hud/orders_window.gd").new())
	assign = _add(load("res://ui/hud/assign_window.gd").new())
	work = _add(load("res://ui/hud/work_window.gd").new())
	work_card = _add(load("res://ui/hud/work_card.gd").new())
	chain = _add(load("res://ui/hud/chain_window.gd").new())
	reactor_win = _add(load("res://ui/hud/reactor_window.gd").new())
	rag = _add(load("res://ui/hud/rag_window.gd").new())
	person = _add(load("res://ui/hud/person_window.gd").new())
	follow_hud = _add(load("res://ui/hud/follow_hud.gd").new())
	unrest_banner = _add(load("res://ui/hud/unrest_banner.gd").new())
	request_card = _add(load("res://ui/hud/request_card.gd").new())
	party_card = _add(load("res://ui/hud/party_card.gd").new())
	floor_sel = _add(load("res://ui/hud/floor_selector.gd").new())
	reactor_banner = _add(load("res://ui/hud/reactor_banner.gd").new())
	top_bar = _add(TopBar.new())
	time_panel = _add(TimePanel.new())
	nav = _add(NavRail.new())
	screens = ScreenHost.new()
	screens.hud = self
	root.add_child(screens)
	watchers = Watchers.new(self)
	watch = load("res://ui/hud/watch_mode.gd").new()
	watch.hud = self
	add_child(watch)
	bounds = BoundsKeeper.new()
	bounds.hud = self
	add_child(bounds)
	wm = WindowManager.new()
	wm.hud = self
	add_child(wm)
	inspector.register_window(wm)
	find.register_window(wm)
	advisor.register_window(wm)
	orders.register_window(wm)
	assign.register_window(wm)
	work.register_window(wm)
	chain.register_window(wm)
	reactor_win.register_window(wm)
	rag.register_window(wm)
	person.register_window(wm)
	load("res://ui/theme/bubble_style.gd").apply(main.view)
	# Every module the game shows by itself goes into the panel manager's dock (docs/UI_PANELS.md §7).
	panels.host("goals", goals, "Mission", "goals", func(): return String(goals._head.text))
	panels.host("alerts", alerts, "Alerts", "sev_warning", func(): return String(alerts._summary.text))
	panels.host("alerts", work_card, "Work", "queue", func(): return String(work_card._line.text))
	panels.host("events", hazard_banner, "Countdown", "hazard", func(): return String(hazard_banner._title.text))
	panels.host("events", reactor_banner, "Reactor", "reactor", func(): return String(reactor_banner._text.text))
	panels.host("events", unrest_banner, "Unrest", "people", func(): return String(unrest_banner._text.text))
	panels.host("events", party_card, "Parties", "music", func(): return "%d on" % int(party_card.count))
	panels.host("events", hazard, "Hazard forecast", "meteor", func(): return String(hazard._head_next.text))
	panels.host("traffic", traffic, "Ships", "ship", func(): return String(traffic._sub.text))
	panels.host("requests", request_card, "Requests", "heart", func(): return "%d open" % v5.requests().size())

func _add(m: Control) -> Control:
	m.set("hud", self)
	hud_root.add_child(m)
	return m

# ---------------------------------------------------------------- refresh
func _process(delta: float) -> void:
	if main == null or main.sim == null:
		return
	var t0: int = Time.get_ticks_usec()
	_refresh(delta)
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0

func _refresh(delta: float) -> void:
	hint.frame()
	_sync_follow()
	_clock += delta
	if _clock < 0.2:
		return
	_clock = 0.0
	_beat += 1
	kpi = data.kpis()
	if hud_root.visible:
		# Fast group, 5 Hz: numbers the player watches. Slow group, 2.5 Hz, alternating.
		top_bar.refresh()
		time_panel.refresh()
		inspector.refresh()
		find.refresh()
		orders.refresh()
		work.refresh()
		assign.refresh()
		chain.refresh()
		hazard.refresh()
		hazard_banner.refresh()
		traffic.refresh()
		if _beat % 2 == 0:
			goals.refresh()
			alerts.refresh()
			work_card.refresh()
		else:
			nav.refresh()
			build_bar.refresh()
			minimap.refresh()
	screens.refresh()
	watchers.check()

## Base switcher (top bar, V4_DESIGN §2): -1 = all bases. A base moves the camera to its core.
func set_base_filter(id: int) -> void:
	base_filter = id
	var s = main.sim
	if id >= 0 and "bases" in s and s.bases != null:
		for b in s.bases.list():
			if int(b["id"]) == id and b.get("pos") != null:
				main.focus_on(b["pos"])
	alerts.refresh()
	var top = screens.top_screen()
	if top != null and String(top.get("screen_name")) == "inventory" and top.has_method("rebuild_tab"):
		top.rebuild_tab()

## Name of the filtered base, "" for all bases.
func base_filter_name() -> String:
	if base_filter < 0 or not ("bases" in main.sim) or main.sim.bases == null:
		return ""
	return String(main.sim.bases.name_of(base_filter))

## Advisor window (key N, or the nav rail).
func toggle_advisor() -> void:
	advisor.toggle()

## Find window (/ or Ctrl+F, or the nav rail).
## Opens the personnel file of a person (tab: "file", "social" or "review").
func open_person(id: int, t: String = "") -> void:
	person.open(id, t)

## The follow view started (id) or ended (-1): the follow card shows, the rest of the HUD dims
## (time controls, toasts, the Rag, the personnel file and the banners stay bright).
## One follow view whatever started it (critic round 41: a debug command that called view.follow_start showed the
## full HUD and no card). Each frame: when the view follows somebody the HUD does not know, or no longer
## follows somebody it shows, the HUD takes the same state as after V.
var _follow_seen := -1
var _follow_dock_saved := false
var _follow_dock_min := false
func _sync_follow() -> void:
	if main == null or main.view == null or follow_hud == null:
		return
	var fid: int = int(main.view.follow_id) if main.in_follow() else -1
	if fid == _follow_seen and follow_hud.visible == (fid >= 0):
		return
	if fid >= 0 and (main.view.selected_kind != "agent" or int(main.view.selected_id) != fid):
		main.select("agent", fid)
	follow_changed(fid)

func follow_changed(id: int) -> void:
	_follow_seen = id
	load("res://ui/theme/bubble_style.gd").apply(main.view)
	follow_hud.show_for(id)
	# The left dock folds to its tabs while you follow (the follow card holds the top left) and comes back as it was.
	if panels != null:
		if id >= 0 and not _follow_dock_saved:
			_follow_dock_saved = true
			_follow_dock_min = bool(panels.minimised)
			panels.minimise_dock(true)
		elif id < 0 and _follow_dock_saved:
			_follow_dock_saved = false
			panels.minimise_dock(_follow_dock_min)
	var dim: float = 0.35 if id >= 0 else 1.0
	for m in [minimap, build_bar, nav, top_bar, inspector, panels._dock if panels != null else null]:
		if m != null:
			(m as CanvasItem).modulate.a = dim
	if id >= 0 and inspector != null:
		inspector.visible = false
	if poi_marks != null:
		poi_marks.queue_redraw()   # no POI tags in the follow view

## An Easter egg was found (V5 §4.5): the device profile keeps it (the codex shows found eggs), a toast.
const EGG_TEXT := {"dance": ["Dance Floor Director", "You found the dance code. The whole corridor dances."],
	"arcade": ["Prism Shift", "You found the arcade in the gaming lounge."], "dev": ["The dev in the dome", "P. Barby visited the dome."]}
func egg_found(kind: String, _who: int = -1) -> void:
	var Profile = load("res://ui/profile.gd")
	var d: Dictionary = Profile.data()
	if typeof(d.get("eggs")) != TYPE_DICTIONARY:
		d["eggs"] = {}
	var first: bool = not d["eggs"].has(kind)
	d["eggs"][kind] = int(main.sim.state.get("tick", 0))
	Profile._save()
	var e: Array = EGG_TEXT.get(kind, [kind.capitalize(), "You found a secret."])
	toast(("SECRET FOUND: %s. %s" if first else "%s. %s") % [e[0], e[1]], "info", "sparkle")

func eggs_found() -> Dictionary:
	var d: Dictionary = load("res://ui/profile.gd").data()
	var out: Dictionary = (d.get("eggs", {}) as Dictionary).duplicate() if typeof(d.get("eggs")) == TYPE_DICTIONARY else {}
	# Version 5: the eggs this colony found (SIM sim/eggs.gd state.v5.eggs: prism_shift, barby, dance)
	# count too; the codex names them arcade, dev and dance.
	var se: Dictionary = main.sim.state.get("v5", {}).get("eggs", {}) if main != null and main.sim != null else {}
	for k in se:
		out[{"prism_shift": "arcade", "barby": "dev"}.get(String(k), String(k))] = se[k]
	return out

func toggle_rag() -> void:
	rag.toggle()

## The Work window (key M, or the nav rail).
func toggle_work() -> void:
	work.toggle()

## The chain window for an item (the alert's Show chain button, the codex).
func open_chain(item: String) -> void:
	chain.open_item(item)

func toggle_find() -> void:
	find.toggle()

## After a new game, a load or an import: every module starts again from the new state.
func rebuild_all() -> void:
	if watch != null and watch.active:
		watch.stop()
	kpi = data.kpis() if main != null and main.sim != null else {}
	screens.close_all()
	for m in [top_bar, time_panel, nav, goals, alerts, build_bar, inspector, minimap, hazard, traffic]:
		m.rebuild()
	find_marks.set_def("")   # a new colony: the old marks mean nothing
	poi_marks.target = -1
	poi_marks._poll = 1.0
	base_filter = -1
	watchers.reset()

func set_hud_visible(on: bool) -> void:
	_hud_visible = on
	hud_root.visible = on

func hud_visible() -> bool:
	return _hud_visible

# ---------------------------------------------------------------- public API (main.gd)
## A message (docs/UI_PANELS.md §5): the panel manager shows it (News; a pop-up when its type pops up).
## kind: info | good | warn | bad | award | research | goal | save. type: a panel manager type; when
## it is empty, it comes from the kind and the icon.
func toast(text: String, kind: String = "info", icon: String = "", type: String = "") -> void:
	if panels == null:
		return
	var t: String = type if type != "" else _type_of(kind, icon, text)
	var pr: String = {"bad": "critical", "warn": "warning", "good": "notice"}.get(kind, "info")
	var ic: String = icon if icon != "" else {"good": "sev_ok", "warn": "sev_warning", "bad": "sev_critical", "award": "medal", "research": "research", "goal": "goals", "save": "save"}.get(kind, "")
	panels.post(t, text, pr, ic)

const ICON_TYPE := {"heart": "people", "people": "people", "home": "people", "colonists": "people", "ship": "traffic", "credits": "traffic",
	"hazard": "hazard", "meteor": "hazard", "wind": "hazard", "shelter": "hazard", "turret": "hazard", "breach": "hazard", "wrench": "hazard",
	"build": "build", "upgrade": "build", "research": "research", "exotic": "research", "medal": "award", "trophy": "award",
	"goals": "goal", "sev_critical": "alert", "sev_warning": "alert", "lock": "unrest", "reactor": "reactor"}
func _type_of(kind: String, icon: String, _text: String) -> String:
	match kind:
		"award": return "award"
		"research": return "research"
		"goal": return "goal"
		"save": return "system"
	return String(ICON_TYPE.get(icon, "system"))

func open_modal(kind: String) -> void:
	open_screen(kind)

func open_screen(name: String, arg = null) -> bool:
	return screens.open(name, arg)

func close_modal() -> void:
	screens.close_top()

func is_modal_open() -> bool:
	return screens.is_open()

func screen_name() -> String:
	return screens.current()

func toggle_menu() -> void:
	if screens.is_open():
		screens.close_top()
	else:
		screens.open("menu")

func toggle_screen(name: String) -> void:
	if screens.current() == name:
		screens.close_top()
	else:
		screens.open(name)

## The overlay step of key O: the 3D view's overlays, then "transport" (the package transport network, drawn by the HUD).
func cycle_overlay() -> void:
	var all: Array = OVERLAYS + ["transport"]
	var cur: String = "transport" if transport_marks.on else String(main.view.overlay)
	set_overlay(all[(all.find(cur) + 1) % all.size()])

func set_overlay(name: String) -> void:
	transport_marks.set_on(name == "transport")
	main.view.set_overlay("" if name == "transport" else name)
	minimap.overlay_changed()

func overlay_name() -> String:
	return "transport" if transport_marks.on else String(main.view.overlay)

func selection_changed() -> void:
	if inspector != null:
		inspector.selection_changed()

func ask_demolish(id: int) -> void:
	var chk: Dictionary = main.sim.build.can_demolish(id)
	var b: Dictionary = main.sim.state["buildings"].get(id, {})
	if b.is_empty():
		return
	if not chk["ok"]:
		hint.ask("%s cannot be removed" % b["name"], chk["warnings"], Callable(), "", false)
		return
	if chk["code"] == "cancel":
		main.submit("cancel", {"id": id})
		return
	var w: Array = (chk["warnings"] as Array).duplicate()
	w.append("Half of its materials come back. Stock inside is put on the ground.")
	# At the bottom edge, in the placement hint: no window over the view (Paul, 2026-10-03).
	hint.ask("Remove %s?" % b["name"], w, func(): main.submit("demolish", {"id": id}), "Remove", true)

func confirm(title: String, lines: Array, on_yes: Callable, yes_text: String = "Yes", danger: bool = false) -> void:
	screens.confirm(title, lines, on_yes, yes_text, danger)

func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for res in cost:
		parts.append("%d %s" % [int(cost[res]), data.item_name(String(res)).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "nothing"

## True while the colony is in danger: a hazard going on now that is not covered, a critical
## alert, or a hull breach. The music director plays the tension track then (V3_1 §2.1).
func tension_now() -> bool:
	for r in data.hazard_active():
		if not bool(r.get("countered", false)):
			return true
	for inc in main.sim.alerts.incidents():
		var issue: Dictionary = inc.get("issue", {})
		if not bool(issue.get("live", true)):
			continue
		if int(issue.get("severity", 1)) >= 3 or String(issue.get("code", "")) == "breach":
			return true
	return false

## Space on the right that the inspector covers (toasts move left of it).
func right_inset() -> float:
	return inspector.width_used() if inspector != null else 0.0
