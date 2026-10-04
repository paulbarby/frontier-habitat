extends RefCounted
## Missing items and missing capability (docs/V5_DESIGN.md section 18.4).
##
## When a build, repair, upgrade, recipe or order needs an item the colony does not have, this finds the production
## chain of the item from the content (recipes and buildings): raw resource -> mine or harvester -> refinery ->
## processor -> item. Each step says if the colony can do it now: "done", "missing" (no such structure: place
## it), "building" (a plan or a site), "broken", "unpowered", "no_worker" (nobody with the role), or
## "needs_research" (the structure is not unlocked).
##
## chain_for(item) = {item, name, ok (every step is done), steps [step], gaps [step], text}
##   step = {item, item_name, kind ("recipe" | "raw" | "crop" | "special"), recipe, building (def id, "" for a find),
##           building_name, status, tech, tech_name, inputs [item ids], text (one line, STE), place (the structure
##           can be placed now: unlocked and none exists), count (structures of this def)}
##   steps are in the order of work: the raw resource first, the item last.
## all_chains() = [chain_for(item)] for every item the colony can make (the codex page "Production chains").
## issues(found, alerts) adds the alerts "chain:<item>" (and the chain to the "materials:<item>" alerts).
## report_missing(item, qty, source, b, who): an order or a plan reports an item it cannot get.
##
## state.v5.chains = {reports {item: {item, qty, source, b, who, tick}}}   (reports lapse after two minutes)

var sim
var _prod := {}          # item -> [[recipe id, def id, kind]] (derived from content)
var _built := false

## Raw items that the "mine" structure digs from a deposit (the others have their own structure).
const SPECIAL := {"silicate": "regolith_harvester", "exotic": "deep_drill", "rocket_fuel": "fuel_refinery"}

func _init(s) -> void:
	sim = s

func reset() -> void:
	_prod = {}
	_built = false

func _w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("chains"):
		v["chains"] = {"reports": {}}
	return v["chains"]

# ---------------------------------------------------------------- reports
func report_missing(item: String, qty: int, source: String, bld: int, who: String, reason: String = "none") -> void:
	# Only an item that nothing can supply asks for a chain. Parts that other repairs hold are taken by the
	# order (jobs.order_task); parts that nobody can reach have their own alert.
	var w: Dictionary = _w()
	w["reports"][item] = {"item": item, "qty": qty, "source": source, "b": bld, "who": who, "tick": int(sim.state["tick"]), "reason": reason}

func _reports() -> Dictionary:
	if not sim.state.has("v5") or not (sim.state["v5"] as Dictionary).has("chains"):
		return {}
	var rep: Dictionary = _w()["reports"]
	var now: int = int(sim.state["tick"])
	var lim: int = 120 * int(sim.bal["tick_hz"])
	for k in rep.keys():
		if now - int(rep[k]["tick"]) > lim:
			rep.erase(k)
	return rep

# ---------------------------------------------------------------- the content graph
func _build() -> void:
	_prod = {}
	var recipes: Dictionary = sim.content["recipes"]
	var defs: Dictionary = sim.content["buildings"]
	var rids: Array = recipes.keys()
	rids.sort()
	var dids: Array = defs.keys()
	dids.sort()
	for did in dids:
		var d: Dictionary = defs[did]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var list: Array = []
		if d.has("recipes"):
			list.append_array(d["recipes"])
		elif d.has("recipe"):
			list.append(d["recipe"])
		for rid in list:
			var rec: Dictionary = recipes.get(String(rid), {})
			if rec.is_empty():
				continue
			for out in rec.get("outputs", {}):
				if not _prod.has(out):
					_prod[out] = []
				_prod[out].append([String(rid), String(did), "recipe"])
	for item in SPECIAL:
		if not _prod.has(item):
			_prod[item] = []
		_prod[item].append(["", String(SPECIAL[item]), "special"])
	for cid in sim.content["crops"]:
		var c: Dictionary = sim.content["crops"][cid]
		if typeof(c) != TYPE_DICTIONARY or not c.has("building"):
			continue
		if not _prod.has(cid):
			_prod[cid] = []
		_prod[cid].append(["", String(c["building"]), "crop"])
		for extra in c.get("also", []):
			_prod[cid].append(["", String(extra), "crop"])
		# Every harvest leaves biomass.
		if int(c.get("biomass", 0)) > 0:
			if not _prod.has("biomass"):
				_prod["biomass"] = []
			_prod["biomass"].append(["", String(c["building"]), "crop"])
	_built = true

