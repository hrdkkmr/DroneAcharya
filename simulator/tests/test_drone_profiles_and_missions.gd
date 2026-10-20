extends "res://tests/test_case.gd"
## Drone profiles, mission limits (time, battery, integrity), the flight briefing and
## flight records.

const AppState := preload("res://scripts/app/app_state.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")
const DroneProfiles := preload("res://scripts/flight/drone_profiles.gd")
const FlightMissions := preload("res://scripts/flight/flight_missions.gd")
const FlightRecord := preload("res://scripts/flight/flight_record.gd")
const MissionState := preload("res://scripts/mission/mission_state.gd")
const DT := 1.0 / 60.0

## The Stage 1 tuning that Recon must keep.
const ORIGINAL := {
	"max_horizontal_speed": 8.0, "max_ascent_speed": 4.0, "max_descent_speed": 3.0, "max_yaw_rate_degrees": 90.0,
	"horizontal_acceleration": 6.0, "horizontal_braking": 8.0, "vertical_acceleration": 6.0, "crash_speed": 3.5,
	"follow_distance": 7.0, "follow_height": 3.0, "follow_smoothing": 5.0,
}


func _start_flight(profile: String, mission := "basic_course") -> Node:
	AppState.flight_profile = profile
	AppState.flight_mission = mission
	var main := add_scene("res://scenes/flight/flight_training.tscn")
	await wait_physics_frames(3)
	return main


func _teleport(drone: CharacterBody3D, position: Vector3) -> void:
	drone.global_position = position
	drone.velocity = Vector3.ZERO
	drone.reset_physics_interpolation()


func after_each() -> void:
	AppState.flight_profile = DroneProfiles.DEFAULT
	AppState.flight_mission = FlightMissions.DEFAULT


func test_every_profile_defines_every_value() -> void:
	var keys: Array = DroneProfiles.PROFILES["recon"].keys()
	for id in DroneProfiles.ORDER:
		for key in keys:
			assert_true(DroneProfiles.PROFILES[id].has(key), "%s defines %s" % [id, key])
	assert_eq(DroneProfiles.resolve_id("no-such-drone"), "recon", "unknown profile falls back to Recon")
	for key in ORIGINAL:
		assert_eq(DroneProfiles.get_profile("recon")[key], ORIGINAL[key], "Recon keeps the original %s" % key)


func test_default_scene_keeps_the_original_tuning() -> void:
	var main := await _start_flight("recon")
	for key in ORIGINAL:
		var holder: Object = main.camera_rig if key.begins_with("follow") else main.drone
		assert_eq(holder.get(key), ORIGINAL[key], "flight scene %s" % key)
	after_each()


## Pure velocity model: each profile reaches a different speed and climb rate in the
## same time, and stops in a different distance.
func test_profiles_produce_different_flight_behaviour() -> void:
	var main := await _start_flight("recon")
	var drone: CharacterBody3D = main.drone
	var results := {}
	for id in DroneProfiles.ORDER:
		drone.apply_profile(id, DroneProfiles.get_profile(id))
		var v := Vector3.ZERO
		for i in 60:
			v = drone.compute_velocity(v, Vector3(0, 1, 1), 0.0, 10.0, DT)
		var speed_1s := Vector2(v.x, v.z).length()
		var climb_1s := v.y
		for i in 600:
			v = drone.compute_velocity(v, Vector3(0, 0, 1), 0.0, 10.0, DT)
		var stop := 0.0
		for i in 600:
			v = drone.compute_velocity(v, Vector3.ZERO, 0.0, 10.0, DT)
			stop += Vector2(v.x, v.z).length() * DT
		results[id] = {"speed_1s": speed_1s, "climb_1s": climb_1s, "top": -v.z, "stop": stop}
	assert_true(results["scout"]["speed_1s"] > results["recon"]["speed_1s"] and results["recon"]["speed_1s"] > results["heavy"]["speed_1s"],
		"acceleration differs: %s" % str(results))
	assert_true(results["scout"]["climb_1s"] > results["recon"]["climb_1s"] and results["recon"]["climb_1s"] > results["heavy"]["climb_1s"], "climb differs")
	assert_true(results["heavy"]["stop"] > results["recon"]["stop"], "heavy needs longer to stop (%.1f vs %.1f m)" % [results["heavy"]["stop"], results["recon"]["stop"]])
	assert_near(results["recon"]["stop"], 4.0, 0.15, "Recon stops from 8 m/s in 4 m, as before")
	after_each()


func test_profile_changes_real_movement_in_the_scene() -> void:
	var distances := {}
	for id in ["scout", "heavy"]:
		var main := await _start_flight(id)
		var drone: CharacterBody3D = main.drone
		Input.action_press("ascend")
		await wait_physics_frames(60)
		Input.action_release("ascend")
		var start: Vector3 = drone.global_position
		Input.action_press("move_forward")
		await wait_physics_frames(90)
		Input.action_release("move_forward")
		distances[id] = start.distance_to(drone.global_position)
		assert_eq(drone.profile_id, id, "profile applied")
		main.queue_free()
		await tree.process_frame
	assert_true(distances["scout"] > distances["heavy"] * 1.5, "scout covers more ground than heavy in 1.5 s (%s)" % str(distances))
	after_each()


