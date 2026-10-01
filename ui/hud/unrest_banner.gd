extends PanelContainer
## Unrest (V5_DESIGN §6.4, §10): a card in the Events tab, and the urgent line, of the panel manager (it
## places it; Paul, 2026-10-01: nothing over the centre) while a base is at Protest, Strike or Riot, or locked down: the stage, the base, the demand the people shout, and the response buttons. Each
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
	["amnesty", "Amnesty", "Prisoners go free. Unrest falls. Security morale falls.", "unrest -25 · guards unhappy"],
	["replace_captain", "Replace the captain", "A new captain for the angry department. The old one is unhappy.", "unrest -15 · old captain unhappy"],
	["arrest_ringleaders", "Arrest the ringleaders", "Security arrests them. Unrest falls only if people think it is fair.", "unrest -10, or +15 if unfair"],
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
var _btn := {}    # response -> Button
var _grid: GridContainer
var _lock: Label       # lockdown: doors open in … (SIM unrest.lock_info)
var lock_base := -2    # the locked base shown (tests; -2 none)
var _eff := {}    # response -> effect Label

func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.set_border_width_all(2)
	_style.border_width_left = 6
	_style.set_corner_radius_all(4)
	_style.content_margin_left = 16
	_style.content_margin_right = 14
	_style.content_margin_top = 10
	_style.content_margin_bottom = 12
	# _style keeps the stage colours (the panel manager colours the card by them); it is not this node's frame.
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
	_lock = Kit.head("", Color("7FD4FF"), 13, "head")
	_lock.name = "Lockdown"
	v.add_child(_lock)
	var grid: GridContainer = Kit.grid(2, 6, 6)   # 2 columns: the dock is narrow
	_grid = grid
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
		_btn[id] = b
		var el: Label = Kit.label(eff, "SmallLabel", 11, P.TEXT_2)
		el.set_meta("effect", id)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # two short lines, never cut
		cell.add_child(el)
		_eff[id] = el
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
	# Lockdown (response lock_down; SIM unrest.lock_info): the doors of a base are closed for a time.
	lock_base = -2
	var left := 0.0
	for b in ids:
		var li: Dictionary = hud.v5.lock_info(int(b))
		if bool(li.get("locked", false)):
			lock_base = int(b)
			left = float(li.get("seconds_left", 0.0))
			break
	var lock_txt: String = ("LOCKDOWN%s  ·  DOORS OPEN IN %s" % [(" AT " + String(s.bases.name_of(lock_base)).to_upper()) if lock_base >= 0 and s.bases.count() > 1 else "", Kit.clock(left)]) if lock_base != -2 else ""
	_lock.text = lock_txt
	_lock.visible = lock_txt != ""
	visible = st in LOUD or lock_base != -2
	shown_stage = st if st in LOUD else ("lockdown" if lock_base != -2 else "")
	if not visible:
		return
	_grid.visible = st in LOUD
	if not (st in LOUD):
		# Only the lockdown: a short banner with the time left.
		base_id = lock_base
		_style.bg_color = Color(0.03, 0.09, 0.14, 0.92)
		_style.border_color = Color("7FD4FF")
		_damage.visible = false
		_demand.visible = false
		_text.text = "LOCKDOWN"
		_text.add_theme_color_override("font_color", Color("7FD4FF"))
		_icon.modulate = Color("7FD4FF")
		_sub.text = "People stay in their rooms: no riot can spread, no leisure, and unrest rises a little. The doors open when the time is over."
		tooltip_text = "Lockdown
