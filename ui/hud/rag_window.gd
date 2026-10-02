extends PanelContainer
## "The Regolith Rag" (V5_DESIGN §4.3, §10): the colony's tabloid, a real newspaper page held in the
## glass-and-metal window frame. Newsprint paper, a red masthead, bold condensed headlines, the lead
## story with a photo and a caption, three columns of stories, the gossip column, Couple Watch,
## Feud Watch, the Commander approval poll, small ads, and a "Serious news" strip with the real
## problems (from the alerts, in plain STE). Back issues: the last 30, from the header.
## Every name in a story is a link: click it to select the person (and, from 5.0 follow view on,
## to follow them). The paper is written in tabloid voice (V5_DESIGN §0: the one exception to STE).
## Data: ui/v5_data.gd rag_issues() (SIM's issues, or the preview issues until SIM publishes them).
## A window of the window manager; it stays inside the view (the paper scrolls).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const RagPhoto = preload("res://ui/widgets/rag_photo.gd")

const INK := Color("16130F")
const INK_2 := Color("3B352C")
const RED := Color("C8102E")
const PAPER := Color("EFE8D6")
const PAPER_W := 980.0

var hud
var _head: HBoxContainer
var _issue_btn: OptionButton
var _scroll: ScrollContainer
var _paper: PanelContainer
var _body: VBoxContainer
var _issues: Array = []
var shown := -1            # index of the issue shown (0 = the newest; tests)
var links: Array = []      # [{id, name}] of every name link on the page (tests)
var layout := "standard"   # "standard", "special" (bad news: a special edition) or "quiet" (tests)
var force_layout := ""     # debug `raglayout` (screenshots of the other layouts)
var compact := false       # a short view (1280x720): smaller masthead and headline, the photo above the fold
const SPECIAL_KINDS := ["riot", "protest", "strike", "fight", "death", "arrest", "breach", "affair", "party_drama_big"]
## House ads (Rag voice) when SIM and the arrivals give fewer than four.
const HOUSE_ADS := [["RAG TIPS LINE", "Seen something juicy? Tell a Rag reporter at the lounge. We never name sources."],
	["ADVERTISE HERE", "Reach every colonist on the planet. All of them. Rates on request."],
	["CLASSIFIEDS", "Swaps, lost socks and lonely hearts: one line free for every crew member."],
	["NEXT ISSUE", "Dawn tomorrow. Same dirt, new day."]]
static var _news_tex: Texture2D

func _ready() -> void:
	var st = GlassFrame.new()
	st.kind = "window"
	st.header_h = 50.0
	st.content_margin_left = 16
	st.content_margin_right = 18
	st.content_margin_top = 12
	st.content_margin_bottom = 14
	st.accent = Color(RED.r, RED.g, RED.b, 0.9)
	add_theme_stylebox_override("panel", st)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	_head = Kit.hbox(10)
	_head.custom_minimum_size.y = 30
	v.add_child(_head)
	_head.add_child(Kit.icon("newspaper", 22, RED.lightened(0.25)))
	var t: Label = Kit.head("THE REGOLITH RAG", P.TEXT, 16, "head_wide")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(t)
	_head.add_child(Kit.label("Issue", "SmallLabel", 12, P.TEXT_2))
	_issue_btn = OptionButton.new()
	_issue_btn.tooltip_text = "Back issues\nThe Rag keeps the last 30 issues. Pick one to read it."
	_issue_btn.custom_minimum_size.x = 260
	_issue_btn.item_selected.connect(func(i: int): show_issue(i))
	_head.add_child(_issue_btn)
	_head.add_child(Kit.icon_button("close", func(): visible = false, "Close\nEsc.", "GhostButton", 16, 30))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_paper = PanelContainer.new()
	var ps := StyleBoxTexture.new()
	ps.texture = newsprint()
	ps.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	ps.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	ps.content_margin_left = 22
	ps.content_margin_right = 22
	ps.content_margin_top = 18
	ps.content_margin_bottom = 20
	_paper.add_theme_stylebox_override("panel", ps)
	_paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_paper)
	_body = Kit.vbox(10)
	_paper.add_child(_body)
	visibility_changed.connect(func():
		if visible:
			open_latest())

func register_window(wm) -> void:
	wm.register(self, "rag", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.position.x + (wa.size.x - sz.x) * 0.5, wa.position.y + 4.0))

func wm_close() -> void:
	visible = false

func toggle() -> void:
	visible = not visible

