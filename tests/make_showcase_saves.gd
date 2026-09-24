extends SceneTree
## Writes the version-3 showcase saves (810 m map, hazards "normal") for the screenshots:
##   content/saves/showcase_v3_mid.fhsave    about day 12: lab, research assembler, industry,
##                                           several dishes, a level-3 and an L structure
##   content/saves/showcase_v3_late.fhsave   about day 24: 60-70 colonists, every room type,
##                                           a meteor turret, the forward airlock outpost at the
##                                           Meridian, a fragment site, a worn machine and a
##                                           breached corridor
##   node tools/godot.mjs script res://tests/make_showcase_saves.gd [seed] [late_day]
## The version-2 saves (showcase_early/mid/late/day9, 256 m map) were made by the v2 code and
## are kept as they are: this code cannot make a 256 m new game.
## Each file is written to a temporary name, checked by decoding it, then renamed.
##
## The late save is the reference campaign plus SET-UP (not play): missing room types, more
## habitats, power, air and a turret are placed finished (build.spawn_active, the call the
## scenario uses for the lander), one supply pod of rations and water cans is dropped (ledger
## reason "reward"), settlers are admitted in groups of 6, one meteor is sent with the debug
## command (debug is off again in the save), and right before the save one machine is set to
## 80 % of its failure threshold and one corridor is breached. The ledger stays {}.

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const Persistence = preload("res://sim/persistence.gd")
const H = preload("res://tests/helpers.gd")

const ROOM_TYPES := ["habitat", "lounge", "cantina", "medical", "bio_lab", "storehouse", "cold_storage",
	"kitchen", "greenhouse", "fungus_farm", "algae_bioreactor", "research_lab", "research_assembler",
	"mine", "refinery", "polymer_plant", "workshop", "glassworks", "electronics_fab", "fabricator",
	"oxygen_plant", "water_recycler", "atmo_processor", "airlock", "junction"]

func _init() -> void:
	var nums: Array = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_float():
			nums.append(float(a))
	var seed_value: int = int(nums[0]) if nums.size() > 0 else 1001
	var late_day: float = nums[1] if nums.size() > 1 else 24.0
	var sim = Sim.new()
	sim.new_game(seed_value, "tutorial", {"hazards": "normal"})
	var ref = Reference.new(sim, "all")
	var mid := false
	while true:
		ref.drive()
		sim.run_seconds(1.0)
		var day: float = sim.util.days_elapsed() + 1.0
		if not mid and ((day >= 12.0 and _mid_ready(sim)) or day >= 16.0):
			mid = _write(sim, "showcase_v3_mid")
		if day >= late_day and _calm(sim):
			break
		if day >= late_day + 3.0:
			break
	_grow(sim, ref)
	var guard := 0
	while not _calm(sim) and guard < 40:
		guard += 1
		ref.drive()
		sim.run_seconds(15.0)
	_final_touches(sim)
	_write(sim, "showcase_v3_late")
	_report(sim)
	print("audit: ", sim.inv.audit())
	quit(0)

## The mid save wants every feature of the middle game on screen.
func _mid_ready(sim) -> bool:
	var labs := false
	var industry := false
	var l3 := false
	var big := false
	var asm := false
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] != "active":
			continue
		labs = labs or b["def"] == "research_lab"
		asm = asm or b["def"] == "research_assembler"
		industry = industry or b["def"] in ["glassworks", "electronics_fab", "fabricator", "regolith_harvester"]
		l3 = l3 or int(b.get("level", 1)) >= 3
		big = big or (int(b.get("size", 1)) >= 2 and sim.bdef(b["def"]).has("sizes"))
	var dishes: int = (sim.state["stats"].get("cooked", {}) as Dictionary).size()
	return labs and asm and industry and l3 and big and dishes >= 3 and _calm(sim)

## No critical alert (severity 3) at this moment: a showcase must not open on an emergency.
static func _calm(sim) -> bool:
	for k in sim.state["issues"]:
		if int(sim.state["issues"][k]["severity"]) >= 3:
			return false
	return true