Ordered with the Lock down response (the unrest banner or Crew, Security)."
		Kit.fit(self)
		return
	base_id = best_b
	var col: Color = STAGE_COL.get(st, P.AMBER)
	_style.bg_color = Color(0.22, 0.03, 0.05, 0.92) if st == "riot" else (Color(0.16, 0.10, 0.02, 0.90) if st == "protest" else Color(0.17, 0.07, 0.02, 0.90))
	_style.border_color = col
	_damage.visible = st == "riot"
	if st == "riot":
		var dmg = best.get("damage", null)
		var inj = best.get("injured", null)
		_damage.text = "DAMAGE: %s  ·  INJURED: %s%s" % [("%d rooms" % int(dmg)) if dmg != null else "not reported yet", str(int(inj)) if inj != null else "not reported yet",
			("  ·  LOOTED: %d" % int(best["looted"])) if best.get("looted", null) != null else ""]
	_text.text = "%s%s  ·  UNREST %d" % [STAGE_TEXT[st], (" AT " + String(s.bases.name_of(best_b)).to_upper()) if best_b >= 0 else "", int(best["value"])]
	_text.add_theme_color_override("font_color", col)
	_icon.modulate = col
	_sub.text = STAGE_SUB[st]
	_responses(best)
	var dm: String = String(best.get("demand", ""))
	_demand.text = ("They shout: \"%s\"" % dm) if dm != "" else ""
	_demand.visible = dm != ""
	var causes: Array = []
	for c in best.get("causes", []):
		causes.append("%s (+%d)" % [String(c["text"]), int(float(c["delta"]))])
	tooltip_text = "Unrest %d\nCauses: %s" % [int(best["value"]), ", ".join(causes) if not causes.is_empty() else "none named"]
	Kit.fit(self)

## Each response's effect from SIM's numbers (content/society.json "responses": unrest, cost,
## unfair_unrest, lock_hours, cooldown_days) when they exist, else the UI's estimate; a response SIM
## says is not ready (used recently) is disabled.
func _responses(u: Dictionary) -> void:
	var cfg: Dictionary = hud.main.sim.content.get("society", {}).get("responses", {}) if typeof(hud.main.sim.content) == TYPE_DICTIONARY else {}
	var ready: Dictionary = u.get("responses", {})
	for r in RESPONSES:
		var id: String = r[0]
		var c: Dictionary = cfg.get(id, {})
		var txt: String = String(r[3])
		var est := true
		if not c.is_empty():
			est = false
			var parts: Array = ["unrest %+d" % int(c.get("unrest", 0))]
			if c.has("unfair_unrest"):
				parts[0] += ", or %+d if unfair" % int(c["unfair_unrest"])
			for item in c.get("cost", {}):
				parts.append("uses %d %s" % [int(c["cost"][item]), String(item).replace("_", " ")])
			if c.has("lock_hours"):
				parts.append("%d h lockdown" % int(c["lock_hours"]))
			if bool(c.get("leisure", false)):
				parts.append("no work")
			if bool(c.get("release", false)):
				parts.append("prisoners go free")
			txt = " · ".join(parts)
		var ok: bool = bool(ready.get(id, true))
		# SIM's own effect and cost (sim.unrest.response_effect, 2026-10-01): the stock a party uses now,
		# the demand, the lock hours. It replaces the table above.
		var un = hud.main.sim.get("unrest")
		if un != null and (un as Object).has_method("response_effect"):
			var fx: Dictionary = un.response_effect(base_id, id)
			if not fx.is_empty():
				est = false
				txt = "unrest %+d · %s" % [int(fx.get("unrest", 0)), String(fx.get("cost", ""))]
				ok = bool(fx.get("ready", ok))
		if _eff.has(id):
			(_eff[id] as Label).text = txt if ok else "not ready: used recently"
		if _btn.has(id):
			var b: Button = _btn[id]
			b.disabled = not ok
			b.tooltip_text = "%s\n%s\nEffect: %s%s.%s" % [r[1], r[2], txt, " (an estimate)" if est else "", "" if ok else "\nUsed recently: ready again after %s day(s)." % str(c.get("cooldown_days", 1))]

func _ask(id: String, nm: String, what: String) -> void:
	var danger: bool = id in ["lock_down", "arrest_ringleaders", "amnesty"]
	hud.confirm("%s?" % nm, [what], func():
		last_result = hud.v5.command("unrest_response", {"base": base_id, "response": id})
		hud.toast("%s: %s" % [nm, String(last_result.get("text", ""))], "info" if bool(last_result.get("ok", false)) else "warn", "people"), nm, danger)
