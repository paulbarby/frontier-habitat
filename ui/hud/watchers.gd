extends RefCounted
## Watches the state for events the player must see, and answers them once:
## new awards (medal pop-up, device profile), goals done, a new chapter, research done,
## victory, the loss report, new stages (version 1), and structures finished.
##
## Rules (orchestrator review, 2026-09-24):
## - What a colony already has when it is loaded or started never pops up. A save made by an
##   older version catches up on goals and awards in its first seconds: everything that
##   appears in the first GRACE_SECONDS after a load is recorded silently, and one summary
##   toast says how many awards the colony has.
## - Nothing pops up and nothing enters the device profile on the title screen: the colony
##   behind the title is a showcase, not the player's.

const Profile = preload("res://ui/profile.gd")
const Sfx = preload("res://ui/sfx.gd")
const Kit = preload("res://ui/kit.gd")
const AlertGate = preload("res://ui/hud/alert_gate.gd")
const WorldSounds = preload("res://ui/hud/world_sounds.gd")

const GRACE_SECONDS := 30.0
## Log codes that toast (sim/hazards.gd, version 3). SIM's alerts already cover an event
## in its warning phase, hull breaches and broken machines; the alert gate toasts those once.
## These are the one-off moments. Not here: "breach" and "fault" (the alert toasts them),
## "maintained" (routine), "hazard_warning" (the alert).
const HAZARD_LOG := {"hazard_detected": ["info", "hazard"], "hazard_start": ["warn", "hazard"], "hazard_impact": ["warn", "meteor"],
	"hazard_intercepted": ["good", "turret"], "hazard_end": ["good", "sev_ok"], "breach_sealed": ["good", "wrench"],
	"shelter": ["info", "shelter"], "survey": ["research", "exotic"],
	# Ships (sim/traffic.gd, version 3.1). ship_orbit, ship_takeoff, ship_gone: the traffic panel shows them.
	"ship_forecast": ["info", "ship"], "ship_landing": ["info", "ship"], "ship_landed": ["good", "ship"],
	"ship_denied": ["info", "ship"], "ship_left": ["warn", "ship"], "trade": ["good", "credits"],
	# Version 5 society (sim/relations.gd, education.gd, ranks.gd): the big moments of people's lives.
	# Feuds, flings, promotions, discipline and unrest answers are not toasted (the Rag shows them; the
	# player gave the order and got its answer).
	"couple": ["info", "heart"], "partners": ["info", "heart"], "wedding": ["good", "heart"], "breakup": ["info", "heart"],
	"affair": ["warn", "heart"], "defect_request": ["warn", "heart"], "defected": ["warn", "ship"],
	"graduated": ["good", "research"], "unrest": ["warn", "people"],
	# Homes, families, security, the dome and the eggs (sim/families.gd, security.gd, leisure.gd, eggs.gd).
	"move_in": ["info", "home"], "request_shared_home": ["warn", "home"], "adoption": ["good", "people"], "grew_up": ["good", "people"],
	"fight": ["warn", "sev_warning"], "arrest": ["warn", "people"], "released": ["info", "people"], "dome_stage": ["good", "build"],
	"arcade_record": ["info", "trophy"], "barby": ["good", "ship"], "dance": ["good", "people"]}

## Parties and HR (V5 sections 16 and 17; sim/party.gd, sim/hr.gd): log code -> [priority, icon, panel manager type,
## pops up]. Small drama only goes to the News tab (a badge); big drama pops up once; a party offer and the HR
## requests have their rows in the Requests tab and a notice here.
const PARTY_LOG := {
	"party_offer": ["notice", "music", "request", true], "party_start": ["info", "music", "party", true], "party_end": ["info", "music", "party", false],
	"party_drama": ["info", "sparkle", "party", false], "party_drama_big": ["warning", "heart", "party", true],
	"birthday": ["info", "sparkle", "party", false], "celebration": ["info", "sparkle", "party", false],
	"hr_complaint": ["info", "colonists", "hr", false], "hr_resolved": ["notice", "sev_ok", "hr", false], "hr_survey": ["info", "list", "hr", true],
	"hr_transfer_request": ["warning", "ship", "hr", true], "hr_transfer_approved": ["info", "ship", "hr", false], "hr_transfer_refused": ["info", "ship", "hr", false],
}

## Orders (V5 section 18; sim/orders.gd, sim/workq.gd): log code -> [priority, icon, panel manager type, pops up]. A head reports a
## team order, an order ends. These show also in the first seconds after a load (a player who gives an order while the game
## is paused after a load still sees the report).
const ORDER_LOG := {
	"team_order": ["info", "people", "orders", true], "team_done": ["info", "sev_ok", "orders", true], "order_done": ["info", "wrench", "orders", false],
	"order_ended": ["info", "orders", "orders", false],
}

