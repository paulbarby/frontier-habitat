extends RefCounted
## Advisor (V4_DESIGN §6): "what to do next", from the colony state only.
##   Advisor.tips(hud) -> [{kind, icon, color, title, text, focus}]
##   kind: "problem" (the biggest problems first), "next" (the next goal steps), "unused" (unused
##   potential). focus: a structure id (int), a position (Vector2) or null.
## Rules are plain and deterministic; every tip says what to do, not only what is wrong.

const P = preload("res://ui/theme/palette.gd")

static func tips(hud) -> Array:
	var out: Array = []
	var s = hud.main.sim
	var d = hud.data
	var k: Dictionary = hud.kpi if not hud.kpi.is_empty() else d.kpis()
	# ---- problems: the worst live alerts first (critical, then the soonest forecast)
	var inc: Array = s.alerts.incidents()
	var live: Array = []
	for i in inc:
		if bool(i["issue"].get("live", true)):
			live.append(i)
	live.sort_custom(func(a, b):
		var sa: int = int(a["issue"]["severity"])
		var sb: int = int(b["issue"]["severity"])
		if sa != sb:
			return sa > sb
		var fa: float = float(a["issue"].get("forecast", 1e9))
		var fb: float = float(b["issue"].get("forecast", 1e9))
		return (fa if fa >= 0.0 else 1e9) < (fb if fb >= 0.0 else 1e9))
	for i in live.slice(0, 2):
		var iss: Dictionary = i["issue"]
		var ents: Array = iss.get("entities", [])
		out.append({"kind": "problem", "icon": P.sev_icon(int(iss["severity"])), "color": P.sev(int(iss["severity"])),
			"title": String(iss["text"]), "text": "Do: " + String(iss.get("action", "")), "focus": int(ents[0]) if not ents.is_empty() else null})
	# Supplies running low that no alert names yet.
	var pop: int = int(k["pop"]["value"])
	if pop > 0 and float(k["food"]["days"]) < 2.0:
		out.append({"kind": "problem", "icon": "food", "color": P.AMBER, "title": "Food for %.1f days." % float(k["food"]["days"]),
			"text": "Do: plant more crops and keep a cook in the kitchen.", "focus": null})
	if pop > 0 and float(k["water"]["days"]) < 2.0:
		out.append({"kind": "problem", "icon": "water", "color": P.AMBER, "title": "Water for %.1f days." % float(k["water"]["days"]),
			"text": "Do: build a water extractor or a recycler, with a reservoir on the same network.", "focus": null})
	if float(k["power"]["net"]) < 0.0:
		out.append({"kind": "problem", "icon": "power", "color": P.AMBER, "title": "Power use is %.1f P above generation." % -float(k["power"]["net"]),
			"text": "Do: build solar or wind, and batteries for the night.", "focus": null})
	# ---- next goal steps
	var goals: Array = hud.goals._goals() if hud.goals != null else []
	var ci: int = d.chapter_index()
	var n := 0
	for g in goals:
		if int(g.get("chapter", -1)) != ci or String(g.get("state", "")) == "done":
			continue
		var prog: String = ""
		if float(g.get("target", 0.0)) > 0.0:
			prog = " (%s of %s)" % [_num(float(g["value"])), _num(float(g["target"]))]
		var hint: String = String(g.get("hint", ""))
		out.append({"kind": "next", "icon": "goals", "color": P.CYAN, "title": String(g["name"]) + prog,
			"text": hint if hint != "" else String(g.get("desc", "")), "focus": null})
		n += 1
		if n >= 2:
			break
	# ---- unused potential
	var idle := {}
	for aid in s.state["agents"]:
		var a: Dictionary = s.state["agents"][aid]
		if String(a.get("state", "")) != "alive" or d.is_visitor(a):
			continue
		if String(a.get("goal", "")) == "Idle":
			var r: String = String(a.get("role", ""))
			idle[r] = int(idle.get(r, 0)) + 1
	for r in idle:
		if int(idle[r]) >= 2:
			var rn: String = String(s.bal.get("role_names", {}).get(r, r)).to_lower()
			out.append({"kind": "unused", "icon": "people", "color": P.VIOLET,
				"title": "%d %ss have no work." % [int(idle[r]), rn], "text": "Build structures that need a %s, or raise the priority of ones waiting for workers." % rn, "focus": null})
	var res: Dictionary = k["research"]
	if bool(res.get("available", false)) and String(res.get("active", "")) == "":
		out.append({"kind": "unused", "icon": "research", "color": P.VIOLET, "title": "No research project.",
			"text": "Labs make no progress. Pick a project on the research screen (T).", "focus": null})
	var off: Array = []
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		if String(b["state"]) == "active" and not bool(b.get("enabled", true)):
			off.append(int(id))
	if not off.is_empty():
		out.append({"kind": "unused", "icon": "power", "color": P.VIOLET, "title": "%d structure(s) switched off." % off.size(),
			"text": "Switch them on when power allows.", "focus": off[0]})
	if pop > 0 and int(k["pop"]["beds"]) - pop >= 4:
		out.append({"kind": "unused", "icon": "people", "color": P.VIOLET, "title": "%d free beds." % (int(k["pop"]["beds"]) - pop),
			"text": "The colony has room for settlers: the shuttle brings them when settlers may come.", "focus": null})
	if float(k["power"]["net"]) > 8.0 and float(k["energy"]["value"]) >= float(k["energy"]["cap"]) * 0.95:
		out.append({"kind": "unused", "icon": "power", "color": P.VIOLET, "title": "Power to spare (+%.0f) and batteries full." % float(k["power"]["net"]),
			"text": "There is room for more machines on the network.", "focus": null})
	return out

static func _num(v: float) -> String:
	return ("%d" % int(v)) if absf(v - roundf(v)) < 0.01 else ("%.1f" % v)
