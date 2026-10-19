extends "res://tests/test_case.gd"
## Integration tests on the real main scene with real physics frames.

const MissionState := preload("res://scripts/mission/mission_state.gd")
const Autopilot := preload("res://tests/tools/autopilot.gd")
const HUD := preload("res://scripts/ui/hud.gd")


func _start() -> Node:
	var main := add_scene("res://scenes/main.tscn")
	await wait_physics_frames(3)
	return main


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await wait_physics_frames(frames)
	Input.action_release(action)


## Moves the drone without physics travel (used to set up specific situations).
func _teleport(drone: CharacterBody3D, position: Vector3) -> void:
	drone.global_position = position
	drone.velocity = Vector3.ZERO
	drone.reset_physics_interpolation()


func test_components_initialize_on_the_launch_pad() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	var mission: Node = main.mission
	assert_true(drone != null and drone.is_in_group("drone"), "drone present")
	assert_true(mission.is_configured(), "mission configured")
	assert_eq(mission.checkpoints.size(), 4, "four checkpoints")
	assert_eq(mission.state.status, MissionState.Status.READY, "ready on pad")
	assert_near(drone.altitude(), 0.0, 0.05, "resting on the ground")
	assert_true(drone.is_on_floor(), "on floor")
	assert_true(main.camera_rig.follow_camera.current, "follow camera active")
	main._process(0.0)
	assert_eq(main.hud.status_value.text, "On launch pad", "HUD status")
	assert_true(main.hud.objective_value.text.contains("checkpoint 1 of 4"), "HUD objective")
	assert_eq(main.hud.altitude_value.text, HUD.format_altitude(drone.altitude()), "HUD altitude")


func test_rings_face_their_approach_and_onboard_camera_looks_down() -> void:
	var main := await _start()
	var previous: Vector3 = main.spawn_transform.origin
	for checkpoint in main.mission.checkpoints:
		var position: Vector3 = checkpoint.global_position
		var approach := Vector3(position.x - previous.x, 0.0, position.z - previous.z).normalized()
		var facing: Vector3 = -checkpoint.global_basis.z
		assert_true(facing.dot(approach) > 0.99, "%s faces its approach (dot %.3f)" % [checkpoint.name, facing.dot(approach)])
		previous = position
	var look: Vector3 = -main.drone.get_node("OnboardCamera").global_basis.z
	assert_true(look.y < -0.05 and look.z < -0.9, "onboard camera looks forward and slightly down %s" % look)


func test_controls_move_the_drone_and_hud_reports_actual_state() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	await _hold("ascend", 60)
	assert_true(drone.altitude() > 1.5, "climbed (altitude %.2f)" % drone.altitude())
	assert_eq(main.mission.state.status, MissionState.Status.FLYING, "mission flying after takeoff")
	var start_z := drone.global_position.z
	await _hold("move_forward", 60)
	assert_true(drone.global_position.z < start_z - 2.0, "moved north")
	assert_true(drone.horizontal_speed() > 3.0, "has ground speed")
	await _hold("yaw_right", 30)
	assert_near(drone.heading_degrees(), 45.0, 1.0, "0.5 s of yaw at 90°/s")
	main._process(0.0)
	var hud = main.hud
	assert_eq(hud.altitude_value.text, HUD.format_altitude(drone.altitude()), "HUD altitude matches drone")
	assert_eq(hud.speed_value.text, HUD.format_speed(drone.horizontal_speed()), "HUD speed matches drone")
	assert_eq(hud.vertical_value.text, HUD.format_vertical_speed(drone.vertical_speed()), "HUD vertical speed matches drone")
	assert_eq(hud.heading_value.text, HUD.format_heading(drone.heading_degrees()), "HUD heading matches drone")
	assert_eq(hud.status_value.text, "Flying", "HUD status")


func test_drone_cannot_descend_through_the_ground() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	await _hold("ascend", 45)
	await _hold("descend", 180)
	assert_true(drone.altitude() > -0.02, "not below ground (altitude %.3f)" % drone.altitude())
	assert_true(drone.is_on_floor(), "resting on the ground")
	_teleport(drone, Vector3(10, 0.2, 10))
	await wait_physics_frames(60)
	assert_true(drone.is_on_floor(), "keys released 0.2 m up: drone settles onto the ground")


func test_follow_camera_tracks_and_view_toggles() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	var rig = main.camera_rig
	await _hold("ascend", 60)
	await _hold("move_forward", 120)
	await wait_physics_frames(60)
	var camera: Camera3D = rig.follow_camera
	var distance := camera.global_position.distance_to(drone.global_position)
	assert_true(distance > 4.0 and distance < 12.0, "chase distance %.1f m" % distance)
	assert_true(camera.global_position.z > drone.global_position.z, "camera is behind a north-facing drone")
	var press := InputEventAction.new()
	press.action = "toggle_view"
	press.pressed = true
	Input.parse_input_event(press)
	await wait_physics_frames(2)
	assert_eq(rig.mode, rig.Mode.ONBOARD, "V switches to onboard view")
	assert_true(drone.get_node("OnboardCamera").current, "onboard camera is current")
	rig.toggle_mode()
	assert_true(camera.current, "toggle back to follow view")


