extends RefCounted
## Research (docs/AAA_DESIGN.md section 6). A research lab turns scientist work into
## research points (RP): RP = work points x rp_per_work x lab level multiplier x research
## bonuses. RP go to the active project; when it completes, the next project in the queue
## that can start starts. Tier-5 special projects also need items (exotic crystals)
## delivered to a research lab before any progress counts.
##
## state.research = {active, queue[], progress{tech: rp}, done{tech: tick}, paid{tech: tick},
##                   rp_total, bank, rate, sec}
##   bank: RP from goal rewards while no project was active; spent on the next project.
##   rate: RP per day, a one-minute moving average (for rp_rate()).
##   sec:  RP made in the current second (folded into rate once per second).

var sim
var _bonus := {}           # bonus key -> summed value of done techs (derived cache)
var _bonus_rev := -1
var _recipe_tech := {}     # recipe id -> tech that unlocks it
var _family_tech := {}     # building family -> tier-5 tech

func _init(s) -> void:
	sim = s
	var techs: Dictionary = sim.content["techs"]
	for id in techs:
		var t: Dictionary = techs[id]
		for r in t.get("unlocks", {}).get("recipes", []):
			_recipe_tech[r] = id
		if String(t.get("family", "")) != "":
			_family_tech[String(t["family"])] = id
		for f in t.get("families", []):
			_family_tech[String(f)] = id

static func fresh_state() -> Dictionary:
	return {"active": "", "queue": [], "progress": {}, "done": {}, "paid": {}, "rp_total": 0.0, "bank": 0.0, "rate": 0.0, "sec": 0.0}

func st() -> Dictionary:
	return sim.state["research"]

func techs() -> Dictionary:
	return sim.content["techs"]

# ---------------------------------------------------------------- queries
func is_done(tech: String) -> bool:
	if tech == "":
		return true
	return st()["done"].has(tech)

func done_count() -> int:
	return st()["done"].size()

## True when every prerequisite is done and the tech itself is not.
func can_start(tech: String) -> bool:
	if not techs().has(tech) or is_done(tech):
		return false
	for r in techs()[tech].get("requires", []):
		if not is_done(r):
			return false
	return true

## "done" | "active" | "queued" | "available" | "locked"
func state_of(tech: String) -> String:
	if is_done(tech):
		return "done"
	if String(st()["active"]) == tech:
		return "active"
	if (st()["queue"] as Array).has(tech):
		return "queued"
	if can_start(tech):
		return "available"
	return "locked"

func is_special(tech: String) -> bool:
	return techs().has(tech) and not (techs()[tech].get("items", {}) as Dictionary).is_empty()

func is_paid(tech: String) -> bool:
	return not is_special(tech) or st()["paid"].has(tech)

## RP still needed by a project.
func remaining(tech: String) -> float:
	if not techs().has(tech):
		return 0.0
	return maxf(0.0, float(techs()[tech]["cost"]) - float(st()["progress"].get(tech, 0.0)))

## Fraction 0..1 of a project.
func fraction(tech: String) -> float:
	if is_done(tech):
		return 1.0
	if not techs().has(tech):
		return 0.0
	return clampf(float(st()["progress"].get(tech, 0.0)) / maxf(1.0, float(techs()[tech]["cost"])), 0.0, 1.0)

## True when a scientist can put work into the active project now.
func workable() -> bool:
	var a: String = st()["active"]
	return a != "" and is_paid(a)

## Items the active special project still waits for ({} when none).
func items_needed() -> Dictionary:
	var a: String = st()["active"]
	if a == "" or is_paid(a):
		return {}
	return techs()[a]["items"]

## RP per day over the last minute or so.
func rp_rate() -> float:
	return float(st().get("rate", 0.0))

