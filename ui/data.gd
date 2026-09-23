extends RefCounted
## Read-only adapter between the interface and the simulation (docs/AAA_DESIGN.md §10).
## Every 2.0 field is read with .get(key, default); every helper is called only when the
## sim object has it. Where SIM has not landed a system yet, the adapter derives what it
## can from content and state, and says so with `available(...) == false`.
## Nothing here writes to sim.state.

const P = preload("res://ui/theme/palette.gd")

const SIZE_NAMES := ["S", "M", "L", "XL"]
static var _json := {}

var main

func _init(m) -> void:
	main = m

func sim():
	return main.sim

func st() -> Dictionary:
	return main.sim.state

func bal() -> Dictionary:
	return main.sim.bal

# ---------------------------------------------------------------- content
static func json(key: String) -> Dictionary:
	if _json.has(key):
		return _json[key]
	var out := {}
	var path := "res://content/%s.json" % key
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				out = d
	_json[key] = out
	return out

## A table from the sim's content (flattened keys, see sim/content.gd), else `fallback`.
func _c(key: String, fallback: Dictionary) -> Dictionary:
	var v = main.sim.content.get(key, null) if main.sim != null else null
	if typeof(v) == TYPE_DICTIONARY and not (v as Dictionary).is_empty():
		return v
	return fallback

