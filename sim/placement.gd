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
	"ports_full": "No free port: too close to another corridor on this room.",
	"links_full": "This room has all the corridors it can take (S 4, M 6, L 7, XL 8).",
	"crossing": "The corridor would cross another corridor. Build a junction where they meet.",
	"lander": "The lander has no corridor port. Its air cannot feed the base.",
	"locked_research": "Research is needed first.",
	"no_size": "This structure has one size only.",
	"ship": "The Meridian takes no corridor or cable.",
	"overlap_ship": "Overlaps the wreck of the Meridian.",
	"door_blocked": "The door would open onto equipment. Choose another side of the room.",
	"depot_blocked": "This would block the rover depot.",
	"one_per_base": "Only one of these can stand at a base.",
	"no_atmosphere": "This planet has no air: this structure cannot work here.",
}

func _init(s) -> void:
	sim = s

## How much wider a corridor tube is than on the v3 maps (0.0 there, exactly: the v3
## margins keep their exact values; 0.3 m on the v4 map).
func _dc() -> float:
	return sim.corridor_r() - 1.2

## The sentence for a refusal code. For a lock (stage, research, size) it names what is needed and
## the progress, for the structure checked last by check_building (the placement preview and the
## place_building command check first).
func reason_text(code: String) -> String:
	if (code == "locked" or code == "locked_research" or code == "no_size") and _last_def != "":
		var li: Dictionary = lock_info(_last_def, _last_size)
		if bool(li["locked"]):
			return String(li["text"])
	return REASONS.get(code, code)

var _last_def := ""
var _last_size := 1

## Why a structure (at a size) cannot be built yet, in plain words, with the progress now:
## {locked (bool), kind ("stage" | "research" | "size" | "unknown" | ""), text, stage, tech}.
## Examples: "Unlocks at stage Growing settlement: 20 colonists (now 16), morale 60 (now 62),
## 3 days without a death (now 5)." / "Research Rover Parts first."
func lock_info(def_id: String, size: int = 1) -> Dictionary:
	var out := {"locked": false, "kind": "", "text": "", "stage": -1, "tech": ""}
	if not sim.content["buildings"].has(def_id):
		out["locked"] = true
		out["kind"] = "unknown"
		out["text"] = "This structure does not exist."
		return out
	var base: Dictionary = sim.bdef(def_id)
	if bool(base.get("needs_atmosphere", false)) and not sim.planet_has_air():
		out["locked"] = true
		out["kind"] = "planet"
		out["text"] = "This planet has no air: %s cannot work here." % String(base.get("name", def_id))
		return out
	var need: int = int(base.get("stage", 0))
	var now: int = int(sim.state["progress"]["stage"])
	if need > now and not sim.unlocked_all():
		out["locked"] = true
		out["kind"] = "stage"
		out["stage"] = need
		out["text"] = stage_text(need)
		return out
	var tech: String = ""
	if not sim.research.building_unlocked(def_id):
		tech = String(base.get("research", ""))
	else:
		var al: Dictionary = sim.sizes.allowed(def_id, size)
		if not bool(al["ok"]):
			out["locked"] = true
			out["kind"] = "size"
			if String(al["code"]) == "locked_research":
				out["tech"] = String(al["research"])
				out["text"] = "Research %s first for size %s." % [_tech_name(String(al["research"])), sim.sizes.size_name(size)]
			else:
				out["text"] = "This structure is not made in size %s. Sizes: %s." % [sim.sizes.size_name(size), ", ".join(sim.sizes.sizes_of(def_id).map(func(z): return sim.sizes.size_label(def_id, z)))]
			return out
	if tech != "":
		out["locked"] = true
		out["kind"] = "research"
		out["tech"] = tech
		out["text"] = "Research %s first." % _tech_name(tech)
	return out

func _tech_name(tech: String) -> String:
	return String(sim.content["techs"].get(tech, {}).get("name", tech))

