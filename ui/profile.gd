extends RefCounted
## The device profile (docs/AAA_DESIGN.md §8): every award ever earned on this device,
## kept in user://profile.json, across games and saves. It is interface data, not game
## state: deleting it changes no colony.

const PATH := "user://profile.json"

static var _data := {}
static var _loaded := false

static func _load() -> void:
	_loaded = true
	_data = {"version": 1, "awards": {}, "games": 0}
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			_data[k] = d[k]
	if typeof(_data.get("awards")) != TYPE_DICTIONARY:
		_data["awards"] = {}

static func _save() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, PATH)

static func data() -> Dictionary:
	if not _loaded:
		_load()
	return _data

## Records an award. Returns true when this device had never earned it before.
static func record_award(id: String, tick: int, seed_value: int, live: bool) -> bool:
	var d: Dictionary = data()
	var aw: Dictionary = d["awards"]
	var first: bool = not aw.has(id)
	if first:
		aw[id] = {"first": Time.get_unix_time_from_system(), "tick": tick, "seed": seed_value, "count": 1}
		_save()
	elif live:
		aw[id]["count"] = int(aw[id].get("count", 1)) + 1
		_save()
	return first

static func award(id: String) -> Dictionary:
	return data()["awards"].get(id, {})

static func award_count() -> int:
	return (data()["awards"] as Dictionary).size()

static func note_game() -> void:
	var d: Dictionary = data()
	d["games"] = int(d.get("games", 0)) + 1
	_save()
