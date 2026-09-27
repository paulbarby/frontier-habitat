extends "res://ui/screens/screen.gd"
## New colony: a planet card for each planet in content/scenarios.json (sunlight, wind,
## radiation, terrain), the difficulty from balance.difficulty, and a seed.
## Version 4: the map. "Frontier" (the 2,560 m planet of V4_DESIGN §1, SIM scenario "frontier") is the
## default; "First landing" (810 m, scenario "tutorial") stays for a first game.

var _planet := "dry"
var _diff := "standard"
var _seed: LineEdit
var _cards := {}
var _diffs := {}
var _summary: Label
var _hazards := "normal"
var _hazard_btns := {}
var _scenario := "frontier"
var _scen_btns := {}
const SCENARIOS := [
	["frontier", "Frontier", "2,560 m. Mountains, plateaus, deep craters and crevices. Rare materials lie far out, on dangerous ground.", "map"],
	["tutorial", "First landing", "810 m. A smaller map round the landing site. Good for a first colony.", "ship"],
]

const HAZARD_TEXT := {
	"off": "No hazard events.",
	"mild": "Fewer hazard events.",
	"normal": "The designed rate. Events come more often as the colony grows.",
	"hard": "More hazard events.",
}
const HAZARD_COL := {"off": Color("5EE07A"), "mild": Color("3EE0FF"), "normal": Color("FFB547"), "hard": Color("FF5A5F")}

func _init() -> void:
	pauses = true
	icon = "planet"
	title = "New colony"
	subtitle = "Pick a world, a difficulty and a seed. The same seed gives the same world."
	compact = true
	compact_size = Vector2(1320, 0)

