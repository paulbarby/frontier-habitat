extends CanvasLayer
## V5 §3 speech bubbles (RENDER): 3D-attached 2D bubbles above people's heads, only in the follow
## view. People within 14 m and in line of sight; the followed person's bubble always shows. A glass
## bubble with a tail, 1-2 short lines, fade in and out, never overlapping (stacked upward), at most 6.
## Emote icons for non-verbal acts (heart, anger, zzz, music note, sweat drop, credit, question).
##
## Text from SIM: sim.social.talks_near(pos, radius) -> [{speaker, text, emote, anim, t0 (game s),
## dur?}] (V5 §4.1). Until SIM publishes it, a RENDER stub makes plausible lines from nearby people
## (stats.src = "stub"). Nothing here writes sim.state.
## Style: UI supplies the glass bubble style (V5 §10); until then the look below (ui_style() takes it).

const RANGE := 14.0
const MAX_SHOWN := 6
const HEAD := 1.9
const EMOTES := ["heart", "anger", "zzz", "note", "sweat", "credit", "question"]

var view
var sim
var follow_id := -1
var _pool: Array = []          # Bubble controls
var _stub_talks: Array = []    # [{speaker, text, emote, t0, dur}]
var _stub_clock := 0.0
var _rng := RandomNumberGenerator.new()
var stats := {"src": "", "shown": 0, "talks": 0, "ms": 0.0}
var style := {"bg": Color(0.07, 0.1, 0.14, 0.78), "border": Color(0.62, 0.86, 1.0, 0.55), "text": Color(0.94, 0.97, 1.0),
	"name": Color(0.55, 0.85, 1.0), "follow_border": Color(1.0, 0.82, 0.45, 0.85), "radius": 10, "font_size": 14, "name_size": 12, "rim": Color(0.72, 0.76, 0.8, 0.9), "rim_dark": Color(0.2, 0.23, 0.27, 0.9)}
var font: Font
var _talk_cache: Array = []
var _last_mine := {}
var _talk_clock := 0.0
var force_stub := false     # evidence only (__fhr "bubbles stub"): RENDER's stub lines instead of SIM's

