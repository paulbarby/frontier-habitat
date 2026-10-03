extends Node3D
## Vehicles on screen (RENDER, V4_DESIGN §5, §8): ART-B's small and medium rover, hopper,
## satellite and launch pad (docs/requests/ART-B-to-RENDER.md §4).
##
## - Rovers drive on the terrain: the body follows the ground under the wheels (pitch, roll),
##   every wheel has its own suspension travel, the wheels spin by the distance driven, the
##   steered wheels turn with the yaw rate, dust from Dust_L/R, head and work lights at dusk,
##   at night and in a shadowed crater.
## - Hopper: spool-up with dust, a ballistic hop with the legs folded and the hover flames on,
##   landing with the legs out.
## - Satellite: an orbit high over the map, wings turning to the sun; launch pad: service arms
##   swing clear, the rocket lifts on its flame and leaves.
## - Crew: ART-NPC's chain step_up -> board -> drive_sit / ride_sit ... alight -> step_down, with the
##   body origin moved at each cut frame (fx_npc puppets). The medium rover and the hopper are
##   pressurised: the crew fades at the hatch (V4 §8).
##
## Data: SIM's vehicles are not published yet (SIM milestone 3). Until then the vehicles here
## are view-side (`vdemo`); `add()` / `drive_to()` / `hop_to()` are the calls a SIM record will feed.
## Nothing is written to sim.state.

const Models = preload("res://presentation/models.gd")
const FILES := {"rover_small": "vehicle_rover_small", "rover_medium": "vehicle_rover_medium", "hopper": "vehicle_hopper", "satellite": "satellite", "launch_pad": "launch_pad"}
const SPEED := {"rover_small": 6.0, "rover_medium": 5.0}
const TURN_RATE := 0.9               # rad/s at most
const CLIP_T := 2.0                  # every crew clip is 60 frames at 30 fps

var view
var sim
var vehicles := {}                   # id -> record
var stats := {"vehicles": 0, "lights": 0, "ms": 0.0}
var _next := 1
var _dust_mat: StandardMaterial3D
# SIM's vehicles (sim/vehicles.gd, milestone 3): sim id -> view id; SIM kinds -> ART-B files.
const KMAP := {"small_rover": "rover_small", "medium_rover": "rover_medium", "hopper": "hopper"}
var _sim := {}
var _hide := {}           # agent id -> true while its body plays the vehicle chain here
var _builds := {}         # depot id -> {node, kind} (a vehicle being built at the depot)

## fx_npc does not draw these agents (their body is a puppet in or beside a vehicle).
func hides(aid: int) -> bool:
	return _hide.has(aid)

func setup(v) -> void:
	view = v
	sim = v.sim

# ---------------------------------------------------------------- build
## A vehicle of `kind` at world transform xf. Returns its id.
func add(kind: String, xf: Transform3D) -> int:
	var path := "res://assets/models/%s.glb" % String(FILES.get(kind, kind))
	if not ResourceLoader.exists(path):
		return -1
	var root: Node3D = (load(path) as PackedScene).instantiate()
	add_child(root)
	var id: int = _next
	_next += 1
	var r := {"id": id, "kind": kind, "node": root, "susp": [], "steer": [], "wheels": [], "hinges": {}, "thr": [], "dust": [], "lights": null,
		"light_nodes": [], "spots": [], "plasma": [], "anchors": {}, "seats": {}, "pos": Vector2(xf.origin.x, xf.origin.z), "yaw": _yaw_of(xf.basis.x),
		"speed": 0.0, "path": [], "path_i": 0, "mode": "park", "hgt": 0.0, "s_legs": 0.0, "s_ramp": 1.0, "s_door": 1.0, "thrust": 0.0,
		"steer_a": 0.0, "crew": [], "t": 0.0, "wb": 3.0, "track": 1.5, "radius": 0.44, "y": xf.origin.y, "pitch": 0.0, "roll": 0.0}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node3D) or n == root:
			continue
		var nm: String = String(n.name)
		var ex: Dictionary = n.get_meta("extras", {}) if n.has_meta("extras") else {}
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			Models._prepare_mesh((n as MeshInstance3D).mesh)
			_plasma_override(n as MeshInstance3D, r)
		if nm.begins_with("Susp_"):
			r["susp"].append({"node": n, "rest": (n as Node3D).transform, "tmin": float(ex.get("travel_min", -0.15)), "tmax": float(ex.get("travel_max", 0.12))})
		elif nm.begins_with("Steer_"):
			r["steer"].append({"node": n, "rest": (n as Node3D).transform, "sign": float(ex.get("steer_sign", 1.0 if nm.contains("F") or nm.contains("1") else -1.0)), "max": deg_to_rad(float(ex.get("steer_max_deg", 25.0)))})
		elif nm.begins_with("Wheel_"):
			r["wheels"].append({"node": n, "rest": (n as Node3D).transform, "rad": float(ex.get("radius", 0.44)), "a": 0.0})
			r["radius"] = float(ex.get("radius", r["radius"]))
		elif nm.begins_with("Door_") or nm == "Ramp" or nm.begins_with("Leg_") or nm.begins_with("Arm_"):
			r["hinges"][nm] = [n, (n as Node3D).transform, float(ex.get("stow_deg", 90.0))]
		elif nm.begins_with("Thruster_"):
			r["thr"].append([n, view.traffic._flame(n as Node3D) if view.get("traffic") != null else null, String(ex.get("role", "hover"))])
		elif nm.begins_with("Dust_"):
			var d := _make_dust()
			(n as Node3D).add_child(d)
			r["dust"].append(d)
		elif nm == "Lights":
			r["lights"] = n
		elif nm.begins_with("Light_"):
			r["light_nodes"].append([n, String(ex.get("role", "head")), float(ex.get("cone_deg", 40.0)), float(ex.get("range_m", 20.0)), Color(String(ex.get("colour", "#fff2dc"))) if String(ex.get("colour", "")).begins_with("#") else Color("fff2dc")])
		elif nm.begins_with("Anchor_"):
			r["anchors"][nm.substr(7)] = n
		elif nm.begins_with("Seat_"):
			r["seats"][int(nm.substr(5))] = n
		elif nm == "Rocket" or nm == "Wing_L" or nm == "Wing_R" or nm == "Dish" or nm == "Cargo":
			r["hinges"][nm] = [n, (n as Node3D).transform, 0.0]
	# Wheelbase and track from the suspension nodes.
	if not (r["susp"] as Array).is_empty():
		var xs: Array = (r["susp"] as Array).map(func(s): return (s["rest"] as Transform3D).origin.x)
		var zs: Array = (r["susp"] as Array).map(func(s): return absf((s["rest"] as Transform3D).origin.z))
		r["wb"] = maxf(1.0, xs.max() - xs.min())
		r["track"] = maxf(0.8, zs.max() * 2.0)
	_make_spots(r)
	vehicles[id] = r
	_place(r, 0.0)
	return id

