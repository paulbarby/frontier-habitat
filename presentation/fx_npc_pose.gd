extends RefCounted
## Pose state machine for one astronaut (RENDER, V3_DESIGN §3.4). Pure logic: no nodes, so
## tools/npc_check.gd drives exactly the machine the game uses.
##
## Pose states: stand, sit, lie, kneel. Changing pose ALWAYS plays the enter or exit clip
## (sit_enter / sit_exit, lie_enter / lie_exit, kneel_enter / kneel_exit); a change between
## two non-stand poses goes through stand. Loops in the same pose cross-fade FADE seconds.
## Locomotion (loop "loco") blends walk <-> run by the real ground speed with one shared
## phase, and the playback rate is speed / stride, so feet do not slide. Carrying is an
## upper-body layer (carry_walk / carry_idle) over the locomotion, faded in and out.
##
## Output (pose()) is what the GPU skinning shader draws: pose A (clip + time), pose B
## (clip + time) mixed in with weight wb, and the carry layer (clip + time, weight wc).

const FADE := 0.25           # shortest cross-fade (s)
const FADE_MAX := 0.6        # longest cross-fade (s)
const FADE_RATE := 300.0     # deg/s: fade = max(FADE, largest bone change / FADE_RATE), V3 §3.4
const ENTER := {"sit": "sit_enter", "lie": "lie_enter", "kneel": "kneel_enter"}
const EXIT := {"sit": "sit_exit", "lie": "lie_exit", "kneel": "kneel_exit"}
## The rest loop of each pose state (V3 §3.5: stand = idle, sit = sit_idle, lie = sleep,
## kneel = repair_kneel).
const REST := {"stand": "idle", "sit": "sit_idle", "lie": "sleep", "kneel": "repair_kneel"}
## Loops that belong to each pose state.
const LOOPS := {
	"stand": ["idle", "idle_look", "work_console", "work_bench", "talk", "carry_idle", "loco"],
	"sit": ["sit_idle", "sit_eat", "sit_type"],
	"lie": ["sleep", "dead"],
	"kneel": ["repair_kneel"],
}
const WALK_START := 0.28     # m/s: start the walk cycle above this ground speed
const WALK_STOP := 0.12      # m/s: back to idle below this

var clips := {}              # name -> {len, loop, speed, stride, pose_from, pose_to, kind}
var pose_state := "stand"
var phase := "loop"          # loop | enter | exit | oneshot | hold
var cur := "idle"            # clip playing (for "loco": the walk clip)
var cur_t := 0.0
var loco := false            # cur is the locomotion blend
var loco_phase := 0.0        # shared 0..1 phase of walk / run
var run_w := 0.0             # weight of the run clip in the locomotion blend
var run_latch := false       # walk or run chosen (hysteresis)
var prev := ""               # clip fading out ("" = none)
var prev_t := 0.0
var prev_rate := 1.0
var fade := 0.0              # seconds left of the cross-fade
var fade_total := FADE       # length of the running cross-fade
var angle_fn: Callable       # (clip_a, t_a, clip_b, t_b) -> largest local bone change, degrees
var idle_clip := "idle"      # the still loop while standing without a task (idle / idle_look)
var want_pose := "stand"
var want_loop := "idle"
var speed := 0.0             # ground speed (m/s), set every frame
var injured := false
var carry := false
var carry_w := 0.0
var carry_t := 0.0
var oneshot_next := ""       # after a oneshot: "hold" (dead) or a loop
var log: Array = []          # transitions taken (for tests): [from, to, kind]

func _init(clip_table: Dictionary) -> void:
	clips = clip_table

func has(c: String) -> bool:
	return clips.has(c)

func clip_len(c: String) -> float:
	return float(clips[c]["len"]) if clips.has(c) else 1.0

## The clip actually played for a wanted loop: a missing clip falls back to a near one.
func resolve_loop(l: String, p: String) -> String:
	if l == "loco":
		return "loco"
	if clips.has(l):
		return l
	var fb: Dictionary = {"idle_look": "idle", "work_console": "work_bench", "work_bench": "work_console", "talk": "idle_look",
		"carry_idle": "idle", "sit_eat": "sit_idle", "sit_type": "sit_idle", "dead": "sleep"}
	var f: String = String(fb.get(l, ""))
	if f != "" and clips.has(f):
		return f
	var r: String = String(REST.get(p, "idle"))
	if clips.has(r):
		return r
	return "idle"

## Can this machine reach the pose at all (its enter, rest loop and exit clips exist)?
func can_pose(p: String) -> bool:
	if p == "stand":
		return clips.has("idle")
	return clips.has(ENTER[p]) and clips.has(EXIT[p]) and clips.has(REST[p])

