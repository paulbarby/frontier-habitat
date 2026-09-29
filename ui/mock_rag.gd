extends RefCounted
## "The Regolith Rag" preview issues (V5_DESIGN §4.3), used until SIM publishes the social log and
## the daily issues (docs/requests/SIM-to-UI.md, v5). The stories use the colony's real colonists,
## buildings and alerts, deterministically from the day, so the window shows a believable paper.
## Shape of one issue (proposed to SIM in docs/requests/UI-to-SIM.md, 2026-09-29):
##   {no, day, price, lead: {kicker, headline, sub, body, actors, photo: {agents, place, pose}, caption},
##    stories: [{tag, headline, body, actors}], gossip: [{text, actors}],
##    couples: [{a, b, status, note}], feuds: [{a, b, note}],
##    poll: {commander, approve, change, question}, ads: [{title, text}], serious: [{text, severity}]}
## Names in bodies are plain text; the window links every actor's name (click: select the person).

const LEADS := [
	["EXCLUSIVE", "LOVE IN THE AIRLOCK!", "Sparks fly at the pressure door", "Colony sweethearts %s and %s were caught holding hands in Airlock 1 last night, and our snapper was there. \"We were only checking the seals,\" blushed %s. A likely story! Friends say the pair have shared every lunch this week, and the tomatoes are not the only thing ripening in the greenhouse.", "kiss_brief", "airlock"],
	["SHOCK", "SPANNER IN THE WORKS!", "Refinery rivals in shouting match", "Tempers boiled over at the refinery when %s told %s to \"fix your own furnace\". Witnesses say the row lasted a full shift change. The Rag understands the pair both want the same promotion. Watch this space, crew!", "argue", "refinery"],
	["SCANDAL", "WHO ATE THE LAST POTATO?", "Kitchen mystery grips the base", "The colony is split after the last baked potato vanished from the Kitchen & Mess. %s swears it was there at breakfast. %s was seen licking butter off a spoon. Coincidence? The Rag thinks not.", "argue", "kitchen"],
	["PARTY", "DOME, SWEET DOME!", "Crew dance until the lights go out", "What a night! %s led a conga line through three corridors while %s ran the music from a spare comms panel. Nobody was hurt, but the night shift says the dust is still settling.", "cheer", "lounge"],
]
const STORIES := [
	["LOVE", "CUPID STRIKES IN THE GREENHOUSE", "%s brought %s a single basil leaf. Sources say it was \"the biggest leaf in the colony\"."],
	["FEUD", "BUNK WARS: THE SNORING FILES", "%s says %s snores \"like a failing air pump\". A bunk swap is under discussion."],
	["WORK", "GRAFT HERO OF THE WEEK", "%s did three repairs before breakfast. Captain says: \"Keep it up.\" %s says: \"Show-off.\""],
	["SPORT", "ARCADE KING CROWNED", "%s set a new high score on the corridor quiz machine. %s demands a rematch."],
	["LOVE", "DATE NIGHT AT THE CANTINA", "%s and %s shared a table for two and one very small dessert."],
	["FEUD", "HANDS OFF MY WRENCH!", "%s borrowed %s's favourite wrench \"for a minute\". That was three days ago."],
]
const GOSSIP := [
	"Which technician was seen humming love songs to a solar panel? Our lips are sealed, %s.",
	"A little bird says %s has been practising dance moves in the storehouse after dark.",
	"%s asked for extra dessert twice this week. Sweet tooth, or sweet on someone?",
	"Rumour has it %s wants the Captain's job. The Captain has not heard. Yet.",
	"Spotted: %s writing a poem. The Rag hopes it rhymes with \"regolith\". Nothing does.",
]
const ADS := [
	["FOR SALE", "One oxygen mask, slightly used. Smells of mint. Ask at Airlock 1."],
	["WANTED", "Dance partner for the Cantina. Must own shoes. No robots (yet)."],
	["LOST", "Left sock, grey, sentimental value. Last seen in the laundry cycle."],
	["SWAP", "Two potato rations for one tomato. Serious offers only."],
	["LESSONS", "Learn to juggle in low gravity. First lesson free, bruises extra."],
	["NOTICE", "The quiet room is for QUIET. You know who you are."],
]