## Newsprint: warm grey-white paper with fine grain and fibres (made once).
static func newsprint() -> Texture2D:
	if _news_tex != null:
		return _news_tex
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.09
	n.seed = 77
	var m := FastNoiseLite.new()
	m.noise_type = FastNoiseLite.TYPE_VALUE
	m.frequency = 0.8
	m.seed = 78
	for y in 256:
		for x in 256:
			var c: float = n.get_noise_2d(x, y) * 0.03 + m.get_noise_2d(x, y) * 0.045
			var fib: float = -0.07 if posmod(x * 13 + y * 7, 173) == 0 or posmod(x * 5 + y * 31, 211) == 0 else 0.0
			img.set_pixel(x, y, Color(PAPER.r + c + fib, PAPER.g + c + fib, PAPER.b + c * 0.8 + fib))
	_news_tex = ImageTexture.create_from_image(img)
	return _news_tex

func open_latest() -> void:
	_issues = hud.v5.rag_issues()
	_issue_btn.clear()
	for i in _issues.size():
		var iss: Dictionary = _issues[i]
		_issue_btn.add_item("No. %d  ·  Day %d  ·  %s" % [int(iss["no"]), int(iss["day"]), String(iss["lead"]["headline"]).capitalize()], i)
	_fit_size()
	show_issue(0)

## As large as the view allows, up to the paper width (the window manager keeps it inside).
func _fit_size() -> void:
	var wa: Rect2 = hud.wm.work_area() if hud.wm != null else Rect2(Vector2.ZERO, get_viewport_rect().size)
	var w: float = minf(PAPER_W + 58.0, wa.size.x - 8.0)
	var h: float = wa.size.y - 8.0
	custom_minimum_size = Vector2(w, h)
	_scroll.custom_minimum_size = Vector2(w - 34.0, h - 80.0)
	size = custom_minimum_size

func show_issue(i: int) -> void:
	shown = i
	links = []
	Kit.clear(_body)
	if _issues.is_empty():
		_body.add_child(_text("No issue yet. The first Rag comes out at dawn.", "rag_body", 16, INK))
		return
	_issue_btn.select(i)
	_fit_size()
	var iss: Dictionary = _issues[i]
	var kind: String = String(iss["lead"].get("kind", ""))
	if kind == "" and iss.has("lead_kind"):
		kind = String(iss["lead_kind"])
	# Quiet: SIM says so, or the lead is cold (heat under 0.25) and there are 2 stories or fewer (critic round 30).
	var cold: bool = float(iss["lead"].get("heat", 1.0)) < 0.25 and (iss.get("stories", []) as Array).size() <= 2
	layout = "special" if kind in SPECIAL_KINDS or String(iss["lead"].get("kicker", "")) in ["UPROAR", "PUNCH-UP", "TRAGEDY", "NICKED", "SCANDAL"] else ("quiet" if kind == "quiet" or cold else "standard")
	if force_layout != "":
		layout = force_layout
	compact = get_viewport_rect().size.y < 800.0
	_masthead(iss)
	_lead(iss)
	_rule(3)
	_stories(iss)
	_rule(3)
	_columns(iss)
	_ads(iss)
	_serious(iss)
	_scroll.scroll_vertical = 0

