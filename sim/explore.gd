extends RefCounted
## Exploration (docs/V4_DESIGN.md section 5): fog of war, points of interest (POIs) with finds,
## and survey satellites. Only on the 2,560 m map (world version 4); older maps have no fog.
## Numbers: content/terrain_v4.json "explore".
##
## state.fog  = {cell (m), n, bits: PackedByteArray n*n (1 = explored), rev, count}
## state.pois = [{id, kind, x, y, found, visited, need}]  (need: "any" | "on_foot" | "scientist")
## state.sats = [{id, name, t0, next_s, band, bands}]
## Revealing: colonists outside see reveal_walk m round them, rovers reveal_rover m, hoppers
## reveal_hopper m (x (1 + research reveal_mult)); a satellite with an uplink (a powered comms
## tower) reveals one band of the map every band_s seconds. A revealed deposit is surveyed (by a
## satellite only with Deep Scan); a revealed POI is found. A POI is visited when a colonist
## comes within visit_r m of it (the need says who may): its finds go into the vehicle there, else
## onto the ground.

const Rng = preload("res://sim/rng.gd")

var sim

func _init(s) -> void:
	sim = s

func cfg() -> Dictionary:
	return sim.content["terrain_v4"]["explore"]

func active() -> bool:
	return sim.state.has("fog")

# ---------------------------------------------------------------- fog
func fog() -> Dictionary:
	return sim.state.get("fog", {})

## True when p is explored (always on maps without fog).
func explored(p: Vector2) -> bool:
	var f = sim.state.get("fog")
	if f == null:
		return true
	var n: int = int(f["n"])
	var i: int = clampi(int(p.x / float(f["cell"])), 0, n - 1)
	var j: int = clampi(int(p.y / float(f["cell"])), 0, n - 1)
	return (f["bits"] as PackedByteArray)[j * n + i] != 0

## Share of the map explored, 0..1.
func explored_share() -> float:
	var f = sim.state.get("fog")
	if f == null:
		return 1.0
	return float(f["count"]) / float(int(f["n"]) * int(f["n"]))

## Marks the cells within r of p explored. survey: deposits there become surveyed. Returns
## the number of new cells.
func reveal(p: Vector2, r: float, survey: bool = true) -> int:
	var f = sim.state.get("fog")
	if f == null:
		return 0
	var cell: float = float(f["cell"])
	var n: int = int(f["n"])
	var bits: PackedByteArray = f["bits"]
	var i0: int = clampi(int((p.x - r) / cell), 0, n - 1)
	var i1: int = clampi(int((p.x + r) / cell), 0, n - 1)
	var j0: int = clampi(int((p.y - r) / cell), 0, n - 1)
	var j1: int = clampi(int((p.y + r) / cell), 0, n - 1)
	var r2: float = r * r
	var added := 0
	for j in range(j0, j1 + 1):
		var cy: float = (float(j) + 0.5) * cell - p.y
		for i in range(i0, i1 + 1):
			var cx: float = (float(i) + 0.5) * cell - p.x
			if cx * cx + cy * cy <= r2 and bits[j * n + i] == 0:
				bits[j * n + i] = 1
				added += 1
	if added > 0:
		f["bits"] = bits
		f["count"] = int(f["count"]) + added
		f["rev"] = int(f["rev"]) + 1
		_after_reveal(p, r + cell, survey)
	return added

func _after_reveal(p: Vector2, r: float, survey: bool) -> void:
	if survey:
		for d in sim.state["deposits"]:
			if not bool(d.get("surveyed", true)) and Vector2(d["x"], d["y"]).distance_to(p) <= r and explored(Vector2(d["x"], d["y"])):
				d["surveyed"] = true
				sim.log_event("deposit_found", "A %s deposit was found." % String(d.get("kind", "metal")).replace("_", " "), [int(d["id"])], 1)
	for poi in sim.state.get("pois", []):
		if not bool(poi["found"]) and Vector2(poi["x"], poi["y"]).distance_to(p) <= r and explored(Vector2(poi["x"], poi["y"])):
			poi["found"] = true
			sim.log_event("poi_found", "Found: %s." % poi_name(poi), [int(poi["id"])], 1)

