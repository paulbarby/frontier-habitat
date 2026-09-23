extends "res://ui/screens/screen.gd"
## Inventory: every item of the colony by category, with its total, what is reserved and
## carried, what is free, the trend (sparkline of the last samples), days of supply at
## yesterday's use, and spoilage (shelf life and units lost yesterday).

const Spark = preload("res://ui/charts/sparkline.gd")

var _rows := {}           # item id -> {total, reserved, free, days, spoil, spark}
var _clock := 0
var _only_stock := false

func _init() -> void:
	icon = "inventory"
	title = "Inventory"
	tabs = [["all", "All", "grid"], ["raw", "Raw", "icat_raw"], ["material", "Materials", "icat_material"], ["component", "Components", "icat_component"],
		["medical", "Medical", "icat_medical"], ["water", "Water", "icat_water"], ["crop", "Crops", "icat_crop"], ["dish", "Dishes", "icat_dish"]]

func header_extra(row: HBoxContainer) -> void:
	var c := CheckButton.new()
	c.text = "Only items in stock"
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on):
		_only_stock = on
		_build_tab_content())
	row.add_child(c)

func build_tab(id: String, box: VBoxContainer) -> void:
	var d = hud.data
	_rows = {}
	var totals: Dictionary = d.totals()
	var units := 0
	for k in totals:
		units += int(totals[k].get("total", 0))
	set_subtitle("%s in the colony  ·  %s of item" % [Kit.plural(units, "unit"), Kit.plural(totals.size(), "kind")])
	# Column heads
	var head: HBoxContainer = _cols(null)
	for c in [["Item", 230], ["Total", 70], ["Reserved", 80], ["Carried", 72], ["Free", 64], ["Trend", 150], ["Days of supply", 110], ["Spoilage", 170]]:
		var l: Label = Kit.head(c[0], P.TEXT_3, 10)
		l.custom_minimum_size.x = c[1]
		head.add_child(l)
	box.add_child(Kit.margin(head, 8, 0, 0, 0))
	var body: VBoxContainer = Kit.vbox(2)
	box.add_child(Kit.scroll(body))
	var cats: Dictionary = d.item_categories()
	var order: Array = cats.keys()
	order.sort_custom(func(a, b): return int(cats[a].get("order", 0)) < int(cats[b].get("order", 0)))
	for cat in order:
		if id != "all" and String(cat) != id:
			continue
		var ids: Array = []
		for it in d.items():
			if d.item_cat(String(it)) == String(cat):
				if _only_stock and int(totals.get(it, {}).get("total", 0)) <= 0:
					continue
				ids.append(String(it))
		if ids.is_empty():
			continue
		var ch: HBoxContainer = Kit.hbox(8)
		ch.add_child(Kit.icon("icat_" + String(cat), 16, P.CYAN))
		ch.add_child(Kit.head(String(cats[cat].get("name", cat)), P.CYAN, 12, "head_wide"))
		body.add_child(Kit.gap(0, 6))
		body.add_child(ch)
		for it in ids:
			body.add_child(_row(it))
	_update()

func _cols(parent) -> HBoxContainer:
	var h: HBoxContainer = Kit.hbox(10)
	if parent != null:
		parent.add_child(h)
	return h

func _row(id: String) -> Control:
	var d = hud.data
	var b: Button = Kit.button("", Callable(), "", "ListButton")
	b.custom_minimum_size.y = 34
	var it: Dictionary = d.item(id)
	b.tooltip_text = "%s\n%s" % [d.item_name(id), String(it.get("desc", ""))]
	var h: HBoxContainer = Kit.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	b.add_child(h)
	var name_box: HBoxContainer = Kit.hbox(8)
	name_box.custom_minimum_size.x = 230
	name_box.add_child(Kit.icon(load("res://ui/theme/icons.gd").item(id), 20, d.item_color(id)))
	name_box.add_child(Kit.label(d.item_name(id), "", 14, P.TEXT))
	h.add_child(name_box)
	var total: Label = _num(h, 70, true)
	var res: Label = _num(h, 80)
	var car: Label = _num(h, 72)
	var free: Label = _num(h, 64)
	var sp = Spark.new()
	sp.color = d.item_color(id)
	sp.custom_minimum_size = Vector2(150, 26)
	sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sp)
	var days: Label = _num(h, 110)
	var spoil: Label = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	spoil.custom_minimum_size.x = 170
	h.add_child(spoil)
	_rows[id] = {"total": total, "res": res, "car": car, "free": free, "spark": sp, "days": days, "spoil": spoil}
	return b

func _num(h: HBoxContainer, w: float, bold: bool = false) -> Label:
	var l: Label = Kit.num("", 14 if bold else 13, P.TEXT if bold else P.TEXT_2, bold)
	l.custom_minimum_size.x = w
	h.add_child(l)
	return l

func refresh() -> void:
	_clock += 1
	if _clock % 5 == 0:
		_update()

func _update() -> void:
	var d = hud.data
	var totals: Dictionary = d.totals()
	var daily: Array = d.daily()
	var last: Dictionary = daily[daily.size() - 1] if not daily.is_empty() else {}
	var used: Dictionary = last.get("consumed", {})
	var lost: Dictionary = last.get("spoiled", {})
	var pop: int = maxi(1, hud.main.sim.alive_count())
	for id in _rows:
		var r: Dictionary = _rows[id]
		var row: Dictionary = totals.get(id, {})
		var t: int = int(row.get("total", 0))
		var rv: int = int(row.get("reserved", 0))
		var cv: int = int(row.get("carried", 0))
		(r["total"] as Label).text = "%d" % t
		(r["res"] as Label).text = "%d" % rv if rv > 0 else "-"
		(r["car"] as Label).text = "%d" % cv if cv > 0 else "-"
		(r["free"] as Label).text = "%d" % maxi(0, t - rv - cv)
		r["spark"].points = d.series("item:" + String(id))
		# Days of supply: dishes feed one colonist a day; other items at yesterday's use.
		var dtext := "-"
		var dcol: Color = P.TEXT_2
		if d.item_cat(String(id)) == "dish":
			dtext = "shared: %s" % Kit.days(float(d.dish_total(totals)) / float(pop))
		elif int(used.get(id, 0)) > 0:
			var dd: float = float(t) / float(used[id])
			dtext = Kit.days(dd)
			dcol = P.RED if dd < 0.5 else (P.AMBER if dd < 1.5 else P.TEXT)
		(r["days"] as Label).text = dtext
		(r["days"] as Label).add_theme_color_override("font_color", dcol)
		var shelf: float = float(d.item(String(id)).get("shelf_days", 0.0))
		var sp_text: String = "keeps" if shelf <= 0.0 else "spoils in %s" % Kit.plural(int(shelf), "day")
		if int(lost.get(id, 0)) > 0:
			sp_text += ", %d lost yesterday" % int(lost[id])
		(r["spoil"] as Label).text = sp_text
		(r["spoil"] as Label).add_theme_color_override("font_color", P.AMBER if int(lost.get(id, 0)) > 0 else (P.TEXT_3 if shelf <= 0.0 else P.TEXT_2))
