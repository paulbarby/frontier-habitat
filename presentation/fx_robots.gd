extends Node3D
## Robot dancers in the super dome Club (RENDER; V5 §1, §8; ART-NPC robot_manifest.json, ART-B anchors).
## One robot per ART-B anchor `Anchor_Dancer_club_<k>` (podium top, 0.35 m in front of the pole, facing
## the room along the anchor's +X). Each robot cycles robot_dance_a / _b / _c / robot_pole from its own
## start (chain rule: every clip starts and ends on the same pose, cut with no blend); robot_idle while the
## Club is closed (sim.leisure.venues(b), venue "club"). The light bar and strips (RobotLight) take a colour
## per dancer and pulse on the 120 bpm beat. Animation runs in game time (paused = still).
## Shown only when the dome is finished and the Club's floor is not cut away.

const FILE := "res://assets/models/robot_dancer.glb"
const DANCES := ["robot_dance_a", "robot_dance_b", "robot_dance_c", "robot_pole"]
const COLS := [Color(1.0, 0.25, 0.85), Color(0.2, 0.85, 1.0), Color(1.0, 0.75, 0.2), Color(0.45, 1.0, 0.35), Color(0.6, 0.4, 1.0), Color(1.0, 0.35, 0.3)]
const LIGHT_FAR := 40.0         # m: the podium spot and rim lights only this close (light cost)
const FAR := 90.0               # m: beyond this the robots are hidden (they are inside a closed venue)

var view
var _scene: PackedScene
var _load_failed := false
var bots := {}                  # "bid:anchor" -> {node, player, lights [Material], k, seq, open}
var stats := {"robots": 0, "open": false, "clip": ""}

func setup(v) -> void:
	view = v

func _ensure_scene() -> bool:
	if _scene != null:
		return true
	if _load_failed or not ResourceLoader.exists(FILE):
		_load_failed = true
		return false
	var ps = load(FILE)
	if ps is PackedScene:
		_scene = ps
		return true
	_load_failed = true
	return false

## Dome finished (stage 9) and the floor of this anchor is not cut away (world_view._dome_update).
func _visible_in(b: Dictionary, meta: Dictionary, ay: float) -> bool:
	if float(view._dome_stage(b)) < 9.0:
		return false
	var k: int = int(meta.get("dome_k", 0))
	if k <= 0:
		return true
	var base_y: float = (meta["xf"] as Transform3D).origin.y
	var fl := 1
	for i in view.LIFT_STOPS.size():
		if ay - base_y + 0.5 >= float(view.LIFT_STOPS[i]):
			fl = i + 1
	return fl <= k

var _fill: OmniLight3D
var force_open := false          # evidence only (__fhr "robots open"): dance whatever the Club's hours

func _club_open(b: Dictionary) -> bool:
	if force_open:
		return true
	var le = view.sim.get("leisure")
	if le == null or not le.has_method("venues"):
		return true
	for v in le.venues(b):
		if String(v.get("id", "")) == "club":
			return bool(v.get("open", false))
	return false

func sync(_delta: float) -> void:
	var seen := {}
	var cam: Camera3D = view.get_viewport().get_camera_3d()
	var gr: float = clampf(float(view.game_rate), 0.0, 8.0)
	var t: float = float(view._time)
	for bid in view.bmeta:
		var b: Dictionary = view.sim.state["buildings"].get(bid, {})
		if b.is_empty() or String(b["def"]) != "super_dome":
			continue
		var meta: Dictionary = view.bmeta[bid]
		var open := _club_open(b)
		for an in (meta.get("anchors", {}) as Dictionary):
			if not String(an).begins_with("Dancer_club_"):
				continue
			var ax: Transform3D = meta["anchors"][an]
			var key := "%d:%s" % [int(bid), an]
			if not _visible_in(b, meta, ax.origin.y) or (cam != null and cam.global_position.distance_to(ax.origin) > FAR):
				if bots.has(key):
					(bots[key]["node"] as Node3D).visible = false
				seen[key] = true
				continue
			if not bots.has(key):
				if not _ensure_scene():
					return
				bots[key] = _make(key, ax, int(String(an).get_slice("_", 2)) if String(an).get_slice("_", 2).is_valid_int() else bots.size())
			var r: Dictionary = bots[key]
			seen[key] = true
			var node: Node3D = r["node"]
			node.visible = true
			node.global_transform = Transform3D(ax.basis.orthonormalized(), ax.origin)
			var ap: AnimationPlayer = r["player"]
			if ap != null:
				ap.speed_scale = gr
				if open != bool(r["open"]) or not ap.is_playing():
					r["open"] = open
					_next(r)
			# RobotLight: the dancer's colour, a pulse on the 120 bpm beat (2 Hz), dim when closed.
			var pulse: float = 0.55 + 0.45 * pow(0.5 + 0.5 * cos(TAU * 2.0 * t * maxf(gr, 0.0) + float(r["k"])), 3.0)
			for m in r["lights"]:
				(m as StandardMaterial3D).emission = COLS[int(r["k"]) % COLS.size()]
				(m as StandardMaterial3D).emission_energy_multiplier = (3.0 * pulse) if open else 0.8
			var near_l: bool = cam != null and cam.global_position.distance_to(ax.origin) < LIGHT_FAR
			(r["spot"] as Light3D).visible = near_l
			(r["rim"] as Light3D).visible = near_l
			(r["spot"] as Light3D).light_energy = (2.6 + 0.8 * pulse) if open else 0.9
			(r["rim"] as Light3D).light_energy = 1.6 if open else 0.5
	for key in bots.keys():
		if not seen.has(key):
			(bots[key]["node"] as Node).queue_free()
			bots.erase(key)
	stats["robots"] = bots.size()
	# The floor fill (critic round 41: "lift the floor from black"): one soft omni over the dance floor, in front
	# of the podiums, while any dancer is drawn and the camera is near.
	var c_sum := Vector3.ZERO
	var f_sum := Vector3.ZERO
	var nv := 0
	var any_open := false
	for key in bots:
		var nd: Node3D = bots[key]["node"]
		if nd.visible:
			c_sum += nd.global_position
			f_sum += nd.global_transform.basis.x
			nv += 1
			any_open = any_open or bool(bots[key]["open"])
	if _fill == null:
		_fill = OmniLight3D.new()
		_fill.name = "ClubFloorFill"
		_fill.light_color = Color(0.95, 0.55, 1.0)
		_fill.omni_range = 8.0
		_fill.omni_attenuation = 0.9
		_fill.shadow_enabled = false
		add_child(_fill)
	_fill.visible = nv > 0 and cam != null and cam.global_position.distance_to(c_sum / maxf(nv, 1)) < LIGHT_FAR
	if nv > 0:
		var fd: Vector3 = Vector3(f_sum.x, 0.0, f_sum.z).normalized()
		_fill.global_position = c_sum / nv + fd * 3.0 + Vector3(0.0, 2.2, 0.0)
		_fill.light_energy = 0.9 if any_open else 0.4

