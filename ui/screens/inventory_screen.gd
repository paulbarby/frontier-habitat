extends "res://ui/screens/screen.gd"
## Inventory: every item of the colony by category, with its total, what is reserved and
## carried, what is free, the trend (sparkline of the last samples), days of supply at
## yesterday's use, and spoilage (shelf life and units lost yesterday).

const Spark = preload("res://ui/charts/sparkline.gd")
const Storage = preload("res://ui/storage.gd")

var _rows := {}           # item id -> {total, reserved, free, days, spoil, spark}
var _clock := 0
var _only_stock := false
var _st_sort := "fill"      # By structure: "fill" (fullest first) or "name"
var _st_base := -2          # By structure: base id, -1 all bases, -2 = follow the top bar filter
var st_rows: Array = []     # By structure: the rows as shown (tests)

func _init() -> void:
	icon = "inventory"
	title = "Inventory"
	tabs = [["all", "All", "grid"], ["raw", "Raw", "icat_raw"], ["material", "Materials", "icat_material"], ["component", "Components", "icat_component"],
		["medical", "Medical", "icat_medical"], ["water", "Water", "icat_water"], ["crop", "Crops", "icat_crop"], ["dish", "Dishes", "icat_dish"],
		["structures", "By structure", "build"]]

func header_extra(row: HBoxContainer) -> void:
	var c := CheckButton.new()
	c.text = "Only items in stock"
	c.tooltip_text = "Only items in stock\nHides the items the colony has none of."
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on):
		_only_stock = on
		_build_tab_content())
	row.add_child(c)

func build_tab(id: String, box: VBoxContainer) -> void:
	if id == "structures":
		# The item rows of the last tab are freed now: _update() must not touch them (it did, and the
		# web build faulted with "memory access out of bounds" on the first switch to this tab).
		_rows = {}
		_by_structure(box)
		return
	var d = hud.data
	_rows = {}
	var totals: Dictionary = _totals()
	var units := 0
	for k in totals:
		units += int(totals[k].get("total", 0))
	var where: String = ("at " + hud.base_filter_name()) if hud.base_filter >= 0 else "in the colony"
	set_subtitle("%s %s  ·  %s of item" % [Kit.plural(units, "unit"), where, Kit.plural(totals.size(), "kind")])
	# Column heads
	var head: HBoxContainer = _cols(null)
	for c in [["Item", 230], ["Total", 70], ["Reserved", 80], ["Carried", 72], ["Free", 64], ["Trend", 150], ["Days of supply", 110], ["Spoilage", 170]]:
		var l: Label = Kit.head(c[0], P.TEXT_3, 10)
		l.custom_minimum_size.x = c[1]
		head.add_child(l)
	box.add_child(Kit.margin(head, 8, 0, 0, 0))
	var body: VBoxContainer = Kit.seam_list(2)   # v4: rows with seams in a darker well
	box.add_child(Kit.well_scroll(body))
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
		var gp: Control = Kit.gap(0, 6)
		gp.set_meta("no_seam", true)
		ch.set_meta("no_seam", true)
		body.add_child(gp)
		body.add_child(ch)
		for it in ids:
			body.add_child(_row(it))
	_update()

## Stock of the whole colony, or of the base picked in the top bar (sim.bases.totals, SIM v4).
func _totals() -> Dictionary:
	var s = hud.main.sim
	if hud.base_filter >= 0 and "bases" in s and s.bases != null:
		return s.bases.totals(hud.base_filter)
	return hud.data.totals()

## The base filter changed: build the tab again.
func rebuild_tab() -> void:
	_build_tab_content()

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
	var totals: Dictionary = _totals()
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

