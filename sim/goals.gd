extends RefCounted
## Base goals (docs/AAA_DESIGN.md section 7). The mission has chapters; a chapter's goals
## open together, and the next chapter opens when every goal of this one is done. Each
## goal is a pure check of the state, with an optional sustain time: the condition must
## hold for that many seconds without a break. A reward arrives as a supply pod, an
## ordinary ground pile next to the lander (real units, ledger reason "reward"), plus RP.
##
## state.goals = {chapter, status{id: {state, value, target, since, done_tick}}, victory,
##                night{start, ok, ls}, good_nights, pods}
##   state: "locked" | "active" | "done". since: tick the condition became true (-1).
## eval_kind() is shared with awards.gd, so a goal and a medal of the same kind agree.

const Text = preload("res://sim/text.gd")

var sim
var _facts := {}          # values computed once per second, shared by goals and awards
var _facts_tick := -1

func _init(s) -> void:
	sim = s

static func fresh_state() -> Dictionary:
	return {"chapter": 0, "status": {}, "victory": -1, "night": {"start": -1, "ok": true, "ls": false},
		"good_nights": 0, "pods": 0}

func gs() -> Dictionary:
	return sim.state["goals"]

func chapters() -> Array:
	return sim.content["chapters"]

## Index of the open chapter (0-based). Equal to the chapter count after victory.
func chapter() -> int:
	return int(gs()["chapter"])

func chapter_info(i: int) -> Dictionary:
	var ch: Array = chapters()
	if i < 0 or i >= ch.size():
		return {}
	return ch[i]

func victory() -> bool:
	return int(gs()["victory"]) >= 0

## Every goal with its chapter and status, in mission order:
## [{id, name, desc, hint, chapter, state, value, target, since, sustain, done_tick, reward}]
func list() -> Array:
	var out: Array = []
	var st: Dictionary = gs()["status"]
	var ch: Array = chapters()
	for i in ch.size():
		for g in ch[i]["goals"]:
			var s: Dictionary = st.get(g["id"], {})
			out.append({"id": g["id"], "name": g["name"], "desc": g.get("desc", ""), "hint": g.get("hint", ""),
				"chapter": i, "state": String(s.get("state", "active" if i == chapter() else ("done" if i < chapter() else "locked"))),
				"value": float(s.get("value", 0.0)), "target": float(s.get("target", 0.0)),
				"since": int(s.get("since", -1)), "sustain": float(g.get("sustain", 0)),
				"done_tick": int(s.get("done_tick", -1)), "reward": g.get("reward", {})})
	return out

func is_done(goal_id: String) -> bool:
	return String(gs()["status"].get(goal_id, {}).get("state", "")) == "done"

# ---------------------------------------------------------------- per second
func tick_second() -> void:
	_facts = {}
	_facts_tick = int(sim.state["tick"])
	_track_night()
	var ch: Array = chapters()
	var i: int = chapter()
	if i >= ch.size():
		return
	var st: Dictionary = gs()["status"]
	var tick: int = int(sim.state["tick"])
	var hz: int = int(sim.bal["tick_hz"])
	var all_done := true
	for g in ch[i]["goals"]:
		var s: Dictionary = st.get(g["id"], {})
		if s.is_empty():
			s = {"state": "active", "value": 0.0, "target": 0.0, "since": -1, "done_tick": -1, "opened": tick}
			st[g["id"]] = s
		if s["state"] == "done":
			continue
		var r: Array = eval_kind(String(g["kind"]), g.get("params", {}), int(s.get("opened", -1)))
		s["value"] = float(r[1])
		s["target"] = float(r[2])
		var sustain: int = int(float(g.get("sustain", 0)) * hz)
		if bool(r[0]):
			if int(s["since"]) < 0:
				s["since"] = tick
			if tick - int(s["since"]) >= sustain:
				s["state"] = "done"
				s["done_tick"] = tick
				_reward(g)
				continue
		else:
			s["since"] = -1
		all_done = false
	if all_done:
		_open_chapter(i + 1)