static func _strip(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if not String(k).begins_with("_") and typeof(d[k]) == TYPE_DICTIONARY:
			out[k] = d[k]
	return out

func items() -> Dictionary:
	return _c("items", json("items").get("items", {}))

func item_categories() -> Dictionary:
	return _c("item_categories", json("items").get("categories", {}))

func item(id: String) -> Dictionary:
	return items().get(id, {})

func item_name(id: String) -> String:
	var it: Dictionary = item(id)
	if it.has("name"):
		return String(it["name"])
	return String(bal().get("resource_names", {}).get(id, id.capitalize()))

## Item colour, lifted when it is too dark to read on the dark glass.
func item_color(id: String) -> Color:
	var it: Dictionary = item(id)
	var c := Color("B0B6BE")
	if it.has("color"):
		c = Color(String(it["color"]))
	if c.get_luminance() < 0.4:
		c = c.lightened(0.35)
	return c

func item_cat(id: String) -> String:
	return String(item(id).get("category", "material"))

func crops() -> Dictionary:
	return _c("crops", _strip(json("crops")))

func dishes() -> Dictionary:
	var d: Dictionary = _c("dishes", _strip(json("dishes")))
	if d.has("nutrients"):
		d = d.duplicate()
		d.erase("nutrients")
	return d

func dish_ids() -> Array:
	var out: Array = []
	for id in items():
		if item_cat(id) == "dish":
			out.append(id)
	return out

func techs() -> Dictionary:
	return _c("techs", json("research").get("techs", {}))

func branches() -> Dictionary:
	return _c("research_branches", json("research").get("branches", {}))

func chapters() -> Array:
	var v = main.sim.content.get("chapters", null) if main.sim != null else null
	if typeof(v) == TYPE_ARRAY and not (v as Array).is_empty():
		return v
	return json("goals").get("chapters", [])

func victory_def() -> Dictionary:
	return _c("victory", json("goals").get("victory", {}))

func awards_def() -> Dictionary:
	return _c("awards", json("awards").get("awards", {}))

func award_tiers() -> Dictionary:
	return _c("award_tiers", json("awards").get("tiers", {}))

func recipes() -> Dictionary:
	return main.sim.content.get("recipes", {})

func planets() -> Dictionary:
	return main.sim.content.get("planets", {})

func difficulties() -> Dictionary:
	return bal().get("difficulty", {})

func bdef(def_id: String) -> Dictionary:
	return main.sim.content["buildings"].get(def_id, {})

# ---------------------------------------------------------------- helpers on sim systems
func sys(name: String):
	if main.sim == null:
		return null
	var o = main.sim.get(name)
	return o if typeof(o) == TYPE_OBJECT else null

func has_helper(system: String, method: String) -> bool:
	var o = sys(system)
	return o != null and o.has_method(method)

## Number of arguments a sim method takes (for calls whose signature grows in 2.0).
func arg_count(obj: Object, method: String) -> int:
	if obj == null:
		return -1
	for m in obj.get_method_list():
		if m["name"] == method:
			return (m["args"] as Array).size()
	return -1

# ---------------------------------------------------------------- time
func day() -> int:
	return main.sim.util.day_number()

func tick_to_day(tick: int) -> String:
	var day_ticks: int = int(bal()["day_length"]) * int(bal()["tick_hz"])
	var d: int = tick / day_ticks + 1
	var sec: float = float(tick % day_ticks) / float(bal()["tick_hz"])
	return "Day %d, %s" % [d, _clock(sec)]

static func _clock(seconds: float) -> String:
	var s: int = int(maxf(0.0, seconds))
	return "%d:%02d" % [s / 60, s % 60]

# ---------------------------------------------------------------- research
func research_available() -> bool:
	return st().has("research") or sys("research") != null

func research() -> Dictionary:
	return st().get("research", {})

func tech_done(tech: String) -> bool:
	if tech == "":
		return true
	return research().get("done", {}).has(tech)

func tech_state(tech: String) -> String:
	if has_helper("research", "state_of"):
		return String(main.sim.research.state_of(tech))
	var r: Dictionary = research()
	if r.get("done", {}).has(tech):
		return "done"
	if String(r.get("active", "")) == tech:
		return "active"
	if (r.get("queue", []) as Array).has(tech):
		return "queued"
	var t: Dictionary = techs().get(tech, {})
	for req in t.get("requires", []):
		if not r.get("done", {}).has(req):
			return "locked"
	return "available"

func tech_progress(tech: String) -> float:
	return float(research().get("progress", {}).get(tech, 0.0))

func tech_cost(tech: String) -> float:
	return float(techs().get(tech, {}).get("cost", 0.0))

## Research points per game day.
func rp_rate() -> float:
	if has_helper("research", "rp_rate"):
		return float(main.sim.research.rp_rate())
	var s: Array = series("rp_rate")
	if not s.is_empty():
		return float(s[s.size() - 1][1])
	return 0.0

func tech_eta_seconds(tech: String) -> float:
	var rate: float = rp_rate()
	if rate <= 0.0:
		return -1.0
	var left: float = maxf(0.0, tech_cost(tech) - tech_progress(tech))
	return left / rate * float(bal()["day_length"])

func tech_name(tech: String) -> String:
	return String(techs().get(tech, {}).get("name", tech))

## The tech that unlocks building `def_id` ("" = from the start).
func building_research(def_id: String) -> String:
	return String(bdef(def_id).get("research", ""))

## {ok, reason} — can the player place this structure now?
func building_unlocked(def_id: String) -> Dictionary:
	var def: Dictionary = bdef(def_id)
	if bool(st().get("flags", {}).get("unlock_all", false)):
		return {"ok": true, "reason": ""}
	var tech: String = String(def.get("research", ""))
	if tech != "" and not tech_done(tech):
		return {"ok": false, "reason": "Needs research: %s." % tech_name(tech), "tech": tech}
	var stage: int = int(def.get("stage", 0))
	if stage > int(st()["progress"]["stage"]) and not research_available():
		var stages: Array = bal().get("stages", [])
		var sname: String = String(stages[stage]["name"]) if stage < stages.size() else str(stage)
		return {"ok": false, "reason": "Unlocks at stage: %s." % sname}
	return {"ok": true, "reason": ""}

# ---------------------------------------------------------------- sizes and levels
func has_sizes(def_id: String) -> bool:
	return bdef(def_id).has("sizes")

func sizes_supported() -> bool:
	return sys("sizes") != null

## The definition of `def_id` at size 0..3 (S..XL).
func size_def(def_id: String, size: int) -> Dictionary:
	if has_helper("sizes", "def_for"):
		var d = main.sim.sizes.def_for(def_id, size)
		if typeof(d) == TYPE_DICTIONARY and not d.is_empty():
			return d
	var def: Dictionary = bdef(def_id).duplicate(true)
	if not def.has("sizes") or size == 1:
		return def
	var sz: Dictionary = bal().get("sizes", {})
	var sizes: Dictionary = def["sizes"]
	for k in sizes:
		var arr = sizes[k]
		if typeof(arr) == TYPE_ARRAY and size < (arr as Array).size():
			def[k] = arr[size]
	var cm: float = float(_at(sz.get("cost_mult", []), size, 1.0))
	var cost := {}
	for res in def.get("cost", {}):
		cost[res] = maxi(1, int(roundf(float(def["cost"][res]) * cm)))
	def["cost"] = cost
	if not sizes.has("power") and def.has("power"):
		def["power"] = snappedf(float(def["power"]) * float(_at(sz.get("power_mult", []), size, 1.0)), 0.1)
	return def

static func _at(arr, i: int, dflt):
	if typeof(arr) == TYPE_ARRAY and i >= 0 and i < (arr as Array).size():
		return arr[i]
	return dflt

## {ok, code, text} — is size `size` allowed for `def_id` now?
func size_allowed(def_id: String, size: int) -> Dictionary:
	if not has_sizes(def_id):
		return {"ok": size == 1, "code": "no_sizes", "text": "This structure has one size."}
	if has_helper("sizes", "allowed"):
		var r = main.sim.sizes.allowed(def_id, size)
		if typeof(r) == TYPE_DICTIONARY:
			var d: Dictionary = r
			if not bool(d.get("ok", false)):
				var tech: String = _size_tech(def_id, size)
				d["text"] = ("Needs research: %s." % tech_name(tech)) if tech != "" else String(d.get("code", "not allowed")).replace("_", " ").capitalize() + "."
			return d
	if not sizes_supported() and size != 1:
		return {"ok": false, "code": "unavailable", "text": "Sizes are not available yet."}
	var tech: String = _size_tech(def_id, size)
	if tech != "" and not tech_done(tech):
		return {"ok": false, "code": "research", "text": "Needs research: %s." % tech_name(tech)}
	return {"ok": true, "code": "ok", "text": ""}

func _size_tech(def_id: String, size: int) -> String:
	var over = bdef(def_id).get("size_research", null)
	if typeof(over) == TYPE_ARRAY:
		return String(_at(over, size, ""))
	return String(_at(bal().get("sizes", {}).get("research", []), size, ""))

func size_of(b: Dictionary) -> int:
	return int(b.get("size", 1))

func level_of(b: Dictionary) -> int:
	return int(b.get("level", 1))

func can_level(def_id: String) -> bool:
	return bool(bdef(def_id).get("levels", false))

## The special tech that unlocks level 5 for a building family.
func family_tech(family: String) -> String:
	if family == "":
		return ""
	var t: Dictionary = techs()
	for id in t:
		var fams: Array = t[id].get("families", [])
		if String(t[id].get("family", "")) == family or fams.has(family):
			return id
	return ""

## The tech needed to reach level `to` (2..5) for this structure.
func level_tech(def_id: String, to: int) -> String:
	var req: Array = bal().get("levels", {}).get("research", [])
	var r: String = String(_at(req, to - 1, ""))
	if r == "family":
		return family_tech(String(bdef(def_id).get("family", "")))
	return r

func upgrades_supported() -> bool:
	return has_helper("upgrades", "check")

## {ok, code, to, cost, research, text}
func upgrade_check(b: Dictionary) -> Dictionary:
	var lvl: int = level_of(b)
	var to: int = lvl + 1
	if not can_level(String(b["def"])):
		return {"ok": false, "code": "no_levels", "to": lvl, "cost": {}, "research": "", "text": "This structure has one level."}
	if lvl >= 5:
		return {"ok": false, "code": "max", "to": lvl, "cost": {}, "research": "", "text": "Level 5 is the highest level."}
	if upgrades_supported():
		var r = main.sim.upgrades.check(b)
		if typeof(r) == TYPE_DICTIONARY:
			var d: Dictionary = (r as Dictionary).duplicate()
			d["text"] = _upgrade_text(d)
			return d
	var cost: Dictionary = upgrade_cost_preview(b, to)
	var tech: String = level_tech(String(b["def"]), to)
	return {"ok": false, "code": "unavailable", "to": to, "cost": cost, "research": tech, "text": "Upgrades are not available yet."}

func _upgrade_text(d: Dictionary) -> String:
	if bool(d.get("ok", false)):
		return ""
	var code: String = String(d.get("code", ""))
	match code:
		"research", "locked_research":
			return "Needs research: %s." % tech_name(String(d.get("research", "")))
		"busy", "in_progress":
			return "An upgrade is in progress."
		"max", "max_level":
			return "Level 5 is the highest level."
		"not_active":
			return "Finish the structure first."
		"not_upgradable":
			return "This structure has one level."
		"demolish":
			return "It is marked for removal."
		"materials":
			return "Not enough materials in storage."
	return code.replace("_", " ").capitalize() + "."

## Local preview of the cost of level `to` (from balance.json levels).
func upgrade_cost_preview(b: Dictionary, to: int) -> Dictionary:
	var lv: Dictionary = bal().get("levels", {})
	var base: Dictionary = size_def(String(b["def"]), size_of(b)).get("cost", {})
	var m: float = float(_at(lv.get("cost_mult", []), to - 1, 1.0))
	var out := {}
	for res in base:
		out[res] = maxi(1, int(ceilf(float(base[res]) * m)))
	var extra = _at(lv.get("extra_cost", []), to - 1, {})
	if typeof(extra) == TYPE_DICTIONARY:
		for res in extra:
			out[res] = int(out.get(res, 0)) + int(extra[res])
	return out

func level_mult(to: int) -> float:
	return float(_at(bal().get("levels", {}).get("output_mult", []), to - 1, 1.0))

# ---------------------------------------------------------------- goals and awards
func goals_available() -> bool:
	return st().has("goals") or sys("goals") != null

func goals_state() -> Dictionary:
	return st().get("goals", {})

func chapter_index() -> int:
	if has_helper("goals", "chapter"):
		var c = main.sim.goals.chapter()
		if typeof(c) == TYPE_INT or typeof(c) == TYPE_FLOAT:
			return int(c)
		if typeof(c) == TYPE_DICTIONARY:
			return int(c.get("index", goals_state().get("chapter", 0)))
	return int(goals_state().get("chapter", 0))

## {state, value, target, since, done_tick} of goal `id` (empty when unknown).
func goal_status(id: String) -> Dictionary:
	return goals_state().get("status", {}).get(id, {})

func goal_done(id: String) -> bool:
	return String(goal_status(id).get("state", "")) == "done"

func victory() -> bool:
	if has_helper("goals", "victory"):
		return bool(main.sim.goals.victory())
	var v = goals_state().get("victory", -1)
	if typeof(v) == TYPE_BOOL:
		return v
	return int(v) >= 0

func awards_state() -> Dictionary:
	return st().get("awards", {})

# ---------------------------------------------------------------- nutrition
func nutrition_available() -> bool:
	for aid in st()["agents"]:
		return st()["agents"][aid].has("nutrition")
	return false

func colony_nutrition() -> Dictionary:
	if has_helper("nutrition", "colony"):
		var r = main.sim.nutrition.colony()
		if typeof(r) == TYPE_DICTIONARY:
			return r
	var sums := {"protein": 0.0, "carbs": 0.0, "fat": 0.0, "vitamins": 0.0}
	var n := 0
	for aid in st()["agents"]:
		var a: Dictionary = st()["agents"][aid]
		if a["state"] != "alive" or not a.has("nutrition"):
			continue
		n += 1
		for k in sums:
			sums[k] += float(a["nutrition"].get(k, 0.0))
	if n == 0:
		return {}
	var out := {}
	var total := 0.0
	for k in sums:
		out[k] = sums[k] / n
		total += out[k]
	out["score"] = total / 4.0
	return out

func agent_nutrition_score(a: Dictionary) -> float:
	var nu: Dictionary = a.get("nutrition", {})
	if nu.is_empty():
		return -1.0
	var s := 0.0
	for k in ["protein", "carbs", "fat", "vitamins"]:
		s += float(nu.get(k, 0.0))
	return s / 4.0

# ---------------------------------------------------------------- metrics
const _V1_COLUMNS := {"pop": 1, "meals": 2, "food_stock": 2, "water_stock": 3, "o2_stock": 4, "energy": 5,
	"item:metal": 6, "item:polymer": 7, "morale": 8, "power_gen": 9, "power_use": 10}

## Chart data: [[tick, value], ...]. From metrics.series (2.0), else from the v1 history.
func series(name: String) -> Array:
	var cur: Array = []
	if has_helper("metrics", "series"):
		var r = main.sim.metrics.series(name)
		if typeof(r) == TYPE_ARRAY:
			cur = r
	var m: Dictionary = st().get("metrics", {})
	if cur.is_empty():
		var ser = m.get("series", {})
		if typeof(ser) == TYPE_DICTIONARY and ser.has(name):
			cur = ser[name]
	# A save from version 1 has the old history table: it continues into the new series,
	# so a chart does not start empty after the upgrade.
	var old: Array = _v1_series(name, m.get("history", []))
	if old.is_empty():
		return cur
	if cur.is_empty():
		return old
	var first: int = int(cur[0][0])
	var out: Array = []
	for p in old:
		if int(p[0]) < first:
			out.append(p)
	out.append_array(cur)
	return out

func _v1_series(name: String, history: Array) -> Array:
	var out: Array = []
	if name == "food_days":
		for row in history:
			if (row as Array).size() > 2:
				out.append([row[0], float(row[2]) / maxf(1.0, float(row[1]))])
		return out
	if not _V1_COLUMNS.has(name):
		return out
	var col: int = _V1_COLUMNS[name]
	for row in history:
		if (row as Array).size() > col:
			out.append([row[0], row[col]])
	return out

func series_names() -> Array:
	var ser = st().get("metrics", {}).get("series", {})
	if typeof(ser) == TYPE_DICTIONARY:
		return ser.keys()
	return []

## -1, 0 or +1 over the last `n` samples of a series (with a dead band).
func trend(name: String, n: int = 18, band: float = 0.02) -> int:
	# The live series without the version-1 merge (no copies): enough for a trend.
	var s: Array = main.sim.metrics.series(name) if has_helper("metrics", "series") else []
	if s.size() < 3:
		s = series(name)
	if s.size() < 3:
		return 0
	var a: float = float(s[maxi(0, s.size() - 1 - n)][1])
	var b: float = float(s[s.size() - 1][1])
	var scale: float = maxf(absf(a), maxf(absf(b), 1.0))
	if (b - a) / scale > band:
		return 1
	if (b - a) / scale < -band:
		return -1
	return 0

func daily() -> Array:
	var d = st().get("metrics", {}).get("daily", [])
	return d if typeof(d) == TYPE_ARRAY else []

func stats() -> Dictionary:
	return st().get("stats", {})

# ---------------------------------------------------------------- ship
func ship() -> Dictionary:
	if has_helper("ship", "info"):
		var r = main.sim.ship.info()
		if typeof(r) == TYPE_DICTIONARY:
			return r
	return st().get("ship", {})

func meridian_id() -> int:
	for id in st()["buildings"]:
		if String(st()["buildings"][id]["def"]) == "meridian":
			return id
	return -1

# ---------------------------------------------------------------- inventory
## {item: {total, reserved, carried}} from the sim.
func totals() -> Dictionary:
	return main.sim.inv.totals()

func total_of(id: String, totals_d: Dictionary = {}) -> int:
	var t: Dictionary = totals_d if not totals_d.is_empty() else totals()
	return int(t.get(id, {}).get("total", 0))

func dish_total(totals_d: Dictionary) -> int:
	var n := 0
	for id in totals_d:
		if item_cat(String(id)) == "dish" or String(id) == "meals":
			n += int(totals_d[id].get("total", 0))
	return n

# ---------------------------------------------------------------- KPIs for the top bar
## One dictionary with every headline number. Computed at most a few times a second.
func kpis() -> Dictionary:
	var s = main.sim
	var out := {}
	var f: Dictionary = s.metrics.forecast()
	var totals_d: Dictionary = totals()
	var pop: int = int(f["pop"])
	var day_len: float = float(bal()["day_length"])
	# Oxygen: base air groups (the lander air is separate).
	var o2 := 0.0
	var o2cap := 0.0
	var make := 0.0
	var use := 0.0
	for comp in s.util.atmo_stats:
		var a: Dictionary = s.util.atmo_stats[comp]
		if not bool(a.get("lander", false)):
			o2 += s.util.units(a["stock"])
			o2cap += s.util.units(a["cap"])
			make += s.util.to_rate(a["make"])
			use += s.util.to_rate(a["breathe"])
	out["o2"] = {"value": o2, "cap": o2cap, "make": make, "use": use, "ratio": make / use if use > 0.0 else (9.99 if make > 0.0 else 0.0),
		"lander_left": s.util.lander_seconds_left()}
	# Water
	var w_in := 0.0
	var w_out := 0.0
	var w_stock := 0.0
	var w_cap := 0.0
	for comp in s.util.water_stats:
		var ws: Dictionary = s.util.water_stats[comp]
		w_in += s.util.to_rate(int(ws.get("in", 0)))
		w_out += s.util.to_rate(int(ws.get("out", 0)))
		w_stock += s.util.units(int(ws.get("stock", 0)))
		w_cap += s.util.units(int(ws.get("cap", 0)))
	out["water"] = {"value": float(f["water"]), "days": float(f["water_days"]), "in": w_in, "out": w_out, "net_stock": w_stock, "net_cap": w_cap,
		"cans": total_of("water", totals_d)}
	# Power and energy
	var gen := 0.0
	var dem := 0.0
	var shed := 0
	for comp in s.util.power_stats:
		gen += s.util.to_rate(s.util.power_stats[comp]["gen"])
		dem += s.util.to_rate(s.util.power_stats[comp]["demand"])
		shed += (s.util.power_stats[comp].get("shed", []) as Array).size()
	out["power"] = {"gen": gen, "use": dem, "net": gen - dem, "shed": shed}
	out["energy"] = {"value": float(f["energy"]), "cap": float(f["energy_cap"]), "night_need": float(f["night_need"])}
	# Food: every dish, and the emergency rations.
	var dishes_n: int = dish_total(totals_d)
	out["food"] = {"value": dishes_n, "days": float(dishes_n) / maxf(1.0, float(pop)), "meals": int(f["meals"])}
	var nu: Dictionary = colony_nutrition()
	out["nutrition"] = nu
	out["morale"] = {"value": s.metrics.avg_morale()}
	out["pop"] = {"value": pop, "beds": int(f["beds"])}
	var r: Dictionary = research()
	out["research"] = {"available": research_available(), "rate": rp_rate(), "active": String(r.get("active", "")),
		"progress": tech_progress(String(r.get("active", ""))), "cost": tech_cost(String(r.get("active", "")))}
	out["totals"] = totals_d
	out["forecast"] = f
	out["day_len"] = day_len
	return out
