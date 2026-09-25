extends "res://ui/screens/screen.gd"
## Immigrant shuttle (docs/V3_1_DESIGN.md §6.5). arg = the arrival id (none: the first shuttle
## that can still be answered).
## One check box per settler on board (role and what the role does): the player picks who may
## stay. Checks what the colony can hold with the picked number: free beds, oxygen made
## against oxygen breathed, days of food. A countdown: time to arrival, or, in orbit, time
## before the shuttle gives up and leaves (SIM t_s).
## Confirm sends traffic_answer {id, grant: true, accept_idx: [indexes into offer.roles]}.

var ship_id := -1
var _roles: Array = []
var _boxes: Array = []      # CheckBox per settler, in offer.roles order
var _count: Label
var _checks: VBoxContainer
var _when: Label
var _ok: Button

func _init() -> void:
	icon = "people"
	title = "Settlers"
	compact = true
	compact_size = Vector2(640, 0)
	pauses = true

func _ready() -> void:
	ship_id = int(arg) if arg != null else -1
	if ship_id < 0:
		for r in hud.data.traffic_ships() + hud.data.traffic_forecast():
			if String(r.get("kind", "")) == "shuttle" and ["forecast", "orbit"].has(String(r.get("phase", ""))):
				ship_id = int(r["id"])
				break
	super._ready()

func build() -> void:
	var d = hud.data
	var r: Dictionary = d.traffic_row(ship_id)
	if r.is_empty() or String(r.get("kind", "")) != "shuttle":
		content.add_child(Kit.wrap("No immigrant shuttle is coming now.", 15, P.TEXT_2))
		return
	_roles = r.get("offer", {}).get("roles", [])
	set_subtitle("%s  ·  %s" % [String(r.get("name", "")), String(r.get("text", ""))])
	_when = Kit.num("", 16, P.CYAN, true)
	content.add_child(_when)
	var c: VBoxContainer = card("On board: choose who may stay", "people", P.CYAN)
	content.add_child(card_panel(c))
	# Who is ticked at the start: the earlier choice, else as many as there are free beds.
	var picked := {}
	if r.has("accept_idx"):
		for i in r["accept_idx"]:
			picked[int(i)] = true
	else:
		var beds: int = d.free_beds()
		var n: int = _roles.size() if beds < 0 else mini(_roles.size(), beds)
		var acc: int = int(r.get("accept", -1))
		if acc >= 0:
			n = mini(n, acc)
		for i in n:
			picked[i] = true
	var s = hud.main.sim
	for i in _roles.size():
		var role: String = String(_roles[i])
		var row: HBoxContainer = Kit.hbox(8)
		var cb := CheckBox.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = picked.has(i)
		cb.toggled.connect(func(_on): _update_checks())
		row.add_child(cb)
		row.add_child(Kit.icon(Icons.role(role), 18, P.ROLE.get(role, P.CYAN)))
		var nm: Label = Kit.label("Settler %d: %s" % [i + 1, String(s.bal["role_names"].get(role, role)).to_lower()], "", 14, P.TEXT)
		nm.custom_minimum_size.x = 210
		row.add_child(nm)
		row.add_child(Kit.label(_role_hint(role), "SmallLabel", 12, P.TEXT_2))
		c.add_child(row)
		_boxes.append(cb)
	var sel: HBoxContainer = Kit.hbox(8)
	c.add_child(sel)
	sel.add_child(Kit.button("All", func(): _pick_first(_roles.size()), "Tick every settler.", "GhostButton"))
	sel.add_child(Kit.button("None", func(): _pick_first(0), "Untick every settler.", "GhostButton"))
	sel.add_child(Kit.button("As many as free beds", func(): _pick_first(d.free_beds() if d.free_beds() >= 0 else _roles.size()), "Tick the first settlers, one for each free bed.", "GhostButton"))
	sel.add_child(Kit.spacer())
	_count = Kit.num("", 14, P.TEXT, true)
	sel.add_child(_count)
	_checks = Kit.vbox(4)
	content.add_child(_checks)
	content.add_child(Kit.label("The others fly on with the shuttle.", "SmallLabel", 12, P.TEXT_3))
	var btns: HBoxContainer = Kit.hbox(8, BoxContainer.ALIGNMENT_END)
	content.add_child(btns)
	btns.add_child(Kit.button("Deny the shuttle", func():
		hud.main.submit("traffic_answer", {"id": ship_id, "grant": false})
		host.close(self), "Deny\nThe shuttle does not land. Nobody stays.", "DangerButton", "close", 14))
	_ok = Kit.button("Confirm", func(): _confirm(), "Confirm\nThe shuttle lands; the ticked settlers stay.", "PrimaryButton", "check", 14)
	btns.add_child(_ok)
	_update_checks()
	refresh()

