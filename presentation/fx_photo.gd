extends Node3D
## V5 §4.4 tabloid photos and personnel portraits (RENDER).
##   photo(agent_ids, place_hint, pose_hint) -> ImageTexture   (512 x 384, grainy "paparazzi" look)
## The texture is returned at once (dark grey) and filled a few frames later; the same request is
## cached (one render per story / portrait). A "studio" below the map (not seen by the main camera)
## holds view-only puppets of the named people (fx_npc.puppet: their own look, their outfit variant)
## in the pose asked for, facing each other for paired poses, before a simple backdrop of the place
## (bar, club, park, pool, corridor, jail, office, dome, default). Nothing is written to sim.state.
##
## Poses: the clip of that name when the people library has it (V5 clips when ART-NPC lands them),
## else the nearest v3 clip (POSE_FALLBACK). Robots are never framed close (mid shot at least).

const W := 512
const H := 384
const STUDIO := Vector3(-150.0, -150.0, -150.0)   # inside the body MultiMesh AABB (-200..2800), under the ground
const POSE_FALLBACK := {"argue": "idle_look", "shout": "idle_look", "kiss_brief": "idle", "hug": "idle", "punch": "cheer",
	"slap": "cheer", "cheer": "cheer", "handcuffed_walk": "walk", "escort_walk": "walk", "dance_a": "cheer", "dance_b": "cheer",
	"dance_c": "cheer", "wave": "cheer", "handshake": "idle", "laugh": "idle_look", "sulk": "idle", "talk_idle": "idle_look",
	"drink_bar": "sit_eat", "sit_bench": "sit_idle", "sit_bar_stool": "sit_idle", "protest_fist": "cheer", "portrait": "idle"}
const PAIRED := ["hug", "kiss_brief", "handshake", "slap", "punch", "argue", "escort_walk", "handcuffed_walk", "dance_a", "dance_b"]
const PLACE_COL := {"bar": [Color(0.22, 0.13, 0.08), Color(1.0, 0.62, 0.25)], "club": [Color(0.06, 0.03, 0.09), Color(1.0, 0.3, 0.85)],
	"park": [Color(0.22, 0.42, 0.18), Color(0.55, 0.8, 0.45)], "pool": [Color(0.1, 0.42, 0.6), Color(0.4, 0.9, 1.0)],
	"corridor": [Color(0.32, 0.34, 0.37), Color(0.35, 0.85, 1.0)], "jail": [Color(0.25, 0.25, 0.26), Color(1.0, 0.48, 0.1)],
	"office": [Color(0.3, 0.3, 0.33), Color(0.6, 0.75, 1.0)], "dome": [Color(0.34, 0.3, 0.26), Color(1.0, 0.8, 0.5)],
	"default": [Color(0.3, 0.26, 0.23), Color(1.0, 0.8, 0.6)]}

var view
var sim
var cache := {}              # key -> ImageTexture
var _queue: Array = []       # [{key, ids, place, pose, tex}]
var _job := {}
var _vp: SubViewport
var _cam: Camera3D
var _grain_vp: SubViewport
var _grain_rect: TextureRect
var _backdrop: Node3D
var _key_light: OmniLight3D
var stats := {"done": 0, "queued": 0, "last_ms": 0.0}

func setup(v) -> void:
	view = v
	sim = v.sim

func _ensure() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.own_world_3d = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.1
	_cam.far = 60.0
	_vp.add_child(_cam)
	_grain_vp = SubViewport.new()
	_grain_vp.size = Vector2i(W, H)
	_grain_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_grain_vp.transparent_bg = false
	add_child(_grain_vp)
	_grain_rect = TextureRect.new()
	_grain_rect.size = Vector2(W, H)
	_grain_rect.texture = _vp.get_texture()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/photo_grain.gdshader")
	_grain_rect.material = sm
	_grain_vp.add_child(_grain_rect)
	_backdrop = Node3D.new()
	add_child(_backdrop)
	_key_light = OmniLight3D.new()
	_key_light.omni_range = 9.0
	_key_light.light_energy = 1.4
	_key_light.shadow_enabled = false
	add_child(_key_light)
	_key_light.global_position = STUDIO + Vector3(1.8, 2.6, 2.4)