## "Unlocks at stage <name>: <each condition> (now <value>)." for stage index i.
func stage_text(i: int) -> String:
	var stages: Array = sim.bal["stages"]
	if i >= stages.size():
		return "This structure comes in a later version of the game."
	var s: Dictionary = stages[i]
	var f: Dictionary = sim.metrics.forecast()
	var pr: Dictionary = sim.state["progress"]
	var day_ticks: float = float(sim.bal["day_length"]) * float(sim.bal["tick_hz"])
	var tick: int = int(sim.state["tick"])
	var since: float = float(tick - int(pr["last_death_tick"])) / day_ticks if int(pr["last_death_tick"]) >= 0 else float(tick) / day_ticks
	var parts: Array = []
	if s.has("pop"):
		parts.append("%d colonists (now %d)" % [int(s["pop"]), int(f["pop"])])
	if s.has("safe_reserve_days"):
		parts.append("%s %s with safe reserves (now %.1f)" % [_num(float(s["safe_reserve_days"])), "day" if float(s["safe_reserve_days"]) == 1.0 else "days", float(pr["safe_ticks"]) / day_ticks])
	if s.has("morale"):
		parts.append("morale %d (now %d)" % [int(s["morale"]), int(round(sim.metrics.avg_morale()))])
	if s.has("no_death_days"):
		parts.append("%s days without a death (now %.1f)" % [_num(float(s["no_death_days"])), since])
	if s.has("districts"):
		parts.append("%d districts with their own air (now %d)" % [int(s["districts"]), sim.metrics.supplied_districts()])
	if s.has("meal_days"):
		parts.append("%s days of meals in store (now %.1f)" % [_num(float(s["meal_days"])), float(f["meal_days"])])
	var txt: String = "Unlocks at stage %s" % String(s["name"])
	if i > int(pr["stage"]) + 1:
		txt += " (stage %d; the colony is at stage %d)" % [i, int(pr["stage"])]
	return txt + (": " + ", ".join(parts) + "." if not parts.is_empty() else ".")

static func _num(x: float) -> String:
	return str(int(x)) if x == floor(x) else "%.1f" % x

## The same sentence with the missing research named, for the placement hint.
func reason_detail(def_id: String, size: int, code: String) -> String:
	if code == "locked" or code == "locked_research" or code == "no_size":
		var li: Dictionary = lock_info(def_id, size)
		if bool(li["locked"]):
			return String(li["text"])
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
	_last_def = def_id
	_last_size = size
	var base: Dictionary = sim.bdef(def_id)
	var bal: Dictionary = sim.bal
	if int(base.get("stage", 0)) > int(sim.state["progress"]["stage"]) and not sim.unlocked_all():
		return "locked"
	if not sim.research.building_unlocked(def_id):
		return "locked_research"
	# V5 15.7: a wind turbine or an atmosphere processor needs air outside.
	if bool(base.get("needs_atmosphere", false)) and not sim.planet_has_air():
		return "no_atmosphere"
	var allowed: Dictionary = sim.sizes.allowed(def_id, size)
	if not bool(allowed["ok"]):
		return String(allowed["code"])
	var def: Dictionary = sim.sizes.def_for(def_id, size)
	var r: float = float(def["radius"])
	if not sim.world.in_map(pos, float(sim.world.margin) + r):
		return "outside_map"
	var blds: Dictionary = sim.state["buildings"]
	# V5 section 8: one super dome a base (the base of the place it would stand at).
	if bool(base.get("one_per_base", false)):
		var here: int = sim.bases.base_at(pos) if sim.bases.count() > 1 else -1
		for id2 in blds:
			var o: Dictionary = blds[id2]
			if id2 != ignore_id and String(o["def"]) == def_id and (here == -1 or sim.bases.base_of(int(id2)) == here):
				return "one_per_base"
	for id in blds:
		if id == ignore_id:
			continue
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			if b["def"] == "corridor":
				var cp: Vector2 = Geometry2D.get_closest_point_to_segment(pos, b["p0"], b["p1"])
				if cp.distance_to(pos) < r + 1.5 + _dc():
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
	for rock in sim.world.rocks_near(pos, r + 0.3):
		if Vector2(rock["x"], rock["y"]).distance_to(pos) < r + float(rock["r"]) + 0.3:
			return "overlap_rock"
	# V4: nothing stands in a crevice.
	if sim.world.crevice_at(pos, r + 0.5):
		return "slope"
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
			# V3.1 porch rule: no corridor tube in front of the new door either.
			if b["kind"] == "link" and b["def"] == "corridor":
				var st: Dictionary = door_strip(probe)
				if _segment_distance(st["p0"], st["p1"], b["p0"], b["p1"]) < 1.2 + _dc() + float(st["half_width"]):
					return "blocked_entrance"
		var door: Vector2 = pos + Vector2(cos(rot), sin(rot)) * (r + 1.3)
		if not sim.world.in_map(door, float(sim.world.margin)) or _terrain_blocked(door):
			return "blocked_entrance"
	# At least one outdoor access point must be open ground, or nobody can build it.
	var open := 0
	for k in 8:
		var a: float = rot + k * TAU / 8.0 + 0.39
		var p: Vector2 = pos + Vector2(cos(a), sin(a)) * (r + float(bal.get("nav_clearance", 0.6)) + 1.0)
		if sim.world.in_map(p, float(sim.world.margin)) and not _terrain_blocked(p) and _free_of_structures(p, ignore_id):
			open += 1
	if open == 0:
		return "blocked_entrance"
	# V4: a rover depot's bays must stay reachable (rovers never drive through a structure or a
	# tube); a new depot must not stand closed in either.
	if sim.nav.has_method("depot_cut"):
		var nd := {}
		if bool(base.get("depot", false)):
			var probe := {"pos": pos, "rot": rot, "radius": r, "def": def_id, "size": size, "level": 1, "id": -1}
			nd = {"pos": pos, "radius": r, "bays": sim.vehicles.bays(probe)}
		if sim.nav.depot_cut({"c": pos, "r": r}, nd):
			return "depot_blocked"
	return "ok"