# ---------------------------------------------------------------- by structure (Paul, 2026-09-28)
## Every structure (and vehicle) with stock: its base, how full it is, FULL, and the top items. Sort
## by fill or by name; filter by base; click a row: the camera goes there and selects it.
func _by_structure(box: VBoxContainer) -> void:
	var s = hud.main.sim
	var d = hud.data
	var bases: Array = s.bases.list() if "bases" in s and s.bases != null and s.bases.has_method("list") else []
	var base_f: int = hud.base_filter if _st_base == -2 else _st_base
	var bar: HBoxContainer = Kit.hbox(10)
	box.add_child(bar)
	bar.add_child(Kit.label("Sort:", "", 13, P.TEXT_2))
	for sp in [["fill", "Fullest first"], ["name", "Name"]]:
		var key: String = sp[0]
		var b: Button = Kit.button(String(sp[1]), func():
			_st_sort = key
			_build_tab_content(), "Sort by %s" % String(sp[1]).to_lower(), "ChipButton")
		b.toggle_mode = true
		b.set_pressed_no_signal(_st_sort == key)
		bar.add_child(b)
	if bases.size() > 1:
		bar.add_child(Kit.gap(12))
		bar.add_child(Kit.label("Base:", "", 13, P.TEXT_2))
		var ob := OptionButton.new()
		ob.tooltip_text = "Base\nShows the structures of one base, or of all."
		ob.add_item("All bases", 0)
		var sel := 0
		for i in bases.size():
			ob.add_item(String(bases[i].get("name", "Base %d" % int(bases[i]["id"]))), i + 1)
			if int(bases[i]["id"]) == base_f:
				sel = i + 1
		ob.select(sel)
		ob.item_selected.connect(func(ix: int):
			_st_base = -1 if ix == 0 else int(bases[ix - 1]["id"])
			_build_tab_content())
		bar.add_child(ob)
	# Rows: SIM's sim.inventory.by_structure(base) (structures, vehicles, "On the ground", "Carried");
	# an older SIM: the UI reads each structure (ui/storage.gd).
	var rows: Array = []
	if s.inv.has_method("by_structure"):
		for r in s.inv.by_structure(base_f if base_f >= 0 else -1):
			var used: int = int(r.get("used", 0))
			var its: Dictionary = r.get("items", {})
			var n_all := 0
			for k in its:
				n_all += int(its[k])
			if n_all <= 0 and not bool(r.get("full", false)):
				continue
			var kind: String = String(r.get("kind", "structure"))
			var capv: int = int(r.get("capacity", 0))
			var pos = null
			if kind == "structure" and s.state["buildings"].has(int(r["id"])):
				pos = s.state["buildings"][int(r["id"])]["pos"]
			elif kind == "vehicle":
				pos = hud.v4.vehicle(int(r["id"])).get("pos", null)
			rows.append({"kind": "building" if kind == "structure" else kind, "id": int(r["id"]), "name": String(r.get("name", "")), "def": String(r.get("def", "")),
				"base": int(r.get("base", -1)), "pos": pos, "used": used if capv > 0 else n_all, "cap": capv, "frac": float(used) / float(capv) if capv > 0 else 0.0,
				"full": bool(r.get("full", false)), "full_titles": ["Stored"] if bool(r.get("full", false)) else [], "items": its})
	for bid in (s.state["buildings"] if rows.is_empty() and not s.inv.has_method("by_structure") else {}):
		var b: Dictionary = s.state["buildings"][bid]
		if String(b.get("state", "")) != "active" or String(b.get("kind", "")) == "link":
			continue
		var sm: Dictionary = Storage.summary(s, b)
		if int(sm["cap"]) <= 0 or (int(sm["used"]) <= 0 and not bool(sm["full"])):
			continue
		var base: int = int(s.bases.base_of(int(bid))) if not bases.is_empty() else -1
		if base_f >= 0 and base != base_f:
			continue
		rows.append({"kind": "building", "id": int(bid), "name": String(b.get("name", "")), "def": String(b["def"]), "base": base, "pos": b["pos"],
			"used": int(sm["used"]), "cap": int(sm["cap"]), "frac": float(sm["frac"]), "full": bool(sm["full"]), "full_titles": sm["full_titles"], "items": sm["items"]})
	for v in (hud.v4.vehicles() if not s.inv.has_method("by_structure") else []):
		var ci: int = int(v.get("cargo_inv", -1))
		if ci == -1 or not s.inv.exists(ci):
			continue
		var inf: Dictionary = Storage.info(s, ci, false)
		if int(inf["used"]) <= 0:
			continue
		var vb: int = int(v.get("base", -1))
		if base_f >= 0 and vb != base_f:
			continue
		var its := {}
		for it in inf["items"]:
			its[it["id"]] = int(it["n"])
		rows.append({"kind": "vehicle", "id": int(v["id"]), "name": String(v["name"]), "def": String(v["kind"]), "base": vb, "pos": v["pos"],
			"used": int(inf["used"]), "cap": int(inf["cap"]), "frac": float(inf["frac"]), "full": bool(inf["full"]), "full_titles": ["Cargo"] if bool(inf["full"]) else [], "items": its})
	if _st_sort == "fill":
		rows.sort_custom(func(a, c): return float(a["frac"]) > float(c["frac"]) if absf(float(a["frac"]) - float(c["frac"])) > 0.0001 else String(a["name"]).naturalnocasecmp_to(String(c["name"])) < 0)
	else:
		rows.sort_custom(func(a, c): return String(a["name"]).naturalnocasecmp_to(String(c["name"])) < 0)
	st_rows = rows
	var nfull := 0
	for r in rows:
		if bool(r["full"]):
			nfull += 1
	set_subtitle("%s with stock  ·  %d full" % [Kit.plural(rows.size(), "structure"), nfull])
	var head: HBoxContainer = Kit.hbox(10)
	for c in [["Structure", 250], ["Base", 150], ["Fill", 200], ["", 64], ["Top items", 420]]:
		var l: Label = Kit.head(c[0], P.TEXT_3, 10)
		l.custom_minimum_size.x = c[1]
		head.add_child(l)
	box.add_child(Kit.margin(head, 8, 0, 0, 0))
	var list: VBoxContainer = Kit.seam_list(2)
	box.add_child(Kit.well_scroll(list))
	if rows.is_empty():
		list.add_child(Kit.label("Nothing is stored here yet.", "", 14, P.TEXT_2))
		return
	for r in rows:
		list.add_child(_st_row(r, bases))

