extends RefCounted
## Venues, the leisure economy, tourism and the super dome's build stages (docs/V5_DESIGN.md
## sections 8 and 9). Numbers: content/society.json "leisure".
##
## A venue belongs to a building with `venues` in its def: the retail module ("shop"), the park
## ("park") and the super dome (16 venues). Its goods are kept in the building's goods store
## (b.inv_in, filled by carriers: jobs._gen_venues). A venue is open when the building is active and
## powered, its staff is there (state.v5.staff {"bid:venue": [agent ids]}; the job is on the agent:
## a.job, a.job_venue) and a shop has goods. A leisure visit (agents "rec") at a venue building picks
## an open venue (a.venue), uses one unit of its goods (rec_use of the visits), gives the visit's
## quality to satisfaction (comfort), and a tourist pays for it (credits "tourism"). Colonists do not
## use money. Staff are proposed by SIM (the most social people of roles with 3 or more people,
## at most staff_share of a role) and can be set with the command "staff".

const Rng = preload("res://sim/rng.gd")

var sim
var _open_sec := -1
var _open := {}               # "bid:venue" -> bool (derived, per game second)

func _init(s) -> void:
	sim = s

func reset() -> void:
	_open_sec = -1
	_open = {}

func cfg() -> Dictionary:
	return sim.content["society"]["leisure"]

func vcfg(vid: String) -> Dictionary:
	return cfg()["venues"].get(vid, {})

func _h(x: int, y: int) -> float:
	return Rng.hash2(x, y, int(sim.state.get("seed", 1)) ^ 0x1E15)

func _hz() -> int:
	return int(sim.bal["tick_hz"])

func _staff_w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("staff"):
		v["staff"] = {}
	return v["staff"]

func staff_r() -> Dictionary:
	return sim.state.get("v5", {}).get("staff", {})

## The venue ids of a building record or def id: [] for an ordinary structure.
func venue_ids(b) -> Array:
	var def: Dictionary = sim.bdef(b if typeof(b) == TYPE_STRING else String(b["def"]))
	var out: Array = []
	for v in def.get("venues", []):
		out.append(String(v["id"]))
	return out

func venue_floor(b: Dictionary, vid: String) -> int:
	for v in sim.bdef(String(b["def"])).get("venues", []):
		if String(v["id"]) == vid:
			return int(v.get("floor", 0))
	return 0

func is_venue_building(b: Dictionary) -> bool:
	return sim.bdef(String(b["def"])).has("venues")

## Ids of the buildings with venues (any state), ascending; made again when the number of
## structures changes or another game is loaded.
var _vb: Array = []
var _vb_n := -1
var _vb_state = null

func venue_buildings() -> Array:
	var blds: Dictionary = sim.state["buildings"]
	# The key: the number of structures and the placement counters of the venue defs (a new venue
	# building always moves a counter, so the list is exact).
	var n: int = blds.size() * 1000003
	var ctr: Dictionary = sim.state.get("counters", {})
	for d in ["retail", "park", "super_dome"]:
		n += int(ctr.get(d, 0)) * 7919
	if n != _vb_n or not is_same(_vb_state, blds):
		_vb_n = n
		_vb_state = blds
		_vb = []
		for id in blds:
			if is_venue_building(blds[id]):
				_vb.append(int(id))
		_vb.sort()
	return _vb

# ---------------------------------------------------------------- open, stock, staff
func stock_inv(b: Dictionary) -> int:
	return int(b.get("inv_in", -1))

func stock_of(b: Dictionary, vid: String) -> Dictionary:
	var out := {}
	var inv: int = stock_inv(b)
	for item in vcfg(vid).get("items", []):
		out[item] = sim.inv.count(inv, String(item)) if inv != -1 else 0
	return out

func staff_of(bid: int, vid: String) -> Array:
	var out: Array = []
	for aid in staff_r().get("%d:%s" % [bid, vid], []):
		var a: Dictionary = sim.state["agents"].get(int(aid), {})
		if not a.is_empty() and a["state"] == "alive":
			out.append(int(aid))
	return out

func _staff_ok(bid: int, vid: String) -> bool:
	var need: int = int(vcfg(vid).get("staff", 0))
	if need <= 0:
		return true
	var n := 0
	for aid in staff_of(bid, vid):
		var a: Dictionary = sim.state["agents"][aid]
		if not a.has("jailed") and not a.has("v5_nowork"):
			n += 1
	return n >= need