func producers(item: String) -> Array:
	if not _built:
		_build()
	return _prod.get(item, [])

## True when the item is a raw resource that a "mine" digs (it has no recipe and no special structure).
func _is_mined(item: String) -> bool:
	var it: Dictionary = sim.content["items"].get(item, {})
	return String(it.get("category", "")) == "raw" and not SPECIAL.has(item) and producers(item).is_empty()

# ---------------------------------------------------------------- colony state
func _def_state(def_id: String) -> Dictionary:
	var d: Dictionary = sim.content["buildings"].get(def_id, {})
	var tech: String = String(d.get("research", ""))
	var unlocked: bool = sim.unlocked_all() or sim.research.is_done(tech)
	var n_ok := 0
	var n_site := 0
	var n_broken := 0
	var n_unpowered := 0
	for bid in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][bid]
		if b["def"] != def_id or bool(b["demolish"]):
			continue
		match String(b["state"]):
			"active":
				if float(d.get("power", 0.0)) > 0.0 and not bool(b["powered"]):
					n_unpowered += 1
				else:
					n_ok += 1
			"broken":
				n_broken += 1
			_:
				n_site += 1
	var status := "missing"
	if n_ok > 0:
		status = "done"
	elif n_unpowered > 0:
		status = "unpowered"
	elif n_broken > 0:
		status = "broken"
	elif n_site > 0:
		status = "building"
	elif not unlocked:
		status = "needs_research"
	return {"status": status, "tech": tech, "unlocked": unlocked, "count": n_ok + n_unpowered + n_broken + n_site}

func _role_present(role: String) -> bool:
	if role == "":
		return true
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["role"] == role and a["kind"] != "visitor":
			return true
	return false

func _tech_name(tech: String) -> String:
	return String(sim.content["techs"].get(tech, {}).get("name", tech))

func _bname(def_id: String) -> String:
	return String(sim.content["buildings"].get(def_id, {}).get("name", def_id))

func _iname(item: String) -> String:
	return sim.items.name_of(item)

# ---------------------------------------------------------------- the chain of one item
func _pick(item: String) -> Array:
	var best: Array = []
	var best_k := 1e9
	var states := {}
	for p in producers(item):
		var did: String = String(p[1])
		if not states.has(did):
			states[did] = _def_state(did)
		var st: String = String(states[did]["status"])
		var k: float = {"done": 0.0, "unpowered": 1.0, "broken": 1.0, "building": 2.0, "missing": 3.0, "needs_research": 4.0}.get(st, 5.0)
		if p[2] == "recipe":
			var prec: Dictionary = sim.content["recipes"][String(p[0])]
			k += 0.1 * float((prec.get("inputs", {}) as Dictionary).size())
			# A recipe that needs a find (a wreck part, a data core) is no chain to plan on; the structure's
			# own recipe is the main one.
			for res in prec.get("inputs", {}):
				if String(sim.content["items"].get(res, {}).get("category", "")) == "find":
					k += 5.0
			if String(sim.content["buildings"][did].get("recipe", "")) == String(p[0]):
				k -= 0.5
			# A recipe that needs a higher level of the structure is a worse choice.
			k += 0.3 * float(int(sim.content["recipes"][String(p[0])].get("min_level", 1)) - 1)
		if k < best_k:
			best_k = k
			best = p
	return best

