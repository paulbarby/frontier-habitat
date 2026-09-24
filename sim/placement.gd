extends RefCounted
## Placement rules (spec 4). Every refusal has a precise reason code and sentence.
## Buildings use a circular footprint on the hidden one-metre grid; rotation is free in
## 15-degree steps and sets the door and port directions only.

var sim

const Ship = preload("res://sim/ship.gd")

const REASONS := {
	"ok": "Placement is valid.",
	"outside_map": "Outside the map.",
	"overlap": "Overlaps another structure.",
	"overlap_rock": "Overlaps a rock outcrop.",
	"overlap_corridor": "Overlaps a corridor. Corridors that must cross need a junction.",
	"slope": "The ground is too steep here.",
	"blocked_entrance": "The entrance or its access strip is blocked.",
	"blocks_entrance": "This would block the access strip of an airlock door.",
	"no_support": "No valid support: a mine must stand on a mineral deposit.",
	"locked": "This structure is not unlocked yet.",
	"same": "Pick two different structures.",
	"gone": "One of the two structures is not there any more.",
	"not_room": "A corridor joins two rooms. Use a cable for outdoor structures.",
	"too_far": "Too far apart.",
	"too_close": "Too close together for a corridor.",
	"duplicate": "These two are already joined.",
	"ports_full": "No free port: too many corridors on one room, or too close to another corridor.",
	"crossing": "The corridor would cross another corridor. Build a junction where they meet.",
	"lander": "The lander has no corridor port. Its air cannot feed the base.",
	"locked_research": "Research is needed first.",
	"no_size": "This structure has one size only.",
	"ship": "The Meridian takes no corridor or cable.",
	"overlap_ship": "Overlaps the wreck of the Meridian.",
}

func _init(s) -> void:
	sim = s

func reason_text(code: String) -> String:
	return REASONS.get(code, code)

## The same sentence with the missing research named, for the placement hint.
func reason_detail(def_id: String, size: int, code: String) -> String:
	if code != "locked_research":
		return reason_text(code)
	var tech: String = ""
	if not sim.research.building_unlocked(def_id):
		tech = String(sim.bdef(def_id).get("research", ""))
	else:
		tech = String(sim.sizes.allowed(def_id, size).get("research", ""))
	if tech != "" and sim.content["techs"].has(tech):
		return "Research %s first." % sim.content["techs"][tech]["name"]
	return reason_text(code)

static func snap_rot(rot: float) -> float:
	var step := deg_to_rad(15.0)
	return fposmod(roundf(rot / step) * step, TAU)

static func snap_pos(p: Vector2) -> Vector2:
	return Vector2(roundf(p.x * 2.0) / 2.0, roundf(p.y * 2.0) / 2.0)

# ---------------------------------------------------------------- buildings
## size is 0..3 (S, M, L, XL); a structure without sizes only has size 1.
func check_building(def_id: String, pos: Vector2, rot: float, ignore_id: int = -1, size: int = 1) -> String:
	if not sim.content["buildings"].has(def_id):
		return "unknown"
	var base: Dictionary = sim.bdef(def_id)
	var bal: Dictionary = sim.bal
	if int(base.get("stage", 0)) > int(sim.state["progress"]["stage"]) and not sim.unlocked_all():
		return "locked"
	if not sim.research.building_unlocked(def_id):
		return "locked_research"
	var allowed: Dictionary = sim.sizes.allowed(def_id, size)
	if not bool(allowed["ok"]):
		return String(allowed["code"])
	var def: Dictionary = sim.sizes.def_for(def_id, size)
	var r: float = float(def["radius"])
	if not sim.world.in_map(pos, float(sim.world.margin) + r):
		return "outside_map"
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		if id == ignore_id:
			continue
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			if b["def"] == "corridor":
				var cp: Vector2 = Geometry2D.get_closest_point_to_segment(pos, b["p0"], b["p1"])
				if cp.distance_to(pos) < r + 1.5:
					return "overlap_corridor"
			continue
		if b["def"] == "meridian":
			if Ship.surface_distance(b, pos) < r + 1.5:
				return "overlap_ship"
			continue
		if (b["pos"] as Vector2).distance_to(pos) < r + float(b["radius"]) + 0.6:
			return "overlap"
		if _has_door(b) and _hits_strip(b, pos, r):
			return "blocks_entrance"
	for rock in sim.world.rocks:
		if Vector2(rock["x"], rock["y"]).distance_to(pos) < r + float(rock["r"]) + 0.3:
			return "overlap_rock"
	var max_slope: float = float(bal["max_slope_exterior"]) if def["kind"] == "exterior" else float(bal["max_slope_rooms"])
	if sim.world.slope_over(pos, r) > max_slope:
		return "slope"
	if bool(def.get("needs_deposit", false)):
		var on := false
		for d in sim.state["deposits"]:
			if Vector2(d["x"], d["y"]).distance_to(pos) <= float(d["r"]):
				on = true
		if not on:
			return "no_support"
	if bool(def.get("airlock", false)):
		var probe := {"pos": pos, "rot": rot, "radius": r}
		for id in blds:
			if id == ignore_id:
				continue
			var b: Dictionary = blds[id]
			if b["def"] == "meridian":
				var dv := Vector2(cos(rot), sin(rot))
				var seg: Array = Ship.segment_of(b)
				if _segment_distance(pos + dv * r, pos + dv * (r + float(bal["door_strip_length"])), seg[0], seg[1]) < float(b["radius"]) + float(bal["door_strip_half_width"]):
					return "blocked_entrance"
				continue
			if b["kind"] != "link" and _hits_strip(probe, b["pos"], float(b["radius"])):
				return "blocked_entrance"
		var door: Vector2 = pos + Vector2(cos(rot), sin(rot)) * (r + 1.3)
		if not sim.world.in_map(door, float(sim.world.margin)) or _terrain_blocked(door):
			return "blocked_entrance"
	# At least one outdoor access point must be open ground, or nobody can build it.
	var open := 0
	for k in 8:
		var a: float = rot + k * TAU / 8.0 + 0.39
		var p: Vector2 = pos + Vector2(cos(a), sin(a)) * (r + 1.1)
		if sim.world.in_map(p, float(sim.world.margin)) and not _terrain_blocked(p) and _free_of_structures(p, ignore_id):
			open += 1
	if open == 0:
		return "blocked_entrance"
	return "ok"

