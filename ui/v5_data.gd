extends RefCounted
## Version-5 SIM data (V5_DESIGN §2–§6, docs/requests/SIM-to-UI.md v5) behind one adapter, so the
## windows do not change when SIM publishes its names. `live(system)` is true when SIM has the system;
## until then the Rag reads the preview issues of ui/mock_rag.gd (real colonists, alerts and days).
## Photos (V5_DESIGN §4.4) come from RENDER's view.photo(agent_ids, place_hint, pose_hint); until
## that lands, the Rag draws a placeholder.

const MockRag = preload("res://ui/mock_rag.gd")

var hud
var _rag_cache: Array = []
var _rag_key := ""

func _init(h) -> void:
	hud = h

func _sim():
	return hud.main.sim

## SIM systems and the method that proves each one is there.
const LIVE := {"social": "rag_issues", "people": "outfit", "ranks": "org", "unrest": "level"}

func live(system: String) -> bool:
	var s = _sim()
	if s == null or not LIVE.has(system):
		return false
	var o = s.get(system)
	return o != null and o is Object and (o as Object).has_method(String(LIVE[system]))

# ---------------------------------------------------------------- the Regolith Rag
## The issues, newest first (up to 30 back issues).
func rag_issues() -> Array:
	var s = _sim()
	if live("social"):
		var key2: String = "sim:%d:%d" % [int(s.state.get("tick", 0)) / 600, (s.state.get("log", []) as Array).size()]
		if key2 != _rag_key:
			_rag_key = key2
			_rag_cache = []
			var r = s.social.rag_issues()
			for iss in (r if typeof(r) == TYPE_ARRAY else []):
				_rag_cache.append(norm_rag(iss))
		return _rag_cache
	var key: String = "%d:%d" % [int(s.state.get("tick", 0)) / 600, s.state["agents"].size()]
	if key != _rag_key:
		_rag_key = key
		_rag_cache = MockRag.issues(s, hud, 5)
	return _rag_cache

## SIM's issue (sim.social.rag_issues: {number, day, masthead, tagline, lead, stories, gossip [text],
## couple_watch, feud_watch, poll {approval, question}, ads [text], serious [text]}) in the shape the
## window draws (ui/mock_rag.gd header). Parts SIM does not give yet are made from what it gives: the
## kicker from the story kind, the caption from the actors, the ad title from its first capital words.
const KICKER := {"couple": "LOVE", "date": "LOVE", "breakup": "HEARTBREAK", "affair": "SCANDAL", "fight": "PUNCH-UP", "arrest": "NICKED",
	"promotion": "TOP DOG", "protest": "UPROAR", "wedding": "WEDDING", "new_building": "BUILT!", "death": "TRAGEDY", "ship": "ARRIVALS", "quiet": "EXCLUSIVE"}
const TAG := {"couple": "LOVE", "date": "LOVE", "breakup": "LOVE", "affair": "SCANDAL", "fight": "FEUD", "arrest": "CRIME", "promotion": "WORK",
	"protest": "UNREST", "wedding": "LOVE", "new_building": "BUILDING", "death": "NEWS", "ship": "ARRIVALS", "quiet": "NEWS"}

