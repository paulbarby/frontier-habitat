extends SceneTree
## Help, codex, What's new and loader tips describe every v5 feature, and say what the game does (UI, 2026-10-02):
##   node tools/godot.mjs script res://tools/ui/test_help_v5.gd
## 1. The topic list has every feature (a checklist); each topic has a category, an icon and short sentences.
## 2. The numbers in the text equal the numbers in the content (unrest stages, slowdown, lock-down hours, officer
##    ratio, jail cells, dome stages, venues and homes, apartment units, planets).
## 3. Every "key X" in the help, in What's new and in the loader tips is a key of ui/keys.gd with that job.
## 4. How to play > People shows every topic in its group; the Codex Guide tab lists every topic.
## 5. What's new and the loader tips name every feature.
## 6. The codex lists only the hazards of the planet: the airless world has no dust storm, wind storm or dust devil.

const Help = preload("res://ui/v5_help.gd")
const KeyList = preload("res://ui/keys.gd")

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0

const FEATURES := ["dock", "roofs", "floors", "settings", "sound_in", "follow", "bubbles", "rag", "unrest", "responses", "lockdown", "security",
	"jail", "love", "requests", "tourism", "secrets", "file", "discipline", "families", "ranks", "skills", "academy", "housing", "giants",
	"venues", "dome", "planets", "chat", "parties", "hr", "complaints", "hr_officer"]

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func q(c: Callable, frames: int = 4) -> void:
	_queue.append([c, frames])

func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		_plan()
	if _n < 7:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _queue.is_empty():
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _text_of(id: String) -> String:
	return String(Help.topic(id)[4]) if not Help.topic(id).is_empty() else ""

func _all_text() -> String:
	var parts: Array = []
	for t in Help.TOPICS:
		parts.append(String(t[4]))
	return "\n".join(parts)

func _has_all(text: String, needles: Array) -> Array:
	var miss: Array = []
	for n in needles:
		if not text.to_lower().contains(String(n).to_lower()):
			miss.append(n)
	return miss