func _terrain_blocked(p: Vector2) -> bool:
	if sim.world.is_steep_cell(int(p.x), int(p.y)):
		return true
	for rock in sim.world.rocks:
		if Vector2(rock["x"], rock["y"]).distance_to(p) < float(rock["r"]) + 0.3:
			return true
	return false

func _free_of_structures(p: Vector2, ignore_id: int) -> bool:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		if id == ignore_id:
			continue
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			if b["def"] == "corridor" and Geometry2D.get_closest_point_to_segment(p, b["p0"], b["p1"]).distance_to(p) < 1.4:
				return false
		elif b["def"] == "meridian":
			if Ship.surface_distance(b, p) < 0.3:
				return false
		elif (b["pos"] as Vector2).distance_to(p) < float(b["radius"]):
			return false
	return true

func _has_door(b: Dictionary) -> bool:
	var def: Dictionary = sim.bdef(b["def"])
	return bool(def.get("airlock", false)) or bool(def.get("hatch", false))

## True when a disc (c, r) touches the reserved access strip in front of a door.
func _hits_strip(door_b: Dictionary, c: Vector2, r: float) -> bool:
	var dirv := Vector2(cos(door_b["rot"]), sin(door_b["rot"]))
	var s0: Vector2 = door_b["pos"] + dirv * float(door_b["radius"])
	var s1: Vector2 = s0 + dirv * float(sim.bal["door_strip_length"])
	var cp: Vector2 = Geometry2D.get_closest_point_to_segment(c, s0, s1)
	return cp.distance_to(c) < r + float(sim.bal["door_strip_half_width"])