# ---------------------------------------------------------------- set-up
## New game on the v4 map: the fog with the landing area known, and the POIs.
func setup() -> void:
	if sim.world == null or int(sim.world.version) < 4:
		return
	var c: Dictionary = cfg()
	var cell: float = float(c["fog_cell"])
	var n: int = int(ceil(float(sim.world.size) / cell))
	var bits := PackedByteArray()
	bits.resize(n * n)
	sim.state["fog"] = {"cell": cell, "n": n, "bits": bits, "rev": 0, "count": 0}
	sim.state["pois"] = _make_pois()
	sim.state["sats"] = []
	reveal(sim.world.center, float(sim.content["terrain_v4"].get("known_radius", 300.0)))

## A v4 save from before the fog (V4 milestones 1-6): the fog is made, with the landing area
## and the ground round every structure and colonist known; the POIs are made.
func ensure() -> void:
	if sim.world == null or int(sim.world.version) < 4 or active():
		return
	setup()
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["kind"] != "link":
			reveal(b["pos"], 80.0)
	for aid in sim.state["agents"]:
		reveal(sim.state["agents"][aid]["pos"], 40.0)

func _make_pois() -> Array:
	var c: Dictionary = cfg()
	var w = sim.world
	var seed_v: int = int(sim.state["seed"])
	var out: Array = []
	var kinds: Dictionary = c["pois"]
	var keys: Array = kinds.keys()
	keys.sort()
	var k_i := 0
	for kind in keys:
		k_i += 1
		var kc: Dictionary = kinds[kind]
		for n in int(kc["count"]):
			for attempt in 60:
				var h1: float = Rng.hash2(k_i * 100 + n, attempt, seed_v ^ 0x5017)
				var h2: float = Rng.hash2(k_i * 100 + n, attempt + 1000, seed_v ^ 0x5017)
				var dist: float = lerpf(float(c["poi_min_dist"]), float(c["poi_max_dist"]), h2)
				var p: Vector2 = w.center + Vector2.RIGHT.rotated(h1 * TAU) * dist
				if not _poi_place_ok(kind, p, out):
					continue
				out.append({"id": sim.new_id(), "kind": kind, "x": snappedf(p.x, 0.5), "y": snappedf(p.y, 0.5), "found": false, "visited": false,
					"need": String(kc.get("need", "any"))})
				break
	return out

func _poi_place_ok(kind: String, p: Vector2, have: Array) -> bool:
	var w = sim.world
	var m: float = 60.0
	if p.x < m or p.y < m or p.x > float(w.size) - m or p.y > float(w.size) - m:
		return false
	for o in have:
		if Vector2(o["x"], o["y"]).distance_to(p) < float(cfg()["poi_spacing"]):
			return false
	if not sim.nav.coarse_open_at(p):
		return false
	match kind:
		"cave":
			var dm: float = w.near_mountain(p)
			return dm > 0.0 and dm < 140.0
		"anomaly":
			return true           # a hopper reaches it when a rover cannot
		"meteorite_field":
			return sim.nav.rover_ok(p) and w.rocks_near(p, 60.0).size() >= 2
	return sim.nav.rover_ok(p)

func poi_name(poi: Dictionary) -> String:
	return String(cfg()["pois"].get(String(poi["kind"]), {}).get("name", String(poi["kind"]))).to_lower()

# ---------------------------------------------------------------- once a second
func tick_second() -> void:
	if not active():
		return
	var c: Dictionary = cfg()
	var mult: float = 1.0 + sim.research.bonus("reveal_mult")
	var rw: float = float(c["reveal_walk"]) * mult
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["where"] == "out" and not _seen_round(a["pos"], rw):
			reveal(a["pos"], rw)
	for vid in sim.vehicles.ids():
		var v: Dictionary = sim.vehicles.get_v(vid)
		if (v["crew"] as Array).is_empty():
			continue
		var rv: float = float(c["reveal_hopper"] if String(sim.vehicles.kind_of(v).get("move", "")) == "hopper" else c["reveal_rover"]) * mult
		if not _seen_round(v["pos"], rv):
			reveal(v["pos"], rv)
	_sats_second()
	_visits_second()

