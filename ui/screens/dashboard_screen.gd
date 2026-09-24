extends "res://ui/screens/screen.gd"
## Colony dashboard: charts from state.metrics.series (sampled every 10 s) and
## metrics.daily (one row per day). Pages: Overview, Life support, Food and nutrition,
## Industry, Population, Research, Hazards (hazard events, hull breaches, maintenance). Charts update every two seconds; hover any chart for
## exact values.

const LineChart = preload("res://ui/charts/line_chart.gd")
const BarChart = preload("res://ui/charts/bar_chart.gd")
const Donut = preload("res://ui/charts/donut_chart.gd")
const Gauge = preload("res://ui/charts/gauge.gd")
const Spark = preload("res://ui/charts/sparkline.gd")

var _updaters: Array = []      # Callables, run every 2 s
var _clock := 0
var _tpd := 6000.0

func _init() -> void:
	icon = "dashboard"
	title = "Colony dashboard"
	tabs = [["overview", "Overview", "grid"], ["life", "Life", "cat_life_support"], ["food", "Food", "cat_food"],
		["industry", "Industry", "cat_industry"], ["population", "People", "people"], ["research", "Research", "research"],
		["hazards", "Hazards", "hazard"]]

func _ready() -> void:
	_tpd = float(hud.main.sim.bal["day_length"]) * float(hud.main.sim.bal["tick_hz"])
	if typeof(arg) == TYPE_STRING and String(arg) != "":
		for t in tabs:
			if t[0] == String(arg):
				tab = String(arg)
	super._ready()

func refresh() -> void:
	_clock += 1
	if _clock % 10 != 0:
		return
	for u in _updaters:
		(u as Callable).call()

func build_tab(id: String, box: VBoxContainer) -> void:
	_updaters = []
	var s = hud.main.sim
	set_subtitle("Day %d  ·  %s  ·  a sample every 10 s" % [s.util.day_number(), Kit.plural(s.alive_count(), "colonist")])
	var body: VBoxContainer = Kit.vbox(12)
	box.add_child(Kit.scroll(body))
	match id:
		"life": _life(body)
		"food": _food(body)
		"industry": _industry(body)
		"population": _population(body)
		"research": _research(body)
		"hazards": _hazards(body)
		_: _overview(body)
	for u in _updaters:
		(u as Callable).call()

# ---------------------------------------------------------------- building blocks
func _row(parent: Control, sep: int = 12) -> HBoxContainer:
	var r: HBoxContainer = Kit.hbox(sep)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(r)
	return r

func _chart_card(parent: Control, chart: Control, h: float, stretch: float = 1.0) -> Control:
	var p: PanelContainer = Kit.panel("CardPanel", false)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = stretch
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	chart.custom_minimum_size = Vector2(200, h)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(chart)
	parent.add_child(p)
	return chart

func _line(parent: Control, title_text: String, specs: Array, h: float = 220.0, mode: String = "line", stretch: float = 1.0, unit_text: String = "") -> Control:
	var ch = LineChart.new()
	ch.title = title_text
	ch.mode = mode
	ch.unit = unit_text
	ch.ticks_per_day = _tpd
	_chart_card(parent, ch, h, stretch)
	var d = hud.data
	_updaters.append(func():
		var ser: Array = []
		for sp in specs:
			ser.append({"name": sp[0], "color": sp[2], "points": d.series(String(sp[1]))})
		ch.series = ser)
	return ch

## A headline tile: icon, name, big number, sub line, sparkline.
func _tile(parent: Control, icon_name: String, name: String, col: Color, series_name: String, getter: Callable) -> void:
	var p: PanelContainer = Kit.panel("CardPanel", false)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(150, 118)
	var v: VBoxContainer = Kit.vbox(2)
	p.add_child(v)
	var h: HBoxContainer = Kit.hbox(6)
	h.add_child(Kit.icon(icon_name, 16, col))
	h.add_child(Kit.head(name, P.TEXT_2, 11))
	v.add_child(h)
	var big: Label = Kit.num("-", 24, P.TEXT, true)
	v.add_child(big)
	var sub: Label = Kit.label("", "SmallLabel", 11, P.TEXT_2)
	v.add_child(sub)
	var sp = Spark.new()
	sp.color = col
	sp.custom_minimum_size = Vector2(120, 30)
	v.add_child(sp)
	parent.add_child(p)
	var d = hud.data
	_updaters.append(func():
		var r: Array = getter.call()
		big.text = String(r[0])
		sub.text = String(r[1])
		big.add_theme_color_override("font_color", r[2] if r.size() > 2 else P.TEXT)
		sp.points = d.series(series_name))

