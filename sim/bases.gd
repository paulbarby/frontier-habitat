extends RefCounted
## Bases (docs/V4_DESIGN.md section 2). A base is a group of structures joined by corridors
## and cables, with a core: the lander, or an outpost core deployed from an Outpost Kit. A
## base has an id and a name; alerts, stocks and charts can be filtered by it.
##
## state.bases = {"list": {id: {id, name, core, founded}}, "next": n}
## Which base a structure belongs to is DERIVED (never saved): a structure joined to a core
## by corridors and cables belongs to that core's base; any other structure belongs to the
## base whose core is nearest. The answer is kept until the structures or links change.

var sim
var _of := {}          # structure id -> base id
var _key := ""
var _at := {}          # point -> base id (see base_at)
var _at_key := ""

func _init(s) -> void:
	sim = s

static func fresh_state() -> Dictionary:
	return {"list": {}, "next": 1}

func bs() -> Dictionary:
	if not sim.state.has("bases"):
		sim.state["bases"] = fresh_state()
	return sim.state["bases"]

## The first base, round the lander (new games and migrated saves).
func ensure_first() -> void:
	var b: Dictionary = bs()
	if not b["list"].is_empty():
		return
	var lid: int = int(sim.state.get("lander_id", -1))
	if lid == -1:
		return
	_add(lid, "Landing base")

func _add(core_id: int, name: String) -> int:
	var b: Dictionary = bs()
	var id: int = int(b["next"])
	b["next"] = id + 1
	b["list"][id] = {"id": id, "name": name, "core": core_id, "founded": int(sim.state["tick"])}
	_key = ""
	return id

func count() -> int:
	return (bs()["list"] as Dictionary).size()

func ids() -> Array:
	var out: Array = (bs()["list"] as Dictionary).keys()
	out.sort()
	return out

func get_base(id: int) -> Dictionary:
	return bs()["list"].get(id, {})

func name_of(id: int) -> String:
	return String(get_base(id).get("name", ""))

## The core structure (lander or outpost core) of a base, {} if it is gone.
func core_of(id: int) -> Dictionary:
	return sim.state["buildings"].get(int(get_base(id).get("core", -1)), {})

## Is this structure a core (self-contained shelter with a hatch)?
func is_core(b: Dictionary) -> bool:
	return bool(sim.bdef(b["def"]).get("core", false))

# ---------------------------------------------------------------- membership
func _refresh() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var key: String = "%d:%d:%d:%d" % [blds.size(), int(sim.state.get("next_id", 0)), count(), int(sim.state["rev"]["power"])]
	if key == _key:
		return
	_key = key
	_at = {}
	_of = {}
	var cores := {}           # core structure id -> base id
	for bid in ids():
		var c: int = int(get_base(bid).get("core", -1))
		if blds.has(c):
			cores[c] = bid
	# Components of the corridor + cable graph (links in any state count: a plan belongs
	# where it is planned).
	var seen := {}
	var sids: Array = blds.keys()
	sids.sort()
	for sid in sids:
		var s0: Dictionary = blds[sid]
		if s0["kind"] == "link" or seen.has(sid):
			continue
		var comp: Array = []
		var stack: Array = [sid]
		seen[sid] = true
		var base_id := -1
		while not stack.is_empty():
			var x: int = stack.pop_back()
			comp.append(x)
			if cores.has(x) and base_id == -1:
				base_id = int(cores[x])
			for lid in sim.topo.links_of.get(x, []):
				var l: Dictionary = blds.get(lid, {})
				if l.is_empty():
					continue
				for e in [int(l["a"]), int(l["b"])]:
					if blds.has(e) and not seen.has(e):
						seen[e] = true
						stack.append(e)
		if base_id == -1:
			base_id = _nearest_base(blds[comp[0]].get("pos", Vector2.ZERO), cores)
		for x in comp:
			_of[x] = base_id
			for lid in sim.topo.links_of.get(x, []):
				_of[int(lid)] = base_id

