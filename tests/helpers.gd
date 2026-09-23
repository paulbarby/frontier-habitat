extends RefCounted
## Shared helpers for the headless tests. No class_name: use
##   const H = preload("res://tests/helpers.gd")
##
## Two kinds of set-up are used by the tests:
##   1. The documented reference layout, played through submit() like a player would.
##   2. Small custom layouts, made "instantly" with sim.build.spawn_active() (the same call
##      the scenario uses for the lander) and an instantly commissioned link. That is test
##      set-up, not player input. Each test says so where it does it.

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const Persistence = preload("res://sim/persistence.gd")

const HZ := 10
const DAY_TICKS := 6000

## Offsets (metres from the lander) of the reference layout. Custom layouts reuse these
## places because the reference layout proves they are legal on every tutorial seed.
const SLOT := {
	"A1": Vector2(8, -14), "B1": Vector2(1, -14), "W1": Vector2(24, -24), "R1": Vector2(24, -31.5),
	"O1": Vector2(18, -11), "L1": Vector2(16, 0), "H1": Vector2(30, 0), "A2": Vector2(8, -22),
	"A3": Vector2(16, -22), "B2": Vector2(1, -19.5), "S1": Vector2(30, -14.5), "K1": Vector2(30, 14),
	"G1": Vector2(15.5, 16),
}

## Power, water, oxygen plant and airlock of the reference layout, in the same order.
const CORE_STEPS := [
	{"place": "solar_array", "as": "A1"}, {"place": "battery", "as": "B1"}, {"link": "cable", "a": "A1", "b": "B1"},
	{"place": "water_extractor", "as": "W1"}, {"place": "reservoir", "as": "R1"}, {"place": "oxygen_plant", "as": "O1"},
	{"link": "cable", "a": "W1", "b": "R1"}, {"link": "cable", "a": "W1", "b": "O1"}, {"link": "cable", "a": "A1", "b": "O1"},
	{"place": "airlock", "as": "L1", "rot": PI}, {"link": "corridor", "a": "L1", "b": "O1"},
]

# ---------------------------------------------------------------- a game under test
## A simulation plus (optionally) the reference driver. step() keeps the driver on its
## once-per-second rhythm, so a test can stop on any tick.
class Game:
	var sim
	var ref = null

	func _init(seed_value: int, with_reference: bool) -> void:
		sim = Sim.new()
		sim.new_game(seed_value)
		if with_reference:
			ref = Reference.new(sim)

	func tick() -> int:
		return int(sim.state["tick"])

	func step() -> void:
		if ref != null and int(sim.state["tick"]) % HZ == 0:
			ref.drive()
		sim.step()

	func run(ticks: int) -> void:
		for i in ticks:
			step()

	func run_seconds(secs: float) -> void:
		run(int(round(secs * HZ)))

	func run_to_tick(target: int) -> void:
		while int(sim.state["tick"]) < target:
			step()

	## Steps until cond.call() is true. Returns false on time-out.
	func run_until(cond: Callable, max_ticks: int) -> bool:
		for i in max_ticks:
			if cond.call():
				return true
			step()
		return cond.call()

	## Submits one player command, runs the tick that applies it, returns its result
	## ({ok, code, id?, warnings?}).
	func cmd(kind: String, payload: Dictionary) -> Dictionary:
		var id: int = sim.submit(kind, payload)
		step()
		return sim.cmds.results.get(id, {"ok": false, "code": "not_applied"})

	func dispose() -> void:
		if sim != null:
			sim.dispose()
		sim = null
		ref = null

static func reference_game(seed_value: int = 1001) -> Game:
	return Game.new(seed_value, true)

static func empty_game(seed_value: int = 1001) -> Game:
	return Game.new(seed_value, false)

## A second simulation that continues from a save of `sim` (encode -> decode -> load).
static func clone_by_save(sim) -> Dictionary:
	var bytes: PackedByteArray = sim.save_bytes()
	var dec: Dictionary = Persistence.decode(bytes)
	if not dec["ok"]:
		return {"ok": false, "error": dec["error"], "bytes": bytes.size()}
	var sim2 = Sim.new()
	sim2.load_state(dec["state"])
	return {"ok": true, "sim": sim2, "bytes": bytes.size()}

