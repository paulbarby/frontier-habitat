extends Node3D
## Elevated orbit camera (RENDER; spec 2, 12). WASD or edge pan, wheel zoom, middle-drag
## orbit, Q/E turn, optional follow. The rig sits on the ground point it looks at.
## 2.0: damped orbit and zoom, the camera flattens as it zooms in, a cinematic fly-in on a
## new colony (any key or click skips it), a slow photo orbit for the title screen, and a
## small shake for big moments.
##
## Other scripts may write yaw, pitch and target_distance directly (the automation hook
## does): a direct write is picked up as the new target.

var camera: Camera3D
var yaw := deg_to_rad(-35.0)
var pitch := deg_to_rad(52.0)
var distance := 62.0
var target_distance := 62.0
var focus := Vector3.ZERO
var bounds := Rect2(0, 0, 256, 256)
var height_fn: Callable
var edge_pan := false
var follow_fn: Callable      # returns Vector3 or null
var _mouse_seen := false     # a real mouse motion arrived (edge pan waits for it)
var ui_blocks_mouse := false
var min_distance := 9.0
var max_distance := 200.0
var pan_speed := 1.0         # settings: multiplies keyboard / edge pan and Q/E turn speed
var shake_enabled := true    # settings "Camera shake" (UI): false = quakes and impacts do not move the camera

var _orbiting := false
var _yaw_t := yaw
var _pitch_t := pitch
var _yaw_seen := yaw
var _pitch_seen := pitch
var _vel := Vector3.ZERO
var _intro := -1.0
const INTRO_SECONDS := 7.0
var _photo := false
var _photo_center := Vector3.ZERO
var _photo_radius := 70.0
var _photo_height := 22.0
var _photo_speed := 0.05
var _photo_angle := 0.0
var _shake := 0.0
var _t := 0.0

# ---------------------------------------------------------------- V5 §3 follow view (over the shoulder)
## shoulder_fn() -> [Vector3 body ground point, float body yaw (model +X forward), float eye height]
## or null (the person is gone: the view ends). collide_fn(pivot, eye, margin) -> the eye pulled in
## so it stays `margin` m off every wall (world_view). While shoulder_fn is valid the rig is in the
## follow view.
##
## Smoothing (2026-10-01, Paul: "the follow cam shakes"): every moving part of the camera is a
## critically damped spring, stepped in closed form (the same result at 30, 60 or 144 fps):
##   pivot    - the body point, with the body's smoothed velocity fed forward (no lag on a steady walk)
##   heading  - the body yaw (slow for small turns, faster for real ones)
##   eye      - the eye height (sit / stand / lie change it in steps)
##   distance - the wheel distance and the wall pull-in (fast in, slow out, a 4 % dead band out)
## The aim is computed from the smoothed heading, never from a separately lagged look point.
var shoulder_fn: Callable
var collide_fn: Callable
var sh_side := 1.0            # 1 = right shoulder, -1 = left (Q/E swap)
var sh_dist := 1.9            # m behind; wheel SH_DMIN..SH_DMAX (face close-up .. 8 m)
var sh_orbit := 0.0           # rad, drag orbit about the person, a full circle (0 = behind)
var sh_pitch := 0.0           # rad, tilt from the drag (SH_PMIN near the floor .. SH_PMAX high above)
var sh_look_yaw := 0.0        # rad, free-look: the aim only (middle drag)
var sh_look_pitch := 0.0
var ceil_fn: Callable         # (feet, eye) -> ceiling y over the eye, INF outdoors (world_view.follow_ceiling)
var door_fn: Callable         # (p) -> horizontal distance to the nearest doorway point, INF none (world_view.follow_door_d)
var door_side := 0.0          # the shoulder offset at a doorway (x SH_SIDE); 1 = off (measurement: 0.2 -> 133 bad probe frames, 0 -> 119, none -> 160)
var door_r0 := 1.5            # m from a doorway point: the offset is door_side inside this, full beyond door_r1
var door_r1 := 3.0
var _sh_door_k := 1.0
var _sh_door_kv := 0.0
var _sh_o := 0.0
var _sh_ov := 0.0
var _sh_pt := 0.0
var _sh_ptv := 0.0
var _sh_ly := 0.0
var _sh_lyv := 0.0
var _sh_lp := 0.0
var _sh_lpv := 0.0
var _sh_cy := INF
var _sh_cyv := 0.0
var _sh_idle := 0.0          # s without camera input (the auto return)
var _sh_returning := false
var _sh_look_drag := false
var _sh_heading := 0.0
var _sh_hvel := 0.0
var _sh_p := Vector3.ZERO     # smoothed body point
var _sh_pv := Vector3.ZERO    # its velocity
var _sh_bu := Vector3.ZERO    # smoothed body velocity (fed forward)
var _sh_bprev := Vector3.ZERO
var _sh_eh := 1.65            # smoothed eye height
var _sh_ehv := 0.0
var _sh_d := 1.9              # smoothed wheel distance
var _sh_dv := 0.0
var _sh_side_s := 1.0         # smoothed shoulder side (Q/E swap slides across)
var _sh_sv := 0.0
var _sh_f := 1.0              # smoothed wall pull-in (fraction of the free eye offset)
var _sh_fv := 0.0
var _sh_push := Vector3.ZERO  # smoothed wall correction of the eye (world)
var _sh_pushv := Vector3.ZERO
var _sh_fhold := 0.0          # s the wall has been further off than the eye (release after 0.6 s)
var _sh_eye := Vector3.ZERO
var _sh_new := true
var _sh_drag := false
var probe_fn: Callable        # measurement only (fx_follow_probe): called after each follow frame
var _sh_pull := 1.0           # last wall pull-in used: fraction of the free eye offset (1 = free)
var _sh_eyeh := 1.65
const SH_W_PIVOT := 10.0      # rad/s: pivot spring
const SH_W_VEL := 6.0         # 1/s: body velocity low-pass (the fed-forward velocity)
const SH_W_EYE := 4.0
const SH_W_DIST := 8.0
const SH_HACC := 5.0          # rad/s^2: the most the heading's turn rate changes (camera jerk at 4x)
const SH_HRATE := 1.75        # rad/s (100 deg/s): the fastest the camera heading turns
const SH_W_IN := 7.0          # wall correction in: fast (14 gave 7-20 mm camera jerk with the roofs-on walls)
const SH_W_OUT := 2.5         # release: slow
const SH_SOFT := 0.8          # m: the smoothed eye keeps this far off a wall (eased)
const SH_HARD := 0.2          # m: the eye is never closer than this to a wall (no easing; outdoors)
const SH_KNEE := 0.8          # m: indoors the soft wall rule's knee depth (world_view._vol_soft)
const SH_KNEE2 := 0.2          # m: the soft rule again on the sprung eye (guard zone 0.25 m; inside the target margin)
const SH_W_SMOOTH := 4.0      # rad/s: indoors the wall push spring (symmetric)
const SH_W_CEIL_DOWN := 3.0   # rad/s: the eased ceiling over the eye, falling (a corridor ahead)
const SH_W_CEIL_UP := 2.0     # rad/s: rising
const SH_CEIL_KNEE := 0.5     # m: the soft ceiling limit's knee
const SH_BODY_GAP := 0.6      # m (plan): the eye never comes closer to the followed body (at 1.9 m zoom)
var dbg_free := Vector3.ZERO  # measurement: the free eye before the wall rule
var dbg_target := Vector3.ZERO # measurement: the soft wall rule's target (before the spring)
var slide_fn: Callable         # (shoulder, last eye, sprung eye) -> eye slid along the walls (world_view.follow_slide)
var _sh_slide_prev := Vector3.ZERO
var _sh_slide_ok := false
var _sh_fin := Vector3.ZERO     # eased eye offset from the pivot after the indoor slide
var _sh_finv := Vector3.ZERO
const SH_W_FINAL := 14.0        # rad/s
var occ_on := 1.0             # measurement switch (render_follow_headless rig.occ_on=0)
var solid_fn: Callable         # (p) -> true inside a solid cell at eye height (world_view.follow_solid)
var arm_fn: Callable           # (a, b, r) -> clear length from a toward b for a sphere of radius r (world_view.follow_arm)
var push_rate_p := 1.0         # the indoor wall push spring is SH_W_SMOOTH x rate_k^p at 2x-4x (measurement switch)
var final_rate_p := 2.0        # the final offset spring is SH_W_FINAL / rate_k^p at 2x-4x (measurement switch)
var indoor_side := 1.0         # the shoulder offset indoors (x SH_SIDE); measurement switch (0.6 and 0.3 tried 2026-10-03: no fewer wall frames, more head jitter)
var _sh_side_k := 1.0
var arm_on := 1.0              # measurement switch (rig.arm_on=0)
var arm_slack := 1.0           # the hard limit's give (fraction of the arm): the spring alone inside it
var arm_w_in := 14.0           # rad/s (SH_W_ARM_IN)
var _sh_arm := 1.0             # the arm's length factor (fraction of the eye's offset from the pivot), eased out
var _sh_armv := 0.0
var dbg_arm := [0, 0, 0.0]     # measurement: [frames the thin arm clamped, frames pulled in, metres clamped]
const ARM_R := 0.22            # m: the thick arm (eased in, so the pull starts before the sight line is cut)
const ARM_MARGIN := 0.12       # m: the eye stays this far before a surface on the thin arm
const ARM_CUT := 0.47          # m: Models.near_fade cuts structure surfaces nearer the lens (they hide nothing)
const ARM_MIN := 1.05         # m: the shortest arm (closer: fx_npc fades the body within 0.8 m of the lens and the frame shows only what is behind it)
const SH_W_ARM_IN := 10.0      # rad/s: in, to the thick arm's length
const SH_W_ARM_OUT := 2.0      # rad/s: back out
var frame_fn: Callable         # (eye, look dir) -> true when no surface is within 0.8 m across the frame centre
var occ_fn: Callable           # (eye) -> how far from the chest the eye may stand (world_view.follow_occluder)
var _sh_occ := 1.0             # eased occluder pull (fraction of the eye's distance from the pivot)
var _sh_occv := 0.0
var _sh_occ_hold := 0.0
const SH_W_OCC_IN := 3.0       # rad/s: in front of an occluder (9 gave 20-30 mm camera jerk)
const SH_W_OCC_OUT := 2.0      # rad/s: back out slowly
const SH_OCC_HOLD := 1.0       # s clear before easing back out
const SH_OCC_MIN := 0.8        # m from the chest: a closer occluder is not avoided by pulling in
var _sh_oo := 0.0              # occluder orbit offset (rad), eased
var _sh_oov := 0.0
var _sh_oo_t := 0.0            # its target
var _sh_od := 1.0              # framing boom factor (a cramped room: a shorter boom), eased
var _sh_odv := 0.0
var _sh_od_t := 1.0
var _sh_oo_clear := 0.0        # s the plain view has been clear
var _sh_oo_blk := 0.0          # s the plain view has been blocked
const SH_OCC_WAIT := 0.25      # s
const SH_W_OCC_BOOM := 3.0     # rad/s: the framing boom length
const SH_W_OCC_ORBIT := 2.0    # rad/s (3.0: a 45 deg swing gave 4 mm camera jerk)
var head_boost := 1.0          # measurement switch (render_follow_headless rig.head_boost=0): the trailing-heading boost
var collide_smooth := false   # set by collide_fn each call: the indoor wall rule is already smooth

