extends RefCounted
## Content of the inspector tabs. Builds controls into the inspector (ui/hud/inspector.gd)
## and registers bindings for the numbers that change every refresh.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Icons = preload("res://ui/theme/icons.gd")
const BuildCard = preload("res://ui/widgets/build_card.gd")
const LineChart = preload("res://ui/charts/line_chart.gd")

const BLOCK_TEXT := {
	"": "Working.", "no_power": "Stopped: no power.", "no_water": "Stopped: no water on its network.",
	"no_input": "Waiting: no input material has been delivered.", "output_blocked": "Output blocked: the output buffer is full.",
	"disabled": "Switched off by you.", "storage_full": "Idle: storage is full.", "no_reservoir": "No reservoir on its network.",
	"deposit_empty": "The deposit under it is empty.", "unreachable": "Nobody can reach it within suit range.",
	"suit_range": "Too far from an airlock with air. Nobody can work here and walk back on one suit. Build an airlock nearer.",
	"occupied": "Waiting: people are still inside.", "no_spares": "No spare parts for the repair.", "broken": "Broken.", "not_ready": "Not finished.",
	"no_staff": "Waiting for a worker.", "no_recipe": "No recipe chosen.", "no_menu": "No dish can be cooked: check the menu and the crops.",
}

const SHORT := {
	"no_power": "NO POWER", "no_water": "NO WATER", "no_input": "NO INPUT", "output_blocked": "OUTPUT FULL",
	"storage_full": "STORAGE FULL", "no_reservoir": "NO RESERVOIR", "deposit_empty": "DEPOSIT EMPTY",
	"unreachable": "OUT OF REACH", "suit_range": "TOO FAR", "occupied": "WAITING", "no_spares": "NO SPARES",
	"no_staff": "NO WORKER", "no_recipe": "NO RECIPE", "no_menu": "NO DISH",
}

var insp

func _init(i) -> void:
	insp = i

func _hud():
	return insp.hud

func _sim():
	return insp.hud.main.sim

func _d():
	return insp.hud.data

# ---------------------------------------------------------------- signatures
func signature(kind: String, rec: Dictionary, tab: String) -> String:
	if kind == "agent":
		return "a:%d:%s:%s:%s:%d" % [rec["id"], rec["state"], tab, rec.get("role", ""), (rec.get("diet", []) as Array).size()]
	var b: Dictionary = rec
	var up: Dictionary = b.get("upgrade", {})
	var trays := ""
	for t in b.get("trays", []):
		trays += String(t.get("crop", "")) + ","
	return "b:%d:%s:%s:%s:%s:%s:%s:%s:%d:%d:%s:%s:%s:%s:%s:%s" % [b["id"], b["state"], b["def"], tab, b.get("demolish", false), b.get("enabled", true),
		_sim().prod.has_batch(b), b.get("door_open", true), int(b.get("level", 1)), int(b.get("size", 1)), up.get("state", ""), trays,
		str(b.get("menu_off", {}).keys()), b.get("recipe_sel", ""), b.get("crop", ""), str(_sim().state.get("ship", {}).get("stage", -1))]

# ---------------------------------------------------------------- helpers
func _def(b: Dictionary) -> Dictionary:
	var s = _sim()
	if s.has_method("bd"):
		return s.bd(b)
	return s.bdef(b["def"])

func _grid() -> GridContainer:
	var g: GridContainer = Kit.grid(2, 12, 3)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g

## A "name  value" row in a 2-column grid; `getter` returns the value text each refresh.
func _fact(g: GridContainer, name: String, getter: Callable, color: Color = P.TEXT) -> void:
	var l: Label = Kit.dim(name, 13)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(l)
	var v: Label = Kit.num(String(getter.call()), 13, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.add_child(v)
	insp.bind(func(): v.text = String(getter.call()))

func _section(title: String, icon: String = "", color: Color = P.TEXT_2) -> VBoxContainer:
	var v: VBoxContainer = Kit.vbox(5)
	var h: HBoxContainer = Kit.hbox(6)
	if icon != "":
		h.add_child(Kit.icon(icon, 14, color))
	h.add_child(Kit.head(title, color, 11))
	v.add_child(h)
	insp.body().add_child(v)
	return v

func _items_row(items: Dictionary, want: Dictionary = {}) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 10)
	f.add_theme_constant_override("v_separation", 4)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if items.is_empty() and want.is_empty():
		f.add_child(Kit.label("empty", "SmallLabel", 12, P.TEXT_3))
		return f
	var keys: Array = want.keys() if not want.is_empty() else items.keys()
	for res in keys:
		var have: int = int(items.get(res, 0))
		var txt: String = ("%d/%d" % [have, int(want[res])]) if not want.is_empty() else ("%d" % have)
		var ok: bool = want.is_empty() or have >= int(want[res])
		f.add_child(Kit.chip(Icons.item(String(res)), txt, _d().item_color(String(res)), _d().item_name(String(res)), ok, 16))
	return f

func _cost_chips(cost: Dictionary) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 10)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var totals: Dictionary = _d().totals()
	for res in cost:
		var row: Dictionary = totals.get(res, {})
		var free: int = int(row.get("total", 0)) - int(row.get("reserved", 0)) - int(row.get("carried", 0))
		f.add_child(Kit.chip(Icons.item(String(res)), "%d" % int(cost[res]), _d().item_color(String(res)), "%s: %d free in storage" % [_d().item_name(String(res)), free], free >= int(cost[res]), 16))
	if cost.is_empty():
		f.add_child(Kit.label("nothing", "SmallLabel", 12, P.TEXT_3))
	return f

func status_of(b: Dictionary) -> Array:
	var s = _sim()
	var state: String = b["state"]
	if bool(b.get("demolish", false)):
		return ["REMOVING", P.RED]
	if state == "blueprint":
		var blk: String = String(b.get("block", ""))
		if blk.begins_with("materials:"):
			return ["WAITING: " + _d().item_name(blk.substr(10)).to_upper(), P.AMBER]
		if blk == "unreachable" or blk == "suit_range":
			return ["OUT OF REACH", P.RED]
		return ["PLANNED", P.CYAN]
	if state == "building":
		return ["BUILDING %d%%" % int(100.0 * float(b["progress"]) / maxf(1.0, float(b["work_total"]))), P.AMBER]
	if state == "broken":
		return ["BROKEN", P.RED]
	if state != "active":
		return [state.to_upper(), P.TEXT_2]
	if not bool(b.get("enabled", true)):
		return ["OFF", P.TEXT_3]
	var def: Dictionary = _def(b)
	if float(def.get("power", 0.0)) > 0.0 and not bool(b.get("powered", true)):
		return ["NO POWER", P.RED]
	var blk2: String = String(b.get("block", ""))
	if blk2 != "" and blk2 != "disabled":
		return [SHORT.get(blk2, blk2.replace("_", " ").to_upper()), P.AMBER]
	if String(b.get("kind", "")) == "room" and not s.util.building_supplied(b["id"]) and String(b["def"]) != "lander":
		return ["NO AIR", P.RED]
	if not (b.get("upgrade", {}) as Dictionary).is_empty():
		return ["UPGRADING", P.VIOLET]
	return ["WORKING", P.GREEN]

