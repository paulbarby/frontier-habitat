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
