extends RefCounted
## Content of the inspector tabs. Builds controls into the inspector (ui/hud/inspector.gd)
## and registers bindings for the numbers that change every refresh.

const P = preload("res://ui/theme/palette.gd")
const Storage = preload("res://ui/storage.gd")
const Kit = preload("res://ui/kit.gd")
const Icons = preload("res://ui/theme/icons.gd")
const BuildCard = preload("res://ui/widgets/build_card.gd")
const LineChart = preload("res://ui/charts/line_chart.gd")
const FocusPicker = preload("res://ui/widgets/focus_picker.gd")

const BLOCK_TEXT := {
	"": "Working.", "no_power": "Stopped: no power.", "no_water": "Stopped: no water on its network.",
	"no_input": "Waiting: no input material has been delivered.", "output_blocked": "Output blocked: the output buffer is full.",
	"disabled": "Switched off by you.", "storage_full": "Idle: storage is full.", "no_reservoir": "No reservoir on its network.",
	"deposit_empty": "The deposit under it is empty.", "unreachable": "Nobody can reach it within suit range.",
	"suit_range": "Too far from an airlock with air. Nobody can work here and walk back on one suit. Build an airlock nearer.",
	"occupied": "Waiting: people are still inside.", "no_spares": "No spare parts for the repair.", "broken": "Broken.", "not_ready": "Not finished.",
	"no_staff": "Waiting for a worker.", "no_recipe": "No recipe chosen.", "no_menu": "No dish can be cooked: check the menu and the crops.",
	"no_atmosphere": "Stopped: this planet has no air, and this structure needs air to work.",
}

