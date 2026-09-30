extends RefCounted
## Homes, couples, families and children (docs/V5_DESIGN.md sections 4.2 and 7). Numbers:
## content/society.json "families".
##
## Homes: the bed building is the home (agents.gd); the unit inside it is the person's record
## `unit` (people.rec_of). A unit holds `beds` adults and `child_beds` children. Partners share a
## unit: when two people become partners one moves in with the other (or both move to a free family
## unit); when there is no room they ask for a shared home (a request for the player).
## Children (agent kind "child", role "child"): no births. Partners adopt through a medical bay
## (command "adopt"), or a shuttle brings a family. A child lives in the family's unit (a bunk),
## goes to school at an academy by day, plays in parks and leisure rooms, never works, and grows up
## after child_grow_days: the role follows the best school subject and the school points are added
## to the skills.
##
## Stored: state.v5.adopt {id: {a, b, at, bld}}, state.v5.school {child id: {skill: points}},
## state.v5.adopt_seq; on the agent: family (id), parents [ids], child_at (tick), age_set (years).

const Rng = preload("res://sim/rng.gd")

var sim

func _init(s) -> void:
	sim = s

func cfg() -> Dictionary:
	return sim.content["society"]["families"]

func _hz() -> int:
	return int(sim.bal["tick_hz"])

func _day() -> int:
	return int(float(sim.bal["day_length"]) * float(_hz()))

func _h(x: int, y: int) -> float:
	return Rng.hash2(x, y, int(sim.state.get("seed", 1)) ^ 0xFA11)

func _w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	for k in ["adopt", "school"]:
		if not v.has(k):
			v[k] = {}
	return v

static func is_child(a: Dictionary) -> bool:
	return String(a.get("kind", "")) == "child"

# ---------------------------------------------------------------- units
## The people (adults and children) living in unit u of building bid.
func unit_people(bid: int, u: int) -> Array:
	var out: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and int(a["bed"]) == bid and int(sim.people.rec_of(int(aid)).get("unit", -1)) == u:
			out.append(int(aid))
	out.sort()
	return out

## A unit of building b with room for `adults` adults and `kids` children (-1: none), the lowest
## index first; the unit the person is in already counts as free for them.
func free_unit(b: Dictionary, adults: int, kids: int, quality: Array = []) -> int:
	for u in sim.floors.units(b):
		if not quality.is_empty() and not quality.has(String(u["quality"])):
			continue
		var na := 0
		var nk := 0
		for aid in unit_people(int(b["id"]), int(u["index"])):
			if is_child(sim.state["agents"][aid]):
				nk += 1
			else:
				na += 1
		if int(u["beds"]) - na >= adults and int(u.get("child_beds", 0)) - nk >= kids:
			return int(u["index"])
	return -1

func _move(a: Dictionary, bid: int, u: int) -> void:
	if not is_child(a):
		sim.agents._set_bed(a, bid)
	else:
		a["bed"] = bid
	sim.people.rec_w(a)["unit"] = u
	sim.people.invalidate(int(a["id"]))

## Two people became partners (relations.gd): they move in together if there is room.
func on_partners(x: Dictionary, y: Dictionary) -> void:
	if String(x.get("kind", "")) == "visitor" or String(y.get("kind", "")) == "visitor":
		return
	if sim.bases.count() > 1 and sim.bases.home_of(x) != sim.bases.home_of(y):
		return
	# 1. Into the unit of one of them.
	for pair in [[x, y], [y, x]]:
		var host: Dictionary = pair[0]
		var guest: Dictionary = pair[1]
		var hb: Dictionary = sim.state["buildings"].get(int(host["bed"]), {})
		var hu: int = int(sim.people.rec_of(int(host["id"])).get("unit", -1))
		if hb.is_empty() or hu < 0 or sim.floors.units(hb).is_empty():
			continue
		var others: Array = unit_people(int(hb["id"]), hu)
		var adults := 0
		for oid in others:
			if not is_child(sim.state["agents"][oid]) and int(oid) != int(guest["id"]):
				adults += 1
		var beds: int = int(sim.floors.units(hb)[hu]["beds"]) if hu < sim.floors.units(hb).size() else 0
		if adults < beds:
			_move(guest, int(hb["id"]), hu)
			_moved_in(x, y, hb)
			return
	# 2. Both into a free family unit of their base.
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for bid in ids:
		var b: Dictionary = sim.state["buildings"][bid]
		if b["state"] != "active" or sim.floors.units(b).is_empty():
			continue
		if sim.bases.count() > 1 and sim.bases.base_of(int(bid)) != sim.bases.home_of(x):
			continue
		var u: int = free_unit(b, 2, 0)
		if u >= 0 and sim.housing.free_beds(b) + (1 if int(x["bed"]) == int(bid) else 0) + (1 if int(y["bed"]) == int(bid) else 0) >= 2:
			_move(x, int(bid), u)
			_move(y, int(bid), u)
			_moved_in(x, y, b)
			return
	# 3. No room: they ask for a shared home.
	sim.relations.add_request("shared_home", x, y, "%s and %s want a shared home. Build a residence tube or an apartment block." % [String(x["name"]), String(y["name"])])

