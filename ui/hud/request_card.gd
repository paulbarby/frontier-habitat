extends PanelContainer
## Requests (V5_DESIGN §4.2, §10; docs/UI_PANELS.md): the questions people ask the player (SIM
## sim.relations.requests()), one row each, oldest first, in the Requests tab of the panel manager (it
## places this card; Paul, 2026-10-01: "the alerts ... need to be able to be minimised"). Each row: the
## kind and the person, SIM's text, the two answers with their effects, what happens when nobody answers
## and the deadline, File and Show. A row can be minimised (one line) or put off (Later: off the urgent
## line until a new request comes). Kinds:
##   leave_with_ship  a colonist in love with a visitor wants to leave on the ship. Let them go (confirm
##                    first: they leave for good) or Refuse (they stay; unhappy for 3 days).
##   shared_home      partners want a home together and there is no free unit. Try again (after you
##                    build a home) or Keep apart (both unhappy for 3 days).
##   party_offer      a celebration is a reason for a party (V5 section 16): pick the place and the hours, Throw
##                    the party (drinks and snacks from the stock) or Skip it.
##   hr_complaint     a person complained at the HR office (section 17): one button for each option SIM gives,
##                    each with its effect under it (mediate, move home, change job, leisure day, leave it to HR,
##                    dismiss).
##   hr_transfer      a very unhappy person asks to go off world: Approve (confirm first) or Refuse.
## Answer: command answer_request {id, answer "allow" | "refuse"} (sim/relations.gd); the three newer kinds
## carry `options` [{id, text, effect}] and the answer is the option id (party: also place, hours).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const PM = preload("res://ui/hud/panel_manager.gd")

## kind -> [head, icon, colour, allow button, allow effect, confirm the allow, refuse button, refuse effect,
##          what happens when nobody answers]
const KIND := {
	"leave_with_ship": ["LEAVE WITH A SHIP", "heart", Color("F472B6"), "Let them go", "They leave the colony on the ship. You lose a colonist and their skills.", true,
		"Refuse", "They stay. Satisfaction (freedom) and attitude fall for 3 days.", "They stay; the visitor leaves alone."],
	"shared_home": ["A HOME FOR TWO", "home", Color("4FC3F7"), "Try again", "They move in together when a unit for two is free. Build a residence tube or an apartment block first.", false,
		"Keep apart", "They stay in their homes. Satisfaction (housing) and attitude fall for 3 days.", "They stay in their own homes and keep asking."],
}
## Kinds that carry options: head, icon, colour, what happens when nobody answers.
const OPT_KIND := {
	"party_offer": ["A REASON TO PARTY", "music", Color("F472B6"), "A small gathering of friends happens by itself, with no drinks."],
	"hr_complaint": ["HR COMPLAINT", "colonists", Color("FFB547"), "After 3 days the complaint is dismissed."],
	"hr_transfer": ["TRANSFER REQUEST", "ship", Color("4FC3F7"), "After 2 days the request lapses. The person is a little more unhappy."],
}
## Options that cannot be undone: asked first.
const CONFIRM_OPTIONS := ["approve"]

const OTHER := ["A REQUEST", "people", Color("4FC3F7"), "Allow", "The simulation does what they ask.", true, "Refuse", "They do not get what they asked for.", "Nothing changes."]

var hud
var request: Dictionary = {}     # the oldest open request (tests)
var last_result: Dictionary = {}  # tests
var later := {}                  # request id -> true: off the urgent line (the player chose Later)
var _list: VBoxContainer
var _allow: Button               # the oldest row's buttons (tests)
var _refuse: Button
var _poll := 1.0
var _sig := ""
var _min := {}                   # request id -> minimised

func _ready() -> void:
	name = "Requests"
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	_list = Kit.vbox(10)
	add_child(_list)

func _process(delta: float) -> void:
	if hud == null or hud.v5 == null:
		return
	_poll += delta
	if _poll >= 1.0:
		_poll = 0.0
		update()

