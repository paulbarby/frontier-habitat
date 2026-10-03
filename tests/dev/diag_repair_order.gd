extends SceneTree
## DIAGNOSTIC (no game file is changed). Reproduces: "I order a colonist to repair a worn system and
## it never happens", for a colonist who is idle / at leisure / at a party / asleep.
##
## The repair order the UI gives (ui/hud/orders_window.gd "Work at..." -> ui/v4_data.gd _live_order):
##   sim.orders.check(a, {agents:[id], kind:"work_at", b:<structure id>}) then submit("order", p).
## The other UI route is the inspector / dashboard "Maintain now" button: submit("maintain", {id}).
##
##   FH_ORCHESTRATOR=1 node tools/godot.mjs script res://tests/dev/diag_repair_order.gd <names|all> <outdir> [seconds]
## Scenario names: see SCENARIOS. <outdir> gets diag_<name>.log (one line per second). Default 900 s.
## 1 game day = 600 s, 1 game hour = 25 s, so 900 s is 36 game hours. 15 game-clock minutes is only 6.25 s.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

const SAVE := "res://content/saves/showcase_v5.fhsave"
const SCENARIOS := {
	"idle_nospares": {"who": "idle", "spares": false, "cmd": "work_at"},
	"idle_spares": {"who": "idle", "spares": true, "cmd": "work_at"},
	"rec_spares": {"who": "rec", "spares": true, "cmd": "work_at"},
	"party_spares": {"who": "party", "spares": true, "cmd": "work_at"},
	"party_fresh_spares": {"who": "party_fresh", "spares": true, "cmd": "work_at"},
	"asleep_spares": {"who": "asleep", "spares": true, "cmd": "work_at"},
	"control_spares": {"who": "none", "spares": true, "cmd": "none"},
	"maintain_now": {"who": "none", "spares": true, "cmd": "maintain"},
	"maintain_now_nospares": {"who": "none", "spares": false, "cmd": "maintain"},
	"rec_go": {"who": "rec", "spares": true, "cmd": "go"},
	"party_go": {"who": "party", "spares": true, "cmd": "go"},
	"asleep_go": {"who": "asleep", "spares": true, "cmd": "go"},
}

var _dir := ""
var _file: FileAccess = null

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "all"
	_dir = args[1] if args.size() > 1 else ""
	var secs: int = int(args[2]) if args.size() > 2 else 900
	var names: Array = SCENARIOS.keys() if which == "all" else Array(which.split(","))
	for n in names:
		if not SCENARIOS.has(String(n)):
			print("unknown scenario ", n)
			continue
		_run(String(n), SCENARIOS[String(n)], secs)
	quit(0)

func _p(text: String) -> void:
	print(text)
	if _file != null:
		_file.store_line(text)

