extends Control
## Bottom build bar: category tabs (always shown) and a drawer of building cards for the
## open tab. The drawer stays open while you build; the same tab or Esc closes it.
## Tools on the right: corridor, cable, remove.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")
const BuildCard = preload("res://ui/widgets/build_card.gd")

const TABS := [
	["life", "Life", "cat_life_support", ["life_support"]],
	["food", "Food", "cat_food", ["food"]],
	["habitat", "Habitat", "cat_housing", ["housing", "comfort", "medical"]],
	["industry", "Industry", "cat_industry", ["industry"]],
	["power", "Power", "cat_utilities", ["utilities"]],
	["logistics", "Logistics", "cat_logistics", ["logistics"]],
	["science", "Science", "cat_science", ["science", "space"]],
	["civic", "Civic", "cat_civic", ["civic"]],
]
const TAB_TIP := {"life": "Life support", "food": "Food", "habitat": "Habitat, comfort and medical", "industry": "Industry", "power": "Power",
	"logistics": "Logistics", "science": "Science and space", "civic": "Civic: security, jail and the super dome"}
const TAB_COLOR := {"life": "life_support", "food": "food", "habitat": "housing", "industry": "industry", "power": "utilities", "logistics": "logistics", "science": "science", "civic": "civic"}

var hud
var open_tab := ""
var size_sel := {}          # def id -> last chosen size
var _tab_panel: PanelContainer
var _tab_buttons := {}
var _tool_buttons := {}
var _drawer: PanelContainer
var _cards_box: VBoxContainer
var tier_rows := {}         # tier -> HBoxContainer of cards (tests read this)
var _cards_scroll: ScrollContainer
var _drawer_left := 0.0     # left edge the drawer keeps clear of (minimap, goals, alerts)
var _drawer_title: Label
var _drawer_sub: Label
var _cards := {}
var _counts := {}
var compact := false    # tab names hidden (icons only) when the bar does not fit beside the minimap
var _full_w := 0.0      # bar width with the tab names

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_panel = Kit.panel("HudPanel")
	_tab_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tab_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tab_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tab_panel.offset_bottom = -8
	add_child(_tab_panel)
	var row: HBoxContainer = Kit.hbox(4)
	_tab_panel.add_child(row)
	row.add_child(Kit.icon("build", 18, P.CYAN))
	row.add_child(Kit.gap(2))
	for t in TABS:
		var id: String = t[0]
		var b: Button = Kit.button(t[1], func(): toggle_tab(id), "%s\nOpen the %s structures." % [t[1], String(t[1]).to_lower()], "TabButton", t[2], 16)
		b.toggle_mode = true
		b.add_theme_color_override("icon_normal_color", P.cat(TAB_COLOR[id]))
		b.add_theme_color_override("icon_hover_color", P.cat(TAB_COLOR[id]).lightened(0.3))
		b.add_theme_color_override("icon_pressed_color", Color.WHITE)
		b.custom_minimum_size = Vector2(0, 34)
		row.add_child(b)
		_tab_buttons[id] = b
		var count := Label.new()
		count.add_theme_font_size_override("font_size", 10)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_counts[id] = count
	row.add_child(Kit.vsep())
	for spec in [["corridor", "Corridor", "corridor", "Corridor\nJoins two rooms: people, power, water and air. 1 steel + 1 polymer per started 10 m. Click the first room, then the second.", "Button"],
			["cable", "Cable", "cable", "Utility cable\nJoins any two structures: power and water only. 1 steel per started 20 m.", "Button"],
			["demolish", "Remove", "demolish", "Remove\nCancel a plan, or take down a structure. Half of its materials come back. Key Delete removes the selected one.", "DangerButton"]]:
		var kind: String = spec[0]
		var cb: Callable
		if kind == "demolish":
			cb = func(): hud.main.start_demolish()
		else:
			cb = func(): hud.main.start_link(kind)
		var b: Button = Kit.icon_button(spec[2], cb, spec[3], spec[4], 18, 38)
		b.custom_minimum_size = Vector2(40, 34)
		b.toggle_mode = true
		row.add_child(b)
		_tool_buttons[kind] = b
	# Drawer
	_drawer = Kit.panel("HudPanel")
	_drawer.add_theme_stylebox_override("panel", load("res://ui/theme/ui_theme.gd").panel_style("reading_hud"))   # critic round 30
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_drawer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_drawer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drawer.offset_bottom = -64
	_drawer.visible = false
	add_child(_drawer)
	var dv: VBoxContainer = Kit.vbox(8)
	_drawer.add_child(dv)
	var dh: HBoxContainer = Kit.hbox(8)
	dv.add_child(dh)
	_drawer_title = Kit.head("", P.TEXT, 13, "head_wide")
	dh.add_child(_drawer_title)
	_drawer_sub = Kit.label("", "SmallLabel", 11, P.TEXT_3)
	_drawer_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(_drawer_sub)
	dh.add_child(Kit.icon_button("close", func(): close_drawer(), "Close\nEsc closes the drawer too.", "GhostButton", 14, 26))
	_cards_box = Kit.vbox(6)
	_cards_scroll = ScrollContainer.new()
	_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_cards_scroll.add_child(_cards_box)
	dv.add_child(_cards_scroll)