func _spec(q: Dictionary = request) -> Array:
	var k: String = String(q.get("kind", ""))
	if OPT_KIND.has(k):
		var o: Array = OPT_KIND[k]
		return [o[0], o[1], o[2], "", "", false, "", "", o[3]]
	return KIND.get(k, OTHER)

## The requests now (rebuilt when the set changes; the deadlines update every second).
func update() -> void:
	var reqs: Array = hud.v5.requests()
	visible = not reqs.is_empty()
	request = reqs[0] if not reqs.is_empty() else {}
	var sig := ""
	for q in reqs:
		sig += "%d:%s:%d:%s|" % [int(q.get("id", -1)), String(q.get("kind", "")), int(q.get("agent", -1)), _min.has(int(q.get("id", -1)))]
	if sig != _sig:
		_sig = sig
		Kit.clear(_list)
		_allow = null
		_refuse = null
		for q in reqs:
			_list.add_child(_row(q))
	for r in _list.get_children():
		var dl: Label = r.find_child("Deadline", true, false)
		if dl != null:
			dl.text = _deadline(r.get_meta("req"))

func _row(q: Dictionary) -> Control:
	var spec: Array = _spec(q)
	var rid: int = int(q.get("id", -1))
	var v: VBoxContainer = Kit.vbox(4)
	v.set_meta("req", q)
	v.name = "Request_%d" % rid
	var h: HBoxContainer = Kit.hbox(6)
	v.add_child(h)
	h.add_child(Kit.icon(String(spec[1]), 16, spec[2]))
	var hd: Label = Kit.head("%s  ·  %s" % [spec[0], hud.v5.agent_name(int(q.get("agent", -1))).to_upper()], spec[2], 11)
	hd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(hd)
	var mn: bool = _min.has(rid)
	h.add_child(PM._ib("chevron_down" if mn else "chevron_up", func():
		if _min.has(rid):
			_min.erase(rid)
		else:
			_min[rid] = true
		_sig = ""
		update(), "Minimise\nOnly this line shows. The request stays open.", "GhostButton", 12, 22))
	h.add_child(PM._ib("clock", func():
		later[rid] = true
		hud.toast("Later: the request waits in the Requests tab.", "info", "heart", "request"), "Later\nOff the urgent line. It stays here until you answer.", "GhostButton", 12, 22))
	if mn:
		return v
	v.add_child(Kit.wrap(String(q.get("text", "")), 13, P.TEXT))
	if OPT_KIND.has(String(q.get("kind", ""))):
		_option_controls(v, q)
		var dl2: Label = Kit.wrap(_deadline(q), 12, P.AMBER)
		dl2.name = "Deadline"
		v.add_child(dl2)
		return v
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	v.add_child(row)
	var ab: Button = Kit.button(String(spec[3]), func(): _ask_allow(q), "%s\n%s%s" % [spec[3], spec[4], "\nYou confirm first." if bool(spec[5]) else ""], "DangerButton" if bool(spec[5]) else "", "sev_ok", 13)
	var rb: Button = Kit.button(String(spec[6]), func(): _answer("refuse", q), "%s\n%s" % [spec[6], spec[7]], "PrimaryButton", "close", 13)
	row.add_child(ab)
	row.add_child(rb)
	row.add_child(Kit.button("File", func(): hud.open_person(int(q.get("agent", -1)), "file"), "Personnel file\nMood, skills and relationships of this person.", "GhostButton", "colonists", 13))
	row.add_child(Kit.button("Show", func(): _show(q), "Show\nThe camera goes to this person.", "GhostButton", "target", 13))
	if _allow == null:
		_allow = ab
		_refuse = rb
	var eff: Label = Kit.wrap("%s: %s\n%s: %s" % [spec[3], spec[4], spec[6], spec[7]], 12, P.TEXT_2)
	eff.name = "Effect"
	v.add_child(eff)
	var dl: Label = Kit.wrap(_deadline(q), 12, P.AMBER)
	dl.name = "Deadline"
	v.add_child(dl)
	return v

