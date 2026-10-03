extends RefCounted
## Version 5 test for the job priorities (Colonists > Priorities tab): 3 = first, 2 = normal, 1 = last,
## 0 ("-") = never; the colony value (set_priority) and the colonist's own value (set_jobs).
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")

func tests() -> Array:
	return [
		["v5_job_priorities", v5_job_priorities],
		["v5_names_unique", v5_names_unique],
	]

static func _spot(sim, def_id: String, around: Vector2, rmin: float, rmax: float, k0: int = 0) -> Vector2:
	var r: float = rmin
	while r <= rmax:
		for k in 36:
			var p: Vector2 = sim.place.snap_pos(around + Vector2.RIGHT.rotated(((k + k0) % 36) * TAU / 36.0) * r)
			if sim.place.check_building(def_id, p, 0.0, -1, 1) == "ok":
				return p
		r += 6.0
	return Vector2(-1, -1)

const CATS := ["construction", "food", "industry", "logistics", "repair"]

## The open work of the small colony: a structure to take down (construction), a dusty panel to clean
## (repair), and one "operate"-like task for each of the other categories (food, industry, logistics)
## on the lander, for the score checks. The real task maker is used (test set-up).
class Board:
	var g
	var sim
	var near_spot: Vector2
	var far_spot: Vector2
	var lid: int
	var demolish_id := -1
	var dust_id := -1
	var by_cat := {}     # category -> task id (score tasks)

	func _init(game, lander_id: int, p_near: Vector2, p_far: Vector2) -> void:
		g = game
		sim = game.sim
		lid = lander_id
		near_spot = p_near
		far_spot = p_far

	## Clears the board and makes the work again (a command passes one tick, which may change it).
	func make(with_demolish: bool, with_dust: bool) -> void:
		for tid in sim.state["tasks"].keys():
			sim.jobs.fail(int(tid), "test_setup")
		by_cat = {}
		if with_demolish and sim.state["buildings"].has(demolish_id):
			sim.jobs._new_task("demolish", "construction", demolish_id, {})
		if with_dust and sim.state["buildings"].has(dust_id):
			sim.jobs._new_task("clean", "repair", dust_id, {})

	## One task of each category on the lander, only to read scores.
	func score_tasks() -> void:
		for cat in CATS:
			by_cat[cat] = int(sim.jobs._new_task("operate", cat, lid, {})["id"])

func _rested(sim, a: Dictionary, bid: int) -> void:
	H.put_inside(sim, a, bid)
	a["fatigue"] = 0.0
	a["hunger"] = 0.0
	a["thirst"] = 0.0
	a["suit"] = sim.agents.suit_cap()
	a["backoff"] = {}

## What the colonist does when it thinks now: "task:<kind>", or the plan kind.
func _pick(sim, a: Dictionary) -> String:
	if a["task"] != -1:
		sim.jobs.release(int(a["task"]), "test_setup")
		a["task"] = -1
	sim.agents.abort_plan(a, "test_setup")
	a["backoff"] = {}
	sim.agents._think(a)
	if a["plan_kind"] == "task" and int(a["task"]) != -1 and sim.state["tasks"].has(int(a["task"])):
		return "task:" + String(sim.state["tasks"][int(a["task"])]["kind"])
	return String(a["plan_kind"])

func _free(sim, a: Dictionary) -> void:
	if a["task"] != -1:
		sim.jobs.release(int(a["task"]), "test_setup")
		a["task"] = -1
	sim.agents.abort_plan(a, "test_setup")

