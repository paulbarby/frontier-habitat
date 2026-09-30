extends RefCounted
## Fights, security officers, arrests, the jail and riots (docs/V5_DESIGN.md sections 6.4, 6.5).
## Numbers: content/society.json "security".
##
## Stored (schema 6):
##   state.v5.fights {id: {id, fighters [ids], bld, pos, start, until, officer, cause, base, injured}}
##   state.v5.fight_seq
##   on the agent: v5_hold ("fight" | "cuffed" | "respond" | "escort"), v5_fight (fight id),
##   v5_escort (the prisoner an officer takes to jail), cell_b (the jail a prisoner is held in).
## A fight starts from an argument (enemies, people with a very bad attitude, hot heads in a bad
## mood) or in a riot. The two stop everything and fight in place; friends may join. The nearest free
## officer of the base walks there; on arrival the fight ends and the one with the worse attitude is
## arrested and walked to a free cell (the officer walks along). Without an officer the fight ends by
## itself after fight_s. A prisoner stays in the jail: sleeps and drinks there and gets prison
## rations (a dish from a store of the base). The jail mod ends -> the prisoner is released.

const Rng = preload("res://sim/rng.gd")

var sim
var _patrol_sec := -1
var _patrol_rooms := {}       # base -> [room ids] for patrols (derived, per game second)

func _init(s) -> void:
	sim = s

func reset() -> void:
	_patrol_sec = -1
	_patrol_rooms = {}

func cfg() -> Dictionary:
	return sim.content["society"]["security"]

func _h(x: int, y: int) -> float:
	return Rng.hash2(x, y, int(sim.state.get("seed", 1)) ^ 0x5EC0)

func _hz() -> int:
	return int(sim.bal["tick_hz"])

func _w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("fights"):
		v["fights"] = {}
	if not v.has("fight_seq"):
		v["fight_seq"] = 0
	return v

func fights_r() -> Dictionary:
	return sim.state.get("v5", {}).get("fights", {})

func _base_of(a: Dictionary) -> int:
	return sim.bases.home_of(a) if sim.bases.count() > 0 else -1

func _adult_colonist(a: Dictionary) -> bool:
	return not a.is_empty() and a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child"

## Can this person start or join a fight now?
func can_fight(a: Dictionary) -> bool:
	return _adult_colonist(a) and a["where"] == "in" and not a.has("v5_hold") and not a.has("jailed") and not bool(a.get("sleeping", false)) \
		and String(a.get("plan_kind", "")) != "safety" and not a.has("lift") and float(a["health"]) > float(cfg()["down_health"])

# ---------------------------------------------------------------- queries
## Every fight going on now: [{id, fighters [ids], bld, pos, start, until, officer, cause}].
func fights() -> Array:
	var out: Array = []
	var f: Dictionary = fights_r()
	var ids: Array = f.keys()
	ids.sort()
	for k in ids:
		out.append(f[k].duplicate())
	return out

## Officers (role security) living at a base: [ids].
func officers(base_id: int) -> Array:
	var out: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if _adult_colonist(a) and String(a["role"]) == "security" and (base_id == -1 or _base_of(a) == base_id):
			out.append(int(aid))
	return out

## {officers, wanted (1 per officer_ratio people), prisoners, cells, fights} for a base (-1: all).
func info(base_id: int = -1) -> Dictionary:
	var pop := 0
	var prisoners := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if _adult_colonist(a) and (base_id == -1 or _base_of(a) == base_id):
			pop += 1
			if int(a.get("cell_b", -1)) != -1:
				prisoners += 1
	var cells := 0
	for j in jails(base_id):
		cells += int(sim.bd(sim.state["buildings"][j]).get("cells", 0))
	var nf := 0
	for k in fights_r():
		if base_id == -1 or int(fights_r()[k].get("base", -1)) == base_id:
			nf += 1
	return {"officers": officers(base_id).size(), "wanted": int(ceil(float(pop) / float(cfg()["officer_ratio"]))), "prisoners": prisoners, "cells": cells, "fights": nf}

## Active jails of a base, by id.
func jails(base_id: int) -> Array:
	var out: Array = []
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["def"]) == "jail" and b["state"] == "active" and not bool(b["demolish"]) and (base_id == -1 or sim.bases.count() == 0 or sim.bases.base_of(int(id)) == base_id):
			out.append(int(id))
	out.sort()
	return out