# ---------------------------------------------------------------- one scenario
func _run(name: String, spec: Dictionary, secs: int) -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes(SAVE))["state"])
	sim.run_seconds(5.0)
	_file = null
	if _dir != "":
		_file = FileAccess.open("%s/diag_%s.log" % [_dir, name], FileAccess.WRITE)
	_p("")
	_p("==================== %s  %s" % [name, str(spec)])
	var who := -1
	match String(spec["who"]):
		"idle": who = _find_idle(sim)
		"rec": who = _find_rec(sim)
		"asleep": who = _find_sleeper(sim)
		"party": who = _make_party_guest(sim, false)
		"party_fresh": who = _make_party_guest(sim, true)
	if who == -1 and String(spec["who"]) != "none":
		_p("NO SUBJECT FOUND for '%s'" % String(spec["who"]))
		if _file != null:
			_file.close()
			_file = null
		sim.dispose()
		return
	var base := 1
	if who != -1:
		base = int(sim.bases.home_of(sim.state["agents"][who]))
	var target: int = _worn_target(sim, base)
	if target == -1:
		_p("NO WORN STRUCTURE in base %d" % base)
		return
	var tb: Dictionary = sim.state["buildings"][target]
	var wr: Dictionary = sim.hazards.hs()["wear"][target]
	_p("subject: %s" % _who_text(sim, who))
	_p("target : bld %d '%s' state=%s wear %.1f of fail_at %.1f (ratio %.2f, WORN badge shows from 0.75) fault=%s base=%d pos=%s" % [target, tb["name"], tb["state"], float(wr["w"]), float(wr["fail_at"]), float(wr["w"]) / float(wr["fail_at"]), wr["fault"], base, str(tb["pos"])])
	if bool(spec["spares"]):
		_p("SETUP (test set-up, not a player action): %s" % _add_spares(sim, base))
	else:
		_p("SETUP: none. Stock as loaded: %s" % _stock_text(sim))
	var t0: int = int(sim.state["tick"])
	var tasks_before: Array = _board_for(sim, target)
	_p("board for target before the order: %s" % str(tasks_before))
	# ---- the command
	var cmd: String = String(spec["cmd"])
	if cmd == "work_at" or cmd == "go":
		var a: Dictionary = sim.state["agents"][who]
		var p := {"agents": [who], "kind": cmd}
		if cmd == "work_at":
			p["b"] = target
		else:
			p["x"] = (tb["pos"] as Vector2).x
			p["y"] = (tb["pos"] as Vector2).y
		var chk: Dictionary = sim.orders.check(a, p)
		_p("orders.check -> %s" % str(chk))
		var cid: int = sim.submit("order", p)
		sim.step()
		_p("order result -> %s" % str(sim.cmds.results.get(cid, {})))
		_p("immediately after the order: plan_kind=%s goal='%s' order=%s plan=%s" % [a["plan_kind"], a["goal"], str(a.get("order", "-")), str(_plan_ops(a))])
	elif cmd == "maintain":
		var cid2: int = sim.submit("maintain", {"id": target})
		sim.step()
		_p("maintain result -> %s" % str(sim.cmds.results.get(cid2, {})))
	# ---- run and log every second
	var plan_secs := {}
	var claimers := {}
	var first_claim_s := -1
	var first_work_s := -1
	var done_s := -1
	var order_gone_s := -1
	var last_sig := ""
	var n0: int = int(wr["n"])
	for s in range(1, secs + 1):
		sim.run_seconds(1.0)
		var a2: Dictionary = sim.state["agents"].get(who, {}) if who != -1 else {}
		var line := _line(sim, s, a2, target)
		if _file != null:
			_file.store_line(line)
		var sig: String = _sig(sim, a2, target)
		if s <= 8 or sig != last_sig or s % 120 == 0:
			print(line)
		last_sig = sig
		# tracking
		if not a2.is_empty():
			var pk: String = "%s/%s" % [a2["plan_kind"], _short_goal(String(a2["goal"]))]
			plan_secs[pk] = int(plan_secs.get(pk, 0)) + 1
			if not a2.has("order") and order_gone_s == -1 and cmd == "work_at":
				order_gone_s = s
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if int(t["bld"]) == target and (t["kind"] == "maintain" or t["kind"] == "repair") and int(t["owner"]) != -1:
				if first_claim_s == -1:
					first_claim_s = s
				claimers[int(t["owner"])] = true
				if String(t["state"]) == "working" and first_work_s == -1:
					first_work_s = s
		var rec2: Dictionary = sim.hazards.hs()["wear"].get(target, {})
		if done_s == -1 and not rec2.is_empty() and int(rec2["n"]) > n0:
			done_s = s
	# ---- summary
	_p("--- SUMMARY %s" % name)
	_p("target wear reset (maintenance/repair done): %s" % ("at t+%d s" % done_s if done_s != -1 else "NEVER in %d s" % secs))
	_p("a maintain/repair task of the target first owned: %s; first 'working': %s" % [("t+%d s" % first_claim_s) if first_claim_s != -1 else "never", ("t+%d s" % first_work_s) if first_work_s != -1 else "never"])
	var names: Array = []
	for c in claimers:
		names.append("%s (%s)" % [sim.state["agents"][c]["name"], sim.state["agents"][c]["role"]])
	_p("colonists who owned a maintain/repair task of the target: %s%s" % [str(names), "  <-- the subject" if claimers.has(who) and who != -1 else ""])
	if who != -1:
		var af: Dictionary = sim.state["agents"][who]
		_p("subject at the end: plan_kind=%s goal='%s' order=%s" % [af["plan_kind"], af["goal"], str(af.get("order", "-"))])
		_p("subject's order cleared at: %s" % ("t+%d s" % order_gone_s if order_gone_s != -1 else "still active at t+%d s" % secs if af.has("order") else "n/a"))
		var pk_list: Array = []
		for k in plan_secs:
			pk_list.append([int(plan_secs[k]), String(k)])
		pk_list.sort_custom(func(x, y): return x[0] > y[0])
		_p("subject's seconds by plan_kind/goal: %s" % str(pk_list.slice(0, 12)))
	for e in sim.state["log"]:
		if int(e["tick"]) >= t0 and ["maintained", "order_ended", "fault"].has(String(e["code"])):
			_p("  LOG t+%d s [%s] %s" % [(int(e["tick"]) - t0) / 10, e["code"], String(e["text"]).substr(0, 140)])
	var shown := 0
	for key in sim.state["issues"]:
		var iss: Dictionary = sim.state["issues"][key]
		if ["maintenance", "broken"].has(String(iss.get("code", ""))) and shown < 6:
			shown += 1
			_p("  ALERT shown to the player at the end: %s" % str(iss).substr(0, 420))
	if shown == 0:
		_p("  ALERT: no maintenance or broken alert at the end")
	if _file != null:
		_file.close()
		_file = null
	sim.dispose()