func _visit(item: String, steps: Array, seen: Dictionary, depth: int) -> void:
	if seen.has(item) or depth > 10:
		return
	seen[item] = true
	var iname: String = _iname(item)
	var p: Array = _pick(item)
	if p.is_empty():
		if _is_mined(item):
			var ds: Dictionary = _def_state("mine")
			var st: String = String(ds["status"])
			steps.append(_step(item, "raw", "", "mine", st, ds, [], "Dig %s with a Mine, on a deposit that holds it." % iname.to_lower()))
		else:
			# A find (a wreck, a probe, a survey): no structure makes it.
			steps.append({"item": item, "item_name": iname, "kind": "raw", "recipe": "", "building": "", "building_name": "", "status": "done" if int(sim.inv.totals().get(item, {}).get("total", 0)) > 0 else "missing",
				"tech": "", "tech_name": "", "inputs": [], "text": "%s is found, not made: explore for it or trade for it." % iname, "place": false, "count": 0})
		return
	var rec: Dictionary = sim.content["recipes"].get(String(p[0]), {}) if p[0] != "" else {}
	var inputs: Array = []
	for res in rec.get("inputs", {}):
		inputs.append(String(res))
	inputs.sort()
	for res in inputs:
		_visit(res, steps, seen, depth + 1)
	if String(p[2]) == "recipe" and bool(rec.get("from_deposit", 0)):
		pass
	var did: String = String(p[1])
	var ds2: Dictionary = _def_state(did)
	var status: String = String(ds2["status"])
	var d: Dictionary = sim.content["buildings"].get(did, {})
	if status == "done" and String(p[2]) == "recipe" and not bool(rec.get("auto", false)) and not _role_present(String(rec.get("role", ""))):
		status = "no_worker"
	var from: String = ""
	if not inputs.is_empty():
		var names: Array = []
		for res in inputs:
			names.append(_iname(res).to_lower())
		from = " from " + " and ".join(names)
	var text: String
	var bn: String = _bname(did)
	match status:
		"done":
			text = "The %s makes %s%s." % [bn, iname.to_lower(), from]
		"missing":
			text = "Build a %s. It makes %s%s." % [bn, iname.to_lower(), from]
		"unpowered":
			text = "The %s has no power. Join it to a power source." % bn
		"broken":
			text = "The %s is broken. Repair it." % bn
		"building":
			text = "A %s is planned or being built." % bn
		"needs_research":
			text = "Research %s to unlock the %s." % [_tech_name(String(ds2["tech"])), bn]
		"no_worker":
			text = "The %s needs a %s to work it." % [bn, String(rec.get("role", "worker"))]
		_:
			text = bn
	steps.append(_step(item, String(p[2]), String(p[0]), did, status, ds2, inputs, text))
	if d.is_empty():
		return

func _step(item: String, kind: String, recipe: String, did: String, status: String, ds: Dictionary, inputs: Array, text: String) -> Dictionary:
	return {"item": item, "item_name": _iname(item), "kind": kind, "recipe": recipe, "building": did, "building_name": _bname(did), "status": status,
		"tech": String(ds.get("tech", "")), "tech_name": _tech_name(String(ds.get("tech", ""))) if String(ds.get("tech", "")) != "" else "", "inputs": inputs,
		"text": text, "place": (status == "missing") and bool(ds.get("unlocked", false)), "count": int(ds.get("count", 0))}

func chain_for(item: String) -> Dictionary:
	var steps: Array = []
	_visit(item, steps, {}, 0)
	var gaps: Array = []
	for s in steps:
		if s["status"] != "done":
			gaps.append(s)
	var text := ""
	if gaps.is_empty():
		text = "%s can be made now." % _iname(item)
	else:
		var g: Dictionary = gaps[0]
		match String(g["status"]):
			"missing":
				text = "%s needed: build a %s." % [_iname(item), g["building_name"]]
			"needs_research":
				text = "%s needed: research %s." % [_iname(item), g["tech_name"]]
			"unpowered":
				text = "%s needed: the %s has no power." % [_iname(item), g["building_name"]]
			"broken":
				text = "%s needed: repair the %s." % [_iname(item), g["building_name"]]
			"no_worker":
				text = "%s needed: the %s needs a worker." % [_iname(item), g["building_name"]]
			_:
				text = "%s needed: the %s is not finished." % [_iname(item), g["building_name"]]
	return {"item": item, "name": _iname(item), "ok": gaps.is_empty(), "steps": steps, "gaps": gaps, "text": text}