## Load warm-up (world_view._night_warmup): every vehicle model, its Plasma override, a dust
## emitter and a lit spot, drawn once at xf under the load cover. A rover that first comes into
## view (or into a base light) mid-game otherwise costs 80-150 ms web frames (showcase_v4, 2026-09-28).
func warm_nodes(xf: Transform3D) -> Array:
	var out: Array = []
	for kind in FILES:
		var path := "res://assets/models/%s.glb" % String(FILES[kind])
		if not ResourceLoader.exists(path):
			continue
		var root: Node3D = (load(path) as PackedScene).instantiate()
		add_child(root)
		root.global_transform = xf
		var tmp := {"plasma": []}
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh != null:
				Models._prepare_mesh((mi as MeshInstance3D).mesh)
				_plasma_override(mi as MeshInstance3D, tmp)
		for ln in root.find_children("Lights", "", true, false):
			(ln as Node3D).visible = true
		out.append(root)
	var d := _make_dust()
	add_child(d)
	d.global_position = xf.origin
	d.emitting = true
	out.append(d)
	var sl := SpotLight3D.new()
	sl.spot_range = 30.0
	sl.light_energy = 1.0
	sl.shadow_enabled = false
	add_child(sl)
	sl.global_transform = xf
	out.append(sl)
	return out

func remove(id: int) -> void:
	if not vehicles.has(id):
		return
	var r: Dictionary = vehicles[id]
	for c in r["crew"]:
		if view.npc != null:
			view.npc.puppet_free(String(c["key"]))
	(r["node"] as Node).queue_free()
	vehicles.erase(id)

func clear() -> void:
	for id in vehicles.keys():
		remove(id)

static func _yaw_of(d: Vector3) -> float:
	return atan2(-d.z, d.x)

func _plasma_override(mi: MeshInstance3D, rec: Dictionary) -> void:
	for si in mi.mesh.get_surface_count():
		var m: Material = mi.mesh.surface_get_material(si)
		if m != null and m.resource_name == "Plasma" and m is StandardMaterial3D:
			var d: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
			d.emission_enabled = true
			mi.set_surface_override_material(si, d)
			rec["plasma"].append([d, maxf(1.0, (m as StandardMaterial3D).emission_energy_multiplier)])

## Real spot lights on the head, work, landing and hatch empties (never hidden: see fx_sky.park).
func _make_spots(r: Dictionary) -> void:
	for e in r["light_nodes"]:
		var role: String = e[1]
		if not (role in ["head", "work", "landing", "hatch", "flood"]):
			continue
		var sl := SpotLight3D.new()
		sl.light_color = e[4] if role != "head" else Color("fff4e0")
		sl.spot_angle = clampf(float(e[2]) * 0.5, 15.0, 60.0)
		sl.spot_range = float(e[3])
		sl.spot_attenuation = 0.7
		sl.light_energy = 0.0005
		sl.shadow_enabled = false
		sl.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
		(e[0] as Node3D).add_child(sl)
		r["spots"].append([sl, role, float(e[3])])

func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 48
	p.lifetime = 2.2
	p.local_coords = false
	p.direction = Vector3(1, 0.35, 0)
	p.spread = 22.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.gravity = Vector3(0, 0.25, 0)
	p.scale_amount_min = 0.9
	p.scale_amount_max = 2.2
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_mat.vertex_color_use_as_albedo = true
		_dust_mat.albedo_color = Color(0.92, 0.76, 0.6, 0.55)
		var gt := GradientTexture2D.new()
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		var gg := Gradient.new()
		gg.set_color(0, Color(1, 1, 1, 1))
		gg.set_color(1, Color(1, 1, 1, 0))
		gt.gradient = gg
		_dust_mat.albedo_texture = gt
	q.material = _dust_mat
	p.mesh = q
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.0))
	gr.set_color(1, Color(1, 1, 1, 0.0))
	gr.add_point(0.15, Color(1, 1, 1, 0.7))
	gr.add_point(0.6, Color(1, 1, 1, 0.35))
	p.color_ramp = gr
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

# ---------------------------------------------------------------- orders (what a SIM record feeds)
## Drive along `pts` (Vector2, sim metres). With `sim.nav.vehicle_path` when there is no path.
func drive_to(id: int, target: Vector2) -> bool:
	var r: Dictionary = vehicles.get(id, {})
	if r.is_empty():
		return false
	var pts: Array = []
	if sim.nav.has_method("vehicle_path"):
		var res: Dictionary = sim.nav.vehicle_path(r["pos"], target, "rover")
		if bool(res.get("ok", false)):
			pts = res["pts"]
	if pts.is_empty():
		pts = [r["pos"], target]
	r["path"] = pts
	r["path_i"] = 1
	r["mode"] = "drive"
	return true

func hop_to(id: int, target: Vector2) -> void:
	var r: Dictionary = vehicles.get(id, {})
	if r.is_empty():
		return
	r["from"] = r["pos"]
	r["to"] = target
	r["mode"] = "hop"
	r["t"] = 0.0
	var d: float = (r["pos"] as Vector2).distance_to(target)
	r["apex"] = clampf(d * 0.22, 25.0, 80.0)
	r["cruise"] = d / 22.0 + 2.0

## Crew: a puppet body at seat `n` of vehicle id (enters by the chain).
func board(id: int, seat: int) -> void:
	var r: Dictionary = vehicles.get(id, {})
	if r.is_empty() or view.npc == null:
		return
	var key := "veh%d_%d" % [id, seat]
	var rec: Dictionary = view.npc.puppet(key, "suit", "engineer" if seat == 1 else "scientist")
	if rec.is_empty():
		return
	r["crew"].append({"key": key, "seat": seat, "stage": "step_up", "t": 0.0})

