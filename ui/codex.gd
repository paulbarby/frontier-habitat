extends RefCounted
## Codex index (V4_DESIGN §6 "Encyclopedia"): every structure, item, recipe, tech, crop and hazard,
## with where it comes from and what uses it. Built from the simulation's content (read only), once
## per game; the codex screen and its crafting-tree view read it.
##   var cx = Codex.new(hud)
##   cx.entries(kind)          -> [{id, kind, name, cat, desc, icon, color}] sorted by name
##   cx.made_by(item)          -> [{how, recipe, name, where: [def ids], inputs: {item: n}, outputs, work}]
##   cx.used_by(item)          -> [{how, id, name, amount}]   how: recipe | build | research | dish
##   cx.tree(item, depth)      -> {item, n, via, where, children: [...]}   (crafting tree, inputs first)
## Kinds: "structure", "item", "tech", "hazard". Vehicles join when SIM publishes them.

const P = preload("res://ui/theme/palette.gd")

var hud
var _made := {}      # item -> [made_by rows]
var _used := {}      # item -> [used_by rows]
var _recipe_where := {}   # recipe id -> [building def ids]

func _init(h) -> void:
	hud = h
	_index()

func _content() -> Dictionary:
	return hud.main.sim.content

func _index() -> void:
	var c: Dictionary = _content()
	var blds: Dictionary = c.get("buildings", {})
	for def_id in blds:
		if String(def_id).begins_with("_"):
			continue
		var r = blds[def_id].get("recipes", blds[def_id].get("recipe", null))
		var list: Array = r if typeof(r) == TYPE_ARRAY else ([r] if typeof(r) == TYPE_STRING else [])
		for rid in list:
			if not _recipe_where.has(rid):
				_recipe_where[rid] = []
			_recipe_where[rid].append(String(def_id))
	var recs: Dictionary = c.get("recipes", {})
	for rid in recs:
		if String(rid).begins_with("_"):
			continue
		var rec: Dictionary = recs[rid]
		var row := {"how": "recipe", "recipe": String(rid), "name": String(rec.get("name", rid)), "where": _recipe_where.get(rid, []),
			"inputs": rec.get("inputs", {}), "outputs": rec.get("outputs", {}), "work": float(rec.get("work", 0)),
			"deposit": rec.has("from_deposit"), "min_level": int(rec.get("min_level", 1))}
		for it in rec.get("outputs", {}):
			_add(_made, String(it), row)
		for it in rec.get("inputs", {}):
			_add(_used, String(it), {"how": "recipe", "id": String(rid), "name": String(rec.get("name", rid)), "amount": int(rec["inputs"][it])})
	# Crops: grown on trays; every harvest also gives biomass.
	var crops: Dictionary = c.get("crops", {})
	for cid in crops:
		if String(cid).begins_with("_"):
			continue
		var cr: Dictionary = crops[cid]
		_add(_made, String(cid), {"how": "crop", "recipe": "", "name": "Grown: " + String(cr.get("name", cid)), "where": [String(cr.get("building", ""))],
			"inputs": {}, "outputs": {String(cid): int(cr.get("yield", 1))}, "work": float(cr.get("cycle_seconds", 0)), "deposit": false})
		if int(cr.get("biomass", 0)) > 0:
			_add(_made, "biomass", {"how": "crop", "recipe": "", "name": "By-product of %s harvests" % String(cr.get("name", cid)).to_lower(),
				"where": [String(cr.get("building", ""))], "inputs": {}, "outputs": {"biomass": int(cr["biomass"])}, "work": 0.0, "deposit": false})
	# Structure costs.
	for def_id in blds:
		if String(def_id).begins_with("_"):
			continue
		for it in blds[def_id].get("cost", {}):
			_add(_used, String(it), {"how": "build", "id": String(def_id), "name": String(blds[def_id].get("name", def_id)), "amount": int(blds[def_id]["cost"][it])})
	# Research packs.
	var techs: Dictionary = hud.data.techs()
	for tid in techs:
		for it in techs[tid].get("packs", {}):
			_add(_used, String(it), {"how": "research", "id": String(tid), "name": String(techs[tid].get("name", tid)), "amount": int(techs[tid]["packs"][it])})
	# Dishes.
	var dishes: Dictionary = c.get("dishes", {})
	for did in dishes:
		if String(did).begins_with("_") or typeof(dishes[did]) != TYPE_DICTIONARY:
			continue
		for it in dishes[did].get("ingredients", {}):
			_add(_used, String(it), {"how": "dish", "id": String(did), "name": String(dishes[did].get("name", String(did).replace("_", " ").capitalize())), "amount": int(dishes[did]["ingredients"][it])})