func _nearest_base(p: Vector2, cores: Dictionary) -> int:
	var best := -1
	var best_d := 1e18
	var blds: Dictionary = sim.state["buildings"]
	var cids: Array = cores.keys()
	cids.sort()
	for c in cids:
		var d: float = (blds[c]["pos"] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = int(cores[c])
	return best

## The base of a structure (or link), -1 when there is no base.
func base_of(bid: int) -> int:
	if count() == 0:
		return -1
	_refresh()
	return int(_of.get(bid, -1))

## The base at a place: the base of the nearest structure within 250 m, else the base whose
## core is nearest.
func base_at(p: Vector2) -> int:
	if count() == 0:
		return -1
	if count() == 1:
		return int(ids()[0])
	_refresh()
	# The answer for a point stays the same while the structures and links stay the same (the key of
	# _refresh), so the scan of every structure is done once for a point (the job board asks for the
	# same few kitchen and store positions every second: 13 scans of 169 structures a second).
	if _at_key != _key or _at.size() > 512:
		_at = {}
		_at_key = _key
	if _at.has(p):
		return int(_at[p])
	var r: int = _base_at_scan(p)
	_at[p] = r
	return r

func _base_at_scan(p: Vector2) -> int:
	var blds: Dictionary = sim.state["buildings"]
	var best := -1
	var best_d := 250.0 * 250.0
	for sid in blds:
		var s: Dictionary = blds[sid]
		if s["kind"] == "link" or s["def"] == "meridian":
			continue
		var d: float = (s["pos"] as Vector2).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = int(_of.get(sid, -1))
	if best != -1:
		return best
	var cores := {}
	for bid in ids():
		var c: int = int(get_base(bid).get("core", -1))
		if blds.has(c):
			cores[c] = bid
	return _nearest_base(p, cores)

## The base a colonist is at now (the room it is in, or where it stands outside).
func base_of_agent(a: Dictionary) -> int:
	if count() <= 1:
		return int(ids()[0]) if count() == 1 else -1
	if a["where"] != "out" and int(a["bld"]) != -1:
		var b: int = base_of(int(a["bld"]))
		if b != -1:
			return b
	return base_at(a["pos"])

## A colonist's home base: the base of its bed, else where it is.
func home_of(a: Dictionary) -> int:
	if int(a.get("bed", -1)) != -1 and sim.state["buildings"].has(int(a["bed"])):
		return base_of(int(a["bed"]))
	return base_of_agent(a)

# ---------------------------------------------------------------- filters
## Rows for the interface: [{id, name, core, pos, structures, colonists, beds}] by id.
func list() -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	_refresh()
	var n_struct := {}
	var beds := {}
	for sid in blds:
		var s: Dictionary = blds[sid]
		if s["kind"] == "link":
			continue
		var b: int = int(_of.get(sid, -1))
		n_struct[b] = int(n_struct.get(b, 0)) + 1
		if s["state"] == "active":
			beds[b] = int(beds.get(b, 0)) + int(sim.bd(s).get("beds", 0))
	var people := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] != "visitor":
			var hb: int = home_of(a)
			people[hb] = int(people.get(hb, 0)) + 1
	for id in ids():
		var core: Dictionary = core_of(id)
		out.append({"id": id, "name": name_of(id), "core": int(get_base(id)["core"]), "pos": core.get("pos", Vector2.ZERO),
			"structures": int(n_struct.get(id, 0)), "colonists": int(people.get(id, 0)), "beds": int(beds.get(id, 0))})
	return out

## Item totals of one base (the colony's `inv.totals()` shape): its structures' inventories,
## ground piles at the base, and what its colonists carry.
func totals(base_id: int) -> Dictionary:
	var out := {}
	var invs: Dictionary = sim.state["inventories"]
	for inv_id in invs:
		var inv: Dictionary = invs[inv_id]
		if inv["role"] == "site" or inv["role"] == "upg" or inv["role"] == "ship" or inv["role"] == "trade":
			continue
		var b := -1
		match String(inv["ot"]):
			"b":
				b = base_of(int(inv["oid"]))
			"a":
				var ag: Dictionary = sim.state["agents"].get(int(inv["oid"]), {})
				b = -1 if ag.is_empty() else base_of_agent(ag)
			_:
				b = base_at(inv.get("pos", Vector2.ZERO))
		if b != base_id:
			continue
		for res in inv["items"]:
			if not out.has(res):
				out[res] = {"total": 0, "reserved": 0, "carried": 0}
			out[res]["total"] += int(inv["items"][res])
			out[res]["reserved"] += int(inv["held_out"].get(res, 0))
			if inv["role"] == "carry":
				out[res]["carried"] += int(inv["items"][res])
	return out