func alight(id: int) -> void:
	var r: Dictionary = vehicles.get(id, {})
	for c in r.get("crew", []):
		if String(c["stage"]) == "seated":
			c["stage"] = "alight"
			c["t"] = 0.0

# ---------------------------------------------------------------- per frame
## Zoomed out past SHADOW_OFF_D (not following), vehicles cast no shadows, like the people (overview: two rovers
## drew 50 shadow surfaces, round 5); each mesh's own setting comes back when the camera comes in.
const SHADOW_OFF_D := 60.0
var _sh_far := false
var _sh_key := -1
func _vehicle_shadows() -> void:
	var fid = view.get("follow_id")
	var far: bool = float(view.camera_distance) > SHADOW_OFF_D and (fid == null or int(fid) < 0)
	if far == _sh_far and vehicles.size() == _sh_key:
		return
	_sh_far = far
	_sh_key = vehicles.size()
	for id in vehicles:
		var nd = vehicles[id].get("node")
		if not (nd is Node3D):
			continue
		for g in (nd as Node3D).find_children("*", "GeometryInstance3D", true, false):
			var gi: GeometryInstance3D = g
			if not gi.has_meta("cast0"):
				gi.set_meta("cast0", gi.cast_shadow)
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else int(gi.get_meta("cast0"))

func sync(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	var dt: float = delta * maxf(float(view.game_rate), float(view.demo_rate))
	_vehicle_shadows()
	_sync_sim(delta)
	if not test_off.has("builds"):
		_sync_builds(delta)
	var nl := 0
	for id in vehicles:
		var r: Dictionary = vehicles[id]
		if r.has("sim_id"):
			if String(r["kind"]) == "hopper":
				_sim_hop(r, delta, dt)
			else:
				_sim_drive(r, delta)
			if not test_off.has("crewpose"):
				_crew(r, dt)
			nl += _lights(r)
			continue
		match String(r["kind"]):
			"rover_small", "rover_medium":
				_drive(r, dt)
			"hopper":
				_hop(r, dt)
			"satellite":
				_orbit(r, dt)
			"launch_pad":
				_launch(r, dt)
		_crew(r, dt)
		nl += _lights(r)
	stats["vehicles"] = vehicles.size()
	stats["lights"] = nl
	stats["ms"] = snappedf(lerpf(float(stats["ms"]), (Time.get_ticks_usec() - t0) / 1000.0, 0.1), 0.001)

func _drive(r: Dictionary, dt: float) -> void:
	var want_v := 0.0
	var crew_busy := false
	for c in r["crew"]:
		if String(c["stage"]) != "seated":
			crew_busy = true
	if String(r["mode"]) == "drive" and not crew_busy:
		var pts: Array = r["path"]
		var i: int = r["path_i"]
		if i >= pts.size():
			r["mode"] = "park"
		else:
			var goal: Vector2 = pts[i]
			var pos: Vector2 = r["pos"]
			if pos.distance_to(goal) < 2.5 and i < pts.size() - 1:
				r["path_i"] = i + 1
				goal = pts[i + 1]
			var to: Vector2 = goal - pos
			var last: bool = int(r["path_i"]) >= pts.size() - 1
			want_v = float(SPEED.get(r["kind"], 5.0))
			if last:
				want_v = minf(want_v, to.length() * 0.8)
				if to.length() < 0.4:
					r["mode"] = "park"
					want_v = 0.0
			# Heading: turn toward the next point, limited, slower in tight turns.
			var yaw_t: float = atan2(-to.y, to.x)
			var dy: float = wrapf(yaw_t - float(r["yaw"]), -PI, PI)
			var turn: float = clampf(dy, -TURN_RATE * dt, TURN_RATE * dt)
			r["yaw"] = float(r["yaw"]) + turn
			want_v *= clampf(1.2 - absf(dy) / 1.2, 0.25, 1.0)
			var yaw_rate: float = turn / maxf(dt, 0.0001)
			r["steer_a"] = lerpf(float(r["steer_a"]), atan(float(r["wb"]) * yaw_rate / maxf(float(r["speed"]), 0.6)), 1.0 - exp(-dt * 6.0))
	var v: float = move_toward(float(r["speed"]), want_v, 2.0 * dt)
	r["speed"] = v
	var fwd2 := Vector2(cos(float(r["yaw"])), -sin(float(r["yaw"])))
	r["pos"] = (r["pos"] as Vector2) + fwd2 * v * dt
	if v < 0.05:
		r["steer_a"] = lerpf(float(r["steer_a"]), 0.0, 1.0 - exp(-dt * 2.0))
	_place(r, v * dt)
	for d in r["dust"]:
		(d as CPUParticles3D).emitting = v > 1.0
	# Tailgate / ramp closed while moving; the medium rover's ramp is down when parked with crew.
	var ramp_want: float = 1.0 if v > 0.05 or String(r["mode"]) == "drive" else (0.0 if String(r["kind"]) == "rover_medium" else 1.0)
	r["s_ramp"] = move_toward(float(r["s_ramp"]), ramp_want, dt / 2.5)
	for nm in r["hinges"]:
		if nm == "Ramp" or nm.begins_with("Door_Hatch"):
			_hinge(r["hinges"][nm], float(r["s_ramp"]))
		elif nm == "Door_Tailgate":
			_hinge(r["hinges"][nm], 1.0)

## Body on the ground under the wheels; suspension, steering and wheel spin.
func _place(r: Dictionary, moved: float) -> void:
	var pos: Vector2 = r["pos"]
	var yaw: float = r["yaw"]
	var fwd := Vector3(cos(yaw), 0, -sin(yaw))
	var left := Vector3(-sin(yaw), 0, -cos(yaw))   # Godot left = -Z of the vehicle
	var hw: float = float(r["wb"]) * 0.5
	var ht: float = float(r["track"]) * 0.5
	var p3 := Vector3(pos.x, 0, pos.y)
	var hf: float = _h(p3 + fwd * hw)
	var hb: float = _h(p3 - fwd * hw)
	var hl: float = _h(p3 + left * ht)
	var hr: float = _h(p3 - left * ht)
	# On a crest (a crater rim) the body rests on the high middle, not the mean of the ends.
	var y: float = maxf((hf + hb + hl + hr) * 0.25, _h(p3) - 0.15)
	# The body tilts at most 15 deg (critic round 22) (the suspension takes the rest); a steeper slope is SIM's
	# parking spot, not a pose (RENDER-to-SIM 2026-09-28).
	var pitch: float = clampf(atan2(hf - hb, hw * 2.0), -0.26, 0.26)
	var roll: float = clampf(atan2(hl - hr, ht * 2.0), -0.26, 0.26)
	if String(r["kind"]).begins_with("rover"):
		var k: float = 0.35 if moved > 0.0 else 1.0
		r["y"] = lerpf(float(r["y"]), y, k)
		r["pitch"] = lerpf(float(r["pitch"]), pitch, k)
		r["roll"] = lerpf(float(r["roll"]), roll, k)
	else:
		r["y"] = y
		r["pitch"] = 0.0
		r["roll"] = 0.0
	# (+Z rotation lifts the nose; +X rotation lifts the left side, which is -Z)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), float(r["pitch"])) * Basis(Vector3(1, 0, 0), float(r["roll"]))
	var xf := Transform3D(basis, Vector3(pos.x, float(r["y"]) + float(r["hgt"]), pos.y))
	(r["node"] as Node3D).global_transform = xf
	if test_off.has("body"):
		(r["node"] as Node3D).visible = false
	# Suspension: the ground under each hub against the body plane.
	for s in r["susp"]:
		var rest: Transform3D = s["rest"]
		var hub_w: Vector3 = xf * rest.origin
		var ground_rest: float = (xf * (rest.origin - Vector3(0, rest.origin.y, 0))).y
		var travel: float = clampf(_h(hub_w) - ground_rest, float(s["tmin"]), float(s["tmax"])) if float(r["hgt"]) < 0.5 else float(s["tmin"])
		(s["node"] as Node3D).transform = Transform3D(rest.basis, rest.origin + Vector3(0, travel, 0))
	for st in r["steer"]:
		var a: float = clampf(float(r["steer_a"]) * float(st["sign"]), -float(st["max"]), float(st["max"]))
		(st["node"] as Node3D).transform = (st["rest"] as Transform3D) * Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
	if moved != 0.0:
		for w in r["wheels"]:
			w["a"] = fposmod(float(w["a"]) + moved / maxf(0.1, float(w["rad"])), TAU)
			var wn: Node3D = w["node"]
			wn.transform = w["rest"]
			wn.rotate_object_local(Vector3.RIGHT, float(w["a"]))

func _h(p: Vector3) -> float:
	return view.h(p.x, p.z)

func _hinge(e: Array, s: float) -> void:
	var n: Node3D = e[0]
	n.transform = e[1]
	n.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(e[2]) * s))