# ---------------------------------------------------------------- page parts
func _masthead(iss: Dictionary) -> void:
	var band := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = RED
	bs.border_width_bottom = 4
	bs.border_color = RED.darkened(0.35)
	bs.content_margin_left = 16
	bs.content_margin_right = 16
	bs.content_margin_top = 4
	bs.content_margin_bottom = 2
	band.add_theme_stylebox_override("panel", bs)
	_body.add_child(band)
	var h: HBoxContainer = Kit.hbox(14)
	band.add_child(h)
	var ear := _text("COLONY\nEDITION", "rag_head", 14, Color.WHITE)
	ear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ear.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(ear)
	var mast := _text("THE REGOLITH RAG", "rag_mast", 46 if compact else 66, Color.WHITE)
	mast.add_theme_constant_override("outline_size", 6)
	mast.add_theme_color_override("font_outline_color", RED.darkened(0.45))
	mast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(mast)
	var box: VBoxContainer = Kit.vbox(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(box)
	for s in ["No. %d" % int(iss["no"]), "DAY %d" % int(iss["day"]), String(iss.get("price", "1 credit")).to_upper()]:
		var l := _text(s, "rag_head", 15, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(l)
	if layout == "special":
		bs.bg_color = INK
		bs.border_color = RED
		ear.text = "SPECIAL\nEDITION"
		ear.add_theme_color_override("font_color", Color("F5C542"))
	var strap := PanelContainer.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = RED if layout == "special" else INK
	ss.content_margin_left = 12
	ss.content_margin_right = 12
	ss.content_margin_top = 3
	ss.content_margin_bottom = 3
	strap.add_theme_stylebox_override("panel", ss)
	_body.add_child(strap)
	var sh: HBoxContainer = Kit.hbox(8)
	strap.add_child(sh)
	var sl := _text(String(iss.get("tagline", "")).to_upper() if String(iss.get("tagline", "")) != "" else "THE COLONY'S No.1 FOR GOSSIP, GRIT AND GROWING TOMATOES", "rag_head", 14, Color.WHITE)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sl)
	sh.add_child(_text("EST. DAY 1", "rag_head", 14, Color("F5C542")))
	# The double rule of a real front page under the masthead.
	_rule(3)
	var gap := Control.new()
	gap.custom_minimum_size.y = 1
	_body.add_child(gap)
	_rule(1)

func _lead(iss: Dictionary) -> void:
	var L: Dictionary = iss["lead"]
	var kh: HBoxContainer = Kit.hbox(10)
	_body.add_child(kh)
	kh.add_child(_chip("SLOW NEWS DAY" if layout == "quiet" else String(L.get("kicker", "EXCLUSIVE"))))
	var sub := _text(String(L.get("sub", "")).to_upper(), "rag_head", 22, RED)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kh.add_child(sub)
	# The lead headline fits two lines (also on a special edition, critic round 30): the size steps down
	# until it does. A quiet day has a smaller lead.
	var head_txt: String = String(L["headline"])
	var max_lines: int = 2
	var width: float = _scroll.custom_minimum_size.x - 60.0
	var px: int = (84 if layout == "special" else (46 if layout == "quiet" else 64)) if not compact else (56 if layout == "special" else (36 if layout == "quiet" else 44))
	while px > 28 and _lines_of(head_txt, px, width) > max_lines:
		px -= 4
	lead_lines = _lines_of(head_txt, px, width)
	var hl := _text(head_txt, "rag_head", px, RED if layout == "special" else INK)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.add_theme_constant_override("line_spacing", -int(P.fs(px) * 0.28))
	hl.name = "LeadHeadline"
	_body.add_child(hl)
	var row: HBoxContainer = Kit.hbox(18)
	_body.add_child(row)
	var pv: VBoxContainer = Kit.vbox(0)
	row.add_child(pv)
	var ph = RagPhoto.new()
	var pw: float = (width if layout == "special" else 540.0) if not compact else (width * 0.8 if layout == "special" else 420.0)
	if layout == "quiet":
		pw = 300.0 if not compact else 260.0
	ph.custom_minimum_size = Vector2(pw, pw * (0.45 if layout == "special" else 0.75))
	var pinfo: Dictionary = L.get("photo", {})
	ph.pose = String(pinfo.get("pose", "talk"))
	ph.place = String(pinfo.get("place", ""))
	ph.texture = hud.v5.photo(pinfo.get("agents", L.get("actors", [])), ph.place, ph.pose)
	ph.name = "LeadPhoto"
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = INK
	fs.set_border_width_all(0)
	fs.content_margin_left = 3
	fs.content_margin_right = 3
	fs.content_margin_top = 3
	fs.content_margin_bottom = 0
	frame.add_theme_stylebox_override("panel", fs)
	frame.add_child(ph)
	pv.add_child(frame)
	var cap := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = INK
	cs.content_margin_left = 10
	cs.content_margin_right = 10
	cs.content_margin_top = 5
	cs.content_margin_bottom = 6
	cap.add_theme_stylebox_override("panel", cs)
	var capl := _rich(String(L.get("caption", "")), L.get("actors", []), 13, Color.WHITE, "rag_head")
	cap.add_child(capl)
	pv.add_child(cap)
	var tv: VBoxContainer = Kit.vbox(8)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if layout == "special":
		# Special edition: the photo takes the page width; the text and the poll go under it.
		var under: HBoxContainer = Kit.hbox(18)
		_body.add_child(under)
		under.add_child(tv)
	else:
		row.add_child(tv)
	tv.add_child(_text("By RAG STAFF", "rag_head", 14, RED))
	var body := _rich(String(L["body"]), L.get("actors", []), 17, INK, "rag_body", true)
	tv.add_child(body)
	tv.add_child(_rule_ctl(1))
	_poll(tv, iss.get("poll", {}))
	# The rest of the column: the quote of the day and what is inside (critic round 25: no empty column).
	_quote(tv, L)
	_inside(tv, iss)
	tv.add_child(_text("\"THE RAG KNOWS.\"", "rag_head", 22, INK_2))
	if layout == "quiet":
		_puzzle()

## Three columns a row (a busy day has six stories: two rows with a rule between them).
func _stories(iss: Dictionary) -> void:
	var list: Array = iss.get("stories", [])
	var row: HBoxContainer = null
	for i in list.size():
		var s: Dictionary = list[i]
		if i % 3 == 0:
			if i > 0:
				_rule(1)
			row = Kit.hbox(0)
			_body.add_child(row)
		if i % 3 > 0:
			row.add_child(_vrule())
		var col: VBoxContainer = Kit.vbox(5)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.custom_minimum_size.x = 250
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 10 if i % 3 > 0 else 0)
		m.add_theme_constant_override("margin_right", 10)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.add_child(col)
		row.add_child(m)
		col.add_child(_text(String(s.get("tag", "NEWS")).to_upper(), "rag_head", 14, RED))
		var h := _text(String(s["headline"]), "rag_head", 30, INK)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_theme_constant_override("line_spacing", -6)
		col.add_child(h)
		col.add_child(_rich(String(s["body"]), s.get("actors", []), 14, INK, "rag_body"))

