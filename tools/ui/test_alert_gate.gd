extends SceneTree
## Test of the alert toast rules and the steady alert list (docs/V3_DESIGN.md §2, UI side).
##   node tools/godot.mjs script res://tools/ui/test_alert_gate.gd
##
## Part A drives ui/hud/alert_gate.gd with made-up alert streams, one update per game
## second, including the version-2 defect: a harvester whose "output blocked" alert goes on
## and off every few seconds because a carrier takes one unit and the buffer fills again.
## Part B runs the real simulation from the showcase saves for 300 s with the gate attached
## and counts toasts per alert and cards that disappear and come back.
## Prints PASS/FAIL lines and exits 1 on any failure.

const AlertGate = preload("res://ui/hud/alert_gate.gd")
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

var fails := 0

func _init() -> void:
	part_a()
	part_b()
	print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

static func inc(key: String, code: String, sev: int, text: String = "", cons: Array = []) -> Dictionary:
	return {"issue": {"key": key, "code": code, "severity": sev, "text": text if text != "" else key, "action": "", "entities": [], "forecast": -1.0}, "consequences": cons}

## Runs `seconds` updates; `stream.call(t) -> Array` gives the incidents at second t.
## Returns {toasts, card_gaps, max_cards}: card_gaps counts seconds where an alert that was
## on the card list is missing although it comes back later (the "pops up and disappears").
func run(gate, seconds: int, stream: Callable, quiet_until: int = -1) -> Dictionary:
	var toasts: Array = []
	var shown_prev := {}
	var gaps := 0
	var ever := {}
	for t in seconds:
		var cur: Array = stream.call(t)
		for i in gate.update(cur, float(t), t < quiet_until):
			toasts.append([t, AlertGate.ident(i)])
		var shown := {}
		for row in gate.display(cur):
			shown[String(row["ident"])] = true
		for k in ever:
			if shown_prev.has(k) and not shown.has(k):
				gaps += 1     # a card went away; counted again if it returns (see below)
		for k in shown:
			ever[k] = true
		shown_prev = shown
	return {"toasts": toasts, "gaps": gaps}

## Seconds a card vanished and later came back (a visible flicker).
func flickers(gate, seconds: int, stream: Callable) -> int:
	var vis: Array = []
	for t in seconds:
		var cur: Array = stream.call(t)
		gate.update(cur, float(t))
		var shown := {}
		for row in gate.display(cur):
			shown[String(row["ident"])] = true
		vis.append(shown)
	var n := 0
	var keys := {}
	for s in vis:
		for k in s:
			keys[k] = true
	for k in keys:
		var was := false
		var gone := false
		for s in vis:
			if s.has(k):
				if gone:
					n += 1
				was = true
				gone = false
			elif was:
				gone = true
	return n

