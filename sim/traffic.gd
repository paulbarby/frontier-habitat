extends RefCounted
## Ships and visitors (docs/V3_1_DESIGN.md section 6.1).
##
## Schedule. Arrivals are planned at least forecast_days (1) ahead, once a powered landing
## pad exists, never before first_day (4). Every number of an arrival (time, kind, stay,
## offer, prices) is a hash of the seed and the arrival number, so the schedule does not
## depend on any random stream: building, trading or answering never moves a ship.
## A player answer (traffic_answer) changes what a ship does, never whether or when it comes.
##
## Life of a ship: scheduled (planned, not shown) -> forecast (shown, one day ahead) ->
## orbit (holding: no free powered pad, or a storm, meteor shower or quake is active; at most
## orbit_hold_h, then it leaves) -> landing (descent_s) -> landed (stay_h) -> boarding (its
## visitors walk back; at most boarding_wait_h) -> takeoff (takeoff_s) -> gone. A denied
## ship ends at "denied" when it would arrive; one that could not land ends at "left".
##
## Visitors are agents with kind "visitor", role "visitor", vkind (trader, tourist ...), ship
## (arrival id, -1 when left behind). They walk, use airlocks, rooms, furniture, eat paid
## meals and sleep in free beds, but never take jobs. A visitor not back at the pad when the
## ship leaves stays in the colony and boards the next ship of the same kind (its ship = -1
## until then). Immigrants from a shuttle are colonists at once.
##
## Credits (state.credits = {balance, earned, spent, by{reason: n}}) are outside the item
## ledger; credits_audit() checks balance = earned - spent >= 0.
## Trade moves real units: bought units land as a pile at the pad (carriers take them to
## storage); sold units are carried to the ship's hold and paid as they arrive.
##
## state.traffic = {n (arrivals planned), next_at (tick of the next arrival, -1 = not
## started), queue [arrival], ships [arrival], done [arrival (last 20)], stranded_n}

const Rng = preload("res://sim/rng.gd")
const Text = preload("res://sim/text.gd")

var sim

const SHIP_PHASES := ["orbit", "landing", "landed", "boarding", "takeoff"]

func _init(s) -> void:
	sim = s

static func fresh_state() -> Dictionary:
	return {"n": 0, "next_at": -1, "queue": [], "ships": [], "done": []}

static func fresh_credits(start: int) -> Dictionary:
	return {"balance": start, "earned": start, "spent": 0, "by": {"start": start}}

func ts() -> Dictionary:
	if not sim.state.has("traffic"):
		sim.state["traffic"] = fresh_state()
	return sim.state["traffic"]

func cfg() -> Dictionary:
	return sim.content["ships"]

func kinds() -> Dictionary:
	return cfg()["kinds"]

func tcfg() -> Dictionary:
	return sim.content["trade"]

func hz() -> int:
	return int(sim.bal["tick_hz"])

func day_ticks() -> int:
	return int(sim.bal["day_length"]) * hz()

func hour_ticks() -> int:
	return int(float(cfg().get("hour_seconds", 25)) * hz())

## A number 0..1 from the seed, the arrival number and a key (no random stream).
func _h(n: int, k: int) -> float:
	return Rng.hash2(n, k, int(sim.state["seed"]) ^ 0x7AF1C)

func _hi(n: int, k: int, lo: int, hi: int) -> int:
	return lo + mini(hi - lo, int(_h(n, k) * float(hi - lo + 1)))

# ---------------------------------------------------------------- credits
func credits() -> int:
	return int(sim.state.get("credits", {}).get("balance", 0))

func earn(n: int, reason: String) -> void:
	if n <= 0:
		return
	var c: Dictionary = sim.state["credits"]
	c["balance"] = int(c["balance"]) + n
	c["earned"] = int(c["earned"]) + n
	c["by"][reason] = int(c["by"].get(reason, 0)) + n

func spend(n: int, reason: String) -> bool:
	var c: Dictionary = sim.state["credits"]
	if n < 0 or n > int(c["balance"]):
		return false
	c["balance"] = int(c["balance"]) - n
	c["spent"] = int(c["spent"]) + n
	c["by"][reason] = int(c["by"].get(reason, 0)) - n
	return true

## {} when the credits balance, else what is wrong.
func credits_audit() -> Dictionary:
	var c: Dictionary = sim.state.get("credits", {})
	if c.is_empty():
		return {"error": "no credits record"}
	var sum := 0
	for k in c["by"]:
		sum += int(c["by"][k])
	if int(c["balance"]) != int(c["earned"]) - int(c["spent"]) or int(c["balance"]) < 0 or sum != int(c["balance"]):
		return {"balance": c["balance"], "earned": c["earned"], "spent": c["spent"], "by_sum": sum}
	return {}

