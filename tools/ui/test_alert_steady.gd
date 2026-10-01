extends SceneTree
## A condition that stays true shows one steady alert entry (Paul, 2026-09-28: "Output blocked at 1
## machine: Mine 1" popped in and out of the Alerts panel), headless:
##   node tools/godot.mjs script res://tools/ui/test_alert_steady.gd
## 600 simulation seconds with a mine whose output buffer stays full, is emptied a little every 45 s
## and fills again. Each second: the panel's visible entries. The blocked entry never leaves once
## it shows, and the visible list never reorders while its set of alerts is the same.

var main
var fails := 0
var _n := 0
var _step := 0
var mine := {}
var secs := 0
var first_seen := -1
var gaps: Array = []
var reorders: Array = []
var last_keys: Array = []
var max_changes := 0
var _last_max := -1
var samples: Array = []
var disp_first := -1
var disp_gaps: Array = []
var last_set: Array = []

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

static func _is_blocked(key: String) -> bool:
	return key.begins_with("blocked") or key.contains("output_blocked")

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
			main._on_cmd("speed 0")
			sim = main.sim
			# A working mine of the showcase (powered, staffed), its output buffer full (test set-up).
			for id in sim.state["buildings"]:
				var b: Dictionary = sim.state["buildings"][id]
				if String(b["def"]) == "mine" and String(b["state"]) == "active" and bool(b.get("powered", false)):
					mine = b
					break
			check("a powered mine in showcase_v4", not mine.is_empty())
			# The goals tracker folded, so the alerts panel has room for its cards (as when a player folds it).
			if not hud.goals.collapsed:
				hud.goals._toggle()
			hud.alerts.hold_s = 0.3   # test: real time runs about 100 times faster than play here
			if mine.is_empty():
				_step = 99
				return false
			_fill()
			_step = 1
			_n = 0
		1:
			# One simulation second per frame, then the HUD's two refresh beats.
			for i in int(sim.bal["tick_hz"]):
				sim.step()
			secs += 1
			if secs % 45 == 0:
				var n: int = sim.inv.count(int(mine["inv_out"]), "ore")
				sim.inv.consume(int(mine["inv_out"]), "ore", mini(n, 4), "test")               # test set-up: the buffer empties a little
			elif secs % 45 == 20:
				_fill()                                                                          # and fills again
			hud.watchers.check()   # as hud._refresh: the gate, then the panel (2.5 Hz there; once a game second here)
			hud.alerts.refresh()
			var keys: Array = []
			for c in hud.alerts._cards:
				keys.append(String(c["key"]))
			var has: bool = false
			for k in keys:
				if _is_blocked(k):
					has = true
			if has and first_seen < 0:
				first_seen = secs
			# The gate's list (what the panel draws from): the blocked alert, once there, stays.
			var disp: Array = hud.watchers.gate.display(sim.alerts.incidents())
			var idents: Array = disp.map(func(x): return String(x["ident"]))
			if idents.has("output_blocked") and disp_first < 0:
				disp_first = secs
			if disp_first >= 0 and not idents.has("output_blocked"):
				disp_gaps.append(secs)
			# On screen: it leaves only when the set of alerts changed (a higher one took its place).
			if first_seen >= 0 and not has and idents.has("output_blocked"):
				var sset: Array = idents.duplicate()
				sset.sort()
				if sset == last_set:
					gaps.append(secs)
			var s2: Array = idents.duplicate()
			s2.sort()
			last_set = s2
			# A live alert that clears goes down the list (the gate holds it, greyed): a change of state, not a
			# reorder. Only the live alerts must keep their order (2026-10-01: the dock shows 8 cards).
			var held: Array = []
			for x in disp:
				if bool(x["cleared"]):
					held.append(String(x["issue"].get("key", "")))
			var live_keys: Array = keys.filter(func(k): return not held.has(k))
			if live_keys.size() == last_keys.size() and live_keys != last_keys:
				var same := true
				for k in live_keys:
					if not last_keys.has(k):
						same = false
				if same:
					reorders.append("%d: %s -> %s" % [secs, str(last_keys), str(live_keys)])
			if secs == 30:
				hud.alerts.max_changes = 0   # after the load settles: count only changes in play
			max_changes = hud.alerts.max_changes
			if secs % 60 == 0:
				samples.append("t%.1f %d:%s max=%d more=%s size=%s inc=%d" % [float(Time.get_ticks_msec()) / 1000.0, secs, str(keys), hud.alerts._max, hud.alerts._more.visible, hud.alerts.size, sim.alerts.incidents().size()])   # 2026-10-01: no fit to the minimap (the dock scrolls)
			last_keys = keys.filter(func(k): return not held.has(k))
			if secs >= 600:
				_step = 2
			_n = 7
		2:
			print("samples ", samples.slice(0, 4))
			check("the blocked mine has an entry in the alert list", disp_first >= 0, "first at %d s" % disp_first)
			check("the entry never leaves the list in 600 s (the gate holds it through the buffer's ups and downs)", disp_gaps.is_empty(), "%d gaps, first %s" % [disp_gaps.size(), str(disp_gaps.slice(0, 6))])
			check("on screen, it never leaves while the set of alerts is the same", gaps.is_empty(), "%d gaps, first %s" % [gaps.size(), str(gaps.slice(0, 6))])
			check("the visible list never reorders while its set is the same", reorders.is_empty(), str(reorders.slice(0, 3)))
			check("the number of cards shown settles (no in-out oscillation)", max_changes <= 2, "%d changes of the card count in 570 s" % max_changes)
			# The tight case (goals open, less room): the card count must still settle.
			hud.goals._toggle()
			hud.alerts.max_changes = 0
			_step = 3
			_n = 0
			secs = 0
			return false
		3:
			for i in int(sim.bal["tick_hz"]):
				sim.step()
			secs += 1
			hud.watchers.check()   # as hud._refresh: the gate, then the panel (2.5 Hz there; once a game second here)
			hud.alerts.refresh()
			if secs >= 120:
				check("goals open (less room): the card count settles too", hud.alerts.max_changes <= 3, "%d changes in 120 s" % hud.alerts.max_changes)
				_step = 99
			_n = 7
			return false
		99:
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false

func _fill() -> void:
	var sim = main.sim
	var inv: int = int(mine["inv_out"])
	var free: int = sim.inv.free_space(inv)
	if free > 0:
		sim.inv.add_new_forced(inv, "ore", free, "test")                                    # test set-up: the buffer full