func _columns(iss: Dictionary) -> void:
	var row: HBoxContainer = Kit.hbox(14)
	_body.add_child(row)
	# The gossip column: a boxed column with a black heading. A quiet day (critic round 36): the
	# column takes the whole width, 8 items in two columns, a bigger type; the watches go under it.
	var g: VBoxContainer = _box(row, "THE DUST-UP", "by Rag Snoop" if layout != "quiet" else "by Rag Snoop  ·  a slow day, so we listened harder")
	if layout == "quiet":
		var gg: GridContainer = Kit.grid(2, 22, 8)
		gg.name = "GossipGrid"
		g.add_child(gg)
		for it in _padded(iss.get("gossip", []), "gossip", 8):
			var gr := _rich("• " + String(it["text"]), it.get("actors", []), 17, INK, "rag_body_i")
			gr.custom_minimum_size.x = 420
			gg.add_child(gr)
		row = Kit.hbox(14)
		_body.add_child(row)
	else:
		for it in _padded(iss.get("gossip", []), "gossip", 3):
			g.add_child(_rich("• " + String(it["text"]), it.get("actors", []), 15, INK, "rag_body_i"))
	# Couple Watch and Feud Watch.
	var cw: VBoxContainer = _box(row, "COUPLE WATCH", "who is with whom")
	for c in iss.get("couples", []):
		var sym: String = {"dating": "&", "partners": "&", "married": "&", "crush": "→", "affair": "&"}.get(String(c.get("status", "")), "&")
		var na: String = hud.v5.agent_name(int(c["a"])).get_slice(" ", 0)
		var nb: String = hud.v5.agent_name(int(c["b"])).get_slice(" ", 0)
		cw.add_child(_rich("[b]%s %s %s[/b] — %s. %s" % [na, sym, nb, String(c.get("status", "")), String(c.get("note", ""))], [int(c["a"]), int(c["b"])], 15, INK, "rag_body"))
	if (iss.get("couples", []) as Array).is_empty():
		cw.add_child(_text("Nobody is dating. Yet.", "rag_body_i", 15, INK_2))
	var fw: VBoxContainer = _box(row, "FEUD WATCH", "who is not speaking to whom")
	for f in iss.get("feuds", []):
		var fa: String = hud.v5.agent_name(int(f["a"])).get_slice(" ", 0)
		var fb: String = hud.v5.agent_name(int(f["b"])).get_slice(" ", 0)
		var note: String = String(f.get("note", ""))
		if note.to_lower().begins_with("enem"):
			note = "Sworn enemies."
		fw.add_child(_rich("[b]%s vs %s[/b] — %s" % [fa, fb, note], [int(f["a"]), int(f["b"])], 15, INK, "rag_body"))
	if (iss.get("feuds", []) as Array).is_empty():
		fw.add_child(_text("All quiet on the feud front.", "rag_body_i", 15, INK_2))
	if layout == "quiet":
		_photo_of_day(row, iss)

