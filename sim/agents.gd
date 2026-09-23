extends RefCounted
## Colonists (spec 9): needs, decisions, plans, movement, airlock queues, survival.
## Decision order each second: immediate survival -> evacuation -> critical personal
## needs -> work (emergency class is inside the task score) -> ordinary needs come
## before NEW work -> recreation -> idle at a safe place.
## A plan is a list of steps: go / pickup / deliver / work / eat / drink / sleep / rec /
## heal / wait. Routes are checked against suit air BEFORE a plan starts (spec 8).

var sim

## Work points a scientist puts in before the research task ends and is offered again.
const RESEARCH_SESSION := 90.0
## Seconds a task rests after a colonist found it out of suit range or without air.
const TASK_REST_SECONDS := 15.0

func _init(s) -> void:
	sim = s

# ---------------------------------------------------------------- creation
func spawn(role: String, agent_name: String, pos: Vector2, bld: int) -> Dictionary:
	var id: int = sim.new_id()
	var a := {
		"id": id, "name": agent_name, "role": role, "state": "alive", "kind": "human",
		"pos": pos, "where": "in" if bld != -1 else "out", "bld": bld, "facing": 0.0,
		"health": 100.0, "hunger": 12.0, "thirst": 12.0, "fatigue": 8.0,
		"morale": float(sim.bal["morale_start"]), "suit": float(sim.bal["suit_air_seconds"]), "o2_grace": 0.0,
		"inv": -1, "bed": -1, "task": -1,
		"plan": [], "pi": 0, "plan_kind": "", "goal": "Idle",
		"route": {}, "li": 0, "wi": 0, "act_t": -1.0, "work_wait": 0.0, "sleeping": false,
		"return_secs": 0.0, "last_dining": -1000000, "last_rec": -1000000,
		"backoff": {}, "cause": "", "born": int(sim.state["tick"]), "rescue": false, "queued": -1, "queue_since": 0,
		"nutrition": sim.nutrition.fresh(), "diet": [], "rec_bonus": 0.0, "medicated": false,
	}
	a["inv"] = sim.inv.create_inv("a", id, "carry", int(sim.bal["carry_human"]))
	sim.state["agents"][id] = a
	sim.alive_changed()
	return a

func hz() -> float:
	return float(sim.bal["tick_hz"])

func loc_of(a: Dictionary) -> Dictionary:
	return {"b": -1 if a["where"] == "out" else int(a["bld"]), "p": a["pos"]}

func breathable(a: Dictionary) -> bool:
	if a["where"] == "out":
		return false
	return sim.util.building_supplied(a["bld"])

## Longest one-way walk (metres on foot) from an airlock that still leaves time for a short
## spell of work and the walk back inside 70% of a full suit (spec 8).
func suit_reach_metres() -> float:
	var bal: Dictionary = sim.bal
	var budget: float = float(bal["suit_air_seconds"]) * float(bal["suit_task_fraction"]) - float(bal["exterior_work_chunk_seconds"])
	return maxf(0.0, budget * 0.5 * sim.util.out_speed())

## Straight-line metres from p to the nearest airlock door (or lander hatch) with air.
func nearest_air_metres(p: Vector2) -> float:
	var best := 1e9
	for comp in sim.topo.locks_by_comp:
		if not sim.util.comp_supplied(comp):
			continue
		for lid in sim.topo.locks_by_comp[comp]:
			best = minf(best, sim.nav.door_pos(sim.state["buildings"][lid]).distance_to(p))
	return best

func productivity(a: Dictionary) -> float:
	var p := 1.0
	if float(a["morale"]) < float(sim.bal["morale_very_low"]):
		p = float(sim.bal["productivity_very_low"])
	elif float(a["morale"]) < float(sim.bal["morale_low"]):
		p = float(sim.bal["productivity_low"])
	if float(a["health"]) < 40.0:
		p *= 0.7
	if a.has("nutrition"):
		p *= sim.nutrition.work_mult(a)
	return p

# ---------------------------------------------------------------- needs (every tick)
func needs_tick() -> void:
	var bal: Dictionary = sim.bal
	var dt: float = 1.0 / hz()
	var day: float = float(bal["day_length"])
	var crit: float = float(bal["need_critical"])
	var need_mult: float = sim.difficulty("need_mult")
	var starved_dmg: float = float(bal["nutrition"]["starved_damage_per_day"]) / day * dt
	# Constant for this tick: worked out once, in the same order as before (same values).
	var hunger_inc: float = float(bal["hunger_per_day"]) * need_mult / day * dt
	var thirst_inc: float = float(bal["thirst_per_day"]) * need_mult / day * dt
	var rest_dec: float = 100.0 / float(bal["sleep_seconds_full"]) * dt
	var tire_inc: float = 100.0 / float(bal["fatigue_awake_seconds"]) * dt
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		a["hunger"] = minf(100.0, float(a["hunger"]) + hunger_inc)
		a["thirst"] = minf(100.0, float(a["thirst"]) + thirst_inc)
		if bool(a["sleeping"]):
			a["fatigue"] = maxf(0.0, float(a["fatigue"]) - rest_dec)
		else:
			a["fatigue"] = minf(100.0, float(a["fatigue"]) + tire_inc)
		var ok_air: bool = breathable(a)
		if ok_air:
			a["o2_grace"] = 0.0
		else:
			a["suit"] = maxf(0.0, float(a["suit"]) - dt)
			if float(a["suit"]) <= 0.0:
				a["o2_grace"] = float(a["o2_grace"]) + dt
				if float(a["o2_grace"]) > float(bal["o2_grace_seconds"]):
					_hurt(a, float(bal["o2_damage_per_second"]) * dt, "lack of oxygen")
		var harmed := false
		if float(a["hunger"]) >= crit:
			_hurt(a, float(bal["starve_damage_per_day"]) / day * dt * _severity(a["hunger"], crit), "starvation")
			harmed = true
		if float(a["thirst"]) >= crit:
			_hurt(a, float(bal["dehydrate_damage_per_day"]) / day * dt * _severity(a["thirst"], crit), "dehydration")
			harmed = true
		if float(a["fatigue"]) >= 100.0:
			_hurt(a, float(bal["exhaustion_damage_per_day"]) / day * dt, "exhaustion")
		# Starved of a nutrient (design section 5): slow damage, and no healing. The flag is
		# set once per second in morale_second().
		if bool(a.get("starved", false)):
			_hurt(a, starved_dmg, "malnutrition")
			harmed = true
		if a["state"] == "alive" and not harmed and ok_air and float(a["health"]) < 100.0:
			var regen: float = float(bal["health_regen_per_day"]) * sim.nutrition.regen_mult(a)
			if a["plan_kind"] == "heal" and _step_op(a) == "heal":
				regen = float(bal["medical_regen_per_day"]) * _heal_mult(a)
			a["health"] = minf(100.0, float(a["health"]) + regen / day * dt)

static func _severity(value: float, crit: float) -> float:
	return 0.3 + 0.7 * clampf((value - crit) / maxf(1.0, 100.0 - crit), 0.0, 1.0)

func _hurt(a: Dictionary, amount: float, cause: String) -> void:
	a["health"] = float(a["health"]) - amount
	a["cause"] = cause
	if float(a["health"]) <= 0.0:
		_die(a, cause)

