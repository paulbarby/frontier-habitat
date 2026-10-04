extends RefCounted
## The job board (spec 9). Once per second it looks at what the colony needs and makes
## task records for it; agents then score and claim them. Task ownership and inventory
## reservations live here and in inventory.gd, never in animation.
## Task states: open -> reserved -> traveling -> working -> completed, with blocked,
## cancelled and failed as exits. Finished tasks are erased; their result is in the log.
## Task kinds: haul, build, demolish, operate, tend, repair, upgrade, research, shipwork.

var sim
var _inbound := {}     # "inv:res" -> units already on their way
var _open_hauls := {}  # dst inv -> count of unowned haul tasks
var _count := {}       # "kind:bld[:tray]" -> number of tasks
var _by_bld := {}      # building id -> [tasks]
var _cold := {}        # inventory id -> true for cold stores (this second)
var _src_index := {}   # item -> [inventory ids that held it when the board was indexed]
var _far_piles := {}   # fragment pile inventory ids beyond suit range (this second)

func _init(s) -> void:
	sim = s

# ---------------------------------------------------------------- per second
## The whole job board once (tools and tests that call it directly).
func tick_second() -> void:
	tick_part(0)
	tick_part(1)
	tick_part(2)

## The job board in three parts, each on its own tick of the second (sim.gd step(): phases 4, 9
## and 1), so that no tick carries all of it (V5 budget: no tick over 12 ms). The parts keep the
## order of the generators (A, B, C, A, B, C ...): machines and repairs still reserve before
## construction, and each part indexes the board again (the state moved between the parts).
func tick_part(part: int) -> void:
	if part != 0:
		_index(part == 1)
	match part:
		0:
			_expire()
			_index()
			# Machines take their inputs before plans reserve the rest: a factory that waits for
			# steel while every unit is promised to construction sites makes no more steel.
			_gen_machine_inputs()
		1:
			# V3: repairs, breach seals and maintenance take their parts before construction plans
			# reserve the rest (a cracked corridor must not wait for a new solar array). They open this
			# part (they closed part 0 before: part 0 was 5-7 ms, part 1 1.3 ms; worst tick budget).
			_gen_repair()
			_gen_hazard_work()
			_gen_research()
			_gen_medical()
			# V3: the Meridian's parts are reserved before ordinary construction and upgrades
			# (with repairs, maintenance and research packs there are more users of steel).
			_gen_ship()
			_gen_construction()
			_gen_upgrades()
			_gen_vehicles()
			_gen_reactors()
			_gen_dining()
			_gen_venues()
			_gen_trade()
			_gen_water_fill()
		2:
			_gen_clearing()
			_gen_operate()
			_gen_tend()
			_gen_demolish()
			# Every 10 s.
			if (int(sim.state["tick"]) / int(sim.bal["tick_hz"])) % 10 == 0:
				_clean_piles()
## full = false: no item-source index (_src_index); part 2 never calls find_source, so it skips the biggest
## part of the rebuild (about a third of it).
func _index(full: bool = true) -> void:
	_free_cache = {}
	_inbound = {}
	_open_hauls = {}
	_count = {}
	_by_bld = {}
	var holds: Dictionary = sim.state["holds"]
	for hid in holds:
		var h: Dictionary = holds[hid]
		if h["dir"] == "in":
			var k := "%d:%s" % [h["inv"], h["res"]]
			_inbound[k] = int(_inbound.get(k, 0)) + int(h["qty"])
	var tasks: Dictionary = sim.state["tasks"]
	for tid in tasks:
		var t: Dictionary = tasks[tid]
		var key := "%s:%d" % [t["kind"], t["bld"]]
		if t["kind"] == "tend":
			key += ":%d" % t["tray"]
		_count[key] = int(_count.get(key, 0)) + 1
		if int(t["bld"]) != -1:
			if not _by_bld.has(t["bld"]):
				_by_bld[t["bld"]] = []
			_by_bld[t["bld"]].append(t)
		if t["kind"] == "haul" and int(t["owner"]) == -1:
			_open_hauls[t["dst"]] = int(_open_hauls.get(t["dst"], 0)) + 1
	_cold = {}
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] == "active" and int(b["inv_out"]) != -1 and bool(sim.bdef(b["def"]).get("cold", false)):
			_cold[int(b["inv_out"])] = true
	_src_index = {}
	_far_piles = {}
	var invs: Dictionary = sim.state["inventories"]
	var reach := -1.0
	for inv_id in invs:
		var inv: Dictionary = invs[inv_id]
		var role: String = inv["role"]
		if not full and role != "pile":
			continue
		if role != "pile" and role != "out" and role != "store":
			continue
		# Meteor fragments beyond suit range are nobody's source until an airlock is near.
		if role == "pile" and bool(inv.get("fragment", false)):
			if reach < 0.0:
				reach = sim.agents.suit_reach_metres()
			if sim.agents.nearest_air_metres(inv["pos"]) > reach:
				_far_piles[inv_id] = true
				continue
		if not full:
			continue
		for r in inv["items"]:
			if not _src_index.has(r):
				_src_index[r] = []
			_src_index[r].append(inv_id)

## True when every waiting task of a structure was refused for suit range and nobody works
## on it: the site is too far from an airlock with air. The player must be told (spec 10:
## "block reasons are visible at each step").
func _range_blocked(bid: int, kind: String = "") -> bool:
	var list: Array = _by_bld.get(bid, [])
	var tick: int = int(sim.state["tick"])
	var old := false
	var any := false
	for t in list:
		if kind != "" and t["kind"] != kind:
			continue
		any = true
		if int(t["owner"]) != -1 or t["reason"] != "suit_range":
			return false
		if tick - int(t["created"]) > 200:
			old = true
	return any and old

func _inb(inv_id: int, res: String) -> int:
	return int(_inbound.get("%d:%s" % [inv_id, res], 0))

func _inb_any(inv_id: int, ids: Array) -> int:
	var n := 0
	for r in ids:
		n += _inb(inv_id, r)
	return n

func _new_task(kind: String, cat: String, bld: int, extra: Dictionary) -> Dictionary:
	var id: int = sim.new_id()
	var t := {
		"id": id, "kind": kind, "cat": cat, "state": "open", "emergency": 0,
		"created": int(sim.state["tick"]), "owner": -1, "bld": bld,
		"src": -1, "dst": -1, "res": "", "qty": 0, "hold_out": -1, "hold_in": -1,
		"tray": -1, "op": "", "role": "", "picked": false, "fails": 0, "retry": 0, "reason": "",
	}
	for k in extra:
		t[k] = extra[k]
	sim.state["tasks"][id] = t
	var key := "%s:%d" % [kind, bld]
	if kind == "tend":
		key += ":%d" % t["tray"]
	_count[key] = int(_count.get(key, 0)) + 1
	return t

var no_divert := false   # set while an order makes its haul: the colonist carries it

func _make_haul(cat: String, src: int, dst: int, res: String, qty: int, bld: int, emergency: int) -> bool:
	var t: Dictionary = _new_task("haul", cat, bld, {"src": src, "dst": dst, "res": res, "qty": qty, "emergency": emergency})
	var ho: int = sim.inv.hold_out(src, res, qty, t["id"])
	var hi: int = sim.inv.hold_in(dst, res, qty, t["id"])
	if ho == -1 or hi == -1:
		sim.inv.release(ho)
		sim.inv.release(hi)
		sim.state["tasks"].erase(t["id"])
		return false
	t["hold_out"] = ho
	t["hold_in"] = hi
	var k := "%d:%s" % [dst, res]
	_inbound[k] = int(_inbound.get(k, 0)) + qty
	# V5 18.5: goods between structures with transport hubs go by tube, not by hand (not an ordered haul).
	if not no_divert and sim.transport.divert(t):
		return true
	_open_hauls[dst] = int(_open_hauls.get(dst, 0)) + 1
	return true