# ---------------------------------------------------------------- finding people
func _colonists_of(sim, base: int) -> Array:
	var out: Array = []
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or String(a.get("kind", "")) != "human" or a["where"] != "in":
			continue
		if base != -1 and int(sim.bases.home_of(a)) != base:
			continue
		out.append(a)
	return out

func _find_idle(sim) -> int:
	# Up to 180 s: the first technician, else the first other adult, with an empty plan or an idle plan.
	var fallback := -1
	for s in 180:
		for a in _colonists_of(sim, 1):
			if a.has("v5_nowork") or a.has("jailed") or a.has("order"):
				continue
			if (a["plan"] as Array).is_empty() or a["plan_kind"] == "idle":
				if a["role"] == "technician":
					return int(a["id"])
				if fallback == -1 and a["role"] != "security" and a["role"] != "hr":
					fallback = int(a["id"])
		if fallback != -1 and s >= 60:
			return fallback
		sim.run_seconds(1.0)
	return fallback

func _find_rec(sim) -> int:
	for s in 120:
		for a in _colonists_of(sim, 1):
			if a["role"] == "technician" and a["plan_kind"] == "rec" and sim.agents._step_op(a) == "rec" and not a.has("order"):
				return int(a["id"])
		sim.run_seconds(1.0)
	return -1

func _find_sleeper(sim) -> int:
	for s in 120:
		for a in _colonists_of(sim, 1):
			if a["role"] == "technician" and a["plan_kind"] == "sleep" and bool(a.get("sleeping", false)) and not a.has("order"):
				return int(a["id"])
		sim.run_seconds(1.0)
	return -1