## Quiet day: PHOTO OF THE DAY, two colonists caught on camera (RENDER's photo when it exists).
func _photo_of_day(row: HBoxContainer, iss: Dictionary) -> void:
	var ids: Array = []
	for r in hud.v5.people():
		if String(r["kind"]) == "colonist":
			ids.append(int(r["id"]))
	if ids.size() < 2:
		return
	var n: int = int(iss.get("no", iss.get("number", 1)))
	var a: int = int(ids[n % ids.size()])
	var b: int = int(ids[(n * 7 + 3) % ids.size()])
	if a == b:
		b = int(ids[(n + 1) % ids.size()])
	var box: VBoxContainer = _box(row, "PHOTO OF THE DAY", "snapped by a reader")
	box.get_parent().name = "PhotoOfDay"
	var ph = RagPhoto.new()
	ph.custom_minimum_size = Vector2(300, 190)
	ph.pose = "talk"
	ph.texture = hud.v5.photo([a, b], "corridor", "talk")
	box.add_child(ph)
	var na: String = hud.v5.agent_name(a)
	var nb: String = hud.v5.agent_name(b)
	box.add_child(_rich("%s and %s in the corridor. Just talking? The Rag wonders." % [na, nb], [a, b], 15, INK, "rag_body_i"))

## The Commander approval poll (from satisfaction): a big number, the change, a bar.
## A column with fewer items than room: more from SIM's own column lines (content/tabloid.json
## columns), without repeats, so a quiet day still fills the page with the Rag's voice.
func _padded(list: Array, column: String, want: int) -> Array:
	var out: Array = list.duplicate()
	var seen := {}
	for x in out:
		seen[(String(x.get("title", "")) + " " + String(x.get("text", ""))).strip_edges() if typeof(x) == TYPE_DICTIONARY and column == "ads" else (String(x.get("text", "")) if typeof(x) == TYPE_DICTIONARY else String(x))] = true
	var more: Array = hud.main.sim.content.get("tabloid", {}).get("columns", {}).get(column, [])
	var start: int = int(_issues[shown]["no"]) if shown >= 0 and shown < _issues.size() else 0
	for k in more.size():
		if out.size() >= want:
			break
		var line: String = String(more[(start + k) % more.size()])
		if seen.has(line):
			continue
		seen[line] = true
		if column == "ads":
			var d: Dictionary = hud.v5.norm_rag({"ads": [line]})["ads"][0]
			out.append(d)
		else:
			out.append({"text": line, "actors": []})
	if column == "gossip" and out.size() < want:
		out.append_array(_gossip_from_people(want - out.size(), seen))
	return out

## More gossip from who really gets on with whom (sim relations), in the Rag's voice, when SIM's
## column has too few lines (a quiet day wants 8). Real names; nothing that SIM does not know.
const GOSSIP_T := {
	"best_friend": ["%s and %s: joined at the hip again. Get a room. A bigger one.", "Rag spies report %s and %s share every meal. Every. Single. One."],
	"friend": ["%s laughed at a joke by %s. Nobody else did.", "%s saved a seat for %s at dinner. Again. We are just saying."],
	"rival": ["%s and %s both want the same shift. Only one can win.", "Tension at the tray racks: %s thinks %s works too slowly."],
	"enemy": ["%s walked out when %s walked in. Frosty.", "%s and %s have not spoken for a week. The Rag has."],
	"dating": ["Hand in hand in the corridor: %s and %s. The Rag saw it first.", "%s and %s: is it serious? Our spies say yes."],
	"partners": ["%s and %s rearranged the furniture. Nesting?", "%s made breakfast for %s. Awww."],
	"married": ["Still in love: %s and %s. The rest of us are jealous.", "%s and %s argued about the thermostat. Married life."],
}
func _gossip_from_people(n: int, seen: Dictionary) -> Array:
	var out: Array = []
	var done := {}
	var k := 0
	for r in hud.v5.people():
		if out.size() >= n:
			break
		if String(r["kind"]) != "colonist":
			continue
		var a: int = int(r["id"])
		for rel in hud.v5.relations(a, 4):
			if out.size() >= n:
				break
			var st: String = String(rel["status"])
			var b: int = int(rel["other"])
			var key: String = "%d:%d" % [mini(a, b), maxi(a, b)]
			if not GOSSIP_T.has(st) or done.has(key):
				continue
			done[key] = true
			var tl: Array = GOSSIP_T[st]
			var na: String = hud.v5.agent_name(a).get_slice(" ", 0)
			var nb: String = hud.v5.agent_name(b).get_slice(" ", 0)
			var line: String = String(tl[k % tl.size()]) % [na, nb]
			k += 1
			if seen.has(line):
				continue
			seen[line] = true
			out.append({"text": line, "actors": [a, b]})
	return out