## Fills an inventory up to `wants` {res: units} with hauls. Returns the first resource
## for which no source exists, or "".
func _fill(dst: int, wants: Dictionary, cat: String, bld: int, emergency: int, near: Vector2, max_open: int) -> String:
	var carry: int = int(sim.bal["carry_human"])
	var missing := ""
	var keys: Array = wants.keys()
	keys.sort()
	for res in keys:
		var need: int = int(wants[res]) - sim.inv.count(dst, res) - _inb(dst, res)
		while need > 0 and int(_open_hauls.get(dst, 0)) < max_open:
			var src: int = find_source(res, near)
			if src == -1:
				if missing == "":
					missing = res
				break
			var qty: int = mini(carry, mini(need, sim.inv.available(src, res)))
			qty = mini(qty, sim.inv.free_space(dst))
			if qty <= 0 or not _make_haul(cat, src, dst, res, qty, bld, emergency):
				break
			need -= qty
	return missing

## Best place to fetch `res` from. Ground piles first, then machine outputs, then stores.
## scan: look at every inventory instead of the index of this second (the index is only whole between the
## second's job parts; an order or an alert asks at any tick).
func find_source(res: String, near: Vector2, skip_inv: int = -1, scan: bool = false) -> int:
	var best := -1
	var best_key := 1e18
	var invs: Dictionary = sim.state["inventories"]
	var blds: Dictionary = sim.state["buildings"]
	var dish: bool = sim.items.is_dish(res)
	# With several bases, a haul on foot never goes to another base (kilometres away, out of
	# suit range): the goods would stay reserved for a walk nobody can make (SIM 2026-09-30: a
	# kitchen's dishes were held for another base's dining room while its own people starved).
	var here: int = sim.bases.base_at(near) if sim.bases.count() > 1 else -1
	# Only inventories that held this item when the board was indexed this second.
	var candidates: Array = _src_index.get(res, [])
	if scan:
		candidates = []
		for iid in invs:
			if int(invs[iid]["items"].get(res, 0)) > 0:
				candidates.append(iid)
	for inv_id in candidates:
		if inv_id == skip_inv or not invs.has(inv_id):
			continue
		var inv: Dictionary = invs[inv_id]
		var rank := 0
		match inv["role"]:
			"pile": rank = 0
			"out": rank = 1
			"store": rank = 2
			_: continue
		if int(inv["items"].get(res, 0)) - int(inv["held_out"].get(res, 0)) <= 0:
			continue
		if _source_resting(inv_id):
			continue
		if inv["ot"] == "b":
			var ob: Dictionary = blds.get(inv["oid"], {})
			if ob.is_empty() or (ob["state"] != "active" and ob["state"] != "broken"):
				continue
			if inv["role"] == "out" and dish and not _surplus_dishes(inv_id):
				continue
			if here != -1 and sim.bases.base_of(int(inv["oid"])) != here:
				continue
		elif here != -1 and sim.bases.base_at(sim.inv.position_of(inv_id)) != here:
			continue
		var key: float = rank * 100000.0 + sim.inv.position_of(inv_id).distance_to(near)
		if key < best_key:
			best_key = key
			best = inv_id
	return best

func _cross_base(t: Dictionary) -> bool:
	var invs: Dictionary = sim.state["inventories"]
	var a: Dictionary = invs.get(int(t["src"]), {})
	var b: Dictionary = invs.get(int(t["dst"]), {})
	if a.is_empty() or b.is_empty():
		return false
	var ba: int = sim.bases.base_of(int(a["oid"])) if a["ot"] == "b" else sim.bases.base_at(sim.inv.position_of(int(t["src"])))
	var bb: int = sim.bases.base_of(int(b["oid"])) if b["ot"] == "b" else sim.bases.base_at(sim.inv.position_of(int(t["dst"])))
	return ba != -1 and bb != -1 and ba != bb

## Dishes live in the kitchen buffer so people can eat them. Only what is above the keep
## level may leave, so a kitchen never empties itself and never blocks at its cap.
func _surplus_dishes(inv_id: int) -> bool:
	return sim.inv.count_any(inv_id, sim.items.dishes()) > int(sim.bal.get("kitchen_keep_meals", 8))

func _stores_with_space(skip_lander: bool) -> Array:
	var out: Array = []
	var invs: Dictionary = sim.state["inventories"]
	var blds: Dictionary = sim.state["buildings"]
	for inv_id in invs:
		var inv: Dictionary = invs[inv_id]
		if inv["role"] != "store" or inv["ot"] != "b":
			continue
		var ob: Dictionary = blds.get(inv["oid"], {})
		if ob.is_empty() or ob["state"] != "active" or bool(ob["demolish"]):
			continue
		if skip_lander and ob["def"] == "lander":
			continue
		if sim.inv.free_space(inv_id) > 0:
			out.append(inv_id)
	return out

# ---------------------------------------------------------------- generators
func _gen_construction() -> void:
	if bool(sim.state.get("options", {}).get("freeze_build", false)):
		return
	var blds: Dictionary = sim.state["buildings"]
	var cap: int = int(sim.bal["haul_outstanding_per_destination"])
	var carry: int = int(sim.bal["carry_human"])
	var rev: int = int(sim.state["rev"]["walk"])
	var tick: int = int(sim.state["tick"])
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] == "blueprint":
			if _unreach(b):
				b["block"] = "unreachable"
				continue
			# Out of suit range: the stock reserved for it is let go, so other plans can use
			# it, and nothing new is reserved for a minute (then the colony tries again).
			if int(b.get("range_wait", -1)) > tick:
				b["block"] = "suit_range"
				continue
			if _range_blocked(id):
				_release_hauls(id, "suit_range")
				b["range_wait"] = tick + RANGE_WAIT_SECONDS * int(sim.bal["tick_hz"])
				b["block"] = "suit_range"
				continue
			var blocked := ""
			for res in b["cost"]:
				var need: int = int(b["cost"][res]) - sim.inv.count(b["inv_site"], res) - _inb(b["inv_site"], res)
				while need > 0 and int(_open_hauls.get(b["inv_site"], 0)) < cap:
					var src: int = find_source(res, b["pos"])
					if src == -1:
						blocked = "materials:" + res
						break
					var qty: int = mini(carry, mini(need, sim.inv.available(src, res)))
					if not _make_haul("construction", src, b["inv_site"], res, qty, id, _site_emergency(b)):
						break
					need -= qty
			if blocked == "" and _range_blocked(id):
				blocked = "suit_range"
			b["block"] = blocked
		elif b["state"] == "building":
			var slots: int = int(sim.bdef(b["def"]).get("build_slots", 2))
			if _unreach(b):
				b["block"] = "unreachable"
				continue
			while int(_count.get("build:%d" % id, 0)) < slots:
				_new_task("build", "construction", id, {"emergency": _site_emergency(b)})
			b["block"] = "suit_range" if _range_blocked(id) else ""

## V5 section 9: carriers stock the venues (the goods store of the retail module and the super dome)
## with the goods their staffed venues sell (sim/leisure.gd wants).
func _gen_venues() -> void:
	if sim.get("leisure") == null:
		return
	# Every 5 s is enough for shop shelves (cost: 0.5 ms a call with a dome).
	if (int(sim.state["tick"]) / int(sim.bal["tick_hz"])) % 5 != 2:
		return
	for w in sim.leisure.wants():
		var b: Dictionary = sim.state["buildings"].get(int(w[2]), {})
		if b.is_empty() or _parked(b):
			continue
		_fill(int(w[0]), w[1], "food", int(w[2]), 0, w[3], 2)

## Seconds a plan out of suit range waits before stock is reserved for it again.
const RANGE_WAIT_SECONDS := 60
## A kitchen keeps its dishes until it has less free room than this.
const KITCHEN_CLEAR_FREE := 4

## Fails the open hauls to a structure that nobody has picked up yet.
func _release_hauls(bid: int, reason: String) -> void:
	var tasks: Dictionary = sim.state["tasks"]
	for t in _by_bld.get(bid, []):
		if t["kind"] == "haul" and int(t["owner"]) == -1 and not bool(t["picked"]) and tasks.has(t["id"]):
			fail(t["id"], reason)

## True while a structure is parked as unreachable: no new work is made for it until the
## walking graph changes (for example, its corridor is finished).
func _parked(b: Dictionary) -> bool:
	return _unreach(b)

## Parked as unreachable: until the walking graph changes, and (V4) at most UNREACH_HOLD s: then
## the colony tries again, so a mark can never outlive its cause.
const UNREACH_HOLD := 120