func prisoners_in(jail_id: int) -> Array:
	var out: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and int(a.get("cell_b", -1)) == jail_id:
			out.append(int(aid))
	out.sort()
	return out

## A jail of the person's base with a free cell (-1: none).
func jail_for(a: Dictionary) -> int:
	for j in jails(_base_of(a)):
		if prisoners_in(j).size() < int(sim.bd(sim.state["buildings"][j]).get("cells", 0)):
			return j
	return -1

func has_office(base_id: int) -> bool:
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["def"]) == "security_office" and b["state"] == "active" and (base_id == -1 or sim.bases.count() == 0 or sim.bases.base_of(int(id)) == base_id):
			return true
	return false

# ---------------------------------------------------------------- the second
## Once a game second (sim.step phase 9): fights move on, new fights start, riots do damage,
## prisoners whose time is up are released.
func tick_second() -> void:
	var now: int = int(sim.state["tick"])
	var f: Dictionary = fights_r()
	if not f.is_empty():
		var ids: Array = f.keys()
		ids.sort()
		for k in ids:
			if f.has(k):
				_fight_second(f[k], now)
	_releases()
	_talk_fights(now)
	if sim.get("unrest") != null:
		for b in sim.unrest._bases():
			if String(sim.unrest.rec_of(int(b)).get("stage", "calm")) == "riot":
				_riot_second(int(b), now)

func _releases() -> void:
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or not a.has("cell_b") or a.has("jailed"):
			continue
		var jb: int = int(a["cell_b"])
		a.erase("cell_b")
		if a.has("v5_hold") and String(a["v5_hold"]) == "cuffed":
			a.erase("v5_hold")
		sim.agents._clear_plan(a)
		sim.people.note(a, "Released from jail.")
		sim.log_event("released", "%s was released from jail." % String(a["name"]), [int(aid), jb], 1)

func _talk_fights(now: int) -> void:
	var talks: Dictionary = sim.state.get("v5", {}).get("talks", {})
	if talks.is_empty():
		return
	var tf: Dictionary = cfg()["talk_fight"]
	var rebel: float = float(sim.content["society"]["attitude"]["rebel_below"])
	var slack: float = float(sim.content["society"]["attitude"]["slack_below"])
	var argue: Array = sim.content["society"]["social"]["talk"]["argue_topics"]
	var keys: Array = talks.keys()
	keys.sort()
	for key in keys:
		var t: Dictionary = talks[key]
		var x: Dictionary = sim.state["agents"].get(int(t["a"]), {})
		var y: Dictionary = sim.state["agents"].get(int(t["b"]), {})
		if not can_fight(x) or not can_fight(y):
			continue
		var ax: float = float(sim.people.rec_of(int(x["id"])).get("att", 0.0))
		var ay: float = float(sim.people.rec_of(int(y["id"])).get("att", 0.0))
		var p := 0.0
		var st: String = String(sim.relations.rel_of(int(x["id"]), int(y["id"])).get("status", ""))
		if st == "enemy":
			p = float(tf["enemy"])
		if minf(ax, ay) <= rebel:
			p = maxf(p, float(tf["rebel"]))
		elif argue.has(String(t["topic"])) and (sim.people.has_trait(x, "hot-headed") or sim.people.has_trait(y, "hot-headed")) and minf(ax, ay) <= slack:
			p = maxf(p, float(tf["hot"]))
		if p <= 0.0:
			continue
		if sim.unrest.locked(_base_of(x)):
			p *= float(cfg()["lock_mult"])
		if _h(int(key % 2147483647), now / _hz()) < p:
			start_fight(x, y, "argument")

## Starts a fight between x and y (both must be able to fight). Returns the fight id or -1.
func start_fight(x: Dictionary, y: Dictionary, cause: String) -> int:
	if not can_fight(x) or not can_fight(y) or int(x["id"]) == int(y["id"]):
		return -1
	var v: Dictionary = _w()
	var fid: int = int(v["fight_seq"]) + 1
	v["fight_seq"] = fid
	var now: int = int(sim.state["tick"])
	var base: int = _base_of(x)
	var dur: float = float(cfg()["fight_s_office"]) if has_office(base) else float(cfg()["fight_s"])
	var f := {"id": fid, "fighters": [int(x["id"]), int(y["id"])], "bld": int(x["bld"]), "pos": ((x["pos"] as Vector2) + (y["pos"] as Vector2)) * 0.5,
		"start": now, "until": now + int(dur * float(_hz())), "officer": -1, "cause": cause, "base": base, "injured": 0}
	v["fights"][fid] = f
	for a in [x, y]:
		_hold_fight(a, fid, dur)
	sim.social.say(x, sim.social.pick_line("fight", x, fid), "fight", int(y["id"]))
	_dispatch(f)
	return fid