## Set the goal: a pose state and a loop inside it ("loco" = stand and move by speed).
func set_goal(p: String, l: String) -> void:
	if not can_pose(p):
		p = "stand"
		if not (l in LOOPS["stand"]):
			l = "idle"
	want_pose = p
	want_loop = l

## One-shot clips: "collapse" (then hold "dead"), "cheer" (then back to the loop).
func play_oneshot(c: String) -> void:
	if not clips.has(c) or phase == "oneshot":
		return
	if c == "collapse" and (phase == "hold" or pose_state == "lie"):
		return
	_start(c, "oneshot")
	oneshot_next = "hold" if c == "collapse" else ""

func is_busy() -> bool:
	return phase == "enter" or phase == "exit" or phase == "oneshot"

## True when the body is fully in the pose's loop (the enter clip has finished).
func settled_in(p: String) -> bool:
	return pose_state == p and phase == "loop"

func _start(c: String, ph: String, t0: float = 0.0) -> void:
	# The clip that was playing fades out over FADE seconds.
	if cur != "" and c != cur:
		prev = cur
		prev_t = cur_t
		prev_rate = _rate_of(cur) if not loco else 1.0
		if loco:
			prev = _loco_clip()
			prev_t = loco_phase * clip_len(prev)
			prev_rate = _loco_rate() * clip_len(prev)
		fade_total = FADE
		if angle_fn.is_valid():
			fade_total = clampf(float(angle_fn.call(prev, prev_t, c, t0)) / FADE_RATE, FADE, FADE_MAX)
		fade = fade_total
	log.append([cur if not loco else "loco", c, ph])
	cur = c
	cur_t = t0
	phase = ph
	loco = false
	run_w = 0.0

func _rate_of(c: String) -> float:
	return 1.0

func _walk_clip() -> String:
	if injured and clips.has("injured_walk"):
		return "injured_walk"
	return "walk" if clips.has("walk") else "idle"

func _loco_clip() -> String:
	return "run" if run_w > 0.5 and clips.has("run") and not injured else _walk_clip()

## Cycles per second of the locomotion blend: speed / stride, so the feet do not slide.
## No cap (orchestrator, 2026-09-24): foot sliding is the bigger fault; the run clip covers
## the colony's normal pace.
func _loco_rate() -> float:
	var w: String = _walk_clip()
	var cyc: float = speed / maxf(0.05, _stride(w))
	if run_w > 0.0 and clips.has("run"):
		cyc = lerpf(cyc, speed / maxf(0.05, _stride("run")), run_w)
	return cyc

## Playback rate (1 = as authored) of a clip now: locomotion clips follow the speed.
func rate_of(c: String) -> float:
	if loco and (c == cur or c == "run" or c == "carry_walk"):
		return _loco_rate() * clip_len(c)
	if c == prev:
		return prev_rate
	return 1.0

func _stride(c: String) -> float:
	var d: Dictionary = clips.get(c, {})
	if float(d.get("stride", 0.0)) > 0.01:
		return float(d["stride"])
	if float(d.get("speed", 0.0)) > 0.01:
		return float(d["speed"]) * float(d.get("len", 1.0))
	return 1.4 * float(d.get("len", 1.0))

func _speed_of(c: String) -> float:
	var d: Dictionary = clips.get(c, {})
	if float(d.get("speed", 0.0)) > 0.01:
		return float(d["speed"])
	return _stride(c) / maxf(0.1, float(d.get("len", 1.0)))

func advance(dt: float) -> void:
	# Cross-fade source keeps playing while it fades.
	if fade > 0.0:
		fade = maxf(0.0, fade - dt)
		prev_t += dt * prev_rate
		if prev != "" and bool(clips.get(prev, {}).get("loop", false)):
			prev_t = fposmod(prev_t, clip_len(prev))
		else:
			prev_t = minf(prev_t, clip_len(prev))
		if fade <= 0.0:
			prev = ""
	# Carry layer weight.
	var carry_on: bool = carry and pose_state == "stand" and phase == "loop" and (clips.has("carry_walk") or clips.has("carry_idle"))
	carry_w = move_toward(carry_w, 1.0 if carry_on else 0.0, dt / FADE)
	match phase:
		"enter", "exit", "oneshot":
			cur_t += dt
			if cur_t >= clip_len(cur):
				_finish()
		"hold":
			cur_t = clip_len(cur)
		"loop":
			_loop_step(dt)
	# Carry clip time: synced to the walk phase while moving, free-running when still.
	if carry_w > 0.0:
		if loco and clips.has("carry_walk"):
			carry_t = loco_phase * clip_len("carry_walk")
		else:
			carry_t = fposmod(carry_t + dt, clip_len("carry_idle") if clips.has("carry_idle") else 1.0)

