extends RefCounted
## Hazards (docs/V3_DESIGN.md section 4): meteors, meteor showers, wind storms, dust
## storms, quakes, solar flares, dust devils, and wear-based machine breakdowns.
##
## Determinism. Every event comes from the "hazard" random stream and the state. The
## scheduler keeps a queue of future events at least horizon_days ahead; it draws only
## when it extends the queue, at fixed ticks (every plan_every_s). Same seed + same
## commands = same events, same places, same results. A command can change what an event
## DOES (a turret, a shelter order, a repair), never whether or where a queued event
## happens. Randomness at the moment of impact (which corridor cracks) uses a hash of the
## event id and the structure id, never the stream. Machine failure thresholds are a hash
## of the building id and its repair count, so building one more machine does not move
## any meteor.
##
## state.hazards = {next_id, queue: [ev], active: [ev], done_count: {kind: n},
##                  wear: {bid: {w, fail_at, fault, n, broken}}, next_at: {kind: tick},
##                  seen: {kind: n}, shelter, sites: {inv_id: site}, craters: [],
##                  breached: [link ids], start_tick, first_first: {}}
## Event: {id, kind, at, end, pos, radius, severity, path?, strikes?, detected_tick,
##         phase: "scheduled"|"forecast"|"warning"|"active"|"done", countered, hits: [],
##         result: {}}
## The v2 dust storm (state.events.storm) lives here as kind "dust_storm"; sim.events
## keeps its v2 read API and state.events.storm stays as a mirror for older views.

const Rng = preload("res://sim/rng.gd")
const Text = preload("res://sim/text.gd")

var sim

const KINDS := ["meteor", "meteor_shower", "wind_storm", "dust_storm", "quake", "solar_flare", "dust_devil"]
const WHOLE_MAP := ["wind_storm", "dust_storm", "solar_flare"]
const NAMES := {"meteor": "Meteor strike", "meteor_shower": "Meteor shower", "wind_storm": "Wind storm",
	"dust_storm": "Dust storm", "quake": "Quake", "solar_flare": "Solar flare", "dust_devil": "Dust devil",
	"breakdown": "Breakdown"}
## Structures that a solar flare trips off unless Surge Protection is researched.
const TRIP_DEFS := ["electronics_fab", "research_lab", "comms_tower", "meteor_turret"]
const FAULTS := ["mechanical", "electrical", "seal"]

func _init(s) -> void:
	sim = s

static func fresh_state() -> Dictionary:
	return {"next_id": 1, "queue": [], "active": [], "done_count": {}, "wear": {}, "next_at": {},
		"seen": {}, "shelter": false, "sites": {}, "craters": [], "breached": [], "start_tick": 0}

func hs() -> Dictionary:
	if not sim.state.has("hazards"):
		sim.state["hazards"] = fresh_state()
	return sim.state["hazards"]

func cfg() -> Dictionary:
	return sim.bal["hazards"]

func kcfg(kind: String) -> Dictionary:
	return cfg()["kinds"].get(kind, {})

func hz() -> int:
	return int(sim.bal["tick_hz"])

func day_ticks() -> int:
	return int(sim.bal["day_length"]) * hz()

## Hazard setting of this game: "off" | "mild" | "normal" | "hard".
func setting() -> String:
	return String(sim.state.get("options", {}).get("hazards", "normal"))

func level() -> float:
	return float(cfg()["settings"].get(setting(), 1.0))

func kind_on(kind: String) -> bool:
	if level() <= 0.0:
		return false
	if kind == "dust_storm":
		return bool(sim.bal.get("storm", {}).get("enabled", true)) and bool(sim.state.get("options", {}).get("storms", true))
	return float(kcfg(kind).get("per_day", 0.0)) > 0.0

func first_tick() -> int:
	var days: float = float(sim.content["scenarios"].get(sim.state["scenario"], {}).get("no_disaster_days", 5))
	return maxi(int(days * float(day_ticks())), int(hs().get("start_tick", 0)))

# ---------------------------------------------------------------- per second
func tick_second() -> void:
	var tick: int = int(sim.state["tick"])
	var h: Dictionary = hs()
	var plan_every: int = int(float(cfg().get("plan_every_s", 60)) * hz())
	if tick % plan_every == 0 or int(h.get("last_plan", -1)) < 0:
		h["last_plan"] = tick
		_plan()
	_phases(tick)
	_active_second(tick)
	_env_update()
	_turrets_second()
	_wear_second()
	_shelter_second()
	_mirror_storm()

# ---------------------------------------------------------------- scheduling
func _plan() -> void:
	var tick: int = int(sim.state["tick"])
	var h: Dictionary = hs()
	var horizon: int = tick + int(float(cfg().get("horizon_days", 2.0)) * float(day_ticks()))
	var first: int = first_tick()
	# Nothing is drawn before the horizon reaches the first day an event may happen: the
	# hazard stream stays untouched in the first days (as in version 2).
	if horizon < first:
		return
	# The dust storm keeps its version-2 rule (only planned once day first-1 is near).
	for kind in KINDS:
		if not kind_on(kind):
			continue
		if kind == "dust_storm" and tick < first - day_ticks() and not h["next_at"].has(kind):
			continue
		var nxt: int = int(h["next_at"].get(kind, -1))
		if nxt < 0:
			nxt = _first_at(kind, maxi(tick, first))
			h["next_at"][kind] = nxt
		var guard := 0
		while nxt <= horizon and guard < 40:
			guard += 1
			var gap: int = _gap_ticks(kind)
			if gap <= 0:
				nxt = horizon + day_ticks()
				break
			var ev: Dictionary = _make_event(kind, nxt)
			nxt = maxi(int(ev["end"]), nxt) + gap
		h["next_at"][kind] = nxt

func _first_at(kind: String, earliest: int) -> int:
	var at: int = earliest
	if kind == "dust_storm":
		at += int(Rng.range_float(sim.state["rng"], "hazard", 0.0, float(sim.bal["storm"]["interval_days"][0])) * float(day_ticks()))
	else:
		var gap: int = _gap_ticks(kind)
		at += gap if gap > 0 else day_ticks()
	return at - at % hz()

## Ticks to the next event of a kind: exponential with the kind's rate, 0.25..6 days.
## The dust storm keeps the v2 interval (uniform in interval_days).
func _gap_ticks(kind: String) -> int:
	var rng: Dictionary = sim.state["rng"]
	if kind == "dust_storm":
		var iv: Array = sim.bal["storm"]["interval_days"]
		var g: int = int(Rng.range_float(rng, "hazard", float(iv[0]), float(iv[1])) * float(day_ticks()))
		return g - g % hz()
	var rate: float = rate_per_day(kind)
	if rate <= 0.0:
		return 0
	var u: float = Rng.next_float(rng, "hazard")
	var days: float = clampf(-log(maxf(1e-6, 1.0 - u)) / rate, 0.25, 6.0)
	var t: int = int(days * float(day_ticks()))
	return t - t % hz()

## Events per day of a kind now: base x setting x ramp(day) x colony factor (local kinds).
func rate_per_day(kind: String) -> float:
	var k: Dictionary = kcfg(kind)
	var base: float = float(k.get("per_day", 0.0)) * level()
	var first_day: float = float(first_tick()) / float(day_ticks())
	var day: float = float(sim.state["tick"]) / float(day_ticks())
	var ramp: float = clampf((day - first_day) / maxf(0.1, float(cfg().get("ramp_days", 10.0))), float(cfg().get("ramp_min", 0.3)), 1.0)
	var r: float = base * ramp
	if bool(k.get("local", false)):
		r *= colony_factor()
	return r

