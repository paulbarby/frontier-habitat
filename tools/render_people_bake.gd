extends SceneTree
## RENDER: bakes the V5 people libraries headless and prints parts, outfits, materials and cost.
##   node tools/godot.mjs script res://tools/render_people_bake.gd
const Npc = preload("res://presentation/fx_npc.gd")
func _init() -> void:
	print("PEOPLE variants ", Npc.people_variants())
	var vl: Array = []
	for v in Npc.people_variants():
		vl.append(v)
		if ResourceLoader.exists("res://assets/models/people_%s_lod1.glb" % v):
			vl.append(v + "_lod1")
	for v in vl:
		var lib: Dictionary = Npc.load_lib("p_" + v)
		if not bool(lib.get("ok", false)):
			print("LIB p_%s FAILED %s" % [v, lib.get("status", "?")])
			continue
		print("LIB p_%s ok nb %d row_w %d rows %d clips %d missing %s tris %d bake %.0f ms outfits %s" % [v, lib["nb"], lib["tex_info"]["row_w"], lib["rows"], (lib["clips"] as Dictionary).size(), str(lib["missing"]), lib["tris"], lib["bake_ms"], str(Npc.lib_outfits(lib))])
		var tri_once := 0
		for p in lib["parts"]:
			if String(p.get("outfit", "")) == "uniform" or String(p.get("outfit", "")) == "casual_a" or p.has("head"):
				tri_once += 0
		for p in lib["parts"]:
			if not OS.get_cmdline_user_args().has("parts"):
				break
			var mesh: Mesh = p["mesh"]
			var mats: Array = []
			for s in mesh.get_surface_count():
				var m = mesh.surface_get_material(s)
				if m is ShaderMaterial:
					mats.append("%s:m%d%s" % [m.resource_name, int(m.get_shader_parameter("mode")), "/2s" if (m as ShaderMaterial).shader.resource_path.ends_with("_2s.gdshader") else ""])
			print("  PART %s outfit=%s face=%s shadow_only=%s | %s" % [p["name"], p.get("outfit", ""), str(p.get("face", false)), str(p.get("shadow_only", false)), " ".join(mats)])
	print("OUTFIT_FOR casual_b ", Npc.outfit_for(Npc.load_lib("p_m1"), "casual_b"), " uniform_medical ", Npc.outfit_for(Npc.load_lib("p_m1"), "uniform_medical"), " prison ", Npc.outfit_for(Npc.load_lib("p_m1"), "prison"))
	quit(0)