func _terrain_blocked(p: Vector2) -> bool:
	if sim.world.is_steep_cell(int(p.x), int(p.y)):
		return true
	for rock in sim.world.rocks_near(p, 0.3):
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
			if b["def"] == "corridor" and Geometry2D.get_closest_point_to_segment(p, b["p0"], b["p1"]).distance_to(p) < 1.4 + _dc():
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

## V3.1 porch zone: the ground in front of an airlock's outer door (or the lander hatch)
## that no structure may cover. `b` is a structure record or a probe {pos, rot, radius}.
## Returns {p0, p1, half_width, porch_length}: the strip runs from p0 (the door, on the
## footprint edge) to p1 (door_strip_length out), half_width to each side; porch_length
## is the part in front of the door that paths cross only to use the door.
func door_strip(b: Dictionary) -> Dictionary:
	var dirv := Vector2(cos(float(b["rot"])), sin(float(b["rot"])))
	var p0: Vector2 = (b["pos"] as Vector2) + dirv * float(b["radius"])
	return {"p0": p0, "p1": p0 + dirv * float(sim.bal["door_strip_length"]),
		"half_width": float(sim.bal["door_strip_half_width"]), "porch_length": float(sim.bal.get("porch_length", 2.5))}

## The porch zone a new airlock would have (for the placement preview).
func door_strip_for(def_id: String, pos: Vector2, rot: float, size: int = 1) -> Dictionary:
	var def: Dictionary = sim.sizes.def_for(def_id, size)
	if def.is_empty() or not (bool(def.get("airlock", false)) or bool(def.get("hatch", false))):
		return {}
	return door_strip({"pos": snap_pos(pos), "rot": snap_rot(rot), "radius": float(def["radius"])})

## Every porch zone on the map now: [{id, p0, p1, half_width, porch_length}] by id.
func door_strips() -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	var ids: Array = blds.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = blds[id]
		if b["kind"] == "link" or not _has_door(b):
			continue
		var st: Dictionary = door_strip(b)
		st["id"] = int(id)
		out.append(st)
	return out

## V3.1 (critic round 13): ground piles and drop points keep clear of every airlock's porch:
## at least pile_porch_clear (2.5 m) from the outer door and off the door strip. Returns the
## point itself when it is clear, else the nearest clear open point on rings of 1 m (16
## directions, up to 10 m), else the point itself.
func in_porch(p: Vector2, strips: Array = []) -> bool:
	if strips.is_empty():
		strips = door_strips()
	var keep: float = float(sim.bal.get("pile_porch_clear", 2.5))
	for st in strips:
		if p.distance_to(st["p0"]) < keep:
			return true
		if Geometry2D.get_closest_point_to_segment(p, st["p0"], st["p1"]).distance_to(p) < float(st["half_width"]):
			return true
	return false

