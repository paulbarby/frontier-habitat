extends RefCounted
## Building sizes S, M, L, XL (index 0..3) and upgrade levels 1..5 (docs/AAA_DESIGN.md
## section 2). Size M (index 1) at level 1 is exactly the version-1 building.
##
## def_for(def_id, size) is the effective definition of a size at level 1. eff() adds the
## level. The simulation reads the effective definition of a building record through
## sim.bd(b); sim.bdef(def_id) stays the base (size M, level 1) definition.
##
## Rules, in order:
##   1. per-size arrays in buildings.json ("sizes": {field: [S, M, L, XL]}) replace fields;
##   2. cost, power and construction work scale with balance.sizes multipliers unless the
##      field is listed in "sizes";
##   3. capacity fields that are not listed scale with balance.sizes.capacity_mult;
##   4. the level multiplies the field named by "level_stat" (output_mult) and the power
##      (power_mult); "level_mult", "wear_mult" and "comfort" are added for the systems that
##      scale by level (work speed, crop growth, healing, research, habitat comfort).
## Effective definitions are cached and must be treated as read-only.

var sim
var _cache := {}      # def_id -> {size * 8 + level: Dictionary}

const SIZE_NAMES := ["S", "M", "L", "XL"]
## Capacity fields that follow capacity_mult when a sized building does not list them.
const CAPACITY_INT := ["storage", "input_cap", "output_cap", "beds", "occupants", "recreation", "treatment_beds", "fill_port"]
const CAPACITY_FLOAT := ["energy_cap", "energy_rate", "water_cap"]
## Level stats that are not a field of the definition: they scale a system instead.
const PSEUDO_STATS := ["work_speed", "growth", "healing", "research", "comfort"]

func _init(s) -> void:
	sim = s

static func size_name(size: int) -> String:
	return SIZE_NAMES[clampi(size, 0, 3)]

## The sizes a structure can have: [0, 1, 2, 3] with a "sizes" block, else [1]. A
## "size_list" limits them (V3.1: the airlock has M and L only).
func sizes_of(def_id: String) -> Array:
	if not sim.content["buildings"].has(def_id):
		return []
	var base: Dictionary = sim.content["buildings"][def_id]
	if base.has("size_list"):
		var out: Array = []
		for v in base["size_list"]:
			out.append(int(v))
		return out
	return [0, 1, 2, 3] if base.has("sizes") else [1]

## Effective definition of a size at level 1.
func def_for(def_id: String, size: int) -> Dictionary:
	return eff(def_id, size, 1)

## Effective definition of a size at a level.
func eff(def_id: String, size: int, level: int) -> Dictionary:
	var per = _cache.get(def_id)
	if per == null:
		per = {}
		_cache[def_id] = per
	var k: int = size * 8 + level
	var d = per.get(k)
	if d == null:
		d = _build(def_id, size, level)
		per[k] = d
	return d

