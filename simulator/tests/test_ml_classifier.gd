extends "res://tests/test_case.gd"
## Model 2: artefact loading/validation, parity with scikit-learn, prediction schema,
## fallback to the rule-based baseline, and inference latency.

const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")
const Features := preload("res://scripts/ai/features.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const PARITY := "res://tests/fixtures/ml_parity_v1.json"


func _classifier() -> MlClassifier:
	var classifier := MlClassifier.new()
	classifier.load_model(MlClassifier.DEFAULT_PATH)
	return classifier


func _features_from(row: Array) -> Dictionary:
	var f := {}
	for i in Features.NAMES.size():
		f[Features.NAMES[i]] = float(row[i])
	return f


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PARITY))


func test_shipped_model_loads_and_matches_the_simulator_features() -> void:
	var c := _classifier()
	assert_true(c.is_loaded(), "model loads: " + c.error)
	assert_eq(c.info()["features"], "features-1", "feature version")
	assert_eq(c.model_type, "random_forest", "selected model type")
	assert_true(c.info()["trees"] > 0, "trees loaded")
	assert_true(not c.metrics.is_empty(), "held-out metrics shipped with the model")


func test_predictions_match_scikit_learn_on_held_out_rows() -> void:
	var c := _classifier()
	var fixture := _fixture()
	assert_eq(fixture["feature_names"], Features.NAMES, "fixture uses features-1")
	assert_eq(fixture["classes"], c.classes, "same class order")
	var worst := 0.0
	var disagreements := 0
	for i in fixture["features"].size():
		var ours := c.predict_vector(PackedFloat64Array(fixture["features"][i]))
		var theirs: Array = fixture["probabilities"][i]
		var best_ours := 0
		var best_theirs := 0
		for k in ours.size():
			worst = maxf(worst, absf(ours[k] - float(theirs[k])))
			if ours[k] > ours[best_ours]:
				best_ours = k
			if float(theirs[k]) > float(theirs[best_theirs]):
				best_theirs = k
		disagreements += int(best_ours != best_theirs)
	assert_true(worst < 1e-6, "probabilities match scikit-learn (max difference %s)" % str(worst))
	assert_eq(disagreements, 0, "identical predicted class on all %d rows" % fixture["features"].size())


func test_prediction_schema_and_latency() -> void:
	var c := _classifier()
	var fixture := _fixture()
	var total_us := 0
	var count := 200
	for i in count:
		var result := c.predict(_features_from(fixture["features"][i]))
		assert_true(result["ok"], "prediction ok")
		if i == 0:
			assert_true(result["category"] in c.classes, "category is a model class")
			assert_true(result["confidence"] >= 0.0 and result["confidence"] <= 1.0, "score within 0-1")
			var total := 0.0
			for k in result["probabilities"]:
				total += float(result["probabilities"][k])
			assert_near(total, 1.0, 0.001, "class scores sum to 1")
			assert_true(result["evidence"] in ["insufficient", "fair", "good"], "evidence quality attached")
		total_us += int(result["latency_us"])
	var mean_ms := total_us / 1000.0 / count
	print("     ML inference mean latency: %.3f ms per track (%d predictions)" % [mean_ms, count])
	assert_true(mean_ms < 20.0, "inference fast enough for once-per-second decision support")
	var incomplete := c.predict({"speed_mean": 3.0})
	assert_true(not incomplete["ok"] and "missing feature" in incomplete["error"], "rejects inputs that are not complete features-1")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_missing_corrupt_or_mismatched_models_fail_safely() -> void:
	var dir := "user://ml_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var missing := MlClassifier.new()
	assert_true(not missing.load_model(dir + "/nope.json") and "not found" in missing.error, "missing file")
	_write(dir + "/corrupt.json", "{not json")
	var corrupt := MlClassifier.new()
	assert_true(not corrupt.load_model(dir + "/corrupt.json") and "not valid JSON" in corrupt.error, "corrupt file")
	var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MlClassifier.DEFAULT_PATH))
	var sample := _features_from(_fixture()["features"][0])
	var mutations := [
		["features do not match", "feature_names", model["feature_names"].slice(1)],
		["unsupported model format", "format_version", 99],
		["unsupported model type", "model_type", "neural_net"],
		["unknown class", "classes", ["bird", "fighter", "swarm", "balloon", "authorised_uav"]],
	]
	for m in mutations:
		var copy: Dictionary = model.duplicate(true)
		copy[m[1]] = m[2]
		_write(dir + "/bad.json", JSON.stringify(copy))
		var bad := MlClassifier.new()
		assert_true(not bad.load_model(dir + "/bad.json"), "rejected: " + m[0])
		assert_true(m[0] in bad.error, "error explains '%s': %s" % [m[0], bad.error])
		assert_true(not bad.predict(sample)["ok"], "no predictions from a rejected model")
	var broken_tree: Dictionary = model.duplicate(true)
	broken_tree["params"]["trees"][0]["left"] = [1]
	_write(dir + "/bad.json", JSON.stringify(broken_tree))
	var bad_tree := MlClassifier.new()
	assert_true(not bad_tree.load_model(dir + "/bad.json") and "malformed tree" in bad_tree.error, "malformed tree rejected")


func test_session_uses_ml_when_loaded_and_labels_the_rule_fallback() -> void:
	var config: Dictionary = ScenarioConfig.load_file("res://scenarios/01_single_rural_day.json")["config"]
	var with_ml := ThreatSession.new(config, _classifier())
	var broken := MlClassifier.new()
	broken.load_model("user://missing_model.json")
	var fallback := ThreatSession.new(config, broken)
	with_ml.start()
	fallback.start()
	for i in 20 * 40:
		with_ml.step()
		fallback.step()
	var ml_entry: Dictionary = with_ml.decisions.latest.values()[0]
	assert_true(ml_entry["ml"]["ok"], "ML assessment produced")
	assert_eq(ml_entry["policy"]["based_on"], "track-classifier-v1", "policy uses the ML assessment when it is loaded")
	var fb_entry: Dictionary = fallback.decisions.latest.values()[0]
	assert_true(not fallback.decisions.ml_active(), "unloaded model is not active")
	assert_true(String(fb_entry["policy"]["based_on"]).begins_with("rules-da"), "policy falls back to the rule-based baseline")
	assert_true(fb_entry["ml"].is_empty(), "no ML output from an unloaded model")