func _die(a: Dictionary, cause: String) -> void:
	a["health"] = 0.0
	a["cause"] = cause
	abort_plan(a, "died")
	_drop_cargo(a)
	a["state"] = "dead"
	a["goal"] = "Dead"
	a["death_tick"] = int(sim.state["tick"])
	sim.alive_changed()
	var pr: Dictionary = sim.state["progress"]
	pr["deaths"] = int(pr["deaths"]) + 1
	pr["last_death_tick"] = int(sim.state["tick"])
	var where_text: String = "outside" if a["where"] == "out" else "in " + String(sim.state["buildings"].get(a["bld"], {}).get("name", "the base"))
	sim.log_event("death", "%s (%s) died of %s, %s." % [a["name"], sim.bal["role_names"].get(a["role"], a["role"]), cause, where_text], [a["id"]], 3)

# ---------------------------------------------------------------- airlocks (every tick)
func locks_tick() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var agents: Dictionary = sim.state["agents"]
	var dt: float = 1.0 / hz()
	var cap: float = float(sim.bal["suit_air_seconds"])
	for id in blds:
		var b: Dictionary = blds[id]
		var lock: Dictionary = b["lock"]
		if lock.is_empty():
			continue
		var cyc: Dictionary = lock["cyc"]
		var supplied: bool = sim.util.building_supplied(id)
		if not cyc.is_empty():
			cyc["t"] = float(cyc["t"]) - dt
			for aid in cyc["agents"]:
				if agents.has(aid) and supplied and agents[aid]["state"] == "alive":
					agents[aid]["suit"] = minf(cap, float(agents[aid]["suit"]) + float(sim.bal["suit_refill_per_second"]) * dt)
			if float(cyc["t"]) <= 0.0:
				for aid in cyc["agents"]:
					if not agents.has(aid) or agents[aid]["state"] != "alive":
						continue
					var a: Dictionary = agents[aid]
					if cyc["dir"] == "in":
						a["where"] = "in"
						a["bld"] = id
						a["pos"] = b["pos"]
					else:
						a["where"] = "out"
						a["bld"] = -1
						a["pos"] = sim.nav.door_pos(b)
					if supplied:
						a["suit"] = cap
					a["li"] = int(a["li"]) + 1
					a["wi"] = 0
					a["queued"] = -1
				lock["cyc"] = {}
			continue
		var queue: Array = lock["queue"]
		if queue.is_empty():
			continue
		for i in range(queue.size() - 1, -1, -1):
			var q: Dictionary = queue[i]
			if not agents.has(q["a"]) or agents[q["a"]]["state"] != "alive" or int(agents[q["a"]]["queued"]) != id:
				queue.remove_at(i)
		if queue.is_empty():
			continue
		# People outside who are low on air go first. The rest stay in arrival order.
		var low: float = cap * float(sim.bal["suit_return_fraction"])
		var head := 0
		for i in queue.size():
			if queue[i]["dir"] == "in" and float(agents[queue[i]["a"]]["suit"]) < low:
				head = i
				break
		var dir: String = queue[head]["dir"]
		var riders: Array = []
		var slots: int = int(sim.bal["airlock_slots"])
		var order: Array = [head]
		for i in queue.size():
			if i != head:
				order.append(i)
		for i in order:
			if riders.size() < slots and queue[i]["dir"] == dir:
				riders.append(queue[i]["a"])
		for i in range(queue.size() - 1, -1, -1):
			if riders.has(queue[i]["a"]):
				queue.remove_at(i)
		var secs: float = float(sim.bal["airlock_cycle_seconds"])
		if float(sim.bdef(b["def"]).get("power", 0.0)) > 0.0 and not bool(b["powered"]):
			secs *= float(sim.bal["airlock_unpowered_mult"])
		for aid in riders:
			var a: Dictionary = agents[aid]
			a["where"] = "lock"
			a["bld"] = id
		lock["cyc"] = {"agents": riders, "dir": dir, "t": secs, "total": secs}

func _enqueue(a: Dictionary, lock_id: int, dir: String) -> void:
	if int(a["queued"]) == lock_id:
		return
	var b: Dictionary = sim.state["buildings"][lock_id]
	(b["lock"]["queue"] as Array).append({"a": a["id"], "dir": dir})
	a["queued"] = lock_id
	a["queue_since"] = int(sim.state["tick"])

func _leave_queues(a: Dictionary) -> void:
	if int(a["queued"]) == -1:
		return
	var b: Dictionary = sim.state["buildings"].get(a["queued"], {})
	a["queued"] = -1
	if b.is_empty() or (b["lock"] as Dictionary).is_empty():
		return
	var queue: Array = b["lock"]["queue"]
	for i in range(queue.size() - 1, -1, -1):
		if int(queue[i]["a"]) == int(a["id"]):
			queue.remove_at(i)

# ---------------------------------------------------------------- decisions (each second)
func think_tick() -> void:
	var tick: int = int(sim.state["tick"])
	var n: int = int(hz())
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and (tick + int(aid)) % n == 0:
			_think(a)

func _think(a: Dictionary) -> void:
	var bal: Dictionary = sim.bal
	if a["where"] == "lock":
		return
	var cap: float = float(bal["suit_air_seconds"])
	a["rescue"] = false
	# 1. Immediate survival: exposed and the air margin is gone -> go to supplied air.
	if not breathable(a) and a["plan_kind"] != "safety":
		var ret: float = _return_seconds(a)
		a["return_secs"] = ret
		if ret >= 1e8:
			a["rescue"] = true
		else:
			var limit: float = maxf(cap * float(bal["suit_return_fraction"]), ret * 1.25 + float(bal["suit_return_margin_seconds"]))
			if a["where"] != "out":
				limit = maxf(limit, cap * 0.5)
			if float(a["suit"]) <= limit:
				_start_safety(a)
				return
	# 2. Evacuation: the room is being removed.
	if a["where"] == "in" and a["plan_kind"] != "safety":
		var here: Dictionary = sim.state["buildings"].get(a["bld"], {})
		if not here.is_empty() and bool(here["demolish"]) and (a["plan"] as Array).is_empty():
			if _go_somewhere_safe(a, a["bld"]):
				return
	# 3. Critical personal needs interrupt work.
	var crit: float = float(bal["need_critical"])
	var kind: String = a["plan_kind"]
	if kind != "safety":
		if float(a["thirst"]) >= crit and kind != "drink" and _try_drink(a):
			return
		if float(a["hunger"]) >= crit and kind != "eat" and kind != "drink" and _try_eat(a):
			return
		if float(a["fatigue"]) >= crit and kind != "sleep" and kind != "eat" and kind != "drink" and _try_sleep(a):
			return
	if not (a["plan"] as Array).is_empty():
		return
	# 4. Ordinary needs, before new work is taken.
	var trig: float = float(bal["need_trigger"])
	if float(a["thirst"]) >= trig and _try_drink(a):
		return
	if float(a["hunger"]) >= trig and _try_eat(a):
		return
	if _wants_sleep(a) and _try_sleep(a):
		return
	if float(a["health"]) < 55.0 and _try_heal(a):
		return
	# 5. Work.
	if _try_work(a):
		return
	# 6. Recreation, then idle somewhere safe.
	if _wants_rec(a) and _try_rec(a):
		return
	_idle(a)