## Hopper: spool 2 s (dust), lift and cruise (ballistic arc, legs folded), land (legs out
## below 10 m), settle 1.5 s.
func _hop(r: Dictionary, dt: float) -> void:
	var thrust := 0.0
	var legs := 0.0
	if String(r["mode"]) == "hop":
		r["t"] = float(r["t"]) + dt
		var t: float = r["t"]
		var cruise: float = r["cruise"]
		var from: Vector2 = r["from"]
		var to: Vector2 = r["to"]
		if t < 2.0:
			thrust = t / 2.0
			r["hgt"] = 0.0
		elif t < 2.0 + cruise:
			var u: float = (t - 2.0) / cruise
			var e: float = u * u * (3.0 - 2.0 * u)
			r["pos"] = from.lerp(to, e)
			r["hgt"] = float(r["apex"]) * sin(PI * u)
			var dir: Vector2 = to - from
			r["yaw"] = lerp_angle(float(r["yaw"]), atan2(-dir.y, dir.x), 1.0 - exp(-dt * 2.0))
			thrust = 1.0
		elif t < 3.5 + cruise:
			r["pos"] = to
			r["hgt"] = 0.0
			thrust = 1.0 - (t - 2.0 - cruise) / 1.5
		else:
			r["mode"] = "park"
			r["hgt"] = 0.0
		legs = clampf((float(r["hgt"]) - 3.0) / 7.0, 0.0, 1.0)
	r["thrust"] = thrust
	r["s_legs"] = legs
	for nm in r["hinges"]:
		if nm.begins_with("Leg_"):
			_hinge(r["hinges"][nm], legs)
		elif nm == "Ramp" or nm.begins_with("Door_"):
			_hinge(r["hinges"][nm], 1.0 if thrust > 0.0 or String(r["mode"]) == "hop" else 0.0)
	_place(r, 0.0)
	for e in r["thr"]:
		var fl = e[1]
		if fl == null:
			continue
		(fl as MeshInstance3D).visible = thrust > 0.02
		if thrust > 0.02:
			var ln: float = (0.8 + 1.4 * thrust) * (1.0 + 0.1 * sin(float(view._time) * 41.0 + float((fl as Object).get_instance_id() % 7)))
			(fl as MeshInstance3D).transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.from_scale(Vector3(0.5 + 0.4 * thrust, ln, 0.5 + 0.4 * thrust)), Vector3(ln * 0.5, 0, 0))
	for e in r["plasma"]:
		(e[0] as StandardMaterial3D).emission_energy_multiplier = float(e[1]) * (0.05 + 2.2 * thrust)
	# Ground dust while the thrust blows within 18 m of the ground.
	var near_ground: bool = thrust > 0.1 and float(r["hgt"]) < 18.0
	if r.get("gdust") == null and view.get("traffic") != null:
		var gd: CPUParticles3D = view.traffic._make_dust()
		gd.emission_ring_radius = 4.0
		gd.emission_ring_inner_radius = 1.0
		add_child(gd)
		r["gdust"] = gd
	if r.get("gdust") != null:
		var gdp: CPUParticles3D = r["gdust"]
		var pp: Vector2 = r["pos"]
		gdp.global_position = Vector3(pp.x, view.h(pp.x, pp.y) + 0.2, pp.y)
		gdp.emitting = near_ground
	_hop_ground(r, thrust)

