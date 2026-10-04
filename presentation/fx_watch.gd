extends Node
## Watch mode for demos (V5 §19.6, Paul 2026-10-04): the follow camera on its own. It follows a person for a while,
## then switches to another interesting person; when an event with people happens (a party, a fight, a drama, a
## wedding, a landing, an accident, a protest) it jumps there and frames the people involved. Every change of person
## is a short fade through black. A caption names who and what. Any key, mouse button or a real mouse move ends it.
##
## API (UI): world_view.watch_start() / watch_stop() / watch_state() -> {active, id, who, what, caption, since}.
## `show_caption` = false when the UI draws its own caption from watch_state().

const HOLD := 28.0            # s on one person when nothing happens
const EVENT_HOLD := 22.0      # s on an event
const MIN_SHOT := 6.0         # s: no switch before this (except for a higher-ranked event)
const FADE := 0.35            # s each way
const EVENT_TTL := 60.0       # s: an event not shown by then is dropped
## log code -> [rank, what]
const EVENTS := {
	"party_drama_big": [9, "a drama at the party"], "fight": [9, "a fight"], "arrest": [8, "an arrest"],
	"wedding": [9, "a wedding"], "death": [7, "a loss"], "breach": [8, "a hull breach"], "toxic_leak": [8, "an accident"],
	"hazard_impact": [7, "an impact"], "unrest": [8, "a protest"], "unrest_response": [6, "a protest"],
	"party_drama": [7, "a scene at the party"], "party_start": [7, "a party"], "feud": [6, "a feud"],
	"breakup": [6, "a break-up"], "affair": [6, "an affair"], "couple": [5, "a new couple"], "date": [5, "a date"],
	"dance": [5, "dancing"], "birthday": [5, "a birthday"], "promotion": [4, "a promotion"], "graduated": [4, "a graduation"],
	"settlers": [6, "new settlers"], "ship_landing": [6, "a ship landing"], "discipline": [5, "a reprimand"],
}

var view
var sim
var active := false
var show_caption := true
var cur := {}                 # {id, who, what, rank, t}
var _queue: Array = []        # [{ids, what, rank, t0, pos}]
var _log_n := -1
var _t := 0.0
var _shot_t := 0.0
var _recent: Array = []
var _fade := 0.0              # 0 clear .. 1 black
var _fade_dir := 0
var _pending := {}
var _layer: CanvasLayer
var _black: ColorRect
var _label: Label
var _mouse_acc := 0.0

func setup(v) -> void:
	view = v
	sim = v.sim

func start() -> bool:
	if active:
		return true
	active = true
	_queue = []
	_recent = []
	_log_n = (sim.state.get("log", []) as Array).size()
	_shot_t = 999.0
	_mouse_acc = 0.0
	_ensure_overlay()
	_layer.visible = true
	_pick_person("", 0)
	return true

func stop() -> void:
	if not active:
		return
	active = false
	cur = {}
	_pending = {}
	_fade = 0.0
	_fade_dir = 0
	if _layer != null:
		_layer.visible = false

func state() -> Dictionary:
	return {"active": active, "id": int(cur.get("id", -1)), "who": String(cur.get("who", "")), "what": String(cur.get("what", "")),
		"caption": _caption(), "since": snappedf(_shot_t, 0.1)}

func _caption() -> String:
	if cur.is_empty():
		return ""
	var w: String = String(cur.get("what", ""))
	return String(cur.get("who", "")) + ((" - " + w) if w != "" else "")

## Any input ends it (§19.6): a key, a mouse button, or the mouse moved more than 24 px.
func _input(event: InputEvent) -> void:
	if not active:
		return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		stop()
	elif event is InputEventMouseMotion:
		_mouse_acc += (event as InputEventMouseMotion).relative.length()
		if _mouse_acc > 24.0:
			stop()

func sync(delta: float) -> void:
	if not active:
		return
	_t += delta
	_shot_t += delta
	_mouse_acc = maxf(0.0, _mouse_acc - delta * 40.0)
	_read_log()
	# the fade: out, switch at black, in
	if _fade_dir != 0:
		_fade = clampf(_fade + float(_fade_dir) * delta / FADE, 0.0, 1.0)
		if _fade_dir > 0 and _fade >= 1.0:
			_apply(_pending)
			_pending = {}
			_fade_dir = -1
		elif _fade_dir < 0 and _fade <= 0.0:
			_fade_dir = 0
	if _black != null:
		_black.color = Color(0, 0, 0, _fade)
	if _label != null:
		_label.visible = show_caption and _fade < 0.5 and not cur.is_empty()
		_label.text = _caption()
	if _fade_dir != 0:
		return
	# the person is gone (left, in a vehicle, died): another one
	if not view.in_follow() and cur.has("id") and not bool(cur.get("place", false)):
		_pick_person("", 0)
		return
	# an event worth a jump
	_queue = _queue.filter(func(e): return _t - float(e["t0"]) < EVENT_TTL)
	if not _queue.is_empty():
		_queue.sort_custom(func(a, b): return int(a["rank"]) > int(b["rank"]))
		var ev: Dictionary = _queue[0]
		var cr: int = int(cur.get("rank", 0))
		if (_shot_t > MIN_SHOT and int(ev["rank"]) >= cr) or int(ev["rank"]) > cr + 2:
			_queue.pop_front()
			_switch_event(ev)
			return
	var hold: float = EVENT_HOLD if int(cur.get("rank", 0)) > 0 else HOLD
	if _shot_t > hold:
		_pick_person("", 0)