func test_reset_restores_the_selected_profile_and_state() -> void:
	var main := await _start_flight("heavy")
	var drone: CharacterBody3D = main.drone
	drone.max_horizontal_speed = 99.0
	main.camera_rig.follow_distance = 1.0
	_teleport(drone, Vector3(5, 6, -20))
	main.mission.state.record_hit("test", 35.0)
	main.reset_mission()
	await wait_physics_frames(2)
	assert_eq(drone.max_horizontal_speed, 5.5, "heavy speed restored")
	assert_eq(main.camera_rig.follow_distance, 9.5, "heavy camera restored")
	assert_true(drone.global_position.distance_to(main.spawn_transform.origin) < 0.05, "back on the pad")
	assert_eq(main.mission.state.integrity, 100.0, "integrity restored")
	assert_eq(main.mission.state.battery_fraction(), 1.0, "battery recharged")
	assert_eq(main.mission.state.events.size(), 0, "event log cleared")
	after_each()


func test_time_limit_warns_then_fails() -> void:
	var state := MissionState.new(2, 40.0, 0.0)
	state.update(2.0, false, false, 3.0, DT)
	var messages := []
	while not state.is_finished():
		var text := state.update(5.0, false, false, 3.0, DT)
		if not text.is_empty():
			messages.append([state.elapsed_seconds, text])
	assert_eq(messages.size(), 2, "one warning and one failure: %s" % str(messages))
	assert_true(messages[0][1] == "30 seconds left" and absf(messages[0][0] - 10.0) < 0.05, "warning at 30 s left")
	assert_true(messages[1][1].begins_with("Mission failed: time limit reached"), "fails at the limit")
	assert_near(state.elapsed_seconds, 40.0, 0.02, "stopped at the limit")
	var stopped := state.elapsed_seconds
	state.update(5.0, false, false, 3.0, 1.0)
	assert_eq(state.elapsed_seconds, stopped, "clock stops after failure")
	assert_true(state.events.any(func(e): return e["type"] == "time_warning"), "warning logged")


func test_no_limit_means_no_warning() -> void:
	var state := MissionState.new(1)
	state.update(2.0, false, false, 3.0, DT)
	for i in 60 * 400:
		state.update(5.0, false, false, 3.0, DT)
	assert_eq(state.status, MissionState.Status.FLYING, "no limit, no battery: still flying after 400 s")
	assert_eq(state.time_remaining(), INF, "no time remaining value")


func test_battery_drains_faster_when_climbing_and_fails_when_empty() -> void:
	var level := MissionState.new(1, 0.0, 100.0)
	var climbing := MissionState.new(1, 0.0, 100.0)
	for i in 60 * 10:
		level.update(5.0, false, false, 3.0, DT, 0.0)
		climbing.update(5.0, false, false, 3.0, DT, 2.0)
	assert_near(level.battery_fraction(), 0.9, 0.002, "10 s level flight uses 10 %")
	assert_near(climbing.battery_fraction(), 0.85, 0.002, "10 s climbing uses 15 %")
	var landed := MissionState.new(1, 0.0, 100.0)
	landed.update(1.0, false, false, 0.0, DT)
	for i in 60 * 30:
		landed.update(0.0, true, false, 0.0, DT)
	assert_true(landed.battery_fraction() > 0.99, "no drain while resting on the ground")
	var messages := []
	while not level.is_finished():
		var text := level.update(5.0, false, false, 3.0, DT)
		if not text.is_empty():
			messages.append(text)
	assert_true(messages[0].begins_with("Battery low: 20%"), "low-battery warning: %s" % str(messages))
	assert_eq(level.failure_reason, "battery depleted", "empty battery fails the mission")


func test_simulated_hits_reduce_integrity_and_fail_on_the_third() -> void:
	var state := MissionState.new(1)
	state.update(2.0, false, false, 3.0, DT)
	assert_true(state.record_hit("projectile", 35.0).contains("Integrity 65%"), "first hit")
	state.record_hit("projectile", 35.0)
	assert_eq(state.status, MissionState.Status.FLYING, "two hits survivable")
	assert_true(state.record_hit("projectile", 35.0).begins_with("Mission failed"), "third hit fails")
	assert_eq(state.hit_count, 3, "hits counted")
	assert_eq(state.record_hit("projectile", 35.0), "", "no hits after the end")


func test_a_light_touch_is_a_counted_bump_not_a_crash() -> void:
	var main := await _start_flight("recon")
	var drone: CharacterBody3D = main.drone
	Input.action_press("ascend")
	await wait_physics_frames(20)
	Input.action_release("ascend")
	# PillarA spans x 0.5..2.5, z -39..-37. Drift into it at 2 m/s (below crash speed 3.5).
	_teleport(drone, Vector3(1.5, 5.0, -35.5))
	for i in 60:
		drone.velocity = Vector3(0, 0, -2.0)
		await tree.physics_frame
	assert_eq(main.mission.state.status, MissionState.Status.FLYING, "not a crash")
	assert_eq(main.mission.state.bump_count, 1, "one bump for one continuous contact")
	after_each()


