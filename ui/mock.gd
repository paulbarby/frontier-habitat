extends RefCounted
## Made-up hazard, maintenance and lab rows for layout checks and screenshots, used before
## SIM's version-3 systems exist. Only the automation command `uimock` sets them, and only
## with the boot parameter debug=1. The interface marks nothing as mock: never use it in play.
## Places are relative to the lander; the machines and labs are real structures of the colony.

static func build(sim, what: String) -> Dictionary:
	var out := {"t0": Time.get_ticks_msec(), "shelter": false}
	var st: Dictionary = sim.state
	var lid: int = int(st.get("lander_id", -1))
	var c: Vector2 = st["buildings"][lid]["pos"] if st["buildings"].has(lid) else sim.world.center
	if what in ["hazards", "all"]:
		out["forecast"] = [
			{"id": 9001, "kind": "meteor", "eta_s": 24.0, "pos": c + Vector2(99, -99), "radius": 8.0, "severity": 2, "countered": false},
			{"id": 9002, "kind": "solar_flare", "eta_s": 95.0, "severity": 1, "countered": false},
			{"id": 9003, "kind": "quake", "eta_s": 262.0, "pos": c + Vector2(-300, 20), "radius": 110.0, "severity": 2, "countered": true,
				"advice": "Seismic dampers cover it. Corridors lose less health."},
		]
		out["active"] = [{"id": 9000, "kind": "wind_storm", "left_s": 71.0, "severity": 2, "countered": false, "active": true}]
	if what in ["hazards", "maintenance", "all"]:
		var risk: Array = []
		var specs := [[82.0, 90.0, 140.0, "mechanical"], [70.0, 88.0, 410.0, "electrical"], [66.0, 80.0, 905.0, "seal"]]
		for id in st["buildings"]:
			var b: Dictionary = st["buildings"][id]
			var def: Dictionary = sim.bdef(String(b["def"]))
			if String(b.get("state", "")) != "active" or not (def.has("recipe") or bool(def.get("automatic", false))):
				continue
			var sp: Array = specs[risk.size()]
			risk.append({"id": id, "wear": sp[0], "fail_at": sp[1], "eta_s": sp[2], "fault": sp[3]})
			if risk.size() >= specs.size():
				break
		out["at_risk"] = risk
	if what in ["traffic", "all"]:
		out["traffic"] = {"credits": 250, "notices": [{"code": "tourists_no_bed", "count": 3, "text": "3 tourists have no bed. The fee drops."}],
			"ships": [{"id": 9100, "kind": "liner", "name": "Tourist liner", "phase": "landed", "answer": "grant", "t_s": 480.0, "text": "6 tourists want beds, meals and comfort.",
				"offer": {"people": 6, "fee": 40}, "pad_pos": null}],
			"forecast": [
			{"id": 9101, "kind": "trader", "name": "Trader", "phase": "forecast", "answer": "grant", "eta_s": 40.0, "text": "",
				"offer": {"sells": {"electronics": {"units": 12, "price": 14}, "glass": {"units": 15, "price": 6}, "medicine": {"units": 8, "price": 22},
					"metal": {"units": 6, "price": 7}, "spare_parts": {"units": 16, "price": 13}, "exotic": {"units": 5, "price": 41}, "polymer": {"units": 9, "price": 5}},
					"buys": {"biomass": {"units": 6, "price": 1}, "glass": {"units": 4, "price": 4}, "metal": {"units": 5, "price": 5}, "silicate": {"units": 5, "price": 1}}}},
			{"id": 9102, "kind": "shuttle", "name": "Immigrant shuttle", "phase": "forecast", "answer": "grant", "eta_s": 120.0, "text": "4 settlers want to join the colony.",
				"offer": {"roles": ["scientist", "technician", "grower", "medic"]}},
			{"id": 9103, "kind": "liner", "name": "Tourist liner", "phase": "forecast", "answer": "deny", "eta_s": 300.0, "text": "6 tourists want beds, meals and comfort.",
				"offer": {"people": 6, "fee": 40}},
			{"id": 9104, "kind": "science", "name": "Science ship", "phase": "forecast", "answer": "grant", "eta_s": 500.0, "text": "2 scientists want to use your labs.",
				"offer": {"buys": {"pack_basic": {"units": 6, "price": 9}}}}]}
	if what in ["labs", "all"]:
		var labs := {}
		var k := 0
		for id in st["buildings"]:
			var b: Dictionary = st["buildings"][id]
			if bool(sim.bdef(String(b["def"])).get("research_lab", false)):
				var boosted: bool = k % 2 == 0
				labs[id] = {"known": true, "mult": 1.2, "mult_boosted": 2.4 if boosted else 1.2, "boosted": boosted, "boost": 2.0, "can_work": true,
					"packs": {"pack_basic": 3} if boosted else {}, "focus": "science" if k == 0 else "", "scientists": 2 - k % 2}
				k += 1
		out["labs"] = labs
	return out
