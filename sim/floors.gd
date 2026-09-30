extends RefCounted
## Multi-storey buildings (docs/V5_DESIGN.md section 7): the apartment block (3 floors) and the
## super dome (5). A building def may have `floors`, `floor_height` (m) and `units`
## [{floor, count, quality, beds}]. People move between floors only through the building's
## lift/stair core (an internal link with a time cost: `lift.seconds_per_floor`); walking stays
## 2D per floor.
##
## The floor is stored on the agent (a["floor"], a["floor_b"] = the building) and set from the anchor
## the person uses; a ride between floors is a["lift"] = {b, from, to, t0, t1}. Walking stays 2D.

const Rng = preload("res://sim/rng.gd")

var sim

func _init(s) -> void:
	sim = s

## Number of floors of a building record or a def id (1 for ordinary structures).
func floors_of(b) -> int:
	var def: Dictionary = sim.bdef(b if typeof(b) == TYPE_STRING else String(b["def"]))
	return maxi(1, int(def.get("floors", 1)))

## Height of one floor (m).
func floor_height(b) -> float:
	var def: Dictionary = sim.bdef(b if typeof(b) == TYPE_STRING else String(b["def"]))
	return float(def.get("floor_height", 3.6))

## Height above the building's ground of floor f (m).
func height_of(b, f: int) -> float:
	return float(clampi(f, 0, floors_of(b) - 1)) * floor_height(b)

## Where an agent stands vertically: {building (id or -1), floor, height (m above the ground at
## its position), floors (of that building), lift ({} or {from, to, t0, t1} (ticks) while riding
## the lift/stair core)}. The floor is the floor of the anchor the person uses (a bed, seat, stand
## or work place: slot_floor); entering a building starts on floor 0.
func agent_floor(a: Dictionary) -> Dictionary:
	var bid: int = int(a.get("bld", -1))
	if a["where"] == "out" or bid == -1 or not sim.state["buildings"].has(bid):
		return {"building": -1, "floor": 0, "height": 0.0, "floors": 1, "lift": {}}
	var b: Dictionary = sim.state["buildings"][bid]
	var n: int = floors_of(b)
	var f := 0
	if int(a.get("floor_b", -1)) == bid:
		f = clampi(int(a.get("floor", 0)), 0, n - 1)
	var lift: Dictionary = a.get("lift", {})
	return {"building": bid, "floor": f, "height": height_of(b, f), "floors": n, "lift": lift.duplicate() if int(lift.get("b", -1)) == bid else {}}

## The floor of anchor i of a kind ("bed", "child_bed", "seat", "stand", "work") in a building:
## from the def's `slot_floors` {kind: [count on floor 0, floor 1, ...]} (anchors are numbered
## floor by floor), else from `units` for beds, else floor 0.
func slot_floor(b: Dictionary, kind: String, i: int) -> int:
	var n: int = floors_of(b)
	if n <= 1 or i < 0:
		return 0
	var def: Dictionary = sim.bd(b)
	var counts = def.get("slot_floors", {}).get(kind)
	if counts == null and (kind == "bed" or kind == "child_bed") and def.has("units"):
		counts = []
		for f in n:
			counts.append(0)
		for u in def["units"]:
			var f2: int = clampi(int(u["floor"]), 0, n - 1)
			counts[f2] = int(counts[f2]) + int(u["count"]) * int(u.get("beds" if kind == "bed" else "child_beds", 0))
	if counts == null:
		return 0
	var acc := 0
	for f in (counts as Array).size():
		acc += int(counts[f])
		if i < acc:
			return mini(f, n - 1)
	return n - 1

## Called when a person takes an anchor (agents.gd _sync_use): the person's floor follows the
## anchor; a change of floor inside the same building is a ride on the lift (the person waits
## lift_seconds; agents.gd skips its step until t1).
func on_use(a: Dictionary) -> void:
	var u: Dictionary = a.get("use", {})
	var bid: int = int(u.get("b", -1))
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty() or floors_of(b) <= 1 or String(u.get("kind", "")) == "service":
		if a.has("floor"):
			a.erase("floor")
			a.erase("floor_b")
		return
	var f: int = slot_floor(b, String(u["kind"]), int(u["i"]))
	# V5: at a venue of the dome the floor is the venue's (leisure.gd).
	if String(a.get("venue", "")) != "" and sim.bdef(String(b["def"])).has("venues") and String(u["kind"]) != "bed" and String(u["kind"]) != "child_bed":
		f = clampi(sim.leisure.venue_floor(b, String(a["venue"])), 0, floors_of(b) - 1)
	var old: int = int(a.get("floor", 0)) if int(a.get("floor_b", -1)) == bid else 0
	if f != old:
		var now: int = int(sim.state["tick"])
		a["lift"] = {"b": bid, "from": old, "to": f, "t0": now, "t1": now + int(ceil(lift_seconds(b, old, f) * float(sim.bal["tick_hz"])))}
	a["floor"] = f
	a["floor_b"] = bid

## The homes of a residential building: [{index, floor, quality, beds}] (residence tube: by its
## variant and size; apartment block and super dome: from the def's `units`).
func units(b: Dictionary) -> Array:
	var def: Dictionary = sim.bd(b)
	var out: Array = []
	if def.has("units"):
		var i := 0
		for u in def["units"]:
			for k in int(u["count"]):
				out.append({"index": i, "floor": int(u["floor"]), "quality": String(u["quality"]), "beds": int(u["beds"]), "child_beds": int(u.get("child_beds", 0))})
				i += 1
	elif def.has("variants"):
		var vname: String = String(b.get("variant", def.get("variant", "family")))
		var v: Dictionary = def["variants"].get(vname, {})
		var n: int = int((v.get("units", [2, 2, 3, 4]) as Array)[clampi(int(b.get("size", 1)), 0, 3)])
		for i in n:
			out.append({"index": i, "floor": 0, "quality": String(v.get("quality", "family")), "beds": int(v.get("beds_per_unit", 2)), "child_beds": int(v.get("child_beds_per_unit", 0))})
	return out

## Seconds to ride the core from floor f0 to f1 in building b.
func lift_seconds(b, f0: int, f1: int) -> float:
	var def: Dictionary = sim.bdef(b if typeof(b) == TYPE_STRING else String(b["def"]))
	return float(def.get("lift", {}).get("seconds_per_floor", 4.0)) * absi(f1 - f0)