## sqrt(structures / 20), 0.5..2.5.
func colony_factor() -> float:
	var n := 0
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "link" and b["kind"] != "special" and (b["state"] == "active" or b["state"] == "broken"):
			n += 1
	return clampf(sqrt(float(n) / float(cfg().get("colony_ref", 20))), float(cfg().get("colony_min", 0.5)), float(cfg().get("colony_max", 2.5)))

func _make_event(kind: String, at: int) -> Dictionary:
	var h: Dictionary = hs()
	var rng: Dictionary = sim.state["rng"]
	var k: Dictionary = kcfg(kind)
	var id: int = int(h["next_id"])
	h["next_id"] = id + 1
	var seen: int = int(h["seen"].get(kind, 0))
	h["seen"][kind] = seen + 1
	var sev: int = _draw_severity(seen == 0)
	var ev := {"id": id, "kind": kind, "at": at, "end": at, "pos": sim.world.center, "radius": 0.0,
		"severity": sev, "detected_tick": -1, "phase": "scheduled", "countered": false, "hits": [], "result": {}}
	match kind:
		"meteor":
			ev["pos"] = _pick_place("meteor")
			var rr: Array = k.get("radius", [4, 12])
			ev["radius"] = snappedf(lerpf(float(rr[0]), float(rr[1]), (float(sev) - 1.0 + Rng.next_float(rng, "hazard")) / 3.0), 0.1)
		"meteor_shower":
			var c: Vector2 = _pick_place("meteor")
			ev["pos"] = c
			var zone: float = float(k.get("zone_m", 60))
			ev["radius"] = zone
			var sn: Array = k.get("strikes", [3, 8])
			var n: int = Rng.range_int(rng, "hazard", int(sn[0]), int(sn[1])) + sev - 1
			var span: int = int(float(k.get("span_s", 60)) * hz())
			var rr: Array = k.get("radius", [4, 8])
			var strikes: Array = []
			for i in n:
				var a: float = Rng.range_float(rng, "hazard", 0.0, TAU)
				var d: float = sqrt(Rng.next_float(rng, "hazard")) * zone
				var t: int = at + int(Rng.next_float(rng, "hazard") * float(span))
				var p: Vector2 = _clamp_map(c + Vector2(cos(a), sin(a)) * d)
				strikes.append({"t": t - t % hz(), "pos": p, "r": snappedf(Rng.range_float(rng, "hazard", float(rr[0]), float(rr[1])), 0.1), "done": false})
			strikes.sort_custom(func(x, y): return int(x["t"]) < int(y["t"]))
			ev["strikes"] = strikes
			ev["end"] = at + span
		"wind_storm", "solar_flare":
			var dr: Array = k.get("duration_s", [120, 300])
			ev["end"] = at + Rng.range_int(rng, "hazard", int(dr[0]), int(dr[1])) * hz()
		"dust_storm":
			var dr2: Array = sim.bal["storm"]["duration_seconds"]
			ev["end"] = at + Rng.range_int(rng, "hazard", int(dr2[0]), int(dr2[1])) * hz()
		"quake":
			ev["pos"] = _pick_place("quake")
			var rq: Array = k.get("radius", [60, 150])
			var z: float = float(sim.world.hazard_at(ev["pos"])["quake"])
			ev["radius"] = snappedf(clampf(Rng.range_float(rng, "hazard", float(rq[0]), float(rq[1])) * (0.7 + 0.3 * z), float(rq[0]), float(rq[1]) * 1.3), 0.1)
			ev["end"] = at + int(float(k.get("shake_s", 6)) * hz())
		"dust_devil":
			var start: Vector2 = _pick_place("wind")
			var flats: Array = sim.world.flats
			if not flats.is_empty() and Rng.next_float(rng, "hazard") < float(k.get("flat_p", 0.6)):
				var f: Dictionary = flats[Rng.range_int(rng, "hazard", 0, flats.size() - 1)]
				var fa: float = Rng.range_float(rng, "hazard", 0.0, TAU)
				start = _clamp_map(Vector2(f["x"], f["y"]) + Vector2(cos(fa), sin(fa)) * float(f["r"]) * 0.5)
			var lr: Array = k.get("length", [80, 200])
			var ang: float = Rng.range_float(rng, "hazard", 0.0, TAU)
			var ln: float = Rng.range_float(rng, "hazard", float(lr[0]), float(lr[1]))
			var endp: Vector2 = _clamp_map(start + Vector2(cos(ang), sin(ang)) * ln)
			ev["pos"] = start
			ev["path"] = [start, endp]
			ev["radius"] = float(k.get("width", 6.0))
			var dd: Array = k.get("duration_s", [60, 120])
			ev["end"] = at + Rng.range_int(rng, "hazard", int(dd[0]), int(dd[1])) * hz()
	if WHOLE_MAP.has(kind):
		_no_overlap(ev)
	_queue_insert(ev)
	return ev

## Whole-map weather never overlaps other whole-map weather: the new event waits for the
## one before it to end (plus a minute).
func _no_overlap(ev: Dictionary) -> void:
	var gap: int = 60 * hz()
	var moved := true
	var guard := 0
	while moved and guard < 20:
		guard += 1
		moved = false
		for other in (hs()["queue"] as Array) + (hs()["active"] as Array):
			if not WHOLE_MAP.has(String(other["kind"])):
				continue
			var len: int = int(ev["end"]) - int(ev["at"])
			if int(ev["at"]) < int(other["end"]) + gap and int(ev["at"]) + len + gap > int(other["at"]):
				ev["at"] = int(other["end"]) + gap
				ev["end"] = int(ev["at"]) + len
				moved = true

func _queue_insert(ev: Dictionary) -> void:
	var q: Array = hs()["queue"]
	var i: int = q.size()
	while i > 0 and (int(q[i - 1]["at"]) > int(ev["at"]) or (int(q[i - 1]["at"]) == int(ev["at"]) and int(q[i - 1]["id"]) > int(ev["id"]))):
		i -= 1
	q.insert(i, ev)

## Severity 1..3: the first event of each kind is 1; later ones rise with the chapter.
func _draw_severity(first: bool) -> int:
	var rng: Dictionary = sim.state["rng"]
	var u: float = Rng.next_float(rng, "hazard")
	var u2: float = Rng.next_float(rng, "hazard")
	if first:
		return 1
	var ch: int = sim.goals.chapter()
	var sev := 1
	if u < 0.2 + 0.15 * float(ch):
		sev += 1
	if u2 < 0.1 * float(ch) - 0.1:
		sev += 1
	return mini(sev, int(cfg()["severity_cap"].get(setting(), 3)))

