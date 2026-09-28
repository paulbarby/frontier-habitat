extends RefCounted
## What a structure (or a vehicle) holds (Paul, 2026-09-28: "storage in all habitats needs to be shown,
## and what is stored", and whether it is full). Read only. SIM (2026-09-28): `sim.inventory.contents(b)`
## (store, buffers, reserved, spoil seconds, cold) and `sim.inventory.by_structure(base)` (the Inventory
## screen's By structure rows). Each holder (input, store, output, supplies) is shown on its own; its
## row of sim.state["inventories"] gives {cap, items, held_out (reserved), held_in (on the way in)}.
##   Storage.holders(sim, b)      -> [{inv, role, title}]   the inventories of a structure worth showing
##   Storage.info(sim, inv_id)    -> {used, cap, incoming, free, frac, full, level, items: [...], cold}
##   Storage.summary(sim, b)      -> {used, cap, frac, full, full_titles, items: {id: n}, holders}
##   Storage.is_full(sim, b)      -> true when a store, or an output buffer, of b is full
## Item rows: {id, n, reserved, free, spoil_s (seconds to the next spoiled unit; -1 none)}.

const WARN := 0.8    # amber from 80 %
const CRIT := 0.95   # red from 95 %
const TITLES := {"store": "Stored", "in": "Input", "out": "Output", "fill": "Supplies", "cargo": "Cargo"}

## The inventories of structure b shown to the player (not a construction site, which the blueprint
## view shows as "Materials delivered").
static func holders(sim, b: Dictionary) -> Array:
	var out: Array = []
	for key in ["inv_out", "inv_in", "inv_fill"]:
		var iid: int = int(b.get(key, -1))
		if iid == -1 or not sim.inv.exists(iid):
			continue
		var inv: Dictionary = sim.inv.get_inv(iid)
		var role: String = String(inv.get("role", key.substr(4)))
		if int(inv.get("cap", 0)) <= 0:
			continue
		out.append({"inv": iid, "role": role, "title": String(TITLES.get(role, role.capitalize()))})
	# Input first, then output (a machine reads left to right: in, out); a store alone.
	out.sort_custom(func(a, c): return ["in", "store", "out", "fill"].find(String(a["role"])) < ["in", "store", "out", "fill"].find(String(c["role"])))
	return out

## spoil_s: SIM's contents(b).spoil (seconds to the next spoiled unit, per item) when given.
static func info(sim, inv_id: int, cold: bool = false, spoil_s: Dictionary = {}) -> Dictionary:
	var inv: Dictionary = sim.inv.get_inv(inv_id)
	var out := {"used": 0, "cap": 0, "incoming": 0, "free": 0, "frac": 0.0, "full": false, "level": 0, "items": [], "cold": cold}
	if inv.is_empty():
		return out
	var cap: int = int(inv.get("cap", 0))
	var used := 0
	var items: Array = []
	var held: Dictionary = inv.get("held_out", {})
	var spoil: Dictionary = inv.get("spoil", {})
	var day: float = float(sim.bal.get("day_length", 600.0))
	for res in inv.get("items", {}):
		var n: int = int(inv["items"][res])
		if n <= 0:
			continue
		used += n
		var rv: int = mini(n, int(held.get(res, 0)))
		var sp := -1.0
		var role: String = String(inv.get("role", ""))
		if spoil_s.has(res) and role != "in" and not cold:
			sp = float(spoil_s[res])
		elif not cold and role != "in" and sim.get("items") != null and sim.items.has_method("shelf_days"):
			var shelf: float = float(sim.items.shelf_days(String(res)))
			var free_units: int = n - rv
			if shelf > 0.0 and free_units > 0:
				var limit: float = roundf(shelf * day)
				sp = maxf(0.0, (limit - float(spoil.get(res, 0))) / float(free_units))
		items.append({"id": String(res), "n": n, "reserved": rv, "free": n - rv, "spoil_s": sp})
	items.sort_custom(func(a, c): return int(a["n"]) > int(c["n"]) if int(a["n"]) != int(c["n"]) else String(a["id"]) < String(c["id"]))
	var incoming: int = int(inv.get("held_in", 0))
	out["used"] = used
	out["cap"] = cap
	out["incoming"] = incoming
	out["free"] = maxi(0, cap - used - incoming)
	out["frac"] = float(used) / float(cap) if cap > 0 else 0.0
	out["full"] = cap > 0 and used >= cap
	out["level"] = 2 if float(out["frac"]) >= CRIT else (1 if float(out["frac"]) >= WARN else 0)
	out["items"] = items
	return out

