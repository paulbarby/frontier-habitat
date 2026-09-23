extends "res://ui/screens/screen.gd"
## New colony: a planet card for each planet in content/scenarios.json (sunlight, wind,
## radiation, terrain), the difficulty from balance.difficulty, and a seed.

var _planet := "dry"
var _diff := "standard"
var _seed: LineEdit
var _cards := {}
var _diffs := {}
var _summary: Label

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
		var b: Button = Kit.button("", func(): _pick_planet(pid), "", "CardButton")
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
		var b2: Button = Kit.button("", func(): _pick_diff(did), "", "CardButton")
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
	_pick_diff(_diff)

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

func _pick_diff(id: String) -> void:
	_diff = id
	for k in _diffs:
		(_diffs[k] as Button).set_pressed_no_signal(k == id)
	_update_summary()

func _update_summary() -> void:
	if _summary == null:
		return
	_summary.text = "%s, %s." % [String(hud.data.planets().get(_planet, {}).get("name", _planet)), String(hud.data.difficulties().get(_diff, {}).get("name", _diff)).to_lower()]

func _start() -> void:
	var seed_value: int = int(_seed.text) if _seed.text.is_valid_int() else 1001
	var go := func(): hud.main.start_new(seed_value, {"planet": _planet, "difficulty": _diff})
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
