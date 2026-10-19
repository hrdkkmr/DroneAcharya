extends Control
## Settings and model information: which decision components exist, how each works
## (rule-based or trained ML), their versions and status, the held-out evaluation
## results shipped with the ML model, and a live inference-latency measurement.

const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")
const RuleEngine := preload("res://scripts/ai/rule_engine.gd")
const DecisionPolicy := preload("res://scripts/ai/decision_policy.gd")
const Features := preload("res://scripts/ai/features.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const PARITY := "res://tests/fixtures/ml_parity_v1.json"

var ml_toggle: CheckBox
var info_label: RichTextLabel
var latency_ms := -1.0


func _ready() -> void:
	UiKit.background(self)
	var column := UiKit.vbox(10)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	add_child(column)
	column.add_child(UiKit.label("Settings & model information", 30))
	ml_toggle = CheckBox.new()
	ml_toggle.text = "Use the trained ML classifier (Model 2) in decision support when it loads"
	ml_toggle.button_pressed = AppState.use_ml
	ml_toggle.toggled.connect(func(on): AppState.use_ml = on)
	column.add_child(ml_toggle)
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_label.add_theme_font_size_override("normal_font_size", 16)
	info_label.add_theme_font_size_override("bold_font_size", 16)
	column.add_child(info_label)
	column.add_child(UiKit.button("Back to menu", AppState.goto.bind(get_tree(), "menu"), 200))
	latency_ms = measure_latency(MlClassifier.shared())
	info_label.text = describe(MlClassifier.shared(), latency_ms)


## Mean inference time per track over the bundled sample rows, or -1 if unavailable.
static func measure_latency(classifier: RefCounted) -> float:
	if not classifier.is_loaded() or not FileAccess.file_exists(PARITY):
		return -1.0
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(PARITY))
	var started := Time.get_ticks_usec()
	for row in fixture["features"]:
		classifier.predict_vector(PackedFloat64Array(row))
	return (Time.get_ticks_usec() - started) / 1000.0 / fixture["features"].size()


static func describe(classifier: RefCounted, latency: float) -> String:
	var lines := PackedStringArray()
	lines.append("[b]Decision components[/b]")
	lines.append("• Model 1 — [b]rule-based[/b] baseline classifier %s (hand-written rules, not machine learning)." % RuleEngine.VERSION)
	if classifier.is_loaded():
		lines.append("• Model 2 — [b]trained ML classifier[/b] %s: %s with %d trees, loaded from %s. Runs locally and offline." % [
			classifier.version, classifier.model_type.replace("_", " "), classifier.info()["trees"], classifier.path])
	else:
		lines.append("• Model 2 — trained ML classifier [color=#ff9a40]NOT LOADED[/color] (%s). Decision support uses the rule-based baseline instead." % classifier.error)
	lines.append("• Model 3 — [b]rule-based[/b] response policy %s, separate from classification." % DecisionPolicy.VERSION)
	lines.append("• Inputs: %s (tracker output and public context only). Assessment rubric: %s." % [Features.VERSION, Rubric.VERSION])
	if latency >= 0.0:
		lines.append("• Measured ML inference time on this computer: %.3f ms per track." % latency)
	var m: Dictionary = classifier.metrics
	if not m.is_empty():
		lines.append("")
		lines.append("[b]Held-out evaluation (synthetic data, unseen scenario seeds)[/b]")
		for split in ["test", "degraded"]:
			var s: Dictionary = m[split]
			lines.append("• %s set (%d samples): ML accuracy %.3f, macro-F1 %.3f · rule-based accuracy %.3f, macro-F1 %.3f · ML calibration error %.3f" % [
				split.capitalize(), s["samples"], s["accuracy"], s["macro_f1"], s["rules_accuracy"], s["rules_macro_f1"], s["ece"]])
		var per_class := PackedStringArray()
		for c in m["per_class_test"]:
			per_class.append("%s %.2f/%.2f" % [c, m["per_class_test"][c]["precision"], m["per_class_test"][c]["recall"]])
		lines.append("• Test precision/recall per class: " + ", ".join(per_class))
	lines.append("")
	lines.append("[b]Limits[/b]")
	lines.append("The classes are the simulator's own fictional behaviour profiles. These results do [b]not[/b] show real-world threat-recognition accuracy.")
	lines.append("ML scores are not calibrated probabilities (calibration error above); the policy uses fixed thresholds.")
	lines.append("Responses are procedural training steps only. See docs/DRONEACHARYA_DATASET_AND_EVALUATION.md.")
	return "\n".join(lines)