## A place for a local event: near a structure with probability near_p, else anywhere,
## accepted in proportion to the hazard zone field (rejection sampling on the stream).
func _pick_place(field: String) -> Vector2:
	var rng: Dictionary = sim.state["rng"]
	var anchors: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "link" and b["def"] != "meridian":
			anchors.append(b["pos"])
	var near: bool = not anchors.is_empty() and Rng.next_float(rng, "hazard") < float(cfg().get("near_p", 0.6))
	var near_m: float = float(cfg().get("near_m", 150.0))
	var size: float = float(sim.world.size)
	var p: Vector2 = sim.world.center
	for i in 12:
		if near:
			var base: Vector2 = anchors[Rng.range_int(rng, "hazard", 0, anchors.size() - 1)]
			var a: float = Rng.range_float(rng, "hazard", 0.0, TAU)
			var d: float = sqrt(Rng.next_float(rng, "hazard")) * near_m
			p = base + Vector2(cos(a), sin(a)) * d
		else:
			p = Vector2(Rng.range_float(rng, "hazard", 20.0, size - 20.0), Rng.range_float(rng, "hazard", 20.0, size - 20.0))
		p = _clamp_map(p)
		var z: float = float(sim.world.hazard_at(p)[field])
		if Rng.next_float(rng, "hazard") < z / 2.0:
			break
	return Vector2(snappedf(p.x, 0.1), snappedf(p.y, 0.1))

func _clamp_map(p: Vector2) -> Vector2:
	var m: float = float(sim.world.margin) + 4.0
	var s: float = float(sim.world.size)
	return Vector2(clampf(p.x, m, s - m), clampf(p.y, m, s - m))

# ---------------------------------------------------------------- phases
## Seconds between detection and the event (forecast lead).
func lead_s(ev: Dictionary) -> float:
	var kind: String = ev["kind"]
	var k: Dictionary = kcfg(kind)
	match kind:
		"meteor", "meteor_shower":
			var l: float = float(k.get("lead_s", 45))
			if sim.ship.has_comms():
				l += float(cfg().get("comms_lead_s", 90))
			return l + sim.research.bonus("meteor_lead_s")
		"quake":
			return float(k.get("lead_s", 20)) + sim.research.bonus("quake_lead_s")
		"dust_storm":
			return float(sim.bal["storm"].get("forecast_seconds", 300))
	return float(k.get("lead_s", 60))

## Seconds of the warning phase before the event (never more than the lead).
func warn_s(ev: Dictionary) -> float:
	var kind: String = ev["kind"]
	if kind == "dust_storm":
		return minf(lead_s(ev), float(sim.bal["storm"]["warning_seconds"]))
	if kind == "quake":
		return lead_s(ev)
	return minf(lead_s(ev), float(kcfg(kind).get("warn_s", 30)))

func _phases(tick: int) -> void:
	var h: Dictionary = hs()
	var q: Array = h["queue"]
	var i := 0
	while i < q.size():
		var ev: Dictionary = q[i]
		var at: int = int(ev["at"])
		if tick >= at:
			q.remove_at(i)
			_start(ev)
			continue
		var lead: int = int(lead_s(ev) * float(hz()))
		var warn: int = int(warn_s(ev) * float(hz()))
		if String(ev["phase"]) == "scheduled" and tick >= at - lead:
			ev["phase"] = "forecast"
			ev["detected_tick"] = tick
			ev["countered"] = countered(ev)
			if ev["kind"] != "dust_storm":
				sim.log_event("hazard_detected", "%s forecast in %s%s." % [NAMES[ev["kind"]], Text.n(maxi(0, (at - tick) / hz()), "second"), _where(ev)], [], 1)
		if String(ev["phase"]) == "forecast" and tick >= at - warn:
			ev["phase"] = "warning"
			ev["countered"] = countered(ev)
			if ev["kind"] == "dust_storm":
				sim.log_event("storm_warning", "Dust storm in %s. Solar power will drop to %d%% and walking outside will be slower. Charge the batteries." % [
					Text.n(maxi(0, (at - tick) / hz()), "second"), int(float(sim.bal["storm"]["solar_mult"]) * 100.0)], [], 2)
			else:
				sim.log_event("hazard_warning", "%s in %s%s. %s" % [NAMES[ev["kind"]], Text.n(maxi(0, (at - tick) / hz()), "second"), _where(ev), advice(ev)], [], 2)
		elif String(ev["phase"]) == "forecast" and tick % (10 * hz()) == 0:
			ev["countered"] = countered(ev)
		i += 1

func _where(ev: Dictionary) -> String:
	if WHOLE_MAP.has(String(ev["kind"])):
		return ""
	return " near %s" % _place_name(ev["pos"])

func _place_name(p: Vector2) -> String:
	var best := ""
	var best_d := 1e18
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			continue
		var d: float = (b["pos"] as Vector2).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = String(b["name"])
	if best == "" or sqrt(best_d) > 200.0:
		return "a place %d m %s of the lander" % [int((p - sim.world.center).length()), sim.topo.district_name(p).to_lower()]
	return best

func _start(ev: Dictionary) -> void:
	var h: Dictionary = hs()
	if int(ev["detected_tick"]) < 0:
		ev["detected_tick"] = int(sim.state["tick"])
	ev["phase"] = "active"
	ev["countered"] = countered(ev)
	(h["active"] as Array).append(ev)
	var kind: String = ev["kind"]
	match kind:
		"meteor":
			_strike(ev, ev["pos"], float(ev["radius"]), int(ev["severity"]))
		"quake":
			_quake(ev)
		"dust_storm":
			sim.log_event("storm", "A dust storm is here. It lasts about %s." % Text.n((int(ev["end"]) - int(ev["at"])) / hz(), "second"), [], 2)
		"solar_flare":
			_flare_trip(true)
			sim.log_event("hazard_start", "A solar flare started. Radiation harms colonists outside for %s.%s" % [Text.n((int(ev["end"]) - int(ev["at"])) / hz(), "second"),
				"" if sim.research.bonus("surge_protect") > 0.0 else " Labs, electronics fabs, comms towers and turrets are off until it ends."], [], 3 if _people_outside() > 0 else 2)
		_:
			sim.log_event("hazard_start", "%s started%s." % [NAMES[kind], _where(ev)], [], 2)

func _end(ev: Dictionary) -> void:
	var h: Dictionary = hs()
	ev["phase"] = "done"
	var kind: String = ev["kind"]
	h["done_count"][kind] = int(h["done_count"].get(kind, 0)) + 1
	match kind:
		"dust_storm":
			sim.stat_add("storms", "", 1)
			sim.log_event("storm_end", "The dust storm is over.", [], 1)
		"solar_flare":
			_flare_trip(false)
			sim.log_event("hazard_end", "The solar flare is over.", [], 1)
		"meteor", "quake":
			pass
		_:
			sim.log_event("hazard_end", "The %s is over." % NAMES[kind].to_lower(), [], 1)
	sim.stat_add("hazards", kind, 1)
	if not h.has("done"):
		h["done"] = []
	var keep: Array = h["done"]
	keep.append({"id": ev["id"], "kind": kind, "at": ev["at"], "end": ev["end"], "pos": ev["pos"], "radius": ev["radius"],
		"severity": ev["severity"], "countered": ev["countered"], "result": ev["result"]})
	while keep.size() > 20:
		keep.pop_front()

func _active_second(tick: int) -> void:
	var act: Array = hs()["active"]
	var i := 0
	while i < act.size():
		var ev: Dictionary = act[i]
		match String(ev["kind"]):
			"meteor_shower":
				for st in ev["strikes"]:
					if not bool(st["done"]) and tick >= int(st["t"]):
						st["done"] = true
						_strike(ev, st["pos"], float(st["r"]), int(ev["severity"]))
			"wind_storm":
				_wind_second(ev)
			"solar_flare":
				_flare_second(ev)
			"dust_devil":
				_devil_second(ev, tick)
		if tick >= int(ev["end"]):
			act.remove_at(i)
			_end(ev)
			continue
		i += 1