## fresh: the least tired guest, so that a critical need (fatigue 85) does not end the party plan early.
func _make_party_guest(sim, fresh: bool) -> int:
	var vs: Array = sim.party.venues(1)
	if vs.is_empty():
		_p("no party venue in base 1")
		return -1
	var venue: int = int(vs[0]["building"])
	var cid: int = sim.submit("throw_party", {"building": venue, "hours": 2})
	sim.step()
	var res: Dictionary = sim.cmds.results.get(cid, {})
	_p("throw_party in %s -> %s" % [vs[0]["name"], str(res)])
	if not bool(res.get("ok", false)):
		return -1
	for s in 150:
		sim.run_seconds(1.0)
		for pt in sim.party.parties():
			if String(pt["phase"]) != "on":
				continue
			var fb := -1
			if fresh:
				# The least tired present guest (technician first), with hunger and thirst under 75.
				var best := -1
				var best_key := 1e9
				for g in pt["guests"]:
					var fa: Dictionary = sim.state["agents"].get(int(g), {})
					if fa.is_empty() or fa["state"] != "alive" or fa["plan_kind"] != "party" or fa["where"] != "in" or int(fa["bld"]) != venue:
						continue
					if float(fa["hunger"]) >= 75.0 or float(fa["thirst"]) >= 75.0:
						continue
					var key: float = float(fa["fatigue"]) + (0.0 if fa["role"] == "technician" else 100.0)
					if key < best_key:
						best_key = key
						best = int(g)
				if best != -1:
					_p("party is ON after %d s; least tired guest chosen (%s, fatigue %.0f)" % [s + 1, sim.state["agents"][best]["role"], float(sim.state["agents"][best]["fatigue"])])
				return best
			for g in pt["guests"]:
				var a: Dictionary = sim.state["agents"].get(int(g), {})
				if a.is_empty() or a["state"] != "alive" or a["plan_kind"] != "party" or a["where"] != "in" or int(a["bld"]) != venue:
					continue
				if a["role"] == "technician":
					_p("party is ON (phase on) after %d s; guest chosen: a technician at the venue" % (s + 1))
					return int(g)
				if fb == -1:
					fb = int(g)
			if fb != -1:
				_p("party is ON after %d s; no technician guest present; guest chosen: another role" % (s + 1))
				return fb
	return -1

# ---------------------------------------------------------------- finding things
## The least worn structure that already shows WORN (ratio >= 0.75), so it does not break during the run.
func _worn_target(sim, base: int) -> int:
	var best := -1
	var best_r := 9.0
	var wear: Dictionary = sim.hazards.hs()["wear"]
	for id in wear:
		var b: Dictionary = sim.state["buildings"].get(id, {})
		if b.is_empty() or b["state"] != "active" or int(sim.bases.base_of(int(id))) != base:
			continue
		var r: float = float(wear[id]["w"]) / maxf(0.001, float(wear[id]["fail_at"]))
		if r >= 0.75 and r < best_r and sim.hazards.wants_maintenance(b):
			best = int(id)
			best_r = r
	return best

## Test set-up: 6 spare parts into the emptiest storehouse of the base. The storehouses of this save are
## full (add_new returned 0 on the first try), so add_new_forced is used ("for scenario set-up only").
func _add_spares(sim, base: int) -> String:
	var best := -1
	var best_free := -1
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if String(b["name"]).begins_with("Storehouse") and b["state"] == "active" and int(sim.bases.base_of(int(id))) == base:
			var free: int = int(sim.inv.free_space(int(b["inv_out"])))
			if free > best_free:
				best_free = free
				best = int(id)
	if best == -1:
		return "no storehouse found"
	# _gen_repair runs before _gen_hazard_work and reserves one spare part for EVERY structure under
	# repair_trigger_health (70). Without enough parts, maintenance of a WORN machine never gets one.
	# So the set-up adds one part per damaged structure plus one per worn machine plus 6 spare.
	var damaged := 0
	var worn := 0
	var trigger: float = float(sim.bal["repair_trigger_health"])
	for id in sim.state["buildings"]:
		var b2: Dictionary = sim.state["buildings"][id]
		if b2["kind"] == "special" or bool(b2["demolish"]) or (b2["state"] != "active" and b2["state"] != "broken"):
			continue
		if float(b2["health"]) < trigger or b2["state"] == "broken":
			damaged += 1
		if sim.hazards.wants_maintenance(b2):
			worn += 1
	var qty: int = damaged + worn + 6
	var sb: Dictionary = sim.state["buildings"][best]
	var inv: int = int(sb["inv_out"])
	sim.inv.add_new_forced(inv, "spare_parts", qty, "diag")
	return "+%d spare_parts (add_new_forced: %d structures under health %d + %d worn machines + 6) into %s (bld %d, inv %d, free space was %d). Stock now: %s" % [qty, damaged, int(trigger), worn, sb["name"], best, inv, best_free, _stock_text(sim)]

func _stock_text(sim) -> String:
	var tot: Dictionary = sim.inv.totals()
	return "spare_parts %s, electronics %s" % [str(tot.get("spare_parts", {}).get("total", 0)), str(tot.get("electronics", {}).get("total", 0))]