func _unreach(b: Dictionary) -> bool:
	if int(b["unreach_rev"]) != int(sim.state["rev"]["walk"]):
		return false
	var since: int = int(b.get("unreach_tick", -1))
	if since >= 0 and int(sim.state["tick"]) - since > UNREACH_HOLD * int(sim.bal["tick_hz"]):
		b["unreach_rev"] = -1
		b.erase("unreach_tick")
		return false
	return true

func _site_emergency(b: Dictionary) -> int:
	# Life support goes first while the colony still depends on the lander air.
	var def: Dictionary = sim.bdef(b["def"])
	if def.get("category", "") == "life_support" and not sim.state["flags"].get("base_air", false):
		return 2
	return 0

## Upgrades: materials to the building's upgrade inventory, then technician work.
func _gen_upgrades() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var cap: int = int(sim.bal["haul_outstanding_per_destination"])
	for id in blds:
		var b: Dictionary = blds[id]
		var u: Dictionary = b.get("upgrade", {})
		if u.is_empty() or _parked(b):
			continue
		if u["state"] == "deliver":
			var miss: String = _fill(int(u["inv"]), u["cost"], "construction", id, 0, b["pos"], cap)
			u["block"] = ("materials:" + miss) if miss != "" else ""
		elif u["state"] == "work":
			var slots: int = mini(2, int(sim.bdef(b["def"]).get("build_slots", 2)))
			while int(_count.get("upgrade:%d" % id, 0)) < slots:
				_new_task("upgrade", "construction", id, {"role": "technician"})
			u["block"] = "suit_range" if _range_blocked(id, "upgrade") else ""

## V4 vehicles: parts to the depot's order, then technician work outside at the depot.
func _gen_vehicles() -> void:
	if sim.vehicles == null:
		return
	var cap: int = int(sim.bal["haul_outstanding_per_destination"])
	for d in sim.vehicles.builders():
		var o: Dictionary = d.get("vorder", {})
		if o.is_empty() or _parked(d):
			continue
		var id: int = int(d["id"])
		if o["state"] == "deliver":
			var miss: String = _fill(int(o["inv"]), o["cost"], "construction", id, 0, d["pos"], cap)
			o["block"] = ("materials:" + miss) if miss != "" else ""
		elif o["state"] == "work":
			while int(_count.get("vbuild:%d" % id, 0)) < 2:
				_new_task("vbuild", "construction", id, {"role": "technician"})
			o["block"] = "suit_range" if _range_blocked(id, "vbuild") else ""

## V4 reactors: fuel rods and coolant to the reactor's buffer; coolant is urgent when it runs hot.
func _gen_reactors() -> void:
	if sim.reactors == null:
		return
	var c: Dictionary = sim.bal["disasters"]["reactor"]
	for b in sim.reactors.reactors():
		if int(b["inv_in"]) == -1 or b["state"] != "active" or _parked(b):
			continue
		var st: String = String(b.get("rx", {}).get("stage", "ok"))
		var em: int = 3 if st == "critical" else (2 if st == "warning" else 0)
		var miss: String = _fill(int(b["inv_in"]), {"coolant": int(c["coolant_keep"]), "fuel_rod": int(c["rods_keep"])}, "industry", int(b["id"]), em, b["pos"], 3)
		b["block"] = ("materials:" + miss) if miss != "" and String(b["block"]) == "" else String(b["block"])

## The Meridian: parts to the hull, then exterior work; later maintenance.
func _gen_ship() -> void:
	var b: Dictionary = sim.ship.record()
	if b.is_empty() or bool(sim.state["ship"].get("away", false)):
		return
	var id: int = int(b["id"])
	var wants: Dictionary = sim.ship.wants()
	if not wants.is_empty():
		# The ship is the mission: its parts go before ordinary construction.
		var miss: String = _fill(int(b["inv_site"]), wants, "construction", id, 1, b["pos"], int(sim.bal["haul_outstanding_per_destination"]))
		b["block"] = ("materials:" + miss) if miss != "" else ""
	else:
		b["block"] = ""
	match sim.ship.work_kind():
		"repair":
			while int(_count.get("shipwork:%d" % id, 0)) < sim.ship.work_slots():
				_new_task("shipwork", "construction", id, {})
		"maint":
			while int(_count.get("shipwork:%d" % id, 0)) < 1:
				_new_task("shipwork", "repair", id, {"role": "technician"})
	if b["block"] == "" and _range_blocked(id, "shipwork"):
		b["block"] = "suit_range"

func _gen_machine_inputs() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var batches: int = int(sim.bal["machine_input_batches"])
	var food_days := -1.0
	# V4: research-pack machines leave an item alone while a planned structure waits for it
	# (a fabricator waited ten days for 2 electronics while every unit became packs).
	var starved := {}
	if bool(sim.bal.get("packs_yield_to_sites", false)):
		for sid in blds:
			var sb: Dictionary = blds[sid]
			if sb["state"] == "blueprint" and String(sb["block"]).begins_with("materials:"):
				starved[String(sb["block"]).substr(10)] = true
	# ...and a machine that makes such an item takes its inputs first (at work speed 1.05 the
	# electronics fab waited eight days for silicate while the glassworks took every unit, and
	# the fabricator for the Meridian's plates waited for its electronics).
	var order: Array = blds.keys()
	if not starved.is_empty():
		var first: Array = []
		var rest: Array = []
		for id in order:
			var ob: Dictionary = blds[id]
			var orec: Dictionary = sim.prod.recipe_of(ob) if ob["state"] == "active" and int(ob["inv_in"]) != -1 else {}
			if not orec.is_empty() and _makes_any(orec, starved):
				first.append(id)
			else:
				rest.append(id)
		order = first + rest
	for id in order:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or int(b["inv_in"]) == -1 or not bool(b["enabled"]) or bool(b["demolish"]) or _parked(b):
			continue
		var rec: Dictionary = sim.prod.recipe_of(b)
		if rec.is_empty():
			continue
		var wants := {}
		if bool(rec.get("menu", false)):
			wants = sim.prod.kitchen_wants(b)
			# Crops for a kitchen are urgent while the colony has less than a day of food.
			if food_days < 0.0:
				food_days = float(sim.metrics.forecast()["meal_days"])
			_fill(b["inv_in"], wants, rec["category"], id, 3 if food_days < 1.0 else 1, b["pos"], 4)
			continue
		# A machine whose output stock is full does not hoard inputs (V3: steel for the ship).
		if sim.prod._output_stock_full(rec):
			continue
		if not starved.is_empty() and bool(rec.get("auto", false)) and _uses_any(rec, starved):
			continue
		for res in rec["inputs"]:
			wants[res] = int(rec["inputs"][res]) * batches
		# A machine that stands idle for want of input gets its goods first.
		var idle: bool = not sim.prod.has_batch(b) and String(b["block"]) == "no_input"
		var em: int = 1 if idle else 0
		if not starved.is_empty() and _makes_any(rec, starved):
			em = 2
		_fill(b["inv_in"], wants, rec["category"], id, em, b["pos"], 3)

static func _makes_any(rec: Dictionary, items: Dictionary) -> bool:
	for res in rec.get("outputs", {}):
		if items.has(res):
			return true
	return false

static func _uses_any(rec: Dictionary, items: Dictionary) -> bool:
	for res in rec["inputs"]:
		if items.has(res):
			return true
	return false