func _moved_in(x: Dictionary, y: Dictionary, b: Dictionary) -> void:
	for p in [x, y]:
		sim.people.note(p, "Moved in with %s." % String((y if p == x else x)["name"]))
		sim.people.add_mod(p, {"kind": "moved_in", "text": "Moved in with a partner", "comp": "housing", "sat": 10.0, "att": 2.0, "days": 3.0})
	# Their children follow them.
	for c in children_of(int(x["id"])) + children_of(int(y["id"])):
		var ch: Dictionary = sim.state["agents"][c]
		_move(ch, int(x["bed"]), int(sim.people.rec_of(int(x["id"])).get("unit", -1)))
	sim.log_event("move_in", "%s and %s moved in together in %s." % [String(x["name"]), String(y["name"]), String(b["name"])], [int(x["id"]), int(y["id"]), int(b["id"])], 1, {"place": int(b["id"])})

func children_of(pid: int) -> Array:
	var out: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and is_child(a) and (a.get("parents", []) as Array).has(pid):
			out.append(int(aid))
	out.sort()
	return out

## The bed building of a child: a parent's home (agents._assign_bed asks).
func child_bed(a: Dictionary) -> int:
	for pid in a.get("parents", []):
		var p: Dictionary = sim.state["agents"].get(int(pid), {})
		if not p.is_empty() and p["state"] == "alive" and int(p["bed"]) != -1:
			if int(a["bed"]) != int(p["bed"]):
				a["bed"] = int(p["bed"])
				sim.people.rec_w(a)["unit"] = int(sim.people.rec_of(int(pid)).get("unit", -1))
			return int(p["bed"])
	# Orphans (and children whose parents have no bed yet) keep a bunk, or take a free one; with
	# none, the ordinary bed rules (agents._assign_bed) decide.
	var cur: Dictionary = sim.state["buildings"].get(int(a["bed"]), {})
	if not cur.is_empty() and cur["state"] == "active" and int(sim.bd(cur).get("child_beds", 0)) > 0:
		return int(a["bed"])
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for bid in ids:
		var b: Dictionary = sim.state["buildings"][bid]
		var cap: int = int(sim.bd(b).get("child_beds", 0))
		if cap <= 0 or b["state"] != "active" or (sim.bases.count() > 1 and sim.bases.base_of(int(bid)) != sim.bases.base_of_agent(a)):
			continue
		var n := 0
		for aid in sim.state["agents"]:
			var x: Dictionary = sim.state["agents"][aid]
			if x["state"] == "alive" and is_child(x) and int(x["bed"]) == int(bid):
				n += 1
		if n < cap:
			a["bed"] = int(bid)
			return int(bid)
	return -1

