extends "res://tests/test_case.gd"
## Pure flight-model checks. The drone is instantiated but not added to the tree,
## so only compute_velocity() and the telemetry helpers are exercised.

const DT := 1.0 / 60.0
const HUD := preload("res://scripts/ui/hud.gd")


func _drone() -> CharacterBody3D:
	return load("res://scenes/drone/drone.tscn").instantiate()


func _fly(drone: CharacterBody3D, move: Vector3, seconds: float, start := Vector3.ZERO, yaw := 0.0, altitude := 10.0) -> Vector3:
	var velocity := start
	for i in int(round(seconds / DT)):
		velocity = drone.compute_velocity(velocity, move, yaw, altitude, DT)
	return velocity


func test_forward_accelerates_at_configured_rate_toward_north() -> void:
	var drone := _drone()
	var velocity := _fly(drone, Vector3(0, 0, 1), 0.5)
	assert_near(velocity.length(), drone.horizontal_acceleration * 0.5, 0.01, "speed after 0.5 s")
	assert_true(velocity.z < 0.0 and absf(velocity.x) < 0.001, "forward is -Z (north) at yaw 0")
	drone.free()


func test_speed_is_capped_including_diagonals() -> void:
	var drone := _drone()
	assert_near(_fly(drone, Vector3(0, 0, 1), 10.0).length(), drone.max_horizontal_speed, 0.001, "forward cap")
	assert_near(_fly(drone, Vector3(1, 0, 1), 10.0).length(), drone.max_horizontal_speed, 0.001, "diagonal cap")
	assert_near(_fly(drone, Vector3(5, 0, 0), 10.0).length(), drone.max_horizontal_speed, 0.001, "out-of-range input is clamped")
	drone.free()


func test_releasing_controls_brakes_to_hover() -> void:
	var drone := _drone()
	var velocity := _fly(drone, Vector3.ZERO, 1.0, Vector3(0, 0, -8))
	assert_near(velocity.length(), 0.0, 0.001, "8 m/s brakes to 0 within 1 s at 8 m/s²")
	drone.free()


func test_yaw_rotates_the_forward_direction() -> void:
	var drone := _drone()
	var velocity := _fly(drone, Vector3(0, 0, 1), 10.0, Vector3.ZERO, -PI / 2.0)
	assert_near(velocity.x, drone.max_horizontal_speed, 0.001, "heading east flies +X")
	drone.rotation.y = -PI / 2.0
	assert_near(drone.heading_degrees(), 90.0, 0.001, "yaw -90° reads as heading 090")
	drone.rotation.y = PI / 2.0
	assert_near(drone.heading_degrees(), 270.0, 0.001, "yaw +90° reads as heading 270")
	drone.free()


func test_vertical_limits_and_ceiling() -> void:
	var drone := _drone()
	assert_near(_fly(drone, Vector3(0, 1, 0), 5.0).y, drone.max_ascent_speed, 0.001, "climb rate cap")
	assert_near(_fly(drone, Vector3(0, -1, 0), 5.0).y, -drone.max_descent_speed, 0.001, "descent rate cap")
	var at_ceiling := _fly(drone, Vector3(0, 1, 0), 2.0, Vector3(0, 4, 0), 0.0, drone.max_altitude)
	assert_near(at_ceiling.y, 0.0, 0.001, "no climbing above max altitude")
	drone.free()


func test_hover_holds_altitude_but_settles_just_above_ground() -> void:
	var drone := _drone()
	assert_near(_fly(drone, Vector3.ZERO, 2.0, Vector3.ZERO, 0.0, 5.0).y, 0.0, 0.001, "hovers at 5 m")
	var near_ground := _fly(drone, Vector3.ZERO, 2.0, Vector3.ZERO, 0.0, drone.settle_altitude * 0.5)
	assert_near(near_ground.y, -drone.settle_speed, 0.001, "settles below settle altitude")
	var climbing := _fly(drone, Vector3(0, 1, 0), 2.0, Vector3.ZERO, 0.0, 0.0)
	assert_near(climbing.y, drone.max_ascent_speed, 0.001, "climb input overrides settling")
	drone.free()


func test_same_inputs_give_identical_results() -> void:
	var a := _drone()
	var b := _drone()
	var moves := [Vector3(0, 1, 1), Vector3(1, 0, 0.5), Vector3(-1, -1, 0), Vector3.ZERO]
	var va := Vector3.ZERO
	var vb := Vector3.ZERO
	for i in 240:
		va = a.compute_velocity(va, moves[i % moves.size()], 0.3, 10.0, DT)
		vb = b.compute_velocity(vb, moves[i % moves.size()], 0.3, 10.0, DT)
	assert_eq(va, vb, "deterministic velocity sequence")
	a.free()
	b.free()


func test_invalid_time_step_is_ignored() -> void:
	var drone := _drone()
	drone.velocity = Vector3(1, 2, 3)
	for delta in [0.0, -1.0, NAN, INF]:
		drone.step(Vector3(0, 0, 1), 1.0, delta)
	assert_eq(drone.velocity, Vector3(1, 2, 3), "velocity unchanged by invalid delta")
	assert_eq(drone.rotation.y, 0.0, "rotation unchanged by invalid delta")
	drone.free()


func test_hud_formats_telemetry_with_units() -> void:
	assert_eq(HUD.format_altitude(12.345), "12.3 m", "altitude")
	assert_eq(HUD.format_speed(4.0), "4.0 m/s", "speed")
	assert_eq(HUD.format_vertical_speed(-1.24), "-1.2 m/s", "vertical speed")
	assert_eq(HUD.format_vertical_speed(2.0), "+2.0 m/s", "climb shows a plus sign")
	assert_eq(HUD.format_heading(0.0), "000° N", "north")
	assert_eq(HUD.format_heading(45.0), "045° NE", "north-east")
	assert_eq(HUD.format_heading(359.7), "000° N", "wraps to north")
	assert_eq(HUD.format_heading(-90.0), "270° W", "negative wraps")
	assert_eq(HUD.format_time(75.4), "01:15.4", "minutes and seconds")