## Research labs: the items of a special project go to the first lab; scientists work.
func _gen_research() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var labs: Array = []
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] == "active" and bool(sim.bdef(b["def"]).get("research_lab", false)) and not bool(b["demolish"]):
			labs.append(b)
	if labs.is_empty():
		return
	var need: Dictionary = sim.research.items_needed()
	var first: Dictionary = labs[0]
	if not need.is_empty() and not _parked(first) and int(first["inv_in"]) != -1:
		if not sim.research.pay_from(first):
			_fill(first["inv_in"], need, "industry", first["id"], 0, first["pos"], 3)
	var role: String = "scientist" if bool(sim.bal["research"].get("scientist_only", true)) else ""
	var workable: bool = sim.research.workable()
	# Research packs (v3): every lab keeps a few of each pack its project uses.
	var pk: Dictionary = sim.research.lab_packs()
	var stock: int = int(sim.bal["research"].get("lab_pack_stock", 4))
	for b in labs:
		if String(sim.state["research"]["active"]) == "":
			b["block"] = "no_project"
			continue
		if not workable:
			b["block"] = "waiting_items"
			continue
		if not pk.is_empty() and int(b["inv_in"]) != -1 and not _parked(b) and bool(b["enabled"]):
			var wants := {}
			var cap_each: int = maxi(1, int(sim.bd(b).get("input_cap", 12)) / maxi(1, pk.size()))
			for item in pk:
				wants[item] = mini(stock, cap_each)
			_fill(b["inv_in"], wants, "industry", b["id"], 0, b["pos"], 3)
		if not bool(b["enabled"]):
			b["block"] = "disabled"
			continue
		if not bool(b["powered"]):
			b["block"] = "no_power"
			continue
		if not sim.research.lab_can_work(b):
			b["block"] = "no_packs"
			continue
		b["block"] = ""
		if _parked(b):
			continue
		var slots: int = int(sim.bd(b).get("work_slots", 1))
		while int(_count.get("research:%d" % b["id"], 0)) < slots:
			_new_task("research", "industry", b["id"], {"role": role})

## Medical bays keep a little medicine, which doubles healing.
func _gen_medical() -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or int(b["inv_in"]) == -1 or bool(b["demolish"]) or _parked(b):
			continue
		if int(sim.bd(b).get("treatment_beds", 0)) <= 0:
			continue
		_fill(b["inv_in"], {"medicine": mini(2, int(sim.bd(b)["input_cap"]))}, "logistics", id, 0, b["pos"], 1)

func _gen_dining() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var below: int = int(sim.bal["dining_restock_below"])
	var dishes: Array = sim.items.dishes()
	for id in blds:
		var b: Dictionary = blds[id]
		# A broken kitchen cannot cook, but people still eat there (agents._try_eat): it is
		# restocked from storage like any dining room (SIM 2026-09-30: with the only kitchen
		# broken and no spares, stored meals never came and the colony starved).
		if (b["state"] != "active" and b["state"] != "broken") or not bool(sim.bdef(b["def"]).get("dining", false)) or bool(b["demolish"]) or _parked(b):
			continue
		var have: int = sim.inv.count_any(b["inv_out"], dishes) + _inb_any(b["inv_out"], dishes)
		if have >= below:
			continue
		# A kitchen that can cook feeds its own dining room: no dishes come back from storage.
		if sim.prod.recipe_of(b).get("menu", false) and have > 0 and sim.prod.machine_block(b) == "":
			continue
		var need: int = below + 2 - have
		var tries := 0
		while need > 0 and int(_open_hauls.get(b["inv_out"], 0)) < 3 and tries < 4:
			tries += 1
			# Bring the dish this dining room lacks most: variety first.
			var best := -1
			var best_res := ""
			var best_key := 1e18
			for d in dishes:
				var src: int = find_source(d, b["pos"], b["inv_out"])
				if src == -1:
					continue
				var key: float = float(sim.inv.count(b["inv_out"], d) + _inb(b["inv_out"], d)) * 1000.0 + sim.inv.position_of(src).distance_to(b["pos"])
				if key < best_key:
					best_key = key
					best = src
					best_res = d
			if best == -1:
				break
			var qty: int = mini(int(sim.bal["carry_human"]), mini(need, sim.inv.available(best, best_res)))
			qty = mini(qty, sim.inv.free_space(b["inv_out"]))
			var urgent: int = 4 if have == 0 else 0
			if qty <= 0 or not _make_haul("food", best, b["inv_out"], best_res, qty, id, urgent):
				break
			need -= qty

func _gen_water_fill() -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or int(b["inv_fill"]) == -1 or bool(b["demolish"]):
			continue
		if not sim.topo.power_comp.has(id):
			continue
		var comp: int = sim.topo.power_comp[id]
		var ws: Dictionary = sim.util.water_stats.get(comp, {})
		if ws.is_empty():
			continue
		var fp: int = sim.util.fp()
		var room_units: int = (int(ws["cap"]) - int(ws["stock"])) / fp - sim.inv.count(b["inv_fill"], "water") - _inb(b["inv_fill"], "water")
		while room_units >= 2 and int(_open_hauls.get(b["inv_fill"], 0)) < 3:
			var src: int = find_source("water", b["pos"])
			if src == -1:
				break
			var qty: int = mini(int(sim.bal["carry_human"]), mini(room_units, sim.inv.available(src, "water")))
			qty = mini(qty, sim.inv.free_space(b["inv_fill"]))
			if qty <= 0 or not _make_haul("logistics", src, b["inv_fill"], "water", qty, id, 1):
				break
			room_units -= qty

## Moves goods to a storehouse: lander cargo, full machine outputs and ground piles, and
## food from ordinary storage into cold storage.
func _gen_clearing() -> void:
	var stores: Array = _stores_with_space(true)
	if stores.is_empty():
		return
	# Lander cargo is moved only while the stores keep room for what the colony produces.
	# Without this, 162 units of cargo fill the first storehouse and every machine blocks.
	var free_total := 0
	for s_id in stores:
		free_total += sim.inv.free_space(s_id)
	var unload_ok: bool = free_total > int(sim.bal.get("unload_keep_free_units", 40))
	var invs: Dictionary = sim.state["inventories"]
	var blds: Dictionary = sim.state["buildings"]
	var carry: int = int(sim.bal["carry_human"])
	var keep: int = int(sim.bal.get("kitchen_keep_meals", 8))
	var dishes: Array = sim.items.dishes()
	var made := 0
	var cold_moves := 0
	for inv_id in invs.keys():
		if made >= 4:
			break
		var inv: Dictionary = invs[inv_id]
		var role: String = inv["role"]
		var cat := "logistics"
		var cold_only := false
		if _source_resting(inv_id):
			continue
		if role == "store":
			if inv["ot"] != "b":
				continue
			var owner_def: String = String(blds.get(inv["oid"], {}).get("def", ""))
			if owner_def == "lander":
				if not unload_ok:
					continue
			elif _cold.is_empty() or _cold.has(inv_id) or cold_moves >= 2:
				continue
			else:
				cold_only = true
		elif role == "out":
			var ob: Dictionary = blds.get(inv["oid"], {})
			if ob.is_empty():
				continue
			cat = sim.bdef(ob["def"]).get("category", "industry")
			if cat != "food":
				cat = "industry"
			if bool(sim.bdef(ob["def"]).get("dining", false)):
				# Dishes stay where people eat. They move out only when the kitchen is nearly
				# full, or into cold storage, where they keep.
				if not _surplus_dishes(inv_id):
					continue
				if _cold.is_empty() and sim.inv.free_space(inv_id) >= KITCHEN_CLEAR_FREE:
					continue
		elif role != "pile":
			continue
		elif _far_piles.has(inv_id):
			continue
		for res in inv["items"].keys():
			if res == "water":
				continue
			var perishable: bool = sim.items.shelf_days(res) > 0.0
			if cold_only and not perishable:
				continue
			var avail: int = sim.inv.available(inv_id, res)
			if role == "out" and dishes.has(res):
				# Leave enough dishes in the kitchen for the people who eat there.
				avail = mini(avail, sim.inv.count_any(inv_id, dishes) - keep)
			if avail <= 0:
				continue
			# Machine outputs are moved only in full loads, so carriers do not run for one unit.
			if role == "out" and avail < carry and sim.inv.free_space(inv_id) > 2:
				continue
			var dst: int = _nearest_store(stores, sim.inv.position_of(inv_id), perishable, cold_only)
			if dst == -1 or dst == inv_id:
				continue
			if _pending_from(inv_id) >= 2:
				break
			var qty: int = mini(carry, mini(avail, sim.inv.free_space(dst)))
			if qty > 0 and _make_haul(cat, inv_id, dst, res, qty, -1, 0):
				made += 1
				if cold_only:
					cold_moves += 1
			break

func _pending_from(inv_id: int) -> int:
	var n := 0
	var tasks: Dictionary = sim.state["tasks"]
	for tid in tasks:
		var t: Dictionary = tasks[tid]
		if t["kind"] == "haul" and int(t["src"]) == inv_id and not bool(t["picked"]):
			n += 1
	return n