## The base an alert is about (its first structure or colonist), -1 for the whole colony.
func base_of_entities(ents: Array) -> int:
	if count() <= 1:
		return int(ids()[0]) if count() == 1 else -1
	var blds: Dictionary = sim.state["buildings"]
	for e in ents:
		if typeof(e) != TYPE_INT and typeof(e) != TYPE_FLOAT:
			continue
		var id: int = int(e)
		if blds.has(id):
			return base_of(id)
		if sim.state["agents"].has(id):
			return base_of_agent(sim.state["agents"][id])
	return -1

# ---------------------------------------------------------------- commands
## "rename_base" {id, name}: 1..32 characters.
func cmd_rename(p: Dictionary) -> Dictionary:
	var id: int = int(p.get("id", -1))
	if get_base(id).is_empty():
		return {"ok": false, "code": "unknown"}
	var nm: String = String(p.get("name", "")).strip_edges()
	if nm.length() < 1 or nm.length() > 32:
		return {"ok": false, "code": "invalid"}
	bs()["list"][id]["name"] = nm
	return {"ok": true, "code": "ok"}

## Where an Outpost Kit may be deployed: the outpost core's placement check, plus at least
## base_min_distance from every other base's core. Returns a placement code ("ok" if fine).
func check_outpost(pos: Vector2, rot: float) -> String:
	var code: String = sim.place.check_building("outpost_core", sim.place.snap_pos(pos), sim.place.snap_rot(rot))
	if code != "ok":
		return code
	var min_d: float = float(sim.content["terrain_v4"].get("base_min_distance", 300.0))
	for id in ids():
		var c: Dictionary = core_of(id)
		if not c.is_empty() and (c["pos"] as Vector2).distance_to(pos) < min_d:
			return "too_close_base"
	return "ok"

## "deploy_outpost" {x, y, rot, inv, name?}: takes one outpost_kit from inventory `inv`
## (a ground pile, a store or a vehicle hold within kit_reach metres of the place) and sets
## up an outpost core there: a new base with its own air for shelter_days days.
func cmd_deploy(p: Dictionary) -> Dictionary:
	var pos: Vector2 = sim.place.snap_pos(Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))
	var rot: float = sim.place.snap_rot(float(p.get("rot", 0.0)))
	var inv_id: int = int(p.get("inv", -1))
	if not sim.inv.exists(inv_id) or sim.inv.available(inv_id, "outpost_kit") < 1:
		return {"ok": false, "code": "no_kit"}
	var reach: float = float(sim.bdef("outpost_core").get("kit_reach", 30.0))
	if sim.inv.position_of(inv_id).distance_to(pos) > reach:
		return {"ok": false, "code": "kit_far"}
	var code: String = check_outpost(pos, rot)
	if code != "ok":
		return {"ok": false, "code": code}
	if not sim.inv.consume(inv_id, "outpost_kit", 1, "deployed"):
		return {"ok": false, "code": "no_kit"}
	sim.stat_add("consumed", "outpost_kit", 1)
	var core: Dictionary = sim.build.spawn_active("outpost_core", pos, rot)
	var days: float = float(sim.bdef("outpost_core").get("shelter_days", 3.0))
	core["air_until"] = int(sim.state["tick"]) + int(days * float(sim.bal["day_length"]) * float(sim.bal["tick_hz"]))
	var n: int = count() + 1
	var nm: String = String(p.get("name", "")).strip_edges()
	if nm == "" or nm.length() > 32:
		nm = "Outpost %d" % (n - 1)
	core["name"] = nm + " core"
	var id: int = _add(int(core["id"]), nm)
	sim.topo.mark_dirty()
	sim.log_event("outpost", "%s is founded. Its core has air for %d days." % [nm, int(days)], [int(core["id"])], 1)
	return {"ok": true, "code": "ok", "id": id, "core": int(core["id"])}
