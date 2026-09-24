extends RefCounted
## Machines, crops, automatic machines, spoilage and wear (spec 6, 7, 10; design 2-5).
## Output only ever comes from delivered inputs and completed work. A machine records its
## in-process batch, including the outputs it will make, so an interruption, a recipe
## change or a save/load can neither duplicate nor lose it.
##
## Kitchens cook dishes (dishes.json). Each batch picks the unlocked dish (by kitchen
## level, not switched off by the player) whose ingredients are in the input buffer and
## that best fills the colony's average nutrition deficit, plus taste, plus a bonus when
## that dish is low in stock. A batch makes as many dishes as it used ingredient units.

const Text = preload("res://sim/text.gd")

var sim
var _colony_cache := {}
var _colony_tick := -1
var _stock_cache := {}
var _stock_tick := -1

func _init(s) -> void:
	sim = s

# ---------------------------------------------------------------- recipes
## The recipe a machine runs: the player's choice (recipe_sel) when it is one of the
## building's recipes, else the default.
func recipe_id(b: Dictionary) -> String:
	var d: Dictionary = sim.bdef(b["def"])
	var sel: String = String(b.get("recipe_sel", ""))
	if sel != "" and (d.get("recipes", []) as Array).has(sel):
		return sel
	return String(d.get("recipe", ""))

func recipe_of(b: Dictionary) -> Dictionary:
	var rid: String = recipe_id(b)
	if rid == "":
		return {}
	return sim.content["recipes"].get(rid, {})

func is_menu(b: Dictionary) -> bool:
	return bool(recipe_of(b).get("menu", false))

func has_batch(b: Dictionary) -> bool:
	return not (b["batch"] as Dictionary).is_empty()

func inputs_ready(b: Dictionary) -> bool:
	var rec: Dictionary = recipe_of(b)
	if rec.is_empty():
		return false
	if bool(rec.get("menu", false)):
		return menu_pick(b) != ""
	for res in rec["inputs"]:
		if sim.inv.available(b["inv_in"], res) < int(rec["inputs"][res]):
			return false
	if int(rec.get("from_deposit", 0)) > 0 and _deposit_under(b).is_empty():
		return false
	return true

func output_space(b: Dictionary) -> bool:
	var rec: Dictionary = recipe_of(b)
	if bool(rec.get("menu", false)):
		# The smallest dish makes 2 units.
		return sim.inv.free_space(b["inv_out"]) >= 2
	var n := 0
	for res in rec["outputs"]:
		n += int(rec["outputs"][res])
	return sim.inv.free_space(b["inv_out"]) >= n

## Why the machine cannot run now, or "" when it can take work.
func machine_block(b: Dictionary) -> String:
	if b["state"] != "active":
		return "broken" if b["state"] == "broken" else "not_ready"
	if not bool(b["enabled"]):
		return "disabled"
	if not bool(b["powered"]):
		return "no_power"
	if has_batch(b):
		return ""
	if not output_space(b):
		return "output_blocked"
	if is_menu(b) and _stock_full():
		return "stock_full"
	if _output_stock_full(recipe_of(b)):
		return "stock_full"
	if not inputs_ready(b):
		var rec: Dictionary = recipe_of(b)
		if int(rec.get("from_deposit", 0)) > 0:
			return "deposit_empty"
		return "no_input"
	var wn: int = int(recipe_of(b).get("water_net", 0))
	if wn > 0 and not sim.util.water_available(b["id"], 2):
		return "no_water"
	return ""

## An automatic recipe machine (research assembler): no staff, its batch runs by itself.
func is_auto_recipe(b: Dictionary) -> bool:
	return bool(sim.bdef(b["def"]).get("auto_recipe", false))