func _build(def_id: String, size: int, level: int) -> Dictionary:
	var base: Dictionary = sim.content["buildings"].get(def_id, {})
	if base.is_empty():
		return {}
	var bal: Dictionary = sim.bal
	var sz: Dictionary = bal["sizes"]
	var d: Dictionary = base.duplicate(true)
	d.erase("sizes")
	var listed: Dictionary = base.get("sizes", {})
	var sized: bool = base.has("sizes")
	size = clampi(size, 0, 3) if sized else 1
	d["size"] = size
	d["level"] = level
	if sized:
		for key in listed:
			var arr = listed[key]
			if typeof(arr) == TYPE_ARRAY and (arr as Array).size() > size:
				d[key] = arr[size]
	# Integer fields that JSON delivered as floats.
	for key in ["trays", "beds", "occupants", "slots", "work_slots", "storage", "input_cap", "output_cap",
			"treatment_beds", "recreation", "fill_port", "max_links", "build_slots", "airlock_slots"]:
		if d.has(key):
			d[key] = int(d[key])
	if size != 1:
		if not listed.has("cost"):
			var cm: float = float(sz["cost_mult"][size])
			var cost := {}
			for r in base["cost"]:
				cost[r] = maxi(1, int(round(float(base["cost"][r]) * cm)))
			d["cost"] = cost
		if base.has("power") and not listed.has("power"):
			d["power"] = _snap(float(base["power"]) * float(sz["power_mult"][size]))
		for key in CAPACITY_INT:
			if base.has(key) and not listed.has(key):
				d[key] = maxi(1, int(round(float(base[key]) * float(sz["capacity_mult"][size]))))
		for key in CAPACITY_FLOAT:
			if base.has(key) and not listed.has(key):
				d[key] = _snap(float(base[key]) * float(sz["capacity_mult"][size]))
	d["work_mult"] = float(sz["work_mult"][size])
	# Level.
	var lv: Dictionary = bal["levels"]
	level = clampi(level, 1, int(lv["max"]))
	var li: int = level - 1
	var m: float = float(lv["output_mult"][li])
	d["level_mult"] = m
	d["wear_mult"] = float(lv["wear_mult"][li])
	d["comfort"] = float(lv["comfort_morale"][li]) if String(base.get("level_stat", "")) == "comfort" else 0.0
	var stat: String = String(base.get("level_stat", ""))
	if level > 1 and stat != "" and not PSEUDO_STATS.has(stat) and d.has(stat):
		if typeof(d[stat]) == TYPE_INT or stat in CAPACITY_INT:
			d[stat] = maxi(1, int(round(float(d[stat]) * m)))
		else:
			d[stat] = _snap_fine(float(d[stat]) * m)
	if level > 1 and d.has("power") and float(d["power"]) > 0.0:
		d["power"] = _snap(float(d["power"]) * float(lv["power_mult"][li]))
	return d

## Rates are kept on a 0.1 grid, so every rate is a whole number of fixed-point sub-units
## per tick (see utilities.gd).
static func _snap(v: float) -> float:
	if v <= 0.0:
		return 0.0
	return maxf(0.1, snappedf(v, 0.1))

static func _snap_fine(v: float) -> float:
	return snappedf(v, 0.05)

## Furniture anchors of a room size (V3_DESIGN section 6), from buildings.json
## "furniture": {beds, seats, work_slots, stands, work_pose}. ART-HAB builds exactly this
## many Anchor_Bed_<i>, Anchor_Seat_<i>, Anchor_Work_<i> and Anchor_Stand_<i> empties.
## A structure without a furniture block has none (all 0, work_pose "stand").
var _furn := {}

func furniture(def_id: String, size: int) -> Dictionary:
	var key: String = "%s:%d" % [def_id, size]
	var got = _furn.get(key)
	if got != null:
		return got
	var base: Dictionary = sim.content["buildings"].get(def_id, {})
	var f: Dictionary = base.get("furniture", {})
	var si: int = clampi(size, 0, 3) if base.has("sizes") else 1
	var out := {"beds": 0, "seats": 0, "work_slots": 0, "stands": 0, "work_pose": String(f.get("work_pose", "stand"))}
	for k in ["beds", "seats", "work_slots", "stands"]:
		var v = f.get(k, 0)
		if typeof(v) == TYPE_ARRAY:
			out[k] = int((v as Array)[si]) if si < (v as Array).size() else 0
		else:
			out[k] = int(v)
	_furn[key] = out
	return out

## Can the player place this size now? {ok, code, research}. code: ok | unknown |
## no_size (this structure has one size) | locked_research (research names the tech).
func allowed(def_id: String, size: int) -> Dictionary:
	if not sim.content["buildings"].has(def_id):
		return {"ok": false, "code": "unknown", "research": ""}
	if not sizes_of(def_id).has(size):
		return {"ok": false, "code": "no_size", "research": ""}
	var base: Dictionary = sim.content["buildings"][def_id]
	var gates: Array = base.get("size_research", sim.bal["sizes"]["research"])
	var gate: String = String(gates[size]) if size < gates.size() else ""
	if gate != "" and not sim.research.is_done(gate) and not sim.unlocked_all():
		return {"ok": false, "code": "locked_research", "research": gate}
	return {"ok": true, "code": "ok", "research": ""}