class Bubble extends Control:
	var owner_fx
	var text := ""
	var who := ""
	var emote := ""
	var alpha := 1.0
	var followed := false
	var tail_x := 0.0
	var tail_tip := Vector2.ZERO   # the speaker's head, in this control's space
	var lines: PackedStringArray = []
	var box := Vector2.ZERO

	func setup(fx) -> void:
		owner_fx = fx
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Lays the text out (1-2 lines, max 240 px) and returns the box size.
	func layout() -> Vector2:
		var f: Font = owner_fx.font
		var fs: int = int(owner_fx.style["font_size"])
		lines = PackedStringArray()
		var words: PackedStringArray = text.split(" ", false)
		var cur := ""
		for w in words:
			var t: String = w if cur == "" else cur + " " + w
			if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 240.0 and cur != "":
				lines.append(cur)
				cur = w
				if lines.size() == 2:
					break
			else:
				cur = t
		if lines.size() < 2 and cur != "":
			lines.append(cur)
		elif lines.size() == 2 and cur != "" and cur != lines[1]:
			lines[1] = lines[1] + "..."
		var wmax := 0.0
		for l in lines:
			wmax = maxf(wmax, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var ns: int = int(owner_fx.style.get("name_size", 12))
		var nw: float = f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
		var icon: float = 26.0 if emote != "" else 0.0
		var w2: float = maxf(wmax, nw) + 20.0 + icon
		var h2: float = 10.0 + ns + lines.size() * (fs + 4) + 6.0
		if lines.is_empty():
			w2 = 40.0
			h2 = 34.0
		box = Vector2(maxf(w2, 40.0), h2)
		size = box + Vector2(0, 12)
		return box

	func _draw() -> void:
		var st: Dictionary = owner_fx.style
		var f: Font = owner_fx.font
		var fs: int = int(st["font_size"])
		var bg: Color = st["bg"]
		bg.a *= alpha
		var bd: Color = st["follow_border"] if followed else st.get("rim", st["border"])
		bd.a *= alpha
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = bd
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(st["radius"]))
		sb.shadow_color = Color(0, 0, 0, 0.35 * alpha)
		sb.shadow_size = 4
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, box))
		# The tail: a small triangle down to the speaker's head.
		var tx: float = clampf(tail_x, 14.0, box.x - 14.0)
		var tip: Vector2 = tail_tip if tail_tip.y > box.y else Vector2(tx, box.y + 11)
		var tri := PackedVector2Array([Vector2(tx - 6, box.y - 1), Vector2(tx + 6, box.y - 1), tip])
		draw_colored_polygon(tri, bg)
		draw_polyline(PackedVector2Array([tri[0], tri[2], tri[1]]), bd, 1.0, true)
		var x0 := 10.0
		if emote != "":
			_draw_emote(Vector2(10 + 11, box.y * 0.5 if lines.is_empty() else 12 + 11), 11.0)
			x0 = 10.0 + 26.0
		if lines.is_empty():
			return
		var nc: Color = st["name"]
		nc.a *= alpha
		var ns: int = int(st.get("name_size", 12))
		draw_string(f, Vector2(x0, 6 + ns), who, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, nc)
		var tc: Color = st["text"]
		tc.a *= alpha
		for i in lines.size():
			draw_string(f, Vector2(x0, 8 + ns + (i + 1) * (fs + 4) - 2), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)

	func _draw_emote(c: Vector2, r: float) -> void:
		var col: Color = {"heart": Color(1.0, 0.36, 0.5), "anger": Color(1.0, 0.3, 0.2), "zzz": Color(0.6, 0.75, 1.0),
			"note": Color(0.7, 0.55, 1.0), "sweat": Color(0.45, 0.8, 1.0), "credit": Color(1.0, 0.82, 0.3), "question": Color(0.9, 0.95, 1.0)}.get(emote, Color.WHITE)
		col.a *= alpha
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.18 * alpha))
		match emote:
			"heart":
				draw_circle(c + Vector2(-3.2, -2), 4.0, col)
				draw_circle(c + Vector2(3.2, -2), 4.0, col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -0.5), c + Vector2(7, -0.5), c + Vector2(0, 7.5)]), col)
			"anger":
				for a in 4:
					var d := Vector2.from_angle(PI * 0.25 + a * PI * 0.5)
					draw_line(c + d * 2.5, c + d * 7.5, col, 2.4, true)
			"zzz":
				var f: Font = owner_fx.font
				draw_string(f, c + Vector2(-7, 5), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
				draw_string(f, c + Vector2(-1, 1), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
			"note":
				draw_circle(c + Vector2(-2.5, 4), 3.0, col)
				draw_line(c + Vector2(0.3, 4), c + Vector2(0.3, -6.5), col, 1.8, true)
				draw_line(c + Vector2(0.3, -6.5), c + Vector2(5.5, -4.5), col, 1.8, true)
			"sweat":
				draw_circle(c + Vector2(0, 2.5), 4.2, col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-3.6, 1), c + Vector2(3.6, 1), c + Vector2(0, -7)]), col)
			"credit":
				var f2: Font = owner_fx.font
				draw_string(f2, c + Vector2(-4.5, 5.5), "¢", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
			_:
				var f3: Font = owner_fx.font
				draw_string(f3, c + Vector2(-4, 5.5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

func setup(v) -> void:
	view = v
	sim = v.sim
	layer = 5
	_rng.seed = 5501
	if ResourceLoader.exists("res://assets/fonts/Inter.woff2"):
		font = load("res://assets/fonts/Inter.woff2")
	if font == null:
		font = ThemeDB.fallback_font

## UI's shared glass bubble style (V5 §10), when it lands: a Dictionary with any of the keys above,
## or a StyleBoxFlat (its bg, border and radius are used).
func ui_style(s) -> void:
	if s is Dictionary:
		for k in s:
			style[k] = s[k]
	elif s is StyleBoxFlat:
		style["bg"] = (s as StyleBoxFlat).bg_color
		style["border"] = (s as StyleBoxFlat).border_color
		style["radius"] = (s as StyleBoxFlat).corner_radius_top_left

## The talks near a point: SIM's when published, else the RENDER stub.
func _talks(center: Vector3) -> Array:
	var soc = sim.get("social")
	if not force_stub and soc != null and (soc as Object).has_method("talks_near"):
		stats["src"] = "sim"
		# SIM-to-RENDER 2026-09-29: {speaker, line, emote, started (tick), line_index, ...}; one line per 4 s.
		var hz: float = float(sim.bal["tick_hz"])
		var lt: float = float(soc.get("LINE_TICKS")) if soc.get("LINE_TICKS") != null else 40.0
		var out: Array = []
		for t in soc.talks_near(Vector2(center.x, center.z), RANGE + 2.0):
			var e: String = String(t.get("emote", ""))
			out.append({"speaker": int(t["speaker"]), "text": String(t.get("line", t.get("text", ""))), "emote": "note" if e == "music" else e,
				"t0": (float(t.get("started", 0)) + float(t.get("line_index", 0)) * lt) / hz, "dur": lt / hz, "anim": String(t.get("anim", ""))})
		return out
	stats["src"] = "stub"
	return _stub(center)

# ---------------------------------------------------------------- stub (until SIM's API lands)
const STUB_LINES := {
	"small": ["Long shift today.", "Did you see the new {building}?", "The view from the rim is something.", "I could use a coffee.", "{other}, you look tired."],
	"state": ["Air feels thin in here.", "Power went low again last night.", "I hope the ship brings more food.", "The reactor had me worried.", "We need more water, honestly."],
	"work": ["Captain wants the {building} fixed by noon.", "My back hurts from hauling crates.", "Research is going well.", "The fabricator jammed twice."],
	"gossip": ["Did you hear about {other} and Kai?", "Don't tell anyone, but...", "They were at the bar till late."],
	"romance": ["Want to walk to the park later?", "You're funny, {other}.", "Dinner tonight?"],
}
const STUB_EMOTE := {"small": ["", "", "question"], "state": ["sweat", "anger", ""], "work": ["", "sweat"], "gossip": ["", "question"], "romance": ["heart", "heart", "note"]}

func _stub(center: Vector3) -> Array:
	var now: float = float(sim.state["tick"]) / float(sim.bal["tick_hz"])
	_stub_talks = _stub_talks.filter(func(t): return now - float(t["t0"]) < float(t["dur"]))
	if now - _stub_clock >= 2.5 or now < _stub_clock:
		_stub_clock = now
		var near: Array = []
		for id in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][id]
			if a["state"] != "alive":
				continue
			var bp = view.agent_world_pos(int(id))
			if bp != null and (bp as Vector3).distance_to(center) < RANGE:
				near.append(int(id))
		var talking := {}
		for t in _stub_talks:
			talking[int(t["speaker"])] = true
		near.shuffle()
		var budget := 2
		for id in ([follow_id] + near):
			if budget <= 0 or talking.has(id) or not sim.state["agents"].has(id):
				continue
			if id != follow_id and _rng.randf() > 0.55:
				continue
			var topic: String = STUB_LINES.keys()[_rng.randi() % STUB_LINES.size()]
			var ls: Array = STUB_LINES[topic]
			var other := "Kai"
			if near.size() > 1:
				var oid: int = near[_rng.randi() % near.size()]
				other = String(sim.state["agents"][oid].get("name", "Kai")).split(" ")[0]
			var bname := "greenhouse"
			var line: String = String(ls[_rng.randi() % ls.size()]).replace("{other}", other).replace("{building}", bname)
			var em: Array = STUB_EMOTE[topic]
			var emo: String = em[_rng.randi() % em.size()]
			if _rng.randf() < 0.12:
				line = ""
				emo = ["zzz", "note", "credit", "heart"][_rng.randi() % 4]
			_stub_talks.append({"speaker": id, "text": line, "emote": emo, "t0": now, "dur": 4.0 + _rng.randf() * 1.5})
			talking[id] = true
			budget -= 1
	return _stub_talks

# ---------------------------------------------------------------- per frame
func sync(_delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	var cam: Camera3D = view.get_viewport().get_camera_3d()
	if follow_id < 0 or cam == null:
		for b in _pool:
			(b as Control).visible = false
		stats["shown"] = 0
		return
	var fpos = view.agent_world_pos(follow_id)
	if fpos == null:
		return
	# SIM's talks are asked once a second (a line lasts 4 s): talks() rebuilds on a new tick and cost
	# 26-28 ms at 66 people in the web build (reported to SIM 2026-09-29).
	_talk_clock -= _delta
	if _talk_clock <= 0.0 or _talk_cache.is_empty() and _talk_clock < -1.0:
		_talk_clock = 1.0
		var tq: int = Time.get_ticks_usec()
		_talk_cache = _talks(fpos)
		stats["query_ms"] = snappedf((Time.get_ticks_usec() - tq) / 1000.0, 0.01)
	var talks: Array = _talk_cache
	stats["talks"] = talks.size()
	var now: float = float(sim.state["tick"]) / float(sim.bal["tick_hz"])
	# Critic round 29: the followed person's last line stays 6 s, so the view is not silent between lines.
	var have_mine := false
	for t in talks:
		if int(t.get("speaker", -1)) == follow_id:
			have_mine = true
			if String(t.get("text", "")) != String(_last_mine.get("text", "#")) or float(t.get("t0", 0.0)) > float(_last_mine.get("t0", -1.0)):
				_last_mine = t.duplicate()
				_last_mine["dur"] = maxf(6.0, float(t.get("dur", 4.0)))
	if int(_last_mine.get("speaker", -2)) != follow_id:
		_last_mine = {}
	if not have_mine and not _last_mine.is_empty() and now - float(_last_mine["t0"]) < float(_last_mine["dur"]):
		talks = talks + [_last_mine]
	var cand: Array = []
	for t in talks:
		var sid: int = int(t.get("speaker", -1))
		var p = view.agent_world_pos(sid)
		if p == null:
			continue
		var d: float = (p as Vector3).distance_to(fpos)
		var mine: bool = sid == follow_id
		if not mine and (d > RANGE or not view.follow_los(fpos, p)):
			continue
		var head: Vector3 = (p as Vector3) + Vector3(0, HEAD, 0)
		if cam.is_position_behind(head):
			continue
		var age: float = now - float(t.get("t0", now))
		var dur: float = float(t.get("dur", 4.5))
		if sid == follow_id:
			dur = maxf(dur, 6.0)
		var fade: float = clampf(age / 0.3, 0.0, 1.0) * clampf((dur - age) / 0.5, 0.0, 1.0)
		if not mine:
			fade *= 1.0 - smoothstep(RANGE - 2.0, RANGE, d)
		if fade <= 0.01:
			continue
		var nm: String = String(sim.state["agents"].get(sid, {}).get("name", ""))
		cand.append({"id": sid, "text": String(t.get("text", "")), "emote": String(t.get("emote", "")), "a": fade, "mine": mine,
			"scr": cam.unproject_position(head), "d": d, "who": nm})
	# The followed person first, then the nearest.
	cand.sort_custom(func(a, b): return a["mine"] if a["mine"] != b["mine"] else float(a["d"]) < float(b["d"]))
	cand = cand.slice(0, MAX_SHOWN)
	while _pool.size() < cand.size():
		var nb := Bubble.new()
		nb.setup(self)
		add_child(nb)
		_pool.append(nb)
	var placed: Array = []
	var vs: Vector2 = view.get_viewport().get_visible_rect().size
	for i in _pool.size():
		var bb: Bubble = _pool[i]
		if i >= cand.size():
			bb.visible = false
			continue
		var c: Dictionary = cand[i]
		bb.text = c["text"]
		bb.who = c["who"]
		bb.emote = c["emote"]
		bb.alpha = c["a"]
		bb.followed = c["mine"]
		var box: Vector2 = bb.layout()
		var scr: Vector2 = c["scr"]
		var r := Rect2(Vector2(scr.x - box.x * 0.5, scr.y - box.y - 16.0), box)
		# Never overlapping: move up past every bubble already placed.
		var moved := true
		var guard := 0
		while moved and guard < 12:
			moved = false
			guard += 1
			for q in placed:
				if (q as Rect2).grow(3.0).intersects(r):
					r.position.y = (q as Rect2).position.y - box.y - 6.0
					moved = true
		r.position.x = clampf(r.position.x, 4.0, vs.x - box.x - 4.0)
		r.position.y = clampf(r.position.y, 4.0, vs.y - box.y - 16.0)
		placed.append(r)
		bb.position = r.position
		bb.tail_x = scr.x - r.position.x
		bb.tail_tip = scr + Vector2(0, -4) - r.position
		bb.visible = true
		bb.queue_redraw()
	stats["shown"] = cand.size()
	stats["ms"] = snappedf(lerpf(float(stats["ms"]), (Time.get_ticks_usec() - t0) / 1000.0, 0.1), 0.001)