var hud
var gate = AlertGate.new()   # alert toasts and the steady alert list (V3_DESIGN §2)
var world                    # world sounds from simulation state (V3_1_DESIGN §2.2)
var _awards := {}
var _goals_done := {}
var _chapter := -1
var _techs := {}
var _victory := false
var _lost := false
var _stage := -1
var _log_tick := -1
var _log_last = null     # the newest log entry seen (compared by value; see the log walk)
var _unseen := 0
var _primed := false
var _grace_tick := 0
var _grace_silent := 0
var _grace_open := false

func _init(h) -> void:
	hud = h
	world = WorldSounds.new(h)

## After a load or a new game: take the current state as known, so nothing old pops up.
func reset() -> void:
	var d = hud.data
	var st: Dictionary = hud.main.sim.state
	_awards = d.awards_state().duplicate()
	_goals_done = {}
	for id in d.goals_state().get("status", {}):
		if String(d.goals_state()["status"][id].get("state", "")) == "done":
			_goals_done[id] = true
	_chapter = d.chapter_index()
	_techs = d.research().get("done", {}).duplicate()
	_victory = d.victory()
	_lost = bool(st["progress"].get("lost", false))
	_stage = int(st["progress"].get("stage", 0))
	var log: Array = st.get("log", [])
	_log_tick = int(log[log.size() - 1]["tick"]) if not log.is_empty() else -1
	_log_last = log[log.size() - 1] if not log.is_empty() else null
	_primed = true
	_unseen = 0
	_grace_tick = int(st["tick"]) + int(GRACE_SECONDS * float(hud.main.sim.bal["tick_hz"]))
	_grace_silent = 0
	_grace_open = true
	# What is wrong when a colony is loaded is shown in the list, not toasted.
	gate.reset()
	gate.update(hud.main.sim.alerts.incidents(), hud.main.sim.seconds(), true)
	world.reset()
	if not _title():
		for id in _awards:
			Profile.record_award(String(id), int(_awards[id]), int(st.get("seed", 0)), false)

func _title() -> bool:
	return bool(hud.main.on_title)

func unseen_awards() -> int:
	return _unseen

func clear_unseen() -> void:
	_unseen = 0