# ---------------------------------------------------------------- structures
func building(b: Dictionary) -> void:
	var d = _d()
	var s = _sim()
	var base: Dictionary = s.bdef(b["def"])
	var def: Dictionary = _def(b)
	var cat: String = String(base.get("category", "logistics"))
	var district: String = s.topo.district_name(b["pos"]) if b.has("pos") else ""
	insp.set_header(Icons.category(cat), P.cat(cat), String(b.get("name", base.get("name", ""))), "%s district  ·  %s" % [district, P.CATEGORY_NAME.get(cat, cat.capitalize())])
	var st: Array = status_of(b)
	insp.add_badge(Kit.badge(st[0], st[1]))
	if d.can_level(String(b["def"])):
		insp.add_badge(Kit.badge("LEVEL %d" % d.level_of(b), P.GOLD if d.level_of(b) >= 5 else P.VIOLET))
	if d.has_sizes(String(b["def"])):
		insp.add_badge(Kit.badge("SIZE %s" % d.SIZE_NAMES[clampi(d.size_of(b), 0, 3)], P.CYAN))
	if String(b["def"]) == "meridian":
		insp.add_tabs([])
		_ship(b)
		_footer_building(b, base)
		return
	var tabs: Array = [["overview", "Overview"]]
	var producer: bool = def.has("recipe") or def.has("recipes") or bool(def.get("research_lab", false)) or bool(def.get("automatic", false)) or def.has("gen_solar") or def.has("gen_wind") or def.has("gen_const")
	if producer and b["state"] == "active":
		tabs.append(["production", "Output"])
	if def.has("trays") and String(def.get("crop", "")) != "mushroom" or (def.has("trays") and (def.get("crops", []) as Array).size() > 1):
		tabs.append(["crops", "Crops"])
	elif def.has("trays"):
		tabs.append(["crops", "Trays"])
	if bool(def.get("menu", false)) or String(def.get("recipe", "")) == "cook":
		tabs.append(["menu", "Menu"])
	if d.can_level(String(b["def"])) and b["state"] == "active":
		tabs.append(["upgrade", "Upgrade"])
	if int(def.get("occupants", 0)) > 0 or def.has("work_slots"):
		tabs.append(["staff", "Staff"])
	tabs.append(["stats", "Stats"])
	insp.add_tabs(tabs)
	match insp.tab:
		"production": _production(b, def)
		"crops": _crops(b, def)
		"menu": _menu(b, def)
		"upgrade": _upgrade(b, def)
		"staff": _staff(b, def)
		"stats": _stats(b, def)
		_: _overview(b, def)
	_footer_building(b, base)

func _overview(b: Dictionary, def: Dictionary) -> void:
	var s = _sim()
	var body: VBoxContainer = insp.body()
	var id: int = b["id"]
	var state: String = b["state"]
	if state == "blueprint":
		var sec: VBoxContainer = _section("Materials delivered", "crate")
		var want: Dictionary = b.get("cost", {})
		var have := {}
		for res in want:
			have[res] = s.inv.count(b["inv_site"], res)
		var row: HFlowContainer = _items_row(have, want)
		sec.add_child(row)
		insp.bind(func():
			var bb: Dictionary = s.state["buildings"].get(id, {})
			if bb.is_empty() or bb["state"] != "blueprint":
				return
			for i in row.get_child_count():
				var res: String = want.keys()[i] if i < want.size() else ""
				if res != "":
					var lab: Label = row.get_child(i).get_child(1)
					lab.text = "%d/%d" % [s.inv.count(bb["inv_site"], res), int(want[res])])
		var blk: String = String(b.get("block", ""))
		if blk.begins_with("materials:"):
			sec.add_child(Kit.wrap("Waiting: no free %s in storage." % _d().item_name(blk.substr(10)).to_lower(), 13, P.AMBER))
		elif blk == "unreachable" or blk == "suit_range":
			sec.add_child(Kit.wrap(BLOCK_TEXT[blk], 13, P.RED))
		else:
			sec.add_child(Kit.wrap("Carriers bring the materials. Then technicians build it.", 12, P.TEXT_2))
	elif state == "building":
		var sec2: VBoxContainer = _section("Construction", "build", P.AMBER)
		var bar = Kit.bar(0.0, P.AMBER, 10.0)
		sec2.add_child(bar)
		var lab: Label = Kit.num("", 13, P.TEXT)
		sec2.add_child(lab)
		insp.bind(func():
			var bb: Dictionary = s.state["buildings"].get(id, {})
			if bb.is_empty():
				return
			var f: float = float(bb["progress"]) / maxf(1.0, float(bb["work_total"]))
			bar.value = f
			lab.text = "%d%%  ·  %d of %d work" % [int(f * 100.0), int(bb["progress"]), int(bb["work_total"])])
		if String(b.get("block", "")) == "suit_range":
			sec2.add_child(Kit.wrap(BLOCK_TEXT["suit_range"], 13, P.RED))
	else:
		var hrow: HBoxContainer = Kit.bar_row("Health", float(b.get("health", 100.0)) / 100.0, "%d" % int(b.get("health", 100.0)), P.level(float(b.get("health", 100.0))), 70.0)
		body.add_child(hrow)
		insp.bind(func():
			var bb: Dictionary = s.state["buildings"].get(id, {})
			if bb.is_empty():
				return
			var h: float = float(bb.get("health", 100.0))
			hrow.get_child(1).value = h / 100.0
			hrow.get_child(1).color = P.level(h)
			(hrow.get_child(2) as Label).text = "%d" % int(h))
		var desc: String = String(s.bdef(b["def"]).get("desc", ""))
		if desc != "":
			body.add_child(Kit.wrap(desc, 13, P.TEXT_2))
		if bool(b.get("demolish", false)):
			body.add_child(Kit.wrap("Marked for removal.", 13, P.RED))
		var status := Kit.wrap("", 13, P.TEXT)
		body.add_child(status)
		insp.bind(func():
			var bb: Dictionary = s.state["buildings"].get(id, {})
			if bb.is_empty():
				return
			var blk: String = String(bb.get("block", ""))
			if not s.prod.recipe_of(bb).is_empty():
				blk = s.prod.machine_block(bb)
			status.text = BLOCK_TEXT.get(blk, blk.replace("_", " ").capitalize() + ".")
			status.add_theme_color_override("font_color", P.GREEN if blk == "" else (P.TEXT_3 if blk == "disabled" else P.AMBER)))
	var g: GridContainer = _grid()
	body.add_child(g)
	_network_facts(g, b, def)