# ---------------------------------------------------------------- effects
## The environment from the active whole-map events: solar output, walking speed and
## the wind turbine factor. Only one whole-map event is active at a time.
func _env_update() -> void:
	var env: Dictionary = sim.state["env"]
	var solar := 1.0
	var speed := 1.0
	var wind := 1.0
	for ev in hs()["active"]:
		match String(ev["kind"]):
			"dust_storm":
				solar *= float(sim.bal["storm"]["solar_mult"])
				speed = minf(speed, float(sim.bal["storm"]["speed_mult"]))
			"wind_storm":
				var k: Dictionary = kcfg("wind_storm")
				solar *= float(k.get("solar_mult", 0.7))
				speed = minf(speed, float(k.get("speed_mult", 0.6)))
				wind = 1.0 if sim.research.bonus("turbine_feather") > 0.0 else float(k.get("turbine_mult", 1.8))
	env["solar_mult"] = solar
	env["speed_mult"] = speed
	env["wind_mult"] = wind

## Strength of a wind storm: 0.75, 1.0, 1.25 by severity.
func _wind_strength(ev: Dictionary) -> float:
	return 0.5 + 0.25 * float(ev["severity"])

func _wind_second(ev: Dictionary) -> void:
	var k: Dictionary = kcfg("wind_storm")
	var cut: float = sim.research.bonus("storm_damage_cut")
	var feather: bool = sim.research.bonus("turbine_feather") > 0.0
	var per_s: float = float(k.get("damage_per_min", 5.0)) / 60.0 * _wind_strength(ev) * (1.0 - cut)
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "exterior" or b["state"] != "active":
			continue
		var z: float = _wind_zone(b)
		var dmg: float = per_s * z
		if sim.bdef(b["def"]).has("gen_wind") and not feather:
			dmg *= 2.0
		_damage(b, dmg, "wind", false)

func _flare_second(ev: Dictionary) -> void:
	var k: Dictionary = kcfg("solar_flare")
	var per_s: float = float(k.get("rad_per_s", 0.8)) * (0.5 + 0.5 * float(ev["severity"])) * (1.0 - sim.research.bonus("flare_damage_cut")) * float(sim.planet.get("radiation_mult", 1.0))
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["where"] == "out":
			sim.agents._hurt(a, per_s, "radiation")

func _flare_trip(on: bool) -> void:
	var protect: bool = sim.research.bonus("surge_protect") > 0.0
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if TRIP_DEFS.has(String(b["def"])):
			b["trip"] = on and not protect
	sim.util.invalidate()

