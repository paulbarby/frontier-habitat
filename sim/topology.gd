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
	if bump:
		sim.state["topo_dirty"] = false
		var rev: Dictionary = sim.state["rev"]
		rev["power"] = int(rev["power"]) + 1
		rev["atmo"] = int(rev["atmo"]) + 1
		rev["walk"] = int(rev["walk"]) + 1
	sim.util.invalidate()
	sim.nav.rebuild()

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
