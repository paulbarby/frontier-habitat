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
const Text = preload("res://sim/text.gd")

static var _content_cache := {}

var content: Dictionary
var bal: Dictionary
var planet: Dictionary
var state: Dictionary
var world
var inv
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

## Breaks the reference cycles between the systems and this object.
func dispose() -> void:
	for s in [inv, topo, nav, place, build, util, prod, jobs, agents, alerts, metrics, cmds,
			items, sizes, upgrades, research, nutrition, goals, awards, ship, events]:
		if s != null:
			s.sim = null
	inv = null
	topo = null
	nav = null

# ---------------------------------------------------------------- start / load
## options: {planet: "dry"|"cold"|"airless", difficulty: "relaxed"|"standard"|"hard"}.
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
		"options": {"planet": planet_id, "difficulty": diff, "spoilage": spoil, "storms": bool(options.get("storms", true))},
		"research": Research.fresh_state(),
		"goals": Goals.fresh_state(),
		"awards": {}, "award_track": {},
		"ship": Ship.fresh_state(),
		"stats": fresh_stats(),
	}
	world = WorldGen.get_world(seed_value, planet, bal, int(sc["map_size"]))
	for d in world.deposit_sites:
		var dep: Dictionary = d.duplicate()
		dep["id"] = new_id()
		state["deposits"].append(dep)
	var lander: Dictionary = build.spawn_active("lander", world.center, 0.0)
	lander["name"] = "Lander"
	state["lander_id"] = lander["id"]
	var cargo_mult: float = difficulty("cargo_mult")
	for res in sc["lander_cargo"]:
		inv.add_new_forced(lander["inv_out"], res, maxi(0, int(round(float(sc["lander_cargo"][res]) * cargo_mult))), "scenario")
	ship.place_initial()
	topo.rebuild(true)
	var i := 0
	for role in sc["colonists"]:
		var a: Dictionary = agents.spawn(role, next_name(), nav.slot_pos(lander, i), lander["id"])
		a["bed"] = lander["id"]
		# Staggered tiredness: the crew never sleeps all at once.
		a["fatigue"] = 4.0 + 6.0 * i
		i += 1
	goals.tick_second()
	log_event("landed", "The lander is down. %s, shelter for %s." % [Text.n(i, "colonist"), Text.n(int(bdef("lander")["shelter_days"]), "day")], [lander["id"]], 1)

static func fresh_stats() -> Dictionary:
	return {"produced": {}, "consumed": {}, "spoiled": {}, "cooked": {}, "eaten": {}, "spoiled_today": {},
		"cooked_total": 0, "harvests": 0, "heals": 0, "techs": 0, "upgrades": 0, "ship_stages": 0,
		"ship_runs": 0, "ship_maintenance": 0, "settlers": 0}

func default_immigration() -> Dictionary:
	return {"open": true, "roles": bal["roles"].duplicate(), "cap": 100}

## Installs a decoded save. Derived data is rebuilt without touching revision numbers,
## so a loaded game continues exactly like the game that was saved.
func load_state(s: Dictionary) -> void:
	state = s
	var sc: Dictionary = content["scenarios"][state["scenario"]]
	planet = content["planets"][state["planet"]]
	world = WorldGen.get_world(int(state["seed"]), planet, bal, int(sc["map_size"]))
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
	var n := 0
	for aid in state["agents"]:
		if state["agents"][aid]["state"] == "alive":
			n += 1
	_alive_tick = tick
	_alive_n = n
	return n

## Forget the per-tick count (a colonist was added or removed during this tick).
func alive_changed() -> void:
	_alive_n = -1

func next_name() -> String:
	var names: Array = content["names"]
	var n: int = int(state["names_used"])
	state["names_used"] = n + 1
	var name: String = names[n % names.size()]
	if n >= names.size():
		name += " %d" % (n / names.size() + 1)
	return name

func log_event(code: String, text: String, entities: Array, sev: int = 1) -> void:
	var log: Array = state["log"]
	log.append({"tick": int(state["tick"]), "code": code, "text": text, "ents": entities.duplicate(), "sev": sev})
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
	var second: bool = tick % int(bal["tick_hz"]) == 0
	cmds.apply_pending()
	util.env_tick()
	if second:
		events.tick_second()
	if bool(state["topo_dirty"]):
		topo.rebuild(true)
	util.power_tick()
	util.water_tick()
	util.atmo_tick()
	agents.needs_tick()
	if second:
		build.tick_second()
		upgrades.tick_second()
		ship.tick_second()
		jobs.tick_second()
	agents.think_tick()
	agents.locks_tick()
	agents.act_tick()
	ship.tick()
	if second:
		prod.crops_second()
		prod.auto_second()
		prod.spoil_second()
		prod.wear_second()
		agents.morale_second()
		research.tick_second()
		alerts.tick_second()
		metrics.tick_second()
		goals.tick_second()
		awards.tick_second()

func run_seconds(secs: float) -> void:
	var n: int = int(secs * float(bal["tick_hz"]))
	for i in n:
		step()
