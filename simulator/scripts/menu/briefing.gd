extends Control
## Briefing: what the exercise is, what the trainee can observe, what to do and how
## it is assessed. Shown before every observation exercise.

const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ScenarioSelect := preload("res://scripts/menu/scenario_select.gd")

const WEIGHT_LABELS := {
	"detection": "Detection timeliness", "classification": "Correct classification",
	"evidence": "Evidence-based confidence", "response": "Response appropriateness",
	"response_time": "Response time", "degraded": "Performance in degraded conditions",
}

var text_label: RichTextLabel
var start_button: Button


func _ready() -> void:
	UiKit.background(self)
	var column := UiKit.vbox(12)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	add_child(column)
	column.add_child(UiKit.label("Briefing", 30))
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("normal_font_size", 17)
	column.add_child(text_label)
	var buttons := UiKit.hbox(12)
	buttons.add_child(UiKit.button("Change scenario", AppState.goto.bind(get_tree(), "scenario_select"), 220))
	buttons.add_child(UiKit.button("Main menu", AppState.goto.bind(get_tree(), "menu"), 160))
	start_button = UiKit.button("Start exercise", _start, 220)
	buttons.add_child(start_button)
	column.add_child(buttons)
	if AppState.selected_config.is_empty():
		text_label.text = "No scenario is selected. Choose one on the scenario selection screen."
		start_button.disabled = true
		return
	text_label.text = briefing_text(AppState.selected_config)


static func briefing_text(c: Dictionary) -> String:
	var lines := PackedStringArray([ScenarioSelect.describe(c), ""])
	lines.append("[b]Your task[/b]")
	lines.append("You are at a fictional observation post. The circle on the ground is the protected area (radius %.0f m)." % c["protected_zone_radius_m"])
	lines.append("1. Watch the sensor track list and the camera view; select tracks as they appear.")
	lines.append("2. Mark a track as acknowledged as soon as you notice it (detection timeliness).")
	lines.append("3. Classify it: bird, drifting balloon, authorised UAV, unidentified UAV, coordinated swarm, or unknown.")
	lines.append("4. Choose a procedural response: continue observing, request identification, log, notify supervisor, or training-area alert.")
	lines.append("Classify with the evidence you have. 'Unknown' with honest low confidence is better than a confident guess.")
	lines.append("")
	lines.append("[b]Available observations (synthetic)[/b]")
	lines.append("• Radar-like sensor: position estimates with range noise, periodic updates, missed detections and delays. Works at night.")
	lines.append("• Camera (EO): precise bearing and an apparent-size estimate when in range; identification quality only within its identification range. Reduced at night and in haze or fog.")
	lines.append("• Some contacts send a fictional cooperative ID reply. Clutter can create false tracks. Degradation windows lower quality further.")
	lines.append("")
	lines.append("[b]Assessment (weights)[/b]")
	for key in WEIGHT_LABELS:
		lines.append("• %s: %d" % [WEIGHT_LABELS[key], int(c["weights"][key])])
	lines.append("Penalties: over-confident claims without evidence, false alarms, missed threats and repeated action spam.")
	lines.append("")
	lines.append("[b]Controls[/b]  Right mouse drag: look · Mouse wheel: zoom · V: eye / sensor view · Tab: next track · Esc: pause · R: restart")
	lines.append("[i]Synthetic training only. Objects, sensors and AI outputs are simulated and are not real-world capabilities.[/i]")
	return "\n".join(lines)


func _start() -> void:
	AppState.replay_requested = false
	AppState.goto(get_tree(), "observation")
