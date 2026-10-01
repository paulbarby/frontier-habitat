extends SceneTree
## RENDER check (Paul 2026-10-01: storm streaks inside habitats): during a dust storm, with the follow camera
## indoors, no weather particle may be drawn inside a room or corridor. The check recomputes every particle
## of the storm field and the camera dust field exactly as particles_inc.gdshaderinc does (the shader's own
## parameters), keeps the ones the shader's clip lets through, and counts those that lie inside a room
## (xz circle, below the model top) or a corridor (1.2 m capsule, below 2.6 m) by the SIM's geometry.
## Pass: 0 such particles in every sample. Also prints how many particles the clip removed.
##   node tools/godot.mjs script res://tools/render_weather_check.gd [label]
## Writes build/web_render/weather_check_<label>.json.

const DT := 1.0 / 30.0
const SAVES := ["res://content/saves/showcase_v3_late.fhsave", "res://content/saves/showcase_v4.fhsave"]
const PROBE = preload("res://presentation/fx_follow_probe.gd")
var main
var label := "run"
var save_i := -1
var frames := 0
var phase := 0
var res := {}
var cur := {}
var probe

func _initialize() -> void:
	for s in OS.get_cmdline_user_args():
		if not s.begins_with("--"):
			label = s
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _next_save() -> bool:
	save_i += 1
	if save_i >= SAVES.size():
		return false
	var path: String = SAVES[save_i]
	if not FileAccess.file_exists(path):
		print("missing save ", path)
		return _next_save()
	main._import_bytes(FileAccess.get_file_as_bytes(path))
	main.set_speed(1)
	main.step_cap_us = 1 << 30
	frames = 0
	phase = 0
	cur = {"save": path.get_file(), "samples": 0, "follows": 0, "inside_drawn": 0, "inside_clipped": 0, "particles": 0, "cam_indoor_samples": 0, "detail": []}
	res[path.get_file()] = cur
	return true

func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	if save_i < 0 or phase >= 3:
		if not _next_save():
			_write()
			return true
		main.view.debug_cmd("storm 1")
		probe = PROBE.new(main.view)
		return false
	main.set_process(false)
	main._process(DT)
	frames += 1
	if frames == 1:
		var id: int = probe.pick_walker("in", int(main.view.follow_id))
		if id >= 0 and main.view.follow_start(id):
			cur["follows"] = int(cur["follows"]) + 1
	if frames > 45 and frames % 15 == 0:
		_sample()
	if frames >= 150:
		frames = 0
		phase += 1
	return false

static func h11(x: float) -> float:
	return fposmod(sin(x * 127.1) * 43758.5453, 1.0)

func _fmod3(a: Vector3, m: Vector3) -> Vector3:
	return Vector3(fposmod(a.x, m.x), fposmod(a.y, m.y), fposmod(a.z, m.z))

## True when the shader's clip arrays hide a particle at p (the same rule as particles_inc.gdshaderinc).
func _clipped(clip: Dictionary, p: Vector3) -> bool:
	for c in clip["rooms"]:
		var v: Vector4 = c
		if p.y < v.w and Vector2(p.x, p.z).distance_to(Vector2(v.x, v.y)) < v.z:
			return true
	var tys: PackedFloat32Array = clip["tube_y"]
	var tb: Array = clip["tubes"]
	for i in tb.size():
		var s: Vector4 = tb[i]
		var a := Vector2(s.x, s.y)
		var b := Vector2(s.z, s.w)
		if p.y < tys[i] and Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b).distance_to(Vector2(p.x, p.z)) < 1.35:
			return true
	return false

## Inside a room or corridor by the SIM's geometry (independent of the clip arrays).
func _inside_volume(p: Vector3) -> String:
	var v = main.view
	for id in v.bmeta:
		var b: Dictionary = v.sim.state["buildings"].get(id, {})
		if b.is_empty() or String(b.get("state", "")) == "blueprint":
			continue
		if b["kind"] == "room":
			var meta: Dictionary = v.bmeta[id]
			var top: float = (meta["xf"] as Transform3D).origin.y + float(meta.get("top", 4.0))
			if p.y < top and Vector2(p.x, p.z).distance_to(b["pos"]) < float(b["radius"]):
				return "%s %d" % [b["def"], int(id)]
		elif b["def"] == "corridor":
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), b["p0"], b["p1"])
			if q.distance_to(Vector2(p.x, p.z)) < 1.2 and p.y < v.h(q.x, q.y) + 2.6:
				return "corridor %d" % int(id)
	return ""

func _sample() -> void:
	var v = main.view
	var fx = v.fx
	var r = v.rig()
	var cam: Vector3 = r.camera.global_position
	var indoor: bool = v.follow_id >= 0 and v.follow_ceiling(v.agent_world_pos(v.follow_id), cam) < INF
	cur["samples"] = int(cur["samples"]) + 1
	if indoor:
		cur["cam_indoor_samples"] = int(cur["cam_indoor_samples"]) + 1
	for pair in [[fx._storm, fx._storm_mat, 1800], [fx._field, fx._field_mat, 900]]:
		if not (pair[0] as Node3D).visible:
			continue
		var m: ShaderMaterial = pair[1]
		var n: int = pair[2]
		var size: Vector3 = m.get_shader_parameter("field_size")
		var center: Vector3 = m.get_shader_parameter("field_center")
		var wind: Vector3 = m.get_shader_parameter("wind")
		var now: float = float(m.get_shader_parameter("now"))
		var amount: float = float(m.get_shader_parameter("field_amount"))
		for i in n:
			var seed: float = float(i) / n
			if seed > amount:
				continue
			var r3 := Vector3(h11(seed * 3.1 + 0.7), h11(seed * 5.7 + 1.3), h11(seed * 9.2 + 2.1))
			var base: Vector3 = Vector3(r3.x * size.x, r3.y * size.y, r3.z * size.z) + wind * now * (0.6 + r3.y * 0.8)
			var p: Vector3 = center + _fmod3(base - center + size * 0.5, size) - size * 0.5
			p.y = center.y + (r3.y - 0.35) * size.y + sin(now * 0.7 + seed * 40.0) * 0.4
			cur["particles"] = int(cur["particles"]) + 1
			var inside: String = _inside_volume(p)
			if inside == "":
				continue
			if _clipped(fx.clip, p):
				cur["inside_clipped"] = int(cur["inside_clipped"]) + 1
			else:
				cur["inside_drawn"] = int(cur["inside_drawn"]) + 1
				if (cur["detail"] as Array).size() < 8:
					(cur["detail"] as Array).append("%s at %s cam %s" % [inside, str(p.snapped(Vector3.ONE * 0.1)), str(cam.snapped(Vector3.ONE * 0.1))])

func _write() -> void:
	var ok := true
	for k in res:
		var c: Dictionary = res[k]
		print("%s: samples %d (camera indoors %d), follows %d, particles %d | inside a room/corridor: drawn %d, clipped %d" % [k, c["samples"], c["cam_indoor_samples"], c["follows"], c["particles"], c["inside_drawn"], c["inside_clipped"]])
		for d in c["detail"]:
			print("   ", d)
		ok = ok and int(c["inside_drawn"]) == 0 and int(c["cam_indoor_samples"]) > 0
	print("TOTAL weather %s: %s" % [label, "PASS" if ok else "FAIL"])
	var f := FileAccess.open("res://build/web_render/weather_check_%s.json" % label, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"label": label, "pass": ok, "saves": res}, " "))
	quit()