func _poll(parent: VBoxContainer, poll: Dictionary) -> void:
	var box := HBoxContainer.new()
	parent.add_child(box)
	var pb: VBoxContainer = _box(box, "RAG POLL", String(poll.get("question", "")))
	var ap: int = int(poll.get("approve", 50))
	var big: HBoxContainer = Kit.hbox(8)
	pb.add_child(big)
	big.add_child(_text("%d%%" % ap, "rag_head", 64, RED if ap < 50 else INK))
	var ch: int = int(poll.get("change", 0))
	var chl := _text(("▲ UP %d %s" % [ch, "POINT" if ch == 1 else "POINTS"]) if ch > 0 else (("▼ DOWN %d %s" % [-ch, "POINT" if ch == -1 else "POINTS"]) if ch < 0 else "— NO CHANGE"), "rag_head", 18, Color("2E7D32") if ch > 0 else (RED if ch < 0 else INK_2))
	chl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	big.add_child(chl)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.value = ap
	bar.custom_minimum_size = Vector2(0, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.12)
	var fg := StyleBoxFlat.new()
	fg.bg_color = RED if ap < 50 else INK
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	pb.add_child(bar)
	var cid: int = int(poll.get("commander", -1))
	pb.add_child(_rich("Commander [b]%s[/b]: %d%% say yes, %d%% say no." % [hud.v5.agent_name(cid), ap, 100 - ap], [cid], 14, INK, "rag_body"))

func _ads(iss: Dictionary) -> void:
	var hh: HBoxContainer = Kit.hbox(8)
	_body.add_child(hh)
	hh.add_child(_text("SMALL ADS", "rag_head", 22, INK))
	var r := _rule_ctl(1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(r)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	var ads: Array = _padded(iss.get("ads", []), "ads", 4)
	# Ship arrivals are ads too (V5_DESIGN §4.3: small ads from retail stock and ship arrivals), from
	# the traffic forecast, while SIM's issue has fewer than four.
	var sm = hud.main.sim
	if ads.size() < 4 and sm.get("traffic") != null and sm.traffic.has_method("forecast"):
		for sh in sm.traffic.forecast():
			if ads.size() >= 4:
				break
			var what: String = {"liner": "Beds and meals wanted for tourists.", "trader": "Bring your surplus. Credits paid.", "shuttle": "New faces coming. Say hello.",
				"science": "Scientists want lab time."}.get(String(sh.get("kind", "")), "Landing soon.")
			ads.append({"title": "ARRIVING", "text": "%s in %s. %s" % [String(sh.get("name", "A ship")), Kit.clock(float(sh.get("eta_s", 0.0))), what]})
	var hi := 0
	while ads.size() < 4 and hi < HOUSE_ADS.size():
		ads.append({"title": HOUSE_ADS[hi][0], "text": HOUSE_ADS[hi][1]})
		hi += 1
	for a in ads:
		var p := PanelContainer.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.25)
		s.set_border_width_all(1)
		s.border_color = INK
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 5
		s.content_margin_bottom = 6
		p.add_theme_stylebox_override("panel", s)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v: VBoxContainer = Kit.vbox(1)
		p.add_child(v)
		v.add_child(_text(String(a["title"]), "rag_head", 17, RED))
		var t := _text(String(a["text"]), "rag_body", 13, INK)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 190
		v.add_child(t)
		grid.add_child(p)

## "Serious news": the real problems, from the alerts, in plain STE (the Rag as a helper).
func _serious(iss: Dictionary) -> void:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color("1D2733")
	s.border_width_top = 3
	s.border_color = RED
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", s)
	_body.add_child(p)
	var v: VBoxContainer = Kit.vbox(4)
	p.add_child(v)
	var h: HBoxContainer = Kit.hbox(8)
	v.add_child(h)
	h.add_child(Kit.icon("sev_warning", 16, P.AMBER))
	h.add_child(Kit.head("SERIOUS NEWS", P.AMBER, 13, "head_wide"))
	var note := Kit.label("The real problems of the colony today.", "SmallLabel", 12, P.TEXT_2)
	h.add_child(note)
	for it in iss.get("serious", []):
		var r: HBoxContainer = Kit.hbox(8)
		var sev: int = int(it.get("severity", 1))
		r.add_child(Kit.icon(P.sev_icon(sev) if sev > 0 else "sev_ok", 14, P.sev(sev) if sev > 0 else P.GREEN))
		var l := Kit.wrap(String(it["text"]), 14, P.TEXT)
		r.add_child(l)
		v.add_child(r)

