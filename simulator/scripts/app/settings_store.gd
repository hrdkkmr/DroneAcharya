extends RefCounted
## Player settings, persisted locally with ConfigFile. Static (no autoload) so it
## works in headless tests; the test runner redirects `path` to a scratch file.
## Volumes are linear 0..1 and are applied to the audio buses created by
## `ensure_buses()`. Unknown or out-of-range values in the file are clamped.

const BUSES := ["SFX", "Ambience"]
const QUALITY := ["standard", "reduced"]
const DEFAULTS := {
	"master_volume": 0.8,
	"sfx_volume": 0.8,
	"ambience_volume": 0.6,
	"muted": false,
	"mouse_sensitivity": 1.0, ## multiplier on the look speed (0.25 .. 3)
	"quality": "standard", ## "reduced" turns off shadows and other costly effects
	"tutorial_done": false,
	"drone_profile": "recon",
	"flight_mission": "basic_course",
}

static var path := "user://settings.cfg"
static var values := DEFAULTS.duplicate()
static var _loaded_from := ""


static func get_value(key: String) -> Variant:
	_ensure_loaded()
	return values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
	values[key] = _sanitize(key, value)
	apply()


## Loads from `path` (missing file = defaults). Returns false only on a read error.
static func load_settings() -> bool:
	values = DEFAULTS.duplicate()
	_loaded_from = path
	if not FileAccess.file_exists(path):
		apply()
		return true
	var file := ConfigFile.new()
	if file.load(path) != OK:
		apply()
		return false
	for key in DEFAULTS:
		if file.has_section_key("settings", key):
			values[key] = _sanitize(key, file.get_value("settings", key))
	apply()
	return true


static func save() -> bool:
	_ensure_loaded()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := ConfigFile.new()
	for key in values:
		file.set_value("settings", key, values[key])
	return file.save(path) == OK


static func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate()
	_loaded_from = path
	apply()


## Creates the SFX and Ambience buses (children of Master) when they do not exist.
static func ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")


static func apply() -> void:
	# The main menu applies settings at startup, before anything has read the file.
	_ensure_loaded()
	ensure_buses()
	_set_bus("Master", values["master_volume"], values["muted"])
	_set_bus("SFX", values["sfx_volume"], false)
	_set_bus("Ambience", values["ambience_volume"], false)


static func effects_reduced() -> bool:
	return get_value("quality") == "reduced"


static func _set_bus(bus: String, linear: float, mute: bool) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, mute or linear <= 0.001)


static func _ensure_loaded() -> void:
	if _loaded_from != path:
		load_settings()


static func _sanitize(key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS.get(key)
	match key:
		"master_volume", "sfx_volume", "ambience_volume":
			return clampf(float(value), 0.0, 1.0) if value is float or value is int else fallback
		"mouse_sensitivity":
			return clampf(float(value), 0.25, 3.0) if value is float or value is int else fallback
		"muted", "tutorial_done":
			return bool(value) if value is bool else fallback
		"quality":
			return value if value in QUALITY else fallback
		"drone_profile", "flight_mission":
			return String(value) if value is String and not String(value).is_empty() else fallback
	return value
