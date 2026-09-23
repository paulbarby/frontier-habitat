extends RefCounted
## Environment, electricity, water and atmosphere (spec 8).
## Continuous stocks are fixed-point integers: FP sub-units per unit. With FP = 60000,
## a rate of 0.1 units/day is exactly 1 sub-unit per tick, so no stock drifts or goes
## negative. All stocks live ON buildings (battery.energy, reservoir.water, room.oxygen);
## a network component is only the sum of its members, so a cut network keeps exactly
## what is physically on each side (acceptance 2).
## Every rate and capacity comes from the building's effective definition (sim.bd: size
## and level) and the colony's research bonuses.
##
## Speed: per network component the static facts (members in priority order, rates,
## capacities) are kept in "plans". They are derived data: invalidate() drops them after a
## topology rebuild, an upgrade or a change of the power order. States that change from
## tick to tick (enabled, powered, stocks) are always read from the records.

const Rng = preload("res://sim/rng.gd")

var sim
var power_stats := {}   # comp -> {gen, demand, served, stored, cap, shed:[ids], has_source}
var water_stats := {}   # comp -> {stock, cap, in, out, recycled}
var atmo_stats := {}    # comp -> {stock, cap, make, breathe, supplied, people}
var _pplan := {}        # power comp -> [entry] sorted by (power class, id)
var _wplan := {}        # power comp -> {res, caps, cap, fills, prod, recs}
var _aplan := {}        # atmo comp -> {rooms, caps, cap_f, prod, lander}
var _fp := 60000
var _per_tick := 0.0    # fp / (day_length * tick_hz)

func _init(s) -> void:
	sim = s
	_fp = int(sim.bal["fixed_point_scale"])
	_per_tick = float(_fp) / (float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))

func fp() -> int:
	return _fp

## Units-per-day rate -> sub-units per tick.
func rt(rate_per_day: float) -> int:
	return int(round(rate_per_day * _per_tick))

func units(sub: int) -> float:
	return float(sub) / float(_fp)

## Walking speed outside now (a dust storm slows it).
func out_speed() -> float:
	return float(sim.bal["speed_outdoor"]) * float(sim.state["env"].get("speed_mult", 1.0))

## Drops the cached plans (topology rebuild, upgrade, power order change, load).
func invalidate() -> void:
	_pplan = {}
	_wplan = {}
	_aplan = {}

# ---------------------------------------------------------------- capacities
func energy_cap_of(b: Dictionary) -> int:
	var d: Dictionary = sim.bd(b)
	return int(float(d.get("energy_cap", 0.0)) * (1.0 + sim.research.bonus("battery_mult")) * _fp)

func water_cap_of(b: Dictionary) -> int:
	return int(float(sim.bd(b).get("water_cap", 0.0)) * _fp)

# ---------------------------------------------------------------- environment
func day_time() -> float:
	var hz: int = int(sim.bal["tick_hz"])
	var dl: int = int(sim.bal["day_length"])
	return float(int(sim.state["tick"]) % (dl * hz)) / float(hz)

func day_number() -> int:
	return int(sim.state["tick"]) / (int(sim.bal["day_length"]) * int(sim.bal["tick_hz"])) + 1

func days_elapsed() -> float:
	return float(sim.state["tick"]) / float(int(sim.bal["day_length"]) * int(sim.bal["tick_hz"]))

func is_night() -> bool:
	return day_time() >= float(sim.planet["daylight_seconds"])

func seconds_to_sunrise() -> float:
	if not is_night():
		return 0.0
	return float(sim.bal["day_length"]) - day_time()

func seconds_to_sunset() -> float:
	if is_night():
		return 0.0
	return float(sim.planet["daylight_seconds"]) - day_time()

