extends RefCounted
## Model 2 — trained machine-learning classifier (local, offline inference).
## Loads a droneacharya-ml-model v1 JSON artefact exported by ml/train.py (scikit-learn
## random forest or logistic regression) and evaluates it in GDScript. Inputs are the
## features-1 values only. The artefact is validated on load; any problem leaves the
## classifier unloaded with an error message, and decision support then falls back to
## the rule-based baseline (labelled as such). Scores are uncalibrated (see the
## evaluation report); they are not probabilities of real-world correctness.

const Features := preload("res://scripts/ai/features.gd")
const RuleEngine := preload("res://scripts/ai/rule_engine.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")

const FORMAT := "droneacharya-ml-model"
const FORMAT_VERSION := 1
const DEFAULT_PATH := "res://models/track_classifier_v1.json"
const SUPPORTED := ["random_forest", "decision_tree", "logistic_regression"]

var path := ""
var error := ""
var version := ""
var model_type := ""
var classes: Array = []
var metrics: Dictionary = {}
var _loaded := false
var _trees: Array = [] ## {left, right, feature (PackedInt32Array), threshold (PackedFloat64Array), slot (PackedInt32Array), values (Array of PackedFloat64Array)}
var _coef: Array = []
var _intercept := PackedFloat64Array()
var _mean := PackedFloat64Array()
var _scale := PackedFloat64Array()

static var _shared: RefCounted = null


## Process-wide instance loaded from DEFAULT_PATH (loaded once, reused by scenes).
static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://scripts/ai/ml_classifier.gd").new()
		_shared.load_model(DEFAULT_PATH)
	return _shared


func is_loaded() -> bool:
	return _loaded


func load_model(model_path: String) -> bool:
	path = model_path
	_loaded = false
	error = ""
	if not FileAccess.file_exists(model_path):
		return _fail("model file not found: " + model_path)
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(model_path)) != OK:
		return _fail("model file is not valid JSON (line %d)" % json.get_error_line())
	var m = json.data
	if typeof(m) != TYPE_DICTIONARY:
		return _fail("model file must contain a JSON object")
	if m.get("format") != FORMAT or int(m.get("format_version", -1)) != FORMAT_VERSION:
		return _fail("unsupported model format or version")
	if not m.get("model_type") in SUPPORTED:
		return _fail("unsupported model type: %s" % m.get("model_type"))
	if m.get("features_version") != Features.VERSION or m.get("feature_names") != Features.NAMES:
		return _fail("model features do not match the simulator's %s inputs" % Features.VERSION)
	for c in m.get("classes", []):
		if not c in Vocabulary.CATEGORIES:
			return _fail("unknown class in model: %s" % c)
	classes = m["classes"]
	if classes.is_empty():
		return _fail("model has no classes")
	model_type = m["model_type"]
	version = String(m.get("version", "unversioned"))
	var ok := _load_logistic(m) if model_type == "logistic_regression" else _load_trees(m)
	if not ok:
		return false
	var metrics_path := model_path.get_basename() + ".metrics.json"
	if FileAccess.file_exists(metrics_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(metrics_path))
		metrics = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_loaded = true
	return true


func _load_trees(m: Dictionary) -> bool:
	_trees.clear()
	var n_features := Features.NAMES.size()
	for tree in m.get("params", {}).get("trees", []):
		var left := PackedInt32Array(tree.get("left", []))
		var right := PackedInt32Array(tree.get("right", []))
		var feature := PackedInt32Array(tree.get("feature", []))
		var threshold := PackedFloat64Array(tree.get("threshold", []))
		var count := left.size()
		if count == 0 or right.size() != count or feature.size() != count or threshold.size() != count:
			return _fail("malformed tree arrays")
		var slot := PackedInt32Array()
		slot.resize(count)
		slot.fill(-1)
		var values := []
		var leaves: Array = tree.get("leaf_nodes", [])
		var leaf_values: Array = tree.get("leaf_values", [])
		if leaves.size() != leaf_values.size():
			return _fail("malformed tree leaves")
		for i in leaves.size():
			var node := int(leaves[i])
			if node < 0 or node >= count or left[node] != -1 or (leaf_values[i] as Array).size() != classes.size():
				return _fail("malformed tree leaves")
			slot[node] = i
			values.append(PackedFloat64Array(leaf_values[i]))
		for node in count:
			if left[node] != -1 and (left[node] >= count or right[node] >= count or feature[node] < 0 or feature[node] >= n_features):
				return _fail("malformed tree structure")
		_trees.append({"left": left, "right": right, "feature": feature, "threshold": threshold, "slot": slot, "values": values})
	if _trees.is_empty():
		return _fail("model has no trees")
	return true