# ---------------------------------------------------------------- pads
## Landing pad ids, found again only when a pad was added or a structure removed (the
## pad counter or the number of structures changed) or another game was loaded. Before,
## every second scanned every structure (V3.1 tick budget).
var _pad_ids: Array = []
var _pad_key := ""
var _pad_state = null

func _pad_list() -> Array:
	var blds: Dictionary = sim.state["buildings"]
	var key: String = "%d:%d" % [int(sim.state["counters"].get("landing_pad", 0)), blds.size()]
	if key != _pad_key or not is_same(_pad_state, sim.state):
		_pad_key = key
		_pad_state = sim.state
		_pad_ids = []
		for id in blds:
			if blds[id]["def"] == "landing_pad":
				_pad_ids.append(int(id))
	return _pad_ids

func _pads(powered_only: bool) -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in _pad_list():
		var b: Dictionary = blds.get(id, {})
		if b.is_empty():
			continue
		if b["def"] == "landing_pad" and b["state"] == "active" and not bool(b["demolish"]):
			if powered_only and not bool(b["powered"]):
				continue
			out.append(int(id))
	return out

func _free_pad() -> int:
	var blds: Dictionary = sim.state["buildings"]
	for id in _pads(true):
		if int(blds[id].get("ship", -1)) == -1:
			return id
	return -1

# ---------------------------------------------------------------- schedule
func tick_second() -> void:
	var tick: int = int(sim.state["tick"])
	var t: Dictionary = ts()
	if tick % (60 * hz()) == 0 or int(t["next_at"]) < 0:
		_plan(tick)
	_queue_second(tick)
	_ships_second(tick)
	_pay_deliveries()

func _plan(tick: int) -> void:
	var t: Dictionary = ts()
	if int(t["next_at"]) < 0:
		if _pads(true).is_empty():
			return
		var first: int = int(float(cfg().get("first_day", 4)) * float(day_ticks()))
		var at: int = maxi(first, tick + int(float(cfg().get("forecast_days", 1.0)) * float(day_ticks())))
		t["next_at"] = at - at % hz()
	var horizon: int = tick + int(float(cfg().get("forecast_days", 1.0)) * 1.2 * float(day_ticks()))
	var guard := 0
	while int(t["next_at"]) <= horizon and guard < 10:
		guard += 1
		var n: int = int(t["n"])
		t["n"] = n + 1
		(t["queue"] as Array).append(_make_arrival(n, int(t["next_at"]), ""))
		var g: Array = cfg().get("gap_days", [0.6, 1.4])
		var gap: int = int(lerpf(float(g[0]), float(g[1]), _h(n, 1)) * float(day_ticks()))
		t["next_at"] = int(t["next_at"]) + gap - gap % hz()

func _pick_kind(n: int) -> String:
	var keys: Array = kinds().keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += float(kinds()[k].get("weight", 1))
	var u: float = _h(n, 2) * total
	for k in keys:
		u -= float(kinds()[k].get("weight", 1))
		if u < 0.0:
			return k
	return keys[keys.size() - 1]

func _price(n: int, item: String, sell: bool) -> int:
	var base: float = float(tcfg()["items"].get(item, 1))
	var sp: float = float(tcfg().get("spread", 0.25))
	var m: float = 1.0 + (Rng.hash2(n, item.hash() & 0xFFFF, int(sim.state["seed"]) ^ 0x5A1E) * 2.0 - 1.0) * sp
	if sell:
		return maxi(1, int(ceil(base * m)))
	return maxi(1, int(floor(base * m * float(tcfg().get("buy_mult", 0.8)))))

## m distinct items of a list, in a hash order of this arrival.
func _choose(n: int, list: Array, m: int, salt: int) -> Array:
	var keyed: Array = []
	for i in list.size():
		keyed.append([Rng.hash2(n, salt + i, int(sim.state["seed"]) ^ 0x3C3C), list[i]])
	keyed.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else str(x[1]) < str(y[1]))
	var out: Array = []
	for i in mini(m, keyed.size()):
		out.append(keyed[i][1])
	out.sort()
	return out

