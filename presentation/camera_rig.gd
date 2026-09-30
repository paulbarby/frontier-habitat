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
var sh_dist := 1.9            # m behind; wheel 1.2..4
var sh_orbit := 0.0           # rad, drag orbit about the person, clamp +-70 deg
var sh_pitch := 0.0           # rad, extra pitch from the drag
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
const SH_W_IN := 14.0         # wall pull-in: fast
const SH_W_OUT := 2.5         # release: slow
const SH_SOFT := 0.6          # m: the smoothed eye starts to pull in this far off a wall
const SH_HARD := 0.2          # m: the eye is never closer than this to a wall (no easing)

## One exact step of a critically damped spring (x, v) toward `target` with angular frequency w.
static func _crit(x: float, v: float, target: float, w: float, dt: float) -> Vector2:
	var e: float = x - target
	var ex: float = exp(-w * dt)
	var tmp: float = (v + w * e) * dt
	return Vector2(target + (e + tmp) * ex, (v - w * tmp) * ex)
const SH_SIDE := 0.55
const SH_UP := 0.15
const SH_ORBIT_MAX := 1.2217  # 70 deg

func shoulder_start(fn: Callable) -> void:
	shoulder_fn = fn
	_sh_new = true
	sh_orbit = 0.0
	sh_pitch = 0.0
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
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			sh_dist = maxf(1.2, sh_dist * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			sh_dist = minf(4.0, sh_dist * 1.13)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_sh_drag = mb.pressed
	elif event is InputEventMouseMotion and _sh_drag:
		var mm: InputEventMouseMotion = event
		sh_orbit = clampf(sh_orbit - mm.relative.x * 0.006, -SH_ORBIT_MAX, SH_ORBIT_MAX)
		sh_pitch = clampf(sh_pitch + mm.relative.y * 0.004, -0.35, 0.6)
	elif event is InputEventKey and event.pressed and not event.echo and not _typing():
		var k: int = (event as InputEventKey).physical_keycode
		if k == KEY_Q or k == KEY_E:
			swap_shoulder()

## One frame of the follow view. Returns false when the person is gone.
func _shoulder_process(delta: float) -> bool:
	var s = shoulder_fn.call()
	if s == null:
		shoulder_stop()
		return false
	var pos: Vector3 = s[0]
	var body_yaw: float = float(s[1])
	var eye_h: float = float(s[2]) if (s as Array).size() > 2 else 1.65
	var dt: float = clampf(delta, 0.0, 0.1)
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
		# at most SH_HACC rad/s^2: at 4x a spring alone swung the camera round a 2 m circle at up to
		# 12 rad/s^2 after each corner (7-15 mm camera jerk, 2026-10-01). The person stays in frame
		# (the camera always looks along its heading at the pivot).
		var rh: Vector2 = _crit(_sh_heading, _sh_hvel, _sh_heading - e, wh, dt)
		var hv: float = clampf(rh.y, _sh_hvel - SH_HACC * dt, _sh_hvel + SH_HACC * dt)
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
	# V5 §3 (critic round 29): exactly eye height + 0.15 m; a seated or lying person gets a little more
	# height so the camera still sees over them.
	var lift: float = maxf(0.0, 1.65 - _sh_eh) * 0.5
	var hd: float = _sh_heading + sh_orbit
	var fwd := Vector3(cos(hd), 0.0, -sin(hd))
	var right := Vector3(sin(hd), 0.0, cos(hd))
	var pivot: Vector3 = _sh_p + Vector3(0.0, _sh_eh + SH_UP, 0.0)
	var shoulder_pt: Vector3 = pivot + right * SH_SIDE * _sh_side_s
	var free: Vector3 = pivot - fwd * _sh_d * cos(sh_pitch) + right * SH_SIDE * _sh_side_s + Vector3(0.0, lift + _sh_d * sin(sh_pitch), 0.0)
	# The camera never passes a wall. The eye eases in when a wall comes within SH_SOFT of it (fast)
	# and out when the wall is gone (slow, with a dead band, so a wall at the edge does not make it
	# pump); it is never closer than SH_HARD to a wall (a hard clamp, only if the easing is too late).
	var f_soft := 1.0
	var f_hard := 1.0
	if collide_fn.is_valid():
		var ol: float = maxf(shoulder_pt.distance_to(free), 0.001)
		f_soft = shoulder_pt.distance_to(collide_fn.call(shoulder_pt, free, SH_SOFT)) / ol
		f_hard = shoulder_pt.distance_to(collide_fn.call(shoulder_pt, free, SH_HARD)) / ol
	if _sh_new:
		_sh_f = f_soft
		_sh_fv = 0.0
	elif dt > 0.0:
		var tgt: float = _sh_f
		var wf: float = SH_W_OUT
		# Out: at once past the dead band, else after 0.6 s of free room (no pumping at a wall edge,
		# and never left a little short for good).
		_sh_fhold = _sh_fhold + dt if f_soft > _sh_f + 0.005 else 0.0
		if f_soft < _sh_f - 0.005:
			tgt = f_soft
			wf = SH_W_IN
		elif f_soft > _sh_f + 0.04 or _sh_fhold > 0.6:
			tgt = f_soft
		var rf: Vector2 = _crit(_sh_f, _sh_fv, tgt, wf, dt)
		_sh_f = rf.x
		_sh_fv = rf.y
	if f_hard < _sh_f:
		_sh_f = f_hard
		_sh_fv = 0.0
	_sh_f = clampf(_sh_f, 0.08, 1.0)
	var eye: Vector3 = shoulder_pt + (free - shoulder_pt) * _sh_f
	if height_fn.is_valid():
		eye.y = maxf(eye.y, float(height_fn.call(eye.x, eye.z)) + 0.35)
	_sh_pull = _sh_f
	_sh_eyeh = _sh_eh
	_sh_new = false
	# The camera looks along the (smoothed) heading, 10 deg down (plus the drag pitch): the person stands
	# on the left third (right shoulder) with room to look ahead (critic round 29).
	var dn: float = deg_to_rad(10.0) + sh_pitch + lift * 0.25
	var aim: Vector3 = fwd * cos(dn) - Vector3(0.0, sin(dn), 0.0)
	_sh_eye = eye
	focus = pos
	distance = eye.distance_to(pos)
	camera.global_position = eye
	camera.look_at(eye + aim, Vector3.UP)
	if probe_fn.is_valid():
		probe_fn.call(self, delta)
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
