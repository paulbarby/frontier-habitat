extends PanelContainer
## Unrest banner (V5_DESIGN §6.4, §10): a banner at the top centre while a base is at Protest,
## Strike or Riot: the stage, the base, the demand the people shout, and the response buttons. Each
## response says its cost and asks to confirm, then goes to SIM (command unrest_response). Riot pulses
## red. The top bar's unrest meter shows every stage; this banner only the three loud ones.
## Data: ui/v5_data.gd unrest(base) (SIM sim.social.unrest).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")

const LOUD := ["protest", "strike", "riot"]
const STAGE_TEXT := {"protest": "PROTEST", "strike": "STRIKE", "riot": "RIOT"}
const STAGE_SUB := {"protest": "A crowd gathers and shouts its demand.", "strike": "A department stops work until the demand is met.",
	"riot": "Fights break out. Rioters damage rooms and break into storage."}
## [id, button, what it does and costs, the effect in short] (V5 §6.4 player responses). The short
## effect is under each button (critic round 30, fix 5); SIM's own numbers replace it when
## sim.social.response_effect(base, id) exists.
const RESPONSES := [
	["meet_demand", "Meet the demand", "Do what they ask. Unrest falls fast. It can cost stock or rules.", "unrest -40 · costs stock or a rule"],
	["leisure_day", "Leisure day", "Everyone gets a free day. Unrest falls. No work today.", "unrest -20 · no work today"],
	["party", "Party at the bar", "Unrest falls. Uses drinks and snacks from storage.", "unrest -15 · uses drinks, snacks"],
	["amnesty", "Amnesty", "Prisoners go free. Unrest falls. Security morale falls.", "unrest -25 · security morale down"],
	["replace_captain", "Replace the captain", "A new captain for the angry department. The old one is unhappy.", "unrest -15 · old captain unhappy"],
	["arrest_ringleaders", "Arrest the ringleaders", "Security arrests them. Unrest falls only if people think it is fair.", "unrest -10 if fair, +15 if not"],
	["lock_down", "Lock down", "The doors of the zone close. A riot cannot spread, but unrest rises.", "riot cannot spread · unrest +10"],
]
## The frame by stage (critic round 30, fix 4): protest amber, strike orange, riot red (pulsing).
const STAGE_COL := {"protest": Color("FFB547"), "strike": Color("FF8A3D"), "riot": Color("FF3B45")}

var hud
var base_id := -1
var shown_stage := ""      # tests
var _icon: TextureRect
var _text: Label
var _sub: Label
var _demand: Label
var _row: HFlowContainer
var _t := 0.0
var _poll := 1.0
var last_result: Dictionary = {}
var _damage: Label
var _style: StyleBoxFlat

func _ready() -> void:
	_style = StyleBoxFlat.new()
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
	custom_minimum_size.x = 680
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(4)
	add_child(v)
	var h: HBoxContainer = Kit.hbox(10)
	v.add_child(h)
	_icon = Kit.icon("people", 24, P.AMBER)
	h.add_child(_icon)
	var tv: VBoxContainer = Kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	_text = Kit.head("", P.AMBER, 14, "head_wide")
	tv.add_child(_text)
	_sub = Kit.label("", "", 13, P.TEXT)
	tv.add_child(_sub)
	_demand = Kit.head("", P.TEXT, 15, "head")
	v.add_child(_demand)
	# Riot: what the rioters did so far (critic round 30, fix 4). SIM's unrest(base) damage / injured.
	_damage = Kit.head("", Color("FF6B72"), 13, "head")
	_damage.name = "Damage"
	v.add_child(_damage)
	var grid: GridContainer = Kit.grid(4, 8, 6)
	v.add_child(grid)
	for r in RESPONSES:
		var id: String = r[0]
		var nm: String = r[1]
		var what: String = r[2]
		var eff: String = r[3]
		var cell: VBoxContainer = Kit.vbox(1)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b: Button = Kit.button(nm, func(): _ask(id, nm, what), "%s\n%s\nEffect: %s (an estimate)." % [nm, what, eff], "DangerButton" if id in ["lock_down", "arrest_ringleaders"] else "", "", 13)
		b.set_meta("response", id)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(b)
		var el: Label = Kit.label(eff, "SmallLabel", 11, P.TEXT_2)
		el.set_meta("effect", id)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(el)
		grid.add_child(cell)

