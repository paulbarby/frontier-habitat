extends SceneTree
## Writes content/saves/showcase_v5.fhsave (docs/V5_DESIGN.md section 11): the v4 showcase (two bases)
## grown into a society: about 110 people with 6 children in families, residence tubes, an apartment
## block, a retail module, a park, an academy with students, a security office, a jail with a prisoner,
## a distillery, a finished and staffed super dome with tourists, two couples, an affair about to
## break, Rag issues from several days of play and calm unrest.
##   node tools/godot.mjs script res://tests/make_showcase_v5.gd [days]
## SET-UP (documented, ledger reason "scenario"): finished structures joined by corridors and cables
## (tests/helpers.gd attach), settlers admitted, stock for food, goods and water, the couples and the
## affair, six children with their parents, officer training, a liner (debug traffic_now) and the
## prisoner and the students at the end. Everything else is ordinary play. Debug and unlock_all are
## off again in the save. The ledger stays {}.

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const H = preload("res://tests/helpers.gd")

var sim

func _cmd(kind: String, p: Dictionary) -> Dictionary:
	var id: int = sim.submit(kind, p)
	sim.step()
	var r: Dictionary = sim.cmds.results.get(id, {"ok": false, "code": "not_applied"})
	if not bool(r.get("ok", false)):
		print("  %s refused: %s" % [kind, str(r)])
	return r

func _colonists() -> Array:
	var out: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and String(a.get("kind", "")) != "visitor" and String(a.get("kind", "")) != "child":
			out.append(a)
	return out

func _place(def_id: String, near: Vector2, size: int, base_id: int = -1) -> Dictionary:
	var b: Dictionary = H.attach(sim, def_id, near, size, 60, base_id)
	print("  %s %s" % [def_id, "at %s" % str(b["pos"]) if not b.is_empty() else "NOT PLACED"])
	return b

func _exterior(def_id: String, near: Vector2, size: int, base_id: int = -1) -> Dictionary:
	var rooms: Array = []
	for id in sim.state["buildings"]:
		var rb: Dictionary = sim.state["buildings"][id]
		if rb["state"] == "active" and rb["kind"] == "room" and sim.topo.atmo_comp.has(int(id)) and (base_id == -1 or sim.bases.base_of(int(id)) == base_id):
			rooms.append([(rb["pos"] as Vector2).distance_to(near), int(id)])
	rooms.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	var r0: float = float(sim.sizes.def_for(def_id, size)["radius"])
	var errs: Array = []
	for e in rooms.slice(0, 40):
		var rb2: Dictionary = sim.state["buildings"][int(e[1])]
		for gap in [7.0, 12.0, 18.0]:
			for k in 24:
				var p: Vector2 = sim.place.snap_pos((rb2["pos"] as Vector2) + Vector2.RIGHT.rotated(k * TAU / 24.0) * (float(rb2["radius"]) + r0 + gap))
				if sim.place.check_building(def_id, p, 0.0, -1, size) != "ok":
					continue
				var b: Dictionary = sim.build.spawn_active(def_id, p, 0.0, size)
				var l: Dictionary = H.link_now(sim, "cable", int(rb2["id"]), int(b["id"]), errs)
				if l.is_empty():
					sim.build._remove_record(b)
					errs.clear()
					continue
				sim.topo.rebuild(true)
				return b
	print("  %s NOT PLACED" % def_id)
	return {}