## "If you do not answer: … Deadline: …" (leave_with_ship: when the ship leaves).
func _deadline(q: Dictionary) -> String:
	var spec: Array = _spec(q)
	if OPT_KIND.has(String(q.get("kind", ""))):
		return "If you do not answer: %s  Deadline: %s." % [spec[8], _expiry_text(q)]
	var when := "none"
	if String(q.get("kind", "")) == "leave_with_ship":
		when = "when the ship leaves"
		var sid: int = int(q.get("ship", -1))
		var tr: Dictionary = hud.data.traffic_row(sid) if sid >= 0 and hud.data.has_method("traffic_row") else {}
		if not tr.is_empty() and String(tr.get("phase", "")) == "landed":
			when = "the ship leaves in %s" % Kit.clock(float(tr.get("t_s", 0.0)))
		elif sid < 0 or tr.is_empty():
			when = "the ship has gone"
	return "If you do not answer: %s  Deadline: %s." % [spec[8], when]

## The deadline of an option request: its `expires` tick as time left ("none" when -1).
func _expiry_text(q: Dictionary) -> String:
	var ex: int = int(q.get("expires", -1))
	if ex < 0:
		return "none"
	var s = hud.main.sim
	var left: float = float(ex - int(s.state["tick"])) / float(s.bal["tick_hz"])
	if left <= 0.0:
		return "now"
	var day: float = float(s.bal.get("day_length", 600.0))
	return Kit.clock(left) if left < day else "%.1f days" % (left / day)

## The buttons of a request with options (party offer, complaint, transfer): one for each option, the effect of
## each under them, File and Show. A party offer first asks where and for how long.
var _party_pick := {}   # request id -> {"place": OptionButton, "hours": OptionButton} (tests)
func _option_controls(v: VBoxContainer, q: Dictionary) -> void:
	var kind: String = String(q.get("kind", ""))
	var rid: int = int(q.get("id", -1))
	var opts: Array = q.get("options", [])
	if kind == "party_offer":
		var choices: Array = q.get("place_choices", [])
		var pr: HBoxContainer = Kit.hbox(6)
		v.add_child(pr)
		var place := OptionButton.new()
		place.name = "Place"
		place.focus_mode = Control.FOCUS_NONE
		place.add_theme_font_size_override("font_size", 12)
		place.tooltip_text = "Where\nThe party gathers here. A venue needs power and air."
		for c in choices:
			place.add_item("%s  ·  about %d units of drinks or snacks" % [String(c["name"]), int(c["cost"])])
			place.set_item_metadata(place.item_count - 1, int(c["building"]))
		if choices.is_empty():
			place.add_item("No venue with power and air")
			place.disabled = true
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(place)
		var hours := OptionButton.new()
		hours.name = "Hours"
		hours.focus_mode = Control.FOCUS_NONE
		hours.add_theme_font_size_override("font_size", 12)
		hours.tooltip_text = "How long\nOne party hour is 60 seconds. A longer party costs the same and runs longer."
		for hh in [1, 2, 3]:
			hours.add_item("%d hour%s" % [hh, "" if hh == 1 else "s"])
			hours.set_item_metadata(hours.item_count - 1, hh)
		hours.select(1)
		pr.add_child(hours)
		_party_pick[rid] = {"place": place, "hours": hours}
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	v.add_child(row)
	for o in opts:
		var oid: String = String(o["id"])
		var primary: bool = (oid == "refuse") if kind == "hr_transfer" else (oid in ["throw", "mediate", "move_home"])
		var confirm: bool = oid in CONFIRM_OPTIONS
		var b: Button = Kit.button(String(o["text"]), func(): _ask_option(q, oid), "%s\n%s%s" % [o["text"], o.get("effect", ""), "\nYou confirm first." if confirm else ""],
			"DangerButton" if confirm else ("PrimaryButton" if primary else ""), "sev_ok" if oid in ["throw", "approve"] else "check", 13)
		b.name = "Opt_" + oid
		if oid == "throw" and (q.get("place_choices", []) as Array).is_empty():
			b.disabled = true
		row.add_child(b)
	row.add_child(Kit.button("File", func(): hud.open_person(int(q.get("agent", -1)), "file"), "Personnel file\nMood, skills and relationships of this person.", "GhostButton", "colonists", 13))
	row.add_child(Kit.button("Show", func(): _show(q), "Show\nThe camera goes to this person.", "GhostButton", "target", 13))
	var lines: Array = []
	for o in opts:
		lines.append("%s: %s" % [o["text"], o.get("effect", "")])
	var eff: Label = Kit.wrap("\n".join(lines), 12, P.TEXT_2)
	eff.name = "Effect"
	v.add_child(eff)