func _network_facts(g: GridContainer, b: Dictionary, def: Dictionary) -> void:
	var s = _sim()
	var id: int = b["id"]
	var p: float = float(def.get("power", 0.0))
	if String(b.get("kind", "")) != "link":
		if p > 0.0:
			_fact(g, "Power use", func(): return "%s P  %s" % [Kit.fmt(p), "ON" if bool(s.state["buildings"].get(id, {}).get("powered", false)) else "OFF"])
		_fact(g, "Power network", func():
			if not s.topo.power_comp.has(id):
				return "not joined"
			var ps: Dictionary = s.util.power_stats.get(s.topo.power_comp[id], {})
			if ps.is_empty():
				return "-"
			return "%s / %s P" % [Kit.fmt(s.util.to_rate(ps["gen"])), Kit.fmt(s.util.to_rate(ps["demand"]))])
		_fact(g, "Network energy", func():
			if not s.topo.power_comp.has(id):
				return "-"
			var ps: Dictionary = s.util.power_stats.get(s.topo.power_comp[id], {})
			if ps.is_empty():
				return "-"
			return "%s / %s E" % [Kit.fmt(s.util.units(ps["stored"])), Kit.fmt(s.util.units(ps["cap"]))])
		if s.topo.atmo_comp.has(id):
			_fact(g, "Air group oxygen", func():
				var ast: Dictionary = s.util.atmo_stats.get(s.topo.atmo_comp.get(id, -1), {})
				if ast.is_empty():
					return "-"
				if bool(ast.get("lander", false)):
					return "lander air"
				return "%s / %s" % [Kit.fmt(s.util.units(ast["stock"])), Kit.fmt(s.util.units(ast["cap"]))])
	if def.has("gen_solar"):
		_fact(g, "Output now", func(): return "%s P  (sun %d%%)" % [Kit.fmt(float(def["gen_solar"]) * float(s.state["env"]["sun"]) * float(s.planet["solar_mult"])), int(float(s.state["env"]["sun"]) * 100.0)], P.GOLD)
	if def.has("gen_wind"):
		_fact(g, "Output now", func(): return "%s P  (wind)" % Kit.fmt(float(def["gen_wind"]) * float(s.state["env"]["wind"])), P.GOLD)
	if def.has("energy_cap"):
		_fact(g, "Charge", func(): return "%s / %s E" % [Kit.fmt(s.util.units(int(s.state["buildings"].get(id, {}).get("energy", 0)))), Kit.fmt(float(def["energy_cap"]))])
	if def.has("water_cap"):
		_fact(g, "Water level", func(): return "%s / %s" % [Kit.fmt(s.util.units(int(s.state["buildings"].get(id, {}).get("water", 0)))), Kit.fmt(float(def["water_cap"]))], Color("3AA0D8"))
	if b["def"] == "lander":
		_fact(g, "Shelter air left", func(): return Kit.clock(s.util.lander_seconds_left()), P.AMBER)
	if def.has("beds") and b["def"] != "lander":
		_fact(g, "Beds used", func(): return "%d / %d" % [s.agents.beds_used(id), int(def["beds"])])
	var lock = b.get("lock", {})
	if typeof(lock) == TYPE_DICTIONARY and not (lock as Dictionary).is_empty():
		_fact(g, "Airlock", func():
			var bb: Dictionary = s.state["buildings"].get(id, {})
			var lk: Dictionary = bb.get("lock", {})
			if lk.is_empty():
				return "-"
			var cyc: Dictionary = lk.get("cyc", {})
			return "%d waiting, %s" % [(lk.get("queue", []) as Array).size(), ("cycling %s" % cyc.get("dir", "")) if not cyc.is_empty() else "idle"])
	_fact(g, "People inside", func(): return "%d" % s.build.occupants(id).size())
	_fact(g, "Work priority", func(): return "%d of 3" % int(s.state["buildings"].get(id, {}).get("priority", 1)))

# ---------------------------------------------------------------- production
func _production(b: Dictionary, def: Dictionary) -> void:
	var s = _sim()
	var d = _d()
	var id: int = b["id"]
	var rec: Dictionary = s.prod.recipe_of(b)
	if bool(def.get("research_lab", false)):
		var sec: VBoxContainer = _section("Research", "research", P.VIOLET)
		var g: GridContainer = _grid()
		sec.add_child(g)
		_fact(g, "Project", func():
			var a: String = String(d.research().get("active", ""))
			return d.tech_name(a) if a != "" else "none: pick one in Research (T)", P.VIOLET)
		_fact(g, "Colony research", func(): return "%s RP/day" % Kit.fmt(d.rp_rate()))
		sec.add_child(Kit.button("Open research", func(): insp.hud.open_screen("research"), "The tech tree. Key T.", "", "research", 16))
	var recipes: Array = def.get("recipes", [])
	if recipes.size() > 1:
		var sec2: VBoxContainer = _section("Recipe", "list")
		var cur: String = String(b.get("recipe_sel", def.get("recipe", "")))
		var can: bool = b.has("recipe_sel")
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		sec2.add_child(row)
		for rid in recipes:
			var r: Dictionary = d.recipes().get(String(rid), {})
			var out: String = String(r.get("outputs", {}).keys()[0]) if not r.get("outputs", {}).is_empty() else ""
			var rr: String = String(rid)
			var bt: Button = Kit.button(String(r.get("name", rid)), func(): insp.hud.main.submit("set_recipe", {"id": id, "recipe": rr}), "Make %s." % d.item_name(out).to_lower(), "ChipButton", Icons.item(out) if out != "" else "", 14)
			bt.toggle_mode = true
			bt.set_pressed_no_signal(rr == cur)
			bt.custom_minimum_size.y = 28
			bt.disabled = not can
			row.add_child(bt)
		if not can:
			sec2.add_child(Kit.label("Recipe choice is not available yet.", "SmallLabel", 12, P.TEXT_3))
	if not rec.is_empty() and not bool(rec.get("menu", false)):
		var sec3: VBoxContainer = _section("Recipe", "build")
		var line: HBoxContainer = Kit.hbox(8)
		sec3.add_child(line)
		line.add_child(_items_row(rec.get("inputs", {})) if not rec.get("inputs", {}).is_empty() else Kit.label("from the ground", "SmallLabel", 12, P.TEXT_2))
		line.add_child(Kit.icon("arrow_right", 16, P.CYAN))
		line.add_child(_items_row(rec.get("outputs", {})))
		sec3.add_child(Kit.label("%d work by a %s." % [int(rec.get("work", 0)), String(s.bal["role_names"].get(rec.get("role", ""), rec.get("role", ""))).to_lower()], "SmallLabel", 12, P.TEXT_2))
		var bar = Kit.bar(0.0, P.CYAN, 8.0)
		sec3.add_child(bar)
		var lab: Label = Kit.num("", 12, P.TEXT_2)
		sec3.add_child(lab)
		insp.bind(func():
			var bb: Dictionary = s.state["buildings"].get(id, {})
			if bb.is_empty():
				return
			if s.prod.has_batch(bb):
				var f: float = float(bb["batch"]["progress"]) / maxf(1.0, float(bb["batch"]["work"]))
				bar.value = f
				lab.text = "Batch %d%% done." % int(f * 100.0)
			else:
				bar.value = 0.0
				lab.text = BLOCK_TEXT.get(s.prod.machine_block(bb), "Idle."))
	_rates(b, def)
	for key in ["inv_in", "inv_out"]:
		if int(b.get(key, -1)) != -1 and s.inv.exists(int(b[key])):
			var inv: Dictionary = s.inv.get_inv(b[key])
			var title: String = {"in": "Input buffer", "out": "Output buffer", "store": "Stored"}.get(inv.get("role", ""), "Stock")
			var sec4: VBoxContainer = _section("%s  %d / %d" % [title, s.inv.total(b[key]), int(inv.get("cap", 0))], "inventory")
			sec4.add_child(_items_row(inv.get("items", {})))