func env_tick() -> void:
	var env: Dictionary = sim.state["env"]
	var t: float = day_time()
	var daylight: float = float(sim.planet["daylight_seconds"])
	var ramp: float = float(sim.bal["solar_ramp_seconds"])
	var sun := 0.0
	if t < daylight:
		sun = clampf(minf(t, daylight - t) / ramp, 0.0, 1.0)
	env["sun"] = sun
	var hz: int = int(sim.bal["tick_hz"])
	var step_ticks: int = int(float(sim.bal["wind_step_seconds"]) * hz)
	if int(sim.state["tick"]) % step_ticks == 0:
		var avg: float = float(sim.planet["wind_avg"])
		var v: float = float(sim.planet["wind_var"])
		var r: float = Rng.next_float(sim.state["rng"], "weather") * 2.0 - 1.0
		var r2: float = Rng.next_float(sim.state["rng"], "weather") * 2.0 - 1.0
		env["wind_target"] = clampf(avg + v * (r + r2 * 0.6), 0.0, float(sim.planet["wind_max"]))
	var cur: float = float(env["wind_raw"])
	cur += clampf(float(env["wind_target"]) - cur, -0.02, 0.02)
	env["wind_raw"] = cur
	env["wind"] = roundf(cur * 10.0) / 10.0

# ---------------------------------------------------------------- electricity
static func is_generator(def: Dictionary) -> bool:
	return def.has("gen_solar") or def.has("gen_wind") or def.has("gen_const")

## The members of a power component in allocation order: power class, then id.
## Each entry is an Array (read by index, which is much faster than by key):
const PE_B := 0        # the building
const PE_F := 1        # flags: PF_SOLAR | PF_WIND | PF_FUSION | PF_BATT | PF_CONS
const PE_SOLAR := 2
const PE_WIND := 3
const PE_D := 4        # the effective definition
const PE_CAP := 5      # battery capacity, units
const PE_RATE := 6     # battery rate, sub-units per tick
const PE_EFF := 7
const PE_WANT := 8     # consumer draw, sub-units per tick
const PE_CLS := 9
const PE_LIFE := 10
const PE_ID := 11
const PF_SOLAR := 1
const PF_WIND := 2
const PF_FUSION := 4
const PF_BATT := 8
const PF_CONS := 16

## {"entries": [entry], "has_source": bool}
func _power_plan(comp: int) -> Dictionary:
	var p = _pplan.get(comp)
	if p != null:
		return p
	var blds: Dictionary = sim.state["buildings"]
	var order: Array = sim.state["policies"]["power_order"]
	var entries: Array = []
	var has_source := false
	for bid in sim.topo.power_members[comp]:
		var b: Dictionary = blds[bid]
		var d: Dictionary = sim.bd(b)
		var base: Dictionary = sim.bdef(b["def"])
		var pc: String = String(base.get("power_class", "industry"))
		var solar: float = float(d.get("gen_solar", 0.0))
		var wind: float = float(d.get("gen_wind", 0.0))
		var f := 0
		if solar > 0.0:
			f |= PF_SOLAR
		if wind > 0.0:
			f |= PF_WIND
		if d.has("gen_const"):
			f |= PF_FUSION
		if d.has("energy_cap"):
			f |= PF_BATT
		if float(d.get("power", 0.0)) > 0.0:
			f |= PF_CONS
		if is_generator(d) or d.has("energy_cap"):
			has_source = true
		entries.append([b, f, solar, wind, d, float(d.get("energy_cap", 0.0)), rt(float(d.get("energy_rate", 0.0))),
			float(d.get("energy_eff", 0.95)), rt(float(d.get("power", 0.0))), order.find(pc), pc == "life_support", int(bid)])
	entries.sort_custom(func(x, y): return int(x[PE_CLS]) < int(y[PE_CLS]) if int(x[PE_CLS]) != int(y[PE_CLS]) else int(x[PE_ID]) < int(y[PE_ID]))
	p = {"entries": entries, "has_source": has_source}
	_pplan[comp] = p
	return p