func _text_has(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	for c in node.get_children():
		if _text_has(c, needle):
			return true
	return false

func _plan() -> void:
	var hud = main.hud
	# ---- 1. topics
	var ids: Array = []
	for t in Help.TOPICS:
		ids.append(String(t[0]))
	var missing: Array = FEATURES.filter(func(f): return not ids.has(f))
	check("every v5 feature has a topic", missing.is_empty(), "missing: " + str(missing))
	var dup: Array = ids.filter(func(i): return ids.count(i) > 1)
	check("topic ids are unique", dup.is_empty(), str(dup))
	var bad: Array = []
	var long_sentences: Array = []
	var Icons = load("res://ui/theme/icons.gd")
	for t in Help.TOPICS:
		if not Help.CATEGORIES.has(String(t[3])):
			bad.append("%s: category %s" % [t[0], t[3]])
		if not Icons.has(String(t[2])):
			bad.append("%s: icon %s" % [t[0], t[2]])
		for sent in String(t[4]).split(". "):
			var words: int = sent.split(" ", false).size()
			if words > 40:
				long_sentences.append("%s: %d words" % [t[0], words])
	check("each topic has a known category and icon", bad.is_empty(), str(bad))
	check("no sentence is longer than 40 words (STE)", long_sentences.is_empty(), str(long_sentences))

	# ---- 2. numbers against the content
	var soc: Dictionary = _json("res://content/society.json")
	var stages: Array = soc["unrest"]["stages"]
	var ut: String = _text_of("unrest")
	var miss_st: Array = []
	for st in stages:
		if int(st[1]) > 0 and not ut.contains("%s from %d" % [String(st[0]).capitalize(), int(st[1])]):
			miss_st.append(st)
	check("Unrest: every stage and its threshold equal the content", miss_st.is_empty(), str(miss_st))
	var slow: int = int(roundf((1.0 - float(soc["unrest"]["slowdown_mult"])) * 100.0))
	check("Unrest: the slowdown is %d %%" % slow, ut.contains("%d %% slower" % slow))
	var lh: int = int(soc["responses"]["lock_down"]["lock_hours"])
	check("Lockdown: %d game hours" % lh, _text_of("lockdown").contains("%d game hours" % lh))
	check("Answers: 7", _text_of("responses").contains("7 answers") and (soc["responses"] as Dictionary).size() == 7, str((soc["responses"] as Dictionary).size()))
	var ratio: int = int(soc["security"]["officer_ratio"])
	check("Security: 1 officer for each %d people" % ratio, _text_of("security").contains("1 officer for each %d people" % ratio))
	var blds: Dictionary = _json("res://content/buildings.json")
	var cells: Array = (blds["jail"]["sizes"]["cells"] as Array).slice(0, (blds["jail"]["size_list"] as Array).size())
	check("Jail: %s cells" % str(cells), _text_of("jail").contains("%d, %d or %d cells" % [int(cells[0]), int(cells[1]), int(cells[2])]), str(cells))
	var dome: Dictionary = blds["super_dome"]
	var dn: int = (dome["build_stages"] as Array).size()
	check("Dome: %d stages in the text and the badge" % dn, _text_of("dome").contains("%d stages" % dn) and _text_of("dome").contains("STAGE n OF %d" % dn), str(dn))
	var homes: int = 0
	for u in dome["units"]:
		homes += int(u["count"])
	check("Dome: %d venues and %d homes" % [(dome["venues"] as Array).size(), homes], _text_of("dome").contains("%d venues" % (dome["venues"] as Array).size()) and _text_of("dome").contains("%d homes" % homes), "")
	var ap: Dictionary = blds["apartment_block"]
	var fam: int = 0
	var pent: int = 0
	for u in ap["units"]:
		if String(u["quality"]) == "penthouse":
			pent += int(u["count"])
		else:
			fam += int(u["count"])
	check("Apartment block: %d floors, %d family units, %d penthouses" % [int(ap["floors"]), fam, pent], _text_of("giants").contains("%d floors" % int(ap["floors"])) and _text_of("giants").contains("%d family units and %d penthouses" % [fam, pent]))
	var pl: Dictionary = _json("res://content/scenarios.json")["planets"]
	var pt: String = _text_of("planets")
	var pmiss: Array = []
	for need in ["short days (%d s)" % int(pl["cold"]["daylight_seconds"]), "weak sun (%s times)" % str(pl["cold"]["solar_mult"]), "strong sun (%s times)" % str(pl["airless"]["solar_mult"]),
			"meteors come %s times" % str(pl["airless"]["hazards"]["meteor"]), "flares %s times" % str(pl["airless"]["hazards"]["solar_flare"]), "double radiation"]:
		if not pt.contains(need):
			pmiss.append(need)
	check("Planets: the numbers equal content/scenarios.json", pmiss.is_empty() and float(pl["airless"]["radiation_mult"]) == 2.0, str(pmiss))
	# Parties and HR (sections 16 and 17).
	var cel: Dictionary = soc["celebrations"]
	var hrc: Dictionary = soc["hr"]
	var pty: String = _text_of("parties")
	check("Parties: hours %d to %d, one party hour %d s, offer lapses after %d min, 1 unit for %d guests" % [int(cel["hours_min"]), int(cel["hours_max"]), int(cel["hour_s"]), int(cel["offer_valid_s"]) / 60, int(soc["party"]["per_people"])],
		pty.contains("(%d to %d; one party hour is %d seconds)" % [int(cel["hours_min"]), int(cel["hours_max"]), int(cel["hour_s"])]) and pty.contains("in %d minutes" % (int(cel["offer_valid_s"]) / 60)) and pty.contains("for every %d guests" % int(soc["party"]["per_people"])))
	var ht: String = _text_of("hr")
	check("HR: complaint under %d, survey every %d days, posts %s" % [int(hrc["complaint_sat"]), int(hrc["survey_days"]), str(hrc["slots"])],
		ht.contains("under %d" % int(hrc["complaint_sat"])) and ht.contains("Every %d days" % int(hrc["survey_days"])) and ht.contains("Size S has %d post, M %d and L %d" % [int(hrc["slots"][0]), int(hrc["slots"][1]), int(hrc["slots"][2])]))
	check("Transfers: under %d, lapse after %d days" % [int(hrc["transfer_sat"]), int(hrc["transfer_offer_days"])], _text_of("complaints").contains("under %d" % int(hrc["transfer_sat"])) and _text_of("complaints").contains("for %d days lapses" % int(hrc["transfer_offer_days"])))
	check("The chat topic names the setting that the Settings screen has", _text_of("chat").contains("Cheeky dialogue") and _text_of("settings").contains("cheeky dialogue"))
	var sk: int = main.sim.people.skills(main.sim.state["agents"][main.sim.state["agents"].keys()[0]]).size()
	check("Skills: %d" % sk, _text_of("skills").begins_with("%d skills" % sk), str(sk))

	# ---- 3. every "key X" is a key of the list with that job
	var keymap := {}   # letter -> row short text
	for r in KeyList.ROWS:
		for c in r["codes"]:
			keymap[String(c).trim_prefix("KEY_")] = String(r["keys"]) + " " + String(r["long"])
	var re := RegEx.new()
	re.compile("\\b[Kk]ey ([A-Z0-9])\\b")
	var re_press := RegEx.new()
	re_press.compile("\\bpress ([A-Z0-9])\\b")
	var shell: String = FileAccess.get_file_as_string("res://templates/web_shell.src.html")
	var new5: Array = load("res://ui/screens/title_screen.gd").NEW_5
	var new5_text: String = "\n".join(new5.map(func(r): return String(r[1])))
	var unknown: Array = []
	var wrong: Array = []
	# What each key opens, from the text next to it (the topic or the tip names the job).
	var job := {"L": "dock", "Y": "roof", "U": "crew", "J": "tabloid", "V": "shoulder", "C": "colony", "K": "codex", "N": "advisor"}
	for src in [[_all_text(), re], [new5_text, re], [shell, re], [shell, re_press]]:
		for m in (src[1] as RegEx).search_all(String(src[0])):
			var letter: String = m.get_string(1)
			if not keymap.has(letter):
				unknown.append(letter)
				continue
			var ctx: String = String(src[0]).substr(maxi(0, m.get_start() - 90), 200).to_lower()
			if job.has(letter) and not ctx.contains(String(job[letter])) and not ctx.contains("colony window"):
				wrong.append("%s near: %s" % [letter, ctx.replace("\n", " ")])
	check("every key named in the text is a key of the list", unknown.is_empty(), str(unknown))
	check("each named key sits next to the job the list gives it", wrong.is_empty(), "\n".join(wrong))

	# ---- 5. What's new and the loader tips name every feature
	var nw_miss: Array = _has_all(new5_text, ["People", "shoulder", "Rag", "Reviews", "Unrest", "Crew", "Security", "dome", "Tourists", "dock", "Roofs", "Planets", "parties", "HR office"])
	check("What's new names every feature", nw_miss.is_empty(), str(nw_miss))
	var shell_miss: Array = _has_all(shell, ["shoulder", "right drag", "Rag", "Crew", "officer", "lock down", "left dock", "roof", "tourists", "dome", "adopt", "airless", "venue", "party", "HR office", "flirt"])
	check("loader tips name every feature", shell_miss.is_empty(), str(shell_miss))
	check("loader tips: 15 or more", shell.count("', '") + 1 >= 15, str(shell.count("', '") + 1))

	# ---- 4. screens
	q(func(): hud.open_screen("help", "people"), 8)
	q(func():
		var top = hud.screens.top_screen()
		var gm: Array = []
		var tm: Array = []
		if top == null:
			gm.append("no help screen")
		else:
			for c in Help.CATEGORIES:
				if top.find_child("Group_" + String(c), true, false) == null:
					gm.append(c)
			for t in Help.TOPICS:
				if not _text_has(top, String(t[1]).to_upper()):
					tm.append(t[0])
		check("How to play > People: a heading for each group", gm.is_empty(), str(gm))
		check("How to play > People: a card for each topic", tm.is_empty(), str(tm))
		hud.screens.close_all(), 4)
	q(func():
		var cx = load("res://ui/codex.gd").new(hud)
		var names: Array = []
		for e in cx.entries("society"):
			names.append(String(e["name"]))
		var cm: Array = []
		for t in Help.TOPICS:
			if not names.has(String(t[1])):
				cm.append(t[0])
		check("Codex, Guide tab: every topic is listed", cm.is_empty(), str(cm))
		check("Codex Guide has no duplicate names", names.size() == _unique(names).size(), str(names.size()))
		var hz: Array = []
		for e in cx.entries("hazard"):
			hz.append(String(e["name"]))
		check("Codex on the dry world lists dust storm, wind storm and dust devil", hz.has("Dust storm") and hz.has("Wind storm") and hz.has("Dust devil"), str(hz)), 2)
	# ---- 6. the airless world
	q(func(): main.start_new(1001, {"planet": "airless", "difficulty": "normal", "hazards": "normal"}), 12)
	q(func():
		var d = main.hud.data
		var kinds: Array = d.hazard_kinds_here()
		check("airless: SIM's kinds_here has no dust storm, wind storm or dust devil", not kinds.has("dust_storm") and not kinds.has("wind_storm") and not kinds.has("dust_devil") and kinds.has("meteor") and kinds.has("solar_flare"), str(kinds))
		var cx = load("res://ui/codex.gd").new(main.hud)
		var hz: Array = []
		var flare_desc := ""
		for e in cx.entries("hazard"):
			hz.append(String(e["name"]))
			if String(e["id"]) == "solar_flare":
				flare_desc = String(e["desc"])
		check("airless: the codex lists no dust storm, wind storm or dust devil", not hz.has("Dust storm") and not hz.has("Wind storm") and not hz.has("Dust devil") and hz.has("Meteor strike") and hz.has("Solar flare"), str(hz))
		check("airless: the flare page says it is stronger", flare_desc.contains("1.5 times") and flare_desc.contains("double"), flare_desc)
		var fc: Array = d.hazard_forecast()
		var bad_f: Array = fc.filter(func(e): return String(e["kind"]) in ["dust_storm", "wind_storm", "dust_devil"])
		check("airless: the forecast has none of them", bad_f.is_empty(), str(bad_f))
		# A wind turbine is locked with SIM's reason, and the palette shows it.
		var li: Dictionary = d.lock_info("wind_turbine", 1)
		check("airless: the wind turbine lock names the planet", not bool(li["ok"]) and String(li["full"]).contains("no air"), str(li))
		var Insp = load("res://ui/hud/inspector_sections.gd")
		check("the inspector and the why-stopped page know the block no_atmosphere", Insp.BLOCK_TEXT.has("no_atmosphere") and Insp.SHORT.has("no_atmosphere"))
		var code: String = main.sim.place.check_building("wind_turbine", Vector2(main.sim.world.center.x + 30.0, main.sim.world.center.y), 0.0)
		check("airless: placing a wind turbine is refused with no_atmosphere", code == "no_atmosphere", code)
		var txt: String = String(main.sim.place.reason_text(code))
		check("airless: the refusal says why", txt.contains("no air"), txt), 2)

func _unique(a: Array) -> Array:
	var out: Array = []
	for x in a:
		if not out.has(x):
			out.append(x)
	return out