func clear_of_porches(p: Vector2) -> Vector2:
	var strips: Array = door_strips()
	if strips.is_empty() or not in_porch(p, strips):
		return p
	for r in range(1, 11):
		for k in 16:
			var q: Vector2 = p + Vector2(float(r), 0).rotated(float(k) * TAU / 16.0)
			if sim.nav.is_walkable(q) and not in_porch(q, strips):
				return q
	return p

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
		if used.size() >= max_links(room):
			return {"code": "links_full", "room": int(room["id"])}
		var min_angle: float = link_min_angle(room)
		for d in used:
			if rad_to_deg(absf((d as Vector2).angle_to(dirv))) < min_angle:
				return {"code": "ports_full"}
		# V3.1: no doorway onto equipment (ART-HAB door clearance data, new links only). On an
		# airlock this covers the chamber and porch side.
		if not link_angle_ok(room, dirv.angle()):
			return {"code": "door_blocked", "room": int(room["id"])}
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
				if _segment_distance(p0, p1, o["p0"], o["p1"]) < 2.6 + 2.0 * _dc() and not _shares_room(o, a_id, b_id):
					return {"code": "overlap_corridor"}
			continue
		if o["def"] == "meridian":
			continue
		var cp: Vector2 = Geometry2D.get_closest_point_to_segment(o["pos"], p0, p1)
		if cp.distance_to(o["pos"]) < float(o["radius"]) + 1.5 + _dc():
			return {"code": "overlap"}
		if _has_door(o):
			var dirv2 := Vector2(cos(o["rot"]), sin(o["rot"]))
			var s0: Vector2 = o["pos"] + dirv2 * float(o["radius"])
			var s1: Vector2 = s0 + dirv2 * float(bal["door_strip_length"])
			if _segment_distance(p0, p1, s0, s1) < 1.3 + _dc() + float(bal["door_strip_half_width"]):
				return {"code": "blocks_entrance"}
	for rock in sim.world.rocks_near((p0 + p1) * 0.5, p0.distance_to(p1) * 0.5 + 1.4):
		var rp := Vector2(rock["x"], rock["y"])
		if Geometry2D.get_closest_point_to_segment(rp, p0, p1).distance_to(rp) < float(rock["r"]) + 1.4:
			return {"code": "overlap_rock"}
	# V4: a corridor does not cross a crevice (a bridge does, later).
	for cv in sim.world.crevices:
		var cpts: Array = cv["pts"]
		for ci in range(1, cpts.size()):
			if _segment_distance(p0, p1, cpts[ci - 1], cpts[ci]) < float(cv["w"]) * 0.5 + 1.5 + _dc():
				return {"code": "slope"}
	var dh: float = absf(sim.world.height_at(p0.x, p0.y) - sim.world.height_at(p1.x, p1.y))
	if dh / maxf(1.0, length) > 0.4:
		return {"code": "slope"}
	# V4: a rover depot's bays must stay reachable (rovers never drive through a tube).
	if sim.nav.has_method("depot_cut") and sim.nav.depot_cut({"p0": p0, "p1": p1}):
		return {"code": "depot_blocked"}
	var n10: int = maxi(1, int(ceil(length / 10.0)))
	return {"code": "ok", "p0": p0, "p1": p1, "length": length, "cost": _scaled(bal["corridor_cost_per_10m"], n10)}

# ---------------------------------------------------------------- door clearance (V3.1)
## Model-angle ranges (degrees; 0 = model +X, counter-clockwise seen from above, as in
## content/door_blocked.json from ART-HAB) where a corridor may not attach to a room of this
## type and size: the doorway would open onto equipment. [] = every angle is free.
func door_ranges(def_id: String, size: int) -> Array:
	var rooms: Dictionary = sim.content.get("door_blocked", {})
	if sim.content["buildings"].get(def_id, {}).has("sizes"):
		var key: String = "%s_%s" % [def_id, String(sim.sizes.size_name(size)).to_lower()]
		if rooms.has(key):
			return rooms[key].get("blocked", [])
	return rooms.get(def_id, {}).get("blocked", [])

## The model angle (degrees, 0..360) of a world direction for a room turned by `rot`. The
## view turns a model by -rot about the vertical axis with sim y on its z axis, so model
## angle = rot - world angle (docs/requests/ART-HAB-to-RENDER.md P3).
static func model_angle(rot: float, world_angle: float) -> float:
	return fposmod(rad_to_deg(rot - world_angle), 360.0)

## True when a corridor may leave a room of this type, size and rotation in this world
## direction (radians).
func link_angle_ok_for(def_id: String, size: int, rot: float, world_angle: float) -> bool:
	var ranges: Array = door_ranges(def_id, size)
	if ranges.is_empty():
		return true
	var m: float = model_angle(rot, world_angle)
	for r in ranges:
		var a0: float = float(r[0])
		var a1: float = float(r[1])
		for w in [m - 360.0, m, m + 360.0]:
			if w >= a0 and w <= a1:
				return false
	return true

