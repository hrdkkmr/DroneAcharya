extends RefCounted
## Test-only pilot. Each physics frame it presses/releases the same input actions a
## player uses (no teleporting), steering toward the next checkpoint, then landing.

const STEER_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right", "ascend", "descend", "yaw_left", "yaw_right",
]
const BRAKING := 6.0 ## m/s²; matches the drone's acceleration when reversing direction
const CRUISE_ALTITUDE_FOR_LANDING := 4.0

## Height kept on the way to the landing zone (raised for missions where 4 m would
## clip street furniture); descends only once above the zone.
var landing_cruise_altitude := CRUISE_ALTITUDE_FOR_LANDING


## Steers toward `target`. With `land` true it stops above the target and descends.
func steer(drone: CharacterBody3D, target: Vector3, land: bool) -> void:
	var offset := target - drone.global_position
	var local := drone.global_basis.inverse() * Vector3(offset.x, 0.0, offset.z)
	var forward_distance := -local.z
	var right_distance := local.x
	var horizontal_distance := Vector2(offset.x, offset.z).length()
	var bearing := atan2(right_distance, forward_distance)
	var forward_speed := -(drone.global_basis.inverse() * drone.velocity).z

	var turning := horizontal_distance > 2.0
	_press("yaw_right", turning and bearing > 0.08)
	_press("yaw_left", turning and bearing < -0.08)
	_press("move_right", right_distance > 0.3)
	_press("move_left", right_distance < -0.3)

	var aligned := absf(bearing) < 0.5
	if land:
		var stopping_distance := forward_speed * forward_speed / (2.0 * BRAKING) + 0.3
		_press("move_forward", aligned and forward_distance > stopping_distance)
		_press("move_back", forward_distance < -0.3 or (forward_distance < stopping_distance and forward_speed > 0.3))
	else:
		_press("move_forward", aligned)
		_press("move_back", false)

	var target_altitude := target.y
	if land:
		target_altitude = landing_cruise_altitude if horizontal_distance > 1.5 else -1.0
	var climb := target_altitude - drone.global_position.y
	_press("ascend", climb > 0.3)
	_press("descend", climb < -0.3)


## Picks the next goal from the mission and steers toward it.
func fly_mission(drone: CharacterBody3D, mission: Node) -> void:
	var state = mission.state
	if state.next_checkpoint < mission.checkpoints.size():
		steer(drone, mission.checkpoints[state.next_checkpoint].global_position, false)
	else:
		steer(drone, mission.landing_zone.global_position, true)


func release_all() -> void:
	for action in STEER_ACTIONS:
		Input.action_release(action)


func _press(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
