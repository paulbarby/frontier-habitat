extends RefCounted
## The authoritative simulation (spec 13). It has no scene, no node and no rendering, so
## it runs headless for tests. Presentation and interface READ `state` and the derived
## stats, and change things only through submit(). `state` is plain data: Dictionaries,
## Arrays, numbers, strings and Vector2, so it saves and hashes exactly.
##
## Fixed step: 10 Hz. Order inside one tick (spec 5): commands, environment, topology,
## power, water and air, needs, construction flow + upgrades + ship + task board,
## decisions, airlocks, movement and work, crops, automatic machines, spoilage, wear,
## morale, research, alerts, metrics, goals, awards. Ties resolve by entity id, because
## every dictionary is filled in ascending id order.
##
## Read-only helpers for the interface (docs/AAA_DESIGN.md section 10):
##   sim.sizes.def_for(def_id, size), sim.sizes.allowed(def_id, size)
##   sim.upgrades.check(b), sim.research.state_of(tech), sim.research.rp_rate()
##   sim.goals.chapter(), sim.goals.list(), sim.awards.list()
##   sim.nutrition.colony(), sim.metrics.series(name), sim.items.info(id), sim.ship.info()
##   sim.bd(b): the effective definition of a building record (size and level applied)

const Rng = preload("res://sim/rng.gd")
const Content = preload("res://sim/content.gd")
const WorldGen = preload("res://sim/world_gen.gd")
const InventorySys = preload("res://sim/inventory.gd")
const Topology = preload("res://sim/topology.gd")
const Nav = preload("res://sim/nav.gd")
const NavV4 = preload("res://sim/nav_v4.gd")
const Placement = preload("res://sim/placement.gd")
const Construction = preload("res://sim/construction.gd")
const Utilities = preload("res://sim/utilities.gd")
const Production = preload("res://sim/production.gd")
const Jobs = preload("res://sim/jobs.gd")
const Agents = preload("res://sim/agents.gd")
const Alerts = preload("res://sim/alerts.gd")
const Metrics = preload("res://sim/metrics.gd")
const Commands = preload("res://sim/commands.gd")
const Persistence = preload("res://sim/persistence.gd")
const Items = preload("res://sim/items.gd")
const Sizes = preload("res://sim/sizes.gd")
const Upgrades = preload("res://sim/upgrades.gd")
const Research = preload("res://sim/research.gd")
const Nutrition = preload("res://sim/nutrition.gd")
const Goals = preload("res://sim/goals.gd")
const Awards = preload("res://sim/awards.gd")
const Ship = preload("res://sim/ship.gd")
const Events = preload("res://sim/events.gd")
const Hazards = preload("res://sim/hazards.gd")
const Traffic = preload("res://sim/traffic.gd")
const Bases = preload("res://sim/bases.gd")
const Vehicles = preload("res://sim/vehicles.gd")
const Orders = preload("res://sim/orders.gd")
const DebugCmds = preload("res://sim/debug_cmds.gd")
const Reactors = preload("res://sim/reactors.gd")
const Explore = preload("res://sim/explore.gd")
const People = preload("res://sim/people.gd")
const Social = preload("res://sim/social.gd")
const Ranks = preload("res://sim/ranks.gd")
const Discipline = preload("res://sim/discipline.gd")
const Unrest = preload("res://sim/unrest.gd")
const Education = preload("res://sim/education.gd")
const Housing = preload("res://sim/housing.gd")
const Relations = preload("res://sim/relations.gd")
const Floors = preload("res://sim/floors.gd")
const Security = preload("res://sim/security.gd")
const Leisure = preload("res://sim/leisure.gd")
const Families = preload("res://sim/families.gd")
const Rag = preload("res://sim/rag.gd")
const Eggs = preload("res://sim/eggs.gd")
const Text = preload("res://sim/text.gd")

static var _content_cache := {}

var content: Dictionary
var bal: Dictionary
var planet: Dictionary
var state: Dictionary
var world
var inv
var inventory      # the same object as inv (the UI's name for it)
var topo
var nav
var place
var build
var util
var prod
var jobs
var agents
var alerts
var metrics
var cmds
var items
var sizes
var upgrades
var research
var nutrition
var goals
var awards
var ship
var events
var hazards
var traffic
var bases
var vehicles
var orders
var debug
var reactors
var explore
var people
var social
var ranks
var discipline
var unrest
var education
var housing
var relations
var floors
var security
var leisure
var families
var rag
var eggs
var pending: Array = []
var _cmd_seq := 0
var _alive_tick := -1
var _alive_n := -1