## Structures outside every power network (links excluded). Made again when the plans
## are dropped or the set of buildings changes.
var _off_grid: Array = []
var _off_key := ""

func _off_grid_ids() -> Array:
	var blds: Dictionary = sim.state["buildings"]
	var key: String = "%d:%d:%d" % [blds.size(), int(sim.state["next_id"]), _pplan.size()]
	if key == _off_key and not _pplan.is_empty():
		return _off_grid
	_off_key = key
	_off_grid = []
	for id in blds:
		if blds[id]["kind"] != "link" and not sim.topo.power_comp.has(id):
			_off_grid.append(id)
	return _off_grid

func power_tick() -> void:
	power_stats = {}
	var blds: Dictionary = sim.state["buildings"]
	var topo = sim.topo
	var env: Dictionary = sim.state["env"]
	var tick: int = int(sim.state["tick"])
	var min_off: int = int(float(sim.bal["shed_min_off_seconds"]) * float(sim.bal["tick_hz"]))
	var sun: float = float(env["sun"])
	var wind: float = float(env["wind"])
	var solar_mult: float = float(sim.planet["solar_mult"]) * float(env.get("solar_mult", 1.0)) * (1.0 + sim.research.bonus("solar_mult"))
	var wind_mult: float = 1.0 + sim.research.bonus("wind_mult")
	var batt_mult: float = 1.0 + sim.research.bonus("battery_mult")
	for id in _off_grid_ids():
		var b0: Dictionary = blds.get(id, {})
		if not b0.is_empty():
			b0["powered"] = false
	for comp in topo.power_members:
		var gen := 0
		var consumers: Array = []
		var batteries: Array = []
		var plan: Dictionary = _power_plan(comp)
		var has_source: bool = plan["has_source"]
		for e in plan["entries"]:
			var b: Dictionary = e[PE_B]
			if b["state"] != "active":
				b["powered"] = false
				continue
			var f: int = e[PE_F]
			if f & (PF_SOLAR | PF_WIND | PF_FUSION):
				if f & PF_SOLAR:
					gen += rt(float(e[PE_SOLAR]) * sun * solar_mult * float(b["out_rate"]))
				if f & PF_WIND:
					gen += rt(float(e[PE_WIND]) * wind * wind_mult * float(b["out_rate"]))
				if f & PF_FUSION:
					gen += _fusion(b, e[PE_D])
			if f & PF_BATT:
				batteries.append(e)
			if f & PF_CONS:
				if bool(b["enabled"]):
					consumers.append(e)
				else:
					b["powered"] = false
			else:
				b["powered"] = true
		var stored := 0
		var cap := 0
		var rate := 0
		for bt in batteries:
			stored += int(bt[PE_B]["energy"])
			cap += int(float(bt[PE_CAP]) * batt_mult * _fp)
			rate += int(bt[PE_RATE])
		var available: int = gen + mini(rate, stored)
		var served := 0
		var demand := 0
		var critical := 0
		var shed: Array = []
		var cut_class := 999      # once a class loses a member, every later class is off
		for ce in consumers:
			var c: Dictionary = ce[PE_B]
			var want: int = int(ce[PE_WANT])
			demand += want
			if bool(ce[PE_LIFE]):
				critical += want
			var was: bool = bool(c["powered"])
			var cls: int = int(ce[PE_CLS])
			if cls > cut_class:
				# Strict priority (acceptance 3): a small comfort load never keeps power
				# while a life-support load is off.
				c["powered"] = false
				shed.append(c["id"])
				if was:
					c["shed_until"] = tick + min_off
			elif available > 0 and tick < int(c["shed_until"]):
				c["powered"] = false
				shed.append(c["id"])
				cut_class = mini(cut_class, cls)
			elif served + want <= available:
				c["powered"] = true
				served += want
			else:
				c["powered"] = false
				shed.append(c["id"])
				cut_class = mini(cut_class, cls)
				if was:
					c["shed_until"] = tick + min_off
		if gen >= served:
			var charge: int = mini(gen - served, rate)
			var gain: int = int(floor(charge * 0.95))
			if not batteries.is_empty():
				gain = int(floor(charge * float(batteries[0][PE_EFF])))
			for bt in batteries:
				var bb: Dictionary = bt[PE_B]
				var room: int = int(float(bt[PE_CAP]) * batt_mult * _fp) - int(bb["energy"])
				var put: int = clampi(room, 0, gain)
				bb["energy"] = int(bb["energy"]) + put
				gain -= put
		else:
			var need: int = served - gen
			for bt in batteries:
				var bb: Dictionary = bt[PE_B]
				var takes: int = mini(int(bb["energy"]), need)
				bb["energy"] = int(bb["energy"]) - takes
				need -= takes
		var stored_after := 0
		for bt in batteries:
			stored_after += int(bt[PE_B]["energy"])
		power_stats[comp] = {"gen": gen, "demand": demand, "served": served, "critical": critical,
			"stored": stored_after, "cap": cap, "shed": shed, "has_source": has_source, "rate": rate}

