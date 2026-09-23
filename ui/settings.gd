extends RefCounted
## Player settings, kept in user://settings.json. Applied by presentation/main.gd.

const PATH := "user://settings.json"
const DEFAULTS := {
	"quality": 2, "ui_scale": 1.0, "glass": true, "edge_pan": false, "camera_speed": 1.0,
	"vol_master": 0.8, "vol_music": 0.5, "vol_sfx": 0.8, "vol_ui": 0.7, "vol_ambience": 0.6,
	"tutorial_tips": true,
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