func _return_seconds(a: Dictionary) -> float:
	if a["where"] == "out":
		var r: Dictionary = _walk_back(a)
		if not r["ok"]:
			return 1e9
		# The walk back plus the expected wait at that door: people already queued outside
		# ride first, two per cycle. Without this a busy hatch leaves the last one airless.
		var lock: Dictionary = sim.state["buildings"][r["lock"]]["lock"]
		var ahead := 0
		for q in lock["queue"]:
			if q["dir"] == "in":
				ahead += 1
		var cycles: int = 1 + int(ahead / int(sim.bal["airlock_slots"]))
		return float(r["seconds"]) + float(cycles) * float(sim.bal["airlock_cycle_seconds"]) * 0.8
	# Inside a room without air: leave through its airlock and walk to supplied air.
	var target: int = _nearest_supplied_room(a["pos"], -1)
	if target == -1:
		return 1e9
	var route: Dictionary = sim.nav.plan(loc_of(a), {"b": target, "p": sim.state["buildings"][target]["pos"]})
	return float(route["seconds"]) if route["ok"] else 1e9

## The walk back to the nearest supplied airlock, in seconds. Two outdoor paths cost
## about half a millisecond, so the answer is kept with the colonist ("ret_c") and made
## again after 10 s, after 6 m of walking, or when the map or that airlock changes.
## Between two searches the kept length plus the straight distance walked since is used:
## never shorter than the true walk back, so the estimate errs on the safe side.
func _walk_back(a: Dictionary) -> Dictionary:
	var tick: int = int(sim.state["tick"])
	var rev: int = int(sim.state["rev"]["walk"])
	var pos: Vector2 = a["pos"]
	var rc: Dictionary = a.get("ret_c", {})
	if not rc.is_empty() and int(rc["rev"]) == rev and tick - int(rc["t"]) < 100:
		var moved: float = pos.distance_to(rc["p"])
		var lid: int = int(rc["lock"])
		if moved <= 6.0 and sim.state["buildings"].has(lid) and sim.util.building_supplied(lid):
			return {"ok": true, "lock": lid, "seconds": (float(rc["len"]) + moved) / sim.util.out_speed()}
	var r: Dictionary = sim.nav.nearest_supplied_lock(pos)
	if r["ok"]:
		a["ret_c"] = {"t": tick, "p": pos, "len": float(r["seconds"]) * sim.util.out_speed(), "lock": int(r["lock"]), "rev": rev}
	else:
		a["ret_c"] = {}
	return r

func _nearest_supplied_room(from: Vector2, skip: int) -> int:
	var best := -1
	var best_d := 1e18
	for comp in sim.topo.locks_by_comp:
		if not sim.util.comp_supplied(comp):
			continue
		for lid in sim.topo.locks_by_comp[comp]:
			if lid == skip:
				continue
			var d: float = (sim.state["buildings"][lid]["pos"] as Vector2).distance_to(from)
			if d < best_d:
				best_d = d
				best = lid
	return best

func _start_safety(a: Dictionary) -> void:
	var target: int = _nearest_supplied_room(a["pos"], -1)
	if target == -1:
		a["rescue"] = true
		return
	var b: Dictionary = sim.state["buildings"][target]
	var to := {"b": target, "p": b["pos"]}
	var route: Dictionary = sim.nav.plan(loc_of(a), to)
	if not route["ok"]:
		a["rescue"] = true
		return
	abort_plan(a, "low_air")
	_start_plan(a, "safety", [{"op": "go", "to": to, "route": route, "rev": int(sim.state["rev"]["walk"])}, {"op": "wait", "t": 1.0}], "Returning to air")

func _go_somewhere_safe(a: Dictionary, avoid: int) -> bool:
	var best := -1
	var best_d := 1e18
	var blds: Dictionary = sim.state["buildings"]
	for bid in sim.topo.atmo_comp:
		if bid == avoid:
			continue
		var b: Dictionary = blds[bid]
		if bool(b["demolish"]) or b["state"] != "active" or not sim.util.building_supplied(bid):
			continue
		var d: float = (b["pos"] as Vector2).distance_to(a["pos"])
		if d < best_d:
			best_d = d
			best = bid
	if best == -1:
		return false
	return _start_personal(a, "idle", best, [{"op": "wait", "t": 2.0}], "Moving to a safe room", -1)

# ---------------------------------------------------------------- personal plans
## Builds "go to room, then steps". Refuses when there is no route or not enough air.
func _start_personal(a: Dictionary, kind: String, bid: int, steps: Array, goal: String, slot: int) -> bool:
	var b: Dictionary = sim.state["buildings"][bid]
	var p: Vector2 = sim.nav.slot_pos(b, int(a["id"]) if slot < 0 else slot)
	var to := {"b": bid, "p": p}
	var route: Dictionary = sim.nav.plan(loc_of(a), to)
	if not route["ok"]:
		return false
	if not _air_ok(a, route["legs"], 0.0, bid, p):
		return false
	abort_plan(a, "need_" + kind)
	var plan: Array = [{"op": "go", "to": to, "route": route, "rev": int(sim.state["rev"]["walk"])}]
	plan.append_array(steps)
	_start_plan(a, kind, plan, goal)
	return true

func _try_drink(a: Dictionary) -> bool:
	var blds: Dictionary = sim.state["buildings"]
	var cands: Array = []
	for bid in sim.topo.atmo_comp:
		var b: Dictionary = blds[bid]
		if b["state"] != "active" or bool(b["demolish"]) or not sim.util.building_supplied(bid):
			continue
		if bool(sim.bdef(b["def"]).get("tap", false)) and sim.util.can_drink_at(bid):
			cands.append([(b["pos"] as Vector2).distance_to(a["pos"]), bid, -1])
		elif int(b["inv_out"]) != -1 and sim.inv.get_inv(b["inv_out"]).get("role", "") == "store" and sim.inv.available(b["inv_out"], "water") >= int(sim.bal["drink_units"]):
			cands.append([(b["pos"] as Vector2).distance_to(a["pos"]) + 5.0, bid, int(b["inv_out"])])
	cands.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	for c in cands.slice(0, 2):
		var hold := -1
		if int(c[2]) != -1:
			hold = sim.inv.hold_out(c[2], "water", int(sim.bal["drink_units"]), -int(a["id"]))
			if hold == -1:
				continue
		if _start_personal(a, "drink", c[1], [{"op": "drink", "hold": hold}], "Going to drink", -1):
			if hold != -1:
				# abort_plan released personal holds; take it again for the new plan.
				hold = sim.inv.hold_out(c[2], "water", int(sim.bal["drink_units"]), -int(a["id"]))
				a["plan"][1]["hold"] = hold
			return true
		sim.inv.release(hold)
	return false