func _make_arrival(n: int, at: int, kind: String) -> Dictionary:
	if kind == "":
		kind = _pick_kind(n)
	var k: Dictionary = kinds()[kind]
	var vr: Array = k.get("visitors", [0, 0])
	var arr := {"id": n + 1, "n": n, "kind": kind, "at": at, "stay_s": int(float(k.get("stay_h", 6)) * float(cfg().get("hour_seconds", 25))),
		"phase": "scheduled", "answer": "grant", "accept": -1, "pad": -1, "t": at, "visitors": [],
		"people": _hi(n, 3, int(vr[0]), int(vr[1])), "offer": {}, "stock_inv": -1, "buy_inv": -1, "orders": {}, "result": {}}
	var offer := {}
	var su: Array = tcfg().get("stock_units", [4, 16])
	var wu: Array = tcfg().get("want_units", [4, 16])
	match kind:
		"trader":
			var st: Array = k.get("stock_types", [6, 10])
			var wt: Array = k.get("want_types", [4, 6])
			var sells := {}
			for i in _choose(n, tcfg()["sells"], _hi(n, 4, int(st[0]), int(st[1])), 100):
				sells[i] = {"units": _hi(n, 200 + String(i).hash() % 97, int(su[0]), int(su[1])), "price": _price(n, i, true)}
			var buys := {}
			for i in _choose(n, tcfg()["buys"], _hi(n, 5, int(wt[0]), int(wt[1])), 300):
				buys[i] = {"units": _hi(n, 400 + String(i).hash() % 97, int(wu[0]), int(wu[1])), "price": _price(n, i, false)}
			offer = {"sells": sells, "buys": buys}
		"science":
			var buys2 := {}
			for i in _choose(n, tcfg()["science_buys"], 2, 500):
				buys2[i] = {"units": _hi(n, 600 + String(i).hash() % 97, 2, 8), "price": _price(n, i, false)}
			offer = {"buys": buys2}
		"shuttle":
			var roles: Array = []
			var all: Array = sim.bal["roles"]
			for i in int(arr["people"]):
				roles.append(all[_hi(n, 700 + i, 0, all.size() - 1)])
			offer = {"roles": roles}
		"liner", "medical", "inspector":
			offer = {"people": int(arr["people"]), "fee": int(k.get("fee", 0))}
	arr["offer"] = offer
	return arr

func _queue_second(tick: int) -> void:
	var t: Dictionary = ts()
	var q: Array = t["queue"]
	var lead: int = int(float(cfg().get("forecast_days", 1.0)) * float(day_ticks()))
	var i := 0
	while i < q.size():
		var arr: Dictionary = q[i]
		if String(arr["phase"]) == "scheduled" and tick >= int(arr["at"]) - lead:
			arr["phase"] = "forecast"
			sim.log_event("ship_forecast", "%s arrives in %s: %s" % [kinds()[arr["kind"]]["name"], Text.n(maxi(0, (int(arr["at"]) - tick) / hz()), "second"), offer_text(arr)], [], 1)
		if tick >= int(arr["at"]):
			q.remove_at(i)
			if String(arr["answer"]) == "deny":
				arr["phase"] = "denied"
				_finish(arr, "The %s was sent away." % String(kinds()[arr["kind"]]["name"]).to_lower())
			else:
				arr["phase"] = "orbit"
				# In orbit, t = the tick the ship gives up and leaves (row t_s counts down to it).
				arr["t"] = _orbit_end(arr)
				(t["ships"] as Array).append(arr)
				sim.log_event("ship_orbit", "%s is in orbit and asks to land." % kinds()[arr["kind"]]["name"], [], 1)
			continue
		i += 1

## Words for what a ship brings and wants.
func offer_text(arr: Dictionary) -> String:
	var o: Dictionary = arr["offer"]
	match String(arr["kind"]):
		"trader":
			return "it sells %s and buys %s." % [", ".join((o["sells"] as Dictionary).keys().map(func(x): return sim.items.name_of(x).to_lower())), ", ".join((o["buys"] as Dictionary).keys().map(func(x): return sim.items.name_of(x).to_lower()))]
		"shuttle":
			return "%s want to join the colony." % Text.n((o["roles"] as Array).size(), "settler")
		"liner":
			return "%s want beds, meals and comfort." % Text.n(int(o["people"]), "tourist")
		"medical":
			return "%s need a medical bay." % Text.n(int(o["people"]), "patient")
		"science":
			return "%s want to use your labs." % Text.n(int(arr["people"]), "scientist")
		"inspector":
			return "an inspector will visit %s." % Text.n(_hi(int(arr["n"]), 8, 4, 6), "room")
	return ""

func _hold_hazard() -> bool:
	var hold: Array = cfg().get("hold_kinds", [])
	for ev in sim.state.get("hazards", {}).get("active", []):
		if hold.has(String(ev["kind"])):
			return true
	return false