## Is the view from heading h good: no occluder between the eye and the person, and (frame_fn) no surface
## within 0.8 m across the centre of the frame? The eye is the wall rule's target for that heading.
var _sh_chk_clock := 0.0
var _sh_search_i := 0
const SH_SEARCH_STEP := 6
# (no boom under 0.75 x: a camera 0.6-0.8 m from the person looked over the head at a wall or the ceiling, or lost
# the person under the frame; the arm, not a short boom, keeps the sight line, 2026-10-03)
const SEARCH_CANDS := [[0.0, 1.0], [0.0, 0.75], [15.0, 1.0], [-15.0, 1.0], [30.0, 1.0], [-30.0, 1.0], [15.0, 0.75], [-15.0, 0.75],
	[45.0, 1.0], [-45.0, 1.0], [30.0, 0.75], [-30.0, 0.75], [60.0, 1.0], [-60.0, 1.0], [45.0, 0.75], [-45.0, 0.75],
	[90.0, 1.0], [-90.0, 1.0], [60.0, 0.75], [-60.0, 0.75], [90.0, 0.75], [-90.0, 0.75]]
var dbg_search := [0, 0]
var dbg_cur_ok := true
var _sh_fr_cool := 0.0
var _sh_fr_sign := 1.0
var _sh_bar := {}   # views barred for a while ("angle:boom%" -> s left)      # measurement: framing searches [failed, found]
func _view_ok(pivot: Vector3, h: float, side: float, lift: float, df: float = 1.0) -> bool:
	var _tv: int = Time.get_ticks_usec()
	var r: bool = _view_ok2(pivot, h, side, lift, df)
	prof_us["viewok"] = int(prof_us.get("viewok", 0)) + Time.get_ticks_usec() - _tv
	prof_us["viewok_n"] = int(prof_us.get("viewok_n", 0)) + 1
	return r

func _view_ok2(pivot: Vector3, h: float, side: float, lift: float, df: float = 1.0) -> bool:
	var e: Vector3 = _free_eye(pivot, h, side, lift, df)
	if collide_fn.is_valid():
		var rt := Vector3(sin(h), 0.0, cos(h))
		var keep: bool = collide_smooth
		e = collide_fn.call(pivot + rt * side, e, SH_SOFT, false, SH_KNEE) as Vector3
		collide_smooth = keep
	# (under the ceiling, as the frame will be: a low room brings the eye down to the shelves)
	if ceil_fn.is_valid():
		var cy: float = float(ceil_fn.call(_sh_p, e))
		if cy < INF:
			e.y = minf(e.y, cy - 0.3 - SH_CEIL_KNEE * 0.4)
	e.y = maxf(e.y, _sh_p.y + 0.25)
	if solid_fn.is_valid() and bool(solid_fn.call(e)):
		return false
	if float(occ_fn.call(e)) != INF:
		return false
	if frame_fn.is_valid():
		# (the aim as the follow frame makes it: toward the pivot, turned by the shoulder offset, 10 deg down)
		var to_p: Vector3 = pivot - e
		var off: float = atan2(side, maxf(_sh_d * df * cos(_sh_pt), 0.05))
		var ay: float = atan2(-to_p.z, to_p.x) - off
		var ap: float = atan2(to_p.y, Vector2(to_p.x, to_p.z).length()) - deg_to_rad(10.0) - lift * 0.25
		var look := Vector3(cos(ay) * cos(ap), sin(ap), -sin(ay) * cos(ap))
		return bool(frame_fn.call(e, look))
	return true