func _init() -> void:
	if _content_cache.is_empty():
		_content_cache = Content.load_all()
	content = _content_cache
	bal = content["balance"]
	inv = InventorySys.new(self)
	inventory = inv
	topo = Topology.new(self)
	nav = Nav.new(self)
	place = Placement.new(self)
	build = Construction.new(self)
	util = Utilities.new(self)
	prod = Production.new(self)
	jobs = Jobs.new(self)
	agents = Agents.new(self)
	alerts = Alerts.new(self)
	metrics = Metrics.new(self)
	cmds = Commands.new(self)
	items = Items.new(self)
	sizes = Sizes.new(self)
	upgrades = Upgrades.new(self)
	research = Research.new(self)
	nutrition = Nutrition.new(self)
	goals = Goals.new(self)
	awards = Awards.new(self)
	ship = Ship.new(self)
	events = Events.new(self)
	hazards = Hazards.new(self)
	traffic = Traffic.new(self)
	bases = Bases.new(self)
	vehicles = Vehicles.new(self)
	orders = Orders.new(self)
	debug = DebugCmds.new(self)
	reactors = Reactors.new(self)
	explore = Explore.new(self)
	people = People.new(self)
	social = Social.new(self)
	ranks = Ranks.new(self)
	discipline = Discipline.new(self)
	unrest = Unrest.new(self)
	education = Education.new(self)
	housing = Housing.new(self)
	relations = Relations.new(self)
	floors = Floors.new(self)
	security = Security.new(self)
	leisure = Leisure.new(self)
	families = Families.new(self)
	rag = Rag.new(self)
	eggs = Eggs.new(self)

## Breaks the reference cycles between the systems and this object.
func dispose() -> void:
	for s in [inv, topo, nav, place, build, util, prod, jobs, agents, alerts, metrics, cmds,
			items, sizes, upgrades, research, nutrition, goals, awards, ship, events, hazards, traffic, bases, vehicles, orders, debug, reactors, explore, people, social, floors, ranks, discipline, unrest, education, housing, relations, security, leisure, families, rag, eggs]:
		if s != null:
			s.sim = null
	inv = null
	inventory = null
	topo = null
	nav = null