## "" when the venue is open, else the reason (for the interface).
func why_closed(b: Dictionary, vid: String) -> String:
	if b["state"] != "active":
		return "Not finished."
	if not bool(b.get("powered", false)):
		return "No power."
	if not _staff_ok(int(b["id"]), vid):
		return "No staff."
	var items: Array = vcfg(vid).get("items", [])
	if not items.is_empty():
		var any := false
		for n in stock_of(b, vid).values():
			any = any or int(n) > 0
		if not any:
			return "No goods."
	return ""

func is_open(b: Dictionary, vid: String) -> bool:
	var sec: int = int(sim.state["tick"]) / _hz()
	if sec != _open_sec:
		_open_sec = sec
		_open = {}
	var key: String = "%d:%s" % [int(b["id"]), vid]
	if not _open.has(key):
		_open[key] = why_closed(b, vid) == ""
	return bool(_open[key])

## Rows for the interface: [{id, name, floor, open, why, staff [ids], need_staff, job, items, stock
## {item: n}, price, fee, quality, adults_only, act}].
func venues(b: Dictionary) -> Array:
	var out: Array = []
	for v in sim.bdef(String(b["def"])).get("venues", []):
		var vid: String = String(v["id"])
		var c: Dictionary = vcfg(vid)
		out.append({"id": vid, "name": String(c.get("name", vid)), "floor": int(v.get("floor", 0)), "open": why_closed(b, vid) == "", "why": why_closed(b, vid),
			"staff": staff_of(int(b["id"]), vid), "need_staff": int(c.get("staff", 0)), "job": String(c.get("job", "")), "items": c.get("items", []),
			"stock": stock_of(b, vid), "price": int(c.get("price", 0)), "fee": int(c.get("fee", 0)), "quality": int(c.get("quality", 0)),
			"adults_only": bool(v.get("adults_only", c.get("adults_only", false))), "act": String(c.get("act", ""))})
	return out

## Where a person is at a venue now (RENDER): {building, venue, floor, act} or {}.
func venue_of(a: Dictionary) -> Dictionary:
	var vid: String = String(a.get("venue", ""))
	if vid == "" or a["where"] != "in":
		return {}
	var b: Dictionary = sim.state["buildings"].get(int(a["bld"]), {})
	if b.is_empty() or not venue_ids(b).has(vid):
		return {}
	var act: String = String(vcfg(vid).get("act", ""))
	if String(a.get("plan_kind", "")) == "staff":
		act = "work"
	return {"building": int(b["id"]), "venue": vid, "floor": venue_floor(b, vid), "act": act}

# ---------------------------------------------------------------- visits
## Extra attraction of a building for a leisure visit (agents._try_rec): the best open venue's quality.
func rec_bonus(b: Dictionary, a: Dictionary) -> float:
	if not is_venue_building(b):
		return 0.0
	var best := 0.0
	var child: bool = String(a.get("kind", "")) == "child"
	for v in sim.bdef(String(b["def"])).get("venues", []):
		var vid: String = String(v["id"])
		if child and bool(v.get("adults_only", vcfg(vid).get("adults_only", false))):
			continue
		if is_open(b, vid):
			best = maxf(best, float(vcfg(vid).get("quality", 0)))
	if String(a.get("kind", "")) == "visitor":
		best *= 2.0
	return best

## Chooses the open venue of building bid for a visit (a.venue); "" when none is open.
func pick_venue(a: Dictionary, bid: int) -> String:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	a.erase("venue")
	if b.is_empty() or not is_venue_building(b):
		return ""
	var child: bool = String(a.get("kind", "")) == "child"
	var cands: Array = []
	var total := 0.0
	for v in sim.bdef(String(b["def"])).get("venues", []):
		var vid: String = String(v["id"])
		if child and bool(v.get("adults_only", vcfg(vid).get("adults_only", false))):
			continue
		if not is_open(b, vid):
			continue
		var w: float = 1.0 + float(vcfg(vid).get("quality", 0))
		if String(a.get("kind", "")) == "visitor" and (int(vcfg(vid).get("price", 0)) > 0 or int(vcfg(vid).get("fee", 0)) > 0):
			w *= 2.0
		if sim.people.has_trait(a, "party-animal") and (vid == "club" or vid == "bar"):
			w *= 3.0
		cands.append([vid, w])
		total += w
	if cands.is_empty():
		return ""
	var r: float = _h(int(a["id"]), int(sim.state["tick"]) / _hz()) * total
	var pick: String = String(cands[0][0])
	for c in cands:
		r -= float(c[1])
		if r < 0.0:
			pick = String(c[0])
			break
	a["venue"] = pick
	return pick