func _open_chapter(i: int) -> void:
	var ch: Array = chapters()
	gs()["chapter"] = i
	if i >= ch.size():
		gs()["victory"] = int(sim.state["tick"])
		var v: Dictionary = sim.content["victory"]
		sim.log_event("victory", "%s. %s" % [v.get("name", "Victory"), v.get("desc", "")], [], 1)
		return
	var st: Dictionary = gs()["status"]
	for g in ch[i]["goals"]:
		if not st.has(g["id"]):
			st[g["id"]] = {"state": "active", "value": 0.0, "target": 0.0, "since": -1, "done_tick": -1, "opened": int(sim.state["tick"])}
	sim.log_event("chapter", "Chapter %d: %s. %s" % [i + 1, ch[i]["name"], ch[i].get("desc", "")], [], 1)

func _reward(g: Dictionary) -> void:
	var rw: Dictionary = g.get("reward", {})
	var items: Dictionary = rw.get("items", {})
	var parts: Array = []
	if not items.is_empty():
		drop_pod(items, "reward")
		parts.append(sim.items.list_text(items))
	var rp: float = float(rw.get("rp", 0))
	if rp > 0.0:
		sim.research.add_rp(rp)
		parts.append(Text.n(int(rp), "research point"))
	var text: String = "Goal complete: %s." % g["name"]
	if not parts.is_empty():
		text += " Reward: %s." % ", ".join(parts)
	sim.log_event("goal", text, [], 1)

## A supply pod: an ordinary ground pile next to the lander with "pod" = true. The
## units are new (ledger "created"). Returns the inventory id.
func drop_pod(items: Dictionary, reason: String) -> int:
	var n: int = int(gs().get("pods", 0))
	gs()["pods"] = n + 1
	var base: Vector2 = sim.world.center
	var lander: Dictionary = sim.state["buildings"].get(sim.state["lander_id"], {})
	var rot := 0.0
	if not lander.is_empty():
		base = lander["pos"]
		rot = float(lander["rot"])
	# Pods land on a ring beside the lander, away from its hatch, one place after another.
	var ang: float = rot + PI * 0.5 + float(n % 6) * 0.45
	var p: Vector2 = base + Vector2(9.0 + float(n / 6 % 3) * 2.5, 0).rotated(ang)
	var q = sim.nav.nearest_walkable(p, 8)
	if q != null:
		p = q
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, sim.place.clear_of_porches(p))
	sim.inv.get_inv(pile)["pod"] = true
	var keys: Array = items.keys()
	keys.sort()
	for k in keys:
		sim.inv.add_new_forced(pile, k, int(items[k]), reason)
		sim.stat_add("rewarded", k, int(items[k]))
	return pile

# ---------------------------------------------------------------- the night check
## A full night with life support running and none of it shed (goal power_supply).
func _track_night() -> void:
	var nt: Dictionary = gs()["night"]
	var night: bool = sim.util.is_night()
	if night:
		if int(nt["start"]) < 0:
			# Only a night watched from its first second counts.
			var t: float = sim.util.day_time()
			nt["start"] = int(sim.state["tick"])
			nt["ok"] = t < float(sim.planet["daylight_seconds"]) + 2.0
			nt["ls"] = false
		var ps: Dictionary = sim.util.power_stats
		var blds: Dictionary = sim.state["buildings"]
		for comp in ps:
			if int(ps[comp]["critical"]) > 0:
				nt["ls"] = true
			for bid in ps[comp]["shed"]:
				if blds.has(bid) and sim.bdef(blds[bid]["def"]).get("power_class", "") == "life_support":
					nt["ok"] = false
	elif int(nt["start"]) >= 0:
		if bool(nt["ok"]) and bool(nt["ls"]):
			gs()["good_nights"] = int(gs()["good_nights"]) + 1
		nt["start"] = -1
		nt["ok"] = true
		nt["ls"] = false

