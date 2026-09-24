extends RefCounted
## Save files (spec 14). The whole authoritative state is one plain Dictionary, so a
## save is its exact binary image: tick, RNG streams, tasks, reservations, active
## batches, needs, policies and pending events all come back exactly once. Navigation,
## terrain and network components are derived and are rebuilt after a load.
## File layout: "FHSAVE1\n" + u32 schema + u32 raw length + DEFLATE(var_to_bytes(state)).
## bytes_to_var never decodes objects, so an imported file cannot run code.

const MAGIC := "FHSAVE1\n"
const SCHEMA := 3
const REQUIRED := ["schema", "seed", "tick", "rng", "buildings", "inventories", "agents", "tasks", "holds", "policies", "ledger"]
const Research = preload("res://sim/research.gd")
const Goals = preload("res://sim/goals.gd")
const Ship = preload("res://sim/ship.gd")
const Hazards = preload("res://sim/hazards.gd")
const Rng = preload("res://sim/rng.gd")
## Ticks in a day of every schema so far (600 s at 10 Hz).
const DAY_TICKS := 6000
const ROLES := ["technician", "grower", "operator", "medic", "scientist"]

static func encode(state: Dictionary) -> PackedByteArray:
	var raw: PackedByteArray = var_to_bytes(state)
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var out := StreamPeerBuffer.new()
	out.put_data(MAGIC.to_ascii_buffer())
	out.put_u32(int(state.get("schema", SCHEMA)))
	out.put_u32(raw.size())
	out.put_data(packed)
	return out.data_array