## The end of a leisure visit (agents._do_timed "rec"): goods used, quality, payment, eggs, dates.
func on_rec_end(a: Dictionary) -> void:
	var vid: String = String(a.get("venue", ""))
	var b: Dictionary = sim.state["buildings"].get(int(a["bld"]), {})
	if vid == "" or b.is_empty() or not venue_ids(b).has(vid):
		return
	var c: Dictionary = vcfg(vid)
	var now: int = int(sim.state["tick"])
	var items: Array = c.get("items", [])
	var used := ""
	if not items.is_empty() and _h(int(a["id"]) + 7, now) < float(cfg()["rec_use"]):
		var inv: int = stock_inv(b)
		var start: int = int(_h(int(a["id"]), now + 3) * items.size())
		for i in items.size():
			var item: String = String(items[(start + i) % items.size()])
			if inv != -1 and sim.inv.consume(inv, item, 1, "used"):
				used = item
				sim.stat_add("consumed", item, 1)
				break
	if items.is_empty() or used != "":
		a["rec_q"] = float(c.get("quality", 0))
		a["rec_q_t"] = now
	if String(a.get("kind", "")) == "visitor":
		var pay: int = int(c.get("price", 0)) if used != "" else int(c.get("fee", 0))
		if pay > 0:
			sim.traffic.earn(pay, "tourism")
			if a.has("visit"):
				a["visit"]["paid"] = int(a["visit"].get("paid", 0)) + pay
				a["visit"]["spent"] = int(a["visit"].get("spent", 0)) + pay
			sim.stat_add("tourism", "", pay)
	if vid == "gaming_lounge" and sim.get("eggs") != null:
		sim.eggs.on_arcade(a)
	_date_check(a, b, vid, now)

## Two partners at the same venue: a date (one story a pair a day).
func _date_check(a: Dictionary, b: Dictionary, vid: String, now: int) -> void:
	if sim.get("relations") == null:
		return
	var pid: int = sim.relations.partner_of(int(a["id"]))
	if pid == -1:
		return
	var p: Dictionary = sim.state["agents"].get(pid, {})
	if p.is_empty() or p["state"] != "alive" or int(p["bld"]) != int(b["id"]) or String(p.get("venue", "")) != vid:
		return
	var day: int = now / (int(sim.bal["day_length"]) * _hz())
	var r: Dictionary = sim.relations._rel_w(a, p)
	if int(r.get("date_day", -1)) == day:
		return
	r["date_day"] = day
	r["aff"] = clampf(float(r["aff"]) + 4.0, -100.0, 100.0)
	sim.log_event("date", "%s and %s had a date at the %s." % [String(a["name"]), String(p["name"]), String(vcfg(vid).get("name", vid)).to_lower()], [int(a["id"]), pid, int(b["id"])], 0, {"place": int(b["id"])})

# ---------------------------------------------------------------- staff
## A member of staff on duty goes to the venue and works a shift (60 s at a time). false at night,
## when tired, or without a valid post (the job is dropped).
func staff_think(a: Dictionary) -> bool:
	var key: String = String(a.get("job_venue", ""))
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2:
		_drop_job(a)
		return false
	var bid: int = int(parts[0])
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty() or b["state"] != "active" or not staff_r().get(key, []).has(int(a["id"])):
		_drop_job(a)
		return false
	if sim.util.is_night() or float(a["fatigue"]) > 70.0:
		return false
	var vid: String = parts[1]
	var name: String = String(vcfg(vid).get("name", vid)).to_lower()
	if sim.agents._start_personal(a, "staff", bid, [{"op": "staff", "t": 60.0}], "Working at the %s" % name, -1):
		a["venue"] = vid
		return true
	return false

func _drop_job(a: Dictionary) -> void:
	var key: String = String(a.get("job_venue", ""))
	if key != "" and staff_r().has(key):
		(_staff_w()[key] as Array).erase(int(a["id"]))
	a.erase("job")
	a.erase("job_venue")

