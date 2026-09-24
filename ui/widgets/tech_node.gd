extends Button
## One research node: branch icon, name, cost or progress, a progress ring, and the state
## as a word: DONE, ACTIVE, QUEUED n, READY, LOCKED. Tier-5 special nodes are gold and show
## their item needs. Drawn by hand for a clean, dense tree.

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const Icons = preload("res://ui/theme/icons.gd")
const FhStyle = preload("res://ui/theme/fh_style.gd")
const Sfx = preload("res://ui/sfx.gd")

var tech := ""
var data
var icon_name := "research"
var branch_color := Color("A78BFA")
var compact := false
var lock_text: Array = []     # why it cannot run, plain words (set by the research screen)
var _state := "locked"
var _selected := false
var _hover := false
var _progress := 0.0
var _queue_pos := 0

func setup(d, t: String, icon: String, col: Color) -> void:
	data = d
	tech = t
	icon_name = icon
	branch_color = col
	focus_mode = Control.FOCUS_NONE
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = " "
	mouse_entered.connect(func():
		_hover = true
		Sfx.play("hover")
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())
	pressed.connect(func(): Sfx.play("click"))

func refresh(selected: bool) -> void:
	_selected = selected
	_state = data.tech_state(tech)
	var cost: float = data.tech_cost(tech)
	_progress = 1.0 if _state == "done" else clampf(data.tech_progress(tech) / maxf(1.0, cost), 0.0, 1.0)
	var q: Array = data.research().get("queue", [])
	_queue_pos = q.find(tech) + 1
	queue_redraw()

func _special() -> bool:
	return int(data.techs().get(tech, {}).get("tier", 1)) >= 5

