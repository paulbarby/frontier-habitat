extends RefCounted
## The long runs: acceptance 13 (a twenty-person settlement for ten days) and the
## behaviour the player reported (building stops after four or five days).
## These take about a minute each, so they live in their own suite.

const H = preload("res://tests/helpers.gd")

func tests() -> Array:
	return [
		["a13_twenty_colonists_ten_days", a13_sustainable],
		["u02_building_still_works_after_day_five", u02_late_building],
		["a15_performance_ticks_per_second", a15_performance],
		["long_campaign_chapters_seed_1001", long_campaign],
		["long_perf_60_colonists_150_structures", long_perf],
	]

## The size the design names for the tick budget: 60 colonists and 150 structures.
## The reference colony at day 12 is grown by test set-up: extra structures placed at once
## and settlers admitted. The number printed is this machine's; the web build is slower.
func long_perf(t) -> void:
	var g = _full_game(1001)
	var sim = g.sim
	g.run_to_tick(12 * 6000)
	sim.state["flags"]["unlock_all"] = true                # test set-up
	var errors: Array = []
	var y := -110
	while sim.state["buildings"].size() < 150 and y <= 110:
		var x := -110
		while sim.state["buildings"].size() < 150 and x <= 110:
			var off := Vector2(x, y)
			if off.length() > 70.0:
				var def_id: String = "solar_array" if (x + y) % 2 == 0 else "battery"
				var pos: Vector2 = sim.place.snap_pos(sim.world.center + off)
				if sim.place.check_building(def_id, pos, 0.0) == "ok":
					sim.build.spawn_active(def_id, pos, 0.0)   # test set-up
			x += 9
		y += 9
	for i in 4:
		g.cmd("admit_settlers", {"count": 12})
	g.run(600)
	var pop: int = sim.alive_count()
	var n: int = sim.state["buildings"].size()
	var t0: int = Time.get_ticks_usec()
	g.run(3000)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / 3000.0
	t.check(pop >= 60 and n >= 150, "the colony has the size of the budget (%d people, %d structures)" % [pop, n])
	t.check(ms < 3.0, "a tick takes less than 3 ms on this machine (%.3f ms)" % ms)
	t.eq(sim.inv.audit(), {}, "ledger")
	t.note("%.3f ms per tick with %d colonists and %d structures (%s)" % [ms, pop, n, OS.get_processor_name()])
	t.done()

