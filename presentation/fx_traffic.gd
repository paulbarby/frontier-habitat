extends Node3D
## Visiting ships (V3_1 §6.3, RENDER). The simulation keeps `state.traffic.ships` = arrivals
## with `phase` (orbit, landing, landed, boarding, takeoff), `pad` and `t` (tick the phase ends).
## This module draws ART-B's ships `ship_<kind>.glb` on the pad's `Anchor_Ship`:
##   landing (20 s): a curved approach from 150 m, braking on the hover thrusters, legs unfold
##     from 40 m, dust ring under 20 m, a touchdown bump; then the ramp and doors open;
##   take-off (15 s): ramp and doors close, hover spool-up, lift-off, legs fold at 40 m, away;
##   thruster flames (hover down, main aft) and the Plasma nozzle cones follow the thrust;
##   at night the Lights node is on and each Flood_<i> carries a warm spot light;
##   `ramp` world sound when the ramp moves (ship_descent, ship_touchdown, ship_takeoff are UI's).
## Model rule (ART-B 2): rest pose = landed; each Leg_*, Ramp, Door_* turns about its local X by
## extras.stow_deg * s (s 0 landed/open .. 1 flight/closed).

const Models = preload("res://presentation/models.gd")
const DESCENT := 20.0
const TAKEOFF := 15.0
const TOP := 150.0            # m: start of the descent, end of the climb
const LEGS_AT := 40.0         # m: legs fold / unfold between LEGS_AT and 10 m
const DUST_AT := 20.0
const RAMP_T := 2.5
const DOOR_T := 1.5
const FLOOD_RANGE := 9.0

var view
var sim
var ships := {}               # arrival id -> view record
var stats := {"ships": 0, "floods": 0, "ms": 0.0}
var _flame_mesh: Mesh
var _flame_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D

func setup(v) -> void:
	view = v
	sim = v.sim

# ---------------------------------------------------------------- per frame
## Shader warm-up (V3.1 stall trace): the flame, dust and vent-mist materials compile on their
## first draw (in the web build a 100-150 ms frame, seen when a ship first took off). They are
## drawn once, tiny, in front of the camera during the first frames of a game.
var _warm: Node3D = null
var _warm_n := 0
func _prewarm() -> void:
	var cam: Camera3D = view.get_viewport().get_camera_3d()
	if cam == null:
		return
	if _warm == null:
		_warm = Node3D.new()
		add_child(_warm)
		_flame(_warm).visible = true
		var d := _make_dust()
		d.local_coords = true
		d.emitting = true
		_warm.add_child(d)
		if view.get("airlock") != null:
			var m: CPUParticles3D = view.airlock._make_mist()
			m.local_coords = true
			m.emitting = true
			_warm.add_child(m)
	_warm.global_transform = Transform3D(Basis.from_scale(Vector3(0.02, 0.02, 0.02)), cam.global_position - cam.global_transform.basis.z * 2.0)
	_warm_n += 1
	if _warm_n > 6:
		_warm.queue_free()
		_warm = null