func _rates(b: Dictionary, def: Dictionary) -> void:
	var s = _sim()
	var rows: Array = []
	for pair in [["o2_out", "Oxygen made", "/day"], ["water_out", "Water pumped", "/day"], ["water_in", "Water used", "/day"], ["algae_per_day", "Algae grown", "/day"],
			["silicate_per_day", "Silicate dug", "/day"], ["fuel_per_day", "Rocket fuel made", "/day"], ["exotic_per_day", "Exotic crystal found", "/day"],
			["recycle_per_day", "Water recycled", "/day"], ["gen_const", "Power made", " P"], ["o2_bonus", "Extra oxygen", "/day"]]:
		if def.has(pair[0]) and float(def[pair[0]]) > 0.0:
			rows.append([pair[1], Kit.fmt(float(def[pair[0]])) + pair[2]])
	if rows.is_empty():
		return
	var sec: VBoxContainer = _section("Rates at full work", "trend_up")
	var g: GridContainer = _grid()
	sec.add_child(g)
	for r in rows:
		var val: String = r[1]
		_fact(g, r[0], func(): return val)
	if _d().level_of(b) > 1:
		sec.add_child(Kit.label("Level %d: output x%s." % [_d().level_of(b), Kit.fmt(_d().level_mult(_d().level_of(b)))], "SmallLabel", 12, P.VIOLET))

# ---------------------------------------------------------------- crops
func _crops(b: Dictionary, def: Dictionary) -> void:
	var s = _sim()
	var d = _d()
	var id: int = b["id"]
	var can_plan: bool = b.has("crop") or (not (b.get("trays", []) as Array).is_empty() and (b["trays"][0] as Dictionary).has("crop"))
	var avail: Array = []
	for cid in d.crops():
		var c: Dictionary = d.crops()[cid]
		if String(c.get("building", "greenhouse")) == String(b["def"]):
			avail.append(cid)
	if avail.size() > 1:
		var sec: VBoxContainer = _section("Crop for every tray", "cat_food", P.CATEGORY["food"])
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		sec.add_child(row)
		var cur: String = String(b.get("crop", ""))
		for cid in avail:
			var c: Dictionary = d.crops()[cid]
			var tech: String = String(c.get("research", ""))
			var ok: bool = d.tech_done(tech)
			var cc: String = String(cid)
			var tip: String = "%s\nGrows in %s s. Yield %d, biomass %d, water %s per day." % [d.item_name(cc), Kit.fmt(float(c.get("cycle_seconds", 0))), int(c.get("yield", 0)), int(c.get("biomass", 0)), Kit.fmt(float(c.get("water_per_day", 0)))]
			if not ok:
				tip += " Needs research: %s." % d.tech_name(tech)
			var bt: Button = Kit.button(d.item_name(cc), func(): insp.hud.main.submit("set_crop", {"id": id, "crop": cc, "tray": -1}), tip, "ChipButton", Icons.item(cc), 14)
			bt.toggle_mode = true
			bt.set_pressed_no_signal(cc == cur)
			bt.disabled = not ok or not can_plan
			bt.custom_minimum_size.y = 28
			bt.add_theme_color_override("icon_normal_color", d.item_color(cc))
			row.add_child(bt)
		if not can_plan:
			sec.add_child(Kit.label("Crop choice is not available yet.", "SmallLabel", 12, P.TEXT_3))
	var trays: Array = b.get("trays", [])
	var sec2: VBoxContainer = _section("Trays  %d" % trays.size(), "grid")
	for i in trays.size():
		var t: Dictionary = trays[i]
		var crop: String = String(t.get("crop", b.get("crop", def.get("crop", "potato"))))
		var row2: HBoxContainer = Kit.hbox(8)
		row2.add_child(Kit.num("%d" % (i + 1), 12, P.TEXT_3))
		row2.add_child(Kit.icon(Icons.item(crop), 18, d.item_color(crop)))
		var nm: Label = Kit.label(d.item_name(crop), "", 13, P.TEXT)
		nm.custom_minimum_size.x = 84
		row2.add_child(nm)
		var bar = Kit.bar(0.0, P.CATEGORY["food"], 7.0)
		row2.add_child(bar)
		var st: Label = Kit.label("", "SmallLabel", 11, P.TEXT_2)
		st.custom_minimum_size.x = 78
		row2.add_child(st)
		sec2.add_child(row2)
		var ti: int = i
		insp.bind(func(): _update_tray(id, ti, bar, st, crop))

func _update_tray(id: int, ti: int, bar, st: Label, crop: String) -> void:
	var s = _sim()
	var d = _d()
	var bb: Dictionary = s.state["buildings"].get(id, {})
	if bb.is_empty() or ti >= (bb.get("trays", []) as Array).size():
		return
	var tt: Dictionary = bb["trays"][ti]
	var cyc: float = float(d.crops().get(String(tt.get("crop", crop)), {}).get("cycle_seconds", s.bal.get("crop_cycle_seconds", 300)))
	var state: String = String(tt.get("state", ""))
	if state == "growing":
		bar.value = float(tt.get("growth", 0.0)) / maxf(1.0, cyc)
		st.text = "growing %d%%" % int(bar.value * 100.0)
		if float(tt.get("interrupt", 0.0)) > 0.0:
			st.text = "STOPPED %ds" % int(tt["interrupt"])
			bar.color = P.AMBER
		else:
			bar.color = P.CATEGORY["food"]
	elif state == "ready":
		bar.value = 1.0
		bar.color = P.GOLD
		st.text = "READY"
	else:
		bar.value = 0.0
		st.text = "empty"

