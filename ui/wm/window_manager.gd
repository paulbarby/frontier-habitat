extends Node
## Window manager (docs/V4_DESIGN.md §7): one system for every floating window.
## - Windows register once: WM.register(window, id, handle, default_place). `handle` is the title
##   bar: drag it to move the window.
## - Predictable places: a window opens where it was last left (per window, remembered in
##   user://windows.json as fractions of the free space, so it survives a resize), else at its
##   default place inside the work area (the view minus the top bar and the build bar).
## - Snap: at the end of a drag, an edge within SNAP px of a work-area edge or of another window's
##   edge lines up with it.
## - Stacking: a click on a window brings it to the front; the order is also the Esc order.
## - Esc closes the last window first (close_last); close_all closes every window.
## - The nav rail is not part of the work area; a window never stays over it. The goals, hazard
##   and traffic panels are snap targets, and fold while a window covers them (critic round 15).
## - Bounds (v3.1 rule): ui/hud/bounds_keeper.gd keeps every window inside the view, also while
##   dragging; the drag itself stops the title bar at the view edges.
## A window is any Control. Optional methods on it: wm_close() (else it is hidden), wm_title().

const SNAP := 14.0
const PATH := "user://windows.json"

var hud
var _wins := {}          # id -> {win, handle, place: Callable}
var order: Array = []    # ids, back to front (last = top, closes first)
var _drag = null         # {id, offset}
var _saved := {}
var _last_wa := Rect2()   # work area at the last frame: default-placed windows follow a change
var _loaded := false

var _folded := {}        # HUD panel -> its unfolded global rect (critic round 15, fix 3)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## The HUD panels a window may cover: they fold (collapse to their header) while a window lies
## over them, and open again when it leaves. Each has `collapsed` and `_toggle()`.
func foldable() -> Array:
	var out: Array = []
	for k in ["goals", "alerts", "hazard", "traffic"]:
		var p = hud.get(k) if hud != null else null
		if p != null and is_instance_valid(p) and p.visible and "collapsed" in p and (p.has_method("fold_set") or p.has_method("_toggle")):
			out.append(p)
	return out

## Each frame: (1) no window stays over the nav rail (critic round 15, fix 2): a window that grew
## or was dragged into the rail strip moves left, unless it is being dragged now; (2) the goals,
## hazard and traffic panels fold while a window covers them (fix 3).
func _process(_delta: float) -> void:
	if hud == null:
		return
	var wa: Rect2 = work_area()
	# The top bar can change height after a load (its rebuild): a window still at its default place
	# (never dragged, no remembered place) goes to the new default place.
	if not wa.is_equal_approx(_last_wa):
		_last_wa = wa
		for id2 in order:
			if bool(_wins[id2].get("auto", false)) and (_wins[id2]["win"] as Control).visible and (_drag == null or String(_drag["id"]) != id2):
				place(id2)
	var rects: Array = []
	for id in order:
		var w: Control = _wins[id]["win"]
		if not w.visible:
			continue
		if _drag == null or String(_drag["id"]) != id:
			var r: Rect2 = w.get_global_rect()
			if r.end.x > wa.end.x + 0.5 and r.size.x <= wa.size.x:
				w.global_position.x = wa.end.x - r.size.x
		rects.append(w.get_global_rect())
	for p in foldable():
		var own: Rect2 = _folded.get(p, (p as Control).get_global_rect())
		var hit := false
		for r in rects:
			if (r as Rect2).grow(-2.0).intersects(own):
				hit = true
				break
		if hit and not _folded.has(p):
			if not p.collapsed:
				_folded[p] = own
				_fold(p, true)
		elif not hit and _folded.has(p):
			_folded.erase(p)
			if p.collapsed:
				_fold(p, false)
	for p in _folded.keys():
		if not is_instance_valid(p):
			_folded.erase(p)

## Folds or opens a HUD panel: fold_set(on) when it has one (the alerts panel, whose _toggle(key)
## opens a card's consequences), else _toggle().
func _fold(p, on: bool) -> void:
	if p.has_method("fold_set"):
		p.fold_set(on)
	elif p.collapsed != on:
		p._toggle()

## Names of the HUD panels folded now under a window (tests).
func folded_names() -> Array:
	var out: Array = []
	for p in _folded:
		if is_instance_valid(p):
			out.append(String(p.name) if p.name != "" else p.get_script().resource_path.get_file())
	return out

## Registers a window. default_place: Callable(win_size: Vector2, work: Rect2) -> Vector2.
func register(win: Control, id: String, handle: Control, default_place: Callable) -> void:
	_load()
	_wins[id] = {"win": win, "handle": handle, "place": default_place}
	win.set_meta("wm_id", id)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.gui_input.connect(func(ev): _handle_input(id, ev))
	win.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			raise(id))
	win.visibility_changed.connect(func(): _on_visibility(id))

## The free part of the view for windows: below the top bar, above the build bar tabs.
func work_area() -> Rect2:
	var vp: Vector2 = hud.root.get_viewport_rect().size
	var top: float = 8.0
	if hud.top_bar != null and hud.top_bar.visible:
		top = hud.top_bar.get_global_rect().end.y + 8.0
	var bottom: float = vp.y - 8.0
	if hud.build_bar != null and hud.build_bar.has_method("tabs_top"):
		bottom = minf(bottom, float(hud.build_bar.tabs_top()) - 8.0)
	var right: float = vp.x - 70.0   # the nav rail (46 px buttons, 8 px from the edge) and 8 px gap
	if hud.nav != null and hud.nav.visible:
		right = minf(right, hud.nav.get_global_rect().position.x - 8.0)
	return Rect2(8.0, top, maxf(100.0, right - 8.0), maxf(100.0, bottom - top))