## Cheap test: the centre and four points at r are explored already.
func _seen_round(p: Vector2, r: float) -> bool:
	return explored(p) and explored(p + Vector2(r, 0)) and explored(p - Vector2(r, 0)) and explored(p + Vector2(0, r)) and explored(p - Vector2(0, r))

func _visits_second() -> void:
	var pois: Array = sim.state.get("pois", [])
	var vr: float = float(cfg()["visit_r"])
	# The people who can visit (outside or in a vehicle), found once a second and not once a POI
	# (cost: 130 people x every found POI).
	var field = null
	for poi in pois:
		if bool(poi["visited"]) or not bool(poi["found"]):
			continue
		if field == null:
			field = []
			for aid in sim.state["agents"]:
				var a0: Dictionary = sim.state["agents"][aid]
				if a0["state"] != "alive" or a0["kind"] == "visitor" or (a0["where"] != "out" and a0["where"] != "vehicle"):
					continue
				field.append(a0)
		var pp := Vector2(poi["x"], poi["y"])
		var who: Array = []
		var veh := {}
		for a in field:
			if (a["pos"] as Vector2).distance_to(pp) <= vr:
				who.append(a)
				if a["where"] == "vehicle" and veh.is_empty():
					veh = sim.vehicles.get_v(int(a["veh"]))
		if who.is_empty() or not _need_met(String(poi["need"]), who):
			continue
		_visit(poi, veh)

func _need_met(need: String, who: Array) -> bool:
	match need:
		"on_foot":
			for a in who:
				if a["where"] == "out":
					return true
			return false
		"scientist":
			for a in who:
				if a["role"] == "scientist":
					return true
			return false
	return true

func _visit(poi: Dictionary, veh: Dictionary) -> void:
	var kc: Dictionary = cfg()["pois"].get(String(poi["kind"]), {})
	poi["visited"] = true
	sim.stat_add("pois_visited", String(poi["kind"]), 1)
	var parts: Array = []
	var finds: Dictionary = kc.get("finds", {})
	if not finds.is_empty():
		var dst: int = -1
		if not veh.is_empty():
			dst = int(veh["cargo"])
		var keys: Array = finds.keys()
		keys.sort()
		for it in keys:
			var n: int = int(finds[it])
			var put := 0
			if dst != -1:
				put = sim.inv.add_new(dst, it, n, "find")
			if put < n:
				var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, Vector2(poi["x"], poi["y"]))
				sim.inv.add_new_forced(pile, it, n - put, "find")
			parts.append("%d %s" % [n, String(sim.content["items"][it].get("plural" if n > 1 else "name", sim.content["items"][it]["name"])).to_lower()])
	var rp: float = float(kc.get("rp", 0.0))
	if rp > 0.0:
		sim.research.add_rp(rp)
		parts.append("%d research points" % int(rp))
	if kc.has("deposit"):
		var dk: Dictionary = kc["deposit"]
		var kinds: Array = dk["kinds"]
		var kind: String = String(kinds[int(poi["id"]) % kinds.size()])
		var dep := {"id": sim.new_id(), "x": float(poi["x"]), "y": float(poi["y"]), "r": float(dk["r"]), "ore": int(dk["ore"]), "kind": kind,
			"tier": 2, "surveyed": true, "rich": true}
		sim.state["deposits"].append(dep)
		parts.append("a rich %s deposit" % kind.replace("_", " "))
	sim.log_event("poi_visited", "%s visited: %s." % [poi_name(poi).capitalize(), ", ".join(parts) if not parts.is_empty() else "nothing of use"], [int(poi["id"])], 1)