# ---------------------------------------------------------------- kitchen menu
func _menu(b: Dictionary, def: Dictionary) -> void:
	var d = _d()
	var s = _sim()
	var id: int = b["id"]
	var lvl: int = d.level_of(b)
	var can: bool = b.has("menu_off")
	var off: Dictionary = b.get("menu_off", {})
	var sec: VBoxContainer = _section("Menu  ·  kitchen level %d" % lvl, "food", P.CATEGORY["food"])
	sec.add_child(Kit.wrap("Each batch cooks the dish that best fills the colony's nutrition gap. Switch a dish off to keep it off the menu.", 12, P.TEXT_2))
	if not can:
		sec.add_child(Kit.label("Menu choice is not available yet.", "SmallLabel", 12, P.TEXT_3))
	var totals: Dictionary = d.totals()
	var dishes: Dictionary = d.dishes()
	for dish in dishes:
		if String(dish) == "meals":
			continue
		var ds: Dictionary = dishes[dish]
		var need_lvl: int = int(ds.get("kitchen_level", 1))
		var row: HBoxContainer = Kit.hbox(8)
		row.add_child(Kit.icon(Icons.item(String(dish)), 20, d.item_color(String(dish))))
		var v: VBoxContainer = Kit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var nm: Label = Kit.label(d.item_name(String(dish)), "BodyStrong", 13, P.TEXT if lvl >= need_lvl else P.TEXT_3)
		v.add_child(nm)
		var ing: HBoxContainer = Kit.hbox(6)
		for c in ds.get("ingredients", {}):
			var have: int = int(totals.get(c, {}).get("total", 0))
			ing.add_child(Kit.chip(Icons.item(String(c)), "%d" % int(ds["ingredients"][c]), d.item_color(String(c)), "%s: %d in store" % [d.item_name(String(c)), have], have > 0, 13))
		v.add_child(ing)
		var nu: Dictionary = ds.get("nutrition", {})
		row.tooltip_text = "%s\nProtein %d, carbs %d, fat %d, vitamins %d. Taste %d. Needs kitchen level %d." % [d.item_name(String(dish)), int(nu.get("protein", 0)), int(nu.get("carbs", 0)), int(nu.get("fat", 0)), int(nu.get("vitamins", 0)), int(ds.get("taste", 0)), need_lvl]
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		if lvl < need_lvl:
			row.add_child(Kit.badge("LEVEL %d" % need_lvl, P.TEXT_3))
		else:
			var dd: String = String(dish)
			var tg := CheckButton.new()
			tg.button_pressed = not off.has(dd)
			tg.disabled = not can
			tg.focus_mode = Control.FOCUS_NONE
			tg.toggled.connect(func(on): insp.hud.main.submit("set_dish", {"id": id, "dish": dd, "on": on}))
			row.add_child(tg)
		sec.add_child(row)
	var cooked: Dictionary = s.state.get("stats", {}).get("cooked", {})
	if not cooked.is_empty():
		var sec2: VBoxContainer = _section("Cooked in the colony", "history")
		sec2.add_child(_items_row(cooked))

# ---------------------------------------------------------------- upgrade
func _upgrade(b: Dictionary, def: Dictionary) -> void:
	var d = _d()
	var s = _sim()
	var id: int = b["id"]
	var lvl: int = d.level_of(b)
	var sec: VBoxContainer = _section("Level %d of 5" % lvl, "level", P.VIOLET)
	var pips = Kit.bar(float(lvl) / 5.0, P.GOLD if lvl >= 5 else P.VIOLET, 10.0)
	pips.segments = 5
	sec.add_child(pips)
	var lv: Dictionary = s.bal.get("levels", {})
	sec.add_child(Kit.label("Output x%s  ·  power x%s  ·  wear x%s" % [Kit.fmt(d.level_mult(lvl)), Kit.fmt(float(d._at(lv.get("power_mult", []), lvl - 1, 1.0))), Kit.fmt(float(d._at(lv.get("wear_mult", []), lvl - 1, 1.0)))], "SmallLabel", 12, P.TEXT_2))
	var up: Dictionary = b.get("upgrade", {})
	if not up.is_empty():
		var sec2: VBoxContainer = _section("Upgrading to level %d" % int(up.get("to", lvl + 1)), "upgrade", P.VIOLET)
		var bar = Kit.bar(0.0, P.VIOLET, 10.0)
		sec2.add_child(bar)
		var lab: Label = Kit.num("", 12, P.TEXT)
		sec2.add_child(lab)
		insp.bind(func():
			var bb: Dictionary = s.state["buildings"].get(id, {})
			var u: Dictionary = bb.get("upgrade", {})
			if u.is_empty():
				return
			var f: float = float(u.get("progress", 0.0)) / maxf(1.0, float(u.get("work_total", 1.0)))
			bar.value = f
			if String(u.get("state", "")) == "deliver":
				var miss: Dictionary = s.upgrades.missing(bb) if d.has_helper("upgrades", "missing") else {}
				var parts: Array = []
				for r in miss:
					parts.append("%d %s" % [int(miss[r]), d.item_name(String(r)).to_lower()])
				lab.text = "Materials on their way." + (" Missing: " + ", ".join(parts) + "." if not parts.is_empty() else "")
			else:
				lab.text = "%d%%  ·  %d of %d work. It keeps working meanwhile." % [int(f * 100.0), int(u.get("progress", 0)), int(u.get("work_total", 0))])
		sec2.add_child(Kit.button("Cancel upgrade", func(): insp.hud.main.submit("cancel_upgrade", {"id": id}), "Cancel upgrade\nDelivered materials stay on the ground. Built-in materials come back by half.", "DangerButton", "close", 14))
		return
	var chk: Dictionary = d.upgrade_check(b)
	if lvl >= 5:
		sec.add_child(Kit.wrap("Level 5 is the highest level. This structure carries the gold crown.", 13, P.GOLD))
		return
	var to: int = int(chk.get("to", lvl + 1))
	var sec3: VBoxContainer = _section("Next: level %d" % to, "upgrade", P.GOLD if to >= 5 else P.VIOLET)
	sec3.add_child(Kit.label("Output x%s after the upgrade." % Kit.fmt(d.level_mult(to)), "SmallLabel", 12, P.TEXT_2))
	var cost: Dictionary = chk.get("cost", {})
	if cost.is_empty():
		cost = d.upgrade_cost_preview(b, to)
	sec3.add_child(_cost_chips(cost))
	var tech: String = String(chk.get("research", d.level_tech(String(b["def"]), to)))
	if tech != "":
		var done: bool = d.tech_done(tech)
		var tr: HBoxContainer = Kit.hbox(6)
		tr.add_child(Kit.icon("check" if done else "lock", 14, P.GREEN if done else P.AMBER))
		tr.add_child(Kit.label("Research: %s%s" % [d.tech_name(tech), "" if done else " (" + d.tech_state(tech) + ")"], "", 13, P.GREEN if done else P.AMBER))
		sec3.add_child(tr)
		if to >= 5:
			sec3.add_child(Kit.wrap("Level 5 needs special research: research points and exotic crystals delivered to a research lab.", 12, P.GOLD))
	var ok: bool = bool(chk.get("ok", false))
	var bt: Button = Kit.button("Upgrade to level %d" % to, func(): insp.hud.main.submit("upgrade", {"id": id}), "Upgrade\nCarriers bring the materials, then technicians build them in. The structure keeps working.", "PrimaryButton", "upgrade", 16)
	bt.disabled = not ok
	sec3.add_child(bt)
	if not ok:
		sec3.add_child(Kit.wrap(String(chk.get("text", "")), 12, P.AMBER))

