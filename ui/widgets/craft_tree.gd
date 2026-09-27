extends Control
## Crafting tree (V4_DESIGN §6, codex): how one unit of an item is made, drawn left to right:
## raw materials on the left, the item on the right. Each node is a metal-rimmed card with the item
## icon, the name and the amount per unit; each edge is labelled with the recipe and the building.
## Click a node: `picked(item)` (the codex opens that item). Data: ui/codex.gd tree().
## Layout: columns by depth (deepest left), rows by leaf order; the size follows the tree, so it
## sits in a scroll area.

signal picked(item: String)

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const Icons = preload("res://ui/theme/icons.gd")

const NODE := Vector2(170, 44)
const COL_W := 340.0   # 170 px node + 170 px gap for the recipe label
const ROW_H := 70.0
const COL_MIN := 236.0  # narrowest column: 170 px node + 66 px gap (deep trees, milestone 5)

var hud
var root_node: Dictionary = {}
var _boxes: Array = []    # [{rect, item, node}]
var _edges: Array = []    # [{a: Vector2, b: Vector2, label}]
var _depth := 0
var _hover := ""
var col_w := COL_W      # fit_width() narrows it so a deep tree fits the pane

func set_tree(t: Dictionary) -> void:
	root_node = t
	_layout()
	queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "

## Tooltip of the card under the pointer: the item, its tier and how it is made (labels can be cut).
func _get_tooltip(at: Vector2) -> String:
	for bx in _boxes:
		if (bx["rect"] as Rect2).has_point(at):
			var it: String = bx["item"]
			var n: Dictionary = bx["node"]
			var tr: int = hud.data.item_tier(it)
			var head: String = hud.data.item_name(it) + ((" (%s)" % hud.data.tier_name(tr).to_lower()) if tr > 0 else "")
			if (n["children"] as Array).is_empty():
				return "%s\nRaw material. Click to open it in the codex." % head
			var where: String = String(hud.data.bdef(String(n["where"])).get("name", n["where"])) if String(n["where"]) != "" else ""
			return "%s\n%s%s. Click to open it in the codex." % [head, String(n["via"]), (" at the " + where.to_lower()) if where != "" else ""]
	return ""
	add_to_group("fs_redraw")

func _max_depth(n: Dictionary) -> int:
	var d := 0
	for c in n["children"]:
		d = maxi(d, 1 + _max_depth(c))
	return d

func _layout() -> void:
	_boxes = []
	_edges = []
	if root_node.is_empty():
		custom_minimum_size = Vector2.ZERO
		return
	_depth = _max_depth(root_node)
	var row := [0]
	_place(root_node, 0, row)
	custom_minimum_size = Vector2(float(_depth) * col_w + NODE.x + 16.0, maxf(1.0, float(row[0])) * ROW_H + 8.0)

## Returns the y centre of the placed node; leaves take the next row, parents sit between children.
func _place(n: Dictionary, depth: int, row: Array) -> float:
	var x: float = 8.0 + float(_depth - depth) * col_w
	var y: float
	var kids: Array = []
	if (n["children"] as Array).is_empty():
		y = 4.0 + float(row[0]) * ROW_H + NODE.y * 0.5
		row[0] += 1
	else:
		for c in n["children"]:
			kids.append(_place(c, depth + 1, row))
		y = (float(kids.front()) + float(kids.back())) * 0.5
	var r := Rect2(Vector2(x, y - NODE.y * 0.5), NODE)
	_boxes.append({"rect": r, "item": String(n["item"]), "node": n})
	var i := 0
	for c in n["children"]:
		var cy: float = kids[i]
		var cx: float = x - col_w + NODE.x
		_edges.append({"a": Vector2(cx, cy), "b": Vector2(x, y), "label": ""})
		i += 1
	if not (n["children"] as Array).is_empty():
		var lab: String = String(n["via"])
		if String(n["where"]) != "":
			lab += " · " + String(hud.data.bdef(String(n["where"])).get("name", n["where"]))
		_edges.append({"a": Vector2(x - (col_w - NODE.x), y), "b": Vector2(x, y), "label": lab})
	return y