## Mean of a chart series over the last `seconds`, or -1 while the samples do not yet
## cover that whole time (or that time starts before `from_tick`).
func _series_mean(name: String, seconds: int, from_tick: int = -1) -> float:
	var arr: Array = sim.metrics.series(name)
	if arr.is_empty():
		return -1.0
	var hz: int = int(sim.bal["tick_hz"])
	var tick: int = int(sim.state["tick"])
	var from: int = tick - seconds * hz
	if from_tick >= 0 and from < from_tick:
		return -1.0
	var step: int = int(sim.bal["series"]["sample_seconds"]) * hz
	if int(arr[0][0]) > from + step:
		return -1.0
	var sum := 0.0
	var n := 0
	for i in range(arr.size() - 1, -1, -1):
		if int(arr[i][0]) <= from:
			break
		sum += float(arr[i][1])
		n += 1
	return sum / float(n) if n > 0 else -1.0

# ---------------------------------------------------------------- conditions
## Returns [ok, value, target] for a condition kind (shared with awards.gd).
## `from_tick`: the tick the goal opened (-1 for awards). A windowed average only counts
## samples taken after it.
func eval_kind(kind: String, p: Dictionary, from_tick: int = -1) -> Array:
	match kind:
		"power_online":
			var best := 0.0
			var ps: Dictionary = sim.util.power_stats
			for comp in ps:
				if int(ps[comp]["cap"]) > 0 and _has_generator(comp):
					best = maxf(best, sim.util.units(int(ps[comp]["stored"])))
			return [best >= float(p.get("stored_e", 1)), best, float(p.get("stored_e", 1))]
		"network_water":
			var w := 0.0
			for comp in sim.util.water_stats:
				w += sim.util.units(int(sim.util.water_stats[comp]["stock"]))
			return [w >= float(p.get("units", 1)), w, float(p.get("units", 1))]
		"base_air":
			var ok: bool = bool(sim.state["flags"].get("base_air", false))
			return [ok, 1.0 if ok else 0.0, 1.0]
		"all_housed":
			var f: Dictionary = _fact_housing()
			return [int(f["pop"]) > 0 and int(f["housed"]) >= int(f["pop"]), float(f["housed"]), float(f["pop"])]
		"o2_ratio":
			var r: float = _fact("o2_ratio")
			return [r >= float(p.get("ratio", 1.0)), r, float(p.get("ratio", 1.0))]
		"water_days":
			var wd: float = float(_forecast()["water_days"])
			return [wd >= float(p.get("days", 1.0)), wd, float(p.get("days", 1.0))]
		"dish_days":
			var dd: float = _dish_days(p.get("exclude", []))
			return [dd >= float(p.get("days", 1.0)), dd, float(p.get("days", 1.0))]
		"night_no_shed":
			var n: int = int(gs().get("good_nights", 0))
			return [n >= 1, float(mini(n, 1)), 1.0]
		"nutrition_avg":
			# "window" (seconds): the mean of the chart samples over that time, which must
			# cover all of it. Without a window: the score now.
			var target_n: float = float(p.get("score", 70))
			var win: int = int(p.get("window", 0))
			if win > 0:
				var mean: float = _series_mean("nutrition", win, from_tick)
				return [int(_nutrition()["people"]) > 0 and mean >= target_n, maxf(mean, 0.0), target_n]
			var sc: float = float(_nutrition()["score"])
			return [int(_nutrition()["people"]) > 0 and sc >= target_n, sc, target_n]
		"morale_avg":
			var m: float = sim.metrics.avg_morale()
			return [sim.alive_count() > 0 and m >= float(p.get("score", 70)), m, float(p.get("score", 70))]
		"produced":
			var item: String = String(p.get("item", "*"))
			var v: int = _produced(item)
			return [v >= int(p.get("count", 1)), float(v), float(p.get("count", 1))]
		"techs_done":
			var td: int = sim.research.done_count()
			return [td >= int(p.get("count", 1)), float(td), float(p.get("count", 1))]
		"pop":
			var pop: int = sim.alive_count()
			return [pop >= int(p.get("count", 1)), float(pop), float(p.get("count", 1))]
		"max_level":
			var ml: int = int(_fact("max_level"))
			return [ml >= int(p.get("level", 2)), float(ml), float(p.get("level", 2))]
		"ship_stage":
			var stg: int = int(sim.state["ship"].get("stage", 0))
			return [stg >= int(p.get("stage", 1)), float(stg), float(p.get("stage", 1))]
		"ship_readiness":
			var sh: Dictionary = sim.state["ship"]
			var rd: float = float(sh.get("readiness", 0.0))
			return [int(sh.get("stage", 0)) >= 5 and rd >= float(p.get("min", 80)), rd, float(p.get("min", 80))]
		"full_supply":
			var parts := 0
			var need := 6
			if _fact("o2_ratio") >= float(p.get("o2_ratio", 1.1)):
				parts += 1
			if float(_forecast()["water_days"]) >= float(p.get("water_days", 1.5)):
				parts += 1
			if _dish_days(["meals"]) >= float(p.get("dish_days", 2.0)):
				parts += 1
			if float(_nutrition()["score"]) >= float(p.get("nutrition", 70)):
				parts += 1
			if _fact("life_shed") < 0.5 and float(_forecast()["energy"]) >= float(_forecast()["night_need"]):
				parts += 1
			if _stock("spare_parts") >= int(p.get("spares", 10)):
				parts += 1
			return [parts >= need, float(parts), float(need)]
		"stat":
			var key: String = String(p.get("key", ""))
			var sv: int = int(sim.state["stats"].get(key, 0))
			return [sv >= int(p.get("count", 1)), float(sv), float(p.get("count", 1))]
		"stored_total":
			var s: int = int(_fact("stored_total"))
			return [s >= int(p.get("count", 1)), float(s), float(p.get("count", 1))]
		"distinct_dishes":
			var dd2: int = (sim.state["stats"].get("cooked", {}) as Dictionary).size()
			return [dd2 >= int(p.get("count", 1)), float(dd2), float(p.get("count", 1))]
		"distinct_buildings":
			var db: int = int(_fact("distinct_buildings"))
			return [db >= int(p.get("count", 1)), float(db), float(p.get("count", 1))]
		"size_built":
			var sb: int = int(_fact("max_size"))
			return [sb >= int(p.get("size", 3)), float(sb), float(p.get("size", 3))]
		"power_gen":
			var pg: float = _fact("power_gen")
			return [pg >= float(p.get("p", 100)), pg, float(p.get("p", 100))]
		"lander_survived":
			var ended: bool = sim.util.days_elapsed() >= float(sim.bdef("lander").get("shelter_days", 3.0))
			var ok2: bool = ended and int(sim.state["progress"]["deaths"]) == 0
			return [ok2, 1.0 if ok2 else 0.0, 1.0]
		"cooked":
			var ck: int = int(sim.state["stats"].get("cooked", {}).get(String(p.get("dish", "")), 0))
			return [ck >= int(p.get("count", 1)), float(ck), float(p.get("count", 1))]
		"goal_done":
			var gd: bool = is_done(String(p.get("goal", "")))
			return [gd, 1.0 if gd else 0.0, 1.0]
		"no_death_days":
			var day_ticks: float = float(sim.bal["day_length"]) * float(sim.bal["tick_hz"])
			var last: int = int(sim.state["progress"]["last_death_tick"])
			var since: float = float(int(sim.state["tick"]) - maxi(0, last)) / day_ticks
			var okd: bool = since >= float(p.get("days", 1)) and sim.alive_count() >= int(p.get("min_pop", 0))
			return [okd, since, float(p.get("days", 1))]
		"victory":
			return [victory(), 1.0 if victory() else 0.0, 1.0]
	return [false, 0.0, 1.0]

