extends RefCounted
## Blueprint flow (spec 10): place -> reserve materials -> deliver -> construction work ->
## commission -> operational if connected and supplied. Also cancel and demolition.
## A building is one record for its whole life; links (corridors, cables) are records of
## kind "link" and follow the same flow. A building record carries its size (0..3 = S, M,
## L, XL) and level (1..5); sim.bd(b) gives its effective definition.

const Text = preload("res://sim/text.gd")

var sim

func _init(s) -> void:
	sim = s

# ---------------------------------------------------------------- creation
func place_building(def_id: String, pos: Vector2, rot: float, size: int = 1) -> Dictionary:
	if not sim.content["buildings"].has(def_id):
		return {"ok": false, "code": "unknown"}
	var base: Dictionary = sim.bdef(def_id)
	if base["kind"] == "link" or not bool(base.get("buildable", true)):
		return {"ok": false, "code": "unknown"}
	pos = sim.place.snap_pos(pos)
	rot = sim.place.snap_rot(rot)
	var code: String = sim.place.check_building(def_id, pos, rot, -1, size)
	if code != "ok":
		return {"ok": false, "code": code}
	var def: Dictionary = sim.sizes.def_for(def_id, size)
	var b: Dictionary = _new_record(def_id, def, def["cost"], int(def.get("size", 1)))
	b["pos"] = pos
	b["rot"] = rot
	_register(b)
	return {"ok": true, "id": b["id"], "code": "ok"}

func place_link(def_id: String, a_id: int, b_id: int) -> Dictionary:
	if def_id != "corridor" and def_id != "cable":
		return {"ok": false, "code": "unknown"}
	var chk: Dictionary = sim.place.check_link(def_id, a_id, b_id)
	if chk["code"] != "ok":
		return {"ok": false, "code": chk["code"]}
	var b: Dictionary = _new_record(def_id, sim.bdef(def_id), chk["cost"], 1)
	b["a"] = a_id
	b["b"] = b_id
	b["p0"] = chk["p0"]
	b["p1"] = chk["p1"]
	b["length"] = chk["length"]
	b["pos"] = ((chk["p0"] as Vector2) + chk["p1"]) * 0.5
	b["rot"] = ((chk["p1"] as Vector2) - chk["p0"]).angle()
	b["door_open"] = true
	_register(b)
	return {"ok": true, "id": b["id"], "code": "ok"}

func _new_record(def_id: String, def: Dictionary, cost: Dictionary, size: int) -> Dictionary:
	var id: int = sim.new_id()
	var counters: Dictionary = sim.state["counters"]
	counters[def_id] = int(counters.get(def_id, 0)) + 1
	var units := 0
	for r in cost:
		units += int(cost[r])
	var b := {
		"id": id, "def": def_id, "kind": def["kind"], "name": "%s %d" % [def["name"], counters[def_id]],
		"pos": Vector2.ZERO, "rot": 0.0, "radius": float(def["radius"]),
		"state": "blueprint", "cost": cost.duplicate(), "health": 100.0,
		"progress": 0.0, "work_total": maxf(1.0, units * float(sim.bal["work_per_material"]) * float(def.get("work_mult", 1.0))),
		"inv_site": -1, "inv_in": -1, "inv_out": -1, "inv_fill": -1,
		"enabled": true, "priority": 1, "powered": false, "shed_until": 0, "block": "",
		"energy": 0, "water": 0, "oxygen": 0, "batch": {}, "trays": [], "lock": {}, "workers": 0,
		"created": int(sim.state["tick"]), "commissioned": -1, "breach": false,
		"demolish": false, "unreach_rev": -1, "out_rate": 1.0,
		"size": size, "level": 1, "upgrade": {}, "recipe_sel": "", "acc": {},
	}
	if def.has("trays"):
		b["crop"] = String(def.get("crop", "potato"))
	if bool(def.get("menu", false)):
		b["menu_off"] = {}
	return b

func _register(b: Dictionary) -> void:
	var units := 0
	for r in b["cost"]:
		units += int(b["cost"][r])
	b["inv_site"] = sim.inv.create_inv("b", b["id"], "site", units)
	sim.state["buildings"][b["id"]] = b
	sim.topo.mark_dirty()
	sim.log_event("blueprint", "%s planned." % b["name"], [b["id"]])
	if units == 0:
		b["state"] = "building"