## The nearest store with room. Perishable goods go to cold storage when it has room.
func _nearest_store(stores: Array, near: Vector2, perishable: bool = false, cold_only: bool = false) -> int:
	var best := -1
	var best_d := 1e18
	for pass_i in 2:
		var want_cold: bool = perishable and pass_i == 0
		if pass_i == 1 and (cold_only or best != -1):
			break
		for s in stores:
			if want_cold and not _cold.has(s):
				continue
			if sim.inv.free_space(s) <= 0:
				continue
			var d: float = sim.inv.position_of(s).distance_to(near)
			if d < best_d:
				best_d = d
				best = s
		if not perishable:
			break
	return best

func _gen_operate() -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or bool(b["demolish"]) or _parked(b):
			continue
		var rec: Dictionary = sim.prod.recipe_of(b)
		if rec.is_empty() or sim.prod.is_auto_recipe(b):
			continue
		var block: String = sim.prod.machine_block(b)
		b["block"] = block
		if block != "":
			continue
		var slots: int = int(sim.bd(b).get("work_slots", 1))
		while int(_count.get("operate:%d" % id, 0)) < slots:
			_new_task("operate", rec["category"], id, {"role": rec["role"]})

func _gen_tend() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var totals := {}
	var limit: int = maxi(int(sim.bal["nutrition"].get("crop_stock_min", 20)), int(float(sim.alive_count()) * float(sim.bal["nutrition"].get("crop_stock_per_colonist", 1.5))))
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or (b["trays"] as Array).is_empty() or not bool(b["enabled"]) or bool(b["demolish"]) or _parked(b):
			continue
		for i in (b["trays"] as Array).size():
			var tray: Dictionary = b["trays"][i]
			if int(_count.get("tend:%d:%d" % [id, i], 0)) > 0:
				continue
			if tray["state"] == "empty" and bool(b["powered"]) and sim.util.water_available(id, 2):
				# Growers do not plant a crop that the colony already has plenty of: it
				# would only spoil in storage.
				if totals.is_empty():
					totals = sim.inv.totals()
				var crop: String = sim.prod.seed_crop(b, tray)
				if int(totals.get(crop, {}).get("total", 0)) >= limit:
					continue
				_new_task("tend", "food", id, {"tray": i, "op": "seed", "role": "grower"})
			elif tray["state"] == "ready":
				_new_task("tend", "food", id, {"tray": i, "op": "harvest", "role": "grower"})

func _gen_repair() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var trigger: float = float(sim.bal["repair_trigger_health"])
	var cand: Array = []
	for id in blds:
		var b0: Dictionary = blds[id]
		if b0["kind"] == "special" or bool(b0["demolish"]):
			continue
		if b0["state"] != "active" and b0["state"] != "broken":
			continue
		if float(b0["health"]) >= trigger and b0["state"] != "broken":
			continue
		if int(_count.get("repair:%d" % id, 0)) > 0:
			continue
		cand.append(id)
	if cand.is_empty():
		return
	# V5 18.1 (diagnosis RC6): with fewer free parts than structures that need one, the parts go to the most
	# urgent first (a broken life-support structure, a broken one, then the lowest health), not to the lowest id;
	# one part stays for the maintenance of a machine that is at risk. With enough parts nothing changes.
	var allowed: Dictionary = _allot_parts(cand)
	for id in cand:
		var b: Dictionary = blds[id]
		if not allowed.is_empty() and not allowed.has(id):
			continue
		# A wear breakdown needs the item of its fault (V3): spare parts, electronics or polymer.
		var item: String = sim.hazards.repair_item(b)
		var src: int = find_source(item, b["pos"])
		if src == -1:
			if b["state"] == "broken":
				b["block"] = "no_spares"
			continue
		var urgent := 0
		if b["state"] == "broken":
			urgent = 8 if sim.bdef(b["def"]).get("category", "") == "life_support" else 3
		var t: Dictionary = _new_task("repair", "repair", id, {"role": "technician", "src": src, "res": item, "qty": 1, "emergency": urgent})
		var ho: int = sim.inv.hold_out(src, item, 1, t["id"])
		if ho == -1:
			sim.state["tasks"].erase(t["id"])
		else:
			t["hold_out"] = ho

# ---------------------------------------------------------------- orders (V5 section 18.1)
## The task that carries out a repair order on structure bid. what: "repair" | "maintain" | "patch" | "clean".
## Returns {task} (an open task is taken, a task another colonist has only started to walk to is taken from them,
## or a new one is made), {missing: item, qty, reason: "none" | "reserved" | "unreachable", where} (no part can
## be had; a part that other repairs only hold is taken from the least urgent of them first), or {busy: true}.
func order_task(bid: int, what: String, agent_id: int) -> Dictionary:
	var tasks: Dictionary = sim.state["tasks"]
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty():
		return {"busy": true}
	for tid in tasks:
		var t: Dictionary = tasks[tid]
		if int(t["bld"]) != bid or t["kind"] != what:
			continue
		var owner: int = int(t["owner"])
		if owner == -1 or owner == agent_id:
			return {"task": t}
		if bool(t["picked"]):
			return {"busy": true}
		# Another colonist has only started to walk to it: the order takes it (agents.begin_task).
		return {"task": t}
	var hz = sim.hazards
	match what:
		"clean":
			return {"task": _new_task("clean", "repair", bid, {})}
		"repair", "maintain", "patch":
			var item: String
			var qty := 1
			var emergency := 0
			if what == "repair":
				item = hz.repair_item(b)
				if b["state"] == "broken":
					emergency = 8 if sim.bdef(b["def"]).get("category", "") == "life_support" else 3
			elif what == "maintain":
				item = hz.fault_item(String(hz.wear_of(bid)["fault"]))
				emergency = 6
			else:
				var bc: Dictionary = sim.bal["hazards"]["breach"]
				item = String(bc["item"])
				emergency = 5
				if find_source(item, b["pos"], -1, true) == -1 and part_stock(item)["free"] <= 0:
					item = String(bc["alt_item"])
					qty = int(bc["alt_qty"])
			var src: int = find_source(item, b["pos"], -1, true)
			# Every free unit is held by another repair: the order takes one from the least urgent of them.
			if src == -1 or sim.inv.available(src, item) < qty:
				if _take_reserved(item, qty):
					src = find_source(item, b["pos"], -1, true)
			if src == -1 or sim.inv.available(src, item) < qty:
				var st: Dictionary = part_stock(item)
				return {"missing": item, "qty": qty, "reason": _why_missing(st), "where": st["where"]}
			var t2: Dictionary = _new_task(what, "repair", bid, {"role": "technician", "src": src, "res": item, "qty": qty, "emergency": emergency})
			var ho: int = sim.inv.hold_out(src, item, qty, t2["id"])
			if ho == -1:
				tasks.erase(t2["id"])
				return {"missing": item, "qty": qty, "reason": "reserved", "where": Vector2.ZERO}
			t2["hold_out"] = ho
			return {"task": t2}
	return {"busy": true}

## Why an item cannot be had: "elsewhere" (free stock exists, but at another base), "reserved" (other tasks hold it),
## "unreachable" (nobody can walk to it) or "none" (the colony has none).
func _why_missing(st: Dictionary) -> String:
	if int(st["free"]) > 0:
		return "elsewhere"
	if int(st["reserved"]) > 0:
		return "reserved"
	if int(st["unreachable"]) > 0:
		return "unreachable"
	return "none"

## What the colony has of an item, by where it is: {free (can be taken now), reserved (held by tasks), unreachable
## (in a store or pile that nobody can walk to), where (position of the unreachable stock)}.
func part_stock(item: String) -> Dictionary:
	var free := 0
	var reserved := 0
	var unreach := 0
	var where := Vector2.ZERO
	for inv_id in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		var role: String = inv["role"]
		if role != "pile" and role != "out" and role != "store":
			continue
		var n: int = int(inv["items"].get(item, 0))
		if n <= 0:
			continue
		if _source_resting(int(inv_id)):
			unreach += n
			where = sim.inv.position_of(int(inv_id))
			continue
		var held: int = int(inv["held_out"].get(item, 0))
		free += n - held
		reserved += held
	return {"free": free, "reserved": reserved, "unreachable": unreach, "where": where}