## Reserve output room and consume the inputs in one step (spec 7: atomic).
func start_batch(b: Dictionary) -> bool:
	if has_batch(b) or machine_block(b) != "":
		return false
	var rec: Dictionary = recipe_of(b)
	if bool(rec.get("menu", false)):
		return _start_dish(b)
	var n := 0
	for res in rec["outputs"]:
		n += int(rec["outputs"][res])
	var hold: int = sim.inv.hold_in(b["inv_out"], "_batch", n, -int(b["id"]) - 1000000)
	if hold == -1:
		return false
	var wn: int = int(rec.get("water_net", 0))
	if wn > 0 and not sim.util.draw_water(b["id"], wn * sim.util.fp(), 2):
		sim.inv.release(hold)
		b["block"] = "no_water"
		return false
	for res in rec["inputs"]:
		sim.inv.consume(b["inv_in"], res, int(rec["inputs"][res]), "batch_input")
		sim.stat_add("consumed", res, int(rec["inputs"][res]))
	if int(rec.get("from_deposit", 0)) > 0:
		var d: Dictionary = _deposit_under(b)
		d["ore"] = int(d["ore"]) - int(rec["from_deposit"])
	b["batch"] = {"recipe": recipe_id(b), "progress": 0.0, "work": float(rec["work"]), "hold": hold,
		"outputs": (rec["outputs"] as Dictionary).duplicate()}
	return true

func _start_dish(b: Dictionary) -> bool:
	var dish: String = menu_pick(b)
	if dish == "":
		return false
	var ds: Dictionary = sim.content["dishes"][dish]
	var count: int = int(ds["units"])
	var hold: int = sim.inv.hold_in(b["inv_out"], "_batch", count, -int(b["id"]) - 1000000)
	if hold == -1:
		return false
	for res in ds["ingredients"]:
		sim.inv.consume(b["inv_in"], res, int(ds["ingredients"][res]), "cooked")
		sim.stat_add("consumed", res, int(ds["ingredients"][res]))
	b["batch"] = {"recipe": recipe_id(b), "dish": dish, "progress": 0.0, "work": float(ds["work_per_dish"]) * count,
		"hold": hold, "outputs": {dish: count}}
	return true

## Work speed of a machine: its level (for "work_speed" buildings) and research.
func speed(b: Dictionary) -> float:
	var d: Dictionary = sim.bd(b)
	var m: float = 1.0
	if String(sim.bdef(b["def"]).get("level_stat", "")) == "work_speed":
		m = float(d.get("level_mult", 1.0))
	if String(recipe_of(b).get("category", "")) == "industry":
		m *= 1.0 + sim.research.bonus("industry_work_mult")
	return m

func work_batch(b: Dictionary, work_points: float) -> bool:
	# Returns true when the batch finished on this call.
	if not has_batch(b):
		return false
	var batch: Dictionary = b["batch"]
	batch["progress"] = float(batch["progress"]) + work_points * float(b["out_rate"]) * speed(b)
	if float(batch["progress"]) < float(batch["work"]):
		return false
	var outs: Dictionary = batch.get("outputs", {})
	if outs.is_empty():
		outs = sim.content["recipes"].get(String(batch["recipe"]), {}).get("outputs", {})
	sim.inv.release(int(batch["hold"]))
	var keys: Array = outs.keys()
	keys.sort()
	for res in keys:
		var n: int = sim.inv.add_new(b["inv_out"], res, int(outs[res]), "batch_output")
		sim.count_produced(res, n)
		if sim.items.is_dish(res):
			sim.stat_add("cooked", res, n)
			sim.stat_add("cooked_total", "", n)
	b["batch"] = {}
	return true

## Player cancel of a started batch: its consumed inputs are lost (spec 7).
func cancel_batch(b: Dictionary) -> void:
	if not has_batch(b):
		return
	sim.inv.release(int(b["batch"]["hold"]))
	b["batch"] = {}
	sim.log_event("batch_cancelled", "%s: the batch was cancelled. Its inputs are lost." % b["name"], [b["id"]])

