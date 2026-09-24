extends RefCounted
## Player commands (spec 13). The interface never edits state: it submits a command, the
## simulation validates it at the start of the next tick and records the result. The
## recorded list plus the seed reproduces a game (spec 14 replay rule).

const Text = preload("res://sim/text.gd")

var sim
var results := {}   # command id -> result, for interface feedback (not saved)

func _init(s) -> void:
	sim = s

func apply_pending() -> void:
	var queue: Array = sim.pending
	if queue.is_empty():
		return
	sim.pending = []
	for c in queue:
		var res: Dictionary = _apply(c["kind"], c["payload"])
		c["tick"] = int(sim.state["tick"])
		c["ok"] = bool(res.get("ok", false))
		c["code"] = res.get("code", "")
		results[c["id"]] = res
		sim.state["commands"].append(c)

func _apply(kind: String, p: Dictionary) -> Dictionary:
	var blds: Dictionary = sim.state["buildings"]
	match kind:
		"place_building":
			return sim.build.place_building(p["def"], Vector2(p["x"], p["y"]), float(p.get("rot", 0.0)), int(p.get("size", 1)))
		"upgrade":
			return sim.upgrades.start(int(p.get("id", -1)))
		"cancel_upgrade":
			return sim.upgrades.cancel(int(p.get("id", -1)))
		"research":
			return sim.research.cmd_research(String(p.get("tech", "")))
		"research_queue":
			return sim.research.cmd_queue(p.get("techs", []))
		"set_crop":
			if blds.has(int(p.get("id", -1))):
				return sim.prod.set_crop(blds[int(p["id"])], String(p.get("crop", "")), int(p.get("tray", -1)))
		"set_recipe":
			if blds.has(int(p.get("id", -1))):
				return sim.prod.set_recipe(blds[int(p["id"])], String(p.get("recipe", "")))
		"set_dish":
			if blds.has(int(p.get("id", -1))):
				return sim.prod.set_dish(blds[int(p["id"])], String(p.get("dish", "")), bool(p.get("on", true)))
		"set_immigration":
			return _set_immigration(p)
		"set_focus":
			if blds.has(int(p.get("id", -1))):
				return sim.research.cmd_focus(blds[int(p["id"])], String(p.get("branch", "")))
		"maintain":
			return sim.hazards.cmd_maintain(int(p.get("id", -1)))
		"shelter":
			return sim.hazards.cmd_shelter(bool(p.get("on", true)))
		"hazard_now":
			return sim.hazards.cmd_hazard_now(p)
		"survey_site":
			return sim.hazards.cmd_survey(int(p.get("id", -1)))
		"ship":
			return sim.ship.command(String(p.get("action", "")), p)
		"place_link":
			return sim.build.place_link(p["def"], int(p["a"]), int(p["b"]))
		"cancel":
			return sim.build.cancel_blueprint(int(p["id"]))
		"demolish":
			return sim.build.order_demolish(int(p["id"]))
		"undo_demolish":
			if blds.has(int(p["id"])):
				var b: Dictionary = blds[int(p["id"])]
				b["demolish"] = false
				b["enabled"] = true
				b["progress"] = 0.0
				sim.jobs.cancel_tasks_for_building(b["id"], "kept")
				return {"ok": true, "code": "ok"}
		"set_enabled":
			if blds.has(int(p["id"])):
				blds[int(p["id"])]["enabled"] = bool(p["on"])
				return {"ok": true, "code": "ok"}
		"set_building_priority":
			if blds.has(int(p["id"])):
				blds[int(p["id"])]["priority"] = clampi(int(p["value"]), 0, 3)
				return {"ok": true, "code": "ok"}
		"set_priority":
			if sim.state["policies"]["priority"].has(p["cat"]):
				sim.state["policies"]["priority"][p["cat"]] = clampi(int(p["value"]), 0, 3)
				return {"ok": true, "code": "ok"}
		"set_power_order":
			var order: Array = p["order"]
			var base: Array = sim.bal["power_class_order"]
			if order.size() == base.size():
				var all := true
				for c in base:
					all = all and order.has(c)
				if all:
					sim.state["policies"]["power_order"] = order.duplicate()
					sim.util.invalidate()
					return {"ok": true, "code": "ok"}
		"set_door":
			if blds.has(int(p["id"])) and blds[int(p["id"])]["def"] == "corridor":
				blds[int(p["id"])]["door_open"] = bool(p["open"])
				sim.topo.mark_dirty()
				return {"ok": true, "code": "ok"}
		"cancel_batch":
			if blds.has(int(p["id"])):
				sim.prod.cancel_batch(blds[int(p["id"])])
				return {"ok": true, "code": "ok"}
		"set_policy":
			sim.state["policies"][p["key"]] = p["value"]
			return {"ok": true, "code": "ok"}
		"admit_settlers":
			return _admit(int(p.get("count", 4)), p.get("roles", []))
		"ack_alert":
			if sim.state["issues"].has(p["key"]):
				sim.state["issues"][p["key"]]["ack"] = true
			return {"ok": true, "code": "ok"}
		"set_flag":
			sim.state["flags"][p["key"]] = p["value"]
			sim.log_event("flag", "Rule change: %s = %s." % [p["key"], str(p["value"])], [], 1)
			return {"ok": true, "code": "ok"}
		"kill_agent":
			# Test and debug only: logged, never silent (spec 17 "log grants and rule changes").
			if sim.state["agents"].has(int(p["id"])):
				sim.agents._die(sim.state["agents"][int(p["id"])], p.get("cause", "test"))
				return {"ok": true, "code": "ok"}
	return {"ok": false, "code": "invalid"}

