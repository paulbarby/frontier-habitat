extends PanelContainer
## Right-side inspector for the selected structure or colonist.
## Structure tabs (only the ones that apply): Overview, Production, Crops, Menu, Upgrade,
## Staff, Stats. Colonist tabs: Status, Nutrition.
## The content is rebuilt only when its structure changes; numbers update in place through
## small bindings, so hover and tooltips stay stable.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")
const Sections = preload("res://ui/hud/inspector_sections.gd")

const WIDTH := 392.0

var hud
var tab := "overview"
var _kind := ""
var _id := -1
var _sig := ""
var _title: Label
var _sub: Label
var _icon: TextureRect
var _badges: HBoxContainer
var _tabs: HBoxContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _footer: HFlowContainer
var _binds: Array = []       # [Callable] run on every refresh
var _accent := P.CYAN
var sections

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -62
	offset_top = 76
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	sections = Sections.new(self)
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	var head: HBoxContainer = Kit.hbox(10)
	v.add_child(head)
	_icon = Kit.icon("info", 26, P.CYAN)
	head.add_child(_icon)
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	_title = Kit.head("", P.TEXT, 16, "head_wide")
	_title.clip_text = true
	tv.add_child(_title)
	_sub = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	_sub.clip_text = true
	tv.add_child(_sub)
	head.add_child(Kit.icon_button("target", func(): _focus(), "Show\nMoves the camera here.", "GhostButton", 16, 30))
	head.add_child(Kit.icon_button("close", func(): hud.main.select("", -1), "Close\nRight click on the ground or Esc clears the selection.", "GhostButton", 16, 30))
	_badges = Kit.hbox(6)
	v.add_child(_badges)
	_tabs = Kit.hbox(3)
	v.add_child(_tabs)
	_body = Kit.vbox(8)
	_scroll = Kit.scroll(_body)
	_scroll.custom_minimum_size = Vector2(WIDTH - 24, 120)
	v.add_child(_scroll)
	_footer = HFlowContainer.new()
	_footer.add_theme_constant_override("h_separation", 6)
	_footer.add_theme_constant_override("v_separation", 6)
	v.add_child(_footer)

func width_used() -> float:
	return (maxf(WIDTH, size.x) + 70.0) if visible else 0.0

func selection_changed() -> void:
	var kind: String = hud.main.view.selected_kind
	var id: int = hud.main.view.selected_id
	if kind != _kind or id != _id:
		_kind = kind
		_id = id
		tab = "overview" if kind == "building" else "status"
		_sig = ""
		if kind != "":
			modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(self, "modulate:a", 1.0, 0.16)
	refresh()

func rebuild() -> void:
	_kind = ""
	_id = -1
	_sig = ""
	visible = false

func set_tab(t: String) -> void:
	tab = t
	_sig = ""
	refresh()

func _focus() -> void:
	var st: Dictionary = hud.main.sim.state
	if _kind == "building" and st["buildings"].has(_id):
		hud.main.focus_on(st["buildings"][_id]["pos"])
	elif _kind == "agent" and st["agents"].has(_id):
		hud.main.focus_on(st["agents"][_id]["pos"])

func refresh() -> void:
	var st: Dictionary = hud.main.sim.state
	var kind: String = hud.main.view.selected_kind
	var id: int = hud.main.view.selected_id
	if kind != _kind or id != _id:
		selection_changed()
		return
	var rec: Dictionary = {}
	if kind == "building":
		rec = st["buildings"].get(id, {})
	elif kind == "agent":
		rec = st["agents"].get(id, {})
	if rec.is_empty():
		if visible:
			visible = false
		if kind != "":
			hud.main.view.select("", -1)
			_kind = ""
			_id = -1
		return
	visible = true
	_fit_height()
	Kit.fit(self)
	var sig: String = sections.signature(kind, rec, tab)
	if sig != _sig:
		_sig = sig
		_rebuild_content(kind, rec)
	for b in _binds:
		(b as Callable).call()

func _fit_height() -> void:
	var bottom: float = hud.build_bar.tabs_top() - 10.0 if hud.build_bar != null else get_viewport_rect().size.y - 90.0
	var room: float = bottom - offset_top - 180.0
	var need: float = _body.get_combined_minimum_size().y + 4.0
	_scroll.custom_minimum_size.y = clampf(minf(need, room), 60.0, 560.0)

func _rebuild_content(kind: String, rec: Dictionary) -> void:
	_binds = []
	Kit.clear(_badges)
	Kit.clear(_tabs)
	Kit.clear(_body)
	Kit.clear(_footer)
	if kind == "building":
		sections.building(rec)
	else:
		sections.agent(rec)
	queue_redraw()

# ---------------------------------------------------------------- used by sections
func set_header(icon_name: String, color: Color, title: String, sub: String) -> void:
	_accent = color
	Kit.set_icon(_icon, icon_name, 26, color)
	_title.text = title.to_upper()
	_sub.text = sub

func add_badge(c: Control) -> void:
	_badges.add_child(c)

func add_tabs(list: Array) -> void:
	# list: [[id, label], ...]; hidden when there is only one tab.
	if list.size() <= 1:
		return
	var ids: Array = []
	for t in list:
		ids.append(t[0])
	if not ids.has(tab):
		tab = ids[0]
	for t in list:
		var id: String = t[0]
		var b: Button = Kit.button(t[1], func(): set_tab(id), "", "TabButton")
		b.toggle_mode = true
		b.set_pressed_no_signal(id == tab)
		b.custom_minimum_size = Vector2(0, 28)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_constant_override("h_separation", 0)
		_tabs.add_child(b)

func body() -> VBoxContainer:
	return _body

func footer() -> HFlowContainer:
	return _footer

func bind(cb: Callable) -> void:
	_binds.append(cb)

func _draw() -> void:
	# Accent strip on the left edge of the header.
	draw_rect(Rect2(0, 14, 3, 30), _accent, true)