## Returns {"ok", "state", "error"}. Validates before anything is loaded.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 16:
		return {"ok": false, "error": "The file is too short to be a save."}
	if bytes.slice(0, 8).get_string_from_ascii() != MAGIC:
		return {"ok": false, "error": "This is not a Frontier Habitat save file."}
	var inp := StreamPeerBuffer.new()
	inp.data_array = bytes
	inp.seek(8)
	var schema: int = inp.get_u32()
	var raw_len: int = inp.get_u32()
	if schema > SCHEMA:
		return {"ok": false, "error": "The save is from a newer version (schema %d). This build reads up to %d." % [schema, SCHEMA]}
	if raw_len <= 0 or raw_len > 256 * 1024 * 1024:
		return {"ok": false, "error": "The save header is damaged."}
	var raw: PackedByteArray = bytes.slice(16).decompress(raw_len, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_len:
		return {"ok": false, "error": "The save data is damaged."}
	var state = bytes_to_var(raw)
	if typeof(state) != TYPE_DICTIONARY:
		return {"ok": false, "error": "The save data has the wrong shape."}
	for key in REQUIRED:
		if not state.has(key):
			return {"ok": false, "error": "The save is missing '%s'." % key}
	state = migrate(state)
	return {"ok": true, "state": state, "error": ""}

## Schema migrations run in order. Version 1 is the first schema.
static func migrate(state: Dictionary) -> Dictionary:
	var v: int = int(state.get("schema", 1))
	if v < 2:
		_v1_to_v2(state)
		v = 2
	if v < 3:
		_v2_to_v3(state)
		v = 3
	state["schema"] = v
	return state

## Version 2 (docs/AAA_DESIGN.md section 10): sizes, levels, crops, dishes, nutrition,
## research, goals, awards, the Meridian, statistics and options. The old item
## "raw_food" becomes "potato" in every inventory, reservation, task and the ledger, so
## the books still balance. "meals" keeps its id (now the emergency ration). The Meridian
## itself is placed by sim.load_state(), which knows the terrain.
static func _v1_to_v2(s: Dictionary) -> void:
	for iid in s["inventories"]:
		var inv: Dictionary = s["inventories"][iid]
		_rename_key(inv["items"], "raw_food", "potato")
		_rename_key(inv["held_out"], "raw_food", "potato")
		if not inv.has("spoil"):
			inv["spoil"] = {}
	for hid in s["holds"]:
		if String(s["holds"][hid]["res"]) == "raw_food":
			s["holds"][hid]["res"] = "potato"
	for tid in s["tasks"]:
		if String(s["tasks"][tid].get("res", "")) == "raw_food":
			s["tasks"][tid]["res"] = "potato"
	var led: Dictionary = s["ledger"]
	if led.has("raw_food"):
		var old: Dictionary = led["raw_food"]
		var cur: Dictionary = led.get("potato", {"created": 0, "consumed": 0, "destroyed": 0})
		for k in ["created", "consumed", "destroyed"]:
			cur[k] = int(cur.get(k, 0)) + int(old.get(k, 0))
		led["potato"] = cur
		led.erase("raw_food")
	var m: Dictionary = s["metrics"]
	_rename_key(m["produced"], "raw_food", "potato")
	if not m.has("series"):
		m["series"] = {}
	if not m.has("daily"):
		m["daily"] = []
	for id in s["buildings"]:
		var b: Dictionary = s["buildings"][id]
		if not b.has("size"):
			b["size"] = 1
		if not b.has("level"):
			b["level"] = 1
		if not b.has("upgrade"):
			b["upgrade"] = {}
		if not b.has("recipe_sel"):
			b["recipe_sel"] = ""
		if not b.has("acc"):
			b["acc"] = {}
		if b["def"] == "kitchen" and not b.has("menu_off"):
			b["menu_off"] = {}
		if not (b.get("trays", []) as Array).is_empty() and not b.has("crop"):
			b["crop"] = "potato"
		for tray in b.get("trays", []):
			if not tray.has("crop"):
				tray["crop"] = "potato"
			if not tray.has("grow"):
				tray["grow"] = "potato" if tray["state"] != "empty" else ""
		var batch: Dictionary = b.get("batch", {})
		if not batch.is_empty() and String(batch.get("recipe", "")) == "cook":
			# A v1 kitchen batch turned 2 raw food into 2 meals: it finishes as mashed potatoes.
			batch["dish"] = "mashed_potato"
			batch["outputs"] = {"mashed_potato": 2}
	for aid in s["agents"]:
		var a: Dictionary = s["agents"][aid]
		if not a.has("nutrition"):
			a["nutrition"] = {"protein": 70.0, "carbs": 70.0, "fat": 70.0, "vitamins": 70.0}
		if not a.has("diet"):
			a["diet"] = []
		if not a.has("rec_bonus"):
			a["rec_bonus"] = 0.0
		if not a.has("medicated"):
			a["medicated"] = false
	if typeof(s.get("events", {})) != TYPE_DICTIONARY:
		s["events"] = {}
	if not s.has("options"):
		s["options"] = {"planet": String(s.get("planet", "dry")), "difficulty": "standard", "spoilage": true}
	if not s.has("research"):
		s["research"] = Research.fresh_state()
	if not s.has("goals"):
		s["goals"] = Goals.fresh_state()
	if not s.has("awards"):
		s["awards"] = {}
	if not s.has("award_track"):
		s["award_track"] = {}
	if not s.has("ship"):
		s["ship"] = Ship.fresh_state()
	if not s.has("stats"):
		var st := {"produced": {}, "consumed": {}, "spoiled": {}, "cooked": {}, "eaten": {}, "spoiled_today": {},
			"cooked_total": 0, "harvests": 0, "heals": 0, "techs": 0, "upgrades": 0, "ship_stages": 0,
			"ship_runs": 0, "ship_maintenance": 0, "settlers": int(m.get("settlers_admitted", 0))}
		for k in m["produced"]:
			st["produced"][k] = int(m["produced"][k])
		s["stats"] = st
	var pol: Dictionary = s["policies"]
	if not pol.has("immigration"):
		pol["immigration"] = {"open": true, "roles": ROLES.duplicate(), "cap": int(pol.get("pop_cap", 100))}

## Version 3 (docs/V3_DESIGN.md): the map keeps its 256 m; hazards start (other than the
## dust storm) no earlier than one day after the load; the v2 storm record becomes a
## dust_storm event; special research already paid with exotic crystals needs no packs;
## colonists get an empty furniture use; the alert hysteresis starts from the shown alerts.
static func _v2_to_v3(s: Dictionary) -> void:
	var tick: int = int(s["tick"])
	s["map_size"] = int(s.get("map_size", 256))
	var opt: Dictionary = s["options"]
	if not opt.has("hazards"):
		opt["hazards"] = "normal"
	if not opt.has("debug"):
		opt["debug"] = false
	if not s.has("hazards"):
		var h: Dictionary = Hazards.fresh_state()
		h["start_tick"] = tick + DAY_TICKS
		var st: Dictionary = s.get("events", {}).get("storm", {})
		if not st.is_empty():
			var count: int = int(st.get("count", 0))
			h["done_count"]["dust_storm"] = count
			h["seen"]["dust_storm"] = count
			if bool(st.get("scheduled", false)):
				var phase: String = String(st.get("phase", "none"))
				var ev := {"id": 1, "kind": "dust_storm", "at": int(st["at"]), "end": int(st["end"]), "pos": Vector2(128, 128),
					"radius": 0.0, "severity": 1, "detected_tick": tick if phase != "none" else -1,
					"phase": "active" if phase == "active" else ("warning" if phase == "warning" else "scheduled"),
					"countered": false, "hits": [], "result": {}}
				h["next_id"] = 2
				if phase == "active":
					h["active"].append(ev)
				else:
					h["queue"].append(ev)
				var gap: float = Rng.range_float(s["rng"], "hazard", 3.0, 5.0)
				var nxt: int = int(st["end"]) + int(gap * float(DAY_TICKS))
				h["next_at"]["dust_storm"] = nxt - nxt % 10
		s["hazards"] = h
	var r: Dictionary = s["research"]
	if not r.has("packs_paid"):
		r["packs_paid"] = {}
	for tech in r.get("paid", {}):
		r["packs_paid"][tech] = true
	for aid in s["agents"]:
		if not s["agents"][aid].has("use"):
			s["agents"][aid]["use"] = {}
	if not s["ship"].has("cargo"):
		s["ship"]["cargo"] = ""
	# No alert_track: the first check after the load drops the old issues that are no longer
	# true and raises the true ones again (critical at once), as version 2 did.
	var env: Dictionary = s.get("env", {})
	if not env.has("wind_mult"):
		env["wind_mult"] = 1.0

static func _rename_key(d: Dictionary, from: String, to: String) -> void:
	if not d.has(from):
		return
	d[to] = int(d.get(to, 0)) + int(d[from])
	d.erase(from)

static func slot_path(slot: String) -> String:
	return "user://saves/%s.fhsave" % slot

## Atomic: write a temporary file, prove it decodes, then replace the slot.
## On failure the previous save stays untouched (spec 14).
static func write_slot(slot: String, state: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var bytes: PackedByteArray = encode(state)
	var tmp: String = slot_path(slot + ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Storage is not writable (error %d). The previous save is kept." % FileAccess.get_open_error()}
	f.store_buffer(bytes)
	f.close()
	var check: Dictionary = decode(FileAccess.get_file_as_bytes(tmp))
	if not check["ok"] or int(check["state"]["tick"]) != int(state["tick"]):
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "error": "The new save did not verify. The previous save is kept."}
	var err: int = DirAccess.rename_absolute(tmp, slot_path(slot))
	if err != OK:
		DirAccess.remove_absolute(slot_path(slot))
		err = DirAccess.rename_absolute(tmp, slot_path(slot))
	if err != OK:
		return {"ok": false, "error": "The save could not be moved into place (error %d)." % err}
	return {"ok": true, "error": "", "bytes": bytes.size()}

static func read_slot(slot: String) -> Dictionary:
	var path: String = slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "No save in this slot."}
	return decode(FileAccess.get_file_as_bytes(path))

## Three rotating autosaves: the new one is verified first, only then the old ones move.
static func autosave(state: Dictionary, slots: int = 3) -> Dictionary:
	var res: Dictionary = write_slot("autosave_new", state)
	if not res["ok"]:
		return res
	DirAccess.remove_absolute(slot_path("autosave_%d" % slots))
	for i in range(slots - 1, 0, -1):
		if FileAccess.file_exists(slot_path("autosave_%d" % i)):
			DirAccess.rename_absolute(slot_path("autosave_%d" % i), slot_path("autosave_%d" % (i + 1)))
	DirAccess.rename_absolute(slot_path("autosave_new"), slot_path("autosave_1"))
	return res

static func list_slots() -> Array:
	var out: Array = []
	var d := DirAccess.open("user://saves")
	if d == null:
		return out
	for name in d.get_files():
		if not name.ends_with(".fhsave"):
			continue
		var slot: String = name.trim_suffix(".fhsave")
		if slot.ends_with(".tmp") or slot == "autosave_new":
			continue
		out.append({"slot": slot, "modified": FileAccess.get_modified_time("user://saves/" + name)})
	out.sort_custom(func(a, b): return int(a["modified"]) > int(b["modified"]) if int(a["modified"]) != int(b["modified"]) else String(a["slot"]) < String(b["slot"]))
	return out

static func digest(state: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(state))
	return ctx.finish().hex_encode()
