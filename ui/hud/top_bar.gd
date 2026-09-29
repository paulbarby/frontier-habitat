extends PanelContainer
## Top-left resource bar: headline KPIs with icons, trends, days of supply and rich
## tooltips (breakdown + sparkline), then the building materials.
## Version 4 (V4_DESIGN §2): with more than one base, a base switcher comes first: "All bases" or one
## base. Picking a base moves the camera to its core and filters the alerts panel and the inventory
## screen to that base (hud.base_filter). With one base it is hidden and takes no room.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Kpi = preload("res://ui/widgets/kpi.gd")

var hud
var _k := {}
var _mat_box: HBoxContainer
var _mats := {}
var _base_opt: OptionButton
var _base_ids: Array = []    # option index -> base id (-1 = all bases)
var _base_sig := ""
var _rename_btn: Button
var _pop: PopupPanel
var _pop_edit: LineEdit

const MATERIALS := ["metal", "polymer", "spare_parts", "electronics"]

func _ready() -> void:
	# Version 4 (V4_DESIGN §7): the glass-and-metal HUD bar (pilot of the new theme).
	var st = load("res://ui/theme/glass_frame.gd").new()
	st.kind = "hud"
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 9
	st.content_margin_bottom = 9
	add_theme_stylebox_override("panel", st)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 8
	offset_top = 8
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row: HBoxContainer = Kit.hbox(8)
	add_child(row)
	_base_opt = OptionButton.new()
	_base_opt.visible = false
	_base_opt.custom_minimum_size = Vector2(170, 0)
	_base_opt.clip_text = true
	_base_opt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_base_opt.tooltip_text = "Base\nAll bases, or one base: the camera goes to its core, and the alerts and the inventory show that base only."
	_base_opt.item_selected.connect(func(i: int): hud.set_base_filter(int(_base_ids[i]) if i < _base_ids.size() else -1))
	row.add_child(_base_opt)
	_rename_btn = Kit.icon_button("edit", func(): _open_rename(), "Rename this base\n1 to 32 characters.", "GhostButton", 14, 28)
	_rename_btn.visible = false
	row.add_child(_rename_btn)
	_pop = PopupPanel.new()
	var pv: HBoxContainer = Kit.hbox(8)
	_pop_edit = LineEdit.new()
	_pop_edit.max_length = 32
	_pop_edit.custom_minimum_size.x = 220
	_pop_edit.text_submitted.connect(func(_s): _do_rename())
	pv.add_child(_pop_edit)
	pv.add_child(Kit.button("Rename", func(): _do_rename(), "Rename\nGives the base this name (1 to 32 characters).", "PrimaryButton", "check", 14))
	_pop.add_child(pv)
	add_child(_pop)
	var specs := [
		["pop", "people", P.CATEGORY["housing"], 78], ["o2", "o2", P.CATEGORY["life_support"], 94],
		["water", "water", Color("3AA0D8"), 84], ["power", "power", P.GOLD, 98],
		["energy", "energy", P.CATEGORY["utilities"], 88], ["food", "food", P.CATEGORY["food"], 96],
		["morale", "morale", P.CATEGORY["comfort"], 80], ["unrest", "people", Color("FF8A3D"), 84], ["research", "research", P.VIOLET, 92],
		["credits", "credits", P.GOLD, 78],
	]
	for s in specs:
		var k = Kpi.new()
		k.setup(s[0], s[1], s[2], s[3])
		k.data = hud.data
		k.clicked.connect(_on_kpi)
		row.add_child(k)
		_k[s[0]] = k
	row.add_child(Kit.vsep())
	_mat_box = Kit.hbox(8)
	row.add_child(_mat_box)
	for id in MATERIALS:
		var k = Kpi.new()
		k.setup("item:" + id, id, P.TEXT_2, 54)
		k.data = hud.data
		k.clicked.connect(_on_kpi)
		_mat_box.add_child(k)
		_mats[id] = k
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	# Narrow screens (or a large interface scale) drop the materials group.
	var w: float = get_viewport_rect().size.x
	if _mat_box != null:
		_mat_box.visible = w >= 1640.0   # 1540 before the credits field (version 3.1)

## Critic round 21 (bottom and top rows never overlap): when the bar would reach the time panel
## (large interface scale, small window), the least urgent numbers hide first; they come back when
## there is room. Their values stay on the dashboard.
const DROP_ORDER := ["credits", "research", "morale", "energy", "unrest"]
var _dropped := 0
func _process(_d: float) -> void:
	if hud == null or hud.time_panel == null:
		return
	var limit: float = hud.time_panel.get_global_rect().position.x - 8.0
	var end_x: float = get_global_rect().end.x
	if end_x > limit and _dropped < DROP_ORDER.size():
		(_k[DROP_ORDER[_dropped]] as Control).visible = false
		_dropped += 1
		reset_size()
	elif _dropped > 0 and end_x + 130.0 < limit:
		_dropped -= 1
		(_k[DROP_ORDER[_dropped]] as Control).visible = true

