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
## Answer: command answer_request {id, answer "allow" | "refuse"} (sim/relations.gd).

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
	return KIND.get(String(q.get("kind", "")), OTHER)

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

func _answer(ans: String, q: Dictionary = request) -> void:
	if q.is_empty():
		return
	last_result = hud.v5.command("answer_request", {"id": int(q["id"]), "answer": ans})
	hud.toast(String(last_result.get("text", "")), "info" if bool(last_result.get("ok", false)) else "warn", String(_spec(q)[1]), "request")
	hud.v5.request_override = []
	later.erase(int(q["id"]))
	_sig = ""
	update()
