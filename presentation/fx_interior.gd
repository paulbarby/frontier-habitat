extends Node3D
const SkyFx = preload("res://presentation/fx_sky.gd")
## Interior lighting (RENDER, V3_DESIGN §7.3): "bright, spacious and modern, day and night".
## Three layers, cheapest first:
##  1. Fill: interior surfaces (models.gd interior_material, wall_cut on inward faces) add a
##     warm light of their own, stronger at night (models.gd FILL_DAY / FILL_NIGHT).
##  2. Light pools: a warm additive pool on the floor under every ceiling lamp
##     (Anchor_Light_<i>) of every room: ONE MultiMesh, depth-tested.
##  3. Real OmniLights at the Anchor_Light_<i> of the open rooms nearest the camera focus,
##     inside a budget by quality (0 / 2 / 4 / 6); the sky keeps that many fewer night lamps
##     so no object gets more than the renderer's 8 lights.

const Models = preload("res://presentation/models.gd")
const POOL_SHADER = preload("res://shaders/light_pool.gdshader")
const FLOOR_Z := 0.14
const WARM := Color(1.0, 0.91, 0.82)        # ceiling lights, about 4 800 K (ART-HAB P8)
const LAMP := Color(1.0, 0.70, 0.42)        # bedside / desk / bar lamps, about 3 100 K
const BUDGET := [0, 2, 4, 6]
# ART-HAB J4 (round 7): family accent lights at Anchor_Accent_<i>: a coloured point light and
# a coloured floor spill. Ratios kept: accent point : spill : ceiling = 80 : 30 : 90.
const ACCENT_POINT := 80.0 / 90.0
const ACCENT_SPILL := 30.0 / 90.0
const CEILING_RANGE := 3.2           # m (J4: was 5.6 in ART-HAB's reference)
const FAMILY := {
	"lounge": "f08fc0", "cantina": "f08fc0", "greenhouse": "ff8fd8", "fungus_farm": "a78bfa",
	"algae_bioreactor": "9cffb0", "bio_lab": "9cffb0", "kitchen": "ffb070", "research_lab": "7fe0ff",
	"research_assembler": "8fb4ff", "medical": "bfe8ff", "cold_storage": "bfe8ff", "habitat": "ffc98a",
	"oxygen_plant": "5fe0ee", "atmo_processor": "5fe0ee", "water_recycler": "5fc8ff",
}
const INDUSTRY_AMBER := "ffb347"
# The floor spill is a fake pool on a bright floor: a coloured additive pool needs more gain
# than the warm ceiling pools to read (critic: "the family colour must show on the floor").
const ACCENT_POOL_GAIN := 6.0     # industry (7 types), storehouse, airlock and the rest

var view
var sim
var lights: Array = []
var used := 0
var quality := 2
var pools: MultiMeshInstance3D
var pool_mat: ShaderMaterial
var _pool_sig := ""
var _pool_clock := 0.0
var _light_clock := 0.0
var _cands: Array = []        # [{pos, range, room}]
var stats := {"pools": 0, "lights": 0, "accents": 0}
var lights_off := false        # test only (__fhr "ilights 0")

func setup(v) -> void:
	view = v
	sim = v.sim
	for c in get_children():
		c.queue_free()
	lights = []
	for i in 6:
		var l := OmniLight3D.new()
		l.light_color = WARM
		l.omni_attenuation = 1.3
		l.shadow_enabled = false
		l.light_energy = 0.0
		SkyFx.park(l)
		l.light_specular = 0.35
		add_child(l)
		lights.append(l)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(uv[k])
		st.set_normal(Vector3.UP)
		st.add_vertex(q[k])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = st.commit()
	mm.instance_count = 0
	pools = MultiMeshInstance3D.new()
	pools.multimesh = mm
	pool_mat = ShaderMaterial.new()
	pool_mat.shader = POOL_SHADER
	pool_mat.render_priority = 1
	pools.material_override = pool_mat
	pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pools.custom_aabb = AABB(Vector3(-100, -60, -100), Vector3(1100, 260, 1100))
	pools.name = "LightPools"
	add_child(pools)
	_pool_sig = ""

func set_quality(q: int) -> void:
	quality = clampi(q, 0, 3)
	_light_clock = 0.0

func mark_dirty() -> void:
	_pool_sig = ""

## Family colour of a room type (J4 table).
static func family_color(def_id: String) -> Color:
	return Color(String(FAMILY.get(def_id, INDUSTRY_AMBER)))

## Accent anchor positions of one room (world), from its Anchor_Accent_<i> empties.
func _room_accents(meta: Dictionary) -> Array:
	var out: Array = []
	for an in meta["anchors"]:
		if String(an).begins_with("Accent_"):
			out.append((meta["anchors"][an] as Transform3D).origin)
	return out

## Lamp positions of one room (world), from its Anchor_Light_<i> empties.
func _room_lamps(meta: Dictionary) -> Array:
	var out: Array = []
	for an in meta["anchors"]:
		if String(an).begins_with("Light_"):
			out.append((meta["anchors"][an] as Transform3D).origin)
	return out

