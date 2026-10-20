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
	# Flight training now opens its briefing (mission and drone choice) first.
	var briefing := await _wait_scene(AppState.SCENES["flight_briefing"])
	assert_true(briefing != null, "flight briefing shown before flying")
	briefing.start_mission()
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
	assert_true(scene.hud.overlay.visible, "pause overlay")
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


## Opens the observation scene and advances its session to `seconds` by stepping the
## simulation directly (no real-time wait; rendering is not needed for these checks).
func _start_observation(path: String, seconds: float) -> Node:
	_select(path)
	AppState.goto(tree, "observation")
	var scene: Node = await _wait_scene(AppState.SCENES["observation"])
	while scene.session.time_s() < seconds:
		scene.session.step()
	await tree.process_frame
	return scene


func test_sensor_view_toggle_changes_view_and_uses_thermal_at_night() -> void:
	var day := await _start_observation("res://scenarios/01_single_rural_day.json", 1.0)
	var press := InputEventAction.new()
	press.action = "toggle_view"
	press.pressed = true
	Input.parse_input_event(press)
	await tree.process_frame
	await tree.process_frame
	assert_true(day.sensor_view and day.hud.sensor_shade.visible, "V switches to the sensor view")
	assert_true(day.observer.fov <= 30.0, "sensor view is zoomed (%.1f°)" % day.observer.fov)
	assert_true("TV" in day.view_text(), "daylight sensor is TV mode")
	day.set_sensor_view(false)
	assert_true(day.observer.fov >= 50.0 and not day.hud.sensor_shade.visible, "back to eye view")
	var night := await _start_observation("res://scenarios/03_mixed_rural_night_degraded.json", 1.0)
	night.set_sensor_view(true)
	assert_true("thermal" in night.view_text(), "night sensor is thermal mode")
	for id in night._visuals:
		assert_true(night._visuals[id].thermal, "%s drawn as heat signature" % id)


func test_track_ui_shows_only_tracker_output() -> void:
	var scene := await _start_observation("res://scenarios/02_swarm_urban_day.json", 60.0)
	var tracks: Array = scene.session.tracker.confirmed_tracks()
	assert_true(tracks.size() >= 2, "tracks available after 60 s (%d)" % tracks.size())
	scene.cycle_track()
	assert_eq(scene.selected_track, tracks[0]["id"], "Tab selects the first track")
	scene.cycle_track()
	assert_eq(scene.selected_track, tracks[1]["id"], "Tab moves to the next track")
	scene.centre_on_selected()
	scene.overlay.update_markers()
	assert_true(scene.overlay.markers.size() > 0, "markers computed")
	for id in scene.overlay._screen_positions:
		assert_true(scene.session.tracker.tracks.has(id), "marker %s belongs to a tracker track" % id)
	assert_true(scene.overlay._screen_positions.has(scene.selected_track), "centred track has a marker on screen")
	scene.hud.refresh(scene.session, scene.selected_track, scene.view_text(), 1.0)
	var visible_text: String = scene.hud.details_label.text + scene.hud.sensor_label.text
	for forbidden in ["unidentified_uav", "authorised_uav", "swarm_uav", "balloon", "truth", "A01", "G01"]:
		assert_true(not forbidden in visible_text, "HUD does not reveal '%s'" % forbidden)


func test_details_explain_coasting_and_lost_tracks() -> void:
	var scene := await _start_observation("res://scenarios/01_single_rural_day.json", 30.0)
	var track: Dictionary = scene.session.tracker.confirmed_tracks()[0]
	track["status"] = "coasting"
	track["last_update_t"] = scene.session.time_s() - 4.0
	var text: String = scene.hud.track_details(scene.session, track["id"])
	assert_true("extrapolated, not observed" in text, "coasting track explained")
	scene.session.tracker._retire(track, "lost", scene.session.time_s())
	assert_true("lost at" in scene.hud.track_details(scene.session, track["id"]), "lost track explained")


func test_classification_workflow_through_the_scene_and_scoring_at_the_end() -> void:
	var scene := await _start_observation("res://scenarios/01_single_rural_day.json", 30.0)
	scene.cycle_track()
	var id: String = scene.selected_track
	assert_true(not id.is_empty(), "a track is selected")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	Input.parse_input_event(key)
	await tree.process_frame
	await tree.process_frame
	assert_true(scene.session.trainee_state(id).get("acknowledged_t", -1.0) >= 0.0, "F acknowledges the selected track")
	scene.hud.classify_requested.emit("unidentified_uav", 60)
	scene.hud.respond_requested.emit("notify_supervisor")
	var state: Dictionary = scene.session.trainee_state(id)
	assert_eq([state["category"], state["response"]], ["unidentified_uav", "notify_supervisor"], "classification and response recorded")
	scene.hud.refresh(scene.session, id, scene.view_text(), 1.0)
	assert_true("Rule-based baseline (not ML)" in scene.hud.support_label.text, "decision support labelled by method")
	assert_true("Recommended:" in scene.hud.support_label.text, "recommendation shown with a reason")
	scene.hud.support_toggle.button_pressed = false
	assert_true(scene.session.events.any(func(e): return e["type"] == "decision_support_visible"), "hiding decision support is logged")
	while not scene.session.is_finished():
		scene.session.step()
	await tree.process_frame
	await tree.process_frame
	assert_true(not scene.evaluation.is_empty(), "session scored at the end")
	assert_true(scene.hud.overlay.visible and "Score" in scene.hud.overlay_detail.text, "score shown")
	assert_eq(scene.record["evaluation"]["rubric"], "da-rubric-1", "record carries the evaluation")