func _st_row(r: Dictionary, bases: Array) -> Control:
	var s = hud.main.sim
	var d = hud.data
	var b: Button = Kit.button("", Callable(), "%s\n%d of %d%s. Click: close this screen, go there and select it." % [r["name"], int(r["used"]), int(r["cap"]),
		(" · FULL: " + ", ".join(r["full_titles"]).to_lower()) if bool(r["full"]) else ""], "ListButton")
	b.custom_minimum_size.y = 40
	var rid: int = int(r["id"])
	var rk: String = String(r["kind"])
	var rp = r["pos"]
	if rp == null:
		b.tooltip_text = "%s\n%d units." % [r["name"], int(r["used"])]
		b.disabled = false
	b.pressed.connect(func():
		if rp == null:
			return
		host.close(self)
		if rk == "building":
			hud.main.select("building", rid)
		hud.main.focus_on(rp))
	var h: HBoxContainer = Kit.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var nb: HBoxContainer = Kit.hbox(8)
	nb.custom_minimum_size.x = 250
	var cat: String = String(s.bdef(String(r["def"])).get("category", "logistics")) if rk == "building" else "logistics"
	nb.add_child(Kit.icon(Icons.category(cat) if rk == "building" else {"vehicle": "rover", "ground": "crate", "carried": "people"}.get(rk, "inventory"), 18, P.cat(cat) if rk == "building" else P.CYAN))
	var nl: Label = Kit.label(String(r["name"]), "", 14, P.TEXT)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.custom_minimum_size.x = 214
	nb.add_child(nl)
	h.add_child(nb)
	var bn := "-"
	for x in bases:
		if int(x["id"]) == int(r["base"]):
			bn = String(x.get("name", ""))
	var bl: Label = Kit.label(bn, "SmallLabel", 12, P.TEXT_2)
	bl.custom_minimum_size.x = 150
	bl.clip_text = true
	h.add_child(bl)
	var fr: HBoxContainer = Kit.hbox(6)
	fr.custom_minimum_size.x = 200
	var level: int = 2 if float(r["frac"]) >= Storage.CRIT else (1 if float(r["frac"]) >= Storage.WARN else 0)
	if int(r["cap"]) > 0:
		var br = Kit.bar(clampf(float(r["frac"]), 0.0, 1.0), Storage.level_color(level), 6.0)
		br.custom_minimum_size.x = 100
		fr.add_child(br)
		fr.add_child(Kit.num("%d%%  %d/%d" % [int(roundf(float(r["frac"]) * 100.0)), int(r["used"]), int(r["cap"])], 12, Storage.level_color(level) if level > 0 else P.TEXT))
	else:
		fr.add_child(Kit.num("%d units" % int(r["used"]), 12, P.TEXT_2))
	h.add_child(fr)
	var fl: Control = Kit.badge("FULL", P.RED) if bool(r["full"]) else Control.new()
	fl.custom_minimum_size.x = 64
	h.add_child(fl)
	var tops: HBoxContainer = Kit.hbox(10)
	var its: Array = (r["items"] as Dictionary).keys()
	its.sort_custom(func(a, c): return int(r["items"][a]) > int(r["items"][c]))
	for it in its.slice(0, 4):
		tops.add_child(Kit.chip(Icons.item(String(it)), "%d" % int(r["items"][it]), d.item_color(String(it)), d.item_name(String(it)), true, 16))
	if its.size() > 4:
		tops.add_child(Kit.label("+%d more" % (its.size() - 4), "SmallLabel", 12, P.TEXT_3))
	h.add_child(tops)
	return b
