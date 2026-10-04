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
		# V5 people orders (docs/V5_DESIGN.md sections 5 and 6).
		"review":
			return sim.discipline.cmd_review(p)
		"discipline":
			return sim.discipline.cmd_discipline(p)
		"appoint":
			return sim.ranks.cmd_appoint(p)
		"set_home":
			return sim.housing.cmd_set_home(p)
		"enrol":
			return sim.education.cmd_enrol(p)
		"unrest_response":
			return sim.unrest.cmd_unrest_response(p)
		"egg":
			return sim.social.cmd_egg(p)
		"answer_request":
			return sim.relations.cmd_answer_request(p)
		"throw_party":
			return sim.party.cmd_throw(p)
		"set_option":
			return _set_option(p)
		"celebrate":
			if not bool(sim.state.get("options", {}).get("debug", false)):
				return {"ok": false, "code": "debug", "text": "Debug only."}
			return sim.party.cmd_celebrate(p)
		"staff":
			return sim.leisure.cmd_staff(p)
		"adopt":
			return sim.families.cmd_adopt(p)
		"set_role":
			return sim.ranks.cmd_set_role(p)
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
		"transport_demo":
			return sim.transport.cmd_demo(p)
		"install_transport":
			return sim.transport.cmd_install(p)
		"set_crops":
			if blds.has(int(p.get("id", -1))):
				return sim.prod.set_crop_shares(blds[int(p["id"])], p.get("beds", {}))
		"workq_move":
			return sim.workq.cmd_move(p)
		"workq_assign":
			return sim.workq.cmd_assign(p)
		"workq_cancel":
			return sim.workq.cmd_cancel(p)
		"workq_release":
			return sim.workq.cmd_release(p)
		"shelter":
			return sim.hazards.cmd_shelter(bool(p.get("on", true)))
		"hazard_now":
			return sim.hazards.cmd_hazard_now(p)
		"rename_base":
			return sim.bases.cmd_rename(p)
		"deploy_outpost":
			return sim.bases.cmd_deploy(p)
		"build_vehicle":
			return sim.vehicles.cmd_build(p)
		"cancel_vehicle":
			return sim.vehicles.cmd_cancel(p)
		"vehicle_board":
			return sim.vehicles.cmd_board(p)
		"vehicle_alight":
			return sim.vehicles.cmd_alight(p)
		"vehicle_drive":
			return sim.vehicles.cmd_drive(p)
		"vehicle_return":
			return sim.vehicles.cmd_return(p)
		"vehicle_stop":
			return sim.vehicles.cmd_stop(p)
		"vehicle_cargo":
			return sim.vehicles.cmd_cargo(p)
		"vehicle_route":
			return sim.vehicles.cmd_route(p)
		"vehicle_explore":
			return sim.vehicles.cmd_explore(p)
		"order":
			return sim.orders.cmd_order(p)
		"build_satellite":
			return sim.vehicles.cmd_build({"pad": int(p.get("pad", -1)), "kind": "satellite"})
		"reactor_scram":
			return sim.reactors.cmd_scram(p)
		"reactor_restart":
			return sim.reactors.cmd_restart(p)
		"reactor_cool":
			return sim.reactors.cmd_cool(p)
		"reactor_evacuate":
			return sim.reactors.cmd_evacuate(p)
		"order_clear":
			return sim.orders.cmd_clear(p)
		"set_jobs":
			return sim.orders.cmd_jobs(p)
		"spawn_vehicle", "debug_vehicle", "place_finished", "debug_building", "finish_building", "reactor_stage", "reveal":
			return sim.debug.run(kind, p)
		"traffic_answer":
			return sim.traffic.cmd_answer(p)
		"trade":
			return sim.traffic.cmd_trade(p)
		"traffic_now":
			return sim.traffic.cmd_now(p)
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
	sim.settler_supplies(count, base)
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

## Command "set_option" {key, value}: the setting "cheeky" (Cheeky dialogue, V5 section 16).
func _set_option(p: Dictionary) -> Dictionary:
	var key: String = String(p.get("key", ""))
	if key != "cheeky":
		return {"ok": false, "code": "invalid", "text": "Unknown option."}
	if not sim.state.has("options"):
		sim.state["options"] = {}
	sim.state["options"]["cheeky"] = bool(p.get("value", true))
	return {"ok": true, "code": "ok", "text": "Cheeky dialogue is %s." % ("on" if bool(p.get("value", true)) else "off")}

## Command "set_immigration": {roles: [..], cap: int, open: bool}. Missing keys stay.
func _set_immigration(p: Dictionary) -> Dictionary:
	var pol: Dictionary = sim.state["policies"].get("immigration", sim.default_immigration())
	if p.has("roles"):
		var roles: Array = []
		for r in p["roles"]:
			if ((sim.bal["roles"] as Array).has(String(r)) or String(r) == "security") and not roles.has(String(r)):
				roles.append(String(r))
		pol["roles"] = roles
	if p.has("cap"):
		pol["cap"] = clampi(int(p["cap"]), 0, 500)
	if p.has("open"):
		pol["open"] = bool(p["open"])
	sim.state["policies"]["immigration"] = pol
	return {"ok": true, "code": "ok"}