# ---------------------------------------------------------------- staff
func _staff(b: Dictionary, def: Dictionary) -> void:
	var s = _sim()
	var d = _d()
	var id: int = b["id"]
	var rec: Dictionary = s.prod.recipe_of(b)
	var sec: VBoxContainer = _section("People here", "colonists")
	if not rec.is_empty():
		sec.add_child(Kit.label("Work places: %d, for a %s." % [int(def.get("work_slots", 1)), String(s.bal["role_names"].get(rec.get("role", ""), "")).to_lower()], "SmallLabel", 12, P.TEXT_2))
	elif bool(def.get("research_lab", false)):
		sec.add_child(Kit.label("Work places: %d, for a scientist." % int(def.get("work_slots", 1)), "SmallLabel", 12, P.TEXT_2))
	var list: VBoxContainer = Kit.vbox(4)
	sec.add_child(list)
	var ids: Array = s.build.occupants(id)
	if ids.is_empty():
		list.add_child(Kit.label("Nobody is inside now.", "SmallLabel", 12, P.TEXT_3))
	for aid in ids.slice(0, 12):
		var a: Dictionary = s.state["agents"].get(aid, {})
		if a.is_empty():
			continue
		var a_id: int = aid
		var row: Button = Kit.button("", func():
			insp.hud.main.select("agent", a_id), "", "ListButton")
		row.custom_minimum_size.y = 30
		var h: HBoxContainer = Kit.hbox(8)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 8
		row.add_child(h)
		h.add_child(Kit.icon(Icons.role(String(a["role"])), 16, P.ROLE.get(a["role"], P.TEXT)))
		var nm: Label = Kit.label(String(a["name"]), "", 13)
		nm.custom_minimum_size.x = 120
		h.add_child(nm)
		h.add_child(Kit.label(String(a.get("goal", "")), "SmallLabel", 12, P.TEXT_2))
		list.add_child(row)

# ---------------------------------------------------------------- stats
func _stats(b: Dictionary, def: Dictionary) -> void:
	var d = _d()
	var s = _sim()
	var body: VBoxContainer = insp.body()
	var name := ""
	var col: Color = P.CYAN
	var title := ""
	var rec: Dictionary = s.prod.recipe_of(b)
	if not rec.is_empty() and not rec.get("outputs", {}).is_empty():
		var out: String = String(rec["outputs"].keys()[0])
		name = "item:" + out
		col = d.item_color(out)
		title = "%s in the colony" % d.item_name(out)
	elif def.has("gen_solar") or def.has("gen_wind") or def.has("gen_const") or def.has("energy_cap"):
		name = "power_gen" if not def.has("energy_cap") else "energy"
		col = P.GOLD
		title = "Power made" if name == "power_gen" else "Stored energy"
	elif def.has("o2_out"):
		name = "o2_stock"
		col = P.CATEGORY["life_support"]
		title = "Oxygen in base rooms"
	elif def.has("water_out") or def.has("water_cap"):
		name = "water_stock"
		col = Color("3AA0D8")
		title = "Water"
	elif def.has("trays") or bool(def.get("menu", false)):
		name = "food_days" if not d.series("food_days").is_empty() else "meals"
		col = P.CATEGORY["food"]
		title = "Food"
	elif bool(def.get("research_lab", false)):
		name = "rp_rate"
		col = P.VIOLET
		title = "Research points per day"
	else:
		name = "pop"
		col = P.CATEGORY["housing"]
		title = "Colonists"
	var ch = LineChart.new()
	ch.title = title
	ch.mode = "area"
	ch.ticks_per_day = float(s.bal["day_length"]) * float(s.bal["tick_hz"])
	ch.custom_minimum_size = Vector2(340, 150)
	ch.series = [{"name": title, "color": col, "points": d.series(name)}]
	ch.show_legend = false
	body.add_child(ch)
	insp.bind(func(): ch.series = [{"name": title, "color": col, "points": d.series(name)}])
	var bst: Dictionary = b.get("stats", {})
	if not bst.is_empty():
		var g: GridContainer = _grid()
		body.add_child(g)
		for k in bst:
			var kk: String = String(k)
			var v = bst[k]
			if typeof(v) == TYPE_DICTIONARY:
				continue
			_fact(g, kk.replace("_", " ").capitalize(), func(): return Kit.fmt(float(s.state["buildings"].get(b["id"], {}).get("stats", {}).get(kk, 0))))
	var g2: GridContainer = _grid()
	body.add_child(g2)
	var id: int = b["id"]
	_fact(g2, "Built on", func(): return d.tick_to_day(int(s.state["buildings"].get(id, {}).get("built_tick", s.state["buildings"].get(id, {}).get("tick", 0)))) if s.state["buildings"].get(id, {}).has("built_tick") else "-")
	_fact(g2, "Radius", func(): return "%s m" % Kit.fmt(float(s.state["buildings"].get(id, {}).get("radius", 0.0))))

