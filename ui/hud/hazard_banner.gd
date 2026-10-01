extends PanelContainer
## The hazard countdown (docs/V3_DESIGN.md §8), for the soonest detected event that is less than
## 30 seconds away: "METEOR STRIKE IN 0:24", the place, covered or not, the advice, and a Shelter
## button for a solar flare. A card in the Events tab, and the urgent line, of the panel manager
## (Paul, 2026-10-01: nothing over the centre). It plays the warning sound once per event.
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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var h: HBoxContainer = Kit.hbox(10)
	add_child(h)
	_icon = Kit.icon("meteor", 26, P.RED)
	h.add_child(_icon)
	var v: VBoxContainer = Kit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_title = Kit.label("", "TitleLabel", 18, P.RED)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_line = Kit.wrap("", 13, P.TEXT)
	v.add_child(_line)
	_btns = Kit.hbox(6)
	v.add_child(_btns)   # under the text: the dock is narrow

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
		Kit.set_icon(_icon, hud.data.hazard_icon(String(soon["kind"])), 26, col)
		Kit.sfx("alert_critical" if col == P.RED else "alert_warning")
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	_title.text = ("%s in %s" % [soon["name"], Kit.clock(soon["eta_s"])]).to_upper()
	_title.add_theme_color_override("font_color", col)
	_line.text = "%s.  %s.  %s" % [hud.data.place_text(soon["pos"]), "Covered" if bool(soon["countered"]) else "Not covered", String(soon["advice"])]