func norm_rag(iss: Dictionary) -> Dictionary:
	if iss.has("no"):
		return iss
	var lead: Dictionary = iss.get("lead", {})
	var actors: Array = lead.get("actors", [])
	var names: Array = []
	for a in actors:
		names.append(agent_name(int(a)).get_slice(" ", 0))
	var ph: Dictionary = lead.get("photo", {})
	var kind: String = String(lead.get("kind", "quiet"))
	var out := {"no": int(iss.get("number", iss.get("day", 0))), "day": int(iss.get("day", 0)), "price": "1 credit",
		"masthead": String(iss.get("masthead", "THE REGOLITH RAG")), "tagline": String(iss.get("tagline", "")),
		"lead": {"kind": kind, "kicker": String(KICKER.get(kind, "EXCLUSIVE")), "headline": String(lead.get("headline", "")),
			"sub": String(lead.get("place", "")) if String(lead.get("place", "")) != "COLONY" else "", "body": String(lead.get("text", "")),
			"actors": actors, "photo": {"agents": ph.get("agents", actors), "place": String(ph.get("place_hint", "")), "pose": String(ph.get("pose_hint", "talk_idle"))},
			"caption": ("PICTURED: " + " AND ".join(names).to_upper() + ". Rag snapper.") if not names.is_empty() else "THE RAG WAS THERE. Rag snapper."},
		"stories": [], "gossip": [], "couples": [], "feuds": [], "ads": [], "serious": []}
	for s in iss.get("stories", []):
		out["stories"].append({"tag": String(TAG.get(String(s.get("kind", "")), "NEWS")), "headline": String(s.get("headline", "")),
			"body": String(s.get("text", "")), "actors": s.get("actors", [])})
	for g in iss.get("gossip", []):
		out["gossip"].append({"text": String(g.get("text", g)) if typeof(g) == TYPE_DICTIONARY else String(g), "actors": g.get("actors", []) if typeof(g) == TYPE_DICTIONARY else []})
	for c in iss.get("couple_watch", []):
		out["couples"].append({"a": int(c["a"]), "b": int(c["b"]), "status": String(c.get("status", "dating")), "note": String(c.get("note", ""))})
	for fd in iss.get("feud_watch", []):
		out["feuds"].append({"a": int(fd["a"]), "b": int(fd["b"]), "note": String(fd.get("note", String(fd.get("status", "")).capitalize() + "s."))})
	for ad in iss.get("ads", []):
		var txt: String = String(ad.get("text", ad)) if typeof(ad) == TYPE_DICTIONARY else String(ad)
		var words: PackedStringArray = txt.split(" ")
		var title := ""
		var k := 0
		while k < words.size() and words[k] == words[k].to_upper() and words[k].strip_edges() != "":
			title += (" " if title != "" else "") + words[k].trim_suffix(":")
			k += 1
		out["ads"].append({"title": title if title != "" else "NOTICE", "text": " ".join(words.slice(k)) if title != "" else txt})
	for sv in iss.get("serious", []):
		out["serious"].append({"text": String(sv.get("text", sv)) if typeof(sv) == TYPE_DICTIONARY else String(sv), "severity": int(sv.get("severity", 2)) if typeof(sv) == TYPE_DICTIONARY else 2})
	if (out["serious"] as Array).is_empty():
		out["serious"].append({"text": "No serious problem today. Air, water, food and power hold.", "severity": 0})
	var poll: Dictionary = iss.get("poll", {})
	var ap: int = int(roundf(float(poll.get("approval", poll.get("approve", 50)))))
	out["poll"] = {"commander": int(poll.get("commander", _commander())), "approve": ap, "change": int(poll.get("change", 0)),
		"question": String(poll.get("question", "Do you approve of the commander?"))}
	return out

## The base commander (SIM ranks when live, else the colonist with the lowest id).
func _commander() -> int:
	var s = _sim()
	if live("ranks") and s.ranks.has_method("commander"):
		return int(s.ranks.commander(-1))
	var best := -1
	for aid in s.state["agents"]:
		if String(s.state["agents"][aid].get("state", "")) == "alive" and (best == -1 or int(aid) < best):
			best = int(aid)
	return best

func preview() -> bool:
	return not live("social")

## A photo for a story, or null (the Rag draws its placeholder).
func photo(agents: Array, place: String, pose: String) -> Texture2D:
	var v = hud.main.view
	if v != null and v.has_method("photo"):
		var t = v.photo(agents, place, pose)
		if t is Texture2D:
			return t
	return null

func agent(id: int) -> Dictionary:
	return _sim().state["agents"].get(id, {})

func agent_name(id: int) -> String:
	return String(agent(id).get("name", "Someone"))

# ---------------------------------------------------------------- people (V5 §2, §5, §6)
func person(id: int) -> Dictionary:
	var a: Dictionary = agent(id)
	if a.is_empty() or not live("people"):
		return {}
	var s = _sim()
	return {"agent": a, "id": id, "name": String(a["name"]), "identity": s.people.identity(a), "rank": s.people.rank(a), "skills": s.people.skills(a),
		"satisfaction": s.people.satisfaction(a), "attitude": s.people.attitude(a), "home": s.people.home(a), "outfit": s.people.outfit(a),
		"role": String(a.get("role", "")), "activity": String(a.get("goal", ""))}

func people() -> Array:
	return _sim().people.list() if live("people") else []

func relations(id: int, n: int = 12) -> Array:
	var s = _sim()
	return s.social.relationships_of(id, n) if s.get("social") != null and s.social.has_method("relationships_of") else []

func recent_lines(id: int, n: int = 3) -> Array:
	var s = _sim()
	return s.social.recent_lines(id, n) if s.get("social") != null and s.social.has_method("recent_lines") else []

func talk_of(id: int) -> Dictionary:
	var s = _sim()
	if s.get("social") == null or not s.social.has_method("talks"):
		return {}
	for t in s.social.talks():
		if int(t.get("a", -1)) == id or int(t.get("b", -1)) == id:
			return t
	return {}