func _note(parent: Control, text: String) -> void:
	parent.add_child(Kit.wrap(text, 13, P.TEXT_3))

# ---------------------------------------------------------------- pages
func _overview(body: VBoxContainer) -> void:
	var d = hud.data
	var r1: HBoxContainer = _row(body, 10)
	_tile(r1, "people", "Colonists", P.CATEGORY["housing"], "pop", func():
		var kk: Dictionary = hud.kpi
		return ["%d" % int(kk["pop"]["value"]), Kit.plural(int(kk["pop"]["beds"]), "bed"), P.AMBER if int(kk["pop"]["beds"]) < int(kk["pop"]["value"]) else P.TEXT])
	_tile(r1, "o2", "Oxygen made", P.CATEGORY["life_support"], "o2_make", func():
		var o: Dictionary = hud.kpi["o2"]
		var ratio: float = float(o["ratio"])
		return [Kit.pct(minf(ratio, 9.99)), "of what people breathe", P.GREEN if ratio >= 1.2 else (P.AMBER if ratio >= 1.0 else P.RED)])
	_tile(r1, "water", "Water", Color("3AA0D8"), "water_stock", func():
		var w: Dictionary = hud.kpi["water"]
		return [Kit.days(float(w["days"])), "%s units" % Kit.fmt(float(w["value"])), P.AMBER if float(w["days"]) < 1.0 else P.TEXT])
	_tile(r1, "power", "Power", P.GOLD, "power_gen", func():
		var pw: Dictionary = hud.kpi["power"]
		return [Kit.signed(float(pw["net"])) + " P", "%s made, %s used" % [Kit.fmt(float(pw["gen"])), Kit.fmt(float(pw["use"]))], P.GREEN if float(pw["net"]) >= 0.0 else P.RED])
	_tile(r1, "food", "Food", P.CATEGORY["food"], "food_days", func():
		var f: Dictionary = hud.kpi["food"]
		return [Kit.days(float(f["days"])), Kit.plural(int(f["value"]), "dish", "dishes"), P.AMBER if float(f["days"]) < 1.0 else P.TEXT])
	_tile(r1, "nutrition", "Nutrition", P.NUTRIENT["vitamins"], "nutrition", func():
		var nu: Dictionary = hud.kpi["nutrition"]
		if nu.is_empty():
			return ["-", "not available", P.TEXT_3]
		var sc: float = float(nu.get("score", 0.0))
		return ["%d" % int(sc), "score of 100", P.GREEN if sc >= 70.0 else (P.AMBER if sc >= 40.0 else P.RED)])
	_tile(r1, "morale", "Morale", P.CATEGORY["comfort"], "morale", func():
		var m: float = float(hud.kpi["morale"]["value"])
		return ["%d" % int(m), "average of 100", P.GREEN if m >= 60.0 else (P.AMBER if m >= 40.0 else P.RED)])
	_tile(r1, "research", "Research", P.VIOLET, "rp_rate", func():
		return ["%s" % Kit.fmt(d.rp_rate()), "RP per day", P.VIOLET])
	var r2: HBoxContainer = _row(body)
	_line(r2, "Colonists, morale and nutrition", [["Colonists", "pop", P.CATEGORY["housing"]], ["Morale", "morale", P.CATEGORY["comfort"]], ["Nutrition", "nutrition", P.NUTRIENT["vitamins"]]], 230.0, "line", 2.0)
	var donut = Donut.new()
	donut.title = "Roles"
	_chart_card(r2, donut, 230.0, 1.0)
	_updaters.append(func(): _fill_roles(donut))
	var r3: HBoxContainer = _row(body)
	_line(r3, "Reserves", [["Oxygen", "o2_stock", P.CATEGORY["life_support"]], ["Energy E", "energy", P.CATEGORY["utilities"]], ["Food days", "food_days", P.CATEGORY["food"]]], 210.0, "line", 2.0)
	var al: VBoxContainer = card("Alerts now", "sev_warning", P.AMBER)
	var alp: PanelContainer = card_panel(al)
	alp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alp.custom_minimum_size.y = 210
	r3.add_child(alp)
	var inc: Array = hud.main.sim.alerts.incidents()
	if inc.is_empty():
		al.add_child(Kit.label("All systems normal.", "", 13, P.GREEN))
	for i in inc.slice(0, 7):
		var row: HBoxContainer = Kit.hbox(6)
		row.add_child(Kit.icon(P.sev_icon(int(i["issue"]["severity"])), 14, P.sev(int(i["issue"]["severity"]))))
		var l: Label = Kit.label(String(i["issue"]["text"]), "", 12, P.TEXT)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = String(i["issue"]["text"]) + "\n" + String(i["issue"]["action"])
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(l)
		al.add_child(row)
	if inc.size() > 7:
		al.add_child(Kit.label("+ %s more" % Kit.plural(inc.size() - 7, "alert"), "SmallLabel", 11, P.TEXT_3))