func _orbit_end(arr: Dictionary) -> int:
	return int(arr["at"]) + int(float(cfg().get("orbit_hold_h", 6)) * float(hour_ticks()))

func _ships_second(tick: int) -> void:
	var t: Dictionary = ts()
	var ships: Array = t["ships"]
	var blds: Dictionary = sim.state["buildings"]
	var i := 0
	while i < ships.size():
		var arr: Dictionary = ships[i]
		var pad: Dictionary = blds.get(int(arr["pad"]), {})
		match String(arr["phase"]):
			"orbit":
				if String(arr["answer"]) == "deny":
					ships.remove_at(i)
					arr["phase"] = "denied"
					_finish(arr, "The %s was sent away." % String(kinds()[arr["kind"]]["name"]).to_lower())
					continue
				var p: int = -1 if _hold_hazard() else _free_pad()
				if p != -1:
					arr["phase"] = "landing"
					arr["pad"] = p
					arr["t"] = tick + int(float(cfg().get("descent_s", 20)) * hz())
					blds[p]["ship"] = int(arr["id"])
					sim.log_event("ship_landing", "%s is landing on %s." % [kinds()[arr["kind"]]["name"], blds[p]["name"]], [p], 1)
				elif tick >= _orbit_end(arr):
					ships.remove_at(i)
					arr["phase"] = "left"
					_finish(arr, "%s could not land and left." % kinds()[arr["kind"]]["name"])
					continue
			"landing":
				if pad.is_empty() or pad["state"] != "active":
					arr["phase"] = "orbit"
					arr["pad"] = -1
					arr["t"] = _orbit_end(arr)
				elif tick >= int(arr["t"]):
					_land(arr, pad, tick)
			"landed":
				if pad.is_empty() or pad["state"] != "active" or tick >= int(arr["t"]):
					arr["phase"] = "boarding"
					arr["t"] = tick + int(float(cfg().get("boarding_wait_h", 1)) * float(hour_ticks()))
					_settle(arr)
			"boarding":
				var aboard := true
				for vid in arr["visitors"]:
					var v: Dictionary = sim.state["agents"].get(int(vid), {})
					if not v.is_empty() and v["state"] == "alive" and int(v.get("ship", -1)) == int(arr["id"]):
						aboard = false
				if aboard or tick >= int(arr["t"]) or pad.is_empty():
					_takeoff(arr, tick)
			"takeoff":
				if tick >= int(arr["t"]):
					ships.remove_at(i)
					if not pad.is_empty():
						pad["ship"] = -1
					arr["phase"] = "gone"
					_finish(arr, "%s left." % kinds()[arr["kind"]]["name"])
					continue
		i += 1

func _finish(arr: Dictionary, text: String) -> void:
	var t: Dictionary = ts()
	var done: Array = t["done"]
	done.append(arr)
	while done.size() > 20:
		done.pop_front()
	sim.stat_add("ships", String(arr["phase"]), 1)
	sim.log_event("ship_" + String(arr["phase"]), text, [], 1)

# ---------------------------------------------------------------- landed
func _land(arr: Dictionary, pad: Dictionary, tick: int) -> void:
	arr["phase"] = "landed"
	arr["t"] = tick + int(arr["stay_s"]) * hz()
	arr["landed_at"] = tick
	var kind: String = arr["kind"]
	var k: Dictionary = kinds()[kind]
	var o: Dictionary = arr["offer"]
	if o.has("sells"):
		var inv: int = sim.inv.create_inv("b", int(pad["id"]), "trade", 100000)
		arr["stock_inv"] = inv
		var keys: Array = (o["sells"] as Dictionary).keys()
		keys.sort()
		for item in keys:
			sim.inv.add_new_forced(inv, item, int(o["sells"][item]["units"]), "ship")
	if o.has("buys"):
		arr["buy_inv"] = sim.inv.create_inv("b", int(pad["id"]), "trade", 100000)
	var spawn = sim.nav.best_access(pad, sim.world.center)
	var text: String = "%s landed on %s." % [k["name"], pad["name"]]
	if kind == "shuttle":
		var roles: Array = o["roles"]
		var who: Array = []
		if arr.has("accept_idx"):
			who = (arr["accept_idx"] as Array).duplicate()
		else:
			var n0: int = int(arr["accept"])
			if n0 < 0:
				var f: Dictionary = sim.metrics.forecast()
				n0 = clampi(int(f["beds"]) - int(f["pop"]), 0, roles.size())
			for r0 in clampi(n0, 0, roles.size()):
				who.append(r0)
		var n: int = who.size()
		for j in n:
			var a: Dictionary = sim.agents.spawn(String(roles[int(who[j])]), sim.next_name(), _spot(spawn, pad, j), -1)
			a["hunger"] = 25.0
			a["thirst"] = 25.0
		sim.stat_add("settlers", "", n)
		arr["result"]["settlers"] = n
		text += " %s joined the colony." % Text.n(n, "settler")
	elif int(arr["people"]) > 0:
		var n2: int = int(arr["people"])
		# Visitors come only when they can reach air on one suit, and tourists only into free beds.
		var can: int = n2 if spawn != null and _reachable(spawn) else 0
		if kind == "liner":
			can = mini(can, maxi(0, free_beds()))
		for vid in _adopt_stranded(arr):
			(arr["visitors"] as Array).append(vid)
		for i in can:
			var v: Dictionary = _spawn_visitor(arr, _spot(spawn, pad, i), i)
			(arr["visitors"] as Array).append(int(v["id"]))
		arr["result"]["came"] = can
		arr["result"]["aboard"] = n2 - can
		if can > 0:
			text += " %s came into the colony." % Text.n(can, "visitor")
		if can < n2:
			text += " %s stayed on board (no air in reach or no free bed)." % Text.n(n2 - can, "visitor")
	sim.stat_add("ships_landed", "", 1)
	sim.log_event("ship_landed", text, [int(pad["id"])], 1)

