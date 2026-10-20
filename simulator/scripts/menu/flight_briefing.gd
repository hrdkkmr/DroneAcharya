extends Control
## Flight briefing: choose a mission and a drone profile, read the objective, limits,
## hazards and controls, then start. The mission clock only starts after takeoff in
## the flight scene, never on this screen. The last choices are remembered locally.

const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")
const DroneProfiles := preload("res://scripts/flight/drone_profiles.gd")
const FlightMissions := preload("res://scripts/flight/flight_missions.gd")
const ControlsReference := preload("res://scripts/ui/controls_reference.gd")

const ENVIRONMENT_NAMES := {"course": "Training course", "city": "City", "village": "Village"}

var mission_id := FlightMissions.DEFAULT
var profile_id := DroneProfiles.DEFAULT
var mission_buttons := {} ## id -> Button
var profile_buttons := {} ## id -> Button
var briefing_label: RichTextLabel
var start_button: Button
var _mission_group := ButtonGroup.new()
var _profile_group := ButtonGroup.new()


func _ready() -> void:
	UiKit.background(self)
	mission_id = FlightMissions.resolve_id(SettingsStore.get_value("flight_mission"))
	profile_id = DroneProfiles.resolve_id(SettingsStore.get_value("drone_profile"))
	var column := UiKit.screen_column(self, 1500, 14)
	column.add_child(UiKit.header("Flight training", "Mission briefing", "Choose a mission and a drone. The mission clock starts when you take off."))
	var body := UiKit.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var missions := UiKit.vbox(8)
	missions.custom_minimum_size = Vector2(400, 0)
	body.add_child(missions)
	missions.add_child(UiKit.heading("1  Mission"))
	for id in FlightMissions.ORDER:
		var m: Dictionary = FlightMissions.get_mission(id)
		var button := _choice_button("%s\n%s%s" % [m["title"], ENVIRONMENT_NAMES.get(m["environment"], m["environment"]),
			" · hostile area" if m["hostile"] else ""], _mission_group)
		button.toggled.connect(func(on): if on: select_mission(id))
		missions.add_child(button)
		mission_buttons[id] = button

	var drones := UiKit.vbox(8)
	drones.custom_minimum_size = Vector2(440, 0)
	body.add_child(drones)
	drones.add_child(UiKit.heading("2  Drone profile"))
	for id in DroneProfiles.ORDER:
		var p := DroneProfiles.get_profile(id)
		var text := "%s\n%s" % [p["title"], _ratings_text(id)]
		var button := _choice_button(text, _profile_group)
		button.tooltip_text = p["summary"]
		button.toggled.connect(func(on): if on: select_profile(id))
		drones.add_child(button)
		profile_buttons[id] = button

	var brief := UiKit.card()
	brief.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(brief)
	var brief_rows := UiKit.vbox(8)
	brief.add_child(brief_rows)
	brief_rows.add_child(UiKit.heading("3  Briefing"))
	briefing_label = UiKit.rich(16, false)
	briefing_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	briefing_label.custom_minimum_size = Vector2(0, 520)
	brief_rows.add_child(briefing_label)

	var buttons := UiKit.hbox(12)
	buttons.add_child(UiKit.button("Back to menu", AppState.goto.bind(get_tree(), "menu"), 200))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	start_button = UiKit.primary_button("Start mission", start_mission, 260)
	buttons.add_child(start_button)
	column.add_child(buttons)
	mission_buttons[mission_id].button_pressed = true
	profile_buttons[profile_id].button_pressed = true
	_refresh()
	start_button.grab_focus.call_deferred()


func _choice_button(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 72)
	button.add_theme_font_size_override("font_size", 17)
	var pressed := UiKit._button_box("pressed")
	pressed.border_color = UiKit.ACCENT
	pressed.set_border_width_all(2)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	return button


static func _ratings_text(id: String) -> String:
	var parts := PackedStringArray()
	var ratings := DroneProfiles.ratings(id)
	for key in ratings:
		parts.append("%s %s" % [key, "■".repeat(ratings[key]) + "□".repeat(5 - ratings[key])])
	return "   ".join(parts.slice(0, 2)) + "\n" + "   ".join(parts.slice(2))


func select_mission(id: String) -> void:
	mission_id = FlightMissions.resolve_id(id)
	_refresh()


func select_profile(id: String) -> void:
	profile_id = DroneProfiles.resolve_id(id)
	_refresh()


func _refresh() -> void:
	if briefing_label:
		briefing_label.text = briefing_text(mission_id, profile_id)


static func briefing_text(mission: String, profile: String) -> String:
	var m := FlightMissions.get_mission(mission)
	var p := DroneProfiles.get_profile(profile)
	var lines := PackedStringArray()
	lines.append("[font_size=24][b]%s[/b][/font_size]" % m["title"])
	lines.append(m["summary"])
	lines.append("")
	lines.append("[color=#ffc740]Objective[/color]  Fly through every ring in number order, then land in the green landing zone and hold still for 1 s.")
	var limit: float = m["time_limit_s"]
	lines.append("[color=#ffc740]Time limit[/color]  %s" % ("%d:%02d after takeoff (warning at 30 s left)" % [int(limit) / 60, int(limit) % 60] if limit > 0.0 else "none"))
	lines.append("[color=#ffc740]Battery[/color]  about %d:%02d of flight with the %s (climbing uses more)." % [int(p["endurance_s"]) / 60, int(p["endurance_s"]) % 60, p["title"]])
	lines.append("[color=#ffc740]Hazards[/color]  %s" % m["hazards"])
	lines.append("[color=#ffc740]Failure[/color]  Hitting an obstacle hard, leaving the training area, running out of time or battery%s." % (", or losing all airframe integrity to simulated hits" if m["hostile"] else ""))
	lines.append("")
	lines.append("[color=#ffc740]Drone[/color]  [b]%s[/b] — %s" % [p["title"], p["summary"]])
	lines.append("Top speed %.0f m/s · climb %.1f m/s · turn %d°/s" % [p["max_horizontal_speed"], p["max_ascent_speed"], int(p["max_yaw_rate_degrees"])])
	lines.append("")
	lines.append("[color=#ffc740]Controls[/color]")
	for row in ControlsReference.FLIGHT:
		lines.append("  [b]%s[/b]  %s" % [row[0], row[1]])
	lines.append("")
	lines.append("[i]Fictional environment and synthetic hazards for training only.[/i]")
	return "\n".join(lines)


func start_mission() -> void:
	AppState.flight_mission = mission_id
	AppState.flight_profile = profile_id
	SettingsStore.set_value("flight_mission", mission_id)
	SettingsStore.set_value("drone_profile", profile_id)
	SettingsStore.save()
	AppState.goto(get_tree(), "flight")