func toggle_tab(id: String) -> void:
	if open_tab == id:
		close_drawer()
		return
	open_tab = id
	_fill()
	_drawer.visible = true
	_drawer.modulate.a = 0.0
	var tw := _drawer.create_tween()
	tw.tween_property(_drawer, "modulate:a", 1.0, 0.16)
	Kit.sfx("open")
	refresh()

func close_drawer() -> void:
	open_tab = ""
	_drawer.visible = false
	refresh()

func is_open() -> bool:
	return open_tab != ""

func _defs_for(tab: String) -> Array:
	var cats: Array = []
	for t in TABS:
		if t[0] == tab:
			cats = t[3]
	var out: Array = []
	var blds: Dictionary = hud.main.sim.content["buildings"]
	for id in blds:
		var d: Dictionary = blds[id]
		if String(d.get("kind", "")) == "link" or not bool(d.get("buildable", true)) or String(d.get("kind", "")) == "special":
			continue
		if cats.has(String(d.get("category", ""))):
			out.append(id)
	return out

func _fill() -> void:
	Kit.clear(_cards_box)
	_cards = {}
	var name := ""
	for t in TABS:
		if t[0] == open_tab:
			name = t[1]
	_drawer_title.text = name.to_upper()
	_drawer_title.add_theme_color_override("font_color", P.cat(TAB_COLOR.get(open_tab, "logistics")))
	# Milestone 5: group the cards by tier (Basic, Mid, High-end: ui/data.gd building_tier), one
	# row for each tier. The tier tag shows only when the tab has more than one tier. When the
	# rows are wider or taller than the free space, the drawer scrolls (see _fit_drawer).
	var by_tier := {}
	for id in _defs_for(open_tab):
		var tr: int = hud.data.building_tier(id)
		if not by_tier.has(tr):
			by_tier[tr] = []
		by_tier[tr].append(id)
	var tiers: Array = by_tier.keys()
	tiers.sort()
	tier_rows = {}
	var D = load("res://ui/data.gd")
	for tr in tiers:
		var row: HBoxContainer = Kit.hbox(8)
		_cards_box.add_child(row)
		if tiers.size() > 1:
			var tag: VBoxContainer = Kit.vbox(2)
			tag.custom_minimum_size.x = 62
			var stripe := ColorRect.new()
			stripe.color = D.TIER_COLOR.get(tr, P.TEXT_2)
			stripe.custom_minimum_size = Vector2(28, 3)
			stripe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag.add_child(stripe)
			var tl: Label = Kit.head(String(D.TIER_NAME.get(tr, "Tier %d" % tr)), D.TIER_COLOR.get(tr, P.TEXT_2), 11, "head_wide")
			tag.add_child(tl)
			tag.add_child(Kit.label(str(by_tier[tr].size()), "SmallLabel", 11, P.TEXT_3))
			tag.tooltip_text = "%s tier\n%s" % [String(D.TIER_NAME.get(tr, "")), ["", "Makes basic materials from local resources.", "Makes mid materials: alloys, titanium, ceramics, parts.", "Makes high-end materials: magnets, fuel rods, metamaterials."][clampi(tr, 0, 3)]]
			tag.mouse_filter = Control.MOUSE_FILTER_STOP
			row.add_child(tag)
		var cards: HBoxContainer = Kit.hbox(8)
		row.add_child(cards)
		tier_rows[tr] = cards
		for id in by_tier[tr]:
			var card = BuildCard.new()
			card.setup(hud.data, id, int(size_sel.get(id, 1)))
			card.pick.connect(_pick)
			cards.add_child(card)
			_cards[id] = card
	_fit_drawer()
	call_deferred("_fit_drawer")

## Shrink the drawer to its cards (a tab with fewer rows must not keep the old height) and
## keep its bottom edge above the tab bar.
func _fit_drawer() -> void:
	var vr: Vector2 = get_viewport_rect().size
	var lr: Vector2 = _free_x()
	var pad: Vector2 = _drawer.get_theme_stylebox("panel").get_minimum_size() if _drawer.has_theme_stylebox("panel") else Vector2(24, 24)
	var head_h: float = _drawer_title.get_parent().get_combined_minimum_size().y + 8.0
	var top_min: float = 64.0
	if hud != null and hud.top_bar != null:
		top_min = hud.top_bar.get_global_rect().end.y + 8.0
	var content: Vector2 = _cards_box.get_combined_minimum_size()
	var max_h: float = maxf(200.0, (vr.y + _drawer.offset_bottom) - top_min - head_h - pad.y)
	# A tall drawer (several tier rows) keeps clear of the left panels (goals, alerts, hazards)
	# when it reaches their height.
	var top_y: float = (vr.y + _drawer.offset_bottom) - minf(content.y, max_h) - head_h - pad.y
	if hud != null:
		for pn in [hud.goals, hud.alerts, hud.hazard]:
			if pn != null and pn is Control and (pn as Control).is_visible_in_tree():
				var pr: Rect2 = (pn as Control).get_global_rect()
				if pr.end.y > top_y and pr.get_center().x < vr.x * 0.4:
					lr.x = maxf(lr.x, pr.end.x + 8.0)
	_drawer_left = lr.x
	var max_w: float = maxf(300.0, (lr.y - lr.x) - pad.x)
	var sb := 14.0     # room for a scroll bar
	var w: float = content.x if content.x <= max_w else max_w
	var h: float = content.y if content.y <= max_h else max_h
	if content.x > max_w:
		h = minf(h + sb, max_h)
	if content.y > max_h:
		w = minf(w + sb, max_w)
	_cards_scroll.custom_minimum_size = Vector2(w, h)
	var ms: Vector2 = _drawer.get_combined_minimum_size()
	_drawer.offset_top = _drawer.offset_bottom - ms.y
	_drawer.size = ms