## Releases the hold of one unowned repair task that holds `item` (the least urgent: lowest emergency, then the
## highest structure id) and ends the task, so that an order can take the unit. Returns true when one was freed.
func _take_reserved(item: String, qty: int) -> bool:
	var best_tid := -1
	var best_key := Vector2(1e9, 0.0)
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] != "repair" and t["kind"] != "maintain" and t["kind"] != "patch":
			continue
		if int(t["owner"]) != -1 or bool(t["picked"]) or int(t["hold_out"]) == -1 or String(t["res"]) != item or int(t["qty"]) < qty:
			continue
		var key := Vector2(float(t["emergency"]), -float(t["bld"]))
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best_tid = int(tid)
	if best_tid == -1:
		return false
	fail(best_tid, "part_taken")
	return true

## The open task of any kind at structure bid that the colonist can work at (the best score first; no role gate:
## an order decides, not the role).
func best_task_at(bid: int, agent: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_s := -1e18
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if int(t["bld"]) != bid or int(t["owner"]) != -1 or t["state"] != "open":
			continue
		var s: float = 100.0 * float(int(sim.state["policies"]["priority"].get(t["cat"], 1))) + 50.0 * float(t["emergency"]) - float(t["id"]) * 0.000001
		if s > best_s:
			best_s = s
			best = t
	return best

## Tasks (any state) at a structure: the order check asks if there is work.
func tasks_at(bid: int) -> int:
	var n := 0
	for tid in sim.state["tasks"]:
		if int(sim.state["tasks"][tid]["bld"]) == bid:
			n += 1
	return n

## The inventory a haul order fills at structure b (the site of a plan, a machine's input, else its store).
func order_inv(b: Dictionary) -> int:
	if b["state"] == "blueprint" and int(b["inv_site"]) != -1:
		return int(b["inv_site"])
	if int(b["inv_in"]) != -1:
		return int(b["inv_in"])
	return int(b["inv_out"])

## One trip of a haul order: carry up to `qty` of res to structure bid. Returns {task, qty}, {missing: res}
## (no store has it) or {full: true} (the place has no room).
func order_haul(res: String, qty: int, bid: int) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty():
		return {"full": true}
	var dst: int = order_inv(b)
	if dst == -1:
		return {"full": true}
	var src: int = find_source(res, b["pos"], dst, true)
	if src == -1:
		return {"missing": res, "reason": _why_missing(part_stock(res))}
	var q: int = mini(int(sim.bal["carry_human"]), mini(qty, sim.inv.available(src, res)))
	q = mini(q, sim.inv.free_space(dst))
	if q <= 0:
		return {"full": true}
	no_divert = true
	var made: bool = _make_haul("logistics", src, dst, res, q, bid, 0)
	no_divert = false
	if not made:
		return {"full": true}
	var last: Dictionary = {}
	for tid in sim.state["tasks"]:
		last = sim.state["tasks"][tid]
	return {"task": last, "qty": q}

## The open task of kind `kind` at structure bid with the lowest id (a build order takes site work).
func open_task_at(bid: int, kind: String) -> Dictionary:
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if int(t["bld"]) == bid and t["kind"] == kind and int(t["owner"]) == -1 and t["state"] == "open":
			t["retry"] = 0
			return t
	return {}

## Free units of an item, counted once for each pass of the board (the index resets it).
var _free_cache := {}
func free_parts(item: String) -> int:
	if not _free_cache.has(item):
		_free_cache[item] = int(part_stock(item)["free"])
	return int(_free_cache[item])

## The structures that get a part now ({id: true}), or {} when there are enough parts for all of them.
func _allot_parts(cand: Array) -> Dictionary:
	if cand.size() < 2:
		return {}
	var blds: Dictionary = sim.state["buildings"]
	var by_item := {}
	for id in cand:
		var item: String = sim.hazards.repair_item(blds[id])
		if not by_item.has(item):
			by_item[item] = []
		by_item[item].append(id)
	var limited := false
	var allowed := {}
	var items: Array = by_item.keys()
	items.sort()
	for item in items:
		var ids: Array = by_item[item]
		var free: int = free_parts(item)
		if ids.size() <= free:
			for id in ids:
				allowed[id] = true
			continue
		limited = true
		ids.sort_custom(func(x, y):
			var kx: Array = _repair_rank(blds[x])
			var ky: Array = _repair_rank(blds[y])
			if kx[0] != ky[0]:
				return kx[0] > ky[0]
			if kx[1] != ky[1]:
				return kx[1] < ky[1]
			return int(x) < int(y))
		var keep: int = 1 if _machine_at_risk() else 0
		var n: int = free
		for id in ids:
			if n <= 0:
				break
			if blds[id]["state"] != "broken" and n <= keep:
				continue
			allowed[id] = true
			n -= 1
	return allowed if limited else {}

## [urgency, health] of a structure that needs a repair (higher urgency first, then the lowest health).
func _repair_rank(b: Dictionary) -> Array:
	var u := 0
	if b["state"] == "broken":
		u = 2 if sim.bdef(b["def"]).get("category", "") == "life_support" else 1
	return [u, float(b["health"])]

## True when a machine wants maintenance and no maintenance task serves it yet.
func _machine_at_risk() -> bool:
	var wear: Dictionary = sim.hazards.hs()["wear"]
	for id in wear:
		var mb: Dictionary = sim.state["buildings"].get(id, {})
		if not mb.is_empty() and int(_count.get("maintain:%d" % id, 0)) == 0 and sim.hazards.wants_maintenance(mb):
			return true
	return false

## V3.1 trade: goods the player sold are carried to the ship's hold on the pad.
func _gen_trade() -> void:
	for w in sim.traffic.delivery_wants():
		var b: Dictionary = sim.state["buildings"].get(int(w[2]), {})
		if b.is_empty():
			continue
		_fill(int(w[0]), w[1], "logistics", int(w[2]), 1, b["pos"], 4)

## Version 3 hazards: maintenance of machines at risk, sealing hull breaches, cleaning
## dusty solar panels, and surveying meteor fragment sites (V3_DESIGN sections 4 and 5).
func _gen_hazard_work() -> void:
	var hz = sim.hazards
	var hc: Dictionary = sim.bal["hazards"]
	var blds: Dictionary = sim.state["buildings"]
	# Only machines that have run have a wear record: look there, not at every structure.
	var wear: Dictionary = hz.hs()["wear"]
	for id in wear:
		var mb: Dictionary = blds.get(id, {})
		if mb.is_empty() or bool(mb["demolish"]) or _parked(mb):
			continue
		if int(_count.get("maintain:%d" % id, 0)) == 0 and hz.wants_maintenance(mb):
			var item: String = hz.fault_item(String(wear[id]["fault"]))
			_item_task("maintain", id, item, 1, 6 if bool(mb.get("maint_first", false)) else 1)
	for id in blds:
		var b: Dictionary = blds[id]
		if not (bool(b.get("breach", false)) or bool(b.get("dust", false))) or bool(b["demolish"]) or _parked(b):
			continue
		if bool(b.get("breach", false)) and (b["state"] == "active" or b["state"] == "broken") and int(_count.get("patch:%d" % id, 0)) == 0:
			var bc: Dictionary = hc["breach"]
			if not _item_task("patch", id, String(bc["item"]), 1, 5):
				_item_task("patch", id, String(bc["alt_item"]), int(bc["alt_qty"]), 5)
		if bool(b.get("dust", false)) and b["state"] == "active" and int(_count.get("clean:%d" % id, 0)) == 0:
			_new_task("clean", "repair", id, {})
	var sites: Dictionary = hz.hs()["sites"]
	if sites.is_empty():
		return
	var open := {}
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] == "survey":
			open[int(t["site"])] = true
	var reach: float = sim.agents.suit_reach_metres()
	for sid in sites:
		var st: Dictionary = sites[sid]
		if bool(st["surveyed"]) or open.has(int(sid)):
			continue
		# A site out of suit range waits for an order or a nearer airlock.
		if not bool(st.get("order", false)) and sim.agents.nearest_air_metres(st["pos"]) > reach:
			continue
		_new_task("survey", "industry", -1, {"role": "scientist", "site": int(sid), "emergency": 1 if bool(st.get("order", false)) else 0})