func _devil_second(ev: Dictionary, tick: int) -> void:
	var path: Array = ev["path"]
	var span: float = maxf(1.0, float(int(ev["end"]) - int(ev["at"])))
	var f: float = clampf(float(tick - int(ev["at"])) / span, 0.0, 1.0)
	var p: Vector2 = (path[0] as Vector2).lerp(path[1], f)
	ev["pos"] = p
	var w: float = float(ev["radius"])
	var k: Dictionary = kcfg("dust_devil")
	var dr: Array = k.get("damage", [5, 15])
	var blds: Dictionary = sim.state["buildings"]
	var hit: Array = ev["hits"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "exterior" or (b["state"] != "active" and b["state"] != "broken"):
			continue
		if (b["pos"] as Vector2).distance_to(p) > w + float(b["radius"]):
			continue
		var seen := false
		for x in hit:
			if int(x["id"]) == int(id):
				seen = true
		if seen:
			continue
		var dmg: float = lerpf(float(dr[0]), float(dr[1]), (float(ev["severity"]) - 1.0) / 2.0)
		var dusted: bool = sim.bdef(b["def"]).has("gen_solar")
		if dusted:
			b["dust"] = true
		hit.append({"id": int(id), "dmg": dmg, "dust": dusted})
		_damage(b, dmg, "dust devil", false)
		if dusted:
			sim.util.invalidate()

## A meteor impact at p with radius r.
func _strike(ev: Dictionary, p: Vector2, r: float, sev: int) -> void:
	var res: Dictionary = ev["result"]
	var turret: int = _covering_turret(p, true)
	if turret != -1:
		var tb: Dictionary = sim.state["buildings"][turret]
		tb["charge"] = maxf(0.0, float(tb.get("charge", 0.0)) - float(sim.bd(tb).get("shot_cost", 50.0)))
		(ev["hits"] as Array).append({"turret": turret, "pos": p})
		res["intercepted"] = int(res.get("intercepted", 0)) + 1
		sim.stat_add("meteors_intercepted", "", 1)
		sim.log_event("hazard_intercepted", "%s shot down a meteor near %s." % [tb["name"], _place_name(p)], [turret], 1)
		return
	res["impacts"] = int(res.get("impacts", 0)) + 1
	var h: Dictionary = hs()
	(h["craters"] as Array).append({"x": p.x, "y": p.y, "r": r, "tick": int(sim.state["tick"])})
	while (h["craters"] as Array).size() > int(cfg().get("craters_max", 80)):
		(h["craters"] as Array).pop_front()
	var mult: float = 0.6 + 0.2 * float(sev)
	var blds: Dictionary = sim.state["buildings"]
	var breaches: Array = []
	for id in blds.keys():
		if not blds.has(id):
			continue
		var b: Dictionary = blds[id]
		if b["kind"] == "special" or (b["state"] != "active" and b["state"] != "broken"):
			continue
		var d: float = 0.0
		if b["kind"] == "link":
			d = maxf(0.0, Geometry2D.get_closest_point_to_segment(p, b["p0"], b["p1"]).distance_to(p) - (1.2 if b["def"] == "corridor" else 0.2))
		else:
			d = maxf(0.0, (b["pos"] as Vector2).distance_to(p) - float(b["radius"]))
		if d > r:
			continue
		var dmg: float = (40.0 + 60.0 * (1.0 - d / maxf(0.1, r))) * mult
		var breach: bool = b["kind"] == "room" or b["def"] == "corridor"
		(ev["hits"] as Array).append({"id": int(id), "dmg": snappedf(dmg, 0.1), "breach": breach})
		if b["def"] == "cable":
			continue
		if breach:
			_breach(b)
			breaches.append(int(id))
		_damage(b, dmg, "a meteor strike", true)
	var hurt := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["where"] != "out":
			continue
		var da: float = (a["pos"] as Vector2).distance_to(p)
		if da <= r + 2.0:
			hurt += 1
			sim.agents._hurt(a, (30.0 + 50.0 * (1.0 - da / (r + 2.0))) * mult, "a meteor strike")
	_fragment_site(ev, p, sev)
	var text: String = "A meteor hit near %s." % _place_name(p)
	if not breaches.is_empty():
		text += " %s breached: air leaks." % Text.n(breaches.size(), "structure")
	if hurt > 0:
		text += " %s outside %s hurt." % [Text.n(hurt, "colonist"), Text.be(hurt)]
	sim.log_event("hazard_impact", text, breaches, 3 if hurt > 0 or not breaches.is_empty() else 1)

func _quake(ev: Dictionary) -> void:
	var k: Dictionary = kcfg("quake")
	var p: Vector2 = ev["pos"]
	var r: float = float(ev["radius"])
	var cut: float = sim.research.bonus("quake_damage_cut")
	var dr: Array = k.get("damage", [10, 40])
	var sevm: float = 0.6 + 0.2 * float(ev["severity"])
	var blds: Dictionary = sim.state["buildings"]
	var cracks: Array = []
	for id in blds.keys():
		if not blds.has(id):
			continue
		var b: Dictionary = blds[id]
		if b["kind"] == "special" or (b["state"] != "active" and b["state"] != "broken"):
			continue
		var d: float = (b["pos"] as Vector2).distance_to(p)
		if d > r:
			continue
		var f: float = 1.0 - d / r
		var dmg: float = lerpf(float(dr[0]), float(dr[1]), f) * sevm * (1.0 - cut)
		if b["def"] == "corridor":
			var chance: float = float(k.get("crack_p", 0.2)) * (0.5 + f) * (1.0 - cut) * sevm
			if cracks.size() < int(k.get("max_cracks", 3)) and Rng.hash2(int(ev["id"]), int(id), int(sim.state["seed"]) ^ 0x7A11) < chance:
				_breach(b)
				cracks.append(int(id))
			continue
		if b["kind"] == "link":
			continue
		(ev["hits"] as Array).append({"id": int(id), "dmg": snappedf(dmg, 0.1)})
		_damage(b, dmg, "a quake", true)
	ev["result"]["cracks"] = cracks.size()
	var text: String = "A quake shook the ground near %s." % _place_name(p)
	if not cracks.is_empty():
		text += " %s cracked: air leaks." % Text.n(cracks.size(), "corridor")
	sim.log_event("hazard_impact", text, cracks, 2 if cracks.is_empty() else 3)

func _damage(b: Dictionary, dmg: float, cause: String, announce: bool) -> void:
	if dmg <= 0.0 or b["kind"] == "link":
		return
	b["health"] = maxf(0.0, float(b["health"]) - dmg)
	b["out_rate"] = float(sim.bal["degraded_output"]) if float(b["health"]) < float(sim.bal["health_degraded"]) else 1.0
	if float(b["health"]) <= 0.0 and b["state"] == "active":
		b["state"] = "broken"
		b["powered"] = false
		sim.topo.mark_dirty()
		sim.log_event("broken", "%s broke: %s. A technician needs one spare part to repair it." % [b["name"], cause], [b["id"]], 2)

func _breach(b: Dictionary) -> void:
	if bool(b.get("breach", false)):
		return
	b["breach"] = true
	if b["kind"] == "link":
		var br: Array = hs()["breached"]
		if not br.has(int(b["id"])):
			br.append(int(b["id"]))
	sim.util.invalidate()
	sim.log_event("breach", "Hull breach in %s. Air leaks until a technician seals it." % b["name"], [b["id"]], 2)

## A technician sealed a hull breach.
func seal(b: Dictionary) -> void:
	b["breach"] = false
	(hs()["breached"] as Array).erase(int(b["id"]))
	sim.util.invalidate()
	sim.stat_add("breaches_sealed", "", 1)
	sim.log_event("breach_sealed", "The hull breach in %s is sealed." % b["name"], [b["id"]], 1)

## A scientist surveyed a fragment site: research points, some more exotic crystal and
## ore on the pile, and sometimes an exotic research pack.
func on_surveyed(sid: int) -> void:
	var site: Dictionary = hs()["sites"].get(sid, {})
	if site.is_empty() or bool(site["surveyed"]):
		return
	site["surveyed"] = true
	var sc: Dictionary = cfg()["survey"]
	sim.research.add_rp(float(sc.get("rp", 40)))
	var pile: int = sid
	if sim.inv.get_inv(pile).is_empty():
		pile = sim.inv.create_inv("g", 0, "pile", 100000, site["pos"])
		sim.inv.get_inv(pile)["fragment"] = true
	if int(sc.get("exotic", 1)) > 0:
		sim.inv.add_new_forced(pile, "exotic", int(sc.get("exotic", 1)), "sample")
	if int(sc.get("ore", 2)) > 0:
		sim.inv.add_new_forced(pile, "ore", int(sc.get("ore", 2)), "sample")
	var got := ""
	if bool(site.get("pack", false)):
		sim.inv.add_new_forced(pile, "pack_exotic", 1, "sample")
		got = " It held an exotic research pack."
	sim.stat_add("surveys", "", 1)
	sim.log_event("survey", "A meteor fragment site was surveyed: %d research points and samples.%s" % [int(sc.get("rp", 40)), got], [], 1)

## Breached corridors per atmosphere component (utilities adds their air loss).
func link_breaches(comp: int) -> int:
	var n := 0
	var blds: Dictionary = sim.state["buildings"]
	for lid in hs().get("breached", []):
		var l: Dictionary = blds.get(lid, {})
		if l.is_empty() or not bool(l.get("breach", false)):
			continue
		if int(sim.topo.atmo_comp.get(int(l["a"]), -1)) == comp:
			n += 1
	return n

## A crater with meteor fragments: a ground pile of ore and exotic crystal, and a site a
## scientist can survey (field samples, V3_DESIGN section 5.2).
func _fragment_site(ev: Dictionary, p: Vector2, sev: int) -> void:
	var fc: Dictionary = cfg().get("fragment", {})
	var s: int = int(sim.state["seed"])
	var n_id: int = int(hs()["next_id"])
	var hsh: float = Rng.hash2(int(ev["id"]), int((ev["hits"] as Array).size()) + n_id, s ^ 0x3F1)
	var ore_r: Array = fc.get("ore", [2, 6])
	var ex_r: Array = fc.get("exotic", [1, 2])
	var ore: int = int(ore_r[0]) + int(hsh * float(int(ore_r[1]) - int(ore_r[0]) + 1)) + sev - 1
	var ex: int = int(ex_r[0]) + int(Rng.hash2(int(ev["id"]), 7, s ^ 0x3F2) * float(int(ex_r[1]) - int(ex_r[0]) + 1))
	var q = sim.nav.nearest_walkable(p, 10)
	var at: Vector2 = q if q != null else p
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, at)
	var inv: Dictionary = sim.inv.get_inv(pile)
	inv["fragment"] = true
	if ore > 0:
		sim.inv.add_new_forced(pile, "ore", ore, "meteor")
	if ex > 0:
		sim.inv.add_new_forced(pile, "exotic", ex, "meteor")
	var pack: bool = Rng.hash2(int(ev["id"]), 11, s ^ 0x3F3) < float(fc.get("pack_p", 0.25)) * (0.5 + 0.5 * float(sev))
	hs()["sites"][pile] = {"id": pile, "pos": at, "ev": int(ev["id"]), "surveyed": false, "pack": pack, "tick": int(sim.state["tick"]), "order": false}

# ---------------------------------------------------------------- turrets
## The turret that covers p and can shoot now (nearest first), or -1.
func _covering_turret(p: Vector2, need_charge: bool) -> int:
	var best := -1
	var best_d := 1e18
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if not bool(sim.bdef(b["def"]).get("turret", false)) or b["state"] != "active":
			continue
		if not bool(b["powered"]) or bool(b.get("trip", false)) or not bool(b["enabled"]):
			continue
		var d: float = (b["pos"] as Vector2).distance_to(p)
		if d > turret_range(b):
			continue
		if need_charge and float(b.get("charge", 0.0)) < float(sim.bd(b).get("shot_cost", 50.0)):
			continue
		if d < best_d:
			best_d = d
			best = id
	return best

func turret_range(b: Dictionary) -> float:
	return float(sim.bd(b).get("turret_range", 70.0)) + sim.research.bonus("turret_range_add")

