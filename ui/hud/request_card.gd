extends PanelContainer
## Request card (V5_DESIGN §4.2, §10): a person asks the player something (SIM sim.relations.requests()).
## The card shows at the top centre, under the unrest banner, until the player answers. Kinds:
##   leave_with_ship  a colonist in love with a visitor wants to leave on the ship. Let them go (confirm
##                    first: they leave for good) or Refuse (they stay; unhappy for 3 days).
##   shared_home      partners want a home together and there is no free unit. Try again (after you
##                    build a home) or Keep apart (both unhappy for 3 days).
## File opens the personnel file; Show moves the camera to the person.
## Answer: command answer_request {id, answer "allow" | "refuse"} (sim/relations.gd).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")

## kind -> [head, icon, colour, allow button, allow effect, confirm the allow, refuse button, refuse effect]
const KIND := {
	"leave_with_ship": ["LEAVE WITH A SHIP", "heart", Color("F472B6"), "Let them go", "They leave the colony on the ship. You lose a colonist and their skills.", true,
		"Refuse", "They stay. Satisfaction (freedom) and attitude fall for 3 days."],
	"shared_home": ["A HOME FOR TWO", "home", Color("4FC3F7"), "Try again", "They move in together when a unit for two is free. Build a residence tube or an apartment block first.", false,
		"Keep apart", "They stay in their homes. Satisfaction (housing) and attitude fall for 3 days."],
}
const OTHER := ["A REQUEST", "people", Color("4FC3F7"), "Allow", "The simulation does what they ask.", true, "Refuse", "They do not get what they asked for."]

var hud
var request: Dictionary = {}     # the request shown now (tests)
var last_result: Dictionary = {}  # tests
var _icon: TextureRect
var _head: Label
var _text: Label
var _more: Label
var _allow: Button
var _refuse: Button
var _eff: Label
var _style: StyleBoxFlat
var _poll := 1.0
var _sig := ""

func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.07, 0.07, 0.12, 0.92)
	_style.border_color = Color("F472B6")
	_style.set_border_width_all(2)
	_style.border_width_left = 6
	_style.set_corner_radius_all(4)
	_style.content_margin_left = 16
	_style.content_margin_right = 14
	_style.content_margin_top = 10
	_style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", _style)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = 76
	custom_minimum_size.x = 520
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	name = "RequestCard"
	var v: VBoxContainer = Kit.vbox(6)
	add_child(v)
	var h: HBoxContainer = Kit.hbox(10)
	v.add_child(h)
	_icon = Kit.icon("heart", 22, Color("F472B6"))
	h.add_child(_icon)
	var tv: VBoxContainer = Kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	_head = Kit.head("", Color("F472B6"), 13, "head_wide")
	tv.add_child(_head)
	_text = Kit.wrap("", 14, P.TEXT, 440.0)
	tv.add_child(_text)
	_more = Kit.label("", "SmallLabel", 12, P.TEXT_3)
	v.add_child(_more)
	var row: HBoxContainer = Kit.hbox(8)
	v.add_child(row)
	_allow = Kit.button("Allow", func(): _ask_allow(), "", "DangerButton", "sev_ok", 14)
	row.add_child(_allow)
	_refuse = Kit.button("Refuse", func(): _answer("refuse"), "", "PrimaryButton", "close", 14)
	row.add_child(_refuse)
	row.add_child(Kit.spacer())
	row.add_child(Kit.button("File", func(): hud.open_person(int(request.get("agent", -1)), "file"), "Personnel file\nMood, skills and relationships of this person.", "GhostButton", "colonists", 14))
	row.add_child(Kit.button("Show", func(): _show(), "Show\nThe camera goes to this person.", "GhostButton", "target", 14))
	_eff = Kit.wrap("", 12, P.TEXT_2, 440.0)
	_eff.name = "Effect"
	v.add_child(_eff)

func _process(delta: float) -> void:
	if hud == null or hud.v5 == null:
		return
	_poll += delta
	if _poll >= 1.0:
		_poll = 0.0
		update()
	if visible:
		# Under the hazard, reactor and unrest banners when they show.
		var y := 76.0
		for bnr in [hud.hazard_banner, hud.reactor_banner, hud.unrest_banner]:
			if bnr != null and bnr.visible:
				y = maxf(y, bnr.get_global_rect().end.y + 8.0)
		offset_top = y

func _spec() -> Array:
	return KIND.get(String(request.get("kind", "")), OTHER)

## Shows the oldest open request (or hides the card).
func update() -> void:
	var reqs: Array = hud.v5.requests()
	visible = not reqs.is_empty()
	if reqs.is_empty():
		request = {}
		_sig = ""
		return
	request = reqs[0]
	var sig: String = "%d:%s:%d:%d" % [int(request.get("id", -1)), String(request.get("kind", "")), int(request.get("agent", -1)), reqs.size()]
	if sig == _sig:
		return
	_sig = sig
	var spec: Array = _spec()
	_head.text = "%s  ·  %s" % [spec[0], hud.v5.agent_name(int(request.get("agent", -1))).to_upper()]
	_head.add_theme_color_override("font_color", spec[2])
	Kit.set_icon(_icon, spec[1], 22, spec[2])
	_style.border_color = spec[2]
	_text.text = String(request.get("text", ""))
	_allow.text = String(spec[3])
	_allow.theme_type_variation = "DangerButton" if bool(spec[5]) else ""
	_allow.tooltip_text = "%s\n%s%s" % [spec[3], spec[4], "\nYou confirm first." if bool(spec[5]) else ""]
	_refuse.text = String(spec[6])
	_refuse.tooltip_text = "%s\n%s" % [spec[6], spec[7]]
	_eff.text = "%s: %s\n%s: %s" % [spec[3], spec[4], spec[6], spec[7]]
	_more.text = ("%s more after this one." % Kit.plural(reqs.size() - 1, "request")) if reqs.size() > 1 else ""
	_more.visible = reqs.size() > 1
	Kit.fit(self)

func _show() -> void:
	var id: int = int(request.get("agent", -1))
	var a: Dictionary = hud.v5.agent(id)
	if not a.is_empty():
		hud.main.select("agent", id)
		hud.main.focus_on(a["pos"])

## Allow: at once, or after a confirm when it cannot be undone (a colonist leaving).
func _ask_allow() -> void:
	var spec: Array = _spec()
	if not bool(spec[5]):
		_answer("allow")
		return
	var nm: String = hud.v5.agent_name(int(request.get("agent", -1)))
	hud.confirm("%s: %s?" % [spec[3], nm], [spec[4], "This cannot be undone."], func(): _answer("allow"), String(spec[3]), true)

func _answer(ans: String) -> void:
	if request.is_empty():
		return
	last_result = hud.v5.command("answer_request", {"id": int(request["id"]), "answer": ans})
	hud.toast(String(last_result.get("text", "")), "info" if bool(last_result.get("ok", false)) else "warn", String(_spec()[1]))
	hud.v5.request_override = []
	_sig = ""
	update()