func _spot(spawn, pad: Dictionary, i: int) -> Vector2:
	var base: Vector2 = spawn if spawn != null else (pad["pos"] as Vector2)
	var q = sim.nav.nearest_walkable(base + Vector2(1.1 * float(i % 3), 1.1 * float(i / 3)), 6)
	return q if q != null else base

func _reachable(p: Vector2) -> bool:
	var r: Dictionary = sim.nav.nearest_supplied_lock(p)
	return bool(r["ok"]) and float(r["seconds"]) * 1.25 + 10.0 < sim.agents.suit_cap() * float(sim.bal["suit_task_fraction"])

## Plain notices for the traffic panel (V3.1): visitors are never a colony alert.
## Today: tourists who find no bed ("3 tourists have no bed. The fee drops.").
func notices() -> Array:
	var out: Array = []
	var tourists := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] == "visitor" and String(a.get("vkind", "")) == "liner":
			tourists += 1
	if tourists > 0:
		var f: Dictionary = sim.metrics.forecast()
		var spare: int = maxi(0, int(f["beds"]) - int(f["pop"]))
		var no_bed: int = tourists - mini(tourists, spare)
		if no_bed > 0:
			out.append({"code": "tourists_no_bed", "count": no_bed,
				"text": "%s %s no bed. The fee drops." % [Text.n(no_bed, "tourist"), "has" if no_bed == 1 else "have"]})
	return out

## Beds nobody of the colony needs: beds - colonists with a room bed - visitors here now.
func free_beds() -> int:
	var f: Dictionary = sim.metrics.forecast()
	var n: int = int(f["beds"]) - int(f["pop"])
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] == "visitor":
			n -= 1
	return n

func _spawn_visitor(arr: Dictionary, pos: Vector2, i: int) -> Dictionary:
	var k: Dictionary = kinds()[arr["kind"]]
	var t: Dictionary = ts()
	t["vcount"] = int(t.get("vcount", 0)) + 1
	var a: Dictionary = sim.agents.spawn("visitor", "%s %d" % [k.get("vname", "Visitor"), int(t["vcount"])], pos, -1)
	a["kind"] = "visitor"
	a["vkind"] = String(arr["kind"])
	a["ship"] = int(arr["id"])
	a["visit"] = {"ate": 0, "rec": 0, "slept": 0, "paid": 0, "treated": false, "study": 0.0, "tour": [], "toured": 0}
	a["hunger"] = 20.0
	a["thirst"] = 20.0
	if arr["kind"] == "medical":
		var hr: Array = k.get("health", [35, 50])
		a["health"] = float(_hi(int(arr["n"]), 900 + i, int(hr[0]), int(hr[1])))
	if arr["kind"] == "inspector":
		var rooms: Array = []
		for id in sim.topo.atmo_comp:
			var b: Dictionary = sim.state["buildings"][id]
			if b["def"] != "lander" and b["state"] == "active":
				rooms.append(int(id))
		rooms.sort()
		a["visit"]["tour"] = _choose(int(arr["n"]), rooms, _hi(int(arr["n"]), 8, 4, 6), 1000)
	sim.alive_changed()
	return a