func _produced(item: String) -> int:
	var pr: Dictionary = sim.state["stats"].get("produced", {})
	if item != "*":
		return int(pr.get(item, 0))
	var n := 0
	for k in pr:
		n += int(pr[k])
	return n

func _has_generator(comp) -> bool:
	var blds: Dictionary = sim.state["buildings"]
	for bid in sim.topo.power_members.get(comp, []):
		var b: Dictionary = blds[bid]
		if b["state"] != "active":
			continue
		var d: Dictionary = sim.bdef(b["def"])
		if d.has("gen_solar") or d.has("gen_wind") or d.has("gen_const"):
			return true
	return false

func _forecast() -> Dictionary:
	if not _facts.has("forecast"):
		_facts["forecast"] = sim.metrics.forecast()
	return _facts["forecast"]

func _nutrition() -> Dictionary:
	if not _facts.has("nutrition"):
		_facts["nutrition"] = sim.nutrition.colony()
	return _facts["nutrition"]

func _stock(item: String) -> int:
	if not _facts.has("totals"):
		_facts["totals"] = sim.inv.totals()
	return int(_facts["totals"].get(item, {}).get("total", 0))

## Dishes in stock per living colonist, leaving out some ids (rations).
func _dish_days(exclude: Array) -> float:
	if not _facts.has("totals"):
		_facts["totals"] = sim.inv.totals()
	var n := 0
	for d in sim.items.dishes():
		if exclude.has(d):
			continue
		n += int(_facts["totals"].get(d, {}).get("total", 0))
	return float(n) / maxf(1.0, float(sim.alive_count()))