func _fill_roles(donut) -> void:
	var s = hud.main.sim
	var roles := {}
	for aid in s.state["agents"]:
		var a: Dictionary = s.state["agents"][aid]
		if a["state"] == "alive":
			roles[a["role"]] = int(roles.get(a["role"], 0)) + 1
	var segs: Array = []
	for r in s.bal.get("roles", roles.keys()):
		if roles.has(r):
			segs.append({"name": String(s.bal["role_names"].get(r, r)), "value": float(roles[r]), "color": P.ROLE.get(r, P.CYAN)})
	donut.segments = segs
	donut.center_value = "%d" % s.alive_count()
	donut.center_label = "colonists"

func _life(body: VBoxContainer) -> void:
	var d = hud.data
	var r1: HBoxContainer = _row(body)
	var g1 = Gauge.new()
	g1.title = "Oxygen made / breathed"
	g1.vmax = 2.0
	g1.zones = [{"to": 1.0, "color": P.RED}, {"to": 1.2, "color": P.AMBER}, {"to": 2.0, "color": P.GREEN}]
	g1.target = 1.2
	g1.label = "goal 120%"
	_chart_card(r1, g1, 150.0)
	_updaters.append(func():
		var r: float = float(hud.kpi["o2"]["ratio"])
		g1.value = minf(r, 2.0)
		g1.value_text = Kit.pct(minf(r, 9.99)))
	var g2 = Gauge.new()
	g2.title = "Drinking water"
	g2.vmax = 4.0
	g2.zones = [{"to": 0.75, "color": P.RED}, {"to": 1.5, "color": P.AMBER}, {"to": 4.0, "color": P.GREEN}]
	g2.target = 1.5
	g2.label = "days, goal 1.5"
	_chart_card(r1, g2, 150.0)
	_updaters.append(func():
		var wd: float = float(hud.kpi["water"]["days"])
		g2.value = minf(wd, 4.0)
		g2.value_text = Kit.days(wd))
	var g3 = Gauge.new()
	g3.title = "Battery charge"
	g3.vmax = 100.0
	g3.zones = [{"to": 25.0, "color": P.RED}, {"to": 50.0, "color": P.AMBER}, {"to": 100.0, "color": P.GREEN}]
	g3.label = "percent"
	_chart_card(r1, g3, 150.0)
	_updaters.append(func():
		var e: Dictionary = hud.kpi["energy"]
		var pc: float = 100.0 * float(e["value"]) / maxf(0.001, float(e["cap"]))
		g3.value = pc
		g3.value_text = "%d%%" % int(pc)
		var need: float = 100.0 * float(e["night_need"]) / maxf(0.001, float(e["cap"]))
		g3.target = need
		g3.label = "night needs %d%%" % int(need))
	var r2: HBoxContainer = _row(body)
	_line(r2, "Oxygen per day: made and breathed", [["Made", "o2_make", P.GREEN], ["Breathed", "o2_use", P.AMBER]], 200.0, "area", 1.0, "/day")
	_line(r2, "Oxygen in base rooms", [["Oxygen", "o2_stock", P.CATEGORY["life_support"]]], 200.0, "area")
	var r3: HBoxContainer = _row(body)
	_line(r3, "Water per day: in and out", [["In", "water_in", Color("3AA0D8")], ["Out", "water_out", P.AMBER]], 200.0, "area", 1.0, "/day")
	_line(r3, "Water stock", [["Water", "water_stock", Color("3AA0D8")]], 200.0, "area")
	var r4: HBoxContainer = _row(body)
	_line(r4, "Power: made and used", [["Made", "power_gen", P.GOLD], ["Used", "power_use", P.AMBER]], 200.0, "area", 1.0, "P")
	_line(r4, "Stored energy", [["Energy", "energy", P.CATEGORY["utilities"]]], 200.0, "area", 1.0, "E")