## The unpulled eye for a heading (the same formula as the follow frame's `free`), for the occluder search.
func _free_eye(pivot: Vector3, hd: float, side: float, lift: float, df: float = 1.0) -> Vector3:
	var fw := Vector3(cos(hd), 0.0, -sin(hd))
	var rt := Vector3(sin(hd), 0.0, cos(hd))
	var dd: float = _sh_d * df
	return pivot - fw * dd * cos(_sh_pt) + rt * side + Vector3(0.0, lift + dd * sin(_sh_pt), 0.0)

## One exact step of a critically damped spring (x, v) toward `target` with angular frequency w.
static func _crit(x: float, v: float, target: float, w: float, dt: float) -> Vector2:
	var e: float = x - target
	var ex: float = exp(-w * dt)
	var tmp: float = (v + w * e) * dt
	return Vector2(target + (e + tmp) * ex, (v - w * tmp) * ex)
const SH_SIDE := 0.55
const SH_UP := 0.15
const SH_DMIN := 0.5
const SH_DMAX := 8.0
const SH_PMIN := -0.6         # rad: the camera low, near the floor, looking up
const SH_PMAX := 1.35         # rad: high above, looking down
const SH_W_ORBIT := 8.0       # rad/s: orbit / tilt / free-look follow the mouse
const SH_W_RETURN := 2.5      # rad/s: the return behind the shoulder
const SH_RETURN_S := 4.0      # s without camera input while the person walks: back behind the shoulder (auto_return only)
const HOVER_K := 0.0035        # rad per pixel: the no-button mouse look
const LOOK_UP_MAX := 1.4       # rad: the aim turns up this far past the lowest tilt (the sky, §19.10)
var hover_look := true         # §19.7: the mouse looks round with no button held
const PLAYER_HOLD := 3.0       # s after the player's last mouse look before the framing swing may act again
var auto_return := false       # §19.7: no auto-snap behind the shoulder (R / Space returns); was 4 s idle while walking
var _sh_vert := 0.0

func shoulder_start(fn: Callable) -> void:
	shoulder_fn = fn
	_sh_new = true
	sh_orbit = 0.0
	sh_pitch = 0.0
	sh_look_pitch = 0.0
	sh_look_yaw = 0.0
	_sh_vert = 0.0
	_photo = false
	_intro = -1.0
	camera.near = 0.08

func shoulder_stop() -> void:
	shoulder_fn = Callable()
	camera.near = 0.35
	_sh_drag = false

func in_shoulder() -> bool:
	return shoulder_fn.is_valid()

func swap_shoulder() -> void:
	sh_side = -sh_side

func _shoulder_input(event: InputEvent) -> void:
	# Paul 2026-10-01: right drag orbits a full circle round the person and tilts from near the floor to
	# high above; middle drag (or Alt + right drag) is free-look (the aim only, the camera stays put);
	# the wheel zooms from a face close-up (0.5 m) to 8 m; R (or 4 s without camera input while the person
	# walks) brings the camera back behind the shoulder, smoothly.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			sh_dist = maxf(SH_DMIN, sh_dist * 0.88)
			_sh_idle = 0.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			sh_dist = minf(SH_DMAX, sh_dist * 1.13)
			_sh_idle = 0.0
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_sh_drag = mb.pressed
			_sh_look_drag = mb.pressed and mb.alt_pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_sh_drag = mb.pressed
			_sh_look_drag = mb.pressed
	elif event is InputEventMouseMotion and (_sh_drag or hover_look):
		# (V5 §19.7, Paul 2026-10-04: the mouse looks round with no button held (over the 3D view only: the HUD
		# takes the events over its panels); dragging works as before)
		var mm: InputEventMouseMotion = event
		_sh_idle = 0.0
		_sh_returning = false
		var kx: float = 0.006 if _sh_drag else HOVER_K
		if _sh_look_drag:
			sh_look_yaw = clampf(sh_look_yaw - mm.relative.x * 0.005, -PI, PI)
			sh_look_pitch = clampf(sh_look_pitch - mm.relative.y * 0.004, -1.2, LOOK_UP_MAX)
		else:
			sh_orbit = wrapf(sh_orbit - mm.relative.x * kx, -PI, PI)
			# one vertical axis: the camera tilts from high above down to near the floor, and past that the aim
			# turns up toward the sky (to about 80 deg), §19.7 / §19.10
			_sh_vert = clampf(_sh_vert + mm.relative.y * kx * 0.7, SH_PMIN - LOOK_UP_MAX, SH_PMAX)
			sh_pitch = clampf(_sh_vert, SH_PMIN, SH_PMAX)
			sh_look_pitch = maxf(0.0, SH_PMIN - _sh_vert)
	elif event is InputEventKey and event.pressed and not event.echo and not _typing():
		var k: int = (event as InputEventKey).physical_keycode
		if k == KEY_Q or k == KEY_E:
			swap_shoulder()
		elif k == KEY_R:
			shoulder_return()

## Back behind the shoulder (orbit, tilt and free-look to 0; the zoom stays), smoothly.
func shoulder_return() -> void:
	_sh_vert = 0.0
	sh_orbit = 0.0
	sh_pitch = 0.0
	sh_look_yaw = 0.0
	sh_look_pitch = 0.0
	_sh_returning = true

## One camera "shot" relative to the person: distance, orbit (rad, 0 = behind), tilt, free-look yaw and
## pitch. The follow view's mouse sets these; a later "watch" mode (V5 §15.2: cinematic automatic shots)
## drives the same targets, so it gets the same springs, wall rule and ceiling.
func set_shot(dist: float, orbit: float, pitch: float, look_yaw: float = 0.0, look_pitch: float = 0.0) -> void:
	sh_dist = clampf(dist, SH_DMIN, SH_DMAX)
	sh_orbit = wrapf(orbit, -PI, PI)
	sh_pitch = clampf(pitch, SH_PMIN, SH_PMAX)
	_sh_vert = sh_pitch
	sh_look_yaw = clampf(look_yaw, -PI, PI)
	sh_look_pitch = clampf(look_pitch, -1.2, 1.2)
	_sh_idle = 0.0
	_sh_returning = false

## One frame of the follow view. Returns false when the person is gone.
var prof_us := {}              # measurement: microseconds per part of the follow frame (sums; read and reset by tools)
func _shoulder_process(delta: float) -> bool:
	var _t0: int = Time.get_ticks_usec()
	var r: bool = _shoulder_process2(delta)
	prof_us["total"] = int(prof_us.get("total", 0)) + Time.get_ticks_usec() - _t0
	prof_us["frames"] = int(prof_us.get("frames", 0)) + 1
	return r