func sync(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	if _warm_n <= 6:
		_prewarm()
	var tr = sim.state.get("traffic", {})
	var rows: Array = (tr.get("ships", []) if tr is Dictionary else []) as Array
	var seen := {}
	var tick: int = int(sim.state["tick"])
	var hz: float = 10.0
	if sim.get("traffic") != null and (sim.traffic as Object).has_method("hz"):
		hz = float(sim.traffic.hz())
	var gdt: float = delta * clampf(float(view.game_rate), 0.0, 50.0)
	var night: float = float(view.sky.night) if view.sky != null else 0.0
	var nflood := 0
	for arr in rows:
		var phase: String = String(arr.get("phase", ""))
		if not (phase in ["landing", "landed", "boarding", "takeoff"]):
			continue
		var pid: int = int(arr.get("pad", -1))
		if not view.bmeta.has(pid) or not sim.state["buildings"].has(pid):
			continue
		var id: int = int(arr["id"])
		seen[id] = true
		if not ships.has(id):
			var rec := _make(id, String(arr.get("kind", "trader")))
			if rec.is_empty():
				continue
			if phase in ["landed", "boarding"]:
				# A loaded game: the ship is already down, ramp and doors open.
				rec["s_ramp"] = 0.0
				rec["s_door"] = 0.0
				rec["s_legs"] = 0.0
				rec["hgt"] = 0.0
				rec["phase"] = phase
			ships[id] = rec
		var r: Dictionary = ships[id]
		var t_s: float = maxf(0.0, float(int(arr.get("t", tick)) - tick) / hz)
		r["pad_xf"] = _pad_xf(pid)
		_pose(r, phase, t_s, gdt)
		nflood += _lights(r, night)
	for id in ships.keys():
		if not seen.has(id):
			_free(id)
	stats["ships"] = ships.size()
	stats["floods"] = nflood
	stats["ms"] = snappedf(lerpf(float(stats["ms"]), (Time.get_ticks_usec() - t0) / 1000.0, 0.1), 0.001)

## World transform of the ship's origin when landed: the pad's Anchor_Ship (nose to pad -X).
func _pad_xf(pid: int) -> Transform3D:
	var meta: Dictionary = view.bmeta[pid]
	var xf: Transform3D = meta["xf"]
	var an: Dictionary = meta.get("anchors", {})
	if an.has("Ship"):
		var a: Transform3D = an["Ship"]
		return Transform3D(a.basis.orthonormalized(), a.origin)
	return Transform3D(xf.basis * Basis(Vector3.UP, PI), xf.origin + Vector3(0, 0.35, 0))

# ---------------------------------------------------------------- build
func _make(id: int, kind: String) -> Dictionary:
	# The inspector flies the courier (V3_1 §6.2).
	var mk: String = {"inspector": "courier"}.get(kind, kind)
	var path := "res://assets/models/ship_%s.glb" % mk
	if not ResourceLoader.exists(path):
		path = "res://assets/models/ship_trader.glb"
		if not ResourceLoader.exists(path):
			return {}
	var ps: PackedScene = load(path)
	var root: Node3D = ps.instantiate()
	add_child(root)
	var rec := {"id": id, "kind": kind, "node": root, "legs": [], "ramp": [], "doors": [], "thr": [], "floods": [], "lights": null,
		"plasma": [], "s_legs": 1.0, "s_ramp": 1.0, "s_door": 1.0, "hgt": TOP, "thrust_h": 0.0, "thrust_m": 0.0,
		"phase": "", "ramp_moving": false, "dust": null, "spots": [], "anchors": {}}
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
			_plasma_override(n as MeshInstance3D, rec)
		if nm.begins_with("Leg_"):
			rec["legs"].append([n, (n as Node3D).transform, float(ex.get("stow_deg", -120.0))])
		elif nm == "Ramp":
			rec["ramp"].append([n, (n as Node3D).transform, float(ex.get("stow_deg", 120.0))])
		elif nm.begins_with("Door_"):
			rec["doors"].append([n, (n as Node3D).transform, float(ex.get("stow_deg", -100.0))])
		elif nm.begins_with("Thruster_"):
			rec["thr"].append([n, String(ex.get("role", "main" if nm.contains("Main") else "hover")), _flame(n as Node3D)])
		elif nm.begins_with("Flood_"):
			rec["floods"].append(n)
		elif nm == "Lights":
			rec["lights"] = n
		elif nm.begins_with("Anchor_"):
			rec["anchors"][nm.substr(7)] = n
	return rec

## The ship's own copy of its Plasma material (the nozzle cones fade per ship).
func _plasma_override(mi: MeshInstance3D, rec: Dictionary) -> void:
	for si in mi.mesh.get_surface_count():
		var m: Material = mi.mesh.surface_get_material(si)
		if m != null and m.resource_name == "Plasma" and m is StandardMaterial3D:
			var d: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
			d.emission_enabled = true
			mi.set_surface_override_material(si, d)
			rec["plasma"].append([d, maxf(1.0, (m as StandardMaterial3D).emission_energy_multiplier)])

## A flame cone on a thruster empty (local +X = flame direction).
func _flame(t: Node3D) -> MeshInstance3D:
	if _flame_mesh == null:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.32
		cm.height = 1.0
		cm.radial_segments = 10
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		_flame_mesh = cm
		_flame_mat = StandardMaterial3D.new()
		_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flame_mat.albedo_color = Color(0.55, 0.75, 1.0, 0.75)
		_flame_mat.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.mesh = _flame_mesh
	mi.material_override = _flame_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	t.add_child(mi)
	return mi

func _free(id: int) -> void:
	var r: Dictionary = ships[id]
	if is_instance_valid(r["node"]):
		(r["node"] as Node).queue_free()
	ships.erase(id)

# ---------------------------------------------------------------- motion
func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

func _pose(r: Dictionary, phase: String, t_s: float, gdt: float) -> void:
	var land: Transform3D = r["pad_xf"]
	var hgt := 0.0
	var side := 0.0             # m back along the approach line
	var pitch := 0.0
	var thrust_h := 0.0
	var thrust_m := 0.0
	var want_ramp := 1.0
	var want_door := 1.0
	match phase:
		"landing":
			var u: float = clampf(1.0 - t_s / DESCENT, 0.0, 1.0)
			# Height falls fast then brakes; the approach offset closes faster (a curve in).
			hgt = TOP * pow(1.0 - u, 2.2)
			side = 140.0 * pow(1.0 - u, 3.0)
			pitch = deg_to_rad(8.0) * smoothstep(0.35, 0.8, u) * (1.0 - smoothstep(0.92, 1.0, u))
			thrust_m = 1.0 - smoothstep(0.3, 0.6, u)
			thrust_h = smoothstep(0.25, 0.55, u)
			if t_s < 0.4:
				hgt = maxf(hgt, 0.0) - 0.08 * sin(PI * (0.4 - t_s) / 0.4)
		"landed", "boarding":
			hgt = 0.0
			want_ramp = 0.0
			want_door = 0.0
			if String(r["phase"]) == "landing":
				r["touch"] = 0.0
			r["touch"] = float(r.get("touch", 9.0)) + gdt
			# Touchdown settle, engines spool down.
			var tt: float = float(r["touch"])
			if tt < 0.35:
				hgt = -0.08 * sin(PI * tt / 0.35)
			thrust_h = maxf(0.0, 1.0 - tt / 1.5)
			# Before take-off the ramp closes (the last 3 s of boarding are not known: close
			# when the phase changes, below).
		"takeoff":
			var u2: float = clampf(1.0 - t_s / TAKEOFF, 0.0, 1.0)
			var lift: float = clampf((u2 - 0.2) / 0.8, 0.0, 1.0)
			hgt = TOP * pow(lift, 2.0)
			side = -160.0 * pow(lift, 2.6)
			pitch = -deg_to_rad(10.0) * smoothstep(0.3, 0.8, lift)
			thrust_h = smoothstep(0.0, 0.2, u2) * (1.0 - smoothstep(0.6, 0.9, lift))
			thrust_m = smoothstep(0.35, 0.7, lift)
			want_ramp = 1.0
			want_door = 1.0
	r["phase"] = phase
	# Legs: out below 10 m, folded above LEGS_AT.
	var s_legs: float = clampf((hgt - 10.0) / (LEGS_AT - 10.0), 0.0, 1.0)
	if phase == "landing" or phase == "takeoff":
		s_legs = s_legs
	else:
		s_legs = 0.0
	# Ramp and doors move at their own pace.
	var sr: float = r["s_ramp"]
	var sd: float = r["s_door"]
	var moving: bool = absf(sr - want_ramp) > 0.001
	if moving and not bool(r["ramp_moving"]):
		view.world_sound("ramp", (r["node"] as Node3D).global_position)
	r["ramp_moving"] = moving
	sr = move_toward(sr, want_ramp, gdt / RAMP_T)
	sd = move_toward(sd, want_door, gdt / DOOR_T)
	r["s_ramp"] = sr
	r["s_door"] = sd
	r["s_legs"] = s_legs
	for e in r["legs"]:
		_hinge(e, s_legs)
	for e in r["ramp"]:
		_hinge(e, sr)
	for e in r["doors"]:
		_hinge(e, sd)
	# Place: back along the ship's -X (it comes in nose first), up by hgt, pitched.
	var fwd: Vector3 = land.basis.x.normalized()
	var pos: Vector3 = land.origin - fwd * side + Vector3(0, hgt, 0)
	var basis: Basis = land.basis * Basis(Vector3(0, 0, 1), pitch)
	(r["node"] as Node3D).global_transform = Transform3D(basis, pos)
	r["hgt"] = hgt
	# Thrust: flames, nozzle glow, dust.
	for e in r["thr"]:
		var fl: MeshInstance3D = e[2]
		var k: float = thrust_h if e[1] == "hover" else thrust_m
		fl.visible = k > 0.02
		if fl.visible:
			var ln: float = (1.2 + 1.6 * k) * (1.0 + 0.08 * sin(float(view._time) * 37.0 + float(fl.get_instance_id() % 13)))
			# Cylinder axis is Y: turn it to the empty's +X, the tip away from the nozzle.
			fl.transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.from_scale(Vector3(0.6 + 0.5 * k, ln, 0.6 + 0.5 * k)), Vector3(ln * 0.5, 0, 0))
	var glow: float = maxf(thrust_h, thrust_m)
	for e in r["plasma"]:
		(e[0] as StandardMaterial3D).emission_energy_multiplier = float(e[1]) * (0.05 + 2.2 * glow)
	_dust(r, hgt, thrust_h)

