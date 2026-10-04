extends RefCounted
## Player settings, kept in user://settings.json. Applied by presentation/main.gd.

const PATH := "user://settings.json"
const DEFAULTS := {
	"quality": 2, "ui_scale": 1.0, "glass": true, "edge_pan": false, "camera_speed": 1.0,
	"vol_master": 0.8, "vol_music": 0.5, "vol_sfx": 0.8, "vol_ui": 0.7, "vol_ambience": 0.6,
	"tutorial_tips": true, "camera_shake": true,
	# Panel manager (docs/UI_PANELS.md): the dock open or closed; each message type: popup | badge | off.
	"dock_open": true, "notify_alert": "popup", "notify_hazard": "popup", "notify_reactor": "popup", "notify_unrest": "popup",
	"notify_request": "popup", "notify_traffic": "popup", "notify_people": "popup", "notify_goal": "popup", "notify_award": "popup",
	"notify_research": "popup", "notify_build": "popup", "notify_system": "popup", "notify_party": "popup", "notify_hr": "popup", "notify_orders": "popup", "notify_music": "badge",
	# V5 section 16: "Cheeky dialogue" (innuendo lines; off = mild flirt lines). SIM: set_option cheeky.
	"cheeky": true,
	# Music panel (V5 section 19.5): tracks the player turned off (null = the manifest defaults), moods that may play (null = all), shuffle.
	"music_off": null, "music_moods": null, "music_shuffle": false, "hint_vehicles": false,
	# All roofs off (Paul, 2026-10-01): key Y, the nav rail button; RENDER view.set_roofs_off.
	"roofs_off": false,
}

static var values := {}
static var _loaded := false

static func load_all() -> Dictionary:
	_loaded = true
	values = DEFAULTS.duplicate()
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				for k in d:
					if DEFAULTS.has(k):
						values[k] = d[k]
	return values

static func get_value(key: String):
	if not _loaded:
		load_all()
	return values.get(key, DEFAULTS.get(key))

static func set_value(key: String, v) -> void:
	if not _loaded:
		load_all()
	values[key] = v
	save()

static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(values, "\t"))
	f.close()
