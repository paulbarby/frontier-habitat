extends Node
## Keeps every window inside the view (Paul, 2026-09-25: "make it so info and UI windows can
## not open outside the view panel"). ONE place for the rule: every HUD panel, every screen
## frame and dialog, toasts, medal pop-ups, banners and the placement hint.
##
## Each frame, after every panel has placed itself (process_priority 1000 = it runs last):
## 1. a window whose rect leaves the view by any part moves back inside, MARGIN px from the edge;
## 2. a window larger than the view is asked to shrink: it gets `fit_height(px)` when it has that
##    method (HUD panels drop cards or scroll); screens scroll their content (ui/screens/screen.gd)
##    and cap compact dialogs to the view width;
## 3. so opening, content growing, a viewport or browser resize and any drag are all covered,
##    and new windows are covered as soon as they are children of the HUD or of the screen host.
## Cost: a rect test per window per frame, no allocation when nothing is outside.

const MARGIN := 8.0

var hud
var moved := 0          # windows moved since start (tests)

func _init() -> void:
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_d: float) -> void:
	enforce()

## All windows the rule covers (visible ones).
func windows() -> Array:
	var out: Array = []
	if hud == null or hud.hud_root == null:
		return out
	if hud.hud_root.visible:
		for c in hud.hud_root.get_children():
			if c is Control and (c as Control).visible and not _is_overlay(c):
				out.append(c)
	var host = hud.screens
	if host != null:
		for s in host.get_children():
			if s is Control and (s as Control).visible:
				if s.get("frame") is Control:
					out.append(s.frame)
		var pops = host.get("_popups")
		if pops is Control:
			for c in (pops as Control).get_children():
				if c is Control and (c as Control).visible:
					out.append(c)
	if hud.toasts != null and hud.toasts.visible:
		var box = hud.toasts.get("_box")
		if box is Control:
			for t in (box as Control).get_children():
				if t is Control:
					out.append(t)
	return out

## Full-screen layers that are not windows (the door-sector overlay).
static func _is_overlay(c: Control) -> bool:
	return c.mouse_filter == Control.MOUSE_FILTER_IGNORE and c.get_script() != null and String(c.get_script().resource_path).ends_with("sector_overlay.gd")

func enforce() -> void:
	var vp: Vector2 = hud.root.get_viewport_rect().size if hud != null and hud.root != null else Vector2.ZERO
	if vp.x <= 0.0:
		return
	if hud.screens != null:
		for s in hud.screens.get_children():
			if s.has_method("fit_view"):
				s.fit_view(vp)
	for w in windows():
		keep(w, vp)

## Moves (and when needed shrinks) one window into the view.
func keep(c: Control, vp: Vector2) -> void:
	var r: Rect2 = c.get_global_rect()
	var room := Vector2(vp.x - 2.0 * MARGIN, vp.y - 2.0 * MARGIN)
	if r.size.y > room.y + 0.5 and c.has_method("fit_height"):
		c.fit_height(room.y)
		r = c.get_global_rect()
	if r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= vp.x + 0.5 and r.end.y <= vp.y + 0.5:
		return
	var x: float = clampf(r.position.x, MARGIN, maxf(MARGIN, vp.x - MARGIN - r.size.x))
	var y: float = clampf(r.position.y, MARGIN, maxf(MARGIN, vp.y - MARGIN - r.size.y))
	c.global_position = Vector2(x, y)
	moved += 1

## For tests: every covered window rect that is not inside the view.
func outside(vp: Vector2) -> Array:
	var out: Array = []
	for w in windows():
		var r: Rect2 = w.get_global_rect()
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > vp.x + 0.5 or r.end.y > vp.y + 0.5:
			out.append("%s %s" % [_name(w), str(r)])
	return out

static func _name(c: Control) -> String:
	var s = c.get_script()
	var n: String = String(s.resource_path).get_file() if s != null else c.get_class()
	var p = c.get_parent()
	if p != null and p.get("screen_name") != null:
		n = "screen:" + String(p.get("screen_name"))
	return n
