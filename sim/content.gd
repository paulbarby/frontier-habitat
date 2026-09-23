extends RefCounted
## Loads the editable content tables (spec 13: content module). JSON numbers arrive as
## floats, so integer tables (costs, cargo, yields, ingredients) are converted here, once.
## Keys that begin with "_" are notes for people and are dropped.

static func load_all() -> Dictionary:
	var c := {}
	c["balance"] = _read("res://content/balance.json")
	c["buildings"] = _read("res://content/buildings.json")
	c["recipes"] = _read("res://content/recipes.json")
	var sc: Dictionary = _read("res://content/scenarios.json")
	c["planets"] = sc["planets"]
	c["scenarios"] = sc["scenarios"]
	c["names"] = sc["names"]
	var items_file: Dictionary = _read("res://content/items.json")
	c["item_categories"] = items_file.get("categories", {})
	c["items"] = items_file.get("items", {})
	c["crops"] = _strip(_read("res://content/crops.json"))
	var dishes_file: Dictionary = _read("res://content/dishes.json")
	c["nutrients"] = dishes_file.get("nutrients", ["protein", "carbs", "fat", "vitamins"])
	dishes_file.erase("nutrients")
	c["dishes"] = _strip(dishes_file)
	var research_file: Dictionary = _read("res://content/research.json")
	c["research_branches"] = research_file.get("branches", {})
	c["techs"] = research_file.get("techs", {})
	var goals_file: Dictionary = _read("res://content/goals.json")
	c["chapters"] = goals_file.get("chapters", [])
	c["victory"] = goals_file.get("victory", {})
	var awards_file: Dictionary = _read("res://content/awards.json")
	c["award_tiers"] = awards_file.get("tiers", {})
	c["awards"] = awards_file.get("awards", {})

	_strip(c["buildings"])
	for id in c["buildings"]:
		var d: Dictionary = c["buildings"][id]
		d["id"] = id
		d["cost"] = _int_dict(d.get("cost", {}))
	_strip(c["recipes"])
	for id in c["recipes"]:
		var r: Dictionary = c["recipes"][id]
		r["id"] = id
		r["inputs"] = _int_dict(r.get("inputs", {}))
		r["outputs"] = _int_dict(r.get("outputs", {}))
	for id in c["scenarios"]:
		c["scenarios"][id]["lander_cargo"] = _int_dict(c["scenarios"][id].get("lander_cargo", {}))
	for id in c["crops"]:
		var cr: Dictionary = c["crops"][id]
		cr["id"] = id
		for k in ["yield", "biomass"]:
			cr[k] = int(cr.get(k, 0))
	for id in c["dishes"]:
		var ds: Dictionary = c["dishes"][id]
		ds["id"] = id
		ds["ingredients"] = _int_dict(ds.get("ingredients", {}))
		ds["kitchen_level"] = int(ds.get("kitchen_level", 0))
		var units := 0
		for k in ds["ingredients"]:
			units += int(ds["ingredients"][k])
		ds["units"] = units
	for id in c["techs"]:
		var t: Dictionary = c["techs"][id]
		t["id"] = id
		t["items"] = _int_dict(t.get("items", {}))
		t["cost"] = float(t.get("cost", 0))
	for ch in c["chapters"]:
		for g in ch["goals"]:
			var rw: Dictionary = g.get("reward", {})
			rw["items"] = _int_dict(rw.get("items", {}))
			g["reward"] = rw
	for id in c["items"]:
		c["items"][id]["id"] = id

	var b: Dictionary = c["balance"]
	b["crop_yield"] = _int_dict(b["crop_yield"])
	b["corridor_cost_per_10m"] = _int_dict(b["corridor_cost_per_10m"])
	b["cable_cost_per_20m"] = _int_dict(b["cable_cost_per_20m"])
	b["default_priority"] = _int_dict(b["default_priority"])
	var lv: Dictionary = b.get("levels", {})
	if lv.has("extra_cost"):
		var ec: Array = []
		for e in lv["extra_cost"]:
			ec.append(_int_dict(e))
		lv["extra_cost"] = ec
	var ship: Dictionary = b.get("ship", {})
	for st in ship.get("stages", []):
		st["deliver"] = _int_dict(st.get("deliver", {}))
	if ship.has("maintenance"):
		ship["maintenance"]["items"] = _int_dict(ship["maintenance"].get("items", {}))
	if ship.has("supply_run"):
		ship["supply_run"]["cargo"] = _int_dict(ship["supply_run"].get("cargo", {}))
	return c

static func _strip(d: Dictionary) -> Dictionary:
	for k in d.keys():
		if String(k).begins_with("_"):
			d.erase(k)
	return d

static func _int_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out

static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("content file missing: " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("content file is not a JSON object: " + path)
		return {}
	return parsed