## Satellite: a straight orbit track over the map at 420 m, 30 m/s, wings to the sun.
func _orbit(r: Dictionary, dt: float) -> void:
	r["t"] = float(r["t"]) + dt
	var c: Vector2 = r.get("orbit_c", Vector2(sim.world.size * 0.5, sim.world.size * 0.5))
	var dir: Vector2 = r.get("orbit_dir", Vector2(0.8, 0.6))
	var half: float = float(sim.world.size) * 0.9
	var s: float = fposmod(float(r["t"]) * 30.0, half * 2.0) - half
	var p: Vector2 = c + dir * s
	var xf := Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(p.x, 420.0, p.y))
	(r["node"] as Node3D).global_transform = xf
	var sun: Vector3 = view.sky.sun_dir if view.sky != null else Vector3.UP
	var wa: float = atan2(sun.y, Vector2(sun.x, sun.z).length()) - PI * 0.5
	for nm in ["Wing_L", "Wing_R"]:
		if r["hinges"].has(nm):
			var e: Array = r["hinges"][nm]
			(e[0] as Node3D).transform = (e[1] as Transform3D) * Transform3D(Basis(Vector3.RIGHT, wa), Vector3.ZERO)
	r["pos"] = p

## Launch pad: `launch` starts it: arms swing clear (3 s), ignition (2 s), lift (accelerating),
## the rocket is hidden above 900 m.
func _launch(r: Dictionary, dt: float) -> void:
	var t: float = float(r.get("lt", -1.0))
	if t < 0.0:
		return
	t += dt
	r["lt"] = t
	var arms: float = clampf(t / 3.0, 0.0, 1.0)
	for nm in ["Arm_Lower", "Arm_Upper"]:
		if r["hinges"].has(nm):
			_hinge(r["hinges"][nm], arms)
	var thrust: float = clampf((t - 3.0) / 1.0, 0.0, 1.0)
	var lift: float = maxf(0.0, t - 5.0)
	var up: float = 1.8 * lift * lift
	if r["hinges"].has("Rocket"):
		var e: Array = r["hinges"]["Rocket"]
		var rn: Node3D = e[0]
		rn.transform = (e[1] as Transform3D) * Transform3D(Basis(), Vector3(0, up, 0))
		rn.visible = up < 900.0
	for e2 in r["thr"]:
		var fl = e2[1]
		if fl == null:
			continue
		(fl as MeshInstance3D).visible = thrust > 0.02 and up < 900.0
		if thrust > 0.02:
			var ln: float = 3.0 + 9.0 * thrust + minf(lift * 3.0, 20.0)
			(fl as MeshInstance3D).transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.from_scale(Vector3(2.4, ln, 2.4)), Vector3(ln * 0.5, 0, 0))
	if r.get("gdust") == null and view.get("traffic") != null:
		var gd: CPUParticles3D = view.traffic._make_dust()
		gd.emission_ring_radius = 7.0
		add_child(gd)
		r["gdust"] = gd
	if r.get("gdust") != null:
		var gdp: CPUParticles3D = r["gdust"]
		gdp.global_position = (r["node"] as Node3D).global_position + Vector3(0, 0.3, 0)
		gdp.emitting = thrust > 0.2 and up < 60.0

## Hopper near the ground (critic round 22): a warm landing glow on the ground under the thrusters
## and a lit dust ring blown out from it, readable from 150 m. Strength by thrust and height.
func _hop_ground(r: Dictionary, thrust: float) -> void:
	var hgt: float = float(r["hgt"])
	var k: float = clampf(thrust, 0.0, 1.0) * (1.0 - smoothstep(4.0, 45.0, hgt))
	var pp: Vector2 = r["pos"]
	var gy: float = view.h(pp.x, pp.y)
	var g: MeshInstance3D = r.get("glow")
	if g == null:
		g = view.decal_ring(1.0, 0.001, 48, Color(1.0, 0.86, 0.62, 1.0), 9)
		add_child(g)
		r["glow"] = g
	g.visible = k > 0.02
	if g.visible:
		var rad: float = 10.0 + hgt * 0.4
		g.position = Vector3(pp.x, gy, pp.y)
		g.scale = Vector3(rad, 1, rad)
		g.set_instance_shader_parameter("icolor", Color(1, 1, 1, clampf(k * 1.4, 0.0, 1.0)))
	var key := "hopdust_%d" % int(r["id"])
	if k > 0.15 and hgt < 20.0:
		view.fx.emitter_set(key, "dust_ring", Vector3(pp.x, gy + 0.3, pp.y), clampf(k * 1.5, 0.3, 1.5))
		view.fx.emitter_radius(key, 3.0 + hgt * 0.2)
	else:
		view.fx.emitter_stop(key)

func launch(id: int) -> void:
	if vehicles.has(id):
		vehicles[id]["lt"] = 0.0

