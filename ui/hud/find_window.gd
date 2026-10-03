extends PanelContainer
## Find (docs/V4_DESIGN.md §3.4): type a name or a type ("kitchen", "habitat", "lab", "power") and
## get every matching structure with its district, size and status. Click a row: the camera goes
## there and the structure is selected. "Mark all" marks every structure of that type on the map
## (ui/hud/find_marks.gd) until it is turned off.
## A window of the window manager: it opens with / or Ctrl+F or the nav rail button, drags by its
## title plate, remembers its place, closes with Esc.
## Points of interest (SIM milestone 7): the found ones match by their kind ("cave", "wreck"),
## "point of interest", "poi", what a visit needs ("scientist", "on foot") and what they give.
## A row names the need and the distance from the colony; click: the camera goes there and the
## tag over it pulses (ui/hud/poi_marks.gd).
## Reads only: sim.state buildings, sim.bdef, the district names, the inspector's status words,
## ui/v4_data.gd pois().

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")

const Quarter = preload("res://ui/wm/quarter.gd")
const WIDTH := 400.0
const MAX_ROWS := 40

var hud
var _edit: LineEdit
var _list: VBoxContainer
var _scroll: ScrollContainer
var _count: Label
var _mark: Button
var _labels: OptionButton
var _label_ids: Array = []    # option index -> "" | "all" | category
var _head: HBoxContainer
var _style
var _query := ""
var _sig := ""
var results: Array = []      # [{id, def, name, cat, district, size, status, color}] (tests read it); POI rows have poi: true

func _ready() -> void:
	_style = GlassFrame.new()
	_style.kind = "window"
	_style.header_h = 50.0
	_style.content_margin_left = 20
	_style.content_margin_right = 22
	_style.content_margin_top = 12
	_style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", _style)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	_head = Kit.hbox(10)
	_head.custom_minimum_size.y = 30
	v.add_child(_head)
	_head.add_child(Kit.icon("search", 22, P.CYAN))
	var t: Label = Kit.head("FIND", P.TEXT, 16, "head_wide")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(t)
	var close_b: Button = Kit.icon_button("close", func(): visible = false, "Close\nEsc.", "GhostButton", 16, 30)
	_head.add_child(close_b)
	Quarter.thin(close_b)
	v.add_child(Kit.gap(0, 6))
	_edit = LineEdit.new()
	_edit.placeholder_text = "Name or type: kitchen, lab, power, cave, wreck"
	_edit.clear_button_enabled = true
	_edit.text_changed.connect(func(s: String):
		_query = s
		_sig = ""
		refresh())
	_edit.text_submitted.connect(func(_s): _go_first())
	v.add_child(_edit)
	var row: HBoxContainer = Kit.hbox(8)
	_count = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count.custom_minimum_size.x = 170   # an autowrap label needs a width, or it measures one letter per line
	row.add_child(_count)
	_mark = Kit.button("Mark all", func(): _toggle_mark(), "Mark all\nMarks every structure of the first type in the list on the map.", "ChipButton", "eye", 14)
	_mark.toggle_mode = true
	_mark.clip_text = true                     # a long type name never widens the window
	_mark.custom_minimum_size.x = 150
	_mark.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_mark)
	v.add_child(row)
	# Label layer by family (V4_DESIGN §3.4): names over the rooms on the map.
	var lrow: HBoxContainer = Kit.hbox(8)
	var ll: Label = Kit.label("Names on the map", "", 13, P.TEXT_2)
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(ll)
	_labels = OptionButton.new()
	_labels.tooltip_text = "Names on the map\nA name tag over every room, or over the rooms of one family."
	_label_ids = ["", "all"]
	_labels.add_item("Off")
	_labels.add_item("All rooms")
	for cat in P.CATEGORY_NAME:
		_labels.add_item(String(P.CATEGORY_NAME[cat]))
		_label_ids.append(String(cat))
	_labels.custom_minimum_size.x = 170
	_labels.item_selected.connect(func(i: int):
		if hud.find_marks != null:
			hud.find_marks.set_labels(String(_label_ids[i])))
	lrow.add_child(_labels)
	v.add_child(lrow)
	var well: PanelContainer = Kit.panel("WellPanel", false)
	v.add_child(well)
	_list = Kit.vbox(0)
	_scroll = Kit.scroll(_list)
	_scroll.custom_minimum_size = Vector2(WIDTH - 42 - 18, 300)
	well.add_child(_scroll)
	visibility_changed.connect(func():
		if visible:
			_sig = ""
			refresh()
			_edit.call_deferred("grab_focus")
			_edit.call_deferred("select_all"))

func register_window(wm) -> void:
	wm.register(self, "find", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.end.x - sz.x, wa.position.y + 40.0))

func wm_close() -> void:
	visible = false

func toggle() -> void:
	visible = not visible

## Opens with a query (the `find` command and tests).
func search(q: String) -> void:
	visible = true
	_edit.text = q
	_query = q
	_sig = ""
	refresh()

