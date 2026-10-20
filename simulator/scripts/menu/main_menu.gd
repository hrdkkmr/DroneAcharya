extends Control
## Landing page: DroneAcharya branding on the left, the training modes on the right.
## The `Title` node (a short safety caption) is kept from Stage 0; the smoke test
## checks its text.

const TITLE := "DroneAcharya — synthetic training only"
const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const AudioCues := preload("res://scripts/audio/audio_cues.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")

## Main entries: [scene key, title, description]. A scene whose file does not exist
## is shown disabled rather than leading to an empty screen.
const ENTRIES := [
	["flight_briefing", "Flight Training", "Fly a training drone through course, city or village missions. Choose a drone profile and reach the landing zone in time."],
	["briefing", "Threat Detection Training", "Watch the synthetic sensors, inspect contacts, classify them and choose a procedural response."],
	["history", "Training History & Reports", "Plain-language reports of past missions and exercises, replay, export and import."],
	["settings", "Settings", "Volume, mouse sensitivity, effects quality and decision-model information."],
]
## Smaller links under the main entries: [scene key, text].
const LINKS := [
	["scenario_select", "Choose a threat scenario…"],
	["tutorial", "Threat detection tutorial"],
]
const DEFAULT_SCENARIO := "res://scenarios/01_single_rural_day.json"

var buttons := {}


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SettingsStore.apply()
	UiKit.install_symbol_font()
	UiKit.background(self)
	AudioCues.attach(self)
	var title: Label = $Title
	title.text = TITLE
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UiKit.MUTED)
	title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	title.offset_top = -40
	title.offset_bottom = -16
	move_child(title, get_child_count() - 1)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	add_child(margin)
	var body := UiKit.hbox(64)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(body)

	var brand := UiKit.vbox(10)
	brand.custom_minimum_size = Vector2(560, 0)
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(brand)
	brand.add_child(UiKit.heading("Synthetic training environment", 15))
	var wordmark := UiKit.label("DRONEACHARYA", 64, Color.WHITE)
	wordmark.name = "Wordmark"
	brand.add_child(wordmark)
	var bar := ColorRect.new()
	bar.color = UiKit.ACCENT
	bar.custom_minimum_size = Vector2(120, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.add_child(bar)
	brand.add_child(UiKit.label("Drone flight and counter-drone threat-recognition trainer", 22, UiKit.TEXT, true))
	brand.add_child(UiKit.label("Every place, contact and sensor here is simulated. Responses are procedural training steps only. This is a training prototype, not an operational system.", 16, UiKit.MUTED, true))

	var column := UiKit.vbox(12)
	column.custom_minimum_size = Vector2(560, 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(column)
	for entry in ENTRIES:
		column.add_child(_entry(entry[0], entry[1], entry[2]))
	var links := UiKit.hbox(12)
	for link in LINKS:
		var button := _register(link[0], UiKit.button(link[1], _open.bind(link[0])))
		button.add_theme_font_size_override("font_size", 16)
		links.add_child(button)
	column.add_child(links)
	var quit := UiKit.button("Exit", get_tree().quit, 160)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	buttons["quit"] = quit
	# Quitting inside a browser tab would only freeze the page; the tab is closed instead.
	quit.visible = not OS.has_feature("web")
	column.add_child(quit)
	buttons["flight"] = buttons["flight_briefing"]
	buttons["flight"].grab_focus.call_deferred()


## A large two-line button: mode name and one sentence about it.
func _entry(key: String, title: String, description: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(560, 100)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_open.bind(key))
	button.pressed.connect(AudioCues.play_global.bind("ui_click"))
	button.tooltip_text = description
	var rows := UiKit.vbox(2)
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiKit.label(title, 22, Color.WHITE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := UiKit.label(description, 15, UiKit.MUTED, true)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.custom_minimum_size = Vector2(520, 0)
	rows.add_child(name_label)
	rows.add_child(text)
	button.add_child(rows)
	return _register(key, button)


func _register(key: String, button: Button) -> Button:
	var path: String = AppState.SCENES.get(key, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		button.disabled = true
		button.tooltip_text += " (not available in this build)"
	buttons[key] = button
	return button


func _open(scene: String) -> void:
	# First time in threat detection: the tutorial comes first, then the briefing.
	if scene == "briefing" and not SettingsStore.get_value("tutorial_done"):
		scene = "tutorial"
	if scene == "briefing" and AppState.selected_config.is_empty():
		var ScenarioConfig := load("res://scripts/sim/scenario_config.gd")
		var result: Dictionary = ScenarioConfig.load_file(DEFAULT_SCENARIO)
		if result["ok"]:
			AppState.selected_config = result["config"]
	AppState.goto(get_tree(), scene)