## A fusion reactor makes its constant power while it gets its cooling water.
func _fusion(b: Dictionary, def: Dictionary) -> int:
	if not bool(b["enabled"]):
		b["block"] = "disabled"
		return 0
	var w: int = rt(float(def.get("water_in", 0.0)))
	if w > 0 and not draw_water(b["id"], w, 1):
		b["block"] = "no_water"
		return 0
	b["block"] = ""
	return rt(float(def["gen_const"]) * float(b["out_rate"]))

## P value (units per day) of a per-tick sub-unit amount, for display.
func to_rate(sub_per_tick: int) -> float:
	return float(sub_per_tick) * float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]) / float(_fp)

# ---------------------------------------------------------------- water
## Reservoirs (with capacities), fill ports, extractors and recyclers of a component.
func _water_plan(comp: int) -> Dictionary:
	var p = _wplan.get(comp)
	if p != null:
		return p
	var blds: Dictionary = sim.state["buildings"]
	var res: Array = []
	var caps: Array = []
	var total := 0
	var prod: Array = []
	var recs: Array = []
	for bid in sim.topo.power_members.get(comp, []):
		var b: Dictionary = blds[bid]
		if b["state"] != "active":
			continue
		var d: Dictionary = sim.bd(b)
		if d.has("water_cap"):
			var c: int = int(float(d["water_cap"]) * _fp)
			res.append(b)
			caps.append(c)
			total += c
		if d.has("water_out"):
			prod.append([b, d])
		elif d.has("recycle_per_day"):
			recs.append([b, d])
	p = {"res": res, "caps": caps, "cap": total, "prod": prod, "recs": recs}
	_wplan[comp] = p
	return p

func _reservoirs(comp: int) -> Array:
	return _water_plan(comp)["res"]

func water_stock(comp: int) -> int:
	var s := 0
	for r in _water_plan(comp)["res"]:
		s += int(r["water"])
	return s