## Food is any dish (design section 5): cooked dishes and emergency rations. The colonist
## goes to the nearest room with food (a dining room counts as nearer) and takes the dish
## it wants most there (nutrition.choose).
func _try_eat(a: Dictionary) -> bool:
	var blds: Dictionary = sim.state["buildings"]
	var dishes: Array = sim.items.dishes()
	var cands: Array = []
	for bid in sim.topo.atmo_comp:
		var b: Dictionary = blds[bid]
		if (b["state"] != "active" and b["state"] != "broken") or bool(b["demolish"]) or not sim.util.building_supplied(bid):
			continue
		if int(b["inv_out"]) == -1 or sim.inv.available_any(b["inv_out"], dishes) < 1:
			continue
		var bonus: float = 0.0 if bool(sim.bdef(b["def"]).get("dining", false)) else 12.0
		cands.append([(b["pos"] as Vector2).distance_to(a["pos"]) + bonus, bid, int(b["inv_out"])])
	cands.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	for c in cands.slice(0, 2):
		if _start_personal(a, "eat", c[1], [{"op": "eat", "hold": -1, "dish": ""}], "Going to eat", -1):
			var dish: String = sim.nutrition.choose(a, c[2])
			var hold: int = sim.inv.hold_out(c[2], dish, 1, -int(a["id"])) if dish != "" else -1
			if hold == -1:
				abort_plan(a, "meal_taken")
				return false
			a["plan"][1]["hold"] = hold
			a["plan"][1]["dish"] = dish
			return true
	return false

func _wants_sleep(a: Dictionary) -> bool:
	if float(a["fatigue"]) >= float(sim.bal["need_trigger"]):
		return true
	return sim.util.is_night() and float(a["fatigue"]) >= float(sim.bal["night_sleep_trigger"])

func beds_used(bid: int) -> int:
	var n := 0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and int(x["bed"]) == bid:
			n += 1
	return n

func _assign_bed(a: Dictionary) -> int:
	var blds: Dictionary = sim.state["buildings"]
	var cur: int = int(a["bed"])
	var cur_ok: bool = blds.has(cur) and blds[cur]["state"] == "active" and not bool(blds[cur]["demolish"]) and sim.util.building_supplied(cur)
	if cur_ok and blds[cur]["def"] != "lander":
		return cur
	var best := -1
	var best_d := 1e18
	for bid in sim.topo.atmo_comp:
		var b: Dictionary = blds[bid]
		var beds: int = int(sim.bd(b).get("beds", 0))
		if beds <= 0 or b["state"] != "active" or bool(b["demolish"]) or b["def"] == "lander":
			continue
		if not sim.util.building_supplied(bid) or beds_used(bid) >= beds:
			continue
		var d: float = (b["pos"] as Vector2).distance_to(a["pos"])
		if d < best_d:
			best_d = d
			best = bid
	if best != -1:
		a["bed"] = best
		return best
	if cur_ok:
		return cur
	var lid: int = int(sim.state["lander_id"])
	if blds.has(lid) and sim.util.building_supplied(lid) and beds_used(lid) < int(sim.bdef("lander")["beds"]):
		a["bed"] = lid
		return lid
	a["bed"] = -1
	return -1

func _try_sleep(a: Dictionary) -> bool:
	var bed: int = _assign_bed(a)
	if bed == -1:
		return false
	var slot: int = int(a["id"])
	return _start_personal(a, "sleep", bed, [{"op": "sleep"}], "Going to bed", slot)

func _try_heal(a: Dictionary) -> bool:
	var blds: Dictionary = sim.state["buildings"]
	for bid in sim.topo.atmo_comp:
		var b: Dictionary = blds[bid]
		var places: int = int(sim.bd(b).get("treatment_beds", 0))
		if places <= 0 or b["state"] != "active" or not bool(b["powered"]) or not sim.util.building_supplied(bid):
			continue
		if _count_doing(bid, "heal") >= places:
			continue
		if _start_personal(a, "heal", bid, [{"op": "heal"}], "Going to the medical room", -1):
			return true
	return false

func _wants_rec(a: Dictionary) -> bool:
	var gap: float = float(int(sim.state["tick"]) - int(a["last_rec"])) / (hz() * float(sim.bal["day_length"]))
	return gap > float(sim.bal["recreation_interval_days"]) * 0.8

## Recreation: a cantina (morale bonus) is preferred to a lounge, then the nearer place.
func _try_rec(a: Dictionary) -> bool:
	var blds: Dictionary = sim.state["buildings"]
	var cands: Array = []
	for bid in sim.topo.atmo_comp:
		var b: Dictionary = blds[bid]
		var d: Dictionary = sim.bd(b)
		var places: int = int(d.get("recreation", 0))
		if places <= 0 or b["state"] != "active" or bool(b["demolish"]) or not sim.util.building_supplied(bid):
			continue
		if _count_doing(bid, "rec") >= places:
			continue
		var bonus: float = float(d.get("morale_bonus", 0.0))
		cands.append([(b["pos"] as Vector2).distance_to(a["pos"]) - bonus * 10.0, bid])
	cands.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	for c in cands:
		var goal: String = "Going to the %s" % String(sim.bdef(blds[c[1]]["def"])["name"]).to_lower()
		if _start_personal(a, "rec", c[1], [{"op": "rec"}], goal, -1):
			return true
	return false

func _count_doing(bid: int, kind: String) -> int:
	var n := 0
	for aid in sim.state["agents"]:
		var x: Dictionary = sim.state["agents"][aid]
		if x["state"] == "alive" and x["plan_kind"] == kind:
			for st in x["plan"]:
				if st["op"] == "go" and int(st["to"]["b"]) == bid:
					n += 1
	return n

func _idle(a: Dictionary) -> void:
	if not breathable(a):
		if not bool(a["rescue"]):
			_start_safety(a)
		return
	a["goal"] = "Idle"
	_start_plan(a, "idle", [{"op": "wait", "t": 3.0}], "Idle")

# ---------------------------------------------------------------- work
func _try_work(a: Dictionary) -> bool:
	var tick: int = int(sim.state["tick"])
	var tasks: Dictionary = sim.state["tasks"]
	var backoff: Dictionary = a["backoff"]
	for k in backoff.keys():
		if int(backoff[k]) <= tick:
			backoff.erase(k)
	var cands: Array = []
	for tid in tasks:
		var t: Dictionary = tasks[tid]
		if int(t["owner"]) != -1 or t["state"] != "open" or int(t["retry"]) > tick or backoff.has(tid):
			continue
		if t["role"] != "" and t["role"] != a["role"]:
			continue
		var s: float = sim.jobs.score(t, a)
		if s > -1e8:
			cands.append([s, tid])
	cands.sort_custom(func(x, y): return x[0] > y[0] if x[0] != y[0] else x[1] < y[1])
	var tries := 0
	for c in cands:
		if tries >= 4:
			break
		# A failed route below can cancel a whole group of tasks, so check each one again.
		if not tasks.has(c[1]):
			continue
		tries += 1
		var t: Dictionary = tasks[c[1]]
		var plan: Dictionary = _plan_for_task(a, t)
		if plan["ok"]:
			sim.jobs.claim(t, a)
			t["state"] = "traveling"
			_start_plan(a, "task", plan["steps"], plan["goal"])
			return true
		backoff[c[1]] = tick + int(float(sim.bal["task_backoff_seconds"]) * hz())
		if plan["reason"] == "no_path_src":
			# The goods cannot be reached: that says nothing about the place they go to.
			# The source rests for a minute and the task is made again from another one.
			sim.jobs.source_unreachable(t)
		elif plan["reason"] == "no_path":
			# Only a colonist inside the base proves that a place cannot be reached; one who
			# stands outside may only be cut off where they stand.
			if a["where"] != "out":
				sim.jobs.path_failed(t)
		elif tasks.has(c[1]):
			t["reason"] = plan["reason"]
			# Out of suit range or without air is the same for everybody for a while: the
			# task rests, so that the colony's other work is not starved by it.
			if plan["reason"] == "suit_range" or plan["reason"] == "no_air":
				t["retry"] = tick + int(TASK_REST_SECONDS * hz())
	return false