## Every item the colony can make, with its chain (the codex page "Production chains"), sorted by tier and name.
func all_chains() -> Array:
	if not _built:
		_build()
	var items: Array = _prod.keys()
	var out: Array = []
	for item in items:
		var it: Dictionary = sim.content["items"].get(item, {})
		if it.is_empty() or String(it.get("category", "")) == "dish":
			continue
		out.append([int(it.get("tier", 1)), String(item)])
	out.sort()
	var res: Array = []
	for e in out:
		res.append(chain_for(String(e[1])))
	return res

# ---------------------------------------------------------------- the alerts
## The items the colony lacks now, with what asks for them: {item: {qty, why [texts], entities [ids]}}.
func missing_items() -> Dictionary:
	var out := {}
	var has_free := {}      # item -> true when a free unit exists somewhere (counted once for each call)
	var blds: Dictionary = sim.state["buildings"]
	for bid in blds:
		var b: Dictionary = blds[bid]
		var blk: String = String(b["block"])
		if (b["state"] == "blueprint" or b["def"] == "meridian") and blk.begins_with("materials:"):
			_note(out, blk.substr(10), 1, "construction of %s" % b["name"], int(bid))
		var u: Dictionary = b.get("upgrade", {})
		if not u.is_empty() and String(u.get("block", "")).begins_with("materials:"):
			_note(out, String(u["block"]).substr(10), 1, "an upgrade of %s" % b["name"], int(bid))
		if b["state"] == "broken" and blk == "no_spares":
			_note(out, sim.hazards.repair_item(b), 1, "the repair of %s" % b["name"], int(bid))
		if b["state"] == "active" and blk == "no_input":
			var rec: Dictionary = sim.prod.recipe_of(b)
			for res in rec.get("inputs", {}):
				if sim.inv.available(int(b["inv_in"]), res) < int(rec["inputs"][res]) and not _free_any(has_free, String(res)):
					_note(out, String(res), int(rec["inputs"][res]), "the work of %s" % b["name"], int(bid))
					break
	# A worn structure (under the repair trigger, not broken) that no task can serve for want of a part.
	var trig: float = float(sim.bal["repair_trigger_health"])
	for bid in blds:
		var wb: Dictionary = blds[bid]
		if wb["state"] != "active" or bool(wb["demolish"]) or wb["kind"] == "special" or float(wb["health"]) >= trig:
			continue
		var wi: String = sim.hazards.repair_item(wb)
		if not _free_any(has_free, wi) and int(_stock(has_free, wi)["unreachable"]) == 0:
			_note(out, wi, 1, "the repair of %s" % wb["name"], int(bid))
	var rep: Dictionary = _reports()
	for item in rep:
		var r: Dictionary = rep[item]
		# Parts that only wait behind other repairs or lie out of reach are not a gap in the chain.
		if String(r.get("reason", "none")) != "none":
			continue
		_note(out, String(item), int(r["qty"]), "the order of %s" % r["who"], int(r["b"]))
	return out

## Spare parts (or any item an order asked for) that exist but nobody can walk to: [{item, qty, where, who}].
func unreachable_reports() -> Array:
	var out: Array = []
	var rep: Dictionary = _reports()
	var items: Array = rep.keys()
	items.sort()
	for item in items:
		var r: Dictionary = rep[item]
		if String(r.get("reason", "")) == "unreachable":
			var st: Dictionary = sim.jobs.part_stock(String(item))
			if int(st["unreachable"]) > 0:
				out.append({"item": String(item), "qty": int(st["unreachable"]), "where": st["where"], "who": String(r["who"])})
	return out

