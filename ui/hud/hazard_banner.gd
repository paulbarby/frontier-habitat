extends PanelContainer
## The hazard banner (docs/V3_DESIGN.md §8): top centre, for the soonest detected event that
## is less than 30 seconds away. "METEOR STRIKE IN 0:24", the place, covered or not, the
## advice, and a Shelter button for a solar flare. It sits right of the hazard panel. It
## plays the warning sound once per event and never takes the mouse except on its buttons.
## Hidden (no draw calls) otherwise.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const HazardPanel = preload("res://ui/hud/hazard_panel.gd")

const SECONDS := 30.0

var hud
var _icon: TextureRect
var _title: Label
var _line: Label
var _btns: HBoxContainer
var _ev_id = null

func _ready() -> void:
	theme_type_variation = "ToastPanel"
	Glass.attach(self, [10, 0, 10, 0])
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size.x = 460
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var h: HBoxContainer = Kit.hbox(14)
	add_child(h)
	_icon = Kit.icon("meteor", 34, P.RED)
	h.add_child(_icon)
	var v: VBoxContainer = Kit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_title = Kit.label("", "TitleLabel", 22, P.RED)
	v.add_child(_title)
	_line = Kit.wrap("", 13, P.TEXT, 360)
	v.add_child(_line)
	_btns = Kit.hbox(6)
	_btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_btns)

func refresh() -> void:
	var soon = null
	# The hazard panel refreshed its rows just before (hud.gd order).
	for r in hud.hazard._rows if hud.hazard != null else []:
		if not bool(r["active"]) and float(r["eta_s"]) < SECONDS:
			soon = r
			break
	if soon == null:
		if visible:
			visible = false
		_ev_id = null
		return
	var col: Color = P.CYAN if bool(soon["countered"]) else (P.RED if int(soon["severity"]) >= 2 else P.AMBER)
	if not visible or _ev_id != soon["id"]:
		# A new event under 30 s: build the buttons, sound once.
		_ev_id = soon["id"]
		visible = true
		Kit.clear(_btns)
		if soon["pos"] != null:
			var p: Vector2 = soon["pos"]
			var show: Button = Kit.button("Show", func(): hud.main.focus_on(p), "Show\nThe camera goes to the place.", "", "target", 14)
			show.custom_minimum_size.y = 30
			_btns.add_child(show)
		if String(soon["kind"]) == "solar_flare":
			_btns.add_child(HazardPanel.shelter_button(hud))
		Kit.set_icon(_icon, hud.data.hazard_icon(String(soon["kind"])), 34, col)
		Kit.sfx("alert_critical" if col == P.RED else "alert_warning")
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	_title.text = ("%s in %s" % [soon["name"], Kit.clock(soon["eta_s"])]).to_upper()
	_title.add_theme_color_override("font_color", col)
	_line.text = "%s.  %s.  %s" % [hud.data.place_text(soon["pos"]), "Covered" if bool(soon["countered"]) else "Not covered", String(soon["advice"])]
	Kit.fit(self)
	_place()

## Top, centred, but never over the hazard panel or the inspector: it moves right of the
## panel when needed; when the top has no room, it goes above the build bar.
func _place() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var w: float = size.x
	var x: float = (vp.x - w) * 0.5
	var lo: float = 0.0
	var hp: Control = hud.hazard
	if hp != null and hp.visible:
		lo = hp.position.x + hp.size.x + 12.0
	var hi: float = vp.x - 70.0 - hud.right_inset() - w
	x = clampf(x, lo, maxf(lo, hi))
	if x <= hi:
		position = Vector2(x, 80.0)
		return
	var mm: Control = hud.minimap
	var left: float = mm.position.x + mm.size.x + 12.0 if mm != null else 0.0
	var bottom: float = hud.build_bar.tabs_top() - 12.0 if hud.build_bar != null else vp.y - 90.0
	position = Vector2(clampf((vp.x - w) * 0.5, left, maxf(left, vp.x - 70.0 - hud.right_inset() - w)), bottom - size.y)