static func _add(d: Dictionary, k: String, row: Dictionary) -> void:
	if not d.has(k):
		d[k] = []
	d[k].append(row)

func made_by(item: String) -> Array:
	return _made.get(item, [])

func used_by(item: String) -> Array:
	return _used.get(item, [])

func recipe_where(rid: String) -> Array:
	return _recipe_where.get(rid, [])

func entries(kind: String) -> Array:
	var c: Dictionary = _content()
	var out: Array = []
	match kind:
		"structure":
			var blds: Dictionary = c.get("buildings", {})
			for def_id in blds:
				if String(def_id).begins_with("_"):
					continue
				var b: Dictionary = blds[def_id]
				var cat: String = String(b.get("category", "logistics"))
				var btier: int = hud.data.building_tier(String(def_id))
				out.append({"id": String(def_id), "kind": kind, "name": String(b.get("name", def_id)), "tier": btier, "cat": String(P.CATEGORY_NAME.get(cat, cat.capitalize())) + " · " + hud.data.tier_name(btier),
					"desc": String(b.get("desc", "")), "icon": String(def_id), "fallback_icon": _cat_icon(cat), "color": P.cat(cat)})
		"item":
			for it in hud.data.items():
				var d: Dictionary = hud.data.item(String(it))
				var tr: int = hud.data.item_tier(String(it))
				out.append({"id": String(it), "kind": kind, "name": hud.data.item_name(String(it)), "tier": tr, "cat": String(hud.data.item_categories().get(hud.data.item_cat(String(it)), {}).get("name", hud.data.item_cat(String(it)))) + ((" · " + hud.data.tier_name(tr)) if tr > 0 else ""),
					"desc": String(d.get("desc", "")), "icon": load("res://ui/theme/icons.gd").item(String(it)), "fallback_icon": "inventory", "color": hud.data.item_color(String(it))})
		"tech":
			var techs: Dictionary = hud.data.techs()
			var branches: Dictionary = hud.data.branches()
			for tid in techs:
				var t: Dictionary = techs[tid]
				var br: String = String(t.get("branch", ""))
				out.append({"id": String(tid), "kind": kind, "name": String(t.get("name", tid)), "cat": "Tier %d · %s" % [int(t.get("tier", 1)), String(branches.get(br, {}).get("name", br.capitalize()) if typeof(branches.get(br)) == TYPE_DICTIONARY else br.capitalize())],
					"desc": String(t.get("desc", "")), "icon": "research", "fallback_icon": "research", "color": P.VIOLET})
		"chain":
			# Version 5 §18.4: one page for each item that has a production chain (SIM's sim.chains when it is there).
			for ch in hud.v18.all_chains():
				var iid: String = String(ch["item"])
				var n_done := 0
				for st in ch["steps"]:
					if String(st["status"]) == "done":
						n_done += 1
				out.append({"id": iid, "kind": kind, "name": String(ch["name"]), "cat": "%d of %d steps done" % [n_done, (ch["steps"] as Array).size()],
					"desc": "", "icon": load("res://ui/theme/icons.gd").item(iid), "fallback_icon": "route", "color": P.GREEN if bool(ch["ok"]) else P.AMBER})
		"society":
			# Version 5 (V5 §5, §6, §10): ranks, skills, discipline, unrest, traits, and the Easter eggs
			# that were found (hidden until then).
			for e in society_entries():
				out.append(e)
		"hazard":
			# Only the hazards of this planet (SIM hazards.kinds_here): the airless world has no storms.
			var Data = load("res://ui/data.gd")
			for hk in hud.data.hazard_kinds_here():
				if not Data.HAZARD.has(hk):
					continue
				var h: Dictionary = Data.HAZARD[hk]
				out.append({"id": String(hk), "kind": kind, "name": String(h["name"]), "cat": "Hazard", "desc": String(h["advice"]) + hud.data.hazard_planet_note(String(hk)),
					"icon": String(h["icon"]), "fallback_icon": "sev_warning", "color": P.AMBER})
	out.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return out