func _board_for(sim, target: int) -> Array:
	var out: Array = []
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if int(t["bld"]) == target:
			out.append("%d:%s:%s:owner=%d:reason=%s:emerg=%d" % [tid, t["kind"], t["state"], int(t["owner"]), t["reason"], int(t["emergency"])])
	return out

func _plan_ops(a: Dictionary) -> Array:
	var ops: Array = []
	for st in a["plan"]:
		ops.append(String(st["op"]))
	return ops

func _who_text(sim, who: int) -> String:
	if who == -1:
		return "none"
	var a: Dictionary = sim.state["agents"][who]
	return "%d %s role=%s where=%s bld=%d plan_kind=%s goal='%s' step=%s sleeping=%s fatigue=%.0f hunger=%.0f thirst=%.0f" % [who, a["name"], a["role"], a["where"], int(a["bld"]), a["plan_kind"], a["goal"], sim.agents._step_op(a), str(a.get("sleeping", false)), float(a["fatigue"]), float(a["hunger"]), float(a["thirst"])]

func _short_goal(g: String) -> String:
	return g.substr(0, 40)

# ---------------------------------------------------------------- the per-second line
func _line(sim, s: int, a: Dictionary, target: int) -> String:
	var b: Dictionary = sim.state["buildings"].get(target, {})
	var rec: Dictionary = sim.hazards.hs()["wear"].get(target, {})
	var tgt := "target[state=%s w=%.2f/%.1f first=%s block=%s]" % [b.get("state", "?"), float(rec.get("w", 0.0)), float(rec.get("fail_at", 0.0)), str(b.get("maint_first", false)), str(b.get("block", ""))]
	var board: Array = _board_for(sim, target)
	var nm := 0
	var nm_owned := 0
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if t["kind"] == "maintain":
			nm += 1
			if int(t["owner"]) != -1:
				nm_owned += 1
	var head := "t+%3d" % s
	if a.is_empty():
		return "%s | (no subject) | %s | board=%s | maintain tasks colony-wide %d (owned %d)" % [head, tgt, str(board), nm, nm_owned]
	var o = a.get("order")
	var ostr := "-"
	if o != null:
		ostr = "%s b=%s" % [o["kind"], str(o.get("b", "-"))]
	var tid2: int = int(a["task"])
	var tk := "-"
	if tid2 != -1 and sim.state["tasks"].has(tid2):
		var tt: Dictionary = sim.state["tasks"][tid2]
		tk = "%d:%s:%s:bld=%d" % [tid2, tt["kind"], tt["state"], int(tt["bld"])]
	var d: float = (a["pos"] as Vector2).distance_to(b["pos"]) if not b.is_empty() else -1.0
	return "%s | %s where=%s bld=%d pos=(%.1f,%.1f) dist_target=%.1f | plan=%s step=%s %d/%d goal='%s' order=%s task=%s slp=%s fat=%.0f hun=%.0f thi=%.0f party=%s | %s | board=%s | maintain tasks colony-wide %d (owned %d)" % [head, a["name"], a["where"], int(a["bld"]), (a["pos"] as Vector2).x, (a["pos"] as Vector2).y, d, a["plan_kind"], sim.agents._step_op(a), int(a["pi"]), (a["plan"] as Array).size(), a["goal"], ostr, tk, str(a.get("sleeping", false)), float(a["fatigue"]), float(a["hunger"]), float(a["thirst"]), str(a.get("party", "-")), tgt, str(board), nm, nm_owned]

## Change signature for the stdout summary (position and wear are left out).
func _sig(sim, a: Dictionary, target: int) -> String:
	var b: Dictionary = sim.state["buildings"].get(target, {})
	var sg := "%s|%s|%s" % [b.get("state", "?"), str(b.get("maint_first", false)), str(_board_for(sim, target))]
	if not a.is_empty():
		var o = a.get("order")
		sg += "|%s|%s|%s|%s|%s|%s" % [a["plan_kind"], a["goal"], str(o["kind"]) if o != null else "-", str(a["task"]), a["where"], str(a.get("sleeping", false))]
	return sg
