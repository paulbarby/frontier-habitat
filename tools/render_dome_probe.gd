extends SceneTree
## RENDER: the super dome template: groups, surfaces (draw calls per dome), anchors, materials.
##   node tools/godot.mjs script res://tools/render_dome_probe.gd [merged]
const Models = preload("res://presentation/models.gd")
func _init() -> void:
	var merged: bool = "merged" in OS.get_cmdline_user_args()
	var tpl: Dictionary = Models.dome_template(merged) if merged else Models.dome_template()
	var surf := 0
	var by_group := {}
	var mats := {}
	for p in tpl["parts"]:
		var m: Mesh = p["mesh"]
		surf += m.get_surface_count()
		by_group[p["group"]] = int(by_group.get(p["group"], 0)) + m.get_surface_count()
		for s in m.get_surface_count():
			var mt: Material = m.surface_get_material(s)
			var nm: String = mt.resource_name if mt != null else "-"
			mats[nm] = int(mats.get(nm, 0)) + 1
	print("DOME groups %d parts %d surfaces %d anchors %d merged %s" % [by_group.size(), tpl["parts"].size(), surf, tpl["anchors"].size(), str(merged)])
	var keys: Array = by_group.keys()
	keys.sort()
	var line := ""
	for k in keys:
		line += "%s:%d " % [String(k).substr(2), by_group[k]]
	print("GROUPS ", line)
	print("MATS ", mats)
	quit(0)
