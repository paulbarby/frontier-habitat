extends RefCounted
## Nutrition (docs/AAA_DESIGN.md section 5). Every colonist has four values, 0..100:
## protein, carbs, fat, vitamins. They are a moving average of the diet: each meal moves
## every value toward the dish's value by meal_weight (0.4):  n = n + (dish - n) x 0.4.
## A one-dish diet therefore settles at that dish's values; a varied diet at their mean.
## Values drift toward 0 (hungry_drift_per_day) only while the colonist is critically
## hungry, i.e. does not eat. The score is the mean of the four.
##   Well fed:  score >= 70 and every value >= 40 -> morale +6, health regeneration x1.5
##   Deficient: any value < 20                    -> morale -8, work x0.9, an alert
##   Starved:   any value < 8                     -> health -10 per day (agents.gd)
##   Variety:   >= 4 distinct dishes in the last 6 -> morale +5; only 1 -> morale -4
##   Taste:     morale + 0.5 x mean taste of the last 3 meals
## Choosing a dish is deterministic: the highest score wins, ties by item id.

var sim
var _n: Array = []
var _cfg: Dictionary

func _init(s) -> void:
	sim = s
	_n = sim.content["nutrients"]
	_cfg = sim.bal["nutrition"]

func nutrients() -> Array:
	return _n

func fresh() -> Dictionary:
	var d := {}
	for k in _n:
		d[k] = float(_cfg["start"])
	return d

static func score_of(n: Dictionary) -> float:
	var s := 0.0
	var c := 0
	for k in n:
		s += float(n[k])
		c += 1
	return s / c if c > 0 else 0.0

func score(a: Dictionary) -> float:
	return score_of(a.get("nutrition", {}))

func well_fed(a: Dictionary) -> bool:
	var n: Dictionary = a.get("nutrition", {})
	if n.is_empty() or score_of(n) < float(_cfg["well_fed_score"]):
		return false
	for k in n:
		if float(n[k]) < float(_cfg["well_fed_min"]):
			return false
	return true

## Nutrients below the deficiency line, in the fixed order of dishes.json.
func deficient(a: Dictionary) -> Array:
	var out: Array = []
	var n: Dictionary = a.get("nutrition", {})
	for k in _n:
		if float(n.get(k, 100.0)) < float(_cfg["deficient_below"]):
			out.append(k)
	return out

func starved(a: Dictionary) -> bool:
	var n: Dictionary = a.get("nutrition", {})
	for k in n:
		if float(n[k]) < float(_cfg["starved_below"]):
			return true
	return false

## True when any nutrient is below the deficiency line (the same test as deficient(), without
## building the list: this runs for every worker every tick).
func any_deficient(a: Dictionary) -> bool:
	var n: Dictionary = a.get("nutrition", {})
	var lim: float = float(_cfg["deficient_below"])
	for k in _n:
		if float(n.get(k, 100.0)) < lim:
			return true
	return false

func work_mult(a: Dictionary) -> float:
	return float(_cfg["deficient_work_mult"]) if any_deficient(a) else 1.0

func regen_mult(a: Dictionary) -> float:
	return float(_cfg["well_fed_regen_mult"]) if well_fed(a) else 1.0

## The morale change from food: well fed or deficient, variety and taste.
func morale_delta(a: Dictionary) -> float:
	var m := 0.0
	if well_fed(a):
		m += float(_cfg["well_fed_morale"])
	elif any_deficient(a):
		m += float(_cfg["deficient_morale"])
	# Variety and taste over the last meals, without copying the diet (runs once a second
	# for every colonist; the same sums in the same order as before).
	var diet: Array = a.get("diet", [])
	var n: int = diet.size()
	var from: int = maxi(0, n - int(_cfg["variety_window"]))
	var distinct: Array = []
	for i in range(from, n):
		if not distinct.has(diet[i]):
			distinct.append(diet[i])
	if distinct.size() >= int(_cfg["variety_good"]):
		m += float(_cfg["variety_good_morale"])
	elif distinct.size() == 1 and n - from >= 3:
		m += float(_cfg["variety_bad_morale"])
	var from2: int = maxi(0, n - int(_cfg["taste_window"]))
	if n > from2:
		var t := 0.0
		for i in range(from2, n):
			t += float(sim.items.info(String(diet[i])).get("taste", 0.0))
		m += float(_cfg["taste_morale_mult"]) * t / (n - from2)
	return m

## Once per second: while the colonist is critically hungry (not eating), every value
## drifts toward 0 by hungry_drift_per_day (scaled by the difficulty). A colonist who eats
## keeps the levels of the diet.
func decay_second(a: Dictionary) -> void:
	if float(a.get("hunger", 0.0)) < float(sim.bal["need_critical"]):
		return
	var n: Dictionary = a["nutrition"]
	var per: float = float(_cfg["hungry_drift_per_day"]) / float(sim.bal["day_length"]) * sim.difficulty("need_mult")
	for k in n:
		n[k] = maxf(0.0, float(n[k]) - per)

## A colonist eats one dish.
func eat(a: Dictionary, dish: String) -> void:
	var info: Dictionary = sim.items.info(dish)
	var n: Dictionary = a["nutrition"]
	var dn: Dictionary = info.get("nutrition", {})
	var w: float = float(_cfg["meal_weight"])
	for k in dn:
		var cur: float = float(n.get(k, 0.0))
		n[k] = clampf(cur + (float(dn[k]) - cur) * w, 0.0, 100.0)
	var diet: Array = a["diet"]
	diet.append(dish)
	while diet.size() > int(_cfg["variety_window"]):
		diet.pop_front()

## How much a colonist wants one dish now (design section 5).
func want(a: Dictionary, dish: String) -> float:
	var info: Dictionary = sim.items.info(dish)
	var dn: Dictionary = info.get("nutrition", {})
	var n: Dictionary = a["nutrition"]
	var target: float = float(_cfg["target"])
	var s := 0.0
	for k in _n:
		s += maxf(0.0, target - float(n.get(k, target))) * float(dn.get(k, 0.0)) / 100.0
	s += float(_cfg["choice_taste_weight"]) * float(info.get("taste", 0.0))
	var diet: Array = a["diet"]
	if not diet.slice(maxi(0, diet.size() - int(_cfg["taste_window"]))).has(dish):
		s += float(_cfg["choice_novelty_bonus"])
	return s

## The dish this colonist picks from an inventory, or "" when it holds none.
func choose(a: Dictionary, inv_id: int) -> String:
	var best := ""
	var best_s := -1e18
	for d in sim.items.dishes():
		if sim.inv.available(inv_id, d) <= 0:
			continue
		var s: float = want(a, d)
		if s > best_s:
			best_s = s
			best = d
	return best

## Colony averages for the interface and the kitchen planner:
## {protein, carbs, fat, vitamins, score, people}.
func colony() -> Dictionary:
	var sum := {}
	for k in _n:
		sum[k] = 0.0
	var people := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["kind"] == "visitor":
			continue
		people += 1
		var n: Dictionary = a.get("nutrition", {})
		for k in _n:
			sum[k] = float(sum[k]) + float(n.get(k, 0.0))
	var out := {}
	for k in _n:
		out[k] = float(sum[k]) / people if people > 0 else 0.0
	out["score"] = score_of(out) if people > 0 else 0.0
	out["people"] = people
	return out

## Names of the nutrients that the most colonists lack, for the alert text.
func shortage_counts() -> Dictionary:
	var out := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["kind"] == "visitor":
			continue
		for k in deficient(a):
			out[k] = int(out.get(k, 0)) + 1
	return out