func build() -> void:
	content.add_child(Kit.head("World", P.TEXT_2, 12))
	var row: HBoxContainer = Kit.hbox(14)
	content.add_child(row)
	var planets: Dictionary = hud.data.planets()
	var day_len: float = float(hud.main.sim.bal["day_length"])
	for id in planets:
		var p: Dictionary = planets[id]
		var pid: String = String(id)
		var b: Button = Kit.button("", func(): _pick_planet(pid), "%s\n%s" % [String(p.get("name", pid)), _blurb(pid)], "CardButton")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(300, 250)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v: VBoxContainer = Kit.vbox(8)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 18
		v.offset_right = -18
		v.offset_top = 16
		v.offset_bottom = -14
		b.add_child(v)
		var top: HBoxContainer = Kit.hbox(12)
		v.add_child(top)
		var globe := _Globe.new()
		globe.kind = pid
		top.add_child(globe)
		var tv: VBoxContainer = Kit.vbox(0)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(tv)
		tv.add_child(Kit.label(String(p.get("name", pid)).to_upper(), "TitleLabel", 19, P.TEXT))
		tv.add_child(Kit.label(_blurb(pid), "SmallLabel", 12, P.TEXT_2))
		var g: GridContainer = Kit.grid(2, 16, 4)
		v.add_child(g)
		var day_share: float = float(p.get("daylight_seconds", 360)) / day_len
		_stat(g, "sun", "Daylight", "%d%% of the day" % int(day_share * 100.0), P.GOLD)
		_stat(g, "sun", "Solar output", "x%s" % Kit.fmt(float(p.get("solar_mult", 1.0))), P.GOLD)
		_stat(g, "wind", "Wind", "%s average, %s max" % [Kit.fmt(float(p.get("wind_avg", 0.0))), Kit.fmt(float(p.get("wind_max", 0.0)))], P.CYAN)
		_stat(g, "radiation", "Radiation", "x%s" % Kit.fmt(float(p.get("radiation_mult", 1.0))), P.AMBER if float(p.get("radiation_mult", 1.0)) > 1.0 else P.GREEN)
		_stat(g, "ore", "Mineral deposits", "%d" % int(p.get("terrain", {}).get("deposits", 5)), Color("B07A5A"))
		row.add_child(b)
		_cards[pid] = b
	content.add_child(Kit.head("Map", P.TEXT_2, 12))
	var mrow: HBoxContainer = Kit.hbox(12)
	content.add_child(mrow)
	for sc in SCENARIOS:
		var sid: String = sc[0]
		var bm: Button = Kit.button("", func(): _pick_scenario(sid), "%s map\n%s" % [String(sc[1]), String(sc[2])], "CardButton")
		bm.toggle_mode = true
		bm.custom_minimum_size = Vector2(0, 66)
		bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vm: VBoxContainer = Kit.vbox(2)
		vm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vm.offset_left = 16
		vm.offset_top = 9
		vm.offset_right = -10
		bm.add_child(vm)
		var tm: HBoxContainer = Kit.hbox(6)
		tm.add_child(Kit.icon(String(sc[3]), 15, P.CYAN))
		tm.add_child(Kit.label(String(sc[1]).to_upper(), "TitleLabel", 15, P.TEXT))
		vm.add_child(tm)
		var lm: Label = Kit.label(String(sc[2]), "SmallLabel", 12, P.TEXT_2)
		lm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vm.add_child(lm)
		mrow.add_child(bm)
		_scen_btns[sid] = bm
	content.add_child(Kit.head("Difficulty", P.TEXT_2, 12))
	var drow: HBoxContainer = Kit.hbox(12)
	content.add_child(drow)
	var diffs: Dictionary = hud.data.difficulties()
	for id in diffs:
		var dd: Dictionary = diffs[id]
		var did: String = String(id)
		var lines: Array = []
		lines.append("Cargo x%s" % Kit.fmt(float(dd.get("cargo_mult", 1.0))))
		lines.append("needs x%s" % Kit.fmt(float(dd.get("need_mult", 1.0))))
		lines.append("research x%s" % Kit.fmt(float(dd.get("research_mult", 1.0))))
		lines.append("wear x%s" % Kit.fmt(float(dd.get("wear_mult", 1.0))))
		lines.append("spoilage " + ("on" if bool(dd.get("spoilage", true)) else "off"))
		var b2: Button = Kit.button("", func(): _pick_diff(did), "%s difficulty\n%s." % [String(dd.get("name", did)), ", ".join(lines)], "CardButton")
		b2.toggle_mode = true
		b2.custom_minimum_size = Vector2(0, 74)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v2: VBoxContainer = Kit.vbox(2)
		v2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v2.offset_left = 16
		v2.offset_top = 10
		b2.add_child(v2)
		v2.add_child(Kit.label(String(dd.get("name", did)).to_upper(), "TitleLabel", 16, P.TEXT))
		v2.add_child(Kit.label(", ".join(lines) + ".", "SmallLabel", 12, P.TEXT_2))
		drow.add_child(b2)
		_diffs[did] = b2
	# Hazards (V3_DESIGN §4.2): options.hazards = off | mild | normal | hard.
	content.add_child(Kit.head("Hazards: meteors, storms, quakes, solar flares, breakdowns", P.TEXT_2, 12))
	var hrow: HBoxContainer = Kit.hbox(12)
	content.add_child(hrow)
	var hz_cfg = hud.main.sim.bal.get("hazards", {}).get("settings", {})
	for hid in HAZARD_TEXT:
		var hh: String = String(hid)
		var lines: String = String(HAZARD_TEXT[hh])
		if typeof(hz_cfg) == TYPE_DICTIONARY and hz_cfg.has(hh) and typeof(hz_cfg[hh]) == TYPE_DICTIONARY and hz_cfg[hh].has("rate_mult"):
			lines += " Events x%s." % Kit.fmt(float(hz_cfg[hh]["rate_mult"]))
		var b3: Button = Kit.button("", func(): _pick_hazards(hh), "Hazards: %s\n%s" % [hh, lines], "CardButton")
		b3.toggle_mode = true
		b3.custom_minimum_size = Vector2(0, 76)   # two lines of text stay inside the rim
		b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v3: VBoxContainer = Kit.vbox(2)
		v3.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v3.offset_left = 16
		v3.offset_top = 9
		v3.offset_right = -10
		b3.add_child(v3)
		var t3: HBoxContainer = Kit.hbox(6)
		t3.add_child(Kit.icon("hazard" if hh != "off" else "sev_ok", 15, HAZARD_COL[hh]))
		t3.add_child(Kit.label(hh.to_upper(), "TitleLabel", 15, P.TEXT))
		v3.add_child(t3)
		var l3: Label = Kit.label(lines, "SmallLabel", 12, P.TEXT_2)
		l3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v3.add_child(l3)
		hrow.add_child(b3)
		_hazard_btns[hh] = b3
	var srow: HBoxContainer = Kit.hbox(10)
	content.add_child(srow)
	srow.add_child(Kit.head("Seed", P.TEXT_2, 12))
	_seed = LineEdit.new()
	_seed.text = str(1000 + randi() % 9000)
	_seed.custom_minimum_size = Vector2(160, 40)
	_seed.tooltip_text = "World seed. The same seed gives the same world."
	srow.add_child(_seed)
	srow.add_child(Kit.icon_button("dice", func(): _seed.text = str(1000 + randi() % 90000), "Random seed", "", 18, 40))
	srow.add_child(Kit.gap(20))
	_summary = Kit.label("", "DimLabel", 13, P.TEXT_2)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(_summary)
	var start: Button = Kit.button("Land the colony", func(): _start(), "Start\nThe current colony is lost unless you saved it.", "PrimaryButton", "ship", 18)
	start.custom_minimum_size = Vector2(240, 46)
	srow.add_child(start)
	if not hud.main.sim.has_method("new_game") or hud.data.arg_count(hud.main.sim, "new_game") < 3:
		content.add_child(Kit.label("The planet and difficulty choice is not available yet: the dry world and standard rules are used.", "SmallLabel", 12, P.AMBER))
	_pick_planet(_planet)
	_pick_scenario(_scenario)
	_pick_diff(_diff)
	_pick_hazards(_hazards)