## The Reference driver keeps its own progress. A loaded game needs a driver that knows
## what was already ordered, or it would replay the whole layout.
static func copy_reference(src, sim2):
	var r = Reference.new(sim2, src.group)
	r.done = src.done.duplicate(true)
	r.alias = src.alias.duplicate(true)
	# The driver adds junction steps and rewrites "*nearest" links while it plays.
	r.steps = src.steps.duplicate(true)
	r.ring = src.ring.duplicate(true)
	r._rescued = src._rescued.duplicate(true)
	return r

static func digest(sim) -> String:
	return Persistence.digest(sim.state)

static func set_clock(sim, day: int, second_of_day: float) -> void:
	# Test set-up: moves the clock before the first tick. Day 1 is the first day.
	sim.state["tick"] = int(round((float(day - 1) * 600.0 + second_of_day) * HZ))

# ---------------------------------------------------------------- queries
static func buildings_of(sim, def_id: String, only_active: bool = false) -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		if blds[id]["def"] == def_id and (not only_active or blds[id]["state"] == "active"):
			out.append(id)
	return out

static func first_of(sim, def_id: String) -> int:
	var ids: Array = buildings_of(sim, def_id)
	return int(ids[0]) if not ids.is_empty() else -1

static func find_link(sim, def_id: String, a_id: int, b_id: int) -> int:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var l: Dictionary = blds[id]
		if l["kind"] == "link" and l["def"] == def_id:
			if (int(l["a"]) == a_id and int(l["b"]) == b_id) or (int(l["a"]) == b_id and int(l["b"]) == a_id):
				return int(id)
	return -1

static func alive_agents(sim) -> Array:
	var out: Array = []
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid]["state"] == "alive":
			out.append(sim.state["agents"][aid])
	return out

static func refused_commands(sim) -> Array:
	var out: Array = []
	for c in sim.state["commands"]:
		if not bool(c["ok"]):
			out.append("%s %s -> %s" % [c["kind"], str(c["payload"]), c["code"]])
	return out

static func log_entries(sim, code: String) -> Array:
	var out: Array = []
	for e in sim.state["log"]:
		if e["code"] == code:
			out.append(e)
	return out

static func issues_with_code(sim, code: String) -> Array:
	var out: Array = []
	for key in sim.state["issues"]:
		if sim.state["issues"][key]["code"] == code:
			out.append(sim.state["issues"][key])
	return out

## Units of one resource in every inventory of the world (sites and carriers included).
static func world_count(sim, res: String) -> int:
	var n := 0
	for inv_id in sim.state["inventories"]:
		n += int(sim.state["inventories"][inv_id]["items"].get(res, 0))
	return n

static func ledger_of(sim, res: String) -> Dictionary:
	return sim.state["ledger"].get(res, {"created": 0, "consumed": 0, "destroyed": 0})

static func battery_energy(sim, ids: Array) -> int:
	var e := 0
	for id in ids:
		if sim.state["buildings"].has(id):
			e += int(sim.state["buildings"][id]["energy"])
	return e

static func reservoir_water(sim, ids: Array) -> int:
	var w := 0
	for id in ids:
		if sim.state["buildings"].has(id):
			w += int(sim.state["buildings"][id]["water"])
	return w

static func oxygen_of(sim, ids: Array) -> int:
	var o := 0
	for id in ids:
		if sim.state["buildings"].has(id):
			o += int(sim.state["buildings"][id]["oxygen"])
	return o

