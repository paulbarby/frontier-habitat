extends RefCounted
## The Academy (docs/V5_DESIGN.md section 5.3). A course takes one person one level up in one
## skill. It needs an active academy with a free seat, and a teacher (a colonist of the base with
## the skill at 60 or more) or, up to level 3, the instructor console. The student does no other
## work until the course ends (a trade-off). Numbers: content/society.json "education".
##
## Stored in state.v5.courses[agent id] = {skill, building, progress 0..1, level_to, teacher}.
## The student walks to the academy and sits in class ("class" steps, a seat anchor); the course
## moves on only then: pace 1 with the teacher in the room (the teacher walks there and teaches:
## "teach" steps at the teacher's desk), console_pace without, and nothing above console_max_level
## without the teacher. Research "education" adds course_speed. Children at school take free seats.

var sim

func _init(s) -> void:
	sim = s

func cfg() -> Dictionary:
	return sim.content["society"]["education"]

func _courses_r() -> Dictionary:
	return sim.state.get("v5", {}).get("courses", {})

## True while a person is enrolled (no other work).
func in_class(a: Dictionary) -> bool:
	return _courses_r().has(int(a["id"]))

## The students of an academy: [{agent, skill, progress 0..1, level_to, teacher}].
func students(building: int) -> Array:
	var out: Array = []
	var cs: Dictionary = _courses_r()
	var ids: Array = cs.keys()
	ids.sort()
	for aid in ids:
		var c: Dictionary = cs[aid]
		if int(c["building"]) == building:
			out.append({"agent": int(aid), "skill": String(c["skill"]), "progress": snappedf(float(c["progress"]), 0.001), "level_to": int(c["level_to"]), "teacher": int(c["teacher"])})
	return out

func seats(b: Dictionary) -> int:
	return int(sim.bd(b).get("seats_class", 4))

func _level_from(level: int) -> int:
	return int(sim.content["people"]["skill_levels"]["from"][clampi(level - 1, 0, 4)])

## A teacher for a skill at a level: a colonist of the base (not the student) with the skill at
## teacher_skill or more; -1 (the console) up to console_max_level; -2: none.
func teacher_for(a: Dictionary, skill: String, level_to: int) -> int:
	var base: int = sim.bases.home_of(a) if sim.bases.count() > 0 else -1
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var x: Dictionary = sim.state["agents"][aid]
		if int(aid) == int(a["id"]) or x["state"] != "alive" or String(x.get("kind", "")) == "visitor" or String(x.get("kind", "")) == "child":
			continue
		if base != -1 and sim.bases.home_of(x) != base:
			continue
		if int(sim.people.skills(x).get(skill, 0)) >= int(cfg()["teacher_skill"]) and int(sim.people.skills(x)[skill]) >= _level_from(level_to):
			return int(aid)
	return -1 if level_to <= int(cfg()["console_max_level"]) else -2

## Command "enrol" {agent, skill, building}.
func cmd_enrol(p: Dictionary) -> Dictionary:
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	var skill: String = String(p.get("skill", ""))
	var bid: int = int(p.get("building", -1))
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if a.is_empty() or a["state"] != "alive" or String(a.get("kind", "")) == "visitor":
		return {"ok": false, "code": "invalid", "text": "No such person."}
	if not (sim.content["people"]["skills"] as Array).has(skill):
		return {"ok": false, "code": "invalid", "text": "Unknown skill."}
	if b.is_empty() or String(b["def"]) != "academy":
		return {"ok": false, "code": "invalid", "text": "Choose an academy."}
	if b["state"] != "active":
		return {"ok": false, "code": "refused", "text": "The academy is not finished."}
	var cs: Dictionary = sim.people.v5w()["courses"]
	if cs.has(int(a["id"])):
		return {"ok": false, "code": "refused", "text": "Already in a course."}
	if students(bid).size() >= seats(b):
		return {"ok": false, "code": "full", "text": "The academy has no free seat."}
	var v: int = int(sim.people.skills(a).get(skill, 0))
	var lv: int = sim.people.level_of(float(v))
	if lv >= 5:
		return {"ok": false, "code": "refused", "text": "Already at the top level."}
	var t: int = teacher_for(a, skill, lv + 1)
	if t == -2:
		return {"ok": false, "code": "no_teacher", "text": "No teacher: the console teaches up to level %d. A colonist with %s %d or more can teach." % [int(cfg()["console_max_level"]), skill, int(cfg()["teacher_skill"])]}
	cs[int(a["id"])] = {"skill": skill, "building": bid, "progress": 0.0, "level_to": lv + 1, "teacher": t}
	sim.people._apply_flags(a, sim.people.rec_w(a))
	sim.people.note(a, "Enrolled in %s (level %d)." % [skill, lv + 1])
	sim.people.invalidate(int(a["id"]))
	return {"ok": true, "code": "ok", "text": "Enrolled: %s to level %d." % [skill.capitalize(), lv + 1], "teacher": t}

## True while the person sits in class in building bid now.
func _in_room(a: Dictionary, bid: int) -> bool:
	return a["state"] == "alive" and a["where"] == "in" and int(a["bld"]) == bid and String(a.get("plan_kind", "")) == "class" and sim.agents._step_op(a) == "class"

func _teaching(t: Dictionary, bid: int) -> bool:
	return not t.is_empty() and t["state"] == "alive" and t["where"] == "in" and int(t["bld"]) == bid and String(t.get("plan_kind", "")) == "teach"

