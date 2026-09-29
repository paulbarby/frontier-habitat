extends RefCounted
## Multi-storey buildings (docs/V5_DESIGN.md section 7): the apartment block (3 floors) and the
## super dome (5). A building def may have `floors`, `floor_height` (m) and `units`
## [{floor, count, quality, beds}]. People move between floors only through the building's
## lift/stair core (an internal link with a time cost: `lift.seconds_per_floor`); walking stays
## 2D per floor.
##
## MILESTONE 1 (API stubs): an agent's floor in a multi-storey building is derived from its id
## (floor 0 while it walks in or out); the real floor comes with the floors milestone and is
## stored on the agent (a["floor"]).

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
## its position), floors (of that building)}.
func agent_floor(a: Dictionary) -> Dictionary:
	var bid: int = int(a.get("bld", -1))
	if a["where"] == "out" or bid == -1 or not sim.state["buildings"].has(bid):
		return {"building": -1, "floor": 0, "height": 0.0, "floors": 1}
	var b: Dictionary = sim.state["buildings"][bid]
	var n: int = floors_of(b)
	var f := 0
	if a.has("floor"):
		f = clampi(int(a["floor"]), 0, n - 1)
	elif n > 1 and (a["plan"] as Array).is_empty():
		f = int(Rng.hash2(int(a["id"]), bid, int(sim.state.get("seed", 1))) * n) % n
	return {"building": bid, "floor": f, "height": height_of(b, f), "floors": n}

## The homes of a residential building: [{index, floor, quality, beds}] (residence tube: by its
## variant and size; apartment block and super dome: from the def's `units`).
func units(b: Dictionary) -> Array:
	var def: Dictionary = sim.bd(b)
	var out: Array = []
	if def.has("units"):
		var i := 0
		for u in def["units"]:
			for k in int(u["count"]):
				out.append({"index": i, "floor": int(u["floor"]), "quality": String(u["quality"]), "beds": int(u["beds"])})
				i += 1
	elif def.has("variants"):
		var vname: String = String(b.get("variant", def.get("variant", "family")))
		var v: Dictionary = def["variants"].get(vname, {})
		var n: int = int((v.get("units", [2, 2, 3, 4]) as Array)[clampi(int(b.get("size", 1)), 0, 3)])
		for i in n:
			out.append({"index": i, "floor": 0, "quality": String(v.get("quality", "family")), "beds": int(v.get("beds_per_unit", 2))})
	return out

## Seconds to ride the core from floor f0 to f1 in building b.
func lift_seconds(b, f0: int, f1: int) -> float:
	var def: Dictionary = sim.bdef(b if typeof(b) == TYPE_STRING else String(b["def"]))
	return float(def.get("lift", {}).get("seconds_per_floor", 4.0)) * absi(f1 - f0)