func test_checkpoints_progress_in_order_and_landing_completes_the_mission() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	var mission: Node = main.mission
	var messages: Array[String] = []
	mission.message.connect(func(text: String) -> void: messages.append(text))
	_teleport(drone, mission.checkpoints[2].global_position)
	await wait_physics_frames(4)
	assert_eq(mission.state.next_checkpoint, 0, "out-of-order checkpoint does not count")
	assert_true(messages.size() > 0 and messages[-1].begins_with("Wrong checkpoint"), "wrong checkpoint explained")
	for i in mission.checkpoints.size():
		_teleport(drone, mission.checkpoints[i].global_position + Vector3(0, 0, 3))
		await wait_physics_frames(2)
		_teleport(drone, mission.checkpoints[i].global_position)
		await wait_physics_frames(4)
		assert_eq(mission.state.next_checkpoint, i + 1, "checkpoint %d registered" % (i + 1))
	assert_true(mission.objective_text().begins_with("Land"), "objective switches to landing")
	_teleport(drone, mission.landing_zone.global_position + Vector3(0, 2, 0))
	Input.action_press("descend")
	for i in 240:
		await tree.physics_frame
		if mission.state.is_finished():
			break
	Input.action_release("descend")
	assert_eq(mission.state.status, MissionState.Status.COMPLETED, "mission completed")
	assert_true(not drone.controls_enabled, "controls locked after completion")
	main._process(0.0)
	assert_true(main.hud.overlay.visible, "result overlay shown")
	assert_eq(main.hud.overlay_title.text, "Mission complete", "overlay title")


func test_reset_restores_the_starting_state() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	var mission: Node = main.mission
	var spawn: Transform3D = main.spawn_transform
	await _hold("ascend", 60)
	_teleport(drone, mission.checkpoints[0].global_position)
	await wait_physics_frames(4)
	await _hold("yaw_left", 20)
	assert_eq(mission.state.next_checkpoint, 1, "made progress before reset")
	var press := InputEventAction.new()
	press.action = "reset_mission"
	press.pressed = true
	Input.parse_input_event(press)
	await wait_physics_frames(2)
	assert_true(drone.global_position.distance_to(spawn.origin) < 0.05, "drone back on the pad")
	assert_near(drone.heading_degrees(), 0.0, 0.01, "heading restored")
	assert_eq(drone.velocity.length(), 0.0, "velocity cleared")
	assert_true(drone.controls_enabled, "controls enabled")
	assert_eq(mission.state.status, MissionState.Status.READY, "mission ready")
	assert_eq(mission.state.next_checkpoint, 0, "checkpoints reset")
	assert_eq(mission.state.elapsed_seconds, 0.0, "clock reset")


func test_hitting_an_obstacle_fails_the_mission_and_reset_recovers() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	var mission: Node = main.mission
	await _hold("ascend", 20)
	_teleport(drone, Vector3(1.5, 5.0, -31.0))
	drone.velocity = Vector3(0, 0, -8)
	await _hold("move_forward", 90)
	assert_eq(mission.state.status, MissionState.Status.FAILED, "crash fails the mission")
	assert_true(mission.state.failure_reason.contains("PillarA"), "reason names the obstacle: " + mission.state.failure_reason)
	main._process(0.0)
	assert_eq(main.hud.overlay_title.text, "Mission failed", "failure overlay")
	main.reset_mission()
	await wait_physics_frames(2)
	assert_eq(mission.state.status, MissionState.Status.READY, "reset after failure")
	assert_true(not main.hud.overlay.visible, "overlay hidden after reset")


func test_leaving_the_training_area_fails_the_mission() -> void:
	var main := await _start()
	await _hold("ascend", 40)
	_teleport(main.drone, Vector3(95, 5, 0))
	await wait_physics_frames(3)
	assert_eq(main.mission.state.status, MissionState.Status.FAILED, "out of bounds fails")
	assert_eq(main.mission.state.failure_reason, "left the training area", "reason")


func test_pause_freezes_the_simulation() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	await _hold("ascend", 40)
	main.set_paused(true)
	var position := drone.global_position
	var elapsed: float = main.mission.state.elapsed_seconds
	await _hold("move_forward", 30)
	assert_eq(drone.global_position, position, "drone frozen while paused")
	assert_eq(main.mission.state.elapsed_seconds, elapsed, "mission clock frozen while paused")
	main._process(0.0)
	assert_eq(main.hud.status_value.text, "Paused", "HUD shows paused")
	main.set_paused(false)
	await _hold("move_forward", 30)
	assert_true(drone.global_position.z < position.z, "moves again after resume")


func test_incomplete_scene_parts_stay_inactive_without_errors() -> void:
	var mission: Node = add_node(load("res://scripts/mission/mission.gd").new())
	var rig: Node = add_node(load("res://scripts/camera/camera_rig.gd").new())
	await wait_physics_frames(5)
	assert_true(not mission.is_configured(), "mission without course is inactive")
	assert_eq(mission.objective_text(), "Mission unavailable: course is incomplete", "explains why")
	assert_eq(mission.status_text(), "Unavailable", "status")
	rig.toggle_mode()
	rig.snap()


func test_autopilot_completes_the_mission_using_real_controls() -> void:
	var main := await _start()
	var drone: CharacterBody3D = main.drone
	var mission: Node = main.mission
	var pilot := Autopilot.new()
	for i in 60 * 120:
		pilot.fly_mission(drone, mission)
		await tree.physics_frame
		if mission.state.is_finished():
			break
	pilot.release_all()
	assert_eq(mission.state.status, MissionState.Status.COMPLETED,
			"autopilot finished: status %d, next checkpoint %d, reason '%s', position %s" % [
				mission.state.status, mission.state.next_checkpoint, mission.state.failure_reason, drone.global_position])
	print("     autopilot mission time: %.1f s" % mission.state.elapsed_seconds)