func _process(delta: float) -> void:
	if hud == null or hud.v5 == null:
		return
	_t += delta
	_poll += delta
	if _poll >= 1.0:
		_poll = 0.0
		_update()
	if visible:
		# A riot pulses: the red frame and its glow beat (the text stays readable).
		var col: Color = STAGE_COL.get(shown_stage, P.AMBER)
		var k: float = (0.5 + 0.5 * sin(_t * 6.0)) if shown_stage == "riot" else 0.0
		_style.border_color = col.lerp(Color.WHITE, 0.35 * k)
		_style.shadow_color = Color(col.r, col.g, col.b, 0.25 + 0.35 * k) if shown_stage == "riot" else Color(0, 0, 0, 0.35)
		_style.shadow_size = int(6.0 + 10.0 * k) if shown_stage == "riot" else 4
		position.x = floorf((get_viewport_rect().size.x - size.x) * 0.5)
		# Under the reactor and hazard banners when they show.
		var y := 76.0
		for bnr in [hud.hazard_banner, hud.reactor_banner]:
			if bnr != null and bnr.visible:
				y = maxf(y, bnr.get_global_rect().end.y + 8.0)
		offset_top = y

## The loudest base (the whole colony when there are no bases).
func _update() -> void:
	var best: Dictionary = {}
	var best_b := -1
	var s = hud.main.sim
	var ids: Array = s.bases.ids() if s.get("bases") != null and s.bases.count() > 1 else [-1]
	for b in ids:
		var u: Dictionary = hud.v5.unrest(int(b))
		if u.is_empty():
			continue
		if best.is_empty() or float(u["value"]) > float(best["value"]):
			best = u
			best_b = int(b)
	var st: String = String(best.get("stage", "calm"))
	visible = st in LOUD
	shown_stage = st if visible else ""
	if not visible:
		return
	base_id = best_b
	var col: Color = STAGE_COL.get(st, P.AMBER)
	_style.bg_color = Color(0.22, 0.03, 0.05, 0.92) if st == "riot" else (Color(0.16, 0.10, 0.02, 0.90) if st == "protest" else Color(0.17, 0.07, 0.02, 0.90))
	_style.border_color = col
	_damage.visible = st == "riot"
	if st == "riot":
		var dmg = best.get("damage", null)
		var inj = best.get("injured", null)
		_damage.text = "DAMAGE: %s  ·  INJURED: %s" % [("%d rooms" % int(dmg)) if dmg != null else "not reported yet", str(int(inj)) if inj != null else "not reported yet"]
	_text.text = "%s%s  ·  UNREST %d" % [STAGE_TEXT[st], (" AT " + String(s.bases.name_of(best_b)).to_upper()) if best_b >= 0 else "", int(best["value"])]
	_text.add_theme_color_override("font_color", col)
	_icon.modulate = col
	_sub.text = STAGE_SUB[st]
	var dm: String = String(best.get("demand", ""))
	_demand.text = ("They shout: \"%s\"" % dm) if dm != "" else ""
	_demand.visible = dm != ""
	var causes: Array = []
	for c in best.get("causes", []):
		causes.append("%s (+%d)" % [String(c["text"]), int(float(c["delta"]))])
	tooltip_text = "Unrest %d\nCauses: %s" % [int(best["value"]), ", ".join(causes) if not causes.is_empty() else "none named"]
	Kit.fit(self)

func _ask(id: String, nm: String, what: String) -> void:
	var danger: bool = id in ["lock_down", "arrest_ringleaders", "amnesty"]
	hud.confirm("%s?" % nm, [what], func():
		last_result = hud.v5.command("unrest_response", {"base": base_id, "response": id})
		hud.toast("%s: %s" % [nm, String(last_result.get("text", ""))], "info" if bool(last_result.get("ok", false)) else "warn", "people"), nm, danger)