func _shoulder_process2(delta: float) -> bool:
	var _tsf: int = Time.get_ticks_usec()
	var s = shoulder_fn.call()
	prof_us["body_fn"] = int(prof_us.get("body_fn", 0)) + Time.get_ticks_usec() - _tsf
	if s == null:
		shoulder_stop()
		return false
	var pos: Vector3 = s[0]
	var body_yaw: float = float(s[1])
	var eye_h: float = float(s[2]) if (s as Array).size() > 2 else 1.65
	var dt: float = clampf(delta, 0.0, 0.1)
	var rate_k: float = clampf(sqrt(maxf(float(s[4]), 1.0)), 1.0, 2.0) if (s as Array).size() > 4 else 1.0
	# A jump (another person, a fade move, a load): start again from the body.
	if not _sh_new and _sh_p.distance_to(pos) > 4.0:
		_sh_new = true
	if _sh_new:
		_sh_heading = body_yaw
		_sh_hvel = 0.0
		_sh_p = pos
		_sh_pv = Vector3.ZERO
		_sh_bu = Vector3.ZERO
		_sh_bprev = pos
		_sh_eh = eye_h
		_sh_ehv = 0.0
		_sh_d = sh_dist
		_sh_dv = 0.0
		_sh_side_s = sh_side
		_sh_sv = 0.0
		_sh_o = sh_orbit
		_sh_ov = 0.0
		_sh_pt = sh_pitch
		_sh_ptv = 0.0
		_sh_ly = sh_look_yaw
		_sh_lyv = 0.0
		_sh_lp = sh_look_pitch
		_sh_lpv = 0.0
		_sh_cy = INF
		_sh_idle = 0.0
	elif dt > 0.0:
		# The body's velocity, low-passed, is fed forward: a steady walk has no lag and the small
		# ripple of the drawn walk is filtered. The spring takes the rest (per axis, relative velocity).
		_sh_bu = _sh_bu.lerp((pos - _sh_bprev) / dt, 1.0 - exp(-dt * SH_W_VEL))
		_sh_bprev = pos
		var pred: Vector3 = _sh_p + _sh_bu * dt
		for ax in 3:
			var r: Vector2 = _crit(pred[ax], _sh_pv[ax] - _sh_bu[ax], pos[ax], SH_W_PIVOT, dt)
			_sh_p[ax] = r.x
			_sh_pv[ax] = r.y + _sh_bu[ax]
		# Heading: small turns (idle sway, a step aside) barely move the camera, a real turn is
		# followed in about 1 s; the spring rate blends between the two (no switch).
		var e: float = angle_difference(body_yaw, _sh_heading)
		var wh: float = lerpf(1.4, 3.2, smoothstep(0.15, 0.6, absf(e)))
		# At 2x-4x the person turns 2-4 times as fast on screen: the heading keeps up (sqrt of the rate,
		# at most 2.2 x), so a runner at 4x does not leave the frame on a corner.
		if (s as Array).size() > 4:
			wh *= clampf(sqrt(maxf(float(s[4]), 1.0)), 1.0, 2.2)
		# Absolute heading and turn rate (the body yaw is the moving target). The turn rate changes by
		# at most SH_HACC rad/s^2 and is at most SH_HRATE: the camera circles the person at ~2 m, so its
		# acceleration is 2 m x rate^2 (at 4x a spring alone gave 7-15 mm camera jerk, 2026-10-01).
		var rh: Vector2 = _crit(_sh_heading, _sh_hvel, _sh_heading - e, wh, dt)
		# At 2x-4x a heading that trails by a lot (the person turned a corner 4 x as fast) may turn up to
		# sqrt(rate) x faster: trailing 80 deg behind a 4x walker put the free eye 1.2 m outside a corridor
		# and the wall rule then swept it (100-400 mm camera jerk, 2026-10-02). Small errors keep the caps.
		var big: float = 1.0 + (rate_k - 1.0) * smoothstep(0.35, 0.9, absf(e)) * head_boost
		var hacc: float = SH_HACC * big
		var hv: float = clampf(clampf(rh.y, _sh_hvel - hacc * dt, _sh_hvel + hacc * dt), -SH_HRATE * big, SH_HRATE * big)
		_sh_heading = rh.x if hv == rh.y else _sh_heading + (_sh_hvel + hv) * 0.5 * dt
		_sh_hvel = hv
		var re: Vector2 = _crit(_sh_eh, _sh_ehv, eye_h, SH_W_EYE, dt)
		_sh_eh = re.x
		_sh_ehv = re.y
		var rd: Vector2 = _crit(_sh_d, _sh_dv, sh_dist, SH_W_DIST, dt)
		_sh_d = rd.x
		_sh_dv = rd.y
		var rs: Vector2 = _crit(_sh_side_s, _sh_sv, sh_side, 6.0, dt)
		_sh_side_s = rs.x
		_sh_sv = rs.y
		# Orbit, tilt and free-look ease to their targets (the mouse sets the targets); a return eases slower.
		_sh_idle += dt
		var moving: bool = _sh_bu.length() > 0.5
		if auto_return and _sh_idle > SH_RETURN_S and moving and (absf(sh_orbit) > 0.001 or absf(sh_pitch) > 0.001 or absf(sh_look_yaw) > 0.001 or absf(sh_look_pitch) > 0.001):
			shoulder_return()
		var wo: float = SH_W_RETURN if _sh_returning else SH_W_ORBIT
		var ro: Vector2 = _crit(_sh_o, _sh_ov, _sh_o + angle_difference(_sh_o, sh_orbit), wo, dt)
		_sh_o = wrapf(ro.x, -PI, PI)
		_sh_ov = ro.y
		var rp: Vector2 = _crit(_sh_pt, _sh_ptv, sh_pitch, wo, dt)
		_sh_pt = rp.x
		_sh_ptv = rp.y
		var rly: Vector2 = _crit(_sh_ly, _sh_lyv, _sh_ly + angle_difference(_sh_ly, sh_look_yaw), wo, dt)
		_sh_ly = rly.x
		_sh_lyv = rly.y
		var rlp: Vector2 = _crit(_sh_lp, _sh_lpv, sh_look_pitch, wo, dt)
		_sh_lp = rlp.x
		_sh_lpv = rlp.y
		if _sh_returning and absf(angle_difference(_sh_o, 0.0)) < 0.01 and absf(_sh_pt) < 0.01 and absf(_sh_ly) < 0.01:
			_sh_returning = false
	# V5 §3 (critic round 29): exactly eye height + 0.15 m; a seated or lying person gets a little more
	# height so the camera still sees over them.
	var lift: float = maxf(0.0, 1.65 - _sh_eh) * 0.5
	var pivot: Vector3 = _sh_p + Vector3(0.0, _sh_eh + SH_UP, 0.0)
	# The shoulder offset shrinks with the zoom (a face close-up looks at the face, not past it).
	# (indoors the shoulder offset eases to indoor_side x: a lens 0.55 m to the side of the person in a 2-3 m wide
	# space faced the side wall in 4-6 of 30 shots, 2026-10-03)
	var ind_t: float = indoor_side if ((s as Array).size() > 3 and bool(s[3])) else 1.0
	_sh_side_k = move_toward(_sh_side_k, ind_t, dt * 0.8)
	# (at a doorway the lens comes in behind the person on the door's line: the 0.55 m shoulder offset put the frame
	# centre on the door housing beside the opening in 2-3 of 30 shots and most bad probe frames, round 5)
	var door_t := 1.0
	if door_fn.is_valid() and door_side < 0.999:
		var ddp: float = minf(float(door_fn.call(_sh_p)), float(door_fn.call(_sh_eye if _sh_eye != Vector3.ZERO else _sh_p)))
		door_t = lerpf(door_side, 1.0, smoothstep(door_r0, door_r1, ddp))
	if dt > 0.0:
		var rdk: Vector2 = _crit(_sh_door_k, _sh_door_kv, door_t, 4.0, dt)
		_sh_door_k = rdk.x
		_sh_door_kv = rdk.y
	var side: float = SH_SIDE * _sh_side_s * clampf(_sh_d / 1.9, 0.25, 1.0) * _sh_side_k * _sh_door_k
	# Occluders on the sight line (orchestrator 2026-10-02: a dome pillar between the lens and the person):
	# the camera first swings round the person by the smallest of +-15/30/45/60 deg that clears both lines
	# (chest, head), eased; it swings back once the plain view has been clear for SH_OCC_HOLD s.
	# (§19.7: the camera never fights the player: no automatic swing for PLAYER_HOLD s after a mouse look)
	if occ_fn.is_valid() and occ_on > 0.5 and not _sh_new and dt > 0.0 and _sh_idle > PLAYER_HOLD:
		# The framing rule (critic round 41): the person in sight (no occluder on the chest / head lines) AND no
		# surface closer than 0.8 m across the centre of the frame. The camera swings round the person by the
		# smallest of +-15..90 deg that gives both, eased; back behind the shoulder once the plain view has
		# been good for SH_OCC_HOLD s. A short block (a doorway jamb passing) waits SH_OCC_WAIT s first.
		var _tf: int = Time.get_ticks_usec()
		var h0: float = _sh_heading + _sh_o
		_sh_chk_clock -= dt
		if _sh_chk_clock <= 0.0:
			# The view is judged from the camera as drawn (2026-10-03). Bad for SH_OCC_WAIT s: a search over
			# swings and boom lengths whose predicted eye (the wall rule's target, under the ceiling, not in a
			# solid cell) sees the person with a clear frame centre; the view just left is barred for 3 s, so a
			# wrong prediction does not bring it back. Good for SH_OCC_HOLD s: one step back toward the plain
			# view, if predicted good.
			_sh_chk_clock = 0.1
			var cur_ok: bool = float(occ_fn.call(camera.global_position)) == INF and (not frame_fn.is_valid() or bool(frame_fn.call(camera.global_position, -camera.global_transform.basis.z)))
			# (and the person on screen: head and chest inside the frame)
			if cur_ok:
				var vps: Vector2 = camera.get_viewport().get_visible_rect().size
				for hh in [1.25, 1.6]:
					var pt: Vector3 = _sh_p + Vector3(0.0, hh * (_sh_eh / 1.65), 0.0)
					if camera.is_position_behind(pt):
						cur_ok = false
					else:
						var sp: Vector2 = camera.unproject_position(pt)
						if sp.x < 0.0 or sp.y < 0.0 or sp.x > vps.x or sp.y > vps.y:
							cur_ok = false
			dbg_cur_ok = cur_ok
			_sh_fr_cool -= 0.1
			for k in _sh_bar.keys():
				_sh_bar[k] = float(_sh_bar[k]) - 0.1
				if float(_sh_bar[k]) <= 0.0:
					_sh_bar.erase(k)
			var cur_key: String = "%d:%d" % [int(round(rad_to_deg(_sh_oo_t) * _sh_side_s)), int(round(_sh_od_t * 100.0))]
			if cur_ok:
				_sh_oo_clear += 0.1
				_sh_oo_blk = 0.0
				if _sh_oo_clear > SH_OCC_HOLD and _sh_fr_cool <= 0.0 and (_sh_od_t < 0.999 or absf(_sh_oo_t) > 0.001):
					var nd: float = minf(1.0, _sh_od_t + 0.2)
					var no: float = move_toward(_sh_oo_t, 0.0, deg_to_rad(15.0)) if nd >= 0.999 else _sh_oo_t
					var nk: String = "%d:%d" % [int(round(rad_to_deg(no) * _sh_side_s)), int(round(nd * 100.0))]
					if not _sh_bar.has(nk) and _view_ok(pivot, h0 + no, side, lift, nd):
						_sh_od_t = nd
						_sh_oo_t = no
						_sh_fr_cool = 0.6
					_sh_oo_clear = SH_OCC_HOLD * 0.5
			else:
				_sh_oo_clear = 0.0
				_sh_oo_blk += 0.1
				if _sh_oo_blk > SH_OCC_WAIT and _sh_fr_cool <= 0.0:
					var found := false
					var tried := 0
					while tried < SH_SEARCH_STEP and _sh_search_i < SEARCH_CANDS.size():
						var cnd: Array = SEARCH_CANDS[_sh_search_i]
						_sh_search_i += 1
						var ck: String = "%d:%d" % [int(cnd[0]), int(round(float(cnd[1]) * 100.0))]
						if ck == cur_key or _sh_bar.has(ck):
							continue
						tried += 1
						var a_off: float = deg_to_rad(float(cnd[0])) * _sh_side_s
						if _view_ok(pivot, h0 + a_off, side, lift, float(cnd[1])):
							_sh_bar[cur_key] = 3.0
							_sh_oo_t = a_off
							_sh_od_t = float(cnd[1])
							found = true
							break
					if found or _sh_search_i >= SEARCH_CANDS.size():
						if not found:
							# (nothing predicted good: a 0.75 x boom behind the shoulder; the arm keeps the sight line)
							_sh_bar[cur_key] = 3.0
							_sh_oo_t = 0.0
							_sh_od_t = 0.75
						_sh_search_i = 0
						dbg_search[1 if found else 0] += 1
						_sh_fr_cool = 0.5
		var roo: Vector2 = _crit(_sh_oo, _sh_oov, _sh_oo_t, SH_W_OCC_ORBIT, dt)
		_sh_oo = roo.x
		_sh_oov = roo.y
		var rod: Vector2 = _crit(_sh_od, _sh_odv, _sh_od_t, SH_W_OCC_BOOM, dt)
		_sh_od = rod.x
		_sh_odv = rod.y
		prof_us["framing"] = int(prof_us.get("framing", 0)) + Time.get_ticks_usec() - _tf
	elif _sh_new:
		_sh_oo = 0.0
		_sh_oov = 0.0
		_sh_oo_t = 0.0
		_sh_od = 1.0
		_sh_odv = 0.0
		_sh_od_t = 1.0
	var hd: float = _sh_heading + _sh_o + _sh_oo
	var fwd := Vector3(cos(hd), 0.0, -sin(hd))
	var right := Vector3(sin(hd), 0.0, cos(hd))
	var shoulder_pt: Vector3 = pivot + right * side
	var free: Vector3 = pivot - fwd * _sh_d * _sh_od * cos(_sh_pt) + right * side + Vector3(0.0, lift + _sh_d * _sh_od * sin(_sh_pt), 0.0)
	# The camera never passes a wall. The eye eases in when a wall comes within SH_SOFT of it (fast)
	# and out when the wall is gone (slow, with a dead band, so a wall at the edge does not make it
	# pump); it is never closer than SH_HARD to a wall (a hard clamp, only if the easing is too late).
	# Indoors (roofs on) the walls are the room's and corridor's own (world_view._follow_collide).
	# The camera never passes a wall: the wall rule (world_view._follow_collide) moves the eye to the nearest
	# clear point; that correction eases in fast (SH_W_IN) and out slowly (SH_W_OUT, after a 4 % dead band
	# or 0.6 s), per axis; then the final eye point is kept SH_HARD clear of every wall (no easing).
	var push_t := Vector3.ZERO
	collide_smooth = false
	dbg_free = free
	var soft_eye := free
	if collide_fn.is_valid():
		soft_eye = collide_fn.call(shoulder_pt, free, SH_SOFT, false, SH_KNEE) as Vector3
		push_t = soft_eye - free
	dbg_target = soft_eye
	if collide_smooth:
		# Indoors (2026-10-02): the target is the soft wall rule (world_view._vol_soft, continuous in the free
		# eye except where two volumes meet: a flip of up to ~0.3 m). One symmetric spring takes the flips
		# out; the soft rule again on the result (small knee) keeps the eye off the wall. No hard clamp, no
		# dead band (16 mm camera jerk with the old spring + clamp).
		if _sh_new:
			_sh_push = push_t
			_sh_pushv = Vector3.ZERO
		elif dt > 0.0:
			for ax in 3:
				var rq2: Vector2 = _crit(_sh_push[ax], _sh_pushv[ax], push_t[ax], SH_W_SMOOTH * pow(rate_k, push_rate_p), dt)
				_sh_push[ax] = rq2.x
				_sh_pushv[ax] = rq2.y
	elif _sh_new:
		_sh_push = push_t
		_sh_pushv = Vector3.ZERO
	elif dt > 0.0:
		var more: bool = push_t.length() > _sh_push.length() + 0.005
		var tgt_p: Vector3 = _sh_push
		var wp: float = SH_W_OUT
		_sh_fhold = _sh_fhold + dt if push_t.length() < _sh_push.length() - 0.005 else 0.0
		if more or (push_t - _sh_push).length() > 0.05 and push_t.length() >= _sh_push.length():
			tgt_p = push_t
			wp = SH_W_IN
		elif _sh_push.length() - push_t.length() > 0.04 * _sh_d or _sh_fhold > 0.6:
			tgt_p = push_t
		for ax in 3:
			var rq: Vector2 = _crit(_sh_push[ax], _sh_pushv[ax], tgt_p[ax], wp, dt)
			_sh_push[ax] = rq.x
			_sh_pushv[ax] = rq.y
	var eye: Vector3 = free + _sh_push
	# No body through the camera (2026-10-02): the eye keeps SH_BODY_GAP (plan) off the person's drawn body.
	# A soft rule (identity beyond 2 x the gap, then eased to the gap): it acts only when the camera's
	# heading trails a sharp turn and the person walks toward the lens.
	var bo := Vector2(eye.x - pos.x, eye.z - pos.z)
	var bl: float = bo.length()
	var gap_k: float = SH_BODY_GAP * clampf(_sh_d / 1.9, 0.3, 1.0)
	# (not when the camera looks down from above the head: the high orbit passes over the person)
	if bl < 2.0 * gap_k and eye.y < pos.y + 2.5:
		var bn: Vector2 = bo / bl if bl > 0.001 else Vector2(-fwd.x, -fwd.z)
		var nl: float = gap_k + gap_k * exp((bl - 2.0 * gap_k) / gap_k) if bl < 2.0 * gap_k else bl
		# (phi(L) = gap + gap e^((L - 2 gap) / gap): equal to L with slope 1 at L = 2 gap, never under the gap)
		nl = lerpf(bl, maxf(nl, bl), clampf((pos.y + 2.5 - eye.y) / 0.4, 0.0, 1.0))
		eye.x = pos.x + bn.x * nl
		eye.z = pos.z + bn.y * nl
	# Occluders on the sight line (a pillar, a shelf, a wall end; world_view.follow_occluder): the eye is drawn
	# in toward the pivot to stand in front of the first one (fast in, slow out after OCC_HOLD s), so the person
	# is never seen through a dithered band.
	if occ_fn.is_valid() and occ_on > 0.5:
		var chest: Vector3 = _sh_p + Vector3(0.0, 1.25, 0.0)
		var cl: float = eye.distance_to(chest)
		var allow: float = float(occ_fn.call(eye))
		# (an occluder closer than SH_OCC_MIN to the chest is the person's own spot: pulling in there only puts
		# the lens in their hair; the near fade takes it)
		var want: float = 1.0 if allow == INF or cl < 0.01 or allow < SH_OCC_MIN or _sh_oo_blk <= SH_OCC_WAIT else clampf(allow / cl, 0.2, 1.0)
		if _sh_new:
			_sh_occ = want
			_sh_occv = 0.0
		elif dt > 0.0:
			_sh_occ_hold = 0.0 if want < _sh_occ - 0.01 else _sh_occ_hold + dt
			var w_o: float = SH_W_OCC_IN if want < _sh_occ else (SH_W_OCC_OUT if _sh_occ_hold > SH_OCC_HOLD else 0.0)
			if w_o > 0.0:
				var ro2: Vector2 = _crit(_sh_occ, _sh_occv, want, w_o, dt)
				_sh_occ = ro2.x
				_sh_occv = ro2.y
			else:
				_sh_occv = 0.0
		var k_o: float = _sh_occ
		if k_o < 0.999:
			eye = pivot + (eye - pivot) * clampf(k_o, 0.2, 1.0)
	if collide_fn.is_valid():
		if collide_smooth:
			# (indoors: slide from last frame's eye toward the sprung eye along the walls, so the eye moves
			# continuously; the soft guard on a new view or a jump)
			if slide_fn.is_valid() and not _sh_new and _sh_slide_ok:
				eye = slide_fn.call(shoulder_pt, _sh_slide_prev, eye) as Vector3
			else:
				eye = collide_fn.call(shoulder_pt, eye, SH_HARD, false, SH_KNEE2) as Vector3
			_sh_slide_prev = eye
			_sh_slide_ok = true
		else:
			_sh_slide_ok = false
			eye = collide_fn.call(shoulder_pt, eye, SH_HARD, true)
	# The slide turns a corner of the walls in one frame (a 0.2 m kink at a room-corridor corner), and the
	# rule changes between indoors and outdoors at a door: the eye's offset from the pivot is eased once more
	# (fast, SH_W_FINAL; one spring for every case, so a change of rule is no jump; a steady walk keeps no lag).
	var rel_t: Vector3 = eye - pivot
	if _sh_new or dt <= 0.0:
		_sh_fin = rel_t
		_sh_finv = Vector3.ZERO
	else:
		for ax in 3:
			var rf: Vector2 = _crit(_sh_fin[ax], _sh_finv[ax], rel_t[ax], SH_W_FINAL / pow(rate_k, final_rate_p), dt)
			_sh_fin[ax] = rf.x
			_sh_finv[ax] = rf.y
	eye = pivot + _sh_fin
	_sh_f = clampf(1.0 - (eye - free).length() / maxf(shoulder_pt.distance_to(free), 0.01), 0.0, 1.0)
	# Under the ceiling (Paul 2026-10-01, roofs on): the ceiling is eased (it changes in steps between a room
	# and a corridor) and applied as a soft limit (no hard clamp on a raw value, 2026-10-02); never below the
	# person's floor + 0.25 m.
	if ceil_fn.is_valid():
		var cy: float = float(ceil_fn.call(pos, eye))
		var tw: Vector3 = Vector3(pivot.x - eye.x, 0.0, pivot.z - eye.z)
		var cy_soft: float = cy
		if tw.length() > 0.01:
			# (and over the person: the camera goes where the person walks; a corridor's lower ceiling is eased
			# into before the camera reaches the doorway, 2026-10-01)
			for k in [0.5, 1.0]:
				cy_soft = minf(cy_soft, float(ceil_fn.call(pos, eye + tw * k)))
		if cy == INF and _sh_cy != INF and not _sh_new and dt > 0.0 and _sh_cy < pivot.y + 1.2:
			# (no ceiling here (a doorway, out of the roof grid): the eased ceiling rises away instead of the limit
			# vanishing in one frame, a 0.1-0.15 m camera jump, 2026-10-03)
			cy = pivot.y + 1.5
			cy_soft = cy
		if cy < INF:
			if _sh_cy == INF or _sh_new:
				_sh_cy = cy_soft
				_sh_cyv = 0.0
			else:
				var rc: Vector2 = _crit(_sh_cy, _sh_cyv, cy_soft, SH_W_CEIL_DOWN if cy_soft < _sh_cy else SH_W_CEIL_UP, dt)
				_sh_cy = rc.x
				_sh_cyv = rc.y
			# soft minimum: identity below (limit - knee), then eases to the limit and never passes it
			var lim: float = _sh_cy - 0.3
			var y0: float = lim - SH_CEIL_KNEE
			if eye.y > y0:
				eye.y = y0 + SH_CEIL_KNEE * (1.0 - exp(-(eye.y - y0) / SH_CEIL_KNEE))
		else:
			_sh_cy = INF
	eye.y = maxf(eye.y, pos.y + 0.25)
	if height_fn.is_valid():
		eye.y = maxf(eye.y, float(height_fn.call(eye.x, eye.z)) + 0.35)
	# The arm (2026-10-03, critic round 41: the person hidden behind a doorway frame, a roof edge, a shelf):
	# nothing DRAWN lies between the point over the person's head (the pivot) and the lens. A sphere swept
	# from the pivot to the eye gives the eased target (in at SH_W_ARM_IN before the thin line is cut); the
	# thin line itself is a hard limit (never a frame with the line cut). Out slowly (SH_W_ARM_OUT). Applied after
	# the final eased offset (before it, the aim took the unsmoothed eye: 88 px head jitter, 2026-10-03).
	var eye_pre: Vector3 = eye
	var _tar: int = Time.get_ticks_usec()
	if arm_fn.is_valid() and arm_on > 0.5:
		var av: Vector3 = eye - pivot
		var al: float = av.length()
		var k_thin := 1.0
		var k_thick := 1.0
		if al > ARM_MIN + ARM_CUT:
			var u: Vector3 = av / al
			# (a surface within ARM_CUT of the lens is cut by the near fade: it hides nothing)
			var c_thin: float = float(arm_fn.call(pivot, eye - u * ARM_CUT, 0.0))
			if c_thin >= 0.0:
				if c_thin < al - ARM_CUT - 0.001:
					k_thin = clampf((c_thin + ARM_CUT - ARM_MARGIN) / al, ARM_MIN / al, 1.0)
				# (the thick arm: two more lines from beside the pivot, ARM_R to each side, converging on the eye; a
				# sphere sweep touched the ceiling and the walls the eye is kept 0.25 m off, all the time)
				var sd: Vector3 = u.cross(Vector3.UP).normalized() * ARM_R
				for sp in [sd, -sd]:
					var a2: Vector3 = pivot + sp
					var l2: float = a2.distance_to(eye)
					var c2: float = float(arm_fn.call(a2, a2.lerp(eye, (l2 - ARM_CUT) / l2), 0.0))
					if c2 >= 0.0 and c2 < l2 - ARM_CUT - 0.001:
						k_thick = minf(k_thick, clampf((c2 + ARM_CUT - ARM_MARGIN) / l2, ARM_MIN / al, 1.0))
		var k_t: float = minf(k_thin, k_thick)
		# (a dead band: a surface grazing the thick lines toggled the target by 1-3 %, 2-6 cm of camera, and the
		# fast spring turned that into 15-30 mm jerk spikes at 4x, 2026-10-03)
		if k_t > 0.96:
			k_t = 1.0
		if _sh_new or dt <= 0.0:
			_sh_arm = k_t
			_sh_armv = 0.0
		else:
			var ra: Vector2 = _crit(_sh_arm, _sh_armv, k_t, (arm_w_in / rate_k) if k_t < _sh_arm else SH_W_ARM_OUT, dt)
			_sh_arm = ra.x
			_sh_armv = ra.y
		if _sh_arm > k_thin + arm_slack:
			dbg_arm[0] += 1
			dbg_arm[2] += (_sh_arm - k_thin) * al
			_sh_arm = k_thin + arm_slack
			_sh_armv = 0.0
		if _sh_arm < 0.999:
			dbg_arm[1] += 1
		if _sh_arm < 0.999:
			eye = pivot + av * _sh_arm
	prof_us["arm"] = int(prof_us.get("arm", 0)) + Time.get_ticks_usec() - _tar
	_sh_pull = _sh_f
	_sh_eyeh = _sh_eh
	_sh_new = false
	# The aim keeps the framing of critic round 29 at any orbit, tilt, zoom and wall pull-in: the person
	# stands where the free (unpulled) camera would see them: on the left third (right shoulder), the
	# head SH_DOWN above the centre. The aim is turned from the line to the person by those two angles,
	# then by the free-look offsets.
	# (from the eye; from the FREE camera point when the eye is pressed close to the head: from beside the
	# head the line to the person swung the aim by up to 1300 deg/s, 2026-10-01)
	# (the arm pulls the eye along its line to the pivot: the aim of the unpulled eye keeps the person framed)
	# (the free point only within 0.9 m of the pivot: from 1.2 m the aim from the free point lost the person off
	# the frame's left edge whenever the wall rule held the eye 0.6-1.0 m from the head, 2026-10-03)
	var src: Vector3 = eye_pre.lerp(free, clampf((0.9 - eye_pre.distance_to(pivot)) / 0.45, 0.0, 1.0))
	var to_p: Vector3 = pivot - src
	var yaw_p: float = atan2(-to_p.z, to_p.x)
	var pit_p: float = atan2(to_p.y, Vector2(to_p.x, to_p.z).length())
	var dp: float = eye.distance_to(pivot)
	if dp < 1.6:
		# (an eye close to the pivot, drawn in by the arm or held in by the walls, looks down at the person from
		# its own place: from the unpulled eye's pitch the chest was below the frame, 2026-10-03)
		var tp: Vector3 = pivot - Vector3(0.0, 0.3 * clampf((1.6 - dp) / 1.0, 0.0, 1.0), 0.0) - eye
		var wa: float = clampf((1.6 - dp) / 0.4, 0.0, 1.0)
		# (the 10 deg drop below the line to the pivot is taken back as well: aimed at the upper chest)
		pit_p = lerpf(pit_p, atan2(tp.y, Vector2(tp.x, tp.z).length()) + deg_to_rad(10.0), wa)
	var off_yaw: float = atan2(side, maxf(_sh_d * cos(_sh_pt), 0.05))
	var ay: float = yaw_p - off_yaw + _sh_ly
	var ap: float = clampf(pit_p - deg_to_rad(10.0) - lift * 0.25 + _sh_lp, -1.45, 1.3)
	var aim := Vector3(cos(ay) * cos(ap), sin(ap), -sin(ay) * cos(ap))
	_sh_eye = eye
	focus = pos
	distance = eye.distance_to(pos)
	camera.global_position = eye
	camera.look_at(eye + aim, Vector3.UP)
	if probe_fn.is_valid():
		var _tp: int = Time.get_ticks_usec()
		probe_fn.call(self, delta)
		prof_us["probe"] = int(prof_us.get("probe", 0)) + Time.get_ticks_usec() - _tp
	return true

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.35
	camera.far = 1400.0
	add_child(camera)
	camera.current = true