func _on_visibility(id: String) -> void:
	var w: Control = _wins[id]["win"]
	if w.visible:
		place(id)
		raise(id)
	else:
		order.erase(id)

## Puts a window at its remembered place, else its default place (clamped into the work area).
func place(id: String) -> void:
	var rec: Dictionary = _wins[id]
	var w: Control = rec["win"]
	var sz: Vector2 = w.get_combined_minimum_size().max(w.size)
	var wa: Rect2 = work_area()
	var pos: Vector2
	if _saved.has(id):
		var f: Array = _saved[id]
		pos = wa.position + Vector2(float(f[0]) * maxf(0.0, wa.size.x - sz.x), float(f[1]) * maxf(0.0, wa.size.y - sz.y))
		rec["auto"] = false
	else:
		pos = (rec["place"] as Callable).call(sz, wa)
		rec["auto"] = true
	w.global_position = _clamp(pos, sz, wa)

func _clamp(pos: Vector2, sz: Vector2, wa: Rect2) -> Vector2:
	return Vector2(clampf(pos.x, wa.position.x, maxf(wa.position.x, wa.end.x - sz.x)), clampf(pos.y, wa.position.y, maxf(wa.position.y, wa.end.y - sz.y)))

func raise(id: String) -> void:
	var w: Control = _wins[id]["win"]
	order.erase(id)
	order.append(id)
	if w.get_parent() != null:
		w.get_parent().move_child(w, w.get_parent().get_child_count() - 1)

func _handle_input(id: String, ev: InputEvent) -> void:
	var w: Control = _wins[id]["win"]
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			raise(id)
			_drag = {"id": id, "offset": w.get_global_mouse_position() - w.global_position}
		elif _drag != null:
			_drag = null
			snap(id)
			remember(id)
		w.accept_event()
	elif ev is InputEventMouseMotion and _drag != null and String(_drag["id"]) == id:
		move_to(id, w.get_global_mouse_position() - _drag["offset"])
		w.accept_event()

## Moves a window (drag); the title bar never leaves the view.
func move_to(id: String, pos: Vector2) -> void:
	_wins[id]["auto"] = false
	var w: Control = _wins[id]["win"]
	var vp: Vector2 = hud.root.get_viewport_rect().size
	var hsz: Vector2 = (_wins[id]["handle"] as Control).size
	pos.x = clampf(pos.x, 8.0 - w.size.x + minf(w.size.x, 80.0), vp.x - minf(w.size.x, 80.0) - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - maxf(hsz.y, 24.0) - 8.0)
	w.global_position = pos

## Lines a window's edges up with work-area edges and other windows within SNAP px.
func snap(id: String) -> void:
	var w: Control = _wins[id]["win"]
	var r: Rect2 = w.get_global_rect()
	var wa: Rect2 = work_area()
	var xs: Array = [wa.position.x, wa.end.x]
	var ys: Array = [wa.position.y, wa.end.y]
	for oid in order:
		if oid == id:
			continue
		var o: Control = _wins[oid]["win"]
		if o.visible:
			var orr: Rect2 = o.get_global_rect()
			xs.append_array([orr.position.x, orr.end.x])
			ys.append_array([orr.position.y, orr.end.y])
	# The goals, hazard and traffic panels are snap targets too (their unfolded edges).
	for p in foldable():
		if p == hud.get("alerts"):
			continue   # the alerts panel folds but is no snap target: its height changes with every alert
		var pr: Rect2 = _folded.get(p, (p as Control).get_global_rect())
		xs.append(pr.end.x + 8.0)
		ys.append(pr.end.y + 8.0)
	var pos: Vector2 = r.position
	for x in xs:
		if absf(r.position.x - float(x)) < SNAP:
			pos.x = float(x)
		elif absf(r.end.x - float(x)) < SNAP:
			pos.x = float(x) - r.size.x
	for y in ys:
		if absf(r.position.y - float(y)) < SNAP:
			pos.y = float(y)
		elif absf(r.end.y - float(y)) < SNAP:
			pos.y = float(y) - r.size.y
	# Critic round 21, fix 2: when the drag ends, the window goes fully inside the work area (not
	# partly off-screen, not over the build bar). A window taller than the work area keeps its top
	# at the top of it.
	w.global_position = _clamp(pos, r.size, wa)

## Keeps the place of a window as fractions of the free work area.
func remember(id: String) -> void:
	if _wins.has(id):
		_wins[id]["auto"] = false
	var w: Control = _wins[id]["win"]
	var wa: Rect2 = work_area()
	var free: Vector2 = (wa.size - w.size).max(Vector2.ONE)
	var p: Vector2 = w.global_position - wa.position
	_saved[id] = [clampf(p.x / free.x, 0.0, 1.0), clampf(p.y / free.y, 0.0, 1.0)]
	_save()

func forget(id: String) -> void:
	_saved.erase(id)
	_save()

## Closes the top window. False when none is open.
func close_last() -> bool:
	for i in range(order.size() - 1, -1, -1):
		var id: String = order[i]
		var w: Control = _wins[id]["win"]
		if w.visible:
			_close(w)
			return true
	return false

func close_all() -> int:
	var n := 0
	for id in order.duplicate():
		var w: Control = _wins[id]["win"]
		if w.visible:
			_close(w)
			n += 1
	return n

func _close(w: Control) -> void:
	if w.has_method("wm_close"):
		w.wm_close()
	else:
		w.visible = false

func open_ids() -> Array:
	var out: Array = []
	for id in order:
		if (_wins[id]["win"] as Control).visible:
			out.append(id)
	return out

func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			_saved = d

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_saved))
		f.close()