func _draw() -> void:
	var t: Dictionary = data.techs().get(tech, {})
	var special: bool = _special()
	var gold := P.GOLD
	var col: Color
	match _state:
		"done": col = P.GREEN
		"active": col = P.CYAN
		"queued": col = P.VIOLET
		"available": col = gold if special else P.CYAN
		_: col = P.TEXT_3
	var r := Rect2(Vector2.ZERO, size)
	var ch := PackedFloat32Array([8, 0, 8, 0])
	var pts: PackedVector2Array = FhStyle.shape(r, ch)
	var top := Color(0.08, 0.12, 0.2, 0.95)
	var bot := Color(0.05, 0.08, 0.14, 0.95)
	if _state == "done":
		top = Color(0.08, 0.2, 0.14, 0.95)
		bot = Color(0.05, 0.12, 0.09, 0.95)
	elif _state == "active":
		top = Color(0.08, 0.24, 0.32, 0.97)
		bot = Color(0.05, 0.14, 0.2, 0.97)
	elif special:
		top = Color(0.2, 0.16, 0.06, 0.95)
		bot = Color(0.11, 0.09, 0.04, 0.95)
	if _hover:
		top = top.lightened(0.08)
	var cols := PackedColorArray()
	for q in pts:
		cols.append(top.lerp(bot, clampf(q.y / maxf(1.0, size.y), 0.0, 1.0)))
	draw_polygon(pts, cols)
	# Glow for active and selected
	if _state == "active" or _selected:
		var gp: PackedVector2Array = FhStyle.shape(r.grow(3.0), PackedFloat32Array([9, 0, 9, 0]))
		gp.append(gp[0])
		draw_polyline(gp, Color(col.r, col.g, col.b, 0.35), 3.0, true)
	var bp: PackedVector2Array = FhStyle.shape(r.grow(-0.5), ch)
	bp.append(bp[0])
	var bc: Color = col if (_selected or _state in ["active", "done", "available", "queued"]) else Color(0.3, 0.36, 0.45)
	if special and _state != "done":
		bc = gold
	draw_polyline(bp, Color(bc.r, bc.g, bc.b, 1.0 if _selected else 0.7), 2.0 if _selected else 1.0, true)
	# Branch strip
	draw_rect(Rect2(0, 8, 3, size.y - 16), branch_color if _state != "locked" else Color(branch_color.r, branch_color.g, branch_color.b, 0.35), true)
	# Icon
	var ic_col: Color = gold if special else branch_color
	if _state == "locked":
		ic_col = Color(ic_col.r, ic_col.g, ic_col.b, 0.45)
	var isz: float = 18.0 if compact else 22.0
	draw_texture_rect(Icons.tex("sparkle" if special else icon_name, int(isz)), Rect2(Vector2(10, 9), Vector2(isz, isz)), false, ic_col)
	# Name (two lines at most)
	var f: Font = Fonts.get_font("body_sb")
	var fs: int = 11 if compact else (12 if String(t.get("name", tech)).length() > 15 else 13)
	var name: String = String(t.get("name", tech))
	var tx: float = 10.0 + isz + 6.0
	var tw: float = size.x - tx - (8.0 if compact else 30.0)
	var tc: Color = P.TEXT if _state != "locked" else P.TEXT_3
	draw_multiline_string(f, Vector2(tx, 20), name, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 2, tc)
	# Bottom line: state word and cost/progress
	var hf: Font = Fonts.get_font("head")
	var word: String = {"done": "DONE", "active": "ACTIVE", "queued": "QUEUED %d" % _queue_pos, "available": "READY", "locked": "LOCKED"}.get(_state, _state.to_upper())
	draw_string(hf, Vector2(10, size.y - 9), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	var mf: Font = Fonts.get_font("mono")
	var cost: float = float(t.get("cost", 0))
	var ctext: String = ("%d RP" % int(cost)) if _state != "active" else ("%d/%d" % [int(_progress * cost), int(cost)])
	var tc2: Color = P.TEXT_2 if _state != "locked" else P.TEXT_3
	var by: float = size.y - 9.0
	draw_string(mf, Vector2(0, by), ctext, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8.0, 10, tc2)
	# Items and research packs it needs, right to left before the RP: [icon]n (version 3).
	if not compact:
		var x: float = size.x - 8.0 - mf.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x - 6.0
		var needs: Array = []
		var items: Dictionary = t.get("items", {})
		for it in items:
			needs.append([String(it), int(items[it])])
		var packs: Dictionary = data.tech_packs(tech)
		for it in packs:
			needs.append([String(it), int(packs[it])])
		needs.reverse()
		var word_w: float = Fonts.get_font("head").get_string_size("QUEUED 9", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0
		for nd in needs:
			var nt: String = "%d" % int(nd[1])
			var w: float = mf.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			if x - w - 13.0 < word_w:
				break
			draw_string(mf, Vector2(x - w, by), nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tc2)
			x -= w + 13.0
			var ic: Color = data.item_color(String(nd[0]))
			if _state == "locked":
				ic = Color(ic.r, ic.g, ic.b, 0.5)
			draw_texture_rect(Icons.tex(Icons.item(String(nd[0])), 12), Rect2(Vector2(x, by - 10.0), Vector2(12, 12)), false, ic)
			x -= 5.0
	# Progress ring (not in compact nodes)
	if not compact:
		var c := Vector2(size.x - 16, 18)
		draw_arc(c, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.1), 2.5, true)
		if _progress > 0.0:
			draw_arc(c, 9.0, -PI * 0.5, -PI * 0.5 + TAU * _progress, 24, col, 2.5, true)
		if _state == "done":
			draw_texture_rect(Icons.tex("check", 10), Rect2(c - Vector2(5, 5), Vector2(10, 10)), false, P.GREEN)
		elif _state == "locked":
			draw_texture_rect(Icons.tex("lock", 10), Rect2(c - Vector2(5, 5), Vector2(10, 10)), false, P.TEXT_3)
	elif _state == "active":
		draw_rect(Rect2(3, size.y - 3, (size.x - 6) * _progress, 2), col, true)

func _make_custom_tooltip(_for_text: String) -> Object:
	var t: Dictionary = data.techs().get(tech, {})
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 280
	var h := Label.new()
	h.text = String(t.get("name", tech)).to_upper()
	h.add_theme_font_override("font", Fonts.get_font("head"))
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", P.GOLD if _special() else P.VIOLET)
	v.add_child(h)
	var l := Label.new()
	var extra := ""
	var packs: Dictionary = data.tech_packs(tech)
	if not packs.is_empty():
		var parts: Array = []
		for it in packs:
			parts.append("%d %s" % [int(packs[it]), data.item_name(String(it)).to_lower()])
		extra += "\nPacks: " + ", ".join(parts) + "."
	for w in lock_text:
		extra += "\n" + String(w)
	l.text = "%s\n%d RP. %s.%s\nClick to see it, double click to research it." % [String(t.get("desc", "")), int(t.get("cost", 0)), _state.capitalize(), extra]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 280
	l.add_theme_font_size_override("font_size", 13)
	v.add_child(l)
	return v