## Free space for the bar and the drawer: x from the minimap's right edge to the nav rail.
func _free_x() -> Vector2:
	var left: float = 236.0
	if hud != null and hud.minimap != null and hud.minimap.visible:
		left = hud.minimap.get_global_rect().end.x + 8.0
	return Vector2(left, get_viewport_rect().size.x - 62.0)

func _pick(def_id: String, size: int) -> void:
	var card = _cards.get(def_id)
	if card != null and card.locked:
		hud.toast("%s is locked. %s" % [hud.data.bdef(def_id).get("name", def_id), card.lock_full.replace("\n", " ") if card.lock_full != "" else card.lock_text], "warn", "lock")
		card.set_pressed_no_signal(false)
		return
	size_sel[def_id] = size
	hud.main.start_place(def_id, size)

func rebuild() -> void:
	size_sel = {}
	if open_tab != "":
		_fill()
	refresh()

func refresh() -> void:
	var m = hud.main
	for id in _tab_buttons:
		(_tab_buttons[id] as Button).set_pressed_no_signal(id == open_tab)
	for k in _tool_buttons:
		var on: bool = (m.tool == "link" and m.tool_def == k) or (m.tool == "demolish" and k == "demolish")
		(_tool_buttons[k] as Button).set_pressed_no_signal(on)
	if open_tab == "":
		return
	var totals: Dictionary = hud.kpi.get("totals", {})
	var locked := 0
	for id in _cards:
		var card = _cards[id]
		if m.tool == "place" and m.tool_def == id:
			card.size_sel = int(m.tool_size)
		card.refresh_state(totals)
		card.set_pressed_no_signal(m.tool == "place" and m.tool_def == id)
		if card.locked:
			locked += 1
	_drawer_sub.text = ("%s, %d locked (the card says what unlocks it; hover for all of it). Red costs are not in storage." % [Kit.plural(_cards.size(), "structure"), locked]) if locked > 0 else ("%s. Red costs are not in storage." % Kit.plural(_cards.size(), "structure"))

func tabs_top() -> float:
	return _tab_panel.position.y

## Centre the bar in the free width between the minimap and the inspector.
func _process(_delta: float) -> void:
	if hud == null:
		return
	var vw: float = get_viewport_rect().size.x
	# Critic round 21, fix 1: the bottom row never overlaps. The bar starts right of the minimap
	# at every interface scale; when it does not fit, the tab names hide (icons stay, the names
	# are in the tooltips) and come back when there is room.
	var left: float = 236.0
	if hud.minimap != null and hud.minimap.visible:
		left = hud.minimap.get_global_rect().end.x + 8.0
	var avail: float = (vw - 62.0) - left
	if not compact:
		_full_w = _tab_panel.size.x
	if not compact and _full_w > avail:
		_set_compact(true)
	elif compact and _full_w > 0.0 and _full_w <= avail - 8.0:
		_set_compact(false)
	for p in [_tab_panel, _drawer]:
		var pc: Control = p
		var left_p: float = maxf(left, _drawer_left) if p == _drawer else left
		var right: float = vw - 62.0
		if hud.inspector.visible and hud.inspector.get_global_rect().end.y > pc.position.y - 8.0:
			right -= hud.inspector.width_used() - 62.0
		var w: float = pc.size.x
		var x: float = clampf((left_p + right) * 0.5 - w * 0.5, left_p, maxf(left_p, right - w))
		if w > right - left_p:
			x = maxf(left_p, (left_p + right) * 0.5 - w * 0.5) if p == _tab_panel else maxf(8.0, (left_p + right) * 0.5 - w * 0.5)
		pc.position.x = x

func _set_compact(on: bool) -> void:
	compact = on
	for t in TABS:
		var b: Button = _tab_buttons[t[0]]
		b.text = "" if on else String(t[1])
	# Shrink to the new width and keep the bottom edge 8 px above the view bottom.
	_tab_panel.reset_size()
	var h: float = _tab_panel.size.y
	_tab_panel.offset_bottom = -8.0
	_tab_panel.offset_top = -8.0 - h

## Top of the bar in logical pixels (for the placement hint and the inspector).
func top_y() -> float:
	if _drawer.visible:
		return _drawer.position.y
	return _tab_panel.position.y