# ---------------------------------------------------------------- the late colony (set-up)
func _grow(sim, ref) -> void:
	var was_unlocked: bool = bool(sim.state["flags"].get("unlock_all", false))
	sim.state["flags"]["unlock_all"] = true
	# Air, power and beds for 70 people first.
	for def_size in [["habitat", 3], ["habitat", 3], ["oxygen_plant", 3], ["atmo_processor", 3], ["water_recycler", 2]]:
		_add_room(sim, def_size[0], def_size[1])
	for i in 4:
		_add_exterior(sim, "solar_array", 3, "battery")
	for i in 2:
		_add_exterior(sim, "battery", 3, "battery")
	_add_exterior(sim, "water_extractor", 2, "reservoir")
	_add_exterior(sim, "reservoir", 2, "water_extractor")
	# Every room type.
	for def_id in ROOM_TYPES:
		if H.buildings_of(sim, def_id, true).is_empty():
			if def_id == "mine":
				continue
			_add_room(sim, def_id, 1)
	_add_exterior(sim, "meteor_turret", 1, "battery")
	_add_exterior(sim, "comms_tower", 1, "battery")
	sim.state["flags"]["unlock_all"] = was_unlocked
	H.fill_utilities(sim, 1.0, 0.8, true)
	# Food and water for the newcomers: one supply pod (real units, ledger "reward").
	sim.goals.drop_pod({"meals": 160, "water": 60}, "reward")
	var g := 0
	while sim.alive_count() < 66 and g < 20:
		g += 1
		sim.submit("admit_settlers", {"count": mini(6, 66 - sim.alive_count())})
		for s in 45:
			ref.drive()
			sim.run_seconds(1.0)
	# A meteor that fell outside suit range: its crater and fragment pile stay.
	sim.state["options"]["debug"] = true
	var spot: Vector2 = _far_spot(sim, 190.0)
	sim.submit("hazard_now", {"kind": "meteor", "x": spot.x, "y": spot.y, "severity": 2})
	sim.run_seconds(5.0)
	sim.state["options"]["debug"] = false
	for s in 120:
		ref.drive()
		sim.run_seconds(1.0)

## One machine near its breakdown and one breached corridor, set right before the save.
func _final_touches(sim) -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["def"] == "refinery" and b["state"] == "active":
			var rec: Dictionary = sim.hazards.wear_of(int(id))
			rec["w"] = snappedf(float(rec["fail_at"]) * 0.8, 0.1)
			print("worn: %s wear %.1f of %.1f (%s fault)" % [b["name"], float(rec["w"]), float(rec["fail_at"]), rec["fault"]])
			break
	var best := -1
	for id in blds:
		var l: Dictionary = blds[id]
		if l["def"] == "corridor" and l["state"] == "active" and not bool(l.get("breach", false)):
			best = int(id)
	if best != -1:
		sim.hazards._breach(blds[best])
		print("breached: %s" % blds[best]["name"])

func _centre(sim) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["kind"] == "room" and b["state"] == "active":
			sum += b["pos"]
			n += 1
	return sum / float(maxi(1, n))

## A finished room joined by a corridor to the nearest room that takes one. Returns its id.
func _add_room(sim, def_id: String, size: int) -> int:
	var c: Vector2 = _centre(sim)
	for r in range(30, 130, 5):
		for k in 36:
			var p: Vector2 = sim.place.snap_pos(c + Vector2(float(r), 0).rotated(k * TAU / 36.0))
			if sim.place.check_building(def_id, p, 0.0, -1, size) != "ok":
				continue
			var partner: int = _link_partner(sim, p, def_id, size, "corridor")
			if partner == -1:
				continue
			var b: Dictionary = sim.build.spawn_active(def_id, p, 0.0, size)
			var errors: Array = []
			H.link_now(sim, "corridor", partner, int(b["id"]), errors)
			if not errors.is_empty():
				_remove(sim, b)
				continue
			print("added %s size %d at %s" % [b["name"], size, str(p - sim.world.center)])
			return int(b["id"])
	print("NO PLACE for ", def_id)
	return -1

## A finished exterior structure joined by a cable to the nearest `near_def` (or any powered one).
func _add_exterior(sim, def_id: String, size: int, near_def: String) -> int:
	var c: Vector2 = sim.world.center + Vector2(-20, -45)
	for r in range(0, 90, 4):
		for k in (1 if r == 0 else 24):
			var p: Vector2 = sim.place.snap_pos(c + Vector2(float(r), 0).rotated(k * TAU / 24.0))
			if sim.place.check_building(def_id, p, 0.0, -1, size) != "ok":
				continue
			var b: Dictionary = sim.build.spawn_active(def_id, p, 0.0, size)
			var best := -1
			var best_d := 1e18
			for id in sim.state["buildings"]:
				var o: Dictionary = sim.state["buildings"][id]
				if int(id) == int(b["id"]) or o["kind"] == "link" or o["state"] != "active" or o["def"] == "meridian" or o["def"] == "lander":
					continue
				if o["def"] != near_def and not sim.topo.power_comp.has(int(id)):
					continue
				var d: float = (o["pos"] as Vector2).distance_to(p) + (0.0 if o["def"] == near_def else 30.0)
				if d < best_d and sim.place.check_link("cable", int(id), int(b["id"]))["code"] == "ok":
					best_d = d
					best = int(id)
			if best == -1:
				_remove(sim, b)
				continue
			var errors: Array = []
			H.link_now(sim, "cable", best, int(b["id"]), errors)
			print("added %s size %d at %s" % [b["name"], size, str(p - sim.world.center)])
			return int(b["id"])
	print("NO PLACE for ", def_id)
	return -1