func _load_logistic(m: Dictionary) -> bool:
	var scaler: Dictionary = m.get("preprocessing", {}).get("scaler", {})
	_mean = PackedFloat64Array(scaler.get("mean", []))
	_scale = PackedFloat64Array(scaler.get("scale", []))
	_intercept = PackedFloat64Array(m.get("params", {}).get("intercept", []))
	_coef.clear()
	for row in m.get("params", {}).get("coef", []):
		_coef.append(PackedFloat64Array(row))
	var n := Features.NAMES.size()
	if _mean.size() != n or _scale.size() != n or _coef.size() != classes.size() or _intercept.size() != classes.size():
		return _fail("malformed logistic-regression parameters")
	for row in _coef:
		if row.size() != n:
			return _fail("malformed logistic-regression parameters")
	return true


func _fail(message: String) -> bool:
	error = message
	_loaded = false
	return false


## Class scores for one feature vector in NAMES order.
func predict_vector(x: PackedFloat64Array) -> PackedFloat64Array:
	var scores := PackedFloat64Array()
	scores.resize(classes.size())
	if model_type == "logistic_regression":
		var logits := PackedFloat64Array()
		var top := -INF
		for k in classes.size():
			var z := _intercept[k]
			for j in x.size():
				z += _coef[k][j] * (x[j] - _mean[j]) / _scale[j]
			logits.append(z)
			top = maxf(top, z)
		var total := 0.0
		for k in classes.size():
			scores[k] = exp(logits[k] - top)
			total += scores[k]
		for k in classes.size():
			scores[k] /= total
		return scores
	# Trees compare float32-rounded inputs, exactly like scikit-learn.
	var x32 := PackedFloat32Array(Array(x))
	for tree in _trees:
		var left: PackedInt32Array = tree["left"]
		var node := 0
		while left[node] != -1:
			node = left[node] if x32[tree["feature"][node]] <= tree["threshold"][node] else tree["right"][node]
		var leaf: PackedFloat64Array = tree["values"][tree["slot"][node]]
		for k in classes.size():
			scores[k] += leaf[k]
	for k in classes.size():
		scores[k] /= _trees.size()
	return scores


## Returns {ok, model, method, category, confidence, probabilities, evidence, latency_us}
## or {ok: false, error}. Only features-1 values are used.
func predict(features: Dictionary) -> Dictionary:
	if not _loaded:
		return {"ok": false, "model": version, "error": error if not error.is_empty() else "model not loaded"}
	for name in Features.NAMES:
		if not features.has(name):
			return {"ok": false, "model": version, "error": "missing feature " + name}
	var started := Time.get_ticks_usec()
	var scores := predict_vector(Features.to_vector(features))
	var best := 0
	for k in scores.size():
		if scores[k] > scores[best]:
			best = k
	var probabilities := {}
	for k in scores.size():
		probabilities[classes[k]] = snappedf(scores[k], 0.0001)
	return {"ok": true, "model": version, "method": "ml (%s)" % model_type, "category": classes[best],
		"confidence": snappedf(scores[best], 0.01), "probabilities": probabilities,
		"evidence": RuleEngine.evidence_quality(features), "latency_us": Time.get_ticks_usec() - started}


func info() -> Dictionary:
	return {"loaded": _loaded, "version": version, "model_type": model_type, "path": path, "error": error,
		"classes": classes, "trees": _trees.size(), "features": Features.VERSION}