## Scenario set-up (and test set-up): a finished structure with no construction.
func spawn_active(def_id: String, pos: Vector2, rot: float, size: int = 1) -> Dictionary:
	var def: Dictionary = sim.sizes.def_for(def_id, size)
	var b: Dictionary = _new_record(def_id, def, {}, int(def.get("size", 1)))
	b["pos"] = pos
	b["rot"] = rot
	sim.state["buildings"][b["id"]] = b
	_commission(b, false)
	return b

# ---------------------------------------------------------------- per-second flow
func tick_second() -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds.keys():
		if not blds.has(id):
			continue
		var b: Dictionary = blds[id]
		match b["state"]:
			"blueprint":
				if _site_complete(b):
					_start_work(b)
			"building":
				if float(b["progress"]) >= float(b["work_total"]):
					_commission(b, true)
			"active", "broken":
				if bool(b["demolish"]):
					_try_finish_demolition(b)

func _site_complete(b: Dictionary) -> bool:
	for res in b["cost"]:
		if sim.inv.count(b["inv_site"], res) < int(b["cost"][res]):
			return false
	return true

func missing_materials(b: Dictionary) -> Dictionary:
	var out := {}
	if b["state"] != "blueprint":
		return out
	for res in b["cost"]:
		var need: int = int(b["cost"][res]) - sim.inv.count(b["inv_site"], res)
		if need > 0:
			out[res] = need
	return out

func _start_work(b: Dictionary) -> void:
	# All materials are on site: they become part of the structure now.
	for res in b["cost"]:
		sim.inv.consume(b["inv_site"], res, int(b["cost"][res]), "built_into")
		sim.stat_add("consumed", res, int(b["cost"][res]))
	b["state"] = "building"
	b["block"] = ""
	# The structure now stands on the ground: the walking map changes.
	sim.topo.mark_dirty()

func add_progress(b: Dictionary, work_points: float) -> void:
	if b["state"] == "building":
		b["progress"] = minf(float(b["work_total"]), float(b["progress"]) + work_points)
	elif bool(b["demolish"]):
		b["progress"] = float(b["progress"]) + work_points

func _commission(b: Dictionary, announce: bool) -> void:
	var def: Dictionary = sim.bd(b)
	if b["inv_site"] != -1:
		sim.inv.dissolve_to_pile(b["inv_site"], b["pos"])
		b["inv_site"] = -1
	b["state"] = "active"
	b["progress"] = 0.0
	b["commissioned"] = int(sim.state["tick"])
	if def.has("storage"):
		b["inv_out"] = sim.inv.create_inv("b", b["id"], "store", int(def["storage"]))
	elif def.has("recipe") or def.has("trays") or def.has("output_cap"):
		b["inv_out"] = sim.inv.create_inv("b", b["id"], "out", int(def.get("output_cap", 8)))
	if int(def.get("input_cap", 0)) > 0:
		b["inv_in"] = sim.inv.create_inv("b", b["id"], "in", int(def["input_cap"]))
	if def.has("fill_port"):
		b["inv_fill"] = sim.inv.create_inv("b", b["id"], "fill", int(def["fill_port"]))
	if def.has("trays"):
		b["trays"] = []
		var crop: String = String(b.get("crop", def.get("crop", "potato")))
		for i in int(def["trays"]):
			b["trays"].append(new_tray(crop))
	if bool(def.get("airlock", false)) or bool(def.get("hatch", false)):
		b["lock"] = {"queue": [], "cyc": {}}
	sim.topo.mark_dirty()
	if announce:
		sim.log_event("commissioned", "%s is complete." % b["name"], [b["id"]])
	sim.jobs.cancel_tasks_for_building(b["id"], "done")

static func new_tray(crop: String) -> Dictionary:
	return {"state": "empty", "growth": 0.0, "interrupt": 0.0, "work": 0.0, "crop": crop, "grow": ""}