func _stat(g: GridContainer, icon_name: String, name: String, value: String, col: Color) -> void:
	var h: HBoxContainer = Kit.hbox(6)
	h.add_child(Kit.icon(icon_name, 14, col))
	h.add_child(Kit.dim(name, 12))
	g.add_child(h)
	g.add_child(Kit.num(value, 12, P.TEXT))

func _blurb(id: String) -> String:
	match id:
		"dry":
			return "Warm dust, good sun, light wind. The first landing."
		"cold":
			return "Short days and weak sun. Wind turbines carry the night."
		"airless":
			return "Strong sun, no wind, double radiation."
	return ""

func _pick_planet(id: String) -> void:
	_planet = id
	for k in _cards:
		(_cards[k] as Button).set_pressed_no_signal(k == id)
	_update_summary()

func _pick_scenario(id: String) -> void:
	_scenario = id
	for k in _scen_btns:
		(_scen_btns[k] as Button).set_pressed_no_signal(k == id)
	_update_summary()

func _pick_diff(id: String) -> void:
	_diff = id
	for k in _diffs:
		(_diffs[k] as Button).set_pressed_no_signal(k == id)
	_update_summary()

func _pick_hazards(id: String) -> void:
	_hazards = id
	for k in _hazard_btns:
		(_hazard_btns[k] as Button).set_pressed_no_signal(k == id)
	_update_summary()

func _update_summary() -> void:
	if _summary == null:
		return
	_summary.text = "%s, %s map, %s, hazards %s." % [String(hud.data.planets().get(_planet, {}).get("name", _planet)), "frontier" if _scenario == "frontier" else "first-landing", String(hud.data.difficulties().get(_diff, {}).get("name", _diff)).to_lower(), _hazards]

func _start() -> void:
	var seed_value: int = int(_seed.text) if _seed.text.is_valid_int() else 1001
	var go := func(): hud.main.start_new(seed_value, {"planet": _planet, "difficulty": _diff, "hazards": _hazards, "scenario": _scenario})
	if hud.main.on_title:
		go.call()
	else:
		hud.confirm("Start a new colony?", ["The current colony is lost unless you saved it."], go, "Land", true)

class _Globe extends Control:
	var kind := "dry"
	func _ready() -> void:
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var cols := {"dry": [Color("E07A3A"), Color("F2A868")], "cold": [Color("7FA8C9"), Color("D8E8F2")], "airless": [Color("8A8A92"), Color("C9C9CF")]}
		var pair: Array = cols.get(kind, cols["dry"])
		draw_circle(c, 29.0, Color(0, 0, 0, 0.35))
		draw_circle(c, 27.0, pair[0])
		draw_circle(c + Vector2(-7, -7), 19.0, pair[1].lerp(pair[0], 0.4))
		draw_arc(c, 27.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 1.5, true)
		draw_arc(c, 34.0, -0.5, 1.9, 24, Color("3EE0FF"), 1.5, true)