## Command "set_recipe": inputs the new recipe does not use are put down inside the room
## (a recoverable pile that carriers take to storage). A running batch finishes as it was.
func set_recipe(b: Dictionary, rid: String) -> Dictionary:
	var d: Dictionary = sim.bdef(b["def"])
	var list: Array = d.get("recipes", [])
	if not list.has(rid):
		return {"ok": false, "code": "invalid"}
	if not sim.research.recipe_unlocked(rid):
		return {"ok": false, "code": "locked_research"}
	if recipe_id(b) == rid:
		b["recipe_sel"] = rid
		return {"ok": true, "code": "ok"}
	b["recipe_sel"] = rid
	if int(b["inv_in"]) != -1:
		sim.jobs.cancel_tasks_for_inventory(b["inv_in"], "recipe_changed")
		var uses: Dictionary = sim.content["recipes"][rid]["inputs"]
		var inv: Dictionary = sim.inv.get_inv(b["inv_in"])
		var pile := -1
		for res in inv["items"].keys():
			if uses.has(res):
				continue
			if pile == -1:
				pile = sim.inv.create_inv("g", int(b["id"]) if sim.topo.atmo_comp.has(b["id"]) else 0, "pile", 100000, sim.nav.slot_pos(b, 7))
			sim.inv.move(b["inv_in"], pile, res, int(inv["items"][res]))
	sim.log_event("recipe", "%s now makes %s." % [b["name"], String(sim.content["recipes"][rid]["name"]).to_lower()], [b["id"]], 0)
	return {"ok": true, "code": "ok"}

func _deposit_under(b: Dictionary) -> Dictionary:
	for d in sim.state["deposits"]:
		if Vector2(d["x"], d["y"]).distance_to(b["pos"]) <= float(d["r"]) and int(d["ore"]) > 0:
			return d
	return {}

# ---------------------------------------------------------------- kitchens
## Dishes this kitchen may cook: its level is high enough and the player did not switch
## them off. Sorted by id.
func menu_of(b: Dictionary) -> Array:
	var out: Array = []
	var level: int = int(b.get("level", 1))
	var off: Dictionary = b.get("menu_off", {})
	for id in sim.items.dishes():
		var ds: Dictionary = sim.content["dishes"].get(id, {})
		if ds.is_empty() or int(ds["kitchen_level"]) < 1 or int(ds["kitchen_level"]) > level:
			continue
		if off.has(id):
			continue
		out.append(id)
	return out

## Crops the kitchen keeps in its input buffer: {crop: units wanted}.
func kitchen_wants(b: Dictionary) -> Dictionary:
	var out := {}
	var stock: int = int(sim.bal["nutrition"]["kitchen_crop_stock"])
	for id in menu_of(b):
		for res in sim.content["dishes"][id]["ingredients"]:
			out[res] = stock
	return out

## The dish the next batch will cook, or "".
func menu_pick(b: Dictionary) -> String:
	if int(b.get("inv_in", -1)) == -1:
		return ""
	var col: Dictionary = _colony()
	var cfg: Dictionary = sim.bal["nutrition"]
	var target: float = float(cfg["target"])
	var free: int = sim.inv.free_space(b["inv_out"])
	var pop: int = maxi(1, int(col["people"]))
	var best := ""
	var best_s := -1e18
	for id in menu_of(b):
		var ds: Dictionary = sim.content["dishes"][id]
		if int(ds["units"]) > free:
			continue
		var ok := true
		for res in ds["ingredients"]:
			if sim.inv.available(b["inv_in"], res) < int(ds["ingredients"][res]):
				ok = false
				break
		if not ok:
			continue
		var s := 0.0
		for k in ds["nutrition"]:
			s += maxf(0.0, target - float(col.get(k, target))) * float(ds["nutrition"][k]) / 100.0
		s += float(cfg["choice_taste_weight"]) * float(ds.get("taste", 0))
		if _dish_stock(id) < maxi(2, pop / 2):
			s += 5.0
		if s > best_s:
			best_s = s
			best = id
	return best

## Kitchens stop while the colony has kitchen_stock_days of cooked dishes: cooking more
## only makes food that spoils. Emergency rations do not count.
func _stock_full() -> bool:
	var days: float = float(sim.bal["nutrition"].get("kitchen_stock_days", 0.0))
	if days <= 0.0:
		return false
	_refresh_stock()
	if _has_cold:
		days = float(sim.bal["nutrition"].get("kitchen_stock_days_cold", days))
	var n := 0
	for d in sim.items.dishes():
		if d == "meals":
			continue
		n += int(_stock_cache.get(d, {}).get("total", 0))
	return float(n) >= days * float(maxi(1, sim.alive_count()))

