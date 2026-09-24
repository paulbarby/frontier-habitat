extends RefCounted
## The interface side of the alert rules (docs/V3_DESIGN.md §2). It sits between
## sim.alerts.incidents() and the two places that show alerts: the toasts and the alert cards.
##
## Toasts:
## - A toast shows only when an alert key is NEW: it was not live at the last update.
## - The same key does not toast again for COOLDOWN seconds after it cleared.
## - Severity-1 notices never toast. They show only in the alert list.
## - Only root incidents toast. A consequence that becomes a root later does not toast
##   (it was already live).
##
## Alert cards (hold): a key that cleared stays on the list, marked "cleared", for
## MIN_SHOW seconds after it first showed, or for FLAP_HOLD (= COOLDOWN, 180 s) when it
## has cleared and come back before. Held cards sort after the live ones. So an alert that
## goes on and off (the "output blocked" defect of version 2) is one steady card, not a card
## that appears and disappears.
##
## Per-machine keys of one kind count as one alert here: every "blocked:<id>" key is the
## alert "output_blocked" (the simulation merges them from version 3; this makes the
## interface safe with a version-2 simulation too).
##
## Time is simulation seconds, so pause and fast forward behave like the simulation.
## Pure logic: tools/ui/test_alert_gate.gd drives it without a scene.

const COOLDOWN := 180.0
const MIN_SHOW := 10.0
const FLAP_HOLD := COOLDOWN
const MERGED_CODES := {"output_blocked": true}

var _live := {}        # ident -> {first: s, root: bool, issue, cons}
var _cleared := {}     # ident -> s when it last cleared
var _flapped := {}     # ident -> true when it came back within COOLDOWN of a clear
var _held := {}        # ident -> {issue, cons, first, until}
var toasts_sent := 0   # for tests and the `alerts` automation command

## The identity of an issue for the rules above.
static func ident(issue: Dictionary) -> String:
	var code: String = String(issue.get("code", ""))
	if MERGED_CODES.has(code):
		return code
	return String(issue.get("key", code))

## Takes the current incidents and returns the issues that must toast now.
## `quiet` (load grace, title screen): record everything, toast nothing.
func update(incidents: Array, now: float, quiet: bool = false) -> Array:
	var seen := {}
	var out: Array = []
	for inc in incidents:
		var root: Dictionary = inc.get("issue", {})
		_see(root, inc.get("consequences", []), true, now, quiet, seen, out)
		for c in inc.get("consequences", []):
			_see(c, [], false, now, quiet, seen, out)
	# Keys that were live and are gone now: cleared.
	for k in _live.keys():
		if seen.has(k):
			continue
		var rec: Dictionary = _live[k]
		_cleared[k] = now
		if bool(rec["root"]):
			var hold: float = FLAP_HOLD if _flapped.has(k) else maxf(0.0, MIN_SHOW - (now - float(rec["first"])))
			if hold > 0.0:
				_held[k] = {"issue": rec["issue"], "cons": rec["cons"], "first": rec["first"], "until": now + hold}
		_live.erase(k)
	for k in _held.keys():
		if seen.has(k) or now >= float(_held[k]["until"]):
			_held.erase(k)
	# Forget old clears.
	for k in _cleared.keys():
		if now - float(_cleared[k]) > COOLDOWN * 2.0 and not _live.has(k):
			_cleared.erase(k)
			_flapped.erase(k)
	toasts_sent += out.size()
	return out

func _see(issue: Dictionary, cons: Array, is_root: bool, now: float, quiet: bool, seen: Dictionary, out: Array) -> void:
	if issue.is_empty():
		return
	var k: String = ident(issue)
	if seen.has(k):
		# A merged key seen twice in one update (two blocked machines): keep the first.
		return
	seen[k] = true
	if _live.has(k):
		var rec: Dictionary = _live[k]
		rec["issue"] = issue
		rec["cons"] = cons
		rec["root"] = bool(rec["root"]) or is_root
		return
	var came_back: bool = _cleared.has(k) and now - float(_cleared[k]) < COOLDOWN
	if came_back:
		_flapped[k] = true
	var first: float = now
	if _held.has(k):
		first = float(_held[k]["first"])
		_held.erase(k)
	_live[k] = {"first": first, "root": is_root, "issue": issue, "cons": cons}
	if quiet or not is_root or came_back:
		return
	if int(issue.get("severity", 1)) < 2:
		return
	out.append(issue)

## The list the alert cards show: the live incidents plus held (cleared) ones, in a stable
## order: severity, then when the interface first saw the key. Each entry is
## {issue, consequences, cleared: bool}.
func display(incidents: Array) -> Array:
	var rows: Array = []
	var seen := {}
	for inc in incidents:
		var issue: Dictionary = inc.get("issue", {})
		var k: String = ident(issue)
		if seen.has(k):
			continue
		seen[k] = true
		var first: float = float(_live.get(k, {}).get("first", 0.0))
		rows.append({"issue": issue, "consequences": inc.get("consequences", []), "cleared": false, "first": first, "ident": k})
	for k in _held:
		if seen.has(k):
			continue
		var h: Dictionary = _held[k]
		rows.append({"issue": h["issue"], "consequences": [], "cleared": true, "first": float(h["first"]), "ident": k})
	rows.sort_custom(func(a, b):
		if bool(a["cleared"]) != bool(b["cleared"]):
			return not bool(a["cleared"])
		var sa: int = int(a["issue"].get("severity", 1))
		var sb: int = int(b["issue"].get("severity", 1))
		if sa != sb:
			return sa > sb
		if not is_equal_approx(float(a["first"]), float(b["first"])):
			return float(a["first"]) < float(b["first"])
		return String(a["ident"]) < String(b["ident"]))
	return rows

func reset() -> void:
	_live = {}
	_cleared = {}
	_flapped = {}
	_held = {}
	toasts_sent = 0

func live_count() -> int:
	return _live.size()

func held_count() -> int:
	return _held.size()