func _rebuild_pools() -> void:
	var list: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in view.bmeta:
		var meta: Dictionary = view.bmeta[id]
		if meta["mode"] != "inst" or not blds.has(id):
			continue
		var b: Dictionary = blds[id]
		if b["kind"] != "room":
			continue
		var s: float = float(meta["tpl"].get("scale", 1.0))
		var fy: float = (meta["xf"] as Transform3D).origin.y + FLOOR_Z * s + 0.03
		var lamps: Array = _room_lamps(meta)
		if lamps.is_empty():
			# A room model without lamp anchors: one soft pool in the middle.
			list.append([Vector3((meta["xf"] as Transform3D).origin.x, fy, (meta["xf"] as Transform3D).origin.z), float(b["radius"]) * 0.55])
			continue
		# J4 wall fall-off: pools stay in the middle half of the room (0.5 R to 0.6 R),
		# so the wall ring reads about 25 % darker than the middle.
		var rr: float = float(b["radius"])
		var c0: Vector3 = (meta["xf"] as Transform3D).origin
		for p in lamps:
			var dc: float = Vector2((p as Vector3).x - c0.x, (p as Vector3).z - c0.z).length()
			var r: float = clampf(maxf(rr * 0.55 - dc * 0.5, rr * 0.3), 1.2, 2.8)
			list.append([Vector3((p as Vector3).x, fy, (p as Vector3).z), r, WARM])
		# J4 family accent: a coloured floor spill under every Anchor_Accent_<i> (1.8 m disk
		# light 1 m above the floor -> about 1.3 m radius on the floor).
		var fam: Color = family_color(String(b["def"])).srgb_to_linear()
		for ap in _room_accents(meta):
			list.append([Vector3((ap as Vector3).x, fy + 0.005, (ap as Vector3).z), 1.4, fam * ACCENT_POOL_GAIN])
		# Critic round 8: a warm pool over the kitchen cook line (in front of each work spot).
		if String(b["def"]) == "kitchen":
			for an in meta["anchors"]:
				if String(an).begins_with("Work_"):
					var wx: Transform3D = meta["anchors"][an]
					var wp: Vector3 = wx.origin + wx.basis.x.normalized() * 0.55
					list.append([Vector3(wp.x, fy, wp.z), 1.15, LAMP * 2.2])
		# Small warm pools under the bedside, desk and bar lamps (Anchor_Lamp_*).
		for an in meta["anchors"]:
			if String(an).begins_with("Lamp_"):
				var lp: Vector3 = (meta["anchors"][an] as Transform3D).origin
				list.append([Vector3(lp.x, fy, lp.z), 0.8, LAMP * 1.3])
	var mm: MultiMesh = pools.multimesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, Transform3D(Basis(), list[i][0]))
		mm.set_instance_color(i, list[i][2] if (list[i] as Array).size() > 2 else WARM)
		mm.set_instance_custom_data(i, Color(float(list[i][1]), 0, 0, 0))
	stats["pools"] = list.size()
	var na := 0
	for e in list:
		if float(e[1]) == 1.4:
			na += 1
	stats["accents"] = na

func sync(delta: float, focus: Vector3, night: float) -> void:
	_pool_clock -= delta
	if _pool_clock <= 0.0:
		_pool_clock = 1.0
		var sig := "%d" % view.bmeta.size()
		for id in view.bmeta:
			sig += "%d%s;" % [id, String(view.bmeta[id]["mode"]).left(1)]
		if sig != _pool_sig:
			_pool_sig = sig
			_rebuild_pools()
	pool_mat.set_shader_parameter("intensity", lerpf(0.10, 0.55, night))
	# Real lights: the open rooms nearest the focus.
	var budget: int = 0 if lights_off else BUDGET[quality]
	_light_clock -= delta
	if _light_clock <= 0.0:
		_light_clock = 0.25
		_cands = []
		var rooms: Array = []
		var blds: Dictionary = sim.state["buildings"]
		for id in view.bmeta:
			var meta: Dictionary = view.bmeta[id]
			if meta["mode"] != "inst" or float(meta.get("open", 0.0)) < 0.5 or not blds.has(id):
				continue
			var d: float = (meta["xf"] as Transform3D).origin.distance_to(focus)
			if d < 60.0:
				rooms.append([d, id])
		rooms.sort_custom(func(a, b): return a[0] < b[0])
		for r in rooms:
			if _cands.size() >= budget:
				break
			var meta: Dictionary = view.bmeta[r[1]]
			var b: Dictionary = blds[r[1]]
			var lamps: Array = _room_lamps(meta)
			lamps.sort_custom(func(a, c): return (a as Vector3).distance_to(focus) < (c as Vector3).distance_to(focus))
			var fade: float = 1.0 - smoothstep(35.0, 60.0, float(r[0]))
			# J4: the family accent light first (one per room while the budget lasts), then
			# ceiling lights with the shorter 3.2 m reach.
			var acc: Array = _room_accents(meta)
			acc.sort_custom(func(a, c): return (a as Vector3).distance_to(focus) < (c as Vector3).distance_to(focus))
			if not acc.is_empty() and _cands.size() < budget:
				_cands.append({"pos": acc[0], "range": 3.0, "fade": fade, "col": family_color(String(b["def"])), "k": ACCENT_POINT})
			for p in lamps:
				if _cands.size() >= budget:
					break
				_cands.append({"pos": p, "range": CEILING_RANGE, "fade": fade, "col": WARM, "k": 1.0})
	used = 0
	for i in lights.size():
		var l: OmniLight3D = lights[i]
		if i < _cands.size() and i < budget:
			var c: Dictionary = _cands[i]
			l.visible = true
			l.position = c["pos"]
			l.omni_range = c["range"]
			l.light_color = c.get("col", WARM)
			var tgt: float = lerpf(0.55, 1.35, night) * float(c["fade"]) * float(c.get("k", 1.0))
			l.light_energy = lerpf(l.light_energy, tgt, 1.0 - exp(-delta * 6.0))
			used += 1
		else:
			if not SkyFx.parked(l):
				l.light_energy = lerpf(l.light_energy, 0.0, 1.0 - exp(-delta * 8.0))
				if l.light_energy < 0.02:
					SkyFx.park(l)
	stats["lights"] = used
	if view.sky != null:
		view.sky.reserved = used