func _on_kpi(key: String) -> void:
	var page := "overview"
	match key:
		"o2", "water", "power", "energy": page = "life"
		"food": page = "food"
		"pop", "morale": page = "population"
		"unrest":
			hud.open_screen("crew")
			return
		"research": page = "research"
		"credits":
			# Credits: the trade screen when a ship to trade with is landed.
			for r in hud.data.traffic_ships():
				var o: Dictionary = r.get("offer", {})
				if String(r.get("phase", "")) == "landed" and (o.has("sells") or o.has("buys")):
					hud.open_screen("trade", int(r["id"]))
					return
			hud.toast("No ship to trade with is on a pad. Traders and science ships buy and sell.", "info", "credits")
			return
	if key.begins_with("item:"):
		hud.open_screen("inventory")
		return
	hud.open_screen("dashboard", page)

func rebuild() -> void:
	refresh()

func _refresh_bases() -> void:
	var s = hud.main.sim
	var list: Array = s.bases.list() if "bases" in s and s.bases != null else []
	var sig: String = str(hud.base_filter)
	for b in list:
		sig += "|%d:%s" % [int(b["id"]), String(b["name"])]
	if sig == _base_sig:
		return
	_base_sig = sig
	_base_opt.visible = list.size() > 1
	_base_opt.clear()
	_base_ids = [-1]
	_base_opt.add_item("All bases")
	for b in list:
		_base_opt.add_item(String(b["name"]))
		_base_ids.append(int(b["id"]))
	var idx: int = _base_ids.find(hud.base_filter)
	_base_opt.select(maxi(0, idx))
	_rename_btn.visible = _base_opt.visible and hud.base_filter >= 0

## Rename the picked base (SIM command rename_base; refusals come back as a toast).
func _open_rename() -> void:
	if hud.base_filter < 0:
		return
	_pop_edit.text = hud.base_filter_name()
	var r: Rect2 = _rename_btn.get_global_rect()
	_pop.popup(Rect2i(Vector2i(int(r.position.x), int(r.end.y) + 6), Vector2i(0, 0)))
	_pop_edit.grab_focus()
	_pop_edit.select_all()

func rename_to(name: String) -> void:
	hud.main.submit("rename_base", {"id": hud.base_filter, "name": name.strip_edges()})
	_base_sig = ""

func _do_rename() -> void:
	rename_to(_pop_edit.text)
	_pop.hide()