func _finish() -> void:
	var c: String = cur
	var d: Dictionary = clips.get(c, {})
	if phase == "oneshot":
		if oneshot_next == "hold":
			pose_state = "lie"
			if clips.has("dead"):
				_start("dead", "hold")
			else:
				cur_t = clip_len(c)
				phase = "hold"
			return
		_start(resolve_loop(want_loop if want_pose == pose_state else String(REST[pose_state]), pose_state), "loop")
		return
	cur_t = clip_len(c)
	if phase == "enter":
		pose_state = String(d.get("pose_to", _pose_after_enter(c)))
	else:
		pose_state = "stand"
	# Next: the wanted loop of this pose, or the next pose change.
	if want_pose != pose_state:
		if pose_state == "stand":
			_start(String(ENTER[want_pose]), "enter")
		else:
			_start(String(EXIT[pose_state]), "exit")
		return
	var l: String = resolve_loop(want_loop, pose_state)
	if l == "loco":
		_start_loco()
	else:
		_start(l, "loop")

func _pose_after_enter(c: String) -> String:
	for p in ENTER:
		if ENTER[p] == c:
			return p
	return "stand"

func _start_loco() -> void:
	var w: String = _walk_clip()
	_start(w, "loop", 0.0)
	loco = true
	loco_phase = 0.0

func _loop_step(dt: float) -> void:
	# A new clip starts only after the running cross-fade ends: the machine blends two poses,
	# so starting a third would pop.
	var can: bool = fade <= 0.0
	# A pose change: exit this pose first, or enter the new one from stand.
	if want_pose != pose_state and can:
		if pose_state == "stand":
			_start(String(ENTER[want_pose]), "enter")
		else:
			_start(String(EXIT[pose_state]), "exit")
		return
	var target: String = resolve_loop(want_loop, pose_state) if want_pose == pose_state else ("loco" if loco else cur)
	if target == "loco":
		# Idle <-> walk <-> run by ground speed (with hysteresis).
		var moving: bool = speed > (WALK_STOP if loco else WALK_START)
		target = "loco" if moving else resolve_loop(idle_clip, "stand")
	if can:
		if target == "loco" and not loco:
			_start_loco()
			return
		if target != "loco" and (loco or target != cur):
			_start(target, "loop")
			return
	if loco:
		# Walk / run blend with one shared phase; rate = speed / stride.
		var vw: float = _speed_of(_walk_clip())
		var vr: float = _speed_of("run") if clips.has("run") else vw * 2.0
		# Walk or run, latched with hysteresis (the measured speed is noisy): the blend lasts
		# only the FADE of a change, both cycles on one shared phase (V3 §3.4).
		if injured or not clips.has("run"):
			run_latch = false
		elif speed > vw + (vr - vw) * 0.55:
			run_latch = true
		elif speed < vw + (vr - vw) * 0.3:
			run_latch = false
		run_w = move_toward(run_w, 1.0 if run_latch else 0.0, dt / FADE)
		cur = _walk_clip()
		loco_phase = fposmod(loco_phase + dt * _loco_rate(), 1.0)
		cur_t = loco_phase * clip_len(cur)
		return
	cur_t = fposmod(cur_t + dt, clip_len(cur)) if bool(clips.get(cur, {}).get("loop", true)) else minf(cur_t + dt, clip_len(cur))

## What to draw now. a/b/c are clip names ("" = none); ta/tb/tc times in seconds.
func pose() -> Dictionary:
	var a: String = cur
	var ta: float = cur_t
	var b := ""
	var tb := 0.0
	var wb := 0.0
	if prev != "" and fade > 0.0:
		b = prev
		tb = prev_t
		wb = fade / maxf(fade_total, 0.001)
		if loco and run_w > 0.5 and clips.has("run"):
			a = "run"
			ta = loco_phase * clip_len("run")
	elif loco and run_w >= 0.999 and clips.has("run"):
		# A steady jog: the run clip alone (no blend).
		a = "run"
		ta = loco_phase * clip_len("run")
	elif loco and run_w > 0.001 and clips.has("run"):
		b = "run"
		tb = loco_phase * clip_len("run")
		wb = run_w
	var c := ""
	if carry_w > 0.001:
		c = "carry_walk" if (loco and clips.has("carry_walk")) else ("carry_idle" if clips.has("carry_idle") else "carry_walk")
		if not clips.has(c):
			c = ""
	return {"a": a, "ta": ta, "b": b, "tb": tb, "wb": wb, "c": c, "tc": carry_t, "wc": carry_w if c != "" else 0.0}