var _has_cold := false

## Colony stock totals, once per second.
func _refresh_stock() -> void:
	var t: int = int(sim.state["tick"])
	if t == _stock_tick:
		return
	_stock_cache = sim.inv.totals()
	_stock_tick = t
	_has_cold = false
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "active" and bool(sim.bdef(b["def"]).get("cold", false)):
			_has_cold = true
			break

## A recipe with stock_max stops while the colony holds that many units of its output.
## With "stock_for": "ship" the limit is also the Meridian's remaining need.
func _output_stock_full(rec: Dictionary) -> bool:
	if not rec.has("stock_max") or (rec["outputs"] as Dictionary).is_empty():
		return false
	_refresh_stock()
	var out: String = String((rec["outputs"] as Dictionary).keys()[0])
	var limit: int = int(rec["stock_max"])
	if String(rec.get("stock_for", "")) == "ship":
		# Made only for the Meridian: no more than its repair still needs.
		limit = mini(limit, sim.ship.future_need(out))
	return int(_stock_cache.get(out, {}).get("total", 0)) >= limit

func _colony() -> Dictionary:
	var t: int = int(sim.state["tick"])
	if t != _colony_tick:
		_colony_cache = sim.nutrition.colony()
		_colony_tick = t
	return _colony_cache

func _dish_stock(id: String) -> int:
	_refresh_stock()
	return int(_stock_cache.get(id, {}).get("total", 0))

## Command "set_dish": switch one dish on or off in this kitchen's menu.
func set_dish(b: Dictionary, dish: String, on: bool) -> Dictionary:
	if not is_menu(b) or not sim.content["dishes"].has(dish) or int(sim.content["dishes"][dish]["kitchen_level"]) < 1:
		return {"ok": false, "code": "invalid"}
	if not b.has("menu_off"):
		b["menu_off"] = {}
	if on:
		b["menu_off"].erase(dish)
	else:
		b["menu_off"][dish] = true
	return {"ok": true, "code": "ok"}

# ---------------------------------------------------------------- crops
func crop_info(crop: String) -> Dictionary:
	return sim.content["crops"].get(crop, sim.content["crops"]["potato"])

## Crops that grow in this building and are unlocked, sorted.
func crops_for(def_id: String) -> Array:
	var out: Array = []
	for id in sim.content["crops"]:
		var c: Dictionary = sim.content["crops"][id]
		if String(c["building"]) == def_id and int(c.get("cycle_seconds", 0)) > 0 and sim.research.crop_unlocked(id):
			out.append(id)
	out.sort()
	return out

## Command "set_crop": tray -1 plans every tray and the building default.
## A growing tray keeps its crop; the new plan starts at the next seeding.
func set_crop(b: Dictionary, crop: String, tray: int) -> Dictionary:
	if (b.get("trays", []) as Array).is_empty() and b["state"] == "active":
		return {"ok": false, "code": "invalid"}
	if not sim.content["crops"].has(crop) or String(sim.content["crops"][crop]["building"]) != b["def"]:
		return {"ok": false, "code": "invalid"}
	if not sim.research.crop_unlocked(crop):
		return {"ok": false, "code": "locked_research"}
	var trays: Array = b.get("trays", [])
	if tray < 0:
		b["crop"] = crop
		for t in trays:
			t["crop"] = crop
	elif tray < trays.size():
		trays[tray]["crop"] = crop
	else:
		return {"ok": false, "code": "invalid"}
	return {"ok": true, "code": "ok"}