func _food(body: VBoxContainer) -> void:
	var d = hud.data
	var r1: HBoxContainer = _row(body)
	# Colony nutrition against the target
	var nb = BarChart.new()
	nb.title = "Colony nutrition (line = target)"
	nb.horizontal = true
	nb.label_w = 110.0
	_chart_card(r1, nb, 220.0)
	var target: float = float(hud.main.sim.bal.get("nutrition", {}).get("target", 70.0))
	_updaters.append(func():
		var nu: Dictionary = d.colony_nutrition()
		var cats: Array = []
		var vals: Array = []
		var icons: Array = []
		for n in ["protein", "carbs", "fat", "vitamins"]:
			cats.append(P.NUTRIENT_NAME[n])
			vals.append(float(nu.get(n, 0.0)))
			icons.append(load("res://ui/theme/icons.gd").tex(n, 16))
		nb.categories = cats
		nb.icons = icons
		nb.target = [target, target, target, target]
		nb.series = [{"name": "Colony average", "color": P.NUTRIENT["vitamins"], "values": vals}])
	var dn = Donut.new()
	dn.title = "Dishes cooked, all time"
	_chart_card(r1, dn, 220.0)
	_updaters.append(func():
		var cooked: Dictionary = d.stats().get("cooked", {})
		var segs: Array = []
		var total := 0
		for dish in cooked:
			total += int(cooked[dish])
			segs.append({"name": d.item_name(String(dish)), "value": float(cooked[dish]), "color": d.item_color(String(dish))})
		segs.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
		dn.segments = segs.slice(0, 8)
		dn.center_value = "%d" % segs.size()
		dn.center_label = "different dishes")
	_line(r1, "Food and nutrition", [["Food days", "food_days", P.CATEGORY["food"]], ["Nutrition score", "nutrition", P.NUTRIENT["vitamins"]]], 220.0, "line", 1.3)
	var r2: HBoxContainer = _row(body)
	var ds = BarChart.new()
	ds.title = "Dishes in stock"
	ds.horizontal = true
	ds.label_w = 150.0
	_chart_card(r2, ds, 290.0)
	_updaters.append(func(): _stock_bars(ds, "dish"))
	var cs = BarChart.new()
	cs.title = "Crops in stock"
	cs.horizontal = true
	cs.label_w = 110.0
	_chart_card(r2, cs, 290.0)
	_updaters.append(func(): _stock_bars(cs, "crop"))
	var sp = BarChart.new()
	sp.title = "Spoiled yesterday"
	sp.horizontal = true
	sp.label_w = 130.0
	_chart_card(r2, sp, 290.0)
	_updaters.append(func():
		var daily: Array = d.daily()
		var spoiled: Dictionary = daily[daily.size() - 1].get("spoiled", {}) if not daily.is_empty() else {}
		var cats: Array = []
		var vals: Array = []
		var icons: Array = []
		for id in spoiled:
			cats.append(d.item_name(String(id)))
			vals.append(float(spoiled[id]))
			icons.append(load("res://ui/theme/icons.gd").tex(load("res://ui/theme/icons.gd").item(String(id)), 16))
		sp.categories = cats
		sp.icons = icons
		sp.series = [{"name": "Spoiled", "color": P.AMBER, "values": vals}])
	_note(body, "Food with a shelf life spoils in ordinary storage. Cold storage keeps it. One dish feeds one colonist for one day.")

func _stock_bars(chart, category: String) -> void:
	var d = hud.data
	var totals: Dictionary = d.totals()
	var rows: Array = []
	for id in d.items():
		if d.item_cat(String(id)) == category:
			rows.append([String(id), int(totals.get(id, {}).get("total", 0))])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	var cats: Array = []
	var vals: Array = []
	var icons: Array = []
	var Ic = load("res://ui/theme/icons.gd")
	for r in rows.slice(0, 9):
		cats.append(d.item_name(String(r[0])))
		vals.append(float(r[1]))
		icons.append(Ic.tex(Ic.item(String(r[0])), 16))
	chart.categories = cats
	chart.icons = icons
	chart.series = [{"name": "Stock", "color": P.CATEGORY["food"], "values": vals}]