func _read_log() -> void:
	var log: Array = sim.state.get("log", [])
	if _log_n < 0 or _log_n > log.size():
		_log_n = log.size()
	# (the log is capped and drops its oldest entries: compare by tick from the end)
	var start: int = _log_n
	_log_n = log.size()
	for i in range(clampi(start, 0, log.size()), log.size()):
		var e: Dictionary = log[i]
		var code: String = String(e.get("code", ""))
		if not EVENTS.has(code):
			continue
		var ids: Array = []
		for x in (e.get("ents", []) as Array):
			if sim.state["agents"].has(int(x)) and String(sim.state["agents"][int(x)].get("state", "")) == "alive":
				ids.append(int(x))
		var pos = null
		if ids.is_empty():
			if code == "ship_landing":
				pos = _pad_pos(e)
			if pos == null:
				continue
		_queue.append({"ids": ids, "what": EVENTS[code][1], "rank": int(EVENTS[code][0]), "t0": _t, "pos": pos, "code": code})
	# a party on now with guests: worth a visit (once per party)
	if sim.get("party") != null and int(_t * 2.0) % 10 == 0:
		for pt in sim.party.parties():
			if String(pt.get("phase", "")) == "on" and not _recent.has("party%d" % int(pt["id"])):
				var gs: Array = (pt.get("guests", []) as Array).filter(func(g): return sim.state["agents"].has(int(g)))
				if not gs.is_empty():
					_recent.append("party%d" % int(pt["id"]))
					_queue.append({"ids": gs, "what": "a party", "rank": 6, "t0": _t, "pos": null, "code": "party"})

func _pad_pos(e: Dictionary):
	for x in (e.get("ents", []) as Array):
		var b: Dictionary = sim.state["buildings"].get(int(x), {})
		if not b.is_empty():
			return b["pos"]
	return null

func _switch_event(ev: Dictionary) -> void:
	var ids: Array = ev["ids"]
	if ids.is_empty():
		_begin({"place": true, "pos": ev["pos"], "who": "", "what": ev["what"], "rank": int(ev["rank"])})
		return
	# the person most in the middle of it: the first named; the others are framed by a wider shot
	var id: int = int(ids[0])
	var names: Array = []
	for x in ids.slice(0, 2):
		names.append(_first(int(x)))
	_begin({"id": id, "who": " and ".join(names), "what": ev["what"], "rank": int(ev["rank"]), "wide": ids.size() > 1})

func _pick_person(_why: String, _rank: int) -> void:
	var best := -1
	var best_s := -INF
	var ags: Dictionary = sim.state["agents"]
	for aid in ags:
		var a: Dictionary = ags[aid]
		if String(a.get("state", "")) != "alive" or view.agent_world_pos(int(aid)) == null or String(a.get("where", "")) == "vehicle":
			continue
		var s: float = 0.0
		if int(a.get("party", -1)) >= 0:
			s += 3.0
		if String(a.get("where", "")) == "in":
			s += 1.0
		var rec = view.npc.agents.get(int(aid)) if view.npc != null else null
		if rec != null:
			s += clampf(float(rec.get("speed", 0.0)), 0.0, 1.5)
			var clip: String = String(rec["sm"].cur)
			if clip.begins_with("talk") or clip.begins_with("dance") or clip in ["cheer", "toast", "sing", "laugh", "argue", "hug"]:
				s += 2.5
			if clip in ["sleep", "lie_enter", "lie_exit"]:
				s -= 4.0
		if _recent.has(int(aid)):
			s -= 5.0
		s += float((int(aid) * 7919 + int(_t * 10.0)) % 100) * 0.01
		if s > best_s:
			best_s = s
			best = int(aid)
	if best < 0:
		return
	_begin({"id": best, "who": String(ags[best].get("name", "")), "what": _doing(best), "rank": 0})

func _doing(id: int) -> String:
	var rec = view.npc.agents.get(id) if view.npc != null else null
	if rec == null:
		return ""
	var clip: String = String(rec["sm"].cur)
	if clip.begins_with("dance"):
		return "dancing"
	if clip.begins_with("talk") or clip == "laugh":
		return "talking"
	if clip.begins_with("work") or clip.begins_with("repair"):
		return "at work"
	if clip.begins_with("sit"):
		return "taking a seat"
	if float(rec.get("speed", 0.0)) > 0.3:
		return "on the way"
	return ""

func _first(id: int) -> String:
	return String(sim.state["agents"].get(id, {}).get("name", "someone")).get_slice(" ", 0)

func _begin(shot: Dictionary) -> void:
	_pending = shot
	_fade_dir = 1
	if cur.is_empty():
		_fade = 1.0

func _apply(shot: Dictionary) -> void:
	if shot.is_empty():
		return
	_shot_t = 0.0
	cur = shot.duplicate()
	if bool(shot.get("place", false)):
		view.follow_stop()
		var p: Vector2 = shot["pos"]
		var mr = view.get_parent()
		if mr != null and mr.has_method("focus_on"):
			mr.focus_on(p)
		var r = view.rig()
		if r != null:
			r.target_distance = 70.0
			if "pitch" in r:
				r.pitch = deg_to_rad(18.0)
		return
	var id: int = int(shot["id"])
	if view.follow_id != id:
		view.follow_start(id)
	_recent.append(id)
	if _recent.size() > 6:
		_recent.pop_front()
	var r2 = view.rig()
	if r2 != null and r2.has_method("set_shot"):
		# a wider, slightly higher shot for an event with several people; an over-the-shoulder shot otherwise
		if bool(shot.get("wide", false)):
			r2.set_shot(4.2, deg_to_rad(25.0), deg_to_rad(16.0))
		else:
			r2.set_shot(2.2, 0.0, 0.0)

func _ensure_overlay() -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0, 0, 0, 0)
	_layer.add_child(_black)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position = Vector2(-300, -96)
	_label.size = Vector2(600, 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	_layer.add_child(_label)
