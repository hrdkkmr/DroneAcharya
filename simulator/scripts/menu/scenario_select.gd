extends Control
## Scenario selection: preset files or a seeded procedural scenario, with a summary
## of the chosen configuration. Invalid preset files are listed with their errors.

const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const AudioCues := preload("res://scripts/audio/audio_cues.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const PRESET_DIR := "res://scenarios"

var presets: Array = [] ## {path, result}
var current: Dictionary = {}

var _list: ItemList
var _summary: RichTextLabel
var _continue: Button
var _seed: SpinBox
var _difficulty: SpinBox
var _environment: OptionButton
var _time: OptionButton
var _visibility: OptionButton
var _swarm: CheckBox
var _single: CheckBox


func _ready() -> void:
	UiKit.background(self)
	AudioCues.attach(self)
	var root := UiKit.hbox(16)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 32)
	add_child(root)

	var left := UiKit.vbox(10)
	left.custom_minimum_size = Vector2(620, 0)
	root.add_child(left)
	left.add_child(UiKit.label("Scenario selection", 30))
	left.add_child(UiKit.heading("Preset scenarios"))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 200)
	_list.add_theme_font_size_override("font_size", 17)
	_list.item_selected.connect(_on_preset_selected)
	left.add_child(_list)
	left.add_child(UiKit.heading("Seeded procedural scenario"))
	left.add_child(_procedural_form())
	left.add_child(UiKit.button("Generate from seed", _on_generate))

	var right := UiKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	right.add_child(UiKit.heading("Selected scenario"))
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = false
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_font_size_override("normal_font_size", 17)
	right.add_child(_summary)
	var buttons := UiKit.hbox(12)
	buttons.add_child(UiKit.button("Back to menu", AppState.goto.bind(get_tree(), "menu"), 200))
	_continue = UiKit.button("Continue to briefing", _on_continue, 260)
	buttons.add_child(_continue)
	right.add_child(buttons)

	_load_presets()
	if not AppState.selected_config.is_empty():
		_show(AppState.selected_config)
	elif _list.item_count > 0:
		_list.select(0)
		_on_preset_selected(0)


func _procedural_form() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	_seed = SpinBox.new()
	_seed.max_value = 4294967295
	_seed.value = 1001
	_difficulty = SpinBox.new()
	_difficulty.min_value = 1
	_difficulty.max_value = 5
	_difficulty.value = 2
	_environment = _options(["random", "urban", "rural"])
	_time = _options(["random", "day", "night"])
	_visibility = _options(["random", "clear", "haze", "fog"])
	_swarm = CheckBox.new()
	_swarm.text = "Include swarm"
	_single = CheckBox.new()
	_single.text = "Single threat only"
	for pair in [["Seed", _seed], ["Difficulty (1-5)", _difficulty], ["Environment", _environment], ["Time of day", _time], ["Visibility", _visibility]]:
		grid.add_child(UiKit.label(pair[0], 16, UiKit.MUTED))
		grid.add_child(pair[1])
	grid.add_child(_swarm)
	grid.add_child(_single)
	return grid


func _options(values: Array) -> OptionButton:
	var option := OptionButton.new()
	for value in values:
		option.add_item(value)
	return option


func _load_presets() -> void:
	var files := Array(DirAccess.get_files_at(PRESET_DIR))
	files.sort()
	for file in files:
		if not file.ends_with(".json"):
			continue
		var path := PRESET_DIR.path_join(file)
		var result := ScenarioConfig.load_file(path)
		presets.append({"path": path, "result": result})
		var label: String = result["config"].get("title", file) if result["ok"] else "%s (invalid)" % file
		_list.add_item(label)


func _on_preset_selected(index: int) -> void:
	var result: Dictionary = presets[index]["result"]
	if result["ok"]:
		_show(result["config"])
	else:
		current = {}
		_continue.disabled = true
		_summary.text = "[color=#ff6a5a]This scenario file is invalid and cannot be used:[/color]\n• " + "\n• ".join(result["errors"])


func _on_generate() -> void:
	var options := {"difficulty": int(_difficulty.value), "swarm": _swarm.button_pressed, "single": _single.button_pressed}
	for pair in [["environment", _environment], ["time_of_day", _time], ["visibility", _visibility]]:
		var option: OptionButton = pair[1]
		if option.selected > 0:
			options[pair[0]] = option.get_item_text(option.selected)
	var result := ScenarioConfig.generate(int(_seed.value), options)
	_list.deselect_all()
	if result["ok"]:
		_show(result["config"])


func _show(config: Dictionary) -> void:
	current = config
	_continue.disabled = false
	_summary.text = describe(config)


## Human-readable summary. Shows the configuration, not which object is which.
static func describe(c: Dictionary) -> String:
	var total := 0
	for g in c["groups"]:
		total += int(g["count"])
	var degradation: Array = c["sensor"]["degradation"]
	var lines := PackedStringArray([
		"[b][font_size=24]%s[/font_size][/b]" % c["title"],
		c["description"], "",
		"[b]Conditions:[/b] %s · %s · visibility %s · wind %.1f m/s" % [c["environment"], c["time_of_day"], c["visibility"], c["wind"]["speed_mps"]],
		"[b]Difficulty:[/b] %d of 5   [b]Duration:[/b] %d s   [b]Seed:[/b] %d" % [c["difficulty"], c["duration_s"], c["seed"]],
		"[b]Airborne objects:[/b] %d (identity unknown until observed)" % total,
		"[b]Radar:[/b] %s   [b]Camera (EO):[/b] %s" % [
			"%.0f m, %.1f Hz" % [c["sensor"]["radar"]["range_m"], c["sensor"]["radar"]["rate_hz"]] if c["sensor"]["radar"]["enabled"] else "off",
			"%.0f m (identify within %.0f m), %.0f Hz" % [c["sensor"]["eo"]["range_m"], c["sensor"]["eo"]["id_range_m"], c["sensor"]["eo"]["rate_hz"]] if c["sensor"]["eo"]["enabled"] else "off"],
		"[b]Sensor degradation:[/b] %s" % ("%d scheduled window(s)" % degradation.size() if degradation.size() else "none scheduled"),
	])
	return "\n".join(lines)


func _on_continue() -> void:
	if current.is_empty():
		return
	AppState.selected_config = current
	AppState.goto(get_tree(), "briefing")