func _inv_loc(inv_id: int, from: Vector2) -> Dictionary:
	var inv: Dictionary = sim.inv.get_inv(inv_id)
	if inv.is_empty():
		return {}
	var blds: Dictionary = sim.state["buildings"]
	if inv["ot"] == "b":
		var b: Dictionary = blds.get(inv["oid"], {})
		if b.is_empty():
			return {}
		var outside_bay: bool = bool(sim.bdef(b["def"]).get("cargo_outside", false))
		if (b["kind"] == "room" or b["kind"] == "special") and sim.topo.atmo_comp.has(b["id"]) and inv["role"] != "site" and not outside_bay:
			return {"b": b["id"], "p": sim.nav.slot_pos(b, inv_id)}
		var p = sim.nav.best_access(b, from)
		if p == null:
			return {}
		return {"b": -1, "p": p}
	if inv["ot"] == "g":
		if int(inv["oid"]) > 0 and sim.topo.atmo_comp.has(int(inv["oid"])):
			return {"b": int(inv["oid"]), "p": inv["pos"]}
		return {"b": -1, "p": inv["pos"]}
	return {}

func _plan_for_task(a: Dictionary, t: Dictionary) -> Dictionary:
	var blds: Dictionary = sim.state["buildings"]
	var rev: int = int(sim.state["rev"]["walk"])
	var names: Dictionary = sim.bal["resource_names"]
	match t["kind"]:
		"haul":
			var src: Dictionary = _inv_loc(t["src"], a["pos"])
			if src.is_empty():
				return {"ok": false, "reason": "no_path_src"}
			var dst: Dictionary = _inv_loc(t["dst"], src["p"])
			if dst.is_empty():
				return {"ok": false, "reason": "no_path"}
			var r1: Dictionary = sim.nav.plan(loc_of(a), src)
			if not r1["ok"]:
				return {"ok": false, "reason": "no_path_src" if a["where"] != "out" else "no_path_here"}
			var r2: Dictionary = sim.nav.plan(src, dst)
			if not r2["ok"]:
				return {"ok": false, "reason": "no_path"}
			var legs: Array = (r1["legs"] as Array) + (r2["legs"] as Array)
			if not _air_ok(a, legs, 0.0, dst["b"], dst["p"]):
				return {"ok": false, "reason": "suit_range"}
			return {"ok": true, "goal": "Carrying %s" % sim.items.name_of(String(t["res"])).to_lower(), "steps": [
				{"op": "go", "to": src, "route": r1, "rev": rev}, {"op": "pickup"},
				{"op": "go", "to": dst, "route": r2, "rev": rev}, {"op": "deliver"}]}
		"build", "demolish":
			var b: Dictionary = blds[t["bld"]]
			var p = sim.nav.best_access(b, a["pos"])
			if p == null:
				return {"ok": false, "reason": "no_path"}
			var to := {"b": -1, "p": p}
			var r: Dictionary = sim.nav.plan(loc_of(a), to)
			if not r["ok"]:
				return {"ok": false, "reason": "no_path"}
			if not _air_ok(a, r["legs"], float(sim.bal["exterior_work_chunk_seconds"]), -1, p):
				return {"ok": false, "reason": "suit_range"}
			var verb: String = "Building" if t["kind"] == "build" else "Removing"
			return {"ok": true, "goal": "%s %s" % [verb, b["name"]], "steps": [
				{"op": "go", "to": to, "route": r, "rev": rev}, {"op": "work", "kind": t["kind"], "b": b["id"]}]}
		"operate", "tend", "research":
			var b: Dictionary = blds[t["bld"]]
			if not sim.util.building_supplied(b["id"]):
				return {"ok": false, "reason": "no_air"}
			var to := {"b": b["id"], "p": sim.nav.slot_pos(b, int(t["id"]))}
			if t["kind"] == "tend":
				var offs: Array = sim.bd(b).get("tray_offsets", [])
				if int(t["tray"]) < offs.size():
					var o := Vector2(offs[t["tray"]][0], offs[t["tray"]][1]).rotated(b["rot"])
					to["p"] = (b["pos"] as Vector2) + o + Vector2(0, 1.1).rotated(b["rot"])
			var r: Dictionary = sim.nav.plan(loc_of(a), to)
			if not r["ok"]:
				return {"ok": false, "reason": "no_path"}
			if not _air_ok(a, r["legs"], 0.0, b["id"], to["p"]):
				return {"ok": false, "reason": "suit_range"}
			var goal: String = "Working at %s" % b["name"]
			if t["kind"] == "tend":
				goal = ("Seeding" if t["op"] == "seed" else "Harvesting") + " at " + String(b["name"])
			elif t["kind"] == "research":
				goal = "Researching at %s" % b["name"]
			return {"ok": true, "goal": goal, "steps": [
				{"op": "go", "to": to, "route": r, "rev": rev}, {"op": "work", "kind": t["kind"], "b": b["id"]}]}
		"upgrade":
			# Rooms are upgraded from inside, exterior structures from outside (suit air).
			var b: Dictionary = blds[t["bld"]]
			var inside: bool = b["kind"] == "room" and sim.topo.atmo_comp.has(b["id"])
			var to := {}
			if inside:
				if not sim.util.building_supplied(b["id"]):
					return {"ok": false, "reason": "no_air"}
				to = {"b": b["id"], "p": sim.nav.slot_pos(b, int(t["id"]))}
			else:
				var p = sim.nav.best_access(b, a["pos"])
				if p == null:
					return {"ok": false, "reason": "no_path"}
				to = {"b": -1, "p": p}
			var r: Dictionary = sim.nav.plan(loc_of(a), to)
			if not r["ok"]:
				return {"ok": false, "reason": "no_path"}
			if not _air_ok(a, r["legs"], 0.0 if inside else float(sim.bal["exterior_work_chunk_seconds"]), int(to["b"]), to["p"]):
				return {"ok": false, "reason": "suit_range"}
			return {"ok": true, "goal": "Upgrading %s" % b["name"], "steps": [
				{"op": "go", "to": to, "route": r, "rev": rev}, {"op": "work", "kind": "upgrade", "b": b["id"]}]}
		"shipwork":
			var b: Dictionary = blds[t["bld"]]
			var p = sim.nav.best_access(b, a["pos"])
			if p == null:
				return {"ok": false, "reason": "no_path"}
			var to := {"b": -1, "p": p}
			var r: Dictionary = sim.nav.plan(loc_of(a), to)
			if not r["ok"]:
				return {"ok": false, "reason": "no_path"}
			if not _air_ok(a, r["legs"], float(sim.bal["exterior_work_chunk_seconds"]), -1, p):
				return {"ok": false, "reason": "suit_range"}
			var verb: String = "Surveying" if int(sim.state["ship"]["stage"]) == 0 else ("Servicing" if int(sim.state["ship"]["stage"]) >= 5 else "Repairing")
			return {"ok": true, "goal": "%s the Meridian" % verb, "steps": [
				{"op": "go", "to": to, "route": r, "rev": rev}, {"op": "work", "kind": "shipwork", "b": b["id"]}]}
		"repair":
			var b: Dictionary = blds[t["bld"]]
			var src: Dictionary = _inv_loc(t["src"], a["pos"])
			if src.is_empty():
				return {"ok": false, "reason": "no_path_src"}
			var to := {}
			if sim.topo.atmo_comp.has(b["id"]):
				to = {"b": b["id"], "p": sim.nav.slot_pos(b, int(t["id"]))}
			else:
				var p = sim.nav.best_access(b, src["p"])
				if p == null:
					return {"ok": false, "reason": "no_path"}
				to = {"b": -1, "p": p}
			var r1: Dictionary = sim.nav.plan(loc_of(a), src)
			if not r1["ok"]:
				return {"ok": false, "reason": "no_path_src" if a["where"] != "out" else "no_path_here"}
			var r2: Dictionary = sim.nav.plan(src, to)
			if not r2["ok"]:
				return {"ok": false, "reason": "no_path"}
			var work: float = float(sim.bal["exterior_work_chunk_seconds"]) if int(to["b"]) == -1 else 0.0
			if not _air_ok(a, (r1["legs"] as Array) + (r2["legs"] as Array), work, to["b"], to["p"]):
				return {"ok": false, "reason": "suit_range"}
			return {"ok": true, "goal": "Repairing %s" % b["name"], "steps": [
				{"op": "go", "to": src, "route": r1, "rev": rev}, {"op": "pickup"},
				{"op": "go", "to": to, "route": r2, "rev": rev}, {"op": "work", "kind": "repair", "b": b["id"]}]}
	return {"ok": false, "reason": "unknown"}

