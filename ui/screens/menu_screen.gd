extends "res://ui/screens/screen.gd"
## Pause menu (Esc): resume, save and load, settings, how to play, new colony, title.

func _init() -> void:
	compact = true
	compact_size = Vector2(500, 0)
	pauses = true
	icon = "pause"
	title = "Paused"

func build() -> void:
	var s = hud.main.sim
	var st: Dictionary = s.state
	var opts: Dictionary = st.get("options", {})
	var planet: String = String(hud.data.planets().get(String(st.get("planet", "dry")), {}).get("name", st.get("planet", "")))
	set_subtitle("Day %d  ·  seed %d  ·  %s  ·  %s" % [s.util.day_number(), int(st["seed"]), planet, String(opts.get("difficulty", "standard")).capitalize()])
	if hud.main.persist_warning != "":
		content.add_child(Kit.wrap(hud.main.persist_warning, 13, P.AMBER))
	var items := [
		["Resume", "play", "Back to the colony. Esc.", func(): host.close(self), "PrimaryButton"],
		["Save and load", "save", "Save to a slot, load a slot, export or import a save file.", func(): hud.open_screen("saveload"), ""],
		["Settings", "settings", "Graphics, interface scale, camera, sound, keys.", func(): hud.open_screen("settings"), ""],
		["How to play", "info", "The rules on one page, and every key.", func(): hud.open_screen("help"), ""],
		["Plan the reference outpost", "build", "Demo: places the documented reference layout as plans. The colonists build it under the normal rules.", func():
			host.close(self)
			hud.main.run_demo(), ""],
		["New colony", "new_game", "Pick a planet, a difficulty and a seed.", func(): hud.open_screen("newcolony"), ""],
		["Main menu", "home", "The title screen. The colony is autosaved first.", func(): hud.confirm("Leave to the main menu?", ["The colony is autosaved first. Continue loads it again."], func(): hud.main.go_title(), "Main menu"), ""],
	]
	for it in items:
		var b: Button = Kit.button(String(it[0]), it[3], "%s\n%s" % [it[0], it[2]], String(it[4]), String(it[1]), 18)
		b.custom_minimum_size = Vector2(0, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		content.add_child(b)
