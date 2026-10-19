extends RefCounted
## droneacharya-scenario v1: validation, defaults and seeded procedural generation.
## A config describes *what kind* of scenario to build; scenario_generator.gd turns
## a valid config into concrete actors, paths and a layout from its seed.

const SimRandom := preload("res://scripts/sim/sim_random.gd")
const ActorProfiles := preload("res://scripts/sim/actor_profiles.gd")

const FORMAT := "droneacharya-scenario"
const VERSION := 1
const ENVIRONMENTS := ["urban", "rural"]
const TIMES_OF_DAY := ["day", "night"]
const VISIBILITIES := ["clear", "haze", "fog"]
const MAX_ACTORS := 30
const WEIGHT_KEYS := ["detection", "classification", "evidence", "response", "response_time", "degraded"]
const DEFAULT_WEIGHTS := {"detection": 20.0, "classification": 20.0, "evidence": 15.0, "response": 20.0, "response_time": 15.0, "degraded": 10.0}
const DEFAULT_SENSOR := {
	"radar": {"enabled": true, "range_m": 1500.0, "rate_hz": 1.0, "range_noise_m": 8.0,
		"bearing_noise_deg": 0.5, "elevation_noise_deg": 0.8, "detection_prob": 0.9, "max_elevation_deg": 60.0},
	"eo": {"enabled": true, "range_m": 700.0, "id_range_m": 350.0, "rate_hz": 5.0,
		"bearing_noise_deg": 0.15, "detection_prob": 0.95, "fov_deg": 360.0, "center_deg": 0.0},
	"delay_s": [0.2, 1.0],
	"clutter_per_min": 1.0,
	"degradation": [],
}


## Returns {"ok": bool, "errors": PackedStringArray, "config": Dictionary}. The config is
## normalised (defaults filled, numbers typed) and only meaningful when ok is true.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "errors": PackedStringArray(["scenario must be a JSON object"]), "config": {}}
	var src: Dictionary = raw
	var c := {}
	if src.get("format") != FORMAT:
		errors.append("format must be \"%s\"" % FORMAT)
	if not _is_number(src.get("version")) or int(src.get("version")) != VERSION:
		errors.append("version must be %d" % VERSION)
	c["format"] = FORMAT
	c["version"] = VERSION
	c["id"] = _text(src, "id", 1, 64, errors)
	c["title"] = _text(src, "title", 1, 80, errors, String(c["id"]))
	c["description"] = _text(src, "description", 0, 400, errors, "")
	c["seed"] = _int(src, "seed", 0, 4294967295, errors)
	c["environment"] = _choice(src, "environment", ENVIRONMENTS, errors)
	c["time_of_day"] = _choice(src, "time_of_day", TIMES_OF_DAY, errors)
	c["visibility"] = _choice(src, "visibility", VISIBILITIES, errors)
	c["duration_s"] = _int(src, "duration_s", 60, 600, errors)
	c["difficulty"] = _int(src, "difficulty", 1, 5, errors, 1)
	c["protected_zone_radius_m"] = _number(src, "protected_zone_radius_m", 40.0, 400.0, errors, 120.0)
	var wind: Dictionary = src.get("wind", {}) if typeof(src.get("wind", {})) == TYPE_DICTIONARY else {}
	c["wind"] = {
		"speed_mps": _number(wind, "speed_mps", 0.0, 15.0, errors, 3.0, "wind."),
		"direction_deg": _number(wind, "direction_deg", 0.0, 360.0, errors, 90.0, "wind."),
	}
	c["groups"] = _groups(src.get("groups"), int(c["duration_s"]) if _is_number(c["duration_s"]) else 600, errors)
	c["sensor"] = _sensor(src.get("sensor", {}), c, errors)
	c["weights"] = _weights(src.get("weights", DEFAULT_WEIGHTS), errors)
	return {"ok": errors.is_empty(), "errors": errors, "config": c}


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": PackedStringArray(["file not found: " + path]), "config": {}}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "errors": PackedStringArray(["invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]]), "config": {}}
	return validate(json.data)