func _hold_fight(a: Dictionary, fid: int, dur: float) -> void:
	sim.agents.abort_plan(a, "fight")
	a["v5_hold"] = "fight"
	a["v5_fight"] = fid
	sim.agents._start_plan(a, "fight", [{"op": "fight", "t": dur + 5.0}], "Fighting")

## The nearest free officer of the base walks to the fight.
func _dispatch(f: Dictionary) -> void:
	var best: Dictionary = {}
	var best_d := 1e18
	for oid in officers(int(f["base"])):
		var o: Dictionary = sim.state["agents"][oid]
		if o["where"] != "in" or o.has("v5_hold") or o.has("jailed") or bool(o.get("sleeping", false)) or o.has("v5_nowork"):
			continue
		var d: float = (o["pos"] as Vector2).distance_to(f["pos"])
		if d < best_d:
			best_d = d
			best = o
	if best.is_empty():
		return
	sim.agents.abort_plan(best, "respond")
	if sim.agents._start_personal(best, "respond", int(f["bld"]), [{"op": "wait", "t": 30.0}], "Responding to a fight", -1):
		best["v5_hold"] = "respond"
		best["v5_fight"] = int(f["id"])
		f["officer"] = int(best["id"])

func _fight_second(f: Dictionary, now: int) -> void:
	var c: Dictionary = cfg()
	var alive: Array = []
	for fid in f["fighters"]:
		var a: Dictionary = sim.state["agents"].get(int(fid), {})
		if a.is_empty() or a["state"] != "alive" or String(a.get("v5_hold", "")) != "fight" or int(a.get("v5_fight", -1)) != int(f["id"]):
			continue
		alive.append(a)
	# Blows: each fighter still standing takes damage; one who is down stops fighting.
	var standing: Array = []
	for a in alive:
		if float(a["health"]) > float(c["down_health"]):
			sim.agents._hurt(a, float(c["damage_per_s"]) * (1.0 + 0.5 * _h(int(a["id"]), now)), "injuries from a fight")
			if a["state"] == "alive" and float(a["health"]) > float(c["down_health"]):
				standing.append(a)
			elif a["state"] == "alive":
				f["injured"] = int(f["injured"]) + 1
				_let_go(a, "Knocked down in a fight")
	# Friends of a fighter in the room may join (at most join_max in all).
	if standing.size() >= 2 and (f["fighters"] as Array).size() < int(c["join_max"]):
		_joiners(f, now)
	# An officer who has arrived separates them.
	var off: Dictionary = sim.state["agents"].get(int(f["officer"]), {})
	var arrived: bool = not off.is_empty() and off["state"] == "alive" and off["where"] == "in" and int(off["bld"]) == int(f["bld"]) \
		and String(off.get("v5_hold", "")) == "respond" and sim.agents._step_op(off) == "wait"
	if arrived or standing.size() < 2 or now >= int(f["until"]):
		_end_fight(f, off if arrived else {})
	elif int(f["officer"]) == -1 and (now - int(f["start"])) % (5 * _hz()) == 0:
		_dispatch(f)

func _joiners(f: Dictionary, now: int) -> void:
	var c: Dictionary = cfg()
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if (f["fighters"] as Array).size() >= int(c["join_max"]):
			return
		if not can_fight(a) or int(a["bld"]) != int(f["bld"]) or (a["pos"] as Vector2).distance_to(f["pos"]) > 8.0:
			continue
		var friend := false
		for fid in f["fighters"]:
			var st: String = String(sim.relations.rel_of(int(aid), int(fid)).get("status", ""))
			if ["friend", "best_friend", "dating", "partners", "married"].has(st):
				friend = true
		var hot: bool = sim.people.has_trait(a, "hot-headed") or float(sim.people.rec_of(int(aid)).get("att", 0.0)) <= float(sim.content["society"]["attitude"]["slack_below"])
		if friend and hot and _h(int(aid), now / _hz() + int(f["id"])) < float(c["join_chance"]):
			(f["fighters"] as Array).append(int(aid))
			_hold_fight(a, int(f["id"]), float(int(f["until"]) - now) / float(_hz()))