func water_tick() -> void:
	water_stats = {}
	var rec_frac_mult: float = 1.0 + sim.research.bonus("recycle_mult")
	for comp in sim.topo.power_members:
		var wp: Dictionary = _water_plan(comp)
		var res: Array = wp["res"]
		if res.is_empty() and (wp["prod"] as Array).is_empty() and (wp["recs"] as Array).is_empty():
			continue      # no water structure on this network: no water numbers for it
		var cap: int = int(wp["cap"])
		var stock := 0
		for r in res:
			stock += int(r["water"])
		var added := 0
		# Delivered water units enter the network here (spec 6: lander water by delivery job).
		for r in res:
			if int(r["inv_fill"]) == -1:
				continue
			while sim.inv.count(r["inv_fill"], "water") > 0 and stock + _fp <= cap:
				sim.inv.consume(r["inv_fill"], "water", 1, "to_network")
				stock += _fp
				added += _fp
		for pair in wp["prod"]:
			var b: Dictionary = pair[0]
			if not bool(b["enabled"]):
				b["block"] = "disabled"
			elif not bool(b["powered"]):
				b["block"] = "no_power"
			elif res.is_empty():
				b["block"] = "no_reservoir"
			elif stock >= cap:
				b["block"] = "storage_full"
			else:
				var put: int = mini(cap - stock, rt(float(pair[1]["water_out"]) * float(b["out_rate"])))
				stock += put
				added += put
				b["block"] = ""
		var recycled := 0
		for pair in wp["recs"]:
			# The recycler returns water the network used: see draw_water().
			var b: Dictionary = pair[0]
			var acc: Dictionary = b["acc"]
			var pool: int = int(acc.get("pool", 0))
			if not bool(b["enabled"]):
				b["block"] = "disabled"
			elif not bool(b["powered"]):
				b["block"] = "no_power"
			elif res.is_empty():
				b["block"] = "no_reservoir"
			elif pool <= 0:
				b["block"] = ""
			else:
				var back: int = mini(mini(pool, cap - stock), rt(float(pair[1]["recycle_per_day"]) * rec_frac_mult * float(b["out_rate"])))
				if back > 0:
					stock += back
					recycled += back
					acc["pool"] = pool - back
				b["block"] = "storage_full" if stock >= cap else ""
		_spread_water(wp, stock)
		water_stats[comp] = {"stock": stock, "cap": cap, "in": added + recycled, "out": 0, "recycled": recycled}

func _reserve(tier: int, cap: int) -> int:
	var reserve := 0
	if tier >= 1:
		reserve += int(float(sim.bal["water_reserve_drink_units_per_colonist"]) * sim.alive_count() * _fp)
	if tier >= 2:
		reserve += int(float(sim.bal["water_reserve_oxygen_units"]) * _fp)
	return mini(reserve, cap / 2)

## Takes water from the network of building `bid`. tier 0 = drinking, 1 = oxygen plants,
## 2 = crops and industry. Lower tiers are protected by reserves (spec 8). All or nothing.
func draw_water(bid: int, amount: int, tier: int) -> bool:
	if not sim.topo.power_comp.has(bid):
		return false
	var comp: int = sim.topo.power_comp[bid]
	var wp: Dictionary = _water_plan(comp)
	var res: Array = wp["res"]
	if res.is_empty():
		return false
	var stock := 0
	for r in res:
		stock += int(r["water"])
	if stock - amount < _reserve(tier, int(wp["cap"])):
		return false
	_spread_water(wp, stock - amount)
	if water_stats.has(comp):
		water_stats[comp]["stock"] = stock - amount
		water_stats[comp]["out"] = int(water_stats[comp]["out"]) + amount
	_to_recyclers(wp, amount)
	return true

## Half of the water a network uses (more with research) goes into the pool of its first
## running recycler, up to one day of that recycler's rate.
func _to_recyclers(wp: Dictionary, amount: int) -> void:
	var recs: Array = wp["recs"]
	if recs.is_empty():
		return
	var frac: float = minf(0.9, 0.5 * (1.0 + sim.research.bonus("recycle_mult")))
	for pair in recs:
		var r: Dictionary = pair[0]
		if not bool(r["enabled"]) or not bool(r["powered"]):
			continue
		var limit: int = int(float(pair[1]["recycle_per_day"]) * _fp)
		var acc: Dictionary = r["acc"]
		acc["pool"] = mini(limit, int(acc.get("pool", 0)) + int(amount * frac))
		return

## True when the network of `bid` could give one unit of water at this tier now.
## The job board uses it so that growers do not seed a tray that cannot be watered.
func water_available(bid: int, tier: int) -> bool:
	if not sim.topo.power_comp.has(bid):
		return false
	var wp: Dictionary = _water_plan(sim.topo.power_comp[bid])
	var res: Array = wp["res"]
	if res.is_empty():
		return false
	var stock := 0
	for r in res:
		stock += int(r["water"])
	return stock - _fp >= _reserve(tier, int(wp["cap"]))