# ---------------------------------------------------------------- cancel
func cancel_blueprint(bid: int) -> Dictionary:
	var blds: Dictionary = sim.state["buildings"]
	if not blds.has(bid):
		return {"ok": false, "code": "unknown"}
	var b: Dictionary = blds[bid]
	if b["state"] != "blueprint" and b["state"] != "building":
		return {"ok": false, "code": "not_blueprint"}
	sim.jobs.cancel_tasks_for_building(bid, "cancelled")
	var drop: Vector2 = drop_point(b)
	if b["state"] == "building":
		# Materials are already built in: half come back, like a demolition.
		var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, drop)
		for res in b["cost"]:
			var back: int = int(floor(int(b["cost"][res]) * float(sim.bal["demolish_refund_fraction"])))
			if back > 0:
				sim.inv.add_new_forced(pile, res, back, "salvage")
		sim.inv.remove_if_empty_pile(pile)
	if b["inv_site"] != -1:
		sim.inv.dissolve_to_pile(b["inv_site"], drop)
	_remove_record(b)
	sim.log_event("cancelled", "%s was cancelled. Delivered materials stay on the ground." % b["name"], [])
	return {"ok": true, "code": "ok"}

# ---------------------------------------------------------------- demolition
## Returns {"ok", "code", "warnings": [text]}. Never deletes residents or stock silently.
func can_demolish(bid: int) -> Dictionary:
	var blds: Dictionary = sim.state["buildings"]
	if not blds.has(bid):
		return {"ok": false, "code": "unknown", "warnings": []}
	var b: Dictionary = blds[bid]
	var warnings: Array = []
	if b["def"] == "meridian":
		return {"ok": false, "code": "ship", "warnings": ["The Meridian cannot be taken apart."]}
	if b["state"] == "blueprint" or b["state"] == "building":
		return {"ok": true, "code": "cancel", "warnings": warnings}
	if b["def"] == "lander":
		var stock: int = sim.inv.total(b["inv_out"])
		if stock > 0:
			return {"ok": false, "code": "lander_cargo", "warnings": ["The lander still holds %s of cargo." % Text.n(stock, "unit")]}
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "alive" and (int(a["bed"]) == bid or int(a["bed"]) == -1):
				return {"ok": false, "code": "lander_beds", "warnings": ["Every resident needs a bed in a habitat first."]}
	var occupied: int = occupants(bid).size()
	if occupied > 0:
		warnings.append("%s %s inside. Work starts after %s." % [Text.n(occupied, "person", "people"), Text.be(occupied), "this person leaves" if occupied == 1 else "they leave"])
	if not (b.get("upgrade", {}) as Dictionary).is_empty():
		warnings.append("The upgrade in progress is cancelled.")
	if b["kind"] != "link":
		for lid in sim.topo.links_of.get(bid, []):
			warnings.append("%s will be removed too." % blds[lid]["name"])
	var cut: Array = _would_disconnect(bid)
	if not cut.is_empty():
		warnings.append("This disconnects %s from %s network." % [Text.n(cut.size(), "structure"), "its" if cut.size() == 1 else "their"])
	return {"ok": true, "code": "ok", "warnings": warnings}

func order_demolish(bid: int) -> Dictionary:
	var chk: Dictionary = can_demolish(bid)
	if not chk["ok"]:
		return chk
	if chk["code"] == "cancel":
		return cancel_blueprint(bid)
	var b: Dictionary = sim.state["buildings"][bid]
	if not (b.get("upgrade", {}) as Dictionary).is_empty():
		sim.upgrades.cancel(bid)
	b["demolish"] = true
	b["enabled"] = false
	b["progress"] = 0.0
	sim.jobs.cancel_tasks_for_building(bid, "demolition")
	sim.log_event("demolish", "%s is marked for removal." % b["name"], [bid])
	return {"ok": true, "code": "ok", "warnings": chk["warnings"]}

func demolish_work_total(b: Dictionary) -> float:
	var units := 0
	for r in b["cost"]:
		units += int(b["cost"][r])
	return maxf(5.0, units * float(sim.bal["work_per_material"]) * float(sim.bal["demolish_work_fraction"]))

func occupants(bid: int) -> Array:
	var out: Array = []
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		if int(a["bld"]) == bid and a["where"] != "out":
			out.append(aid)
		elif not b.is_empty() and b["kind"] == "link" and a["where"] == "in":
			if Geometry2D.get_closest_point_to_segment(a["pos"], b["p0"], b["p1"]).distance_to(a["pos"]) < 1.4:
				out.append(aid)
	return out