## Visitors of this kind that an earlier ship left behind join this one.
func _adopt_stranded(arr: Dictionary) -> Array:
	var out: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] == "visitor" and int(a.get("ship", -1)) == -1 and String(a.get("vkind", "")) == String(arr["kind"]):
			a["ship"] = int(arr["id"])
			out.append(int(aid))
	return out

## Fees when the stay ends (the ship starts boarding): the minimum fee of the tourists who
## stayed on board. Visitors who came in pay when they board (visitor_fee).
func _settle(arr: Dictionary) -> void:
	var k: Dictionary = kinds()[arr["kind"]]
	if String(arr["kind"]) == "liner":
		var paid: int = int(round(float(k.get("fee", 0)) * float(k.get("fee_min", 0.3)))) * int(arr["result"].get("aboard", 0))
		if paid > 0:
			earn(paid, "fees")
			arr["result"]["fees"] = int(arr["result"].get("fees", 0)) + paid

## What a boarding visitor pays: a tourist by comfort (ate, relaxed, slept), an inspector
## by the goals done and the health of the rooms it saw. Patients paid when treated.
func visitor_fee(a: Dictionary) -> int:
	var k: Dictionary = kinds().get(String(a.get("vkind", "")), {})
	var fee: int = int(k.get("fee", 0))
	var vs: Dictionary = a["visit"]
	match String(a.get("vkind", "")):
		"liner":
			var score: float = 0.3 + (0.25 if int(vs["ate"]) > 0 else 0.0) + (0.25 if int(vs["rec"]) > 0 else 0.0) + (0.2 if int(vs["slept"]) > 0 else 0.0)
			return int(round(float(fee) * score))
		"inspector":
			var tour: Array = vs["tour"]
			var hsum := 0.0
			for rid in tour:
				hsum += float(sim.state["buildings"].get(int(rid), {}).get("health", 0.0))
			var mean_h: float = hsum / float(maxi(1, tour.size()))
			var goals_done := 0
			var goals_all := 0
			for g in sim.goals.list():
				goals_all += 1
				if g["state"] == "done":
					goals_done += 1
			var seen: float = float(int(vs["toured"])) / float(maxi(1, tour.size()))
			return int(round(float(fee) * (0.5 * float(goals_done) / float(maxi(1, goals_all)) + 0.5 * mean_h / 100.0) * seen))
	return 0

## A visitor boards its ship: it pays and leaves.
func on_board(a: Dictionary, arr: Dictionary) -> void:
	var fee: int = visitor_fee(a)
	if fee > 0:
		earn(fee, "fees")
		a["visit"]["paid"] = int(a["visit"]["paid"]) + fee
	arr["result"]["fees"] = int(arr["result"].get("fees", 0)) + fee + int(a["visit"]["paid"]) - fee

func _takeoff(arr: Dictionary, tick: int) -> void:
	arr["phase"] = "takeoff"
	arr["t"] = tick + int(float(cfg().get("takeoff_s", 15)) * hz())
	var left := 0
	for vid in arr["visitors"]:
		var v: Dictionary = sim.state["agents"].get(int(vid), {})
		if not v.is_empty() and v["state"] == "alive" and int(v.get("ship", -1)) == int(arr["id"]):
			v["ship"] = -1
			left += 1
	arr["result"]["left_behind"] = left
	# Trade ends: unsold stock leaves with the ship; units carried aboard were paid.
	for key in ["stock_inv", "buy_inv"]:
		var inv_id: int = int(arr[key])
		if inv_id == -1:
			continue
		sim.jobs.cancel_tasks_for_inventory(inv_id, "ship_left")
		sim.inv.release_for_inventory(inv_id)
		var inv: Dictionary = sim.inv.get_inv(inv_id)
		for item in (inv.get("items", {}) as Dictionary).keys():
			var n: int = int(inv["items"][item])
			if key == "stock_inv":
				sim.inv.destroy(inv_id, item, n, "ship_left")
			else:
				sim.inv.consume(inv_id, item, n, "sold")
				sim.stat_add("sold", item, n)
		sim.state["inventories"].erase(inv_id)
		arr[key] = -1
	sim.log_event("ship_takeoff", "%s takes off.%s" % [kinds()[arr["kind"]]["name"], (" %s stayed behind and wait for the next ship." % Text.n(left, "visitor")) if left > 0 else ""], [], 1)

## True when a ship's visitors should walk back: it boards, or it leaves within return_h.
func time_to_return(arr: Dictionary) -> bool:
	var ph: String = arr["phase"]
	if ph == "boarding":
		return true
	return ph == "landed" and int(sim.state["tick"]) >= int(arr["t"]) - int(float(cfg().get("return_h", 3)) * float(hour_ticks()))

