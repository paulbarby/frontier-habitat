extends SceneTree
## Times HUD module refreshes headless on a save (desktop timings; the web build is slower).
##   node tools/godot.mjs script res://tools/ui/prof_hud.gd --load=res://content/saves/showcase_v3_late.fhsave --title=0

var _main
var _n := 0

func _init() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)

func _t(label: String, c: Callable, reps: int = 5) -> void:
	var t0: int = Time.get_ticks_usec()
	for i in reps:
		c.call()
	print("%-28s %7.2f ms" % [label, float(Time.get_ticks_usec() - t0) / 1000.0 / reps])

func _process(_d: float) -> bool:
	_n += 1
	if _n < 20:
		return false
	var h = _main.hud
	_t("minimap._paint", func(): h.minimap._paint())
	_t("minimap._terrain_image", func(): h.minimap._terrain_image(), 1)
	_t("goals.refresh", func(): h.goals.refresh())
	_t("alerts.refresh", func(): h.alerts.refresh())
	_t("nav.refresh", func(): h.nav.refresh())
	_t("build_bar.refresh", func(): h.build_bar.refresh())
	_t("top_bar.refresh", func(): h.top_bar.refresh())
	_t("hazard.refresh", func(): h.hazard.refresh())
	_t("inspector.refresh", func(): h.inspector.refresh())
	_t("watchers.check", func(): h.watchers.check())
	_t("data.kpis", func(): h.data.kpis())
	_t("tension_now", func(): h.tension_now())
	_t("sim.step x10", func():
		for i in 10:
			_main.sim.step(), 3)
	return true
