extends Node
## Watch mode (V5_DESIGN §19.6; Paul, 2026-10-04): a hands-off tour for demos. RENDER's director (presentation/fx_watch.gd, API
## world_view.watch_start / watch_stop / watch_state) follows a person, then another interesting one, goes to what happens (a party, a
## fight, a wedding, a landing, an accident, a protest), fades between shots and draws the caption. This is the UI side: the key F2,
## the menu entry, the title-screen start, and the HUD: it is hidden while the tour runs and comes back when it ends. RENDER ends the tour
## on any key, mouse button or mouse move; this node sees it end (watch_state().active) and brings the HUD back.

var hud
var active := false
var _was_hud := true
var _t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func toggle() -> void:
	if active:
		stop()
	else:
		start()

func start() -> bool:
	if active or hud.main.sim == null or hud.main.on_title:
		return false
	hud.main.cancel_tool()
	hud.screens.close_all()
	if hud.main.in_follow():
		hud.main.follow_end()
	if not hud.main.view.watch_start():
		return false
	active = true
	_t = 0.0
	_was_hud = bool(hud.hud_root.visible)
	hud.set_hud_visible(false)
	return true

func stop() -> void:
	if not active:
		return
	active = false
	hud.main.view.watch_stop()
	hud.set_hud_visible(_was_hud)

## The caption (who and what) of the shot now, "" when none.
func caption() -> String:
	return String(hud.main.view.watch_state().get("caption", ""))

func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	# RENDER ended the tour (an input, or the colony changed): the HUD comes back.
	if hud.main.sim == null or hud.main.on_title or not bool(hud.main.view.watch_state().get("active", false)):
		if _t > 0.3:
			stop()