## Builds a valid config from a seed. Options may fix environment, time_of_day,
## visibility, difficulty (1-5), "swarm" (bool) and "single" (one threat only).
static func generate(scenario_seed: int, options: Dictionary = {}) -> Dictionary:
	var rng := SimRandom.stream(scenario_seed, "procedural-config")
	var difficulty := clampi(int(options.get("difficulty", 1 + rng.randi() % 3)), 1, 5)
	var environment: String = options.get("environment", ENVIRONMENTS[rng.randi() % 2])
	var time_of_day: String = options.get("time_of_day", "night" if rng.randf() < 0.3 else "day")
	var visibility: String = options.get("visibility", VISIBILITIES[mini(rng.randi() % 3, difficulty - 1)])
	var duration := 120 + 30 * (difficulty - 1)
	var spawn_end := duration - 40
	var groups := []
	if options.get("single", false):
		groups.append(_group("unidentified_uav", ["transit", "loiter", "hover"][rng.randi() % 3], 1, [5, 25], [500, 900]))
	else:
		groups.append(_group("unidentified_uav", ["transit", "loiter", "hover"][rng.randi() % 3], 1 + int(difficulty >= 4), [5, spawn_end], [500, 1100]))
		groups.append(_group("authorised_uav", "transit", 1, [0, spawn_end], [700, 1200]))
		groups.append(_group("bird", "erratic", 1 + rng.randi() % (1 + difficulty), [0, spawn_end], [200, 700]))
		if difficulty >= 2 or rng.randf() < 0.5:
			groups.append(_group("balloon", "drift", 1, [0, spawn_end], [300, 900]))
		if options.get("swarm", difficulty >= 3):
			groups.append(_group("swarm_uav", ["transit", "loiter"][rng.randi() % 2], 3 + difficulty, [10, spawn_end], [800, 1300]))
	var quality := 1.0 - 0.1 * (difficulty - 1)
	var sensor := DEFAULT_SENSOR.duplicate(true)
	sensor["radar"]["detection_prob"] = snappedf(0.92 * quality, 0.01)
	sensor["radar"]["range_noise_m"] = 6.0 + 3.0 * difficulty
	sensor["radar"]["bearing_noise_deg"] = 0.3 + 0.15 * difficulty
	sensor["eo"]["detection_prob"] = snappedf(0.96 * quality, 0.01)
	sensor["delay_s"] = [0.2, 0.6 + 0.3 * difficulty]
	sensor["clutter_per_min"] = 0.5 * difficulty
	if difficulty >= 2:
		var start := float(30 + rng.randi() % 30)
		sensor["degradation"] = [{"start_s": start, "end_s": start + 15.0 + 5.0 * difficulty, "severity": snappedf(0.3 + 0.1 * difficulty, 0.01)}]
	var config := {
		"format": FORMAT, "version": VERSION,
		"id": "procedural-%d" % scenario_seed,
		"title": "Procedural · %s %s · level %d" % [environment, time_of_day, difficulty],
		"description": "Generated from seed %d." % scenario_seed,
		"seed": scenario_seed, "environment": environment, "time_of_day": time_of_day,
		"visibility": visibility, "duration_s": duration, "difficulty": difficulty,
		"protected_zone_radius_m": 120.0,
		"wind": {"speed_mps": snappedf(rng.randf_range(1.0, 6.0), 0.1), "direction_deg": float(rng.randi() % 360)},
		"groups": groups, "sensor": sensor, "weights": DEFAULT_WEIGHTS.duplicate(),
	}
	return validate(config)


static func _group(profile: String, behavior: String, count: int, spawn: Array, start_range: Array) -> Dictionary:
	var p := ActorProfiles.get_profile(profile)
	return {"profile": profile, "behavior": behavior, "count": count, "spawn_s": spawn,
		"start_range_m": start_range, "altitude_m": p["altitude_m"], "speed_mps": p["speed_mps"]}


