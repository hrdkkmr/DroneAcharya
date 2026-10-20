extends "res://tests/test_case.gd"
## Phase 1 of the UX overhaul: landing page, pause menus, back navigation, settings
## persistence and on-demand controls.

const AppState := preload("res://scripts/app/app_state.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")


func _wait_scene(path: String) -> Node:
	for i in 10:
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene.scene_file_path == path:
			return tree.current_scene
	failures.append("scene did not change to " + path)
	return null


func _press_action(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await tree.process_frame
	await tree.process_frame


func _all_text(node: Node) -> String:
	var text := ""
	if node is Label and node.is_visible_in_tree():
		text += node.text + "\n"
	for child in node.get_children():
		text += _all_text(child)
	return text


func test_landing_page_has_branding_modes_and_exit() -> void:
	var menu := add_scene("res://scenes/main.tscn")
	await tree.process_frame
	assert_true(menu.get_node_or_null("Title") != null, "safety caption kept")
	var text := _all_text(menu)
	assert_true("DRONEACHARYA" in text, "brand wordmark shown")
	assert_true("Synthetic training environment".to_upper() in text, "subtitle explains the synthetic environment")
	for key in ["flight", "briefing", "history", "settings", "quit", "scenario_select"]:
		assert_true(menu.buttons.has(key), "entry " + key)
	assert_true("Threat Detection Training" in text and "Training History & Reports" in text, "mode names")
	assert_true(tree.auto_accept_quit, "closing the window quits normally")


func test_flight_pause_menu_resumes_restarts_and_returns_to_menu() -> void:
	AppState.goto(tree, "flight")
	var flight := await _wait_scene(AppState.SCENES["flight"])
	var hud = flight.hud
	assert_true(hud.get_node_or_null("Controls") == null, "no permanent controls panel")
	assert_true(not ("Space / C" in _all_text(hud)), "control keys not listed during flight")
	await _press_action("pause")
	assert_true(tree.paused and hud.overlay.visible, "Esc opens the pause menu")
	for id in ["resume", "restart", "controls", "settings", "menu"]:
		assert_true(hud.overlay.buttons.has(id), "pause menu offers " + id)
	hud.overlay.press("controls")
	assert_true(hud.overlay.controls_box.visible, "Controls section opens")
	assert_true("Space / C" in _all_text(hud.overlay.controls_box), "controls listed on demand")
	hud.overlay.press("settings")
	assert_true(hud.overlay.settings_box.visible and not hud.overlay.controls_box.visible, "Settings section replaces Controls")
	hud.overlay.press("resume")
	assert_true(not tree.paused and not hud.overlay.visible, "Resume closes the menu and unpauses")
	await _press_action("pause")
	hud.overlay.press("menu")
	var menu := await _wait_scene(AppState.SCENES["menu"])
	assert_true(menu != null and not tree.paused, "Back to menu returns to the landing page, unpaused")
	assert_true(not is_instance_valid(flight), "flight scene (mission, drone, timers) released")


func test_in_game_buttons_do_not_steal_gameplay_keys() -> void:
	AppState.goto(tree, "flight")
	var flight := await _wait_scene(AppState.SCENES["flight"])
	await _press_action("pause")
	flight.hud.overlay.press("resume")
	await tree.process_frame
	assert_true(flight.get_viewport().gui_get_focus_owner() == null, "no button keeps focus after the menu closes")


func test_observation_pause_menu_and_exit_abort_the_exercise() -> void:
	AppState.selected_config = ScenarioConfig.load_file("res://scenarios/01_single_rural_day.json")["config"]
	AppState.goto(tree, "observation")
	var scene := await _wait_scene(AppState.SCENES["observation"])
	scene.toggle_pause()
	assert_true(tree.paused and scene.hud.overlay.visible, "pause menu open")
	for id in ["resume", "restart", "controls", "settings", "menu"]:
		assert_true(scene.hud.overlay.buttons.has(id), "observation pause offers " + id)
	assert_true(not scene.hud.review_button.visible, "no report button while paused")
	var session = scene.session
	scene.hud.overlay.press("menu")
	await _wait_scene(AppState.SCENES["menu"])
	assert_eq(session.status, ThreatSession.Status.ABORTED, "exit aborts the running exercise")
	assert_true(not tree.paused, "menu is not paused")


func test_settings_persist_and_are_clamped() -> void:
	var original := SettingsStore.path
	SettingsStore.path = "user://test_runs/settings_roundtrip.cfg"
	DirAccess.remove_absolute(SettingsStore.path)
	SettingsStore.load_settings()
	assert_eq(SettingsStore.get_value("master_volume"), SettingsStore.DEFAULTS["master_volume"], "defaults without a file")
	SettingsStore.set_value("master_volume", 0.3)
	SettingsStore.set_value("sfx_volume", 7.0)
	SettingsStore.set_value("mouse_sensitivity", 1.5)
	SettingsStore.set_value("quality", "ultra")
	SettingsStore.set_value("tutorial_done", true)
	assert_true(SettingsStore.save(), "saved")
	SettingsStore.values = SettingsStore.DEFAULTS.duplicate()
	assert_true(SettingsStore.load_settings(), "reloaded")
	assert_near(SettingsStore.get_value("master_volume"), 0.3, 0.0001, "master volume survives a restart")
	assert_near(SettingsStore.get_value("sfx_volume"), 1.0, 0.0001, "out-of-range volume clamped")
	assert_near(SettingsStore.get_value("mouse_sensitivity"), 1.5, 0.0001, "sensitivity survives")
	assert_eq(SettingsStore.get_value("quality"), "standard", "unknown quality falls back")
	assert_eq(SettingsStore.get_value("tutorial_done"), true, "tutorial completion survives")
	var master := AudioServer.get_bus_index("Master")
	assert_near(db_to_linear(AudioServer.get_bus_volume_db(master)), 0.3, 0.001, "master bus volume applied")
	assert_true(AudioServer.get_bus_index("SFX") != -1 and AudioServer.get_bus_index("Ambience") != -1, "SFX and Ambience buses exist")
	SettingsStore.set_value("muted", true)
	assert_true(AudioServer.is_bus_mute(master), "mute applied to the master bus")
	DirAccess.remove_absolute(SettingsStore.path)
	SettingsStore.path = original
	SettingsStore.load_settings()


func test_settings_screen_changes_and_saves_values() -> void:
	AppState.goto(tree, "settings")
	var screen := await _wait_scene(AppState.SCENES["settings"])
	var panel = screen.settings_panel
	panel.sliders["sfx_volume"].value = 0.25
	assert_near(SettingsStore.get_value("sfx_volume"), 0.25, 0.0001, "slider changes the setting")
	var file := ConfigFile.new()
	assert_eq(file.load(SettingsStore.path), OK, "settings file written")
	assert_near(float(file.get_value("settings", "sfx_volume")), 0.25, 0.0001, "saved value")
	panel.reset_defaults()
	assert_near(SettingsStore.get_value("sfx_volume"), SettingsStore.DEFAULTS["sfx_volume"], 0.0001, "reset to defaults")
	assert_near(panel.sliders["sfx_volume"].value, SettingsStore.DEFAULTS["sfx_volume"], 0.0001, "slider shows the reset value")


func test_mouse_buttons_are_not_bound_to_keyboard_actions() -> void:
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			assert_true(not event is InputEventMouseButton, "'%s' has no mouse-button binding (mouse is handled per screen)" % action)