## Suit-air check for a whole plan (spec 8). Walks the legs and counts exposed seconds
## in each stretch between refills. A stretch may use at most 70% of the air it starts
## with, INCLUDING the walk back to a supplied airlock from where the plan ends.
func _air_ok(a: Dictionary, legs: Array, exposed_work: float, end_b: int, end_p: Vector2) -> bool:
	var bal: Dictionary = sim.bal
	var cap: float = float(bal["suit_air_seconds"])
	var frac: float = float(bal["suit_task_fraction"])
	var start_air: float = float(a["suit"])
	var used := 0.0
	for leg in legs:
		match leg["m"]:
			"out":
				used += float(leg["len"]) / sim.util.out_speed()
			"in":
				if not sim.util.building_supplied(leg["b"]):
					used += float(leg["len"]) / float(bal["speed_indoor"])
			"lock":
				if sim.util.building_supplied(leg["b"]):
					if used > frac * start_air:
						return false
					start_air = cap
					used = 0.0
				else:
					used += float(bal["airlock_cycle_seconds"])
	var end_exposed: bool = end_b == -1 or not sim.util.building_supplied(end_b)
	if end_exposed:
		used += exposed_work
		if end_b == -1:
			var back: Dictionary = sim.nav.nearest_supplied_lock(end_p)
			if not back["ok"]:
				return false
			used += float(back["seconds"])
		else:
			var lid: int = _nearest_supplied_room(end_p, -1)
			if lid == -1:
				return false
			used += (sim.state["buildings"][lid]["pos"] as Vector2).distance_to(end_p) * 1.3 / sim.util.out_speed() + float(bal["airlock_cycle_seconds"])
	return used <= frac * start_air

# ---------------------------------------------------------------- plan control
func _start_plan(a: Dictionary, kind: String, steps: Array, goal: String) -> void:
	a["plan"] = steps
	a["pi"] = 0
	a["plan_kind"] = kind
	a["goal"] = goal
	a["route"] = {}
	a["li"] = 0
	a["wi"] = 0
	a["act_t"] = -1.0
	a["work_wait"] = 0.0
	a["sleeping"] = false

func _step_op(a: Dictionary) -> String:
	var plan: Array = a["plan"]
	if plan.is_empty() or int(a["pi"]) >= plan.size():
		return ""
	return plan[a["pi"]]["op"]

func abort_plan(a: Dictionary, reason: String) -> void:
	_leave_queues(a)
	sim.inv.release_owner(-int(a["id"]))
	var tid: int = int(a["task"])
	a["task"] = -1
	if tid != -1 and sim.state["tasks"].has(tid):
		var t: Dictionary = sim.state["tasks"][tid]
		if bool(t["picked"]):
			_drop_cargo(a)
			sim.jobs.fail(tid, reason)
		else:
			sim.jobs.release(tid, reason, 2.0)
	_clear_plan(a)

func _clear_plan(a: Dictionary) -> void:
	a["plan"] = []
	a["pi"] = 0
	a["plan_kind"] = ""
	a["route"] = {}
	a["li"] = 0
	a["wi"] = 0
	a["act_t"] = -1.0
	a["sleeping"] = false
	a["goal"] = "Idle"

func on_task_lost(a: Dictionary, tid: int, _reason: String) -> void:
	if int(a["task"]) != tid:
		return
	a["task"] = -1
	_leave_queues(a)
	_drop_cargo(a)
	_clear_plan(a)

func _finish_task(a: Dictionary) -> void:
	var tid: int = int(a["task"])
	a["task"] = -1
	sim.jobs.complete(tid)
	_clear_plan(a)

func _drop_cargo(a: Dictionary) -> void:
	if sim.inv.total(a["inv"]) <= 0:
		return
	var oid: int = 0 if a["where"] == "out" else int(a["bld"])
	var pos: Vector2 = a["pos"]
	if a["where"] == "out":
		var q = sim.nav.nearest_walkable(pos, 6)
		if q != null:
			pos = q
	var pile: int = sim.inv.create_inv("g", oid, "pile", 100000, pos)
	var inv: Dictionary = sim.inv.get_inv(a["inv"])
	for res in inv["items"].keys():
		sim.inv.move(a["inv"], pile, res, int(inv["items"][res]))
	sim.log_event("dropped", "%s put cargo down at a safe place." % a["name"], [a["id"]], 0)

# ---------------------------------------------------------------- acting (every tick)
func act_tick() -> void:
	var dt: float = 1.0 / hz()
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["where"] == "lock":
			continue
		var plan: Array = a["plan"]
		if plan.is_empty():
			continue
		if int(a["pi"]) >= plan.size():
			if a["plan_kind"] == "task":
				_finish_task(a)
			else:
				_clear_plan(a)
			continue
		var step: Dictionary = plan[a["pi"]]
		match step["op"]:
			"go": _do_go(a, step, dt)
			"pickup": _do_pickup(a)
			"deliver": _do_deliver(a)
			"work": _do_work(a, step, dt)
			"eat": _do_eat(a, step, dt)
			"drink": _do_drink(a, step, dt)
			"sleep": _do_sleep(a)
			"rec": _do_timed(a, float(sim.bal["recreation_seconds"]), dt, "Relaxing", "rec")
			"heal": _do_heal(a)
			"wait": _do_timed(a, float(step["t"]), dt, a["goal"], "")

func _next_step(a: Dictionary) -> void:
	a["pi"] = int(a["pi"]) + 1
	a["route"] = {}
	a["li"] = 0
	a["wi"] = 0
	a["act_t"] = -1.0
	a["work_wait"] = 0.0

