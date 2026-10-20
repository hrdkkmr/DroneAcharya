extends Control
## Briefing: what the exercise is, what the trainee can observe, what to do and how
## it is assessed. Shown before every observation exercise.

const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const AudioCues := preload("res://scripts/audio/audio_cues.gd")
const ScenarioSelect := preload("res://scripts/menu/scenario_select.gd")
const ControlsReference := preload("res://scripts/ui/controls_reference.gd")

const WEIGHT_LABELS := {
	"detection": "Detection timeliness", "classification": "Correct classification",
	"evidence": "Evidence-based confidence", "response": "Response appropriateness",
	"response_time": "Response time", "degraded": "Performance in degraded conditions",
}

var text_label: RichTextLabel
var start_button: Button


func _ready() -> void:
	UiKit.background(self)
	AudioCues.attach(self)
	var column := UiKit.screen_column(self, 1500, 12)
	column.add_child(UiKit.header("Threat detection training", "Briefing", "Read the situation, then start. The exercise clock starts when you press Start."))
	var body := UiKit.hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	text_label = UiKit.rich(17, false)
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text_label)
	var side := UiKit.card()
	side.custom_minimum_size = Vector2(520, 0)
	side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(side)
	var side_rows := UiKit.vbox(6)
	side.add_child(side_rows)
	side_rows.add_child(UiKit.heading("Controls"))
	for row in ControlsReference.OBSERVATION:
		side_rows.add_child(UiKit.key_line(row[0], row[1]))
	side_rows.add_child(UiKit.spacer(6))
	side_rows.add_child(UiKit.button("Replay the tutorial", AppState.goto.bind(get_tree(), "tutorial"), 260))
	var buttons := UiKit.hbox(12)
	buttons.add_child(UiKit.button("Main menu", AppState.goto.bind(get_tree(), "menu"), 160))
	buttons.add_child(UiKit.button("Change scenario", AppState.goto.bind(get_tree(), "scenario_select"), 220))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	start_button = UiKit.primary_button("Start exercise", _start, 240)
	buttons.add_child(start_button)
	column.add_child(buttons)
	if AppState.selected_config.is_empty():
		text_label.text = "No scenario is selected. Choose one on the scenario selection screen."
		start_button.disabled = true
		return
	text_label.text = briefing_text(AppState.selected_config)
	start_button.grab_focus.call_deferred()


static func briefing_text(c: Dictionary) -> String:
	var lines := PackedStringArray([ScenarioSelect.describe(c), ""])
	lines.append("[b]Your task[/b]")
	lines.append("You are at a fictional observation post. The circle on the ground is the protected area (radius %.0f m)." % c["protected_zone_radius_m"])
	lines.append("1. Select each new contact as soon as you notice it: click its marker, its radar symbol or its row (detection timeliness).")
	lines.append("2. Classify it with the mouse wheel and right-click: bird, drifting balloon, authorised UAV, unidentified UAV, coordinated swarm, or unknown.")
	lines.append("3. Choose a procedural response the same way: continue observing, request identification, log, notify supervisor, or training-area alert. Alarms ask you to confirm once more.")
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
	lines.append("[i]Synthetic training only. Objects, sensors and AI outputs are simulated and are not real-world capabilities.[/i]")
	return "\n".join(lines)


func _start() -> void:
	AppState.replay_requested = false
	AppState.goto(get_tree(), "observation")