func _industry(body: VBoxContainer) -> void:
	var d = hud.data
	var r1: HBoxContainer = _row(body)
	var pc = BarChart.new()
	pc.title = "Made and used yesterday"
	_chart_card(r1, pc, 260.0, 2.0)
	_updaters.append(func():
		var daily: Array = d.daily()
		var row: Dictionary = daily[daily.size() - 1] if not daily.is_empty() else {}
		var made: Dictionary = row.get("produced", {})
		var used: Dictionary = row.get("consumed", {})
		var ids: Array = []
		for id in made:
			if d.item_cat(String(id)) in ["raw", "material", "component", "medical"]:
				ids.append(String(id))
		for id in used:
			if not ids.has(String(id)) and d.item_cat(String(id)) in ["raw", "material", "component", "medical"]:
				ids.append(String(id))
		var cats: Array = []
		var a: Array = []
		var b: Array = []
		var icons: Array = []
		var Ic = load("res://ui/theme/icons.gd")
		for id in ids.slice(0, 12):
			cats.append(d.item_name(id))
			a.append(float(made.get(id, 0)))
			b.append(float(used.get(id, 0)))
			icons.append(Ic.tex(Ic.item(id), 16))
		pc.categories = cats
		pc.icons = icons
		pc.series = [{"name": "Made", "color": P.GREEN, "values": a}, {"name": "Used", "color": P.AMBER, "values": b}])
	var mc: VBoxContainer = card("Machines", "cat_industry", P.CATEGORY["industry"])
	var mp: PanelContainer = card_panel(mc)
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(mp)
	var mg: GridContainer = Kit.grid(3, 12, 4)
	mc.add_child(mg)
	_updaters.append(func(): _fill_machines(mg))
	var r2: HBoxContainer = _row(body)
	_line(r2, "Building materials", [["Steel", "item:metal", d.item_color("metal")], ["Polymer", "item:polymer", d.item_color("polymer")], ["Spare parts", "item:spare_parts", d.item_color("spare_parts")]], 220.0)
	_line(r2, "Advanced materials", [["Glass", "item:glass", d.item_color("glass")], ["Electronics", "item:electronics", d.item_color("electronics")], ["Composite", "item:composite", d.item_color("composite")], ["Rocket fuel", "item:rocket_fuel", d.item_color("rocket_fuel")]], 220.0)

func _fill_machines(g: GridContainer) -> void:
	Kit.clear(g)
	var s = hud.main.sim
	var by := {}
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		if b["state"] != "active":
			continue
		var rec: Dictionary = s.prod.recipe_of(b)
		if rec.is_empty() or bool(rec.get("menu", false)):
			continue
		var name: String = String(s.bdef(b["def"]).get("name", b["def"]))
		if not by.has(name):
			by[name] = [0, 0]
		var blk: String = s.prod.machine_block(b)
		if blk == "":
			by[name][0] += 1
		else:
			by[name][1] += 1
	g.add_child(Kit.head("Machine", P.TEXT_3, 10))
	g.add_child(Kit.head("Working", P.TEXT_3, 10))
	g.add_child(Kit.head("Waiting", P.TEXT_3, 10))
	if by.is_empty():
		g.add_child(Kit.label("No machines yet.", "SmallLabel", 12, P.TEXT_3))
	for name in by:
		g.add_child(Kit.label(name, "", 13, P.TEXT))
		g.add_child(Kit.num("%d" % by[name][0], 13, P.GREEN))
		g.add_child(Kit.num("%d" % by[name][1], 13, P.AMBER if int(by[name][1]) > 0 else P.TEXT_3))

