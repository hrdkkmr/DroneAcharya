extends "res://tests/test_case.gd"
## Menu navigation, scenario selection, briefing and the observation scene.

const AppState := preload("res://scripts/app/app_state.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")


func _wait_scene(path: String) -> Node:
	for i in 10:
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene.scene_file_path == path:
			return tree.current_scene
	failures.append("scene did not change to " + path)
	return null


func _select(path: String) -> Dictionary:
	var config: Dictionary = ScenarioConfig.load_file(path)["config"]
	AppState.selected_config = config
	return config


func test_main_menu_lists_all_modes_and_opens_flight_training() -> void:
	AppState.selected_config = {}
	var menu := add_scene("res://scenes/main.tscn")
	await tree.process_frame
	for key in ["flight", "briefing", "scenario_select", "history", "settings"]:
		assert_true(menu.buttons.has(key), "menu has an entry for " + key)
	assert_true(not menu.buttons["flight"].disabled, "flight training enabled")
	menu.buttons["flight"].pressed.emit()
	var flight := await _wait_scene(AppState.SCENES["flight"])
	assert_true(flight != null and flight.get_node_or_null("Drone") != null, "flight scene with drone loaded")


func test_threat_observation_uses_default_scenario_when_none_selected() -> void:
	AppState.selected_config = {}
	var menu := add_scene("res://scenes/main.tscn")
	await tree.process_frame
	menu.buttons["briefing"].pressed.emit()
	var briefing := await _wait_scene(AppState.SCENES["briefing"])
	assert_eq(AppState.selected_config.get("id"), "single-rural-day", "default scenario selected")
	assert_true(briefing != null and not briefing.start_button.disabled, "briefing can start")


func test_scenario_selection_presets_procedural_and_continue() -> void:
	AppState.selected_config = {}
	AppState.goto(tree, "scenario_select")
	var screen := await _wait_scene(AppState.SCENES["scenario_select"])
	assert_eq(screen.presets.size(), 4, "four presets listed")
	screen._list.select(1)
	screen._on_preset_selected(1)
	assert_eq(screen.current["id"], "swarm-urban-day", "second preset selected")
	screen._seed.value = 4242
	screen._difficulty.value = 4
	screen._swarm.button_pressed = true
	screen._on_generate()
	assert_eq(screen.current["id"], "procedural-4242", "procedural scenario generated")
	assert_eq(screen.current["difficulty"], 4, "difficulty applied")
	screen._on_continue()
	var briefing := await _wait_scene(AppState.SCENES["briefing"])
	assert_eq(AppState.selected_config["id"], "procedural-4242", "selection carried to briefing")
	var text: String = briefing.text_label.text
	for fragment in ["Assessment (weights)", "Radar", "protected area", "Synthetic training only", "Seed:[/b] 4242"]:
		assert_true(fragment in text, "briefing mentions " + fragment)


func test_briefing_without_selection_cannot_start() -> void:
	AppState.selected_config = {}
	AppState.goto(tree, "briefing")
	var briefing := await _wait_scene(AppState.SCENES["briefing"])
	assert_true(briefing.start_button.disabled, "start disabled without a scenario")


func test_observation_scene_runs_pauses_and_restarts() -> void:
	_select("res://scenarios/02_swarm_urban_day.json")
	AppState.goto(tree, "observation")
	var scene := await _wait_scene(AppState.SCENES["observation"])
	assert_true(scene.get_node("Title").text.begins_with("DroneAcharya"), "safety title shown")
	assert_eq(scene.session.status, ThreatSession.Status.RUNNING, "exercise running")
	await wait_physics_frames(60 * 15)
	var tick: int = scene.session.tick()
	assert_true(tick >= 290 and tick <= 310, "about 15 s simulated at 20 Hz (tick %d)" % tick)
	var visible := 0
	for id in scene._visuals:
		visible += int(scene._visuals[id].visible)
	assert_eq(visible, scene.session.world.active_ids().size(), "one visible model per active actor")
	assert_true(visible > 0, "actors spawned and visible")
	scene.toggle_pause()
	await wait_physics_frames(30)
	assert_eq(scene.session.tick(), tick, "simulation frozen while paused")
	assert_true(scene._overlay.visible, "pause overlay")
	scene.toggle_pause()
	var layout: Dictionary = scene.session.definition["layout"]
	scene.start_session()
	assert_eq(scene.session.tick(), 0, "restart begins at tick 0")
	assert_eq(scene.session.definition["layout"], layout, "restart keeps the same seeded layout")


func test_environment_variants_change_lighting_fog_and_props() -> void:
	_select("res://scenarios/03_mixed_rural_night_degraded.json")
	AppState.goto(tree, "observation")
	var night := await _wait_scene(AppState.SCENES["observation"])
	assert_true(night.world_root.has_node("Moon"), "night uses moonlight")
	assert_true(night.world_root.has_node("Trees"), "rural scenario has trees")
	_select("res://scenarios/04_single_urban_fog.json")
	AppState.goto(tree, "observation")
	var fog := await _wait_scene(AppState.SCENES["observation"])
	assert_true(fog.world_root.has_node("Sun"), "day uses sunlight")
	assert_true(fog.world_root.has_node("Buildings") and not fog.world_root.has_node("Trees"), "urban scenario has buildings only")
	var env: Environment = fog.world_root.get_node("WorldEnvironment").environment
	assert_true(env.fog_density >= 0.01, "fog visibility increases fog density (%.4f)" % env.fog_density)


func test_exit_to_menu_aborts_the_session() -> void:
	_select("res://scenarios/01_single_rural_day.json")
	AppState.goto(tree, "observation")
	var scene := await _wait_scene(AppState.SCENES["observation"])
	var session = scene.session
	scene.exit_to_menu()
	await _wait_scene(AppState.SCENES["menu"])
	assert_eq(session.status, ThreatSession.Status.ABORTED, "session aborted on exit")
