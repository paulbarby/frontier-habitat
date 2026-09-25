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
