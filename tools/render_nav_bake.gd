extends SceneTree
## RENDER: bakes the furniture grid (fx_nav) of every room model into
## res://presentation/navgrid/<model>.nav, so the web build does not rasterise models at
## run time (70-140 ms each natively). A grid whose model changed is rebuilt live.
##   node tools/godot.mjs script res://tools/render_nav_bake.gd

const Models = preload("res://presentation/models.gd")
const Nav = preload("res://presentation/fx_nav.gd")

func _init() -> void:
	var n := 0
	var skipped := 0
	var t0: int = Time.get_ticks_msec()
	var dir := DirAccess.open("res://assets/models")
	for f in dir.get_files():
		if not f.ends_with(".glb"):
			continue
		var name: String = f.get_basename()
		if name.begins_with("ship_") or name.begins_with("crop") or name.begins_with("crate") or name.begins_with("astronaut") or name.begins_with("rock"):
			continue
		var tpl: Dictionary = Models._template_from_file("res://assets/models/" + f)
		var has_ring := false
		for p in tpl["parts"]:
			if float(p.get("wall_r", 0.0)) > 0.0:
				has_ring = true
		if not has_ring:
			skipped += 1
			continue
		if Nav.bake(tpl, name):
			n += 1
	# Per-room decal data from ART-HAB's build report (tools/ is not exported).
	var meta := {}
	if FileAccess.file_exists("res://tools/blender/build_report.json"):
		var rep = JSON.parse_string(FileAccess.get_file_as_string("res://tools/blender/build_report.json"))
		if rep is Dictionary:
			for m in rep.get("models", []):
				var dec = ((m as Dictionary).get("v3", {}) as Dictionary).get("decals", {}) if m is Dictionary else {}
				if dec is Dictionary and not (dec as Dictionary).is_empty():
					meta[String(m.get("id", ""))] = dec
	var r := Resource.new()
	r.set_meta("rooms", meta)
	ResourceSaver.save(r, Nav.BAKE_DIR + "room_meta.res", ResourceSaver.FLAG_COMPRESS)
	print("render_nav_bake: %d grids, %d models without a wall ring, %d room metas, %d ms" % [n, skipped, meta.size(), Time.get_ticks_msec() - t0])
	quit()