# ---------------------------------------------------------------- children
## Spawns a child of these parents at pos in building bld (-1 outside).
func spawn_child(parents: Array, pos: Vector2, bld: int) -> Dictionary:
	var a: Dictionary = sim.agents.spawn("child", sim.next_name(), pos, bld)
	a["kind"] = "child"
	a["parents"] = parents.duplicate()
	a["family"] = int(parents[0]) if not parents.is_empty() else int(a["id"])
	a["child_at"] = int(sim.state["tick"])
	a["hunger"] = 20.0
	a["thirst"] = 20.0
	sim.people.invalidate(int(a["id"]))
	sim.people._id_cache.erase(int(a["id"]))
	sim.people._rank_sig = -1
	if not parents.is_empty():
		var p: Dictionary = sim.state["agents"].get(int(parents[0]), {})
		if not p.is_empty():
			a["bed"] = int(p["bed"])
			sim.people.rec_w(a)["unit"] = int(sim.people.rec_of(int(p["id"])).get("unit", -1))
	_w()["school"][int(a["id"])] = {}
	return a

## Command "adopt" {agent}: the person and their partner adopt a child through a medical bay.
func cmd_adopt(p: Dictionary) -> Dictionary:
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	if a.is_empty() or a["state"] != "alive" or String(a.get("kind", "")) == "visitor" or is_child(a):
		return {"ok": false, "code": "invalid", "text": "Only a colonist can adopt."}
	var pid: int = sim.relations.partner_of(int(a["id"]))
	var st: String = String(sim.relations.rel_of(int(a["id"]), pid).get("status", "")) if pid != -1 else ""
	if st != "partners" and st != "married":
		return {"ok": false, "code": "refused", "text": "Only partners or a married couple can adopt."}
	var home: Dictionary = sim.state["buildings"].get(int(a["bed"]), {})
	var u: int = int(sim.people.rec_of(int(a["id"])).get("unit", -1))
	if home.is_empty() or u < 0 or u >= sim.floors.units(home).size():
		return {"ok": false, "code": "refused", "text": "They need a family home with a free bunk first."}
	var kids := 0
	for c in unit_people(int(home["id"]), u):
		if is_child(sim.state["agents"][c]):
			kids += 1
	var v: Dictionary = _w()
	for k in v["adopt"]:
		if int(v["adopt"][k]["a"]) == int(a["id"]) or int(v["adopt"][k]["b"]) == int(a["id"]):
			kids += 1
	if kids >= int(sim.floors.units(home)[u].get("child_beds", 0)):
		return {"ok": false, "code": "full", "text": "No free bunk in their home."}
	var bay := -1
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if int(sim.bd(b).get("treatment_beds", 0)) > 0 and b["state"] == "active" and (sim.bases.count() < 2 or sim.bases.base_of(int(id)) == sim.bases.home_of(a)):
			if bay == -1 or int(id) < bay:
				bay = int(id)
	if bay == -1:
		return {"ok": false, "code": "refused", "text": "An adoption needs a medical bay."}
	var seq: int = int(v.get("adopt_seq", 0)) + 1
	v["adopt_seq"] = seq
	v["adopt"][seq] = {"a": int(a["id"]), "b": pid, "at": int(sim.state["tick"]) + int(float(cfg()["adopt_days"]) * float(_day())), "bld": bay}
	sim.people.note(a, "Asked to adopt a child.")
	return {"ok": true, "code": "ok", "text": "The child comes to the medical bay in %d day(s)." % int(ceil(float(cfg()["adopt_days"])))}