## Settlers arrive by shuttle next to the lander and walk to the nearest air.
## The spec makes this a controlled event for the MVP; trade ships come in phase 5.
func _admit(count: int, roles: Array) -> Dictionary:
	if int(sim.state["progress"]["stage"]) < 1 and not bool(sim.state["flags"].get("unlock_all", false)):
		return {"ok": false, "code": "locked"}
	count = clampi(count, 1, 12)
	var allow: Array = roles if not roles.is_empty() else ["technician", "grower", "operator", "scientist", "technician", "operator", "grower", "medic"]
	_land(count, allow)
	sim.log_event("settlers", "%s landed." % Text.n(count, "settler"), [], 1)
	return {"ok": true, "code": "ok"}

func _land(count: int, allow: Array) -> void:
	var lander: Dictionary = sim.state["buildings"].get(sim.state["lander_id"], {})
	var base: Vector2 = sim.world.center + Vector2(9, 3)
	if not lander.is_empty():
		base = sim.nav.door_pos(lander) + Vector2(2.5, 0).rotated(lander["rot"])
	for i in count:
		var role: String = allow[i % allow.size()]
		var p: Vector2 = base + Vector2(1.3 * (i % 4), 1.3 * (i / 4)).rotated(0.6)
		var q = sim.nav.nearest_walkable(p, 8)
		var a: Dictionary = sim.agents.spawn(role, sim.next_name(), q if q != null else base, -1)
		a["hunger"] = 25.0
		a["thirst"] = 25.0
	var m: Dictionary = sim.state["metrics"]
	m["settlers_admitted"] = int(m.get("settlers_admitted", 0)) + count
	sim.stat_add("settlers", "", count)

## Settlers that come with a Meridian supply run: only while immigration is open, only
## the allowed roles, never above the population cap or the free beds. Returns how many.
func immigrants(max_count: int) -> int:
	var pol: Dictionary = sim.state["policies"].get("immigration", {})
	if not bool(pol.get("open", true)) or max_count <= 0:
		return 0
	var f: Dictionary = sim.metrics.forecast()
	var free_beds: int = int(f["beds"]) - int(f["pop"])
	var cap_left: int = int(pol.get("cap", 100)) - int(f["pop"])
	var n: int = mini(max_count, mini(free_beds, cap_left))
	if n <= 0:
		return 0
	var roles: Array = pol.get("roles", [])
	if roles.is_empty():
		return 0
	_land(n, roles)
	return n

## Command "set_immigration": {roles: [..], cap: int, open: bool}. Missing keys stay.
func _set_immigration(p: Dictionary) -> Dictionary:
	var pol: Dictionary = sim.state["policies"].get("immigration", sim.default_immigration())
	if p.has("roles"):
		var roles: Array = []
		for r in p["roles"]:
			if (sim.bal["roles"] as Array).has(String(r)) and not roles.has(String(r)):
				roles.append(String(r))
		pol["roles"] = roles
	if p.has("cap"):
		pol["cap"] = clampi(int(p["cap"]), 0, 500)
	if p.has("open"):
		pol["open"] = bool(p["open"])
	sim.state["policies"]["immigration"] = pol
	return {"ok": true, "code": "ok"}