## A tabloid photo or a portrait (pose_hint "portrait" or one person). Cached per request.
func photo(agent_ids: Array, place_hint: String = "default", pose_hint: String = "idle") -> ImageTexture:
	var ids: Array = agent_ids.map(func(x): return int(x))
	var key := "%s|%s|%s" % [str(ids), place_hint, pose_hint]
	if cache.has(key):
		return cache[key]
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.12, 0.13))
	var tex := ImageTexture.create_from_image(img)
	cache[key] = tex
	_queue.append({"key": key, "ids": ids, "place": place_hint, "pose": pose_hint, "tex": tex})
	stats["queued"] = _queue.size()
	return tex

## Portrait for the personnel file.
func portrait(agent_id: int) -> ImageTexture:
	return photo([agent_id], "office", "portrait")

## The body a photo puppet uses: people library of the person (fx_npc._people_key), else the
## first people library for a person not in the simulation, else the indoor astronaut.
func _photo_variant(npc, a: Dictionary, i: int) -> String:
	if not a.is_empty():
		var k: String = npc._people_key(a)
		if npc.libs.has(k):
			return k
	var pk: Array = npc.libs.keys().filter(func(x): return String(x).begins_with("p_"))
	pk.sort()
	if not pk.is_empty():
		return pk[i % pk.size()]
	return "in" if npc.libs.has("in") else "suit"

## Off-duty places: the people in the photo wear casual clothes.
static func place_casual(place: String) -> bool:
	return place in ["bar", "club", "park", "pool", "dome"]

var _pairs = null
## Distance between the two partners of a paired pose (npc_pairs.json; 0.84 m when not listed).
func _pair_distance(pose: String) -> float:
	if _pairs == null:
		_pairs = {}
		var path := "res://assets/models/npc_pairs.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_pairs = parsed.get("pairs", {})
	var p = _pairs.get(pose)
	return float(p.get("distance_m", 0.84)) if p is Dictionary else 0.84

func _clip_for(lib: Dictionary, pose: String) -> String:
	var clips: Dictionary = lib.get("clips", {})
	if clips.has(pose):
		return pose
	var fb: String = POSE_FALLBACK.get(pose, "idle")
	return fb if clips.has(fb) else "idle"

func sync(_delta: float) -> void:
	if _job.is_empty():
		if _queue.is_empty():
			return
		_ensure()
		_job = _queue.pop_front()
		_job["step"] = 0
		_job["t0"] = Time.get_ticks_usec()
		stats["queued"] = _queue.size()
	match int(_job["step"]):
		0:
			_stage(_job)
			_job["step"] = 1
		1, 2:
			# the puppets are drawn from the next frame on; render the photo then
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			_job["step"] = int(_job["step"]) + 1
		3:
			_grain_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			_job["step"] = 4
		_:
			var img: Image = _grain_vp.get_texture().get_image()
			if img != null and not img.is_empty():
				(_job["tex"] as ImageTexture).set_image(img)
			_clear_stage()
			stats["done"] = int(stats["done"]) + 1
			stats["last_ms"] = snappedf((Time.get_ticks_usec() - int(_job["t0"])) / 1000.0, 0.1)
			_job = {}