static func issues(sim, hud = null, count: int = 5) -> Array:
	var st: Dictionary = sim.state
	var ids: Array = []
	for aid in st["agents"]:
		var a: Dictionary = st["agents"][aid]
		if String(a.get("state", "")) == "alive" and String(a.get("kind", "human")) != "visitor":
			ids.append(int(aid))
	ids.sort()
	var day: int = int(sim.util.day_number()) if sim.util.has_method("day_number") else 1
	var out: Array = []
	if ids.size() < 2:
		return out
	for k in count:
		var d: int = day - k
		if d < 1:
			break
		out.append(_issue(sim, hud, ids, d, 40 + d))
	return out

static func _pick(ids: Array, seed_v: int, n: int) -> Array:
	var out: Array = []
	var i: int = posmod(seed_v * 7919, ids.size())
	while out.size() < mini(n, ids.size()):
		var id: int = ids[i % ids.size()]
		if not out.has(id):
			out.append(id)
		i += 3
	return out

static func _name(sim, id: int) -> String:
	return String(sim.state["agents"].get(id, {}).get("name", "Someone"))

static func _first(sim, id: int) -> String:
	return _name(sim, id).get_slice(" ", 0)

static func _issue(sim, hud, ids: Array, d: int, no: int) -> Dictionary:
	var L: Array = LEADS[d % LEADS.size()]
	var la: Array = _pick(ids, d, 2)
	var lead := {"kicker": L[0], "headline": L[1], "sub": L[2],
		"body": L[3] % [_name(sim, la[0]), _name(sim, la[1]), _first(sim, la[0])] if String(L[3]).count("%s") == 3 else L[3] % [_name(sim, la[0]), _name(sim, la[1])],
		"actors": la, "photo": {"agents": la, "place": L[5], "pose": L[4]},
		"caption": "CAUGHT ON CAMERA: %s and %s. Rag snapper." % [_first(sim, la[0]), _first(sim, la[1])]}
	var stories: Array = []
	for j in 3:
		var S: Array = STORIES[(d + j * 2) % STORIES.size()]
		var sa: Array = _pick(ids, d * 5 + j * 11 + 3, 2)
		stories.append({"tag": S[0], "headline": S[1], "body": S[2] % [_first(sim, sa[0]), _first(sim, sa[1])], "actors": sa})
	var gossip: Array = []
	for j in 3:
		var g: String = GOSSIP[(d + j) % GOSSIP.size()]
		var ga: Array = _pick(ids, d * 3 + j * 17 + 1, 1)
		gossip.append({"text": g % _first(sim, ga[0]), "actors": ga})
	var ca: Array = _pick(ids, d * 13 + 5, 4)
	var couples: Array = [{"a": ca[0], "b": ca[1], "status": "dating", "note": "Seen sharing a tray at lunch."}]
	if ca.size() >= 4:
		couples.append({"a": ca[2], "b": ca[3], "status": "crush", "note": "One-way traffic, sources say."})
	var fa: Array = _pick(ids, d * 19 + 7, 2)
	var feuds: Array = [{"a": fa[0], "b": fa[1], "note": "Not speaking since the wrench affair."}]
	var cmd: int = ids[0]
	var approve: int = 45 + posmod(d * 37, 40)
	var ads: Array = []
	for j in 4:
		var A: Array = ADS[(d + j) % ADS.size()]
		ads.append({"title": A[0], "text": A[1]})
	var serious: Array = []
	if sim.get("alerts") != null and sim.alerts.has_method("incidents"):
		for i in sim.alerts.incidents():
			var iss: Dictionary = i.get("issue", {})
			if int(iss.get("severity", 1)) >= 2:
				serious.append({"text": String(iss.get("text", "")), "severity": int(iss.get("severity", 2))})
			if serious.size() >= 3:
				break
	if serious.is_empty():
		serious.append({"text": "No serious problem today. Air, water, food and power hold.", "severity": 0})
	return {"no": no, "day": d, "price": "1 credit", "lead": lead, "stories": stories, "gossip": gossip, "couples": couples,
		"feuds": feuds, "poll": {"commander": cmd, "approve": approve, "change": posmod(d * 11, 9) - 4, "question": "Is the Commander doing a good job?"},
		"ads": ads, "serious": serious, "mock": true}