func _stock(cache: Dictionary, item: String) -> Dictionary:
	if not cache.has(item):
		cache[item] = sim.jobs.part_stock(item)
	return cache[item]

func _free_any(cache: Dictionary, item: String) -> bool:
	return int(_stock(cache, item)["free"]) > 0

func _note(out: Dictionary, item: String, qty: int, why: String, ent: int) -> void:
	if not out.has(item):
		out[item] = {"qty": 0, "why": [], "entities": []}
	out[item]["qty"] = int(out[item]["qty"]) + qty
	if not (out[item]["why"] as Array).has(why):
		out[item]["why"].append(why)
	if ent != -1 and not (out[item]["entities"] as Array).has(ent):
		out[item]["entities"].append(ent)

## Alerts (called by alerts.tick_second): "chain:<item>" when a missing item has a gap in its chain, and the chain on
## the "materials:<item>" alerts the alerts module already makes.
## The alerts are worked out every sixth second and kept in the state between (a chain is a few ms of work and does
## not change faster; the kept rows are state, so a loaded game shows the same alerts as the saved one).
func issues(found: Dictionary, alerts) -> void:
	var tick: int = int(sim.state["tick"])
	var hz: int = int(sim.bal["tick_hz"])
	var w: Dictionary = _w()
	var kept_at: int = int(w.get("kept_at", -100000))
	if tick - kept_at < 6 * hz and kept_at <= tick:
		var rows: Dictionary = w.get("kept", {})
		for k in rows:
			found[k] = (rows[k] as Dictionary).duplicate()
		var by_item: Dictionary = w.get("by_item", {})
		for k in found:
			if String(k).begins_with("materials:") and by_item.has(String(k).substr(10)):
				found[k]["chain"] = by_item[String(k).substr(10)]
		return
	w["kept_at"] = tick
	var before: Array = found.keys()
	var by_item2 := {}
	_compute(found, alerts, by_item2)
	var kept := {}
	for k in found:
		if not before.has(k) and (String(k).begins_with("chain:") or String(k).begins_with("unreach:")):
			kept[k] = (found[k] as Dictionary).duplicate()
	w["kept"] = kept
	w["by_item"] = by_item2

func _compute(found: Dictionary, alerts, by_item: Dictionary) -> void:
	for u in unreachable_reports():
		var ukey := "unreach:%s" % u["item"]
		alerts._add(found, ukey, "unreachable_stock", 1, "%s lies where nobody can reach it (%d). %s waits for it." % [sim.items.name_of(String(u["item"])), int(u["qty"]), u["who"]],
			"Clear a way to it, or make more.", [])
		found[ukey]["where"] = u["where"]
		found[ukey]["item"] = String(u["item"])
	var miss: Dictionary = missing_items()
	if miss.is_empty():
		return
	var items: Array = miss.keys()
	items.sort()
	for item in items:
		var m: Dictionary = miss[item]
		var ch: Dictionary = chain_for(String(item))
		by_item[String(item)] = ch
		if found.has("materials:%s" % item):
			found["materials:%s" % item]["chain"] = ch
		if ch["ok"]:
			continue
		var gap: Dictionary = ch["gaps"][0]
		var action: String = "Show the production chain."
		if bool(gap.get("place", false)):
			action = "Place a %s." % gap["building_name"]
		elif String(gap["status"]) == "needs_research":
			action = "Research %s." % gap["tech_name"]
		var text: String = "%s For %s." % [ch["text"], ", ".join(m["why"])]
		var key := "chain:%s" % item
		alerts._add(found, key, "chain", 1, text, action, m["entities"].duplicate())
		found[key]["chain"] = ch
		found[key]["item"] = String(item)
		found[key]["qty"] = int(m["qty"])
		found[key]["place"] = String(gap["building"]) if bool(gap.get("place", false)) else ""