## A task that fetches `qty` of `item` and brings it to structure `bid` (maintenance and
## breach repair). Returns false when no unit is free anywhere.
func _item_task(kind: String, bid: int, item: String, qty: int, emergency: int) -> bool:
	var b: Dictionary = sim.state["buildings"][bid]
	var src: int = find_source(item, b["pos"])
	if src == -1 or sim.inv.available(src, item) < qty:
		return false
	var t: Dictionary = _new_task(kind, "repair", bid, {"role": "technician", "src": src, "res": item, "qty": qty, "emergency": emergency})
	var ho: int = sim.inv.hold_out(src, item, qty, t["id"])
	if ho == -1:
		sim.state["tasks"].erase(t["id"])
		return false
	t["hold_out"] = ho
	return true

func _gen_demolish() -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if not bool(b["demolish"]):
			continue
		if float(b["progress"]) >= sim.build.demolish_work_total(b):
			continue
		if not sim.build.occupants(id).is_empty():
			b["block"] = "occupied"
			continue
		while int(_count.get("demolish:%d" % id, 0)) < 2:
			_new_task("demolish", "construction", id, {})

## Empty ground piles (a delivered pod, a cleared drop) are removed every ten seconds.
func _clean_piles() -> void:
	var invs: Dictionary = sim.state["inventories"]
	var empty: Array = []
	for inv_id in invs:
		var inv: Dictionary = invs[inv_id]
		if inv["role"] == "pile" and (inv["items"] as Dictionary).is_empty() and int(inv["held_in"]) == 0:
			empty.append(inv_id)
	for inv_id in empty:
		sim.inv.remove_if_empty_pile(inv_id)

# ---------------------------------------------------------------- lifecycle
func _expire() -> void:
	var tasks: Dictionary = sim.state["tasks"]
	var blds: Dictionary = sim.state["buildings"]
	var holds: Dictionary = sim.state["holds"]
	var agents: Dictionary = sim.state["agents"]
	for tid in tasks.keys():
		if not tasks.has(tid):
			continue
		var t: Dictionary = tasks[tid]
		var owner: int = int(t["owner"])
		if owner != -1 and (not agents.has(owner) or agents[owner]["state"] != "alive" or int(agents[owner]["task"]) != tid):
			# The owner died or dropped it without saying so: free the claim.
			if bool(t["picked"]):
				fail(tid, "owner_lost")
				continue
			t["owner"] = -1
			t["state"] = "open"
			owner = -1
		if int(t["bld"]) != -1 and not blds.has(t["bld"]):
			fail(tid, "target_gone")
			continue
		if t["kind"] == "haul":
			if not bool(t["picked"]) and not holds.has(t["hold_out"]):
				fail(tid, "source_gone")
				continue
			# A haul between two bases that nobody has picked up (made before the rule in
			# find_source, in an old save) is let go, so its goods are free again.
			if not bool(t["picked"]) and sim.bases.count() > 1 and _cross_base(t):
				fail(tid, "other_base")
				continue
			if not holds.has(t["hold_in"]):
				fail(tid, "destination_gone")
				continue
		elif t["kind"] == "repair" or t["kind"] == "maintain" or t["kind"] == "patch":
			if not bool(t["picked"]) and not holds.has(t["hold_out"]):
				fail(tid, "source_gone")
				continue
		if owner == -1:
			var b: Dictionary = blds.get(t["bld"], {})
			match t["kind"]:
				"operate":
					if sim.prod.machine_block(b) != "":
						fail(tid, "machine_blocked")
				"tend":
					var tray: Dictionary = b["trays"][t["tray"]] if (b["trays"] as Array).size() > int(t["tray"]) else {}
					var want: String = "empty" if t["op"] == "seed" else "ready"
					if tray.is_empty() or tray["state"] != want or not bool(b["enabled"]):
						fail(tid, "tray_changed")
				"build":
					if b["state"] != "building":
						fail(tid, "done")
				"repair":
					if float(b["health"]) >= 100.0 and b["state"] != "broken":
						fail(tid, "done")
				"maintain":
					if not sim.hazards.wants_maintenance(b):
						fail(tid, "done")
				"patch":
					if not bool(b.get("breach", false)):
						fail(tid, "done")
				"clean":
					if not bool(b.get("dust", false)) or b["state"] != "active":
						fail(tid, "done")
				"survey":
					var site: Dictionary = sim.hazards.hs()["sites"].get(int(t.get("site", -1)), {})
					if site.is_empty() or bool(site["surveyed"]):
						fail(tid, "done")
				"demolish":
					if not bool(b["demolish"]):
						fail(tid, "done")
				"upgrade":
					var u: Dictionary = b.get("upgrade", {})
					if u.is_empty() or u["state"] != "work":
						fail(tid, "done")
				"vbuild":
					var vo: Dictionary = b.get("vorder", {})
					if vo.is_empty() or vo["state"] != "work":
						fail(tid, "done")
				"research":
					if not sim.research.lab_can_work(b) or b["state"] != "active" or not bool(b["powered"]) or not bool(b["enabled"]):
						fail(tid, "no_project")
				"shipwork":
					if sim.ship.work_kind() == "" or bool(sim.state["ship"].get("away", false)):
						fail(tid, "done")

func claim(t: Dictionary, agent: Dictionary) -> void:
	t["reason"] = ""
	t["owner"] = agent["id"]
	t["state"] = "reserved"
	agent["task"] = t["id"]

## Gives an unfinished task back to the board. Cargo already picked up must be handled
## by the caller first (drop or keep), because a picked haul cannot simply reopen.
func release(tid: int, reason: String, backoff_seconds: float = 0.0) -> void:
	var tasks: Dictionary = sim.state["tasks"]
	if not tasks.has(tid):
		return
	var t: Dictionary = tasks[tid]
	if bool(t["picked"]):
		fail(tid, reason)
		return
	t["owner"] = -1
	t["state"] = "open"
	t["reason"] = reason
	t["retry"] = int(sim.state["tick"]) + int(backoff_seconds * float(sim.bal["tick_hz"]))

func complete(tid: int) -> void:
	var tasks: Dictionary = sim.state["tasks"]
	if not tasks.has(tid):
		return
	var t: Dictionary = tasks[tid]
	sim.inv.release_owner(tid)
	var m: Dictionary = sim.state["metrics"]["tasks_done"]
	m[t["kind"]] = int(m.get(t["kind"], 0)) + 1
	tasks.erase(tid)

func fail(tid: int, reason: String) -> void:
	var tasks: Dictionary = sim.state["tasks"]
	if not tasks.has(tid):
		return
	var t: Dictionary = tasks[tid]
	sim.inv.release_owner(tid)
	var owner: int = int(t["owner"])
	tasks.erase(tid)
	if owner != -1 and sim.state["agents"].has(owner):
		sim.agents.on_task_lost(sim.state["agents"][owner], tid, reason)

## The goods of a haul or repair cannot be reached from inside the base. The task ends,
## and its source is not offered again for a minute (state.unreach_src: inventory -> tick).
func source_unreachable(t: Dictionary) -> void:
	if not sim.state.has("unreach_src"):
		sim.state["unreach_src"] = {}
	var us: Dictionary = sim.state["unreach_src"]
	var tick: int = int(sim.state["tick"])
	for k in us.keys():
		if int(us[k]) <= tick:
			us.erase(k)
	us[int(t["src"])] = tick + SOURCE_REST_SECONDS * int(sim.bal["tick_hz"])
	fail(t["id"], "source_unreachable")

const SOURCE_REST_SECONDS := 60

func _source_resting(inv_id: int) -> bool:
	var us: Dictionary = sim.state.get("unreach_src", {})
	return not us.is_empty() and int(us.get(inv_id, -1)) > int(sim.state["tick"])