## Once per second: growing trays take their water (one second's worth) and grow, or
## count the interruption.
func crops_second() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var dt := 1.0
	var hz: int = int(sim.bal["tick_hz"])
	var limit: float = float(sim.bal["crop_interrupt_limit_seconds"])
	for id in blds:
		var b: Dictionary = blds[id]
		if (b["trays"] as Array).is_empty() or b["state"] == "blueprint" or b["state"] == "building":
			continue
		var growing := 0
		var reason := ""
		var gm: float = -1.0
		for tray in b["trays"]:
			if tray["state"] != "growing":
				continue
			growing += 1
			if gm < 0.0:
				gm = float(b["out_rate"]) * _growth_mult(b)
			var crop: Dictionary = crop_info(String(tray.get("grow", "potato")))
			var ok: bool = b["state"] == "active" and bool(b["enabled"]) and bool(b["powered"])
			if not ok:
				reason = "no_power" if b["state"] == "active" and bool(b["enabled"]) else "disabled"
			elif not sim.util.draw_water(id, sim.util.rt(float(crop["water_per_day"])) * hz, 2):
				ok = false
				reason = "no_water"
			if ok:
				tray["growth"] = float(tray["growth"]) + dt * gm
				if float(tray["growth"]) >= float(crop["cycle_seconds"]):
					tray["state"] = "ready"
					tray["work"] = 0.0
			else:
				tray["interrupt"] = float(tray["interrupt"]) + dt
				if float(tray["interrupt"]) > limit:
					tray["state"] = "empty"
					tray["growth"] = 0.0
					tray["interrupt"] = 0.0
					tray["work"] = 0.0
					tray["grow"] = ""
					sim.state["metrics"]["crops_lost"] = int(sim.state["metrics"].get("crops_lost", 0)) + 1
					sim.log_event("crop_lost", "%s lost a crop: %s for more than %s." % [b["name"], _reason_words(reason), Text.n(int(limit), "second")], [id])
		if growing > 0:
			b["block"] = reason

func _growth_mult(b: Dictionary) -> float:
	if String(sim.bdef(b["def"]).get("level_stat", "")) == "growth":
		return float(sim.bd(b).get("level_mult", 1.0))
	return 1.0

static func _reason_words(code: String) -> String:
	match code:
		"no_power": return "no power"
		"no_water": return "no water"
		"disabled": return "switched off"
	return "interrupted"

## Seconds until the first tray of a stopped greenhouse dies, or -1.
func crop_risk_seconds(b: Dictionary) -> float:
	var worst := -1.0
	for tray in b["trays"]:
		if tray["state"] == "growing":
			var left: float = float(sim.bal["crop_interrupt_limit_seconds"]) - float(tray["interrupt"])
			if worst < 0.0 or left < worst:
				worst = left
	return worst

## Growth of a tray as a fraction 0..1 (for the view).
func tray_fraction(tray: Dictionary) -> float:
	if tray["state"] == "ready":
		return 1.0
	if tray["state"] != "growing":
		return 0.0
	var crop: Dictionary = crop_info(String(tray.get("grow", "potato")))
	return clampf(float(tray["growth"]) / maxf(1.0, float(crop["cycle_seconds"])), 0.0, 1.0)

## The crop a tray will be seeded with: its plan, when that crop is allowed here.
func seed_crop(b: Dictionary, tray: Dictionary) -> String:
	var plan: String = String(tray.get("crop", b.get("crop", "")))
	var c: Dictionary = sim.content["crops"].get(plan, {})
	if not c.is_empty() and String(c["building"]) == b["def"] and sim.research.crop_unlocked(plan):
		return plan
	var list: Array = crops_for(b["def"])
	if list.has(String(b.get("crop", ""))):
		return String(b["crop"])
	return String(list[0]) if not list.is_empty() else "potato"

func finish_seed(b: Dictionary, tray_i: int) -> void:
	var tray: Dictionary = b["trays"][tray_i]
	tray["grow"] = seed_crop(b, tray)
	tray["state"] = "growing"
	tray["growth"] = 0.0
	tray["interrupt"] = 0.0
	tray["work"] = 0.0

func harvest_units(crop_id: String) -> Dictionary:
	var crop: Dictionary = crop_info(crop_id)
	var m: float = 1.0 + sim.research.bonus("crop_yield_mult")
	var out := {}
	var y: int = int(floor(float(crop["yield"]) * m + 0.5))
	if y > 0:
		out[crop_id] = y
	var bm: int = int(floor(float(crop["biomass"]) * m + 0.5))
	if bm > 0:
		out["biomass"] = bm
	return out