func _hinge(e: Array, s: float) -> void:
	var n: Node3D = e[0]
	n.transform = e[1]
	n.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(e[2]) * s))

## Dust ring on the pad while the hover thrusters blow below DUST_AT.
func _dust(r: Dictionary, hgt: float, thrust_h: float) -> void:
	var on: bool = hgt < DUST_AT and thrust_h > 0.1
	var pa = r["dust"]
	if not on:
		if pa != null and is_instance_valid(pa):
			(pa as CPUParticles3D).emitting = false
		return
	if pa == null or not is_instance_valid(pa):
		pa = _make_dust()
		add_child(pa)
		r["dust"] = pa
	var p2: CPUParticles3D = pa
	var land: Transform3D = r["pad_xf"]
	p2.global_position = land.origin + Vector3(0, 0.2, 0)
	p2.emitting = true

func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 160
	p.lifetime = 2.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 5.5
	p.emission_ring_inner_radius = 1.5
	p.emission_ring_height = 0.2
	p.direction = Vector3(1, 0.15, 0)
	p.spread = 180.0
	p.flatness = 0.85
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 11.0
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = 2.2
	p.scale_amount_max = 4.5
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_mat.vertex_color_use_as_albedo = true
		# (pale: an orange dust on the orange ground could not be seen, critic round 13)
		_dust_mat.albedo_color = Color(1.0, 0.9, 0.8, 0.8)
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
	gr.add_point(0.1, Color(1, 1, 1, 0.8))
	gr.add_point(0.55, Color(1, 1, 1, 0.45))
	p.color_ramp = gr
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