# ---------------------------------------------------------------- invariants
## Everything that must be true of inventories and reservations between two ticks.
## Returns a list of problems; empty means sound.
##   - no count is negative, no hold is larger than the stock it reserves
##   - the per-inventory hold counters equal the sum of the hold records (no leak)
##   - incoming reservations fit the capacity
##   - every hold has a living owner: a task, a colonist's own plan, or a machine batch
static func inventory_problems(sim) -> Array:
	var problems: Array = []
	var invs: Dictionary = sim.state["inventories"]
	var holds: Dictionary = sim.state["holds"]
	var tasks: Dictionary = sim.state["tasks"]
	var agents: Dictionary = sim.state["agents"]
	var blds: Dictionary = sim.state["buildings"]
	var sum_out := {}   # inventory id -> {resource -> units in "out" hold records}
	var sum_in := {}    # inventory id -> units in "in" hold records
	for hid in holds:
		var h: Dictionary = holds[hid]
		if not invs.has(h["inv"]):
			problems.append("hold %d points at missing inventory %d" % [hid, h["inv"]])
			continue
		if int(h["qty"]) <= 0:
			problems.append("hold %d has quantity %d" % [hid, h["qty"]])
		if h["dir"] == "out":
			if not sum_out.has(h["inv"]):
				sum_out[h["inv"]] = {}
			sum_out[h["inv"]][h["res"]] = int(sum_out[h["inv"]].get(h["res"], 0)) + int(h["qty"])
		else:
			sum_in[h["inv"]] = int(sum_in.get(h["inv"], 0)) + int(h["qty"])
		var owner: int = int(h["owner"])
		if owner > 0:
			if not tasks.has(owner):
				problems.append("hold %d (%s x%d) belongs to task %d, which no longer exists" % [hid, h["res"], h["qty"], owner])
			elif int(tasks[owner]["hold_out"]) != int(hid) and int(tasks[owner]["hold_in"]) != int(hid):
				problems.append("hold %d names task %d, but the task does not name the hold" % [hid, owner])
		elif owner <= -1000000:
			var bid: int = -owner - 1000000
			if not blds.has(bid) or (blds[bid]["batch"] as Dictionary).is_empty() or int(blds[bid]["batch"]["hold"]) != int(hid):
				problems.append("batch hold %d has no running batch in building %d" % [hid, bid])
		else:
			var aid: int = -owner
			if not agents.has(aid) or agents[aid]["state"] != "alive":
				problems.append("personal hold %d belongs to colonist %d, who is not alive" % [hid, aid])
	for inv_id in invs:
		var inv: Dictionary = invs[inv_id]
		var total := 0
		for res in inv["items"]:
			var n: int = int(inv["items"][res])
			total += n
			if n < 0:
				problems.append("inventory %d has %d %s" % [inv_id, n, res])
		var recs: Dictionary = sum_out.get(inv_id, {})
		for res in inv["held_out"]:
			var held: int = int(inv["held_out"][res])
			if held < 0 or held > int(inv["items"].get(res, 0)):
				problems.append("inventory %d holds %d %s out of a stock of %d" % [inv_id, held, res, int(inv["items"].get(res, 0))])
			if held != int(recs.get(res, 0)):
				problems.append("inventory %d counts %d %s held, the hold records say %d" % [inv_id, held, res, int(recs.get(res, 0))])
		for res in recs:
			if not inv["held_out"].has(res):
				problems.append("inventory %d has hold records for %s but no counter" % [inv_id, res])
		if int(inv["held_in"]) < 0 or int(inv["held_in"]) != int(sum_in.get(inv_id, 0)):
			problems.append("inventory %d counts %d incoming, the hold records say %d" % [inv_id, inv["held_in"], int(sum_in.get(inv_id, 0))])
		if inv["role"] != "pile" and total + int(inv["held_in"]) > int(inv["cap"]) and not (inv["ot"] == "b" and int(inv["oid"]) == int(sim.state["lander_id"])):
			problems.append("inventory %d (%s) is over capacity: %d + %d incoming > %d" % [inv_id, inv["role"], total, inv["held_in"], inv["cap"]])
	return problems

## Utility stocks never go negative and never exceed capacity (spec 8). Version 2: the
## capacity is the effective one (size, level and research bonus).
static func utility_problems(sim) -> Array:
	var problems: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			continue
		var def: Dictionary = sim.bd(b)
		if int(b["energy"]) < 0 or int(b["water"]) < 0 or int(b["oxygen"]) < 0:
			problems.append("%s has a negative stock (E %d, water %d, O2 %d)" % [b["name"], b["energy"], b["water"], b["oxygen"]])
		if def.has("energy_cap") and int(b["energy"]) > sim.util.energy_cap_of(b):
			problems.append("%s holds more energy than its capacity" % b["name"])
		if def.has("water_cap") and int(b["water"]) > sim.util.water_cap_of(b):
			problems.append("%s holds more water than its capacity" % b["name"])
	return problems