func _init() -> void:
	var nums: Array = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_float():
			nums.append(float(a))
	var days: float = nums[0] if nums.size() > 0 else 5.0
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	sim = Sim.new()
	sim.load_state(dec["state"], {"debug": true})
	sim.state["flags"]["unlock_all"] = true
	var dead0 := 0
	for a0 in sim.state["agents"].values():
		if a0["state"] == "dead":
			dead0 += 1
	var base: int = int(sim.bases.ids()[0])
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var lp: Vector2 = lander["pos"]
	print("start: %d colonists, day %.1f" % [sim.alive_count(), sim.seconds() / 600.0])
	# ---- utilities for 110 people: power, water, air, food stock.
	for k in 3:
		H.attach_power(sim, lp, base)
	for k in 5:
		_exterior("water_extractor", lp, 2, base)
	for k in 3:
		_exterior("reservoir", lp, 2, base)
	for k in 4:
		_place("atmo_processor", lp, 2, base)
	for k in 2:
		_place("water_recycler", lp, 2, base)
	var stores: Array = []
	for k in 3:
		var s: Dictionary = _place("storehouse", lp, 2, base)
		if not s.is_empty():
			stores.append(s)
	_place("kitchen", lp, 2, base)
	_place("cantina", lp, 2, base)
	_place("medical", lp, 1, base)
	# ---- the v5 structures.
	var tubes: Array = []
	for k in 3:
		tubes.append(_place("residence_tube", lp, 2, base))
	var exe: Dictionary = _place("residence_tube", lp, 2, base)
	if not exe.is_empty():
		exe["variant"] = "executive"
	var block: Dictionary = _place("apartment_block", lp, 1, base)
	var retail: Dictionary = _place("retail", lp, 1, base)
	var park: Dictionary = _place("park", lp, 2, base)
	var academy: Dictionary = _place("academy", lp, 1, base)
	var office: Dictionary = _place("security_office", lp, 0, base)
	var jail: Dictionary = _place("jail", lp, 1, base)
	var still: Dictionary = _place("distillery", lp, 1, base)
	var dome: Dictionary = _place("super_dome", lp, 1, base)
	var pad: Dictionary = {}
	for id in sim.state["buildings"]:
		if String(sim.state["buildings"][id]["def"]) == "landing_pad" and sim.state["buildings"][id]["state"] == "active":
			pad = sim.state["buildings"][id]
	if pad.is_empty():
		pad = _exterior("landing_pad", lp, 1, base)
	# ---- stock (SET-UP: as if made over the weeks before).
	if not stores.is_empty():
		var st0: int = int(stores[0]["inv_out"])
		for item in {"meals": 700, "drinks": 120, "snacks": 120}.keys():
			sim.inv.add_new_forced(st0, item, {"meals": 700, "drinks": 120, "snacks": 120}[item], "scenario")
		if stores.size() > 1:
			var st1: int = int(stores[1]["inv_out"])
			sim.inv.add_new_forced(st1, "meals", 500, "scenario")
			for item in ["clothing", "gifts", "gadgets", "luxury_goods"]:
				sim.inv.add_new_forced(st1, item, 40, "scenario")
		if stores.size() > 2:
			sim.inv.add_new_forced(int(stores[2]["inv_out"]), "meals", 400, "scenario")
			sim.inv.add_new_forced(int(stores[2]["inv_out"]), "potato", 60, "scenario")
			sim.inv.add_new_forced(int(stores[2]["inv_out"]), "wheat", 40, "scenario")
	H.fill_utilities(sim, 1.0, 0.9, true)
	sim.run_seconds(20.0)
	# ---- people: settlers up to about 104 adults.
	var guard := 0
	while _colonists().size() < 104 and guard < 60:
		guard += 1
		_cmd("admit_settlers", {"count": mini(5, 104 - _colonists().size()), "roles": ["technician", "grower", "operator", "scientist", "technician", "operator", "grower", "medic"]})
		H.fill_utilities(sim, 1.0, 0.9, true)
		sim.run_seconds(40.0)
	print("colonists: %d" % _colonists().size())
	var ppl: Array = _colonists()
	# ---- six security officers (SET-UP: trained at the academy before).
	var officers := 0
	for a in ppl:
		if officers >= 6:
			break
		if String(a["role"]) == "technician" and not ["commander", "captain"].has(String(sim.people.rank(a)["rank"])):
			sim.people.rec_w(a)["skill_bonus"] = {"security": 55}
			sim.people.invalidate(int(a["id"]))
			if bool(_cmd("set_role", {"agent": int(a["id"]), "role": "security"}).get("ok", false)):
				officers += 1
	# ---- couples, an affair, families with six children (SET-UP).
	var pairs: Array = []
	var used := {}
	for i in ppl.size():
		for j in range(i + 1, ppl.size()):
			if pairs.size() >= 5:
				break
			if used.has(i) or used.has(j) or String(ppl[i]["role"]) == "security" or String(ppl[j]["role"]) == "security":
				continue
			if sim.social.compatible(ppl[i], ppl[j]):
				pairs.append([ppl[i], ppl[j]])
				used[i] = true
				used[j] = true
	var now: int = int(sim.state["tick"])
	var statuses: Array = ["married", "married", "partners", "partners", "dating"]
	for k in pairs.size():
		var x: Dictionary = pairs[k][0]
		var y: Dictionary = pairs[k][1]
		var r: Dictionary = sim.relations._rel_w(x, y)
		r["aff"] = 60.0 + 5.0 * k
		r["att"] = 75.0
		r["status"] = statuses[k]
		r["since"] = now - 6000 * (k + 1)
		r["talks"] = 25
		sim.relations._bump()
		if statuses[k] != "dating":
			sim.families.on_partners(x, y)
	var kids := 0
	for k in mini(4, pairs.size()):
		var x2: Dictionary = pairs[k][0]
		var y2: Dictionary = pairs[k][1]
		var n: int = 2 if k < 2 else 1
		for c in n:
			if kids >= 6:
				break
			var ch: Dictionary = sim.families.spawn_child([int(x2["id"]), int(y2["id"])], x2["pos"], int(x2["bld"]) if x2["where"] == "in" else -1)
			if x2["where"] != "in":
				H.put_inside(sim, ch, int(lander["id"]))
			# Some have been here a while (SET-UP).
			ch["child_at"] = now - 6000 * (3 + 4 * c + 2 * k)
			kids += 1
	print("couples %d, children %d, officers %d" % [pairs.size(), kids, officers])
	# ---- staff for the dome and the shop: SIM's proposal (every 30 s) plus the stock hauled in.
	H.fill_utilities(sim, 1.0, 0.9, true)
	var d := 0.0
	while d < days:
		for k in 12:
			sim.run_seconds(50.0)
			H.fill_utilities(sim, 1.0, 0.9, true)
		d += 1.0
		var dead := 0
		for a in sim.state["agents"].values():
			if a["state"] == "dead":
				dead += 1
		print("day %.1f: %d people, %d dead, unrest %.1f %s, issues %d" % [sim.seconds() / 600.0, sim.alive_count(), dead, float(sim.unrest.info(-1)["value"]), sim.unrest.info(-1)["stage"], sim.state["v5"].get("rag", {}).size()])
		if d >= days - 1.0 and not pad.is_empty():
			# Tourists for the dome: a liner lands before the save (debug command traffic_now).
			if sim.traffic.ships().is_empty() and sim.traffic.forecast().is_empty():
				_cmd("traffic_now", {"kind": "liner", "in": 30.0})
	# The affair (SET-UP at the end, so that it is not found out before the save): the dating partner
	# of pair 4 and somebody else.
	now = int(sim.state["tick"])
	if pairs.size() >= 5:
		var cheat: Dictionary = pairs[4][0]
		for a in ppl:
			if a["state"] == "alive" and int(a["id"]) != int(cheat["id"]) and int(a["id"]) != int(pairs[4][1]["id"]) and sim.social.compatible(cheat, a) and sim.relations.partner_of(int(a["id"])) == -1 and String(a["role"]) != "security":
				var ra: Dictionary = sim.relations._rel_w(cheat, a)
				ra["aff"] = 40.0
				ra["att"] = 85.0
				ra["status"] = "affair"
				ra["since"] = now
				ra["talks"] = 12
				sim.relations._bump()
				break
	# ---- students and a prisoner (SET-UP at the end).
	if not academy.is_empty():
		var n_enrol := 0
		for a in _colonists():
			if n_enrol >= 3:
				break
			if String(a["role"]) == "security" or a.has("job"):
				continue
			if bool(_cmd("enrol", {"agent": int(a["id"]), "skill": "leadership", "building": int(academy["id"])}).get("ok", false)):
				n_enrol += 1
	var worst: Dictionary = {}
	var wv := 1e9
	for a in _colonists():
		var att: float = float(sim.people.rec_of(int(a["id"])).get("att", 0.0))
		if att < wv and String(a["role"]) != "security":
			wv = att
			worst = a
	if not worst.is_empty():
		_cmd("discipline", {"agent": int(worst["id"]), "action": "jail", "days": 3.0})
	# Unrest stays calm (the orchestrator's brief for this save: "calm unrest").
	var causes := {}
	for a in sim.state["agents"].values():
		if a["state"] == "dead":
			causes[String(a.get("cause", ""))] = int(causes.get(String(a.get("cause", "")), 0)) + 1
	print("deaths: %s" % str(causes))
	var died: int = 0
	for c in causes.values():
		died += int(c)
	died -= dead0
	H.fill_utilities(sim, 1.0, 0.9, true)
	sim.state["flags"]["unlock_all"] = false
	sim.state["options"]["debug"] = false
	var people := 0
	var children := 0
	for a in sim.state["agents"].values():
		if a["state"] == "alive":
			people += 1
			if String(a.get("kind", "")) == "child":
				children += 1
	var audit: Dictionary = sim.inv.audit()
	print("save: %d people (%d children), unrest %.1f %s, issues %d, ledger %s" % [people, children, float(sim.unrest.info(-1)["value"]), sim.unrest.info(-1)["stage"], sim.state["v5"].get("rag", {}).size(), str(audit)])
	var bytes: PackedByteArray = Persistence.encode(sim.state)
	var f := FileAccess.open("res://content/saves/showcase_v5.fhsave", FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	print("wrote content/saves/showcase_v5.fhsave (%d bytes)" % bytes.size())
	sim.dispose()
	if died > 0:
		print("FAILED: %d died while the save was built" % died)
	quit(0 if audit.is_empty() and died == 0 else 1)
