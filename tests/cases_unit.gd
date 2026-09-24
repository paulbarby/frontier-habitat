extends RefCounted
## Unit tests: random streams, fixed-point rates, placement refusals, save-file checks,
## and the reservation primitives.

const H = preload("res://tests/helpers.gd")
const Rng = preload("res://sim/rng.gd")
const Persistence = preload("res://sim/persistence.gd")

func tests() -> Array:
	return [
		["unit_rng_streams", unit_rng_streams],
		["unit_fixed_point_rates", unit_fixed_point_rates],
		["unit_placement_reasons", unit_placement_reasons],
		["unit_persistence_rejects_bad_files", unit_persistence_rejects_bad_files],
		["unit_reservation_primitives", unit_reservation_primitives],
	]

# ---------------------------------------------------------------- RNG
func unit_rng_streams(t) -> void:
	# Known answers from an independent mulberry32 written in JavaScript (Node 22):
	# streamSeed(1001, 1) and the first five outputs of that stream.
	t.eq(Rng.stream_seed(1001, 1), 2426579955, "stream_seed(1001, 1)")
	t.eq(Rng.stream_seed(1001, 2), 1845535991, "stream_seed(1001, 2)")
	t.eq(Rng.stream_seed(0, 0), 301794027, "stream_seed(0, 0)")
	var known := {"w": Rng.stream_seed(1001, 1)}
	var got: Array = []
	for i in 5:
		got.append(Rng.next_u32(known, "w"))
	t.eq(got, [398591926, 3186289379, 2130959216, 2484126304, 2290692246], "first five outputs of stream (1001, 1)")

	# Same seed, same sequence. Different stream, different sequence.
	var a := {"x": Rng.stream_seed(77, 1), "y": Rng.stream_seed(77, 2)}
	var b := {"x": Rng.stream_seed(77, 1), "y": Rng.stream_seed(77, 2)}
	var same := true
	var differs := false
	var in_range := true
	for i in 2000:
		var va: int = Rng.next_u32(a, "x")
		same = same and va == Rng.next_u32(b, "x")
		differs = differs or va != Rng.next_u32(a, "y")
		in_range = in_range and va >= 0 and va <= 0xFFFFFFFF
	t.check(same, "two streams with the same seed give the same 2000 numbers")
	t.check(differs, "streams with different salts give different numbers")
	t.check(in_range, "every output is an unsigned 32-bit number")

	# Streams are independent: drawing from one does not move the other.
	var c := {"x": Rng.stream_seed(5, 1), "y": Rng.stream_seed(5, 2)}
	var y_before: int = int(c["y"])
	for i in 100:
		Rng.next_u32(c, "x")
	t.eq(int(c["y"]), y_before, "stream y after 100 draws from stream x")

	# A stream is one integer, so a copy of the state resumes exactly (save/load rule).
	var saved: Dictionary = c.duplicate(true)
	var cont: Array = []
	var cont2: Array = []
	for i in 50:
		cont.append(Rng.next_float(c, "x"))
	for i in 50:
		cont2.append(Rng.next_float(saved, "x"))
	t.eq(cont2, cont, "a restored stream continues with the same numbers")

	var lo := 1e9
	var hi := -1e9
	var hit_lo := false
	var hit_hi := false
	var ints_ok := true
	for i in 5000:
		var f: float = Rng.next_float(c, "x")
		lo = minf(lo, f)
		hi = maxf(hi, f)
		var n: int = Rng.range_int(c, "y", 3, 6)
		ints_ok = ints_ok and n >= 3 and n <= 6
		hit_lo = hit_lo or n == 3
		hit_hi = hit_hi or n == 6
	t.check(lo >= 0.0 and hi < 1.0, "next_float stays in [0, 1): saw %f .. %f" % [lo, hi])
	t.check(ints_ok and hit_lo and hit_hi, "range_int(3, 6) stays inside and reaches both ends")

	# In the simulation only the weather stream moves in an ordinary game (spec 11: the
	# hazard stream is separate from everything else).
	var g = H.empty_game(1001)
	var before: Dictionary = g.sim.state["rng"].duplicate(true)
	t.eq(before.size(), 4, "number of RNG streams in the state")
	var distinct := {}
	for k in before:
		distinct[before[k]] = true
	t.eq(distinct.size(), 4, "distinct stream seeds")
	g.run_seconds(90.0)
	var after: Dictionary = g.sim.state["rng"]
	t.check(int(after["weather"]) != int(before["weather"]), "the weather stream advanced in 90 s")
	t.eq(int(after["hazard"]), int(before["hazard"]), "hazard stream after 90 s")
	t.eq(int(after["arrivals"]), int(before["arrivals"]), "arrivals stream after 90 s")
	t.note("known-answer vector ok, 2000-draw repeat ok, float range %.5f..%.5f" % [lo, hi])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- fixed point
