extends CharacterBody3D
## Assisted ("position-hold") drone flight: the drone hovers when no key is held and
## accelerates toward a target velocity chosen by the pilot. This is a training
## approximation, not an aerodynamic flight model.

signal crashed(impact_speed: float, obstacle_name: String)

@export_group("Speed limits")
@export var max_horizontal_speed := 8.0 ## m/s
@export var max_ascent_speed := 4.0 ## m/s
@export var max_descent_speed := 3.0 ## m/s
@export var max_yaw_rate_degrees := 90.0 ## degrees per second
@export var max_altitude := 40.0 ## m above ground; climbing stops here
## Below this height, with no climb input, the drone settles onto the ground so that
## releasing the keys just above the ground still counts as landed.
@export var settle_altitude := 0.3 ## m
@export var settle_speed := 1.0 ## m/s

@export_group("Response")
@export var horizontal_acceleration := 6.0 ## m/s² while a direction key is held
@export var horizontal_braking := 8.0 ## m/s² when no direction key is held
@export var vertical_acceleration := 6.0 ## m/s²
@export var crash_speed := 3.5 ## m/s into an obstacle that counts as a crash
@export var max_visual_tilt_degrees := 18.0

## When false (after a crash or mission end) pilot input is ignored and the drone
## brakes and descends until it rests on the ground.
var controls_enabled := true

var _rotor_spin := 0.0

@onready var _visual: Node3D = get_node_or_null("Visual")


func _physics_process(delta: float) -> void:
	step(read_pilot_input(), read_yaw_input(), delta)


## Pilot input in the drone's own frame: x = right, y = up, z = forward. Each in [-1, 1].
func read_pilot_input() -> Vector3:
	return Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("descend", "ascend"),
		Input.get_axis("move_back", "move_forward"))


## Positive = turn right (clockwise seen from above).
func read_yaw_input() -> float:
	return Input.get_axis("yaw_left", "yaw_right")


## Advances the drone by one physics step. Public so tests can drive it directly.
func step(move: Vector3, yaw_input: float, delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	if not controls_enabled:
		move = Vector3(0.0, -1.0, 0.0)
		yaw_input = 0.0
	rotation.y -= deg_to_rad(max_yaw_rate_degrees) * clampf(yaw_input, -1.0, 1.0) * delta
	velocity = compute_velocity(velocity, move, rotation.y, altitude(), delta)
	var impact_velocity := velocity
	move_and_slide()
	_check_crash(impact_velocity)
	_update_visual(delta)


## Pure velocity update (no physics query), shared by gameplay and tests.
func compute_velocity(current: Vector3, move: Vector3, yaw: float, current_altitude: float, delta: float) -> Vector3:
	var local_move := Vector3(clampf(move.x, -1.0, 1.0), 0.0, -clampf(move.z, -1.0, 1.0)).limit_length(1.0)
	var desired_horizontal := local_move.rotated(Vector3.UP, yaw) * max_horizontal_speed
	var horizontal := Vector3(current.x, 0.0, current.z)
	var rate := horizontal_acceleration if local_move.length() > 0.01 else horizontal_braking
	horizontal = horizontal.move_toward(desired_horizontal, rate * delta)

	var lift := clampf(move.y, -1.0, 1.0)
	var desired_vertical := lift * (max_ascent_speed if lift > 0.0 else max_descent_speed)
	if current_altitude >= max_altitude and desired_vertical > 0.0:
		desired_vertical = 0.0
	elif lift == 0.0 and current_altitude < settle_altitude:
		desired_vertical = -settle_speed
	var vertical := move_toward(current.y, desired_vertical, vertical_acceleration * delta)
	return Vector3(horizontal.x, vertical, horizontal.z)


func reset_to(spawn: Transform3D) -> void:
	global_transform = spawn
	velocity = Vector3.ZERO
	controls_enabled = true
	if _visual:
		_visual.rotation = Vector3.ZERO
	reset_physics_interpolation()


## Height of the drone's base above the ground plane (the ground is at y = 0).
func altitude() -> float:
	return global_position.y


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func vertical_speed() -> float:
	return velocity.y


## Compass heading in degrees: 0 = north (-Z), 90 = east (+X), increasing clockwise.
func heading_degrees() -> float:
	return fposmod(-rad_to_deg(rotation.y), 360.0)


func _check_crash(impact_velocity: Vector3) -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var obstacle := collision.get_collider() as Node
		if obstacle == null or not obstacle.is_in_group("obstacle"):
			continue
		var impact_speed := -impact_velocity.dot(collision.get_normal())
		if impact_speed >= crash_speed and controls_enabled:
			controls_enabled = false
			crashed.emit(impact_speed, obstacle.name)
			return


## Tilts the body toward the direction of travel and spins the rotors. Visual only.
func _update_visual(delta: float) -> void:
	if _visual == null:
		return
	var local_velocity := global_basis.inverse() * velocity
	var tilt := deg_to_rad(max_visual_tilt_degrees) / max_horizontal_speed
	var target := Vector3(local_velocity.z * tilt, 0.0, -local_velocity.x * tilt)
	var blend := 1.0 - exp(-8.0 * delta)
	_visual.rotation.x = lerpf(_visual.rotation.x, target.x, blend)
	_visual.rotation.z = lerpf(_visual.rotation.z, target.z, blend)
	var airborne := not is_on_floor() or velocity.y > 0.0
	_rotor_spin = fmod(_rotor_spin + (40.0 if airborne else 8.0) * delta, TAU)
	var rotors := _visual.get_node_or_null("Rotors")
	if rotors == null:
		return
	for rotor in rotors.get_children():
		(rotor as Node3D).rotation.y = _rotor_spin