func _turrets_second() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var day: float = float(sim.bal["day_length"])
	var mult: float = 1.0 + sim.research.bonus("turret_charge_mult")
	for id in blds:
		var b: Dictionary = blds[id]
		var d: Dictionary = sim.bdef(b["def"])
		if not bool(d.get("turret", false)) or b["state"] != "active":
			continue
		if not b.has("charge"):
			b["charge"] = 0.0
		if bool(b["powered"]) and not bool(b.get("trip", false)) and bool(b["enabled"]):
			b["charge"] = minf(float(d.get("charge_cap", 100.0)), float(b["charge"]) + float(d.get("charge_per_day", 240.0)) / day * mult)

# ---------------------------------------------------------------- countered and advice
## True when the colony's defences cover the event now (V3_DESIGN section 4.3).
func countered(ev: Dictionary) -> bool:
	match String(ev["kind"]):
		"meteor":
			return _covering_turret(ev["pos"], true) != -1
		"meteor_shower":
			var t: int = _covering_turret(ev["pos"], true)
			if t == -1:
				return false
			var b: Dictionary = sim.state["buildings"][t]
			return float(b.get("charge", 0.0)) >= float(sim.bd(b).get("shot_cost", 50.0)) * float((ev.get("strikes", []) as Array).size())
		"wind_storm":
			return sim.research.bonus("storm_damage_cut") > 0.0
		"quake":
			return sim.research.bonus("quake_damage_cut") > 0.0
		"solar_flare":
			return sheltered() and (sim.research.bonus("surge_protect") > 0.0 or not _has_trippable())
		"dust_storm":
			var stored := 0.0
			var cap := 0.0
			for comp in sim.util.power_stats:
				stored += float(sim.util.power_stats[comp]["stored"])
				cap += float(sim.util.power_stats[comp]["cap"])
			return cap > 0.0 and stored >= cap * 0.5
		"dust_devil":
			var path: Array = ev.get("path", [])
			if path.size() < 2:
				return true
			var blds: Dictionary = sim.state["buildings"]
			for id in blds:
				var b: Dictionary = blds[id]
				if b["state"] == "active" and sim.bdef(b["def"]).has("gen_solar"):
					if Geometry2D.get_closest_point_to_segment(b["pos"], path[0], path[1]).distance_to(b["pos"]) <= float(ev["radius"]) + float(b["radius"]):
						return false
			return true
	return false

func _has_trippable() -> bool:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		if TRIP_DEFS.has(String(blds[id]["def"])) and blds[id]["state"] == "active":
			return true
	return false

## One line of plain advice for an event.
func advice(ev: Dictionary) -> String:
	var c: bool = bool(ev.get("countered", false))
	match String(ev["kind"]):
		"meteor":
			return "A turret covers this place." if c else "Keep people away from the target. A meteor defense turret shoots it down."
		"meteor_shower":
			return "Turrets cover this place." if c else "Keep people inside. Turrets shoot down strikes while they have charge."
		"wind_storm":
			return "Storm anchoring protects the exterior structures." if c else "Exterior structures take damage. Research Storm Anchoring."
		"dust_storm":
			return "Solar power drops. The batteries are charged." if c else "Solar power drops. Charge the batteries."
		"quake":
			return "Seismic dampers cut the damage." if c else "Corridors near it can crack. Research Seismic Dampers."
		"solar_flare":
			if c:
				return "Everyone stays inside."
			return "Order Shelter: everyone goes inside." + ("" if sim.research.bonus("surge_protect") > 0.0 else " Research Surge Protection to keep labs and turrets on.")
		"dust_devil":
			return "No solar panel is on its path." if c else "Solar panels on its path lose half their power until a colonist cleans them."
	return ""

# ---------------------------------------------------------------- wear and breakdowns
## True for a structure that wears and can break down: machines, generators with moving
## parts, labs and turrets.
var _machine_def := {}     # def id -> bool (derived cache)
var _zone := {}            # building id -> wind zone at its place (derived cache)

func is_machine(b: Dictionary) -> bool:
	var got = _machine_def.get(b["def"])
	if got != null:
		return got
	var d: Dictionary = sim.bdef(b["def"])
	var m: bool = d["kind"] != "link" and d["kind"] != "special" and (d.has("recipe") or bool(d.get("automatic", false)) or bool(d.get("research_lab", false)) or d.has("gen_wind") or d.has("gen_const") or bool(d.get("turret", false)))
	_machine_def[b["def"]] = m
	return m

func _wind_zone(b: Dictionary) -> float:
	var got = _zone.get(int(b["id"]))
	if got == null:
		got = float(sim.world.hazard_at(b["pos"])["wind"])
		_zone[int(b["id"])] = got
	return got

## The item a fault needs: mechanical -> spare parts, electrical -> electronics,
## seal -> polymer.
func fault_item(fault: String) -> String:
	return String(cfg()["wear"]["faults"].get(fault, "spare_parts"))

## The wear record of a machine (made on first use, with its failure threshold).
func wear_of(bid: int) -> Dictionary:
	var w: Dictionary = hs()["wear"]
	if not w.has(bid):
		w[bid] = {"w": 0.0, "n": 0, "fail_at": 0.0, "fault": "", "broken": false}
		_draw_threshold(bid)
	return w[bid]

## A new failure threshold and fault for a machine: a hash of its id and repair count.
func _draw_threshold(bid: int) -> void:
	var rec: Dictionary = hs()["wear"][bid]
	var s: int = int(sim.state["seed"]) ^ 0x5EA7
	var n: int = int(rec["n"])
	var fr: Array = cfg()["wear"].get("fail_at", [60, 100])
	rec["fail_at"] = snappedf(lerpf(float(fr[0]), float(fr[1]), Rng.hash2(bid, n, s)), 0.1)
	var u: float = Rng.hash2(bid, n + 1000, s)
	var fault := "mechanical"
	# An electrical fault needs electronics: only once the colony can make them.
	if u >= 0.55 and u < 0.8 and sim.research.is_done("ind_2"):
		fault = "electrical"
	elif u >= 0.8:
		fault = "seal"
	rec["fault"] = fault

## Wear per second of a machine now (0 when it does not run).
func wear_rate(b: Dictionary) -> float:
	if b["state"] != "active" or not bool(b["enabled"]) or (not bool(b["powered"]) and float(sim.bdef(b["def"]).get("power", 0.0)) > 0.0):
		return 0.0
	var wc: Dictionary = cfg()["wear"]
	var r: float = float(wc.get("per_day", 7.0)) / float(sim.bal["day_length"])
	r *= float(sim.bd(b).get("wear_mult", 1.0)) * sim.difficulty("wear_mult") * (1.0 - sim.research.bonus("wear_cut"))
	if b["kind"] == "exterior":
		var z: float = _wind_zone(b)
		r *= 0.75 + 0.25 * z
		for ev in hs()["active"]:
			if ev["kind"] == "wind_storm":
				r *= 1.0 + float(kcfg("wind_storm").get("wear_mult", 2.0)) * _wind_strength(ev) * z * (1.0 - sim.research.bonus("storm_damage_cut"))
	return r

## Wear fraction at which a machine shows in the forecast and gets maintenance.
func risk_frac() -> float:
	var base: float = float(cfg()["wear"].get("risk_frac", 0.75))
	var lead: float = sim.research.bonus("forecast_lead")
	return clampf(1.0 - (1.0 - base) * (1.0 + lead), 0.3, 0.95)

