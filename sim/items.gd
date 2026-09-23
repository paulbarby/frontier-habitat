extends RefCounted
## Item types (docs/AAA_DESIGN.md section 3). Read-only facts about each item id, built
## from content/items.json, crops.json and dishes.json. Nothing here changes state.

var sim
var _info := {}        # id -> merged info Dictionary (built once)
var _dishes: Array = []   # every dish id, sorted, rations included
var _crops: Array = []    # every crop item id, sorted

func _init(s) -> void:
	sim = s
	var items: Dictionary = sim.content["items"]
	var ids: Array = items.keys()
	ids.sort()
	for id in ids:
		var it: Dictionary = items[id]
		var nm: String = String(it.get("name", id))
		var d := {
			"id": id, "name": nm, "category": String(it.get("category", "material")),
			"color": String(it.get("color", "#FFFFFF")), "value": int(it.get("value", 1)),
			"shelf_days": float(it.get("shelf_days", 0.0)), "desc": String(it.get("desc", "")),
			"one": String(it.get("one", nm)), "plural": String(it.get("plural", nm)),
		}
		if sim.content["dishes"].has(id):
			var ds: Dictionary = sim.content["dishes"][id]
			d["nutrition"] = ds["nutrition"]
			d["taste"] = float(ds.get("taste", 0))
			d["ingredients"] = ds["ingredients"]
			d["kitchen_level"] = int(ds["kitchen_level"])
			d["work_per_dish"] = float(ds.get("work_per_dish", 0))
		if sim.content["crops"].has(id):
			d["crop"] = sim.content["crops"][id]
		_info[id] = d
		if d["category"] == "dish":
			_dishes.append(id)
		elif d["category"] == "crop":
			_crops.append(id)

## Everything the interface needs about one item: name, category, colour, value,
## shelf_days (0 = keeps forever), desc; dishes add nutrition, taste, ingredients,
## kitchen_level, work_per_dish; crops add crop (the crops.json entry).
func info(id: String) -> Dictionary:
	if _info.has(id):
		return _info[id]
	return {"id": id, "name": String(sim.bal["resource_names"].get(id, id)), "category": "material",
		"color": "#FFFFFF", "value": 1, "shelf_days": 0.0, "desc": ""}

func name_of(id: String) -> String:
	return String(info(id)["name"])

## "3 hull plates", "1 spare part", "10 steel": a count of an item for texts (lower case).
func amount(id: String, n: int) -> String:
	var i: Dictionary = info(id)
	return "%d %s" % [n, String(i.get("one", i["name"]) if n == 1 else i.get("plural", i["name"])).to_lower()]

## "2 hull plates, 10 steel" for a dictionary {item: units}, in id order.
func list_text(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append(amount(k, int(d[k])))
	return ", ".join(parts)

func exists(id: String) -> bool:
	return _info.has(id)

func is_dish(id: String) -> bool:
	return _info.has(id) and _info[id]["category"] == "dish"

func is_crop(id: String) -> bool:
	return _info.has(id) and _info[id]["category"] == "crop"

func shelf_days(id: String) -> float:
	return float(_info[id]["shelf_days"]) if _info.has(id) else 0.0

## Every dish id (rations included), sorted by id.
func dishes() -> Array:
	return _dishes

func crops() -> Array:
	return _crops

## Every item id, sorted.
func all() -> Array:
	var out: Array = _info.keys()
	out.sort()
	return out

## Item ids of one category, sorted.
func of_category(cat: String) -> Array:
	var out: Array = []
	for id in all():
		if _info[id]["category"] == cat:
			out.append(id)
	return out

## Units of every dish in an inventory (a dictionary of items).
static func dish_units(items_dict: Dictionary, dish_ids: Array) -> int:
	var n := 0
	for id in dish_ids:
		n += int(items_dict.get(id, 0))
	return n