# ---------------------------------------------------------------- links
## Returns {"code", "p0", "p1", "length", "cost"}.
func check_link(def_id: String, a_id: int, b_id: int) -> Dictionary:
	var blds: Dictionary = sim.state["buildings"]
	var bal: Dictionary = sim.bal
	if a_id == b_id:
		return {"code": "same"}
	if not blds.has(a_id) or not blds.has(b_id):
		return {"code": "gone"}
	var a: Dictionary = blds[a_id]
	var b: Dictionary = blds[b_id]
	if a["kind"] == "link" or b["kind"] == "link":
		return {"code": "not_room"}
	if a["def"] == "meridian" or b["def"] == "meridian":
		return {"code": "ship"}
	var u: Vector2 = (b["pos"] - a["pos"]).normalized()
	var p0: Vector2 = a["pos"] + u * float(a["radius"])
	var p1: Vector2 = b["pos"] - u * float(b["radius"])
	var length: float = p0.distance_to(p1)
	if (b["pos"] as Vector2).distance_to(a["pos"]) < float(a["radius"]) + float(b["radius"]):
		length = 0.0
	for id in blds:
		var l: Dictionary = blds[id]
		if l["kind"] == "link" and l["def"] == def_id and ((l["a"] == a_id and l["b"] == b_id) or (l["a"] == b_id and l["b"] == a_id)):
			return {"code": "duplicate"}
		if l["def"] == "meridian":
			var seg: Array = Ship.segment_of(l)
			if _segment_distance(p0, p1, seg[0], seg[1]) < float(l["radius"]) + 1.5:
				return {"code": "overlap_ship"}
	if def_id == "cable":
		if length > float(bal["cable_max_length"]):
			return {"code": "too_far"}
		var n: int = maxi(1, int(ceil(maxf(length, 0.1) / 20.0)))
		return {"code": "ok", "p0": p0, "p1": p1, "length": length, "cost": _scaled(bal["cable_cost_per_20m"], n)}

	# corridor
	if a["kind"] == "special" or b["kind"] == "special":
		return {"code": "lander"}
	if a["kind"] != "room" or b["kind"] != "room":
		return {"code": "not_room"}
	if length > float(bal["corridor_max_length"]):
		return {"code": "too_far"}
	if length < float(bal["corridor_min_length"]):
		return {"code": "too_close"}
	for pair in [[a, u], [b, -u]]:
		var room: Dictionary = pair[0]
		var dirv: Vector2 = pair[1]
		var def: Dictionary = sim.bd(room)
		var used: Array = _corridor_dirs(room["id"])
		if used.size() >= int(def.get("max_links", 4)):
			return {"code": "ports_full"}
		var min_angle: float = link_min_angle(room)
		for d in used:
			if rad_to_deg(absf((d as Vector2).angle_to(dirv))) < min_angle:
				return {"code": "ports_full"}
		if bool(def.get("airlock", false)):
			var door := Vector2(cos(room["rot"]), sin(room["rot"]))
			if rad_to_deg(absf(door.angle_to(dirv))) < 55.0:
				return {"code": "blocked_entrance"}
	for id in blds:
		if id == a_id or id == b_id:
			continue
		var o: Dictionary = blds[id]
		if o["kind"] == "link":
			if o["def"] == "corridor":
				if Geometry2D.segment_intersects_segment(p0, p1, o["p0"], o["p1"]) != null:
					return {"code": "crossing"}
				if _segment_distance(p0, p1, o["p0"], o["p1"]) < 2.6 and not _shares_room(o, a_id, b_id):
					return {"code": "overlap_corridor"}
			continue
		if o["def"] == "meridian":
			continue
		var cp: Vector2 = Geometry2D.get_closest_point_to_segment(o["pos"], p0, p1)
		if cp.distance_to(o["pos"]) < float(o["radius"]) + 1.5:
			return {"code": "overlap"}
		if _has_door(o):
			var dirv2 := Vector2(cos(o["rot"]), sin(o["rot"]))
			var s0: Vector2 = o["pos"] + dirv2 * float(o["radius"])
			var s1: Vector2 = s0 + dirv2 * float(bal["door_strip_length"])
			if _segment_distance(p0, p1, s0, s1) < 1.3 + float(bal["door_strip_half_width"]):
				return {"code": "blocks_entrance"}
	for rock in sim.world.rocks:
		var rp := Vector2(rock["x"], rock["y"])
		if Geometry2D.get_closest_point_to_segment(rp, p0, p1).distance_to(rp) < float(rock["r"]) + 1.4:
			return {"code": "overlap_rock"}
	var dh: float = absf(sim.world.height_at(p0.x, p0.y) - sim.world.height_at(p1.x, p1.y))
	if dh / maxf(1.0, length) > 0.4:
		return {"code": "slope"}
	var n10: int = maxi(1, int(ceil(length / 10.0)))
	return {"code": "ok", "p0": p0, "p1": p1, "length": length, "cost": _scaled(bal["corridor_cost_per_10m"], n10)}

## Smallest angle in degrees between two corridors on one room: the general
## link_min_angle_deg (28), or the room's own "link_min_angle_deg" (junction 55, so two
## corridor tubes of 2.36 m do not overlap outside its hub; V3, CRITIC measure). Only new
## links are checked, so saves with closer corridors still load and work.
func link_min_angle(room: Dictionary) -> float:
	return float(sim.bd(room).get("link_min_angle_deg", sim.bal["link_min_angle_deg"]))

func _shares_room(link: Dictionary, a_id: int, b_id: int) -> bool:
	return link["a"] == a_id or link["b"] == a_id or link["a"] == b_id or link["b"] == b_id

func _corridor_dirs(room_id: int) -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var l: Dictionary = blds[id]
		if l["kind"] != "link" or l["def"] != "corridor":
			continue
		if l["a"] == room_id:
			out.append(((l["p1"] as Vector2) - l["p0"]).normalized())
		elif l["b"] == room_id:
			out.append(((l["p0"] as Vector2) - l["p1"]).normalized())
	return out

static func _segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	var d: float = Geometry2D.get_closest_point_to_segment(a0, b0, b1).distance_to(a0)
	d = minf(d, Geometry2D.get_closest_point_to_segment(a1, b0, b1).distance_to(a1))
	d = minf(d, Geometry2D.get_closest_point_to_segment(b0, a0, a1).distance_to(b0))
	d = minf(d, Geometry2D.get_closest_point_to_segment(b1, a0, a1).distance_to(b1))
	return d

static func _scaled(cost: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k in cost:
		out[k] = int(cost[k]) * n
	return out