# ---------------------------------------------------------------- instant layouts (test set-up)
## A finished structure at `off` metres from the lander, after the normal placement check.
## Returns {} and an error text in `errors` when the place is not legal.
static func spawn(sim, def_id: String, off: Vector2, rot: float, errors: Array, size: int = 1) -> Dictionary:
	var pos: Vector2 = sim.place.snap_pos(sim.world.center + off)
	var r: float = sim.place.snap_rot(rot)
	var code: String = sim.place.check_building(def_id, pos, r, -1, size)
	if code != "ok":
		errors.append("cannot place %s at %s: %s" % [def_id, str(off), code])
		return {}
	return sim.build.spawn_active(def_id, pos, r, size)

## A finished corridor or cable between two structures, after the normal link check.
static func link_now(sim, def_id: String, a_id: int, b_id: int, errors: Array) -> Dictionary:
	var res: Dictionary = sim.build.place_link(def_id, a_id, b_id)
	if not bool(res["ok"]):
		errors.append("cannot link %s %d-%d: %s" % [def_id, a_id, b_id, res["code"]])
		return {}
	var l: Dictionary = sim.state["buildings"][res["id"]]
	l["cost"] = {}          # no material was delivered, so none can come back as salvage
	sim.build._commission(l, false)
	return l

## Removes a finished link at once, through the same code path that removes the links of
## a demolished building.
static func unlink_now(sim, link_id: int) -> void:
	var l: Dictionary = sim.state["buildings"][link_id]
	l["demolish"] = true
	l["progress"] = sim.build.demolish_work_total(l)
	sim.build._try_finish_demolition(l)

## Plays a list of {"place", "as", "at"?, "rot"?} and {"link", "a", "b", "as"?} steps
## instantly. "at" is a SLOT name or a Vector2 offset; without it, "as" names the slot.
## Returns {"ids": alias -> id, "errors": [...]}.
static func layout(sim, steps: Array, ids: Dictionary = {}) -> Dictionary:
	var errors: Array = []
	for st in steps:
		if st.has("place"):
			var at = st.get("at", st["as"])
			var off: Vector2 = SLOT[at] if typeof(at) == TYPE_STRING else at
			var b: Dictionary = spawn(sim, st["place"], off, float(st.get("rot", 0.0)), errors, int(st.get("size", 1)))
			if not b.is_empty():
				ids[st["as"]] = int(b["id"])
		elif st.has("link"):
			if not ids.has(st["a"]) or not ids.has(st["b"]):
				errors.append("link %s-%s: a structure is missing" % [st["a"], st["b"]])
				continue
			var l: Dictionary = link_now(sim, st["link"], ids[st["a"]], ids[st["b"]], errors)
			if not l.is_empty():
				ids[st.get("as", "%s-%s" % [st["a"], st["b"]])] = int(l["id"])
	return {"ids": ids, "errors": errors}

## Fills batteries, reservoirs and room air (test set-up: a base that already ran a while).
static func fill_utilities(sim, energy_fraction: float = 1.0, water_fraction: float = 0.8, air: bool = true) -> void:
	var blds: Dictionary = sim.state["buildings"]
	var fp: int = sim.util.fp()
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active":
			continue
		if b["kind"] == "link" or b["def"] == "meridian":
			continue
		var def: Dictionary = sim.bd(b)
		if def.has("energy_cap"):
			b["energy"] = int(sim.util.energy_cap_of(b) * energy_fraction)
		if def.has("water_cap"):
			b["water"] = int(sim.util.water_cap_of(b) * water_fraction)
		if air and b["kind"] == "room":
			b["oxygen"] = int(float(def.get("occupants", 1)) * float(sim.bal["oxygen_per_occupant_capacity"]) * fp)

## Test set-up: the colonist stands in a room, with no plan and no task.
static func put_inside(sim, a: Dictionary, bid: int, slot: int = -1) -> void:
	sim.agents.abort_plan(a, "test_setup")
	var b: Dictionary = sim.state["buildings"][bid]
	a["where"] = "in"
	a["bld"] = bid
	a["pos"] = sim.nav.slot_pos(b, int(a["id"]) if slot < 0 else slot)

## Test set-up: the colonist stands outdoors, with no plan and no task.
static func put_outside(sim, a: Dictionary, pos: Vector2, suit: float) -> void:
	sim.agents.abort_plan(a, "test_setup")
	a["where"] = "out"
	a["bld"] = -1
	a["pos"] = pos
	a["suit"] = suit

static func set_priorities(g: Game, values: Dictionary) -> void:
	for cat in values:
		g.cmd("set_priority", {"cat": cat, "value": int(values[cat])})