func _wear_second() -> void:
	if level() <= 0.0 or not bool(cfg()["wear"].get("enabled", true)):
		return
	if int(sim.state["tick"]) < int(float(cfg()["wear"].get("start_day", 1.0)) * float(day_ticks())):
		return
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or not is_machine(b):
			continue
		var rate: float = wear_rate(b)
		if rate <= 0.0:
			continue
		var rec: Dictionary = wear_of(int(id))
		rec["w"] = float(rec["w"]) + rate
		if float(rec["w"]) >= float(rec["fail_at"]):
			rec["broken"] = true
			b["state"] = "broken"
			b["powered"] = false
			b["block"] = "fault"
			sim.topo.mark_dirty()
			sim.stat_add("breakdowns", "", 1)
			var item: String = fault_item(String(rec["fault"]))
			sim.log_event("fault", "%s broke down: %s fault. A technician repairs it with %s." % [b["name"], rec["fault"], sim.items.amount(item, 1)], [int(id)], 2)

## Called when a technician repaired a machine. A wear breakdown ends: the wear is 0 and
## a new threshold is drawn.
func on_repaired(b: Dictionary) -> void:
	var w: Dictionary = hs()["wear"]
	if not w.has(int(b["id"])):
		return
	var rec: Dictionary = w[int(b["id"])]
	if bool(rec["broken"]):
		_reset_wear(int(b["id"]))

func _reset_wear(bid: int) -> void:
	var rec: Dictionary = wear_of(bid)
	rec["w"] = 0.0
	rec["n"] = int(rec["n"]) + 1
	rec["broken"] = false
	_draw_threshold(bid)
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if not b.is_empty():
		b.erase("maint_first")

## Maintenance done: wear 0, a new threshold.
func on_maintained(b: Dictionary) -> void:
	_reset_wear(int(b["id"]))
	sim.stat_add("maintenance", "", 1)
	sim.log_event("maintained", "%s had its maintenance. Its wear is 0." % b["name"], [b["id"]], 0)

## The item and quantity a repair of this structure uses now.
func repair_item(b: Dictionary) -> String:
	var rec: Dictionary = hs()["wear"].get(int(b["id"]), {})
	if b["state"] == "broken" and bool(rec.get("broken", false)):
		return fault_item(String(rec["fault"]))
	return "spare_parts"

## True when a machine wants maintenance now (at risk, or ordered first).
func wants_maintenance(b: Dictionary) -> bool:
	if b["state"] != "active" or not is_machine(b):
		return false
	var rec: Dictionary = hs()["wear"].get(int(b["id"]), {})
	if rec.is_empty():
		return false
	if bool(b.get("maint_first", false)):
		return float(rec["w"]) > 0.0
	return float(rec["w"]) >= float(rec["fail_at"]) * risk_frac()

## Machines above the forecast share of their threshold, soonest failure first:
## [{id, name, wear, fail_at, eta_s, fault, item, first}] (wear and fail_at in 0..100).
func at_risk() -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	var w: Dictionary = hs()["wear"]
	var frac: float = risk_frac()
	for id in w:
		var b: Dictionary = blds.get(id, {})
		if b.is_empty() or b["state"] != "active":
			continue
		var rec: Dictionary = w[id]
		if float(rec["w"]) < float(rec["fail_at"]) * frac and not bool(b.get("maint_first", false)):
			continue
		var rate: float = wear_rate(b)
		var eta: float = (float(rec["fail_at"]) - float(rec["w"])) / rate if rate > 0.0 else -1.0
		out.append({"id": int(id), "name": b["name"], "wear": float(rec["w"]), "fail_at": float(rec["fail_at"]),
			"eta_s": eta, "fault": rec["fault"], "item": fault_item(String(rec["fault"])), "first": bool(b.get("maint_first", false))})
	out.sort_custom(func(x, y):
		var ex: float = 1e12 if float(x["eta_s"]) < 0.0 else float(x["eta_s"])
		var ey: float = 1e12 if float(y["eta_s"]) < 0.0 else float(y["eta_s"])
		return ex < ey if ex != ey else int(x["id"]) < int(y["id"]))
	return out

# ---------------------------------------------------------------- shelter
func sheltered() -> bool:
	return bool(hs().get("shelter", false))

## The shelter order ends by itself when no flare or shower is forecast or active.
func _shelter_second() -> void:
	var h: Dictionary = hs()
	if not bool(h.get("shelter", false)):
		return
	for ev in (h["queue"] as Array) + (h["active"] as Array):
		if (ev["kind"] == "solar_flare" or ev["kind"] == "meteor_shower") and String(ev["phase"]) != "scheduled":
			return
	h["shelter"] = false
	sim.log_event("shelter", "The shelter order ended. Work outside starts again.", [], 1)

## True while a solar flare is active.
func flare_active() -> bool:
	for ev in hs()["active"]:
		if ev["kind"] == "solar_flare":
			return true
	return false

## Health under which a colonist outside goes in by itself during a flare.
func retreat_health() -> float:
	return float(kcfg("solar_flare").get("retreat_health", 70))

## Colonists outside (for alerts and log severity; visitors are not counted, V3.1).
func _people_outside() -> int:
	var n := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["where"] == "out" and a["kind"] != "visitor":
			n += 1
	return n

# ---------------------------------------------------------------- commands
## "shelter" {on}: everyone goes inside and no work outside starts.
func cmd_shelter(on: bool) -> Dictionary:
	hs()["shelter"] = on
	sim.log_event("shelter", "Shelter order: everyone goes inside." if on else "The shelter order ended.", [], 1)
	return {"ok": true, "code": "ok"}

## "maintain" {id}: this machine gets its maintenance first.
func cmd_maintain(bid: int) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty() or not is_machine(b):
		return {"ok": false, "code": "invalid"}
	if b["state"] != "active":
		return {"ok": false, "code": "not_active"}
	wear_of(bid)
	b["maint_first"] = true
	return {"ok": true, "code": "ok"}

## "survey_site" {id}: a scientist surveys this fragment site first.
func cmd_survey(site_id: int) -> Dictionary:
	var s: Dictionary = hs()["sites"].get(site_id, {})
	if s.is_empty() or bool(s["surveyed"]):
		return {"ok": false, "code": "invalid"}
	s["order"] = true
	return {"ok": true, "code": "ok"}

