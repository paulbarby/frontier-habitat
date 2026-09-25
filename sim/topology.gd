extends RefCounted
## The three graphs of spec 4, as DERIVED data. They are rebuilt from the buildings and
## links after construction, demolition, damage or a load, and each rebuild raises a
## revision number so that agents drop stale routes.
##   electricity + water : completed structures joined by cables or corridors
##   atmosphere          : completed rooms joined by open corridors
##   walking (indoor)    : the same rooms and corridors; outdoor cells live in nav.gd
## A component is named by the smallest building id in it, which is stable and readable.

var sim
var power_comp := {}      # building id -> component key
var power_members := {}   # component key -> [building ids]
var atmo_comp := {}
var atmo_members := {}
var atmo_corridor_len := {}   # component key -> metres of corridor (adds oxygen capacity)
var locks_by_comp := {}   # atmosphere component key -> [airlock / hatch building ids]
var links_of := {}        # building id -> [link ids] (all states)

func _init(s) -> void:
	sim = s

func mark_dirty() -> void:
	sim.state["topo_dirty"] = true

static func conducts(b: Dictionary) -> bool:
	return b["state"] == "active" or b["state"] == "broken"

## bump = false after a load: the graphs are rebuilt but the saved revision numbers and
## the saved dirty flag stay, so the loaded game continues exactly like the original.
func rebuild(bump: bool = true) -> void:
	var blds: Dictionary = sim.state["buildings"]
	var pp := {}
	var ap := {}
	links_of = {}
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			for e in [b["a"], b["b"]]:
				if not links_of.has(e):
					links_of[e] = []
				links_of[e].append(id)
			continue
		if b["def"] == "meridian":
			# The wreck is part of no network: no power, no water, no air, no walking inside.
			continue
		if conducts(b):
			pp[id] = id
			if b["kind"] == "room" or b["kind"] == "special":
				ap[id] = id
	atmo_corridor_len = {}
	var corridor_len_by_link := {}
	for id in blds:
		var l: Dictionary = blds[id]
		if l["kind"] != "link" or l["state"] != "active":
			continue
		var a: int = l["a"]
		var bb: int = l["b"]
		if pp.has(a) and pp.has(bb):
			_union(pp, a, bb)
		if l["def"] == "corridor" and bool(l.get("door_open", true)) and ap.has(a) and ap.has(bb):
			_union(ap, a, bb)
			corridor_len_by_link[id] = float(l["length"])
	power_comp = {}
	power_members = {}
	for id in pp:
		var r: int = _find(pp, id)
		power_comp[id] = r
		if not power_members.has(r):
			power_members[r] = []
		power_members[r].append(id)
	atmo_comp = {}
	atmo_members = {}
	locks_by_comp = {}
	for id in ap:
		var r: int = _find(ap, id)
		atmo_comp[id] = r
		if not atmo_members.has(r):
			atmo_members[r] = []
			locks_by_comp[r] = []
		atmo_members[r].append(id)
		var def: Dictionary = sim.bdef(blds[id]["def"])
		if bool(def.get("airlock", false)) or bool(def.get("hatch", false)):
			locks_by_comp[r].append(id)
	for lid in corridor_len_by_link:
		var r: int = atmo_comp[blds[lid]["a"]]
		atmo_corridor_len[r] = float(atmo_corridor_len.get(r, 0.0)) + float(corridor_len_by_link[lid])
	sim.util.invalidate()
	sim.nav.rebuild()
	if bump:
		sim.state["topo_dirty"] = false
		var rev: Dictionary = sim.state["rev"]
		rev["power"] = int(rev["power"]) + 1
		rev["atmo"] = int(rev["atmo"]) + 1
		# The walk revision (which drops every kept route) only moves when the walking map
		# really changed: the cells structures block and the room graph (v3: a cable, a
		# repair or a breakdown no longer makes every walker plan again on the 810 m map).
		# The last signature is saved, so a loaded game moves it exactly like the original.
		var sig: int = sim.nav.signature()
		if sig != int(sim.state.get("walk_sig", -1)) or not sim.state.has("walk_sig"):
			rev["walk"] = int(rev["walk"]) + 1
			sim.state["walk_sig"] = sig
			_step_off_new_ground()

## V3.1: a structure that starts on the ground where a colonist stands outside moves that
## colonist to the nearest open cell. And a colonist outside whom new structures closed in
## (no walk to any airlock with air is left) moves to the nearest open cell from which there
## is one, at most 15 m: without this such a colonist died of lack of air (a13, campaign).
## Both are rare; the view fades the body (V3_1_DESIGN 4.3).
func _step_off_new_ground() -> void:
	var any_lock := false
	for comp in sim.topo.locks_by_comp:
		if sim.util.comp_supplied(comp) and not (sim.topo.locks_by_comp[comp] as Array).is_empty():
			any_lock = true
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["where"] != "out":
			continue
		var p: Vector2 = a["pos"]
		var ok_here: bool = sim.nav.is_walkable(p)
		if ok_here and (not any_lock or bool(sim.nav.nearest_supplied_lock(p)["ok"])):
			continue
		var best = null
		if not ok_here:
			best = sim.nav.nearest_walkable(p, 4)
			if best != null and (not any_lock or bool(sim.nav.nearest_supplied_lock(best)["ok"])):
				a["pos"] = best
				a["ret_c"] = {}
				continue
		if not any_lock:
			if best != null:
				a["pos"] = best
			continue
		var found = null
		for r in range(1, 16):
			for k in 16:
				var q: Vector2 = p + Vector2(float(r), 0).rotated(float(k) * TAU / 16.0)
				if sim.nav.is_walkable(q) and bool(sim.nav.nearest_supplied_lock(q)["ok"]):
					found = q
					break
			if found != null:
				break
		if found != null:
			a["pos"] = found
			a["ret_c"] = {}
			sim.stat_add("closed_in_moves", "", 1)

# Union by smallest id keeps the component key stable and deterministic.
func _find(p: Dictionary, x: int) -> int:
	while int(p[x]) != x:
		p[x] = p[int(p[x])]
		x = int(p[x])
	return x

func _union(p: Dictionary, a: int, b: int) -> void:
	var ra: int = _find(p, a)
	var rb: int = _find(p, b)
	if ra == rb:
		return
	if ra < rb:
		p[rb] = ra
	else:
		p[ra] = rb

func same_power(a: int, b: int) -> bool:
	return power_comp.has(a) and power_comp.has(b) and int(power_comp[a]) == int(power_comp[b])

func same_atmo(a: int, b: int) -> bool:
	return atmo_comp.has(a) and atmo_comp.has(b) and int(atmo_comp[a]) == int(atmo_comp[b])

## Names a place by compass direction from the lander: "East greenhouse" (spec 12).
func district_name(pos: Vector2) -> String:
	var c: Vector2 = sim.world.center
	var d: Vector2 = pos - c
	if d.length() < 14.0:
		return "Central"
	var a: float = rad_to_deg(atan2(d.y, d.x))
	if a < 0.0:
		a += 360.0
	var names := ["East", "South-east", "South", "South-west", "West", "North-west", "North", "North-east"]
	return names[int(fmod(a + 22.5, 360.0) / 45.0)]