## Command "staff" {building, venue, agent}: agent -1 clears the venue's staff.
func cmd_staff(p: Dictionary) -> Dictionary:
	var bid: int = int(p.get("building", -1))
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	var vid: String = String(p.get("venue", ""))
	if b.is_empty() or not venue_ids(b).has(vid):
		return {"ok": false, "code": "invalid", "text": "Choose a venue."}
	var key: String = "%d:%s" % [bid, vid]
	var aid: int = int(p.get("agent", -1))
	var st: Dictionary = _staff_w()
	if aid == -1:
		for old in st.get(key, []):
			var o: Dictionary = sim.state["agents"].get(int(old), {})
			if not o.is_empty():
				o.erase("job")
				o.erase("job_venue")
		st.erase(key)
		return {"ok": true, "code": "ok", "text": "No staff at the %s." % String(vcfg(vid).get("name", vid)).to_lower()}
	var a: Dictionary = sim.state["agents"].get(aid, {})
	if a.is_empty() or a["state"] != "alive" or String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
		return {"ok": false, "code": "invalid", "text": "Only a colonist can work there."}
	if sim.bases.count() > 1 and sim.bases.base_of(bid) != sim.bases.home_of(a):
		return {"ok": false, "code": "refused", "text": "That venue is at another base."}
	_drop_job(a)
	var need: int = maxi(1, int(vcfg(vid).get("staff", 1)))
	var arr: Array = st.get(key, [])
	while arr.size() >= need:
		var gone: Dictionary = sim.state["agents"].get(int(arr.pop_front()), {})
		if not gone.is_empty():
			gone.erase("job")
			gone.erase("job_venue")
	arr.append(aid)
	st[key] = arr
	a["job"] = String(vcfg(vid).get("job", "staff"))
	a["job_venue"] = key
	sim.people.note(a, "New job: %s at the %s." % [String(a["job"]), String(vcfg(vid).get("name", vid)).to_lower()])
	return {"ok": true, "code": "ok", "text": "%s works at the %s." % [String(a["name"]), String(vcfg(vid).get("name", vid)).to_lower()]}

## SIM's staff proposal: venues without staff get the most social people of large roles.
func _auto_staff() -> void:
	var blds: Array = []
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "active" and is_venue_building(b):
			blds.append(int(id))
	if blds.is_empty():
		return
	blds.sort()
	var st: Dictionary = _staff_w()
	# Drop staff who died, left or moved to another base.
	for key in st.keys():
		var keep: Array = []
		var bid0: int = int(String(key).split(":")[0])
		for aid in st[key]:
			var a: Dictionary = sim.state["agents"].get(int(aid), {})
			if not a.is_empty() and a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("job_venue", "")) == String(key) \
					and (sim.bases.count() < 2 or sim.bases.home_of(a) == sim.bases.base_of(bid0)) and sim.state["buildings"].has(bid0):
				keep.append(int(aid))
		if keep.is_empty():
			st.erase(key)
		else:
			st[key] = keep
	var share: float = float(cfg()["staff_share"])
	for bid in blds:
		var b: Dictionary = sim.state["buildings"][bid]
		var base: int = sim.bases.base_of(bid) if sim.bases.count() > 0 else -1
		for vid in venue_ids(b):
			var need: int = int(vcfg(vid).get("staff", 0))
			var key2: String = "%d:%s" % [bid, vid]
			if need <= 0 or st.get(key2, []).size() >= need:
				continue
			var pick: Dictionary = _candidate(base, share)
			if pick.is_empty():
				return
			var arr: Array = st.get(key2, [])
			arr.append(int(pick["id"]))
			st[key2] = arr
			pick["job"] = String(vcfg(vid).get("job", "staff"))
			pick["job_venue"] = key2

func _candidate(base: int, share: float) -> Dictionary:
	var by_role := {}
	var staff_by_role := {}
	var pool: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or String(a.get("kind", "")) == "visitor" or String(a.get("kind", "")) == "child":
			continue
		if base != -1 and sim.bases.count() > 1 and sim.bases.home_of(a) != base:
			continue
		var role: String = String(a["role"])
		by_role[role] = int(by_role.get(role, 0)) + 1
		if a.has("job"):
			staff_by_role[role] = int(staff_by_role.get(role, 0)) + 1
			continue
		if not ["grower", "operator", "technician", "scientist"].has(role):
			continue
		if ["commander", "captain", "first_hand"].has(String(sim.people.rank(a)["rank"])):
			continue
		pool.append(a)
	var best: Dictionary = {}
	var best_v := -1
	for a in pool:
		var role2: String = String(a["role"])
		if int(by_role.get(role2, 0)) < 3 or int(staff_by_role.get(role2, 0)) + 1 > int(floor(float(by_role[role2]) * share)):
			continue
		var sk: Dictionary = sim.people.skills(a)
		var v: int = int(sk["social"]) + int(sk["cooking"])
		if v > best_v:
			best_v = v
			best = a
	return best

# ---------------------------------------------------------------- goods
## For the job board: [[goods store, {item: units wanted}, building id, pos]] of venue buildings.
func wants() -> Array:
	var out: Array = []
	for id in venue_buildings():
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] != "active" or bool(b["demolish"]) or stock_inv(b) == -1 or sim.inv.free_space(stock_inv(b)) <= 0:
			continue
		var target: int = int(cfg()["dome_stock_target"]) if String(b["def"]) == "super_dome" else int(cfg()["stock_target"])
		var w := {}
		for vid in venue_ids(b):
			if not _staff_ok(int(id), vid):
				continue
			for item in vcfg(vid).get("items", []):
				w[String(item)] = target
		if not w.is_empty():
			out.append([stock_inv(b), w, int(id), b["pos"]])
	return out

