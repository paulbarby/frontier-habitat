extends PanelContainer
## Follow HUD (V5_DESIGN §3): a small top-left card while the camera follows a person over the
## shoulder. Name, rank and role; a mood face and the satisfaction bar; what they do now ("Off duty —
## talking with Kai"); partner and crush icons; the last 3 lines they said. Buttons: Personnel file
## (review), Next person (Tab), Switch to the person they talk to, Exit (Esc). While it shows, the
## rest of the HUD is dimmed (hud.gd follow_changed); the time controls stay bright.
## Data: ui/v5_data.gd (sim.people, sim.social). RENDER draws the camera and the bubbles.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")
const V5 = preload("res://ui/v5_data.gd")

const MOOD_ICON := V5.MOOD_ICON
const MOOD_COL := V5.MOOD_COL
## The inspector's person rows, folded into the card (critic round 29: the inspector closes while
## following). [label, agent key, inverted].
const NEEDS := [["Health", "health", false], ["Fed", "hunger", true], ["Water", "thirst", true], ["Rested", "fatigue", true]]

var hud
var agent_id := -1
var talk_with := -1          # the person they talk to now (tests)
var _name: Label
var _title: Label
var _mood: TextureRect
var _bar
var _sat: Label
var _doing: Label
var _love: HBoxContainer
var _lines: VBoxContainer
var _switch: Button
var _needs: GridContainer
var _t := 0.0
var _sig := ""

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 8
	offset_top = 76
	custom_minimum_size.x = 340
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(6)
	add_child(v)
	var top: HBoxContainer = Kit.hbox(8)
	v.add_child(top)
	top.add_child(Kit.icon("follow", 18, P.GOLD))
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(Kit.head("Following", P.GOLD, 11))
	_name = Kit.head("", P.TEXT, 15, "head_wide")
	tv.add_child(_name)
	_title = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	tv.add_child(_title)
	_mood = Kit.icon("morale", 26, P.GREEN)
	top.add_child(_mood)
	var sr: HBoxContainer = Kit.hbox(8)
	v.add_child(sr)
	sr.add_child(Kit.dim("Satisfaction", 12))
	_bar = Kit.bar(0.5, P.GREEN, 7.0)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(_bar)
	_sat = Kit.num("", 12, P.TEXT)
	sr.add_child(_sat)
	_needs = Kit.grid(2, 14, 3)
	_needs.name = "Needs"
	v.add_child(_needs)
	for n in NEEDS:
		var r: HBoxContainer = Kit.bar_row(String(n[0]), 1.0, "", P.GREEN, 52.0)
		r.custom_minimum_size.x = 150
		r.set_meta("key", n[1])
		r.set_meta("inv", n[2])
		_needs.add_child(r)
	_doing = Kit.wrap("", 13, P.CYAN)
	_doing.custom_minimum_size.x = 300
	v.add_child(_doing)
	_love = Kit.hbox(6)
	v.add_child(_love)
	_lines = Kit.vbox(2)
	v.add_child(_lines)
	var btn: HBoxContainer = Kit.hbox(4)
	v.add_child(btn)
	btn.add_child(Kit.button("File", func(): hud.open_person(agent_id, "review"), "Personnel file\nReview, discipline, skills and relationships of this person.", "", "colonists", 14))
	btn.add_child(Kit.button("Next", func(): hud.main.follow_next_person(), "Next person\nFollow the next person. Key Tab.", "", "chevron_right", 14))
	_switch = Kit.button("Switch", func(): _switch_to(), "Switch\nFollow the person they talk to now.", "", "people", 14)
	btn.add_child(_switch)
	btn.add_child(Kit.button("Exit", func(): hud.main.follow_end(), "Exit\nBack to the colony view. Key Esc.", "GhostButton", "close", 14))

func show_for(id: int) -> void:
	agent_id = id
	visible = id >= 0
	_sig = ""
	refresh()

func _switch_to() -> void:
	if talk_with >= 0 and hud.main.follow_person(talk_with):
		show_for(talk_with)

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh()

func refresh() -> void:
	var p: Dictionary = hud.v5.person(agent_id)
	if p.is_empty():
		return
	var sv: float = float(p["satisfaction"]["value"])
	var m: int = V5.mood(sv)
	_name.text = String(p["name"]).to_upper()
	_title.text = "%s  ·  %s" % [String(p["rank"]["title"]), String(hud.main.sim.bal.get("role_names", {}).get(p["role"], String(p["role"]).capitalize()))]
	Kit.set_icon(_mood, MOOD_ICON[m], 26, MOOD_COL[m])
	_mood.tooltip_text = "Mood\n%s (satisfaction %d)." % [["Very unhappy", "Unhappy", "So-so", "Content", "Happy"][m], int(sv)]
	_mood.mouse_filter = Control.MOUSE_FILTER_PASS
	_bar.value = sv / 100.0
	_bar.color = P.level(sv, 50.0, 30.0)
	_sat.text = "%d" % int(sv)
	var a: Dictionary = hud.v5.agent(agent_id)
	for r in _needs.get_children():
		var raw: float = float(a.get(String(r.get_meta("key")), 0.0))
		var shown: float = 100.0 - raw if bool(r.get_meta("inv")) else raw
		r.get_child(1).value = shown / 100.0
		r.get_child(1).color = P.level(shown, 50.0, 25.0)
		(r.get_child(2) as Label).text = "%d" % int(shown)
	var t: Dictionary = hud.v5.talk_of(agent_id)
	talk_with = -1
	var doing: String = String(p["activity"])
	if not t.is_empty():
		talk_with = int(t["b"]) if int(t["a"]) == agent_id else int(t["a"])
		doing = "Talking with %s (%s)" % [hud.v5.agent_name(talk_with).get_slice(" ", 0), String(t.get("topic", "")).replace("_", " ")]
	_doing.text = doing
	_switch.disabled = talk_with < 0
	# Partner and a known crush.
	var sig: String = "%d" % agent_id
	var rel: Array = hud.v5.relations(agent_id, 6)
	var lines: Array = hud.v5.recent_lines(agent_id, 3)
	for ln in lines:
		sig += "|" + String(ln.get("text", ""))
	if sig == _sig:
		Kit.fit(self)
		return
	_sig = sig
	Kit.clear(_love)
	for r in rel:
		var st: String = String(r["status"])
		if st in ["dating", "partners", "married", "affair"] or (st == "crush" and bool(r.get("known", false))):
			_love.add_child(Kit.icon("heart", 14, Color("F472B6")))
			_love.add_child(Kit.label("%s: %s" % [String(V5.STATUS_NAME.get(st, st)), hud.v5.agent_name(int(r["other"])).get_slice(" ", 0)], "SmallLabel", 12, P.TEXT_2))
	_love.visible = _love.get_child_count() > 0
	Kit.clear(_lines)
	for ln in lines:
		var l: Label = Kit.wrap("\"%s\"" % String(ln.get("text", "")), 12, P.TEXT_2)
		l.custom_minimum_size.x = 300
		_lines.add_child(l)
	if lines.is_empty():
		_lines.add_child(Kit.label("Nothing said yet.", "SmallLabel", 12, P.TEXT_3))
	Kit.fit(self)