# ---------------------------------------------------------------- lights
## Lights node on at dusk; a warm spot light on every Flood_<i> at night (critic round 12).
func _lights(r: Dictionary, night: float) -> int:
	var ln = r["lights"]
	if ln != null and is_instance_valid(ln):
		(ln as Node3D).visible = night > 0.15 or float(r["hgt"]) > 1.0
	var want: bool = night > 0.15
	var spots: Array = r["spots"]
	if spots.is_empty():
		for f in r["floods"]:
			var sl := SpotLight3D.new()
			sl.light_color = Color("ffd9a0")
			sl.spot_angle = 40.0
			sl.spot_range = FLOOD_RANGE
			sl.spot_attenuation = 0.6
			sl.light_energy = 7.0
			sl.shadow_enabled = false
			# Godot spots shine along -Z: turn -Z to the empty's +X.
			sl.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
			(f as Node3D).add_child(sl)
			spots.append(sl)
	# Never hidden (see fx_sky.park): no range by day.
	for s in spots:
		var sp: SpotLight3D = s
		sp.spot_range = FLOOD_RANGE
		sp.light_energy = 7.0 if want else 0.0005
	return spots.size() if want else 0

## Debug / tests.
func info() -> Array:
	var out: Array = []
	for id in ships:
		var r: Dictionary = ships[id]
		out.append({"night": snappedf(float(view.sky.night) if view.sky != null else -1.0, 0.01), "id": id, "kind": r["kind"], "phase": r["phase"], "hgt": snappedf(float(r["hgt"]), 0.01), "legs": snappedf(float(r["s_legs"]), 0.01),
			"ramp": snappedf(float(r["s_ramp"]), 0.01), "door": snappedf(float(r["s_door"]), 0.01), "floods": (r["spots"] as Array).size()})
	return out

## Ramp foot of the ship on pad `pid` (world), or Vector3.INF (visitors walk from here).
func ramp_foot(pid: int) -> Vector3:
	for id in ships:
		var r: Dictionary = ships[id]
		if r["anchors"].has("Ramp") and _pad_of(id) == pid:
			return (r["anchors"]["Ramp"] as Node3D).global_position
	return Vector3.INF

## The ramp foot of a landed ship nearest to p within r (world), or Vector3.INF.
func ramp_near(p: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var bd: float = r
	for id in ships:
		var s: Dictionary = ships[id]
		# (landed: the ramp may still be opening; the visitor starts at its foot all the same)
		# (the view's record can still say "landing" on the frame the simulation lands it)
		if not (String(s["phase"]) in ["landing", "landed", "boarding"]) or float(s["hgt"]) > 2.0 or not s["anchors"].has("Ramp"):
			continue
		var f: Vector3 = (s["anchors"]["Ramp"] as Node3D).global_position
		var d: float = Vector2(f.x - p.x, f.z - p.z).length()
		if d < bd:
			bd = d
			best = f
	return best

func _pad_of(id: int) -> int:
	var tr = sim.state.get("traffic", {})
	for arr in (tr.get("ships", []) if tr is Dictionary else []):
		if int(arr["id"]) == id:
			return int(arr.get("pad", -1))
	return -1