func can_drink_at(bid: int) -> bool:
	if not sim.topo.power_comp.has(bid):
		return false
	return water_stock(sim.topo.power_comp[bid]) >= int(sim.bal["drink_units"]) * _fp

## Spreads a component's water over its reservoirs in proportion to capacity.
func _spread_water(wp: Dictionary, total: int) -> void:
	var res: Array = wp["res"]
	var caps: Array = wp["caps"]
	var cap_sum: float = float(wp["cap"])
	if cap_sum <= 0.0:
		return
	var left: int = total
	var n: int = res.size()
	for i in n:
		var share: int = left if i == n - 1 else int(floor(total * (float(caps[i]) / cap_sum)))
		share = mini(share, left)
		res[i]["water"] = share
		left -= share

# ---------------------------------------------------------------- atmosphere
func lander_supplied(b: Dictionary) -> bool:
	var days: float = float(sim.bdef(b["def"]).get("shelter_days", 3.0))
	return days_elapsed() < days and b["state"] == "active"

func lander_seconds_left() -> float:
	var lid: int = int(sim.state["lander_id"])
	if not sim.state["buildings"].has(lid):
		return 0.0
	var days: float = float(sim.bdef("lander").get("shelter_days", 3.0))
	return maxf(0.0, (days - days_elapsed()) * float(sim.bal["day_length"]))

func comp_supplied(comp: int) -> bool:
	if atmo_stats.has(comp):
		return bool(atmo_stats[comp]["supplied"])
	return false

func building_supplied(bid: int) -> bool:
	if not sim.topo.atmo_comp.has(bid):
		return false
	return comp_supplied(sim.topo.atmo_comp[bid])

## Oxygen per day that the working producers can make: oxygen plants and atmosphere
## processors (o2_out) and algae bioreactors (o2_bonus). Stopped producers do not count.
func o2_capacity_per_day() -> float:
	var total := 0.0
	var o2_mult: float = 1.0 + sim.research.bonus("o2_mult")
	for comp in sim.topo.atmo_members:
		var ap: Dictionary = _atmo_plan(comp)
		for pr in ap["prod"]:
			var b: Dictionary = pr[0]
			var d: Dictionary = pr[1]
			if b["state"] != "active" or not bool(b["enabled"]) or not bool(b["powered"]) or b["block"] == "no_water":
				continue
			if d.has("o2_out"):
				total += float(d["o2_out"]) * o2_mult * float(b["out_rate"])
			else:
				total += float(d["o2_bonus"]) * float(b["out_rate"])
	return total

## Rooms of an atmosphere component with their oxygen capacity, and its producers.
func _atmo_plan(comp: int) -> Dictionary:
	var p = _aplan.get(comp)
	if p != null:
		return p
	var blds: Dictionary = sim.state["buildings"]
	var members: Array = sim.topo.atmo_members[comp]
	var per_occ: float = float(sim.bal["oxygen_per_occupant_capacity"])
	var rooms: Array = []
	var caps: Array = []
	var cap_f := 0.0
	var prod: Array = []
	for bid in members:
		var b: Dictionary = blds[bid]
		var d: Dictionary = sim.bd(b)
		var c: float = float(d.get("occupants", 1)) * per_occ
		rooms.append(b)
		caps.append(c)
		cap_f += c
		if d.has("o2_out") or d.has("o2_bonus"):
			prod.append([b, d])
	var room_cap: float = cap_f
	cap_f += float(sim.topo.atmo_corridor_len.get(comp, 0.0)) / 10.0 * float(sim.bal["oxygen_per_corridor_10m"])
	p = {"rooms": rooms, "caps": caps, "room_cap": room_cap, "cap": int(cap_f * _fp), "prod": prod,
		"lander": blds[members[0]]["kind"] == "special"}
	_aplan[comp] = p
	return p

