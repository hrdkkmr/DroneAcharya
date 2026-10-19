extends "res://tests/test_case.gd"
## droneacharya-scenario v1 validation and seeded procedural generation.

const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const PRESET_DIR := "res://scenarios"


func _valid() -> Dictionary:
	return {
		"format": "droneacharya-scenario", "version": 1, "id": "t", "seed": 7,
		"environment": "rural", "time_of_day": "day", "visibility": "clear", "duration_s": 90,
		"groups": [{"profile": "unidentified_uav", "behavior": "loiter", "count": 1}],
	}


func _has_error(result: Dictionary, fragment: String) -> bool:
	for error in result["errors"]:
		if fragment in error:
			return true
	return false


func test_all_presets_validate() -> void:
	var files := DirAccess.get_files_at(PRESET_DIR)
	assert_true(files.size() >= 4, "at least four presets")
	for file in files:
		if file.ends_with(".json"):
			var result := ScenarioConfig.load_file(PRESET_DIR.path_join(file))
			assert_true(result["ok"], "%s validates: %s" % [file, "; ".join(result["errors"])])


func test_minimal_config_gets_documented_defaults() -> void:
	var result := ScenarioConfig.validate(_valid())
	assert_true(result["ok"], "minimal config valid: " + "; ".join(result["errors"]))
	var c: Dictionary = result["config"]
	assert_eq(c["difficulty"], 1, "default difficulty")
	assert_eq(c["sensor"]["radar"]["range_m"], 1500.0, "default radar range")
	assert_eq(c["weights"], ScenarioConfig.DEFAULT_WEIGHTS, "default weights")
	assert_eq(c["groups"][0]["count"], 1, "count typed as int")


func test_invalid_configs_are_rejected_with_reasons() -> void:
	var cases := {
		"format must be": {"format": "other"},
		"version must be 1": {"version": 2},
		"environment must be one of": {"environment": "desert"},
		"time_of_day must be one of": {"time_of_day": "dusk"},
		"duration_s must be a whole number": {"duration_s": 5},
		"seed must be a whole number": {"seed": -1},
		"groups must be a non-empty array": {"groups": []},
		"profile must be one of": {"groups": [{"profile": "fighter"}]},
		"is not valid for bird": {"groups": [{"profile": "bird", "behavior": "loiter"}]},
		"count must be a whole number from 3": {"groups": [{"profile": "swarm_uav", "count": 2}]},
		"spawn_s must satisfy": {"groups": [{"profile": "bird", "spawn_s": [50, 10]}]},
		"weights must total 100": {"weights": {"detection": 50, "classification": 20, "evidence": 15, "response": 20, "response_time": 15, "degraded": 10}},
		"id_range_m must not exceed": {"sensor": {"eo": {"range_m": 200, "id_range_m": 400}}},
		"end_s must be after start_s": {"sensor": {"degradation": [{"start_s": 40, "end_s": 30}]}},
		"at least one sensor": {"sensor": {"radar": {"enabled": false}, "eo": {"enabled": false}}},
		"at most 30 actors": {"groups": [
			{"profile": "swarm_uav", "count": 12}, {"profile": "swarm_uav", "count": 12}, {"profile": "bird", "count": 6, "behavior": "erratic"},
			{"profile": "balloon", "count": 1}]},
	}
	for expected in cases:
		var config := _valid()
		config.merge(cases[expected], true)
		var result := ScenarioConfig.validate(config)
		assert_true(not result["ok"], "rejected: " + expected)
		assert_true(_has_error(result, expected), "reason mentions '%s': %s" % [expected, "; ".join(result["errors"])])
	assert_true(not ScenarioConfig.validate("not an object")["ok"], "non-object rejected")
	assert_true(not ScenarioConfig.load_file("res://scenarios/missing.json")["ok"], "missing file rejected")


func test_procedural_generation_is_valid_and_reproducible() -> void:
	for seed_value in [1, 42, 26247, 4294967295]:
		for difficulty in [1, 3, 5]:
			var a := ScenarioConfig.generate(seed_value, {"difficulty": difficulty})
			assert_true(a["ok"], "seed %d level %d valid: %s" % [seed_value, difficulty, "; ".join(a["errors"])])
			assert_eq(a["config"], ScenarioConfig.generate(seed_value, {"difficulty": difficulty})["config"], "same seed, same config")
	assert_true(ScenarioConfig.generate(1)["config"] != ScenarioConfig.generate(2)["config"], "different seeds differ")


func test_procedural_options_are_respected() -> void:
	var single: Dictionary = ScenarioConfig.generate(5, {"single": true, "environment": "urban", "time_of_day": "night", "visibility": "fog"})["config"]
	assert_eq(single["groups"].size(), 1, "single threat")
	assert_eq([single["environment"], single["time_of_day"], single["visibility"]], ["urban", "night", "fog"], "conditions fixed")
	var swarm: Dictionary = ScenarioConfig.generate(5, {"swarm": true, "difficulty": 2})["config"]
	var profiles := []
	for g in swarm["groups"]:
		profiles.append(g["profile"])
	assert_true("swarm_uav" in profiles, "swarm requested")
	var hard: Dictionary = ScenarioConfig.generate(5, {"difficulty": 5})["config"]
	var easy: Dictionary = ScenarioConfig.generate(5, {"difficulty": 1})["config"]
	assert_true(hard["sensor"]["radar"]["detection_prob"] < easy["sensor"]["radar"]["detection_prob"], "harder = lower detection probability")
	assert_true(not hard["sensor"]["degradation"].is_empty(), "harder levels include degradation")
