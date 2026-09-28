extends RefCounted
## Inventories, reservations ("holds") and the conservation ledger (spec 7).
## Every physical unit is in exactly one inventory: a store, a machine buffer, a
## construction site, a carrier or a ground pile. Units change place only through the
## functions here, so the ledger can prove nothing is duplicated or lost (acceptance 1).

var sim

func _init(s) -> void:
	sim = s

# ---------------------------------------------------------------- inventories
func create_inv(owner_type: String, owner_id: int, role: String, cap: int, pos: Vector2 = Vector2.ZERO) -> int:
	var id: int = sim.new_id()
	sim.state["inventories"][id] = {
		"id": id, "ot": owner_type, "oid": owner_id, "role": role, "pos": pos,
		"cap": cap, "items": {}, "held_out": {}, "held_in": 0, "spoil": {},
	}
	return id

func get_inv(inv_id: int) -> Dictionary:
	return sim.state["inventories"].get(inv_id, {})

func exists(inv_id: int) -> bool:
	return sim.state["inventories"].has(inv_id)

func count(inv_id: int, res: String) -> int:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return 0
	return int(inv["items"].get(res, 0))

func total(inv_id: int) -> int:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return 0
	var n := 0
	for r in inv["items"]:
		n += int(inv["items"][r])
	return n

func available(inv_id: int, res: String) -> int:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return 0
	return int(inv["items"].get(res, 0)) - int(inv["held_out"].get(res, 0))

## Unreserved units of any of the listed items (for example every dish).
func available_any(inv_id: int, ids: Array) -> int:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return 0
	var n := 0
	var items: Dictionary = inv["items"]
	var held: Dictionary = inv["held_out"]
	for r in items:
		if ids.has(r):
			n += int(items[r]) - int(held.get(r, 0))
	return n

## Units of any of the listed items, reserved or not.
func count_any(inv_id: int, ids: Array) -> int:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return 0
	var n := 0
	for r in inv["items"]:
		if ids.has(r):
			n += int(inv["items"][r])
	return n

func free_space(inv_id: int) -> int:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return 0
	return int(inv["cap"]) - total(inv_id) - int(inv["held_in"])

func position_of(inv_id: int) -> Vector2:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return Vector2.ZERO
	match inv["ot"]:
		"b":
			var b: Dictionary = sim.state["buildings"].get(inv["oid"], {})
			return b.get("pos", Vector2.ZERO)
		"a":
			var a: Dictionary = sim.state["agents"].get(inv["oid"], {})
			return a.get("pos", Vector2.ZERO)
		"v":
			return sim.vehicles.get_v(int(inv["oid"])).get("pos", inv["pos"])
	return inv["pos"]

# ---------------------------------------------------------------- holds
func hold_out(inv_id: int, res: String, qty: int, owner: int) -> int:
	if qty <= 0 or available(inv_id, res) < qty:
		return -1
	var inv: Dictionary = get_inv(inv_id)
	inv["held_out"][res] = int(inv["held_out"].get(res, 0)) + qty
	var hid: int = sim.new_id()
	sim.state["holds"][hid] = {"inv": inv_id, "res": res, "qty": qty, "dir": "out", "owner": owner}
	return hid

func hold_in(inv_id: int, res: String, qty: int, owner: int) -> int:
	if qty <= 0 or free_space(inv_id) < qty:
		return -1
	var inv: Dictionary = get_inv(inv_id)
	inv["held_in"] = int(inv["held_in"]) + qty
	var hid: int = sim.new_id()
	sim.state["holds"][hid] = {"inv": inv_id, "res": res, "qty": qty, "dir": "in", "owner": owner}
	return hid