func atmo_tick() -> void:
	atmo_stats = {}
	var people := {}
	var acomp: Dictionary = sim.topo.atmo_comp
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["where"] == "out":
			continue
		var c = acomp.get(a["bld"])
		if c != null:
			people[c] = int(people.get(c, 0)) + 1
	var breath: int = rt(float(sim.bal["oxygen_per_colonist"]))
	var o2_mult: float = 1.0 + sim.research.bonus("o2_mult")
	var blds: Dictionary = sim.state["buildings"]
	for comp in sim.topo.atmo_members:
		var ap: Dictionary = _atmo_plan(comp)
		var n: int = int(people.get(comp, 0))
		if bool(ap["lander"]):
			var first: Dictionary = blds[sim.topo.atmo_members[comp][0]]
			atmo_stats[comp] = {"stock": 0, "cap": 0, "make": 0, "breathe": n * breath, "supplied": lander_supplied(first), "people": n, "lander": true}
			continue
		var rooms: Array = ap["rooms"]
		var cap: int = int(ap["cap"])
		var stock := 0
		var breaches := 0
		for b in rooms:
			stock += int(b["oxygen"])
			if bool(b["breach"]):
				breaches += 1
		stock = mini(stock, cap)
		var made := 0
		for pr in ap["prod"]:
			var b: Dictionary = pr[0]
			var def: Dictionary = pr[1]
			if b["state"] != "active":
				continue
			var algae: bool = not def.has("o2_out")
			if not bool(b["enabled"]):
				if not algae:
					b["block"] = "disabled"
				continue
			if not bool(b["powered"]):
				if not algae:
					b["block"] = "no_power"
				continue
			if algae:
				# A bioreactor adds oxygen while its algae live (auto_second sets its block).
				if b["block"] == "no_water" or stock >= cap:
					continue
				var add_a: int = mini(rt(float(def["o2_bonus"]) * float(b["out_rate"])), cap - stock)
				stock += add_a
				made += add_a
				continue
			if stock >= cap:
				b["block"] = "storage_full"
				continue
			var want: int = rt(float(def["o2_out"]) * o2_mult * float(b["out_rate"]))
			var add: int = mini(want, cap - stock)
			var water_in: float = float(def.get("water_in", 0.0))
			if water_in <= 0.0:
				stock += add
				made += add
				b["block"] = ""
				continue
			var water_need: int = int(ceil(float(rt(water_in * float(b["out_rate"]))) * float(add) / float(maxi(1, want))))
			if draw_water(b["id"], water_need, 1):
				stock += add
				made += add
				b["block"] = ""
			else:
				b["block"] = "no_water"
		var need: int = n * breath
		var supplied := true
		if stock >= need and stock > 0:
			stock -= need
		elif need > 0:
			stock = 0
			supplied = false
		else:
			supplied = stock > 0
		if breaches > 0:
			stock = maxi(0, stock - breaches * rt(float(sim.bal["breach_drain_per_day"])))
		_spread_air(ap, stock)
		atmo_stats[comp] = {"stock": stock, "cap": cap, "make": made, "breathe": need, "supplied": supplied and stock > 0, "people": n, "lander": false}

## Spreads a component's oxygen over its rooms in proportion to their capacity.
func _spread_air(ap: Dictionary, total: int) -> void:
	var rooms: Array = ap["rooms"]
	var caps: Array = ap["caps"]
	var cap_sum: float = float(ap["room_cap"])
	if cap_sum <= 0.0:
		return
	var left: int = total
	var n: int = rooms.size()
	for i in n:
		var share: int = left if i == n - 1 else int(floor(total * (float(caps[i]) / cap_sum)))
		share = mini(share, left)
		rooms[i]["oxygen"] = share
		left -= share