func _stage(job: Dictionary) -> void:
	var npc = view.npc
	var ids: Array = job["ids"]
	var pose: String = job["pose"]
	var portrait: bool = pose == "portrait" or ids.size() == 1 and pose in ["idle", "portrait"]
	var paired: bool = ids.size() >= 2 and pose in PAIRED
	var n: int = maxi(1, ids.size())
	var keys: Array = []
	for i in n:
		var aid: int = ids[i] if i < ids.size() else -1
		var a: Dictionary = sim.state["agents"].get(aid, {})
		if npc == null:
			break
		# Every photo place is indoors (round 39: no suited astronaut in the club photo): the
		# person's own V5 people body when a people library is loaded, else the indoor astronaut.
		var variant: String = _photo_variant(npc, a, i)
		var key := "photo_%d" % i
		npc.puppet_free(key)
		var rec: Dictionary = npc.puppet(key, variant, String(a.get("role", "engineer")))
		if rec.is_empty():
			continue
		if npc.agents.has(aid):
			rec["look"] = npc.agents[aid]["look"]
		var plib: Dictionary = npc.libs.get(String(rec["var"]), {})
		if bool(plib.get("people", false)):
			if npc.agents.has(aid) and npc.agents[aid].has("plook"):
				for f in ["plook", "outfit", "omesh", "addons", "oidx", "cloth"]:
					if npc.agents[aid].has(f):
						rec[f] = npc.agents[aid][f]
			elif not a.is_empty():
				rec.erase("plook")
				npc._people_look(a, rec, plib)
			if place_casual(String(job["place"])):
				npc.set_outfit(plib, rec, npc.outfit_for(plib, "casual_a"))
		# Positions: paired poses face each other 0.8 m apart; a group stands in a shallow arc.
		var off := Vector3.ZERO
		var yaw := PI * 0.5   # facing the camera (+Z is towards it; model +X forward)
		if paired and i < 2:
			# ART-NPC pairs (npc_pairs.json): partner B at distance_m along A's forward axis, facing A.
			var half: float = 0.5 * _pair_distance(pose)
			off = Vector3(-half if i == 0 else half, 0, 0)
			yaw = 0.0 if i == 0 else PI
		elif n > 1:
			off = Vector3((float(i) - float(n - 1) * 0.5) * 0.85, 0, -absf(float(i) - float(n - 1) * 0.5) * 0.25)
		rec["pos"] = STUDIO + off
		rec["yaw"] = -yaw if not (paired and i < 2) else yaw
		rec["fade"] = 1.0
		var lib: Dictionary = npc.libs.get(String(rec["var"]), {})
		var clip: String = _clip_for(lib, "idle" if portrait else pose)
		rec["sm"].force(clip, true, true)   # cut: no cross-fade from the new puppet's rest pose
		# Paired clips start together (sync_s 0); a one-shot pair (hug) is shot at its middle.
		var lib_c: Dictionary = (lib.get("clips", {}) as Dictionary).get(clip, {})
		if paired and i < 2:
			rec["sm"].cur_t = float(lib_c.get("len", 2.0)) * 0.5 if not bool(lib_c.get("loop", true)) else 0.9
		else:
			rec["sm"].cur_t = 0.6 + 0.3 * float(i)
		keys.append(key)
	job["keys"] = keys
	_build_backdrop(String(job["place"]))
	# Camera: portrait = head and shoulders; else half-body to full body by group size.
	var look: Vector3
	var eye: Vector3
	if portrait:
		look = STUDIO + Vector3(0, 1.52, 0)
		eye = look + Vector3(0.35, 0.05, 1.35)
	else:
		var wdt: float = 1.2 + 0.7 * float(n)
		look = STUDIO + Vector3(0, 1.15, 0)
		eye = look + Vector3(0.9, 0.2, wdt * 1.25)
	_cam.global_position = eye
	_cam.look_at(look, Vector3.UP)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _clear_stage() -> void:
	if view.npc != null:
		for k in _job.get("keys", []):
			view.npc.puppet_free(String(k))
	for c in _backdrop.get_children():
		c.queue_free()

func _build_backdrop(place: String) -> void:
	var cols: Array = PLACE_COL.get(place, PLACE_COL["default"])
	var base: Color = cols[0]
	var acc: Color = cols[1]
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = base.darkened(0.2)
	floor_m.roughness = 0.8
	var wall_m := StandardMaterial3D.new()
	wall_m.albedo_color = base
	wall_m.roughness = 0.9
	var glow_m := StandardMaterial3D.new()
	glow_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_m.albedo_color = acc
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	fl.mesh = pm
	fl.material_override = floor_m
	_backdrop.add_child(fl)
	fl.global_position = STUDIO
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(14, 6, 0.2)
	wall.mesh = bm
	wall.material_override = wall_m
	_backdrop.add_child(wall)
	wall.global_position = STUDIO + Vector3(0, 3, -2.6)
	# Light strips / signs on the back wall (and trees in the park, water on the pool deck).
	for k in 3:
		var s := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(2.6, 0.08, 0.05) if place != "jail" else Vector3(0.06, 3.0, 0.06)
		s.mesh = sb
		s.material_override = glow_m
		_backdrop.add_child(s)
		s.global_position = STUDIO + (Vector3(-3.2 + k * 3.2, 2.4, -2.45) if place != "jail" else Vector3(-1.5 + k * 1.5, 1.5, -1.6))
	if place == "park":
		for k in 3:
			var tr := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 1.1
			sp.height = 2.0
			tr.mesh = sp
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.2, 0.5, 0.2)
			tr.material_override = tm
			_backdrop.add_child(tr)
			tr.global_position = STUDIO + Vector3(-3.0 + k * 3.0, 2.6, -2.0)
	_key_light.light_color = acc.lerp(Color(1, 0.95, 0.9), 0.6)
