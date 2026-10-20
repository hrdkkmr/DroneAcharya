extends Control
## Full-screen tutorial shown before the first threat-detection exercise (and from
## the main menu). Finishing or skipping marks it done; then the briefing opens.

const AppState := preload("res://scripts/app/app_state.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")
const TutorialPanel := preload("res://scripts/menu/tutorial_panel.gd")
const DEFAULT_SCENARIO := "res://scenarios/01_single_rural_day.json"

var panel: TutorialPanel


func _ready() -> void:
	get_tree().paused = false
	load("res://scripts/audio/audio_cues.gd").attach(self)
	panel = TutorialPanel.new()
	add_child(panel)
	panel.finished.connect(_on_finished)


func _on_finished(_skipped: bool) -> void:
	SettingsStore.set_value("tutorial_done", true)
	SettingsStore.save()
	if AppState.selected_config.is_empty():
		var result: Dictionary = load("res://scripts/sim/scenario_config.gd").load_file(DEFAULT_SCENARIO)
		if result["ok"]:
			AppState.selected_config = result["config"]
	AppState.goto(get_tree(), "briefing")