func _population(body: VBoxContainer) -> void:
	var s = hud.main.sim
	var r1: HBoxContainer = _row(body)
	var donut = Donut.new()
	donut.title = "Roles"
	_chart_card(r1, donut, 230.0)
	_updaters.append(func(): _fill_roles(donut))
	_line(r1, "Colonists", [["Colonists", "pop", P.CATEGORY["housing"]]], 230.0, "area", 2.0)
	var r2: HBoxContainer = _row(body)
	var hb = BarChart.new()
	hb.title = "Health and morale of every colonist"
	_chart_card(r2, hb, 230.0)
	_updaters.append(func():
		var bands := ["0-24", "25-49", "50-74", "75-100"]
		var h := [0.0, 0.0, 0.0, 0.0]
		var m := [0.0, 0.0, 0.0, 0.0]
		for aid in s.state["agents"]:
			var a: Dictionary = s.state["agents"][aid]
			if a["state"] != "alive":
				continue
			h[clampi(int(float(a["health"]) / 25.0), 0, 3)] += 1.0
			m[clampi(int(float(a["morale"]) / 25.0), 0, 3)] += 1.0
		hb.categories = bands
		hb.series = [{"name": "Health", "color": P.RED.lerp(P.GREEN, 0.7), "values": h}, {"name": "Morale", "color": P.CATEGORY["comfort"], "values": m}])
	var ab = BarChart.new()
	ab.title = "Doing now"
	ab.horizontal = true
	ab.label_w = 130.0
	_chart_card(r2, ab, 230.0)
	_updaters.append(func():
		var doing := {}
		for aid in s.state["agents"]:
			var a: Dictionary = s.state["agents"][aid]
			if a["state"] == "alive":
				var g: String = String(a.get("goal", "")).split(" ")[0].capitalize()
				doing[g] = int(doing.get(g, 0)) + 1
		var keys: Array = doing.keys()
		keys.sort_custom(func(x, y): return int(doing[x]) > int(doing[y]))
		var vals: Array = []
		for k2 in keys.slice(0, 8):
			vals.append(float(doing[k2]))
		ab.categories = keys.slice(0, 8)
		ab.series = [{"name": "Colonists", "color": P.CYAN, "values": vals}])
	_line(r2, "Morale and nutrition", [["Morale", "morale", P.CATEGORY["comfort"]], ["Nutrition", "nutrition", P.NUTRIENT["vitamins"]]], 230.0)

func _research(body: VBoxContainer) -> void:
	var d = hud.data
	var r1: HBoxContainer = _row(body)
	_line(r1, "Research points per day", [["RP per day", "rp_rate", P.VIOLET]], 230.0, "area", 2.0)
	var pc: VBoxContainer = card("Project", "research", P.VIOLET)
	var pp: PanelContainer = card_panel(pc)
	pp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(pp)
	var name_l: Label = Kit.label("", "TitleLabel", 17, P.TEXT)
	pc.add_child(name_l)
	var bar = Kit.bar(0.0, P.VIOLET, 10.0)
	pc.add_child(bar)
	var info: Label = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	pc.add_child(info)
	pc.add_child(Kit.button("Open research", func(): hud.open_screen("research"), "Key T.", "", "research", 16))
	_updaters.append(func():
		var a: String = String(d.research().get("active", ""))
		name_l.text = d.tech_name(a).to_upper() if a != "" else "NO ACTIVE PROJECT"
		bar.value = d.tech_progress(a) / maxf(1.0, d.tech_cost(a)) if a != "" else 0.0
		var eta: float = d.tech_eta_seconds(a) if a != "" else -1.0
		info.text = ("%s of %s RP. Done in about %s." % [Kit.fmt(d.tech_progress(a)), Kit.fmt(d.tech_cost(a)), Kit.clock(eta)]) if eta >= 0.0 else ("%d of %d projects done." % [d.research().get("done", {}).size(), d.techs().size()]))
	var bb = BarChart.new()
	bb.title = "Projects done by branch"
	bb.horizontal = true
	bb.label_w = 150.0
	_chart_card(body, bb, 230.0)
	_updaters.append(func():
		var br: Dictionary = d.branches()
		var cats: Array = []
		var done: Array = []
		var total: Array = []
		for b in br:
			var n := 0
			var k := 0
			for t in d.techs():
				if String(d.techs()[t].get("branch", "")) == String(b):
					n += 1
					if d.tech_done(String(t)):
						k += 1
			cats.append(String(br[b].get("name", b)))
			done.append(float(k))
			total.append(float(n))
		bb.categories = cats
		bb.target = total
		bb.series = [{"name": "Done", "color": P.VIOLET, "values": done}])