## Once a game second (sim.step phase 9): adoptions arrive, children grow up.
func tick_second() -> void:
	var now: int = int(sim.state["tick"])
	var v: Dictionary = sim.state.get("v5", {})
	var ad: Dictionary = v.get("adopt", {})
	if not ad.is_empty():
		var keys: Array = ad.keys()
		keys.sort()
		for k in keys:
			var r: Dictionary = ad[k]
			if now < int(r["at"]):
				continue
			ad.erase(k)
			var pa: Dictionary = sim.state["agents"].get(int(r["a"]), {})
			var pb: Dictionary = sim.state["agents"].get(int(r["b"]), {})
			var bay: Dictionary = sim.state["buildings"].get(int(r["bld"]), {})
			if pa.is_empty() or pa["state"] != "alive" or bay.is_empty():
				continue
			var parents: Array = [int(pa["id"])]
			if not pb.is_empty() and pb["state"] == "alive":
				parents.append(int(pb["id"]))
			var ch: Dictionary = spawn_child(parents, sim.nav.slot_pos(bay, int(pa["id"])), int(bay["id"]))
			for pid in parents:
				var pp: Dictionary = sim.state["agents"][pid]
				sim.people.add_mod(pp, {"kind": "new_child", "text": "A new child at home", "comp": "social", "sat": 15.0, "att": 4.0, "days": 3.0})
				sim.people.note(pp, "Adopted %s." % String(ch["name"]))
			sim.log_event("adoption", "%s adopted %s." % [" and ".join(parents.map(func(x): return String(sim.state["agents"][x]["name"]))), String(ch["name"])], parents + [int(ch["id"]), int(bay["id"])], 1)
	if (now / _hz()) % 10 != 3:
		return
	var grow: int = int(float(cfg()["child_grow_days"]) * float(_day()))
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and is_child(a) and now - int(a.get("child_at", 0)) >= grow:
			grow_up(a)

## A child becomes an adult colonist: the role of the best school subject, school points as skills.
func grow_up(a: Dictionary) -> void:
	var sch: Dictionary = sim.state.get("v5", {}).get("school", {}).get(int(a["id"]), {})
	var best := ""
	var bv := -1.0
	var keys: Array = sch.keys()
	keys.sort()
	for k in keys:
		if float(sch[k]) > bv:
			bv = float(sch[k])
			best = String(k)
	var roles: Dictionary = cfg()["role_of_skill"]
	var role: String = String(roles.get(best, "technician"))
	a["kind"] = "human"
	a["role"] = role
	a["age_set"] = int(cfg()["grown_age"])
	a["grown"] = int(sim.state["tick"])
	var r: Dictionary = sim.people.rec_w(a)
	if not r.has("skill_bonus"):
		r["skill_bonus"] = {}
	for k in keys:
		r["skill_bonus"][k] = int(r["skill_bonus"].get(k, 0)) + int(round(float(sch[k])))
	if sim.state.get("v5", {}).has("school"):
		sim.state["v5"]["school"].erase(int(a["id"]))
	sim.people._id_cache.erase(int(a["id"]))
	sim.people.invalidate(int(a["id"]))
	sim.people._rank_sig = -1
	sim.agents._beds_tick = -1
	sim.alive_changed()
	sim.people.note(a, "Grew up and joined the crew as a %s." % String(sim.bal["role_names"].get(role, role)).to_lower())
	sim.log_event("grew_up", "%s grew up and joins the crew as a %s." % [String(a["name"]), String(sim.bal["role_names"].get(role, role)).to_lower()], [int(a["id"])], 1)

## A child's day (people.duty_think): school at an academy by day, else play (false: the ordinary
## rules, leisure first, decide).
func child_think(a: Dictionary) -> bool:
	# School hours: a share of the daylight (content "school_day" [from, to]).
	var dtm: float = sim.util.day_time()
	var dl: float = float(sim.planet["daylight_seconds"])
	var sd: Array = cfg()["school_day"]
	if dtm < dl * float(sd[0]) or dtm >= dl * float(sd[1]):
		return false
	var acad: int = sim.education.school_for(a)
	if acad == -1:
		return false
	return sim.agents._start_personal(a, "class", acad, [{"op": "class", "t": float(sim.content["society"]["education"]["class_s"])}], "At school", -1)

## School points for a child in class (education.tick): the child's best subjects by aptitude.
func school_second(a: Dictionary, pts: float) -> void:
	var v: Dictionary = _w()
	var sch: Dictionary = v["school"].get(int(a["id"]), {})
	var skills: Array = sim.content["people"]["skills"]
	var k1: String = String(skills[int(_h(int(a["id"]), 1) * skills.size()) % skills.size()])
	var k2: String = String(skills[int(_h(int(a["id"]), 2) * skills.size()) % skills.size()])
	sch[k1] = snappedf(float(sch.get(k1, 0.0)) + pts * 0.6, 0.001)
	sch[k2] = snappedf(float(sch.get(k2, 0.0)) + pts * 0.4, 0.001)
	v["school"][int(a["id"])] = sch