# ---------------------------------------------------------------- the Meridian
func _ship(b: Dictionary) -> void:
	var d = _d()
	var s = _sim()
	var info: Dictionary = d.ship()
	var body: VBoxContainer = insp.body()
	if info.is_empty():
		body.add_child(Kit.wrap("The crashed colony ship. Repairs are not available yet.", 13, P.TEXT_2))
		return
	var stages: Array = s.bal.get("ship", {}).get("stages", [])
	var stage: int = int(info.get("stage", 0))
	var sec: VBoxContainer = _section("Repair stage %d of 5" % mini(stage, 5), "ship", P.CATEGORY["space"])
	var pips = Kit.bar(float(stage) / 5.0, P.CYAN if stage < 5 else P.GOLD, 10.0)
	pips.segments = 5
	sec.add_child(pips)
	var names: Array = []
	for st in stages:
		names.append(String(st.get("name", "")))
	names.append("Operational")
	sec.add_child(Kit.label("Now: %s" % (names[stage] if stage < names.size() else "Operational"), "BodyStrong", 14, P.TEXT))
	if stage < stages.size():
		var cur: Dictionary = stages[stage]
		var want: Dictionary = cur.get("deliver", {})
		if not want.is_empty():
			var have := {}
			var inv_id: int = int(s.state["buildings"].get(b["id"], {}).get("inv_in", -1))
			for r in want:
				have[r] = s.inv.count(inv_id, r) if inv_id != -1 and s.inv.exists(inv_id) else 0
			sec.add_child(Kit.label("Deliver", "SmallLabel", 12, P.TEXT_2))
			sec.add_child(_items_row(have, want))
		if float(cur.get("work", 0)) > 0.0:
			var bar = Kit.bar(0.0, P.CYAN, 8.0)
			sec.add_child(bar)
			var lab: Label = Kit.num("", 12, P.TEXT_2)
			sec.add_child(lab)
			var work: float = float(cur["work"])
			insp.bind(func():
				var inf: Dictionary = d.ship()
				var f: float = float(inf.get("progress", 0.0)) / maxf(1.0, work)
				bar.value = f
				lab.text = "%s  ·  %d of %d work" % [String(inf.get("phase", "")).capitalize(), int(inf.get("progress", 0.0)), int(work)])
	if stage >= 4:
		var rr = Kit.bar_row("Readiness", float(info.get("readiness", 0.0)) / 100.0, "%d%%" % int(info.get("readiness", 0.0)), P.level(float(info.get("readiness", 0.0)), 80.0, 60.0), 80.0)
		body.add_child(rr)
		insp.bind(func():
			var inf: Dictionary = d.ship()
			var rv: float = float(inf.get("readiness", 0.0))
			rr.get_child(1).value = rv / 100.0
			rr.get_child(1).color = P.level(rv, 80.0, 60.0)
			(rr.get_child(2) as Label).text = "%d%%" % int(rv))
		var g: GridContainer = _grid()
		body.add_child(g)
		_fact(g, "Supply runs", func(): return "%d" % int(d.ship().get("runs", 0)))
		_fact(g, "Away", func(): return "yes" if bool(d.ship().get("away", false)) else "no")
	var prog: String = String(info.get("program", "auto"))
	var row: HBoxContainer = Kit.hbox(6)
	body.add_child(row)
	for spec in [["survey", "Repair", "Colonists work on the ship when the Meridian chapter is open."], ["hold", "Hold", "Stop ship work. Materials stay in the ship."], ["supply_run", "Supply run", "Fly a supply run now (needs research Orbital Logistics and readiness)."]]:
		var act: String = spec[0]
		var bt: Button = Kit.button(spec[1], func(): insp.hud.main.submit("ship", {"action": act}), "%s\n%s" % [spec[1], spec[2]], "ChipButton")
		bt.custom_minimum_size.y = 28
		bt.toggle_mode = true
		bt.set_pressed_no_signal((act == "hold" and prog == "hold") or (act == "survey" and prog != "hold"))
		row.add_child(bt)

# ---------------------------------------------------------------- footer actions
func _footer_building(b: Dictionary, base: Dictionary) -> void:
	var f: HFlowContainer = insp.footer()
	var m = insp.hud.main
	var id: int = b["id"]
	var state: String = b["state"]
	if String(b["def"]) == "meridian":
		return
	if state == "blueprint" or state == "building":
		f.add_child(Kit.button("Cancel plan", func(): m.submit("cancel", {"id": id}), "Cancel plan\nDelivered materials stay on the ground and can be collected.", "DangerButton", "close", 14))
	else:
		var def: Dictionary = _def(b)
		if float(def.get("power", 0.0)) > 0.0 or def.has("recipe") or def.has("trays") or bool(def.get("automatic", false)):
			var on: bool = bool(b.get("enabled", true))
			f.add_child(Kit.button("Switch off" if on else "Switch on", func(): m.submit("set_enabled", {"id": id, "on": not bool(m.sim.state["buildings"][id]["enabled"])}), "Switch on or off\nA switched-off structure uses no power and does no work.", "", "power_toggle", 14))
		if _sim().prod.has_batch(b):
			f.add_child(Kit.button("Cancel batch", func(): insp.hud.confirm("Cancel the batch in %s?" % b["name"], ["The inputs already used by this batch are lost."], func(): m.submit("cancel_batch", {"id": id}), "Cancel batch", true), "", "", "close", 14))
		if b["def"] == "corridor":
			var open: bool = bool(b.get("door_open", true))
			f.add_child(Kit.button("Close door" if open else "Open door", func(): m.submit("set_door", {"id": id, "open": not bool(m.sim.state["buildings"][id].get("door_open", true))}), "Isolation door\nA closed door separates the air of the two sides.", "", "door", 14))
		if bool(b.get("demolish", false)):
			f.add_child(Kit.button("Keep it", func(): m.submit("undo_demolish", {"id": id}), "Stop the removal.", "", "check", 14))
		elif b["def"] != "lander":
			f.add_child(Kit.button("Remove", func(): insp.hud.ask_demolish(id), "Remove\nHalf of the materials come back. Key Delete.", "DangerButton", "demolish", 14))
	var pr: HBoxContainer = Kit.hbox(2)
	pr.add_child(Kit.icon("priority", 16, P.TEXT_2))
	pr.add_child(Kit.icon_button("minus", func(): m.submit("set_building_priority", {"id": id, "value": int(m.sim.state["buildings"][id]["priority"]) - 1}), "Lower work priority", "GhostButton", 12, 26))
	var pl: Label = Kit.num("%d" % int(b.get("priority", 1)), 14, P.TEXT, true)
	pr.add_child(pl)
	pr.add_child(Kit.icon_button("plus", func(): m.submit("set_building_priority", {"id": id, "value": int(m.sim.state["buildings"][id]["priority"]) + 1}), "Raise work priority\n3 is first. 0 is never.", "GhostButton", 12, 26))
	f.add_child(pr)
	insp.bind(func(): pl.text = "%d" % int(m.sim.state["buildings"].get(id, {}).get("priority", 1)))