func refresh() -> void:
	_refresh_bases()
	var k: Dictionary = hud.kpi
	if k.is_empty():
		return
	var d = hud.data
	var day_len: float = float(k["day_len"])
	# People
	var pop: Dictionary = k["pop"]
	var kp = _k["pop"]
	kp.set_value("%d" % pop["value"], Kit.plural(int(pop["beds"]), "bed"), 1 if int(pop["beds"]) < int(pop["value"]) else 0, d.trend("pop"))
	kp.tip_title = "Colonists"
	kp.tip_lines = [["Living", "%d" % pop["value"]], ["Beds in the base", "%d" % pop["beds"], P.AMBER if int(pop["beds"]) < int(pop["value"]) else P.TEXT]]
	kp.tip_note = "Every colonist needs a bed in a room with air."
	kp.series_key = "pop"
	# Oxygen
	var o2: Dictionary = k["o2"]
	var ko = _k["o2"]
	var ratio: float = float(o2["ratio"])
	var o2_state := 0
	if float(o2["cap"]) > 0.0 and float(o2["make"]) < float(o2["use"]):
		o2_state = 1
	if float(o2["cap"]) > 0.0 and float(o2["value"]) < 0.3 and float(o2["use"]) > 0.0:
		o2_state = 2
	var o2_sub: String = ("make %s" % Kit.pct(minf(ratio, 9.99))) if float(o2["use"]) > 0.0 else ("no base air" if float(o2["cap"]) <= 0.0 else "nobody breathes")
	ko.set_value(Kit.fmt(float(o2["value"])), o2_sub, o2_state, d.trend("o2_stock"))
	ko.tip_title = "Oxygen"
	ko.tip_lines = [["In base rooms", "%s of %s" % [Kit.fmt(float(o2["value"])), Kit.fmt(float(o2["cap"]))]],
		["Made per day", Kit.fmt(float(o2["make"])), P.GREEN], ["Breathed per day", Kit.fmt(float(o2["use"])), P.AMBER],
		["Make / breathe", Kit.pct(minf(ratio, 9.99)), P.GREEN if ratio >= 1.2 else (P.AMBER if ratio >= 1.0 else P.RED)]]
	if float(o2["lander_left"]) > 0.0:
		ko.tip_lines.append(["Lander air left", Kit.clock(float(o2["lander_left"])), P.AMBER])
	ko.tip_note = "The lander air is separate. Overlay: air shows each group of rooms."
	ko.series_key = "o2_stock"
	# Water
	var w: Dictionary = k["water"]
	var kw = _k["water"]
	var wd: float = float(w["days"])
	kw.set_value(Kit.fmt(float(w["value"])), Kit.days(wd), 2 if wd < 0.3 else (1 if wd < 0.75 else 0), d.trend("water_stock"))
	kw.tip_title = "Water"
	kw.tip_lines = [["Total", Kit.fmt(float(w["value"]))], ["In reservoirs", "%s of %s" % [Kit.fmt(float(w["net_stock"])), Kit.fmt(float(w["net_cap"]))]],
		["Water cans in store", "%d" % int(w["cans"])], ["Pumped per day", Kit.fmt(float(w["in"])), P.GREEN], ["Used per day", Kit.fmt(float(w["out"])), P.AMBER],
		["Drinking water for", Kit.days(wd)]]
	kw.series_key = "water_stock"
	# Power
	var pw: Dictionary = k["power"]
	var kpw = _k["power"]
	var net: float = float(pw["net"])
	kpw.set_value(Kit.signed(net) + " P", "%s / %s P" % [Kit.fmt(float(pw["gen"])), Kit.fmt(float(pw["use"]))], 2 if int(pw["shed"]) > 0 else (1 if net < 0.0 else 0), d.trend("power_gen"))
	kpw.tip_title = "Power"
	kpw.tip_lines = [["Made now", Kit.fmt(float(pw["gen"])) + " P", P.GREEN], ["Needed now", Kit.fmt(float(pw["use"])) + " P", P.AMBER],
		["Balance", Kit.signed(net) + " P", P.GREEN if net >= 0.0 else P.RED], ["Structures switched off", "%d" % int(pw["shed"]), P.RED if int(pw["shed"]) > 0 else P.TEXT]]
	kpw.tip_note = "A colony-wide surplus does not help a district that is not joined. Overlay: power."
	kpw.series_key = "power_gen"
	# Energy
	var e: Dictionary = k["energy"]
	var ke = _k["energy"]
	var e_low: bool = float(e["cap"]) > 0.0 and float(e["value"]) < float(e["night_need"])
	ke.set_value("%s E" % Kit.fmt(float(e["value"])), "of %s E" % Kit.fmt(float(e["cap"])), 1 if e_low else 0, d.trend("energy"))
	ke.tip_title = "Stored energy"
	ke.tip_lines = [["In batteries", "%s of %s E" % [Kit.fmt(float(e["value"])), Kit.fmt(float(e["cap"]))]],
		["Life support needs for one night", Kit.fmt(float(e["night_need"])) + " E", P.AMBER if e_low else P.TEXT]]
	ke.series_key = "energy"
	# Food
	var fd: Dictionary = k["food"]
	var kf = _k["food"]
	var days_f: float = float(fd["days"])
	var nu: Dictionary = k["nutrition"]
	var sub_f: String = Kit.days(days_f)
	if not nu.is_empty():
		sub_f += "  diet %d" % int(float(nu.get("score", 0.0)))
	kf.set_value("%d" % int(fd["value"]), sub_f, 2 if days_f < 0.4 else (1 if days_f < 1.0 else 0), d.trend("food_days"))
	kf.tip_title = "Food"
	kf.tip_lines = [["Dishes in store", "%d" % int(fd["value"])], ["Emergency rations", "%d" % int(fd["meals"])], ["Food for", Kit.days(days_f)]]
	if not nu.is_empty():
		for n in ["protein", "carbs", "fat", "vitamins"]:
			var v: float = float(nu.get(n, 0.0))
			kf.tip_lines.append([P.NUTRIENT_NAME[n], "%d" % int(v), P.RED if v < 25.0 else (P.AMBER if v < 40.0 else P.NUTRIENT[n])])
		kf.tip_lines.append(["Nutrition score", "%d" % int(float(nu.get("score", 0.0)))])
	kf.tip_note = "One dish feeds one colonist for one day."
	kf.series_key = "food_days"
	# Morale
	var m: float = float(k["morale"]["value"])
	var km = _k["morale"]
	km.set_value("%d" % int(m), _morale_word(m), 2 if m < 25.0 else (1 if m < 45.0 else 0), d.trend("morale"))
	km.tip_title = "Morale"
	km.tip_lines = [["Average", "%d of 100" % int(m)], ["Mood", _morale_word(m)]]
	km.tip_note = "Low morale slows work. Food variety, taste, recreation and comfort raise it."
	km.series_key = "morale"
	# Unrest (version 5, V5 §6.4): per base with the top bar's base filter; the causes in the tooltip.
	var ku = _k["unrest"]
	var u: Dictionary = hud.v5.unrest(hud.base_filter) if hud.v5 != null else {}
	ku.visible = not u.is_empty()
	if ku.visible:
		var uv: float = float(u["value"])
		var stage: String = String(u.get("stage", "calm"))
		ku.set_value("%d" % int(uv), stage, 2 if uv >= 55.0 else (1 if uv >= 25.0 else 0), 99, false)
		ku.tip_title = "Unrest"
		ku.tip_lines = [["Unrest", "%d of 100" % int(uv)], ["Stage", stage.capitalize()]]
		for c in u.get("causes", []):
			ku.tip_lines.append(["  " + String(c["text"]), "+%d" % int(float(c["delta"]))])
		ku.tip_note = "Grumbling from 25, slowdown from 40, protest from 55, strike from 70, riot from 85. Better food, rest, housing and fair treatment lower it. Click: the crew."
	# Research
	var r: Dictionary = k["research"]
	var kr = _k["research"]
	if not bool(r["available"]):
		kr.set_value("-", "not available", 0, 99)
		kr.tip_title = "Research"
		kr.tip_lines = []
		kr.tip_note = "Research is not available yet."
	else:
		var active: String = String(r["active"])
		var sub_r: String = "no project" if active == "" else Kit.pct(float(r["progress"]) / maxf(1.0, float(r["cost"])))
		kr.set_value("%s/d" % Kit.fmt(float(r["rate"])), sub_r, 1 if active == "" else 0, d.trend("rp_rate"))
		kr.tip_title = "Research"
		kr.tip_lines = [["Research points per day", Kit.fmt(float(r["rate"]))]]
		if active != "":
			kr.tip_lines.append(["Project", d.tech_name(active)])
			kr.tip_lines.append(["Progress", "%s of %s RP" % [Kit.fmt(float(r["progress"])), Kit.fmt(float(r["cost"]))]])
			var eta: float = d.tech_eta_seconds(active)
			kr.tip_lines.append(["Time left", Kit.clock(eta) if eta >= 0.0 else "no research now"])
		kr.tip_note = "A research lab with a scientist makes research points." if active != "" else "No active project. Open Research (T) and pick one."
		kr.series_key = "rp_rate"
	# Credits (version 3.1): earned from trade, fees and meals; spent at traders.
	var kc = _k["credits"]
	kc.visible = d.traffic_available()
	if kc.visible:
		var cs: Dictionary = d.credits_state()
		kc.set_value("%d" % d.credits(), "credits", 0, 99)
		kc.tip_title = "Credits"
		kc.tip_lines = [["Balance", "%d" % d.credits(), P.GOLD], ["Earned", "%d" % int(cs.get("earned", 0)), P.GREEN], ["Spent", "%d" % int(cs.get("spent", 0)), P.AMBER]]
		var by: Dictionary = cs.get("by", {})
		for key in by:
			kc.tip_lines.append(["  " + String(key).capitalize(), "%d" % int(by[key])])
		kc.tip_note = "Visitors pay fees and meals. Traders buy and sell. Click: trade with a landed ship."
	# Materials
	var totals: Dictionary = k["totals"]
	for id in MATERIALS:
		var row: Dictionary = totals.get(id, {"total": 0, "reserved": 0, "carried": 0})
		var km2 = _mats[id]
		var total: int = int(row.get("total", 0))
		var reserved: int = int(row.get("reserved", 0))
		km2.set_value("%d" % total, ("%d res." % reserved) if reserved > 0 else d.item_name(id).to_lower(), 1 if total - reserved <= 2 and id != "electronics" else 0, 99)
		km2.tip_title = d.item_name(id)
		km2.tip_lines = [["Total", "%d" % total], ["Reserved for plans and tasks", "%d" % reserved], ["Being carried", "%d" % int(row.get("carried", 0))],
			["Free to use", "%d" % (total - reserved - int(row.get("carried", 0)))]]
		km2.tip_note = String(d.item(id).get("desc", ""))
		km2.series_key = "item:" + id
		km2.series_color = d.item_color(id)

static func _morale_word(m: float) -> String:
	if m >= 80.0:
		return "happy"
	if m >= 60.0:
		return "content"
	if m >= 45.0:
		return "uneasy"
	if m >= 25.0:
		return "unhappy"
	return "angry"
