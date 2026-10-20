extends "res://tests/test_case.gd"
## Sound cues: generated sounds, cooldowns, volume and mute, pause, scene changes,
## and a visual sign for every alarm. (Runs with the dummy audio driver headless:
## these tests check what plays and when, not how it sounds.)

const AppState := preload("res://scripts/app/app_state.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")
const SoundBank := preload("res://scripts/audio/sound_bank.gd")
const AudioCues := preload("res://scripts/audio/audio_cues.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const MissionState := preload("res://scripts/mission/mission_state.gd")


func _wait_scene(path: String) -> Node:
	for i in 10:
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene.scene_file_path == path:
			return tree.current_scene
	failures.append("scene did not change to " + path)
	return null


func _playing_players(node: Node) -> int:
	var count := int(node is AudioStreamPlayer and node.playing and not node.stream_paused)
	for child in node.get_children():
		count += _playing_players(child)
	return count


func test_every_cue_is_generated_short_and_loops_repeat() -> void:
	for cue in SoundBank.CUES:
		var stream := SoundBank.get_stream(cue)
		assert_true(stream != null and stream.data.size() > 100, "%s rendered" % cue)
		assert_true(stream.get_length() <= 1.0, "%s is short (%.2f s)" % [cue, stream.get_length()])
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s plays once" % cue)
	for loop in ["rotor", "wind"]:
		assert_eq(SoundBank.get_stream(loop).loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % loop)


func test_cooldown_stops_the_same_cue_repeating() -> void:
	var cues: Node = AudioCues.attach(add_node(Node.new()))
	await tree.process_frame
	assert_true(cues.play("contact_detected"), "first cue plays")
	assert_true(not cues.play("contact_detected"), "the same cue within its cooldown is skipped")
	assert_true(cues.play("decision_confirmed"), "a different cue still plays")
	assert_eq(cues.history, ["contact_detected", "decision_confirmed"], "only distinct cues started")
	assert_true(not cues.play("no_such_cue"), "unknown cue ignored")
	for i in 20:
		cues.play("ui_click")
		cues._last_played.erase("ui_click")
	assert_true(cues.get_child_count() <= AudioCues.POOL_SIZE, "a fixed pool of players, never one per cue")


func test_volume_and_mute_apply_and_the_game_still_runs_muted() -> void:
	SettingsStore.set_value("sfx_volume", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "effects at 0 % mutes the SFX bus")
	SettingsStore.set_value("sfx_volume", 0.5)
	assert_near(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), 0.5, 0.001, "effects volume applied")
	SettingsStore.set_value("muted", true)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "mute applied")
	var main := add_scene("res://scenes/flight/flight_training.tscn")
	await wait_physics_frames(3)
	Input.action_press("ascend")
	await wait_physics_frames(40)
	Input.action_release("ascend")
	assert_eq(main.mission.state.status, MissionState.Status.FLYING, "flying works while muted")
	assert_true("takeoff" in main.cues.history, "cues still issued (silently) while muted")
	SettingsStore.reset_to_defaults()


func test_flight_cues_follow_mission_events_and_pause_stops_the_motor() -> void:
	var main := add_scene("res://scenes/flight/flight_training.tscn")
	await wait_physics_frames(3)
	assert_true("mission_start" in main.cues.history, "mission start cue")
	var rotor: AudioStreamPlayer = main.cues.loops["rotor"]
	assert_true(rotor.playing, "rotor loop running")
	Input.action_press("ascend")
	await wait_physics_frames(40)
	Input.action_release("ascend")
	main.drone.global_position = main.mission.checkpoints[0].global_position + Vector3(0, 0, 3)
	await wait_physics_frames(2)
	main.drone.global_position = main.mission.checkpoints[0].global_position
	await wait_physics_frames(4)
	main._process(0.0)
	assert_true("takeoff" in main.cues.history and "checkpoint" in main.cues.history, "takeoff and checkpoint cues: %s" % str(main.cues.history))
	assert_true(rotor.pitch_scale > 0.8, "motor pitch rises in flight")
	main.set_paused(true)
	assert_true(rotor.stream_paused, "motor sound paused with the game")
	main.set_paused(false)
	assert_true(not rotor.stream_paused, "motor resumes")


func test_scene_change_leaves_no_sound_playing() -> void:
	AppState.goto(tree, "flight")
	var flight := await _wait_scene(AppState.SCENES["flight"])
	await wait_physics_frames(5)
	assert_true(_playing_players(tree.root) > 0, "flight has sound playing")
	AppState.goto(tree, "menu")
	await _wait_scene(AppState.SCENES["menu"])
	await tree.process_frame
	assert_true(not is_instance_valid(flight), "flight scene freed")
	assert_eq(_playing_players(tree.root), 0, "nothing left playing after returning to the menu")


func test_every_alarm_cue_has_a_visual_sign() -> void:
	for cue in AudioCues.CRITICAL_CUES:
		assert_true(SoundBank.CUES.has(cue), "%s exists" % cue)
		assert_true(not String(AudioCues.CRITICAL_CUES[cue]).is_empty(), "%s has a documented visual equivalent" % cue)
	# The incoming cue only plays in the same frame as the INCOMING banner.
	AppState.flight_mission = "village_hostile"
	var main := add_scene("res://scenes/flight/flight_training.tscn")
	await wait_physics_frames(3)
	main.mission.state.status = MissionState.Status.FLYING
	var checked := false
	var heard := 0
	for i in 60 * 30:
		main.drone.global_position = Vector3(-60, 14, -50)
		main.drone.velocity = Vector3.ZERO
		await tree.physics_frame
		# The scene's own _process plays the cue right after it updates the HUD;
		# the banner stays up while the warning lasts.
		if main.cues.history.count("incoming") > heard:
			assert_true(main.hud.has_alert("incoming"), "INCOMING banner shown with the sound")
			checked = true
			break
	assert_true(checked, "an incoming cue occurred")
	AppState.flight_mission = "basic_course"


func test_observation_cues_for_contacts_and_decisions() -> void:
	AppState.selected_config = ScenarioConfig.load_file("res://scenarios/01_single_rural_day.json")["config"]
	AppState.goto(tree, "observation")
	var scene := await _wait_scene(AppState.SCENES["observation"])
	assert_true(scene.cues.loops.has("wind"), "ambience loop")
	while scene.session.time_s() < 30.0:
		scene.session.step()
	scene._process(0.0)
	assert_true("contact_detected" in scene.cues.history, "new contact cue")
	assert_true(scene.hud.alerts_box.get_child_count() > 0 or scene.session.tracker.confirmed_tracks().size() > 0, "new contact also shown on screen")
	scene.cycle_track()
	scene.hud.confirm()
	assert_true("decision_confirmed" in scene.cues.history, "decision cue")
	scene.hud._busy_until_ms = 0
	scene.hud.highlight["respond"] = 4
	scene.hud.confirm()
	assert_true("confirm_needed" in scene.cues.history and scene.hud.confirm_row.visible, "alarm confirmation has a cue and a visible prompt")