func finish_harvest(b: Dictionary, tray_i: int) -> bool:
	var tray: Dictionary = b["trays"][tray_i]
	var outs: Dictionary = harvest_units(String(tray.get("grow", "potato")))
	var n := 0
	for res in outs:
		n += int(outs[res])
	if sim.inv.free_space(b["inv_out"]) < n:
		return false
	var keys: Array = outs.keys()
	keys.sort()
	for res in keys:
		sim.inv.add_new(b["inv_out"], res, int(outs[res]), "harvest")
		sim.count_produced(res, int(outs[res]))
	sim.stat_add("harvests", "", 1)
	tray["state"] = "empty"
	tray["growth"] = 0.0
	tray["interrupt"] = 0.0
	tray["work"] = 0.0
	tray["grow"] = ""
	return true

# ---------------------------------------------------------------- automatic machines
## Once per second: machines that work without staff and put units into their output
## buffer: algae bioreactor, regolith harvester, fuel refinery, deep core drill. A unit is
## made each time a fixed-point accumulator passes one whole unit.
func auto_second() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var hz: int = int(sim.bal["tick_hz"])
	var fp: int = sim.util.fp()
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or int(b["inv_out"]) == -1:
			continue
		var d: Dictionary = sim.bd(b)
		if bool(d.get("auto_recipe", false)):
			_auto_recipe_second(b, d)
			continue
		var item := ""
		var rate := 0.0
		var water := 0.0
		if d.has("algae_per_day"):
			item = "algae"
			rate = float(d["algae_per_day"])
			water = float(d.get("water_in", 0.0))
		elif d.has("silicate_per_day"):
			item = "silicate"
			rate = float(d["silicate_per_day"])
		elif d.has("fuel_per_day"):
			item = "rocket_fuel"
			rate = float(d["fuel_per_day"])
			water = rate * float(d.get("water_per_fuel", 0.0))
		elif d.has("exotic_per_day"):
			item = "exotic"
			rate = float(d["exotic_per_day"])
		else:
			continue
		if not bool(b["enabled"]):
			b["block"] = "disabled"
			continue
		if not bool(b["powered"]):
			b["block"] = "no_power"
			continue
		if item == "exotic" and _deposit_under(b).is_empty():
			b["block"] = "deposit_empty"
			continue
		if sim.inv.free_space(b["inv_out"]) <= 0:
			b["block"] = "output_blocked"
			continue
		if water > 0.0 and not sim.util.draw_water(id, sim.util.rt(water) * hz, 2):
			b["block"] = "no_water"
			continue
		b["block"] = ""
		var acc: Dictionary = b["acc"]
		var v: int = int(acc.get(item, 0)) + sim.util.rt(rate * float(b["out_rate"])) * hz
		while v >= fp and sim.inv.free_space(b["inv_out"]) > 0:
			sim.inv.add_new(b["inv_out"], item, 1, "machine")
			sim.count_produced(item, 1)
			v -= fp
		acc[item] = mini(v, fp)

## One second of an automatic recipe machine: start a batch when it can, then work it at
## auto_speed (size) work points per second; level and research act through speed().
func _auto_recipe_second(b: Dictionary, d: Dictionary) -> void:
	if bool(b.get("trip", false)):
		b["block"] = "flare"
		return
	if not has_batch(b):
		var block: String = machine_block(b)
		b["block"] = block
		if block != "" or not start_batch(b):
			return
	if not bool(b["enabled"]):
		b["block"] = "disabled"
		return
	if not bool(b["powered"]):
		b["block"] = "no_power"
		return
	b["block"] = ""
	work_batch(b, float(d.get("auto_speed", 1.0)))