# ---------------------------------------------------------------- matching
func _match(q: String) -> Array:
	var s = hud.main.sim
	var out: Array = []
	var words: PackedStringArray = q.to_lower().strip_edges().split(" ", false)
	# Several bases (SIM v4 milestone 2, sim.bases): each row names its base, and a base name matches.
	var multi: bool = "bases" in s and s.bases != null and s.bases.list().size() > 1
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		var def_id: String = String(b["def"])
		var base: Dictionary = s.bdef(def_id)
		if String(base.get("kind", "")) == "link":   # corridors and utility cables: not places to find
			continue
		var cat: String = String(base.get("category", "logistics"))
		var name: String = String(b.get("name", base.get("name", def_id)))
		var base_name: String = String(s.bases.name_of(s.bases.base_of(int(id)))) if multi else ""
		var hay: String = ("%s %s %s %s %s" % [name, String(base.get("name", "")), def_id.replace("_", " "), P.CATEGORY_NAME.get(cat, cat), base_name]).to_lower()
		var ok := true
		for w in words:
			if not hay.contains(w):
				ok = false
				break
		if not ok:
			continue
		var st: Array = hud.inspector.sections.status_of(b)
		var district: String = s.topo.district_name(b["pos"]) if b.has("pos") else ""
		var size_txt: String = hud.data.size_word(def_id, hud.data.size_of(b))
		out.append({"id": int(id), "def": def_id, "name": name, "cat": cat, "district": district, "base": base_name, "size": size_txt, "status": String(st[0]), "color": st[1], "pos": b.get("pos", Vector2.ZERO)})
	out.sort_custom(func(a, b2): return String(a["name"]).naturalnocasecmp_to(String(b2["name"])) < 0)
	# Points of interest after the structures, nearest first.
	var pois: Array = []
	var home: Vector2 = hud.data.colony_center()
	for p in hud.v4.pois():
		var hay2: String = ("%s %s point of interest poi site needs %s %s %s" % [p["name"], String(p["kind"]).replace("_", " "), p["need_short"],
			"visited" if bool(p["visited"]) else "not visited", hud.v4.poi_finds_text(p)]).to_lower()
		var ok2 := true
		for w in words:
			if not hay2.contains(w):
				ok2 = false
				break
		if not ok2:
			continue
		var dist: float = (p["pos"] as Vector2).distance_to(home)
		pois.append({"id": int(p["id"]), "def": "", "poi": true, "kind": String(p["kind"]), "name": String(p["name"]), "cat": "", "district": "", "base": "", "size": "",
			"status": "VISITED" if bool(p["visited"]) else "TO VISIT", "color": P.GREEN if bool(p["visited"]) else P.AMBER, "pos": p["pos"], "dist": dist,
			"need": String(p["need_short"]), "need_text": String(p["need_text"]), "finds": hud.v4.poi_finds_text(p), "desc": String(p["desc"])})
	pois.sort_custom(func(a, b2): return float(a["dist"]) < float(b2["dist"]))
	return out + pois

func refresh() -> void:
	if visible:
		Quarter.fit(self, hud, "find", WIDTH, _scroll, _list, 60.0)
		# Narrow: the rows of the head share the width.
		var nw: bool = float(get_meta("qw", WIDTH)) < WIDTH - 0.5
		_count.custom_minimum_size.x = 60.0 if nw else 170.0
		_mark.custom_minimum_size.x = 80.0 if nw else 150.0
		_labels.custom_minimum_size.x = 90.0 if nw else 170.0
	if not visible or hud == null or hud.main == null or hud.main.sim == null:
		return
	results = _match(_query) if _query.strip_edges() != "" else []
	var sig: String = _query + "|" + str(results.size())
	for r in results:
		sig += "|%d:%s" % [r["id"], r["status"]]
	if sig == _sig:
		Kit.fit(self)   # shrink back after a long line went away (layout settles a frame later)
		return
	_sig = sig
	Kit.clear(_list)
	if _query.strip_edges() == "":
		_count.text = "Type to find a structure. Enter goes to the first one."
		_list.add_child(Kit.wrap("Examples: kitchen, habitat 2, lab, power, broken.", 13, P.TEXT_3))
	elif results.is_empty():
		_count.text = "Nothing matches \"%s\"." % _query
	else:
		var np := 0
		for r in results:
			if bool(r.get("poi", false)):
				np += 1
		var parts: Array = []
		if results.size() - np > 0:
			parts.append(Kit.plural(results.size() - np, "structure"))
		if np > 0:
			parts.append(Kit.plural(np, "point of interest", "points of interest"))
		_count.text = "%s. Click one: the camera goes there." % " and ".join(parts)
	for i in mini(results.size(), MAX_ROWS):
		_list.add_child(_row(results[i]))
	if results.size() > MAX_ROWS:
		_list.add_child(Kit.label("%d more. Type more of the name." % (results.size() - MAX_ROWS), "SmallLabel", 12, P.TEXT_3))
	_mark.disabled = _first_structure().is_empty()
	_update_mark_text()
	# The list well is as tall as its rows, up to 300 px (then it scrolls); the window shrinks with it.
	_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y + 4.0, 48.0, 300.0)
	Kit.fit(self)

