extends RefCounted
## One test's record: checks, measured numbers, skip reason. A test function gets one of
## these as its only argument. A test MUST call done() as its last statement: GDScript
## has no exceptions, so a script error ends the function early, and a test that did not
## reach done() is reported as FAIL instead of looking like a pass.

var name := ""
var failures: Array = []     # text of every failed check
var notes: Array = []        # measured numbers, printed on the result line
var checks := 0
var skipped := ""
var finished := false

func _init(test_name: String) -> void:
	name = test_name

## Records a check. Returns cond, so a test can stop early when a precondition fails.
func check(cond: bool, what: String) -> bool:
	checks += 1
	if not cond:
		# The same failure at every sampled tick is one line, not thousands.
		if failures.size() < 25 and not failures.has(what):
			failures.append(what)
	return cond

func eq(actual, expected, what: String) -> bool:
	return check(typeof(actual) == typeof(expected) and actual == expected, "%s: expected %s, got %s" % [what, str(expected), str(actual)])

func near(actual: float, expected: float, tolerance: float, what: String) -> bool:
	return check(absf(actual - expected) <= tolerance, "%s: expected %s +/- %s, got %s" % [what, str(expected), str(tolerance), str(actual)])

func fail(what: String) -> void:
	check(false, what)

## A measured number or fact for the result line.
func note(text: String) -> void:
	notes.append(text)

func skip(reason: String) -> void:
	skipped = reason
	finished = true

func done() -> void:
	finished = true

func passed() -> bool:
	return skipped == "" and finished and failures.is_empty()