func _let_go(a: Dictionary, why: String) -> void:
	if String(a.get("v5_hold", "")) == "fight":
		a.erase("v5_hold")
		a.erase("v5_fight")
		sim.agents._clear_plan(a)
	sim.people.add_mod(a, {"kind": "fought", "text": why, "comp": "safety", "sat": -10.0, "att": -4.0, "days": 2.0})

## The fight ends: with an officer, the one with the worst attitude is arrested.
func _end_fight(f: Dictionary, officer: Dictionary) -> void:
	var v: Dictionary = _w()
	v["fights"].erase(int(f["id"]))
	var people: Array = []
	for fid in f["fighters"]:
		var a: Dictionary = sim.state["agents"].get(int(fid), {})
		if a.is_empty() or a["state"] != "alive":
			continue
		people.append(a)
		if String(a.get("v5_hold", "")) == "fight" and int(a.get("v5_fight", -1)) == int(f["id"]):
			_let_go(a, "Was in a fight")
	# The two first fighters now dislike each other more.
	var x: Dictionary = sim.state["agents"].get(int(f["fighters"][0]), {})
	var y: Dictionary = sim.state["agents"].get(int(f["fighters"][1]), {})
	if not x.is_empty() and not y.is_empty() and x["state"] == "alive" and y["state"] == "alive":
		var r: Dictionary = sim.relations._rel_w(x, y)
		r["aff"] = clampf(float(r["aff"]) - 20.0, -100.0, 100.0)
		sim.relations._update_status(r, x, y, "")
	var names: Array = []
	var ids: Array = []
	for a in people:
		names.append(String(a["name"]))
		ids.append(int(a["id"]))
	var place: String = String(sim.state["buildings"].get(int(f["bld"]), {}).get("name", "the base"))
	sim.log_event("fight", "%s had a fist fight in %s." % [" and ".join(names) if names.size() <= 2 else ", ".join(names), place], ids + [int(f["bld"])], 2, {"place": int(f["bld"]), "cause": String(f["cause"])})
	if int(f["injured"]) > 0 and sim.get("unrest") != null:
		var ur: Dictionary = sim.unrest.rec_of(int(f["base"]))
		if not ur.is_empty():
			ur["injured"] = int(ur.get("injured", 0)) + int(f["injured"])
	if not officer.is_empty():
		officer.erase("v5_hold")
		officer.erase("v5_fight")
		sim.agents._clear_plan(officer)
		var worst: Dictionary = {}
		var wv := 1e9
		for a in people:
			var att: float = float(sim.people.rec_of(int(a["id"])).get("att", 0.0))
			if att < wv:
				wv = att
				worst = a
		if not worst.is_empty():
			arrest(worst, officer, float(cfg()["arrest_days"]))

# ---------------------------------------------------------------- arrest, escort, jail
## Arrests a person: jail (a free cell) or confinement. The officer (or {}) walks along.
func arrest(a: Dictionary, officer: Dictionary, days: float) -> Dictionary:
	var res: Dictionary = sim.discipline.apply(a, "jail", {"days": days, "silent": true, "arrest": true})
	var jailed: bool = a.has("jailed")
	var text: String = "%s was arrested%s." % [String(a["name"]), (" by " + String(officer["name"])) if not officer.is_empty() else ""]
	sim.log_event("arrest", text + (" Taken to jail." if jailed else " Confined to quarters (no free cell)."), [int(a["id"])] + ([int(officer["id"])] if not officer.is_empty() else []), 2)
	if jailed and not officer.is_empty() and officer["state"] == "alive":
		var jb: int = int(a.get("cell_b", -1))
		if jb != -1 and sim.agents._start_personal(officer, "escort", jb, [{"op": "wait", "t": 3.0}], "Escorting %s to jail" % String(a["name"]).split(" ")[0], -1):
			officer["v5_hold"] = "escort"
			officer["v5_escort"] = int(a["id"])
	return res