## An option: at once, or after a confirm when it cannot be undone (a person leaves for good).
func _ask_option(q: Dictionary, oid: String) -> void:
	if oid in CONFIRM_OPTIONS:
		var nm: String = hud.v5.agent_name(int(q.get("agent", -1)))
		var txt: String = oid
		for o in q.get("options", []):
			if String(o["id"]) == oid:
				txt = String(o["text"])
		hud.confirm("%s: %s?" % [txt, nm], [_effect_of(q, oid), "This cannot be undone."], func(): _answer_option(q, oid), txt, true)
		return
	_answer_option(q, oid)

func _effect_of(q: Dictionary, oid: String) -> String:
	for o in q.get("options", []):
		if String(o["id"]) == oid:
			return String(o.get("effect", ""))
	return ""

func _answer_option(q: Dictionary, oid: String) -> void:
	var extra := {}
	if String(q.get("kind", "")) == "party_offer" and oid == "throw":
		var pk: Dictionary = _party_pick.get(int(q["id"]), {})
		if not pk.is_empty():
			var pl: OptionButton = pk["place"]
			var hr: OptionButton = pk["hours"]
			if pl.selected >= 0 and pl.item_count > 0 and pl.get_item_metadata(pl.selected) != null:
				extra["place"] = int(pl.get_item_metadata(pl.selected))
			extra["hours"] = int(hr.get_item_metadata(hr.selected))
	_answer(oid, q, extra)

func _show(q: Dictionary) -> void:
	var id: int = int(q.get("agent", -1))
	var a: Dictionary = hud.v5.agent(id)
	if not a.is_empty():
		hud.main.select("agent", id)
		hud.main.focus_on(a["pos"])

## Allow: at once, or after a confirm when it cannot be undone (a colonist leaving).
func _ask_allow(q: Dictionary = request) -> void:
	var spec: Array = _spec(q)
	if not bool(spec[5]):
		_answer("allow", q)
		return
	var nm: String = hud.v5.agent_name(int(q.get("agent", -1)))
	hud.confirm("%s: %s?" % [spec[3], nm], [spec[4], "This cannot be undone."], func(): _answer("allow", q), String(spec[3]), true)

func _answer(ans: String, q: Dictionary = request, extra: Dictionary = {}) -> void:
	if q.is_empty():
		return
	var payload := {"id": int(q["id"]), "answer": ans}
	payload.merge(extra)
	last_result = hud.v5.command("answer_request", payload)
	hud.toast(String(last_result.get("text", "")), "info" if bool(last_result.get("ok", false)) else "warn", String(_spec(q)[1]), _type_of(q))
	hud.v5.request_override = []
	later.erase(int(q["id"]))
	_sig = ""
	update()

## The panel manager type of a request's answer message.
func _type_of(q: Dictionary) -> String:
	match String(q.get("kind", "")):
		"party_offer":
			return "party"
		"hr_complaint", "hr_transfer":
			return "hr"
	return "request"
