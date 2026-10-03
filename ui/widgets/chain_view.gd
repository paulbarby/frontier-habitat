extends RefCounted
## One production chain as a small diagram (V5_DESIGN §18.4): raw resource -> structure -> item -> structure -> item. A step is a
## card with an icon, the name, a state tag (DONE, MISSING, NO POWER, NEEDS RESEARCH, NO WORKER) and one line in STE; an arrow
## joins the steps. A missing structure that is unlocked has a Place button; one that needs research has a Research button.
## An input branch of a recipe is indented. Used by the chain window (alert: Show chain) and the codex page Production chains.
## Data: ui/v18_data.gd chain_of() (SIM's sim.chains when it is there).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Icons = preload("res://ui/theme/icons.gd")

const STATE_COL := {"done": Color("6EE7A8"), "missing": Color("FF5A5F"), "building": Color("3EE0FF"), "broken": Color("FF5A5F"), "unpowered": Color("FFB547"), "no_worker": Color("FFB547"), "needs_research": Color("A78BFA")}
const STATE_WORD := {"done": "DONE", "missing": "MISSING", "building": "BEING BUILT", "broken": "BROKEN", "unpowered": "NO POWER", "no_worker": "NO WORKER", "needs_research": "NEEDS RESEARCH"}

## The chain's summary line: what the colony can do now, and what is missing first.
static func summary(chain: Dictionary) -> String:
	if String(chain.get("text", "")) != "":
		return String(chain["text"])
	if bool(chain.get("ok", false)):
		return "%s: every step is done. The colony makes it now." % String(chain.get("name", ""))
	for st in chain.get("steps", []):
		if String(st["state"]) != "done":
			return "%s: the first step that is not done is %s." % [String(chain.get("name", "")), String(st["name"])]
	return String(chain.get("name", ""))

## Builds the diagram into a VBox. `on_place(def_id)` and `on_research(tech_id)` are called by the buttons.
static func build(hud, chain: Dictionary, on_place: Callable, on_research: Callable) -> VBoxContainer:
	var box: VBoxContainer = Kit.vbox(0)
	box.name = "ChainSteps"
	var steps: Array = chain.get("steps", [])
	for i in steps.size():
		var st: Dictionary = steps[i]
		box.add_child(_step(hud, st, on_place, on_research))
		if i < steps.size() - 1:
			var ar: HBoxContainer = Kit.hbox(0)
			ar.alignment = BoxContainer.ALIGNMENT_BEGIN
			ar.add_child(Kit.gap(float(int(st.get("depth", 0)) * 14 + 26), 0.0))
			ar.add_child(Kit.icon("arrow_down", 14, P.TEXT_3))
			box.add_child(ar)
	return box

static func _step(hud, st: Dictionary, on_place: Callable, on_research: Callable) -> Control:
	var col: Color = STATE_COL.get(String(st["state"]), P.TEXT_2)
	var row: HBoxContainer = Kit.hbox(0)
	row.set_meta("step", String(st.get("id", "")))
	row.set_meta("state", String(st["state"]))
	row.add_child(Kit.gap(float(int(st.get("depth", 0)) * 14), 0.0))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", load("res://ui/theme/list_row.gd").make(col))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(card)
	var v: VBoxContainer = Kit.vbox(2)
	card.add_child(v)
	var h: HBoxContainer = Kit.hbox(8)
	v.add_child(h)
	var icon: String = _icon(hud, st)
	h.add_child(Kit.icon(icon, 20, col if String(st["kind"]) == "building" else P.TEXT))
	var nm: Label = Kit.label(String(st["name"]), "BodyStrong", 14, P.TEXT)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size.x = 60
	nm.tooltip_text = String(st["name"])
	nm.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(nm)
	h.add_child(Kit.label({"resource": "RESOURCE", "building": "STRUCTURE", "item": "ITEM"}.get(String(st["kind"]), ""), "SmallLabel", 10, P.TEXT_3))
	var tag: Control = Kit.badge(String(STATE_WORD.get(String(st["state"]), String(st["state"]).to_upper())), col)
	h.add_child(tag)
	var tx: Label = Kit.wrap(String(st.get("text", "")), 12, P.TEXT_2)
	v.add_child(tx)
	if bool(st.get("can_place", false)) and String(st.get("def", "")) != "":
		var d: String = String(st["def"])
		var pb: Button = Kit.button("Place %s" % String(st["name"]), func(): on_place.call(d), "Place\nChoose where to build it. The structure is unlocked.", "PrimaryButton", "build", 14)
		pb.set_meta("place", d)
		pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pb.clip_text = true
		v.add_child(pb)
	elif String(st["state"]) == "needs_research" and String(st.get("tech", "")) != "":
		var t: String = String(st["tech"])
		var rb: Button = Kit.button("Open Research", func(): on_research.call(t), "Research\nOpens the tech tree.", "GhostButton", "research", 14)
		rb.set_meta("tech", t)
		rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(rb)
	return row

static func _icon(hud, st: Dictionary) -> String:
	match String(st["kind"]):
		"building":
			var def: String = String(st.get("def", st.get("id", "")))
			if Icons.has(def):
				return def
			var cat: String = String(hud.main.sim.content["buildings"].get(def, {}).get("category", "industry"))
			return Icons.category(cat) if Icons.has(Icons.category(cat)) else "build"
		"item":
			return Icons.item(String(st["id"]))
		_:
			return "poi_deposit" if String(st.get("id", "")) == "deposit" else Icons.item(String(st.get("id", "")))