## Narrows the columns (not below COL_MIN) so the whole tree fits width w. Returns true when it fits.
func fit_width(w: float) -> bool:
	if _depth <= 0 or w <= 0.0:
		return true
	var cw: float = clampf((w - NODE.x - 16.0) / float(_depth), COL_MIN, COL_W)
	if absf(cw - col_w) > 0.5:
		col_w = cw
		_layout()
		queue_redraw()
	return custom_minimum_size.x <= w + 0.5

## Shortens a label to width w with an ellipsis (the full text is in the tooltip of the node).
static func _trim(font: Font, s: String, w: float, fs: int) -> String:
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
		return s
	var t: String = s
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		t = t.left(t.length() - 1)
	return t.strip_edges() + "…"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := ""
		for bx in _boxes:
			if (bx["rect"] as Rect2).has_point(event.position):
				h = bx["item"]
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for bx in _boxes:
			if (bx["rect"] as Rect2).has_point(event.position):
				picked.emit(String(bx["item"]))
				accept_event()
				return

static func _amount(n: float) -> String:
	if absf(n - roundf(n)) < 0.01:
		return "%d" % int(roundf(n))
	return "%.2f" % n

func _draw() -> void:
	if root_node.is_empty():
		return
	var font: Font = Fonts.get_font("body")
	var mono: Font = Fonts.get_font("mono")
	# Edges: an elbow from each input to its product, then the recipe label over the last leg.
	for e in _edges:
		var a: Vector2 = e["a"]
		var b: Vector2 = e["b"]
		if String(e["label"]) == "":
			var mx: float = b.x - (col_w - NODE.x) * 0.5
			draw_polyline(PackedVector2Array([a, Vector2(mx, a.y), Vector2(mx, b.y), b - Vector2(col_w - NODE.x, 0) * 0.5]), Color(0.55, 0.7, 0.85, 0.55), 1.5, true)
		else:
			draw_line(a + Vector2((col_w - NODE.x) * 0.5, 0), b, Color(0.55, 0.7, 0.85, 0.55), 1.5, true)
			draw_colored_polygon(PackedVector2Array([b, b + Vector2(-7, -4), b + Vector2(-7, 4)]), Color(0.55, 0.7, 0.85, 0.8))
			# The recipe and building, under the product card (clear of the input lines).
			var gap: float = col_w - NODE.x
			var lw: float = NODE.x + gap * 0.5 - 8.0
			draw_string(font, Vector2(b.x - gap * 0.5 + 6.0, b.y + NODE.y * 0.5 + 13.0), _trim(font, String(e["label"]), lw, P.fs(11)), HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(11), P.TEXT_2)
	# Nodes: metal-rimmed cards (the theme's card look), icon, name, amount.
	var card: StyleBox = load("res://ui/theme/ui_theme.gd").panel_style("card_button")
	var card_h: StyleBox = load("res://ui/theme/ui_theme.gd").panel_style("card_hover")
	for bx in _boxes:
		var r: Rect2 = bx["rect"]
		var it: String = bx["item"]
		var n: Dictionary = bx["node"]
		draw_style_box(card_h if it == _hover else card, r)
		# Tier stripe on the left (basic grey, mid cyan, high-end gold: ui/data.gd item_tier).
		var tr: int = hud.data.item_tier(it)
		if tr > 0:
			draw_rect(Rect2(r.position + Vector2(3, 6), Vector2(3, r.size.y - 12)), load("res://ui/data.gd").TIER_COLOR[tr], true)
		var tex: Texture2D = Icons.tex(Icons.item(it), 22)
		if tex != null:
			draw_texture_rect(tex, Rect2(r.position + Vector2(8, 11), Vector2(22, 22)), false, hud.data.item_color(it))
		draw_string(font, r.position + Vector2(36, 19), hud.data.item_name(it), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 44.0, P.fs(13), P.TEXT)
		var sub: String = "× " + _amount(float(n["n"])) + ("  raw" if bool(n["raw"]) else "")
		draw_string(mono, r.position + Vector2(36, 36), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 44.0, P.fs(12), P.TEXT_2 if not bool(n["raw"]) else P.AMBER)