const SHORT := {
	"no_power": "NO POWER", "no_water": "NO WATER", "no_input": "NO INPUT", "output_blocked": "OUTPUT FULL",
	"storage_full": "STORAGE FULL", "no_reservoir": "NO RESERVOIR", "deposit_empty": "DEPOSIT EMPTY",
	"unreachable": "OUT OF REACH", "suit_range": "TOO FAR", "occupied": "WAITING", "no_spares": "NO SPARES",
	"no_staff": "NO WORKER", "no_recipe": "NO RECIPE", "no_menu": "NO DISH",
	"level_low": "NEEDS LEVEL 2", "deposit_locked": "LOCKED DEPOSIT", "no_atmosphere": "NO AIR ON PLANET",
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
	# Version 3: wear known, fault, breach, lab focus, the cargo choice change the layout too.
	var wv: Dictionary = _d().wear_of(b)
	var v3: String = "%s:%s:%s:%s:%s" % [wv.get("known", false), wv.get("broken", false), _d().breach_of(b).is_empty(),
		b.get("focus", _d().lab_info(int(b["id"])).get("focus", "") if bool(_def(b).get("research_lab", false)) else ""), insp.hud.get("cargo_choice")]
	return "b:%d:%s:%s:%s:%s:%s:%s:%s:%d:%d:%s:%s:%s:%s:%s:%s:%s" % [b["id"], b["state"], b["def"], tab, b.get("demolish", false), b.get("enabled", true),
		_sim().prod.has_batch(b), b.get("door_open", true), int(b.get("level", 1)), int(b.get("size", 1)), up.get("state", ""), trays,
		str(b.get("menu_off", {}).keys()), b.get("recipe_sel", ""), b.get("crop", ""), str(_sim().state.get("ship", {}).get("stage", -1)), v3]

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
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long text wraps; the window never widens (fix 7)
	g.add_child(l)
	var v: Label = Kit.num(String(getter.call()), 13, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size.x = 140.0
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
	if blk2.begins_with("materials:"):
		return ["WAITING: " + _d().item_name(blk2.substr(10)).to_upper(), P.AMBER]
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
	var stb: Control = Kit.badge(st[0], st[1])
	# The OUT OF REACH / TOO FAR badge says why on hover (the nearest airlock with air, walk, reach).
	if String(b.get("block", "")) in ["unreachable", "suit_range"]:
		var rr: Dictionary = load("res://ui/why.gd").reach(insp.hud, b)
		stb.tooltip_text = "%s\n%s\nFix: %s" % [String(st[0]), " ".join(rr.why), " ".join(rr.fix)]
		stb.mouse_filter = Control.MOUSE_FILTER_PASS
	insp.add_badge(stb)
	if d.can_level(String(b["def"])):
		insp.add_badge(Kit.badge("LEVEL %d" % d.level_of(b), P.GOLD if d.level_of(b) >= 5 else P.VIOLET))
	if d.size_word(String(b["def"]), d.size_of(b)) != "":
		insp.add_badge(Kit.badge("SIZE %s" % d.size_word(String(b["def"]), d.size_of(b)), P.CYAN))
	# Version 5: the super dome is built in stages (SIM leisure.dome_stage); the stage shows while it is built.
	var ds: Dictionary = _dome_stage(b)
	if not ds.is_empty() and String(ds.get("id", "")) != "done":
		var sb: Control = Kit.badge("STAGE %d OF %d" % [int(ds["index"]) + 1, int(ds["count"])], P.GOLD)
		sb.tooltip_text = "Build stage
%s: %d %% done. The dome is built in %d stages; each one shows in the world." % [String(ds["name"]), int(float(ds.get("progress", 0.0)) * 100.0), int(ds["count"])]
		sb.mouse_filter = Control.MOUSE_FILTER_PASS
		insp.add_badge(sb)
	if String(b["def"]) == "meridian":
		insp.add_tabs([])
		_ship(b)
		_footer_building(b, base)
		return
	# Paul, 2026-09-28: what every structure holds, and whether it is full. A storehouse, cold storage
	# or the lander opens on its Storage view; other holders show Storage on the Overview tab.
	var store_first: bool = _is_store(b) and b["state"] == "active"
	var tabs: Array = [["storage", "Storage"], ["overview", "Overview"]] if store_first else [["overview", "Overview"]]
	if b["state"] == "active" and Storage.summary(s, b)["full"]:
		insp.add_badge(Kit.badge("FULL", P.RED))
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
	if _is_depot(b) and b["state"] == "active":
		tabs.append(["vehicles", "Vehicles"])
	if _is_pad(b) and b["state"] == "active":
		tabs.append(["satellite", "Satellite"])
	if _has_venues(b) and b["state"] == "active":
		tabs.append(["venues", "Venues"])
	if _can_party(b) and b["state"] == "active":
		tabs.append(["party", "Party"])
	tabs.append(["stats", "Stats"])
	insp.add_tabs(tabs)
	match insp.tab:
		"production": _production(b, def)
		"crops": _crops(b, def)
		"menu": _menu(b, def)
		"upgrade": _upgrade(b, def)
		"staff": _staff(b, def)
		"stats": _stats(b, def)
		"vehicles": _depot(b)
		"satellite": _pad(b)
		"venues": _venues(b)
		"party": _party(b)
		"storage": _storage(b)
		_: _overview(b, def)
	if insp.tab != "storage" and not store_first and b["state"] == "active" and insp.tab in ["", "overview"]:
		_storage(b)
	_footer_building(b, base)

# ---------------------------------------------------------------- storage (Paul, 2026-09-28)
func _is_store(b: Dictionary) -> bool:
	for h in Storage.holders(_sim(), b):
		if String(h["role"]) == "store":
			return true
	return false

## The Storage section: per holder (input, stored, output, supplies) a capacity bar with used /
## capacity and %, coloured by fill (cyan, amber from 80 %, red from 95 %), a FULL badge, and one
## line per item: tier stripe, icon, name, amount, reserved units, the time to the next spoiled
## unit (not in cold storage). Updates in place; the item lines are made again when they change.
func _storage(b: Dictionary) -> void:
	var s = _sim()
	var hs: Array = Storage.holders(s, b)
	if hs.is_empty():
		return
	var cold: bool = Storage.is_cold(s, b)
	var sec: VBoxContainer = _section("Storage", "inventory")
	sec.name = "StorageSection"
	var bid: int = int(b["id"])
	for h in hs:
		_storage_block(sec, int(h["inv"]), String(h["title"]), cold, bid)
	if cold:
		sec.add_child(Kit.label("Cold storage: food here does not spoil.", "SmallLabel", 12, P.CYAN))
	elif String(hs[0]["role"]) == "store":
		sec.add_child(Kit.label("Reserved units are kept for construction, orders or a carrier on the way.", "SmallLabel", 12, P.TEXT_3))

func _storage_block(sec: VBoxContainer, inv_id: int, title: String, cold: bool, bid: int = -1) -> void:
	var s = _sim()
	var d = _d()
	var box: VBoxContainer = Kit.vbox(3)
	box.set_meta("inv", inv_id)
	sec.add_child(box)
	var head: HBoxContainer = Kit.hbox(8)
	box.add_child(head)
	var tl: Label = Kit.head(title, P.TEXT_2, 11)
	head.add_child(tl)
	var num: Label = Kit.num("", 13, P.TEXT)
	num.name = "Used"
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(num)
	var full: Control = Kit.badge("FULL", P.RED)
	full.name = "Full"
	head.add_child(full)
	var bar = Kit.bar(0.0, P.CYAN, 7.0)
	box.add_child(bar)
	var incoming: Label = Kit.label("", "SmallLabel", 12, P.TEXT_3)
	box.add_child(incoming)
	var rows: VBoxContainer = Kit.vbox(1)
	rows.name = "Items"
	box.add_child(rows)
	var sig := [""]
	var upd := func():
		if not s.inv.exists(inv_id):
			return
		var ct: Dictionary = Storage.contents(s, s.state["buildings"].get(bid, {})) if bid != -1 else {}
		var inf: Dictionary = Storage.info(s, inv_id, cold, ct.get("spoil", {}))
		var col: Color = Storage.level_color(int(inf["level"]))
		num.text = "%d / %d  (%d%%)" % [int(inf["used"]), int(inf["cap"]), int(roundf(float(inf["frac"]) * 100.0))]
		num.add_theme_color_override("font_color", col if int(inf["level"]) > 0 else P.TEXT)
		full.visible = bool(inf["full"])
		bar.value = clampf(float(inf["frac"]), 0.0, 1.0)
		bar.color = col
		incoming.text = ("%d more on the way in." % int(inf["incoming"])) if int(inf["incoming"]) > 0 else ""
		incoming.visible = incoming.text != ""
		var sg := ""
		for it in inf["items"]:
			sg += "%s:%d:%d:%d|" % [it["id"], int(it["n"]), int(it["reserved"]), int(float(it["spoil_s"]) / 30.0)]
		if sg == sig[0]:
			return
		sig[0] = sg
		Kit.clear(rows)
		if (inf["items"] as Array).is_empty():
			rows.add_child(Kit.label("Empty.", "SmallLabel", 12, P.TEXT_3))
			return
		for it in inf["items"]:
			rows.add_child(_storage_row(it))
	upd.call()
	insp.bind(upd)

func _storage_row(it: Dictionary) -> Control:
	var d = _d()
	var id: String = String(it["id"])
	var h: HBoxContainer = Kit.hbox(6)
	h.set_meta("item", id)
	var tr: int = d.item_tier(id)
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(3, 16)
	stripe.color = load("res://ui/data.gd").TIER_COLOR.get(tr, Color(0, 0, 0, 0)) if tr > 0 else Color(0, 0, 0, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(stripe)
	h.add_child(Kit.icon(Icons.item(id), 16, d.item_color(id)))
	var nm: Label = Kit.label(d.item_name(id), "", 13, P.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(nm)
	if int(it["reserved"]) > 0:
		h.add_child(Kit.label("%d reserved" % int(it["reserved"]), "SmallLabel", 12, P.AMBER))
	if float(it.get("spoil_s", -1.0)) >= 0.0:
		var sp: float = float(it["spoil_s"])
		h.add_child(Kit.label("spoils in %s" % Kit.clock(sp), "SmallLabel", 12, P.AMBER if sp < 120.0 else P.TEXT_3))
	var n: Label = Kit.num("%d" % int(it["n"]), 13, P.TEXT)
	n.custom_minimum_size.x = 34
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(n)
	h.tooltip_text = "%s%s\n%d here: %d free, %d reserved.%s" % [d.item_name(id), (" (%s)" % d.tier_name(tr).to_lower()) if tr > 0 else "", int(it["n"]), int(it["free"]), int(it["reserved"]),
		(" The next unit spoils in %s (a unit at a time; cold storage stops it)." % Kit.clock(float(it["spoil_s"]))) if float(it.get("spoil_s", -1.0)) >= 0.0 else ""]
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h

# ---------------------------------------------------------------- launch pad: survey satellite (SIM milestone 7)
func _is_pad(b: Dictionary) -> bool:
	var s = _sim()
	return "vehicles" in s and s.vehicles != null and s.vehicles.has_method("is_pad") and bool(s.vehicles.is_pad(b))

## The satellites in orbit (bands mapped, the uplink), the one being built (parts, then assembly;
## Cancel) and the Build button with its cost and research lock. Command: build_satellite {pad}.
func _pad(b: Dictionary) -> void:
	var s = _sim()
	var d = _d()
	var id: int = b["id"]
	var v4 = insp.hud.v4
	var sc: Dictionary = s.content.get("vehicles", {}).get("satellite", {})
	var orbit: VBoxContainer = _section("In orbit", "satellite")
	var ol: VBoxContainer = Kit.vbox(4)
	orbit.add_child(ol)
	var upd_orbit := func():
		Kit.clear(ol)
		var sats: Array = v4.sats()
		if sats.is_empty():
			ol.add_child(Kit.wrap("No satellite yet. A survey satellite maps one band of the planet every minute: the points of interest in it are found.", 13, P.TEXT_2))
			return
		for st in sats:
			var line: String = "%s: %d of %d bands mapped." % [String(st["name"]), int(st["bands_done"]), int(st["bands"])]
			if int(st["bands_done"]) >= int(st["bands"]):
				line += " Done."
			elif bool(st["uplink"]):
				line += " Next band in %d s." % int(ceilf(float(st["next_s"])))
			ol.add_child(Kit.wrap(line, 13, P.TEXT))
			if not bool(st["uplink"]) and int(st["bands_done"]) < int(st["bands"]):
				ol.add_child(Kit.wrap("No uplink: it maps only while a comms tower has power.", 13, P.AMBER))
	upd_orbit.call()
	insp.bind(upd_orbit)
	# The order in progress (the same record as a depot's vehicle order).
	var ob: VBoxContainer = _section("Building", "build")
	var head: Label = Kit.label("", "", 14, P.TEXT)
	ob.add_child(head)
	var bar = Kit.bar(0.0, P.CYAN, 6.0)
	ob.add_child(bar)
	var why: Label = Kit.wrap("", 13, P.AMBER)
	why.custom_minimum_size.x = 300
	ob.add_child(why)
	ob.add_child(Kit.button("Cancel the build", func(): insp.hud.confirm("Cancel the satellite?", ["The parts already delivered go back to storage."], func(): v4.cancel_vehicle(id), "Cancel build", true),
		"Cancel\nStops the build. Delivered parts go back to storage.", "DangerButton", "close", 14))
	var upd := func():
		var bb: Dictionary = s.state["buildings"].get(id, {})
		var vo = bb.get("vorder", null)
		var has: bool = typeof(vo) == TYPE_DICTIONARY and not (vo as Dictionary).is_empty()
		ob.visible = has
		if not has:
			return
		var st: String = String(vo.get("state", ""))
		head.text = "Survey satellite: %s" % ("carriers bring the parts" if st == "deliver" else "technicians assemble it, then it launches")
		bar.value = clampf(float(vo.get("progress", 0.0)) / maxf(1.0, float(vo.get("work_total", 1.0))), 0.0, 1.0) if st == "work" else 0.0
		var blk: String = String(vo.get("block", ""))
		why.text = ("Waiting for %s: none free in storage." % d.item_name(blk.substr(10)).to_lower()) if blk.begins_with("materials:") else (v4.refusal_text(blk) if blk != "" else "")
		why.visible = why.text != ""
	upd.call()
	insp.bind(upd)
	var bs: VBoxContainer = _section("Build a survey satellite", "satellite")
	var tech: String = String(sc.get("research", ""))
	var locked: bool = tech != "" and not d.tech_done(tech)
	var btn: Button = Kit.button("Build satellite", func():
		var r: Dictionary = v4._submit("build_satellite", {"pad": id})
		var ok: bool = bool(r.get("ok", false)) or String(r.get("code", "")) == "submitted"
		var code: String = String(r.get("code", ""))
		insp.hud.toast("Survey satellite: %s" % ("ordered. Carriers bring the parts." if ok else v4.refusal_text("depot_busy" if code == "busy" else code)), "info" if ok else "warn"),
		"Build a survey satellite\nCarriers bring the parts; technicians assemble it on the pad; then it launches.", "PrimaryButton" if not locked else "", "satellite", 14)
	btn.disabled = locked
	bs.add_child(btn)
	bs.add_child(Kit.wrap(String(sc.get("desc", "")), 12, P.TEXT_2))
	if locked:
		bs.add_child(Kit.wrap("Needs research: %s." % d.tech_name(tech), 12, P.AMBER))
	bs.add_child(_cost_chips(sc.get("cost", {})))

# ---------------------------------------------------------------- rover depot (version 4, SIM milestone 3)
func _is_depot(b: Dictionary) -> bool:
	var s = _sim()
	return "vehicles" in s and s.vehicles != null and s.vehicles.has_method("is_depot") and bool(s.vehicles.is_depot(b))

## The depot's bays (who stands in each), the vehicle being built (parts delivered, then assembly, with
## progress and what it waits for; Cancel), and one Build button per kind with its cost, seats, cargo and
## research lock. Commands: build_vehicle {depot, kind}, cancel_vehicle {depot}.
func _depot(b: Dictionary) -> void:
	var s = _sim()
	var d = _d()
	var id: int = b["id"]
	var v4 = insp.hud.v4
	var sec: VBoxContainer = _section("Bays", "rover")
	var parked := {}
	var bays: Array = s.vehicles.bays(b)
	for v in v4.vehicles():
		if int(v.get("depot", -1)) == id and int(v.get("bay", -1)) >= 0:
			parked[int(v["bay"])] = v
		else:
			for bay0 in bays:   # standing on a bay without the bay number set (e.g. just spawned): by position
				if String(v.get("state", "")) == "parked" and (v["pos"] as Vector2).distance_to(bay0["pos"]) < 4.0:
					parked[int(bay0["i"])] = v
	for bay in bays:
		var i: int = int(bay["i"])
		var who: String = "free"
		if parked.has(i):
			var pv: Dictionary = parked[i]
			who = "%s (%s, %d%% %s)" % [String(pv["name"]), v4.vehicle_name(String(pv["kind"])).to_lower(), int(100.0 * float(pv["fuel"] if String(pv["kind"]) == "hopper" else pv["charge"])), "fuel" if String(pv["kind"]) == "hopper" else "charge"]
		sec.add_child(Kit.label("Bay %d, %s: %s" % [i + 1, String(bay["kind"]), who], "", 13, P.TEXT if parked.has(i) else P.TEXT_2))
	sec.add_child(Kit.wrap("Parked here, a vehicle charges (1 per second with power), takes rocket fuel from the depot store and spare parts for repairs.", 12, P.TEXT_2))
	# The order in progress.
	var ob: VBoxContainer = _section("Building", "build")
	var head: Label = Kit.label("", "", 14, P.TEXT)
	ob.add_child(head)
	var bar = Kit.bar(0.0, P.CYAN, 6.0)
	ob.add_child(bar)
	var why: Label = Kit.wrap("", 13, P.AMBER)
	why.custom_minimum_size.x = 300
	ob.add_child(why)
	var cancel: Button = Kit.button("Cancel the build", func(): insp.hud.confirm("Cancel the vehicle?", ["The parts already delivered go back to storage."], func(): v4.cancel_vehicle(id), "Cancel build", true),
		"Cancel\nStops the build. Delivered parts go back to storage.", "DangerButton", "close", 14)
	ob.add_child(cancel)
	var upd := func():
		var bb: Dictionary = s.state["buildings"].get(id, {})
		var vo = bb.get("vorder", null)
		var has: bool = typeof(vo) == TYPE_DICTIONARY and not (vo as Dictionary).is_empty()
		ob.visible = has
		if not has:
			return
		var st: String = String(vo.get("state", ""))
		head.text = "%s: %s" % [v4.vehicle_name(String(vo.get("kind", ""))), "carriers bring the parts" if st == "deliver" else "technicians assemble it"]
		bar.value = clampf(float(vo.get("progress", 0.0)) / maxf(1.0, float(vo.get("work_total", 1.0))), 0.0, 1.0) if st == "work" else 0.0
		var blk: String = String(vo.get("block", ""))
		why.text = ("Waiting for %s: none free in storage." % d.item_name(blk.substr(10)).to_lower()) if blk.begins_with("materials:") else (v4.refusal_text(blk) if blk != "" else "")
		why.visible = why.text != ""
	upd.call()
	insp.bind(upd)
	# One Build button per kind.
	var bs: VBoxContainer = _section("Build a vehicle", "rover")
	var kinds: Dictionary = v4.kinds()
	for k in kinds:
		var kd: Dictionary = kinds[k]
		var kk: String = String(k)
		var card: PanelContainer = Kit.panel("CardPanel", false)
		var cv: VBoxContainer = Kit.vbox(4)
		card.add_child(cv)
		var top: HBoxContainer = Kit.hbox(8)
		cv.add_child(top)
		top.add_child(Kit.icon("rover", 18, P.CYAN))
		var nm: Label = Kit.label(String(kd.get("name", kk)), "BodyStrong", 14, P.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		var tech: String = String(kd.get("research", ""))
		var locked: bool = tech != "" and not d.tech_done(tech)
		var btn: Button = Kit.button("Build", func():
			var r: Dictionary = v4.build_vehicle(id, kk)
			var ok: bool = bool(r.get("ok", false)) or String(r.get("code", "")) == "submitted"
			var code: String = String(r.get("code", ""))
			insp.hud.toast("%s: %s" % [String(kd.get("name", kk)), "ordered. Carriers bring the parts." if ok else v4.refusal_text("depot_busy" if code == "busy" else code)], "info" if ok else "warn"),
			"Build a %s\nCarriers bring the parts; technicians assemble it outside the depot. It needs a free %s bay." % [String(kd.get("name", kk)).to_lower(), String(kd.get("bay", "small"))], "PrimaryButton" if not locked else "", "build", 14)
		btn.disabled = locked
		top.add_child(btn)
		var facts: String = "%d seats, cargo %d, %s. %s bay." % [int(kd.get("seats", 0)), int(kd.get("cargo", 0)), "pressurised cabin" if bool(kd.get("pressurised", false)) else "open (crew in suits)", String(kd.get("bay", "small")).capitalize()]
		cv.add_child(Kit.wrap(facts, 12, P.TEXT_2))
		if locked:
			cv.add_child(Kit.wrap("Needs research: %s." % d.tech_name(tech), 12, P.AMBER))
		cv.add_child(_cost_chips(kd.get("cost", {})))
		bs.add_child(card)

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
			# The reason with the numbers (why.gd reach): the nearest airlock with air, its walk, the reach.
			var rr: Dictionary = load("res://ui/why.gd").reach(insp.hud, b)
			sec.add_child(Kit.wrap(String(rr.short) + "." if String(rr.short) != "" else BLOCK_TEXT[blk], 13, P.RED))
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
			var rr2: Dictionary = load("res://ui/why.gd").reach(insp.hud, b)
			sec2.add_child(Kit.wrap(String(rr2.short) + "." if String(rr2.short) != "" else BLOCK_TEXT["suit_range"], 13, P.RED))
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
		_wear_breach(b, def)
		_turret(b, def)
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

## Version 3 (V3_DESIGN §4): wear and the time to failure, the fault of a broken machine, a
## hull breach. Numbers update in place.
func _wear_breach(b: Dictionary, def: Dictionary) -> void:
	var d = _d()
	var s = _sim()
	var id: int = b["id"]
	var body: VBoxContainer = insp.body()
	var w0: Dictionary = d.wear_of(b)
	var fault: String = String(w0.get("fault", b.get("fault", "")))
	if String(b["state"]) == "broken" and fault != "" and bool(w0.get("broken", true)):
		var item: String = String(w0.get("item", d.FAULT_ITEM.get(fault, "spare_parts")))
		if item == "":
			item = String(d.FAULT_ITEM.get(fault, "spare_parts"))
		var fl: Label = Kit.wrap("Fault: %s. A technician repairs it with 1 %s." % [String(d.FAULT_NAME.get(fault, fault)).get_slice(" (", 0).to_lower(), d.item_name(item).to_lower()], 13, P.RED)
		body.add_child(fl)
	var br: Dictionary = d.breach_of(b)
	if not br.is_empty():
		var bl: HBoxContainer = Kit.hbox(6)
		bl.add_child(Kit.icon("breach", 16, P.RED))
		bl.add_child(Kit.wrap("Hull breach: air leaks out. A technician repairs it with 1 hull plate (or 2 steel).", 13, P.RED))
		body.add_child(bl)
	if not bool(w0.get("known", false)):
		return
	var row: HBoxContainer = Kit.bar_row("Wear", 0.0, "", P.AMBER, 70.0)
	body.add_child(row)
	var eta: Label = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	eta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # never widens the window (critic round 15, fix 7)
	body.add_child(eta)
	insp.bind(func():
		var bb: Dictionary = s.state["buildings"].get(id, {})
		if bb.is_empty():
			return
		var ww: Dictionary = d.wear_of(bb)
		var wear: float = float(ww.get("wear", 0.0))
		var fa: float = maxf(1.0, float(ww.get("fail_at", 100.0)))
		var bar = row.get_child(1)
		bar.value = clampf(wear / 100.0, 0.0, 1.0)
		bar.target = fa / 100.0
		bar.color = P.RED if wear / fa >= 0.9 else (P.AMBER if wear / fa >= 0.75 else P.GREEN)
		(row.get_child(2) as Label).text = "%d%%" % int(wear)
		var e: float = float(ww.get("eta_s", -1.0))
		var ft: String = String(ww.get("fault", ""))
		if e >= 0.0:
			eta.text = "Fails at %d%% wear, in about %s at this rate%s. Maintain it before then." % [int(fa), Kit.clock(e), (" (%s)" % String(d.FAULT_NAME.get(ft, ft)).to_lower()) if ft != "" else ""]
			eta.add_theme_color_override("font_color", P.AMBER)
		else:
			eta.text = "Fails at %d%% wear. Not near failure now." % int(fa)
			eta.add_theme_color_override("font_color", P.TEXT_2))

## Version 3: a Meteor Defense turret: charge, shots and the area it covers.
func _turret(b: Dictionary, def: Dictionary) -> void:
	var def_id: String = String(b["def"])
	if not (bool(def.get("turret", false)) or def_id.contains("turret") or def.has("turret_range")):
		return
	var s = _sim()
	var id: int = b["id"]
	var sec: VBoxContainer = _section("Meteor defense", "turret", P.CYAN)
	var cover: float = float(def.get("turret_range", def.get("intercept_range", def.get("range", 70.0))))
	if _d().has_helper("hazards", "turret_range"):
		cover = float(s.hazards.turret_range(b))
	var cap: float = float(def.get("charge_cap", def.get("charge_max", 0.0)))
	var per_shot: float = float(def.get("shot_cost", def.get("charge_per_shot", 0.0)))
	var per_day: float = float(def.get("charge_per_day", 0.0))
	var g: GridContainer = _grid()
	sec.add_child(g)
	_fact(g, "Covers", func():
		var n := 0
		var bb: Dictionary = s.state["buildings"].get(id, {})
		if bb.is_empty():
			return "-"
		for oid in s.state["buildings"]:
			var o: Dictionary = s.state["buildings"][oid]
			if oid != id and String(o.get("kind", "")) != "link" and (o["pos"] as Vector2).distance_to(bb["pos"]) <= cover:
				n += 1
		return "%d m radius, %s" % [int(cover), Kit.plural(n, "structure")])
	_fact(g, "Charge", func():
		var c: float = float(s.state["buildings"].get(id, {}).get("charge", -1.0))
		if c < 0.0:
			return "-"
		return ("%s / %s" % [Kit.fmt(c), Kit.fmt(cap)]) if cap > 0.0 else Kit.fmt(c), P.CYAN)
	if per_day > 0.0:
		_fact(g, "Recharge", func(): return "%s per day (needs power)" % Kit.fmt(per_day))
	if per_shot > 0.0:
		_fact(g, "Shots ready", func():
			var c: float = float(s.state["buildings"].get(id, {}).get("charge", 0.0))
			return "%d" % int(floor(c / per_shot)))
	var st_i: Dictionary = s.state["buildings"].get(id, {}).get("stats", {})
	if st_i.has("intercepts"):
		_fact(g, "Meteors stopped", func(): return "%d" % int(s.state["buildings"].get(id, {}).get("stats", {}).get("intercepts", 0)), P.GREEN)
	sec.add_child(Kit.label("It stops a meteor inside its radius while it has charge for a shot.", "SmallLabel", 12, P.TEXT_2))

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
		_lab_facts(sec, b)
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
			# A recipe that needs research is shown locked, with the tech in the tooltip.
			var lock_tech: String = recipe_tech(rr)
			var locked: bool = lock_tech != "" and not d.tech_done(lock_tech)
			var tip: String = "Make %s from %s." % [d.item_name(out).to_lower(), insp.hud.cost_text(r.get("inputs", {}))]
			if locked:
				tip = "Locked. Research %s first." % d.tech_name(lock_tech)
			# Version 4: a recipe with min_level needs the structure at that level (SIM code level_low).
			var min_lv: int = int(r.get("min_level", 1))
			var low: bool = min_lv > 1 and d.level_of(b) < min_lv
			if low and not locked:
				tip = "Needs level %d. Upgrade this structure first (Upgrade tab).\n%s" % [min_lv, tip]
			var bt: Button = Kit.button(String(r.get("name", rid)) + (("  (L%d)" % min_lv) if min_lv > 1 else ""), func(): insp.hud.main.submit("set_recipe", {"id": id, "recipe": rr}), tip, "ChipButton", "lock" if locked else (Icons.item(out) if out != "" else ""), 14)
			bt.toggle_mode = true
			bt.set_pressed_no_signal(rr == cur)
			bt.custom_minimum_size.y = 28
			bt.disabled = not can or locked or low
			row.add_child(bt)
		if not can:
			sec2.add_child(Kit.label("Recipe choice is not available yet.", "SmallLabel", 12, P.TEXT_3))
	if not rec.is_empty() and not bool(rec.get("menu", false)):
		var sec3: VBoxContainer = _section("Recipe", "build")
		var line: HBoxContainer = Kit.hbox(8)
		sec3.add_child(line)
		if not rec.get("inputs", {}).is_empty():
			line.add_child(_items_row(rec.get("inputs", {})))
		if int(rec.get("water_net", 0)) > 0:
			line.add_child(Kit.chip("water", "%d" % int(rec["water_net"]), Color("3AA0D8"), "Water from the network, %d per batch." % int(rec["water_net"]), true, 16))
		if rec.get("inputs", {}).is_empty() and int(rec.get("water_net", 0)) <= 0:
			line.add_child(Kit.label("from the ground", "SmallLabel", 12, P.TEXT_2))
		line.add_child(Kit.icon("arrow_right", 16, P.CYAN))
		line.add_child(_items_row(rec.get("outputs", {})))
		if bool(def.get("automatic", false)) or String(rec.get("role", "")) == "":
			# Automatic machines (research assembler, harvesters): no worker, a time per batch.
			var secs: float = float(rec.get("time", rec.get("seconds", rec.get("work", 0))))
			sec3.add_child(Kit.label("Automatic: no worker.%s%s" % [(" %s s per batch." % Kit.fmt(secs)) if secs > 0.0 else "",
				(" Uses %s P while it works." % Kit.fmt(float(def.get("power", 0.0)))) if float(def.get("power", 0.0)) > 0.0 else ""], "SmallLabel", 12, P.TEXT_2))
		else:
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
	_storage(b)

## The tech that unlocks recipe `rid` ("" = none): content research unlocks.recipes.
func recipe_tech(rid: String) -> String:
	var d = _d()
	for t in d.techs():
		if (d.techs()[t].get("unlocks", {}).get("recipes", []) as Array).has(rid):
			return String(t)
	return ""

## A research lab (version 3, V3_DESIGN §5): its rate without and with packs, the packs it
## holds, and its focus branch.
func _lab_facts(sec: VBoxContainer, b: Dictionary) -> void:
	var d = _d()
	var id: int = b["id"]
	var g: GridContainer = _grid()
	sec.add_child(g)
	var li: Dictionary = d.lab_info(id)
	_fact(g, "Output now", func():
		var x: Dictionary = d.lab_info(id)
		var t: String = ("%s RP/day, " % Kit.fmt(float(x["rate"]))) if x.has("rate") else ""
		return "%sx%s%s" % [t, Kit.fmt(float(x.get("mult_boosted", x.get("mult", 1.0)))), "  BOOSTED" if bool(x.get("boosted", false)) else ""], P.VIOLET)
	_fact(g, "Without packs", func(): return "x%s" % Kit.fmt(float(d.lab_info(id).get("mult", 1.0))))
	if bool(li.get("known", false)):
		_fact(g, "Works on the project", func(): return "yes" if bool(d.lab_info(id).get("can_work", true)) else "no: it needs packs")
	_fact(g, "Scientists here", func(): return "%d" % int(d.lab_info(id).get("scientists", 0)))
	if d.packs_available() or not (li.get("packs", {}) as Dictionary).is_empty():
		_fact(g, "Packs held", func():
			var pk: Dictionary = d.lab_info(id).get("packs", {})
			if pk.is_empty():
				return "none"
			var parts: Array = []
			for it in pk:
				parts.append("%d %s" % [int(pk[it]), d.item_name(String(it)).to_lower()])
			return ", ".join(parts))
		sec.add_child(Kit.label("A lab that holds the pack type of its project works x%s." % Kit.fmt(float(li.get("boost", 2.0))), "SmallLabel", 12, P.TEXT_2))
	sec.add_child(FocusPicker.make(insp.hud, id))

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
			tg.tooltip_text = "On the menu\nOn: the cook may make this dish. Off: never." if can else "On the menu\nThis kitchen level cannot cook it yet."
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
	# Supply-run cargo (V3_DESIGN §5.1): science brings research packs.
	var cargo: String = String(insp.hud.cargo_choice)
	if cargo == "":
		cargo = _d().cargo_current() if _d().cargo_current() != "" else "science"
		insp.hud.cargo_choice = cargo
	var csec: VBoxContainer = _section("Supply run cargo", "crate", P.CATEGORY["space"])
	var crow: HBoxContainer = Kit.hbox(6)
	csec.add_child(crow)
	for kind in _d().CARGO:
		var k: String = String(kind)
		var cb: Button = Kit.button(k.capitalize(), func():
			insp.hud.cargo_choice = k
			insp.refresh(), "%s cargo\nThe next supply run brings this." % k.capitalize(), "ChipButton", {"science": "icat_science", "medical": "icat_medical", "industrial": "icat_component"}[k], 14)
		cb.toggle_mode = true
		cb.set_pressed_no_signal(k == cargo)
		cb.custom_minimum_size.y = 28
		crow.add_child(cb)
	var brings: Dictionary = _d().cargo_items(cargo)
	if brings.is_empty():
		csec.add_child(Kit.label("The contents of this cargo are set by the ship.", "SmallLabel", 12, P.TEXT_2))
	else:
		csec.add_child(Kit.label("This cargo brings:", "SmallLabel", 12, P.TEXT_2))
		csec.add_child(_items_row(brings))
		if _d().cargo_current() != "" and cargo != _d().cargo_current():
			csec.add_child(Kit.label("The next automatic run still brings %s cargo. Press Supply run to use this one." % _d().cargo_current(), "SmallLabel", 11, P.AMBER))
	var row: HBoxContainer = Kit.hbox(6)
	body.add_child(row)
	for spec in [["survey", "Repair", "Colonists work on the ship when the Meridian chapter is open."], ["hold", "Hold", "Stop ship work. Materials stay in the ship."], ["supply_run", "Supply run", "Fly a supply run now with the chosen cargo (needs research Orbital Logistics and readiness)."]]:
		var act: String = spec[0]
		var bt: Button = Kit.button(spec[1], func():
			var pl: Dictionary = {"action": act}
			if act == "supply_run":
				pl["cargo"] = String(insp.hud.cargo_choice)
			insp.hud.main.submit("ship", pl), "%s\n%s" % [spec[1], spec[2]], "ChipButton")
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
			f.add_child(Kit.button("Cancel batch", func(): insp.hud.confirm("Cancel the batch in %s?" % b["name"], ["The inputs already used by this batch are lost."], func(): m.submit("cancel_batch", {"id": id}), "Cancel batch", true), "Cancel batch\nStops the batch now. The inputs it already used are lost.", "", "close", 14))
		if b["def"] == "corridor":
			var open: bool = bool(b.get("door_open", true))
			f.add_child(Kit.button("Close door" if open else "Open door", func(): m.submit("set_door", {"id": id, "open": not bool(m.sim.state["buildings"][id].get("door_open", true))}), "Isolation door\nA closed door separates the air of the two sides.", "", "door", 14))
		if bool(_d().wear_of(b).get("known", false)) and state == "active":
			f.add_child(Kit.button("Maintain now", func():
				m.submit("maintain", {"id": id})
				insp.hud.toast("Maintenance of %s is the next technician job." % String(b.get("name", "")), "info", "wrench"),
				"Maintain now\nA technician does this job first: wear goes back to 0 and a new failure point is set. It uses 1 part of the fault's item.", "", "wrench", 14))
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
	# Radiation dose (SIM milestone 6): a badge from 250 mSv.
	var dl: Array = insp.hud.v4.dose_level(insp.hud.v4.dose_of(a))
	if String(dl[0]) != "":
		insp.add_badge(Kit.badge(String(dl[0]), dl[1]))
	if d.is_visitor(a):
		_visitor(a)
		return
	insp.add_tabs([["status", "Status"], ["nutrition", "Nutrition"]] if score >= 0.0 else [["status", "Status"]])
	if insp.tab == "nutrition" and score >= 0.0:
		_nutrition(a)
	else:
		_needs(a)
	var f: HFlowContainer = insp.footer()
	f.add_child(Kit.button("Follow", func(): insp.hud.main.follow_selected(), "Follow\nThe camera follows this colonist. Key F.", "", "follow", 14))
	# Version 5: the personnel file and the over-the-shoulder follow view.
	if insp.hud.v5 != null and insp.hud.v5.live("people"):
		f.add_child(Kit.button("File", func(): insp.hud.open_person(id), "Personnel file\nSkills, satisfaction, attitude, relationships; review and discipline.", "", "colonists", 14))
		f.add_child(Kit.button("Shoulder", func(): insp.hud.main.follow_person(id), "Over the shoulder\nThe camera goes behind this person; you see what they say. Key V. Esc ends it.", "", "follow", 14))

## Visitor card (version 3.1, V3_1_DESIGN §6.5): kind, ship, leaves in, paid, what the visit
## gave them so far, health. Visitors take no jobs.
func _visitor(a: Dictionary) -> void:
	var d = _d()
	var s = _sim()
	var id: int = a["id"]
	var vk: String = String(a.get("vkind", ""))
	var kname: String = String(d.ship_kind(vk).get("vname", vk.capitalize()))
	var where: String = "Outside" if a["where"] == "out" else "In " + String(s.state["buildings"].get(a.get("bld", -1), {}).get("name", "a room"))
	insp.set_header(d.ship_icon(vk), P.GOLD, String(a["name"]), "%s, visitor  ·  %s" % [kname, where])
	insp.add_badge(Kit.badge("VISITOR", P.GOLD))
	var sec: VBoxContainer = _section("Visit", "ship", P.GOLD)
	var g: GridContainer = _grid()
	sec.add_child(g)
	var CS = load("res://ui/screens/colonists_screen.gd")
	_fact(g, "Kind", func(): return kname)
	_fact(g, "Ship", func(): return String(CS.visitor_info(insp.hud, s.state["agents"].get(id, a))["ship"]))
	_fact(g, "Leaves in", func(): return String(CS.visitor_info(insp.hud, s.state["agents"].get(id, a))["leaves"]), P.AMBER)
	_fact(g, "Paid", func(): return "%d credits" % int(s.state["agents"].get(id, a).get("visit", {}).get("paid", 0)), P.GOLD)
	_fact(g, "Health", func(): return "%d" % int(float(s.state["agents"].get(id, a).get("health", 100.0))))
	_fact(g, "Doing", func(): return String(s.state["agents"].get(id, a).get("goal", "")), P.CYAN)
	var visit: Dictionary = a.get("visit", {})
	var got: Array = []
	for pair in [["ate", "ate a meal"], ["slept", "slept in a bed"], ["rec", "had recreation"], ["treated", "was treated"], ["toured", "toured rooms"], ["study", "worked in a lab"]]:
		var v = visit.get(pair[0], null)
		if v != null and (typeof(v) == TYPE_BOOL and v or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and float(v) > 0.0) or (typeof(v) == TYPE_ARRAY and not (v as Array).is_empty())):
			got.append(pair[1])
	sec.add_child(Kit.wrap(("So far: " + ", ".join(got) + ".") if not got.is_empty() else "No service yet. Visitors pay for meals, beds and recreation.", 13, P.TEXT_2))
	sec.add_child(Kit.label("Visitors breathe and eat like colonists. They take no jobs.", "SmallLabel", 12, P.TEXT_3))
	insp.footer().add_child(Kit.button("Follow", func(): insp.hud.main.follow_selected(), "Follow\nThe camera follows this visitor. Key F.", "", "follow", 14))

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
	# Radiation dose: the bar fills to the sickness level (1,000 mSv); ticks of colour at 250 and 750.
	var v4 = insp.hud.v4
	var lim: Dictionary = v4.dose_limits()
	var dose0: float = v4.dose_of(a)
	var drow: HBoxContainer = Kit.bar_row("Dose", dose0 / float(lim["sick"]), "%d mSv" % int(dose0), v4.dose_level(dose0)[1] if dose0 >= float(lim["warn"]) else P.GREEN, 70.0)
	drow.tooltip_text = "Radiation dose\nHigh from %d mSv, dangerous from %d, sickness above %d. It falls slowly (5 %% a day). Inside a room a colonist takes a tenth of the outside rate." % [int(lim["warn"]), int(lim["critical"]), int(lim["sick"])]
	drow.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(drow)
	insp.bind(func():
		var aa: Dictionary = s.state["agents"].get(id, {})
		if aa.is_empty():
			return
		var dd: float = v4.dose_of(aa)
		drow.get_child(1).value = minf(1.0, dd / float(lim["sick"]))
		drow.get_child(1).color = v4.dose_level(dd)[1] if dd >= float(lim["warn"]) else P.GREEN
		(drow.get_child(2) as Label).text = "%d mSv" % int(dd))
	var g: GridContainer = _grid()
	body.add_child(g)
	_fact(g, "Doing", func(): return String(s.state["agents"].get(id, {}).get("goal", "")), P.CYAN)
	_fact(g, "Radiation now", func():
		var aa: Dictionary = s.state["agents"].get(id, {})
		if aa.is_empty():
			return "-"
		var rr: float = v4.dose_rate(aa)
		return ("%.2f mSv/h" % rr) if rr >= 0.005 else "none")
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

# ---------------------------------------------------------------- venues (version 5, V5 §8-§9; SIM sim/leisure.gd)
func _has_venues(b: Dictionary) -> bool:
	var l = _sim().get("leisure")
	return l != null and (l as Object).has_method("venues") and not (_sim().bdef(String(b["def"])).get("venues", []) as Array).is_empty()

# ---------------------------------------------------------------- parties (version 5, V5 section 16; sim/party.gd)
## A cantina, a lounge, a park and the super dome can hold a party (sim.party.cfg()["venue_defs"]).
func _can_party(b: Dictionary) -> bool:
	var pt = _sim().get("party")
	return pt != null and (pt as Object).has_method("venues") and (pt.cfg().get("venue_defs", []) as Array).has(String(b["def"]))

## The Party tab: throw a party here (hours, the cost, the guests), the party now (phase, time left, score, the
## last drama) and the offers that name this place. Answers go through command throw_party (SIM).
func _party(b: Dictionary) -> void:
	var id: int = int(b["id"])
	var pt = _sim().get("party")
	var sec: VBoxContainer = _section("Party", "music", Color("F472B6"))
	sec.name = "Party"
	sec.add_child(Kit.wrap("A party needs power and air in this place. It uses drinks, snacks or rations from the stock of the base: 1 unit for every 2 guests. Friends of the honoured person come first, then others who are off duty. They dance and talk. Satisfaction rises. Something may go wrong.", 12, P.TEXT_2))
	var info: Label = Kit.wrap("", 12, P.TEXT)
	info.name = "PartyInfo"
	sec.add_child(info)
	var h: HBoxContainer = Kit.hbox(8)
	sec.add_child(h)
	var hours := OptionButton.new()
	hours.name = "PartyHours"
	hours.focus_mode = Control.FOCUS_NONE
	hours.add_theme_font_size_override("font_size", 12)
	hours.tooltip_text = "How long\nOne party hour is 60 seconds. The cost is the same for 1, 2 or 3 hours."
	for hh in [1, 2, 3]:
		hours.add_item("%d hour%s" % [hh, "" if hh == 1 else "s"])
		hours.set_item_metadata(hours.item_count - 1, hh)
	hours.select(1)
	h.add_child(hours)
	var go: Button = Kit.button("Throw a party", func():
		var res: Dictionary = _hud().v5.command("throw_party", {"building": id, "hours": int(hours.get_item_metadata(hours.selected))})
		insp.last_party = res
		_hud().toast(String(res.get("text", "")), "good" if bool(res.get("ok", false)) else "warn", "music", "party"), "Throw a party\nGuests gather here. It costs drinks, snacks or rations from the base stock.", "PrimaryButton", "music", 13)
	go.name = "ThrowParty"
	h.add_child(go)
	# The rest follows the simulation: the cost, the party now, the offers that name this place.
	var box: VBoxContainer = Kit.vbox(4)
	box.name = "PartyBox"
	sec.add_child(box)
	var sig := [""]
	var fill := func():
		var bb: Dictionary = _sim().state["buildings"].get(id, {})
		if bb.is_empty():
			return
		var base: int = int(_sim().bases.base_of(id)) if _sim().bases.count() > 1 else -1
		var row_v: Dictionary = {}
		for r in pt.venues(base):
			if int(r["building"]) == id:
				row_v = r
		if row_v.is_empty():
			info.text = "This place cannot hold a party now: it needs power and air."
			info.add_theme_color_override("font_color", P.AMBER)
		else:
			info.text = "Up to %d guests. About %d units of drinks, snacks or rations. Quality %d." % [int(row_v["cap"]), pt.party_cost(int(row_v["cap"])), int(row_v["quality"])]
			info.add_theme_color_override("font_color", P.TEXT)
		go.disabled = row_v.is_empty()
		var parts: Array = []
		for r in pt.parties():
			if int(r["building"]) == id:
				parts.append(r)
		var offers: Array = []
		for o in pt.offers():
			for c in o.get("place_choices", []):
				if int(c["building"]) == id:
					offers.append(o)
					break
		var sg: String = str(parts) + str(offers)
		if sg == sig[0]:
			return
		sig[0] = sg
		Kit.clear(box)
		for r in parts:
			var pl: VBoxContainer = Kit.vbox(2)
			pl.name = "PartyNow"
			box.add_child(pl)
			pl.add_child(Kit.head("%s  ·  %s" % [String(r["phase"]).to_upper(), load("res://ui/hud/party_card.gd").title_of(r["reason"]).to_upper()], P.AMBER, 11))
			var sc: Dictionary = r["score"]
			pl.add_child(Kit.label("%d guests  ·  fun %d  ·  attendance %d  ·  drama %d" % [(r["guests"] as Array).size(), int(sc.get("fun", 0)), int(sc.get("attendance", 0)), int(sc.get("drama", 0))], "SmallLabel", 12, P.TEXT_2))
			for d in r["drama"]:
				pl.add_child(Kit.wrap(("DRAMA: " if bool(d.get("big", false)) else "") + String(d.get("text", "")), 12, P.RED if bool(d.get("big", false)) else P.TEXT_2))
		for o in offers:
			var ol: Label = Kit.wrap("An offer waits in the Requests tab: %s" % String(o.get("text", "")), 12, P.GOLD)
			ol.name = "PartyOffer"
			box.add_child(ol)
	fill.call()
	insp.bind(fill)

func _dome_stage(b: Dictionary) -> Dictionary:
	var l = _sim().get("leisure")
	return l.dome_stage(b) if l != null and (l as Object).has_method("dome_stage") else {}

## Each venue of a shop, park or the super dome: open or closed (and why), staff, goods in stock, what a
## tourist pays. SIM proposes the staff; colonists use venues for free.
func _venues(b: Dictionary) -> void:
	var id: int = int(b["id"])
	var sec: VBoxContainer = _section("Venues", "cat_civic", P.CYAN)
	sec.name = "Venues"
	sec.add_child(Kit.wrap("A venue is open when the structure has power, its staff are at work and a shop has goods. Colonists use venues for free; tourists pay the price.", 12, P.TEXT_2))
	var tour: Label = Kit.wrap("", 12, P.GOLD)
	tour.name = "Tourism"
	sec.add_child(tour)
	var tfill := func():
		var t: Dictionary = _hud().v5.tourism()
		tour.text = "Visitors now: %d  ·  tourism earned %d credits (all time)  ·  balance %d" % [int(t["visitors"]), int(t["earned"]), int(t["balance"])]
	tfill.call()
	insp.bind(tfill)
	var box: VBoxContainer = Kit.vbox(8)
	sec.add_child(box)
	var sig := [""]
	var fill := func():
		var bb: Dictionary = _sim().state["buildings"].get(id, {})
		if bb.is_empty():
			return
		var rows: Array = _sim().leisure.venues(bb)
		var sg: String = str(rows)
		if sg == sig[0]:
			return
		sig[0] = sg
		Kit.clear(box)
		for r in rows:
			box.add_child(_venue_row(r, id))
	fill.call()
	insp.bind(fill)

func _venue_row(r: Dictionary, bid: int = -1) -> Control:
	var v: VBoxContainer = Kit.vbox(2)
	v.name = "Venue_" + String(r["id"])
	var h: HBoxContainer = Kit.hbox(6)
	v.add_child(h)
	var open: bool = bool(r.get("open", false))
	h.add_child(Kit.icon("sev_ok" if open else "lock", 14, P.GREEN if open else P.AMBER))
	var nm: Label = Kit.label(String(r["name"]) + (("  ·  floor %d" % (int(r["floor"]) + 1)) if int(r.get("floor", 0)) > 0 else ""), "", 13, P.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)
	if bool(r.get("adults_only", false)):
		h.add_child(Kit.badge("ADULTS", P.VIOLET))
	h.add_child(Kit.badge("OPEN" if open else "CLOSED", P.GREEN if open else P.AMBER))
	var parts: Array = []
	if not open and String(r.get("why", "")) != "":
		parts.append(String(r["why"]))
	var staff: Array = r.get("staff", [])
	if int(r.get("need_staff", 0)) > 0:
		var names: Array = []
		for aid in staff:
			names.append(_hud().v5.agent_name(int(aid)).get_slice(" ", 0))
		parts.append("Staff %d of %d%s" % [staff.size(), int(r["need_staff"]), (": " + ", ".join(names)) if not names.is_empty() else ""])
	if int(r.get("price", 0)) > 0 or int(r.get("fee", 0)) > 0:
		parts.append("Tourists pay %d" % maxi(int(r.get("price", 0)), int(r.get("fee", 0))))
	if int(r.get("quality", 0)) > 0:
		parts.append("Quality %d" % int(r["quality"]))
	var l: Label = Kit.wrap("  ·  ".join(parts), 12, P.TEXT_2)
	v.add_child(l)
	if int(r.get("need_staff", 0)) > 0 and bid >= 0:
		v.add_child(_staff_pick(bid, r))
	var stock: Dictionary = r.get("stock", {})
	if not (r.get("items", []) as Array).is_empty():
		var any := false
		for n in stock.values():
			any = any or int(n) > 0
		if not any:
			v.add_child(Kit.wrap("No goods. Carriers bring %s from storage." % ", ".join((r["items"] as Array).map(func(x): return _d().item_name(String(x)).to_lower())), 12, P.AMBER))
		else:
			v.add_child(_items_row(stock))
	return v

## Venue staff (command "staff" {building, venue, agent}; -1 = none). SIM proposes staff; the player can
## choose. People without a venue job come first, then by name; the current job is named.
func _staff_pick(bid: int, r: Dictionary) -> Control:
	var s = _sim()
	var ob := OptionButton.new()
	ob.name = "Staff_" + String(r["id"])
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_size_override("font_size", 12)
	ob.custom_minimum_size = Vector2(200, 26)
	ob.tooltip_text = "Staff
Choose who works at the %s (%s). The person leaves their other venue job." % [String(r["name"]).to_lower(), String(r.get("job", "staff"))]
	ob.add_item("Choose staff...")
	ob.set_item_metadata(0, -2)
	ob.add_item("No staff")
	ob.set_item_metadata(1, -1)
	var base: int = s.bases.base_of(bid) if s.bases.count() > 1 else -1
	var rows: Array = []
	for p in _hud().v5.people():
		if String(p["kind"]) != "colonist" or bool(p.get("prisoner", false)):
			continue
		if base >= 0 and int(p.get("base", -1)) != base:
			continue
		rows.append(p)
	rows.sort_custom(func(x, y):
		var jx: bool = String(x.get("job", "")) != ""
		var jy: bool = String(y.get("job", "")) != ""
		return (not jx and jy) or (jx == jy and String(x["name"]) < String(y["name"])))
	for p in rows:
		var job: String = String(p.get("job", ""))
		ob.add_item("%s%s" % [String(p["name"]), ("  (" + job + ")") if job != "" else ""])
		ob.set_item_metadata(ob.item_count - 1, int(p["id"]))
	ob.select(0)
	var vid: String = String(r["id"])
	ob.item_selected.connect(func(i: int):
		var aid: int = int(ob.get_item_metadata(i))
		if aid == -2:
			return
		var res: Dictionary = _hud().v5.command("staff", {"building": bid, "venue": vid, "agent": aid})
		insp.last_staff = res
		_hud().toast("Staff: " + String(res.get("text", "")), "info" if bool(res.get("ok", false)) else "warn", "people"))
	return ob