func _plan_failed(a: Dictionary, reason: String) -> void:
	var tid: int = int(a["task"])
	if tid != -1 and sim.state["tasks"].has(tid) and reason == "no_path":
		sim.jobs.path_failed(sim.state["tasks"][tid])
	abort_plan(a, reason)

func _do_go(a: Dictionary, step: Dictionary, dt: float) -> void:
	var rev: int = int(sim.state["rev"]["walk"])
	if (a["route"] as Dictionary).is_empty() or int(a["route"].get("rev", -1)) != rev:
		var route: Dictionary = {}
		if (a["route"] as Dictionary).is_empty() and int(step.get("rev", -1)) == rev and step.has("route"):
			route = step["route"]
		else:
			_leave_queues(a)
			route = sim.nav.plan(loc_of(a), step["to"])
			if not route["ok"]:
				_plan_failed(a, "no_path")
				return
		route["rev"] = rev
		a["route"] = route
		a["li"] = 0
		a["wi"] = 0
	var legs: Array = a["route"]["legs"]
	if int(a["li"]) >= legs.size():
		var to: Dictionary = step["to"]
		if int(to["b"]) != -1:
			a["where"] = "in"
			a["bld"] = int(to["b"])
		else:
			a["where"] = "out"
			a["bld"] = -1
		_next_step(a)
		return
	var leg: Dictionary = legs[a["li"]]
	if leg["m"] == "lock":
		_enqueue(a, leg["b"], leg["dir"])
		return
	if leg["m"] == "in":
		a["where"] = "in"
		a["bld"] = int(leg["b"])
	else:
		a["where"] = "out"
		a["bld"] = -1
	var speed: float = float(sim.bal["speed_indoor"]) if leg["m"] == "in" else float(sim.bal["speed_outdoor"]) * float(sim.state["env"].get("speed_mult", 1.0))
	var dist: float = speed * dt
	var pts: Array = leg["pts"]
	while dist > 0.0 and int(a["wi"]) < pts.size():
		var target: Vector2 = pts[a["wi"]]
		var d: float = (a["pos"] as Vector2).distance_to(target)
		if d <= dist:
			a["pos"] = target
			dist -= d
			a["wi"] = int(a["wi"]) + 1
		else:
			var dirv: Vector2 = (target - (a["pos"] as Vector2)) / d
			a["pos"] = (a["pos"] as Vector2) + dirv * dist
			a["facing"] = dirv.angle()
			dist = 0.0
	if int(a["wi"]) >= pts.size():
		a["li"] = int(a["li"]) + 1
		a["wi"] = 0

func _do_pickup(a: Dictionary) -> void:
	var t: Dictionary = sim.state["tasks"].get(a["task"], {})
	if t.is_empty() or not sim.inv.take_held(t["hold_out"], a["inv"]):
		_plan_failed(a, "pickup_failed")
		return
	t["hold_out"] = -1
	t["picked"] = true
	_next_step(a)

func _do_deliver(a: Dictionary) -> void:
	var t: Dictionary = sim.state["tasks"].get(a["task"], {})
	if t.is_empty() or not sim.inv.put_held(t["hold_in"], a["inv"]):
		_plan_failed(a, "deliver_failed")
		return
	t["hold_in"] = -1
	t["picked"] = false
	var m: Dictionary = sim.state["metrics"]
	m["delivered"] = int(m.get("delivered", 0)) + int(t["qty"])
	_finish_task(a)

func _do_work(a: Dictionary, step: Dictionary, dt: float) -> void:
	var blds: Dictionary = sim.state["buildings"]
	var t: Dictionary = sim.state["tasks"].get(a["task"], {})
	if t.is_empty() or not blds.has(step["b"]):
		abort_plan(a, "target_gone")
		return
	var b: Dictionary = blds[step["b"]]
	t["state"] = "working"
	var wp: float = productivity(a) * dt
	match step["kind"]:
		"build":
			if b["state"] != "building":
				_finish_task(a)
				return
			if a["role"] == "technician":
				wp *= float(sim.bal["technician_build_mult"])
			sim.build.add_progress(b, wp)
			if float(b["progress"]) >= float(b["work_total"]):
				_finish_task(a)
		"demolish":
			if not bool(b["demolish"]):
				_finish_task(a)
				return
			sim.build.add_progress(b, wp)
			if float(b["progress"]) >= sim.build.demolish_work_total(b):
				_finish_task(a)
		"operate":
			if not sim.prod.has_batch(b) and not sim.prod.start_batch(b):
				_finish_task(a)
				return
			if not bool(b["powered"]) and float(sim.bdef(b["def"]).get("power", 0.0)) > 0.0:
				a["work_wait"] = float(a["work_wait"]) + dt
				if float(a["work_wait"]) > 8.0:
					abort_plan(a, "no_power")
				return
			a["work_wait"] = 0.0
			if sim.prod.work_batch(b, wp) and sim.prod.machine_block(b) != "":
				_finish_task(a)
		"tend":
			var tray: Dictionary = b["trays"][t["tray"]]
			var want: String = "empty" if t["op"] == "seed" else "ready"
			if tray["state"] != want:
				_finish_task(a)
				return
			tray["work"] = float(tray["work"]) + wp
			if t["op"] == "seed" and float(tray["work"]) >= float(sim.bal["crop_seed_work"]):
				sim.prod.finish_seed(b, t["tray"])
				_finish_task(a)
			elif t["op"] == "harvest" and float(tray["work"]) >= float(sim.bal["crop_harvest_work"]):
				if sim.prod.finish_harvest(b, t["tray"]):
					_finish_task(a)
				else:
					b["block"] = "output_blocked"
					abort_plan(a, "output_blocked")
		"repair":
			a["act_t"] = (0.0 if float(a["act_t"]) < 0.0 else float(a["act_t"])) + wp * (float(sim.bal["technician_build_mult"]) if a["role"] == "technician" else 1.0)
			if float(a["act_t"]) >= float(sim.bal["repair_work"]):
				if sim.inv.consume(a["inv"], "spare_parts", 1, "repair"):
					sim.stat_add("consumed", "spare_parts", 1)
					sim.prod.repair(b)
				t["picked"] = false
				_finish_task(a)
		"research":
			# One session of work, then the scientist is free to eat, sleep or change task.
			if not sim.research.workable() or not bool(b["powered"]) or not bool(b["enabled"]):
				_finish_task(a)
				return
			sim.research.add_work(b, wp)
			a["act_t"] = (0.0 if float(a["act_t"]) < 0.0 else float(a["act_t"])) + wp
			if float(a["act_t"]) >= RESEARCH_SESSION:
				_finish_task(a)
		"upgrade":
			var u: Dictionary = b.get("upgrade", {})
			if u.is_empty() or u["state"] != "work":
				_finish_task(a)
				return
			if a["role"] == "technician":
				wp *= float(sim.bal["technician_build_mult"])
			sim.upgrades.add_work(b, wp)
			if float(u["progress"]) >= float(u["work_total"]):
				_finish_task(a)
		"shipwork":
			var kind: String = sim.ship.work_kind()
			if kind == "":
				_finish_task(a)
				return
			if a["role"] == "technician":
				wp *= float(sim.bal["technician_build_mult"])
			var before: int = int(sim.state["stats"].get("ship_maintenance", 0))
			var stage: int = int(sim.state["ship"]["stage"])
			sim.ship.add_work(wp)
			if sim.ship.work_kind() != kind or int(sim.state["ship"]["stage"]) != stage or int(sim.state["stats"].get("ship_maintenance", 0)) != before:
				_finish_task(a)