func v5_job_priorities(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	sim.state["flags"]["unlock_all"] = true                                                # test set-up
	var lid: int = int(sim.state["lander_id"])
	var lander: Dictionary = sim.state["buildings"][lid]
	var ids: Array = []
	for aid in sim.state["agents"]:
		ids.append(int(aid))
	ids.sort()
	var a: Dictionary = sim.state["agents"][ids[0]]
	var b: Dictionary = sim.state["agents"][ids[1]]
	var c: Dictionary = sim.state["agents"][ids[2]]
	t.check(ids.size() >= 3, "a small colony (%d colonists)" % ids.size())
	# Two solar arrays: one to take down (construction), one dusty (repair), 25-60 m from the lander.
	var p1: Vector2 = _spot(sim, "solar_array", lander["pos"], 25.0, 60.0)
	var d_b: Dictionary = sim.build.spawn_active("solar_array", p1, 0.0)                 # test set-up
	var p2: Vector2 = _spot(sim, "solar_array", lander["pos"], 25.0, 70.0, 18)
	var d_c: Dictionary = sim.build.spawn_active("solar_array", p2, 0.0)                 # test set-up
	d_b["demolish"] = true                                                                 # test set-up
	d_c["dust"] = true                                                                     # test set-up
	var board := Board.new(g, lid, p1, p2)
	board.demolish_id = int(d_b["id"])
	board.dust_id = int(d_c["id"])

	# ---- Scores: the category value decides, in the order 3 > 2 > 1 > never.
	board.make(false, false)
	board.score_tasks()
	var colony: Dictionary = sim.state["policies"]["priority"]
	t.eq(sim.orders.job_categories(), CATS, "the tab shows the five categories")
	for cat in CATS:
		t.check(int(colony[cat]) >= 1 and int(colony[cat]) <= 3, "colony value of %s is 1..3 (%d)" % [cat, int(colony[cat])])
	_rested(sim, a, lid)
	var s := {}
	for cat in CATS:
		s[cat] = sim.jobs.score(sim.state["tasks"][board.by_cat[cat]], a)
	t.check(s["construction"] > s["logistics"], "colony default: construction (%d) before logistics (%d)" % [int(colony["construction"]), int(colony["logistics"])])
	# 3 / 2 / 1 / never on one colonist: the order of the scores follows the values.
	t.check(bool(g.cmd("set_jobs", {"agent": ids[0], "jobs": {"construction": 3, "food": 2, "industry": 1, "logistics": 0, "repair": 1}})["ok"]), "set_jobs 3/2/1/-/1")
	board.make(false, false)
	board.score_tasks()
	for cat in CATS:
		s[cat] = sim.jobs.score(sim.state["tasks"][board.by_cat[cat]], a)
	t.check(s["construction"] > s["food"] and s["food"] > s["industry"] and s["industry"] > -1e8, "3 scores above 2, 2 above 1 (%d %d %d)" % [int(s["construction"]), int(s["food"]), int(s["industry"])])
	t.check(s["logistics"] <= -1e8, "'-' (0) is never offered (score %d)" % int(s["logistics"]))
	t.check(s["construction"] - s["food"] > 99.0 and s["food"] - s["industry"] > 99.0, "one step of priority is 100 points")

	# ---- Behaviour: construction at 3 and the rest at 1 takes the construction job first.
	var first := {"construction": 3, "food": 1, "industry": 1, "logistics": 1, "repair": 1}
	var last := {"construction": 1, "food": 1, "industry": 1, "logistics": 1, "repair": 3}
	for x in [a, b, c]:
		_rested(sim, x, lid)
	t.check(bool(g.cmd("set_jobs", {"agent": ids[0], "jobs": first})["ok"]), "set_jobs construction 3, rest 1")
	t.check(bool(g.cmd("set_jobs", {"agent": ids[1], "jobs": last})["ok"]), "set_jobs repair 3, rest 1")
	board.make(true, true)
	for x in [a, b, c]:
		_rested(sim, x, lid)
	t.eq(_pick(sim, a), "task:demolish", "construction at 3: takes the construction job although a repair job is open")
	t.eq(_pick(sim, b), "task:clean", "repair at 3: takes the repair job although a construction job is open")
	# The same when the repair job is the nearer one (distance never beats a step of two).
	t.eq(_pick(sim, a), "task:demolish", "construction at 3 again (repeatable)")
	_free(sim, a)
	_free(sim, b)

	# ---- Waiting counts (by design): the colony default logistics 1 would starve behind busier categories without it.
	# A repair job (2) that has waited 40 minutes ranks above a construction job (3) made now; at the same age
	# (checked above) the 3 comes first. The rule: 100 points a step, 0.1 point a second of waiting.
	t.check(bool(g.cmd("set_jobs", {"agent": ids[0], "jobs": {"construction": 3, "food": 2, "industry": 2, "logistics": 2, "repair": 2}})["ok"]), "set_jobs construction 3, repair 2")
	board.make(true, true)
	for tid in sim.state["tasks"]:
		if sim.state["tasks"][tid]["kind"] == "clean":
			sim.state["tasks"][tid]["created"] = int(sim.state["tick"]) - 24000                # test set-up: 2400 s old
	_rested(sim, a, lid)
	t.eq(_pick(sim, a), "task:clean", "a repair job at 2 that waited 40 minutes ranks above a new construction job at 3 (aging)")
	_free(sim, a)
	board.make(true, true)
	for tid in sim.state["tasks"]:
		if sim.state["tasks"][tid]["kind"] == "clean":
			sim.state["tasks"][tid]["created"] = int(sim.state["tick"]) - 3000                 # test set-up: 5 minutes old
	_rested(sim, a, lid)
	t.eq(_pick(sim, a), "task:demolish", "a repair job at 2 that waited 5 minutes does not (30 points)")
	_free(sim, a)

	# ---- "-" means never, even when it is the only job.
	board.make(true, false)
	var none := {"construction": 0, "food": 1, "industry": 1, "logistics": 1, "repair": 1}
	t.check(bool(g.cmd("set_jobs", {"agent": ids[0], "jobs": none})["ok"]), "set_jobs construction '-'")
	board.make(true, false)
	_rested(sim, a, lid)
	t.check(_pick(sim, a) != "task:demolish", "construction '-': the only open job (construction) is not taken (%s)" % _pick(sim, a))
	_free(sim, a)
	# Every category '-': nothing is taken, whatever is open.
	var all_off := {"construction": 0, "food": 0, "industry": 0, "logistics": 0, "repair": 0}
	t.check(bool(g.cmd("set_jobs", {"agent": ids[0], "jobs": all_off})["ok"]), "set_jobs all '-'")
	board.make(true, true)
	_rested(sim, a, lid)
	var pk: String = _pick(sim, a)
	t.check(not pk.begins_with("task:"), "all '-': no job at all (%s)" % pk)
	_free(sim, a)
	# The colony value '-' (0) works the same for a colonist with no own value.
	g.cmd("set_jobs", {"agent": ids[2], "clear": true})
	t.check(bool(g.cmd("set_priority", {"cat": "construction", "value": 0})["ok"]), "set_priority construction '-'")
	board.make(true, false)
	_rested(sim, c, lid)
	t.check(_pick(sim, c) != "task:demolish", "colony construction '-': a colonist with no own value does not take it")
	_free(sim, c)

	# ---- The colonist's own value overrides the colony value.
	g.cmd("set_priority", {"cat": "construction", "value": 1})
	g.cmd("set_priority", {"cat": "repair", "value": 3})
	g.cmd("set_jobs", {"agent": ids[0], "clear": true})
	g.cmd("set_jobs", {"agent": ids[0], "jobs": {"construction": 3}})
	g.cmd("set_jobs", {"agent": ids[2], "clear": true})
	board.make(true, true)
	for x in [a, c]:
		_rested(sim, x, lid)
	t.eq(_pick(sim, c), "task:clean", "colony construction 1, repair 3: a colonist with no own value takes repair")
	t.eq(_pick(sim, a), "task:demolish", "own construction 3 overrides the colony value 1 (repair is 3 in the colony)")
	_free(sim, a)
	_free(sim, c)
	# A change of the colony value changes everyone who has no own value, and only them.
	g.cmd("set_priority", {"cat": "construction", "value": 3})
	g.cmd("set_priority", {"cat": "repair", "value": 1})
	g.cmd("set_jobs", {"agent": ids[0], "jobs": {"construction": 1, "repair": 3}})
	board.make(true, true)
	for x in [a, c]:
		_rested(sim, x, lid)
	t.eq(_pick(sim, c), "task:demolish", "colony construction 3, repair 1: the colonist with no own value now takes construction")
	t.eq(_pick(sim, a), "task:clean", "the colonist with an own value is not moved by the colony change")
	_free(sim, a)
	_free(sim, c)

	# ---- Needs and orders still come first, even for a colonist whose own value is 3.
	g.cmd("set_jobs", {"agent": ids[0], "jobs": {"construction": 3, "repair": 1}})
	board.make(true, true)
	_rested(sim, a, lid)
	a["thirst"] = float(sim.bal["need_critical"]) + 1.0                                    # test set-up
	t.eq(_pick(sim, a), "drink", "critical thirst comes before a job at 3")
	_rested(sim, a, lid)
	a["hunger"] = float(sim.bal["need_critical"]) + 1.0                                    # test set-up
	var hk: String = _pick(sim, a)
	t.check(hk == "eat" or hk == "drink", "critical hunger comes before a job at 3 (%s)" % hk)
	_rested(sim, a, lid)
	a["fatigue"] = float(sim.bal["need_critical"]) + 1.0                                   # test set-up
	t.eq(_pick(sim, a), "sleep", "critical exhaustion comes before a job at 3")
	_rested(sim, a, lid)
	board.make(true, true)
	var oc: Dictionary = g.cmd("order", {"agents": [ids[0]], "kind": "stay", "x": lander["pos"].x, "y": lander["pos"].y})
	t.check(bool(oc["ok"]), "an order is given")
	board.make(true, true)
	_rested(sim, a, lid)
	t.eq(_pick(sim, a), "order", "an order comes before a job at 3")
	g.cmd("order_clear", {"agents": [ids[0]]})

	# ---- The values survive save and load, and a loaded game continues exactly.
	g.cmd("set_jobs", {"agent": ids[1], "jobs": {"food": 0, "industry": 2}})
	g.cmd("set_priority", {"cat": "food", "value": 3})
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved and loaded")
	if bool(cl["ok"]):
		var sim2 = cl["sim"]
		t.eq(sim2.state["policies"]["priority"], sim.state["policies"]["priority"], "the colony values survive")
		for i in 3:
			var x1: Dictionary = sim.state["agents"][ids[i]]
			var x2: Dictionary = sim2.state["agents"][ids[i]]
			t.eq(x2.get("jobs", {}), x1.get("jobs", {}), "own values of colonist %d survive (%s)" % [i, str(x1.get("jobs", {}))])
		for i in 300:
			sim.step()
			sim2.step()
		t.eq(H.digest(sim2), H.digest(sim), "the loaded game continues exactly")
		sim2.dispose()
	# 'clear' returns the colonist to the colony values.
	g.cmd("set_jobs", {"agent": ids[1], "clear": true})
	t.check(not b.has("jobs"), "clear removes the own values")
	g.dispose()
	t.done()

## Names: a big pool, a unique full name for everybody, no number suffix, a child takes a parent's last name,
## and an old save with numbered names is renamed (only those), the log follows, the ids stay.
func v5_names_unique(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	var firsts: Array = sim.content["first_names"]
	var lasts: Array = sim.content["last_names"]
	t.check(firsts.size() >= 150 and lasts.size() >= 150, "pools of %d first and %d last names" % [firsts.size(), lasts.size()])
	var seen_f := {}
	for f in firsts:
		t.check(not seen_f.has(f) and not String(f).contains(" ") and not String(f).is_valid_int(), "first name %s is one word and its own" % f)
		seen_f[f] = true
		if seen_f.size() > 8:
			break
	# 2,000 names: all different, none with a number, all of the form First Last.
	var names := {}
	var bad := 0
	var numbered := 0
	for i in 2000:
		var nm: String = sim.next_name()
		if names.has(nm):
			bad += 1
		names[nm] = true
		var parts: PackedStringArray = nm.split(" ")
		if parts.size() != 2:
			bad += 1
		if parts[parts.size() - 1].is_valid_int():
			numbered += 1
	t.eq(bad, 0, "2,000 names are all different and of the form First Last")
	t.eq(numbered, 0, "no number after a name")
	# A child takes a parent's last name, and the full name is free.
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	var mum: Dictionary = sim.state["agents"][ids[0]]
	var lid: int = int(sim.state["lander_id"])
	var kid: Dictionary = sim.families.spawn_child([int(mum["id"])], mum["pos"], lid)       # test set-up
	t.eq(sim.last_name_of(String(kid["name"])), sim.last_name_of(String(mum["name"])), "a child takes the parent's last name (%s, %s)" % [kid["name"], mum["name"]])
	var all := {}
	var dup := 0
	for aid in sim.state["agents"]:
		var n2: String = String(sim.state["agents"][aid]["name"])
		if all.has(n2):
			dup += 1
		all[n2] = true
	t.eq(dup, 0, "every full name in the colony is its own")
	# Old save: numbered names. Three people get "X 2", "X 3" and one "X 20"; the log mentions them.
	var a1: Dictionary = sim.state["agents"][ids[1]]
	var a2: Dictionary = sim.state["agents"][ids[2]]
	var a3: Dictionary = sim.state["agents"][ids[3]]
	var keep: String = String(a1["name"])
	a2["name"] = keep + " 2"                                                                # test set-up: an old numbered name
	a3["name"] = keep + " 20"                                                               # test set-up
	sim.log_event("test", "%s and %s met %s." % [a2["name"], a3["name"], keep], [int(a2["id"]), int(a3["id"])], 1)
	var before_ids: Array = sim.state["agents"].keys()
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved and loaded")
	if bool(cl["ok"]):
		var sim2 = cl["sim"]
		t.eq(sim2.state["agents"].keys(), before_ids, "the same people (ids)")
		var n1: String = String(sim2.state["agents"][ids[1]]["name"])
		var n2b: String = String(sim2.state["agents"][ids[2]]["name"])
		var n3b: String = String(sim2.state["agents"][ids[3]]["name"])
		t.eq(n1, keep, "the plain name is not changed")
		t.check(not n2b.contains(keep + " 2") and not n3b.contains(keep + " 20") and n2b != n3b, "the numbered names are replaced (%s, %s)" % [n2b, n3b])
		var last_log: String = String(sim2.state["log"][sim2.state["log"].size() - 1]["text"])
		t.eq(last_log, "%s and %s met %s." % [n2b, n3b, keep], "the log has the new names")
		sim2.dispose()
	g.dispose()
	t.done()