# ---------------------------------------------------------------- helpers
## The condensed headline fonts squeeze the glyphs, not their advances (a FontVariation transform):
## a negative glyph spacing per size closes the gaps (12 % of the size), so headlines set tight.
func _font(font: String, px: int) -> Font:
	if font == "rag_head" or font == "rag_mast":
		return Fonts.rag_size(P.fs(px), font == "rag_mast")
	return Fonts.get_font(font)

func _text(s: String, font: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", _font(font, px))
	l.add_theme_font_size_override("font_size", P.fs(px))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _chip(s: String) -> Control:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = RED
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.add_child(_text(s.to_upper(), "rag_head", 20, Color.WHITE))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

## A text with every actor's name as a link (click: select that person).
func _rich(s: String, actors: Array, px: int, col: Color, font: String, drop_cap: bool = false) -> RichTextLabel:
	var t: String = s
	for a in actors:
		var nm: String = hud.v5.agent_name(int(a))
		var first: String = nm.get_slice(" ", 0)
		var tag: String = "[url=agent:%d]" % int(a)
		if t.contains(nm):
			t = t.replace(nm, "%s%s[/url]" % [tag, nm])
			links.append({"id": int(a), "name": nm})
		elif first != "" and t.contains(first):
			t = t.replace(first, "%s%s[/url]" % [tag, first])
			links.append({"id": int(a), "name": first})
	if drop_cap and t.length() > 1 and not t.begins_with("["):
		t = "[font_size=%d][b]%s[/b][/font_size]%s" % [P.fs(px) * 2, t.substr(0, 1), t.substr(1)]
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.text = t
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", _font(font, px))
	r.add_theme_font_override("bold_font", Fonts.get_font("rag_body_b") if font.begins_with("rag_body") else _font(font, px))
	r.add_theme_font_override("italics_font", Fonts.get_font("rag_body_i"))
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		r.add_theme_font_size_override(k, P.fs(px))
	r.add_theme_color_override("default_color", col)
	r.meta_underlined = true
	r.meta_clicked.connect(_on_meta)
	# Hover on a name: a hand cursor and a tooltip with who it is (critic round 25).
	r.meta_hover_started.connect(func(meta):
		r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		r.tooltip_text = _name_tip(str(meta)))
	r.meta_hover_ended.connect(func(_meta):
		r.mouse_default_cursor_shape = Control.CURSOR_ARROW
		r.tooltip_text = "")
	r.add_theme_color_override("font_selected_color", RED)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r

func _name_tip(meta: String) -> String:
	if not meta.begins_with("agent:"):
		return ""
	var id: int = int(meta.substr(6))
	var p: Dictionary = hud.v5.person(id)
	if p.is_empty():
		return "%s\nClick: select this person." % hud.v5.agent_name(id)
	return "%s\n%s. Click: select them and open their personnel file." % [p["name"], String(p["rank"]["title"])]

## How many lines a headline takes at px in width w.
func _lines_of(s: String, px: int, w: float) -> int:
	var f: Font = _font("rag_head", px)
	var lines := 1
	var cur := 0.0
	var sp: float = f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(px)).x
	for word in s.split(" ", false):
		var ww: float = f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(px)).x
		if cur > 0.0 and cur + sp + ww > w:
			lines += 1
			cur = ww
		else:
			cur += (sp if cur > 0.0 else 0.0) + ww
	return lines

## The quote of the day: a line the lead's first actor said lately (SIM recent_lines).
func _quote(parent: VBoxContainer, L: Dictionary) -> void:
	var actors: Array = L.get("actors", [])
	if actors.is_empty():
		return
	var lines: Array = hud.v5.recent_lines(int(actors[0]), 1)
	if lines.is_empty():
		return
	var q: Dictionary = lines[0]
	parent.add_child(_text("QUOTE OF THE DAY", "rag_head", 16, RED))
	parent.add_child(_rich("\"%s\" — %s" % [String(q.get("text", "")), hud.v5.agent_name(int(actors[0]))], actors, 16, INK, "rag_body_i"))