static func _groups(raw: Variant, duration: int, errors: PackedStringArray) -> Array:
	var result := []
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		errors.append("groups must be a non-empty array")
		return result
	if (raw as Array).size() > 12:
		errors.append("at most 12 groups")
	var total := 0
	for i in (raw as Array).size():
		var g = raw[i]
		var prefix := "groups[%d]." % i
		if typeof(g) != TYPE_DICTIONARY:
			errors.append(prefix.trim_suffix(".") + " must be an object")
			continue
		var profile_name := String(g.get("profile", ""))
		var profile := ActorProfiles.get_profile(profile_name)
		if profile.is_empty():
			errors.append("%sprofile must be one of %s" % [prefix, ", ".join(PackedStringArray(ActorProfiles.names()))])
			continue
		var behavior := String(g.get("behavior", profile["behaviors"][0]))
		if not behavior in profile["behaviors"]:
			errors.append("%sbehavior '%s' is not valid for %s (use %s)" % [prefix, behavior, profile_name, ", ".join(PackedStringArray(profile["behaviors"]))])
		var swarm := profile_name == "swarm_uav"
		var count = _int(g, "count", 3 if swarm else 1, 12 if swarm else 6, errors, 3 if swarm else 1, prefix)
		total += count if typeof(count) == TYPE_INT else 0
		result.append({
			"profile": profile_name, "behavior": behavior, "count": count,
			"spawn_s": _pair(g, "spawn_s", 0.0, maxf(duration - 20.0, 0.0), errors, [0.0, 0.0], prefix),
			"start_range_m": _pair(g, "start_range_m", 100.0, 2000.0, errors, [400.0, 900.0], prefix),
			"altitude_m": _pair(g, "altitude_m", 5.0, 400.0, errors, profile["altitude_m"], prefix),
			"speed_mps": _pair(g, "speed_mps", 0.0, 20.0, errors, profile["speed_mps"], prefix),
		})
	if total > MAX_ACTORS:
		errors.append("at most %d actors in total (got %d)" % [MAX_ACTORS, total])
	return result


static func _sensor(raw: Variant, c: Dictionary, errors: PackedStringArray) -> Dictionary:
	var src: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var d: Dictionary = DEFAULT_SENSOR
	var radar_src: Dictionary = src.get("radar", {}) if typeof(src.get("radar", {})) == TYPE_DICTIONARY else {}
	var eo_src: Dictionary = src.get("eo", {}) if typeof(src.get("eo", {})) == TYPE_DICTIONARY else {}
	var radar := {
		"enabled": bool(radar_src.get("enabled", true)),
		"range_m": _number(radar_src, "range_m", 200.0, 5000.0, errors, d["radar"]["range_m"], "sensor.radar."),
		"rate_hz": _number(radar_src, "rate_hz", 0.2, 10.0, errors, d["radar"]["rate_hz"], "sensor.radar."),
		"range_noise_m": _number(radar_src, "range_noise_m", 0.0, 100.0, errors, d["radar"]["range_noise_m"], "sensor.radar."),
		"bearing_noise_deg": _number(radar_src, "bearing_noise_deg", 0.0, 10.0, errors, d["radar"]["bearing_noise_deg"], "sensor.radar."),
		"elevation_noise_deg": _number(radar_src, "elevation_noise_deg", 0.0, 10.0, errors, d["radar"]["elevation_noise_deg"], "sensor.radar."),
		"detection_prob": _number(radar_src, "detection_prob", 0.0, 1.0, errors, d["radar"]["detection_prob"], "sensor.radar."),
		"max_elevation_deg": _number(radar_src, "max_elevation_deg", 5.0, 90.0, errors, d["radar"]["max_elevation_deg"], "sensor.radar."),
	}
	var eo := {
		"enabled": bool(eo_src.get("enabled", true)),
		"range_m": _number(eo_src, "range_m", 50.0, 3000.0, errors, d["eo"]["range_m"], "sensor.eo."),
		"id_range_m": _number(eo_src, "id_range_m", 10.0, 3000.0, errors, d["eo"]["id_range_m"], "sensor.eo."),
		"rate_hz": _number(eo_src, "rate_hz", 0.5, 30.0, errors, d["eo"]["rate_hz"], "sensor.eo."),
		"bearing_noise_deg": _number(eo_src, "bearing_noise_deg", 0.0, 5.0, errors, d["eo"]["bearing_noise_deg"], "sensor.eo."),
		"detection_prob": _number(eo_src, "detection_prob", 0.0, 1.0, errors, d["eo"]["detection_prob"], "sensor.eo."),
		"fov_deg": _number(eo_src, "fov_deg", 5.0, 360.0, errors, d["eo"]["fov_deg"], "sensor.eo."),
		"center_deg": _number(eo_src, "center_deg", 0.0, 360.0, errors, d["eo"]["center_deg"], "sensor.eo."),
	}
	if _is_number(eo["id_range_m"]) and _is_number(eo["range_m"]) and eo["id_range_m"] > eo["range_m"]:
		errors.append("sensor.eo.id_range_m must not exceed sensor.eo.range_m")
	if not radar["enabled"] and not eo["enabled"]:
		errors.append("at least one sensor (radar or eo) must be enabled")
	var duration := float(c["duration_s"]) if _is_number(c["duration_s"]) else 600.0
	var degradation := []
	var raw_deg = src.get("degradation", [])
	if typeof(raw_deg) != TYPE_ARRAY:
		errors.append("sensor.degradation must be an array")
	else:
		for i in (raw_deg as Array).size():
			var w = raw_deg[i]
			var prefix := "sensor.degradation[%d]." % i
			if typeof(w) != TYPE_DICTIONARY:
				errors.append(prefix + " must be an object")
				continue
			var start = _number(w, "start_s", 0.0, duration, errors, null, prefix)
			var end = _number(w, "end_s", 0.0, duration, errors, null, prefix)
			if _is_number(start) and _is_number(end) and end <= start:
				errors.append(prefix + "end_s must be after start_s")
			degradation.append({"start_s": start, "end_s": end, "severity": _number(w, "severity", 0.0, 1.0, errors, 0.5, prefix)})
	return {
		"radar": radar, "eo": eo,
		"delay_s": _pair(src, "delay_s", 0.0, 5.0, errors, d["delay_s"], "sensor."),
		"clutter_per_min": _number(src, "clutter_per_min", 0.0, 30.0, errors, d["clutter_per_min"], "sensor."),
		"degradation": degradation,
	}