## "hazard_now" {kind, x?, y?, severity?, in?}: tests and screenshots only, and only when
## state.options.debug is true. It is a recorded command, so a replay stays exact.
func cmd_hazard_now(p: Dictionary) -> Dictionary:
	if not bool(sim.state.get("options", {}).get("debug", false)):
		return {"ok": false, "code": "debug_only"}
	var kind: String = String(p.get("kind", ""))
	if not KINDS.has(kind):
		return {"ok": false, "code": "invalid"}
	var h: Dictionary = hs()
	var tick: int = int(sim.state["tick"])
	var at: int = tick + int(maxf(1.0, float(p.get("in", 1.0))) * float(hz()))
	at += (hz() - at % hz()) % hz()
	var sev: int = clampi(int(p.get("severity", 1)), 1, 3)
	var pos: Vector2 = sim.world.center + Vector2(40, 0)
	if typeof(p.get("pos")) == TYPE_VECTOR2:
		pos = _clamp_map(p["pos"])
	elif p.has("x") and p.has("y"):
		pos = _clamp_map(Vector2(float(p["x"]), float(p["y"])))
	var id: int = int(h["next_id"])
	h["next_id"] = id + 1
	var k: Dictionary = kcfg(kind)
	var ev := {"id": id, "kind": kind, "at": at, "end": at, "pos": pos, "radius": 0.0, "severity": sev,
		"detected_tick": tick, "phase": "warning", "countered": false, "hits": [], "result": {}, "debug": true}
	match kind:
		"meteor":
			ev["radius"] = float(p.get("radius", 4.0 + 3.0 * float(sev - 1)))
		"meteor_shower":
			ev["radius"] = float(k.get("zone_m", 60))
			var strikes: Array = []
			var n: int = 3 + sev
			for i in n:
				var a: float = TAU * float(i) / float(n)
				var sp: Vector2 = _clamp_map(pos + Vector2(cos(a), sin(a)) * float(ev["radius"]) * 0.5)
				var t: int = at + i * 8 * hz()
				strikes.append({"t": t, "pos": sp, "r": 5.0, "done": false})
			ev["strikes"] = strikes
			ev["end"] = at + n * 8 * hz()
		"wind_storm", "solar_flare":
			ev["end"] = at + int(float(p.get("duration", 120.0)) * float(hz()))
		"dust_storm":
			ev["end"] = at + int(float(p.get("duration", 120.0)) * float(hz()))
		"quake":
			ev["radius"] = float(p.get("radius", 80.0))
			ev["end"] = at + int(float(k.get("shake_s", 6)) * hz())
		"dust_devil":
			var endp: Vector2 = _clamp_map(pos + Vector2(float(p.get("length", 120.0)), 0.0).rotated(float(p.get("dir", 0.0))))
			ev["path"] = [pos, endp]
			ev["radius"] = float(k.get("width", 6.0))
			ev["end"] = at + int(float(p.get("duration", 60.0)) * float(hz()))
	ev["countered"] = countered(ev)
	_queue_insert(ev)
	sim.log_event("hazard_warning", "Test event: %s in %s%s." % [NAMES[kind], Text.n(maxi(1, (at - tick) / hz()), "second"), _where(ev)], [], 2)
	return {"ok": true, "code": "ok", "id": id}

# ---------------------------------------------------------------- the v2 storm mirror
## state.events.storm as version 2 kept it: {phase, at, end, count, scheduled}, for the
## old read API (sim.events) and views that read it directly.
func _mirror_storm() -> void:
	var ev_state: Dictionary = sim.state["events"]
	var found := {}
	for ev in hs()["active"]:
		if ev["kind"] == "dust_storm":
			found = ev
	if found.is_empty():
		for ev in hs()["queue"]:
			if ev["kind"] == "dust_storm":
				found = ev
				break
	var count: int = int(hs()["done_count"].get("dust_storm", 0))
	if found.is_empty():
		if ev_state.has("storm"):
			var st: Dictionary = ev_state["storm"]
			st["phase"] = "none"
			st["count"] = count
			st["scheduled"] = false
		return
	var phase := "none"
	match String(found["phase"]):
		"warning": phase = "warning"
		"active": phase = "active"
	ev_state["storm"] = {"phase": phase, "at": int(found["at"]), "end": int(found["end"]), "count": count, "scheduled": true}

# ---------------------------------------------------------------- read API (V3_DESIGN 4.4)
func _view(ev: Dictionary) -> Dictionary:
	var tick: int = int(sim.state["tick"])
	var out := {"id": int(ev["id"]), "kind": ev["kind"], "name": NAMES.get(ev["kind"], ev["kind"]),
		"eta_s": maxf(0.0, float(int(ev["at"]) - tick) / float(hz())), "end_s": maxf(0.0, float(int(ev["end"]) - tick) / float(hz())),
		"pos": ev["pos"], "radius": float(ev["radius"]), "severity": int(ev["severity"]), "countered": bool(ev["countered"]),
		"advice": advice(ev), "phase": ev["phase"], "at": int(ev["at"]), "end": int(ev["end"]),
		"whole_map": WHOLE_MAP.has(String(ev["kind"]))}
	if ev.has("path"):
		out["path"] = ev["path"]
	if ev.has("strikes"):
		var st: Array = []
		for s in ev["strikes"]:
			st.append({"eta_s": maxf(0.0, float(int(s["t"]) - tick) / float(hz())), "pos": s["pos"], "r": float(s["r"]), "done": bool(s["done"])})
		out["strikes"] = st
	return out

## Detected events not yet started, soonest first (scheduled ones stay hidden).
func forecast() -> Array:
	var out: Array = []
	for ev in hs()["queue"]:
		if String(ev["phase"]) != "scheduled":
			out.append(_view(ev))
	return out

## Events happening now.
func active() -> Array:
	var out: Array = []
	for ev in hs()["active"]:
		out.append(_view(ev))
	return out

## Every queued event, scheduled ones included (tests and debug only; the UI must not
## show these).
func queue_all() -> Array:
	var out: Array = []
	for ev in hs()["queue"]:
		out.append(_view(ev))
	return out

func zone_at(pos: Vector2) -> Dictionary:
	return sim.world.hazard_at(pos)

## Everything about one structure: wear, fault, breach, dust, flare trip, turret charge.
func info(bid: int) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty():
		return {}
	var out := {"id": bid, "machine": is_machine(b), "breach": bool(b.get("breach", false)), "dust": bool(b.get("dust", false)),
		"trip": bool(b.get("trip", false)), "health": float(b["health"])}
	var rec: Dictionary = hs()["wear"].get(bid, {})
	if not rec.is_empty():
		var rate: float = wear_rate(b)
		out["wear"] = float(rec["w"])
		out["fail_at"] = float(rec["fail_at"])
		out["fault"] = rec["fault"]
		out["item"] = fault_item(String(rec["fault"]))
		out["eta_s"] = (float(rec["fail_at"]) - float(rec["w"])) / rate if rate > 0.0 else -1.0
		out["at_risk"] = float(rec["w"]) >= float(rec["fail_at"]) * risk_frac()
		out["broken_by_wear"] = bool(rec["broken"])
		out["maint_first"] = bool(b.get("maint_first", false))
	if bool(sim.bdef(b["def"]).get("turret", false)):
		out["charge"] = float(b.get("charge", 0.0))
		out["charge_cap"] = float(sim.bd(b).get("charge_cap", 100.0))
		out["range"] = turret_range(b)
		out["shot_cost"] = float(sim.bd(b).get("shot_cost", 50.0))
	return out

## The full record of a queued, active or recent event ({} when unknown).
func event(id: int) -> Dictionary:
	for list in [hs()["queue"], hs()["active"], hs().get("done", [])]:
		for ev in list:
			if int(ev["id"]) == id:
				return ev
	return {}

## Meteor fragment sites: [{id (pile inventory), pos, surveyed, units {item: n}}].
func sites() -> Array:
	var out: Array = []
	var sites_d: Dictionary = hs()["sites"]
	for id in sites_d:
		var s: Dictionary = sites_d[id]
		out.append({"id": int(id), "pos": s["pos"], "surveyed": bool(s["surveyed"]), "units": (sim.inv.get_inv(int(id)).get("items", {}) as Dictionary).duplicate()})
	return out

## Craters left by meteors: [{x, y, r, tick}] (the view draws decals).
func craters() -> Array:
	return hs()["craters"]