## Called by discipline.apply after a jail mod was added: the person gets a cell and is walked there
## (escort: a free officer of the base walks along; an arrest brings its own officer).
func on_jailed(a: Dictionary, escort: bool = false) -> void:
	var jb: int = jail_for(a) if int(a.get("cell_b", -1)) == -1 else int(a["cell_b"])
	if jb == -1:
		return
	a["cell_b"] = jb
	a.erase("v5_fight")
	sim.agents.abort_plan(a, "arrested")
	a["v5_hold"] = "cuffed"
	if not _to_cell(a, jb):
		a.erase("v5_hold")
		return
	if not escort:
		return
	for oid in officers(_base_of(a)):
		var o: Dictionary = sim.state["agents"][oid]
		if o["where"] != "in" or o.has("v5_hold") or o.has("jailed") or bool(o.get("sleeping", false)):
			continue
		if sim.agents._start_personal(o, "escort", jb, [{"op": "wait", "t": 3.0}], "Escorting %s to jail" % String(a["name"]).split(" ")[0], -1):
			o["v5_hold"] = "escort"
			o["v5_escort"] = int(a["id"])
			return

func _to_cell(a: Dictionary, jb: int) -> bool:
	return sim.agents._start_personal(a, "jail", jb, [{"op": "cell", "t": 10.0}], "Taken to a cell" if String(a.get("v5_hold", "")) == "cuffed" else "In a cell", -1)

## The part of a person's decision that this system owns (agents._think calls it first for a
## person with v5_hold or jailed). true: nothing else decides this second.
func hold_think(a: Dictionary) -> bool:
	var hold: String = String(a.get("v5_hold", ""))
	var busy: bool = not (a["plan"] as Array).is_empty()
	match hold:
		"fight":
			if fights_r().has(int(a.get("v5_fight", -1))):
				return true
			a.erase("v5_hold")
			a.erase("v5_fight")
			sim.agents._clear_plan(a)
			return false
		"respond":
			if busy and fights_r().has(int(a.get("v5_fight", -1))):
				return true
			a.erase("v5_hold")
			a.erase("v5_fight")
			if busy and String(a["plan_kind"]) == "respond":
				sim.agents._clear_plan(a)
			return false
		"escort":
			if busy and String(a["plan_kind"]) == "escort":
				return true
			a.erase("v5_hold")
			a.erase("v5_escort")
			return false
		"cuffed":
			if busy and String(a["plan_kind"]) == "jail":
				return true
			a.erase("v5_hold")
	if a.has("jailed"):
		return _prisoner_think(a)
	return false

func _prisoner_think(a: Dictionary) -> bool:
	var jb: int = int(a.get("cell_b", -1))
	var j: Dictionary = sim.state["buildings"].get(jb, {})
	if j.is_empty() or j["state"] != "active":
		# The jail is gone: the rest of the time is spent confined to quarters.
		a.erase("cell_b")
		sim.people.end_mods(a, ["jail"])
		sim.discipline.apply(a, "confine", {"days": 0.5, "silent": true})
		return false
	if not (a["plan"] as Array).is_empty():
		return true
	if a["where"] != "in" or int(a["bld"]) != jb:
		if not _to_cell(a, jb):
			sim.agents._idle(a)
		return true
	var bal: Dictionary = sim.bal
	var trig: float = float(bal["need_trigger"])
	if float(a["thirst"]) >= trig and sim.util.can_drink_at(jb):
		sim.agents._start_plan(a, "drink", [{"op": "drink", "hold": -1}], "Drinking in the cell")
		return true
	if float(a["hunger"]) >= trig and _prison_meal(a):
		return true
	if float(a["fatigue"]) >= trig or (sim.util.is_night() and float(a["fatigue"]) >= float(bal["night_sleep_trigger"])):
		sim.agents._start_plan(a, "sleep", [{"op": "sleep"}], "Sleeping in a cell")
		return true
	sim.agents._start_plan(a, "jail", [{"op": "cell", "t": 20.0}], "Serving time")
	return true

## A prison ration: a dish from the nearest store of the base, eaten in the cell.
func _prison_meal(a: Dictionary) -> bool:
	var dishes: Array = sim.items.dishes().duplicate()
	dishes.sort_custom(func(x, y): return (0 if x == "meals" else 1) < (0 if y == "meals" else 1) if (x == "meals") != (y == "meals") else String(x) < String(y))
	for d in dishes:
		var src: int = sim.jobs.find_source(String(d), a["pos"])
		if src == -1:
			continue
		if not sim.inv.consume(src, String(d), 1, "eaten"):
			continue
		sim.stat_add("eaten", String(d), 1)
		sim.stat_add("consumed", String(d), 1)
		a["hunger"] = maxf(0.0, float(a["hunger"]) - float(sim.bal["meal_hunger"]))
		if a.has("nutrition"):
			sim.nutrition.eat(a, String(d))
		sim.agents._start_plan(a, "jail", [{"op": "cell", "t": float(sim.bal["eat_seconds"])}], "Eating a prison ration")
		return true
	return false