func _do_eat(a: Dictionary, step: Dictionary, dt: float) -> void:
	if float(a["act_t"]) < 0.0:
		var hid: int = int(step["hold"])
		var dish: String = String(step.get("dish", ""))
		if dish == "" and sim.state["holds"].has(hid):
			dish = String(sim.state["holds"][hid]["res"])
		if not sim.inv.consume_held(hid, "eaten"):
			abort_plan(a, "no_meal")
			return
		step["dish"] = dish
		a["act_t"] = float(sim.bal["eat_seconds"])
		a["goal"] = "Eating %s" % sim.items.name_of(dish).to_lower()
		var m: Dictionary = sim.state["metrics"]
		m["meals_eaten"] = int(m.get("meals_eaten", 0)) + 1
		sim.stat_add("eaten", dish, 1)
		sim.stat_add("consumed", dish, 1)
	a["act_t"] = float(a["act_t"]) - dt
	if float(a["act_t"]) <= 0.0:
		a["hunger"] = maxf(0.0, float(a["hunger"]) - float(sim.bal["meal_hunger"]))
		if a.has("nutrition"):
			sim.nutrition.eat(a, String(step.get("dish", "meals")))
		var b: Dictionary = sim.state["buildings"].get(a["bld"], {})
		if not b.is_empty() and bool(sim.bdef(b["def"]).get("dining", false)):
			a["last_dining"] = int(sim.state["tick"])
		_clear_plan(a)

func _do_drink(a: Dictionary, step: Dictionary, dt: float) -> void:
	if float(a["act_t"]) < 0.0:
		var ok := false
		if int(step["hold"]) != -1:
			ok = sim.inv.consume_held(int(step["hold"]), "drunk")
		else:
			ok = sim.util.draw_water(a["bld"], int(sim.bal["drink_units"]) * sim.util.fp(), 0)
		if not ok:
			abort_plan(a, "no_water")
			return
		a["act_t"] = float(sim.bal["drink_seconds"])
		a["goal"] = "Drinking"
		var m: Dictionary = sim.state["metrics"]
		m["water_drunk"] = int(m.get("water_drunk", 0)) + int(sim.bal["drink_units"])
	a["act_t"] = float(a["act_t"]) - dt
	if float(a["act_t"]) <= 0.0:
		a["thirst"] = maxf(0.0, float(a["thirst"]) - float(sim.bal["drink_thirst"]))
		_clear_plan(a)

func _do_sleep(a: Dictionary) -> void:
	a["sleeping"] = true
	a["goal"] = "Sleeping"
	var done: bool = float(a["fatigue"]) <= 0.5
	if not sim.util.is_night() and float(a["fatigue"]) < 15.0:
		done = true
	if done:
		_clear_plan(a)

func _do_heal(a: Dictionary) -> void:
	var b: Dictionary = sim.state["buildings"].get(a["bld"], {})
	if float(a["act_t"]) < 0.0:
		# The first moment of treatment: one unit of medicine doubles the healing.
		a["act_t"] = 0.0
		a["medicated"] = not b.is_empty() and sim.prod.use_medicine(b)
		if bool(a["medicated"]):
			sim.stat_add("consumed", "medicine", 1)
	a["goal"] = "Treated in the medical bay" + (" (medicine)" if bool(a.get("medicated", false)) else "")
	if float(a["health"]) >= 90.0 or b.is_empty() or not bool(b["powered"]):
		if float(a["health"]) >= 90.0:
			sim.stat_add("heals", "", 1)
		a["medicated"] = false
		_clear_plan(a)

## Medical healing speed: the bay's level ("healing") and medicine (x2).
func _heal_mult(a: Dictionary) -> float:
	var m := 1.0
	var b: Dictionary = sim.state["buildings"].get(a["bld"], {})
	if not b.is_empty() and String(sim.bdef(b["def"]).get("level_stat", "")) == "healing":
		m = float(sim.bd(b).get("level_mult", 1.0))
	if bool(a.get("medicated", false)):
		m *= 2.0
	return m

func _do_timed(a: Dictionary, seconds: float, dt: float, goal: String, mark: String) -> void:
	if float(a["act_t"]) < 0.0:
		a["act_t"] = seconds
		a["goal"] = goal
	a["act_t"] = float(a["act_t"]) - dt
	if float(a["act_t"]) <= 0.0:
		if mark == "rec":
			a["last_rec"] = int(sim.state["tick"])
			# A cantina gives a morale bonus until the next recreation.
			var b: Dictionary = sim.state["buildings"].get(a["bld"], {})
			a["rec_bonus"] = float(sim.bd(b).get("morale_bonus", 0.0)) if not b.is_empty() else 0.0
		_clear_plan(a)

# ---------------------------------------------------------------- morale (each second)
func morale_second() -> void:
	var bal: Dictionary = sim.bal
	var tick: int = int(sim.state["tick"])
	var day_ticks: float = float(bal["day_length"]) * hz()
	var beds := 0
	var blds: Dictionary = sim.state["buildings"]
	for bid in blds:
		if blds[bid]["state"] == "active" and blds[bid]["kind"] != "link":
			beds += int(sim.bd(blds[bid]).get("beds", 0))
	var pop: int = sim.alive_count()
	var pr: Dictionary = sim.state["progress"]
	var recent_death: bool = int(pr["last_death_tick"]) >= 0 and float(tick - int(pr["last_death_tick"])) < float(bal["morale_death_memory_days"]) * day_ticks
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var target: float = float(bal["morale_base"])
		if float(tick - int(a["last_dining"])) < day_ticks:
			target += float(bal["morale_dining_bonus"])
		if float(tick - int(a["last_rec"])) < day_ticks * float(bal["recreation_interval_days"]):
			target += float(bal["morale_recreation_bonus"])
		elif float(tick - int(a["born"])) > day_ticks:
			target -= float(bal["morale_no_recreation_penalty"])
		if beds < pop:
			target -= float(bal["morale_crowding_penalty"])
		if float(a["fatigue"]) >= float(bal["need_critical"]):
			target -= float(bal["morale_tired_penalty"])
		if float(a["hunger"]) >= float(bal["need_critical"]) or float(a["thirst"]) >= float(bal["need_critical"]):
			target -= float(bal["morale_hungry_penalty"])
		if recent_death:
			target -= float(bal["morale_death_penalty"])
		if a.has("nutrition"):
			sim.nutrition.decay_second(a)
			a["starved"] = sim.nutrition.starved(a)
			target += sim.nutrition.morale_delta(a)
		if float(a.get("rec_bonus", 0.0)) > 0.0 and float(tick - int(a["last_rec"])) < day_ticks * float(bal["recreation_interval_days"]):
			target += float(a["rec_bonus"])
		var bed: Dictionary = blds.get(int(a["bed"]), {})
		if not bed.is_empty() and bed["state"] == "active":
			target += float(sim.bd(bed).get("comfort", 0.0))
		target = clampf(target, 0.0, 100.0)
		var step: float = float(bal["morale_rate_per_day"]) / float(bal["day_length"])
		a["morale"] = move_toward(float(a["morale"]), target, step)