# ---------------------------------------------------------------- crew
## ART-NPC's chain: step_up (ground anchor) -> board (board anchor) -> drive_sit / ride_sit
## (seat); out: alight (seat -> board anchor at frame 0) -> step_down (board -> ground).
## Right-hand seats (even numbers on the small rover) use the _r clips. Pressurised vehicles
## (medium rover, hopper): the body walks to the hatch and fades (V4 §8).
func _crew(r: Dictionary, dt: float) -> void:
	if (r["crew"] as Array).is_empty() or view.npc == null:
		return
	var xf: Transform3D = (r["node"] as Node3D).global_transform
	var yaw: float = _yaw_of(xf.basis.x)
	var pressurised: bool = String(r["kind"]) != "rover_small"
	for c in r["crew"]:
		var rec: Dictionary = view.npc.puppets.get(String(c["key"]), {})
		if rec.is_empty():
			continue
		var n: int = int(c["seat"])
		var right: bool = n % 2 == 0
		var sfx: String = "_r" if right else ""
		var an: Dictionary = r["anchors"]
		var ground: Vector3 = (an["Ground_%d" % n] as Node3D).global_position if an.has("Ground_%d" % n) else xf * Vector3(0.96, 0, 1.45 if right else -1.45)
		var boardp: Vector3 = (an["Board_%d" % n] as Node3D).global_position if an.has("Board_%d" % n) else ground + Vector3(0, 0.5, 0)
		var seat: Vector3 = (r["seats"][n] as Node3D).global_position if r["seats"].has(n) else boardp
		c["t"] = float(c["t"]) + dt
		rec["yaw"] = yaw
		rec["fade"] = 1.0
		var sm = rec["sm"]
		match String(c["stage"]):
			"step_up":
				if pressurised:
					var hatch: Vector3 = (an["Hatch"] as Node3D).global_position if an.has("Hatch") else xf.origin
					var foot: Vector3 = (an["Ramp"] as Node3D).global_position if an.has("Ramp") else ((an["Board"] as Node3D).global_position if an.has("Board") else hatch)
					rec["pos"] = foot
					sm.force("idle", true)
					rec["fade"] = clampf(1.0 - (float(c["t"]) - 0.5) / 0.4, 0.0, 1.0)
					if float(c["t"]) > 0.9:
						c["stage"] = "seated"
						rec["fade"] = 0.0
					continue
				rec["pos"] = ground
				sm.force("step_up" + sfx, false, true)
				if sm.script_done():
					c["stage"] = "board"
					c["t"] = 0.0
					rec["pos"] = boardp
					sm.force("board" + sfx, false, true)
			"board":
				rec["pos"] = boardp
				if sm.script_done():
					c["stage"] = "seated"
					rec["pos"] = seat
					sm.force("drive_sit" if n == 1 else "ride_sit", true, true)
			"seated":
				if pressurised:
					rec["fade"] = 0.0
					continue
				rec["pos"] = seat
				sm.force("drive_sit" if n == 1 else "ride_sit", true)
			"alight":
				if pressurised:
					var foot2: Vector3 = (an["Ramp"] as Node3D).global_position if an.has("Ramp") else xf.origin
					rec["pos"] = foot2
					sm.force("idle", true)
					rec["fade"] = clampf((float(c["t"]) - 0.2) / 0.4, 0.0, 1.0)
					if float(c["t"]) > 0.7:
						c["stage"] = "out"
					continue
				rec["pos"] = boardp
				sm.force("alight" + sfx, false, true)
				if sm.script_done():
					c["stage"] = "step_down"
					c["t"] = 0.0
					sm.force("step_down" + sfx, false, true)
			"step_down":
				rec["pos"] = ground
				if sm.script_done():
					c["stage"] = "out"
					sm.force("idle", true)
			"out":
				rec["pos"] = ground if not pressurised else rec["pos"]
				sm.force("idle", true)

# ---------------------------------------------------------------- lights
var test_off := {}     # measurement only (__fhr "vtest <crew|dust|hinges> 0|1")
var spots_on := true   # measurement only (__fhr "vspots 0")
## Head and work lights at dusk, at night, in a shadowed crater, and landing lights while a
## hopper is low; the Lights node (lit lenses, cab windows) with them.
func _lights(r: Dictionary) -> int:
	var night: float = float(view.sky.night) if view.sky != null else 0.0
	var dark: float = maxf(night, float(view.get("v4_dark") if view.get("v4_dark") != null else 0.0))
	var running: bool = float(r["speed"]) > 0.1 or float(r["thrust"]) > 0.05
	# (not "running in half-dark": a spot switched on and off at each stop of a route cost a
	# 100-150 ms web frame each time, showcase_v4 perf 2026-09-28)
	var on: bool = dark > 0.25
	var ln = r["lights"]
	if ln != null and is_instance_valid(ln):
		(ln as Node3D).visible = (on or running) if not test_off.has("lnode") else true
	var n := 0
	for e in r["spots"]:
		var sl: SpotLight3D = e[0]
		sl.visible = spots_on
		var role: String = e[1]
		var want: bool = on
		if role == "landing":
			want = float(r["thrust"]) > 0.05 and float(r["hgt"]) < 40.0 and dark > 0.1
		# Unused: parked as fx_sky.park does (no range), not only dimmed. A dim spot with its full
		# range still lit every object the rover passed, and each new one cost a 110-150 ms web
		# frame by day (showcase_v4 perf, 2026-09-28: 3 of 3 day spikes).
		sl.spot_range = float(e[2]) if want else 0.001
		sl.light_energy = (6.0 if role == "head" else 3.5) if want else 0.0
		if want:
			n += 1
	return n

## Debug / tests.
func info() -> Array:
	var out: Array = []
	for id in vehicles:
		var r: Dictionary = vehicles[id]
		out.append({"id": id, "kind": r["kind"], "mode": r["mode"], "pos": [snappedf((r["pos"] as Vector2).x, 0.1), snappedf((r["pos"] as Vector2).y, 0.1)],
			"speed": snappedf(float(r["speed"]), 0.01), "hgt": snappedf(float(r["hgt"]), 0.1), "pitch": snappedf(rad_to_deg(float(r["pitch"])), 0.1),
			"roll": snappedf(rad_to_deg(float(r["roll"])), 0.1), "steer": snappedf(rad_to_deg(float(r["steer_a"])), 0.1), "crew": (r["crew"] as Array).map(func(c): return _crew_info(c))})
	return out

func _crew_info(c: Dictionary) -> String:
	var rec: Dictionary = view.npc.puppets.get(String(c["key"]), {}) if view.npc != null else {}
	if rec.is_empty():
		return String(c["stage"]) + ":no body"
	var sm = rec["sm"]
	return "%s:%s/%s %.2f has_step_up %s libs %d" % [c["stage"], sm.cur, sm.phase, sm.cur_t, str(sm.has("step_up")), view.npc.libs.size()]

# ---------------------------------------------------------------- SIM's vehicles
func _sync_sim(delta: float) -> void:
	var sv = sim.get("vehicles")
	if sv == null or not (sv as Object).has_method("list"):
		return
	var rows: Array = sv.list()
	var seen := {}
	for row in rows:
		var sid: int = int(row["id"])
		seen[sid] = true
		var file_kind: String = KMAP.get(String(row["kind"]), "")
		if file_kind == "":
			continue
		if not _sim.has(sid):
			var p: Vector2 = row["pos"]
			var vid: int = add(file_kind, Transform3D(Basis(Vector3.UP, -float(row["rot"])), Vector3(p.x, view.h(p.x, p.y), p.y)))
			if vid < 0:
				continue
			_sim[sid] = vid
			vehicles[vid]["sim_id"] = sid
			vehicles[vid]["yaw"] = -float(row["rot"])
		var r: Dictionary = vehicles[_sim[sid]]
		r["row"] = row
		if not test_off.has("crew"):
			_sync_crew(r, row)
	for sid in _sim.keys():
		if not seen.has(sid):
			remove(int(_sim[sid]))
			_sim.erase(sid)