func test_settings_screen_reports_models_and_toggles_ml() -> void:
	var menu := add_scene("res://scenes/main.tscn")
	await tree.process_frame
	assert_true(not menu.buttons["settings"].disabled, "settings entry enabled")
	menu.buttons["settings"].pressed.emit()
	var screen := await _wait_scene(AppState.SCENES["settings"])
	var text: String = screen.info_label.text
	for fragment in ["rule-based", "trained ML classifier", "track-classifier-v1", "Held-out evaluation", "not", "calibrat"]:
		assert_true(fragment in text, "model information mentions '%s'" % fragment)
	assert_true(screen.latency_ms > 0.0, "inference latency measured (%.3f ms)" % screen.latency_ms)
	screen.ml_toggle.button_pressed = false
	assert_true(not AppState.use_ml, "ML can be switched off")
	_select("res://scenarios/01_single_rural_day.json")
	AppState.goto(tree, "observation")
	var scene := await _wait_scene(AppState.SCENES["observation"])
	assert_true(not scene.session.decisions.ml_active(), "observation runs rules-only when ML is off")
	AppState.use_ml = true


func test_exercise_to_review_to_3d_replay_and_back() -> void:
	var dir: String = AppState.sessions_dir
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	var scene := await _start_observation("res://scenarios/01_single_rural_day.json", 25.0)
	scene.set_truth_labels(true)
	assert_true(scene.overlay.truth_labels.is_empty(), "no truth labels during a live exercise")
	scene.cycle_track()
	scene.acknowledge_selected()
	scene.classify_selected("unknown", 30)
	scene.respond_selected("request_identification")
	while not scene.session.is_finished():
		scene.session.step()
	await tree.process_frame
	await tree.process_frame
	assert_true(scene.saved_path.begins_with(dir), "session saved to the history folder: " + scene.saved_path)
	assert_true(scene.hud.review_button.visible, "review button offered")
	var session_id: String = scene.record["session_id"]
	scene.hud.review_requested.emit()
	var history := await _wait_scene(AppState.SCENES["history"])
	assert_eq(history.sessions.size(), 1, "one session in history")
	assert_eq(history.selected["session_id"], session_id, "the finished session is selected")
	assert_true("/ 100" in history.report_label.text and "Decision timeline" in history.report_label.text, "review shown")
	assert_true(history.verify_replay()["identical"], "replay verified from the saved file")
	assert_true("Replay verified" in history.status_label.text, "verification reported")
	var exported: Dictionary = history.export_selected()
	assert_true(exported["ok"], "exported")
	var imported: Dictionary = history.import_file(exported["path"])
	assert_eq([imported["ok"], imported["skipped"]], [true, 1], "re-importing the same session is a harmless duplicate")
	history.replay_in_3d()
	var replay_scene := await _wait_scene(AppState.SCENES["observation"])
	assert_true(replay_scene.replay != null, "observation scene in replay mode")
	assert_true(replay_scene.hud.replay_bar.visible and not replay_scene.hud.decision_panel.visible, "replay controls shown, decision controls hidden")
	await wait_physics_frames(60)
	assert_true(replay_scene.session.tick() > 0, "replay advancing")
	replay_scene.seek_replay(20 * 30)
	assert_eq(replay_scene.session.tick(), 600, "seek forward")
	replay_scene.seek_replay(100)
	assert_eq(replay_scene.session.tick(), 100, "seek backwards re-simulates from the start")
	replay_scene.seek_replay(20 * 30)
	replay_scene.set_truth_labels(true)
	var labels: Array = replay_scene.overlay.truth_labels
	assert_true(labels.any(func(l): return "A01" in l["text"] and "Unidentified UAV" in l["text"]), "truth labels available in replay")
	var before: int = replay_scene.session.spam_count
	replay_scene.acknowledge_selected()
	assert_eq(replay_scene.session.spam_count, before, "trainee actions ignored during replay")
	replay_scene.exit_to_menu()
	await _wait_scene(AppState.SCENES["history"])


func test_history_recommends_and_starts_the_next_exercise() -> void:
	var dir: String = AppState.sessions_dir
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	AppState.review_session = {}
	AppState.goto(tree, "history")
	var history := await _wait_scene(AppState.SCENES["history"])
	assert_eq(history.recommendation["rule"], "foundation", "empty history recommends a foundation exercise")
	assert_true("rule-based" in history.recommendation["method"] and "foundation" in history.recommendation_label.text, "recommendation explained")
	var expected: Dictionary = history.recommendation["config"]
	history.start_recommended()
	var briefing := await _wait_scene(AppState.SCENES["briefing"])
	assert_eq(AppState.selected_config, expected, "briefing uses the recommended config")
	assert_true(not briefing.start_button.disabled, "recommended exercise can start")