# ---------------------------------------------------------------- trade
## Command "trade" {id, buy {item: n}, sell {item: n}}. Buying moves units from the ship to
## a pile at the pad at once (carriers store them); selling orders units that carriers take
## to the ship's hold, paid as they arrive. Returns {ok, code, cost, orders}.
func cmd_trade(p: Dictionary) -> Dictionary:
	var arr: Dictionary = ship(int(p.get("id", -1)))
	if arr.is_empty() or String(arr["phase"]) != "landed":
		return {"ok": false, "code": "no_ship"}
	var o: Dictionary = arr["offer"]
	var buy: Dictionary = p.get("buy", {})
	var sell: Dictionary = p.get("sell", {})
	var cost := 0
	for item in buy:
		var n: int = int(buy[item])
		if n <= 0:
			continue
		if not o.get("sells", {}).has(item) or sim.inv.available(int(arr["stock_inv"]), item) < n:
			return {"ok": false, "code": "no_stock"}
		cost += n * int(o["sells"][item]["price"])
	if cost > credits():
		return {"ok": false, "code": "no_credits"}
	var totals: Dictionary = sim.inv.totals()
	for item in sell:
		var n2: int = int(sell[item])
		if n2 <= 0:
			continue
		if not o.get("buys", {}).has(item):
			return {"ok": false, "code": "not_wanted"}
		var ordered: int = int(arr["orders"].get(item, {}).get("n", 0))
		if ordered + n2 > int(o["buys"][item]["units"]):
			return {"ok": false, "code": "too_many"}
		var have: int = int(totals.get(item, {}).get("total", 0)) - int(totals.get(item, {}).get("reserved", 0))
		if n2 > have:
			return {"ok": false, "code": "no_stock_colony"}
	if cost > 0:
		spend(cost, "trade")
		var pad: Dictionary = sim.state["buildings"][int(arr["pad"])]
		var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, sim.build.drop_point(pad))
		var keys: Array = buy.keys()
		keys.sort()
		for item in keys:
			if int(buy[item]) > 0:
				sim.inv.move(int(arr["stock_inv"]), pile, item, int(buy[item]))
				sim.stat_add("bought", item, int(buy[item]))
		sim.inv.remove_if_empty_pile(pile)
	for item in sell:
		if int(sell[item]) <= 0:
			continue
		var od: Dictionary = arr["orders"].get(item, {"n": 0, "paid": 0, "price": int(o["buys"][item]["price"])})
		od["n"] = int(od["n"]) + int(sell[item])
		arr["orders"][item] = od
	if cost > 0 or not sell.is_empty():
		sim.log_event("trade", "Trade with the %s: %s." % [String(kinds()[arr["kind"]]["name"]).to_lower(),
			"bought for %d credits" % cost if cost > 0 else "goods ordered for sale"], [], 1)
	return {"ok": true, "code": "ok", "cost": cost}

## Units carried to the ship's hold are paid as they arrive.
func _pay_deliveries() -> void:
	for arr in ts()["ships"]:
		if int(arr.get("buy_inv", -1)) == -1:
			continue
		for item in arr["orders"]:
			var od: Dictionary = arr["orders"][item]
			var got: int = sim.inv.count(int(arr["buy_inv"]), item)
			if got > int(od["paid"]):
				earn((got - int(od["paid"])) * int(od["price"]), "trade")
				od["paid"] = got

## For the job board: {buy_inv: {item: units ordered}} of landed ships.
func delivery_wants() -> Array:
	var out: Array = []
	for arr in ts()["ships"]:
		if String(arr["phase"]) != "landed" or int(arr.get("buy_inv", -1)) == -1 or (arr["orders"] as Dictionary).is_empty():
			continue
		var wants := {}
		for item in arr["orders"]:
			wants[item] = int(arr["orders"][item]["n"])
		out.append([int(arr["buy_inv"]), wants, int(arr["pad"])])
	return out