## People in the seats of an academy now (students and children at school).
func seated(bid: int) -> int:
	var n := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("plan_kind", "")) == "class":
			for st in a["plan"]:
				if String(st["op"]) == "go" and int(st["to"]["b"]) == bid:
					n += 1
			if a["where"] == "in" and int(a["bld"]) == bid and sim.agents._step_op(a) == "class":
				n += 1
	return n

## An academy of the child's base with a seat free for school (-1: none).
func school_for(a: Dictionary) -> int:
	var base: int = sim.bases.home_of(a) if sim.bases.count() > 1 else -1
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["def"]) != "academy" or b["state"] != "active" or not sim.util.building_supplied(int(id)):
			continue
		if base != -1 and sim.bases.base_of(int(id)) != base:
			continue
		if students(int(id)).size() + seated(int(id)) < seats(b) + 1:
			return int(id)
	return -1

## A student's or a teacher's part of the day (people.duty_think). true: a plan started.
func think(a: Dictionary) -> bool:
	var cs: Dictionary = _courses_r()
	var c: Dictionary = cs.get(int(a["id"]), {})
	var class_s: float = float(cfg().get("class_s", 40))
	if not c.is_empty():
		var bid: int = int(c["building"])
		var name: String = String(c["skill"]).capitalize()
		return sim.agents._start_personal(a, "class", bid, [{"op": "class", "t": class_s}], "In class: %s" % name, -1)
	# A teacher goes to the academy while a student of theirs is there.
	var ids: Array = cs.keys()
	ids.sort()
	for sid in ids:
		var c2: Dictionary = cs[sid]
		if int(c2["teacher"]) != int(a["id"]):
			continue
		var s: Dictionary = sim.state["agents"].get(int(sid), {})
		var bid2: int = int(c2["building"])
		if s.is_empty() or s["state"] != "alive" or String(s.get("plan_kind", "")) != "class":
			continue
		if sim.agents._start_personal(a, "teach", bid2, [{"op": "teach", "t": class_s}], "Teaching %s" % String(c2["skill"]), 0):
			return true
	return false

## Every tick (sim.step): each course moves on once a game second on its own tick while the student
## sits in class; a course ends when its academy is gone or the student dies. Children at school
## gain school points the same way.
func tick() -> void:
	var cs: Dictionary = _courses_r()
	var hz: int = int(sim.bal["tick_hz"])
	var now: int = int(sim.state["tick"])
	if not cs.is_empty():
		var dur_s: float = float(cfg()["course_hours"]) / 24.0 * float(sim.bal["day_length"])
		var speed: float = 1.0 + sim.research.bonus("course_speed")
		var ids: Array = cs.keys()
		ids.sort()
		for aid in ids:
			if (now + int(aid)) % hz != 0:
				continue
			var c: Dictionary = cs[aid]
			var a: Dictionary = sim.state["agents"].get(int(aid), {})
			var b: Dictionary = sim.state["buildings"].get(int(c["building"]), {})
			if a.is_empty() or a["state"] != "alive" or b.is_empty() or b["state"] != "active":
				cs.erase(aid)
				if not a.is_empty():
					sim.people._apply_flags(a, sim.people.rec_w(a))
				continue
			if not _in_room(a, int(c["building"])):
				continue
			var pace := 0.0
			if int(c["teacher"]) >= 0 and _teaching(sim.state["agents"].get(int(c["teacher"]), {}), int(c["building"])):
				pace = 1.0
			elif int(c["level_to"]) <= int(cfg()["console_max_level"]):
				pace = float(cfg().get("console_pace", 0.5))
			c["progress"] = minf(1.0, float(c["progress"]) + pace * speed / dur_s)
			if float(c["progress"]) >= 1.0:
				_graduate(a, c)
				cs.erase(aid)
				sim.people._apply_flags(a, sim.people.rec_w(a))
				if String(a.get("plan_kind", "")) == "class":
					sim.agents._clear_plan(a)
	# School: children in class, once a second each.
	if now % hz == 6:
		var pts: float = float(sim.content["society"]["families"]["school_pts_per_s"])
		for aid in sim.state["agents"]:
			var k: Dictionary = sim.state["agents"][aid]
			if String(k.get("kind", "")) == "child" and k["state"] == "alive" and String(k.get("plan_kind", "")) == "class" and sim.agents._step_op(k) == "class" and k["where"] == "in":
				sim.families.school_second(k, pts)

func _graduate(a: Dictionary, c: Dictionary) -> void:
	var skill: String = String(c["skill"])
	var v: int = int(sim.people.skills(a).get(skill, 0))
	var need: int = maxi(0, _level_from(int(c["level_to"])) - v)
	var r: Dictionary = sim.people.rec_w(a)
	if not r.has("skill_bonus"):
		r["skill_bonus"] = {}
	r["skill_bonus"][skill] = int(r["skill_bonus"].get(skill, 0)) + need + 1
	sim.people.invalidate(int(a["id"]))
	var lvn: String = String(sim.content["people"]["skill_levels"]["names"][clampi(int(c["level_to"]) - 1, 0, 4)])
	sim.people.note(a, "Finished a course: %s %s." % [skill, lvn])
	sim.log_event("graduated", "%s finished a course: %s, now %s." % [String(a["name"]), skill, lvn], [int(a["id"]), int(c["building"])], 1, {"skill": skill})
