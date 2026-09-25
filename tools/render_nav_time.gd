extends SceneTree
## RENDER: times the furniture grid (fx_nav) of a few room models.
##   node tools/godot.mjs script res://tools/render_nav_time.gd

const Models = preload("res://presentation/models.gd")
const Nav = preload("res://presentation/fx_nav.gd")

func _init() -> void:
	for id in ["habitat_m", "kitchen_m", "research_lab_l", "airlock", "junction"]:
		var path := "res://assets/models/%s.glb" % id
		if not ResourceLoader.exists(path):
			continue
		var t0: int = Time.get_ticks_usec()
		var tpl: Dictionary = Models._template_from_file(path)
		var t1: int = Time.get_ticks_usec()
		var g: Dictionary = Nav.grid_of(tpl)
		var t2: int = Time.get_ticks_usec()
		print("%s: template %.1f ms, grid %.1f ms, tris %d, n %d" % [id, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, int(g.get("tris", 0)), int(g.get("n", 0))])
	quit()