## Units of these items the colony can use at a base (stores, goods stores, machine outputs).
func count_stock(base_id: int, items: Array) -> int:
	var n := 0
	for inv_id in _stock_invs(base_id):
		for item in items:
			n += maxi(0, sim.inv.available(inv_id, String(item)))
	return n

## Uses n units of these items (in that order of preference) from the base; returns the units used.
func take_stock(base_id: int, items: Array, n: int, reason: String) -> int:
	var got := 0
	for item in items:
		for inv_id in _stock_invs(base_id):
			while got < n and sim.inv.available(inv_id, String(item)) > 0:
				if not sim.inv.consume(inv_id, String(item), 1, reason):
					break
				sim.stat_add("consumed", String(item), 1)
				got += 1
			if got >= n:
				return got
	return got

func _stock_invs(base_id: int) -> Array:
	var out: Array = []
	var ids: Array = sim.state["inventories"].keys()
	ids.sort()
	for inv_id in ids:
		var inv: Dictionary = sim.state["inventories"][inv_id]
		if inv["ot"] != "b" or not ["store", "out", "in"].has(String(inv["role"])):
			continue
		var b: Dictionary = sim.state["buildings"].get(int(inv["oid"]), {})
		if b.is_empty() or (b["state"] != "active" and b["state"] != "broken"):
			continue
		if String(inv["role"]) == "in" and not is_venue_building(b):
			continue
		if base_id != -1 and sim.bases.count() > 1 and sim.bases.base_of(int(inv["oid"])) != base_id:
			continue
		out.append(int(inv_id))
	return out

## Small ads for the Rag: goods in stock at open shops.
func ad_lines() -> Array:
	var out: Array = []
	var ids: Array = sim.state["buildings"].keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] != "active" or not is_venue_building(b):
			continue
		for vid in venue_ids(b):
			if out.size() >= 3:
				return out
			var st: Dictionary = stock_of(b, vid)
			for item in st:
				if int(st[item]) > 0 and is_open(b, vid):
					out.append("%s IN STOCK at the %s, %s. Treat yourself!" % [sim.items.name_of(String(item)).to_upper(), String(vcfg(vid).get("name", vid)).to_lower(), String(b["name"])])
					break
	return out

# ---------------------------------------------------------------- tourism and the dome
## Tourists a liner brings are multiplied by this when a super dome is open (3 venues or more).
func tourist_mult() -> float:
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["def"]) == "super_dome" and b["state"] == "active":
			var n := 0
			for vid in venue_ids(b):
				if is_open(b, vid):
					n += 1
			if n >= 3:
				return float(cfg()["dome_tourist_mult"])
	return 1.0

## The build stage of a super dome (RENDER draws it): {index (-1 site, 0..count-1 building, count
## done), id, name, count, progress (0..1 within the stage)}.
func dome_stage(b: Dictionary) -> Dictionary:
	var stages: Array = sim.bdef(String(b["def"])).get("build_stages", [])
	var n: int = stages.size()
	if n == 0:
		return {}
	match String(b["state"]):
		"blueprint":
			return {"index": -1, "id": "site", "name": "Site", "count": n, "progress": 0.0}
		"building":
			var f: float = clampf(float(b["progress"]) / maxf(1.0, float(b["work_total"])), 0.0, 0.9999) * float(n)
			var i: int = int(f)
			return {"index": i, "id": String(stages[i]), "name": String(stages[i]).replace("_", " ").capitalize(), "count": n, "progress": snappedf(f - float(i), 0.001)}
	return {"index": n, "id": "done", "name": "Finished", "count": n, "progress": 1.0}

## Once a game second (sim.step phase 9): dome stages are logged, staff proposed every 30 s.
func tick_second() -> void:
	var sec: int = int(sim.state["tick"]) / _hz()
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["def"]) != "super_dome" or b["state"] != "building":
			continue
		var st: Dictionary = dome_stage(b)
		var i: int = int(st["index"])
		if i > int(b.get("stage_i", 0)):
			var stages: Array = sim.bdef("super_dome")["build_stages"]
			b["stage_i"] = i
			sim.log_event("dome_stage", "%s: %s is done." % [String(b["name"]), String(stages[i - 1]).replace("_", " ")], [int(id)], 1, {"stage": i})
	if sec % 30 == 7:
		_auto_staff()