# ---------------------------------------------------------------- hazards and maintenance (version 3)
## V3_DESIGN §4 and §8: every detected event, the machines near failure with Maintain now,
## and hull breaches. Lists rebuild when their rows change; times update every 2 s.
func _hazards(body: VBoxContainer) -> void:
	var d = hud.data
	var s = hud.main.sim
	var top: HBoxContainer = _row(body)
	# Events
	var ev: VBoxContainer = card("Hazard events", "hazard", P.AMBER)
	var evp: PanelContainer = card_panel(ev)
	evp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	evp.size_flags_stretch_ratio = 1.3
	top.add_child(evp)
	var hz_opt: String = String(s.state.get("options", {}).get("hazards", "normal"))
	var info: Label = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	ev.add_child(info)
	var ev_list: VBoxContainer = Kit.vbox(4)
	ev.add_child(ev_list)
	var ev_sig := ["-"]   # "-": build on the first update, also when the list is empty
	var ev_rows: Array = []
	_updaters.append(func():
		var rows: Array = hud.hazard.rows()
		var done: Dictionary = s.state.get("hazards", {}).get("done_count", {}) if typeof(s.state.get("hazards", {})) == TYPE_DICTIONARY else {}
		var parts: Array = []
		for k in done:
			parts.append("%s %d" % [d.hazard_name(String(k)).to_lower(), int(done[k])])
		info.text = "Hazard setting: %s.  Events so far: %s." % [hz_opt, ", ".join(parts) if not parts.is_empty() else "none"]
		var sig := ""
		for r in rows:
			sig += "%s:%s:%s|" % [r["id"], r["active"], r["countered"]]
		if sig != ev_sig[0]:
			ev_sig[0] = sig
			Kit.clear(ev_list)
			ev_rows.clear()
			if rows.is_empty():
				ev_list.add_child(Kit.label("No event is detected now. A Comms Tower and Deep-space radar research detect meteors earlier.", "", 13, P.GREEN))
			for r in rows:
				ev_rows.append(_event_row(ev_list, r))
		for k in mini(rows.size(), ev_rows.size()):
			var r2: Dictionary = rows[k]
			(ev_rows[k] as Label).text = (("NOW  " + Kit.clock(r2["left_s"])) if float(r2["left_s"]) >= 0.0 else "NOW") if bool(r2["active"]) else Kit.clock(r2["eta_s"]))
	# Breaches
	var br: VBoxContainer = card("Hull breaches", "breach", P.RED)
	var brp: PanelContainer = card_panel(br)
	brp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brp)
	var br_list: VBoxContainer = Kit.vbox(4)
	br.add_child(br_list)
	var br_sig := [""]
	_updaters.append(func():
		var ids: Array = []
		for id in s.state["buildings"]:
			if not d.breach_of(s.state["buildings"][id]).is_empty():
				ids.append(id)
		if str(ids) == br_sig[0]:
			return
		br_sig[0] = str(ids)
		Kit.clear(br_list)
		if ids.is_empty():
			br_list.add_child(Kit.label("No breach. Air stays in.", "", 13, P.GREEN))
			return
		for id in ids:
			var b: Dictionary = s.state["buildings"][id]
			var row: HBoxContainer = Kit.hbox(8)
			row.add_child(Kit.icon("breach", 16, P.RED))
			row.add_child(_goto_button(String(b.get("name", "")), int(id)))
			row.add_child(Kit.label("Air leaks. A technician repairs it with 1 hull plate (or 2 steel).", "SmallLabel", 12, P.TEXT_2))
			br_list.add_child(row))
	# Maintenance
	var mt: VBoxContainer = card("Maintenance: machines near failure", "wrench", P.CYAN)
	body.add_child(card_panel(mt))
	mt.add_child(Kit.wrap("Every machine wears while it works. It breaks when its wear reaches its failure point. Maintenance by a technician (1 part of the fault's item) sets wear to 0. Maintain now puts the job first.", 13, P.TEXT_2))
	var grid: GridContainer = Kit.grid(7, 14, 6)
	mt.add_child(grid)
	var mt_sig := ["-"]
	var mt_binds: Array = []
	_updaters.append(func():
		var risk: Array = d.at_risk()
		var sig := ""
		for r in risk:
			sig += "%d|" % int(r.get("id", -1))
		if sig != mt_sig[0]:
			mt_sig[0] = sig
			Kit.clear(grid)
			mt_binds.clear()
			for h in ["Machine", "Wear", "", "Fails in", "Fault", "Uses (stock)", ""]:
				grid.add_child(Kit.head(h, P.TEXT_3, 11))
			if risk.is_empty():
				grid.add_child(Kit.label("No machine is near failure." if d.has_helper("hazards", "at_risk") or d.mock.has("at_risk") else "Wear data is not available in this version.", "", 13, P.GREEN))
			for r in risk:
				mt_binds.append(_risk_row(grid, r))
		for k in mini(risk.size(), mt_binds.size()):
			(mt_binds[k] as Callable).call(risk[k]))