## Colony-wide bonus from finished research: the sum of "bonus" values of done techs.
## solar_mult 0.2 means +20 %.
func bonus(key: String) -> float:
	var rev: int = st()["done"].size()
	if rev != _bonus_rev:
		_bonus = {}
		for id in st()["done"]:
			if not techs().has(id):
				continue
			var bn: Dictionary = techs()[id].get("bonus", {})
			for k in bn:
				_bonus[k] = float(_bonus.get(k, 0.0)) + float(bn[k])
		_bonus_rev = rev
	return float(_bonus.get(key, 0.0))

func building_unlocked(def_id: String) -> bool:
	var def: Dictionary = sim.content["buildings"].get(def_id, {})
	return is_done(String(def.get("research", ""))) or sim.unlocked_all()

func crop_unlocked(crop: String) -> bool:
	var c: Dictionary = sim.content["crops"].get(crop, {})
	if c.is_empty():
		return false
	return is_done(String(c.get("research", ""))) or sim.unlocked_all()

func recipe_unlocked(rid: String) -> bool:
	return is_done(String(_recipe_tech.get(rid, ""))) or sim.unlocked_all()

## The tech a building needs to reach `level` ("" = none). Level 5 needs the tier-5
## special tech of the building's family.
func level_tech(def_id: String, level: int) -> String:
	var gates: Array = sim.bal["levels"]["research"]
	if level < 1 or level > gates.size():
		return ""
	var g: String = String(gates[level - 1])
	if g == "family":
		var fam: String = String(sim.content["buildings"].get(def_id, {}).get("family", ""))
		return String(_family_tech.get(fam, "__none__"))
	return g

## The research multiplier of one lab: level x (1 + research bonuses + comms) x difficulty.
func lab_mult(lab: Dictionary) -> float:
	var d: Dictionary = sim.bd(lab)
	var m: float = float(d.get("level_mult", 1.0))
	var add: float = bonus("research_mult") + comms_bonus()
	return m * (1.0 + add) * sim.difficulty("research_mult")

## +10 % while a comms tower works (not more than one counts). The towers are found
## again only when the set of buildings changes (count or next id); their power is read
## every tick, so the answer is always the one a full scan would give.
var _comms := 0.0
var _comms_tick := -1
var _towers: Array = []
var _towers_key := ""

func comms_bonus() -> float:
	var tick: int = int(sim.state["tick"])
	if tick == _comms_tick:
		return _comms
	_comms_tick = tick
	var blds: Dictionary = sim.state["buildings"]
	var key: String = "%d:%d" % [blds.size(), int(sim.state["next_id"])]
	if key != _towers_key:
		_towers_key = key
		_towers = []
		for id in blds:
			if sim.bdef(blds[id]["def"]).has("research_bonus"):
				_towers.append(id)
	_comms = 0.0
	for id in _towers:
		var b: Dictionary = blds.get(id, {})
		if not b.is_empty() and b["state"] == "active" and bool(b["powered"]):
			_comms = float(sim.bdef(b["def"])["research_bonus"])
			break
	return _comms

# ---------------------------------------------------------------- changes
## Work by a scientist in a lab. Returns the RP added.
func add_work(lab: Dictionary, work_points: float) -> float:
	if not workable():
		return 0.0
	var rp: float = work_points * float(sim.bal["research"]["rp_per_work"]) * lab_mult(lab)
	_add(rp)
	return rp

## RP from a goal reward. Banked while no project is active.
func add_rp(rp: float) -> void:
	if rp <= 0.0:
		return
	var a: String = st()["active"]
	if a == "" or not is_paid(a):
		st()["bank"] = float(st()["bank"]) + rp
		return
	_add(rp)

func _add(rp: float) -> void:
	var r: Dictionary = st()
	var a: String = r["active"]
	if a == "":
		return
	r["progress"][a] = float(r["progress"].get(a, 0.0)) + rp
	r["rp_total"] = float(r["rp_total"]) + rp
	r["sec"] = float(r.get("sec", 0.0)) + rp
	if float(r["progress"][a]) >= float(techs()[a]["cost"]) - 0.0001:
		var over: float = float(r["progress"][a]) - float(techs()[a]["cost"])
		_complete(a)
		if over > 0.0:
			add_rp(over)