# ---------------------------------------------------------------- satellites
## A finished satellite order at a launch pad goes up (vehicles.add_build_work calls this).
func launch(pad: Dictionary) -> Dictionary:
	var sats: Array = sim.state.get("sats", [])
	if not sim.state.has("sats"):
		sim.state["sats"] = sats
	var c: Dictionary = cfg()
	var n: int = sats.size() + 1
	var s := {"id": sim.new_id(), "name": "Survey satellite %d" % n, "t0": int(sim.state["tick"]), "next_s": float(c["band_s"]),
		"band": (n - 1) * 3 % int(c["bands"]), "bands": 0}
	sats.append(s)
	sim.log_event("satellite_launched", "%s launched from %s. With an uplink it maps a band every %d s." % [s["name"], pad["name"], int(c["band_s"])], [int(pad["id"])], 1)
	return s

## True while a powered comms tower stands.
func uplink() -> bool:
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["def"] == "comms_tower" and b["state"] == "active" and bool(b["powered"]):
			return true
	return false

func _sats_second() -> void:
	var sats = sim.state.get("sats")
	if sats == null or (sats as Array).is_empty():
		return
	var c: Dictionary = cfg()
	var nb: int = int(c["bands"])
	if not uplink():
		return
	for s in sats:
		if int(s["bands"]) >= nb:
			continue
		s["next_s"] = float(s["next_s"]) - 1.0
		if float(s["next_s"]) > 0.0:
			continue
		s["next_s"] = float(c["band_s"])
		reveal_band(int(s["band"]), sim.research.is_done("exp_deep_scan") or sim.unlocked_all())
		s["band"] = (int(s["band"]) + 1) % nb
		s["bands"] = int(s["bands"]) + 1
		if int(s["bands"]) >= nb:
			sim.log_event("satellite_done", "%s has mapped the whole planet." % s["name"], [], 1)

## Reveals band b of the map (a strip across the map, west to east).
func reveal_band(band: int, survey: bool) -> void:
	var f: Dictionary = fog()
	var nb: int = int(cfg()["bands"])
	var n: int = int(f["n"])
	var cell: float = float(f["cell"])
	var j0: int = band * n / nb
	var j1: int = (band + 1) * n / nb
	var bits: PackedByteArray = f["bits"]
	var added := 0
	for j in range(j0, j1):
		for i in n:
			if bits[j * n + i] == 0:
				bits[j * n + i] = 1
				added += 1
	f["bits"] = bits
	f["count"] = int(f["count"]) + added
	f["rev"] = int(f["rev"]) + 1
	var y0: float = float(j0) * cell
	var y1: float = float(j1) * cell
	for poi in sim.state.get("pois", []):
		if not bool(poi["found"]) and float(poi["y"]) >= y0 and float(poi["y"]) < y1:
			poi["found"] = true
			sim.log_event("poi_found", "The satellite found: %s." % poi_name(poi), [int(poi["id"])], 1)
	if survey:
		for d in sim.state["deposits"]:
			if not bool(d.get("surveyed", true)) and float(d["y"]) >= y0 and float(d["y"]) < y1:
				d["surveyed"] = true

# ---------------------------------------------------------------- reads and debug
func pois() -> Array:
	return sim.state.get("pois", [])

func poi(id: int) -> Dictionary:
	for p in pois():
		if int(p["id"]) == id:
			return p
	return {}

func sats() -> Array:
	var out: Array = []
	var nb: int = int(cfg()["bands"])
	for s in sim.state.get("sats", []):
		out.append({"id": int(s["id"]), "name": s["name"], "bands_done": int(s["bands"]), "bands": nb, "next_s": float(s["next_s"]),
			"band": int(s["band"]), "uplink": uplink()})
	return out

## Debug: "reveal" {x, y, r}.
func debug_reveal(p: Dictionary) -> Dictionary:
	if not active():
		return {"ok": false, "code": "no_fog"}
	var n: int = reveal(Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))), clampf(float(p.get("r", 100.0)), 1.0, 4000.0))
	return {"ok": true, "code": "ok", "cells": n}
