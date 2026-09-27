extends SceneTree
## RENDER debug: the wall-ring radius of model files (parts with wall_r) and a few anchors.
##   node tools/godot.mjs script res://tools/render_model_radius.gd airlock_m airlock_l habitat_m
const Models = preload("res://presentation/models.gd")
func _init() -> void:
	for id in OS.get_cmdline_user_args():
		var tpl: Dictionary = Models._template_from_file("res://assets/models/%s.glb" % id)
		var wr := 0.0
		for p in tpl["parts"]:
			wr = maxf(wr, float(p.get("wall_r", 0.0)))
		var an: Array = []
		for k in (tpl.get("anchors", {}) as Dictionary):
			if String(k).begins_with("Chamber") or String(k).begins_with("Suit") or String(k).begins_with("Porch"):
				an.append("%s %s" % [k, str((tpl["anchors"][k] as Transform3D).origin.snappedf(0.01))])
		print("%s wall_r %.2f keys %s radius %s | %s" % [id, wr, str((tpl as Dictionary).keys()), str(tpl.get("radius", tpl.get("model_radius", "-"))), ", ".join(an)])
	quit()