static func _from_sim(r: Dictionary, cold: bool) -> Dictionary:
	var cap: int = int(r.get("cap", 0))
	var used: int = int(r.get("used", r.get("total", 0)))
	var items: Array = []
	var src = r.get("items", {})
	if typeof(src) == TYPE_DICTIONARY:
		for res in src:
			var e = src[res]
			var n: int = int(e.get("n", e)) if typeof(e) == TYPE_DICTIONARY else int(e)
			var rv: int = int(e.get("reserved", 0)) if typeof(e) == TYPE_DICTIONARY else 0
			items.append({"id": String(res), "n": n, "reserved": rv, "free": n - rv, "spoil_s": float(e.get("spoil_s", -1.0)) if typeof(e) == TYPE_DICTIONARY else -1.0})
	elif typeof(src) == TYPE_ARRAY:
		for e in src:
			items.append({"id": String(e.get("id", "")), "n": int(e.get("n", 0)), "reserved": int(e.get("reserved", 0)), "free": int(e.get("n", 0)) - int(e.get("reserved", 0)), "spoil_s": float(e.get("spoil_s", -1.0))})
	items.sort_custom(func(a, c): return int(a["n"]) > int(c["n"]))
	var frac: float = float(used) / float(cap) if cap > 0 else 0.0
	return {"used": used, "cap": cap, "incoming": int(r.get("incoming", r.get("held_in", 0))), "free": int(r.get("free", maxi(0, cap - used))),
		"frac": frac, "full": cap > 0 and used >= cap, "level": 2 if frac >= CRIT else (1 if frac >= WARN else 0), "items": items, "cold": cold}

## SIM's contents of a structure, or {} (an older SIM).
static func contents(sim, b: Dictionary) -> Dictionary:
	if sim.inv.has_method("contents"):
		var r = sim.inv.contents(b)
		if typeof(r) == TYPE_DICTIONARY:
			return r
	return {}

static func is_cold(sim, b: Dictionary) -> bool:
	return bool(sim.bdef(String(b.get("def", ""))).get("cold", false))

## The whole structure: every holder summed; full when a store or an output buffer is full (an input
## buffer full is normal: the machine has what it needs).
static func summary(sim, b: Dictionary) -> Dictionary:
	var used := 0
	var cap := 0
	var items := {}
	var full_titles: Array = []
	var hs: Array = holders(sim, b)
	var cold: bool = is_cold(sim, b)
	for h in hs:
		var inf: Dictionary = info(sim, int(h["inv"]), cold)
		used += int(inf["used"])
		cap += int(inf["cap"])
		for it in inf["items"]:
			items[it["id"]] = int(items.get(it["id"], 0)) + int(it["n"])
		if bool(inf["full"]) and String(h["role"]) != "in":
			full_titles.append(String(h["title"]))
	var frac: float = float(used) / float(cap) if cap > 0 else 0.0
	return {"used": used, "cap": cap, "frac": frac, "full": not full_titles.is_empty(), "full_titles": full_titles, "items": items, "holders": hs}

static func is_full(sim, b: Dictionary) -> bool:
	for h in holders(sim, b):
		if String(h["role"]) == "in":
			continue
		var inv: Dictionary = sim.inv.get_inv(int(h["inv"]))
		if int(inv.get("cap", 0)) > 0 and sim.inv.total(int(h["inv"])) >= int(inv["cap"]):
			return true
	return false

## "12 / 12" etc. and the colour of a fill level.
static func level_color(level: int) -> Color:
	return [Color("3EE0FF"), Color("FFB547"), Color("FF5A5F")][clampi(level, 0, 2)]