# ---------------------------------------------------------------- version 2 campaign
## The full reference campaign (docs/AAA_DESIGN.md SIM item 10): research, sizes,
## upgrades, several crops and dishes, industry, a forward airlock and the Meridian.
## It must reach chapter 4 and finish the survey and the hull by about day 25, with no
## death from starvation or thirst, and the ledger must balance every day.
## The day each chapter completes is printed on the result line.
func long_campaign(t) -> void:
	var g = _full_game(1001)
	var sim = g.sim
	var t0: int = Time.get_ticks_msec()
	var chapter_day := {}
	var goal_day := {}
	var bad_days: Array = []
	var day := 0
	var hull_day := -1.0
	while day < 30:
		day += 1
		g.run_to_tick(day * 6000)
		if not sim.inv.audit().is_empty():
			bad_days.append("day %d ledger %s" % [day, str(sim.inv.audit())])
		var p: Array = H.inventory_problems(sim)
		if not p.is_empty():
			bad_days.append("day %d: %s" % [day, p[0]])
		var u: Array = H.utility_problems(sim)
		if not u.is_empty():
			bad_days.append("day %d: %s" % [day, u[0]])
		for gid in sim.state["goals"]["status"]:
			var gs: Dictionary = sim.state["goals"]["status"][gid]
			if gs["state"] == "done" and not goal_day.has(gid):
				goal_day[gid] = float(int(gs["done_tick"])) / 6000.0 + 1.0
		for i in sim.goals.chapter():
			if not chapter_day.has(i + 1):
				chapter_day[i + 1] = day
		if int(sim.state["ship"]["stage"]) >= 2 and hull_day < 0.0:
			hull_day = float(goal_day.get("ship_hull", day))
		if hull_day > 0.0 and day >= 26:
			break
	var causes := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "dead":
			causes[a["cause"]] = int(causes.get(a["cause"], 0)) + 1
	t.eq(bad_days, [], "ledger, reservations and utility stocks sound every day")
	t.check(not causes.has("starvation") and not causes.has("dehydration"), "no death from starvation or thirst: %s" % str(causes))
	t.check(sim.goals.chapter() >= 3, "chapter 4 (the Meridian) is open (chapter %d)" % (sim.goals.chapter() + 1))
	t.check(goal_day.has("ship_survey"), "the wreck was surveyed")
	t.check(hull_day > 0.0 and hull_day <= 27.0, "the hull was patched by about day 25 (day %.1f)" % hull_day)
	t.eq(H.refused_commands(sim), [], "every reference command was accepted")
	var parts: Array = []
	for i in range(1, 6):
		if chapter_day.has(i):
			parts.append("ch%d done day %d" % [i, chapter_day[i]])
	for gid in ["balanced_diet", "food_supply", "iron_will", "silicon_age", "growing", "first_upgrade", "ship_survey", "ship_hull"]:
		if goal_day.has(gid):
			parts.append("%s %.1f" % [gid, float(goal_day[gid])])
	t.note(", ".join(parts))
	var col: Dictionary = sim.nutrition.colony()
	var n_def := 0
	var n_fed := 0
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		if ag["state"] == "alive":
			if not sim.nutrition.deficient(ag).is_empty():
				n_def += 1
			if sim.nutrition.well_fed(ag):
				n_fed += 1
	t.note("nutrition score %.1f (P%.0f C%.0f F%.0f V%.0f), %d with a deficiency, %d well fed" % [float(col["score"]), float(col["protein"]), float(col["carbs"]), float(col["fat"]), float(col["vitamins"]), n_def, n_fed])
	t.note("%d alive, %d deaths %s, %d techs, %d structures, %.2f ms per tick with the driver" % [sim.alive_count(), int(sim.state["progress"]["deaths"]), str(causes), sim.research.done_count(), sim.state["buildings"].size(), float(Time.get_ticks_msec() - t0) / float(maxi(1, g.tick()))])
	t.done()

## The full reference colony: the opening layout plus the phase-4 additions and settlers.
func _full_game(seed_value: int):
	var g = H.Game.new(seed_value, false)
	g.ref = H.Reference.new(g.sim, "all")
	return g

# ---------------------------------------------------------------- 13
func a13_sustainable(t) -> void:
	var g = _full_game(1001)
	var worst_meals := 999
	var worst_water := 999.0
	var deaths_seen := 0
	for day in 13:
		g.run_to_tick((day + 1) * 6000)
		var f: Dictionary = g.sim.metrics.forecast()
		t.eq(g.sim.inv.audit(), {}, "day %d: ledger" % (day + 1))
		t.eq(H.inventory_problems(g.sim), [], "day %d: reservations" % (day + 1))
		t.eq(H.utility_problems(g.sim), [], "day %d: utility stocks" % (day + 1))
		if day >= 6:
			worst_meals = mini(worst_meals, int(f["meals"]))
			worst_water = minf(worst_water, float(f["water"]))
		deaths_seen = int(g.sim.state["progress"]["deaths"])
	var f2: Dictionary = g.sim.metrics.forecast()
	t.eq(deaths_seen, 0, "no deaths in thirteen days")
	t.check(int(f2["pop"]) >= 20, "at least twenty colonists live here (%d)" % int(f2["pop"]))
	t.check(worst_meals > 0, "meals never ran out after day 7 (lowest %d)" % worst_meals)
	t.check(worst_water > 0.0, "water never ran out after day 7 (lowest %.0f)" % worst_water)
	t.check(int(g.sim.state["metrics"]["produced"].get("metal", 0)) > 0, "the colony refined its own metal")
	t.check(int(g.sim.state["progress"]["stage"]) >= 2, "it reached the Growing settlement stage (%d)" % int(g.sim.state["progress"]["stage"]))
	t.eq(H.refused_commands(g.sim), [], "every reference command was accepted")
	t.note("%d people, %d meals, %.0f water, stage %d" % [int(f2["pop"]), int(f2["meals"]), float(f2["water"]), int(g.sim.state["progress"]["stage"])])
	t.done()