func check() -> void:
	if not _primed:
		reset()
		return
	var d = hud.data
	var st: Dictionary = hud.main.sim.state
	var in_grace: bool = int(st["tick"]) < _grace_tick
	var quiet: bool = in_grace or _title()
	# Awards
	var aw: Dictionary = d.awards_state()
	for id in aw:
		if _awards.has(id):
			continue
		_awards[id] = aw[id]
		if _title():
			continue
		if in_grace:
			Profile.record_award(String(id), int(aw[id]), int(st.get("seed", 0)), false)
			_grace_silent += 1
		else:
			var first: bool = Profile.record_award(String(id), int(aw[id]), int(st.get("seed", 0)), true)
			_unseen += 1
			hud.screens.award_popup(String(id), first)
	if _grace_open and not in_grace:
		_grace_open = false
		if _grace_silent > 0 and not _title():
			hud.toast("This colony has %s. The awards gallery (V) lists them." % Kit.plural(aw.size(), "award"), "award", "medal")
	# Goals
	var status: Dictionary = d.goals_state().get("status", {})
	for id in status:
		if String(status[id].get("state", "")) == "done" and not _goals_done.has(id):
			_goals_done[id] = true
			if not quiet:
				hud.toast("Goal done: %s. %s" % [_goal_name(String(id)), _reward_line(String(id))], "goal", "sev_ok")
	var ch: int = d.chapter_index()
	if ch != _chapter:
		var chs: Array = d.chapters()
		if ch > _chapter and ch < chs.size() and not quiet:
			hud.screens.chapter_banner(ch)   # one message in the panel manager (was a toast and a banner)
		_chapter = ch
	# Research
	var done: Dictionary = d.research().get("done", {})
	for t in done:
		if not _techs.has(t):
			_techs[t] = true
			if not quiet:
				hud.toast("Research complete: %s. %s" % [d.tech_name(String(t)), String(d.techs().get(t, {}).get("desc", ""))], "research", "research")
	# Victory and loss
	var v: bool = d.victory()
	if v and not _victory:
		_victory = true
		if not _title():
			hud.open_screen("victory")
	var lost: bool = bool(st["progress"].get("lost", false))
	if lost and not _lost:
		_lost = true
		if not _title():
			hud.open_screen("lost")
	# Stages (version 1 progression)
	var stage: int = int(st["progress"].get("stage", 0))
	if stage > _stage:
		_stage = stage
		var stages: Array = hud.main.sim.bal.get("stages", [])
		if stage < stages.size() and not quiet:
			hud.toast("New stage: %s." % stages[stage]["name"], "good", "star")
	# World sounds: airlock phases, impacts, storms, ships (the old single airlock sound is gone).
	world.check(_title())
	# Alerts: one toast per new key (warnings and critical only), never again for 180 s
	# after it cleared. The alert cards read the same gate.
	for issue in gate.update(hud.main.sim.alerts.incidents(), hud.main.sim.seconds(), quiet):
		var sv: int = int(issue.get("severity", 2))
		hud.toast(String(issue.get("text", "")), "bad" if sv >= 3 else "warn", "sev_critical" if sv >= 3 else "sev_warning", "alert")
	# Log: finished structures, settlers, pods, upgrades, deaths
	var log: Array = st.get("log", [])
	if not _title():
		for i in range(log.size() - 1, -1, -1):
			var e: Dictionary = log[i]
			# The last entry seen stops the walk (entries of one tick, logged while paused, after it still
			# count: a v5 order at speed 0); by tick only when that entry has left the capped log.
			if _log_last != null and e == _log_last:
				break
			if int(e["tick"]) < _log_tick or (_log_last == null and int(e["tick"]) <= _log_tick):
				break
			if quiet and not ORDER_LOG.has(String(e.get("code", ""))):
				continue
			match String(e.get("code", "")):
				"commissioned":
					hud.toast(String(e["text"]), "good", "build")
					_world_at("construct", e)
				"settlers":
					hud.toast(String(e["text"]), "info", "people")
				"upgraded":
					hud.toast(String(e["text"]), "good", "upgrade")
					_world_at("construct", e)
				"ship", "ship_run", "ship_flight":
					hud.toast(String(e["text"]), "info", "ship")
				"storm_warning", "storm":
					hud.toast(String(e["text"]), "warn", "wind")
				"storm_end":
					hud.toast(String(e["text"]), "good", "wind")
				"crop_lost":
					# "broken" is not here: the alert gate toasts the broken:<id> alert once.
					hud.toast(String(e["text"]), "warn", "sev_warning", "alert")
				"research_paid":
					hud.toast(String(e["text"]), "research", "exotic")
				"death":
					hud.toast(String(e["text"]), "bad", "sev_critical", "people")
				var code:
					if ORDER_LOG.has(String(code)):
						var os: Array = ORDER_LOG[String(code)]
						hud.panels.post(String(os[2]), String(e["text"]), String(os[0]), String(os[1]), bool(os[3]))
					elif PARTY_LOG.has(String(code)):
						var ps: Array = PARTY_LOG[String(code)]
						hud.panels.post(String(ps[2]), String(e["text"]), String(ps[0]), String(ps[1]), bool(ps[3]))
					elif HAZARD_LOG.has(String(code)):
						var spec: Array = HAZARD_LOG[String(code)]
						var ty: String = "request" if String(code).begins_with("request_") or String(code) == "defect_request" else ({"unrest": "unrest", "dome_stage": "build", "graduated": "people"}.get(String(code), ""))
						hud.toast(String(e["text"]), spec[0], spec[1], ty)
						if String(code) == "ship_landed" and hud.main.audio != null:
							hud.main.audio.music.cue("mus_arrival")   # also started by RENDER's ship_touchdown sound
						elif String(code) == "trade":
							Sfx.play("trade_chime")
	if not log.is_empty():
		_log_tick = maxi(_log_tick, int(log[log.size() - 1]["tick"]))
		_log_last = log[log.size() - 1]

## A world sound at the log entry's first structure (only heard zoomed in and close: audio.gd rules).
func _world_at(name: String, e: Dictionary) -> void:
	var ents: Array = e.get("entities", [])
	var blds: Dictionary = hud.main.sim.state["buildings"]
	if hud.main.audio != null and not ents.is_empty() and blds.has(int(ents[0])):
		hud.main.audio.world(name, blds[int(ents[0])]["pos"])

func _goal_name(id: String) -> String:
	for ch in hud.data.chapters():
		for g in ch.get("goals", []):
			if String(g["id"]) == id:
				return String(g["name"])
	return id

func _reward_line(id: String) -> String:
	for ch in hud.data.chapters():
		for g in ch.get("goals", []):
			if String(g["id"]) == id:
				var rw: Dictionary = g.get("reward", {})
				var parts: Array = []
				for it in rw.get("items", {}):
					parts.append("%d %s" % [int(rw["items"][it]), hud.data.item_name(String(it)).to_lower()])
				if float(rw.get("rp", 0)) > 0.0:
					parts.append("%d RP" % int(rw["rp"]))
				if parts.is_empty():
					return ""
				return "Supply pod at the lander: " + ", ".join(parts) + "."
	return ""