## A room of the colony that would accept a corridor to a room of this size at p.
func _link_partner(sim, p: Vector2, def_id: String, size: int, kind: String) -> int:
	var probe: Dictionary = sim.build.spawn_active(def_id, p, 0.0, size)
	var best := -1
	var best_d := 1e18
	for id in sim.state["buildings"]:
		var o: Dictionary = sim.state["buildings"][id]
		if int(id) == int(probe["id"]) or o["kind"] != "room" or o["state"] != "active":
			continue
		var d: float = (o["pos"] as Vector2).distance_to(p)
		if d < best_d and d < 40.0 and sim.place.check_link(kind, int(id), int(probe["id"]))["code"] == "ok":
			best_d = d
			best = int(id)
	_remove(sim, probe)
	return best

## Takes a finished structure away through the demolition path (inventories dissolve).
func _remove(sim, b: Dictionary) -> void:
	var n_log: int = (sim.state["log"] as Array).size()
	b["demolish"] = true
	b["progress"] = sim.build.demolish_work_total(b)
	sim.build._try_finish_demolition(b)
	# A set-up probe leaves no trace: no log line, no gap in the names.
	while (sim.state["log"] as Array).size() > n_log:
		(sim.state["log"] as Array).pop_back()
	var ctr: Dictionary = sim.state["counters"]
	ctr[b["def"]] = maxi(0, int(ctr.get(b["def"], 1)) - 1)

## Open ground `dist` metres from the lander, beyond suit range of every airlock.
func _far_spot(sim, dist: float) -> Vector2:
	for k in 24:
		var p: Vector2 = sim.world.center + Vector2(dist, 0).rotated(0.4 + k * TAU / 24.0)
		if sim.nav.is_walkable(p) and sim.agents.nearest_air_metres(p) > sim.agents.suit_reach_metres() + 20.0:
			return p
	return sim.world.center + Vector2(dist, 0)

func _report(sim) -> void:
	var have := {}
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "active":
			have[b["def"]] = true
	var missing: Array = []
	for d in ROOM_TYPES + ["meteor_turret"]:
		if not have.has(d):
			missing.append(d)
	print("late: %d alive, %d deaths, missing types %s, fragment sites %d, at risk %d, breached %s, sheltered %s" % [
		sim.alive_count(), int(sim.state["progress"]["deaths"]), str(missing), sim.hazards.sites().size(),
		sim.hazards.at_risk().size(), str(not (sim.state["hazards"]["breached"] as Array).is_empty()), str(sim.hazards.sheltered())])

func _write(sim, name: String) -> bool:
	var bytes: PackedByteArray = sim.save_bytes()
	var path := "res://content/saves/%s.fhsave" % name
	var tmp := "res://content/saves/%s.tmp.fhsave" % name
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		print("FAILED to write ", tmp)
		return false
	f.store_buffer(bytes)
	f.close()
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(tmp))
	if not dec["ok"]:
		print("FAILED to verify ", tmp, ": ", dec["error"])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	var final_abs: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(final_abs)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), final_abs)
	var f2: Dictionary = sim.metrics.forecast()
	var lv := 1
	var big := 1
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		lv = maxi(lv, int(b.get("level", 1)))
		if sim.bdef(b["def"]).has("sizes"):
			big = maxi(big, int(b.get("size", 1)))
	print("wrote %s: day %.2f, %d bytes, %d alive, %d deaths, %d structures, chapter %d, techs %d, max level %d, max size %d, ship stage %d, hazards %s, audit %s" % [
		final_abs, sim.util.days_elapsed() + 1.0, bytes.size(), f2["pop"], int(sim.state["progress"]["deaths"]),
		sim.state["buildings"].size(), sim.goals.chapter() + 1, sim.research.done_count(), lv, big,
		int(sim.state["ship"]["stage"]), str(sim.state["hazards"]["done_count"]), str(sim.inv.audit())])
	return true