# ---------------------------------------------------------------- patrol
## A security officer on duty walks between the security office and the leisure rooms of the base.
func patrol_think(a: Dictionary) -> bool:
	var base: int = _base_of(a)
	var rooms: Array = _patrol_list(base)
	if rooms.is_empty():
		return false
	var minute: int = int(sim.state["tick"]) / (60 * _hz())
	var target: int = int(rooms[int(_h(int(a["id"]), minute) * rooms.size()) % rooms.size()])
	return sim.agents._start_personal(a, "patrol", target, [{"op": "patrol", "t": float(cfg()["patrol_s"])}], "On patrol", -1)

func _patrol_list(base: int) -> Array:
	var sec: int = int(sim.state["tick"]) / _hz()
	if sec != _patrol_sec:
		_patrol_sec = sec
		_patrol_rooms = {}
	if _patrol_rooms.has(base):
		return _patrol_rooms[base]
	var out: Array = []
	for id in sim.topo.atmo_comp:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] != "active" or bool(b["demolish"]) or not sim.util.building_supplied(int(id)):
			continue
		if base != -1 and sim.bases.count() > 1 and sim.bases.base_of(int(id)) != base:
			continue
		var d: String = String(b["def"])
		var cat: String = String(sim.bdef(d).get("category", ""))
		if d == "security_office" or d == "jail" or cat == "comfort" or d == "super_dome" or d == "kitchen":
			out.append(int(id))
	out.sort()
	_patrol_rooms[base] = out
	return out

# ---------------------------------------------------------------- riots
## A riot second at a base: fights break out, a room is damaged, stores are looted.
func _riot_second(base: int, now: int) -> void:
	var c: Dictionary = cfg()
	var ur: Dictionary = sim.unrest.rec_of(base)
	var mult: float = float(c["lock_mult"]) if sim.unrest.locked(base) else 1.0
	var sec: int = now / _hz()
	if _h(base + 17, sec) < float(c["riot_fight_chance"]) * mult:
		var cands: Array = []
		var ids: Array = sim.state["agents"].keys()
		ids.sort()
		for aid in ids:
			var a: Dictionary = sim.state["agents"][aid]
			if can_fight(a) and _base_of(a) == base:
				cands.append(a)
		cands.sort_custom(func(x, y):
			var ax: float = float(sim.people.rec_of(int(x["id"])).get("att", 0.0))
			var ay: float = float(sim.people.rec_of(int(y["id"])).get("att", 0.0))
			return ax < ay if ax != ay else int(x["id"]) < int(y["id"]))
		var done := false
		for i in mini(cands.size(), 12):
			if done:
				break
			for j in range(i + 1, cands.size()):
				if int(cands[i]["bld"]) == int(cands[j]["bld"]):
					start_fight(cands[i], cands[j], "riot")
					done = true
					break
	if _h(base + 29, sec) < 0.2 * mult:
		var rooms: Array = []
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["state"] == "active" and b["kind"] != "link" and String(b["def"]) != "lander" and (sim.bases.count() == 0 or sim.bases.base_of(int(id)) == base):
				rooms.append(int(id))
		rooms.sort()
		if not rooms.is_empty():
			var rid: int = int(rooms[int(_h(base + 31, sec) * rooms.size()) % rooms.size()])
			var rb: Dictionary = sim.state["buildings"][rid]
			if float(rb["health"]) > float(c["riot_min_health"]):
				rb["health"] = maxf(float(c["riot_min_health"]), float(rb["health"]) - float(c["riot_damage"]) * 5.0)
				if not ur.is_empty():
					var dm: Array = ur.get("damaged", [])
					if not dm.has(rid):
						dm.append(rid)
					ur["damaged"] = dm
	if _h(base + 41, sec) < float(c["loot_chance"]) * mult:
		for item in c["loot_items"]:
			var at: Vector2 = sim.bases.core_of(base).get("pos", sim.world.center) if sim.bases.count() > 0 else sim.world.center
			var src: int = sim.jobs.find_source(String(item), at)
			if src != -1:
				sim.inv.destroy(src, String(item), 1, "looted")
				if not ur.is_empty():
					ur["looted"] = int(ur.get("looted", 0)) + 1
				break