## "Inside today": the other headlines, each with a page number (the page scrolls to them).
func _inside(parent: VBoxContainer, iss: Dictionary) -> void:
	var st: Array = iss.get("stories", [])
	if st.is_empty():
		return
	parent.add_child(_text("INSIDE TODAY", "rag_head", 16, RED))
	var pg := 2
	for s in st.slice(0, 4):
		var h: HBoxContainer = Kit.hbox(6)
		var l := _text(String(s.get("headline", "")), "rag_head", 15, INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(l)
		h.add_child(_text("P%d" % pg, "rag_head", 15, RED))
		parent.add_child(h)
		pg += 1

## Quiet day (critic round 30): a big puzzle box, WHO SAID IT? Three real lines from colonists and the
## three names in another order; the answers are printed upside down (here: small, at the foot).
var puzzle: Array = []   # [{text, who}] (tests)
var lead_lines := 0      # lines of the lead headline as laid out (tests)
func _puzzle() -> void:
	puzzle = []
	var seen := {}
	for r in hud.v5.people():
		if puzzle.size() >= 3:
			break
		var id: int = int(r["id"])
		var ln: Array = hud.v5.recent_lines(id, 1)
		if ln.is_empty() or String(ln[0].get("text", "")) == "" or seen.has(String(ln[0]["text"])):
			continue
		seen[String(ln[0]["text"])] = true
		puzzle.append({"text": String(ln[0]["text"]), "who": id})
	if puzzle.size() < 2:
		return
	_rule(3)
	var row: HBoxContainer = Kit.hbox(14)
	_body.add_child(row)
	var b: VBoxContainer = _box(row, "RAG PUZZLE: WHO SAID IT?", "match the quote to the colonist")
	var names: Array = []
	for i in puzzle.size():
		b.add_child(_text("%d.  \"%s\"" % [i + 1, String(puzzle[i]["text"])], "rag_body_i", 18, INK))
		names.append(puzzle[i]["who"])
	var shuffled: Array = names.duplicate()
	shuffled.push_back(shuffled.pop_front())   # a fixed order that is never the answer
	var letters := ["A", "B", "C"]
	var nl: Array = []
	for i in shuffled.size():
		nl.append("[b]%s[/b] [url=agent:%d]%s[/url]" % [letters[i], int(shuffled[i]), hud.v5.agent_name(int(shuffled[i]))])
	var names_l := _rich("   ".join(nl), [], 18, INK, "rag_body")
	b.add_child(names_l)
	var ans: Array = []
	for i in names.size():
		ans.append("%d-%s" % [i + 1, letters[shuffled.find(names[i])]])
	b.add_child(_text("Answers: " + ", ".join(ans) + ". No cheating.", "rag_body_i", 12, INK_2))

func _on_meta(meta) -> void:
	var m: String = str(meta)
	if m.begins_with("agent:"):
		var id: int = int(m.substr(6))
		var a: Dictionary = hud.v5.agent(id)
		if a.is_empty():
			hud.toast("That person is no longer in the colony.", "info")
			return
		hud.main.select("agent", id)
		hud.main.focus_on(a["pos"])
		if hud.person != null and hud.v5.live("people"):
			hud.open_person(id)

func _box(row: HBoxContainer, title: String, sub: String) -> VBoxContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.18)
	s.set_border_width_all(2)
	s.border_color = INK
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 0
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(p)
	var v: VBoxContainer = Kit.vbox(6)
	p.add_child(v)
	var hd := PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = INK
	hs.content_margin_left = 8
	hs.content_margin_right = 8
	hs.content_margin_top = 2
	hs.content_margin_bottom = 2
	hs.expand_margin_left = 10
	hs.expand_margin_right = 10
	hd.add_theme_stylebox_override("panel", hs)
	hd.add_child(_text(title, "rag_head", 22, Color.WHITE))
	v.add_child(hd)
	if sub != "":
		var sl := _text(sub, "rag_body_i", 13, INK_2)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sl)
	return v

func _rule(px: int) -> void:
	_body.add_child(_rule_ctl(px))

func _rule_ctl(px: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = INK
	r.custom_minimum_size = Vector2(0, px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _vrule() -> ColorRect:
	var r := ColorRect.new()
	r.color = INK
	r.custom_minimum_size = Vector2(1, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