func _fact_housing() -> Dictionary:
	if _facts.has("housing"):
		return _facts["housing"]
	var blds: Dictionary = sim.state["buildings"]
	var pop := 0
	var housed := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["kind"] == "visitor":
			continue
		pop += 1
		var bed: Dictionary = blds.get(int(a["bed"]), {})
		if not bed.is_empty() and bed["def"] != "lander":
			housed += 1
	_facts["housing"] = {"pop": pop, "housed": housed}
	return _facts["housing"]

func _fact(key: String) -> float:
	if _facts.has(key):
		return float(_facts[key])
	var v := 0.0
	var blds: Dictionary = sim.state["buildings"]
	match key:
		"o2_ratio":
			var cap: float = sim.util.o2_capacity_per_day()
			var need: float = float(sim.alive_count()) * float(sim.bal["oxygen_per_colonist"])
			v = cap / need if need > 0.0 else 0.0
		"max_level":
			for id in blds:
				var b: Dictionary = blds[id]
				if b["state"] == "active" and b["kind"] != "link":
					v = maxf(v, float(b.get("level", 1)))
		"max_size":
			for id in blds:
				var b: Dictionary = blds[id]
				if b["state"] == "active" and b["kind"] != "link" and sim.bdef(b["def"]).has("sizes"):
					v = maxf(v, float(b.get("size", 1)))
		"distinct_buildings":
			var seen := {}
			for id in blds:
				var b: Dictionary = blds[id]
				if b["state"] == "active" and b["kind"] != "link" and bool(sim.bdef(b["def"]).get("buildable", true)):
					seen[b["def"]] = true
			v = float(seen.size())
		"power_gen":
			for comp in sim.util.power_stats:
				v += sim.util.to_rate(int(sim.util.power_stats[comp]["gen"]))
		"life_shed":
			for comp in sim.util.power_stats:
				for bid in sim.util.power_stats[comp]["shed"]:
					if blds.has(bid) and sim.bdef(blds[bid]["def"]).get("power_class", "") == "life_support":
						v = 1.0
		"stored_total":
			for inv_id in sim.state["inventories"]:
				var inv: Dictionary = sim.state["inventories"][inv_id]
				if inv["role"] != "store":
					continue
				for r in inv["items"]:
					v += float(inv["items"][r])
	_facts[key] = v
	return v
