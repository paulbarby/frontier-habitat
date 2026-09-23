extends Node3D
## The Meridian (RENDER): the crashed colony ship as its repair goes on (§9).
## Reads state.ship = {stage, away, flight_t, ...} and the building record "meridian".
##   Damage1 shown until stage 2, Damage2 until stage 3, Damage3 until stage 4;
##   Scaffold while stages 1..3 are worked; Lights from stage 3; EngineGlow from stage 4.
##   Test flight (flight_t 0..1): engines spool up, it lifts 20 m, levels out, hovers,
##   lands level with a dust ring. Supply runs (away): it flies off and comes back.
## Model conventions from ART-B: length along X, nose +X, crash tilt baked in (pitch 4 deg
## nose down around x = -13, roll 2 deg). Level pose = rotation.z + 4 deg, rotation.x - 2 deg.

const Models = preload("res://presentation/models.gd")

var view
var forced_flight := -1.0
var node: Node3D
var body: Node3D
var bid := -1
var groups := {}
var anchors := {}
var _t := 0.0
var _away_anim := 0.0     # 0 = on the ground, 1 = gone
var _last_flight := -1.0
var _was_away := false
var _base: Transform3D

func setup(v) -> void:
	view = v

func attach(b: Dictionary) -> void:
	detach()
	bid = b["id"]
	var tpl: Dictionary = Models.prop(["meridian"], 7.0, "special", "space")
	node = Node3D.new()
	body = Models.node_from(tpl)
	node.add_child(body)
	add_child(node)
	_base = Transform3D(Basis(Vector3.UP, -float(b["rot"])), view.to3(b["pos"], 0.0))
	node.transform = _base
	groups = {}
	for c in body.get_children():
		groups[String(c.name)] = c
	anchors = tpl["anchors"]
	_was_away = bool(view.sim.state.get("ship", {}).get("away", false))
	_away_anim = 1.0 if _was_away else 0.0

func detach() -> void:
	if node != null:
		node.queue_free()
	node = null
	body = null
	bid = -1
	groups = {}
	if view != null and view.fx != null:
		view.fx.emitter_stop("ship_l")
		view.fx.emitter_stop("ship_r")

func _show(g: String, on: bool) -> void:
	if groups.has(g):
		(groups[g] as Node3D).visible = on

func sync(delta: float, sim_dt: float) -> void:
	if node == null:
		return
	_t += delta
	var sim = view.sim
	var s: Dictionary = sim.state.get("ship", {})
	var stage: int = int(s.get("stage", 0))
	var ft: float = float(s.get("flight_t", -1.0))
	if forced_flight >= 0.0:
		ft = forced_flight
		stage = 4
	_show("Damage1", stage < 2)
	_show("Damage2", stage < 3)
	_show("Damage3", stage < 4)
	_show("Scaffold", stage >= 1 and stage <= 3)
	_show("Lights", stage >= 3)
	var flying: bool = ft >= 0.0
	var away: bool = bool(s.get("away", false))
	_away_anim = move_toward(_away_anim, 1.0 if away else 0.0, delta / 14.0)
	var engines: bool = flying or (_away_anim > 0.0 and _away_anim < 1.0)
	_show("EngineGlow", stage >= 4 and (engines or stage >= 5))
	# Pose: crashed (baked tilt) until the test flight levels it; level afterwards.
	var level: float = 0.0
	var lift := 0.0
	var rumble := Vector3.ZERO
	if stage >= 5 and not flying:
		level = 1.0
	if flying:
		var f: float = clampf(ft, 0.0, 1.0)
		lift = 20.0 * _ease(clampf((f - 0.12) / 0.25, 0.0, 1.0)) * (1.0 - _ease(clampf((f - 0.7) / 0.25, 0.0, 1.0)))
		lift += sin(_t * 1.3) * 0.35 * clampf((f - 0.35) * 8.0, 0.0, 1.0) * clampf((0.7 - f) * 8.0, 0.0, 1.0)
		level = _ease(clampf((f - 0.1) / 0.2, 0.0, 1.0))
		if f < 0.14:
			rumble = Vector3(sin(_t * 40.0), 0, cos(_t * 37.0)) * 0.05 * f / 0.14
	if _away_anim > 0.0:
		level = 1.0
		var a: float = _away_anim
		lift = maxf(lift, 20.0 * _ease(clampf(a / 0.3, 0.0, 1.0)) + pow(clampf((a - 0.3) / 0.7, 0.0, 1.0), 2.0) * 400.0)
	var pivot := Vector3(-13.0, 0.0, 0.0)
	var tilt := Basis(Vector3(0, 0, 1), deg_to_rad(4.0) * level) * Basis(Vector3(1, 0, 0), deg_to_rad(-2.0) * level)
	var local := Transform3D(tilt, pivot - tilt * pivot + Vector3(0, level * 0.1, 0))
	var fwd: Vector3 = (_base.basis * Vector3(1, 0, 0)).normalized()
	var drift: Vector3 = fwd * pow(clampf((_away_anim - 0.3) / 0.7, 0.0, 1.0), 2.0) * 600.0
	node.transform = Transform3D(_base.basis, _base.origin + Vector3(0, lift, 0) + drift + rumble) * local
	node.visible = _away_anim < 0.999
	# Engines: plumes from the nozzles while flying, a dust ring when near the ground.
	var fx = view.fx
	if engines and node.visible:
		var power: float = clampf(ft / 0.12, 0.2, 1.0) if flying else 1.0
		for side in ["L", "R"]:
			var key: String = "Engine_" + side
			var a_xf: Transform3D = anchors.get(key, Transform3D(Basis(), Vector3(-21.0, 3.0, -2.0 if side == "L" else 2.0)))
			var w: Transform3D = node.global_transform * a_xf
			fx.emitter_set("ship_" + side.to_lower(), "plume", w.origin, power)
			var ex: Vector3 = (w.basis * Vector3(1, 0, 0)).normalized()
			fx.pools["plume"]["mat"].set_shader_parameter("dir", ex)
		if lift < 9.0:
			fx.emitter_set("ship_dust", "dust_ring", node.global_position - Vector3(0, lift, 0) + Vector3(0, 0.3, 0), clampf(1.0 - lift / 9.0, 0.2, 1.0))
			fx.emitter_radius("ship_dust", 10.0)
		else:
			fx.emitter_stop("ship_dust")
	else:
		fx.emitter_stop("ship_l")
		fx.emitter_stop("ship_r")
		fx.emitter_stop("ship_dust")
	if flying and _last_flight < 0.0:
		view.focus_event("liftoff", bid)
	if not flying and _last_flight >= 0.9:
		view.focus_event("landing", bid)
		fx.burst("dust", node.global_position, 60, 12.0)
	_last_flight = ft

func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