## Riders: a new crew member plays step_up -> board -> seat (open rover) or fades in at the
## hatch (pressurised); one who leaves plays alight -> step_down / fades out, then fx_npc draws
## them again.
func _sync_crew(r: Dictionary, row: Dictionary) -> void:
	var now: Array = row.get("crew", [])
	var have := {}
	for c in r["crew"]:
		if c.has("aid"):
			have[int(c["aid"])] = c
	var used := {}
	for c in r["crew"]:
		if String(c["stage"]) != "out":
			used[int(c["seat"])] = true
	for aid in now:
		if have.has(int(aid)):
			var c0: Dictionary = have[int(aid)]
			if String(c0["stage"]) in ["alight", "step_down", "out"]:
				c0["stage"] = "seated"
			continue
		var seat := 1
		while used.has(seat):
			seat += 1
		used[seat] = true
		var a: Dictionary = sim.state["agents"].get(int(aid), {})
		var key := "veh%d_a%d" % [int(r["id"]), int(aid)]
		if view.npc == null or view.npc.puppet(key, "suit", String(a.get("role", "engineer"))).is_empty():
			continue
		(r["crew"] as Array).append({"key": key, "seat": seat, "stage": "step_up", "t": 0.0, "aid": int(aid)})
		_hide[int(aid)] = true
	for c in r["crew"].duplicate():
		if not c.has("aid"):
			continue
		var aid2: int = int(c["aid"])
		if not (aid2 in now) and String(c["stage"]) in ["step_up", "board", "seated"]:
			c["stage"] = "alight"
			c["t"] = 0.0
		if String(c["stage"]) == "out" and float(c["t"]) > 0.3:
			view.npc.puppet_free(String(c["key"]))
			_hide.erase(aid2)
			(r["crew"] as Array).erase(c)

## A rover follows SIM's position (10 ticks a second) smoothly; heading from its motion.
## A vehicle parked in a depot bay stands at ART-HAB's Anchor_Bay_<i> (inside the hangar),
## facing out through the door (the anchor's +X). Returns {pos, yaw} or {}.
func _bay_spot(row: Dictionary) -> Dictionary:
	var did: int = int(row.get("depot", -1))
	var bay: int = int(row.get("bay", -1))
	if did < 0 or bay < 0 or String(row.get("state", "")) == "driving" or not view.bmeta.has(did):
		return {}
	var an: Dictionary = view.bmeta[did].get("anchors", {})
	var key := "Bay_%d" % bay
	if not an.has(key):
		return {}
	var t: Transform3D = an[key]
	return {"pos": Vector2(t.origin.x, t.origin.z), "yaw": _yaw_of(t.basis.x.normalized())}

func _sim_drive(r: Dictionary, delta: float) -> void:
	var row: Dictionary = r["row"]
	var target: Vector2 = row["pos"]
	var spot: Dictionary = _bay_spot(row)
	if not spot.is_empty():
		target = spot["pos"]
	var prev: Vector2 = r["pos"]
	var k: float = 1.0 - exp(-delta * 9.0)
	var now: Vector2 = prev.lerp(target, k) if prev.distance_to(target) < 30.0 else target
	var d: Vector2 = now - prev
	var moved: float = d.length()
	r["pos"] = now
	r["speed"] = moved / maxf(delta, 0.0001)
	var yaw_t: float = atan2(-d.y, d.x) if moved > 0.01 else (float(spot["yaw"]) if not spot.is_empty() else -float(row["rot"]))
	var y0: float = float(r["yaw"])
	var yaw: float = lerp_angle(y0, yaw_t, 1.0 - exp(-delta * 5.0))
	r["yaw"] = yaw
	var rate: float = wrapf(yaw - y0, -PI, PI) / maxf(delta, 0.0001)
	r["steer_a"] = lerpf(float(r["steer_a"]), atan(float(r["wb"]) * rate / maxf(float(r["speed"]), 0.6)) if moved > 0.005 else 0.0, 1.0 - exp(-delta * 6.0))
	r["mode"] = String(row.get("state", "parked"))
	_place(r, moved)
	for dd in r["dust"]:
		(dd as CPUParticles3D).emitting = float(r["speed"]) > 1.0 and not test_off.has("dust")
	var parked: bool = String(row.get("state", "")) != "driving"
	r["s_ramp"] = move_toward(float(r["s_ramp"]), 0.0 if parked and String(r["kind"]) == "rover_medium" else 1.0, delta / 2.5)
	for nm in r["hinges"]:
		if nm == "Ramp" or nm.begins_with("Door_Hatch"):
			_hinge(r["hinges"][nm], float(r["s_ramp"]))
		elif nm == "Door_Tailgate":
			_hinge(r["hinges"][nm], 1.0)
	if not test_off.has("charge"):
		_charging(r, row)