# ---------------------------------------------------------------- reported by the player
## On day 6 the player plans structures on the far side of the station. Each one must
## either be built or show a reason. The report was: no building and no reason.
func u02_late_building(t) -> void:
	var g = _full_game(1002)
	g.run_to_tick(6 * 6000)
	var before: int = H.buildings_of(g.sim, "solar_array", true).size()
	var ctr: Vector2 = g.sim.world.center
	var placed: Array = []
	for off in [Vector2(-34, 26), Vector2(-40, -30), Vector2(52, 30)]:
		for slide in range(0, 26, 2):
			var p: Vector2 = ctr + off + Vector2(slide, slide) * 0.4
			if g.sim.place.check_building("solar_array", p, 0.0) == "ok":
				var r: Dictionary = g.cmd("place_building", {"def": "solar_array", "x": p.x, "y": p.y, "rot": 0.0})
				if r["ok"]:
					placed.append(int(r["id"]))
					break
	if not t.check(placed.size() >= 2, "far plans were placed (%d)" % placed.size()):
		t.done()
		return
	# Nothing may sit still without a reason: either work happens or the player is told.
	var silent := 0
	for s in 400:
		g.run(10)
		for id in placed:
			if not g.sim.state["buildings"].has(id):
				continue
			var b: Dictionary = g.sim.state["buildings"][id]
			if b["state"] == "active":
				continue
			# "" is only honest while work or a delivery is actually on its way.
			if String(b["block"]) == "" and not _busy(g.sim, b) and s > 30:
				silent += 1
	t.eq(silent, 0, "a stopped plan always shows a reason")
	# Each plan must end in one of two honest states: finished, or stopped with a reason.
	g.run(20000)
	var unfinished := 0
	var without_reason := 0
	for id in placed:
		if not g.sim.state["buildings"].has(id):
			continue
		var b: Dictionary = g.sim.state["buildings"][id]
		if b["state"] == "active":
			continue
		unfinished += 1
		if String(b["block"]) == "" and not _busy(g.sim, b):
			without_reason += 1
	var done: bool = without_reason == 0 and unfinished < placed.size()
	var reasons: Array = []
	for id in placed:
		if g.sim.state["buildings"].has(id):
			var b: Dictionary = g.sim.state["buildings"][id]
			reasons.append("%s: %s '%s'" % [b["name"], b["state"], b["block"]])
	t.eq(without_reason, 0, "no plan is stopped without a reason: %s" % str(reasons))
	t.check(done, "the plans within reach were built: %s" % str(reasons))
	t.check(H.buildings_of(g.sim, "solar_array", true).size() > before, "new arrays are working")
	t.eq(g.sim.inv.audit(), {}, "ledger")
	t.note("finished on day %d" % (int(g.tick() / 6000) + 1))
	t.done()

## Work is really happening on this plan: progress, materials on site, or a carrier on the way.
static func _busy(sim, b: Dictionary) -> bool:
	if float(b["progress"]) > 0.0:
		return true
	if int(b["inv_site"]) != -1 and sim.inv.total(b["inv_site"]) > 0:
		return true
	for hid in sim.state["holds"]:
		if int(sim.state["holds"][hid]["inv"]) == int(b["inv_site"]):
			return true
	for tid in sim.state["tasks"]:
		if int(sim.state["tasks"][tid]["bld"]) == int(b["id"]):
			return true
	return false

# ---------------------------------------------------------------- 15
func a15_performance(t) -> void:
	var g = _full_game(1001)
	g.run_to_tick(8 * 6000)
	var pop: int = g.sim.alive_count()
	var blds: int = g.sim.state["buildings"].size()
	var t0: int = Time.get_ticks_msec()
	g.run(3000)
	var ms: float = float(Time.get_ticks_msec() - t0)
	var per_tick: float = ms / 3000.0
	t.check(per_tick < 100.0, "one tick takes less than 100 ms (%.2f ms)" % per_tick)
	t.note("%.2f ms per tick with %d colonists and %d structures; %.0f ticks/s, real-time needs 10" % [per_tick, pop, blds, 1000.0 / maxf(per_tick, 0.001)])
	t.note("this machine only: %s" % OS.get_processor_name())
	t.done()