## A route could not be found. After a few tries the target is parked as unreachable
## until the walking graph changes: one persistent issue, not a retry every tick.
func path_failed(t: Dictionary) -> void:
	t["fails"] = int(t["fails"]) + 1
	if int(t["fails"]) < int(sim.bal["task_max_path_fails"]):
		return
	var blds: Dictionary = sim.state["buildings"]
	if int(t["bld"]) != -1 and blds.has(t["bld"]):
		var b: Dictionary = blds[t["bld"]]
		# V4 (Paul: "OUT OF REACH" beside an airlock): the failures may come from where the
		# colonists stood (a walk re-planned from a cell that a new neighbour just closed), not from
		# the structure. It is marked only when no airlock with air has a way to it either; else only
		# this task fails and the work goes on.
		var outdoor: bool = b["state"] == "blueprint" or b["state"] == "building" or b["kind"] == "exterior"
		if b["kind"] != "link" and outdoor and _walk_from_airlock(b):
			t["fails"] = 0
			fail(t["id"], "no_path")
			return
		var again: bool = int(b.get("unreach_logged", -2)) == int(sim.state["rev"]["walk"])
		if int(b.get("unreach_rev", -1)) != int(sim.state["rev"]["walk"]):
			b["unreach_n"] = int(b.get("unreach_n", 0)) + 1      # a new episode of "unreachable" (V5 19.1)
		b["unreach_rev"] = int(sim.state["rev"]["walk"])
		b["unreach_tick"] = int(sim.state["tick"])
		b["unreach_logged"] = int(sim.state["rev"]["walk"])
		b["block"] = "unreachable"
		if not again:
			sim.log_event("unreachable", "%s cannot be reached on foot yet. A room needs a corridor route to an airlock. Work on it waits until the map changes." % b["name"], [b["id"]], 1)
		cancel_tasks_for_building(t["bld"], "unreachable")
	else:
		fail(t["id"], "unreachable")

## A cheap check for path_failed (the frame budget): is there a walk from the nearest airlock with
## air to one of the structure's two nearest access points? Kept per structure until the walking
## graph changes.
func _walk_from_airlock(b: Dictionary) -> bool:
	var rev: int = int(sim.state["rev"]["walk"])
	if int(b.get("walk_ok_rev", -1)) == rev:
		return bool(b["walk_ok"])
	var ok := false
	var c: Vector2 = b["pos"]
	var best_lock := -1
	var best_d := 1e18
	for comp in sim.topo.locks_by_comp:
		if sim.util.comp_supplied(comp):
			for lid in sim.topo.locks_by_comp[comp]:
				var d: float = sim.nav.door_pos(sim.state["buildings"][lid]).distance_squared_to(c)
				if d < best_d or (d == best_d and int(lid) < best_lock):
					best_d = d
					best_lock = int(lid)
	if best_lock != -1:
		var door: Vector2 = sim.nav.door_pos(sim.state["buildings"][best_lock])
		var pts: Array = sim.nav.access_points(b)
		pts.sort_custom(func(x, y): return (x as Vector2).distance_squared_to(door) < (y as Vector2).distance_squared_to(door))
		for q in pts.slice(0, 2):
			if bool(sim.nav.path_out(door, q)["ok"]):
				ok = true
				break
	b["walk_ok_rev"] = rev
	b["walk_ok"] = ok
	return ok

func cancel_tasks_for_building(bid: int, reason: String) -> void:
	var tasks: Dictionary = sim.state["tasks"]
	var invs: Dictionary = sim.state["inventories"]
	for tid in tasks.keys():
		if not tasks.has(tid):
			continue
		var t: Dictionary = tasks[tid]
		var hit: bool = int(t["bld"]) == bid
		if not hit:
			for key in ["src", "dst"]:
				var inv: Dictionary = invs.get(t[key], {})
				if not inv.is_empty() and inv["ot"] == "b" and int(inv["oid"]) == bid:
					hit = true
		if hit:
			fail(tid, reason)

## Cancels the tasks that bring units to (or take units from) one inventory.
func cancel_tasks_for_inventory(inv_id: int, reason: String) -> void:
	var tasks: Dictionary = sim.state["tasks"]
	for tid in tasks.keys():
		if not tasks.has(tid):
			continue
		var t: Dictionary = tasks[tid]
		if int(t["src"]) == inv_id or int(t["dst"]) == inv_id:
			fail(tid, reason)

## Cancels the upgrade work of a building and the hauls into its upgrade inventory.
func cancel_upgrade_tasks(bid: int, upg_inv: int, kind: String = "upgrade") -> void:
	var tasks: Dictionary = sim.state["tasks"]
	for tid in tasks.keys():
		if not tasks.has(tid):
			continue
		var t: Dictionary = tasks[tid]
		if (t["kind"] == kind and int(t["bld"]) == bid) or (upg_inv != -1 and int(t["dst"]) == upg_inv):
			fail(tid, "upgrade_ended")

## The base a task belongs to (V4): its structure's base, else the base where its goods
## are. Kept per task until the structures or links change.
var _tb := {}
var _tb_key := ""

func task_base(t: Dictionary) -> int:
	var key: String = "%d:%d:%d" % [sim.state["buildings"].size(), int(sim.state["rev"]["power"]), sim.bases.count()]
	if key != _tb_key:
		_tb_key = key
		_tb = {}
	var tid: int = int(t["id"])
	var got = _tb.get(tid)
	if got != null:
		return int(got)
	var b := -1
	if int(t.get("bld", -1)) != -1 and sim.state["buildings"].has(int(t["bld"])):
		b = sim.bases.base_of(int(t["bld"]))
	elif int(t.get("src", -1)) != -1 and sim.inv.exists(int(t["src"])):
		b = sim.bases.base_at(sim.inv.position_of(int(t["src"])))
	elif int(t.get("dst", -1)) != -1 and sim.inv.exists(int(t["dst"])):
		b = sim.bases.base_at(sim.inv.position_of(int(t["dst"])))
	_tb[tid] = b
	return b

func score(t: Dictionary, agent: Dictionary) -> float:
	var prio: int = int(sim.state["policies"]["priority"].get(t["cat"], 1))
	# V4: the colonist's own job priorities (set_jobs) come before the colony's.
	var own = agent.get("jobs")
	if own != null and (own as Dictionary).has(t["cat"]):
		prio = int(own[t["cat"]])
	if prio <= 0:
		return -1e9
	var blds: Dictionary = sim.state["buildings"]
	var target: Vector2 = agent["pos"]
	if t["kind"] == "haul" or t["kind"] == "repair" or t["kind"] == "maintain" or t["kind"] == "patch":
		target = sim.inv.position_of(t["src"]) if not bool(t["picked"]) else sim.inv.position_of(t["dst"])
	elif t["kind"] == "survey":
		target = sim.hazards.hs()["sites"].get(int(t["site"]), {}).get("pos", target)
	if blds.has(t["bld"]):
		var b: Dictionary = blds[t["bld"]]
		prio = clampi(prio + int(b["priority"]) - 1, 1, 3)
		if t["kind"] != "haul" and t["kind"] != "repair" and t["kind"] != "maintain" and t["kind"] != "patch":
			target = b["pos"]
	var waiting: float = float(int(sim.state["tick"]) - int(t["created"])) / float(sim.bal["tick_hz"])
	var travel: float = (agent["pos"] as Vector2).distance_to(target) / float(sim.bal["speed_outdoor"]) * 1.3
	# One step of priority is 100 points. Waiting adds 0.1 point a second ON PURPOSE: a job at the colony
	# default 1 (logistics) that waits 17 minutes ranks with a new job at 2, so the hauls that feed the
	# kitchens are never starved by busier categories. A strict order (tried 2026-10-03: priority first,
	# then waiting) starved them: the reference campaign ended with 46 deaths. Distance costs 0.74 points
	# a metre; on foot no job is farther than about 100 m (suit range), so it never outweighs a step.
	var s: float = 100.0 * prio + 50.0 * int(t["emergency"]) + 0.1 * waiting - 2.0 * travel
	if t["role"] != "" and t["role"] == agent["role"]:
		s += float(sim.bal.get("specialist_bonus", 30.0))
	# V5 section 18.3: the order of the department queue (pins and holds the player set).
	if sim.workq.busy or sim.workq._dirty:
		s = sim.workq.adjust(t, s, 100.0 * prio + 50.0 * int(t["emergency"]))
	return s