func release(hid: int) -> void:
	if hid < 0 or not sim.state["holds"].has(hid):
		return
	var h: Dictionary = sim.state["holds"][hid]
	var inv: Dictionary = get_inv(h["inv"])
	if not inv.is_empty():
		if h["dir"] == "out":
			inv["held_out"][h["res"]] = maxi(0, int(inv["held_out"].get(h["res"], 0)) - int(h["qty"]))
			if int(inv["held_out"][h["res"]]) == 0:
				inv["held_out"].erase(h["res"])
		else:
			inv["held_in"] = maxi(0, int(inv["held_in"]) - int(h["qty"]))
	sim.state["holds"].erase(hid)

func release_owner(owner: int) -> void:
	var ids: Array = []
	for hid in sim.state["holds"]:
		if int(sim.state["holds"][hid]["owner"]) == owner:
			ids.append(hid)
	for hid in ids:
		release(hid)

func release_for_inventory(inv_id: int) -> Array:
	# Returns the owners whose holds were released, so their tasks can be cancelled.
	var owners: Array = []
	var ids: Array = []
	for hid in sim.state["holds"]:
		if int(sim.state["holds"][hid]["inv"]) == inv_id:
			ids.append(hid)
	for hid in ids:
		var o: int = int(sim.state["holds"][hid]["owner"])
		if not owners.has(o):
			owners.append(o)
		release(hid)
	return owners

## Moves the units of an "out" hold into dst (a carrier). The hold ends.
func take_held(hid: int, dst_inv: int) -> bool:
	if not sim.state["holds"].has(hid):
		return false
	var h: Dictionary = sim.state["holds"][hid]
	var src: Dictionary = get_inv(h["inv"])
	var dst: Dictionary = get_inv(dst_inv)
	if src.is_empty() or dst.is_empty() or h["dir"] != "out":
		return false
	var res: String = h["res"]
	var qty: int = int(h["qty"])
	if int(src["items"].get(res, 0)) < qty:
		return false
	release(hid)
	_sub(src, res, qty)
	_add(dst, res, qty)
	return true

## Moves qty of the hold's resource from src (a carrier) into the inventory of an "in" hold.
func put_held(hid: int, src_inv: int) -> bool:
	if not sim.state["holds"].has(hid):
		return false
	var h: Dictionary = sim.state["holds"][hid]
	var dst: Dictionary = get_inv(h["inv"])
	var src: Dictionary = get_inv(src_inv)
	if src.is_empty() or dst.is_empty() or h["dir"] != "in":
		return false
	var res: String = h["res"]
	var qty: int = mini(int(h["qty"]), int(src["items"].get(res, 0)))
	release(hid)
	if qty <= 0:
		return false
	_sub(src, res, qty)
	_add(dst, res, qty)
	return true

## Unreserved move. Respects unreserved stock and free space. Returns the quantity moved.
func move(src_inv: int, dst_inv: int, res: String, qty: int) -> int:
	var n: int = mini(qty, mini(available(src_inv, res), free_space(dst_inv)))
	if n <= 0:
		return 0
	_sub(get_inv(src_inv), res, n)
	_add(get_inv(dst_inv), res, n)
	return n

# ---------------------------------------------------------------- ledger
func add_new(inv_id: int, res: String, qty: int, _reason: String) -> int:
	var n: int = mini(qty, free_space(inv_id))
	if n <= 0:
		return 0
	_add(get_inv(inv_id), res, n)
	_ledger(res, "created", n)
	return n

func add_new_forced(inv_id: int, res: String, qty: int, _reason: String) -> void:
	# For scenario set-up only: ignores capacity.
	_add(get_inv(inv_id), res, qty)
	_ledger(res, "created", qty)

func consume(inv_id: int, res: String, qty: int, _reason: String) -> bool:
	if available(inv_id, res) < qty:
		return false
	_sub(get_inv(inv_id), res, qty)
	_ledger(res, "consumed", qty)
	return true