## Codex-only people entries; the v5 topics (the dock, follow, the Rag, security, jail, tourism, ranks, discipline,
## unrest, homes, the academy, the new structures, the dome, floors, planets) come from ui/v5_help.gd TOPICS (also the How to play tab).
const SOCIETY := [
	["satisfaction", "Satisfaction", "People", "morale", "0 to 100: needs, food, housing, leisure, friends, work, fairness, safety and freedom. The personnel file shows each part and its reason. Low satisfaction makes attitudes worse."],
	["attitude", "Attitude", "People", "trend_down", "-100 to 100: how a person treats work and rules. Bad (-30 and below): slow work, long breaks, backtalk. Very bad (-70 and below): protests and fights. It follows satisfaction, traits, the captain, friends and discipline."],
	["relationships", "Relationships", "Society", "heart", "People become friends, rivals or enemies at work, at meals and in leisure places. Adults can fall in love, date, move in together and marry; affairs and break-ups make news in The Regolith Rag (key J). Crushes stay secret until the Rag or a speech bubble tells."],
]
const EGGS := {"dance": ["Dance Floor Director", "In the over-the-shoulder view, the old code makes the person dance, and their friends join in."],
	"arcade": ["Prism Shift", "A neon tunnel racer on an arcade cabinet in the gaming lounge. Some colonists are champions."],
	"dev": ["The dev in the dome", "A tourist named P. Barby once visited the super dome. He said he made the place."]}

func society_entries() -> Array:
	var out: Array = []
	for tp in load("res://ui/v5_help.gd").TOPICS:
		out.append({"id": String(tp[0]), "kind": "society", "name": String(tp[1]), "cat": String(tp[3]), "desc": String(tp[4]), "icon": String(tp[2]), "fallback_icon": "people", "color": P.CYAN})
	for s in SOCIETY:
		out.append({"id": String(s[0]), "kind": "society", "name": String(s[1]), "cat": String(s[2]), "desc": String(s[4]), "icon": String(s[3]), "fallback_icon": "people", "color": P.CYAN})
	var found: Dictionary = hud.eggs_found() if hud.has_method("eggs_found") else {}
	for k in EGGS:
		if found.has(k):
			out.append({"id": "egg_" + String(k), "kind": "society", "name": String(EGGS[k][0]), "cat": "Secret (found)", "desc": String(EGGS[k][1]), "icon": "sparkle", "fallback_icon": "sparkle", "color": P.GOLD})
	return out

static func _cat_icon(cat: String) -> String:
	return load("res://ui/theme/icons.gd").category(cat)

## Crafting tree of `item`: how one unit is made, inputs first, down to raw materials.
## Each node: {item, n (units), via (recipe or crop name), where (first building def), children}.
func tree(item: String, n: float = 1.0, depth: int = 5, seen: Array = []) -> Dictionary:
	var node := {"item": item, "n": n, "via": "", "where": "", "raw": true, "children": []}
	var rows: Array = made_by(item)
	if rows.is_empty() or depth <= 0 or seen.has(item):
		return node
	# The first recipe that has inputs (a real chain), else the first way at all.
	var pick: Dictionary = rows[0]
	for r in rows:
		if not (r["inputs"] as Dictionary).is_empty():
			pick = r
			break
	node.raw = false
	node.via = String(pick["name"])
	node.where = String((pick["where"] as Array)[0]) if not (pick["where"] as Array).is_empty() else ""
	var made: float = maxf(1.0, float((pick["outputs"] as Dictionary).get(item, 1)))
	var next_seen: Array = seen.duplicate()
	next_seen.append(item)
	for it in pick["inputs"]:
		node.children.append(tree(String(it), n * float(pick["inputs"][it]) / made, depth - 1, next_seen))
	return node