# ---------------------------------------------------------------- spoilage
## Once per second (design section 3). Every inventory keeps an exact integer accumulator
## per perishable item: it grows by the free units each second; each time it reaches
## shelf_days x day_length one unit spoils (ledger "destroyed", reason "spoiled").
## Cold storage, machine input buffers, sites, upgrades, the ship and carried units never
## spoil. Reserved units are being handled and do not spoil either.
func spoil_second() -> void:
	if not bool(sim.state.get("options", {}).get("spoilage", true)):
		return
	var invs: Dictionary = sim.state["inventories"]
	var blds: Dictionary = sim.state["buildings"]
	var day: float = float(sim.bal["day_length"])
	for inv_id in invs:
		var inv: Dictionary = invs[inv_id]
		var role: String = inv["role"]
		if role != "store" and role != "out" and role != "pile" and role != "fill":
			continue
		if inv["ot"] == "b" and bool(sim.bdef(blds.get(inv["oid"], {}).get("def", "lander")).get("cold", false)):
			continue
		var items: Dictionary = inv["items"]
		if items.is_empty():
			if not (inv.get("spoil", {}) as Dictionary).is_empty():
				inv["spoil"] = {}
			continue
		if not inv.has("spoil"):
			inv["spoil"] = {}
		var acc: Dictionary = inv["spoil"]
		for res in acc.keys():
			if not items.has(res):
				acc.erase(res)
		for res in items.keys():
			var shelf: float = sim.items.shelf_days(res)
			if shelf <= 0.0:
				continue
			var free: int = int(items.get(res, 0)) - int(inv["held_out"].get(res, 0))
			if free <= 0:
				continue
			var limit: int = int(round(shelf * day))
			var v: int = int(acc.get(res, 0)) + free
			while v >= limit and free > 0:
				sim.inv.destroy(inv_id, res, 1, "spoiled")
				sim.stat_add("spoiled", res, 1)
				sim.stat_add("spoiled_today", res, 1)
				v -= limit
				free -= 1
			if items.has(res):
				acc[res] = v
			else:
				acc.erase(res)

# ---------------------------------------------------------------- wear
func wear_second() -> void:
	if sim.util.days_elapsed() < float(sim.bal["wear_start_day"]):
		return
	var per_second: float = float(sim.bal["wear_per_day"]) / float(sim.bal["day_length"]) * sim.difficulty("wear_mult")
	var blds: Dictionary = sim.state["buildings"]
	# Version 3: with hazards on, machines wear by the v3 rule (sim/hazards.gd: wear,
	# maintenance, breakdowns with a fault). The v2 health loss stays for the rest.
	var v3_wear: bool = sim.hazards.level() > 0.0 and bool(sim.bal["hazards"]["wear"].get("enabled", true))
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or b["kind"] == "link" or b["kind"] == "special":
			continue
		if not bool(b["enabled"]):
			continue
		if v3_wear and sim.hazards.is_machine(b):
			continue
		b["health"] = maxf(0.0, float(b["health"]) - per_second * float(sim.bd(b).get("wear_mult", 1.0)))
		b["out_rate"] = float(sim.bal["degraded_output"]) if float(b["health"]) < float(sim.bal["health_degraded"]) else 1.0
		if float(b["health"]) <= 0.0:
			b["state"] = "broken"
			b["powered"] = false
			sim.topo.mark_dirty()
			sim.log_event("broken", "%s broke down. A technician needs one spare part to repair it." % b["name"], [id])

func repair(b: Dictionary) -> void:
	b["health"] = minf(100.0, float(b["health"]) + float(sim.bal["repair_health"]))
	b["out_rate"] = float(sim.bal["degraded_output"]) if float(b["health"]) < float(sim.bal["health_degraded"]) else 1.0
	if b["state"] == "broken":
		b["state"] = "active"
		b["breach"] = false
		sim.topo.mark_dirty()
		sim.log_event("repaired", "%s works again." % b["name"], [b["id"]])

# ---------------------------------------------------------------- medicine
## A patient who starts treatment uses one unit of medicine from the bay, if it has one:
## healing is then twice as fast.
func use_medicine(bay: Dictionary) -> bool:
	if int(bay.get("inv_in", -1)) == -1:
		return false
	return sim.inv.consume(bay["inv_in"], "medicine", 1, "treatment") if sim.inv.available(bay["inv_in"], "medicine") > 0 else false