func consume_held(hid: int, _reason: String) -> bool:
	if not sim.state["holds"].has(hid):
		return false
	var h: Dictionary = sim.state["holds"][hid]
	var inv: Dictionary = get_inv(h["inv"])
	var res: String = h["res"]
	var qty: int = int(h["qty"])
	if inv.is_empty() or h["dir"] != "out" or int(inv["items"].get(res, 0)) < qty:
		return false
	release(hid)
	_sub(inv, res, qty)
	_ledger(res, "consumed", qty)
	return true

func destroy(inv_id: int, res: String, qty: int, _reason: String) -> int:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return 0
	var n: int = mini(qty, int(inv["items"].get(res, 0)))
	if n > 0:
		_sub(inv, res, n)
		_ledger(res, "destroyed", n)
	return n

## Turns whatever is in the inventory into a recoverable ground pile and deletes it.
func dissolve_to_pile(inv_id: int, pos: Vector2) -> int:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty():
		return -1
	release_for_inventory(inv_id)
	var pile := -1
	if total(inv_id) > 0:
		pile = create_inv("g", 0, "pile", 100000, sim.place.clear_of_porches(pos))
		var p: Dictionary = get_inv(pile)
		for res in inv["items"].keys():
			_add(p, res, int(inv["items"][res]))
		inv["items"] = {}
	sim.state["inventories"].erase(inv_id)
	return pile

func remove_if_empty_pile(inv_id: int) -> void:
	var inv: Dictionary = get_inv(inv_id)
	if inv.is_empty() or inv["role"] != "pile":
		return
	if total(inv_id) == 0 and int(inv["held_in"]) == 0:
		release_for_inventory(inv_id)
		sim.state["inventories"].erase(inv_id)

func _add(inv: Dictionary, res: String, qty: int) -> void:
	inv["items"][res] = int(inv["items"].get(res, 0)) + qty

func _sub(inv: Dictionary, res: String, qty: int) -> void:
	var left: int = int(inv["items"].get(res, 0)) - qty
	if left <= 0:
		inv["items"].erase(res)
	else:
		inv["items"][res] = left

func _ledger(res: String, column: String, qty: int) -> void:
	var led: Dictionary = sim.state["ledger"]
	if not led.has(res):
		led[res] = {"created": 0, "consumed": 0, "destroyed": 0}
	led[res][column] = int(led[res][column]) + qty

# ---------------------------------------------------------------- totals and audit
## Totals for the top bar: total, reserved and reachable are different numbers (spec 7).
func totals() -> Dictionary:
	var out := {}
	for inv_id in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		# Materials on a construction site, in an upgrade or at the Meridian are committed.
		# ... and a visiting ship's hold (V3.1 trade) is not the colony's.
		if inv["role"] == "site" or inv["role"] == "upg" or inv["role"] == "ship" or inv["role"] == "trade":
			continue
		for res in inv["items"]:
			if not out.has(res):
				out[res] = {"total": 0, "reserved": 0, "carried": 0}
			out[res]["total"] += int(inv["items"][res])
			out[res]["reserved"] += int(inv["held_out"].get(res, 0))
			if inv["role"] == "carry":
				out[res]["carried"] += int(inv["items"][res])
	return out