static func _weights(raw: Variant, errors: PackedStringArray) -> Dictionary:
	var result := {}
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("weights must be an object")
		return DEFAULT_WEIGHTS.duplicate()
	var total := 0.0
	for key in WEIGHT_KEYS:
		var value = _number(raw, key, 0.0, 100.0, errors, null, "weights.")
		result[key] = value
		total += float(value) if _is_number(value) else 0.0
	for key in raw:
		if not key in WEIGHT_KEYS:
			errors.append("weights.%s is not a known component" % key)
	if absf(total - 100.0) > 0.001:
		errors.append("weights must total 100 (got %s)" % total)
	return result


static func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _number(src: Dictionary, key: String, low: float, high: float, errors: PackedStringArray, default: Variant = null, prefix := "") -> Variant:
	var value = src.get(key, default)
	if value == null:
		errors.append("%s%s is required" % [prefix, key])
		return null
	if not _is_number(value) or float(value) < low or float(value) > high:
		errors.append("%s%s must be a number from %s to %s" % [prefix, key, low, high])
		return value
	return float(value)


static func _int(src: Dictionary, key: String, low: int, high: int, errors: PackedStringArray, default: Variant = null, prefix := "") -> Variant:
	var value = src.get(key, default)
	if value == null:
		errors.append("%s%s is required" % [prefix, key])
		return null
	if not _is_number(value) or float(value) != floorf(float(value)) or float(value) < low or float(value) > high:
		errors.append("%s%s must be a whole number from %d to %d" % [prefix, key, low, high])
		return value
	return int(value)


static func _pair(src: Dictionary, key: String, low: float, high: float, errors: PackedStringArray, default: Variant, prefix := "") -> Variant:
	var value = src.get(key, default)
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2 or not _is_number(value[0]) or not _is_number(value[1]):
		errors.append("%s%s must be [min, max]" % [prefix, key])
		return value
	var pair := [float(value[0]), float(value[1])]
	if pair[0] < low or pair[1] > high or pair[0] > pair[1]:
		errors.append("%s%s must satisfy %s <= min <= max <= %s" % [prefix, key, low, high])
	return pair


static func _text(src: Dictionary, key: String, min_len: int, max_len: int, errors: PackedStringArray, default: Variant = null, prefix := "") -> Variant:
	var value = src.get(key, default)
	if typeof(value) != TYPE_STRING or (value as String).length() < min_len or (value as String).length() > max_len:
		errors.append("%s%s must be text of %d-%d characters" % [prefix, key, min_len, max_len])
		return value
	return value


static func _choice(src: Dictionary, key: String, options: Array, errors: PackedStringArray) -> Variant:
	var value = src.get(key)
	if not value in options:
		errors.append("%s must be one of %s" % [key, ", ".join(PackedStringArray(options))])
	return value