func link_angle_ok(room: Dictionary, world_angle: float) -> bool:
	return link_angle_ok_for(room["def"], int(room.get("size", 1)), float(room["rot"]), world_angle)

## The directions a new corridor may leave a room (placement ghost and link tool): a list
## of {"from", "to"} world angles in radians, from < to, counter-clockwise (increasing
## angle); to - from is at most TAU. [{"from": 0, "to": TAU}] when every angle is free, []
## when none is.
func link_sectors_for(def_id: String, size: int, rot: float) -> Array:
	var ranges: Array = door_ranges(def_id, size)
	if ranges.is_empty():
		return [{"from": 0.0, "to": TAU}]
	# Blocked model intervals on 0..360, split where they wrap, sorted and merged.
	var segs: Array = []
	for r in ranges:
		var a0: float = float(r[0])
		var a1: float = float(r[1])
		if a1 - a0 >= 360.0:
			return []
		a0 = fposmod(a0, 360.0)
		a1 = a0 + (float(r[1]) - float(r[0]))
		if a1 > 360.0:
			segs.append([a0, 360.0])
			segs.append([0.0, a1 - 360.0])
		else:
			segs.append([a0, a1])
	segs.sort_custom(func(x, y): return x[0] < y[0])
	var merged: Array = []
	for sg in segs:
		if not merged.is_empty() and float(sg[0]) <= float(merged.back()[1]):
			merged.back()[1] = maxf(float(merged.back()[1]), float(sg[1]))
		else:
			merged.append([float(sg[0]), float(sg[1])])
	# Free model intervals, joined across 360 -> 0.
	var free: Array = []
	var at := 0.0
	for sg in merged:
		if float(sg[0]) > at:
			free.append([at, float(sg[0])])
		at = maxf(at, float(sg[1]))
	if at < 360.0:
		if not free.is_empty() and float(free[0][0]) <= 0.0:
			free[0] = [at - 360.0, float(free[0][1])]
		else:
			free.append([at, 360.0])
	var out: Array = []
	for f in free:
		# Model [m0, m1] is world [rot - m1, rot - m0].
		var w0: float = fposmod(rot - deg_to_rad(float(f[1])), TAU)
		out.append({"from": w0, "to": w0 + deg_to_rad(float(f[1]) - float(f[0]))})
	out.sort_custom(func(x, y): return float(x["from"]) < float(y["from"]))
	return out

func link_sectors(room: Dictionary) -> Array:
	return link_sectors_for(room["def"], int(room.get("size", 1)), float(room["rot"]))

## Smallest angle in degrees between two corridors on one room: the general
## link_min_angle_deg (28), or the room's own "link_min_angle_deg" (junction 55, so two
## corridor tubes of 2.36 m do not overlap outside its hub; V3, CRITIC measure). Only new
## links are checked, so saves with closer corridors still load and work.
func link_min_angle(room: Dictionary) -> float:
	var d: Dictionary = sim.bd(room)
	var base: float = float(d.get("link_min_angle_deg", sim.bal["link_min_angle_deg"]))
	if bool(d.get("airlock", false)) or d.has("link_min_angle_deg"):
		return base          # airlocks and junctions keep their own rule
	return maxf(base, door_angle(float(room["radius"])))

## Paul, 2026-09-27: the angle a doorway's housing needs at the wall of a room of this
## radius (housing 3.44 m + 0.3 m gap as a chord at the wall radius, radius - 0.32 m), so two
## door frames never overlap.
func door_angle(radius: float) -> float:
	var rw: float = maxf(1.0, radius - 0.32)
	var half: float = float(sim.bal.get("door_housing_m", 3.44) + sim.bal.get("door_gap_m", 0.3)) * 0.5
	return rad_to_deg(2.0 * asin(minf(1.0, half / rw)))

## How many corridors a room takes (Paul, 2026-09-27): S 4, M 6, L 7, XL 8
## (balance.room_max_links); airlocks and junctions keep their own number.
func max_links(room: Dictionary) -> int:
	var d: Dictionary = sim.bd(room)
	if d.has("max_links"):
		return int(d["max_links"])
	if bool(d.get("airlock", false)) or not sim.content["buildings"].get(room["def"], {}).has("sizes"):
		return 4
	var per: Array = sim.bal.get("room_max_links", [4, 6, 7, 8])
	return int(per[clampi(int(room.get("size", 1)), 0, per.size() - 1)])

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