func jump_to(p: Vector3) -> void:
	focus = p

## Cinematic fly-in: from high above the plain down to the lander. Any input skips it.
func play_intro() -> void:
	_intro = 0.0
	_photo = false

func skip_intro() -> void:
	_intro = -1.0

func is_intro() -> bool:
	return _intro >= 0.0

## Slow orbit around `center` for the title screen and screenshots.
func photo_orbit(center: Vector3, radius: float = 70.0, height: float = 22.0, speed: float = 0.05) -> void:
	_photo = true
	_intro = -1.0
	_photo_center = center
	_photo_radius = radius
	_photo_height = height
	_photo_speed = speed
	_photo_angle = yaw

func stop_photo() -> void:
	_photo = false

func shake(amount: float) -> void:
	if not shake_enabled:
		_shake = 0.0
		return
	_shake = maxf(_shake, amount)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 0.5:
		_mouse_seen = true
	if _intro >= 0.0 and ((event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		_intro = -1.0

func _unhandled_input(event: InputEvent) -> void:
	if in_shoulder():
		_shoulder_input(event)
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_distance = maxf(min_distance, target_distance * 0.86)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_distance = minf(max_distance, target_distance * 1.16)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
	elif event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event
		_yaw_t -= mm.relative.x * 0.006
		_pitch_t = clampf(_pitch_t + mm.relative.y * 0.005, deg_to_rad(12.0), deg_to_rad(86.0))
	elif event is InputEventPanGesture:
		var pg: InputEventPanGesture = event
		target_distance = clampf(target_distance * (1.0 + pg.delta.y * 0.05), min_distance, max_distance)

## The steepest pitch allowed at a distance: close up the camera looks across the base.
func _pitch_cap(d: float) -> float:
	return deg_to_rad(lerpf(30.0, 88.0, smoothstep(10.0, 95.0, d)))

func _process(delta: float) -> void:
	_t += delta
	if in_shoulder() and _shoulder_process(delta):
		_yaw_seen = yaw
		_pitch_seen = pitch
		return
	# Direct writes from other scripts become the new targets.
	if absf(yaw - _yaw_seen) > 0.0001:
		_yaw_t = yaw
	if absf(pitch - _pitch_seen) > 0.0001:
		_pitch_t = pitch
	var move := Vector2.ZERO
	if not _typing():
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if Input.is_physical_key_pressed(KEY_Q):
			_yaw_t += delta * 1.4 * pan_speed
		if Input.is_physical_key_pressed(KEY_E):
			_yaw_t -= delta * 1.4 * pan_speed
	# Edge pan only after the mouse has really moved over the window: a pointer parked at
	# (0, 0) (headless browser, a fresh tab) panned the view and cancelled follow (critic round 6).
	if edge_pan and _mouse_seen and not ui_blocks_mouse and get_window().has_focus():
		var mp: Vector2 = get_viewport().get_mouse_position()
		var size: Vector2 = get_viewport().get_visible_rect().size
		if mp.x >= 0 and mp.y >= 0 and mp.x <= size.x and mp.y <= size.y:
			if mp.x < 6: move.x -= 1.0
			if mp.x > size.x - 6: move.x += 1.0
			if mp.y < 6: move.y -= 1.0
			if mp.y > size.y - 6: move.y += 1.0
	# Damped panning: velocity eases in and out instead of starting and stopping dead.
	var want := Vector3.ZERO
	if move != Vector2.ZERO:
		follow_fn = Callable()
		_photo = false
		var speed: float = distance * 0.95 * pan_speed
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		want = (right * move.x - fwd * move.y).normalized() * speed
	_vel = _vel.lerp(want, 1.0 - exp(-delta * 10.0))
	focus += _vel * delta
	if follow_fn.is_valid():
		var p = follow_fn.call()
		if p != null:
			focus = focus.lerp(p, 1.0 - exp(-delta * 6.0))
		else:
			follow_fn = Callable()
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	if height_fn.is_valid():
		focus.y = lerpf(focus.y, height_fn.call(focus.x, focus.z), 1.0 - exp(-delta * 5.0))
	distance = lerpf(distance, target_distance, 1.0 - exp(-delta * 7.0))
	yaw = lerp_angle(yaw, _yaw_t, 1.0 - exp(-delta * 9.0))
	var cap: float = _pitch_cap(distance)
	pitch = lerpf(pitch, minf(_pitch_t, cap), 1.0 - exp(-delta * 8.0))
	var eye_yaw: float = yaw
	var eye_pitch: float = pitch
	var eye_dist: float = distance
	var look: Vector3 = focus
	if _photo:
		_photo_angle += delta * _photo_speed
		eye_yaw = _photo_angle
		eye_pitch = atan2(_photo_height, _photo_radius)
		eye_dist = Vector2(_photo_radius, _photo_height).length()
		look = _photo_center
	if _intro >= 0.0:
		_intro += delta
		var k: float = clampf(_intro / INTRO_SECONDS, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - k, 3.0)
		eye_yaw = yaw + deg_to_rad(130.0) * (1.0 - e)
		eye_pitch = lerpf(deg_to_rad(14.0), pitch, smoothstep(0.0, 1.0, k))
		eye_dist = lerpf(260.0, distance, e)
		look = focus + Vector3(0, 30.0 * (1.0 - e), 0)
		if k >= 1.0:
			_intro = -1.0
	var dirv := Vector3(sin(eye_yaw) * cos(eye_pitch), sin(eye_pitch), cos(eye_yaw) * cos(eye_pitch))
	var eye: Vector3 = look + dirv * eye_dist
	# Never below the ground (the camera flattens close to the surface).
	if height_fn.is_valid():
		var gy: float = height_fn.call(clampf(eye.x, bounds.position.x, bounds.end.x), clampf(eye.z, bounds.position.y, bounds.end.y))
		eye.y = maxf(eye.y, gy + 1.6)
	if not shake_enabled:
		_shake = 0.0
	if _shake > 0.0:
		_shake = move_toward(_shake, 0.0, delta * 1.5)
		eye += Vector3(sin(_t * 31.0), sin(_t * 27.0 + 1.3), cos(_t * 29.0)) * _shake * 0.25 * clampf(distance / 60.0, 0.4, 2.0)
	camera.global_position = eye
	camera.look_at(look, Vector3.UP)
	_yaw_seen = yaw
	_pitch_seen = pitch

func _typing() -> bool:
	var f: Control = get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