func _pick_first(n: int) -> void:
	for i in _boxes.size():
		(_boxes[i] as CheckBox).set_pressed_no_signal(i < n)
	_update_checks()

func picked() -> Array:
	var out: Array = []
	for i in _boxes.size():
		if (_boxes[i] as CheckBox).button_pressed:
			out.append(i)
	return out

func _confirm() -> void:
	var idx: Array = picked()
	hud.main.submit("traffic_answer", {"id": ship_id, "grant": true, "accept_idx": idx})
	hud.toast("The shuttle may land. %s may stay." % Kit.plural(idx.size(), "settler"), "info", "people")
	host.close(self)

func _role_hint(role: String) -> String:
	match role:
		"technician": return "builds, repairs, runs factories"
		"grower": return "farms crops"
		"operator": return "runs machines, cooks, mines"
		"medic": return "treats the sick"
		"scientist": return "makes research points"
	return ""

## Countdown and whether the choice is still open (a landed shuttle has decided).
func refresh() -> void:
	if _when == null:
		return
	var r: Dictionary = hud.data.traffic_row(ship_id)
	var ph: String = String(r.get("phase", "gone"))
	match ph:
		"forecast":
			_when.text = "Arrives in %s" % Kit.clock(float(r.get("eta_s", 0.0)))
		"orbit":
			_when.text = "In orbit: it leaves in %s unless it can land" % Kit.clock(float(r.get("t_s", 0.0)))
		_:
			_when.text = "The shuttle has %s: the choice is closed." % ("landed" if ph == "landed" else "gone")
	_when.add_theme_color_override("font_color", P.AMBER if ph == "orbit" else (P.CYAN if ph == "forecast" else P.TEXT_3))
	if _ok != null:
		_ok.disabled = not ["forecast", "orbit"].has(ph)

## What the colony can hold with the picked settlers (words and numbers, amber when short).
func _update_checks() -> void:
	var d = hud.data
	var n: int = picked().size()
	_count.text = "%d of %d picked" % [n, _roles.size()]
	Kit.clear(_checks)
	var k: Dictionary = hud.kpi if not hud.kpi.is_empty() else d.kpis()
	var pop: int = int(k["pop"]["value"])
	var beds: int = d.free_beds()
	if beds >= 0:
		_line(n <= beds, "Free beds: %d. Needed: %d." % [beds, n] + ("" if n <= beds else " %s without a bed." % Kit.plural(n - beds, "settler")))
	var o2: Dictionary = k["o2"]
	if float(o2["use"]) > 0.0 and pop > 0:
		var use_after: float = float(o2["use"]) * float(pop + n) / float(pop)
		var ratio: float = float(o2["make"]) / use_after
		_line(ratio >= 1.0, "Oxygen: made %s per day, breathed %s with them (%s)." % [Kit.fmt(float(o2["make"])), Kit.fmt(use_after), Kit.pct(minf(ratio, 9.99))])
	var food: Dictionary = k["food"]
	var days: float = float(food["value"]) / maxf(1.0, float(pop + n))
	_line(days >= 1.0, "Food: %s of dishes for %s." % [Kit.days(days), Kit.plural(pop + n, "colonist")])

func _line(ok: bool, text: String) -> void:
	var h: HBoxContainer = Kit.hbox(6)
	h.add_child(Kit.icon("sev_ok" if ok else "sev_warning", 15, P.GREEN if ok else P.AMBER))
	h.add_child(Kit.wrap(text, 13, P.TEXT if ok else P.AMBER, 520.0))
	_checks.add_child(h)
