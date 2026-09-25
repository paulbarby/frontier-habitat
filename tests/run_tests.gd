extends SceneTree
## Headless test runner for the Frontier Habitat simulation.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- replay      (name filter)
##   godot --headless --path . --script res://tests/run_tests.gd -- !long_     (all but names with "long_")
##   godot --headless --path . --script res://tests/run_tests.gd -- --list
##   godot --headless --path . --script res://tests/run_tests.gd -- --inproc a01
##
## Exit code 0 only when every selected test passes AND no GDScript error was printed.
##
## Why two processes: GDScript has no exceptions. A script error inside the simulation
## only prints "SCRIPT ERROR" and ends that one function; the game goes on, and a test
## cannot see it from the inside. So this script starts the tests in a child process and
## reads the child's error stream. "--inproc" runs the tests directly in this process
## (no script-error detection); the child uses it.

const Ctx = preload("res://tests/ctx.gd")

const SUITES := [
	"res://tests/cases_unit.gd",
	"res://tests/cases_v2.gd",
	"res://tests/cases_acceptance.gd",
	"res://tests/cases_soak.gd",
	"res://tests/cases_v3.gd",
	"res://tests/cases_v31.gd",
]

var _err_mutex := Mutex.new()
var _err_lines: Array = []      # [test name, text]
var _current := ""

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var inproc := false
	var list_only := false
	var filter := ""
	for a in args:
		if a == "--inproc":
			inproc = true
		elif a == "--list":
			list_only = true
		elif not a.begins_with("--"):
			filter = a
	if inproc or list_only:
		quit(_run_tests(filter, list_only))
	else:
		quit(_run_child(args))

# ---------------------------------------------------------------- parent: run the child, watch stderr
func _run_child(user_args: PackedStringArray) -> int:
	var exe: String = OS.get_executable_path()
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/run_tests.gd", "--", "--inproc"]
	args.append_array(user_args)
	var info: Dictionary = OS.execute_with_pipe(exe, args)
	if info.is_empty():
		print("NOTE  could not start a child process; running in this process. Script errors will NOT fail the run.")
		return _run_tests(_filter_of(user_args), false)
	var out_pipe: FileAccess = info["stdio"]
	var err_pipe: FileAccess = info["stderr"]
	var pid: int = info["pid"]
	var th := Thread.new()
	th.start(_drain_errors.bind(err_pipe))
	while true:
		var line: String = out_pipe.get_line()
		if out_pipe.get_error() != OK and line == "":
			break
		if line.begins_with("RUN   "):
			_err_mutex.lock()
			_current = line.substr(6).strip_edges()
			_err_mutex.unlock()
		print(line)
	th.wait_to_finish()
	var waited := 0
	while OS.is_process_running(pid) and waited < 10000:
		OS.delay_msec(20)
		waited += 20
	var code: int = OS.get_process_exit_code(pid)

	# Group the script errors: message + the "at:" line that follows it.
	var groups := {}
	var order: Array = []
	var i := 0
	while i < _err_lines.size():
		var text: String = _err_lines[i][1]
		if text.contains("SCRIPT ERROR") or text.contains("Parse Error") or text.contains("Parser Error"):
			var where := ""
			if i + 1 < _err_lines.size() and String(_err_lines[i + 1][1]).strip_edges().begins_with("at:"):
				where = String(_err_lines[i + 1][1]).strip_edges()
			var key := "[%s] %s  %s" % [_err_lines[i][0], text.strip_edges(), where]
			if not groups.has(key):
				groups[key] = 0
				order.append(key)
			groups[key] += 1
		i += 1
	if not order.is_empty():
		var total := 0
		for k in order:
			total += int(groups[k])
		print("")
		print("SCRIPT ERRORS: %d. A script error ends the function it happens in, so the run FAILS." % total)
		for k in order:
			print("  x%d  %s" % [groups[k], k])
		return 1
	if code != 0:
		return 1
	return 0

func _drain_errors(pipe: FileAccess) -> void:
	while true:
		var line: String = pipe.get_line()
		if pipe.get_error() != OK and line == "":
			break
		_err_mutex.lock()
		_err_lines.append([_current, line])
		_err_mutex.unlock()

static func _filter_of(user_args: PackedStringArray) -> String:
	for a in user_args:
		if not a.begins_with("--"):
			return a
	return ""

# ---------------------------------------------------------------- child: the tests themselves
func _run_tests(filter: String, list_only: bool) -> int:
	var t_start: int = Time.get_ticks_msec()
	var passed := 0
	var failed := 0
	var skipped := 0
	var failed_names: Array = []
	for path in SUITES:
		var script = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL  %s  (the test file did not load)" % path)
			failed += 1
			failed_names.append(path)
			continue
		var suite = script.new()
		for entry in suite.tests():
			var test_name: String = entry[0]
			if filter.begins_with("!"):
				if test_name.contains(filter.substr(1)):
					continue
			elif filter != "" and not test_name.contains(filter):
				continue
			if list_only:
				print(test_name)
				continue
			print("RUN   %s" % test_name)
			var t = Ctx.new(test_name)
			var t0: int = Time.get_ticks_msec()
			(entry[1] as Callable).call(t)
			var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
			var notes: String = "" if t.notes.is_empty() else "  | " + "; ".join(t.notes)
			if t.skipped != "":
				skipped += 1
				print("SKIP  %s  | %s" % [test_name, t.skipped])
			elif t.passed():
				passed += 1
				print("PASS  %s  %.1f s, %d checks%s" % [test_name, secs, t.checks, notes])
			else:
				failed += 1
				failed_names.append(test_name)
				print("FAIL  %s  %.1f s, %d checks%s" % [test_name, secs, t.checks, notes])
				for f in t.failures:
					print("      - %s" % f)
				if not t.finished:
					print("      - the test did not reach its end (a script error stopped it)")
	if list_only:
		return 0
	print("")
	print("%d passed, %d failed, %d skipped in %.1f s" % [passed, failed, skipped, float(Time.get_ticks_msec() - t_start) / 1000.0])
	if failed > 0:
		print("failed: %s" % ", ".join(failed_names))
	if passed + failed + skipped == 0:
		print("no test matches '%s'" % filter)
		return 1
	return 0 if failed == 0 else 1