func _complete(tech: String) -> void:
	var r: Dictionary = st()
	r["done"][tech] = int(sim.state["tick"])
	r["progress"].erase(tech)
	r["active"] = ""
	sim.stat_add("techs", "", 1)
	sim.log_event("research", "Research complete: %s. %s" % [techs()[tech]["name"], String(techs()[tech].get("desc", ""))], [], 1)
	_start_next()

## Starts the first project of the queue that can start. Queue entries that are done are
## dropped; entries still waiting for a prerequisite stay in order.
func _start_next() -> void:
	var r: Dictionary = st()
	if String(r["active"]) != "":
		return
	var q: Array = r["queue"]
	for i in range(q.size() - 1, -1, -1):
		if is_done(String(q[i])) or not techs().has(q[i]):
			q.remove_at(i)
	for i in q.size():
		if can_start(String(q[i])):
			r["active"] = String(q[i])
			q.remove_at(i)
			sim.log_event("research_start", "Research started: %s." % techs()[r["active"]]["name"], [], 0)
			var bank: float = float(r["bank"])
			if bank > 0.0 and is_paid(r["active"]):
				r["bank"] = 0.0
				_add(bank)
			return

## Command "research": make `tech` active now. Missing prerequisites are queued first, in
## order, so a click on any node of the tree does the right thing.
func cmd_research(tech: String) -> Dictionary:
	if not techs().has(tech):
		return {"ok": false, "code": "unknown"}
	if is_done(tech):
		return {"ok": false, "code": "done"}
	var chain: Array = []
	_missing_chain(tech, chain)
	var r: Dictionary = st()
	var q: Array = r["queue"]
	# The old active project goes back to the front of the queue; its RP stay.
	if String(r["active"]) != "" and not chain.has(r["active"]):
		q.push_front(r["active"])
	r["active"] = ""
	for i in range(chain.size() - 1, -1, -1):
		q.erase(chain[i])
		q.push_front(chain[i])
	_start_next()
	return {"ok": true, "code": "ok"}

func _missing_chain(tech: String, out: Array) -> void:
	if is_done(tech) or out.has(tech):
		return
	for req in techs()[tech].get("requires", []):
		_missing_chain(String(req), out)
	out.append(tech)

## Command "research_queue": replace the queue. Unknown and finished techs are dropped.
func cmd_queue(list: Array) -> Dictionary:
	var q: Array = []
	for t in list:
		var id: String = String(t)
		if techs().has(id) and not is_done(id) and not q.has(id) and id != String(st()["active"]):
			q.append(id)
	st()["queue"] = q
	_start_next()
	return {"ok": true, "code": "ok"}

## Consumes the items of the active special project from a lab's input buffer once all
## of them are there. Returns true when the project is paid.
func pay_from(lab: Dictionary) -> bool:
	var need: Dictionary = items_needed()
	if need.is_empty():
		return true
	if int(lab.get("inv_in", -1)) == -1:
		return false
	for res in need:
		if sim.inv.available(lab["inv_in"], res) < int(need[res]):
			return false
	var a: String = st()["active"]
	for res in need:
		sim.inv.consume(lab["inv_in"], res, int(need[res]), "research")
		sim.stat_add("consumed", res, int(need[res]))
	st()["paid"][a] = int(sim.state["tick"])
	sim.log_event("research_paid", "%s: the research lab has the %s it needs. Work can start." % [techs()[a]["name"], _items_text(need)], [lab["id"]], 1)
	var bank: float = float(st()["bank"])
	if bank > 0.0:
		st()["bank"] = 0.0
		_add(bank)
	return true

func _items_text(d: Dictionary) -> String:
	return sim.items.list_text(d)

func tick_second() -> void:
	var r: Dictionary = st()
	var day: float = float(sim.bal["day_length"])
	var per_day: float = float(r.get("sec", 0.0)) * day
	r["rate"] = float(r.get("rate", 0.0)) + (per_day - float(r.get("rate", 0.0))) / 60.0
	r["sec"] = 0.0
	if String(r["active"]) == "":
		_start_next()