# ---------------------------------------------------------------- start / load
## options: {planet: "dry"|"cold"|"airless", difficulty: "relaxed"|"standard"|"hard",
##           hazards: "off"|"mild"|"normal"|"hard" (default normal), storms: bool,
##           debug: bool (allows the hazard_now command; boot param debug=1)}.
## Without options the scenario's planet and the standard difficulty are used.
func new_game(seed_value: int, scenario_id: String = "tutorial", options: Dictionary = {}) -> void:
	var sc: Dictionary = content["scenarios"][scenario_id]
	var planet_id: String = String(options.get("planet", sc["planet"]))
	if not content["planets"].has(planet_id):
		planet_id = String(sc["planet"])
	var diff: String = String(options.get("difficulty", "standard"))
	if not bal["difficulty"].has(diff):
		diff = "standard"
	planet = content["planets"][planet_id]
	var spoil: bool = bool(bal["difficulty"][diff].get("spoilage", true)) and bool(bal["spoilage"].get("enabled", true))
	state = {
		"schema": Persistence.SCHEMA, "seed": seed_value, "scenario": scenario_id, "planet": planet_id,
		"tick": 0, "next_id": 1, "topo_dirty": false,
		"rng": {
			"weather": Rng.stream_seed(seed_value, 1), "hazard": Rng.stream_seed(seed_value, 2),
			"arrivals": Rng.stream_seed(seed_value, 3), "names": Rng.stream_seed(seed_value, 4),
		},
		"buildings": {}, "inventories": {}, "holds": {}, "agents": {}, "tasks": {},
		"deposits": [], "counters": {}, "ledger": {},
		"policies": {"priority": bal["default_priority"].duplicate(), "power_order": bal["power_class_order"].duplicate(), "pop_cap": 100,
			"immigration": default_immigration()},
		"env": {"sun": 0.0, "wind": 0.0, "wind_raw": float(planet["wind_avg"]), "wind_target": float(planet["wind_avg"]), "solar_mult": 1.0, "speed_mult": 1.0},
		"issues": {}, "log": [], "commands": [], "events": {},
		"metrics": {"history": [], "produced": {}, "tasks_done": {}, "series": {}, "daily": []},
		"progress": {"stage": 0, "tutorial_step": 0, "deaths": 0, "last_death_tick": -1, "safe_ticks": 0, "lost": false},
		"flags": {"base_air": false},
		"rev": {"walk": 0, "power": 0, "atmo": 0},
		"lander_id": -1, "names_used": 0,
		"options": {"planet": planet_id, "difficulty": diff, "spoilage": spoil, "storms": bool(options.get("storms", true)),
			"hazards": _hazard_setting(options), "debug": bool(options.get("debug", false))},
		"hazards": Hazards.fresh_state(),
		"traffic": Traffic.fresh_state(),
		"bases": Bases.fresh_state(),
		"credits": Traffic.fresh_credits(int(content["trade"].get("start_credits", 0))),
		"research": Research.fresh_state(),
		"goals": Goals.fresh_state(),
		"awards": {}, "award_track": {},
		"ship": Ship.fresh_state(),
		"stats": fresh_stats(),
	}
	# options.map_size (tests, tools) overrides the scenario's map: 256, 810 or 2560 (v4).
	# V4 rules (bigger rooms, faster walking, longer suits): new games only.
	state["rules"] = 4
	bal = content["balance"]
	state["map_size"] = int(options.get("map_size", sc["map_size"]))
	world = WorldGen.get_world(seed_value, planet, bal, int(state["map_size"]), content["terrain_v4"])
	_pick_nav()
	var known_r: float = float(content["terrain_v4"].get("known_radius", 300.0))
	for d in world.deposit_sites:
		var dep: Dictionary = d.duplicate()
		dep["id"] = new_id()
		# V4: on the v4 map a deposit is known near the start and after a survey (fog, finds).
		dep["surveyed"] = int(world.version) < 4 or Vector2(d["x"], d["y"]).distance_to(world.center) <= known_r
		state["deposits"].append(dep)
	var lander: Dictionary = build.spawn_active("lander", world.center, 0.0)
	lander["name"] = "Lander"
	state["lander_id"] = lander["id"]
	var cargo_mult: float = difficulty("cargo_mult")
	for res in sc["lander_cargo"]:
		inv.add_new_forced(lander["inv_out"], res, maxi(0, int(round(float(sc["lander_cargo"][res]) * cargo_mult))), "scenario")
	ship.place_initial()
	bases.ensure_first()
	topo.rebuild(true)
	# V4 milestone 7: fog of war and points of interest (v4 map only).
	explore.setup()
	if nav.has_method("prewarm"):
		nav.prewarm()
	var i := 0
	for role in sc["colonists"]:
		var a: Dictionary = agents.spawn(role, next_name(), nav.slot_pos(lander, i), lander["id"])
		a["bed"] = lander["id"]
		# Staggered tiredness: the crew never sleeps all at once.
		a["fatigue"] = 4.0 + 6.0 * i
		i += 1
	goals.tick_second()
	log_event("landed", "The lander is down. %s, shelter for %s." % [Text.n(i, "colonist"), Text.n(int(bdef("lander")["shelter_days"]), "day")], [lander["id"]], 1)

## Does the planet have an atmosphere (V5 section 15.7)? content planets.<id>.atmosphere: "none" on the
## airless world.
func planet_has_air() -> bool:
	return String(planet.get("atmosphere", "thin")) != "none"

## Is a deposit known to the colony (surveyed)? Saves before V4 know every deposit.
static func deposit_known(d: Dictionary) -> bool:
	return bool(d.get("surveyed", true))

## Test tools: no structure is built, finished or removed while on (saved in options).
func set_freeze_build(on: bool) -> void:
	if not state.has("options"):
		state["options"] = {}
	state["options"]["freeze_build"] = on