# ---------------------------------------------------------------- per structure (V4, UI)
## What a structure or a vehicle holds, for its panel (Paul: "full or not, and what is stored").
## x = a building record or a vehicle record (sim.vehicles.get_v).
## {capacity, used, free, full, items {item: n}, reserved {item: n},        (its store: a
##   storehouse, cold storage, the lander, an outpost core, a depot store; a vehicle's cargo;
##   else a machine's output buffer)
##  buffers {in {item: n}, out {item: n}, in_cap, out_cap, in_used, out_used}, (machine buffers)
##  other {fill, site, upgrade, build, ship, trade, floor: {item: n}} (only the ones it has;
##   floor = ground piles inside a room),
##  spoil {item: seconds until the next unit spoils} (items that spoil where they are),
##  cold (bool), all {item: n} (everything above together)}
func contents(x: Dictionary) -> Dictionary:
	var out := {"capacity": 0, "used": 0, "free": 0, "full": false, "items": {}, "reserved": {},
		"buffers": {"in": {}, "out": {}, "in_cap": 0, "out_cap": 0, "in_used": 0, "out_used": 0},
		"other": {}, "spoil": {}, "cold": false, "all": {}}
	if x.is_empty():
		return out
	var is_vehicle: bool = x.has("cargo") and not x.has("def")
	var id: int = int(x["id"])
	var mine: Array = []
	for inv_id in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		if is_vehicle:
			if inv["ot"] == "v" and int(inv["oid"]) == id:
				mine.append(inv)
		elif (inv["ot"] == "b" and int(inv["oid"]) == id) or (inv["ot"] == "g" and int(inv["oid"]) == id):
			mine.append(inv)
	if not is_vehicle:
		out["cold"] = bool(sim.bdef(x["def"]).get("cold", false))
	var main := {}
	for inv in mine:
		if inv["role"] == "store" or inv["role"] == "vcargo":
			main = inv
	if main.is_empty():
		for inv in mine:
			if inv["role"] == "out":
				main = inv
	var day: float = float(sim.bal["day_length"])
	var names := {"fill": "fill", "site": "site", "upg": "upgrade", "vbuild": "build", "ship": "ship", "trade": "trade", "pile": "floor", "box": "floor"}
	for inv in mine:
		var items: Dictionary = (inv["items"] as Dictionary).duplicate()
		for r in items:
			out["all"][r] = int(out["all"].get(r, 0)) + int(items[r])
		match String(inv["role"]):
			"in":
				out["buffers"]["in"] = items
				out["buffers"]["in_cap"] = int(inv["cap"])
				out["buffers"]["in_used"] = total(int(inv["id"]))
			"out":
				out["buffers"]["out"] = items
				out["buffers"]["out_cap"] = int(inv["cap"])
				out["buffers"]["out_used"] = total(int(inv["id"]))
			"store", "vcargo":
				pass
			_:
				var key: String = String(names.get(String(inv["role"]), String(inv["role"])))
				var o: Dictionary = out["other"].get(key, {})
				for r in items:
					o[r] = int(o.get(r, 0)) + int(items[r])
				out["other"][key] = o
		# Spoilage: where it spoils (stores, output buffers, fill ports, piles; not cold rooms).
		var role: String = inv["role"]
		if not out["cold"] and (role == "store" or role == "out" or role == "pile" or role == "fill") and bool(sim.state.get("options", {}).get("spoilage", true)):
			var acc: Dictionary = inv.get("spoil", {})
			for r in items:
				var shelf: float = sim.items.shelf_days(r)
				var free: int = int(items[r]) - int(inv["held_out"].get(r, 0))
				if shelf <= 0.0 or free <= 0:
					continue
				var left: float = ceilf(float(int(round(shelf * day)) - int(acc.get(r, 0))) / float(free))
				out["spoil"][r] = minf(float(out["spoil"].get(r, 1e18)), maxf(0.0, left))
	if not main.is_empty():
		out["capacity"] = int(main["cap"])
		out["used"] = total(int(main["id"]))
		out["free"] = maxi(0, int(main["cap"]) - int(out["used"]))
		out["full"] = int(out["used"]) >= int(main["cap"])
		out["items"] = (main["items"] as Dictionary).duplicate()
		out["reserved"] = (main["held_out"] as Dictionary).duplicate()
	return out