func unit_fixed_point_rates(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var fp: int = sim.util.fp()
	var day_ticks: int = int(sim.bal["day_length"]) * int(sim.bal["tick_hz"])
	t.eq(fp, 60000, "fixed_point_scale")
	t.eq(day_ticks, 6000, "ticks per day")
	t.eq(sim.util.rt(1.0) * day_ticks, fp, "1 P for one day is exactly 1 E (spec 5)")
	t.eq(sim.util.rt(0.0), 0, "rt(0)")

	# Every rate in buildings.json is a whole number of sub-units per tick, so a day of
	# ticks adds up to exactly the daily amount: no drift, ever.
	var checked := 0
	var worst := 0.0
	for def_id in sim.content["buildings"]:
		var def: Dictionary = sim.content["buildings"][def_id]
		for key in ["power", "gen_solar", "water_out", "o2_out", "water_in", "energy_rate"]:
			if not def.has(key):
				continue
			var r: float = float(def[key])
			var per_tick: int = sim.util.rt(r)
			var err: float = absf(float(per_tick) * float(day_ticks) - r * float(fp))
			worst = maxf(worst, err)
			t.check(err < 1e-6, "%s.%s = %s per day is not exact in fixed point (rt = %d)" % [def_id, key, str(r), per_tick])
			t.near(sim.util.to_rate(per_tick), r, 1e-9, "to_rate(rt(%s.%s))" % [def_id, key])
			checked += 1
		if def.has("gen_wind"):
			# Wind is rounded to 0.1 before it is used, so every wind output is exact too.
			for tenth in [1, 7, 30, 80]:
				var rw: float = float(def["gen_wind"]) * float(tenth) / 10.0
				t.check(absf(float(sim.util.rt(rw)) * day_ticks - rw * fp) < 1e-6, "wind output %s P is not exact" % str(rw))
				checked += 1
		for key in ["energy_cap", "water_cap"]:
			if def.has(key):
				var cap: float = float(def[key]) * fp
				t.check(absf(cap - roundf(cap)) < 1e-9, "%s.%s is not a whole number of sub-units" % [def_id, key])
				checked += 1
	for key in ["oxygen_per_colonist", "crop_water_per_day", "breach_drain_per_day"]:
		var r2: float = float(sim.bal[key])
		t.check(absf(float(sim.util.rt(r2)) * day_ticks - r2 * fp) < 1e-6, "balance.%s = %s per day is not exact" % [key, str(r2)])
		checked += 1
	var o2_cap: float = float(sim.bal["oxygen_per_occupant_capacity"]) * fp
	t.check(absf(o2_cap - roundf(o2_cap)) < 1e-9, "oxygen capacity per occupant is a whole number of sub-units")
	t.near(sim.util.units(fp), 1.0, 1e-12, "units(fp)")
	# The spec numbers themselves.
	t.eq(sim.util.rt(12.0), 120, "solar array 12 P per tick")
	t.eq(sim.util.rt(0.2), 2, "storehouse 0.2 P per tick")
	t.eq(sim.util.rt(0.5), 5, "airlock 0.5 P per tick")
	t.eq(sim.util.rt(60.0), 600, "extractor 60 water/day per tick")
	t.note("%d rates exact, worst error %.2e sub-units/day" % [checked, worst])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- placement
func _place(g, def_id: String, pos: Vector2, rot: float = 0.0) -> Dictionary:
	return g.cmd("place_building", {"def": def_id, "x": pos.x, "y": pos.y, "rot": rot})

func unit_placement_reasons(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var c: Vector2 = sim.world.center
	var seen: Array = []

	var r: Dictionary = _place(g, "solar_array", c + Vector2(3, 0))
	t.eq(r["code"], "overlap", "solar array on top of the lander")
	t.check(not bool(r["ok"]), "an overlapping placement is refused")
	seen.append(r["code"])

	r = _place(g, "battery", Vector2(1.0, 1.0))
	t.eq(r["code"], "outside_map", "battery at the map corner")
	seen.append(r["code"])
	r = _place(g, "battery", Vector2(float(sim.world.size) + 44.0, c.y))
	t.eq(r["code"], "outside_map", "battery beyond the east edge")

	# Slope: search the terrain of this seed for a place that is too steep for a habitat.
	var steep_at = null
	var y := 12.0
	var far: float = float(sim.world.size) - 12.0
	while y < far and steep_at == null:
		var x := 12.0
		while x < far:
			if sim.place.check_building("habitat", Vector2(x, y), 0.0) == "slope":
				steep_at = Vector2(x, y)
				break
			x += 4.0
		y += 4.0
	if steep_at == null:
		t.note("seed 1001 has no place too steep for a habitat; slope refusal not exercised")
	else:
		r = _place(g, "habitat", steep_at)
		t.eq(r["code"], "slope", "habitat on steep ground at %s" % str(steep_at))
		seen.append(r["code"])

	# The door of this airlock points at the lander hull: its access strip is blocked.
	r = _place(g, "airlock", c + Vector2(-10, 0), 0.0)
	t.eq(r["code"], "blocked_entrance", "airlock with its door against the lander")
	seen.append(r["code"])
	# And a structure may not stand on the access strip of an existing door (the hatch).
	r = _place(g, "solar_array", c + Vector2(9.5, 0))
	t.eq(r["code"], "blocks_entrance", "solar array on the lander's hatch strip")
	seen.append(r["code"])

	r = _place(g, "mine", c + Vector2(20, 0))
	t.eq(r["code"], "no_support", "mine away from any deposit")
	seen.append(r["code"])
	var dep: Dictionary = sim.state["deposits"][0]
	r = _place(g, "mine", Vector2(dep["x"], dep["y"]))
	t.eq(r["code"], "ok", "mine on the start deposit")
	t.check(bool(r["ok"]) and sim.state["buildings"].has(r.get("id", -1)), "the accepted mine exists as a blueprint")

	if not sim.world.rocks.is_empty():
		var rock: Dictionary = sim.world.rocks[0]
		r = _place(g, "battery", Vector2(rock["x"], rock["y"]))
		t.eq(r["code"], "overlap_rock", "battery on a rock outcrop")
		seen.append(r["code"])

	r = _place(g, "workshop", c + Vector2(-20, 14))
	t.eq(r["code"], "locked", "workshop before its stage is reached")
	seen.append(r["code"])
	r = _place(g, "lander", c + Vector2(-20, 14))
	t.check(not bool(r["ok"]), "the lander is not buildable")
	r = _place(g, "no_such_thing", c + Vector2(-20, 14))
	t.eq(r["code"], "unknown", "unknown definition")

	# Links.
	var errors: Array = []
	var lock: Dictionary = H.spawn(sim, "airlock", H.SLOT["L1"], PI, errors)
	var sol: Dictionary = H.spawn(sim, "solar_array", H.SLOT["A1"], 0.0, errors)
	var bat: Dictionary = H.spawn(sim, "battery", H.SLOT["B1"], 0.0, errors)
	t.check(errors.is_empty(), "set-up places are legal: %s" % str(errors))
	if errors.is_empty():
		var lr: Dictionary = g.cmd("place_link", {"def": "corridor", "a": lock["id"], "b": sim.state["lander_id"]})
		t.eq(lr["code"], "lander", "corridor to the lander")
		lr = g.cmd("place_link", {"def": "corridor", "a": lock["id"], "b": sol["id"]})
		t.eq(lr["code"], "not_room", "corridor to an outdoor structure")
		lr = g.cmd("place_link", {"def": "cable", "a": sol["id"], "b": sol["id"]})
		t.eq(lr["code"], "same", "cable from a structure to itself")
		lr = g.cmd("place_link", {"def": "cable", "a": sol["id"], "b": bat["id"]})
		t.eq(lr["code"], "ok", "cable solar-battery")
		lr = g.cmd("place_link", {"def": "cable", "a": bat["id"], "b": sol["id"]})
		t.eq(lr["code"], "duplicate", "the same cable again")
		seen.append_array(["lander", "not_room", "same", "duplicate"])

	# Every refusal has a sentence for the player (spec 4: precise rejection reason).
	for code in seen:
		t.check(sim.place.reason_text(code) != code and sim.place.reason_text(code).length() > 8, "reason '%s' has no sentence" % code)
	t.check(H.refused_commands(sim).size() >= seen.size() - 1, "refused commands are recorded in the command log")
	t.note("refusals seen: %s" % ", ".join(seen))
	g.dispose()
	t.done()

# ---------------------------------------------------------------- persistence
func _frame(schema: int, payload) -> PackedByteArray:
	var raw: PackedByteArray = var_to_bytes(payload)
	var out := StreamPeerBuffer.new()
	out.put_data(Persistence.MAGIC.to_ascii_buffer())
	out.put_u32(schema)
	out.put_u32(raw.size())
	out.put_data(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return out.data_array

func unit_persistence_rejects_bad_files(t) -> void:
	var g = H.reference_game(1001)
	g.run_seconds(40.0)
	var sim = g.sim
	var bytes: PackedByteArray = sim.save_bytes()
	var good: Dictionary = Persistence.decode(bytes)
	t.check(bool(good["ok"]), "a fresh save decodes: %s" % good.get("error", ""))
	if bool(good["ok"]):
		t.eq(Persistence.digest(good["state"]), Persistence.digest(sim.state), "digest of the decoded state")
		t.eq(int(good["state"]["tick"]), 400, "tick in the decoded state")

	var cases := {}
	cases["empty"] = PackedByteArray()
	cases["too short"] = PackedByteArray([1, 2, 3, 4, 5])
	var junk := PackedByteArray()
	for i in 4096:
		junk.append((i * 73 + 11) % 256)
	cases["garbage"] = junk
	var junk_body: PackedByteArray = bytes.slice(0, 16)
	junk_body.append_array(junk)
	cases["good header, garbage body"] = junk_body
	cases["truncated to 60%"] = bytes.slice(0, int(bytes.size() * 0.6))
	cases["truncated by one byte"] = bytes.slice(0, bytes.size() - 1)
	var newer: PackedByteArray = bytes.duplicate()
	newer.encode_u32(8, Persistence.SCHEMA + 1)
	cases["newer schema"] = newer
	var bad_len: PackedByteArray = bytes.duplicate()
	bad_len.encode_u32(12, 0)
	cases["zero length header"] = bad_len
	cases["wrong shape"] = _frame(Persistence.SCHEMA, [1, 2, 3])
	var partial: Dictionary = sim.state.duplicate(true)
	partial.erase("ledger")
	cases["missing key"] = _frame(Persistence.SCHEMA, partial)
	for label in cases:
		var res: Dictionary = Persistence.decode(cases[label])
		t.check(not bool(res["ok"]), "%s: must be refused" % label)
		t.check(not res.has("state"), "%s: a refused file must not hand back a state" % label)
		t.check(String(res.get("error", "")).length() > 10, "%s: needs an error sentence, got '%s'" % [label, res.get("error", "")])
	t.check(String(Persistence.decode(newer)["error"]).contains("newer"), "the newer-schema message says so: %s" % Persistence.decode(newer)["error"])
	t.check(String(Persistence.decode(cases["missing key"])["error"]).contains("ledger"), "the missing-key message names the key")

	# Slot files: written through a temporary file, verified, then moved into place.
	var slot := "zz_test_%d" % OS.get_process_id()
	var w: Dictionary = Persistence.write_slot(slot, sim.state)
	t.check(bool(w["ok"]), "write_slot: %s" % w.get("error", ""))
	var rd: Dictionary = Persistence.read_slot(slot)
	t.check(bool(rd["ok"]), "read_slot: %s" % rd.get("error", ""))
	if bool(rd["ok"]):
		t.eq(Persistence.digest(rd["state"]), Persistence.digest(sim.state), "digest after write_slot + read_slot")
	t.check(not FileAccess.file_exists(Persistence.slot_path(slot + ".tmp")), "no temporary file stays behind")
	# A second save to the same slot replaces the first one.
	g.run_seconds(5.0)
	w = Persistence.write_slot(slot, sim.state)
	rd = Persistence.read_slot(slot)
	t.check(bool(w["ok"]) and bool(rd["ok"]) and int(rd["state"]["tick"]) == 450, "overwriting a slot keeps the newer game")
	DirAccess.remove_absolute(Persistence.slot_path(slot))
	t.check(not bool(Persistence.read_slot(slot)["ok"]), "an empty slot reports an error instead of a state")

	# Autosave rotation uses fixed slot names. Only exercise it when no real autosave
	# exists, so a test run never touches a player's saves.
	var real := false
	for i in range(1, 4):
		real = real or FileAccess.file_exists(Persistence.slot_path("autosave_%d" % i))
	if real:
		t.note("autosave rotation not exercised: real autosaves exist and were left alone")
	else:
		var ticks: Array = []
		for i in 4:
			g.run_seconds(1.0)
			ticks.append(g.tick())
			t.check(bool(Persistence.autosave(sim.state, 3)["ok"]), "autosave %d" % i)
		var kept: Array = []
		for i in range(1, 5):
			var s: Dictionary = Persistence.read_slot("autosave_%d" % i)
			if bool(s["ok"]):
				kept.append(int(s["state"]["tick"]))
		t.eq(kept, [ticks[3], ticks[2], ticks[1]], "three rotating autosaves, newest first")
		for i in range(1, 5):
			DirAccess.remove_absolute(Persistence.slot_path("autosave_%d" % i))
		DirAccess.remove_absolute(Persistence.slot_path("autosave_new"))
	t.note("save %d bytes, %d bad files refused" % [bytes.size(), cases.size()])
	g.dispose()
	t.done()

# ---------------------------------------------------------------- reservations
func unit_reservation_primitives(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, sim.world.center + Vector2(12, 12))
	var box: int = sim.inv.create_inv("g", 0, "pile", 4, sim.world.center + Vector2(14, 12))
	var carrier: int = sim.inv.create_inv("g", 0, "pile", 10, sim.world.center)
	sim.inv.add_new_forced(pile, "metal", 5, "test")

	var h1: int = sim.inv.hold_out(pile, "metal", 3, 9001)
	t.check(h1 != -1, "first worker reserves 3 of 5")
	t.eq(sim.inv.hold_out(pile, "metal", 3, 9002), -1, "second worker asks for 3 of the 2 that are left")
	var h2: int = sim.inv.hold_out(pile, "metal", 2, 9002)
	t.check(h2 != -1, "second worker reserves the last 2")
	t.eq(sim.inv.available(pile, "metal"), 0, "free metal with everything reserved")
	t.eq(sim.inv.hold_out(pile, "metal", 1, 9003), -1, "third worker finds nothing to reserve")
	t.eq(sim.inv.move(pile, carrier, "metal", 5), 0, "an unreserved move cannot take reserved units")
	t.check(not sim.inv.consume(pile, "metal", 1, "test"), "reserved units cannot be consumed by somebody else")

	# Releasing a claim makes exactly those units free again.
	sim.inv.release_owner(9002)
	t.eq(sim.inv.available(pile, "metal"), 2, "free metal after worker two lets go")
	t.check(not sim.state["holds"].has(h2), "the released hold record is gone")

	# Collecting moves exactly the reserved units, once.
	t.check(sim.inv.take_held(h1, carrier), "worker one collects its 3 units")
	t.check(not sim.inv.take_held(h1, carrier), "the same reservation cannot be collected twice")
	t.eq(sim.inv.count(carrier, "metal"), 3, "units in the carrier")
	t.eq(sim.inv.count(pile, "metal"), 2, "units left in the pile")

	# Destination capacity is reserved too.
	var i1: int = sim.inv.hold_in(box, "metal", 3, 9001)
	t.check(i1 != -1, "3 incoming units fit a box of 4")
	t.eq(sim.inv.hold_in(box, "metal", 2, 9002), -1, "2 more do not fit while 3 are on their way")
	t.check(sim.inv.put_held(i1, carrier), "delivery into the reserved room")
	t.eq(sim.inv.count(box, "metal"), 3, "units delivered")
	t.eq(sim.inv.free_space(box), 1, "room left in the box")
	t.eq(sim.inv.add_new(box, "metal", 5, "test"), 1, "add_new is capped by the free room")

	t.eq(sim.inv.audit(), {}, "audit after the primitive operations")
	t.eq(H.inventory_problems(sim), [], "inventory invariants")
	# The audit notices a unit that appears from nowhere, and one that vanishes.
	sim.state["inventories"][pile]["items"]["metal"] = 3
	t.check(not sim.inv.audit().is_empty(), "the audit reports a duplicated unit")
	sim.state["inventories"][pile]["items"]["metal"] = 1
	t.check(not sim.inv.audit().is_empty(), "the audit reports a lost unit")
	g.dispose()
	t.done()