## Hopper: SIM moves it in a straight line between hop points at 25 m/s while `hopping`;
## the view gives the hop its arc, flames, legs and dust.
func _sim_hop(r: Dictionary, delta: float, dt: float) -> void:
	var row: Dictionary = r["row"]
	var p: Vector2 = row["pos"]
	var hopping: bool = bool(row.get("hopping", false))
	var pts: Array = row.get("path", [])
	var pi: int = int(row.get("pi", 0))
	var hgt := 0.0
	if hopping and pi >= 1 and pi < pts.size():
		var a: Vector2 = pts[pi - 1]
		var b: Vector2 = pts[pi]
		var span: float = a.distance_to(b)
		var u: float = clampf(a.distance_to(p) / maxf(span, 0.1), 0.0, 1.0)
		hgt = clampf(span * 0.22, 25.0, 80.0) * sin(PI * u)
		var dir: Vector2 = b - a
		r["yaw"] = lerp_angle(float(r["yaw"]), atan2(-dir.y, dir.x), 1.0 - exp(-delta * 3.0))
	var spot: Dictionary = _bay_spot(row)
	if not spot.is_empty() and not hopping:
		p = spot["pos"]
		r["yaw"] = lerp_angle(float(r["yaw"]), float(spot["yaw"]), 1.0 - exp(-delta * 3.0))
	var prev: Vector2 = r["pos"]
	r["pos"] = prev.lerp(p, 1.0 - exp(-delta * 9.0)) if prev.distance_to(p) < 60.0 else p
	r["hgt"] = lerpf(float(r["hgt"]), hgt, 1.0 - exp(-delta * 9.0))
	# Thrust: on while hopping, spooling down 1.5 s after a landing.
	var was: bool = bool(r.get("was_hop", false))
	if was and not hopping:
		r["land_t"] = 1.5
	r["was_hop"] = hopping
	r["land_t"] = maxf(0.0, float(r.get("land_t", 0.0)) - dt)
	r["mode"] = "hop" if hopping else "park"
	r["t"] = 0.0
	# Reuse the demo hop's drawing with a fixed profile (the flight itself comes from SIM).
	var thrust: float = 1.0 if hopping else float(r["land_t"]) / 1.5
	var legs: float = clampf((float(r["hgt"]) - 3.0) / 7.0, 0.0, 1.0)
	r["thrust"] = thrust
	r["s_legs"] = legs
	for nm in r["hinges"]:
		if nm.begins_with("Leg_"):
			_hinge(r["hinges"][nm], legs)
		elif nm == "Ramp" or nm.begins_with("Door_"):
			_hinge(r["hinges"][nm], 1.0 if thrust > 0.0 or String(row.get("state", "")) == "driving" else 0.0)
	_place(r, 0.0)
	for e in r["thr"]:
		var fl = e[1]
		if fl == null:
			continue
		(fl as MeshInstance3D).visible = thrust > 0.02
		if thrust > 0.02:
			var ln: float = (0.8 + 1.4 * thrust) * (1.0 + 0.1 * sin(float(view._time) * 41.0))
			(fl as MeshInstance3D).transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.from_scale(Vector3(0.5 + 0.4 * thrust, ln, 0.5 + 0.4 * thrust)), Vector3(ln * 0.5, 0, 0))
	for e in r["plasma"]:
		(e[0] as StandardMaterial3D).emission_energy_multiplier = float(e[1]) * (0.05 + 2.2 * thrust)
	if r.get("gdust") == null and view.get("traffic") != null:
		var gd: CPUParticles3D = view.traffic._make_dust()
		gd.emission_ring_radius = 4.0
		gd.emission_ring_inner_radius = 1.0
		add_child(gd)
		r["gdust"] = gd
	if r.get("gdust") != null:
		var gdp: CPUParticles3D = r["gdust"]
		var pp: Vector2 = r["pos"]
		gdp.global_position = Vector3(pp.x, view.h(pp.x, pp.y) + 0.2, pp.y)
		gdp.emitting = thrust > 0.1 and float(r["hgt"]) < 18.0
	_hop_ground(r, thrust)
	if not test_off.has("charge"):
		_charging(r, row)

## Parked at a depot bay and filling up (charge, or fuel for the hopper): a soft cyan pulse.
func _charging(r: Dictionary, row: Dictionary) -> void:
	var key := "vchg_%d" % int(r["id"])
	var at_depot: bool = int(row.get("depot", -1)) >= 0 and int(row.get("bay", -1)) >= 0 and String(row.get("state", "")) != "driving"
	var filling: bool = at_depot and (float(row.get("charge", 0.0)) < float(row.get("charge_cap", 0.0)) - 0.5 or float(row.get("fuel", 0.0)) < float(row.get("fuel_cap", 0.0)) - 0.1)
	if filling:
		var p: Vector2 = r["pos"]
		view.fx.emitter_set(key, "pulse", Vector3(p.x, view.h(p.x, p.y) + 2.8, p.y), 0.6)
	else:
		view.fx.emitter_stop(key)

## A vehicle on order at a depot: a hologram of it at the first bay; sparks while it is worked.
func _sync_builds(_delta: float) -> void:
	var sv = sim.get("vehicles")
	if sv == null or not (sv as Object).has_method("depots"):
		return
	var seen := {}
	for d in sv.depots():
		var o = d.get("vorder", {})
		if not (o is Dictionary) or (o as Dictionary).is_empty():
			continue
		var did: int = int(d["id"])
		seen[did] = true
		var fk: String = KMAP.get(String(o.get("kind", "")), "")
		if fk == "":
			continue
		if not _builds.has(did) or String(_builds[did]["kind"]) != fk:
			if _builds.has(did):
				(_builds[did]["node"] as Node).queue_free()
			var path := "res://assets/models/%s.glb" % String(FILES[fk])
			if not ResourceLoader.exists(path):
				continue
			var n: Node3D = (load(path) as PackedScene).instantiate()
			add_child(n)
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = Models.ghost_material(Color(0.35, 0.9, 1.0, 0.28))
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_builds[did] = {"node": n, "kind": fk}
		var bays: Array = sv.bays(d)
		var bp: Vector2 = d["pos"]
		var brot: float = float(d.get("rot", 0.0))
		for bay in bays:
			var free := true
			for vid in _sim:
				if int((vehicles[_sim[vid]].get("row", {}) as Dictionary).get("bay", -2)) == int(bay["i"]) and int((vehicles[_sim[vid]].get("row", {}) as Dictionary).get("depot", -2)) == did:
					free = false
			if free:
				bp = bay["pos"]
				brot = float(bay.get("rot", brot))
				var an: Dictionary = view.bmeta[did].get("anchors", {}) if view.bmeta.has(did) else {}
				if an.has("Bay_%d" % int(bay["i"])):
					var at: Transform3D = an["Bay_%d" % int(bay["i"])]
					bp = Vector2(at.origin.x, at.origin.z)
					brot = -_yaw_of(at.basis.x.normalized())
				break
		var prog: float = clampf(float(o.get("progress", 0.0)) / maxf(float(o.get("work_total", 1.0)), 0.001), 0.0, 1.0)
		var node: Node3D = _builds[did]["node"]
		node.global_transform = Transform3D(Basis(Vector3.UP, -brot), Vector3(bp.x, view.h(bp.x, bp.y), bp.y))
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var gm: StandardMaterial3D = Models.ghost_material(Color(0.35, 0.9, 1.0, snappedf(lerpf(0.18, 0.6, prog), 0.07)))
			(mi as MeshInstance3D).material_override = gm
		var sk := "vbuild_%d" % did
		if String(o.get("state", "")) == "work":
			view.fx.emitter_set(sk, "site_sparks", Vector3(bp.x, view.h(bp.x, bp.y) + 1.0, bp.y), 1.0)
		else:
			view.fx.emitter_stop(sk)
	for did in _builds.keys():
		if not seen.has(did):
			(_builds[did]["node"] as Node).queue_free()
			_builds.erase(did)
			view.fx.emitter_stop("vbuild_%d" % did)
