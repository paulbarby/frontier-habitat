extends CanvasLayer
## The interface root (docs/AAA_DESIGN.md §13). It answers four questions at all times:
## what is failing, why, how long is left, what can the player do. It reads the simulation
## through ui/data.gd and sends commands through main.submit(); it never edits state.
## Every status is a word or a number as well as a colour.
##
## Layout (logical 1600 x 900, anchored, so it holds from 1280 x 720 up):
##   top-left KPI bar · top-right time panel · right nav rail · left goals + alerts ·
##   bottom-left minimap · bottom build bar · right inspector · top-right toasts ·
##   hazard forecast right of the goals · hazard banner top centre (version 3).
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
const Toasts = preload("res://ui/hud/toasts.gd")
const PlaceHint = preload("res://ui/hud/place_hint.gd")
const ScreenHost = preload("res://ui/screens/screen_host.gd")
const Watchers = preload("res://ui/hud/watchers.gd")
const HazardPanel = preload("res://ui/hud/hazard_panel.gd")
const HazardBanner = preload("res://ui/hud/hazard_banner.gd")

const OVERLAYS := ["", "power", "water", "air", "walk", "hazard"]

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
var toasts
var hint
var screens
var watchers
var hazard
var hazard_banner
var cargo_choice := ""   # supply-run cargo picked in the Meridian panel ("" = the ship's kept choice)
var kpi := {}
var _clock := 0.0
var _beat := 0
var _hud_visible := true

# ---------------------------------------------------------------- construction
func _ready() -> void:
	layer = 10
	data = Data.new(main)
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
	minimap = _add(Minimap.new())
	build_bar = _add(BuildBar.new())
	hint = _add(PlaceHint.new())
	goals = _add(GoalsTracker.new())
	alerts = _add(AlertsPanel.new())
	hazard = _add(HazardPanel.new())
	hazard_banner = _add(HazardBanner.new())
	inspector = _add(Inspector.new())
	top_bar = _add(TopBar.new())
	time_panel = _add(TimePanel.new())
	nav = _add(NavRail.new())
	screens = ScreenHost.new()
	screens.hud = self
	root.add_child(screens)
	toasts = Toasts.new()
	toasts.hud = self
	root.add_child(toasts)
	watchers = Watchers.new(self)

func _add(m: Control) -> Control:
	m.set("hud", self)
	hud_root.add_child(m)
	return m

# ---------------------------------------------------------------- refresh
func _process(delta: float) -> void:
	if main == null or main.sim == null:
		return
	hint.frame()
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
		hazard.refresh()
		hazard_banner.refresh()
		if _beat % 2 == 0:
			goals.refresh()
			alerts.refresh()
		else:
			nav.refresh()
			build_bar.refresh()
			minimap.refresh()
	screens.refresh()
	watchers.check()

## After a new game, a load or an import: every module starts again from the new state.
func rebuild_all() -> void:
	kpi = data.kpis() if main != null and main.sim != null else {}
	screens.close_all()
	for m in [top_bar, time_panel, nav, goals, alerts, build_bar, inspector, minimap, hazard]:
		m.rebuild()
	watchers.reset()

func set_hud_visible(on: bool) -> void:
	_hud_visible = on
	hud_root.visible = on
	toasts.visible = on

func hud_visible() -> bool:
	return _hud_visible

# ---------------------------------------------------------------- public API (main.gd)
func toast(text: String, kind: String = "info", icon: String = "") -> void:
	if toasts != null:
		toasts.push(text, kind, icon)

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

func cycle_overlay() -> void:
	var i: int = (OVERLAYS.find(main.view.overlay) + 1) % OVERLAYS.size()
	set_overlay(OVERLAYS[i])

func set_overlay(name: String) -> void:
	main.view.set_overlay(name)
	minimap.overlay_changed()

func selection_changed() -> void:
	if inspector != null:
		inspector.selection_changed()

func ask_demolish(id: int) -> void:
	var chk: Dictionary = main.sim.build.can_demolish(id)
	var b: Dictionary = main.sim.state["buildings"].get(id, {})
	if b.is_empty():
		return
	if not chk["ok"]:
		screens.confirm("%s cannot be removed" % b["name"], chk["warnings"], Callable(), "", false)
		return
	if chk["code"] == "cancel":
		main.submit("cancel", {"id": id})
		return
	var w: Array = (chk["warnings"] as Array).duplicate()
	w.append("Half of its materials come back. Stock inside is put on the ground.")
	screens.confirm("Remove %s?" % b["name"], w, func(): main.submit("demolish", {"id": id}), "Remove", true)

func confirm(title: String, lines: Array, on_yes: Callable, yes_text: String = "Yes", danger: bool = false) -> void:
	screens.confirm(title, lines, on_yes, yes_text, danger)

func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for res in cost:
		parts.append("%d %s" % [int(cost[res]), data.item_name(String(res)).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "nothing"

## Space on the right that the inspector covers (toasts move left of it).
func right_inset() -> float:
	return inspector.width_used() if inspector != null else 0.0