func _make(key: String, ax: Transform3D, k: int) -> Dictionary:
	var node: Node3D = _scene.instantiate()
	node.name = "Robot_" + key.replace(":", "_")
	add_child(node)
	node.global_transform = Transform3D(ax.basis.orthonormalized(), ax.origin)
	var ap: AnimationPlayer = null
	var aps: Array = node.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		ap = aps[0]
		# Clips play once each; the next one starts on animation_finished (the chain rule: no blend).
		for an in ap.get_animation_list():
			(ap.get_animation(an) as Animation).loop_mode = Animation.LOOP_NONE
		ap.playback_default_blend_time = 0.0
	var lights: Array = []
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m3: MeshInstance3D = mi
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in m3.mesh.get_surface_count():
			var src: Material = m3.get_active_material(si)
			if src == null or not (src is StandardMaterial3D):
				continue
			var nm: String = String(src.resource_name)
			if nm.begins_with("RobotLight"):
				var lm: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
				lm.emission_enabled = true
				m3.set_surface_override_material(si, lm)
				lights.append(lm)
			elif nm.begins_with("RobotChrome"):
				# No reflection probe in the Compatibility renderer: a brushed chrome with a rim so the robot
				# reads as metal under the Club's lamps instead of going dark (ART-NPC note).
				var cm: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
				cm.metallic = 0.85
				cm.roughness = 0.24
				cm.albedo_color = Color(0.86, 0.88, 0.92)
				cm.rim_enabled = true
				cm.rim = 0.55
				cm.rim_tint = 0.4
				m3.set_surface_override_material(si, cm)
	# Critic round 41: a coloured spot from above per podium and a cool rim light from behind, so the dancer reads
	# against the dark club (no shadows: the Compatibility renderer's light budget).
	var spot := SpotLight3D.new()
	spot.name = "PodiumSpot"
	spot.light_color = COLS[k % COLS.size()].lerp(Color.WHITE, 0.35)
	spot.spot_range = 5.0
	spot.spot_angle = 24.0
	spot.spot_attenuation = 0.8
	spot.shadow_enabled = false
	spot.position = Vector3(0.0, 3.2, 0.0)
	spot.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	node.add_child(spot)
	var rim := OmniLight3D.new()
	rim.name = "RimLight"
	rim.light_color = Color(0.65, 0.8, 1.0)
	rim.omni_range = 1.8
	rim.omni_attenuation = 1.2
	rim.shadow_enabled = false
	rim.position = Vector3(-0.7, 1.7, 0.0)   # behind the dancer (the anchor faces +X)
	node.add_child(rim)
	var r := {"node": node, "player": ap, "lights": lights, "k": k, "seq": k, "open": false, "spot": spot, "rim": rim}
	if ap != null:
		ap.animation_finished.connect(func(_n): _next(r))
	return r

func _next(r: Dictionary) -> void:
	var ap: AnimationPlayer = r["player"]
	if ap == null:
		return
	var c: String = "robot_idle"
	if bool(r["open"]):
		c = DANCES[int(r["seq"]) % DANCES.size()]
		r["seq"] = int(r["seq"]) + 1
	if not ap.has_animation(c):
		for an in ap.get_animation_list():
			if String(an).ends_with(c):
				c = String(an)
				break
	if ap.has_animation(c):
		ap.play(c, 0.0)
		stats["clip"] = c
	stats["open"] = bool(r["open"])