## The balance of a game saved before V4: balance.json with the legacy_v3 values on top
## (made once, shared, never written).
static var _legacy_bal := {}

## V4 food margin: settlers land with their own ration meals (balance.settler_meals each; 0 in
## saves from before V4). The meals are a ground pile at the landing place; carriers store them.
func settler_supplies(count: int, at: Vector2) -> void:
	var n: int = int(bal.get("settler_meals", 0)) * count
	if n <= 0:
		return
	var q = nav.nearest_walkable(at, 8)
	var pile: int = inv.create_inv("g", 0, "pile", 100000, place.clear_of_porches(q if q != null else at))
	inv.add_new_forced(pile, "meals", n, "settler_supplies")
	log_event("settler_supplies", "The settlers brought %d ration meals." % n, [], 0)

func legacy_balance() -> Dictionary:
	if _legacy_bal.is_empty():
		var b: Dictionary = content["balance"].duplicate(false)
		var leg: Dictionary = b.get("legacy_v3", {})
		for k in leg:
			b[k] = leg[k]
		_legacy_bal = b
	return _legacy_bal

## Radius of a corridor tube in metres (1.2 on older maps; terrain_v4 corridor_scale on the
## v4 map, 1.0 until the wider tubes go live).
func corridor_r() -> float:
	if world == null or int(world.version) < 4:
		return 1.2
	return 1.2 * float(content["terrain_v4"].get("corridor_scale", 1.25))

## The walking graph for the map: one fine grid (maps before version 4) or the hierarchical
## graph of the 2,560 m map (sim/nav_v4.gd).
func _pick_nav() -> void:
	var want_v4: bool = int(world.version) >= 4
	var is_v4: bool = nav != null and nav.get_script() == NavV4
	if want_v4 != is_v4 or nav == null:
		if nav != null:
			nav.sim = null
		nav = NavV4.new(self) if want_v4 else Nav.new(self)

func _hazard_setting(options: Dictionary) -> String:
	var hs: String = String(options.get("hazards", "normal"))
	return hs if bal["hazards"]["settings"].has(hs) else "normal"

static func fresh_stats() -> Dictionary:
	return {"produced": {}, "consumed": {}, "spoiled": {}, "cooked": {}, "eaten": {}, "spoiled_today": {},
		"cooked_total": 0, "harvests": 0, "heals": 0, "techs": 0, "upgrades": 0, "ship_stages": 0,
		"ship_runs": 0, "ship_maintenance": 0, "settlers": 0}

func default_immigration() -> Dictionary:
	return {"open": true, "roles": bal["roles"].duplicate(), "cap": 100}

## Installs a decoded save. Derived data is rebuilt without touching revision numbers,
## so a loaded game continues exactly like the game that was saved.
## opts: {debug: true} turns on state.options.debug (the hazard_now command) for a loaded
## save (boot params load= and debug=1). It is written into the state, so it is saved.
func load_state(s: Dictionary, opts: Dictionary = {}) -> void:
	state = s
	# The v5 people and social caches are derived from the old state.
	people.reset()
	social.reset()
	unrest.reset()
	relations.reset()
	security.reset()
	leisure.reset()
	if bool(opts.get("debug", false)):
		if not state.has("options"):
			state["options"] = {}
		state["options"]["debug"] = true
	var sc: Dictionary = content["scenarios"][state["scenario"]]
	planet = content["planets"][state["planet"]]
	# A save from before V4 keeps the v3 walking, carrying and suit numbers.
	bal = content["balance"] if int(state.get("rules", 3)) >= 4 else legacy_balance()
	# A version-2 save keeps its 256 m map (the migration writes map_size 256).
	world = WorldGen.get_world(int(state["seed"]), planet, bal, int(state.get("map_size", 256)), content["terrain_v4"])
	_pick_nav()
	pending = []
	# A version-1 save has no Meridian yet: it lands on the first free site (migration).
	if int(state["ship"].get("id", -1)) == -1:
		ship.place_initial()
		if bool(state["topo_dirty"]):
			topo.rebuild(true)
		else:
			topo.rebuild(false)
	else:
		topo.rebuild(false)
	# Saves before V4 have no bases: the first one is made round the lander (derived only
	# from the state, so the loaded game and a migrated game agree).
	bases.ensure_first()
	# V4 saves from before the fog get it here (landing area and the ground round the base).
	explore.ensure()
	if nav.has_method("prewarm"):
		nav.prewarm()
	# V5 15.7: an old save on an airless planet drops its pending atmospheric events.
	hazards.drop_atmospheric()
	# A rider saved outside the vehicle is put back aboard (vehicles.repair_crews).
	vehicles.repair_crews()
	# V5: a save from before schema 6 gets one commander a base, chosen by seniority.
	people.ensure_commanders()
	people.prewarm()
	util.power_stats = {}
	util.water_stats = {}
	util.atmo_stats = {}
	_prime_stats()