## The inventory list: one row per structure or vehicle that holds anything, plus "ground" (piles
## outdoors), "carried" (what people carry) and ship/trade holds, for one base (-1 = all).
## [{id, name, def, kind ("structure" | "vehicle" | "ground" | "carried"), base, capacity, used,
##   full, items {item: n} (everything it holds)}], structures first by id. The items of all rows
## together are every unit in the world (the ledger's balance).
func by_structure(base_id: int = -1) -> Array:
	var rows := {}
	var ground := {}
	var carried := {}
	var blds: Dictionary = sim.state["buildings"]
	var many: bool = sim.bases.count() > 1
	for inv_id in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		var items: Dictionary = inv["items"]
		var ot: String = inv["ot"]
		var oid: int = int(inv["oid"])
		var key := ""
		var bb := -1
		if (ot == "b" or ot == "g") and oid != 0 and blds.has(oid):
			key = "b%d" % oid
			bb = sim.bases.base_of(oid)
		elif ot == "v":
			key = "v%d" % oid
			bb = sim.bases.base_at(position_of(int(inv_id))) if many else (int(sim.bases.ids()[0]) if sim.bases.count() == 1 else -1)
		elif ot == "a":
			key = "carried"
			var a: Dictionary = sim.state["agents"].get(oid, {})
			bb = sim.bases.base_of_agent(a) if not a.is_empty() else -1
		else:
			key = "ground"
			bb = sim.bases.base_at(position_of(int(inv_id))) if many else (int(sim.bases.ids()[0]) if sim.bases.count() == 1 else -1)
		if base_id != -1 and bb != base_id:
			continue
		var bucket: Dictionary
		if key == "carried":
			bucket = carried
		elif key == "ground":
			bucket = ground
		else:
			if not rows.has(key):
				if key.begins_with("b"):
					var b: Dictionary = blds[oid]
					rows[key] = {"id": oid, "name": b["name"], "def": b["def"], "kind": "structure", "base": bb, "items": {}}
				else:
					var v: Dictionary = sim.vehicles.get_v(oid)
					rows[key] = {"id": oid, "name": String(v.get("name", "Vehicle")), "def": String(v.get("kind", "")), "kind": "vehicle", "base": bb, "items": {}}
			bucket = rows[key]["items"]
		for r in items:
			bucket[r] = int(bucket.get(r, 0)) + int(items[r])
	var out: Array = []
	var keys: Array = rows.keys()
	keys.sort_custom(func(p, q): return (0 if String(p).begins_with("b") else 1) * 100000000 + int(String(p).substr(1)) < (0 if String(q).begins_with("b") else 1) * 100000000 + int(String(q).substr(1)))
	for k in keys:
		var row: Dictionary = rows[k]
		var c: Dictionary = contents(blds[row["id"]] if row["kind"] == "structure" else sim.vehicles.get_v(int(row["id"])))
		row["capacity"] = c["capacity"]
		row["used"] = c["used"]
		row["full"] = c["full"]
		out.append(row)
	if not ground.is_empty():
		out.append({"id": -1, "name": "On the ground", "def": "", "kind": "ground", "base": base_id, "capacity": 0, "used": 0, "full": false, "items": ground})
	if not carried.is_empty():
		out.append({"id": -2, "name": "Carried", "def": "", "kind": "carried", "base": base_id, "capacity": 0, "used": 0, "full": false, "items": carried})
	return out

## Returns {} when the books balance, else a description of each mismatch.
func audit() -> Dictionary:
	var world := {}
	for inv_id in sim.state["inventories"]:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		var held := {}
		for res in inv["items"]:
			world[res] = int(world.get(res, 0)) + int(inv["items"][res])
		for res in inv["held_out"]:
			held[res] = int(inv["held_out"][res])
			if int(inv["held_out"][res]) > int(inv["items"].get(res, 0)):
				return {"error": "hold exceeds stock", "inv": inv_id, "res": res}
	var problems := {}
	var led: Dictionary = sim.state["ledger"]
	var keys := {}
	for r in world:
		keys[r] = true
	for r in led:
		keys[r] = true
	for res in keys:
		var l: Dictionary = led.get(res, {"created": 0, "consumed": 0, "destroyed": 0})
		var expected: int = int(l["created"]) - int(l["consumed"]) - int(l["destroyed"])
		if int(world.get(res, 0)) != expected:
			problems[res] = {"in_world": int(world.get(res, 0)), "expected": expected}
	return problems