## One event row; returns the time label (updated by the caller).
func _event_row(parent: VBoxContainer, r: Dictionary) -> Label:
	var d = hud.data
	var col: Color = hud.hazard._col(r)
	var row: HBoxContainer = Kit.hbox(10)
	parent.add_child(row)
	row.add_child(Kit.icon(d.hazard_icon(String(r["kind"])), 18, col))
	var nm: Label = Kit.head(String(r["name"]), P.TEXT, 12)
	nm.custom_minimum_size.x = 130
	row.add_child(nm)
	var t: Label = Kit.num("", 13, col, true)
	t.custom_minimum_size.x = 86
	row.add_child(t)
	var sev: Label = Kit.label("Severity %d" % int(r["severity"]), "SmallLabel", 12, P.sev(int(r["severity"])))
	sev.custom_minimum_size.x = 70
	row.add_child(sev)
	var cov: bool = bool(r["countered"])
	var bd: Control = Kit.badge("COVERED" if cov else "NOT COVERED", P.GREEN if cov else P.AMBER)
	bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bd)
	if r["pos"] != null:
		var p: Vector2 = r["pos"]
		var b: Button = Kit.button(d.place_text(p), func():
			host.close(self)
			hud.main.focus_on(p), "Show\nThe camera goes to the place.", "ListButton", "target", 13)
		b.custom_minimum_size.y = 26
		b.add_theme_font_size_override("font_size", 12)
		row.add_child(b)
	else:
		row.add_child(Kit.label("Whole map", "SmallLabel", 12, P.TEXT_2))
	if String(r["kind"]) == "solar_flare":
		row.add_child(hud.hazard.shelter_button(hud))
	var adv: Label = Kit.wrap(String(r["advice"]), 12, P.TEXT_2)
	adv.custom_minimum_size.x = 220
	row.add_child(adv)
	return t

func _goto_button(text: String, id: int) -> Button:
	var b: Button = Kit.button(text, func():
		host.close(self)
		var bb: Dictionary = hud.main.sim.state["buildings"].get(id, {})
		if not bb.is_empty():
			hud.main.focus_on(bb["pos"])
			hud.main.select("building", id), "Show\nThe camera goes to it and selects it.", "ListButton", "target", 13)
	b.custom_minimum_size.y = 26
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b

## One maintenance row in the 7-column grid; returns a Callable(row) that updates it.
func _risk_row(grid: GridContainer, r: Dictionary) -> Callable:
	var d = hud.data
	var s = hud.main.sim
	var id: int = int(r.get("id", -1))
	var b: Dictionary = s.state["buildings"].get(id, {})
	grid.add_child(_goto_button(String(b.get("name", "Structure %d" % id)), id))
	var bar = Kit.bar(0.0, P.AMBER, 8.0)
	bar.custom_minimum_size.x = 120
	grid.add_child(bar)
	var pct: Label = Kit.num("", 13, P.TEXT)
	grid.add_child(pct)
	var eta: Label = Kit.num("", 13, P.AMBER, true)
	grid.add_child(eta)
	var fault: String = String(r.get("fault", ""))
	grid.add_child(Kit.label(String(d.FAULT_NAME.get(fault, fault.capitalize() if fault != "" else "-")), "", 13, P.TEXT))
	var item: String = String(d.FAULT_ITEM.get(fault, ""))
	if item != "":
		var have: int = d.total_of(item)
		grid.add_child(Kit.chip(Icons.item(item), "1 of %d" % have, d.item_color(item), "Maintenance uses 1 %s. %d in the colony." % [d.item_name(item).to_lower(), have], have >= 1, 16))
	else:
		grid.add_child(Kit.label("-", "", 13, P.TEXT_3))
	var mb: Button = Kit.button("Maintain now", func():
		hud.main.submit("maintain", {"id": id})
		hud.toast("Maintenance of %s is the next technician job." % String(b.get("name", "")), "info", "wrench"),
		"Maintain now\nA technician does this job first. Wear goes back to 0.", "PrimaryButton", "wrench", 14)
	mb.custom_minimum_size.y = 28
	grid.add_child(mb)
	return func(rr: Dictionary):
		var w: float = float(rr.get("wear", 0.0))
		var fa: float = maxf(1.0, float(rr.get("fail_at", 100.0)))
		bar.value = clampf(w / fa, 0.0, 1.0)
		bar.color = P.RED if w / fa >= 0.9 else P.AMBER
		pct.text = "%d%% of %d%%" % [int(w), int(fa)]
		var e: float = float(rr.get("eta_s", -1.0))
		eta.text = Kit.clock(e) if e >= 0.0 else "-"