# ---------------------------------------------------------------- commands
## "traffic_answer" {id, grant: bool, accept?: int, accept_idx?: [int]}. accept = settlers a
## shuttle may leave (-1 = as many as there are free beds, the default); accept_idx (or
## accept_ids) = exactly these settlers, by index into offer.roles (V3.1).
func cmd_answer(p: Dictionary) -> Dictionary:
	var arr: Dictionary = find(int(p.get("id", -1)))
	if arr.is_empty():
		return {"ok": false, "code": "unknown"}
	if not ["scheduled", "forecast", "orbit"].has(String(arr["phase"])):
		return {"ok": false, "code": "too_late"}
	var pick = p.get("accept_idx", p.get("accept_ids", null))
	if pick != null:
		# Settlers by person (V3.1, UI request): indexes into offer.roles.
		if String(arr["kind"]) != "shuttle" or typeof(pick) != TYPE_ARRAY:
			return {"ok": false, "code": "invalid"}
		var n: int = (arr["offer"]["roles"] as Array).size()
		var idx: Array = []
		for v in pick:
			var i: int = int(v)
			if i < 0 or i >= n:
				return {"ok": false, "code": "invalid"}
			if not idx.has(i):
				idx.append(i)
		idx.sort()
		arr["accept_idx"] = idx
		arr["accept"] = idx.size()
	elif p.has("accept"):
		arr["accept"] = int(p["accept"])
		arr.erase("accept_idx")
	arr["answer"] = "grant" if bool(p.get("grant", true)) else "deny"
	return {"ok": true, "code": "ok"}

## "traffic_now" {kind, in?}: tests and screenshots only (state.options.debug). A ship of
## that kind arrives in `in` seconds (default 60). Recorded, so replays stay exact.
func cmd_now(p: Dictionary) -> Dictionary:
	if not bool(sim.state.get("options", {}).get("debug", false)):
		return {"ok": false, "code": "debug_only"}
	var kind: String = String(p.get("kind", ""))
	if not kinds().has(kind):
		return {"ok": false, "code": "invalid"}
	var t: Dictionary = ts()
	var tick: int = int(sim.state["tick"])
	var at: int = tick + int(maxf(1.0, float(p.get("in", 60.0))) * float(hz()))
	at += (hz() - at % hz()) % hz()
	var n: int = 100000 + int(t["n"])
	t["n"] = int(t["n"]) + 1
	var arr: Dictionary = _make_arrival(n, at, kind)
	arr["phase"] = "forecast"
	(t["queue"] as Array).append(arr)
	(t["queue"] as Array).sort_custom(func(x, y): return int(x["at"]) < int(y["at"]) if int(x["at"]) != int(y["at"]) else int(x["id"]) < int(y["id"]))
	return {"ok": true, "code": "ok", "id": int(arr["id"])}

# ---------------------------------------------------------------- read API
func find(id: int) -> Dictionary:
	for list in [ts()["queue"], ts()["ships"], ts()["done"]]:
		for arr in list:
			if int(arr["id"]) == id:
				return arr
	return {}

func ship(id: int) -> Dictionary:
	for arr in ts()["ships"]:
		if int(arr["id"]) == id:
			return arr
	return {}

func _row(arr: Dictionary) -> Dictionary:
	var tick: int = int(sim.state["tick"])
	var k: Dictionary = kinds()[arr["kind"]]
	var pad: Dictionary = sim.state["buildings"].get(int(arr["pad"]), {})
	var row := {"id": int(arr["id"]), "kind": arr["kind"], "name": k["name"], "phase": arr["phase"], "answer": arr["answer"],
		"eta_s": maxf(0.0, float(int(arr["at"]) - tick) / float(hz())), "at": int(arr["at"]),
		"stay_s": int(arr["stay_s"]), "people": int(arr["people"]), "offer": arr["offer"], "text": offer_text(arr),
		"pad": int(arr["pad"]), "pad_pos": pad.get("pos", Vector2.ZERO), "t_s": maxf(0.0, float(int(arr["t"]) - tick) / float(hz())),
		"visitors": (arr["visitors"] as Array).duplicate(), "accept": int(arr["accept"]), "result": arr["result"]}
	if arr.has("accept_idx"):
		row["accept_idx"] = (arr["accept_idx"] as Array).duplicate()
	if int(arr.get("stock_inv", -1)) != -1:
		row["stock"] = (sim.inv.get_inv(int(arr["stock_inv"])).get("items", {}) as Dictionary).duplicate()
	if not (arr["orders"] as Dictionary).is_empty():
		row["orders"] = arr["orders"]
	return row

## Arrivals the player may see (forecast), soonest first.
func forecast() -> Array:
	var out: Array = []
	for arr in ts()["queue"]:
		if String(arr["phase"]) != "scheduled":
			out.append(_row(arr))
	return out

## Ships in orbit, landing, on a pad, boarding or taking off. t_s = seconds left in the phase.
func ships() -> Array:
	var out: Array = []
	for arr in ts()["ships"]:
		out.append(_row(arr))
	return out

## Every planned arrival, hidden ones too (tests and debug only).
func queue_all() -> Array:
	var out: Array = []
	for arr in ts()["queue"]:
		out.append(_row(arr))
	return out