func test_finished_mission_is_saved_as_a_versioned_flight_record() -> void:
	var dir: String = AppState.flight_sessions_dir
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	var main := await _start_flight("scout")
	var drone: CharacterBody3D = main.drone
	var mission: Node = main.mission
	Input.action_press("ascend")
	await wait_physics_frames(30)
	Input.action_release("ascend")
	for i in mission.checkpoints.size():
		_teleport(drone, mission.checkpoints[i].global_position + Vector3(0, 0, 3))
		await wait_physics_frames(2)
		_teleport(drone, mission.checkpoints[i].global_position)
		await wait_physics_frames(4)
	_teleport(drone, mission.landing_zone.global_position + Vector3(0, 0.2, 0))
	for i in 180:
		await tree.physics_frame
		if mission.state.is_finished():
			break
	await tree.process_frame
	assert_eq(mission.state.status, MissionState.Status.COMPLETED, "mission completed")
	assert_true(main.saved_path.begins_with(dir), "record saved: " + main.saved_path)
	var loaded := FlightRecord.load_file(main.saved_path)
	assert_true(loaded["ok"], "record reloads: %s" % loaded.get("error", ""))
	var r: Dictionary = loaded["record"]
	assert_eq([r["format"], int(r["format_version"])], ["droneacharya-flight-session", 1], "versioned format")
	assert_eq(r["profile"]["id"], "scout", "profile recorded")
	assert_eq(r["result"]["status"], "completed", "result")
	assert_eq(int(r["result"]["checkpoints_passed"]), 4, "checkpoints")
	assert_eq(r["result"]["checkpoint_times"].size(), 4, "a time for each checkpoint")
	assert_true(r["events"].any(func(e): return e["type"] == "completed"), "events recorded")
	assert_true(main.hud.overlay.visible and main.hud.overlay.buttons.has("report"), "result screen offers the report")
	var listed := FlightRecord.list_history(dir)
	assert_eq(listed["records"].size(), 1, "listed in history")
	after_each()


func test_flight_record_validation_rejects_bad_files() -> void:
	assert_true(not FlightRecord.validate([]).ok, "not an object")
	assert_true(not FlightRecord.validate({"format": "x"}).ok, "missing fields")
	var state := MissionState.new(1)
	var record := FlightRecord.build(state, FlightMissions.get_mission("basic_course"), "recon", DroneProfiles.get_profile("recon"), "t", "2026-10-20T00:00:00Z")
	assert_true(FlightRecord.validate(record).ok, "built record is valid")
	record["format_version"] = 99
	assert_true(not FlightRecord.validate(record).ok, "unknown version rejected")


func test_flight_briefing_chooses_mission_and_profile() -> void:
	AppState.goto(tree, "flight_briefing")
	var screen: Node = null
	for i in 10:
		await tree.process_frame
		if tree.current_scene and tree.current_scene.scene_file_path == AppState.SCENES["flight_briefing"]:
			screen = tree.current_scene
			break
	assert_true(screen != null, "briefing opened")
	for id in DroneProfiles.ORDER:
		assert_true(screen.profile_buttons.has(id), "profile %s offered" % id)
	screen.profile_buttons["heavy"].button_pressed = true
	assert_eq(screen.profile_id, "heavy", "heavy selected")
	assert_true("Heavy utility" in screen.briefing_label.text and "Time limit" in screen.briefing_label.text, "briefing describes the choice")
	assert_true("Space / C" in screen.briefing_label.text, "controls listed on the briefing")
	screen.start_mission()
	var flight: Node = null
	for i in 10:
		await tree.process_frame
		if tree.current_scene and tree.current_scene.scene_file_path == AppState.SCENES["flight"]:
			flight = tree.current_scene
			break
	assert_true(flight != null, "flight started")
	if flight:
		assert_eq(flight.drone.max_horizontal_speed, 5.5, "heavy profile applied")
		assert_eq(flight.mission.state.status, MissionState.Status.READY, "clock not started on arrival")
		assert_eq(flight.mission.state.elapsed_seconds, 0.0, "no time counted during the briefing")
	assert_eq(SettingsStore.get_value("drone_profile"), "heavy", "choice remembered")
	SettingsStore.reset_to_defaults()
	after_each()


func test_hud_shows_limit_and_time_warning_with_a_word() -> void:
	var main := await _start_flight("recon")
	var state = main.mission.state
	main._process(0.0)
	assert_true("limit 03:00" in main.hud.limit_value.text, "time limit shown: " + main.hud.limit_value.text)
	assert_true(not main.hud.has_alert("time"), "no warning at the start")
	state.status = MissionState.Status.FLYING
	state.elapsed_seconds = 160.0
	main._process(0.0)
	assert_true(main.hud.has_alert("time"), "time warning banner shown")
	var banner: Node = main.hud.alerts["time"]
	assert_true("TIME LOW" == (banner.get_child(0).get_node("Word") as Label).text, "warning has a word, not only a colour")
	after_each()