func _first_structure() -> Dictionary:
	for r in results:
		if not bool(r.get("poi", false)):
			return r
	return {}

## A point of interest row: kind icon, name, what a visit needs and gives, distance, status.
func _poi_row(r: Dictionary) -> Control:
	var V4 = load("res://ui/v4_data.gd")
	var b := Button.new()
	b.theme_type_variation = "ListButton"
	b.custom_minimum_size.y = 64
	b.tooltip_text = "%s\n%s\n%s Gives: %s.\nClick: the camera goes there. To visit it: select colonists, Orders, Survey, then click it." % [r["name"], r["desc"], r["need_text"], r["finds"]]
	b.pressed.connect(func(): _go(r))
	var h: HBoxContainer = Kit.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.add_child(Kit.icon(String(V4.POI_ICON.get(String(r["kind"]), "star")), 20, V4.POI_COLOR.get(String(r["kind"]), P.TEXT)))
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	var n: Label = Kit.label(String(r["name"]), "BodyStrong", 14, P.TEXT)
	n.custom_minimum_size.x = 160
	tv.add_child(n)
	# One line each, cut with an ellipsis (the tooltip has the full text): a wrapped line made the
	# row taller than its button.
	for pair in [["Needs %s  ·  %d m away" % [r["need"], int(r["dist"])], P.TEXT_2], ["Gives " + String(r["finds"]), P.TEXT_3]]:
		var sl: Label = Kit.label(String(pair[0]), "SmallLabel", 12, pair[1])
		sl.custom_minimum_size.x = 160
		sl.clip_text = true
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(sl)
	var st: Label = Kit.label(String(r["status"]), "SmallLabel", 11, r["color"])
	st.add_theme_font_override("font", load("res://ui/theme/fonts.gd").get_font("mono_b"))
	h.add_child(st)
	var seam := HSeparator.new()
	seam.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	seam.offset_top = -2
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(seam)
	return b

func _row(r: Dictionary) -> Control:
	if bool(r.get("poi", false)):
		return _poi_row(r)
	var b := Button.new()
	b.theme_type_variation = "ListButton"
	b.custom_minimum_size.y = 44
	b.tooltip_text = "%s\nClick: the camera goes there and selects it." % r["name"]
	b.pressed.connect(func(): _go(r))
	var h: HBoxContainer = Kit.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.add_child(Kit.icon(Icons.category(String(r["cat"])), 20, P.cat(String(r["cat"]))))
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	var n: Label = Kit.label(String(r["name"]), "BodyStrong", 14, P.TEXT)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wraps in a small window (was clipped)
	n.custom_minimum_size.x = 160
	tv.add_child(n)
	var sub: String = "%s district" % r["district"] if String(r["district"]) != "" else ""
	if String(r.get("base", "")) != "":
		sub = String(r["base"]) + ("  ·  " + sub if sub != "" else "")
	if String(r["size"]) != "":
		sub += ("  ·  " if sub != "" else "") + "size " + String(r["size"])
	var sl: Label = Kit.label(sub, "SmallLabel", 12, P.TEXT_2)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wraps in a small window (was clipped)
	sl.custom_minimum_size.x = 160
	tv.add_child(sl)
	var st: Label = Kit.label(String(r["status"]), "SmallLabel", 11, r["color"])
	st.add_theme_font_override("font", load("res://ui/theme/fonts.gd").get_font("mono_b"))
	h.add_child(st)
	# A seam under each row, no box per row (critic round 15 list rule).
	var seam := HSeparator.new()
	seam.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	seam.offset_top = -2
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(seam)
	return b

func _go(r: Dictionary) -> void:
	if bool(r.get("poi", false)):
		if hud.poi_marks != null:
			hud.poi_marks.target = int(r["id"])
		hud.main.focus_on(r["pos"])
		return
	hud.main.select("building", int(r["id"]))
	hud.main.focus_on(r["pos"])

func _go_first() -> void:
	if not results.is_empty():
		_go(results[0])

# ---------------------------------------------------------------- marks
func _toggle_mark() -> void:
	if hud.find_marks == null:
		return
	var first: Dictionary = _first_structure()
	if hud.find_marks.def_id != "" or first.is_empty():
		hud.find_marks.set_def("")
	else:
		hud.find_marks.set_def(String(first["def"]))
	_update_mark_text()

func _update_mark_text() -> void:
	if hud.find_marks == null:
		return
	var on: bool = hud.find_marks.def_id != ""
	_mark.set_pressed_no_signal(on)
	if on:
		_mark.text = "Marked: %s" % String(hud.data.bdef(hud.find_marks.def_id).get("name", hud.find_marks.def_id))
	elif not _first_structure().is_empty():
		_mark.text = "Mark all %s" % String(hud.data.bdef(String(_first_structure()["def"])).get("name", "")).to_lower()
	else:
		_mark.text = "Mark all"