func _try_finish_demolition(b: Dictionary) -> void:
	if float(b["progress"]) < demolish_work_total(b):
		return
	if not occupants(b["id"]).is_empty():
		b["block"] = "occupied"
		return
	var blds: Dictionary = sim.state["buildings"]
	var drop: Vector2 = drop_point(b)
	sim.upgrades.drop_for_removal(b)
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, drop)
	for res in b["cost"]:
		var back: int = int(floor(int(b["cost"][res]) * float(sim.bal["demolish_refund_fraction"])))
		if back > 0:
			sim.inv.add_new_forced(pile, res, back, "salvage")
	for key in ["inv_in", "inv_out", "inv_fill", "inv_site"]:
		if int(b[key]) != -1:
			var inv: Dictionary = sim.inv.get_inv(b[key])
			for res in inv.get("items", {}).keys():
				var q: int = int(inv["items"][res])
				sim.inv.release_for_inventory(b[key])
				sim.inv.move(b[key], pile, res, q)
			sim.inv.dissolve_to_pile(b[key], drop)
	sim.inv.remove_if_empty_pile(pile)
	if b["kind"] != "link":
		for lid in sim.topo.links_of.get(b["id"], []).duplicate():
			if blds.has(lid):
				var l: Dictionary = blds[lid]
				if l["state"] == "blueprint" or l["state"] == "building":
					cancel_blueprint(lid)
				else:
					l["progress"] = demolish_work_total(l)
					l["demolish"] = true
					_try_finish_demolition(l)
	_remove_record(b)
	sim.log_event("demolished", "%s was removed. Half of its materials were recovered." % b["name"], [])

func _remove_record(b: Dictionary) -> void:
	var blds: Dictionary = sim.state["buildings"]
	var bid: int = b["id"]
	sim.jobs.cancel_tasks_for_building(bid, "removed")
	if b["kind"] != "link":
		for id in blds.keys():
			if not blds.has(id):
				continue
			var l: Dictionary = blds[id]
			if l["kind"] == "link" and (l["a"] == bid or l["b"] == bid) and (l["state"] == "blueprint" or l["state"] == "building"):
				cancel_blueprint(id)
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if int(a["bed"]) == bid:
			a["bed"] = -1
	blds.erase(bid)
	# Rebuild at once: later systems in this same tick must not see the removed structure.
	sim.topo.rebuild(true)

## A walkable place next to a structure where recoverable goods are put down.
func drop_point(b: Dictionary) -> Vector2:
	var pts: Array = sim.nav.access_points(b)
	if pts.is_empty():
		var q = sim.nav.nearest_walkable(b["pos"], 12)
		return q if q != null else b["pos"]
	return pts[0]

func _drop_point(b: Dictionary) -> Vector2:
	return drop_point(b)

## Structures that lose their power/water network if `bid` is removed (demolition warning).
func _would_disconnect(bid: int) -> Array:
	var topo = sim.topo
	if not topo.power_comp.has(bid):
		var b: Dictionary = sim.state["buildings"][bid]
		if b["kind"] != "link" or b["state"] != "active":
			return []
	var blds: Dictionary = sim.state["buildings"]
	var adj := {}
	for id in blds:
		var l: Dictionary = blds[id]
		if l["kind"] == "link" and l["state"] == "active" and id != bid and l["a"] != bid and l["b"] != bid:
			for pair in [[l["a"], l["b"]], [l["b"], l["a"]]]:
				if not adj.has(pair[0]):
					adj[pair[0]] = []
				adj[pair[0]].append(pair[1])
	var start := -1
	var comp_key := -1
	var target: Dictionary = blds[bid]
	if target["kind"] == "link":
		comp_key = int(topo.power_comp.get(target["a"], -1))
	else:
		comp_key = int(topo.power_comp.get(bid, -1))
	if comp_key == -1:
		return []
	var members: Array = topo.power_members.get(comp_key, [])
	# The part that keeps a generator or battery counts as "the network".
	for m in members:
		if m == bid:
			continue
		var def: Dictionary = sim.bdef(blds[m]["def"])
		if def.has("gen_solar") or def.has("gen_wind") or def.has("gen_const") or def.has("energy_cap"):
			start = m
			break
	if start == -1:
		return []
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var x: int = stack.pop_back()
		for y in adj.get(x, []):
			if not seen.has(y):
				seen[y] = true
				stack.append(y)
	var cut: Array = []
	for m in members:
		if m != bid and not seen.has(m):
			cut.append(m)
	return cut
