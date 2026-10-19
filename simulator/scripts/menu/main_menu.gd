extends Control
## Main menu: entry point for every training mode.

const TITLE := "DroneAcharya — synthetic training only"
const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

## Entries: [button text, scene key, description]. A scene key whose file does not
## exist yet is shown disabled rather than leading to an empty screen.
const ENTRIES := [
	["Flight Training", "flight", "Fly the training drone through the four-ring course and land."],
	["Threat Observation", "briefing", "Start the selected (or default) observation scenario."],
	["Scenario Selection", "scenario_select", "Choose a preset or generate a seeded scenario."],
	["Training History & After-Action Review", "history", "Review, replay, export and import past sessions."],
	["Settings & Model Information", "settings", "Decision models, versions and evaluation results."],
]
const DEFAULT_SCENARIO := "res://scenarios/01_single_rural_day.json"

var buttons := {}


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var title: Label = $Title
	title.text = TITLE
	UiKit.background(self)
	move_child(title, get_child_count() - 1)
	var column := UiKit.vbox(12)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.custom_minimum_size = Vector2(560, 0)
	column.position = Vector2(-280, -150)
	add_child(column)
	column.add_child(UiKit.label("AI-enabled drone and counter-drone threat simulation trainer (prototype)", 18, UiKit.MUTED))
	for entry in ENTRIES:
		var button := UiKit.button(entry[0], _open.bind(entry[1]), 560)
		button.tooltip_text = entry[2]
		var path: String = AppState.SCENES[entry[1]]
		if not ResourceLoader.exists(path):
			button.disabled = true
			button.tooltip_text += " (added in a later phase)"
		column.add_child(button)
		buttons[entry[1]] = button
	column.add_child(UiKit.button("Quit", get_tree().quit, 560))
	column.add_child(UiKit.label("Fictional environments and synthetic actors. Not an operational system.", 14, UiKit.MUTED))


func _open(scene: String) -> void:
	if scene == "briefing" and AppState.selected_config.is_empty():
		var ScenarioConfig := load("res://scripts/sim/scenario_config.gd")
		var result: Dictionary = ScenarioConfig.load_file(DEFAULT_SCENARIO)
		if result["ok"]:
			AppState.selected_config = result["config"]
	AppState.goto(get_tree(), scene)