# ---------------------------------------------------------------- colonists
func agent(a: Dictionary) -> void:
	var s = _sim()
	var d = _d()
	var id: int = a["id"]
	var role: String = String(a.get("role", ""))
	var where: String = "Outside" if a["where"] == "out" else "In " + String(s.state["buildings"].get(a["bld"], {}).get("name", "a room"))
	insp.set_header(Icons.role(role), P.ROLE.get(role, P.CYAN), String(a["name"]), "%s  ·  %s" % [String(s.bal["role_names"].get(role, role)), where])
	if a["state"] != "alive":
		insp.add_badge(Kit.badge("DEAD", P.RED))
		insp.body().add_child(Kit.wrap("Died of %s." % String(a.get("cause", "unknown causes")), 14, P.RED))
		return
	var h: float = float(a.get("health", 100.0))
	insp.add_badge(Kit.badge("HEALTHY" if h >= 70.0 else ("HURT" if h >= 35.0 else "CRITICAL"), P.level(h, 70.0, 35.0)))
	var score: float = d.agent_nutrition_score(a)
	if score >= 0.0:
		var low := false
		for k in ["protein", "carbs", "fat", "vitamins"]:
			if float(a.get("nutrition", {}).get(k, 100.0)) < 25.0:
				low = true
		insp.add_badge(Kit.badge("DEFICIENT" if low else ("WELL FED" if score >= 70.0 else "FED"), P.RED if low else (P.GREEN if score >= 70.0 else P.AMBER)))
	insp.add_tabs([["status", "Status"], ["nutrition", "Nutrition"]] if score >= 0.0 else [["status", "Status"]])
	if insp.tab == "nutrition" and score >= 0.0:
		_nutrition(a)
	else:
		_needs(a)
	var f: HFlowContainer = insp.footer()
	f.add_child(Kit.button("Follow", func(): insp.hud.main.follow_selected(), "Follow\nThe camera follows this colonist. Key F.", "", "follow", 14))

func _needs(a: Dictionary) -> void:
	var s = _sim()
	var body: VBoxContainer = insp.body()
	var id: int = a["id"]
	var suit_max: float = float(s.bal["suit_air_seconds"])
	var rows := [["Health", "health", false], ["Fed", "hunger", true], ["Water", "thirst", true], ["Rested", "fatigue", true], ["Morale", "morale", false]]
	for r in rows:
		var key: String = r[1]
		var inv: bool = r[2]
		var v: float = float(a.get(key, 0.0))
		var shown: float = 100.0 - v if inv else v
		var row: HBoxContainer = Kit.bar_row(r[0], shown / 100.0, "%d" % int(shown), P.level(shown, 50.0, 25.0), 70.0)
		body.add_child(row)
		insp.bind(func():
			var aa: Dictionary = s.state["agents"].get(id, {})
			if aa.is_empty():
				return
			var vv: float = float(aa.get(key, 0.0))
			var sh: float = 100.0 - vv if inv else vv
			row.get_child(1).value = sh / 100.0
			row.get_child(1).color = P.level(sh, 50.0, 25.0)
			(row.get_child(2) as Label).text = "%d" % int(sh))
	var srow: HBoxContainer = Kit.bar_row("Suit air", float(a.get("suit", 0.0)) / suit_max, "%ds" % int(a.get("suit", 0.0)), P.CYAN, 70.0)
	body.add_child(srow)
	insp.bind(func():
		var aa: Dictionary = s.state["agents"].get(id, {})
		if aa.is_empty():
			return
		srow.get_child(1).value = float(aa.get("suit", 0.0)) / suit_max
		srow.get_child(1).color = P.CYAN if float(aa.get("suit", 0.0)) > suit_max * 0.3 else P.RED
		(srow.get_child(2) as Label).text = "%ds" % int(aa.get("suit", 0.0)))
	var g: GridContainer = _grid()
	body.add_child(g)
	_fact(g, "Doing", func(): return String(s.state["agents"].get(id, {}).get("goal", "")), P.CYAN)
	_fact(g, "Air here", func():
		var aa: Dictionary = s.state["agents"].get(id, {})
		if aa.is_empty():
			return "-"
		return "yes" if s.agents.breathable(aa) else "NO, on suit air")
	_fact(g, "Carrying", func():
		var aa: Dictionary = s.state["agents"].get(id, {})
		if aa.is_empty():
			return "-"
		var cargo: Dictionary = s.inv.get_inv(aa["inv"]).get("items", {})
		return insp.hud.cost_text(cargo) if not cargo.is_empty() else "nothing")
	_fact(g, "Bed", func(): return String(s.state["buildings"].get(s.state["agents"].get(id, {}).get("bed", -1), {}).get("name", "none")))
	_fact(g, "Work speed", func():
		var aa: Dictionary = s.state["agents"].get(id, {})
		return "%d%%" % int(s.agents.productivity(aa) * 100.0) if not aa.is_empty() else "-")

func _nutrition(a: Dictionary) -> void:
	var s = _sim()
	var d = _d()
	var body: VBoxContainer = insp.body()
	var id: int = a["id"]
	var target: float = float(s.bal.get("nutrition", {}).get("target", 70.0)) / 100.0
	var sec: VBoxContainer = _section("Nutrition  ·  line = target %d" % int(target * 100.0), "nutrition", P.CATEGORY["food"])
	for n in ["protein", "carbs", "fat", "vitamins"]:
		var key: String = n
		var v: float = float(a.get("nutrition", {}).get(n, 0.0))
		var row: HBoxContainer = Kit.bar_row(P.NUTRIENT_NAME[n], v / 100.0, "%d" % int(v), P.NUTRIENT[n], 70.0, target)
		sec.add_child(row)
		insp.bind(func():
			var aa: Dictionary = s.state["agents"].get(id, {})
			if aa.is_empty():
				return
			var vv: float = float(aa.get("nutrition", {}).get(key, 0.0))
			row.get_child(1).value = vv / 100.0
			row.get_child(1).color = P.RED if vv < 25.0 else P.NUTRIENT[key]
			(row.get_child(2) as Label).text = "%d" % int(vv))
	var score_l: Label = Kit.label("", "BodyStrong", 14)
	sec.add_child(score_l)
	insp.bind(func():
		var aa: Dictionary = s.state["agents"].get(id, {})
		score_l.text = "Score %d of 100" % int(d.agent_nutrition_score(aa)) if not aa.is_empty() else "")
	var diet: Array = a.get("diet", [])
	var sec2: VBoxContainer = _section("Last meals, newest first", "history")
	var row2: HBoxContainer = Kit.hbox(6)
	sec2.add_child(row2)
	if diet.is_empty():
		row2.add_child(Kit.label("No meals yet.", "SmallLabel", 12, P.TEXT_3))
	var distinct := {}
	for i in range(diet.size() - 1, -1, -1):
		var dish: String = String(diet[i])
		distinct[dish] = true
		var ic: TextureRect = Kit.icon(Icons.item(dish), 26, d.item_color(dish))
		ic.tooltip_text = d.item_name(dish)
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		var cell: PanelContainer = Kit.panel("WellPanel", false)
		cell.add_child(ic)
		cell.tooltip_text = d.item_name(dish)
		row2.add_child(cell)
	var good: int = int(s.bal.get("nutrition", {}).get("variety_good", 4))
	if diet.is_empty():
		return
	sec2.add_child(Kit.label("%s in the last %s. %d or more lift morale." % [Kit.plural(distinct.size(), "different dish", "different dishes"), Kit.plural(diet.size(), "meal"), good], "SmallLabel", 12, P.GREEN if distinct.size() >= good else P.TEXT_2))