var unrest_override := {}   # debug `unrest <stage> [value]` (screenshots and tests; debug=1 or tests only)
func unrest(base_id: int = -1) -> Dictionary:
	var s = _sim()
	if not unrest_override.is_empty():
		return unrest_override
	# SIM's unrest system (sim.unrest.info) when it is there, else the social stub.
	var un = s.get("unrest")
	if un != null and un is Object and (un as Object).has_method("info"):
		return un.info(base_id)
	return s.social.unrest(base_id) if s.get("social") != null and s.social.has_method("unrest") else {}

const STATUS_NAME := {"acquaintance": "Acquaintance", "friend": "Friend", "best_friend": "Best friend", "rival": "Rival", "enemy": "Enemy",
	"crush": "Crush", "dating": "Dating", "partners": "Partner", "married": "Married", "ex": "Ex", "affair": "Affair", "stranger": "Stranger"}

## Mood face 0..4 from satisfaction (0 = very unhappy).
static func mood(v: float) -> int:
	return clampi(int(v / 20.0), 0, 4)

## Player names of the outfits (critic round 36: never the raw id).
const OUTFIT_NAME := {"uniform_engineering": "Engineering uniform", "uniform_science": "Science uniform", "uniform_food": "Food uniform",
	"uniform_medical": "Medical uniform", "uniform_security": "Security uniform", "uniform_command": "Command uniform",
	"casual_a": "Casual clothes", "casual_b": "Casual clothes", "casual_c": "Casual clothes", "swimwear": "Swimwear",
	"prison": "Prison overalls", "school": "School uniform", "suit": "Space suit"}
static func outfit_name(id: String) -> String:
	if OUTFIT_NAME.has(id):
		return String(OUTFIT_NAME[id])
	var parts: PackedStringArray = id.split("_")
	if parts.size() == 2 and parts[0] == "uniform":
		return parts[1].capitalize() + " uniform"
	return id.replace("_", " ").capitalize()

## Mood faces (critic round 30): very unhappy .. happy.
const MOOD_ICON := ["mood_0", "mood_1", "mood_2", "mood_3", "mood_4"]
const MOOD_COL := [Color("FF5A5F"), Color("FFB547"), Color("B7C6D6"), Color("6EE7A8"), Color("FFD166")]
const MOOD_NAME := ["Very unhappy", "Unhappy", "So-so", "Content", "Happy"]
const PUNISH := ["warning", "extra_shift", "ration_cut", "confine", "demote", "jail", "poor", "needs_improvement"]

## Is a punishment unfair (critic round 30, fix 3)? SIM decides when people.predict gives "unfair";
## until then: unfair when the person's attitude is fair or good (0 or more), i.e. nothing to punish.
func unfair(id: int, action: String, pr: Dictionary = {}) -> String:
	if not (action in PUNISH):
		return ""
	if pr.has("unfair"):
		return String(pr["unfair"]) if typeof(pr["unfair"]) == TYPE_STRING else ("Others will see this as unfair." if bool(pr["unfair"]) else "")
	var p: Dictionary = person(id)
	if p.is_empty():
		return ""
	var av: float = float(p["attitude"]["value"])
	if av < 0.0:
		return ""
	var friends: int = 0
	for r in relations(id, 12):
		if String(r["status"]) in ["friend", "best_friend", "dating", "partners", "married"]:
			friends += 1
	return "%s's attitude is %s (%+d): there is no bad conduct to punish. %d friends will call it unfair: fairness falls and unrest rises." % [agent_name(id).get_slice(" ", 0), "good" if av >= 20.0 else "fair", int(av), friends]

## Who else sees an action: the friends and partner (first names), for the confirm.
func witnesses(id: int, n: int = 4) -> Array:
	var out: Array = []
	for r in relations(id, 12):
		if String(r["status"]) in ["friend", "best_friend", "dating", "partners", "married"]:
			out.append(agent_name(int(r["other"])).get_slice(" ", 0))
			if out.size() >= n:
				break
	return out