## The per-tick stats are derived. After a load they are recomputed from the state on a
## COPY of the stocks, so the state itself is not advanced.
func _prime_stats() -> void:
	var backup: Dictionary = state.duplicate(true)
	util.power_tick()
	util.water_tick()
	util.atmo_tick()
	var ps: Dictionary = util.power_stats
	var ws: Dictionary = util.water_stats
	var at: Dictionary = util.atmo_stats
	state = backup
	util.power_stats = ps
	util.water_stats = ws
	util.atmo_stats = at
	util.invalidate()

func save_bytes() -> PackedByteArray:
	return Persistence.encode(state)

# ---------------------------------------------------------------- helpers
func new_id() -> int:
	var id: int = int(state["next_id"])
	state["next_id"] = id + 1
	return id

## The base definition (size M, level 1). Use bd(b) for a building record.
func bdef(def_id: String) -> Dictionary:
	return content["buildings"][def_id]

## The effective definition of a building record: its size and level applied.
func bd(b: Dictionary) -> Dictionary:
	return sizes.eff(b["def"], int(b.get("size", 1)), int(b.get("level", 1)))

func unlocked_all() -> bool:
	return bool(state["flags"].get("unlock_all", false))

## A difficulty multiplier (cargo_mult, need_mult, research_mult, wear_mult).
func difficulty(key: String) -> float:
	var d: String = String(state.get("options", {}).get("difficulty", "standard"))
	return float(bal["difficulty"].get(d, {}).get(key, 1.0))

## Lifetime counters: stat_add("harvests", "", 1) or stat_add("produced", "metal", 2).
func stat_add(key: String, item: String, n: int) -> void:
	var st: Dictionary = state["stats"]
	if item == "":
		st[key] = int(st.get(key, 0)) + n
		return
	if not st.has(key):
		st[key] = {}
	st[key][item] = int(st[key].get(item, 0)) + n

## Counts new units made by the colony (production, harvests, machines) in both the old
## metrics.produced table and state.stats.produced.
func count_produced(item: String, n: int) -> void:
	var mp: Dictionary = state["metrics"]["produced"]
	mp[item] = int(mp.get(item, 0)) + n
	stat_add("produced", item, n)

## Living colonists. Counted once per tick (a death later in the same tick shows from
## the next tick on, the same way in a saved and a continued game).
func alive_count() -> int:
	var tick: int = int(state["tick"])
	if tick == _alive_tick and _alive_n >= 0:
		return _alive_n
	# Colonists only: visitors (V3.1, agent.kind "visitor") are not part of the colony.
	var n := 0
	var v := 0
	for aid in state["agents"]:
		var a: Dictionary = state["agents"][aid]
		if a["state"] == "alive":
			if a["kind"] != "visitor":
				n += 1
			else:
				v += 1
	_alive_tick = tick
	_alive_n = n
	_visitors_n = v
	return n

## Living visitors (V3.1), counted with alive_count(). They use air, water and food but are
## not part of the colony: no colony alert, goal, award or chart counts them.
var _visitors_n := 0

func visitor_count() -> int:
	alive_count()
	return _visitors_n

## True for a colonist, false for a visitor (V3.1).
static func is_colonist(a: Dictionary) -> bool:
	return a.get("kind", "") != "visitor"

## Forget the per-tick count (a colonist was added or removed during this tick).
func alive_changed() -> void:
	_alive_n = -1
	# V5: the id buckets of people.ids_mod are made again (an agent was added or removed).
	if people != null:
		people._bk_n = -1

