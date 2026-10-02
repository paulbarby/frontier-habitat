extends PanelContainer
## Parties now (V5_DESIGN section 16): a card in the Events tab of the panel manager (it places it; the card
## has no placement code). One block for each party that gathers or runs (SIM sim.party.parties()): why, where,
## the phase and the time left, the guests and the honoured people, the score (fun, attendance, drama) and the
## last bits of drama. Show: the camera goes to the party. Follow a guest: over the shoulder of a guest.
## The messages (start, drama, end) go to the News tab by ui/hud/watchers.gd.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")

var hud
var count := 0             # parties shown (the Events tab counts them)
var rows_now: Array = []   # tests
var _list: VBoxContainer
var _poll := 1.0
var _sig := ""

func _ready() -> void:
	name = "Parties"
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	_list = Kit.vbox(8)
	add_child(_list)

func _process(delta: float) -> void:
	if hud == null or hud.main == null or hud.main.sim == null:
		return
	_poll += delta
	if _poll >= 1.0:
		_poll = 0.0
		update()

func update() -> void:
	var s = hud.main.sim
	var pt = s.get("party")
	var rows: Array = pt.parties() if pt != null and (pt as Object).has_method("parties") else []
	rows_now = rows
	count = rows.size()
	visible = count > 0
	var sig := ""
	for r in rows:
		sig += "%d:%s:%d:%d:%d|" % [int(r["id"]), String(r["phase"]), (r["guests"] as Array).size(), (r["drama"] as Array).size(), int(float(r["score"].get("fun", 0.0)))]
	if sig != _sig:
		_sig = sig
		Kit.clear(_list)
		for r in rows:
			_list.add_child(_block(r))
	for b in _list.get_children():
		var tl: Label = b.find_child("Time", true, false)
		if tl != null:
			tl.text = _time_text(b.get_meta("party"))

## "Birthday party", "Promotion party" ... from the reason's event kind (SIM's reason text is the offer's question).
const KIND_NAME := {"birthday": "Birthday party", "promotion": "Promotion party", "goal": "Goal party", "medal": "Medal party", "structure": "Opening party",
	"wedding": "Wedding party", "adoption": "Adoption party", "record": "Record party"}
static func title_of(reason: Dictionary) -> String:
	return String(KIND_NAME.get(String(reason.get("kind", "")), "Party"))

func _time_text(r: Dictionary) -> String:
	var s = hud.main.sim
	var hz: float = float(s.bal["tick_hz"])
	var tick: int = int(s.state["tick"])
	if String(r["phase"]) == "gathering":
		return "Gathering: the party starts in %s." % Kit.clock(maxf(0.0, float(int(r["start"]) - tick) / hz))
	return "On: %s left." % Kit.clock(maxf(0.0, float(int(r["end"]) - tick) / hz))

func _block(r: Dictionary) -> Control:
	var v: VBoxContainer = Kit.vbox(3)
	v.name = "Party_%d" % int(r["id"])
	v.set_meta("party", r)
	var h: HBoxContainer = Kit.hbox(6)
	v.add_child(h)
	h.add_child(Kit.icon("music", 16, Color("F472B6")))
	var hd: Label = Kit.head(title_of(r["reason"]), Color("F472B6"), 11)
	hd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(hd)
	var bname: String = String(hud.main.sim.state["buildings"].get(int(r["building"]), {}).get("name", "the venue"))
	v.add_child(Kit.wrap("At %s. %d guests%s." % [bname, (r["guests"] as Array).size(), (", for " + ", ".join((r["honoured"] as Array).map(func(x): return hud.v5.agent_name(int(x)).get_slice(" ", 0)))) if not (r["honoured"] as Array).is_empty() else ""], 12, P.TEXT))
	var tl: Label = Kit.label(_time_text(r), "SmallLabel", 12, P.AMBER)
	tl.name = "Time"
	v.add_child(tl)
	var sc: Dictionary = r["score"]
	v.add_child(Kit.label("Fun %d  ·  Attendance %d  ·  Drama %d" % [int(sc.get("fun", 0)), int(sc.get("attendance", 0)), int(sc.get("drama", 0))], "SmallLabel", 12, P.TEXT_2))
	var dr: Array = r["drama"]
	for i in range(maxi(0, dr.size() - 2), dr.size()):
		var d: Dictionary = dr[i]
		var l: Label = Kit.wrap(("DRAMA: " if bool(d.get("big", false)) else "") + String(d.get("text", "")), 12, P.RED if bool(d.get("big", false)) else P.TEXT_2)
		v.add_child(l)
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	v.add_child(row)
	row.add_child(Kit.button("Show", func(): _show(r), "Show\nThe camera goes to the party.", "GhostButton", "target", 13))
	var gb: Button = Kit.button("Follow a guest", func(): _follow(r), "Follow a guest\nOver the shoulder of a guest. Click a speech bubble to switch to another.", "GhostButton", "follow", 13)
	gb.disabled = (r["guests"] as Array).is_empty()
	row.add_child(gb)
	return v

func _show(r: Dictionary) -> void:
	var b: Dictionary = hud.main.sim.state["buildings"].get(int(r["building"]), {})
	if not b.is_empty():
		hud.main.select("building", int(r["building"]))
	var p = r.get("pos", null)
	if typeof(p) == TYPE_VECTOR2:
		hud.main.focus_on(p)

func _follow(r: Dictionary) -> void:
	for g in r["guests"]:
		if hud.main.follow_person(int(g)):
			return