# ---------------------------------------------------------------- reviews and discipline (V5 §6.2, §6.3)
## SIM gives the prediction when it has sim.people.predict(a, action, params); until then the UI
## predicts from V5 §6.3 and the person's traits (marked as an estimate).
const REVIEWS := [["excellent", "Excellent"], ["good", "Good"], ["needs_improvement", "Needs improvement"], ["poor", "Poor"]]
const ACTIONS := [
	["praise", "Praise", "A public thank-you."],
	["bonus_leisure", "Bonus leisure", "A free half-day for leisure."],
	["gift", "Gift", "A gift from the shop stock."],
	["warning", "Verbal warning", "A talk in private."],
	["extra_shift", "Extra shift", "One more shift today."],
	["ration_cut", "Ration cut", "Half meals for 2 days."],
	["confine", "Confine to quarters", "No work, no leisure for 1 day."],
	["demote", "Demotion", "One rank down."],
	["jail", "Jail", "2 days in a cell. Needs a jail."],
]

func predict(id: int, action: String) -> Dictionary:
	var s = _sim()
	var a: Dictionary = agent(id)
	if a.is_empty():
		return {}
	# SIM's prediction: sim.discipline.predict (v5 discipline system), or sim.people.predict.
	for sysn in ["discipline", "people"]:
		var o = s.get(sysn)
		if o != null and o is Object and (o as Object).has_method("predict"):
			var r = o.predict(a, action, {})
			if typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).is_empty():
				return r
	var tr: Array = s.people.identity(a)["traits"] if live("people") else []
	var hot: bool = tr.has("hot-headed")
	var loyal: bool = tr.has("loyal") or tr.has("calm")
	var amb: bool = tr.has("ambitious") or tr.has("workaholic")
	var p := {"attitude": 0, "satisfaction": 0, "others": "", "risk": "", "estimate": true}
	match action:
		"excellent": p = {"attitude": 10 if amb else 6, "satisfaction": 8, "others": "Small envy from rivals.", "risk": ""}
		"good": p = {"attitude": 6 if amb else 3, "satisfaction": 4, "others": "", "risk": ""}
		"needs_improvement": p = {"attitude": -6 if hot else (4 if loyal else 1), "satisfaction": -4, "others": "", "risk": ""}
		"poor": p = {"attitude": -15 if hot else (3 if loyal else -4), "satisfaction": -10, "others": "", "risk": "May answer back or argue." if hot else ""}
		"praise": p = {"attitude": 5, "satisfaction": 6, "others": "Small envy from rivals.", "risk": ""}
		"bonus_leisure": p = {"attitude": 4, "satisfaction": 10, "others": "Small envy.", "risk": "No work for half a day."}
		"gift": p = {"attitude": 3, "satisfaction": 8, "others": "Small envy.", "risk": "Uses 1 gift from the shop."}
		"warning": p = {"attitude": -4 if hot else (5 if loyal else 2), "satisfaction": -2, "others": "None.", "risk": ""}
		"extra_shift": p = {"attitude": -3, "satisfaction": -8, "others": "None.", "risk": "Tired: works slower tomorrow."}
		"ration_cut": p = {"attitude": 8, "satisfaction": -15, "others": "Friends feel it is unfair (fairness down).", "risk": "Hunger and health risk."}
		"confine": p = {"attitude": -10 if hot else 6, "satisfaction": -10, "others": "Fairness down a little.", "risk": "No work for a day."}
		"demote": p = {"attitude": -20 if hot else -10, "satisfaction": -20, "others": "A rival is happy. The Rag will hear of it.", "risk": "May start a feud."}
		"jail": p = {"attitude": -25 if hot else 10, "satisfaction": -30, "others": "Fairness down if others think it unfair. Unrest up.", "risk": "Attitude may harden."}
	p["estimate"] = true
	return p

## Sends a v5 order. SIM command names (proposed in UI-to-SIM.md): review, discipline, appoint,
## enrol, set_home, unrest_response. Returns {ok, code, text}. When SIM does not know the command yet
## the text says so; nothing is changed.
func command(kind: String, payload: Dictionary) -> Dictionary:
	var cid = hud.main.submit(kind, payload)
	var res: Dictionary = _sim().cmds.results.get(cid, {})
	if res.is_empty():
		return {"ok": true, "code": "submitted", "text": "Order given."}
	if String(res.get("code", "")) == "invalid" and not live_command(kind):
		return {"ok": false, "code": "not_yet", "text": "The simulation does not take this order yet (version 5 is being built)."}
	return {"ok": bool(res.get("ok", false)), "code": String(res.get("code", "")), "text": String(res.get("text", res.get("code", "")))}

## True when SIM has a handler for a v5 order (sim.<system>.cmd_<kind>).
func live_command(kind: String) -> bool:
	var s = _sim()
	for sys_name in ["people", "social", "ranks", "education", "housing", "discipline", "unrest"]:
		var o = s.get(sys_name)
		if o != null and o is Object and (o as Object).has_method("cmd_" + kind):
			return true
	return false