func next_name() -> String:
	var names: Array = content["names"]
	var n: int = int(state["names_used"])
	state["names_used"] = n + 1
	var name: String = names[n % names.size()]
	if n >= names.size():
		name += " %d" % (n / names.size() + 1)
	return name

## extra: more fields for the entry (V4: "pos" [x, y] and "def" of an explosion).
func log_event(code: String, text: String, entities: Array, sev: int = 1, extra: Dictionary = {}) -> void:
	var log: Array = state["log"]
	var e := {"tick": int(state["tick"]), "code": code, "text": text, "ents": entities.duplicate(), "sev": sev}
	for k in extra:
		e[k] = extra[k]
	log.append(e)
	# V5: social events also go to the social log (the Rag's source; sim/rag.gd).
	if rag != null:
		rag.from_log(code, text, entities, extra)
	var cap: int = int(bal["log_max_entries"])
	while log.size() > cap:
		log.pop_front()

func submit(kind: String, payload: Dictionary) -> int:
	# The sequence number lives in the state, so a loaded game numbers its next command
	# exactly like the game that was saved (replay rule, spec 14).
	_cmd_seq = int(state.get("cmd_seq", 0)) + 1
	state["cmd_seq"] = _cmd_seq
	pending.append({"id": _cmd_seq, "kind": kind, "payload": payload.duplicate(true)})
	return _cmd_seq

func seconds() -> float:
	return float(state["tick"]) / float(bal["tick_hz"])

# ---------------------------------------------------------------- the tick
func step() -> void:
	state["tick"] = int(state["tick"]) + 1
	var tick: int = int(state["tick"])
	# The once-a-second work is spread over the ticks of the second (V5 budget: no tick over
	# 12 ms). Each system keeps a period of one second; only its phase differs. Systems that
	# test "tick % (N * tick_hz) == 0" inside keep phase 0.
	var hz: int = int(bal["tick_hz"])
	var phase: int = tick % hz
	cmds.apply_pending()
	util.env_tick()
	if phase == 0:
		hazards.tick_second()
		traffic.tick_second()
	if bool(state["topo_dirty"]):
		topo.rebuild(true)
	util.power_tick()
	util.water_tick()
	util.atmo_tick()
	agents.needs_tick()
	if phase == _phase_of(1, hz):
		build.tick_second()
		upgrades.tick_second()
	if phase == _phase_of(2, hz):
		vehicles.tick_second()
		reactors.tick_second()
	if phase == _phase_of(3, hz):
		explore.tick_second()
		ship.tick_second()
	# The job board in three parts (jobs.gd tick_part: phases 4, 9 and 1).
	if phase == _phase_of(4, hz):
		jobs.tick_part(0)
	elif phase == _phase_of(9, hz):
		jobs.tick_part(1)
	elif phase == _phase_of(1, hz):
		jobs.tick_part(2)
	agents.think_tick()
	agents.locks_tick()
	agents.act_tick()
	vehicles.tick()
	ship.tick()
	if phase == _phase_of(5, hz):
		prod.crops_second()
		prod.auto_second()
		prod.spoil_second()
		prod.wear_second()
	# Morale in two halves (even and odd ids) on phases 6 and 7.
	if phase == _phase_of(6, hz):
		agents.morale_second(0)
	if phase == _phase_of(7, hz):
		agents.morale_second(1)
		research.tick_second()
		goals.tick_second()
		awards.tick_second()
	# Alerts every second tick of the clock (every 2 s): half the cost; raise and clear waits are 5 s and more.
	if phase == _phase_of(8, hz) and (tick / hz) % 2 == 0:
		alerts.tick_second()
	# V5: people (a slice a tick), courses and unrest (each base on its own tick).
	people.tick()
	relations.tick()
	education.tick()
	unrest.tick()
	rag.tick()
	if phase == _phase_of(9, hz):
		security.tick_second()
		leisure.tick_second()
		families.tick_second()
	if phase == 0:
		metrics.tick_second()

## The tick of the second on which a group of once-a-second systems runs (0 .. tick_hz - 1).
func _phase_of(k: int, hz: int) -> int:
	return k % hz

func run_seconds(secs: float) -> void:
	var n: int = int(secs * float(bal["tick_hz"]))
	for i in n:
		step()