func part_a() -> void:
	print("-- part A: made-up alert streams, one update per game second")
	# 1. The version-2 defect, notice level: blocked on for 3 s, off for 1 s, 300 s.
	var flap1 := func(t: int) -> Array:
		return [inc("blocked:12", "output_blocked", 1, "East regolith harvester: output blocked.")] if t % 4 != 3 else []
	var g = AlertGate.new()
	var r: Dictionary = run(g, 300, flap1)
	check("notice that flaps 75 times in 300 s: 0 toasts", (r["toasts"] as Array).is_empty(), str(r["toasts"]))
	check("notice that flaps: the card never disappears", flickers(AlertGate.new(), 300, flap1) == 0)
	# 2. The same at warning level (a simulation that raises it as a warning).
	var flap2 := func(t: int) -> Array:
		return [inc("blocked:12", "output_blocked", 2)] if t % 4 != 3 else []
	g = AlertGate.new()
	r = run(g, 300, flap2)
	check("warning that flaps 75 times in 300 s: exactly 1 toast", (r["toasts"] as Array).size() == 1, str(r["toasts"]))
	check("warning that flaps: the card never disappears", flickers(AlertGate.new(), 300, flap2) == 0)
	# 3. Two harvesters blocked in turn (version-2 keys blocked:12 and blocked:14): one alert.
	var two := func(t: int) -> Array:
		var out: Array = []
		if t % 6 < 3:
			out.append(inc("blocked:12", "output_blocked", 2))
		if t % 6 >= 2:
			out.append(inc("blocked:14", "output_blocked", 2))
		return out
	g = AlertGate.new()
	r = run(g, 300, two)
	check("two machines blocked in turn: 1 toast", (r["toasts"] as Array).size() == 1, str(r["toasts"]))
	# 4. The text changes every second (numbers in it) but the key does not: 1 toast.
	var numbers := func(t: int) -> Array:
		return [inc("storage_full", "storage_full", 2, "Storage is full. %d machines cannot put output anywhere." % (1 + t % 5))]
	g = AlertGate.new()
	r = run(g, 300, numbers)
	check("changing numbers in the text: 1 toast", (r["toasts"] as Array).size() == 1, str(r["toasts"]))
	# 5. Clears, comes back after 100 s (inside 180 s): no second toast.
	var back100 := func(t: int) -> Array:
		return [inc("power:1", "power", 3)] if t < 20 or (t >= 120 and t < 140) else []
	g = AlertGate.new()
	r = run(g, 300, back100)
	check("back 100 s after it cleared: 1 toast", (r["toasts"] as Array).size() == 1, str(r["toasts"]))
	# 6. Clears, comes back after 200 s (after 180 s): a second toast.
	var back200 := func(t: int) -> Array:
		return [inc("power:1", "power", 3)] if t < 20 or (t >= 220 and t < 240) else []
	g = AlertGate.new()
	r = run(g, 300, back200)
	check("back 200 s after it cleared: 2 toasts", (r["toasts"] as Array).size() == 2, str(r["toasts"]))
	# 7. A consequence that becomes a root (its cause cleared): no new toast.
	var promote := func(t: int) -> Array:
		if t < 30:
			return [inc("power:1", "power", 3, "", [{"key": "crop:5", "code": "crop_risk", "severity": 2, "text": "crop"}])]
		return [inc("crop:5", "crop_risk", 2)]
	g = AlertGate.new()
	r = run(g, 60, promote)
	check("consequence becomes a root: only the root toasted once", (r["toasts"] as Array).size() == 1 and r["toasts"][0][1] == "power:1", str(r["toasts"]))
	# 8. Present at load (grace): recorded, no toast.
	var always := func(_t: int) -> Array:
		return [inc("water:2", "water", 3)]
	g = AlertGate.new()
	r = run(g, 60, always, 30)
	check("alert already there at load: 0 toasts", (r["toasts"] as Array).is_empty(), str(r["toasts"]))
	# 9. A one-off alert that clears is held at most MIN_SHOW s after it first showed.
	var once := func(t: int) -> Array:
		return [inc("x", "x", 2)] if t >= 5 and t < 8 else []
	g = AlertGate.new()
	var last_shown := -1
	for t in 60:
		var cur: Array = once.call(t)
		g.update(cur, float(t))
		if not g.display(cur).is_empty():
			last_shown = t
	check("one-off alert: card gone 10 s after it first showed", last_shown == 14, "last shown at %d s" % last_shown)

func part_b() -> void:
	print("-- part B: the real simulation, 300 game seconds from each showcase save, gate attached")
	var dir := "res://content/saves"
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("showcase") and f.ends_with(".fhsave"):
			files.append(dir.path_join(f))
	files.sort()
	for path in files:
		var res: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))
		if not res["ok"]:
			check("load " + path, false, String(res.get("error", "")))
			continue
		var sim = Sim.new()
		sim.load_state(res["state"])
		var gate = AlertGate.new()
		gate.update(sim.alerts.incidents(), sim.seconds(), true)
		var hz: int = int(sim.bal["tick_hz"])
		var per_key := {}
		var raw_back := {}     # root key -> times it went away and came back (simulation)
		var card_back := {}    # ident -> times its card went away and came back (interface)
		var raw_seen := {}
		var raw_gone := {}
		var vis_seen := {}
		var vis_gone := {}
		for sec in 300:
			for i in hz:
				sim.step()
			var cur: Array = sim.alerts.incidents()
			for issue in gate.update(cur, sim.seconds()):
				var k: String = AlertGate.ident(issue)
				per_key[k] = int(per_key.get(k, 0)) + 1
			var raw := {}
			for x in cur:
				raw[String(x["issue"]["key"])] = true
			_track(raw, raw_seen, raw_gone, raw_back)
			var vis := {}
			for row in gate.display(cur):
				vis[String(row["ident"])] = true
			_track(vis, vis_seen, vis_gone, card_back)
		var twice: Array = []
		var total := 0
		for k in per_key:
			total += int(per_key[k])
			if int(per_key[k]) > 1:
				twice.append(k)
		var flappy: Array = []
		for k in card_back:
			if int(card_back[k]) > 1:
				flappy.append("%s x%d" % [k, card_back[k]])
		var name: String = path.get_file()
		print("   %s: day %d, %d toasts %s, %d alert keys; simulation keys that went and came back: %s; cards that went and came back: %s" % [name, sim.util.day_number(), total, str(per_key), vis_seen.size(), str(raw_back), str(card_back)])
		check("%s: no alert toasted twice in 300 s" % name, twice.is_empty(), str(per_key))
		check("%s: no card went away and came back more than once" % name, flappy.is_empty(), str(flappy))
		sim.dispose()

## Counts, per key, how often it went away and came back.
static func _track(now: Dictionary, seen: Dictionary, gone: Dictionary, back: Dictionary) -> void:
	for k in seen:
		if not now.has(k):
			gone[k] = true
	for k in now:
		if gone.has(k):
			back[k] = int(back.get(k, 0)) + 1
			gone.erase(k)
		seen[k] = true
